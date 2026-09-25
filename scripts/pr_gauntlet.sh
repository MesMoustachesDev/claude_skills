#!/usr/bin/env bash
# pr_gauntlet.sh — fait courir le gauntlet à une branche, sans toucher à l'arbre de travail.
#
# Usage : pr_gauntlet.sh <branche> [--base <branche>] [--mutation] [--keep] [--out <dir>]
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

branch="${1:-}"; shift || true
[ -n "$branch" ] || { echo "usage: pr_gauntlet.sh <branche> [--base <b>] [--mutation] [--keep] [--out <dir>]" >&2; exit 2; }
base=""; mutation=0; keep=0; out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) base="$2"; shift 2 ;;
    --mutation) mutation=1; shift ;;
    --keep) keep=1; shift ;;
    --out) out="$2"; shift 2 ;;
    *) echo "option inconnue : $1" >&2; exit 2 ;;
  esac
done

GAUNTLET="$HOME/.claude/scripts/gauntlet.sh"
GAUNTLET_ROOT="$HOME/.claude/scripts/gauntlet"
PROJECT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "pas dans un repo git" >&2; exit 2; }
slug="$(printf '%s' "$branch" | sed 's#^origin/##; s#[^A-Za-z0-9_]#_#g')"
out="${out:-$HOME/.cache/gauntlet/pr/$slug}"; rm -rf "$out"; mkdir -p "$out"
report="$out/report.md"

# --- config : celle du projet, sinon le template global ----------------------------------------
cfg_file="$PROJECT/.claude/rules/feature_pipeline.md"
[ -f "$cfg_file" ] || cfg_file="$HOME/.claude/commands/templates/flutter/feature_pipeline.md"
cfg() { awk '/^```ini/{f=1;next} /^```/{f=0} f' "$cfg_file" | grep -E "^[[:space:]]*$1[[:space:]]*=" | head -1 | sed 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//'; }
FLUTTER="$(cfg flutter)"; FLUTTER="${FLUTTER:-flutter}"
features_root="$(cfg features_root)"; features_root="${features_root:-features}"
[ -n "$base" ] || base="$(cfg base_branch)"
[ -n "$base" ] || base="$(git -C "$PROJECT" remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p')"
base="${base:-main}"

# --- worktree ----------------------------------------------------------------------------------
git -C "$PROJECT" fetch -q origin "$base" "$branch" 2>/dev/null || true
ref="$branch"; git -C "$PROJECT" rev-parse -q --verify "$ref" >/dev/null 2>&1 || ref="origin/$branch"
git -C "$PROJECT" rev-parse -q --verify "$ref" >/dev/null 2>&1 || { echo "branche introuvable : $branch" >&2; exit 2; }
baseref="origin/$base"; git -C "$PROJECT" rev-parse -q --verify "$baseref" >/dev/null 2>&1 || baseref="$base"
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
if [ ! -f "$wt/.fvmrc" ] && [ -f "$PROJECT/.fvmrc" ]; then cp "$PROJECT/.fvmrc" "$wt/.fvmrc"; fi
mb="$(git -C "$wt" merge-base HEAD "$baseref")"

# --- diff --------------------------------------------------------------------------------------
changed="$(git -C "$wt" diff --name-only "$mb" HEAD)"
stat="$(git -C "$wt" diff --shortstat "$mb" HEAD)"
commits="$(git -C "$wt" log --no-merges --format='%h %s' "$mb"..HEAD)"
ncommits="$(printf '%s\n' "$commits" | grep -c . || true)"

# packages touchés : le pubspec.yaml le plus proche de chaque fichier modifié, sous features_root
pkgs="$(printf '%s\n' "$changed" | grep "^$features_root/" | while IFS= read -r f; do
  d="$(dirname "$f")"
  while [ "$d" != "." ] && [ "$d" != "/" ] && [ ! -f "$wt/$d/pubspec.yaml" ]; do d="$(dirname "$d")"; done
  [ -f "$wt/$d/pubspec.yaml" ] && printf '%s\n' "$d"
done | sort -u)"
outside="$(printf '%s\n' "$changed" | grep -v "^$features_root/" | grep -v '^$' || true)"

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
  if [ -n "$bad" ]; then ko "commits_format : hors convention ($pat) :"; printf '%s\n' "$bad" | sed 's/^/         /'; else ok "commits_format : $ncommits commit(s) conventionnels"; fi
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
  [ -n "$outside" ] && { warn "fichiers hors features/ :"; printf '%s\n' "$outside" | head -15 | sed 's/^/         /'; }
  echo '```'; echo
} | tee -a "$report"

# --- gauntlet par package ------------------------------------------------------------------------
if [ -n "$pkgs" ]; then
  echo "pub get dans le worktree…" >&2
  # shellcheck disable=SC2086
  (cd "$wt" && $FLUTTER pub get >"$out/pub_get.log" 2>&1) || { warn "pub get a échoué (voir $out/pub_get.log) — les checks qui compilent seront rouges"; }
fi
for p in $pkgs; do
  name="$(basename "$p")"
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
