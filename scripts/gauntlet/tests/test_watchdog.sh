#!/usr/bin/env bash
# Repro — pipeline.sh watchdog et devices.
# Cas réel : import_cancel_sync, nuit du 4 au 5 novembre 2026. stages.red PASSED à 21:54 (join), aucune
# question posée, rien lancé ensuite : 11 h sans rien jusqu'à 9 h. Le watchdog doit dire « stalled » avec
# l'étape suivante (3b), et ne pas crier quand un sous-agent tourne ou quand c'est Thibault qu'on attend.
source "$(dirname "$0")/fixture.sh"
PIPE="$TESTS_DIR/../../pipeline.sh"
export HOME="$TMP_ROOT/home" NOTIFY_DRY=1; mkdir -p "$HOME/.claude/activity"
R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R" "watchdog.minutes = 20" "qa.platforms = ios" "ios.simulator = iPhone 16 Pro" "ios.simulator_base = QA base"
commit "$R" init >/dev/null
F="$R/.claude/features/demo"
run_p() { OUT="$(cd "$R" && bash "$PIPE" "$@" 2>&1)"; RC=$?; }
old() { touch -t "$(date -v-"$1"M '+%Y%m%d%H%M.%S')" "${@:2}"; }   # mtime à -N minutes
AT11H="$(date -u -v-660M '+%Y-%m-%dT%H:%M:%SZ')"

pipeline "$R" demo "{\"feature\":\"demo\",\"mode\":\"create\",\"size\":\"M\",
  \"stages\":{\"cadrage\":{\"status\":\"PASSED\"},\"contracts_draft\":{\"status\":\"PASSED\"},\"dedup\":{\"status\":\"PASSED\"},
             \"spec\":{\"status\":\"PASSED\"},\"contracts\":{\"status\":\"PASSED\",\"at\":\"2026-11-04T18:34:06Z\"},
             \"red\":{\"status\":\"PASSED\",\"at\":\"$AT11H\"}},
  \"human_gates\":{\"contracts\":{\"at\":\"x\"},\"spec\":{\"at\":\"2026-11-04T18:21:47Z\"}},
  \"cockpit\":{\"waiting\":null,\"at\":\"$AT11H\"}}"
mkdir -p "$F/.gauntlet"; echo '{"ok":true}' > "$F/.gauntlet/last_red.json"
old 660 "$F/pipeline.json" "$F/.gauntlet/last_red.json"

echo "nuit du 4 au 5 : red joint à 21:54, rien ensuite"
run_p watchdog demo
expect_out "verdict   : stalled" "11 h sans rien : stalled"
expect_out "étape suivante 3b" "l'étape à relancer est nommée"
expect_out "dernier gate joué : red (vert)" "le gate que personne n'a lu est nommé"
run_p watchdog demo --json --notify
expect_out '"notified": true' "--notify : notification envoyée"
run_p watchdog demo --notify
expect_no_out "notifié" "pas de seconde notification pour le même verdict"

echo "contrôle — activité récente : pas d'alerte"
touch "$F/.gauntlet/last_red.json"
run_p watchdog demo
expect_out "verdict   : idle" "moins de 20 min : idle"

echo "contrôle — un sous-agent écrit : working"
old 660 "$F/.gauntlet/last_red.json"
SID=s-test; printf '{"session":"%s","cwd":"%s","state":"working","at":0}\n' "$SID" "$R" > "$HOME/.claude/activity/$SID.json"
mkdir -p "$HOME/.claude/projects/x/$SID/subagents"; echo '{}' > "$HOME/.claude/projects/x/$SID/subagents/agent-a.jsonl"
run_p watchdog demo
expect_out "verdict   : working" "sous-agent actif : working"
rm -rf "$HOME/.claude/projects/x" "$HOME/.claude/activity/$SID.json"

echo "question à Thibault : waiting_thibault, alerte après le délai"
run_p say demo "Valide les tests (3b)" --report tests
old 660 "$F/pipeline.json"
python3 - "$F/pipeline.json" "$AT11H" <<'PY'
import json, sys; p = json.load(open(sys.argv[1])); p["cockpit"]["at"] = sys.argv[2]; json.dump(p, open(sys.argv[1], "w"))
PY
old 660 "$F/pipeline.json"
run_p watchdog demo --json
expect_out '"verdict": "waiting_thibault"' "question en attente : waiting_thibault"
expect_out '"alert": true' "attente de plus de 20 min : alerte"
expect_out "Valide les tests" "ce qu'on attend de lui est repris"

echo "next --after : au rapport d'un agent, attend son hook (cas réel : import_cancel_sync, tours finis sur « j'attends la notification »)"
# Le hook démarre 3 s après le rapport, joue 2 s, écrit stages.clean = PASSED.
( sleep 3; echo "$$ $(date +%s) feature-cleaner" > "$F/.gauntlet/hook_clean.running"; sleep 2
  python3 - "$F/pipeline.json" <<'PY'
import json, sys, datetime
p = json.load(open(sys.argv[1])); now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
p["stages"]["clean"] = {"status": "PASSED", "at": now}; json.dump(p, open(sys.argv[1], "w"))
PY
  rm -f "$F/.gauntlet/hook_clean.running" ) &
run_p next demo --after clean
wait
expect_out "hook      : clean = PASSED" "le hook démarré après le rapport est attendu, son verdict lu"
python3 - "$F/pipeline.json" <<'PY'
import json, sys, datetime
p = json.load(open(sys.argv[1])); now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
p["stages"]["clean"] = {"status": "RED", "at": now}; p.setdefault("attempts", {})["clean"] = 1; json.dump(p, open(sys.argv[1], "w"))
PY
run_p next demo --after clean
expect_out "il tourne encore : ne le relance pas" "gate rouge : l'agent renvoyé au travail n'est pas relancé"
python3 - "$F/pipeline.json" <<'PY'
import json, sys
p = json.load(open(sys.argv[1])); p["stages"]["clean"] = {"status": "RED", "at": "2026-11-04T21:54:47Z"}; json.dump(p, open(sys.argv[1], "w"))
PY
SECONDS=0; run_p next demo --after clean
expect_out "aucun hook de fin vu pour clean" "pas de hook en 30 s : le dire, rejouer le gate"
[ "$SECONDS" -le 40 ] && _pass "attente bornée ($SECONDS s)" || _fail "attente bornée ($SECONDS s)"

echo "devices — preflight QA"
run_p devices demo ios reuse --device "iPhone 16 Pro"
expect_rc 2 "réutiliser le simulateur partagé est refusé"
run_p devices demo ios reuse --device "QA base"
expect_rc 2 "réutiliser le modèle est refusé"
run_p devices demo ios prepared
expect_rc 2 "prepared sans --state refusé"
run_p devices demo ios prepared --state "connecté au compte de test, rapport 1234 téléchargé"
expect_rc 0 "prepared avec état"
run_p devices demo ios prepared-done
expect_out "état préparé" "prepared-done tracé"
expect_file_has "$F/pipeline.json" '"prepared_at"' "qa_devices.ios.prepared_at écrit"
run_p devices demo
expect_out "ios : {" "devices liste le choix"

finish
