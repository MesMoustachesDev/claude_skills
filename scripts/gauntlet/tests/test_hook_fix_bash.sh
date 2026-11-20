#!/usr/bin/env bash
# Repro — écritures par Bash dans /fix : même angle mort que le hook de /feature (Hugo, `sed -i` après
# un Edit refusé). fix-restrict-writes.sh ne regardait que Edit/Write.
#   implementer : sed -i ou redirection vers un test gelé ou vers .claude/fixes/<nom>/ : refusés ;
#     code source et journaux hors du projet : permis.
#   reproducer : tests et son dossier par Bash : permis ; code source par sed : refusé (logs via Edit).
#   reviewer : lecture seule, Bash compris.
source "$(dirname "$0")/fixture.sh"

HOOKS="$TESTS_DIR/../../../hooks"
export PIPELINE_GAUNTLET_ROOT="$TESTS_DIR/.."
export FIX_LIB="$TESTS_DIR/../../fix/lib.sh"
R="$TMP_ROOT/repo"; mkdir -p "$R"; git -C "$R" init -q -b develop
mkdir -p "$R/lib" "$R/test" "$R/.claude/fixes/crash"
echo "int a = 1;" > "$R/lib/a.dart"
echo "void main() {}" > "$R/test/a_test.dart"
echo '{}' > "$R/.claude/fixes/crash/repro.json"
git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -q -m init
git -C "$R" checkout -q -b fix/crash
R="$(cd "$R" && pwd -P)"

# hook <agent> <outil> <fichier ou commande> — sortie dans $OUT
hook() {
  local key=file_path; [ "$2" = Bash ] && key=command
  OUT="$(jq -n --arg a "$1" --arg c "$R" --arg t "$2" --arg k "$key" --arg v "$3" \
    '{agent_type:$a, cwd:$c, tool_name:$t, tool_input:{($k):$v}}' \
    | bash "$HOOKS/fix-restrict-writes.sh" 2>&1)"
}

echo "Fanny (fix-implementer)"
hook fix-implementer Edit "$R/test/a_test.dart"
expect_out "GELÉS" "Edit d'un test : refusé (comme avant)"
hook fix-implementer Bash "sed -i '' 's/a/b/' test/a_test.dart"
expect_out "écriture par Bash" "sed -i sur un test : refusé, et le refus dit que Bash suit la même zone"
hook fix-implementer Bash "echo '{}' > .claude/fixes/crash/repro.json"
expect_out "repro.json est gelé" "redirection vers repro.json : refusée"
hook fix-implementer Bash "sed -i '' 's/1/2/' lib/a.dart && fvm flutter test > /tmp/fix.log 2>&1; tail /tmp/fix.log"
expect_no_out deny "code source et journal dans /tmp : permis"

echo "Bastien (fix-reproducer)"
hook fix-reproducer Bash "cat > test/crash_test.dart <<'EOF2'
void main() {} // l'apostrophe
EOF2"
expect_no_out deny "heredoc vers un nouveau test : permis"
hook fix-reproducer Bash "fvm flutter test test/crash_test.dart | tee .claude/fixes/crash/red.log"
expect_no_out deny "tee vers son dossier de fix : permis"
hook fix-reproducer Bash "sed -i '' 's/1/2/' lib/a.dart"
expect_out "reproducer : tu n'écris que des tests" "sed -i dans le code source : refusé"

echo "Victor (fix-reviewer)"
hook fix-reviewer Bash "git diff develop -- lib | head -50"
expect_no_out deny "lecture par Bash : permis"
hook fix-reviewer Bash "cat > .claude/fixes/crash/review.json <<'EOF2'
{}
EOF2"
expect_no_out deny "heredoc vers review.json : permis"
hook fix-reviewer Bash "sed -i '' 's/1/2/' lib/a.dart"
expect_out "reviewer : lecture seule" "sed -i dans lib/ : refusé"

