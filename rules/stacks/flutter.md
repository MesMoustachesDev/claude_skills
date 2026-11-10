---
paths:
  - "**/*.dart"
  - "**/pubspec.yaml"
  - "**/*.arb"
---
# Flutter / Dart — doctrine du pipeline

Chargée par Claude Code au premier fichier `.dart`, `pubspec.yaml` ou `.arb` lu (ADR 0011). Les agents,
commandes et `pipeline/*.md` parlent sans langage (« la commande de test du langage », « le state
holder », « le fichier de clés ») : cette règle dit ce que ces mots veulent dire en Flutter. Les règles du
projet (`.claude/rules/`) disent comment **ce** projet les applique et priment. Les conventions de test
sont dans `flutter-tests.md`, chargée en même temps.

## Vocabulaire du pipeline → Flutter

| Le pipeline dit | En Flutter |
|---|---|
| le code du package, `<src>/` | `lib/src/` : `data/`, `domain/`, `presentation/`, `injection/` ; le barrel `lib/<package>.dart` |
| les tests miroir, `<tests>/` | `test/src/` (miroir de `lib/src/`) ; l'acceptation dans `test/<feature>.feature`, ses steps dans `test/step/` |
| le state holder | le **BLoC** (`*_bloc.dart`), ses events (`*_event.dart`) et states (`*_state.dart`), sealed |
| la DI | Riverpod : providers privés pour data sources et repository, publics pour use cases et BLoC |
| le type résultat, l'erreur typée | `Either<ErrorEntity, T>` (dartz) : `Left(X)` pour l'erreur X, `Right(v)` pour un succès |
| le fichier de clés | `lib/src/presentation/keys.dart` (classe `<Name>Keys`) |
| le manifeste du package | `pubspec.yaml` (le `pubspec.yaml` racine porte le `workspace:`) ; la version résolue est dans `pubspec.lock` |
| la commande de test du langage | `flutter test <fichier>` (`fvm flutter` si le projet a un `.fvmrc`) ; `stack.sh get test_cmd` |
| l'analyse statique | `flutter analyze` ; le formatage `dart format` |
| l'installation des dépendances | `flutter pub get` (`fvm flutter pub get` avec `.fvmrc`), à la racine ; jamais `pub upgrade` |
| la génération de code | `dart run build_runner build --delete-conflicting-outputs` ; fichiers générés `*.g.dart`, `*.freezed.dart`, `*.mocks.dart` |
| la lib de mock | `mocktail` |
| l'outil Gherkin | `bdd_widget_test` (génère un `testWidgets` par scénario et les steps à compléter) |
| un test d'UI | un widget test (`testWidgets`, `WidgetTester`) |
| les textes de l'interface | l10n par fichiers ARB, `context.l10n.*` |
| un stub | `throw UnimplementedError()` |
| le brick global | `~/.claude/bricks/flutter_feature` (mason) |
| les gabarits du langage | `~/.claude/stacks/flutter/templates/` |

## Gestion d'erreur (règle de base, non négociable)

Un `try/catch` n'existe que dans `lib/src/data/`, autour de l'I/O (réseau, fichiers, stockage, galerie,
canal plateforme, plugin natif). La couche data le convertit en `Either<ErrorEntity, T>`. Domain (use
cases, entités, services de domaine), presentation et injection ne contiennent **aucun** `try/catch` : ils
composent des `Either` (`flatMap` / `flatMapAsync`) et seul le BLoC les déplie. Attraper `on Object` en data
quand un plugin lève une `Error` (ex. `CompressError`). Une méthode qui fait une I/O, directement ou via un
autre use case, rend `Either<ErrorEntity, T>` : un `Future<void>` sur une telle méthode est un **bloquant**
(critique de spec) et un **critique** (revue), comme un `try/catch` ajouté chez l'appelant pour compenser.

## Contrats (Arthur)

- Brouillon : entités, interfaces de repository et de data sources, signatures des use cases,
  events/states **sealed**, `lib/src/presentation/keys.dart` (une clé par élément que les séquences
  touchent ou vérifient). Fichiers de contrat lus par le gate : `*/domain/*`, `*/keys.dart`,
  `*_event.dart`, `*_state.dart`.
