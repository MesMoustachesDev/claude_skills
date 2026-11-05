#!/usr/bin/env bash
# watchdog.sh — veille des features /feature en cours, hors de toute session.
#
#   watchdog.sh register <worktree> <nom>   la feature est suivie (étape 0 de /feature, création ou reprise)
#   watchdog.sh unregister <nom>            plus suivie (fin de l'étape 9, worktree supprimé)
#   watchdog.sh scan                        pour chaque feature suivie : pipeline.sh watchdog <nom> --notify
#   watchdog.sh list                        features suivies et leur verdict, sans notifier
#   watchdog.sh install [minutes]           LaunchAgent macOS qui lance `scan` toutes les N minutes (défaut 15)
#   watchdog.sh uninstall                   retire le LaunchAgent
#
# Deux veilleurs se complètent. Dans la session de l'orchestrateur, un CronCreate relance `/feature <nom>
# watchdog` quand la session est inactive : c'est lui qui relance la suite. Celui-ci tourne même session
# fermée ou bloquée sur une permission (un cron de session ne se déclenche que session inactive) : il ne
# relance rien, il prévient Thibault (notify.sh) de ce qui est attendu. Liste suivie :
# ~/.claude/state/feature_watchdog.tsv (worktree<TAB>nom). Une feature terminée ou un worktree disparu en sort.
set -u
LIST="$HOME/.claude/state/feature_watchdog.tsv"
PIPE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pipeline.sh"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/watchdog.sh"
LABEL=com.claude.feature-watchdog
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
mkdir -p "$(dirname "$LIST")"; touch "$LIST"

drop() { local tmp; tmp="$(mktemp)"; awk -F'\t' -v n="$1" '$2 != n' "$LIST" > "$tmp"; mv "$tmp" "$LIST"; }

each() {  # each <args pour pipeline.sh watchdog…> — verdict de chaque feature suivie
  local wt name v
  while IFS=$'\t' read -r wt name; do
    [ -n "$name" ] || continue
    if [ ! -f "$wt/.claude/features/$name/pipeline.json" ]; then drop "$name"; echo "$name : worktree ou pipeline.json disparu, retiré"; continue; fi
    v="$(cd "$wt" && bash "$PIPE" watchdog "$name" --json "$@" 2>&1)"
    printf '%s\t%s\n' "$name" "$(jq -r '"\(.verdict) — \(.detail)" + (if .notified then " [notifié]" else "" end)' <<<"$v" 2>/dev/null || echo "erreur : $v")"
    [ "$(jq -r .verdict <<<"$v" 2>/dev/null)" = done ] && drop "$name"
  done < <(cat "$LIST")
  return 0
}

case "${1:-}" in
  register)
    [ -d "${2:-}" ] && [ -n "${3:-}" ] || { echo "usage : watchdog.sh register <worktree> <nom>" >&2; exit 2; }
    drop "$3"; printf '%s\t%s\n' "$(cd "$2" && pwd -P)" "$3" >> "$LIST"; echo "suivie : $3 ($2)"
    [ -f "$PLIST" ] || echo "LaunchAgent absent : la veille hors session ne tourne pas (watchdog.sh install)" ;;
  unregister) [ -n "${2:-}" ] || exit 2; drop "$2"; echo "plus suivie : $2" ;;
  scan) each --notify ;;
  list) each ;;
  install)
    min="${2:-15}"; mkdir -p "$(dirname "$PLIST")"
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$SELF</string><string>scan</string></array>
  <key>StartInterval</key><integer>$((min * 60))</integer>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string></dict>
  <key>StandardOutPath</key><string>$HOME/.claude/state/feature_watchdog.log</string>
  <key>StandardErrorPath</key><string>$HOME/.claude/state/feature_watchdog.log</string>
</dict></plist>
EOF
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
    launchctl bootstrap "gui/$(id -u)" "$PLIST" && echo "LaunchAgent $LABEL : scan toutes les $min min" ;;
  uninstall) launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null; rm -f "$PLIST"; echo "LaunchAgent retiré" ;;
  *) sed -n '2,17p' "${BASH_SOURCE[0]}"; [ "${1:-}" = -h ] || [ "${1:-}" = --help ]; exit $? ;;
esac
