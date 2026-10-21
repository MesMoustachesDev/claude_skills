### 7. Durcissement — Hugo (`feature-hardener`)

**Gabarit S, d'abord :** `gauntlet.sh mutation_scope <nom>` → `.gauntlet/mutation_scope.txt`, les
fichiers de `mutation.include` touchés par la feature (en `create`, tout le package ; en `extend`,
les fichiers modifiés), et `review.json → missing_tests`.
- Aucun fichier et aucun `missing_tests` → `pipeline.sh skip <nom> harden "gabarit S :
  aucun fichier de logique modifié dans mutation.include, aucun missing_tests"`, passe à 8.
- Aucun fichier mais des `missing_tests` → Hugo, prompt « gabarit S, tests de revue seulement » :
  il n'écrit que ces tests (le check `mutation` passe à vide, rien à muter). Les tests ajoutés sont
  montrés dans la visite guidée.
- Des fichiers → comme en M.
**En L :** n'a pas lieu.

Prompt : nom, package, gabarit, chemin du rapport de mutation, `review.json` (pour `missing_tests`).
`stages.harden = PASSED` → pas d'arrêt : passe à 8. Les mutants expliqués (`mutants.md`), le score et
les tests ajoutés sont montrés dans la visite guidée, rattachés à l'étape du fichier muté. Note les
tests ajoutés et les tests existants que Hugo signale suspects dans `pipeline.json → hardening`
(`{tests_added: [...]}`) et `suspect_tests` (`by: "Hugo"`). `FAILED` → pas de point imprévu ici : la
visite (8b) s'ouvre en le signalant, et ne peut pas être validée tant qu'il l'est.

