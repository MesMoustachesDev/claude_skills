# 0015 — Les scénarios Gherkin s'écrivent avant les contrats, et les contrats en sortent

Statut : acceptée (2026-11-12)
Où elle vit : `scripts/pipeline/pipeline.py` (`ORDER`, `state_of`) · `pipeline/feature/steps/1_spec.md`,
`1c_contracts_draft.md`, `1d_dedup.md`, `1e_contracts.md`, `1f_spec_contracts.md` · `commands/feature.md`
(tableau des étapes) · `agents/feature-specifier.md` · `agents/feature-architect.md` ·
`agents/feature-spec-critic.md` · `scripts/gauntlet/spec_lint.py` et `checks_review.sh` (phase
`scenarios`) · `mods/pipeline-view` (scénarios montrés avant le premier `.feature`)

## Contexte

Jusqu'ici : cadrage (C<n> + séquences) → 0c brouillon de contrats (Arthur) → 0d roue réinventée → 0e
contrats de Thibault → 1 spec (Sophie, écrite **à partir des contrats**) → 1b critique → 2 complétion.
Aucune ADR ne justifiait cet ordre ; il venait de l'idée que la spec décrit des contrats déjà écrits.

C'est l'inverse du BDD outside-in, où les scénarios Given/When/Then viennent d'abord et où les interfaces
en sortent. Le coût est réel : sur une sous-feature d'écriture d'un plan d'entraînement, on a débattu de
la forme d'un objet de mise à jour, d'un identifiant de séance et d'une erreur « introuvable » sur des
signatures, là où un scénario aurait posé la question directement (« que doit renvoyer le modèle pour
garder les séances déjà cochées ? »). Une signature répond à une question que personne n'a encore posée ;
un scénario la pose.

## Décision

Nouvel ordre :

| Étape | Qui | Ce qui en sort |
|---|---|---|
| 0b cadrage | Sophie + Thibault | C<n>, séquences, décisions techniques |
| 1 scénarios | Sophie | `spec.md` : §4 Gherkin, §6 données, §7 erreurs, §8, §9 ; **§5 vide** (« après les contrats ») |
| 1b critique + point d'étape « scénarios » | Camille, puis Thibault | `hg.spec` |
| 1c brouillon de contrats | Arthur | stubs **tirés des scénarios** : chaque When devient un appel, chaque Then un état ou un retour, chaque erreur de §7 une valeur d'erreur, chaque clé citée par §4 une entrée du fichier de clés |
| 1d roue réinventée | Denis | inchangé (ex-0d) |
| 1e contrats de Thibault | Thibault | `hg.contracts` (ex-0e) |
| 1f §5 de la spec | Sophie | §5 renvoie aux symboles des contrats ; `spec_lint` complet |
| 1g ticket | toi | ex-1c |
| 2 complétion | Arthur | inchangé |

- **`spec_lint` a deux phases**, choisies par le gauntlet d'après `pipeline.json` : sans
  `human_gates.contracts`, phase `scenarios` (pas de vérification des symboles de §5, des `Classe.membre`
  ni des clés : ils n'existent pas encore, et les clés citées par §4 sont l'entrée d'Arthur) ; avec, phase
  complète, comme avant.
- **Un contrat qui ne permet pas un scénario validé** est signalé par Arthur (brouillon) ou par Sophie
  (1f) ; Thibault tranche : il change son contrat, ou le scénario change (relance de Sophie, puis 1b en
  mode ciblé).
- **Reprise des features en cours** (`ORDER` et `state_of`) : une feature dont la spec a été validée
  **après** ses contrats (ordre d'avant) saute 1f, sa §5 est déjà écrite ; une feature arrêtée entre 0c et
  1 de l'ancien ordre passe d'abord par 1 (les scénarios), le brouillon déjà commité restant en place.
- Le panneau Pipeline montre les C<n> du cadrage, puis la §4 de la spec, tant qu'aucun `.feature` n'est
  dans le code.

## Conséquences

- Les questions produit se posent sur des scénarios, en français, avant toute signature ; Arthur part
  d'une liste d'appels et d'états au lieu d'une page blanche.
- Un aller-retour de plus de Sophie (1f), court : §5 seule, contre la spec déjà validée.
- Un point d'étape « scénarios » sans code à côté : Thibault juge le comportement, pas encore la forme.

## Hors champ

- Le gabarit L (découpé au cadrage) : chaque sous-feature suit le nouvel ordre.
- `/fix` : pas de contrats ni de spec, inchangé.
