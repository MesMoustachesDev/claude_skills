### 1. Spec — Sophie (`feature-specifier`)

Prompt de lancement : nom, `cadrage.md` validé (« périmètre, comportements et séquences figés : ne les
rediscute pas »), `contracts.sha` et `contracts.files` (« écrits par Thibault : la spec les décrit,
elle ne les change pas »), description brute (ou « aucune, à découvrir »), l'issue GitLab existante
entre `<issue>` s'il y en a une (`issue.md`, partie A), racine, chemin de sortie, le **gabarit** et son
plafond de taille (« gabarit S : spec ≤ 15 Ko » / « gabarit M : spec ≤ 40 Ko »), le package et les
dépendances validés au cadrage.

Sophie écrit à partir des contrats édités : les scénarios Gherkin (un par comportement C<n>, plus les
états génériques), les erreurs, les données, §8. §5 renvoie aux contrats de Thibault par **symbole**
(`Classe.methode`, avec le fichier) au lieu de recopier les signatures : un symbole survit aux
éditions, un numéro de ligne non. §9 ne garde que ce que les contrats ne montrent pas : package et
dépendances (statut `validée`, tranchés au cadrage), plus une ligne `proposée` seulement pour une
dépendance découverte en écrivant la spec. Un contrat qui ne permet pas un scénario du cadrage (erreur
sans state, donnée absente d'une entité) n'est pas corrigé par Sophie : elle le liste dans son rapport
sous « Contrats à revoir par Thibault », avec le fichier et le symbole.
`archi.json` ne contient que `sequences` : chaque C<n> relié à son scénario de §4.

**Gabarit S :** plafond 15 Ko au lieu de 40. **En L :** l'étape n'a pas lieu (découpée en 0b).

### 1b. Critique — Camille (`feature-spec-critic`)

Lance Camille (`feature-spec-critic`, prompt : nom, gabarit et plafond de taille, `spec.md`,
`archi.json`, `cadrage.md`, `contracts.sha` et `contracts.files`, `create_feature_rules.md`, template
de spec). Puis `gauntlet.sh spec_review_verdict <nom>` :
- rouge avec des bloquants `owner: "spec"` → relance le **specifier** avec ceux-là (« corrige ces
  points, sans réécrire ce qui n'est pas cité »), puis 1b à nouveau ;
- rouge avec **seulement** des bloquants `owner: "thibault"` (un contrat à changer) → personne n'est
  relancé : passe au point d'étape « spec », où Thibault tranche chacun. Le verdict reste rouge tant
  qu'un seul n'est pas tranché.
Le rapport de Sophie liste une « Dette existante (hors feature) » → ajoute chaque ligne à
`pipeline.json → debt` (`{source: "spec", file, issue}`) : elle n'entre ni dans §9 ni dans le périmètre.

**Critique ciblée, plafond global.** Avant **chaque** relance de Sophie (bloquants de Camille,
modifications demandées par le dev), copie `spec.md` en `.claude/features/<nom>/.spec_prev.md` ; à son
retour, `diff -u .spec_prev.md spec.md > spec.diff`. Seule la première passe de Camille lit tout. Les
suivantes sont en **mode ciblé** (prompt : « mode ciblé », `spec.diff`, le `spec_review.json`
précédent) : elle ne relit que ce que le diff touche. `loops.spec` compte **toutes** les passes de
Camille après la première, quel qu'en soit le déclencheur : max 2 en M, soit 3 passes en tout.
Avant chaque passe de Camille après la première : `pipeline.sh loop <nom> spec` ; code 3 = plus de passe : tu montres les bloquants restants au dev avec la spec, et il tranche.
Regroupe ce qui relance Sophie : un seul envoi par arrêt, jamais une relance par réponse.

**Gabarit S : une seule passe de Camille** (`loops.spec` max 0). Ses bloquants relancent Sophie une
fois, sans nouvelle passe ; toute relance suivante non plus. À chaque point d'étape qui suit une
relance, montre `spec.diff` en plus du reste et rappelle en une ligne qu'aucune critique ne l'a relu :
le dev est le relecteur. Les bloquants encore ouverts sont listés au point d'étape « spec » ; le dev tranche
ou accepte (`accept`). Si Camille note « la feature est peut-être à découper » ou que la spec dépasse
un critère de S : reclassement (voir « Gabarits »). **En L :** l'étape n'a pas lieu.

Vert → **Point d'étape « spec ».** `gauntlet.sh report <nom> spec`, `SendUserFile` du
`report.html` (`display: render`) : les scénarios avec leur phrase en français, la séquence du cadrage
de chacun, §9, la spec. Si la section « Séquences » porte le badge « incohérence(s) » (un C<n> sans
scénario, un titre absent de §4), relance Sophie avec la liste, sans montrer le rapport, puis 1b ;
ce compteur partage `loops.spec`.

En 10 lignes max : objectif, périmètre, points signalés par Sophie, notes non bloquantes de Camille.
Puis **ce qui sera testé** : le nombre total de scénarios de §4, puis une ligne par C<n> (« C2 →
<titre §4> — <phrase fr> »), groupée « Nominal : », « Limite : », « Erreur : », et les scénarios de
§4 hors cadrage (états génériques) en une ligne. Puis, s'il y en a, **les contrats à revoir** : chacun
avec l'extrait de son fichier (`fichier:ligne`) et le scénario qu'il empêche.

Un seul `AskUserQuestion` : « Valider la spec » / « Demander des modifications » (texte libre →
relance Sophie avec le retour, puis 1b), plus, dans le même appel :
- une question par contrat à revoir (les « Contrats à revoir » de Sophie et les bloquants
  `owner: "thibault"` de Camille) : « Je modifie mon contrat » (tu réouvres le fichier, il édite, puis
  « Réédition plus tard » de 0e ; Sophie met §5 à jour) / « Le scénario s'adapte » (relance Sophie) /
  « Accepter : <raison> ». Chaque bloquant de Camille ainsi tranché reçoit `"accepted": true` et la
  raison (« contrat modifié : <sha> » ou celle du dev) ; `spec_review_verdict` doit être vert avant
  la validation ;
- une question par ligne de §9 encore `proposée` (une dépendance découverte) : la proposition
  « (Recommandé) » avec sa raison, l'alternative avec ce qu'elle change ; précédée dans ton message
  de ce qui existe aujourd'hui (`pubspec.yaml:ligne`, l'usage dans le repo) ;
- la question de reclassement si un critère de S est dépassé.
Validation → la colonne Statut des lignes tranchées passe à `validée` ou `modifiée`,
`pipeline.sh gate <nom> spec`, `pipeline.sh pass <nom> spec`, et « brouillon » devient « validée le
<date> » dans l'en-tête de la spec.

**1c. Issue GitLab.** `issue.status == "to_create"` → `~/.claude/pipeline/issue.md`, partie B, gabarit
feature (spec validée, contrats de Thibault). Sinon rien.

