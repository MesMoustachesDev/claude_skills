#!/usr/bin/env bash
# pipeline-gate.sh — Stop (→ SubagentStop) déclaré dans le frontmatter des agents feature-*.
# L'agent ne peut pas rendre la main tant que le gauntlet de son étape est rouge. Après
# pipeline.max_attempts échecs, on le laisse sortir et l'étape passe en FAILED : l'orchestrateur
# appelle le dev au lieu de tourner en rond.
#
# Entrée (stdin, JSON) : agent_type, cwd
# Sortie : exit 0 = peut s'arrêter ; exit 2 + stderr = continue, la raison est montrée à l'agent
set -u
input="$(cat)"
agent="$(jq -r '.agent_type // empty' <<<"$input")"
cwd="$(jq -r '.cwd // empty' <<<"$input")"

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

GAUNTLET_ROOT="${PIPELINE_GAUNTLET_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts/gauntlet" && pwd)}"   # surcharge : tests du hook ; défaut : le gauntlet de ce checkout
GAUNTLET="$GAUNTLET_ROOT/../gauntlet.sh"
# shellcheck source=../scripts/gauntlet/lib.sh
source "$GAUNTLET_ROOT/lib.sh"
# Le worktree de la feature, pas le cwd hérité de la session (voir hook_feature_root).
root="$(hook_feature_root "$cwd" "" "$(hook_agent_transcript "$input")")" && cwd="$root"
cd "$cwd" 2>/dev/null || exit 0
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
feature="$(git branch --show-current 2>/dev/null | sed -n 's#^feature/##p')"
[ -n "$feature" ] || feature="$(cat "$PROJECT_ROOT/.claude/features/.current" 2>/dev/null)"
if [ -z "$feature" ]; then
  # Jamais « gate ignoré » en silence : l'agent le dit en tête de son rapport, l'orchestrateur rejoue le
  # gate lui-même. Une seule fois (stop_hook_active), sinon l'agent tournerait sans fin.
  [ "$(jq -r '.stop_hook_active // false' <<<"$input")" = true ] && exit 0
  echo "pipeline-gate : worktree de la feature introuvable (cwd $cwd, pas de « Racine : <worktree> » dans ton prompt) — gate '$profile' NON JOUÉ. Commence ton rapport final par « GATE NON JOUÉ ($profile) : worktree introuvable », puis termine." >&2
  exit 2
fi
case "$profile" in *_data|*_presentation) export GAUNTLET_LAYER="${profile##*_}" ;; esac   # sorties de la couche (log)
init_project_context "$feature" 2>/dev/null || { echo "pipeline-gate : contexte projet illisible, gate ignoré" >&2; exit 0; }

# Journal (ADR 0019) : gate rouge et FAILED, une ligne dans .gauntlet/hooks.jsonl ; jamais bloquant.
source "$GAUNTLET_ROOT/hook_log.sh"
gate_log() {   # gate_log <issue> <raison> [étape]
  local failed; failed="$(jq -r '(.failed // []) | join(" ")' "$GAUNTLET_OUT/last_${3:-$profile}.json" 2>/dev/null)"
  hook_log "$FEATURE_DIR" pipeline-gate "$agent" Stop "" "$1" "$2${failed:+ : $failed}" "${3:-$profile}"
}
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
# pipe_set <statut> <tentatives> — sous verrou : les deux moitiés des étapes 3 et 4 finissent parfois
# ensemble, et deux jq > tmp && mv simultanés perdent l'écriture de l'une.
pipe_set() {
  local lock="$PIPE.lock" i=0 tmp
  until mkdir "$lock" 2>/dev/null; do i=$((i+1)); [ "$i" -ge 100 ] && break; sleep 0.1; done
  tmp="$(mktemp)"
  jq --arg p "$profile" --arg s "$1" --argjson a "$2" '.attempts[$p]=$a | .stages[$p]={status:$s, at:(now|todate)}' "$PIPE" > "$tmp" && mv "$tmp" "$PIPE"
  rmdir "$lock" 2>/dev/null
}
# Marqueur « gate en cours » : le rapport de l'agent arrive à l'orchestrateur avant la fin de ce hook ;
# pipeline.sh next/join et gauntlet.sh attendent qu'il disparaisse (hook_wait.sh).
mkdir -p "$FEATURE_DIR/.gauntlet"
running="$FEATURE_DIR/.gauntlet/hook_${profile}.running"
echo "$$ $(date +%s) $agent" > "$running"
trap 'rm -f "$running"' EXIT
export PIPELINE_GATE_HOOK=1
attempts="$(jq -r --arg p "$profile" '.attempts[$p] // 0' "$PIPE")"

# QA: a run that already finished on the same state (commit + uncommitted changes) is not replayed, its
# verdict is reused. Flows can be single-use (they change server state) and the agent usually ran them itself.
[ "$profile" = qa ] && export GAUNTLET_QA_REUSE=1
if "$GAUNTLET" "$profile" "$feature" >/dev/null 2>&1; then
  pipe_set PASSED 0
  exit 0
fi

attempts=$((attempts+1))
log="$GAUNTLET_OUT/last_${profile}.log"
if [ "$attempts" -ge "$max" ]; then
  pipe_set FAILED "$attempts"
  gate_log failed "gate $profile rouge après $attempts tentatives, étape FAILED"
  {
    echo "pipeline-gate : gate '$profile' toujours rouge après $attempts tentatives. Étape marquée FAILED."
    echo "Arrête-toi et rends un rapport : ce qui bloque, ce que tu as essayé, ce que tu recommandes (spec ? test faux ? contrat ?)."
  } >&2
  exit 0
fi

pipe_set RED "$attempts"
gate_log red "gate $profile rouge (tentative $attempts/$max)"
{
  echo "GATE '$profile' ROUGE (tentative $attempts/$max) — tu ne peux pas t'arrêter tant que ce n'est pas vert."
  echo "Sortie du gauntlet (${log#$PROJECT_ROOT/}) :"
  echo "----------------------------------------------------------------"
  grep -vE '^\s*$' "$log" | tail -60
  echo "----------------------------------------------------------------"
  echo "Corrige, puis termine à nouveau : le gate se relancera automatiquement."
} >&2
exit 2
