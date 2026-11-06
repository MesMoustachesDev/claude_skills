#!/usr/bin/env bash
# checks_test.sh — tests d'un module Android / Kotlin : suite JVM (src/test), rouge/vert, noms, couverture,
# mutation. Sourcé par stacks/android/checks.sh, après scripts/gauntlet/checks_test.sh (déroulé commun de la
# suite, packages de writes.extra, gel, tests ajoutés).
#
# Seuls les tests JVM tournent (tâche testDebugUnitTest, ou test pour un module Kotlin pur) : tests unitaires,
# ViewModel, et tests Compose sous Robolectric. Les tests instrumentés de src/androidTest demandent un appareil :
# le gauntlet ne les lance pas, ils ne prouvent rien ici (la QA Maestro joue le parcours sur l'émulateur).

# feature_tests_here — le périmètre du package courant (couche comprise) contient un fichier de test JVM.
feature_tests_here() { scope_files "$PKG_REL/" | grep -qE '^src/test/.*\.(kt|java)$'; }

# run_tests_json — lance la tâche de tests unitaires du module (--continue : tous les tests, même après un
# échec), puis lit ses rapports JUnit XML (build/test-results/<tâche>/) en une ligne JSON par test
# (test_report.jsonl, format de test_results). Rend le code de Gradle. Couche : `--tests` sur ses fichiers.
run_tests_json() {
  TEST_REPORT="$GAUNTLET_OUT/test_report.jsonl"; TEST_NONE=0
  local none=ko task results targets=() f rc
  [ "${TESTS_OPTIONAL:-0}" = 1 ] && none=info
  [ -d "$PKG_DIR/src/test" ] || { TEST_NONE=1; $none "pas de dossier src/test dans $PKG_REL"; : > "$TEST_REPORT"; return 1; }
  if [ -n "${LAYER:-}" ]; then
    while IFS= read -r f; do targets+=("$f"); done < <(layer_files src/test)
    [ ${#targets[@]} -gt 0 ] || { TEST_NONE=1; $none "aucun fichier de test dans la couche $LAYER ($PKG_REL)"; : > "$TEST_REPORT"; return 1; }
  fi
  task="$(unit_test_task)"; results="$PKG_DIR/build/test-results/$task"
  rm -rf "$results"
  TESTS_RAN="${TESTS_RAN:-} $TEST_REPORT"   # rapports produits par ce run (test_names les réutilise)
  gradle_pkg ":$task" --continue ${targets[@]+"${targets[@]}"} > "$GAUNTLET_OUT/test_stderr.log" 2>&1; rc=$?
  # shellcheck disable=SC2046
  python3 "$ANDROID_CHECKS_DIR/reports.py" junit "$results" "$PKG_DIR" $(stack_list test_dirs | tr '\n' ' ') > "$TEST_REPORT"
  return $rc
}

# test_results — une ligne JSON par test : {file, name, result, skipped}
test_results() { grep '^{' "$TEST_REPORT" 2>/dev/null; }

check_test()       { run_suite_check; }
check_red_check()  { run_red_check; }
check_test_names() { run_test_names; }

# coverage — couverture des lignes ajoutées sous src/main depuis base_branch, hors lignes seulement déplacées.
# Outil du projet : Kover (org.jetbrains.kotlinx.kover, koverXmlReport) ou JaCoCo (jacocoTestReport) ; la clé
# coverage_task de la config du projet nomme une autre tâche. Ni l'un ni l'autre : N/A. Le rapport XML (format
# JaCoCo, les deux outils l'écrivent) est le plus récent sous build/reports/{kover,jacoco}/.
# Packages de writes.extra où la feature a écrit des tests : même seuil.
check_coverage() {
  local rc=0 r
  coverage_pkg; r=$?
  [ "$r" = "$NA_RC" ] && return "$NA_RC"
  [ "$r" = 0 ] || rc=1
  each_extra_package extra_test_packages coverage_extra_pkg || rc=1
  return $rc
}
coverage_extra_pkg() {
  feature_tests_here || { info "pas de test de la feature dans $PKG_REL : couverture non jugée"; return 0; }
  coverage_pkg
}
coverage_pkg() {
  local thr task xml base changed moved d
  thr="$(cfg threshold.coverage_changed 90)"
  task="$(cfg coverage_task)"
  if [ -z "$task" ]; then
    if has_plugin 'kover'; then task=koverXmlReport
    elif has_plugin 'jacoco'; then task=jacocoTestReport
    else not_applicable "ni Kover ni JaCoCo dans le build (ni coverage_task dans la config) : couverture non mesurable"; return; fi
  fi
  rm -rf "$PKG_DIR/build/reports/kover" "$PKG_DIR/build/reports/jacoco"
  gradle_log coverage ":$(unit_test_task)" ":$task" \
    || { tail -20 "$GAUNTLET_OUT/gradle_coverage.log"; ko "$task a échoué (voir .gauntlet/gradle_coverage.log)"; return 1; }
  xml="$(find "$PKG_DIR/build/reports/kover" "$PKG_DIR/build/reports/jacoco" -name '*.xml' 2>/dev/null | xargs ls -t 2>/dev/null | head -1)"
  [ -n "$xml" ] || { ko "$task n'a écrit aucun rapport XML sous build/reports/{kover,jacoco} (activer xml.required)"; return 1; }
  base="$(merge_base)"; changed="$GAUNTLET_OUT/changed_lines.txt"
  for d in $(stack_list src_dirs); do new_lines "$base" "$PKG_REL/$d"; done | drop_generated | sort -u > "$changed"
  moved="$(cat "$GAUNTLET_OUT/moved_lines.count" 2>/dev/null)"
  [ "${moved:-0}" -gt 0 ] && info "$moved ligne(s) seulement déplacée(s) : hors couverture"
  [ -s "$changed" ] || { info "aucune ligne modifiée dans src/main depuis $base"; return 0; }
  # shellcheck disable=SC2046
  python3 "$ANDROID_CHECKS_DIR/reports.py" coverage "$xml" "$PKG_DIR" $(stack_list src_dirs | tr '\n' ' ') \
    | awk -v pkg="$PKG_REL" -v thr="$thr" -v changed="$changed" '
      BEGIN { while ((getline l < changed) > 0) ch[l]=1 }
      { k = pkg "/" $1; if (k in ch) { tot++; if ($2+0 > 0) cov++; else miss[k]=1 } }
      END {
        if (tot==0) { print "   aucune ligne modifiée n'"'"'est instrumentée (rien à couvrir)"; exit 0 }
        pct=cov*100/tot; printf "   lignes modifiées couvertes : %d/%d (%.1f%%), seuil %d%%\n", cov, tot, pct, thr
        n=0; for (k in miss) { if (n<30) print "   ✗ " k; n++ }
        if (n>30) print "   … et " (n-30) " autres"
        exit (pct+0.0001 >= thr) ? 0 : 1
      }'
}

# mutation — pitest, si le projet l'applique : info.solidsoft.pitest (module JVM, tâche pitest) ou
# pl.droidsonroids.pitest (module Android, pitestDebug) ; mutation.task de la config nomme une autre tâche. Le
# rapport XML (outputFormats XML) donne chaque mutant ; seuls ceux des fichiers de mutation.include du périmètre
# comptent. Score = mutants tués / mutants, ≥ threshold.mutation. Survivants dans .gauntlet/mutation_survivors.txt
# (Hugo les tue ou les explique dans mutants.md). Sans pitest : N/A.
# Pitest et ses deux plugins Gradle sont libres (Apache 2.0). Sans filtre Kotlin, pitest mute aussi le code que
# le compilateur ajoute (vérifications de nullité, machines à états des coroutines, data class) : des survivants
# que personne ne peut tuer. Le filtre Kotlin d'Arcmutate est sous licence payante ; sans lui, le projet exclut
# ces mutateurs (avoidCallsTo, excludedMethods) ou baisse threshold.mutation, et le dit dans sa config.
mutation_files() {
  local files
  # shellcheck disable=SC2046
  files="$(expand_globs "$PKG_DIR" $(cfg_list mutation.include | tr '\n' ' ') | filter_excluded $(cfg_list mutation.exclude | tr '\n' ' ') | drop_generated)"
  [ -n "$files" ] || return 2
  printf '%s\n' "$files" | filter_scope_files "$PKG_REL/"
}
check_mutation_scope() {
  local files n
  files="$(mutation_files)"; [ $? = 2 ] && files=""
  printf '%s' "$files" | grep -v '^$' > "$GAUNTLET_OUT/mutation_scope.txt"
  n="$(wc -l < "$GAUNTLET_OUT/mutation_scope.txt" | tr -d ' ')"
  info "$n fichier(s) de logique à muter dans le périmètre (gabarit $SIZE) → ${GAUNTLET_OUT#$PROJECT_ROOT/}/mutation_scope.txt"
  sed 's/^/   /' "$GAUNTLET_OUT/mutation_scope.txt"
  has_plugin 'pitest' || info "pitest non appliqué au projet : le gate mutation sera non applicable"
  return 0
}
check_mutation() {
  local thr files task xml all scoped total killed
  has_plugin 'pitest' || { not_applicable "pitest non appliqué au projet (info.solidsoft.pitest ou pl.droidsonroids.pitest) : pas de mutation"; return; }
  thr="$(cfg threshold.mutation 85)"
  files="$(mutation_files)"
  [ $? = 2 ] && { ko "aucun fichier ne correspond à mutation.include"; return 1; }
  [ -n "$files" ] || { info "aucun fichier à muter dans le périmètre"; return 0; }
  task="$(cfg mutation.task)"
  [ -n "$task" ] || { if [ "$(module_kind)" = android ]; then task=pitestDebug; else task=pitest; fi; }
  rm -rf "$PKG_DIR/build/reports/pitest"
  gradle_log mutation ":$task" || { tail -20 "$GAUNTLET_OUT/gradle_mutation.log"; ko "$task a échoué (voir .gauntlet/gradle_mutation.log)"; return 1; }
  xml="$(find "$PKG_DIR/build/reports/pitest" -name 'mutations.xml' 2>/dev/null | xargs ls -t 2>/dev/null | head -1)"
  [ -n "$xml" ] || { ko "pas de mutations.xml sous build/reports/pitest (outputFormats doit contenir XML)"; return 1; }
  # shellcheck disable=SC2046
  all="$(python3 "$ANDROID_CHECKS_DIR/reports.py" pitest "$xml" "$PKG_DIR" $(stack_list src_dirs | tr '\n' ' '))"
  scoped="$(printf '%s\n' "$all" | grep -v '^$' | grep -F -f <(printf '%s:\n' $files))"
  total="$(printf '%s' "$scoped" | grep -c .)"
  [ "$total" -gt 0 ] || { info "aucun mutant dans les fichiers du périmètre"; return 0; }
  killed="$(printf '%s\n' "$scoped" | grep -cE '^[^ ]+ (KILLED|TIMED_OUT|MEMORY_ERROR) ')"
  printf '%s\n' "$scoped" | grep -vE '^[^ ]+ (KILLED|TIMED_OUT|MEMORY_ERROR) ' > "$GAUNTLET_OUT/mutation_survivors.txt"
  awk -v k="$killed" -v t="$total" -v thr="$thr" 'BEGIN { printf "   score : %d/%d (%.1f%%), seuil %d%%\n", k, t, k*100/t, thr }'
  sed 's/^/   ✗ /' "$GAUNTLET_OUT/mutation_survivors.txt" | head -30
  awk -v k="$killed" -v t="$total" -v thr="$thr" 'BEGIN { exit (k*100/t + 0.0001 >= thr) ? 0 : 1 }'
}
