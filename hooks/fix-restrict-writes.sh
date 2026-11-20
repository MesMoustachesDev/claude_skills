#!/usr/bin/env bash
# fix-restrict-writes.sh — PreToolUse (Edit|Write|MultiEdit|NotebookEdit|Bash) déclaré dans le
# frontmatter des agents fix-*. Le reproducer écrit les tests, l'implementer écrit le code, jamais l'inverse.
#
#   fix-reproducer  : tests, manifestes (package.json, pubspec.yaml et ceux du langage : stack.sh), .claude/fixes/<nom>/
#                     sauf fix.json (l'état, écrit par fix.py : ADR 0003) ;
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
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hook_input
[[ "$agent" == fix-* ]] || exit 0
HOOK_NAME=fix-restrict-writes; HOOK_LABEL=fix
via=""
[ "$tool" = Bash ] && via=" (écriture par Bash : même zone que Edit/Write ; un refus ne se contourne pas, il se rapporte)"
HOOK_DENY_SUFFIX="$via"

hook_targets
[ -n "$targets" ] || [ -n "$skind" ] || exit 0

source "${FIX_LIB:-$HOOK_SCRIPTS/fix/lib.sh}"
# Le worktree du fix, pas le cwd : un sous-agent hérite du cwd de la session, qui peut être le checkout
# principal. Le fichier écrit, puis le cwd, puis le worktree cité dans le prompt de l'agent.
hook_run_root fix "$cwd" "${targets%%$'\n'*}" "$(hook_agent_transcript "$input")"
cd "$HOOK_ROOT" 2>/dev/null || { [ -n "$skind" ] && hook_deny "fix : Serena, worktree illisible ($cwd)"; exit 0; }
cwd="$HOOK_ROOT"
name="$HOOK_RUN"
[ -n "$name" ] || hook_ctx_deny "fix : fix courant inconnu (branche fix/<nom> ou .claude/fixes/.current)"
fix_context "$name" || { [ -n "$skind" ] && hook_deny "fix : Serena, contexte du fix illisible"; exit 0; }
# Serena : le serveur de l'agent doit servir ce worktree (serena.sh which : cwd, sinon dernier prepare du repo).
if [ -n "$skind" ]; then
  [ "$served" = "$PROJECT_ROOT" ] || hook_deny "fix : Serena sert $served, pas ton worktree ($PROJECT_ROOT). N'utilise pas Serena ici : grep pour les usages, et dis-le dans ton rapport."
  [ "$skind" = read ] && exit 0
fi

fix_rel="${FIX_DIR#$PROJECT_ROOT/}"
[ -d "$FIX_DIR" ] && RUN_DIR="$FIX_DIR"
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
  local file="$1"
  hook_check_common "$file" "fix : écriture hors du projet refusée ($file)" || return 0
  case "$agent" in
    fix-reproducer)
      [ "$rel" = "$fix_rel/fix.json" ] && hook_deny "reproducer : $fix_rel/fix.json ne s'écrit que par fix.py, celui de l'orchestrateur et des gates (ADR 0003). Le reste de $fix_rel/ est à toi. Refusé : $rel"
      in_fix_dir && return 0
      is_test_path "$rel" && return 0
      is_manifest_path "$rel" && return 0
      debug_only && return 0
      hook_deny "reproducer : tu n'écris que des tests, $fix_rel/, et les manifestes ($(manifest_label)) pour brancher un runner. Dans le code source, seulement des lignes de log contenant $DEBUG_MARKER (une ligne par log, via Edit ; leur retrait aussi). La correction est le travail de l'implementer. Refusé : $rel"
      ;;
    fix-implementer)
      is_probe_path "$rel" && return 0
      is_test_path "$rel" && hook_deny "implementer : les tests sont GELÉS. Si un test te semble faux, arrête-toi et dis-le dans ton rapport final (fichier:ligne, ce qu'il attend, pourquoi c'est faux) — le reproducer tranchera. Pour débugger, copie-le en \`test/zz_probe_<nom>_test.dart\` (même dossier de test, nom en zz_probe_ pour les autres langages), lance-le par son chemin et efface-le dans la même commande. Refusé : $rel"
      in_fix_dir && hook_deny "implementer : $fix_rel/ appartient au reproducer et à l'orchestrateur (repro.json est gelé). Refusé : $rel"
      ;;
    fix-reviewer)
      case "$rel" in "$fix_rel/review.md"|"$fix_rel/review.json") return 0 ;; esac
      hook_deny "reviewer : lecture seule. Tu n'écris que $fix_rel/review.md et review.json, ni test ni probe : une critique que tu ne prouves pas en lisant le code ou en rejouant un test existant va dans review.json → to_verify, avec ce qu'il faudrait lancer. Refusé : $rel"
      ;;
  esac
  return 0
}

while IFS= read -r t; do
  [ -n "$t" ] || continue
  check "$t"
  [ "${IN_ZONE:-0}" = 1 ] && hook_log_decision allow ""
done <<<"$targets"
exit 0
