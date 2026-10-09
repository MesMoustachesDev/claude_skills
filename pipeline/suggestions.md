# Suggestions de revue — format et présentation au dev

Partagé par `/feature` (Romain, `feature-reviewer`) et `/fix` (Victor, `fix-reviewer`). Une suggestion
est une amélioration non bloquante : c'est le dev qui décide si on la traite. Pour décider, il a besoin
du problème, de sa raison d'être et du prix du correctif, pas d'un titre.

## Ce que le reviewer écrit — `review.json → suggestions[]`

```json
{
  "id": "S1",
  "summary": "Titre court, 3 à 6 mots",
  "file": "lib/src/...", "line": 42, "rule": "pr_rules: <item> | universal: <catégorie> | ...",
  "problem": "Ce qui ne va pas, concrètement, dans le code tel qu'il est.",
  "why": "Pourquoi c'est un problème : la règle, le principe ou le risque en jeu.",
  "cause": "D'où ça vient : choix d'implémentation, contrainte, copie d'un existant, oubli.",
  "consequences": "Ce qui arrive si on ne fait rien : pour l'utilisateur, la maintenance, les prochaines features.",
  "fix": "Le correctif proposé, assez précis pour être appliqué sans relire la revue.",
  "pros": "Ce que le correctif apporte.",
  "cons": "Ce qu'il coûte ou risque : temps, fichiers touchés, régression possible, périmètre élargi.",
  "effort": "S | M | L"
}
```

Une à deux phrases par champ, pas plus. Les `id` se suivent (`S1`, `S2`…) et ne changent plus une
fois écrits. `cons` n'est jamais « aucun » : un correctif coûte toujours au moins du temps et un
re-passage des gates ; dis lequel. `effort` : S = quelques lignes dans un fichier, M = plusieurs
fichiers ou un test à ajouter, L = un découpage ou une API qui change. Le gate de format refuse
une suggestion à laquelle il manque un champ.

## Ce que l'orchestrateur montre au dev

Toutes les suggestions, une par bloc, dans cet ordre, sans résumer ni regrouper :

```
**S1 — <summary>** · `<file>:<line>` · effort <S|M|L>
- **Problème** : <problem>
- **Pourquoi c'est un problème** : <why>
- **Cause** : <cause>
- **Si on ne fait rien** : <consequences>
- **Correctif** : <fix>
- **Pour** : <pros> · **Contre** : <cons>
```

Puis un `AskUserQuestion` en `multiSelect: true` : une question par lot de 4 suggestions au plus
(header `S1–S4`, `S5–S8`…), 4 questions par appel, d'autres appels s'il en reste. Une option par
suggestion : label `S1 <summary>`, description `effort <S|M|L> · + <pros, en quelques mots> ·
− <cons, en quelques mots>`. Un lot d'une seule suggestion reçoit une seconde option « Aucune de ce
lot ». Aucune case cochée = suggestion non retenue. « Other » permet au dev de nuancer
(« S3 mais sans toucher à X ») : transmets sa phrase telle quelle avec la suggestion.

Les retenues partent à l'implementer avec leur bloc complet (`problem`, `fix`, et la nuance du dev).
Les autres vont dans l'evidence avec leur bloc, sous « Suggestions non appliquées ». Ne jamais
réduire les suggestions à un nombre ou à une liste de titres.
