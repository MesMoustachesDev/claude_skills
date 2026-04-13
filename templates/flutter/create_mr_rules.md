# Create MR Rules — GitLab / Flutter

## Provider & CLI

- **Provider** : GitLab (self-hosted)
- **CLI** : `glab` (https://gitlab.com/gitlab-org/cli)
- **Branche de base** : `develop`

## Conventions de titre

- **Format** : `{type}: {description courte}`
- **Types autorisés** : `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `style`, `perf`, `ci`
- **Langue** : anglais
- **Longueur max** : 72 caractères
- **Pas de point final**

Exemples :
- `feat: add send report page with attachment selection`
- `fix: prevent crash when pictures list is empty`
- `chore: bump version to 1.0.49`

## Template du body

```markdown
## Summary
<!-- 2-5 bullet points décrivant les changements -->

## Changes
<!-- Liste des fichiers/modules impactés avec une ligne de contexte -->

## Related issue
<!-- Lien vers le ticket GitLab si applicable, sinon supprimer cette section -->

## Test plan
<!-- Comment vérifier que la MR fonctionne -->
```

## Questions à poser

Avant de générer le titre et la description, poser ces questions via `AskUserQuestion` :

1. **Ticket GitLab** : "Y a-t-il un ticket GitLab associé à cette MR ?"
   - Oui → demander le numéro ou l'URL du ticket, l'inclure dans le body (section "Related issue") avec `Closes #XXX` ou `Relates to #XXX`
   - Non → supprimer la section "Related issue" du body

## Labels

Pas de labels par défaut. Si le titre commence par un type connu, ne pas ajouter de label automatique.

## Reviewers

Pas de reviewer par défaut. Ne pas assigner automatiquement.

## Commande de création

```bash
glab mr create \
  --title "{title}" \
  --description "$(cat <<'EOF'
{body}
EOF
)" \
  --source-branch "{source_branch}" \
  --target-branch "{target_branch}" \
  --no-editor
```

## Règles spécifiques

- Ne jamais créer de MR en draft sauf si l'utilisateur le demande explicitement
- Vérifier que `glab` est authentifié avant de tenter la création (`glab auth status`)
