#!/usr/bin/env bash
# Repro — `gauntlet.sh report <nom> contracts` en 1e sur un module Android : « section contracts absente du
# rapport ». report.py ne voyait du code que dans <package>/lib (Flutter) ; un module Android (src/main) n'avait ni
# contrats, ni scénarios, ni tests. Il lit désormais les dossiers du langage (stack.ini → src_dirs, test_dirs).
source "$(dirname "$0")/fixture.sh"

R="$TMP_ROOT/repo"; mk_repo "$R"
M=feature/login; P="$R/$M"; K="src/main/kotlin/com/x/login"
mkdir -p "$R/.claude/rules" "$P/$K/domain"
{
  echo '# test'; echo '```ini'
  echo 'package_path = feature/{name}'
  echo 'features_root = feature'
  echo 'base_branch = develop'
  echo '```'
} > "$R/.claude/rules/feature_pipeline.md"
echo 'include(":feature:login")' > "$R/settings.gradle.kts"
printf 'plugins {\n  id("com.android.library")\n}\n' > "$P/build.gradle.kts"
commit "$R" base >/dev/null
git -C "$R" checkout -q -b feature/login
printf 'package com.x.login.domain\n\ninterface LoginRepository {\n    fun login(): Int\n}\n' > "$P/$K/domain/LoginRepository.kt"
SHA="$(commit "$R" draft)"
pipeline "$R" login "{\"mode\":\"extend\",\"package\":\"$M\",\"contracts\":{\"draft_sha\":\"$SHA\",\"files\":[\"$M/$K/domain/LoginRepository.kt\"]}}"

echo "report contracts — module Android"
OUT="$(cd "$R" && bash "$GAUNTLET" report login contracts 2>&1)"; RC=$?
expect_rc 0 "report contracts"
expect_no_out "absente du rapport" "la section existe"
expect_file_has "$R/.claude/features/login/report.html" "Contrats (dans le code)" "report.html a la section contrats"
expect_file_has "$R/.claude/features/login/report.html" "LoginRepository.kt" "elle nomme le fichier de contrat"
finish
