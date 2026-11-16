### 1c. Brouillon de contrats tiré des scénarios — Arthur (`feature-architect`, mode brouillon)

**Les contrats sortent des scénarios validés (ADR 0015).** Chaque When de §4 devient un appel (use case,
méthode du state holder ou event), chaque Then un état, un retour ou une valeur observable, chaque Given
une donnée que le repository ou une entité doit porter, chaque erreur de §7 une valeur d'erreur (state ou
failure), chaque clé citée par §4 une entrée du fichier de clés. Un contrat qui ne sert aucun scénario
n'est pas posé.

L'architecture appartient à Thibault, et il la possède mieux en l'écrivant qu'en cochant des
propositions : Arthur ne fait que lui éviter la page blanche. Prompt : « mode brouillon », nom,
**mode**, `cadrage.md` validé, `spec.md` (scénarios validés : §4, §6, §7) et `archi.json`,
`create_feature_rules.md`, package, valeur de `brick`, la feature de
référence (« Notes pour les agents » de la config), et le chemin du graphe (`graph=` de l'étape 0)
si `prepare` a dit `ok`. En `extend` : « pas de scaffold ; ajoute dans l'existant ; ne renomme rien ».

Arthur scaffolde (en `create`) et pose **dans les vrais fichiers du package**, en stubs, le court
brouillon de ce que Thibault doit posséder : entités, interfaces de repository et de data sources,
signatures des use cases, events/states sealed, le fichier de clés. Chaque choix qu'un dev senior pourrait
faire autrement (Stream ou Future, un state holder ou deux, où vit une logique, remote/local) porte au-dessus
de la ligne un commentaire `// DÉCISION (Thibault) : <question> — proposé : <X>, alternative : <Y>`.
**Les choix structurants viennent du cadrage** (« Décisions techniques », tranchées avec Thibault dans
la discussion de départ) : Arthur les applique, sans `DÉCISION` à ces endroits. Son rapport signale une
« Décision manquante au cadrage » → point imprévu : rouvre la discussion avec Thibault sur ce point
(texte, du tac au tac, comme en 0b), note la décision dans `discussion.md` et le cadrage, puis relance
Arthur.
**Scénario sans contrat possible** : un scénario validé que le brouillon ne sait pas porter sans
changer le scénario (une donnée que rien ne fournit, deux Then incompatibles) → son rapport le liste sous
« Scénarios à revoir » ; point imprévu : montre-le à Thibault avec le scénario, il tranche (le scénario
change : relance Sophie en mode correction, puis Camille en mode ciblé ; ou il dit comment le porter :
relance Arthur).
**Ajouts proposés** : son rapport liste, sous ce titre, tout ce qu'il a posé et que le cadrage ne
nomme pas (une classe, une interface, une data source, un découpage, une dépendance) : une ligne
chacun, `Détail | Proposition | Pourquoi c'est utile`.
Rien d'autre à la main : pas de DI, de route, de modèle de données ni de mapper à ce stade (2).

**Le hook d'Arthur écrit `stages.contracts`, qui appartient à l'étape 2.** Après **chaque** retour
d'Arthur avant l'étape 2 (brouillon, mode application en 1e) : `pipeline.sh after-architect <nom>`
(il déplace `stages.contracts` vers `stages.contracts_draft` et remet `attempts.contracts` à 0). Il nomme
aussi les **tests à réaligner** : un fake ou un appel de test qui ne compile plus contre le brouillon ne
retient pas Arthur (le gate `contracts` le liste dans `.gauntlet/tests_to_realign.txt`, ADR 0015 amendée) ;
lance Théo (`feature-test-writer`) en background, « adapte ces fakes et appels au contrat, ne change aucune
assertion ». Son hook joue `analyze` et n'écrit aucun stage. Brouillon `FAILED` →
**point imprévu** : le rapport d'Arthur et les 40 dernières lignes de `last_contracts.log`,
« relancer Arthur avec une consigne » / « je pars de ce qu'il y a et je corrige moi-même en 1e ».

`pipeline.sh commit-contracts <nom> draft` : commit `chore(<nom>): contracts draft (Arthur)` sur les
seuls fichiers du package, du manifeste racine et de `writes.extra` touchés, puis `contracts.draft_sha`
et `contracts.files`, la liste des fichiers de contrats (diff depuis la merge-base sous
le code du package, filtré sur les `contract_globs` du langage : `stack.sh get contract_globs <package>`). **`contracts.files` est la
définition des contrats de Thibault** pour tous les agents : un fichier qu'il n'a pas modifié est
aussi le sien.

**Gabarit S :** identique. **En L :** n'a pas lieu.

