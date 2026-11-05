# 0010 — Une question à Thibault se pose en AskUserQuestion et se suffit à elle-même

Statut : acceptée (2026-11-05)
Où elle vit : `commands/feature.md`, `commands/fix.md`, `commands/epic.md`, `commands/reviewPR.md`
(« Une question se suffit à elle-même ») · `pipeline/suggestions.md` (« Ce que l'orchestrateur montre
au dev ») · `pipeline/{feature,fix,review}/cockpit.md` (« Répondre depuis la page », retirée)

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
  qu'on attend Thibault).
- La question contient tout ce qu'il faut pour trancher : de quoi on parle (`fichier:ligne`, ce que
  fait le code ou ce que dit la spec), ce qu'on demande, et pour chaque option ce qu'elle change.
- Jamais un identifiant seul (`S1`, `K3`, « le point 2 ») sans ce qu'il désigne. Les suggestions :
  le texte de la question résume chacune (problème → correctif), le label dit ce qui change.
- Le message au-dessus peut porter le détail long ; la question ne s'y réfère pas.

C'est une consigne d'orchestrateur : aucun script ne relit les questions.

## Conséquences

- Des questions plus longues, une question par lot de 4 suggestions au plus.
- Un `AskUserQuestion` bloque : une réponse ne peut plus venir de la page du cockpit. Le cockpit
  reste une page de lecture (rapports, avancement).

## Hors champ

- Les questions ouvertes (une discussion, « comment tu le ferais ? ») restent du texte dans la session.
- Le contenu des rapports et des pages du cockpit ne change pas.
