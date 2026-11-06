# Create Screen Rules — Android / Jetpack Compose

Ce fichier définit comment créer ou refaire un écran Compose dans ce projet : où il vit, ce qu'il lit, ce qu'il
doit préserver. Les règles d'architecture sont dans `create_feature_rules.md` ; celles de revue dans `pr_rules.md`.

## Contexte technique

- **UI** : Jetpack Compose, Material 3, thème `AppTheme` du module `designsystem`
- **State management** : ViewModel + `StateFlow<XxxUiState>`, lu par `collectAsStateWithLifecycle()`
- **Navigation** : Navigation Compose, une extension `NavGraphBuilder.xxxScreen()` par feature
- **Textes** : `strings.xml` et ses locales, `stringResource(R.string.…)`

## Philosophie

- Un écran = `XxxRoute` (branchement) + `XxxScreen(state, onEvent)` (rendu pur). Seul `XxxScreen` contient de l'UI.
- Le rendu est une fonction de l'état : aucune logique métier, aucun appel réseau, aucune lecture de préférence.
- Chaque état de `XxxUiState` a son rendu et son `@Preview` (chargement, erreur, vide, contenu).
- Un composant qui sert deux écrans va dans le design system, pas dans la feature.

## Détection automatique dans le projet

### Design System
Chercher le module du thème (`designsystem`, `core:ui`) : `AppTheme`, les tokens d'espacement
(`AppTheme.spacing.m`, `Dimens`), la typographie (`MaterialTheme.typography`), les composants (`AppButton`,
`AppTopBar`). Les utiliser ; ne rien redéfinir localement.

### State Management
Lire un ViewModel existant du projet : forme de l'`UiState` (sealed ou data class), nom de la fonction d'événement,
façon d'exposer les effets ponctuels (navigation, snackbar : `Channel` + `receiveAsFlow`, ou champ d'état consommé).

### Localisation
`src/main/res/values/strings.xml` du module ; les locales `values-xx/` existantes reçoivent chaque clé ajoutée.

### Navigation
La route vit dans `XxxNavigation.kt` du module (`const val XXX_ROUTE`, ou une route typée `@Serializable`) ;
l'app l'enregistre dans son `NavHost`.

## Questions à poser

1. Source : maquette (capture, lien), description textuelle, ou écran existant à refaire ?
2. États à afficher (chargement, erreur, vide, contenu) et ce qui les déclenche
3. Actions de l'utilisateur et où elles mènent

## Traitement de l'input

- **Capture de maquette** : relever la structure (barre, contenu défilant, actions en bas), les composants du DS
  qui correspondent, les espacements en tokens. Ne pas recopier des valeurs en px.
- **Description textuelle** : en déduire l'`UiState` et les événements avant d'écrire du Compose.

## Structure cible des fichiers

```
ui/
├── XxxViewModel.kt
├── XxxUiState.kt
├── XxxUiEvent.kt
├── XxxTestTags.kt
├── XxxScreen.kt          # XxxRoute, XxxScreen, @Preview
├── XxxNavigation.kt
└── component/            # morceaux privés à l'écran, si XxxScreen dépasse ~150 lignes
```

## Conventions visuelles strictes

- Couleurs : `MaterialTheme.colorScheme.*` ; jamais `Color(0x…)` ni `Color.Red` (gate `design_system`)
- Espacements et tailles : tokens du DS ; jamais `16.dp` ni `14.sp` en dur (gate `design_system`)
- Typographie : `MaterialTheme.typography.*`
- Textes : `stringResource(R.string.…)` ; jamais une chaîne en dur dans `Text("…")` (gate `l10n_strings`)
- Chaque élément que la spec touche ou vérifie : `Modifier.testTag(XxxTestTags.X)` ; la racine :
  `Modifier.semantics { testTagsAsResourceId = true }` (Maestro lit les tags comme `id:`)
- Accessibilité : `contentDescription` sur les icônes porteuses de sens (depuis `strings.xml`), cibles ≥ 48.dp
  (token du DS)

## Anatomie de page

### Squelette commun

```kotlin
@Composable
fun XxxScreen(state: XxxUiState, onEvent: (XxxUiEvent) -> Unit) {
    Scaffold(
        modifier = Modifier.testTag(XxxTestTags.SCREEN).semantics { testTagsAsResourceId = true },
        topBar = { AppTopBar(title = stringResource(R.string.xxx_title)) },
    ) { padding ->
        when (state) {
            XxxUiState.Loading -> AppLoading(Modifier.padding(padding))
            XxxUiState.Error -> AppError(onRetry = { onEvent(XxxUiEvent.Retry) }, modifier = Modifier.padding(padding))
            XxxUiState.Empty -> AppEmpty(Modifier.padding(padding))
            is XxxUiState.Loaded -> XxxContent(state, onEvent, Modifier.padding(padding))
        }
    }
}
```

### Règles

- Un `when` exhaustif sur l'état, sans `else`
- Le padding du `Scaffold` est appliqué au contenu
- Insets : `Scaffold` les gère ; pas de `statusBarsPadding()` en plus

### Anatomie du projet

<!-- À compléter par le projet : composants de page du DS, barre, états vides et d'erreur standard. -->

## Refaire un écran existant (`/redo_screen`)

### Contrat à préserver

- Le ViewModel, son `UiState` et ses événements (signatures inchangées)
- Chaque `testTag` de `XxxTestTags` : ni supprimé, ni déplacé, ni renommé
- Les clés `strings.xml`
- La route et ses arguments

### Détection des tests liés

`grep -rn 'XxxTestTags\|XxxScreen' --include=*.kt src/test src/androidTest` et les flows Maestro du module
(`maestro/*.yaml`, `id:`).

### Vérification

- `./gradlew :<module>:testDebugUnitTest` vert, sans test modifié
- Captures avant / après : `~/.claude/stacks/android/android_cli.sh preview <module> <dossier>` (rendu des
  `@Preview` sans appareil, avec l'arbre de composants), sinon Maestro sur l'émulateur ; Thibault valide le visuel
