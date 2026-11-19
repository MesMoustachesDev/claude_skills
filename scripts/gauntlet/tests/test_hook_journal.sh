#!/usr/bin/env bash
# Repro — journal des décisions des hooks (ADR 0019). Avant, un refus n'était écrit nulle part : pour trouver
# les refus et les contournements des sous-agents, il a fallu fouiller les transcripts. Cas réel (anonymisé) :
# un implementer refusé sur un fichier gelé le recopie sous le même nom ailleurs, et l'y modifie (la zone refuse
# déjà la copie d'un test sous un nom de test ; le journal voit celle qui passe).
#   un refus écrit sa ligne dans <run>/.gauntlet/hooks.jsonl (no-interpreter, fix-restrict-writes,
#   review-restrict-writes) ; une écriture permise par la zone écrit « allow » ; sans contexte de fix, rien
#   n'est écrit et la décision est la même ; hook_journal.py compte et repère le contournement ;
#   learn.py extract en tire les signaux hook_bypass, hook_denied_repeat, gate_failed.
source "$(dirname "$0")/fixture.sh"

HOOKS="$TESTS_DIR/../../../hooks"
SCRIPTS="$TESTS_DIR/../.."
export PIPELINE_GAUNTLET_ROOT="$TESTS_DIR/.."
export FIX_LIB="$TESTS_DIR/../../fix/lib.sh"
export LEARN_HOME="$TMP_ROOT/lessons"
unset SERENA_PROJECT

mk_fix_repo() {   # mk_fix_repo <dossier> <branche>
  mk_repo "$1"; mkdir -p "$1/lib" "$1/test" "$1/.claude/fixes/crash"
  echo "int a = 1;" > "$1/lib/a.dart"; echo "void main() {}" > "$1/test/a_test.dart"
  echo '{}' > "$1/.claude/fixes/crash/repro.json"
  commit "$1" init >/dev/null; git -C "$1" checkout -q -b "$2"
}
R="$TMP_ROOT/repo"; mk_fix_repo "$R" fix/crash; R="$(cd "$R" && pwd -P)"
N="$TMP_ROOT/nofix"; mk_fix_repo "$N" develop-2; N="$(cd "$N" && pwd -P)"
J="$R/.claude/fixes/crash/.gauntlet/hooks.jsonl"

# hook <script> <agent> <outil> <entrée JSON de l'outil> [cwd] [transcript]
hook() {
  OUT="$(jq -n --arg a "$2" --arg c "${5:-$R}" --arg t "$3" --argjson i "$4" --arg tr "${6:-}" \
    '{agent_type:$a, cwd:$c, tool_name:$t, tool_input:$i, agent_transcript_path:$tr}' \
    | bash "$HOOKS/$1" 2>&1)"; RC=$?
}
cmd() { jq -n --arg c "$1" '{command:$c}'; }
fp() { jq -n --arg f "$1" '{file_path:$f}'; }
last() { OUT="$(tail -1 "$J" 2>/dev/null)"; }

echo "no-interpreter — le refus s'écrit"
hook no-interpreter.sh fix-implementer Bash "$(cmd "python3 - <<'EOF'
open('test/a_test.dart','w').write('x')
EOF")"
expect_out '"deny"' "refusé"
DECISION_CTX="$OUT"
last
expect_out '"hook":"no-interpreter"' "une ligne : hook"
expect_out '"agent":"fix-implementer"' "… agent"
expect_out '"outcome":"deny"' "… issue deny"
expect_out "code lu sur l'entrée standard" "… raison"
expect_out '"target":"python3 - <<' "… la commande, en cible"
expect_out '"at":"20' "… date"

echo "sans contexte de fix : rien n'est écrit, même décision"
hook no-interpreter.sh fix-implementer Bash "$(cmd "python3 - <<'EOF'
open('test/a_test.dart','w').write('x')
EOF")" "$N"
[ "$OUT" = "$DECISION_CTX" ] && _pass "décision identique avec et sans journal" || _fail "décision différente sans contexte"
[ -z "$(find "$N" -name hooks.jsonl)" ] && _pass "aucun hooks.jsonl écrit sans fix" || _fail "hooks.jsonl écrit sans fix"
hook fix-restrict-writes.sh fix-implementer Edit "$(fp "$N/test/a_test.dart")" "$N"
expect_out "fix courant inconnu" "fix-restrict-writes sans fix : refus de contexte inchangé"
[ -z "$(find "$N" -name hooks.jsonl)" ] && _pass "… et rien d'écrit" || _fail "hooks.jsonl écrit sans fix"

