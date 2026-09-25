#!/usr/bin/env bash
# checks_maintain.sh — maintenabilité à long terme, en scripts. Sourcé par gauntlet.sh.
#
# Fixables par le cleaner (profil clean) : deps_unused design_system l10n_strings l10n_arb barrel_api
#   unused_code unused_files test_hygiene todo_tickets deprecated_api generated_fresh footprint no_secrets
# Jugement / décision (profil maintain, lu par le reviewer) : deps_features pub_health
#
# Conventions : `// gauntlet-ignore` en fin de ligne exempte cette ligne des greps (avec une raison à côté).

IGNORE_MARK='gauntlet-ignore'

# ---------------------------------------------------------------------------
# pubspec du package
# ---------------------------------------------------------------------------
# pkg_deps <dependencies|dev_dependencies> → "nom<TAB>path|hosted" par ligne
pkg_deps() {
  awk -v sect="$1" '
    $0 ~ "^"sect":" {f=1; next}
    /^[^ ]/ {f=0}
    f && /^  [a-zA-Z_0-9]+:/ { if (cur!="") print cur"\t"kind; cur=$1; sub(/:$/,"",cur); kind="hosted" }
    f && /^    path:/ { kind="path" }
    f && /^    sdk:/  { kind="sdk" }
    END { if (cur!="") print cur"\t"kind }
  ' "$PKG_DIR/pubspec.yaml"
}
pkg_used_packages() { grep -rhoE "package:[a-zA-Z_0-9]+/" "$PKG_DIR/lib" 2>/dev/null | sed 's#package:##; s#/$##' | sort -u; }
# grep_src <dir> <pattern>… — grep -nE multi-motifs, sans les lignes marquées gauntlet-ignore, chemins relatifs au package
grep_src() {
  local dir="$1"; shift
  local args=(); local p; for p in "$@"; do args+=(-e "$p"); done
  grep -rnE --include='*.dart' --exclude='*.g.dart' --exclude='*.freezed.dart' "${args[@]}" "$dir" 2>/dev/null \
    | grep -v "$IGNORE_MARK" | sed "s#^$PKG_DIR/##"
}
presentation_files() { # vues et widgets, hors bloc/keys/events/states
  find "$PKG_DIR/lib/src/presentation" -name '*.dart' 2>/dev/null \
    | grep -vE '/bloc/|_event\.dart$|_state\.dart$|/keys\.dart$|\.g\.dart$|\.freezed\.dart$' \
    | filter_excluded $(cfg_list ds.exempt | sed "s#^#$PKG_DIR/#" | tr '\n' ' ')
}

# ---------------------------------------------------------------------------
# Dépendances
# ---------------------------------------------------------------------------
# deps_unused — chaque dépendance déclarée est importée quelque part dans lib/.
check_deps_unused() {
  local used rc=0 dep kind
  used="$(pkg_used_packages)"
  while IFS=$'\t' read -r dep kind; do
    [ "$kind" = sdk ] && continue
    grep -qx "$dep" <<<"$used" || { ko "dépendance déclarée mais jamais importée : $dep"; rc=1; }
  done < <(pkg_deps dependencies)
  [ "$rc" = 0 ] && info "toutes les dépendances déclarées sont utilisées"
  return $rc
}

