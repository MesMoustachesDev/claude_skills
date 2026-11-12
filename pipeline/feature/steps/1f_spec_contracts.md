### 1f. §5 de la spec : les contrats de Thibault — Sophie (`feature-specifier`, mode contrats)

Les scénarios sont validés (1), les contrats en sont sortis (1c, 1e) : la spec les rattache. Rien d'autre
ne change dans la spec ; les scénarios validés ne se réécrivent pas ici.

Prompt : nom, « mode contrats », `spec.md` (scénarios validés), `cadrage.md`, `contracts.sha` et
`contracts.files` (« écrits par Thibault : la spec les décrit, elle ne les change pas »), racine, gabarit
et plafond. Copie d'abord `spec.md` en `.claude/features/<nom>/.spec_prev.md`.

Sophie écrit §5 : une ligne par contrat, le fichier et le **symbole** (`Classe.methode`), jamais une
signature recopiée ni un numéro de ligne, et le C<n> qu'il sert. Elle aligne les clés de §4 sur le
fichier de clés que Thibault a gardé (un nom changé par lui se reporte dans le scénario, mot pour mot,
sans changer ce que le scénario prouve). Un contrat qui ne permet pas un scénario validé (erreur sans
état, donnée absente d'une entité, appel qui manque) n'est pas corrigé par Sophie : elle le liste sous
« Contrats à revoir par Thibault », avec `fichier:ligne`, le C<n> empêché et le changement minimal, et
marque le jeton `<!-- spec_lint: ignore <jeton> -->`. Elle revient quand `spec_lint` est vert, **phase
complète** (clés, symboles, `Classe.membre` : `human_gates.contracts` est posé).

À son retour : `diff -u .spec_prev.md spec.md > spec.diff`.
- **Aucun contrat à revoir** → `pipeline.sh pass <nom> spec_contracts`, une ligne à Thibault (« §5
  rattachée : <n> contrats, <n> clés alignées ») et le `spec.diff` s'il touche autre chose que §5. Pas de
  point d'étape.
- **Contrats à revoir** → un `AskUserQuestion`, une question par contrat, précédée dans ton message de
  l'extrait (`fichier:ligne`) et du scénario qu'il empêche : « Je modifie mon contrat » (tu réouvres le
  fichier, il édite, puis « Réédition plus tard » de 1e ; Sophie remet §5 à jour) / « Le scénario
  s'adapte » (relance Sophie en « mode correction » sur §4 avec la consigne, puis Camille en **mode
  ciblé** sur `spec.diff`, `pipeline.sh loop <nom> spec` avant ; le scénario modifié se montre à Thibault
  avant `pass`) / « Accepter : <raison> » (`pipeline.sh accept <nom> spec_contracts "<raison>"`). Une
  fois chacun tranché et `spec_lint` vert : `pipeline.sh pass <nom> spec_contracts`.

« scénarios validés le <date> » devient « validée le <date> » dans l'en-tête de la spec.

**Gabarit S :** identique. **En L :** n'a pas lieu.

### 1g. Ticket

`issue.status == "to_create"` → `~/.claude/pipeline/issue.md`, partie B, gabarit feature (scénarios
validés, contrats de Thibault). Sinon rien.
