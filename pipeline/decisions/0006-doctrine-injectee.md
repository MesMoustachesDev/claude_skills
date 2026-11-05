# 0006 — La doctrine d'un agent est injectée dans son contexte, pas demandée

Statut : remplacée par 0008 (2026-11-05) : au-delà de 10 Ko, Claude Code range la sortie d'un hook dans un
fichier et n'en donne qu'un aperçu ; 14 agents sur 16 ne recevaient que le début de leur doctrine.
Où elle vit : `hooks/doctrine.py` et `hooks/doctrine.json` (hook `SubagentStart` de `settings.json`)

## Contexte

Les agents recevaient leur doctrine sous forme de chemins : « lis `create_test.md` » dans leur fichier,
ou le chemin dans le prompt de lancement de l'orchestrateur. 371 transcripts (29/10 au 05/11) montrent
que la lecture dépendait de l'agent :
- Théo ne relisait jamais `create_test.md` en relance (0/14), Hugo jamais (0/12) ;
- Bastien ne lisait jamais `debug_issue.md` (0/7) ;
- les règles d'écran étaient lues 0 à 2 fois sur 5 à 9 runs, et leur chemin n'existait pas dans projet-client ;
- `answers.md` n'était lu que 1/9 fois chez Romain et 3/46 chez Arthur.

Seuls les `.claude/rules/*.md` du projet et les skills de l'en-tête arrivaient à chaque fois, parce
que Claude Code les charge lui-même.

## Décision

- Un hook `SubagentStart` lit les fichiers que `doctrine.json` associe au type d'agent et les met en
  entier dans son contexte (`additionalContext`), à chaque lancement, relances comprises.
- `rules:<fichier>` désigne la règle du projet (`.claude/rules/` à la racine du repo ou dans un dossier
  de premier niveau) ; sans elle, le template `commands/templates/flutter/<fichier>`. Un agent n'a plus
  de « si présent » qui le laisse sans règle.
- Une doctrine nouvelle pour un agent s'ajoute dans `doctrine.json`, pas en « lis X » dans son prompt.
- Le template n'est qu'un filet. Une règle projet absente (`create_screen_rules.md`, `pr_rules.md`) est
  signalée par le doctor (`RÈGLE ABSENTE`), et le preflight de `/feature` demande à Thibault : la créer
  depuis le template, garder le template (`rules.template`), ou s'en passer (`rules.none`, le hook ne donne
  plus rien pour elle).

## Conséquences

- Plus de lecture sautée : vérifié sur Romain, qui cite `review_grid.md` sans ouvrir de fichier.
- Le contexte de départ grossit : de 7 Ko (Théo) à 40 Ko (Romain, cinq fichiers).
- Les consignes « lis X » restées dans les fichiers d'agent sont sans effet : le texte injecté dit à
  l'agent que c'est fait.

## Hors champ

- Les skills de Claude Code (`simplify`…) : intégrés, ils ne se préchargent pas et ne sont pas des
  fichiers. Nina a sa méthode écrite dans son prompt.
- Les règles projet chargées d'office suivent le dossier de la session qui lance l'agent, pas sa ligne
  `Racine :` ; ce hook ne change rien à ça.
