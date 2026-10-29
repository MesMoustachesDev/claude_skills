#!/usr/bin/env bash
# Repro — écritures par Bash et tests créés par Hugo.
# Cas réel : refactor_feature, Hugo crée editor_actions_mutation_test.dart (cat > en Bash), veut le
# corriger avec Edit : « les tests existants ne se modifient pas » ; il le corrige en `sed -i`. Et Nina
# réécrit README.md par sed, hors de sa zone, sans que rien ne le voie.
#   hook d'écriture : un test absent du gel est à Hugo (Edit permis) ; un test gelé reste refusé ;
#     sed -i, redirections, tee, cp/mv passent par la même zone que Edit/Write ; hors worktree, libre.
source "$(dirname "$0")/fixture.sh"
need_fvm

HOOKS="$TESTS_DIR/../../../hooks"
export PIPELINE_GAUNTLET_ROOT="$TESTS_DIR/.."
R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
P=app/features/feat
mk_pkg "$R/$P" feat
mkdir -p "$R/$P/test/src/data"
echo "void main() {}" > "$R/$P/test/src/data/frozen_test.dart"
echo "# feat" > "$R/$P/README.md"
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/x
FREEZE="$(git -C "$R" rev-parse HEAD)"
pipeline "$R" x "{\"mode\":\"create\",\"package\":\"$P\",\"tests_freeze_sha\":\"$FREEZE\"}"
echo "void main() {}" > "$R/$P/test/src/data/new_mutation_test.dart"   # créé par Hugo après le gel
R="$(cd "$R" && pwd -P)"

# hook <agent> <outil> <fichier ou commande> — sortie dans $OUT
hook() {
  local key=file_path; [ "$2" = Bash ] && key=command
  OUT="$(jq -n --arg a "$1" --arg c "$R" --arg t "$2" --arg k "$key" --arg v "$3" \
    '{agent_type:$a, cwd:$c, tool_name:$t, tool_input:{($k):$v}}' \
    | bash "$HOOKS/pipeline-restrict-writes.sh" 2>&1)"
}

echo "Hugo — tests gelés et tests à lui"
hook feature-hardener Edit "$R/$P/test/src/data/new_mutation_test.dart"
expect_no_out deny "Edit d'un test qu'il a créé après le gel : permis"
hook feature-hardener Edit "$R/$P/test/src/data/frozen_test.dart"
expect_out "test gelé" "Edit d'un test gelé : refusé"
hook feature-hardener Bash "cd $R/$P && sed -i '' 's|a|b|' test/src/data/frozen_test.dart"
expect_out "écriture par Bash" "sed -i sur un test gelé : refusé, et le refus dit que Bash suit la même zone"
hook feature-hardener Bash "cd $R/$P && sed -i '' 's|a|b|' test/src/data/new_mutation_test.dart && grep -n b test"
expect_no_out deny "sed -i sur son propre test : permis"
hook feature-hardener Bash "cd $R/$P && cat > test/src/data/other_mutation_test.dart <<'EOF'
// l'accent, une apostrophe que shlex ne lirait pas
EOF
fvm dart format test >/dev/null 2>&1"
expect_no_out deny "heredoc vers un nouveau test : permis"

echo "Ivan, Nina, Romain — la même zone que Edit/Write"
hook feature-implementer Bash "echo x > $R/$P/test/src/data/frozen_test.dart"
expect_out "GELÉS" "implementer : redirection vers un test : refusée"
hook feature-implementer Bash "L=/private/tmp/log.txt; fvm flutter test > \$L 2>&1; tail \$L"
expect_no_out deny "implementer : journal hors du worktree (variable développée) : permis"
hook feature-implementer Bash "for f in a b; do cp $R/$P/lib/\$f.dart /tmp; done"
expect_no_out deny "variable de boucle inconnue : pas de décision"
hook feature-cleaner Bash "cd $R/$P && sed -i '' 's/a/b/' README.md"
expect_no_out deny "cleaner : README du package (dépendance retirée) : permis"
hook feature-cleaner Bash "cd $R/$P && P=lib/src && mkdir -p \$P/support && mv test/src/data/frozen_test.dart \$P/support/"
expect_out "GELÉS" "cleaner : mv d'un test gelé : refusé (\$P développé)"
hook feature-reviewer Bash "cd $R/$P
cat > lib/src/data/patch.dart <<'EOF'
int x = 1;
EOF"
expect_out "reviewer : lecture seule" "reviewer : heredoc dans lib/ après un cd sur sa propre ligne : refusé"
hook feature-reviewer Bash "cd $R/$P && git diff develop -- lib | head -50"
expect_no_out deny "reviewer : lecture seule par Bash : permis"
hook feature-spec-critic Bash "tee $R/.claude/features/x/spec.md < /dev/null"
expect_out "pas la spec elle-même" "spec-critic : tee vers spec.md : refusé"

finish
