---
name: ga4
description: Administre une propriété Google Analytics 4 en ligne de commande, par l'Admin API — lister les comptes et propriétés, lister et créer les dimensions et métriques personnalisées (custom definitions). À utiliser dès qu'un paramètre d'event ajouté ou renommé doit être enregistré dans GA4, ou pour vérifier ce qui y est déjà, au lieu de passer par l'interface web.
---

# GA4 en ligne de commande

Un paramètre d'event n'apparaît dans les rapports GA4 que s'il est enregistré en définition personnalisée, et
seulement pour les events envoyés après. Quand un changement ajoute un paramètre, on l'enregistre dans le même
tour, par ce script, jamais par l'interface web.

```bash
S=~/.claude/skills/ga4/ga4.py
python3 $S whoami                       # vérifie l'accès ; liste comptes et propriétés (id, nom)
python3 $S defs <propriété>             # dimensions et métriques déjà enregistrées
python3 $S add-dim <propriété> <param> "<Nom affiché>" --desc "<ce que contient le paramètre>" [--scope USER] [--dry-run]
python3 $S add-metric <propriété> <param> "<Nom affiché>" --unit SECONDS --desc "…" [--dry-run]
```

- `<propriété>` : l'id numérique, ou la clé du projet dans `~/.claude-local/ga4.ini` (`<clé> = <id>`, une
  ligne par projet, hors du repo public). Une propriété manquante : `whoami` donne son id, ajoute la ligne.
- Vérifie la propriété avant d'écrire : plusieurs projets partagent le même compte, et le nom affiché
  (`whoami`) n'est pas toujours celui de l'app.
- `add-*` est idempotent : un paramètre déjà enregistré sort en `already exists`, pas en erreur. Montre la
  commande avec `--dry-run`, puis lance-la.
- Dimension (texte, booléen) ou métrique (nombre qu'on veut sommer) : suis le tableau « Custom definitions »
  de la doc analytics du projet s'il y en a une, et mets-le à jour dans le même changement.
- Description : ce que contient le paramètre, ses valeurs possibles ; jamais de donnée d'utilisateur.

## Accès

Le script prend les credentials par défaut de gcloud (`gcloud auth application-default`). Il leur faut le scope
`analytics.edit`. Sans lui, le script s'arrête (code 3) et imprime la seule commande qui répare :

```bash
gcloud auth application-default login --client-id-file="$HOME/.config/gcloud/ga-client.json" --scopes=https://www.googleapis.com/auth/analytics.edit,https://www.googleapis.com/auth/analytics.readonly,https://www.googleapis.com/auth/cloud-platform
```

C'est une connexion Google interactive : tu la montres à l'utilisateur, il la lance lui-même, tu ne la lances
pas à sa place. Elle remplace les credentials par défaut ; garder `cloud-platform` dans les scopes évite de
casser les autres outils qui s'en servent. Le compte actif de `gcloud auth login` ne compte pas ici.

Le MCP `analytics-mcp` lit les rapports avec ces mêmes credentials ; il ne crée rien. Pour écrire, ce script.
