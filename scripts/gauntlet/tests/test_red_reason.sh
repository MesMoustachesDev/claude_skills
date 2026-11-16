#!/usr/bin/env bash
# Repro — red_check « rouge pour la bonne raison ». Avant : un fichier de test avec au moins un échec passait,
# quelle qu'en soit la cause ; un test qui jette dans son propre montage (mock sans réponse, clé introuvable)
# passait le gel et ne se voyait qu'à l'étape 4, toujours rouge une fois le code écrit.
#   échec sur un stub (UnimplementedError) ou une assertion : vert.
#   échec du montage : rouge, test et message nommés ; red_accept_error (fichier + raison) le lève.
source "$(dirname "$0")/fixture.sh"
need_fvm

R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R" ""
P=app/features/feat
mk_pkg "$R/$P" feat
mkdir -p "$R/$P/test/src/data"
echo "int d() => throw UnimplementedError();" > "$R/$P/lib/src/data/d.dart"
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/x
pipeline "$R" x "{\"mode\":\"create\",\"package\":\"$P\"}"
T="$R/$P/test/src/data"

echo "red_check — échec sur un stub ou une assertion"
printf '// FAKE_STUB_FAIL\nvoid main() {}\n' > "$T/a_test.dart"
printf '// FAKE_FAIL\nvoid main() {}\n' > "$T/b_test.dart"
run_g "$R" red_check x
expect_rc 0 "stub et assertion : rouge pour la bonne raison"
expect_out "sur un stub ou une assertion" "le bilan le dit"

echo "red_check — échec du montage"
printf '// FAKE_SETUP_FAIL\nvoid main() {}\n' > "$T/c_test.dart"
run_g "$R" red_check x
expect_rc 1 "un test qui jette dans son montage bloque"
expect_out "test/src/data/c_test.dart — c_test — Bad state: No element" "le test et son message sont nommés"

echo "red_check — échec du montage accepté par Thibault"
PJ="$R/.claude/features/x/pipeline.json"
jq '.red_accept_error = [{file: "test/src/data/c_test.dart", reason: "le widget jette exprès"}]' "$PJ" > "$PJ.tmp" && mv "$PJ.tmp" "$PJ"
run_g "$R" red_check x
expect_rc 0 "accepté : ne bloque plus"
expect_out "rouge hors stub, accepté par Thibault : test/src/data/c_test.dart (le widget jette exprès)" "il reste signalé, avec sa raison"

finish
