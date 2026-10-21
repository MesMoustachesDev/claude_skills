### 7. Publication — validée sur le texte exact

Une revue de branche sans MR/PR : rien à publier, `review.sh pass <slug> posted` et passe à 8.

1. `review.sh post <slug>` (sans `--go`) : l'aperçu, rien n'est envoyé. Pour chaque remarque retenue,
   le commentaire tel qu'il partira, et s'il sera **en ligne** (ligne modifiée par la MR) ou
   **général** (ailleurs : il est préfixé de `fichier:ligne`).
2. Montre à Thibault, dans la session, **le texte exact** de chaque commentaire (`comments.md`), avec
   sa cible (`!218`, `fichier:ligne`, en ligne ou général). Pas de résumé : le texte.
3. Un seul `AskUserQuestion` : « Go, publier les <n> commentaires » / « Modifier un commentaire »
   (texte libre : tu le changes dans le cockpit par `ArtifactData` `set` sur
   `reviews/<clé>/triage/<id>`, puis « Trier », puis retour en 1) / « Ne rien publier » / « Discuter ».
   Un « go » ne vaut que pour ce texte-là : toute modification repasse par 1.
4. **Go** → `review.sh post <slug> --go`. Il publie un commentaire à la fois, enregistre chaque succès
   (une relance ne republie jamais un commentaire déjà parti) et passe l'étape quand tout est parti.
   Un échec : montre l'erreur, propose de relancer ou de poster ce commentaire en général.
   **Ne rien publier** → `review.sh pass <slug> posted`, et la synthèse le dira.

Approuver la MR, changer un label ou répondre à un fil existant suit la même règle : texte ou action
montré, « go » explicite, puis seulement l'appel.
