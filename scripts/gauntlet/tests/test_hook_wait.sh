#!/usr/bin/env bash
# Repro — le rapport d'un agent en arrière-plan arrive avant que son hook de fin ait écrit le gate.
# Cas réel : library_sheet (projet-client), 2026-11-03 : rapport de Théo à 10:14:20, notification
# de fin à 10:15:36 (le hook jouait red_presentation, 77 s) ; l'orchestrateur a lu une étape vide et
# rejoué le gate en parallèle. Même chose deux fois pour Arthur (contracts).
#   le hook pose hook_<profil>.running pendant le gate et l'efface en sortant ;
#   gauntlet.sh et pipeline.sh next attendent ce marqueur au lieu de lire ou de rejouer trop tôt.
source "$(dirname "$0")/fixture.sh"
need_fvm

HOOKS="$TESTS_DIR/../../../hooks"
SCRIPTS="$TESTS_DIR/../.."
export PIPELINE_GAUNTLET_ROOT="$TESTS_DIR/.."
M="$TMP_ROOT/main"; mk_repo "$M"; write_cfg "$M"
P=app/features/feat
mk_pkg "$M/$P" feat
commit "$M" "develop" >/dev/null
git -C "$M" checkout -q -b feature/x
pipeline "$M" x "{\"mode\":\"create\",\"package\":\"$P\"}"
G="$M/.claude/features/x/.gauntlet"

echo "le hook efface son marqueur en sortant"
OUT="$(jq -n --arg c "$M" '{agent_type:"feature-dedup", cwd:$c}' | bash "$HOOKS/pipeline-gate.sh" 2>&1)"; RC=$?
expect_rc 2 "gate joué (dedup.json absent → rouge)"
OUT="$(ls "$G"/hook_*.running 2>/dev/null || echo aucun)"
expect_out "aucun" "plus de marqueur après le hook"

echo "un hook en cours retient gauntlet.sh et pipeline.sh next"
mkdir -p "$G"; sleep 30 & SP=$!
echo "$SP $(date +%s) feature-test-writer" > "$G/hook_red.running"
( sleep 3; kill "$SP" ) &
T0=$(date +%s)
OUT="$(cd "$M" && bash "$SCRIPTS/pipeline.sh" next x 2>&1)"; RC=$?
OUT="$OUT attendu=$(( $(date +%s) - T0 ))s"
expect_out "hook de fin en cours : red" "next annonce qu'il attend le hook"
expect_rc 0 "next répond une fois le hook fini"
OUT="$(ls "$G"/hook_*.running 2>/dev/null || echo aucun)"
expect_out "aucun" "marqueur d'un hook mort nettoyé"

finish
