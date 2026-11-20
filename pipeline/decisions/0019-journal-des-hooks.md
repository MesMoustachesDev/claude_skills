# 0019 — Chaque décision des hooks s'écrit dans le journal du run, que lit learn

Statut : acceptée (2026-11-19)
Où elle vit : `scripts/gauntlet/hook_log.sh` (`hook_log`, `hook_run_dir` : la seule écriture) · appelée par
`hooks/no-interpreter.sh`, `state-guard.sh`, `orchestrator-reads.sh` (ADR 0020), `pipeline-restrict-writes.sh`, `fix-restrict-writes.sh`, `review-restrict-writes.sh`,
`pipeline-gate.sh`, `fix-gate.sh`, la plupart par `hooks/lib.sh` (`hook_deny`, `hook_log_decision`, `gate_log`) ·
`scripts/hook_journal.py` (la seule lecture) · `scripts/learn.py extract`
(signaux `hook_bypass`, `hook_denied_repeat`, `gate_failed`) et `pipeline/learn.md` · `scripts/report/report.py`
(section Gauntlet du rapport) · evidence de /feature (`pipeline/feature/steps/9_evidence.md`) et de /fix
(`pipeline/fix/steps/5_evidence.md`) · `scripts/gauntlet/tests/test_hook_journal.sh`, `test_realign.sh`

## Contexte

Un refus de hook n'était écrit nulle part : le message allait à l'agent, et c'était tout. Pour trouver les
refus et les contournements des sous-agents (ADR 0017), il a fallu fouiller 927 transcripts. `learn.py extract`
ne lisait que `pipeline.json`, `fix.json` et les verdicts de revue : une consigne d'agent qui le pousse contre
son hook, ou une zone qu'il contourne en recopiant un fichier gelé ailleurs, ne devenait jamais une leçon.
Idée reprise de crewAI : un événement à chaque passage dans un hook, avec son issue.

## Décision

- Une fonction, `hook_log`, que les six hooks appellent au moment de décider. Une ligne JSON par décision,
  ajoutée (`>>`) à `<run>/.gauntlet/hooks.jsonl`, `<run>` = `.claude/features/<nom>`, `.claude/fixes/<nom>`
  ou le dossier de la revue (`~/.cache/gauntlet/review/<slug>/`, trouvé dans le prompt de l'agent) :
  `at`, `hook`, `agent`, `tool`, `target` (fichier relatif au worktree, ou commande ; tronquée), `outcome`
  (`deny`, `ask`, `red`, `failed`, `allow`), `reason` (tronquée), et `stage` pour les gates (leur profil).
- `allow` ne s'écrit que pour une écriture jugée par une zone (un fichier que la zone de l'agent laisse
  passer), pas pour une lecture ni une commande sans écriture : c'est elle qui montre, après un refus, le
  même fichier écrit par un autre chemin.
- Le journal ne bloque jamais : sans dossier de run (pas de feature ni de fix courant), ou si l'écriture
  échoue, rien n'est écrit et le hook décide exactement comme avant. Pas de verrou : une ligne courte en
  ajout simple.
- Une seule lecture, `scripts/hook_journal.py` : refus par agent et par étape (gates compris), contournements
  (un refus sur un fichier, puis le même fichier écrit par un autre outil, ou un fichier du même nom écrit
  ailleurs), refus répétés (même agent, même zone, au moins deux fois). `learn.py extract` en tire des
  signaux qui suivent le chemin des autres (`record`, `candidates`) ; le rapport et l'evidence en montrent le
  tableau.

## Conséquences

- Un contournement ou une consigne qui se bat avec son hook devient une récurrence que learn propose de
  corriger, dans la consigne de l'agent ou dans le message du hook.
- Le nombre de refus par agent et par étape mesure le coût de 0017 et 0018 en tours.
- Le journal grossit avec les écritures permises de l'implementer : une ligne courte par fichier écrit.

## Hors champ

- Les décisions de l'orchestrateur et des hooks hors pipeline (`claude-home-guard.sh`, `rtk-rewrite.sh`) :
  ils n'ont pas de run.
- Un refus avant que le contexte du run soit lisible (feature inconnue) : rien n'est écrit, comme pour une
  session sans pipeline. Le gate « NON JOUÉ » non plus.
