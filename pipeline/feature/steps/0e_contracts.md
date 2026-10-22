### 0e. Point d'étape « contrats » : Thibault les écrit

`gauntlet.sh report <nom> contracts` puis `SendUserFile` du `report.html` (`display: render`) : les
fichiers de `contracts.files`, les `DÉCISION (Thibault)` encore ouvertes avec `fichier:ligne`, les
déclarations qui existent déjà ailleurs (Denis), les séquences du cadrage pour rappel.

**Une relecture, pas une découverte.** Les choix structurants ont été tranchés dans la discussion de
départ (0b) et Arthur les a appliqués : ne repose pas de question ouverte ici. Les `DÉCISION (Thibault)`
qui restent sont des choix mineurs, avec la proposition d'Arthur. Thibault veut rouvrir un choix du
cadrage → on en discute dans la session, du tac au tac, et la décision change dans `discussion.md` et le
cadrage avant qu'il édite.
**Ajouts proposés.** Montre ensuite, à part, le tableau `Détail | Proposition | Pourquoi c'est utile`
du rapport d'Arthur : ce sont ses ajouts, pas des décisions de Thibault. Chaque ligne est
contestable ; une ligne qu'il ne comprend pas s'explique avant qu'il édite.

**Cockpit d'abord.** `pipeline.sh say <nom> "Écris tes contrats : <n> fichiers, <n> DÉCISION"`, puis
« Rafraîchir » (`~/.claude/pipeline/feature/cockpit.md`) et donne-lui le lien : il y lit chaque fichier
en diff (brouillon d'Arthur → état actuel), avec les `DÉCISION` surlignées, et peut éditer et
enregistrer là, depuis son téléphone aussi. L'IDE reste ouvert pour les éditions lourdes : il choisit.

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
- **« J'ai fini »** → d'abord « Rapatrier » (`cockpit.md`) : ses éditions du cockpit sont écrites dans
  les fichiers ; un conflit (fichier modifié dans l'IDE entre-temps) se montre avec les deux versions
  et il choisit. Puis `grep -rn "DÉCISION (Thibault)" <package>/lib`. Il en reste : liste-les et pose
  une question par commentaire (« garder la proposition d'Arthur (Recommandé) » / « l'alternative » /
  « je l'édite »), par paquets de 4. Les « garder » / « alternative » et le mécanique demandé sont
  appliqués par Arthur en **mode application** (« applique ces choix, efface ces commentaires,
  réaligne impls stubbées, imports et README ; aucun scaffold, aucune autre signature ») ; à son
  retour, `pipeline.sh after-architect <nom>` comme en 0c. Puis `gauntlet.sh contracts <nom>`. Rouge → montre
  les erreurs (`fichier:ligne`) et propose « je corrige » / « Arthur corrige le mécanique ».
  « Appelants cassés » dans le rapport d'Arthur (tests ou fichiers hors package qui appellent une
  signature changée) → Théo les réaligne tout de suite, en background, sans attendre le rouge
  d'`analyze` : « ces appels ne compilent plus après le changement de signature ; adapte-les, ne
  change aucune assertion ».
- Verdicts `architect` de Denis : déclaration remplacée par l'existant → `"accepted": true, "reason":
  "remplacé par Thibault"` sur l'entrée ; gardée → Thibault donne sa raison, `accepted` avec elle.
  Puis `gauntlet.sh dedup_verdict <nom>` vert.
- **Gabarit** : plus de 2 `DÉCISION` dans le brouillon en S → question de reclassement en M ; plus
  de 5 en M → question « découper (L) / continuer en M » (voir « Gabarits »). Dans le premier
  `AskUserQuestion` de cet arrêt, avant qu'il édite.

Vert → `pipeline.sh commit-contracts <nom> thibault` : commit `feat(<nom>): contracts (by Thibault)`
des seuls fichiers du package, du pubspec et de `writes.extra` modifiés depuis `draft_sha`, avec
`--allow-empty` (Thibault peut garder le brouillon tel quel : c'est un choix, et le commit le date),
puis `contracts.sha`, `contracts.files` recalculé (un fichier de contrat ajouté par Thibault en fait
partie) et `human_gates.contracts`. Les fichiers de
`contracts.files` sont désormais la référence : aucun agent ne change une de leurs signatures sans
lui (Arthur, Théo, Ivan et Nina rapportent un contrat qui ne tient pas, ils ne le contournent pas).

**Réédition plus tard** (contrat à revoir au point d'étape « spec », décision demandée par Ivan…) :
Thibault édite, puis tu joues `gauntlet.sh contracts <nom>` (avant l'étape 2) ou `gauntlet.sh green
<nom>` (après : il y a du code autour) ; rouge → montre-le-lui avant tout commit. Vert →
`pipeline.sh commit-contracts <nom> reedit "<quoi>" <fichiers qu'il a édités>` : commit
`feat(<nom>): contracts (by Thibault) — <quoi>` des **seuls fichiers qu'il a édités** (jamais `-A` :
le travail en cours d'un agent ne doit pas y entrer), `contracts.sha` et `contracts.files` mis à jour.
Édités dans le cockpit : `cockpit.md`, « Rapatrier », avant le gauntlet. Si un test gelé dépend du contrat changé :
re-gel, cause `contrat`.

**Gabarit S :** identique — c'est le moment où la feature devient la sienne. **En L :** n'a pas lieu.
**Découpage décidé ici (M → L)** : le brouillon et les contrats déjà commités restent sur
`feature/<nom>`. Le découpage se valide comme en 0b (5) ; la première sous-feature part de cette
branche (`base: feature/<nom>` dans son `pipeline.json`), et son 0c part des fichiers existants au
lieu de repartir de zéro ; les suivantes suivent l'ordre de dépendance.

