# 0018 — Serena donne les références exactes aux agents qui explorent et relisent, en lecture seule

Statut : acceptée (2026-11-19), amendée le 2026-11-19 (écriture, plus bas)
Où elle vit : `scripts/serena.sh` (prepare, serve, which) · `serena/contexts/pipeline-lecture.yml` ·
`scripts/gauntlet/serena_guard.sh` et les hooks `pipeline-restrict-writes.sh`, `fix-restrict-writes.sh`,
`review-restrict-writes.sh` · `mcpServers` du frontmatter de fix-reproducer, feature-specifier,
feature-architect, feature-dedup, feature-reviewer, fix-reviewer, review-architect, review-code ·
`pipeline/serena.md` (contrat) · `serena/contexts/pipeline-ecriture.yml`, `mcpServers` de feature-implementer, ses deux moitiés et feature-cleaner (écriture) · `pipeline/graphify.md` · `scripts/gauntlet/tests/test_serena.sh` · refus et écritures Serena au journal des hooks
(`.gauntlet/hooks.jsonl`, 0019)

## Contexte

Les agents cherchaient les usages d'un symbole par grep (règle de `pipeline/graphify.md` : le graphe exclut
les tests et le code généré). Sur un essai du 2026-11-19 (projet Flutter, 46 packages, Serena 2.1.0, 4
symboles réels), grep ramenait 12 lignes de bruit sur 14 pour une méthode au nom courant (homonymes,
overrides, commentaires), et `impact.json` manquait tous les tests et un appel de méthode depuis un autre
package. Serena, adossé au serveur de langage Dart, a rendu 0 référence manquée et 0 faux positif, tests et
code généré compris. Coût mesuré : ≈ 1,3 Go par serveur (≈ 2,1 Go pour deux), premier appel de 4 à 20 s.

L'essai a aussi trouvé des pièges, qui fondent la plupart des choix ci-dessous :

1. `serena init` écrit `agent_interface: REPL` : le serveur n'expose alors que `serena_repl` (du python) et
   ignore les listes d'outils. Il faut l'interface `tools`.
2. `.serena/project.yml` l'emporte sur la ligne de commande, même pour un projet non « trusted », et
   `.serena/project.local.yml` l'emporte sur `project.yml`. Un agent qui écrit l'un des deux rouvre python
   au prochain démarrage. `project.yml` porte aussi `activation_command`, une commande shell lancée à
   l'activation.
3. Le contexte `claude-code` livré par Serena impose sa doctrine (« Read → FORBIDDEN », Edit remplacé par
   ses outils) : contraire au pipeline.
4. Serena télécharge son propre SDK Dart (3.7.1, sans vérification), plus vieux que celui que fvm épingle ;
   il n'a pas d'option de chemin, seulement `dart_sdk_version`, appliqué seulement à un projet « trusted ».
5. L'auto-détection des langages rend `[]` sur un monorepo ; sans `flutter pub get`, pas de résolution
   entre packages. Le tableau de bord web s'ouvre par défaut.
6. Le serveur MCP d'un sous-agent ne voit ni son prompt ni son transcript : il ne connaît que son cwd, et un
   sous-agent hérite parfois du cwd du checkout principal (reprise, et toujours pour /reviewPR, dont le
   worktree est temporaire).

## Décision

- **Lecture seulement**, six outils : `find_symbol`, `get_symbols_overview`, `find_referencing_symbols`,
  `find_implementations`, `find_declaration`, `get_diagnostics_for_file`. Donnés à fix-reproducer,
  feature-specifier, feature-architect, feature-dedup, feature-reviewer, fix-reviewer, review-architect et
  review-code. L'écriture (point 9 du plan) n'est donnée à personne.
- **Branchement** : un serveur `serena` inline dans le frontmatter de ces huit agents (`mcpServers`), qui
  lance `scripts/serena.sh serve`. Claude Code le démarre avec le sous-agent et l'arrête avec lui ; la
  session principale n'en a pas les outils. Un serveur par agent actif : deux en parallèle à la revue.
- **Trouver le worktree** (piège 6) : `serena.sh which` prend la racine git du cwd si elle est sur une
  branche `feature/*` ou `fix/*`, sinon le dernier `serena.sh prepare` lancé dans le même repo, que
  l'orchestrateur lance à l'étape 0 de /feature et /fix et avant les agents de /reviewPR. Les hooks
  vérifient à chaque appel que le worktree servi est celui de l'agent (`hook_feature_root` pour /feature,
  la racine du fix, le worktree cité dans le prompt pour /reviewPR), sinon ils refusent Serena et l'agent
  fait avec grep.
