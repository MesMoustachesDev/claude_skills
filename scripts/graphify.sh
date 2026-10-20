#!/usr/bin/env bash
# graphify.sh — mécanique graphify partagée par /feature, /fix et /reviewPR.
# Contrat : ~/.claude/pipeline/graphify.md · spec : docs/superpowers/specs/2026-10-20-graphify-partage-design.md
#   prepare <worktree> [--update]
#   impact <worktree> <base> [--out <dir>]
# Sort TOUJOURS en 0 ; la dernière ligne de stdout donne l'état ("graphify: ok …", "absent", "stale …", "échec <raison>").
set -u
exec </dev/null
trap 'exit 0' EXIT
GRAPHIFY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# main_checkout <wt> — chemin absolu du checkout principal (1er worktree de `git worktree list`)
main_checkout() {
  git -C "$1" worktree list --porcelain 2>/dev/null | awk '/^worktree /{sub(/^worktree /,""); print; exit}'
}

# find_graph_dir <root> — affiche "" ou "<sous-dossier>/" du graph.json le moins profond ; rc 1 si aucun
find_graph_dir() {
  local root="$1" d
  [ -f "$root/graphify-out/graph.json" ] && { printf '\n'; return 0; }
  for d in "$root"/*/; do
    [ -f "${d}graphify-out/graph.json" ] && { printf '%s/\n' "$(basename "$d")"; return 0; }
  done
  return 1
}

# read_cfg <root> <clé> — valeur dans le bloc ini de <root>/.claude/rules/feature_pipeline.md (même awk que cfg() de pr_gauntlet.sh)
read_cfg() {
  local f="$1/.claude/rules/feature_pipeline.md" k="${2//./\\.}"
  [ -f "$f" ] || f="$HOME/.claude/commands/templates/flutter/feature_pipeline.md"
  [ -f "$f" ] || return 0
  awk '/^```ini/{f=1;next} /^```/{f=0} f' "$f" | grep -E "^[[:space:]]*$k[[:space:]]*=" | head -1 | sed 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//'
}

# status_line <status> <détail> — dernière ligne de stdout
status_line() {
  local s="$1" d="${2:-}"
  [ "$s" = failed ] && s="échec"
  printf 'graphify: %s%s\n' "$s" "${d:+ $d}"
}

cmd_impact() {
  local wt="${1:-}" base="${2:-}" out="" gd res rc st detail ignore mainco
  if [ $# -lt 2 ]; then status_line failed "usage : impact <worktree> <base> [--out <dir>]"; return 0; fi
  shift 2
  while [ $# -gt 0 ]; do
    case "$1" in --out) out="${2:-}"; shift; [ $# -gt 0 ] && shift ;; *) shift ;; esac
  done
  wt="$(cd "$wt" 2>/dev/null && pwd)" || { status_line failed "worktree introuvable"; return 0; }
  gd="$(find_graph_dir "$wt")" || gd=""
  [ -n "$out" ] || out="$wt/${gd}graphify-out/impact"
  mainco="$(main_checkout "$wt")"; mainco="${mainco:-$wt}"
  ignore="$(read_cfg "$wt" graphify.ignore_packages)"
  [ -n "$ignore" ] || ignore="$(read_cfg "$mainco" graphify.ignore_packages)"
  res="$(python3 "$GRAPHIFY_DIR/graphify/impact.py" --worktree "$wt" --graph-dir "$gd" --base "$base" \
          --out "$out" --ignore-packages "${ignore:-core}" --main "$mainco")"; rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$res" ]; then
    mkdir -p "$out" 2>/dev/null
    printf '{"status":"failed","reason":"impact.py a échoué","consumers":[],"dependencies":[],"reading_order":[],"not_in_graph":[]}\n' > "$out/impact.json"
    printf '> ⚠ Impact non calculé (impact.py a échoué).\n\n### Consommateurs hors package non touchés\n\n—\n\n### Dépendances\n\n—\n\n### Ordre de lecture du diff\n\n—\n' > "$out/impact.md"
    status_line failed "impact.py a échoué"; return 0
  fi
  st="${res%%$'\t'*}"; detail="${res#*$'\t'}"
  status_line "$st" "$detail"
}

GRAPHIFY_FILES="graph.json GRAPH_REPORT.md graph.html manifest.json"

# resolve_scan_root <valeur de .graphify_root> <dossier qui contient graphify-out/> <checkout principal>
# Absolu : tel quel. Relatif : depuis le dossier de graphify-out/, puis en remontant jusqu'au principal
# (le sous-produit features/graphify-out/ porte « features », relatif à la racine du repo).
resolve_scan_root() {
  local v="$1" d="$2" top="$3" cur
  case "$v" in /*) (cd "$v" 2>/dev/null && pwd -P); return ;; esac
  cur="$d"
  while :; do
    [ -d "$cur/$v" ] && { (cd "$cur/$v" && pwd -P); return 0; }
    [ "$cur" = "$top" ] || [ "$cur" = "/" ] && return 1
    cur="$(dirname "$cur")"
  done
}

# copy_graph_files <src graphify-out> <dst graphify-out> — recopie les 4 fichiers présents (rc 0 même si aucun)
copy_graph_files() {
  local f
  [ "$1" -ef "$2" ] && return 0
  mkdir -p "$2" || return 1
  for f in $GRAPHIFY_FILES; do [ -f "$1/$f" ] && cp "$1/$f" "$2/$f"; done
  return 0
}

# copy_tree <src> <dst> — rsync -a si présent, sinon cp -R ; ni impact/ ni les fichiers d'état de prepare
copy_tree() {
  mkdir -p "$2" || return 1
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --exclude 'impact/' --exclude '.prepare_status' --exclude 'graph.base.json' "$1/" "$2/"
  else
    cp -R "$1/." "$2/" && rm -rf "$2/impact" "$2/.prepare_status" "$2/graph.base.json"
  fi
}

# json_field <graph.json> <champ> — valeur texte du champ de premier niveau (vide si absent/illisible)
json_field() {
  python3 -c 'import json,sys
try: v=json.load(open(sys.argv[1])).get(sys.argv[2],"")
except Exception: v=""
print(v if isinstance(v,str) else "")' "$1" "$2" 2>/dev/null
}

cmd_prepare() {
  local wt="${1:-}" upd=0 mainco gd cdir canon rootf rootv scan scan_rel head built created="" st=ok
  local wtgd wtscan common ex
  if [ $# -lt 1 ]; then status_line failed "usage : prepare <worktree> [--update]"; return 0; fi
  shift
  while [ $# -gt 0 ]; do case "$1" in --update) upd=1 ;; esac; shift; done
  wt="$(cd "$wt" 2>/dev/null && pwd -P)" || { status_line failed "worktree introuvable"; return 0; }
  mainco="$(main_checkout "$wt")"
  [ -n "$mainco" ] && mainco="$(cd "$mainco" 2>/dev/null && pwd -P)"
  [ -n "$mainco" ] || { status_line failed "checkout principal introuvable"; return 0; }

  gd="$(find_graph_dir "$mainco")" || { status_line absent; return 0; }
  cdir="${mainco}/${gd%/}"; cdir="${cdir%/}"          # dossier qui contient le graphify-out/ canonique
  canon="$cdir/graphify-out"
  command -v graphify >/dev/null 2>&1 || { status_line failed "graphify introuvable"; return 0; }

  rootf="$canon/.graphify_root"
  [ -f "$rootf" ] || { status_line failed ".graphify_root manquant"; return 0; }
  rootv="$(head -1 "$rootf" | sed 's/[[:space:]]*$//')"
  scan="$(resolve_scan_root "$rootv" "$cdir" "$mainco")" || scan=""
  [ -n "$scan" ] && [ -d "$scan" ] || { status_line failed "racine de scan introuvable ($rootv)"; return 0; }
  case "$scan/" in "$mainco"/*) ;; *) status_line failed "racine de scan hors du checkout principal"; return 0 ;; esac
  scan_rel="${scan#"$mainco"}"; scan_rel="${scan_rel#/}"

  # .graphifyignore (modèle) à côté du graphify-out/ canonique
  if [ ! -e "$cdir/.graphifyignore" ]; then
    printf '*.g.dart\n*.freezed.dart\n*.mocks.dart\ngenerated_l10n/\n' > "$cdir/.graphifyignore" && created=" .graphifyignore créé"
  fi

  # fraîcheur du graphe du principal (SHA, à défaut mtime)
  head="$(git -C "$mainco" rev-parse HEAD 2>/dev/null)"
  built="$(json_field "$canon/graph.json" built_at_commit)"
  local need=0
  if [ -n "$built" ]; then [ "$built" != "$head" ] && need=1
  else
    local ct; ct="$(git -C "$mainco" log -1 --format=%ct 2>/dev/null)"
    [ -n "$ct" ] && [ "$(stat -f %m "$canon/graph.json" 2>/dev/null || stat -c %Y "$canon/graph.json" 2>/dev/null || echo 0)" -lt "$ct" ] && need=1
  fi
  if [ "$need" = 1 ]; then
    if (cd "$cdir" && graphify update "$scan") >&2; then
      copy_graph_files "$scan/graphify-out" "$canon"
    else
      echo "graphify: update du principal en échec, graphe existant conservé" >&2
    fi
  fi

  # copie vers le worktree (même chemin relatif), cache/ de la racine de scan compris
  if ! [ "$wt" -ef "$mainco" ]; then
    wtgd="$wt/${gd%/}"; wtgd="${wtgd%/}"
    copy_tree "$canon" "$wtgd/graphify-out" || { status_line failed "copie vers le worktree impossible"; return 0; }
    if ! [ "$scan/graphify-out" -ef "$canon" ] && [ -d "$scan/graphify-out/cache" ]; then
      copy_tree "$scan/graphify-out/cache" "$wt/${scan_rel:+$scan_rel/}graphify-out/cache"
    fi
  else
    wtgd="$cdir"
  fi

  # exclusion locale (jamais le .gitignore versionné)
  if ! git -C "$wt" check-ignore -q "${gd}graphify-out/x" 2>/dev/null; then
    common="$(git -C "$wt" rev-parse --git-common-dir 2>/dev/null)"
    case "$common" in /*) ;; *) common="$wt/$common" ;; esac
    ex="$common/info/exclude"
    mkdir -p "$common/info"
    grep -qxF 'graphify-out/' "$ex" 2>/dev/null || printf 'graphify-out/\n' >> "$ex"
  fi

  if [ "$upd" = 1 ]; then
    wtscan="$wt${scan_rel:+/$scan_rel}"
    cp "$wtgd/graphify-out/graph.json" "$wtgd/graphify-out/graph.base.json" 2>/dev/null
    if (cd "$wtgd" && graphify update "$wtscan") >&2; then
      copy_graph_files "$wtscan/graphify-out" "$wtgd/graphify-out"
    else
      st=stale
      echo "graphify: update du worktree en échec, graphe de la base conservé" >&2
    fi
  fi

  printf '%s\n' "$st" > "$wtgd/graphify-out/.prepare_status"
  if [ "$st" = stale ]; then status_line stale "(update worktree en échec)"
  else status_line ok "graph=${gd}graphify-out/graph.json$created"; fi
}

case "${1:-}" in
  prepare) shift; cmd_prepare "$@" ;;
  impact) shift; cmd_impact "$@" ;;
  *) echo "usage : graphify.sh prepare <worktree> [--update] | impact <worktree> <base> [--out <dir>]" >&2; status_line failed "sous-commande inconnue" ;;
esac
