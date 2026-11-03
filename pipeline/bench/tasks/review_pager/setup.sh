#!/bin/bash
# Base commitée, puis le changement à relire en second commit.
set -euo pipefail
dart pub get --offline >/dev/null
git init -q && git add -A && git -c user.email=bench@local -c user.name=bench commit -qm base
cp -R "$TASK_DIR/change/." .
git add -A && git -c user.email=bench@local -c user.name=bench commit -qm "feat: pageCount et chargement"
