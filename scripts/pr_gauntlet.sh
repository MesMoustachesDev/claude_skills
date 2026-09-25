#!/usr/bin/env bash
# pr_gauntlet.sh — fait courir le gauntlet à une branche, sans toucher à l'arbre de travail.
#
# Usage : pr_gauntlet.sh <branche | !N | #N | URL> [--base <branche>] [--mutation] [--keep] [--out <dir>] [--install-sdk]
#
# 1. checkout de la branche dans un worktree temporaire, pub get
# 2. checks PR (taille, commits, lock, tests touchés)
# 3. pour chaque package touché : gauntlet.sh pr en mode extend (périmètre = diff vs base)
#    + dedup_candidates (pour le jugement IA de /reviewPR)
# 4. report.md + logs dans --out (défaut ~/.cache/gauntlet/pr/<branche>), exit 1 si un check est rouge
#
# Lu par /reviewPR : les scripts d'abord, le jugement ensuite.
set -u
set -o pipefail
# Aucun outil ne doit pouvoir poser une question (fvm "install it now?", pub "continue?") : stdin fermé,
# une commande qui attend une réponse échoue tout de suite au lieu de bloquer la revue.
exec </dev/null

branch="${1:-}"; shift || true
[ -n "$branch" ] || { echo "usage: pr_gauntlet.sh <branche | !N | #N | URL de MR/PR> [--base <b>] [--mutation] [--keep] [--out <dir>]" >&2; exit 2; }
base=""; mutation=0; keep=0; out=""; install_sdk=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="$2"; shift 2 ;;
    --mutation) mutation=1; shift ;;
    --keep) keep=1; shift ;;
    --out) out="$2"; shift 2 ;;
    --install-sdk) install_sdk=1; shift ;;
    *) echo "option inconnue : $1" >&2; exit 2 ;;
  esac
done

GAUNTLET="$HOME/.claude/scripts/gauntlet.sh"
GAUNTLET_ROOT="$HOME/.claude/scripts/gauntlet"
PROJECT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "pas dans un repo git" >&2; exit 2; }
# Le remote n'est pas forcément "origin".
remote="$(git -C "$PROJECT" remote | grep -x origin || git -C "$PROJECT" remote | head -1)"
remote="${remote:-origin}"

