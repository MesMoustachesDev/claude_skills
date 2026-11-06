# Grille de revue — partagée

Lue par `/reviewPR`, `feature-reviewer` et `fix-reviewer`. Une seule source : une règle ajoutée ici
s'applique aux trois. Les règles projet (`.claude/rules/pr_rules.md`, `CLAUDE.md`) priment.

**Projet sans `create_feature_rules.md`** (backend Node, scripts…) : « Architecture » se lit contre le
`CLAUDE.md` du projet et les fonctions voisines ; les items DS / l10n / barrel / state holder sont `na`.
La règle de langage chargée (`~/.claude/rules/stacks/<langage>*.md`) dit ce que ces items veulent dire
dans le langage du diff. Si le projet a des agents de revue spécialisés (`.claude/agents/*review*.md`), leurs invariants
font partie de la grille.

## Règles universelles

**Qualité du code**
- Logique incorrecte ou cas limites non gérés
- Une décision (garde, « jamais de chiffre inventé ») vérifiée sur le seul chemin nominal : vérifie-la sur chaque chemin et chaque valeur qui y mènent (learn 2026-11-02, decision_checked_on_one_path_only, 2 runs)
- Code mort ou commenté sans justification
- Duplication évitable (DRY)
- Complexité cyclomatique excessive (fonctions > 30 lignes qui gagneraient à être découpées)
- Magic numbers / strings sans constante nommée

**Sécurité**
- Données sensibles hardcodées (clés API, mots de passe, tokens)
- Injection potentielle (SQL, commandes shell, etc.)
- Inputs non validés / non sanitizés
- Permissions trop larges

**Performance**
- Requêtes ou opérations lourdes dans des boucles
- Allocations mémoire inutiles ou fréquentes
- Appels réseau bloquants sur le thread principal (mobile)

**Maintenabilité**
- Nommage ambigu ou trompeur
- Un nom en `-Manager`, `-Helper`, `-Handler`, `-Util` qui ne dit pas quel concept il porte : nomme le concept (article de Romain Rochegude, « Rethinking hexagonal architecture with Elegant Objects », 2026-11-03)
- Absence de documentation sur les choix non évidents
- Tests manquants pour de la logique métier critique
- Dépendances introduites sans justification

**Spécifique mobile (Flutter / Android / Kotlin / Wear OS)**
- Gestion du cycle de vie (leaks, états non sauvegardés)
- Recompositions/rebuilds inutiles (Compose / Flutter)
- Permissions non justifiées dans le manifest
- Absence de gestion offline ou d'état de chargement

## Grille de maintenabilité (jugement, pas mesure)

Pour chaque package touché, tranche explicitement `ok` / `ko` :

- **Architecture** : les couches de `create_feature_rules.md` sont respectées ; aucune logique métier
  dans un widget ; aucun `DataModel` en présentation ; aucun repository en présentation, `ErrorRepository`
  compris (le state holder appelle un use case, qui reporte l'erreur ; le check `deps` le bloque sur les lignes
  de la feature, la dette existante sort dans `debt_deps.txt`) ; les résultats sont dépliés dans le state holder,
  pas ailleurs ; aucun `try/catch` hors de la couche data (l'I/O est attrapée en data et rendue en
  type résultat, règle non négociable) ; ce qui a été mis dans `core`/`router`/`l10n` y a sa place.
- **Roue réinventée par la responsabilité** : ouvre `dedup_candidates.json`. Pour chaque paire
  (déclaration nouvelle ↔ candidate existante) : lis les deux corps et tranche — doublon (utiliser
  l'existant), à étendre (l'existant fait 80 %, on l'étend, on ne crée pas un jumeau), distinct. Pour
  chaque widget nouveau, parcours `design_catalog` **par rôle** (bouton, carte, état vide, bandeau,
  champ) : un composant du DS qui rend la même chose est un problème critique. Les scripts ont attrapé
  les doublons par nom et par corps ; toi tu attrapes `SearchBarTextField` qui refait
  `DesignTextField`.
- **Dépendances** : chaque inter-features est nécessaire (pourrait passer par `core` ?) ; chaque
  package hébergé ajouté est justifié et maintenu (le rapport `pub_health` donne la date de release) ;
  pas de doublon avec ce que `core` exporte (second client HTTP, second logger). Pour chaque package
  que `pub_health` signale, propose : alternative (vérifie-la sur le registre du langage), fichiers impactés
  (`grep -rl`), risque, verdict `replace | pin | watch`.
- **Design system et l10n** : au-delà des valeurs brutes (script), les états d'écran utilisent les
  composants d'état du DS ; les clés l10n sont nommées comme les voisines ; pas de concaténation de
  chaînes traduites.
- **Cohérence** : nommage, suffixes, verbes d'events, gestion d'erreur homogènes avec deux features
  voisines que tu ouvres (la feature de référence de `feature_pipeline.md`, et la plus proche).
- **Proportion** : la quantité de code est à la mesure du comportement. Pas de type, d'état, de mode
  ou de cas que ni le besoin ni un test n'exigent ; pas de widget géant (~300 lignes et plus) qui porte
  de la logique ; pas de couche qui recalcule ce que le domaine sait déjà ; pas d'abstraction à un seul
  usage sans raison écrite. Ce que les conventions imposent (couches de `create_feature_rules.md`, un
  use case par action même relais) n'est **pas** du surdimensionnement. Un `ko` dit ce qui est en
  trop, ce qui le remplacerait, et l'ordre de grandeur des lignes économisées.
- **Lisibilité à froid** : un point que toi, sans contexte, tu n'as compris qu'en lisant deux fois
  → finding. Le barrel se comprend sans ouvrir `src/`. Le README du package est encore vrai.
- **Tests** : pour chaque comportement ajouté dans `lib/`, un test nommé le prouve ; les assertions
  vérifient le contenu, pas le type ; pas de `verify()` d'un appel interne hors side-effect.
  Une interface du domaine doublée par un mock reconfiguré dans chaque fichier de test, alors qu'un fake
  (implémentation en mémoire, écrite une fois dans `test/`) suffirait → suggestion.
  Un test qui attend un délai fixe pour voir un résultat (délai codé en dur, N rafraîchissements de
  durée fixe, `sleep`, `waitForAnimationToEnd` sans condition dans Maestro) → `ko` : il attend un état
  (condition, flux émis, `extendedWaitUntil` ; les formes du langage sont dans sa règle), sinon il est lent ou instable.
- **Règles portées par les objets** : une règle qui ne dépend que de l'état d'une entité (validité, total,
  statut qui interdit une action) est une méthode de l'entité, pure et testée sans mock. Un state holder ou un
  use case qui lit les champs d'une entité pour décider à sa place → `ko`, avec la méthode qui la remplacerait.
  Le use case par action, même relais, reste la convention : le use case coordonne, l'entité décide.
  Question à te poser : faut-il connaître l'état interne de l'objet pour appliquer sa règle ? (article de Romain Rochegude, « Rethinking hexagonal architecture with Elegant Objects », 2026-11-03)
- **Transverse en décorateur** : cache, logs, retry, report d'erreur ou analytics recopiés dans trois
  méthodes ou plus d'un repository ou d'un use case → suggestion : un décorateur qui implémente la même
  interface et enveloppe l'autre, nommé par un adjectif (`CachedXRepository`, `LoggedXRepository`),
  assemblé dans les providers. (article de Romain Rochegude, « Rethinking hexagonal architecture with Elegant Objects », 2026-11-03)
