#!/usr/bin/env bash
# Repro — commit-contracts thibault quand Thibault a supprimé un fichier de contrat par `git rm` (suppression
# déjà indexée) : `git add -- <fichiers>` refusait le chemin (« pathspec did not match any files ») et le commit
# n'avait pas lieu. Cas réel : une sous-feature d'écriture en bibliothèque, un fichier d'events retiré du brouillon.
#   la suppression indexée est commitée, le fichier sort de contracts.files ;
#   une suppression non indexée (rm seul) l'est aussi.
source "$(dirname "$0")/fixture.sh"
need_fvm

PIPELINE_SH="$TESTS_DIR/../../pipeline.sh"
R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
F=app/features/feat
mk_pkg "$R/$F" feat
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/x
pipeline "$R" x '{"mode":"create","package":"app/features/feat"}'
mkdir -p "$R/$F/lib/src/domain"
for n in a b c; do echo "abstract class C$n {}" > "$R/$F/lib/src/domain/$n.dart"; done

echo "brouillon d'Arthur"
OUT="$(cd "$R" && bash "$PIPELINE_SH" commit-contracts x draft 2>&1)"; RC=$?
expect_rc 0 "commit-contracts draft"
OUT="$(jq -r '.contracts.files | join(",")' "$R/.claude/features/x/pipeline.json")"
expect_out "$F/lib/src/domain/b.dart" "b.dart est un fichier de contrat"

echo "Thibault : git rm b.dart, rm c.dart, édite a.dart"
git -C "$R" rm -q "$F/lib/src/domain/b.dart"
rm "$R/$F/lib/src/domain/c.dart"
echo "abstract class A { void f(); }" > "$R/$F/lib/src/domain/a.dart"
OUT="$(cd "$R" && bash "$PIPELINE_SH" commit-contracts x thibault 2>&1)"; RC=$?
expect_rc 0 "commit-contracts thibault accepte les suppressions"
expect_no_out "pathspec" "aucun refus de chemin"
OUT="$(git -C "$R" show --name-status --format= HEAD)"
expect_out "$F/lib/src/domain/b.dart" "la suppression indexée de b.dart est dans le commit"
expect_out "$F/lib/src/domain/c.dart" "la suppression de c.dart est dans le commit"
expect_out "$F/lib/src/domain/a.dart" "l'édition de a.dart est dans le commit"
OUT="$(git -C "$R" status --porcelain -- "$F")"
[ -z "$OUT" ] && _pass "rien ne reste à commiter dans le package" || _fail "reste à commiter"
OUT="$(jq -r '.contracts.files | join(",")' "$R/.claude/features/x/pipeline.json")"
expect_no_out "b.dart" "b.dart sort de contracts.files"
expect_out "$F/lib/src/domain/a.dart" "a.dart reste dans contracts.files"

finish
