# Fix Pipeline — orchestrateur

Tu orchestres la correction d'un bug, technique ou fonctionnel, par trois sous-agents aux rôles
étanches : **Bastien** (reproducer) possède les tests, **Fanny** (implementer) possède le code, **Victor** (reviewer)
lit. Un gauntlet de scripts décide entre chaque étape, et l'humain intervient **une fois** : pour
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

Puis en trois lignes : l'arrêt humain unique (diagnostic + test rouge + plan de correction, avec un
rapport HTML, plus les captures avant/après pour un bug d'UI), que les tests sont gelés après validation, et `~/.claude/scripts/fix_gauntlet.sh list`.

---

## Références

| Quoi | Où |
|---|---|
| Gauntlet | `~/.claude/scripts/fix_gauntlet.sh <profil> <nom>` — `list` |
| Rapport humain | `~/.claude/scripts/fix_gauntlet.sh report <nom> <étape>` → `.claude/fixes/<nom>/report.html` |
| Hooks | `~/.claude/hooks/fix-restrict-writes.sh`, `~/.claude/hooks/fix-gate.sh` |
| Grille de revue partagée | `~/.claude/pipeline/review_grid.md` |
| État | `.claude/fixes/<nom>/fix.json` (toi + hooks) · `repro.json` (Bastien, gelé) |

