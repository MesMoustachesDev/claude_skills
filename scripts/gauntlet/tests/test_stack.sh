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
printf '# cfg\n```ini\ngradle_run = ./run.sh --offline\n```\n' > "$A/.claude/rules/feature_pipeline.md"
run_s get test_cmd "$A/app"; expect_out "./run.sh --offline :@unitTest" "{gradle_run} remplacé par la valeur du projet"
run_s get manifests "$A/app"; expect_out "gradle/libs.versions.toml" "clé absente du projet : stack.ini"
printf '# cfg\n```ini\nstack = flutter\nflutter = fvm flutter\n```\n' > "$A/.claude/rules/feature_pipeline.md"
run_s detect "$A/app"; expect_out "flutter" "stack = flutter force le langage"
run_s get test_cmd "$A/app"; expect_out "fvm flutter test" "commande de test du langage forcé"
printf '# cfg\n```ini\nstack = cobol\n```\n' > "$A/.claude/rules/feature_pipeline.md"
run_s detect "$A/app"; expect_rc 2 "langage inconnu dans la config : exit 2"

echo "vals, package, markers, chemins ~/"
rm -f "$A/.claude/rules/feature_pipeline.md"
run_s vals "$A/app" test_cmd nope src_dirs; OUT="$(printf '%s\n' "$OUT" | paste -sd '|' -)"
expect_out "stacks/android/gradle_run.sh :@unitTest||src/main" "vals : une ligne par clé, vide comprise, ~/ rendu absolu"
run_s package "$A/feature/login/src/test/X.kt"; expect_out "$(cd "$A/feature/login" && pwd -P)" "package : le dossier qui porte le marqueur"
run_s package "$F/android/app/src/main/kotlin/Main.kt"; expect_out "$(cd "$F/android/app" && pwd -P)" "package : android/app d'une app Flutter"
run_s package "$N"; expect_rc 1 "package : aucun marqueur, exit 1"
run_s markers; expect_out "pubspec.yaml" "markers : Flutter"; expect_out "build.gradle.kts" "markers : Android"
run_s get templates "$F/lib"; expect_out "$HOME/.claude/stacks/flutter/templates" "~/ rendu absolu"
printf '# cfg\n```ini\ngradle_run = ./run.sh --offline\n```\n' > "$TMP_ROOT/autre.md"
OUT="$(STACK_CFG="$TMP_ROOT/autre.md" bash "$STACK" get test_cmd "$A/app" 2>&1)"
expect_out "./run.sh --offline :@unitTest" "STACK_CFG : une autre config du projet (GAUNTLET_CFG, gabarit)"

echo "dir, list"
run_s dir "$F/lib"; expect_out "stacks/flutter" "dir : le dossier du langage"
run_s list; expect_out "marqueurs : pubspec.yaml" "list : flutter et ses marqueurs"
expect_out "marqueurs : settings.gradle.kts" "list : android et ses marqueurs"

finish
