# 0011 — Ce qui est propre à un langage vit dans son dossier, et ne se charge que pour ce langage

Statut : acceptée (2026-11-06), amendée le 2026-11-06 (check non applicable)
Où elle vit : `scripts/stack.sh` (détection, valeurs) · `stacks/<langage>/` (`stack.ini`, `checks.sh`,
`templates/`) · `rules/stacks/<langage>*.md` (doctrine, frontmatter `paths:`) · `stacks/README.md` ·
`scripts/gauntlet/tests/test_stack.sh` · plan `.claude/plans/langages.md`

## Contexte

Le pipeline ne connaissait que Flutter, en dur : `flutter analyze` et la mutation Dart dans le gauntlet,
`pubspec.yaml` comme marque de package dans sept scripts, `lib/` et `test/` dans les hooks d'écriture, BLoC
et mocktail dans les prompts d'agents, les gabarits `commands/templates/flutter/` exposés en skills dans
toutes les sessions. Rien ne choisissait le langage. Thibault veut que **toutes** les commandes choisissent
le bon langage (Kotlin / Android natif en premier), sans que chaque langage ajoute sa doctrine au contexte
des projets qui ne l'utilisent pas.

## Décision

- **Le langage se déduit du chemin**, par `stack.sh detect` : le marqueur le plus proche en remontant
  (`pubspec.yaml` → flutter, `build.gradle*` / `settings.gradle*` → android). Une app Flutter est donc du
  Flutter dans `lib/` et du Kotlin dans `android/app/`. `stack = <langage>` dans la config du projet force.
- **Les valeurs pour les scripts** (commandes, marqueurs, globs, fichiers de dépendances) vivent dans
  `stacks/<langage>/stack.ini` ; la config du projet prime clé par clé (`stack.sh get`).
- **La doctrine pour Claude** vit dans `~/.claude/rules/stacks/<langage>*.md`, avec `paths:` sur les
  extensions du langage. Claude Code ne la charge qu'au premier Read / Write / Edit d'un fichier qui
  correspond, dans la session comme dans un sous-agent (vérifié le 2026-11-06 sur un projet jetable : rien au
  démarrage, rien à la lecture d'un `.dart`, la règle Kotlin à la lecture d'un `.kt`, dans la session et dans
  un sous-agent `general-purpose`). Toutes les commandes en profitent sans choisir quoi que ce soit.
- Commandes, prompts d'agents et `pipeline/*.md` restent **sans langage** : « la commande de test du
  langage », « les conventions de test du langage ». Aucune règle sans `paths:` dans `~/.claude/rules/`.
- Les gabarits sortent de `commands/` vers `stacks/<langage>/templates/` : sous `commands/`, chacun était un
  skill listé dans toutes les sessions.
- **Un check sans version pour le langage du package est signalé, pas bloquant** (choix de Thibault,
  2026-11-06) : `[N/A] <check> : non applicable à <langage>` dans le journal, `not_applicable` dans
  `last_<profil>.json`, jamais compté dans `passed`, et le profil peut passer. Sans ça, tout `/feature`
  d'un langage neuf serait rouge tant que ses checks ne sont pas écrits. Le revers, accepté : un check
  oublié pour un langage ne bloque rien ; le rapport et l'evidence montrent la liste des `[N/A]`.

## Conséquences

- Ajouter un langage = un dossier `stacks/<langage>/`, une règle `rules/stacks/<langage>.md`, un test.
- La doctrine d'un langage n'arrive qu'au premier fichier lu de ce langage : un agent qui conclut sans
  avoir lu de code du package ne l'a pas. Les agents du pipeline lisent le code avant d'écrire ; un agent
  qui écrit d'abord (test-writer sur un package vide) doit lire un fichier existant du langage avant.
- `~/.claude/rules/` est public comme le reste du repo : aucun nom de client ou de projet.
- La migration se fait point par point (plan `langages.md`) : tant qu'un consommateur n'est pas migré, il
  garde ses valeurs Flutter en dur, que `stacks/flutter/stack.ini` reprend à l'identique.

## Hors champ

- Les règles d'un projet (`.claude/rules/` du projet) gardent la priorité : elles disent comment **ce**
  projet applique le langage.
- Un fichier sans extension de langage (YAML de CI, Markdown) ne charge aucune doctrine : c'est voulu.
