# 0013 — /epic orchestre les /feature et les /fix et lance lui-même leurs sessions

Statut : acceptée (2026-11-12)
Où elle vit : `commands/epic.md` (intro, « Lancer une sous-session », nouvel epic point 5, tableau de
bord point 3), `pipeline/feature/steps/0b_cadrage.md` (point 7)

## Contexte

Le texte de `/epic` disait « tu ne lances aucune sous-feature » et donnait à Thibault une commande à
recopier pour chacune. Sur un epic de quatre bugs de prod, l'epic a donc cadré puis attendu ; Thibault
cherchait les sessions de chaque bug, qui n'existaient pas. Pour lui, `/epic` a toujours été
l'orchestrateur des `/fix` et des `/feature` : c'est lui qui lance les bonnes sessions au bon moment.

## Décision

- `/epic` lance chaque morceau du découpage dans sa propre session (`start_session`, worktree à part),
  dès que ses dépendances sont mergées, avec un brief complet (commande, faits relevés, ce qui
  contredit la description, validation attendue).
- Un morceau dit son outil (`split[i].tool` : `feature` ou `fix`) ; un epic de bugs, c'est un `/fix`
  par bug. `split[i].session` garde l'id de la session.
- L'epic suit les notes de fin de tour, vérifie avant de changer un statut, relaie les questions des
  sessions à Thibault sans y répondre, et lance ce qu'un merge débloque.
- L'epic n'écrit toujours aucun code.

## Conséquences

Thibault n'a plus de commande à recopier ; l'epic consomme des sessions en parallèle (une par morceau
débloqué). Les règles « sessions lancées par une autre session » du CLAUDE.md global s'appliquent :
pas de troisième niveau, pas de sondage, jamais deux sessions dans le même dossier.

## Hors champ

Un morceau dont une dépendance n'est qu'en MR ouverte ne part de sa branche qu'avec l'accord de
Thibault. Les écritures dans le tracker restent montrées et validées (`tracker.md`).
