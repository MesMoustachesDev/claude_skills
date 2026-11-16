#!/usr/bin/env bash
# Repro — le démon Gradle qui ne voit pas l'effacement des sorties (fake_gradle.sh, FAKE_GRADLE_STALE=1). Cas
# réel : une sous-feature Android, gate rejoué sans changement de code.
#   test : run_tests_json effaçait build/test-results puis lançait la tâche, jugée UP-TO-DATE → « aucun test
#     exécuté ». La tâche est rejouée (--rerun) : le deuxième passage voit ses tests.
#   analyze : lint_issues effaçait lint-results*.xml, lintReport UP-TO-DATE ne le réécrivait pas, et le [FAIL]
#     « aucun rapport » était avalé par issues="$(lint_issues)" → analyze [FAIL] sans raison. Le rapport à jour
#     est relu ; s'il a disparu, lint est relancé sans ses résultats partiels ; sans rapport du tout, le [FAIL]
#     dit pourquoi.
source "$(dirname "$0")/fixture.sh"
FAKE_GRADLE="$TESTS_DIR/fake_gradle.sh"

R="$TMP_ROOT/repo"; mk_repo "$R"
M=feature/login; P="$R/$M"; K="src/main/kotlin/com/x/login"; T="src/test/kotlin/com/x/login"
mkdir -p "$R/.claude/rules" "$P/$K/ui" "$P/$T/ui"
{
  echo '# test'; echo '```ini'
  echo "gradle = $FAKE_GRADLE"
  echo 'package_path = feature/{name}'
  echo 'features_root = feature'
  echo 'base_branch = develop'
  echo 'qa.platforms ='
  echo '```'
} > "$R/.claude/rules/feature_pipeline.md"
echo 'include(":feature:login")' > "$R/settings.gradle.kts"
printf 'plugins {\n  id("com.android.library")\n}\n' > "$P/build.gradle.kts"
printf 'package com.x.login.ui\n\nfun LoginScreen() {\n    val title = 1\n}\n' > "$P/$K/ui/LoginScreen.kt"
printf 'package com.x.login.ui\n\nclass LoginScreenTest {\n    fun works() = Unit\n}\n' > "$P/$T/ui/LoginScreenTest.kt"
commit "$R" base >/dev/null
git -C "$R" checkout -q -b feature/login
printf 'package com.x.login.ui\n\nfun LoginScreen() {\n    val title = 2\n}\n' > "$P/$K/ui/LoginScreen.kt"

run_s() { OUT="$(cd "$R" && FAKE_GRADLE_STALE=1 GAUNTLET_MODE=extend GAUNTLET_PACKAGE="$M" bash "$GAUNTLET" "$@" 2>&1)"; RC=$?; }

echo "test — rejoué deux fois, démon qui ne voit pas l'effacement"
run_s test login; expect_rc 0 "premier passage"
run_s test login; expect_rc 0 "deuxième passage : la tâche est rejouée"
expect_no_out "aucun test" "les tests sont vus"

echo "analyze — rejoué deux fois"
run_s analyze login; expect_rc 0 "premier passage"
run_s analyze login; expect_rc 0 "deuxième passage : le rapport à jour est relu"
expect_no_out "aucun rapport" "pas de rapport manquant"

echo "analyze — rapport effacé hors de la vue de Gradle"
rm -f "$P"/build/reports/lint-results*.xml
run_s analyze login; expect_rc 0 "lint relancé sans ses résultats partiels"
expect_out "lint relancé" "la relance est dite"

echo "analyze — lint ne produit aucun rapport"
rm -rf "$P/build"
OUT="$(cd "$R" && FAKE_GRADLE_NO_LINT_REPORT=1 GAUNTLET_MODE=extend GAUNTLET_PACKAGE="$M" bash "$GAUNTLET" analyze login 2>&1)"; RC=$?
expect_rc 1 "analyze rouge"
expect_out "n'a produit aucun rapport" "le [FAIL] dit pourquoi (pas avalé par la substitution)"
finish
