# Prune Tests — élaguer la suite d'une feature livrée

Tu élagues les tests d'une feature déjà livrée. **Le dev, c'est Thibault** : il relit le diff et décide
du commit. Appelle-le Thibault et tutoie-le.

Le principe : **Élise propose, le script décide, Thibault commite.** Un test ne part que si la suite
reste verte, si les lignes couvertes de `lib/` restent les mêmes et si le score de mutation du gauntlet
ne baisse pas (ADR 0001, amendement « tests sobres »).

Cible : **$ARGUMENTS**, le nom d'une feature qui a son `.claude/features/<nom>/pipeline.json`. Vide :
demande-la. Option `--no-mutation` : couverture seule, pour un premier tri rapide. Elle laisse passer les
tests qui tuent un mutant sans couvrir de ligne de plus : ne la propose jamais pour le passage final.

1. **Le worktree.** Tu travailles sur la branche de la feature, dans un worktree à part
   (`<repo>-wt/<nom>`), arbre propre. Une branche déjà mergée : nouvelle branche
   `chore/<nom>_tests_sobres` depuis la branche de base, et dis-le à Thibault.
2. **La référence.** `gauntlet.sh test <nom>` et `gauntlet.sh mutation <nom>` doivent être verts. Sinon,
   arrête-toi : on n'élague pas une suite rouge.
3. **Les candidats.** Lance **Élise** (`test-pruner`) avec la feature, son package et la racine du worktree. Elle
   écrit `.claude/features/<nom>/prune_candidates.json`. Montre à Thibault le nombre de candidats par
   `kind`, sans attendre.
4. **L'élagage.** En arrière-plan : `gauntlet.sh prune <nom> .claude/features/<nom>/prune_candidates.json`.
   Une liste refusée (exit 2) repart chez Élise avec le message du script, une fois. Un lot qui perd
   quelque chose est coupé en deux par le script : c'est long (un passage de mutation par lot), pas bloqué.
5. **Le nettoyage.** Les helpers, fixtures et imports devenus morts dans les fichiers touchés se
   retirent, puis `flutter analyze` sur le package et `gauntlet.sh test` / `mutation` rejoués.
6. **Le compte rendu.** Avant / après : tests, lignes de test, lignes couvertes, score de mutation, durée
   de la suite ; puis les candidats gardés et pourquoi (`prune_candidates.result.json`). Les retraits sont
   dans le worktree, **non commités**. Thibault relit `git diff` ; sur son « go », un commit par fichier
   de test ou par couche (`test: retire les tests déjà prouvés de <couche>`). Pousser et ouvrir une MR
   restent à sa demande.
