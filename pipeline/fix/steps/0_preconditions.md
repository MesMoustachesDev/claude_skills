# /fix — étape 0 : préconditions

Création comme reprise, une fois par session, avant l'étape que donne `steps.py next`. Règles communes :
`~/.claude/pipeline/conduite.md`.

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
  - **Fichiers non versionnés** (création comme reprise) : `bash ~/.claude/scripts/worktree_untracked.sh
    <worktree>` copie depuis le checkout principal les fichiers gitignorés que le build lit et qui
    manquent (`local.properties`, configs Firebase, `.env*`…), jamais un keystore ni un secret de
    signature. Sans eux, un module Android ne builde pas et le gate red échoue sur l'environnement (cas
    réel, 2026-11-06), et les hooks interdisent à Bastien de les écrire. Pas de question : dis les fichiers
    copiés avec le bloc « ce que tu tranches sans lui ».
  - Les dépendances ne sont pas versionnées : Bastien les installe dans le package du bug
    (`npm ci` s'il y a un lockfile, sinon la commande d'installation du langage) — jamais `npm install`
    d'un paquet, jamais de bump.
  - **Carte graphify** : `bash ~/.claude/scripts/graphify.sh prepare <worktree>` (contrat :
    `~/.claude/pipeline/graphify.md`). Lis la dernière ligne de stdout et garde-la : le mot après
    `graphify: ` (`ok`, `stale`, `absent`, `échec`) se passe tel quel à `fix.py init --graphify` ci-dessous
    et, sur `ok`, la valeur de `graph=` à `--graph`. `absent` → ne parle pas de graphify et continue ; `stale` ou `échec` → note
    la ligne et continue sans carte.
  - **Serena** : `bash ~/.claude/scripts/serena.sh prepare <worktree>` (contrat :
    `~/.claude/pipeline/serena.md`), à la création comme à la reprise. Lis la dernière ligne de stdout :
    `absent` → ne parle pas de Serena et continue ; `échec` → note la ligne dans le rapport et continue
    sans ; `ok` → rien à passer : Bastien et Victor le trouvent seuls.
- **Reprise** : une fois dans le worktree, si `.claude/fixes/<nom>/fix.json` existe, affiche l'état et
  reprends à la première étape non `PASSED`. Les agents d'une session précédente ne sont plus
  joignables : relance-les à contexte vierge avec les fichiers du dossier (c'est fait pour).
- `.gitignore` : ajoute `.claude/worktrees/`, `.claude/fixes/*/.gauntlet/`, `.claude/fixes/*/fix.json`, `.claude/fixes/*/report.html`
  et `.claude/fixes/.current` s'ils n'y sont pas (commit séparé `chore: ignore fix pipeline scratch`,
  dans le worktree).
- Crée l'état depuis le worktree, nouveau fix seulement (il écrit aussi `.claude/fixes/.current`) :
  ```bash
  python3 ~/.claude/scripts/fix/fix.py init <nom> "<description brute>" --base-branch <branche du checkout principal> --graphify <mot de graphify> [--graph <valeur de graph=>]
  ```
- **Attente** : `ask` ne porte jamais un statut (« Bastien reproduit le bug ») : le watchdog lit tout
  texte de `ask` comme une question qui attend le dev (`waiting_thibault`) et ne verrait plus un fix
  bloqué (cas réel, premier /fix Kotlin).
- **Watchdog** (création comme reprise, une fois par session) :
  1. `CronCreate` récurrent, `cron` = toutes les 1,5 × `watchdog.minutes` de
     `.claude/pipeline/feature_pipeline.md`, arrondi à un diviseur de 60 (défaut 20 → 30 :
     `"*/30 * * * *"`, minute de départ décalée). `prompt` = le texte court ci-dessous, **jamais**
     `/fix <nom> watchdog`, qui recopie tout `fix.md` à chaque réveil (ADR 0005, amendement 4) :
     ```
     Watchdog <nom> : bash ~/.claude/scripts/fix_gauntlet.sh watchdog <nom>. working ou idle → fin
     du tour, sans message. stalled → reprends à l'étape qu'il nomme, dans ce tour ; relis
     ~/.claude/commands/fix.md si tu ne l'as plus en tête. waiting_thibault avec alert: true →
     PushNotification d'une ligne, au plus une fois par watchdog.renotify_minutes. done → CronDelete
     de watchdog_cron. Détail : fix.md, « Watchdog ».
     ```
     Garde l'id : `python3 ~/.claude/scripts/fix/fix.py set <nom> watchdog_cron <id>`. Il ne se déclenche que session inactive. Il expire au
     bout de 7 jours : en reprise, recrée-le (`CronList` d'abord, pas de doublon). Un cron de ce fix dont
     le prompt est encore `/fix <nom> watchdog` (ancien format) : `CronDelete`, puis recrée-le.
  2. `bash ~/.claude/scripts/watchdog.sh register <worktree> <nom> --fix` : la veille hors session suit
     le fix même session fermée ou bloquée sur une permission. « LaunchAgent absent » → dis-le une fois
     avec le bloc « ce que tu tranches sans lui ».
  Le traitement d'un réveil est dans `~/.claude/pipeline/conduite.md` (« Watchdog »).
- **Ticket** : `~/.claude/pipeline/issue.md`, partie A, avant de lancer Bastien (nouveau run
  seulement). Un ticket existant fait partie de l'entrée de Bastien.
