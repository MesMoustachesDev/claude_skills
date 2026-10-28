#!/usr/bin/env bash
# notify.sh — prévient Thibault qu'une tâche longue a fini ou a besoin de lui, sans qu'il ait à demander.
#
#   notify.sh [--needs-you] "<titre>" "<message>"
#
# Notification macOS (son « Glass » si fini, « Sosumi » si --needs-you), et une ligne dans
# ~/.claude/state/notifications.log : l'historique se relit avec `bgrun.sh status`. Rien ne sort de la
# machine. Ne fait jamais échouer l'appelant.
needs=0
[ "${1:-}" = --needs-you ] && { needs=1; shift; }
title="${1:-Claude}"; msg="$(printf '%s' "${2:-}" | grep -v '^[[:space:]]*$' | paste -sd '|' - | sed 's/|/ · /g')"
log="$HOME/.claude/state/notifications.log"
mkdir -p "$(dirname "$log")"
printf '%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$([ $needs = 1 ] && echo NEEDS_YOU || echo DONE)" "$title" "$msg" >> "$log"
sound=Glass; [ $needs = 1 ] && { sound=Sosumi; title="⚠️ $title"; }
# osascript : guillemets et antislashs échappés, message coupé (le centre de notifications tronque de toute façon).
esc() { printf '%s' "$1" | head -c 240 | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' '; }
osascript -e "display notification \"$(esc "$msg")\" with title \"$(esc "$title")\" sound name \"$sound\"" >/dev/null 2>&1 || true
exit 0
