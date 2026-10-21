# Format des remarques — agents de /reviewPR

Chaque agent écrit **un seul fichier**, `<dossier de la revue>/findings_<rôle>.json` (`archi`, `code`
ou `qa`), puis rend un rapport de trois lignes au plus. `review.sh findings` fusionne les trois,
numérote (F1, F2…), retire les doublons (même fichier, même ligne, même titre) et trie les critiques
en tête. Une remarque incomplète est écartée et signalée : remplis tous les champs obligatoires.

```json
{
  "role": "archi",
  "summary": "Une phrase : ce que tu as relu et ce qui en ressort.",
  "grid": {
    "architecture": "ok — couches respectées, Either déplié dans le BLoC",
    "roue_reinventee": "ko — F2",
    "dependances": "na"
  },
  "findings": [
    {
      "severity": "critical",
      "title": "Titre court, le problème et pas la solution",
      "file": "features/esl/lib/src/data/esl_repository_impl.dart",
      "line": 42,
      "problem": "Ce qui ne va pas, en une ou deux phrases, factuel.",
      "why": "Pourquoi c'est un problème ici : conséquence concrète, règle enfreinte (pr_rules, grille), ou écart au voisin de référence.",
      "evidence": "Ce que tu as lu ou lancé pour l'établir : `git grep -n is_reachable origin/develop -- lib/` → 3 résultats ; fichier:ligne du voisin.",
      "suggestion": "Comment corriger, avec un extrait si utile.",
      "comment": "Le commentaire tel qu'il serait posté sur la MR : poli, direct, autoportant, en français, sans « nous » ni formule creuse. Il cite le fichier et la ligne si le commentaire est général."
    }
  ]
}
```

- `severity` : `critical` (à corriger avant merge : bug, régression, faille, violation d'architecture,
  roue réinventée avérée, `[FAIL]` du gauntlet), `suggestion` (non bloquant, `[WARN]` compris),
  `question` (contexte manquant, à demander à l'auteur).
- `file` est relatif à la racine du repo ; `line` est une ligne de la **nouvelle** version du fichier,
  dans le diff de la MR si possible (un commentaire en ligne n'est accepté que sur une ligne modifiée ;
  ailleurs, il est posté en commentaire général). Remarque sans fichier : omets `file` et `line`.
- `evidence` est obligatoire de fait : une remarque qu'on ne peut pas vérifier ne sera pas postée. Le
  graphe graphify oriente, le `git grep` fait foi.
- `grid` : les items de la grille qui sont les tiens (voir ton fichier d'agent), `ok` / `ko` / `na`
  avec une ligne de justification.
- Rien de ce que le gauntlet a mesuré n'est reformulé en opinion : « le script signale … ligne 12 ».
- La QA ajoute `"scenarios"` : voir `review-qa`.
