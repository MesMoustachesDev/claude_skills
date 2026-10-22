#!/usr/bin/env bash
# pipeline.sh — état et comptabilité du feature pipeline (.claude/features/<nom>/pipeline.json).
#
# L'orchestrateur ne calcule plus l'étape suivante ni ne réécrit pipeline.json à la main : il appelle
# ce script, qui décide de façon déterministe. À lancer depuis le worktree de la feature.
#
#   pipeline.sh next <nom> [--json]              étape suivante, fichier d'étape à lire, entrées à passer
#   pipeline.sh status <nom>                     tableau d'état (commande /feature <nom> status)
#   pipeline.sh init <nom> --mode M --package P --base B
#   pipeline.sh size <nom> S|M|L "<raison>"      gabarit (reclassement tracé dans size_changes)
#   pipeline.sh pass <nom> <étape>               stages.<étape> = PASSED
#   pipeline.sh skip <nom> <étape> "<raison>"    stages.<étape> = SKIPPED (gabarit)
#   pipeline.sh gate <nom> <point> [k=v ...]     human_gates.<point> = {at, by: user, k: v…}
#   pipeline.sh loop <nom> <boucle>              loops.<boucle> += 1 ; exit 3 au-delà du plafond
#   pipeline.sh debt <nom> <source> <fichier> "<problème>" [--line N]
#   pipeline.sh accept <nom> <étape> "<raison>"  trace une acceptation du dev (evidence)
#   pipeline.sh set <nom> <clé.pointée> <json>   écriture libre (ex. suggestions.S1 '{"decision":"applied"}')
#   pipeline.sh after-architect <nom>            après chaque retour d'Arthur avant l'étape 2 (0c, 0e)
#   pipeline.sh contracts-files <nom>            recalcule contracts.files (arbre de travail)
#   pipeline.sh commit-contracts <nom> draft|thibault|reedit ["<quoi>"] [fichiers…]
#   pipeline.sh freeze <nom>                     gel des tests (3b)
#   pipeline.sh refreeze <nom> <cause> <étape>   re-gel (cause : hygiene|technique|contrat|spec|interne)
#   pipeline.sh say <nom> "<texte>" [--report <étape>] [--ask <id> --options "A|B"]  « en attente de toi » du cockpit (+ étape du rapport)
#   pipeline.sh cockpit-push <nom> <dossier> [--versions id=v,…] [--hub-version N]  documents de la page de la feature (writes) et de sa ligne dans l'accueil (hub_writes)
#   pipeline.sh cockpit-pull <nom> <dossier>     applique les éditions de contrats lues du cockpit
#   pipeline.sh cockpit-page <nom> <dossier>     copie de la page du cockpit pour cette feature (à publier au démarrage)
#   pipeline.sh page-deleted <nom>               la page de la feature a été supprimée (carte gardée dans l'accueil)
exec python3 "$(dirname "${BASH_SOURCE[0]}")/pipeline/pipeline.py" "$@"