# deps_features — les dépendances vers d'autres features sont justifiées dans la spec (§8) et
# n'introduisent aucun cycle dans le graphe des packages du workspace.
check_deps_features() {
  local shared rc=0 dep kind spec="$FEATURE_DIR/spec.md" arch fanout=0
  shared="$(cfg_list deps.shared_packages | tr '\n' ' ')"
  arch="$( [ -f "$spec" ] && awk '/^## 8/{f=1;next} /^## 9/{f=0} f' "$spec" )"
  while IFS=$'\t' read -r dep kind; do
    [ "$kind" = path ] || continue
    grep -qw "$dep" <<<"$shared" && continue
    fanout=$((fanout+1))
    if [ ! -f "$spec" ]; then ko "dépendance inter-features $dep : pas de spec pour la justifier"; rc=1
    elif ! grep -qw "$dep" <<<"$arch"; then ko "dépendance inter-features $dep absente de la spec §8 Architecture — à justifier ou à retirer"; rc=1
    fi
  done < <(pkg_deps dependencies)
  # cycles : graphe name → deps(path) sur tous les pubspec du dossier des features
  local root; root="$PROJECT_ROOT/$(cfg features_root features)"
  local graph; graph="$(find "$root" -name pubspec.yaml -not -path '*/build/*' 2>/dev/null | while read -r p; do
      n="$(sed -n "s/^name:[[:space:]]*['\"]\{0,1\}\([A-Za-z0-9_]*\)['\"]\{0,1\}.*/\1/p" "$p" | head -1)"
      awk '/^dependencies:/{f=1;next} /^[^ ]/{f=0} f && /^  [a-zA-Z_0-9]+:/{cur=$1; sub(/:$/,"",cur)} f && /^    path:/{print cur}' "$p" | sed "s/^/$n /"
    done)"
  local cyc; cyc="$(awk -v start="$PKG_NAME" '
    { adj[$1]=adj[$1]" "$2 }
    function dfs(n, path,   i, k, arr) {
      if (n == start && path != "") { print path" → "start; found=1; return }
      if (seen[n]++) return
      k=split(adj[n], arr, " "); for (i=1;i<=k;i++) if (arr[i]!="") dfs(arr[i], path (path==""?"":" → ") n)
    }
    END { dfs(start, ""); if (!found) exit 0 }' <<<"$graph")"
  [ -n "$cyc" ] && { ko "cycle de dépendances entre features : $cyc"; rc=1; }
  [ "$rc" = 0 ] && info "inter-features : $fanout dépendance(s) hors packages partagés, toutes justifiées, aucun cycle"
  return $rc
}

# pub_health — dépendances hébergées : abandonnées, majeure en retard, ou non publiées depuis trop longtemps.
# Bloquant pour les dépendances AJOUTÉES par la feature ; informatif (warn) pour les préexistantes.
check_pub_health() {
  local rc=0 max_months out dep kind base_pubspec added cache="$HOME/.cache/gauntlet/pub"
  max_months="$(cfg pub.max_age_months 24)"; mkdir -p "$cache"
  out="$GAUNTLET_OUT/outdated.json"
  # --show-all : sinon les packages déjà à jour sont omis du JSON.
  (cd "$PKG_DIR" && $DART pub outdated --json --show-all > "$out" 2>/dev/null) || { printf '[WARN] dart pub outdated indisponible (hors ligne ?) — check sauté\n'; return 0; }
  base_pubspec="$(git -C "$PROJECT_ROOT" show "$(merge_base):$PKG_REL/pubspec.yaml" 2>/dev/null || true)"
  printf '   %-28s %-10s %-10s %-10s %s\n' "package" "actuel" "résolvable" "dernier" "état"
  while IFS=$'\t' read -r dep kind; do
    [ "$kind" = hosted ] || continue
    added=0; grep -qE "^  $dep:" <<<"$base_pubspec" || added=1
    local cur res lat disc pubd age_m state=""
    read -r cur res lat disc < <(jq -r --arg p "$dep" '.packages[] | select(.package==$p) | "\(.current.version // "-") \(.resolvable.version // "-") \(.latest.version // "-") \(.latest.isDiscontinued // false)"' "$out" | head -1)
    [ -n "$cur" ] || { cur="?"; res="?"; lat="?"; disc=false; }
    local meta="$cache/$dep.json"
    if [ ! -f "$meta" ] || [ -n "$(find "$meta" -mtime +7 2>/dev/null)" ]; then
      curl -sL --compressed --max-time 10 "https://pub.dev/api/packages/$dep" -o "$meta" 2>/dev/null || rm -f "$meta"
    fi
    pubd="$( [ -f "$meta" ] && jq -r '.latest.published // empty' "$meta" 2>/dev/null | cut -c1-10)"
    [ "$( [ -f "$meta" ] && jq -r '.isDiscontinued // false' "$meta" 2>/dev/null)" = true ] && disc=true
    age_m=""; [ -n "$pubd" ] && age_m=$(( ( $(date +%s) - $(date -j -f '%Y-%m-%d' "$pubd" +%s 2>/dev/null || date -d "$pubd" +%s) ) / 2592000 ))
    if [ "$disc" = true ]; then state="ABANDONNÉ$( [ -f "$meta" ] && jq -r '.replacedBy // empty' "$meta" | sed 's/^/ → /')"
    elif [ -n "$age_m" ] && [ "$age_m" -gt "$max_months" ]; then state="pas de release depuis $age_m mois"
    elif [ "$lat" != "-" ] && [ "${lat%%.*}" != "${res%%.*}" ]; then state="majeure $lat disponible, contrainte bloque à $res"
    fi
    if [ -n "$state" ]; then
      if [ "$disc" = true ] || [ "$added" = 1 ]; then ko "$dep : $state$( [ "$added" = 1 ] && printf ' (ajouté par cette feature)')"; rc=1
      else printf '[WARN] %s : %s (préexistant)\n' "$dep" "$state"; fi
    fi
    printf '   %-28s %-10s %-10s %-10s %s\n' "$dep" "$cur" "$res" "$lat" "${state:-ok}$( [ "$added" = 1 ] && printf ' · nouveau')"
  done < <(pkg_deps dependencies)
  return $rc
}

