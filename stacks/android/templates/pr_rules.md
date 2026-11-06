# Règles PR — Android natif / Clean Architecture

## Architecture & couches

- Les entités du domaine sont du Kotlin pur : aucun import `android.*` ni `androidx.*` (sauf `androidx.annotation`), aucune annotation de sérialisation ou de base (`@Serializable`, `@Entity`)
- Les modèles réseau / Room vivent dans `data/` et se mappent vers les entités — jamais l'inverse
- Un repository est une interface du domaine ; son implémentation vit dans `data/`
- Un use case = une action métier (`operator fun invoke`). Pas de use case fourre-tout
- Un ViewModel ne connaît que des use cases — zéro import de data source, de repository impl, de Retrofit ou de Room
- Un composable ne fait pas de logique métier : il reçoit l'état et des lambdas, il n'appelle ni use case ni repository
- Direction des dépendances : `ui` → `domain` ← `data`. Jamais `domain` → `data` ou `domain` → `ui`

## Injection de dépendances

- Toute dépendance arrive par le constructeur (`@Inject constructor`) — pas d'objet global accédé dans une classe métier
- Les liaisons vivent dans `di/` (`@Module @InstallIn`, `@Binds` pour une interface) ; pas de `XxxRepositoryImpl()` instancié à la main dans un ViewModel ou un composable
- Les dispatchers s'injectent (`@IoDispatcher`) ; jamais `Dispatchers.IO` en dur dans une classe testée
- Portée explicite : `@Singleton` seulement pour un état partagé, avec un commentaire

## État et cycle de vie

- Le ViewModel expose un `StateFlow<XxxUiState>` en lecture seule ; le `MutableStateFlow` est privé
- `XxxUiState` est immuable (`data class` + `copy`, ou `sealed interface`) ; chaque écran traite chargement, erreur, succès, vide
- Pas de `Context`, `Activity`, `View` ni `NavController` dans un ViewModel ou un use case (fuite) — `SavedStateHandle` pour les arguments
- Côté UI : `collectAsStateWithLifecycle()`, jamais `collectAsState()` sur un flux de ViewModel
- Pas de `GlobalScope` ; `viewModelScope` dans le ViewModel, le scope injecté ailleurs

## Compose & UI

- `XxxRoute` (branché au ViewModel) et `XxxScreen(state, onEvent)` (sans ViewModel) ; chaque `XxxScreen` a ses `@Preview`
- Les valeurs visuelles viennent du thème et des tokens du design system : pas de `Color(0x…)`, de `16.dp` ni de `14.sp` en dur
- Les textes viennent de `stringResource(R.string.…)` ; chaque clé ajoutée existe dans toutes les locales `values-xx/`
- Chaque élément testé porte `Modifier.testTag(XxxTestTags.X)` ; la racine de l'écran active `testTagsAsResourceId` (Maestro)
- `LazyColumn` / `LazyRow` avec `key =` ; pas de calcul lourd dans la composition (`remember`, `derivedStateOf`)
- Un composant réutilisable va dans le module du design system — pas copié-collé entre features

## Gestion des erreurs

- Les erreurs métier sont typées (`Result<T>`, ou un `sealed interface XxxError`) — pas de `throw Exception("message")` dans le domaine
- `try/catch` et `runCatching` seulement dans `data/`, autour de l'I/O ; une `CancellationException` est relancée, jamais avalée
- Un `catch (e: Exception)` sans relance ni log est interdit
- L'UI affiche toujours un message compréhensible — jamais un écran blanc ni un crash

## Tests

- Chaque use case, mapper, repository et ViewModel ajouté a son test JVM dans `src/test` ; chaque écran a son test Compose (Robolectric)
- `runTest` et le temps virtuel ; jamais `Thread.sleep` ni `@Ignore`
- Sélection par `onNodeWithTag`, jamais par le texte affiché

## Build

- Une dépendance s'ajoute au catalogue `gradle/libs.versions.toml`, jamais une version en dur dans un `build.gradle.kts`
- Pas de `minSdk`, `compileSdk` ni de version de Kotlin changés dans une PR de feature
- Aucune clé d'API, aucun secret dans le code ou `gradle.properties` commité
