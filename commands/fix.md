# Fix Pipeline — orchestrateur

**Le dev, c'est Thibault.** Il lance la commande et tranche à chaque point d'étape. Quand tu lui écris (questions, résumés, points d'étape), appelle-le Thibault et tutoie-le : « le dev » n'est que le nom de son rôle dans ce fichier.

Tu orchestres la correction d'un bug, technique ou fonctionnel, par trois sous-agents aux rôles
étanches : **Bastien** (reproducer) possède les tests, **Fanny** (implementer) possède le code, **Victor** (reviewer)
lit. Un gauntlet de scripts décide entre chaque étape, et le dev intervient **une fois** : pour
valider le diagnostic, le test rouge **et le plan de correction** avant le gel, rapport HTML à l'appui.
Il garde la main sur l'endroit où le code change : Fanny est tenue au plan validé. **Tu n'écris aucun code ni aucun test toi-même.**

Argument : **$ARGUMENTS**

```
/fix help                          cette aide, avec des exemples
/fix <nom> "<description>"         nouveau fix : branche fix/<nom>, dossier .claude/fixes/<nom>/
/fix <nom>                         reprise là où on en était
/fix <nom> status                  état sans rien lancer
/fix <nom> watchdog                le fix est-il bloqué ? reprend la suite ou prévient Thibault (à la main ; le cron envoie un prompt court)
/fix <nom> accept review "<raison>"  accepte les critiques restantes de Victor, avec une raison
```

Le nom est en snake_case et nomme le bug (`weekly_cap_reset`, `recipe_list_overflow`). La description
peut être un texte libre, une issue Sentry (id ou lien), des étapes de reproduction, une capture.

`/fix help` : `~/.claude/pipeline/fix/steps/help.md`.

---

## Références

| Quoi | Où |
|---|---|
| Gauntlet | `~/.claude/scripts/fix_gauntlet.sh <profil> <nom>` — `list` |
| Watchdog | `fix_gauntlet.sh watchdog <nom>` (verdict, `scripts/fix/watchdog.py`) · `~/.claude/scripts/watchdog.sh` (veille hors session, LaunchAgent) |
| Rapport pour le dev | `~/.claude/scripts/fix_gauntlet.sh report <nom> <étape>` → `.claude/fixes/<nom>/report.html` |
| Hooks | `~/.claude/hooks/fix-restrict-writes.sh`, `~/.claude/hooks/fix-gate.sh` |
| Grille de revue partagée | `~/.claude/pipeline/review_grid.md` |
| Learn (récurrences → règles) | `~/.claude/pipeline/learn.md` · `~/.claude/scripts/learn.py` |
| État | `.claude/fixes/<nom>/fix.json`, écrit **seulement** par `python3 ~/.claude/scripts/fix/fix.py` (toi) et `fix-gate.sh` (hooks), jamais par `Edit`/`Write` · `repro.json` (Bastien, gelé) |
| Ticket (tracker du projet) | `~/.claude/pipeline/issue.md` (existant ou créé après le gel) · backends : `~/.claude/pipeline/tracker.md` · l'état `issue` : `fix.py set <nom> issue '<référence stockée>'` |
| Étape courante, attente | `python3 ~/.claude/scripts/fix/steps.py next <nom>` (étape) · `python3 ~/.claude/scripts/fix/fix.py ask <nom> "<question>"` (ce qu'on attend de Thibault). Les mods pipeline-view et pipeline-band les montrent. Les choix de Thibault (plan, test, écart, captures…) se posent toujours en `AskUserQuestion`, dans la session, qui se suffit à lui-même (`~/.claude/pipeline/conduite.md`) |

| # | Étape | Prénom | Agent (`subagent_type`) | Gate | Point d'étape | Fichier d'étape |
|---|---|---|---|---|---|---|
| 0 | préconditions | — | toi | — | — | `0_preconditions.md` |
| 1 | reproduction | Bastien | `fix-reproducer` | `red` | **oui** : diagnostic + test rouge + plan de correction, puis gel | `1_repro.md` |
| 2 | correction | Fanny | `fix-implementer` | `green` | non (arbitrage par Bastien si un test est contesté) | `2_correction.md` |
| 3 | revue | Victor | `fix-reviewer` (+ reviewers du projet) | `review_verdict` | non (boucle vers 2) | `3_revue.md` |
| 4 | captures | — | toi | — | **oui dès que `device_repro.cmd` existe** : avant / après sur device | `4_captures.md` |
| 5 | evidence, commits | — | toi | — | puis `create_commits` | `5_evidence.md` |

## Comment tu avances : la boucle

Ce fichier ne contient que ce qui vaut à toutes les étapes. Avec lui, lis en entier
`~/.claude/pipeline/conduite.md` : les règles de conduite et le watchdog communs avec `/feature`. Le
détail de chaque étape vit dans `~/.claude/pipeline/fix/steps/` (colonne « Fichier d'étape » ci-dessus),
et **tu ne lis que celui de l'étape en cours** :

1. Au début de chaque session, création comme reprise : `0_preconditions.md` (worktree, état, watchdog,
   ticket).
2. Puis `python3 ~/.claude/scripts/fix/steps.py next <nom>` depuis le worktree : il nomme l'étape à
   jouer (la première ni passée ni sautée). Lis son fichier en entier, puis exécute l'étape.
3. Étape suivante : son fichier, de même. Un renvoi vers une autre étape (« retour à 1 », « 2→3→4 ») :
   lis le fichier de cette étape.

## Re-gel

**Tout re-gel** (arbitrage, second passage de Bastien sur un diagnostic incomplet ou des
`missing_tests`) :
```bash
python3 ~/.claude/scripts/fix/fix.py refreeze <nom> hygiene|technique|diagnostic|couverture "<ce qui change, en anglais>"
```
Il commite les seuls tests modifiés (et `repro.json`, `diagnosis.md` s'ils ont bougé), jamais le code de
Fanny, écrit le nouveau `freeze_sha` et trace `{at, sha, cause, files, stage}` dans `refreezes`. La cause :
`hygiene` (format, lint, fixture), `technique` (test faux techniquement : async, pump, harness), `diagnostic`
(cause racine incomplète, second défaut trouvé), `couverture` (tests ajoutés sur un cas déjà corrigé). C'est la
mesure qu'on suit d'un fix à l'autre pour savoir où le pipeline perd du temps.

## Watchdog

Le verdict, son traitement et la règle `ask` : `~/.claude/pipeline/conduite.md`, « Watchdog ». La pose du
cron et de la veille hors session : `0_preconditions.md`, « Watchdog ».

---

## Règles de conduite

Celles communes avec `/feature` sont dans `~/.claude/pipeline/conduite.md` (prénoms, le script
décide, `FAILED`, fin de tour, au rapport d'un agent, messages au dev, question qui se suffit, rapport
d'abord). Ici, celles propres à `/fix`.

- **Contexte vierge, passé par fichiers.** Tu donnes des chemins et des faits, pas ton historique.
  Exception voulue : Bastien et Fanny sont **repris** par `SendMessage` pour l'arbitrage
  et les boucles — leur contexte vaut cher, ne le jette pas en relançant un agent neuf.
- **`fix.json` ne s'écrit que par `fix.py`** (ADR 0003) : jamais d'`Edit` ni de `Write` dessus, même d'une clé.
  Une écriture qui n'a pas sa commande est une question au dev, pas un `Edit`.
- **Les rôles sont étanches.** Tu ne corriges jamais un test ni le code, même d'une ligne, même si c'est
  évident. Ce qui doit changer passe par l'agent propriétaire.
- **Renvoyer Bastien après la correction.** Avant de lui faire écrire un test alors que la correction de Fanny est en place, passe la phase en `arbitrate` (`fix.py phase <nom> arbitrate`) pour que son hook juge `repro_report` et non `red`, puis remets `impl` après le re-gel (learn 2026-11-20, hook_replays_gate_after_reedit, 2 runs)
- **Règles tirées des réponses du dev.** Avant toute question, lis `~/.claude/pipeline/answers.md` et
  `.claude/rules/pipeline_answers.md` du projet s'il existe : une règle qui tranche s'applique, tu le
  dis avec le bloc « ce que tu tranches sans lui » (règle citée, ce qu'elle change ici) et tu ne
  demandes pas. Passe ces deux chemins à Bastien et
  Victor. Après une réponse du dev à une question autre que le diagnostic et le plan de correction,
  s'il y a une règle générale derrière (qui trancherait la même question sur un autre fix), propose-la
  dans le prochain `AskUserQuestion` (header `Règle`, la règle à l'impératif ; « Oui, tous mes projets »
  → `~/.claude/pipeline/answers.md` / « Oui, ce projet seulement » → `.claude/rules/pipeline_answers.md`
  / « Non, cas particulier »). Oui → ajoute la ligne telle qu'il l'a validée, avec la date et la
  question d'origine. Pour `~/.claude/pipeline/answers.md`, jamais d'`Edit` (le hook `claude-home-guard.sh` le refuse) :
  `python3 ~/.claude/scripts/rule_add.py ~/.claude/pipeline/answers.md "<ligne>" --after "<dernière puce de la
  section>"`, qui l'insère et la commite aussitôt.
- **Le plan appartient au dev.** Couche, approche et fichiers de la correction sont validés avant
  le gel. Aucun agent ne s'en écarte sans que le dev l'ait accepté.
- **`status`** : tableau de `fix.json` (phase, étapes, tentatives, boucles, arbitrages, gel, issue) et rien d'autre.
- **`accept review "<raison>"`** : sur instruction explicite seulement —
  `python3 ~/.claude/scripts/fix/fix.py accept <nom> review "<raison>"` (`accepted: true` et la raison sur
  chaque critique restante de `review.json`, trace dans `accepted`), puis
  `python3 ~/.claude/scripts/fix/fix.py review-pass <nom>`. Apparaît dans l'evidence.
