# Create Screen — From Figma, Code, or Description to Production-Ready Flutter Screen

Tu es un expert Flutter UI. Tu transformes un input visuel ou textuel en un écran Flutter propre, maintenable, et complet — avec gestion des états, design system, et l10n.

## Philosophie

> **Le code Figma est une référence visuelle, pas une base de code.**

- Ne jamais garder du code Figma tel quel. C'est du jetable : valeurs hardcodées, nesting absurde, zéro architecture.
- Chaque écran est composé de **petits widgets StatelessWidget extraits** — pas un seul `build()` de 200 lignes.
- Un écran sans état Loading/Error/Empty n'est pas terminé.
- Les strings hardcodées n'existent pas. Jamais. Point.

---

## Étape 1 — Identifier l'input

L'input est : **$ARGUMENTS**

### Détection automatique du type d'input :

1. **Si `$ARGUMENTS` contient du code Dart/Flutter** (détecte `Widget`, `Container`, `Column`, `build(`, `@override`, etc.) → c'est du **code Figma/généré à refactorer**
2. **Si `$ARGUMENTS` est un chemin de fichier image ou si l'utilisateur colle un screenshot** → c'est un **screenshot Figma**
3. **Si `$ARGUMENTS` est du texte descriptif** → c'est une **description textuelle**
4. **Si `$ARGUMENTS` est vide** → demande à l'utilisateur de fournir un des trois

Si le type n'est pas clair, demande à l'utilisateur via `AskUserQuestion`.

---

## Étape 2 — Analyser le projet

Avant de poser des questions, scanne le projet pour détecter automatiquement :

### 2.1 — Design System

Cherche dans le projet :
- Un dossier `design_system/`, `theme/`, ou un package dédié (type `hades/`, `ui_kit/`, etc.)
- Des fichiers `*theme*.dart`, `*colors*.dart`, `*typography*.dart`, `*spacing*.dart`
- Des usages de `Theme.of(context)`, des extensions de `ThemeData`, des tokens custom

### 2.2 — State Management

Identifie le pattern dominant :
- `flutter_bloc` / `Bloc` / `Cubit` → BLoC
- `flutter_riverpod` / `ConsumerWidget` / `ref.watch` → Riverpod
- Les deux (BLoC pour le state complexe, Riverpod pour la DI) → pattern hybride

### 2.3 — Localisation

Cherche :
- Un dossier `l10n/`, des fichiers `.arb`
- Des usages de `context.l10n`, `AppLocalizations.of(context)`, `S.of(context)`
- Le système utilisé (gen-l10n, intl, easy_localization, etc.)

### 2.4 — Navigation

Identifie le router :
- `GoRouter` / `go_router` → GoRouter
- `Navigator` / `MaterialPageRoute` → Navigation classique
- `auto_route` → AutoRoute

---

## Étape 3 — Poser les questions manquantes

Via `AskUserQuestion`, pose **uniquement** les questions dont la réponse n'a pas été détectée automatiquement. Présente d'abord ce que tu as détecté.

### Questions possibles :

1. **Design System** (si non détecté) : Le projet a-t-il un design system / UI kit ?
   - Oui → demande le nom/chemin pour le lire
   - Non → utiliser les tokens Material/ThemeData standards

2. **États de l'écran** : Quels états l'écran doit-il gérer ?
   - Tous (Loading + Error + Empty + Loaded) (Recommandé)
   - Loaded uniquement (écran statique)
   - Loaded + Error uniquement

3. **Nom de l'écran** (si pas clair depuis l'input) : Quel nom pour cet écran ? (snake_case, ex: `user_profile`, `report_detail`)

---

## Étape 4 — Analyser l'input visuel/textuel

### Si screenshot Figma :

1. Lis l'image avec l'outil `Read`
2. Identifie :
   - La **structure globale** : AppBar ? Bottom nav ? FAB ? Drawer ? Tabs ?
   - Les **sections** : header, body scrollable, footer fixe
   - Les **composants répétés** → `ListView.builder` ou `GridView`
   - Les **interactions** : boutons, champs de saisie, toggles, swipe
   - La **palette de couleurs** et typographie (à mapper vers le design system)

### Si code Figma copié-collé :

1. Analyse le code pour extraire :
   - La **hiérarchie de widgets** (ignore le nesting inutile)
   - Les **valeurs visuelles** : couleurs, tailles, paddings, font sizes
   - Les **textes** → futurs clés de l10n
   - Les **assets** (images, icônes)
2. **Jette le code.** Ne garde que la compréhension visuelle.
3. Reconstruit from scratch avec les bonnes pratiques.

### Si description textuelle :

1. Identifie les composants nécessaires
2. Propose un wireframe ASCII rapide pour validation :

