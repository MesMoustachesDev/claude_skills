#!/usr/bin/env bash
# pipeline-restrict-writes.sh — PreToolUse (Edit|Write|MultiEdit|NotebookEdit|Bash) déclaré dans le
# frontmatter des agents feature-*. Chaque agent n'écrit que dans sa zone. Tout le reste est refusé
# avec une raison lisible par l'agent.
#
# Entrée (stdin, JSON) : agent_type, cwd, scratchpad_dir, tool_name, tool_input.file_path | .command
# Sortie : rien (pas de décision) ou {"hookSpecificOutput":{"permissionDecision":"deny",...}}
#
# Bash : les fichiers que la commande écrit (redirection, sed -i, tee, cp…, cf. bash_write_targets.py)
# passent par la même zone, sauf ceux hors du worktree (journaux dans /tmp). Cas réel : Hugo,
# refactor_feature, un Edit refusé refait en `sed -i`. Le gauntlet (test_freeze_check) reste le
# filet pour ce que l'extraction ne voit pas (python -c, scripts).
set -u
set -f   # pas d'expansion des globs de config par le shell : ce sont des motifs pour `case`
input="$(cat)"
agent="$(jq -r '.agent_type // empty' <<<"$input")"
[[ "$agent" == feature-* ]] || exit 0            # hors pipeline : pas de décision

cwd="$(jq -r '.cwd // empty' <<<"$input")"
scratch="$(jq -r '.scratchpad_dir // empty' <<<"$input")"
tool="$(jq -r '.tool_name // empty' <<<"$input")"
GAUNTLET_ROOT="${PIPELINE_GAUNTLET_ROOT:-$HOME/.claude/scripts/gauntlet}"   # surcharge : tests du hook
if [ "$tool" = Bash ]; then
  targets="$(jq -r '.tool_input.command // empty' <<<"$input" | python3 "$GAUNTLET_ROOT/bash_write_targets.py" "${cwd:-$PWD}")"
else
  targets="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")"
fi
[ -n "$targets" ] || exit 0
file="${targets%%$'\n'*}"

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}
# Contexte illisible : Edit/Write refusés ; Bash laissé passer (un `> /tmp/log` n'a pas besoin de la
# feature, et le gate reste le filet).
ctx_deny() { [ "$tool" = Bash ] && exit 0; deny "$1"; }

# --- contexte projet (réutilise le gauntlet) --------------------------------------------------
# shellcheck source=../scripts/gauntlet/lib.sh
source "$GAUNTLET_ROOT/lib.sh"
# Le worktree de la feature, pas le cwd : un sous-agent hérite du cwd de la session, qui peut être le
# checkout principal (session ouverte sur le projet, reprise) — la branche y est develop et tout serait
# refusé, ou contourné par Bash. Le fichier écrit, puis le cwd, puis la racine du prompt de l'agent.
root="$(hook_feature_root "$cwd" "$file" "$(hook_agent_transcript "$input")")" && cwd="$root"
cd "$cwd" 2>/dev/null || exit 0
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
feature="$(git branch --show-current 2>/dev/null | sed -n 's#^feature/##p')"
[ -n "$feature" ] || feature="$(cat "$PROJECT_ROOT/.claude/features/.current" 2>/dev/null)"
[ -n "$feature" ] || ctx_deny "pipeline : feature courante inconnue (branche feature/<nom> ou .claude/features/.current)"
# Create mode before Arthur's scaffold: the package does not exist yet and init_project_context would die
# (exit 2 inside the function, so `|| deny` never runs and every write is blocked). Only the specifier
# (cadrage, spec) and the architect (scaffold) may write until the package exists.
pkg_planned="$(jq -r '.package // empty' "$PROJECT_ROOT/.claude/features/$feature/pipeline.json" 2>/dev/null)"
pkg_planned="${pkg_planned%/}"
if [ -n "$pkg_planned" ] && [ ! -d "$PROJECT_ROOT/$pkg_planned" ]; then
  case "$agent" in
    feature-specifier|feature-architect) ;;
    *) ctx_deny "pipeline : le package $pkg_planned n'existe pas encore (mode create, avant le scaffold d'Arthur)." ;;
  esac
  CFG_FILE="${GAUNTLET_CFG:-$PROJECT_ROOT/.claude/rules/feature_pipeline.md}"
  [ -f "$CFG_FILE" ] || ctx_deny "pipeline : contexte projet illisible (feature_pipeline.md ?)"
  PKG_REL="$pkg_planned"
