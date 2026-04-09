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

4. **Couche présentation** : La feature expose-t-elle de l'UI ?
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
abstract class {FeatureName}Repository {
  // TODO: Define repository contract
}
```

#### Data source interfaces (si applicable)

**Remote** (`lib/src/domain/repository/{feature_name}_remote_data_source.dart`) :
```dart
abstract class {FeatureName}RemoteDataSource {
  // TODO: Define remote data source contract
}
```

**Local** (`lib/src/domain/repository/{feature_name}_local_data_source.dart`) :
```dart
abstract class {FeatureName}LocalDataSource {
  // TODO: Define local data source contract
}
```

#### Use case (`lib/src/domain/usecase/get_{feature_name}_use_case.dart`)

```dart
class Get{FeatureName}UseCase {
  const Get{FeatureName}UseCase({
    required this.{featureName}Repository,
  });

  final {FeatureName}Repository {featureName}Repository;

  // TODO: Define call method
  // Future<{FeatureName}Entity> call() async {
  //   return {featureName}Repository.get{FeatureName}();
  // }
}
```

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
class {FeatureName}RemoteDataSourceImpl implements {FeatureName}RemoteDataSource {
  const {FeatureName}RemoteDataSourceImpl();

  // TODO: Implement remote calls
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
