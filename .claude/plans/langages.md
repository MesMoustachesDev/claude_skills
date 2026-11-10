# Langages : chaque commande choisit le bon (Flutter, Android / Kotlin…)

Décision : `pipeline/decisions/0011-un-dossier-par-langage.md`. Mode d'emploi : `stacks/README.md`.

## Mécanisme

1. **Résolveur et dossiers de langage** : `scripts/stack.sh` (detect, get, dir, list), `stacks/flutter/stack.ini`
   reprenant les valeurs en dur d'aujourd'hui, `stacks/android/stack.ini` en ébauche, ADR 0011, test. [fait]
   → `pipeline/langages`

## Sortir Flutter de ce qui est commun

2. **Doctrine Flutter → `rules/stacks/flutter*.md`** (paths `**/*.dart`, `**/pubspec.yaml`, `**/*.arb`) : [fait] retirer la prose
   Flutter des agents (`feature-*`, `fix-*`, `review-*`), des commandes (`feature`, `fix`, `create_test`,
   `debug_issue`, `reviewPR`, `create_screen`…) et de `pipeline/` (`review_grid.md`, `answers.md`, steps).
   Les textes deviennent « la commande / les conventions du langage ».
   → `pipeline/langages_doctrine`
3. **Gabarits → `stacks/flutter/templates/`** (plus exposés en skills), brick `flutter_feature` à côté ; [fait]
   `/feature init` copie les gabarits du langage détecté ; mettre à jour la douzaine de références.
   Le lien `commands/templates/flutter` est retiré au point 4 : `pr_gauntlet.sh` et `graphify.sh` lisent
   `stack.sh get templates`.
   → `pipeline/langages_doctrine`
4. **Scripts du /feature** : [fait] gauntlet (`checks_*.sh` → génériques + `stacks/flutter/checks.sh`), hooks
   `pipeline-restrict-writes.sh`, `pipeline.py` (`CONTRACT_GLOBS`, marqueur de package), `review.py`,
   `pr_gauntlet.sh`, `report.py`, doctor : tout passe par `stack.sh`. Les tests du gauntlet existants gardent
   le comportement Flutter à l'identique.
   → `pipeline/langages_scripts`
5. **/fix** : [fait] `is_manifest_path`, globs de test et `conventions` par `stack.sh` ; reproducer sans `fvm` en dur
   (prose de l'agent : point 2).
   → `pipeline/langages_scripts`

## Android / Kotlin

6. **`stacks/android/`** : `checks.sh` (Gradle test, lint, detekt / ktlint, couverture Kover, mutation à [fait]
   choisir), `rules/stacks/android.md` (Compose, MockK, Turbine, coroutines, Hilt), gabarits, et Android CLI :
   `preview render --component-tree` pour les écrans sans appareil, `layout` pour la QA, `emulator`.
   Le rapport HTML et l'evidence listent les checks `[N/A]` d'un gate (ADR 0011 : signalés, pas bloquants).
   → `pipeline/langages_android`
   Reste `[N/A]` pour Android : build_runner, metrics (detekt via analyze s'il est appliqué), reinvented,
   barrel_api, unused_code, unused_files, widget_functions, deps_unused, deps_features,
   pub_health, generated_fresh, test_dups ; format / coverage / mutation quand le
   build n'applique ni ktlint/Spotless, ni Kover/JaCoCo, ni pitest. Non essayé : `layout.json` écrit par le gate sur un flow
   rouge (la commande `layout` elle-même marche), lint / detekt / ktlint / Kover / pitest réels (pas en cache : simulés), un module `com.android.library` réel (AGP), la QA Maestro Android.
7. **Installer Android CLI** (téléchargement depuis developer.android.com, `--no-metrics`). [fait]
   1.1 dans `~/.local/bin/android` (binaire signé Google), `~/.androidrc` = `--no-metrics`. Essayé sur un
   projet Wear OS / Compose : `preview list` et `preview render` via `android_cli.sh` (PNG + arbre JSON),
   `emulator start --headless` (serial lu dans sa sortie : adb n'est pas dans le PATH des sessions), `layout`.
8. **Essai sur un vrai projet Kotlin** : un `/fix`, puis un `/feature`, sur un projet Wear OS / Compose. [fait]
   → `fix/phone_session_tagged_watch`, `feature/gps_settings_shortcut`
   Les deux sont allés au bout : commits locaux sur leurs branches, rien de poussé ni de MR. Le `/fix` a eu
   son parcours sur émulateur téléphone ; le `/feature` (M) a fait trois boucles, car la QA Maestro sur Wear
   a trouvé deux défauts réels que spec, critique et tests JVM avaient laissés passer.
   Corrigé dans `~/.claude` :
   - `/fix` copie les fichiers ignorés du checkout (`worktree_untracked.sh`) ;
   - `gradle_run.sh` affiche le message d'assertion (init script) et ne requalifie pas une tâche
     déjà qualifiée ;
   - `fix_gauntlet` : `lint` prend la `lint_cmd` du langage, un check qui ne vérifie rien est `[N/A]` ;
   - `expand_globs` : `**/` vaut zéro dossier ;
   - `spec_lint` lit le Kotlin (symboles, `*TestTags.kt`) ;
   - `red_check` : `red_accept_green`, pour un fichier tout vert accepté avec sa raison ;
   - gate `test` : `known_failures`, les tests déjà rouges sur la base ;
   - gate `qa` : captures Maestro 2.12 ;
   - learn : 5 règles (`retry-path`, bornes et erreurs de spec, repli journalisé, état de plateforme refermé).
   Reste, noté :
   - **Zones et procédure**
     - le `/feature init` écrit les règles dans le checkout principal sans les commiter ;
     - `0e` confie à Théo des appelants hors tests que son hook refuse ;
     - le hook d'écriture ne voit pas un script Python lancé depuis le scratchpad ;
     - les zones de l'implementer et du QA sont incohérentes : README, flows Maestro.
   - **Non applicables Android**
     - `test_dups` lié au Dart (`test_plan`, `test_plan_match` et `dedup` ont leur version Android) ;
     - `deps_unused` (une dépendance inutile vue seulement en revue) ;
     - le rapport « Séquences ».
   - **Gates et tests hors du module**
     - les tests hors du module de la feature (`app/src/test`) ne sont pas lancés par le gate `test` du package ;
     - un gate N/A n'écrit pas d'étape, et `next` bloque ;
     - un gate rejoué à la main n'écrit pas `stages.*`.
   - **QA Wear**
     - aucun émulateur par fix (`device_sim` est iOS seulement) ;
     - consignes `device_repro` iOS ;
     - app debug préinstallée sur l'AVD jetable (autre signature) ;
     - écran en veille pendant le run ;
     - deux Maestro sur un appareil (« Device server died ») ;
     - pas de shell Maestro (pont adb maison) ;
     - pas de check « testTag non exposé à Maestro ».
   - **Pilotage**
     - `next --after` ne sait pas attendre un agent avant son premier hook ;
     - `cockpit-push` sans `if_version` sur les contrats ;
     - `change_tree` compte les fichiers non suivis ;
     - le rejeu ne repropose pas la spec et a peu de boucles.
   - **Hors Android**
     - le garde de worktree et le hook rtk refusent `git` et les commandes composées
       (contournement : `/usr/bin/git`).
   Journal complet : notes de session `langages_essai_android_journal.md`.
