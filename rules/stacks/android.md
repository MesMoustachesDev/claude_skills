---
paths:
  - "**/*.kt"
  - "**/*.kts"
  - "**/AndroidManifest.xml"
  - "**/res/values*/*.xml"
---
# Android natif (Kotlin, Gradle, Jetpack Compose) — doctrine du pipeline

Chargée par Claude Code au premier fichier `.kt`, `.kts`, `AndroidManifest.xml` ou `res/values*/*.xml` lu
(ADR 0011). Les agents, commandes et `pipeline/*.md` parlent sans langage (« la commande de test du langage »,
« le state holder », « le fichier de clés ») : cette règle dit ce que ces mots veulent dire en Android natif.
Les règles du projet (`.claude/rules/`) disent comment **ce** projet les applique et priment. Les conventions de
test sont dans `android-tests.md`, chargée en même temps.

Une app Flutter a aussi du Kotlin dans `android/app/` : cette règle vaut pour ce code-là (plugin natif, canal
plateforme), pas pour le Dart de `lib/`.

## Vocabulaire du pipeline → Android

| Le pipeline dit | En Android |
|---|---|
| le package, `<package>/` | un **module Gradle** (`feature/login/`, son `build.gradle.kts`), déclaré dans `settings.gradle.kts` |
| le code du package, `<src>/` | `src/main/kotlin/<paquet>/` : `data/`, `domain/`, `ui/` (ou `presentation/`), `di/` ; les ressources dans `src/main/res/` |
| les tests miroir, `<tests>/` | `src/test/kotlin/<paquet>/` (JVM : unitaires, ViewModel, Compose sous Robolectric) ; `src/androidTest/` pour l'instrumenté |
| le state holder | le **ViewModel** (`androidx.lifecycle.ViewModel`) qui expose un `StateFlow<XxxUiState>` ; `XxxUiState` sealed (ou data class + sealed pour les cas) ; les actions de l'écran en `sealed interface XxxUiEvent` |
| la DI | Hilt (`@HiltViewModel`, `@Inject constructor`, `@Module @InstallIn`) ou Koin (`module { viewModelOf(::X) }`) : celle du projet |
| le type résultat, l'erreur typée | `Result<T>` de Kotlin, ou le type scellé d'erreur du projet (`sealed interface XxxError`) ; jamais une exception qui traverse le domaine |
| le fichier de clés | `XxxTestTags.kt` (`object XxxTestTags { const val SUBMIT = "login_submit" }`), lu par `Modifier.testTag(…)` |
| le manifeste du package | `build.gradle.kts` du module ; les versions dans `gradle/libs.versions.toml` (catalogue) |
| la commande de test du langage | `./gradlew :<module>:testDebugUnitTest` (`test` pour un module Kotlin/JVM pur) ; un fichier : `--tests <paquet>.<Classe>` ; `stack.sh get test_cmd` (lanceur `stacks/android/gradle_run.sh`) |
| l'analyse statique | la compilation (`compileDebugUnitTestKotlin`), Android lint (`lintDebug`), detekt s'il est appliqué ; le formatage ktlint (`ktlintCheck` / `ktlintFormat`) ou Spotless (`spotlessCheck` / `spotlessApply`) |
| l'installation des dépendances | aucune : Gradle résout au build. Une dépendance s'ajoute au catalogue, puis au `build.gradle.kts` du module |
| la génération de code | KSP / kapt, dans le build (Hilt, Room, Moshi) ; rien à lancer, rien à commiter (`build/`) |
| la lib de mock | MockK (`mockk`, `coEvery`, `coVerify`) ; des fakes écrits à la main pour les repositories |
| l'outil Gherkin | aucun outil imposé : un scénario = un test Compose nommé d'après lui (voir `android-tests.md`, Acceptation) |
| un test d'UI | un test Compose : `createComposeRule()` dans `src/test` sous Robolectric (sinon `createAndroidComposeRule` en `src/androidTest`) |
| les textes de l'interface | `res/values/strings.xml` et ses locales `values-xx/` ; `stringResource(R.string.…)` |
| un stub | `TODO()` (lève `NotImplementedError`) |
| le scaffold | pas de brick mason : voir Contrats |
| les gabarits du langage | `~/.claude/stacks/android/templates/` |

