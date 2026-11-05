# 0001 — Les tests sont écrits et gelés avant l'implémentation

Statut : acceptée (2026-11-05, reprise du pipeline existant depuis 2026-09-25), amendée le 2026-11-05
(tests sobres, plus bas)
Où elle vit : `commands/feature.md` (étapes 3, 3b, 4) · `pipeline/feature/steps/3_tests.md` (gel,
re-gel) · `hooks/pipeline-restrict-writes.sh` · `scripts/gauntlet/checks_test.sh`
(`red_check`, `test_freeze_check`) · `scripts/pipeline.sh freeze|refreeze`

## Contexte

Un agent qui écrit le code et ses tests ajuste les tests au code : la suite passe, et ne prouve que
ce que le code fait déjà. Les tests sont l'actif durable de la feature ; ils doivent dire ce que la
spec demande, pas ce qu'Ivan a compris.

## Décision

- Théo écrit les tests contre la spec et les contrats de Thibault, sans voir aucune implémentation :
  le code n'est que des stubs `throw UnimplementedError()`. Le gate `red` exige une suite qui compile
  et qui est rouge.
- Gaëlle relit les tests, Thibault les valide au point d'étape « tests », puis `pipeline.sh freeze`
  les commite et pose `tests_freeze_sha`.
- Après le gel, `test/` ne change plus. Le hook d'écriture le refuse à Ivan et à Nina ; Hugo peut
  seulement ajouter des fichiers. `test_freeze_check` (strict, ou additive pour Hugo) rejoue le diff
  depuis `tests_freeze_sha` à chaque gate : c'est le filet pour ce que le hook ne voit pas
  (cas réel : Hugo, refactor_feature, un Edit refusé refait en `sed -i`).

## Conséquences

- Un test faux bloque Ivan au lieu d'être corrigé en silence. Il le signale (« tests suspects ») et
  Thibault tranche.
- Un test corrigé se re-gèle (`pipeline.sh refreeze`) avec sa cause (`hygiene`, `technique`,
  `contrat`, `spec`, `interne`), comptée : c'est la mesure qui dira si un double-loop vaudrait mieux.
- La suite écrite à froid colle mal aux détails d'implémentation : sur refactor_feature, la
  suite gelée avait 38 tests rouges contre le code final, corrigés par deux re-gels (banc de rejeu,
  2026-11-04).

## Amendement du 2026-11-05 : des tests sobres

Une suite gelée se paie à chaque refactor et à chaque re-gel. Sur les features du projet client, elle faisait
3 à 16 lignes de test par ligne de code, avec le même comportement prouvé à plusieurs étages. La cause :
les règles tirées de `learn` ajoutaient des tests sans jamais en retirer, et deux d'entre elles
demandaient le doublon. Désormais :

- un comportement se prouve une fois, au plus bas étage qui le peut. Un maillon qui transforme se teste
  pour chacun de ses cas, un maillon qui transmet a un test de propagation. Aucun test de rendu
  (`create_test.md`, principes 18 et 19) ;
- Gaëlle bloque les doublons ; le check `test_dups` du gate `red` lui liste les noms de test présents
  dans deux fichiers. Il ne bloque pas lui-même, parce qu'un nom générique peut désigner deux classes.

Une règle que `learn` propose et qui ajouterait des tests se relit à la lumière du principe 18 :
elle précise l'étage où le test manquait, pas « à chaque maillon ».

## Hors champ

- Les tests ajoutés par Hugo (7) après le gel : nouveaux fichiers seulement, jamais de modification.
- `/fix` suit la même logique avec un test de reproduction gelé (Bastien), décrite dans
  `commands/fix.md`.
- L'orchestrateur corrige un test seulement sur instruction explicite de Thibault, suivie d'un re-gel.
