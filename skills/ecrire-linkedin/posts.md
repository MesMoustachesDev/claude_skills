# Règles d'un post

Ces règles s'ajoutent à `voix.md` (tics, procédés, règles de style) et aux sections « MON PÉRIMÈTRE TECHNIQUE » et « CE QUE JE SUIS » de `commentaires.md`, qui valent aussi pour les posts.

## Le fond

- N'invente rien sur ce que je fais. Un fait du post vient de ce que j'ai dit, d'une discussion Claude Code, ou de « CE QUE JE SUIS ». Pas d'anecdote, de chiffre ou de résultat fabriqué.
- **Pas de trou.** Jamais de `[À COMPLÉTER]`, `[X]`, `TODO` laissé dans le texte. Le fait manquant (une conclusion, un chiffre, un résultat), va le chercher toi-même dans les transcripts `~/.claude/projects/*/*.jsonl` du projet concerné (préfixe les chemins par `./`, les dossiers commencent par « - »), avec des sous-agents en parallèle s'il y en a plusieurs. S'il n'existe nulle part, réécris le passage pour ne plus en dépendre, et dis-le.
- Les missions clients ne sont jamais citées par leur nom (audin, my-center, Wifirst…) : « une app terrain », « un client ».
- Pas de données perso : emails, identifiants, noms de proches.
- Hors de mon périmètre technique, je ne fais pas l'expert : je raconte en curieux.
- Les chiffres et citations d'une source externe : la source est nommée (subreddit, rapport, site).

## La forme

- **Jamais de hashtags.**
- Uniquement des caractères tapables au clavier : pas de tiret cadratin ni demi-cadratin, pas de flèche, pas de puce spéciale, pas d'apostrophe typographique ’, pas de « … » en un seul caractère (trois points tapés). Les guillemets « » sont permis dans un post.
- Listes en « - » en début de ligne, introduites par une ligne finie par « : ».
- Pas de tournures IA : pas de « Le problème n'est pas… », « Ce qui fait la différence… », « Pas X. Mais Y. », « X, c'est A. Y, c'est B. », pas de « c'est comme », pas de maxime de mug, pas d'enchaînement de petites phrases-constats. Écrire simple, comme à un enfant de 8 ans. Un storytelling en phrases courtes, ça va.
- Je ne suis pas PO : « ce à quoi on pense » plutôt que « ce qui a été décidé ».
- 2 ou 3 tics de `voix.md`, une touche Kaamelott au maximum.
- Emojis : zéro, ou un seul qui ajoute le ton. Jamais 🚀 💡 🎯 🔥 ✅ 👉 💪 🙌.
- Longueur : 800 à 1 800 caractères en général, 3 000 au maximum (limite The Engine).

## La checklist de viralité de The Engine (à cocher, toutes)

1. Double hook : les deux premières lignes accrochent, chacune seule.
2. Open loop : une question ou une tension posée tôt, résolue plus tard.
3. Phrases longues et courtes alternées.
4. Un bloc en escalier : des lignes courtes qui s'enchaînent.
5. Une ligne finie par « : » avant une liste en « - ».
6. Des parenthèses (un aparté, une vanne).
7. De petites touches d'humour.
8. Des mots de liaison en début de ligne (« Sauf que », « Bah oui », « Et », « Du coup »).
9. Dire à qui il s'adresse (« Si tu es dev mobile… »).
10. **Une punchline en dernière ligne avant le PS.** Essentielle. Une question finale ne compte pas.
11. Un PS.

## Pour le ton

Avant d'écrire, lis 2 ou 3 de mes posts publiés qui ont marché : `search_posts` avec `only_mine: true`, tri `engagement_rate` desc, `posted_from` il y a 90 jours, `page_size` 5. Pas les anciens fichiers de `brouillons/`, qui peuvent contenir des erreurs (hashtags notamment).
