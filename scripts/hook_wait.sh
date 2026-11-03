#!/usr/bin/env bash
# hook_wait.sh — attend qu'aucun hook de fin d'agent (pipeline-gate.sh, fix-gate.sh) ne joue de gate
# dans <dossier .gauntlet>.
#
# Le rapport final d'un agent en arrière-plan arrive à l'orchestrateur avant que son hook de fin ait
# joué le gate (70 s et plus pour red ou contracts). Lire l'étape à ce moment-là, c'est la trouver vide ;
# la rejouer, c'est deux gauntlets en même temps dans le même worktree. Le hook pose
# hook_<profil>.running (« <pid> <epoch> <agent> ») et l'efface en sortant ; ce script attend.
#
# Usage : hook_wait.sh <dossier .gauntlet> [secondes max, défaut 540]
# Exit 0 : plus aucun hook en cours. Exit 3 : toujours en cours après le délai (le nom est sur stderr).
# Sans effet dans un hook (PIPELINE_GATE_HOOK=1) : il n'attend pas après lui-même.
set -u
dir="${1:?usage: hook_wait.sh <dossier .gauntlet> [secondes]}"
max="${2:-540}"
[ "${PIPELINE_GATE_HOOK:-}" = 1 ] && exit 0
said=0 start="$(date +%s)"
while :; do
  busy=""
  for m in "$dir"/hook_*.running; do
    [ -f "$m" ] || continue
    read -r pid since agent < "$m"
    # Hook tué (timeout, session fermée) : son marqueur ne bloque plus rien.
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null && [ $(( $(date +%s) - ${since:-0} )) -lt 960 ]; then
      busy="$busy $(basename "$m" .running | sed 's/^hook_//') (${agent:-?})"
    else
      rm -f "$m"
    fi
  done
  [ -z "$busy" ] && exit 0
  if [ "$said" = 0 ]; then
    echo "hook de fin en cours :$busy — j'attends qu'il ait joué et écrit le gate" >&2
    said=1
  fi
  if [ $(( $(date +%s) - start )) -ge "$max" ]; then
    echo "hook de fin toujours en cours après ${max}s :$busy — attends la notification de fin de l'agent, puis relance" >&2
    exit 3
  fi
  sleep 2
done
