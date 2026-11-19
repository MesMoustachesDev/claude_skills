#!/usr/bin/env bash
# review-restrict-writes.sh — PreToolUse (Edit|Write|MultiEdit|NotebookEdit|Bash|mcp__serena__.*) des agents review-*.
# Une revue ne modifie jamais le code relu : les agents n'écrivent que dans le dossier de la revue
# (~/.cache/gauntlet/review/<slug>/ : leurs remarques, et pour la QA ses flows Maestro).
# Serena (ADR 0018) : les outils de lecture seulement, et seulement si le serveur sert le worktree relu (son
# chemin figure dans le prompt de l'agent) ; personne n'écrit sous .serena/, Bash compris.
# Sortie : exit 0 = autorisé ; exit 2 + stderr = refusé, la raison est montrée à l'agent.
set -u
input="$(cat)"
tool="$(jq -r '.tool_name // empty' <<<"$input")"
GAUNTLET_ROOT="${PIPELINE_GAUNTLET_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts/gauntlet" && pwd)}"
refuse() { echo "review-restrict-writes : $1" >&2; exit 2; }

case "$tool" in
  mcp__serena__*)
    source "$GAUNTLET_ROOT/serena_guard.sh"
    source "$GAUNTLET_ROOT/lib.sh"
    [ "$(serena_kind "$tool")" = read ] \
      || refuse "outil Serena refusé ($tool). Une revue lit seulement : $SERENA_READ_TOOLS."
    served="$(serena_served "$(jq -r '.cwd // empty' <<<"$input")")"
    [ -n "$served" ] || refuse "Serena ne sert aucun worktree connu. Cherche les usages avec grep."
    t="$(hook_agent_transcript "$input")"
    { [ -n "$t" ] && head -c 400000 "$t" 2>/dev/null | grep -qF "${served#/private}"; } \
      || refuse "Serena sert $served, qui n'est pas le worktree de ta revue. N'utilise pas Serena ici : grep pour les usages, et dis-le dans tes remarques."
    exit 0 ;;
  Bash)
    source "$GAUNTLET_ROOT/serena_guard.sh"
    while IFS= read -r f; do
      [ -n "$f" ] && in_serena_dir "$f" && refuse "écriture sous .serena/ refusée ($f) : c'est la config de Serena, réécrite par serena.sh."
    done < <(jq -r '.tool_input.command // empty' <<<"$input" \
               | python3 "$GAUNTLET_ROOT/bash_write_targets.py" "$(jq -r '.cwd // empty' <<<"$input")")
    exit 0 ;;
esac

path="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")"
[ -n "$path" ] || exit 0
root="$HOME/.cache/gauntlet/review/"
case "$path" in
  "$root"*)
    case "$path" in *"/../"*|*"/.."|*"/./"*|*/.serena/*) ;; *) exit 0 ;; esac ;;
esac
{
  echo "review-restrict-writes : écriture refusée — $path"
  echo "Une revue ne touche pas au code relu. Tu n'écris que dans ton dossier de revue : $root<slug>/"
  echo "(findings_<rôle>.json, et pour la QA maestro/*.yaml). Un défaut se rapporte, il ne se corrige pas ici."
} >&2
exit 2
