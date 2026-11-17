### 5. Nettoyage — Nina (`feature-cleaner`)

Prompt : nom, package, `last_clean.log` si présent, et `dedup.md` s'il porte des entrées
`fix_by: cleaner` reportées depuis 1d (« applique ces factorisations ; 5b les revérifie et bloque »).
Le gate `clean` porte le check `roles` (ADR 0016, non applicable sans `.claude/roles.md`) : Nina pose
`/// rôle: <mot>` sur chaque déclaration réutilisable de la feature, et ajoute au vocabulaire le mot
qu'aucun ne couvre. Son rapport les liste sous « Rôles ajoutés » : montre-les à Thibault au point
d'étape suivant (`git diff <merge-base> -- .claude/roles.md`), c'est lui qui garde le vocabulaire fermé.
`stages.clean = PASSED` → continue ; `FAILED` → même traitement qu'en 4.
**Gabarit S :** identique. **En L :** n'a pas lieu.

### 5b. Roue réinventée, second passage — Denis (`feature-dedup`)

Même mécanique qu'en 1d, sur le code implémenté (helpers, widgets, extensions apparus pendant 4 et 5).
Vert → `pipeline.sh pass <nom> dedup_clean`. Rouge → relance le **cleaner** avec `dedup.md`, puis 5b ;
`pipeline.sh loop <nom> dedup_clean` avant chaque relance (code 3 au-delà de 2 : point imprévu).

**Gabarit S : sautée** — `pipeline.sh skip <nom> dedup_clean "gabarit S : un seul
passage de Denis (1d)"`. Exception : si `dedup.json` porte des entrées `fix_by: cleaner` reportées
de 1d, 5b a lieu (c'est là qu'elles bloquent), mais seulement `gauntlet.sh dedup_verdict` après
Nina, sans relancer Denis ; rouge → Nina, comme en M. Le check `reinvented` du profil `clean`
reste actif. **En L :** n'a pas lieu.

