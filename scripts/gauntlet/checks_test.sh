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
