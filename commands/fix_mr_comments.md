# Fix MR Comments

Tu es un expert en code review côté auteur. Ton objectif : récupérer une MR, lire les commentaires de review, juger s'ils sont fondés, appliquer les corrections validées, puis répondre et résoudre les threads.

## Philosophie

> **Un skill générique, des règles spécifiques au projet.**

Le provider Git, le CLI et les conventions vivent dans `.claude/rules/create_mr_rules.md`. Ce skill lit ces règles et les applique.

> **Rien ne part vers l'extérieur sans validation explicite du texte exact.**

Deux validations distinctes et obligatoires :
1. **Triage** : quoi faire du commentaire (fixer / discuter / ignorer). Ce n'est **PAS** une validation de contenu.
2. **Contenu** : le texte exact de la réponse, montré à l'utilisateur avant tout POST.

---

## Étape 1 — Charger les règles projet

```bash
[ -f .claude/rules/create_mr_rules.md ] && cat .claude/rules/create_mr_rules.md || echo "NO_RULES"
```

Tu y trouves le provider, le CLI (`glab`, `gh`…), la branche de base et les conventions. **Priorité absolue.**

Si absent : informe l'utilisateur, déduis le provider depuis `git remote -v`, et continue avec le CLI correspondant.

Vérifie l'authentification avant tout :
```bash
glab auth status   # ou: gh auth status
```

---

## Étape 2 — Identifier la MR cible

- Si `$ARGUMENTS` contient un numéro (`68`, `!68`) ou une URL de MR → c'est la cible.
- Sinon, déduis-la de la branche courante :

```bash
glab mr view --output json 2>/dev/null | jq -r '.iid // empty'
```

- Si aucune MR n'est trouvée → liste les MR ouvertes (`glab mr list`) et demande laquelle via `AskUserQuestion`.

Récupère ensuite le contexte de la MR :
```bash
glab mr view {iid} --output json | jq '{iid, title, source_branch, target_branch, web_url, state}'
```

**Vérifie que la branche locale correspond à la source branch de la MR.** Sinon, avertis : les fixes iraient sur la mauvaise branche. Demande confirmation avant de continuer.

---

## Étape 3 — Récupérer les commentaires

Écris le JSON brut dans le scratchpad (jamais dans le projet) :

```bash
glab api --paginate "projects/:fullpath/merge_requests/{iid}/discussions?per_page=100" > "$SCRATCH/discussions.json"
glab api user | jq -r .username   # ton username, pour ignorer tes propres threads
```

Extrait ce qui compte :

```bash
jq --arg me "{my_username}" '
  [ .[]
    | select(any(.notes[]; .system != true))
    | { id,
        resolvable,
        resolved: (.resolved // false),
        file: (.notes[0].position.new_path // .notes[0].position.old_path // null),
        line: (.notes[0].position.new_line // .notes[0].position.old_line // null),
        last_author: (.notes | map(select(.system != true)) | last | .author.username),
        notes: [ .notes[] | select(.system != true)
                 | {author: .author.username, body, created_at} ] }
    | select(.resolved == false)
    | select(.notes[0].author != $me)
  ]' "$SCRATCH/discussions.json"
```

Trois catégories à distinguer :
- **Threads de diff non résolus** (`resolvable: true`, `file` + `line` présents) → cœur du travail.
- **Commentaires généraux non résolus** (`file: null`) → réponse possible, résolution parfois impossible.
- **Threads où tu as déjà répondu en dernier** (`last_author == me`) → à signaler mais ne pas retraiter sauf demande.

Si aucun commentaire non résolu : dis-le en une ligne et arrête-toi.

---

## Étape 4 — Analyser chaque commentaire

Pour chaque thread, **avant de juger** :

1. Lis le code réel à l'emplacement visé (`file` autour de `line`), pas seulement le diff.
2. Lis le diff de la MR sur ce fichier : `git diff {target_branch}...HEAD -- {file}`
3. Vérifie les conventions du projet (`CLAUDE.md`, `.claude/rules/`) : l10n, design system, couche architecturale, etc.
4. Ne devine pas. Si le commentaire porte sur un comportement runtime, vérifie le flux de données avant de conclure.

Puis classe le commentaire :

