#!/usr/bin/env bash
# checks_static.sh — analyse, format, génération, dépendances, stubs, métriques.
# Chaque check : fonction check_<nom> [mode], exit 0 = vert. Sourcé par gauntlet.sh.

# capture <cmd...> — exécute dans PKG_DIR, affiche les 40 dernières lignes, retourne le code.
capture() {
  local out rc
  out="$(cd "$PKG_DIR" && "$@" 2>&1)"; rc=$?
  printf '%s\n' "$out" | tail -40
  return $rc
}

check_analyze() {
  # shellcheck disable=SC2086
  capture $FLUTTER analyze --fatal-warnings --no-pub
}

check_format() {
  local dirs="lib"; [ -d "$PKG_DIR/test" ] && dirs="lib test"
  # shellcheck disable=SC2086
  capture $DART format --set-exit-if-changed --output=none $dirs
}

check_build_runner() {
  if ! has_dev_dep build_runner; then info "pas de build_runner dans le package, sauté"; return 0; fi
  # shellcheck disable=SC2086
  capture $DART run build_runner build --delete-conflicting-outputs
}

check_no_stubs() {
  local hits
  hits="$(grep -rn --include='*.dart' 'UnimplementedError' "$PKG_DIR/lib" 2>/dev/null | sed "s#^$PKG_DIR/##")"
  [ -z "$hits" ] && return 0
  printf '%s\n' "$hits"; printf '\n%d stub(s) restant(s) dans lib/\n' "$(printf '%s\n' "$hits" | wc -l | tr -d ' ')"
  return 1
}

check_no_temp_markers() {
  local dirs="$PKG_DIR/lib"; [ -d "$PKG_DIR/test" ] && dirs="$dirs $PKG_DIR/test"
  local hits
  # shellcheck disable=SC2086
  hits="$(grep -rnE --include='*.dart' --exclude='*.g.dart' 'TEMP VISUAL TEST|TEMP PIPELINE|(^|[^a-zA-Z_])print\(' $dirs 2>/dev/null | sed "s#^$PKG_DIR/##")"
  [ -z "$hits" ] && return 0
  printf '%s\n' "$hits"; printf '\nmarqueurs temporaires ou print() à retirer\n'
  return 1
}

# deps — direction des couches : lib/src/<couche>/ n'importe que les couches listées dans deps.<couche>.
# Règles supplémentaires : imports package:/dart: uniquement (pas de relatif) ; domain sans packages interdits.
check_deps() {
  local layer allowed forbidden f line imp target rc=0 self="$PKG_NAME"
  forbidden="$(cfg_list deps.domain_forbidden_packages)"
  for layer in domain data presentation injection; do
    [ -d "$PKG_DIR/lib/src/$layer" ] || continue
    allowed="$(cfg_list "deps.$layer" | tr '\n' ' ')"
    while IFS= read -r line; do
      f="${line%%:*}"; imp="$(printf '%s' "$line" | sed -E "s/^[^:]*:[0-9]+:[[:space:]]*import[[:space:]]+['\"]([^'\"]+)['\"].*/\1/")"
      case "$imp" in
        package:*|dart:*) ;;
        *) ko "$f : import relatif '$imp' (imports package: uniquement)"; rc=1; continue ;;
      esac
      if [[ "$imp" == package:$self/src/* ]]; then
        target="${imp#package:$self/src/}"; target="${target%%/*}"
        if [ "$target" != "$layer" ] && ! grep -qw "$target" <<<"$allowed"; then
          ko "$f : $layer → $target interdit (autorisé : ${allowed:-rien})"; rc=1
        fi
      fi
      if [ "$layer" = domain ] && [ -n "$forbidden" ]; then
        for p in $forbidden; do
          if [[ "$imp" == "package:$p/"* ]]; then ko "$f : domain importe $p (domaine impur)"; rc=1; fi
        done
      fi
    done < <(grep -rnE --include='*.dart' --exclude='*.g.dart' "^[[:space:]]*import[[:space:]]" "$PKG_DIR/lib/src/$layer" | sed "s#^$PKG_DIR/##")
  done
  [ "$rc" = 0 ] && info "couches : $(for l in domain data presentation injection; do [ -d "$PKG_DIR/lib/src/$l" ] && printf '%s ' "$l"; done)"
  return $rc
}

DART_TOOLS="$GAUNTLET_ROOT/dart_tools"
# Les commandes dart tournent depuis PROJECT_ROOT pour que `fvm dart` résolve le SDK du projet ;
# le package d'outils est ciblé explicitement (-C / --packages).
ensure_dart_tools() {
  [ -f "$DART_TOOLS/.dart_tool/package_config.json" ] && return 0
  # shellcheck disable=SC2086
  (cd "$PROJECT_ROOT" && $DART pub get -C "$DART_TOOLS" >/dev/null 2>&1) || { ko "dart pub get a échoué dans $DART_TOOLS"; return 1; }
}
run_dart_tool() { # run_dart_tool <script.dart> <args...>
  local script="$1"; shift
  # shellcheck disable=SC2086
  (cd "$PROJECT_ROOT" && $DART --packages="$DART_TOOLS/.dart_tool/package_config.json" "$DART_TOOLS/bin/$script" "$@")
}

# stub_check — après ARCHITECT : chaque méthode des fichiers stub.include est `throw UnimplementedError()`.
check_stub_check() {
  ensure_dart_tools || return 1
  local files
  files="$(expand_globs "$PKG_DIR" $(cfg_list stub.include | tr '\n' ' ') | filter_excluded '*.g.dart' '*.freezed.dart')"
  if [ -z "$files" ]; then ko "aucun fichier ne correspond à stub.include"; return 1; fi
  info "$(printf '%s\n' "$files" | wc -l | tr -d ' ') fichier(s) inspecté(s)"
  # shellcheck disable=SC2086
  run_dart_tool stub_check.dart --root "$PKG_DIR" $(printf '%s ' $files)
}

# metrics — dart_code_linter, seuils depuis la config. Exit 2 de l'outil = violation.
check_metrics() {
  local rc out
  out="$(cd "$PKG_DIR" && $DART pub global run dart_code_linter:metrics analyze lib \
      --cyclomatic-complexity="$(cfg threshold.cyclomatic 10)" \
      --source-lines-of-code="$(cfg threshold.function_lines 30)" \
      --maximum-nesting-level="$(cfg threshold.nesting 3)" \
      --number-of-parameters="$(cfg threshold.parameters 4)" \
      --set-exit-on-violation-level=warning \
      --exclude='{/**.g.dart,/**.freezed.dart}' \
      --no-congratulate --reporter=console 2>&1)"; rc=$?
  printf '%s\n' "$out" | grep -vE '^\s*$' | tail -60
  [ "$rc" = 0 ] && info "seuils : cyclo ≤ $(cfg threshold.cyclomatic 10), lignes ≤ $(cfg threshold.function_lines 30), imbrication ≤ $(cfg threshold.nesting 3), params ≤ $(cfg threshold.parameters 4)"
  return $rc
}
