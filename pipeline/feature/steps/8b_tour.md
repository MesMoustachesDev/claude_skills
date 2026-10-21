### 8b. Point d'étape « visite guidée » du code

L'evidence dit que la feature est prouvée ; la visite fait que Thibault sait **comment** elle marche.
Elle remplace les anciens arrêts mutants et captures : tout ce qu'il devait valider séparément est
rattaché à l'endroit du code qu'il concerne.

`gauntlet.sh report <nom> tour`, `SendUserFile` du `report.html` (`display: render`), puis
`SendUserFile` des captures (`.claude/features/<nom>/qa/**/*.png`, un appel par plateforme). La section
« Visite guidée » montre les étapes de `review.json → tour` (écrites par Romain), dans l'ordre du flux
de données (vue → BLoC → use case → repository → data source) : chacune avec `fichier:ligne`
(recalculé depuis le symbole si le code a bougé depuis la revue), un extrait, ce que fait le code, le
C<n> ou la décision qu'elle implémente, et rattachés : les mutants de ce fichier (`mutants.md`), ses
suggestions de Romain avec leur décision, les captures de ses scénarios, les tests suspects. En tête,
les ✗ de Quentin ; en fin, ce qui n'a pu être rattaché à aucune étape.

Dans ton message : une ligne par étape, `[fichier:ligne](chemin:ligne)` cliquable, puis ce qu'elle
fait en une phrase et ses rattachements en compte (« 1 mutant équivalent, 2 captures »). Ouvre le
fichier de la première étape avec `open_in_editor` si l'outil est disponible. Puis `AskUserQuestion` :
« Valider la visite » / « J'ai une question » / « Je renvoie une étape : … » (texte libre).
**Pas de « Valider » tant qu'il reste** un ✗ dans `qa.md`, `stages.harden` ou `stages.qa` à
`FAILED` (ou `qa` rouge), ou un mutant survivant sans explication dans `mutants.md` : dis lequel en
tête, et les seules options sont « Je renvoie une étape : … » et « Accepter : <raison> » (`accept`,
qui apparaît dans l'evidence).
- **Question** → réponds avec l'extrait de code et ce qu'il fait, puis repose la même question. Tant
  qu'il pose des questions, la visite n'est pas validée.
- **Renvoi** — selon ce qui est en cause à cette étape : le code (défaut, comportement, capture ✗) →
  Ivan avec l'étape, le `fichier:ligne` et le retour, puis **toujours** `gauntlet.sh clean <nom>`
  (design system, l10n, métriques ne sont vérifiés que là) : rouge → Nina. Si `lib/` n'a changé que
  dans `presentation/**/view/**`, Romain et Hugo sont sautés ; sinon rejoue 6→7. Puis Quentin, puis
  8b. Une explication de mutant → Hugo avec le retour, puis 8b. `pipeline.sh loop <nom> tour` avant chaque renvoi ; code 3 (au-delà de 2) : point
  imprévu.
Validation → `pipeline.sh gate <nom> tour 'returned=[<étapes renvoyées>]'`.

**Gabarit S :** identique — 5 à 8 étapes, moins quand la feature a moins de couches (2 minimum,
comme le vérifie le gate `review`). **En L :** n'a pas lieu.

