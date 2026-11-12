# 0014 — Un epic a son plan dans `.claude/plans/`, écrit avant tout lancement

Statut : acceptée (2026-11-12)
Où elle vit : `commands/epic.md` (nouvel epic point 5, « Le plan de l'epic », `sync` point 1),
`pipeline/feature/steps/0b_cadrage.md` (point 7)

## Contexte

`/epic` gardait son découpage dans `pipeline.json → split` et le montrait dans son tableau de bord, mais
n'écrivait pas de plan dans `.claude/plans/`. Le panneau Pipeline ne lit que ces plans : sur un epic de
quatre bugs de prod, les quatre `/fix` tournaient et le panneau montrait toujours un autre plan. Pour
Thibault, le plan est la seule chose qui compte dans un epic.

## Décision

- Le découpage validé devient `.claude/plans/<nom>.md` dans le checkout principal, avant de lancer la
  première sous-session : un point par morceau, au format des « Plans de travail » du CLAUDE.md global.
- L'epic tient ce plan à jour dans le même tour que `split` : `→ <branche>` au lancement, `[fait]` au
  merge, `[abandonné]` et sa raison, `[toi]` quand une question attend Thibault.
- Une reprise sans plan l'écrit d'abord.

## Conséquences

L'epic sort de son worktree (`ExitWorktree keep`) avant d'écrire le plan : une session isolée dans un
worktree ne peut pas écrire dans le checkout principal. `split` reste l'état machine ; le plan en est la
vue pour Thibault et le panneau.

## Hors champ

Le format du panneau Pipeline lui-même (mod pipeline-view).
