#!/usr/bin/env bash
# fix-restrict-writes.sh — PreToolUse (Edit|Write|MultiEdit|NotebookEdit|Bash) déclaré dans le
# frontmatter des agents fix-*. Le reproducer écrit les tests, l'implementer écrit le code, jamais l'inverse.
#
#   fix-reproducer  : tests, manifestes (package.json / pubspec.yaml), .claude/fixes/<nom>/ ;
#                     dans le code source, uniquement des lignes de log [DEBUG_ISSUE] (ajout ou retrait).
#   fix-implementer : tout le projet SAUF les tests et .claude/fixes/<nom>/ (repro.json est gelé).
#   fix-reviewer    : .claude/fixes/<nom>/review.{md,json} seulement.
#
# Bash : les fichiers que la commande écrit (redirection, sed -i, tee, cp…, cf.
# gauntlet/bash_write_targets.py) passent par la même zone, sauf ceux hors du projet (journaux dans
# /tmp). Ce que l'extraction ne voit pas (python -c, scripts), le gauntlet le ferme :
# only_tests_changed pour le reproducer, freeze_check pour l'implementer.
set -u
input="$(cat)"
agent="$(jq -r '.agent_type // empty' <<<"$input")"
[[ "$agent" == fix-* ]] || exit 0

cwd="$(jq -r '.cwd // empty' <<<"$input")"
scratch="$(jq -r '.scratchpad_dir // empty' <<<"$input")"
tool="$(jq -r '.tool_name // empty' <<<"$input")"
GAUNTLET_ROOT="${PIPELINE_GAUNTLET_ROOT:-$HOME/.claude/scripts/gauntlet}"   # surcharge : tests du hook
if [ "$tool" = Bash ]; then
  targets="$(jq -r '.tool_input.command // empty' <<<"$input" | python3 "$GAUNTLET_ROOT/bash_write_targets.py" "${cwd:-$PWD}")"
else
  targets="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")"
fi
[ -n "$targets" ] || exit 0

via=""
[ "$tool" = Bash ] && via=" (écriture par Bash : même zone que Edit/Write ; un refus ne se contourne pas, il se rapporte)"
deny() {
  jq -n --arg r "$1$via" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}
# Contexte illisible : Edit/Write refusés ; Bash laissé passer (le gauntlet reste le filet).
ctx_deny() { [ "$tool" = Bash ] && exit 0; deny "$1"; }

source "${FIX_LIB:-$HOME/.claude/scripts/fix/lib.sh}"
cd "$cwd" 2>/dev/null || exit 0
name="$(current_fix)"
[ -n "$name" ] || ctx_deny "fix : fix courant inconnu (branche fix/<nom> ou .claude/fixes/.current)"
fix_context "$name" || exit 0

normalize() {
  local p="$1" rest=""
  case "$p" in /*) ;; *) p="$cwd/$p" ;; esac
  while [ ! -d "$p" ] && [ "$p" != "/" ]; do rest="/$(basename "$p")$rest"; p="$(dirname "$p")"; done
  printf '%s%s' "$(cd "$p" && pwd -P)" "$rest"
}
fix_rel="${FIX_DIR#$PROJECT_ROOT/}"
in_fix_dir() { [[ "$rel" == "$fix_rel"/* ]]; }

# debug_only — l'édition n'ajoute ou ne retire que des lignes contenant [DEBUG_ISSUE]
debug_only() {
  case "$tool" in
    Edit)      jq -e --arg m "$DEBUG_MARKER" '
                 def strip: split("\n") | map(select(contains($m) | not)) | join("\n");
                 (.tool_input.old_string | strip) == (.tool_input.new_string | strip)' <<<"$input" >/dev/null ;;
    MultiEdit) jq -e --arg m "$DEBUG_MARKER" '
                 def strip: split("\n") | map(select(contains($m) | not)) | join("\n");
                 all(.tool_input.edits[]; (.old_string | strip) == (.new_string | strip))' <<<"$input" >/dev/null ;;
    *) return 1 ;;
  esac
}

# check <fichier> — refuse (et sort) si le fichier est hors de la zone de l'agent ; sinon rend la main
check() {
  local file="$1" abs
  abs="$(normalize "$file")"
  [ -n "$scratch" ] && [[ "$abs" == "$scratch"/* ]] && return 0
  if [[ "$abs" != "$PROJECT_ROOT"/* ]]; then
    [ "$tool" = Bash ] && return 0                       # journaux, /tmp : hors du projet, libre
    deny "fix : écriture hors du projet refusée ($file)"
  fi
  rel="${abs#$PROJECT_ROOT/}"
  case "$agent" in
    fix-reproducer)
      in_fix_dir && return 0
      is_test_path "$rel" && return 0
      is_manifest_path "$rel" && return 0
      debug_only && return 0
      deny "reproducer : tu n'écris que des tests, $fix_rel/, et package.json/pubspec.yaml pour brancher un runner. Dans le code source, seulement des lignes de log contenant $DEBUG_MARKER (une ligne par log, via Edit ; leur retrait aussi). La correction est le travail de l'implementer. Refusé : $rel"
      ;;
    fix-implementer)
      is_test_path "$rel" && deny "implementer : les tests sont GELÉS. Si un test te semble faux, arrête-toi et dis-le dans ton rapport final (fichier:ligne, ce qu'il attend, pourquoi c'est faux) — le reproducer tranchera. Refusé : $rel"
      in_fix_dir && deny "implementer : $fix_rel/ appartient au reproducer et à l'orchestrateur (repro.json est gelé). Refusé : $rel"
      ;;
    fix-reviewer)
      case "$rel" in "$fix_rel/review.md"|"$fix_rel/review.json") return 0 ;; esac
      deny "reviewer : lecture seule. Tu n'écris que $fix_rel/review.md et review.json. Refusé : $rel"
      ;;
  esac
  return 0
}

while IFS= read -r t; do [ -n "$t" ] && check "$t"; done <<<"$targets"
exit 0
