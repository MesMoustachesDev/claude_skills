---
name: image-post
description: "Génère l'image d'un post LinkedIn de Thibault : Claude écrit la scène à partir du post, l'envoie avec les photos de référence et un style au webhook n8n « Image LinkedIn » (Gemini Nano Banana Pro), puis montre le résultat. Gère aussi sa photo de profil LinkedIn (mode portrait fidèle : on retouche une vraie photo de lui au lieu de générer). À lancer quand il demande une image pour un post ou une photo de profil, ou via /image-post."
---

# Image pour un post LinkedIn

Dossier : `~/Dropbox/MesMoustachesDev/linkedin/`
- `references/` : les seules photos de référence (son visage). Ne jamais y mettre une image générée. `IMG-20260802-WA0040.jpg` est la photo de base par défaut (Image 1) : la seule de face, nette, sans casquette ni lunettes sur les yeux.
- `photos/` : ses vraies photos, pour l'option `photo originale` et comme autres photos de base possibles.
- `generees/` : les images produites, chacune avec son `.prompt.txt`.
- `.env` : `N8N_IMAGE_WEBHOOK`.

Dans ce skill (`~/.claude/skills/image-post/`) :
- `styles.md` : les styles disponibles (`## nom`). `identite`, le verrou d'identité, est ajouté automatiquement.
- `generer_image.sh` : l'appel au webhook. Envoie la photo de base en Image 1, puis les autres références.
- `portrait-fidele.scene.txt` : la scène de la photo de profil.

## La règle de ressemblance

C'est l'Image 1 qui porte son visage, pas le texte. Les modèles d'image (Nano Banana Pro compris) gardent bien mieux un visage quand on leur dit « garde-le exactement comme sur l'Image 1, change seulement X » que quand on le décrit. Une description (« visage large, barbe dense… ») les pousse à inventer un barbu générique.
- Ne décris jamais son visage, sa barbe ni ses cheveux dans une scène. Désigne-le : « the man from Image 1 ».
- Dis seulement ce qui change : décor, tenue, posture, lumière, cadrage.
- Le réalisme vient du vocabulaire photo (boîtier, focale, ouverture, lumière) et d'une vraie peau demandée explicitement, pas d'adjectifs comme « realistic » ou « beautiful ».

## Photo de profil

S'il demande une photo de profil, ce n'est pas une image de post : saute les étapes 1 à 3.
Sa photo de profil validée (en ligne sur LinkedIn depuis le 19/10/2026) : `generees/photo-profil-v4-20261019.jpg`.

**Une variante de la photo validée** (autre fond, autre tenue) : ne régénère pas depuis ses photos, le visage dérive à chaque génération (le 19/10, un fond anthracite régénéré ne lui ressemblait plus). Modifie la photo validée seule :
1. Écris `generees/photo-profil-<variante>-<date>.scene.txt` : « Edit Image 1. Change ONLY <le changement>. Everything else stays pixel-identical to Image 1: face, expression, beard, hair, skin, pose, framing, lighting on him. Do not regenerate or retouch the person. »
2. Lance : `SEULE_BASE=1 ~/.claude/skills/image-post/generer_image.sh <scène> portrait-profil photo-profil-<variante>-<date> 1:1 ~/Dropbox/MesMoustachesDev/linkedin/generees/photo-profil-v4-20261019.jpg`

