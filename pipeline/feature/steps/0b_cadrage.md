### 0b. Cadrage — on en discute d'abord, du tac au tac

Thibault veut **discuter** avant que quoi que ce soit soit lancé : le besoin, le périmètre et la base
technique se décident dans une conversation vivante, pas dans un questionnaire ni dans un brouillon de
code qu'il découvre après coup. Aucun agent n'écrit de cadrage, de contrat ou de spec tant que cette
discussion n'est pas finie. Le cadrage fige le *quoi* **et** les choix techniques structurants ; les
contrats de Thibault, puis la spec, détaillent le *comment*.

1. **Sophie explore, en arrière-plan** (`feature-specifier`, `run_in_background: true`, prompt : « mode
   exploration », nom, description brute, issue s'il y en a une, racine, le chemin du graphe (`graph=`
   de l'étape 0) si `prepare` a dit `ok`, sortie `.claude/features/<nom>/exploration.md`). Elle relève
   des **faits**, sans rien proposer : le code qui fait déjà tout ou partie du besoin (ici et ailleurs :
   autre plateforme, web, backend, feature voisine), les valeurs en dur, la carte de ce qui entoure le
   besoin, les règles non négociables qui s'appliquent, et les **points techniques qui structureront la
   feature** (nouvelle I/O, état, frontières de packages) avec ce qui existe pour chacun.
2. **Toi et Thibault, tout de suite, sans attendre Sophie.** Une conversation, pas un formulaire :
   - **Une question à la fois**, courte (une ou deux phrases). Pas d'`AskUserQuestion`, pas de rapport,
     pas de cockpit : du texte, dans la session. Six lignes au plus par message.
   - **Tu rebondis sur ce qu'il dit** : tu reformules en une phrase ce que tu as compris, tu poses la
     question suivante qui en découle, tu pointes le cas qu'il n'a pas vu (vide, erreur, hors ligne,
     double appel, données existantes), tu proposes deux ou trois pistes avec celle que tu recommandes
     quand ça l'aide à trancher. Il peut changer d'avis en route : suis-le.
   - **D'abord le fonctionnel** : pour qui, quel déclencheur, ce que l'utilisateur voit, les cas
     limites, ce qui est hors périmètre (avec un exemple). **Puis la base technique** : où ça vit,
     ce qu'on réutilise, comment la donnée circule, ce qui est nouveau (I/O, état, package). Les choix
     structurants se tranchent **ici** : sur ceux-là, demande d'abord « comment tu le ferais ? » et
     réagis à **son** raisonnement (ce qui tient, ce qui manque, les risques) avant de donner le tien.
   - **Les faits de Sophie arrivent en route** : sa notification ne coupe pas l'échange ; au message
     suivant, glisse le fait utile avec son `fichier:ligne` (« `X` existe déjà dans `core/…:42`, on
     s'appuie dessus ? »).
   - **Les règles non négociables** (`create_feature_rules.md`, gestion d'erreur, règles tirées de ses
     réponses) ne se discutent pas : rappelle-les quand elles tranchent, en une ligne.
   - **Tu notes au fil de l'eau** dans `.claude/features/<nom>/discussion.md` : les décisions prises
     (une ligne chacune, avec la raison dans ses mots), le périmètre retenu, les questions encore
     ouvertes. C'est l'entrée de Sophie, pas un compte rendu pour lui.
   - **Fin de la discussion** : quand il dit que c'est clair, ou qu'il ne reste que des détails. Un
     récapitulatif de 15 lignes au plus — ce qu'on fait, ce qu'on ne fait pas (un exemple chacun),
     les comportements clés, les choix techniques avec leur raison, le package, le gabarit qui se
     dessine. Il le valide ou le corrige, en texte ; une correction se discute, puis le récapitulatif
     revient.
3. **Sophie écrit le cadrage** (`feature-specifier`, prompt : « mode cadrage », nom, `discussion.md`,
   `exploration.md`, issue, racine, graphe, sortie `.claude/features/<nom>/cadrage.md`). Elle **met en
   forme ce qui a été décidé**, elle ne rouvre rien : ce qui existe, le besoin dans les mots de Thibault,
   le périmètre avec ses exemples, les comportements C<n> avec leur séquence, le package et les
   dépendances, les **décisions techniques prises** (avec leur raison), les règles, le gabarit et ses
   mesures. Un trou qu'elle trouve en écrivant (une séquence qui ne tient pas, un cas jamais abordé) va
   dans une courte section « À confirmer » — pas une salve de questions.
4. **Toi, avec le rapport.** `gauntlet.sh report <nom> cadrage`, puis « Rafraîchir » (cockpit) : le
   cadrage rendu, une séquence par scénario. Les « À confirmer » se discutent dans la session, comme en 2 ;
   une réponse va dans `discussion.md`, Sophie intègre (« intègre, ne réécris pas le reste »).

5. **Gabarit.** Vérifie la proposition de Sophie contre les critères de « Gabarits » (c'est la
   règle qui tranche, pas l'estimation de l'agent : 3 décisions majeures, c'est M même si elle
   propose S).
6. **Fin du cadrage** : une seule question (en boutons dans le cockpit, « Répondre depuis la page ») avec une à trois réponses à donner — « C'est bien ça
   qu'on fait, séquences comprises ? » (Oui / Non, je précise), **seulement si le gabarit retenu est
   L** « Découper ? » (le découpage proposé / continuer en M) — un S ou un M s'applique sans question,
   annoncé en une ligne avec ses mesures (règle du dev) — et, seulement si le cadrage propose une vraie alternative, « Package » (la proposition, puis
   l'alternative, chacune avec ce qu'elle change). Oui → `size`, `size_reason` (les mesures, une
   ligne), `package` et `mode` si le package a changé : `pipeline.sh size <nom> <S|M|L> "<mesures>"`,
   `pipeline.sh gate <nom> cadrage size=<S|M|L> package=<chemin>`, `pipeline.sh pass <nom> cadrage`. Le package et les dépendances validés iront en §9 au statut
   `validée` : ils ne se reposent plus.
7. **En L : découpage, puis arrêt.** Le découpage proposé se valide comme le reste du cadrage
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
brouillon en appliquant les décisions techniques prises (il ne les repose pas), Sophie le reprend en §1-§2 tel quel ; ni un contrat ni §9 ne le contredisent. Un changement
de périmètre demandé plus tard repasse par 0b (cadrage mis à jour et revalidé) avant toute relance.

