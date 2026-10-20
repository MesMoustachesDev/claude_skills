#!/usr/bin/env bash
# graphify.sh — mécanique graphify partagée par /feature, /fix et /reviewPR.
# Contrat : ~/.claude/pipeline/graphify.md · spec : docs/superpowers/specs/2026-10-20-graphify-partage-design.md
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

case "${1:-}" in
  impact) shift; cmd_impact "$@" ;;
  *) echo "usage : graphify.sh impact <worktree> <base> [--out <dir>]" >&2; status_line failed "sous-commande inconnue" ;;
esac
