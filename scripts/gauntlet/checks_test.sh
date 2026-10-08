#!/usr/bin/env bash
# checks_test.sh — tests, rouge/vert, gel des tests, couverture, mutation. Sourcé par gauntlet.sh.

TEST_REPORT="" # défini par run_tests_json

# run_tests_json — lance flutter test --reporter json, conserve le rapport. Retourne le code de flutter test.
run_tests_json() {
  TEST_REPORT="$GAUNTLET_OUT/test_report.jsonl"
  [ -d "$PKG_DIR/test" ] || { ko "pas de dossier test/ dans $PKG_REL"; return 1; }
  # shellcheck disable=SC2086
  (cd "$PKG_DIR" && $FLUTTER test --reporter json --no-pub > "$TEST_REPORT" 2>"$GAUNTLET_OUT/test_stderr.log")
}

# test_results — une ligne JSON par test non caché : {file, name, result, skipped}
test_results() {
  jq -c -s '
    (map(select(.type=="testStart")) | map({key:(.test.id|tostring), value:.test}) | from_entries) as $t
    # The suite path is the test file. A testWidgets url points into flutter_test (widget_tester.dart),
    # its root_url at the file: read the suite first, root_url next, url last.
    | (map(select(.type=="suite")) | map({key:(.suite.id|tostring), value:.suite.path}) | from_entries) as $s
    | map(select(.type=="testDone" and (.hidden|not)))
    | map(. as $d | $t[($d.testID|tostring)] as $x
        | {file: (($s[($x.suiteID|tostring)] // $x.root_url // $x.url // "?") | sub("^file://"; "")),
           name: $x.name, result: $d.result, skipped: $d.skipped})
    | .[]' < <(grep '^{' "$TEST_REPORT") 2>/dev/null | sed "s#\"file\":\"$PKG_DIR/#\"file\":\"#"
  # grep '^{' : the engine may print native log lines on stdout ("Shell: [ERROR:flutter/runtime/…]"),
  # which would make the whole JSON report unreadable.
}

check_test() {
  local rc total failed
  run_tests_json; rc=$?
  total="$(test_results | wc -l | tr -d ' ')"
  failed="$(test_results | jq -r 'select(.result!="success") | "  ✗ \(.file) — \(.name)"')"
  [ "$total" = 0 ] && { ko "aucun test exécuté"; tail -20 "$GAUNTLET_OUT/test_stderr.log"; return 1; }
  if [ -n "$failed" ]; then printf '%s\n' "$failed"; fi
  info "$total test(s), $(printf '%s' "$failed" | grep -c '✗' || true) échec(s)"
  [ "$rc" = 0 ] && [ -z "$failed" ]
}

# red_check — après TEST-WRITER : la suite compile, et chaque fichier de test contient ≥ 1 échec.
# Les tests qui passent déjà contre les stubs sont listés (information), pas bloquants.
check_red_check() {
  run_tests_json || true
  local total green_files passing
  total="$(test_results | wc -l | tr -d ' ')"
  if [ "$total" = 0 ]; then
    ko "aucun test exécuté — la suite ne compile probablement pas"; tail -30 "$GAUNTLET_OUT/test_stderr.log"; return 1
  fi
  # mode extend : seuls les fichiers de test nouveaux ou modifiés doivent être rouges
  local scoped_files
  scoped_files="$(test_results | jq -r '.file' | sort -u | filter_scope_files "$PKG_REL/")"
  if [ -z "$scoped_files" ]; then ko "aucun fichier de test dans le périmètre — le test-writer n'a rien ajouté"; return 1; fi
  green_files="$(test_results | jq -r -s 'group_by(.file) | map(select(all(.[]; .result=="success")) | .[0].file) | .[]' | grep -xF -f <(printf '%s\n' "$scoped_files"))"
  passing="$(test_results | jq -r 'select(.result=="success") | "\(.file):0 — \(.name)"' | filter_scope_lines "$PKG_REL/" | sed 's/^/  · /; s/:0 —/ —/')"
  [ -n "$passing" ] && { info "tests du périmètre qui passent déjà contre les stubs :"; printf '%s\n' "$passing"; }
  if [ -n "$green_files" ]; then
    printf '%s\n' "$green_files" | sed 's/^/  ✗ tout vert : /'
    ko "ces fichiers ne testent rien que les stubs ne satisfassent déjà"
    return 1
  fi
  info "$total test(s), $(printf '%s\n' "$scoped_files" | wc -l | tr -d ' ') fichier(s) dans le périmètre, rouge dans chacun"
}

# test_names — écrit .claude/features/<f>/tests.md pour le skim du dev. Toujours vert.
check_test_names() {
  [ -f "$TEST_REPORT" ] || run_tests_json || true
  local out="$FEATURE_DIR/tests.md"
  {
    printf '# Tests — %s\n\n' "$FEATURE"
    printf '_%s tests. « passe déjà » = vert contre les stubs, donc ne contraint pas l'"'"'implémentation._\n' "$(test_results | wc -l | tr -d ' ')"
    test_results | jq -r -s 'group_by(.file)[] | "\n## \(.[0].file)\n" + (map("- " + .name + (if .result=="success" then "  _(passe déjà)_" else "" end)) | join("\n"))'
  } > "$out"
  info "écrit : ${out#$PROJECT_ROOT/}"
}

# test_freeze_check <strict|additive> — les tests gelés (SHA dans pipeline.json) sont intacts.
#   strict   : aucun changement, aucun fichier nouveau dans test/
#   additive : seuls des fichiers AJOUTÉS sont tolérés (hardener) ; aucune modification, aucune suppression
check_test_freeze_check() {
  local mode="${1:-strict}" sha changes untracked rc=0
  sha="$(pipeline_get .tests_freeze_sha)"
  [ -n "$sha" ] || { ko "pas de gel enregistré (pipeline.json → tests_freeze_sha)"; return 1; }
  changes="$(git -C "$PROJECT_ROOT" diff --name-status "$sha" -- "$PKG_REL/test" 2>/dev/null)"
  untracked="$(git -C "$PROJECT_ROOT" ls-files --others --exclude-standard -- "$PKG_REL/test" 2>/dev/null)"
  case "$mode" in
    strict)
      [ -n "$changes" ]   && { printf '%s\n' "$changes" | sed 's/^/  /'; rc=1; }
      [ -n "$untracked" ] && { printf '%s\n' "$untracked" | sed 's/^/  ?? /'; rc=1; }
      [ "$rc" = 1 ] && ko "test/ a changé depuis le gel ($sha)"
      ;;
    additive)
      local bad; bad="$(printf '%s\n' "$changes" | grep -vE '^A' | grep -v '^$')"
      [ -n "$bad" ] && { printf '%s\n' "$bad" | sed 's/^/  /'; ko "seuls des ajouts de fichiers sont tolérés dans test/"; rc=1; }
      [ -n "$untracked" ] && info "nouveaux fichiers : $(printf '%s' "$untracked" | tr '\n' ' ')"
      ;;
    *) die "mode inconnu : $mode" ;;
  esac
  [ "$rc" = 0 ] && info "gel $sha respecté ($mode)"
  return $rc
}

