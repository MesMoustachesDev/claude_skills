#!/usr/bin/env bash
# no-interpreter.sh — PreToolUse (Bash) déclaré dans le frontmatter des agents feature-* et fix-* (ADR 0017).
# Refuse aux sous-agents un interpréteur avec du code inline (`python3 - <<EOF`, `python3 -c`, `perl -pi -e`,
# `node -e`…), l'exécution d'un script écrit pendant la session, et `awk -i inplace` : leurs écritures sont
# invisibles aux hooks *-restrict-writes.sh. Les scripts du pipeline (`python3 [-I] ~/.claude/scripts/…`)
# passent. Le détail de ce qui est reconnu : scripts/gauntlet/interpreter_check.py.
# L'orchestrateur n'est pas concerné (agent_type vide ou autre) : on voit ce qu'il fait.
set -u
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hook_input
[[ "$agent" == feature-* || "$agent" == fix-* ]] || exit 0
[ "$tool" = Bash ] || exit 0
HOOK_NAME=no-interpreter

why="$(jq -r '.tool_input.command // empty' <<<"$input" | python3 -I "$GAUNTLET_ROOT/interpreter_check.py" "${cwd:-$PWD}" "$scratch" 2>&1)"
[ -n "$why" ] || exit 0

# Journal (ADR 0019) : le refus s'écrit dans le dossier du run, s'il est connu ; la raison courte (why) au journal,
# le message complet à l'agent. La commande est la cible ; elle n'est pas répétée dans la raison.
LOG_TARGET="$log_cmd"; log_cmd=""
hook_deny "$agent : interpréteur refusé — $why. Pour écrire un fichier : Edit ou MultiEdit (Write pour en créer un). Pour lire du JSON : jq. Pour une recherche : grep, rg, sed -n. Les scripts du pipeline (python3 -I ~/.claude/scripts/…) restent permis. Un refus se rapporte, il ne se contourne pas : s'il te manque un outil, arrête-toi et dis-le dans ton rapport final (ADR 0017)." "$why"
