#!/usr/bin/env bash
# Repro — l'orchestrateur de /feature lisait lui-même le code (plan de refacto, point 18) : environ 870 tours de
# grep, sed, cat, ls et Read, dont lib/, test/ et les logs du gauntlet, malgré la règle « tu passes des chemins
# et des faits ». ADR 0020 : orchestrator-reads.sh refuse à la session principale, pendant un /feature ou un /fix,
# la lecture du code et du log entier du gauntlet ; les fichiers du pipeline restent lisibles ; un sous-agent
# n'est jamais bloqué ; hors /feature et /fix, rien ne change.
source "$(dirname "$0")/fixture.sh"

HOOK="$TESTS_DIR/../../../hooks/orchestrator-reads.sh"
export PIPELINE_GAUNTLET_ROOT="$TESTS_DIR/.."
STEPS="$(cd "$TESTS_DIR/../../../pipeline/feature/steps" && pwd)"
R="$TMP_ROOT/repo"; mk_repo "$R"
mkdir -p "$R/features/x/lib/src" "$R/features/x/test" "$R/.claude/features/x/.gauntlet" "$R/docs"
printf 'int a = 1;\n' > "$R/features/x/lib/src/a.dart"
printf 'void main() {}\n' > "$R/features/x/test/a_test.dart"
printf 'name: x\n' > "$R/features/x/pubspec.yaml"
echo '{}' > "$R/.claude/features/x/pipeline.json"; echo '# spec' > "$R/.claude/features/x/spec.md"
echo 'FAIL check' > "$R/.claude/features/x/.gauntlet/last_green.log"
echo '{"failed":["check"]}' > "$R/.claude/features/x/.gauntlet/last_green.json"
echo '# doc' > "$R/docs/readme.md"
commit "$R" init >/dev/null
git -C "$R" checkout -q -b feature/x
R="$(cd "$R" && pwd -P)"
A="$R/features/x/lib/src/a.dart"; LOG="$R/.claude/features/x/.gauntlet/last_green.log"

T_FEATURE="$TMP_ROOT/feature.jsonl"; T_FIX="$TMP_ROOT/fix.jsonl"; T_NONE="$TMP_ROOT/none.jsonl"; T_SKILL="$TMP_ROOT/skill.jsonl"
T_QUOTED="$TMP_ROOT/quoted.jsonl"
# le format d'un vrai transcript : la commande tapée est un message de l'utilisateur
cmd_line() { printf '{"type":"user","message":{"role":"user","content":"<command-message>%s</command-message>\\n<command-name>/%s</command-name>"}}\n' "$1" "$1"; }
# la même commande citée dans un résultat d'outil (un grep de transcript) : guillemets échappés
jq -cn '{type:"user",message:{role:"user",content:[{type:"tool_result",content:"{\"role\":\"user\",\"content\":\"<command-message>feature</command-message>\\n<command-name>/feature</command-name>\"} \"name\":\"Skill\",\"input\":{\"skill\":\"feature\"}"}]}}' > "$T_QUOTED"
{ cmd_line feature; cmd_line compact; echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"create_mr"}}]}}'; } > "$T_FEATURE"      # /compact et create_mr ne terminent pas le /feature
{ cmd_line feature; cmd_line fix; } > "$T_FIX"
echo '{"type":"user","message":{"content":"bonjour"}}' > "$T_NONE"
echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"feature","args":"x"}}]}}' > "$T_SKILL"

# hook <transcript> <agent ou ""> <outil> <entrée JSON de l'outil> — sortie dans $OUT
hook() {
  OUT="$(jq -n --arg tr "$1" --arg a "$2" --arg c "$R" --arg t "$3" --argjson i "$4" \
    '{transcript_path:$tr, cwd:$c, tool_name:$t, tool_input:$i} + (if $a != "" then {agent_type:$a, agent_id:"ab12"} else {} end)' \
    | bash "$HOOK" 2>&1)"
}
read_() { hook "$T_FEATURE" "" Read "$(jq -n --arg f "$1" '{file_path:$f}')"; }
bash_() { hook "${2:-$T_FEATURE}" "${3:-}" Bash "$(jq -n --arg c "$1" '{command:$c}')"; }

echo "orchestrateur, /feature actif — code refusé"
read_ "$A"
expect_out deny "Read de lib/ : refusé"
expect_out "agent de l'étape" "le refus dit où va la question"
read_ "$R/features/x/test/a_test.dart"
expect_out deny "Read de test/ : refusé"
read_ "$R/.claude/worktrees/feature-y/lib/b.dart"
expect_out deny "le code d'un worktree de feature (sous .claude/worktrees/) : refusé"
hook "$T_FEATURE" "" Read "$(jq -n --arg f "$A" '{file_path:$f, offset:1, limit:200}')"
expect_out deny "Read de 200 lignes de code : refusé"
bash_ "cat $A"
expect_out deny "cat d'un fichier de lib/ : refusé"
bash_ "cd features/x/lib/src && cat a.dart"
expect_out deny "cd puis cat : refusé"
bash_ "grep -rn Foo features/x/lib"
expect_out deny "grep -r dans lib/ : refusé"
bash_ "grep -rn Foo ."
expect_out deny "grep -r à la racine du projet (elle contient lib/) : refusé"
bash_ "rg Foo features/x"
expect_out deny "rg dans un package : refusé"
bash_ "sed -n '1,200p' $A"
expect_out deny "sed -n de 200 lignes : refusé"
bash_ "ls features/x/lib/src"
expect_out deny "ls de lib/src : refusé"
bash_ "find . -name '*.dart'"
expect_out deny "find des .dart : refusé"
hook "$T_FEATURE" "" Grep '{"pattern":"Foo","path":"features/x/lib"}'
expect_out deny "Grep dans lib/ : refusé"
hook "$T_FEATURE" "" Glob '{"pattern":"**/*.dart"}'
expect_out deny "Glob des .dart : refusé"
expect_file_has "$R/.claude/features/x/.gauntlet/hooks.jsonl" '"hook":"orchestrator-reads"' "le refus est au journal de la feature"

