#!/usr/bin/env bash
# Repro — interpréteurs refusés aux sous-agents (ADR 0017, hooks/no-interpreter.sh).
# Cas réels (scan des transcripts feature-* / fix-* jusqu'au 2026-11-19, chemins anonymisés) : ~1 200 écritures
# par `python3 - <<'EOF' … open(p,'w').write(s)`, invisibles à bash_write_targets.py ; un implementer copie un
# test gelé dans test/zz_debug_test.dart par python ; un relecteur rejoue des tests copiés dans /tmp avec
# `node --test` ; des `perl -0pi -e` ; une QA écrit puis lance un pont python dans maestro/support/.
#   refusés : code inline (-c, -e, -, heredoc, <<<, tube), à travers bash -c / eval / env / xargs / find -exec /
#     chemin absolu, scripts écrits pendant la session (scratchpad, /tmp, non suivis, modifiés), perl -pi,
#     awk -i inplace, shell qui lit son script sur l'entrée standard ;
#   permis : scripts du pipeline (~/.claude/scripts, $HOME/…, chemin absolu), python3 -m, node --test dans le
#     projet, script suivi et inchangé, outils du projet (fvm, dart run build_runner), l'orchestrateur.
source "$(dirname "$0")/fixture.sh"

HOOK="$TESTS_DIR/../../../hooks/no-interpreter.sh"
export PIPELINE_GAUNTLET_ROOT="$TESTS_DIR/.."
export INTERPRETER_TMP_DIRS="/tmp:/private/tmp"                 # le dépôt de test vit sous $TMPDIR
R="$TMP_ROOT/repo"; mkdir -p "$R/pkg/lib" "$R/pkg/test" "$R/tool" "$R/maestro/support" "$R/node/tests"
echo "int a = 1;" > "$R/pkg/lib/a.dart"
echo "void main() {}" > "$R/pkg/test/a_test.dart"
echo "print('gen')" > "$R/tool/gen.py"
echo "print('old')" > "$R/tool/edited.py"
printf '#!/bin/sh\necho ok\n' > "$R/tool/run.sh"; chmod +x "$R/tool/run.sh"
echo "test('a', () => {})" > "$R/node/tests/a.test.js"
git -C "$R" init -q -b develop && git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -q -m init
echo "print('new')" > "$R/tool/edited.py"                                    # modifié pendant la session
echo "print('bridge')" > "$R/maestro/support/adb_bridge.py"                   # écrit pendant la session
printf '#!/bin/sh\necho new\n' > "$R/tool/new.sh"; chmod +x "$R/tool/new.sh"
S="$TMP_ROOT/scratchpad"; mkdir -p "$S"; echo "print(1)" > "$S/apply5.py"; echo "void main() {}" > "$S/probe.dart"
R="$(cd "$R" && pwd -P)"; S="$(cd "$S" && pwd -P)"

# hook <agent> <commande> — décision du hook dans $OUT
hook() {
  OUT="$(jq -n --arg a "$1" --arg c "$R" --arg s "$S" --arg v "$2" \
    '{agent_type:$a, cwd:$c, scratchpad_dir:$s, tool_name:"Bash", tool_input:{command:$v}}' \
    | bash "$HOOK" 2>&1)"
}
denied()  { hook "$1" "$2"; expect_out '"deny"' "$3"; }
allowed() { hook "$1" "$2"; expect_no_out deny "$3"; }

echo "Cas réels — refusés"
denied feature-implementer "cd $R/pkg && python3 - <<'EOF'
p='test/a_test.dart'
s=open(p).read()
open(p,'w').write(s.replace('main', 'main2'))
EOF" "implementer : python3 - <<EOF qui réécrit un test (le motif des ~1 200 écritures)"
OUT_MSG="$OUT"
denied feature-implementer "cd $R/pkg && python3 -I - <<'EOF'
import shutil; shutil.copy('test/a_test.dart', 'test/zz_debug_test.dart')
EOF
fvm flutter test test/zz_debug_test.dart; rm test/zz_debug_test.dart" "implementer : copie d'un test gelé en zz_debug par python"
denied feature-reviewer "python3 -I -c \"import json; print(json.load(open('.claude/features/x/review.json'))['verdict'])\"" \
  "reviewer : python3 -c pour lire du JSON"
denied feature-cleaner "cd $R/pkg && perl -0pi -e 's/int a/final int a/' lib/a.dart" "cleaner : perl -0pi -e"
denied feature-hardener "S=$S; python3 -I \$S/apply5.py" "hardener : script du scratchpad (variable développée)"
denied fix-implementer "cat > $S/gen.py <<'EOF'
print(1)
EOF
python3 $S/gen.py" "fix-implementer : script écrit et lancé dans la même commande"
denied fix-reviewer "mkdir -p /tmp/victor_mut5 && cd /tmp/victor_mut5 && PATH=\"/opt/homebrew/opt/node@22/bin:\$PATH\" node --test --test-name-pattern=\"deadline\" tests/a.test.js" \
  "reviewer : node --test sur des tests copiés dans /tmp"
denied fix-reproducer "python3 /dev/stdin <<'EOF'
print(1)
EOF" "reproducer : python3 /dev/stdin"
denied feature-implementer "perl -e 'select(undef,undef,undef,5)'; fvm flutter test" "perl -e (même pour attendre : sleep)"
denied feature-qa "pkill -f adb_bridge.py; cd $R && (nohup python3 maestro/support/adb_bridge.py emulator-5560 > /tmp/bridge.log 2>&1 &); sleep 1" \
  "qa : pont python écrit pendant la session, non suivi"
