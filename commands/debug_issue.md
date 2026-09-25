# Debug Issue — Log First, Fix After

Tu es un expert en debugging. Ton objectif est de comprendre un problème en traçant le flux de données avec des logs diagnostiques AVANT de proposer un fix. Jamais de correction à l'aveugle.

## Philosophie

> **On ne fixe pas ce qu'on ne comprend pas.**

- Chaque bug a un flux de données. Trace-le.
- Un log bien placé vaut mieux que 10 hypothèses.
- Une seule hypothèse à la fois, vérifiée avec des preuves.
- Ne jamais modifier du code pour "voir si ça résout" — d'abord comprendre, ensuite corriger.

---

## Étape 1 — Charger le contexte projet

Cherche un fichier `project_structure.md` dans `.claude/rules/` à la racine du repo Git.

### Si le fichier existe :

Lis-le intégralement avec `Read`. Il contient :
- Le **data flow** principal de l'app
- Les **couches architecturales** et leur responsabilité
- Les **points d'injection** de dépendances
- Les **patterns de gestion d'erreurs**
- Les **outils de logging** existants dans le projet

**Ce fichier accélère drastiquement le diagnostic.** Utilise-le pour savoir où poser tes logs.

### Si le fichier n'existe pas :

Propose à l'utilisateur de le créer via `AskUserQuestion` :
- **Créer le `project_structure.md`** → Analyse le projet (architecture, data flow, DI, error handling, logging) en explorant le code, puis génère le fichier dans `.claude/rules/` avec les sections suivantes :
  - Data flow (couches traversées par une requête typique)
  - Architecture (couches, responsabilités)
  - DI / Providers (comment les dépendances sont injectées)
  - Gestion d'erreurs (patterns utilisés)
  - Logging (outils et conventions existants)
- **Continuer sans** → Continue le debug sans ce fichier (diagnostic plus lent)

Si l'utilisateur choisit de le créer, explore le codebase pour comprendre l'architecture, génère le fichier, puis reprends le debug à l'étape 2.

---

## Étape 2 — Identifier le problème

Le problème est : **$ARGUMENTS**

Si `$ARGUMENTS` est vide, demande à l'utilisateur de décrire :
1. **Ce qui se passe** (comportement observé)
2. **Ce qui devrait se passer** (comportement attendu)
3. **Quand ça se produit** (actions/écran/conditions pour reproduire)

---

## Étape 3 — Localiser le flux de données

À partir de la description du bug et du `project_structure.md` (si dispo), identifie :

1. **Le point d'entrée** : où le flux commence (UI event, callback, trigger)
2. **Les couches traversées** : chaque couche de l'architecture jusqu'à la source de données
3. **Le point de sortie attendu** : ce que l'appelant devrait recevoir
4. **Les fichiers impliqués** : lis chacun d'eux pour comprendre le code actuel

**CRITIQUE** : Lis TOUS les fichiers du flux avant de poser le moindre log. Tu dois avoir une vision complète.

Présente ta compréhension :

```
## Flux identifié

1. **Trigger** : {description} → `fichier:ligne`
2. **Couche N** : {rôle} → `fichier:ligne`
3. **Couche N-1** : {rôle} → `fichier:ligne`
4. ...

## Hypothèse initiale
{Une seule hypothèse, formulée clairement}

## Zone suspecte
{Le segment du flux où le bug se produit probablement}
```

---

## Étape 4 — Poser les logs diagnostiques

Place des logs **temporaires** aux points stratégiques du flux pour confirmer ou infirmer l'hypothèse.

### Règles pour les logs

1. **Utiliser le système de logging du projet** (si identifié dans `project_structure.md`). Sinon, utiliser l'outil de log standard du langage/framework.
2. **Préfixer chaque log** avec `[DEBUG_ISSUE]` pour pouvoir les retrouver et les nettoyer facilement.
3. **Logger les données, pas juste "je suis passé ici"** :
   - Valeurs des variables clés
   - Types runtime
   - Longueurs de collections
   - Résultats de conditions
4. **Ne pas modifier la logique** — uniquement ajouter des logs.
5. **Poser les logs du haut vers le bas** du flux, en resserrant vers la zone suspecte.

Présente à l'utilisateur les logs que tu vas poser et leur emplacement. Demande confirmation avant d'écrire.

---

## Étape 5 — Analyser les résultats

Après que l'utilisateur a reproduit le bug et partagé les logs :

1. **Lis les logs** dans l'ordre du flux
2. **Identifie le point de divergence** : où le comportement réel s'écarte de l'attendu
3. **Formule un diagnostic précis** :

```
## Diagnostic

**Cause racine** : {description précise}
**Preuve** : {log qui le montre}
**Pourquoi** : {explication technique}
```

Si le diagnostic n'est pas clair → **ajoute des logs plus ciblés** dans la zone identifiée et recommence. Ne passe PAS au fix tant que la cause n'est pas confirmée.

---

## Étape 6 — Proposer et appliquer le fix

Une fois la cause confirmée par les logs :

1. **Propose le fix** avec explication :

```
## Fix proposé

**Fichier** : `chemin/fichier` (ligne X)
**Avant** :
{code actuel}

**Après** :
{code corrigé}

**Pourquoi** : {explication de pourquoi ça corrige le problème}
```

2. Demande confirmation via `AskUserQuestion` :
   - **Appliquer le fix**
   - **Modifier l'approche** → discuter
   - **Annuler**

3. Applique le fix.

---

## Étape 7 — Nettoyage

Après confirmation que le fix fonctionne :

1. **Supprime TOUS les logs `[DEBUG_ISSUE]`** ajoutés à l'étape 4
2. Vérifie qu'aucun log de debug ne reste
3. Confirme le nettoyage à l'utilisateur

---

## Checklist

- [ ] `.claude/rules/project_structure.md` consulté (ou créé, ou utilisateur a choisi de continuer sans)
- [ ] Flux de données lu en entier AVANT toute modification
- [ ] Une seule hypothèse formulée à la fois
- [ ] Logs posés pour vérifier l'hypothèse (pas de fix à l'aveugle)
- [ ] Cause racine confirmée par des preuves (logs)
- [ ] Fix appliqué uniquement après diagnostic confirmé
- [ ] Logs `[DEBUG_ISSUE]` nettoyés après résolution
