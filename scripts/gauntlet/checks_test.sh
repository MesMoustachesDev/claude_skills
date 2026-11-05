#!/usr/bin/env bash
# checks_test.sh — tests, rouge/vert, gel des tests, couverture, mutation. Sourcé par gauntlet.sh.

TEST_REPORT="" # défini par run_tests_json
TEST_NONE=0    # 1 : le package (ou sa couche) n'a aucun fichier de test, rien n'a tourné

# --- Packages de writes.extra modifiés par la feature ------------------------------------------------
# Une feature extend peut ouvrir d'autres packages (pipeline.json → writes_extra, ou les zones permanentes du
# projet) et y écrire du code et des tests. Seuls comptent ceux que la feature a réellement modifiés depuis la
# base (arbre de travail compris) ; une zone permanente (router, l10n, dskit…) qu'elle n'a pas touchée ne fait
# rien tourner.
#   extra_changed_packages : lib/ ou test/ modifié → analyze et format (la compilation du package est en jeu).
#   extra_test_packages    : test/ modifié, la feature y a écrit des tests → red_check, test, test_freeze_check,
#                            test_names, coverage. Un package où elle n'a touché que lib/ (un export dskit, des
#                            clés l10n) n'a pas de test de la feature à prouver : sa suite ne tourne pas pour rien
#                            (celle de dskit ne se charge même pas sans native assets), analyze couvre sa compilation.
# Pipeline seulement : hors pipeline.json, ou avec GAUNTLET_PACKAGE (pr_gauntlet.sh et fix_gauntlet.sh passent
# déjà sur chaque package touché), aucun package supplémentaire.
extra_changed_packages() {
  [ -f "$FEATURE_DIR/pipeline.json" ] && [ -z "${GAUNTLET_PACKAGE:-}" ] || return 0
  local base pkg d hit dirs="${*:-lib test}"; base="$(merge_base)"
  while IFS= read -r pkg; do
    [ -n "$pkg" ] && [ -f "$PROJECT_ROOT/$pkg/pubspec.yaml" ] || continue
    hit=""
    for d in $dirs; do
      hit="$( { diff_names "$base" "$pkg/$d"; untracked "$pkg/$d"; } 2>/dev/null | head -1)"
      [ -n "$hit" ] && break
    done
    [ -n "$hit" ] && printf '%s\n' "$pkg"
  done < <(extra_packages)
}
extra_test_packages() { extra_changed_packages test; }
# each_extra_package <liste> <commande…> — <commande> sur chaque package que rend <liste>
# (extra_changed_packages | extra_test_packages), via with_package. Échoue si elle échoue sur l'un d'eux.
each_extra_package() {
  local list="$1" pkg rc=0; shift
  while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    info "package $pkg (writes.extra, modifié par la feature)"
    with_package "$pkg" "$@" || rc=1
  done < <("$list")
  return $rc
}
# feature_tests_here — le périmètre du package courant (couche comprise) contient un fichier de test.
feature_tests_here() { scope_files "$PKG_REL/" | grep -qE '^test/.*_test\.dart$'; }

# run_tests_json — lance flutter test --reporter json, conserve le rapport. Retourne le code de flutter test.
# Aucun fichier de test (pas de test/, couche vide) : TEST_NONE=1, échec signalé, ou simple info sous
# TESTS_OPTIONAL=1 (un package parmi plusieurs, cf. check_test).
run_tests_json() {
  TEST_REPORT="$GAUNTLET_OUT/test_report.jsonl"; TEST_NONE=0
  local none=ko; [ "${TESTS_OPTIONAL:-0}" = 1 ] && none=info
  [ -d "$PKG_DIR/test" ] || { TEST_NONE=1; $none "pas de dossier test/ dans $PKG_REL"; : > "$TEST_REPORT"; return 1; }
  # Couche : seuls les tests de la moitié tournent, ceux que l'autre écrit en même temps ne la cassent pas.
  local targets=""
  if [ -n "${LAYER:-}" ]; then
    targets="$(layer_files test | grep '_test\.dart$' | tr '\n' ' ')"
    [ -n "$targets" ] || { TEST_NONE=1; $none "aucun fichier de test dans la couche $LAYER ($PKG_REL)"; : > "$TEST_REPORT"; return 1; }
  fi
  TESTS_RAN="${TESTS_RAN:-} $TEST_REPORT"   # rapports produits par ce run (test_names les réutilise)
  # shellcheck disable=SC2086
  (cd "$PKG_DIR" && $FLUTTER test --reporter json --no-pub $targets > "$TEST_REPORT" 2>"$GAUNTLET_OUT/test_stderr.log")
}

