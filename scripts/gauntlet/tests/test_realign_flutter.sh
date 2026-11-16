#!/usr/bin/env bash
# Repro — test_realign.sh, côté Flutter (fake_flutter.sh, sortie au format de `flutter analyze`) : en 1c/1e, un
# fake de test/ qui n'implémente plus l'interface élargie par Arthur est à Théo (tests_to_realign.txt), pas une
# erreur qui retient Arthur ; une erreur dans lib/ bloque toujours.
source "$(dirname "$0")/fixture.sh"
need_fvm

R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
F=app/features/feat
mk_pkg "$R/$F" feat
mkdir -p "$R/$F/lib/src/domain" "$R/$F/test"
printf 'abstract class Repo {\n  int load();\n}\n' > "$R/$F/lib/src/domain/repo.dart"
printf "import 'package:feat/src/domain/repo.dart';\n\nclass FakeRepo implements Repo {\n  @override\n  int load() => 1;\n}\n" > "$R/$F/test/fake_repo.dart"
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/x
printf 'abstract class Repo {\n  int load();\n  void save();\n}\n' > "$R/$F/lib/src/domain/repo.dart"
echo "// FAKE_ANALYZE_ERROR" >> "$R/$F/test/fake_repo.dart"
pipeline "$R" x "{\"mode\":\"create\",\"package\":\"$F\",\"human_gates\":{\"spec\":{\"at\":\"2026-11-12T09:00:00Z\",\"by\":\"user\"}}}"

run_g() { OUT="$(cd "$R" && bash "$GAUNTLET" "$@" 2>&1)"; RC=$?; }

echo "1c : le fake de test/ ne compile plus"
run_g contracts x
expect_no_out "[FAIL] analyze" "analyze ne retient pas Arthur"
expect_file_has "$R/.claude/features/x/.gauntlet/tests_to_realign.txt" "$F/test/fake_repo.dart" "le fake est donné à Théo"

echo "contrôle : une erreur dans lib/"
echo "// FAKE_ANALYZE_ERROR" >> "$R/$F/lib/src/domain/repo.dart"
run_g contracts x
expect_out "[FAIL] analyze" "une erreur dans lib/ bloque"
finish
