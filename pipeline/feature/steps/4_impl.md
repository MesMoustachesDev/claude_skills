### 4. Implémentation — Ivan en deux moitiés parallèles

Le premier passage s'implémente en **deux agents lancés dans le même message**, chacun sur sa couche, avec
sa zone d'écriture (hook) et son gate de couche. Les tests de présentation mockent les use cases : aucune
moitié n'attend l'autre.

| Moitié | `subagent_type` | Écrit | Gate (hook) |
|---|---|---|---|
| data/domain | `feature-implementer-data` | couches data, domain, injection du package | `green_data` |
| présentation | `feature-implementer-presentation` | le reste du code du package, `writes.extra` (router, l10n) | `green_presentation` |

Prompt commun : nom, `spec.md`, package, `tests.md`, et « tu implémentes en parallèle de l'autre moitié ;
ton fichier d'agent dit ta zone ». La sortie rouge de sa couche : `.claude/features/<nom>/.gauntlet/last_red.log`
(le gate complet de l'étape 3), ou `.gauntlet/<couche>/last_green_<couche>.log` en reprise. En plus, pour la
présentation : `create_screen_rules.md` si la feature a une page. Les deux reviennent quand leur gate de
couche est vert (`stages.green_data`, `stages.green_presentation`, écrits par leur hook).

Puis **`pipeline.sh join <nom> green`** : refuse tant qu'une moitié n'est pas verte, sinon joue le gate
complet (`green` : toute la suite, analyse et stubs du package entier) et écrit `stages.green`.
- `join` vert → continue.
- `join` rouge alors que les deux moitiés sont vertes : c'est la jonction. Relance **Ivan complet**
  (`feature-implementer`) avec `.gauntlet/last_green.log`, puis `join` à nouveau.
- **Reprise** : `pipeline.sh next` affiche l'état de chaque moitié ; ne relance que celle qui n'est pas
  `PASSED`.
- **Une seule couche touchée** : lance seulement cette moitié, et `pipeline.sh skip <nom> green_<autre>
  "<raison, tirée de §8>"` ; `join` accepte une moitié `SKIPPED`.

Au retour de chaque moitié (et d'Ivan complet) :
- `FAILED` (5 tentatives) → **point imprévu** : montre le rapport de l'agent (ce qui bloque,
  tests suspects), les 40 dernières lignes du log de sa couche, et propose : relancer cette moitié avec une
  consigne / corriger un test suspect (toi, sur instruction explicite du dev, **et tu re-gèles** :
  nouveau commit, nouveau `tests_freeze_sha`) / revenir à la spec. L'autre moitié, verte, ne se relance pas.
- Le rapport contient `Décision d'architecture requise` → **point imprévu** : c'est le code de
  Thibault. Si l'autre moitié tourne encore et que la décision peut toucher un fichier qu'elle lit (une
  signature, un `ErrorEntity`, un état), laisse-la finir sans la relancer, puis tranche. Montre l'extrait
  concerné (`fichier:ligne`) et ce qui existe ailleurs dans le repo, ouvre le fichier pour lui, et une
  question : « je modifie mon contrat » (« Réédition plus tard » de 0e) / l'option d'Ivan / l'autre. Puis
  `SendMessage` à la moitié concernée avec la décision ; si le contrat a changé, l'autre moitié repasse
  son gate (`gauntlet.sh green_<couche> <nom>`) avant `join`.
- Le rapport liste des « tests suspects » alors que le gate est vert → ajoute-les à
  `pipeline.json → suspect_tests` (`{file, line, why, by: "Ivan (data)" | "Ivan (présentation)"}`) : la
  visite guidée (8b) les montre à l'étape du fichier concerné ; ne bloque pas.

Les **relances suivantes** — critiques de Romain (6), retours de la visite (8b), défauts de Quentin (8) — vont
à **Ivan complet** (`feature-implementer`) : un retour peut traverser les couches.

**Gabarit S :** identique, deux moitiés comprises (gate `green` d'intégrité au `join`). **En L :** n'a pas lieu.