denied feature-implementer "python3 tool/edited.py" "script suivi mais modifié depuis HEAD"

echo "Contournements — refusés"
denied feature-implementer "bash -c \"python3 -c 'print(1)'\"" "bash -c"
denied feature-implementer "sh -c 'cd pkg && perl -pi -e s/a/b/ lib/a.dart'" "sh -c avec perl -pi"
denied feature-implementer "eval \"python3 -c 1\"" "eval"
denied feature-implementer "X='python3 -c 1'; eval \$X" "eval d'une variable"
denied feature-implementer "env FOO=1 /usr/bin/python3 -c 'print(1)'" "env + chemin absolu"
denied feature-implementer "timeout 30 python3 -c 'print(1)'" "timeout"
denied feature-implementer "ls pkg/lib | xargs -I{} python3 {}" "xargs"
denied feature-implementer "find pkg -name '*.dart' -exec perl -pi -e 's/a/b/' {} +" "find -exec perl -pi"
denied feature-implementer "echo 'print(1)' | python3" "code par un tube"
denied feature-implementer "python3 <<< 'print(1)'" "<<<"
denied feature-implementer "node -e 'require(\"fs\").writeFileSync(\"x\", \"y\")'" "node -e"
denied feature-implementer "node -pe 1" "node -pe"
denied feature-implementer "ruby -e 'File.write(\"x\", 1)'" "ruby -e"
denied feature-implementer "php -r 'file_put_contents(\"x\", 1);'" "php -r"
denied feature-implementer "deno eval 'Deno.writeTextFileSync(\"x\", \"y\")'" "deno eval"
denied feature-implementer "bun -e '1'" "bun -e"
denied feature-implementer "python3 -Ic 'print(1)'" "python3 -Ic (drapeaux collés)"
denied feature-implementer "awk -i inplace '{print}' pkg/lib/a.dart" "awk -i inplace"
denied feature-implementer "bash <<'EOF'
python3 -c 1
EOF" "bash qui lit son script sur un heredoc"
denied feature-implementer "fvm dart run $S/probe.dart" "dart run d'un script du scratchpad"
denied feature-implementer "./tool/new.sh" "exécutable non suivi, lancé par son chemin"
denied feature-implementer "bash tool/new.sh" "bash d'un script non suivi"
denied feature-implementer "for f in a b; do python3 \$f.py; done" "script dont le chemin est inconnu"
expect_out_in() { grep -qF -- "$1" <<<"$OUT_MSG" && _pass "$2" || { OUT="$OUT_MSG"; _fail "$2 — sans « $1 »"; }; }
expect_out_in "Edit ou MultiEdit" "le refus dit d'écrire par Edit ou MultiEdit"
expect_out_in "jq" "le refus dit de lire le JSON avec jq"
expect_out_in "Un refus se rapporte, il ne se contourne pas" "le refus dit qu'un refus se rapporte"

echo "Scripts du pipeline et outils du projet — permis"
allowed feature-test-planner "cd $R && python3 ~/.claude/scripts/gauntlet/test_plan.py items .claude/features/x/spec.md" "test_plan.py par ~"
allowed feature-test-planner "python3 -I \$HOME/.claude/scripts/gauntlet/test_plan.py check spec.md tests_plan.json mobile" "test_plan.py par \$HOME, -I"
allowed feature-test-planner "python3 -I $HOME/.claude/scripts/gauntlet/test_plan.py items spec.md; echo EXIT \$?" "test_plan.py par chemin absolu"
allowed feature-test-planner "python3 -I ~/.claude/scripts/gauntlet/test_plan.py check spec.md - <<'EOF'
{\"tests\": []}
EOF" "heredoc de données vers un script du pipeline"
allowed fix-reproducer "python3 -m json.tool .claude/fixes/x/repro.json >/dev/null && ~/.claude/scripts/fix_gauntlet.sh red x" "python3 -m json.tool, fix_gauntlet.sh"
allowed fix-reproducer "cd $R/node && PATH=\"/opt/homebrew/opt/node@22/bin:\$PATH\" node --test tests/a.test.js 2>&1 | tail -8" "node --test dans le projet"
allowed fix-reproducer "node --version && ls code/functions" "node --version"
allowed feature-implementer "python3 tool/gen.py" "script suivi et inchangé du projet"
allowed feature-implementer "./tool/run.sh && bash tool/run.sh" "exécutable suivi et inchangé"
allowed feature-implementer "cd $R/pkg && fvm dart run build_runner build -d && fvm flutter test test/a_test.dart" "fvm dart run build_runner, flutter test"
allowed feature-implementer "~/.claude/scripts/gauntlet.sh green x > $S/g.log 2>&1; tail -5 $S/g.log" "gauntlet.sh, journal dans le scratchpad"
allowed feature-qa "/usr/bin/true -s emulator-5560 shell settings put secure location_mode 0" "outil installé hors dépôt, par chemin absolu"
allowed feature-reviewer "grep -rn 'python3 -c' pkg; git log --oneline -3; awk '{print \$1}' pkg/lib/a.dart" "grep, awk sans -i inplace"
allowed feature-reviewer "jq -r '.verdict' .claude/features/x/review.json" "jq"

echo "Hors périmètre — l'orchestrateur et les autres agents"
allowed "" "python3 - <<'EOF'
print(1)
EOF" "orchestrateur (agent_type vide) : python permis"
allowed review-code "python3 -c 'print(1)'" "agent hors feature-*/fix-* : non concerné"

finish
