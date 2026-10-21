### 6. Tri des remarques par Thibault

Dans le cockpit, chaque remarque montre son agent, sa gravité, `fichier:ligne`, le problème, le
pourquoi, la preuve, la suggestion, et le commentaire proposé. Thibault choisit **Commenter** ou
**Écarter**, et peut réécrire le commentaire à la main, ou l'**orienter** : un champ de consigne (« plus
court », « sous forme de question », « avec la correction en code »…) et Claude le réécrit depuis la
page, avec la remarque, sa preuve et le code autour ; « Revenir à la version d'avant » annule. Le cockpit enregistre, rien ne part.

**Attendre.** Un seul `AskUserQuestion` : « J'ai trié dans le cockpit » / « Trions ici, dans la
session » / « Discuter — je veux comprendre une remarque avant de trier ». Un message
`[cockpit <clé>]` reçu par le cockpit vaut « J'ai trié dans le cockpit ».

- **Trié dans le cockpit** → « Trier » (`~/.claude/pipeline/review/cockpit.md`) : `review.sh
  triage-pull` applique ses choix et écrit `comments.md`. Il reste des remarques non triées : pose-les
  ici, par paquets de 4 au plus (« Commenter (Recommandé) » / « Écarter », chacune précédée de son
  `fichier:ligne` et de l'extrait de code), puis écris ses choix dans le cockpit par la même voie
  (`ArtifactData` `set` sur `reviews/<clé>/triage/<id>` : `{id, decision, text, saved_at}`), et
  « Trier » à nouveau.
- **Trions ici** → même chose, toutes les remarques, critiques d'abord.
- **Discuter** → explique la remarque (le code, la preuve, ce que chaque choix change), réponds, puis
  repose la même question.

Le tri n'est **pas** une validation de ce qui sera posté : c'est l'étape 7.

Une remarque dont tu doutes de la preuve (étape 5) : dis-le dans le tri, à côté d'elle.
`pr_rules.md` impose son propre workflow de triage : il remplace celui-ci, le cockpit reste le
support. Fin : `triage-pull` passe l'étape quand toutes les remarques sont triées.
