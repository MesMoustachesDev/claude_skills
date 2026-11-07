---
paths:
  - "**/*.dart"
  - "**/pubspec.yaml"
  - "**/*.arb"
---
# Flutter / Dart — conventions de test

Ce que `~/.claude/commands/create_test.md` (la philosophie, sans langage) et les agents de test veulent dire
en Flutter. Vocabulaire et architecture : `flutter.md`, chargée en même temps.

## Stack de test

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
```

Pour les BLoCs, utiliser directement `stream` + `emitsInOrder` (pas de `bloc_test` sauf si le projet l'utilise
déjà). Lancer les tests avec l'outil MCP `run_tests` quand il est là, sinon `flutter test <fichier>`.

## Structure du fichier test

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// Mocks — privés, préfixés _
class _MockDependency extends Mock implements Dependency {}

void main() {
  // Déclarations late
  late ClassUnderTest sut; // "system under test"
  late _MockDependency mockDependency;

  setUp(() {
    mockDependency = _MockDependency();
    sut = ClassUnderTest(dependency: mockDependency);
  });

  // Si BLoC
  tearDown(() {
    sut.close(); // uniquement pour les BLoCs
  });

  // Enregistrement des fallback values si nécessaire
  setUpAll(() {
    registerFallbackValue(SomeType());
  });

  group('methodName', () {
    group('happy path', () {
      test('description comportementale', () async {
        // Arrange
        when(() => mockDependency.method(any()))
            .thenAnswer((_) async => expectedResult);

        // Act
        final result = await sut.method(input);

        // Assert
        expect(result, equals(expectedValue));
      });
    });

    group('edge cases', () {
      test('returns empty list when no data exists', () async {
        when(() => mockDependency.method(any()))
            .thenAnswer((_) async => []);

        final result = await sut.method(input);

        expect(result, isEmpty);
      });
    });

    group('error handling', () {
      test('propagates exception when dependency fails', () async {
        when(() => mockDependency.method(any()))
            .thenThrow(Exception('Network error'));

        expect(
          () => sut.method(input),
          throwsA(isA<Exception>()),
        );
      });
    });
  });
}
```

Checklist Flutter, en plus de celle de `create_test.md` : mocks privés `_MockXxx` ; `setUp` initialise le SUT
et les mocks ; `tearDown` ferme les BLoCs ; `having()` pour les propriétés des states complexes ; pas de
`verify()` sauf pour les side-effects critiques.

## Pour les BLoCs

```dart
group('{FeatureName}Bloc', () {
  test('initial state is {FeatureName}Initial', () {
    expect(sut.state, isA<{FeatureName}Initial>());
  });

  test('emits [Loading, Loaded] when data loads successfully', () {
    when(() => mockUseCase(any()))
        .thenAnswer((_) => Stream.value(data));

    sut.add(const LoadEvent());

    expectLater(
      sut.stream,
      emitsInOrder([
        isA<{FeatureName}Loading>(),
        isA<{FeatureName}Loaded>()
            .having((s) => s.items, 'items', hasLength(3)),
      ]),
    );
  });

  test('emits [Loading, Error] when use case throws', () {
    when(() => mockUseCase(any()))
        .thenAnswer((_) => Stream.error(Exception('fail')));

    sut.add(const LoadEvent());

    expectLater(
      sut.stream,
      emitsInOrder([
        isA<{FeatureName}Loading>(),
        isA<{FeatureName}Error>(),
      ]),
    );
  });
});
```

## Pour les Use Cases

```dart
group('Get{FeatureName}UseCase', () {
  test('delegates to repository and returns result', () async {
    final expected = {FeatureName}Entity(/* ... */);
    when(() => mockRepo.get{FeatureName}(any()))
        .thenAnswer((_) async => expected);

    final result = await sut(params);

    expect(result, equals(expected));
  });

  // EDGE CASES — c'est ici que les vrais bugs se cachent
  test('handles empty result from repository', () async {
    when(() => mockRepo.get{FeatureName}(any()))
        .thenAnswer((_) async => null);

    final result = await sut(params);

    expect(result, isNull);
  });
});
```

## Pour les Mappers

Les mappers méritent des tests exhaustifs car ils convertissent des données :

```dart
group('{FeatureName}Mapper', () {
  test('maps all fields correctly from DAO to entity', () {
    final dao = SomeDao(field1: 'a', field2: 42);

    final entity = dao.toEntity();

    expect(entity.field1, equals('a'));
    expect(entity.field2, equals(42));
  });

  test('handles null optional fields gracefully', () {
    final dao = SomeDao(field1: 'a', field2: null);

    final entity = dao.toEntity();

    expect(entity.field2, isNull);
  });

  // Test des valeurs limites spécifiques au domaine
  test('maps empty string as empty, not null', () {
    final dao = SomeDao(field1: '', field2: 0);

    final entity = dao.toEntity();

    expect(entity.field1, isEmpty);
    expect(entity.field1, isNotNull);
  });
});
```

## Pour les widgets alimentés par un stream

