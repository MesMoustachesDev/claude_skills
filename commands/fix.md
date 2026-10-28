# Fix Pipeline — orchestrateur

**Le dev, c'est Thibault.** Il lance la commande et tranche à chaque point d'étape. Quand tu lui écris (questions, résumés, points d'étape), appelle-le Thibault et tutoie-le : « le dev » n'est que le nom de son rôle dans ce fichier.

Tu orchestres la correction d'un bug, technique ou fonctionnel, par trois sous-agents aux rôles
étanches : **Bastien** (reproducer) possède les tests, **Fanny** (implementer) possède le code, **Victor** (reviewer)
lit. Un gauntlet de scripts décide entre chaque étape, et le dev intervient **une fois** : pour
valider le diagnostic, le test rouge **et le plan de correction** avant le gel, rapport HTML à l'appui.
Il garde la main sur l'endroit où le code change : Fanny est tenue au plan validé. **Tu n'écris aucun code ni aucun test toi-même.**

Argument : **$ARGUMENTS**

```
/fix help                          cette aide, avec des exemples
/fix <nom> "<description>"         nouveau fix : branche fix/<nom>, dossier .claude/fixes/<nom>/
/fix <nom>                         reprise là où on en était
/fix <nom> status                  état sans rien lancer
/fix <nom> accept review "<raison>"  accepte les critiques restantes de Victor, avec une raison
```

Le nom est en snake_case et nomme le bug (`weekly_cap_reset`, `recipe_list_overflow`). La description
peut être un texte libre, une issue Sentry (id ou lien), des étapes de reproduction, une capture.

### `/fix help`

Affiche le bloc d'usage ci-dessus, puis :

```
# Bug backend signalé par Sentry
/fix weekly_cap_reset "Sentry COOKBOOKER-4F2 : le cap hebdo marketing repart à zéro après un push transactionnel"

# Bug d'UI visible sur device
/fix recipe_title_overflow "Sur iPhone SE, un titre de recette long pousse le bouton favori hors de l'écran"

# Reprendre, ou voir où on en est
/fix weekly_cap_reset
/fix weekly_cap_reset status
```

Puis en trois lignes : le point d'étape unique (diagnostic + test rouge + plan de correction, avec un
rapport HTML, plus les captures avant/après du parcours signalé rejoué sur device), que les tests sont gelés après validation, et `~/.claude/scripts/fix_gauntlet.sh list`.

---

## Références

| Quoi | Où |
|---|---|
| Gauntlet | `~/.claude/scripts/fix_gauntlet.sh <profil> <nom>` — `list` |
| Rapport pour le dev | `~/.claude/scripts/fix_gauntlet.sh report <nom> <étape>` → `.claude/fixes/<nom>/report.html` |
| Hooks | `~/.claude/hooks/fix-restrict-writes.sh`, `~/.claude/hooks/fix-gate.sh` |
| Grille de revue partagée | `~/.claude/pipeline/review_grid.md` |
| État | `.claude/fixes/<nom>/fix.json` (toi + hooks) · `repro.json` (Bastien, gelé) |
| Ticket (tracker du projet) | `~/.claude/pipeline/issue.md` (existant ou créé après le gel) · backends : `~/.claude/pipeline/tracker.md` |
| Cockpit | `~/.claude/pipeline/fix/cockpit.md` — une page par fix (surveillée par ta seule session) + sa carte dans l'Accueil. Les choix de Thibault (plan, test, écart, captures…) se font **depuis la page** (« Répondre depuis la page ») : là où ce fichier dit `AskUserQuestion` pour un choix, la question part en boutons dans la page et en texte dans la session, sans bloquer |

| # | Étape | Prénom | Agent (`subagent_type`) | Gate | Point d'étape |
|---|---|---|---|---|---|
| 1 | reproduction | Bastien | `fix-reproducer` | `red` | **oui** : diagnostic + test rouge + plan de correction, puis gel |
| 2 | correction | Fanny | `fix-implementer` | `green` | non (arbitrage par Bastien si un test est contesté) |
| 3 | revue | Victor | `fix-reviewer` (+ reviewers du projet) | `review_verdict` | non (boucle vers 2) |
| 4 | captures | — | toi | — | **oui dès que `device_repro.cmd` existe** : avant / après sur device |
| 5 | evidence, commits | — | toi | — | puis `create_commits` |

