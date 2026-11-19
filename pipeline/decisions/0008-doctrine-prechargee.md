# 0008 — La doctrine d'un agent est préchargée comme skill, les règles projet viennent de .claude/rules

Statut : acceptée (2026-11-05), remplace 0006 ; amendée le 2026-11-06 par 0011 (doctrine d'un langage) ; amendée le
2026-11-19 (config des scripts hors de `.claude/rules/`, règles d'écran sous `paths:`)
Où elle vit : le champ `skills:` des fichiers d'agent · `skills/doctrine-*` (liens vers les fichiers de
`pipeline/` et des templates) · `.claude/rules/` des projets · `scripts/gauntlet/doctor.sh` et
`steps/00_preconditions.md` (règle projet absente) · `.claude/pipeline/` des projets et ses lecteurs (`stack.sh`,
`gauntlet/lib.sh`, `pr_gauntlet.sh`, `review.py`, `pipeline.py`…, `commands/deploy_app.md`, `create_mr.md`) ·
frontmatter `paths:` de `stacks/*/templates/create_screen_rules.md`

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

- **Amendement du 2026-11-19 (décision de Thibault, après mesure).** `.claude/rules/` ne garde que ce que les
  agents doivent avoir en tête. Mesure sur les transcripts du jour : les règles du projet pesaient 8,6 k tokens
  par agent au premier tour dans un projet, 16,8 k dans un autre, dont environ 6 k de fichiers qu'aucun agent
  n'applique :
  - `feature_pipeline.md` (config des scripts), `deploy_app.md` (lu par `/deploy_app`) et `create_mr_rules.md`
    (lu par `/create_mr`, `/fix_mr_comments` et l'evidence) sortent de `.claude/rules/` vers **`.claude/pipeline/`**
    du projet. Pourquoi ce dossier : Claude Code ne le charge pas (il ne lit d'office que `CLAUDE.md`,
    `rules/`, `settings*`, `agents/`, `commands/`, `skills/`) ; il ne croise ni `features/`, ni `fixes/`, ni
    `worktrees/`, ni `plans/` ; il porte le nom de ce qui le lit, le pipeline de `~/.claude`. Un projet qui
    exclut `.claude/*` avec une liste blanche ajoute `!.claude/pipeline/` (`/feature init`, étape 5).
  - Tous les lecteurs regardent `.claude/pipeline/` d'abord, puis **l'ancien `.claude/rules/`** : un projet non
    migré marche comme avant. `/feature init` propose le `git mv`. Les neuf lecteurs du bloc `ini` restent des
    copies séparées (les réunir est un autre changement).
  - `create_screen_rules.md` reste dans `.claude/rules/` mais porte un frontmatter **`paths:`** sur les fichiers
    de présentation (écrans, widgets, vues, thème) : Claude Code ne la charge qu'au premier de ces fichiers
    lu ou écrit, comme la doctrine d'un langage (ADR 0011). Les agents qui en ont besoin la lisent de toute
    façon par leur prompt (Arthur, Ivan, Romain, Quentin, Pauline). Les globs du gabarit sont génériques,
    chaque projet les ajuste à son arbre.
  - Rien d'autre ne bouge : `pr_rules.md`, `create_feature_rules.md`, `build_rules.md`, `roles.md` restent
    chargés d'office ; l'absence de règles projet dans un `/fix` en worktree est une autre question.

## Conséquences

- L'agent a ses règles en entier dès son premier tour, relances comprises, sans dépendre de lui.
- Les skills `doctrine-*` apparaissent aussi dans la liste des skills des autres sessions.
- (2026-11-19) Un agent qui veut la config du projet la lit dans `.claude/pipeline/` ; elle n'est plus dans
  son contexte d'office. Un agent qui conclut sur l'écran sans avoir ouvert de fichier de présentation n'a pas
  `create_screen_rules.md` : son prompt le lui fait lire. Le gain attendu (environ 4 k tokens par agent et par
  étape) reste à mesurer sur un vrai `/feature` après migration des projets.

## Hors champ

- Les skills intégrés à Claude Code (`simplify`) ne se préchargent pas : la méthode de Nina est dans son prompt.
