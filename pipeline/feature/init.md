## `/feature init`

À lancer une fois par projet. `/feature <nom>` l'appelle tout seul si le doctor échoue.

1. `~/.claude/scripts/gauntlet.sh doctor` — s'il est vert, dis-le et arrête-toi.
2. **Config** — si `.claude/rules/feature_pipeline.md` manque : copie le template, puis pose en **un**
   `AskUserQuestion` les questions dont tu n'as pas la réponse dans le repo : commandes (`fvm` ?
   détecte `.fvmrc`), `base_branch` (détecte `develop`/`main`), plateformes QA, `android.app_id`
   (lis `android/app/build.gradle*` → `applicationId`), `ios.app_id` (lis `ios/Runner.xcodeproj/project.pbxproj`
   → `PRODUCT_BUNDLE_IDENTIFIER`), AVD (`emulator -list-avds`), simulateur (`xcrun simctl list devices available`),
   feature de référence, commandes de build si flavors. Écris les valeurs dans le bloc `ini`.
   `riverpod_major` : lis `pubspec.lock` (`riverpod:` → `version:`), pas le pubspec — c'est la version
   résolue qui compte. Si le projet est en 2.x, dis-le : le global vise Riverpod 3, le brick génère la
   forme 2.x tant que le projet n'a pas migré, et `pub_health` le rappellera à chaque feature.
3. **Règles de code** — si `.claude/rules/create_feature_rules.md` manque : propose le template global
   (comme `/create_feature`), copie-le dans `.claude/rules/`.
3b. **Règles d'écran** — si `.claude/rules/create_screen_rules.md` manque : copie
   `~/.claude/commands/templates/flutter/create_screen_rules.md`. Si sa section **Anatomie du projet**
   est vide, propose 2 ou 3 écrans du repo qui partagent un squelette (`AskUserQuestion` : « lesquels
   sont les bons modèles ? »), lis-les, et remplis la section avec les vrais widgets et tokens. Ivan,
   Romain, Quentin et Pauline s'y alignent.
4. **Brick** — compare `.claude/rules/create_feature_rules.md` au template global (`diff`). S'ils
   divergent sur la structure ou les templates de fichiers (pas seulement le texte d'intro) :
   dérive un brick projet dans `./bricks/feature/` à partir du brick global, en appliquant les
   différences (dossiers, nommage, imports), et mets `brick = project` dans la config. Sinon
   `brick = global`. Dans les deux cas : `mason add -g <nom> --path <chemin>` si `mason` est installé.
   S'il ne l'est pas, donne la commande `dart pub global activate mason_cli` et continue : Arthur
   sait scaffolder à la main.
5. **`.gitignore`** du projet : ajoute `.claude/features/*/.gauntlet/`, `.claude/features/*/report.html`,
   `.claude/features/.current` et `coverage/` (le gate coverage écrit `<package>/coverage/lcov.info`)
   s'ils n'y sont pas.
6. `gauntlet.sh doctor` à nouveau. Tant qu'il est rouge, corrige ou demande. Résume ce qui a été créé.

