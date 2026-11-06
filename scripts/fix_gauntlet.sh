#!/usr/bin/env bash
# fix_gauntlet.sh — gates déterministes du pipeline /fix. Indépendant de la stack : les commandes
# viennent de .claude/fixes/<nom>/repro.json, écrit par le reproducer et gelé avec les tests.
#
# Usage :
#   fix_gauntlet.sh <profil|check> <nom>
#   fix_gauntlet.sh list
#   fix_gauntlet.sh after <profil> <nom>  au rapport d'un agent : attend son hook, et l'agent si le gate est rouge
#   fix_gauntlet.sh watchdog <nom> [--json] [--notify]  le fix est-il bloqué ? (fix/watchdog.py, ADR 0005)
#   fix_gauntlet.sh report <nom> [étape]   rapport HTML pour le dev (.claude/fixes/<nom>/report.html)
#
# Exit 0 si tout est vert, 1 sinon. Écrit .claude/fixes/<nom>/.gauntlet/last_<profil>.{log,json}.
# Les commandes de repro.json tournent depuis <racine>/<package>, avec :
#   FIX_SHOTS_DIR  dossier où déposer les captures (UI) — shots/red/ pendant red, shots/green/ pendant green
#   FIX_PHASE      red | green
#   FIX_SIM_UDID   (device_red / device_green) UDID du simulateur iOS propre à ce fix, « <modèle> · fix-<nom> »,
#                  cloné de ios.simulator_base par sim.sh ; déjà posé dans l'environnement, il est gardé tel quel
set -u
set -o pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # ce checkout (~/.claude/scripts en usage normal)
source "$SCRIPTS/gauntlet/lib.sh"   # info ok ko die section, stack_check_known
source "$SCRIPTS/fix/lib.sh"

profile_checks() {
  case "$1" in
    red)            echo "repro_schema only_tests_changed no_debug_markers target_red" ;;
    repro_report)   echo "repro_schema no_debug_markers" ;;
    green)          echo "repro_schema freeze_check source_changed no_debug_markers target_green suite_green lint conventions" ;;
    review_report)  echo "review_report" ;;
    review_verdict) echo "review_verdict" ;;
    *) echo "" ;;
  esac
}

