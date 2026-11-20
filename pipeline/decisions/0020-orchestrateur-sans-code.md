# 0020 — L'orchestrateur d'un /feature ou d'un /fix ne lit pas de code : la question part à l'agent de l'étape

Statut : acceptée (2026-11-20)
Où elle vit : `hooks/orchestrator-reads.sh` (PreToolUse `Read|Grep|Glob|Bash` de `settings.json`) ·
`commands/feature.md` et `commands/fix.md` (« Tu ne lis pas de code ») · `scripts/gauntlet/tests/test_hook_orchestrator_reads.sh` ·
journal des refus (ADR 0019)

## Contexte

`commands/feature.md` dit déjà à l'orchestrateur « tu passes des chemins et des faits, jamais ton historique ».
La règle n'était pas tenue : environ 870 tours où l'orchestrateur d'un /feature lit ou cherche lui-même
(`grep` 365, `sed` 216, `cat` 152, `ls` 96, `Read` 69 ; `dead/tours.py`), dont du code de `lib/` et `test/` et
des logs entiers du gauntlet. Chaque lecture reste dans son contexte pour le reste de la session : elle coûte
à chaque tour suivant, et elle pousse l'orchestrateur à trancher lui-même ce qu'un agent à contexte vierge
doit établir.

## Décision

Un hook refuse à l'orchestrateur, pendant un /feature ou un /fix, la lecture du code, et dit pourquoi.

- **Qui.** La session principale : ni `agent_type` ni `agent_id` dans l'entrée du hook. Un sous-agent n'est
  jamais concerné. Et seulement pendant un /feature ou un /fix : la dernière commande d'orchestration (`feature`, `fix`,
  `epic`, `reviewPR`) de son transcript est `feature` ou `fix`, tapée par Thibault ou appelée par le Skill tool. Une
  autre commande (`create_mr`, appelée par /feature lui-même ; `/compact`) ne termine pas le run. Seuls
  comptent un vrai message de l'utilisateur et un vrai appel du Skill tool : le même texte cité dans un
  résultat d'outil a ses guillemets échappés et ne compte pas.
- **Refusé.** Un fichier de code (un dossier `lib`, `test`, `tests`, `integration_test`, `test_driver`, `src`
  dans le chemin, ou une extension source) par `Read`, `Grep`, `Glob`, et par Bash `cat`, `less`, `more`,
  `bat`, `nl`, `awk`, `sed`, `head`, `tail`, `grep`, `rg`, `ls`, `find`, `tree`. Une recherche récursive dans
  un dossier qui contient du code, sauf restreinte à des fichiers qui n'en sont pas (`--include='*.md'`,
  `-g`, `-name`, un glob `**/*.json`). Le log entier du gauntlet (`.gauntlet/*.log`) par `Read` sans `limit`,
  `cat`, `less`, `more` ou `bat`.
- **Permis.** Les fichiers du pipeline : ce qui est sous un dossier `.claude` du projet (`.claude/features/<nom>/`, `.claude/fixes/<nom>/`,
  `pipeline.json`, `fix.json`, la spec, le diagnostic, `.claude/rules/`), hors `.claude/worktrees/` où vit le code des worktrees ;
  `~/.claude` (steps, scripts) ; le scratchpad. Un **extrait** à montrer à Thibault (`fichier:ligne`, que
  demandent les étapes 1e, 1f, 3, 4 et 8b) : `Read` avec `limit` ≤ 40, `sed -n 'a,bp'`, `head` ou `tail` de
  40 lignes au plus, sur un seul fichier nommé. Le log du gauntlet par `tail`, `grep`, `sed`, `Read` avec
  `limit`, et `last_<profil>.json` par `jq`. `ls` d'un dossier qui n'est pas du code, `wc`, `jq`, `git`.
- **Le refus** dit pourquoi et quoi faire : la question part à l'agent de l'étape avec le chemin et ce qu'on
  cherche ; un extrait passe par `limit` ou `sed -n` ; le log par le résumé du gate. Il s'écrit au journal
  de la feature ou du fix (ADR 0019).

Un hook à part, pas une extension de `pipeline-restrict-writes.sh` : celui-là juge les écritures des
sous-agents par zone ; celui-ci juge les lectures de la session principale. Ils n'ont ni le même appelant
ni la même question.

## Conséquences

- L'orchestrateur délègue ce qu'il lisait : un rapport d'agent plus long, un contexte plus court.
- La correction d'un test par l'orchestrateur, sur instruction de Thibault (étape 4), passe par un extrait
  lu avec `limit`, puis `Edit` ; une correction qui demande de lire tout le fichier part à Théo.
- Le hook voit chaque `Read` et chaque `Bash` de chaque session : chemin rapide (outil, agent, transcript)
  avant toute analyse, environ 0,2 s sur un transcript de 11 Mo pendant un /feature.
- Mesure : `dead/tours.py` après un mois.

## Hors champ

- `/reviewPR`, `/epic` et les sous-agents : rien ne change pour eux. /fix est entré le jour même, sur décision de Thibault (« oui sur fix »).
- `git show`, `git diff`, `git log -p` ne sont pas jugés : l'orchestrateur lit un diff à certaines étapes.
- Les écritures : ce hook ne juge que les lectures (`sed -i` passe ici, d'autres hooks en décident).
- L'analyse des commandes Bash est textuelle (découpage sur `;`, `&&`, `|`, mots par `xargs`) : une lecture
  cachée dans `$(…)`, `xargs cat` ou un script n'est pas vue. Un refus se rapporte, il ne se contourne pas.
