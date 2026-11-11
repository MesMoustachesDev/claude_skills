---
paths:
  - "**/*.kt"
  - "**/*.kts"
  - "**/AndroidManifest.xml"
  - "**/res/values*/*.xml"
---
# Android natif (Kotlin) — conventions de test

Ce que `~/.claude/commands/create_test.md` (la philosophie, sans langage) et les agents de test veulent dire en
Kotlin / Android. Vocabulaire et architecture : `android.md`, chargée en même temps.

## Stack de test

JUnit 4 (`org.junit.Test`, ce qu'utilisent Robolectric et les règles Compose ; JUnit 5 si le projet l'a déjà),
MockK, Turbine pour les `Flow`, `kotlinx-coroutines-test` (`runTest`, `StandardTestDispatcher`), Robolectric et
`androidx.compose.ui:ui-test-junit4` pour les tests Compose sur la JVM. Assertions : `kotlin.test` ou celles du
projet (Truth, AssertK) — une seule lib par module.

Le gate lance **`src/test` seulement** (`./gradlew :<module>:testDebugUnitTest`, ou `test` pour un module JVM) :
rapports JUnit XML sous `build/test-results/`. Un test de `src/androidTest` demande un appareil : il ne compte
ni pour `red_check`, ni pour `test`, ni pour la couverture. D'où : tout test d'UI qui peut tourner sous
Robolectric va dans `src/test`.

Lancer un fichier : `./gradlew :<module>:testDebugUnitTest --tests '<paquet>.<Classe>'` (ou
`stack.sh get test_files_cmd` puis le chemin du fichier : le lanceur le traduit).

## Structure du fichier test

```kotlin
class GetProfileUseCaseTest {
    // Dépendances : MockK pour un appel à vérifier, un fake écrit à la main pour un repository à état.
    private val repository = mockk<ProfileRepository>()
    private val useCase = GetProfileUseCase(repository)

    @Test
    fun `returns the profile when the repository finds it`() = runTest {
        coEvery { repository.profile("42") } returns Result.success(aProfile(id = "42"))

        val result = useCase("42")

        assertEquals(Result.success(aProfile(id = "42")), result)
    }
}
```

- Un test = un comportement, nommé en phrase entre backticks (`fun \`shows an error when offline\`()`).
- Données de test par des fabriques (`aProfile(id = …)`) dans le dossier de test, pas de littéraux recopiés.
- `@Before` seulement pour ce que tous les tests partagent ; pas d'état mutable entre tests.

## Pour les ViewModels

```kotlin
class ProfileViewModelTest {
    @get:Rule val mainDispatcher = MainDispatcherRule()   // Dispatchers.setMain(StandardTestDispatcher())

    private val getProfile = mockk<GetProfileUseCase>()

    @Test
    fun `loads then shows the profile`() = runTest {
        coEvery { getProfile("42") } returns Result.success(aProfile())
        val viewModel = ProfileViewModel(getProfile, SavedStateHandle(mapOf("id" to "42")))

        viewModel.uiState.test {
            assertEquals(ProfileUiState.Loading, awaitItem())
            assertEquals(ProfileUiState.Loaded(aProfile()), awaitItem())
        }
    }
}
```

- `MainDispatcherRule` (une règle du module de test partagé, sinon dans le fichier) : `viewModelScope` tourne sur
  `Dispatchers.Main`, absent de la JVM.
- Les dispatchers injectés reçoivent le `StandardTestDispatcher` du test (`UnconfinedTestDispatcher` seulement
  pour un `stateIn` qui doit démarrer tout de suite).
- `StateFlow` : Turbine (`test { awaitItem() }`), ou `uiState.value` après `advanceUntilIdle()`. Jamais
  `Thread.sleep` ni `delay` réel (gate `test_hygiene`).
- Un événement : `viewModel.onEvent(XxxUiEvent.Submit)`, puis l'état attendu.

## Pour les Use Cases et les repositories

- Use case : son repository mocké (`coEvery … returns`), chaque branche du résultat (succès, chaque erreur de
  §7) testée.
- Repository : ses data sources mockées ou fakes ; l'erreur d'I/O (exception levée par la data source) devient
  le résultat d'erreur attendu ; une `CancellationException` est relancée, pas convertie (test dédié).
