#!/usr/bin/env bash
# Repro — tests ajoutés par Hugo après le gel, et gates stricts qui suivent.
# Cas réels : trois features où l'orchestrateur remplissait hardening.tests_added à la main, une fois oublié, une
# fois en chemins relatifs à la racine au lieu du package : test_freeze_check:strict (green, clean) passait au rouge
# sur les tests de Hugo, et il fallait re-geler.
#   check tests_added (profil harden, donc hook de fin de Hugo) : enregistre lui-même les fichiers ajoutés à test/
#     depuis le gel, relatifs au package (`test/…`), ceux d'un package de writes.extra depuis la racine.
#   pipeline.sh set … hardening.tests_added : un chemin depuis la racine dans le package est ramené au package ;
#     un chemin hors des test/ de la feature est refusé, rien n'est écrit.
source "$(dirname "$0")/fixture.sh"

PIPELINE_SH="$TESTS_DIR/../../pipeline.sh"
R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
F=app/features
P=$F/feat
mk_pkg "$R/$P" feat
mk_pkg "$R/$F/pics" pics
mk_pkg "$R/$F/other" other
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/x
mkdir -p "$R/$P/test/src/data" "$R/$F/pics/test/src/data"
echo "void main() {}" > "$R/$P/test/src/data/frozen_test.dart"
echo "void main() {}" > "$R/$F/pics/test/src/data/frozen_test.dart"
FREEZE="$(commit "$R" "tests (frozen)")"
PJ="{\"mode\":\"extend\",\"package\":\"$P\",\"writes_extra\":[\"$F/pics/**\"],\"tests_freeze_sha\":\"$FREEZE\""
pipeline "$R" x "$PJ}"
PIPE="$R/.claude/features/x/pipeline.json"
added() { jq -c '.hardening.tests_added' "$PIPE"; }

# Hugo : un test commité, un non suivi dans le package, un non suivi dans pics (writes.extra).
echo "void main() {}" > "$R/$P/test/c_mutation_test.dart"
git -C "$R" add "$P/test/c_mutation_test.dart" && git -C "$R" commit -qm "hugo"
echo "void main() {}" > "$R/$P/test/src/data/a_mutation_test.dart"
echo "void main() {}" > "$R/$F/pics/test/src/data/b_mutation_test.dart"

echo "contrôle — sans hardening.tests_added, le gel strict voit les tests de Hugo"
run_g "$R" test_freeze_check:strict x
expect_rc 1 "strict rouge"
expect_out "a_mutation_test.dart" "le test de Hugo est nommé"

echo "harden — tests_added enregistre les ajouts, relatifs au package"
run_g "$R" list
expect_out "harden     test analyze tests_added test_freeze_check:additive mutation" "le profil harden joue tests_added"
run_g "$R" tests_added x
expect_rc 0 "tests_added vert"
OUT="$(added)"
expect_out '["app/features/pics/test/src/data/b_mutation_test.dart","test/c_mutation_test.dart","test/src/data/a_mutation_test.dart"]' \
  "package : test/… ; writes.extra : depuis la racine"
run_g "$R" test_freeze_check:strict x
expect_rc 0 "strict vert après l'enregistrement"
echo "// retouche" >> "$R/$P/test/src/data/frozen_test.dart"
run_g "$R" test_freeze_check:strict x
expect_rc 1 "un test gelé modifié reste rouge"
git -C "$R" checkout -q -- "$P/test/src/data/frozen_test.dart"
rm "$R/$P/test/src/data/a_mutation_test.dart"
run_g "$R" tests_added x
OUT="$(added)"
expect_no_out "a_mutation_test.dart" "un test retiré par Hugo sort de la liste"

echo "pipeline.sh set — chemins depuis la racine"
setp() { OUT="$(cd "$R" && bash "$PIPELINE_SH" set x "$1" "$2" 2>&1)"; RC=$?; }
setp hardening.tests_added "[\"$P/test/src/data/a_mutation_test.dart\",\"$R/$P/test/d_test.dart\",\"$F/pics/test/src/data/b_mutation_test.dart\"]"
expect_rc 0 "set accepte un chemin depuis la racine"
OUT="$(added)"
expect_out '["test/src/data/a_mutation_test.dart","test/d_test.dart","app/features/pics/test/src/data/b_mutation_test.dart"]' \
  "ramené au package (absolu compris), writes.extra gardé"
setp hardening "{\"tests_added\":[\"$P/test/e_test.dart\"]}"
expect_rc 0 "set de hardening entier"
OUT="$(added)"
expect_out '["test/e_test.dart"]' "hardening.tests_added normalisé aussi"
BEFORE="$(cat "$PIPE")"
for bad in "$F/other/test/o_test.dart" "lib/src/x.dart" "../feat/test/x_test.dart" '"pas une liste"'; do
  case "$bad" in \"*) setp hardening.tests_added "$bad" ;; *) setp hardening.tests_added "[\"$bad\"]" ;; esac
  expect_rc 2 "refusé : $bad"
done
expect_out "liste de chemins attendue" "message clair pour une valeur qui n'est pas une liste"
setp hardening.tests_added "[\"lib/src/x.dart\"]"
expect_out "n'est pas un test du package. Attendu : test/… (relatif à $P)" "message clair : le format attendu"
[ "$(cat "$PIPE")" = "$BEFORE" ] && _pass "pipeline.json inchangé après un refus" || _fail "pipeline.json modifié après un refus"

finish
