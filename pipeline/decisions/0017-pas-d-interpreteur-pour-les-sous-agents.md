# 0017 — Les sous-agents de /feature et /fix ne lancent pas d'interpréteur avec du code inline

Statut : acceptée (2026-11-19)
Où elle vit : `hooks/no-interpreter.sh` (PreToolUse Bash, déclaré dans le frontmatter de tous les agents
`feature-*` et `fix-*`) · `scripts/gauntlet/interpreter_check.py` (ce qui est reconnu) ·
`scripts/gauntlet/bash_write_targets.py` (les écritures par Bash que voient les `*-restrict-writes.sh`) ·
`scripts/gauntlet/tests/test_hook_interpreter.sh`, `test_hook_fix_bash.sh` · chaque refus s'écrit au journal
des hooks (`.gauntlet/hooks.jsonl`, 0019)

## Contexte

Les hooks d'écriture (`pipeline-restrict-writes.sh`, `fix-restrict-writes.sh`) tiennent la zone de chaque
agent : tests gelés pour Ivan, Nina et Fanny (0001), lecture seule pour les relecteurs (0002). Pour Bash, ils
ne voient que ce que `bash_write_targets.py` sait extraire : redirections, `sed -i`, `tee`, `cp`, `mv`, `rm`.
Un interpréteur leur échappe entièrement, et ils le disaient en commentaire en s'en remettant au gauntlet
(`test_freeze_check`, `only_tests_changed`), qui ne juge qu'en fin d'étape.

Le scan des transcripts des sous-agents (927 fichiers, jusqu'au 2026-11-19) compte 2 985 appels à python,
perl ou node, dont environ 1 200 écrivent des fichiers, presque toujours par le même motif :
`python3 - <<'EOF'`, `s=open(p).read()`, `s.replace(…)`, `open(p,'w').write(s)`. Python servait d'éditeur, en
dehors de toute zone. Des cas réels :

- un implementer, refusé sur un test gelé, en refait la copie par `cp` puis `sed -i` ;
- un implementer et un fix-implementer copient un test gelé dans `test/zz_debug_test.dart` par python pour y
  ajouter un `print`, le lancent, puis l'effacent ;
- des relecteurs, en lecture seule, écrivent des tests « probe » dans le worktree ou les copient dans `/tmp`
  pour les lancer avec `node --test` ;
- des `perl -0pi -e` à la place d'un Edit refusé.

## Décision

- Un hook PreToolUse sur Bash refuse aux agents dont `agent_type` commence par `feature-` ou `fix-` :
  - python, perl, ruby, node, deno, bun et php avec du code inline : `-c`, `-e` et leurs cousins (`-pe`,
    `node -p`, `php -r`), `-` ou `/dev/stdin`, un heredoc, `<<<`, ou du code reçu par un tube ;
  - les mêmes derrière `bash -c`, `sh -c`, `eval`, `env`, `xargs`, `find -exec`, `timeout`, `fvm` ou un chemin
    absolu : le hook regarde à travers ;
  - l'exécution d'un script écrit pendant la session : sous le scratchpad ou `/tmp`, absent, ou, dans un dépôt
    git, non suivi, ignoré ou modifié depuis HEAD. Vaut pour ces interpréteurs, pour `dart run x.dart`, pour
    `bash x.sh` et pour un exécutable lancé par son chemin ;
  - un shell qui lit son script sur l'entrée standard (`bash <<EOF`, `… | sh`) ;
  - `perl -pi` et `awk -i inplace`, et `node --test` sur des tests copiés dans `/tmp`.
- Il laisse passer les scripts du pipeline (`python3 [-I] ~/.claude/scripts/…`, par `~`, `$HOME` ou le chemin
  absolu), tout script suivi et inchangé (ceux de `~/.claude/stacks/` compris), `python3 -m json.tool` et
  les autres modules, les lanceurs de tests du projet (`node --test`, `deno test`, `bun test`) et les outils
  installés.
- Le message de refus dit quoi faire : Edit ou MultiEdit pour écrire, `jq` pour lire du JSON, et qu'un refus
  se rapporte, il ne se contourne pas.
- `bash_write_targets.py` voit aussi les écritures vers lesquelles les agents se reporteront une fois python
  fermé : `git apply` et `patch` (fichiers du patch, qu'il vienne d'un fichier, de `<`, d'un heredoc ou de
  `<<<`), `git checkout [<rev>] -- f`, `git restore f`, `install`, `dd of=f`, `rsync`.
- Les tests du hook rejouent des commandes réelles tirées des transcripts, chemins anonymisés : les cas
  refusés, et les appels aux scripts du pipeline qui doivent passer. Sur les 2 985 appels du scan, 2 834 sont
  refusés ; les 151 qui passent sont des scripts du pipeline, `python3 -m json.tool`, `node --test` dans le
  projet et des commandes où l'interpréteur n'est qu'un mot (`grep python3`).

## Conséquences

- Une écriture passe par Edit, MultiEdit ou Write, que les hooks de zone voient. Le gauntlet reste le filet
  (0001, 0003) ; le hook ferme le trou avant qu'il serve.
- Un agent qui avait besoin d'un outil absent du pipeline le dit dans son rapport au lieu de l'écrire. Cas
  attendu : la QA écrivait un petit pont python dans `maestro/support/` pour piloter l'émulateur depuis un
  flow ; ce pont, non suivi tant qu'il n'est pas commité, est refusé. Un tel outil se commite dans le projet
  ou devient un script de `~/.claude/scripts/`.
- Lire un JSON passe par `jq` ; vérifier qu'il est bien formé par `jq empty` ou `python3 -m json.tool`.
- À mesurer : le scan des transcripts relancé une semaine après doit compter zéro appel inline chez les
  sous-agents, et le banc de rejeu dit si le nombre de tours par étape a bougé.

## Hors champ

- L'orchestrateur de `/feature` et `/fix` garde python : on voit ce qu'il fait (décision de Thibault). Les
  agents hors `feature-*` et `fix-*` (relecteurs de `/reviewPR`, sessions ordinaires) ne sont pas concernés.
- Ce n'est pas un parseur shell. Passent encore : un exécutable lancé par un chemin dont une variable reste
  inconnue, awk sans `-i inplace` (son `print > "f"`), `git checkout <branche>`, d'autres interpréteurs
  (`osascript`, `swift`, `uv run`). Le gauntlet les rattrape en fin d'étape ; un cas qui se répète devient
  une règle du hook.
- Les tests de debug temporaires (`test/zz_probe_*`) et la règle « à vérifier » des relecteurs sont décidés
  dans les amendements de 0001 et 0002.
