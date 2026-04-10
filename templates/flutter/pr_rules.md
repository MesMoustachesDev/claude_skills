# Règles PR — Flutter / Clean Architecture

## Architecture & couches

- Les `Entity` sont de purs objets métier : pas d'import Flutter, pas de dépendance à un package externe, pas de logique de sérialisation
- Les `Model` (data layer) étendent ou mappent les `Entity` — jamais l'inverse
- Les `Repository` sont définis par une interface dans le domain layer ; l'implémentation vit dans le data layer
- Les `UseCase` contiennent **une seule responsabilité** : un UseCase = une action métier. Pas de UseCase fourre-tout
- Les `ViewModel` / `Cubit` / `Bloc` ne connaissent que les UseCase — zéro import de `datasource`, `repository impl`, ou package réseau
- Les widgets ne font pas de logique métier : pas d'appel direct à un repository, pas de transformation de données
- Les imports ne cassent pas la règle de dépendance : `presentation` → `domain` ← `data`. Jamais `domain` → `data` ou `domain` → `presentation`

## Injection de dépendances

- Toute dépendance est injectée via le constructeur — pas de singleton global accédé directement dans une classe métier
- Les instances sont enregistrées dans le DI container (get_it ou équivalent) ; pas de `MyRepo()` instancié à la main dans un widget ou un ViewModel
- Les UseCase et Repository sont enregistrés en `factory` sauf justification explicite (état partagé → `singleton` avec commentaire)

## State management

- Pas d'état mutable exposé directement (`var` public dans un Cubit/ViewModel accessible depuis l'UI)
- Les états sont immutables : utiliser `copyWith` ou des classes scellées (`sealed class` / `freezed`)
- Chaque écran gère les états : chargement, erreur, succès, vide — aucun de ces cas ne doit être ignoré dans le widget
- Pas de `BuildContext` passé à un ViewModel/Cubit/UseCase
- Les `StreamSubscription` sont annulés dans `close()` / `dispose()`

## Widgets & UI

- Pas de logique conditionnelle complexe inline dans le `build()` — extraire en méthode ou widget dédié si > 2 conditions imbriquées
- Les widgets réutilisables vont dans un dossier `shared/` ou `core/widgets/` — pas copié-collé entre features
- Pas de `MediaQuery`, `Theme` ou `Localizations` accédés en dehors de la couche presentation
- Les `const` constructeurs sont utilisés partout où c'est possible
- Pas de `setState` dans un `StatefulWidget` quand un state manager est déjà en place pour ce périmètre

## Gestion des erreurs

- Les erreurs métier sont typées : pas de `throw Exception("message string")` dans le domain ou le data layer — utiliser des classes d'erreur dédiées ou `Either<Failure, T>`
- Les `catch` génériques (`catch (e)`) sont interdits sans re-throw ou log explicite
- Les erreurs réseau / parsing sont catchées dans le datasource et transformées en `Failure` avant de remonter au domain
- L'UI affiche toujours un message d'erreur compréhensible — jamais un écran blanc ou une exception non gérée

## Async & performance

- Pas d'`await` dans une boucle (`for` / `forEach`) quand les appels sont indépendants — utiliser `Future.wait()`
- Les `FutureBuilder` et `StreamBuilder` sont évités au profit du state manager — sauf cas justifié (données one-shot sans état global)
- Les opérations lourdes (parsing JSON massif, traitement image) sont exécutées dans un `Isolate` ou via `compute()`
- Pas de rebuild intempestif : les `watch` / `select` sont scoped au minimum nécessaire

## Tests

- Tout nouveau UseCase a au moins un test unitaire couvrant le cas nominal et un cas d'erreur
- Les Repository impl sont testés avec un mock du datasource (mockito / mocktail)
- Les Cubit/Bloc sont testés avec `bloc_test`
- Pas de test qui appelle du vrai réseau ou une vraie base de données — tout est mocké
- Les golden tests sont mis à jour si un widget partagé est modifié

## Nommage & conventions

- Nommage cohérent par couche :
  - `UserEntity` → `UserModel` → `UserRepository` (interface) → `UserRepositoryImpl` → `GetUserUseCase` → `UserCubit` → `UserScreen`
- Les fichiers suivent le snake_case Dart : `get_user_use_case.dart`, pas `GetUserUseCase.dart`
- Les events Bloc sont des verbes à l'infinitif : `LoadUser`, `UpdateProfile` — pas `UserLoaded` (c'est un état)
- Les états sont des noms ou adjectifs : `UserLoaded`, `UserError`, `UserLoading`
- Pas d'abréviation cryptique : `usrSvc`, `repoImpl2`, `tmpData` — nommer ce que c'est vraiment

## Sécurité & données sensibles

- Zéro clé API, token, secret hardcodé dans le code source — utiliser `flutter_dotenv`, des variables d'environnement, ou un secret manager
- Les données sensibles (tokens, credentials) ne sont pas loggées, même en debug
- Les inputs utilisateur sont validés côté client **et** vérifiés côté serveur — jamais uniquement l'un des deux
- Pas de données personnelles stockées en clair dans les préférences locales sans chiffrement

## Divers

- Pas de `print()` en production — utiliser un logger configuré (`logger`, `talker`, etc.) avec niveau de log
- Les `TODO` et `FIXME` laissés dans le code sont accompagnés d'un ticket/issue référencé, pas juste un commentaire vague
- Les dépendances ajoutées dans `pubspec.yaml` sont justifiées : pas de package pour 3 lignes de code qu'on peut écrire soi-même
- Les breaking changes sur des interfaces partagées (Repository, UseCase) sont signalés explicitement dans la description de la PR
