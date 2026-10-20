#!/usr/bin/env bash
# graphify.sh prepare — rafraîchir, copier, ignorer, mettre à jour (spec graphify partagé §3.1, §5).
# Pas de Flutter ni de fvm : faux `graphify` dans le PATH.
source "$(dirname "$0")/fixture.sh"
source "$(dirname "$0")/graphify_fixture.sh"
fake_graphify_on_path

OLD='{"_mark":"root","built_at_commit":"0ld0ld","nodes":[],"links":[]}'
NEW='{"_mark":"new","nodes":[],"links":[]}'
printf '%s\n' "$NEW" > "$TMP_ROOT/new_graph.json"
export FAKE_GRAPHIFY_GRAPH="$TMP_ROOT/new_graph.json"

# new_prep <nom> [plain|reloconly] — repo + worktree feature/x ; $REPO, $WT, $CALLS
new_prep() {
  REPO="$TMP_ROOT/$1/a b/repo"; CALLS="$TMP_ROOT/graphify.calls"; : > "$CALLS"
  mk_repo "$REPO"; REPO="$(cd "$REPO" && pwd -P)"   # chemin physique (/private/var sur macOS), comme le script
  mkdir -p "$REPO/features/a"; echo x > "$REPO/features/a/f.dart"
  if [ "${2:-plain}" = reloconly ]; then
    mk_graph "$REPO/features/graphify-out" "$OLD"; printf 'features' > "$REPO/features/graphify-out/.graphify_root"
  else
    mk_graph "$REPO/graphify-out" "$OLD"; printf '%s' "$REPO/features" > "$REPO/graphify-out/.graphify_root"
    mk_graph "$REPO/features/graphify-out" '{"_mark":"byproduct","nodes":[],"links":[]}'; printf 'features' > "$REPO/features/graphify-out/.graphify_root"
  fi
  printf 'graphify-out/\n' > "$REPO/.gitignore"; printf '.claude/worktrees/\n' >> "$REPO/.gitignore"
  commit "$REPO" init >/dev/null
  WT="$REPO/.claude/worktrees/feature-x"
  git -C "$REPO" worktree add -q -b feature/x "$WT"
}
prep() { OUT="$(bash "$GRAPHIFY_SH" prepare "$@" 2>"$TMP_ROOT/stderr.log")"; RC=$?; }
mark() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("_mark",""))' "$1"; }
expect_eq() { [ "$1" = "$2" ] && _pass "$3" || { OUT="obtenu « $1 », attendu « $2 »"; _fail "$3"; }; }

echo "prepare_picks_shallowest"
new_prep shallow
git -C "$REPO" rev-parse HEAD >/dev/null
# à jour : built_at_commit == HEAD
python3 - "$REPO" <<'PY'
import json,subprocess,sys
r=sys.argv[1]; h=subprocess.check_output(["git","-C",r,"rev-parse","HEAD"],text=True).strip()
p=r+"/graphify-out/graph.json"; d=json.load(open(p)); d["built_at_commit"]=h; json.dump(d,open(p,"w"))
PY
prep "$WT"
expect_rc 0 "sortie 0"
expect_out "graphify: ok" "ligne d'état ok"
expect_out "graph=graphify-out/graph.json" "graphe racine"
expect_eq "$(mark "$WT/graphify-out/graph.json")" root "graph.json copié = celui de la racine"
[ -e "$WT/features/graphify-out/graph.json" ] && _fail "sous-produit non copié" || _pass "sous-produit non copié"
expect_eq "$(wc -l < "$CALLS" | tr -d ' ')" 0 "à jour : pas d'appel update"
expect_eq "$(cat "$WT/graphify-out/.prepare_status")" ok ".prepare_status ok"

echo "prepare_refreshes_stale_main"
new_prep stale
prep "$WT"
expect_file_has "$CALLS" "update $REPO/features" "update appelé sur <repo>/features"
expect_eq "$(mark "$REPO/graphify-out/graph.json")" new "graphe du principal rafraîchi"
expect_eq "$(mark "$WT/graphify-out/graph.json")" new "worktree reçoit le graphe rafraîchi"

echo "prepare_creates_graphifyignore"
new_prep ign
prep "$WT"
expect_out ".graphifyignore créé" "ligne d'état"
for pat in '*.g.dart' '*.freezed.dart' '*.mocks.dart' 'generated_l10n/'; do expect_file_has "$REPO/.graphifyignore" "$pat" "motif $pat"; done
prep "$WT"
expect_no_out ".graphifyignore créé" "pas recréé"

