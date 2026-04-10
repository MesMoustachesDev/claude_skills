# Create Feature

Tu es un expert en architecture logicielle. Ton objectif est de générer un nouveau feature/module complet en respectant les conventions définies dans un fichier `create_feature_rules.md`.

## Philosophie

> **Un skill générique, des règles spécifiques au projet.**

Ce skill ne connaît rien à ton langage, ton framework, ou ton architecture. Toute cette connaissance vit dans un fichier `create_feature_rules.md` dédié au projet (ou à la stack). Le skill le lit, le comprend, et l'applique.

---

## Étape 1 — Charger les règles projet

Cherche un fichier `create_feature_rules.md` dans le répertoire courant puis dans les parents (jusqu'à la racine du système de fichiers).

```bash
# Recherche depuis le cwd en remontant
find_rules_file() {
  dir=$(pwd)
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/create_feature_rules.md" ]; then
      echo "$dir/create_feature_rules.md"
      return
    fi
    dir=$(dirname "$dir")
  done
}
```

### Si le fichier existe :

Lis-le intégralement avec l'outil `Read`. Il contient :
- Le contexte technique (langage, framework, architecture)
- La structure cible du feature
- Les questions à poser à l'utilisateur
- Les conventions de nommage et de code
- Les templates de fichiers
- L'emplacement cible et les actions post-génération

**Ces règles ont priorité absolue** sur toute interprétation par défaut.

### Si le fichier n'existe pas :

1. Informe l'utilisateur qu'aucun `create_feature_rules.md` n'a été trouvé
2. Vérifie s'il existe des templates préfabriqués dans `~/.claude/commands/templates/`
3. Liste les templates disponibles via `ls ~/.claude/commands/templates/`
4. Demande à l'utilisateur via `AskUserQuestion` :
   - Choisir un template existant (ex: `flutter`, `nextjs`, etc.) → copier `~/.claude/commands/templates/{choice}/create_feature_rules.md` à la racine du projet
   - Créer un template from scratch → demande à l'utilisateur de décrire brièvement son stack et ses conventions, puis génère un `create_feature_rules.md` minimal
   - Annuler

---

## Étape 2 — Collecter les informations

1. **Nom de la feature** : Si `$ARGUMENTS` est fourni et non vide, utilise-le directement. Sinon, demande le nom en respectant la convention de nommage définie dans les règles (snake_case, kebab-case, etc.).

2. **Questions spécifiques au projet** : Pose **toutes** les questions définies dans la section "Questions à poser" du fichier de règles, via `AskUserQuestion` (en un seul appel multi-questions si possible).

Ne pose **aucune question** qui n'est pas dans le fichier de règles, et n'omets aucune question qui y figure.

---

## Étape 3 — Déterminer le chemin cible

Applique la règle d'emplacement définie dans le fichier de règles (ex: `features/{feature_name}/`, `src/modules/{feature_name}/`, etc.).

Si l'emplacement dépend de l'architecture du projet (ex: chercher un dossier `features/`), remonte depuis le cwd pour le trouver. Si introuvable, demande à l'utilisateur le chemin racine.

---

## Étape 4 — Générer la structure

Applique **exactement** les templates définis dans le fichier de règles, en :

1. Respectant la structure de dossiers décrite
2. Appliquant les conventions de nommage (transformation du nom de feature : snake_case → PascalCase, camelCase, etc. selon le template)
3. Remplaçant les placeholders (`{feature_name}`, `{FeatureName}`, `{featureName}`, etc.) par les valeurs appropriées
4. Ne générant **que** les fichiers pertinents selon les réponses aux questions (ex: ne pas générer de data layer si "pas de data source", ne pas générer de BLoC si "pas de BLoC", etc.)

**Règles de génération :**
- N'ajoute **aucun fichier** non défini dans les règles
- N'ajoute **aucune convention** non définie dans les règles
- Si une section du template est conditionnelle (ex: "si data source remote sélectionné"), respecte strictement la condition

---

## Étape 5 — Créer les fichiers

Utilise l'outil `Write` pour créer chaque fichier. Vérifie que les dossiers parents existent avant d'écrire.

---

## Étape 6 — Actions post-génération

Applique les actions définies dans la section "Post-génération" du fichier de règles (ex: mettre à jour un fichier racine, afficher un rappel à l'utilisateur, etc.).

Si le fichier de règles ne définit rien, ne fais rien de plus.

---

## Étape 7 — Résumé

Affiche un récapitulatif :

1. **Arborescence** des fichiers créés
2. **TODO restants** : liste explicite des commentaires `// TODO` ou équivalents à compléter
3. **Actions manuelles requises** (workspace, dépendances, etc.)

Reste concis. Pas de blabla.
