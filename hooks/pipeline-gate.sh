#!/usr/bin/env bash
# pipeline-gate.sh — Stop (→ SubagentStop) déclaré dans le frontmatter des agents feature-*.
# L'agent ne peut pas rendre la main tant que le gauntlet de son étape est rouge. Après
# pipeline.max_attempts échecs, on le laisse sortir et l'étape passe en FAILED : l'orchestrateur
# appelle l'humain au lieu de tourner en rond.
#
# Entrée (stdin, JSON) : agent_type, cwd
# Sortie : exit 0 = peut s'arrêter ; exit 2 + stderr = continue, la raison est montrée à l'agent
set -u
input="$(cat)"
agent="$(jq -r '.agent_type // empty' <<<"$input")"
cwd="$(jq -r '.cwd // empty' <<<"$input")"

case "$agent" in
  feature-architect)   profile=contracts ;;
  feature-test-writer) profile=red ;;
  feature-implementer) profile=green ;;
  feature-cleaner)     profile=clean ;;
  feature-reviewer)    profile=review ;;   # format du rapport seulement ; le verdict est lu par l'orchestrateur
  feature-dedup)       profile=dedup ;;    # idem
  feature-hardener)    profile=harden ;;
  feature-qa)          profile=qa ;;
  *) exit 0 ;;
esac

GAUNTLET="$HOME/.claude/scripts/gauntlet.sh"
GAUNTLET_ROOT="$HOME/.claude/scripts/gauntlet"
# shellcheck source=../scripts/gauntlet/lib.sh
source "$GAUNTLET_ROOT/lib.sh"
cd "$cwd" 2>/dev/null || exit 0
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
feature="$(git branch --show-current 2>/dev/null | sed -n 's#^feature/##p')"
[ -n "$feature" ] || feature="$(cat "$PROJECT_ROOT/.claude/features/.current" 2>/dev/null)"
[ -n "$feature" ] || { echo "pipeline-gate : feature courante inconnue, gate ignoré" >&2; exit 0; }
init_project_context "$feature" 2>/dev/null || { echo "pipeline-gate : contexte projet illisible, gate ignoré" >&2; exit 0; }

PIPE="$FEATURE_DIR/pipeline.json"
[ -f "$PIPE" ] || echo '{}' > "$PIPE"
max="$(cfg pipeline.max_attempts 5)"
attempts="$(jq -r --arg p "$profile" '.attempts[$p] // 0' "$PIPE")"

if "$GAUNTLET" "$profile" "$feature" >/dev/null 2>&1; then
  tmp="$(mktemp)"; jq --arg p "$profile" '.attempts[$p]=0 | .stages[$p]={status:"PASSED", at:(now|todate)}' "$PIPE" > "$tmp" && mv "$tmp" "$PIPE"
  exit 0
fi

attempts=$((attempts+1))
log="$GAUNTLET_OUT/last_${profile}.log"
if [ "$attempts" -ge "$max" ]; then
  tmp="$(mktemp)"; jq --arg p "$profile" --argjson a "$attempts" '.attempts[$p]=$a | .stages[$p]={status:"FAILED", at:(now|todate)}' "$PIPE" > "$tmp" && mv "$tmp" "$PIPE"
  {
    echo "pipeline-gate : gate '$profile' toujours rouge après $attempts tentatives. Étape marquée FAILED."
    echo "Arrête-toi et rends un rapport : ce qui bloque, ce que tu as essayé, ce que tu recommandes (spec ? test faux ? contrat ?)."
  } >&2
  exit 0
fi

tmp="$(mktemp)"; jq --arg p "$profile" --argjson a "$attempts" '.attempts[$p]=$a | .stages[$p]={status:"RED", at:(now|todate)}' "$PIPE" > "$tmp" && mv "$tmp" "$PIPE"
{
  echo "GATE '$profile' ROUGE (tentative $attempts/$max) — tu ne peux pas t'arrêter tant que ce n'est pas vert."
  echo "Sortie du gauntlet (${log#$PROJECT_ROOT/}) :"
  echo "----------------------------------------------------------------"
  grep -vE '^\s*$' "$log" | tail -60
  echo "----------------------------------------------------------------"
  echo "Corrige, puis termine à nouveau : le gate se relancera automatiquement."
} >&2
exit 2
