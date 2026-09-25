#!/usr/bin/env bash
# checks_review.sh — rapports des agents de jugement (reviewer, dedup). Sourcé par gauntlet.sh.
#
# Deux checks par rapport, et la distinction compte :
#   *_report  : le fichier existe et a le bon schéma. C'est le gate du hook Stop de l'agent — un agent
#               qui trouve des problèmes doit pouvoir rendre la main, sinon on le bloque pour avoir
#               fait son travail.
#   *_verdict : aucun finding bloquant non accepté. C'est l'orchestrateur qui le lit, et qui boucle
#               vers l'implementer / l'architect / le cleaner.
#
# review.json : { critical:[{file,line,rule,summary,fix}], suggestions:[...], missing_tests:[{scenario,why}], rules_checked:{} }
# dedup.json  : { verdicts:[{target:{name,file,line}, existing:{name,file,line,package}, verdict:"duplicate|extend|distinct", reason, accepted?}] }

check_review_report() {
  local f="$FEATURE_DIR/review.json"
  [ -f "$f" ] || { ko "review.json absent — le reviewer doit produire ${f#$PROJECT_ROOT/}"; return 1; }
  jq -e 'has("critical") and has("suggestions") and has("missing_tests") and (.critical|type=="array")' "$f" >/dev/null 2>&1 \
    || { ko "review.json invalide : clés attendues critical, suggestions, missing_tests"; return 1; }
  info "critiques : $(jq '.critical|length' "$f"), suggestions : $(jq '.suggestions|length' "$f"), scénarios non couverts : $(jq '.missing_tests|length' "$f")"
}

check_review_verdict() {
  check_review_report || return 1
  local f="$FEATURE_DIR/review.json" n
  n="$(jq '[.critical[] | select(.accepted != true)] | length' "$f")"
  [ "$n" = 0 ] && return 0
  jq -r '.critical[] | select(.accepted != true) | "   ✗ \(.file):\(.line // "?") [\(.rule // "-")] \(.summary)"' "$f"
  ko "$n finding(s) critique(s) → retour à l'implementer"
  return 1
}

check_dedup_report() {
  local f="$FEATURE_DIR/dedup.json"
  [ -f "$f" ] || { ko "dedup.json absent — l'agent feature-dedup doit produire ${f#$PROJECT_ROOT/}"; return 1; }
  jq -e '.verdicts | type=="array" and all(.[]; .verdict | IN("duplicate","extend","distinct"))' "$f" >/dev/null 2>&1 \
    || { ko "dedup.json invalide : verdicts[].verdict ∈ duplicate|extend|distinct"; return 1; }
  info "paires jugées : $(jq '.verdicts|length' "$f") — doublons : $(jq '[.verdicts[]|select(.verdict=="duplicate")]|length' "$f"), à étendre : $(jq '[.verdicts[]|select(.verdict=="extend")]|length' "$f")"
}

check_dedup_verdict() {
  check_dedup_report || return 1
  local f="$FEATURE_DIR/dedup.json" n
  n="$(jq '[.verdicts[] | select((.verdict=="duplicate" or .verdict=="extend") and .accepted != true)] | length' "$f")"
  [ "$n" = 0 ] && return 0
  jq -r '.verdicts[] | select((.verdict=="duplicate" or .verdict=="extend") and .accepted != true) | "   ✗ \(.verdict): \(.target.name) (\(.target.file):\(.target.line)) ≈ \(.existing.package)/\(.existing.name) (\(.existing.file):\(.existing.line)) — \(.reason)"' "$f"
  ko "$n roue(s) réinventée(s) : utiliser ou étendre l'existant"
  return 1
}
