# Create Merge Request

Tu es un expert en gestion de versions. Ton objectif est d'analyser les changements de la branche courante et de créer une Merge Request / Pull Request propre, bien documentée, via le CLI approprié.

## Philosophie

> **Un skill générique, des règles spécifiques au projet.**

Ce skill ne connaît rien à ton provider Git, ton CLI, ou tes conventions de MR. Toute cette connaissance vit dans un fichier `create_mr_rules.md` dédié au projet. Le skill le lit, le comprend, et l'applique.

---

## Étape 1 — Charger les règles projet

Cherche un fichier `create_mr_rules.md` dans le répertoire courant puis dans les parents (jusqu'à la racine du système de fichiers).

### Si le fichier existe :

Lis-le intégralement avec `Read`. Il contient :
- Le CLI à utiliser (`gh`, `glab`, script custom…)
- La branche de base par défaut
- Le format du titre et du body
- Les labels, reviewers, assignees par défaut
- Les conventions spécifiques (tickets, prefixes, etc.)

**Ces règles ont priorité absolue.**

### Si le fichier n'existe pas :

1. Informe l'utilisateur
2. Liste les templates disponibles via `ls ~/.claude/commands/templates/`
3. Demande via `AskUserQuestion` :
   - Choisir un template existant → copier `~/.claude/commands/templates/{choice}/create_mr_rules.md` à la racine du projet
   - Créer un `create_mr_rules.md` minimal → demande le provider (GitHub, GitLab, etc.), le CLI, la branche de base, et génère le fichier
   - Annuler

---

## Étape 2 — Collecter le contexte Git

### Détection automatique

```bash
# Branche courante
git branch --show-current

# Branche de base (depuis les règles, ou détection auto)
# Vérifier que la branche courante n'est PAS la branche de base

# Remote
git remote -v
```

### Vérifications de sécurité

1. **La branche courante ne doit pas être la branche de base.** Si c'est le cas → erreur, demande de changer de branche.
2. **Vérifier qu'il y a des commits à merger.** S'il n'y a aucun commit au-dessus de la base → erreur.
3. **Vérifier qu'il n'y a pas de changements non commités.** Si oui → avertir l'utilisateur et demander s'il veut continuer ou commiter d'abord.

---

## Étape 3 — Analyser les changements

```bash
# Commits de la branche
git log {base_branch}..HEAD --oneline

# Diff complet
git diff {base_branch}...HEAD

# Fichiers modifiés
git diff {base_branch}...HEAD --name-status
```

Analyse :
- Le **périmètre** des changements (quelles features/modules/couches sont touchés)
- La **nature** des changements (feature, bugfix, refactor, chore, etc.)
- Les **points d'attention** (fichiers critiques modifiés, migrations, breaking changes)

---

## Étape 4 — Générer le titre et la description

### Titre

Génère un titre concis en respectant le format défini dans les règles (convention de prefix, longueur max, langue, etc.).

Si `$ARGUMENTS` est fourni et non vide, utilise-le comme indication pour le titre (ça peut être un titre direct ou une description libre).

### Description / Body

Génère le body en suivant le template défini dans les règles. Typiquement :
- Résumé des changements (2-5 bullet points)
- Détail technique si pertinent
- Lien vers le ticket si applicable
- Checklist de review si définie dans les règles

---

## Étape 5 — Présenter à l'utilisateur

Affiche le résultat AVANT de créer la MR :

```
## MR Preview

**Titre** : {titre}
**Base** : {base_branch} ← {current_branch}
**Labels** : {labels}
**Reviewers** : {reviewers}

### Description
{body}
```

Demande confirmation via `AskUserQuestion` :
- **Créer la MR** telle quelle
- **Modifier** → demande ce qu'il veut changer (titre, description, labels…) puis re-présente
- **Annuler**

---

## Étape 6 — Pousser et créer la MR

### Push

Vérifie que la branche est poussée sur le remote. Si non :

```bash
git push -u origin {current_branch}
```

### Création

Utilise le CLI défini dans les règles pour créer la MR avec tous les paramètres (titre, body, labels, reviewers, base branch, etc.).

Passe le body via un HEREDOC pour préserver le formatage :

```bash
{cli_command} <<'EOF'
{body}
EOF
```

---

## Étape 7 — Résumé

Affiche :
1. **URL de la MR** créée
2. **Titre** final
3. **Base** : `{base_branch} ← {current_branch}`
4. **Labels** et **Reviewers** assignés

Reste concis.