- **Config tenue par le lanceur**, à chaque démarrage : home Serena à part (`~/.claude-local/serena`, par
  `SERENA_HOME`, jamais `~/.serena`) avec interface `tools`, sans tableau de bord, liste fermée, projets
  trusted ; contexte maison `serena/contexts/pipeline-lecture.yml` (`fixed_tools`, `prompt: null`) ;
  `.serena/project.yml` réécrit (dart, version du SDK, `read_only`, liste fermée, pas
  d'`activation_command`), `project.local.yml` vidé ; le SDK de fvm servi par un lien sous
  `language_servers/static/DartLanguageServer/dart-sdk-<version>/dart-sdk` ; `.serena/` exclu par
  `.git/info/exclude`.
- **Les hooks sont la barrière**, pas la config (piège 2) : liste fermée des outils `mcp__serena__*` dans
  les trois hooks de zone ; les quatre outils d'écriture (`replace_symbol_body`, `insert_after_symbol`,
  `insert_before_symbol`, `safe_delete_symbol`) passent par la zone de Edit (`relative_path` joint au
  worktree et normalisé), refusés à la revue ; tout autre outil refusé ; toute écriture sous `.serena/`
  refusée, par Edit, Write ou Bash.
- **Serena ne bloque jamais**, comme graphify : `prepare` rend `ok`, `absent` (pas installé, projet non
  Dart, `flutter pub get` pas fait) ou `échec` ; `serve` sans worktree sort en 0 et l'agent fait sans.
- Les usages d'un symbole modifié : `find_referencing_symbols` quand Serena est là, grep sinon
  (`pipeline/graphify.md`). Les lignes de Serena sont 0-based : la consigne des agents le dit.

## Conséquences

- Des références exactes là où grep et le graphe se trompaient, au prix d'≈ 1,3 Go et de quelques secondes
  par agent qui l'utilise.
- `serena.sh prepare` écrit dans le worktree (`.serena/`, ignoré par git) et dans `.git/info/exclude`.
- Le pointeur « dernier prepare du repo » est partagé : deux revues en parallèle dans le même repo se le
  disputent. Le hook refuse alors Serena à l'agent dont ce n'est pas le worktree ; il fait avec grep.
- À mesurer : le nombre de refus « Serena sert … pas ton worktree » sur une semaine, et si les relecteurs
  citent encore des usages faux.

## Hors champ

- Kotlin : son serveur de langage ne rend que les références du fichier même. Serena n'est pas proposé.
- L'écriture par Serena : voir l'amendement ci-dessous.
- L'installation de Serena (`uv tool install -p 3.13 serena-agent`) reste une décision de Thibault par
  machine ; sans elle, rien ne change.

## Amendement du 2026-11-19 : l'écriture

Un essai d'écriture sur le même projet (contexte d'écriture, tout annulé ensuite) : `replace_symbol_body` est
exact, les insertions sont justes, et le LSP voit le nouveau contenu sans relance ; seul défaut,
`insert_after_symbol` après une méthode perd l'indentation. Mais `safe_delete_symbol` casse le code sur une
variable ou un champ (il reste `const ;`, `final int ;` : la plage LSP ne couvre pas le mot-clé) et refuse
de supprimer une classe inutilisée qui a un constructeur (le sien compte comme une référence). Et Serena
écrit sans broncher dans un `*.g.dart` ou un test gelé : seul le hook l'arrête.

- feature-implementer, ses deux moitiés et feature-cleaner ont Serena en écriture : `serena.sh serve
  --ecriture`, contexte `serena/contexts/pipeline-ecriture.yml`, home Serena à part
  (`~/.claude-local/serena-ecriture`), `project.yml` avec `read_only: false`. Liste fermée : les six outils
  de lecture plus `replace_symbol_body`, `insert_after_symbol`, `insert_before_symbol`. Les relecteurs et
  les explorateurs restent en lecture.
- `safe_delete_symbol` et `rename_symbol` sont refusés par les hooks comme tout outil inconnu ; les
  suppressions passent par Edit.
- Les hooks jugent `relative_path` comme un Edit de ce fichier (zone de l'agent, tests gelés) et refusent
  en plus les fichiers générés aux outils d'écriture Serena (motifs `generated.exclude`).
- Consigne : ces outils pour remplacer ou ajouter un symbole entier, Edit pour le reste ; `fvm dart format
  <fichier>` après chaque écriture Serena.
- Serena lit sa config au démarrage : un relecteur lancé après un implementer réécrit `project.yml` en
  lecture sans changer le serveur déjà lancé, et inversement. Si deux démarrages se croisent, un serveur
  peut prendre la liste de l'autre mode : le hook reste la barrière (zone de Edit de l'agent).
- Correction du même jour : `serena/` manquait à la liste blanche de `.gitignore` de `~/.claude`, et le
  contexte de lecture n'avait pas été versionné ; `test_serena.sh` vérifie maintenant que les deux contextes
  sont suivis par git.
- À mesurer sur le banc de rejeu : tours et tokens par étape (implementer, cleaner), avant et après.
