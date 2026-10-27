# Cockpit — une page par fix

Même principe que `/feature` (`~/.claude/pipeline/feature/cockpit.md`) : **chaque fix a sa page**,
publiée par la session `/fix` au démarrage et surveillée par elle seule, plus une carte dans
**l'Accueil** (https://claude.ai/artifact/TiXbjaUnp6yVay81XBKQ8R), qu'aucune session ne surveille. Le script : `~/.claude/scripts/fix_cockpit.py`
(depuis le worktree du fix). Dossier de travail : `D="${TMPDIR:-/tmp}/cockpit-fix-<nom>"`.

## Créer la page (une fois, juste après l'écriture de `fix.json`)

1. `python3 ~/.claude/scripts/fix_cockpit.py page <nom> <ton dossier scratchpad>` : la copie de la page,
   titrée « Fix <nom> ».
2. `Artifact` publish de ce fichier, sans `url`, `icon: "dashboard"`, `capabilities: {"db": {},
   "comments": {}, "sample": {}}`.
3. `python3 ~/.claude/scripts/fix_cockpit.py set-url <nom> <url publiée>`.
4. Reprise dans une nouvelle session : `Artifact` `read` de `fix.json → cockpit.url`, puis
   republication du fichier avec `url` (sans `capabilities`), pour armer la surveillance.

## Rafraîchir (à chaque arrêt pour Thibault, et à la fin)

1. `python3 ~/.claude/scripts/fix_cockpit.py say <nom> "<ce qu'on attend de lui>" [--report <étape>]`
   (`""` une fois sa réponse reçue).
2. `ArtifactData` `list` de `fixes` sur **la page du fix**, `out_dir` = `$D/in` ; `list` de `index` sur
   **l'Accueil**. Seules les versions du résultat servent (première fois : aucune).
3. `python3 ~/.claude/scripts/fix_cockpit.py push <nom> "$D/out" --versions "<clé>=<v>" --hub-version <v>`.
   Il imprime `writes` (la page : état, cause racine, plan, diagnostic, dernier `report.html`) et
   `hub_writes` (la carte de l'Accueil).
4. `ArtifactData` `batch` de `writes` sur la page, puis de `hub_writes` sur l'Accueil. Version
   périmée : refais 2 à 4, une fois. Donne à Thibault le lien de **la page du fix**.

Les captures ne sont pas embarquées dans le rapport : elles s'envoient toujours par `SendUserFile`.

## Répondre depuis la page

Même mécanique que `/feature` (`~/.claude/pipeline/feature/cockpit.md`, « Répondre depuis la page ») :
`fix_cockpit.py say <nom> "<…>" --ask <id> --options "A|B|Discuter"`, « Rafraîchir », puis la question
en texte dans la session, sans `AskUserQuestion` bloquant. Ids : `plan`, `test`, `ecart`, `arbitrage`,
`captures`, `page-fin`. Le point d'étape 1 pose deux questions (plan, test) : deux `say` successifs ne se
cumulent pas, donc une seule question à la fois — le plan d'abord, puis le test.

## Être prévenu

« Prévenir Claude » sur la page du fix ne réveille que ta session : `[cockpit <clé>] …` est la réponse de
Thibault à l'arrêt en cours. Une validation (plan, test, captures) passe quand même par sa question :
le message te dit seulement qu'il a lu et qu'il est là.
