---
name: post-call-malt
description: "Après un call Malt d'une heure : Thibault dicte 3 lignes de compte rendu et le besoin détecté, le skill les écrit dans la fiche Notion « Leads CTO », pose les prochaines actions (J+2 compte rendu écrit, J+7 reco Malt, J+30 nouvelles) et signale un besoin hors mobile. Interactif, à lancer via /post-call-malt, ou proposé par la routine du matin quand une fiche passe en « Call Malt fait »."
---

# Post-call Malt

Un call d'une heure devient une mission quand il est suivi dans les 48 h d'un compte rendu écrit avec 2 ou 3 recommandations, dont une où j'interviens naturellement. Ce skill s'assure que ça arrive. Tout en français.

Base Notion « Leads CTO », data source `collection://2f51306a-181a-80eb-a76e-000ba6c4a442`.

## 1. Trouver la fiche

- Si un nom est passé en argument, cherche la fiche par `Name` (SQL, LIKE insensible à la casse).
- Sinon, liste les fiches en « Call Malt prévu » ou « Call Malt fait » dont `Notes` ne contient pas « CR : », et demande laquelle avec AskUserQuestion (une option par fiche).
- Aucune fiche : dis-le et arrête.

## 2. Recueillir

Pose une seule question, en texte libre, qui demande les 4 choses d'un coup :
1. Le compte rendu en 3 lignes (contexte, problème, ce que j'ai conseillé).
2. Le besoin détecté, en quelques mots (mobile, backend, web, design, data, recrutement, rien).
3. Les 2 ou 3 recommandations que je vais écrire dans le compte rendu envoyé.
4. Si une mission est déjà évoquée, laquelle.

Si Thibault répond partiellement, ne redemande qu'une fois ce qui manque. S'il ne répond pas, n'écris rien.

## 3. Écrire dans Notion

`update_properties` sur la fiche :
- `Statut` : « Call Malt fait » (ou « Mission » si une mission est actée).
- `Dernier contact` : aujourd'hui.
- `Besoin détecté` : le besoin, tel que dicté.
- `Notes` : en tête, `AAAA-MM-JJ CR : <les 3 lignes> | Recos : <les recos>`, puis les notes existantes.
- `Prochaine action` : aujourd'hui + 2 jours. `Action` : « Envoyer le compte rendu écrit avec les recos ».

Puis insère dans le contenu de la page (insert_content, à la fin) une liste à cocher avec les deux suivantes, pour que je les retrouve quand la première est faite :
- J+7 : demander la recommandation Malt
- J+30 : prendre des nouvelles de la reco mise en place

Quand la routine du matin voit `Action` = « Envoyer le compte rendu… » échue et cochée, elle passera à la suivante : ce n'est pas ce skill qui le fait.

## 4. Rendre

Trois lignes maximum : la fiche mise à jour (lien), la prochaine action et sa date, et, si le besoin détecté n'est pas du mobile, une ligne « besoin hors mobile : <besoin>, à passer au pool de freelances quand il existera ».

Pas de récapitulatif, pas de félicitations.