- Avant de poser le brouillon d'un package neuf, lis un fichier `.dart` de la feature de référence : c'est
  ce qui charge cette règle.
- Scaffold `create` : `mason make <brick> --name <feature> --riverpod3 <true si riverpod_major = 3 dans
  feature_pipeline.md> [options]` ; brick `project` → `./bricks/feature`, `global` →
  `~/.claude/bricks/flutter_feature`. Ajoute le package au `workspace:` du `pubspec.yaml` racine. Sans
  `mason` : `dart pub global activate mason_cli`, sinon la structure à la main selon `create_feature_rules.md`.
- Stub d'une méthode d'implémentation, exactement :
  ```dart
  @override
  Future<Either<ErrorEntity, X>> fetch(String id) => throw UnimplementedError();
  ```
  ou en bloc avec un seul `throw UnimplementedError();`. Dans un BLoC, les handlers sont des **méthodes**
  (`on<LoadX>(_onLoad)`), stubbées — pas de closure inline. La `build()` d'une page est un stub aussi.
- Complétion : les `DataModel` avec leurs annotations JSON (`json_serializable`) et le squelette des
  mappers (§6) ; DI Riverpod ; route ; clés l10n dans l'ARB. Fichiers de page : `<écran>_page.dart`,
  `<écran>_loaded_view.dart`.
- Dépendances du `pubspec.yaml` du package : `core` et ce que §8 liste, dont chaque lib tierce que le
  package importe lui-même (pas de ré-export via `core`) ; en `dev_dependencies` :
  `build_runner`, `mocktail`, `bdd_widget_test`, plus `json_serializable` si des modèles JSON existent.