else
  init_project_context "$feature" 2>/dev/null || ctx_deny "pipeline : contexte projet illisible (feature_pipeline.md ?)"
fi

# chemin absolu canonique (le fichier ou ses dossiers parents peuvent ne pas exister encore)
normalize() {
  local p="$1" rest=""
  case "$p" in /*) ;; *) p="$cwd/$p" ;; esac
  while [ ! -d "$p" ] && [ "$p" != "/" ]; do rest="/$(basename "$p")$rest"; p="$(dirname "$p")"; done
  printf '%s%s' "$(cd "$p" && pwd -P)" "$rest"
}
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd -P)"

FEAT_REL=".claude/features/$feature"
FEATURE_DIR="${FEATURE_DIR:-$PROJECT_ROOT/$FEAT_REL}"
extra="$(writes_extra | tr '\n' ' ')"   # zones supplémentaires : config projet (router, l10n…) + pipeline.json de la feature

# match <chemin> <glob>... — case avec * traversant /
match() { local p="$1"; shift; local g; for g in "$@"; do g="${g//\*\*/\*}"; case "$p" in $g) return 0;; esac; done; return 1; }

# Les packages ouverts par writes.extra (`<pkg>/lib/**`, appelants adaptés par la feature) ont aussi leurs
# tests dans le périmètre : `<pkg>/test/**`, et leur pubspec.yaml pour une dev_dependency de test.
# A whole package opened as `<pkg>/**` (folder holding a pubspec.yaml) counts the same way: its test/ is a
# test path (frozen for the implementer and the cleaner, open to the test-writer).
extra_tests="$(printf '%s\n' $extra | sed -n -e 's#/lib/\*\*$#/test/*#p' -e 's#/test/\*\*$#/test/*#p' | tr '\n' ' ')"
extra_pubspecs="$(printf '%s\n' $extra | sed -n 's#/lib/\*\*$#/pubspec.yaml#p' | tr '\n' ' ')"
for g in $extra; do
  case "$g" in */lib/\*\*|*/test/\*\*) continue ;; */\*\*) ;; *) continue ;; esac
  [ -f "$PROJECT_ROOT/${g%/\*\*}/pubspec.yaml" ] || continue
  extra_tests="$extra_tests${g%/\*\*}/test/* "; extra_pubspecs="$extra_pubspecs${g%/\*\*}/pubspec.yaml "
done
is_test_path() { match "$rel" "$PKG_REL/test/*" "*.feature" $extra_tests; }
# Un test présent au gel (pipeline.json → tests_freeze_sha) : figé pour Hugo. Ceux qu'il a créés depuis
# restent les siens : il les corrige avec Edit, sans détour par sed.
freeze_sha="$(jq -r '.tests_freeze_sha // empty' "$FEATURE_DIR/pipeline.json" 2>/dev/null)"
is_frozen() { [ -n "$freeze_sha" ] && git -C "$PROJECT_ROOT" cat-file -e "$freeze_sha:$rel" 2>/dev/null; }
via=""; [ "$tool" = Bash ] && via=" (écriture par Bash : même zone que Edit/Write ; un refus ne se contourne pas, il se rapporte)"

