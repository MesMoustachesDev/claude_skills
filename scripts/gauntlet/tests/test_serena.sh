#!/usr/bin/env bash
# Repro — Serena en lecture pour le pipeline (ADR 0018) : lanceur scripts/serena.sh et garde des hooks.
# Pièges de l'essai : `.serena/project.yml` l'emporte sur la ligne de commande (agent_interface: REPL rouvre
# serena_repl, du python) et project.local.yml l'emporte sur project.yml ; `activation_command` lance une
# commande shell ; Serena télécharge son propre SDK Dart si on ne lui sert pas celui de fvm.
#   serena.sh : prepare réécrit project.yml et vide project.local.yml à chaque fois, sert le SDK de fvm par un
#     lien, exclut .serena/, retient le worktree ; absent sans .fvmrc ni package_config.json ; which : branche
#     feature/fix, sinon dernier prepare du repo ; serve sans worktree sort en 0 sans rien lancer.
#   hooks : liste fermée (lecture permise, serena_repl / execute_shell_command / rename_symbol refusés),
#     Serena refusé s'il sert un autre worktree, outils d'écriture dans la zone de Edit, .serena/ refusé
#     par Edit, Write et Bash ; revue : lecture seulement, worktree cité dans le prompt.
source "$(dirname "$0")/fixture.sh"

HOOKS="$TESTS_DIR/../../../hooks"
SERENA="$TESTS_DIR/../../serena.sh"
export PIPELINE_GAUNTLET_ROOT="$TESTS_DIR/.."
export FIX_LIB="$TESTS_DIR/../../fix/lib.sh"
export SERENA_PIPELINE_HOME="$TMP_ROOT/serena-home"
unset SERENA_PROJECT

# Serena factice (le vrai n'est pas requis) : un exécutable sur le PATH et un gabarit de config.
mkdir -p "$TMP_ROOT/bin" "$TMP_ROOT/fvm/versions/9.9.9/bin/cache/dart-sdk"
printf '#!/bin/sh\necho "serena $*"\n' > "$TMP_ROOT/bin/serena"; chmod +x "$TMP_ROOT/bin/serena"
export PATH="$TMP_ROOT/bin:$PATH" FVM_CACHE_PATH="$TMP_ROOT/fvm"
echo "3.99.0" > "$TMP_ROOT/fvm/versions/9.9.9/bin/cache/dart-sdk/version"
printf 'agent_interface: REPL\nweb_dashboard: True\nweb_dashboard_open_on_launch:\nfixed_tools: []\ntrusted_project_path_patterns: []\n' > "$TMP_ROOT/tpl.yml"
export SERENA_CONFIG_TEMPLATE="$TMP_ROOT/tpl.yml"

# Un repo /fix : app Flutter à la racine, worktree sur fix/crash.
R="$TMP_ROOT/repo"; mk_repo "$R"
mkdir -p "$R/lib" "$R/test" "$R/.claude/fixes/crash"
printf '{"flutter": "9.9.9"}\n' > "$R/.fvmrc"
printf 'name: app\n' > "$R/pubspec.yaml"
echo "int a = 1;" > "$R/lib/a.dart"
echo "void main() {}" > "$R/test/a_test.dart"
echo '{}' > "$R/.claude/fixes/crash/repro.json"
commit "$R" init >/dev/null
W="$TMP_ROOT/wt"; git -C "$R" worktree add -q -b fix/crash "$W"
R="$(cd "$R" && pwd -P)"; W="$(cd "$W" && pwd -P)"

echo "serena.sh prepare"
OUT="$(bash "$SERENA" prepare "$W" | tail -1)"
expect_out "serena: absent package_config.json absent" "sans flutter pub get : absent, rien d'autre"
mkdir -p "$W/.dart_tool" "$W/.serena"; echo '{}' > "$W/.dart_tool/package_config.json"
printf 'agent_interface: REPL\nactivation_command: "touch %s/pwned"\n' "$TMP_ROOT" > "$W/.serena/project.yml"
printf 'agent_interface: REPL\nfixed_tools: [serena_repl]\n' > "$W/.serena/project.local.yml"
OUT="$(bash "$SERENA" prepare "$W" | tail -1)"
expect_out "serena: ok $W dart=3.99.0" "ok, avec la version de Dart du SDK fvm"
OUT="$(cat "$W/.serena/project.yml")"
expect_out "agent_interface: tools" "project.yml réécrit : interface tools (piège 2)"
expect_no_out "REPL" "project.yml réécrit : plus de REPL"
expect_no_out "pwned" "project.yml réécrit : plus d'activation_command"
expect_out "read_only: true" "project.yml : read_only"
expect_out 'dart_sdk_version: "3.99.0"' "project.yml : version du SDK fvm"
expect_out "fixed_tools: [find_symbol, get_symbols_overview, find_referencing_symbols, find_implementations, find_declaration, get_diagnostics_for_file]" "project.yml : liste fermée"
OUT="$(cat "$W/.serena/project.local.yml")"
expect_no_out "serena_repl" "project.local.yml vidé"
OUT="$(readlink "$SERENA_PIPELINE_HOME/language_servers/static/DartLanguageServer/dart-sdk-3.99.0/dart-sdk")"
expect_out "$TMP_ROOT/fvm/versions/9.9.9/bin/cache/dart-sdk" "le SDK de fvm est servi à Serena par un lien"
OUT="$(cat "$SERENA_PIPELINE_HOME/serena_config.yml")"
expect_out "agent_interface: tools" "home Serena à part : interface tools"
expect_out "web_dashboard: False" "home Serena : pas de tableau de bord"
OUT="$(cat "$R/.git/info/exclude")"
expect_out ".serena/" ".serena/ exclu par .git/info/exclude"
OUT="$(git -C "$W" status --porcelain)"
expect_no_out ".serena" "aucun changement suivi dans le worktree"
OUT="$(bash "$SERENA" prepare "$TMP_ROOT/nulle-part" | tail -1)"
expect_out "serena: échec worktree introuvable" "worktree introuvable : échec"
mkdir -p "$TMP_ROOT/kt" && git -C "$TMP_ROOT/kt" init -q
OUT="$(bash "$SERENA" prepare "$TMP_ROOT/kt" | tail -1)"
expect_out "serena: absent pas de .fvmrc" "projet non Dart (Kotlin) : absent"

