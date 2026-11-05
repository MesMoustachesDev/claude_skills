# 0009 — La liste des tests se décide avant d'en écrire un

Statut : acceptée (2026-11-05), amende 0001
Où elle vit : `pipeline/feature/steps/3_tests.md` (3a) · `agents/feature-test-planner.md` ·
`agents/feature-test-reviewer.md` (mode liste) · `agents/feature-test-writer*.md` ·
`scripts/gauntlet/test_plan.py` · `scripts/gauntlet/checks_test_plan.sh` (`test_plan`, `test_plan_match`
dans le gate `red`) · `hooks/pipeline-restrict-writes.sh` · `hooks/pipeline-gate.sh` ·
`scripts/pipeline/pipeline.py` (`ORDER`)

## Contexte

Sur une feature du projet client, Théo avait écrit 152 tests ; 37 ne prouvaient rien de plus (retirés
sans perdre une ligne couverte ni un mutant). Les règles « un comportement, un étage » de 0001 agissaient
pendant l'écriture, et Gaëlle bloquait les doublons **après** : chaque test en trop avait déjà coûté son
écriture, sa relecture et un tour de boucle, puis se payait à chaque passage de la suite. Élaguer après
coup (essai `/prune_tests`, retiré le même jour) coûtait plus encore : prouver qu'un test ne sert à rien
demande une passe de mutation par lot.

## Décision

- **3a.** Avant tout test, Théo-liste (`feature-test-planner`) écrit `tests_plan.json` : chaque test avec
  son fichier, son nom, son étage et les items de la spec qu'il prouve. `test_plan.py items` numérote ces
  items : scénarios de §4, contrats de §5, règles de données de §6 (tables et règles numérotées), erreurs
  de §7.
- **Assez**, tenu par le script (`test_plan`) : chaque item est prouvé ou écarté avec sa raison, chaque
  scénario a son test d'acceptation. Tenu par Gaëlle (mode liste) : chaque test prouve vraiment son
  item, et une règle à plusieurs conditions a un test par condition et par borne.
- **Sobre**, tenu par le script : chaque test prouve au moins un item ; un item prouvé par beaucoup de
  tests est signalé. Tenu par Gaëlle : les doublons sortent de la liste avant d'être écrits.
- Théo écrit exactement la liste : `test_plan_match`, dans le gate `red`, refuse un test écrit hors liste
  ou prévu et pas écrit. Un test à ajouter passe d'abord par la liste.
- Le filet d'après reste : la couverture (5) et la mutation (Hugo, 7) disent ce que la liste aurait raté.

## Conséquences

- Mesuré sur la même feature : voir « Mesure ».
- Une étape de plus (un agent Sonnet, quelques minutes, puis la relecture de Gaëlle sur une page) avant
  l'écriture, qui en économise plus qu'elle ne coûte dès que la liste retire des tests.
- La liste devient la table de couverture lisible de la feature : chaque test dit ce qu'il prouve.

## Mesure (2026-11-05, une feature du projet client, 152 tests écrits par Théo avant le gel)

Théo-liste, sur la spec seule, a proposé 61 tests. On a gardé de la vraie suite les tests qui
correspondent à la liste (correspondance faite par un agent à contexte vierge, sur le corps des tests), et
mesuré sur le vrai code :

| Suite | Tests ajoutés | Couverture des lignes modifiées | Mutants survivants |
|---|---|---|---|
| Théo, avant le gel | 152 | — | 4 (tués ensuite par Hugo) |
| Réduite à la première liste | 58 | [OK] | 5 sur 51 (90 %) |
| Réduite à la liste corrigée | 61 (59 retrouvés) | 98,5 % [OK] | 2 sur 51 (96 %) |

Les survivants de la première liste venaient tous d'une règle à deux conditions testée d'un seul côté :
d'où « un test par condition et par borne » (Théo-liste, Gaëlle). Les 2 qui restent sont deux des 4 que
la suite de 152 tests laissait aussi, et que Hugo tue à l'étape 7. Limites : une seule feature, et des
tests réels pris pour ceux que Théo écrirait depuis la liste.

## Hors champ

- Les tests de Hugo (7) : ajoutés après le gel pour tuer un mutant, hors liste.
- Les tests écrits dans un autre package (`writes.extra`) : `test_plan_match` ne compare que le package
  de la feature.
- Les features dont les tests étaient déjà écrits avant cette décision : pas de retour en 3a
  (`pipeline.py`), pas de comparaison sans liste (`test_plan_match`).
- `/fix` : un test de reproduction, pas de liste.