profiles_list() {
  cat <<'EOF'
Profils :
  red             après le REPRODUCER : seuls des tests ont changé, le test cible échoue avec expected_failure
  repro_report    reproducer en arbitrage : repro.json valide, pas de log de debug oublié
  green           après l'IMPLEMENTER : gel intact, du code a changé, cible verte, suite verte, lint
  (device_red / device_green ne sont dans aucun profil : l'orchestrateur les lance lui-même, jamais un hook.
   Ils tournent sur le simulateur du fix, cloné du modèle ios.simulator_base (sim.sh ensure fix-<nom>) :
   pas de go du dev. Sans ios.simulator_base, ou avec FIX_SIM_UDID pointé sur le modèle ou un appareil
   partagé, le go du dev reste requis avant chaque lancement)
  review_report   review.json présent et valide (hook du reviewer)
  review_verdict  aucun critique non accepté (lu par l'orchestrateur)

Checks :
  repro_schema       repro.json : package, target_cmd, expected_failure, suite_cmd, test_files existants et reconnus comme tests, fix_plan
  only_tests_changed depuis base_sha : uniquement tests, manifestes (package.json, pubspec.yaml, ceux du langage) et .claude/fixes/<nom>/
  no_debug_markers   aucun [DEBUG_ISSUE] dans le repo
  target_red         target_cmd échoue ET sa sortie contient expected_failure (rouge pour la bonne raison)
  freeze_check       depuis freeze_sha : aucun test ni repro.json modifié, aucun test ajouté
  source_changed     depuis freeze_sha : au moins un fichier hors tests a changé
  target_green       target_cmd passe
  suite_green        suite_cmd passe
  lint               lint_cmd passe ; vide → lint_cmd du langage du package (stack.ini) ; aucun → [N/A]
  conventions        design_system + l10n_strings du gauntlet feature sur les lignes modifiées de chaque package touché
                     ([N/A] sans .claude/rules/feature_pipeline.md)
                     Un check qui n'a rien pu vérifier sort en [N/A] (not_applicable du JSON), jamais vert (ADR 0011).
  device_red         device_repro.cmd (le parcours du signalement, sur device) échoue avec device_repro.expected_failure
  device_green       device_repro.cmd passe
                     (les deux sautés seulement si device_repro.not_applicable donne une raison ; la commande
                     reçoit FIX_SIM_UDID, le simulateur du fix, à supprimer après le merge : sim.sh remove fix-<nom>)
EOF
}

# run_in_pkg <label> <cmd> — exécute une commande de repro.json depuis le package, sortie dans $FIX_OUT/<label>.out
run_in_pkg() {
  local label="$1" cmd="$2" pkg out="$FIX_OUT/$1.out"
  pkg="$(repro_get .package)"; pkg="${pkg:-.}"
  mkdir -p "$FIX_SHOTS_DIR"
  (cd "$PROJECT_ROOT/$pkg" && FIX_SHOTS_DIR="$FIX_SHOTS_DIR" FIX_PHASE="$FIX_PHASE" FIX_SIM_UDID="${FIX_SIM_UDID:-}" \
     MAESTRO_DRIVER_STARTUP_TIMEOUT="${MAESTRO_DRIVER_STARTUP_TIMEOUT:-180000}" bash -c "$cmd") > "$out" 2>&1
}

# device_sim — FIX_SIM_UDID : le simulateur propre à ce fix (sim.sh ensure fix-<nom>), cloné et booté.
# Un FIX_SIM_UDID déjà posé (le dev a choisi un appareil) est gardé ; sans ios.simulator_base, il reste vide.
device_sim() {
  [ -n "${FIX_SIM_UDID:-}" ] && { info "simulateur imposé : $FIX_SIM_UDID"; return 0; }
  local sim="$SCRIPTS/sim.sh"
  (cd "$PROJECT_ROOT" && "$sim" base) >/dev/null 2>&1 \
    || { info "pas de ios.simulator_base : FIX_SIM_UDID vide, la commande choisit son appareil"; return 0; }
  FIX_SIM_UDID="$(cd "$PROJECT_ROOT" && "$sim" ensure "fix-$FIX_NAME" 2>"$FIX_OUT/sim.out")" \
    || { sed 's/^/  /' "$FIX_OUT/sim.out"; ko "pas de simulateur pour ce fix (sim.sh ensure fix-$FIX_NAME)"; return 1; }
  info "simulateur du fix : $(cd "$PROJECT_ROOT" && "$sim" base) · fix-$FIX_NAME ($FIX_SIM_UDID)"
}

check_repro_schema() {
  [ -f "$REPRO" ] || { ko "repro.json absent — le reproducer doit produire ${REPRO#$PROJECT_ROOT/}"; return 1; }
  jq -e '(.package|type=="string") and (.kind|IN("unit","widget","integration","ui"))
         and (.target_cmd|type=="string" and length>0) and (.expected_failure|type=="string" and length>0)
         and (.suite_cmd|type=="string" and length>0) and (.test_files|type=="array" and length>0)
         and (.root_cause|type=="string" and length>0) and (.miss_reason|IN("no_test","wrong_test","wrong_layer","untested_case","flaky_or_env","other"))
' \
    "$REPRO" >/dev/null 2>&1 \
    || { ko "repro.json invalide : package, kind (unit|widget|integration|ui), target_cmd, expected_failure, suite_cmd, test_files[], root_cause, miss_reason (no_test|wrong_test|wrong_layer|untested_case|flaky_or_env|other)"; return 1; }
  if ! jq -e '(.fix_plan|type=="object") and (.fix_plan.layer|type=="string" and length>0)
         and (.fix_plan.approach|type=="string" and length>0) and (.fix_plan.files|type=="array" and length>0)
         and (.fix_plan.rejected|type=="string" and length>0)' "$REPRO" >/dev/null 2>&1; then
    # Un fix gelé avant l'introduction du plan reste reprenable : son repro.json ne peut plus changer.
    if [ -n "$(state_get .freeze_sha)" ]; then info "pas de fix_plan (gelé avant le plan de correction)"
    else ko "repro.json : fix_plan {layer, approach, files[], rejected} manquant ou incomplet"; return 1; fi
  fi
  # The bug is reproduced where it was reported: a device run of the reported scenario, or a stated
  # reason why there is none (backend crash with no screen, Sentry-only…).
  if ! jq -e '(.device_repro|type=="object") and (
                ((.device_repro.cmd|type=="string" and length>0) and (.device_repro.expected_failure|type=="string" and length>0))
                or (.device_repro.not_applicable|type=="string" and length>0))' "$REPRO" >/dev/null 2>&1; then
    if [ -n "$(state_get .freeze_sha)" ]; then info "pas de device_repro (gelé avant son introduction)"
    else ko "repro.json : device_repro {cmd, expected_failure} (parcours du signalement rejoué sur device) ou {not_applicable: \"<raison>\"} manquant"; return 1; fi
  fi
  [ -d "$PROJECT_ROOT/$(repro_get .package)" ] || { ko "package introuvable : $(repro_get .package)"; return 1; }
  local f rc=0
  while IFS= read -r f; do
    [ -e "$PROJECT_ROOT/$f" ] || { ko "test_files : $f n'existe pas (chemin relatif à la racine)"; rc=1; continue; }
    is_test_path "$f" || { ko "test_files : $f n'est pas reconnu comme un test (ajoute son motif à repro.json → test_paths)"; rc=1; }
  done < <(jq -r '.test_files[]' "$REPRO")
  [ "$rc" = 0 ] && info "kind $(repro_get .kind), $(jq '.test_files|length' "$REPRO") fichier(s) de test, cause : $(repro_get .miss_reason)"
  return $rc
}

