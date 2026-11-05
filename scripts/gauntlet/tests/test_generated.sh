#!/usr/bin/env bash
# Repro — les fichiers générés (generated.exclude) ne sont jugés par aucun check.
# Cas réel : feature import_cancel_sync, un cascade_invocations dans
# database/lib/src/model/import/import_snapshot_dao.g.dart:77 a rendu rouges red_presentation puis
# green_presentation, accepté deux fois à la main.
#   analyze / format : un lint ou un fichier non formaté dans un .g.dart ne bloque pas, en create comme en
#                      extend (fichier généré ajouté par la feature) ; le même dans un .dart écrit à la main
#                      bloque (contrôle).
#   generated.exclude : motif configurable (un *.out.dart ajouté est ignoré) ; `none` rejuge tout.
#   erreur de compilation : bloque toujours, même dans un fichier généré.
source "$(dirname "$0")/fixture.sh"
need_fvm

R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
F=app/features
mk_pkg "$R/$F/feat" feat
echo 'class A {}' > "$R/$F/feat/lib/a.dart"
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/x

LINT='// FAKE_ANALYZE_INFO
class   Unformatted{int  a=1;}'
echo "create — lint et format dans un .g.dart"
pipeline "$R" x '{"mode":"create","package":"app/features/feat"}'
printf '%s\n' "$LINT" > "$R/$F/feat/lib/a.g.dart"
run_g "$R" analyze x
expect_rc 0 "analyze : lint d'un .g.dart ignoré"
expect_no_out "cascade_invocations" "le lint du .g.dart n'est pas listé"
run_g "$R" format x
expect_rc 0 "format : .g.dart non formaté ignoré"

echo "extend — fichier généré ajouté par la feature (cas import_snapshot_dao.g.dart)"
pipeline "$R" x '{"mode":"extend","package":"app/features/feat"}'
mkdir -p "$R/$F/feat/lib/src/model"
printf '%s\n' "$LINT" > "$R/$F/feat/lib/src/model/snapshot_dao.g.dart"
printf '%s\n' "$LINT" > "$R/$F/feat/test/repo_test.mocks.dart"
run_g "$R" analyze x
expect_rc 0 "analyze : lint d'un .g.dart et d'un .mocks.dart ajoutés ignoré"
run_g "$R" format x
expect_rc 0 "format : fichiers générés ajoutés ignorés"

echo "contrôle — le même lint dans un fichier écrit à la main"
printf '%s\n' "$LINT" > "$R/$F/feat/lib/src/model/snapshot_dao.dart"
run_g "$R" analyze x
expect_rc 1 "analyze : lint d'un .dart écrit à la main bloque"
expect_out "snapshot_dao.dart" "le fichier écrit à la main est nommé"
expect_no_out "snapshot_dao.g.dart" "le .g.dart n'est pas nommé"
run_g "$R" format x
expect_rc 1 "format : .dart non formaté bloque"
rm "$R/$F/feat/lib/src/model/snapshot_dao.dart"

echo "generated.exclude configurable"
printf '%s\n' "$LINT" > "$R/$F/feat/lib/src/model/thing.out.dart"
run_g "$R" analyze x
expect_rc 1 "contrôle : *.out.dart n'est pas généré par défaut"
write_cfg "$R" "generated.exclude = *.g.dart, *.out.dart"
run_g "$R" analyze x
expect_rc 1 "*.mocks.dart retiré du motif : rejugé"
write_cfg "$R" "generated.exclude = *.g.dart, *.mocks.dart, *.out.dart"
run_g "$R" analyze x
expect_rc 0 "*.out.dart ajouté au motif : ignoré"
write_cfg "$R" "generated.exclude = none"
run_g "$R" analyze x
expect_rc 1 "none : tout est rejugé"
write_cfg "$R"
rm "$R/$F/feat/lib/src/model/thing.out.dart"

echo "erreur de compilation dans un fichier généré"
echo '// FAKE_ANALYZE_ERROR' >> "$R/$F/feat/lib/src/model/snapshot_dao.g.dart"
run_g "$R" analyze x
expect_rc 1 "une erreur de compilation bloque même dans un .g.dart"
expect_out "erreurs de compilation" "message d'erreur de compilation"

finish
