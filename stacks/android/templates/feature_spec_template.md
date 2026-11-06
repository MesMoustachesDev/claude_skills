# Spec — {feature_name}

<!--
  Ce document est écrit par l'agent feature-specifier APRÈS que le dev a écrit les contrats dans le
  code (commit « contracts (by Thibault) »), à partir du cadrage validé. Il décrit ces contrats sans
  les changer et écrit tout ce qu'ils ne disent pas. Tests, implémentation et QA en découlent.

  Règles d'écriture :
  - Les sections 4 à 8 sont CONSOMMÉES PAR DES AGENTS ET DES SCRIPTS. Elles doivent
    être précises, complètes et non ambiguës. Pas de "à définir", pas de "etc.".
  - Les contrats sont dans le code du dev : la section 5 y renvoie (fichier:ligne), sans recopier.
  - Les payloads sont des EXEMPLES RÉELS : valeurs plausibles, tous les champs, y compris
    les nullables et les cas limites.
  - La section 10 doit être VIDE à la validation. Une question ouverte = spec pas finie.
  - Supprimer les commentaires HTML une fois la section remplie.
  - Après une décision ou un renvoi tardif (contrat réédité, §9 changé), relire chaque section qui cite le code touché et ses appelants (grep), et la mettre à jour dans le même passage. (learn 2026-11-05, spec_stale_after_late_decision, 2 runs)
-->

| | |
|---|---|
| **Feature** | `{feature_name}` |
| **Package** | `{package_path}` |
| **Branche** | `feature/{feature_name}` |
| **Base** | `{base_branch}` |
| **Statut** | brouillon → validée le {date} |

---

## 1. Contexte & objectif

<!-- Un paragraphe. Le problème utilisateur, pas la solution. Pourquoi maintenant. -->

## 2. Périmètre

### Inclus

<!-- Liste fermée de ce que la feature fait. Chaque item doit se retrouver dans au moins un scénario de la section 4. -->

- 

### Exclu (explicitement)

<!-- Ce qu'on pourrait croire inclus et qui ne l'est pas. Ce qui est reporté à une itération suivante. -->

- 

## 3. Parcours & états d'écran

<!--
  Un bloc par écran ou par dialogue. Pour chaque écran, les quatre états sont obligatoires
  (Loading / Error / Empty / Loaded) — "N/A" avec justification s'il n'y en a pas.
  Wireframe ASCII pour le Loaded. Navigation entrante et sortante.
  Pour chaque résultat asynchrone, dis ce que voit l'utilisateur et ce qui se passe s'il agit avant son arrivée : durée de vie (instance, session), résultat tardif, résultat en échec. (learn 2026-11-04, spec_state_window_unspecified, 2 runs)
-->

### Écran : {ScreenName}

- **Route** : `/{route}` — paramètres : 
- **Entrée depuis** : 
- **Sortie vers** : 

| État | Rendu | Actions disponibles |
|---|---|---|
| Loading | | |
| Error | | |
| Empty | | |
| Loaded | voir wireframe | |

```
┌────────────────────────────────┐
│                                │
│                                │
└────────────────────────────────┘
```

## 4. Scénarios d'acceptation (Gherkin)

<!--
  LA PARTIE DURABLE. Recopiés tels quels dans src/test/resources/{feature_name}.feature ; chaque scénario
  devient un test Compose du même nom ({Name}AcceptanceTest.kt, Robolectric), puis un flow Maestro rejoué sur
  l'émulateur.

  - Un scénario = un comportement observable par l'utilisateur.
  - La phrase d'un scénario ne promet que ce que ses steps vérifient. Chaque step est déclarée, n'a
    qu'une lecture, Given pour un état, Then pour un résultat observable. (learn 2026-10-27, spec_scenario_overclaims + bdd_step_semantics)
  - Un scénario par comportement C<n> du cadrage, qui reprend chaque étape de sa séquence
    (action, réponse du serveur, résultat visible) ; archi.json → sequences les relie.
  - Couvrir chaque item de la section 2 "Inclus".
  - Couvrir chaque état de la section 3 (au moins un scénario Error, un Empty).
  - Les steps référencent les éléments par leur testTag de la section 5 ({Name}TestTags.kt),
    jamais par leur texte affiché (localisé, donc instable).
  - Formulation en anglais (le nom du test Compose), phrases courtes.
  - Pour chaque valeur attendue qui dépend d'un Given (préférences, état stocké, Background), écrire
    d'où elle vient d'après §6/§8 et le code existant (fichier:ligne), et vérifier qu'aucun scénario
    existant avec le même Given n'attend autre chose. (learn 2026-10-30, spec_scenarios_contradict_rules, 2 runs)
  - Avant d'écrire un step qui lit un tag, vérifier qu'il est déclaré dans un *TestTags.kt des
    contrats (y compris ceux des autres packages touchés) ; sinon la remonter comme contrat manquant,
    jamais l'inventer. (learn 2026-11-02, spec_reads_key_absent_from_contract, 2 runs)
  - Un comportement de bibliothèque cité par la spec (durée par défaut, erreur levée, crans, debug /
    release) est vérifié dans son code ou par exécution, avec la référence fichier:ligne ; sinon il est
    marqué « à vérifier ». (learn 2026-11-02, spec_unverified_library_behavior, 4 runs)
  - Déclarer chaque step Gherkin de §4 dans les notes du harnais : ce qu'elle pompe et ce que vaut
    la fixture. (learn 2026-11-02, spec_harness_steps_undeclared, 4 runs)
  - Un step qui tape ou lit un élément désigne une seule cible (tag et composable exact) ; si deux composables
    ou deux mises en page répondent, écrire un step par cible. (learn 2026-11-04, spec_step_ambiguous_target, 2 runs)