check_only_tests_changed() {
  local base f bad=""
  # A second reproducer pass runs after the fix was committed: compare to the
  # last freeze, not to the base, or the fix itself reads as source changes.
  base="$(state_get .freeze_sha)"
  [ -n "$base" ] && [ "$base" != "null" ] || base="$(state_get .base_sha)"
  [ -n "$base" ] || { ko "fix.json → base_sha absent"; return 1; }
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    # graphify.sh prepare copies untracked .graphifyignore files into the worktree.
    case "$f" in .claude/fixes/*|.graphifyignore|*/.graphifyignore|graphify-out/*) continue ;; esac
    is_test_path "$f" || is_manifest_path "$f" || bad="$bad  $f"$'\n'
  done < <(changed_since "$base")
  [ -z "$bad" ] && { info "depuis $base : tests et dossier du fix seulement"; return 0; }
  printf '%s' "$bad"
  ko "le reproducer ne corrige pas : ces fichiers hors tests ont changé depuis $base"
  return 1
}

check_no_debug_markers() {
  local hits
  hits="$(git -C "$PROJECT_ROOT" grep -nF --untracked "$DEBUG_MARKER" -- . ':!.claude/' 2>/dev/null | head -20)"
  [ -z "$hits" ] && return 0
  printf '%s\n' "$hits" | sed 's/^/  /'
  ko "logs $DEBUG_MARKER encore présents — à retirer"
  return 1
}

check_target_red() {
  local rc expected
  run_in_pkg target "$(repro_get .target_cmd)"; rc=$?
  expected="$(repro_get .expected_failure)"
  if [ "$rc" = 0 ]; then
    tail -15 "$FIX_OUT/target.out" | sed 's/^/  /'
    ko "target_cmd passe : le test ne reproduit pas le bug"; return 1
  fi
  if ! grep -qF -- "$expected" "$FIX_OUT/target.out"; then
    tail -30 "$FIX_OUT/target.out" | sed 's/^/  /'
    ko "target_cmd échoue, mais pas pour la raison annoncée : « $expected » absent de la sortie (compilation ? import ? setup ?)"
    return 1
  fi
  grep -nF -- "$expected" "$FIX_OUT/target.out" | head -3 | sed 's/^/  › /'
  info "rouge pour la bonne raison (exit $rc)"
}

# device_skip — true (with the reason logged) when the fix declares no device reproduction.
device_skip() {
  local na; na="$(repro_get .device_repro.not_applicable)"
  if [ -n "$na" ]; then info "pas de repro device : $na"; return 0; fi
  if [ -z "$(repro_get .device_repro.cmd)" ] && [ -n "$(state_get .freeze_sha)" ]; then
    info "pas de device_repro (gelé avant son introduction)"; return 0
  fi
  return 1
}

check_device_red() {
  device_skip && return 0
  device_sim || return 1
  local rc expected
  run_in_pkg device "$(repro_get .device_repro.cmd)"; rc=$?
  expected="$(repro_get .device_repro.expected_failure)"
  if [ "$rc" = 0 ]; then
    tail -15 "$FIX_OUT/device.out" | sed 's/^/  /'
    ko "device_repro.cmd passe : le parcours du signalement ne montre pas le bug sur device"; return 1
  fi
  if ! grep -qF -- "$expected" "$FIX_OUT/device.out"; then
    tail -30 "$FIX_OUT/device.out" | sed 's/^/  /'
    ko "device_repro.cmd échoue, mais pas pour la raison annoncée : « $expected » absent de la sortie (build ? device ? sélecteur ?)"
    return 1
  fi
  info "bug reproduit sur device (captures : ${FIX_SHOTS_DIR#$PROJECT_ROOT/})"
}

check_device_green() {
  device_skip && return 0
  device_sim || return 1
  run_in_pkg device "$(repro_get .device_repro.cmd)" && { info "parcours du signalement vert sur device (captures : ${FIX_SHOTS_DIR#$PROJECT_ROOT/})"; return 0; }
  tail -30 "$FIX_OUT/device.out" | sed 's/^/  /'
  ko "device_repro.cmd échoue encore sur device"
  return 1
}

check_freeze_check() {
  local sha f bad=""
  sha="$(state_get .freeze_sha)"
  [ -n "$sha" ] || { ko "pas de gel enregistré (fix.json → freeze_sha)"; return 1; }
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if is_test_path "$f" || [ "$f" = "${REPRO#$PROJECT_ROOT/}" ]; then bad="$bad  $f"$'\n'; fi
  done < <(changed_since "$sha")
  [ -z "$bad" ] && { info "gel $sha respecté"; return 0; }
  printf '%s' "$bad"
  ko "tests ou repro.json modifiés depuis le gel ($sha)"
  return 1
}

check_source_changed() {
  local sha f n=0
  sha="$(state_get .freeze_sha)"
  [ -n "$sha" ] || { ko "pas de gel enregistré"; return 1; }
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in .claude/*) continue ;; esac
    is_test_path "$f" || n=$((n+1))
  done < <(changed_since "$sha")
  [ "$n" -gt 0 ] && { info "$n fichier(s) source modifié(s) depuis le gel"; return 0; }
  ko "aucun fichier source modifié depuis le gel : rien n'a été corrigé (test instable ?)"
  return 1
}

check_target_green() {
  run_in_pkg target "$(repro_get .target_cmd)" && { info "test cible vert"; return 0; }
  tail -30 "$FIX_OUT/target.out" | sed 's/^/  /'
  ko "target_cmd échoue encore"
  return 1
}

check_suite_green() {
  run_in_pkg suite "$(repro_get .suite_cmd)" && { info "suite verte"; return 0; }
  tail -40 "$FIX_OUT/suite.out" | sed 's/^/  /'
  ko "suite_cmd échoue (régression, ou échec préexistant : voir repro.json → baseline_suite)"
  return 1
}

check_lint() {
  local cmd pkg; cmd="$(repro_get .lint_cmd)"
  if [ -z "$cmd" ]; then
    pkg="$(repro_get .package)"
    cmd="$(bash "$SCRIPTS/stack.sh" get lint_cmd "$PROJECT_ROOT/${pkg:-.}" 2>/dev/null)"
    [ -n "$cmd" ] || { not_applicable "ni lint_cmd dans repro.json, ni lint_cmd pour le langage du package"; return; }
    info "lint du langage : $cmd"
  fi
  run_in_pkg lint "$cmd" && return 0
  tail -30 "$FIX_OUT/lint.out" | sed 's/^/  /'
  ko "lint_cmd échoue"
  return 1
}

# conventions — the feature gauntlet's presentation checks, scoped to the lines this fix changed. A fix is
# held to the same design system and l10n rules as a feature, even on a line it only re-indents.
# Packages jugés : ceux qui contiennent un fichier source modifié hors tests, source au sens du langage du package
# (stack.ini → extensions : .dart pour Flutter, .kt/.kts/.java pour Android). Un check sans version pour ce langage
# est dit non applicable, pas vert en silence.
check_conventions() {
  [ -f "$PROJECT_ROOT/.claude/rules/feature_pipeline.md" ] \
    || { not_applicable "pas de .claude/rules/feature_pipeline.md (/feature init)"; return; }
  local base f d pkgs="" pkg c rc=0 lang ext ok_ext others=""
  base="$(state_get .base_sha)"
  [ -n "$base" ] || { ko "fix.json → base_sha absent"; return 1; }
  while IFS= read -r f; do
    is_test_path "$f" && continue
    d="$(bash "$SCRIPTS/stack.sh" package "$PROJECT_ROOT/$f" 2>/dev/null)" || continue
    d="${d#"$PROJECT_ROOT"}"; d="${d#/}"
    [ -n "$d" ] || continue                       # package racine : hors conventions, comme avant
    ok_ext=0
    for ext in $(bash "$SCRIPTS/stack.sh" get extensions "$PROJECT_ROOT/$d" 2>/dev/null | tr ',' ' '); do
      case "$f" in *"$ext") ok_ext=1 ;; esac
    done
    if [ "$ok_ext" = 1 ]; then pkgs="$pkgs"$'\n'"$d"; else others="$others"$'\n'"$f"; fi
  done < <(changed_since "$base")
  pkgs="$(printf '%s\n' "$pkgs" | grep -v '^$' | sort -u)"
  others="$(printf '%s\n' "$others" | grep -v '^$')"
  [ -n "$others" ] && info "non applicable (pas une source du langage de leur package) : $(printf '%s' "$others" | tr '\n' ' ')"
  [ -n "$pkgs" ] || { info "aucun fichier source d'un langage connu modifié hors tests"; return 0; }
  while IFS= read -r pkg; do
    lang="$(bash "$SCRIPTS/stack.sh" detect "$PROJECT_ROOT/$pkg" 2>/dev/null)"
    for c in design_system l10n_strings; do
      if ! grep -qsE "^check_${c}\(\)" "$CLAUDE_STACKS_DIR/$lang"/checks*.sh "$SCRIPTS"/gauntlet/checks_*.sh; then
        info "$pkg : $c non applicable à ${lang:-ce langage} (aucune version de ce check)"
        FIX_NA="$FIX_NA $c@$pkg"; continue
      fi
      if GAUNTLET_MODE=extend GAUNTLET_PACKAGE="$pkg" GAUNTLET_FEATURES_ROOT="$FIX_OUT/conventions" GAUNTLET_KEEP_FORMAT_LINES=1 \
        "$SCRIPTS/gauntlet.sh" "$c" "$(printf '%s' "$pkg" | tr '/' '_')" > "$FIX_OUT/conventions_$c.out" 2>&1; then
        # Vert ou non applicable (outil absent du projet) : le second se dit, il n'est pas « conforme ».
        if grep -q '^\[N/A\]' "$FIX_OUT/conventions_$c.out"; then
          info "$pkg : $c non applicable ($(grep -m1 '^\[N/A\]' "$FIX_OUT/conventions_$c.out" | sed 's/^\[N\/A\][[:space:]]*//'))"
          FIX_NA="$FIX_NA $c@$pkg"
        else info "$pkg : $c conforme"; fi
        continue
      fi
      grep -E '✗|\[FAIL\]' "$FIX_OUT/conventions_$c.out" | sed 's/^/  /'
      ko "$pkg : $c"; rc=1
    done
  done <<< "$pkgs"
  return $rc
}

