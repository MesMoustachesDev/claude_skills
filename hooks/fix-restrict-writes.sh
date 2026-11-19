#!/usr/bin/env bash
# fix-restrict-writes.sh — PreToolUse (Edit|Write|MultiEdit|NotebookEdit|Bash) déclaré dans le
# frontmatter des agents fix-*. Le reproducer écrit les tests, l'implementer écrit le code, jamais l'inverse.
#
#   fix-reproducer  : tests, manifestes (package.json, pubspec.yaml et ceux du langage : stack.sh), .claude/fixes/<nom>/ ;
#                     dans le code source, uniquement des lignes de log [DEBUG_ISSUE] (ajout ou retrait).
#   fix-implementer : tout le projet SAUF les tests et .claude/fixes/<nom>/ (repro.json est gelé) ; parmi les
#                     tests, les probes `zz_probe_*` seulement (copie d'un test gelé pour débugger, ADR 0001).
#   fix-reviewer    : .claude/fixes/<nom>/review.{md,json} seulement, ni test ni probe (ADR 0002 : `to_verify`).
#
# Bash : les fichiers que la commande écrit (redirection, sed -i, tee, cp…, cf.
# gauntlet/bash_write_targets.py) passent par la même zone, sauf ceux hors du projet (journaux dans
# /tmp). Les interpréteurs inline (python -c, heredoc python, perl -pi…) sont refusés aux sous-agents par
# un hook à part (ADR 0017) ; le gauntlet reste le filet en fin d'étape : only_tests_changed pour le
# reproducer, freeze_check pour l'implementer, no_probes pour un probe oublié.
set -u
input="$(cat)"
agent="$(jq -r '.agent_type // empty' <<<"$input")"
[[ "$agent" == fix-* ]] || exit 0

cwd="$(jq -r '.cwd // empty' <<<"$input")"
scratch="$(jq -r '.scratchpad_dir // empty' <<<"$input")"
tool="$(jq -r '.tool_name // empty' <<<"$input")"
GAUNTLET_ROOT="${PIPELINE_GAUNTLET_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts/gauntlet" && pwd)}"   # surcharge : tests du hook ; défaut : le gauntlet de ce checkout
via=""
[ "$tool" = Bash ] && via=" (écriture par Bash : même zone que Edit/Write ; un refus ne se contourne pas, il se rapporte)"
deny() {
  jq -n --arg r "$1$via" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}
# Contexte illisible : Edit/Write (et Serena) refusés ; Bash laissé passer (le gauntlet reste le filet).
ctx_deny() { [ "$tool" = Bash ] && exit 0; deny "$1"; }

# Serena (ADR 0018) : liste fermée d'outils. La lecture passe si le serveur de l'agent sert bien ce
# worktree ; un outil d'écriture va à la même zone qu'un Edit du fichier de relative_path ; tout autre
# outil Serena est refusé.
source "$GAUNTLET_ROOT/serena_guard.sh"
skind="$(serena_kind "$tool")"; served=""
if [ -n "$skind" ]; then
  [ "$skind" = other ] && deny "fix : outil Serena hors liste ($tool). Permis : $SERENA_READ_TOOLS. Un refus se rapporte, il ne se contourne pas."
  served="$(serena_served "${cwd:-$PWD}")"
  [ -n "$served" ] || deny "fix : Serena ne sert aucun worktree connu. Cherche les usages avec grep, et dis-le dans ton rapport."
  targets=""
  if [ "$skind" = write ]; then
    rp="$(jq -r '.tool_input.relative_path // empty' <<<"$input")"
    [ -n "$rp" ] || deny "fix : $tool sans relative_path."
    targets="$(serena_target "$served" "$rp")"
  fi
elif [ "$tool" = Bash ]; then
  targets="$(jq -r '.tool_input.command // empty' <<<"$input" | python3 "$GAUNTLET_ROOT/bash_write_targets.py" "${cwd:-$PWD}")"
else
  targets="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")"
fi
[ -n "$targets" ] || [ -n "$skind" ] || exit 0

source "${FIX_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts/fix" && pwd)/lib.sh}"
cd "$cwd" 2>/dev/null || { [ -n "$skind" ] && deny "fix : Serena, worktree illisible ($cwd)"; exit 0; }
name="$(current_fix)"
[ -n "$name" ] || ctx_deny "fix : fix courant inconnu (branche fix/<nom> ou .claude/fixes/.current)"
fix_context "$name" || { [ -n "$skind" ] && deny "fix : Serena, contexte du fix illisible"; exit 0; }
# Serena : le serveur de l'agent doit servir ce worktree (serena.sh which : cwd, sinon dernier prepare du repo).
if [ -n "$skind" ]; then
  [ "$served" = "$PROJECT_ROOT" ] || deny "fix : Serena sert $served, pas ton worktree ($PROJECT_ROOT). N'utilise pas Serena ici : grep pour les usages, et dis-le dans ton rapport."
  [ "$skind" = read ] && exit 0
fi

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
  in_serena_dir "$abs" && deny "fix : .serena/ est la config de Serena, réécrite par serena.sh à chaque démarrage ; personne n'y écrit (ADR 0018). Refusé : $file"
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
      deny "reproducer : tu n'écris que des tests, $fix_rel/, et les manifestes ($(manifest_label)) pour brancher un runner. Dans le code source, seulement des lignes de log contenant $DEBUG_MARKER (une ligne par log, via Edit ; leur retrait aussi). La correction est le travail de l'implementer. Refusé : $rel"
      ;;
    fix-implementer)
      is_probe_path "$rel" && return 0
      is_test_path "$rel" && deny "implementer : les tests sont GELÉS. Si un test te semble faux, arrête-toi et dis-le dans ton rapport final (fichier:ligne, ce qu'il attend, pourquoi c'est faux) — le reproducer tranchera. Pour débugger, copie-le en \`test/zz_probe_<nom>_test.dart\` (même dossier de test, nom en zz_probe_ pour les autres langages), lance-le par son chemin et efface-le dans la même commande. Refusé : $rel"
      in_fix_dir && deny "implementer : $fix_rel/ appartient au reproducer et à l'orchestrateur (repro.json est gelé). Refusé : $rel"
      ;;
    fix-reviewer)
      case "$rel" in "$fix_rel/review.md"|"$fix_rel/review.json") return 0 ;; esac
      deny "reviewer : lecture seule. Tu n'écris que $fix_rel/review.md et review.json, ni test ni probe : une critique que tu ne prouves pas en lisant le code ou en rejouant un test existant va dans review.json → to_verify, avec ce qu'il faudrait lancer. Refusé : $rel"
      ;;
  esac
  return 0
}

while IFS= read -r t; do [ -n "$t" ] && check "$t"; done <<<"$targets"
exit 0