**Une nouvelle photo de profil** (s'il veut repartir de zéro) :
1. Copie `portrait-fidele.scene.txt` dans `generees/photo-profil-<date>.scene.txt`, sans en retirer le verrou d'identité ni le bloc photo. N'y change que ce qu'il a demandé (couleur du fond : bleu-gris, anthracite ou gris clair ; tenue). Le fond reste uni, sans décor.
2. Lance : `~/.claude/skills/image-post/generer_image.sh ~/Dropbox/MesMoustachesDev/linkedin/generees/photo-profil-<date>.scene.txt portrait-profil photo-profil-<date> 1:1`

Puis passe à l'étape 5, en comparant aussi à la photo validée.

## 1. Le post

Prends le texte du post : celui qu'il colle, ou un brouillon de The Engine (`get_post`) s'il en nomme un.

## 2. Le style

S'il a nommé un style, prends-le. Sinon, lis les sections de `styles.md` et demande-lui avec AskUserQuestion (une question par post, `fusain` en premier, puis les autres styles, et **toujours une option `photo originale`** : une vraie photo de lui, sans génération). Ne choisis pas à sa place. Si plusieurs posts : une question par post (4 max par appel, refais un appel pour les suivants), pas une question groupée.

### Photo originale

S'il choisit `photo originale` : pas de scène, pas de webhook, pas de retouche.
1. Regarde (Read) chaque photo de `photos/` et de `references/` (les vraies photos, jamais `generees/`).
2. Propose-lui celles qui collent au ton du post avec AskUserQuestion : `label` = nom du fichier, `description` = ce qu'on voit et pourquoi elle colle au post.
3. Utilise le fichier tel quel, sans recadrage, filtre ni modification. Passe directement à l'étape 5 avec ce fichier.

## 3. La scène

Écris la scène en anglais, 4 à 8 lignes, dans `generees/<nom>.scene.txt` (`<nom>` = un slug court du sujet + la date). Elle commence par « The man from Image 1 » et ne décrit jamais son visage (voir la règle de ressemblance). Ce que la scène doit dire :
- **Le décor, choisi selon le ton du post** :
  - technique / concentré : bureau à la maison près d'une fenêtre, coin de café, coworking
  - freelance / indépendance / argent : terrasse de café, rue, quai de gare (de passage)
  - histoire / échec / apprentissage : table de cuisine, canapé, bureau tamisé
  - IA / outils / productivité : open space, tableau blanc, espace commun de coworking
  - communauté / partage : couloir de conférence, événement, café animé
- **Un détail concret tiré du post** quand il s'y prête (une montre au poignet, un téléphone posé avec une recette…), jamais de texte ni de code lisible.
- **La posture** : naturelle, assise ou appuyée, de trois-quarts, regard ailleurs, ne pose pas pour l'objectif. Mains vides ou au repos, pas d'objet symbolique tenu.
- **Le cadrage** : la personne occupe 50 à 60 % du cadre, légèrement décentrée.

Ne répète pas le style ni les règles d'identité : le script les ajoute.

## 4. L'appel

```bash
~/.claude/skills/image-post/generer_image.sh ~/Dropbox/MesMoustachesDev/linkedin/generees/<nom>.scene.txt <style> <nom> 4:5 [photo_base]
```

Le script envoie la photo de base en Image 1 (par défaut `references/IMG-20260802-WA0040.jpg`), puis les autres photos de `references/`. Passe une autre `photo_base` (chemin complet, prise dans `references/` ou `photos/`) seulement si la scène demande un angle très différent. Timeout 240 s : la génération prend souvent 30 à 90 s. S'il échoue, montre le message d'erreur tel quel, ne relance pas plus d'une fois.

## 5. Le résultat

Lis l'image produite et compare-la à 2 photos de `references/` : visage large aux joues pleines, barbe brune très dense et longue, cheveux longs attachés. Si ça ne lui ressemble pas (visage trop fin, barbe courte, traits lissés, « un Jean-Michel au hasard »), ne la lui montre pas comme acceptable : relance une fois. Pour cette relance, ne décris pas ses traits. Retire de la scène ce qui contredit l'Image 1 (un angle trop éloigné, une expression forcée), ou passe une autre photo de base. N'attache jamais une image qui ne lui ressemble pas. Puis montre-la avec SendUserFile. Dis en une phrase si la ressemblance et le style tiennent. Propose : relancer avec une autre scène, un autre style, ou l'attacher au brouillon dans The Engine. N'attache rien sans son accord.
