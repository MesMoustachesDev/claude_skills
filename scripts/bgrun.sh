#!/usr/bin/env bash
# bgrun.sh — lance une tâche longue (boucle ralph, eval, build, mutation…) pour que Thibault soit prévenu
# à la fin au lieu de demander « on en est où ? ».
#
#   bgrun.sh run <nom> [--needs-you-if <regex>] -- <commande…>
#       Exécute la commande au premier plan (log dans ~/.claude/state/bg/<nom>.log), puis notifie
#       (notify.sh) : « terminé » ou « échec (code n) », avec les 3 dernières lignes du log. Si la regex
#       --needs-you-if apparaît dans ces lignes, la notification dit qu'il faut Thibault.
#       Depuis une session Claude : Bash avec run_in_background, JAMAIS `nohup … &` — la session est
#       alors réveillée à la fin, et la notification part même si la session est fermée.
#   bgrun.sh status [<nom>]      tâches en cours et terminées (état, durée, dernière ligne), notifications récentes
#   bgrun.sh tail <nom> [n]      dernières lignes du log
set -uo pipefail
DIR="$HOME/.claude/state/bg"
NOTIFY="$(dirname "${BASH_SOURCE[0]}")/notify.sh"
mkdir -p "$DIR"

now() { date '+%Y-%m-%d %H:%M:%S'; }
write_state() { # write_state <nom> <état> [code]
  jq -n --arg n "$1" --arg s "$2" --arg c "${3:-}" --arg cmd "$CMD" --arg cwd "$PWD" --arg start "$START" \
    --arg end "$([ "$2" = running ] || now)" --argjson pid "$$" \
    '{name:$n, state:$s, code:$c, cmd:$cmd, cwd:$cwd, pid:$pid, start:$start, end:$end}' > "$DIR/$1.json"
}

cmd_run() {
  local name="${1:?nom}" needs_re="" code tail_lines title
  shift
  [ "${1:-}" = --needs-you-if ] && { needs_re="$2"; shift 2; }
  [ "${1:-}" = -- ] && shift
  [ $# -gt 0 ] || { echo "usage : bgrun.sh run <nom> [--needs-you-if <regex>] -- <commande…>" >&2; exit 2; }
  CMD="$*"; START="$(now)"
  write_state "$name" running
  echo "[bgrun] $name démarré $START — log : $DIR/$name.log — état : bgrun.sh status $name"
  "$@" > "$DIR/$name.log" 2>&1
  code=$?
  tail_lines="$(grep -v '^[[:space:]]*$' "$DIR/$name.log" | tail -3)"
  if [ "$code" = 0 ]; then write_state "$name" done 0; title="$name : terminé"
  else write_state "$name" failed "$code"; title="$name : échec (code $code)"; fi
  if [ -n "$needs_re" ] && grep -qiE "$needs_re" <<<"$tail_lines"; then
    write_state "$name" needs_you "$code"
    bash "$NOTIFY" --needs-you "$name : il faut toi" "$tail_lines"
  elif [ "$code" = 0 ]; then bash "$NOTIFY" "$title" "$tail_lines"
  else bash "$NOTIFY" --needs-you "$title" "$tail_lines"; fi
  echo "[bgrun] $name fini $(now), code $code"
  printf '%s\n' "$tail_lines"
  return "$code"
}

cmd_status() {
  local f n st pid
  for f in "$DIR"/${1:-*}.json; do
    [ -f "$f" ] || continue
    st="$(jq -r .state "$f")"; pid="$(jq -r .pid "$f")"; n="$(jq -r .name "$f")"
    # Un « running » dont le processus n'existe plus a été tué sans pouvoir l'écrire.
    [ "$st" = running ] && ! kill -0 "$pid" 2>/dev/null && st="interrompu"
    printf '%-28s %-10s début %s%s\n    %s\n' "$n" "$st" "$(jq -r .start "$f")" \
      "$(jq -r 'if .end != "" then " · fin " + .end else "" end' "$f")" \
      "$(grep -v '^[[:space:]]*$' "$DIR/$n.log" 2>/dev/null | tail -1 | cut -c1-150)"
  done
  [ -f "$HOME/.claude/state/notifications.log" ] && { echo; echo "Notifications récentes :"; tail -5 "$HOME/.claude/state/notifications.log" | cut -f1-3 | sed 's/^/  /'; }
}

case "${1:-}" in
  run)    shift; cmd_run "$@" ;;
  status) shift; cmd_status "$@" ;;
  tail)   tail -n "${3:-30}" "$DIR/${2:?nom}.log" ;;
  *)      sed -n '2,15p' "$0"; exit 2 ;;
esac
