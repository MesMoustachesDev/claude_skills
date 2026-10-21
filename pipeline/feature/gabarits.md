## Gabarits S / M / L

La même chaîne de 11 agents pour une bascule d'UI et pour un système d'import, c'est trop pour l'une
et trop peu découpé pour l'autre. Le gabarit, choisi à la fin du cadrage (0b) et validé par le dev
avec le reste du cadrage, rend le pipeline proportionnel. Il est écrit dans `pipeline.json → size`.

| Gabarit | Critères (au cadrage) | Ce qui change |
|---|---|---|
| **S** | ≤ ~8 scénarios estimés, aucun nouveau package (ni package de feature créé, ni dépendance pub.dev ajoutée), ≤ 2 décisions majeures estimées | spec ≤ 15 Ko ; une passe de Camille ; pas de 5b ; Hugo seulement si `mutation.include` contient des fichiers de logique modifiés (ou si Romain signale des `missing_tests`) ; QA sur une plateforme |
| **M** | ni S ni L | le pipeline décrit dans ce fichier, sans allègement (spec ≤ 40 Ko, `loops.spec` max 2) |
| **L** | > 5 décisions majeures estimées, ou la feature touche plusieurs packages | découpage obligatoire en sous-features avant toute spec ; chacune repasse par `/feature` en S ou en M |

Dans le doute entre deux gabarits, prends le plus lourd : un S sous-dimensionné rate des cas, un M
de trop ne coûte que du temps.

**Ce que le gabarit ne touche jamais** : les gates d'intégrité — compilation (`analyze`,
`build_runner`), suite verte (`test`, `green`), gel (`test_freeze_check`, re-gels), dépendances
(`deps`, `deps_features`), `error_handling` — et les profils du gauntlet (`profiles.sh` ne lit pas
le gabarit). Les six points d'étape (cadrage, contrats de Thibault, spec, tests et gel, suggestions,
visite guidée) restent en S. Le gabarit allège le jugement (critique, dedup, mutation, QA), jamais la
preuve ni la propriété du code.

**Lu à chaque étape.** Avant de lancer une étape, relis `pipeline.json → size` (une reprise peut
arriver après un reclassement). Une étape que le gabarit saute n'est pas absente : écris
`stages.<étape> = {"status": "SKIPPED", "at": "<iso>", "reason": "gabarit S : <pourquoi>"}`. La
reprise, `status`, le rapport HTML et l'evidence la montrent avec sa raison. Une étape `SKIPPED`
n'est jamais rejouée à la reprise, sauf reclassement.

**Reclassement.** S → M dès qu'un critère de S est dépassé : plus de 2 commentaires
`DÉCISION (Thibault)` dans le brouillon d'Arthur (mesuré en 0e), plus de 8 scénarios en §4, un
package ou une dépendance ajoutés en §8 (mesurés au point d'étape « spec »). Dis-le au dev en une ligne, avec
la mesure, et `AskUserQuestion` « Passer en M (Recommandé) » / « Rester en S : <raison> », dans le
même appel que la question de l'arrêt en cours. En M, une étape déjà `SKIPPED` en S est rejouée avant d'aller plus loin. M → L : plus
de 5 `DÉCISION (Thibault)` dans le brouillon (mesuré en 0e, avant qu'il édite), ou un imprévu après
la spec : le dev décide (découper ou continuer en M) ; ce que deviennent les contrats déjà commités
est décrit en 0e. Chaque reclassement va dans
`pipeline.json → size_changes` (`{at, from, to, reason}`) et dans l'evidence.

