# 0005 — Le pipeline ne s'arrête que pour attendre Thibault

Statut : acceptée (2026-11-05)
Où elle vit : `scripts/pipeline.sh watchdog` (verdict, `pipeline/pipeline.py` → `watchdog_verdict`) ·
`scripts/watchdog.sh` (veille hors session, LaunchAgent `com.claude.feature-watchdog`) ·
`pipeline/feature/steps/00_preconditions.md` (« Watchdog » : `CronCreate`, `register`) ·
`commands/feature.md` (« Watchdog », « Jamais de tour qui finit sur j'attends ») · `feature_pipeline.md` →
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

## Conséquences

- Un oubli de l'orchestrateur coûte au plus `watchdog.minutes`, plus le décalage du cron (jusqu'à 50 %
  de la période), au lieu d'une nuit.
- Une question posée sans `say` est prise pour un blocage : la session relance la boucle au lieu
  d'attendre. La consigne existe pour que ça n'arrive pas.
- Le cron de session expire au bout de 7 jours et disparaît avec la session : il se recrée à chaque
  reprise.

## Hors champ

- Le watchdog ne répond jamais à la place de Thibault, ne valide aucun point d'étape et ne rejoue
  pas une étape `FAILED` (0003) : il le notifie.
- `/fix` et `/reviewPR` ne sont pas suivis.
