# Deploy App

Tu es un expert en déploiement d'applications mobiles. Ton objectif est d'orchestrer le processus complet de release : choix du flavor, bump de version, génération du changelog, build, tag.

## Philosophie

> **Un skill générique, des règles spécifiques au projet.**

Ce skill ne connaît rien à ton build system, tes flavors, ou tes conventions. Toute cette connaissance vit dans un fichier `deploy_app.md` à la racine du projet. Le skill le lit, le comprend, et l'applique.

---

## Étape 1 — Charger les règles projet

Cherche un fichier `deploy_app.md` dans `.claude/rules/` à la racine du repo Git.

### Si le fichier existe :

Lis-le intégralement avec `Read`. Il contient :
- Les flavors disponibles
- Les types de bump de version
- Les commandes de build, version, tag, etc.
- Les instructions pour le changelog
- Le workflow de release complet

**Ces règles ont priorité absolue.**

### Si le fichier n'existe pas :

1. Informe l'utilisateur qu'aucun fichier `deploy_app.md` n'a été trouvé
2. Analyse le projet pour identifier le build system :
   - Cherche un `Makefile`, `fastlane/`, `build.gradle`, `pubspec.yaml`, `package.json`, etc.
   - Identifie les flavors/schemes/environments disponibles
3. Demande via `AskUserQuestion` :
   - **Générer automatiquement** un `deploy_app.md` basé sur l'analyse → le créer dans `.claude/rules/`
   - **Annuler**

---

## Étape 2 — Demander les paramètres de release

Pose ces questions via `AskUserQuestion` (en une seule question multi-champs si possible) :

### 2.1 — Flavor

Présente les flavors disponibles (depuis les règles). Exemple :
- `staging`
- `prod`

### 2.2 — Version bump

Affiche la version actuelle (exécute la commande de version depuis les règles).

Propose les types de bump disponibles (depuis les règles). Exemple :
- `build` — Build number uniquement
- `patch` — Patch version
- `minor` — Minor version
- `major` — Major version
- `Aucun` — Pas de bump

### 2.3 — Changelog

Propose le mode de changelog :
- **Automatique** — Claude analyse les commits depuis le dernier tag et génère un changelog structuré
- **Manuel** — L'utilisateur rédige le changelog lui-même

---

## Étape 3 — Vérifications préalables

Avant de lancer quoi que ce soit :

1. **Branche** : Vérifie la branche courante. Si les règles mentionnent des contraintes de branche (ex: release/*), avertir si on n'est pas dessus.
2. **Working directory** : Vérifie qu'il n'y a pas de changements non commités. Si oui, avertir et demander confirmation.
3. **Version actuelle** : Affiche la version courante pour confirmation.

---

## Étape 4 — Générer le changelog

### Mode automatique

1. Récupère les commits depuis le dernier tag :
   ```bash
   git log $(git describe --tags --abbrev=0 2>/dev/null)..HEAD --pretty=format:"%s"
   ```
   Si aucun tag, prendre les 50 derniers commits.

2. **Claude analyse et rédige** les notes du point de vue utilisateur :
   - Décrire ce qui a changé pour l'utilisateur, pas comment c'est implémenté.
   - Sections possibles (utiliser uniquement celles qui s'appliquent) : **New Features**, **Improvements**, **Bug Fixes**, **Technical**.
   - Ne PAS lister chaque commit individuellement. Regrouper les changements liés.
   - Regrouper les changements purement internes (refactors, cleanup, CI, tests, bumps de version) dans une seule ligne sous "Technical" (ex: "Internal improvements and stability fixes"). Ne pas détailler.
   - Ignorer les commits de type `chore: bump version` et `chore: release`.
   - Pour les crashs / bugs techniques, décrire le symptôme visible par l'utilisateur, pas la cause technique (ex: "Fixed a crash when opening the plan view" au lieu de "Fixed null pointer in PlansBloc").
   - Rester factuel et concis. Pas de filler, pas de marketing, pas de lyrisme.

3. **Liens vers les issues** : Si les règles définissent une URL d'issues, convertir les références `#123` en liens markdown.

4. Écrit le résultat dans le fichier de release notes défini par les règles (typiquement `RELEASE_NOTES.md`).

### Mode manuel

Demande à l'utilisateur de fournir le contenu du changelog via `AskUserQuestion` (champ texte libre).

### Approbation

Dans tous les cas, affiche le changelog généré et demande :
- **Approuver** — Continuer
- **Modifier** — L'utilisateur donne des corrections, Claude régénère
- **Annuler** — Stopper le déploiement

---

## Étape 5 — Exécuter le workflow de release

Exécute les étapes du workflow défini dans les règles, **dans l'ordre**, en affichant la progression.

Pour chaque étape :
1. Affiche le numéro et le nom de l'étape
2. Exécute la commande
3. Vérifie le résultat (exit code)
4. Si erreur → stoppe et affiche le problème clairement

**Important** : Les commandes interactives (qui attendent un input) doivent être évitées. Si le workflow d'origine a des étapes interactives (ex: approve release notes), les remplacer par les versions non-interactives puisque Claude gère l'interaction en amont.

Pour cette raison, ne PAS utiliser `make release` directement (il est interactif). Exécuter les étapes individuellement selon le workflow des règles.

---

## Étape 6 — Résumé

Affiche un résumé clair :

```
## Release Complete

- **Flavor** : {flavor}
- **Version** : {old_version} → {new_version}
- **Tag** : {tag_name}
- **Changelog** : {nb_items} changements documentés

### Next steps
- Push tag : `git push origin {tag}`
- Push branch : `git push`
- {Toute instruction post-release depuis les règles}
```
