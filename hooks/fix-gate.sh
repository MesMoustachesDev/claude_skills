#!/usr/bin/env bash
# fix-gate.sh — Stop (→ SubagentStop) déclaré dans le frontmatter des agents fix-*. L'agent ne peut
# pas rendre la main tant que le gate de son étape est rouge. Après max_attempts échecs, il sort et
# l'étape passe en FAILED : l'orchestrateur appelle le dev au lieu de tourner en rond.
#
# Profil selon l'agent et fix.json → phase :
#   fix-reproducer  phase repro → red ; phase arbitrate → repro_report (le test peut avoir été corrigé
#                   alors que l'implementer a déjà avancé : la rougeur n'est plus garantie)
#   fix-implementer green
#   fix-reviewer    review_report (format seulement ; le verdict est lu par l'orchestrateur)
#
# Sortie : exit 0 = peut s'arrêter ; exit 2 + stderr = continue, la raison est montrée à l'agent.
set -u
input="$(cat)"
agent="$(jq -r '.agent_type // empty' <<<"$input")"
cwd="$(jq -r '.cwd // empty' <<<"$input")"
[[ "$agent" == fix-* ]] || exit 0

source "$HOME/.claude/scripts/fix/lib.sh"
cd "$cwd" 2>/dev/null || exit 0
name="$(current_fix)"
[ -n "$name" ] || { echo "fix-gate : fix courant inconnu, gate ignoré" >&2; exit 0; }
fix_context "$name" || exit 0
[ -d "$FIX_DIR" ] || exit 0

case "$agent" in
  fix-reproducer)  [ "$(state_get .phase)" = arbitrate ] && profile=repro_report || profile=red ;;
  fix-implementer) profile=green ;;
  fix-reviewer)    profile=review_report ;;
  *) exit 0 ;;
esac

GAUNTLET="$HOME/.claude/scripts/fix_gauntlet.sh"
max="$(state_get .max_attempts)"; max="${max:-5}"
attempts="$(state_get ".attempts[\"$profile\"]")"; attempts="${attempts:-0}"

if "$GAUNTLET" "$profile" "$name" >/dev/null 2>&1; then
  state_set '.attempts[$p]=0 | .stages[$p]={status:"PASSED", at:(now|todate)}' --arg p "$profile"
  exit 0
fi

attempts=$((attempts+1))
log="$FIX_OUT/last_${profile}.log"
if [ "$attempts" -ge "$max" ]; then
  state_set '.attempts[$p]=$a | .stages[$p]={status:"FAILED", at:(now|todate)}' --arg p "$profile" --argjson a "$attempts"
  {
    echo "fix-gate : gate '$profile' toujours rouge après $attempts tentatives. Étape marquée FAILED."
    echo "Arrête-toi et rends un rapport : ce qui bloque, ce que tu as essayé, ce que tu recommandes."
  } >&2
  exit 0
fi

state_set '.attempts[$p]=$a | .stages[$p]={status:"RED", at:(now|todate)}' --arg p "$profile" --argjson a "$attempts"
{
  echo "GATE '$profile' ROUGE (tentative $attempts/$max) — tu ne peux pas t'arrêter tant que ce n'est pas vert."
  echo "Sortie (${log#$PROJECT_ROOT/}) :"
  echo "----------------------------------------------------------------"
  grep -vE '^\s*$' "$log" | tail -60
  echo "----------------------------------------------------------------"
  echo "Corrige, puis termine à nouveau : le gate se relancera automatiquement."
} >&2
exit 2
