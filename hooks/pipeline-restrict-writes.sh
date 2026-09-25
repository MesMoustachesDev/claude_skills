#!/usr/bin/env bash
# pipeline-restrict-writes.sh — PreToolUse (Edit|Write|MultiEdit|NotebookEdit) déclaré dans le
# frontmatter des agents feature-*. Chaque agent n'écrit que dans sa zone. Tout le reste est refusé
# avec une raison lisible par l'agent.
#
# Entrée (stdin, JSON) : agent_type, cwd, scratchpad_dir, tool_input.file_path
# Sortie : rien (pas de décision) ou {"hookSpecificOutput":{"permissionDecision":"deny",...}}
#
# Ce hook ferme le chemin facile. Le gauntlet (test_freeze_check) ferme les autres (sed dans Bash…).
set -u
set -f   # pas d'expansion des globs de config par le shell : ce sont des motifs pour `case`
input="$(cat)"
agent="$(jq -r '.agent_type // empty' <<<"$input")"
[[ "$agent" == feature-* ]] || exit 0            # hors pipeline : pas de décision

file="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")"
[ -n "$file" ] || exit 0
cwd="$(jq -r '.cwd // empty' <<<"$input")"
scratch="$(jq -r '.scratchpad_dir // empty' <<<"$input")"
tool="$(jq -r '.tool_name // empty' <<<"$input")"

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# --- contexte projet (réutilise le gauntlet) --------------------------------------------------
GAUNTLET_ROOT="$HOME/.claude/scripts/gauntlet"
# shellcheck source=../scripts/gauntlet/lib.sh
source "$GAUNTLET_ROOT/lib.sh"
cd "$cwd" 2>/dev/null || exit 0
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
feature="$(git branch --show-current 2>/dev/null | sed -n 's#^feature/##p')"
[ -n "$feature" ] || feature="$(cat "$PROJECT_ROOT/.claude/features/.current" 2>/dev/null)"
[ -n "$feature" ] || deny "pipeline : feature courante inconnue (branche feature/<nom> ou .claude/features/.current)"
init_project_context "$feature" 2>/dev/null || deny "pipeline : contexte projet illisible (feature_pipeline.md ?)"

# chemin absolu canonique (le fichier ou ses dossiers parents peuvent ne pas exister encore)
normalize() {
  local p="$1" rest=""
  case "$p" in /*) ;; *) p="$cwd/$p" ;; esac
  while [ ! -d "$p" ] && [ "$p" != "/" ]; do rest="/$(basename "$p")$rest"; p="$(dirname "$p")"; done
  printf '%s%s' "$(cd "$p" && pwd -P)" "$rest"
}
abs="$(normalize "$file")"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd -P)"
[ -n "$scratch" ] && [[ "$abs" == "$scratch"/* ]] && exit 0     # brouillons : toujours permis
[[ "$abs" == "$PROJECT_ROOT"/* ]] || deny "pipeline : écriture hors du projet refusée ($file)"
rel="${abs#$PROJECT_ROOT/}"

FEAT_REL=".claude/features/$feature"
extra="$(cfg_list writes.extra | tr '\n' ' ')"   # zones supplémentaires (router, l10n…), config projet

# match <chemin> <glob>... — case avec * traversant /
match() { local p="$1"; shift; local g; for g in "$@"; do g="${g//\*\*/\*}"; case "$p" in $g) return 0;; esac; done; return 1; }

is_test_path() { match "$rel" "$PKG_REL/test/*" "*.feature"; }

case "$agent" in
  feature-specifier)
    match "$rel" "$FEAT_REL/*" || deny "specifier : n'écrit que dans $FEAT_REL/ (spec.md). Le code vient après validation."
    ;;
  feature-architect)
    is_test_path && deny "architect : les tests sont écrits par le test-writer, pas par toi."
    match "$rel" "$PKG_REL/lib/*" "$PKG_REL/pubspec.yaml" "$PKG_REL/maestro/*" "pubspec.yaml" $extra \
      || deny "architect : zone autorisée = $PKG_REL/lib/**, pubspec.yaml${extra:+, $extra}. Refusé : $rel"
    ;;
  feature-test-writer)
    match "$rel" "$PKG_REL/test/*" "$PKG_REL/pubspec.yaml" \
      || deny "test-writer : tu n'écris que dans $PKG_REL/test/** (et pubspec.yaml pour les dev_dependencies). Si un contrat manque, signale-le, ne le crée pas. Refusé : $rel"
    ;;
  feature-implementer|feature-cleaner)
    is_test_path && deny "${agent#feature-} : les tests sont GELÉS. Si un test est faux, dis-le dans ton rapport final ; ne le modifie pas. Refusé : $rel"
    match "$rel" "$PKG_REL/lib/*" "$PKG_REL/pubspec.yaml" "pubspec.yaml" $extra \
      || deny "${agent#feature-} : zone autorisée = $PKG_REL/lib/**, pubspec.yaml${extra:+, $extra}. Refusé : $rel"
    ;;
  feature-hardener)
    if is_test_path; then
      [ "$tool" = Write ] || deny "hardener : les tests existants ne se modifient pas. Tue le mutant dans un NOUVEAU fichier test/**/*_mutation_test.dart."
      [ -e "$abs" ] && deny "hardener : $rel existe déjà. Les tests gelés ne se réécrivent pas ; crée un nouveau fichier *_mutation_test.dart."
      exit 0
    fi
    match "$rel" "$PKG_REL/lib/*" "$FEAT_REL/mutants.md" \
      || deny "hardener : zone autorisée = nouveaux fichiers de test, $PKG_REL/lib/** (rare), $FEAT_REL/mutants.md. Refusé : $rel"
    ;;
  feature-reviewer)
    match "$rel" "$FEAT_REL/review.md" "$FEAT_REL/review.json" \
      || deny "reviewer : lecture seule. Tu n'écris que $FEAT_REL/review.md et review.json. Refusé : $rel"
    ;;
  feature-dedup)
    match "$rel" "$FEAT_REL/dedup.md" "$FEAT_REL/dedup.json" \
      || deny "dedup : lecture seule. Tu n'écris que $FEAT_REL/dedup.md et dedup.json. Refusé : $rel"
    ;;
  feature-spec-critic)
    match "$rel" "$FEAT_REL/spec_review.md" "$FEAT_REL/spec_review.json" \
      || deny "spec-critic : lecture seule. Tu n'écris que $FEAT_REL/spec_review.md et spec_review.json — pas la spec elle-même. Refusé : $rel"
    ;;
  feature-test-reviewer)
    match "$rel" "$FEAT_REL/tests_review.md" "$FEAT_REL/tests_review.json" \
      || deny "test-reviewer : lecture seule. Tu n'écris que $FEAT_REL/tests_review.md et tests_review.json — jamais un test. Refusé : $rel"
    ;;
  feature-qa)
    match "$rel" "$FEAT_REL/qa/*" "$FEAT_REL/qa.md" "$PKG_REL/maestro/*" \
      || deny "qa : zone autorisée = $PKG_REL/maestro/** et $FEAT_REL/qa/. Un bug trouvé se rapporte dans qa.md, il ne se corrige pas ici. Refusé : $rel"
    ;;
  *) exit 0 ;;
esac
exit 0