check_review_report() {
  local f="$FIX_DIR/review.json"
  [ -f "$f" ] || { ko "review.json absent — le reviewer doit produire ${f#$PROJECT_ROOT/}"; return 1; }
  jq -e '(.critical|type=="array") and (.suggestions|type=="array") and (.missing_tests|type=="array") and (.root_cause_addressed|IN("yes","no","partial")) and (.plan_respected|IN("yes","no","partial"))' "$f" >/dev/null 2>&1 \
    || { ko "review.json invalide : critical[], suggestions[], missing_tests[], root_cause_addressed (yes|no|partial), plan_respected (yes|no|partial)"; return 1; }
  local incomplete; incomplete="$(jq -r '[.suggestions | to_entries[] | select(([.value | .id,.summary,.problem,.why,.cause,.consequences,.fix,.pros,.cons] | map(type=="string" and length>0) | all | not) or ((.value.effort|IN("S","M","L"))|not)) | (.value.id // "#\(.key+1)")] | join(", ")' "$f")"
  [ -z "$incomplete" ] || { ko "suggestions incomplètes ($incomplete) : id, summary, problem, why, cause, consequences, fix, pros, cons, effort (S|M|L) — voir ~/.claude/pipeline/suggestions.md"; return 1; }
  info "critiques : $(jq '.critical|length' "$f"), suggestions : $(jq '.suggestions|length' "$f"), cause racine traitée : $(jq -r .root_cause_addressed "$f"), plan respecté : $(jq -r .plan_respected "$f")"
}

