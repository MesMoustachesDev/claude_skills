#!/usr/bin/env bash
# Repro — feature extend dont le code et les tests vivent aussi dans un autre package, ouvert par writes.extra.
# Cas réel : image_source, extend sur main_page, toute la data/domain dans pictures
# (pipeline.json → writes_extra = pictures/**). Avant le correctif :
#   hook : la moitié data (test-writer-data, implementer-data) n'avait pas accès à pictures, la moitié
#     présentation y avait tout (data comprise) ;
#   gauntlet : tests, red_check et analyze ne tournaient que sur le package principal — red_data rouge
#     (« aucun fichier de test dans le périmètre ») alors que les tests data étaient écrits dans pictures,
#     et green ne prouvait pas pictures ; le gel ne commitait pas pictures/test.
# Attendu : les packages de writes.extra MODIFIÉS par la feature entrent dans ces gates ; une zone permanente du
# projet non touchée (router) ne fait rien tourner ; un package modifié sans test de la feature ne fait pas
# échouer red_check ; hors pipeline (GAUNTLET_PACKAGE) rien ne change.
source "$(dirname "$0")/fixture.sh"
need_fvm

HOOK="$TESTS_DIR/../../../hooks/pipeline-restrict-writes.sh"
PIPELINE_SH="$TESTS_DIR/../../pipeline.sh"
R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R" "writes.extra = app/features/router/**"
F=app/features
P=$F/feat
mk_pkg "$R/$P" feat
mk_pkg "$R/$F/pics" pics
mk_pkg "$R/$F/other" other
mk_pkg "$R/$F/libonly" libonly
mk_pkg "$R/$F/router" router
mkdir -p "$R/$P/lib/src/presentation" "$R/$P/test/src/presentation" "$R/$F/pics/test/src/data" "$R/$F/other/test"
echo "int p() => 1;" > "$R/$P/lib/src/presentation/p.dart"
printf 'void main() {}\n' > "$R/$P/test/src/presentation/old_test.dart"
echo "int d() => 1;" > "$R/$F/pics/lib/src/data/d.dart"
printf 'void main() {}\n' > "$R/$F/pics/test/src/data/old_test.dart"
echo "int o() => 1;" > "$R/$F/other/lib/src/data/o.dart"
# other : modifié (lib) sans test de la feature. Sa suite rouge prouve qu'elle ne tourne pas pour rien.
printf '// FAKE_FAIL\nvoid main() {}\n' > "$R/$F/other/test/o_test.dart"
# router : zone permanente du projet, que la feature ne touche pas. Sa suite rouge prouve qu'elle ne tourne pas.
printf '// FAKE_FAIL\nvoid main() {}\n' > "$R/$F/router/test/r_test.dart"
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/x
PJ='{"mode":"extend","package":"app/features/feat","writes_extra":["app/features/pics/**","app/features/other/**","app/features/libonly/lib/**"]'
pipeline "$R" x "$PJ}"

# Étape 3 : data/domain dans pics, présentation dans feat ; other modifié (lib) sans test de la feature.
printf '// FAKE_FAIL\nvoid main() {}\n' > "$R/$F/pics/test/src/data/new_test.dart"
printf '// FAKE_FAIL\nvoid main() {}\n' > "$R/$P/test/src/presentation/p_test.dart"
echo "int o() => 2;" > "$R/$F/other/lib/src/data/o.dart"

echo "red_data — les tests data de la feature sont dans pics"
run_g "$R" red_data x
expect_rc 0 "red_data vert : pics/test/src/data/new_test.dart est rouge"
expect_out "app/features/pics" "le package pics est jugé"
expect_no_out "app/features/router" "router (zone projet non modifiée) ne tourne pas"
[ -d "$R/.claude/features/x/.gauntlet/data/packages" ] && _pass "sorties de pics dans .gauntlet/data/packages/" || _fail "sorties de package absentes"

echo "red_presentation — feat seul a des tests de présentation de la feature"
run_g "$R" red_presentation x
expect_rc 0 "red_presentation vert"
expect_out "aucun test de la feature dans app/features/pics (couche presentation)" "la suite de pics ne tourne pas pour la moitié présentation"

echo "other — modifié sans test de la feature : analysé, suite non lancée"
run_g "$R" test x
expect_out "app/features/other (writes.extra) : modifié sans test de la feature" "other est nommé"
expect_no_out "o_test" "la suite rouge de other ne tourne pas"
echo "// FAKE_ANALYZE_ERROR" >> "$R/$F/other/lib/src/data/o.dart"
run_g "$R" red_data x
expect_rc 1 "red_data rouge : other ne compile plus"
expect_out "o.dart" "le fichier de other est nommé"
echo "int o() => 2;" > "$R/$F/other/lib/src/data/o.dart"

echo "red — gate complet, tests.md"
run_g "$R" red x
expect_rc 0 "red vert"
expect_file_has "$R/.claude/features/x/tests.md" "app/features/pics/test/src/data/new_test.dart" "tests.md liste le test de pics"
grep -q "old_test" "$R/.claude/features/x/tests.md" && grep -q "app/features/pics/test/src/data/old_test" "$R/.claude/features/x/tests.md" \
  && _fail "tests.md liste un test préexistant de pics" || _pass "tests.md ne liste de pics que les tests de la feature"

echo "red_data — un test de pics tout vert reste bloquant"
printf 'void main() {}\n' > "$R/$F/pics/test/src/data/new_test.dart"
run_g "$R" red_data x
expect_rc 1 "red_data rouge"
expect_out "tout vert : test/src/data/new_test.dart" "le fichier de pics est nommé"

echo "red_data — une erreur de compilation dans pics bloque"
printf '// FAKE_FAIL\n// FAKE_ANALYZE_ERROR\nvoid main() {}\n' > "$R/$F/pics/test/src/data/new_test.dart"
run_g "$R" red_data x
expect_rc 1 "red_data rouge (analyze)"
expect_out "new_test.dart" "le fichier fautif est nommé"
printf '// FAKE_FAIL\nvoid main() {}\n' > "$R/$F/pics/test/src/data/new_test.dart"

echo "contrôle — sans la zone pics, red_data n'a plus de test de la feature"
pipeline "$R" x '{"mode":"extend","package":"app/features/feat"}'
run_g "$R" red_data x
expect_rc 1 "red_data rouge, un seul package (comportement inchangé)"
expect_out "aucun test exécuté" "message d'origine"
pipeline "$R" x "$PJ}"

echo "freeze — pics/test est gelé avec le package"
OUT="$(cd "$R" && bash "$PIPELINE_SH" freeze x 2>&1)"; RC=$?
expect_rc 0 "pipeline.sh freeze"
SHA="$(jq -r .tests_freeze_sha "$R/.claude/features/x/pipeline.json")"
OUT="$(git -C "$R" show --name-only --format= "$SHA")"
expect_out "app/features/pics/test/src/data/new_test.dart" "le gel commite le test de pics"
expect_out "app/features/feat/test/src/presentation/p_test.dart" "le gel commite le test de feat"
expect_no_out "other/lib" "le gel ne commite pas de lib/"

echo "green — la suite de pics fait partie du gate"
run_g "$R" test x
expect_rc 1 "test rouge tant que pics est rouge"
expect_out "new_test" "le test rouge de pics est nommé"
# Implémentation simulée : le fake lit le marqueur dans le test, on le retire et on re-gèle.
sed -i '' 's#// FAKE_FAIL#// impl verte#' "$R/$F/pics/test/src/data/new_test.dart" "$R/$P/test/src/presentation/p_test.dart"
git -C "$R" commit -qam "impl verte"
pipeline "$R" x "$PJ,\"tests_freeze_sha\":\"$(git -C "$R" rev-parse HEAD)\"}"
run_g "$R" test x
expect_rc 0 "test vert"
run_g "$R" green_data x
expect_rc 0 "green_data vert"

echo "test_freeze_check — pics/test est surveillé"
run_g "$R" test_freeze_check:strict x
expect_rc 0 "gel respecté"
echo "// retouche" >> "$R/$F/pics/test/src/data/new_test.dart"
run_g "$R" test_freeze_check:strict x
expect_rc 1 "test de pics modifié après le gel : rouge"
expect_out "app/features/pics/test/src/data/new_test.dart" "le fichier est nommé"
printf 'void main() {}\n' > "$R/$F/pics/test/src/data/extra_test.dart"
run_g "$R" test_freeze_check:additive x
expect_rc 1 "additive : une modification reste refusée"
git -C "$R" checkout -q -- "$F/pics/test/src/data/new_test.dart"
run_g "$R" test_freeze_check:additive x
expect_rc 0 "additive : un fichier ajouté dans pics est toléré"
rm "$R/$F/pics/test/src/data/extra_test.dart"

echo "hors pipeline — GAUNTLET_PACKAGE : aucun package supplémentaire"
printf '// FAKE_FAIL\nvoid main() {}\n' > "$R/$F/pics/test/src/data/new_test.dart"
OUT="$(cd "$R" && GAUNTLET_PACKAGE=$P bash "$GAUNTLET" test x 2>&1)"; RC=$?
expect_rc 0 "test vert : pics ignoré sous GAUNTLET_PACKAGE"
git -C "$R" checkout -q -- "$F/pics/test/src/data/new_test.dart"

# hook_write <agent> <fichier> — décision du hook dans $OUT ("deny…" ou vide)
hook_write() {
  OUT="$(jq -n --arg a "$1" --arg c "$R" --arg f "$R/$2" \
    '{agent_type:$a, cwd:$c, tool_name:"Edit", tool_input:{file_path:$f}}' | bash "$HOOK" 2>&1)"
}
echo "hook — la couche data des packages de writes.extra va à la moitié data"
hook_write feature-test-writer-data "$F/pics/test/src/data/x_test.dart";             expect_no_out deny "tests data : pics/test/src/data"
hook_write feature-test-writer-data "$F/pics/test/src/injection/x_test.dart";        expect_no_out deny "tests data : pics/test/src/injection"
hook_write feature-test-writer-data "$F/libonly/test/src/domain/x_test.dart";        expect_no_out deny "tests data : <pkg>/lib/** ouvre aussi sa couche data de test"
hook_write feature-test-writer-data "$F/pics/test/acceptance/x_test.dart";           expect_out deny "tests data : refus pics/test/acceptance"
hook_write feature-test-writer-data "$F/pics/pubspec.yaml";                          expect_out deny "tests data : refus pubspec de pics"
hook_write feature-test-writer-data "$P/test/src/data/x_test.dart";                  expect_no_out deny "tests data : package principal inchangé"
hook_write feature-test-writer-presentation "$F/pics/test/src/domain/x_test.dart";   expect_out deny "tests présentation : refus pics/test/src/domain"
hook_write feature-test-writer-presentation "$F/pics/test/acceptance/x_test.dart";   expect_no_out deny "tests présentation : pics/test/acceptance"
hook_write feature-implementer-data "$F/pics/lib/src/data/x.dart";                   expect_no_out deny "impl data : pics/lib/src/data"
hook_write feature-implementer-data "$F/libonly/lib/src/domain/x.dart";              expect_no_out deny "impl data : libonly/lib/src/domain"
hook_write feature-implementer-data "$F/router/lib/src/data/x.dart";                 expect_no_out deny "impl data : zone projet router/** (package)"
hook_write feature-implementer-data "$F/pics/lib/src/presentation/x.dart";           expect_out deny "impl data : refus pics/lib/src/presentation"
hook_write feature-implementer-data "$F/pics/test/src/data/new_test.dart";           expect_out "GELÉS" "impl data : tests de pics gelés"
hook_write feature-implementer-presentation "$F/pics/lib/src/domain/x.dart";         expect_out deny "impl présentation : refus pics/lib/src/domain"
hook_write feature-implementer-presentation "$F/router/lib/src/data/x.dart";         expect_out deny "impl présentation : refus router/lib/src/data"
hook_write feature-implementer-presentation "$F/pics/lib/src/presentation/x.dart";   expect_no_out deny "impl présentation : pics/lib/src/presentation"
hook_write feature-implementer-presentation "$F/router/lib/r.dart";                  expect_no_out deny "impl présentation : reste de router"
hook_write feature-implementer "$F/pics/lib/src/data/x.dart";                        expect_no_out deny "implementer complet : inchangé"
hook_write feature-test-writer "$F/pics/test/src/data/x_test.dart";                  expect_no_out deny "test-writer complet : inchangé"

finish
