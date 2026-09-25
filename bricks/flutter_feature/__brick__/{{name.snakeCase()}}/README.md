# {{name.snakeCase()}}

## But

<!-- Un paragraphe : le problème utilisateur que ce package résout, et ce qu'il ne fait PAS.
     Source : spec.md §1 et §2. Le gate package_readme exige cette section. -->

## API publique

<!-- Une ligne par export du barrel lib/{{name.snakeCase()}}.dart. Le gate package_readme vérifie
     que chaque déclaration exportée est nommée ici. -->

| Export | Rôle |
|---|---|
| `{{name.pascalCase()}}Entity` | modèle métier |
| `{{name.pascalCase()}}Repository` | contrat d'accès aux données |{{#remote}}
| `Fetch{{name.pascalCase()}}UseCase` · `fetch{{name.pascalCase()}}UseCaseProvider` | |{{/remote}}{{#local}}
| `Watch{{name.pascalCase()}}UseCase` · `watch{{name.pascalCase()}}UseCaseProvider` | |{{/local}}{{#bloc}}
| `{{name.camelCase()}}BlocProvider` | |{{/bloc}}{{#presentation}}
| `{{name.pascalCase()}}Page` | écran principal |
| `{{name.pascalCase()}}Keys` | clés de widgets (tests, Maestro) |{{/presentation}}

## Dépendances

<!-- Packages partagés et inter-features, avec la raison des inter-features (spec §8). -->

## Vérifier

```bash
~/.claude/scripts/gauntlet.sh maintain {{name.snakeCase()}}
```
