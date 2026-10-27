### 9. Evidence, commits, MR

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
Issue : #<iid> <url>                ← si pipeline.json → issue existe (issue.md, partie C)

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

Puis, **dans cet ordre** : invoque la skill `create_commits` avec « sans validation » (elle découpe le
travail restant en commits atomiques et les crée sans attendre : règle du dev ; le plan va dans
l'evidence ; les commits de contrats et de gel existent déjà), puis la skill `create_mr` en
lui indiquant que la description de MR est `evidence.md` et l'issue liée (`issue.md`, partie C). `create_mr` applique ses propres règles de
validation du dev avant tout push ou création : tu ne les contournes pas.

`pipeline.sh pass <nom> evidence`. Sors du worktree avec `ExitWorktree` `action: "keep"` (la branche reste
pour la MR) et donne la commande de nettoyage à lancer après le merge, sans l'exécuter :
`git worktree remove .claude/worktrees/feature-<nom> && git branch -d feature/<nom>`.
Termine par un résumé de 5 lignes et le chemin de l'evidence.

**Fin : la page de la feature.** Après `pipeline.sh pass <nom> evidence` : `pipeline.sh say <nom> ""`
puis « Rafraîchir » (`~/.claude/pipeline/feature/cockpit.md`) — la carte de l'accueil passe dans
« Terminées ». Puis un seul `AskUserQuestion` : « Supprimer la page de cette feature ? » — « Garder (son
historique : décisions, contrats, rapports) » / « Supprimer ». **Supprimer** → `Artifact` `delete` avec
`cockpit.url` (l'outil lui demande confirmation ; c'est définitif), puis `pipeline.sh page-deleted
<nom>`, puis `pipeline.sh cockpit-push` et le seul `batch` de `hub_writes` sur l'accueil : la carte reste,
marquée « Page supprimée ». Ne supprime jamais la page sans cette question, ni l'accueil, jamais.

