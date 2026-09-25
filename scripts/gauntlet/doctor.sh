#!/usr/bin/env bash
# doctor.sh — vérifie que le projet et la machine peuvent faire tourner le pipeline. Sourcé par gauntlet.sh.

DOCTOR_RC=0
need() { # need <label> <cmd...>
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$label"; else ko "$label"; DOCTOR_RC=1; fi
}
warn_if() { # warn_if <label> <cmd...>  (non bloquant)
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$label"; else printf '[WARN] %s\n' "$label"; fi
}
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

run_doctor() {
  section "outils"
  need "git"  git --version
  need "jq"   jq --version
  need "bash ≥ 4 ($BASH_VERSION)" ver_ge "${BASH_VERSION%%(*}" 4.0
  # shellcheck disable=SC2086
  need "flutter ($FLUTTER)" $FLUTTER --version
  # shellcheck disable=SC2086
  need "dart ($DART)" $DART --version
  local dcl mt
  dcl="$($DART pub global list 2>/dev/null | awk '/^dart_code_linter /{print $2}')"
  need "dart_code_linter ≥ 4.0 (${dcl:-absent}) — $DART pub global activate dart_code_linter" ver_ge "${dcl:-0}" 4.0
  mt="$($DART pub global list 2>/dev/null | awk '/^mutation_test /{print $2}')"
  need "mutation_test ≥ 1.8 (${mt:-absent}) — $DART pub global activate mutation_test" ver_ge "${mt:-0}" 1.8
  need "maestro" maestro --version
  warn_if "mason (scaffold sans IA) — $DART pub global activate mason_cli" mason --version

  section "outils dart du gauntlet"
  # shellcheck disable=SC2086
  need "pub get dans scripts/gauntlet/dart_tools" sh -c "cd '$PROJECT_ROOT' && $DART pub get -C '$GAUNTLET_ROOT/dart_tools'"

  section "configuration ($CFG_FILE)"
  need "package_path défini" test -n "$(cfg package_path)"
  need "base_branch existe ($BASE_BRANCH)" git -C "$PROJECT_ROOT" rev-parse --verify "$BASE_BRANCH"
  need "create_feature_rules.md présent" test -f "$PROJECT_ROOT/.claude/rules/create_feature_rules.md"
  case "$(cfg brick global)" in
    project) need "brick projet ./bricks/feature" test -f "$PROJECT_ROOT/bricks/feature/brick.yaml" ;;
    *)       need "brick global ~/.claude/bricks/flutter_feature" test -f "$HOME/.claude/bricks/flutter_feature/brick.yaml" ;;
  esac

  section "plateformes QA"
  for p in $(cfg_list qa.platforms); do
    case "$p" in
      android)
        need "adb" adb --version
        need "AVD '$(cfg android.avd)' existe" sh -c "'$HOME/Library/Android/sdk/emulator/emulator' -list-avds | grep -qx '$(cfg android.avd)'"
        need "android.app_id renseigné" sh -c "[ -n '$(cfg android.app_id)' ] && [ '$(cfg android.app_id)' != com.example.app ]"
        ;;
      ios)
        need "xcrun simctl" xcrun simctl help
        need "simulateur '$(cfg ios.simulator)' disponible" sh -c "xcrun simctl list devices available | grep -q '$(cfg ios.simulator) ('"
        need "ios.app_id renseigné" sh -c "[ -n '$(cfg ios.app_id)' ] && [ '$(cfg ios.app_id)' != com.example.app ]"
        ;;
      *) ko "plateforme inconnue : $p"; DOCTOR_RC=1 ;;
    esac
  done

  section "résumé"
  [ "$DOCTOR_RC" = 0 ] && ok "le projet peut faire tourner le pipeline" || ko "corriger les points ci-dessus avant /feature"
  return $DOCTOR_RC
}
