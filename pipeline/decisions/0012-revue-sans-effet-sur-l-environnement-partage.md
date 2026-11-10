# 0012 — Une revue lit la config à la racine du repo, prépare son worktree et n'installe rien sur le simulateur partagé

Statut : acceptée (2026-11-10)
Où elle vit : `scripts/review/review.py` (`project_root`, `cmd_preflight`, `review_sim`, `cmd_qa`, `cmd_sim`,
`cmd_cleanup`, contrôle après `cmd_gauntlet`) · `scripts/sim.sh` (`--like`) · `scripts/gauntlet/checks_qa.sh`
(`GAUNTLET_SIM_UDID`) · `scripts/pr_gauntlet.sh` et `scripts/worktree_untracked.sh` (`--patterns`) ·
`agents/review-qa.md` · `pipeline/review/steps/1_preflight.md`, `2_gauntlet.md`, `4_agents.md`,
`8_synthese.md` · clé `untracked.required` des gabarits `stacks/*/templates/feature_pipeline.md`

## Contexte

La revue d'une MR d'un projet a perdu du temps et une install sur trois points que rien ne signalait :

1. Session lancée depuis le dossier de l'app (un sous-dossier du repo), règles projet posées dans
   `<app>/.claude/rules/` : le préflight, qui lit la racine du repo, a conclu « pas de config » et la revue
   est partie sur le template générique.
2. Sans `ios.simulator_base`, la QA a installé le build de la MR sur `ios.simulator`, le simulateur partagé :
   l'app staging et ses données ont été écrasées.
3. Le worktree de revue n'avait pas le `.env` du flavor staging, ignoré par git et chargé en optionnel : l'app
   démarrait sur une page blanche, sans erreur de build, jusqu'à ce que le fichier soit récupéré à la main.

## Décision

- **La racine, c'est git.** `review.sh` résout la racine avec `git rev-parse --show-toplevel` (et, dans un
  worktree sans la config non suivie, le checkout principal), jamais le dossier courant ; il note d'où il a
  été lancé et affiche la racine. Le préflight bloque sur une `feature_pipeline.md` ou `pr_rules.md` posée
  dans un `.claude/rules/` de sous-dossier (avec la commande `mv`), et avertit quand `pr_rules.md` manque.
- **La QA de revue a son simulateur, toujours.** `review.sh qa` et `review.sh sim` utilisent
  « `<modèle>` · review-`<slug>` » : clone de `ios.simulator_base` s'il existe, sinon un simulateur neuf du
  même type d'appareil et du même runtime que `ios.simulator` (`sim.sh --like`), sans compte ni données.
  Le gauntlet le reçoit en `GAUNTLET_SIM_UDID`, qui passe avant tout autre choix. Le simulateur partagé
  n'est jamais rendu ; si `sim.sh` le rendait, la QA s'arrête. `review.sh cleanup` supprime le simulateur.
  Maëlle n'installe ni ne lance l'app ailleurs.
- **Les fichiers ignorés dont l'app a besoin se vérifient au préflight.** Requis = `untracked.required` de
  la config, plus chaque fichier qu'un `.gitignore` nomme exactement (chemin ancré, sans joker), qui
  correspond à la liste copiée et porte le nom d'un flavor des builds QA (`--flavor staging` →
  `<app>/assets/.env.staging`). Absent du checkout principal ou hors de la liste copiée : bloquant, domaine
  **worktree**. Le worktree de revue reçoit `worktree.copy_untracked` (comme un worktree de feature, par
  `worktree_untracked.sh` : jamais un secret de signature, jamais un écrasement), puis `pr.copy_untracked`.
  Après le gauntlet, un requis absent du worktree est signalé et noté dans `untracked_missing`. Seuls les
  noms de fichiers sont affichés, jamais leur contenu.

## Conséquences

- Une revue iOS sans modèle prépare un simulateur vierge : pas de compte connecté, donc les scénarios
  connectés demandent que Thibault se connecte sur ce simulateur, ou un `ios.simulator_base` préparé.
- Créer et booter un simulateur coûte quelques dizaines de secondes par revue.
- La détection par flavor ne devine pas un fichier sans flavor dans son nom (`.env` unique, JSON de
  `--dart-define-from-file`) : il se déclare dans `untracked.required`.
- Les fichiers ignorés copiés dans un worktree de revue sont lisibles par le code de la MR, comme dans un
  worktree de feature : c'est déjà le cas des tests et du build, qui tournent sur ce code.

## Hors champ

- L'émulateur Android de la revue : `review.sh qa` garde le choix du gauntlet (`android.serial`). Même risque
  à traiter à part s'il se présente.
- `/feature` et `/fix` sans `ios.simulator_base` gardent le simulateur partagé (leur app est celle du dev, pas
  celle d'un tiers) ; cette ADR ne vise que `/reviewPR`.
