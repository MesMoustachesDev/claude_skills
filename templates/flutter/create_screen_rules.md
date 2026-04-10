# Create Screen Rules — Flutter

Ce fichier définit les conventions et templates pour générer un écran Flutter depuis un input visuel (screenshot, code Figma) ou textuel.

## Contexte technique

- **Langage** : Dart
- **Framework** : Flutter
- **Widget style** : StatelessWidget par défaut, ConsumerWidget si Riverpod
- **Découpage** : petits widgets extraits dans des fichiers séparés

## Philosophie

> **Le code Figma est une référence visuelle, pas une base de code.**

- Ne jamais garder du code Figma tel quel. C'est du jetable : valeurs hardcodées, nesting absurde, zéro architecture.
- Chaque écran est composé de **petits widgets extraits** — pas un seul `build()` de 200 lignes.
- Un écran sans état Loading/Error/Empty n'est pas terminé.
- Les strings hardcodées n'existent pas. Jamais.
- **Règle d'or** : si un widget a plus de ~30 lignes de `build()`, il doit être extrait.

---

## Détection automatique dans le projet

Avant de poser des questions, scanne le projet :

### Design System

- Dossiers : `design_system/`, `theme/`, packages dédiés (`hades/`, `ui_kit/`, etc.)
- Fichiers : `*theme*.dart`, `*colors*.dart`, `*typography*.dart`, `*spacing*.dart`
- Usages : `Theme.of(context)`, extensions de `ThemeData`, tokens custom

### State Management

- `flutter_bloc` / `Bloc` / `Cubit` → BLoC
- `flutter_riverpod` / `ConsumerWidget` / `ref.watch` → Riverpod
- Les deux (BLoC pour state complexe, Riverpod pour DI) → hybride

### Localisation

- Dossier `l10n/`, fichiers `.arb`
- Usages : `context.l10n`, `AppLocalizations.of(context)`, `S.of(context)`
- Systèmes : gen-l10n, intl, easy_localization

### Navigation

- `GoRouter` / `go_router` → GoRouter
- `Navigator` / `MaterialPageRoute` → Navigation classique
- `auto_route` → AutoRoute

---

## Questions à poser

Présente d'abord ce qui a été détecté. Ne pose **que** les questions dont la réponse n'est pas déjà connue.

1. **Design System** (si non détecté) : Le projet a-t-il un design system / UI kit ?
   - Oui → demande le nom/chemin
   - Non → utiliser Material/ThemeData standard

2. **États de l'écran** : Quels états gérer ?
   - Tous (Loading + Error + Empty + Loaded) (Recommandé)
   - Loaded uniquement (écran statique)
   - Loaded + Error uniquement

3. **Nom de l'écran** (si pas clair depuis l'input) : snake_case, ex: `user_profile`, `report_detail`

---

## Traitement de l'input

### Si screenshot Figma

1. Lire l'image avec `Read`
2. Identifier :
   - Structure globale : AppBar, Bottom nav, FAB, Drawer, Tabs
   - Sections : header, body scrollable, footer fixe
   - Composants répétés → `ListView.builder` ou `GridView`
   - Interactions : boutons, inputs, toggles, swipe
   - Palette de couleurs et typographie (à mapper vers le DS)

### Si code Figma copié-collé

1. Extraire la hiérarchie, les valeurs visuelles, les textes, les assets
2. **Jeter le code**. Ne garder que la compréhension visuelle.
3. Reconstruire from scratch.

### Si description textuelle

1. Identifier les composants
2. Proposer un wireframe ASCII pour validation :

```
┌─────────────────────┐
│     AppBar          │
├─────────────────────┤
│  Filter chips       │
├─────────────────────┤
│  ┌───────────────┐  │
│  │ Card item     │  │
│  └───────────────┘  │
├─────────────────────┤
│   Bottom Nav        │
└─────────────────────┘
```

3. Demander validation avant de coder.

---

## Structure cible des fichiers

```
lib/src/presentation/ui/
├── {screen_name}_page.dart          # Page principale (scaffold + états)
├── {screen_name}_loaded_view.dart   # Vue état Loaded
└── widgets/
    ├── {screen_name}_header.dart    # Sections
    ├── {screen_name}_list_item.dart # Items répétés
    └── {screen_name}_filter.dart    # Composants
```

Chaque widget extrait = `StatelessWidget` (ou `ConsumerWidget` si Riverpod) dans son propre fichier.

---

## Conventions visuelles strictes

1. **Design system first** — Utiliser les tokens du DS détecté. Sinon `Theme.of(context).colorScheme`, `textTheme`.
2. **Jamais de valeurs magiques** :
   - ❌ `Color(0xFF2196F3)`, `FontSize: 14`, `EdgeInsets.all(8)`
   - ✅ `Theme.of(context).colorScheme.primary`, `theme.textTheme.bodyMedium`, spacing constants du DS
3. **Jamais de strings hardcodées** — Tout passe par l10n. Si l10n absent : `static const` + `// TODO: Move to l10n`.
4. **`const` partout où possible** — Constructeurs, widgets statiques, valeurs.
5. **Icônes** — Icon set du projet si détecté, sinon `Icons.*` Material.

---

## Templates de fichiers

### Page principale avec BLoC (`{screen_name}_page.dart`)

```dart
class {ScreenName}Page extends StatelessWidget {
  const {ScreenName}Page({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<{ScreenName}Bloc, {ScreenName}State>(
      builder: (context, state) {
        return Scaffold(
          // AppBar si applicable
          body: switch (state) {
            {ScreenName}Initial() => const _LoadingView(),
            {ScreenName}Loading() => const _LoadingView(),
            {ScreenName}Loaded(:final data) =>
              {ScreenName}LoadedView(data: data),
            {ScreenName}Error(:final message) =>
              _ErrorView(message: message),
            {ScreenName}Empty() => const _EmptyView(),
          },
        );
      },
    );
  }
}
```

### Page principale avec Riverpod (`{screen_name}_page.dart`)

```dart
class {ScreenName}Page extends ConsumerWidget {
  const {ScreenName}Page({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: ref.watch({screenName}Provider).when(
            data: (data) => {ScreenName}LoadedView(data: data),
            loading: () => const _LoadingView(),
            error: (error, _) => _ErrorView(message: error.toString()),
          ),
    );
  }
}
```

### Loading view (privée dans le fichier page)

```dart
class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator.adaptive(),
    );
  }
}
```

### Error view avec retry (privée)

```dart
class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            child: Text(context.l10n.retry),
          ),
        ],
      ),
    );
  }
}
```

### Empty view (privée)

```dart
class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        context.l10n.noDataAvailable,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}
```

### Widget extrait (dans son propre fichier)

```dart
import 'package:flutter/material.dart';

class {WidgetName} extends StatelessWidget {
  const {WidgetName}({
    super.key,
    // TODO: required fields
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return /* TODO */;
  }
}
```

---

## Localisation

Si le projet a de la l10n :

1. Identifier toutes les strings visibles dans l'écran
2. Générer les clés au format du projet (camelCase pour gen-l10n)
3. Utiliser `context.l10n.keyName` (ou équivalent détecté)
4. Lister les clés à ajouter aux fichiers ARB/traductions dans le résumé final

Si pas de l10n → `static const` regroupées en haut du fichier + `// TODO: Move to l10n`.

---

## Résumé final

1. **Arborescence** des fichiers créés
2. **Wireframe ASCII** du résultat
3. **Clés l10n** à ajouter
4. **TODO restants** : navigation wiring, data binding, logique métier
5. **Widgets extraits** : liste de chaque widget avec sa responsabilité (1 ligne chacun)
