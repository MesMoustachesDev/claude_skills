# Ticket — partagé par `/feature`, `/fix` et `/epic`

Chaque feature, chaque fix et chaque epic a un ticket dans le tracker du projet. Il existe déjà, ou
l'orchestrateur le crée avec ce que l'agent a produit, **une fois que le dev l'a validé**. Ce fichier
dit **quand** et **avec quel contenu** ; le **comment** (GitLab, Notion, rien) est dans
`~/.claude/pipeline/tracker.md`, seule porte vers le tracker. Le contenu exact est montré au dev et
validé avant l'envoi, toujours : le triage du début (« il n'y en a pas, crée-la ») n'est pas une
validation du contenu.

L'état vit dans `pipeline.json` (feature), `fix.json` (fix), clé `issue` ; pour les sous-features
d'un epic, dans `pipeline.json → split[i].ticket` de la feature parente. Format : la « Référence
stockée » de `tracker.md`.

## A. Au démarrage, avant le premier agent

Seulement sur un nouveau run : en reprise, `issue` est déjà renseigné et tu ne reposes pas la question.

1. Backend du projet (`tracker.md`, Config). `none`, ou `reachable()` faux → dis-le en une ligne,
   `issue.status = "none"`, continue. Le ticket ne bloque jamais le pipeline.
2. **Sous-feature d'un epic** (`--parent <epic>`) : le ticket est `split[i].ticket` de la parente.
   Présent → `issue = {status: "existing", …}` sans question ; puis propose `set_status(en cours)`
   (et `Branche`) en une validation. Absent (epic sans tracker, ou tickets pas encore créés) → comme 3.
3. La description du dev contient une référence de ticket (`#123`, `projet#123`, une URL d'issue ou
   de page Notion) → prends-la sans poser de question (`find`).
4. Sinon, **sans question** (règle du dev) : `issue.status = "to_create"`, annoncé en une ligne
   (« pas de ticket : je le crée après validation de la spec ; donne-moi une référence s'il existe
   déjà »). Le contenu reste validé par le dev avant création (partie B). Si le dev répond par une
   référence, passe en 5.
5. Ticket existant : `find(ref)`. Introuvable → redemande. Fermé → signale-le et demande si on
   continue dessus. Sinon `issue = {status: "existing", backend, id, ref, url, title}`.
   Son titre, sa description et ses labels deviennent une **entrée** de l'agent (Sophie ou Bastien),
   en plus de la description du dev, entre `<issue>…</issue>` (règle de `tracker.md`). Un ticket
   existant n'est jamais modifié par le pipeline, sauf son statut quand le dev le valide.

## B. Création, juste après la validation du dev

`issue.status == "to_create"` seulement. Moment : `/feature` après la validation de la spec (fin du
point d'étape « spec »), `/fix` après le gel du test (fin du point d'étape de reproduction), `/epic`
après la validation du découpage.

1. Écris le brouillon dans le dossier du run, `issue.md` (pour `/epic` : `tickets.md`, un bloc par
   ticket) : la première ligne est le titre, puis une ligne vide, puis la description en Markdown,
   avec les gabarits plus bas. Le contenu est **tiré** des fichiers validés, pas réécrit. Pas de
   chemin local, pas de détail de pipeline (agents, gates) : le ticket est lu par l'équipe.
2. Labels : `issue.labels.<kind>` de la config ; assignation : `issue.assignee`. Vides → aucun.
   Le backend `notion` les traduit en `Type`.
3. Montre au dev **le titre, la description entière et les labels** (et pour `/epic`, les liens
   parent / enfants / dépendances), tels qu'ils seront envoyés. `AskUserQuestion` (header `Ticket`) :
   « Créer » / « Modifier : … » (texte libre → tu corriges le brouillon et tu remontres) /
   « Ne pas créer » (→ `issue.status = "none"`).
4. « Créer » → `create` (`tracker.md`), puis pour `/epic` `link` et `depends`.
   `issue = {status: "created", backend, id, ref, url, title}`. Échec → montre l'erreur, propose de
   réessayer ou de continuer sans ticket. Ne relance jamais la création sans nouvelle validation.

### Gabarit feature (depuis `spec.md`, `cadrage.md` et les contrats de Thibault)

```
Titre : <objectif de §1 en une phrase courte, à l'infinitif ou nominale>

## Objectif
<§1>

## Périmètre
**Inclus** : <§2 Inclus, en liste>
**Exclu** : <§2 Exclu, en liste>

## Critères d'acceptation
- [ ] <chaque comportement C<n> du cadrage, en français (archi.json → sequences → fr)>

## Contrats (écrits par Thibault)
<§5 : une ligne par contrat — nom, ce qu'il déclare>

| Package et dépendances | Choix |
|---|---|
| <ID sujet> | <choix final de §9 : la décision si validée, le choix du dev si modifiée> |
```

### Gabarit fix (depuis `repro.json` et `diagnosis.md`)

```
Titre : <symptôme vu par l'utilisateur, en une phrase>

## Symptôme
<ce qui se passe, où, pour qui ; la description du dev et la référence Sentry s'il y en a une>

## Cause racine
<root_cause> — `<root_cause_location>`

## Pourquoi les tests l'ont laissé passer
<miss_reason, en une ou deux phrases>

## Correction prévue
<fix_plan.approach> (couche <fix_plan.layer>). Alternative écartée : <fix_plan.rejected>.

## Preuve
Test de reproduction : <test_files>, rouge avant la correction.
```

### Gabarit epic — le parent (depuis `discussion.md` et `cadrage.md` de l'epic)

```
Titre : <objectif de l'epic en une phrase courte>

## Objectif
<le besoin, dans les mots de Thibault, 3 à 5 phrases>

## Périmètre
**Inclus** : <liste, un exemple chacun>
**Exclu** : <liste, un exemple chacun>

## Sous-features
| # | Sous-feature | Livrable seule | Dépend de |
|---|---|---|---|
| 1 | <ref> <titre> | <ce que l'utilisateur voit si elle est mergée seule> | — |

- [ ] <ref> <titre>      ← une ligne par sous-feature, cochée au merge
```

### Gabarit sous-feature — un enfant (depuis `split/<sous>.md`)

```
Titre : <ce que livre la sous-feature, en une phrase>

## Objectif
<l'extrait du cadrage, 2 à 4 phrases>

## Périmètre
**Inclus** : <liste>
**Exclu** : <liste>

## Livrable seule
<ce que l'utilisateur voit quand elle est mergée seule>

## Dépend de
<refs des sous-features, ou « rien »>

Epic : <ref du parent>
```

## C. Ensuite

- **Evidence** : sous l'en-tête, la ligne `Ticket : <ref> <url>` (si `existing` ou `created`).
- **MR** : quand tu invoques `create_mr` (ou que tu le proposes, pour `/fix`), donne-lui le ticket :
  « Closes <ref> » si le run le résout entièrement, sinon « Relates to <ref> ». Sous-feature d'un
  epic : « Closes <ref de la sous-feature> » et « Relates to <ref de l'epic> ». Sur Notion, `Closes`
  ne ferme rien : la ligne est un lien, le statut se met à jour par `/epic sync` ou `set_status`.
  C'est le dev qui tranche dans `create_mr` ; tu ne lui reposes pas la question de l'existence d'un
  ticket. MR ouverte → propose `set_status(MR ouverte)` (+ `MR`) en une validation.
- `status` du pipeline : affiche le ticket (ref et URL) avec le reste de l'état.
