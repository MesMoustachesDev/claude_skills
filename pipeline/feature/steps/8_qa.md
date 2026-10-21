### 8. QA — Quentin (`feature-qa`)

**Gabarit S : une seule plateforme** — le gauntlet la choisit (`qa.platform_s`, sinon la première de
`qa.platforms`) en lisant `pipeline.json → size` ; un flow par scénario, comme en M. Dis au dev
laquelle dans la visite guidée. **En L :** n'a pas lieu.

Prompt : nom, gabarit, `spec.md`, package, `feature_pipeline.md`. Au retour, quel que soit le gate :
pas d'arrêt, passe à 8b (un `qa` rouge ou `FAILED` bloque la validation de la visite, voir 8b). Les captures sont montrées dans la visite guidée, à l'étape qui implémente
leur scénario ; les ✗ de `qa.md` sont en tête de la visite.

