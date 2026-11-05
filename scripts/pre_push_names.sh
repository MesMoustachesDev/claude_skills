#!/usr/bin/env bash
# pre_push_names.sh — hook pre-push de ~/.claude (lien dans .git/hooks/pre-push) : refuse de pousser des
# lignes ajoutées ou un message de commit qui contiennent un nom de ~/.claude-local/clients.txt (repo public).
set -u
list="$HOME/.claude-local/clients.txt"
[ -f "$list" ] || { echo "pre-push : $list absent, noms non vérifiés" >&2; exit 0; }
pat="$(grep -v '^#' "$list" | grep -v '^$' | sed 's/[.[\*^$()+?{|]/\\&/g' | paste -sd'|' -)"
[ -n "$pat" ] || exit 0
rc=0
while read -r _ local_sha _ remote_sha; do
  [ "$local_sha" = 0000000000000000000000000000000000000000 ] && continue
  range="$local_sha"; [ "$remote_sha" != 0000000000000000000000000000000000000000 ] && range="$remote_sha..$local_sha"
  # Les lignes ajoutées et les messages des commits poussés : ce qui est déjà public n'est pas rejugé.
  hits="$(git log -p --format='commit %h %s%n%B' "$range" -- . ':!skills/ecrire-linkedin/commentaires.md' \
    | grep -E '^(\+[^+]|commit |[^-+@ d])' | grep -iE "$pat" | grep -v '^commit ' | head -20)"
  [ -n "$hits" ] && { echo "pre-push refusé : ces lignes nomment un client (repo public, CLAUDE.md) :" >&2; printf '%s\n' "$hits" | cut -c1-160 >&2; rc=1; }
done
exit $rc