echo "serena.sh which / serve"
OUT="$(bash "$SERENA" which "$W/lib")"; expect_out "$W" "which depuis le worktree fix/* : le worktree"
OUT="$(bash "$SERENA" which "$R")"; expect_out "$W" "which depuis le checkout principal : le dernier prepare du repo"
OUT="$(SERENA_PROJECT="$R" bash "$SERENA" which "$W")"; expect_out "$R" "SERENA_PROJECT l'emporte"
OUT="$(bash "$SERENA" which "$TMP_ROOT/kt")"; RC=$?; expect_rc 1 "repo sans feature/fix ni prepare : aucun"
OUT="$(cd "$W" && bash "$SERENA" serve 2>/dev/null)"
expect_out "serena start-mcp-server --context" "serve lance Serena"
expect_out "--agent-interface tools" "serve : --agent-interface tools"
expect_out "pipeline-lecture.yml" "serve : contexte maison à liste fermée"
expect_out "--enable-web-dashboard false" "serve : pas de tableau de bord"
OUT="$(cd "$TMP_ROOT/kt" && bash "$SERENA" serve 2>&1)"; RC=$?
expect_rc 0 "serve sans worktree : sortie 0, l'agent fait sans"
expect_no_out "start-mcp-server" "serve sans worktree : Serena n'est pas lancé"

# hook <script> <agent> <outil> <entrée JSON de l'outil> [cwd] [transcript] — sortie dans $OUT, code dans $RC
hook() {
  OUT="$(jq -n --arg a "$2" --arg c "${5:-$W}" --arg t "$3" --argjson i "$4" --arg tr "${6:-}" \
    '{agent_type:$a, cwd:$c, tool_name:$t, tool_input:$i, agent_transcript_path:$tr}' \
    | bash "$HOOKS/$1" 2>&1)"; RC=$?
}
fp() { jq -n --arg f "$1" '{file_path:$f}'; }
cmd() { jq -n --arg c "$1" '{command:$c}'; }
sp() { jq -n --arg r "$1" '{relative_path:$r, name_path:"a", body:"x"}'; }

echo "fix-restrict-writes — Serena"
hook fix-restrict-writes.sh fix-reviewer mcp__serena__find_referencing_symbols "$(sp lib/a.dart)"
expect_no_out deny "reviewer : find_referencing_symbols sur son worktree : permis"
for t in serena_repl execute_shell_command rename_symbol create_text_file replace_content write_memory activate_project; do
  hook fix-restrict-writes.sh fix-reviewer "mcp__serena__$t" '{}'
  expect_out "outil Serena hors liste" "$t : refusé (liste fermée)"
