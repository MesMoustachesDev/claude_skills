#!/usr/bin/env bash
# gauntlet.sh — gates déterministes du feature pipeline.
#
# Usage :
#   gauntlet.sh <profil|check> <feature> [options]
#   gauntlet.sh doctor
#   gauntlet.sh list
#
# Profils : contracts | red | green | clean | harden | qa   (voir gauntlet/profiles.sh)
# Checks  : n'importe quel check individuel (gauntlet.sh list)
#
# À lancer depuis n'importe où dans le repo du projet. Lit .claude/rules/feature_pipeline.md.
# Exit 0 si tout est vert, 1 sinon. Écrit .claude/features/<feature>/.gauntlet/last_<profil>.{log,json}.
set -u
set -o pipefail

GAUNTLET_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/gauntlet" && pwd)"
# shellcheck source=gauntlet/lib.sh
source "$GAUNTLET_ROOT/lib.sh"
source "$GAUNTLET_ROOT/profiles.sh"
for f in "$GAUNTLET_ROOT"/checks_*.sh "$GAUNTLET_ROOT/doctor.sh"; do source "$f"; done

target="${1:-}"
feature="${2:-}"
shift 2 2>/dev/null || true

case "$target" in
  ""|-h|--help) sed -n '2,14p' "${BASH_SOURCE[0]}"; exit 0 ;;
  list)  profiles_list; exit 0 ;;
  doctor) init_project_context ""; run_doctor; exit $? ;;
esac

[ -n "$feature" ] || die "usage: gauntlet.sh <profil|check> <feature>"
init_project_context "$feature"

checks="$(profile_checks "$target")"
if [ -z "$checks" ]; then
  if declare -F "check_${target%%:*}" >/dev/null; then checks="$target"; else die "profil ou check inconnu : $target"; fi
fi

run_checks "$target" $checks
