Banc de tâches (hors pipeline : pas de pipeline.json, pas de spec.md, pas de gauntlet).

Relis le dernier commit du dossier courant (`git diff HEAD~1 HEAD`), un package Dart de pagination,
comme tu relirais une MR : défauts de logique, cas limites, gestion d'erreur. Écris tes constats dans
`review.json` à la racine : une liste `[{"file": "lib/src/…", "line": 12, "severity": "blocker" |
"major" | "minor", "summary": "…"}]`, `line` dans le fichier après le commit. Ne modifie aucun autre
fichier. Termine par une ligne « FINI ».
