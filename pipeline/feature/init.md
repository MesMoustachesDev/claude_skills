## `/feature init`

À lancer une fois par projet. `/feature <nom>` l'appelle tout seul si le doctor échoue.

1. `~/.claude/scripts/gauntlet.sh doctor` — s'il est vert, dis-le et arrête-toi.
1b. **Langage** — `bash ~/.claude/scripts/stack.sh detect <app_dir>` (dossier de l'app). Les gabarits viennent
   de `$(bash ~/.claude/scripts/stack.sh dir <app_dir>)/templates/` (« le template » dans la suite). Lis le
   manifeste du package : c'est ce qui charge la règle de langage, qui ajoute ses questions propres.
   Rien détecté : demande le langage à Thibault, et écris `stack = <langage>` dans le bloc `ini`.
2. **Config** — si `.claude/rules/feature_pipeline.md` manque : copie le template `feature_pipeline.md`, puis
   pose en **un** `AskUserQuestion` les questions dont tu n'as pas la réponse dans le repo : commandes
   (wrapper de SDK, comme la règle de langage le dit), `base_branch` (détecte `develop`/`main`), plateformes QA, `android.app_id`
   (lis `android/app/build.gradle*` → `applicationId`), `ios.app_id` (lis `ios/Runner.xcodeproj/project.pbxproj`
   → `PRODUCT_BUNDLE_IDENTIFIER`), AVD (`emulator -list-avds`), simulateur (`xcrun simctl list devices available`),
   feature de référence, commandes de build si flavors, et le **tracker** (`~/.claude/pipeline/tracker.md`) :
   backend (détecté : `gitlab` si `glab repo view` réussit, sinon `none` ; `notion` au choix), projet
   GitLab des tickets s'il diffère du code (une règle projet qui le cite, comme `create_mr_rules.md`,
   donne la réponse), base Notion (« Créer <Projet> — Roadmap » / « Coller l'URL d'une base »).
   Écris les valeurs dans le bloc `ini`.
   Projet déjà configuré mais sans clé `tracker` : pose seulement ces questions-là et ajoute la section
   du template. Créer la base Notion est une écriture externe : nom, schéma et emplacement montrés et
   validés avant (`tracker.md`, backend `notion`).
   Les clés propres au langage (versions de bibliothèques que lit le brick, par exemple) : la règle de
   langage dit où les lire — la version résolue du lockfile, pas celle déclarée.
3. **Règles de code** — si `.claude/rules/create_feature_rules.md` manque : propose le template global
   (comme `/create_feature`), copie-le dans `.claude/rules/`.
3b. **Règles d'écran** — si `.claude/rules/create_screen_rules.md` manque : copie le
   template `create_screen_rules.md`. Si sa section **Anatomie du projet**
   est vide, propose 2 ou 3 écrans du repo qui partagent un squelette (`AskUserQuestion` : « lesquels
   sont les bons modèles ? »), lis-les, et remplis la section avec les vrais widgets et tokens. Ivan,
   Romain, Quentin et Pauline s'y alignent.
4. **Brick** — compare `.claude/rules/create_feature_rules.md` au template global (`diff`). S'ils
   divergent sur la structure ou les templates de fichiers (pas seulement le texte d'intro) :
   dérive un brick projet dans `./bricks/feature/` à partir du brick global, en appliquant les
   différences (dossiers, nommage, imports), et mets `brick = project` dans la config. Sinon
   `brick = global`. Dans les deux cas : `mason add -g <nom> --path <chemin>` si `mason` est installé.
   S'il ne l'est pas, donne la commande d'installation que dit la règle de langage et continue : Arthur
   sait scaffolder à la main.
5. **`.gitignore`** du projet : ajoute `.claude/features/*/.gauntlet/`, `.claude/features/*/report.html`,
   `.claude/features/.current` et `coverage/` (le gate coverage écrit `<package>/coverage/lcov.info`)
   s'ils n'y sont pas.
5b. **Clés du pipeline sans question** (valeurs par défaut écrites dans le bloc `ini`, à ajuster) :
   `generated.exclude` (ajoute le dossier de sortie de gen-l10n : `output-dir` de `l10n.yaml`, s'il
   n'est pas couvert par le défaut), `worktree.copy_untracked` (lance
   `worktree_untracked.sh <un worktree> --dry-run` pour voir ce que le défaut trouverait ; ajoute les
   fichiers ignorés que le build lit et que le défaut rate, jamais un keystore), `watchdog.minutes`,
   `watchdog.renotify_minutes`.
5c. **Veille hors session** : si `~/Library/LaunchAgents/com.claude.feature-watchdog.plist` manque,
   propose-la en une question (« Installer la veille hors session ? » : un LaunchAgent qui lance
   `watchdog.sh scan` toutes les 15 min et notifie quand une feature attend ou est bloquée, même session
   fermée). Oui → `bash ~/.claude/scripts/watchdog.sh install`. Une fois par machine, pas par projet.
6. `gauntlet.sh doctor` à nouveau. Tant qu'il est rouge, corrige ou demande. Résume ce qui a été créé.

