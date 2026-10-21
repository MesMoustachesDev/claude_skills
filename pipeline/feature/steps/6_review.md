### 6. Revue — Romain (`feature-reviewer`)

D'abord les scripts : `~/.claude/scripts/gauntlet.sh maintain <nom>` (dépendances inter-features
justifiées, santé des packages pub.dev, design system, l10n, code mort, périmètre, secrets…). Son
verdict n'arrête rien ici : le log est une **entrée** de Romain, qui transforme chaque échec en finding.

Prompt : nom, `spec.md`, package, **deux bases** — la merge-base avec `base_branch` (le périmètre :
tout ce que la feature a écrit, contrats, scaffold et code ; c'est contre elle que se décide
suggestion ou dette) et `tests_freeze_sha` (ce qu'Ivan et Nina ont écrit depuis le gel) — `tests.md`,
`.claude/features/<nom>/.gauntlet/last_maintain.log`, `.claude/features/<nom>/dedup.md`,
`.claude/rules/pr_rules.md` si présent, `.claude/rules/create_feature_rules.md`,
`~/.claude/commands/reviewPR.md`, `contracts.sha` et `contracts.files` (les contrats de Thibault : la référence), `archi.json`
(les C<n> pour la visite guidée). Romain écrit aussi `review.json → tour`, la visite guidée (8b).
Au retour, `gauntlet.sh review_verdict <nom>` (le hook de l'agent n'a vérifié que le format — un
reviewer qui trouve des critiques doit pouvoir rendre la main) :
- vert → `pipeline.sh pass <nom> review`. Montre **tout de suite** au dev chaque entrée de
  `review.json → suggestions` au format de `~/.claude/pipeline/suggestions.md` (problème, pourquoi,
  cause, si on ne fait rien, correctif, pour / contre, effort), puis le choix en `AskUserQuestion`
  multiSelect décrit dans ce fichier. Note chaque choix dans `pipeline.json → suggestions`
  (`{"S1": {"decision": "applied|skipped", "note": "<nuance du dev>"}}`), puis
  `pipeline.sh gate <nom> suggestions` (aussi quand il n'y avait aucune suggestion à montrer). Les retenues repartent à
  Ivan (bloc complet + nuance) puis à Nina, avant Hugo ; les autres vont, avec leur bloc, en
  « Suggestions non appliquées » dans l'evidence. Une suggestion déjà tranchée (même fichier, même
  problème) qui revient dans une revue suivante ne se repose pas.
- rouge → **boucle** : `pipeline.sh loop <nom> review`. Code 0 : relance **Ivan** (prompt : la liste
  `critical` avec `fix`, plus le contexte habituel), puis le **cleaner**, puis le **reviewer**.
  Code 3 (plafond dépassé) : point imprévu avec la liste des critiques persistantes.
- `review.json → debt` (problèmes du code préexistant, hors des lignes de la feature) : ajoute
  chaque entrée à `pipeline.json → debt` (`{source: "review", file, line, issue}`), **sans la montrer
  au dev** ni la poser en question ; elle sort dans l'evidence sous « Dette existante ». Une
  suggestion qui porte sur du code préexistant (hors du diff depuis la merge-base) est traitée de
  même : pas présentée, ajoutée à `debt`, et notée `pipeline.json → suggestions.<id> = {"decision":
  "debt"}` (la visite et l'evidence ne la montrent pas comme « à trancher » ni « non appliquée »).
- `review.json → missing_tests` ne déclenche jamais de boucle ni de re-gel : la liste va à Hugo (7),
  qui ajoute ces tests en fichiers nouveaux.

**Gabarit S :** identique (critiques, suggestions, boucle vers Ivan). Les `missing_tests` vont à
Hugo, et c'est ce qui le fait lancer même sans logique à muter (voir 7). **En L :** n'a pas lieu.

