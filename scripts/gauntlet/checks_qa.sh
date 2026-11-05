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
# iOS : avec ios.simulator_base, chaque run a son simulateur, « <modèle> · feature-<feature> » (sim.sh ensure,
# nom surchargé par GAUNTLET_SIM_NAME), à supprimer avec le worktree. Sans, ios.simulator, partagé.

wait_until() { # wait_until <secondes> <cmd...>
  local t="$1"; shift
  while [ "$t" -gt 0 ]; do "$@" >/dev/null 2>&1 && return 0; sleep 2; t=$((t-2)); done
  return 1
}

EMULATOR="$HOME/Library/Android/sdk/emulator/emulator"
android_online() { adb -s "$1" get-state 2>/dev/null | grep -q device; }
# android_boot <avd> <serial> [options emulator…] — démarre l'AVD sur le port du serial, attend la fin du boot
android_boot() {
  local avd="$1" serial="$2"; shift 2
  info "démarrage de l'AVD $avd ($serial${*:+, $*})"
  nohup "$EMULATOR" -avd "$avd" -port "${serial#emulator-}" -no-snapshot-load "$@" >"$GAUNTLET_OUT/emulator.log" 2>&1 &
  wait_until 180 sh -c "adb -s $serial shell getprop sys.boot_completed 2>/dev/null | grep -q 1" || { ko "l'émulateur n'a pas booté (voir .gauntlet/emulator.log)"; return 1; }
}
# qa_android_serial — l'émulateur de la feature, selon pipeline.json → qa_devices.android (preflight) :
#   fresh | prepared  instance jetable de android.avd (-read-only : l'AVD n'est pas modifié, plusieurs
#                     instances possibles), sur un port libre, gardée pour la feature (.gauntlet/android_serial)
#   reuse             l'appareil nommé (serial en ligne, ou AVD à démarrer)
#   sans choix        android.serial, partagé (comportement d'avant le preflight)
qa_android_serial() { # → serial
  local avd mode dev port
  avd="$(cfg android.avd)"; mode="$(pipeline_get .qa_devices.android.mode)"; dev="$(pipeline_get .qa_devices.android.device)"
  case "$mode" in
    reuse)
      if android_online "$dev"; then serial="$dev"; info "émulateur réutilisé : $dev"; return 0; fi
      serial="$(cat "$GAUNTLET_OUT/android_serial" 2>/dev/null)"
      android_online "${serial:-none}" && { info "émulateur réutilisé : $dev ($serial)"; return 0; }
      serial="$(android_free_serial)" || return 1
      android_boot "$dev" "$serial" || return 1
      echo "$serial" > "$GAUNTLET_OUT/android_serial" ;;
    fresh|prepared)
      [ -n "$avd" ] || { ko "android.avd non configuré : pas d'AVD à cloner"; return 1; }
      serial="$(cat "$GAUNTLET_OUT/android_serial" 2>/dev/null)"
      if android_online "${serial:-none}"; then info "émulateur de la feature : $avd ($serial)"; return 0; fi
      serial="$(android_free_serial)" || return 1
      android_boot "$avd" "$serial" -read-only || return 1
      echo "$serial" > "$GAUNTLET_OUT/android_serial" ;;
    *)
      serial="$(cfg android.serial emulator-5554)"
      if ! android_online "$serial"; then
        [ -n "$avd" ] || { ko "android.avd non configuré et $serial hors ligne"; return 1; }
        android_boot "$avd" "$serial" || return 1
      fi ;;
  esac
}
android_free_serial() {
  local p
  for p in 5560 5562 5564 5566 5568 5570 5572 5574 5576 5578; do
    android_online "emulator-$p" || adb devices 2>/dev/null | grep -q "emulator-$p" || { printf 'emulator-%s\n' "$p"; return 0; }
  done
  ko "aucun port d'émulateur libre (5560-5578)"; return 1
}

