#!/usr/bin/env bash
# stack.sh — le langage d'un package, et ce que ce langage veut dire pour les scripts du pipeline.
#
#   stack.sh detect [chemin]       nom du langage du package qui contient <chemin> (défaut : le dossier courant)
#   stack.sh dir [chemin]          ~/.claude/stacks/<langage>
#   stack.sh get <clé> [chemin]    valeur de la clé : config du projet (bloc ini de .claude/rules/feature_pipeline.md)
#                                  si elle la donne, sinon stacks/<langage>/stack.ini ; vide si aucun ne la donne
#   stack.sh vals <chemin> <clé>…  une valeur par ligne, dans l'ordre des clés (un seul processus, pour les hooks)
#   stack.sh package <chemin>      le dossier du package qui contient <chemin> : le plus proche, en remontant
#                                  jusqu'à la racine du repo, qui porte un marqueur d'un langage connu ; exit 1 sinon
#   stack.sh markers               marqueurs de tous les langages, un par ligne
#   stack.sh list                  langages connus, leur priorité et leurs marqueurs
#
# Détection : on remonte de <chemin> vers la racine du repo ; le premier dossier qui contient un marqueur d'un
# langage (stack.ini → markers) décide. Deux langages marqués dans le même dossier : le plus petit `priority`
# gagne. Ainsi android/app/… d'une app Flutter est du Kotlin (build.gradle le plus proche), lib/ est du Flutter.
# `stack = <langage>` dans la config du projet force le langage de tout le repo. Rien trouvé : exit 1.
#
# La prose propre à un langage (règles, conseils aux agents) n'est pas ici : elle vit dans
# ~/.claude/rules/stacks/<langage>*.md, chargée par Claude Code seulement quand un fichier de ce langage est lu
# (frontmatter `paths:`). Voir ~/.claude/stacks/README.md et l'ADR 0011.
#
# STACK_CFG=<fichier> : la config du projet à lire à la place de <racine>/.claude/rules/feature_pipeline.md
# (GAUNTLET_CFG du gauntlet, template de pr_gauntlet.sh). Une valeur qui commence par `~/` est rendue absolue.
set -u
STACKS="${CLAUDE_STACKS_DIR:-$HOME/.claude/stacks}"

# ini_get <fichier> <clé> — `clé = valeur` d'un fichier ini simple (commentaires #, pas de sections)
ini_get() {
  [ -f "$1" ] || return 0
  awk -v k="$2" '
    /^[[:space:]]*#/ { next }
    { line = $0; i = index(line, "=") }
    i > 0 {
      key = substr(line, 1, i - 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      if (key == k) { v = substr(line, i + 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); print v; exit }
    }' "$1"
}

# project_cfg <racine> <clé> — même lecture que cfg() du gauntlet : blocs ```ini de feature_pipeline.md
project_cfg() {
  local f="${STACK_CFG:-$1/.claude/rules/feature_pipeline.md}"
  [ -f "$f" ] || return 0
  awk '/^```ini/{f=1;next} /^```/{f=0} f' "$f" \
    | grep -E "^[[:space:]]*${2//./\\.}[[:space:]]*=" | head -1 | sed 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//'
}

# known — « priorité<TAB>nom » de chaque langage, triés
known() {
  local d p
  for d in "$STACKS"/*/; do
    [ -f "$d/stack.ini" ] || continue
    p="$(ini_get "$d/stack.ini" priority)"
    printf '%s\t%s\n' "${p:-50}" "$(basename "$d")"
  done | sort -n
}

root_of() { git -C "$1" rev-parse --show-toplevel 2>/dev/null || echo /; }

# start_dir <chemin> — le dossier d'où partir (un fichier : son dossier ; absent : le parent existant)
start_dir() {
  local p="${1:-$PWD}"
  while [ ! -e "$p" ] && [ "$p" != / ]; do p="$(dirname "$p")"; done
  [ -d "$p" ] || p="$(dirname "$p")"
  (cd "$p" && pwd -P)
}

detect() {
  local dir root forced name m
  dir="$(start_dir "${1:-}")"
  root="$(root_of "$dir")"
  forced="$(project_cfg "$root" stack)"
  if [ -n "$forced" ]; then
    [ -f "$STACKS/$forced/stack.ini" ] || { echo "stack.sh : langage inconnu dans la config : $forced" >&2; return 2; }
    echo "$forced"; return 0
  fi
  while :; do
    while IFS=$'\t' read -r _ name; do
      for m in $(ini_get "$STACKS/$name/stack.ini" markers | tr ',' ' '); do
        [ -e "$dir/$m" ] && { echo "$name"; return 0; }
      done
    done < <(known)
    [ "$dir" = "$root" ] || [ "$dir" = / ] && break
    dir="$(dirname "$dir")"
  done
  return 1
}

# value <langage> <racine> <clé> — config du projet, sinon stack.ini ; `{clé}` remplacé par la valeur de cette clé
# (`test_cmd = {flutter} test` avec `flutter = fvm flutter` dans la config → `fvm flutter test`).
value() {
  local v ref depth=0
  v="$(project_cfg "$2" "$3")"
  [ -n "$v" ] || v="$(ini_get "$STACKS/$1/stack.ini" "$3")"
  while [[ "$v" =~ \{([a-z_.]+)\} ]] && [ $depth -lt 5 ]; do
    ref="${BASH_REMATCH[1]}"
    v="${v//\{$ref\}/$(value "$1" "$2" "$ref")}"
    depth=$((depth + 1))
  done
  case "$v" in "~/"*) v="$HOME/${v#\~/}" ;; esac
  printf '%s' "$v"
}

# package <chemin> — le dossier le plus proche, de <chemin> à la racine du repo, qui porte un marqueur
package() {
  local dir root m
  dir="$(start_dir "${1:-}")"; root="$(root_of "$dir")"
  while :; do
    for m in $(all_markers); do [ -e "$dir/$m" ] && { echo "$dir"; return 0; }; done
    [ "$dir" = "$root" ] || [ "$dir" = / ] && return 1
    dir="$(dirname "$dir")"
  done
}
all_markers() {
  local name
  while IFS=$'\t' read -r _ name; do ini_get "$STACKS/$name/stack.ini" markers | tr ',' '\n'; done < <(known) \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | awk '!seen[$0]++'
}

case "${1:-}" in
  detect) detect "${2:-}" ;;
  dir) s="$(detect "${2:-}")" || exit $?; echo "$STACKS/$s" ;;
  get)
    [ -n "${2:-}" ] || { echo "usage : stack.sh get <clé> [chemin]" >&2; exit 2; }
    s="$(detect "${3:-}")" || exit $?
    printf '%s\n' "$(value "$s" "$(root_of "$(start_dir "${3:-}")")" "$2")" ;;
  vals)
    s="$(detect "${2:-}")" || exit $?
    r="$(root_of "$(start_dir "${2:-}")")"
    shift 2
    for k in "$@"; do printf '%s\n' "$(value "$s" "$r" "$k")"; done ;;
  package) package "${2:-}" ;;
  markers) all_markers ;;
  list)
    while IFS=$'\t' read -r p name; do
      printf '%-10s priorité %-3s marqueurs : %s\n' "$name" "$p" "$(ini_get "$STACKS/$name/stack.ini" markers)"
    done < <(known) ;;
  *) sed -n '2,24p' "${BASH_SOURCE[0]}"; [ "${1:-}" = -h ] || [ "${1:-}" = --help ] ;;
esac
