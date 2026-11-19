#!/usr/bin/env bash
# Repro — probes de debug (ADR 0001) et relecteurs sans probe (ADR 0002).
# Cas réels : un implementer et un fix-implementer copient un test gelé dans test/zz_debug_test.dart par python
# pour y ajouter un debugDumpApp() ou un print, le lancent, puis l'effacent ; des relecteurs écrivent des tests
# « probe » dans le worktree pour prouver une critique.
#   hooks : `<dossier de test>/zz_probe_*` est ouvert à l'implementer (et ses moitiés), au cleaner, au hardener,
#     au fix-implementer et au fix-reproducer ; un test gelé reste refusé, et le refus dit comment débugger ;
#     les relecteurs n'ont pas de probe, leur refus renvoie à `to_verify`.
#   gauntlet : un probe oublié rougit test_freeze_check (strict et additive), tests_added ne l'enregistre pas
#     comme test de Hugo ; côté /fix, le check no_probes.
source "$(dirname "$0")/fixture.sh"
need_fvm

HOOKS="$TESTS_DIR/../../../hooks"
export PIPELINE_GAUNTLET_ROOT="$TESTS_DIR/.."
R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
F=app/features
P=$F/feat
mk_pkg "$R/$P" feat
mk_pkg "$R/$F/pics" pics
mkdir -p "$R/$P/test/src/data" "$R/$P/test/src/presentation" "$R/$F/pics/test"
echo "void main() {}" > "$R/$P/test/src/data/frozen_test.dart"
echo "void main() {}" > "$R/$F/pics/test/pics_test.dart"
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/x
FREEZE="$(git -C "$R" rev-parse HEAD)"
pipeline "$R" x "{\"mode\":\"extend\",\"package\":\"$P\",\"writes_extra\":[\"$F/pics/**\"],\"tests_freeze_sha\":\"$FREEZE\"}"
R="$(cd "$R" && pwd -P)"

# hook <script> <agent> <outil> <fichier ou commande> — sortie dans $OUT
hook() {
  local key=file_path; [ "$3" = Bash ] && key=command
  OUT="$(jq -n --arg a "$2" --arg c "$R" --arg t "$3" --arg k "$key" --arg v "$4" \
    '{agent_type:$a, cwd:$c, tool_name:$t, tool_input:{($k):$v}}' \
    | bash "$HOOKS/$1" 2>&1)"
}
PROBE="$R/$P/test/zz_probe_frozen_test.dart"

echo "/feature — le probe est ouvert aux agents qui écrivent du code"
for a in feature-implementer feature-implementer-data feature-implementer-presentation feature-cleaner feature-hardener; do
  hook pipeline-restrict-writes.sh "$a" Write "$PROBE"
  expect_no_out deny "$a : Write de test/zz_probe_frozen_test.dart permis"
done
hook pipeline-restrict-writes.sh feature-implementer Bash "cd $R/$P && cp test/src/data/frozen_test.dart test/zz_probe_frozen_test.dart && fvm flutter test test/zz_probe_frozen_test.dart; rm test/zz_probe_frozen_test.dart"
expect_no_out deny "implementer : cp, lancement par son chemin, rm dans la même commande : permis"
hook pipeline-restrict-writes.sh feature-implementer-data Write "$R/$P/test/src/data/zz_probe_repo_test.dart"
expect_no_out deny "moitié data : probe sous test/src/data : permis"
hook pipeline-restrict-writes.sh feature-cleaner Write "$R/$F/pics/test/zz_probe_pics_test.dart"
expect_no_out deny "cleaner : probe dans un package de writes.extra : permis"

