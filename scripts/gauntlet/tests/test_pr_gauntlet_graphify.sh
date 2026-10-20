#!/usr/bin/env bash
# pr_gauntlet.sh — section « Impact (graphify) » du report.md (spec graphify partagé §4.5).
# Repo + remote bare local ; flutter et graphify factices ; `dart` = celui du PATH (pas de fvm).
source "$(dirname "$0")/fixture.sh"
source "$(dirname "$0")/graphify_fixture.sh"
PR_GAUNTLET="${PR_GAUNTLET:-$TESTS_DIR/../../pr_gauntlet.sh}"

# new_pr <nom> — clone de travail $REPO (develop + feature/x poussées sur un remote bare), graphe de la fixture
new_pr() {
  local d="$TMP_ROOT/$1"; REPO="$d/work"; mkdir -p "$d"
  mk_impact_repo "$REPO" plain
  write_cfg "$REPO"; sed -i.bak 's/^dart = .*/dart = dart/' "$REPO/.claude/rules/feature_pipeline.md"; rm -f "$REPO/.claude/rules/feature_pipeline.md.bak"
  # le graphe n'est pas versionné (graphify-out/ est local au checkout principal)
  git -C "$REPO" rm -r -q --cached graphify-out; printf 'graphify-out/\n' >> "$REPO/.git/info/exclude"
  git -C "$REPO" add -A; git -C "$REPO" commit -q -m "feat(a): modifie foo_impl"
  git clone -q --bare "$REPO" "$d/remote.git"
  git -C "$REPO" remote add origin "$d/remote.git"
  git -C "$REPO" push -q origin develop feature/x 2>/dev/null
  git -C "$REPO" fetch -q origin
  impact_graph_json '' > "$d/graph.json"; export FAKE_GRAPHIFY_GRAPH="$d/graph.json"
}
# run_pr <nom> — lance pr_gauntlet depuis $REPO ; $OUT, $RC ; $PROUT = dossier de sortie
run_pr() {
  PROUT="$TMP_ROOT/$1/out"
  OUT="$(cd "$REPO" && bash "$PR_GAUNTLET" feature/x --base develop --out "$PROUT" 2>&1)"; RC=$?
  REPORT="$PROUT/report.md"
}

fake_graphify_on_path
export FLUTTER="$FAKE_FLUTTER"

echo "pr_impact_section"
new_pr ok; run_pr ok; RC_OK=$RC
expect_file_has "$REPORT" "## Impact (graphify)" "section Impact"
expect_file_has "$REPORT" "| features/b | B_Bloc | A_Repo |" "consommateur non touché"
expect_file_has "$REPORT" "### Ordre de lecture du diff" "ordre de lecture"
expect_file_has "$REPORT" "### Consommateurs hors package non touchés" "sous-titre consommateurs"
[ "$(grep -n '## Impact (graphify)' "$REPORT" | cut -d: -f1)" -lt "$(grep -n '## Verdict scripts' "$REPORT" | cut -d: -f1)" ] \
  && _pass "Impact avant Verdict scripts" || _fail "Impact avant Verdict scripts"
grep -q "^prepare\|^update" "$TMP_ROOT/graphify.calls" 2>/dev/null && _pass "graphify update appelé" || { OUT="$(cat "$TMP_ROOT/graphify.calls" 2>&1)"; _fail "graphify update appelé"; }

echo "pr_impact_does_not_change_rc"
new_pr fail; printf '{' > "$REPO/graphify-out/graph.json"
FAKE_GRAPHIFY_FAIL=1 run_pr fail
expect_rc "$RC_OK" "même code de sortie qu'avec un graphe valide"
expect_file_has "$REPORT" "Impact : non calculé" "ligne d'état dans le rapport"
expect_file_has "$REPORT" "## Verdict scripts" "verdict scripts toujours écrit"

echo "pr_impact_absent"
new_pr absent; rm -rf "$REPO/graphify-out"
run_pr absent
expect_rc "$RC_OK" "même code de sortie sans graphe"
expect_file_has "$REPORT" "Impact : non calculé (absent)" "ligne « absent »"

echo "pr_worktree_cleaned"
new_pr clean; run_pr clean
n="$(git -C "$REPO" worktree list | grep -c .)"
[ "$n" = 1 ] && _pass "seul le checkout principal reste" || { OUT="$(git -C "$REPO" worktree list)"; _fail "worktrees restants : $n"; }

finish