echo "fix-restrict-writes — refus, écritures permises, contournement"
hook fix-restrict-writes.sh fix-implementer Edit "$(fp "$R/test/a_test.dart")"
expect_out "GELÉS" "Edit du test gelé : refusé"
last; expect_out '"hook":"fix-restrict-writes"' "le refus s'écrit"
expect_out '"target":"test/a_test.dart"' "… cible relative au worktree"
hook fix-restrict-writes.sh fix-implementer Bash "$(cmd "cp test/a_test.dart lib/a_test.dart")"
expect_out "GELÉS" "copie du test gelé sous un nom de test dans lib/ : refusée par la zone (*_test)"
hook fix-restrict-writes.sh fix-implementer Edit "$(fp "$R/.claude/fixes/crash/repro.json")"
expect_out "repro.json est gelé" "Edit de repro.json : refusé"
hook fix-restrict-writes.sh fix-implementer Bash "$(cmd "cp .claude/fixes/crash/repro.json lib/repro.json && sed -i '' 's/a/b/' lib/repro.json")"
expect_no_out deny "copie de repro.json dans lib/ : permise par la zone"
last; expect_out '"outcome":"allow"' "l'écriture permise s'écrit (allow)"
expect_out '"target":"lib/repro.json"' "… avec son fichier"
expect_out "bash: cp .claude/fixes/crash/repro.json" "… et la commande"
hook fix-restrict-writes.sh fix-implementer Edit "$(fp "$R/test/a_test.dart")"
hook fix-restrict-writes.sh fix-implementer Bash "$(cmd "git status --short; fvm flutter test")"
last; expect_no_out "git status" "une commande sans écriture ne s'écrit pas"
OUT="$(grep -c '"outcome":"deny"' "$J")"; expect_out "5" "cinq refus au journal (interpréteur, deux Edit du test, cp, repro.json)"

echo "hook_journal.py — refus par agent et étape, contournement"
hook_log_gate() {   # une ligne de gate, comme pipeline-gate.sh / fix-gate.sh l'écrivent
  ( source "$TESTS_DIR/../hook_log.sh"; hook_log "$R/.claude/fixes/crash" fix-gate fix-implementer Stop "" "$1" "gate green rouge : suite" green )
}
hook_log_gate red; hook_log_gate failed
last; expect_out '"stage":"green"' "ligne de gate : étape (profil)"
OUT="$(python3 "$SCRIPTS/hook_journal.py" summary "$R/.claude/fixes/crash")"
expect_out "## Refus des hooks" "summary : section"
expect_out "| fix-implementer | 2 correction | 5 | 1 | 1 |" "summary : refus, gate rouge et FAILED de fix-implementer à l'étape 2, sur une ligne"
expect_out "\`.claude/fixes/crash/repro.json\` refusé par fix-restrict-writes (Edit), puis \`lib/repro.json\` écrit par Bash (copie)" "summary : le contournement par copie"
OUT="$(python3 "$SCRIPTS/hook_journal.py" summary "$N/.claude/fixes/crash")"
[ -z "$OUT" ] && _pass "summary sans journal : rien (section omise)" || _fail "summary sans journal non vide"

echo "learn.py extract — signaux du journal"
OUT="$(python3 "$SCRIPTS/learn.py" extract "$R/.claude/fixes/crash")"
expect_out '"kind": "hook_bypass"' "hook_bypass"
expect_out '"kind": "hook_denied_repeat"' "hook_denied_repeat (deux refus sur test/)"
expect_out '"kind": "gate_failed"' "gate_failed"
expect_out 'puis lib/repro.json écrit par Bash (copie)' "le texte du contournement"

echo "review-restrict-writes — dans le dossier de la revue"
RV="$HOME/.cache/gauntlet/review/zz-test-journal-$$"; mkdir -p "$RV"
T="$TMP_ROOT/t.jsonl"; printf '{"prompt":"Dossier de la revue : %s"}\n' "$RV" > "$T"
hook review-restrict-writes.sh review-code Edit "$(fp "$R/lib/a.dart")" "$R" "$T"
expect_rc 2 "review-code : Edit du code relu refusé"
OUT="$(tail -1 "$RV/.gauntlet/hooks.jsonl" 2>/dev/null)"
expect_out '"hook":"review-restrict-writes"' "le refus s'écrit dans le dossier de la revue"
hook review-restrict-writes.sh review-code Edit "$(fp "$R/lib/a.dart")" "$R" ""
expect_rc 2 "sans transcript : même refus"
rm -rf "${RV:?}"

finish
