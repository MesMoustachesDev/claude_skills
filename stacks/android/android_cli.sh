#!/usr/bin/env bash
# android_cli.sh — ce que le pipeline demande à Android CLI (developer.android.com/tools/agents), par la clé
# `android` du langage (stack.ini : `android --no-metrics`, la config du projet prime).
#
#   android_cli.sh preview <module> <dossier> [fqn…]
#       rend les @Preview Compose du module, sans appareil : un PNG et un arbre de composants JSON (bornes, noms,
#       sources, sémantique, modifiers) par preview, dans <dossier>. Sans fqn : toutes celles du module
#       (`preview list`). Pour : la revue (Romain regarde l'écran que décrit la spec), le polish (Pauline, avant /
#       après), la QA rapide (Quentin, avant l'émulateur). L'arbre JSON dit ce qu'une capture ne dit pas :
#       testTags, contentDescription, tailles en dp.
#   android_cli.sh layout <fichier> [serial]
#       hiérarchie de l'écran affiché sur l'appareil (JSON complet, éléments cachés compris) : un flow Maestro
#       rouge, un élément introuvable → ce qui est vraiment à l'écran.
#   android_cli.sh emulator <avd> [--cold]
#       démarre l'AVD sans fenêtre et rend la main quand il a booté ; écrit son serial sur stdout.
#
# Lancé depuis n'importe où dans le projet : la racine Gradle et le chemin du module viennent de gradle_run.sh.
# Android CLI absent : exit 3, « non applicable », rien n'est installé (le doctor le signale).
# Essayé le 2026-11-06 avec Android CLI 1.1 sur un projet Wear OS / Compose : preview (38 s pour deux previews, PNG
# et arbre JSON avec texte, contentDescription, rôle et ligne source), layout (installe un serveur d'instrumentation
# sur l'appareil), emulator (--headless). `--no-metrics` est accepté, et ~/.androidrc le pose pour tous les appels.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CLAUDE_STACKS_DIR="${CLAUDE_STACKS_DIR:-$(cd "$here/.." && pwd)}"
cmd="${1:-}"; shift 2>/dev/null || true
android="${ANDROID_CLI:-$(bash "$here/../../scripts/stack.sh" get android "$PWD" 2>/dev/null)}"
android="${android:-android}"
# shellcheck disable=SC2086
command -v ${android%% *} >/dev/null 2>&1 || {
  echo "Android CLI (${android%% *}) absent : non applicable — developer.android.com/tools/agents (installation : Thibault)" >&2; exit 3; }

case "$cmd" in
  preview)
    [ $# -ge 2 ] || { echo "usage : android_cli.sh preview <module> <dossier> [fqn…]" >&2; exit 2; }
    where="$(cd "$1" && bash "$here/gradle_run.sh" --where)" || exit 2
    root="$(printf '%s' "$where" | cut -f1)"; ref="$(printf '%s' "$where" | cut -f2)"; ref="${ref:-:}"
    out="$(mkdir -p "$2" && cd "$2" && pwd)"; shift 2
    fqns=("$@")
    if [ ${#fqns[@]} -eq 0 ]; then
      # shellcheck disable=SC2086
      while IFS= read -r f; do [ -n "$f" ] && fqns+=("$f"); done < <(cd "$root" && $android preview list "$ref" --format=text 2>/dev/null)
      [ ${#fqns[@]} -gt 0 ] || { echo "aucune @Preview dans $ref" >&2; exit 1; }
    fi
    args=(); for f in "${fqns[@]}"; do args+=("--fqn=$f"); done
    # shellcheck disable=SC2086
    (cd "$root" && $android preview render "$ref" --component-tree --format=json --output="$out" "${args[@]}") ;;
  layout)
    [ $# -ge 1 ] || { echo "usage : android_cli.sh layout <fichier> [serial]" >&2; exit 2; }
    # shellcheck disable=SC2086
    $android layout --pretty --full --output="$1" ${2:+--device="$2"} ;;
  emulator)
    [ $# -ge 1 ] || { echo "usage : android_cli.sh emulator <avd> [--cold]" >&2; exit 2; }
    # Le serial : Android CLI l'annonce (« Virtual device successfully started as 'emulator-5554' ») ; il ne
    # choisit pas le port. adb n'est souvent pas dans le PATH des sessions : on lit sa ligne, pas `adb devices`.
    log="$(mktemp)"
    # shellcheck disable=SC2086
    $android emulator start --headless ${2:+--cold} "$1" 2>&1 | tee "$log" >&2
    rc=${PIPESTATUS[0]}
    serial="$(sed -n "s/.*started as '\([^']*\)'.*/\1/p" "$log" | tail -1)"
    rm -f "$log"
    [ "$rc" = 0 ] && [ -n "$serial" ] || { echo "émulateur $1 : pas démarré (exit $rc)" >&2; exit 1; }
    echo "$serial" ;;
  *) sed -n '2,24p' "${BASH_SOURCE[0]}"; exit 2 ;;
esac
