#!/usr/bin/env bash
# claude-home-guard.sh — PreToolUse (Edit|Write|MultiEdit|NotebookEdit|Bash), toutes les sessions.
# Personne n'écrit directement dans le checkout principal de ~/.claude : toutes les sessions le lisent,
# et une modification laissée là finit non commitée, mêlée à celles des autres (5 novembre : 29 fichiers
# de sept sessions). Refuse l'écriture d'un fichier versionné, ou versionnable, sous ~/.claude ; laisse
# passer ce que git ignore (état, transcripts, plans, résultats), les worktrees ~/.claude-wt/*, et ce
# qu'écrivent les scripts (rule_add.py, claude_change.sh, learn.py) : ils ne passent pas par un outil.
# Bash : les cibles que voit scripts/gauntlet/bash_write_targets.py (redirection, sed -i, tee, cp, mv, rm).
set -u
input="$(cat)"
home="$HOME/.claude"
tool="$(jq -r '.tool_name // empty' <<<"$input")"
cwd="$(jq -r '.cwd // empty' <<<"$input")"

case "$tool" in
  Edit|Write|MultiEdit|NotebookEdit)
    targets="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")" ;;
  Bash)
    targets="$(jq -r '.tool_input.command // empty' <<<"$input" \
      | python3 "$home/scripts/gauntlet/bash_write_targets.py" "${cwd:-$PWD}" 2>/dev/null)" ;;
  *) exit 0 ;;
esac
[ -n "$targets" ] || exit 0

blocked=""
while IFS= read -r t; do
  [ -n "$t" ] || continue
  case "$t" in "$home"/*) ;; *) continue ;; esac
  rel="${t#"$home"/}"
  # Ignoré par git (état, activité, transcripts, plans, leçons…) : ce n'est pas la config.
  git -C "$home" check-ignore -q --no-index -- "$rel" 2>/dev/null && continue
  blocked="$blocked $rel"
done <<<"$targets"
[ -n "$blocked" ] || exit 0

reason="~/.claude est lu par toutes les sessions : on n'y écrit pas directement (refusé :$blocked). \
Une règle d'une ligne (learn, réponse de Thibault) : python3 ~/.claude/scripts/rule_add.py <fichier> \"<ligne>\" --after \"<ancre>\" (elle est commitée aussitôt). \
Tout autre changement : bash ~/.claude/scripts/claude_change.sh start <nom>, écris et commite dans ~/.claude-wt/<nom>, puis claude_change.sh land <nom>."
jq -n --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
