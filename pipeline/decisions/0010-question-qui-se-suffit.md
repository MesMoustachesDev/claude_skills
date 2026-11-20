# 0010 — Une question à Thibault se pose en AskUserQuestion et se suffit à elle-même

Statut : acceptée (2026-11-05), amendée le 2026-11-19 (cockpit de /feature et /fix retiré), amendée le 2026-11-20 (règle commune dans `pipeline/conduite.md`), amendée le 2026-11-20 (précisions de /feature étendues à /fix)
Où elle vit : `pipeline/conduite.md` (lu par `/feature` et `/fix`), `commands/epic.md`, `commands/reviewPR.md`
(« Une question se suffit à elle-même ») · `pipeline/suggestions.md` (« Ce que l'orchestrateur montre
au dev ») · `pipeline/review/cockpit.md` (« Répondre depuis la page », retirée)

## Contexte

Thibault répond souvent depuis Remote Control, où il ne voit que l'`AskUserQuestion`, pas le texte
au-dessus. Les orchestrateurs posaient le contexte dans le message (blocs de suggestions, extrait de
code, plan) et une question nue : « S1–S4 : lesquelles ? », « on applique S1 ou pas ». Sans le texte
au-dessus, il ne savait pas de quoi on parlait.

Le cockpit faisait répondre depuis la page, sans `AskUserQuestion` bloquant (`--ask`). Thibault ne
s'en sert plus : trop contraignant.

## Décision

- Tout choix demandé à Thibault se pose en `AskUserQuestion`, dans `/feature`, `/fix`, `/epic` et
  `/reviewPR`. « Répondre depuis la page » et `--ask` sont retirés ; `say` reste (il dit au watchdog
  qu'on attend Thibault). Amendement (2026-11-19) : le cockpit de `/feature` et `/fix` est retiré
  (0004) et leur `say` devient `ask` (0005). `/reviewPR` garde son cockpit, son tri et son `say`.
- La question contient tout ce qu'il faut pour trancher : de quoi on parle (`fichier:ligne`, ce que
  fait le code ou ce que dit la spec), ce qu'on demande, et pour chaque option ce qu'elle change.
- Jamais un identifiant seul (`S1`, `K3`, « le point 2 ») sans ce qu'il désigne. Les suggestions :
  le texte de la question résume chacune (problème → correctif), le label dit ce qui change.
- Le message au-dessus peut porter le détail long ; la question ne s'y réfère pas.

C'est une consigne d'orchestrateur : aucun script ne relit les questions.
- Amendement (2026-11-20) : le texte de la règle, écrit deux fois dans `commands/feature.md` et
  `commands/fix.md`, est dans `pipeline/conduite.md`, lu par les deux. Les précisions qui n'étaient que dans
  l'un y restent marquées /feature ou /fix ; rien ne change sur le fond.
- Amendement (2026-11-20, Thibault) : les précisions écrites pour /feature seul valent aussi pour /fix :
  options sans jargon que la question n'explique pas ; l'extrait au-dessus, 3 à 8 lignes avec lien
  cliquable ; relue seule, la question permet de répondre sans cocher « Recommandé » au hasard ; et, dans
  les messages au dev, pas de récit de ce que les agents ont fait.

## Conséquences

- Des questions plus longues, une question par lot de 4 suggestions au plus.
- Un `AskUserQuestion` bloque : une réponse ne peut plus venir de la page du cockpit. Le cockpit de
  `/reviewPR` reste une page de lecture et de tri.

## Hors champ

- Les questions ouvertes (une discussion, « comment tu le ferais ? ») restent du texte dans la session.
- Le contenu des rapports ne change pas.
