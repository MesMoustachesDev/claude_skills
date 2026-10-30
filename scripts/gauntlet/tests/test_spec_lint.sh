#!/usr/bin/env bash
# Repro — spec_lint, gate de Sophie avant la critique de Camille.
# Cas réel : refactor_feature, première critique — la clé 'editor_stroke_preview' absente de
# keys.dart, et « écriture des préférences en échec » sans scénario : deux bloquants qu'un script trouve.
source "$(dirname "$0")/fixture.sh"
need_fvm

R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
P=app/features/feat
mk_pkg "$R/$P" feat
mkdir -p "$R/$P/lib/src/presentation" "$R/$P/lib/src/domain"
cat > "$R/$P/lib/src/presentation/keys.dart" <<'EOF'
class FeatKeys {
  static const String page = 'feat_page';
  static const String save = 'feat_save_button';
  static const String swatchPrefix = 'feat_swatch_';
}
EOF
cat > "$R/$P/lib/src/domain/repo.dart" <<'EOF'
abstract interface class FeatRepository {
  Future<int> load();
}
EOF
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/x
pipeline "$R" x "{\"mode\":\"create\",\"package\":\"$P\",\"size\":\"M\"}"
F="$R/.claude/features/x"

spec() {  # spec <ligne §7> <clé citée> <symbole §5> <membre>
  cat > "$F/spec.md" <<EOF
# Spec — x
## 4. Scénarios
  Scenario: saves the drawing
    When I tap {'feat_save_button'}
    Then I see {'$2'} and {'feat_swatch_3'}
## 5. Contrats
| Symbole | Sert |
|---|---|
| \`$3\`, \`FeatKeys\`, \`Either\` | C1 |
## 6. Données
\`FeatRepository.$4\` rend le nombre ; \`TextStyle.copyWith\` est du SDK.
## 7. Erreurs
| Erreur | Origine | Comportement UI | Retry | Scénario |
|---|---|---|---|---|
| lecture en échec | data source | message | oui | C1 |
$1
## 8. Architecture
EOF
}
printf '{"sequences":[{"id":"C1","scenario":"saves the drawing"}]}\n' > "$F/archi.json"

echo "spec propre"
spec "| écriture en échec | data source | rien | non | hors scénario : jamais visible |" feat_page FeatRepository load
run_g "$R" spec_lint x
expect_rc 0 "vert (clé à préfixe, type du SDK, classe hors workspace ignorés)"

echo "les deux bloquants d'refactor_feature"
spec "| écriture en échec | data source | rien | non | |" feat_stroke_preview FeatRepository load
run_g "$R" spec_lint x
expect_rc 1 "rouge"
expect_out "'feat_stroke_preview'" "clé absente de keys.dart"
expect_out "« écriture en échec » ne cite aucun scénario" "erreur de §7 sans scénario"

echo "symboles, archi.json, exemption"
spec "" feat_page FeatRepositry load
run_g "$R" spec_lint x
expect_out "§5 cite \`FeatRepositry\`" "symbole de §5 introuvable (faute de frappe)"
spec "" feat_page FeatRepository fetch
run_g "$R" spec_lint x
expect_out "pas de membre fetch" "membre absent d'une classe du workspace"
printf '{"sequences":[{"id":"C1","scenario":"saves the picture"}]}\n' > "$F/archi.json"
run_g "$R" spec_lint x
expect_out "C1 pointe vers « saves the picture »" "titre d'archi.json absent de §4"
printf '{"sequences":[{"id":"C1","scenario":"saves the drawing"}]}\n' > "$F/archi.json"
spec "" feat_stroke_preview FeatRepository load
echo "<!-- spec_lint: ignore feat_stroke_preview -->" >> "$F/spec.md"
run_g "$R" spec_lint x
expect_rc 0 "jeton marqué spec_lint: ignore (contrat à revoir) : vert"

echo "plafond du gabarit et cadrage"
pipeline "$R" x "{\"mode\":\"create\",\"package\":\"$P\",\"size\":\"S\"}"
head -c 16000 /dev/zero | tr '\0' 'a' >> "$F/spec.md"
run_g "$R" spec_lint x
expect_out "plafond du gabarit 15360" "spec au-delà de 15 Kio en S"
rm "$F/spec.md"
run_g "$R" spec_lint x
expect_rc 0 "pas encore de spec.md (cadrage, exploration) : vert"

finish
