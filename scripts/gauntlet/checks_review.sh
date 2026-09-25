#!/usr/bin/env bash
# checks_review.sh — gate de l'agent reviewer. Sourcé par gauntlet.sh.
#
# Le reviewer écrit .claude/features/<f>/review.json :
#   { "critical": [ {file, line, rule, summary} ], "suggestions": [...], "missing_tests": [...], "rules_checked": n }
# Le gate est vert si le fichier existe, est valide, et n'a aucun finding critique.
# Les critiques renvoient à l'implementer (orchestrateur), missing_tests est transmis au hardener.

check_review() {
  local f="$FEATURE_DIR/review.json" n
  [ -f "$f" ] || { ko "review.json absent — le reviewer doit produire ${f#$PROJECT_ROOT/}"; return 1; }
  jq -e 'has("critical") and has("suggestions") and has("missing_tests")' "$f" >/dev/null 2>&1 \
    || { ko "review.json invalide : clés attendues critical, suggestions, missing_tests"; return 1; }
  n="$(jq '.critical | length' "$f")"
  info "critiques : $n, suggestions : $(jq '.suggestions | length' "$f"), scénarios non couverts : $(jq '.missing_tests | length' "$f")"
  if [ "$n" -gt 0 ]; then
    jq -r '.critical[] | "   ✗ \(.file):\(.line // "?") [\(.rule // "-")] \(.summary)"' "$f"
    return 1
  fi
}
