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
    | map(select(.type=="testDone" and (.hidden|not)))
    | map(. as $d | $t[($d.testID|tostring)] as $x
        | {file: (($x.url // $x.root_url // "?") | sub("^file://"; "")),
           name: $x.name, result: $d.result, skipped: $d.skipped})
    | .[]' "$TEST_REPORT" 2>/dev/null | sed "s#\"file\":\"$PKG_DIR/#\"file\":\"#"
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
  green_files="$(test_results | jq -r -s 'group_by(.file) | map(select(all(.[]; .result=="success")) | .[0].file) | .[]')"
  passing="$(test_results | jq -r 'select(.result=="success") | "  · \(.file) — \(.name)"')"
  [ -n "$passing" ] && { info "tests qui passent déjà contre les stubs :"; printf '%s\n' "$passing"; }
  if [ -n "$green_files" ]; then
    printf '%s\n' "$green_files" | sed 's/^/  ✗ tout vert : /'
    ko "ces fichiers ne testent rien que les stubs ne satisfassent déjà"
    return 1
  fi
  info "$total test(s), rouge dans chaque fichier"
}

# test_names — écrit .claude/features/<f>/tests.md pour le skim humain. Toujours vert.
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

# mutation — mutation_test sur les globs configurés. Score ≥ threshold.mutation.
check_mutation() {
  local thr files xml report rc score
  thr="$(cfg threshold.mutation 85)"
  files="$(expand_globs "$PKG_DIR" $(cfg_list mutation.include | tr '\n' ' ') | filter_excluded $(cfg_list mutation.exclude | tr '\n' ' '))"
  [ -n "$files" ] || { ko "aucun fichier ne correspond à mutation.include"; return 1; }
  xml="$GAUNTLET_OUT/mutation.xml"; report="$GAUNTLET_OUT/mutation-report"; rm -rf "$report"
  {
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<mutations version="1.2">\n  <files>\n'
    printf '%s\n' "$files" | sed 's#^#    <file>#; s#$#</file>#'
    printf '  </files>\n  <commands>\n    <command group="test" expected-return="0" working-directory="." timeout="900">%s test --no-pub</command>\n  </commands>\n' "$FLUTTER"
    printf '  <threshold failure="%s">\n    <rating over="95" name="A"/>\n    <rating over="85" name="B"/>\n    <rating over="70" name="C"/>\n    <rating over="0" name="D"/>\n  </threshold>\n</mutations>\n' "$thr"
  } > "$xml"
  info "$(printf '%s\n' "$files" | wc -l | tr -d ' ') fichier(s) à muter, seuil $thr%"
  local cov=(); [ -f "$PKG_DIR/coverage/lcov.info" ] && cov=(-c coverage/lcov.info)
  # shellcheck disable=SC2086
  (cd "$PKG_DIR" && $DART pub global run mutation_test "$xml" -o "$report" -f md -q "${cov[@]}" >"$GAUNTLET_OUT/mutation_stdout.log" 2>&1); rc=$?
  # Le rapport md contient un tableau | Mutations | n |, | Undetected | n |, | Success | true/false |.
  local md total undetected success
  md="$(ls "$report"/*.md 2>/dev/null | head -1)"
  if [ -z "$md" ]; then ko "pas de rapport produit"; tail -20 "$GAUNTLET_OUT/mutation_stdout.log"; return 1; fi
  total="$(grep -E '^\| Mutations ' "$md" | awk -F'|' '{gsub(/ /,"",$3); print $3}')"
  undetected="$(grep -E '^\| Undetected ' "$md" | awk -F'|' '{gsub(/ /,"",$3); print $3}')"
  success="$(grep -E '^\| Success ' "$md" | awk -F'|' '{gsub(/ /,"",$3); print $3}')"
  if [ "${total:-0}" = 0 ]; then info "aucune mutation possible dans ces fichiers (code trivial) — rien à prouver"; return 0; fi
  printf '   mutants : %s, survivants : %s, score : %d%% (seuil %s%%)\n' "$total" "$undetected" $(( (total-undetected)*100/total )) "$thr"
  grep -E '^## Undetected mutations in file' "$md" | sed 's/^## Undetected mutations in file : /   ✗ survivants dans /'
  info "rapport : ${report#$PROJECT_ROOT/}/ — chaque survivant est à tuer ou à expliquer dans mutants.md"
  [ "$success" = true ]
}
