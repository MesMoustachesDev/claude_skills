# Feature Pipeline — configuration projet

Ce fichier est lu par `/feature`, par les sept agents `feature-*` et par `~/.claude/scripts/gauntlet.sh`.
Il contient **uniquement des faits du projet** : le process, les rôles et les scripts sont globaux
(`~/.claude`) et ne se dupliquent pas ici.

Le bloc `ini` ci-dessous est la partie machine. Le gauntlet le parse ligne à ligne (`clé = valeur`,
`#` pour les commentaires, listes séparées par des virgules). Tout ce qui est en dehors du bloc
est de la documentation pour les humains et les agents.

```ini
# ---------------------------------------------------------------------------
# Commandes
# ---------------------------------------------------------------------------
flutter = fvm flutter
dart = fvm dart

# ---------------------------------------------------------------------------
# Structure
# ---------------------------------------------------------------------------
# Chemin d'un package feature, {name} remplacé par le nom de la feature.
package_path = features/{name}
# Branche depuis laquelle on crée feature/{name} et contre laquelle on mesure le diff.
base_branch = develop
# Brick Mason utilisé par l'architect. "project" = ./bricks/feature, "global" = ~/.claude/bricks/flutter_feature.
brick = global
# Zones d'écriture supplémentaires pour architect/implementer/cleaner, hors du package feature
# (enregistrer une route, ajouter des clés l10n…). Globs relatifs à la racine du repo.
writes.extra = features/router/**, features/l10n/lib/**

# ---------------------------------------------------------------------------
# Seuils (surcharger ici pour dévier des défauts globaux)
# ---------------------------------------------------------------------------
threshold.cyclomatic = 10
threshold.function_lines = 30
threshold.nesting = 3
threshold.parameters = 4
# Couverture des lignes MODIFIÉES par la feature (pas du package entier), en %.
threshold.coverage_changed = 90
# Score de mutation minimal, en %.
threshold.mutation = 85
# Tentatives d'un agent sur un gate rouge avant d'appeler l'humain.
pipeline.max_attempts = 5

# ---------------------------------------------------------------------------
# Mutation testing (globs relatifs au package)
# ---------------------------------------------------------------------------
mutation.include = lib/src/domain/**.dart, lib/src/data/**.dart, lib/src/presentation/**/bloc/*.dart
mutation.exclude = **/*.g.dart, **/*.freezed.dart, **/keys.dart, **/*_event.dart, **/*_state.dart

# ---------------------------------------------------------------------------
# Fichiers qui doivent être des stubs après l'étape ARCHITECT (globs relatifs au package)
# ---------------------------------------------------------------------------
stub.include = lib/src/data/**/*_impl.dart, lib/src/data/mapper/*.dart, lib/src/domain/usecase/*.dart, lib/src/presentation/**/bloc/*_bloc.dart, lib/src/presentation/**/view/*.dart

# ---------------------------------------------------------------------------
# Direction des dépendances entre couches (imports package:<self>/src/<couche>/...)
# Clé = couche qui importe, valeur = couches qu'elle a le droit d'importer.
# ---------------------------------------------------------------------------
deps.domain =
deps.data = domain
deps.presentation = domain
deps.injection = domain, data, presentation
# Packages interdits dans domain/ (pureté du domaine).
deps.domain_forbidden_packages = flutter, flutter_bloc, flutter_riverpod, dio, appwrite, isar

# ---------------------------------------------------------------------------
# Maintenabilité (checks_maintain.sh)
# ---------------------------------------------------------------------------
# Packages du workspace que toute feature peut utiliser sans justification. Toute autre dépendance
# inter-features doit être nommée dans la spec §8 (gate deps_features).
deps.shared_packages = core, design, l10n, router, error, env, analytics
# Une dépendance hébergée sans release depuis plus de N mois est signalée (bloquant si ajoutée par la feature).
pub.max_age_months = 24
# Design system : préfixes d'import acceptés (une vue doit en importer un) et motifs interdits en présentation.
# Les motifs sont des regex grep -E, séparés par des virgules (donc sans virgule dedans).
ds.imports = package:design/, package:core/design.dart
ds.forbidden = Colors\.[a-z], TextStyle\(, Color\(0x, fontSize:, EdgeInsets\.(all|symmetric|only)\([0-9], SizedBox\((height|width): [0-9], BorderRadius\.circular\([0-9]
# Globs (relatifs au package) exemptés des checks design_system / l10n_strings.
ds.exempt =
# Fichiers ARB (glob relatif à la racine) : les clés ajoutées par la feature doivent exister dans chacun.
l10n.arb_glob = features/l10n/lib/**/*.arb
# Un TODO/FIXME doit référencer un ticket : regex après le mot-clé.
todo.pattern = \((#[0-9]+|[A-Z]+-[0-9]+)\)
# Roue réinventée (dup_check) : taille minimale d'un corps pour compter comme clone, et noms à ignorer
# en plus des conventions (build, copyWith, call, show, of…).
dup.min_tokens = 40
dup.ignore_names =

# ---------------------------------------------------------------------------
# QA — Maestro (flows dans <package>/maestro/, captures dans .claude/features/<name>/qa/<platform>/)
# ---------------------------------------------------------------------------
qa.platforms = android, ios
android.avd = Pixel_6
android.serial = emulator-5554
android.app_id = com.example.app
android.build = fvm flutter build apk --debug
android.apk = build/app/outputs/flutter-apk/app-debug.apk
ios.simulator = iPhone 16 Pro
ios.app_id = com.example.app
ios.build = fvm flutter build ios --debug --simulator
ios.app = build/ios/iphonesimulator/Runner.app
```

## Notes pour les agents

<!-- Tout ce qui est spécifique au projet et que les agents doivent savoir en plus de
     .claude/rules/create_feature_rules.md. Exemples : comment lancer l'app en staging,
     quel compte de test utiliser (référence à un secret, jamais la valeur), quelles
     features servent de modèle. -->

- Feature de référence (structure exemplaire à imiter) : `features/{exemple}`
- Compte de test QA : voir `{où}` — ne jamais écrire d'identifiants dans un flow Maestro ; utiliser `-e` avec des variables d'environnement.