# ---------------------------------------------------------------------------
# Présentation : design system, localisation
# ---------------------------------------------------------------------------
# design_system — pas de valeur visuelle brute dans la présentation ; chaque vue importe le DS.
check_design_system() {
  local rc=0 hits files imports f
  files="$(presentation_files)"; [ -n "$files" ] || { info "pas de présentation"; return 0; }
  local pats=(); local p; while IFS= read -r p; do [ -n "$p" ] && pats+=(-e "$p"); done < <(cfg_list ds.forbidden)
  if [ "${#pats[@]}" -gt 0 ]; then
    hits="$(printf '%s\n' "$files" | xargs grep -nE "${pats[@]}" 2>/dev/null | grep -v "$IGNORE_MARK" | sed "s#^$PKG_DIR/##")"
    [ -n "$hits" ] && { printf '%s\n' "$hits" | head -40 | sed 's/^/   ✗ /'; ko "valeurs visuelles en dur : passer par le design system"; rc=1; }
  fi
  imports="$(cfg_list ds.imports)"
  if [ -n "$imports" ]; then
    for f in $(printf '%s\n' "$files" | grep -E '/view/|/widget'); do
      if ! grep -qE "^import '($(printf '%s\n' "$imports" | paste -sd'|' -))" "$f"; then
        ko "${f#$PKG_DIR/} n'importe pas le design system ($(printf '%s' "$imports" | tr '\n' ' '))"; rc=1
      fi
    done
  fi
  [ "$rc" = 0 ] && info "$(printf '%s\n' "$files" | wc -l | tr -d ' ') fichier(s) de présentation conformes"
  return $rc
}

# l10n_strings — aucune chaîne utilisateur en dur dans la présentation.
check_l10n_strings() {
  local files hits
  files="$(presentation_files)"; [ -n "$files" ] || return 0
  local pat="Text\([[:space:]]*['\"][^'\"]*[A-Za-z]{3}|(hintText|labelText|label|title|tooltip|semanticLabel|helperText|errorText|message)[[:space:]]*:[[:space:]]*['\"][^'\"]*[A-Za-z]{3}|SnackBar\([[:space:]]*content:[[:space:]]*Text\([[:space:]]*['\"]"
  # Les interpolations sont retirées avant le test : '${context.l10n.x} ${y}' n'est pas une chaîne en dur.
  hits="$(printf '%s\n' "$files" | xargs grep -nE "$pat" 2>/dev/null | grep -v "$IGNORE_MARK" \
      | while IFS= read -r line; do
          stripped="$(sed -E 's/\$\{[^}]*\}//g; s/\$[a-zA-Z_][a-zA-Z0-9_]*//g' <<<"${line#*:*:}")"
          grep -qE "$pat" <<<"$stripped" && printf '%s\n' "$line"
        done | sed "s#^$PKG_DIR/##")"
  [ -z "$hits" ] && { info "aucune chaîne en dur"; return 0; }
  printf '%s\n' "$hits" | head -40 | sed 's/^/   ✗ /'; ko "chaînes utilisateur en dur : passer par context.l10n"
  return 1
}

