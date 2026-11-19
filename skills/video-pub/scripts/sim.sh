#!/usr/bin/env bash
# sim.sh — un simulateur iOS à soi pour filmer l'app, sans toucher à ceux des autres sessions.
#
#   sim.sh new <simulateur source (nom ou UDID)> <langue, ex. fr>   clone, démarre, langue, barre d'état 9:41 ; affiche l'UDID
#   sim.sh rec-start <udid> <fichier.mov>                            lance l'enregistrement d'écran en fond
#   sim.sh rec-stop <fichier.mov>                                    l'arrête proprement (le .mov est écrit à l'arrêt)
#   sim.sh off <udid>                                                éteint le simulateur
#   sim.sh watch <udid iPhone> [langue] [type de montre]              crée une Apple Watch, l'appaire à cet iPhone
#                                                                    (le tien, créé par `new`), attend la connexion ; affiche l'UDID
#
# Ne clone que depuis un simulateur éteint (Shutdown) : on ne démarre ni ne modifie jamais un
# simulateur qu'une autre session utilise.
set -euo pipefail
cmd="${1:-}"

statusbar() { xcrun simctl status_bar "$1" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3; }

case "$cmd" in
  new)
    src="${2:?simulateur source}"; lang="${3:-fr}"
    state=$(xcrun simctl list devices | grep -F "$src" | head -1 || true)
    [ -n "$state" ] || { echo "simulateur introuvable : $src"; exit 1; }
    echo "$state" | grep -q Shutdown || { echo "refusé : $src n'est pas éteint (une autre session l'utilise peut-être). Choisis un simulateur éteint."; exit 1; }
    name="$(echo "$state" | sed -E 's/ \([0-9A-F-]{36}\).*//; s/^ +//') · video-pub-$(date +%H%M)"
    udid=$(xcrun simctl clone "$src" "$name")
    xcrun simctl boot "$udid"
    xcrun simctl spawn "$udid" defaults write -g AppleLanguages -array "$lang"
    loc=$(echo "$lang" | tr '[:lower:]' '[:upper:]'); xcrun simctl spawn "$udid" defaults write -g AppleLocale "${lang}_${loc}"
    xcrun simctl shutdown "$udid"; xcrun simctl boot "$udid"   # la langue n'est prise qu'au démarrage
    statusbar "$udid"
    echo "$udid"
    ;;
  rec-start)
    udid="${2:?udid}"; out="${3:?fichier.mov}"
    xcrun simctl io "$udid" recordVideo --codec h264 --force "$out" > "$out.log" 2>&1 &
    echo $! > "$out.pid"; sleep 2; cat "$out.log"
    ;;
  rec-stop)
    out="${2:?fichier.mov}"
    kill -INT "$(cat "$out.pid")"; sleep 3; tail -2 "$out.log"
    ;;
  off)
    xcrun simctl shutdown "${2:?udid}"; echo "éteint"
    ;;
  watch)
    phone="${2:?udid de ton iPhone}"; lang="${3:-fr}"; wtype="${4:-Apple Watch Series 12 (46mm)}"
    xcrun simctl list devices | grep -F "$phone" | grep -q 'video-pub' \
      || { echo "refusé : $phone n'est pas un simulateur créé par sim.sh new (nom en « · video-pub-… »)."; exit 1; }
    dt=$(xcrun simctl list devicetypes | grep -F "$wtype" | head -1 | sed -E 's/.*\((com\.apple[^)]*)\).*/\1/')
    rt=$(xcrun simctl list runtimes | grep -i watchos | tail -1 | sed -E 's/.* - (com\.apple[^ ]*).*/\1/')
    [ -n "$dt" ] && [ -n "$rt" ] || { echo "type de montre ou runtime watchOS introuvable ($wtype)"; exit 1; }
    watch=$(xcrun simctl create "$wtype · video-pub-$(date +%H%M)" "$dt" "$rt")
    pair=$(xcrun simctl pair "$watch" "$phone")
    xcrun simctl boot "$watch"
    xcrun simctl spawn "$watch" defaults write -g AppleLanguages -array "$lang"
    loc=$(echo "$lang" | tr '[:lower:]' '[:upper:]'); xcrun simctl spawn "$watch" defaults write -g AppleLocale "${lang}_${loc}"
    # Juste après l'appairage, la paire reste « disconnected » : il faut éteindre les deux, puis
    # démarrer l'iPhone avant la montre. La connexion arrive ensuite en une demi-minute environ.
    xcrun simctl shutdown "$watch"; xcrun simctl shutdown "$phone" 2>/dev/null || true
    xcrun simctl boot "$phone"; sleep 8; xcrun simctl boot "$watch"
    statusbar "$phone"
    for _ in $(seq 1 20); do
      xcrun simctl list pairs | grep -F "$pair" | grep -q ', connected' && { echo "$watch"; exit 0; }
      sleep 6
    done
    echo "montre créée ($watch) mais la paire n'est pas connectée après 2 min : relance l'iPhone puis la montre." >&2; exit 1
    ;;
  *) sed -n 2,9p "$0"; exit 2 ;;
esac
