# Règles de Thibault, pour toutes les sessions

## Plans de travail (`.claude/plans/*.md`)

Un plan découpé en points numérotés vit dans `.claude/plans/<nom>.md`, sur le checkout principal du
repo. Le panneau Pipeline (mod pipeline-view) le lit et montre l'état de chaque point. Pour qu'il sache
où en est un point :

- **Dès qu'un point est pris**, par toi ou par une session que tu lances, ajoute sous ce point une ligne
  `→ \`<branche>\``. C'est la branche qui porte le travail : celle du `/feature` ou du `/fix` s'il en
  crée une (`feature/<nom>`, `fix/<nom>`), sinon celle du worktree de la session. Plusieurs branches :
  `→ \`a\`, \`b\``. Écris dans le fichier du checkout principal, pas dans une copie d'un worktree.
- **Un point livré** (mergé, ou réglé sans code) : ajoute `[fait]` à sa première ligne.
- Un point qui attend Thibault garde `[toi]` ; le panneau le montre comme une décision à prendre.
