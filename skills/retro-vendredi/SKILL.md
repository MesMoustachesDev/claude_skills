---
name: retro-vendredi
description: Retro technique du vendredi sur /feature et /fix — mesure la qualité, la vitesse et la consommation des runs de la semaine contre les 4 semaines d'avant (scripts/retro/retro.py, sans LLM), en tire au plus 3 conclusions, propose au plus 3 changements du pipeline validés par script, et n'applique qu'après le go de Thibault. Suit aussi l'effet des changements appliqués les semaines d'avant. À lancer via /retro-vendredi ou par la routine du vendredi 16h.
---

# Retro technique du vendredi

Tu fais la retro hebdomadaire du pipeline (`/feature`, `/fix`) pour Thibault. Tutoie-le, en français,
sans tirets cadratins. **Le modèle traduit, le script décide** : les chiffres viennent de `retro.py`, tu
ne recomptes rien à la main et tu n'inventes aucune tendance que le JSON ne montre pas.

## 1. Mesurer

```bash
python3 ~/.claude/scripts/retro/retro.py collect
```

Il imprime le chemin de `~/.claude-local/retro/AAAA-Www.json` et écrit à côté la page `AAAA-Www.html`
(premier passage : quelques minutes, le cache des transcripts se remplit ; ensuite quelques secondes).
Lis le JSON. Ce qu'il contient, par pipeline (`kinds.feature`, `kinds.fix`) :

- `this_week` / `previous_weeks` / `trend` : moyennes par run des métriques de `metrics`, et le sens
  (`↑` `↓` `=` à ±15 %, `?` sans données). Le sens souhaité est dans `metrics[clé][1]`.
- `weekly` (courbe), `by_size` (features S/M/L : ne compare pas un L à un S), `miss_reasons` (fix : pourquoi
  les tests ont laissé passer le bug).
- `agents_this_week` / `agents_previous` : unités de coût, heures actives, lancements et modèles par agent.
- `runs` : le détail de chaque run fini cette semaine. `in_progress`, `actions_followup`.

Unités = coût relatif à un token d'entrée (cache écrit ×1,25, lu ×0,1, sortie ×5). Heures actives = écarts
de moins de 5 min entre messages ; au-delà c'est de l'attente (Thibault, tâche de fond).

Puis les erreurs récurrentes, qui sont l'autre moitié de la qualité :

```bash
python3 ~/.claude/scripts/learn.py scan ~/work
python3 ~/.claude/scripts/learn.py candidates
```

`scan` liste les runs finis pas encore passés par learn : cite-les, ne les étiquette pas ici (c'est l'étape
9b des pipelines). `candidates` donne les patterns vus dans 2 runs ou plus.

## 2. Comprendre

Pour chaque métrique qui se dégrade (`trend` contraire au sens souhaité) ou qui reste haute, cherche
la cause dans les runs eux-mêmes avant de conclure : `runs[].dir` n'est pas dans le JSON, le dossier
est `<racine du projet>/.claude/{features,fixes}/<nom>/` (ou `archive/`, ou le worktree). Lis
`pipeline.json`/`fix.json` (notes des étapes, `refreezes[].cause`, `accepted[].reason`), `review.json`,
`evidence.md`. Un chiffre isolé sur 1 run n'est pas une tendance : dis-le.

Questions à poser aux données, dans cet ordre :
1. **Qualité** : où sont les RED, regels, critiques, tests manquants ? Quel agent les a laissés passer ?
   Pour /fix, `miss_reasons` : un `untested_case` ou `wrong_layer` qui revient pointe une étape de /feature
   (planner, test-writer) à renforcer.
2. **Vitesse** : le délai vient-il du travail des agents (`active_h`) ou de l'attente (`wait_h`) ? Une
   attente longue est un sujet de flow (question mal posée, porte humaine trop tôt), pas d'agent.
3. **Consommation** : quel agent pèse le plus en unités par run, et a-t-il bougé ? Relances du même rôle
   (`relaunches`) = travail refait : pourquoi ? Un agent cher sur un travail mécanique peut passer à un
   modèle moins cher, un agent qui rate souvent peut mériter le plus fort.
4. **Suivi** : `actions_followup` : chaque changement appliqué a-t-il fait bouger sa métrique dans le
   bon sens, sur assez de runs (3 au moins) ? Sinon, propose de le revoir ou de l'annuler.

## 3. Proposer

Au plus **3** changements, les plus rentables, chacun tiré d'une mesure. Écris-les dans
`~/.claude-local/retro/AAAA-Www.proposals.json` (même semaine que le rapport), une liste de :

```json
{"id": "planner-cas-limites", "kind": "rule|agent_prompt|agent_model|pipeline_step|command|other",
 "target": "chemin sous ~/.claude du fichier à changer", "pipeline": "feature|fix|both",
 "metric": "une clé de metrics", "change": "le changement, en une ou deux phrases",
 "why": "la mesure qui le justifie, chiffres compris", "evidence": ["projet/run", "..."]}
```

Valide-les : `python3 ~/.claude/scripts/retro/retro.py check <fichier>`. Code non nul : corrige et
revalide, ne montre jamais une proposition refusée. Avant de proposer de changer une règle de fond de
`/feature`, `/fix`, du gauntlet ou des agents, lis son ADR (`~/.claude/pipeline/decisions/`) : la
proposition dit si elle l'amende.

## 4. Montrer

Envoie la page avec `SendUserFile` (`~/.claude-local/retro/AAAA-Www.html`, display `render`). Elle nomme
des projets : jamais d'Artifact publié ni de copie dans `~/.claude`. Puis un message court :

- une ligne par pipeline : runs finis, et les 3 mouvements les plus nets (métrique, avant → maintenant) ;
- **Conclusions** (3 au plus) : ce qui s'améliore, ce qui se dégrade, pourquoi, avec le run qui le montre ;
- **Suivi** des changements des semaines d'avant ;
- **Propositions** numérotées : changement, mesure qui le justifie, métrique qui dira s'il a marché.

Puis une seule question `AskUserQuestion`, multiSelect, « Lesquelles j'applique ? », une option par
proposition plus « Aucune ». Semaine sans run fini : dis-le en deux lignes, montre le suivi s'il y en a,
et arrête-toi.

## 5. Appliquer (seulement sur son go, dans cette session)

Pour chaque proposition retenue :
- une règle d'une ligne : `python3 ~/.claude/scripts/rule_add.py <fichier> "<ligne>" [--after "…"]` ;
- tout autre changement : `~/.claude/scripts/claude_change.sh start retro-<id>`, édition et commit dans
  `~/.claude-wt/retro-<id>` (ADR mise à jour dans le même commit si la règle a une ADR), puis
  `claude_change.sh land retro-<id>` dans le même tour ;
- un changement de mod (`mods/<nom>`) monte sa version et met le plugin à jour (CLAUDE.md global).

Puis `python3 ~/.claude/scripts/retro/retro.py record <proposals.json> <id> applied <sha>` ; pour une
proposition qu'il écarte, `record … rejected "<sa raison>"`. Le suivi des semaines suivantes en dépend.
Rien de nommé (client, projet) n'entre dans `~/.claude` : un exemple dit « une feature d'écran ».

S'il ne répond pas, n'applique rien : les propositions restent dans le fichier et dans cette session.
