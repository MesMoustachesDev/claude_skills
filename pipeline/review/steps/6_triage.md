### 6. Tri des remarques par Thibault

Le tri se fait dans la session, en `AskUserQuestion`, **par paquets de 4 remarques au plus, critiques
d'abord** (puis suggestions, questions, « à vérifier »). Une question par remarque, avec deux options :
« Commenter (Recommandé) » / « Écarter ». Chaque question se suffit à elle-même (il répond souvent depuis
Remote Control, où il ne voit qu'elle) : `fichier:ligne`, l'agent et la gravité, le problème en une
phrase, l'extrait de code (le `snippet` de `findings.json`, réduit aux lignes utiles), puis le
**commentaire proposé** tel qu'il partirait. Une remarque dont tu doutes de la preuve (étape 5) :
dis-le dans sa question. Une remarque `to_verify` : dis qu'elle n'est pas prouvée et qu'elle ne sera
pas postée telle quelle.

Une réponse « Other » de Thibault vaut **nouveau texte du commentaire** (la remarque est donc
commentée, avec ce texte). Si elle ressemble plutôt à une consigne (« plus court », « en question »)
ou à une question, ce n'est pas un texte : réécris le commentaire selon la consigne et repose la
question pour cette remarque, ou réponds-lui.

**Chaque paquet s'enregistre aussitôt**, par `review.sh` et jamais à la main :
- les choix sans texte : `review.sh triage <slug> F1=comment F2=skip F4=comment` (le commentaire
  proposé est gardé) ;
- un texte donné par Thibault : `review.sh triage <slug> F3 comment "<son texte>"`.

Le script refuse un id inconnu ou une décision autre que `comment` / `skip` (rien n'est enregistré) ;
il réécrit `comments.md` et imprime ce qui reste **NON TRIÉ** : c'est le paquet suivant. Rien ne part :
le tri est un filtre.

Avant le premier paquet, un seul `AskUserQuestion` : « Trions maintenant » / « Discuter — je veux
comprendre une remarque avant de trier ». **Discuter** → explique la remarque (le code, la preuve, ce
que chaque choix change), réponds, puis repose la même question. Une remarque déjà triée ne se
redemande pas, sauf si Thibault veut revenir dessus.

Le tri n'est **pas** une validation de ce qui sera posté : c'est l'étape 7.

`pr_rules.md` impose son propre workflow de triage : il remplace celui-ci, l'enregistrement passe
toujours par `review.sh triage`. Fin : `review.sh triage` passe l'étape quand toutes les remarques sont
triées.
