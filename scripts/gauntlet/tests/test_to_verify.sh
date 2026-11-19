#!/usr/bin/env bash
# Repro — relecteurs sans probe : une critique non prouvée part « à vérifier » (ADR 0002).
# Cas réels : Romain, Victor et Gaëlle écrivaient des tests probe pour vérifier une critique ; ils sont en lecture
# seule. Ce qu'ils ne prouvent pas en lisant ou en rejouant un test existant va dans `to_verify`, avec `how`.
#   gauntlet /feature : review_report valide to_verify ; review_verdict rouge tant qu'un to_verify d'Ivan n'a pas
#     d'outcome, ceux de Hugo ne bloquent pas ; tests_review_verdict rouge tant qu'un to_verify n'a pas d'outcome.
#   fix_gauntlet.sh : même règle pour Fanny et Bastien.
#   review.sh (/reviewPR) : severity to_verify exige how, compte à part, n'est jamais postée ni écrite dans
#     comments.md, même triée « commenter ».
source "$(dirname "$0")/fixture.sh"
need_fvm
SCRIPTS="$(cd "$TESTS_DIR/../.." && pwd)"

R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
P=app/features/feat
mk_pkg "$R/$P" feat
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/x
pipeline "$R" x "{\"mode\":\"create\",\"package\":\"$P\"}"
FD="$R/.claude/features/x"
TOUR='"tour":[{"layer":"vue","file":"lib/a","what":"a"},{"layer":"state","file":"lib/b","what":"b"}]'
review() { printf '{"critical":[],"suggestions":[],"missing_tests":[],%s,"to_verify":%s}\n' "$TOUR" "$1" > "$FD/review.json"; }

echo "/feature — review.json → to_verify"
review '[]'
run_g "$R" review_verdict x
expect_rc 0 "verdict vert sans to_verify"
review '[{"id":"V1","claim":"double tap = deux requêtes","file":"lib/a.dart","line":3,"how":"test du state holder : deux onSubmit","owner":"implementer"}]'
run_g "$R" review_report x
expect_rc 0 "report vert : to_verify complet"
expect_out "à vérifier : 1" "le report compte les à vérifier"
run_g "$R" review_verdict x
expect_rc 1 "verdict rouge : to_verify d'Ivan sans outcome"
expect_out "→ Ivan" "le verdict dit à qui il va"
expect_out "deux onSubmit" "le verdict donne ce qu'il faut lancer"
review '[{"id":"V1","claim":"double tap","how":"test","owner":"implementer","outcome":"dismissed","note":"garde isLoading, test rejoué vert"}]'
run_g "$R" review_verdict x
expect_rc 0 "verdict vert une fois l'outcome noté"
review '[{"id":"V1","claim":"le cas vide n'"'"'est pas prouvé","how":"test du mapper sur une liste vide","owner":"hardener"}]'
run_g "$R" review_verdict x
expect_rc 0 "to_verify de Hugo : ne bloque pas la revue"
expect_out "→ Hugo" "il est annoncé pour l'étape 7"
review '[{"id":"V1","claim":"double tap","owner":"implementer"}]'
run_g "$R" review_report x
expect_rc 1 "report rouge : how manquant"
expect_out "to_verify incomplet (V1)" "l'entrée fautive est nommée"
review '[{"id":"V1","claim":"x","how":"y","owner":"reviewer"}]'
run_g "$R" review_report x
expect_rc 1 "report rouge : owner inconnu"
review '[{"id":"V1","claim":"x","how":"y","owner":"implementer","outcome":"peut-être"}]'
run_g "$R" review_report x
expect_rc 1 "report rouge : outcome hors proved|dismissed"
printf '{"critical":[],"suggestions":[],"missing_tests":[],%s}\n' "$TOUR" > "$FD/review.json"
run_g "$R" review_verdict x
expect_rc 0 "review.json sans to_verify (ancien format) : vert"

