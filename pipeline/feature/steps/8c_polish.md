### 8c. Polish visuel — sur demande de Thibault, puis Pauline (`feature-polisher`)

Après la visite validée, avant l'evidence. **Pauline ne se lance jamais d'office** : c'est Thibault
qui décide, à chaque feature.

**La question.** Si la feature n'a aucune page (`lib/src/presentation/` sans vue touchée depuis la
merge-base) : `pipeline.sh gate <nom> polish decision=no_screen`, rien d'autre. Sinon un seul
`AskUserQuestion` (mécanique du cockpit, `--ask`), précédé des « Défauts visuels » de `qa.md` et
d'une capture par écran (`SendUserFile`) : « On fait un polish visuel des écrans ? » — « Oui, audit
d'abord » / « Non, on livre » / « Discuter ».
- **Non** → `pipeline.sh gate <nom> polish decision=skipped`, passe à 9.

**Audit.** Pauline, prompt : `mode: audit`, nom, package, `spec.md`, `create_screen_rules.md`
(entrée de `pipeline.sh next` ; absent → le template, et dis-le à Thibault), `qa.md`, dossier des
captures, `feature_pipeline.md`. Au retour : `polish.md`, les captures `polish/avant/`
(`SendUserFile`), puis un `AskUserQuestion` multiSelect, un choix par écart (`P<n> — <écran> :
<point>`, effort en description), plus « Tout », « Rien finalement », et une ligne par composant DS
manquant. Ses réponses vont dans `pipeline.json → polish` (`pipeline.sh set <nom> polish
'{"retained": ["P1", …], "notes": "…"}'`). « Rien » → `gate polish decision=skipped`, passe à 9.
Les « Hors polish » de son rapport ne sont pas proposés ici : ils vont en `debt` s'ils portent sur du
code préexistant, sinon en point imprévu (c'est un changement de comportement ou de contrat).

**Application.** `pipeline.sh loop <nom> polish` (code 3 : point imprévu). Pauline, prompt :
`mode: application`, le même contexte, `polish.md`, les IDs retenus et les notes de Thibault. Au
retour, `stages.polish` doit être `PASSED` (le hook a joué `gauntlet.sh polish`). `FAILED` → point
imprévu, comme en 4. Puis **Quentin** (8) sur l'état poli : les flows doivent rester verts. Pas de
Romain ni de Hugo si `lib/` n'a changé que dans `presentation/` ; sinon rejoue 6 → 7 (comme un
renvoi de 8b).

**Validation.** `SendUserFile` des captures avant / après côte à côte (un appel par plateforme), le
tableau de `polish.md` avec la colonne `Fait`, puis `AskUserQuestion` : « Valider le polish » /
« Je renvoie : <IDs + retour> » / « Annuler le polish » / « Discuter ».
- **Renvoi** → application à nouveau avec le retour (boucle `polish`).
- **Annuler** → `git restore --source=<sha d'avant l'application> -- <package>/lib <zones du DS>`,
  sur instruction explicite de Thibault seulement, puis `gate polish decision=reverted`.
- **Valider** → commit `style(<nom>): polish visuel (<IDs>)`, puis
  `pipeline.sh gate <nom> polish decision=applied 'returned=[<IDs renvoyés>]'`.

**Gabarit S :** identique, la question est posée aussi. **En L :** n'a pas lieu.