# test_results — une ligne JSON par test non caché : {file, name, result, skipped}
test_results() {
  jq -c -s '
    (map(select(.type=="testStart")) | map({key:(.test.id|tostring), value:.test}) | from_entries) as $t
    # The suite path is the test file. A testWidgets url points into flutter_test (widget_tester.dart),
    # its root_url at the file: read the suite first, root_url next, url last.
    | (map(select(.type=="suite")) | map({key:(.suite.id|tostring), value:.suite.path}) | from_entries) as $s
    | map(select(.type=="testDone" and (.hidden|not)))
    | map(. as $d | $t[($d.testID|tostring)] as $x
        | {file: (($s[($x.suiteID|tostring)] // $x.root_url // $x.url // "?") | sub("^file://"; "")),
           name: $x.name, result: $d.result, skipped: $d.skipped})
    | .[]' < <(grep '^{' "$TEST_REPORT") 2>/dev/null | sed "s#\"file\":\"$PKG_DIR/#\"file\":\"#"
  # grep '^{' : the engine may print native log lines on stdout ("Shell: [ERROR:flutter/runtime/…]"),
  # which would make the whole JSON report unreadable.
}

# test_pkg — la suite du package courant. 0 vert, 1 rouge ; 3 sous TESTS_OPTIONAL=1 si rien n'a tourné faute
# de fichier de test (sans TESTS_OPTIONAL, c'est un échec).
test_pkg() {
  local rc total failed
  run_tests_json; rc=$?
  [ "$TEST_NONE" = 1 ] && [ "${TESTS_OPTIONAL:-0}" = 1 ] && return 3
  total="$(test_results | wc -l | tr -d ' ')"
  failed="$(test_results | jq -r 'select(.result!="success") | "  ✗ \(.file) — \(.name)"')"
  [ "$total" = 0 ] && { ko "aucun test exécuté"; tail -20 "$GAUNTLET_OUT/test_stderr.log"; return 1; }
  if [ -n "$failed" ]; then printf '%s\n' "$failed"; fi
  info "$total test(s), $(printf '%s' "$failed" | grep -c '✗' || true) échec(s)"
  [ "$rc" = 0 ] && [ -z "$failed" ]
}

# each_test_package <fonction> <message si rien n'a tourné> — <fonction> (0 ok, 1 échec, 3 rien à juger) sur le
# package de la feature puis sur chaque package de extra_test_packages. Un package sans rien à juger (pas de
# test dans la couche, pas de test de la feature) ne fait pas échouer ; il en faut un au moins qui juge.
# Sans package supplémentaire : <fonction> seule, comportement d'un package unique inchangé.
each_test_package() {
  local fn="$1" none_msg="$2" extras pkg r rc=0 judged=0
  extras="$(extra_test_packages)"
  [ -n "$extras" ] || { "$fn"; return; }
  info "package $PKG_REL"
  TESTS_OPTIONAL=1 "$fn"; r=$?
  case "$r" in 0) judged=1 ;; 3) ;; *) judged=1; rc=1 ;; esac
  while IFS= read -r pkg; do
    info "package $pkg (writes.extra, tests de la feature)"
    TESTS_OPTIONAL=1 with_package "$pkg" extra_test_run "$fn"; r=$?
    case "$r" in 0) judged=1 ;; 3) ;; *) judged=1; rc=1 ;; esac
  done <<< "$extras"
  [ "$judged" = 1 ] && return $rc
  [ -z "$none_msg" ] && return 3     # l'appelant tranche (red_check : rejeu pass_base)
  ko "$none_msg"; return 1
}
# extra_test_run <fonction> — <fonction> dans un package de writes.extra, seulement si le périmètre (couche
# comprise) y contient un test de la feature : la moitié présentation ne relance pas toute la suite de pictures
# parce que la moitié data y a écrit ses tests. Sinon rien à juger (3).
extra_test_run() {
  feature_tests_here || { info "aucun test de la feature dans $PKG_REL${LAYER:+ (couche $LAYER)} : suite non lancée"; return 3; }
  "$@"
}

check_test() {
  # Packages modifiés sans test de la feature : nommés, pas lancés (voir extra_changed_packages).
  local pkg tested; tested="$(extra_test_packages)"
  while IFS= read -r pkg; do
    [ -n "$pkg" ] && ! grep -qxF "$pkg" <<<"$tested" && info "package $pkg (writes.extra) : modifié sans test de la feature, suite non lancée (analyze le compile)"
  done < <(extra_changed_packages)
  each_test_package test_pkg "aucun test exécuté (ni dans $PKG_REL, ni dans les packages de writes.extra modifiés)"
}