qa_prepare_android() { # → QA_DEVICE
  local serial apk
  qa_android_serial || return 1
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

# qa_ios_udid — the run's own clone of ios.simulator_base (booted by sim.sh), else the shared ios.simulator.
# Preflight (pipeline.json → qa_devices.ios) : reuse → le simulateur nommé ; fresh | prepared → le clone.
qa_ios_udid() {
  local sim name mode dev
  mode="$(pipeline_get .qa_devices.ios.mode)"; dev="$(pipeline_get .qa_devices.ios.device)"
  if [ "$mode" = reuse ]; then
    udid="$(xcrun simctl list devices available -j | jq -r --arg k "$dev" '[.devices[][] | select(.name==$k or .udid==$k)][0].udid // empty')"
    [ -n "$udid" ] || { ko "simulateur « $dev » (qa_devices.ios.device) introuvable"; return 1; }
    info "simulateur réutilisé : $dev ($udid)"
    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
    return 0
  fi
  if [ -n "$mode" ] && [ -z "$(cfg ios.simulator_base)" ]; then
    ko "qa_devices.ios = $mode mais pas de ios.simulator_base à cloner : configure le modèle, ou choisis reuse"; return 1
  fi
  if [ -n "$(cfg ios.simulator_base)" ]; then
    name="${GAUNTLET_SIM_NAME:-feature-$FEATURE}"
    udid="$(cd "$PROJECT_ROOT" && SIM_BASE="$(cfg ios.simulator_base)" "$HOME/.claude/scripts/sim.sh" ensure "$name" 2>"$GAUNTLET_OUT/sim.log")" \
      || { sed 's/^/   /' "$GAUNTLET_OUT/sim.log"; ko "pas de simulateur pour ce run (sim.sh ensure $name)"; return 1; }
    info "simulateur du run : $(cfg ios.simulator_base) · $name ($udid)"
    return 0
  fi
  sim="$(cfg ios.simulator 'iPhone 16 Pro')"
  udid="$(xcrun simctl list devices available -j | jq -r --arg n "$sim" '.devices[][] | select(.name==$n) | .udid' | head -1)"
  [ -n "$udid" ] || { ko "simulateur '$sim' introuvable"; return 1; }
  info "simulateur partagé : $sim ($udid) — pas de ios.simulator_base"
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
}

qa_prepare_ios() { # → QA_DEVICE
  local udid app
  qa_ios_udid || return 1
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
    # --submodule=diff : a submodule (dskit) changes the state through its content, not only its gitlink.
    git -C "$PROJECT_ROOT" diff --submodule=diff HEAD -- "$app" ':(exclude,glob)**/.claude/**'
    untracked "$app" | grep -v '/\.claude/' | grep -v '^\.claude/' \
      | while IFS= read -r f; do shasum "$PROJECT_ROOT/$f"; done
  } 2>/dev/null | shasum | cut -d' ' -f1
}

# qa_device — sans build ni flow : démarre (ou clone) l'appareil de chaque plateforme pour cette feature et
# imprime son identifiant. Quentin s'en sert pour préparer l'état demandé (qa_devices.<pf>.mode = prepared)
# avant de lancer les flows.
check_qa_device() {
  local platform udid serial rc=0
  for platform in $(qa_platforms); do
    case "$platform" in
      ios) qa_ios_udid && info "ios : $udid" || rc=1 ;;
      android) qa_android_serial && info "android : $serial" || rc=1 ;;
    esac
    local st; st="$(pipeline_get ".qa_devices.$platform.state")"
    [ -n "$st" ] && info "état à préparer ($platform) : $st"
  done
  return $rc
}
# qa_device_ready <plateforme> — mode prepared : l'état décrit au preflight doit avoir été préparé.
qa_device_ready() {
  [ "$(pipeline_get ".qa_devices.$1.mode")" = prepared ] || return 0
  [ -n "$(pipeline_get ".qa_devices.$1.prepared_at")" ] && return 0
  ko "qa_devices.$1 = prepared, état pas encore préparé : « $(pipeline_get ".qa_devices.$1.state") » — gauntlet.sh qa_device $FEATURE, préparer l'appareil, puis pipeline.sh devices $FEATURE $1 prepared-done"
  return 1
}

