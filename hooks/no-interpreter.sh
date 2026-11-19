#!/usr/bin/env bash
# no-interpreter.sh — PreToolUse (Bash) déclaré dans le frontmatter des agents feature-* et fix-* (ADR 0017).
# Refuse aux sous-agents un interpréteur avec du code inline (`python3 - <<EOF`, `python3 -c`, `perl -pi -e`,
# `node -e`…), l'exécution d'un script écrit pendant la session, et `awk -i inplace` : leurs écritures sont
# invisibles aux hooks *-restrict-writes.sh. Les scripts du pipeline (`python3 [-I] ~/.claude/scripts/…`)
# passent. Le détail de ce qui est reconnu : scripts/gauntlet/interpreter_check.py.
# L'orchestrateur n'est pas concerné (agent_type vide ou autre) : on voit ce qu'il fait.
set -u
input="$(cat)"
agent="$(jq -r '.agent_type // empty' <<<"$input")"
[[ "$agent" == feature-* || "$agent" == fix-* ]] || exit 0
[ "$(jq -r '.tool_name // empty' <<<"$input")" = Bash ] || exit 0

cwd="$(jq -r '.cwd // empty' <<<"$input")"
scratch="$(jq -r '.scratchpad_dir // empty' <<<"$input")"
GAUNTLET_ROOT="${PIPELINE_GAUNTLET_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts/gauntlet" && pwd)}"
why="$(jq -r '.tool_input.command // empty' <<<"$input" \
  | python3 -I "$GAUNTLET_ROOT/interpreter_check.py" "${cwd:-$PWD}" "$scratch" 2>&1)"
[ -n "$why" ] || exit 0

msg="$agent : interpréteur refusé — $why. Pour écrire un fichier : Edit ou MultiEdit (Write pour en créer un). Pour lire du JSON : jq. Pour une recherche : grep, rg, sed -n. Les scripts du pipeline (python3 -I ~/.claude/scripts/…) restent permis. Un refus se rapporte, il ne se contourne pas : s'il te manque un outil, arrête-toi et dis-le dans ton rapport final (ADR 0017)."
jq -n --arg r "$msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
