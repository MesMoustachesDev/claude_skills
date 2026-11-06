# 0008 — La doctrine d'un agent est préchargée comme skill, les règles projet viennent de .claude/rules

Statut : acceptée (2026-11-05), remplace 0006 ; amendée le 2026-11-06 par 0011 (doctrine d'un langage)
Où elle vit : le champ `skills:` des fichiers d'agent · `skills/doctrine-*` (liens vers les fichiers de
`pipeline/` et des templates) · `.claude/rules/` des projets · `scripts/gauntlet/doctor.sh` et
`steps/00_preconditions.md` (règle projet absente)

## Contexte

L'ADR 0006 injectait la doctrine par un hook `SubagentStart`. Au-delà d'environ 10 Ko, Claude Code range la
sortie d'un hook dans un fichier et n'en met qu'un aperçu dans le contexte : sur 16 types d'agents, 14 ne
recevaient que le début de leurs fichiers (vérifié dans leurs transcripts). Deux mécanismes, eux, chargent
le texte en entier : le champ `skills:` de l'en-tête d'un agent (vérifié sur 26 Ko, dernière ligne citée,
pour un skill comme pour une commande, et pour un skill qui n'est qu'un lien vers un fichier), et les
fichiers de `.claude/rules/` du projet, chargés d'office.

## Décision

- La doctrine du pipeline est préchargée par `skills:` : `create_test` et `debug_issue` (des commandes),
  `doctrine-review-grid`, `doctrine-suggestions`, `doctrine-answers`, `doctrine-spec-template` (des liens vers
  `pipeline/*.md` et le template de spec : une seule source).
- Les règles d'un projet (`create_screen_rules.md`, `pr_rules.md`) vivent dans son `.claude/rules/`. Absente,
  le doctor la signale et le preflight demande à Thibault : la créer depuis le template, prendre le template
  tel quel (même copie), ou s'en passer (`rules.none`).
- Une doctrine nouvelle pour un agent s'ajoute à son `skills:`, jamais en « lis X ».
- Sauf la doctrine d'un langage (ADR 0011) : elle vit dans `~/.claude/rules/stacks/<langage>*.md`, chargée
  au premier fichier du langage lu. Les skills d'un langage (`dart-flutter:*`) ne sont plus dans `skills:`
  (un projet Kotlin les recevrait) : la règle du langage les nomme et l'agent les invoque avec `Skill`.
  Le gabarit de spec (`doctrine-spec-template`) reste préchargé, lien vers `stacks/flutter/templates/`.

## Conséquences

- L'agent a ses règles en entier dès son premier tour, relances comprises, sans dépendre de lui.
- Les skills `doctrine-*` apparaissent aussi dans la liste des skills des autres sessions.

## Hors champ

- Les skills intégrés à Claude Code (`simplify`) ne se préchargent pas : la méthode de Nina est dans son prompt.
