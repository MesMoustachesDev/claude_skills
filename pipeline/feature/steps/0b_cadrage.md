### 0b. Cadrage fonctionnel — Sophie en mode cadrage, puis toi avec le dev (interactif)

Le dev doit savoir **ce qui va être fait** avant qu'une ligne de spec soit écrite. Un périmètre qui bouge
pendant les boucles de spec coûte une boucle Sophie + Camille par changement, et un changement qui
arrive après les contrats coûte la chaîne entière. Le cadrage fige le *quoi* ; les contrats de Thibault, puis la spec, écrivent le *comment*.

1. **Sophie, mode cadrage** (`feature-specifier`, prompt : « mode cadrage », nom, description brute,
   issue s'il y en a une, racine, sortie `.claude/features/<nom>/cadrage.md`, le chemin du graphe
   (`graph=` de l'étape 0) si `prepare` a dit `ok`). Elle explore et n'écrit
   pas de spec. `cadrage.md` contient, court :
   - **Ce qui existe déjà** : le code actuel qui fait tout ou partie du besoin, dans ce repo **et
     ailleurs** (autre plateforme, web, backend, autre feature), avec les valeurs en dur relevées
     (seuils, formats, limites) et les écarts entre eux. C'est souvent là que se cache la bonne réponse.
     **Le projet a un graphe graphify** (le `graph=` de l'étape 0, copié dans le
     worktree) → Sophie part de la carte, pas d'une exploration à l'aveugle (`~/.claude/pipeline/graphify.md`,
     section Explorer) et cite les nœuds avec leur `fichier:ligne`. Le cadrage en tire une **carte** :
     un `flowchart` Mermaid de ce qui existe autour du besoin (packages, classes, flux), avec ce que la
     feature touchera.
   - **Ce que je comprends du besoin** en 3 à 5 phrases, dans les mots du dev.
   - **Périmètre** : inclus / exclu, chaque ligne avec un exemple concret.
   - **Comportements visibles = scénarios d'acceptation** : 5 à 10, chacun sous un titre `### C<n> —
     <phrase>` (« quand … alors … » en français, sur un cas réel : « une photo portrait 4032×3024
     prise à la caméra → stockée en 1920×2560 JPEG q85 »), suivi de son **diagramme de séquence**
     Mermaid (`sequenceDiagram`) en termes de comportement : `U` Utilisateur ↔ `E` Écran ↔ `A` App ↔
     serveur, stockage ou plateforme (tout autre id). Pas de classe, pas de BLoC : ce que fait
     l'utilisateur, ce que l'écran montre, ce que l'app demande et ce qu'on lui répond, erreurs
     comprises. Ces séquences seront comparées aux tests d'acceptation réels au point d'étape « tests ».
   - **Package et dépendances** : le package proposé (nouveau ou extension de `features/x`) et toute
     dépendance pub.dev ou inter-feature à ajouter, chacun avec l'alternative et ce qu'elle change.
     C'est la seule décision structurante qui se prend avant le code : le reste, Thibault l'écrit
     dans ses contrats.
   - **Questions ouvertes** : chacune commence par **ce qui existe aujourd'hui** — l'extrait de code
     ou de cadrage concerné (`fichier:ligne`, 3 à 8 lignes) et ce qu'il fait — puis 2 à 3 options
     concrètes, une recommandée et pourquoi, et ce que chaque option change pour l'utilisateur.
   - **Règles non négociables** qui s'appliquent (`create_feature_rules.md`, gestion d'erreur…) :
     rappelées, jamais posées comme question.
   - **Gabarit proposé** (S / M / L) avec les mesures qui le fondent : scénarios estimés, packages
     touchés, package ou dépendance ajoutés, décisions majeures estimées (chacune en une ligne). En L,
     un **découpage proposé** : les sous-features (nom, package, périmètre, gabarit estimé, ordre et
     dépendances entre elles), chacune livrable et testable seule.
2. **Toi, avec le dev.** `gauntlet.sh report <nom> cadrage` puis `SendUserFile` du `report.html`
   (`display: render`) : le cadrage rendu, une séquence par scénario. Résume en 5 lignes ce qui
   existe et le périmètre proposé, puis pose les questions ouvertes par `AskUserQuestion` (4 max par
   appel, options concrètes, recommandée en premier), **chacune précédée dans ton message de son
   extrait** (« Questions avec leur contexte », Règles de conduite). Le dev peut corriger le périmètre,
   un exemple ou une séquence en texte libre : relance Sophie en mode cadrage avec ses réponses
   (« intègre, ne réécris pas le reste »), renvoie le rapport, et recommence tant qu'il reste une
   question ou qu'une séquence le surprend.
3. **Gabarit.** Vérifie la proposition de Sophie contre les critères de « Gabarits » (c'est la
   règle qui tranche, pas l'estimation de l'agent : 3 décisions majeures, c'est M même si elle
   propose S).
4. **Fin du cadrage** : un seul `AskUserQuestion` avec une à trois questions — « C'est bien ça
   qu'on fait, séquences comprises ? » (Oui / Non, je précise), **seulement si le gabarit retenu est
   L** « Découper ? » (le découpage proposé / continuer en M) — un S ou un M s'applique sans question,
   annoncé en une ligne avec ses mesures (règle du dev) — et, seulement si le cadrage propose une vraie alternative, « Package » (la proposition, puis
   l'alternative, chacune avec ce qu'elle change). Oui → `size`, `size_reason` (les mesures, une
   ligne), `package` et `mode` si le package a changé : `pipeline.sh size <nom> <S|M|L> "<mesures>"`,
   `pipeline.sh gate <nom> cadrage size=<S|M|L> package=<chemin>`, `pipeline.sh pass <nom> cadrage`. Le package et les dépendances validés iront en §9 au statut
   `validée` : ils ne se reposent plus.
5. **En L : découpage, puis arrêt.** Le découpage proposé se valide comme le reste du cadrage
   (texte libre pour le corriger, relance de Sophie). Validé → `pipeline.json → split` (`[{name,
   package, size, depends_on}]`) ; Sophie écrit pour chacune `.claude/features/<nom>/split/<sous>.md`
   (l'extrait du cadrage qui la concerne). Puis tu t'arrêtes : pas de spec, pas d'issue, pas de
   worktree de plus. Donne au dev la commande de chaque sous-feature, dans l'ordre de dépendance
   (`/feature <sous> --parent <nom> [--in <package>] "<description>"`) ; au cadrage d'une sous-feature,
   Sophie reçoit en entrée le chemin absolu de son extrait (que `pipeline.sh init … --parent` imprime) et
   ne repart pas de zéro. Le cockpit range chaque sous-feature sous sa parente (« 2/3 ») et montre, sur
   la parente, l'avancement de toutes. Une sous-feature qui dépend
   d'une autre attend son merge, ou part de sa branche (`base` dans son `pipeline.json`). Sors avec
   `ExitWorktree` `action: "keep"` : le dossier de la feature parente garde le découpage.

**Le cadrage validé est l'entrée verrouillée des contrats et de la spec.** Arthur en tire son
brouillon, Sophie le reprend en §1-§2 tel quel ; ni un contrat ni §9 ne le contredisent. Un changement
de périmètre demandé plus tard repasse par 0b (cadrage mis à jour et revalidé) avant toute relance.

