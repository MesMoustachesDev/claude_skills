#!/usr/bin/env bash
# fixture.sh — helpers des tests de reproduction du gauntlet. Sourcé par chaque test_*.sh.
#
# Chaque test monte un repo git jetable (branche develop, config feature_pipeline.md, app dans app/ avec son
# .fvmrc) et lance le vrai gauntlet.sh dessus. `flutter test` est simulé (fake_flutter.sh : un fichier de test
# qui contient FAKE_FAIL échoue) ; `dart` est le vrai `fvm dart` (stub_check parse l'AST).
#
# GAUNTLET=<chemin de gauntlet.sh> pour rejouer les tests contre une autre version (avant correctif).
set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAUNTLET="${GAUNTLET:-$TESTS_DIR/../../gauntlet.sh}"
FAKE_FLUTTER="$TESTS_DIR/fake_flutter.sh"
FVM_FLUTTER_VERSION="${FVM_FLUTTER_VERSION:-$(ls "$HOME/fvm/versions" 2>/dev/null | sort -V | tail -1)}"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/gauntlet-test.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT
FAILS=0; PASSES=0
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

need_fvm() {
  command -v fvm >/dev/null && [ -n "$FVM_FLUTTER_VERSION" ] && return 0
  echo "SKIP: fvm ou un SDK fvm installé est requis"; exit 0
}

# mk_repo <dir> — repo git vide sur develop
mk_repo() {
  mkdir -p "$1" && git -C "$1" init -q -b develop && git -C "$1" config commit.gpgsign false
  git -C "$1" config protocol.file.allow always
}
# commit <dir> <message> — tout commiter
commit() { git -C "$1" add -A && git -C "$1" commit -q -m "$2" && git -C "$1" rev-parse HEAD; }

# write_cfg <root> [lignes ini…] — config du pipeline, app dans app/ avec son .fvmrc
write_cfg() {
  local root="$1"; shift
  mkdir -p "$root/.claude/rules" "$root/app"
  printf '{\n  "flutter": "%s"\n}\n' "$FVM_FLUTTER_VERSION" > "$root/app/.fvmrc"
  {
    echo '# test'; echo '```ini'
    echo "flutter = $FAKE_FLUTTER"
    echo "dart = fvm dart"
    echo "package_path = app/features/{name}"
    echo "features_root = app/features"
    echo "base_branch = develop"
    echo "app_dir = app"
    echo "stub.include = lib/src/data/*_impl.dart"
    echo "deps.shared_packages = core"
    echo "qa.platforms ="
    for l in "$@"; do echo "$l"; done
    echo '```'
  } > "$root/.claude/rules/feature_pipeline.md"
}

# mk_pkg <dir> <name> [dep_path…] — package Dart minimal ; chaque dep_path = "nom:chemin relatif"
mk_pkg() {
  local dir="$1" name="$2" d; shift 2
  mkdir -p "$dir/lib/src/data" "$dir/test"
  {
    echo "name: $name"
    echo "environment:"; echo "  sdk: ^3.5.0"
    echo "dependencies:"
    echo "  flutter:"; echo "    sdk: flutter"
    for d in "$@"; do echo "  ${d%%:*}:"; echo "    path: ${d#*:}"; done
  } > "$dir/pubspec.yaml"
}

# pipeline <root> <feature> <json> — .claude/features/<feature>/pipeline.json
pipeline() { mkdir -p "$1/.claude/features/$2"; printf '%s\n' "$3" > "$1/.claude/features/$2/pipeline.json"; }

# run_g <root> <args…> — lance le gauntlet depuis <root>, sortie dans $OUT, code dans $RC
run_g() { local root="$1"; shift; OUT="$(cd "$root" && bash "$GAUNTLET" "$@" 2>&1)"; RC=$?; }

# Assertions (sur $OUT / $RC du dernier run_g)
_pass() { PASSES=$((PASSES+1)); printf '  ok    %s\n' "$1"; }
_fail() { FAILS=$((FAILS+1)); printf '  FAIL  %s\n' "$1"; printf '%s\n' "$OUT" | sed 's/^/        │ /' | tail -25; }
expect_rc()       { [ "$RC" = "$1" ] && _pass "$2 (exit $RC)" || _fail "$2 (exit $RC, attendu $1)"; }
expect_out()      { grep -qF -- "$1" <<<"$OUT" && _pass "$2" || _fail "$2 — sortie sans « $1 »"; }
expect_no_out()   { grep -qF -- "$1" <<<"$OUT" && _fail "$2 — sortie avec « $1 »" || _pass "$2"; }
expect_file_has() { grep -qF -- "$2" "$1" 2>/dev/null && _pass "$3" || { OUT="$(cat "$1" 2>/dev/null)"; _fail "$3 — $1 sans « $2 »"; }; }

finish() {
  printf '%s : %d ok, %d échec(s)\n' "$(basename "$0")" "$PASSES" "$FAILS"
  [ "$FAILS" = 0 ]
}
