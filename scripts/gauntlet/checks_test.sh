#!/usr/bin/env bash
# checks_test.sh — tests, la part commune à tous les langages : packages de writes.extra modifiés, gel des tests,
# tests ajoutés par le hardener, lignes nouvelles. Sourcé par gauntlet.sh. Lancer la suite, rouge/vert,
# couverture et mutation dépendent du langage : stacks/<langage>/checks_test.sh.
#
# Les dossiers de test d'un package viennent du langage (stack.ini → test_dirs : test/ pour Flutter).

# pkg_test_paths_from_rel / pkg_test_paths_to_rel — stdin : chemins de test. Ceux du package de la feature
# sont relatifs au package (`test/…`) dans pipeline.json, relatifs à la racine (`<package>/test/…`) dans git ;
# ceux d'un package de writes.extra gardent leur chemin depuis la racine.
pkg_test_paths_from_rel() {
  local td expr=()
  for td in $(stack_list test_dirs); do expr+=(-e "s#^$td/#$PKG_REL/$td/#"); done
  if [ ${#expr[@]} -gt 0 ]; then sed "${expr[@]}"; else cat; fi
}
pkg_test_paths_to_rel() {
  local td expr=()
  for td in $(stack_list test_dirs); do expr+=(-e "s#^$PKG_REL/$td/#$td/#"); done
  if [ ${#expr[@]} -gt 0 ]; then sed "${expr[@]}"; else cat; fi
}

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
  local base pkg d hit dirs="${*:-$(stack_dirs)}"; base="$(merge_base)"
  while IFS= read -r pkg; do
    [ -n "$pkg" ] && is_package_dir "$PROJECT_ROOT/$pkg" || continue
    hit=""
    for d in $dirs; do
      hit="$( { diff_names "$base" "$pkg/$d"; untracked "$pkg/$d"; } 2>/dev/null | head -1)"
      [ -n "$hit" ] && break
    done
    [ -n "$hit" ] && printf '%s\n' "$pkg"
  done < <(extra_packages)
}

extra_test_packages() { extra_changed_packages $(stack_list test_dirs | tr '\n' ' '); }

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

# test_freeze_check <strict|additive> — les tests gelés (SHA dans pipeline.json) sont intacts.
#   strict   : aucun changement, aucun fichier nouveau dans test/
#   additive : seuls des fichiers AJOUTÉS sont tolérés (hardener) ; aucune modification, aucune suppression
# Surveille test/ du package et celui de chaque package de writes.extra modifié (gelés avec lui, pipeline.sh freeze).
check_test_freeze_check() {
  local mode="${1:-strict}" sha changes="" untracked="" rc=0 pkg
  sha="$(pipeline_get .tests_freeze_sha)"
  [ -n "$sha" ] || { ko "pas de gel enregistré (pipeline.json → tests_freeze_sha)"; return 1; }
  local td
  for pkg in "$PKG_REL" $(extra_test_packages); do
    for td in $(stack_list test_dirs); do
      changes="$changes$(diff_name_status "$sha" "$pkg/$td" 2>/dev/null)"$'\n'
      untracked="$untracked$(untracked "$pkg/$td" 2>/dev/null)"$'\n'
    done
  done
  changes="$(printf '%s' "$changes" | grep -v '^$')"; untracked="$(printf '%s' "$untracked" | grep -v '^$')"
  # Hugo's additions (pipeline.json → hardening.tests_added, written by check_tests_added) are allowed after
  # the freeze, as long as they are new files: an untracked or added file only, never a modification.
  # `test/…` is relative to the package; a writes.extra package's file keeps its path from the root.
  local hugo f
  hugo="$(pipeline_get '.hardening.tests_added[]?' | grep -v '^$' | pkg_test_paths_from_rel)"
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

# tests_added — enregistre les tests de Hugo (pipeline.json → hardening.tests_added) : les fichiers AJOUTÉS à
# test/ depuis tests_freeze_sha (non suivis compris), dans le package et dans chaque package de writes.extra qui a
# des tests de la feature. Ceux du package sont relatifs au package (`test/…`), ceux d'un package de writes.extra
# relatifs à la racine (`<pkg>/test/…` : `test/…` seul serait ambigu). La liste est remplacée : c'est l'état de
# l'arbre. Sans elle, les gates stricts qui suivent (green, clean, polish) voient ces fichiers comme des changements.
check_tests_added() {
  local sha pkg added="" json
  [ -f "$FEATURE_DIR/pipeline.json" ] || { info "hors pipeline : rien à enregistrer"; return 0; }
  sha="$(pipeline_get .tests_freeze_sha)"
  [ -n "$sha" ] || { info "pas de gel enregistré : rien à enregistrer"; return 0; }
  local td
  for pkg in "$PKG_REL" $(extra_test_packages); do
    for td in $(stack_list test_dirs); do
      added="$added$(diff_name_status "$sha" "$pkg/$td" 2>/dev/null | awk -F'\t' '$1 == "A" { print $2 }')"$'\n'
      added="$added$(untracked "$pkg/$td" 2>/dev/null)"$'\n'
    done
  done
  json="$(printf '%s' "$added" | grep -v '^$' | pkg_test_paths_to_rel | sort -u | jq -R . | jq -cs .)"
  (cd "$PROJECT_ROOT" && bash "$GAUNTLET_ROOT/../pipeline.sh" set "$FEATURE" hardening.tests_added "$json" >/dev/null) \
    || { ko "hardening.tests_added non enregistré ($json)"; return 1; }
  info "hardening.tests_added : $(jq -r 'length' <<<"$json") fichier(s) ajouté(s) depuis le gel $sha"
  jq -r '.[]' <<<"$json" | sed 's/^/   /'
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

# extra_packages — packages opened by writes.extra other than the feature package, one path per line relative
# to PROJECT_ROOT. A glob's fixed prefix is walked up to the nearest folder holding a package marker
# (pubspec.yaml, build.gradle.kts… : stack.sh markers).
extra_packages() {
  local g d
  while IFS= read -r g; do
    d="${g%%\**}"; d="${d%/}"
    while [ -n "$d" ] && [ "$d" != . ] && ! is_package_dir "$PROJECT_ROOT/$d"; do d="$(dirname "$d")"; done
    [ -n "$d" ] && [ "$d" != . ] && [ "$d" != "$PKG_REL" ] && printf '%s\n' "$d"
  done < <(writes_extra) | sort -u
}

# ---------------------------------------------------------------------------------------------------------
# Suite, rouge, noms : le déroulé commun aux langages. Le langage fournit, dans stacks/<langage>/checks_test.sh :
#   run_tests_json      lance la suite du package courant (couche comprise), pose TEST_REPORT et TEST_NONE,
#                       rend le code de la suite ; écrit la sortie d'erreur dans $GAUNTLET_OUT/test_stderr.log
#   test_results        une ligne JSON par test : {file (relatif au package), name, result, skipped}
#   feature_tests_here  le périmètre du package courant contient un fichier de test
# et ses check_test / check_red_check / check_test_names appellent run_suite_check / run_red_check /
# run_test_names. Un langage sans ces trois fonctions n'a pas ces checks : non applicables.
# ---------------------------------------------------------------------------------------------------------
TEST_REPORT="" # défini par run_tests_json
TEST_NONE=0    # 1 : le package (ou sa couche) n'a aucun fichier de test, rien n'a tourné

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

run_suite_check() {
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
run_red_check() {
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
  # Fichiers tout verts acceptés par Thibault (pipeline.json → red_accept_green, avec sa raison) : ce qu'ils
  # prouvent existe avant les tests (ressources posées au scaffold). Signalés, plus bloquants.
  local accepted f
  accepted="$(pipeline_get '.red_accept_green[]?.file')"
  if [ -n "$green_files" ] && [ -n "$accepted" ]; then
    for f in $(printf '%s\n' "$green_files" | grep -xF -f <(printf '%s\n' "$accepted")); do
      info "tout vert, accepté par Thibault : $f ($(pipeline_get ".red_accept_green[] | select(.file==\"$f\") | .reason"))"
    done
    green_files="$(printf '%s\n' "$green_files" | grep -vxF -f <(printf '%s\n' "$accepted"))"
  fi
  if [ -n "$green_files" ]; then
    printf '%s\n' "$green_files" | sed 's/^/  ✗ tout vert : /'
    ko "ces fichiers ne testent rien que les stubs ne satisfassent déjà"
    return 1
  fi
  info "$total test(s), $(printf '%s\n' "$scoped_files" | wc -l | tr -d ' ') fichier(s) dans le périmètre, rouge dans chacun"
}

# test_names — écrit .claude/features/<f>/tests.md pour le skim du dev. Toujours vert.
# Packages de writes.extra modifiés : leurs fichiers de test de la feature suivent, préfixés du package.
run_test_names() {
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