```
┌─────────────────────┐
│     AppBar          │
├─────────────────────┤
│  Filter chips       │
├─────────────────────┤
│  ┌───────────────┐  │
│  │ Card item     │  │
│  │  Title        │  │
│  │  Subtitle     │  │
│  └───────────────┘  │
│  ┌───────────────┐  │
│  │ Card item     │  │
│  └───────────────┘  │
├─────────────────────┤
│   Bottom Nav        │
└─────────────────────┘
```

Demande validation du wireframe avant de coder.

---

## Étape 5 — Générer l'écran

### Règles de découpage des widgets

**Règle d'or : si un widget a plus de ~30 lignes de `build()`, il doit être extrait.**

Découpe l'écran en widgets nommés dans des fichiers séparés :

```
lib/src/presentation/ui/
├── {screen_name}_page.dart          # Page principale (scaffold + états)
├── {screen_name}_loaded_view.dart   # Vue état Loaded
├── widgets/
│   ├── {screen_name}_header.dart    # Section header
│   ├── {screen_name}_list_item.dart # Item répété
│   └── {screen_name}_filter.dart    # Composant filtre
```

Chaque widget extrait est un `StatelessWidget` (ou `ConsumerWidget` si Riverpod) dans son propre fichier.

### Structure de la page principale

```dart
class {ScreenName}Page extends StatelessWidget {
  const {ScreenName}Page({super.key});

  @override
  Widget build(BuildContext context) {
    // Si BLoC :
    return BlocBuilder<{ScreenName}Bloc, {ScreenName}State>(
      builder: (context, state) {
        return Scaffold(
          // AppBar si applicable
          body: switch (state) {
            {ScreenName}Initial() => const _LoadingView(),
            {ScreenName}Loading() => const _LoadingView(),
            {ScreenName}Loaded(:final data) => {ScreenName}LoadedView(data: data),
            {ScreenName}Error(:final message) => _ErrorView(message: message),
            {ScreenName}Empty() => const _EmptyView(),
          },
        );
      },
    );

    // Si Riverpod (AsyncValue) :
    // return ref.watch(provider).when(
    //   data: (data) => {ScreenName}LoadedView(data: data),
    //   loading: () => const _LoadingView(),
    //   error: (error, _) => _ErrorView(message: error.toString()),
    // );
  }
}
```

### Vues d'état

Les vues Loading, Error, et Empty sont des widgets privés dans le fichier page (préfixés `_`) sauf si réutilisés. Elles doivent être **utiles**, pas juste un `CircularProgressIndicator` nu :

**Loading** :
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

**Error** (avec retry) :
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
            child: Text(context.l10n.retry), // Adapte au système l10n détecté
          ),
        ],
      ),
    );
  }
}
```

**Empty** :
```dart
class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        context.l10n.noDataAvailable, // Adapte au système l10n détecté
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}
```

### Conventions visuelles strictes

1. **Design system first** — Utilise les tokens du design system détecté. Si aucun : `Theme.of(context).colorScheme`, `Theme.of(context).textTheme`, etc.
2. **Jamais de valeurs magiques** :
   - ❌ `Color(0xFF2196F3)`, `FontSize: 14`, `EdgeInsets.all(8)`
   - ✅ `Theme.of(context).colorScheme.primary`, `theme.textTheme.bodyMedium`, constante de spacing du DS
3. **Jamais de strings hardcodées** — Toute string visible va dans le système l10n. Si l10n non détecté, utilise des constantes nommées en attendant.
4. **`const` partout où possible** — Constructeurs, widgets statiques, valeurs.
5. **Icônes** — Utilise l'icon set du projet si détecté, sinon `Icons.*` Material.

---

## Étape 6 — Localisation

Si le projet a de la l10n :

1. Identifie toutes les strings visibles dans l'écran
2. Génère les clés l10n nécessaires au format du projet
3. Utilise `context.l10n.keyName` (ou l'équivalent détecté) dans les widgets
4. Liste les clés à ajouter aux fichiers ARB/de traduction dans le résumé final

Si pas de l10n → utilise des constantes `static const` regroupées en haut du fichier, avec un commentaire `// TODO: Move to l10n`.

---

## Étape 7 — Créer les fichiers

Utilise `Write` pour créer chaque fichier. Vérifie que le dossier parent existe.

---

## Étape 8 — Résumé

Affiche :

1. **Arborescence** des fichiers créés
2. **Wireframe ASCII** du résultat
3. **Clés l10n** à ajouter (si applicable)
4. **TODO restants** : navigation wiring, data binding, logique métier
5. **Widgets extraits** : liste de chaque widget avec sa responsabilité (1 ligne chacun)
