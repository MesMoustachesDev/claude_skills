# flutter_feature — brick Mason

Squelette d'un package feature Flutter / Clean Architecture pour le feature pipeline (`/feature`).
Aligné sur `~/.claude/commands/templates/flutter/create_feature_rules.md`. Toutes les implémentations
sont des stubs `throw UnimplementedError()` : l'architect transcrit ensuite les contrats de la spec,
le test-writer écrit les tests, l'implementer fait passer au vert.

```bash
dart pub global activate mason_cli
mason add -g flutter_feature --path ~/.claude/bricks/flutter_feature
cd <racine du projet>/features
mason make flutter_feature --name recipe_list --remote true --local false --bloc true --presentation true
```

Un projet dont les conventions divergent (dossiers, nommage, imports) dérive son propre brick dans
`./bricks/feature/` via `/feature init`, et met `brick = project` dans `.claude/rules/feature_pipeline.md`.
