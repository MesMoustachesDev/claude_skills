#!/usr/bin/env bash
# fix-restrict-writes.sh — PreToolUse (Edit|Write|MultiEdit|NotebookEdit) déclaré dans le frontmatter
# des agents fix-*. Le reproducer écrit les tests, l'implementer écrit le code, jamais l'inverse.
#
#   fix-reproducer  : tests, manifestes (package.json / pubspec.yaml), .claude/fixes/<nom>/ ;
#                     dans le code source, uniquement des lignes de log [DEBUG_ISSUE] (ajout ou retrait).
#   fix-implementer : tout le projet SAUF les tests et .claude/fixes/<nom>/ (repro.json est gelé).
#   fix-reviewer    : .claude/fixes/<nom>/review.{md,json} seulement.
#
# Ce hook ferme le chemin facile. Le gauntlet ferme les autres (sed dans Bash…) :
# only_tests_changed pour le reproducer, freeze_check pour l'implementer.
set -u
input="$(cat)"
agent="$(jq -r '.agent_type // empty' <<<"$input")"
[[ "$agent" == fix-* ]] || exit 0

file="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")"
[ -n "$file" ] || exit 0
cwd="$(jq -r '.cwd // empty' <<<"$input")"
scratch="$(jq -r '.scratchpad_dir // empty' <<<"$input")"
tool="$(jq -r '.tool_name // empty' <<<"$input")"

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

source "$HOME/.claude/scripts/fix/lib.sh"
cd "$cwd" 2>/dev/null || exit 0
name="$(current_fix)"
[ -n "$name" ] || deny "fix : fix courant inconnu (branche fix/<nom> ou .claude/fixes/.current)"
fix_context "$name" || exit 0

normalize() {
  local p="$1" rest=""
  case "$p" in /*) ;; *) p="$cwd/$p" ;; esac
  while [ ! -d "$p" ] && [ "$p" != "/" ]; do rest="/$(basename "$p")$rest"; p="$(dirname "$p")"; done
  printf '%s%s' "$(cd "$p" && pwd -P)" "$rest"
}
abs="$(normalize "$file")"
[ -n "$scratch" ] && [[ "$abs" == "$scratch"/* ]] && exit 0
[[ "$abs" == "$PROJECT_ROOT"/* ]] || deny "fix : écriture hors du projet refusée ($file)"
rel="${abs#$PROJECT_ROOT/}"
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

case "$agent" in
  fix-reproducer)
    in_fix_dir && exit 0
    is_test_path "$rel" && exit 0
    is_manifest_path "$rel" && exit 0
    debug_only && exit 0
    deny "reproducer : tu n'écris que des tests, $fix_rel/, et package.json/pubspec.yaml pour brancher un runner. Dans le code source, seulement des lignes de log contenant $DEBUG_MARKER (une ligne par log, via Edit). La correction est le travail de l'implementer. Refusé : $rel"
    ;;
  fix-implementer)
    is_test_path "$rel" && deny "implementer : les tests sont GELÉS. Si un test te semble faux, arrête-toi et dis-le dans ton rapport final (fichier:ligne, ce qu'il attend, pourquoi c'est faux) — le reproducer tranchera. Refusé : $rel"
    in_fix_dir && deny "implementer : $fix_rel/ appartient au reproducer et à l'orchestrateur (repro.json est gelé). Refusé : $rel"
    ;;
  fix-reviewer)
    case "$rel" in "$fix_rel/review.md"|"$fix_rel/review.json") exit 0 ;; esac
    deny "reviewer : lecture seule. Tu n'écris que $fix_rel/review.md et review.json. Refusé : $rel"
    ;;
esac
exit 0
