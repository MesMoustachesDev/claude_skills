#!/usr/bin/env bash
# graphify_fixture.sh — helpers des tests graphify. À sourcer APRÈS fixture.sh.
GRAPHIFY_SH="${GRAPHIFY_SH:-$TESTS_DIR/../../graphify.sh}"

# mk_graph <dir> <json> — écrit <dir>/graph.json (dir = le dossier graphify-out/)
mk_graph() { mkdir -p "$1" && printf '%s\n' "$2" > "$1/graph.json"; }

# fake_graphify_on_path — met dans le PATH un `graphify` factice : `update <path>` écrit $FAKE_GRAPHIFY_GRAPH
# dans <path>/graphify-out/graph.json (ou sort en 1 si FAKE_GRAPHIFY_FAIL=1)
fake_graphify_on_path() {
  local bin="$TMP_ROOT/fake-graphify-bin"
  mkdir -p "$bin"
  cat > "$bin/graphify" <<'FAKE'
#!/usr/bin/env bash
[ "${FAKE_GRAPHIFY_FAIL:-0}" = 1 ] && { echo "fake graphify: échec forcé" >&2; exit 1; }
if [ "${1:-}" = update ]; then
  mkdir -p "$2/graphify-out"
  [ -n "${FAKE_GRAPHIFY_GRAPH:-}" ] && cp "$FAKE_GRAPHIFY_GRAPH" "$2/graphify-out/graph.json"
  exit 0
fi
exit 0
FAKE
  chmod +x "$bin/graphify"
  export PATH="$bin:$PATH"
}

# impact_graph_json <préfixe des source_file : "" ou "features/"> — graph.json de la fixture (stdout)
impact_graph_json() {
  GP="$1" python3 - <<'PY'
import json, os
p = os.environ["GP"]
def n(i, label, f=None, loc="L1"):
    d = {"id": i, "label": label, "source_location": loc}
    if f: d["source_file"] = p + f
    return d
def l(s, t, rel, f, loc):
    return {"source": s, "target": t, "relation": rel, "source_file": p + f, "source_location": loc}
nodes = [
    n("A_Repo", "A_Repo", "a/lib/src/data/foo_impl.dart", "L10"),
    n("A__priv", "_priv", "a/lib/src/data/foo_impl.dart", "L30"),
    n("B_Bloc", "B_Bloc", "b/lib/src/bloc.dart", "L20"),
    n("D_Button", "D_Button", "design/lib/src/button.dart", "L5"),
    n("C_Error", "C_Error", "core/lib/src/error.dart", "L7"),
    n("SDK_Future", "Future"),
]
links = [
    l("B_Bloc", "A_Repo", "references", "b/lib/src/bloc.dart", "L33"),
    l("A_Repo", "D_Button", "calls", "a/lib/src/data/foo_impl.dart", "L12"),
    l("A_Repo", "C_Error", "imports", "a/lib/src/data/foo_impl.dart", "L1"),
    l("A_Repo", "SDK_Future", "references", "a/lib/src/data/foo_impl.dart", "L14"),
    l("A_Repo", "A__priv", "defines", "a/lib/src/data/foo_impl.dart", "L30"),
    l("B_Bloc", "A__priv", "calls", "b/lib/src/bloc.dart", "L40"),
]
print(json.dumps({"directed": False, "built_at_commit": "deadbeef", "nodes": nodes, "links": links}))
PY
}

# mk_impact_repo <repo> [plain|rootscan] — repo de la spec §3.3 : packages a, b (→ a), design, core sous features/,
# graph.json dans <repo>/graphify-out/, commit sur develop, puis feature/x avec foo_impl.dart modifié (non commité).
#   plain    : .graphify_root = <repo>/features, source_file relatifs à features/
#   rootscan : .graphify_root = <repo>, source_file préfixés features/
mk_impact_repo() {
  local R="$1" mode="${2:-plain}" F
  mk_repo "$R"; F="$R/features"
  mk_pkg "$F/a" a design:../design
  mk_pkg "$F/b" b a:../a
  mk_pkg "$F/design" design
  mk_pkg "$F/core" core
  echo "class ARepo {}" > "$F/a/lib/src/data/foo_impl.dart"
  echo "class BBloc {}" > "$F/b/lib/src/bloc.dart"
  echo "class DButton {}" > "$F/design/lib/src/button.dart"
  echo "class CError {}" > "$F/core/lib/src/error.dart"
  if [ "$mode" = rootscan ]; then
    mk_graph "$R/graphify-out" "$(impact_graph_json features/)"; printf '%s' "$R" > "$R/graphify-out/.graphify_root"
  else
    mk_graph "$R/graphify-out" "$(impact_graph_json '')"; printf '%s' "$R/features" > "$R/graphify-out/.graphify_root"
  fi
  commit "$R" develop >/dev/null
  git -C "$R" checkout -q -b feature/x
  echo "// modifié" >> "$F/a/lib/src/data/foo_impl.dart"
}

# run_impact <repo> [args…] — lance graphify.sh impact <repo> develop --out <repo>/out ; $OUT = stdout, $RC
run_impact() {
  local R="$1"; shift
  OUT="$(bash "$GRAPHIFY_SH" impact "$R" develop --out "$R/out" "$@" 2>"$TMP_ROOT/stderr.log")"; RC=$?
}

# expect_json <fichier> <expression python sur d> <label>
expect_json() {
  if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if eval(sys.argv[2]) else 1)' "$1" "$2" 2>/dev/null
  then _pass "$3"; else OUT="$(cat "$1" 2>/dev/null)"; _fail "$3 — $2"; fi
}
