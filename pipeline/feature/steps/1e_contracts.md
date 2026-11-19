### 1e. Point d'étape « contrats » : Thibault les écrit

`gauntlet.sh report <nom> contracts`, cité par un lien cliquable vers `report.html` : les
fichiers de `contracts.files`, les `DÉCISION (Thibault)` encore ouvertes avec `fichier:ligne`, les
déclarations qui existent déjà ailleurs (Denis), les scénarios validés de §4 pour rappel : chaque
contrat se lit en regard du scénario qui l'a fait naître.
**Puis, avant toute question : le résumé « Reprendre le fil »** — réécris `recap.json`, puis
`pipeline.sh recap <nom> .claude/features/<nom>/recap.json` (contenu : règle 4 de `commands/feature.md`).

**Une relecture, pas une découverte.** Les choix structurants ont été tranchés dans la discussion de
départ (0b) et Arthur les a appliqués : ne repose pas de question ouverte ici. Les `DÉCISION (Thibault)`
qui restent sont des choix mineurs, avec la proposition d'Arthur. Thibault veut rouvrir un choix du
cadrage → on en discute dans la session, du tac au tac, et la décision change dans `discussion.md` et le
cadrage avant qu'il édite.
**Ajouts proposés.** Montre ensuite, à part, le tableau `Détail | Proposition | Pourquoi c'est utile`
du rapport d'Arthur : ce sont ses ajouts, pas des décisions de Thibault. Chaque ligne est
contestable ; une ligne qu'il ne comprend pas s'explique avant qu'il édite.

**L'attente d'abord.** `pipeline.sh ask <nom> "Écris tes contrats : <n> fichiers, <n> DÉCISION"` : l'encart
« à lire » de pipeline-view montre chaque fichier en diff (avant la feature → état actuel). Il édite dans
l'IDE.

**Ouvre les fichiers pour lui.** Si l'outil `open_in_editor` est disponible (`mcp__ccd_host__open_in_editor`,
à charger par `ToolSearch` s'il est différé), ouvre chaque fichier de `contracts.files`, en commençant
par l'interface du repository, à la ligne de sa première `DÉCISION`. Sinon, un lien cliquable par
fichier (`[fichier](chemin:ligne)`). Dans ton message, en 12 lignes max : un fichier par ligne avec
ce qu'il déclare et le nombre de `DÉCISION` qu'il porte ; les verdicts `architect` de Denis (« `X`
existe déjà dans `core/…:12` : réutiliser ? ») ; et la consigne : « Édite ces contrats comme tu les
veux : signatures, découpage, noms. Les corps restent exactement `throw UnimplementedError()` (un
corps "évident" fait échouer `stub_check`). Une interface changée casse son impl stubbée (`analyze`)
et peut-être le README (`package_readme`) : Arthur peut les réaligner. Efface chaque `DÉCISION` une
fois tranchée. » Puis **attends** : `AskUserQuestion` « J'ai fini » / « Corrige le mécanique (impls
stubbées, imports, README) sans toucher à mes signatures » / « J'ai une question ».

- **Question** → réponds avec l'extrait de code (`fichier:ligne`) et ce qui existe ailleurs dans le
  repo, puis repose la même question. Une question n'est jamais un « j'ai fini ».
- **« J'ai fini »** → `grep -rn "DÉCISION (Thibault)" <package>/lib`. Il en reste : liste-les et pose
  une question par commentaire (« garder la proposition d'Arthur (Recommandé) » / « l'alternative » /
  « je l'édite »), par paquets de 4. Les « garder » / « alternative » et le mécanique demandé sont
  appliqués par Arthur en **mode application** (« applique ces choix, efface ces commentaires,
  réaligne impls stubbées, imports et README ; aucun scaffold, aucune autre signature ») ; à son
  retour, `pipeline.sh after-architect <nom>` comme en 1c. Puis `gauntlet.sh contracts <nom>`. Rouge → montre
  les erreurs (`fichier:ligne`) et propose « je corrige » / « Arthur corrige le mécanique ».
  « Appelants cassés » dans le rapport d'Arthur (tests ou fichiers hors package qui appellent une
  signature changée) → Théo les réaligne tout de suite, en background, sans attendre le rouge
  d'`analyze` : « ces appels ne compilent plus après le changement de signature ; adapte-les, ne
  change aucune assertion ». Idem pour les fichiers que nomme `after-architect` (tests à réaligner). Avant
  l'étape 3, le hook de Théo joue `analyze` et n'écrit pas `stages.red`.
- Verdicts `architect` de Denis : déclaration remplacée par l'existant → `"accepted": true, "reason":
  "remplacé par Thibault"` sur l'entrée ; gardée → Thibault donne sa raison, `accepted` avec elle.
  Puis `gauntlet.sh dedup_verdict <nom>` vert.
- **Gabarit** : plus de 2 `DÉCISION` dans le brouillon en S → question de reclassement en M ; plus
  de 5 en M → question « découper (L) / continuer en M » (voir « Gabarits »). Dans le premier
  `AskUserQuestion` de cet arrêt, avant qu'il édite.

Vert → `pipeline.sh commit-contracts <nom> thibault` : commit `feat(<nom>): contracts (by Thibault)`
des seuls fichiers du package, du manifeste et de `writes.extra` modifiés depuis `draft_sha`, avec
`--allow-empty` (Thibault peut garder le brouillon tel quel : c'est un choix, et le commit le date),
puis `contracts.sha`, `contracts.files` recalculé (un fichier de contrat ajouté par Thibault en fait
partie ; en mode extend, tout fichier source qu'il a édité aussi, même hors `contract_globs` : une
interface existante hors `domain/`, un fichier d'events d'un autre package — `contracts.edited`) et
`human_gates.contracts`. Les fichiers de
`contracts.files` sont désormais la référence : aucun agent ne change une de leurs signatures sans
lui (Arthur, Théo, Ivan et Nina rapportent un contrat qui ne tient pas, ils ne le contournent pas).

**Réédition plus tard** (contrat à revoir en 1f, décision demandée par Ivan…) :
Thibault édite, puis tu joues `gauntlet.sh contracts <nom>` (avant l'étape 2) ou `gauntlet.sh green
<nom>` (après : il y a du code autour) ; rouge → montre-le-lui avant tout commit. Vert →
`pipeline.sh commit-contracts <nom> reedit "<quoi>" <fichiers qu'il a édités>` : commit
`feat(<nom>): contracts (by Thibault) — <quoi>` des **seuls fichiers qu'il a édités** (jamais `-A` :
le travail en cours d'un agent ne doit pas y entrer), `contracts.sha` et `contracts.files` mis à jour.
Si un test gelé dépend du contrat changé :
re-gel, cause `contrat`.

**Gabarit S :** identique — c'est le moment où la feature devient la sienne. **En L :** n'a pas lieu.
**Découpage décidé ici (M → L)** : le brouillon et les contrats déjà commités restent sur
`feature/<nom>`. Le découpage se valide comme en 0b (5) ; la première sous-feature part de cette
branche (`base: feature/<nom>` dans son `pipeline.json`), et son 1c part des fichiers existants au
lieu de repartir de zéro ; les suivantes suivent l'ordre de dépendance.

