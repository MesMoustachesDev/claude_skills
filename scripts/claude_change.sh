#!/usr/bin/env bash
# claude_change.sh — un changement du pipeline (~/.claude) dans son propre worktree, puis dans main.
#
#   claude_change.sh start <nom>   worktree ~/.claude-wt/<nom> sur la branche pipeline/<nom>, depuis main
#   claude_change.sh land <nom>    le travail commité de pipeline/<nom> entre dans main (le checkout
#                                  principal, que lisent toutes les sessions), puis worktree et branche partent
#
# Le checkout principal de ~/.claude est lu par toutes les sessions : personne n'y écrit directement
# (hooks/claude-home-guard.sh). Une règle d'une ligne passe par scripts/rule_add.py ; tout le reste par ici.
set -euo pipefail
cmd="${1:-}"; name="${2:-}"
[[ "$name" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || { echo "usage : claude_change.sh start|land <nom en minuscules>"; exit 2; }
HOME_REPO="$HOME/.claude"; WT="$HOME/.claude-wt/$name"; BRANCH="pipeline/$name"

case "$cmd" in
  start)
    if [ -d "$WT" ]; then echo "déjà là : $WT ($BRANCH)"; exit 0; fi
    mkdir -p "$HOME/.claude-wt"
    git -C "$HOME_REPO" worktree add -q -b "$BRANCH" "$WT" main
    echo "worktree : $WT (branche $BRANCH). Écris et commite là ; puis claude_change.sh land $name"
    ;;
  land)
    [ -d "$WT" ] || { echo "pas de worktree $WT"; exit 2; }
    if [ -n "$(git -C "$WT" status --porcelain)" ]; then
      echo "refusé : $WT a des changements non commités. Commite-les d'abord."; git -C "$WT" status --short; exit 1
    fi
    [ "$(git -C "$HOME_REPO" branch --show-current)" = main ] || { echo "refusé : ~/.claude n'est pas sur main"; exit 1; }
    git -C "$WT" rebase -q main || { echo "conflit avec main : résous-le dans $WT (git rebase --continue), puis relance land"; exit 1; }
    git -C "$HOME_REPO" merge -q --ff-only "$BRANCH" \
      || { echo "refusé : main a des changements non commités qui touchent les mêmes fichiers (git -C ~/.claude status)"; exit 1; }
    git -C "$HOME_REPO" worktree remove "$WT"
    git -C "$HOME_REPO" branch -q -d "$BRANCH"
    echo "dans main : $(git -C "$HOME_REPO" log --oneline -1)"
    ;;
  *) echo "usage : claude_change.sh start|land <nom>"; exit 2 ;;
esac
