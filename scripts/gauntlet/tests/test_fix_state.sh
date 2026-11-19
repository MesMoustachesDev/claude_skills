#!/usr/bin/env bash
# Repro — fix.json écrit à la main par l'orchestrateur /fix : une douzaine d'Edit par fix (gabarit, phase,
# freeze_sha, loops.review += 1 compté par le modèle, history/ copié à la main) et stages.review = PASSED écrit par
# le modèle lui-même, contre l'ADR 0003. Point 6 du plan de refacto : chaque écriture passe par scripts/fix/fix.py,
# sous le verrou de statefile ; un verdict de gate ne s'écrit que par script. Un test par sous-commande
# (`after` : test_fix_after.sh).
source "$(dirname "$0")/fixture.sh"
FP="$TESTS_DIR/../../fix/fix.py"
R="$TMP_ROOT/repo"; mk_repo "$R"
mkdir -p "$R/src" "$R/test"; echo 'code' > "$R/src/app.sh"; echo 'old' > "$R/test/old_test.sh"
printf '.claude/fixes/*/fix.json\n.claude/fixes/*/.gauntlet/\n.claude/fixes/.current\n' > "$R/.gitignore"
BASE="$(commit "$R" init)"; git -C "$R" checkout -q -b fix/crash
D="$R/.claude/fixes/crash"; S="$D/fix.json"
fx() { OUT="$(cd "$R" && python3 "$FP" "$@" 2>&1)"; RC=$?; }
js() { jq -r "$1" "$S"; }
check() { [ "$(js "$1")" = "$2" ] && _pass "$3" || { OUT="$(cat "$S")"; _fail "$3 — $1 = $(js "$1"), attendu $2"; }; }

echo "init"
fx init crash "le panier plante" --base-branch nope
expect_rc 2 "branche de base inconnue : refusé"
fx init crash "le panier plante" --base-branch develop --graphify échec
expect_rc 0 "init"
check .base_sha "$BASE" "base_sha = HEAD"
check .phase repro "phase repro"
check .graphify failed "« échec » s'écrit failed"
check '.stages|length' 0 "stages vides"
[ "$(cat "$R/.claude/fixes/.current")" = crash ] && _pass ".current écrit" || _fail ".current écrit"
fx init crash "x" --base-branch develop
expect_rc 2 "init sur un fix existant : refusé (reprise)"

echo "agent"
fx agent crash reproducer a1b2c3
check .agents.reproducer a1b2c3 "agents.reproducer"
fx agent crash boss a1
expect_rc 2 "rôle inconnu : refusé"

echo "pass / skip : les verdicts de gate ne s'écrivent pas à la main"
for st in red green review; do
  fx pass crash "$st"; expect_rc 2 "pass $st refusé"
done
expect_out "ADR 0003" "le refus cite l'ADR"
fx skip crash review "flemme"; expect_rc 2 "skip review refusé"
check '.stages|length' 0 "aucun verdict écrit"

echo "gate"
fx gate crash plan maybe; expect_rc 2 "choix du plan hors liste : refusé"
(cd "$R" && python3 "$FP" ask crash "Valide le plan" >/dev/null)
fx gate crash plan alternative
check .human_gates.plan.choice alternative "human_gates.plan.choice"
check '.waiting // "vide"' vide "la question posée est effacée"
fx gate crash repro; expect_rc 2 "repro ne se pose pas par gate (freeze)"

echo "freeze"
echo 'new' > "$R/test/crash_test.sh"; echo 'probe' > "$R/test/zz_probe_crash_test.sh"
echo '{}' > "$D/repro.json"; echo '# diag' > "$D/diagnosis.md"; mkdir -p "$D/shots/red"; echo png > "$D/shots/red/a.png"
fx freeze crash "cart crashes"; expect_rc 2 "stages.red pas PASSED : refusé"
expect_out "stages.red" "le refus nomme le gate"
python3 "$TESTS_DIR/../../statefile.py" jq "$S" '.stages.red={status:"PASSED"}'   # ce qu'écrit fix-gate.sh
fx freeze crash "cart crashes"
expect_rc 0 "freeze"
SHA="$(git -C "$R" rev-parse HEAD)"
check .freeze_sha "$SHA" "freeze_sha = commit de gel"
check .human_gates.repro.sha "$SHA" "human_gates.repro"
check .phase impl "phase impl"
OUT="$(git -C "$R" show --name-only --format=%s HEAD)"
expect_out "test(crash): reproduce cart crashes (frozen)" "message de gel"
expect_out "test/crash_test.sh" "test gelé"
expect_out ".claude/fixes/crash/repro.json" "repro.json gelé"
expect_out ".claude/fixes/crash/shots/red/a.png" "captures red gelées"
expect_no_out "zz_probe_" "jamais un probe"
fx freeze crash "again"; expect_rc 2 "second freeze refusé (refreeze)"
rm "$R/test/zz_probe_crash_test.sh"

echo "phase"
fx phase crash review; expect_rc 2 "phase hors liste : refusé"
fx phase crash arbitrate; check .phase arbitrate "phase arbitrate"
fx phase crash impl

echo "arbitrate"
fx arbitrate crash close juste; expect_rc 2 "close sans arbitrage ouvert : refusé"
fx arbitrate crash open test/crash_test.sh "le test attend 3, la spec dit 2"
check .phase arbitrate "open : phase arbitrate"
check '.arbitrations[0].claim' "le test attend 3, la spec dit 2" "contestation tracée"
check .loops.arbitrate 1 "loops.arbitrate compté par le script"
fx arbitrate crash close corrige; expect_rc 2 "corrigé sans re-gel : refusé"
fx arbitrate crash close juste
check '.arbitrations[0].verdict' juste "verdict tracé"
check .phase impl "close : phase impl"
fx arbitrate crash open t a; fx arbitrate crash close juste
fx arbitrate crash open t b; expect_rc 3 "troisième arbitrage : plafond, exit 3"