# red_check — après TEST-WRITER : la suite compile, et chaque fichier de test contient ≥ 1 échec.
# Les tests qui passent déjà contre les stubs sont listés (information), pas bloquants.
# Packages de writes.extra modifiés : chacun est jugé de même ; un package sans fichier de test de la feature
# ne fait pas échouer, mais il en faut au moins un dans le périmètre, tous packages confondus.
check_red_check() {
  each_test_package red_pkg ""; local r=$?
  [ "$r" = 3 ] || return "$r"
  # Aucun package n'a de fichier de test dans le périmètre.
  [ -n "${PASS_BASE:-}" ] && { info "aucun fichier de test modifié $(pass_label), ni dans $PKG_REL ni dans les packages de writes.extra : le rejeu n'ajoute pas de test ici"; return 0; }
  ko "aucun fichier de test dans le périmètre ($PKG_REL et packages de writes.extra modifiés) — le test-writer n'a rien ajouté"; return 1
}
# red_pkg — red_check sur le package courant. 0 ok, 1 échec ; 3 sous TESTS_OPTIONAL=1 si aucun fichier de test
# de la feature dans ce package.
red_pkg() {
  run_tests_json || true
  # Périmètre de la passe : lors d'un rejeu (pass_base), les tests d'une passe déjà implémentée sont verts
  # et doivent l'être (non-régressions gelées) ; seuls les tests écrits depuis doivent être rouges.
  local total green_files passing SCOPE_FILE SCOPE_ALL; use_pass_scope
  total="$(test_results | wc -l | tr -d ' ')"
  if [ "$total" = 0 ]; then
    [ "$TEST_NONE" = 1 ] && [ "${TESTS_OPTIONAL:-0}" = 1 ] && return 3
    ko "aucun test exécuté — la suite ne compile probablement pas"; tail -30 "$GAUNTLET_OUT/test_stderr.log"; return 1
  fi
  # mode extend : seuls les fichiers de test nouveaux ou modifiés doivent être rouges
  local scoped_files
  scoped_files="$(test_results | jq -r '.file' | sort -u | filter_scope_files "$PKG_REL/")"
  if [ -z "$scoped_files" ] && [ "${TESTS_OPTIONAL:-0}" = 1 ]; then
    info "$total test(s), aucun fichier de test de la feature dans $PKG_REL"; return 3
  fi
  if [ -z "$scoped_files" ] && [ -n "${PASS_BASE:-}" ]; then
    info "$total test(s), aucun fichier de test du package modifié $(pass_label) : le rejeu n'ajoute pas de test ici"; return 0
  fi
  if [ -z "$scoped_files" ]; then ko "aucun fichier de test dans le périmètre — le test-writer n'a rien ajouté"; return 1; fi
  green_files="$(test_results | jq -r -s 'group_by(.file) | map(select(all(.[]; .result=="success")) | .[0].file) | .[]' | grep -xF -f <(printf '%s\n' "$scoped_files"))"
  passing="$(test_results | jq -r 'select(.result=="success") | "\(.file):0 — \(.name)"' | filter_scope_lines "$PKG_REL/" | sed 's/^/  · /; s/:0 —/ —/')"
  [ -n "$passing" ] && { info "tests du périmètre qui passent déjà contre les stubs :"; printf '%s\n' "$passing"; }
  if [ -n "$green_files" ]; then
    printf '%s\n' "$green_files" | sed 's/^/  ✗ tout vert : /'
    ko "ces fichiers ne testent rien que les stubs ne satisfassent déjà"
    return 1
  fi
  info "$total test(s), $(printf '%s\n' "$scoped_files" | wc -l | tr -d ' ') fichier(s) dans le périmètre, rouge dans chacun"
}

# test_names — écrit .claude/features/<f>/tests.md pour le skim du dev. Toujours vert.
# Packages de writes.extra modifiés : leurs fichiers de test de la feature suivent, préfixés du package.
check_test_names() {
  [ -f "$TEST_REPORT" ] || run_tests_json || true
  local out="$FEATURE_DIR/tests.md" all="$GAUNTLET_OUT/test_names.jsonl"
  { test_results; each_extra_package extra_test_packages test_names_pkg; } | grep '^{' > "$all"
  {
    printf '# Tests — %s\n\n' "$FEATURE"
    printf '_%s tests. « passe déjà » = vert contre les stubs, donc ne contraint pas l'"'"'implémentation._\n' "$(grep -c . "$all")"
    jq -r -s 'group_by(.file)[] | "\n## \(.[0].file)\n" + (map("- " + .name + (if .result=="success" then "  _(passe déjà)_" else "" end)) | join("\n"))' "$all"
  } > "$out"
  info "écrit : ${out#$PROJECT_ROOT/}"
}
# test_names_pkg — résultats du package courant (writes.extra), limités aux fichiers de test de la feature,
# chemins préfixés du package. Rapport réutilisé s'il vient de ce run (red_check), sinon la suite tourne.
test_names_pkg() {
  TEST_REPORT="$GAUNTLET_OUT/test_report.jsonl"
  case " ${TESTS_RAN:-} " in *" $TEST_REPORT "*) ;; *) TESTS_OPTIONAL=1 run_tests_json || true ;; esac
  local files; files="$(test_results | jq -r '.file' | sort -u | filter_scope_files "$PKG_REL/")"
  [ -n "$files" ] || return 0
  # shellcheck disable=SC2086
  test_results | jq -c --arg p "$PKG_REL/" 'select(.file | IN($ARGS.positional[])) | .file = $p + .file' --args $files
}

