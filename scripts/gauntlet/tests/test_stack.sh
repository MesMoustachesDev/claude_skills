#!/usr/bin/env bash
# stack.sh — le langage d'un chemin, et ses valeurs. Cas visé : une app Flutter avec du Kotlin natif dans
# android/, et un projet Android pur ; aucun des deux ne doit recevoir la doctrine ou les commandes de l'autre.
source "$(dirname "$0")/fixture.sh"
STACK="$TESTS_DIR/../../stack.sh"
export CLAUDE_STACKS_DIR="$TESTS_DIR/../../../stacks"
run_s() { OUT="$(bash "$STACK" "$@" 2>&1)"; RC=$?; }

F="$TMP_ROOT/flutter_app"; mk_repo "$F"
mkdir -p "$F/lib/src" "$F/android/app/src/main/kotlin" "$F/packages/login/lib"
touch "$F/pubspec.yaml" "$F/android/build.gradle" "$F/android/app/build.gradle" "$F/packages/login/pubspec.yaml"
A="$TMP_ROOT/android_app"; mk_repo "$A"
mkdir -p "$A/app/src/main/java/com/x" "$A/feature/login/src/test"
touch "$A/settings.gradle.kts" "$A/app/build.gradle.kts" "$A/feature/login/build.gradle.kts"
N="$TMP_ROOT/rien"; mk_repo "$N"

echo "détection par le marqueur le plus proche"
run_s detect "$F/lib/src"; expect_out "flutter" "lib/ d'une app Flutter : flutter"
run_s detect "$F/android/app/src/main/kotlin/Main.kt"; expect_out "android" "android/app d'une app Flutter : android"
run_s detect "$F/packages/login/lib/a.dart"; expect_out "flutter" "un package Flutter du monorepo : flutter"
run_s detect "$A/feature/login/src/test"; expect_out "android" "projet Android : android"
run_s detect "$N"; expect_rc 1 "aucun marqueur : exit 1"

echo "la config du projet force le langage et prime clé par clé"
mkdir -p "$A/.claude/rules"
printf '# cfg\n```ini\ngradle = ./gradlew --offline\n```\n' > "$A/.claude/rules/feature_pipeline.md"
run_s get test_cmd "$A/app"; expect_out "./gradlew --offline test" "{gradle} remplacé par la valeur du projet"
run_s get manifests "$A/app"; expect_out "gradle/libs.versions.toml" "clé absente du projet : stack.ini"
printf '# cfg\n```ini\nstack = flutter\nflutter = fvm flutter\n```\n' > "$A/.claude/rules/feature_pipeline.md"
run_s detect "$A/app"; expect_out "flutter" "stack = flutter force le langage"
run_s get test_cmd "$A/app"; expect_out "fvm flutter test" "commande de test du langage forcé"
printf '# cfg\n```ini\nstack = cobol\n```\n' > "$A/.claude/rules/feature_pipeline.md"
run_s detect "$A/app"; expect_rc 2 "langage inconnu dans la config : exit 2"

echo "dir, list"
run_s dir "$F/lib"; expect_out "stacks/flutter" "dir : le dossier du langage"
run_s list; expect_out "marqueurs : pubspec.yaml" "list : flutter et ses marqueurs"
expect_out "marqueurs : settings.gradle.kts" "list : android et ses marqueurs"

finish
