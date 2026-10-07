---
name: image-post
description: "Génère l'image d'un post LinkedIn de Thibault : Claude écrit la scène à partir du post, l'envoie avec les photos de référence et un style au webhook n8n « Image LinkedIn » (Gemini Nano Banana Pro), puis montre le résultat. À lancer quand il demande une image pour un post, ou via /image-post."
---

# Image pour un post LinkedIn

Dossier : `~/Dropbox/MesMoustachesDev/linkedin/`
- `references/` : les seules photos de référence (son visage). Ne jamais y mettre une image générée.
- `styles.md` : les styles disponibles (`## nom`). `identite` est ajouté automatiquement.
- `generees/` : les images produites, chacune avec son `.prompt.txt`.
- `generer_image.sh` : l'appel au webhook.

## 1. Le post

Prends le texte du post : celui qu'il colle, ou un brouillon de The Engine (`get_post`) s'il en nomme un.

## 2. Le style

S'il a nommé un style, prends-le. Sinon, lis les sections de `styles.md` et demande-lui avec AskUserQuestion (une question, les styles en options, `fusain` en premier). Ne choisis pas à sa place.

## 3. La scène

Écris la scène en anglais, 4 à 8 lignes, dans `generees/<nom>.scene.txt` (`<nom>` = un slug court du sujet + la date). Ce que la scène doit dire :
- **Le décor, choisi selon le ton du post** :
  - technique / concentré : bureau à la maison près d'une fenêtre, coin de café, coworking
  - freelance / indépendance / argent : terrasse de café, rue, quai de gare (de passage)
  - histoire / échec / apprentissage : table de cuisine, canapé, bureau tamisé
  - IA / outils / productivité : open space, tableau blanc, espace commun de coworking
  - communauté / partage : couloir de conférence, événement, café animé
- **Un détail concret tiré du post** quand il s'y prête (une montre au poignet, un téléphone posé avec une recette…), jamais de texte ni de code lisible.
- **La posture** : naturelle, assise ou appuyée, regard ailleurs. Mains vides ou au repos, pas d'objet symbolique tenu.
- **Le cadrage** : la personne occupe 50 à 60 % du cadre, légèrement décentrée.

Ne répète pas le style ni les règles d'identité : le script les ajoute.

## 4. L'appel

```bash
~/Dropbox/MesMoustachesDev/linkedin/generer_image.sh ~/Dropbox/MesMoustachesDev/linkedin/generees/<nom>.scene.txt <style> <nom> 4:5
```

Le script envoie toutes les photos de `references/`. Timeout 240 s : la génération prend souvent 30 à 90 s. S'il échoue, montre le message d'erreur tel quel, ne relance pas plus d'une fois.

## 5. Le résultat

Lis l'image produite pour la regarder, puis montre-la avec SendUserFile. Dis en une phrase si la ressemblance et le style tiennent. Propose : relancer avec une autre scène, un autre style, ou l'attacher au brouillon dans The Engine. N'attache rien sans son accord.
