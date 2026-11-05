#!/usr/bin/env bash
# Repro — prune : un test qui ne couvre rien de plus est retiré ; celui qui seul couvre une ligne de lib/ est
# gardé ; un lot qui perd quelque chose est coupé jusqu'au candidat fautif ; une liste mal formée est refusée
# entière, sans rien toucher. Sans mutation (--no-mutation) : la couverture simulée suffit à la décision.
source "$(dirname "$0")/fixture.sh"
need_fvm

R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
P=app/features/feat
mk_pkg "$R/$P" feat
mkdir -p "$R/$P/test/src/data"
T="$P/test/src/data/repo_test.dart"
cat > "$R/$T" <<'DART'
void main() {
  test('maps a text', () {
    expect(map('a'), 'A'); // COVERS lib/src/data/repo.dart:3
  });

  test('maps another text', () {
    expect(map('b'), 'B'); // COVERS lib/src/data/repo.dart:3
  });

  test(
    'maps an empty text (with parentheses)',
    () {
      expect(map(''), ''); // COVERS lib/src/data/repo.dart:7
    },
  );

  test('maps a text, again', () {
    expect(map('c'), 'C'); // COVERS lib/src/data/repo.dart:3
  });
}
DART
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/x
pipeline "$R" x "{\"mode\":\"create\",\"package\":\"$P\"}"
C="$R/.claude/features/x/prune_candidates.json"
cand() { printf '{"file":"%s","line":%s,"name":"%s","kind":"variante","proved_by":"%s:2","why":"même branche"}' "$T" "$1" "$2" "$T"; }

echo "prune — liste mal formée : refusée entière, rien n'est touché"
printf '{"candidates":[%s,{"file":"/etc/passwd","line":1,"name":"x","kind":"variante","proved_by":"-","why":"-"}]}\n' \
  "$(cand 6 'maps another text')" > "$C"
run_g "$R" prune x "$C" --no-mutation
expect_rc 2 "refusée"
expect_out "liste refusée" "dit pourquoi"
OUT="$(git -C "$R" status --short -- "$P")"; expect_no_out "repo_test.dart" "le fichier de test est intact"

echo "prune — kind inconnu : refusé"
printf '{"candidates":[%s]}\n' "$(cand 6 'maps another text' | sed 's/variante/autre/')" > "$C"
run_g "$R" prune x "$C" --no-mutation
expect_rc 2 "refusée"
expect_out "kind" "nomme le champ fautif"

echo "prune — deux redondants gardés retirés, celui qui couvre seul la ligne 7 reste"
printf '{"candidates":[%s,%s,%s]}\n' "$(cand 6 'maps another text')" "$(cand 11 'maps an empty text (with parentheses)')" \
  "$(cand 17 'maps a text, again')" > "$C"
run_g "$R" prune x "$C" --no-mutation
expect_rc 0 "élagage joué"
expect_out "2 retirés, 1 gardés" "le lot fautif est coupé jusqu'au candidat"
F="$R/$T"
OUT="$(cat "$F")"
expect_out "'maps a text'" "le premier test reste"
expect_out "maps an empty text (with parentheses)" "le test qui couvre seul la ligne 7 reste"
expect_no_out "maps another text" "le redondant est retiré"
expect_no_out "maps a text, again" "le second redondant est retiré"
expect_out "});
}" "le fichier reste bien formé"
R2="$R/.claude/features/x/prune_candidates.result.json"
expect_file_has "$R2" "ligne(s) de lib/ plus couvertes" "le verdict du gardé dit ce qu'il perdrait"
OUT="$(git -C "$R" log --oneline feature/x)"; expect_no_out "prune" "rien n'est commité"

finish
