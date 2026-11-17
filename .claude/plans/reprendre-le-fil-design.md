# Encart « Reprendre le fil » — pipeline-view, /feature

## Intention

Thibault mène souvent plusieurs features `/feature` en parallèle, une par session. En revenant sur
une session, il perd du temps à se remettre en tête où en est la feature et ce qui a été tranché.
L'encart le lui rend en un coup d'œil (une dizaine de secondes de lecture), en haut du panneau
pipeline-view : un pense-bête, pas un document de plus.

## Objectifs

- Dire, pour la feature de la session ouverte : son but, l'étape courante, ce qui attend Thibault,
  ce qui a bougé depuis son dernier passage, les décisions structurantes, ce qui reste ouvert, ce
  qui a été sorti du périmètre.
- Tenir en une dizaine de lignes, une ligne par élément.

## Non-objectifs

- Une vue de toutes les features en cours : pipeline-view ne montre que la session ouverte.
- Remplacer l'encart « à lire », `discussion.md` ou le cockpit : l'encart y renvoie, il ne les recopie pas.
- `/fix` : hors de cette version (voir « Laissé au constructeur » pour la marge).

## Anti-objectifs

- Un encart qu'il faut lire : s'il dépasse l'écran ou reprend des puces de trois lignes, il a raté.
- Un résumé qui ment : une étape ou une attente fausse est pire que rien. Les lignes factuelles ne
  sont jamais écrites par un modèle.
- Un texte de modèle écrit tel quel dans `pipeline.json` sans validation.

## Maquette

```
┌ Reprendre le fil · message_attachment ─────────── vu il y a 2 j ┐
│ But       Joindre une pièce à un message                        │
│ Étape     revue des tests (Gaëlle) · 7/15                       │
│ T'attend  valider la revue des tests                            │
│ Depuis    tests (rouge) ✓ (Théo) · revue tests ✗ (Gaëlle)       │
│ Décidé    • une pièce par message                               │
│           • une erreur réseau garde le brouillon                │
│           • ancien bouton d'envoi supprimé                      │
│ Ouvert    • taille maximale d'une pièce ?                       │
│ À côté    bug d'aperçu → /fix séparé                            │
└─────────────────────────────────────────────────────────────────┘
```

Placé en tête du panneau, au-dessus des étapes. Une ligne vide est omise (pas de « Ouvert » s'il n'y
a rien d'ouvert).

## Approches considérées

- **A. Extraction seule par le mod** : il lit `pipeline.json` et `discussion.md` (`## Décisions`,
  `## Questions ouvertes` moins les `RÉSOLU`). Rien à changer dans `/feature`, toujours à jour. Mais
  les puces de `discussion.md` font deux ou trois lignes, ne sont pas triées, et il n'y a pas de
  « But » : il faudrait couper à l'aveugle.
- **B. Mixte — retenue par Thibault.** Le factuel est calculé par le mod, le jugement est écrit par
  l'orchestrateur à chaque point d'étape, dans des champs bornés validés par un script.
  Succinct et trié ; coûte un changement de `feature.md` et de `pipeline.py`, et le résumé peut
  avoir un point d'étape de retard.
- **C. Le mod appelle un modèle à l'ouverture** : écartée (lent, payant, sortie non garantie).

## Conception (approche B)

### Lignes factuelles — calculées par le mod, jamais écrites par un modèle

- **Étape** : l'étape courante (celle que l'encart « à lire » utilise déjà via `pipeline.sh next
  --json`), son libellé et qui la tient (`stageOwner`), et sa position dans les étapes non sautées.