# check <fichier> — décide pour un fichier ; deny sort du hook au premier refus.
check() {
  local file="$1" abs
  abs="$(normalize "$file")"
  [ -n "$scratch" ] && [[ "$abs" == "$scratch"/* ]] && return 0     # brouillons : toujours permis
  if [[ "$abs" != "$PROJECT_ROOT"/* ]]; then
    [ "$tool" = Bash ] && return 0                                  # journaux, /tmp : hors zone, hors sujet
    deny "pipeline : écriture hors du worktree de la feature refusée ($file). Le worktree est $PROJECT_ROOT : écris sous ce chemin."
  fi
  rel="${abs#$PROJECT_ROOT/}"
case "$agent" in
  feature-specifier)
    match "$rel" "$FEAT_REL/*" || deny "specifier : n'écrit que dans $FEAT_REL/ (spec.md). Le code vient après validation.$via"
    ;;
  feature-architect)
    is_test_path && deny "architect : les tests sont écrits par le test-writer, pas par toi.$via"
    match "$rel" "$PKG_REL/lib/*" "$PKG_REL/pubspec.yaml" "$PKG_REL/README.md" "$PKG_REL/maestro/*" "pubspec.yaml" $extra \
      || deny "architect : zone autorisée = $PKG_REL/lib/**, $PKG_REL/README.md, pubspec.yaml${extra:+, $extra}. Refusé : $rel$via"
    ;;
  feature-test-writer)
    match "$rel" "$PKG_REL/test/*" "$PKG_REL/pubspec.yaml" "$FEAT_REL/tests.md" $extra_tests $extra_pubspecs \
      || deny "test-writer : tu n'écris que dans $PKG_REL/test/**${extra_tests:+, $extra_tests} (et pubspec.yaml pour les dev_dependencies). Si un contrat manque, signale-le, ne le crée pas. Refusé : $rel$via"
    ;;
  # Moitiés parallèles des étapes 3 et 4 : chacune n'écrit que sa couche, l'autre écrit le reste en même
  # temps. data = src/data, src/domain, src/injection ; presentation = le reste du package (et writes.extra :
  # router, l10n). Le pubspec n'est ouvert qu'aux tests de présentation (dev_dependency bdd_widget_test).
  feature-test-writer-data)
    match "$rel" "$PKG_REL/test/src/data/*" "$PKG_REL/test/src/domain/*" "$PKG_REL/test/src/injection/*" \
      || deny "test-writer data : tu n'écris que dans $PKG_REL/test/src/{data,domain,injection}/**. Le BLoC, l'acceptation et le pubspec sont à la moitié présentation, qui écrit en même temps que toi. Si un contrat manque, signale-le, ne le crée pas. Refusé : $rel$via"
    ;;
  feature-test-writer-presentation)
    match "$rel" "$PKG_REL/test/src/data/*" "$PKG_REL/test/src/domain/*" "$PKG_REL/test/src/injection/*" \
      && deny "test-writer présentation : $PKG_REL/test/src/{data,domain,injection}/** est à la moitié data, qui écrit en même temps que toi. Refusé : $rel$via"
    match "$rel" "$PKG_REL/test/*" "$PKG_REL/pubspec.yaml" $extra_tests $extra_pubspecs \
      || deny "test-writer présentation : tu n'écris que dans $PKG_REL/test/** hors src/{data,domain,injection}${extra_tests:+, $extra_tests} (et pubspec.yaml pour les dev_dependencies). Si un contrat manque, signale-le, ne le crée pas. Refusé : $rel$via"
    ;;
  feature-implementer-data)
    is_test_path && deny "implementer data : les tests sont GELÉS. Si un test est faux, dis-le dans ton rapport final ; ne le modifie pas. Refusé : $rel$via"
    match "$rel" "$PKG_REL/lib/src/data/*" "$PKG_REL/lib/src/domain/*" "$PKG_REL/lib/src/injection/*" \
      || deny "implementer data : zone autorisée = $PKG_REL/lib/src/{data,domain,injection}/**. La présentation est à l'autre moitié ; une dépendance nouvelle (pubspec) est une décision d'architecture à rapporter. Refusé : $rel$via"
    ;;
  feature-implementer-presentation)
    is_test_path && deny "implementer présentation : les tests sont GELÉS. Si un test est faux, dis-le dans ton rapport final ; ne le modifie pas. Refusé : $rel$via"
    match "$rel" "$PKG_REL/lib/src/data/*" "$PKG_REL/lib/src/domain/*" "$PKG_REL/lib/src/injection/*" \
      && deny "implementer présentation : $PKG_REL/lib/src/{data,domain,injection}/** est à la moitié data, qui écrit en même temps que toi. Tu ne dépends que des signatures des use cases. Refusé : $rel$via"
    match "$rel" "$PKG_REL/lib/*" $extra \
      || deny "implementer présentation : zone autorisée = $PKG_REL/lib/** hors src/{data,domain,injection}${extra:+, $extra}. Une dépendance nouvelle (pubspec) est une décision d'architecture à rapporter. Refusé : $rel$via"
    ;;
  feature-implementer|feature-cleaner)
    is_test_path && deny "${agent#feature-} : les tests sont GELÉS. Si un test est faux, dis-le dans ton rapport final ; ne le modifie pas. Refusé : $rel$via"
    # Nina retire une dépendance ou déplace un fichier : le README du package le dit (cas réel, par sed).
    readme=""; [ "$agent" = feature-cleaner ] && readme="$PKG_REL/README.md"
    match "$rel" "$PKG_REL/lib/*" "$PKG_REL/pubspec.yaml" "pubspec.yaml" $readme $extra \
      || deny "${agent#feature-} : zone autorisée = $PKG_REL/lib/**, pubspec.yaml${readme:+, $readme}${extra:+, $extra}. Refusé : $rel$via"
    ;;
  feature-hardener)
    if is_test_path; then
      is_frozen && deny "hardener : $rel est un test gelé (gel $freeze_sha) : il ne se modifie pas. Tue le mutant dans un NOUVEAU fichier test/**/*_mutation_test.dart ; ceux que tu as créés, tu les corriges avec Edit.$via"
      return 0
    fi
    match "$rel" "$PKG_REL/lib/*" "$FEAT_REL/mutants.md" $extra_pubspecs \
      || deny "hardener : zone autorisée = nouveaux fichiers de test, $PKG_REL/lib/** (rare), $FEAT_REL/mutants.md, pubspec.yaml des packages de writes.extra. Refusé : $rel$via"
    ;;
  feature-reviewer)
    match "$rel" "$FEAT_REL/review.md" "$FEAT_REL/review.json" \
      || deny "reviewer : lecture seule. Tu n'écris que $FEAT_REL/review.md et review.json. Refusé : $rel$via"
    ;;
  feature-dedup)
    match "$rel" "$FEAT_REL/dedup.md" "$FEAT_REL/dedup.json" \
      || deny "dedup : lecture seule. Tu n'écris que $FEAT_REL/dedup.md et dedup.json. Refusé : $rel$via"
    ;;
  feature-spec-critic)
    match "$rel" "$FEAT_REL/spec_review.md" "$FEAT_REL/spec_review.json" \
      || deny "spec-critic : lecture seule. Tu n'écris que $FEAT_REL/spec_review.md et spec_review.json — pas la spec elle-même. Refusé : $rel$via"
    ;;
  feature-test-reviewer)
    match "$rel" "$FEAT_REL/tests_review.md" "$FEAT_REL/tests_review.json" \
      || deny "test-reviewer : lecture seule. Tu n'écris que $FEAT_REL/tests_review.md et tests_review.json — jamais un test. Refusé : $rel$via"
    ;;
  feature-polisher)
    is_test_path && deny "polisher : les tests sont GELÉS, clés et Semantics comprises. Un test qui gêne le polish se signale dans polish.md. Refusé : $rel$via"
    match "$rel" "$PKG_REL/lib/src/presentation/*" "$FEAT_REL/polish.md" "$FEAT_REL/polish/*" $extra \
      || deny "polisher : zone autorisée = $PKG_REL/lib/src/presentation/**, $FEAT_REL/polish.md, $FEAT_REL/polish/**${extra:+, $extra}. La logique, le domain et la data ne bougent pas au polish. Refusé : $rel$via"
    ;;
  feature-qa)
    match "$rel" "$FEAT_REL/qa/*" "$FEAT_REL/qa.md" "$PKG_REL/maestro/*" \
      || deny "qa : zone autorisée = $PKG_REL/maestro/** et $FEAT_REL/qa/. Un bug trouvé se rapporte dans qa.md, il ne se corrige pas ici. Refusé : $rel$via"
    ;;
  *) return 0 ;;
esac
}

while IFS= read -r t; do [ -n "$t" ] && check "$t"; done <<<"$targets"
exit 0
