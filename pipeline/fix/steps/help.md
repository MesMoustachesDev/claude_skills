# /fix help

Affiche le bloc d'usage de `~/.claude/commands/fix.md`, puis :

```
# Bug backend signalé par Sentry
/fix weekly_cap_reset "Sentry APP-4F2 : le cap hebdo marketing repart à zéro après un push transactionnel"

# Bug d'UI visible sur device
/fix recipe_title_overflow "Sur iPhone SE, un titre de recette long pousse le bouton favori hors de l'écran"

# Reprendre, ou voir où on en est
/fix weekly_cap_reset
/fix weekly_cap_reset status
```

Puis en trois lignes : le point d'étape unique (diagnostic + test rouge + plan de correction, avec un
rapport HTML, plus les captures avant/après du parcours signalé rejoué sur device), que les tests sont gelés après validation, et `~/.claude/scripts/fix_gauntlet.sh list`.
