# 0003 — Le gauntlet est le seul juge d'une étape

Statut : acceptée (2026-11-05, reprise du pipeline existant depuis 2026-09-25), amendée le 2026-11-10
(trous du gauntlet, plus bas), le 2026-11-17 (checks d'avertissement, plus bas), le 2026-11-19 (verrou de l'état)
et le 2026-11-19 (`fix.json` écrit par script, plus bas)
Où elle vit : `scripts/gauntlet.sh` et `scripts/gauntlet/` (profils, checks) · `hooks/pipeline-gate.sh`
(gate de fin d'agent) · `scripts/pipeline.sh` (seul à écrire `pipeline.json`, sous le verrou de
`scripts/statefile.py`, comme `gate_set` des deux gates (`gate_run` de `hooks/lib.sh`), `review.py`,
`fix/steps.py`, `state_set` de `fix/lib.sh` et `learn.py`) · `scripts/fix/fix.py` (seul à écrire `fix.json` avec `hooks/fix-gate.sh`) · `pipeline/conduite.md`
(« Le script décide, pas l'agent, pas toi »)

## Contexte

Un agent qui dit « tous les tests passent » peut se tromper : il n'a pas rejoué la suite, il a lu un
vieux log, ou il a fini sur un gate rouge. L'orchestrateur, lui, a tendance à croire le rapport.
Une étape validée sur parole laisse passer ce que personne n'a vérifié.

## Décision

- Une étape est passée quand `pipeline.json → stages.<profil>` vaut `PASSED`, écrit par le gauntlet
  lancé depuis le hook de fin de l'agent. Ni le rapport de l'agent ni l'avis de l'orchestrateur ne
  comptent.
- Chaque profil (`contracts`, `red`, `green`, `clean`, `review_verdict`, `harden`, `qa`…) est un
  ensemble de checks déterministes : compilation, analyse, suite, gel, périmètre, dépendances,
  règles d'architecture (`error_handling`), hygiène des tests, mutation.
- `pipeline.json` ne s'écrit que par `pipeline.sh`, jamais à la main.
- Ce qu'un modèle juge (Camille, Gaëlle, Denis, Romain) sort en JSON, et c'est un script
  (`*_verdict`) qui en tire le verdict.

## Conséquences

- Un agent est renvoyé au travail tant que son gate est rouge, jusqu'à 5 tentatives, puis Thibault
  tranche. Une étape `FAILED` n'est jamais rejouée en silence.
- Chaque règle importante doit être un check, sinon elle n'est pas tenue. Une règle qui n'est
  qu'une consigne d'agent est une règle faible.
- Le gauntlet a ses bugs (périmètre trop large, dette existante). Ils se corrigent dans le gauntlet,
  jamais en passant outre.

## Hors champ

- Les points d'étape de Thibault (cadrage, contrats, spec, tests, suggestions, visite) : ils jugent
  ce qu'un script ne peut pas juger, et le gauntlet ne les remplace pas.
- `accept <étape> "<raison>"` : Thibault peut accepter un verdict d'agent, avec une raison qui sort
  dans l'evidence. C'est lui qui le fait, jamais l'orchestrateur.

## Amendement du 2026-11-10 : les trous du gauntlet

Des règles d'`answers.md` laissaient l'orchestrateur accepter un gate rouge sans demander (couverture,
`stub_check`, `red_check`, `metrics`), alors que cette ADR réserve l'acceptation à Thibault. Désormais :

- une telle règle porte la mention « trou du gauntlet » et nomme un cas exact. L'orchestrateur
  l'applique citée dans l'evidence ; hors de ce cas exact, c'est une question ;
- c'est une dette du gauntlet, pas une façon de faire : elle disparaît quand un check sait reconnaître
  le cas. Une nouvelle règle de ce genre ne s'ajoute qu'avec la piste du check qui la remplacera ;
- `metrics` est le premier fermé : le check mesure la fonction à la merge-base et ne laisse passer, en
  dette signalée, que celle qui était déjà hors seuil et n'a pas empiré (`metrics_ratchet`).
  `metrics_accepted` reste pour une acceptation de Thibault.

## Amendement du 2026-11-17 : les checks d'avertissement

Une faille que la revue relève plusieurs fois mais qu'un script ne reconnaît qu'à peu près (motif de code,
pas preuve) devient un check d'avertissement : il sort en `[WARN] fichier:ligne` et rend toujours vert. Il ne
change aucun verdict ; il met le cas sous les yeux du reviewer, qui tranche. Premier du genre :
`server_fetch_redirect` (`scripts/gauntlet/checks_security.sh`, `fix_gauntlet.sh`), dans les profils `green`
de `/feature` et `/fix` : `fetch()` serveur sur une URL non constante qui suit les redirections (SSRF).
Comme tout check, il sort en `[N/A]` quand il n'a rien à lire (aucun fichier JS/TS), jamais en vert.

## Amendement du 2026-11-19 : `fix.json` écrit par script

« Seul à écrire » couvrait `pipeline.json`, pas `fix.json` : `commands/fix.md` demandait à l'orchestrateur d'écrire
l'état du fix à la main, en 19 passages (gabarit de création, `phase`, `freeze_sha`, `refreezes`, `human_gates`,
`loops.review += 1` compté par le modèle, copie de `review.json` dans `history/`), et `stages.review = PASSED`
était un verdict de gate écrit par le modèle lui-même. Désormais :

- `fix.json` ne s'écrit que par `scripts/fix/fix.py` (l'orchestrateur) et `hooks/fix-gate.sh` (`stages`,
  `attempts`), sous le verrou de `statefile.py`. Jamais d'`Edit` ni de `Write`.
- `fix.py` réutilise les commandes de `pipeline.py` (`gate`, `loop` et son archive `history/`, `debt`, `accept`,
  `ask`, `recap`, `set`, le re-gel, l'attente des hooks) par la classe `Fix` de `fix/steps.py`, une
  `pipeline.Ctx` sur `fix.json`. Il ajoute ce qui est propre au fix : `init`, `agent`, `phase`, `freeze`,
  `refreeze` (causes du fix), `arbitrate`, `deviation`, `review-pass`.
- Un verdict de gate ne s'écrit que par un script : `red` et `green` par le hook, `review` par
  `fix.py review-pass`, qui joue `fix_gauntlet.sh review_verdict`. `fix.py pass` et `skip` refusent ces clés.
- `set` n'accepte qu'une liste fermée (`suggestions.<id>` avec une décision bornée, `issue`, `watchdog_cron`) :
  le modèle donne la valeur, le script la décode et refuse ce qui sort du schéma.