echo "prepare_excludes"
new_prep excl
printf '.claude/worktrees/\n' > "$REPO/.gitignore"; git -C "$REPO" add .gitignore; git -C "$REPO" commit -q -m gi
git -C "$REPO" worktree remove --force "$WT"; git -C "$REPO" branch -q -D feature/x
git -C "$REPO" worktree add -q -b feature/x "$WT"
prep "$WT"; prep "$WT"
git -C "$WT" check-ignore -q graphify-out/x && _pass "graphify-out/ ignoré dans le worktree" || _fail "graphify-out/ ignoré dans le worktree"
git -C "$REPO" diff --quiet -- .gitignore && _pass ".gitignore inchangé" || _fail ".gitignore inchangé"
EXF="$(git -C "$WT" rev-parse --git-common-dir)/info/exclude"; case "$EXF" in /*) ;; *) EXF="$WT/$EXF" ;; esac
expect_eq "$(grep -cxF 'graphify-out/' "$EXF")" 1 "info/exclude : une seule entrée après deux prepare"

echo "prepare_update_worktree"
new_prep upd
prep "$WT" --update
expect_rc 0 "sortie 0"
expect_out "graphify: ok" "ok"
expect_file_has "$CALLS" "update $WT/features" "update appelé sur <wt>/features"
expect_eq "$(mark "$WT/graphify-out/graph.base.json")" new "graph.base.json = graphe avant update (rafraîchi du principal)"
expect_eq "$(cat "$WT/graphify-out/.prepare_status")" ok ".prepare_status ok"

echo "prepare_update_fails_stale"
new_prep fail
FAKE_GRAPHIFY_FAIL=1 FAKE_GRAPHIFY_FAIL_MATCH="/worktrees/" prep "$WT" --update
expect_rc 0 "sortie 0"
expect_out "graphify: stale (update worktree en échec)" "stale"
expect_eq "$(cat "$WT/graphify-out/.prepare_status")" stale ".prepare_status stale"
expect_eq "$(mark "$WT/graphify-out/graph.json")" new "graph.json = graphe copié"

echo "prepare_no_graphify_cli"
new_prep nocli
SAVED_PATH="$PATH"; PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v 'fake-graphify-bin' | while read -r d; do [ -x "$d/graphify" ] || printf '%s:' "$d"; done)"
PATH="${PATH%:}"
prep "$WT"
PATH="$SAVED_PATH"
expect_rc 0 "sortie 0"
expect_out "graphify: échec graphify introuvable" "échec explicite"

echo "prepare_absent"
REPO="$TMP_ROOT/absent/repo"; mk_repo "$REPO"; echo x > "$REPO/f"; commit "$REPO" i >/dev/null
git -C "$REPO" worktree add -q -b feature/x "$TMP_ROOT/absent/wt"
prep "$TMP_ROOT/absent/wt"
expect_rc 0 "sortie 0"
expect_out "graphify: absent" "absent"
[ -e "$TMP_ROOT/absent/wt/graphify-out" ] && _fail "rien créé" || _pass "rien créé dans le worktree"

echo "prepare_relative_graphify_root"
new_prep rel reloconly
prep "$WT"
expect_rc 0 "sortie 0"
expect_out "graphify: ok" "ok"
expect_eq "$(mark "$WT/features/graphify-out/graph.json")" new "graphe copié au même chemin relatif"
expect_file_has "$CALLS" "update $REPO/features" "racine de scan résolue (features)"

echo "prepare_path_with_spaces"
new_prep "sp ace"
prep "$WT" --update
expect_out "graphify: ok" "ok"
expect_file_has "$CALLS" "update $WT/features" "update sur le worktree"
expect_eq "$(mark "$WT/graphify-out/graph.base.json")" new "graph.base.json"

echo "prepare_worktree_outside_repo"
new_prep outside
OWT="$TMP_ROOT/out/wt"; mkdir -p "$TMP_ROOT/out"
git -C "$REPO" worktree add -q --detach "$OWT"
prep "$OWT"
expect_out "graphify: ok" "ok"
expect_eq "$(mark "$OWT/graphify-out/graph.json")" new "graphe copié"
git -C "$OWT" check-ignore -q graphify-out/x && _pass "exclude correct" || _fail "exclude correct"

finish
