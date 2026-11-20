#!/usr/bin/env bash
# Repro — l'état d'un run s'écrivait aussi à la main (plan de refacto, point 13, livraison 3). ADR 0003 : pipeline.json
# ne s'écrit que par pipeline.sh, fix.json que par fix.py ; mais rien ne refusait à l'orchestrateur un Edit, un
# Write ou un `jq … > pipeline.json`, et le specifier comme le reproducer avaient le fichier dans leur zone.
#   state-guard.sh (toutes les sessions) : Edit, Write, MultiEdit et une écriture par Bash de
#     .claude/features/<nom>/pipeline.json ou .claude/fixes/<nom>/fix.json sont refusés, et le refus nomme le
#     script ; la lecture, les autres fichiers du run et un fix.json hors de .claude/fixes passent ; le refus
#     s'écrit au journal du run.
#   zones : le specifier n'écrit plus pipeline.json, le reproducer plus fix.json ; le reste de leur dossier, si.
source "$(dirname "$0")/fixture.sh"

HOOKS="$TESTS_DIR/../../../hooks"
export PIPELINE_GAUNTLET_ROOT="$TESTS_DIR/.."
export FIX_LIB="$TESTS_DIR/../../fix/lib.sh"
R="$TMP_ROOT/repo"; mk_repo "$R"
mkdir -p "$R/lib" "$R/test" "$R/.claude/fixes/crash" "$R/.claude/features/x"
echo "int a = 1;" > "$R/lib/a.dart"
echo '{}' > "$R/.claude/fixes/crash/fix.json"; echo '{}' > "$R/.claude/fixes/crash/repro.json"
echo '{}' > "$R/.claude/features/x/pipeline.json"
commit "$R" init >/dev/null
git -C "$R" checkout -q -b fix/crash
R="$(cd "$R" && pwd -P)"
FJ="$R/.claude/fixes/crash/fix.json"; PJ="$R/.claude/features/x/pipeline.json"

# hook <script> <agent ou ""> <outil> <fichier ou commande> — sortie dans $OUT, code dans $RC
hook() {
  local key=file_path; [ "$3" = Bash ] && key=command
  OUT="$(jq -n --arg a "$2" --arg c "$R" --arg t "$3" --arg k "$key" --arg v "$4" \
    '{agent_type:$a, cwd:$c, tool_name:$t, tool_input:{($k):$v, old_string:"a", new_string:"b", content:"{}"}}' \
    | bash "$HOOKS/$1" 2>&1)"; RC=$?
}

echo "orchestrateur — pipeline.json"
hook state-guard.sh "" Edit "$PJ"
expect_out deny "Edit de pipeline.json : refusé"
expect_out "pipeline.sh" "le refus nomme le script"
hook state-guard.sh "" Write ".claude/features/x/pipeline.json"
expect_out deny "Write par un chemin relatif : refusé"
hook state-guard.sh "" Bash "jq '.stages.red.status=\"PASSED\"' $PJ > /tmp/p && mv /tmp/p $PJ"
expect_out deny "jq > puis mv sur pipeline.json : refusé"
hook state-guard.sh "" Bash "jq -r '.stages' .claude/features/x/pipeline.json"
expect_no_out deny "lecture par jq : permise"
hook state-guard.sh "" Bash "bash ~/.claude/scripts/pipeline.sh set x phase green"
expect_no_out deny "pipeline.sh : permis (le hook ne voit pas ce que le script écrit)"
hook state-guard.sh "" Write "$R/.claude/features/x/spec.md"
expect_no_out deny "un autre fichier du dossier de la feature : permis"
expect_file_has "$R/.claude/features/x/.gauntlet/hooks.jsonl" '"hook":"state-guard"' "le refus est au journal de la feature"

echo "orchestrateur — fix.json"
hook state-guard.sh "" Edit "$FJ"
expect_out deny "Edit de fix.json : refusé"
expect_out "fix.py" "le refus nomme fix.py"
hook state-guard.sh "" Bash "echo '{}' | tee .claude/fixes/crash/fix.json"
expect_out deny "tee vers fix.json : refusé"
hook state-guard.sh "" Write "$R/test/fixtures/fix.json"
expect_no_out deny "un fix.json hors de .claude/fixes (fixture de test) : permis"
hook state-guard.sh "" Write "$R/.claude/fixes/crash/diagnosis.md"
expect_no_out deny "un autre fichier du dossier du fix : permis"

echo "sous-agents : le même garde, et leur zone"
hook state-guard.sh fix-reproducer Edit "$FJ"
expect_out deny "garde : fix.json refusé au reproducer aussi"
hook fix-restrict-writes.sh fix-reproducer Edit "$FJ"
expect_out deny "zone du reproducer : fix.json refusé"
expect_out "fix.py" "le refus dit qui l'écrit"
hook fix-restrict-writes.sh fix-reproducer Bash "jq '.phase=\"fix\"' .claude/fixes/crash/fix.json > .claude/fixes/crash/fix.json.tmp && mv .claude/fixes/crash/fix.json.tmp .claude/fixes/crash/fix.json"
expect_out deny "zone du reproducer : jq > puis mv sur fix.json refusé"
hook fix-restrict-writes.sh fix-reproducer Write "$R/.claude/fixes/crash/repro.json"
expect_no_out deny "zone du reproducer : repro.json, toujours permis"

finish
