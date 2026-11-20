#!/usr/bin/env bash
# hook_log.sh — journal des décisions des hooks (ADR 0019). Sourcé par no-interpreter.sh, les trois
# *-restrict-writes.sh et les gates pipeline-gate.sh et fix-gate.sh. Lu par scripts/hook_journal.py
# (learn.py extract, rapport, evidence).
#
#   hook_log <dossier du run> <hook> <agent> <outil> <cible> <issue> <raison> [étape]
#     Une ligne JSON ajoutée à <dossier du run>/.gauntlet/hooks.jsonl : at, hook, agent, tool, target
#     (tronquée), outcome (deny | ask | red | failed | allow), reason (tronquée), stage (gates). `allow` ne
#     s'écrit que pour une écriture jugée par une zone.
#   hook_run_dir <agent> <cwd> <entrée JSON du hook> [fichier]
#     Le dossier du run de l'agent : .claude/features/<nom> (feature-*), .claude/fixes/<nom> (fix-*), le
#     dossier de la revue (review-*). Rien s'il est introuvable.
#
# Le journal ne bloque jamais : sans dossier de run, ou si l'écriture échoue, rien n'est écrit et le hook
# décide comme avant. Ajout simple (`>>` d'une ligne courte) : pas de verrou.
HOOK_LOG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

hook_log() {
  local dir="${1:-}"
  [ -n "$dir" ] && [ -d "$dir" ] || return 0
  mkdir -p "$dir/.gauntlet" 2>/dev/null || return 0
  jq -cn --arg hook "${2:-}" --arg agent "${3:-}" --arg tool "${4:-}" --arg target "${5:-}" \
    --arg outcome "${6:-}" --arg reason "${7:-}" --arg stage "${8:-}" '
    def cut($n): gsub("\\s+"; " ") | if length > $n then .[0:$n - 1] + "…" else . end;
    {at: (now | todate), hook: $hook, agent: $agent, tool: $tool, target: ($target | cut(200)),
     outcome: $outcome, reason: ($reason | cut(300))}
    + (if $stage != "" then {stage: $stage} else {} end)' \
    >> "$dir/.gauntlet/hooks.jsonl" 2>/dev/null || true
  return 0
}

# _git_named <toplevel> <préfixe de branche> <dossier .claude/…> — nom du run : branche <préfixe><nom>,
# sinon .claude/<dossier>/.current
_git_named() {
  local n
  n="$(git -C "$1" branch --show-current 2>/dev/null | sed -n "s#^$2##p")"
  [ -n "$n" ] || n="$(cat "$1/.claude/$3/.current" 2>/dev/null)"
  printf '%s' "$n"
}

hook_run_dir() {
  local agent="$1" cwd="$2" input="${3:-}" file="${4:-}" top name t d
  case "$agent" in
    feature-*)
      declare -F hook_feature_root >/dev/null || source "$HOOK_LOG_LIB_DIR/lib.sh" 2>/dev/null || return 0
      t=""; [ -n "$input" ] && t="$(hook_agent_transcript "$input" 2>/dev/null)"
      top="$(hook_feature_root "$cwd" "$file" "$t" 2>/dev/null)" || top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
      [ -n "$top" ] || return 0
      name="$(_git_named "$top" feature/ features)"; [ -n "$name" ] || return 0
      d="$top/.claude/features/$name" ;;
    fix-*)
      declare -F hook_worktree_root >/dev/null || source "$HOOK_LOG_LIB_DIR/lib.sh" 2>/dev/null || return 0
      t=""; [ -n "$input" ] && t="$(hook_agent_transcript "$input" 2>/dev/null)"
      top="$(hook_worktree_root fix "$cwd" "$file" "$t" 2>/dev/null)" || top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
      [ -n "$top" ] || return 0
      name="$(_git_named "$top" fix/ fixes)"; [ -n "$name" ] || return 0
      d="$top/.claude/fixes/$name" ;;
    review-*)
      [ -n "$input" ] || return 0
      declare -F hook_agent_transcript >/dev/null || source "$HOOK_LOG_LIB_DIR/lib.sh" 2>/dev/null || return 0
      t="$(hook_agent_transcript "$input" 2>/dev/null)"
      [ -n "$t" ] && [ -f "$t" ] || return 0
      d="$(head -c 400000 "$t" | grep -oE "$HOME/\.cache/gauntlet/review/[A-Za-z0-9_.-]+" | head -1)" ;;
    *) return 0 ;;
  esac
  [ -n "$d" ] && [ -d "$d" ] && printf '%s\n' "$d"
  return 0
}
