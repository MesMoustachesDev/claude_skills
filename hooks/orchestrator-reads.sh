#!/usr/bin/env bash
# orchestrator-reads.sh — PreToolUse (Read|Grep|Glob|Bash) de settings.json (ADR 0020).
# L'orchestrateur d'un /feature ne lit pas de code : une question sur le code part à l'agent de l'étape, qui
# rend un fait. Chaque lecture de l'orchestrateur reste dans son contexte jusqu'à la fin de la session.
#
# Qui : la session principale seulement (ni agent_type ni agent_id : un sous-agent n'est jamais concerné), et
# seulement pendant un /feature : la dernière commande d'orchestration de son transcript (feature, fix, epic,
# reviewPR ; tapée `/feature` ou appelée par le Skill tool) est `feature`. Une autre commande (create_mr, que
# /feature appelle lui-même ; /compact, /model…) ne change rien ; un /fix, un /reviewPR ou un /epic lancé après, si.
#
# Refusé :
#   - un fichier de code : un chemin dont un dossier est lib, test, tests, integration_test, test_driver ou src,
#     ou un fichier source (.dart, .kt, .swift, .ts…) — par Read, Grep, Glob, et par Bash : cat, less, more,
#     bat, nl, awk, sed, head, tail, grep, rg, ls, find, tree ;
#   - une recherche récursive (grep -r, rg, find, tree, ls -R, Grep, Glob) dans un dossier qui contient du code,
#     sauf restreinte à des fichiers qui n'en sont pas (--include, -g, -name, glob : *.md, *.json…) ;
#   - le log entier du gauntlet (.gauntlet/*.log) par Read sans limit, cat, less, more ou bat : le gate en
#     donne le résumé.
# Permis :
#   - les fichiers du pipeline : tout ce qui est sous un dossier .claude du projet (.claude/features/<nom>/,
#     pipeline.json, spec.md, .claude/rules/) hors .claude/worktrees/, ~/.claude (steps, scripts), le scratchpad ;
#   - un extrait à montrer à Thibault (fichier:ligne) : Read avec limit ≤ EXCERPT_MAX, sed -n 'a,bp' ou head/tail
#     de EXCERPT_MAX lignes au plus, sur un fichier nommé ;
#   - le log du gauntlet par tail, head, grep, sed, ou Read avec limit ; last_<profil>.json par jq ;
#   - ls d'un dossier qui n'est pas du code (racine d'un package), wc, jq, git.
set -u
EXCERPT_MAX=40
raw="$(cat)"
# Chemins rapides : ce hook voit chaque appel d'outil de chaque session.
case "$(jq -r '.tool_name // empty' <<<"$raw")" in Read|Grep|Glob|Bash) ;; *) exit 0 ;; esac
[ -z "$(jq -r '(.agent_type // "") + (.agent_id // "")' <<<"$raw")" ] || exit 0
transcript="$(jq -r '.transcript_path // empty' <<<"$raw")"
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

# Les commandes qui orchestrent un run. Les autres (create_mr, create_commits, appelées par /feature lui-même,
# et les commandes intégrées) ne le terminent pas.
ORCHESTRATORS=' feature fix epic reviewPR '
# feature_active — la dernière commande d'orchestration du transcript est /feature
feature_active() {
  local n last=""
  while IFS= read -r n; do
    n="${n#<command-name>/}"; n="${n%%<*}"; n="${n#\"skill\":\"}"; n="${n%\"}"
    case "$ORCHESTRATORS" in *" $n "*) last="$n" ;; esac
  # Seulement un vrai message de Thibault (content qui commence par <command-message>) ou un vrai appel du
  # Skill tool : le même texte cité dans un résultat d'outil ou un fichier écrit a ses guillemets échappés.
  done < <(grep -oE '"role":"user","content":"<command-message>[^<]*</command-message>(\\n)?<command-name>/[A-Za-z0-9_-]+<|"name":"Skill","input":\{"skill":"[A-Za-z0-9_-]+"' "$transcript" 2>/dev/null \
    | grep -oE '<command-name>/[A-Za-z0-9_-]+<|"skill":"[A-Za-z0-9_-]+"')
  [ "$last" = feature ]
}
feature_active || exit 0

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hook_input <<<"$raw"
HOOK_NAME=orchestrator-reads
CLAUDE_HOME="$(cd "$HOOKS_DIR/.." && pwd -P)"
CODE_DIRS='lib test tests integration_test test_driver src'
CODE_EXT='dart kt kts java swift m mm h c cc cpp ts tsx js jsx mjs py rb go rs cs php scala vue svelte'

