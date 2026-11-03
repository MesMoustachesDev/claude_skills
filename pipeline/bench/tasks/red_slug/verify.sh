#!/bin/bash
# Réussi : lib/ et spec.md intacts, suite rouge sur le stub, verte sur la bonne implémentation,
# rouge sur chaque mutant (un mutant viole une règle de la spec). Le score dit combien en tombent.
set -uo pipefail
hidden="$TASK_DIR/hidden"
if ! git diff --quiet HEAD -- lib/ spec.md; then echo "lib/ ou spec.md modifiés"; exit 1; fi
ls test/*_test.dart >/dev/null 2>&1 || { echo "aucun test"; exit 1; }
if dart test >/dev/null 2>&1; then echo "vert sur le stub"; exit 1; fi
cp "$hidden/correct.dart" lib/src/slug.dart
if ! dart test >/dev/null 2>&1; then echo "rouge sur la bonne implémentation"; git checkout -q lib/; exit 1; fi
killed=0; total=0; alive=""
for m in "$hidden"/mutant_*.dart; do
  total=$((total + 1)); cp "$m" lib/src/slug.dart
  if dart test >/dev/null 2>&1; then alive="$alive $(basename "$m" .dart | sed 's/^mutant_//')"; else killed=$((killed + 1)); fi
done
git checkout -q lib/
echo "mutants tués : $killed/$total${alive:+ · survivants :$alive}"
[ "$killed" -eq "$total" ]
