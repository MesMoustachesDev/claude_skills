#!/usr/bin/env bash
# Repro — writes.extra propre à la feature : une zone hors package ouverte par `pipeline.sh extra` (pipeline.json
# → writes_extra) vaut pour cette feature seulement, sans toucher feature_pipeline.md du projet.
#   pipeline.sh extra : écrit pipeline.json, jamais la config ; sans glob, liste projet + feature.
#   hook pipeline-restrict-writes : l'implementer peut écrire dans la zone de la feature ; sans elle, refus.
#   footprint : un fichier modifié dans la zone de la feature passe ; sans elle, FAIL.
# Cas réels : cookbooker meal_plan_basics_leftovers (functions/** ouvert à vie pour un paramètre), social_apps
# (remote_config/**, Info.plist, AndroidManifest.xml ajoutés à la config du projet).
source "$(dirname "$0")/fixture.sh"
need_fvm

HOOK="$TESTS_DIR/../../../hooks/pipeline-restrict-writes.sh"
PIPELINE_SH="$TESTS_DIR/../../pipeline.sh"
R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R" "writes.extra = app/features/router/**"
F=app/features
mk_pkg "$R/$F/feat" feat
mk_pkg "$R/$F/other" other
echo "int o() => 1;" > "$R/$F/other/lib/src/data/o.dart"
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/x
pipeline "$R" x '{"mode":"extend","package":"app/features/feat"}'
CFG_BEFORE="$(cat "$R/.claude/rules/feature_pipeline.md")"

# hook_write <agent> <fichier> — décision du hook dans $OUT ("deny…" ou vide)
hook_write() {
  OUT="$(jq -n --arg a "$1" --arg c "$R" --arg f "$R/$2" \
    '{agent_type:$a, cwd:$c, tool_name:"Edit", tool_input:{file_path:$f}}' | bash "$HOOK" 2>&1)"
}

echo "pipeline.sh extra — la zone va dans pipeline.json"
OUT="$(cd "$R" && bash "$PIPELINE_SH" extra x "app/features/other/lib/**" 2>&1)"; RC=$?
expect_rc 0 "pipeline.sh extra réussit"
expect_out "app/features/router/**  (projet)" "la zone du projet est listée"
expect_out "app/features/other/lib/**  (feature)" "la zone de la feature est listée"
[ "$(cat "$R/.claude/rules/feature_pipeline.md")" = "$CFG_BEFORE" ] && _pass "feature_pipeline.md inchangé" || _fail "feature_pipeline.md modifié"
OUT="$(jq -r '.writes_extra | join(",")' "$R/.claude/features/x/pipeline.json")"
expect_out "app/features/other/lib/**" "pipeline.json → writes_extra contient la zone"

echo "hook — zone de la feature"
hook_write feature-implementer "$F/other/lib/src/data/o.dart"
expect_no_out "deny" "l'implementer écrit dans la zone ouverte pour la feature"
hook_write feature-implementer "$F/router/lib/r.dart"
expect_no_out "deny" "la zone du projet reste ouverte"
hook_write feature-test-writer "$F/other/test/o_test.dart"
expect_no_out "deny" "le test-writer écrit dans test/ du package ouvert pour la feature"

echo "footprint — fichier modifié dans la zone de la feature"
echo "int o() => 2;" > "$R/$F/other/lib/src/data/o.dart"
run_g "$R" footprint x
expect_rc 0 "footprint accepte la zone de la feature"

echo "contrôle : sans la zone de la feature"
pipeline "$R" x '{"mode":"extend","package":"app/features/feat"}'
hook_write feature-implementer "$F/other/lib/src/data/o.dart"
expect_out "deny" "le hook refuse hors zone"
run_g "$R" footprint x
expect_rc 1 "footprint bloque hors zone"
expect_out "app/features/other/lib/src/data/o.dart" "le fichier hors zone est nommé"

finish
