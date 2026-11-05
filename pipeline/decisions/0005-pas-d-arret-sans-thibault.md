# 0005 — Le pipeline ne s'arrête que pour attendre Thibault

Statut : acceptée (2026-11-05), amendée le 2026-11-05 (rapport d'agent), amendée le 2026-11-05 (attente bloquante, /fix)
Où elle vit : `scripts/pipeline.sh watchdog` (verdict, `pipeline/pipeline.py` → `watchdog_verdict`) ·
`scripts/watchdog.sh` (veille hors session, LaunchAgent `com.claude.feature-watchdog`) ·
`pipeline/feature/steps/00_preconditions.md` (« Watchdog » : `CronCreate`, `register`) ·
`commands/feature.md` et `commands/fix.md` (« Un tour ne finit que sur une question… », « Au rapport d'un agent ») ·
`scripts/fix_gauntlet.sh after` · `pipeline.py` → `wait_agents` · `feature_pipeline.md` →
`watchdog.minutes`, `watchdog.renotify_minutes`

## Contexte

Sur `import_cancel_sync`, `red` a été joint le 4 novembre à 21 h 54 et rien n'a été lancé ensuite :
3b a démarré le lendemain à 9 h, à la main. Aucune question n'attendait Thibault. La règle « jamais de
tour qui finit sur j'attends » n'était qu'une consigne d'agent : l'orchestrateur l'a oubliée, et
personne ne l'a vu.

## Décision

- Un script dit si une feature est bloquée (`pipeline.sh watchdog`) : `working` (un gate ou un
  sous-agent tourne), `idle`, `stalled` (rien ne tourne, aucune question posée, plus de
  `watchdog.minutes` sans activité), `waiting_thibault` (`cockpit.waiting`, permission en attente,
  étape `FAILED`), `done`.
- Dans la session, un `CronCreate` lance `/feature <nom> watchdog` : sur `stalled`, l'orchestrateur
  reprend la boucle seul, parce que la suite ne dépend pas de Thibault ; sur `waiting_thibault` au-delà
  du délai, il le notifie de ce qui est attendu.
- Hors session, `watchdog.sh scan` (toutes les 15 min) notifie même quand la session est fermée ou
  bloquée sur une permission. Il ne relance rien : il n'a pas de session à relancer.
- Un tour qui finit sur une question à Thibault pose `pipeline.sh say` : c'est ce qui distingue
  « on l'attend » de « bloqué ».
- Amendement, même jour : au rapport (hand-back) d'un agent, l'orchestrateur agit dans le même tour
  avec `pipeline.sh next --after <profil>`, qui attend que le hook de ce gate démarre puis finisse.
  Il ne finit plus de tour sur « j'attends le hook ou la notification ». Sur `import_cancel_sync`,
  la notification de fin n'arrivait qu'avec le message suivant de Thibault : quatre relances à la main.
- Amendement 2 : **un tour d'orchestrateur ne finit que sur une question à Thibault ou sur la fin**,
  jamais sur une attente d'agent, de hook ou de notification. Deux trous restaient :
  - gate rouge : `next --after` disait « fin de tour permise, son prochain rapport rappellera » ; c'est
    ce rapport qui ne relance pas toujours de tour. `next --after` et `join --after` attendent
    maintenant, bloqués, que l'agent renvoyé au travail ait un nouveau verdict (`wait_agents`) ;
    `join` attend aussi l'autre moitié ;
  - `/fix` n'avait que la consigne « attends la notification » : gate green de Fanny passé,
    l'orchestrateur a écrit « j'attends », Victor n'a été lancé qu'au retour de Thibault.
    `fix_gauntlet.sh after <profil> <nom>` fait pour `/fix` ce que `next --after` fait pour `/feature`.
  Un appel est borné à 540 s (il tient dans un appel Bash de 600 s) ; au-delà, exit 4 et
  l'orchestrateur relance la même commande, dans le même tour.

## Conséquences

- Un oubli de l'orchestrateur coûte au plus `watchdog.minutes`, plus le décalage du cron (jusqu'à 50 %
  de la période), au lieu d'une nuit.
- Une question posée sans `say` est prise pour un blocage : la session relance la boucle au lieu
  d'attendre. La consigne existe pour que ça n'arrive pas.
- Le cron de session expire au bout de 7 jours et disparaît avec la session : il se recrée à chaque
  reprise.
- Pendant l'attente bloquante, la session est occupée : un message de Thibault attend la fin de l'appel
  (540 s au plus). Un agent qui ne s'arrête jamais coûte une relance de la commande toutes les 9 min,
  pas une nuit.

## Hors champ

- Le watchdog ne répond jamais à la place de Thibault, ne valide aucun point d'étape et ne rejoue
  pas une étape `FAILED` (0003) : il le notifie.
- Le watchdog ne suit pas `/fix` ni `/reviewPR` : pour `/fix`, seule l'attente bloquante dans le tour
  (amendement 2) empêche l'arrêt ; un oubli de l'orchestrateur n'y est rattrapé par personne.
