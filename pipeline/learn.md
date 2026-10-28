# Learn — ce qu'un run apprend aux suivants

Partagé par `/feature` (étape 9b) et `/fix` (étape 5), juste avant `create_commits` : une règle
ajoutée au projet part dans les commits du run.
Une erreur corrigée par un agent de revue (Romain, Victor, Camille, Gaëlle, Denis) ou rattrapée par un
re-gel coûte une boucle. Si elle revient d'un run à l'autre, c'est qu'une règle manque **en amont**, là
où l'agent qui l'a produite la lit. Learn repère ces récurrences et propose la règle à Thibault.

Ce n'est pas `answers.md` : `answers.md` retient **ses réponses** à des questions ; learn retient
**les erreurs des agents**. Les deux se complètent, aucun ne remplace l'autre.

Outil : `~/.claude/scripts/learn.py` (registre dans `~/.claude/pipeline/lessons/`). Le script extrait et
compte ; toi, tu étiquettes et tu rédiges. Tu n'édites jamais `ledger.jsonl` ni `patterns.json` à la main.

## 1. Extraire

`python3 ~/.claude/scripts/learn.py extract <dossier du run>` (`.claude/features/<nom>` ou
`.claude/fixes/<nom>`). Il rend les signaux pas encore étiquetés — critiques et suggestions de revue
(finales et archivées à chaque boucle dans `history/`), tests manquants, bloquants de spec et de tests,
roues réinventées, `miss_reason` de Bastien, écarts au plan, arbitrages, re-gels, acceptations — et
les patterns déjà connus (`known_patterns`).

## 2. Étiqueter

Pour chaque signal, un `pattern` : un slug en snake_case qui nomme **la cause qui se répète**, pas le
symptôme du run (`either_unfolded_outside_bloc`, `mock_hides_platform_null`, `spec_omits_empty_state`,
pas `meal_plan_bug_42`).
- Un pattern connu qui a la même cause → réutilise-le. C'est l'essentiel : un slug neuf par run ne
  fait jamais de récurrence.
- Une cause générale, nouvelle → nouveau slug, avec une description d'une phrase dans `patterns`.
- Propre à ce run (une faute de frappe, un choix de goût, un détail métier unique) → `noise`.
  Dans le doute entre `noise` et un pattern, choisis le pattern : il ne coûte rien tant qu'il ne revient pas.

Écris `{"run": "<clé du run>", "patterns": {"<slug neuf>": "<desc>"}, "labels": [{"id": "…", "pattern": "…"}]}`
dans le scratchpad, puis `learn.py record <fichier>`. Tous les signaux sont étiquetés, `noise` compris.

## 3. Proposer

`learn.py candidates` liste les patterns vus dans **au moins 2 runs distincts**, ni promus, ni refusés
récemment. Aucun → une ligne dans le résumé final (« learn : n signaux, aucune récurrence ») et c'est fini.

Pour chaque candidat, `learn.py examples <slug>`, puis choisis **où** la règle empêche l'erreur, c'est-à-dire
dans ce que lit l'agent qui l'a produite, pas celui qui l'a rattrapée :

| L'erreur vient de | Signaux typiques | La règle va dans |
|---|---|---|
| l'implémentation (Ivan, Nina, Fanny) | `review_critical`, `suggestion` appliquée, `reinvented`, `plan_deviation` | `.claude/rules/create_feature_rules.md` du projet ; si elle vaut pour tous les projets Flutter, le template `~/.claude/commands/templates/flutter/create_feature_rules.md` |
| les tests (Théo, Bastien, Hugo) | `tests_blocking`, `missing_test`, `miss`, `arbitration`, re-gel `technique` | `~/.claude/commands/create_test.md` |
| la spec (Sophie) | `spec_blocking`, re-gel `spec` | `~/.claude/commands/templates/flutter/feature_spec_template.md` (la section concernée) |
| la revue elle-même : un défaut vu tard (re-gel, QA, visite) qu'aucune revue n'a signalé | `refreeze`, `accepted` répété | `~/.claude/pipeline/review_grid.md` |
| un choix que Thibault tranche toujours pareil | `accepted` répété | `~/.claude/pipeline/answers.md` (son format) |

**Détectable par un script ?** (un import interdit, un `try/catch` hors `data/`, une valeur brute, un
fichier oublié) → la règle textuelle ne suffit pas : propose en plus un check du gauntlet, en carte de
session (`start_session`, `own_initiative`) avec le slug, les exemples et le fichier du check. Tu ne
modifies pas le gauntlet toi-même.

Montre ensuite, avant la question, un tableau `Pattern | Runs | Exemples (fichier:ligne) | Règle proposée | Fichier`.
La règle est à l'impératif, une ligne, au format du fichier cible (une puce dans la bonne section), suivie de
`(learn <date>, <slug>, <n> runs)`. Puis un seul `AskUserQuestion` multiSelect, header `Leçons`, une option par
règle (label : le slug ; description : la règle et le fichier), plus « Discuter — je veux comprendre avant de décider ».

## 4. Appliquer

- Retenue → ajoute la ligne telle qu'il l'a validée dans le fichier cible, puis
  `learn.py promote <slug> <fichier> "<règle>"`. Un fichier du projet (`.claude/rules/…`) est commité
  avec le run ; un fichier de `~/.claude` n'est pas commité par toi.
- Non retenue → `learn.py reject <slug> "<sa raison, ou « non retenue »>"`. Le pattern ne revient
  qu'après deux runs de plus.
- « Discuter » → tu expliques (les exemples, ce que la règle aurait évité), puis tu reposes la même question.

Learn ne bloque jamais la livraison : si le script échoue, une ligne dans le résumé final, et c'est fini.

## Rattrapage

`learn.py scan ~/work` liste les runs terminés (avec `evidence.md`) qui ne sont jamais passés par learn.
Sur demande de Thibault seulement : étiquette-les run par run (étapes 1 et 2), puis une seule étape 3 à la fin.
