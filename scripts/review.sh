#!/usr/bin/env bash
# review.sh — état et mécanique de /reviewPR (~/.cache/gauntlet/review/<slug>/review.json).
#
# L'orchestrateur ne tient rien à la main : la cible, le worktree, l'état des agents, la fusion des
# remarques, le tri et la publication passent par ce script. À lancer depuis le repo du projet.
#
#   review.sh init <branche | !N | #N | URL>     résout la cible, crée l'état, imprime slug et dossiers
#   review.sh preflight <slug>                   vérifie outillage, QA, graphe, auth de la forge AVANT le gauntlet
#   review.sh decide <slug> <domaine> "<décision>"  trace ce que Thibault a tranché au préflight
#   review.sh next <slug> [--json]               étape suivante et fichier d'étape à lire
#   review.sh status <slug>                      état de la revue
#   review.sh gauntlet <slug> [--mutation]       pr_gauntlet.sh avec worktree conservé, chemin enregistré
#   review.sh agent <slug> <archi|code|qa> <running|done|skipped|failed> ["<résumé>"]
#   review.sh pass <slug> <étape>                étape passée (context, briefing, triage, posted, synthesis)
#   review.sh say <slug> "<texte>"               « en attente de toi » du cockpit
#   review.sh qa <slug> [--all-platforms]        rejoue les flows Maestro de la revue sur l'app du worktree
#   review.sh run-tests <slug> <package> <tests…> rejoue des tests existants du worktree (scénario déjà couvert)
#   review.sh probe <slug> <package> [fichiers]  joue les tests jetables de <revue>/probes/ dans le worktree, puis les retire
#   review.sh findings <slug>                    fusionne findings_<rôle>.json en findings.json (ids F1…), doublons fusionnés
#   review.sh merge <slug> F2 F3 [F4…]           fusionne des doublons que seul le sens rapproche (mémorisé)
#   review.sh cockpit-push <slug> <dossier> [--versions id=v,…]
#   review.sh triage-pull <slug> <dossier>       applique le tri fait dans le cockpit, écrit comments.md
#   review.sh post <slug> [--go]                 sans --go : les appels exacts ; avec --go : les publie
#   review.sh cleanup <slug>                     supprime le worktree de la revue (garde rapports et captures)
exec python3 "$(dirname "${BASH_SOURCE[0]}")/review/review.py" "$@"
