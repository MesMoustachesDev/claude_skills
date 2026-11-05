#!/usr/bin/env bash
# Repro — le gate qa suit le preflight (pipeline.json → qa_devices) : un appareil « prepared » dont l'état
# n'a pas été préparé bloque avant tout build ; reuse vise l'appareil nommé ; fresh sans modèle à cloner
# est refusé au lieu de retomber sur le simulateur partagé.
source "$(dirname "$0")/fixture.sh"
command -v xcrun >/dev/null || { echo "SKIP: xcrun requis"; exit 0; }
R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R" "qa.platforms = ios" "ios.simulator = Simulateur partagé inexistant"
sed -i "" "/^qa.platforms =$/d" "$R/.claude/rules/feature_pipeline.md"   # write_cfg pose « qa.platforms = » vide en tête
mk_pkg "$R/app/features/feat" feat; mkdir -p "$R/app/features/feat/maestro"; echo 'appId: x' > "$R/app/features/feat/maestro/s1.yaml"
commit "$R" init >/dev/null; git -C "$R" checkout -q -b feature/x

pipeline "$R" x '{"mode":"create","package":"app/features/feat","qa_devices":{"ios":{"mode":"prepared","state":"connecté, rapport 1234 téléchargé"}}}'
run_g "$R" qa x
expect_rc 1 "prepared non préparé : qa rouge"
expect_out "état pas encore préparé : « connecté, rapport 1234 téléchargé »" "l'état attendu est rappelé"
expect_no_out "build ios" "aucun build lancé"

pipeline "$R" x '{"mode":"create","package":"app/features/feat","qa_devices":{"ios":{"mode":"reuse","device":"Appareil inexistant 42"}}}'
run_g "$R" qa_device x
expect_rc 1 "reuse d'un appareil inconnu : rouge"
expect_out "simulateur « Appareil inexistant 42 » (qa_devices.ios.device) introuvable" "l'appareil est nommé"

pipeline "$R" x '{"mode":"create","package":"app/features/feat","qa_devices":{"ios":{"mode":"fresh"}}}'
run_g "$R" qa_device x
expect_rc 1 "fresh sans ios.simulator_base : rouge"
expect_out "pas de ios.simulator_base à cloner" "pas de repli sur le simulateur partagé"
finish
