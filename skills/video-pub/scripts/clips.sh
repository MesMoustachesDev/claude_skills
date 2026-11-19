#!/usr/bin/env bash
# clips.sh — repérer et découper les plans d'un enregistrement d'écran.
#
#   clips.sh sheet <video> <début s> <durée s> <images/s> <sortie.jpg>   planche horodatée (temps absolus dans la vidéo)
#   clips.sh cut <video> <début s> <durée s> <sortie.mp4>                un plan, 30 i/s, 600 px de large, une image clé par image
#   clips.sh join <sortie.mp4> <plan1.mp4> <plan2.mp4> [...]             met des plans bout à bout
#   clips.sh still <video> <temps s> <recadrage w:h:x:y|-> <sortie.jpg>  une image fixe, recadrée ou non
#
# Une image clé par image (-g 1) : la composition se cale sur n'importe quelle image sans flou.
# Les enregistrements du simulateur ont un débit d'images variable : on coupe avec -ss/-t, pas avec trim.
set -euo pipefail
FF=$(node -e "console.log(require(process.env.HOME + '/.cache/video-pub/node_modules/ffmpeg-static'))")
FONT=/System/Library/Fonts/Helvetica.ttc
cmd="${1:-}"

case "$cmd" in
  sheet)
    v="$2"; a="$3"; d="$4"; fps="$5"; out="$6"
    n=$(python3 -c "import math;print(max(1,math.ceil($d*$fps)))"); cols=$(( n < 16 ? n : 16 )); rows=$(( (n + cols - 1) / cols ))
    "$FF" -y -loglevel error -ss "$a" -i "$v" -t "$d" -vf "fps=$fps,scale=150:-1,drawtext=fontfile=$FONT:text='%{eif\:t+$a\:d}.%{eif\:mod((t+$a)*10\,10)\:d}':x=4:y=h-28:fontsize=22:fontcolor=red:box=1:boxcolor=white,tile=${cols}x${rows}" -frames:v 1 "$out"
    echo "$out ($n images, de $a s à $(python3 -c "print($a+$d)") s)"
    ;;
  cut)
    "$FF" -y -loglevel error -ss "$3" -i "$2" -t "$4" -vf "fps=30,scale=600:-2" -c:v libx264 -crf 16 -g 1 -pix_fmt yuv420p -an "$5"
    echo "$5"
    ;;
  join)
    out="$2"; shift 2; lst=$(mktemp -t clipsjoin); for f in "$@"; do echo "file '$(cd "$(dirname "$f")" && pwd)/$(basename "$f")'" >> "$lst"; done
    "$FF" -y -loglevel error -f concat -safe 0 -i "$lst" -c copy "$out"; rm -f "$lst"; echo "$out"
    ;;
  still)
    v="$2"; t="$3"; crop="$4"; out="$5"
    if [ "$crop" = "-" ]; then vf="null"; else vf="crop=$crop"; fi
    "$FF" -y -loglevel error -ss "$t" -i "$v" -frames:v 1 -vf "$vf" -q:v 2 "$out"; echo "$out"
    ;;
  *) sed -n 2,10p "$0"; exit 2 ;;
esac