# path_kind <chemin absolu> — log | pipeline | code | other
path_kind() {
  local p="$1" inner d e
  case "$p" in */.gauntlet/*.log) echo log; return ;; esac
  case "$p" in "$CLAUDE_HOME"|"$CLAUDE_HOME"/*|"$HOME/.claude"|"$HOME/.claude"/*) echo pipeline; return ;; esac
  [ -n "$scratch" ] && case "$p" in "$scratch"|"$scratch"/*) echo pipeline; return ;; esac
  # Un worktree de feature vit dans <projet>/.claude/worktrees/ : son code n'est pas un fichier du pipeline.
  inner="$p"
  case "$p" in */.claude/worktrees/*) inner="${p##*/.claude/worktrees/}"; inner="/${inner#*/}" ;; esac
  case "$inner/" in */.claude/*) echo pipeline; return ;; esac
  for d in $CODE_DIRS; do case "$inner/" in */"$d"/*) echo code; return ;; esac; done
  for e in $CODE_EXT; do case "$p" in *."$e") echo code; return ;; esac; done
  echo other
}

# glob_is_code <motif> — le motif peut désigner du code : extension source, dossier de code, ou rien de
# restreint (*, **/*)
glob_is_code() {
  local g="$1" last d e
  [ -n "$g" ] || return 0
  for e in $CODE_EXT; do case "$g" in *."$e"|*."$e"[,\}]*|*,"$e"[,\}]*) return 0 ;; esac; done
  for d in $CODE_DIRS; do case "/$g/" in */"$d"/*) return 0 ;; esac; done
  last="${g##*/}"
  case "$last" in *.*) return 1 ;; *) return 0 ;; esac
}

# has_code_below <dossier> — un dossier de code jusqu'à 4 niveaux, hors .git, .claude, build
has_code_below() {
  local d="$1" a
  [ -d "$d" ] || return 1
  a=(); for x in $CODE_DIRS; do a+=(-name "$x" -o); done; unset 'a[${#a[@]}-1]'
  [ -n "$(find "$d" -maxdepth 4 \( -name .git -o -name .claude -o -name build -o -name node_modules \
    -o -name .dart_tool -o -name .gradle -o -name Pods \) -prune -o -type d \( "${a[@]}" \) -print -quit 2>/dev/null)" ]
}

# journal (ADR 0019) : le dossier de la feature du worktree visé ou du cwd, s'il est connu
set_run_dir() {
  hook_run_root feature "${cwd:-$PWD}" "${1:-}" 2>/dev/null || return 0
  [ -n "$HOOK_RUN" ] && [ -d "$HOOK_ROOT/.claude/features/$HOOK_RUN" ] && RUN_DIR="$HOOK_ROOT/.claude/features/$HOOK_RUN"
  return 0
}

WHY_CODE="L'orchestrateur d'un /feature ne lit pas de code (ADR 0020) : chaque lecture reste dans ton contexte jusqu'à la fin de la session. \
La question part à l'agent de l'étape : passe-lui le chemin et ce que tu cherches, il te rend un fait. \
Pour montrer un extrait à Thibault (fichier:ligne) : Read avec offset et limit ≤ $EXCERPT_MAX, ou sed -n 'a,bp' <fichier> ($EXCERPT_MAX lignes au plus). \
Les fichiers du pipeline (.claude/features/<nom>/, pipeline.json, steps) restent lisibles. Un refus se rapporte, il ne se contourne pas."
WHY_LOG="Le log entier du gauntlet ne se lit pas (ADR 0020) : le gate en donne le résumé, sa sortie et .gauntlet/last_<profil>.json (jq '.failed'). \
Pour un check précis : tail -60, grep -n <check> sur le log, ou Read avec limit."

