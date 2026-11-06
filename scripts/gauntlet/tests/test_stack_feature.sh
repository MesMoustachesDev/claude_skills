#!/usr/bin/env bash
# Repro — le gauntlet du /feature choisit les checks du langage du package (ADR 0011, plan langages point 4).
#   Un package Android (build.gradle.kts) à côté d'un package Flutter, dans le même repo :
#   - un check propre à Flutter (analyze) est dit « non applicable à android », compté à part, jamais « passé » ;
#   - les checks communs (no_secrets, todo_tickets) lisent les sources du langage (.kt), pas seulement .dart ;
#   - le hook pipeline-restrict-writes ouvre src/main et src/test du package Android, comme lib et test pour Flutter ;
#   - stacklib.py (pipeline.py, review.py, report.py) lit les mêmes valeurs que stack.sh ; pipeline.py prend les
#     fichiers de contrat du langage (contract_globs).
source "$(dirname "$0")/fixture.sh"

HOOK="$TESTS_DIR/../../../hooks/pipeline-restrict-writes.sh"
R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
F=app/features/feat
mk_pkg "$R/$F" feat
echo "int d() => 1;" > "$R/$F/lib/src/data/d.dart"
A=mods/login
mkdir -p "$R/$A/src/main/kotlin/x/data" "$R/$A/src/test/kotlin/x"
echo 'plugins { id("com.android.library") }' > "$R/$A/build.gradle.kts"
printf 'package x.data\nclass LoginRepository\n' > "$R/$A/src/main/kotlin/x/data/LoginRepository.kt"
commit "$R" "develop" >/dev/null

# run_pkg <package> <args…> — gauntlet hors pipeline sur <package>
run_pkg() { local p="$1"; shift; OUT="$(cd "$R" && GAUNTLET_MODE=create GAUNTLET_PACKAGE="$p" bash "$GAUNTLET" "$@" 2>&1)"; RC=$?; }

echo "un check propre à Flutter sur un package Android : non applicable, dit"
run_pkg "$A" analyze login
expect_rc 0 "analyze ne bloque pas un package Android"
expect_out "[N/A]  analyze : non applicable à android" "le check est dit non applicable à android"
expect_no_out "passés  : analyze" "il n'est pas compté passé"
OUT="$(jq -c '[.stack, .not_applicable, .passed]' "$R/.claude/features/login/.gauntlet/last_analyze.json")"
expect_out '["android",["analyze"],[]]' "last_analyze.json : stack android, analyze non applicable, rien de passé"
run_pkg "$F" analyze feat
expect_no_out "[N/A]" "contrôle : sur le package Flutter, analyze tourne"
run_pkg "$A" check_qui_nexiste_pas login
expect_rc 2 "un check inconnu de tous les langages reste refusé"

echo "checks communs : les sources du langage"
printf 'package x\nval apiKey = "abcdef123456"\n' > "$R/$A/src/main/kotlin/x/Config.kt"
run_pkg "$A" no_secrets login
expect_rc 1 "no_secrets : une clé en clair dans un .kt bloque"
expect_out "Config.kt" "le fichier Kotlin est nommé"
printf "final apiKey = 'abcdef123456';\n" > "$R/$F/lib/config.dart"
run_pkg "$F" no_secrets feat
expect_rc 1 "contrôle Flutter : une clé en clair dans un .dart bloque toujours"
printf 'package x\n// TODO brancher le cache\nfun f() = 1\n' > "$R/$A/src/test/kotlin/x/CacheTest.kt"
run_pkg "$A" todo_tickets login
expect_rc 1 "todo_tickets : un TODO sans ticket dans src/test d'un package Android bloque"
expect_out "CacheTest.kt" "le test Kotlin est nommé"

echo "hook — zones d'écriture d'un package Android"
git -C "$R" checkout -q -b feature/login
pipeline "$R" login "{\"mode\":\"create\",\"package\":\"$A\"}"
hook_write() {
  OUT="$(jq -n --arg a "$1" --arg c "$R" --arg f "$R/$2" \
    '{agent_type:$a, cwd:$c, tool_name:"Edit", tool_input:{file_path:$f}}' | bash "$HOOK" 2>&1)"
}
hook_write feature-test-writer "$A/src/test/kotlin/x/LoginTest.kt";        expect_no_out deny "test-writer : src/test du package"
hook_write feature-test-writer "$A/build.gradle.kts";                      expect_no_out deny "test-writer : son manifeste (dépendance de test)"
hook_write feature-test-writer "$A/src/main/kotlin/x/Login.kt";            expect_out deny "test-writer : refus src/main"
expect_out "$A/src/test/**" "le refus nomme la zone src/test"
hook_write feature-architect "$A/src/main/kotlin/x/Login.kt";              expect_no_out deny "architect : src/main"
hook_write feature-architect "$A/src/test/kotlin/x/LoginTest.kt";          expect_out deny "architect : refus des tests"
hook_write feature-implementer "$A/src/test/kotlin/x/LoginTest.kt";        expect_out "GELÉS" "implementer : tests gelés"
hook_write feature-implementer "$A/src/main/kotlin/x/Login.kt";            expect_no_out deny "implementer : src/main"
hook_write feature-implementer-data "$A/src/main/kotlin/x/data/Repo.kt";   expect_no_out deny "implementer data : sa couche (src/main/*/data)"
hook_write feature-implementer-data "$A/src/main/kotlin/x/ui/Screen.kt";   expect_out deny "implementer data : refus de l'ui"
hook_write feature-implementer-presentation "$A/src/main/kotlin/x/data/Repo.kt"; expect_out deny "implementer présentation : refus de la data"
hook_write feature-polisher "$A/src/main/kotlin/x/ui/Screen.kt";           expect_no_out deny "polisher : src/main/*/ui"
hook_write feature-test-writer "$F/test/a_test.dart";                      expect_out deny "contrôle : le package Flutter n'est pas celui de la feature"

echo "stacklib.py — les valeurs que lisent pipeline.py, review.py et report.py"
pyget() { OUT="$(python3 -c "import sys; sys.path.insert(0, '$TESTS_DIR/../..'); import stacklib; print($1)" 2>&1)"; }
pyget "stacklib.get_list('contract_globs', '$R/$A')";   expect_out "['*/domain/*']" "contrats Android"
pyget "stacklib.get_list('contract_globs', '$R/$F')";   expect_out "'*/keys.dart'" "contrats Flutter"
pyget "stacklib.get_list('test_dirs', '$R/$A')";        expect_out "['src/test', 'src/androidTest']" "dossiers de test Android"
pyget "stacklib.is_package('$R/$A'), stacklib.is_package('$R/$F'), stacklib.is_package('$R/app')"
expect_out "True True False" "is_package : build.gradle.kts et pubspec.yaml, pas app/"

echo "pipeline.py — fichiers de contrat du langage"
mkdir -p "$R/$A/src/main/kotlin/x/domain"
printf 'package x.domain
interface Login
' > "$R/$A/src/main/kotlin/x/domain/Login.kt"
OUT="$(cd "$R" && bash "$TESTS_DIR/../../pipeline.sh" contracts-files login 2>&1)"
expect_out "$A/src/main/kotlin/x/domain/Login.kt" "contracts-files : le domain Kotlin est un contrat"
expect_no_out "Config.kt" "un fichier hors domain n'en est pas un"

finish
