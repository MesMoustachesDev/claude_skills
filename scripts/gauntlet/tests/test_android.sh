#!/usr/bin/env bash
# Repro — les checks du gauntlet pour un module Android (stacks/android/, plan langages point 6).
#   Gradle est simulé (fake_gradle.sh : rapports JUnit, lint, ktlint, detekt, Kover, pitest d'après des marqueurs
#   FAKE_* dans les sources) ; test_android_gradle.sh rejoue une partie avec le vrai Gradle, hors ligne.
#   - chaque check Android juge ce qu'il doit (compilation, lint, format, tests, rouge, couverture, mutation,
#     stubs, couches, design system, chaînes, strings.xml, hygiène, README) ;
#   - un outil absent du projet (ni ktlint ni Spotless, ni Kover ni JaCoCo, pas de pitest) : [N/A], jamais vert ;
#   - un check que seul Flutter a (build_runner) : [N/A] ;
#   - gradle_run.sh qualifie les tâches par le module et traduit un fichier de test en --tests.
source "$(dirname "$0")/fixture.sh"
FAKE_GRADLE="$TESTS_DIR/fake_gradle.sh"
RUNNER="$TESTS_DIR/../../../stacks/android/gradle_run.sh"

R="$TMP_ROOT/repo"; mk_repo "$R"
M=feature/login; P="$R/$M"; K="src/main/kotlin/com/x/login"; T="src/test/kotlin/com/x/login"
mkdir -p "$R/.claude/rules" "$P/$K/domain" "$P/$K/data" "$P/$K/ui" "$P/$T/ui" "$P/src/main/res/values" "$P/src/main/res/values-en"
cat > "$R/.claude/rules/feature_pipeline.md" <<EOF
# test
\`\`\`ini
gradle = $FAKE_GRADLE
package_path = feature/{name}
features_root = feature
base_branch = develop
qa.platforms =
stub.include = src/main/**/data/*Impl.kt
deps.domain =
deps.data = domain
deps.presentation = domain
deps.injection = domain, data, presentation
ds.forbidden = Color\(0x, [0-9]+\.dp
ds.imports = com.x.design.
mutation.include = src/main/**.kt
readme.sections = ^## But
threshold.coverage_changed = 90
threshold.mutation = 80
\`\`\`
EOF
echo 'include(":feature:login")' > "$R/settings.gradle.kts"
plugins_all='plugins {
  id("com.android.library")
  id("org.jlleitschuh.gradle.ktlint")
  id("org.jetbrains.kotlinx.kover")
  id("io.gitlab.arturbosch.detekt")
  id("info.solidsoft.pitest")
}'
printf '%s\n' "$plugins_all" > "$P/build.gradle.kts"
printf 'package com.x.login.domain\n\ninterface LoginRepository {\n    suspend fun login(user: String): Result<Unit>\n}\n' > "$P/$K/domain/LoginRepository.kt"
printf 'package com.x.login.data\n\nimport com.x.login.domain.LoginRepository\n\nclass LoginRepositoryImpl : LoginRepository {\n    override suspend fun login(user: String): Result<Unit> = TODO()\n}\n' > "$P/$K/data/LoginRepositoryImpl.kt"
printf 'package com.x.login.ui\n\nimport com.x.design.AppTheme\n\nfun LoginScreen() {\n    val title = 1\n}\n' > "$P/$K/ui/LoginScreen.kt"
printf 'package com.x.login.ui\n\nclass LoginScreenTest {\n    fun works() = Unit\n}\n' > "$P/$T/ui/LoginScreenTest.kt"
printf '<resources>\n    <string name="login_title">Connexion</string>\n</resources>\n' > "$P/src/main/res/values/strings.xml"
printf '<resources>\n    <string name="login_title">Sign in</string>\n</resources>\n' > "$P/src/main/res/values-en/strings.xml"
printf '# login\n\n## But\nSe connecter.\n' > "$P/README.md"
commit "$R" base >/dev/null
git -C "$R" checkout -q -b feature/login

run_c() { OUT="$(cd "$R" && GAUNTLET_MODE=create GAUNTLET_PACKAGE="$M" bash "$GAUNTLET" "$@" 2>&1)"; RC=$?; }
run_x() { OUT="$(cd "$R" && GAUNTLET_MODE=extend GAUNTLET_PACKAGE="$M" bash "$GAUNTLET" "$@" 2>&1)"; RC=$?; }
json() { OUT="$(jq -c "$1" "$R/.claude/features/login/.gauntlet/last_$2.json")"; }
reset() { git -C "$R" checkout -q -- . && git -C "$R" clean -qfd -e .claude; }

echo "gradle_run.sh — tâches du module, type, fichiers de test"
OUT="$(cd "$P" && bash "$RUNNER" --where)"; expect_out "$(printf ':feature:login\tandroid')" "--where : chemin Gradle du module, android"
OUT="$(cd "$P" && GRADLE_RUN_DRY=1 STACK_CFG="$R/.claude/rules/feature_pipeline.md" bash "$RUNNER" :@unitTest --continue "$T/ui/LoginScreenTest.kt")"
expect_out ":feature:login:testDebugUnitTest --continue --tests com.x.login.ui.LoginScreenTest" ":@unitTest et --tests <classe>"
expect_out "$FAKE_GRADLE" "la commande gradle de la config du projet"
expect_out "test_logging.gradle" "init script : le message d'assertion d'un test rouge sur la console"
OUT="$(cd "$P" && GRADLE_RUN_DRY=1 bash "$RUNNER" :@unitTest -x :feature:login:processDebugGoogleServices)"
expect_out " -x :feature:login:processDebugGoogleServices" "une tâche déjà qualifiée par le module n'est pas préfixée deux fois"
printf 'plugins { kotlin("jvm") }\n' > "$P/build.gradle.kts"
OUT="$(cd "$P/$K" && GRADLE_RUN_DRY=1 bash "$RUNNER" :@unitTest :@compile)"
expect_out ":feature:login:test :feature:login:compileTestKotlin" "module Kotlin/JVM : test et compileTestKotlin, depuis un sous-dossier"
reset

echo "analyze — compilation, lint, detekt, au périmètre"
run_c analyze login; expect_rc 0 "module propre"; expect_no_out "[N/A]" "analyze a une version Android"
printf '\nval broken = FAKE_COMPILE_ERROR\n' >> "$P/$K/ui/LoginScreen.kt"
run_c analyze login; expect_rc 1 "une erreur de compilation bloque"; expect_out "$K/ui/LoginScreen.kt:9: Unresolved reference" "l'erreur est nommée, chemin du module"
reset; printf '\n// FAKE_LINT\n' >> "$P/$K/ui/LoginScreen.kt"
run_c analyze login; expect_rc 1 "une issue lint dans le périmètre bloque"; expect_out "FakeLint" "l'issue est nommée"
commit "$R" "lint existant" >/dev/null; git -C "$R" checkout -q develop; git -C "$R" merge -q --ff-only feature/login; git -C "$R" checkout -q feature/login
printf 'fun other() = 2\n' >> "$P/$K/domain/LoginRepository.kt"
run_x analyze login; expect_rc 0 "extend : l'issue lint d'une ligne non touchée ne bloque pas"; expect_out "hors périmètre (préexistantes)" "elle est dite préexistante"
reset; printf '\n// FAKE_DETEKT\n' >> "$P/$K/domain/LoginRepository.kt"
run_x analyze login; expect_rc 1 "detekt appliqué : une issue sur une ligne ajoutée bloque"; expect_out "LongMethod" "la règle detekt est nommée"
reset; printf '\nfun call() = FAKE_DEPRECATED\n' >> "$P/$K/ui/LoginScreen.kt"
run_x deprecated_api login; expect_rc 1 "deprecated_api : une API dépréciée sur une ligne ajoutée"; expect_out "is deprecated" "le message du compilateur"
reset

echo "format — ktlint du projet, sinon non applicable"
printf '\n// FAKE_FORMAT\n' >> "$P/$K/ui/LoginScreen.kt"
run_x format login; expect_rc 1 "ktlint : un fichier du périmètre à formater"; expect_out "$K/ui/LoginScreen.kt" "le fichier est nommé"
run_x format:test login; expect_rc 0 "format:test ne juge que les tests"
reset; sed -i.bak '/ktlint/d' "$P/build.gradle.kts"; rm -f "$P/build.gradle.kts.bak"
printf '\n// FAKE_FORMAT\n' >> "$P/$K/ui/LoginScreen.kt"
run_x format login; expect_rc 0 "sans formateur : ne bloque pas"; expect_out "[N/A]  format : non applicable à ce package" "format dit non applicable"
json '[.not_applicable, .passed]' format; expect_out '[["format"],[]]' "last_format.json : non applicable, pas passé"
reset

echo "test, red_check, test_names — rapports JUnit"
run_c test login; expect_rc 0 "suite verte"; expect_out "1 test(s), 0 échec(s)" "le test JUnit est compté"
run_c red_check login; expect_rc 1 "red_check : un fichier tout vert bloque"; expect_out "tout vert : $T/ui/LoginScreenTest.kt" "le fichier est nommé"
PJ="$R/.claude/features/login/pipeline.json"; mkdir -p "${PJ%/*}"; [ -f "$PJ" ] && cp "$PJ" "$PJ.bak" || echo '{}' > "$PJ.bak"
jq --arg f "$T/ui/LoginScreenTest.kt" '.red_accept_green = [{file: $f, reason: "ressources posées au scaffold"}]' "$PJ.bak" > "$PJ"
run_c red_check login; expect_rc 0 "red_check : un fichier tout vert accepté par Thibault ne bloque plus"
expect_out "tout vert, accepté par Thibault : $T/ui/LoginScreenTest.kt (ressources posées au scaffold)" "il reste signalé, avec sa raison"
mv "$PJ.bak" "$PJ"
printf '// FAKE_FAIL\n' >> "$P/$T/ui/LoginScreenTest.kt"
run_c red_check login; expect_rc 0 "red_check : rouge dans chaque fichier"
run_c test login; expect_rc 1 "test : l'échec bloque"; expect_out "✗ $T/ui/LoginScreenTest.kt" "le fichier rouge est nommé"
run_c test_names login; expect_file_has "$R/.claude/features/login/tests.md" "## $T/ui/LoginScreenTest.kt" "tests.md liste le fichier de test"
reset

echo "coverage — Kover, lignes ajoutées"
printf 'fun covered() = 1\n' >> "$P/$K/domain/LoginRepository.kt"
run_x coverage login; expect_rc 0 "ligne ajoutée couverte"; expect_out "1/1 (100.0%)" "le compte est fait sur les lignes ajoutées"
printf 'fun notCovered() = 2 // FAKE_UNCOVERED\n' >> "$P/$K/domain/LoginRepository.kt"
run_x coverage login; expect_rc 1 "une ligne ajoutée non couverte sous le seuil bloque"; expect_out "✗ $M/$K/domain/LoginRepository.kt:" "la ligne est nommée"
sed -i.bak '/kover/d' "$P/build.gradle.kts"; rm -f "$P/build.gradle.kts.bak"
run_x coverage login; expect_rc 0 "sans Kover ni JaCoCo : ne bloque pas"; expect_out "[N/A]  coverage" "coverage dit non applicable"
reset

echo "mutation — pitest"
printf 'fun isAdult(age: Int) = age >= 18 // FAKE_SURVIVOR\n' >> "$P/$K/domain/LoginRepository.kt"
run_x mutation login; expect_rc 1 "un survivant sous le seuil bloque"; expect_out "SURVIVED" "le survivant est listé"
expect_file_has "$R/.claude/features/login/.gauntlet/mutation_survivors.txt" "ConditionalsBoundary" "mutation_survivors.txt"
sed -i.bak '/pitest/d' "$P/build.gradle.kts"; rm -f "$P/build.gradle.kts.bak"
run_x mutation login; expect_rc 0 "sans pitest : ne bloque pas"; expect_out "[N/A]  mutation" "mutation dit non applicable"
reset

echo "stubs — TODO(), NotImplementedError"
run_c stub_check login; expect_rc 0 "stub_check : l'impl est un TODO()"
run_c no_stubs login; expect_rc 1 "no_stubs : le TODO() reste"; expect_out "LoginRepositoryImpl.kt:6" "la ligne est nommée"
printf 'package com.x.login.data\n\nimport com.x.login.domain.LoginRepository\n\nclass LoginRepositoryImpl : LoginRepository {\n    // TODO(#12) cache\n    override suspend fun login(user: String): Result<Unit> {\n        return Result.success(Unit)\n    }\n}\n' > "$P/$K/data/LoginRepositoryImpl.kt"
run_c no_stubs login; expect_rc 0 "no_stubs : un commentaire // TODO n'est pas un stub"
run_c stub_check login; expect_rc 1 "stub_check : une fonction implémentée avant les tests bloque"; expect_out "fun login" "la fonction est nommée"
reset
echo "spec_lint — symboles et testTags Kotlin"
S="$TMP_ROOT/speclint"; mkdir -p "$S/feat/src/main/java/x/domain" "$S/ui/src/main/java/x/ui"
printf 'package x.domain\n\ninterface OpenSettingsUseCase {\n    operator fun invoke(): Result<Unit>\n}\n' > "$S/feat/src/main/java/x/domain/OpenSettingsUseCase.kt"
printf 'package x.domain\n\nobject FeatTestTags {\n    const val OPEN = "feat_open"\n}\n' > "$S/feat/src/main/java/x/domain/FeatTestTags.kt"
printf 'package x.ui\n\nclass LocationText\n' > "$S/ui/src/main/java/x/ui/LocationText.kt"
printf '# Spec\n## 4. Scénarios\n  Scenario: opens\n    When I tap "feat_open" then "feat_close"\n## 5. Contrats\n| `OpenSettingsUseCase`, `LocationText`, `Result` | C1 |\n## 6. Données\n`OpenSettingsUseCase.kt`, `Result.success`, `OpenSettingsUseCase.invoke`, `FeatTestTags.OPEN`\n' > "$S/spec.md"
OUT="$(SPEC_LINT_EXT=".kt,.kts,.java" python3 "$TESTS_DIR/../spec_lint.py" "$S/spec.md" "$S/feat" "$S" - 40960 2>&1)"
expect_out "1 fichier(s) de clés" "spec_lint lit le *TestTags.kt du package"
expect_out "clé 'feat_close'" "une clé absente du TestTags est signalée"
expect_no_out "clé 'feat_open'" "une clé du TestTags n'est pas signalée"
expect_no_out '`OpenSettingsUseCase`, introuvable' "un symbole Kotlin du package est indexé"
expect_no_out '`LocationText`, introuvable' "un symbole Kotlin d'un autre module est indexé"
expect_no_out "Result" "Result (Kotlin) et Result.success ne sont pas des contrats du workspace"
expect_no_out "membre kt" "Fichier.kt n'est pas un Classe.membre"
G="$TMP_ROOT/globs"; mkdir -p "$G/src/main/java/x/domain/sub"; touch "$G/src/main/java/x/domain/AUseCase.kt" "$G/src/main/java/x/domain/sub/BUseCase.kt"
OUT="$(bash -c 'source "$1" >/dev/null 2>&1; expand_globs "$2" "src/main/**/domain/**/*UseCase.kt"' _ "$TESTS_DIR/../lib.sh" "$G")"
expect_out "src/main/java/x/domain/AUseCase.kt" "expand_globs : domain/**/ vaut aussi zéro dossier (use case posé dans domain/)"
expect_out "src/main/java/x/domain/sub/BUseCase.kt" "expand_globs : domain/**/ traverse les sous-dossiers"

echo "error_handling, deps — couches"
printf '\nfun f() { try { g() } catch (e: Exception) { } }\n' >> "$P/$K/ui/LoginScreen.kt"
run_c error_handling login; expect_rc 1 "try/catch dans ui bloque"; expect_out "$K/ui/LoginScreen.kt" "le fichier est nommé"
reset; printf '\nfun f() = runCatching { 1 }\n' >> "$P/$K/data/LoginRepositoryImpl.kt"
run_c error_handling login; expect_rc 0 "runCatching dans data est permis"
reset
printf 'package com.x.login.domain\n\nimport android.content.Context\nimport com.x.login.data.LoginRepositoryImpl\n\nclass Login\n' > "$P/$K/domain/Login.kt"
printf 'package com.x.login.ui\n\nimport com.x.login.domain.LoginUseCase\n\nclass LoginViewModel(private val login: LoginUseCase)\n' > "$P/$K/ui/LoginViewModel.kt"
printf 'package com.x.login.ui\n\nimport com.x.design.AppTheme\nimport com.x.login.domain.LoginRepository\n\nfun Header(repo: LoginRepository, u: LoginUseCase) = Unit\n' > "$P/$K/ui/Header.kt"
run_c deps login; expect_rc 1 "deps : violations bloquent"
expect_out "domain → data interdit" "domain n'importe pas data"; expect_out "domaine impur : pas d'Android" "domain sans android.*"
expect_out "presentation → repository (LoginRepository)" "la présentation ne voit aucun repository"
expect_no_out "LoginViewModel.kt" "le ViewModel peut appeler un use case"
reset

echo "design system, chaînes, strings.xml"
printf '\nfun Box() { val c = Color(0xFF00FF00); val p = 16.dp }\n' >> "$P/$K/ui/LoginScreen.kt"
run_c design_system login; expect_rc 1 "valeurs visuelles en dur"; expect_out "Color(0xFF00FF00)" "la ligne est nommée"
reset; printf 'package com.x.login.ui\n\nfun ProfileScreen() = Unit\n' > "$P/$K/ui/ProfileScreen.kt"
run_c design_system login; expect_rc 1 "un écran sans import du design system"; expect_out "ProfileScreen.kt n'importe pas le design system" "l'écran est nommé"
reset; printf '\nfun T() { Text("Bonjour tout le monde"); Text(stringResource(R.string.login_title)) }\n' >> "$P/$K/ui/LoginScreen.kt"
run_c l10n_strings login; expect_rc 1 "chaîne en dur dans Text()"; expect_out "Bonjour" "la chaîne est nommée"
reset; sed -i.bak 's#</resources>#    <string name="login_error">Erreur</string>\n</resources>#' "$P/src/main/res/values/strings.xml"; rm -f "$P/src/main/res/values/strings.xml.bak"
run_x l10n_arb login; expect_rc 1 "clé ajoutée absente de values-en"; expect_out "values-en/strings.xml : clés manquantes : login_error" "la locale et la clé sont nommées"
printf '<resources>\n    <string name="login_title">Sign in</string>\n    <string name="login_error">Error</string>\n</resources>\n' > "$P/src/main/res/values-en/strings.xml"
run_x l10n_arb login; expect_rc 0 "toutes les locales ont la clé"
reset

echo "hygiène des tests, README"
printf '\nfun slow() { Thread.sleep(100) }\n' >> "$P/$T/ui/LoginScreenTest.kt"
run_c test_hygiene login; expect_rc 1 "Thread.sleep dans un test"; expect_out "Thread.sleep" "la ligne est nommée"
reset; rm "$P/README.md"
run_c package_readme login; expect_rc 1 "README absent d'un module bibliothèque"
reset

echo "checks que seul Flutter a, profil complet"
run_c build_runner login; expect_rc 0 "build_runner ne bloque pas"; expect_out "[N/A]  build_runner : non applicable à android" "build_runner non applicable à android"
sed -i.bak '/ktlint/d; /kover/d' "$P/build.gradle.kts"; rm -f "$P/build.gradle.kts.bak"
printf 'package com.x.login.data\n\nimport com.x.login.domain.LoginRepository\n\nclass LoginRepositoryImpl : LoginRepository {\n    override suspend fun login(user: String): Result<Unit> = Result.success(Unit)\n}\n' > "$P/$K/data/LoginRepositoryImpl.kt"
run_x clean login   # rouge hors pipeline (pas de gel) : on lit ce que le JSON dit de chaque check
json '.not_applicable' clean
expect_out '"format"' "profil clean : format non applicable (pas de formateur)"
expect_out '"metrics"' "profil clean : metrics non applicable à android"
json '.passed' clean; expect_out '"analyze"' "profil clean : analyze passé"
reset

echo "Android CLI (android_cli.sh) — commandes passées, CLI simulé"
mkdir -p "$TMP_ROOT/bin"
cat > "$TMP_ROOT/bin/android" <<'EOS'
#!/usr/bin/env bash
echo "android $*" >> "$ANDROID_LOG"
[ "$1" = --no-metrics ] && shift
[ "$1 $2" = "preview list" ] && { echo com.x.login.ui.LoginScreenKt.LoginPreview; echo com.x.login.ui.LoginScreenKt.DarkPreview; }
exit 0
EOS
chmod +x "$TMP_ROOT/bin/android"; export ANDROID_LOG="$TMP_ROOT/android.log"
OUT="$(cd "$P" && PATH="$TMP_ROOT/bin:$PATH" ANDROID_CLI="android --no-metrics" bash "$TESTS_DIR/../../../stacks/android/android_cli.sh" preview . "$TMP_ROOT/previews" 2>&1)"; RC=$?
expect_rc 0 "preview : rend la main"
OUT="$(cat "$ANDROID_LOG")"
expect_out "android --no-metrics preview list :feature:login --format=text" "preview list sur le module, --no-metrics"
expect_out "preview render :feature:login --component-tree --format=json --output=" "preview render : module, arbre de composants JSON"
expect_out "/previews --fqn=com.x.login.ui.LoginScreenKt.LoginPreview --fqn=com.x.login.ui.LoginScreenKt.DarkPreview" "preview render : le dossier, chaque preview listée"
OUT="$(cd "$P" && ANDROID_CLI=android-absent bash "$TESTS_DIR/../../../stacks/android/android_cli.sh" layout x.json 2>&1)"; RC=$?
expect_rc 3 "Android CLI absent : exit 3"; expect_out "non applicable" "dit non applicable"

echo "doctor — outils Android"
OUT="$(cd "$R" && PATH="$TMP_ROOT/bin:$PATH" bash "$GAUNTLET" doctor 2>&1)"
expect_out "== langage : android ==" "le doctor reconnaît le projet Android"
expect_out "racine Gradle (settings.gradle.kts)" "racine Gradle trouvée"
expect_out "Android CLI (android)" "Android CLI vérifié (ici le faux)"
expect_no_out "dart_code_linter" "aucun outil Flutter demandé"

echo "rapport HTML — les checks non applicables d'un gate"
OUT="$(python3 -c "import sys; sys.path.insert(0, '$TESTS_DIR/../../report'); sys.path.insert(0, '$TESTS_DIR/../..'); import report; print(report.gauntlet_results('$R/.claude/features/login/.gauntlet'))" 2>&1)"
expect_out "<th>non applicables</th>" "colonne non applicables"
expect_out "Non vérifiés</b> : " "liste des non vérifiés sous le tableau"
expect_out "<code>metrics</code>" "metrics y est nommé"

finish
