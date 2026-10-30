#!/usr/bin/env bash
# Repro — étapes 3 et 4 en deux moitiés parallèles (data/domain, présentation) sur le même package.
#   red_<couche> / green_<couche> : chaque check ne juge que la couche ; un fichier que l'autre moitié écrit
#     en même temps (test rouge, stub, erreur de compilation) ne bloque pas.
#   sorties dans .gauntlet/<couche>/ : deux gauntlets simultanés n'écrasent pas le rapport de l'autre.
#   hook pipeline-restrict-writes : chaque moitié n'écrit que sa couche.
#   pipeline.sh join : refuse tant qu'une moitié n'est pas verte, puis joue le gate complet.
source "$(dirname "$0")/fixture.sh"
need_fvm

HOOK="$TESTS_DIR/../../../hooks/pipeline-restrict-writes.sh"
PIPELINE_SH="$TESTS_DIR/../../pipeline.sh"
R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R" "writes.extra = app/features/router/**"
P=app/features/feat
mk_pkg "$R/$P" feat
mkdir -p "$R/$P/lib/src/domain" "$R/$P/lib/src/presentation" "$R/$P/test/src/data" "$R/$P/test/src/presentation"
echo "int d() => 1;" > "$R/$P/lib/src/data/d.dart"
echo "int p() => throw UnimplementedError();" > "$R/$P/lib/src/presentation/p.dart"
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/x
pipeline "$R" x "{\"mode\":\"create\",\"package\":\"$P\"}"

# Étape 3 : la moitié data a fini (rouge pour la bonne raison) ; la présentation est en cours d'écriture.
printf '// FAKE_FAIL\nvoid main() {}\n' > "$R/$P/test/src/data/d_test.dart"
printf '// FAKE_ANALYZE_ERROR\nvoid main() {}\n' > "$R/$P/test/src/presentation/p_test.dart"

echo "red_data — la moitié présentation en cours ne bloque pas"
run_g "$R" red_data x
expect_rc 0 "red_data vert malgré un fichier de présentation qui ne compile pas"
expect_out "couche data" "le périmètre annonce la couche"
[ -f "$R/.claude/features/x/.gauntlet/data/last_red_data.log" ] && _pass "log dans .gauntlet/data/" || _fail "log de couche absent"
[ -f "$R/.claude/features/x/.gauntlet/last_red_data.log" ] && _fail "log écrit à la racine de .gauntlet/" || _pass "rien à la racine de .gauntlet/"

echo "red_presentation — sa propre erreur la bloque"
run_g "$R" red_presentation x
expect_rc 1 "red_presentation rouge sur sa propre erreur de compilation"
expect_out "p_test.dart" "le fichier fautif est nommé"
printf '// FAKE_FAIL\nvoid main() {}\n' > "$R/$P/test/src/presentation/p_test.dart"
run_g "$R" red_presentation x
expect_rc 0 "red_presentation vert une fois sa couche rouge pour la bonne raison"

echo "red_data — un fichier de test de la couche tout vert reste bloquant"
printf 'void main() {}\n' > "$R/$P/test/src/data/d_test.dart"
run_g "$R" red_data x
expect_rc 1 "red_data rouge : le fichier de la couche ne teste rien"
printf '// FAKE_FAIL\nvoid main() {}\n' > "$R/$P/test/src/data/d_test.dart"

# Gel, puis étape 4 : la moitié data a fini, la présentation a encore son stub et son test rouge.
SHA="$(commit "$R" "tests (frozen)")"
pipeline "$R" x "{\"mode\":\"create\",\"package\":\"$P\",\"tests_freeze_sha\":\"$SHA\"}"
sed -i '' 's#// FAKE_FAIL#// impl verte#' "$R/$P/test/src/data/d_test.dart"
git -C "$R" commit -qam "data vert (test réécrit pour la fixture : le fake lit le marqueur)"
SHA="$(git -C "$R" rev-parse HEAD)"
pipeline "$R" x "{\"mode\":\"create\",\"package\":\"$P\",\"tests_freeze_sha\":\"$SHA\"}"

echo "green_data — stub et test rouge de la présentation ignorés"
run_g "$R" green_data x
expect_rc 0 "green_data vert"
run_g "$R" green_presentation x
expect_rc 1 "green_presentation rouge"
expect_out "p.dart" "son stub est nommé"
expect_no_out "d_test" "le test data n'y apparaît pas"

echo "join — refuse tant qu'une moitié n'est pas verte"
pipeline "$R" x "{\"mode\":\"create\",\"package\":\"$P\",\"tests_freeze_sha\":\"$SHA\",\"stages\":{\"green_data\":{\"status\":\"PASSED\"},\"green_presentation\":{\"status\":\"RED\"}}}"
OUT="$(cd "$R" && bash "$PIPELINE_SH" join x green 2>&1)"; RC=$?
expect_rc 1 "join refuse"
expect_out "green_presentation (RED)" "la moitié rouge est nommée"
OUT="$(jq -r '.stages.green // "absent"' "$R/.claude/features/x/pipeline.json")"
expect_out "absent" "stages.green non écrit"

echo "join — les deux vertes, le gate complet tranche"
echo "int p() => 2;" > "$R/$P/lib/src/presentation/p.dart"
sed -i '' 's#// FAKE_FAIL#// impl verte#' "$R/$P/test/src/presentation/p_test.dart"
git -C "$R" commit -qam "présentation verte"
SHA="$(git -C "$R" rev-parse HEAD)"
pipeline "$R" x "{\"mode\":\"create\",\"package\":\"$P\",\"tests_freeze_sha\":\"$SHA\",\"stages\":{\"green_data\":{\"status\":\"PASSED\"},\"green_presentation\":{\"status\":\"SKIPPED\",\"reason\":\"test\"}}}"
OUT="$(cd "$R" && bash "$PIPELINE_SH" join x green 2>&1)"; RC=$?
expect_rc 0 "join vert (une moitié SKIPPED acceptée)"
OUT="$(jq -r '.stages.green.status' "$R/.claude/features/x/pipeline.json")"
expect_out "PASSED" "stages.green = PASSED"
echo "// FAKE_ANALYZE_ERROR" >> "$R/$P/lib/src/data/d.dart"
pipeline "$R" x "{\"mode\":\"create\",\"package\":\"$P\",\"tests_freeze_sha\":\"$SHA\",\"stages\":{\"green_data\":{\"status\":\"PASSED\"},\"green_presentation\":{\"status\":\"PASSED\"}}}"
OUT="$(cd "$R" && bash "$PIPELINE_SH" join x green 2>&1)"; RC=$?
expect_rc 1 "join rouge si le gate complet l'est"
OUT="$(jq -r '.stages.green.status' "$R/.claude/features/x/pipeline.json")"
expect_out "RED" "stages.green = RED"
git -C "$R" checkout -q -- "$P/lib/src/data/d.dart"

# hook_write <agent> <fichier> — décision du hook dans $OUT ("deny…" ou vide)
hook_write() {
  OUT="$(jq -n --arg a "$1" --arg c "$R" --arg f "$R/$2" \
    '{agent_type:$a, cwd:$c, tool_name:"Edit", tool_input:{file_path:$f}}' | bash "$HOOK" 2>&1)"
}
echo "hook — chaque moitié n'écrit que sa couche"
hook_write feature-test-writer-data "$P/test/src/data/x_test.dart";            expect_no_out deny "tests data : test/src/data"
hook_write feature-test-writer-data "$P/test/src/domain/x_test.dart";          expect_no_out deny "tests data : test/src/domain"
hook_write feature-test-writer-data "$P/test/src/presentation/x_test.dart";    expect_out deny "tests data : refus test/src/presentation"
hook_write feature-test-writer-data "$P/pubspec.yaml";                         expect_out deny "tests data : refus pubspec"
hook_write feature-test-writer-presentation "$P/test/step/a.dart";             expect_no_out deny "tests présentation : test/step"
hook_write feature-test-writer-presentation "$P/test/feat.feature";            expect_no_out deny "tests présentation : .feature"
hook_write feature-test-writer-presentation "$P/pubspec.yaml";                 expect_no_out deny "tests présentation : pubspec"
hook_write feature-test-writer-presentation "$P/test/src/data/x_test.dart";    expect_out deny "tests présentation : refus test/src/data"
hook_write feature-implementer-data "$P/lib/src/injection/di.dart";            expect_no_out deny "impl data : injection"
hook_write feature-implementer-data "$P/lib/src/presentation/p.dart";          expect_out deny "impl data : refus présentation"
hook_write feature-implementer-data "$P/test/src/data/d_test.dart";            expect_out "GELÉS" "impl data : tests gelés"
hook_write feature-implementer-presentation "$P/lib/src/presentation/p.dart";  expect_no_out deny "impl présentation : presentation"
hook_write feature-implementer-presentation "$P/lib/feat.dart";                expect_no_out deny "impl présentation : barrel"
hook_write feature-implementer-presentation "app/features/router/lib/r.dart";  expect_no_out deny "impl présentation : writes.extra"
hook_write feature-implementer-presentation "$P/lib/src/domain/u.dart";        expect_out deny "impl présentation : refus domain"
hook_write feature-implementer-presentation "$P/pubspec.yaml";                 expect_out deny "impl présentation : refus pubspec"

finish