check_review_verdict() {
  check_review_report || return 1
  local f="$FIX_DIR/review.json" n
  n="$(jq '[.critical[] | select(.accepted != true)] | length' "$f")"
  [ "$n" = 0 ] && return 0
  jq -r '.critical[] | select(.accepted != true) | "   ✗ \(.file):\(.line // "?") [\(.rule // "-")] \(.summary)"' "$f"
  ko "$n finding(s) critique(s) → retour à l'implementer"
  return 1
}

# fix_after <profil> <nom> — au rapport (hand-back) d'un agent, dans le même tour : attend que le hook de fin de
# son gate ait démarré puis fini, et, gate rouge, que l'agent renvoyé au travail ait un nouveau verdict. Ni le
# rapport suivant ni la notification de fin ne relancent un tour à coup sûr (cas réel : gate green de Fanny
# passé, Victor jamais lancé). Budget FIX_WAIT_MAX (540 s, tient dans un appel Bash de 600 s).
# Exit 0 : verdict lu (PASSED, FAILED, ou aucun hook vu) ; 4 : budget épuisé, relance la même commande.
fix_after() {
  local p="$1" t0 seen=0 st at left
  [ -n "$p" ] && [ -n "$2" ] || die "usage: fix_gauntlet.sh after <profil> <nom>"
  fix_context "$2" || die "pas dans un repo git"
  [ -f "$STATE" ] || die "fix inconnu : $STATE"
  t0="$(date +%s)"
  left() { echo $(( ${FIX_WAIT_MAX:-540} - ($(date +%s) - t0) )); }
  # Le rapport peut précéder le démarrage du hook de quelques secondes.
  while [ $(( $(date +%s) - t0 )) -le "${FIX_AFTER_WAIT:-30}" ]; do
    at="$(jq -r --arg p "$p" '.stages[$p].at // empty | fromdateiso8601' "$STATE" 2>/dev/null)"
    if [ -f "$FIX_OUT/hook_$p.running" ] || { [ -n "$at" ] && [ "$at" -ge $((t0 - 120)) ]; }; then seen=1; break; fi
    sleep 1
  done
  if [ "$seen" = 0 ]; then
    echo "hook      : aucun hook de fin vu pour $p en ${FIX_AFTER_WAIT:-30} s — rejoue le gate (fix_gauntlet.sh $p $FIX_NAME) et dis-le ; ne relance pas l'agent"
    return 0
  fi
  local said=0
  while :; do
    bash "$SCRIPTS/hook_wait.sh" "$FIX_OUT" "$(( $(left) > 5 ? $(left) : 5 ))" 2>/dev/null
    st="$(state_get ".stages[\"$p\"].status")"
    [ "$st" != RED ] && [ ! -f "$FIX_OUT/hook_$p.running" ] && break
    if [ "$said" = 0 ]; then echo "agent au travail : $p rouge, renvoyé au travail par son hook — j'attends son prochain verdict" >&2; said=1; fi
    if [ "$(left)" -le 5 ]; then
      echo "hook      : $p toujours rouge après ${FIX_WAIT_MAX:-540} s (tentative $(state_get ".attempts[\"$p\"]")) — l'agent travaille encore : relance la même commande, dans ce tour ; ne relance pas l'agent"
      return 4
    fi
    sleep 2
  done
  case "$st" in
    PASSED) echo "hook      : $p = PASSED — lance l'étape suivante, dans ce tour" ;;
    FAILED) echo "hook      : $p FAILED après $(state_get ".attempts[\"$p\"]") tentatives — point imprévu : le dev décide (AskUserQuestion)" ;;
    *)      echo "hook      : $p = ${st:-vide} — le hook n'a rien écrit : rejoue le gate (fix_gauntlet.sh $p $FIX_NAME) et dis-le" ;;
  esac
}

