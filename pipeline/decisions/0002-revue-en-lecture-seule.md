# 0002 — La revue est en lecture seule

Statut : acceptée (2026-11-05, reprise du pipeline existant depuis 2026-09-25)
Où elle vit : `agents/feature-reviewer.md` (`disallowedTools`) · `hooks/pipeline-restrict-writes.sh`
(Romain n'écrit que `review.md` et `review.json`) · `pipeline/feature/steps/6_review.md` · même
règle pour Camille, Gaëlle, Denis, Victor (`/fix`) et les relecteurs de `/reviewPR`

## Contexte

Un relecteur qui corrige ce qu'il trouve devient un auteur de plus. Personne ne relit sa correction,
elle échappe au gel et aux gates de l'étape qui l'aurait produite, et Thibault ne voit jamais le
problème qu'elle a réglé.

## Décision

- Romain lit le code, les contrats, la spec, le log `maintain` du gauntlet et le rapport de Denis,
  et n'écrit que `review.json` (critiques, suggestions, dette, tests manquants, visite guidée) et
  `review.md`. Le frontmatter lui retire `Edit`, et le hook refuse toute autre écriture, Bash compris.
- Ce qu'il trouve repart vers l'agent qui en a la charge : les critiques à Ivan puis Nina (boucle,
  plafonnée par `pipeline.sh loop`), les suggestions à Thibault, les `missing_tests` à Hugo, la dette
  à l'evidence.

## Conséquences

- Chaque correction passe par l'étape qui la contrôle : gate `green`, gel des tests, nouvelle revue.
- Thibault voit chaque suggestion au format de `pipeline/suggestions.md` et décide lui-même.
- Une boucle de revue coûte un passage d'Ivan, de Nina et de Romain. Le plafond de `loop`
  rend la main à Thibault quand elle ne converge pas.

## Hors champ

- La visite guidée (8b) est écrite par Romain mais ne change pas de code.
- L'application d'une suggestion retenue n'est pas faite par Romain : elle repart à Ivan.
