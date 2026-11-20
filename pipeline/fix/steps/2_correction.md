# /fix — étape 2 : correction, Fanny (`fix-implementer`)

Prompt : `Racine : <worktree>` en première ligne (voir l'étape 1), nom, `diagnosis.md`, `repro.json`, `.gauntlet/last_red.log`, règles projet. Note son `agentId` :
`python3 ~/.claude/scripts/fix/fix.py agent <nom> implementer <agentId>`.

Au rapport de Fanny, dans le même tour : `python3 ~/.claude/scripts/fix/fix.py after <nom> green`, puis :
- **Écart au plan** dans le rapport → **point imprévu** : `fix_gauntlet.sh report <nom> repro`,
  `python3 ~/.claude/scripts/fix/fix.py ask <nom> "Écart au plan de Fanny à trancher"`, puis `AskUserQuestion` « Accepter l'écart » / « Tenir le plan : … ». Accepté →
  `python3 ~/.claude/scripts/fix/fix.py deviation <nom> "<raison>" <fichiers…>` (Victor le lit ; `repro.json`
  reste gelé) et `SendMessage` à Fanny « écart accepté, continue ». Refusé → `SendMessage` avec la
  consigne du dev.
- **Contestation de test** dans le rapport → **arbitrage**, quel que soit le gate :
  1. `python3 ~/.claude/scripts/fix/fix.py arbitrate <nom> open "<test>" "<contestation de Fanny>"` : phase
     `arbitrate`, contestation tracée, `loops.arbitrate` compté. Exit 3 (plus de 2 arbitrages) → point imprévu
     avec les deux positions, sans `SendMessage`.
  2. `SendMessage` à Bastien : la contestation telle quelle, et « tranche : test juste ou test faux ».
  3. Verdict **test juste** → `python3 ~/.claude/scripts/fix/fix.py arbitrate <nom> close juste`, puis
     `SendMessage` à Fanny avec l'explication de Bastien.
     Verdict **test corrigé** → montre le diff du test au dev (`git diff <freeze_sha> -- <test_files>`)
     et `AskUserQuestion` « Valider la correction du test » / « Refuser ». Validé →
     `python3 ~/.claude/scripts/fix/fix.py refreeze <nom> <cause> "<ce qui change, en anglais>"` (causes
     `fix.md`, « Re-gel »), puis `python3 ~/.claude/scripts/fix/fix.py arbitrate <nom> close corrige`, et `SendMessage` à
     Fanny : « le test a été corrigé, reprends ». Refusé → `SendMessage` à Bastien avec la raison.
- `stages.green` `FAILED` → point imprévu : rapport, 40 dernières lignes de `last_green.log`,
  options (consigne à Fanny / revoir le diagnostic → retour à 1 avec Bastien).
- `stages.green` `PASSED` → étape 3.
