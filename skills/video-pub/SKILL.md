---
name: video-pub
description: "Fabrique une vidéo pub verticale (TikTok, Reels, 1080×1920) pour l'app d'un projet, à partir d'un parcours que Thibault décrit : filme les vraies séquences dans un simulateur iOS à part, dessine en motion design ce qui ne se filme pas (une autre app, un partage, une accroche), puis monte le tout et rend un MP4. À lancer via /video-pub <parcours>, ou quand il demande une vidéo pub, une vidéo TikTok ou une démo animée de l'app."
---

# Vidéo pub de l'app : dessin + vraies images

Thibault donne un **parcours** (« on partage une vidéo depuis TikTok vers l’app, elle s’ouvre, extrait le contenu, le range »).
Tu en fais une vidéo de 15 à 25 s : accroche dessinée, vraies séquences de l'app filmées dans le
simulateur, passages dessinés pour ce qui ne se filme pas, fin avec logo et appel à l'action.

Dans ce skill (`~/.claude/skills/video-pub/`) :
- `template/pub.html` : une composition complète qui marche, à copier puis adapter (voir « La composition »).
- `scripts/setup.sh` : installe une fois puppeteer-core et ffmpeg dans `~/.cache/video-pub`.
- `scripts/sim.sh` : simulateur à soi (clone, langue, barre d'état 9:41), enregistrement d'écran.
- `scripts/clips.sh` : planches horodatées, découpe des plans, images fixes.
- `scripts/render.js` : rendu image par image puis MP4, ou quelques captures pour vérifier.

## 0. La config du projet

Lis `.claude/video-pub.md` dans le checkout principal du projet. Elle donne : nom de l'app, couleurs
(marque, accent, texte) avec le fichier du thème d'où elles viennent, police, icône, bundle id, comment
obtenir un build simulateur, ce que l'app sait faire et ne sait pas faire (les promesses interdites),
tutoiement ou vouvoiement, dossier de sortie.

Pas de fichier : cherche les couleurs et l'icône dans le code (thème, design system, `AppIcon`) et
montre-les à Thibault avant de t'en servir. Ne prends jamais une couleur d'une note marketing ou d'une
habitude de plateforme (le jaune TikTok n'est pas une couleur de marque). Propose ensuite d'écrire le fichier.

## 1. Le storyboard, validé avant de filmer

Découpe le parcours en plans de 2 à 4 s, en tableau : temps, ce qu'on voit, **filmé ou dessiné**, titre à l'écran.
- **Filmé** : tout ce qui se passe dans l'app et que le simulateur peut montrer.
- **Dessiné** : ce qui ne se filme pas dans le simulateur (une autre app comme TikTok ou Instagram,
  la feuille de partage d'iOS, un geste sur l'écran d'accueil), l'accroche et la fin. Le dessin
  reprend les couleurs et l'icône de l'app ; il ne copie pas l'interface d'une autre marque au pixel près.
- Le passage de la feuille de partage au tap sur l'icône de l'app, s'il fait partie du parcours, est
  souvent LA fonctionnalité à montrer : ne le coupe pas parce qu'il ne se filme pas, dessine-le.
- Accroche dans les 2 premières secondes, un titre court par plan (2 lignes au plus, un mot clé surligné
  de la couleur d'accent), fin : logo, promesse, « Gratuit … » seulement si c'est vrai, « Lien en bio ».

Montre le storyboard à Thibault et attends son accord avant de filmer.

## 2. Filmer

1. `scripts/setup.sh` (une fois).
2. Un build simulateur de l'app, selon la config du projet. Un `Runner.app` récent d'un worktree qui
   contient la branche de base suffit : copie-le dans ton dossier de travail, ne lance pas de build dans
   le worktree d'une autre session.
3. `scripts/sim.sh new <simulateur éteint> <langue>` → UDID. Jamais un simulateur déjà démarré : il sert à
   une autre session. Ouvre le panneau (`attach`), installe et lance l'app (`launch`).
4. `scripts/sim.sh rec-start <udid> <dossier>/rec.mov`, puis joue le parcours avec l'outil du simulateur
   (tap, swipe, screenshot pour savoir où taper). Gestes lents et nets : ce sont les images de la pub.
   Fais défiler doucement (swipe d'au moins 0,8 s) là où la vidéo doit montrer une liste.
5. Fenêtres de consentement : choisis toujours l'option qui refuse. Notifications, avis, permission :
   « Pas maintenant ». Ces passages seront coupés au montage.
6. Connexion : n'entre jamais un mot de passe ni le compte de Thibault. Passe par le mode invité ou le
   parcours de bienvenue de l'app ; si le parcours exige un compte, arrête-toi et demande-lui comment faire.
7. `scripts/sim.sh rec-stop <dossier>/rec.mov`, puis `scripts/sim.sh off <udid>` à la fin.

L'app installée parle au vrai serveur : un compte invité, une extraction ou une donnée créée pendant le
tournage existe en production. Dis-le à Thibault dans le compte rendu.

### Avec une Apple Watch

Quand le parcours passe par la montre, filme-la aussi au lieu de la dessiner.
1. `scripts/sim.sh watch <udid iPhone> fr` : crée la montre, l'appaire à ton iPhone et attend que la paire
   soit `connected`. Sans le redémarrage dans l'ordre (iPhone puis montre) que fait le script, la paire
   reste `disconnected` et l'app iPhone ne voit pas la montre.
2. Installe l'app montre directement : `xcrun simctl install <udid montre> <Runner.app>/Watch/<app montre>.app`,
   puis lance-la (`xcrun simctl launch <udid montre> <bundle id montre>`) avant d'ouvrir l'écran de l'iPhone
   qui en dépend. Si l'iPhone dit encore « montre non installée », réinstalle l'app iPhone, puis relance les deux.
3. Le panneau du simulateur pilote aussi la montre (`device` = son UDID). Sur une pile de pages verticales,
   seul un balayage rapide change de page (0,15 s, du bas vers le haut de l'écran) ; un balayage lent ne fait rien.
4. Enregistre les deux écrans en même temps (`rec-start` sur chacun) ; leurs durées diffèrent (le
   simulateur n'écrit une image que quand l'écran change) : repère chaque moment sur sa propre planche.
   Pour la même raison, une coupe d'une seconde sur un écran immobile peut sortir vide : coupe au moins 2 s.
5. La barre d'état de la montre ne se règle pas (`status_bar` n'y marche pas) : elle montre l'heure réelle.
   Coupe le haut de l'écran au découpage (`clips.sh cutc … 416:424:0:72` pour une 46 mm) et dessine l'heure
   de l'iPhone (9:41) dans le boîtier.
6. La montre se met dans un boîtier dessiné, posé sur un poignet dessiné : l'écran filmé à l'intérieur, le reste en dessin.

Une fonction réservée aux comptes connectés (souvent le cas de la montre) ne se filme pas en invité : la
config du projet le dit ; sinon, vérifie la condition d'affichage du bouton dans le code avant de tourner.

## 3. Choisir et couper les plans

- `scripts/clips.sh sheet <rec.mov> 0 <durée> 1 planche.jpg` : une image par seconde, horodatée.
  Regarde la planche, puis resserre autour de chaque moment utile (`... <début> 3 5 zoom.jpg`, cinq images
  par seconde) pour trouver l'instant exact d'un tap ou d'un écran qui apparaît.
- `scripts/clips.sh cut <rec.mov> <début> <durée> clips/<nom>.mp4` pour chaque plan ;
  `join` pour coller deux morceaux (un écran, puis plus loin le défilement qui le suit).
- `scripts/clips.sh still` pour une image fixe tirée de l'app (une photo de plat, un écran) qui servira
  dans une partie dessinée : la vidéo dessinée d'une autre app peut montrer le même contenu que l'app filmée.
- Un chargement mis en cache est plus rapide qu'une première fois réelle : si la pub montre une vitesse,
  qu'elle soit celle qu'un nouvel utilisateur verra, sinon garde le chargement court sans rien promettre.

## 4. La composition

Copie `template/pub.html` dans le dossier de sortie, avec l'icône (`icon.png`), l'image fixe
(`contenu.jpg`) et `clips/`. Elle contient, dans l'ordre :
- `:root` : les couleurs (marque, accent, texte), à remplir depuis la config projet ;
- une scène d'accroche (galerie de captures, barre de recherche « Aucun résultat ») ;
- une scène téléphone : un écran **dessiné** (vidéo d'une autre app, bouton Partager, feuille
  « Partager vers… », doigt, tap sur l'icône, écran de lancement), puis les **vraies vidéos** de l'app
  (tableau `shots` : vidéo, début, fin, vitesse, titre) calées image par image ;
- une scène de fin (logo, promesse, gratuit, lien en bio).

Tout le mouvement dépend de `render(t)` (t en secondes) : jamais d'animation CSS ni de lecture vidéo libre,
sinon le rendu image par image ne correspond plus. Une vidéo se cale avec `currentTime` et
`renderAsync` attend `seeked`. Garde `window.DURATION` à jour.

Zones sûres TikTok sur 1080×1920 : pas de texte dans les 150 px du haut, les 420 px du bas, ni à
droite au-delà de x = 920 entre y = 900 et y = 1600 (colonne de boutons). Les titres en haut au-dessus du
téléphone, ou au centre avec `left:50px;right:170px`.

Contenu inventé (créateur, légende, recette dessinée) : jamais un pseudo qui pourrait être un vrai compte
(`@ta.recette.preferee`, pas `@chez.margaux`), jamais une statistique inventée présentée comme vraie.
Chaque promesse à l'écran doit exister dans l'app (la config liste les interdites) ; ce que tu as vu
pendant le tournage fait foi (un quota, une option payante).

## 5. Vérifier, puis rendre

1. `node scripts/render.js pub.html captures/c --frames <un temps par plan>` puis regarde les captures
   ensemble (planche `hstack`) : titres coupés ou qui débordent, texte hors zone sûre, vidéo pas calée
   (première image au lieu de la bonne), emoji illisible sur la couleur d'accent, doigt qui ne tombe pas
   sur l'icône. Corrige et recommence tant que ça ne va pas.
2. `node scripts/render.js pub.html <sortie>.mp4` (environ 1 min pour 20 s).
3. Tire 6 à 8 images du MP4 final (`ffmpeg -vf select=...,tile=8x1`) et regarde-les avant de livrer.

## 6. Livrer

Envoie le MP4 (SendUserFile, `render`) et dis en peu de lignes : le déroulé (tableau), ce qui est filmé et
ce qui est dessiné, ce qui a touché la production, ce que la vidéo ne montre pas encore. Elle est
**muette** : la musique s'ajoute dans l'outil de pub (bibliothèque commerciale de TikTok Ads Manager),
seule à couvrir les droits d'une pub. Ne publie rien, ne lance aucune campagne.
