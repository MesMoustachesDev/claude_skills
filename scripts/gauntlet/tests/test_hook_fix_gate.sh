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

echo "hook-verdict : réservé au hook, valeurs bornées"
OUT="$(cd "$R" && python3 "$TESTS_DIR/../../fix/fix.py" hook-verdict crash green PASSED 0 2>&1)"; RC=$?
expect_rc 2 "hors hook (PIPELINE_GATE_HOOK absent) : refusé"
expect_out "réservé au hook" "le refus le dit"
OUT="$(cd "$R" && PIPELINE_GATE_HOOK=1 python3 "$TESTS_DIR/../../fix/fix.py" hook-verdict crash green DONE 0 2>&1)"; RC=$?
expect_rc 2 "statut hors liste : refusé"
OUT="$(cd "$R" && PIPELINE_GATE_HOOK=1 python3 "$TESTS_DIR/../../fix/fix.py" hook-verdict crash review PASSED 0 2>&1)"; RC=$?
expect_rc 2 "profil qui n'est pas un gate de fin d'agent (review : review-pass) : refusé"
OUT="$(st .stages.green.status)"
expect_out "absent" "rien n'est écrit"

echo "fix courant inconnu : aucune décision"
git -C "$R" checkout -q develop
echo '{}' > "$S"
gate fix-reviewer
expect_rc 0 "ni branche fix/ ni .current : exit 0"
expect_out "fix courant inconnu" "et il le dit"
OUT="$(st .stages)"
expect_out "absent" "fix.json non touché"

echo "bug 1 — cwd au checkout principal, fix dans son worktree"
git -C "$R" checkout -q develop
printf '.claude/worktrees/\n' > "$R/.gitignore"; commit "$R" ignore >/dev/null
W="$R/.claude/worktrees/fix-crash"
git -C "$R" branch -q -D fix/crash; git -C "$R" worktree add -q "$W" -b fix/crash
W="$(cd "$W" && pwd -P)"; WD="$W/.claude/fixes/crash"; mkdir -p "$WD"
echo '{"phase":"review"}' > "$WD/fix.json"; rm -f "$S"
T="$TMP_ROOT/session"; mkdir -p "$T/subagents"
printf '{"type":"user","message":{"role":"user","content":"Victor, revue du fix. Worktree : %s"}}\n' "$W" > "$T/subagents/agent-v1.jsonl"
OUT="$(jq -n --arg c "$R" --arg t "$T.jsonl" '{agent_type:"fix-reviewer", agent_id:"v1", cwd:$c, transcript_path:$t}' \
  | bash "$HOOKS/fix-gate.sh" 2>&1)"; RC=$?
expect_rc 2 "le gate se joue dans le worktree cité par le prompt (review.json absent → rouge)"
OUT="$(jq -r '.stages.review_report.status // "absent"' "$WD/fix.json")"
expect_out "RED" "stages.review_report écrit dans le fix.json du worktree"
[ -f "$S" ] && _fail "fix.json écrit dans le checkout principal" || _pass "checkout principal non touché"
expect_file_has "$WD/.gauntlet/hooks.jsonl" '"hook":"fix-gate"' "journal dans le dossier du fix du worktree"

finish
