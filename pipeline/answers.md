# Règles tirées des réponses de Thibault

Chaque règle ici remplace une question que `/feature` ou `/fix` lui a déjà posée. Elle vaut pour
**tous ses projets**. Les règles propres à un projet vivent dans son `.claude/rules/pipeline_answers.md`,
au même format ; en cas de conflit, la règle du projet gagne.

Lu par les orchestrateurs avant toute question (étape 1 du filtre), et transmis aux agents qui
proposent des choix (Sophie, Camille, Arthur, Romain, Victor, Bastien). Une règle s'applique sans
redemander ; l'orchestrateur dit laquelle il a appliquée, citée, et ce qu'elle change ici (bloc
« ce que tu tranches sans lui » de `feature.md` et `fix.md`). Elle prime sur une question
que `feature.md` ou `fix.md` prévoirait au même endroit.

Format : une ligne par règle, à l'impératif, puis entre parenthèses la date et la question d'origine.
Ajout uniquement sur accord explicite de Thibault (voir « Chaque réponse peut devenir une règle »
dans `feature.md` et `fix.md`). Une règle qu'il contredit plus tard est corrigée, pas doublée.

## Pipeline et livraison
- Les contrats que Thibault écrit sont seulement les interfaces (repository, data source, use case, state) ; clés de test, DI et l10n sont de l'implémentation, posée par Arthur sans lui demander (2026-11-06, Règle)

