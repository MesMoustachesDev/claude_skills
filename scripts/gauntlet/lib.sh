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
# Worktree de la feature, pour les hooks
# ---------------------------------------------------------------------------
# Un sous-agent hérite du cwd de la session de l'orchestrateur, qui n'est pas toujours le worktree de la
# feature (session ouverte sur le checkout principal, reprise, cwd remis à zéro). Les hooks ne s'y fient
# donc pas seuls : ils cherchent le worktree dans le fichier écrit, le cwd, puis le prompt de l'agent
# (l'orchestrateur y met toujours « Racine : <worktree> »).

# feature_root_from <chemin> — racine git de <chemin> (ou de son premier parent existant) si elle est sur
# une branche feature/*, rien sinon
feature_root_from() {
  local d="$1" top
  [ -n "$d" ] || return 1
  while [ ! -d "$d" ] && [ "$d" != / ] && [ "$d" != . ]; do d="$(dirname "$d")"; done
  top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" || return 1
  case "$(git -C "$top" branch --show-current 2>/dev/null)" in feature/*) printf '%s\n' "$top" ;; *) return 1 ;; esac
}
# hook_agent_transcript <entrée JSON du hook> — transcript du sous-agent : agent_transcript_path, sinon
# déduit du transcript de la session (<session>/subagents/agent-<id>.jsonl)
hook_agent_transcript() {
  local t id
  t="$(jq -r '.agent_transcript_path // empty' <<<"$1")"
  [ -n "$t" ] && { printf '%s\n' "$t"; return; }
  t="$(jq -r '.transcript_path // empty' <<<"$1")"; id="$(jq -r '.agent_id // empty' <<<"$1")"
  [ -n "$t" ] && [ -n "$id" ] && printf '%s\n' "${t%.jsonl}/subagents/agent-$id.jsonl"
}
# hook_feature_root <cwd> <fichier ou ""> <transcript de l'agent ou ""> — le worktree de la feature
hook_feature_root() {
  local r wt pat='/[^ "`'"'"'\\]*/\.claude/worktrees/feature-[A-Za-z0-9_.-]*'
  r="$(feature_root_from "$2")" && { printf '%s\n' "$r"; return 0; }
  r="$(feature_root_from "$1")" && { printf '%s\n' "$r"; return 0; }
  [ -n "$3" ] && [ -f "$3" ] || return 1
  # La ligne « Racine : » du prompt d'abord ; à défaut, le premier worktree de feature cité.
  wt="$(grep -m1 'Racine' "$3" | grep -oE "$pat" | head -1)"
  [ -n "$wt" ] || wt="$(head -c 400000 "$3" | grep -oE "$pat" | head -1)"
  r="$(feature_root_from "$wt")" && { printf '%s\n' "$r"; return 0; }
  return 1
}

# ---------------------------------------------------------------------------
# Contexte projet
# ---------------------------------------------------------------------------
# Variables exportées : PROJECT_ROOT CFG_FILE FEATURE PKG_REL PKG_DIR PKG_NAME FEATURE_DIR
#                       GAUNTLET_OUT STACK STACK_DIR FLUTTER DART BASE_BRANCH MODE SIZE
init_project_context() {
  PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "pas dans un repo git"
  # GAUNTLET_CFG : surcharge de la config (tests du gauntlet lui-même, dry-run sur un projet non initialisé).
  CFG_FILE="${GAUNTLET_CFG:-$PROJECT_ROOT/.claude/rules/feature_pipeline.md}"
  [ -f "$CFG_FILE" ] || die "config absente : $CFG_FILE (lancer /feature init)"

  BASE_BRANCH="$(cfg base_branch 'develop')"

  # APP_ROOT : le dossier de l'app Flutter (app_dir), là où vit .fvmrc. Toute commande dart/flutter lancée
  # hors d'un package (outils Dart du gauntlet, pub global) tourne depuis APP_ROOT : depuis la racine du
  # repo, `fvm dart` ne trouve pas de .fvmrc et retombe sur le SDK global (Dart 2.18 sur cette machine).
  APP_ROOT="$PROJECT_ROOT/$(cfg app_dir .)"; APP_ROOT="${APP_ROOT%/}"; APP_ROOT="${APP_ROOT%/.}"
  # Langage : celui de l'app, puis celui du package de la feature une fois connu (stack_init).
  stack_init "$(lang_dir "$APP_ROOT")"
  # Les exécutables pub (mason, metrics, mutation_test) et leur `dart` doivent être ceux du SDK du
  # projet : avec fvm, on met le SDK épinglé en tête de PATH. Sans ça, un vieux `dart` système
  # (celui de /usr/local/bin) casse tout silencieusement. Sans `dart` (autre langage), rien ne change.
  sdk_path

  FEATURE="$1"
  if [ -n "$FEATURE" ]; then
    # GAUNTLET_FEATURES_ROOT : relocalise .claude/features (tests du gauntlet sans écrire dans le projet).
    FEATURE_DIR="${GAUNTLET_FEATURES_ROOT:-$PROJECT_ROOT/.claude/features}/$FEATURE"
    # Couche (profils *_data / *_presentation, étapes 3 et 4 en deux moitiés parallèles) : sorties à part,
    # deux gauntlets tournent en même temps sur le même package sans écraser le rapport de l'autre.
    LAYER="${GAUNTLET_LAYER:-}"
    case "$LAYER" in ""|data|presentation) ;; *) die "couche inconnue : $LAYER (data|presentation)" ;; esac
    GAUNTLET_OUT="$FEATURE_DIR/.gauntlet${LAYER:+/$LAYER}"
    mkdir -p "$GAUNTLET_OUT"
    # Mode et package : pipeline.json (écrit par l'orchestrateur) > variables d'environnement > config.
    #   create : la feature EST le package, tout le package est dans le périmètre.
    #   extend : la feature ajoute à un package existant, le périmètre = fichiers/lignes modifiés depuis base.
    MODE="${GAUNTLET_MODE:-$(pipeline_get .mode)}"; MODE="${MODE:-create}"
    # Gabarit (S|M|L, choisi au cadrage) : allège les étapes de jugement (QA sur une plateforme en S),
    # jamais les gates d'intégrité (compilation, suite verte, gel, deps, error_handling).
    SIZE="${GAUNTLET_SIZE:-$(pipeline_get .size)}"; SIZE="${SIZE:-M}"
    # Base du diff : pipeline.json > config. Une feature peut partir d'une autre branche que base_branch.
    local pipeline_base; pipeline_base="$(pipeline_get .base)"
    [ -n "$pipeline_base" ] && BASE_BRANCH="$pipeline_base"
    PKG_REL="${GAUNTLET_PACKAGE:-$(pipeline_get .package)}"
    [ -n "$PKG_REL" ] || PKG_REL="$(cfg package_path 'features/{name}' | sed "s/{name}/$FEATURE/g")"
    PKG_REL="${PKG_REL%/}"
    PKG_DIR="$PROJECT_ROOT/$PKG_REL"
    [ -d "$PKG_DIR" ] || die "package introuvable : $PKG_DIR"
    stack_init "$PKG_DIR"; sdk_path
    PKG_NAME="$(pkg_name_of "$PKG_DIR")"
    scope_init
  fi
}

