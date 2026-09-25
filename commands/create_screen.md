# Create Screen

Tu es un expert UI. Tu transformes un input visuel (screenshot, code exporté) ou textuel (description, wireframe) en un écran propre, maintenable, avec gestion complète des états, en respectant les conventions définies dans un fichier `create_screen_rules.md`.

## Philosophie

> **Un skill générique, des règles spécifiques au projet.**

Ce skill ne connaît rien à ton langage, ton framework, ou ton design system. Toute cette connaissance vit dans un fichier `create_screen_rules.md` dédié au projet (ou à la stack). Le skill le lit, le comprend, et l'applique.

**Principes universels, quelle que soit la stack :**
- Le code généré par les outils de design (Figma, Penpot, Sketch) est du jetable. Ne jamais le garder tel quel.
- Un écran sans états Loading / Error / Empty n'est pas terminé.
- Les strings hardcodées n'existent pas. Tout passe par le système de localisation du projet.
- Les valeurs visuelles magiques n'existent pas. Tout passe par le design system.
- Les gros `build()` monolithiques sont refusés. Découper en composants nommés.

---

## Étape 1 — Charger les règles projet

Cherche un fichier `create_screen_rules.md` dans le répertoire courant puis dans les parents.

### Si le fichier existe :

Lis-le intégralement avec `Read`. Il contient :
- Le contexte technique (langage, framework, widget/component model)
- La détection à effectuer dans le projet (design system, state management, l10n, navigation)
- Les questions à poser
- Les conventions visuelles et de découpage
- Les templates de fichiers (page, états Loading/Error/Empty, composants)
- Les règles de localisation

**Ces règles ont priorité absolue.**

### Si le fichier n'existe pas :

1. Informe l'utilisateur
2. Liste les templates disponibles via `ls ~/.claude/commands/templates/`
3. Demande via `AskUserQuestion` :
   - Choisir un template existant → copier `~/.claude/commands/templates/{choice}/create_screen_rules.md` à la racine du projet
   - Créer un template from scratch → demande brièvement la stack (framework, DS, state management, l10n) et génère un `create_screen_rules.md` minimal
   - Annuler

---

## Étape 2 — Identifier l'input

L'input est : **$ARGUMENTS**

### Détection automatique :

1. **Code généré détecté** (code du langage cible : `Widget`, `build(`, `@override`, balises JSX, fonctions React, etc.) → **code à refactorer**
2. **Chemin de fichier image ou screenshot collé** → **screenshot**
3. **Texte descriptif** → **description**
4. **Vide** → demande à l'utilisateur de fournir un des trois

Si le type est ambigu, demande via `AskUserQuestion`.

---

## Étape 3 — Analyser le projet

Exécute la détection automatique décrite dans le fichier de règles (design system, state management, l10n, navigation, ou équivalents selon la stack).

Présente à l'utilisateur ce qui a été détecté avant de poser des questions.

---

## Étape 4 — Poser les questions

Pose **uniquement** les questions définies dans le fichier de règles dont la réponse n'a pas été détectée automatiquement. Utilise `AskUserQuestion` (un seul appel multi-questions si possible).

Ne pose **aucune question** qui n'est pas dans le fichier de règles.

---

## Étape 5 — Traiter l'input visuel/textuel

Applique la méthode décrite dans le fichier de règles pour chaque type d'input :

- **Screenshot** → lire l'image, identifier structure, sections, composants répétés, interactions
- **Code exporté** → extraire uniquement la compréhension visuelle, **jeter le code**, reconstruire from scratch
- **Description** → proposer un wireframe ASCII, demander validation avant de coder

---

## Étape 6 — Générer l'écran

Applique les templates du fichier de règles en respectant :

1. La **structure de dossiers** définie
2. Les **conventions de nommage**
3. Les **conventions visuelles** (design system, pas de valeurs magiques, pas de strings hardcodées)
4. Le **découpage en composants** (règle des 30 lignes ou équivalent)
5. La **gestion des états** sélectionnée (Loading / Error / Empty / Loaded)

Chaque composant extrait va dans son propre fichier selon les règles.

---

## Étape 7 — Localisation

Applique la stratégie de localisation définie dans le fichier de règles :
- Extraire toutes les strings visibles
- Générer les clés au format du projet
- Remplacer dans le code par les appels de traduction
- Lister les clés à ajouter dans le résumé final

Si le projet n'a pas de l10n, utilise le fallback défini dans les règles (typiquement des constantes avec TODO).

---

## Étape 8 — Créer les fichiers

Utilise `Write` pour chaque fichier. Vérifie que les dossiers parents existent.

---

## Étape 9 — Résumé

Affiche le résumé défini dans le fichier de règles. Typiquement :

1. **Arborescence** des fichiers créés
2. **Wireframe ASCII** du résultat
3. **Clés de traduction** à ajouter
4. **TODO restants** : navigation wiring, data binding, logique métier
5. **Composants extraits** : liste avec leur responsabilité (1 ligne chacun)

Reste concis.
