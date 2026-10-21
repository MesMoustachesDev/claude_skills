### 3. Tests — Théo (`feature-test-writer`)

Prompt : nom, `spec.md`, package, la liste des chemins autorisés en lecture (`lib/src/domain/**`,
`lib/src/presentation/keys.dart`, `**/*_event.dart`, `**/*_state.dart`, `lib/src/data/model/*.dart`),
`~/.claude/commands/create_test.md`, `cadrage.md` et `archi.json` (« chaque séquence C<n> est un
scénario d'acceptation, relié à son titre de §4 par `archi.json → sequences` : chaque action, réponse
du serveur et résultat visible qu'elle montre doit avoir son step »). Au retour, `stages.red` doit
être `PASSED`.

**Contrat manquant** (Théo ou Gaëlle signalent un type, une clé ou un state absent des contrats) :
ce n'est ni à Théo ni à Arthur de l'inventer. Tu le montres à Thibault avec l'extrait du fichier de
contrat et le scénario qui en a besoin ; il l'ajoute (« Réédition plus tard » de 0e, puis Arthur en
mode application si une impl stubbée doit suivre), puis Théo reprend là où il s'était arrêté.

**Gabarit S :** identique — les tests sont l'actif durable, ils ne s'allègent pas. **En L :** n'a pas lieu.

### 3b. Revue des tests — Gaëlle (`feature-test-reviewer`)

Lance Gaëlle (`feature-test-reviewer`, prompt : nom, `spec.md`, `cadrage.md`, `archi.json`, package, `tests.md`, `create_test.md`).
Puis `gauntlet.sh tests_review_verdict <nom>` : rouge → relance le **test-writer** avec
`tests_review.md` (il complète et corrige les tests cités, il ne réécrit pas les autres), puis
`gauntlet.sh red`, puis 3b ; `pipeline.sh loop <nom> tests` avant chaque relance ; code 3 (au-delà de 2) : point d'étape avec les bloquants restants.
Un bloquant qui est un contrat manquant suit « Contrat manquant » (3) avant la relance de Théo.
**Gabarit S :** identique, gel compris. **En L :** n'a pas lieu.

Vert → **Point d'étape « tests ».** `gauntlet.sh report <nom> tests`, `SendUserFile` du `report.html`
(`display: render`) : la section « Séquences » s'ouvre en premier. Pour chaque C<n>, côte à côte, la
séquence validée au cadrage et la même redessinée par le script **depuis le test d'acceptation réel**
(le `testWidgets` généré par `bdd_widget_test` et le corps de chaque step : pump, tap/saisie, réponse
du faux repository/serveur, assertion, chacun avec `fichier:ligne`), et les écarts signalés (étape du
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

