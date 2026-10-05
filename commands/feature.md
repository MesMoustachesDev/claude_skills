# Feature Pipeline — orchestrateur

Tu orchestres le pipeline de livraison d'une feature : une chaîne de sous-agents à contexte vierge,
un gauntlet de scripts entre chaque, et cinq arrêts humains. **Tu n'écris aucun code toi-même.**
Ton rôle est de lancer le bon agent avec le bon contexte, lire les verdicts des scripts, et parler
à l'humain uniquement aux gates prévus ou quand une étape est en échec définitif.

Argument : **$ARGUMENTS**

```
/feature help                                  cette aide, avec des exemples
/feature init                                  prépare le projet (config, règles, brick, doctor)
/feature <nom> [description]                   nouvelle feature = nouveau package features/<nom>
/feature <nom> --in <package> [description]    ajout à un package existant (mode extend)
/feature <nom> status                          affiche l'état sans rien lancer
/feature <nom> accept <étape> "<raison>"       accepte un verdict d'agent (dedup, review…) avec une raison
```

Le nom est en snake_case et nomme **le changement**, pas forcément le package. Une feature = une
branche `feature/<nom>` = un dossier de travail `.claude/features/<nom>/` = un package cible :
- **mode `create`** (défaut) : le package `features/<nom>` (ou `package_path` de la config) est créé ;
  tout le package est dans le périmètre des gates.
- **mode `extend`** (`--in <package>`, ou décidé par le specifier en §8 « extension de … ») : le
  package existe ; le **périmètre** des gates de qualité est le diff depuis `base_branch` — fichiers
  ajoutés, lignes ajoutées. La feature est responsable de ce qu'elle touche et doit laisser le reste
  au moins aussi bon : les gates d'intégrité (compilation, suite verte, gel, dépendances, périmètre,
  barrel, README) restent sur le package entier.

### `/feature help`

Affiche le bloc d'usage ci-dessus, puis ces exemples, tels quels :

```
# Nouvelle feature, package neuf, description libre
/feature meal_reminders "Rappels de repas : l'utilisateur programme une notification par repas planifié"

# Ajout à une feature existante : le nom décrit le changement, --in désigne le package
/feature recipe_export_pdf --in features/show_recipe "Exporter une recette en PDF depuis l'écran recette"

# Correctif comportemental dans un package existant (petite spec, mêmes gates)
/feature category_sort_fix --in features/category "Les catégories custom sont triées après les prédéfinies"

# Reprendre où on en était (après une coupure, ou le lendemain)
/feature meal_reminders

# Où en est-on ?
/feature meal_reminders status

# Le dedup a jugé un widget en doublon, je le garde en connaissance de cause
/feature meal_reminders accept dedup "MealCard n'est pas une DesignCard : pas de slot image, comportement de swipe spécifique"

# Préparer un projet la première fois
/feature init

# Audit de maintenabilité d'un package existant, hors pipeline (aucun agent, scripts seuls)
~/.claude/scripts/gauntlet.sh maintain category
```

Puis rappelle en trois lignes : les cinq arrêts humains (architecture + spec, contrats, tests, mutants,
captures), chacun avec un rapport HTML, que rien
n'est pushé sans `create_mr`, et que `~/.claude/scripts/gauntlet.sh list` détaille chaque check.

---

## Références

| Quoi | Où |
|---|---|
| Gauntlet | `~/.claude/scripts/gauntlet.sh <profil> <nom>` — `doctor`, `list` |
| Rapport humain | `~/.claude/scripts/gauntlet.sh report <nom> <étape>` → `.claude/features/<nom>/report.html` |
| Config projet | `.claude/rules/feature_pipeline.md` (template : `~/.claude/commands/templates/flutter/feature_pipeline.md`) |
| Règles de code | `.claude/rules/create_feature_rules.md` (template : `~/.claude/commands/templates/flutter/create_feature_rules.md`) |
| Template de spec | `~/.claude/commands/templates/flutter/feature_spec_template.md` |
| Brick global | `~/.claude/bricks/flutter_feature` |
| État | `.claude/features/<nom>/pipeline.json` |

Étapes, agents et profils de gate :

