# Encart « Reprendre le fil » — plan d'implémentation

→ `pipeline/reprendre-le-fil`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** En tête du panneau pipeline-view, un encart d'une dizaine de lignes qui rappelle, pour la feature `/feature` de la session : but, étape, ce qui attend Thibault, ce qui a bougé depuis son dernier passage, décisions, questions ouvertes, hors périmètre.

**Architecture:** Les lignes factuelles (Étape, T'attend, Depuis) sont calculées par le mod depuis `pipeline.json` et un horodatage de passage stocké hors du repo. Les lignes de jugement (But, Décidé, Ouvert, À côté) sont écrites par l'orchestrateur via `pipeline.sh recap`, qui valide strictement un JSON borné ; sans `recap`, le mod extrait de `discussion.md`.

**Tech Stack:** Python 3 (`scripts/pipeline/pipeline.py`), bash (tests `scripts/gauntlet/tests/`), TypeScript/TSX du mod (`claude-code` engine, Ink-like `Box`/`Text`), `claude plugin test`.

**Spec:** `.claude/plans/reprendre-le-fil-design.md`

## Global Constraints

- Tout le travail se fait dans `~/.claude-wt/reprendre-le-fil` (branche `pipeline/reprendre-le-fil`), jamais dans `~/.claude` ; `claude_change.sh land reprendre-le-fil` à la fin, dans le même tour.
- Toute écriture de `pipeline.json` passe par `pipeline.sh` ; `recap` ne s'écrit que par `pipeline.sh recap`.
- Bornes du `recap` : `goal` 1 à 80 caractères, une ligne ; `decided` 0 à 5 chaînes ; `open` 0 à 3 ; `aside` 0 à 3 ; chaque chaîne ≤ 80 caractères, une ligne, non vide ; aucun autre champ.
- Aucun nom de client ou de projet dans `~/.claude` : exemples de tests neutres (« une feature de connexion », `feat`, `x`).
- Version du mod : `0.15.0` → `0.16.0`, description de `plugin.json` mise à jour ; puis `claude plugin marketplace update thibault-mods` et `claude plugin update pipeline-view@thibault-mods`.
- Commentaires et messages en français, dans le ton du code voisin (phrases courtes, « Thibault », pas de jargon anglais inutile).
- `/fix` hors périmètre : l'encart ne s'affiche que pour une feature.

## Review Focus

1. **Réveil du watchdog, message d'une autre session, notification de fin d'agent** : ne doivent pas compter comme un passage, sinon « Depuis » est toujours vide. → test de `isThibaultPrompt` (tâche 3).
2. **`recap` avec un champ multi-ligne, une chaîne vide ou un type faux (nombre, objet)** : refusé, `pipeline.json` intact. → tests de la tâche 1.
3. **`discussion.md` absent, vide, ou sans `## Décisions`** : l'encart s'affiche sans lignes Décidé/Ouvert, sans erreur. → test de `discussionFallback` (tâche 2).
4. **Étape écrite sans `at` ou avec un `at` illisible** : ignorée dans « Depuis », pas de `NaN`. → test de `sinceLines` (tâche 2).
5. **Fichier de passage corrompu** : traité comme « aucun passage » (3 dernières étapes, pas de « vu il y a »). → test de `parseSeen` (tâche 3).

---

### Task 0: Worktree et documents

- [ ] **Step 1:** `bash ~/.claude/scripts/claude_change.sh start reprendre-le-fil` → `worktree : ~/.claude-wt/reprendre-le-fil`.
- [ ] **Step 2:** Copier le design en `~/.claude-wt/reprendre-le-fil/plans/reprendre-le-fil-design.md` et ce plan en `plans/reprendre-le-fil.md`, en remplaçant le nom de feature de la maquette par un exemple neutre (contrainte « aucun nom »).
- [ ] **Step 3:** Commit `docs(pipeline-view): design et plan de l'encart « Reprendre le fil »`.

### Task 1: `pipeline.sh recap`

**Files:**
- Modify: `scripts/pipeline/pipeline.py` (nouvelle `cmd_recap`, `COMMANDS`, refus dans `cmd_set`)
- Modify: `scripts/pipeline.sh` (ligne d'aide)
- Create: `scripts/gauntlet/tests/test_recap.sh`

**Interfaces:**
- Produces: `pipeline.json → recap = {goal: str, decided: [str], open: [str], aside: [str], at: "<ISO UTC>", stage: "<clé de pipeline.sh next>"}`.

- [ ] **Step 1: Écrire le test** `test_recap.sh` (même squelette que `test_tests_added.sh` : `source fixture.sh`, `mk_repo`, `pipeline "$R" x '{"mode":"new","package":"app/feat","stages":{}}'`, `OUT/RC` capturés via `(cd "$R" && bash "$PIPELINE_SH" …)`, `finish`). Cas :
  - JSON valide (`goal` + 2 `decided`) → `expect_rc 0`, `jq -r .recap.goal` égal, `.recap.at` non vide, `.recap.stage` égal à `.key` de `pipeline.sh next x --json`.
  - `goal` de 81 caractères → `expect_rc 2`, `expect_out "goal"`, `pipeline.json` identique octet pour octet (`cmp` avec une copie prise avant).
  - 6 `decided` → rc 2. 4 `open` → rc 2. 4 `aside` → rc 2.
  - chaîne avec `\n` → rc 2. chaîne vide dans `decided` → rc 2. `decided` = `"x"` (pas une liste) → rc 2. `goal` = `3` → rc 2.
  - champ inconnu `"why"` → rc 2, `expect_out "why"`.
  - fichier absent → rc 2. fichier non-JSON → rc 2.
  - `pipeline.sh set x recap '{}'` et `set x recap.goal '"a"'` → rc 2, `expect_out "pipeline.sh recap"`.
- [ ] **Step 2:** `bash scripts/gauntlet/tests/test_recap.sh` → FAIL (commande inconnue).
- [ ] **Step 3: Implémenter `cmd_recap(c, args)`** : `args[0]` = chemin du JSON ; valide via une fonction `recap_errors(raw) -> list[str]` (un message par écart, nommant le champ) ; une erreur → `die("recap refusé : " + "; ".join(errs))` sans `c.save()`. Valide → `c.p["recap"] = {goal, decided, open, aside (listes absentes → []), "at": now(), "stage": <clé>}`, `c.save()`, `print("recap écrit")`. La clé d'étape : appeler la même logique que `cmd_next` en `--json` (extraire une fonction `next_step_key(c) -> str` si `cmd_next` n'en expose pas, sans changer sa sortie). Dans `cmd_set` : `key == "recap"` ou `key.startswith("recap.")` → `die("recap s'écrit par pipeline.sh recap <nom> <fichier.json>")`.
- [ ] **Step 4:** Ajouter dans `pipeline.sh` : `#   pipeline.sh recap <nom> <fichier.json>       résumé « Reprendre le fil » (goal, decided ≤5, open ≤3, aside ≤3, 80 car.) ; refusé hors schéma`.
- [ ] **Step 5:** `bash scripts/gauntlet/tests/test_recap.sh` → tous `ok`, et les autres tests du dossier toujours verts (`for t in scripts/gauntlet/tests/test_*.sh; do bash "$t"; done`).
- [ ] **Step 6:** Commit `feat(pipeline): pipeline.sh recap, résumé borné et validé`.

### Task 2: Fonctions pures de l'encart

**Files:**
- Create: `mods/pipeline-view/hooks/recap.ts`
- Modify: `mods/pipeline-view/types/index.d.ts` (types `Recap`, `RecapView`, atom `recap`)
- Test: `mods/pipeline-view/tests/pipeline-view.test.tsx`

**Interfaces:**
- Consumes: `PipelineSnapshot`, `PipelineStage`, `mark`, `stageOwner` (`hooks/model.ts`).
- Produces:
  - `type Recap = { goal: string; decided: string[]; open: string[]; aside: string[]; stage: string; source: 'recap' | 'discussion' }`
  - `parseRecap(pipelineText: string): Recap | null` — lit `pipeline.json → recap`, revalide les bornes (une donnée hors bornes → `null`), `source: 'recap'`.
  - `discussionFallback(md: string): Recap` — `goal: ''`, `decided` : 5 premières puces de `## Décisions`, `open` : 3 premières puces de `## Questions ouvertes` qui ne commencent pas par `RÉSOLU`, `aside: []`, `stage: ''`, `source: 'discussion'`. Une puce = ligne `- …` ; ses lignes de suite sont ignorées. Coupe à 80 caractères avec `…`.
  - `sinceLines(snap: PipelineSnapshot, seenAt: number | null): string[]` — étapes avec `at` lisible et `> seenAt` (ou toutes si `seenAt === null`), les plus récentes d'abord, au plus 3, format `` `${label} ${mark(status)}${owner ? ` (${owner})` : ''}` ``.
  - `progress(snap: PipelineSnapshot): string` — `` `${passées}/${non sautées}` `` (`PASSED` sur tout sauf `SKIPPED`).
  - `ago(ms: number): string` — `"il y a 5 min"`, `"il y a 3 h"`, `"il y a 2 j"`.
  - `type RecapView = { name: string; step: string; owner: string; progress: string; waiting: string; since: string[]; seenAgo: string; recap: Recap | null; isStale: boolean }`

- [ ] **Step 1: Écrire les tests** (`test('recap : …', …)`, style des tests existants) :
  - `parseRecap` d'un `pipeline.json` avec `recap` valide → objet égal ; `decided` de 6 → `null` ; sans `recap` → `null` ; JSON illisible → `null`.
  - `discussionFallback` sur un markdown de 7 décisions dont une de 120 caractères et 2 questions dont 1 `RÉSOLU` → 5 décisions, la longue finit par `…` et fait 80 caractères, 1 question. Sur `''` → listes vides.
  - `sinceLines(snap PIPELINE, Date.parse('2026-10-06T00:00:00Z'))` → `['impl (vert) ✗ (Ivan)']` ; avec `null` → 3 lignes, `green` en premier ; une étape `at: 'nope'` → ignorée.
  - `progress` sur `{PASSED, PASSED, RED, SKIPPED}` → `'2/3'`.
  - `ago(2 * 86_400_000)` → `'il y a 2 j'`.
- [ ] **Step 2:** `claude plugin test mods/pipeline-view` → FAIL (module absent).
- [ ] **Step 3:** Implémenter `hooks/recap.ts` et les types.
- [ ] **Step 4:** `claude plugin test mods/pipeline-view` → PASS.
- [ ] **Step 5:** Commit `feat(pipeline-view): calcul de l'encart « Reprendre le fil »`.

### Task 3: Le dernier passage de Thibault

**Files:**
- Create: `mods/pipeline-view/hooks/seen.ts`
- Modify: `mods/pipeline-view/hooks/register.tsx` (`prompt.submit`, `tool.call` d'`AskUserQuestion`, `settled` du `tool.call` générique)
- Test: `mods/pipeline-view/tests/pipeline-view.test.tsx`

**Interfaces:**
- Produces:
  - `seenFile(activityDir: string, mainRepo: string, feature: string): string` → `` `${activityDir}/seen/${mainRepo.replace(/[^A-Za-z0-9]/g, '_')}__${feature}.json` ``
  - `parseSeen(text: string): number | null` — `{"at": <ms>}` ; tout autre contenu → `null`.
  - `isThibaultPrompt(e: { origin?: { kind: string }; isMeta?: true }): boolean` — `true` seulement pour `origin.kind` ∈ `composer`, `bridge`, `sdk` (l'app desktop passe par le SDK) et `isMeta` absent ; `false` pour toute autre origine (`task-notification`, `scheduled-trigger`, `peer`, `peer-send-message`, `plugin`, `channel`, `coordinator`, `observer`…) ou sans `origin`.
  - dans `register.tsx` : `markSeen($): Promise<void>` (écrit `{"at": now}` pour la feature courante ; rien si la session n'a pas de feature).

- [ ] **Step 1: Vérifier** dans les types du moteur (`.claude-plugin/types/claude-code/index.d.ts`, `PromptOrigin`) que la liste des `origin.kind` n'a pas bougé, et qu'un message tapé dans l'app desktop arrive bien en `composer` ou `sdk` (une ligne de log temporaire suffit) ; ajuster l'ensemble accepté si besoin.
- [ ] **Step 2: Écrire les tests** : `isThibaultPrompt({ origin: { kind: 'composer' } })`, `'bridge'`, `'sdk'` → `true` ; `{ origin: { kind: 'composer' }, isMeta: true }` → `false` ; `'task-notification'`, `'scheduled-trigger'`, `'peer'`, `'plugin'` → `false` ; `{}` → `false`. `parseSeen('{"at":5}')` → `5` ; `'oops'`, `'{"at":"5"}'` → `null`. `seenFile('/a', '/Users/t/work/app', 'feat')` → `'/a/seen/_Users_t_work_app__feat.json'`.
- [ ] **Step 3:** `claude plugin test mods/pipeline-view` → FAIL.
- [ ] **Step 4: Implémenter `seen.ts`**, puis le câblage : la feature courante (repo principal via `git rev-parse --git-common-dir`, nom via `locate`) est retenue par `load()` ; `markSeen` est appelé (a) dans `prompt.submit` après `next(e)` si `isThibaultPrompt(e)` ; (b) dans le `tool.call` d'`AskUserQuestion` après `next(e)` réussi (pas de `deny`) ; (c) dans `settled` quand une permission attendue a tourné sans `deny`. Ouvrir le panneau n'écrit rien. `mkdir -p ${activityDir()}/seen` au `session.start`, comme `activityDir()`.
- [ ] **Step 5:** `claude plugin test mods/pipeline-view` → PASS.
- [ ] **Step 6:** Commit `feat(pipeline-view): retient le dernier passage de Thibault par feature`.

### Task 4: Afficher l'encart

**Files:**
- Modify: `mods/pipeline-view/hooks/register.tsx` (`load` remplit l'atom `recap` ; rendu du `Pane`)
- Test: `mods/pipeline-view/tests/pipeline-view.test.tsx`

**Interfaces:**
- Consumes: tout le Produces des tâches 2 et 3 ; `featureStep` et `waitingOf` existants.

- [ ] **Step 1: Écrire les tests de rendu** (avec `PANE`, comme les tests existants du `Pane`) :
  - feature avec `recap` et passage 2 jours avant : le rendu contient `Reprendre le fil`, `vu il y a 2 j`, `But`, `Décidé`, l'étape, `T'attend` quand `cockpit.waiting` est posé.
  - `recap.stage` différent de l'étape courante → contient `résumé de l'étape`.
  - sans `recap`, avec `discussion.md` → contient `extrait de discussion.md`, pas de ligne `But`.
  - aucun passage → pas de `vu il y a`, 3 lignes sous `Depuis`.
  - un `fix` → pas d'encart.
  - `cockpit.waiting` posé → `T'attend` apparaît une seule fois ; l'encart « à lire » n'affiche plus `À toi :` (titre `À lire · étape …`).
- [ ] **Step 2:** `claude plugin test mods/pipeline-view` → FAIL.
- [ ] **Step 3: Implémenter.** `load()` (feature seulement) construit le `RecapView` : `recap = parseRecap(text) ?? discussionFallback(<dossier>/discussion.md)` (`null` si le fichier manque aussi), `isStale = recap.source === 'recap' && recap.stage !== step.key`. Rendu en tête du `Pane`, au-dessus des étapes : titre gras `Reprendre le fil · <nom>` + `vu il y a …` en `dimColor` (ou `extrait de discussion.md` / `résumé de l'étape <x>`), puis une ligne par élément non vide dans l'ordre But, Étape (`<titre> (<qui>) · <progress>`), T'attend (`color="warning"`), Depuis, Décidé (`• …`), Ouvert (`• …`), À côté. Libellés alignés sur 9 colonnes. L'en-tête « à lire » devient toujours `À lire · étape <titre>`.
- [ ] **Step 4:** `claude plugin test mods/pipeline-view` → PASS.
- [ ] **Step 5:** Commit `feat(pipeline-view): encart « Reprendre le fil » en tête du panneau`.

### Task 5: L'orchestrateur écrit le résumé, publication

**Files:**
- Modify: `commands/feature.md` (règle 4), `pipeline/feature/steps/0b_cadrage.md` (fin du cadrage)
- Modify: `mods/pipeline-view/.claude-plugin/plugin.json`

- [ ] **Step 1:** Lire `pipeline/decisions/0005-pas-d-arret-sans-thibault.md` ; vérifier que l'ajout n'introduit aucun arrêt (le résumé ne pose aucune question).
- [ ] **Step 2:** Règle 4 de `commands/feature.md`, avant `pipeline.sh say … --report` : « écris le résumé « Reprendre le fil » : un JSON `{goal, decided, open, aside}` dans le dossier de la feature, puis `pipeline.sh recap <nom> <fichier>`. `goal` : le but en une ligne ; `decided` : les 5 décisions les plus structurantes de `discussion.md` et du cadrage, une ligne chacune, pas tout le journal ; `open` : ce qui reste à trancher ; `aside` : ce qui a été sorti du périmètre et où c'est parti. Un refus : corrige le JSON, ne contourne jamais par `set`. Aucune question à Thibault. » Même ajout, une ligne, à la fin de `0b_cadrage.md`.
- [ ] **Step 3:** `plugin.json` : `"version": "0.16.0"`, et la description commence par « Affiche, en tête, un encart « Reprendre le fil » (but, étape, ce qui t'attend, ce qui a bougé depuis ton dernier passage, décisions, questions ouvertes) ; l'état du pipeline… ».
- [ ] **Step 4:** `claude plugin test mods/pipeline-view` et `for t in scripts/gauntlet/tests/test_*.sh; do bash "$t"; done` → tout vert. `bash scripts/pre_push_names.sh` (ou le hook `pre-push`) → aucun nom.
- [ ] **Step 5:** Commit `feat(feature): l'orchestrateur écrit le résumé « Reprendre le fil » à chaque point d'étape`.
- [ ] **Step 6:** `bash ~/.claude/scripts/claude_change.sh land reprendre-le-fil`, puis `claude plugin marketplace update thibault-mods` et `claude plugin update pipeline-view@thibault-mods`. Dire à Thibault qu'un redémarrage de l'app est nécessaire pour charger la 0.16.0.