echo "/feature — un test gelé reste gelé, et le refus dit comment débugger"
hook pipeline-restrict-writes.sh feature-implementer Edit "$R/$P/test/src/data/frozen_test.dart"
expect_out "GELÉS" "implementer : Edit d'un test gelé refusé"
expect_out "test/zz_probe_<nom>_test.dart" "le refus donne le nom du probe"
expect_out "efface-le dans la même commande" "le refus dit de l'effacer dans la même commande"
hook pipeline-restrict-writes.sh feature-implementer-presentation Write "$R/$P/test/zz_debug_test.dart"
expect_out "GELÉS" "moitié présentation : test/zz_debug_test.dart (le nom des cas réels) refusé"
hook pipeline-restrict-writes.sh feature-hardener Edit "$R/$P/test/src/data/frozen_test.dart"
expect_out "zz_probe_" "hardener : le refus d'un test gelé donne aussi le probe"
hook pipeline-restrict-writes.sh feature-implementer Write "$R/$P/lib/zz_probe_x.dart"
expect_no_out "zz_probe" "un zz_probe_ hors du dossier de test n'est pas un probe (lib/ suit la zone du code)"

echo "/feature — pas de probe pour les relecteurs"
hook pipeline-restrict-writes.sh feature-reviewer Write "$PROBE"
expect_out "to_verify" "reviewer : probe refusé, le refus renvoie à to_verify"
hook pipeline-restrict-writes.sh feature-reviewer Bash "cp $R/$P/test/src/data/frozen_test.dart $PROBE"
expect_out "reviewer : lecture seule" "reviewer : probe par cp refusé"
hook pipeline-restrict-writes.sh feature-test-reviewer Write "$PROBE"
expect_out "to_verify" "test-reviewer : probe refusé, le refus renvoie à to_verify"
hook pipeline-restrict-writes.sh feature-polisher Write "$PROBE"
expect_out "GELÉS" "polisher : pas de probe (hors liste)"

echo "gauntlet — un probe oublié rougit test_freeze_check"
run_g "$R" test_freeze_check:strict x
expect_rc 0 "strict vert sans probe"
echo "void main() {}" > "$PROBE"
run_g "$R" test_freeze_check:strict x
expect_rc 1 "strict rouge : probe non suivi oublié"
expect_out "zz_probe_* oublié" "le probe est nommé comme tel"
expect_no_out "test/ a changé" "pas confondu avec un test gelé modifié"
run_g "$R" test_freeze_check:additive x
expect_rc 1 "additive (Hugo) rouge : probe oublié"
echo "void main() {}" > "$R/$P/test/src/data/a_mutation_test.dart"
run_g "$R" tests_added x
OUT="$(jq -c '.hardening.tests_added' "$R/.claude/features/x/pipeline.json")"
expect_out "a_mutation_test.dart" "tests_added : le test de Hugo est enregistré"
expect_no_out "zz_probe" "tests_added : le probe n'est pas un test de Hugo"
run_g "$R" test_freeze_check:strict x
expect_rc 1 "strict toujours rouge après tests_added : le probe ne devient pas un test toléré"
rm "$PROBE"
run_g "$R" test_freeze_check:strict x
expect_rc 0 "strict vert une fois le probe effacé (le test de Hugo reste toléré)"
echo "void main() {}" > "$R/$F/pics/test/zz_probe_pics_test.dart"
git -C "$R" add -A "$F/pics" && git -C "$R" commit -qm "probe commité par erreur"
run_g "$R" test_freeze_check:additive x
expect_rc 1 "additive rouge : probe commité dans un package de writes.extra"
git -C "$R" rm -q "$F/pics/test/zz_probe_pics_test.dart" && git -C "$R" commit -qm "retrait"