| # | Étape | Agent (`subagent_type`) | Gate | Arrêt humain après |
|---|---|---|---|---|
| 1 | spec | `feature-specifier` | — | non |
| 1b | critique | `feature-spec-critic` | `spec_review_verdict` | **oui** : décisions d'architecture une par une, puis la spec (boucle vers 1 avant) |
| 2 | contracts | `feature-architect` | `contracts` | non |
| 2b | dedup | `feature-dedup` | `dedup_verdict` | **oui** : architecture réelle (code scaffoldé) vs architecture validée |
| 3 | tests | `feature-test-writer` | `red` | non |
| 3b | revue des tests | `feature-test-reviewer` | `tests_review_verdict` | **oui** : skim de `tests.md` + `tests_review.md`, puis gel (boucle vers 3 avant) |
| 4 | impl | `feature-implementer` | `green` | non |
| 5 | clean | `feature-cleaner` | `clean` | non |
| 5b | dedup | `feature-dedup` | `dedup_verdict` | non (boucle vers 5 si doublons) |
| 6 | review | `feature-reviewer` | `review_verdict` | non (boucle vers 4 si critiques) |
| 7 | harden | `feature-hardener` | `harden` | **oui** : mutants expliqués |
| 8 | qa | `feature-qa` | `qa` | **oui** : captures |
| 9 | evidence | toi | — | puis `/create_commits` et `/create_mr` |

---

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
4. **Brick** — compare `.claude/rules/create_feature_rules.md` au template global (`diff`). S'ils
   divergent sur la structure ou les templates de fichiers (pas seulement le texte d'intro) :
   dérive un brick projet dans `./bricks/feature/` à partir du brick global, en appliquant les
   différences (dossiers, nommage, imports), et mets `brick = project` dans la config. Sinon
   `brick = global`. Dans les deux cas : `mason add -g <nom> --path <chemin>` si `mason` est installé.
   S'il ne l'est pas, donne la commande `dart pub global activate mason_cli` et continue : l'architect
   sait scaffolder à la main.
5. **`.gitignore`** du projet : ajoute `.claude/features/*/.gauntlet/`, `.claude/features/*/report.html` et `.claude/features/.current`
   s'ils n'y sont pas.
6. `gauntlet.sh doctor` à nouveau. Tant qu'il est rouge, corrige ou demande. Résume ce qui a été créé.

---

## `/feature <nom> [description]`

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
  - Dépendances non versionnées : `flutter pub get` (ou `fvm flutter pub get`) à la racine du
    worktree avant le doctor ; les fichiers générés non commités se régénèrent au gate `build_runner`.
  - `.gitignore` : `.claude/worktrees/` s'il n'y est pas.
- `gauntlet.sh doctor` rouge → exécute `/feature init` d'abord.
- **Mode et package** : `--in <package>` → `mode: extend`, `package` = ce chemin (doit exister, avec
  un `pubspec.yaml`). Sinon `mode: create`, `package` = `package_path` avec `{name}` — sauf si, après
  la spec, §8 dit « extension de `features/x` » : tu confirmes avec l'humain (« la spec propose
  d'étendre `x` plutôt que de créer un package — d'accord ? ») et tu bascules en `extend`.
- **Reprise** : si `.claude/features/<nom>/pipeline.json` existe, lis-le, affiche l'état (étape
  courante, gates passés, arrêts humains validés) et reprends à la première étape non `PASSED`.
  Sinon crée le dossier et `pipeline.json` :
  ```json
  { "feature": "<nom>", "mode": "create|extend", "package": "<chemin du package>", "branch": "feature/<nom>", "base": "<base_branch>",
    "created": "<iso>", "stages": {}, "human_gates": {}, "attempts": {}, "tests_freeze_sha": null, "loops": {}, "accepted": [] }
  ```
  `mode` et `package` sont lus par le gauntlet et les hooks : c'est ce qui définit le périmètre.
- **Branche** : déjà en place via le worktree (voir plus haut). Les modifications non commitées du
  checkout principal ne suivent pas : signale-le si elles concernent cette feature.
- Écris `<nom>` dans `.claude/features/.current` (secours pour les hooks quand la branche ne suit pas
  la convention).

### 1. Spec — `feature-specifier`

Prompt de lancement : nom, description brute (ou « aucune, à découvrir »), racine, chemin de sortie,
et la phrase : « Tu proposes l'architecture, l'humain la tranche : chaque décision structurante va en §9
avec le statut `proposée`, une alternative réelle et la raison. Tu ne la présentes pas comme acquise. »

### 1b. Critique — `feature-spec-critic`