deny_code() { set_run_dir "$1"; LOG_TARGET="$1"; hook_deny "orchestrator-reads : $2 refusé ($1). $WHY_CODE" "$2 : code lu par l'orchestrateur"; }
deny_log()  { set_run_dir "$1"; LOG_TARGET="$1"; hook_deny "orchestrator-reads : $2 refusé ($1). $WHY_LOG" "$2 : log entier du gauntlet"; }

# check_dir_search <dossier> <outil> <motif de restriction ou ""> — recherche récursive dans un dossier
check_dir_search() {
  local d="$1" k
  k="$(path_kind "$d")"
  case "$k" in
    pipeline|log) return 0 ;;
    code) deny_code "$d" "$2" ;;
  esac
  [ -d "$d" ] || return 0
  if [ -n "$3" ]; then glob_is_code "$3" || return 0; fi
  has_code_below "$d" && deny_code "$d" "$2 récursif"
  return 0
}

# ---------------------------------------------------------------------------- outils dédiés
case "$tool" in
  Read)
    f="$(jq -r '.tool_input.file_path // empty' <<<"$input")"; [ -n "$f" ] || exit 0
    abs="$(hook_normalize "$f")"
    limit="$(jq -r '.tool_input.limit // empty' <<<"$input")"
    case "$(path_kind "$abs")" in
      code) [[ "$limit" =~ ^[0-9]+$ ]] && [ "$limit" -le "$EXCERPT_MAX" ] && exit 0
            deny_code "$abs" "Read${limit:+ de $limit lignes}" ;;
      log)  [[ "$limit" =~ ^[0-9]+$ ]] && exit 0
            deny_log "$abs" "Read sans limit" ;;
    esac
    exit 0 ;;
  Grep)
    p="$(jq -r '.tool_input.path // empty' <<<"$input")"; abs="$(hook_normalize "${p:-.}")"
    g="$(jq -r '.tool_input.glob // empty' <<<"$input")"
    t="$(jq -r '.tool_input.type // empty' <<<"$input")"; [ -n "$t" ] && g="${g:-*.$t}"
    if [ -f "$abs" ]; then [ "$(path_kind "$abs")" = code ] && deny_code "$abs" Grep; exit 0; fi
    check_dir_search "$abs" Grep "$g"; exit 0 ;;
  Glob)
    p="$(jq -r '.tool_input.path // empty' <<<"$input")"; abs="$(hook_normalize "${p:-.}")"
    g="$(jq -r '.tool_input.pattern // empty' <<<"$input")"
    k="$(path_kind "$abs")"
    [ "$k" = pipeline ] && exit 0
    [ "$k" = code ] && deny_code "$abs" Glob
    for e in $CODE_EXT; do case "$g" in *."$e"|*."$e"[,\}]*|*,"$e"[,\}]*) deny_code "$abs/$g" Glob ;; esac; done
    for d in $CODE_DIRS; do case "/$g/" in */"$d"/*) deny_code "$abs/$g" Glob ;; esac; done
    case "$g" in *'**'*) glob_is_code "$g" && has_code_below "$abs" && deny_code "$abs/$g" "Glob récursif" ;; esac
    exit 0 ;;
esac

# ---------------------------------------------------------------------------- Bash
# split_segments — une commande par ligne, coupée sur ; && || | et les retours à la ligne hors guillemets
split_segments() {
  local s="$1" out="" q="" c i n=${#1}
  for ((i=0; i<n; i++)); do
    c="${s:i:1}"
    if [ -n "$q" ]; then
      [ "$c" = "$q" ] && q=""; out+="$c"; continue
    fi
    case "$c" in
      "'"|'"') q="$c"; out+="$c" ;;
      ';'|'|'|'&'|$'\n') out+=$'\n' ;;
      *) out+="$c" ;;
    esac
  done
  printf '%s\n' "$out"
}
# tokens — les mots d'un segment, guillemets retirés (xargs, sans rien évaluer), sinon coupés aux blancs
tokens() {
  local t
  t="$(printf '%s' "$1" | xargs printf '%s\n' 2>/dev/null)" || t="$(printf '%s' "$1" | tr -s ' \t' '\n\n')"
  printf '%s\n' "$t"
}

# check_files <outil> <fichiers…> — lecture entière de fichiers nommés (cat & co)
check_files() {
  local t="$1" f a; shift
  for f in "$@"; do
    a="$(hook_normalize "$f")"
    case "$(path_kind "$a")" in
      code) deny_code "$a" "$t" ;;
      log)  deny_log "$a" "$t" ;;
    esac
  done
}
# check_excerpt <outil> <lignes> <fichiers…> — un extrait de code est permis s'il tient en EXCERPT_MAX lignes
check_excerpt() {
  local t="$1" lines="$2" f a; shift 2
  for f in "$@"; do
    a="$(hook_normalize "$f")"
    [ "$(path_kind "$a")" = code ] || continue
    [[ "$lines" =~ ^[0-9]+$ ]] && [ "$lines" -le "$EXCERPT_MAX" ] && [ "$#" -eq 1 ] && continue
    deny_code "$a" "$t${lines:+ de $lines lignes}"
  done
}

check_segment() {
  local -a w=() args=()
  local x cmd i n lines pat recursive restrict dir
  while IFS= read -r x; do [ -n "$x" ] && w+=("$x"); done < <(tokens "$1")
  # préfixes : VAR=…, (, {, command, sudo, rtk, time, nice
  i=0
  while [ "$i" -lt "${#w[@]}" ]; do
    case "${w[$i]}" in *=*|'('|'{'|command|sudo|rtk|time|nice|then|do|else) i=$((i+1)) ;; *) break ;; esac
  done
  [ "$i" -lt "${#w[@]}" ] || return 0
  cmd="${w[$i]##*/}"; cmd="${cmd#(}"
  # les mots suivants, sans les redirections
  n=$((i+1)); args=()
  while [ "$n" -lt "${#w[@]}" ]; do
    x="${w[$n]}"
    case "$x" in
      [0-9]'>'*|'>'*|'<'*|'&>'*|')'|'}') case "$x" in '>'|'>>'|'<'|[0-9]'>'|'&>') n=$((n+1)) ;; esac ;;
      *) args+=("$x") ;;
    esac
    n=$((n+1))
  done
  set -- ${args[@]+"${args[@]}"}
  case "$cmd" in
    cd)
      [ $# -ge 1 ] && cwd="$(hook_normalize "$1")" ;;
    cat|less|more|bat|nl|strings|xxd|od)
      local -a f=(); for x; do case "$x" in -*) ;; *) f+=("$x") ;; esac; done
      [ ${#f[@]} -gt 0 ] && check_files "$cmd" "${f[@]}" ;;
    head|tail)
      local -a f=(); lines=10
      while [ $# -gt 0 ]; do
        case "$1" in
          -n|-c) lines="$2"; shift ;;
          -n*) lines="${1#-n}" ;;
          --lines=*) lines="${1#--lines=}" ;;
          -[0-9]*) lines="${1#-}" ;;
          -*) ;;
          *) f+=("$1") ;;
        esac
        shift
      done
      lines="${lines#+}"
      [ ${#f[@]} -gt 0 ] && check_excerpt "$cmd" "$lines" "${f[@]}" ;;
    sed)
      local -a f=(); pat=""; local quiet=0 inplace=0
      while [ $# -gt 0 ]; do
        case "$1" in
          -n) quiet=1 ;;
          -i*|--in-place*) inplace=1 ;;
          -e) pat="$2"; shift ;;
          -E|-r|-u|-s|-z) ;;
          -*) case "$1" in *n*) quiet=1 ;; esac ;;
          *) if [ -z "$pat" ]; then pat="$1"; else f+=("$1"); fi ;;
        esac
        shift
      done
      [ "$inplace" = 1 ] && return 0          # une écriture : pas l'affaire de ce hook
      [ ${#f[@]} -gt 0 ] || return 0
      lines=""
      if [ "$quiet" = 1 ]; then
        if [[ "$pat" =~ ^([0-9]+),([0-9]+)p$ ]]; then lines=$(( BASH_REMATCH[2] - BASH_REMATCH[1] + 1 ))
        elif [[ "$pat" =~ ^([0-9]+)p$ ]]; then lines=1; fi
      fi
      for x in "${f[@]}"; do
        [ "$(path_kind "$(hook_normalize "$x")")" = log ] && return 0
      done
      if [ -n "$lines" ] && [ "$lines" -gt 0 ]; then check_excerpt sed "$lines" "${f[@]}"
      else check_excerpt sed "" "${f[@]}"; fi ;;
    awk|gawk)
      local -a f=(); pat=""
      while [ $# -gt 0 ]; do
        case "$1" in -f|-v|-F) shift ;; -*) ;; *) if [ -z "$pat" ]; then pat="$1"; else f+=("$1"); fi ;; esac
        shift
      done
      for x in ${f[@]+"${f[@]}"}; do
        [ "$(path_kind "$(hook_normalize "$x")")" = code ] && deny_code "$(hook_normalize "$x")" "$cmd"
      done ;;
    grep|egrep|fgrep|rg|ag|ack)
      local -a f=(); pat=""; local haspat=0; recursive=0; restrict=""
      case "$cmd" in rg|ag|ack) recursive=1 ;; esac
      while [ $# -gt 0 ]; do
        case "$1" in
          -e|--regexp|-f|--file) haspat=1; shift ;;
          --regexp=*|--file=*) haspat=1 ;;
          --include|-g|--glob|-t|--type) [ "$1" = -t ] || [ "$1" = --type ] && restrict="*.$2" || restrict="$2"; shift ;;
          --include=*|--glob=*) restrict="${1#*=}" ;;
          --type=*) restrict="*.${1#*=}" ;;
          -r|-R|--recursive|--dereference-recursive) recursive=1 ;;
          -A|-B|-C|-m|--max-count|--exclude|--exclude-dir) shift ;;
          --*) ;;
          -*) [[ "$1" =~ ^-[A-Za-z]*[rR] ]] && recursive=1 ;;
          *) if [ "$haspat" = 0 ] && [ -z "$pat" ]; then pat="$1"; haspat=1; else f+=("$1"); fi ;;
        esac
        shift
      done
      if [ ${#f[@]} -eq 0 ]; then
        [ "$recursive" = 1 ] && check_dir_search "$cwd" "$cmd" "$restrict"
        return 0
      fi
      for x in "${f[@]}"; do
        dir="$(hook_normalize "$x")"
        if [ -d "$dir" ]; then
          [ "$recursive" = 1 ] && check_dir_search "$dir" "$cmd" "$restrict"
        else
          [ "$(path_kind "$dir")" = code ] && deny_code "$dir" "$cmd"
        fi
      done ;;
    ls|tree)
      local -a f=(); recursive=0; [ "$cmd" = tree ] && recursive=1
      for x; do case "$x" in -*R*) recursive=1 ;; -*) ;; *) f+=("$x") ;; esac; done
      [ ${#f[@]} -gt 0 ] || f=(.)
      for x in "${f[@]}"; do
        dir="$(hook_normalize "$x")"
        [ "$(path_kind "$dir")" = code ] && deny_code "$dir" "$cmd"
        [ "$recursive" = 1 ] && check_dir_search "$dir" "$cmd" ""
      done ;;
    find)
      local -a f=(); restrict=""; local inexpr=0
      while [ $# -gt 0 ]; do
        case "$1" in
          -name|-iname|-path|-ipath) inexpr=1; glob_is_code "$2" || restrict="${restrict:-$2}"; shift ;;
          -*|'('|'!'|')') inexpr=1 ;;
          *) [ "$inexpr" = 0 ] && f+=("$1") ;;
        esac
        shift
      done
      [ ${#f[@]} -gt 0 ] || f=(.)
      for x in "${f[@]}"; do check_dir_search "$(hook_normalize "$x")" find "$restrict"; done ;;
  esac
  return 0
}

[ "$tool" = Bash ] || exit 0
cmdline="$(jq -r '.tool_input.command // empty' <<<"$input")"
[ -n "$cmdline" ] || exit 0
cwd="${cwd:-$PWD}"
while IFS= read -r seg; do
  [ -n "${seg//[[:space:]]/}" ] || continue
  check_segment "$seg"
done < <(split_segments "$cmdline")
exit 0
