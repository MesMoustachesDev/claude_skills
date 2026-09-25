#!/usr/bin/env bash
# profiles.sh — un profil par étape du pipeline. Un check peut prendre un mode après ":".
#
# L'ordre compte : les checks rapides d'abord, les coûteux (coverage, mutation, qa) sont sautés
# si un rapide a échoué.

# Maintenabilité que le cleaner peut corriger lui-même (voir checks_maintain.sh).
MAINTAIN_FIXABLE="deps_unused reinvented package_readme design_system l10n_strings l10n_arb barrel_api unused_code unused_files test_hygiene todo_tickets deprecated_api generated_fresh footprint no_secrets"

profile_checks() {
  case "$1" in
    contracts) echo "build_runner analyze deps stub_check reinvented package_readme" ;;
    dedup)     echo "dedup_report" ;;
    red)       echo "build_runner analyze red_check test_names" ;;
    green)     echo "test analyze format no_stubs no_temp_markers deps test_freeze_check:strict" ;;
    clean)     echo "test analyze format no_stubs no_temp_markers deps test_freeze_check:strict metrics $MAINTAIN_FIXABLE coverage" ;;
    maintain)  echo "$MAINTAIN_FIXABLE deps_features pub_health" ;;
    review)    echo "review_report" ;;
    harden)    echo "test analyze test_freeze_check:additive mutation" ;;
    qa)        echo "qa" ;;
    *)         echo "" ;;
  esac
}

profiles_list() {
  cat <<'EOF'
Profils (étape → checks) :
  contracts  build_runner analyze deps stub_check reinvented package_readme
  dedup      dedup_report           (hook de l'agent feature-dedup ; le verdict est lu par l'orchestrateur : dedup_verdict)
  red        build_runner analyze red_check test_names
  green      test analyze format no_stubs no_temp_markers deps test_freeze_check:strict
  clean      green + metrics + maintenabilité fixable + coverage
  maintain   maintenabilité complète (fixable + deps_features pub_health) — lu par le reviewer, utilisable en audit
  review     review_report          (hook du reviewer ; verdict : review_verdict)
  harden     test analyze test_freeze_check:additive mutation
  qa         qa

Checks individuels :
  analyze            flutter analyze --fatal-warnings sur le package
  format             dart format --set-exit-if-changed lib test
  build_runner       build_runner build si le package le déclare (json_serializable, bdd_widget_test)
  deps               direction des dépendances entre couches + pureté du domain
  stub_check         après ARCHITECT : chaque méthode d'impl est un throw UnimplementedError
  no_stubs           après IMPLEMENTER : plus aucun UnimplementedError dans lib/
  no_temp_markers    aucun marqueur TEMP / print( dans lib/ et test/
  test               flutter test (rapport JSON conservé)
  red_check          après TEST-WRITER : chaque fichier de test a ≥ 1 échec
  test_names         écrit .claude/features/<f>/tests.md (liste lisible pour le skim humain)
  test_freeze_check  :strict = aucun changement dans test/ depuis le gel ; :additive = fichiers ajoutés seulement
  metrics            dart_code_linter : complexité, lignes, imbrication, paramètres
  coverage           couverture des lignes modifiées depuis base_branch
  mutation           mutation_test sur les globs configurés, score ≥ seuil
  review_report      review.json présent et valide        review_verdict   aucun critique non accepté
  dedup_report       dedup.json présent et valide         dedup_verdict    aucun duplicate/extend non accepté
  qa                 flows Maestro sur chaque plateforme, captures

Maintenabilité (checks_maintain.sh) :
  deps_unused        chaque dépendance déclarée est importée
  reinvented         roue réinventée : nom public déjà pris ailleurs, ou corps identique à renommage près (AST)
  dedup_candidates   produit dedup_candidates.json (déclarations ressemblantes du workspace) pour l'agent feature-dedup
  package_readme     README.md du package : sections (readme.sections) et chaque export du barrel nommé
  deps_features      dépendances inter-features justifiées dans la spec §8, aucun cycle dans le workspace
  pub_health         packages abandonnés / sans release depuis pub.max_age_months / majeure en retard
  design_system      pas de valeur visuelle brute (ds.forbidden), chaque vue importe le DS (ds.imports)
  l10n_strings       pas de chaîne utilisateur en dur dans la présentation
  l10n_arb           les clés ARB ajoutées existent dans toutes les locales (l10n.arb_glob)
  barrel_api         le barrel n'exporte ni src/data/ ni *_impl.dart
  unused_code        dart_code_linter check-unused-code
  unused_files       dart_code_linter check-unused-files
  test_hygiene       pas de skip:, Future.delayed, sleep(, print( dans test/
  todo_tickets       TODO/FIXME avec ticket (todo.pattern)
  deprecated_api     aucun deprecated_member_use
  generated_fresh    fichiers générés à jour et commités
  footprint          la feature ne touche que son package + writes.extra
  no_secrets         pas de secret ni d'email de test en clair (lib, test, maestro)
EOF
}