- Appelants d'une signature changée : un seul `grep -rn '<nom>(' --include=*.dart` à la fin. Pas de boucles de
  `flutter analyze` sur les autres packages : le gate analyse le tien.

## Implémentation et vues (Ivan, Nina, Fanny, Pauline)

- Zones des deux moitiés d'Ivan : data/domain `lib/src/{data,domain,injection}/**` ; présentation
  `lib/src/presentation/**`, le reste de `lib/` et les clés ARB de ses vues.
- Ordre : mappers → data sources → repository → use cases → BLoC → vues. Le BLoC déplie les `Either` que
  rendent les use cases ; il n'appelle jamais un repository.
- Chaque clé de `keys.dart` est posée **deux fois** : `key: ValueKey(<Name>Keys.x)` sur le widget ET
  `Semantics(identifier: <Name>Keys.x, ...)` autour — la QA Maestro ne voit que les identifiers. Design
  system pour toute valeur visuelle, `context.l10n.*` pour tout texte.
- Refaire un écran : le contrat à préserver comprend le binding BLoC / Riverpod, les events, chaque
  `ValueKey` et `Semantics(identifier:)` de `keys.dart` (ni supprimé, ni déplacé, ni renommé), les clés
  l10n. Un golden ne se régénère pas sans validation visuelle de Thibault.
- Un fichier généré manquant ou périmé (`generated_fresh`) : `build_runner`, puis commit des fichiers générés.
- Dépendance inutilisée (`deps_unused`) : retire-la du `pubspec.yaml`.
- Traces de travail interdites à la livraison : `print(`, `debugPrint(`.
- Skills Dart / Flutter, à invoquer avec l'outil `Skill` avant d'écrire la couche concernée (ils ne sont plus
  préchargés par l'en-tête des agents, pour qu'un projet d'un autre langage ne les reçoive pas) :
  - `dart-flutter:dart-use-pattern-matching` pour le domain et le BLoC (sealed + `switch` exhaustif plutôt
    que des cascades de `if` et des flags) — implementers et Fanny ;
  - `dart-flutter:flutter-apply-architecture-best-practices` — implementers ;
  - pour les vues, `dart-flutter:flutter-build-responsive-layout`, et `dart-flutter:flutter-fix-layout-issues`
    au moindre débordement — implementers (moitié présentation) et Fanny (vue).
  Un skill qui contredit les règles du projet : le projet gagne.
- Fanny ne modifie aucun fichier hors `fix_plan.files` sans l'avoir signalé comme écart et obtenu l'accord, même pour supprimer du code devenu mort. (learn 2026-11-09, out-of-plan-file, 2 runs)
- Formate seulement les fichiers que tu as modifiés (`dart format <fichier>`), jamais un dossier entier (`dart format lib`). (learn 2026-11-10, agent_formats_whole_directory, 2 runs)

## Spec (Sophie, Camille)

- Ce qui existe déjà : `features/core/lib/*.dart` (Either, ErrorEntity, DataLoader, analytics, logger…).
- Le code source d'un paquet tiers se lit dans `~/.pub-cache/hosted/pub.dev/<paquet>-<version>/` (la version
  du `pubspec.lock`).
- Chaque clé de widget utilisée par §4 existe dans `keys.dart` ; §8 a une machine d'états Mermaid par BLoC,
  dont les events et states sont ceux des contrats ; aucune I/O faillible sans `Either`.
- Les scénarios de §4 s'écrivent en anglais, courts, compatibles `bdd_widget_test`.

## Revue (Romain, Victor, Alice, Corentin)

- Couches : `presentation → domain ← data` ; `Either` déplié dans le BLoC seulement, aucun `try/catch` hors
  `lib/src/data/` ; aucun `DataModel` ni repository en présentation (`ErrorRepository` compris : le BLoC
  appelle un use case, qui reporte l'erreur).
- Le package se lit de haut en bas : DI → use cases → BLoC → vue. La visite guidée suit vue → BLoC → use case
  → repository → data source (`layer` : `vue`, `bloc`, `usecase`, `repository`, `datasource`, `mapper`,
  `composant`).
- Items de la grille propres à Flutter : DS, l10n (ARB), barrel, BLoC. Rebuilds inutiles.
- Dépendance vieillissante (`pub_health`) : vérifie l'alternative sur pub.dev (date de release, score,
  `isDiscontinued`) et dis son coût (« `dartz` → `fpdart`, 41 fichiers, API proche, Option renommée »).
- Un catch qui laisse passer une `Error` levée par un plugin (`on Exception` face à `CompressError extends
  Error`) est un **critique**.

## Réponses de Thibault propres à Flutter

Celles de `pipeline/answers.md` valent en Flutter avec ces mots :
- Une écriture locale qui peut échouer (Isar, stockage, préférences, plugin) rend `Either<ErrorEntity, void>`
  depuis la data source ; pas de `Future<void>` qui lève. (2026-10-17, « Either »)
- Couches strictes : BLoC → use case → repository → data sources ; ne supprime jamais un use case appelé
  par un BLoC. (2026-10-17, « respecte mon archi »)
- Une transaction Isar faillible se rend en `Either` via `AtomicOperationHelper.executeAtomicallyOrLeft`
  (core), appelé dans la data source locale (ou le repository qui combine plusieurs data sources), jamais
  dans un use case ; pas de repository ou de data source neufs juste pour porter la transaction.
  (2026-10-30, « DÉCISION 1 » ; corrigée le 2026-11-10)
- Entité de domaine : classe `XxxEntity`, fichier `xxx_entity.dart`. (2026-10-29, « Contrats »)
- Clé de test manquante : Arthur l'ajoute à `keys.dart`, avec son `Semantics.identifier`. (2026-10-17, « Clés »)

## Outillage

- `/feature init` : commandes `fvm` ? (détecte `.fvmrc` ; alors `flutter = fvm flutter`, `dart = fvm dart`
  dans le bloc `ini`) ; sans `mason` : `dart pub global activate mason_cli` ; `riverpod_major` se lit dans `pubspec.lock`
  (`riverpod:` → `version:`), pas dans le pubspec — c'est la version résolue qui compte. Un projet en 2.x :
  dis-le : le global vise Riverpod 3, le brick génère la
  forme 2.x tant que le projet n'a pas migré, et `pub_health` le rappellera à chaque feature.
- Fichiers à copier dans un worktree neuf en plus des `.env*` : `.fvmrc`.
- Doctor : `fvm install …`, `dart pub global activate …` (installations locales).
- `/fix` : un reproducer qui branche un runner de test peut toucher `pubspec.yaml` ; un bug de rendu ou
  d'interaction se reproduit en widget test (`find.byKey`).
- Après les correctifs d'une MR : `flutter analyze` pour vérifier que ça compile.
