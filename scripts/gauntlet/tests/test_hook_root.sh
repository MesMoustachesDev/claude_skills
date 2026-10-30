#!/usr/bin/env bash
# Repro — hooks lancés depuis le checkout principal alors que la feature vit dans un worktree.
# Cas réel : refactor_feature (projet-client), sous-agents au cwd flutter_app/ (branche develop) :
# 24 refus « feature courante inconnue » chez 6 agents, spec écrite par `cat >` en Bash, gates « ignorés ».
#   hook d'écriture : le worktree vient du fichier écrit, sinon de « Racine : » dans le prompt de l'agent ;
#     écrire dans le checkout principal reste refusé, avec le chemin du worktree.
#   hook de gate : même résolution ; worktree introuvable → l'agent est retenu une fois (pas « ignoré »).
source "$(dirname "$0")/fixture.sh"
need_fvm

HOOKS="$TESTS_DIR/../../../hooks"
export PIPELINE_GAUNTLET_ROOT="$TESTS_DIR/.."
M="$TMP_ROOT/main"; mk_repo "$M"; write_cfg "$M"
P=app/features/feat
mk_pkg "$M/$P" feat
echo "int d() => 1;" > "$M/$P/lib/src/data/d.dart"
printf '.claude/worktrees/\n' > "$M/.gitignore"
commit "$M" "develop" >/dev/null
W="$M/.claude/worktrees/feature-x"
git -C "$M" worktree add -q "$W" -b feature/x
pipeline "$W" x "{\"mode\":\"create\",\"package\":\"$P\"}"
W="$(cd "$W" && pwd -P)"; M="$(cd "$M" && pwd -P)"

# Transcript du sous-agent : le prompt de l'orchestrateur, avec ou sans « Racine : ».
T="$TMP_ROOT/session"; mkdir -p "$T/subagents"
printf '{"type":"user","message":{"role":"user","content":"Sophie, étape 1. Racine : %s (branche feature/x)."}}\n' "$W" > "$T/subagents/agent-a1.jsonl"
printf '{"type":"user","message":{"role":"user","content":"Sophie, étape 1, sans racine."}}\n' > "$T/subagents/agent-a2.jsonl"

# hook <hook> <agent> <agent_id> <fichier ou ""> [stop_hook_active] — sortie dans $OUT, code dans $RC
hook() {
  OUT="$(jq -n --arg a "$2" --arg c "$M/app" --arg f "$4" --arg t "$T.jsonl" --arg id "$3" --argjson s "${5:-false}" \
    '{agent_type:$a, agent_id:$id, cwd:$c, transcript_path:$t, tool_name:"Write", tool_input:{file_path:$f}, stop_hook_active:$s}' \
    | bash "$HOOKS/$1" 2>&1)"; RC=$?
}

echo "hook d'écriture — cwd au checkout principal"
hook pipeline-restrict-writes.sh feature-specifier a2 "$W/.claude/features/x/spec.md"
expect_no_out deny "fichier dans le worktree : le worktree vient du fichier (prompt sans racine)"
hook pipeline-restrict-writes.sh feature-specifier a1 "$M/.claude/features/x/spec.md"
expect_out "hors du worktree" "fichier dans le checkout principal : refusé"
expect_out "$W" "le refus donne le chemin du worktree (tiré de la racine du prompt)"
hook pipeline-restrict-writes.sh feature-specifier a2 "$M/.claude/features/x/spec.md"
expect_out "feature courante inconnue" "sans racine ni fichier dans le worktree : refus inchangé"

echo "hook de gate — cwd au checkout principal"
hook pipeline-gate.sh feature-dedup a1 ""
expect_rc 2 "racine du prompt : le gate se joue (dedup.json absent → rouge)"
OUT="$(jq -r '.stages.dedup.status // "absent"' "$W/.claude/features/x/pipeline.json")"
expect_out "RED" "stages.dedup écrit dans le pipeline.json du worktree"
hook pipeline-gate.sh feature-dedup a2 ""
expect_rc 2 "worktree introuvable : l'agent est retenu, pas « gate ignoré »"
expect_out "GATE NON JOUÉ" "il doit le dire en tête de son rapport"
hook pipeline-gate.sh feature-dedup a2 "" true
expect_rc 0 "au second arrêt (stop_hook_active), il sort"

finish
