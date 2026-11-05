#!/usr/bin/env bash
# fake_flutter.sh — remplace `flutter` dans les tests du gauntlet.
#   --version            → une ligne
#   test --reporter json → un rapport JSON par fichier test/**/*_test.dart du dossier courant, un test par
#                          fichier ; le test échoue si le fichier contient FAKE_FAIL. Exit 1 si un échec.
#                          Des chemins en argument (gauntlet par couche) → ces fichiers seulement.
#   analyze              → FAKE_ANALYZE_ERROR dans un fichier analysé = erreur de compilation (les chemins en
#                          argument, sinon lib/ et test/) ; FAKE_ANALYZE_INFO = un lint (info), exit 1
case "${1:-}" in
  --version) echo "Flutter fake (gauntlet tests)"; exit 0 ;;
  test|analyze) ;;
  *) exit 0 ;;
esac
cmd="$1"; shift
paths=() coverage=""
while [ $# -gt 0 ]; do
  case "$1" in --reporter) shift ;; --coverage) coverage=1 ;; -*) ;; *) paths+=("$1") ;; esac
  shift
done
if [ "$cmd" = analyze ]; then
  [ ${#paths[@]} -gt 0 ] || paths=(lib test)
  hits="$(grep -rl FAKE_ANALYZE_ERROR "${paths[@]}" 2>/dev/null)"
  infos="$(grep -rl FAKE_ANALYZE_INFO "${paths[@]}" 2>/dev/null)"
  [ -z "$hits$infos" ] && { echo "No issues found!"; exit 0; }
  [ -n "$hits" ] && printf '  error • fake compile error • %s:1:1 • fake\n' $hits
  [ -n "$infos" ] && printf '   info • Cascade consecutive method invocations • %s:1:1 • cascade_invocations\n' $infos
  exit 1
fi
id=0 rc=0
while IFS= read -r f; do
  id=$((id+1))
  abs="$PWD/$f"
  result=success; grep -q FAKE_FAIL "$f" && { result=failure; rc=1; }
  printf '{"type":"suite","suite":{"id":%d,"path":"%s"}}\n' "$id" "$abs"
  printf '{"type":"testStart","test":{"id":%d,"name":"%s","suiteID":%d,"url":"file://%s"}}\n' "$id" "$(basename "$f" .dart)" "$id" "$abs"
  printf '{"type":"testDone","testID":%d,"result":"%s","hidden":false,"skipped":false}\n' "$id" "$result"
done < <(if [ ${#paths[@]} -gt 0 ]; then printf '%s\n' "${paths[@]}"; else find test -name '*_test.dart' 2>/dev/null | sort; fi)
if [ -n "$coverage" ]; then
  mkdir -p coverage
  grep -rhoE 'COVERS [^ ]+:[0-9]+' test 2>/dev/null | sort -u \
    | awk '{ split($2, a, ":"); print "SF:" a[1]; print "DA:" a[2] ",1"; print "end_of_record" }' > coverage/lcov.info
fi
exit $rc
