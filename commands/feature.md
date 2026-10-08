# Feature Pipeline — orchestrateur

**Le dev, c'est Thibault.** Il lance la commande et tranche à chaque point d'étape. Quand tu lui écris (questions, résumés, points d'étape), appelle-le Thibault et tutoie-le : « le dev » n'est que le nom de son rôle dans ce fichier.

Tu orchestres le pipeline de livraison d'une feature : une chaîne de sous-agents à contexte vierge,
un gauntlet de scripts entre chaque, et cinq points d'étape. **Tu n'écris aucun code toi-même.**
Ton rôle est de lancer le bon agent avec le bon contexte, lire les verdicts des scripts, et parler
au dev uniquement aux gates prévus ou quand une étape est en échec définitif.

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
- **mode `extend`** (`--in <package>`, ou décidé par Sophie en §8 « extension de … ») : le
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

Puis rappelle en trois lignes : les cinq points d'étape (architecture + spec, contrats, tests, mutants,
captures), chacun avec un rapport HTML, que rien
n'est pushé sans `create_mr`, et que `~/.claude/scripts/gauntlet.sh list` détaille chaque check.

---

## Références

| Quoi | Où |
|---|---|
| Gauntlet | `~/.claude/scripts/gauntlet.sh <profil> <nom>` — `doctor`, `list` |
| Rapport pour le dev | `~/.claude/scripts/gauntlet.sh report <nom> <étape>` → `.claude/features/<nom>/report.html` |
| Config projet | `.claude/rules/feature_pipeline.md` (template : `~/.claude/commands/templates/flutter/feature_pipeline.md`) |
| Règles de code | `.claude/rules/create_feature_rules.md` (template : `~/.claude/commands/templates/flutter/create_feature_rules.md`) |
| Template de spec | `~/.claude/commands/templates/flutter/feature_spec_template.md` |
| Brick global | `~/.claude/bricks/flutter_feature` |
| État | `.claude/features/<nom>/pipeline.json` |
| Issue GitLab | `~/.claude/pipeline/issue.md` (existante ou créée après la spec validée) |

Étapes, agents et profils de gate :

| # | Étape | Prénom | Agent (`subagent_type`) | Gate | Point d'étape après |
|---|---|---|---|---|---|
| 0b | cadrage | Sophie (mode cadrage) + toi | `feature-specifier` | — | **oui, interactif** : ce qui existe, le périmètre, les comportements, jusqu'à « c'est ça » |
| 1 | spec | Sophie | `feature-specifier` | — | non |
| 1b | critique | Camille | `feature-spec-critic` | `spec_review_verdict` | **oui** : décisions d'architecture une par une, puis la spec (boucle vers 1 avant) |
| 2 | contracts | Arthur | `feature-architect` | `contracts` | non |
| 2b | dedup | Denis | `feature-dedup` | `dedup_verdict` | **oui** : architecture réelle (code scaffoldé) vs architecture validée |
| 3 | tests | Théo | `feature-test-writer` | `red` | non |
| 3b | revue des tests | Gaëlle | `feature-test-reviewer` | `tests_review_verdict` | **oui** : skim de `tests.md` + `tests_review.md`, puis gel (boucle vers 3 avant) |
| 4 | impl | Ivan | `feature-implementer` | `green` | non |
| 5 | clean | Nina | `feature-cleaner` | `clean` | non |
| 5b | dedup | Denis | `feature-dedup` | `dedup_verdict` | non (boucle vers 5 si doublons) |
| 6 | review | Romain | `feature-reviewer` | `review_verdict` | non (boucle vers 4 si critiques) |
| 7 | harden | Hugo | `feature-hardener` | `harden` | **oui** : mutants expliqués |
| 8 | qa | Quentin | `feature-qa` | `qa` | **oui** : captures |
| 9 | evidence | — | toi (+ `graphify update` si le projet a un graphe) | — | puis `/create_commits` et `/create_mr` |

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
   S'il ne l'est pas, donne la commande `dart pub global activate mason_cli` et continue : Arthur
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
  la spec, §8 dit « extension de `features/x` » : tu confirmes avec le dev (« la spec propose
  d'étendre `x` plutôt que de créer un package — d'accord ? ») et tu bascules en `extend`.
