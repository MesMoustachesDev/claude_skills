### 4. Trois relectures en parallèle

Lance **dans un seul message, trois appels `Agent`** (ils tournent en même temps, en arrière-plan) :
`review-architect` (Alice), `review-code` (Corentin), `review-qa` (Maëlle). Avant l'envoi,
`review.sh agent <slug> archi running`, puis `code`, puis `qa`.

**Maëlle est sautée** (pas d'appel, `review.sh agent <slug> qa skipped "<raison>"`) seulement si
Thibault a passé `--no-qa` ou s'il n'y a pas de worktree. Un device indisponible ou une MR sans rien de
visible ne la sautent pas : elle prouve alors par les tests existants, ou par des tests jetables
(`agents/review-qa.md`). Dis-lui dans son prompt ce que `context.md` promet de visible.

Chaque prompt tient en 10 lignes, avec des chemins et des faits, jamais ton historique :
- le slug, le dossier de la revue, le worktree, la source, la cible, le merge-base
  (`git -C <worktree> merge-base HEAD <remote>/<cible>`) ;
- `context.md`, le rapport du gauntlet (`review.sh next` le donne), le graphe de la PR s'il existe ;
- les règles projet qui existent (chemins notés dans `context.md`) ;
- les décisions du préflight qui le concernent (`review.sh next` les affiche) : « QA sans device,
  décidé par Thibault », « pas de graphe : lis les consommateurs à la main », « `reinvented` ne
  tournera pas : juge les doublons à la lecture » ;
- « écris `findings_<rôle>.json` au format de `~/.claude/pipeline/review/findings_format.md`, puis
  rends ton rapport en trois lignes ».

**Pendant qu'ils tournent**, n'en fais pas le travail. `review.sh say <slug> "Relecture en cours :
Alice, Corentin, Maëlle"` puis « Rafraîchir » : Thibault voit l'avancement dans le cockpit. Les
notifications arrivent seules ; ne les sonde pas.

**À chaque retour** : `review.sh agent <slug> <rôle> done "<sa première ligne de rapport>"` (ou
`skipped` pour Maëlle si son fichier dit `"skipped"`, avec la raison). Le script repasse un `done` en
`failed` si le fichier manque. Un agent en échec (`failed`, erreur, fichier absent) : relance-le une
fois avec la même consigne ; au second échec, `review.sh agent <slug> <rôle> failed "<raison>"` et le
briefing le dira. L'étape est finie quand les trois sont `done`, `skipped` ou `failed`.

Un agent rapporte un manque **que le préflight n'a pas tranché** (build qui échoue, check qui crashe) :
point imprévu, tout de suite — dis à Thibault ce que ça empêche et propose de corriger puis relancer
cet agent, ou de continuer sans ; ne le garde pas pour le briefing.
