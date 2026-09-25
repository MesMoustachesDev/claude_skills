#!/usr/bin/env bash
# lib.sh — helpers partagés par le gauntlet. Sourcé, pas exécuté.

# ---------------------------------------------------------------------------
# Sortie
# ---------------------------------------------------------------------------
if [ -t 1 ]; then C_OK=$'\033[32m'; C_KO=$'\033[31m'; C_DIM=$'\033[2m'; C_B=$'\033[1m'; C_0=$'\033[0m'; else C_OK=; C_KO=; C_DIM=; C_B=; C_0=; fi
info()    { printf '%s   %s%s\n' "$C_DIM" "$*" "$C_0"; }
section() { printf '\n%s== %s ==%s\n' "$C_B" "$*" "$C_0"; }
ok()      { printf '%s[OK]%s   %s\n' "$C_OK" "$C_0" "$*"; }
ko()      { printf '%s[FAIL]%s %s\n' "$C_KO" "$C_0" "$*"; }
die()     { printf '%s[ABORT]%s %s\n' "$C_KO" "$C_0" "$*" >&2; exit 2; }

# ---------------------------------------------------------------------------
# Contexte projet
# ---------------------------------------------------------------------------
# Variables exportées : PROJECT_ROOT CFG_FILE FEATURE PKG_REL PKG_DIR PKG_NAME FEATURE_DIR
#                       GAUNTLET_OUT FLUTTER DART BASE_BRANCH
init_project_context() {
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "pas dans un repo git"
  # GAUNTLET_CFG : surcharge de la config (tests du gauntlet lui-même, dry-run sur un projet non initialisé).
  CFG_FILE="${GAUNTLET_CFG:-$PROJECT_ROOT/.claude/rules/feature_pipeline.md}"
  [ -f "$CFG_FILE" ] || die "config absente : $CFG_FILE (lancer /feature init)"

  FLUTTER="$(cfg flutter 'flutter')"
  DART="$(cfg dart 'dart')"
  BASE_BRANCH="$(cfg base_branch 'develop')"

  # Les exécutables pub (mason, metrics, mutation_test) et leur `dart` doivent être ceux du SDK du
  # projet : avec fvm, on met le SDK épinglé en tête de PATH. Sans ça, un vieux `dart` système
  # (celui de /usr/local/bin) casse tout silencieusement.
  export PATH="$HOME/.pub-cache/bin:$PATH"
  if [[ "$DART" == fvm* ]] && [ -f "$PROJECT_ROOT/.fvmrc" ]; then
    local fv; fv="$(jq -r '.flutter // empty' "$PROJECT_ROOT/.fvmrc" 2>/dev/null)"
    [ -n "$fv" ] && [ -d "$HOME/fvm/versions/$fv/bin" ] && export PATH="$HOME/fvm/versions/$fv/bin:$PATH"
  fi

  FEATURE="$1"
  if [ -n "$FEATURE" ]; then
    # GAUNTLET_FEATURES_ROOT : relocalise .claude/features (tests du gauntlet sans écrire dans le projet).
    FEATURE_DIR="${GAUNTLET_FEATURES_ROOT:-$PROJECT_ROOT/.claude/features}/$FEATURE"
    GAUNTLET_OUT="$FEATURE_DIR/.gauntlet"
    mkdir -p "$GAUNTLET_OUT"
    # Mode et package : pipeline.json (écrit par l'orchestrateur) > variables d'environnement > config.
    #   create : la feature EST le package, tout le package est dans le périmètre.
    #   extend : la feature ajoute à un package existant, le périmètre = fichiers/lignes modifiés depuis base.
    MODE="${GAUNTLET_MODE:-$(pipeline_get .mode)}"; MODE="${MODE:-create}"
    PKG_REL="${GAUNTLET_PACKAGE:-$(pipeline_get .package)}"
    [ -n "$PKG_REL" ] || PKG_REL="$(cfg package_path 'features/{name}' | sed "s/{name}/$FEATURE/g")"
    PKG_REL="${PKG_REL%/}"
    PKG_DIR="$PROJECT_ROOT/$PKG_REL"
    [ -d "$PKG_DIR" ] || die "package introuvable : $PKG_DIR"
    PKG_NAME="$(sed -n "s/^name:[[:space:]]*['\"]\{0,1\}\([A-Za-z0-9_]*\)['\"]\{0,1\}.*/\1/p" "$PKG_DIR/pubspec.yaml" | head -1)"
    scope_init
  fi
}