Lance `feature-spec-critic` (prompt : nom, `spec.md`, `create_feature_rules.md`, template de spec).
Puis `gauntlet.sh spec_review_verdict <nom>` : rouge → relance le **specifier** avec
`spec_review.md` (« corrige ces points, sans réécrire ce qui n'est pas cité »), puis 1b à nouveau ;
`loops.spec`, max 2, puis tu montres les bloquants restants à l'humain avec la spec.

Vert → **Arrêt humain 1 : architecture, puis spec.** L'humain garde la main sur l'archi : rien
n'est scaffoldé tant qu'il n'a pas tranché chaque décision.

**1a. Architecture.** `gauntlet.sh report <nom> spec`, puis `SendUserFile` du `report.html`
(`display: render`, légende « décisions d'architecture à trancher »). Le rapport montre les cartes §9
et les diagrammes §8. Puis `AskUserQuestion`, **une question par ligne de §9 au statut `proposée`**
(par paquets de 4 questions max par appel) :
- `header` : l'ID et le sujet (`A1 Package`) ; `question` : la décision en une phrase et son enjeu ;
- option 1 : la décision proposée, suffixée « (Recommandé) », avec la raison en description ;
- option 2 : l'alternative de §9, avec ce qu'elle changerait concrètement en description ;
- « Other » reste ouvert pour une troisième voie.

Toutes acceptées → passe la colonne Statut de ces lignes à `validée` (édition de `spec.md`, seule
écriture que tu fais dans la spec avec l'en-tête). Au moins une changée → relance le **specifier** avec
la spec existante et les décisions imposées (« A2 : <choix de l'humain> — statut `modifiée`, répercute
sur §5, §6, §8 et les scénarios concernés ; ne touche pas aux autres décisions »), puis 1b, puis 1a à
nouveau **pour les seules lignes encore `proposée`** (une décision tranchée ne se repose pas).
`human_gates.architecture = {at, by: "user", decisions: {"A1": "validée", "A2": "modifiée"}}`.

**1b. Spec.** En 10 lignes max : objectif, périmètre, nombre de scénarios, points signalés par le
specifier, notes non bloquantes du critique. Le rapport est déjà ouvert : renvoie à ses sections
« Spec » et « Tests » plutôt que de les recopier.
Puis `AskUserQuestion` : « Valider la spec » / « Demander des modifications » (texte libre → relance
le specifier avec la spec existante + le retour, puis 1b ; repasse par 1a si §9 a bougé).
Validation → `human_gates.spec = {at, by: "user"}`, `stages.spec = PASSED`, et remplace « brouillon »
par « validée le <date> » dans l'en-tête de la spec.

### 2. Contrats — `feature-architect`

Prompt : nom, **mode**, `spec.md`, `create_feature_rules.md`, package, valeur de `brick`. En mode
`extend`, ajoute : « pas de scaffold ; ajoute dans l'existant ; ne renomme rien ». Au retour, vérifie
`stages.contracts` dans `pipeline.json` (le hook l'a écrit).
Le rapport mentionne un écart avec la spec → **arrêt humain hors plan** : montre l'écart, propose
« corriger la spec et relancer l'architect » ou « accepter l'écart ». Note la décision dans `pipeline.json`.

### 2b. Roue réinventée — `feature-dedup`

Le script cherche les ressemblances, l'agent juge, le script lit le verdict :
1. `gauntlet.sh dedup_candidates <nom>` → `.claude/features/<nom>/dedup_candidates.json`.
   S'il n'y a aucune entrée, saute l'agent : `stages.dedup = PASSED`.
2. Lance `feature-dedup` (prompt : nom, package, chemin des candidats, `spec.md`).
3. `gauntlet.sh dedup_verdict <nom>` : vert → `stages.dedup = PASSED`. À ce stade le verdict ne
   bloque que les entrées `fix_by: architect` (un choix de contrat : réutiliser un type, un use case).
   Les entrées `fix_by: cleaner` (factoriser du code existant, extraire un widget porteur de rendu)
   demandent du vrai code, que l'architect ne peut pas écrire sous le gate des stubs : le script les
   affiche « reportées au cleaner » sans bloquer, tu les transmets à l'étape 5, et 5b les revérifie
   en bloquant. Ne relance jamais l'architect sur une entrée `cleaner`. Rouge → relance l'**architect**
   avec `dedup.md` (« ces déclarations existent déjà : utilise / étends l'existant », entrées
   `architect` seulement), puis 2b à nouveau ; `loops.dedup_contracts`, max 2, puis arrêt humain hors plan. L'humain peut **accepter**
   un verdict (il a une raison) : tu poses `"accepted": true` sur l'entrée dans `dedup.json` avec sa
   raison, et le verdict repasse au vert. L'exemption apparaîtra dans l'evidence.

### 2c. Arrêt humain 2 : architecture réelle

L'architecture existe maintenant en code. `gauntlet.sh report <nom> contracts`, puis `SendUserFile` du
`report.html` (`display: render`). La section « Architecture réelle » est générée depuis le package :
diagramme des classes par couche (ajoutées en bleu, existantes en gris), dépendances du pubspec,
providers, et les **écarts** avec la spec validée (contrat de §5 absent du code, dépendance du pubspec
non nommée en §8, classe domain/presentation hors §5).

En 5 lignes : le nombre de classes par couche, les dépendances inter-features, les écarts (tous, un
par ligne). `AskUserQuestion` : « Valider l'architecture » / « Corriger : … » (texte libre).
- Correction qui reste dans la spec validée (nommage, découpage, placement) → relance l'**architect**
  avec le retour, puis 2b et 2c à nouveau.
- Correction qui change une décision de §9 ou un contrat de §5 → retour au **specifier** (décision
  imposée, statut `modifiée`), 1b, 1a pour cette ligne seulement, puis 2 depuis le début.
Validation → `human_gates.contracts = {at, by: "user"}`.

Puis commit : `git add -A <package> pubspec.yaml features/router features/l10n && git commit -m "feat(<nom>): scaffold and contracts"`.

### 3. Tests — `feature-test-writer`

Prompt : nom, `spec.md`, package, la liste des chemins autorisés en lecture (`lib/src/domain/**`,
`lib/src/presentation/keys.dart`, `**/*_event.dart`, `**/*_state.dart`, `lib/src/data/model/*.dart`),
`~/.claude/commands/create_test.md`. Au retour, `stages.red` doit être `PASSED`.

### 3b. Revue des tests — `feature-test-reviewer`

Lance `feature-test-reviewer` (prompt : nom, `spec.md`, package, `tests.md`, `create_test.md`).
Puis `gauntlet.sh tests_review_verdict <nom>` : rouge → relance le **test-writer** avec
`tests_review.md` (il complète et corrige les tests cités, il ne réécrit pas les autres), puis
`gauntlet.sh red`, puis 3b ; `loops.tests`, max 2, puis arrêt humain avec les bloquants restants.

Vert → **Arrêt humain 3.** `gauntlet.sh report <nom> tests`, `SendUserFile` du `report.html`
(`display: render`) : matrice scénarios §4 × `.feature`, inventaire des tests par fichier. Puis montre
`.claude/features/<nom>/tests.md` (le fichier entier : c'est
court et c'est fait pour être lu), la table de couverture de `tests_review.md`, les tests « passe
déjà » avec la justification de l'agent, et les contrats manquants s'il y en a. `AskUserQuestion` :
« Valider les tests » / « Il manque des scénarios » (texte libre → relance le test-writer avec le
retour, puis 3b ; ses fichiers existants restent, il complète).

Validation → **gel** :
```bash
git add <package>/test <package>/pubspec.yaml && git commit -m "test(<nom>): acceptance and unit tests (frozen)"
```
Enregistre le SHA dans `pipeline.json → tests_freeze_sha`, `human_gates.tests`, `stages.red = PASSED`.
À partir d'ici, `test/` ne change plus, sauf ajouts du hardener.

### 4. Implémentation — `feature-implementer`

Prompt : nom, `spec.md`, package, `tests.md`, et `.claude/features/<nom>/.gauntlet/last_red.log`
(ou `last_green.log` en reprise/boucle) — la sortie rouge. Au retour :
- `stages.green = PASSED` → continue.
- `FAILED` (5 tentatives) → **arrêt humain hors plan** : montre le rapport de l'agent (ce qui bloque,
  tests suspects), les 40 dernières lignes du log, et propose : relancer l'implementer avec une
  consigne / corriger un test suspect (toi, sur instruction explicite de l'humain, **et tu re-gèles** :
  nouveau commit, nouveau `tests_freeze_sha`) / revenir à la spec.
- Le rapport contient `Décision d'architecture requise` → **arrêt humain hors plan**, comme en 1a :
  rapport HTML, une question avec les deux options. La réponse va en §9 (nouvelle ligne, statut
  `validée` ou `modifiée`), puis `SendMessage` à l'implementer avec la décision.
- Le rapport liste des « tests suspects » alors que le gate est vert → transmets-les tel quel à
  l'arrêt humain 4, ne bloque pas.

### 5. Nettoyage — `feature-cleaner`

Prompt : nom, package, `last_clean.log` si présent, et `dedup.md` s'il porte des entrées
`fix_by: cleaner` reportées depuis 2b (« applique ces factorisations ; 5b les revérifie et bloque »).
`stages.clean = PASSED` → continue ; `FAILED` → même traitement qu'en 4.

### 5b. Roue réinventée, second passage — `feature-dedup`

Même mécanique qu'en 2b, sur le code implémenté (helpers, widgets, extensions apparus pendant 4 et 5).
Rouge → relance le **cleaner** avec `dedup.md`, puis 5b ; `loops.dedup_clean`, max 2.

### 6. Revue — `feature-reviewer`

D'abord les scripts : `~/.claude/scripts/gauntlet.sh maintain <nom>` (dépendances inter-features
justifiées, santé des packages pub.dev, design system, l10n, code mort, périmètre, secrets…). Son
verdict n'arrête rien ici : le log est une **entrée** du reviewer, qui transforme chaque échec en finding.

Prompt : nom, `spec.md`, package, `tests_freeze_sha` (base du diff), `tests.md`,
`.claude/features/<nom>/.gauntlet/last_maintain.log`, `.claude/features/<nom>/dedup.md`,
`.claude/rules/pr_rules.md` si présent, `.claude/rules/create_feature_rules.md`,
`~/.claude/commands/reviewPR.md`.
Au retour, `gauntlet.sh review_verdict <nom>` (le hook de l'agent n'a vérifié que le format — un
reviewer qui trouve des critiques doit pouvoir rendre la main) :
- vert → `stages.review = PASSED`, continue.
- rouge → **boucle** : `loops.review += 1`. Si ≤ 2 : relance l'**implementer** (prompt : la liste
  `critical` avec `fix`, plus le contexte habituel), puis le **cleaner**, puis le **reviewer**.
  Au-delà de 2 : arrêt humain hors plan avec la liste des critiques persistantes.

### 7. Durcissement — `feature-hardener`

Prompt : nom, package, chemin du rapport de mutation, `review.json` (pour `missing_tests`).
`stages.harden = PASSED` → **arrêt humain 4.** `gauntlet.sh report <nom> mutants` et `SendUserFile`
(`display: render`). Montre `mutants.md` en entier, le score, le nombre de
tests ajoutés, les tests existants signalés suspects (4 et 7), et `review.json → suggestions` en
résumé. `AskUserQuestion` : « Valider » / « Ces explications ne tiennent pas : … » (texte libre →
relance le hardener avec le retour). Validation → `human_gates.mutants`.

### 8. QA — `feature-qa`

Prompt : nom, `spec.md`, package, `feature_pipeline.md`. Au retour, quel que soit le gate :
**arrêt humain 5.** `gauntlet.sh report <nom> qa` (les captures y sont intégrées). Montre `qa.md` en
entier et envoie le rapport puis les captures avec `SendUserFile`
(`.claude/features/<nom>/qa/*/*.png`, toutes, en un appel par plateforme) — l'humain regarde des
images, pas des chemins. `AskUserQuestion` : « Valider » / « Défauts bloquants : … » (→ relance
l'implementer avec les défauts, puis cleaner, reviewer, hardener sont **sautés** si `lib/` n'a changé
que dans `presentation/**/view/**` — sinon rejoue 5→7 — puis QA à nouveau ; `loops.qa`, max 2).
Validation → `human_gates.qa`.

### 9. Evidence, commits, MR

Écris `.claude/features/<nom>/evidence.md` — la page que l'humain lit à la place du code :

```
# Evidence — <nom>
Spec validée le <date> · Branche feature/<nom> · Base <base>@<sha>

## Architecture                      ← spec §8 (diagrammes mermaid) + §9 avec le statut final de chaque décision
| ID | Décision | Statut (validée / modifiée par l'humain) |

## Acceptation
| Scénario | Widget test | Android | iOS |   ← §4 × tests.md × qa.md

## Mesures
Tests : <n> (dont <n> ajoutés par le hardener) · Couverture lignes modifiées : <n>%
Mutation : <n>% (<n> mutants, <n> survivants expliqués) · Complexité max : <n> · Dépendances : ✓
Revue : <n> critiques (résolues), <n> suggestions · Règles projet : <n>/<n> · Maintenabilité : <n>/7

## Maintenabilité                    ← last_maintain.log + review.json → rules_checked.maintainability
Dépendances inter-features : <liste, justifiées §8> · Packages ajoutés : <liste avec date de release>
Roue réinventée : <n> paires jugées, <n> doublons résolus, <n> verdicts acceptés par l'humain (<raisons>)   ← dedup.json
Widgets vs design system : <n> comparés, <n> remplacés, <n> extensions du DS                              ← dedup.json
Exemptions gauntlet-ignore : <n> (<où>)

## Dépendances à traiter hors feature   ← review.json → dependencies
| Package | Problème | Alternative | Fichiers | Risque | Verdict |

## Qualité des entrées               ← spec_review.json, tests_review.json
Spec : <n> bloquants corrigés avant validation, <n> notes · Tests : <n>/<n> scénarios couverts, <n> bloquants corrigés avant gel

## Suggestions non appliquées        ← review.json
## Mutants expliqués                 ← mutants.md
## Défauts visuels mineurs           ← qa.md
## Captures                          ← chemins relatifs
```

Puis, **dans cet ordre** : invoque la skill `create_commits` (elle découpe le travail restant en
commits atomiques ; les commits de contrats et de gel existent déjà), puis la skill `create_mr` en
lui indiquant que la description de MR est `evidence.md`. `create_mr` applique ses propres règles de
validation humaine avant tout push ou création : tu ne les contournes pas.

`stages.evidence = PASSED`. Sors du worktree avec `ExitWorktree` `action: "keep"` (la branche reste
pour la MR) et donne la commande de nettoyage à lancer après le merge, sans l'exécuter :
`git worktree remove .claude/worktrees/feature-<nom> && git branch -d feature/<nom>`.
Termine par un résumé de 5 lignes et le chemin de l'evidence.

---

## Règles de conduite

- **Un agent par étape, contexte vierge.** Tu passes des chemins et des faits, jamais ton historique.
  Le prompt de lancement tient en 15 lignes.
- **Le script décide, pas l'agent, pas toi.** Un gate est passé quand `pipeline.json → stages.<profil>`
  vaut `PASSED`, écrit par le hook. Ne te fie pas au rapport de l'agent pour ça.
- **Tu ne codes pas, tu ne corriges pas.** Une exception, explicite : corriger un test sur instruction
  de l'humain (étape 4), suivie d'un nouveau gel.
- **Tu ne pushes rien, tu ne crées rien d'externe.** C'est `create_mr` qui gère, avec validation.
- **Aux arrêts humains, sois court.** Ce que l'humain doit décider, les faits qui comptent, la question.
  Pas de récit de ce que les agents ont fait.
- **Chaque arrêt humain commence par le rapport.** `gauntlet.sh report <nom> <étape>` puis `SendUserFile`
  `display: render`, avant le texte et la question. Il est régénéré à chaque arrêt, jamais réutilisé.
  Les arrêts hors plan aussi : l'humain décide mieux avec le diagramme sous les yeux.
- **L'architecture appartient à l'humain.** Aucun agent ne tranche seul une décision structurante
  (package, couches, data sources, Stream/Future, dépendances, découpage des BLoCs). Un agent qui en
  rencontre une nouvelle en cours de route la remonte ; tu la poses à l'humain comme en 1a.
- **Une étape `FAILED` n'est jamais rejouée en silence.** L'humain décide.
- **`status`** : affiche `pipeline.json` sous forme de tableau (mode, package, étape, statut,
  tentatives, date) et les arrêts humains validés. Rien d'autre.
- **`accept <étape> "<raison>"`** : pose `"accepted": true` et la raison sur les entrées bloquantes
  du rapport de l'étape (`dedup.json`, `review.json`, `spec_review.json`, `tests_review.json`),
  ajoute `{stage, at, reason}` à `pipeline.json → accepted`, relance le verdict. Toujours sur
  instruction explicite de l'humain, jamais de ta propre initiative ; chaque acceptation apparaît
  dans l'evidence.
