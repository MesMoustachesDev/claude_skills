#!/usr/bin/env bash
# review-restrict-writes.sh — PreToolUse (Edit|Write|MultiEdit|NotebookEdit) des agents review-*.
# Une revue ne modifie jamais le code relu : les agents n'écrivent que dans le dossier de la revue
# (~/.cache/gauntlet/review/<slug>/ : leurs remarques, et pour la QA ses flows Maestro).
# Sortie : exit 0 = autorisé ; exit 2 + stderr = refusé, la raison est montrée à l'agent.
set -u
input="$(cat)"
path="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")"
[ -n "$path" ] || exit 0
root="$HOME/.cache/gauntlet/review/"
case "$path" in
  "$root"*)
    case "$path" in *"/../"*|*"/.."|*"/./"*) ;; *) exit 0 ;; esac ;;
esac
{
  echo "review-restrict-writes : écriture refusée — $path"
  echo "Une revue ne touche pas au code relu. Tu n'écris que dans ton dossier de revue : $root<slug>/"
  echo "(findings_<rôle>.json, et pour la QA maestro/*.yaml). Un défaut se rapporte, il ne se corrige pas ici."
} >&2
exit 2