# GAUNTLET_QA_REUSE=1 (set by the feature-qa end hook): if a QA run already finished on the same state
# (qa_fingerprint), its verdict is reused and the flows are not replayed. A manual `gauntlet.sh qa` always runs.
check_qa() {
  # GAUNTLET_QA_FLOWS : autre dossier de flows (les flows de /reviewPR vivent hors du repo).
  local flows_dir="${GAUNTLET_QA_FLOWS:-$PKG_DIR/maestro}" nflows platform out app_id rc=0 prc failures shots fp marker
  local last="$GAUNTLET_OUT/qa_last_run.json" failed_platforms=""
  fp="$(qa_fingerprint)"
  if [ -n "${GAUNTLET_QA_REUSE:-}" ] && [ -f "$last" ] && [ "$(jq -r '.fingerprint // empty' "$last")" = "$fp" ]; then
    info "un run QA a fini sur ce même état ($(jq -r '.date' "$last"), commit $(jq -r '.commit[0:8]' "$last")) : verdict réutilisé, flows non rejoués"
    for platform in $(jq -r '.failed[]?' "$last"); do ko "qa $platform rouge à ce run (voir ${FEATURE_DIR#$PROJECT_ROOT/}/qa/$platform/maestro.log)"; done
    [ "$(jq -r '.ok' "$last")" = true ]; return
  fi
  # config.yaml is Maestro's workspace config (executionOrder, flow globs), not a flow.
  nflows="$(find "$flows_dir" -maxdepth 1 -name '*.yaml' ! -name config.yaml 2>/dev/null | wc -l | tr -d ' ')"
  # In extend mode the folder also holds the flows of earlier features (config.yaml includeTags keeps
  # them from running): only the flows the feature added must bring a capture.
  if [ "$MODE" = extend ] && [ -z "${GAUNTLET_QA_FLOWS:-}" ]; then
    local base f rel
    base="$(merge_base)"; nflows=0
    for f in "$flows_dir"/*.yaml; do
      [ -f "$f" ] && [ "$(basename "$f")" != config.yaml ] || continue
      rel="${f#$PROJECT_ROOT/}"
      git -C "$PROJECT_ROOT" cat-file -e "$base:$rel" 2>/dev/null || nflows=$((nflows + 1))
    done
  fi
  [ "$nflows" -gt 0 ] || { ko "aucun flow dans ${flows_dir#$PROJECT_ROOT/}/"; return 1; }
  # Passed explicitly: without it, `maestro test <dir>` was seen ignoring config.yaml (executionOrder).
  local maestro_cfg=()
  [ -f "$flows_dir/config.yaml" ] && { maestro_cfg=(--config "$flows_dir/config.yaml"); info "config Maestro : ${flows_dir#$PROJECT_ROOT/}/config.yaml"; }
  [ "$SIZE" = S ] && info "gabarit S : QA sur $(qa_platforms) seulement"
  for platform in $(qa_platforms); do
    section "qa $platform"
    out="$FEATURE_DIR/qa/$platform"; mkdir -p "$out"; qa_archive_previous "$out"
    QA_DEVICE=""
    qa_device_ready "$platform" || { rc=1; failed_platforms="$failed_platforms $platform"; continue; }
    "qa_prepare_$platform" || { rc=1; failed_platforms="$failed_platforms $platform"; continue; }
    app_id="$(cfg "$platform.app_id")"
    marker="$GAUNTLET_OUT/qa_${platform}_started"; touch "$marker"
    MAESTRO_DRIVER_STARTUP_TIMEOUT="${MAESTRO_DRIVER_STARTUP_TIMEOUT:-180000}" maestro test --device "$QA_DEVICE" -e "APP_ID=$app_id" -e "SCREENSHOT_DIR=$out" ${maestro_cfg[@]+"${maestro_cfg[@]}"} \
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