# ---------------------------------------------------------------------------
# Langage du package (ADR 0011, scripts/stack.sh, stacks/<langage>/)
# ---------------------------------------------------------------------------
# Ce qui est propre à un langage (commandes, marqueurs, dossiers, fichiers générés) vient de
# stacks/<langage>/stack.ini, la config du projet primant clé par clé ; les checks propres au langage, de
# stacks/<langage>/checks.sh (stack_load_checks). Les langages lus sont ceux de ce checkout : un worktree de
# ~/.claude se teste avec les siens.
GAUNTLET_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_SH="$GAUNTLET_LIB_DIR/../stack.sh"
export CLAUDE_STACKS_DIR="${CLAUDE_STACKS_DIR:-$(cd "$GAUNTLET_LIB_DIR/../../stacks" 2>/dev/null && pwd)}"
# Clés lues d'un coup par stack_init ; une autre clé passe par stack_val, qui interroge stack.sh.
STACK_KEYS="extensions manifests package_manifest src_dirs test_dirs layer.data generated.exclude tool_files flutter dart"
STACK=""; STACK_DIR=""; STACK_VALS=""
# stack_sh <args…> — stack.sh, avec la config que lit le gauntlet (GAUNTLET_CFG compris)
stack_sh() { STACK_CFG="${CFG_FILE:-}" bash "$STACK_SH" "$@"; }
# stack_init <chemin> — STACK, STACK_DIR et les valeurs du langage de <chemin> ; FLUTTER, DART, fichiers générés.
# Aucun langage reconnu : STACK vide, les checks propres à un langage sont non applicables.
stack_init() {
  local k
  STACK="$(stack_sh detect "$1" 2>/dev/null)" || STACK=""
  STACK_DIR="${STACK:+$CLAUDE_STACKS_DIR/$STACK}"
  if [ -n "$STACK" ]; then
    # stack.sh vals : une ligne par clé, vide comprise ; paste les remet en face de leur clé.
    # shellcheck disable=SC2086
    STACK_VALS="$(paste <(for k in $STACK_KEYS; do printf '%s\n' "$k"; done) <(stack_sh vals "$1" $STACK_KEYS))"
  else
    STACK_VALS=""
  fi
  FLUTTER="$(stack_val flutter)"
  DART="$(stack_val dart)"
  LAYER_DATA_DIRS="$(stack_list layer.data | tr '\n' ' ')"
  # Exported for the Python and Dart tools of the gauntlet (dup_check, spec_lint), which skip the same files.
  GENERATED_ERE="$(generated_ere)"; export GAUNTLET_GENERATED_ERE="$GENERATED_ERE"
}
# lang_dir <dossier> — <dossier> s'il a un langage (un marqueur en remontant) ; sinon le package le plus proche
# sous lui (app dont les packages vivent dans features/, sans pubspec.yaml à sa racine) ; sinon <dossier>.
lang_dir() {
  stack_sh detect "$1" >/dev/null 2>&1 && { printf '%s' "$1"; return; }
  local m f
  for m in $(bash "$STACK_SH" markers); do
    f="$(find "$1" -maxdepth 4 -name "$m" -not -path '*/.git/*' -not -path '*/build/*' -not -path '*/.dart_tool/*' 2>/dev/null \
         | awk '{ print gsub("/", "/"), $0 }' | sort -n | head -1 | cut -d' ' -f2-)"
    [ -n "$f" ] && { dirname "$f"; return; }
  done
  printf '%s' "$1"
}
# stack_val <clé> — valeur pour le langage courant (config du projet, sinon stack.ini) ; vide sans langage
stack_val() {
  [ -n "$STACK" ] || return 0
  case " $STACK_KEYS " in
    *" $1 "*) printf '%s\n' "$STACK_VALS" | awk -F'\t' -v k="$1" '$1 == k { sub(/^[^\t]*\t/, ""); print; exit }' ;;
    *) stack_sh get "$1" "${PKG_DIR:-$APP_ROOT}" 2>/dev/null ;;
  esac
}
# stack_list <clé> — une valeur par ligne (séparateur virgule), vides ignorés
stack_list() { stack_val "$1" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$'; }
# stack_ext_ere — les extensions du langage en ERE ancrée sur la fin : \.(dart)$ ; rien ne correspond sans langage
stack_ext_ere() {
  local alts; alts="$(stack_list extensions | sed 's/^\.//; s/[].[^$+(){}|\\]/\\&/g' | paste -sd '|' -)"
  if [ -n "$alts" ]; then printf '\\.(%s)$' "$alts"; else printf '^$a'; fi
}
# stack_includes — les extensions du langage en options --include de grep (--include=*.dart …)
stack_includes() { stack_list extensions | sed 's/^/--include=*/'; }
# stack_dirs — dossiers du code puis des tests, relatifs au package (lib test pour Flutter)
stack_dirs() { { stack_list src_dirs; stack_list test_dirs; } | tr '\n' ' '; }
# stack_check_known <nom> — un langage au moins a un check_<nom> (stacks/*/checks*.sh)
stack_check_known() { grep -qsE "^check_${1}\(\)" "$CLAUDE_STACKS_DIR"/*/checks*.sh; }
# stack_load_checks — les checks du langage courant, sourcés après les génériques : un check_<nom> du langage
# remplace le générique du même nom. Un check qu'un autre langage a et pas celui-ci est non applicable
# (run_checks le dit, il n'est pas vert en silence).
stack_load_checks() {
  [ -n "$STACK_DIR" ] && [ -f "$STACK_DIR/checks.sh" ] || return 0
  # shellcheck source=/dev/null
  source "$STACK_DIR/checks.sh"
}
# is_package_dir <dossier> — le dossier porte le marqueur d'un langage connu (pubspec.yaml, build.gradle.kts…)
STACK_MARKERS=""
is_package_dir() {
  local m
  [ -n "$STACK_MARKERS" ] || STACK_MARKERS="$(bash "$STACK_SH" markers | tr '\n' ' ')"
  for m in $STACK_MARKERS; do [ -e "$1/$m" ] && return 0; done
  return 1
}
# pkg_name_of <dossier> — le nom du package : `name:` de son pubspec.yaml s'il en a un, sinon le nom du dossier
pkg_name_of() {
  local n=""
  [ -f "$1/pubspec.yaml" ] && n="$(sed -n "s/^name:[[:space:]]*['\"]\{0,1\}\([A-Za-z0-9_]*\)['\"]\{0,1\}.*/\1/p" "$1/pubspec.yaml" | head -1)"
  printf '%s' "${n:-$(basename "$1")}"
}

# sdk_path — le SDK du projet en tête de PATH : exécutables pub, puis SDK épinglé par fvm (rien hors fvm)
sdk_path() {
  case ":$PATH:" in *":$HOME/.pub-cache/bin:"*) ;; *) export PATH="$HOME/.pub-cache/bin:$PATH" ;; esac
  local fv; fv="$(fvm_pinned_version)"
  [ -n "$fv" ] && [ -d "$HOME/fvm/versions/$fv/bin" ] && export PATH="$HOME/fvm/versions/$fv/bin:$PATH"
  return 0
}
# fvmrc_path — le .fvmrc que fvm lit depuis APP_ROOT (APP_ROOT ou un parent jusqu'à PROJECT_ROOT), vide sinon.
fvmrc_path() {
  local d="$APP_ROOT"
  while :; do
    [ -f "$d/.fvmrc" ] && { printf '%s' "$d/.fvmrc"; return 0; }
    [ "$d" = "$PROJECT_ROOT" ] || [ "$d" = / ] && return 1
    d="$(dirname "$d")"
  done
}
# fvm_pinned_version — la version Flutter épinglée par ce .fvmrc (vide hors fvm ou sans .fvmrc).
fvm_pinned_version() {
  [[ "$DART" == fvm* ]] || return 0
  local rc; rc="$(fvmrc_path)" || return 0
  jq -r '.flutter // empty' "$rc" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Git, submodules compris
# ---------------------------------------------------------------------------
# Un package peut vivre dans un submodule (flutter_app/dskit) : le repo parent n'en voit que le gitlink.
# Les helpers ci-dessous lancent git dans le bon repo et rendent des chemins relatifs à PROJECT_ROOT.
# submodules — chemins des submodules (relatifs à PROJECT_ROOT), un par ligne.
submodules() {
  [ -f "$PROJECT_ROOT/.gitmodules" ] || return 0
  git -C "$PROJECT_ROOT" config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}'
}
# submodule_of <chemin> — le submodule qui contient <chemin> (relatif à PROJECT_ROOT), vide sinon.
submodule_of() {
  local p="${1%/}" s best=""
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    case "$p/" in "$s"/*) [ ${#s} -gt ${#best} ] && best="$s" ;; esac
  done < <(submodules)
  printf '%s' "$best"
}
# sub_rev <submodule> <rev> — <rev> traduit pour le submodule : un commit du submodule tel quel, sinon le
# gitlink que le commit <rev> du parent enregistre. Absent (submodule ajouté après <rev>) : l'arbre vide.
sub_rev() {
  local sub="$1" rev="$2" r
  if git -C "$PROJECT_ROOT/$sub" cat-file -e "$rev^{commit}" 2>/dev/null; then printf '%s' "$rev"; return; fi
  r="$(git -C "$PROJECT_ROOT" rev-parse -q --verify "$rev:$sub" 2>/dev/null)"
  printf '%s' "${r:-4b825dc642cb6eb9a060e54bf8d69288fbee4904}"
}
# git_sites <rev> <chemin> — où lancer git pour couvrir <chemin>, un site par repo, champs séparés par \036 :
# repo, préfixe (chemin du submodule + /, vide pour le parent), rev traduite, chemin dans ce repo, puis les
# exclusions (gitlinks des submodules, pour le parent). <chemin> dans un submodule → ce submodule seul ;
# sinon le parent et chaque submodule initialisé sous <chemin>.
git_sites() {
  local rev="$1" path="${2%/}" sub s excl=()
  [ -n "$path" ] || path=.
  sub="$(submodule_of "$path")"
  if [ -n "$sub" ]; then
    local inner="${path#"$sub"}"; inner="${inner#/}"
    printf '%s\036%s\036%s\036%s\n' "$PROJECT_ROOT/$sub" "$sub/" "$(sub_rev "$sub" "$rev")" "${inner:-.}"
    return
  fi
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    [ "$path" = . ] || case "$s/" in "$path"/*) ;; *) continue ;; esac
    excl+=(":(exclude)$s")
    [ -e "$PROJECT_ROOT/$s/.git" ] || continue
    printf '%s\036%s\036%s\036%s\n' "$PROJECT_ROOT/$s" "$s/" "$(sub_rev "$s" "$rev")" .
  done < <(submodules)
  local IFS=$'\036'
  printf '%s\n' "$PROJECT_ROOT"$'\036'$'\036'"$rev"$'\036'"$path${excl[*]+${excl[*]:+$'\036'}${excl[*]}}"  # ${…+} : tableau vide sous set -u en bash 3.2
}
# Chaque helper lit un site : SITE_DIR, SITE_PRE, SITE_REV et le tableau SITE_PATHS (chemin + exclusions).
_read_site() {
  local IFS=$'\036' f i
  read -r -a f || return 1
  SITE_DIR="${f[0]}"; SITE_PRE="${f[1]}"; SITE_REV="${f[2]}"
  # Pas de "${f[@]:3}" : sous bash 3.2 (macOS), avec un IFS non standard, la tranche colle les éléments en un seul.
  SITE_PATHS=(); for ((i = 3; i < ${#f[@]}; i++)); do SITE_PATHS+=("${f[i]}"); done
}
# diff_names <rev> <chemin> [args…] — fichiers modifiés depuis <rev> (arbre de travail compris).
diff_names() {
  local rev="$1" path="$2"; shift 2
  while _read_site; do
    git -C "$SITE_DIR" diff --name-only --ignore-submodules=all "$@" "$SITE_REV" -- "${SITE_PATHS[@]}" | sed "s#^#$SITE_PRE#"
  done < <(git_sites "$rev" "$path")
}
# diff_name_status <rev> <chemin> — comme diff_names, en --name-status.
diff_name_status() {
  while _read_site; do
    git -C "$SITE_DIR" diff --name-status --ignore-submodules=all "$SITE_REV" -- "${SITE_PATHS[@]}" \
      | awk -v pre="$SITE_PRE" 'BEGIN { FS=OFS="\t" } { for (i=2; i<=NF; i++) $i=pre $i; print }'
  done < <(git_sites "$1" "$2")
}
# diff_u0 <rev> <chemin> [args…] — patch -U0 depuis <rev>, chemins `b/…` relatifs à PROJECT_ROOT.
diff_u0() {
  local rev="$1" path="$2"; shift 2
  while _read_site; do
    git -C "$SITE_DIR" diff -U0 --ignore-submodules=all --src-prefix="a/$SITE_PRE" --dst-prefix="b/$SITE_PRE" "$@" "$SITE_REV" -- "${SITE_PATHS[@]}"
  done < <(git_sites "$rev" "$path")
}
# untracked <chemin> — fichiers non suivis (hors .gitignore), submodules compris.
untracked() {
  while _read_site; do
    git -C "$SITE_DIR" ls-files --others --exclude-standard -- "${SITE_PATHS[@]}" | sed "s#^#$SITE_PRE#"
  done < <(git_sites HEAD "$1")
}
# show_at <rev> <fichier> — contenu de <fichier> (relatif à PROJECT_ROOT) au commit <rev>.
show_at() {
  local sub; sub="$(submodule_of "$2")"
  if [ -n "$sub" ]; then git -C "$PROJECT_ROOT/$sub" show "$(sub_rev "$sub" "$1"):${2#"$sub"/}" 2>/dev/null
  else git -C "$PROJECT_ROOT" show "$1:$2" 2>/dev/null; fi
}
# git_in <chemin> <args…> — git lancé dans le repo qui contient <chemin> (le submodule s'il y en a un).
git_in() { local sub; sub="$(submodule_of "$1")"; shift; git -C "$PROJECT_ROOT${sub:+/$sub}" "$@"; }

# ---------------------------------------------------------------------------
# Périmètre modifié (mode extend)
# ---------------------------------------------------------------------------
# SCOPE_FILE : une ligne par élément, relative à PROJECT_ROOT —
#   "chemin"        fichier entier (ajouté ou non suivi)
#   "chemin:ligne"  ligne ajoutée dans un fichier modifié
# SCOPE_ALL=1 en mode create : tout le package est dans le périmètre.
# Package dans un submodule : le diff tourne dans le submodule, depuis le gitlink que la base enregistre.
#
# Périmètre de la passe (PASS_SCOPE_FILE, PASS_SCOPE_ALL) : les gates qui jugent le travail de l'étape en
# cours (stub_check : les nouveaux contrats sont des stubs ; red_check : les nouveaux tests sont rouges)
# ne doivent pas rejuger le code d'une passe déjà validée. Lors d'un rejeu (amendement de spec, nouvelle
# passe sur une feature déjà implémentée), pipeline.json → pass_base (ou GAUNTLET_PASS_BASE) donne le commit
# où la passe en cours a commencé : ces gates ne voient que ce qui a changé depuis. Sans pass_base, le
# périmètre de la passe est celui de la feature.
scope_init() {
  SCOPE_FILE="$GAUNTLET_OUT/scope.txt"
  PASS_SCOPE_FILE="$SCOPE_FILE"
  if [ "$MODE" != extend ]; then SCOPE_ALL=1; : > "$SCOPE_FILE"
  else SCOPE_ALL=0; scope_compute "$(merge_base)" > "$SCOPE_FILE"; fi
  PASS_SCOPE_ALL="$SCOPE_ALL"
  PASS_BASE="${GAUNTLET_PASS_BASE:-$(pipeline_get .pass_base)}"
  if [ -n "$PASS_BASE" ]; then
    git -C "$PROJECT_ROOT" rev-parse -q --verify "$PASS_BASE^{commit}" >/dev/null || die "pass_base introuvable : $PASS_BASE"
    PASS_SCOPE_FILE="$GAUNTLET_OUT/scope_pass.txt"; PASS_SCOPE_ALL=0
    scope_compute "$PASS_BASE" > "$PASS_SCOPE_FILE"
  fi
  if [ -n "${LAYER:-}" ]; then
    layer_scope "$SCOPE_FILE" "$SCOPE_ALL"; SCOPE_ALL=0
    [ "$PASS_SCOPE_FILE" != "$SCOPE_FILE" ] && layer_scope "$PASS_SCOPE_FILE" "$PASS_SCOPE_ALL"
    PASS_SCOPE_ALL=0
  fi
}

# Couches d'une moitié (étapes 3 et 4 en parallèle). data = data, domain et injection, lib et test ;
# presentation = tout le reste du package (presentation, barrel, test/step, .feature, tests générés).
# Chemins relatifs au package.
# Les dossiers de la couche data viennent du langage (stack.ini → layer.data, posés par stack_init).
LAYER_DATA_DIRS=""
# in_layer <couche> <chemin relatif au package>
in_layer() {
  local d
  for d in $LAYER_DATA_DIRS; do
    # shellcheck disable=SC2254
    case "$2" in $d/*) [ "$1" = data ]; return ;; esac
  done
  [ "$1" = presentation ]
}
# layer_files <dossier>… — fichiers .dart de la couche courante sous ces dossiers, relatifs au package
layer_files() {
  local f
  (cd "$PKG_DIR" && find "$@" -name '*.dart' 2>/dev/null) | sort | while IFS= read -r f; do
    in_layer "$LAYER" "$f" && printf '%s\n' "$f"
  done
}
# layer_scope <fichier de périmètre> <tout ?> — restreint le périmètre à la couche courante. Un périmètre
# « package entier » (create) devient la liste des fichiers de la couche ; un périmètre extend garde ses
# entrées dans la couche. Les checks filtrés au périmètre (format, marqueurs, error_handling, deps,
# red_check…) ne jugent alors que la moitié de l'agent, pas les fichiers que l'autre écrit en même temps.
layer_scope() {
  local file="$1" all="$2" tmp l; tmp="$(mktemp)"
  if [ "$all" = 1 ]; then layer_files lib test | drop_generated | sed "s#^#$PKG_REL/#" > "$tmp"
  else
    while IFS= read -r l; do
      [[ "$l" == "$PKG_REL/"* ]] || continue
      in_layer "$LAYER" "${l#$PKG_REL/}" && printf '%s\n' "$l"
    done < "$file" > "$tmp"
  fi
  mv "$tmp" "$file"
}
# scope_compute <base> — le périmètre du package depuis <base>, au format de SCOPE_FILE.
scope_compute() {
  local base="$1"
  {
    diff_names "$base" "$PKG_REL" --diff-filter=A
    untracked "$PKG_REL"
    diff_u0 "$base" "$PKG_REL" --diff-filter=M \
      | awk '/^\+\+\+ b\//{f=substr($0,7)} /^@@/{split($3,a,","); s=substr(a[1],2); n=(a[2]==""?1:a[2]); for(i=0;i<n;i++) print f":"(s+i)}' \
      | drop_format_only "$base"
  } | drop_generated | sort -u
}
# drop_format_only <base> — stdin « fichier:ligne » (relatif à PROJECT_ROOT) → sans les lignes d'un fichier
# .dart qui ne changent que par le format depuis <base> (dart format : ligne recoupée, recollée, réindentée,
# virgule finale ; format_only.py compare token par token). Sans ça, un `dart format` sur un fichier entier
# fait entrer du code non touché dans le périmètre : couverture et métriques rouges, re-gels « hygiene ».
# Les autres entrées passent telles quelles. Écrit le nombre de lignes écartées dans format_lines.count.
# GAUNTLET_KEEP_FORMAT_LINES=1 : rien n'est écarté (conventions de /fix, qui jugent aussi les lignes réindentées).
drop_format_only() {
  local base="$1" in tmp f
  if [ "${GAUNTLET_KEEP_FORMAT_LINES:-0}" = 1 ]; then cat; echo 0 > "$GAUNTLET_OUT/format_lines.count"; return 0; fi
  in="$(cat)"; tmp="$(mktemp)"
  printf '%s\n' "$in" | grep -E '\.dart:[0-9]+$' | sed -E 's/:[0-9]+$//' | sort -u \
    | while IFS= read -r f; do
        show_at "$base" "$f" > "$tmp" && [ -f "$PROJECT_ROOT/$f" ] || continue
        python3 "$GAUNTLET_ROOT/format_only.py" "$tmp" "$PROJECT_ROOT/$f" | sed "s#^#$f:#"
      done > "$tmp.fmt"
  printf '%s\n' "$in" | grep -v '^$' | grep -vxFf "$tmp.fmt"
  grep -c . "$tmp.fmt" > "$GAUNTLET_OUT/format_lines.count"
  rm -f "$tmp" "$tmp.fmt"
}
# use_pass_scope — à appeler en tête d'un check, après `local SCOPE_FILE SCOPE_ALL` : ce check (et les
# helpers qu'il appelle, portée dynamique de bash) jugent la passe en cours, pas toute la feature.
use_pass_scope() { SCOPE_FILE="$PASS_SCOPE_FILE"; SCOPE_ALL="$PASS_SCOPE_ALL"; }
# with_package <package> <commande…> — runs <commande> (a check or its per-package helper) against another
# package of the workspace, a writes.extra package the feature changed. Package, perimeter and outputs are
# rebound for the duration of the command (bash dynamic scoping): the perimeter is always extend (the feature
# adds to an existing package), restricted to the current layer under GAUNTLET_LAYER, and the outputs go to
# .gauntlet[/<couche>]/packages/<package>/, so the feature package's report is never overwritten.
with_package() {
  local PKG_REL="${1%/}"; shift
  local PKG_DIR="$PROJECT_ROOT/$PKG_REL" MODE=extend PKG_NAME SCOPE_FILE SCOPE_ALL PASS_SCOPE_FILE PASS_SCOPE_ALL PASS_BASE \
        TEST_REPORT TEST_NONE EXTRA_PKG=1
  # One statement: the right-hand side still reads the caller's GAUNTLET_OUT.
  local GAUNTLET_OUT="$GAUNTLET_OUT/packages/$(printf '%s' "$PKG_REL" | tr '/' '%')"
  mkdir -p "$GAUNTLET_OUT"
  PKG_NAME="$(pkg_name_of "$PKG_DIR")"
  scope_init
  "$@"
}
pass_label() { [ -n "${PASS_BASE:-}" ] && printf 'depuis pass_base %s' "${PASS_BASE:0:10}" || printf 'depuis %s' "$BASE_BRANCH"; }
scope_summary() {
  if [ -n "${LAYER:-}" ] && [ "$MODE" != extend ]; then echo "couche $LAYER, $(grep -c . "$SCOPE_FILE") fichier(s) (create)"; return; fi
  [ "$SCOPE_ALL" = 1 ] && echo "package entier (create)" || echo "${LAYER:+couche $LAYER, }$(grep -vc ':' "$SCOPE_FILE") fichier(s) nouveau(x), $(grep -c ':' "$SCOPE_FILE") ligne(s) ajoutée(s) dans $(grep ':' "$SCOPE_FILE" | cut -d: -f1 | sort -u | wc -l | tr -d ' ') fichier(s) modifié(s) (extend)"
}
# in_scope_file <chemin relatif à PROJECT_ROOT> — fichier nouveau ou touché
in_scope_file() { [ -n "$(printf '%s\n' "$1" | drop_generated)" ] || return 1; [ "$SCOPE_ALL" = 1 ] || grep -qxE "$1(:[0-9]+)?" "$SCOPE_FILE" 2>/dev/null || grep -q "^$1:" "$SCOPE_FILE" 2>/dev/null; }
# scope_files <prefix> — fichiers du périmètre, relatifs à <prefix> (ex: "$PKG_REL/"), sources du langage
# seulement (stack.ini → extensions ; en create, sous src_dirs et test_dirs)
scope_files() {
  local prefix="$1" ere; ere="$(stack_ext_ere)"
  # shellcheck disable=SC2046
  if [ "$SCOPE_ALL" = 1 ]; then (cd "$PROJECT_ROOT/$prefix" && find $(stack_dirs) -type f 2>/dev/null | grep -E "$ere") | drop_generated
  else cut -d: -f1 "$SCOPE_FILE" | grep -E "$ere" | sort -u | sed "s#^$prefix##"; fi
}
# filter_scope_lines <prefix> — stdin "chemin:ligne:…" (chemins relatifs à <prefix>) → garde les hits du périmètre.
# Un fichier généré n'est jamais dans le périmètre, en create comme en extend.
filter_scope_lines() {
  local prefix="$1"
  if [ "$SCOPE_ALL" = 1 ]; then drop_generated; return; fi
  awk -v prefix="$prefix" -v scope="$SCOPE_FILE" '
    BEGIN { while ((getline l < scope) > 0) { if (index(l, ":")) lines[l]=1; else files[l]=1 } }
    { split($0, a, ":"); f=prefix a[1]; if ((f in files) || ((f":"a[2]) in lines)) print }'
}
# filter_scope_files <prefix> — stdin "chemin…" → garde les lignes dont le fichier est dans le périmètre
filter_scope_files() {
  local prefix="$1"
  if [ "$SCOPE_ALL" = 1 ]; then drop_generated; return; fi
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

# ---------------------------------------------------------------------------
# Fichiers générés
# ---------------------------------------------------------------------------
# Aucun check ne juge une sortie de build_runner, de gen-l10n ou d'un autre générateur : un lint dans un
# .g.dart n'est pas corrigeable par l'agent (il serait écrasé à la prochaine génération). Le motif vient de
# feature_pipeline.md → generated.exclude (globs, `*` traverse les `/`, un glob sans `/` vise le nom du
# fichier) ; `none` n'exclut rien. Seuls generated_fresh (génération à jour et commitée) et la compilation
# (`error •` de l'analyse, qui ne passe pas par le périmètre) les regardent encore. Défaut : celui du langage
# (stack.ini → generated.exclude).
generated_globs() {
  local v; v="$(stack_val generated.exclude)"
  [ -n "$v" ] || v="$(cfg generated.exclude)"
  [ "$v" = none ] && return 0
  printf '%s' "$v" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$'
}
# generated_ere — les globs en une ERE ancrée sur la fin du chemin : (^|/)(alt1|alt2…)$ ; vide si aucun.
generated_ere() {
  local alts
  alts="$(generated_globs | sed -e 's#^\*\*/##' -e 's/[].[^$+(){}|\\]/\\&/g' -e 's/\*\*/*/g' -e 's/\*/.*/g' -e 's#?#[^/]#g' | paste -sd '|' -)"
  [ -n "$alts" ] && printf '(^|/)(%s)$' "$alts"
}
# drop_generated — filtre stdin : lignes « chemin », « chemin:ligne » ou « chemin:ligne:texte » (grep -n)
# sans celles dont le chemin est un fichier généré. only_generated : l'inverse.
drop_generated() { _generated_filter 0; }
only_generated() { _generated_filter 1; }
_generated_filter() {
  if [ -z "${GENERATED_ERE:-}" ]; then [ "$1" = 1 ] || cat; return 0; fi
  # ENVIRON, pas -v : awk interpréterait les \. de l'ERE comme des séquences d'échappement.
  RE="$GENERATED_ERE" KEEP="$1" awk '{ p = $0; i = index(p, ":"); if (i) p = substr(p, 1, i - 1)
    if ((p ~ ENVIRON["RE"]) == (ENVIRON["KEEP"] == 1)) print }'
}
# generated_dcl_exclude — les mêmes globs pour --exclude de dart_code_linter : {/**.g.dart,/**/x/**,…}
generated_dcl_exclude() {
  local g out=""
  while IFS= read -r g; do
    g="${g#\*\*/}"
    case "$g" in \**) g="/**${g#\*}" ;; *) g="/**/$g" ;; esac
    out="$out${out:+,}$g"
  done < <(generated_globs)
  printf '{%s}' "${out:-/**/.no-generated-files}"
}

