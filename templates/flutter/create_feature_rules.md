# Create Feature Rules — Flutter / Clean Architecture

Ce fichier définit les conventions et templates pour générer une feature Flutter selon une architecture modulaire en packages workspace, clean architecture, Riverpod + BLoC, et error handling avec `Either`.

## Contexte technique

- **Langage** : Dart
- **Framework** : Flutter
- **Architecture** : Clean Architecture (domain / data / presentation) en packages modulaires
- **DI** : Riverpod
- **State management** : BLoC (pour l'état complexe) + Riverpod (pour la DI et l'état simple)
- **Error handling** : `Either<ErrorEntity, T>` via `dartz` (importé depuis `package:core/rx.dart`)
- **Database locale** : Isar (si applicable)
- **HTTP** : Dio wrappé dans un `DataLoader` (disponible dans `package:core/load_from_remote.dart`)

## Structure d'un feature package

```
features/{feature_name}/
├── lib/
│   ├── {feature_name}.dart           # Barrel file
│   └── src/
│       ├── domain/
│       │   ├── model/
│       │   │   └── {feature_name}_entity.dart
│       │   ├── repository/
│       │   │   ├── {feature_name}_repository.dart
│       │   │   ├── {feature_name}_remote_data_source.dart
│       │   │   └── {feature_name}_local_data_source.dart
│       │   └── usecase/
│       │       └── get_{feature_name}_use_case.dart
│       ├── data/
│       │   ├── repository/
│       │   │   └── {feature_name}_repository_impl.dart
│       │   ├── datasource/
│       │   │   ├── {feature_name}_remote_data_source_impl.dart
│       │   │   └── {feature_name}_local_data_source_impl.dart
│       │   └── mapper/
│       │       └── {feature_name}_mapper.dart
│       ├── injection/
│       │   └── {feature_name}_di.dart
│       └── presentation/
│           ├── bloc/
│           │   ├── {feature_name}_bloc.dart
│           │   ├── {feature_name}_event.dart
│           │   └── {feature_name}_state.dart
│           └── ui/
│               └── {feature_name}_page.dart
├── test/
│   └── src/
│       ├── domain/usecase/
│       ├── data/repository/
│       └── presentation/bloc/
└── pubspec.yaml
```

## Questions à poser

1. **Data sources** : Remote / Local / Les deux / Aucune
2. **BLoC** : Oui / Non (Riverpod seul suffit)
3. **Lecture des données** : Stream / Future / Les deux
4. **Couche présentation** : Oui (UI) / Non (domain/data seulement)

## Conventions strictes

- **Nommage des fichiers** : snake_case
- **Nommage des classes** : PascalCase dérivé du nom de la feature
- **Imports core** : Toujours depuis `package:core/...` (pas de dépendances tierces directes)
- **Barrel file** : N'exporte que les APIs publiques (DI, interfaces domain, use cases, UI)
- **Providers Riverpod** :
  - Data sources et repositories : providers **privés** (préfixés `_`)
  - Use cases, BLoCs, mappers : providers **publics**
  - `AutoDisposeProvider` par défaut
  - `ref.watch()` pour les dépendances réactives
- **Sealed classes** pour events et states des BLoCs
- **Equatable** pour entities, events, states
- **`resolution: workspace`** dans le pubspec.yaml

## Error handling avec `Either`

- Utiliser `Either<ErrorEntity, T>` pour **toute opération qui peut échouer** : appels API, opérations I/O
- `Left` = erreur (`ErrorEntity`), `Right` = succès
- Les **data sources remote** retournent `Future<Either<ErrorEntity, T>>` — ils catchent et wrappent les erreurs
- Les **repositories** propagent les `Either` des data sources (pas de try/catch dans le repo)
- Les **use cases** propagent les `Either` et peuvent les combiner via `flatMap` / `flatMapAsync` (extensions dans `package:core/either_extensions.dart`)
- Pour les appels API, utiliser `DataLoader.invoke()` (`ref.watch(dataLoaderProvider)`) qui wrappe Dio et retourne `Either<ErrorEntity, T>` automatiquement
- Dans le **BLoC**, `fold()` le `Either` pour émettre le bon state : `result.fold((error) => ErrorState(error), (data) => LoadedState(data))`

## Patterns Stream vs Future

- **Remote data sources** → `Future<Either<ErrorEntity, T>>` pour les appels API, parfois `Stream<Either<...>>` pour les opérations longues (download/upload progress)
- **Local data sources** → `Stream<T>` pour les lectures réactives (watch), `Future<void>` pour les écritures — **pas de Either** (la lecture locale ne fail pas de façon récupérable)
- **Repositories** → propagent le type du data source sous-jacent

---

## Templates de fichiers

### pubspec.yaml

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

Si **local data source** → ajouter `database: path: ../database` si le projet utilise Isar.