# --- main ----------------------------------------------------------------------------------------
target="${1:-}"; name="${2:-}"
case "$target" in
  ""|-h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}"; exit 0 ;;
  list) profiles_list; exit 0 ;;
  after) fix_after "${2:-}" "${3:-}"; exit $? ;;
  watchdog) shift; exec python3 "$(dirname "${BASH_SOURCE[0]}")/fix/watchdog.py" "$@" ;;
  report) exec python3 "$SCRIPTS/report/report.py" fix "$name" "${3:-}" ;;
esac
[ -n "$name" ] || die "usage: fix_gauntlet.sh <profil|check> <nom>"
fix_context "$name" || die "pas dans un repo git"
[ -d "$FIX_DIR" ] || die "fix inconnu : $FIX_DIR"
mkdir -p "$FIX_OUT"
# Un hook de fin d'agent (fix-gate.sh) joue peut-être déjà ce gate : on attend qu'il ait fini.
bash "$SCRIPTS/hook_wait.sh" "$FIX_OUT" || exit 1

checks="$(profile_checks "$target")"
if [ -z "$checks" ]; then
  declare -F "check_$target" >/dev/null || die "profil ou check inconnu : $target"
  checks="$target"
fi
case "$target" in green|target_green|device_green) FIX_PHASE=green ;; *) FIX_PHASE=red ;; esac
FIX_SHOTS_DIR="$FIX_DIR/shots/$FIX_PHASE"

