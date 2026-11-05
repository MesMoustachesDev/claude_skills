# Décisions du pipeline

Une décision par fichier, numérotée, au format de `0000-gabarit.md`. Elles disent pourquoi le
pipeline (`/feature`, `/fix`, le gauntlet, les agents) est fait comme il est, pour qu'une session
qui le modifie ne défasse pas sans le savoir une règle dont elle ne voit pas la raison.

**Un changement qui revient sur une décision met son ADR à jour dans le même commit** : nouveau
statut (`remplacée par NNNN`, `amendée le <date>`), ou une nouvelle ADR qui la remplace. Une ADR ne
se supprime pas.

| # | Décision | Statut |
|---|---|---|
| [0001](0001-tests-geles-avant-implementation.md) | Les tests sont écrits et gelés avant l'implémentation | acceptée |
| [0002](0002-revue-en-lecture-seule.md) | La revue est en lecture seule | acceptée |
| [0003](0003-gauntlet-seul-juge.md) | Le gauntlet est le seul juge d'une étape | acceptée |
| [0004](0004-evidence-par-etape.md) | Chaque étape laisse ses preuves, l'evidence les rassemble | acceptée |
| [0005](0005-pas-d-arret-sans-thibault.md) | Le pipeline ne s'arrête que pour attendre Thibault (watchdog) | acceptée |
| [0006](0006-doctrine-injectee.md) | La doctrine d'un agent est injectée dans son contexte, pas demandée | acceptée |
