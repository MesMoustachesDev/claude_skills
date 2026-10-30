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

GAUNTLET_ROOT="${PIPELINE_GAUNTLET_ROOT:-$HOME/.claude/scripts/gauntlet}"   # surcharge : tests du hook
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

PIPE="$FEATURE_DIR/pipeline.json"
[ -f "$PIPE" ] || echo '{}' > "$PIPE"
# pipe_set <statut> <tentatives> — sous verrou : les deux moitiés des étapes 3 et 4 finissent parfois
# ensemble, et deux jq > tmp && mv simultanés perdent l'écriture de l'une.
pipe_set() {
  local lock="$PIPE.lock" i=0 tmp
  until mkdir "$lock" 2>/dev/null; do i=$((i+1)); [ "$i" -ge 100 ] && break; sleep 0.1; done
  tmp="$(mktemp)"
  jq --arg p "$profile" --arg s "$1" --argjson a "$2" '.attempts[$p]=$a | .stages[$p]={status:$s, at:(now|todate)}' "$PIPE" > "$tmp" && mv "$tmp" "$PIPE"
  rmdir "$lock" 2>/dev/null
}
max="$(cfg pipeline.max_attempts 5)"
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
  {
    echo "pipeline-gate : gate '$profile' toujours rouge après $attempts tentatives. Étape marquée FAILED."
    echo "Arrête-toi et rends un rapport : ce qui bloque, ce que tu as essayé, ce que tu recommandes (spec ? test faux ? contrat ?)."
  } >&2
  exit 0
fi

pipe_set RED "$attempts"
{
  echo "GATE '$profile' ROUGE (tentative $attempts/$max) — tu ne peux pas t'arrêter tant que ce n'est pas vert."
  echo "Sortie du gauntlet (${log#$PROJECT_ROOT/}) :"
  echo "----------------------------------------------------------------"
  grep -vE '^\s*$' "$log" | tail -60
  echo "----------------------------------------------------------------"
  echo "Corrige, puis termine à nouveau : le gate se relancera automatiquement."
} >&2
exit 2
