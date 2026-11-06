#!/usr/bin/env bash
# checks_maintain.sh — maintenabilité d'un module Android / Kotlin : design system, chaînes, strings.xml, hygiène
# des tests, API dépréciées, README. Sourcé par stacks/android/checks.sh.
#
# Pas de version Android (non applicables, ADR 0011) : deps_unused, deps_features, pub_health (dépendances Gradle :
# pas d'outil fiable sans réseau), reinvented, dedup_candidates (outils AST Dart), barrel_api (Kotlin n'a pas de
# barrel ; `internal` fait ce travail, le compilateur le garde), unused_code, unused_files (detekt les porte s'il
# est appliqué : voir analyze), widget_functions (un composable EST une fonction), generated_fresh (KSP et kapt
# génèrent dans build/, jamais commité).

# presentation_files — sources de la présentation (stack.ini → presentation_dirs), chemins absolus, hors
# ViewModel, UiState, événements, testTags et ds.exempt.
presentation_files() {
  local f g
  (cd "$PKG_DIR" && find src/main -type f -name '*.kt' 2>/dev/null) | sort | while IFS= read -r f; do
    for g in $(stack_list presentation_dirs); do
      # shellcheck disable=SC2254
      case "$f" in $g/*) printf '%s\n' "$f"; break ;; esac
    done
  done | grep -vE '(ViewModel|UiState|UiEvent|TestTags)\.kt$' | drop_generated | sed "s#^#$PKG_DIR/#" \
    | filter_excluded $(cfg_list ds.exempt | sed "s#^#$PKG_DIR/#" | tr '\n' ' ')
}

# design_system — pas de valeur visuelle brute dans la présentation (ds.forbidden : Color(0x…), 16.dp, 14.sp…) ;
# chaque écran (fichier *Screen.kt) importe le design system (ds.imports, préfixes de paquet).
check_design_system() {
  local rc=0 hits files f imports
  files="$(presentation_files)"; [ -n "$files" ] || { info "pas de présentation"; return 0; }
  local pats=() p; while IFS= read -r p; do [ -n "$p" ] && pats+=(-e "$p"); done < <(cfg_list ds.forbidden)
  if [ "${#pats[@]}" -gt 0 ]; then
    hits="$(printf '%s\n' "$files" | xargs grep -nHE "${pats[@]}" 2>/dev/null | grep -v "$IGNORE_MARK" \
      | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|\*|/\*)' | sed "s#^$PKG_DIR/##" | filter_scope_lines "$PKG_REL/")"
    [ -n "$hits" ] && { printf '%s\n' "$hits" | head -40 | sed 's/^/   ✗ /'; ko "valeurs visuelles en dur : passer par le thème et les tokens du design system"; rc=1; }
  fi
  imports="$(cfg_list ds.imports)"
  if [ -n "$imports" ]; then
    for f in $(printf '%s\n' "$files" | grep -E 'Screen\.kt$' | sed "s#^$PKG_DIR/##" | filter_scope_files "$PKG_REL/" | sed "s#^#$PKG_DIR/#"); do
      grep -qE "^import ($(printf '%s\n' "$imports" | sed 's/\./\\./g' | paste -sd'|' -))" "$f" \
        || { ko "${f#$PKG_DIR/} n'importe pas le design system ($(printf '%s' "$imports" | tr '\n' ' '))"; rc=1; }
    done
  fi
  [ "$rc" = 0 ] && info "$(printf '%s\n' "$files" | wc -l | tr -d ' ') fichier(s) de présentation conformes"
  return $rc
}

# l10n_strings — aucune chaîne utilisateur en dur dans la présentation : Text("…"), text = "…", label, title,
# placeholder, contentDescription, message… passent par stringResource(R.string.…). Les testTags et les clés de
# navigation ne sont pas visés.
L10N_KT_RE='Text\([[:space:]]*"[^"]*[A-Za-z]{3}|(text|title|label|placeholder|contentDescription|message|supportingText|confirmButtonText|dismissButtonText)[[:space:]]*=[[:space:]]*"[^"]*[A-Za-z]{3}|Toast\.makeText\([^,]*,[[:space:]]*"'
check_l10n_strings() {
  local files hits line stripped
  files="$(presentation_files)"; [ -n "$files" ] || return 0
  # Les gabarits ${…} et $x sont retirés avant le test : "${stringResource(R.string.a)} $n" n'est pas en dur.
  hits="$(printf '%s\n' "$files" | xargs grep -nHE "$L10N_KT_RE" 2>/dev/null | grep -v "$IGNORE_MARK" \
      | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|\*|/\*)' \
      | while IFS= read -r line; do
          stripped="$(sed -E 's/\$\{[^}]*\}//g; s/\$[a-zA-Z_][a-zA-Z0-9_]*//g' <<<"${line#*:*:}")"
          grep -qE "$L10N_KT_RE" <<<"$stripped" && printf '%s\n' "$line"
        done | sed "s#^$PKG_DIR/##" | filter_scope_lines "$PKG_REL/")"
  [ -z "$hits" ] && { info "aucune chaîne en dur"; return 0; }
  printf '%s\n' "$hits" | head -40 | sed 's/^/   ✗ /'; ko "chaînes utilisateur en dur : passer par stringResource(R.string.…)"
  return 1
}

