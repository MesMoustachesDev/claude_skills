#!/usr/bin/env bash
# fake_flutter.sh — remplace `flutter` dans les tests du gauntlet.
#   --version            → une ligne
#   test --reporter json → un rapport JSON par fichier test/**/*_test.dart du dossier courant, un test par
#                          fichier ; le test échoue si le fichier contient FAKE_FAIL. Exit 1 si un échec.
case "${1:-}" in
  --version) echo "Flutter fake (gauntlet tests)"; exit 0 ;;
  test) ;;
  *) exit 0 ;;
esac
id=0 rc=0
while IFS= read -r f; do
  id=$((id+1))
  abs="$PWD/$f"
  result=success; grep -q FAKE_FAIL "$f" && { result=failure; rc=1; }
  printf '{"type":"suite","suite":{"id":%d,"path":"%s"}}\n' "$id" "$abs"
  printf '{"type":"testStart","test":{"id":%d,"name":"%s","suiteID":%d,"url":"file://%s"}}\n' "$id" "$(basename "$f" .dart)" "$id" "$abs"
  printf '{"type":"testDone","testID":%d,"result":"%s","hidden":false,"skipped":false}\n' "$id" "$result"
done < <(find test -name '*_test.dart' 2>/dev/null | sort)
exit $rc
