#!/usr/bin/env bash
# state-guard.sh — PreToolUse (Edit|Write|MultiEdit|NotebookEdit|Bash) de settings.json : toutes les sessions,
# l'orchestrateur de /feature et de /fix compris, et leurs sous-agents.
# L'état d'un run ne s'écrit que par son script (ADR 0003) : .claude/features/<nom>/pipeline.json par
# pipeline.sh, .claude/fixes/<nom>/fix.json par fix.py, le verdict des gates par leur hook-verdict. Refuse Edit,
# Write, et une écriture par Bash (jq … >, tee, sed -i, cp, mv, rm : gauntlet/bash_write_targets.py) de ces
# deux fichiers. Les scripts y écrivent sans passer par un outil : ils ne sont pas concernés.
set -u
raw="$(cat)"
# Chemin rapide : ce hook voit chaque appel d'outil de chaque session.
case "$raw" in *pipeline.json*|*fix.json*) ;; *) exit 0 ;; esac
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hook_input <<<"$raw"
HOOK_NAME=state-guard

case "$tool" in
  Edit|Write|MultiEdit|NotebookEdit)
    targets="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")" ;;
  Bash)
    targets="$(jq -r '.tool_input.command // empty' <<<"$input" \
      | python3 "$GAUNTLET_ROOT/bash_write_targets.py" "${cwd:-$PWD}" 2>/dev/null)" ;;
  *) exit 0 ;;
esac

while IFS= read -r file; do
  [ -n "$file" ] || continue
  abs="$(hook_normalize "$file")"
  case "$abs" in
    */.claude/features/*/pipeline.json) script="~/.claude/scripts/pipeline.sh" ;;
    */.claude/fixes/*/fix.json)         script="python3 ~/.claude/scripts/fix/fix.py" ;;
    *) continue ;;
  esac
  # Journal (ADR 0019) dans le dossier du run, puisque c'est son état qu'on protège.
  [ -d "$(dirname "$abs")" ] && RUN_DIR="$(dirname "$abs")"
  LOG_TARGET="$abs"
  hook_deny "$(basename "$abs") ne s'écrit que par $script (ADR 0003), jamais par $tool. \
Passe par la commande du script qui fait ce changement ; s'il n'y en a pas, dis-le à Thibault au lieu d'écrire le fichier. Refusé : $abs" \
    "état du run écrit hors de son script"
done <<<"$targets"
exit 0
