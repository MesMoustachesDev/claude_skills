### 4. Implémentation — Ivan (`feature-implementer`)

Prompt : nom, `spec.md`, package, `tests.md`, et `.claude/features/<nom>/.gauntlet/last_red.log`
(ou `last_green.log` en reprise/boucle) — la sortie rouge. Au retour :
- `stages.green = PASSED` → continue.
- `FAILED` (5 tentatives) → **point imprévu** : montre le rapport de l'agent (ce qui bloque,
  tests suspects), les 40 dernières lignes du log, et propose : relancer Ivan avec une
  consigne / corriger un test suspect (toi, sur instruction explicite du dev, **et tu re-gèles** :
  nouveau commit, nouveau `tests_freeze_sha`) / revenir à la spec.
- Le rapport contient `Décision d'architecture requise` → **point imprévu** : c'est le code de
  Thibault. Montre l'extrait concerné (`fichier:ligne`) et ce qui existe ailleurs dans le repo, ouvre
  le fichier pour lui, et une question : « je modifie mon contrat » (« Réédition plus tard » de 0e)
  / l'option d'Ivan / l'autre. Puis `SendMessage` à Ivan avec la décision.
- Le rapport liste des « tests suspects » alors que le gate est vert → ajoute-les à
  `pipeline.json → suspect_tests` (`{file, line, why, by: "Ivan"}`) : la visite guidée (8b) les
  montre à l'étape du fichier concerné ; ne bloque pas.

**Gabarit S :** identique (gate `green` d'intégrité). **En L :** n'a pas lieu.