# l10n_arb — version Android : strings.xml. Les clés ajoutées au strings.xml par défaut (res/values/) du module, et
# les clés existantes que le code modifié lit (R.string.<clé>), existent dans chaque locale (res/values-xx/) que le
# module traduit déjà. translatable="false" n'a pas à l'être. l10n.strings_glob (relatif à la racine) ajoute des
# fichiers hors du module (un module de ressources partagé).
strings_keys() { # <fichier> (stdin si -) → clés traduisibles, triées
  sed -nE '/translatable="false"/d; s/.*<(string|plurals)[^>]*name="([^"]*)".*/\2/p' "$1" 2>/dev/null | LC_ALL=C sort -u
}
check_l10n_arb() {
  local defaults locales f g base added="" used all tmp missing rc=0
  defaults="$( { ls "$PKG_DIR"/src/main/res/values/strings.xml 2>/dev/null | sed "s#^$PROJECT_ROOT/##"
                 g="$(cfg l10n.strings_glob)"; [ -n "$g" ] && expand_globs "$PROJECT_ROOT" "$g" | grep '/values/strings\.xml$'; } | sort -u)"
  [ -n "$defaults" ] || { info "pas de res/values/strings.xml dans le module"; return 0; }
  base="$(merge_base)"; tmp="$(mktemp)"
  for f in $defaults; do
    show_at "$base" "$f" > "$tmp" 2>/dev/null || : > "$tmp"
    added="$added $(LC_ALL=C comm -23 <(strings_keys "$PROJECT_ROOT/$f") <(strings_keys "$tmp") | tr '\n' ' ')"
  done
  rm -f "$tmp"
  all="$(for f in $defaults; do strings_keys "$PROJECT_ROOT/$f"; done | LC_ALL=C sort -u)"
  used="$( (cd "$PKG_DIR" && grep -rnoE --include='*.kt' 'R\.(string|plurals)\.[A-Za-z_][A-Za-z0-9_]*' src/main 2>/dev/null) \
    | filter_scope_lines "$PKG_REL/" | sed -E 's/.*R\.(string|plurals)\.//' | LC_ALL=C sort -u \
    | LC_ALL=C comm -12 - <(printf '%s\n' "$all") | LC_ALL=C comm -23 - <(printf '%s\n' $added | LC_ALL=C sort -u))"
  added="$(printf '%s\n' $added | grep -v '^$')"
  [ -n "$added$used" ] || { info "aucune clé strings.xml ajoutée depuis $base ni lue par le code modifié"; return 0; }
  locales="$(for f in $defaults; do ls "$PROJECT_ROOT/$(dirname "$(dirname "$f")")"/values-*/strings.xml 2>/dev/null; done | sed "s#^$PROJECT_ROOT/##")"
  [ -n "$locales" ] || { info "$(printf '%s' "$added" | grep -c .) clé(s) ajoutée(s), aucune autre locale (values-xx) à tenir"; return 0; }
  for f in $locales; do
    missing="$(LC_ALL=C comm -23 <(printf '%s\n' $added | LC_ALL=C sort -u) <(strings_keys "$PROJECT_ROOT/$f") | tr '\n' ' ')"
    [ -n "${missing// /}" ] && { ko "$f : clés manquantes : $missing"; rc=1; }
    missing="$(LC_ALL=C comm -23 <(printf '%s\n' "$used" | grep -v '^$' | LC_ALL=C sort -u) <(strings_keys "$PROJECT_ROOT/$f") | tr '\n' ' ')"
    [ -n "${missing// /}" ] && { ko "$f : clés existantes lues par le code modifié, absentes ici : $missing"; rc=1; }
  done
  [ "$rc" = 0 ] && info "$(printf '%s' "$added" | grep -c .) clé(s) ajoutée(s) et $(printf '%s' "$used" | grep -c .) existante(s) lue(s), présentes dans $(printf '%s\n' "$locales" | wc -l | tr -d ' ') locale(s)"
  return $rc
}

