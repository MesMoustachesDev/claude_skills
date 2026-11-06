#!/usr/bin/env bash
# Repro — /fix prend les globs de test, les manifestes et les sources du langage du package (ADR 0011, plan
# langages point 5). Un package Android (build.gradle.kts) à côté d'un package Flutter, dans le même repo :
#   - fix/lib.sh : is_test_path et is_manifest_path ajoutent ceux du langage du package de repro.json (à défaut,
#     du package qui contient le chemin) aux génériques ;
#   - fix-restrict-writes.sh : le reproducer branche son runner dans les manifestes du langage ;
#   - fix_gauntlet.sh conventions : un .kt modifié est une source, jugée par les versions Android de
#     design_system et l10n_strings (plan langages point 6) ; le JSON du gate porte not_applicable.
source "$(dirname "$0")/fixture.sh"

FIX_LIB="$TESTS_DIR/../../fix/lib.sh"
FIX_G="$TESTS_DIR/../../fix_gauntlet.sh"
HOOK="$TESTS_DIR/../../../hooks/fix-restrict-writes.sh"
R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
F=app/feat; A=mods/login
mk_pkg "$R/$F" feat
echo "int a() => 1;" > "$R/$F/lib/a.dart"; echo "void main() {}" > "$R/$F/test/a_test.dart"
mkdir -p "$R/$A/src/main/kotlin/x" "$R/$A/src/test/kotlin/x" "$R/gradle"
echo 'plugins { id("com.android.library") }' > "$R/$A/build.gradle.kts"
printf 'package x\nfun login() = 1\n' > "$R/$A/src/main/kotlin/x/Login.kt"
echo '[versions]' > "$R/gradle/libs.versions.toml"
mkdir -p "$R/.claude/fixes/crash"
base="$(commit "$R" "develop")"
git -C "$R" checkout -q -b fix/crash
R="$(cd "$R" && pwd -P)"
printf '{"base_sha":"%s"}\n' "$base" > "$R/.claude/fixes/crash/fix.json"
repro() { printf '{"package":"%s"}\n' "$1" > "$R/.claude/fixes/crash/repro.json"; }

# classify <chemin…> — « chemin : test|manifeste|source » selon fix/lib.sh, dans $OUT
classify() {
  OUT="$(cd "$R" && bash -c 'source "$1"; shift; fix_context crash
    for p in "$@"; do
      if is_test_path "$p"; then k=test; elif is_manifest_path "$p"; then k=manifeste; else k=source; fi
      echo "$p : $k"
    done' _ "$FIX_LIB" "$@" 2>&1)"
}

echo "fix/lib.sh — repro.json sur le package Android"
repro "$A"
classify "$A/src/androidTest/kotlin/x/LoginUiTest.kt" "$A/src/test/kotlin/x/LoginTest.kt" "$A/src/main/kotlin/x/Login.kt" \
         "$A/build.gradle.kts" "gradle/libs.versions.toml" "$A/src/main/AndroidManifest.xml" "package.json"
expect_out "$A/src/androidTest/kotlin/x/LoginUiTest.kt : test" "src/androidTest : un test (glob du langage)"
expect_out "$A/src/test/kotlin/x/LoginTest.kt : test" "src/test : un test"
expect_out "$A/src/main/kotlin/x/Login.kt : source" "src/main : du code"
expect_out "$A/build.gradle.kts : manifeste" "build.gradle.kts du package : un manifeste"
expect_out "gradle/libs.versions.toml : manifeste" "libs.versions.toml : un manifeste"
expect_out "$A/src/main/AndroidManifest.xml : source" "AndroidManifest.xml n'est pas un manifeste de dépendances"
expect_out "package.json : manifeste" "les manifestes génériques restent"