- Crée les commits du plan sans demander de validation : ils sont locaux et réversibles, le plan va dans l'evidence. Le push et la MR restent soumis à sa validation. (2026-10-17, « Commits », 11 réponses « Go » sur 11)
- Applique le gabarit S ou M qui sort des critères sans le demander, annoncé avec ses mesures et ce qu'il change pour la suite ; ne pose que la question du découpage quand le gabarit est L. (2026-10-17, « Gabarit », 8 sur 8)
- Une feature qui ne touche les autres packages que par des ajouts mécaniques (param optionnel, une ligne) reste en M au lieu de passer en L. (2026-10-19, « Gabarit »)
- Sans référence d'issue dans la description, passe l'issue en `to_create` sans demander s'il en existe une ; le contenu de l'issue reste validé avant sa création. (2026-10-17, « Issue », 7 sur 7)
- Ouvre pour la feature (`pipeline.sh extra <nom> <glob>`, jamais la config `writes.extra` du projet) les chemins que la spec et les contrats validés touchent (leurs `test/` compris) sans demander, et dis lesquels et pourquoi. Un hook global qui contredit son propre commentaire est une question : montre le diff proposé, et la correction passe par `claude_change.sh` (ADR 0007), jamais en cours de feature sans son accord. (2026-10-17, « writes.extra » et « Hook », 11 sur 11 ; amendée le 2026-11-10 : un hook de garde ne s'assouplit pas en silence)

## Gates et seuils

- Couverture sous le seuil avant l'étape de mutation : Hugo couvre, sans question. (2026-10-17, « Couverture », 4 sur 4)
- Faux positif du gauntlet : corrige le gauntlet ou le script global (avec le diff montré), pas une acceptation du rouge feature par feature. Les seules exceptions sont les règles marquées « trou du gauntlet » ci-dessous : chacune nomme un cas exact que le script ne sait pas encore reconnaître, s'applique citée dans l'evidence, et disparaît quand un check le reconnaît (ADR 0003). (2026-10-17, « Gauntlet », 5 sur 5 ; amendée le 2026-11-10)
- `metrics` : rien à accepter. Le check compare lui-même à la merge-base ; une fonction déjà hors seuil qui n'a pas empiré sort en dette, une qui a grossi bloque. Ne mets pas une fonction qui a empiré dans `metrics_accepted` : c'est une question. (2026-11-10, revue des règles ; remplace la partie « Métriques » de la règle du 2026-10-17)
- Trou du gauntlet — lignes non couvertes qui ne sont que du code existant déplacé, reformaté, ou de la DI ; `stub_check` rouge sur du code inchangé et déjà validé : accepte, note-le en dette, ne demande pas. Reste une question : une ligne de code neuf non couverte après le passage de Hugo. (2026-10-17, « Couverture », « stub_check », 12 cas)
- Trou du gauntlet — en extend, quand les contrats n'ajoutent que des champs ou paramètres (aucune méthode), accepte `stub_check` sans demander ; l'acceptation reste tracée dans l'evidence. (2026-10-19, « stub_check »)
- Trou du gauntlet — accepte `red_check` sur les tests d'un code déjà réaligné par le commit de contrats, sans demander ; l'acceptation reste tracée dans l'evidence. Seulement les fichiers de test dont le code testé est dans ce commit ; un autre fichier tout vert reste une question. (2026-10-19, « red_check » ; restreinte le 2026-11-10)
- Ne demande pas de valider les mutants quand tous les survivants sont expliqués dans `mutants.md` : ils sont présentés dans la visite guidée. (2026-10-17, « Mutants », 6 sur 6)

## Tests

- Un test faux pour une raison technique (step, fixture, mock, constructeur à adapter à une signature) se corrige et se regèle sans demander, re-gel de cause `technique`. Une assertion qui change de valeur attendue n'est jamais technique : c'est une question, même si elle paraît mécanique. (2026-10-17, « Test faux », 10 sur 10 ; amendée le 2026-11-10 : « assertion de record » retirée, elle change ce que le test prouve)
- Une dev_dependency de test déjà résolue en transitif, à la même version, est acceptée sans question. (2026-10-21, fake_async)

## Périmètre et dette

## Revue et suggestions

- Une `DÉCISION` ou un choix par défaut que Thibault n'a pas modifié est gardé tel quel : ne redemande pas « tu gardes bien ces propositions ? ». (2026-10-17, « Décisions », 6 sur 6)
- Une clé de test manquante dans le fichier de clés (ou son identifiant d'accessibilité à poser) : Arthur l'ajoute aux contrats, sans question. (2026-10-17, « Clés », 3 sur 3 ; confirmée le 2026-10-30 sur error_redirect)

## QA

- Chaque worktree crée son propre simulateur (clone du simulateur modèle, supprimé avec le worktree) ; ne lance jamais une étape device sur le simulateur partagé. (2026-11-03, « c'est pas "faisable". C'est la règle », fix photo_delete_without_confirm)

## Code et conventions

- Avant de proposer un mécanisme (stockage, détection, navigation, analytics…), cherche comment c'est déjà fait ailleurs dans le code et réutilise-le ; ne propose du neuf qu'en disant pourquoi l'existant ne convient pas. (2026-10-17, « On n'a pas un système cool pour ça déjà ? »)
- Le cadrage, les comportements et les textes d'interface s'écrivent du point de vue de l'utilisateur, sans technique. (2026-10-17, « le user s'en carre de la technique »)
- Une écriture locale qui peut échouer (base locale, stockage, préférences, plugin) rend le type résultat (erreur typée ou rien) depuis la data source, comme toute I/O ; pas de fonction sans résultat qui lève. (2026-10-17, « Either », tranché après 3 Either et 2 Future<void>)
- Couches strictes : state holder → use case → repository → data sources. Le repository combine les data sources ; pas de parsing JSON ni de persistance dans un use case ; ne supprime jamais un use case appelé par un state holder. (2026-10-17, « respecte mon archi », 5 réponses)
- Jamais `.first` ni `take(1)` sur un Stream de watch : ajoute une méthode `Future` au repository ou à la data source. (2026-10-17, 2 réponses)
- Ce que `core` enveloppe (type résultat, erreurs, logger, analytics, helpers maison) s'utilise via `core`, jamais en recodant. Une lib tierce que le package importe directement se déclare dans son propre manifeste, à la version que le workspace résout déjà ; `core` ne sert pas de ré-export de libs tierces. (2026-10-17, « Core est là pour ça » ; amendée le 2026-11-10 : un ré-export cache les vraies dépendances et lie tous les packages aux versions de `core`)
- Une nouvelle I/O transverse (détection ou ouverture d'app, plugin natif…) vit dans son propre package. (2026-10-17, « Dans sa propre feature ça », 4 réponses)
- Une transaction de base locale vit dans la couche data, jamais dans un use case : une méthode métier de la data source locale (ou du repository, s'il combine plusieurs data sources) ouvre la transaction avec l'outil transactionnel de `core` (règle de langage) et rend le type résultat. Le use case appelle cette méthode sans savoir qu'une base ou une transaction existe. Pas de repository ou de data source neufs juste pour la porter : la méthode va dans ceux qui existent. (2026-10-30, « DÉCISION 1 » ; corrigée le 2026-11-10 : la version d'origine mettait la transaction dans le use case, contre « Couches strictes »)
- Nomme chaque entité de domaine avec le suffixe `Entity` (classe `XxxEntity`, fichier nommé d'après elle selon la convention du langage). (2026-10-29, « Contrats »)
