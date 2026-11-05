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

## Sessions lancées par une autre session

Quand tu lances ou pilotes d'autres sessions (`start_session`, `SendMessage`, sous-features d'un epic) :

- **Jamais deux sessions qui écrivent dans le même dossier.** Avant `use_worktree: false`, regarde
  `~/.claude/activity/*.json` (publié par le mod pipeline-view) : une session `working` ou `waiting`
  dans ce dossier depuis moins de 30 min → worktree à part, ou attendre. Le mod arrête aussi la
  reprise d'un `/feature` ou d'un `/fix` déjà en cours ailleurs.
- **Tu ne réponds jamais à une permission à la place de Thibault**, ni à une question qu'une session
  enfant lui pose : tu la lui relaies, avec le nom de la session.
- **Tu n'écris pas à une session qui attend Thibault** : ton message pourrait passer pour sa réponse.
- **Pas de troisième niveau** : une session que tu lances n'en lance pas d'autres.
- **Pas de sondage** : tu attends la note de fin de tour de la session, ou un réveil programmé.
- **Changer d'agent ou de modèle en cours de route** (relancer une étape sur Opus, reprendre le travail
  d'une session dans une autre) : vérifie d'abord tout ce qui peut échouer (modèle disponible, dossier,
  branche, résumé à transmettre), puis seulement arrête l'ancienne, et montre à Thibault le résumé
  passé à la nouvelle avant de l'envoyer.

## Écrire d'après une réponse de modèle

Quand une routine, un script ou un skill écrit quelque chose (Notion, n8n, config, règle, fichier) à
partir de ce qu'un modèle a répondu : **le modèle traduit, le script décide.** Sa réponse est une
donnée, décodée strictement (JSON attendu, champs connus, valeurs bornées), refusée si elle ne passe
pas, jamais exécutée telle quelle. Avant d'écrire : la dire en mots à Thibault, et l'essayer à blanc
quand c'est possible (ce qu'elle changerait, sur quoi). C'est ce que font déjà `verifier.py`
d'`ecrire-linkedin` et la liste fermée des écritures de `mission-linkedin`.

## Décisions du pipeline (`~/.claude/pipeline/decisions/`)

Les règles de fond de `/feature`, `/fix`, du gauntlet et des agents ont chacune une ADR. Avant de
changer l'une de ces règles, lis son ADR. Un changement qui revient dessus met l'ADR à jour dans le
même commit : statut amendé, ou une nouvelle ADR qui la remplace.

## Changer le pipeline (`~/.claude`)

Le checkout principal de `~/.claude` est lu par toutes les sessions : on n'y écrit pas directement, le
hook `claude-home-guard.sh` le refuse (ADR 0007). Une règle d'une ligne : `scripts/rule_add.py`, qui la
commite aussitôt. Tout autre changement : `scripts/claude_change.sh start <nom>`, travail et commits dans
`~/.claude-wt/<nom>`, puis `claude_change.sh land <nom>` dans le même tour.
