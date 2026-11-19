#!/usr/bin/env bash
# Repro — perte d'écriture sur pipeline.json (point 3 du plan de refacto). pipeline.py, review.py et le hook de gate
# lisaient, modifiaient puis remplaçaient le fichier sans verrou : un `pipeline.sh debt` lancé pendant le gate d'une
# moitié (pipe_set de pipeline-gate.sh) pouvait effacer stages.red_data. Tous passent désormais par
# scripts/statefile.py : flock sur <fichier>.lock, relecture sous le verrou, .tmp unique, os.replace.
source "$(dirname "$0")/fixture.sh"
PIPE="$TESTS_DIR/../../pipeline.sh"; SF="$TESTS_DIR/../../statefile.py"
R="$TMP_ROOT/repo"; mk_repo "$R"; commit "$R" init >/dev/null
F="$R/.claude/features/demo"; P="$F/pipeline.json"
pipeline "$R" demo '{"feature":"demo","mode":"create","size":"M","stages":{},"attempts":{},"debt":[]}'

echo "deux pipeline.sh debt et un pipe_set simulé, en même temps, 15 fois"
N=15
for i in $(seq 1 "$N"); do
  (cd "$R" && bash "$PIPE" debt demo review "a$i.dart" "problème A $i" >/dev/null 2>&1) &
  (cd "$R" && bash "$PIPE" debt demo review "b$i.dart" "problème B $i" >/dev/null 2>&1) &
  python3 "$SF" jq "$P" --arg p "red_data_$i" '.attempts[$p]=0 | .stages[$p]={status:"PASSED"}' &
  wait
done
OUT="$(jq -r '"\(.debt | length) \(.stages | length) \(.attempts | length)"' "$P")"
expect_out "$((2 * N)) $N $N" "rien de perdu : $((2 * N)) dettes, $N stages, $N attempts"
OUT="$(ls "$F")"
expect_no_out ".tmp" "aucun .tmp laissé"

echo "une commande qui a lu l'état avant le hook n'efface pas ce qu'il a écrit"
OUT="$(cd "$R" && python3 - "$TESTS_DIR/../.." <<'PY'
import os, subprocess, sys
sys.path[:0] = [sys.argv[1], os.path.join(sys.argv[1], "pipeline")]
import pipeline as pl
c = pl.Ctx("demo")                                     # la commande lit l'état…
subprocess.run(["python3", os.path.join(sys.argv[1], "statefile.py"), "jq", c.path,
                '.stages.red_presentation={status:"RED"}'], check=True)   # …le hook écrit pendant ce temps…
c.p.setdefault("human_gates", {})["tests"] = {"at": "x"}
c.p["debt"].append({"source": "s", "file": "late.dart", "issue": "i"})
c.save()                                               # …puis elle écrit
import json
p = json.load(open(c.path))
print("hook:", p["stages"]["red_presentation"]["status"], "gate:", "tests" in p["human_gates"], "debt:", len(p["debt"]))
PY
)"
expect_out "hook: RED gate: True debt: $((2 * N + 1))" "l'écriture du hook et celle de la commande sont toutes deux là"

echo "statefile.py jq : un filtre faux n'écrit rien"
before="$(cat "$P")"
OUT="$(python3 "$SF" jq "$P" '.stages[' 2>&1)"; RC=$?
expect_rc 2 "filtre refusé"
[ "$before" = "$(cat "$P")" ] && _pass "pipeline.json inchangé" || _fail "pipeline.json modifié par un filtre en erreur"

finish
