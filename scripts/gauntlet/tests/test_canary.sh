#!/usr/bin/env bash
# Canari — aucun secret ne finit dans ce que le pipeline écrit (repris de vibe-manager,
# CanaryScenarioTests). Un marqueur unique est mis partout où un secret vit : variables d'environnement
# de jetons, fichier .env de l'app, URL du remote git. On joue les profils, le doctor et les rapports,
# puis on cherche le marqueur dans tout ce que le pipeline a écrit (.claude/features/<nom>/, rapports).
source "$(dirname "$0")/fixture.sh"
need_fvm

CANARY="PIPELINE-CANARY-$(uuidgen)"
export GITLAB_TOKEN="glpat-$CANARY" CI_JOB_TOKEN="$CANARY" APPWRITE_API_KEY="$CANARY" \
  SENTRY_AUTH_TOKEN="$CANARY" REVENUECAT_API_KEY="$CANARY" OPENAI_API_KEY="sk-$CANARY"

R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
P=app/features/feat
mk_pkg "$R/$P" feat
echo "int d() => 1;" > "$R/$P/lib/src/data/d.dart"
printf 'void main() {}\n' > "$R/$P/test/d_test.dart"
printf 'API_KEY=%s\n' "$CANARY" > "$R/app/.env"
printf '.env\n' > "$R/.gitignore"
git -C "$R" remote add origin "https://oauth2:$CANARY@gitlab.example.com/x/y.git"
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/x
pipeline "$R" x "{\"mode\":\"create\",\"package\":\"$P\"}"

echo "profils, doctor et rapports joués avec des secrets dans l'environnement"
for profile in red green clean; do run_g "$R" "$profile" x; done
run_g "$R" doctor
DOCTOR="$OUT"
for step in tests evidence; do run_g "$R" report x "$step"; done

OUT="$(grep -rl -- "$CANARY" "$R/.claude" 2>/dev/null || echo aucun)"
expect_out "aucun" "aucun fichier de .claude/ ne contient le marqueur"
OUT="$DOCTOR"
expect_no_out "$CANARY" "le doctor ne l'affiche pas"
# Le dépôt du test lui-même (son .env, son .git/config) porte le marqueur : hors de la recherche.
OUT="$(grep -rl -- "$CANARY" "${TMPDIR:-/tmp}"/gauntlet-* "${TMPDIR:-/tmp}"/claude-gauntlet* 2>/dev/null | grep -vF "$TMP_ROOT/" || echo aucun)"
expect_out "aucun" "aucun journal temporaire du gauntlet ne le contient"

finish
