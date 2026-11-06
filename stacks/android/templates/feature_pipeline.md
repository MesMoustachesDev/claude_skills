# Feature Pipeline — configuration projet (Android natif)

Ce fichier est lu par `/feature`, par les agents `feature-*` et par `~/.claude/scripts/gauntlet.sh`.
Il contient **uniquement des faits du projet** : le process, les rôles et les scripts sont globaux
(`~/.claude`) et ne se dupliquent pas ici.

Le bloc `ini` ci-dessous est la partie machine. Le gauntlet le parse ligne à ligne (`clé = valeur`,
`#` pour les commentaires, listes séparées par des virgules). Tout ce qui est en dehors du bloc
est de la documentation pour les devs et les agents.

Un « package » du pipeline est ici un **module Gradle** (`feature/<nom>/`, son `build.gradle.kts`).

```ini
# ---------------------------------------------------------------------------
# Langage et commandes
# ---------------------------------------------------------------------------
# Force le langage de tout le repo (utile si le repo contient aussi un pubspec.yaml). Sans : marqueur le plus proche.
stack = android
# Le wrapper, relatif à la racine Gradle. `./gradlew --offline` hors réseau.
gradle = ./gradlew
# Tâches de test, compilation et lint d'un module Android (variant debug) ; un module Kotlin/JVM pur prend
# test, compileTestKotlin, lint (stacks/android/stack.ini). Surcharger ici si le projet n'a pas de variant debug.
unit_test_task = testDebugUnitTest
compile_task = compileDebugUnitTestKotlin
lint_task = lintDebug
# Couverture : Kover (koverXmlReport) ou JaCoCo (jacocoTestReport) détectés dans le build ; une autre tâche ici.
coverage_task =
# Mutation : pitest (pitestDebug pour un module Android, pitest pour un module JVM) ; une autre tâche ici.
mutation.task =

# ---------------------------------------------------------------------------
# Structure
# ---------------------------------------------------------------------------
# Chemin d'un module feature, {name} remplacé par le nom de la feature.
package_path = feature/{name}
features_root = feature
# Branche depuis laquelle on crée feature/{name} et contre laquelle on mesure le diff.
base_branch = develop
# Zones d'écriture supplémentaires, hors du module feature, ouvertes à TOUTES les features (enregistrer le module
# dans settings.gradle.kts, la dépendance et la route dans l'app). Globs relatifs à la racine du repo.
# Une zone dont une seule feature a besoin va dans son pipeline.json : `pipeline.sh extra <nom> <glob>`.
writes.extra = settings.gradle.kts, app/build.gradle.kts, app/src/main/**, gradle/libs.versions.toml

# ---------------------------------------------------------------------------
# Tracker : où vivent les tickets d'epic, de feature et de fix (~/.claude/pipeline/tracker.md).
# gitlab | notion | none. Absent : gitlab si `glab repo view` réussit, sinon none.
# ---------------------------------------------------------------------------
tracker =
tracker.gitlab.project =
tracker.notion.database =
issue.labels.epic = epic
issue.labels.feature =
issue.labels.fix = bug
issue.assignee = @me

# ---------------------------------------------------------------------------
# Seuils
# ---------------------------------------------------------------------------
# Complexité, lignes, imbrication, paramètres : detekt les juge s'il est appliqué (gate analyze) ; le gate
# metrics (dart_code_linter) n'a pas de version Android.
threshold.cyclomatic = 10
threshold.function_lines = 30
threshold.nesting = 3
threshold.parameters = 4
# Couverture des lignes MODIFIÉES par la feature (pas du module entier), en %.
threshold.coverage_changed = 90
# Score de mutation minimal, en %. Sans le filtre Kotlin d'Arcmutate (payant), pitest garde des mutants
# impossibles à tuer (code ajouté par le compilateur) : exclure ces mutateurs dans le build, ou baisser ce seuil.
threshold.mutation = 80
pipeline.max_attempts = 5

# ---------------------------------------------------------------------------
# Fichiers générés : aucun check ne les juge. Vide = le défaut de stacks/android/stack.ini
# (build/, Hilt, Room, BuildConfig, R) ; none = aucun.
# ---------------------------------------------------------------------------
generated.exclude =

# ---------------------------------------------------------------------------
# Worktree de feature : fichiers gitignorés copiés du checkout principal s'ils manquent. Jamais un keystore.
# ---------------------------------------------------------------------------
worktree.copy_untracked = **/local.properties, **/google-services.json, **/.env, **/.env.*, **/secrets.properties

watchdog.minutes = 20
watchdog.renotify_minutes = 120

# ---------------------------------------------------------------------------
# Mutation testing (globs relatifs au module)
# ---------------------------------------------------------------------------
mutation.include = src/main/**/domain/**.kt, src/main/**/data/**.kt, src/main/**/*ViewModel.kt
mutation.exclude = **/di/**, **/*Module.kt, **/*UiState.kt, **/*UiEvent.kt, **/*TestTags.kt

# ---------------------------------------------------------------------------
# Fichiers qui doivent être des stubs (TODO()) après l'étape ARCHITECT (globs relatifs au module)
# ---------------------------------------------------------------------------
stub.include = src/main/**/data/**/*Impl.kt, src/main/**/data/**/*Mapper.kt, src/main/**/domain/**/*UseCase.kt, src/main/**/*ViewModel.kt, src/main/**/*Screen.kt

# ---------------------------------------------------------------------------
# Direction des dépendances entre couches (segment de paquet domain | data | ui | presentation | di).
# Clé = couche qui importe, valeur = couches qu'elle a le droit d'importer. ui et presentation : deps.presentation ;
# di : deps.injection. Le domaine n'importe jamais android.* ni androidx.* (sauf androidx.annotation).
# ---------------------------------------------------------------------------
deps.domain =
deps.data = domain
deps.presentation = domain
deps.injection = domain, data, presentation, ui
# Paquets interdits dans domain/ (en plus d'android et androidx) : préfixes de paquet.
deps.domain_forbidden_packages = retrofit2, okhttp3, io.ktor, androidx.room, com.google.firebase
# Globs relatifs au module, exemptés du gate deps (dette existante assumée).
deps.exempt =

# ---------------------------------------------------------------------------
# Maintenabilité
# ---------------------------------------------------------------------------
deps.shared_packages = core, designsystem
# Design system : préfixes de paquet qu'un écran (*Screen.kt) doit importer, et motifs interdits en présentation
# (regex grep -E, séparées par des virgules, donc sans virgule dedans).
ds.imports = com.example.designsystem.
ds.forbidden = Color\(0x, [^A-Za-z_.][0-9]+(\.[0-9]+)?\.dp, [^A-Za-z_.][0-9]+(\.[0-9]+)?\.sp, FontWeight\.W[0-9], RoundedCornerShape\([0-9]
# Globs (relatifs au module) exemptés des checks design_system / l10n_strings (le module du thème lui-même).
ds.exempt =
# strings.xml hors du module (un module de ressources partagé), glob relatif à la racine. Ceux du module
# (src/main/res/values*/strings.xml) sont toujours lus.
l10n.strings_glob =
todo.pattern = \((#[0-9]+|[A-Z]+-[0-9]+)\)
# README.md de chaque module feature : sections obligatoires (regex grep -E).
readme.sections = ^## (But|Purpose), ^## (API publique|Public API)

# ---------------------------------------------------------------------------
# Revue de PR (pr_gauntlet.sh, /reviewPR)
# ---------------------------------------------------------------------------
pr.max_lines = 600
commits.pattern = ^(feat|fix|chore|refactor|test|docs|perf|ci|build|style)(\([a-z0-9_/-]+\))?!?: .+
pr.copy_untracked = local.properties

# ---------------------------------------------------------------------------
# QA — Maestro sur Android (flows dans <module>/maestro/, captures dans .claude/features/<name>/qa/android/)
# ---------------------------------------------------------------------------
app_dir = .
qa.platforms = android
qa.platform_s =
android.avd = Pixel_6
android.serial = emulator-5554
android.app_id = com.example.app
android.build = ./gradlew :app:assembleDebug
android.apk = app/build/outputs/apk/debug/app-debug.apk
# cli : l'AVD de QA démarre par Android CLI (`android emulator start --headless`) ; vide : l'émulateur du SDK.
android.emulator =

rules.none =
```

## Ce que les gates font, et ne font pas, sur Android

| Gate | Outil | Sans l'outil dans le build |
|---|---|---|
| analyze | compilation Kotlin, Android lint, detekt s'il est appliqué | — (compilation et lint toujours) |
| format | ktlint (`org.jlleitschuh.gradle.ktlint`) ou Spotless | non applicable |
| test, red_check, test_names | `testDebugUnitTest`, rapports JUnit XML (src/test seulement) | — |
| coverage | Kover ou JaCoCo (rapport XML) | non applicable |
| mutation | pitest (`info.solidsoft.pitest`, `pl.droidsonroids.pitest`), outputFormats XML | non applicable |
| build_runner, metrics, reinvented, barrel_api, unused_code, widget_functions, pub_health, test_plan… | — | non applicables à Android |

Un check non applicable est signalé (`[N/A]` dans le journal, le rapport HTML et l'evidence), jamais compté vert.
