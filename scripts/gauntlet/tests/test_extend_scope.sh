#!/usr/bin/env bash
# Repro 1 — mode extend : les gates qui jugent le travail de la feature ne bloquent pas sur l'existant.
#   deps_features : une dépendance inter-features et un cycle déjà présents sur develop → WARN, pas FAIL ;
#                   une dépendance ou une arête de cycle ajoutée par la feature → FAIL (contrôles).
#   stub_check / red_check : lors d'un rejeu (pipeline.json → pass_base), le code et les tests d'une passe
#                   déjà validée sont hors périmètre ; sans pass_base, comportement inchangé (contrôle).
# Cas réel : feature main_page_tab_indicator (cycle main_page → plans → main_page préexistant, stub_check
# et red_check acceptés à la main sur des fichiers déjà implémentés au premier passage).
source "$(dirname "$0")/fixture.sh"
need_fvm

R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
F=app/features
mk_pkg "$R/$F/feat"  feat  other:../other
mk_pkg "$R/$F/other" other feat:../feat          # cycle feat → other → feat, préexistant
mk_pkg "$R/$F/third" third
cat > "$R/$F/feat/lib/src/data/foo_impl.dart" <<'EOF'
class Foo {
  int a() => throw UnimplementedError();
}
EOF
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/x
SPEC='# spec
## 8 Architecture
Aucune nouvelle dépendance.
## 9 Décisions
'
mkdir -p "$R/.claude/features/x"; printf '%s' "$SPEC" > "$R/.claude/features/x/spec.md"
pipeline "$R" x '{"mode":"extend","package":"app/features/feat"}'

echo "deps_features — existant sur develop"
echo "// touched" >> "$R/$F/feat/lib/src/data/foo_impl.dart"
run_g "$R" deps_features x
expect_rc 0 "dépendance et cycle préexistants ne bloquent pas"
expect_out "[WARN] dépendance inter-features other préexistante" "dépendance préexistante signalée"
expect_out "[WARN] cycle préexistant" "cycle préexistant signalé"

echo "deps_features — contrôle : dépendance ajoutée non justifiée"
mk_pkg "$R/$F/feat" feat other:../other third:../third
run_g "$R" deps_features x
expect_rc 1 "dépendance ajoutée par la feature bloque"
expect_out "dépendance inter-features third (ajoutée par la feature) absente de la spec §8" "message nomme la dépendance ajoutée"

echo "deps_features — contrôle : cycle introduit par la feature"
printf '%s' "${SPEC/Aucune nouvelle dépendance./feat dépend de third.}" > "$R/.claude/features/x/spec.md"
mk_pkg "$R/$F/third" third feat:../feat           # third → feat ajouté : cycle feat → third → feat
run_g "$R" deps_features x
expect_rc 1 "cycle qui emprunte une arête ajoutée bloque"
expect_out "cycle de dépendances entre features introduit par la feature : feat → third → feat" "le cycle introduit est nommé"
git -C "$R" checkout -q -- "$F" && rm -rf "$R/.claude/features/x/.gauntlet"
printf '%s' "$SPEC" > "$R/.claude/features/x/spec.md"

echo "stub_check — rejeu après une passe implémentée"
cat > "$R/$F/feat/lib/src/data/foo_impl.dart" <<'EOF'
class Foo {
  int a() => 1;
  int c() => 2;
}
EOF
# a() existed on develop (base version, not a new contract: stub_check skips it); c() is pass 1's own
# contract, implemented, so without pass_base it is judged and fails.
cat > "$R/$F/feat/test/foo_test.dart" <<'EOF'
// pass 1 test, green since pass 1 was implemented
EOF
PASS1="$(commit "$R" "pass 1 implemented")"
cat > "$R/$F/feat/lib/src/data/bar_impl.dart" <<'EOF'
class Bar {
  int b() => throw UnimplementedError();
}
EOF
run_g "$R" stub_check x
expect_rc 1 "contrôle : sans pass_base, le code de la passe 1 est jugé (inchangé)"
pipeline "$R" x "{\"mode\":\"extend\",\"package\":\"app/features/feat\",\"pass_base\":\"$PASS1\"}"
run_g "$R" stub_check x
expect_rc 0 "avec pass_base, seul le contrat du rejeu est inspecté"
expect_out "1 fichier(s) inspecté(s)" "un seul fichier inspecté (bar_impl.dart)"
cat > "$R/$F/feat/lib/src/data/bar_impl.dart" <<'EOF'
class Bar {
  int b() => 3;
}
EOF
run_g "$R" stub_check x
expect_rc 1 "contrôle : un non-stub ajouté pendant le rejeu bloque toujours"
expect_out "bar_impl.dart" "le non-stub du rejeu est nommé"

echo "red_check — rejeu : tests de la passe 1 déjà verts"
cat > "$R/$F/feat/test/bar_test.dart" <<'EOF'
// FAKE_FAIL : new red test of the replay
EOF
run_g "$R" red_check x
expect_rc 0 "avec pass_base, le test vert de la passe 1 ne bloque pas"
expect_no_out "tout vert : test/foo_test.dart" "foo_test.dart hors périmètre de la passe"
pipeline "$R" x '{"mode":"extend","package":"app/features/feat"}'
run_g "$R" red_check x
expect_rc 1 "contrôle : sans pass_base, le fichier tout vert bloque (inchangé)"
expect_out "tout vert : test/foo_test.dart" "foo_test.dart signalé sans pass_base"

finish
