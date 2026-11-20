# /fix — étape 3 : revue, Victor (`fix-reviewer`), et les reviewers du projet

Liste `.claude/agents/*.md` du projet : un agent de revue dont la description couvre les chemins
touchés par `git diff --name-only <freeze_sha>` (ex. `appwrite-function-reviewer` pour `functions/`)
est lancé **en parallèle** de `fix-reviewer`, dans le même message. Son rapport va dans
`.claude/fixes/<nom>/review_<agent>.md` (c'est toi qui l'écris, tel quel).

**Graphe (seulement si `fix.json → graphify` n'est pas `absent`).** Avant chaque lancement de Victor,
boucles comprises, depuis le worktree : `bash ~/.claude/scripts/graphify.sh prepare <worktree> --update`,
puis `bash ~/.claude/scripts/graphify.sh impact <worktree> <base_sha> --out .claude/fixes/<nom>/.gauntlet/graphify`
(contrat : `~/.claude/pipeline/graphify.md`). Lis la dernière ligne de stdout : `ok` ou `stale` → le
chemin de `impact.json` va dans le prompt de Victor ; `échec` → note la ligne et continue sans.

Prompt de `fix-reviewer` : nom, `diagnosis.md`, `repro.json` (dont `fix_plan`), `fix.json →
plan_deviations`, `freeze_sha`, `base_sha`, règles projet, et le chemin de `impact.json` s'il a été calculé.

Au rapport de Victor, dans le même tour : `python3 ~/.claude/scripts/fix/fix.py after <nom> review_report`,
puis `python3 ~/.claude/scripts/fix/fix.py review-pass <nom>` : il reporte `review.json → debt` dans
`fix.json → debt` (sans le montrer au dev), joue le gauntlet `review_verdict` et, vert, écrit lui-même
`stages.review = PASSED` (exit 0) ; rouge, exit 1. Les problèmes **bloquants** d'un reviewer projet (sa
propre classification : critique, bloquant, erreur) comptent comme des critiques, même si `review-pass` est
vert : boucle comme ci-dessous.
- Une suggestion qui porte sur du code hors du diff depuis `base_sha`, sans la montrer :
  `python3 ~/.claude/scripts/fix/fix.py debt <nom> review <fichier> "<problème>" [--line N]` puis
  `python3 ~/.claude/scripts/fix/fix.py set <nom> suggestions.<id> '{"decision":"debt"}'`.
- `review-pass` vert et aucun bloquant projet → les **suggestions** (celles de Victor et les
  non-bloquants des reviewers projet, dans le diff) : montre-les au dev au format de
  `~/.claude/pipeline/suggestions.md` et fais-le choisir en `AskUserQuestion` multiSelect (même
  fichier). Note chaque choix : `python3 ~/.claude/scripts/fix/fix.py set <nom> suggestions.<id>
  '{"decision":"applied|skipped","note":"…"}'`. Des retenues →
  `python3 ~/.claude/scripts/fix/fix.py deviation <nom> "suggestion <id> retenue par le dev" <fichiers…>` (le plan
  validé ne les couvrait pas), `python3 ~/.claude/scripts/fix/fix.py loop <nom> review`, `SendMessage` à Fanny
  avec leur bloc complet et la nuance du dev, puis `fix.py after <nom> green`, puis revue à nouveau. Une
  suggestion déjà tranchée ne se repose pas.
- `review-pass` rouge (critiques) → `python3 ~/.claude/scripts/fix/fix.py loop <nom> review` : il archive
  `review.json` dans `history/review_<n>.json` (la passe suivante l'écrase, et learn en a besoin) et compte la
  boucle. Exit 0 : `SendMessage` à Fanny (ou un neuf si injoignable) avec la liste `critical` et leurs `fix`,
  puis `fix.py after <nom> green`, puis revue à nouveau. Exit 3 (plafond de 2 dépassé) : point d'étape hors
  plan avec les critiques persistantes.
- `plan_respected` ≠ `yes` sans critique `fix: plan` (Victor l'a jugé acceptable) : tu le
  signales au dev dans l'evidence, avec les fichiers hors plan du rapport.
- `missing_tests` de Victor : **ne relance personne**. Ils vont dans l'evidence ; le dev décidera
  s'ils méritent un second passage de Bastien.
- `to_verify` de Victor (ADR 0002 : ce qu'il soupçonne sans l'avoir prouvé en lisant ou en rejouant un test
  existant ; il n'écrit pas de probe) : `review_verdict` reste rouge tant qu'une entrée n'a pas d'`outcome`.
  `owner: "implementer"` → `SendMessage` à Fanny avec les critiques (`claim`, `how`) : elle la prouve par un
  probe `zz_probe_*` et la corrige, ou l'écarte. `owner: "reproducer"` → `SendMessage` à Bastien : prouvée,
  il écrit le vrai test, tu re-gèles (`cause` selon la liste de `fix.md`, « Re-gel ») et Fanny reprend ; écartée, rien ne
  bouge. Au rapport, note sur l'entrée de `review.json` `outcome: "proved"|"dismissed"` et `note` (la preuve
  en une ligne), puis rejoue `python3 ~/.claude/scripts/fix/fix.py review-pass <nom>`. Tout écarté et aucune
  critique → vert sans relancer Victor ; sinon `fix.py loop <nom> review`, gate green puis revue à nouveau,
  comme pour une critique. Les `outcome` vont
  dans l'evidence (« Revue »).
