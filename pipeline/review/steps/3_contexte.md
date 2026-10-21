### 3. Le pourquoi avant le comment → `context.md`

Un diff dit ce qui change, jamais pourquoi. Les trois agents partent de ce que tu écris ici : sans le
pourquoi, leurs remarques ne sont pas vérifiables, et Maëlle ne sait pas quoi tester.

Écris `<dossier de la revue>/context.md`, court (une page), à partir de :

**a. L'intention déclarée** — titre, auteur, labels et description de la MR sont dans `review.json`
(résolus à l'init). Cherche dans la description **et dans le nom de branche** une référence de ticket
(JIRA, issue, `#123`) ; si un outil permet de l'ouvrir, ouvre-la. Description vide : écris-le, c'est en
soi une remarque.

**b. L'intention réelle** — `git -C <worktree> log --stat <merge-base>..HEAD` : les commits racontent
souvent mieux que la description.

**c. Ce qui existait déjà vs ce que la MR crée vraiment.** Pour chaque symbole nouveau qui compte
(entity, modèle, clé l10n, constante, provider, route), vérifie s'il existait **sur la cible** :
`git grep -n "<Symbole>" <remote>/<cible> -- '<glob>'` puis la même chose sur la source. Avec un graphe,
`graphify explain "<Symbole>" --graph <graphe de la PR>` oriente, le `git grep` fait foi. Ça change
tout au verdict : un champ figé est une étourderie si le modèle expose déjà la donnée, une contrainte
backend sinon.

**d. Le voisin de référence.** La MR ajoute-t-elle un n-ième cas à un pattern existant ? Ouvre le cas
le plus proche déjà en place et lis-le en entier : c'est l'étalon d'Alice et de Corentin. Avec un graphe,
`graphify path "<A>" "<B>" --graph <graphe de la PR>`.

**e. Les règles** — note les chemins qui existent : `.claude/rules/pr_rules.md`,
`.claude/rules/create_feature_rules.md`, `CLAUDE.md` du projet.

`context.md` contient, dans cet ordre et avec exactement ces titres (le cockpit les affiche en tête
de la revue, sous « La MR ») :

```
## Pourquoi                      le besoin, l'objectif de la MR, le ticket — ou « description vide »
## Ce que fait le code           le résumé : 3 à 5 lignes, ce que le code fait vraiment
## Existait déjà / ajouté par la MR
## Voisin de référence           le fichier, et pourquoi c'est lui
## Ce que la MR promet de visible   ce que Maëlle doit pouvoir constater, ou « rien de visible »
## Règles                        les chemins qui existent
```

Aucun verdict.

Puis `review.sh pass <slug> context`.
