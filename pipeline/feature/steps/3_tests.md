### 3a. La liste des tests — Théo-liste (`feature-test-planner`), puis Gaëlle

Avant d'écrire un test, on décide **lesquels** : un test jamais écrit ne coûte rien, ni à écrire, ni à
relire, ni à faire tourner. Lance Théo-liste (`feature-test-planner`, prompt : nom, `spec.md`,
`cadrage.md`, `archi.json`, package). Il écrit `tests_plan.json` : chaque test avec son fichier, son nom,
son étage et les items de la spec qu'il prouve (`test_plan.py items` les numérote : scénarios, contrats,
données, erreurs). Son gate (`test_plan`) refuse une liste où un item n'est ni prouvé ni écarté avec sa
raison, un scénario sans test d'acceptation, un test qui ne prouve rien. C'est le filet du « assez ».

Puis Gaëlle (`feature-test-reviewer`, « mode liste », même prompt + `tests_plan.json`) relit la liste, qui
tient en une page : un test qui manque, une raison d'écart faible, un doublon (même comportement à deux
étages, variante qui passe par la même branche). Puis `gauntlet.sh tests_review_verdict <nom>` : rouge →
`pipeline.sh loop <nom> test_plan`, Théo-liste reprend avec `tests_review.md` (il corrige la liste, il ne
la refait pas), puis Gaëlle ; code 3 (au-delà de 2) : point d'étape avec les bloquants restants. Vert →
`pipeline.sh pass <nom> test_plan_review`.

**Gabarit S :** identique. **En L :** n'a pas lieu.

### 3. Tests — Théo en deux moitiés parallèles

Le premier passage s'écrit en **deux agents lancés dans le même message**, chacun sur sa couche, avec sa
zone d'écriture (hook) et son gate de couche :

| Moitié | `subagent_type` | Écrit | Gate (hook) |
|---|---|---|---|
| data/domain | `feature-test-writer-data` | `test/src/{data,domain,injection}/**` | `red_data` |
| présentation | `feature-test-writer-presentation` | le reste de `test/`, `.feature`, steps, pubspec | `red_presentation` |

Prompt commun (15 lignes max) : nom, `spec.md`, `tests_plan.json` (« tu écris les tests de la liste dont
le fichier est dans ta zone, ni plus ni moins »), package, `~/.claude/commands/create_test.md`, et « tu
écris en parallèle de l'autre moitié ; ton fichier d'agent dit ce que tu lis et où tu écris ». En plus,
pour la présentation : `cadrage.md` et `archi.json` (« chaque séquence C<n> est un scénario d'acceptation,
relié à son titre de §4 par `archi.json → sequences` : chaque action, réponse du use case mocké et
résultat visible qu'elle montre doit avoir son step »). Les deux reviennent quand leur gate de couche est
vert (`stages.red_data`, `stages.red_presentation`, écrits par leur hook).

Puis **`pipeline.sh join <nom> red`** : refuse tant qu'une moitié n'est pas verte, sinon joue le gate
complet (`red` : toute la suite, l'analyse du package entier, `tests.md`) et écrit `stages.red`.
- `join` vert → 3b.
- `join` rouge alors que les deux moitiés sont vertes : c'est la jonction (un import croisé, un fichier
  généré, une analyse hors couche). Relance **Théo complet** (`feature-test-writer`) avec
  `.gauntlet/last_red.log` : il corrige ce que le log cite, il ne réécrit rien d'autre. Puis `join` à
  nouveau.
- Une moitié `FAILED` (5 tentatives) : point imprévu comme ailleurs ; l'autre moitié, verte, ne se relance
  pas.
- **Reprise** : `pipeline.sh next` affiche l'état de chaque moitié ; ne relance que celle qui n'est pas
  `PASSED`.
- **Une seule couche touchée** (mode extend dont §8 ne touche, par exemple, que la présentation) : lance
  seulement cette moitié, et `pipeline.sh skip <nom> red_data "<raison, tirée de §8>"` pour l'autre ; `join`
  accepte une moitié `SKIPPED`.

Les **relances suivantes** — boucle de Gaëlle (3b), « Il manque des scénarios » de Thibault, Théo réaligné
en 0e — passent d'abord par la liste (Théo-liste la complète, `test_plan` vert), puis vont à **Théo complet**
(`feature-test-writer`) : un retour cite des fichiers des deux couches, et
la suite est déjà écrite. Après lui, `gauntlet.sh red <nom>` comme avant.

**Contrat manquant** (Théo ou Gaëlle signalent un type, une clé ou un state absent des contrats) :
ce n'est ni à Théo ni à Arthur de l'inventer. Tu le montres à Thibault avec l'extrait du fichier de
contrat et le scénario qui en a besoin ; il l'ajoute (« Réédition plus tard » de 0e, puis Arthur en
mode application si une impl stubbée doit suivre), puis Théo reprend là où il s'était arrêté.

