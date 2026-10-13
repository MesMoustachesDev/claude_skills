#!/usr/bin/env bash
# checks_qa.sh — QA Maestro : build, install, flows par plateforme, captures. Sourcé par gauntlet.sh.
#
# Flows : <package>/maestro/*.yaml, un par scénario Gherkin. Plateformes : qa.platforms ; en gabarit S
# (pipeline.json → size), une seule (qa.platform_s, sinon la première). Variables injectées :
#   APP_ID          appId de la plateforme (android.app_id / ios.app_id)
#   SCREENSHOT_DIR  dossier absolu des captures (.claude/features/<f>/qa/<platform>/)
# Un flow écrit ses captures avec : - takeScreenshot: ${SCREENSHOT_DIR}/<scenario>
# Le run précédent (captures, report.xml, maestro.log) est déplacé dans qa/<platform>/_runs/<date>/, jamais
# effacé. Un config.yaml dans <package>/maestro/ est passé à Maestro (--config : executionOrder…).

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
  (cd "$PROJECT_ROOT/$(cfg app_dir .)" && $(cfg android.build) >"$GAUNTLET_OUT/build_android.log" 2>&1) || { ko "build android échoué (voir .gauntlet/build_android.log)"; tail -20 "$GAUNTLET_OUT/build_android.log"; return 1; }
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
  local build; build="$(cfg ios.build)"
  # Without an explicit device, flutter build ios can fail silently (watch companion) and leave a stale .app.
  case " $build " in *" -d "*) ;; *) build="$build -d $udid" ;; esac
  info "build ios : $build"
  # shellcheck disable=SC2086
  (cd "$PROJECT_ROOT/$(cfg app_dir .)" && $build >"$GAUNTLET_OUT/build_ios.log" 2>&1) || { ko "build ios échoué (voir .gauntlet/build_ios.log)"; tail -20 "$GAUNTLET_OUT/build_ios.log"; return 1; }
  app="$PROJECT_ROOT/$(cfg ios.app)"
  [ -d "$app" ] || { ko ".app introuvable : $app"; return 1; }
  xcrun simctl install "$udid" "$app" || { ko "simctl install échoué"; return 1; }
  QA_DEVICE="$udid"
}

# qa_platforms — qa.platforms ; en gabarit S, une seule : qa.platform_s, sinon la première de la liste.
qa_platforms() {
  if [ "$SIZE" = S ]; then
    local p; p="$(cfg qa.platform_s)"; [ -n "$p" ] || p="$(cfg_list qa.platforms | head -1)"
    printf '%s\n' "$p"
  else
    cfg_list qa.platforms
  fi
}