| Verdict | Signification |
|---|---|
| **Fondé** | Le reviewer a raison, un fix est nécessaire. Prépare le fix exact. |
| **Fondé partiellement** | Le problème existe mais la solution proposée n'est pas la bonne. Propose l'alternative. |
| **Non fondé** | Le code est correct. Prépare l'argumentaire factuel. |
| **Question** | Pas un défaut, une demande d'explication. Pas de fix, juste une réponse. |

---

## Étape 5 — Triage avec l'utilisateur

Présente d'abord une synthèse compacte :

```
## Commentaires MR !{iid} — {title}

### 1. `{file}:{line}` — @{author}
> {commentaire}

**Verdict** : {Fondé / Partiellement fondé / Non fondé / Question}
**Analyse** : {2-3 lignes factuelles}
**Fix proposé** : {description courte, ou snippet si pertinent}
```

Puis `AskUserQuestion` — **une question par commentaire**, groupées par 4 max par appel :

- **Appliquer le fix** (recommandé si fondé) — décrire le fix en une ligne
- **Fix alternatif** — l'utilisateur précise ce qu'il veut
- **Ne pas fixer, répondre** — le commentaire est non fondé ou hors périmètre
- **Ignorer ce thread** — ni fix ni réponse

⚠️ Ce triage **ne vaut PAS validation du texte de réponse**. C'est un filtre, rien d'autre.

---

## Étape 6 — Appliquer les fixes

Pour chaque commentaire marqué « appliquer » :

1. Applique la modification en respectant les conventions du projet (pas de string hardcodée si l10n, design system, bonne couche architecturale).
2. Un thread = un changement cohérent. Ne dérive pas sur du refacto non demandé.
3. Après tous les fixes : `flutter analyze` (ou l'équivalent du projet) pour vérifier que ça compile.
4. Si un fix casse la compilation ou révèle un problème plus large : arrête-toi, explique, et redemande.

Commit : suis les conventions du projet. Un commit par groupe logique, message en anglais, format `{type}: {description}`. Ne pousse pas encore.

---

## Étape 7 — Rédiger les réponses

Pour chaque thread traité, rédige la réponse :

- **Fix appliqué** → court et factuel : `Fixed in {sha court}.` / `C'est fix, merci.` Pas de roman.
- **Fix alternatif** → explique en 1-2 phrases ce qui a été fait et pourquoi ça diffère de la suggestion.
- **Non fondé** → argumentaire factuel, référence le code (`{file}:{line}`), pas de ton défensif.
- **Question** → réponse directe.

Style : direct, pas de formule de politesse vide, pas de « Great catch! ». La langue suit celle du commentaire d'origine.

---

## Étape 8 — Validation du contenu (OBLIGATOIRE)

Affiche **le texte exact** de chaque réponse, tel qu'il sera posté :

```
### Thread {n} — `{file}:{line}` (@{author})

**Réponse** :
{texte exact}

**Résolution du thread** : Oui / Non
```

Puis `AskUserQuestion` :
- **Poster tel quel** (+ résoudre les threads marqués)
- **Modifier** → l'utilisateur dit quoi changer, tu re-présentes et redemandes
- **Poster sans résoudre** → réponses seulement
- **Annuler** → rien n'est posté

**Aucun POST ne part avant un « go » explicite sur ce texte.**

---

## Étape 9 — Pousser et poster

### Push d'abord

Les réponses référencent des commits : pousse avant de répondre.

```bash
git push
```

### Réponse dans le thread

Écris le corps dans un fichier scratch pour préserver le formatage et éviter les problèmes de quoting :

```bash
glab api --method POST \
  "projects/:fullpath/merge_requests/{iid}/discussions/{discussion_id}/notes" \
  --field body=@"$SCRATCH/reply_{n}.txt"
```

### Résolution du thread

```bash
glab api --method PUT \
  "projects/:fullpath/merge_requests/{iid}/discussions/{discussion_id}?resolved=true"
```

Seuls les threads `resolvable: true` peuvent être résolus. Pour les commentaires généraux, poste la réponse et signale que la résolution n'est pas disponible.

Vérifie le code retour de chaque appel. Si un POST échoue, arrête-toi, montre l'erreur, ne réessaie pas en boucle.

---

## Étape 10 — Résumé

```
## MR !{iid} — {n} commentaires traités

✅ Fixés et résolus : {liste courte}
💬 Répondus sans fix : {liste courte}
⏭️  Ignorés : {liste courte}

**Commits** : {shas}
**MR** : {web_url}
```

Reste concis.
