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
# review.json : { critical:[{file,line,rule,summary,fix}], suggestions:[{id,summary,file,line,rule,problem,why,cause,
#                 consequences,fix,pros,cons,effort}] (pipeline/suggestions.md), missing_tests:[{scenario,why}], rules_checked:{},
#                 tour:[{layer,file,symbol,line,what,implements}] (visite guidée, 2 à 8 étapes),
#                 to_verify:[{id,claim,file,line,how,owner:"implementer|hardener",outcome?,note?}] (ADR 0002 : critique que
#                 le relecteur n'a pas prouvée ; l'orchestrateur écrit outcome "proved|dismissed" après Ivan ou Hugo) }
# dedup.json  : { verdicts:[{target:{name,file,line}, existing:{name,file,line,package}, verdict:"duplicate|extend|distinct", reason, accepted?}] }

check_review_report() {
  local f="$FEATURE_DIR/review.json"
  [ -f "$f" ] || { ko "review.json absent — le reviewer doit produire ${f#$PROJECT_ROOT/}"; return 1; }
  jq -e 'has("critical") and has("suggestions") and has("missing_tests") and (.critical|type=="array")' "$f" >/dev/null 2>&1 \
    || { ko "review.json invalide : clés attendues critical, suggestions, missing_tests"; return 1; }
  local incomplete; incomplete="$(jq -r '[.suggestions | to_entries[] | select(([.value | .id,.summary,.problem,.why,.cause,.consequences,.fix,.pros,.cons] | map(type=="string" and length>0) | all | not) or ((.value.effort|IN("S","M","L"))|not)) | (.value.id // "#\(.key+1)")] | join(", ")' "$f")"
  [ -z "$incomplete" ] || { ko "suggestions incomplètes ($incomplete) : id, summary, problem, why, cause, consequences, fix, pros, cons, effort (S|M|L) — voir ~/.claude/pipeline/suggestions.md"; return 1; }
  _to_verify_ok "$f" '"implementer","hardener"' || return 1
  # La visite guidée n'est exigée qu'à la passe qui rend critical vide (une passe avec critiques rend la main à Ivan).
  if jq -e '[.critical[] | select(.accepted != true)] | length == 0' "$f" >/dev/null 2>&1; then
    jq -e '(.tour|type=="array") and (.tour|length>=2 and length<=8) and all(.tour[]; type=="object" and (.file|type=="string") and (.what|type=="string") and (.what|length>0))' "$f" >/dev/null 2>&1 \
      || { ko "review.json : tour absent ou invalide — 2 à 8 étapes {layer, file, symbol, line, what, implements} dans l'ordre du flux de données (exigé dès que critical est vide)"; return 1; }
  fi
  info "critiques : $(jq '.critical|length' "$f"), suggestions : $(jq '.suggestions|length' "$f"), scénarios non couverts : $(jq '.missing_tests|length' "$f"), à vérifier : $(jq '(.to_verify // [])|length' "$f"), dette : $(jq '(.debt // [])|length' "$f"), visite : $(jq '(.tour // [])|length' "$f") étapes"
}

