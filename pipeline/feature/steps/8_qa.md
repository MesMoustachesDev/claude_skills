### 8. QA — Quentin (`feature-qa`)

**Gabarit S : une seule plateforme** — le gauntlet la choisit (`qa.platform_s`, sinon la première de
`qa.platforms`) en lisant `pipeline.json → size` ; un flow par scénario, comme en M. Dis au dev
laquelle dans la visite guidée. **En L :** n'a pas lieu.

**Appareil** : `pipeline.json → qa_devices`, posé au preflight (étape 0). Absent (feature commencée
avant le preflight) → pose la question du preflight maintenant (`00_preconditions.md`, « Preflight
QA »), avant de lancer Quentin. Mode `prepared` : Quentin démarre l'appareil (`gauntlet.sh qa_device
<nom>`), le met dans l'état décrit (`qa_devices.<pf>.state`), puis `pipeline.sh devices <nom> <pf>
prepared-done` ; sans ça, le gate `qa` est rouge avant tout build. L'appareil retenu est dit dans la
visite guidée.

Prompt : nom, gabarit, `spec.md`, package, `feature_pipeline.md`, `create_screen_rules.md` si présent,
et `qa_devices` (mode, état à préparer, appareil réutilisé) tel que l'imprime `pipeline.sh devices <nom>`. Au retour, quel que soit le gate :
pas d'arrêt, passe à 8b (un `qa` rouge ou `FAILED` bloque la validation de la visite, voir 8b). Les captures sont montrées dans la visite guidée, à l'étape qui implémente
leur scénario ; les ✗ de `qa.md` sont en tête de la visite.

