#!/usr/bin/env bash
# transit.sh — registre des vidéos déposées dans le bucket de transit, pour savoir quoi supprimer.
#
#   transit.sh add <projet> <bucket> <file_id> <url> <fichier local>   note un dépôt (date du jour)
#   transit.sh ok <file_id>                                           l'agent marketing a confirmé le téléchargement
#   transit.sh due [jours=7]                                          à supprimer : confirmées, ou déposées il y a plus de N jours
#   transit.sh gone <file_id>                                         retiré du registre après suppression dans le bucket
#   transit.sh list                                                   tout le registre
#
# Le dépôt et la suppression eux-mêmes passent par le connecteur Appwrite du projet
# (storage_create_file, storage_delete_file) : ce script ne touche à aucun serveur.
set -euo pipefail
REG="$HOME/.cache/video-pub/transit.tsv"
mkdir -p "$(dirname "$REG")"; touch "$REG"
cmd="${1:-}"

case "$cmd" in
  add)
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%F)" "$2" "$3" "$4" "$5" "attente" "$6" >> "$REG"; echo "noté : $4"
    ;;
  ok)
    python3 - "$REG" "$2" <<'PY'
import sys
reg, fid = sys.argv[1], sys.argv[2]
rows = [l.rstrip('\n').split('\t') for l in open(reg) if l.strip()]
n = 0
for r in rows:
    if r[3] == fid: r[5] = 'confirmé'; n += 1
open(reg, 'w').write(''.join('\t'.join(r) + '\n' for r in rows))
print(f'{fid} : confirmé' if n else f'{fid} : absent du registre')
PY
    ;;
  due)
    python3 - "$REG" "${2:-7}" <<'PY'
import sys, datetime
reg, days = sys.argv[1], int(sys.argv[2])
today = datetime.date.today()
for l in open(reg):
    if not l.strip(): continue
    d, proj, bucket, fid, url, state, local = (l.rstrip('\n').split('\t') + [''] * 7)[:7]
    age = (today - datetime.date.fromisoformat(d)).days
    if state == 'confirmé' or age > days:
        print(f'{proj}\t{bucket}\t{fid}\t{state}, {age} j')
PY
    ;;
  gone)
    python3 - "$REG" "$2" <<'PY'
import sys
reg, fid = sys.argv[1], sys.argv[2]
rows = [l for l in open(reg) if l.strip() and l.split('\t')[3] != fid]
open(reg, 'w').write(''.join(rows)); print(f'{fid} : retiré du registre')
PY
    ;;
  list) column -t -s $'\t' "$REG" 2>/dev/null || cat "$REG" ;;
  *) sed -n 2,10p "$0"; exit 2 ;;
esac