# _to_verify_ok <fichier> <owners jq, ex. '"implementer","hardener"'> — `to_verify` (optionnel) : critiques que le
# relecteur n'a pas prouvées en lisant le code ou en rejouant un test existant (ADR 0002). Chacune dit ce qu'il
# faudrait lancer (`how`) et à qui elle va (`owner`) ; `outcome` est écrit par l'orchestrateur, jamais par le relecteur.
_to_verify_ok() {
  local bad
  jq -e '(.to_verify // []) | type=="array"' "$1" >/dev/null 2>&1 || { ko "${1##*/} : to_verify doit être une liste"; return 1; }
  bad="$(jq -r --argjson owners "[$2]" '[(.to_verify // []) | to_entries[] | select(
      ([.value | .id, .claim, .how] | map(type=="string" and length>0) | all | not)
      or ((.value.owner // "") as $o | $owners | index($o) | not)
      or (.value.outcome != null and (.value.outcome | IN("proved","dismissed") | not))
    ) | (.value.id // "#\(.key+1)")] | join(", ")' "$1" 2>/dev/null)"
  [ -z "$bad" ] || { ko "${1##*/} : to_verify incomplet ($bad) : id, claim, how (la commande ou le test qui la prouverait), owner ∈ $2 ; outcome, s'il est là, ∈ proved|dismissed"; return 1; }
}

# _to_verify_open <fichier> <owner> — les entrées de to_verify de cet owner sans outcome, une ligne chacune
_to_verify_open() {
  jq -r --arg o "$2" '(.to_verify // [])[] | select(.owner == $o and .outcome == null) | "   ? \(.id) \(.file // "-"):\(.line // "?") \(.claim) — à lancer : \(.how)"' "$1"
}

check_review_verdict() {
  check_review_report || return 1
  local f="$FEATURE_DIR/review.json" n v h rc=0
  n="$(jq '[.critical[] | select(.accepted != true)] | length' "$f")"
  v="$(jq '[(.to_verify // [])[] | select(.owner == "implementer" and .outcome == null)] | length' "$f")"
  h="$(jq '[(.to_verify // [])[] | select(.owner == "hardener" and .outcome == null)] | length' "$f")"
  if [ "$n" != 0 ]; then
    jq -r '.critical[] | select(.accepted != true) | "   ✗ \(.file):\(.line // "?") [\(.rule // "-")] \(.summary)"' "$f"
    ko "$n finding(s) critique(s) → retour à l'implementer"; rc=1
  fi
  if [ "$v" != 0 ]; then
    _to_verify_open "$f" implementer
    ko "$v critique(s) à vérifier → Ivan : la prouver par un probe ou l'écarter (outcome dans review.json)"; rc=1
  fi
  # Celles de Hugo ne bloquent pas la revue : elles partent à l'étape 7 avec missing_tests.
  [ "$h" != 0 ] && { _to_verify_open "$f" hardener; info "$h critique(s) à vérifier → Hugo (étape 7), avec missing_tests"; }
  return $rc
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
  local f="$FEATURE_DIR/dedup.json" n deferred open
  # Before the implementation (1d), only stubs exist: a finding whose fix means
  # writing real code (fix_by: cleaner) is carried to the cleaner, and blocks again at 5b.
  open='(.verdict=="duplicate" or .verdict=="extend") and .accepted != true'
  if [ "$(pipeline_get .stages.green.status)" != PASSED ]; then
    deferred="$(jq "[.verdicts[] | select($open and .fix_by == \"cleaner\")] | length" "$f")"
    if [ "$deferred" != 0 ]; then
      jq -r ".verdicts[] | select($open and .fix_by == \"cleaner\") | \"   → reporté au cleaner : \(.target.name) ≈ \(.existing.name) — \(.reason)\"" "$f"
      info "$deferred verdict(s) reporté(s) au cleaner, revérifié(s) en 5b"
    fi
    open="$open and .fix_by != \"cleaner\""
  fi
  n="$(jq "[.verdicts[] | select($open)] | length" "$f")"
  [ "$n" = 0 ] && return 0
  jq -r ".verdicts[] | select($open) | \"   ✗ \(.verdict): \(.target.name) (\(.target.file):\(.target.line)) ≈ \(.existing.package)/\(.existing.name) (\(.existing.file):\(.existing.line)) — \(.reason)\"" "$f"
  ko "$n roue(s) réinventée(s) : utiliser ou étendre l'existant"
  return 1
}

# spec_review.json  : { blocking:[{section,issue,fix,owner?:"spec|thibault"}], notes:[{section,issue}] }   (agent feature-spec-critic)
# tests_review.json : { blocking:[{file,line,test,issue,fix}], notes:[...], coverage:{scenario:"tested|missing"},
#                       to_verify:[{id,claim,file,line,how,owner:"test-writer",outcome?,note?}] }  (agent feature-test-reviewer)

_report_ok() { # _report_ok <file> <label> <jq-schema>
  [ -f "$1" ] || { ko "$2 absent — l'agent doit produire ${1#$PROJECT_ROOT/}"; return 1; }
  jq -e "$3" "$1" >/dev/null 2>&1 || { ko "$2 invalide (schéma)"; return 1; }
}
_verdict_ok() { # _verdict_ok <file> <label> <message>
  local n; n="$(jq '[.blocking[] | select(.accepted != true)] | length' "$1")"
  [ "$n" = 0 ] && return 0
  jq -r '.blocking[] | select(.accepted != true) | "   ✗ [\(.section // .file // "-")] \(.issue)"' "$1"
  ko "$n point(s) bloquant(s) — $3"
  return 1
}

# spec_lint — avant Camille, gate du hook de Sophie : ce qu'un script vérifie sans relecture (clés, une
# scène par erreur de §7, symboles cités, archi.json ↔ §4, plafond du gabarit). Voir spec_lint.py.
# Sans spec.md (cadrage, exploration), rien à vérifier. Avant les contrats de Thibault (ADR 0015 : scénarios
# d'abord), phase « scenarios » : symboles, membres et clés n'existent pas encore.
check_spec_lint() {
  local spec="$FEATURE_DIR/spec.md" archi="$FEATURE_DIR/archi.json" cap
  [ -f "$spec" ] || { info "pas encore de spec.md, rien à vérifier"; return 0; }
  [ -f "$archi" ] || archi=-
  case "$SIZE" in S) cap=15360 ;; L) cap=0 ;; *) cap=40960 ;; esac
  # Les symboles se cherchent dans les sources du langage du package. Flutter : sous features_root ; ailleurs
  # (Android : modules ui, app, core à côté des features), dans tout le repo.
  local ext ws="$PROJECT_ROOT/$(cfg features_root features)"
  ext="$(bash "$STACK_SH" get extensions "$PKG_DIR" 2>/dev/null | tr -d ' ')"
  case "$ext" in ''|.dart) ;; *) ws="$PROJECT_ROOT" ;; esac
  local phase=full
  jq -e '.human_gates.contracts' "$FEATURE_DIR/pipeline.json" >/dev/null 2>&1 || phase=scenarios
  SPEC_LINT_PHASE="$phase" SPEC_LINT_EXT="${ext:-.dart}" python3 "$GAUNTLET_ROOT/spec_lint.py" "$spec" "$PKG_DIR" "$ws" "$archi" "$cap"
}