# --- !N / #N / URL → branche source (et cible) via glab ou gh ----------------------------------------
mr_base=""
num=""
case "$branch" in
  '!'[0-9]*|'#'[0-9]*) num="${branch#[!#]}" ;;
  [0-9]*) [[ "$branch" =~ ^[0-9]+$ ]] && num="$branch" ;;
  *merge_requests/*|*/pull/*) num="$(printf '%s' "$branch" | grep -oE '[0-9]+$')" ;;
esac
if [ -n "$num" ]; then
  if command -v glab >/dev/null 2>&1 && j="$(cd "$PROJECT" && glab mr view "$num" --output json 2>/dev/null)" && [ -n "$j" ]; then
    branch="$(jq -r .source_branch <<<"$j")"; mr_base="$(jq -r .target_branch <<<"$j")"
    echo "MR !$num → branche $branch (cible $mr_base)" >&2
  elif command -v gh >/dev/null 2>&1 && j="$(cd "$PROJECT" && gh pr view "$num" --json headRefName,baseRefName 2>/dev/null)" && [ -n "$j" ]; then
    branch="$(jq -r .headRefName <<<"$j")"; mr_base="$(jq -r .baseRefName <<<"$j")"
    echo "PR #$num → branche $branch (base $mr_base)" >&2
  else
    echo "impossible de résoudre $branch : glab/gh absent ou MR introuvable" >&2; exit 2
  fi
fi
slug="$(printf '%s' "$branch" | sed 's#^origin/##; s#[^A-Za-z0-9_]#_#g')"
out="${out:-$HOME/.cache/gauntlet/pr/$slug}"; rm -rf "$out"; mkdir -p "$out"
report="$out/report.md"

# --- config : celle du projet, sinon le template global ----------------------------------------
cfg_file="$PROJECT/.claude/rules/feature_pipeline.md"
[ -f "$cfg_file" ] || cfg_file="$HOME/.claude/commands/templates/flutter/feature_pipeline.md"
cfg() { awk '/^```ini/{f=1;next} /^```/{f=0} f' "$cfg_file" | grep -E "^[[:space:]]*$1[[:space:]]*=" | head -1 | sed 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//'; }
FLUTTER="$(cfg flutter)"; FLUTTER="${FLUTTER:-flutter}"
features_root="$(cfg features_root)"; features_root="${features_root:-features}"
# base : option > cible de la MR > config > HEAD du remote
[ -n "$base" ] || base="$mr_base"
[ -n "$base" ] || base="$(cfg base_branch)"
[ -n "$base" ] || base="$(git -C "$PROJECT" remote show "$remote" 2>/dev/null | sed -n 's/.*HEAD branch: //p')"
base="${base:-main}"

# --- worktree ----------------------------------------------------------------------------------
git -C "$PROJECT" fetch -q "$remote" "+refs/heads/$base:refs/remotes/$remote/$base" "+refs/heads/$branch:refs/remotes/$remote/$branch" 2>/dev/null || true
# l'état distant d'abord (c'est lui qu'on review), la branche locale en secours
ref="$remote/$branch"; git -C "$PROJECT" rev-parse -q --verify "$ref" >/dev/null 2>&1 || ref="$branch"
git -C "$PROJECT" rev-parse -q --verify "$ref" >/dev/null 2>&1 || { echo "branche introuvable : $branch (ni $remote/$branch)" >&2; exit 2; }
baseref="$remote/$base"; git -C "$PROJECT" rev-parse -q --verify "$baseref" >/dev/null 2>&1 || baseref="$base"
echo "revue de $ref contre $baseref" >&2
wt="$(mktemp -d)/wt"
git -C "$PROJECT" worktree add -q --detach "$wt" "$ref" || { echo "worktree impossible" >&2; exit 2; }
cleanup() { [ "$keep" = 1 ] && { echo "worktree conservé : $wt"; return; }; git -C "$PROJECT" worktree remove --force "$wt" >/dev/null 2>&1; rm -rf "$(dirname "$wt")"; }
trap cleanup EXIT
# Submodules (un package du workspace peut en être un) : un worktree ne les initialise pas tout seul.
if [ -f "$wt/.gitmodules" ]; then
  echo "submodules…" >&2
  git -C "$wt" submodule update --init --recursive -q 2>"$out/submodules.log" || true
  # Repli : un submodule dont le commit n'est pas sur le remote (pointeur jamais pushé) est copié depuis
  # le checkout principal. Ce n'est pas exactement l'état de la branche, et le rapport le dit.
  git -C "$wt" config --file .gitmodules --get-regexp 'submodule\..*\.path' | awk '{print $2}' | while IFS= read -r sm; do
    # dossier vide (ou seulement .git) = submodule non récupéré ; `git -C` y retomberait sur le parent
    if [ -z "$(find "$wt/$sm" -mindepth 1 -maxdepth 1 -not -name .git 2>/dev/null | head -1)" ] && [ -d "$PROJECT/$sm" ]; then
      rm -rf "$wt/$sm"; cp -R "$PROJECT/$sm" "$wt/$sm"; rm -rf "$wt/$sm/.git"
      printf '[WARN] submodule %s : commit %s introuvable sur son remote — copie du checkout principal (%s)\n' \
        "$sm" "$(git -C "$wt" ls-tree HEAD "$sm" | awk '{print substr($3,1,8)}')" "$(git -C "$PROJECT/$sm" rev-parse --short HEAD 2>/dev/null)" | tee -a "$report" >&2
    fi
  done
fi
# Fichiers non suivis dont les checks ont besoin (.env lu par un générateur…) : liste explicite dans la
# config, vide par défaut. Jamais un keystore : rien dans le profil pr ne signe un binaire.
for f in $(cfg pr.copy_untracked | tr ',' ' '); do
  if [ -e "$PROJECT/$f" ] && [ ! -e "$wt/$f" ]; then mkdir -p "$wt/$(dirname "$f")"; cp -R "$PROJECT/$f" "$wt/$f"; fi
done
# La config projet doit être visible du gauntlet dans le worktree
[ -f "$wt/.claude/rules/feature_pipeline.md" ] || { mkdir -p "$wt/.claude/rules"; cp "$cfg_file" "$wt/.claude/rules/feature_pipeline.md"; }
# .fvmrc est souvent non suivi : sans lui, fvm retombe sur son SDK global (et demande à l'installer).
# On le recopie partout où le checkout principal en a un (racine et chaque package).
while IFS= read -r rc; do
  rel="${rc#$PROJECT/}"; [ -f "$wt/$rel" ] || { mkdir -p "$wt/$(dirname "$rel")"; cp "$rc" "$wt/$rel"; }
done < <(find "$PROJECT" -maxdepth 3 -name .fvmrc -not -path '*/.git/*' -not -path '*/build/*' 2>/dev/null)
mb="$(git -C "$wt" merge-base HEAD "$baseref")"

# --- diff --------------------------------------------------------------------------------------
changed="$(git -C "$wt" diff --name-only "$mb" HEAD)"
stat="$(git -C "$wt" diff --shortstat "$mb" HEAD)"
commits="$(git -C "$wt" log --no-merges --format='%h %s' "$mb"..HEAD)"
ncommits="$(printf '%s\n' "$commits" | grep -c . || true)"

# packages touchés : le pubspec.yaml le plus proche de chaque fichier modifié — package d'un workspace
# (features/x), app dans un sous-dossier (my_center/), ou la racine elle-même (".").
pkg_of() { local d; d="$(dirname "$1")"; while [ "$d" != "." ] && [ "$d" != "/" ] && [ ! -f "$wt/$d/pubspec.yaml" ]; do d="$(dirname "$d")"; done; [ -f "$wt/$d/pubspec.yaml" ] && printf '%s\n' "$d"; }
pkgs="$(printf '%s\n' "$changed" | grep -v '^$' | while IFS= read -r f; do pkg_of "$f"; done | sort -u)"
outside="$(printf '%s\n' "$changed" | grep -v '^$' | while IFS= read -r f; do [ -z "$(pkg_of "$f")" ] && printf '%s\n' "$f"; done || true)"

[ -z "$pkgs" ] && echo "[WARN] aucun package Dart touché (pas de pubspec.yaml au-dessus des fichiers modifiés) : seuls les checks PR tournent" >&2
project_cfg=0; [ "$cfg_file" = "$PROJECT/.claude/rules/feature_pipeline.md" ] && project_cfg=1
{
  printf '# Gauntlet PR — `%s` → `%s`\n\n' "$branch" "$base"
  printf '%s · %s commit(s) · packages touchés : %s\n\n' "$stat" "$ncommits" "$(printf '%s' "$pkgs" | tr '\n' ' ' | sed 's/ $//')"
} > "$report"

# --- checks PR (hors package) --------------------------------------------------------------------
pr_rc=0
ok()   { printf '[OK]   %s\n' "$*"; }
ko()   { printf '[FAIL] %s\n' "$*"; pr_rc=1; }
warn() { printf '[WARN] %s\n' "$*"; }
{
  echo "## Checks PR"; echo; echo '```'
  # taille
  adds="$(git -C "$wt" diff --numstat "$mb" HEAD | awk '{a+=$1; d+=$2} END{print a+0" "d+0}')"
  lines=$(( ${adds% *} + ${adds#* } ))
  max_lines="$(cfg pr.max_lines)"; max_lines="${max_lines:-600}"
  if [ "$lines" -gt "$max_lines" ]; then warn "pr_size : $lines lignes modifiées (> $max_lines) — une PR qu'on ne peut pas relire d'une traite se découpe"; else ok "pr_size : $lines lignes, $(printf '%s\n' "$changed" | grep -c .) fichier(s)"; fi
  # commits
  pat="$(cfg commits.pattern)"; pat="${pat:-^(feat|fix|chore|refactor|test|docs|perf|ci|build|style)(\([a-z0-9_/-]+\))?!?: .+}"
  bad="$(printf '%s\n' "$commits" | grep -v '^$' | awk '{ $1=""; sub(/^ /,""); print }' | grep -vE "$pat" || true)"
  wip="$(printf '%s\n' "$commits" | grep -iE ' (wip|fixup!|squash!|tmp|temp)\b' || true)"
  if [ -n "$bad" ]; then
    if [ "$project_cfg" = 1 ] && [ -n "$(cfg commits.pattern)" ]; then ko "commits_format : hors convention ($pat) :"; else warn "commits_format : hors convention conventional-commits (fixer commits.pattern dans .claude/rules/feature_pipeline.md pour rendre bloquant) :"; fi
    printf '%s\n' "$bad" | sed 's/^/         /'
  else ok "commits_format : $ncommits commit(s) conventionnels"; fi
  [ -n "$wip" ] && { ko "commits_wip : commits de travail à squasher :"; printf '%s\n' "$wip" | sed 's/^/         /'; }
  # lock
  if printf '%s\n' "$changed" | grep -qE '(^|/)pubspec\.yaml$'; then
    if printf '%s\n' "$changed" | grep -qE '(^|/)pubspec\.lock$'; then ok "pubspec_lock : lock mis à jour avec les pubspec"; else warn "pubspec_lock : un pubspec.yaml change sans pubspec.lock — pub get non commité ?"; fi
  fi
  # tests touchés (par package)
  for p in $pkgs; do
    if printf '%s\n' "$changed" | grep -q "^$p/lib/" && ! printf '%s\n' "$changed" | grep -q "^$p/test/"; then
      ko "tests_touched : $p — lib/ modifié sans aucun test modifié ou ajouté"
    fi
  done
  # hors packages
  [ -n "$outside" ] && { warn "fichiers hors de tout package Dart :"; printf '%s\n' "$outside" | head -15 | sed 's/^/         /'; }
  echo '```'; echo
} | tee -a "$report"

# --- gauntlet par package ------------------------------------------------------------------------
# Le SDK que la branche épingle (.fvmrc) doit être installé : fvm le demanderait, stdin est fermé, on
# préfère le dire. --install-sdk l'installe (long, réseau).
sdk_ok=1
if [[ "$FLUTTER" == fvm* ]]; then
  for rc in $(find "$wt" -maxdepth 3 -name .fvmrc -not -path '*/.git/*' 2>/dev/null); do
    v="$(jq -r '.flutter // empty' "$rc" 2>/dev/null)"; [ -n "$v" ] || continue
    if [ ! -d "$HOME/fvm/versions/$v" ]; then
      if [ "$install_sdk" = 1 ]; then echo "fvm install $v…" >&2; fvm install "$v" >"$out/fvm_install.log" 2>&1 || { ko "sdk : fvm install $v a échoué (voir $out/fvm_install.log)" | tee -a "$report"; sdk_ok=0; }
      else ko "sdk : la branche épingle Flutter $v (${rc#$wt/}), non installé — \`fvm install $v\` ou relancer avec --install-sdk ; checks qui compilent sautés" | tee -a "$report"; sdk_ok=0; fi
    fi
  done
fi
if [ -n "$pkgs" ] && [ "$sdk_ok" = 1 ]; then
  echo "pub get dans le worktree…" >&2
  if grep -qE '^workspace:' "$wt/pubspec.yaml" 2>/dev/null; then
    # shellcheck disable=SC2086
    (cd "$wt" && $FLUTTER pub get >"$out/pub_get.log" 2>&1) || { warn "pub get a échoué (voir $out/pub_get.log) — les checks qui compilent seront rouges"; }
  else
    for p in $pkgs; do
      # shellcheck disable=SC2086
      (cd "$wt/$p" && $FLUTTER pub get >>"$out/pub_get.log" 2>&1) || { warn "pub get a échoué dans $p (voir $out/pub_get.log)"; }
    done
  fi
fi
[ "$sdk_ok" = 1 ] || pkgs=""
for p in $pkgs; do
  name="$(basename "$p")"; [ "$p" = "." ] && name="$(basename "$PROJECT")"
  echo "## Package \`$p\`" >> "$report"; echo >> "$report"
  export GAUNTLET_MODE=extend GAUNTLET_PACKAGE="$p" GAUNTLET_FEATURES_ROOT="$out/features" GAUNTLET_CFG="$wt/.claude/rules/feature_pipeline.md"
  profile=pr; [ "$mutation" = 1 ] && profile=pr_mutation
  (cd "$wt" && "$GAUNTLET" "$profile" "$name") > "$out/$name.log" 2>&1; rc=$?
  [ "$rc" = 0 ] || pr_rc=1
  (cd "$wt" && "$GAUNTLET" dedup_candidates "$name") >/dev/null 2>&1 || true
  {
    echo '```'
    grep -E '^\[(OK|FAIL|WARN)\]|^   ✗|^\[WARN\]' "$out/$name.log" | grep -vE '^\[(OK|FAIL)\] +[a-z_]+$' | head -80
    echo; grep -E '^  (passés|échoués|sautés)' "$out/$name.log"
    echo '```'
    cand="$out/features/$name/dedup_candidates.json"
    [ -f "$cand" ] && printf '\nCandidats roue réinventée (à juger) : `%s` — %s paire(s), %s widget(s) vs %s composant(s) du DS\n' "$cand" "$(jq .pairs "$cand")" "$(jq '.widgets|length' "$cand")" "$(jq '.design_catalog|length' "$cand")"
    echo; echo "Log complet : \`$out/$name.log\`"; echo
  } >> "$report"
done

{
  echo "## Verdict scripts"; echo
  if [ "$pr_rc" = 0 ]; then echo "✅ tout est vert — reste le jugement (architecture, spec, lisibilité, roue réinventée par la responsabilité)."
  else echo "❌ des checks sont rouges — à corriger avant relecture humaine ; le détail est au-dessus."; fi
} >> "$report"
echo; echo "rapport : $report"
exit $pr_rc
