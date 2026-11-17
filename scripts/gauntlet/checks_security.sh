#!/usr/bin/env bash
# checks_security.sh — failles détectables à la lecture du code. Sourcé par gauntlet.sh.
#
# Ces checks sont des heuristiques : ils sortent en [WARN] fichier:ligne et ne font jamais échouer un gate.
# Le reviewer lit les [WARN] du log et tranche.

# server_fetch_redirect — fetch() serveur JS/TS sur une URL non constante qui suit les redirections
# (gauntlet/fetch_redirect.py). Périmètre : fichiers du package touchés par la feature (tout le package en create).
check_server_fetch_redirect() {
  local files out
  if [ "$SCOPE_ALL" = 1 ]; then files="$(git -C "$PROJECT_ROOT" ls-files -- "$PKG_REL" | drop_generated)"
  else files="$(cut -d: -f1 "$SCOPE_FILE" | sort -u)"; fi
  files="$(printf '%s\n' "$files" | grep -E '\.[cm]?[jt]s$')"
  [ -n "$files" ] || { info "aucun fichier JS/TS dans le périmètre"; return "$NA_RC"; }
  # shellcheck disable=SC2086
  out="$(python3 "$GAUNTLET_ROOT/fetch_redirect.py" "$PROJECT_ROOT" $files)"
  [ -n "$out" ] && printf '%s\n' "$out" || info "aucun fetch() serveur qui suit les redirections d'une URL non constante"
  return 0
}