echo "/feature — tests_review.json → to_verify (Gaëlle → Théo)"
tr() { printf '{"blocking":[],"notes":[],"coverage":{"a":"tested"},"to_verify":%s}\n' "$1" > "$FD/tests_review.json"; }
tr '[{"id":"V1","claim":"passe même si le use case n'"'"'est pas appelé","how":"rejouer avec le mock sans réponse","owner":"test-writer"}]'
run_g "$R" tests_review_verdict x
expect_rc 1 "verdict rouge : to_verify sans outcome"
expect_out "→ Théo" "il va au test-writer"
tr '[{"id":"V1","claim":"x","how":"y","owner":"test-writer","outcome":"proved"}]'
run_g "$R" tests_review_verdict x
expect_rc 0 "verdict vert avec outcome"
tr '[{"id":"V1","claim":"x","how":"y","owner":"implementer"}]'
run_g "$R" tests_review_report x
expect_rc 1 "report rouge : owner autre que test-writer"

echo "/fix — review.json → to_verify (Victor → Fanny ou Bastien)"
X="$TMP_ROOT/fix"; mkdir -p "$X/.claude/fixes/crash"; git -C "$X" init -q -b fix/crash
git -C "$X" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
echo '{}' > "$X/.claude/fixes/crash/fix.json"
fixrev() { printf '{"root_cause_addressed":"yes","plan_respected":"yes","critical":[],"suggestions":[],"missing_tests":[],"to_verify":%s}\n' "$1" > "$X/.claude/fixes/crash/review.json"; }
run_f() { OUT="$(cd "$X" && bash "$SCRIPTS/fix_gauntlet.sh" "$@" 2>&1)"; RC=$?; }
fixrev '[{"id":"V1","claim":"le test ne couvre pas le retour arrière","how":"test : pop puis push","owner":"reproducer"}]'
run_f review_report crash
expect_rc 0 "report vert"
run_f review_verdict crash
expect_rc 1 "verdict rouge : to_verify sans outcome"
expect_out "→ Bastien" "owner reproducer → Bastien"
fixrev '[{"id":"V1","claim":"x","how":"y","owner":"implementer","outcome":"proved"}]'
run_f review_verdict crash
expect_rc 0 "verdict vert avec outcome"
fixrev '[{"id":"V1","claim":"x","how":"y","owner":"hardener"}]'
run_f review_report crash
expect_rc 1 "report rouge : hardener n'existe pas dans /fix"

echo "/reviewPR — severity to_verify"
H="$TMP_ROOT/home"; D="$H/.cache/gauntlet/review/mr-1"; mkdir -p "$D"
printf '{"slug":"mr-1","key":"k","kind":"github","number":"1","project_root":"%s","remote":"origin","source":"feature/x","stages":{}}\n' "$R" > "$D/review.json"
cat > "$D/findings_code.json" <<'EOF'
{"role":"code","summary":"s","findings":[
 {"severity":"critical","title":"Crash sur liste vide","problem":"first sur une liste vide","evidence":"lib/a.dart:3"},
 {"severity":"to_verify","title":"Double requête au double tap","problem":"rien ne garde onSubmit","how":"test du state holder : deux onSubmit sans attendre"},
 {"severity":"to_verify","title":"Sans how","problem":"soupçon"}]}
EOF
run_rv() { OUT="$(cd "$R" && HOME="$H" bash "$SCRIPTS/review.sh" "$@" 2>&1)"; RC=$?; }
run_rv findings mr-1
expect_rc 0 "review.sh findings"
expect_out "1 à vérifier" "le compte sépare les à vérifier"
expect_out "Sans how" "un to_verify sans how est écarté et signalé"
FV="$(jq -r '.findings[] | select(.severity=="to_verify") | .id' "$D/findings.json")"
FC="$(jq -r '.findings[] | select(.severity=="critical") | .id' "$D/findings.json")"
OUT="$(jq -r '.findings[-1].severity' "$D/findings.json")"
expect_out "to_verify" "les à vérifier sont triées après les questions"
T="$TMP_ROOT/triage"; mkdir -p "$T"
for id in "$FV" "$FC"; do printf '{"id":"%s","decision":"comment","text":"texte %s"}\n' "$id" "$id" > "$T/$id.json"; done
run_rv triage-pull mr-1 "$T"
expect_rc 0 "triage-pull"
expect_out "À VÉRIFIER, non postées : $FV" "un à vérifier coché « commenter » est signalé non posté"
OUT="$(cat "$D/comments.md")"
expect_out "texte $FC" "comments.md : la critique y est"
expect_no_out "texte $FV" "comments.md : l'à vérifier n'y est pas"
run_rv post mr-1
expect_out "texte $FC" "post (aperçu) : la critique part"
expect_no_out "texte $FV" "post (aperçu) : l'à vérifier ne part jamais"

finish
