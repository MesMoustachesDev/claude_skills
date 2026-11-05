### 9. Evidence, commits, MR

`evidence.md` est la page du dev ; la MR a sa propre description, `mr.md` (point 3 plus bas).

**9a. Graphe graphify (seulement si le projet en a un).** Contrat : `~/.claude/pipeline/graphify.md`.
Depuis le worktree :
`bash ~/.claude/scripts/graphify.sh prepare <worktree> --update`, puis
`bash ~/.claude/scripts/graphify.sh impact <worktree> <base> --out .claude/features/<nom>/.gauntlet/graphify`
(`<base>` = le merge-base de la branche de base). La dernière ligne de stdout donne l'état :
- `absent` → saute 9a, pas de section « Impact » dans l'evidence.
- `ok` → la section « Impact » reprend le tableau « Consommateurs hors package non touchés » de
  `impact.md` (package consommateur, symboles touchés, via). `impact.md` ne remplace pas le `grep` des
  usages d'un symbole modifié.
- `stale` → section « Impact » : le même tableau, précédé de la ligne « Impact : calculé sur le graphe
  de la base (update en échec) » ; les symboles ajoutés par le diff manquent, une absence de
  consommateur ne prouve rien.
- `échec` → ligne « Impact : non calculé (<raison>) ».
graphify ne bloque jamais la livraison.

Le graphe mis à jour reste dans le worktree. Celui du checkout principal sera rafraîchi au
démarrage de la prochaine feature (étape 0).

Écris `.claude/features/<nom>/evidence.md` — la page que le dev lit à la place du code :

```
# Evidence — <nom>
Spec validée le <date> · Branche feature/<nom> · Base <base>@<sha>
Gabarit : <S|M> (<size_reason>)      ← pipeline.json → size ; reclassements : size_changes (de → vers, raison)
Ticket : <ref> <url>                ← si pipeline.json → issue existe (issue.md, partie C) ; sous-feature : + « Epic : <ref> »

## Étapes sautées (gabarit)          ← pipeline.json → stages, status SKIPPED ; omise en M sans étape sautée
| Étape | Raison |

## Contrats (écrits par Thibault)    ← pipeline.json → contracts (draft_sha → sha), git diff --stat entre les deux
<n> fichiers · <n> décisions d'Arthur tranchées dans le code · commit <sha>
| ID | Package et dépendances (§9) | Statut |

## Arbre du changement             ← change_tree.py <merge-base> (worktree) + le rôle de chaque fichier, repris de 8b
```
<l'arbre, une ligne par fichier, rôle compris>
```

## Visite guidée                     ← review.json → tour, human_gates.tour
| # | Fichier:ligne | Ce que fait le code | Implémente |

## Acceptation
| Scénario | Widget test | Android | iOS |   ← §4 × tests.md × qa.md ; en S, « — (gabarit S) » sur la plateforme non jouée

## Mesures
Tests : <n> (dont <n> ajoutés par Hugo) · Couverture lignes modifiées : <n>%
Mutation : <n>% (<n> mutants, <n> survivants expliqués) | sautée (gabarit S) · Complexité max : <n> · Dépendances : ✓
Revue : <n> critiques (résolues), <n> suggestions · Règles projet : <n>/<n> · Maintenabilité : <n>/8

## Maintenabilité                    ← last_maintain.log + review.json → rules_checked.maintainability
Dépendances inter-features : <liste, justifiées §8> · Packages ajoutés : <liste avec date de release>
Roue réinventée : <n> paires jugées, <n> doublons résolus, <n> verdicts acceptés par le dev (<raisons>)   ← dedup.json
Widgets vs design system : <n> comparés, <n> remplacés, <n> extensions du DS                              ← dedup.json
Exemptions gauntlet-ignore : <n> (<où>)

## Impact (graphify)                  ← 9a, seulement si le projet a un graphe ; tableau tiré de impact.md
| Package consommateur | Symboles touchés | Via |
`stale` : tableau gardé, précédé de « Impact : calculé sur le graphe de la base (update en échec) ».
`échec` : une seule ligne à la place du tableau, « Impact : non calculé (<raison>) ». `absent` : pas de section.

## Dette existante (hors feature)       ← pipeline.json → debt + .gauntlet/debt_deps.txt
| Fichier | Problème | Vu par (spec, gate, revue) |
Puis propose au dev une session séparée par lot cohérent (start_session, own_initiative) : la dette
n'est pas corrigée dans la feature, mais elle ne se perd pas.

## Dépendances à traiter hors feature   ← review.json → dependencies
| Package | Problème | Alternative | Fichiers | Risque | Verdict |

## Qualité des entrées               ← spec_review.json, tests_review.json
Spec : <n> bloquants corrigés avant validation, <n> notes · Tests : <n>/<n> scénarios couverts, <n> bloquants corrigés avant gel
Re-gels : <n> (hygiene <n> · technique <n> · contrat <n> · spec <n> · interne <n>)   ← pipeline.json → refreezes

## Suggestions non appliquées        ← review.json + pipeline.json → suggestions `skipped` (pas `debt`) : un bloc par suggestion (problème, si on ne fait rien, correctif, contre)
## Mutants expliqués                 ← mutants.md
## Défauts visuels mineurs           ← qa.md
## Polish visuel                     ← human_gates.polish (decision) + polish.md : IDs faits, captures avant / après ; « non demandé » si skipped
## Captures                          ← chemins relatifs
```

**9b. Learn.** `~/.claude/pipeline/learn.md`, en entier : extraire, étiqueter, proposer les récurrences à
Thibault, appliquer ce qu'il retient. Ne bloque jamais la livraison.

