#!/usr/bin/env bash
# Repro 2 — un package qui vit dans un submodule (flutter_app/hades) est visible du gauntlet.
# Avant : le diff tournait dans le repo parent, qui ne voit que le gitlink → périmètre vide (stub_check :
# « aucun fichier d'implémentation dans le périmètre »), gel des tests aveugle, empreinte QA figée.
source "$(dirname "$0")/fixture.sh"
need_fvm

S="$TMP_ROOT/hades-src"; mk_repo "$S"
mk_pkg "$S" hades
cat > "$S/lib/src/data/theme_impl.dart" <<'EOF'
class Theme {
  int a() => 1;
}
EOF
echo "// existing test" > "$S/test/theme_test.dart"
commit "$S" "hades init" >/dev/null

R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
mkdir -p "$R/app/features"
git -C "$R" -c protocol.file.allow=always submodule add -q "$S" app/hades
BASE="$(commit "$R" "develop with hades submodule")"
git -C "$R" checkout -q -b feature/x
pipeline "$R" x "{\"mode\":\"extend\",\"package\":\"app/hades\",\"tests_freeze_sha\":\"$BASE\"}"
H="$R/app/hades"

echo "périmètre et stub_check dans le submodule"
cat > "$H/lib/src/data/theme_impl.dart" <<'EOF'
class Theme {
  int a() => 1;
  int b() => throw UnimplementedError();
}
EOF
git -C "$H" commit -qam "hades: contract b"                  # commit dans le submodule, gitlink non commité
cat > "$H/lib/src/data/tab_impl.dart" <<'EOF'
class Tab {
  int c() => throw UnimplementedError();
}
EOF
run_g "$R" stub_check x
expect_rc 0 "stub_check voit les contrats du submodule"
expect_out "2 fichier(s) inspecté(s)" "fichier modifié + fichier non suivi du submodule"
expect_file_has "$R/.claude/features/x/.gauntlet/scope.txt" "app/hades/lib/src/data/tab_impl.dart" "fichier non suivi dans scope.txt, chemin depuis la racine"
expect_file_has "$R/.claude/features/x/.gauntlet/scope.txt" "app/hades/lib/src/data/theme_impl.dart:3" "ligne ajoutée (commit du submodule) dans scope.txt"
cat > "$H/lib/src/data/tab_impl.dart" <<'EOF'
class Tab {
  int c() => 4;
}
EOF
run_g "$R" stub_check x
expect_rc 1 "contrôle : un non-stub ajouté dans le submodule bloque"

echo "gel des tests dans le submodule"
echo "// new test" > "$H/test/tab_test.dart"
run_g "$R" test_freeze_check:additive x
expect_rc 0 "additive : un test ajouté dans le submodule est toléré"
expect_out "app/hades/test/tab_test.dart" "le test ajouté est listé"
echo "// edited after freeze" >> "$H/test/theme_test.dart"
run_g "$R" test_freeze_check:additive x
expect_rc 1 "additive : un test gelé modifié dans le submodule bloque"
expect_out "app/hades/test/theme_test.dart" "le test modifié est nommé"

echo "empreinte QA"
fp() { (cd "$R" && GAUNTLET_ROOT="$(cd "$(dirname "$GAUNTLET")/gauntlet" && pwd)" bash -c '
  source "$GAUNTLET_ROOT/lib.sh"; source "$GAUNTLET_ROOT/checks_qa.sh"; init_project_context x >/dev/null; qa_fingerprint'); }
A="$(fp)"; echo "// tweak" >> "$H/lib/src/data/theme_impl.dart"; B="$(fp)"
OUT="$A / $B"; [ -n "$A" ] && [ "$A" != "$B" ] && _pass "une modification dans le submodule change l'empreinte QA" || _fail "empreinte QA inchangée après modification du submodule"

finish
