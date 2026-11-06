# Un dossier par langage

Chaque langage que le pipeline sait traiter a son dossier ici : `flutter/`, `android/`… Rien de ce qui est
propre à un langage ne vit ailleurs, pour qu'un projet Kotlin ne charge jamais la doctrine Flutter, et
inversement (ADR `pipeline/decisions/0011-un-dossier-par-langage.md`).

| Quoi | Où | Qui le lit |
|---|---|---|
| Valeurs pour les scripts (marqueurs, commandes, globs) | `stacks/<langage>/stack.ini` | `scripts/stack.sh get <clé>` |
| Checks du gauntlet propres au langage | `stacks/<langage>/checks.sh` (fonctions `check_*` qui remplacent les communes, `stack_doctor`) | `gauntlet.sh` (`stack_load_checks`), `fix_gauntlet.sh` |
| Gabarits de règles projet, brick, scaffold | `stacks/<langage>/templates/` | `/feature init`, le doctor |
| Doctrine pour Claude (conventions, tests, architecture, conseils aux agents) | `~/.claude/rules/stacks/<langage>*.md`, avec un frontmatter `paths:` | Claude Code, seulement quand un fichier de ce langage est lu |

## Choisir le langage

`stack.sh detect <chemin>` remonte de `<chemin>` vers la racine du repo ; le premier dossier qui contient un
marqueur (`markers`) décide, le plus petit `priority` gagnant à égalité. Une app Flutter est donc du Flutter
dans `lib/` et du Kotlin dans `android/app/`. `stack = <langage>` dans le bloc ini de
`.claude/rules/feature_pipeline.md` force le langage de tout le repo.

`stack.sh get <clé> <chemin>` rend la valeur de la config du projet si elle la donne, sinon celle de
`stack.ini`. Dans une valeur, `{flutter}`, `{dart}`, `{gradle}` renvoient aux clés du même nom.

Les scripts Python (`pipeline.py`, `review.py`, `report.py`) passent par `scripts/stacklib.py`, qui appelle
`stack.sh`. `stack.sh vals <chemin> <clé>…` rend plusieurs valeurs d'un coup (hooks) ; `stack.sh package
<chemin>` le dossier du package qui contient un chemin ; `STACK_CFG=<fichier>` lit une autre config que celle
du projet (`GAUNTLET_CFG`, gabarit).

## Les checks du gauntlet

`gauntlet.sh` source les checks communs (`scripts/gauntlet/checks_*.sh` : gel des tests, empreinte, secrets,
TODO, QA, rapports des agents), puis `stacks/<langage>/checks.sh` du langage du package. Un check qu'un autre
langage définit et pas celui-ci est **non applicable** : `[N/A]  <check> : non applicable à <langage>` dans le
journal, `not_applicable` dans `last_<profil>.json`, jamais compté dans `passed`. Il ne bloque pas le profil :
le langage n'a simplement pas encore ce gate (Android, point 6 du plan `langages.md`). Les checks communs lisent
les valeurs du langage (`extensions`, `src_dirs`, `test_dirs`, `manifests`, `tool_files`).

## La doctrine : des règles chargées à la demande

Une règle de `~/.claude/rules/` avec `paths:` n'est mise dans le contexte qu'au premier Read, Write ou Edit
d'un fichier qui correspond, dans la session comme dans un sous-agent (vérifié le 2026-11-06 : rien au
démarrage, rien à la lecture d'un `.dart`, la règle Kotlin à la lecture d'un `.kt`). Toutes les commandes en
profitent sans rien faire. Une règle **sans** `paths:` dans `~/.claude/rules/` se chargerait dans toutes les
sessions de tous les projets : il n'y en a pas, et ce README n'est pas dans `rules/` pour cette raison.

```markdown
---
paths:
  - "**/*.kt"
  - "**/*.kts"
---
# Android / Kotlin
…
```

Les prompts d'agents, les commandes et `pipeline/*.md` restent sans langage : ils disent « la commande de
test du langage », « les conventions de test du langage », et la règle chargée dit lesquelles.

## Ajouter un langage

1. `stacks/<langage>/stack.ini` : `priority`, `markers`, `extensions`, `manifests`, `test_globs`, `src_dirs`,
   `test_dirs`, `package_manifest`, `layer.data`, `presentation_dirs`, `contract_globs`, `generated.exclude`, les
   commandes (`test_cmd`, `test_files_cmd`, `prepare_cmd`…). `stacks/flutter/stack.ini` documente chaque clé.
2. `~/.claude/rules/stacks/<langage>.md` avec `paths:` sur ses extensions.
3. `stacks/<langage>/checks.sh` pour les checks qui ne se réduisent pas à une commande.
4. Un test dans `scripts/gauntlet/tests/test_stack.sh`.
