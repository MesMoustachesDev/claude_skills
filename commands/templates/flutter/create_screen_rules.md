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
- Anatomie : section **Anatomie du projet** du `create_screen_rules.md` du repo, sinon widgets de page / états déjà réutilisés par plusieurs écrans (`grep` des classes qui enveloppent `Scaffold`, des vues Loading / Error / Empty)

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

## Anatomie de page

> **Les tokens rendent un écran cohérent avec le DS. L'anatomie le rend cohérent avec les autres écrans.**

Toutes les pages de l'app partagent le même squelette. Un utilisateur qui passe d'un écran à l'autre ne doit voir changer que le contenu, jamais la charpente : même AppBar, mêmes marges, même rythme vertical, mêmes écrans d'état, même place pour l'action principale.

### Squelette commun

```
┌──────────────────────────────┐
│ AppBar (titre l10n, actions) │  ← toujours le même widget DS
├──────────────────────────────┤
│ Header de page (optionnel)   │  ← résumé, filtres, onglets
├──────────────────────────────┤
│ Body scrollable              │  ← padding horizontal = token page
│   Section                    │
│     SectionHeader            │  ← titre de section, widget DS
│     contenu                  │
│   ↕ gap section (token)      │
│   Section                    │
├──────────────────────────────┤
│ Footer CTA (optionnel)       │  ← action principale, fixe, SafeArea
└──────────────────────────────┘
```

### Règles

1. **Un seul scaffold de page.** Chaque page passe par le widget de page du DS (ex. `AppPageScaffold`), jamais par un `Scaffold` + `AppBar` assemblés à la main. S'il n'existe pas et que le projet a plus de deux pages, le proposer dans le DS avant de coder l'écran.
2. **Rythme vertical par tokens.** Trois niveaux seulement : marge de page, écart entre sections, écart entre éléments d'une section. Pas d'autre espacement inventé localement.
3. **Hiérarchie typographique fixe.** Titre de page dans l'AppBar, titres de section via le `SectionHeader` du DS, contenu en style corps. Un écran ne crée pas de nouveau niveau de titre.
4. **États partagés.** Loading, Error (avec retry) et Empty (icône, message, action optionnelle) sont des widgets du DS réutilisés par toutes les pages, jamais des classes privées recopiées par écran. S'ils n'existent pas, les créer une fois dans le DS.
5. **Une action principale par écran**, toujours au même endroit (footer CTA ou FAB, selon ce que fait le projet), jamais dans le body.
6. **Listes et cartes.** Les éléments répétés utilisent la carte / tuile du DS et le même séparateur que les autres listes de l'app.
7. **Grands écrans.** Le body est contraint à la largeur max du DS si le projet en définit une, pour que tablette et web gardent la même lecture.
8. **Pas de composant maison qui duplique le DS.** Si un écran a besoin d'un composant visuel qui servira ailleurs, il va dans le DS, pas dans `widgets/` de l'écran.

### Anatomie du projet

Les règles ci-dessus sont génériques. La version projet (noms réels des widgets et tokens) vit dans le `create_screen_rules.md` du repo, sous ce titre, et prime sur les exemples :

```markdown
### Anatomie du projet
- Scaffold de page : `<Widget>` (`<chemin>`)
- AppBar : `<Widget>`
- SectionHeader : `<Widget>`
- États : `<LoadingWidget>`, `<ErrorWidget>`, `<EmptyWidget>`
- Espacements : page `<token>`, section `<token>`, élément `<token>`
- Action principale : footer CTA `<Widget>` | FAB
- Largeur max : `<token>` | aucune
- Écrans de référence : `<page_a.dart>`, `<page_b.dart>`
```

Si cette section est absente ou incomplète, la déduire de 2 ou 3 écrans de référence validés par l'utilisateur, puis proposer de l'écrire dans le `create_screen_rules.md` du repo pour que les écrans suivants s'y alignent.

---

## Refaire un écran existant (`/redo_screen`)