check_spec_review_report()  { _report_ok "$FEATURE_DIR/spec_review.json" "spec_review.json" '(.blocking|type=="array") and (.notes|type=="array")' && info "bloquants : $(jq '.blocking|length' "$FEATURE_DIR/spec_review.json"), notes : $(jq '.notes|length' "$FEATURE_DIR/spec_review.json")"; }
check_spec_review_verdict() {
  check_spec_review_report || return 1
  local f="$FEATURE_DIR/spec_review.json" n
  # owner "thibault" : le correctif est un contrat écrit par le dev. Il bloque comme les autres, mais
  # ne relance pas le specifier : le dev le tranche au point d'étape « scénarios » (ou en 1f pour un contrat) (accepted + raison).
  local t
  n="$(jq '[.blocking[] | select(.accepted != true and .owner != "thibault")] | length' "$f")"
  t="$(jq '[.blocking[] | select(.accepted != true and .owner == "thibault")] | length' "$f")"
  [ "$n" = 0 ] && [ "$t" = 0 ] && return 0
  jq -r '.blocking[] | select(.accepted != true and .owner != "thibault") | "   ✗ [\(.section // "-")] \(.issue)"' "$f"
  jq -r '.blocking[] | select(.accepted != true and .owner == "thibault") | "   ✗ pour Thibault [\(.section // "-")] \(.issue)"' "$f"
  [ "$n" != 0 ] && ko "$n point(s) bloquant(s) — retour au specifier"
  [ "$t" != 0 ] && ko "$t contrat(s) à trancher par Thibault au point d'étape « scénarios » (ou en 1f pour un contrat)"
  return 1
}

check_tests_review_report()  { _report_ok "$FEATURE_DIR/tests_review.json" "tests_review.json" '(.blocking|type=="array") and (.notes|type=="array") and (.coverage|type=="object")' && _to_verify_ok "$FEATURE_DIR/tests_review.json" '"test-writer"' && info "bloquants : $(jq '.blocking|length' "$FEATURE_DIR/tests_review.json"), scénarios sans test : $(jq '[.coverage[]|select(.=="missing")]|length' "$FEATURE_DIR/tests_review.json"), à vérifier : $(jq '(.to_verify // [])|length' "$FEATURE_DIR/tests_review.json")"; }
check_tests_review_verdict() {
  check_tests_review_report || return 1
  local f="$FEATURE_DIR/tests_review.json" v rc=0
  _verdict_ok "$f" "tests_review" "retour au test-writer" || rc=1
  v="$(jq '[(.to_verify // [])[] | select(.outcome == null)] | length' "$f")"
  if [ "$v" != 0 ]; then
    _to_verify_open "$f" test-writer
    ko "$v point(s) à vérifier → Théo : le prouver (test rejoué, probe) ou l'écarter (outcome dans tests_review.json)"; rc=1
  fi
  return $rc
}
