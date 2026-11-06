#!/usr/bin/env bash
# checks.sh — les checks du gauntlet propres à Flutter. Sourcé par gauntlet.sh (stack_load_checks), après les
# checks communs de scripts/gauntlet/checks_*.sh, quand le package est du Flutter (scripts/stack.sh detect) :
# une fonction check_<nom> d'ici remplace la commune du même nom. Un check d'ici qu'un autre langage n'a pas
# est « non applicable » pour lui (run_checks).
#
#   checks_static.sh    analyze, format, build_runner, deps, error_handling, stub_check, no_stubs,
#                       no_temp_markers, metrics (dart_code_linter)
#   checks_test.sh      test, red_check, test_names, coverage, mutation (mutation_test)
#   checks_test_plan.sh test_plan, test_plan_match (test_plan.py lit les *_test.dart et les .feature)
#   checks_test_dups.sh test_dups (test_dups.py lit les noms de test Dart)
#   checks_maintain.sh  deps_unused, deps_features, pub_health, design_system, widget_functions, l10n_strings,
#                       l10n_arb, barrel_api, unused_code, unused_files, test_hygiene, deprecated_api,
#                       generated_fresh, reinvented, dedup_candidates, package_readme
#   stack_doctor        ce que le doctor vérifie pour Flutter (SDK, fvm, outils pub, brick)
FLUTTER_CHECKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _f in checks_static.sh checks_test.sh checks_test_plan.sh checks_test_dups.sh checks_maintain.sh; do
  # shellcheck source=/dev/null
  source "$FLUTTER_CHECKS_DIR/$_f"
done
unset _f

# dart_version <dir> — la version de `$DART` lancé depuis <dir> (x.y.z), vide si introuvable.
dart_version() { (cd "$1" && $DART --version 2>&1) | sed -n 's/.*Dart SDK version: \([0-9][0-9.]*\).*/\1/p' | head -1; }

# doctor_dart_sdk — le SDK que voient les outils Dart du gauntlet (lancés depuis APP_ROOT) est celui du
# projet. Avec fvm : un .fvmrc doit être lisible depuis app_dir, sinon fvm retombe sans bruit sur son SDK
# global (vu : Dart 2.18 depuis la racine d'un repo dont l'app vit dans flutter_app/, et stub_check cassé).
doctor_dart_sdk() {
  local min seen pinned fv rc_file root_v
  min="$(sed -n 's/^[[:space:]]*sdk:[[:space:]]*["'"'"']\{0,1\}[\^>=]*\([0-9][0-9.]*\).*/\1/p' "$GAUNTLET_ROOT/dart_tools/pubspec.yaml" | head -1)"
  seen="$(dart_version "$APP_ROOT")"
  if [[ "$DART" == fvm* ]]; then
    rc_file="$(fvmrc_path)"
    need ".fvmrc lisible depuis app_dir ($(cfg app_dir .)) — sinon fvm retombe sur son SDK global" test -n "$rc_file"
    fv="$(fvm_pinned_version)"
    if [ -n "$fv" ]; then
      pinned="$("$HOME/fvm/versions/$fv/bin/dart" --version 2>&1 | sed -n 's/.*Dart SDK version: \([0-9][0-9.]*\).*/\1/p' | head -1)"
      need "SDK épinglé installé (fvm $fv) — fvm install $fv" test -n "$pinned"
      need "fvm dart depuis app_dir = SDK épinglé (vu : ${seen:-?}, attendu : ${pinned:-?})" test -n "$seen" -a "$seen" = "${pinned:-x}"
    fi
    if [ "$APP_ROOT" != "$PROJECT_ROOT" ]; then
      root_v="$(dart_version "$PROJECT_ROOT")"
      [ -n "$root_v" ] && [ "$root_v" != "$seen" ] && info "depuis la racine du repo, $DART résout Dart $root_v : aucune commande du gauntlet ne doit y tourner"
    fi
  fi
  need "Dart des outils du gauntlet ≥ ${min:-?} (vu depuis app_dir : ${seen:-?})" ver_ge "${seen:-0}" "${min:-0}"
}

stack_doctor() {
  # fvm resolves the SDK from the .fvmrc of the current directory or a parent: every dart/flutter command
  # that does not run inside a package (the gauntlet's Dart tools, pub global) runs from APP_ROOT.
  need "flutter ($FLUTTER)" sh -c "cd '$APP_ROOT' && $FLUTTER --version"
  need "dart ($DART)" sh -c "cd '$APP_ROOT' && $DART --version"
  doctor_dart_sdk
  local dcl mt
  dcl="$(cd "$APP_ROOT" && $DART pub global list 2>/dev/null | awk '/^dart_code_linter /{print $2}')"
  need "dart_code_linter ≥ 4.0 (${dcl:-absent}) — $DART pub global activate dart_code_linter" ver_ge "${dcl:-0}" 4.0
  mt="$(cd "$APP_ROOT" && $DART pub global list 2>/dev/null | awk '/^mutation_test /{print $2}')"
  need "mutation_test ≥ 1.8 (${mt:-absent}) — $DART pub global activate mutation_test" ver_ge "${mt:-0}" 1.8
  warn_if "mason (scaffold sans IA) — $DART pub global activate mason_cli" mason --version
  need "pub get dans scripts/gauntlet/dart_tools (outils dart du gauntlet)" sh -c "cd '$APP_ROOT' && $DART pub get -C '$GAUNTLET_ROOT/dart_tools'"
  # Le gate coverage écrit <package>/coverage/lcov.info : non ignoré, il finit dans un commit ou une revue.
  need ".gitignore ignore coverage/ (lcov du gate coverage) — /feature init" \
    git -C "$PROJECT_ROOT" check-ignore -q --no-index "$(cfg package_path | sed 's/{name}/x/')/coverage/lcov.info"
  case "$(cfg brick global)" in
    project) need "brick projet ./bricks/feature" test -f "$PROJECT_ROOT/bricks/feature/brick.yaml" ;;
    *)       need "brick global ~/.claude/bricks/flutter_feature" test -f "$HOME/.claude/bricks/flutter_feature/brick.yaml" ;;
  esac
}
