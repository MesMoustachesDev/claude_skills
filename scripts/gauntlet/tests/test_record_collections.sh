#!/usr/bin/env bash
# Repro — test_hygiene : un record comparé par == ne contient pas de Map, List ou Set. Le == d'un record compare
# chaque champ avec ==, et celui d'une collection compare l'identité : deux Map de même contenu sont différentes.
# Cas réel : add_floors_wizard_page_test.dart (feature name_on_creation), `assignments: {1: image}` dans le
# record attendu. Le test était rouge contre une implémentation juste, gelé, et a coûté un re-gel.
# Le motif revenait à presque chaque feature.
source "$(dirname "$0")/fixture.sh"
need_fvm

R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
P=app/features/feat
mk_pkg "$R/$P" feat
mkdir -p "$R/$P/test"
cat > "$R/$P/test/feat_test.dart" <<'EOF'
void main() {
  test('existing', () {
    expect((a: 1, b: [2]), (a: 1, b: [2]));
  });
}
EOF
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/x
pipeline "$R" x '{"mode":"extend","package":"app/features/feat"}'

echo "test_hygiene — record préexistant"
run_g "$R" test_hygiene x
expect_rc 0 "vert : la dette existante n'est pas jugée"

echo "test_hygiene — records ajoutés par la feature"
cat >> "$R/$P/test/feat_test.dart" <<'EOF'

void more() {
  testWidgets('finish', (tester) async {
    await open(tester, step3(assignments: {1: image}, names: const {0: 'RDC'}));
    expect(
      (
        closed: popped.closed,
        count: popped.result?.count,
      ),
      (
        closed: true,
        assignments: {1: image},
        names: const {0: 'RDC'},
        tags: <String>['a'],
        label: foo(items: [1]),
        set: <int>{},
      ),
    );
    expect(popped.result?.assignments, {1: image});
  });
}
EOF
run_g "$R" test_hygiene x
expect_rc 1 "rouge"
expect_out "feat_test.dart:17:        assignments: {1: image}," "Map dans un record"
expect_out "feat_test.dart:18:        names: const {0: 'RDC'}," "Map const aussi (identité selon d'où vient la valeur)"
expect_out "feat_test.dart:19:        tags: <String>['a']," "List typée"
expect_out "feat_test.dart:21:        set: <int>{}," "Set typé"
expect_no_out "feat_test.dart:9:" "argument nommé d'un appel : pas un record"
expect_no_out "feat_test.dart:20:" "collection en argument d'un appel dans le record"
expect_no_out "feat_test.dart:24:" "expect à part : comparaison profonde"
expect_no_out "feat_test.dart:3:" "le record préexistant reste de la dette"

finish
