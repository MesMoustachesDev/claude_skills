#!/usr/bin/env bash
# Repro — hooks/fix-gate.sh (Stop des agents fix-*) n'avait aucun test (plan de refacto, point 13).
#   Profil selon l'agent : reviewer → review_report ; reproducer → red, repro_report en phase arbitrate.
#   Gate rouge : exit 2, la sortie du gate montrée à l'agent, stages/attempts écrits dans fix.json, une ligne
#     « red » au journal des hooks. Vert : exit 0, PASSED, tentatives remises à 0. max_attempts atteint :
#     FAILED, exit 0 (l'agent sort et rapporte). Le marqueur « gate en cours » est effacé en sortant.
#   Hors fix-*, ou fix courant inconnu : aucune décision.
source "$(dirname "$0")/fixture.sh"

HOOKS="$TESTS_DIR/../../../hooks"
R="$TMP_ROOT/repo"; mk_repo "$R"
mkdir -p "$R/lib" "$R/test" "$R/.claude/fixes/crash"
echo "int a = 1;" > "$R/lib/a.dart"
commit "$R" init >/dev/null
git -C "$R" checkout -q -b fix/crash
R="$(cd "$R" && pwd -P)"
D="$R/.claude/fixes/crash"; S="$D/fix.json"

# gate <agent> [cwd] — sortie dans $OUT, code dans $RC
gate() {
  OUT="$(jq -n --arg a "$1" --arg c "${2:-$R}" '{agent_type:$a, cwd:$c, stop_hook_active:false}' \
    | bash "$HOOKS/fix-gate.sh" 2>&1)"; RC=$?
}
st() { jq -r "$1 // \"absent\"" "$S" 2>/dev/null; }

echo "hors fix-* : aucune décision"
gate feature-reviewer
expect_rc 0 "agent feature-* : exit 0"
[ -f "$S" ] && _fail "fix.json créé pour un agent hors fix" || _pass "fix.json non touché"

echo "Victor — review.json absent : rouge"
echo '{"phase":"review","max_attempts":5}' > "$S"
gate fix-reviewer
expect_rc 2 "gate rouge : l'agent est retenu"
expect_out "GATE 'review_report' ROUGE (tentative 1/5)" "le message nomme le profil et la tentative"
expect_out "review.json absent" "la sortie du gate est montrée à l'agent"
OUT="$(st .stages.review_report.status) $(st .attempts.review_report)"
expect_out "RED 1" "fix.json : stages.review_report = RED, attempts = 1"
expect_file_has "$D/.gauntlet/hooks.jsonl" '"hook":"fix-gate"' "journal des hooks : une ligne fix-gate"
expect_file_has "$D/.gauntlet/hooks.jsonl" '"outcome":"red"' "journal : issue red"
ls "$D/.gauntlet"/hook_*.running >/dev/null 2>&1 && _fail "marqueur hook_*.running resté" || _pass "marqueur « gate en cours » effacé"

echo "Victor — review.json valide : vert"
echo '{"critical":[],"suggestions":[],"missing_tests":[],"root_cause_addressed":"yes","plan_respected":"yes"}' > "$D/review.json"
gate fix-reviewer
expect_rc 0 "gate vert : l'agent peut s'arrêter"
OUT="$(st .stages.review_report.status) $(st .attempts.review_report)"
expect_out "PASSED 0" "fix.json : PASSED, tentatives remises à 0"
OUT="$(st .phase)"
expect_out "review" "le reste de fix.json est gardé"

echo "max_attempts atteint : FAILED, l'agent sort"
rm -f "$D/review.json"
jq '.max_attempts=2 | .attempts.review_report=1' "$S" > "$S.tmp" && mv "$S.tmp" "$S"
gate fix-reviewer
expect_rc 0 "FAILED : exit 0, l'agent rend son rapport"
expect_out "Étape marquée FAILED" "le message le dit"
OUT="$(st .stages.review_report.status) $(st .attempts.review_report)"
expect_out "FAILED 2" "fix.json : FAILED, attempts = 2"
expect_file_has "$D/.gauntlet/hooks.jsonl" '"outcome":"failed"' "journal : issue failed"

echo "Bastien — profil selon la phase"
echo '{"phase":"repro"}' > "$S"
gate fix-reproducer
OUT="$(st .stages.red.status)"
expect_out "RED" "phase repro : profil red"
echo '{"phase":"arbitrate"}' > "$S"
gate fix-reproducer
OUT="$(st .stages.repro_report.status) $(st .stages.red.status)"
expect_out "RED absent" "phase arbitrate : profil repro_report, stages.red non touché"

echo "fix courant inconnu : aucune décision"
git -C "$R" checkout -q develop
echo '{}' > "$S"
gate fix-reviewer
expect_rc 0 "ni branche fix/ ni .current : exit 0"
expect_out "fix courant inconnu" "et il le dit"
OUT="$(st .stages)"
expect_out "absent" "fix.json non touché"

finish
