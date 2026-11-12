# Règles d'un post

Ces règles s'ajoutent à `voix.md` (tics, procédés, règles de style) et aux sections « MON PÉRIMÈTRE TECHNIQUE » et « CE QUE JE SUIS » de `commentaires.md`, qui valent aussi pour les posts.

## Le fond

- N'invente rien sur ce que je fais. Un fait du post vient de ce que j'ai dit, d'une discussion Claude Code, ou de « CE QUE JE SUIS ». Pas d'anecdote, de chiffre ou de résultat fabriqué.
- **Pas de trou.** Jamais de `[À COMPLÉTER]`, `[X]`, `TODO` laissé dans le texte. Le fait manquant (une conclusion, un chiffre, un résultat), va le chercher toi-même dans les transcripts `~/.claude/projects/*/*.jsonl` du projet concerné (préfixe les chemins par `./`, les dossiers commencent par « - »), avec des sous-agents en parallèle s'il y en a plusieurs. S'il n'existe nulle part, réécris le passage pour ne plus en dépendre, et dis-le.
- Les missions clients ne sont jamais citées par leur nom (leur liste : `~/.claude-local/clients.txt`, hors du repo) : « une app terrain », « un client ».
- Pas de données perso : emails, identifiants, noms de proches.
- Hors de mon périmètre technique, je ne fais pas l'expert : je raconte en curieux.
- Les chiffres et citations d'une source externe : la source est nommée (subreddit, rapport, site).
- Jamais de chiffres d'audience d'une source : pas de « le post fait 68 000 vues », « 1 000 votes sur Reddit », « 365 points sur Hacker News ». On s'en fout. Ça sert à choisir l'idée, pas à l'écrire. Pareil pour le détail de la source qui n'apporte rien (qui a posté, techno, durée et conditions d'une mission) : on garde seulement ce qui sert le propos.

## La forme

- **Jamais de hashtags.**
- Uniquement des caractères tapables au clavier : pas de tiret cadratin ni demi-cadratin, pas de flèche, pas de puce spéciale, pas d'apostrophe typographique ’, pas de « … » en un seul caractère (trois points tapés). Les guillemets « » sont permis dans un post.
- Listes en « - » en début de ligne, introduites par une ligne finie par « : ».
- Pas de tournures IA : pas de « Le problème n'est pas… », « Ce qui fait la différence… », « Pas X. Mais Y. », « X, c'est A. Y, c'est B. », pas de « c'est comme », pas de maxime de mug, pas d'enchaînement de petites phrases-constats. Écrire simple, comme à un enfant de 8 ans. Un storytelling en phrases courtes, ça va.
- Je ne suis pas PO : « ce à quoi on pense » plutôt que « ce qui a été décidé ».
- 2 ou 3 tics de `voix.md`, une touche Kaamelott au maximum.
- Emojis : zéro, ou un seul qui ajoute le ton. Jamais 🚀 💡 🎯 🔥 ✅ 👉 💪 🙌.
- Longueur : 700 à 1 300 caractères, 1 800 au maximum. Ce n'est pas un tuto : un seul détail technique suffit, pas le mode d'emploi complet.

## Le ton

Constaté sur la MegaSearch de novembre 2026 : les posts tech FR qui marchent sont courts et prennent position.
- **Le hook prend position** : un pari (« Je prends le pari inverse »), un désaccord, ou une phrase de hype citée puis démontée en une ligne (« Non. Tu as ouvert 7 sessions Claude Code avec un dashboard. »). Plutôt ça que « voilà ce qui m'est arrivé ». L'anecdote vient ensuite, comme preuve.
- **Une vraie question de désaccord est permise** en toute fin, après la punchline (à la place du PS, ou après lui). Elle porte sur un point précis du post et invite à me contredire : « Je me trompe sur quel point ? », « Vous auriez gardé l'auto-enchaînement, vous ? ». La question au bateau (« Et vous, vous en pensez quoi ? ») reste interdite.
- **Le texte seul est une option à part entière.** Une image seulement si elle montre quelque chose (une capture, un chiffre), pas pour décorer.

## La checklist de viralité de The Engine (21 critères, dont 5 essentiels *)

C'est la checklist affichée dans l'éditeur de The Engine (onglet « Checklist viralité »). Après `add_post`, ouvre le brouillon dans le navigateur intégré et lis le score : un essentiel (*) ou un obligatoire raté se corrige avant de me dire que c'est fini. Le reste est facultatif, seulement si le post s'y prête : pas tout à la fois, sinon tous les posts ont le même moule. Le score total n'est pas un objectif.

Obligatoires (les 5 essentiels * de The Engine, plus les miens) :
1. * Un hook qui attire l'attention.
2. Double hook : les deux premières lignes accrochent, chacune seule.
3. Open loop : une question ou une tension posée tôt, résolue plus tard.
4. Phrases longues et courtes alternées.
5. Des parenthèses (un aparté, une vanne).
6. De petites touches d'humour.
7. * **Tes mots à toi** : mes vraies phrases et mes tics de `voix.md`, pas seulement un ton. Quand la matière vient d'une discussion, cite ce que j'ai réellement écrit (mot pour mot, avec « => » pour enchaîner ma réaction). Raté le 30/10 sur le post « Maîtrise avancée de Claude Code », qui n'avait aucune vraie phrase de moi.
8. * Parler à la première personne.
9. * Éviter les tournures IA.
10. * **Une punchline avant la fin** (avant le PS ou la question de désaccord). Une question ne compte pas comme punchline.

Facultatives :
11. Un hook à contre-courant (prendre l'avis dominant à rebours).
12. Un bloc en escalier : des lignes courtes qui s'enchaînent.
13. Une ligne finie par « : » avant une liste en « - ».
14. Des mots de liaison en début de ligne (« Sauf que », « Bah oui », « Et », « Du coup »).
15. Faire ressortir des mots (un mot en MAJUSCULES, une citation entre « »).
16. Un élément de branding (dev mobile Flutter / Android, Cookbooker, freelance).
17. Ne pas être trop lisse (un avis tranché, une aspérité).
18. Dire à qui il s'adresse (« Si tu es dev mobile… »).
19. Un PS.
20. Un visuel complémentaire (voir `/image-post`), seulement s'il montre quelque chose.

## Pour le ton

Avant d'écrire, lis 2 ou 3 de mes posts publiés qui ont marché : `search_posts` avec `only_mine: true`, tri `engagement_rate` desc, `posted_from` il y a 90 jours, `page_size` 5. Pas les anciens fichiers de `brouillons/`, qui peuvent contenir des erreurs (hashtags notamment).
