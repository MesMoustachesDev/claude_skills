### `/feature help`

Affiche le bloc d'usage ci-dessus, puis ces exemples, tels quels :

```
# Nouvelle feature, package neuf, description libre
/feature meal_reminders "Rappels de repas : l'utilisateur programme une notification par repas planifié"

# Ajout à une feature existante : le nom décrit le changement, --in désigne le package
/feature recipe_export_pdf --in features/show_recipe "Exporter une recette en PDF depuis l'écran recette"

# Correctif comportemental dans un package existant (petite spec, mêmes gates)
/feature category_sort_fix --in features/category "Les catégories custom sont triées après les prédéfinies"

# Reprendre où on en était (après une coupure, ou le lendemain)
/feature meal_reminders

# Où en est-on ?
/feature meal_reminders status

# Le dedup a jugé un widget en doublon, je le garde en connaissance de cause
/feature meal_reminders accept dedup "MealCard n'est pas une DesignCard : pas de slot image, comportement de swipe spécifique"

# Préparer un projet la première fois
/feature init

# Audit de maintenabilité d'un package existant, hors pipeline (aucun agent, scripts seuls)
~/.claude/scripts/gauntlet.sh maintain category
```

Puis rappelle en cinq lignes : les six points d'étape (cadrage avec une séquence par scénario,
contrats que tu écris toi-même, spec, tests avec leurs séquences réelles, suggestions de revue, visite
guidée du code), chacun avec un rapport HTML ; le gabarit S / M / L choisi au cadrage, qui allège les
étapes de jugement d'une petite feature et impose le découpage d'une grosse ; que rien
n'est pushé sans `create_mr`, et que `~/.claude/scripts/gauntlet.sh list` détaille chaque check.
Ajoute une ligne : chaque feature a sa page de cockpit (l'état, ce qu'on attend de lui, ses décisions,
ses contrats éditables, « Prévenir Claude »), et l'accueil https://claude.ai/artifact/TiXbjaUnp6yVay81XBKQ8R
les liste toutes.

