#!/bin/bash
# Prépare le dépôt jetable : dépendances, puis un commit qui fige les tests.
set -euo pipefail
dart pub get --offline >/dev/null
git init -q && git add -A && git -c user.email=bench@local -c user.name=bench commit -qm init
