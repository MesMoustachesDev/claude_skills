### 1. Préflight — ce qui manque se demande maintenant, pas dans le briefing

Une revue qui découvre à la fin que la QA n'avait pas d'appId, que le graphe n'existait pas ou que
`glab` n'était pas authentifié a fait perdre son temps à Thibault. Tout ce qui empêcherait une partie
de la revue se vérifie ici, avant le gauntlet, et se tranche **en un seul arrêt**.

1. `review.sh preflight <slug>` (Bash timeout 600000 : il lance le doctor du gauntlet). Il vérifie :
   l'outillage (SDK épinglé installé, outils Dart du gauntlet — leur absence fait crasher `reinvented`
   et `dedup` —, linter, maestro), la config QA (plateformes, appIds réels et non de template, AVD et
   simulateur, compte de test référencé), le graphe graphify, et l'authentification de `glab`/`gh`.
   Il écrit `preflight.json` et liste les manques par domaine.
2. **Rien ne manque** → `review.sh pass <slug> preflight`, étape suivante, sans question.
3. **Sinon, un seul `AskUserQuestion`**, une question par domaine concerné (4 au plus), chacune
   précédée dans ton message de ce qui manque exactement (la ligne du préflight). Options type :
   - **qa** : « Je te donne les valeurs maintenant » (appIds, AVD ou simulateur, où est le compte de
     test : une référence à un secret, jamais la valeur) / « QA sans device : tests existants et tests
     jetables (Recommandé si pas de device sous la main) » / « Pas de QA pour cette revue ».
   - **graphe** : « Construire le graphe maintenant (`/graphify` sur le projet, quelques minutes) » /
     « Sans graphe : Alice lit les consommateurs hors package à la main ».
   - **outillage** : « Lance les corrections » (les commandes que le doctor donne : `fvm install …`,
     `dart pub global activate …` — installations locales, rien d'externe) / « Continuer : les checks
     concernés seront marqués non joués ».
   - **publication** : « Je m'authentifie (`glab auth login`, dans mon terminal) » / « Je publierai à
     la main : la revue s'arrêtera au texte validé ».
   - **projet** (pas de config) : « Continuer avec le template générique » / « Je lance `/feature init` d'abord ».
4. **Applique ses réponses** avant d'aller plus loin :
   - valeurs QA données → écris-les dans `.claude/rules/feature_pipeline.md` du projet (bloc `ini` et
     « Notes pour les agents »), montre le diff à Thibault en une ligne par clé ; c'est sa config, il
     vient de te la donner ;
   - corrections d'outillage, graphe → lance-les, puis `review.sh preflight <slug>` à nouveau ;
   - authentification → attends qu'il dise que c'est fait, puis `review.sh preflight <slug>`.
5. Pour chaque domaine : `review.sh decide <slug> <domaine> "<ce qui a été décidé>"` (ex. `qa "sans
   device : tests existants + jetables (pas d'AVD sur cette machine)"`). `review.sh pass <slug>
   preflight` refuse tant qu'un domaine signalé n'a pas de décision.

Ces décisions vont dans le prompt des agents (étape 4) et dans le briefing comme des **choix faits au
départ**. Un manque que le préflight n'avait pas vu et qui casse en route (un check qui crashe, un build
qui échoue) n'est pas noté pour la fin : c'est un point imprévu, tu t'arrêtes et tu le dis tout de suite.
