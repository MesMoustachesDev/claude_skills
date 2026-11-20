#!/usr/bin/env bash
# pipeline-gate.sh — Stop (→ SubagentStop) déclaré dans le frontmatter des agents feature-*.
# L'agent ne peut pas rendre la main tant que le gauntlet de son étape est rouge. Après
# pipeline.max_attempts échecs, on le laisse sortir et l'étape passe en FAILED : l'orchestrateur
# appelle le dev au lieu de tourner en rond.
#
# Entrée (stdin, JSON) : agent_type, cwd
# Sortie : exit 0 = peut s'arrêter ; exit 2 + stderr = continue, la raison est montrée à l'agent
set -u
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
hook_input
HOOK_NAME=pipeline-gate

case "$agent" in
  feature-architect)   profile=contracts ;;
  feature-specifier)   profile=spec_lint ;;       # vert sans spec.md (cadrage, exploration)
  feature-test-planner) profile=test_plan ;;
  feature-test-writer) profile=red ;;
  feature-implementer) profile=green ;;
  # Moitiés parallèles des étapes 3 et 4 : gate de leur couche ; le gate complet se joue après les deux
  # (pipeline.sh join).
  feature-test-writer-data|feature-test-writer-presentation) profile="red_${agent##*-}" ;;
  feature-implementer-data|feature-implementer-presentation) profile="green_${agent##*-}" ;;
  feature-cleaner)     profile=clean ;;
  feature-reviewer)      profile=review ;;        # format du rapport seulement ; le verdict est lu par l'orchestrateur
  feature-dedup)         profile=dedup ;;         # idem
  feature-spec-critic)   profile=spec_review ;;   # idem
  feature-test-reviewer) profile=tests_review ;;  # idem
  feature-hardener)    profile=harden ;;
  feature-qa)          profile=qa ;;
  feature-polisher)    profile=polish ;;
  *) exit 0 ;;
esac

GAUNTLET="$HOOK_SCRIPTS/gauntlet.sh"
# shellcheck source=../scripts/gauntlet/lib.sh
source "$GAUNTLET_ROOT/lib.sh"
# Le worktree de la feature, pas le cwd hérité de la session (voir hook_feature_root).
hook_run_root feature "$cwd" "" "$(hook_agent_transcript "$input")"
cwd="$HOOK_ROOT"
cd "$cwd" 2>/dev/null || exit 0
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
feature="$HOOK_RUN"
if [ -z "$feature" ]; then
  # Jamais « gate ignoré » en silence : l'agent le dit en tête de son rapport, l'orchestrateur rejoue le
  # gate lui-même. Une seule fois (stop_hook_active), sinon l'agent tournerait sans fin.
  [ "$(jq -r '.stop_hook_active // false' <<<"$input")" = true ] && exit 0
  echo "pipeline-gate : worktree de la feature introuvable (cwd $cwd, pas de « Racine : <worktree> » dans ton prompt) — gate '$profile' NON JOUÉ. Commence ton rapport final par « GATE NON JOUÉ ($profile) : worktree introuvable », puis termine." >&2
  exit 2
fi
case "$profile" in *_data|*_presentation) export GAUNTLET_LAYER="${profile##*_}" ;; esac   # sorties de la couche (log)
init_project_context "$feature" 2>/dev/null || { echo "pipeline-gate : contexte projet illisible, gate ignoré" >&2; exit 0; }

PIPE="$FEATURE_DIR/pipeline.json"
[ -f "$PIPE" ] || echo '{}' > "$PIPE"
max="$(cfg pipeline.max_attempts 5)"

# Théo avant son étape (lancé en 1c/1e pour réaligner un fake ou un appel qu'un contrat a cassé) : son gate
# n'est pas `red`, et stages.red n'est pas à lui. Il joue `analyze` (tout compile, tests compris) et n'écrit
# rien dans pipeline.json ; ses tentatives se comptent à part (.gauntlet/realign_attempts).
if [ "${profile%%_*}" = red ] && ! bash "$GAUNTLET_ROOT/../pipeline.sh" reached "$feature" red >/dev/null 2>&1; then
  mkdir -p "$FEATURE_DIR/.gauntlet"; count="$FEATURE_DIR/.gauntlet/realign_attempts"
  if env -u GAUNTLET_LAYER "$GAUNTLET" analyze "$feature" >/dev/null 2>&1; then rm -f "$count"; exit 0; fi
  n=$(( $(cat "$count" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$count"
  if [ "$n" -ge "$max" ]; then
    rm -f "$count"
    hook_log "$FEATURE_DIR" pipeline-gate "$agent" Stop "" failed "réalignement : analyze rouge après $n tentatives" realign
    echo "pipeline-gate : réalignement — analyze toujours rouge après $n tentatives. Arrête-toi et rapporte ce qui ne compile pas." >&2
    exit 0
  fi
  hook_log "$FEATURE_DIR" pipeline-gate "$agent" Stop "" red "réalignement : analyze rouge (tentative $n/$max)" realign
  {
    echo "RÉALIGNEMENT (avant l'étape 3) : analyze rouge (tentative $n/$max) — adapte les tests au contrat, ne change aucune assertion."
    echo "----------------------------------------------------------------"
    grep -vE '^\s*$' "$FEATURE_DIR/.gauntlet/last_analyze.log" 2>/dev/null | tail -40
    echo "----------------------------------------------------------------"
  } >&2
  exit 2
fi
# gate_set <statut> <tentatives> (appelé par gate_run) — sous le verrou de statefile.py (flock sur
# pipeline.json.lock), le même que pipeline.sh : les deux moitiés des étapes 3 et 4 finissent parfois ensemble, et un `pipeline.sh debt` peut
# tomber au même moment ; aucune écriture n'efface l'autre.
gate_set() {
  python3 "$GAUNTLET_ROOT/../statefile.py" jq "$PIPE" --arg p "$profile" --arg s "$1" --argjson a "$2" \
    '.attempts[$p]=$a | .stages[$p]={status:$s, at:(now|todate)}'
}
attempts="$(jq -r --arg p "$profile" '.attempts[$p] // 0' "$PIPE")"

# QA: a run that already finished on the same state (commit + uncommitted changes) is not replayed, its
# verdict is reused. Flows can be single-use (they change server state) and the agent usually ran them itself.
[ "$profile" = qa ] && export GAUNTLET_QA_REUSE=1
GATE_DIR="$FEATURE_DIR"; GATE_OUT="$GAUNTLET_OUT"
GATE_LOG_LABEL="Sortie du gauntlet"; GATE_FAILED_HINT=" (spec ? test faux ? contrat ?)"
gate_run "$GAUNTLET" "$profile" "$feature"