echo "pipeline.sh freeze et refreeze — un probe n'est jamais gelé"
echo "void main() {} // nouveau" > "$R/$P/test/src/data/new_test.dart"
echo "void main() {}" > "$PROBE"
OUT="$(cd "$R" && bash "$TESTS_DIR/../../pipeline.sh" freeze x 2>&1)"; RC=$?
expect_rc 0 "pipeline.sh freeze"
OUT="$(git -C "$R" show --name-only --format= "$(jq -r .tests_freeze_sha "$R/.claude/features/x/pipeline.json")")"
expect_out "test/src/data/new_test.dart" "le gel commite le nouveau test"
expect_no_out "zz_probe" "le gel ne commite pas le probe"
echo "// corrigé" >> "$R/$P/test/src/data/new_test.dart"
OUT="$(cd "$R" && bash "$TESTS_DIR/../../pipeline.sh" refreeze x technique tests 2>&1)"; RC=$?
expect_rc 0 "pipeline.sh refreeze"
OUT="$(git -C "$R" show --name-only --format= "$(jq -r .tests_freeze_sha "$R/.claude/features/x/pipeline.json")")"
expect_no_out "zz_probe" "le re-gel ne commite pas le probe"
rm "$PROBE"

echo "/fix — Fanny et Bastien ont le probe, Victor non ; no_probes"
export FIX_LIB="$TESTS_DIR/../../fix/lib.sh"
X="$TMP_ROOT/fix"; mkdir -p "$X"; git -C "$X" init -q -b develop
mkdir -p "$X/lib" "$X/test" "$X/.claude/fixes/crash"
echo "int a = 1;" > "$X/lib/a.dart"
echo "void main() {}" > "$X/test/a_test.dart"
echo '{}' > "$X/.claude/fixes/crash/repro.json"
git -C "$X" add -A && git -C "$X" -c user.email=t@t -c user.name=t commit -q -m init
git -C "$X" checkout -q -b fix/crash
X="$(cd "$X" && pwd -P)"
printf '{"base_sha":"%s"}\n' "$(git -C "$X" rev-parse HEAD)" > "$X/.claude/fixes/crash/fix.json"
R="$X"
hook fix-restrict-writes.sh fix-implementer Write "$X/test/zz_probe_a_test.dart"
expect_no_out deny "fix-implementer : probe permis"
hook fix-restrict-writes.sh fix-implementer Bash "cp test/a_test.dart test/zz_probe_a_test.dart && fvm flutter test test/zz_probe_a_test.dart; rm test/zz_probe_a_test.dart"
expect_no_out deny "fix-implementer : cp, lancement, rm dans la même commande : permis"
hook fix-restrict-writes.sh fix-implementer Edit "$X/test/a_test.dart"
expect_out "GELÉS" "fix-implementer : test gelé toujours refusé"
expect_out "zz_probe_<nom>_test.dart" "le refus donne le nom du probe"
hook fix-restrict-writes.sh fix-reproducer Write "$X/test/zz_probe_a_test.dart"
expect_no_out deny "fix-reproducer : probe permis"
hook fix-restrict-writes.sh fix-reviewer Write "$X/test/zz_probe_a_test.dart"
expect_out "to_verify" "fix-reviewer : probe refusé, le refus renvoie à to_verify"

FIX_G="$TESTS_DIR/../../fix_gauntlet.sh"
OUT="$(cd "$X" && bash "$FIX_G" list 2>&1)"
expect_out "no_probes" "fix_gauntlet list documente no_probes"
OUT="$(cd "$X" && bash "$FIX_G" no_probes crash 2>&1)"; RC=$?
expect_rc 0 "no_probes vert sans probe"
echo "void main() {}" > "$X/test/zz_probe_a_test.dart"
OUT="$(cd "$X" && bash "$FIX_G" no_probes crash 2>&1)"; RC=$?
expect_rc 1 "no_probes rouge : probe oublié"
expect_out "test/zz_probe_a_test.dart" "le probe est nommé"
for p in red repro_report green; do
  OUT="$(cd "$X" && bash -c 'source "$1"; profile_checks "$2"' _ <(sed -n '/^profile_checks()/,/^}/p' "$FIX_G") "$p" 2>&1)"
  expect_out "no_probes" "profil $p : no_probes y est"
done

finish