## Gestion d'erreur (règle de base, non négociable)

Un `try/catch` (ou `runCatching`) n'existe que dans la couche `data/`, autour de l'I/O (réseau, base Room,
DataStore, fichiers, SDK tiers). La data le convertit en `Result<T>` (ou le type d'erreur du projet). Domain,
ui et di n'en contiennent **aucun** : ils composent des résultats (`map`, `fold`, `getOrElse`) et seul le
ViewModel les transforme en `UiState`. En coroutine, un `catch (e: Exception)` avale aussi la
`CancellationException` : la data la relance (`catch (e: CancellationException) { throw e }` avant, ou
`ensureActive()`). Une fonction qui fait une I/O rend un résultat : un `suspend fun save(x): Unit` qui lève est
un **bloquant** (critique de spec) et un **critique** (revue). Gate : `error_handling`.

## Architecture

- Couches : `ui → domain ← data`, `di` les assemble. Le domaine est du Kotlin pur : ni `android.*` ni
  `androidx.*` (sauf `androidx.annotation`), idéalement un module `kotlin("jvm")`. Gate : `deps` (couche lue
  dans le chemin et le paquet, `deps.<couche>` de la config).
- Le ViewModel appelle des use cases (`class GetXUseCase(private val repo: XRepository) { suspend operator fun
  invoke(…) }`), jamais un repository. Un composable ne voit ni use case ni repository : il reçoit l'état et
  des lambdas.
- Écran = deux composables : `XxxRoute(viewModel: XxxViewModel = hiltViewModel())` lit
  `collectAsStateWithLifecycle()` et passe `XxxScreen(state, onEvent)`, sans ViewModel, prévisualisable et
  testable. Chaque `XxxScreen` a ses `@Preview` (un par état de l'`UiState`).
- Coroutines : `viewModelScope` dans le ViewModel ; les dispatchers s'injectent (`@IoDispatcher`), jamais
  `Dispatchers.IO` en dur (les tests les remplacent) ; `stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), initial)`.
- Navigation : la route et ses arguments vivent dans le module de la feature (`fun NavGraphBuilder.xxxScreen()`),
  l'app ne fait que l'enregistrer.

## Contrats (Arthur)

- Brouillon : entités, interfaces de repository et de data sources (`domain/`), signatures des use cases,
  `XxxUiState` et `XxxUiEvent` **sealed**, `XxxTestTags.kt` (un tag par élément que les séquences touchent ou
  vérifient). Fichiers de contrat lus par le gate : `*/domain/*`, `*UiState.kt`, `*UiEvent.kt`, `*TestTags.kt`.
- Avant de poser le brouillon d'un module neuf, lis un fichier `.kt` du module de référence : c'est ce qui
  charge cette règle.
- **Scaffold d'un module (create), sans brick** : copier la forme du module de feature le plus proche, pas
  l'inventer.
  1. `feature/<nom>/build.gradle.kts` : les mêmes plugins que le module de référence (souvent un plugin de
     convention `id("<projet>.android.feature")`, sinon `com.android.library` + `kotlin.android` + Compose +
     Hilt/KSP) et `android { namespace = "<paquet>.<nom>" }`.
  2. `include(":feature:<nom>")` dans `settings.gradle.kts` ; la dépendance `implementation(project(":feature:<nom>"))`
     dans `app/build.gradle.kts` (zone `writes.extra`).
  3. Les dossiers `src/main/kotlin/<paquet>/<nom>/{data,domain,ui,di}`, `src/test/kotlin/<paquet>/<nom>/`,
     `src/main/res/values/strings.xml`, et le `README.md` (sections `readme.sections`).
  4. `./gradlew :feature:<nom>:compileDebugUnitTestKotlin` doit passer avant de rendre la main.
  `create_feature_rules.md` du projet décrit sa structure ; elle prime.
- Stub d'une fonction d'implémentation, exactement :
  ```kotlin
  override suspend fun fetch(id: String): Result<X> = TODO()
  ```
  ou un bloc dont la seule instruction est `TODO()`. Dans un ViewModel, chaque événement a sa fonction
  (`fun onEvent(event: XxxUiEvent)` qui délègue à `private fun load()`…), stubbée. `XxxScreen` est un stub
  aussi (`TODO()`), ses `@Preview` attendent l'implémentation. Gate : `stub_check` (lit les fonctions au niveau
  du texte : une fonction d'interface ou abstraite n'a pas de corps et ne compte pas).
- Complétion : modèles réseau / Room (`@Serializable`, `@Entity`) et le squelette des mappers ; module de DI ;
  route ; clés `strings.xml` (et leurs locales).
- Dépendances du module : celles du module de référence et ce que §8 liste, par le catalogue
  (`libs.xxx`) ; en test : `junit`, `mockk`, `turbine`, `kotlinx-coroutines-test`, Robolectric et
  `ui-test-junit4` pour Compose.
- Appelants d'une signature changée : un seul `grep -rn '<nom>(' --include=*.kt` à la fin ; le gate compile le
  module.

## Implémentation et vues (Ivan, Nina, Fanny, Pauline)

- Zones des deux moitiés d'Ivan : data/domain `src/main/*/{data,domain,di}/**` et leurs tests ; présentation
  `src/main/*/ui/**` (ou `presentation/`), les ressources de ses écrans.
- Ordre : mappers → data sources → repository → use cases → ViewModel → écrans.
- Chaque tag de `XxxTestTags` est posé avec `Modifier.testTag(XxxTestTags.X)`. Pour Maestro, la racine de
  l'écran active `Modifier.semantics { testTagsAsResourceId = true }` : sans lui, Maestro ne voit pas les
  testTags (il lit `resource-id`). Design system (le thème Material du projet, ses tokens d'espacement et de
  couleur) pour toute valeur visuelle ; `stringResource` pour tout texte. Gates : `design_system`
  (`ds.forbidden` : `Color(0x…)`, `16.dp` en dur…), `l10n_strings`, `l10n_arb` (les locales de `strings.xml`).
- Refaire un écran : le contrat à préserver comprend le ViewModel et son `UiState`, chaque `testTag` (ni
  supprimé, ni déplacé, ni renommé), les clés `strings.xml`.
- Traces de travail interdites à la livraison : `println(`, `printStackTrace()` (gate `no_temp_markers`) ;
  `Log.d` passe par le logger du projet.
- Compose : état hissé (`XxxScreen` sans état propre hors `remember` d'UI), `LazyColumn` avec `key =`, pas de
  calcul lourd dans la composition (`remember`, `derivedStateOf`), lambdas stables.

## Voir un écran sans appareil (Android CLI)

`~/.claude/stacks/android/android_cli.sh preview <module> <dossier> [fqn…]` rend les `@Preview` du module en PNG
avec leur **arbre de composants** JSON (bornes, testTags, sémantique, modifiers), sans émulateur
(`android preview render --component-tree --format=json`). À utiliser :
- **revue** (Romain) : regarder l'écran que décrit la spec, vérifier dans l'arbre que chaque testTag de §4 est
  posé et visible ;
- **polish** (Pauline) : captures avant / après de chaque état de l'`UiState` ;
- **QA rapide** (Quentin) : avant de démarrer l'émulateur, s'assurer que l'écran rend et porte ses tags.
`android_cli.sh layout <fichier> [serial]` donne la hiérarchie de l'écran affiché sur l'appareil (le gate `qa`
l'écrit dans `qa/android/layout.json` quand un flow est rouge). `android.emulator = cli` dans la config fait
démarrer l'AVD de QA par `android emulator start --headless`. Sans Android CLI (exit 3, « non applicable ») :
captures par Maestro sur l'émulateur, comme avant. La clé `android` de `stack.ini` porte `--no-metrics`.

## Spec (Sophie, Camille)

- Ce qui existe déjà : le module `core` (ou `common`) du projet : type résultat, dispatchers, logger,
  composants du design system.
- Le code source d'une dépendance : dans le cache Gradle (`~/.gradle/caches/modules-2/files-2.1/<groupe>/<artefact>/<version>/`,
  le `-sources.jar`), à la version du catalogue.
- Chaque testTag utilisé par §4 existe dans `XxxTestTags` ; §8 a une machine d'états Mermaid par ViewModel, dont
  les états et événements sont ceux de `XxxUiState` / `XxxUiEvent` ; aucune I/O faillible sans résultat.
- Les scénarios de §4 s'écrivent en anglais, courts : chacun devient un test Compose du même nom.

## Revue (Romain, Victor, Alice, Corentin)

- Couches : `ui → domain ← data` ; résultat déplié dans le ViewModel seulement ; aucun try/catch hors `data/` ;
  aucun modèle réseau ni repository en `ui/` ; domaine sans Android.
- Le module se lit de haut en bas : DI → use cases → ViewModel → écran. La visite guidée suit écran →
  ViewModel → use case → repository → data source (`layer` : `vue`, `viewmodel`, `usecase`, `repository`,
  `datasource`, `mapper`, `composant`).
- Items de la grille propres à Android : DS (thème, tokens), l10n (`strings.xml` et locales), testTags et
  `testTagsAsResourceId`, recompositions inutiles, cycle de vie (`collectAsStateWithLifecycle`), fuite de
  `Context` dans un ViewModel (critique).
- Dépendance ajoutée : la version du catalogue, la date de release, l'alternative AndroidX quand elle existe.
- Un `catch (e: Exception)` en coroutine qui avale la `CancellationException` est un **critique**.

## Réponses de Thibault, en Android

Celles de `pipeline/answers.md` valent en Android avec ces mots (transposition des réponses données en Flutter ;
une réponse propre à Android s'ajoute ici avec sa date) :
- Une écriture locale qui peut échouer (Room, DataStore, fichier) rend un résultat depuis la data source ; pas
  de `suspend fun …: Unit` qui lève.
- Couches strictes : ViewModel → use case → repository → data sources ; ne supprime jamais un use case appelé
  par un ViewModel.
- Tag de test manquant : Arthur l'ajoute à `XxxTestTags`, et l'implementer le pose avec `testTag`.

## Outillage

- `/feature init` : `stack = android` si le repo a aussi du Flutter ; `gradle = ./gradlew` (ou
  `./gradlew --offline` hors réseau) ; `android.build`, `android.apk`, `android.app_id` pour la QA ; le
  formateur (ktlint ou Spotless), la couverture (Kover ou JaCoCo), pitest : ce que le build applique, sinon
  les gates `format`, `coverage`, `mutation` sont **non applicables** (signalés, pas bloquants, ADR 0011).
- Checks sans version Android (non applicables) : `build_runner`, `metrics` (detekt les porte s'il est
  appliqué, via `analyze`), `reinvented`, `barrel_api`, `unused_code`, `unused_files`,
  `widget_functions`, `deps_unused`, `deps_features`, `pub_health`, `generated_fresh`, `test_plan`,
  `test_plan_match`, `test_dups`.
- `dedup_candidates` (étape 0d) : `stacks/android/kotlin_dedup.py`, lexer Kotlin en Python sans dépendance.
- Fichiers à copier dans un worktree neuf : `local.properties` (chemin du SDK), `google-services.json`, les
  `.env*` ; jamais un keystore.
- Doctor : JDK, wrapper `./gradlew` à la racine, Android CLI (avertissement), adb.
- `/fix` : un reproducer qui branche un runner de test peut toucher `build.gradle.kts` ou le catalogue ; un bug
  de rendu ou d'interaction se reproduit en test Compose (`onNodeWithTag`).
- Après les correctifs d'une MR : `./gradlew :<module>:compileDebugUnitTestKotlin` pour vérifier que ça compile.