# qa_archive_previous <out> — moves the previous run's captures, report and log to <out>/_runs/<date of
# that run>/ instead of deleting them: a single-use flow (one that changes server state) cannot be replayed
# to get its captures back. Maestro's own timestamped folders (--test-output-dir) are left in place.
qa_archive_previous() {
  local out="$1" ref dest f
  for ref in "$out"/maestro.log "$out"/report.xml "$out"/*.png ""; do [ -f "$ref" ] && break; done
  [ -n "$ref" ] || return 0
  dest="$out/_runs/$(date -r "$ref" '+%Y-%m-%d_%H%M%S' 2>/dev/null || date '+%Y-%m-%d_%H%M%S')"
  mkdir -p "$dest"
  for f in "$out"/*.png "$out"/report.xml "$out"/maestro.log; do [ -f "$f" ] && mv "$f" "$dest/"; done
  info "run précédent conservé : ${dest#$PROJECT_ROOT/}/"
}

# qa_fingerprint — the state a QA run depends on: HEAD plus uncommitted and untracked changes under app_dir
# (flows included). .claude/ is excluded: the run itself writes its captures there.
qa_fingerprint() {
  local app f; app="$(cfg app_dir .)"
  {
    git -C "$PROJECT_ROOT" rev-parse HEAD
    git -C "$PROJECT_ROOT" diff HEAD -- "$app" ':(exclude,glob)**/.claude/**'
    git -C "$PROJECT_ROOT" ls-files --others --exclude-standard -- "$app" ':(exclude,glob)**/.claude/**' \
      | while IFS= read -r f; do shasum "$PROJECT_ROOT/$f"; done
  } 2>/dev/null | shasum | cut -d' ' -f1
}

# GAUNTLET_QA_REUSE=1 (set by the feature-qa end hook): if a QA run already finished on the same state
# (qa_fingerprint), its verdict is reused and the flows are not replayed. A manual `gauntlet.sh qa` always runs.
check_qa() {
  local flows_dir="$PKG_DIR/maestro" nflows platform out app_id rc=0 prc failures shots fp marker
  local last="$GAUNTLET_OUT/qa_last_run.json" failed_platforms=""
  fp="$(qa_fingerprint)"
  if [ -n "${GAUNTLET_QA_REUSE:-}" ] && [ -f "$last" ] && [ "$(jq -r '.fingerprint // empty' "$last")" = "$fp" ]; then
    info "un run QA a fini sur ce même état ($(jq -r '.date' "$last"), commit $(jq -r '.commit[0:8]' "$last")) : verdict réutilisé, flows non rejoués"
    for platform in $(jq -r '.failed[]?' "$last"); do ko "qa $platform rouge à ce run (voir ${FEATURE_DIR#$PROJECT_ROOT/}/qa/$platform/maestro.log)"; done
    [ "$(jq -r '.ok' "$last")" = true ]; return
  fi
  # config.yaml is Maestro's workspace config (executionOrder, flow globs), not a flow.
  nflows="$(find "$flows_dir" -maxdepth 1 -name '*.yaml' ! -name config.yaml 2>/dev/null | wc -l | tr -d ' ')"
  [ "$nflows" -gt 0 ] || { ko "aucun flow dans ${flows_dir#$PROJECT_ROOT/}/"; return 1; }
  # Passed explicitly: without it, `maestro test <dir>` was seen ignoring config.yaml (executionOrder).
  local maestro_cfg=()
  [ -f "$flows_dir/config.yaml" ] && { maestro_cfg=(--config "$flows_dir/config.yaml"); info "config Maestro : ${flows_dir#$PROJECT_ROOT/}/config.yaml"; }
  [ "$SIZE" = S ] && info "gabarit S : QA sur $(qa_platforms) seulement"
  for platform in $(qa_platforms); do
    section "qa $platform"
    out="$FEATURE_DIR/qa/$platform"; mkdir -p "$out"; qa_archive_previous "$out"
    QA_DEVICE=""
    "qa_prepare_$platform" || { rc=1; failed_platforms="$failed_platforms $platform"; continue; }
    app_id="$(cfg "$platform.app_id")"
    marker="$GAUNTLET_OUT/qa_${platform}_started"; touch "$marker"
    maestro test --device "$QA_DEVICE" -e "APP_ID=$app_id" -e "SCREENSHOT_DIR=$out" ${maestro_cfg[@]+"${maestro_cfg[@]}"} \
      --format junit --output "$out/report.xml" --test-output-dir "$out" "$flows_dir" >"$out/maestro.log" 2>&1; prc=$?
    failures="$(grep -oE '(failures|errors)="[0-9]+"' "$out/report.xml" 2>/dev/null | grep -oE '[0-9]+' | paste -sd+ - | bc 2>/dev/null || echo "?")"
    # This run's captures only: archived runs and older Maestro folders stay on disk.
    shots="$(find "$out" -name '*.png' -newer "$marker" -not -path "$out/_runs/*" | wc -l | tr -d ' ')"
    info "$nflows flow(s), échecs : ${failures:-?}, captures : $shots"
    if [ "$prc" != 0 ] || [ "${failures:-1}" != 0 ]; then
      grep -E 'FAILED|Failed|failed' "$out/maestro.log" | head -20 | sed 's/^/   /'
      ko "qa $platform rouge (voir ${out#$PROJECT_ROOT/}/maestro.log)"; rc=1; failed_platforms="$failed_platforms $platform"
    elif [ "$shots" -lt "$nflows" ]; then
      ko "qa $platform : $shots capture(s) pour $nflows flow(s) — chaque flow doit prendre au moins une capture"; rc=1; failed_platforms="$failed_platforms $platform"
    else
      ok "qa $platform"
    fi
  done
  jq -n --arg fp "$fp" --arg commit "$(git -C "$PROJECT_ROOT" rev-parse HEAD)" --argjson ok "$([ "$rc" = 0 ] && echo true || echo false)" \
        --arg failed "$failed_platforms" \
        '{fingerprint:$fp, commit:$commit, ok:$ok, date:(now|todate), failed:($failed|split(" ")|map(select(.!="")))}' > "$last"
  return $rc
}
