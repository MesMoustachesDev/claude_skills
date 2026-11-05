#!/usr/bin/env bash
# Repro — test_plan : la liste décidée avant les tests. Refusée si un item de la spec n'est ni prouvé ni
# écarté, si un scénario n'a pas son test d'acceptation, si un test ne prouve rien ou est mal formé.
# test_plan_match (gate red) : un test écrit hors liste, ou prévu et pas écrit, rougit ; les tests qui
# existaient sur develop ne comptent pas.
source "$(dirname "$0")/fixture.sh"
need_fvm

R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
P=app/features/feat
mk_pkg "$R/$P" feat
mkdir -p "$R/$P/test/src/data"
cat > "$R/$P/test/src/data/old_test.dart" <<'DART'
void main() {
  test('an old behaviour', () {});
}
DART
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/x
pipeline "$R" x "{\"mode\":\"extend\",\"package\":\"$P\"}"
FD="$R/.claude/features/x"
cat > "$FD/spec.md" <<'MD'
# Spec — x
## 4. Scénarios d'acceptation (Gherkin)
```gherkin
Feature: x
  Scenario: shows the list
  Scenario: shows an error when offline
```
## 5. Contrats
| Contrat | Fichier |
|---|---|
| `GetX.call` | lib/src/domain/get_x.dart |
| `XKeys` | lib/src/presentation/keys.dart |
## 6. Données
| Champ | Absent | Règle |
|---|---|---|
| `name` | sauté | String |
## 7. Erreurs
| Erreur | Origine | Comportement UI | Retry | Scénario |
|---|---|---|---|---|
| Réseau | data source | message | oui | C2 |
MD
plan() { printf '%s\n' "$1" > "$FD/tests_plan.json"; }
T="$P/test/src/data/x_mapper_test.dart"; A="$P/test/x.feature"
GOOD='{"tests":[
 {"file":"'$A'","name":"shows the list","layer":"acceptance","proves":["S1","K1"]},
 {"file":"'$A'","name":"shows an error when offline","layer":"acceptance","proves":["S2","E1"]},
 {"file":"'$T'","name":"skips an item without name","layer":"mapper","proves":["D1"]}],
 "not_tested":[{"items":["K2"],"why":"keys : utilisées par S1 et S2"}]}'

echo "test_plan — items numérotés"
OUT="$(python3 "$TESTS_DIR/../test_plan.py" items "$FD/spec.md")"
expect_out "S2	§4	shows an error when offline" "scénarios"
expect_out "K2	§5	\`XKeys\`" "contrats"
expect_out "D1	§6	\`name\`" "données"
expect_out "E1	§7	Réseau" "erreurs"

echo "test_plan — liste suffisante : verte"
plan "$GOOD"
run_g "$R" test_plan x
expect_rc 0 "verte"
expect_out "liste : 3 tests (2 scénarios), 6 items, 1 écartés" "résume la liste"

echo "test_plan — un item oublié"
plan "${GOOD%%\"not_tested\"*}\"not_tested\":[]}"
run_g "$R" test_plan x
expect_rc 1 "rouge"
expect_out "K2 §5" "nomme l'item oublié"

echo "test_plan — scénario sans test d'acceptation"
plan "$(sed 's/"proves":\["S1","K1"\]/"proves":["K1"]/; s/"name":"skips an item without name","layer":"mapper","proves":\["D1"\]/"name":"skips an item without name","layer":"mapper","proves":["D1","S1"]/' <<<"$GOOD")"
run_g "$R" test_plan x
expect_rc 1 "rouge"
expect_out "scénario sans test d'acceptation" "le dit"

echo "test_plan — un test qui ne prouve rien"
plan "$(sed 's/"proves":\["D1"\]/"proves":[]/' <<<"$GOOD")"
run_g "$R" test_plan x
expect_rc 1 "rouge"
expect_out "proves vide" "le dit"

echo "test_plan — item inconnu, hors package : refusés"
plan "$(sed 's/"proves":\["D1"\]/"proves":["D9"]/' <<<"$GOOD")"
run_g "$R" test_plan x
expect_rc 1 "item inconnu"
expect_out "items inconnus ['D9']" "le nomme"
plan "$(sed "s#$T#app/other/test/x_test.dart#" <<<"$GOOD")"
run_g "$R" test_plan x
expect_rc 1 "fichier hors package"

echo "test_plan_match — pas de liste"
mv "$FD/tests_plan.json" "$FD/tests_plan.json.bak"
run_g "$R" test_plan_match x
expect_rc 0 "feature commencée avant l'étape 3a : rien à comparer"
pipeline "$R" x "{\"mode\":\"extend\",\"package\":\"$P\",\"stages\":{\"test_plan\":{\"status\":\"RED\"}}}"
run_g "$R" test_plan_match x
expect_rc 1 "feature passée par 3a : la liste manque"
expect_out "tests_plan.json absent" "le dit"
mv "$FD/tests_plan.json.bak" "$FD/tests_plan.json"

echo "test_plan_match — la suite écrite est la liste"
plan "$GOOD"
cat > "$R/$A" <<'G'
Feature: x
  Scenario: shows the list
  Scenario: shows an error when offline
G
cat > "$R/$T" <<'DART'
void main() {
  test(
    'skips an item without name',
    () {},
  );
}
DART
run_g "$R" test_plan_match x
expect_rc 0 "conforme (le test de develop ne compte pas)"

echo "test_plan_match — un test hors liste, un test manquant"
cat >> "$R/$P/test/src/data/old_test.dart" <<'DART'
void more() {
  test('a new test nobody planned', () {});
}
DART
sed -i '' '/Scenario: shows an error when offline/d' "$R/$A"
run_g "$R" test_plan_match x
expect_rc 1 "rouge"
expect_out "écrit, pas prévu : $P/test/src/data/old_test.dart — a new test nobody planned" "le test hors liste"
expect_out "prévu, pas écrit : $A — shows an error when offline" "le scénario manquant"
expect_no_out "an old behaviour" "un test de develop n'est jamais hors liste"

finish
