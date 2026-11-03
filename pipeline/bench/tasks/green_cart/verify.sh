#!/bin/bash
# Réussi : tests intacts (même contenu qu'au commit) et `dart test` vert.
set -uo pipefail
if ! git diff --quiet HEAD -- test/; then echo "tests modifiés"; exit 1; fi
if [ -n "$(git ls-files --others --exclude-standard test/)" ]; then echo "tests ajoutés"; exit 1; fi
out=$(dart test 2>&1); code=$?
echo "$out" | grep -E '[0-9]+:[0-9]+ \+' | tail -1 | sed -E 's/^.*[0-9]+:[0-9]+ //'
exit $code
