Banc de tâches (hors pipeline : pas de pipeline.json, pas de gauntlet).

Le package Dart du dossier courant expose `slugify` (`lib/src/slug.dart`, un stub
`throw UnimplementedError()`). Sa spec est `spec.md`. Écris les tests de `slugify` dans
`test/slug_test.dart` (package:test), contre la spec seule : chaque règle doit être prouvée par au
moins un test dont l'assertion échouerait si la règle était mal codée. Ne touche ni à `lib/` ni à
`spec.md`, n'écris aucune implémentation. La suite doit compiler et être rouge (`dart test`).
Termine par une ligne « FINI ».
