#!/usr/bin/env bash
# Repro — worktree_untracked.sh : un worktree de feature reçoit les fichiers gitignorés du checkout principal
# dont le build a besoin, jamais un secret de signature, jamais en écrasant.
# Cas réel : le worktree de import_cancel_sync n'avait ni features/env/.env.staging.secrets ni
# .env.prod.secrets (lus par envied à la génération de env_*.g.dart).
source "$(dirname "$0")/fixture.sh"
WU="$TESTS_DIR/../../worktree_untracked.sh"
R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
mkdir -p "$R/app/features/env" "$R/app/android" "$R/app/ios/Runner" "$R/app/build"
printf '*.secrets\n.ci.env\nlocal.properties\nkey.properties\n*.jks\nbuild/\nGoogleService-Info.plist\n.claude/worktrees/\n' > "$R/.gitignore"
commit "$R" init >/dev/null
echo s > "$R/app/features/env/.env.staging.secrets"; echo c > "$R/app/.ci.env"; echo sdk > "$R/app/android/local.properties"
echo k > "$R/app/android/key.properties"; echo j > "$R/app/android/upload.jks"; echo b > "$R/app/build/x.env"
echo p > "$R/app/ios/Runner/GoogleService-Info.plist"
W="$R/.claude/worktrees/feature-x"; git -C "$R" worktree add -q "$W" -b feature/x
mkdir -p "$W/app/android"; echo mine > "$W/app/android/local.properties"
run_w() { OUT="$(bash "$WU" "$@" 2>&1)"; RC=$?; }

echo "dry-run"
run_w "$W" --dry-run
expect_out "à copier  app/features/env/.env.staging.secrets" ".env.*.secrets listé"
expect_out "à copier  app/ios/Runner/GoogleService-Info.plist" "config Firebase listée"
[ -e "$W/app/.ci.env" ] && _fail "dry-run n'écrit rien" || _pass "dry-run n'écrit rien"
echo "copie"
run_w "$W"
expect_rc 0 "copie (exit 0)"
expect_file_has "$W/app/features/env/.env.staging.secrets" s ".env.staging.secrets copié"
expect_file_has "$W/app/.ci.env" c ".ci.env copié"
expect_file_has "$W/app/android/local.properties" mine "fichier déjà là jamais écrasé"
expect_no_out "key.properties" "key.properties ne correspond pas au motif par défaut"
expect_no_out "build/x.env" "sortie de build jamais copiée"
expect_no_out "worktrees/" "autre worktree jamais copié"
echo "secret de signature refusé même s'il est demandé"
write_cfg "$R" "worktree.copy_untracked = **/*.properties, **/*.jks"
run_w "$W"
expect_out "refusé    app/android/key.properties (secret de signature)" "key.properties refusé"
expect_out "refusé    app/android/upload.jks (secret de signature)" "keystore refusé"
[ -e "$W/app/android/upload.jks" ] && _fail "keystore absent du worktree" || _pass "keystore absent du worktree"
echo "--patterns : la liste en vigueur (lue par le préflight de /reviewPR)"
OUT="$(bash "$WU" --patterns "$R")"
expect_out "**/*.properties" "liste de la config"
write_cfg "$R" "worktree.copy_untracked = none"
OUT="$(bash "$WU" --patterns "$R")"; [ -z "$OUT" ] && _pass "none : liste vide" || _fail "none : liste vide"
echo "reprise : rien à copier"
write_cfg "$R"
run_w "$W"
expect_out "résumé : 0 copié(s)" "seconde passe idempotente"
finish
