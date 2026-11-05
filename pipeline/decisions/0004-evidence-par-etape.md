# 0004 — Chaque étape laisse ses preuves, l'evidence les rassemble

Statut : acceptée (2026-11-05, reprise du pipeline existant depuis 2026-09-25)
Où elle vit : `.claude/features/<nom>/` (artefacts par étape, `.gauntlet/last_<profil>.log`,
`history/`) · `scripts/gauntlet.sh report` · `pipeline/feature/steps/9_evidence.md` · `scripts/mr.py`

## Contexte

Thibault suit le pipeline par intermittence et ne relit pas tout le code. Sans traces, il ne peut
pas savoir ce qui a été vérifié, par qui, ni ce qui a été tranché sans lui. Une session qui reprend
une feature n'a pas non plus l'historique de la précédente.

## Décision

- Chaque étape écrit ses artefacts dans `.claude/features/<nom>/` : `cadrage.md`, `spec.md`,
  `archi.json`, `tests.md`, les `*_review.json`, `dedup.json`, `review.json`, `mutants.md`, `qa.md`,
  le log de chaque gate. `pipeline.sh loop` archive chaque verdict de boucle dans `history/`.
- Chaque point d'étape commence par un rapport régénéré (`gauntlet.sh report`), affiché dans le
  cockpit.
- À la fin, `evidence.md` rassemble tout : contrats, arbre du changement, visite guidée, étapes
  sautées, re-gels et leur cause, suggestions non appliquées, dette existante, acceptations,
  mutants, captures QA, impact graphify. C'est la page que Thibault lit à la place du code.
  La MR a sa propre description (`mr.md`).

## Conséquences

- Une feature se reprend depuis `pipeline.json` et ses artefacts, sans le contexte de la session.
- `learn.py` (9b) lit les verdicts archivés pour proposer des règles quand un problème revient.
- Le dossier de feature grossit, et il fait partie de ce qui se commite avec la feature.

## Hors champ

- Les transcripts des sessions et des agents : ils restent dans `~/.claude/projects/`, l'evidence
  ne les cite pas.
- En L (epic), la feature mère s'arrête après le cadrage et n'a pas d'evidence ; chaque
  sous-feature a la sienne.