- Mapper : une table d'entrées → sorties, un cas par champ optionnel ou absent.

## Pour les écrans Compose

```kotlin
@RunWith(AndroidJUnit4::class)          // Robolectric, dans src/test
@Config(sdk = [34])
class ProfileScreenTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun `shows the error and retries`() {
        var events = listOf<ProfileUiEvent>()
        compose.setContent { AppTheme { ProfileScreen(ProfileUiState.Error, onEvent = { events += it }) } }

        compose.onNodeWithTag(ProfileTestTags.RETRY).performClick()

        assertEquals(listOf(ProfileUiEvent.Retry), events)
    }
}
```

- Sélection par `onNodeWithTag(XxxTestTags.X)`, jamais `onNodeWithText` (le texte change avec la locale).
- `XxxScreen(state, onEvent)` se teste seul ; le câblage au ViewModel se prouve en acceptation.
- `compose.waitUntil { … }` ou `waitForIdle()` pour attendre un état, jamais une durée.
- `testOptions { unitTests.isIncludeAndroidResources = true }` dans le `build.gradle.kts` du module : sans lui,
  Robolectric ne trouve pas les ressources.

## Pièges d'égalité et d'asynchrone (Théo)

- Assertions sur le contenu : `assertNotNull(x)` seul est un déchet.
- `data class` : `==` compare les champs, une `List` aussi (par contenu) ; un `Array` compare l'identité —
  `contentEquals`, ou une `List` dans le modèle.
- Pas de `verify` / `coVerify` sauf effet de bord critique listé dans la spec.
- `runTest` : une coroutine lancée dans un autre scope que celui du test n'est pas attendue ; injecte le scope
  ou le dispatcher.

## Emplacement des fichiers

Miroir de `src/main/kotlin/` dans `src/test/kotlin/`, même paquet :

| Source | Test |
|--------|------|
| `src/main/kotlin/<p>/domain/GetFooUseCase.kt` | `src/test/kotlin/<p>/domain/GetFooUseCaseTest.kt` |
| `src/main/kotlin/<p>/data/FooRepositoryImpl.kt` | `src/test/kotlin/<p>/data/FooRepositoryImplTest.kt` |
| `src/main/kotlin/<p>/data/FooMapper.kt` | `src/test/kotlin/<p>/data/FooMapperTest.kt` |
| `src/main/kotlin/<p>/ui/FooViewModel.kt` | `src/test/kotlin/<p>/ui/FooViewModelTest.kt` |
| `src/main/kotlin/<p>/ui/FooScreen.kt` | `src/test/kotlin/<p>/ui/FooScreenTest.kt` |

Tests de mutation (Hugo) : nouveaux fichiers à côté du test existant, suffixés `MutationTest.kt`
(`GetFooUseCaseMutationTest.kt`). La mutation (pitest) n'existe que si le projet applique un plugin pitest ;
sinon le gate est non applicable et Hugo n'a pas de survivants à tuer : il le dit.
Sondes de `/reviewPR` (Maëlle) : `<dossier de la revue>/probes/<nn>_<slug>Test.kt`, posées le temps du run dans
`src/test/kotlin/review_probe/` (`probe_dir`), jamais commitées.

## Ce que lit l'auteur des tests (Théo)

Contrats : `src/main/*/domain/**` (entités, interfaces, use cases), `*UiState.kt`, `*UiEvent.kt`,
`*TestTags.kt`, les modèles de `data/` (`@Serializable`, `@Entity`). Jamais `*Impl.kt`, `*ViewModel.kt`, ni le
corps des écrans. Un module encore vide : lis d'abord un fichier `.kt` du module de référence.

## Acceptation (Gherkin → tests Compose nommés)

Pas d'outil Gherkin imposé en Kotlin (Cucumber-Android demande un appareil, et le gauntlet ne lance que la JVM).
- `src/test/resources/<feature>.feature` : §4 recopié tel quel (la trace), et un test par scénario dans
  `src/test/kotlin/<p>/ui/<Feature>AcceptanceTest.kt`, **nommé exactement comme le scénario**
  (`` fun `Shows the profile after login`() ``), ses étapes en commentaires `// Given …`, `// When …`, `// Then …`
  au-dessus du code qui les joue.
