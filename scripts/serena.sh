#!/usr/bin/env bash
# serena.sh — Serena (serveur MCP adossé au LSP Dart) pour le pipeline, en lecture seule (ADR 0018).
#
#   serena.sh prepare <worktree>   prépare le worktree et retient que c'est lui que Serena doit servir.
#                                  Sort toujours en 0 ; la dernière ligne de stdout donne l'état :
#                                  `serena: ok <worktree> dart=<version>`, `serena: absent <raison>`,
#                                  `serena: échec <raison>`. Lancé par /feature, /fix et /reviewPR.
#   serena.sh serve [<worktree>]   le serveur MCP des sous-agents (mcpServers de leur frontmatter) : retrouve
#                                  le worktree (`which`), le prépare, puis lance Serena. Sans worktree ou
#                                  sans Serena : message sur stderr et sortie 0, l'agent travaille sans.
#   serena.sh which <dossier>      le worktree que `serve` servirait depuis ce dossier (le cwd du serveur) :
#                                  $SERENA_PROJECT, sinon la racine git du dossier si elle est sur une branche
#                                  feature/* ou fix/*, sinon le dernier `prepare` du même repo. Lu aussi par
#                                  les hooks *-restrict-writes.sh, qui refusent Serena quand ce n'est pas le
#                                  worktree de l'agent.
#
# Ce que prepare tient, à chaque appel (Serena lit sa config au démarrage, un agent ne doit pas la changer) :
#   - une home Serena à part ($SERENA_PIPELINE_HOME, défaut ~/.claude-local/serena), jamais ~/.serena :
#     serena_config.yml réécrit (interface `tools`, pas de tableau de bord, outils en liste fermée,
#     projets « trusted » : le project.yml ci-dessous n'est appliqué qu'à un projet trusted) ;
#   - le SDK Dart de fvm (.fvmrc) servi à Serena par un lien sous
#     <home>/language_servers/static/DartLanguageServer/dart-sdk-<version>/dart-sdk : Serena n'a pas
#     d'option de chemin, et sans ce lien il télécharge un autre SDK, sans vérification ;
#   - <worktree>/.serena/project.yml réécrit (dart, version du SDK, interface `tools`, read_only, liste
#     fermée, pas d'activation_command) et project.local.yml vidé : ils l'emportent sur la ligne de
#     commande (piège 2 de la note d'essai) ;
#   - `.serena/` dans .git/info/exclude.
# Absent (pipeline sans Serena, comme graphify) : Serena non installé, pas de pubspec.yaml ni de .fvmrc
# (projet non Dart : rien pour Kotlin), package_config.json absent (`flutter pub get` pas fait).
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXT="$here/../serena/contexts/pipeline-lecture.yml"
SHOME="${SERENA_PIPELINE_HOME:-$HOME/.claude-local/serena}"
FIXED_TOOLS="[find_symbol, get_symbols_overview, find_referencing_symbols, find_implementations, find_declaration, get_diagnostics_for_file]"

serena_bin() { command -v serena 2>/dev/null || { [ -x "$HOME/.local/bin/serena" ] && echo "$HOME/.local/bin/serena"; }; }

# repo_key <dossier> — identifiant du repo (dossier .git commun, partagé par ses worktrees)
repo_key() {
  local c; c="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  printf '%s' "$(cd "$c" && pwd -P)" | shasum | cut -c1-16
}

which_wt() {
  local d="${1:-$PWD}" top br k p
  if [ -n "${SERENA_PROJECT:-}" ] && [ -d "$SERENA_PROJECT" ]; then (cd "$SERENA_PROJECT" && pwd -P); return 0; fi
  top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" || return 1
  top="$(cd "$top" && pwd -P)"
  br="$(git -C "$top" branch --show-current 2>/dev/null)"
  case "$br" in feature/*|fix/*) printf '%s\n' "$top"; return 0 ;; esac
  k="$(repo_key "$top")" || return 1
  p="$(cat "$SHOME/pointers/$k" 2>/dev/null)"
  [ -n "$p" ] && [ -d "$p" ] && { printf '%s\n' "$p"; return 0; }
  return 1
}

# app_root <worktree> — le dossier de l'app (où vit .fvmrc) : la racine, app_dir de la config, sinon le
# premier .fvmrc à deux niveaux
app_root() {
  local w="$1" d cfgf
  [ -f "$w/.fvmrc" ] && { printf '%s' "$w"; return 0; }
  for cfgf in "$w/.claude/rules/feature_pipeline.md"; do
    d="$(awk '/^```ini/{f=1;next} /^```/{f=0} f' "$cfgf" 2>/dev/null | grep -E '^[[:space:]]*app_dir[[:space:]]*=' \
      | head -1 | sed 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$d" ] && [ -f "$w/$d/.fvmrc" ] && { printf '%s' "$w/${d%/}"; return 0; }
  done
  d="$(find "$w" -maxdepth 3 -name .fvmrc -not -path '*/.dart_tool/*' -not -path '*/build/*' 2>/dev/null | head -1)"
  [ -n "$d" ] && { printf '%s' "$(dirname "$d")"; return 0; }
  return 1
}

# atomic <fichier> — écrit stdin dans le fichier par renommage (deux serveurs peuvent démarrer ensemble)
atomic() { local t; t="$(mktemp "$1.XXXXXX")" && cat > "$t" && mv -f "$t" "$1"; }

write_home_config() {
  local tpl
  mkdir -p "$SHOME/pointers" || return 1
  tpl="${SERENA_CONFIG_TEMPLATE:-}"                     # surcharge : tests du lanceur
  if [ -z "$tpl" ]; then
    tpl="$(dirname "$(dirname "$(readlink -f "$(serena_bin)")")")"
    tpl="$(ls "$tpl"/lib/python3*/site-packages/serena/resources/serena_config.template.yml 2>/dev/null | head -1)"
  fi
  [ -f "$tpl" ] || return 1
  sed -E \
    -e 's/^agent_interface:.*/agent_interface: tools/' \
    -e 's/^gui_log_window:.*/gui_log_window: False/' \
    -e 's/^web_dashboard:.*/web_dashboard: False/' \
    -e 's/^web_dashboard_open_on_launch:.*/web_dashboard_open_on_launch: False/' \
    -e "s/^fixed_tools:.*/fixed_tools: $FIXED_TOOLS/" \
    -e 's/^trusted_project_path_patterns:.*/trusted_project_path_patterns: ["**"]/' \
    "$tpl" | atomic "$SHOME/serena_config.yml"
}

