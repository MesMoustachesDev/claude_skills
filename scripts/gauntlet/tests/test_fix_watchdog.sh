#!/usr/bin/env bash
# Repro — le watchdog ne suivait pas /fix (ADR 0005, « Hors champ »). Cas réel : gate green de Fanny passé,
# Victor jamais lancé, aucune question posée : personne ne l'a vu jusqu'au retour du dev.
#   fix_gauntlet.sh watchdog <nom> doit dire « stalled » avec l'étape à reprendre, ne pas crier quand un
#   sous-agent tourne ou quand on attend le dev, et watchdog.sh doit suivre le fix hors session.
source "$(dirname "$0")/fixture.sh"
FG="$TESTS_DIR/../../fix_gauntlet.sh"; WD="$TESTS_DIR/../../watchdog.sh"
CK="$TESTS_DIR/../../fix_cockpit.py"
export HOME="$TMP_ROOT/home" NOTIFY_DRY=1; mkdir -p "$HOME/.claude/activity"
R="$TMP_ROOT/repo"; mkdir -p "$R/.claude/fixes/crash/.gauntlet"; git -C "$R" init -q -b develop
echo x > "$R/a"; git -C "$R" add -A && git -C "$R" -c user.email=t@t -c user.name=t commit -q -m init
git -C "$R" checkout -q -b fix/crash
D="$R/.claude/fixes/crash"; S="$D/fix.json"
old() { touch -t "$(date -v-"$1"M '+%Y%m%d%H%M.%S')" "${@:2}"; }   # mtime à -N minutes
run_w() { OUT="$(cd "$R" && bash "$FG" watchdog crash "$@" 2>&1)"; RC=$?; }
cat > "$S" <<'EOF'
{"fix":"crash","stages":{"red":{"status":"PASSED"},"green":{"status":"PASSED","at":"2026-11-05T14:02:00Z"}},
 "human_gates":{"repro":{"at":"2026-11-05T13:40:00Z"}},"cockpit":{"waiting":null}}
EOF
echo '{"ok":true}' > "$D/.gauntlet/last_green.json"
old 90 "$S" "$D/.gauntlet/last_green.json"

echo "green de Fanny passé il y a 90 min, Victor jamais lancé"
run_w
expect_out "verdict   : stalled" "rien ne tourne, aucune question : stalled"
expect_out "étape suivante 3 — Revue (Victor)" "l'étape à reprendre est nommée"
expect_out "dernier gate joué : green (vert)" "le gate que personne n'a lu est nommé"
run_w --json --notify
expect_out '"notified": true' "--notify : notification envoyée (90 min ≥ deux délais)"
run_w --notify
expect_no_out "notifié" "pas de seconde notification pour le même verdict"

echo "contrôle — un sous-agent écrit : working"
SID=s-fix; printf '{"session":"%s","cwd":"%s","state":"working","at":0}\n' "$SID" "$R" > "$HOME/.claude/activity/$SID.json"
mkdir -p "$HOME/.claude/projects/x/$SID/subagents"; echo '{}' > "$HOME/.claude/projects/x/$SID/subagents/agent-v.jsonl"
run_w
expect_out "verdict   : working" "Victor tourne : working"
rm -rf "$HOME/.claude/projects/x" "$HOME/.claude/activity/$SID.json"

echo "question au dev : waiting_thibault"
(cd "$R" && python3 "$CK" say crash "Valide le diagnostic, le test rouge et le plan" >/dev/null)
expect_file_has "$S" '"at"' "say note depuis quand on attend"
run_w
expect_out "verdict   : waiting_thibault" "question en attente : pas un blocage"
expect_out "Valide le diagnostic" "ce qu'on attend du dev est repris"
(cd "$R" && python3 "$CK" say crash "" >/dev/null); old 90 "$S"

echo "veille hors session : watchdog.sh suit le fix"
mkdir -p "$HOME/.claude/state"; printf '%s\t%s\n' "/nulle/part" "ancienne_feature" > "$HOME/.claude/state/feature_watchdog.tsv"
OUT="$(bash "$WD" register "$R" crash --fix 2>&1)"
expect_out "suivi : crash (fix" "register --fix"
OUT="$(bash "$WD" list 2>&1)"
expect_out "ancienne_feature : worktree ou pipeline.json disparu" "une ligne à deux colonnes reste lue comme une feature"
expect_out "crash" "le fix est listé"
expect_out "stalled" "avec son verdict"

echo "fix terminé : done, et il sort de la liste"
python3 - "$S" <<'PY'
import json, sys
p = json.load(open(sys.argv[1])); p["stages"].update({"review": {"status": "PASSED"}, "evidence": {"status": "PASSED"}})
json.dump(p, open(sys.argv[1], "w"))
PY
run_w
expect_out "verdict   : done" "evidence PASSED : done"
bash "$WD" list >/dev/null 2>&1
OUT="$(cat "$HOME/.claude/state/feature_watchdog.tsv")"
expect_no_out "crash" "un fix terminé n'est plus suivi"

finish
