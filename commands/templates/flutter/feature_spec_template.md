# Spec — {feature_name}

<!--
  Ce document est écrit par l'agent feature-specifier et validé par un humain.
  C'est le seul gate humain obligatoire du pipeline : tout ce qui suit (contrats,
  tests, implémentation, QA) en découle sans autre intervention.

  Règles d'écriture :
  - Les sections 4 à 8 sont CONSOMMÉES PAR DES AGENTS ET DES SCRIPTS. Elles doivent
    être précises, complètes et non ambiguës. Pas de "à définir", pas de "etc.".
  - Les blocs de code Dart sont des CONTRATS : signatures exactes, noms définitifs.
  - Les payloads sont des EXEMPLES RÉELS : valeurs plausibles, tous les champs, y compris
    les nullables et les cas limites.
  - La section 10 doit être VIDE à la validation. Une question ouverte = spec pas finie.
  - Supprimer les commentaires HTML une fois la section remplie.
-->

| | |
|---|---|
| **Feature** | `{feature_name}` |
| **Package** | `{package_path}` |
| **Branche** | `feature/{feature_name}` |
| **Base** | `{base_branch}` |
| **Statut** | brouillon → validée le {date} |

---

## 1. Contexte & objectif

<!-- Un paragraphe. Le problème utilisateur, pas la solution. Pourquoi maintenant. -->

## 2. Périmètre

### Inclus

<!-- Liste fermée de ce que la feature fait. Chaque item doit se retrouver dans au moins un scénario de la section 4. -->

- 

### Exclu (explicitement)

<!-- Ce qu'on pourrait croire inclus et qui ne l'est pas. Ce qui est reporté à une itération suivante. -->

- 

## 3. Parcours & états d'écran

<!--
  Un bloc par écran ou par dialogue. Pour chaque écran, les quatre états sont obligatoires
  (Loading / Error / Empty / Loaded) — "N/A" avec justification s'il n'y en a pas.
  Wireframe ASCII pour le Loaded. Navigation entrante et sortante.
-->

### Écran : {ScreenName}

- **Route** : `/{route}` — paramètres : 
- **Entrée depuis** : 
- **Sortie vers** : 

| État | Rendu | Actions disponibles |
|---|---|---|
| Loading | | |
| Error | | |
| Empty | | |
| Loaded | voir wireframe | |

```
┌────────────────────────────────┐
│                                │
│                                │
└────────────────────────────────┘
```

## 4. Scénarios d'acceptation (Gherkin)

<!--
  LA PARTIE DURABLE. Recopiés tels quels dans test/{feature_name}.feature et
  exécutés via bdd_widget_test, puis rejoués sur device via Maestro.

  - Un scénario = un comportement observable par l'utilisateur.
  - Couvrir chaque item de la section 2 "Inclus".
  - Couvrir chaque état de la section 3 (au moins un scénario Error, un Empty).
  - Les steps référencent les widgets par leur clé de la section 5 (keys.dart),
    jamais par leur texte affiché (localisé, donc instable).
  - Formulation en anglais (convention bdd_widget_test), phrases courtes.
-->

```gherkin
Feature: {Feature name}

  Background:
    Given the app is running

  Scenario: 
    Given 
    When 
    Then 

  Scenario: shows an error when 
    Given 
    When 
    Then 

  Scenario: shows an empty state when 
    Given 
    When 
    Then 
```

## 5. Contrats

<!--
  Signatures Dart EXACTES. L'architect les recopie, le test-writer teste contre elles,
  l'implementer les respecte. Un changement ici après validation = retour à la spec.

  Conventions : voir .claude/rules/create_feature_rules.md (nommage, imports package:core/...,
  Either<ErrorEntity, T> pour tout ce qui peut échouer, Stream pour les lectures locales).
-->

### Entities (`lib/src/domain/model/`)

```dart
class {Name}Entity extends Equatable {
  const {Name}Entity({required this.id});
  final String id;
  @override
  List<Object?> get props => [id];
}
```

### Repository (`lib/src/domain/repository/{feature_name}_repository.dart`)

```dart
abstract class {Name}Repository {
  Future<Either<ErrorEntity, {Name}Entity>> fetch(String id);
}
```

### Data sources (`lib/src/domain/repository/`)

<!-- Remote (Appwrite/HTTP) → Future<Either<...>>. Local (Isar) → Stream<T> / Future<void>. Supprimer ce qui n'existe pas. -->

```dart
abstract class {Name}RemoteDataSource {
}

abstract class {Name}LocalDataSource {
}
```

### Use cases (`lib/src/domain/usecase/`)

<!-- Un use case = une action métier. Signature du call() uniquement. -->