# test_hygiene — pas de test désactivé (@Ignore, @Disabled), d'attente réelle (Thread.sleep, runBlocking { delay })
# ni de println dans les tests. Dans runTest, delay() avance le temps virtuel : il n'est pas visé.
check_test_hygiene() {
  local d dirs="" hits
  for d in $(stack_list test_dirs); do [ -d "$PKG_DIR/$d" ] && dirs="$dirs $PKG_DIR/$d"; done
  [ -n "$dirs" ] || return 0
  # shellcheck disable=SC2086
  hits="$(grep -rnE --include='*.kt' --include='*.java' '@Ignore|@Disabled|Thread\.sleep\(|SystemClock\.sleep\(|(^|[^A-Za-z0-9_.])println\(' $dirs 2>/dev/null \
    | grep -v "$IGNORE_MARK" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|\*|/\*)' | sed "s#^$PKG_DIR/##" | filter_scope_lines "$PKG_REL/")"
  [ -z "$hits" ] && { info "tests propres"; return 0; }
  printf '%s\n' "$hits" | head -30 | sed 's/^/   ✗ /'
  ko "tests désactivés, attentes réelles ou println() : runTest et le temps virtuel, pas Thread.sleep"
  return 1
}

# deprecated_api — aucun usage d'API dépréciée dans le périmètre (avertissements « is deprecated » du compilateur
# Kotlin, relus dans la compilation d'analyze, ou relancée).
check_deprecated_api() {
  local log="$GAUNTLET_OUT/gradle_compile.log" hits
  [ -s "$log" ] || gradle_log compile :@compile
  hits="$(kotlin_diag "$log" w | grep -iE 'deprecated' | filter_scope_lines "$PKG_REL/")"
  [ -z "$hits" ] && { info "aucune API dépréciée dans le périmètre"; return 0; }
  printf '%s\n' "$hits" | head -20 | sed 's/^/   ✗ /'; ko "API dépréciées : migrer avant que ça casse"
  return 1
}

# package_readme — README.md du module : les sections de readme.sections. Le module d'application
# (com.android.application) n'en a pas besoin. Kotlin n'a pas de barrel : l'API publique se lit dans le README.
check_package_readme() {
  local readme="$PKG_DIR/README.md" rc=0 sec
  has_plugin_in_module 'com\.android\.application|android\.application' && { info "module d'application, README de package non exigé"; return 0; }
  [ -f "$readme" ] || { ko "README.md absent dans $PKG_REL — but du module et API publique"; return 1; }
  while IFS= read -r sec; do
    [ -n "$sec" ] || continue
    grep -qE "$sec" "$readme" || { ko "README.md : section manquante ($sec)"; rc=1; }
  done < <(cfg_list readme.sections)
  [ "$rc" = 0 ] && info "README : sections présentes"
  return $rc
}
# has_plugin_in_module <regex> — le build du module lui-même cite <regex>
has_plugin_in_module() { cat "$PKG_DIR/build.gradle.kts" "$PKG_DIR/build.gradle" 2>/dev/null | grep -v '^[[:space:]]*//' | grep -qE "$1"; }
