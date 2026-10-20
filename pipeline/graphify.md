# graphify — contrat partagé

Lu par `/feature`, `/fix` et `/reviewPR`. Une seule source : la mécanique est dans
`~/.claude/scripts/graphify.sh` (`prepare`, `impact`) et `scripts/graphify/impact.py`, le contrat ici.
Le graphe est une carte du **checkout principal** (`graphify-out/graph.json`, éventuellement dans un
sous-dossier du repo) ; chaque worktree en reçoit une copie.

## Quand

`<wt>` = worktree, `<base>` = merge-base de la branche de base (`/feature`) ou `base_sha` (`/fix`).

| Pipeline | Étape | Commande |
|---|---|---|
| /feature | 0 | `prepare <wt>` |
| /feature | 9a | `prepare <wt> --update` puis `impact <wt> <base> --out .claude/features/<nom>/.gauntlet/graphify` |
| /fix | 0 | `prepare <wt>` |
| /fix | 3 | avant chaque passe de Victor : `prepare <wt> --update` puis `impact <wt> <base_sha> --out .claude/fixes/<nom>/.gauntlet/graphify` |
| /reviewPR | — | `pr_gauntlet.sh`, automatiquement |

- `bash ~/.claude/scripts/graphify.sh prepare <wt> [--update]` et `… impact <wt> <base> [--out <dir>]`.
- Sort toujours en 0. La **dernière ligne de stdout** donne l'état : `graphify: ok …`, `stale …`,
  `absent` ou `échec <raison>`. Lis-la, ne te fie pas au code retour.
- `prepare` rafraîchit le graphe du principal s'il est en retard sur son HEAD, le copie dans le worktree
  (cache compris), copie les `.graphifyignore` non versionnés du principal (graphify les lit de la
  racine de scan jusqu'à la racine du repo) et exclut `graphify-out/` via `.git/info/exclude`.
  Sa ligne `ok` donne le chemin du graphe relatif au repo (`graph=<dossier>/graphify-out/graph.json`) ;
  il écrit aussi la racine de scan du worktree dans `graphify-out/.scan_root`, que lit `impact`.
  Avec `--update`, il garde d'abord `graph.base.json` (le graphe avant mise à jour) puis relance
  `graphify update` sur le worktree ; s'il échoue : `stale`, graphe de la base conservé.
- Un `graph.json` corrompu donne `échec graph.json illisible`. Sans graphe : `absent`, ne crée rien.

## Lire impact.json

`impact` écrit `impact.json` et `impact.md` (sections « Consommateurs hors package non touchés »,
« Dépendances », « Ordre de lecture du diff »). Le diff = fichiers changés depuis la base, arbre de
travail et fichiers non suivis compris. Packages listés dans `graphify.ignore_packages` (défaut `core`) exclus.

- `status` : `ok`, `stale`, `absent` ou `failed` ; `reason` si `failed`. **`stale`** = l'update du
  worktree a échoué : **les symboles ajoutés par le diff manquent** du graphe. Les consommateurs trouvés
  restent vrais, l'absence d'un consommateur ne prouve rien.
- `consumers[]` : un symbole **d'un autre package qui dépend du code touché** (il peut casser).
  `package`, `file`, `symbol`, `location` (la ligne seule, ex. `L42` : cite `file:location`) ;
  `via` / `via_file` = le symbole touché qu'il utilise ; `relation` = nature du lien.
  - `touched` : le fichier du consommateur est déjà dans le diff. Ceux-là sont absents de `impact.md` :
    ils sont dans ce que tu relis de toute façon.
  - `removed` : le symbole `via` n'existe plus dans le graphe courant (supprimé ou renommé), retrouvé
    via `graph.base.json` : à lire en premier, le consommateur ne compile peut-être plus. Ce graphe peut
    aussi venir d'un checkout principal en avance sur la base — vérifie que le symbole a bien disparu
    dans le diff.
  - `classified: false` : orientation de l'arête indéterminée (ni son `source_file` ni son sens ne
    désignent le côté qui référence) **et** les deux packages ne sont pas tous deux Dart (pas de pubspec
    pour trancher) ; consommateur par défaut. Vérifie.
- `dependencies[]` : `package`, `symbol`, `via` — ce que le code touché **utilise** ailleurs (le package
  touché dépend de lui). Ce n'est **pas** un consommateur : ne le compte pas comme impact.
- `reading_order[]` : `file`, `degree` — fichiers du diff présents dans le graphe, par degré décroissant
  (les plus connectés d'abord). `not_in_graph[]` : fichiers du diff absents du graphe (nouveaux, générés,
  ignorés), lis-les dans l'ordre du diff.

## Explorer

Quand le projet a un graphe (copié dans le worktree par `prepare`), pars de la carte, pas d'une
exploration à l'aveugle. Le graphe n'est pas forcément à la racine : son chemin est le `graph=` de la
ligne d'état de `prepare` (ex. `flutter_app/graphify-out/graph.json`), transmis dans ton prompt.
graphify cherche par défaut `./graphify-out/graph.json` : passe `--graph <g>` à chaque commande
(`<g>` = `<worktree>/<graph=…>`), ou lance-la depuis le dossier qui contient `graphify-out/`.

1. `GRAPH_REPORT.md` (à côté de `graph.json`) : communautés et nœuds centraux du domaine.
2. `graphify explain "<Symbole>" --graph <g>` et `graphify path "<A>" "<B>" --graph <g>` sur les
   symboles du besoin.
3. `graphify query "<question>" --budget 1500 --graph <g>` en **dernier recours** : il remonte du bruit,
   surtout les fichiers l10n générés.

Ne lis le code que pour vérifier ce que le graphe montre. Cite les nœuds avec leur `fichier:ligne` :
le `source_file` d'un nœud est relatif à la racine de scan (`graphify-out/.scan_root`), préfixe-le du
chemin de cette racine dans le repo.
Sophie en tire aussi la **carte** du cadrage : un `flowchart` Mermaid de ce qui existe autour du besoin
(packages, classes, flux), avec ce que la feature touchera.

## Règles

- **graphify ne bloque jamais.** `absent` : ne mentionne pas graphify (ni section Impact), continue
  comme avant. `stale` : impact calculé sur le graphe de la base, utilisable ; une absence de
  consommateur ne prouve rien — note la ligne. `échec` : note la ligne et continue sans le graphe.
- **Le graphe localise, la lecture et les logs prouvent.** Un nœud ou une arête n'est jamais une preuve
  de comportement ni de cause : va lire le code.
- `.graphifyignore` exclut le code généré (`*.g.dart`, `*.freezed.dart`, `*.mocks.dart`, `generated_l10n/`)
  et les tests : le graphe ne voit ni leurs usages ni ceux qui passent par du code généré. Le `grep` des
  usages d'un symbole modifié reste donc **obligatoire**, `impact.md` ne le remplace pas.
- Ne modifie ni le graphe ni `graphify-out/` à la main ; `prepare` et `impact` sont les seuls points d'entrée.
