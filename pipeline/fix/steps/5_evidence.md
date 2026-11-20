# /fix — étape 5 : evidence, commits

Écris `.claude/fixes/<nom>/evidence.md` :

```
# Fix — <nom>
Branche fix/<nom> · Base <base_branch>@<base_sha court> · Test gelé @<freeze_sha court>
Issue : #<iid> <url>       si fix.json → issue existe (issue.md, partie C)

## Bug                      symptôme, en une phrase
## Cause racine             root_cause — root_cause_location
## Pourquoi les tests l'ont raté   miss_reason — l'explication, et le test existant corrigé s'il y en a un
## Preuve                   test(s) ajouté(s), rouge avant (expected_failure), vert après ; suite verte
## Plan validé             couche, approche, alternative écartée ; choix du dev (proposé / alternative / autre)
## Correction               l'arbre du changement : `python3 ~/.claude/scripts/change_tree.py <base_sha>` depuis le worktree, le rôle de chaque fichier en une ligne à la place de `<rôle>` (volumes et reformatage mesurés : ne les recalcule pas), chaque fichier marqué prévu / écart accepté ; même défaut corrigé ailleurs
## Non vérifiés             .gauntlet/last_*.json → not_applicable (check@package : conventions sans version pour le langage, ou outil absent du projet), avec la ligne [N/A] du journal ; « aucun » sinon (ADR 0011 : signalé, pas bloquant)
## Revue                    cause traitée : yes/partial ; plan respecté : yes/partial ; critiques résolues : n ; à vérifier : n prouvées, n écartées (review.json → to_verify.outcome) ; reviewers projet : verdicts
## Impact (graphify)        consommateurs hors package (impact.json, touched: false) × verdict de Victor (review.json → impact_checked) ; omise sans graphe ; `stale` : tableau gardé, précédé de « Impact : calculé sur le graphe de la base (update en échec) » ; `échec` : la seule ligne « Impact : non calculé (<raison>) »
## Refus des hooks         `python3 ~/.claude/scripts/hook_journal.py summary .claude/fixes/<nom>` tel quel (refus par agent et étape, gates rouges, contournements) ; omise s'il n'imprime rien (ADR 0019)
## Arbitrages               contestations de Fanny et verdicts (si présents)
## Re-gels                  n, par cause (fix.json → refreezes)
## Suggestions             appliquées (id, titre) ; non appliquées : un bloc chacune (problème, si on ne fait rien, correctif, contre)
## Non traité               missing_tests, hors périmètre signalé, acceptations (raisons)
## Dette existante          fix.json → debt (review.json → debt de Victor) : fichier, ligne, problème
## Parcours sur device      le signalement rejoué : symptôme avant (shots/red), état après (shots/green), avec les données utilisées ; ou la raison de device_repro.not_applicable validée par le dev
```

Régénère `fix_gauntlet.sh report <nom> evidence` et donne son chemin avec celui de l'evidence (il
n'est pas commité). **Learn** : `~/.claude/pipeline/learn.md`, en entier (extraire, étiqueter,
proposer les récurrences, appliquer ce que le dev retient ; ne bloque jamais la livraison). Puis,
dans cet ordre :

1. La skill `create_commits` avec « sans validation » et « rien sous `.claude/` » (règle du dev :
   commits créés sans attendre, plan dans l'evidence ; le commit de gel existe déjà ; elle découpe la
   correction).
2. Depuis le worktree : `python3 ~/.claude/scripts/mr.py archive fix <nom> <base_branch>` puis
   `python3 ~/.claude/scripts/mr.py untrack fix <nom> <base_branch>`. Le dossier du fix est copié sous
   `.claude/archive/fixes/<nom>/` du checkout principal (exclu de git, localement), les règles
   `.claude/rules/` changées y sont recopiées, non commitées ; `untrack` retire de la branche, en un
   commit, `repro.json` et `diagnosis.md` commités au gel (le gate a fini de s'en servir). Dis au dev
   les règles recopiées, avec le bloc « ce que tu tranches sans lui ».
3. Écris `.claude/fixes/<nom>/mr.md`, la description de MR, pour un relecteur qui ne connaît ni le
   pipeline ni ses agents : les règles de `~/.claude/pipeline/feature/steps/9_evidence.md`, point 3,
   avec ces sections : **Summary** (le bug vu par l'utilisateur, l'issue), **Changes** (la cause
   racine et la correction, en 2 à 4 puces), **Review focus** si utile (écart au plan, même défaut
   corrigé ailleurs), **Test plan** (le test de reproduction, rouge avant et vert après, et le parcours
   sur device s'il y en a un). Vérifie : `python3 ~/.claude/scripts/mr.py check
   .claude/fixes/<nom>/mr.md <base_branch>`, et ne montre rien au dev avant `ok`.
4. Tu ne pushes rien et ne crées rien d'externe (hormis l'issue validée à l'étape 1) : propose
   `create_mr` au dev, avec `mr.md` comme description (vérifiée, à ne pas regénérer) et l'issue liée
   (`issue.md`, partie C) ; elle appliquera ses propres validations. MR créée → relance
   `mr.py archive fix <nom> <base_branch>` (l'archive prend `mr.md`).

`python3 ~/.claude/scripts/fix/fix.py pass <nom> evidence` (il efface l'attente et retire
`.claude/fixes/.current`), `CronDelete` de `fix.json → watchdog_cron` et
`bash ~/.claude/scripts/watchdog.sh unregister <nom>`.

Sors du worktree avec `ExitWorktree` `action: "keep"` : la branche `fix/<nom>` reste, prête à être
mergée par le dev. Donne-lui la commande de nettoyage à lancer après le merge, sans l'exécuter (le
dossier du fix, non suivi, est archivé : d'où `--force` ; le simulateur du fix part avec) :
`~/.claude/scripts/sim.sh remove fix-<nom>; git worktree remove --force .claude/worktrees/fix-<nom> && git branch -d fix/<nom>`.

Termine par 6 lignes : cause, pourquoi raté, test, correction, learn (règles ajoutées ou « aucune
récurrence »), chemin de l'evidence. Si la cause
racine révèle un piège non évident du projet (un comportement d'API, un invariant), propose en une
ligne de l'enregistrer en mémoire.
