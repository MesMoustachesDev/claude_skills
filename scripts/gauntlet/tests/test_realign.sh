#!/usr/bin/env bash
# Repro — un fake de test cassé par un contrat, en 1c/1e. Cas réel : une sous-feature Android, Arthur ajoute une
# méthode à une interface qu'un fake de test implémente.
#   bug 4 : le gate contracts restait rouge sur analyze (Arthur ne peut pas toucher aux tests), et
#     `next --after contracts` attendait 540 s. Avant hg.contracts, des erreurs de compilation dans les tests
#     seulement sont listées pour Théo (tests_to_realign.txt) et ne retiennent pas Arthur ; contrôles : une erreur
#     dans src/main, ou après hg.contracts, bloque toujours.
#   bug 3 : Théo lancé en 1e pour réaligner le fake jouait le gate red et écrivait stages.red. Avant l'étape 3,
#     son hook joue analyze et n'écrit rien ; à l'étape 3, inchangé.
#   bug 7 : un gate rejoué à la main et vert ne réécrivait pas stages.<profil> ; `pipeline.sh replay` le fait.
source "$(dirname "$0")/fixture.sh"
FAKE_GRADLE="$TESTS_DIR/fake_gradle.sh"
HOOKS="$TESTS_DIR/../../../hooks"
PIPELINE_SH="$TESTS_DIR/../../pipeline.sh"
export PIPELINE_GAUNTLET_ROOT="$TESTS_DIR/.."

R="$TMP_ROOT/repo"; mk_repo "$R"
M=feature/login; P="$R/$M"; K="src/main/kotlin/com/x/login"; T="src/test/kotlin/com/x/login"
mkdir -p "$R/.claude/rules" "$R/.claude/pipeline" "$P/$K/domain" "$P/$K/data" "$P/$T/domain"
{
  echo '# test'; echo '```ini'
  echo "gradle = $FAKE_GRADLE"
  echo 'package_path = feature/{name}'
  echo 'features_root = feature'
  echo 'base_branch = develop'
  echo 'qa.platforms ='
  echo 'stub.include = src/main/**/data/*Impl.kt'
  echo 'deps.data = domain'
  echo '```'
} > "$R/.claude/pipeline/feature_pipeline.md"
echo 'include(":feature:login")' > "$R/settings.gradle.kts"
printf 'plugins {\n  kotlin("jvm")\n}\n' > "$P/build.gradle.kts"
printf '# login\n\nConnexion.\n' > "$P/README.md"
printf 'package com.x.login.domain\n\ninterface LoginRepository {\n    fun login(): Int\n}\n' > "$P/$K/domain/LoginRepository.kt"
printf 'package com.x.login.domain\n\nclass FakeLoginRepository : LoginRepository {\n    override fun login() = 1\n}\n' > "$P/$T/domain/FakeLoginRepository.kt"
commit "$R" base >/dev/null
git -C "$R" checkout -q -b feature/login
# Arthur ajoute une méthode et son stub : le fake ne compile plus.
printf 'package com.x.login.data\n\nimport com.x.login.domain.LoginRepository\n\nclass LoginRepositoryImpl : LoginRepository {\n    override fun login(): Int = TODO()\n    override fun logout(): Unit = TODO()\n}\n' > "$P/$K/data/LoginRepositoryImpl.kt"
printf 'package com.x.login.domain\n\ninterface LoginRepository {\n    fun login(): Int\n    fun logout()\n}\n' > "$P/$K/domain/LoginRepository.kt"
printf 'package com.x.login.domain\n\nclass FakeLoginRepository : LoginRepository { // FAKE_COMPILE_ERROR\n    override fun login() = 1\n}\n' > "$P/$T/domain/FakeLoginRepository.kt"

S='"cadrage":{"status":"PASSED","at":"2026-11-12T08:00:00Z"},"spec":{"status":"PASSED","at":"2026-11-12T09:00:00Z"}'
HG_SPEC='"spec":{"at":"2026-11-12T09:00:00Z","by":"user"}'
HG_CON='"contracts":{"at":"2026-11-12T11:00:00Z","by":"user"}'
AT_1C="{\"mode\":\"extend\",\"package\":\"$M\",\"size\":\"M\",\"stages\":{$S},\"human_gates\":{$HG_SPEC}}"
UP_TO_2='"contracts_draft":{"status":"PASSED","at":"2026-11-12T10:00:00Z"},"dedup":{"status":"PASSED","at":"2026-11-12T10:05:00Z"},"spec_contracts":{"status":"PASSED","at":"2026-11-12T11:30:00Z"},"contracts":{"status":"PASSED","at":"2026-11-12T12:00:00Z"},"test_plan":{"status":"PASSED","at":"2026-11-12T12:10:00Z"},"test_plan_review":{"status":"PASSED","at":"2026-11-12T12:20:00Z"}'
AT_3="{\"mode\":\"extend\",\"package\":\"$M\",\"size\":\"M\",\"stages\":{$S,$UP_TO_2},\"human_gates\":{$HG_SPEC,$HG_CON}}"
PJ="$R/.claude/features/login/pipeline.json"

