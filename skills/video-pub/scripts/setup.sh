#!/usr/bin/env bash
# setup.sh — installe une fois les outils de rendu, hors de tout repo : ~/.cache/video-pub
#   puppeteer-core (pilote le Chrome installé) et ffmpeg-static (encodage H.264).
# Affiche le chemin de ffmpeg. Sans effet si c'est déjà installé.
set -euo pipefail
DIR="$HOME/.cache/video-pub"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || { echo "Google Chrome introuvable ($CHROME) : il sert au rendu (codec H.264 des vidéos)."; exit 1; }
command -v node >/dev/null || { echo "node introuvable"; exit 1; }
mkdir -p "$DIR"
if [ ! -d "$DIR/node_modules/puppeteer-core" ] || [ ! -d "$DIR/node_modules/ffmpeg-static" ]; then
  (cd "$DIR" && [ -f package.json ] || (cd "$DIR" && npm init -y >/dev/null))
  (cd "$DIR" && npm i --silent puppeteer-core@23.11.1 ffmpeg-static@5.2.0)
fi
node -e "console.log(require('$DIR/node_modules/ffmpeg-static'))"