Après avoir émis sur un `StreamController` (ou fait échouer le flux), utiliser
`await tester.pump(Duration.zero)`, jamais un `pump()` nu. Quand aucun frame n'est planifié, un
`pump()` nu traite l'événement **après** le frame : le `setState` du builder n'apparaît qu'au pump
suivant, et le test échoue contre une implémentation correcte. Mettre ce pump dans les helpers
d'émission (`emit`, `fail`) plutôt que dans chaque test.

```dart
Future<void> emit(WidgetTester tester, List<Item> items) async {
  controller.add(items);
  await tester.pump(Duration.zero);
}
```

## Pièges d'égalité et d'asynchrone (Théo)

- Assertions sur le contenu : `expect(x, isNotNull)` seul est un déchet.
- Jamais de Map, List ou Set dans un record comparé (`expect`, `equals`, `verify`, `when`). Le `==` d'un record
  compare chaque champ avec `==`, et celui d'une collection compare l'identité : le test rougit contre un code
  juste. Sors ce champ dans un `expect(résultat.champ, {…})` à part, qui compare le contenu. Le gate le refuse
  (`test_hygiene`).
- Pas de `verify()` sauf side-effect critique listé dans la spec.
- Logique qui peut échouer en partie (boucle, import, synchro) : teste le réessai après l'échec partiel, et vérifie qu'au second passage rien n'est perdu ni doublé. (learn 2026-11-07, retry-path, 2 runs)
- Widget alimenté par un stream : `await tester.pump(Duration.zero)` après chaque émission ou erreur (section
  ci-dessus), dans les helpers d'émission.

## Attendre un état, pas une durée

`Completer`, `pumpUntil`, `pumpAndSettle`, `expectLater` sur le stream ; jamais `Future.delayed`,
`pump(Duration(seconds: …))` ni N `pump` de durée fixe, même recopiés d'un test voisin.

## Égalité

Un champ ajouté aux `props` d'une entité, d'un event ou d'un état Equatable a son test d'égalité (principe 10
de `create_test.md`).

## Emplacement des fichiers

Miroir de `lib/src/` dans `test/src/` :

| Source | Test |
|--------|------|
| `lib/src/domain/usecase/get_foo_use_case.dart` | `test/src/domain/usecase/get_foo_use_case_test.dart` |
| `lib/src/data/repository/foo_repository_impl.dart` | `test/src/data/repository/foo_repository_impl_test.dart` |
| `lib/src/data/mapper/foo_mapper.dart` | `test/src/data/mapper/foo_mapper_test.dart` |
| `lib/src/presentation/bloc/foo_bloc.dart` | `test/src/presentation/bloc/foo_bloc_test.dart` |

Tests de mutation (Hugo) : nouveaux fichiers à côté du test existant, suffixés `_mutation_test.dart`
(`test/src/domain/usecase/fetch_x_usecase_mutation_test.dart`).
Sondes de `/reviewPR` (Maëlle) : `<dossier de la revue>/probes/<nn>_<slug>_test.dart`, un widget test le plus
souvent, jamais dans le repo.

## Ce que lit l'auteur des tests (Théo)

Contrats : `lib/src/domain/**` (entities, interfaces, signatures des use cases, `ErrorEntity`),
`lib/src/presentation/keys.dart`, les `*_event.dart` / `*_state.dart` des BLoCs, `lib/src/data/model/*.dart`
(modèles de données). Jamais `lib/src/data/**/*_impl.dart`, `lib/src/presentation/**/view/**`, `*_bloc.dart`.
Un package encore vide : lis d'abord un fichier `.dart` existant de la feature de référence.

## Acceptation (Gherkin → `bdd_widget_test`)

- Ajoute `bdd_widget_test` aux `dev_dependencies` si absent, écris `test/<feature>.feature` (§4 recopié tel
  quel), lance `dart run build_runner build --delete-conflicting-outputs`, puis complète les step definitions
  générées dans `test/step/` ; un helper partagé vit dans un fichier de `test/**/step/`.
- Sélection par `find.byKey(ValueKey(<Name>Keys.x))`, jamais `find.text`.
- Une action de l'utilisateur : `tester.tap`, `enterText`, `drag`… Une réponse d'un système extérieur : le
  use case mocké, `when(() => getX(...)).thenAnswer((_) async => Right(…))`, `Left(<ErrorEntity de §7>)` pour
  une erreur, un `StreamController` pour un use case `watch`. Un résultat visible : un `expect`.
- Le rapport du point d'étape lit le `testWidgets` généré par `bdd_widget_test` et le corps de chaque step.
- L'acceptation tourne sur le **vrai BLoC**, branché sur des use cases mockés. Un test de widget d'un état
  isolé peut piloter un BLoC mocké avec `whenListen` ; un test d'acceptation, jamais.
- Deux moitiés en parallèle : **seule la moitié présentation lance `build_runner`** (codegen de
  `bdd_widget_test`), et seulement quand son `.feature` change ; deux `build_runner` sur le même package se
  marchent dessus. Un `*.g.dart` qui manque à la moitié data est un oubli d'Arthur : elle le rapporte.
- Zones : moitié data `test/src/{data,domain,injection}/**` ; moitié présentation `test/src/presentation/**`
  (BLoC, widgets), `test/<feature>.feature`, `test/step/**`, les tests générés, et `bdd_widget_test` dans le
  `pubspec.yaml`.
