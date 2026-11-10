#!/usr/bin/env bash
# worktree_untracked.sh — copie dans un worktree les fichiers gitignorés dont le build et les tests ont
# besoin (.env, configs Firebase, local.properties…), depuis le checkout principal d'où il a été créé.
#
#   worktree_untracked.sh <worktree> [--dry-run]
#   worktree_untracked.sh --patterns <checkout>   la liste en vigueur, un glob par ligne (rien si « none »)
#
# Checkout principal : le premier de `git worktree list`. Fichiers candidats : les fichiers ignorés du
# checkout principal (git ls-files --others --ignored) qui correspondent à worktree.copy_untracked
# (feature_pipeline.md du checkout principal, globs git séparés par des virgules ; défaut ci-dessous).
# Seul ce qui manque dans le worktree est copié : un fichier déjà là n'est jamais écrasé.
# Jamais copiés, même s'ils correspondent : keystores et secrets de signature (SIGNING_DENY).
# Sortie : une ligne par fichier (copié | à copier | refusé), puis « résumé : … ». Exit 2 sur erreur d'usage.
set -u
DEFAULT='**/.env, **/.env.*, **/*.env, **/.ci.env, **/local.properties, **/google-services.json, **/GoogleService-Info.plist, **/firebase_options*.dart, **/firebase_app_id_file.json, **/.fvmrc'
SIGNING_DENY='*.jks *.keystore key.properties *.p8 *.p12 *.pem *.cer *.der *.mobileprovision *.provisionprofile AuthKey*'

# copy_list <checkout> — worktree.copy_untracked de sa config, sinon le défaut
copy_list() {
  local cfg="$1/.claude/rules/feature_pipeline.md" l
  l="$( [ -f "$cfg" ] && awk '/^```ini/{f=1;next} /^```/{f=0} f' "$cfg" | grep -E '^[[:space:]]*worktree\.copy_untracked[[:space:]]*=' \
    | head -1 | sed 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//')"
  printf '%s' "${l:-$DEFAULT}"
}
if [ "${1:-}" = --patterns ]; then
  [ -d "${2:-}" ] || { echo "usage : worktree_untracked.sh --patterns <checkout>" >&2; exit 2; }
  list="$(copy_list "$2")"; [ "$list" = none ] && exit 0
  printf '%s\n' "$list" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$'
  exit 0
fi

wt="${1:-}"; dry=0; [ "${2:-}" = --dry-run ] && dry=1
[ -d "$wt" ] || { echo "usage : worktree_untracked.sh <worktree> [--dry-run]" >&2; exit 2; }
wt="$(cd "$wt" && pwd -P)"
main="$(git -C "$wt" worktree list --porcelain | awk '/^worktree /{print substr($0, 10); exit}')"
main="$(cd "$main" && pwd -P)"
[ "$main" != "$wt" ] || { echo "résumé : $wt est le checkout principal, rien à copier"; exit 0; }

list="$(copy_list "$main")"
[ "$list" = none ] && { echo "résumé : worktree.copy_untracked = none"; exit 0; }
specs=(); while IFS= read -r g; do [ -n "$g" ] && specs+=(":(glob)$g"); done < <(printf '%s\n' "$list" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

copied=0 present=0 denied=0
while IFS= read -r f; do
  # Dossiers (dépôts imbriqués), autres worktrees, sorties de build : jamais.
  case "$f" in */|.claude/worktrees/*|*/.claude/worktrees/*|*/build/*|build/*|*/.dart_tool/*|*/ephemeral/*|*/Pods/*) continue ;; esac
  base="${f##*/}"
  for d in $SIGNING_DENY; do
    # shellcheck disable=SC2254
    case "$base" in $d) echo "refusé    $f (secret de signature)"; denied=$((denied+1)); continue 2 ;; esac
  done
  if [ -e "$wt/$f" ]; then present=$((present+1)); continue; fi
  if [ "$dry" = 1 ]; then echo "à copier  $f"
  else mkdir -p "$wt/$(dirname "$f")" && cp -p "$main/$f" "$wt/$f" && echo "copié     $f"; fi
  copied=$((copied+1))
done < <(git -C "$main" ls-files --others --ignored --exclude-standard -- "${specs[@]}" 2>/dev/null)

verb="copié(s)"; [ "$dry" = 1 ] && verb="à copier"
echo "résumé : $copied $verb depuis $main, $present déjà présent(s), $denied refusé(s)"
