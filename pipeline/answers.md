# Règles tirées des réponses de Thibault

Chaque règle ici remplace une question que `/feature` ou `/fix` lui a déjà posée. Elle vaut pour
**tous ses projets**. Les règles propres à un projet vivent dans son `.claude/rules/pipeline_answers.md`,
au même format ; en cas de conflit, la règle du projet gagne.

Lu par les orchestrateurs avant toute question (étape 1 du filtre), et transmis aux agents qui
proposent des choix (Sophie, Camille, Arthur, Romain, Victor, Bastien). Une règle s'applique sans
redemander ; l'orchestrateur dit en une ligne laquelle il a appliquée. Elle prime sur une question
que `feature.md` ou `fix.md` prévoirait au même endroit.

Format : une ligne par règle, à l'impératif, puis entre parenthèses la date et la question d'origine.
Ajout uniquement sur accord explicite de Thibault (voir « Chaque réponse peut devenir une règle »
dans `feature.md` et `fix.md`). Une règle qu'il contredit plus tard est corrigée, pas doublée.

## Pipeline et livraison

- Crée les commits du plan sans demander de validation : ils sont locaux et réversibles, le plan va dans l'evidence. Le push et la MR restent soumis à sa validation. (2026-10-17, « Commits », 11 réponses « Go » sur 11)
- Applique le gabarit S ou M qui sort des critères sans le demander, annoncé en une ligne avec ses mesures ; ne pose que la question du découpage quand le gabarit est L. (2026-10-17, « Gabarit », 8 sur 8)
- Une feature qui ne touche les autres packages que par des ajouts mécaniques (param optionnel, une ligne) reste en M au lieu de passer en L. (2026-10-19, « Gabarit »)
- Sans référence d'issue dans la description, passe l'issue en `to_create` sans demander s'il en existe une ; le contenu de l'issue reste validé avant sa création. (2026-10-17, « Issue », 7 sur 7)
- Ouvre pour la feature (`pipeline.sh extra <nom> <glob>`, jamais la config `writes.extra` du projet) les chemins que la spec et les contrats validés touchent (leurs `test/` compris) sans demander, et dis-le en une ligne ; corrige le hook global quand il contredit son propre commentaire. (2026-10-17, « writes.extra » et « Hook », 11 sur 11)

## Gates et seuils

- Couverture sous le seuil avant l'étape de mutation : Hugo couvre, sans question. (2026-10-17, « Couverture », 4 sur 4)
- Lignes non couvertes qui ne sont que du code existant déplacé, reformaté, ou de la DI ; `metrics` au-dessus du seuil sur une signature qui existait avant la feature ; `stub_check` rouge sur du code inchangé et déjà validé : accepte, note-le en dette, ne demande pas. Reste une question : une ligne de code neuf non couverte après le passage de Hugo. (2026-10-17, « Couverture », « Métriques », « stub_check », 12 cas)
- Faux positif du gauntlet : corrige le gauntlet ou le script global (avec le diff montré), jamais une acceptation du rouge feature par feature. (2026-10-17, « Gauntlet », 5 sur 5) Exception : la règle `stub_check` à périmètre vide ci-dessous.
- En extend, quand les contrats n'ajoutent que des champs ou paramètres (aucune méthode), accepte `stub_check` sans demander ; l'acceptation reste tracée dans l'evidence. (2026-10-19, « stub_check »)
- Accepte `red_check` sur les tests d'un code déjà réaligné par le commit de contrats, sans demander ; l'acceptation reste tracée dans l'evidence. (2026-10-19, « red_check »)
- Ne demande pas de valider les mutants quand tous les survivants sont expliqués dans `mutants.md` : ils sont présentés dans la visite guidée. (2026-10-17, « Mutants », 6 sur 6)

## Tests

- Un test faux pour une raison technique (assertion de record, step, fixture, constructeur à adapter à une signature) se corrige et se regèle sans demander, re-gel de cause `technique`. Demande seulement si la correction change le comportement attendu. (2026-10-17, « Test faux », 10 sur 10)
- Une dev_dependency de test déjà résolue en transitif, à la même version, est acceptée sans question. (2026-10-21, fake_async)

## Périmètre et dette

## Revue et suggestions

- Une `DÉCISION` ou un choix par défaut que Thibault n'a pas modifié est gardé tel quel : ne redemande pas « tu gardes bien ces propositions ? ». (2026-10-17, « Décisions », 6 sur 6)
- Une clé de test manquante dans `keys.dart` : Arthur l'ajoute, sans question. (2026-10-17, « Clés », 2 sur 2)

## QA

## Code et conventions

- Avant de proposer un mécanisme (stockage, détection, navigation, analytics…), cherche comment c'est déjà fait ailleurs dans le code et réutilise-le ; ne propose du neuf qu'en disant pourquoi l'existant ne convient pas. (2026-10-17, « On n'a pas un système cool pour ça déjà ? »)
- Le cadrage, les comportements et les textes d'interface s'écrivent du point de vue de l'utilisateur, sans technique. (2026-10-17, « le user s'en carre de la technique »)
- Une écriture locale qui peut échouer (Isar, stockage, préférences, plugin) rend `Either<ErrorEntity, void>` depuis la data source, comme toute I/O ; pas de `Future<void>` qui lève. (2026-10-17, « Either », tranché après 3 Either et 2 Future<void>)
- Couches strictes : BLoC → use case → repository → data sources. Le repository combine les data sources ; pas de parsing JSON ni de persistance dans un use case ; ne supprime jamais un use case appelé par un BLoC. (2026-10-17, « respecte mon archi », 5 réponses)
- Jamais `.first` ni `take(1)` sur un Stream de watch : ajoute une méthode `Future` au repository ou à la data source. (2026-10-17, 2 réponses)
- Un package tiers déjà exposé par `core` s'importe via `core`, pas en dépendance directe. (2026-10-17, « Core est là pour ça »)
- Une nouvelle I/O transverse (détection ou ouverture d'app, plugin natif…) vit dans son propre package. (2026-10-17, « Dans sa propre feature ça », 4 réponses)
