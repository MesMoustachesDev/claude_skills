# 0005 — Le pipeline ne s'arrête que pour attendre Thibault

Statut : acceptée (2026-11-05), amendée le 2026-11-05 (rapport d'agent), amendée le 2026-11-05 (attente bloquante, /fix), amendée le 2026-11-06 (watchdog de /fix), amendée le 2026-11-13 (prompt court, période), amendée le 2026-11-19 (`say` devient `ask`), amendée le 2026-11-19 (`after` de /fix en Python), amendée le 2026-11-20 (consignes communes dans `pipeline/conduite.md`)
Où elle vit : `scripts/pipeline.sh watchdog` (verdict, `pipeline/pipeline.py` → `watchdog_verdict`) ·
`scripts/watchdog.sh` (veille hors session, LaunchAgent `com.claude.feature-watchdog`) ·
`pipeline/feature/steps/00_preconditions.md` (« Watchdog » : `CronCreate`, `register`) ·
`pipeline/conduite.md`, lu par `commands/feature.md` et `commands/fix.md` (« Un tour ne finit que sur une question… », « Au rapport d'un agent », « Watchdog ») ·
`scripts/fix/fix.py after` (alias `fix_gauntlet.sh after`) · `pipeline.py` → `wait_hooks`, `wait_agents` · `scripts/fix_gauntlet.sh watchdog`
(`scripts/fix/watchdog.py`, étape et attente : `scripts/fix/steps.py`) · `pipeline/fix/steps/0_preconditions.md` (« Watchdog ») · `feature_pipeline.md` →
`watchdog.minutes`, `watchdog.renotify_minutes`

## Contexte

Sur `import_cancel_sync`, `red` a été joint le 4 novembre à 21 h 54 et rien n'a été lancé ensuite :
3b a démarré le lendemain à 9 h, à la main. Aucune question n'attendait Thibault. La règle « jamais de
tour qui finit sur j'attends » n'était qu'une consigne d'agent : l'orchestrateur l'a oubliée, et
personne ne l'a vu.

## Décision

- Un script dit si une feature est bloquée (`pipeline.sh watchdog`) : `working` (un gate ou un
  sous-agent tourne), `idle`, `stalled` (rien ne tourne, aucune question posée, plus de
  `watchdog.minutes` sans activité), `waiting_thibault` (`waiting`, permission en attente,
  étape `FAILED`), `done`.
- Dans la session, un `CronCreate` lance `/feature <nom> watchdog` : sur `stalled`, l'orchestrateur
  reprend la boucle seul, parce que la suite ne dépend pas de Thibault ; sur `waiting_thibault` au-delà
  du délai, il le notifie de ce qui est attendu.
- Hors session, `watchdog.sh scan` (toutes les 15 min) notifie même quand la session est fermée ou
  bloquée sur une permission. Il ne relance rien : il n'a pas de session à relancer.
- Un tour qui finit sur une question à Thibault pose `pipeline.sh ask` : c'est ce qui distingue
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
- Amendement 3 (2026-11-06) : **le watchdog suit aussi `/fix`**. L'attente bloquante ne couvre que
  l'oubli au rapport d'un agent ; un orchestrateur `/fix` qui s'arrête ailleurs n'était rattrapé par
  personne. `fix_gauntlet.sh watchdog <nom>` rend les mêmes verdicts sur `.claude/fixes/<nom>/`
  (étape de `fix/steps.py → steps`, attente de `waiting`, `done` = `stages.evidence`
  `PASSED`), avec les mêmes seuils et les helpers de `pipeline.py`. `/fix` pose à l'étape 0 le même
  `CronCreate` (`/fix <nom> watchdog`) et `watchdog.sh register <wt> <nom> --fix` ; la liste suivie
  prend une 3e colonne `feature|fix` (sans elle : feature). `ask` du fix note `waiting_at`.
- Amendement 4 (2026-11-13) : **le cron envoie un prompt court, pas la commande slash, et toutes les
  1,5 × `watchdog.minutes`**. Mesuré sur les runs du 5 au 13 nov. :
  - `/feature <nom> watchdog` recopie tout `commands/feature.md` (27 Ko, environ 7k tokens) à chaque
    réveil, et la copie reste dans la conversation : 120k à 150k tokens par feature (`library_read`,
    `library_write`, `revenuecat_customer_attributes`), autant pour un long `/fix` ;
  - les sessions qui reçoivent ces réveils ne sont plus compactées à la reprise : avant, 4 à 6
    compactions par feature tenaient l'orchestrateur autour de 250k tokens ; après, aucune ou une seule
    au-delà de 550k, contexte moyen 460k, pointes à 800k–960k. Le coût de l'orchestrateur est passé de 34 % à 44 % du total ;
  - sur 200 réveils, environ 9 % rendaient `stalled`, environ 70 % `idle` : un cron au rythme de
    `watchdog.minutes` arrive presque toujours avant que le blocage soit possible.
  Le prompt court (texte dans `00_preconditions.md` et `commands/fix.md`, étape 0) dit seulement
  quoi lancer et quoi faire de chaque verdict ; l'orchestrateur relit la commande s'il ne l'a plus en
  tête. `/feature <nom> watchdog` et `/fix <nom> watchdog` restent pour un appel à la main. Un cron à
  l'ancien format est remplacé à la reprise. Le lien entre réveils et absence de compaction est une
  corrélation (les 6 sessions de features réveillées ; celles sans réveil compactaient encore), pas un mécanisme prouvé : à remesurer sur les
  prochaines features.
- Amendement 5 (2026-11-19) : **le cockpit est retiré (0004), `say` devient `ask`**. `pipeline.sh ask
  <nom> "<question>"` et `fix/steps.py ask <nom> "<question>"` écrivent `waiting` et `waiting_at` à la
  racine de `pipeline.json` et `fix.json` (avant : `cockpit.waiting`, `cockpit.at`). `pipeline.sh gate`
  l'efface ; sinon `ask <nom> ""`. Le watchdog n'a jamais lu que ces deux valeurs : son verdict ne
  change pas. Les mods pipeline-view et pipeline-band lisent la même clé `waiting`.
- Amendement 6 (2026-11-19) : **une seule attente bloquante pour /feature et /fix**. `fix_after`, réécriture en
  shell de `wait_hooks` et `wait_agents` (`fix_gauntlet.sh`), disparaît : `fix/fix.py after <nom> <profil>`
  appelle ces deux fonctions de `pipeline.py` sur `fix.json`, avec les mêmes constantes (30 s pour voir le hook
  démarrer, `stages.<profil>.at` récent de 120 s, budget de 540 s, exit 4 au-delà). Les réglages de test passent
  par `PIPELINE_AFTER_WAIT` et `PIPELINE_WAIT_MAX` (avant : `FIX_AFTER_WAIT`, `FIX_WAIT_MAX`).
  `fix_gauntlet.sh after <profil> <nom>` reste un alias, pour un /fix repris avec l'ancien `fix.md` en tête.
  `fix/fix.py ask` est le `ask` du fix dans `commands/fix.md` ; `fix/steps.py ask`, même fonction, reste pour
  les appels existants.
- Amendement 7 (2026-11-20) : **rien ne change sur le fond, les consignes changent de fichier.** « Un tour
  ne finit que sur une question… », « Au rapport d'un agent », le tableau des verdicts du watchdog et la règle
  `ask`, écrits deux fois (`commands/feature.md`, `commands/fix.md`), sont dans `pipeline/conduite.md`, lu
  par les deux orchestrateurs ; ce qui diffère (commande d'attente, verdict `done`) y est marqué /feature ou
  /fix. `commands/fix.md` est découpé en étapes (`pipeline/fix/steps/`) : la pose du cron de /fix est dans
  `0_preconditions.md`. Le prompt court du cron ne change pas : « Détail : fix.md, « Watchdog » » mène à un
  renvoi vers `conduite.md`, comme celui de /feature.

## Conséquences

- Un oubli de l'orchestrateur coûte au plus `watchdog.minutes` plus une période du cron
  (1,5 × `watchdog.minutes`, 30 min par défaut), au lieu d'une nuit.
- Une question posée sans `ask` est prise pour un blocage : la session relance la boucle au lieu
  d'attendre. La consigne existe pour que ça n'arrive pas.
- Le cron de session expire au bout de 7 jours et disparaît avec la session : il se recrée à chaque
  reprise.
- Pendant l'attente bloquante, la session est occupée : un message de Thibault attend la fin de l'appel
  (540 s au plus). Un agent qui ne s'arrête jamais coûte une relance de la commande toutes les 9 min,
  pas une nuit.

## Hors champ

- Le watchdog ne répond jamais à la place de Thibault, ne valide aucun point d'étape et ne rejoue
  pas une étape `FAILED` (0003) : il le notifie.
- Le watchdog ne suit pas `/reviewPR`.
