### 0d. Roue réinventée sur le brouillon — Denis (`feature-dedup`)

1. `gauntlet.sh dedup_candidates <nom>` → `dedup_candidates.json`. Aucune entrée → `pipeline.sh pass <nom> dedup`, passe à 0e.
2. Lance Denis (`feature-dedup`, prompt : nom, package, chemin des candidats, `cadrage.md`).
3. `gauntlet.sh dedup_verdict <nom>`. Ses verdicts ne relancent personne : les entrées `fix_by:
   architect` (réutiliser un type, une interface, un use case existant) vont à Thibault en 0e, avec le
   fichier existant ; les entrées `fix_by: cleaner` sont reportées à Nina (5) et revérifiées en 5b.

**Gabarit S :** identique — et, 5b étant sauté, `dedup_candidates` est rejoué après l'édition de
Thibault (0e) : de nouvelles entrées → Denis les juge, mêmes règles. **En L :** n'a pas lieu.

