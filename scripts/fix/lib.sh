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

# --- Langage du package (scripts/stack.sh, ADR 0011) ----------------------------------------------------
# Les globs de test et les manifestes du langage complètent les génériques ci-dessous. Le package qui décide :
# celui de repro.json (.package), sinon celui qui contient le chemin jugé (le reproducer écrit ses tests et
# branche son runner avant d'écrire repro.json). Langages de ce checkout, comme le gauntlet.
FIX_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CLAUDE_STACKS_DIR="${CLAUDE_STACKS_DIR:-$(cd "$FIX_SCRIPTS/../stacks" 2>/dev/null && pwd)}"
FIX_STACK_PKG="-"; FIX_STACK=""; FIX_STACK_TEST_GLOBS=""; FIX_STACK_MANIFESTS=""; FIX_STACK_EXTS=""
# fix_stack_load <chemin relatif> — FIX_STACK (langage), FIX_STACK_TEST_GLOBS (relatifs à la racine),
# FIX_STACK_MANIFESTS, FIX_STACK_EXTS pour le package qui décide ; rien à refaire si c'est le même package.
fix_stack_load() {
  local pkg rel vals g
  pkg="$(repro_get .package 2>/dev/null)"
  if [ -n "$pkg" ]; then pkg="${pkg%/}"; [ "$pkg" = . ] && pkg=""; pkg="$PROJECT_ROOT${pkg:+/$pkg}"
  else pkg="$(bash "$FIX_SCRIPTS/stack.sh" package "$PROJECT_ROOT/$1" 2>/dev/null)"; fi
  [ "$pkg" = "$FIX_STACK_PKG" ] && return 0
  FIX_STACK_PKG="$pkg"; FIX_STACK=""; FIX_STACK_TEST_GLOBS=""; FIX_STACK_MANIFESTS=""; FIX_STACK_EXTS=""
  [ -n "$pkg" ] || return 0
  FIX_STACK="$(bash "$FIX_SCRIPTS/stack.sh" detect "$pkg" 2>/dev/null)" || { FIX_STACK=""; return 0; }
  vals="$(bash "$FIX_SCRIPTS/stack.sh" vals "$pkg" test_globs manifests extensions 2>/dev/null)"
  rel="${pkg#"$PROJECT_ROOT"}"; rel="${rel#/}"
  set -f
  # Globs du langage relatifs au package : tels quels, et préfixés du package.
  for g in $(printf '%s\n' "$vals" | sed -n 1p | tr ',' ' '); do
    FIX_STACK_TEST_GLOBS="$FIX_STACK_TEST_GLOBS $g${rel:+ $rel/$g}"
  done
  set +f
  FIX_STACK_MANIFESTS="$(printf '%s\n' "$vals" | sed -n 2p | tr ',' ' ' | xargs)"
  FIX_STACK_EXTS="$(printf '%s\n' "$vals" | sed -n 3p | tr ',' ' ' | xargs)"
}

# Chemins de test, relatifs à la racine. `*` traverse les `/` (motifs case).
# Génériques, puis ceux du langage (stack.ini → test_globs) ; repro.json → test_paths complète la liste si le
# projet a une convention à lui.
FIX_TEST_GLOBS_DEFAULT='test/* */test/* tests/* */tests/* */__tests__/* integration_test/* */integration_test/* maestro/* */maestro/* *.test.* *.spec.* *_test.* *.feature'

is_test_path() { # is_test_path <chemin relatif>
  local p="$1" g extra=""
  [ -f "${REPRO:-}" ] && extra="$(jq -r '(.test_paths // [])[]' "$REPRO" 2>/dev/null | tr '\n' ' ')"
  fix_stack_load "$p"
  set -f
  for g in $FIX_TEST_GLOBS_DEFAULT $extra $FIX_STACK_TEST_GLOBS; do
    # shellcheck disable=SC2254
    case "$p" in $g) set +f; return 0 ;; esac
  done
  set +f
  return 1
}

# Manifestes que le reproducer peut toucher pour brancher un runner de test absent : package.json et
# pubspec.yaml partout, plus ceux du langage (stack.ini → manifests : build.gradle.kts, libs.versions.toml…).
is_manifest_path() {
  local m
  case "$1" in package.json|*/package.json|pubspec.yaml|*/pubspec.yaml) return 0 ;; esac
  fix_stack_load "$1"
  for m in $FIX_STACK_MANIFESTS; do case "$1" in "$m"|*/"$m") return 0 ;; esac; done
  return 1
}
# manifest_label — les manifestes permis, pour un message
manifest_label() {
  local m out="package.json, pubspec.yaml"
  for m in $FIX_STACK_MANIFESTS; do case "$m" in package.json|pubspec.yaml) ;; *) out="$out, $m" ;; esac; done
  printf '%s' "$out"
}

# changed_since <sha> — fichiers modifiés, ajoutés, supprimés ou non suivis depuis <sha>, relatifs à la racine.
# Descend dans les sous-modules : un sous-module changé (flutter_app/dskit) donne ses fichiers, préfixés de
# son chemin, pas un seul chemin opaque que is_test_path ne sait pas classer.
changed_since() {
  local f
  { git -C "$PROJECT_ROOT" diff --name-only "$1" 2>/dev/null
    git -C "$PROJECT_ROOT" ls-files --others --exclude-standard 2>/dev/null; } | sort -u \
  | while IFS= read -r f; do
      if [ -e "$PROJECT_ROOT/$f/.git" ]; then submodule_changed_since "$1" "$f"; else printf '%s\n' "$f"; fi
    done | sort -u
}

# submodule_changed_since <sha> <chemin> — fichiers du sous-module changés depuis le commit qu'il pointait à
# <sha>, préfixés de <chemin>. Sous-module absent à <sha> ou commit introuvable : le chemin seul.
submodule_changed_since() {
  local sub="$PROJECT_ROOT/$2" old
  old="$(git -C "$PROJECT_ROOT" ls-tree "$1" -- "$2" 2>/dev/null | awk '$2=="commit"{print $3}')"
  if [ -z "$old" ] || ! git -C "$sub" cat-file -e "$old^{commit}" 2>/dev/null; then printf '%s\n' "$2"; return; fi
  { git -C "$sub" diff --name-only "$old" 2>/dev/null
    git -C "$sub" ls-files --others --exclude-standard 2>/dev/null; } | sed "s#^#$2/#"
}

DEBUG_MARKER='[DEBUG_ISSUE]'
