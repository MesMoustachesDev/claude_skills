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

# analyze — le package compile ; les issues (warnings, infos) ne bloquent que dans les fichiers du périmètre.
check_analyze() {
  local out rc issues
  out="$(cd "$PKG_DIR" && $FLUTTER analyze --fatal-warnings --fatal-infos --no-pub 2>&1)"; rc=$?
  [ "$rc" = 0 ] && { info "aucune issue"; return 0; }
  # une erreur de compilation bloque toujours ; le reste est filtré au périmètre
  if printf '%s\n' "$out" | grep -qE '^\s*error •'; then printf '%s\n' "$out" | grep -E '^\s*error •' | head -30; ko "erreurs de compilation"; return 1; fi
  issues="$(printf '%s\n' "$out" | grep -E '^\s*(warning|info) •' | sed -E 's/^.* • ([^ ]+\.dart):([0-9]+):[0-9]+ • (.*)$/\1:\2: \3 — &/' | filter_scope_lines "$PKG_REL/" | sed -E 's/^([^:]+:[0-9]+): [^—]*— //')"
  [ -z "$issues" ] && { info "issues hors périmètre uniquement ($(printf '%s\n' "$out" | grep -cE '^\s*(warning|info) •'), préexistantes)"; return 0; }
  printf '%s\n' "$issues" | head -30
  ko "issues d'analyse dans le périmètre"
  return 1
}

# format — seuls les fichiers du périmètre doivent être formatés.
check_format() {
  local files
  files="$(scope_files "$PKG_REL/" | grep -E '^(lib|test)/' | while IFS= read -r f; do [ -f "$PKG_DIR/$f" ] && printf '%s\n' "$f"; done)"
  [ -n "$files" ] || { info "aucun fichier dart dans le périmètre"; return 0; }
  # shellcheck disable=SC2086
  capture $DART format --set-exit-if-changed --output=none $files
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
  hits="$(grep -rnE --include='*.dart' --exclude='*.g.dart' 'TEMP VISUAL TEST|TEMP PIPELINE|(^|[^a-zA-Z_])print\(' $dirs 2>/dev/null | sed "s#^$PKG_DIR/##" | filter_scope_lines "$PKG_REL/")"
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
  # mode extend : seules les méthodes ajoutées doivent être des stubs
  files="$(printf '%s\n' "$files" | filter_scope_files "$PKG_REL/")"
  if [ -z "$files" ]; then ko "aucun fichier d'implémentation dans le périmètre — l'architect n'a posé aucun contrat"; return 1; fi
  info "$(printf '%s\n' "$files" | wc -l | tr -d ' ') fichier(s) inspecté(s)"
  scope_for_tool "$PKG_REL/" "$GAUNTLET_OUT/scope_pkg.txt"
  # shellcheck disable=SC2086
  run_dart_tool stub_check.dart --root "$PKG_DIR" --scope "$GAUNTLET_OUT/scope_pkg.txt" $(printf '%s ' $files)
}

# metrics — dart_code_linter, seuils depuis la config, rapport JSON filtré au périmètre : une fonction
# compte si l'une de ses lignes est nouvelle (extend) ou toujours (create).
check_metrics() {
  local json="$GAUNTLET_OUT/metrics.json" viol
  (cd "$PKG_DIR" && $DART pub global run dart_code_linter:metrics analyze lib \
      --cyclomatic-complexity="$(cfg threshold.cyclomatic 10)" \
      --source-lines-of-code="$(cfg threshold.function_lines 30)" \
      --maximum-nesting-level="$(cfg threshold.nesting 3)" \
      --number-of-parameters="$(cfg threshold.parameters 4)" \
      --exclude='{/**.g.dart,/**.freezed.dart}' \
      --no-congratulate --reporter=json --json-path="$json" >/dev/null 2>&1)
  [ -s "$json" ] || { ko "dart_code_linter n'a produit aucun rapport"; return 1; }
  viol="$(jq -r '.records[] | .path as $p | (.functions // {}) | to_entries[] | .key as $f
            | .value.codeSpan.start.line as $s | .value.codeSpan.end.line as $e
            | .value.metrics[] | select(.level=="warning" or .level=="alarm")
            | "\($p):\($s):\($e) \($f) \(.metricsId)=\(.value)"' "$json" \
        | awk -v all="$SCOPE_ALL" -v prefix="$PKG_REL/" -v scope="$SCOPE_FILE" '
            BEGIN { while ((getline l < scope) > 0) { if (index(l, ":")) lines[l]=1; else files[l]=1 } }
            { split($1, a, ":"); f=prefix a[1]; s=a[2]+0; e=a[3]+0; keep=(all==1)||(f in files)
              if (!keep) for (i=s;i<=e;i++) if ((f":"i) in lines) { keep=1; break }
              if (keep) { sub(/:[0-9]+$/, "", $1); print "   ✗ " $0 } }')"
  [ -z "$viol" ] && { info "seuils : cyclo ≤ $(cfg threshold.cyclomatic 10), lignes ≤ $(cfg threshold.function_lines 30), imbrication ≤ $(cfg threshold.nesting 3), params ≤ $(cfg threshold.parameters 4) — rien à signaler dans le périmètre"; return 0; }
  printf '%s\n' "$viol" | head -40
  ko "métriques hors seuil dans le périmètre"
  return 1
}