# l10n_arb — les clés ajoutées par la feature existent dans toutes les locales.
check_l10n_arb() {
  local glob files added f missing rc=0 base
  glob="$(cfg l10n.arb_glob)"; [ -n "$glob" ] || { info "l10n.arb_glob non configuré, sauté"; return 0; }
  files="$(expand_globs "$PROJECT_ROOT" "$glob")"; [ -n "$files" ] || { ko "aucun fichier ARB pour $glob"; return 1; }
  base="$(merge_base)"
  added="$( { for f in $files; do git -C "$PROJECT_ROOT" diff -U0 "$base" -- "$f" | grep -E '^\+[[:space:]]*"[a-zA-Z][a-zA-Z0-9_]*"[[:space:]]*:' | sed -E 's/^\+[[:space:]]*"([^"]+)".*/\1/'; done; } | sort -u)"
  [ -n "$added" ] || { info "aucune clé l10n ajoutée depuis $base"; return 0; }
  for f in $files; do
    missing="$(for k in $added; do jq -e --arg k "$k" 'has($k)' "$PROJECT_ROOT/$f" >/dev/null 2>&1 || printf '%s ' "$k"; done)"
    [ -n "$missing" ] && { ko "$f : clés manquantes : $missing"; rc=1; }
  done
  [ "$rc" = 0 ] && info "$(printf '%s\n' "$added" | wc -l | tr -d ' ') clé(s) ajoutée(s), présentes dans $(printf '%s\n' "$files" | wc -l | tr -d ' ') locale(s)"
  return $rc
}

# ---------------------------------------------------------------------------
# Surface publique, code mort, hygiène
# ---------------------------------------------------------------------------
# barrel_api — le barrel n'expose ni la couche data ni les implémentations.
check_barrel_api() {
  local barrel="$PKG_DIR/lib/$PKG_NAME.dart" bad
  [ -f "$barrel" ] || { ko "barrel absent : lib/$PKG_NAME.dart"; return 1; }
  bad="$(grep -nE "^export '.*(src/data/|_impl\.dart)" "$barrel")"
  [ -z "$bad" ] && { info "barrel : $(grep -c '^export' "$barrel") export(s), aucune fuite de la couche data"; return 0; }
  printf '%s\n' "$bad" | sed 's/^/   ✗ /'; ko "le barrel exporte la couche data ou une implémentation"
  return 1
}

check_unused_code() {
  local out rc
  out="$(cd "$PKG_DIR" && $DART pub global run dart_code_linter:metrics check-unused-code lib --fatal-unused --no-congratulate --exclude='{/**.g.dart,/**.freezed.dart}' 2>&1)"; rc=$?
  [ "$rc" = 0 ] || printf '%s\n' "$out" | grep -E '⚠|✖' | head -30 | sed 's/^/   /'
  return $rc
}
check_unused_files() {
  local out rc
  out="$(cd "$PKG_DIR" && $DART pub global run dart_code_linter:metrics check-unused-files lib --fatal-unused --no-congratulate --exclude='{/**.g.dart,/**.freezed.dart}' 2>&1)"; rc=$?
  [ "$rc" = 0 ] || printf '%s\n' "$out" | grep -E '⚠|✖' | head -30 | sed 's/^/   /'
  return $rc
}

# test_hygiene — pas de test désactivé, pas d'attente réelle, pas de print dans test/.
check_test_hygiene() {
  [ -d "$PKG_DIR/test" ] || return 0
  local hits; hits="$(grep_src "$PKG_DIR/test" "skip:[[:space:]]*(true|['\"])" "Future\.delayed\(" "sleep\(" "(^|[^a-zA-Z_])print\(")"
  [ -z "$hits" ] && { info "test/ propre"; return 0; }
  printf '%s\n' "$hits" | head -30 | sed 's/^/   ✗ /'; ko "tests désactivés, attentes réelles ou print() dans test/"
  return 1
}

# todo_tickets — un TODO/FIXME référence un ticket (pattern configurable).
check_todo_tickets() {
  local pat hits; pat="$(cfg todo.pattern '\((#[0-9]+|[A-Z]+-[0-9]+)\)')"
  hits="$(grep_src "$PKG_DIR/lib" "(TODO|FIXME)" ; [ -d "$PKG_DIR/test" ] && grep_src "$PKG_DIR/test" "(TODO|FIXME)")"
  hits="$(printf '%s\n' "$hits" | grep -v '^$' | grep -vE "(TODO|FIXME)$pat")"
  [ -z "$hits" ] && { info "tous les TODO référencent un ticket"; return 0; }
  printf '%s\n' "$hits" | head -20 | sed 's/^/   ✗ /'; ko "TODO/FIXME sans ticket (attendu : TODO$pat)"
  return 1
}

# deprecated_api — aucun usage d'API dépréciée (flutter analyze, niveau info).
check_deprecated_api() {
  local out hits
  out="$(cd "$PKG_DIR" && $FLUTTER analyze --no-pub 2>&1)"
  hits="$(printf '%s\n' "$out" | grep -E 'deprecated_member_use')"
  [ -z "$hits" ] && { info "aucune API dépréciée"; return 0; }
  printf '%s\n' "$hits" | head -20 | sed 's/^/   ✗ /'; ko "API dépréciées : migrer avant que ça casse"
  return 1
}

# generated_fresh — les fichiers générés sont à jour et commités.
check_generated_fresh() {
  has_dev_dep build_runner || { info "pas de build_runner"; return 0; }
  # shellcheck disable=SC2086
  (cd "$PKG_DIR" && $DART run build_runner build --delete-conflicting-outputs >/dev/null 2>&1) || { ko "build_runner a échoué"; return 1; }
  local dirty; dirty="$(git -C "$PROJECT_ROOT" status --porcelain -- "$PKG_REL" | grep -E '\.(g|freezed)\.dart$')"
  [ -z "$dirty" ] && { info "fichiers générés à jour et commités"; return 0; }
  printf '%s\n' "$dirty" | sed 's/^/   ✗ /'; ko "fichiers générés modifiés ou non commités : relancer build_runner et commiter"
  return 1
}

# footprint — la feature ne touche que son package, les zones autorisées et son dossier de travail.
check_footprint() {
  local base allowed changed bad
  base="$(merge_base)"
  allowed="$PKG_REL/* pubspec.yaml pubspec.lock .gitignore .claude/features/* $(cfg_list writes.extra | tr '\n' ' ')"
  changed="$( { git -C "$PROJECT_ROOT" diff --name-only "$base"; git -C "$PROJECT_ROOT" ls-files --others --exclude-standard; } | sort -u)"
  bad="$(printf '%s\n' "$changed" | grep -v '^$' | while IFS= read -r f; do
      ok_=0; for g in $allowed; do g="${g//\*\*/\*}"; case "$f" in $g) ok_=1; break;; esac; done; [ "$ok_" = 0 ] && printf '%s\n' "$f"; done)"
  [ -z "$bad" ] && { info "$(printf '%s\n' "$changed" | grep -c . ) fichier(s) touché(s), tous dans le périmètre"; return 0; }
  printf '%s\n' "$bad" | sed 's/^/   ✗ /'; ko "fichiers hors périmètre de la feature (writes.extra pour élargir)"
  return 1
}

# no_secrets — pas d'identifiant, de clé ou d'email de test en clair.
check_no_secrets() {
  local dirs="$PKG_DIR/lib" hits
  [ -d "$PKG_DIR/test" ] && dirs="$dirs $PKG_DIR/test"
  # shellcheck disable=SC2086
  hits="$(grep -rnEi --include='*.dart' --include='*.yaml' --include='*.json' \
      -e "(password|passwd|secret|api[_-]?key|token)[[:space:]]*[:=][[:space:]]*['\"][^'\"$]{6,}" \
      -e "AKIA[0-9A-Z]{16}" -e "sk_(live|test)_[0-9a-zA-Z]{10,}" -e "ghp_[0-9a-zA-Z]{20,}" -e "glpat-[0-9a-zA-Z_-]{10,}" \
      -e "BEGIN (RSA|EC|OPENSSH) PRIVATE KEY" $dirs "$PKG_DIR/maestro" 2>/dev/null | grep -v "$IGNORE_MARK")"
  local mail; mail="$(grep -rnE --include='*.yaml' "inputText:[[:space:]]*['\"]?[^\$[:space:]'\"]+@[^[:space:]'\"]+" "$PKG_DIR/maestro" 2>/dev/null)"
  hits="$(printf '%s\n%s\n' "$hits" "$mail" | grep -v '^$' | sed "s#^$PKG_DIR/##")"
  [ -z "$hits" ] && { info "aucun secret ni identifiant en clair"; return 0; }
  printf '%s\n' "$hits" | head -20 | sed 's/^/   ✗ /'; ko "secrets ou identifiants en clair — variables d'environnement (\${VAR}) uniquement"
  return 1
}

# ---------------------------------------------------------------------------
# Roue réinventée
# ---------------------------------------------------------------------------
# reinvented — une déclaration du package existe déjà ailleurs : même nom public (fonction top-level,
# membre d'extension sur le même type, statique, classe, extension, enum, typedef) ou même corps à
# renommage près (clone de type 2, ≥ dup.min_tokens tokens), workspace entier et package lui-même.
check_reinvented() {
  ensure_dart_tools || return 1
  local root; root="$(cfg features_root features)"
  local ignore; ignore="$(cfg_list dup.ignore_names | paste -sd, -)"
  run_dart_tool dup_check.dart --root "$PROJECT_ROOT/$root" --package "$PKG_DIR" \
    --min-tokens "$(cfg dup.min_tokens 40)" ${ignore:+--ignore-names "$ignore"}
}

# dedup_candidates — entrée de l'agent feature-dedup : pour chaque déclaration réutilisable du
# package, les déclarations du workspace qui lui ressemblent (tokens de nom pondérés IDF, type
# étendu, signature). Toujours vert : c'est un producteur, le verdict vient de l'agent.
check_dedup_candidates() {
  ensure_dart_tools || return 1
  local root; root="$(cfg features_root features)"
  local ignore; ignore="$(cfg_list dup.ignore_names | paste -sd, -)"
  run_dart_tool dup_check.dart --root "$PROJECT_ROOT/$root" --package "$PKG_DIR" \
    ${ignore:+--ignore-names "$ignore"} --ds-package "$(cfg ds.package design)" \
    --candidates "$FEATURE_DIR/dedup_candidates.json"
}

# ---------------------------------------------------------------------------
# README du package : but + API publique, en phase avec le barrel
# ---------------------------------------------------------------------------
check_package_readme() {
  local readme="$PKG_DIR/README.md" barrel="$PKG_DIR/lib/$PKG_NAME.dart" rc=0 sec exp f names n missing=""
  [ -f "$readme" ] || { ko "README.md absent dans $PKG_REL — but du package et API publique"; return 1; }
  while IFS= read -r sec; do
    [ -n "$sec" ] || continue
    grep -qE "$sec" "$readme" || { ko "README.md : section manquante ($sec)"; rc=1; }
  done < <(cfg_list readme.sections)
  [ -f "$barrel" ] || { ko "barrel absent : lib/$PKG_NAME.dart"; return 1; }
  # Chaque déclaration publique exportée par le barrel doit être nommée dans le README.
  while IFS= read -r exp; do
    f="$PKG_DIR/lib/$exp"; [ -f "$f" ] || continue
    names="$(grep -hoE "^(abstract |final |sealed |base |mixin )*(class|enum|extension|mixin|typedef) [A-Za-z_][A-Za-z0-9_]*|^final [a-z][A-Za-z0-9_]*Provider\b" "$f" \
             | awk '{print $NF}' | grep -v '^_' | sort -u)"
    for n in $names; do grep -qw "$n" "$readme" || missing="$missing $n"; done
  done < <(grep -oE "^export '[^']+'" "$barrel" | sed "s/^export '//; s/'$//" | grep -v '^package:')
  [ -n "$missing" ] && { ko "README.md ne mentionne pas :$missing"; rc=1; }
  [ "$rc" = 0 ] && info "README : sections présentes, API publique documentée"
  return $rc
}
