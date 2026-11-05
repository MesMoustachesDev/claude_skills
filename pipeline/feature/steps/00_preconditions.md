### 0. Préconditions

- Racine : `git rev-parse --show-toplevel`. Nom valide (`^[a-z][a-z0-9_]*$`).
- **Worktree, jamais de `git checkout` dans le checkout principal.** D'autres sessions y travaillent :
  changer sa branche fait atterrir leurs commits sur la branche de la feature. Tout le pipeline tourne
  dans `.claude/worktrees/feature-<nom>/`, sur la branche `feature/<nom>` — à faire **avant** de lire
  ou créer `pipeline.json`, qui vit dans le worktree :
  - `git worktree list` montre déjà `feature/<nom>` → `EnterWorktree` avec `path` = ce chemin (reprise).
  - **`<base>`** : `base_branch` de la config. **Sous-feature d'un epic (`--parent <epic>`)** :
    `feature/<epic>` dès que cette branche existe (`git rev-parse --verify feature/<epic>` ou
    `origin/feature/<epic>`) — la sous-feature en part, sa MR y revient, et c'est la base du diff des
    gates. Seule exception : `/epic` a proposé de partir de la branche d'une dépendance encore en MR
    (`feature/<dep>`). Annonce la base avant de créer le worktree, avec le bloc « ce que tu
    tranches sans lui » (`feature.md`) : quelle branche, pourquoi, ce que ça change pour la MR.
  - Sinon : `git fetch origin <base>` (ignore l'échec hors ligne), puis
    `git worktree add .claude/worktrees/feature-<nom> -b feature/<nom> <base>` (si la branche existe
    sans worktree : `git worktree add .claude/worktrees/feature-<nom> feature/<nom>`), puis
    `EnterWorktree` avec ce `path`. Les sous-agents, les hooks et le gauntlet prennent le worktree
    pour racine.
  - **Carte graphify** : `bash ~/.claude/scripts/graphify.sh prepare <worktree>` (contrat :
    `~/.claude/pipeline/graphify.md`). Lis la dernière ligne de stdout : `absent` → ne parle pas de graphify
    et continue ; `stale` ou `échec` → note la ligne et continue sans carte. Sur `ok`, garde la valeur
    de `graph=` (chemin du graphe relatif à la racine, ex. `flutter_app/graphify-out/graph.json`) et
    écris-la dans `pipeline.json → graphify_graph` (à la création, ou en remplacement à la reprise ;
    `null` hors `ok`) : tu la passes à Sophie et à Arthur, qui s'en servent dès le cadrage, et à tout
    agent relancé plus tard ; 9a le mettra à jour.
  - **Fichiers non versionnés** (création comme reprise), avant le `pub get` :
    `bash ~/.claude/scripts/worktree_untracked.sh <worktree>`. Il copie depuis le checkout principal
    (le premier de `git worktree list`) les fichiers gitignorés que le build et les tests lisent et qui
    manquent au worktree : `.env*`, `*.env`, `.ci.env`, `local.properties`, configs Firebase, `.fvmrc`…
    (`worktree.copy_untracked` de la config ; défaut dans l'en-tête du script). Il n'écrase jamais un
    fichier déjà là et ne copie jamais un keystore ni un secret de signature (`*.jks`, `key.properties`,
    `*.p8`, `*.p12`…), même s'ils sont demandés. Pas de question : dis-le avec le bloc « ce que tu
    tranches sans lui » (`feature.md`) — les fichiers copiés (lignes `copié`), la ligne `résumé`, les
    `refusé` s'il y en a, et que la liste se règle dans `worktree.copy_untracked`. Rien de copié : une
    ligne suffit, dans le même bloc que la base de branche.
  - Dépendances non versionnées : `flutter pub get` (ou `fvm flutter pub get`) à la racine du
    worktree avant le doctor ; les fichiers générés non commités se régénèrent au gate `build_runner`.
  - `.gitignore` : `.claude/worktrees/` s'il n'y est pas.
- `gauntlet.sh doctor` rouge → exécute `/feature init` d'abord.
- **Règles du projet absentes** : chaque ligne `RÈGLE ABSENTE : <fichier>` du doctor est une question à
  Thibault, posée avant le cadrage, toutes dans le même `AskUserQuestion`. Pour chaque fichier, dis à quoi il sert (`create_screen_rules.md` : Arthur, Ivan, Romain et
  Pauline l'appliquent à chaque écran ; `pr_rules.md` : la référence de Romain et de `/reviewPR`). Un fichier
  de `.claude/rules/` est chargé en entier dans chaque agent par Claude Code : c'est la seule façon sûre de
  le leur donner. Les choix :
  - « La créer depuis le template » → copie `~/.claude/commands/templates/flutter/<fichier>` dans
    `.claude/rules/<fichier>` du worktree, ouvre-le pour qu'il l'adapte (`open_in_editor`), commit avec la
    feature ;
  - « Prendre le template tel quel » → la même copie, sans l'ouvrir ;
  - « Le projet n'en a pas besoin » → ajoute le fichier à `rules.none` de `.claude/rules/feature_pipeline.md`.

- **Mode et package** : `--in <package>` → `mode: extend`, `package` = ce chemin (doit exister, avec
  un `pubspec.yaml`). Sinon `mode: create`, `package` = `package_path` avec `{name}` — sauf si le
  cadrage propose « extension de `features/x` » et que le dev le valide en 0b : tu bascules en
  `extend` avant le brouillon d'Arthur (les contrats s'écrivent dans le bon package).
- **Reprise** : si `.claude/features/<nom>/pipeline.json` existe, `pipeline.sh status <nom>` (affiche
  gabarit, étapes passées, sautées et points d'étape validés) puis `pipeline.sh next <nom>` : c'est lui
  qui donne l'étape où reprendre, dans l'ordre du tableau. Un brouillon commité sans
  `human_gates.contracts` reprend à 0e : rouvre les fichiers pour Thibault. `size: L` avec `split`
  rempli : `next` le dit, affiche l'état de chaque sous-feature (son `pipeline.json` dans son worktree)
  et ne lance rien.
  Sinon : `pipeline.sh init <nom> --mode create|extend --package <chemin> --base <base>` (la base
  du worktree, ci-dessus ; `--parent <nom>` pour une sous-feature d'une feature découpée : il vérifie
  qu'elle est dans son découpage, imprime le chemin de son extrait de cadrage, et refuse `base_branch`
  quand `feature/<parent>` existe), qui crée le dossier et `pipeline.json`
  avec tous ses champs. `mode` et `package` sont lus par le
  gauntlet et les hooks : c'est ce qui définit le périmètre. Changement de package ou de mode validé
  au cadrage : `pipeline.sh set <nom> package '"<chemin>"'` et `pipeline.sh set <nom> mode '"extend"'`.
  **Rejeu** (amendement de spec, nouvelle passe contracts → red → green sur du code déjà implémenté) :
  avant de relancer la première étape rejouée, `pipeline.sh set <nom> pass_base '"<SHA de HEAD>"'` (le
  travail de la passe validée). `stub_check` et `red_check` ne jugent alors que ce qui a changé depuis :
  le code et les tests de la passe précédente ne sont plus « non-stub » ni « tout vert » à tort. Les
  gates d'intégrité gardent le périmètre de la feature. `pipeline.sh set <nom> pass_base null` une fois
  le rejeu vert.
  Puis **crée la page de la feature** (`~/.claude/pipeline/feature/cockpit.md`, « Créer la page ») ;
  en reprise, réarme-la pour cette session (même section, point 4).
- **Watchdog** (création comme reprise, une fois par session). Le pipeline ne reste jamais des heures
  sans avancer : sur `import_cancel_sync`, `red` a été joint à 21 h 54, et 3b n'a été lancée qu'à 9 h.
  1. `CronCreate` récurrent, `cron` = toutes les `watchdog.minutes` de la config (défaut 20 :
     `"*/20 * * * *"`, minute de départ décalée), `prompt` = `/feature <nom> watchdog`. Garde l'id
     dans `pipeline.sh set <nom> watchdog_cron '"<id>"'`. Il ne se déclenche que session inactive :
     il ne coupe jamais un tour. Il expire au bout de 7 jours : en reprise, recrée-le (`CronList`
     d'abord, pas de doublon).
  2. `bash ~/.claude/scripts/watchdog.sh register <worktree> <nom>` : la veille hors session
     (LaunchAgent, voir `init.md`) suit la feature même session fermée ou bloquée sur une permission.
     S'il répond « LaunchAgent absent », dis-le une fois avec le bloc « ce que tu tranches sans lui » :
     seule la veille dans la session tourne.
  Le traitement de `/feature <nom> watchdog` est dans `feature.md` (« Watchdog »).
- **Preflight QA** (nouveau run, ou reprise sans `qa_devices`) : `qa.platforms` vide → rien. Sinon,
  pour chaque plateforme, comment Quentin obtient son appareil à l'étape 8. Un simulateur par worktree,
  jamais le simulateur partagé (`ios.simulator`) ni le modèle (`ios.simulator_base`) : `pipeline.sh
  devices` les refuse. Une seule question, posée avec la première du cadrage (même
  `AskUserQuestion`), header `Appareil QA`, options :
  - « Cloner un neuf (Recommandé) » → `pipeline.sh devices <nom> <pf> fresh` : clone du modèle
    (iOS, `sim.sh`, déjà connecté au compte de test) ; Android : instance jetable `-read-only` de
    `android.avd`.
  - « Cloner un neuf, à préparer » → il décrit l'état (compte, rapport téléchargé, écran de départ…) ;
    `pipeline.sh devices <nom> <pf> prepared --state "<sa description, telle quelle>"`. Quentin le
    prépare avant ses flows ; le gate `qa` refuse de tourner tant que ce n'est pas fait.
  - « Réutiliser un existant » → il nomme l'appareil (nom ou UDID du simulateur, serial ou AVD) ;
    `pipeline.sh devices <nom> <pf> reuse --device "<nom>"`. Liste-lui les candidats avant
    (`sim.sh list`, `adb devices`).
  Montre l'état actuel avant la question : `pipeline.sh devices <nom>` et `sim.sh list`.
  `size` (`S|M|L`, posé à la fin de 0b par `pipeline.sh size`) est lu par `pipeline.sh` et par le
  gauntlet (QA) ; absent ou `null`, c'est `M`.
- **Ticket** (tracker du projet : `~/.claude/pipeline/tracker.md`) : `~/.claude/pipeline/issue.md`,
  partie A, avant de lancer Sophie (nouveau run seulement). Sous-feature d'un epic (`--parent`) : son
  ticket est celui de l'epic (`split[i].ticket`). Un ticket existant fait partie de l'entrée de Sophie.
- **Branche** : déjà en place via le worktree (voir plus haut). Les modifications non commitées du
  checkout principal ne suivent pas : signale-le si elles concernent cette feature.
- Écris `<nom>` dans `.claude/features/.current` (secours pour les hooks quand la branche ne suit pas
  la convention).

