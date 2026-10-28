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
  `writes.extra` sont autorisés aux tests. Ne jamais contourner le hook par le shell : ouvrir la zone
  pour cette feature, `pipeline.sh extra <nom> "<glob>"` (guillemets : sinon le shell développe `**`) (chemins touchés par la spec et les contrats
  validés : sans demander, règle du dev ; tout autre chemin : avec son accord). La config du projet
  (`writes.extra` de `feature_pipeline.md`) ne garde que les zones que toutes les features touchent.
- **Captures QA perdues après un second run.** Cause : `gauntlet.sh qa` effaçait `qa/<plateforme>/*.png`
  à chaque lancement, et le hook de fin de Quentin le relance. En place : le run précédent (captures,
  `report.xml`, `maestro.log`) est déplacé dans `qa/<plateforme>/_runs/<date>/`, jamais effacé.
- **Flows Maestro exécutés dans le désordre malgré `config.yaml` (`executionOrder`).** Cause :
  `maestro test <dossier>` sans `--config`. En place : `<package>/maestro/config.yaml` est passé en
  `--config` quand il existe, et n'est plus compté comme un flow.
- **Le hook de fin de Quentin rejoue des flows à usage unique** (ex. « Appliquer ») après un run manuel.
  En place : le hook réutilise le verdict du dernier `gauntlet.sh qa` fini sur le même état (HEAD +
  modifications non commitées hors `.claude/`, `.gauntlet/qa_last_run.json`) sans rien rejouer. Un
  `gauntlet.sh qa` lancé à la main tourne toujours ; un flow modifié change l'état et relance le hook.
- **Mutation muette sur un autre package modifié par la feature** (`writes.extra`). La mutation ne
  tourne que sur le package de `pipeline.json`. En place : `mutation` et `mutation_scope` listent les
  fichiers de logique modifiés dans les packages de `writes.extra` (« non muté »,
  `.gauntlet/mutation_scope_extra.txt`) : à reporter dans la revue et l'evidence.
- **Clé l10n existante traduite dans une seule langue** (ex. `labelRetry`, anglais seulement : la VF
  affiche « Retry »). Cause : `l10n_arb` ne vérifiait que les clés ajoutées. En place : il vérifie aussi
  les clés existantes que le code modifié lit via `l10n.<clé>`.
- **Le test-writer ne peut pas écrire dans `test/` d'un package ouvert en `<pkg>/**`.** En place : un
  `<pkg>/**` de `writes.extra` (dossier avec `pubspec.yaml`) compte comme `<pkg>/lib/**` : ses `test/`
  et `pubspec.yaml` sont ouverts au test-writer et au hardener, et ses tests sont gelés pour Ivan et Nina.
- **`stub_check` / `red_check` rouges sur du code ou des tests d'une passe déjà validée** (rejeu après
  amendement). En place : `pipeline.json → pass_base` (voir « Rejeu » en 0, Préconditions) restreint ces deux gates
  à ce qui a changé depuis. Ne pas `accept` : poser `pass_base`.
- **`deps_features` rouge sur une dépendance ou un cycle déjà présents sur la base** (mode extend).
  En place : seuls une dépendance absente du pubspec de la base et un cycle qui emprunte une arête
  ajoutée bloquent ; le reste sort en `[WARN] … préexistant`, à reporter en dette.
- **Couverture, métriques ou checks de lignes rouges sur du code existant seulement reformaté** (`dart
  format` sur un fichier entier, mode extend). En place : `drop_format_only` (`lib.sh`, avec
  `format_only.py`) retire du périmètre et des lignes à couvrir toute ligne `.dart` dont les tokens sont
  inchangés depuis la base (recoupée, recollée, réindentée, virgule finale). `coverage` l'annonce : « n
  ligne(s) seulement reformatée(s) ». Ne pas `accept` : si une ligne reformatée est encore comptée, elle
  porte un vrai changement de token. Les `conventions` de `/fix` gardent ces lignes
  (`GAUNTLET_KEEP_FORMAT_LINES=1`). Repro : `tests/test_format_only.sh`.
- **Package dans un submodule (`flutter_app/hades`) invisible au gauntlet.** En place : les diffs
  (périmètre, gel, couverture, `writes.extra`, empreinte QA) tournent dans le submodule, depuis le
  gitlink que la base enregistre. Un `tests_freeze_sha` peut être un commit du parent ou du submodule.
- **`stub_check` / `dup_check` cassés, « Dart 2.18 ».** Cause : `fvm dart` lancé depuis la racine du
  repo, sans `.fvmrc` (il vit dans `app_dir`) → SDK global. En place : les outils Dart tournent depuis
  `app_dir` ; `gauntlet.sh doctor` vérifie que `.fvmrc` est lisible depuis `app_dir` et que le SDK
  résolu est celui épinglé.
- **Session isolée en worktree : « this command runs rtk with a git command… Refusing to run it ».**
  Cause : le hook rtk réécrit `git …` en `rtk git …`, que le garde-fou du worktree refuse (de même pour
  un glob ou une variable passés à rtk). Le hook rtk reste tel quel : dans ce cas seulement, appeler
  `/usr/bin/git` (non réécrit par rtk). Les autres commandes passent toujours par rtk.