-->


```gherkin
Feature: {Feature name}

  Background:
    Given the app is running

  Scenario: 
    Given 
    When 
    Then 

  Scenario: shows an error when 
    Given 
    When 
    Then 

  Scenario: shows an empty state when 
    Given 
    When 
    Then 
```

## 5. Contrats

<!--
  Écrits par le dev dans le code (commit « contracts (by Thibault) » — {sha}). Cette section ne
  recopie aucune signature : une ligne par contrat, fichier:ligne, ce qu'il déclare, le C<n> qu'il
  sert. Le test-writer lit les fichiers, l'implementer les respecte. Un contrat qui empêche un
  comportement du cadrage n'est pas contourné ici : il va dans « Contrats à revoir par Thibault »
  du rapport du specifier.
  Pour chaque I/O appelée par un contrat (canal plateforme, plugin, moteur de rendu), vérifie que la
  signature rend un résultat (`Result<T>` ou le type d'erreur du projet) ; sinon, remonte un bloquant avant d'écrire la spec. (learn 2026-11-03, spec_error_path_without_contract, 2 runs)
  Chaque ligne de §5 cite un fichier de contracts.files et un comportement que sa signature permet. (learn 2026-11-04, spec_contradicts_contracts, 2 runs)
  Un composant que le harnais d'acceptation remplace par un mock (navigation, ViewModel appelant, service) a son propre test unitaire, nommé dans §5. (learn 2026-11-04, orchestrator_untested_because_mocked_by_consumers, 2 runs)  Pour chaque donnée que la spec lit, nomme la méthode du contrat qui la fournit ; s'il n'y en a pas, c'est un point §9 à trancher avant la spec. (learn 2026-11-04, contract_missing_input_for_mapping, 2 runs)
-->

| Contrat | Fichier:ligne | Déclare | Sert |
|---|---|---|---|
| `{Name}Repository.fetch` | `src/main/kotlin/{paquet}/domain/{Name}Repository.kt:5` | `suspend fun fetch(id: String): Result<{Name}>` | C1, C3 |
| `{Name}UiState` | `src/main/kotlin/{paquet}/ui/{Name}UiState.kt:4` | sealed : Loading, Loaded, Empty, Error | C1–C4 |
| `{Name}TestTags` | `src/main/kotlin/{paquet}/ui/{Name}TestTags.kt:1` | SCREEN, LOADING, ERROR, ERROR_RETRY, EMPTY | §4 |

<!--
  testTags ({Name}TestTags.kt) — trois consommateurs :
  - tests Compose  : onNodeWithTag({Name}TestTags.ERROR_RETRY)
  - flows Maestro  : tapOn: { id: "{feature_name}_error_retry" }  (resource-id)
  - implémentation : Modifier.testTag({Name}TestTags.ERROR_RETRY), et une fois sur la racine de l'écran
                     Modifier.semantics { testTagsAsResourceId = true }
  Sans testTagsAsResourceId, Maestro ne voit PAS les testTags.
  Chaque tag cité en §4 doit exister dans {Name}TestTags.
-->

## 6. Données

<!--
  Sans cette section, le test-writer ne peut pas tester les mappers ni les data sources.
  Un exemple RÉEL par payload, avec tous les champs. Les cas limites en plus (champ null,
  liste vide, chaîne vide) s'ils existent.
-->

### Payloads remote

**`{Name}DataModel`** — réponse de `{endpoint ou collection Appwrite}` :

```json
{
  "$id": "abc123",
  "name": "Exemple",
  "createdAt": "2026-09-25T10:00:00.000Z",
  "optionalField": null
}
```

Cas limites :

```json
{ "$id": "abc124", "name": "", "createdAt": "2026-09-25T10:00:00.000Z", "optionalField": null }
```

### Schéma local (Isar)

<!-- Si data source locale. Sinon "N/A". Les DAOs vivent dans features/local_storage/ (cf. create_feature_rules.md). -->

N/A

### Mapping

| Source (`DataModel`) | Cible (`Entity`) | Règle |
|---|---|---|
| `$id` | `id` | direct |
| `name` | `name` | `trim()` ; vide → conservé vide, jamais null |
| `createdAt` | `createdAt` | ISO 8601 → `DateTime.parse`, UTC |

## 7. Erreurs

<!-- Chaque ErrorEntity possible, d'où elle vient, et ce que l'UI en fait. C'est la spec des scénarios Error.
     Colonne Scénario : le C<n> qui la prouve, ou « hors scénario : <raison> » (spec_lint le vérifie). -->

| Erreur | Origine | Comportement UI | Retry possible | Scénario |
|---|---|---|---|---|
| `NetworkError` | remote data source | `{Name}Error` + message générique + bouton retry | oui | C3 |
| `NotFoundError` | remote data source | `{Name}Empty` | non | C4 |
| `UnauthorizedError` | remote data source | redirection login (géré par `error` package) | non | hors scénario : géré par le package `error`, testé là-bas |

## 8. Architecture

<!-- Décisions structurelles. La map des dépendances est vérifiée par le gate `deps`. -->

- **Module** : nouveau `feature/{feature_name}` / extension de `feature/{existing}` — justification :
- **Modules partagés utilisés** : `core`, `designsystem`
- **Dépendances inter-features** (le gate `deps_features` vérifie que chacune est nommée ici) :
  - `{autre_feature}` — pourquoi, et pourquoi ça ne passe pas par `core`
- **Dépendances ajoutées** (catalogue `gradle/libs.versions.toml`) : aucune | `{groupe}:{artefact}` — pourquoi, dernière release le {date}, alternative AndroidX rejetée
- **Direction des couches** : `ui → domain ← data`, `di → *`. Domaine sans Android. Aucune exception.
- **DI** (Hilt `@Module` dans `di/`, ou Koin, celle du projet) : data sources et repository liés par leur interface, ViewModel `@HiltViewModel`.
- **Code existant déplacé ou découpé** : aucun | `fichier:symbole` — testé : oui / non (non → tests de caractérisation écrits d'abord, `create_test.md` §9). (learn 2026-10-27, refactor_moved_code_without_tests)
- **Routes** (navigation Compose, `NavGraphBuilder.{feature_name}Screen()`) : 
- **Clés l10n** (`src/main/res/values/strings.xml` et ses `values-xx/`) : 
- **Events analytics** (le tracker du module `core`) : 
- **Services existants réutilisés** (ne pas réinventer) : 

<!--
  Pas de vue d'architecture : la structure est dans les contrats du dev. Les séquences par scénario
  sont dans cadrage.md ; `archi.json` (à côté de cette spec, format :
  ~/.claude/stacks/android/templates/feature_archi_example.json) relie seulement chaque C<n> à son
  scénario de §4. Seul diagramme gardé ici : la machine d'états de chaque ViewModel.
-->

**États du ViewModel** (un diagramme par ViewModel, états de `{Name}UiState`)

```mermaid
stateDiagram-v2
  [*] --> Loading
  Loading --> Loaded: success(entity)
  Loading --> Empty: NotFound
  Loading --> Error: failure(error)
  Error --> Loading: Retry
```

## 9. Package et dépendances

<!--
  Ce que les contrats ne montrent pas, et seulement ça. Format parsé par le rapport HTML et
  l'orchestrateur : ne pas changer les colonnes.

  - Module (nouveau / extension de …) et dépendances (catalogue Gradle, inter-modules) : tranchés au
    cadrage, statut `validée`.
  - Une dépendance découverte en écrivant la spec : statut `proposée`, avec une alternative RÉELLE ;
    le dev la tranche au point d'étape « spec ».
  - Jamais Stream/Future, découpage des ViewModels, data sources, emplacement d'une logique : c'est dans
    le code du dev. Jamais une question qu'une règle tranche, jamais la dette du code existant.
  - ID stable (A1, A2…), jamais renuméroté.
  - Avant d'écrire une ligne, vérifie qu'aucune règle (create_feature_rules, CLAUDE.md, answers.md,
    gates) ne la tranche ; si une règle la tranche, écris la décision en citant la règle, sans la proposer. (learn 2026-11-03, spec_asks_what_rules_decide, 2 runs)
-->

| ID | Sujet | Décision | Alternative | Raison | Statut |
|---|---|---|---|---|---|
| A1 | Package | | | | validée |

## 10. Questions ouvertes

<!-- DOIT ÊTRE VIDE à la validation. Sinon, la spec n'est pas finie. -->

_Aucune._