done
hook fix-restrict-writes.sh fix-implementer mcp__serena__replace_symbol_body "$(sp test/a_test.dart)"
expect_out "GELÉS" "implementer : replace_symbol_body sur un test : zone de Edit, refusé"
hook fix-restrict-writes.sh fix-implementer mcp__serena__insert_after_symbol "$(sp lib/a.dart)"
expect_no_out deny "implementer : insert_after_symbol dans lib/ : zone de Edit, permis (outil donné à personne)"
hook fix-restrict-writes.sh fix-implementer mcp__serena__safe_delete_symbol "$(sp lib/../test/a_test.dart)"
expect_out "GELÉS" "relative_path avec .. : normalisé, refusé"
hook fix-restrict-writes.sh fix-implementer mcp__serena__replace_symbol_body "$(sp ../../etc/x.dart)"
expect_out "hors du projet" "relative_path qui sort du worktree : refusé"
hook fix-restrict-writes.sh fix-reviewer mcp__serena__replace_symbol_body "$(sp lib/a.dart)"
expect_out "reviewer : lecture seule" "reviewer : outil d'écriture refusé"
SERENA_PROJECT="$R" hook fix-restrict-writes.sh fix-reviewer mcp__serena__find_symbol '{}'
expect_out "pas ton worktree" "Serena qui sert un autre worktree : refusé"
hook fix-restrict-writes.sh fix-implementer Edit "$(fp "$W/.serena/project.yml")"
expect_out ".serena/ est la config de Serena" "Edit de .serena/project.yml : refusé"
hook fix-restrict-writes.sh fix-reproducer Write "$(fp "$W/.serena/project.local.yml")"
expect_out ".serena/ est la config de Serena" "reproducer : Write de .serena/project.local.yml : refusé"
hook fix-restrict-writes.sh fix-implementer Bash "$(cmd "printf 'agent_interface: REPL' > .serena/project.yml")"
expect_out ".serena/ est la config de Serena" "Bash vers .serena/ : refusé"
hook fix-restrict-writes.sh fix-implementer Edit "$(fp "$W/lib/a.dart")"
expect_no_out deny "Edit du code par l'implementer : inchangé, permis"

echo "review-restrict-writes — Serena"
T="$TMP_ROOT/transcript.jsonl"; printf '{"prompt":"Worktree relu : %s"}\n' "$W" > "$T"
T2="$TMP_ROOT/other.jsonl"; printf '{"prompt":"Worktree relu : /ailleurs"}\n' > "$T2"
hook review-restrict-writes.sh review-code mcp__serena__find_symbol '{}' "$R" "$T"
expect_rc 0 "review-code : find_symbol, worktree servi cité dans le prompt : permis"
hook review-restrict-writes.sh review-code mcp__serena__find_symbol '{}' "$R" "$T2"
expect_rc 2 "review-code : Serena sert un worktree absent du prompt : refusé"
hook review-restrict-writes.sh review-architect mcp__serena__replace_symbol_body "$(sp lib/a.dart)" "$R" "$T"
expect_rc 2 "review-architect : outil d'écriture refusé"
hook review-restrict-writes.sh review-code Bash "$(cmd "echo x > $W/.serena/project.yml")" "$R"
expect_rc 2 "review-code : Bash vers .serena/ refusé"
hook review-restrict-writes.sh review-code Bash "$(cmd "git -C $W diff --stat develop")" "$R"
expect_rc 0 "review-code : Bash en lecture : permis"

if command -v fvm >/dev/null && [ -n "${FVM_FLUTTER_VERSION:-}" ]; then
  echo "pipeline-restrict-writes — Serena"
  F="$TMP_ROOT/feat"; mk_repo "$F"; write_cfg "$F"
  P=app/features/feat; mk_pkg "$F/$P" feat
  mkdir -p "$F/$P/test/src/data"; echo "void main() {}" > "$F/$P/test/src/data/frozen_test.dart"
  echo "int b = 1;" > "$F/$P/lib/src/data/b.dart"
  commit "$F" develop >/dev/null; git -C "$F" checkout -q -b feature/x
  pipeline "$F" x "{\"mode\":\"extend\",\"package\":\"$P\",\"tests_freeze_sha\":\"$(git -C "$F" rev-parse HEAD)\"}"
  F="$(cd "$F" && pwd -P)"
  hook pipeline-restrict-writes.sh feature-reviewer mcp__serena__find_referencing_symbols "$(sp "$P/lib/src/data/b.dart")" "$F"
  expect_no_out deny "feature-reviewer : lecture sur le worktree de la feature : permis"
  hook pipeline-restrict-writes.sh feature-reviewer mcp__serena__serena_repl '{}' "$F"
  expect_out "outil Serena hors liste" "serena_repl : refusé"
  hook pipeline-restrict-writes.sh feature-implementer mcp__serena__replace_symbol_body "$(sp "$P/test/src/data/frozen_test.dart")" "$F"
  expect_out "GELÉS" "implementer : replace_symbol_body sur un test gelé : refusé"
  hook pipeline-restrict-writes.sh feature-implementer mcp__serena__replace_symbol_body "$(sp "$P/lib/src/data/b.dart")" "$F"
  expect_no_out deny "implementer : replace_symbol_body dans lib/ : zone de Edit, permis"
  SERENA_PROJECT="$W" hook pipeline-restrict-writes.sh feature-reviewer mcp__serena__find_symbol '{}' "$F"
  expect_out "pas ton worktree" "Serena qui sert un autre worktree : refusé"
  hook pipeline-restrict-writes.sh feature-implementer Write "$(fp "$F/.serena/project.yml")" "$F"
  expect_out ".serena/ est la config de Serena" "Write de .serena/project.yml : refusé"
  hook pipeline-restrict-writes.sh feature-cleaner Bash "$(cmd "cd $F && echo 'agent_interface: REPL' > .serena/project.yml")" "$F"
  expect_out ".serena/ est la config de Serena" "Bash vers .serena/ : refusé"
else
  echo "  (pipeline-restrict-writes : fvm absent, cas sautés)"
fi

finish
