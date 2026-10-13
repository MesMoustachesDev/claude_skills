#!/usr/bin/env bash
# Repro 3 — les outils Dart du gauntlet (stub_check, dup_check) tournent depuis app_dir, là où vit .fvmrc.
# Avant : run_dart_tool / ensure_dart_tools faisaient `cd PROJECT_ROOT` ; sans .fvmrc à la racine, `fvm dart`
# retombait sur son SDK global (Dart 2.18 sur la machine de Thibault) et stub_check cassait.
# Le doctor détecte la configuration qui y mène : .fvmrc illisible depuis app_dir, ou un SDK résolu depuis
# app_dir différent de celui épinglé.
source "$(dirname "$0")/fixture.sh"
need_fvm

R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
mk_pkg "$R/app/features/feat" feat
cat > "$R/app/features/feat/lib/src/data/foo_impl.dart" <<'EOF'
class Foo {
  int a() => throw UnimplementedError();
}
EOF
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/feat
pipeline "$R" feat '{"mode":"create","package":"app/features/feat"}'

# Un SDK global factice, vieux, pour que la repro ne dépende pas du `fvm global` de la machine :
# fvm (sans .fvmrc) exécute le premier `dart` du PATH.
OLD="$TMP_ROOT/old-dart"; mkdir -p "$OLD"
cat > "$OLD/dart" <<'EOF'
#!/usr/bin/env bash
echo 'Dart SDK version: 2.18.6 (stable) (fake global SDK)'; [ "${1:-}" = --version ] && exit 0
echo "old global dart cannot run: $*" >&2; exit 255
EOF
chmod +x "$OLD/dart"
root_v="$(cd "$R" && PATH="$OLD:$PATH" fvm dart --version 2>&1 | grep -m1 "Dart SDK")"
echo "   (fvm dart depuis la racine du repo de test : $root_v)"

echo "stub_check depuis app_dir"
OUT=; RC=; OUT="$(cd "$R" && PATH="$OLD:$PATH" bash "$GAUNTLET" stub_check feat 2>&1)"; RC=$?
expect_rc 0 "stub_check passe malgré un dart global ancien"
expect_no_out "old global dart" "le SDK global n'est jamais appelé"

echo "doctor"
OUT="$(cd "$R" && PATH="$OLD:$PATH" bash "$GAUNTLET" doctor 2>&1)"
expect_out "[OK]   .fvmrc lisible depuis app_dir (app)" "doctor : .fvmrc trouvé depuis app_dir"
expect_out "[OK]   fvm dart depuis app_dir = SDK épinglé" "doctor : SDK épinglé résolu"
write_cfg "$R" ; sed -i '' 's/^app_dir = app$/app_dir = ./' "$R/.claude/rules/feature_pipeline.md"
OUT="$(cd "$R" && PATH="$OLD:$PATH" bash "$GAUNTLET" doctor 2>&1)"
expect_out "[FAIL] .fvmrc lisible depuis app_dir (.)" "doctor : app_dir sans .fvmrc détecté"
expect_out "[FAIL] Dart des outils du gauntlet ≥ 3.5.0 (vu depuis app_dir : 2.18.6)" "doctor : SDK global trop vieux détecté"

finish
