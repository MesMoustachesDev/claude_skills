#!/bin/bash
set -euo pipefail
dart pub get --offline >/dev/null
git init -q && git add -A && git -c user.email=bench@local -c user.name=bench commit -qm init