# pipeline_get <clé jq> — lit .claude/features/<feature>/pipeline.json
pipeline_get() { [ -f "$FEATURE_DIR/pipeline.json" ] && jq -r "$1 // empty" "$FEATURE_DIR/pipeline.json"; }

# writes_extra — zones d'écriture hors du package, une par ligne : celles du projet (feature_pipeline.md →
# writes.extra : router, l10n…, permanentes) puis celles de la feature (pipeline.json → writes_extra, posées
# par `pipeline.sh extra`, qui disparaissent avec elle). Une zone ouverte pour une seule feature ne va jamais
# dans la config du projet.
writes_extra() { { cfg_list writes.extra; pipeline_get '.writes_extra[]?'; } | grep -v '^$' | awk '!seen[$0]++'; }

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
  # The closest of the remote and local merge bases: a base branch with unpushed commits must not
  # drag them into the feature's perimeter.
  local remote local_base
  remote="$(git -C "$PROJECT_ROOT" merge-base HEAD "origin/$BASE_BRANCH" 2>/dev/null)"
  local_base="$(git -C "$PROJECT_ROOT" merge-base HEAD "$BASE_BRANCH" 2>/dev/null)"
  if [ -n "$remote" ] && [ -n "$local_base" ]; then
    if git -C "$PROJECT_ROOT" merge-base --is-ancestor "$remote" "$local_base"; then
      printf '%s\n' "$local_base"
    else
      printf '%s\n' "$remote"
    fi
  elif [ -n "$remote$local_base" ]; then
    printf '%s\n' "$remote$local_base"
  else
    git -C "$PROJECT_ROOT" rev-list --max-parents=0 HEAD | tail -1
  fi
}

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
    local failed="" skipped="" passed="" na="" timings="" spec name mode rc t0 dt fast_failed=0
    printf 'gauntlet %s — feature %s — package %s — périmètre : %s — %s\n' "$label" "$FEATURE" "$PKG_REL" "$(scope_summary)" "$(date '+%Y-%m-%d %H:%M:%S')"
    for spec in "$@"; do
      name="${spec%%:*}"; mode=""; [[ "$spec" == *:* ]] && mode="${spec#*:}"
      section "$name${mode:+ ($mode)}"
      if is_expensive "$name" && [ "$fast_failed" = 1 ]; then
        info "sauté : un check rapide a échoué"; skipped="$skipped $name"; continue
      fi
      # Check propre à un langage, sans version pour celui du package : dit, compté à part, jamais « passé ».
      if ! declare -F "check_$name" >/dev/null; then
        printf '[N/A]  %s : non applicable à %s (aucune version de ce check pour ce langage)\n' "$name" "${STACK:-ce package, langage non reconnu}"
        na="$na $name"; continue
      fi
      t0=$SECONDS; "check_$name" "$mode"; rc=$?; dt=$((SECONDS-t0))
      if [ "$rc" -eq 0 ]; then ok "$name (${dt}s)"; passed="$passed $name"
      else ko "$name (${dt}s)"; failed="$failed $name"; is_expensive "$name" || fast_failed=1; fi
      timings="$timings $name=$dt"
    done
    section "résumé $label"
    [ -n "$passed" ]  && printf '  passés  :%s\n' "$passed"
    [ -n "$failed" ]  && printf '  échoués :%s\n' "$failed"
    [ -n "$skipped" ] && printf '  sautés  :%s\n' "$skipped"
    [ -n "$na" ]      && printf '  non applicables à %s :%s\n' "${STACK:-ce langage}" "$na"
    jq -n --arg profile "$label" --arg feature "$FEATURE" --arg stack "$STACK" --arg na "$na" \
          --argjson ok "$([ -z "$failed" ] && echo true || echo false)" \
          --arg passed "$passed" --arg failed "$failed" --arg skipped "$skipped" --arg timings "$timings" \
          '{profile:$profile, feature:$feature, ok:$ok, date:(now|todate),
            passed:($passed|split(" ")|map(select(.!=""))),
            failed:($failed|split(" ")|map(select(.!=""))),
            skipped:($skipped|split(" ")|map(select(.!=""))),
            stack:$stack, not_applicable:($na|split(" ")|map(select(.!=""))),
            seconds:($timings|split(" ")|map(select(.!="")|split("=")|{(.[0]):(.[1]|tonumber)})|add // {})}' > "$json"
  } 2>&1 | tee -a "$log"
  [ "$(jq -r '.ok' "$json" 2>/dev/null)" = true ]
}