echo "fix/lib.sh — repro.json sur le package Flutter (contrôle)"
repro "$F"
classify "$F/test/a_test.dart" "$F/lib/a.dart" "$F/pubspec.yaml" "gradle/libs.versions.toml"
expect_out "$F/test/a_test.dart : test" "test/ : un test"
expect_out "$F/lib/a.dart : source" "lib/ : du code"
expect_out "$F/pubspec.yaml : manifeste" "pubspec.yaml : un manifeste"
expect_out "gradle/libs.versions.toml : source" "les manifestes Gradle ne s'ouvrent pas pour un fix Flutter"

echo "fix/lib.sh — sans repro.json : le package qui contient le chemin"
rm -f "$R/.claude/fixes/crash/repro.json"
classify "$A/src/androidTest/kotlin/x/LoginUiTest.kt" "$A/build.gradle.kts"
expect_out "$A/src/androidTest/kotlin/x/LoginUiTest.kt : test" "src/androidTest reconnu avant repro.json"
expect_out "$A/build.gradle.kts : manifeste" "build.gradle.kts reconnu avant repro.json"

echo "fix-restrict-writes.sh — le reproducer branche son runner dans les manifestes du langage"
repro "$A"
hook_write() {
  OUT="$(jq -n --arg a "$1" --arg c "$R" --arg f "$R/$2" \
    '{agent_type:$a, cwd:$c, tool_name:"Write", tool_input:{file_path:$f}}' | bash "$HOOK" 2>&1)"
}
hook_write fix-reproducer "gradle/libs.versions.toml";                expect_no_out deny "reproducer : libs.versions.toml permis"
hook_write fix-reproducer "$A/src/androidTest/kotlin/x/UiTest.kt";    expect_no_out deny "reproducer : src/androidTest permis"
hook_write fix-reproducer "$A/src/main/kotlin/x/Login.kt";            expect_out deny "reproducer : le code source refusé"
expect_out "build.gradle.kts" "le refus nomme les manifestes du langage"
hook_write fix-implementer "$A/src/test/kotlin/x/LoginTest.kt";       expect_out "GELÉS" "implementer : les tests Kotlin sont gelés"

echo "fix_gauntlet.sh conventions — les sources du langage, versions Android"
printf 'package x\nfun login() = 2\n' > "$R/$A/src/main/kotlin/x/Login.kt"
echo '<manifest/>' > "$R/$A/src/main/AndroidManifest.xml"
OUT="$(cd "$R" && bash "$FIX_G" conventions crash 2>&1)"; RC=$?
expect_rc 0 "conventions : un fix Android sans présentation passe"
expect_out "$A : design_system conforme" "design_system tourne sur le package Android"
expect_out "$A : l10n_strings conforme" "l10n_strings tourne sur le package Android"
expect_out "non applicable (pas une source du langage de leur package) : $A/src/main/AndroidManifest.xml" \
  "un fichier qui n'est pas une source du langage est nommé"
expect_no_out "aucun fichier source" "le .kt modifié compte comme source"
OUT="$(jq -c '.not_applicable' "$R/.claude/fixes/crash/.gauntlet/last_conventions.json")"
expect_out '[]' "last_conventions.json porte not_applicable (vide ici)"
mkdir -p "$R/$A/src/main/kotlin/x/ui"
printf 'package x.ui\nfun LoginScreen() { Text("Bienvenue a bord") }\n' > "$R/$A/src/main/kotlin/x/ui/LoginScreen.kt"
OUT="$(cd "$R" && bash "$FIX_G" conventions crash 2>&1)"; RC=$?
expect_rc 1 "conventions : une chaîne en dur dans un écran Compose du fix bloque"
expect_out "LoginScreen.kt" "l'écran est nommé"
rm -rf "$R/$A/src/main/kotlin/x/ui"
echo "int a() => 2;" > "$R/$F/lib/a.dart"
OUT="$(cd "$R" && bash "$FIX_G" conventions crash 2>&1)"; RC=$?
expect_out "$F : design_system conforme" "contrôle Flutter : design_system tourne sur le .dart modifié"
expect_no_out "$F : design_system non applicable" "contrôle Flutter : jamais dit non applicable"

finish
