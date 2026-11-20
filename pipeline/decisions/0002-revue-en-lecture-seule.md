# 0002 — La revue est en lecture seule

Statut : acceptée (2026-11-05, reprise du pipeline existant depuis 2026-09-25), amendée le 2026-11-19
(une critique non prouvée part « à vérifier »)
Où elle vit : `agents/feature-reviewer.md` (`disallowedTools`) · `hooks/pipeline-restrict-writes.sh`
(Romain n'écrit que `review.md` et `review.json`) · `pipeline/feature/steps/6_review.md` · même
règle pour Camille, Gaëlle, Denis, Victor (`/fix`) et les relecteurs de `/reviewPR` · `to_verify` :
`scripts/gauntlet/checks_review.sh` (`review_report`, `review_verdict`, `tests_review_*`) ·
`scripts/fix_gauntlet.sh` · `scripts/review/review.py` (severity `to_verify`) ·
`pipeline/suggestions.md` · `pipeline/review/findings_format.md` · `pipeline/feature/steps/3_tests.md`,
`7_harden.md` · `pipeline/fix/steps/3_revue.md` · `pipeline/review/steps/5_briefing.md` · Serena en lecture seule, outils d'écriture refusés aux relecteurs par les mêmes hooks (0018)

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

## Amendement du 2026-11-19 : prouvé, ou « à vérifier »

Romain, Victor et Gaëlle écrivaient des tests « probe » dans le worktree pour vérifier une critique, par
python le plus souvent : un relecteur qui écrit un test devient un auteur, ce que la décision interdit, et
0012 veut une revue sans effet sur ce qu'elle relit. Décidé par Thibault le 2026-11-19 :

- Les relecteurs n'ont pas de probe. La zone `zz_probe_*` (0001) ne leur est pas ouverte, et 0017 ferme
  l'interpréteur par lequel passaient leurs probes.
- Une critique se prouve en lisant le code (le `fichier:ligne` qui la montre) ou en rejouant un test
  existant. Ce qui ne se prouve pas ainsi n'est pas une critique : il va dans `to_verify`
  (`{id, claim, file, line, how, owner}`), avec ce qu'il faudrait lancer pour le prouver.
- `to_verify` repart vers l'agent qui en a la charge, qui le prouve par un probe ou l'écarte : `/feature`,
  Ivan (`owner: implementer`, bloque `review_verdict` comme une critique) ou Hugo (`owner: hardener`, à
  l'étape 7 avec `missing_tests`) ; tests de Gaëlle, Théo ; `/fix`, Fanny ou Bastien (bloque
  `review_verdict`). L'orchestrateur note `outcome` (`proved|dismissed`) et `note` ; le relecteur ne
  l'écrit jamais.
- `/reviewPR` : `"severity": "to_verify"` avec `how`. L'orchestrateur la passe à Maëlle, qui prouve
  légitimement par un test jetable hors du repo (son moyen C, inchangé) ; elle n'est jamais postée, même
  cochée « commenter » au tri.

Conséquence : une critique écartée coûte un passage de l'agent qui la vérifie, au lieu d'un probe écrit par
le relecteur ; elle ne coûte pas une boucle complète (tout écarté et aucune critique → verdict rejoué,
sans relancer le cleaner ni le relecteur).

## Hors champ

- La visite guidée (8b) est écrite par Romain mais ne change pas de code.
- L'application d'une suggestion retenue n'est pas faite par Romain : elle repart à Ivan.
