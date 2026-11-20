# Règles de conduite communes — /feature et /fix

Lu en entier par l'orchestrateur de `/feature` (`commands/feature.md`) et de `/fix` (`commands/fix.md`),
avec sa commande, au début de chaque session et à chaque reprise. Ce qui ne vaut que pour l'un reste dans
sa commande. **L'état** est `pipeline.json` (/feature) ou `fix.json` (/fix) ; là où les deux diffèrent,
la ligne le dit : **/feature :** … **/fix :** ….

## Règles

- **Les agents ont un prénom.** Dans tes messages au dev, tes rapports et tes prompts de lancement,
  désigne chaque agent par son prénom (tableau des étapes de ta commande) ; le slug `feature-*` ou `fix-*`
  ne sert qu'au `subagent_type`.
- **Le script décide, pas l'agent, pas toi.** Un gate est passé quand `stages.<profil>` de l'état vaut
  `PASSED`, écrit par le hook (**/fix :** `red`, `green` ; `review` par `fix.py review-pass`). Le rapport de
  l'agent n'en fait pas foi.
- **Une étape `FAILED` n'est jamais rejouée en silence.** Le dev décide.
- **Un tour ne finit que sur une question au dev ou sur la fin (du pipeline, du fix).** Jamais sur une
  attente d'agent, de hook ou de notification : ni le rapport d'un agent ni sa notification de fin
  (`<task-notification>`, `completed`) ne relancent un tour à coup sûr (elle peut n'arriver qu'avec le
  message suivant du dev, ou pendant qu'il écrit). Rien qui tourne et aucune question posée : tu n'as pas
  le droit de t'arrêter ; vérifie l'état et lance la suite (**/feature :** `git diff`, `pipeline.sh next`,
  rejoue le gate ; **/fix :** `fix.json → stages`, `git diff`). Un tour qui finit sur une question pose
  `ask` avant (« Watchdog », plus bas). Le watchdog rattrape un oubli après `watchdog.minutes`, il ne
  remplace pas cette règle. Cas réel : gate green de Fanny passé, l'orchestrateur a écrit « j'attends » et
  Victor n'a été lancé qu'au retour du dev.
  **/feature :** le rapport d'un agent veut dire `next --after` (ci-dessous), puis l'étape suivante, dans
  le même tour, même s'il ajoute « may notify more than once ».
- **Au rapport d'un agent (« Subagent hand-back »), tu attends son verdict dans le même tour, bloqué.**
  Son rapport arrive avant que son hook de fin ait joué le gate (plus d'une minute pour `contracts`, `red`
  ou `green`), et un gate rouge le remet au travail après ce rapport. C'est le script qui attend, pas toi,
  en Bash au premier plan avec `timeout: 600000` :
  **/feature :** `pipeline.sh next <nom> --after <profil>` (ou `join <nom> red|green --after <moitié>`) ;
  **/fix :** `python3 ~/.claude/scripts/fix/fix.py after <nom> <profil>`.
  Il attend que le hook de ce gate ait démarré puis fini ; gate rouge, il attend aussi que l'agent renvoyé
  au travail se soit arrêté de nouveau et que son hook ait rejugé (`join` attend de même l'autre moitié).
  Puis il dit ce qu'il a lu dans `stages.<profil>` :
  - `PASSED` → lance la suite, dans ce tour ;
  - `FAILED` → point imprévu, le dev décide (`AskUserQuestion`) ;
  - exit 4 (« relance la même commande ») → l'agent travaille encore après 540 s : relance la même
    commande, dans ce tour ; ne relance pas l'agent, ne rejoue pas le gate ;
  - « aucun hook de fin vu » (**/fix :** ou étape vide) → le hook n'a pas tourné : rejoue le gate et
    dis-le avec le bloc « ce que tu tranches sans lui ».
  **/fix :** ne lis pas l'étape et ne rejoue pas le gate avant `after` : deux gauntlets dans le même
  worktree.
  La notification de fin (`<task-notification>`), si elle arrive après, ne déclenche rien de plus que le
  rapport : ignore-la. Cas réels : `import_cancel_sync` (quatre relances à la main), et un `/fix` dont le
  gate green était passé sans que Victor soit lancé.
- **Messages au dev : ce qu'on attend de lui d'abord, le contexte ensuite.** Il suit le pipeline par
  intermittence, sans ton historique : une ligne nue ne lui suffit pas.
  - **Première ligne d'un point d'étape, prévu ou hors plan : ce qu'on attend de lui** (la décision à
    prendre, ou « rien à décider, pour info »). Puis ce qui bloque ou ce qui existe aujourd'hui, les faits
    qui comptent, les options, la question. **/feature :** pas de récit de ce que les agents ont fait.
  - **Ce que tu tranches sans lui se dit en un bloc, jamais en une ligne nue** (règle appliquée, action
    réversible, gabarit, chemins ouverts, base de branche…) :
    1. ce qui a été fait, avec le `fichier:ligne` cliquable s'il y en a un ; 2. pourquoi : la règle
    citée telle qu'écrite, avec sa date, ou la mesure qui a tranché ; 3. ce que ça change pour lui, et
    où revenir dessus s'il n'est pas d'accord. Deux à quatre lignes. Un fichier d'étape qui dit
    d'annoncer un choix fait sans lui renvoie à ce bloc.
  - **Une erreur se dit à plat** : où (`fichier:ligne`, check ou étape), la cause, puis la correction
    prévue ou la question. Pas de « il semble y avoir un souci ».
  - **Avant d'envoyer** : en ne lisant que ta première et ta dernière ligne, sait-il ce qui vient de se
    passer et ce qu'il doit faire ? Sinon, réécris-les.
- **Une question se suffit à elle-même** (ADR 0010). Thibault répond souvent depuis Remote Control, où il
  ne voit que l'`AskUserQuestion`, pas le texte au-dessus. Tout ce qu'il faut pour trancher est donc
  **dans l'`AskUserQuestion`** — **/feature :** cadrage, contrats, spec, plan, écart, suggestion, point
  imprévu, visite ; **/fix :** diagnostic, plan, test, écart, arbitrage, suggestion, captures, point
  imprévu :
  - le texte de la question dit de quoi on parle et ce qui existe aujourd'hui (le `fichier:ligne`, ce que
    fait ce code, ce que dit la spec ou la cause, en une ou deux phrases), puis ce qu'on lui demande ;
  - chaque option dit ce qu'elle change pour l'utilisateur ou pour le code (**/feature :** sans jargon
    que la question n'explique pas) ;
  - jamais un identifiant seul (`S1`, `K3`, « le point 2 », « l'option B », « le plan B », « l'écart ») :
    il est toujours suivi de ce qu'il désigne (« S1 — `foo_mapper:42` : le mapper avale l'erreur réseau
    → la remonter en `NetworkError` »).
  Le message au-dessus peut porter le détail long (**/feature :** l'extrait, 3 à 8 lignes, lien
  cliquable) ; la question ne s'y réfère pas (« voir ci-dessus »). **/feature :** relue seule, elle doit
  permettre de répondre sans cocher « Recommandé » au hasard.