hook() { OUT="$(jq -n --arg a "$1" --arg c "$R" '{agent_type:$a, cwd:$c}' | bash "$HOOKS/pipeline-gate.sh" 2>&1)"; RC=$?; }
run_g() { OUT="$(cd "$R" && bash "$GAUNTLET" "$@" 2>&1)"; RC=$?; }

echo "bug 4 — 1c : fake cassé par le brouillon d'Arthur"
pipeline "$R" login "$AT_1C"
run_g contracts login
expect_no_out "[FAIL] analyze" "analyze ne retient pas Arthur pour un test"
expect_out "à réaligner par Théo" "l'erreur est donnée à Théo"
expect_file_has "$R/.claude/features/login/.gauntlet/tests_to_realign.txt" "$M/$T/domain/FakeLoginRepository.kt" "tests_to_realign.txt nomme le fake"
hook feature-architect
OUT="$(jq -r '.stages.contracts.status' "$PJ")"
expect_out "PASSED" "le hook d'Arthur passe : next --after contracts n'attend pas"
OUT="$(cd "$R" && bash "$PIPELINE_SH" after-architect login 2>&1)"
expect_out "tests à réaligner" "after-architect dit de lancer Théo"
expect_out "FakeLoginRepository.kt" "avec le fichier"

echo "bug 4 — contrôles"
pipeline "$R" login "$AT_3"
run_g contracts login; expect_out "[FAIL] analyze" "après hg.contracts : un test qui ne compile pas bloque"
pipeline "$R" login "$AT_1C"
printf 'package com.x.login.domain\n\ninterface LoginRepository { // FAKE_COMPILE_ERROR\n    fun login(): Int\n    fun logout()\n}\n' > "$P/$K/domain/LoginRepository.kt"
run_g contracts login; expect_out "[FAIL] analyze" "1c : une erreur dans src/main bloque"
printf 'package com.x.login.domain\n\ninterface LoginRepository {\n    fun login(): Int\n    fun logout()\n}\n' > "$P/$K/domain/LoginRepository.kt"

echo "bug 3 — Théo en 1e réaligne le fake"
pipeline "$R" login "$AT_1C"
hook feature-test-writer
expect_rc 2 "fake toujours cassé : Théo est renvoyé au travail"
expect_out "RÉALIGNEMENT" "par le réalignement, pas par le gate red"
OUT="$(tail -1 "$R/.claude/features/login/.gauntlet/hooks.jsonl" 2>/dev/null)"
expect_out '"outcome":"red"' "journal (ADR 0019) : le gate rouge s'écrit"
expect_out '"stage":"realign"' "… avec son étape (réalignement)"
OUT="$(jq -r '.stages.red // "absent"' "$PJ")"; expect_out "absent" "stages.red n'est pas écrit"
printf 'package com.x.login.domain\n\nclass FakeLoginRepository : LoginRepository {\n    override fun login() = 1\n    override fun logout() = Unit\n}\n' > "$P/$T/domain/FakeLoginRepository.kt"
hook feature-test-writer
expect_rc 0 "fake réaligné : Théo sort"
OUT="$(jq -r '.stages.red // "absent"' "$PJ")"; expect_out "absent" "stages.red toujours vierge"
hook feature-test-writer-presentation
OUT="$(jq -r '.stages.red_presentation // "absent"' "$PJ")"; expect_out "absent" "une moitié non plus"

echo "bug 3 — contrôle : à l'étape 3, le hook de Théo écrit stages.red"
pipeline "$R" login "$AT_3"
hook feature-test-writer
OUT="$(jq -r '.stages.red.status // "absent"' "$PJ")"; expect_no_out "absent" "stages.red écrit"

echo "bug 7 — gate rejoué à la main"
pipeline "$R" login "{\"mode\":\"extend\",\"package\":\"$M\",\"stages\":{\"contracts\":{\"status\":\"RED\",\"at\":\"2026-11-12T12:00:00Z\"}},\"attempts\":{\"contracts\":3},\"human_gates\":{$HG_SPEC,$HG_CON}}"
OUT="$(cd "$R" && bash "$PIPELINE_SH" replay login contracts 2>&1)"; RC=$?
expect_rc 0 "replay vert"
expect_out "était RED" "l'ancien statut est dit"
OUT="$(jq -c '[.stages.contracts.status, .attempts.contracts]' "$PJ")"
expect_out '["PASSED",0]' "stages.contracts réécrit, tentatives remises à 0"
OUT="$(cd "$R" && bash "$PIPELINE_SH" replay login spec 2>&1)"; RC=$?
expect_rc 2 "un profil que le hook n'écrit pas est refusé"
finish
