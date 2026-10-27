### 2. Complétion du scaffold — Arthur (`feature-architect`, mode complétion)

Prompt : « mode complétion », nom, **mode**, `spec.md` validée, `contracts.sha` et `contracts.files`
(« fichiers de Thibault : n'y ajoute que des imports ou des `part` »), `create_feature_rules.md`,
`create_screen_rules.md` si la feature a une page (entrée de `pipeline.sh next`), package, valeur de
`brick`. Arthur pose ce qui découle mécaniquement des contrats et de la spec : modèles de données et
squelettes de mappers (§6), DI, route, clés l10n, events analytics, README, dépendances du pubspec
(§8), en stubs. Au retour, `stages.contracts` doit être `PASSED` (le hook l'a écrit). Un contrat de
Thibault qui ne tient pas (type absent, conflit de nom) → **point imprévu** : l'écart avec l'extrait
du fichier, « je corrige mon contrat » / « Arthur s'adapte sans toucher à mes signatures ».

Pas de point d'étape : la structure est celle que Thibault a écrite. Commit :
`git add -A <package> pubspec.yaml <writes.extra de la config> && git commit -m "feat(<nom>): scaffold"`.

**Gabarit S :** identique (gate `contracts` d'intégrité). **En L :** n'a pas lieu.

