### 2. Gauntlet — les scripts mesurent d'abord

`review.sh gauntlet <slug>` (ajoute `--mutation` si Thibault l'a demandé). Bash timeout 600000 : la
compilation et les tests de chaque package touché prennent plusieurs minutes. Le script lance
`pr_gauntlet.sh` avec la cible résolue à l'init et `--keep` : la branche est sortie dans un worktree
temporaire (l'arbre de travail de Thibault n'est pas touché), chaque package touché passe le profil
`pr` **en mode extend** (périmètre = diff vs la cible de la MR : la dette préexistante ne compte pas),
`dedup_candidates.json` est produit par package, et `report.md` est écrit. Le chemin du worktree est
enregistré dans l'état.

Puis **lis `report.md` en entier**. Il contient :
- les checks PR (taille, commits, lock, tests touchés) et, par package, les `[OK]` / `[WARN]` /
  `[FAIL]` ;
- quand le projet a un graphe graphify, la section `## Impact (graphify)` : les consommateurs hors
  package non touchés, l'ordre de lecture du diff, et le chemin du **graphe de la PR** (à passer en
  `--graph` à `graphify explain` / `path` / `query`) — contrat : `~/.claude/pipeline/graphify.md`.
  Une ligne `Impact : non calculé ((absent))` veut dire pas de graphe : n'en parle pas.

Le gauntlet rouge n'arrête pas la revue : ses `[FAIL]` deviendront les remarques critiques de Corentin.
Le script n'a pas pu tourner (projet sans `feature_pipeline.md`, outils absents, SDK manquant) : dis-le
à Thibault en une ligne et continue avec le diff seul, en le disant aussi au briefing.

Pas de worktree enregistré (`review.sh next` ne l'affiche pas) : relis `gauntlet.log` dans le dossier
de la revue ; sans worktree, Maëlle est sautée et Alice et Corentin lisent avec `git show
<remote>/<source>:<fichier>`.
