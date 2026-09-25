#!/usr/bin/env bash
# profiles.sh — un profil par étape du pipeline. Un check peut prendre un mode après ":".
#
# L'ordre compte : les checks rapides d'abord, les coûteux (coverage, mutation, qa) sont sautés
# si un rapide a échoué.

profile_checks() {
  case "$1" in
    contracts) echo "build_runner analyze deps stub_check" ;;
    red)       echo "build_runner analyze red_check test_names" ;;
    green)     echo "test analyze format no_stubs no_temp_markers deps test_freeze_check:strict" ;;
    clean)     echo "test analyze format no_stubs no_temp_markers deps test_freeze_check:strict metrics coverage" ;;
    review)    echo "review" ;;
    harden)    echo "test analyze test_freeze_check:additive mutation" ;;
    qa)        echo "qa" ;;
    *)         echo "" ;;
  esac
}

profiles_list() {
  cat <<'EOF'
Profils (étape → checks) :
  contracts  build_runner analyze deps stub_check
  red        build_runner analyze red_check test_names
  green      test analyze format no_stubs no_temp_markers deps test_freeze_check:strict
  clean      green + metrics coverage
  review     review
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
  review             review.json du reviewer présent et sans finding critique
  qa                 flows Maestro sur chaque plateforme, captures
EOF
}