log="$FIX_OUT/last_${target}.log"; json="$FIX_OUT/last_${target}.json"
: > "$log"
{
  passed=""; failed=""; FIX_NA=""   # FIX_NA : checks non applicables (check@package), posés par conventions
  printf 'fix_gauntlet %s — fix %s — %s\n' "$target" "$FIX_NAME" "$(date '+%Y-%m-%d %H:%M:%S')"
  for c in $checks; do
    section "$c"
    "check_$c"; rc=$?
    if [ "$rc" = 0 ]; then ok "$c"; passed="$passed $c"
    elif [ "$rc" = "$NA_RC" ]; then printf '[N/A]  %s\n' "$c"; FIX_NA="$FIX_NA $c"
    else ko "$c"; failed="$failed $c"; fi
  done
  section "résumé $target"
  [ -n "$passed" ] && printf '  passés  :%s\n' "$passed"
  [ -n "$failed" ] && printf '  échoués :%s\n' "$failed"
  [ -n "$FIX_NA" ] && printf '  non applicables :%s\n' "$FIX_NA"
  jq -n --arg p "$target" --arg f "$FIX_NAME" --argjson ok "$([ -z "$failed" ] && echo true || echo false)" \
        --arg passed "$passed" --arg failed "$failed" --arg na "$FIX_NA" \
        '{profile:$p, fix:$f, ok:$ok, date:(now|todate),
          passed:($passed|split(" ")|map(select(.!=""))), failed:($failed|split(" ")|map(select(.!=""))),
          not_applicable:($na|split(" ")|map(select(.!="")))}' > "$json"
} 2>&1 | tee -a "$log"
[ "$(jq -r '.ok' "$json" 2>/dev/null)" = true ]
