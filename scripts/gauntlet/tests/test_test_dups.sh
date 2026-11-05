#!/usr/bin/env bash
# Repro — test_dups : un même nom de test dans deux fichiers est listé comme candidat doublon pour Gaëlle,
# sans bloquer ; un nom qui n'en contient qu'un autre n'est pas pris pour lui ; « doublon voulu » l'écarte.
source "$(dirname "$0")/fixture.sh"
need_fvm

R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
P=app/features/feat
mk_pkg "$R/$P" feat
mkdir -p "$R/$P/test/src/data" "$R/$P/test/src/domain"
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/x
pipeline "$R" x "{\"mode\":\"create\",\"package\":\"$P\"}"

cat > "$R/$P/test/src/data/repo_test.dart" <<'EOF'
void main() {
  test('propagates the error when the photo cannot be read', () {});
  test('maps every field', () {});
  testWidgets(
    'shows the empty state',
    (tester) async {},
  );
}
EOF
cat > "$R/$P/test/src/domain/use_case_test.dart" <<'EOF'
void main() {
  test('propagates the error when the photo cannot be read', () {});
  test('maps every field of a text', () {});
  testWidgets('shows the empty state', (tester) async {}); // doublon voulu : écran et feuille
}
EOF

echo "test_dups — liste les noms en double, ne bloque pas"
run_g "$R" test_dups x
expect_rc 0 "le check ne bloque jamais"
expect_out "1 nom(s) de test en double" "un seul nom retenu"
D="$R/.claude/features/x/.gauntlet/test_dups.txt"
expect_file_has "$D" "test/src/data/repo_test.dart:2: propagates the error when the photo cannot be read" "occurrence du repository"
expect_file_has "$D" "test/src/domain/use_case_test.dart:2: propagates the error" "occurrence du use case"
OUT="$(cat "$D")"
expect_no_out "maps every field" "un nom contenu dans un autre n'est pas un doublon"
expect_no_out "shows the empty state" "« doublon voulu » écarte le nom"

echo "test_dups — rien en double"
rm "$R/$P/test/src/domain/use_case_test.dart"
run_g "$R" test_dups x
expect_rc 0 "vert"
expect_out "aucun nom de test en double" "dit qu'il n'y a rien"

finish
