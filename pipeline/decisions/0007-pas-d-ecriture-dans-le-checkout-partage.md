# 0007 — Personne n'écrit directement dans le checkout principal de ~/.claude

Statut : acceptée (2026-11-05)
Où elle vit : `hooks/claude-home-guard.sh` (PreToolUse de `settings.json`) · `scripts/rule_add.py` ·
`scripts/claude_change.sh` · `CLAUDE.md` · `pipeline/learn.md` §4 · `commands/feature.md` et `fix.md`
(« Chaque réponse peut devenir une règle »)

## Contexte

Chaque feature a son worktree dans le projet, mais `~/.claude` n'en avait qu'un, lu par toutes les
sessions. Les orchestrateurs de `/feature` et `/fix` y corrigeaient le gauntlet en cours de route, learn y
ajoutait ses règles, et la consigne disait « un fichier de `~/.claude` n'est pas commité par toi ». Le
5 novembre, 29 fichiers de sept sessions attendaient un commit, mêlés : une session ne savait plus quoi
commiter, et une autre a vu ses commits atterrir sur la branche d'une troisième.

## Décision

- Un hook `PreToolUse` refuse toute écriture (Edit, Write, et les écritures Bash que voit
  `bash_write_targets.py`) d'un fichier versionné ou versionnable sous `~/.claude`. Restent libres ce que
  git ignore (état, transcripts, plans, résultats), les worktrees `~/.claude-wt/*`, et les scripts.
- Une règle d'une ligne passe par `rule_add.py <fichier> "<ligne>" --after "<ancre>"`, qui l'insère et la
  commite aussitôt, et refuse un fichier qui a déjà des changements d'un autre.
- Tout autre changement passe par `claude_change.sh start <nom>` (worktree et branche `pipeline/<nom>`),
  puis `land <nom>` (rebase sur main, avance rapide de main, nettoyage), dans le même tour.

## Conséquences

- Le checkout principal reste propre : ce qu'il contient est commité, et chaque commit a un auteur.
- Une correction du gauntlet en pleine feature coûte un `start` et un `land` de plus ; elle n'est visible
  des autres sessions qu'au `land`.
- Les écritures que le hook ne voit pas (`python -c`, un script maison) restent possibles : c'est un filet,
  pas une prison.

## Hors champ

- Les règles projet (`.claude/rules/` d'un repo) : `mr.py archive` les recopie encore dans le checkout
  principal du projet sans les commiter.
- Thibault lui-même : le hook ne juge que les outils de Claude.
