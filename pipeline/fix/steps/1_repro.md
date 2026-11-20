# /fix — étape 1 : reproduction, Bastien (`fix-reproducer`)

**Chaque prompt d'agent du fix (Bastien, Fanny, Victor, et un agent neuf qui en reprend un) commence par
`Racine : <chemin absolu du worktree>`.** Les hooks y retrouvent le worktree quand le cwd hérité de ta
session n'est pas le bon (checkout principal, reprise) ; sans elle, la zone d'écriture et le gate se jouent
sur le mauvais dossier.

Prompt (15 lignes max) : `Racine : <worktree>`, nom, description brute, le ticket existant entre `<issue>` s'il y en a
une (`issue.md`, partie A), dossier du fix, chemins des règles projet
(`CLAUDE.md`, `.claude/rules/*`, `.claude/agents/*` s'il y en a — ils portent des invariants), et :
« Une issue Sentry est citée : utilise le MCP Sentry pour la stack et les tags » si c'est le cas.
Si `fix.json → graphify` vaut `ok` : « graphe : `<fix.json → graphify_graph>` (relatif à la racine,
passe-le en `--graph`), voir `~/.claude/pipeline/graphify.md` ».
**Note l'`agentId` retourné** : `python3 ~/.claude/scripts/fix/fix.py agent <nom> reproducer <agentId>` ; tu en
auras besoin pour l'arbitrage.

Au rapport de Bastien, dans le même tour : `python3 ~/.claude/scripts/fix/fix.py after <nom> red`
(`after <nom> repro_report` en phase `arbitrate` ; `~/.claude/pipeline/conduite.md`, « Au rapport d'un agent »), puis :
- `Besoin du dev : …` dans le rapport → pose la question au dev (`AskUserQuestion`), puis
  `SendMessage` à Bastien avec la réponse. Ne relance pas un agent neuf.
- `stages.red` `FAILED` → point imprévu : rapport de l'agent, 40 dernières lignes de
  `.gauntlet/last_red.log`, options (consigne à Bastien / abandonner).
- `stages.red` `PASSED` → point d'étape.

**Point d'étape — diagnostic, test rouge et plan de correction.** D'abord
`fix_gauntlet.sh report <nom> repro` (cause, plan avec son schéma, diff du test), cité par un lien
cliquable vers `report.html`, puis `python3 ~/.claude/scripts/fix/fix.py ask <nom> "Valide le diagnostic, le test rouge et le plan"` :
l'encart « à lire » de pipeline-view montre le diagnostic et le plan. Puis, court :
- Cause racine (`root_cause` + `root_cause_location`) et la preuve, en 3 lignes tirées de `diagnosis.md`.
- Pourquoi les tests l'ont raté : `miss_reason` + la phrase du diagnostic.
- Le test : `git diff <base_sha> -- <test_files>` (le diff entier s'il fait moins de 60 lignes, sinon les
  noms des tests et l'assertion clé), et la ligne `expected_failure` relevée dans `.gauntlet/target.out`.
- `baseline_suite` si elle n'est pas verte : le dev doit le savoir avant de lancer la correction.
- Le plan : `fix_plan.layer`, `approach`, `files`, et `rejected` (l'alternative écartée).
- Le parcours du signalement sur device (`device_repro`) : la capture qui montre le bug (`shots/red/`,
  `SendUserFile`, display `render`) et le symptôme relevé par `device_red`. `device_repro.not_applicable`
  → sa raison en une ligne, que le dev valide avec le test : jamais acceptée en silence. Pas de
  `device_repro` du tout → le gate red est rouge, tu ne fais pas de point d'étape.

`AskUserQuestion`, deux questions dans le même appel :
1. **Plan** (header `Plan`) : « <approche en une phrase> dans <couche> (Recommandé) » / « <alternative
   écartée> » (description : ce qu'elle change) ; « Other » pour une troisième voie.
2. **Diagnostic et test** (header `Test`) : « Valider et geler » / « Revoir le diagnostic ou le test ».

Plan changé ou test à revoir → `SendMessage` à Bastien avec le retour (« mets `fix_plan` à jour
avec le choix du dev » ; le gate red revalide `repro.json`), puis cet arrêt à nouveau.
Plan tranché : `python3 ~/.claude/scripts/fix/fix.py gate <nom> plan proposed|alternative|other`.

Validation → **gel**, après ce `gate <nom> plan` :
```bash
python3 ~/.claude/scripts/fix/fix.py freeze <nom> "<bug en une phrase, en anglais>"
```
Il commite les tests modifiés (le flow `maestro/fix_<nom>.yaml` et tout test existant corrigé par Bastien
compris, jamais un `zz_probe_*`), les manifestes touchés, `repro.json`, `diagnosis.md` et `shots/red/`, puis
écrit `freeze_sha`, `human_gates.repro` et `phase = "impl"`. Il refuse sans `stages.red` `PASSED` ou sans le
plan tranché. Le plan est gelé avec `repro.json`.

**Ticket.** `issue.status == "to_create"` → `~/.claude/pipeline/issue.md`, partie B, gabarit fix
(`repro.json` et `diagnosis.md` gelés). Puis lance Fanny.