echo "refreeze"
fx refreeze crash hygiene "rien"; expect_rc 2 "rien de modifié : refusé"
echo 'code fixed' > "$R/src/app.sh"; echo 'new2' > "$R/test/crash_test.sh"
fx refreeze crash interne "x"; expect_rc 2 "cause hors liste : refusé"
fx refreeze crash technique "await the pump"
expect_rc 0 "refreeze"
SHA="$(git -C "$R" rev-parse HEAD)"
check .freeze_sha "$SHA" "nouveau freeze_sha"
check '.refreezes[0].cause' technique "refreezes.cause"
OUT="$(git -C "$R" show --name-only --format=%s HEAD)"
expect_out "test(crash): await the pump (refrozen)" "message de re-gel"
expect_no_out "src/app.sh" "le code de Fanny n'est pas re-gelé"
[ -n "$(git -C "$R" status --porcelain src/app.sh)" ] && _pass "le code de Fanny reste en cours" || _fail "le code de Fanny reste en cours"

echo "deviation"
fx deviation crash "suggestion S1 retenue par le dev" src/app.sh src/other.sh
check '.plan_deviations[0].files|length' 2 "plan_deviations"

echo "review-pass"
rv() { printf '{"root_cause_addressed":"yes","plan_respected":"yes","critical":%s,"suggestions":[],"missing_tests":[],"to_verify":[],"debt":[{"file":"src/old.sh","line":4,"issue":"vieux bug"}]}\n' "$1" > "$D/review.json"; }
rv '[{"file":"src/app.sh","line":1,"rule":"r","summary":"null non géré"}]'
fx review-pass crash
expect_rc 1 "critique : rouge"
check '.stages.review // "vide"' vide "rouge : stages.review pas écrit"
check '.debt[0].issue' "vieux bug" "review.json → debt reporté"
fx review-pass crash
check '.debt|length' 1 "dette pas dupliquée"

echo "loop"
fx loop crash review
check .loops.review 1 "loops.review compté par le script"
[ -f "$D/history/review_1.json" ] && _pass "review.json archivé dans history/review_1.json" || _fail "history/review_1.json"
fx loop crash arbitrate; expect_rc 2 "arbitrate se compte à l'ouverture"
fx loop crash review; fx loop crash review; expect_rc 3 "troisième boucle : plafond, exit 3"

echo "accept"
fx accept crash green "x"; expect_rc 2 "seule la revue s'accepte"
fx accept crash review "risque connu, ticket à part"
check '.accepted[0].stage' review "accepted tracé"
OUT="$(jq -r '.critical[0].accepted' "$D/review.json")"; expect_out true "critique acceptée dans review.json"
fx review-pass crash
expect_rc 0 "acceptée : vert"
check .stages.review.status PASSED "stages.review = PASSED, écrit par review-pass"

echo "debt"
fx debt crash review src/x.sh "autre" --line 9
check '.debt[1].line' 9 "debt"

echo "set"
fx set crash suggestions.S1 '{"decision":"applied","note":"ok"}'
check .suggestions.S1.decision applied "suggestions.S1"
fx set crash suggestions.S2 '{"decision":"maybe"}'; expect_rc 2 "décision hors liste : refusée"
fx set crash watchdog_cron cron-42; check .watchdog_cron cron-42 "watchdog_cron"
fx set crash issue '{"status":"none"}'; check .issue.status none "issue"
fx set crash phase impl; expect_rc 2 "clé hors liste : refusée"
fx set crash stages.review '{"status":"PASSED"}'; expect_rc 2 "verdict par set : refusé"

echo "ask"
fx ask crash "Regarde les captures avant / après"; check .waiting "Regarde les captures avant / après" "waiting posé"
fx ask crash ""; check '.waiting // "vide"' vide "waiting effacé"

echo "recap"
echo '{"goal":"corriger le crash du panier","decided":["plan : garde null"]}' > "$TMP_ROOT/recap.json"
fx recap crash "$TMP_ROOT/recap.json"; check .recap.goal "corriger le crash du panier" "recap écrit"
check .recap.stage green "recap.stage = étape courante du fix (green jamais passé ici)"
echo '{"goal":"x","oops":1}' > "$TMP_ROOT/bad.json"
fx recap crash "$TMP_ROOT/bad.json"; expect_rc 2 "recap hors schéma : refusé"

echo "gate ui, pass evidence"
fx gate crash ui; check '.human_gates.ui.by' user "human_gates.ui"
(cd "$R" && python3 "$FP" ask crash "x" >/dev/null)
fx pass crash evidence
check .stages.evidence.status PASSED "stages.evidence"
check '.waiting // "vide"' vide "attente effacée à la fin"
[ ! -f "$R/.claude/fixes/.current" ] && _pass ".current retiré" || _fail ".current retiré"

echo "verrou : une commande ne perd pas ce que fix-gate.sh écrit en même temps"
for i in $(seq 1 10); do
  (cd "$R" && python3 "$FP" debt crash review "f$i.sh" "p$i" >/dev/null 2>&1) &
  python3 "$TESTS_DIR/../../statefile.py" jq "$S" --arg p "g$i" '.attempts[$p]=1' &
  wait
done
check '[.attempts | keys[] | select(startswith("g"))] | length' 10 "10 attempts du hook gardés"
check '.debt|length' 12 "10 dettes ajoutées"
finish
