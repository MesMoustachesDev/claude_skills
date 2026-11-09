# Create Feature Rules — Android natif / Clean Architecture

Ce fichier définit les conventions et gabarits pour générer une feature Android selon une architecture modulaire
(un module Gradle par feature), clean architecture, ViewModel + `StateFlow`, Jetpack Compose, et erreurs typées
avec `Result`.

## Contexte technique

- **Langage** : Kotlin
- **UI** : Jetpack Compose (Material 3, thème du module `designsystem`)
- **Architecture** : Clean Architecture (domain / data / ui) en modules Gradle
- **DI** : Hilt (KSP)
- **State management** : ViewModel qui expose un `StateFlow<XxxUiState>`
- **Asynchrone** : coroutines et `Flow`
- **Error handling** : `Result<T>` de Kotlin (ou le type d'erreur scellé du module `core`)
- **Réseau** : Retrofit / OkHttp (ou Ktor), derrière une data source
- **Base locale** : Room (si applicable)

## Structure d'un module feature

```
feature/{feature_name}/
├── build.gradle.kts
├── README.md
└── src/
    ├── main/
    │   ├── kotlin/{paquet}/{feature_name}/
    │   │   ├── domain/
    │   │   │   ├── {Name}.kt                     # entité
    │   │   │   ├── {Name}Repository.kt           # interface
    │   │   │   └── Get{Name}UseCase.kt
    │   │   ├── data/
    │   │   │   ├── {Name}RepositoryImpl.kt
    │   │   │   ├── {Name}RemoteDataSource.kt     # interface + Impl
    │   │   │   ├── {Name}Dto.kt
    │   │   │   └── {Name}Mapper.kt
    │   │   ├── di/
    │   │   │   └── {Name}Module.kt
    │   │   └── ui/
    │   │       ├── {Name}ViewModel.kt
    │   │       ├── {Name}UiState.kt
    │   │       ├── {Name}UiEvent.kt
    │   │       ├── {Name}TestTags.kt
    │   │       ├── {Name}Screen.kt               # {Name}Route + {Name}Screen + @Preview
    │   │       └── {Name}Navigation.kt
    │   └── res/values/strings.xml
    └── test/
        ├── kotlin/{paquet}/{feature_name}/
        │   ├── domain/Get{Name}UseCaseTest.kt
        │   ├── data/{Name}RepositoryImplTest.kt
        │   ├── data/{Name}MapperTest.kt
        │   ├── ui/{Name}ViewModelTest.kt
        │   ├── ui/{Name}ScreenTest.kt
        │   └── ui/{Name}AcceptanceTest.kt
        └── resources/{feature_name}.feature
```

## Scaffold (sans brick)

Il n'y a pas de brick mason en Android. Le module se crée à la main, en copiant la forme du module de feature
existant le plus proche :
1. `feature/{feature_name}/build.gradle.kts` : mêmes plugins que le module de référence (plugin de convention du
   projet s'il y en a un), `android { namespace = "{paquet}.{feature_name}" }`,
   `testOptions { unitTests.isIncludeAndroidResources = true }`.
2. `include(":feature:{feature_name}")` dans `settings.gradle.kts` ; `implementation(project(":feature:{feature_name}"))`
   dans `app/build.gradle.kts`.
3. Les dossiers ci-dessus, `strings.xml`, `README.md`.
4. `./gradlew :feature:{feature_name}:compileDebugUnitTestKotlin` passe.

## Questions à poser

1. **Data sources** : Remote / Local / Les deux / Aucune
2. **Écran** : oui (Route + Screen + navigation) / non (module de logique seulement)
3. **Flux** : lecture ponctuelle (`suspend`) ou observation (`Flow`) ?

## Conventions strictes

- Un fichier = une classe publique ; nom du fichier = nom de la classe
- Entités : `data class` du domaine, sans annotation de sérialisation ni de base
- Use case : une classe, `suspend operator fun invoke(…)` (ou `operator fun invoke(): Flow<…>`)
- Repository et data sources : une interface (domaine pour le repository, data pour les sources), une `…Impl` liée par `@Binds`
- ViewModel : `@HiltViewModel`, `StateFlow` privé en `MutableStateFlow`, un `fun onEvent(event: {Name}UiEvent)`
- Écran : `{Name}Route` lit le ViewModel ; `{Name}Screen(state, onEvent)` n'en voit aucun
- `{Name}TestTags` : `object` de `const val`, préfixés `{feature_name}_`
- Stub (étape architect) : `TODO()`

## Error handling avec `Result`

- Seule la couche `data/` attrape : `try { … } catch (e: CancellationException) { throw e } catch (e: IOException) { Result.failure(e) }`
- Domaine et ViewModel composent : `result.map { … }`, `fold(onSuccess = …, onFailure = …)`
- Une erreur métier précise : un `sealed interface {Name}Error` du domaine, porté par `Result.failure` ou un type scellé du projet
- Un repli sur une valeur par défaut dans un `catch` (ou `.catch {}` d'un Flow) journalise l'erreur avant de rendre le repli : un repli silencieux cache la panne. (learn 2026-11-09, swallowed_error_without_log, 2 runs)

## Gabarits de fichiers

### Entité (`domain/{Name}.kt`)

```kotlin
package {paquet}.{feature_name}.domain

data class {Name}(
    val id: String,
    val title: String,
)
```

### Repository (`domain/{Name}Repository.kt`)

```kotlin
package {paquet}.{feature_name}.domain

interface {Name}Repository {
    suspend fun fetch(id: String): Result<{Name}>
}
```

### Use case (`domain/Get{Name}UseCase.kt`)

```kotlin
package {paquet}.{feature_name}.domain

import javax.inject.Inject

class Get{Name}UseCase @Inject constructor(
    private val repository: {Name}Repository,
) {
    suspend operator fun invoke(id: String): Result<{Name}> = TODO()
}
```

### Repository impl (`data/{Name}RepositoryImpl.kt`)

```kotlin
package {paquet}.{feature_name}.data

import {paquet}.{feature_name}.domain.{Name}
import {paquet}.{feature_name}.domain.{Name}Repository
import javax.inject.Inject

class {Name}RepositoryImpl @Inject constructor(
    private val remote: {Name}RemoteDataSource,
) : {Name}Repository {
    override suspend fun fetch(id: String): Result<{Name}> = TODO()
}
```

### DI (`di/{Name}Module.kt`)

```kotlin
package {paquet}.{feature_name}.di

import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

@Module
@InstallIn(SingletonComponent::class)
internal abstract class {Name}Module {
    @Binds abstract fun repository(impl: {Name}RepositoryImpl): {Name}Repository
    @Binds abstract fun remote(impl: {Name}RemoteDataSourceImpl): {Name}RemoteDataSource
}
```

### UiState, UiEvent, TestTags (`ui/`)

```kotlin
sealed interface {Name}UiState {
    data object Loading : {Name}UiState
    data class Loaded(val item: {Name}) : {Name}UiState
    data object Empty : {Name}UiState
    data object Error : {Name}UiState
}

sealed interface {Name}UiEvent {
    data object Retry : {Name}UiEvent
}

object {Name}TestTags {
    const val SCREEN = "{feature_name}_screen"
    const val ERROR_RETRY = "{feature_name}_error_retry"
}
```

### ViewModel (`ui/{Name}ViewModel.kt`)

```kotlin
@HiltViewModel
class {Name}ViewModel @Inject constructor(
    private val get{Name}: Get{Name}UseCase,
    savedStateHandle: SavedStateHandle,
) : ViewModel() {
    private val _uiState = MutableStateFlow<{Name}UiState>({Name}UiState.Loading)
    val uiState: StateFlow<{Name}UiState> = _uiState.asStateFlow()

    fun onEvent(event: {Name}UiEvent): Unit = TODO()
}
```

### Écran (`ui/{Name}Screen.kt`)

```kotlin
@Composable
fun {Name}Route(viewModel: {Name}ViewModel = hiltViewModel()) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    {Name}Screen(state, viewModel::onEvent)
}

@Composable
fun {Name}Screen(state: {Name}UiState, onEvent: ({Name}UiEvent) -> Unit) {
    TODO()
}

@Preview
@Composable
private fun {Name}ScreenErrorPreview() = AppTheme { {Name}Screen({Name}UiState.Error) {} }
```

### `build.gradle.kts` (sans plugin de convention)

```kotlin
plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.hilt)
    alias(libs.plugins.ksp)
}

android {
    namespace = "{paquet}.{feature_name}"
    testOptions { unitTests.isIncludeAndroidResources = true }
}

dependencies {
    implementation(project(":core"))
    implementation(project(":designsystem"))
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)
    testImplementation(libs.junit)
    testImplementation(libs.mockk)
    testImplementation(libs.turbine)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.robolectric)
    testImplementation(libs.androidx.compose.ui.test.junit4)
}
```