echo "orchestrateur, /feature actif — pipeline et extraits permis"
read_ "$R/.claude/features/x/spec.md"
expect_no_out deny "Read de .claude/features/<nom>/spec.md : permis"
read_ "$R/.claude/features/x/pipeline.json"
expect_no_out deny "Read de pipeline.json : permis"
read_ "$STEPS/1_spec.md"
expect_no_out deny "Read d'un step du pipeline : permis"
bash_ "jq -r '.stages' .claude/features/x/pipeline.json"
expect_no_out deny "jq sur pipeline.json : permis"
bash_ "cat .claude/features/x/spec.md | head -20"
expect_no_out deny "cat de la spec : permis"
bash_ "grep -rn x .claude/features/x"
expect_no_out deny "grep -r dans .claude/features/ : permis"
bash_ "grep -rn x --include='*.md' ."
expect_no_out deny "grep -r restreint aux .md : permis"
bash_ "ls features/x"
expect_no_out deny "ls de la racine du package : permis"
hook "$T_FEATURE" "" Read "$(jq -n --arg f "$A" '{file_path:$f, offset:1, limit:8}')"
expect_no_out deny "extrait de 8 lignes (Read avec limit) : permis"
bash_ "sed -n '10,30p' $A"
expect_no_out deny "extrait par sed -n de 21 lignes : permis"
hook "$T_FEATURE" "" Glob '{"pattern":"**/*.md"}'
expect_no_out deny "Glob des .md : permis"
bash_ "bash ~/.claude/scripts/pipeline.sh next x"
expect_no_out deny "pipeline.sh : permis"

echo "orchestrateur, /feature actif — log du gauntlet"
bash_ "cat $LOG"
expect_out deny "cat du log entier : refusé"
expect_out "résumé" "le refus renvoie au résumé du gate"
read_ "$LOG"
expect_out deny "Read du log sans limit : refusé"
bash_ "tail -60 $LOG"
expect_no_out deny "tail du log : permis"
bash_ "grep -n check $LOG"
expect_no_out deny "grep dans le log : permis"
bash_ "jq '.failed' .claude/features/x/.gauntlet/last_green.json"
expect_no_out deny "last_<profil>.json par jq : permis"

echo "sous-agents — jamais bloqués"
hook "$T_FEATURE" feature-implementer Read "$(jq -n --arg f "$A" '{file_path:$f}')"
expect_no_out deny "Read de lib/ par l'implementer : permis"
bash_ "grep -rn Foo ." "$T_FEATURE" feature-reviewer
expect_no_out deny "grep -r par le reviewer : permis"
OUT="$(jq -n --arg tr "$T_FEATURE" --arg c "$R" --arg f "$A" '{transcript_path:$tr, cwd:$c, agent_id:"ab12", tool_name:"Read", tool_input:{file_path:$f}}' | bash "$HOOK" 2>&1)"
expect_no_out deny "agent_id sans agent_type : permis"

echo "hors /feature et /fix — rien ne change"
T_REVIEW="$TMP_ROOT/review.jsonl"; { cmd_line fix; cmd_line reviewPR; } > "$T_REVIEW"
bash_ "cat $A" "$T_REVIEW"
expect_no_out deny "/reviewPR lancé après le /fix : permis"
bash_ "cat $A" "$T_NONE"
expect_no_out deny "aucune commande du pipeline : permis"
bash_ "cat $A" "$TMP_ROOT/absent.jsonl"
expect_no_out deny "transcript introuvable : permis"
bash_ "cat $A" "$T_QUOTED"
expect_no_out deny "/feature seulement cité dans un résultat d'outil : permis"
bash_ "cat $A" "$T_SKILL"
expect_out deny "/feature lancé par le Skill tool : refusé"

echo "orchestrateur, /fix actif — même règle, journal du fix"
F="$TMP_ROOT/fixrepo"; mk_repo "$F"
mkdir -p "$F/lib" "$F/.claude/fixes/crash"
printf 'int b = 1;\n' > "$F/lib/b.dart"; echo '{}' > "$F/.claude/fixes/crash/fix.json"; echo '# diag' > "$F/.claude/fixes/crash/diagnosis.md"
commit "$F" init >/dev/null; git -C "$F" checkout -q -b fix/crash
R="$(cd "$F" && pwd -P)"
bash_ "cat lib/b.dart" "$T_FIX"
expect_out deny "/fix lancé après le /feature : cat de lib/ refusé"
expect_out "/fix ne lit pas de code" "le refus nomme /fix"
expect_file_has "$R/.claude/fixes/crash/.gauntlet/hooks.jsonl" '"hook":"orchestrator-reads"' "le refus est au journal du fix"
bash_ "cat .claude/fixes/crash/diagnosis.md" "$T_FIX"
expect_no_out deny "/fix : le diagnostic dans .claude/fixes/ reste lisible"
bash_ "sed -n '1,10p' lib/b.dart" "$T_FIX"
expect_no_out deny "/fix : un extrait de 10 lignes reste permis"
bash_ "cat lib/b.dart" "$T_FIX" fix-reproducer
expect_no_out deny "/fix : le reproducer n'est jamais bloqué"

finish
