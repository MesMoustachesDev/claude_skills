# Create Feature

Tu es un expert Flutter/Clean Architecture. Ton objectif est de générer un nouveau feature package complet dans un projet Flutter modulaire.

## Étape 1 — Collecter les informations

Pose les questions suivantes à l'utilisateur via `AskUserQuestion` (en un seul appel multi-questions) :

### Questions obligatoires :

1. **Nom de la feature** : Demande le nom en snake_case (ex: `user_profile`, `device_sync`). Si `$ARGUMENTS` est fourni et non vide, utilise-le comme nom sans demander.

2. **Data sources** : Quels types de sources de données ?
   - Remote uniquement (API)
   - Local uniquement (base de données locale)
   - Les deux (remote + local)
   - Aucune (feature légère, pas de data layer)

3. **BLoC** : La feature a-t-elle besoin d'un BLoC pour gérer un état complexe côté présentation ?
   - Oui
   - Non (Riverpod providers suffisent)

4. **Lecture des données** : Comment les données sont-elles consommées ?
   - Stream (données réactives, mises à jour en temps réel — typique pour le local/watch)
   - Future (one-shot, requête → réponse — typique pour le remote)
   - Les deux (Stream pour la lecture locale, Future pour les appels API)

5. **Couche présentation** : La feature expose-t-elle de l'UI ?
   - Oui (pages + widgets)
   - Non (domain/data seulement, consommée par d'autres features)

## Étape 2 — Déterminer le chemin cible

Cherche le dossier `features/` le plus proche dans l'arborescence du projet courant. Si tu ne le trouves pas, demande à l'utilisateur le chemin racine du projet.

Le package sera créé dans `features/{feature_name}/`.

## Étape 3 — Générer la structure

En fonction des réponses, génère **tous** les fichiers ci-dessous. Respecte **exactement** les conventions décrites.

### Conventions strictes :

- **Nommage des fichiers** : snake_case partout
- **Nommage des classes** : PascalCase dérivé du nom de la feature
- **Imports core** : Toujours importer depuis `package:core/...` (pas de dépendances tierces directes)
- **Barrel file** : N'exporte que les APIs publiques (DI, interfaces domain, use cases, UI)
- **Providers Riverpod** :
  - Data sources et repositories : providers privés (préfixés `_`)
  - Use cases, BLoCs, mappers : providers publics
  - Utiliser `AutoDisposeProvider` par défaut
  - `ref.watch()` pour les dépendances réactives
- **Sealed classes** pour les events et states des BLoCs
- **Equatable** pour entities, events, states
- **`resolution: workspace`** dans le pubspec.yaml
- **Error handling avec `Either`** :
  - Utiliser `Either<ErrorEntity, T>` (package `dartz` via `package:core/rx.dart`) pour **toute opération qui peut échouer** : appels API, lectures DB, opérations I/O
  - `Left` = erreur (`ErrorEntity`), `Right` = succès
  - Les **data sources** retournent `Either<ErrorEntity, T>` — c'est ici que les erreurs sont catchées et wrappées
  - Les **repositories** propagent les `Either` reçus des data sources (pas de try/catch dans le repo, le data source a déjà géré)
  - Les **use cases** propagent les `Either` et peuvent les combiner via `flatMap` / `flatMapAsync` (extensions dans `package:core/either_extensions.dart`)
  - Pour les appels API, utiliser le `DataLoader` de core (`ref.watch(dataLoaderProvider)`) qui wrappe Dio et retourne `Either<ErrorEntity, T>` automatiquement
  - Dans la **couche présentation** (BLoC), `fold()` le `Either` pour émettre le bon state : `result.fold((error) => ErrorState(error), (data) => LoadedState(data))`

---

### 3.1 — pubspec.yaml

```yaml
name: '{feature_name}'
description: '{Feature Name} feature module'

environment:
  sdk: ^3.7.1

dependencies:
  flutter:
    sdk: flutter
  core:
    path: ../core
  # Ajouter d'autres features si nécessaire

resolution: workspace
```

Si **local data source** → ajouter la dépendance `database: path: ../database` seulement si le projet utilise Isar/database package.

---

### 3.2 — Barrel file (`lib/{feature_name}.dart`)

```dart
library;

export 'src/injection/{feature_name}_di.dart';
// Exporter domain entities, use cases, et UI si applicable
```

N'exporte **jamais** les implémentations data layer.

---

### 3.3 — Domain Layer (`lib/src/domain/`)

#### Entity (`lib/src/domain/model/{feature_name}_entity.dart`)

```dart
import 'package:core/equatable.dart';

class {FeatureName}Entity extends Equatable {
  const {FeatureName}Entity({
    // TODO: Add fields
  });

  @override
  List<Object?> get props => [/* TODO */];
}
```

#### Repository interface (`lib/src/domain/repository/{feature_name}_repository.dart`)

```dart
import 'package:core/rx.dart';
import 'package:core/error/domain/model/error.dart';

abstract class {FeatureName}Repository {
  // TODO: Define repository contract
  //
  // Opérations remote (faillibles) → Either :
  // Future<Either<ErrorEntity, {FeatureName}Entity>> fetch{FeatureName}(int id);
  //
  // Lectures locales réactives → Stream (pas de Either, la lecture locale ne fail pas) :
  // Stream<List<{FeatureName}Entity>> watch{FeatureName}s();
  // Stream<{FeatureName}Entity?> watch{FeatureName}ById(int id);
  //
  // Écritures locales → Future<void> :
  // Future<void> save{FeatureName}({FeatureName}Entity entity);
}
```

#### Data source interfaces (si applicable)

**Remote** (`lib/src/domain/repository/{feature_name}_remote_data_source.dart`) :
```dart
import 'package:core/rx.dart';
import 'package:core/error/domain/model/error.dart';

abstract class {FeatureName}RemoteDataSource {
  // TODO: Define remote data source contract
  // Les appels réseau retournent toujours Either<ErrorEntity, T>.
  // Exemple :
  // Future<Either<ErrorEntity, {FeatureName}DataModel>> fetch{FeatureName}(int id);
}
```

**Local** (`lib/src/domain/repository/{feature_name}_local_data_source.dart`) :
```dart
abstract class {FeatureName}LocalDataSource {
  // TODO: Define local data source contract
  //
  // Lectures réactives (watch) → Stream<T> :
  // Stream<List<{FeatureName}Entity>> watch{FeatureName}s();
  // Stream<{FeatureName}Entity?> watch{FeatureName}ById(int id);
  //
  // Écritures → Future<void> :
  // Future<void> save{FeatureName}({FeatureName}Entity entity);
  // Future<void> delete{FeatureName}(int id);
  //
  // Les lectures locales (Isar, SQLite) ne retournent PAS Either —
  // elles ne peuvent pas échouer de façon récupérable.
}
```

#### Use case (`lib/src/domain/usecase/get_{feature_name}_use_case.dart`)

Adapte le type de retour selon le choix Future/Stream :

**Si Future (remote)** :
```dart
import 'package:core/rx.dart';
import 'package:core/error/domain/model/error.dart';

class Get{FeatureName}UseCase {
  const Get{FeatureName}UseCase({
    required this.{featureName}Repository,
  });

  final {FeatureName}Repository {featureName}Repository;

  // TODO: Define call method
  // Future<Either<ErrorEntity, {FeatureName}Entity>> call(int id) async {
  //   return {featureName}Repository.get{FeatureName}(id);
  // }
}
```

**Si Stream (local/watch)** :
```dart
class Watch{FeatureName}UseCase {
  const Watch{FeatureName}UseCase({
    required this.{featureName}Repository,
  });

  final {FeatureName}Repository {featureName}Repository;

  // TODO: Define call method
  // Stream<List<{FeatureName}Entity>> call() {
  //   return {featureName}Repository.watch{FeatureName}s();
  // }
}
```

**Si les deux** → génère un use case par type d'opération (ex: `Watch{FeatureName}UseCase` + `Fetch{FeatureName}UseCase`).

---

### 3.4 — Data Layer (`lib/src/data/`) — uniquement si data sources sélectionnées

#### Repository implementation (`lib/src/data/repository/{feature_name}_repository_impl.dart`)

```dart
class {FeatureName}RepositoryImpl implements {FeatureName}Repository {
  const {FeatureName}RepositoryImpl({
    // Injecter les data sources nécessaires
  });

  // TODO: Implement repository methods
}
```

Injecte `{FeatureName}RemoteDataSource` et/ou `{FeatureName}LocalDataSource` selon les choix.

#### Remote data source impl (si remote) (`lib/src/data/datasource/{feature_name}_remote_data_source_impl.dart`)

```dart
import 'package:core/rx.dart';
import 'package:core/error/domain/model/error.dart';
import 'package:core/load_from_remote.dart';

class {FeatureName}RemoteDataSourceImpl implements {FeatureName}RemoteDataSource {
  const {FeatureName}RemoteDataSourceImpl({
    required this.dataLoader,
    required this.client, // Dio client authentifié
  });

  final DataLoader dataLoader;
  final Dio client;

  // TODO: Implement remote calls
  // Utilise dataLoader.invoke() qui retourne Either<ErrorEntity, T> :
  //
  // @override
  // Future<Either<ErrorEntity, {FeatureName}DataModel>> fetch{FeatureName}(int id) {
  //   return dataLoader.invoke(
  //     defaultErrorMessage: 'Failed to fetch {feature_name}',
  //     request: () => client.get('/v1/endpoint/$id'),
  //     fromJson: {FeatureName}DataModel.fromJson,
  //     requestKey: 'fetch_{feature_name}_$id',
  //   );
  // }
}
```

#### Local data source impl (si local) (`lib/src/data/datasource/{feature_name}_local_data_source_impl.dart`)

```dart
class {FeatureName}LocalDataSourceImpl implements {FeatureName}LocalDataSource {
  const {FeatureName}LocalDataSourceImpl();

  // TODO: Implement local storage operations
}
```

#### Mapper (si data sources) (`lib/src/data/mapper/{feature_name}_mapper.dart`)

```dart
// Extensions pour convertir entre data models et domain entities
// TODO: Add mapper extensions
```

---

### 3.5 — Injection (`lib/src/injection/{feature_name}_di.dart`)

Génère les providers Riverpod dans l'ordre : data sources → repository → use cases → BLoC (si applicable).

```dart
import 'package:core/flutter_riverpod.dart';
```

- Data sources et repository : `final _dataSourceProvider = ...` (privés)
- Use cases : `final get{FeatureName}UseCaseProvider = ...` (publics)
- BLoC : `final {featureName}BlocProvider = ...` (public, avec `.family` si paramétré)

---

### 3.6 — Presentation Layer (si UI sélectionné)

#### BLoC (si sélectionné)

**Event** (`lib/src/presentation/bloc/{feature_name}_event.dart`) :
```dart
import 'package:core/equatable.dart';

sealed class {FeatureName}Event extends Equatable {
  const {FeatureName}Event();

  @override
  List<Object?> get props => [];
}
```

**State** (`lib/src/presentation/bloc/{feature_name}_state.dart`) :
```dart
import 'package:core/equatable.dart';

sealed class {FeatureName}State extends Equatable {
  const {FeatureName}State();
}

final class {FeatureName}Initial extends {FeatureName}State {
  const {FeatureName}Initial();

  @override
  List<Object?> get props => [];
}
```

**BLoC** (`lib/src/presentation/bloc/{feature_name}_bloc.dart`) :
```dart
import 'package:core/flutter_bloc.dart';

class {FeatureName}Bloc extends Bloc<{FeatureName}Event, {FeatureName}State> {
  {FeatureName}Bloc() : super(const {FeatureName}Initial()) {
    on<{FeatureName}Event>((event, emit) async {
      // TODO: Handle events with switch expression
    });
  }
}
```

#### Page (`lib/src/presentation/ui/{feature_name}_page.dart`) :
```dart
import 'package:flutter/material.dart';

class {FeatureName}Page extends StatelessWidget {
  const {FeatureName}Page({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO: Implement page
    return const Placeholder();
  }
}
```

Si BLoC → la page utilise `BlocProvider` et `BlocBuilder`.
Si pas de BLoC → la page utilise `ConsumerWidget` avec Riverpod.

---

### 3.7 — Infrastructure de test (`test/`)

Génère un fichier de test de base qui prépare le terrain pour quand le dev implémentera la logique. Ce fichier contient les mocks, le `setUp`, et un test squelette — mais **aucun test fonctionnel** (il n'y a pas encore de logique à tester).

#### Test du use case (`test/src/domain/usecase/get_{feature_name}_use_case_test.dart`)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:{feature_name}/src/domain/repository/{feature_name}_repository.dart';
import 'package:{feature_name}/src/domain/usecase/get_{feature_name}_use_case.dart';

class _Mock{FeatureName}Repository extends Mock
    implements {FeatureName}Repository {}

void main() {
  late Get{FeatureName}UseCase sut;
  late _Mock{FeatureName}Repository mockRepository;

  setUp(() {
    mockRepository = _Mock{FeatureName}Repository();
    sut = Get{FeatureName}UseCase(
      {featureName}Repository: mockRepository,
    );
  });

  // TODO: Implement tests when use case logic is written.
  // Use /create_test to generate intent-driven tests.
}
```

#### Test du BLoC (si BLoC sélectionné) (`test/src/presentation/bloc/{feature_name}_bloc_test.dart`)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:{feature_name}/src/presentation/bloc/{feature_name}_bloc.dart';
import 'package:{feature_name}/src/presentation/bloc/{feature_name}_event.dart';
import 'package:{feature_name}/src/presentation/bloc/{feature_name}_state.dart';

// TODO: Add mock classes for BLoC dependencies

void main() {
  late {FeatureName}Bloc sut;

  setUp(() {
    sut = {FeatureName}Bloc();
  });

  tearDown(() {
    sut.close();
  });

  test('initial state is {FeatureName}Initial', () {
    expect(sut.state, isA<{FeatureName}Initial>());
  });

  // TODO: Implement tests when BLoC logic is written.
  // Use /create_test to generate intent-driven tests.
}
```

#### Test du repository impl (si data sources) (`test/src/data/repository/{feature_name}_repository_impl_test.dart`)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:{feature_name}/src/data/repository/{feature_name}_repository_impl.dart';
// TODO: Import data source interfaces

// TODO: Add mock classes for data sources

void main() {
  late {FeatureName}RepositoryImpl sut;

  setUp(() {
    // TODO: Initialize mocks and SUT
  });

  // TODO: Implement tests when repository logic is written.
  // Use /create_test to generate intent-driven tests.
}
```

---

## Étape 4 — Créer les fichiers

Utilise l'outil `Write` pour créer chaque fichier. Ne crée **aucun** fichier superflu.

## Étape 5 — Mettre à jour le workspace

Avertis l'utilisateur qu'il doit ajouter la feature au `pubspec.yaml` racine dans la section `workspace:` :

```yaml
workspace:
  - features/{feature_name}
```

Et s'il veut l'importer depuis l'app principale, ajouter aussi dans `dependencies:` :

```yaml
dependencies:
  {feature_name}:
    path: features/{feature_name}
```

## Étape 6 — Résumé

Affiche un récapitulatif de tout ce qui a été créé, sous forme d'arborescence. Indique les `// TODO` à compléter.
