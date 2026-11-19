#!/usr/bin/env bash
# Config du projet hors de .claude/rules/ (ADR 0008, amendée le 2026-11-19) : les lecteurs du bloc ini prennent
# .claude/pipeline/feature_pipeline.md, et à défaut l'ancien .claude/rules/feature_pipeline.md, pour qu'un
# projet pas encore migré marche comme avant. Le nouvel emplacement gagne quand les deux existent.
source "$(dirname "$0")/fixture.sh"
SCRIPTS="$(cd "$TESTS_DIR/../.." && pwd)"
export CLAUDE_STACKS_DIR="$SCRIPTS/../stacks"
# fn <script> <fonction> <args…> — appelle une fonction d'un script sans lancer le script
fn() { local s="$1" f="$2"; shift 2; bash -c "$(sed -n "/^$f() {/,/^}/p" "$s")"'; "$@"' _ "$f" "$@" 2>&1; }

R="$TMP_ROOT/repo"; mk_repo "$R"; mkdir -p "$R/app" "$R/.claude/rules" "$R/.claude/pipeline"
touch "$R/app/pubspec.yaml" "$R/app/.fvmrc"
cfg() { printf '# cfg\n```ini\nflutter = %s\napp_dir = app\nworktree.copy_untracked = %s\nios.simulator_base = %s\ngraphify.ignore_packages = %s\n```\n' "$2" "$2" "$2" "$2" > "$1"; }
OLD="$R/.claude/rules/feature_pipeline.md"; NEW="$R/.claude/pipeline/feature_pipeline.md"
pycfg() { python3 - "$R" <<'PY'
import importlib.util, os, sys
root = sys.argv[1]
here = os.environ["SCRIPTS"]
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path); m = importlib.util.module_from_spec(spec)
    sys.path[:0] = [os.path.dirname(path)]; spec.loader.exec_module(m); return m
pl = load("pipeline", os.path.join(here, "pipeline", "pipeline.py"))
rv = load("review", os.path.join(here, "review", "review.py"))
print("pipeline.py", os.path.relpath(pl.project_cfg_file(root), root))
print("review.py", os.path.relpath(rv.cfg_path(root), root))
PY
}
export SCRIPTS
all() {
  OUT="$(bash "$SCRIPTS/stack.sh" get flutter "$R/app" 2>&1)"; expect_out "$1" "$2 : stack.sh get"
  OUT="$(bash "$SCRIPTS/worktree_untracked.sh" --patterns "$R" 2>&1)"; expect_out "$1" "$2 : worktree_untracked.sh"
  OUT="$(fn "$SCRIPTS/sim.sh" cfg_base "$R")"; expect_out "$1" "$2 : sim.sh"
  OUT="$(fn "$SCRIPTS/graphify.sh" read_cfg "$R" graphify.ignore_packages)"; expect_out "$1" "$2 : graphify.sh"
  OUT="$(cd "$R" && GAUNTLET_CFG= bash -c 'source "$1/gauntlet/lib.sh" 2>/dev/null; init_project_context "" >/dev/null 2>&1; echo "$CFG_FILE"; cfg flutter' _ "$SCRIPTS" 2>&1)"
  expect_out "$1" "$2 : gauntlet/lib.sh"
  OUT="$(pycfg 2>&1)"; expect_out "pipeline.py $3" "$2 : pipeline.py"; expect_out "review.py $3" "$2 : review.py"
}

echo "projet pas encore migré : l'ancien .claude/rules/ est lu"
cfg "$OLD" ancien
all ancien "ancien seul" .claude/rules/feature_pipeline.md
OUT="$(fn "$SCRIPTS/serena.sh" app_root "$R")"; expect_out "$R/app" "ancien seul : serena.sh app_root"

echo "projet migré : .claude/pipeline/ est lu"
rm -f "$OLD"; cfg "$NEW" nouveau
all nouveau "nouveau seul" .claude/pipeline/feature_pipeline.md
OUT="$(fn "$SCRIPTS/serena.sh" app_root "$R")"; expect_out "$R/app" "nouveau seul : serena.sh app_root"

echo "les deux : le nouveau gagne"
cfg "$OLD" ancien
all nouveau "les deux" .claude/pipeline/feature_pipeline.md

echo "le gabarit d'écran est sous paths:"
for st in flutter android; do
  OUT="$(head -12 "$CLAUDE_STACKS_DIR/$st/templates/create_screen_rules.md")"
  expect_out "paths:" "$st : create_screen_rules.md a un frontmatter paths:"
done

finish