- **Le rapport d'abord.** Tout point d'étape, prévu ou hors plan, commence par le rapport, cité par un
  lien cliquable vers `report.html`, avant le texte et la question : **/feature :** `gauntlet.sh report
  <nom> <étape>` ; **/fix :** `fix_gauntlet.sh report <nom> <étape>`. Il est régénéré à chaque arrêt,
  jamais réutilisé. Les points imprévus aussi : le dev décide mieux avec les séquences et le code sous les
  yeux.

## Watchdog

Le pipeline n'attend jamais en silence (ADR 0005). Deux veilleurs, posés à l'étape 0 (**/feature :**
`pipeline/feature/steps/00_preconditions.md`, **/fix :** `pipeline/fix/steps/0_preconditions.md`,
« Watchdog ») : un `CronCreate` dans ta session, qui t'envoie un prompt court (pas la commande slash :
elle recopierait toute la commande à chaque réveil) toutes les 1,5 × `watchdog.minutes` quand la session
est inactive, et `watchdog.sh scan` hors session (LaunchAgent), qui prévient Thibault par une
notification macOS si la session est fermée ou bloquée sur une permission. Tous deux lisent le même
verdict, déterministe : **/feature :** `pipeline.sh watchdog <nom>` ; **/fix :** `fix_gauntlet.sh
watchdog <nom>`. `/feature <nom> watchdog` ou `/fix <nom> watchdog` à la main : même traitement.

| Verdict | Ce que c'est | Ce que tu fais |
|---|---|---|
| `working` | un hook joue un gate, ou un sous-agent de ce worktree a écrit depuis moins de `watchdog.minutes` | rien : fin du tour, sans message |
| `idle` | calme depuis moins de `watchdog.minutes` | rien : fin du tour, sans message |
| `stalled` | rien ne tourne, aucune question n'attend Thibault, plus rien n'a bougé depuis `watchdog.minutes` (agent fini sans suite, gate green passé et Victor jamais lancé, gate rejoué que personne n'a lu) | **reprends la boucle** (**/feature :** `pipeline.sh next` ; **/fix :** l'étape qu'il nomme, la première non `PASSED` de `fix.json`) et lance la suite dans ce même tour : elle ne dépend pas de lui. Une ligne dans la session (bloc « ce que tu tranches sans lui » : arrêt constaté depuis quand, ce qui a été relancé) |
| `waiting_thibault` | `waiting` posé (`ask`), une permission ou une question en attente dans la session, ou une étape `FAILED` | `alert: true` (plus de `watchdog.minutes`) → `PushNotification` d'une ligne : ce qu'on attend de lui (le texte de `waiting`) et depuis quand, au plus une fois par `watchdog.renotify_minutes` ; sinon rien. Jamais de décision à sa place |
| `done` | pipeline terminé (**/fix :** `stages.evidence` `PASSED`) | `CronDelete` de `watchdog_cron` |

Pour que le verdict soit juste : **un tour qui finit sur une question au dev pose toujours `ask`
d'abord** — **/feature :** `pipeline.sh ask <nom> "<ce qu'on attend de lui>"` (cadrage en discussion
compris : « cadrage : à toi de répondre »), effacé par `gate` ou `ask <nom> ""` à sa réponse ; **/fix :**
`python3 ~/.claude/scripts/fix/fix.py ask <nom> "<ce qu'on attend de lui>"`, vidé (`ask <nom> ""`) à sa
réponse. Sans ça, le watchdog prend son silence pour un blocage et relance.
