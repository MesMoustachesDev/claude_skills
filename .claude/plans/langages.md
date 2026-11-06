# Langages : chaque commande choisit le bon (Flutter, Android / Kotlin…)

Décision : `pipeline/decisions/0011-un-dossier-par-langage.md`. Mode d'emploi : `stacks/README.md`.

## Mécanisme

1. **Résolveur et dossiers de langage** : `scripts/stack.sh` (detect, get, dir, list), `stacks/flutter/stack.ini`
   reprenant les valeurs en dur d'aujourd'hui, `stacks/android/stack.ini` en ébauche, ADR 0011, test. [fait]
   → `pipeline/langages`

## Sortir Flutter de ce qui est commun

2. **Doctrine Flutter → `rules/stacks/flutter*.md`** (paths `**/*.dart`, `**/pubspec.yaml`) : retirer la prose
   Flutter des agents (`feature-*`, `fix-*`, `review-*`), des commandes (`feature`, `fix`, `create_test`,
   `debug_issue`, `reviewPR`, `create_screen`…) et de `pipeline/` (`review_grid.md`, `answers.md`, steps).
   Les textes deviennent « la commande / les conventions du langage ».
   → `pipeline/langages_doctrine`
3. **Gabarits → `stacks/flutter/templates/`** (plus exposés en skills), brick `flutter_feature` à côté ;
   `/feature init` copie les gabarits du langage détecté ; mettre à jour la douzaine de références.
   → `pipeline/langages_doctrine`
4. **Scripts du /feature** : gauntlet (`checks_*.sh` → génériques + `stacks/flutter/checks.sh`), hooks
   `pipeline-restrict-writes.sh`, `pipeline.py` (`CONTRACT_GLOBS`, marqueur de package), `review.py`,
   `pr_gauntlet.sh`, `report.py`, doctor : tout passe par `stack.sh`. Les tests du gauntlet existants gardent
   le comportement Flutter à l'identique.
   → `pipeline/langages_scripts`
5. **/fix** : `is_manifest_path`, globs de test et `conventions` par `stack.sh` ; reproducer sans `fvm` en dur.
   → `pipeline/langages_scripts`

## Android / Kotlin

6. **`stacks/android/`** : `checks.sh` (Gradle test, lint, detekt / ktlint, couverture Kover, mutation à
   choisir), `rules/stacks/android.md` (Compose, MockK, Turbine, coroutines, Hilt), gabarits, et Android CLI :
   `preview render --component-tree` pour les écrans sans appareil, `layout` pour la QA, `emulator`.
7. **Installer Android CLI** (téléchargement depuis developer.android.com, `--no-metrics`). [toi]
8. **Essai sur un vrai projet Kotlin** : un `/fix`, puis un `/feature`. [toi : quel projet]