Puis, **dans cet ordre** :

1. **Commits.** Invoque la skill `create_commits` avec « sans validation » et « rien sous `.claude/` »
   (elle découpe le travail restant en commits atomiques et les crée sans attendre : règle du dev ; le
   plan va dans l'evidence ; les commits de contrats et de gel existent déjà). Les documents du run et
   les règles ajoutées par learn ne partent pas dans la MR.
2. **Archive et nettoyage de la branche**, depuis le worktree :
   `python3 ~/.claude/scripts/mr.py archive feature <nom> <base>` puis
   `python3 ~/.claude/scripts/mr.py untrack feature <nom> <base>` (`<base>` = `pipeline.json → base`).
   Le dossier du run est copié dans le checkout principal, sous `.claude/archive/features/<nom>/`
   (exclu de git, localement) ; une règle `.claude/rules/` changée par le run y est recopiée, non
   commitée. `untrack` ramène `.claude/` à son état de la base en un commit. Dis au dev, avec le bloc
   « ce que tu tranches sans lui », les règles recopiées : il les commitera à part s'il les garde.
3. **La description de MR : `.claude/features/<nom>/mr.md`, pas `evidence.md`.** Elle est écrite pour
   un relecteur de l'équipe qui ne connaît ni le pipeline, ni ses agents, ni ce que le dev a répondu.
   Gabarit et langue : ceux de `create_mr_rules.md` du projet. Contenu :
   - le ticket, là où le gabarit le met (`Related issue`), dans la syntaxe des règles (cross-projet
     comprise) : `issue.md`, partie C, `Closes`/`Relates to`, et pour une sous-feature d'epic le
     ticket de l'epic aussi ;
   - **Summary** : pourquoi la MR existe, en 2 à 4 puces, en termes de comportement pour l'utilisateur ;
   - **Changes** : 3 à 6 puces par package ou couche, ce qui change et pourquoi (pas la liste des
     fichiers, pas l'arbre du changement) ;
   - **Review focus** (si utile) : les choix qui méritent un œil (décisions de §9, dépendance gardée
     ou retirée, consommateurs hors package touchés, migration de données), au plus 5 puces ;
   - **Test plan** : les scénarios d'acceptation regroupés, comment les rejouer (tests, flows Maestro
     du package), et une ligne de chiffres (tests, couverture des lignes modifiées).

   Jamais : un prénom d'agent ou du dev, ce que le dev a répondu, le vocabulaire du pipeline (gel,
   gabarit, gauntlet, evidence…), un chemin `.claude/`, la dette, les mutants, les incidents
   d'outillage. Tout ça reste dans `evidence.md`. Au plus 60 lignes.
   Vérifie : `python3 ~/.claude/scripts/mr.py check .claude/features/<nom>/mr.md <base>`. Chaque refus
   se corrige dans `mr.md` (ou dans la branche s'il vise un fichier `.claude/`), puis on revérifie ;
   on ne montre pas la MR au dev avant `ok`.
4. **MR.** La skill `create_mr`, en lui indiquant que la description est `mr.md` (vérifiée, à ne pas
   regénérer) et la **branche cible** : `pipeline.json → base` (`feature/<epic>` pour une sous-feature
   d'epic, jamais `base_branch` à sa place). `create_mr` applique ses propres règles de validation du
   dev avant tout push ou création : tu ne les contournes pas. MR créée → relance
   `mr.py archive feature <nom> <base>` : l'archive prend `mr.md` et l'état final.

`pipeline.sh pass <nom> evidence`. **Arrête le watchdog** : `CronDelete` de `watchdog_cron`, puis
`bash ~/.claude/scripts/watchdog.sh unregister <nom>` (le scan hors session retire aussi seul une feature
terminée). Sors du worktree avec `ExitWorktree` `action: "keep"` (la branche reste
pour la MR) et donne la commande de nettoyage à lancer après le merge, sans l'exécuter (le dossier du
run, non suivi, est archivé : d'où `--force` ; le simulateur QA de la feature part avec) :
`~/.claude/scripts/sim.sh remove feature-<nom>; git worktree remove --force .claude/worktrees/feature-<nom> && git branch -d feature/<nom>`.
`qa_devices.<pf>.mode = reuse` : l'appareil n'appartient pas à la feature, retire `sim.sh remove` de la
commande. Android `fresh` ou `prepared` : ajoute `adb -s $(cat .claude/features/<nom>/.gauntlet/android_serial) emu kill`
(instance jetable, rien à supprimer de l'AVD).
Termine par un résumé de 5 lignes (la dernière : learn, règles ajoutées ou « aucune récurrence »), le chemin de l'evidence et l'URL de la MR.

**Fin : la page de la feature.** Après `pipeline.sh pass <nom> evidence` : `pipeline.sh say <nom> ""`
puis « Rafraîchir » (`~/.claude/pipeline/feature/cockpit.md`) — la carte de l'accueil passe dans
« Terminées ». Puis un seul `AskUserQuestion` : « Supprimer la page de cette feature ? » — « Garder (son
historique : décisions, contrats, rapports) » / « Supprimer ». **Supprimer** → `Artifact` `delete` avec
`cockpit.url` (l'outil lui demande confirmation ; c'est définitif), puis `pipeline.sh page-deleted
<nom>`, puis `pipeline.sh cockpit-push` et le seul `batch` de `hub_writes` sur l'accueil : la carte reste,
marquée « Page supprimée ». Ne supprime jamais la page sans cette question, ni l'accueil, jamais.