- **Reprise** : si `.claude/features/<nom>/pipeline.json` existe, lis-le, affiche l'état (étape
  courante, gates passés, points d'étape validés) et reprends à la première étape non `PASSED`.
  Sinon crée le dossier et `pipeline.json` :
  ```json
  { "feature": "<nom>", "mode": "create|extend", "package": "<chemin du package>", "branch": "feature/<nom>", "base": "<base_branch>",
    "created": "<iso>", "stages": {}, "human_gates": {}, "attempts": {}, "tests_freeze_sha": null, "loops": {}, "accepted": [],
    "issue": null }
  ```
  `mode` et `package` sont lus par le gauntlet et les hooks : c'est ce qui définit le périmètre.
- **Issue GitLab** : `~/.claude/pipeline/issue.md`, partie A, avant de lancer Sophie (nouveau run
  seulement). Une issue existante fait partie de l'entrée de Sophie.
- **Branche** : déjà en place via le worktree (voir plus haut). Les modifications non commitées du
  checkout principal ne suivent pas : signale-le si elles concernent cette feature.
- Écris `<nom>` dans `.claude/features/.current` (secours pour les hooks quand la branche ne suit pas
  la convention).

### 0b. Cadrage fonctionnel — Sophie en mode cadrage, puis toi avec le dev (interactif)

Le dev doit savoir **ce qui va être fait** avant qu'une ligne de spec soit écrite. Un périmètre qui bouge
pendant les boucles de spec coûte une boucle Sophie + Camille par changement, et un changement qui
arrive après les contrats coûte la chaîne entière. Le cadrage fige le *quoi* ; la spec écrit le *comment*.

1. **Sophie, mode cadrage** (`feature-specifier`, prompt : « mode cadrage », nom, description brute,
   issue s'il y en a une, racine, sortie `.claude/features/<nom>/cadrage.md`). Elle explore et n'écrit
   pas de spec. `cadrage.md` contient, court :
   - **Ce qui existe déjà** : le code actuel qui fait tout ou partie du besoin, dans ce repo **et
     ailleurs** (autre plateforme, web, backend, autre feature), avec les valeurs en dur relevées
     (seuils, formats, limites) et les écarts entre eux. C'est souvent là que se cache la bonne réponse.
   - **Ce que je comprends du besoin** en 3 à 5 phrases, dans les mots du dev.
   - **Périmètre** : inclus / exclu, chaque ligne avec un exemple concret.
   - **Comportements visibles** : 5 à 10 exemples « quand … alors … » en français, sur des cas réels
     (« une photo portrait 4032×3024 prise à la caméra → stockée en 1920×2560 JPEG q85 »).
   - **Questions ouvertes** : chacune avec 2 à 3 options concrètes, une recommandée et pourquoi,
     et ce que chaque option change pour l'utilisateur.
   - **Règles non négociables** qui s'appliquent (`create_feature_rules.md`, gestion d'erreur…) :
     rappelées, jamais posées comme question.
2. **Toi, avec le dev.** `SendUserFile` de `cadrage.md` (`display: render`). Résume en 5 lignes ce qui
   existe et le périmètre proposé, puis pose les questions ouvertes par `AskUserQuestion` (4 max par
   appel, options concrètes, recommandée en premier). Le dev peut corriger le périmètre ou un exemple en
   texte libre : relance Sophie en mode cadrage avec ses réponses (« intègre, ne réécris pas le reste »),
   renvoie le cadrage, et recommence tant qu'il reste une question ou qu'un exemple le surprend.
3. **Fin du cadrage** : `AskUserQuestion` « C'est bien ça qu'on fait ? » (Oui / Non, je précise).
   Oui → `human_gates.cadrage = {at, by: "user"}`, `stages.cadrage = PASSED`.

**Le cadrage validé est l'entrée verrouillée de la spec.** Sophie le reprend en §1-§2 tel quel ; une
décision de §9 ne le contredit jamais. Un changement de périmètre demandé plus tard repasse par 0b
(cadrage mis à jour et revalidé) avant toute relance de la spec.

### 1. Spec — Sophie (`feature-specifier`)