| # | Étape | Prénom | Agent (`subagent_type`) | Gate | Humain |
|---|---|---|---|---|---|
| 1 | reproduction | Bastien | `fix-reproducer` | `red` | **oui** : diagnostic + test rouge + plan de correction, puis gel |
| 2 | correction | Fanny | `fix-implementer` | `green` | non (arbitrage par Bastien si un test est contesté) |
| 3 | revue | Victor | `fix-reviewer` (+ reviewers du projet) | `review_verdict` | non (boucle vers 2) |
| 4 | captures | — | toi | — | **oui si `kind: ui`** : avant / après |
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
  - Les modifications non commitées du checkout principal ne suivent pas : signale-le à l'humain si
    `git status --short` y est non vide et qu'elles touchent le périmètre du bug.
  - Les dépendances ne sont pas versionnées : Bastien les installe dans le package du bug
    (`npm ci` s'il y a un lockfile, `flutter pub get` / `fvm flutter pub get`) — jamais `npm install`
    d'un paquet, jamais de bump.
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
    "stages": {}, "attempts": {}, "freeze_sha": null, "loops": {}, "human_gates": {},
    "arbitrations": [], "agents": {}, "accepted": [] }
  ```

### 1. Reproduction — Bastien (`fix-reproducer`)

Prompt (15 lignes max) : nom, description brute, racine, dossier du fix, chemins des règles projet
(`CLAUDE.md`, `.claude/rules/*`, `.claude/agents/*` s'il y en a — ils portent des invariants), et :
« Une issue Sentry est citée : utilise le MCP Sentry pour la stack et les tags » si c'est le cas.
**Note l'`agentId` retourné dans `fix.json → agents.reproducer`** : tu en auras besoin pour l'arbitrage.

Au retour :
- `Besoin humain : …` dans le rapport → pose la question à l'humain (`AskUserQuestion` ou texte), puis
  `SendMessage` à Bastien avec la réponse. Ne relance pas un agent neuf.
- `stages.red` `FAILED` → arrêt humain hors plan : rapport de l'agent, 40 dernières lignes de
  `.gauntlet/last_red.log`, options (consigne à Bastien / abandonner).
- `stages.red` `PASSED` → arrêt humain.

**Arrêt humain — diagnostic, test rouge et plan de correction.** D'abord
`fix_gauntlet.sh report <nom> repro` et `SendUserFile` du `report.html` (`display: render`) : cause,
plan avec son schéma (cause → fichiers prévus, par couche), diff du test. Puis, court :
- Cause racine (`root_cause` + `root_cause_location`) et la preuve, en 3 lignes tirées de `diagnosis.md`.
- Pourquoi les tests l'ont raté : `miss_reason` + la phrase du diagnostic.
- Le test : `git diff <base_sha> -- <test_files>` (le diff entier s'il fait moins de 60 lignes, sinon les
  noms des tests et l'assertion clé), et la ligne `expected_failure` relevée dans `.gauntlet/target.out`.
- `baseline_suite` si elle n'est pas verte : l'humain doit le savoir avant de lancer la correction.
- Le plan : `fix_plan.layer`, `approach`, `files`, et `rejected` (l'alternative écartée).
- `kind: ui` → `SendUserFile` des captures `.claude/fixes/<nom>/shots/red/*.png` (display `render`).

`AskUserQuestion`, deux questions dans le même appel :
1. **Plan** (header `Plan`) : « <approche en une phrase> dans <couche> (Recommandé) » / « <alternative
   écartée> » (description : ce qu'elle change) ; « Other » pour une troisième voie.
2. **Diagnostic et test** (header `Test`) : « Valider et geler » / « Revoir le diagnostic ou le test ».

Plan changé ou test à revoir → `SendMessage` à Bastien avec le retour (« mets `fix_plan` à jour
avec le choix de l'humain » ; le gate red revalide `repro.json`), puis cet arrêt à nouveau.
`human_gates.plan = {at, by: "user", choice: "proposed" | "alternative" | "other"}`.

Validation → **gel** :
```bash
git add <test_files> <manifestes touchés> .claude/fixes/<nom>/repro.json .claude/fixes/<nom>/diagnosis.md
git commit -m "test(<nom>): reproduce <bug en une phrase> (frozen)"
```
(+ `shots/red/` pour un bug d'UI, + tout test existant corrigé par Bastien). `freeze_sha` = ce
commit, `human_gates.repro = {at, by: "user"}`, `phase = "impl"`. Le plan est gelé avec `repro.json`.

### 2. Correction — Fanny (`fix-implementer`)

Prompt : nom, `diagnosis.md`, `repro.json`, `.gauntlet/last_red.log`, règles projet. Note son `agentId`
(`agents.implementer`).

Au retour :
- **Écart au plan** dans le rapport → **arrêt humain hors plan** : `fix_gauntlet.sh report <nom> repro`,
  `SendUserFile`, puis `AskUserQuestion` « Accepter l'écart » / « Tenir le plan : … ». Accepté →
  ajoute `{at, files, reason}` à `fix.json → plan_deviations` (Victor le lit ; `repro.json` reste
  gelé) et `SendMessage` à Fanny « écart accepté, continue ». Refusé → `SendMessage` avec la
  consigne de l'humain.
- **Contestation de test** dans le rapport → **arbitrage**, quel que soit le gate :
  1. `phase = "arbitrate"`, ajoute `{at, test, claim}` à `arbitrations`.
  2. `SendMessage` à Bastien : la contestation telle quelle, et « tranche : test juste ou test faux ».
  3. Verdict **test juste** → `phase = "impl"`, `SendMessage` à Fanny avec l'explication de Bastien.
     Verdict **test corrigé** → montre le diff du test à l'humain (`git diff <freeze_sha> -- <test_files>`)
     et `AskUserQuestion` « Valider la correction du test » / « Refuser ». Validé → re-gel (nouveau commit
     `test(<nom>): <ce qui change> (refrozen)`, nouveau `freeze_sha`), `phase = "impl"`, `SendMessage` à
     Fanny : « le test a été corrigé, reprends ». Refusé → `SendMessage` à Bastien avec la raison.
  4. `loops.arbitrate` max 2, puis arrêt humain hors plan avec les deux positions.
- `stages.green` `FAILED` → arrêt humain hors plan : rapport, 40 dernières lignes de `last_green.log`,
  options (consigne à Fanny / revoir le diagnostic → retour à 1 avec Bastien).
- `stages.green` `PASSED` → étape 3.

### 3. Revue — Victor (`fix-reviewer`), et les reviewers du projet

Liste `.claude/agents/*.md` du projet : un agent de revue dont la description couvre les chemins
touchés par `git diff --name-only <freeze_sha>` (ex. `appwrite-function-reviewer` pour `functions/`)
est lancé **en parallèle** de `fix-reviewer`, dans le même message. Son rapport va dans
`.claude/fixes/<nom>/review_<agent>.md` (c'est toi qui l'écris, tel quel).

Prompt de `fix-reviewer` : nom, `diagnosis.md`, `repro.json` (dont `fix_plan`), `fix.json →
plan_deviations`, `freeze_sha`, `base_sha`, règles projet.

Puis `fix_gauntlet.sh review_verdict <nom>`. Les problèmes **bloquants** d'un reviewer projet (sa
propre classification : critique, bloquant, erreur) comptent comme des critiques.
- Aucun critique → `stages.review = PASSED`.
- Critiques → `loops.review += 1`. Si ≤ 2 : `SendMessage` à Fanny (ou un neuf si injoignable)
  avec la liste `critical` et leurs `fix`, puis gate green, puis revue à nouveau. Au-delà : arrêt humain
  hors plan avec les critiques persistantes.
- `plan_respected` ≠ `yes` sans critique `fix: plan` (Victor l'a jugé acceptable) : tu le
  signales à l'humain dans l'evidence, avec les fichiers hors plan du rapport.
- `missing_tests` de Victor : **ne relance personne**. Ils vont dans l'evidence ; l'humain décidera
  s'ils méritent un second passage de Bastien.

### 4. Captures — seulement `kind: ui`

Le gate green a rejoué le flow : `shots/green/` contient les captures après correction. Regarde-les
(`Read`) avant de les montrer — une capture qui ne montre pas l'état attendu est un défaut, pas un
succès. `fix_gauntlet.sh report <nom> ui` (captures red | green et correction vs plan), puis
`SendUserFile` du rapport et des paires avant/après, un appel, `display: render`, légende « avant | après ».
`AskUserQuestion` : « Valider » / « Défaut visible : … » (→ `SendMessage` à Fanny, puis 2→3→4 ;
`loops.ui` max 2). Validation → `human_gates.ui`.

### 5. Evidence, commits

Écris `.claude/fixes/<nom>/evidence.md` :

```
# Fix — <nom>
Branche fix/<nom> · Base <base_branch>@<base_sha court> · Test gelé @<freeze_sha court>

## Bug                      symptôme, en une phrase
## Cause racine             root_cause — root_cause_location
## Pourquoi les tests l'ont raté   miss_reason — l'explication, et le test existant corrigé s'il y en a un
## Preuve                   test(s) ajouté(s), rouge avant (expected_failure), vert après ; suite verte
## Plan validé             couche, approche, alternative écartée ; choix de l'humain (proposé / alternative / autre)
## Correction               fichiers, en une ligne chacun, marqués prévu / écart accepté ; même défaut corrigé ailleurs
## Revue                    cause traitée : yes/partial ; plan respecté : yes/partial ; critiques résolues : n ; reviewers projet : verdicts
## Arbitrages               contestations de Fanny et verdicts (si présents)
## Non traité               suggestions, missing_tests, hors périmètre signalé, acceptations (raisons)
## Captures                 avant / après (ui)
```

Régénère `fix_gauntlet.sh report <nom> evidence` et donne son chemin avec celui de l'evidence (il
n'est pas commité). Puis invoque la skill `create_commits` (le commit de gel existe déjà ; elle découpe la correction et
l'evidence). Tu ne pushes rien et ne crées rien d'externe : propose `create_mr` à l'humain, qui
appliquera ses propres validations. `stages.evidence = PASSED`, supprime `.claude/fixes/.current`.

Sors du worktree avec `ExitWorktree` `action: "keep"` : la branche `fix/<nom>` reste, prête à être
mergée par l'humain. Donne-lui la commande de nettoyage à lancer après le merge, sans l'exécuter :
`git worktree remove .claude/worktrees/fix-<nom> && git branch -d fix/<nom>`.

Termine par 5 lignes : cause, pourquoi raté, test, correction, chemin de l'evidence. Si la cause
racine révèle un piège non évident du projet (un comportement d'API, un invariant), propose en une
ligne de l'enregistrer en mémoire.

---

## Règles de conduite

- **Les agents ont un prénom.** Dans tes messages à l'humain, tes rapports et tes prompts de lancement,
  désigne chaque agent par son prénom (tableau des étapes) ; le slug `fix-*` ne sert qu'au `subagent_type`.
- **Contexte vierge, passé par fichiers.** Tu donnes des chemins et des faits, pas ton historique.
  Exception voulue : Bastien et Fanny sont **repris** par `SendMessage` pour l'arbitrage
  et les boucles — leur contexte vaut cher, ne le jette pas en relançant un agent neuf.
- **Le script décide.** Un gate est passé quand `fix.json → stages.<profil>` vaut `PASSED`, écrit par
  le hook. Le rapport d'un agent n'en fait pas foi.
- **Les rôles sont étanches.** Tu ne corriges jamais un test ni le code, même d'une ligne, même si c'est
  évident. Ce qui doit changer passe par l'agent propriétaire.
- **Une étape `FAILED` n'est jamais rejouée en silence.** L'humain décide.
- **Hors plan, sois court** : ce qui bloque, les faits, les options, la question.
- **Le rapport d'abord.** Tout arrêt humain, prévu ou hors plan, commence par `fix_gauntlet.sh report
  <nom> <étape>` et `SendUserFile` `display: render`. Régénéré à chaque fois, jamais réutilisé.
- **Le plan appartient à l'humain.** Couche, approche et fichiers de la correction sont validés avant
  le gel. Aucun agent ne s'en écarte sans que l'humain l'ait accepté.
- **`status`** : tableau de `fix.json` (phase, étapes, tentatives, boucles, arbitrages, gel) et rien d'autre.
- **`accept review "<raison>"`** : sur instruction explicite seulement — `"accepted": true` et la raison
  sur chaque critique restante de `review.json`, `{stage, at, reason}` dans `accepted`, relance du
  verdict. Apparaît dans l'evidence.
