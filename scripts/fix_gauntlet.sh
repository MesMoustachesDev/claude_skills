#!/usr/bin/env bash
# fix_gauntlet.sh — gates déterministes du pipeline /fix. Indépendant de la stack : les commandes
# viennent de .claude/fixes/<nom>/repro.json, écrit par le reproducer et gelé avec les tests.
#
# Usage :
#   fix_gauntlet.sh <profil|check> <nom>
#   fix_gauntlet.sh list
#   fix_gauntlet.sh report <nom> [étape]   rapport HTML pour le dev (.claude/fixes/<nom>/report.html)
#
# Exit 0 si tout est vert, 1 sinon. Écrit .claude/fixes/<nom>/.gauntlet/last_<profil>.{log,json}.
# Les commandes de repro.json tournent depuis <racine>/<package>, avec :
#   FIX_SHOTS_DIR  dossier où déposer les captures (UI) — shots/red/ pendant red, shots/green/ pendant green
#   FIX_PHASE      red | green
set -u
set -o pipefail

source "$HOME/.claude/scripts/gauntlet/lib.sh"   # info ok ko die section
source "$HOME/.claude/scripts/fix/lib.sh"

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
  (device_red / device_green ne sont dans aucun profil : le simulateur est partagé avec d'autres sessions,
   l'orchestrateur les lance lui-même, un par un, après le go du dev — jamais un hook)
  review_report   review.json présent et valide (hook du reviewer)
  review_verdict  aucun critique non accepté (lu par l'orchestrateur)

Checks :
  repro_schema       repro.json : package, target_cmd, expected_failure, suite_cmd, test_files existants et reconnus comme tests, fix_plan
  only_tests_changed depuis base_sha : uniquement tests, manifestes (package.json/pubspec.yaml) et .claude/fixes/<nom>/
  no_debug_markers   aucun [DEBUG_ISSUE] dans le repo
  target_red         target_cmd échoue ET sa sortie contient expected_failure (rouge pour la bonne raison)
  freeze_check       depuis freeze_sha : aucun test ni repro.json modifié, aucun test ajouté
  source_changed     depuis freeze_sha : au moins un fichier hors tests a changé
  target_green       target_cmd passe
  suite_green        suite_cmd passe
  lint               lint_cmd passe (sauté si vide)
  conventions        design_system + l10n_strings du gauntlet feature sur les lignes modifiées de chaque package touché
                     (sauté sans .claude/rules/feature_pipeline.md)
  device_red         device_repro.cmd (le parcours du signalement, sur device) échoue avec device_repro.expected_failure
  device_green       device_repro.cmd passe
                     (les deux sautés seulement si device_repro.not_applicable donne une raison)
EOF
}

# run_in_pkg <label> <cmd> — exécute une commande de repro.json depuis le package, sortie dans $FIX_OUT/<label>.out
run_in_pkg() {
  local label="$1" cmd="$2" pkg out="$FIX_OUT/$1.out"
  pkg="$(repro_get .package)"; pkg="${pkg:-.}"
  mkdir -p "$FIX_SHOTS_DIR"
  (cd "$PROJECT_ROOT/$pkg" && FIX_SHOTS_DIR="$FIX_SHOTS_DIR" FIX_PHASE="$FIX_PHASE" bash -c "$cmd") > "$out" 2>&1
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
  local cmd; cmd="$(repro_get .lint_cmd)"
  [ -n "$cmd" ] || { info "pas de lint_cmd"; return 0; }
  run_in_pkg lint "$cmd" && return 0
  tail -30 "$FIX_OUT/lint.out" | sed 's/^/  /'
  ko "lint_cmd échoue"
  return 1
}

# conventions — the feature gauntlet's presentation checks, scoped to the lines this fix changed. A fix is
# held to the same design system and l10n rules as a feature, even on a line it only re-indents.
check_conventions() {
  [ -f "$PROJECT_ROOT/.claude/rules/feature_pipeline.md" ] || { info "pas de feature_pipeline.md : sauté"; return 0; }
  local base f d pkgs="" pkg c rc=0
  base="$(state_get .base_sha)"
  [ -n "$base" ] || { ko "fix.json → base_sha absent"; return 1; }
  while IFS= read -r f; do
    case "$f" in *.dart) ;; *) continue ;; esac
    is_test_path "$f" && continue
    d="$(dirname "$f")"
    while [ "$d" != . ] && [ ! -f "$PROJECT_ROOT/$d/pubspec.yaml" ]; do d="$(dirname "$d")"; done
    [ "$d" != . ] && pkgs="$pkgs"$'\n'"$d"
  done < <(changed_since "$base")
  pkgs="$(printf '%s\n' "$pkgs" | grep -v '^$' | sort -u)"
  [ -n "$pkgs" ] || { info "aucun package Dart touché hors tests"; return 0; }
  while IFS= read -r pkg; do
    for c in design_system l10n_strings; do
      GAUNTLET_MODE=extend GAUNTLET_PACKAGE="$pkg" GAUNTLET_FEATURES_ROOT="$FIX_OUT/conventions" GAUNTLET_KEEP_FORMAT_LINES=1 \
        "$HOME/.claude/scripts/gauntlet.sh" "$c" "$(printf '%s' "$pkg" | tr '/' '_')" > "$FIX_OUT/conventions_$c.out" 2>&1 \
        && { info "$pkg : $c conforme"; continue; }
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

# --- main ----------------------------------------------------------------------------------------
target="${1:-}"; name="${2:-}"
case "$target" in
  ""|-h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}"; exit 0 ;;
  list) profiles_list; exit 0 ;;
  report) exec python3 "$HOME/.claude/scripts/report/report.py" fix "$name" "${3:-}" ;;
esac
[ -n "$name" ] || die "usage: fix_gauntlet.sh <profil|check> <nom>"
fix_context "$name" || die "pas dans un repo git"
[ -d "$FIX_DIR" ] || die "fix inconnu : $FIX_DIR"
mkdir -p "$FIX_OUT"

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
  passed=""; failed=""
  printf 'fix_gauntlet %s — fix %s — %s\n' "$target" "$FIX_NAME" "$(date '+%Y-%m-%d %H:%M:%S')"
  for c in $checks; do
    section "$c"
    if "check_$c"; then ok "$c"; passed="$passed $c"; else ko "$c"; failed="$failed $c"; fi
  done
  section "résumé $target"
  [ -n "$passed" ] && printf '  passés  :%s\n' "$passed"
  [ -n "$failed" ] && printf '  échoués :%s\n' "$failed"
  jq -n --arg p "$target" --arg f "$FIX_NAME" --argjson ok "$([ -z "$failed" ] && echo true || echo false)" \
        --arg passed "$passed" --arg failed "$failed" \
        '{profile:$p, fix:$f, ok:$ok, date:(now|todate),
          passed:($passed|split(" ")|map(select(.!=""))), failed:($failed|split(" ")|map(select(.!="")))}' > "$json"
} 2>&1 | tee -a "$log"
[ "$(jq -r '.ok' "$json" 2>/dev/null)" = true ]