Prompt de lancement : nom, `cadrage.md` validé (« périmètre et comportements figés : ne les rediscute
pas »), description brute (ou « aucune, à découvrir »), l'issue GitLab existante
entre `<issue>` s'il y en a une (`issue.md`, partie A), racine, chemin de sortie, et la phrase : « Tu proposes l'architecture, le dev la tranche : chaque décision structurante va en §9
avec le statut `proposée`, une alternative réelle et la raison. Tu ne la présentes pas comme acquise. »

### 1b. Critique — Camille (`feature-spec-critic`)

Lance Camille (`feature-spec-critic`, prompt : nom, `spec.md`, `archi.json`, `create_feature_rules.md`, template de spec).
Puis `gauntlet.sh spec_review_verdict <nom>` : rouge → relance le **specifier** avec
`spec_review.md` (« corrige ces points, sans réécrire ce qui n'est pas cité »), puis 1b à nouveau ;
`loops.spec`, max 2, puis tu montres les bloquants restants au dev avec la spec.

Vert → **Point d'étape 1 : architecture, puis spec.** Le dev garde la main sur l'archi : rien
n'est scaffoldé tant qu'il n'a pas tranché chaque décision.

**1a. Architecture.** `gauntlet.sh report <nom> spec`. Si la section « Architecture » porte le badge
« incohérence(s) » (archi.json ne colle pas à la spec), relance Sophie avec la liste affichée, sans
montrer le rapport, puis 1b ; ce compteur partage `loops.spec`. Sinon `SendUserFile` du `report.html`
(`display: render`, légende « décisions d'architecture à trancher »). Le rapport est interactif : un
résumé, les décisions (clic = surligner où elles s'appliquent ; « Voir l'alternative » redessine la
carte et l'arborescence), la carte de ce qui change par couche (squelette standard masqué), les
parcours en séquence, l'arborescence des fichiers ajoutés et modifiés. Dis-le en une ligne. Puis
`AskUserQuestion`, **une question par ligne de §9 au statut `proposée`** (par paquets de 4 questions
max par appel) :
- `header` : l'ID et le sujet (`A1 Package`) ; `question` : la décision en une phrase et son enjeu ;
- option 1 : la décision proposée, suffixée « (Recommandé) », avec la raison en description ;
- option 2 : l'alternative de §9, avec en description son `impact` tiré de `archi.json → decisions` ;
- « Other » reste ouvert pour une troisième voie.

Toutes acceptées → passe la colonne Statut de ces lignes à `validée` (édition de `spec.md`, seule
écriture que tu fais dans la spec avec l'en-tête). Au moins une changée → relance le **specifier** avec
la spec existante et les décisions imposées (« A2 : <choix du dev> — statut `modifiée`, répercute
sur §5, §6, §8, les scénarios concernés et `archi.json` ; ne touche pas aux autres décisions »), puis 1b, puis 1a à
nouveau **pour les seules lignes encore `proposée`** (une décision tranchée ne se repose pas).
`human_gates.architecture = {at, by: "user", decisions: {"A1": "validée", "A2": "modifiée"}}`.

**1b. Spec.** En 10 lignes max : objectif, périmètre, points signalés par le specifier, notes non
bloquantes du critique. Puis **ce qui sera testé**, tiré de `archi.json → scenarios` : le nombre total
de scénarios de §4, puis une ligne par scénario sélectionné, groupée et dans cet ordre (« Nominal : »,
« Limite : », « Erreur : »), avec sa phrase `fr`. C'est ce que le dev valide vraiment : ce que la
feature fera et où elle peut casser. La section « Scénarios » du rapport montre le Gherkin de chacun
et la liste complète ; renvoie-y plutôt que de recopier les steps.
Puis `AskUserQuestion` : « Valider la spec » / « Demander des modifications » (texte libre → relance
Sophie avec la spec existante + le retour, puis 1b ; repasse par 1a si §9 a bougé).
Validation → `human_gates.spec = {at, by: "user"}`, `stages.spec = PASSED`, et remplace « brouillon »
par « validée le <date> » dans l'en-tête de la spec.

**1c. Issue GitLab.** `issue.status == "to_create"` → `~/.claude/pipeline/issue.md`, partie B, gabarit
feature (spec et `archi.json` validés). Sinon rien.

### 2. Contrats — Arthur (`feature-architect`)

Prompt : nom, **mode**, `spec.md`, `create_feature_rules.md`, package, valeur de `brick`. En mode
`extend`, ajoute : « pas de scaffold ; ajoute dans l'existant ; ne renomme rien ». Au retour, vérifie
`stages.contracts` dans `pipeline.json` (le hook l'a écrit).
Le rapport mentionne un écart avec la spec → **point imprévu** : montre l'écart, propose
« corriger la spec et relancer Arthur » ou « accepter l'écart ». Note la décision dans `pipeline.json`.

### 2b. Roue réinventée — Denis (`feature-dedup`)

Le script cherche les ressemblances, l'agent juge, le script lit le verdict :
1. `gauntlet.sh dedup_candidates <nom>` → `.claude/features/<nom>/dedup_candidates.json`.
   S'il n'y a aucune entrée, saute l'agent : `stages.dedup = PASSED`.
2. Lance Denis (`feature-dedup`, prompt : nom, package, chemin des candidats, `spec.md`).
3. `gauntlet.sh dedup_verdict <nom>` : vert → `stages.dedup = PASSED`. À ce stade le verdict ne
   bloque que les entrées `fix_by: architect` (un choix de contrat : réutiliser un type, un use case).
   Les entrées `fix_by: cleaner` (factoriser du code existant, extraire un widget porteur de rendu)
   demandent du vrai code, qu'Arthur ne peut pas écrire sous le gate des stubs : le script les
   affiche « reportées à Nina » sans bloquer, tu les transmets à l'étape 5, et 5b les revérifie
   en bloquant. Ne relance jamais Arthur sur une entrée `cleaner`. Rouge → relance **Arthur**
   avec `dedup.md` (« ces déclarations existent déjà : utilise / étends l'existant », entrées
   `architect` seulement), puis 2b à nouveau ; `loops.dedup_contracts`, max 2, puis point imprévu. Le dev peut **accepter**
   un verdict (il a une raison) : tu poses `"accepted": true` sur l'entrée dans `dedup.json` avec sa
   raison, et le verdict repasse au vert. L'exemption apparaîtra dans l'evidence.

### 2c. Point d'étape 2 : architecture réelle

L'architecture existe maintenant en code. `gauntlet.sh report <nom> contracts`, puis `SendUserFile` du
`report.html` (`display: render`). La section « Architecture » s'ouvre en mode « Plan vs code » : la
même carte que celle validée en 1a, où chaque classe prévue absente du code apparaît en pointillé rouge
et chaque classe ajoutée hors plan en rouge plein ; l'arborescence s'ouvre sur « Écarts » (prévu absent,
non prévu, conforme, d'après git). La section « Code scaffoldé » liste les autres écarts (contrat de §5
absent du code, dépendance du pubspec non nommée en §8, classe domain/presentation hors §5), les
dépendances et les providers.

En 5 lignes : le nombre de classes par couche, les dépendances inter-features, les écarts (tous, un
par ligne). `AskUserQuestion` : « Valider l'architecture » / « Corriger : … » (texte libre).
- Correction qui reste dans la spec validée (nommage, découpage, placement) → relance **Arthur**
  avec le retour, puis 2b et 2c à nouveau.
- Correction qui change une décision de §9 ou un contrat de §5 → retour au **specifier** (décision
  imposée, statut `modifiée`), 1b, 1a pour cette ligne seulement, puis 2 depuis le début.
Validation → `human_gates.contracts = {at, by: "user"}`.

Puis commit : `git add -A <package> pubspec.yaml features/router features/l10n && git commit -m "feat(<nom>): scaffold and contracts"`.

### 3. Tests — Théo (`feature-test-writer`)

Prompt : nom, `spec.md`, package, la liste des chemins autorisés en lecture (`lib/src/domain/**`,
`lib/src/presentation/keys.dart`, `**/*_event.dart`, `**/*_state.dart`, `lib/src/data/model/*.dart`),
`~/.claude/commands/create_test.md`. Au retour, `stages.red` doit être `PASSED`.

### 3b. Revue des tests — Gaëlle (`feature-test-reviewer`)

Lance Gaëlle (`feature-test-reviewer`, prompt : nom, `spec.md`, package, `tests.md`, `create_test.md`).
Puis `gauntlet.sh tests_review_verdict <nom>` : rouge → relance le **test-writer** avec
`tests_review.md` (il complète et corrige les tests cités, il ne réécrit pas les autres), puis
`gauntlet.sh red`, puis 3b ; `loops.tests`, max 2, puis point d'étape avec les bloquants restants.

Vert → **Point d'étape 3.** `gauntlet.sh report <nom> tests`, `SendUserFile` du `report.html`
(`display: render`) : section « Scénarios » ouverte (sélection en français, chaque scénario marqué
présent ou absent des `.feature`), matrice scénarios §4 × `.feature`, inventaire des tests par
fichier. Rappelle en une ligne les scénarios sélectionnés absents des `.feature` s'il y en a. Puis montre
`.claude/features/<nom>/tests.md` (le fichier entier : c'est
court et c'est fait pour être lu), la table de couverture de `tests_review.md`, les tests « passe
déjà » avec la justification de l'agent, et les contrats manquants s'il y en a. `AskUserQuestion` :
« Valider les tests » / « Il manque des scénarios » (texte libre → relance Théo avec le
retour, puis 3b ; ses fichiers existants restent, il complète).

Validation → **gel** :
```bash
git add <package>/test <package>/pubspec.yaml && git commit -m "test(<nom>): acceptance and unit tests (frozen)"
```
Enregistre le SHA dans `pipeline.json → tests_freeze_sha`, `human_gates.tests`, `stages.red = PASSED`.
À partir d'ici, `test/` ne change plus, sauf ajouts de Hugo.

### 4. Implémentation — Ivan (`feature-implementer`)

Prompt : nom, `spec.md`, package, `tests.md`, et `.claude/features/<nom>/.gauntlet/last_red.log`
(ou `last_green.log` en reprise/boucle) — la sortie rouge. Au retour :
- `stages.green = PASSED` → continue.
- `FAILED` (5 tentatives) → **point imprévu** : montre le rapport de l'agent (ce qui bloque,
  tests suspects), les 40 dernières lignes du log, et propose : relancer Ivan avec une
  consigne / corriger un test suspect (toi, sur instruction explicite du dev, **et tu re-gèles** :
  nouveau commit, nouveau `tests_freeze_sha`) / revenir à la spec.
- Le rapport contient `Décision d'architecture requise` → **point imprévu**, comme en 1a :
  rapport HTML, une question avec les deux options. La réponse va en §9 (nouvelle ligne, statut
  `validée` ou `modifiée`), puis `SendMessage` à Ivan avec la décision.
- Le rapport liste des « tests suspects » alors que le gate est vert → transmets-les tel quel à
  le point d'étape 4, ne bloque pas.

### 5. Nettoyage — Nina (`feature-cleaner`)

Prompt : nom, package, `last_clean.log` si présent, et `dedup.md` s'il porte des entrées
`fix_by: cleaner` reportées depuis 2b (« applique ces factorisations ; 5b les revérifie et bloque »).
`stages.clean = PASSED` → continue ; `FAILED` → même traitement qu'en 4.

### 5b. Roue réinventée, second passage — Denis (`feature-dedup`)

Même mécanique qu'en 2b, sur le code implémenté (helpers, widgets, extensions apparus pendant 4 et 5).
Rouge → relance le **cleaner** avec `dedup.md`, puis 5b ; `loops.dedup_clean`, max 2.

### 6. Revue — Romain (`feature-reviewer`)

D'abord les scripts : `~/.claude/scripts/gauntlet.sh maintain <nom>` (dépendances inter-features
justifiées, santé des packages pub.dev, design system, l10n, code mort, périmètre, secrets…). Son
verdict n'arrête rien ici : le log est une **entrée** de Romain, qui transforme chaque échec en finding.

Prompt : nom, `spec.md`, package, `tests_freeze_sha` (base du diff), `tests.md`,
`.claude/features/<nom>/.gauntlet/last_maintain.log`, `.claude/features/<nom>/dedup.md`,
`.claude/rules/pr_rules.md` si présent, `.claude/rules/create_feature_rules.md`,
`~/.claude/commands/reviewPR.md`.
Au retour, `gauntlet.sh review_verdict <nom>` (le hook de l'agent n'a vérifié que le format — un
reviewer qui trouve des critiques doit pouvoir rendre la main) :
- vert → `stages.review = PASSED`. Affiche **tout de suite** au dev chaque entrée de
  `review.json → suggestions` (une ligne : fichier, problème, correctif), et demande en un
  `AskUserQuestion` multiSelect lesquelles appliquer dans la feature. Les retenues repartent à
  Ivan puis à Nina, avant Hugo ; les autres vont en « Suggestions non appliquées »
  dans l'evidence. Ne jamais résumer les suggestions en un simple nombre.
- rouge → **boucle** : `loops.review += 1`. Si ≤ 2 : relance **Ivan** (prompt : la liste
  `critical` avec `fix`, plus le contexte habituel), puis le **cleaner**, puis le **reviewer**.
  Au-delà de 2 : point imprévu avec la liste des critiques persistantes.

### 7. Durcissement — Hugo (`feature-hardener`)

Prompt : nom, package, chemin du rapport de mutation, `review.json` (pour `missing_tests`).
`stages.harden = PASSED` → **point d'étape 4.** `gauntlet.sh report <nom> mutants` et `SendUserFile`
(`display: render`). Montre `mutants.md` en entier, le score, le nombre de
tests ajoutés, les tests existants signalés suspects (4 et 7), et `review.json → suggestions` en
résumé. `AskUserQuestion` : « Valider » / « Ces explications ne tiennent pas : … » (texte libre →
relance Hugo avec le retour). Validation → `human_gates.mutants`.

### 8. QA — Quentin (`feature-qa`)

Prompt : nom, `spec.md`, package, `feature_pipeline.md`. Au retour, quel que soit le gate :
**point d'étape 5.** `gauntlet.sh report <nom> qa` (les captures y sont intégrées). Montre `qa.md` en
entier et envoie le rapport puis les captures avec `SendUserFile`
(`.claude/features/<nom>/qa/*/*.png`, toutes, en un appel par plateforme) — le dev regarde des
images, pas des chemins. `AskUserQuestion` : « Valider » / « Défauts bloquants : … » (→ relance
Ivan avec les défauts, puis Nina, Romain et Hugo sont **sautés** si `lib/` n'a changé
que dans `presentation/**/view/**` — sinon rejoue 5→7 — puis QA à nouveau ; `loops.qa`, max 2).
Validation → `human_gates.qa`.

### 9. Evidence, commits, MR

**9a. Graphe graphify (seulement si le projet en a un).** Cherche un `graphify-out/graph.json` dans le
checkout principal (`git worktree list --porcelain` → premier `worktree`), à la racine ou un niveau
en dessous. Absent → saute 9a, et pas de section « Impact » dans l'evidence. Présent :
1. Dans le worktree, garantis que `graphify-out/` est ignoré : `git check-ignore -q graphify-out/x`,
   sinon ajoute `graphify-out/` à `$(git rev-parse --git-common-dir)/info/exclude` (jamais au
   `.gitignore` versionné depuis le pipeline). `create_commits` ne doit jamais l'embarquer.
2. Copie le dossier `graphify-out/` du checkout principal au même chemin relatif dans le worktree.
   Copie aussi le `graphify-out/cache/` qui se trouve sous la racine de scan, s'il existe.
3. Racine de scan : le contenu de `graphify-out/.graphify_root`, avec le préfixe du checkout
   principal remplacé par celui du worktree. Puis, depuis le dossier qui contient `graphify-out/` :
   `graphify update <racine de scan du worktree>`. C'est de l'AST seul, sans LLM et sans coût. Échec → note-le dans
   l'evidence et continue : graphify ne bloque jamais la livraison.
4. **Impact** : dans `graph.json`, prends les nœuds dont le `source_file` est dans
   `git diff --name-only <base>...HEAD`. Puis leurs voisins directs situés dans **un autre package**. Liste
   ces packages et les symboles par lesquels ils sont touchés : ce sont les consommateurs que la MR
   peut casser. Ignore les nœuds génériques (types du SDK, `_`, imports de `package:core/*`).

Le graphe mis à jour reste dans le worktree. Le checkout principal se rafraîchira avec
`/graphify <racine> --update` après le merge.

Écris `.claude/features/<nom>/evidence.md` — la page que le dev lit à la place du code :

```
# Evidence — <nom>
Spec validée le <date> · Branche feature/<nom> · Base <base>@<sha>
Issue : #<iid> <url>                ← si pipeline.json → issue existe (issue.md, partie C)

## Architecture                      ← archi.json → summary + §9 avec le statut final de chaque décision
| ID | Décision | Statut (validée / modifiée par le dev) |

## Acceptation
| Scénario | Widget test | Android | iOS |   ← §4 × tests.md × qa.md

## Mesures
Tests : <n> (dont <n> ajoutés par Hugo) · Couverture lignes modifiées : <n>%
Mutation : <n>% (<n> mutants, <n> survivants expliqués) · Complexité max : <n> · Dépendances : ✓
Revue : <n> critiques (résolues), <n> suggestions · Règles projet : <n>/<n> · Maintenabilité : <n>/7

## Maintenabilité                    ← last_maintain.log + review.json → rules_checked.maintainability
Dépendances inter-features : <liste, justifiées §8> · Packages ajoutés : <liste avec date de release>
Roue réinventée : <n> paires jugées, <n> doublons résolus, <n> verdicts acceptés par le dev (<raisons>)   ← dedup.json
Widgets vs design system : <n> comparés, <n> remplacés, <n> extensions du DS                              ← dedup.json
Exemptions gauntlet-ignore : <n> (<où>)

## Impact (graphify)                  ← 9a, seulement si le projet a un graphe
| Package consommateur | Symboles touchés |

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
lui indiquant que la description de MR est `evidence.md` et l'issue liée (`issue.md`, partie C). `create_mr` applique ses propres règles de
validation du dev avant tout push ou création : tu ne les contournes pas.

`stages.evidence = PASSED`. Sors du worktree avec `ExitWorktree` `action: "keep"` (la branche reste
pour la MR) et donne la commande de nettoyage à lancer après le merge, sans l'exécuter :
`git worktree remove .claude/worktrees/feature-<nom> && git branch -d feature/<nom>`.
Termine par un résumé de 5 lignes et le chemin de l'evidence.

---

## Règles de conduite

- **Gestion d'erreur (règle de base, non négociable)** : un `try/catch` n'existe que dans `lib/src/data/`, autour de l'I/O (réseau, fichiers, stockage, galerie, canal plateforme, plugin natif). La couche data le convertit en `Either<ErrorEntity, T>`. Domain (use cases, entités, services de domaine), presentation et injection ne contiennent **aucun** `try/catch` : ils composent des `Either` (`flatMap` / `flatMapAsync`) et seul le BLoC les déplie. Attraper `on Object` en data quand un plugin lève une `Error` (ex. `CompressError`). Une décision §9 ne peut pas y déroger. Le gauntlet le vérifie (check `error_handling`). Un agent qui propose ou accepte un écart est renvoyé ; ne pose jamais cette règle comme question au dev.
- **Les agents ont un prénom.** Dans tes messages au dev, tes rapports et tes prompts de lancement,
  désigne chaque agent par son prénom (tableau des étapes) ; le slug `feature-*` ne sert qu'au `subagent_type`.
- **Un agent par étape, contexte vierge.** Tu passes des chemins et des faits, jamais ton historique.
  Le prompt de lancement tient en 15 lignes.
- **Le script décide, pas l'agent, pas toi.** Un gate est passé quand `pipeline.json → stages.<profil>`
  vaut `PASSED`, écrit par le hook. Ne te fie pas au rapport de l'agent pour ça.
- **Tu ne codes pas, tu ne corriges pas.** Une exception, explicite : corriger un test sur instruction
  du dev (étape 4), suivie d'un nouveau gel.
- **Tu ne pushes rien, tu ne crées rien d'externe.** C'est `create_mr` qui gère, avec validation. Seule
  exception : l'issue GitLab de 1c, dont le dev valide le contenu exact avant l'envoi.
- **Aux points d'étape, sois court.** Ce que le dev doit décider, les faits qui comptent, la question.
  Pas de récit de ce que les agents ont fait.
- **Chaque point d'étape commence par le rapport.** `gauntlet.sh report <nom> <étape>` puis `SendUserFile`
  `display: render`, avant le texte et la question. Il est régénéré à chaque arrêt, jamais réutilisé.
  Les points imprévus aussi : le dev décide mieux avec le diagramme sous les yeux.
- **L'architecture appartient au dev.** Aucun agent ne tranche seul une décision structurante
  (package, couches, data sources, Stream/Future, dépendances, découpage des BLoCs). Un agent qui en
  rencontre une nouvelle en cours de route la remonte ; tu la poses au dev comme en 1a.
- **Une étape `FAILED` n'est jamais rejouée en silence.** Le dev décide.
- **`status`** : affiche `pipeline.json` sous forme de tableau (mode, package, étape, statut,
  tentatives, date), l'issue (iid et URL) et les points d'étape validés. Rien d'autre.
- **`accept <étape> "<raison>"`** : pose `"accepted": true` et la raison sur les entrées bloquantes
  du rapport de l'étape (`dedup.json`, `review.json`, `spec_review.json`, `tests_review.json`),
  ajoute `{stage, at, reason}` à `pipeline.json → accepted`, relance le verdict. Toujours sur
  instruction explicite du dev, jamais de ta propre initiative ; chaque acceptation apparaît
  dans l'evidence.

---

## Dépannage — causes déjà identifiées

À lire avant de chercher. Chaque entrée : symptôme → cause → ce qui est en place / quoi faire.

- **`test` ou `red_check` : « aucun test exécuté » alors que `flutter test` passe à la main.**
  Cause : le moteur Flutter écrit parfois une ligne de log natif sur stdout au milieu du rapport
  `--reporter json` (ex. `Shell: [ERROR:flutter/runtime/dart_isolate.cc(…)] Callbacks into the Dart VM
  are currently prohibited…`, vu avec `ui.ImageDescriptor` / `compute`). `jq -s` échoue sur toute la
  ligne et le gauntlet lit 0 test. En place : `test_results` (`checks_test.sh`) ne passe à `jq` que les
  lignes qui commencent par `{`. Si ça revient : `grep -vn '^{' .gauntlet/test_report.jsonl`.
- **Deux gates en même temps sur la même feature** (le hook de fin d'un agent + un run lancé à la main) :
  rapports écrasés, `.gauntlet/` incohérent. Attends la fin de l'un avant l'autre. La mutation a un
  verrou (`.gauntlet/mutation.lock`, avec pid) ; les autres profils n'en ont pas encore.
- **Un `mutation_test` tué laisse un mutant dans le code source** (en mode en place, `app_dir = .`).
  En place : restauration garantie (`mutation_restore`), et avec `app_dir` ≠ `.` la mutation tourne
  dans des clones APFS, le dépôt n'est jamais muté. En cas de doute : `git diff -- <package>/lib`.
- **Mutation très lente (~60 s par mutant).** Cause : un mutant fait bloquer un test (flux qui n'émet
  plus) jusqu'au timeout de 30 s, pas la compilation (3 à 8 s). En place : `--fail-fast --timeout
  <mutation.test_timeout>`, tests ciblés `foo_test.dart` + `foo_*_test.dart`, file partagée,
  tranches de `mutation.shard_lines` lignes, `mutation.workers` clones.
- **Mutation : tous les fichiers en `BASELINE_KO`.** Les clones ont disparu (un autre run a nettoyé
  `.gauntlet/mutation-clones`) ou les tests échouent déjà sans mutant sous charge (monter
  `mutation.test_timeout`). Voir `mutation-worker-*.log`.
- **Une commande en arrière-plan qui dure plus d'environ 1 h 30 peut être tuée sans trace.** Garde
  chaque gate sous ce budget, et surveille un run long (Monitor) au lieu d'attendre sa notification.
- **Un agent bloqué ne notifie rien.** Un sous-agent figé (stream coupé, attente d'un gate) reste
  « en cours » sans processus. Si un gate dure, vérifie qu'un `flutter test` / `mutation_test` tourne
  vraiment (`ps`), sinon arrête l'agent et relance.
- **Hook d'écriture qui refuse un fichier attendu.** `writes.extra` est un glob : un dossier ou un
  submodule s'écrit `x/**` (pas `x`). Les `test/` et `pubspec.yaml` des packages `<pkg>/lib/**` de
  `writes.extra` sont autorisés aux tests. Ne jamais contourner le hook par le shell : corriger la
  config, avec l'accord du dev.
