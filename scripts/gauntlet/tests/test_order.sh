#!/usr/bin/env bash
# Repro — ordre des étapes de /feature (ADR 0015 : les scénarios avant les contrats, les contrats en sortent).
#   pipeline.sh next : cadrage → 1 scénarios → 1c brouillon → 1d → 1e contrats → 1f §5 → 2 ;
#   une feature commencée dans l'ancien ordre reprend sans retour en arrière : spec validée après les contrats
#   → 1f sautée ; brouillon commité avant les scénarios → 1 d'abord, puis 1e, puis 1f ;
#   stages.contracts posé par le hook d'Arthur en 1c/1e ne passe pas pour l'étape 2 ; after-architect le déplace
#   vers contracts_draft tant que les contrats ne sont pas validés (la spec, elle, l'est déjà depuis l'ADR 0015).
source "$(dirname "$0")/fixture.sh"

PIPELINE_SH="$TESTS_DIR/../../pipeline.sh"
R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/x

# next_is <json de pipeline.json> <clé attendue> <libellé>
next_is() {
  pipeline "$R" x "$1"
  OUT="$(cd "$R" && bash "$PIPELINE_SH" next x --json 2>&1)"; RC=$?
  local key; key="$(jq -r '.key' <<<"$OUT" 2>/dev/null)"
  [ "$key" = "$2" ] && _pass "$3 → $2" || _fail "$3 → $key, attendu $2"
}
P='"mode":"create","package":"app/features/feat","size":"M"'
CAD='"cadrage":{"status":"PASSED","at":"2026-11-12T08:00:00Z"}'
SPEC='"spec":{"status":"PASSED","at":"2026-11-12T09:00:00Z"}'
DRAFT='"contracts_draft":{"status":"PASSED","at":"2026-11-12T10:00:00Z"},"dedup":{"status":"PASSED","at":"2026-11-12T10:05:00Z"}'
HG_SPEC_9='"spec":{"at":"2026-11-12T09:00:00Z","by":"user"}'
HG_CON_11='"contracts":{"at":"2026-11-12T11:00:00Z","by":"user"}'

echo "nouvel ordre"
next_is "{$P,\"stages\":{$CAD}}" spec "cadrage validé : les scénarios d'abord"
next_is "{$P,\"stages\":{$CAD,$SPEC},\"human_gates\":{$HG_SPEC_9}}" contracts_draft "scénarios validés : brouillon de contrats"
next_is "{$P,\"stages\":{$CAD,$SPEC,$DRAFT},\"human_gates\":{$HG_SPEC_9}}" hg.contracts "brouillon et dedup : Thibault écrit ses contrats"
next_is "{$P,\"stages\":{$CAD,$SPEC,$DRAFT},\"human_gates\":{$HG_SPEC_9,$HG_CON_11}}" spec_contracts "contrats écrits : §5 de la spec"
next_is "{$P,\"stages\":{$CAD,$SPEC,$DRAFT,\"spec_contracts\":{\"status\":\"PASSED\",\"at\":\"2026-11-12T11:30:00Z\"}},\"human_gates\":{$HG_SPEC_9,$HG_CON_11}}" contracts "§5 écrite : complétion (2)"

echo "hook d'Arthur en 1e : stages.contracts n'est pas l'étape 2"
next_is "{$P,\"stages\":{$CAD,$SPEC,$DRAFT,\"contracts\":{\"status\":\"PASSED\",\"at\":\"2026-11-12T10:30:00Z\"}},\"human_gates\":{$HG_SPEC_9}}" hg.contracts "stages.contracts entre scénarios et contrats ignoré"

echo "after-architect après le brouillon (1c) : scénarios validés, contrats pas encore"
pipeline "$R" x "{$P,\"stages\":{$CAD,$SPEC,\"contracts\":{\"status\":\"PASSED\",\"at\":\"2026-11-12T10:00:00Z\"}},\"human_gates\":{$HG_SPEC_9}}"
OUT="$(cd "$R" && bash "$PIPELINE_SH" after-architect x 2>&1)"; RC=$?
expect_rc 0 "after-architect"
OUT="$(jq -c '[.stages.contracts_draft.status, .stages.contracts]' "$R/.claude/features/x/pipeline.json")"
expect_out '["PASSED",null]' "stages.contracts devient stages.contracts_draft"
OUT="$(cd "$R" && bash "$PIPELINE_SH" next x --json 2>&1 | jq -r .key)"
expect_out "dedup" "next ne rejoue pas 1c"
echo "after-architect à l'étape 2 : contrats validés"
pipeline "$R" x "{$P,\"stages\":{$CAD,$SPEC,$DRAFT,\"contracts\":{\"status\":\"PASSED\",\"at\":\"2026-11-12T12:00:00Z\"}},\"human_gates\":{$HG_SPEC_9,$HG_CON_11}}"
OUT="$(cd "$R" && bash "$PIPELINE_SH" after-architect x 2>&1)"
expect_out "rien à déplacer" "stages.contracts reste à l'étape 2"
OUT="$(jq -r '.stages.contracts.status' "$R/.claude/features/x/pipeline.json")"
expect_out "PASSED" "stages.contracts intact"

echo "features commencées dans l'ancien ordre"
HG_CON_8='"contracts":{"at":"2026-11-12T08:30:00Z","by":"user"}'
next_is "{$P,\"stages\":{$CAD,$DRAFT},\"human_gates\":{$HG_CON_8}}" spec "contrats écrits, spec pas encore : la spec"
next_is "{$P,\"stages\":{$CAD,$SPEC,$DRAFT},\"human_gates\":{$HG_CON_8,$HG_SPEC_9}}" contracts "spec validée après les contrats : 1f sautée"
next_is "{$P,\"stages\":{$CAD,\"contracts_draft\":{\"status\":\"PASSED\",\"at\":\"2026-11-12T08:10:00Z\"}}}" spec "brouillon commité, contrats pas écrits : les scénarios d'abord"

finish
