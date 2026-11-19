#!/usr/bin/env bash
# Repro — /reviewPR sur une MR dont la branche est partie avant l'ajout de ios.simulator_base : review.sh sim
# et qa créaient un simulateur neuf (« <ios.simulator> · review-<slug> », sim.sh --like) au lieu de cloner le
# modèle, faute de lire la clé ailleurs que dans le worktree ; cleanup ne supprimait que le dernier créé.
# La config du simulateur se lit dans le checkout principal ; cleanup supprime tous les « … · review-<slug> ».
source "$(dirname "$0")/fixture.sh"
command -v jq >/dev/null || { echo "SKIP: jq requis"; exit 0; }
SCRIPTS="$(cd "$TESTS_DIR/../.." && pwd)"

# HOME jetable : review.py y trouve sim.sh (celui testé), un faux gauntlet.sh et son état ; xcrun simulé.
H="$TMP_ROOT/home"; BIN="$TMP_ROOT/bin"; mkdir -p "$H/.claude/scripts" "$BIN"
ln -s "$SCRIPTS/sim.sh" "$H/.claude/scripts/sim.sh"
printf '#!/usr/bin/env bash\necho "gauntlet $* sim=$GAUNTLET_SIM_UDID"\n' > "$H/.claude/scripts/gauntlet.sh"
cp "$TESTS_DIR/fake_xcrun.py" "$BIN/xcrun"; chmod +x "$H/.claude/scripts/gauntlet.sh" "$BIN/xcrun"
export FAKE_SIMS="$TMP_ROOT/sims.json"
cat > "$FAKE_SIMS" <<'EOF'
[{"name":"Shared","udid":"SHARED-0","state":"Booted","deviceTypeIdentifier":"iPhone-X","runtime":"iOS-26"},
 {"name":"QA base","udid":"BASE-0","state":"Shutdown","deviceTypeIdentifier":"iPhone-X","runtime":"iOS-26"}]
EOF

# develop sans ios.simulator_base, la MR part de là ; la clé arrive ensuite sur develop (checkout principal).
R="$TMP_ROOT/repo"; mk_repo "$R"
cfg_ios() { write_cfg "$R" "qa.platforms = ios" "ios.simulator = Shared" "$@"; sed -i "" "/^qa.platforms =$/d" "$R/.claude/pipeline/feature_pipeline.md"; }
cfg_ios; commit "$R" init >/dev/null
git -C "$R" branch mr
cfg_ios "ios.simulator_base = QA base"; commit "$R" "simulateur modèle" >/dev/null
WT="$TMP_ROOT/wt/mr"; git -C "$R" worktree add -q "$WT" mr

D="$H/.cache/gauntlet/review/mr-1"; mkdir -p "$D/maestro"; echo 'appId: x' > "$D/maestro/s1.yaml"
printf '{"slug":"mr-1","project_root":"%s","worktree":"%s","gauntlet_out":"%s","stages":{}}\n' "$R" "$WT" "$TMP_ROOT/out" > "$D/review.json"

run_r() { OUT="$(cd "$R" && HOME="$H" PATH="$BIN:$PATH" bash "$SCRIPTS/review.sh" "$@" 2>&1)"; RC=$?; }
udid_of() { jq -r --arg n "$1" '[.[] | select(.name==$n)][0].udid // empty' "$FAKE_SIMS"; }
expect_sim()    { [ -n "$(udid_of "$1")" ] && _pass "$2" || { OUT="$(cat "$FAKE_SIMS")"; _fail "$2 — « $1 » absent"; }; }
expect_no_sim() { [ -z "$(udid_of "$1")" ] && _pass "$2" || { OUT="$(cat "$FAKE_SIMS")"; _fail "$2 — « $1 » présent"; }; }

OUT="$(cd "$WT" && PATH="$BIN:$PATH" bash "$SCRIPTS/sim.sh" base 2>&1)"; RC=$?
expect_out "QA base" "sim.sh base depuis le worktree : le modèle du checkout principal"

run_r sim mr-1
expect_rc 0 "review.sh sim"
expect_sim "QA base · review-mr-1" "sim clone le modèle"
expect_no_sim "Shared · review-mr-1" "aucun simulateur neuf (--like)"
CLONE="$(udid_of "QA base · review-mr-1")"
expect_out "$CLONE" "sim imprime l'UDID du clone"

# Un simulateur neuf laissé par l'ancien code ne doit ni servir à la QA ni survivre au cleanup.
jq '. + [{"name":"Shared · review-mr-1","udid":"LIKE-0","state":"Shutdown","deviceTypeIdentifier":"iPhone-X","runtime":"iOS-26"}]' \
  "$FAKE_SIMS" > "$FAKE_SIMS.tmp" && mv "$FAKE_SIMS.tmp" "$FAKE_SIMS"
N="$(jq length "$FAKE_SIMS")"
run_r qa mr-1
expect_rc 0 "review.sh qa"
expect_out "sim=$CLONE" "qa vise le clone du modèle déjà là"
[ "$(jq length "$FAKE_SIMS")" = "$N" ] && _pass "qa ne crée aucun simulateur" || _fail "qa a créé un simulateur"

run_r cleanup mr-1
expect_rc 0 "review.sh cleanup"
expect_no_sim "QA base · review-mr-1" "cleanup supprime le clone du modèle"
expect_no_sim "Shared · review-mr-1" "cleanup supprime aussi le simulateur neuf"
expect_sim "QA base" "le modèle reste"
expect_sim "Shared" "le simulateur partagé reste"
finish
