#!/usr/bin/env bash
# Repro — mode extend : une ligne de code existant que `dart format` a seulement recoupée, recollée ou
# réindentée (virgule finale comprise) n'entre pas dans le périmètre de la feature.
#   error_handling : un try/catch préexistant hors data/, reformaté par la feature → pas de FAIL ;
#                    un try/catch ajouté par la feature, dans le même fichier reformaté → FAIL (contrôle).
#   GAUNTLET_KEEP_FORMAT_LINES=1 (conventions de /fix) : la ligne reformatée reste jugée (contrôle).
# Cas réels : ingredients_to_use_chips (couverture 79,4 % sur du code reformaté), sidos_menu_entries (S10,
# 4 providers et ~70 lignes reformatés), two_factor_login (re-gel « dart format only »).
source "$(dirname "$0")/fixture.sh"
need_fvm

R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
F=app/features
mk_pkg "$R/$F/feat" feat
mkdir -p "$R/$F/feat/lib/src/domain"
cat > "$R/$F/feat/lib/src/domain/legacy.dart" <<'EOF'
int legacy(int a, int b) { try { return a ~/ b; } catch (e) { return 0; } }
int other(int a) => a;
EOF
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/x
pipeline "$R" x '{"mode":"extend","package":"app/features/feat"}'

echo "error_handling — try/catch préexistant, seulement reformaté"
cat > "$R/$F/feat/lib/src/domain/legacy.dart" <<'EOF'
int legacy(int a, int b) {
  try {
    return a ~/ b;
  } catch (e) {
    return 0;
  }
}

int other(
  int a,
) =>
    a;
EOF
run_g "$R" error_handling x
expect_rc 0 "le try/catch reformaté n'est pas jugé"
expect_no_out "legacy.dart" "aucune ligne de legacy.dart signalée"

echo "error_handling — contrôle : la ligne reformatée reste jugée avec GAUNTLET_KEEP_FORMAT_LINES=1"
OUT="$(cd "$R" && GAUNTLET_KEEP_FORMAT_LINES=1 bash "$GAUNTLET" error_handling x 2>&1)"; RC=$?
expect_rc 1 "opt-out : le try/catch reformaté est jugé (conventions de /fix)"

echo "error_handling — contrôle : try/catch ajouté dans le fichier reformaté"
cat >> "$R/$F/feat/lib/src/domain/legacy.dart" <<'EOF'

int added(int a) {
  try {
    return 10 ~/ a;
  } catch (e) {
    return -1;
  }
}
EOF
run_g "$R" error_handling x
expect_rc 1 "le try/catch ajouté par la feature bloque"
expect_out "legacy.dart:15" "la ligne ajoutée est nommée"
expect_no_out "legacy.dart:2:" "la ligne seulement reformatée reste hors périmètre"

finish
