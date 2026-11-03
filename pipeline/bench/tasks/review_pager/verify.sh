#!/bin/bash
# Réussi : review.json lisible, et un constat sur chacun des deux défauts plantés (ligne à ±2 près) :
# pageCount (ligne 11) et l'erreur avalée de load (lignes 24-27). Le reste est compté à part.
set -uo pipefail
[ -f review.json ] || { echo "pas de review.json"; exit 1; }
python3 - <<'PY'
import json, sys
try:
    found = json.load(open('review.json'))
    assert isinstance(found, list)
except Exception as e:
    print(f'review.json illisible : {e}'); sys.exit(1)
def near(f, lo, hi):
    return str(f.get('file', '')).endswith('pager.dart') and lo - 2 <= int(f.get('line') or -99) <= hi + 2
bugs = {'pageCount': (11, 11), 'erreur avalée': (24, 27)}
hit = [name for name, (lo, hi) in bugs.items() if any(near(f, lo, hi) for f in found)]
others = len([f for f in found if not any(near(f, lo, hi) for lo, hi in bugs.values())])
print(f"défauts trouvés : {len(hit)}/{len(bugs)} ({', '.join(hit) or 'aucun'}) · autres constats : {others}")
sys.exit(0 if len(hit) == len(bugs) else 1)
PY