# ---------------------------------------------------------------------------
# Périmètre modifié (mode extend)
# ---------------------------------------------------------------------------
# SCOPE_FILE : une ligne par élément, relative à PROJECT_ROOT —
#   "chemin"        fichier entier (ajouté ou non suivi)
#   "chemin:ligne"  ligne ajoutée dans un fichier modifié
# SCOPE_ALL=1 en mode create : tout le package est dans le périmètre.
scope_init() {
  SCOPE_FILE="$GAUNTLET_OUT/scope.txt"
  if [ "$MODE" != extend ]; then SCOPE_ALL=1; : > "$SCOPE_FILE"; return; fi
  SCOPE_ALL=0
  local base; base="$(merge_base)"
  {
    git -C "$PROJECT_ROOT" diff --name-only --diff-filter=A "$base" -- "$PKG_REL"
    git -C "$PROJECT_ROOT" ls-files --others --exclude-standard -- "$PKG_REL"
    git -C "$PROJECT_ROOT" diff -U0 --diff-filter=M "$base" -- "$PKG_REL" \
      | awk '/^\+\+\+ b\//{f=substr($0,7)} /^@@/{split($3,a,","); s=substr(a[1],2); n=(a[2]==""?1:a[2]); for(i=0;i<n;i++) print f":"(s+i)}'
  } | sort -u > "$SCOPE_FILE"
}
scope_summary() { [ "$SCOPE_ALL" = 1 ] && echo "package entier (create)" || echo "$(grep -vc ':' "$SCOPE_FILE") fichier(s) nouveau(x), $(grep -c ':' "$SCOPE_FILE") ligne(s) ajoutée(s) dans $(grep ':' "$SCOPE_FILE" | cut -d: -f1 | sort -u | wc -l | tr -d ' ') fichier(s) modifié(s) (extend)"; }
# in_scope_file <chemin relatif à PROJECT_ROOT> — fichier nouveau ou touché
in_scope_file() { [ "$SCOPE_ALL" = 1 ] || grep -qxE "$1(:[0-9]+)?" "$SCOPE_FILE" 2>/dev/null || grep -q "^$1:" "$SCOPE_FILE" 2>/dev/null; }
# scope_files <prefix> — fichiers du périmètre, relatifs à <prefix> (ex: "$PKG_REL/"), .dart seulement
scope_files() {
  local prefix="$1"
  if [ "$SCOPE_ALL" = 1 ]; then (cd "$PROJECT_ROOT/$prefix" && find lib test -name '*.dart' 2>/dev/null)
  else cut -d: -f1 "$SCOPE_FILE" | grep '\.dart$' | sort -u | sed "s#^$prefix##"; fi
}
# filter_scope_lines <prefix> — stdin "chemin:ligne:…" (chemins relatifs à <prefix>) → garde les hits du périmètre
filter_scope_lines() {
  local prefix="$1"
  if [ "$SCOPE_ALL" = 1 ]; then cat; return; fi
  awk -v prefix="$prefix" -v scope="$SCOPE_FILE" '
    BEGIN { while ((getline l < scope) > 0) { if (index(l, ":")) lines[l]=1; else files[l]=1 } }
    { split($0, a, ":"); f=prefix a[1]; if ((f in files) || ((f":"a[2]) in lines)) print }'
}
# filter_scope_files <prefix> — stdin "chemin…" → garde les lignes dont le fichier est dans le périmètre
filter_scope_files() {
  local prefix="$1"
  if [ "$SCOPE_ALL" = 1 ]; then cat; return; fi
  awk -v prefix="$prefix" -v scope="$SCOPE_FILE" '
    BEGIN { while ((getline l < scope) > 0) { sub(/:[0-9]+$/, "", l); files[l]=1 } }
    { split($0, a, ":"); if ((prefix a[1]) in files) print }'
}
# scope_for_tool <prefix> <out> — copie du périmètre avec chemins relatifs à <prefix>, pour les outils Dart (--scope)
scope_for_tool() {
  if [ "$SCOPE_ALL" = 1 ]; then : > "$2"; else sed "s#^$1##" "$SCOPE_FILE" > "$2"; fi
}