# test_freeze_check <strict|additive> — les tests gelés (SHA dans pipeline.json) sont intacts.
#   strict   : aucun changement, aucun fichier nouveau dans test/
#   additive : seuls des fichiers AJOUTÉS sont tolérés (hardener) ; aucune modification, aucune suppression
# Surveille test/ du package et celui de chaque package de writes.extra modifié (gelés avec lui, pipeline.sh freeze).
check_test_freeze_check() {
  local mode="${1:-strict}" sha changes="" untracked="" rc=0 pkg
  sha="$(pipeline_get .tests_freeze_sha)"
  [ -n "$sha" ] || { ko "pas de gel enregistré (pipeline.json → tests_freeze_sha)"; return 1; }
  for pkg in "$PKG_REL" $(extra_test_packages); do
    changes="$changes$(diff_name_status "$sha" "$pkg/test" 2>/dev/null)"$'\n'
    untracked="$untracked$(untracked "$pkg/test" 2>/dev/null)"$'\n'
  done
  changes="$(printf '%s' "$changes" | grep -v '^$')"; untracked="$(printf '%s' "$untracked" | grep -v '^$')"
  # Hugo's additions (pipeline.json → hardening.tests_added, relative to the package) are allowed after
  # the freeze, as long as they are new files: an untracked or added file only, never a modification.
  local hugo f
  hugo="$(pipeline_get '.hardening.tests_added[]?' | grep -v '^$' | sed "s#^#$PKG_REL/#")"
  if [ -n "$hugo" ]; then
    while IFS= read -r f; do
      untracked="$(printf '%s\n' "$untracked" | grep -vxF "$f")"
      changes="$(printf '%s\n' "$changes" | grep -vxF "$(printf 'A\t%s' "$f")")"
    done <<< "$hugo"
    changes="$(printf '%s' "$changes" | grep -v '^$')"; untracked="$(printf '%s' "$untracked" | grep -v '^$')"
  fi
  case "$mode" in
    strict)
      [ -n "$changes" ]   && { printf '%s\n' "$changes" | sed 's/^/  /'; rc=1; }
      [ -n "$untracked" ] && { printf '%s\n' "$untracked" | sed 's/^/  ?? /'; rc=1; }
      [ "$rc" = 1 ] && ko "test/ a changé depuis le gel ($sha)"
      ;;
    additive)
      local bad; bad="$(printf '%s\n' "$changes" | grep -vE '^A' | grep -v '^$')"
      [ -n "$bad" ] && { printf '%s\n' "$bad" | sed 's/^/  /'; ko "seuls des ajouts de fichiers sont tolérés dans test/"; rc=1; }
      [ -n "$untracked" ] && info "nouveaux fichiers : $(printf '%s' "$untracked" | tr '\n' ' ')"
      ;;
    *) die "mode inconnu : $mode" ;;
  esac
  [ "$rc" = 0 ] && info "gel $sha respecté ($mode)"
  return $rc
}

