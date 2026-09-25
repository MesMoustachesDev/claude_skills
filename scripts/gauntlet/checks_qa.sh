#!/usr/bin/env bash
# checks_qa.sh — QA Maestro : build, install, flows par plateforme, captures. Sourcé par gauntlet.sh.
#
# Flows : <package>/maestro/*.yaml, un par scénario Gherkin. Variables injectées :
#   APP_ID          appId de la plateforme (android.app_id / ios.app_id)
#   SCREENSHOT_DIR  dossier absolu des captures (.claude/features/<f>/qa/<platform>/)
# Un flow écrit ses captures avec : - takeScreenshot: ${SCREENSHOT_DIR}/<scenario>

wait_until() { # wait_until <secondes> <cmd...>
  local t="$1"; shift
  while [ "$t" -gt 0 ]; do "$@" >/dev/null 2>&1 && return 0; sleep 2; t=$((t-2)); done
  return 1
}

qa_prepare_android() { # → QA_DEVICE
  local serial avd apk
  serial="$(cfg android.serial emulator-5554)"; avd="$(cfg android.avd)"
  if ! adb -s "$serial" get-state 2>/dev/null | grep -q device; then
    [ -n "$avd" ] || { ko "android.avd non configuré et $serial hors ligne"; return 1; }
    info "démarrage de l'AVD $avd"
    nohup "$HOME/Library/Android/sdk/emulator/emulator" -avd "$avd" -no-snapshot-load >"$GAUNTLET_OUT/emulator.log" 2>&1 &
    wait_until 180 sh -c "adb -s $serial shell getprop sys.boot_completed 2>/dev/null | grep -q 1" || { ko "l'émulateur n'a pas booté (voir .gauntlet/emulator.log)"; return 1; }
  fi
  adb -s "$serial" shell settings put global window_animation_scale 0 >/dev/null 2>&1
  adb -s "$serial" shell settings put global transition_animation_scale 0 >/dev/null 2>&1
  adb -s "$serial" shell settings put global animator_duration_scale 0 >/dev/null 2>&1
  info "build android : $(cfg android.build)"
  # shellcheck disable=SC2086
  (cd "$PROJECT_ROOT" && $(cfg android.build) >"$GAUNTLET_OUT/build_android.log" 2>&1) || { ko "build android échoué (voir .gauntlet/build_android.log)"; tail -20 "$GAUNTLET_OUT/build_android.log"; return 1; }
  apk="$PROJECT_ROOT/$(cfg android.apk)"
  [ -f "$apk" ] || { ko "APK introuvable : $apk"; return 1; }
  adb -s "$serial" install -r -d "$apk" >/dev/null 2>&1 || { ko "adb install échoué"; return 1; }
  QA_DEVICE="$serial"
}

qa_prepare_ios() { # → QA_DEVICE
  local sim udid app
  sim="$(cfg ios.simulator 'iPhone 16 Pro')"
  udid="$(xcrun simctl list devices available -j | jq -r --arg n "$sim" '.devices[][] | select(.name==$n) | .udid' | head -1)"
  [ -n "$udid" ] || { ko "simulateur '$sim' introuvable"; return 1; }
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  open -a Simulator >/dev/null 2>&1 || true
  wait_until 120 sh -c "xcrun simctl list devices -j | jq -e '.devices[][] | select(.udid==\"$udid\" and .state==\"Booted\")'" || { ko "le simulateur n'a pas booté"; return 1; }
  info "build ios : $(cfg ios.build)"
  # shellcheck disable=SC2086
  (cd "$PROJECT_ROOT" && $(cfg ios.build) >"$GAUNTLET_OUT/build_ios.log" 2>&1) || { ko "build ios échoué (voir .gauntlet/build_ios.log)"; tail -20 "$GAUNTLET_OUT/build_ios.log"; return 1; }
  app="$PROJECT_ROOT/$(cfg ios.app)"
  [ -d "$app" ] || { ko ".app introuvable : $app"; return 1; }
  xcrun simctl install "$udid" "$app" || { ko "simctl install échoué"; return 1; }
  QA_DEVICE="$udid"
}

check_qa() {
  local flows_dir="$PKG_DIR/maestro" nflows platform out app_id rc=0 prc failures shots
  nflows="$(find "$flows_dir" -maxdepth 1 -name '*.yaml' 2>/dev/null | wc -l | tr -d ' ')"
  [ "$nflows" -gt 0 ] || { ko "aucun flow dans ${flows_dir#$PROJECT_ROOT/}/"; return 1; }
  for platform in $(cfg_list qa.platforms); do
    section "qa $platform"
    out="$FEATURE_DIR/qa/$platform"; mkdir -p "$out"; rm -f "$out"/*.png "$out"/report.xml
    QA_DEVICE=""
    "qa_prepare_$platform" || { rc=1; continue; }
    app_id="$(cfg "$platform.app_id")"
    maestro test --device "$QA_DEVICE" -e "APP_ID=$app_id" -e "SCREENSHOT_DIR=$out" \
      --format junit --output "$out/report.xml" --test-output-dir "$out" "$flows_dir" >"$out/maestro.log" 2>&1; prc=$?
    failures="$(grep -oE '(failures|errors)="[0-9]+"' "$out/report.xml" 2>/dev/null | grep -oE '[0-9]+' | paste -sd+ - | bc 2>/dev/null || echo "?")"
    shots="$(find "$out" -name '*.png' | wc -l | tr -d ' ')"
    info "$nflows flow(s), échecs : ${failures:-?}, captures : $shots"
    if [ "$prc" != 0 ] || [ "${failures:-1}" != 0 ]; then
      grep -E 'FAILED|Failed|failed' "$out/maestro.log" | head -20 | sed 's/^/   /'
      ko "qa $platform rouge (voir ${out#$PROJECT_ROOT/}/maestro.log)"; rc=1
    elif [ "$shots" -lt "$nflows" ]; then
      ko "qa $platform : $shots capture(s) pour $nflows flow(s) — chaque flow doit prendre au moins une capture"; rc=1
    else
      ok "qa $platform"
    fi
  done
  return $rc
}
