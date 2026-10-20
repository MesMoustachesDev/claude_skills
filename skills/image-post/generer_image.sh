#!/usr/bin/env bash
# Génère une image LinkedIn via le webhook n8n « Image LinkedIn ».
#
# Usage : generer_image.sh <fichier_scene.txt> [style] [nom] [format] [photo_base]
#   fichier_scene.txt : la scène, écrite à partir du post (en anglais de préférence)
#   style             : une section de styles.md, à côté de ce script (défaut : fusain)
#   nom               : nom du fichier généré (défaut : date-heure)
#   format            : ratio Gemini, ex. 4:5, 1:1, 16:9 (défaut : 4:5)
#   photo_base        : la photo envoyée en « Image 1 », celle qui porte le visage
#                       (défaut : references/IMG-20260802-WA0040.jpg, la seule de face, nette, sans casquette)
#
# Image 1 = photo_base, puis les autres images de linkedin/references/ (Image 2, 3…).
# SEULE_BASE=1 : n'envoie que photo_base (pour décliner une image déjà validée sans toucher au visage).
# L'image générée arrive dans linkedin/generees/, à côté d'une copie de la scène et du style.
# Config : N8N_IMAGE_WEBHOOK dans linkedin/.env
set -euo pipefail
shopt -s nullglob

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
DIR="$HOME/Dropbox/MesMoustachesDev/linkedin"
# shellcheck disable=SC1091
source "$DIR/.env"
: "${N8N_IMAGE_WEBHOOK:?N8N_IMAGE_WEBHOOK manquant dans $DIR/.env}"

SCENE_FILE="${1:?Usage : generer_image.sh <fichier_scene.txt> [style] [nom] [format] [photo_base]}"
STYLE="${2:-fusain}"
NAME="${3:-$(date +%Y%m%d-%H%M%S)}"
RATIO="${4:-4:5}"
BASE="${5:-$DIR/references/IMG-20260802-WA0040.jpg}"
[ -f "$BASE" ] || { echo "Photo de base introuvable : $BASE" >&2; exit 1; }

section() {
  awk -v title="## $1" '$0 == title { found = 1; next } /^## / { found = 0 } found' "$SKILL_DIR/styles.md"
}

STYLE_TEXT="$(section "$STYLE")"
if [ -z "$STYLE_TEXT" ]; then
  echo "Style inconnu : $STYLE. Styles dispo :" >&2
  grep '^## ' "$SKILL_DIR/styles.md" | sed 's/^## /  /' | grep -v '^  identite$' >&2
  exit 1
fi
FULL_STYLE="$STYLE_TEXT

$(section identite)"

refs=(-F "ref=@$BASE")
[ "${SEULE_BASE:-0}" = 1 ] || for f in "$DIR"/references/*.jpg "$DIR"/references/*.jpeg "$DIR"/references/*.png "$DIR"/references/*.webp; do
  [ "$f" -ef "$BASE" ] && continue
  refs+=(-F "ref=@$f")
done
if [ ${#refs[@]} -eq 0 ]; then
  echo "Aucune image de référence" >&2
  exit 1
fi

mkdir -p "$DIR/generees"
OUT="$DIR/generees/$NAME.png"

curl -sS --fail-with-body --max-time 240 -X POST "$N8N_IMAGE_WEBHOOK" \
  -F "prompt=<$SCENE_FILE" \
  --form-string "style=$FULL_STYLE" \
  --form-string "file_name=$NAME" \
  --form-string "aspect_ratio=$RATIO" \
  "${refs[@]}" \
  -o "$OUT"

# Gemini renvoie parfois du JPEG : on corrige l'extension selon le vrai format
case "$(file -b --mime-type "$OUT")" in
  image/jpeg) mv "$OUT" "${OUT%.png}.jpg"; OUT="${OUT%.png}.jpg" ;;
  image/webp) mv "$OUT" "${OUT%.png}.webp"; OUT="${OUT%.png}.webp" ;;
esac

{ cat "$SCENE_FILE"; printf '\n\n--- style : %s ---\n%s\n\n--- image 1 : %s ---\n' "$STYLE" "$FULL_STYLE" "$(basename "$BASE")"; } > "$DIR/generees/$NAME.prompt.txt"
echo "$OUT"
