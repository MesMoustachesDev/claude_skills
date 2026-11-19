# Serena — contrat partagé

Lu par `/feature`, `/fix`, `/reviewPR` et les agents qui explorent ou relisent. Décision : ADR 0018.
Serena est un serveur MCP adossé au serveur de langage (LSP) Dart : il donne les **références exactes** d'un
symbole sur l'état réel du worktree, tests et code généré compris, là où grep ramène les homonymes et les
commentaires, et où graphify ne voit que des fichiers. graphify reste la carte (cadrage, `impact.json`, ordre
de lecture du diff) ; Serena est la boussole des usages.

## Quand

| Pipeline | Étape | Commande |
|---|---|---|
| /feature | 0, juste après la carte graphify | `bash ~/.claude/scripts/serena.sh prepare <wt>` |
| /fix | 0, juste après la carte graphify | `bash ~/.claude/scripts/serena.sh prepare <wt>` |
| /reviewPR | 4, avant de lancer les agents | `bash ~/.claude/scripts/serena.sh prepare <worktree de la revue>` |

- Sort toujours en 0. La **dernière ligne de stdout** donne l'état : `serena: ok <wt> dart=<version>`,
  `serena: absent <raison>` ou `serena: échec <raison>`. Lis-la, ne te fie pas au code retour.
- **Serena ne bloque jamais**, comme graphify. `absent` (pas installé, projet non Dart, `flutter pub get` pas
  fait) : ne parle pas de Serena et continue. `échec` : note la ligne dans ton rapport et continue sans.
- `prepare` retient le worktree : les sous-agents qui ont Serena le retrouvent même s'ils héritent du cwd du
  checkout principal. Relance-le après un changement de worktree (reprise, nouvelle revue).
- Rien pour Kotlin : le serveur de langage Kotlin ne sort que les références du fichier même.

## Les agents

Ont Serena en lecture (serveur `serena` dans leur frontmatter) : fix-reproducer, feature-specifier, feature-architect,
feature-dedup, feature-reviewer, fix-reviewer, review-architect, review-code. Lecture seule, six outils :

| Outil | Pour |
|---|---|
| `find_symbol` | trouver une déclaration (`name_path_pattern`, `relative_path` optionnel : dossier ou fichier) |
| `find_referencing_symbols` | **les usages exacts** d'un symbole (`name_path`, `relative_path` = fichier de sa déclaration) |
| `find_implementations` | les implémentations et les overrides (que `find_referencing_symbols` ne compte pas) |
| `find_declaration` | aller d'un usage à sa déclaration |
| `get_symbols_overview` | les symboles d'un fichier |
| `get_diagnostics_for_file` | les erreurs et warnings du LSP sur un fichier |

- **Les usages d'un symbole modifié** : `find_referencing_symbols` quand Serena est là, grep sinon. Serena suit
  l'appel par un sous-type (un appel sur l'implémentation compte pour la méthode abstraite) ; les overrides,
  c'est `find_implementations`.
- **Lignes 0-based** dans la sortie de Serena : `> 129:` est la ligne 130 du fichier. Convertis avant de citer
  un `fichier:ligne`.
- Le premier appel démarre le serveur Dart : 5 à 20 s. Les suivants : moins d'une seconde.
- Pas d'outil Serena dans la liste (ou outil refusé par le hook, ou « Serena sert … pas ton worktree ») :
  travaille avec grep et dis-le en une ligne dans ton rapport. Un refus se rapporte, il ne se contourne pas.
- Personne n'écrit sous `.serena/` : c'est la config de Serena, réécrite par `serena.sh` à chaque démarrage.

## L'écriture

Ont Serena en écriture (`serena.sh serve --ecriture`) : feature-implementer, ses deux moitiés (-data,
-presentation) et feature-cleaner. Les six outils de lecture, plus :

| Outil | Pour |
|---|---|
| `replace_symbol_body` | remplacer un symbole entier (`name_path`, `relative_path`, `body`) |
| `insert_after_symbol` | ajouter un symbole après un autre |
| `insert_before_symbol` | ajouter un symbole avant un autre (import, constante de haut niveau) |

- Ces outils pour **remplacer ou ajouter un symbole entier** ; Edit pour le reste et pour **toute
  suppression**. Pas de `safe_delete_symbol` (il casse une variable ou un champ, et refuse de supprimer une
  classe inutilisée qui a un constructeur), pas de `rename_symbol` (il réécrit des fichiers que le hook ne
  voit pas, dont les tests gelés) : le hook les refuse.
- Après chaque écriture Serena : `fvm dart format <fichier>`. Serena perd l'indentation après une méthode.
- Le hook juge `relative_path` (relatif à la racine du worktree) comme un Edit de ce fichier : même zone, tests
  gelés refusés. Il refuse en plus les fichiers générés (`*.g.dart`, `*.freezed.dart`, l10n générée…), où
  Serena écrirait sans broncher : on change la source et on relance le générateur.
- Le LSP voit le nouveau contenu tout de suite (références et diagnostics à jour, sans relance).