# cfg <clé> [défaut] — lit le bloc ```ini de feature_pipeline.md
cfg() {
  local key="$1" default="${2:-}" val
  val="$(awk '/^```ini/{f=1;next} /^```/{f=0} f' "$CFG_FILE" \
        | grep -E "^[[:space:]]*${key}[[:space:]]*=" | head -1 | sed 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//')"
  if [ -n "$val" ]; then printf '%s' "$val"; else printf '%s' "$default"; fi
}
# cfg_list <clé> — une valeur par ligne, séparateur virgule, vides ignorés
cfg_list() { cfg "$1" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$'; }

# pipeline_get <clé jq> — lit .claude/features/<feature>/pipeline.json
pipeline_get() { [ -f "$FEATURE_DIR/pipeline.json" ] && jq -r "$1 // empty" "$FEATURE_DIR/pipeline.json"; }

# ---------------------------------------------------------------------------
# Fichiers
# ---------------------------------------------------------------------------
# expand_globs <dir> <glob>... — un chemin relatif à <dir> par ligne. Supporte ** (find) et * simple.
expand_globs() {
  local dir="$1"; shift
  local g base rest
  for g in "$@"; do
    [ -n "$g" ] || continue
    case "$g" in
      *'**'*)
        base="${g%%\*\**}"; rest="${g#*\*\*}"; rest="${rest#/}"
        base="${base%/}"; [ -n "$base" ] || base="."
        [ -d "$dir/$base" ] || continue
        if [[ "$rest" == */* ]]; then
          (cd "$dir" && find "$base" -type f -path "*/$rest" 2>/dev/null)
        else
          (cd "$dir" && find "$base" -type f -name "*${rest#\*}" 2>/dev/null)
        fi
        ;;
      *)
        (cd "$dir" && shopt -s nullglob && for f in $g; do [ -f "$f" ] && printf '%s\n' "$f"; done)
        ;;
    esac
  done | sed 's#^\./##' | sort -u
}
# filter_excluded <glob>... — filtre stdin (chemins) contre des globs d'exclusion (case, * traverse /)
filter_excluded() {
  local f g keep
  while IFS= read -r f; do
    keep=1
    for g in "$@"; do
      g="${g//\*\*/\*}"
      # shellcheck disable=SC2254
      case "$f" in $g|*/$g) keep=0; break ;; esac
    done
    [ "$keep" = 1 ] && printf '%s\n' "$f"
  done
}

# merge_base — commit de référence pour les diffs (base_branch)
merge_base() {
  git -C "$PROJECT_ROOT" merge-base HEAD "origin/$BASE_BRANCH" 2>/dev/null \
    || git -C "$PROJECT_ROOT" merge-base HEAD "$BASE_BRANCH" 2>/dev/null \
    || git -C "$PROJECT_ROOT" rev-list --max-parents=0 HEAD | tail -1
}

# has_dev_dep <pkg> — le package feature déclare-t-il cette dev dependency ?
has_dev_dep() { awk '/^dev_dependencies:/{f=1;next} /^[^ ]/{f=0} f' "$PKG_DIR/pubspec.yaml" | grep -qE "^[[:space:]]+$1:"; }

# ---------------------------------------------------------------------------
# Exécution des checks
# ---------------------------------------------------------------------------
EXPENSIVE_CHECKS="coverage mutation qa"
is_expensive() { case " $EXPENSIVE_CHECKS " in *" $1 "*) return 0 ;; esac; return 1; }

# run_checks <label> <check[:mode]>... — exécute, journalise, résume. Les checks coûteux sont
# sautés si un check rapide a échoué avant eux (inutile de muter un code qui ne passe pas ses tests).
run_checks() {
  local label="$1"; shift
  local log="$GAUNTLET_OUT/last_${label}.log" json="$GAUNTLET_OUT/last_${label}.json"
  : > "$log"
  # Le bloc tourne dans un sous-shell (pipe vers tee) : le verdict passe par le fichier JSON,
  # pas par des variables — elles seraient perdues à la sortie du pipe.
  {
    local failed="" skipped="" passed="" spec name mode rc fast_failed=0
    printf 'gauntlet %s — feature %s — package %s — périmètre : %s — %s\n' "$label" "$FEATURE" "$PKG_REL" "$(scope_summary)" "$(date '+%Y-%m-%d %H:%M:%S')"
    for spec in "$@"; do
      name="${spec%%:*}"; mode=""; [[ "$spec" == *:* ]] && mode="${spec#*:}"
      section "$name${mode:+ ($mode)}"
      if is_expensive "$name" && [ "$fast_failed" = 1 ]; then
        info "sauté : un check rapide a échoué"; skipped="$skipped $name"; continue
      fi
      "check_$name" "$mode"; rc=$?
      if [ "$rc" -eq 0 ]; then ok "$name"; passed="$passed $name"
      else ko "$name"; failed="$failed $name"; is_expensive "$name" || fast_failed=1; fi
    done
    section "résumé $label"
    [ -n "$passed" ]  && printf '  passés  :%s\n' "$passed"
    [ -n "$failed" ]  && printf '  échoués :%s\n' "$failed"
    [ -n "$skipped" ] && printf '  sautés  :%s\n' "$skipped"
    jq -n --arg profile "$label" --arg feature "$FEATURE" \
          --argjson ok "$([ -z "$failed" ] && echo true || echo false)" \
          --arg passed "$passed" --arg failed "$failed" --arg skipped "$skipped" \
          '{profile:$profile, feature:$feature, ok:$ok, date:(now|todate),
            passed:($passed|split(" ")|map(select(.!=""))),
            failed:($failed|split(" ")|map(select(.!=""))),
            skipped:($skipped|split(" ")|map(select(.!="")))}' > "$json"
  } 2>&1 | tee -a "$log"
  [ "$(jq -r '.ok' "$json" 2>/dev/null)" = true ]
}
