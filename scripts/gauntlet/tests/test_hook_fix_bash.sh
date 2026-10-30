#!/usr/bin/env bash
# Repro — écritures par Bash dans /fix : même angle mort que le hook de /feature (Hugo, `sed -i` après
# un Edit refusé). fix-restrict-writes.sh ne regardait que Edit/Write.
#   implementer : sed -i ou redirection vers un test gelé ou vers .claude/fixes/<nom>/ : refusés ;
#     code source et journaux hors du projet : permis.
#   reproducer : tests et son dossier par Bash : permis ; code source par sed : refusé (logs via Edit).
#   reviewer : lecture seule, Bash compris.
source "$(dirname "$0")/fixture.sh"

HOOKS="$TESTS_DIR/../../../hooks"
export PIPELINE_GAUNTLET_ROOT="$TESTS_DIR/.."
export FIX_LIB="$TESTS_DIR/../../fix/lib.sh"
R="$TMP_ROOT/repo"; mkdir -p "$R"; git -C "$R" init -q -b develop
mkdir -p "$R/lib" "$R/test" "$R/.claude/fixes/crash"
echo "int a = 1;" > "$R/lib/a.dart"
echo "void main() {}" > "$R/test/a_test.dart"
echo '{}' > "$R/.claude/fixes/crash/repro.json"
git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -q -m init
git -C "$R" checkout -q -b fix/crash
R="$(cd "$R" && pwd -P)"

# hook <agent> <outil> <fichier ou commande> — sortie dans $OUT
hook() {
  local key=file_path; [ "$2" = Bash ] && key=command
  OUT="$(jq -n --arg a "$1" --arg c "$R" --arg t "$2" --arg k "$key" --arg v "$3" \
    '{agent_type:$a, cwd:$c, tool_name:$t, tool_input:{($k):$v}}' \
    | bash "$HOOKS/fix-restrict-writes.sh" 2>&1)"
}

echo "Fanny (fix-implementer)"
hook fix-implementer Edit "$R/test/a_test.dart"
expect_out "GELÉS" "Edit d'un test : refusé (comme avant)"
hook fix-implementer Bash "sed -i '' 's/a/b/' test/a_test.dart"
expect_out "écriture par Bash" "sed -i sur un test : refusé, et le refus dit que Bash suit la même zone"
hook fix-implementer Bash "echo '{}' > .claude/fixes/crash/repro.json"
expect_out "repro.json est gelé" "redirection vers repro.json : refusée"
hook fix-implementer Bash "sed -i '' 's/1/2/' lib/a.dart && fvm flutter test > /tmp/fix.log 2>&1; tail /tmp/fix.log"
expect_no_out deny "code source et journal dans /tmp : permis"

echo "Bastien (fix-reproducer)"
hook fix-reproducer Bash "cat > test/crash_test.dart <<'EOF2'
void main() {} // l'apostrophe
EOF2"
expect_no_out deny "heredoc vers un nouveau test : permis"
hook fix-reproducer Bash "fvm flutter test test/crash_test.dart | tee .claude/fixes/crash/red.log"
expect_no_out deny "tee vers son dossier de fix : permis"
hook fix-reproducer Bash "sed -i '' 's/1/2/' lib/a.dart"
expect_out "reproducer : tu n'écris que des tests" "sed -i dans le code source : refusé"

echo "Victor (fix-reviewer)"
hook fix-reviewer Bash "git diff develop -- lib | head -50"
expect_no_out deny "lecture par Bash : permis"
hook fix-reviewer Bash "cat > .claude/fixes/crash/review.json <<'EOF2'
{}
EOF2"
expect_no_out deny "heredoc vers review.json : permis"
hook fix-reviewer Bash "sed -i '' 's/1/2/' lib/a.dart"
expect_out "reviewer : lecture seule" "sed -i dans lib/ : refusé"

finish
