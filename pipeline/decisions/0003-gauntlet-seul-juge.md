# 0003 — Le gauntlet est le seul juge d'une étape

Statut : acceptée (2026-11-05, reprise du pipeline existant depuis 2026-09-25)
Où elle vit : `scripts/gauntlet.sh` et `scripts/gauntlet/` (profils, checks) · `hooks/pipeline-gate.sh`
(gate de fin d'agent) · `scripts/pipeline.sh` (seul à écrire `pipeline.json`) · `commands/feature.md`
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