# prepare <worktree> — imprime « ok <wt> dart=<v> », « absent <raison> » ou « échec <raison> »
prepare() {
  local w="$1" app flutter sdk dv link common k
  [ -d "$w" ] || { echo "échec worktree introuvable : $w"; return; }
  w="$(cd "$w" && pwd -P)"
  [ -n "$(serena_bin)" ] || { echo "absent serena non installé"; return; }
  app="$(app_root "$w")" || { echo "absent pas de .fvmrc (projet non Dart, ou SDK non épinglé)"; return; }
  [ -f "$app/pubspec.yaml" ] || { echo "absent pas de pubspec.yaml dans ${app#$w/}"; return; }
  [ -f "$app/.dart_tool/package_config.json" ] \
    || { echo "absent package_config.json absent (flutter pub get pas fait dans ${app#$w/})"; return; }
  flutter="$(jq -r '.flutter // .flutterSdkVersion // empty' "$app/.fvmrc" 2>/dev/null)"
  [ -n "$flutter" ] || { echo "échec .fvmrc illisible"; return; }
  sdk="${FVM_CACHE_PATH:-$HOME/fvm}/versions/$flutter/bin/cache/dart-sdk"
  dv="$(cat "$sdk/version" 2>/dev/null)"
  [ -n "$dv" ] || { echo "échec SDK fvm $flutter absent ($sdk ; fvm install $flutter)"; return; }
  write_home_config || { echo "échec config Serena (gabarit introuvable)"; return; }
  link="$SHOME/language_servers/static/DartLanguageServer/dart-sdk-$dv/dart-sdk"
  if [ ! -e "$link" ] || { [ -L "$link" ] && [ "$(readlink "$link")" != "$sdk" ]; }; then
    mkdir -p "$(dirname "$link")" && ln -sfn "$sdk" "$link" || { echo "échec lien du SDK : $link"; return; }
  fi
  mkdir -p "$w/.serena" || { echo "échec $w/.serena"; return; }
  atomic "$w/.serena/project.yml" <<EOF || { echo "échec project.yml"; return; }
# Réécrit par ~/.claude/scripts/serena.sh à chaque démarrage (ADR 0018) : ne pas modifier.
project_name: "$(basename "$w")"
language_servers: [dart]
encoding: "utf-8"
activation_command:
agent_interface: tools
ignore_all_files_in_gitignore: true
ls_specific_settings: {dart: {dart_sdk_version: "$dv"}}
ls_workspace_folders: ["."]
ls_additional_workspace_folders: []
ignored_paths: []
read_only: true
excluded_tools: []
included_optional_tools: []
fixed_tools: $FIXED_TOOLS
excluded_apis: []
included_apis: []
default_modes:
added_modes:
initial_prompt: ""
EOF
  printf '# Vidé par ~/.claude/scripts/serena.sh : il l emporterait sur project.yml.\n' | atomic "$w/.serena/project.local.yml"
  common="$(git -C "$w" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  if [ -n "$common" ]; then
    mkdir -p "$common/info"
    grep -qxF '.serena/' "$common/info/exclude" 2>/dev/null || echo '.serena/' >> "$common/info/exclude"
  fi
  k="$(repo_key "$w")" && printf '%s\n' "$w" | atomic "$SHOME/pointers/$k"
  echo "ok $w dart=$dv"
}

cmd="${1:-}"
case "$cmd" in
  prepare)
    [ -n "${2:-}" ] || { echo "usage : serena.sh prepare <worktree>" >&2; exit 2; }
    echo "serena: $(prepare "$2")"
    exit 0 ;;
  which)
    which_wt "${2:-$PWD}" ;;
  serve)
    w="${2:-}"; [ -n "$w" ] || w="$(which_wt "$PWD")" \
      || { echo "serena: absent pas de worktree feature/fix ni de prepare pour $PWD" >&2; exit 0; }
    st="$(prepare "$w")"
    case "$st" in ok*) ;; *) echo "serena: $st" >&2; exit 0 ;; esac
    w="$(cd "$w" && pwd -P)"
    export SERENA_HOME="$SHOME"
    exec "$(serena_bin)" start-mcp-server --context "$CONTEXT" --agent-interface tools --project "$w" \
      --enable-web-dashboard false --open-web-dashboard false --enable-gui-log-window false ;;
  *) echo "usage : serena.sh prepare <worktree> | serve [<worktree>] | which <dossier>" >&2; exit 2 ;;
esac
