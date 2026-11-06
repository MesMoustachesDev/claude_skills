# shellcheck shell=bash
# test_plan / test_plan_match — la liste des tests décidée avant l'écriture (étape 3a, test_plan.py).
# test_plan : la liste de Théo prouve chaque item de la spec ou l'écarte avec sa raison, et chaque test
# prouve au moins un item. test_plan_match (gate red) : les tests écrits sont ceux de la liste, ni plus ni moins.
# Les packages de writes.extra comptent avec celui de la feature : une feature extend peut y écrire des tests.
plan_packages() { { printf '%s\n' "$PKG_REL"; extra_packages; } | paste -sd, -; }
check_test_plan() {
  local spec="$FEATURE_DIR/spec.md" plan="$FEATURE_DIR/tests_plan.json"
  [ -f "$spec" ] || { ko "spec.md absente"; return 1; }
  [ -f "$plan" ] || { ko "tests_plan.json absent : la liste se décide avant les tests (étape 3a)"; return 1; }
  python3 "$GAUNTLET_ROOT/test_plan.py" check "$spec" "$plan" "$(plan_packages)"
}

check_test_plan_match() {
  local plan="$FEATURE_DIR/tests_plan.json"
  if [ ! -f "$plan" ]; then
    # Feature commencée avant l'étape 3a (aucune trace de test_plan dans pipeline.json) : rien à comparer.
    if [ "$(pipeline_get '.stages.test_plan.status')" = "" ]; then
      info "pas de tests_plan.json, et la feature n'a pas d'étape 3a (commencée avant) : rien à comparer"
      return 0
    fi
    ko "tests_plan.json absent : la liste se décide avant les tests (étape 3a)"; return 1
  fi
  python3 "$GAUNTLET_ROOT/test_plan.py" match "$plan" "$PROJECT_ROOT" "$(plan_packages)" "$(merge_base)"
}
