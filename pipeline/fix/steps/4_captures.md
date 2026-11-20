# /fix — étape 4 : captures, dès que `device_repro.cmd` existe

Pas de fix livré sans le parcours du signalement rejoué sur device après la correction : c'est la
seule preuve que le symptôme vu par l'utilisateur a disparu, les tests ne prouvent que la cause.
**Chaque fix a son simulateur iOS.** `device_red` et `device_green` ne sont dans aucun profil ni hook :
tu les lances toi-même (`fix_gauntlet.sh device_green <nom>`), jamais avant que la correction soit
verte. Ils tournent sur « `<ios.simulator_base>` · fix-<nom> », cloné du modèle par
`~/.claude/scripts/sim.sh ensure fix-<nom>` et passé à `device_repro.cmd` dans `$FIX_SIM_UDID` : pas de
go du dev, aucune autre session ne s'en sert. Le go du dev par créneau (`AskUserQuestion`) ne reste
que si le run utilise un simulateur partagé : pas de `ios.simulator_base`, `FIX_SIM_UDID` pointé sur le
modèle ou un autre appareil, ou un `device_repro.cmd` gelé qui cherche encore `iPhone … (Booted)`.
Modèle absent ou allumé : `sim.sh` dit comment le créer ou l'éteindre ; tu le montres au dev, tu ne
crées ni n'éteins le modèle toi-même.
`shots/green/` contient alors les captures après correction. Regarde-les
(`Read`) avant de les montrer — une capture qui ne montre pas l'état attendu est un défaut, pas un
succès. `fix_gauntlet.sh report <nom> ui` (captures red | green et correction vs plan), puis
lien cliquable vers `report.html`, et `SendUserFile` des paires avant/après, un appel, `display: render`, légende « avant | après ».
`AskUserQuestion` : « Valider » / « Défaut visible : … » (→ `python3 ~/.claude/scripts/fix/fix.py loop <nom> ui` ;
exit 3 au-delà de 2 : point imprévu ; sinon `SendMessage` à Fanny, puis 2→3→4). Validation →
`python3 ~/.claude/scripts/fix/fix.py gate <nom> ui`. Avant la question :
`python3 ~/.claude/scripts/fix/fix.py ask <nom> "Regarde les captures avant / après"`.
