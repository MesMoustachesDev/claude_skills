#!/usr/bin/env bash
# checks.sh — les checks du gauntlet propres à Android natif (Kotlin, Gradle, Compose). Sourcé par gauntlet.sh
# (stack_load_checks) après les checks communs, quand le package est un module Gradle (scripts/stack.sh detect).
# Le package du pipeline est un module : son dossier porte build.gradle(.kts), son code vit sous src/main, ses
# tests sous src/test (JVM, ce que le gauntlet lance) et src/androidTest (instrumentés : QA, pas le gauntlet).
#
#   checks_static.sh    analyze (compilation, Android lint, detekt s'il est appliqué), format (ktlint ou Spotless),
#                       deps, error_handling, stub_check, no_stubs, no_temp_markers
#   checks_test.sh      test, red_check, test_names (rapports JUnit XML), coverage (Kover ou JaCoCo),
#                       mutation, mutation_scope (pitest s'il est appliqué)
#   checks_maintain.sh  design_system, l10n_strings, l10n_arb (strings.xml), test_hygiene, deprecated_api,
#                       package_readme
#   stack_doctor        ce que le doctor vérifie pour Android (JDK, wrapper, Android CLI, adb)
#
# Un check que Flutter a et pas Android (build_runner, metrics, reinvented, barrel_api, unused_code…) est non
# applicable : `[N/A]` dans le journal (ADR 0011). Un check d'ici dont l'outil manque au projet (pas de formateur,
# pas de couverture, pas de pitest) rend NA_RC : `[N/A]` aussi, avec la raison, jamais un vert.
ANDROID_CHECKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _f in checks_static.sh checks_test.sh checks_maintain.sh; do
  # shellcheck source=/dev/null
  source "$ANDROID_CHECKS_DIR/$_f"
done
unset _f

# ---------------------------------------------------------------------------------------------------------
# Gradle
# ---------------------------------------------------------------------------------------------------------
# gradle_pkg <arg…> — gradle_run.sh depuis le package courant (tâches `:x` et alias `:@unitTest` qualifiés par le
# module), avec la config que lit le gauntlet et la commande `gradle` du langage (./gradlew, ou celle du projet).
gradle_pkg() {
  (cd "$PKG_DIR" && STACK_CFG="${CFG_FILE:-}" GRADLE="$(stack_val gradle)" bash "$ANDROID_CHECKS_DIR/gradle_run.sh" "$@")
}
# gradle_log <nom> <arg…> — gradle_pkg, sortie dans $GAUNTLET_OUT/gradle_<nom>.log ; rend le code de Gradle.
gradle_log() {
  local name="$1"; shift
  gradle_pkg "$@" > "$GAUNTLET_OUT/gradle_$name.log" 2>&1
}
# module_kind — android | jvm (gradle_run.sh --where)
module_kind() { gradle_pkg --where 2>/dev/null | cut -f3; }
# unit_test_task — la tâche de tests unitaires du module (testDebugUnitTest, ou test pour un module JVM)
unit_test_task() { if [ "$(module_kind)" = android ]; then stack_val unit_test_task; else stack_val jvm_unit_test_task; fi; }

# build_files — fichiers où un projet applique ses plugins : le build du module, celui de la racine Gradle, le
# catalogue de versions, les plugins de convention (build-logic/, buildSrc/).
build_files() {
  local root; root="$(gradle_pkg --where 2>/dev/null | cut -f1)"
  for f in "$PKG_DIR/build.gradle.kts" "$PKG_DIR/build.gradle" "$root/build.gradle.kts" "$root/build.gradle" \
           "$root/gradle/libs.versions.toml"; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
  [ -n "$root" ] && find "$root/build-logic" "$root/buildSrc" -type f \( -name '*.kts' -o -name '*.gradle' -o -name '*.kt' \) \
    -not -path '*/build/*' 2>/dev/null
}
# has_plugin <regex> — un fichier de build_files cite <regex> hors commentaire (ktlint, detekt, kover, pitest…)
has_plugin() {
  local f
  while IFS= read -r f; do
    grep -v '^[[:space:]]*//' "$f" | grep -qE "$1" && return 0
  done < <(build_files)
  return 1
}

# rel_pkg — stdin : lignes qui commencent par un chemin absolu (file:// compris) → chemin relatif au package.
# Le dossier du package peut arriver sous deux noms (/var et /private/var sur macOS) : les deux sont retirés.
rel_pkg() {
  local real; real="$(cd "$PKG_DIR" && pwd -P)"
  sed -e 's#^file://##' -e "s#^$real/##" -e "s#^$PKG_DIR/##"
}
# kotlin_diag <log> <e|w> — diagnostics du compilateur Kotlin (« e: file:///…/X.kt:12:5 message ») en
# « chemin:ligne: message », chemins relatifs au package.
kotlin_diag() {
  grep -E "^$2: " "$1" | sed -E "s/^$2: //" | rel_pkg \
    | sed -E 's/^([^:]+):([0-9]+):[0-9]+:? (.*)$/\1:\2: \3/; s/^([^:]+): \(([0-9]+), [0-9]+\): (.*)$/\1:\2: \3/'
}

# ---------------------------------------------------------------------------------------------------------
# Doctor
# ---------------------------------------------------------------------------------------------------------
stack_doctor() {
  local root gradle android_cli
  need "java (JDK pour Gradle)" java -version
  root="$(cd "$APP_ROOT" && bash "$ANDROID_CHECKS_DIR/gradle_run.sh" --where 2>/dev/null | cut -f1)"
  need "racine Gradle (settings.gradle.kts) au-dessus de app_dir" test -n "$root"
  gradle="$(stack_val gradle)"
  case "$gradle" in
    ./*) need "wrapper Gradle ${gradle%% *} à la racine ($root)" test -x "$root/${gradle%% *}" ;;
    *)   need "gradle ($gradle)" sh -c "${gradle%% *} --version" ;;
  esac
  # Android CLI : previews Compose sans appareil, hiérarchie de l'écran, émulateurs. Non bloquant : sans lui, la
  # QA passe par Maestro et l'émulateur du SDK, et les captures de revue par Maestro.
  android_cli="$(stack_val android)"
  if [ "$(cfg android.emulator)" = cli ]; then
    need "Android CLI (${android_cli%% *}) : android.emulator = cli — developer.android.com/tools/agents" sh -c "${android_cli%% *} --version"
  else
    warn_if "Android CLI (${android_cli%% *}) — developer.android.com/tools/agents ; previews Compose sans appareil, écran à l'arrêt d'un flow rouge (android_cli.sh)" \
      sh -c "${android_cli%% *} --version"
  fi
  warn_if "adb (QA Maestro sur émulateur)" adb --version
}
