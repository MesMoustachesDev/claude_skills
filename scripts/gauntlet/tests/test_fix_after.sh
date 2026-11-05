#!/usr/bin/env bash
# Repro — /fix : au rapport d'un agent, l'orchestrateur écrivait « j'attends la notification » et rendait la
# main. Cas réel : gate green de Fanny passé, rien n'a enchaîné sur Victor jusqu'au retour de Thibault.
#   fix_gauntlet.sh after <profil> <nom> attend le hook de fin, et l'agent renvoyé au travail sur gate rouge,
#   puis dit quoi faire ; exit 4 au bout du budget (relancer la même commande, dans le même tour).
source "$(dirname "$0")/fixture.sh"
FG="$TESTS_DIR/../../fix_gauntlet.sh"
R="$TMP_ROOT/repo"; mkdir -p "$R/.claude/fixes/crash/.gauntlet"; git -C "$R" init -q -b develop
echo x > "$R/a"; git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -q -m init
git -C "$R" checkout -q -b fix/crash
S="$R/.claude/fixes/crash/fix.json"; G="$R/.claude/fixes/crash/.gauntlet"
now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
put() { echo "{\"stages\":{\"green\":{\"status\":\"$1\",\"at\":\"$2\"}},\"attempts\":{\"green\":${3:-0}}}" > "$S"; }
run_a() { OUT="$(cd "$R" && bash "$FG" after green crash 2>&1)"; RC=$?; }

echo "le hook démarre après le rapport, écrit PASSED"
put RED 2026-11-04T10:00:00Z 1
( sleep 2; echo "$$ $(date +%s) fix-implementer" > "$G/hook_green.running"; sleep 2; put PASSED "$(now)"; rm -f "$G/hook_green.running" ) &
run_a; wait
expect_out "green = PASSED — lance l'étape suivante" "verdict vert lu après le hook : la suite (Victor) est lancée"
expect_rc 0 "exit 0"

echo "gate rouge : l'agent est renvoyé au travail, on attend son verdict suivant"
put RED "$(now)" 1
( sleep 4; echo "$$ $(date +%s) fix-implementer" > "$G/hook_green.running"; sleep 1; put PASSED "$(now)"; rm -f "$G/hook_green.running" ) &
run_a; wait
expect_out "agent au travail : green rouge" "rouge : attente annoncée, pas de fin de tour"
expect_out "green = PASSED" "puis le verdict vert est lu"

echo "rouge jusqu'au bout du budget : exit 4"
put RED "$(now)" 2
SECONDS=0; OUT="$(cd "$R" && FIX_WAIT_MAX=6 bash "$FG" after green crash 2>&1)"; RC=$?
expect_rc 4 "budget épuisé : exit 4"
expect_out "relance la même commande, dans ce tour" "consigne : relancer, pas rendre la main"
[ "$SECONDS" -le 15 ] && _pass "budget tenu ($SECONDS s)" || _fail "budget tenu ($SECONDS s)"

echo "FAILED : le dev décide"
put FAILED "$(now)" 5
run_a
expect_out "FAILED après 5 tentatives" "FAILED remonté au dev"

echo "aucun hook : rejouer le gate"
put RED 2026-11-04T10:00:00Z 1
SECONDS=0; OUT="$(cd "$R" && FIX_AFTER_WAIT=3 bash "$FG" after green crash 2>&1)"; RC=$?
expect_out "aucun hook de fin vu pour green" "rouge ancien sans hook : rejouer le gate, pas attendre"
finish