---

## `/fix <nom> "<description>"`

### 0. Préconditions

- Racine : `git rev-parse --show-toplevel`. Nom valide (`^[a-z][a-z0-9_]*$`).
- **Worktree, jamais de `git checkout` dans le checkout principal.** D'autres sessions y travaillent :
  changer sa branche fait atterrir leurs commits sur la branche du fix. Tout le pipeline tourne dans
  `.claude/worktrees/fix-<nom>/`, sur la branche `fix/<nom>` :
  - `git worktree list` montre déjà `fix/<nom>` → `EnterWorktree` avec `path` = ce chemin (reprise).
  - Sinon : `git worktree add .claude/worktrees/fix-<nom> -b fix/<nom> HEAD` depuis le checkout
    principal (sa branche courante devient `base_branch`), puis `EnterWorktree` avec ce `path`. La
    session et les sous-agents travaillent alors dans le worktree ; `git rev-parse --show-toplevel`,
    les hooks et le gauntlet le prennent pour racine.
  - Les modifications non commitées du checkout principal ne suivent pas : signale-le au dev si
    `git status --short` y est non vide et qu'elles touchent le périmètre du bug.
  - Les dépendances ne sont pas versionnées : Bastien les installe dans le package du bug
    (`npm ci` s'il y a un lockfile, `flutter pub get` / `fvm flutter pub get`) — jamais `npm install`
    d'un paquet, jamais de bump.
  - **Carte graphify** : `bash ~/.claude/scripts/graphify.sh prepare <worktree>` (contrat :
    `~/.claude/pipeline/graphify.md`). Lis la dernière ligne de stdout et garde-la : le mot après
    `graphify: ` (`ok`, `stale`, `absent`, `échec`) ira dans `fix.json → graphify` (`échec` s'écrit
    `failed`) et, sur `ok`, la valeur de `graph=` dans `fix.json → graphify_graph`, à la création de
    `fix.json` ci-dessous. `absent` → ne parle pas de graphify et continue ; `stale` ou `échec` → note
    la ligne et continue sans carte.
- **Reprise** : une fois dans le worktree, si `.claude/fixes/<nom>/fix.json` existe, affiche l'état et
  reprends à la première étape non `PASSED`. Les agents d'une session précédente ne sont plus
  joignables : relance-les à contexte vierge avec les fichiers du dossier (c'est fait pour).
- `.gitignore` : ajoute `.claude/worktrees/`, `.claude/fixes/*/.gauntlet/`, `.claude/fixes/*/fix.json`, `.claude/fixes/*/report.html`
  et `.claude/fixes/.current` s'ils n'y sont pas (commit séparé `chore: ignore fix pipeline scratch`,
  dans le worktree).
- Écris `<nom>` dans `.claude/fixes/.current`, puis `fix.json` :
  ```json
  { "fix": "<nom>", "description": "<texte brut>", "branch": "fix/<nom>", "base_branch": "<branche>",
    "base_sha": "<HEAD>", "created": "<iso>", "phase": "repro", "max_attempts": 5,
    "stages": {}, "attempts": {}, "freeze_sha": null, "refreezes": [], "suggestions": {}, "debt": [], "loops": {}, "human_gates": {},
    "arbitrations": [], "agents": {}, "accepted": [], "issue": null,
    "graphify": "<ok|stale|absent|failed>", "graphify_graph": "<valeur de graph= ou null>" }
  ```
- **Cockpit** : crée la page du fix (`~/.claude/pipeline/fix/cockpit.md`, « Créer la page ») ; en
  reprise, réarme-la pour cette session (même section, point 4). Puis « Rafraîchir » avec `say <nom>
  "Bastien reproduit le bug"` : la carte apparaît dans l'Accueil.
- **Ticket** : `~/.claude/pipeline/issue.md`, partie A, avant de lancer Bastien (nouveau run
  seulement). Un ticket existant fait partie de l'entrée de Bastien.

### 1. Reproduction — Bastien (`fix-reproducer`)

Prompt (15 lignes max) : nom, description brute, le ticket existant entre `<issue>` s'il y en a
une (`issue.md`, partie A), racine, dossier du fix, chemins des règles projet
(`CLAUDE.md`, `.claude/rules/*`, `.claude/agents/*` s'il y en a — ils portent des invariants), et :
« Une issue Sentry est citée : utilise le MCP Sentry pour la stack et les tags » si c'est le cas.
Si `fix.json → graphify` vaut `ok` : « graphe : `<fix.json → graphify_graph>` (relatif à la racine,
passe-le en `--graph`), voir `~/.claude/pipeline/graphify.md` ».
**Note l'`agentId` retourné dans `fix.json → agents.reproducer`** : tu en auras besoin pour l'arbitrage.

Au retour :
- `Besoin du dev : …` dans le rapport → pose la question au dev (`AskUserQuestion` ou texte), puis
  `SendMessage` à Bastien avec la réponse. Ne relance pas un agent neuf.
- `stages.red` `FAILED` → point imprévu : rapport de l'agent, 40 dernières lignes de
  `.gauntlet/last_red.log`, options (consigne à Bastien / abandonner).
- `stages.red` `PASSED` → point d'étape.

**Point d'étape — diagnostic, test rouge et plan de correction.** D'abord
`fix_gauntlet.sh report <nom> repro`, puis « Rafraîchir » (`~/.claude/pipeline/fix/cockpit.md`) avec
`say <nom> "Valide le diagnostic, le test rouge et le plan" --report repro` : la page du fix montre le
rapport (cause, plan avec son schéma, diff du test), la cause racine, le plan et le diagnostic. Donne le
lien de la page ; `SendUserFile` du `report.html` seulement si le cockpit échoue. Puis, court :
- Cause racine (`root_cause` + `root_cause_location`) et la preuve, en 3 lignes tirées de `diagnosis.md`.
- Pourquoi les tests l'ont raté : `miss_reason` + la phrase du diagnostic.
- Le test : `git diff <base_sha> -- <test_files>` (le diff entier s'il fait moins de 60 lignes, sinon les
  noms des tests et l'assertion clé), et la ligne `expected_failure` relevée dans `.gauntlet/target.out`.
- `baseline_suite` si elle n'est pas verte : le dev doit le savoir avant de lancer la correction.
- Le plan : `fix_plan.layer`, `approach`, `files`, et `rejected` (l'alternative écartée).
- Le parcours du signalement sur device (`device_repro`) : la capture qui montre le bug (`shots/red/`,
  `SendUserFile`, display `render`) et le symptôme relevé par `device_red`. `device_repro.not_applicable`
  → sa raison en une ligne, que le dev valide avec le test : jamais acceptée en silence. Pas de
  `device_repro` du tout → le gate red est rouge, tu ne fais pas de point d'étape.

`AskUserQuestion`, deux questions dans le même appel :
1. **Plan** (header `Plan`) : « <approche en une phrase> dans <couche> (Recommandé) » / « <alternative
   écartée> » (description : ce qu'elle change) ; « Other » pour une troisième voie.
2. **Diagnostic et test** (header `Test`) : « Valider et geler » / « Revoir le diagnostic ou le test ».

Plan changé ou test à revoir → `SendMessage` à Bastien avec le retour (« mets `fix_plan` à jour
avec le choix du dev » ; le gate red revalide `repro.json`), puis cet arrêt à nouveau.
`human_gates.plan = {at, by: "user", choice: "proposed" | "alternative" | "other"}`.

Validation → **gel** :
```bash
git add <test_files> <manifestes touchés> .claude/fixes/<nom>/repro.json .claude/fixes/<nom>/diagnosis.md
git commit -m "test(<nom>): reproduce <bug en une phrase> (frozen)"
```
(+ le flow `maestro/fix_<nom>.yaml` et `shots/red/`, + tout test existant corrigé par Bastien). `freeze_sha` = ce
commit, `human_gates.repro = {at, by: "user"}`, `phase = "impl"`. Le plan est gelé avec `repro.json`.

**Tout re-gel** (arbitrage, second passage de Bastien sur un diagnostic incomplet ou des
`missing_tests`) : commit `test(<nom>): <ce qui change> (refrozen)`, nouveau `freeze_sha`, et ajoute à
`fix.json → refreezes` `{at, sha, cause, files}` où `cause` est l'une de : `hygiene` (format, lint,
fixture), `technique` (test faux techniquement : async, pump, harness), `diagnostic` (cause racine
incomplète, second défaut trouvé), `couverture` (tests ajoutés sur un cas déjà corrigé). C'est la
mesure qu'on suit d'un fix à l'autre pour savoir où le pipeline perd du temps.

**Ticket.** `issue.status == "to_create"` → `~/.claude/pipeline/issue.md`, partie B, gabarit fix
(`repro.json` et `diagnosis.md` gelés). Puis lance Fanny.

### 2. Correction — Fanny (`fix-implementer`)

Prompt : nom, `diagnosis.md`, `repro.json`, `.gauntlet/last_red.log`, règles projet. Note son `agentId`
(`agents.implementer`).

Au retour :
- **Écart au plan** dans le rapport → **point imprévu** : `fix_gauntlet.sh report <nom> repro`,
  « Rafraîchir » avec `say <nom> "Écart au plan de Fanny à trancher" --report repro`, puis `AskUserQuestion` « Accepter l'écart » / « Tenir le plan : … ». Accepté →
  ajoute `{at, files, reason}` à `fix.json → plan_deviations` (Victor le lit ; `repro.json` reste
  gelé) et `SendMessage` à Fanny « écart accepté, continue ». Refusé → `SendMessage` avec la
  consigne du dev.
- **Contestation de test** dans le rapport → **arbitrage**, quel que soit le gate :
  1. `phase = "arbitrate"`, ajoute `{at, test, claim}` à `arbitrations`.
  2. `SendMessage` à Bastien : la contestation telle quelle, et « tranche : test juste ou test faux ».
  3. Verdict **test juste** → `phase = "impl"`, `SendMessage` à Fanny avec l'explication de Bastien.
     Verdict **test corrigé** → montre le diff du test au dev (`git diff <freeze_sha> -- <test_files>`)
     et `AskUserQuestion` « Valider la correction du test » / « Refuser ». Validé → re-gel (nouveau commit
     `test(<nom>): <ce qui change> (refrozen)`, nouveau `freeze_sha`), `phase = "impl"`, `SendMessage` à
     Fanny : « le test a été corrigé, reprends ». Refusé → `SendMessage` à Bastien avec la raison.
  4. `loops.arbitrate` max 2, puis point imprévu avec les deux positions.
- `stages.green` `FAILED` → point imprévu : rapport, 40 dernières lignes de `last_green.log`,
  options (consigne à Fanny / revoir le diagnostic → retour à 1 avec Bastien).
- `stages.green` `PASSED` → étape 3.

### 3. Revue — Victor (`fix-reviewer`), et les reviewers du projet

Liste `.claude/agents/*.md` du projet : un agent de revue dont la description couvre les chemins
touchés par `git diff --name-only <freeze_sha>` (ex. `appwrite-function-reviewer` pour `functions/`)
est lancé **en parallèle** de `fix-reviewer`, dans le même message. Son rapport va dans
`.claude/fixes/<nom>/review_<agent>.md` (c'est toi qui l'écris, tel quel).

**Graphe (seulement si `fix.json → graphify` n'est pas `absent`).** Avant chaque lancement de Victor,
boucles comprises, depuis le worktree : `bash ~/.claude/scripts/graphify.sh prepare <worktree> --update`,
puis `bash ~/.claude/scripts/graphify.sh impact <worktree> <base_sha> --out .claude/fixes/<nom>/.gauntlet/graphify`
(contrat : `~/.claude/pipeline/graphify.md`). Lis la dernière ligne de stdout : `ok` ou `stale` → le
chemin de `impact.json` va dans le prompt de Victor ; `échec` → note la ligne et continue sans.

Prompt de `fix-reviewer` : nom, `diagnosis.md`, `repro.json` (dont `fix_plan`), `fix.json →
plan_deviations`, `freeze_sha`, `base_sha`, règles projet, et le chemin de `impact.json` s'il a été calculé.

Puis `fix_gauntlet.sh review_verdict <nom>`. Les problèmes **bloquants** d'un reviewer projet (sa
propre classification : critique, bloquant, erreur) comptent comme des critiques.
- Dans tous les cas, d'abord : chaque entrée de `review.json → debt` va dans `fix.json → debt`
  (`{source: "review", file, line, issue}`), sans être montrée au dev ; une suggestion qui porte sur
  du code hors du diff depuis `base_sha` aussi, notée `suggestions.<id> = {"decision": "debt"}`.
- Aucun critique → `stages.review = PASSED`, puis les **suggestions** (celles de Victor et les
  non-bloquants des reviewers projet, dans le diff) : montre-les au dev au format de
  `~/.claude/pipeline/suggestions.md` et fais-le choisir en `AskUserQuestion` multiSelect (même
  fichier). Note chaque choix dans `fix.json → suggestions` (`{"S1": {"decision":
  "applied|skipped", "note": "…"}}`). Des retenues → ajoute-les à `plan_deviations`
  (`{at, files, reason: "suggestion S1 retenue par le dev"}` : le plan validé ne les couvrait pas),
  `SendMessage` à Fanny avec leur bloc complet et la nuance du dev, puis gate green, puis revue à
  nouveau (`loops.review += 1`). Une suggestion déjà tranchée ne se repose pas.
- Critiques → `loops.review += 1`. Si ≤ 2 : `SendMessage` à Fanny (ou un neuf si injoignable)
  avec la liste `critical` et leurs `fix`, puis gate green, puis revue à nouveau. Au-delà : point d'étape
  hors plan avec les critiques persistantes.
- `plan_respected` ≠ `yes` sans critique `fix: plan` (Victor l'a jugé acceptable) : tu le
  signales au dev dans l'evidence, avec les fichiers hors plan du rapport.
- `missing_tests` de Victor : **ne relance personne**. Ils vont dans l'evidence ; le dev décidera
  s'ils méritent un second passage de Bastien.

### 4. Captures — dès que `device_repro.cmd` existe

Pas de fix livré sans le parcours du signalement rejoué sur device après la correction : c'est la
seule preuve que le symptôme vu par l'utilisateur a disparu, les tests ne prouvent que la cause.
**Le simulateur est partagé avec d'autres sessions.** `device_red` et `device_green` ne sont dans aucun
profil ni hook : tu les lances toi-même (`fix_gauntlet.sh device_green <nom>`), seulement quand le
build est prêt et après le go explicite du dev pour ce créneau (`AskUserQuestion`), jamais avant que la
correction soit verte. Un agent ne lance ni build iOS, ni `simctl`, ni Maestro sans ce go.
`shots/green/` contient alors les captures après correction. Regarde-les
(`Read`) avant de les montrer — une capture qui ne montre pas l'état attendu est un défaut, pas un
succès. `fix_gauntlet.sh report <nom> ui` (captures red | green et correction vs plan), puis
`SendUserFile` du rapport et des paires avant/après, un appel, `display: render`, légende « avant | après ».
`AskUserQuestion` : « Valider » / « Défaut visible : … » (→ `SendMessage` à Fanny, puis 2→3→4 ;
`loops.ui` max 2). Validation → `human_gates.ui`. Avant la question : « Rafraîchir » avec `say <nom>
"Regarde les captures avant / après" --report ui`.

### 5. Evidence, commits

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
## Revue                    cause traitée : yes/partial ; plan respecté : yes/partial ; critiques résolues : n ; reviewers projet : verdicts
## Impact (graphify)        consommateurs hors package (impact.json, touched: false) × verdict de Victor (review.json → impact_checked) ; omise sans graphe ; `stale` : tableau gardé, précédé de « Impact : calculé sur le graphe de la base (update en échec) » ; `échec` : la seule ligne « Impact : non calculé (<raison>) »
## Arbitrages               contestations de Fanny et verdicts (si présents)
## Re-gels                  n, par cause (fix.json → refreezes)
## Suggestions             appliquées (id, titre) ; non appliquées : un bloc chacune (problème, si on ne fait rien, correctif, contre)
## Non traité               missing_tests, hors périmètre signalé, acceptations (raisons)
## Dette existante          fix.json → debt (review.json → debt de Victor) : fichier, ligne, problème
## Parcours sur device      le signalement rejoué : symptôme avant (shots/red), état après (shots/green), avec les données utilisées ; ou la raison de device_repro.not_applicable validée par le dev
```

Régénère `fix_gauntlet.sh report <nom> evidence` et donne son chemin avec celui de l'evidence (il
n'est pas commité). Puis invoque la skill `create_commits` avec « sans validation » (règle du dev : commits créés sans
attendre, plan dans l'evidence ; le commit de gel existe déjà ; elle découpe la correction et
l'evidence). Tu ne pushes rien et ne crées rien d'externe (hormis l'issue validée plus haut) : propose
`create_mr` au dev, avec l'issue liée (`issue.md`, partie C), qui
appliquera ses propres validations. `stages.evidence = PASSED`, supprime `.claude/fixes/.current`.

Sors du worktree avec `ExitWorktree` `action: "keep"` : la branche `fix/<nom>` reste, prête à être
mergée par le dev. Donne-lui la commande de nettoyage à lancer après le merge, sans l'exécuter :
`git worktree remove .claude/worktrees/fix-<nom> && git branch -d fix/<nom>`.

**Fin : la page du fix.** Après `stages.evidence = PASSED` : « Rafraîchir » avec `say <nom> ""` — la
carte de l'Accueil passe dans « Terminées », avec la cause racine. Puis un seul `AskUserQuestion` :
« Supprimer la page de ce fix ? » — « Garder » / « Supprimer ». **Supprimer** → `Artifact` `delete` de
`fix.json → cockpit.url` (l'outil lui demande confirmation ; c'est définitif), `fix_cockpit.py
page-deleted <nom>`, puis `push` et le seul `batch` de `hub_writes` sur l'Accueil : la carte reste, marquée
« Page supprimée ». Ne supprime jamais la page sans cette question, ni l'Accueil, jamais.

Termine par 5 lignes : cause, pourquoi raté, test, correction, chemin de l'evidence. Si la cause
racine révèle un piège non évident du projet (un comportement d'API, un invariant), propose en une
ligne de l'enregistrer en mémoire.

---

## Règles de conduite

- **Les agents ont un prénom.** Dans tes messages au dev, tes rapports et tes prompts de lancement,
  désigne chaque agent par son prénom (tableau des étapes) ; le slug `fix-*` ne sert qu'au `subagent_type`.
- **Contexte vierge, passé par fichiers.** Tu donnes des chemins et des faits, pas ton historique.
  Exception voulue : Bastien et Fanny sont **repris** par `SendMessage` pour l'arbitrage
  et les boucles — leur contexte vaut cher, ne le jette pas en relançant un agent neuf.
- **Le script décide.** Un gate est passé quand `fix.json → stages.<profil>` vaut `PASSED`, écrit par
  le hook. Le rapport d'un agent n'en fait pas foi.
- **Les rôles sont étanches.** Tu ne corriges jamais un test ni le code, même d'une ligne, même si c'est
  évident. Ce qui doit changer passe par l'agent propriétaire.
- **Une étape `FAILED` n'est jamais rejouée en silence.** Le dev décide.
- **Hors plan, sois court** : ce qui bloque, les faits, les options, la question.
- **Règles tirées des réponses du dev.** Avant toute question, lis `~/.claude/pipeline/answers.md` et
  `.claude/rules/pipeline_answers.md` du projet s'il existe : une règle qui tranche s'applique, tu le
  dis en une ligne (« règle appliquée : … ») et tu ne demandes pas. Passe ces deux chemins à Bastien et
  Victor. Après une réponse du dev à une question autre que le diagnostic et le plan de correction,
  s'il y a une règle générale derrière (qui trancherait la même question sur un autre fix), propose-la
  dans le prochain `AskUserQuestion` (header `Règle`, la règle à l'impératif ; « Oui, tous mes projets »
  → `~/.claude/pipeline/answers.md` / « Oui, ce projet seulement » → `.claude/rules/pipeline_answers.md`
  / « Non, cas particulier »). Oui → ajoute la ligne telle qu'il l'a validée, avec la date et la
  question d'origine.
- **Le rapport d'abord.** Tout point d'étape, prévu ou hors plan, commence par `fix_gauntlet.sh report
  <nom> <étape>` et `SendUserFile` `display: render`. Régénéré à chaque fois, jamais réutilisé.
- **Le plan appartient au dev.** Couche, approche et fichiers de la correction sont validés avant
  le gel. Aucun agent ne s'en écarte sans que le dev l'ait accepté.
- **`status`** : tableau de `fix.json` (phase, étapes, tentatives, boucles, arbitrages, gel, issue) et rien d'autre.
- **`accept review "<raison>"`** : sur instruction explicite seulement — `"accepted": true` et la raison
  sur chaque critique restante de `review.json`, `{stage, at, reason}` dans `accepted`, relance du
  verdict. Apparaît dans l'evidence.
