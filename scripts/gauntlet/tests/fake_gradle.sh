#!/usr/bin/env bash
# fake_gradle.sh — remplace `./gradlew` dans les tests du gauntlet Android. Lancé depuis la racine Gradle avec des
# tâches qualifiées (`:feature:login:testDebugUnitTest`, gradle_run.sh) ; le module est le dossier du chemin.
# Écrit les mêmes rapports que les vrais outils, d'après des marqueurs dans les sources du module :
#   compile*          FAKE_COMPILE_ERROR → « e: file:///…:1:1 », exit 1 ; FAKE_DEPRECATED → « w: … is deprecated »
#   test* (unitaire)  un TEST-<classe>.xml par fichier de src/test (ou par --tests), un cas ; FAKE_FAIL → échec
#   lint*             build/reports/lint-results-debug.xml, une issue Warning par ligne FAKE_LINT
#   ktlintCheck       « /abs/X.kt:N:1 … » par ligne FAKE_FORMAT, exit 1
#   detekt            build/reports/detekt/detekt.xml, une erreur par ligne FAKE_DETEKT
#   koverXmlReport    build/reports/kover/report.xml : chaque ligne de src/main couverte, sauf FAKE_UNCOVERED
#   pitest*           build/reports/pitest/mutations.xml : un mutant tué par fichier, un survivant par FAKE_SURVIVOR
# Chaque appel est ajouté à $FAKE_GRADLE_LOG s'il est posé.
set -u
[ -n "${FAKE_GRADLE_LOG:-}" ] && printf '%s\n' "$*" >> "$FAKE_GRADLE_LOG"
root="$PWD"; rc=0; filters=()
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  [ "${args[i]}" = --tests ] && filters+=("${args[i+1]}")
done

pkg_of() { sed -n 's/^[[:space:]]*package[[:space:]]\{1,\}\([A-Za-z0-9_.]*\).*/\1/p' "$1" | head -1; }
srcs() { find "$1" -type f \( -name '*.kt' -o -name '*.java' \) 2>/dev/null | sort; }

for a in "$@"; do
  case "$a" in :*) ;; *) continue ;; esac
  task="${a##*:}"; mpath="${a%:*}"; mod="$root$(printf '%s' "$mpath" | tr ':' '/')"
  case "$task" in
    compile*)
      for f in $(srcs "$mod/src"); do
        grep -n FAKE_COMPILE_ERROR "$f" | cut -d: -f1 | while read -r n; do echo "e: file://$f:$n:1 Unresolved reference 'fake'."; done
        grep -n FAKE_DEPRECATED "$f" | cut -d: -f1 | while read -r n; do echo "w: file://$f:$n:5 'fake(): Unit' is deprecated. Use other."; done
      done
      grep -rqs FAKE_COMPILE_ERROR "$mod/src" && { echo "BUILD FAILED"; rc=1; } ;;
    test*)
      out="$mod/build/test-results/$task"; mkdir -p "$out"
      for f in $(srcs "$mod/src/test"); do
        cls="$(pkg_of "$f")"; cls="${cls:+$cls.}$(basename "${f%.*}")"
        if [ ${#filters[@]} -gt 0 ]; then printf '%s\n' "${filters[@]}" | grep -qxF "$cls" || continue; fi
        if grep -q FAKE_FAIL "$f"; then
          body='<failure message="fake">fake</failure>'; nf=1; rc=1
        else body=''; nf=0; fi
        printf '<?xml version="1.0" encoding="UTF-8"?>\n<testsuite name="%s" tests="1" failures="%s" errors="0" skipped="0">\n  <testcase name="%s" classname="%s" time="0.0">%s</testcase>\n</testsuite>\n' \
          "$cls" "$nf" "$(basename "${f%.*}") works" "$cls" "$body" > "$out/TEST-$cls.xml"
      done ;;
    lint*)
      mkdir -p "$mod/build/reports"
      { echo '<?xml version="1.0" encoding="UTF-8"?>'; echo '<issues format="6">'
        for f in $(srcs "$mod/src/main"); do
          grep -n FAKE_LINT "$f" | cut -d: -f1 | while read -r n; do
            printf '  <issue id="FakeLint" severity="Warning" message="fake lint"><location file="%s" line="%s" column="1"/></issue>\n' "$f" "$n"
          done
        done; echo '</issues>'; } > "$mod/build/reports/lint-results-debug.xml" ;;
    ktlintCheck)
      for f in $(srcs "$mod/src"); do
        grep -n FAKE_FORMAT "$f" | cut -d: -f1 | while read -r n; do echo "$f:$n:1 Unexpected blank line(s) (standard:no-consecutive-blank-lines)"; done
      done
      grep -rqs FAKE_FORMAT "$mod/src" && rc=1 ;;
    detekt)
      mkdir -p "$mod/build/reports/detekt"
      { echo '<?xml version="1.0" encoding="UTF-8"?>'; echo '<checkstyle version="4.3">'
        for f in $(srcs "$mod/src/main"); do
          printf '<file name="%s">\n' "$f"
          grep -n FAKE_DETEKT "$f" | cut -d: -f1 | while read -r n; do
            printf '  <error line="%s" column="1" severity="warning" message="fake complexity" source="detekt.LongMethod"/>\n' "$n"
          done
          echo '</file>'
        done; echo '</checkstyle>'; } > "$mod/build/reports/detekt/detekt.xml" ;;
    koverXmlReport)
      mkdir -p "$mod/build/reports/kover"
      { echo '<?xml version="1.0" encoding="UTF-8"?>'; echo '<report name="fake">'
        for f in $(srcs "$mod/src/main"); do
          printf '<package name="%s"><sourcefile name="%s">\n' "$(pkg_of "$f" | tr '.' '/')" "$(basename "$f")"
          awk '/^[[:space:]]*(package|import)/ || /^[[:space:]]*$/ || /^[[:space:]]*[{}][[:space:]]*$/ { next }
               { printf "  <line nr=\"%d\" mi=\"%d\" ci=\"%d\" mb=\"0\" cb=\"0\"/>\n", NR, /FAKE_UNCOVERED/ ? 1 : 0, /FAKE_UNCOVERED/ ? 0 : 1 }' "$f"
          echo '</sourcefile></package>'
        done; echo '</report>'; } > "$mod/build/reports/kover/report.xml" ;;
    pitest*)
      mkdir -p "$mod/build/reports/pitest"
      { echo '<?xml version="1.0" encoding="UTF-8"?>'; echo '<mutations>'
        for f in $(srcs "$mod/src/main"); do
          cls="$(pkg_of "$f")"; cls="${cls:+$cls.}$(basename "${f%.*}")Kt"
          printf '<mutation detected="true" status="KILLED"><sourceFile>%s</sourceFile><mutatedClass>%s</mutatedClass><lineNumber>1</lineNumber><mutator>org.pitest.Math</mutator><description>fake</description></mutation>\n' "$(basename "$f")" "$cls"
          grep -n FAKE_SURVIVOR "$f" | cut -d: -f1 | while read -r n; do
            printf '<mutation detected="false" status="SURVIVED"><sourceFile>%s</sourceFile><mutatedClass>%s</mutatedClass><lineNumber>%s</lineNumber><mutator>org.pitest.ConditionalsBoundary</mutator><description>changed conditional boundary</description></mutation>\n' "$(basename "$f")" "$cls" "$n"
          done
        done; echo '</mutations>'; } > "$mod/build/reports/pitest/mutations.xml" ;;
  esac
done
exit $rc
