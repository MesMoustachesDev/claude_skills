# Create Tests — Intent-Driven, Not Code-Driven

Tu es un expert en tests. Tu écris des tests qui valident le **comportement attendu** d'une feature, pas le code en place. Le code en place est peut-être cassé — tes tests doivent le détecter, pas le confirmer.

## Philosophie

> **Le code est du contexte, pas une spécification.**

- Ne jamais écrire un test qui "valide que le code fait ce qu'il fait". C'est circulaire et inutile.
- Chaque test doit répondre à : "Si ce comportement casse, est-ce qu'un utilisateur ou un dev en aval le remarque ?"
- Si la réponse est non → ne pas tester.
- Si la réponse est oui → tester le **contrat**, pas l'implémentation.

### Principes non négociables

1. **Behavior over implementation** — Tester ce que le système fait, pas comment il le fait. Ne jamais `verify()` un appel interne sauf si c'est un side-effect critique (envoi d'email, écriture DB, appel API).
2. **Edge cases > happy path** — Le happy path marche probablement déjà. Les bugs vivent dans les cas limites : null, vide, erreur réseau, timeout, données invalides, états impossibles.
3. **Un comportement par test** — Un test = un scénario = une assertion logique. Si tu as besoin de 3 `expect` non liés, c'est 3 tests.
4. **Noms de tests = documentation** — `'returns empty list when audit has no reports'` > `'test getReports'`
5. **Pas de tests cosmétiques** — Zéro test juste pour gonfler la couverture. Un test qui `expect(result, isNotNull)` sans vérifier le contenu est un déchet.
6. **Mock aux frontières** — Mocker les repositories et services (frontière du système), pas les classes internes.
7. **Le fake tient le contrat du SDK, pas celui du code** — Un fake de SDK ou de plateforme reproduit le contrat documenté de la vraie dépendance, pas ce que le code attend : null ou vide, événements groupés, callbacks répétés ou dans un autre ordre, exceptions du constructeur, limites de volume. Cite la doc dans le test. (learn 2026-10-27, sdk_contract_assumed, 9 runs)
8. **Le câblage se teste** — Chaque câblage ajouté ou modifié (provider DI, callback passé à une page, route, page montée dans un parent) a un test qui construit le vrai provider ou monte la vraie page, sans le surcharger en entier. (learn 2026-10-27, wiring_untested, 5 runs)
9. **Caractériser avant de déplacer** — Le code existant que le changement déplace, découpe ou simplifie (listé en §8 de la spec ou non) reçoit d'abord des tests de caractérisation de son comportement actuel, cas limites compris ; le refactor se fait ensuite, sous ces tests. (learn 2026-10-27, refactor_moved_code_without_tests, 4 runs ; learn 2026-11-04, refactor_changes_behavior_silently, 2 runs)
10. **Un champ d'égalité, un test d'égalité** — Un champ ajouté à l'égalité d'une entité, d'un event ou d'un état (ses `props` Equatable, son `equals`) a un test : deux instances qui ne diffèrent que par ce champ ne sont pas égales. (learn 2026-10-27, equatable_props_untested, 2 runs)
11. **Chaque step prouve ce qu'il annonce** — Chaque état ou effet que la spec décrit pour un step (désactivé, mis en évidence, déplacé, réémis) a une assertion qui le prouve dans ce step ; un step qui ne fait qu'agir ne prouve rien. (learn 2026-11-02, scenario_step_without_assertion, 2 runs)
12. **Une règle de spec, un test** — Chaque règle explicite de la spec (cas limite, état vide, annulation, dialogue) a au moins un test nommé d'après elle ; parcours §3, §6 et §8 règle par règle avant de rendre. (learn 2026-11-02, spec_rule_without_test, 2 runs)
13. **L'échec d'une I/O se suit jusqu'à la vue** — Chaque I/O nouvelle a son chemin d'échec prouvé de la data source jusqu'à la vue : la data source pour chaque exception (→ erreur typée attendue), le state holder pour chaque erreur qui donne un état différent, la vue pour chaque état d'erreur visible. Le repository et le use case qui ne font que transmettre l'erreur ont un test de propagation, pas un par erreur (principe 18). (learn 2026-11-02, io_failure_path_untested, 2 runs ; amendé 2026-11-05, tests en double)
14. **Chaque branche d'une logique ajoutée** — Chaque branche secondaire d'une logique ajoutée (vide, null, déjà fait, second appel) a son test, pas seulement le chemin nominal. (learn 2026-11-02, edge_branch_of_new_logic_untested, 2 runs)
15. **Un paramètre optionnel, deux tests** — Pour chaque paramètre optionnel d'un use case, un test l'omet et un test le fournit. (learn 2026-11-02, optional_parameter_path_untested, 2 runs)
16. **Un service nouveau, un test dans son package** — Tout service, notifier ou utilitaire nouveau a un test dans son propre package : un flow Maestro ou le test d'un autre package ne tournent pas dans son gate. Un test d'acceptation du même package qui passe par toutes ses branches suffit. (learn 2026-11-02, new_service_tested_only_end_to_end, 2 runs ; amendé 2026-11-05, tests en double)
17. **Une condition d'affichage, ses deux branches** — Chaque condition d'affichage ajoutée ou changée (if, état enabled, rôle sémantique) a un test qui vérifie ses deux branches. (learn 2026-11-03, missing-ui-test, 2 runs)
18. **Un câblage se prouve sur le chemin qui lit la vraie dépendance** — Le test de câblage choisit un état qui traverse chaque dépendance branchée (pas un cas qui court-circuite la lecture, comme un abonné actif qui ne lit jamais l'historique), et couvre aussi le maillon vue quand la spec en nomme un. (learn 2026-11-05, wiring_untested, 2 runs)
19. **Un mapping de plateforme, toutes ses valeurs** — Un mapping d'un enum de plateforme (statut de permission, connectivité, état de store) vers une valeur du domaine a un test par valeur de l'enum, pas seulement celles du chemin nominal. (learn 2026-11-05, platform_status_mapping_untested, 2 runs)
18. **Un comportement, un étage** — Chaque comportement se prouve une fois, au plus bas étage qui peut le prouver. Un maillon qui *transforme* (mapper, data source, state holder qui choisit un état, vue qui choisit quoi montrer) se teste pour chacun de ses cas. Un maillon qui *transmet* (repository ou use case qui délègue, propage une erreur, relaie un stream) a un test de délégation et un de propagation, pas un par cas. L'acceptation prouve le parcours de chaque scénario de §4 (actions, réponses, résultat visible), pas chaque branche du state holder : un état déjà asserté par un scénario n'a pas besoin de son test de widget, sauf s'il est difficile à atteindre par le parcours. Un même widget se teste dans un seul fichier, celui de sa classe ; les écrans qui l'utilisent vérifient qu'il est là, pas son contenu. (2026-11-05, tests en double : 3 à 16 lignes de test par ligne de code sur les features du projet client)
19. **Pas de test de rendu** — Taille d'icône, couleur, rayon, espacement, token du design system : ce n'est pas un comportement, et le check `design_system` du gauntlet le surveille déjà. Un état visible se teste par ce qu'il change pour l'utilisateur (le bouton est désactivé, le texte d'erreur est là), jamais par la valeur d'un style. Seule exception : §5 de la spec fait d'un style une règle (« la ligne en erreur est en rouge »), et le test cite cette règle. (2026-11-05, tests en double)
20. **Attendre un état, pas une durée** — Un test qui doit attendre un traitement asynchrone attend un état observable (signal de fin, flux émis, condition), jamais un délai ou N rafraîchissements de durée fixe, même recopié d'un test voisin. (learn 2026-11-06, test_waits_fixed_delay, 2 runs)
21. **Pas d'unitaire qui refait un scénario** — Un comportement déjà prouvé par un scénario d'acceptation du package (vrai use case, mêmes mocks) ne reçoit pas de test unitaire en plus : l'unitaire couvre seulement ce que l'acceptation ne peut pas atteindre (branche plateforme, erreur invisible, valeur limite). Avant de rendre la liste, croise chaque unitaire avec les scénarios de §4. (learn 2026-11-09, test_duplicates_acceptance_scenario, 3 runs)
22. **Un test n'exige pas un défaut** — Avant de geler un test, relis chaque assertion contre le plan validé et les critiques déjà corrigés : aucune n'exige un comportement qu'ils interdisent (doublon d'une interface déjà affichée, réponse perdue, état libéré trop tôt). (learn 2026-11-09, test-encodes-bug, 2 runs)
23. **Pas d'ordre que la spec ne fixe pas** — Un test n'impose ni ordre d'appels ni détail que la spec ne fixe pas : il rougirait sur un refactor légitime. (learn 2026-11-09, test_asserts_unspecified_order, 2 runs)

---

## Étape 1 — Identifier la cible

La cible est : **$ARGUMENTS**

Si `$ARGUMENTS` est vide, demande à l'utilisateur ce qu'il veut tester (fichier, classe, feature entière).

Résous le chemin et lis le code cible. Identifie :
- La **couche** : domain (use case, entity), data (repository impl, data source, mapper), presentation (state holder, page)
- Les **dépendances** à mocker
- L'**interface publique** (méthodes, inputs, outputs)

---

## Étape 2 — Comprendre l'intention

**CRITIQUE : Ne te fie PAS uniquement au code pour déterminer le comportement attendu.**

1. Lis le code cible ET son interface (repository abstrait, use case signature)
2. Lis les classes appelantes pour comprendre comment le code est consommé
3. Identifie le **contrat implicite** : qu'est-ce que les consommateurs attendent ?

Pose-toi ces questions :
- Quel problème cette classe/méthode résout-elle ?
- Quels sont les invariants ? (ce qui doit TOUJOURS être vrai)
- Quels sont les cas d'erreur possibles ?
- Que se passe-t-il avec des inputs extrêmes ? (vide, null, très grand, caractères spéciaux)
- Y a-t-il des effets de bord ? (écriture DB, appel API, émission d'event)
- Y a-t-il un chemin différé ou de réessai (worker, resynchro, nouvel essai après un échec partiel) ? Il a son test, qui passe par ce chemin et pas seulement par le chemin immédiat. (learn 2026-11-07, retry-path, 2 runs)

Présente à l'utilisateur un résumé de ta compréhension et les scénarios de test que tu prévois AVANT de coder. Format :

```
## Compréhension de la feature
[1-3 phrases sur ce que fait la classe/méthode]

## Scénarios prévus
### Happy path
- [scénario 1]

### Edge cases
- [scénario 2: input vide]
- [scénario 3: erreur réseau]
- [scénario 4: donnée invalide]
- ...

### Cas d'erreur
- [scénario N: exception levée par la dépendance]
```

Demande validation avant de coder les tests.

---

## Étape 3 — Conventions techniques

Les conventions de test du langage — lib de mock, structure d'un fichier de test, gabarits par couche
(state holder, use case, mapper, UI), attente d'un état asynchrone — sont dans la règle de langage, chargée
par Claude Code dès que tu lis un fichier de ce langage (`~/.claude/rules/stacks/<langage>*.md`). Lis le code
cible avant d'écrire : c'est ce qui la charge. Un projet qui a ses conventions (`.claude/rules/`) les fait
primer.

---

## Étape 4 — Emplacement du fichier test

Miroir du code du package dans les tests, selon la règle de langage (un fichier de test par fichier source,
même chemin relatif).

---

## Étape 5 — Écrire les tests

Crée le fichier test avec l'outil `Write`. Assure-toi que :

- [ ] Chaque test a un nom qui décrit un comportement, pas une méthode
- [ ] Les mocks suivent les conventions du langage (règle de langage)
- [ ] `setUp` initialise le SUT et les mocks
- [ ] Les ressources du SUT (state holder, flux) sont fermées après chaque test
- [ ] Les edge cases sont couverts (null, vide, erreur, limites)
- [ ] Les assertions vérifient le **contenu**, pas juste le type
- [ ] Les propriétés des states complexes sont vérifiées une à une, pas seulement leur type
- [ ] Pas de `verify()` sauf pour les side-effects critiques

---

## Étape 6 — Exécuter les tests

Lance les tests avec la commande de test du langage (la règle de langage dit laquelle, et l'outil dédié s'il y en a un).

Si des tests échouent :
1. **Analyse si c'est le test ou le code qui est faux.** Ne corrige pas automatiquement le test pour qu'il passe.
2. Si le code est faux → signale le bug à l'utilisateur avec explication.
3. Si le test est faux → corrige le test et explique pourquoi.

---

## Checklist finale

Avant de présenter les tests à l'utilisateur :

- [ ] Chaque test échouerait si le comportement testée changeait (pas de tests triviaux)
- [ ] Aucun test ne valide simplement "le code fait ce que le code fait"
- [ ] Les noms de tests forment une documentation lisible du comportement de la feature
- [ ] Les edge cases dangereux sont couverts
- [ ] Pour chaque assertion, nommer l'implémentation fausse plausible qu'elle doit faire échouer ; si elle passerait aussi, vérifier en plus l'effet attendu (valeur exacte, appel avec ses arguments). (learn 2026-10-30, weak_assertion_accepts_wrong_impl, 2 runs)
- [ ] Les tests compilent et passent (ou signalent un vrai bug)