- **T'attend** : `cockpit.waiting` de `pipeline.json`, s'il est posé ; sinon la ligne est omise.
- **Depuis** : les étapes dont `stages.<clé>.at` est postérieur au dernier passage de Thibault,
  avec leur statut (`✓`, `✗`) et qui les tient. Au plus 3, les plus récentes.
  *Dernier passage* est **lié à la feature, pas à la session** (choix de Claude) : une feature reprise
  dans une nouvelle session, après un `/clear` ou un redémarrage de l'app, garde son « Depuis ». Il
  est écrit sur disque hors du repo (par exemple à côté de `~/.claude/activity`, une entrée par
  repo + feature), pas dans l'état mémoire du mod. Le « vu il y a… » du titre vient de là.
  Aucun passage connu (sous-feature d'`/epic`, première ouverture) : « Depuis » montre les 3
  dernières étapes écrites et le titre n'affiche pas « vu il y a » (choix de Claude).
  *Ce qui compte comme un passage* (décidé par Thibault) : un message qu'il tape, sa réponse à un
  `AskUserQuestion`, une permission qu'il accorde. Ne comptent pas : les réveils du watchdog
  (`CronCreate`), les messages d'une autre session (`/epic`, `SendMessage`), les notifications de fin
  d'agent, l'ouverture du panneau. Côté technique, `origin.kind` de `PromptSubmitInput` fait le tri :
  `composer`, `bridge` et `human` (message tapé dans l'app desktop, relevé dans les transcripts) comptent,
  `sdk`, `peer`, `task-notification` et le reste non ; `isMeta` exclut aussi.

### Lignes de jugement — écrites par l'orchestrateur, validées par un script

Nouvelle clé `recap` dans `pipeline.json`, écrite **uniquement** par une nouvelle commande :

```
pipeline.sh recap <nom> <fichier.json>
```

Schéma (tout autre champ ou type est refusé, exit non nul, `pipeline.json` inchangé) :

| Champ     | Type             | Bornes                              |
|-----------|------------------|-------------------------------------|
| `goal`    | chaîne           | 1 à 80 caractères, une ligne        |
| `decided` | liste de chaînes | 0 à 5 éléments, ≤ 80 car. chacun    |
| `open`    | liste de chaînes | 0 à 3 éléments, ≤ 80 car. chacun    |
| `aside`   | liste de chaînes | 0 à 3 éléments, ≤ 80 car. chacun    |

`pipeline.sh set recap …` est refusé : `recap` ne s'écrit que par cette commande, sinon la
validation se contourne (choix de Claude).

La commande ajoute elle-même `at` (horodatage) et `stage` (l'étape courante au moment de
l'écriture). Le mod affiche « résumé de l'étape <x> » en discret quand `stage` diffère de l'étape
courante, pour qu'un résumé en retard se voie.

**Quand l'orchestrateur l'écrit** : à chaque point d'étape, juste avant
`pipeline.sh say … --report <étape>` (règle 4 de `commands/feature.md`), et à la fin du cadrage
(0b). Il condense `discussion.md` et le cadrage : les 5 décisions les plus structurantes, pas tout
le journal. Écrire le résumé ne pose aucune question à Thibault.

### Repli sans `recap` (features anciennes, ou avant le premier point d'étape)

Le mod extrait de `discussion.md` (approche A) : premières puces de `## Décisions` et questions non
`RÉSOLU`, chacune coupée à 80 caractères avec « … », au plus 5 et 3. Pas de ligne « But ». Le titre
de l'encart signale « extrait de discussion.md ».

## Contraintes

- Le checkout principal de `~/.claude` est en lecture seule (ADR 0007) : tout passe par
  `scripts/claude_change.sh start <nom>` puis `land` dans le même tour.
- Toute écriture de `pipeline.json` passe par `pipeline.sh` (règle 3 de `commands/feature.md`).
- Changement de mod : monter la version de `mods/pipeline-view/.claude-plugin/plugin.json`
  (0.15.0 → 0.16.0), mettre à jour sa description, puis `claude plugin marketplace update
  thibault-mods` et `claude plugin update pipeline-view@thibault-mods`.
- Aucun nom de client ou de projet dans `~/.claude` : la maquette ci-dessus ne va pas dans le repo
  telle quelle (exemple neutre dans les tests et la doc).
- Pas de nouvelle ADR prévue : on ajoute une écriture au point d'étape sans changer une règle de
  fond. Le constructeur relit ADR 0005 (pas d'arrêt sans Thibault) pour s'assurer que l'écriture
  du résumé n'introduit aucun arrêt.

## Laissé au constructeur

- Le rendu exact (couleurs, `dimColor`, troncature à la largeur du panneau) dans le style de
  `register.tsx`.
- Où vit le calcul de « Depuis » et du repli (un nouveau `hooks/recap.ts`, à côté de `pending.ts`,
  semble naturel) et ses tests dans `tests/pipeline-view.test.tsx`.
- Comment le mod récupère l'heure du dernier message de Thibault (hook de soumission de message ou
  donnée déjà publiée par `activity.ts`).
- Le libellé de la position (« 7/15 ») si une étape est sautée ou inconnue, et la place des
  sous-étapes (`hg.*`, `contracts_draft`…) dans ce décompte.
- Éviter que « T'attend » s'affiche deux fois avec le « À toi » de l'encart « à lire ».
- Étendre plus tard à `/fix` (mêmes lignes factuelles, `recap` écrit au point de diagnostic) : hors
  de cette version.