**Gabarit S :** identique, deux moitiés comprises — les tests sont l'actif durable, ils ne s'allègent pas,
et le parallèle ne coûte pas de temps. **En L :** n'a pas lieu.

### 3b. Revue des tests — Gaëlle (`feature-test-reviewer`)

Lance Gaëlle (`feature-test-reviewer`, prompt : nom, `spec.md`, `cadrage.md`, `archi.json`, package, `tests.md`, `create_test.md`).
La liste a déjà tranché quels tests existent (3a) et le gate `red` a vérifié que la suite est la liste :
Gaëlle juge ici **comment** ils sont écrits (assertions, couplage, séquences). Un test qu'elle veut ajouter
passe d'abord par la liste : Théo-liste l'y ajoute, puis Théo l'écrit.
Gaëlle relit **les deux moitiés ensemble** (sa matrice de jonction §7 croise les deux rapports de Théo :
passe-lui la ligne « Jonction §7 » de chacun).
Puis `gauntlet.sh tests_review_verdict <nom>` : rouge → relance **Théo complet** (`feature-test-writer`) avec
`tests_review.md` (il complète et corrige les tests cités, il ne réécrit pas les autres), puis
`gauntlet.sh red`, puis 3b ; `pipeline.sh loop <nom> tests` avant chaque relance ; code 3 (au-delà de 2) : point d'étape avec les bloquants restants.
Un bloquant qui est un contrat manquant suit « Contrat manquant » (3) avant la relance de Théo.
**Gabarit S :** identique, gel compris. **En L :** n'a pas lieu.

Vert → **Point d'étape « tests ».** `gauntlet.sh report <nom> tests`, `SendUserFile` du `report.html`
(`display: render`) : la section « Séquences » s'ouvre en premier. Pour chaque C<n>, côte à côte, la
séquence validée au cadrage et la même redessinée par le script **depuis le test d'acceptation réel**
(le `testWidgets` généré par `bdd_widget_test` et le corps de chaque step : pump, tap/saisie, réponse
du use case mocké, assertion, chacun avec `fichier:ligne`), et les écarts signalés (étape du
cadrage absente du test, ou l'inverse). Puis les scénarios, la matrice §4 × `.feature`, l'inventaire.

En 10 lignes max : les écarts, un par ligne avec le C<n> et le `fichier:ligne` du step concerné (ce
sont des heuristiques : dis lesquels Gaëlle a déjà jugés justifiés), les scénarios absents des
`.feature`, les tests « passe déjà » avec la justification de Théo, les contrats manquants. Puis
renvoie à `tests.md` et à la table de couverture de `tests_review.md` dans le rapport plutôt que de
les recopier. `AskUserQuestion` : « Valider les tests » / « Il manque des scénarios ou des étapes »
(texte libre → relance Théo avec le retour et les écarts retenus, puis 3b ; ses fichiers existants
restent, il complète).

Validation → **gel** : `pipeline.sh freeze <nom>` (commit `test(<nom>): acceptance and unit tests
(frozen)` de `<package>/test` et du pubspec du package, puis `tests_freeze_sha`, `human_gates.tests`,
`stages.red = PASSED`).
À partir d'ici, `test/` ne change plus, sauf ajouts de Hugo.

**Re-gel** (test corrigé sur instruction du dev, à n'importe quelle étape) : avant le commit,
`gauntlet.sh format:test <nom>`, `no_secrets:test` et `test_hygiene` doivent être verts — une
correction qui casse le formatage ou un marqueur coûte sinon un re-gel de plus. Puis
`pipeline.sh refreeze <nom> <cause> <étape> "<quoi>"` (commit `test(<nom>): <quoi> (refrozen)`, nouveau
`tests_freeze_sha`, entrée dans `refreezes`), où `cause` est l'une de : `hygiene` (format, secrets, hygiène),
`technique` (test faux techniquement : pump, async, fixture), `contrat` (signature de §5 changée),
`spec` (amendement de spec, nouvelle décision §9), `interne` (test couplé à une classe interne que
l'implémentation a découpée autrement). C'est la mesure qui décidera d'un passage au double-loop.

