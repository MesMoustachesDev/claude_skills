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

run_doctor() {
  section "outils"
  need "git"  git --version
  need "jq"   jq --version
  need "bash ≥ 4 ($BASH_VERSION)" ver_ge "${BASH_VERSION%%(*}" 4.0
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
  need "maestro" maestro --version
  warn_if "mason (scaffold sans IA) — $DART pub global activate mason_cli" mason --version

  section "outils dart du gauntlet"
  need "pub get dans scripts/gauntlet/dart_tools" sh -c "cd '$APP_ROOT' && $DART pub get -C '$GAUNTLET_ROOT/dart_tools'"

  section "configuration ($CFG_FILE)"
  need "package_path défini" test -n "$(cfg package_path)"
  need "base_branch existe ($BASE_BRANCH)" git -C "$PROJECT_ROOT" rev-parse --verify "$BASE_BRANCH"
  need "create_feature_rules.md présent" test -f "$PROJECT_ROOT/.claude/rules/create_feature_rules.md"
  # Le gate coverage écrit <package>/coverage/lcov.info : non ignoré, il finit dans un commit ou une revue.
  need ".gitignore ignore coverage/ (lcov du gate coverage) — /feature init" \
    git -C "$PROJECT_ROOT" check-ignore -q --no-index "$(cfg package_path | sed 's/{name}/x/')/coverage/lcov.info"
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
