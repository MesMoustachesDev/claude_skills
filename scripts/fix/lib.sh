#!/usr/bin/env bash
# fix/lib.sh — contexte partagé par fix_gauntlet.sh et les hooks fix-*. Sourcé, pas exécuté.
#
# Un fix = une branche fix/<nom> = un dossier .claude/fixes/<nom>/ :
#   fix.json    état, écrit par l'orchestrateur et les hooks (phase, base_sha, freeze_sha, stages…)
#   repro.json  écrit par le reproducer, GELÉ avec les tests : commandes et preuve du bug
#   diagnosis.md, review.json, review.md, shots/, .gauntlet/

# fix_context <nom> — PROJECT_ROOT FIX_NAME FIX_DIR FIX_OUT REPRO STATE
fix_context() {
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd -P)"
  FIX_NAME="$1"
  [ -n "$FIX_NAME" ] || return 1
  FIX_DIR="${FIX_ROOT:-$PROJECT_ROOT/.claude/fixes}/$FIX_NAME"
  FIX_OUT="$FIX_DIR/.gauntlet"
  REPRO="$FIX_DIR/repro.json"
  STATE="$FIX_DIR/fix.json"
}

# current_fix — nom du fix courant : branche fix/<nom>, sinon .claude/fixes/.current
current_fix() {
  local n
  n="$(git branch --show-current 2>/dev/null | sed -n 's#^fix/##p')"
  [ -n "$n" ] || n="$(cat "$(git rev-parse --show-toplevel 2>/dev/null)/.claude/fixes/.current" 2>/dev/null)"
  printf '%s' "$n"
}

state_get() { [ -f "$STATE" ] && jq -r "$1 // empty" "$STATE"; }
repro_get() { [ -f "$REPRO" ] && jq -r "$1 // empty" "$REPRO"; }
state_set() { # state_set <filtre jq> [--arg k v]...
  local f="$1"; shift
  [ -f "$STATE" ] || echo '{}' > "$STATE"
  local tmp; tmp="$(mktemp)"
  jq "$@" "$f" "$STATE" > "$tmp" && mv "$tmp" "$STATE"
}

# Chemins de test, relatifs à la racine. `*` traverse les `/` (motifs case).
# repro.json → test_paths complète la liste si le projet a une convention à lui.
FIX_TEST_GLOBS_DEFAULT='test/* */test/* tests/* */tests/* */__tests__/* integration_test/* */integration_test/* maestro/* */maestro/* *.test.* *.spec.* *_test.* *.feature'

is_test_path() { # is_test_path <chemin relatif>
  local p="$1" g extra=""
  [ -f "${REPRO:-}" ] && extra="$(jq -r '(.test_paths // [])[]' "$REPRO" 2>/dev/null | tr '\n' ' ')"
  set -f
  for g in $FIX_TEST_GLOBS_DEFAULT $extra; do
    # shellcheck disable=SC2254
    case "$p" in $g) set +f; return 0 ;; esac
  done
  set +f
  return 1
}

# Manifestes que le reproducer peut toucher pour brancher un runner de test absent.
is_manifest_path() { case "$1" in package.json|*/package.json|pubspec.yaml|*/pubspec.yaml) return 0 ;; esac; return 1; }

# changed_since <sha> — fichiers modifiés, ajoutés, supprimés ou non suivis depuis <sha>, relatifs à la racine
changed_since() {
  { git -C "$PROJECT_ROOT" diff --name-only "$1" 2>/dev/null
    git -C "$PROJECT_ROOT" ls-files --others --exclude-standard 2>/dev/null; } | sort -u
}

DEBUG_MARKER='[DEBUG_ISSUE]'
