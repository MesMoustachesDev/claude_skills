### 0c. Brouillon de contrats — Arthur (`feature-architect`, mode brouillon)

L'architecture appartient à Thibault, et il la possède mieux en l'écrivant qu'en cochant des
propositions : Arthur ne fait que lui éviter la page blanche. Prompt : « mode brouillon », nom,
**mode**, `cadrage.md` validé, `create_feature_rules.md`, package, valeur de `brick`, la feature de
référence (« Notes pour les agents » de la config), et le chemin du graphe (`graph=` de l'étape 0)
si `prepare` a dit `ok`. En `extend` : « pas de scaffold ; ajoute dans l'existant ; ne renomme rien ».

Arthur scaffolde (en `create`) et pose **dans les vrais fichiers du package**, en stubs, le court
brouillon de ce que Thibault doit posséder : entités, interfaces de repository et de data sources,
signatures des use cases, events/states sealed, `keys.dart`. Chaque choix qu'un dev senior pourrait
faire autrement (Stream ou Future, un BLoC ou deux, où vit une logique, remote/local) porte au-dessus
de la ligne un commentaire `// DÉCISION (Thibault) : <question> — proposé : <X>, alternative : <Y>`.
**Sa démarche d'abord** : les 1 à 3 décisions qui structurent le plus la feature (nouvelle I/O,
découpage de l'état, frontière entre packages, ce qui a le plus de conséquences si on se trompe)
portent `// DÉCISION (Thibault, ta démarche) : <question>` **sans proposition** ; le stub reste
minimal à cet endroit. Arthur garde sa proposition pour lui, dans son rapport, à part (« proposition
retenue en réserve »), et ne la montre pas au dev.
**Ajouts proposés** : son rapport liste, sous ce titre, tout ce qu'il a posé et que le cadrage ne
nomme pas (une classe, une interface, une data source, un découpage, une dépendance) : une ligne
chacun, `Détail | Proposition | Pourquoi c'est utile`.
Rien d'autre à la main : pas de DI, de route, de modèle de données ni de mapper à ce stade (2).

**Le hook d'Arthur écrit `stages.contracts`, qui appartient à l'étape 2.** Après **chaque** retour
d'Arthur avant l'étape 2 (brouillon, mode application en 0e) : `pipeline.sh after-architect <nom>`
(il déplace `stages.contracts` vers `stages.contracts_draft` et remet `attempts.contracts` à 0). Brouillon `FAILED` →
**point imprévu** : le rapport d'Arthur et les 40 dernières lignes de `last_contracts.log`,
« relancer Arthur avec une consigne » / « je pars de ce qu'il y a et je corrige moi-même en 0e ».

`pipeline.sh commit-contracts <nom> draft` : commit `chore(<nom>): contracts draft (Arthur)` sur les
seuls fichiers du package, du pubspec racine et de `writes.extra` touchés, puis `contracts.draft_sha`
et `contracts.files`, la liste des fichiers de contrats (diff depuis la merge-base sous
`<package>/lib`, filtré sur `**/domain/**`, `**/keys.dart`, `**/*_event.dart`, `**/*_state.dart`). **`contracts.files` est la
définition des contrats de Thibault** pour tous les agents : un fichier qu'il n'a pas modifié est
aussi le sien.

**Gabarit S :** identique. **En L :** n'a pas lieu.

