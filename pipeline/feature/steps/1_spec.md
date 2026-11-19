### 1. Scénarios — Sophie (`feature-specifier`)

**Les scénarios avant les contrats (ADR 0015).** Les Given/When/Then posent les questions produit en
français ; les contrats d'Arthur (1c) puis de Thibault (1e) en sortent. Aucun contrat n'existe encore.

Prompt de lancement : nom, « mode scénarios », `cadrage.md` validé (« périmètre, comportements et
séquences figés : ne les rediscute pas »), description brute (ou « aucune, à découvrir »), l'issue
GitLab existante entre `<issue>` s'il y en a une (`issue.md`, partie A), racine, chemin de sortie, le
**gabarit** et son plafond de taille (« gabarit S : spec ≤ 15 Ko » / « gabarit M : spec ≤ 40 Ko »), le
package et les dépendances validés au cadrage.

Sophie écrit à partir du cadrage et du code existant : les scénarios Gherkin de §4 (un par comportement
C<n>, plus les états génériques), §6 (les données **telles que le produit les voit** : champs, règles,
bornes, sans type ni classe à inventer), §7 (chaque erreur avec le scénario qui la prouve), §8, et §9
(package et dépendances, statut `validée`, tranchés au cadrage ; une ligne `proposée` seulement pour une
dépendance découverte en écrivant). **§5 reste vide** : « *Après les contrats (1f).* ». Les clés que §4
cite (`'<préfixe>_x'`) sont des propositions : Arthur les posera dans le fichier de clés en 1c. Un
scénario qui demande un choix produit que le cadrage n'a pas tranché (« que renvoie le service quand… »)
n'est pas tranché par Sophie : elle l'écrit tel qu'elle le propose et le liste dans son rapport sous
« Questions pour Thibault », avec le C<n> et l'alternative.
`archi.json` ne contient que `sequences` : chaque C<n> relié à son scénario de §4.
Sophie revient quand `spec_lint` est vert, **phase scénarios** (sans `human_gates.contracts`, le gauntlet
ne vérifie ni clés ni symboles : ils n'existent pas encore ; restent le scénario de chaque erreur §7,
`archi.json` ↔ §4 et le plafond).

**Feature commencée avant l'ADR 0015** (`human_gates.contracts` déjà posé : Thibault a écrit ses contrats
dans l'ancien ordre) : prompt en « mode complet », avec `contracts.sha` et `contracts.files` (« écrits par
Thibault : la spec les décrit, elle ne les change pas ») ; Sophie écrit aussi §5 comme en 1f, et
`spec_lint` joue complet. L'étape 1f sera sautée (`pipeline.sh next` le sait).

**Gabarit S :** plafond 15 Ko au lieu de 40. **En L :** l'étape n'a pas lieu (découpée en 0b).

### 1b. Critique — Camille (`feature-spec-critic`)

Lance Camille (`feature-spec-critic`, prompt : nom, « mode scénarios », gabarit et plafond de taille,
`spec.md`, `archi.json`, `cadrage.md`, `create_feature_rules.md`, template de spec ; feature commencée
avant l'ADR 0015 : « mode complet », plus `contracts.sha` et `contracts.files`). Puis `gauntlet.sh spec_review_verdict <nom>` :
- rouge avec des bloquants `owner: "spec"` → relance le **specifier** avec ceux-là (« mode correction :
  corrige ces points, aligne les autres lignes qui disent la même chose, sans réécrire ce qui n'est pas
  cité »), puis 1b à nouveau ;
- rouge avec **seulement** des bloquants `owner: "thibault"` (un choix produit, ou en mode complet un
  contrat à changer) → personne n'est relancé : passe au point d'étape « scénarios », où Thibault tranche
  chacun. Le verdict reste rouge tant
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
le dev est le relecteur. Les bloquants encore ouverts sont listés au point d'étape « scénarios » ; le dev tranche
ou accepte (`accept`). Si Camille note « la feature est peut-être à découper » ou que la spec dépasse
un critère de S : reclassement (voir « Gabarits »). **En L :** l'étape n'a pas lieu.

Vert → **Point d'étape « scénarios ».** `gauntlet.sh report <nom> spec`, cité par un lien cliquable vers `report.html` : les scénarios avec leur phrase en français, la séquence du cadrage
de chacun, §6, §7, §9, la spec. Si la section « Séquences » porte le badge « incohérence(s) » (un C<n>
sans scénario, un titre absent de §4), relance Sophie avec la liste, sans montrer le rapport, puis 1b ;
ce compteur partage `loops.spec`.

**Thibault juge le comportement, pas encore la forme** : c'est le moment des questions produit (ce qui
s'affiche, ce qui est gardé, ce qui part en erreur), pas des signatures. En 10 lignes max : objectif,
périmètre, questions de Sophie, notes non bloquantes de Camille. Puis **ce qui sera testé** : le nombre
total de scénarios de §4, puis une ligne par C<n> (« C2 → <titre §4> — <phrase fr> »), groupée
« Nominal : », « Limite : », « Erreur : », et les scénarios de §4 hors cadrage (états génériques) en
une ligne.

Un seul `AskUserQuestion` : « Valider les scénarios » / « Demander des modifications » (texte libre →
relance Sophie avec le retour, puis 1b), plus, dans le même appel :
- une question par « Question pour Thibault » de Sophie et par bloquant `owner: "thibault"` de Camille :
  la proposition de Sophie « (Recommandé) », l'alternative, « Autre (je précise) ». Un choix autre que
  la proposition relance Sophie (un seul envoi pour toutes les réponses). Chaque bloquant de Camille
  ainsi tranché reçoit `"accepted": true` et la raison ; `spec_review_verdict` doit être vert avant la
  validation. En **mode complet** (feature commencée avant l'ADR 0015), un bloquant qui demande de
  changer un contrat se tranche comme en 1f ;
- une question par ligne de §9 encore `proposée` (une dépendance découverte) : la proposition
  « (Recommandé) » avec sa raison, l'alternative avec ce qu'elle change ; précédée dans ton message
  de ce qui existe aujourd'hui (`<manifeste>:ligne`, l'usage dans le repo) ;
- la question de reclassement si un critère de S est dépassé.
Validation → la colonne Statut des lignes tranchées passe à `validée` ou `modifiée`,
`pipeline.sh gate <nom> spec`, `pipeline.sh pass <nom> spec`, et « brouillon » devient « scénarios
validés le <date> » dans l'en-tête de la spec (« validée le <date> » en mode complet). Suite : 1c ; en
mode complet, le ticket de 1g (`1f_spec_contracts.md`), puis l'étape que donne `pipeline.sh next`.