# Les voisins de python (plan interpreteurs-serena, point 2) : une fois python fermé (ADR 0017), les mêmes
# écritures passeraient par git apply, patch, git checkout/restore, install, dd ou rsync.
echo "Fanny — écritures par patch, git, install, dd, rsync"
printf -- '--- a/test/a_test.dart\n+++ b/test/a_test.dart\n@@ -1 +1 @@\n-void main() {}\n+void main() { print(1); }\n' > "$TMP_ROOT/t.patch"
hook fix-implementer Bash "git apply $TMP_ROOT/t.patch"
expect_out "GELÉS" "git apply d'un patch qui touche un test : refusé"
hook fix-implementer Bash "cd lib && git apply <<'EOF2'
--- a/test/a_test.dart
+++ b/test/a_test.dart
@@ -1 +1 @@
-void main() {}
+void main() { print('x'); }
EOF2"
expect_out "GELÉS" "git apply d'un heredoc, depuis un sous-dossier (chemins depuis la racine) : refusé"
hook fix-implementer Bash "git apply --check $TMP_ROOT/t.patch"
expect_no_out deny "git apply --check : n'écrit rien, permis"
hook fix-implementer Bash "patch -p1 < $TMP_ROOT/t.patch"
expect_out "GELÉS" "patch -p1 < f : refusé"
hook fix-implementer Bash "patch test/a_test.dart $TMP_ROOT/t.patch"
expect_out "GELÉS" "patch <fichier> <patch> : refusé"
hook fix-implementer Bash "git checkout develop -- test/a_test.dart"
expect_out "GELÉS" "git checkout <rev> -- <test> : refusé"
hook fix-implementer Bash "git restore --source=develop test/a_test.dart"
expect_out "GELÉS" "git restore d'un test : refusé"
hook fix-implementer Bash "git restore --staged test/a_test.dart"
expect_no_out deny "git restore --staged : l'index seul, permis"
hook fix-implementer Bash "install -m 644 /tmp/x test/a_test.dart"
expect_out "GELÉS" "install -m 644 vers un test : refusé"
hook fix-implementer Bash "dd if=/tmp/x of=test/a_test.dart"
expect_out "GELÉS" "dd of=<test> : refusé"
hook fix-implementer Bash "rsync -a /tmp/x_test.dart test/"
expect_out "GELÉS" "rsync vers test/ : refusé"
hook fix-implementer Bash "git apply $TMP_ROOT/lib.patch 2>/dev/null; rsync -a lib/ /tmp/backup/; git checkout -- lib/a.dart"
expect_no_out deny "code source, sauvegarde hors du projet : permis"

echo "bug 1 — cwd au checkout principal, fix dans son worktree"
git -C "$R" checkout -q develop
printf '.claude/worktrees/\n' > "$R/.gitignore"; git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -q -m ignore
W="$R/.claude/worktrees/fix-crash"
git -C "$R" branch -q -D fix/crash; git -C "$R" worktree add -q "$W" -b fix/crash
W="$(cd "$W" && pwd -P)"
echo crash > "$R/.claude/fixes/.current"   # le cas où l'ancien hook prenait le checkout principal pour le fix
hook fix-implementer Edit "$W/test/a_test.dart"
expect_out "GELÉS" "Edit d'un test du worktree, cwd au checkout principal : jugé dans le worktree, refusé"
hook fix-implementer Edit "$W/lib/a.dart"
expect_no_out deny "Edit du code source du worktree : permis (pas « hors du projet »)"
hook fix-implementer Write "$W/.claude/fixes/crash/repro.json"
expect_out "repro.json est gelé" "repro.json du worktree : refusé à l'implementer (jugé hors de son dossier de fix avant)"
hook fix-reviewer Write "$W/.claude/fixes/crash/review.json"
expect_no_out deny "review.json du worktree : permis au reviewer (refusé avant)"
hook fix-reproducer Write "$W/.claude/fixes/crash/diagnosis.md"
expect_no_out deny "diagnosis.md du worktree : permis au reproducer (refusé avant)"
hook fix-reproducer Edit "$R/test/a_test.dart"
expect_no_out "hors du projet" "fichier du checkout principal sans worktree dans le prompt : comportement d'avant (.current)"

finish