### Barrel file (`lib/{feature_name}.dart`)

```dart
library;

export 'src/injection/{feature_name}_di.dart';
// Exporter domain entities, use cases, et UI si applicable
```

N'exporte **jamais** les implémentations data layer.

### Entity (`lib/src/domain/model/{feature_name}_entity.dart`)

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

### Repository interface (`lib/src/domain/repository/{feature_name}_repository.dart`)

```dart
import 'package:core/rx.dart';
import 'package:core/error/domain/model/error.dart';

abstract class {FeatureName}Repository {
  // TODO: Define repository contract
  //
  // Opérations remote (faillibles) → Either :
  // Future<Either<ErrorEntity, {FeatureName}Entity>> fetch{FeatureName}(int id);
  //
  // Lectures locales réactives → Stream (pas de Either) :
  // Stream<List<{FeatureName}Entity>> watch{FeatureName}s();
  // Stream<{FeatureName}Entity?> watch{FeatureName}ById(int id);
  //
  // Écritures locales → Future<void> :
  // Future<void> save{FeatureName}({FeatureName}Entity entity);
}
```

### Remote data source interface (`lib/src/domain/repository/{feature_name}_remote_data_source.dart`)

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

### Local data source interface (`lib/src/domain/repository/{feature_name}_local_data_source.dart`)

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

### Use case

**Si Future (remote)** (`lib/src/domain/usecase/get_{feature_name}_use_case.dart`) :
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

**Si Stream (local/watch)** (`lib/src/domain/usecase/watch_{feature_name}_use_case.dart`) :
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

**Si les deux** → générer un use case par type d'opération (ex: `Watch{FeatureName}UseCase` + `Fetch{FeatureName}UseCase`).

### Repository implementation (`lib/src/data/repository/{feature_name}_repository_impl.dart`)

```dart
class {FeatureName}RepositoryImpl implements {FeatureName}Repository {
  const {FeatureName}RepositoryImpl({
    // Injecter les data sources nécessaires
  });

  // TODO: Implement repository methods
}
```

Injecte `{FeatureName}RemoteDataSource` et/ou `{FeatureName}LocalDataSource` selon les choix.

### Remote data source impl (`lib/src/data/datasource/{feature_name}_remote_data_source_impl.dart`)

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

### Local data source impl (`lib/src/data/datasource/{feature_name}_local_data_source_impl.dart`)

```dart
class {FeatureName}LocalDataSourceImpl implements {FeatureName}LocalDataSource {
  const {FeatureName}LocalDataSourceImpl();

  // TODO: Implement local storage operations
}
```

### Mapper (`lib/src/data/mapper/{feature_name}_mapper.dart`)

```dart
// Extensions pour convertir entre data models et domain entities
// TODO: Add mapper extensions
```

### DI (`lib/src/injection/{feature_name}_di.dart`)

```dart
import 'package:core/flutter_riverpod.dart';
```

Ordre des providers : data sources → repository → use cases → BLoC.

- Data sources et repository : `final _dataSourceProvider = ...` (privés)
- Use cases : `final get{FeatureName}UseCaseProvider = ...` (publics)
- BLoC : `final {featureName}BlocProvider = ...` (public, avec `.family` si paramétré)

### BLoC Event (`lib/src/presentation/bloc/{feature_name}_event.dart`)

```dart
import 'package:core/equatable.dart';

sealed class {FeatureName}Event extends Equatable {
  const {FeatureName}Event();

  @override
  List<Object?> get props => [];
}
```

### BLoC State (`lib/src/presentation/bloc/{feature_name}_state.dart`)

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

### BLoC (`lib/src/presentation/bloc/{feature_name}_bloc.dart`)

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

### Page (`lib/src/presentation/ui/{feature_name}_page.dart`)

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

- Si BLoC → la page utilise `BlocProvider` et `BlocBuilder`
- Si pas de BLoC → la page utilise `ConsumerWidget` avec Riverpod

---

## Infrastructure de test

Générer un fichier de test de base avec les mocks et le `setUp`, **sans tests fonctionnels** (le dev utilisera `/create_test` une fois la logique implémentée).

### Test du use case (`test/src/domain/usecase/get_{feature_name}_use_case_test.dart`)

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

### Test du BLoC (`test/src/presentation/bloc/{feature_name}_bloc_test.dart`)

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

### Test du repository impl (`test/src/data/repository/{feature_name}_repository_impl_test.dart`)

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

## Emplacement cible

Le feature package est créé dans `features/{feature_name}/` (relatif à la racine du projet).

## Post-génération

Avertir l'utilisateur qu'il doit ajouter la feature au `pubspec.yaml` racine :

```yaml
workspace:
  - features/{feature_name}
```

Et si l'app principale doit l'importer :

```yaml
dependencies:
  {feature_name}:
    path: features/{feature_name}
```
