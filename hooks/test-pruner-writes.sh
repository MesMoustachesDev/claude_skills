#!/usr/bin/env bash
# test-pruner-writes.sh — PreToolUse (Write) d'Élise (test-pruner) : elle propose, elle ne retire rien.
# Seule écriture permise : .claude/features/<nom>/prune_candidates.json.
jq -e '.tool_input.file_path // "" | test("/\\.claude/features/[^/]+/prune_candidates\\.json$")' >/dev/null && exit 0
echo "test-pruner : tu n'écris que .claude/features/<nom>/prune_candidates.json, jamais un test." >&2
exit 2
