#!/usr/bin/env bash
# Repro — les checks Android avec le VRAI Gradle, hors ligne (--offline), sur un projet jetable : settings.gradle.kts,
# un module Kotlin/JVM (kotlin("jvm"), JUnit 4), un test. Ce que test_android.sh simule, joué pour de vrai :
# compilation et ses erreurs (format du compilateur Kotlin), rapports JUnit XML, rouge contre un stub TODO().
# Ni lint ni ktlint ni Kover : un module JVM sans ces plugins, d'où format et coverage non applicables.
#
# Rien n'est téléchargé : il faut une distribution Gradle et le plugin Kotlin déjà dans ~/.gradle (GRADLE_TEST_DIST,
# GRADLE_TEST_KOTLIN pour en choisir d'autres). Sinon : SKIP.
source "$(dirname "$0")/fixture.sh"

DIST="${GRADLE_TEST_DIST:-$(ls -d "$HOME"/.gradle/wrapper/dists/gradle-8.13-bin/*/gradle-8.13/bin/gradle 2>/dev/null | head -1)}"
KOTLIN="${GRADLE_TEST_KOTLIN:-2.2.10}"
command -v java >/dev/null && [ -x "${DIST:-/nonexistent}" ] \
  && ls "$HOME/.gradle/caches/modules-2/files-2.1/org.jetbrains.kotlin/kotlin-gradle-plugin/$KOTLIN" >/dev/null 2>&1 \
  || { echo "SKIP: Gradle 8.13 et le plugin Kotlin $KOTLIN doivent être dans ~/.gradle (hors ligne, rien n'est téléchargé)"; exit 0; }

R="$TMP_ROOT/repo"; mk_repo "$R"
M=lib; P="$R/$M"; K="src/main/kotlin/x/data"; T="src/test/kotlin/x/data"
mkdir -p "$R/.claude/rules" "$P/$K" "$P/$T"
cat > "$R/.claude/rules/feature_pipeline.md" <<EOF
# test
\`\`\`ini
gradle = $DIST --offline
package_path = {name}
base_branch = develop
qa.platforms =
stub.include = src/main/**/data/*Impl.kt
\`\`\`
EOF
cat > "$R/settings.gradle.kts" <<'EOF'
rootProject.name = "jetable"
include(":lib")
EOF
printf 'org.gradle.daemon.idletimeout=60000\norg.gradle.jvmargs=-Xmx1g\n' > "$R/gradle.properties"
cat > "$P/build.gradle.kts" <<EOF
buildscript {
  repositories { google(); mavenCentral(); gradlePluginPortal() }
  dependencies { classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$KOTLIN") }
}
apply(plugin = "org.jetbrains.kotlin.jvm")
repositories { google(); mavenCentral() }
dependencies { "testImplementation"("junit:junit:4.13.2") }
EOF
printf 'build/\n.gradle/\n.kotlin/\n' > "$R/.gitignore"
printf 'package x.data\n\nclass AddImpl {\n    fun add(a: Int, b: Int): Int = TODO()\n}\n' > "$P/$K/AddImpl.kt"
printf 'package x.data\n\nimport org.junit.Assert.assertEquals\nimport org.junit.Test\n\nclass AddImplTest {\n    @Test\n    fun adds() {\n        assertEquals(3, AddImpl().add(1, 2))\n    }\n}\n' > "$P/$T/AddImplTest.kt"
commit "$R" base >/dev/null

run_c() { OUT="$(cd "$R" && GAUNTLET_MODE=create GAUNTLET_PACKAGE="$M" bash "$GAUNTLET" "$@" 2>&1)"; RC=$?; }

echo "contrats posés : stubs TODO(), suite rouge"
run_c stub_check lib; expect_rc 0 "stub_check : la fonction est un TODO()"
run_c analyze lib;    expect_rc 0 "analyze : le module compile (vrai kotlinc)"; expect_out "module JVM sans com.android.lint" "pas d'Android lint pour un module JVM"
run_c red_check lib;  expect_rc 0 "red_check : le test échoue contre le stub (NotImplementedError)"
run_c test_names lib; expect_file_has "$R/.claude/features/lib/tests.md" "- adds" "tests.md : le test JUnit par son nom"

echo "implémentation : suite verte"
printf 'package x.data\n\nclass AddImpl {\n    fun add(a: Int, b: Int): Int = a + b\n}\n' > "$P/$K/AddImpl.kt"
run_c test lib;     expect_rc 0 "test : vert"; expect_out "1 test(s), 0 échec(s)" "le rapport JUnit XML est lu"
run_c no_stubs lib; expect_rc 0 "no_stubs : plus de TODO()"
run_c format lib;   expect_rc 0 "format sans ktlint ni Spotless"; expect_out "[N/A]  format" "format non applicable"
run_c coverage lib; expect_rc 0 "coverage sans Kover ni JaCoCo"; expect_out "[N/A]  coverage" "coverage non applicable"

echo "erreur de compilation"
printf 'package x.data\n\nclass AddImpl {\n    fun add(a: Int, b: Int): Int = a + c\n}\n' > "$P/$K/AddImpl.kt"
run_c analyze lib; expect_rc 1 "analyze : la compilation échoue"
expect_out "$K/AddImpl.kt:4:" "l'erreur du compilateur, chemin relatif au module et ligne"

finish
