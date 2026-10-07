# Business Rules — les règles métier d'un répertoire, depuis ses fichiers Gherkin

Tu produis une page HTML qui rassemble toutes les règles métier écrites en Gherkin (`.feature`) sous
un répertoire. **Le script fait tout le travail ; tu ne lis ni les `.feature` ni le HTML.** C'est ce qui
rend la commande quasi gratuite en tokens, quelle que soit la taille du projet.

Argument : **$ARGUMENTS**

```
/business_rules                       répertoire courant (racine du repo en général)
/business_rules <répertoire>          un package, un dossier de features, un worktree…
/business_rules <répertoire> --out <fichier.html>
/business_rules help                  cette aide
```

## Ce que fait le script

`~/.claude/scripts/business_rules/business_rules.py` :
- cherche tous les `.feature` sous le répertoire, hors dépendances et artefacts (`vendor`,
  `node_modules`, `build`, `Pods`, `.dart_tool`…) et hors worktrees de `.claude/worktrees` (pour ne pas
  compter deux fois les features d'une branche en cours) ;
- les regroupe par package (le dossier parent le plus proche qui a un `pubspec.yaml` ou un
  `package.json`) ;
- comprend Feature, description, Background, `Rule`, Scenario, Scenario Outline et Examples, tags,
  data tables et docstrings, en anglais et en français (`# language: fr`) ;
- écrit une page autonome (aucune dépendance réseau) : navigation par package et par feature,
  recherche plein texte, filtre par tag, scénarios dépliables, et les signalements (feature sans
  scénario, scénario sans `Then`, titres en double, Scenario Outline sans exemples) ;
- imprime le chemin écrit et un résumé de quelques lignes.

Sortie par défaut : `<racine git>/.claude/business_rules.html`, ou `<répertoire>/business_rules.html`
hors d'un repo git.

## Déroulé

1. `help` → affiche le bloc d'usage ci-dessus et la section « Ce que fait le script » en 3 lignes. Rien d'autre.
2. Lance, depuis le répertoire courant :
   ```bash
   python3 ~/.claude/scripts/business_rules/business_rules.py $ARGUMENTS
   ```
   Lis uniquement sa sortie. N'ouvre pas le HTML avec `Read`, ne lis pas les `.feature` : le résumé
   imprimé suffit, et la page est faite pour le dev.
3. Code de sortie non nul → montre le message d'erreur tel quel et arrête-toi.
4. `SendUserFile` du chemin imprimé en première ligne, `display: render`, légende « règles métier ».
5. Réponds en 5 lignes au plus : nombre de packages, de features et de scénarios ; les 3 packages les
   plus fournis ; les signalements par type, s'il y en a. Pas de liste de scénarios, pas de
   paraphrase des règles : c'est le rôle de la page.
6. Le résumé a une ligne « exclus : … » → des `.feature` vivent dans des worktrees de
   `.claude/worktrees`, exclus volontairement. Relaye-la en une ligne avec la commande pour en voir
   un : `/business_rules <chemin du worktree>`. C'est le cas typique de « 0 feature » à la racine d'un
   repo dont les features sont en cours sur des branches.

Tu ne modifies aucun fichier du projet, et tu ne commites pas la page générée.