### Contrat à préserver

Une refonte ne change que la présentation. Avant d'écrire, lister et garder intacts :

- L'API publique de la page : nom de classe, constructeur, paramètres, route GoRouter / AutoRoute
- Le binding au state management : `BlocBuilder` / `BlocListener` / `BlocSelector`, `ref.watch` / `ref.listen`, events émis, providers lus
- Les `Key(...)` et `ValueKey(...)` et les `Semantics` / `semanticsLabel` : les tests widget, `bdd_widget_test` et flows Maestro s'en servent
- Les clés l10n existantes (on les réutilise, on n'en renomme aucune)
- Les comportements : navigation, dialogs, snackbars, pull-to-refresh, pagination

### Détection des tests liés

- `grep` des noms de widgets de l'écran et de ses clés dans `test/`, `integration_test/`, `maestro/`
- Goldens : fichiers utilisant `matchesGoldenFile` / `screenMatchesGolden` qui couvrent l'écran
- Widgetbook : use cases qui référencent ses widgets

### Vérification

1. `dart analyze` sur les fichiers touchés, zéro nouveau warning
2. `flutter test` sur les tests liés détectés, tous verts
3. Goldens liés : les régénérer (`--update-goldens`) seulement après validation visuelle de l'utilisateur, jamais pour faire passer un test rouge
4. Visuel : captures avant / après sur simulateur ou émulateur (flow Maestro si le repo en a, sinon lancement manuel), en clair et en sombre, et une fois en grande taille de police. Regarder chaque capture avant de conclure.

---

## Templates de fichiers

Les noms `AppPageScaffold`, `AppLoadingView`, `AppErrorView`, `AppEmptyView` et `AppSpacing` sont des exemples : utiliser ceux de **Anatomie du projet**.

### Page principale avec BLoC (`{screen_name}_page.dart`)

```dart
class {ScreenName}Page extends StatelessWidget {
  const {ScreenName}Page({super.key});

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: context.l10n.{screenName}Title,
      body: BlocBuilder<{ScreenName}Bloc, {ScreenName}State>(
        builder: (context, state) => switch (state) {
          {ScreenName}Initial() || {ScreenName}Loading() =>
            const AppLoadingView(),
          {ScreenName}Loaded(:final data) =>
            {ScreenName}LoadedView(data: data),
          {ScreenName}Error(:final message) => AppErrorView(
              message: message,
              onRetry: () => context
                  .read<{ScreenName}Bloc>()
                  .add(const {ScreenName}Requested()),
            ),
          {ScreenName}Empty() => AppEmptyView(
              message: context.l10n.{screenName}Empty,
            ),
        },
      ),
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
    return AppPageScaffold(
      title: context.l10n.{screenName}Title,
      body: ref.watch({screenName}Provider).when(
            data: (data) => {ScreenName}LoadedView(data: data),
            loading: () => const AppLoadingView(),
            error: (error, _) => AppErrorView(
              message: error.toString(),
              onRetry: () => ref.invalidate({screenName}Provider),
            ),
          ),
    );
  }
}
```

### Vue Loaded (`{screen_name}_loaded_view.dart`)

```dart
class {ScreenName}LoadedView extends StatelessWidget {
  const {ScreenName}LoadedView({super.key, required this.data});

  final {Data} data;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: [
        // Sections séparées par AppSpacing.section
      ],
    );
  }
}
```

### Vues d'état (dans le DS, créées une seule fois)

Uniquement si le DS ne les a pas encore. Elles servent à toutes les pages, jamais recopiées en classes privées.

```dart
class AppErrorView extends StatelessWidget {
  const AppErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.page),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: AppSpacing.item,
          children: [
            Text(
              message,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            FilledButton(
              onPressed: onRetry,
              child: Text(context.l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}
```

`AppLoadingView` (indicateur adaptatif centré) et `AppEmptyView` (icône, message, action optionnelle) suivent le même modèle.

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
