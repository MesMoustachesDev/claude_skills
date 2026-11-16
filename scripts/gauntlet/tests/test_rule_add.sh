#!/usr/bin/env bash
# Repro — rule_add.py --after "<puce>" insérait après la PREMIÈRE ligne d'une puce sur plusieurs lignes : la
# règle ajoutée coupait la puce en deux (cas réel : la puce « Compose : état hissé… » des règles Android,
# coupée par deux règles de learn).
#   --after sur une puce de deux lignes : la règle va après sa ligne de suite ;
#   --after sur une ligne indentée suivie de sœurs au même retrait : la règle va juste après elle.
source "$(dirname "$0")/fixture.sh"

RULE_ADD="$TESTS_DIR/../../rule_add.py"
H="$TMP_ROOT/home"; mk_repo "$H/.claude"
F="$H/.claude/rules.md"
cat > "$F" <<'MD'
# Règles
- Compose : état hissé, pas de
  calcul lourd dans la composition.

## Ensuite
<!--
  Ligne A du commentaire.
  Ligne B du commentaire.
-->
MD
commit "$H/.claude" init >/dev/null

echo "puce sur deux lignes"
OUT="$(HOME="$H" python3 "$RULE_ADD" "$F" "- Nouvelle règle." --after "Compose : état hissé" 2>&1)"; RC=$?
expect_rc 0 "rule_add"
OUT="$(sed -n 2,4p "$F")"
[ "$OUT" = "$(printf -- '- Compose : état hissé, pas de\n  calcul lourd dans la composition.\n- Nouvelle règle.')" ] \
  && _pass "la règle suit la ligne de suite, la puce reste entière" || _fail "puce coupée par la règle"

echo "ligne indentée suivie de sœurs"
OUT="$(HOME="$H" python3 "$RULE_ADD" "$F" "  Ligne A2." --after "Ligne A du commentaire" 2>&1)"; RC=$?
expect_rc 0 "rule_add"
OUT="$(grep -n 'Ligne A2' "$F")"
expect_out "9:" "la règle va juste après la ligne visée"
finish
