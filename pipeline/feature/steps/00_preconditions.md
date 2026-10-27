### 0. Préconditions

- Racine : `git rev-parse --show-toplevel`. Nom valide (`^[a-z][a-z0-9_]*$`).
- **Worktree, jamais de `git checkout` dans le checkout principal.** D'autres sessions y travaillent :
  changer sa branche fait atterrir leurs commits sur la branche de la feature. Tout le pipeline tourne
  dans `.claude/worktrees/feature-<nom>/`, sur la branche `feature/<nom>` — à faire **avant** de lire
  ou créer `pipeline.json`, qui vit dans le worktree :
  - `git worktree list` montre déjà `feature/<nom>` → `EnterWorktree` avec `path` = ce chemin (reprise).
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
  - Dépendances non versionnées : `flutter pub get` (ou `fvm flutter pub get`) à la racine du
    worktree avant le doctor ; les fichiers générés non commités se régénèrent au gate `build_runner`.
  - `.gitignore` : `.claude/worktrees/` s'il n'y est pas.
- `gauntlet.sh doctor` rouge → exécute `/feature init` d'abord.
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
  Sinon : `pipeline.sh init <nom> --mode create|extend --package <chemin> --base <base_branch>`
  (`--parent <nom>` pour une sous-feature d'une feature découpée : il vérifie qu'elle est dans son
  découpage et imprime le chemin de son extrait de cadrage), qui crée le dossier et `pipeline.json`
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
  `size` (`S|M|L`, posé à la fin de 0b par `pipeline.sh size`) est lu par `pipeline.sh` et par le
  gauntlet (QA) ; absent ou `null`, c'est `M`.
- **Issue GitLab** : `~/.claude/pipeline/issue.md`, partie A, avant de lancer Sophie (nouveau run
  seulement). Une issue existante fait partie de l'entrée de Sophie.
- **Branche** : déjà en place via le worktree (voir plus haut). Les modifications non commitées du
  checkout principal ne suivent pas : signale-le si elles concernent cette feature.
- Écris `<nom>` dans `.claude/features/.current` (secours pour les hooks quand la branche ne suit pas
  la convention).

