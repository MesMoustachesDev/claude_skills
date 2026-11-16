#!/usr/bin/env bash
# Repro — contracts.files ne voyait que contract_globs (domain, clés, events, states). En mode extend, une interface
# que Thibault édite en 1e hors de ces motifs (une interface existante hors domain/, un fichier d'events d'un autre
# package de writes_extra) n'était pas protégée. Cas réel : une sous-feature Android, un constructeur de prompt
# dans le module téléphone et l'event analytics d'un autre module.
#   extend : les fichiers source que Thibault a édités entrent dans contracts.files (contracts.edited), pas ses
#            tests ; contracts-files les garde au recalcul ;
#   create : contrôle, seul contract_globs compte.
source "$(dirname "$0")/fixture.sh"
need_fvm

PIPELINE_SH="$TESTS_DIR/../../pipeline.sh"
F=app/features/feat; A=app/features/analytics

setup() { # setup <mode>
  R="$TMP_ROOT/repo-$1"; mk_repo "$R"; write_cfg "$R"
  mk_pkg "$R/$F" feat; mk_pkg "$R/$A" analytics
  mkdir -p "$R/$F/lib/src/export" "$R/$F/lib/src/domain" "$R/$A/lib"
  echo "abstract class PromptBuilder { String build(); }" > "$R/$F/lib/src/export/prompt_builder.dart"
  echo "abstract class AnalyticsEvent {}" > "$R/$A/lib/analytics_event.dart"
  commit "$R" "develop" >/dev/null
  git -C "$R" checkout -q -b feature/x
  pipeline "$R" x "{\"mode\":\"$1\",\"package\":\"$F\",\"writes_extra\":[\"$A/**\"]}"
  echo "abstract class Repo {}" > "$R/$F/lib/src/domain/repo.dart"
  OUT="$(cd "$R" && bash "$PIPELINE_SH" commit-contracts x draft 2>&1)"; RC=$?
  expect_rc 0 "commit-contracts draft ($1)"
  echo "abstract class PromptBuilder { String build(); String buildFor(int id); }" > "$R/$F/lib/src/export/prompt_builder.dart"
  echo "abstract class AnalyticsEvent { String get name; }" > "$R/$A/lib/analytics_event.dart"
  echo "void main() {}" > "$R/$F/test/prompt_builder_test.dart"
  OUT="$(cd "$R" && bash "$PIPELINE_SH" commit-contracts x thibault 2>&1)"; RC=$?
  expect_rc 0 "commit-contracts thibault ($1)"
  OUT="$(jq -r '.contracts.files | join(",")' "$R/.claude/features/x/pipeline.json")"
}

echo "extend : les fichiers édités par Thibault sont des contrats"
setup extend
expect_out "$F/lib/src/domain/repo.dart" "le contrat de domain/ reste"
expect_out "$F/lib/src/export/prompt_builder.dart" "l'interface hors domain/ est un contrat"
expect_out "$A/lib/analytics_event.dart" "le fichier d'events d'un autre package est un contrat"
expect_no_out "prompt_builder_test.dart" "un test n'est pas un contrat"
OUT="$(cd "$R" && bash "$PIPELINE_SH" contracts-files x 2>&1)"
expect_out "$F/lib/src/export/prompt_builder.dart" "contracts-files le garde au recalcul"

echo "create : contract_globs seulement"
setup create
expect_out "$F/lib/src/domain/repo.dart" "le contrat de domain/"
expect_no_out "prompt_builder.dart" "hors motifs : pas un contrat en create"
finish
