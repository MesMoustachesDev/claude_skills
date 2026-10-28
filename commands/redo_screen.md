# Redo Screen

Tu es un expert UI. Tu refais la présentation d'un écran **existant** pour qu'il suive le design system et la même anatomie que les autres pages de l'app, sans toucher à sa logique ni casser ses tests. Les conventions viennent du même fichier `create_screen_rules.md` que `/create_screen`.

## Philosophie

> **On change la charpente visuelle, jamais le contrat.**

Principes universels, quelle que soit la stack :
- Un écran refait doit ressembler à ses voisins : même squelette, mêmes marges, mêmes états, même place pour l'action principale. Le DS seul ne suffit pas, l'anatomie de page compte autant.
- La logique, le state management, les routes, les clés de test et les clés l10n existantes sont un contrat. On les préserve.
- Un composant visuel utile à plusieurs écrans va dans le design system, pas dans le dossier de l'écran.
- Aucun changement n'est présenté comme fini sans vérification : analyse statique, tests liés, captures avant / après regardées.

---

## Étape 1 — Charger les règles projet

Cherche `create_screen_rules.md` dans `.claude/rules/` à la racine du repo Git.

- **S'il existe** : lis-le intégralement avec `Read`. Les sections **Anatomie de page**, **Anatomie du projet** et **Refaire un écran existant** pilotent cette commande. Ces règles ont priorité absolue.
- **S'il n'existe pas** : même procédure que `/create_screen` (lister `~/.claude/commands/templates/`, proposer via `AskUserQuestion` de copier un template, d'en créer un minimal, ou d'annuler).

---

## Étape 2 — Identifier la cible

L'input est : **$ARGUMENTS**

- **Chemin d'un fichier page** ou **nom d'écran** → l'écran à refaire (si le nom correspond à plusieurs fichiers, demande lequel)
- **`--audit`** dans l'input → mode audit : s'arrêter après l'étape 5, sans rien modifier
- **Screenshot ou description en plus** → cible visuelle à atteindre, toujours contrainte par le DS et l'anatomie
- **Vide** → demande l'écran à refaire

---

## Étape 3 — Inventaire de l'existant

Lis la page et tous les widgets qu'elle utilise dans son dossier. Puis établis, en suivant la section **Refaire un écran existant** des règles :

1. **Le contrat à préserver** : API publique, route, binding au state management, events / actions, clés de test, sémantique, clés l10n, comportements (navigation, dialogs, snackbars, refresh, pagination)
2. **Les tests liés** : tests unitaires, widget, d'acceptation, goldens, flows end-to-end, catalogues de composants qui référencent l'écran ou ses widgets
3. **Une capture « avant »** selon la méthode visuelle des règles, si un appareil ou simulateur est disponible

---

## Étape 4 — Charger l'anatomie de référence

- **Si la section Anatomie du projet est remplie** dans les règles du repo : c'est la référence.
- **Sinon** : repère les écrans qui partagent déjà un squelette commun, propose-en 2 ou 3 via `AskUserQuestion` (« lesquels sont les bons modèles ? »), lis-les, et déduis l'anatomie (scaffold, AppBar, en-têtes de section, espacements, états, action principale). Propose ensuite de l'écrire dans la section **Anatomie du projet** du `create_screen_rules.md` du repo, pour que tous les écrans suivants s'y alignent.

---

## Étape 5 — Rapport d'écart

Compare l'écran à l'anatomie et aux conventions visuelles des règles. Présente un tableau concis :

| Point | Actuel | Attendu |
|---|---|---|
| Scaffold / AppBar | … | … |
| Espacements | valeurs magiques ? | tokens |
| Hiérarchie typo | … | … |
| États Loading / Error / Empty | locaux / absents ? | widgets DS partagés |
| Action principale | … | … |
| Composants qui dupliquent le DS | … | composant DS |
| Strings en dur | … | l10n |

Ajoute un wireframe ASCII **avant / après**.

Liste à part les **composants manquants dans le DS** que l'écran nécessite (et qui serviraient ailleurs) : ils sont créés dans le DS, pas localement.

- **Mode `--audit`** : affiche le rapport et arrête-toi.
- **Sinon** : demande validation via `AskUserQuestion` avant toute écriture (refaire tel quel, ajuster, annuler).

---

## Étape 6 — Réécrire la présentation

En appliquant les templates, l'anatomie et les conventions des règles :

1. Ne modifier que les fichiers de présentation de l'écran (et le DS pour les composants validés à l'étape 5)
2. Garder intact le contrat de l'étape 3 : même API publique, même binding, mêmes clés de test, même sémantique
3. Remplacer les états locaux par les widgets d'état du DS
4. Découper en composants nommés selon la structure de fichiers des règles ; supprimer les fichiers devenus inutiles et leurs imports
5. Aucune valeur visuelle magique, aucune string en dur

---

## Étape 7 — Localisation

Réutilise les clés existantes, sans en renommer aucune. Crée de nouvelles clés seulement pour du texte nouveau, au format du projet, et liste-les dans le résumé.

---

## Étape 8 — Vérifier

Applique la section **Vérification** des règles :

1. Analyse statique sur les fichiers touchés, zéro nouveau warning
2. Tests liés de l'étape 3, tous verts. Un test rouge signale un contrat cassé : corrige le code, jamais le test
3. Goldens / snapshots : ne les régénérer qu'après validation visuelle de l'utilisateur
4. Captures **après** (clair, sombre, grande police) comparées aux captures avant et aux écrans de référence. Regarde chaque capture avant de conclure.

Si une vérification n'a pas pu tourner (pas d'appareil, outil absent), dis-le explicitement.

---

## Étape 9 — Résumé

1. **Fichiers** modifiés / créés / supprimés
2. **Écarts corrigés** (repris du tableau de l'étape 5)
3. **Contrat préservé** : confirmation point par point (API, binding, clés de test, l10n)
4. **Vérification** : résultat de l'analyse, des tests, chemins des captures avant / après
5. **Ajouts au DS** et **clés l10n** nouvelles
6. **TODO restants**

Reste concis.
