#!/usr/bin/env bash
# run_all.sh — rejoue toutes les repros du gauntlet. GAUNTLET=<gauntlet.sh> pour tester une autre version.
cd "$(dirname "$0")" || exit 2
rc=0
for t in test_*.sh; do echo "== $t"; bash "$t" || rc=1; done
exit $rc
