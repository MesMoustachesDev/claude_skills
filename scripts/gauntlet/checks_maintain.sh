#!/usr/bin/env bash
# checks_maintain.sh — maintenabilité, la part commune à tous les langages : TODO référencés, empreinte de la
# feature, secrets en clair. Sourcé par gauntlet.sh. Le reste de la maintenabilité (dépendances, design system,
# l10n, barrel, code mort…) dépend du langage : stacks/<langage>/checks_maintain.sh.
#
# Conventions : `// gauntlet-ignore` en fin de ligne exempte cette ligne des greps (avec une raison à côté).

IGNORE_MARK='gauntlet-ignore'

# grep_src <dir> <pattern>… — grep -nE multi-motifs dans les sources du langage (stack.ini → extensions), sans
# les lignes marquées gauntlet-ignore, chemins relatifs au package
grep_src() {
  local dir="$1"; shift
  local args=(); local p; for p in "$@"; do args+=(-e "$p"); done
  # shellcheck disable=SC2046
  grep -rnE $(stack_includes) "${args[@]}" "$dir" 2>/dev/null \
    | grep -v "$IGNORE_MARK" | sed "s#^$PKG_DIR/##" | drop_generated
}

# todo_tickets — un TODO/FIXME référence un ticket (pattern configurable).
check_todo_tickets() {
  local pat hits; pat="$(cfg todo.pattern '\((#[0-9]+|[A-Z]+-[0-9]+)\)')"
  local d
  hits="$(for d in $(stack_dirs); do [ -d "$PKG_DIR/$d" ] && grep_src "$PKG_DIR/$d" "(TODO|FIXME)"; done)"
  hits="$(printf '%s\n' "$hits" | grep -v '^$' | grep -vE "(TODO|FIXME)$pat" | filter_scope_lines "$PKG_REL/")"
  [ -z "$hits" ] && { info "tous les TODO référencent un ticket"; return 0; }
  printf '%s\n' "$hits" | head -20 | sed 's/^/   ✗ /'; ko "TODO/FIXME sans ticket (attendu : TODO$pat)"
  return 1
}

# footprint — la feature ne touche que son package, les zones autorisées et son dossier de travail.
check_footprint() {
  local base allowed changed bad app
  # The allowed list holds patterns: without this, `for g in $allowed` expands them against the disk
  # and a nested file (lib/src/...) never matches its package's pattern.
  local -; set -f
  base="$(merge_base)"
  app="$(cfg app_dir .)"; app="${app%/}"; [ "$app" = . ] && app="" || app="$app/"
  # Manifestes et fichiers d'outil du langage (stack.ini → manifests, tool_files), à la racine et dans l'app.
  local f tool=""
  for f in $(stack_list manifests) $(stack_list tool_files); do tool="$tool $f $app$f"; done
  allowed="$PKG_REL/*$tool .gitignore .claude/features/* .claude/rules/* ${app}.claude/rules/* $(writes_extra | tr '\n' ' ')"
  # A submodule zone `x/**` also covers its gitlink `x` (a submodule shows up as one changed path).
  allowed="$allowed $(writes_extra | sed -n 's#/\*\*$##p' | tr '\n' ' ')"
  # quotepath=false: otherwise git escapes non-ASCII paths ("polish/apr\303\250s/") and they never match.
  changed="$( { git -C "$PROJECT_ROOT" -c core.quotepath=false diff --name-only "$base"; git -C "$PROJECT_ROOT" -c core.quotepath=false ls-files --others --exclude-standard; } | sort -u)"
  bad="$(printf '%s\n' "$changed" | grep -v '^$' | while IFS= read -r f; do
      ok_=0; for g in $allowed; do g="${g//\*\*/\*}"; case "$f" in $g) ok_=1; break;; esac; done; [ "$ok_" = 0 ] && printf '%s\n' "$f"; done)"
  [ -z "$bad" ] && { info "$(printf '%s\n' "$changed" | grep -c . ) fichier(s) touché(s), tous dans le périmètre"; return 0; }
  printf '%s\n' "$bad" | sed 's/^/   ✗ /'; ko "fichiers hors périmètre de la feature (writes.extra pour élargir)"
  return 1
}

# no_secrets [test] — pas d'identifiant, de clé ou d'email de test en clair.
#   test : test/ seulement (profil red : un marqueur posé après le gel force un re-gel).
check_no_secrets() {
  local dirs="" hits mail="" d
  if [ "${1:-}" != test ]; then for d in $(stack_list src_dirs) maestro; do dirs="$dirs $PKG_DIR/$d"; done; fi
  for d in $(stack_list test_dirs); do [ -d "$PKG_DIR/$d" ] && dirs="$dirs $PKG_DIR/$d"; done
  [ -n "${dirs// /}" ] || { info "rien à inspecter"; return 0; }
  # Sources du langage, plus la config (yaml, json) et les flows Maestro.
  # shellcheck disable=SC2086,SC2046
  hits="$(grep -rnEi $(stack_includes) --include='*.yaml' --include='*.json' \
      -e "(password|passwd|secret|api[_-]?key|token)[[:space:]]*[:=][[:space:]]*['\"][^'\"$]{6,}" \
      -e "AKIA[0-9A-Z]{16}" -e "sk_(live|test)_[0-9a-zA-Z]{10,}" -e "ghp_[0-9a-zA-Z]{20,}" -e "glpat-[0-9a-zA-Z_-]{10,}" \
      -e "BEGIN (RSA|EC|OPENSSH) PRIVATE KEY" $dirs 2>/dev/null | grep -v "$IGNORE_MARK")"
  [ "${1:-}" = test ] || mail="$(grep -rnE --include='*.yaml' "inputText:[[:space:]]*['\"]?[^\$[:space:]'\"]+@[^[:space:]'\"]+" "$PKG_DIR/maestro" 2>/dev/null)"
  hits="$(printf '%s\n%s\n' "$hits" "$mail" | grep -v '^$' | sed "s#^$PKG_DIR/##" | filter_scope_lines "$PKG_REL/")"
  [ -z "$hits" ] && { info "aucun secret ni identifiant en clair"; return 0; }
  printf '%s\n' "$hits" | head -20 | sed 's/^/   ✗ /'; ko "secrets ou identifiants en clair — variables d'environnement (\${VAR}) uniquement"
  return 1
}