# coverage — couverture des lignes modifiées depuis base_branch (fichiers suivis : diff ; nouveaux : toutes les lignes).
check_coverage() {
  local thr lcov base changed rc
  thr="$(cfg threshold.coverage_changed 90)"
  # shellcheck disable=SC2086
  (cd "$PKG_DIR" && $FLUTTER test --coverage --no-pub >/dev/null 2>&1) || { ko "flutter test --coverage a échoué"; return 1; }
  lcov="$PKG_DIR/coverage/lcov.info"
  [ -f "$lcov" ] || { ko "pas de $lcov"; return 1; }
  base="$(merge_base)"
  changed="$GAUNTLET_OUT/changed_lines.txt"
  {
    git -C "$PROJECT_ROOT" diff -U0 "$base" -- "$PKG_REL/lib" \
      | awk '/^\+\+\+ b\//{f=substr($0,7)} /^@@/{split($3,a,","); s=substr(a[1],2); n=(a[2]==""?1:a[2]); for(i=0;i<n;i++) print f":"(s+i)}'
    git -C "$PROJECT_ROOT" ls-files --others --exclude-standard -- "$PKG_REL/lib" | while IFS= read -r f; do
      awk -v f="$f" '{print f":"NR}' "$PROJECT_ROOT/$f"
    done
  } | grep -vE '\.g\.dart:|\.freezed\.dart:' | sort -u > "$changed"
  if [ ! -s "$changed" ]; then info "aucune ligne modifiée dans lib/ depuis $base"; return 0; fi
  awk -v pkg="$PKG_REL" -v thr="$thr" -v changed="$changed" '
    BEGIN { while ((getline l < changed) > 0) ch[l]=1 }
    /^SF:/ { f=substr($0,4); sub(/^\.\//,"",f); if (f !~ "^"pkg"/") f=pkg"/"f }
    /^DA:/ { split(substr($0,4),a,","); k=f":"a[1]; if (k in ch) { tot++; if (a[2]+0>0) cov++; else miss[k]=1 } }
    END {
      if (tot==0) { print "   aucune ligne modifiée n'"'"'est exécutable (rien à couvrir)"; exit 0 }
      pct=cov*100/tot; printf "   lignes modifiées couvertes : %d/%d (%.1f%%), seuil %d%%\n", cov, tot, pct, thr
      n=0; for (k in miss) { if (n<30) print "   ✗ " k; n++ }
      if (n>30) print "   … et " (n-30) " autres"
      exit (pct+0.0001 >= thr) ? 0 : 1
    }' "$lcov"
}

# mutation — mutation_test sur les globs configurés. Score global ≥ threshold.mutation.
#
# Un run mutation_test PAR FICHIER, limité aux tests de ce fichier : `foo.dart` → `test/**/foo_test.dart`.
# Sans test homonyme : tous les tests unitaires. Les tests d'acceptance (test/<x>_test.dart généré depuis
# test/<x>.feature) ne tournent jamais en mutation : trop lents, et un mutant que seule l'acceptance tue
# doit recevoir un test unitaire. Avant : toute la suite (acceptance comprise) relancée pour chaque mutant.
# Le coût d'un mutant n'est pas la compilation (3 à 8 s) mais les tests qu'il fait bloquer (un flux qui
# n'émet plus attend le timeout de 30 s). D'où `--fail-fast --timeout <mutation.test_timeout, 10s>`.
# Parallélisme : mutation.workers (défaut 4) clones APFS (`cp -c`, copie à l'écriture) de app_dir ; chaque
# worker mute dans son clone, le dépôt n'est jamais muté. Couverture : lcov de toute la suite, passé à
# mutation_test qui ne mute que les lignes couvertes (un mutant non couvert survit par construction).
# app_dir = "." : un seul worker, en place, avec restauration garantie des fichiers mutés.
mutation_unit_tests() {
  (cd "$PKG_DIR" && find test -name '*_test.dart' -not -path '*/.dart_tool/*' | sort | while IFS= read -r t; do
      [ -f "${t%_test.dart}.feature" ] || printf '%s\n' "$t"; done)
}
mutation_tests_for() {
  local stem own
  stem="$(basename "$1" .dart)"
  # `foo_test.dart` et les fichiers ajoutés au durcissement `foo_<x>_test.dart` (ex. foo_mutation_test.dart)
  own="$(cd "$PKG_DIR" && find test \( -name "${stem}_test.dart" -o -name "${stem}_*_test.dart" \) -not -path '*/.dart_tool/*' | sort | while IFS= read -r t; do
      [ -f "${t%_test.dart}.feature" ] || printf '%s\n' "$t"; done)"
  if [ -n "$own" ]; then printf '%s\n' "$own"; else mutation_unit_tests; fi
}
mutation_restore() {
  local o
  for o in "$GAUNTLET_OUT/mutation-orig"/*; do
    [ -f "$o" ] && cp "$o" "$PKG_DIR/$(basename "$o" | tr '%' '/')"
  done
}
# Tâches : un fichier est découpé en tranches de mutation.shard_lines lignes (défaut 100), chacune son xml,
# pour qu'un gros fichier se répartisse sur tous les workers. File partagée : chaque worker prend la
# tâche suivante dès qu'il est libre (verrou mkdir), au lieu d'un lot fixé d'avance.
# Passage à vide : avant sa première tranche d'un fichier, un worker lance les tests de ce fichier sans
# mutant, sous la même charge. S'ils échouent (test lent > timeout sous charge, test cassé), le fichier est
# marqué BASELINE_KO et le gate échoue, au lieu de compter des mutants faussement tués.
#
# mutation_plan <fichier> — écrit les xml des tranches et ajoute « fichier<TAB>tranche<TAB>xml » à la file.
mutation_plan() {
  local f="$1" slug lines tests tmo k xml shard
  slug="$(printf '%s' "$f" | tr '/' '%')"
  tmo="$(cfg mutation.test_timeout 10s)"; shard="$(cfg mutation.shard_lines 100)"
  if [ "$SCOPE_ALL" != 1 ] && ! grep -qx "$PKG_REL/$f" "$SCOPE_FILE"; then
    lines="$(grep "^$PKG_REL/$f:" "$SCOPE_FILE" | cut -d: -f2 | sort -n)"   # lignes ajoutées seulement
  else
    lines="$(seq 1 "$(wc -l < "$PKG_DIR/$f" | tr -d ' ')")"
  fi
  [ -n "$lines" ] || return 0
  tests="$(mutation_tests_for "$f" | tr '\n' ' ')"
  printf '%s\n' "$tests" > "$GAUNTLET_OUT/mutation-tests-$slug.txt"
  for k in $(printf '%s\n' "$lines" | awk -v s="$shard" '{print int(($1-1)/s)}' | sort -un); do
    xml="$GAUNTLET_OUT/mutation-$slug#$k.xml"
    {
      printf '<?xml version="1.0" encoding="UTF-8"?>\n<mutations version="1.2">\n  <files>\n    <file>%s\n' "$f"
      # lignes de la tranche → plages contiguës <lines begin end/>
      printf '%s\n' "$lines" | awk -v s="$shard" -v k="$k" 'int(($1-1)/s)==k' | awk 'NR==1{b=$1;e=$1;next} $1==e+1{e=$1;next} {printf "      <lines begin=\"%d\" end=\"%d\"/>\n",b,e; b=$1;e=$1} END{if(NR) printf "      <lines begin=\"%d\" end=\"%d\"/>\n",b,e}'
      printf '    </file>\n  </files>\n  <commands>\n    <command group="test" expected-return="0" working-directory="." timeout="300">%s test --no-pub --fail-fast --timeout %s %s</command>\n  </commands>\n' "$FLUTTER" "$tmo" "$tests"
      printf '  <threshold failure="0">\n    <rating over="0" name="D"/>\n  </threshold>\n</mutations>\n'
    } > "$xml"
    printf '%s\t%s\t%s\n' "$f" "$k" "$xml" >> "$GAUNTLET_OUT/mutation-queue"
  done
}
# mutation_pop — retire et affiche la prochaine tâche de la file (vide si la file est vide).
mutation_pop() {
  local lock="$GAUNTLET_OUT/mutation-queue.lock" q="$GAUNTLET_OUT/mutation-queue" task
  until mkdir "$lock" 2>/dev/null; do sleep 0.2; done
  task="$(head -1 "$q" 2>/dev/null)"
  [ -n "$task" ] && { tail -n +2 "$q" > "$q.tmp"; mv "$q.tmp" "$q"; }
  rmdir "$lock"
  printf '%s' "$task"
}
# mutation_worker <n> <dossier du package où muter> — prend des tâches dans la file jusqu'à épuisement.
mutation_worker() {
  local n="$1" pkg="$2" task f k xml slug tests log="$GAUNTLET_OUT/mutation-worker-$1.log" cov=() checked=" "
  [ -f "$pkg/coverage/lcov.info" ] && cov=(-c coverage/lcov.info)
  : > "$log"
  while task="$(mutation_pop)"; [ -n "$task" ]; do
    IFS=$'\t' read -r f k xml <<< "$task"
    slug="$(printf '%s' "$f" | tr '/' '%')"
    case "$checked" in *" $f "*) ;; *)
      tests="$(cat "$GAUNTLET_OUT/mutation-tests-$slug.txt")"
      # shellcheck disable=SC2086
      if ! (cd "$pkg" && $FLUTTER test --no-pub --timeout "$(cfg mutation.test_timeout 10s)" $tests >>"$log" 2>&1); then
        printf 'BASELINE_KO %s\n' "$f" >> "$log"; printf '%s\n' "$f" >> "$GAUNTLET_OUT/mutation-baseline-ko"
      fi
      checked="$checked$f " ;;
    esac
    grep -qx "$f" "$GAUNTLET_OUT/mutation-baseline-ko" 2>/dev/null && continue
    printf '== %s#%s\n' "$f" "$k" >> "$log"
    # shellcheck disable=SC2086
    (cd "$pkg" && $DART pub global run mutation_test "$xml" -o "$GAUNTLET_OUT/mutation-report/$slug#$k" -f md -q "${cov[@]}" >>"$log" 2>&1)
  done
}
check_mutation() {
  local thr files report
  thr="$(cfg threshold.mutation 85)"
  files="$(expand_globs "$PKG_DIR" $(cfg_list mutation.include | tr '\n' ' ') | filter_excluded $(cfg_list mutation.exclude | tr '\n' ' '))"
  [ -n "$files" ] || { ko "aucun fichier ne correspond à mutation.include"; return 1; }
  # mode extend : fichiers du périmètre seulement, et dans un fichier modifié, seules les lignes ajoutées
  files="$(printf '%s\n' "$files" | filter_scope_files "$PKG_REL/")"
  [ -n "$files" ] || { info "aucun fichier à muter dans le périmètre"; return 0; }
  # Un seul run de mutation par feature : deux runs partagent clones, file et rapports, et le nettoyage de
  # l'un détruit le travail de l'autre. Verrou avec pid ; un verrou dont le pid est mort est repris.
  local mlock="$GAUNTLET_OUT/mutation.lock"
  if ! mkdir "$mlock" 2>/dev/null; then
    if kill -0 "$(cat "$mlock/pid" 2>/dev/null)" 2>/dev/null; then
      ko "un run de mutation tourne déjà pour cette feature (pid $(cat "$mlock/pid")) : attends sa fin ou tue-le"; return 1
    fi
    rm -rf "$mlock"; mkdir "$mlock"
  fi
  echo $$ > "$mlock/pid"
  trap 'rm -rf "'"$mlock"'"' RETURN
  report="$GAUNTLET_OUT/mutation-report"
  rm -rf "$report" "$GAUNTLET_OUT/mutation-orig" "$GAUNTLET_OUT/mutation-clones" "$GAUNTLET_OUT"/mutation-*.xml \
    "$GAUNTLET_OUT"/mutation-worker-*.log "$GAUNTLET_OUT"/mutation-tests-*.txt "$GAUNTLET_OUT/mutation-queue" \
    "$GAUNTLET_OUT/mutation-queue.lock" "$GAUNTLET_OUT/mutation-baseline-ko"
  mkdir -p "$report" "$GAUNTLET_OUT/mutation-orig"
  # Couverture de toute la suite : mutation_test ne mute que les lignes couvertes.
  (cd "$PKG_DIR" && $FLUTTER test --no-pub --coverage >"$GAUNTLET_OUT/mutation_coverage.log" 2>&1) \
    || info "couverture non produite (voir mutation_coverage.log) : toutes les lignes du périmètre sont mutées"
  local app workers ntasks nfiles i f
  app="$(cfg app_dir .)"; app="${app%/}"
  for f in $files; do mutation_plan "$f"; done
  ntasks="$(wc -l < "$GAUNTLET_OUT/mutation-queue" 2>/dev/null | tr -d ' ')"; ntasks="${ntasks:-0}"
  nfiles="$(printf '%s\n' "$files" | wc -l | tr -d ' ')"
  workers="$(cfg mutation.workers 4)"
  [ "$workers" -gt "$ntasks" ] && workers="$ntasks"
  [ "$app" = . ] && workers=1
  [ "$workers" -ge 1 ] || { info "aucune ligne à muter dans le périmètre"; return 0; }
  info "$nfiles fichier(s), $ntasks tranche(s), $workers worker(s), tests ciblés en --fail-fast, seuil $thr%"
  if [ "$app" = . ]; then
    # Pas de clone possible sans dupliquer le dépôt : en place, avec restauration garantie.
    for f in $files; do cp "$PKG_DIR/$f" "$GAUNTLET_OUT/mutation-orig/$(printf '%s' "$f" | tr '/' '%')"; done
    trap mutation_restore EXIT INT TERM
    mutation_worker 1 "$PKG_DIR"
    mutation_restore; trap - EXIT INT TERM
  else
    # Un clone APFS (copie à l'écriture) de app_dir par worker : le dépôt n'est jamais muté.
    local pids=() clone
    for ((i = 1; i <= workers; i++)); do
      clone="$GAUNTLET_OUT/mutation-clones/w$i"; mkdir -p "$(dirname "$clone/$app")"
      cp -cR "$PROJECT_ROOT/$app" "$clone/$app" 2>/dev/null || cp -R "$PROJECT_ROOT/$app" "$clone/$app"
      mutation_worker "$i" "$clone/$PKG_REL" &
      pids+=("$!")
    done
    trap 'kill "${pids[@]}" 2>/dev/null' INT TERM
    wait "${pids[@]}"
    trap - INT TERM
    rm -rf "$GAUNTLET_OUT/mutation-clones"
  fi
  cat "$GAUNTLET_OUT"/mutation-worker-*.log > "$GAUNTLET_OUT/mutation_stdout.log" 2>/dev/null
  if [ -s "$GAUNTLET_OUT/mutation-baseline-ko" ]; then
    ko "tests en échec SANS mutant (sous charge, timeout $(cfg mutation.test_timeout 10s)) : score non fiable pour"
    sed 's/^/   ✗ /' "$GAUNTLET_OUT/mutation-baseline-ko" | sort -u
    info "monter mutation.test_timeout ou corriger ces tests ; voir mutation_stdout.log"
    return 1
  fi
  local slug md t u ft fu total=0 undetected=0 survivors="" task k xml
  for f in $files; do
    slug="$(printf '%s' "$f" | tr '/' '%')"; ft=0; fu=0
    for xml in "$GAUNTLET_OUT/mutation-$slug#"*.xml; do
      [ -f "$xml" ] || continue
      k="${xml##*#}"; k="${k%.xml}"
      # Le rapport md contient un tableau | Mutations | n |, | Undetected | n |.
      md="$(ls "$report/$slug#$k"/*.md 2>/dev/null | head -1)"
      if [ -z "$md" ]; then ko "pas de rapport pour $f (tranche $k)"; tail -20 "$GAUNTLET_OUT/mutation_stdout.log"; return 1; fi
      t="$(grep -E '^\| Mutations ' "$md" | awk -F'|' '{gsub(/ /,"",$3); print $3}')"
      u="$(grep -E '^\| Undetected ' "$md" | awk -F'|' '{gsub(/ /,"",$3); print $3}')"
      ft=$(( ft + ${t:-0} )); fu=$(( fu + ${u:-0} ))
    done
    total=$(( total + ft )); undetected=$(( undetected + fu ))
    [ "$fu" != 0 ] && survivors="${survivors}   ✗ ${fu}/${ft} survivant(s) dans $f — ${report#"$PROJECT_ROOT"/}/$slug#*/"$'\n'
  done
  if [ "$total" = 0 ]; then info "aucune mutation possible dans ces fichiers (code trivial) — rien à prouver"; return 0; fi
  local score=$(( (total-undetected)*100/total ))
  printf '   mutants : %s, survivants : %s, score : %d%% (seuil %s%%)\n' "$total" "$undetected" "$score" "$thr"
  printf '%s' "$survivors"
  info "rapports : ${report#"$PROJECT_ROOT"/}/<fichier>/ — chaque survivant est à tuer ou à expliquer dans mutants.md"
  [ "$score" -ge "$thr" ]
}