- Dans `tests_plan.json`, le scénario est listé **sur le `.feature`** (`layer: acceptance`), jamais sur la méthode :
  `test_plan_match` rattache la méthode JUnit qui porte son titre (casse ignorée) au scénario, elle ne compte pas en
  plus. Un scénario sans méthode du même nom reste « prévu, pas écrit ».
- L'acceptation tourne sur le **vrai ViewModel**, branché sur des use cases mockés, rendu par le vrai écran
  (`XxxRoute` avec le ViewModel construit dans le test) sous Robolectric. Une action de l'utilisateur :
  `performClick`, `performTextInput` ; une réponse d'un système extérieur : `coEvery { useCase(…) } returns …`
  (l'erreur de §7 pour un cas d'erreur, un `MutableSharedFlow` pour un use case qui observe) ; un résultat
  visible : `onNodeWithTag(…).assertIsDisplayed()` / `assertTextEquals(…)`.
- Deux moitiés en parallèle : zones data `src/test/*/{data,domain,di}/**` ; présentation `src/test/*/ui/**`
  (ViewModel, écrans, acceptation) et `src/test/resources/*.feature`.

## QA Maestro sur Android natif (Quentin)

- `qa.platforms = android` (pas d'iOS), `android.build = ./gradlew :app:assembleDebug`, `android.apk =
  app/build/outputs/apk/debug/app-debug.apk`, `android.app_id` = l'`applicationId` du variant debug.
- Maestro lit les testTags comme `id:` **seulement** si l'écran active
  `Modifier.semantics { testTagsAsResourceId = true }` (une fois, sur la racine) : `tapOn: { id: "login_submit" }`.
  Sans lui, le flow ne trouve rien ; c'est un défaut de l'implémentation, pas du flow.
- Un flow rouge : le gate écrit `qa/android/layout.json` (hiérarchie de l'écran à l'arrêt, `android layout`)
  quand Android CLI est là ; lis-le avant de conclure qu'un élément manque.
- Les tests de `src/androidTest` (instrumentés) ne remplacent pas un flow : ils ne passent pas par l'APK installé.

## QA sans écran, par adb (Quentin)

Une feature sans écran (aucun `@Composable` dans son périmètre : AppFunctions, service, receiver…) n'a pas de
flow Maestro. Chaque scénario de §4 se joue sur l'APK installé, en ligne de commande, et le gate `qa` lit
`qa.md` au lieu de lancer Maestro. Dès qu'un fichier du périmètre déclare un `@Composable`, les flows sont exigés.
- Émulateur à **2 cœurs au moins** (instance jetable `-read-only -no-snapshot -cores 4`) : sur un AVD à 1 cœur,
  `adb shell cmd app_function execute-app-function` se bloque dans system_server et finit en « Timed out ».
- AppFunctions : `adb shell cmd app_function list-app-functions` pour l'index, puis
  `execute-app-function --package <appId> --function <functionId complet> --parameters '<json>'`. Le functionId
  est l'identifiant complet de l'index (classe qualifiée et `#` méthode), jamais le nom court de la fonction.
- Données : d'abord par les fonctions de l'app elles-mêmes. Quand aucune fonction ne permet de préparer l'état
  (plan archivé, séance faite, données corrompues), par la base de l'app debug : `run-as <appId>` pour copier la
  base sur l'hôte, `sqlite3` dessus (app arrêtée, `-wal` et `-shm` retirés), puis la repousser. Le SQL joué va
  dans `qa/android/setup_db.sql`.
- Chaque appel écrit sa sortie brute dans `qa/android/<nn>_<slug>.txt`. `qa.md` garde le tableau
  `| # | Scénario | Android | Observation |` : une ligne par scénario de §4, titre exact, verdict ✓ (« ✓ avec
  réserve » compris), ✗ ou « non vérifié », et pour chaque ✓ le fichier de sortie brute entre backticks dans
  l'Observation. Le gate est rouge s'il manque un scénario, sur un ✗ ou un « non vérifié », ou si un ✓ ne cite
  aucun fichier présent dans `qa/android/`.