```dart
class Fetch{Name}UseCase {
  Future<Either<ErrorEntity, {Name}Entity>> call(String id);
}
```

### BLoC (`lib/src/presentation/{screen}/bloc/`)

<!-- Events = verbes à l'infinitif. States = noms/adjectifs. Sealed. Le test-writer teste emitsInOrder contre ces states. -->

```dart
sealed class {Name}Event extends Equatable {}
final class Load{Name} extends {Name}Event { const Load{Name}(this.id); final String id; }

sealed class {Name}State extends Equatable {}
final class {Name}Initial extends {Name}State {}
final class {Name}Loading extends {Name}State {}
final class {Name}Loaded extends {Name}State { const {Name}Loaded(this.entity); final {Name}Entity entity; }
final class {Name}Empty extends {Name}State {}
final class {Name}Error extends {Name}State { const {Name}Error(this.error); final ErrorEntity error; }
```

### Clés de widgets (`lib/src/presentation/keys.dart`)

<!--
  TOUTES les clés, sous forme de String. Trois consommateurs :
  - widget tests   : find.byKey(ValueKey({Name}Keys.errorRetry))
  - flows Maestro  : tapOn: { id: "{feature_name}_error_retry" }  (Semantics identifier)
  - implémentation : Semantics(identifier: {Name}Keys.errorRetry, child: X(key: ValueKey({Name}Keys.errorRetry)))
  Maestro ne voit PAS les Key Flutter, seulement les Semantics identifiers : l'implémentation pose les deux.
  Nommage : {feature}_{screen}_{element}.
-->

```dart
abstract final class {Name}Keys {
  static const String page = '{feature_name}_page';
  static const String loading = '{feature_name}_loading';
  static const String error = '{feature_name}_error';
  static const String errorRetry = '{feature_name}_error_retry';
  static const String empty = '{feature_name}_empty';
}
```

## 6. Données

<!--
  Sans cette section, le test-writer ne peut pas tester les mappers ni les data sources.
  Un exemple RÉEL par payload, avec tous les champs. Les cas limites en plus (champ null,
  liste vide, chaîne vide) s'ils existent.
-->

### Payloads remote

**`{Name}DataModel`** — réponse de `{endpoint ou collection Appwrite}` :

```json
{
  "$id": "abc123",
  "name": "Exemple",
  "createdAt": "2026-09-25T10:00:00.000Z",
  "optionalField": null
}
```

Cas limites :

```json
{ "$id": "abc124", "name": "", "createdAt": "2026-09-25T10:00:00.000Z", "optionalField": null }
```

### Schéma local (Isar)

<!-- Si data source locale. Sinon "N/A". Les DAOs vivent dans features/local_storage/ (cf. create_feature_rules.md). -->

N/A

### Mapping

| Source (`DataModel`) | Cible (`Entity`) | Règle |
|---|---|---|
| `$id` | `id` | direct |
| `name` | `name` | `trim()` ; vide → conservé vide, jamais null |
| `createdAt` | `createdAt` | ISO 8601 → `DateTime.parse`, UTC |

## 7. Erreurs

<!-- Chaque ErrorEntity possible, d'où elle vient, et ce que l'UI en fait. C'est la spec des scénarios Error. -->

| Erreur | Origine | Comportement UI | Retry possible |
|---|---|---|---|
| `NetworkError` | remote data source | `{Name}Error` + message générique + bouton retry | oui |
| `NotFoundError` | remote data source | `{Name}Empty` | non |
| `UnauthorizedError` | remote data source | redirection login (géré par `error` package) | non |

## 8. Architecture

<!-- Décisions structurelles. La map des dépendances est vérifiée par le gate `deps`. -->

- **Package** : nouveau `features/{feature_name}` / extension de `features/{existing}` — justification :
- **Dépendances du package** (pubspec) : `core`, 
- **Direction des couches** : `presentation → domain ← data`, `injection → *`. Aucune exception.
- **DI** (Riverpod, `lib/src/injection/{feature_name}_di.dart`) : providers privés pour data sources et repository, publics pour use cases et BLoC.
- **Routes** (`features/router`) : 
- **Clés l10n** (`features/l10n`, ARB) : 
- **Events analytics** (`package:core/analytics.dart`) : 
- **Services existants réutilisés** (ne pas réinventer) : 

## 9. Décisions & alternatives rejetées

<!-- Pour que le cleaner et l'implementer ne re-décident pas. Une ligne par décision : choix, alternative, raison. -->

| Décision | Alternative rejetée | Raison |
|---|---|---|
| | | |

## 10. Questions ouvertes

<!-- DOIT ÊTRE VIDE à la validation. Sinon, la spec n'est pas finie. -->

_Aucune._
