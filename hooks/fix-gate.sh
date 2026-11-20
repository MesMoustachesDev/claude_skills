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
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hook_input
HOOK_NAME=fix-gate
[[ "$agent" == fix-* ]] || exit 0

source "$HOOK_SCRIPTS/fix/lib.sh"
# Le worktree du fix, pas le cwd hérité de la session : le cwd, puis le worktree cité dans le prompt.
hook_run_root fix "$cwd" "" "$(hook_agent_transcript "$input")"
cd "$HOOK_ROOT" 2>/dev/null || exit 0
name="$HOOK_RUN"
[ -n "$name" ] || { echo "fix-gate : fix courant inconnu, gate ignoré" >&2; exit 0; }
fix_context "$name" || exit 0
[ -d "$FIX_DIR" ] || exit 0

case "$agent" in
  fix-reproducer)  [ "$(state_get .phase)" = arbitrate ] && profile=repro_report || profile=red ;;
  fix-implementer) profile=green ;;
  fix-reviewer)    profile=review_report ;;
  *) exit 0 ;;
esac

max="$(state_get .max_attempts)"; max="${max:-5}"
attempts="$(state_get ".attempts[\"$profile\"]")"; attempts="${attempts:-0}"
# gate_set <statut> <tentatives> (appelé par gate_run) — fix.py hook-verdict : valeurs bornées, sous le verrou de
# statefile.py (fix.json.lock), le même que les commandes de l'orchestrateur.
gate_set() { python3 "$HOOK_SCRIPTS/fix/fix.py" hook-verdict "$name" "$profile" "$1" "$2" >/dev/null; }
GATE_DIR="$FIX_DIR"; GATE_OUT="$FIX_OUT"
gate_run "$HOOK_SCRIPTS/fix_gauntlet.sh" "$profile" "$name"
