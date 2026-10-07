# Grille de revue — partagée

Lue par `/reviewPR`, `feature-reviewer` et `fix-reviewer`. Une seule source : une règle ajoutée ici
s'applique aux trois. Les règles projet (`.claude/rules/pr_rules.md`, `CLAUDE.md`) priment.

**Hors Flutter** (backend Node, scripts…) : « Architecture » se lit contre le `CLAUDE.md` du projet et
les fonctions voisines, pas contre `create_feature_rules.md` ; les items DS / l10n / barrel / BLoC sont
`na`. Si le projet a des agents de revue spécialisés (`.claude/agents/*review*.md`), leurs invariants
font partie de la grille.

## Règles universelles

**Qualité du code**
- Logique incorrecte ou cas limites non gérés
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
  dans un widget ; aucun `DataModel` en présentation ; les `Either` sont dépliés dans le BLoC, pas
  ailleurs ; aucun `try/catch` hors de `lib/src/data/` (l'I/O est attrapée en data et rendue en
  `Either<ErrorEntity, T>`, règle non négociable) ; ce qui a été mis dans `core`/`router`/`l10n` y a sa place.
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
  que `pub_health` signale, propose : alternative (vérifie-la sur pub.dev), fichiers impactés
  (`grep -rl`), risque, verdict `replace | pin | watch`.
- **Design system et l10n** : au-delà des valeurs brutes (script), les états d'écran utilisent les
  composants d'état du DS ; les clés l10n sont nommées comme les voisines ; pas de concaténation de
  chaînes traduites.
- **Cohérence** : nommage, suffixes, verbes d'events, gestion d'erreur homogènes avec deux features
  voisines que tu ouvres (la feature de référence de `feature_pipeline.md`, et la plus proche).
- **Lisibilité à froid** : un point que toi, sans contexte, tu n'as compris qu'en lisant deux fois
  → finding. Le barrel se comprend sans ouvrir `src/`. Le README du package est encore vrai.
- **Tests** : pour chaque comportement ajouté dans `lib/`, un test nommé le prouve ; les assertions
  vérifient le contenu, pas le type ; pas de `verify()` d'un appel interne hors side-effect.