# new_lines <base> <chemin> — « fichier:ligne » des lignes ajoutées depuis <base>, fichiers non suivis compris,
# SANS les lignes seulement déplacées (code existant découpé, extrait dans un widget ou un autre fichier,
# réindenté) : git --color-moved les reconnaît. Index temporaire (intent-to-add des non-suivis), le vrai
# index n'est pas touché. Écrit le nombre de lignes déplacées écartées dans $GAUNTLET_OUT/moved_lines.count.
new_lines() {
  local base="$1" path="$2" idx moved_total=0 m
  while _read_site; do
    idx="$(mktemp)"
    cp "$(git -C "$SITE_DIR" rev-parse --path-format=absolute --git-path index)" "$idx"
    git -C "$SITE_DIR" ls-files --others --exclude-standard -z -- "${SITE_PATHS[@]}" \
      | GIT_INDEX_FILE="$idx" xargs -0 git -C "$SITE_DIR" add -N -- 2>/dev/null
    GIT_INDEX_FILE="$idx" git -C "$SITE_DIR" \
        -c color.diff.new=green -c color.diff.old=red -c color.diff.newMoved=blue -c color.diff.newMovedAlternative=blue \
        -c color.diff.newMovedDimmed=blue -c color.diff.newMovedAlternativeDimmed=blue \
        diff --color=always --color-moved=plain --color-moved-ws=allow-indentation-change -U0 --ignore-submodules=all \
        --src-prefix="a/$SITE_PRE" --dst-prefix="b/$SITE_PRE" "$SITE_REV" -- "${SITE_PATHS[@]}" \
      | awk -v out="$GAUNTLET_OUT/moved_lines.count" '
          { raw=$0; plain=$0; gsub(/\033\[[0-9;]*m/, "", plain) }
          plain ~ /^\+\+\+ b\// { f=substr(plain,7); next }
          plain ~ /^@@/ { split(plain, h, " "); split(h[3], a, ","); n=substr(a[1],2)+0; next }
          plain ~ /^\+/ { if (raw ~ /^\033\[34m/) moved++; else print f":"n; n++ }
          END { print moved+0 > out }'
    rm -f "$idx"
    m="$(cat "$GAUNTLET_OUT/moved_lines.count" 2>/dev/null)"; moved_total=$((moved_total + ${m:-0}))
  done < <(git_sites "$base" "$path")
  printf '%s\n' "$moved_total" > "$GAUNTLET_OUT/moved_lines.count"
}

# coverage — couverture des lignes ajoutées depuis base_branch, hors lignes seulement déplacées (new_lines)
# et seulement reformatées (drop_format_only).
# Packages de writes.extra modifiés : même seuil, package par package, pour ceux où la feature a écrit des
# tests (elle y prétend du code testé). Un package modifié sans test de la feature (clés l10n et code généré,
# retouche d'un widget dskit) est nommé, pas jugé : sa suite n'a pas été écrite pour ces lignes.
check_coverage() {
  local rc=0
  coverage_pkg || rc=1
  each_extra_package extra_test_packages coverage_extra_pkg || rc=1
  return $rc
}
coverage_extra_pkg() {
  feature_tests_here || { info "pas de test de la feature dans $PKG_REL : couverture non jugée"; return 0; }
  coverage_pkg
}
coverage_pkg() {
  local thr lcov base changed rc moved formatted
  thr="$(cfg threshold.coverage_changed 90)"
  # shellcheck disable=SC2086
  (cd "$PKG_DIR" && $FLUTTER test --coverage --no-pub >/dev/null 2>&1) || { ko "flutter test --coverage a échoué"; return 1; }
  lcov="$PKG_DIR/coverage/lcov.info"
  [ -f "$lcov" ] || { ko "pas de $lcov"; return 1; }
  base="$(merge_base)"
  changed="$GAUNTLET_OUT/changed_lines.txt"
  new_lines "$base" "$PKG_REL/lib" | drop_generated | drop_format_only "$base" | sort -u > "$changed"
  moved="$(cat "$GAUNTLET_OUT/moved_lines.count" 2>/dev/null)"
  [ "${moved:-0}" -gt 0 ] && info "$moved ligne(s) seulement déplacée(s) (code existant découpé ou extrait) : hors couverture"
  formatted="$(cat "$GAUNTLET_OUT/format_lines.count" 2>/dev/null)"
  [ "${formatted:-0}" -gt 0 ] && info "$formatted ligne(s) seulement reformatée(s) (dart format) : hors couverture"
  if [ ! -s "$changed" ]; then info "aucune ligne modifiée dans lib/ depuis $base"; return 0; fi
  awk -v pkg="$PKG_REL" -v thr="$thr" -v changed="$changed" '
    BEGIN { while ((getline l < changed) > 0) ch[l]=1 }
    /^SF:/ { f=substr($0,4); sub(/^\.\//,"",f); if (f !~ "^"pkg"/") f=pkg"/"f }
    /^DA:/ { split(substr($0,4),a,","); k=f":"a[1]; if (k in ch) { tot++; if (a[2]+0>0) cov++; else miss[k]=1 } }
    END {
      if (tot==0) { print "   aucune ligne modifiée n'"'"'est exécutable (rien à couvrir)"; exit 0 }
      pct=cov*100/tot; printf "   lignes modifiées couvertes : %d/%d (%.1f%%), seuil %d%%\n", cov, tot, pct, thr
      n=0; for (k in miss) { if (n<30) print "   ✗ " k; n++ }
      if (n>30) print "   … et " (n-30) " autres"
      exit (pct+0.0001 >= thr) ? 0 : 1
    }' "$lcov"
}

# mutation — mutation_test sur les globs configurés. Score global ≥ threshold.mutation.
#
# Un run mutation_test PAR FICHIER, limité aux tests de ce fichier : `foo.dart` → `test/**/foo_test.dart`.
# Sans test homonyme : tous les tests unitaires. Les tests d'acceptance (test/<x>_test.dart généré depuis
# test/<x>.feature) ne tournent jamais en mutation : trop lents, et un mutant que seule l'acceptance tue
# doit recevoir un test unitaire. Avant : toute la suite (acceptance comprise) relancée pour chaque mutant.
# Le coût d'un mutant n'est pas la compilation (3 à 8 s) mais les tests qu'il fait bloquer (un flux qui
# n'émet plus attend le timeout de 30 s). D'où `--fail-fast --timeout <mutation.test_timeout, 10s>`.
# Parallélisme : mutation.workers (défaut 4) clones APFS (`cp -c`, copie à l'écriture) de app_dir ; chaque
# worker mute dans son clone, le dépôt n'est jamais muté. Couverture : lcov de toute la suite, passé à
# mutation_test qui ne mute que les lignes couvertes (un mutant non couvert survit par construction).
# app_dir = "." : un seul worker, en place, avec restauration garantie des fichiers mutés.
mutation_unit_tests() {
  (cd "$PKG_DIR" && find test -name '*_test.dart' -not -path '*/.dart_tool/*' | sort | while IFS= read -r t; do
      [ -f "${t%_test.dart}.feature" ] || printf '%s\n' "$t"; done)
}
mutation_tests_for() {
  local stem own
  stem="$(basename "$1" .dart)"
  # `foo_test.dart` et les fichiers ajoutés au durcissement `foo_<x>_test.dart` (ex. foo_mutation_test.dart)
  own="$(cd "$PKG_DIR" && find test \( -name "${stem}_test.dart" -o -name "${stem}_*_test.dart" \) -not -path '*/.dart_tool/*' | sort | while IFS= read -r t; do
      [ -f "${t%_test.dart}.feature" ] || printf '%s\n' "$t"; done)"
  if [ -n "$own" ]; then printf '%s\n' "$own"; else mutation_unit_tests; fi
}
mutation_restore() {
  local o
  for o in "$GAUNTLET_OUT/mutation-orig"/*; do
    [ -f "$o" ] && cp "$o" "$PKG_DIR/$(basename "$o" | tr '%' '/')"
  done
}
# Tâches : un fichier est découpé en tranches de mutation.shard_lines lignes (défaut 100), chacune son xml,
# pour qu'un gros fichier se répartisse sur tous les workers. File partagée : chaque worker prend la
# tâche suivante dès qu'il est libre (verrou mkdir), au lieu d'un lot fixé d'avance.
# Passage à vide : avant sa première tranche d'un fichier, un worker lance les tests de ce fichier sans
# mutant, sous la même charge. S'ils échouent (test lent > timeout sous charge, test cassé), le fichier est
# marqué BASELINE_KO et le gate échoue, au lieu de compter des mutants faussement tués.
#
# mutation_plan <fichier> — écrit les xml des tranches et ajoute « fichier<TAB>tranche<TAB>xml » à la file.
mutation_plan() {
  local f="$1" slug lines tests tmo k xml shard
  slug="$(printf '%s' "$f" | tr '/' '%')"
  tmo="$(cfg mutation.test_timeout 10s)"; shard="$(cfg mutation.shard_lines 100)"
  if [ "$SCOPE_ALL" != 1 ] && ! grep -qx "$PKG_REL/$f" "$SCOPE_FILE"; then
    lines="$(grep "^$PKG_REL/$f:" "$SCOPE_FILE" | cut -d: -f2 | sort -n)"   # lignes ajoutées seulement
  else
    lines="$(seq 1 "$(wc -l < "$PKG_DIR/$f" | tr -d ' ')")"
  fi
  [ -n "$lines" ] || return 0
  tests="$(mutation_tests_for "$f" | tr '\n' ' ')"
  # A trailing space becomes an empty argument in mutation_test's command: flutter test then loads every test.
  tests="${tests% }"
  printf '%s\n' "$tests" > "$GAUNTLET_OUT/mutation-tests-$slug.txt"
  for k in $(printf '%s\n' "$lines" | awk -v s="$shard" '{print int(($1-1)/s)}' | sort -un); do
    xml="$GAUNTLET_OUT/mutation-$slug#$k.xml"
    {
      printf '<?xml version="1.0" encoding="UTF-8"?>\n<mutations version="1.2">\n  <files>\n    <file>%s\n' "$f"
      # lignes de la tranche → plages contiguës <lines begin end/>
      printf '%s\n' "$lines" | awk -v s="$shard" -v k="$k" 'int(($1-1)/s)==k' | awk 'NR==1{b=$1;e=$1;next} $1==e+1{e=$1;next} {printf "      <lines begin=\"%d\" end=\"%d\"/>\n",b,e; b=$1;e=$1} END{if(NR) printf "      <lines begin=\"%d\" end=\"%d\"/>\n",b,e}'
      printf '    </file>\n  </files>\n  <commands>\n    <command group="test" expected-return="0" working-directory="." timeout="300">%s test --no-pub --fail-fast --timeout %s %s</command>\n  </commands>\n' "$FLUTTER" "$tmo" "$tests"
      printf '  <threshold failure="0">\n    <rating over="0" name="D"/>\n  </threshold>\n</mutations>\n'
    } > "$xml"
    printf '%s\t%s\t%s\n' "$f" "$k" "$xml" >> "$GAUNTLET_OUT/mutation-queue"
  done
}
# mutation_pop — retire et affiche la prochaine tâche de la file (vide si la file est vide).
mutation_pop() {
  local lock="$GAUNTLET_OUT/mutation-queue.lock" q="$GAUNTLET_OUT/mutation-queue" task
  until mkdir "$lock" 2>/dev/null; do sleep 0.2; done
  task="$(head -1 "$q" 2>/dev/null)"
  [ -n "$task" ] && { tail -n +2 "$q" > "$q.tmp"; mv "$q.tmp" "$q"; }
  rmdir "$lock"
  printf '%s' "$task"
}
# mutation_worker <n> <dossier du package où muter> — prend des tâches dans la file jusqu'à épuisement.
mutation_worker() {
  local n="$1" pkg="$2" task f k xml slug tests log="$GAUNTLET_OUT/mutation-worker-$1.log" cov=() checked=" "
  [ -f "$pkg/coverage/lcov.info" ] && cov=(-c coverage/lcov.info)
  : > "$log"
  while task="$(mutation_pop)"; [ -n "$task" ]; do
    IFS=$'\t' read -r f k xml <<< "$task"
    slug="$(printf '%s' "$f" | tr '/' '%')"
    case "$checked" in *" $f "*) ;; *)
      tests="$(cat "$GAUNTLET_OUT/mutation-tests-$slug.txt")"
      # shellcheck disable=SC2086
      if ! (cd "$pkg" && $FLUTTER test --no-pub --timeout "$(cfg mutation.test_timeout 10s)" $tests >>"$log" 2>&1); then
        printf 'BASELINE_KO %s\n' "$f" >> "$log"; printf '%s\n' "$f" >> "$GAUNTLET_OUT/mutation-baseline-ko"
      fi
      checked="$checked$f " ;;
    esac
    grep -qx "$f" "$GAUNTLET_OUT/mutation-baseline-ko" 2>/dev/null && continue
    printf '== %s#%s\n' "$f" "$k" >> "$log"
    # shellcheck disable=SC2086
    (cd "$pkg" && $DART pub global run mutation_test "$xml" -o "$GAUNTLET_OUT/mutation-report/$slug#$k" -f md -q "${cov[@]}" >>"$log" 2>&1)
  done
}
# mutation_files — fichiers de mutation.include (hors mutation.exclude) dans le périmètre de la feature.
# Mode extend : fichiers du périmètre seulement (dans un fichier modifié, seules les lignes ajoutées
# seront mutées). Retour 2 si mutation.include ne correspond à aucun fichier du package.
mutation_files() {
  local files
  files="$(expand_globs "$PKG_DIR" $(cfg_list mutation.include | tr '\n' ' ') | filter_excluded $(cfg_list mutation.exclude | tr '\n' ' ') | drop_generated)"
  [ -n "$files" ] || return 2
  printf '%s\n' "$files" | filter_scope_files "$PKG_REL/"
}
# extra_packages — packages opened by writes.extra other than the feature package, one path per line relative
# to PROJECT_ROOT. A glob's fixed prefix is walked up to the nearest folder holding a pubspec.yaml.
extra_packages() {
  local g d
  while IFS= read -r g; do
    d="${g%%\**}"; d="${d%/}"
    while [ -n "$d" ] && [ "$d" != . ] && [ ! -f "$PROJECT_ROOT/$d/pubspec.yaml" ]; do d="$(dirname "$d")"; done
    [ -n "$d" ] && [ "$d" != . ] && [ "$d" != "$PKG_REL" ] && printf '%s\n' "$d"
  done < <(writes_extra) | sort -u
}
# mutation_extra_report — mutation only runs on the feature package. Logic files (mutation.include) the
# feature changed in a writes.extra package are listed, never silently dropped: their tests are not proven by
# mutation, the reviewer and the evidence must say so. Informative, writes .gauntlet/mutation_scope_extra.txt.
mutation_extra_report() {
  local pkg base changed logic out="$GAUNTLET_OUT/mutation_scope_extra.txt"
  : > "$out"
  base="$(merge_base)"
  while IFS= read -r pkg; do
    [ -n "$pkg" ] && [ -d "$PROJECT_ROOT/$pkg/lib" ] || continue
    changed="$( { diff_names "$base" "$pkg/lib" --diff-filter=AM; untracked "$pkg/lib"; } | sed "s#^$pkg/##" | sort -u)"
    [ -n "$changed" ] || continue
    logic="$(expand_globs "$PROJECT_ROOT/$pkg" $(cfg_list mutation.include | tr '\n' ' ') \
      | filter_excluded $(cfg_list mutation.exclude | tr '\n' ' ') | drop_generated | grep -Fx -f <(printf '%s\n' "$changed"))"
    [ -n "$logic" ] || continue
    printf '%s\n' "$logic" | sed "s#^#$pkg/#" >> "$out"
    info "non muté : $pkg (writes.extra) — $(printf '%s\n' "$logic" | wc -l | tr -d ' ') fichier(s) de logique modifié(s) par la feature"
    printf '%s\n' "$logic" | sed 's/^/   /'
  done < <(extra_packages)
  [ -s "$out" ] && info "la mutation ne couvre que $PKG_REL : ces fichiers sont à signaler à la revue (${out#$PROJECT_ROOT/})"
  return 0
}
# mutation_scope — informatif, toujours vert : la liste des fichiers de logique que la mutation toucherait,
# dans .gauntlet/mutation_scope.txt. L'orchestrateur la lit en gabarit S pour décider de lancer Hugo.
check_mutation_scope() {
  local files n
  files="$(mutation_files)"; [ $? = 2 ] && files=""
  printf '%s' "$files" | grep -v '^$' > "$GAUNTLET_OUT/mutation_scope.txt"
  n="$(wc -l < "$GAUNTLET_OUT/mutation_scope.txt" | tr -d ' ')"
  info "$n fichier(s) de logique à muter dans le périmètre (gabarit $SIZE) → ${GAUNTLET_OUT#$PROJECT_ROOT/}/mutation_scope.txt"
  sed 's/^/   /' "$GAUNTLET_OUT/mutation_scope.txt"
  mutation_extra_report
  return 0
}
check_mutation() {
  local thr files report
  thr="$(cfg threshold.mutation 85)"
  files="$(mutation_files)"
  [ $? = 2 ] && { ko "aucun fichier ne correspond à mutation.include"; return 1; }
  mutation_extra_report
  [ -n "$files" ] || { info "aucun fichier à muter dans le périmètre"; return 0; }
  # Un seul run de mutation par feature : deux runs partagent clones, file et rapports, et le nettoyage de
  # l'un détruit le travail de l'autre. Verrou avec pid ; un verrou dont le pid est mort est repris.
  local mlock="$GAUNTLET_OUT/mutation.lock"
  if ! mkdir "$mlock" 2>/dev/null; then
    if kill -0 "$(cat "$mlock/pid" 2>/dev/null)" 2>/dev/null; then
      ko "un run de mutation tourne déjà pour cette feature (pid $(cat "$mlock/pid")) : attends sa fin ou tue-le"; return 1
    fi
    rm -rf "$mlock"; mkdir "$mlock"
  fi
  echo $$ > "$mlock/pid"
  trap 'rm -rf "'"$mlock"'"' RETURN
  report="$GAUNTLET_OUT/mutation-report"
  rm -rf "$report" "$GAUNTLET_OUT/mutation-orig" "$GAUNTLET_OUT/mutation-clones" "$GAUNTLET_OUT"/mutation-*.xml \
    "$GAUNTLET_OUT"/mutation-worker-*.log "$GAUNTLET_OUT"/mutation-tests-*.txt "$GAUNTLET_OUT/mutation-queue" \
    "$GAUNTLET_OUT/mutation-queue.lock" "$GAUNTLET_OUT/mutation-baseline-ko"
  mkdir -p "$report" "$GAUNTLET_OUT/mutation-orig"
  # Couverture de toute la suite : mutation_test ne mute que les lignes couvertes.
  (cd "$PKG_DIR" && $FLUTTER test --no-pub --coverage >"$GAUNTLET_OUT/mutation_coverage.log" 2>&1) \
    || info "couverture non produite (voir mutation_coverage.log) : toutes les lignes du périmètre sont mutées"
  local app workers ntasks nfiles i f
  app="$(cfg app_dir .)"; app="${app%/}"
  for f in $files; do mutation_plan "$f"; done
  ntasks="$(wc -l < "$GAUNTLET_OUT/mutation-queue" 2>/dev/null | tr -d ' ')"; ntasks="${ntasks:-0}"
  nfiles="$(printf '%s\n' "$files" | wc -l | tr -d ' ')"
  workers="$(cfg mutation.workers 4)"
  [ "$workers" -gt "$ntasks" ] && workers="$ntasks"
  [ "$app" = . ] && workers=1
  [ "$workers" -ge 1 ] || { info "aucune ligne à muter dans le périmètre"; return 0; }
  info "$nfiles fichier(s), $ntasks tranche(s), $workers worker(s), tests ciblés en --fail-fast, seuil $thr%"
  if [ "$app" = . ]; then
    # Pas de clone possible sans dupliquer le dépôt : en place, avec restauration garantie.
    for f in $files; do cp "$PKG_DIR/$f" "$GAUNTLET_OUT/mutation-orig/$(printf '%s' "$f" | tr '/' '%')"; done
    trap mutation_restore EXIT INT TERM
    mutation_worker 1 "$PKG_DIR"
    mutation_restore; trap - EXIT INT TERM
  else
    # Un clone APFS (copie à l'écriture) de app_dir par worker : le dépôt n'est jamais muté.
    local pids=() clone
    for ((i = 1; i <= workers; i++)); do
      clone="$GAUNTLET_OUT/mutation-clones/w$i"; mkdir -p "$(dirname "$clone/$app")"
      cp -cR "$PROJECT_ROOT/$app" "$clone/$app" 2>/dev/null || cp -R "$PROJECT_ROOT/$app" "$clone/$app"
      mutation_worker "$i" "$clone/$PKG_REL" &
      pids+=("$!")
    done
    trap 'kill "${pids[@]}" 2>/dev/null' INT TERM
    wait "${pids[@]}"
    trap - INT TERM
    rm -rf "$GAUNTLET_OUT/mutation-clones"
  fi
  cat "$GAUNTLET_OUT"/mutation-worker-*.log > "$GAUNTLET_OUT/mutation_stdout.log" 2>/dev/null
  if [ -s "$GAUNTLET_OUT/mutation-baseline-ko" ]; then
    ko "tests en échec SANS mutant (sous charge, timeout $(cfg mutation.test_timeout 10s)) : score non fiable pour"
    sed 's/^/   ✗ /' "$GAUNTLET_OUT/mutation-baseline-ko" | sort -u
    info "monter mutation.test_timeout ou corriger ces tests ; voir mutation_stdout.log"
    return 1
  fi
  local slug md t u ft fu total=0 undetected=0 survivors="" task k xml
  for f in $files; do
    slug="$(printf '%s' "$f" | tr '/' '%')"; ft=0; fu=0
    for xml in "$GAUNTLET_OUT/mutation-$slug#"*.xml; do
      [ -f "$xml" ] || continue
      k="${xml##*#}"; k="${k%.xml}"
      # Le rapport md contient un tableau | Mutations | n |, | Undetected | n |.
      md="$(ls "$report/$slug#$k"/*.md 2>/dev/null | head -1)"
      if [ -z "$md" ]; then ko "pas de rapport pour $f (tranche $k)"; tail -20 "$GAUNTLET_OUT/mutation_stdout.log"; return 1; fi
      t="$(grep -E '^\| Mutations ' "$md" | awk -F'|' '{gsub(/ /,"",$3); print $3}')"
      u="$(grep -E '^\| Undetected ' "$md" | awk -F'|' '{gsub(/ /,"",$3); print $3}')"
      ft=$(( ft + ${t:-0} )); fu=$(( fu + ${u:-0} ))
    done
    total=$(( total + ft )); undetected=$(( undetected + fu ))
    [ "$fu" != 0 ] && survivors="${survivors}   ✗ ${fu}/${ft} survivant(s) dans $f — ${report#"$PROJECT_ROOT"/}/$slug#*/"$'\n'
  done
  if [ "$total" = 0 ]; then info "aucune mutation possible dans ces fichiers (code trivial) — rien à prouver"; return 0; fi
  # Mutants expliqués dans mutants.md comme « équivalent » ou « mécanique » (égalité générée, props
  # Equatable, toString, log, garde défensive) : retirés du calcul. Sinon le seul moyen d'atteindre le seuil
  # est d'écrire des tests qui ne prouvent rien. Le dev valide ces explications dans la visite guidée.
  local explained=0 mfile="$FEATURE_DIR/mutants.md"
  if [ -f "$mfile" ] && [ "$undetected" -gt 0 ]; then
    explained="$(for f in $files; do
        awk -F'|' -v f="$f" 'index($2, f) && tolower($4) ~ /(équivalent|equivalent|mécanique|mecanique)/ {n++} END {print n+0}' "$mfile"
      done | awk '{s+=$1} END {print s+0}')"
    [ "$explained" -gt "$undetected" ] && explained="$undetected"
  fi
  local scored=$(( total - explained ))
  local score=100
  [ "$scored" -gt 0 ] && score=$(( (total-undetected)*100/scored ))
  printf '   mutants : %s, survivants : %s (dont %s expliqués équivalents ou mécaniques, hors calcul), score : %d%% (seuil %s%%)\n' "$total" "$undetected" "$explained" "$score" "$thr"
  printf '%s' "$survivors"
  info "rapports : ${report#"$PROJECT_ROOT"/}/<fichier>/ — chaque survivant est à tuer ou à expliquer dans mutants.md"
  [ "$score" -ge "$thr" ]
}
