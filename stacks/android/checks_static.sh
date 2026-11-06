#!/usr/bin/env bash
# checks_static.sh — compilation, lint, format, couches, stubs d'un module Android / Kotlin. Chaque check :
# fonction check_<nom> [mode], exit 0 = vert, NA_RC = outil absent du projet. Sourcé par stacks/android/checks.sh.

# analyze — le module compile (code et tests JVM) ; Android lint, et detekt s'il est appliqué. Une erreur de
# compilation bloque toujours ; un avertissement du compilateur, une issue lint (Warning, Error, Fatal) ou detekt
# ne bloque que dans les fichiers du périmètre. Packages de writes.extra modifiés : analysés de même, à la suite.
check_analyze() {
  local rc=0
  analyze_pkg || rc=1
  each_extra_package extra_changed_packages analyze_pkg || rc=1
  return $rc
}
analyze_pkg() {
  local log="$GAUNTLET_OUT/gradle_compile.log" errors warns issues rc=0 out_of_scope=0
  gradle_log compile :@compile; local crc=$?
  errors="$(kotlin_diag "$log" e)"
  if [ "$crc" != 0 ]; then
    # Couche : une erreur dans un fichier que l'autre moitié écrit en même temps n'est pas la sienne (le gate
    # complet, après les deux, compile tout). Une erreur sans fichier (build cassé) bloque toujours.
    if [ -n "${LAYER:-}" ] && [ -n "$errors" ] && [ -z "$(printf '%s\n' "$errors" | while IFS= read -r l; do in_layer "$LAYER" "${l%%:*}" && printf '%s\n' "$l"; done)" ]; then
      info "erreurs de compilation hors de la couche $LAYER seulement (l'autre moitié) :"; printf '%s\n' "$errors" | head -10 | sed 's/^/   · /'
    else
      if [ -n "$errors" ]; then printf '%s\n' "$errors" | head -30; else tail -30 "$log"; fi
      ko "erreurs de compilation"; return 1
    fi
  fi
  warns="$(kotlin_diag "$log" w | drop_generated | filter_scope_lines "$PKG_REL/")"
  [ -n "$warns" ] && { printf '%s\n' "$warns" | head -30 | sed 's/^/   ✗ /'; ko "avertissements du compilateur dans le périmètre"; rc=1; }
  # Android lint : un module JVM pur n'en a que s'il applique com.android.lint.
  if [ "$(module_kind)" = android ] || has_plugin 'com\.android\.lint'; then
    issues="$(lint_issues)" || { rc=1; issues=""; }
    if [ -n "$issues" ]; then
      out_of_scope="$(printf '%s\n' "$issues" | grep -c .)"
      issues="$(printf '%s\n' "$issues" | drop_generated | filter_scope_lines "$PKG_REL/")"
      out_of_scope=$((out_of_scope - $(printf '%s' "$issues" | grep -c .)))
      [ "$out_of_scope" -gt 0 ] && info "lint : $out_of_scope issue(s) hors périmètre (préexistantes)"
      [ -n "$issues" ] && { printf '%s\n' "$issues" | head -30 | sed 's/^/   ✗ /'; ko "issues Android lint dans le périmètre"; rc=1; }
    fi
  else
    info "module JVM sans com.android.lint : pas d'Android lint"
  fi
  if has_plugin 'detekt'; then
    issues="$(detekt_issues)" || { rc=1; issues=""; }
    issues="$(printf '%s\n' "$issues" | grep -v '^$' | drop_generated | filter_scope_lines "$PKG_REL/")"
    [ -n "$issues" ] && { printf '%s\n' "$issues" | head -30 | sed 's/^/   ✗ /'; ko "issues detekt dans le périmètre"; rc=1; }
  else
    info "detekt non appliqué au projet : seulement le compilateur et lint"
  fi
  [ "$rc" = 0 ] && info "compile ; aucune issue dans le périmètre"
  return $rc
}
# lint_issues — lance Android lint, rend ses issues (reports.py lint). Le code de lint ne compte pas : il échoue
# sur une erreur ancienne comme sur une neuve, le périmètre tranche. Sans rapport : échec.
lint_issues() {
  local xml
  rm -f "$PKG_DIR"/build/reports/lint-results*.xml
  gradle_log lint :@lint
  xml="$(ls -t "$PKG_DIR"/build/reports/lint-results*.xml 2>/dev/null | head -1)"
  [ -n "$xml" ] || { tail -20 "$GAUNTLET_OUT/gradle_lint.log"; ko "Android lint n'a produit aucun rapport (voir .gauntlet/gradle_lint.log)"; return 1; }
  python3 "$ANDROID_CHECKS_DIR/reports.py" lint "$xml" "$PKG_DIR"
}
# detekt_issues — lance detekt, rend ses issues (rapport checkstyle build/reports/detekt/detekt.xml).
detekt_issues() {
  local xml="$PKG_DIR/build/reports/detekt/detekt.xml"
  rm -f "$xml"
  gradle_log detekt :detekt
  [ -f "$xml" ] || { tail -20 "$GAUNTLET_OUT/gradle_detekt.log"; ko "detekt n'a produit aucun rapport XML (voir .gauntlet/gradle_detekt.log)"; return 1; }
  python3 "$ANDROID_CHECKS_DIR/reports.py" checkstyle "$xml" "$PKG_DIR"
}

# format [test] — seuls les fichiers du périmètre doivent être formatés, par l'outil du projet : ktlint
# (org.jlleitschuh.gradle.ktlint, tâche ktlintCheck) ou Spotless (spotlessCheck). Ni l'un ni l'autre : N/A.
#   test : src/test et src/androidTest seulement (profil red : le test-writer ne peut pas corriger src/main).
check_format() {
  local rc=0 r
  format_pkg "${1:-}"; r=$?
  [ "$r" = "$NA_RC" ] && return "$NA_RC"
  [ "$r" = 0 ] || rc=1
  each_extra_package extra_changed_packages format_pkg "${1:-}" || rc=1
  return $rc
}
format_pkg() {
  local tool task files dirs bad log
  if has_plugin 'ktlint'; then tool=ktlint; task=:ktlintCheck
  elif has_plugin 'spotless'; then tool=spotless; task=:spotlessCheck
  else not_applicable "ni ktlint (org.jlleitschuh.gradle.ktlint) ni Spotless dans le build : aucun formateur à faire respecter"; return; fi
  dirs="$( { [ "${1:-}" = test ] || stack_list src_dirs; stack_list test_dirs; } | paste -sd'|' -)"
  files="$(scope_files "$PKG_REL/" | grep -E "^($dirs)/" | while IFS= read -r f; do [ -f "$PKG_DIR/$f" ] && printf '%s\n' "$f"; done)"
  [ -n "$files" ] || { info "aucune source Kotlin dans le périmètre"; return 0; }
  gradle_log format "$task"; log="$GAUNTLET_OUT/gradle_format.log"
  if [ "$tool" = ktlint ]; then
    # « /abs/X.kt:3:1 Unexpected blank line(s) (standard:no-consecutive-blank-lines) », dans la sortie ou les
    # rapports texte du plugin.
    bad="$( { cat "$log"; cat "$PKG_DIR"/build/reports/ktlint/*/*.txt 2>/dev/null; } \
      | grep -E '\.kts?:[0-9]+:[0-9]+:? ' | sed 's/^[^/]*\(\/\)/\1/' | rel_pkg | sort -u \
      | grep -E "^($(printf '%s\n' "$files" | sed 's/[.[\*^$]/\\&/g' | paste -sd'|' -)):")"
  else
    # spotlessCheck : « The following files had format violations: » puis un chemin par ligne, indenté.
    bad="$(grep -E '^[[:space:]]+[^[:space:]]+\.kts?$' "$log" | sed 's/^[[:space:]]*//' | rel_pkg | sort -u | grep -xF -f <(printf '%s\n' "$files"))"
  fi
  [ -z "$bad" ] && { info "$(printf '%s\n' "$files" | grep -c .) fichier(s) du périmètre formatés ($tool)"; return 0; }
  printf '%s\n' "$bad" | head -30 | sed 's/^/   ✗ /'
  ko "fichiers du périmètre à formater : $(stack_val gradle) ${task#:} (ou ${tool}Format / spotlessApply)"
  return 1
}

# no_stubs — après IMPLEMENTER : plus aucun TODO() ni NotImplementedError dans src/main. Un commentaire
# `// TODO` n'est pas un stub (todo_tickets le juge). `// gauntlet-ignore` exempte la ligne (ou la suivante).
STUB_RE='(^|[^A-Za-z0-9_.])TODO\(|NotImplementedError'
check_no_stubs() {
  local mark="${IGNORE_MARK:-gauntlet-ignore}" f hits d
  hits="$(for d in $(stack_list src_dirs); do grep -rlE --include='*.kt' --include='*.java' "$STUB_RE" "$PKG_DIR/$d" 2>/dev/null; done \
    | while IFS= read -r f; do
      [ -n "${LAYER:-}" ] && ! in_layer "$LAYER" "${f#$PKG_DIR/}" && continue
      printf '%s\n' "${f#$PKG_DIR/}" | drop_generated | grep -q . || continue
      # ENVIRON, pas -v : awk lirait les \( de l'ERE comme des séquences d'échappement.
      RE="$STUB_RE" awk -v mark="$mark" -v file="${f#$PKG_DIR/}" '
        { line[NR]=$0 }
        END {
          for (i=1;i<=NR;i++) {
            l = line[i]; sub(/\/\/.*$/, "", l)
            if (l !~ ENVIRON["RE"]) continue
            if (index(line[i] "\n" line[i+1], mark)) continue
            print file":"i":"line[i]
          }
        }' "$f"
    done)"
  [ -z "$hits" ] && return 0
  printf '%s\n' "$hits"; printf '\n%d stub(s) restant(s) dans src/main\n' "$(printf '%s\n' "$hits" | wc -l | tr -d ' ')"
  return 1
}

# no_temp_markers — aucun marqueur TEMP, println/print ni printStackTrace() dans src/ et les tests du périmètre.
check_no_temp_markers() {
  local dirs="" d hits
  for d in $(stack_dirs); do [ -d "$PKG_DIR/$d" ] && dirs="$dirs $PKG_DIR/$d"; done
  [ -n "$dirs" ] || return 0
  # shellcheck disable=SC2086
  hits="$(grep -rnE --include='*.kt' --include='*.java' 'TEMP VISUAL TEST|TEMP PIPELINE|(^|[^A-Za-z0-9_.])println?\(|System\.out\.print|printStackTrace\(\)' $dirs 2>/dev/null \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|\*|/\*)' | sed "s#^$PKG_DIR/##" | filter_scope_lines "$PKG_REL/")"
  [ -z "$hits" ] && return 0
  printf '%s\n' "$hits"; printf '\nmarqueurs temporaires, println() ou printStackTrace() à retirer (Log / Timber, ou rien)\n'
  return 1
}

# error_handling — un try/catch (ou runCatching) n'existe que dans la couche data (*/data/, I/O). Partout ailleurs
# (domain, ui, di), l'échec circule en valeur (Result<T>, ou le type d'erreur scellé du projet) rendue par la data.
# Les coroutines : un CancellationException ne s'avale pas, d'où la règle. `// gauntlet-ignore: <raison>` exempte.
ERROR_HANDLING_KT_RE='(^|[^A-Za-z_])try[[:space:]]*\{|(^|[^A-Za-z_])catch[[:space:]]*\(|(^|[^A-Za-z_.])runCatching[[:space:]]*\{|\.runCatching[[:space:]]*\{'
check_error_handling() {
  local hits d
  hits="$(for d in $(stack_list src_dirs); do
      [ -d "$PKG_DIR/$d" ] && grep -rnE --include='*.kt' --include='*.java' "$ERROR_HANDLING_KT_RE" "$PKG_DIR/$d" 2>/dev/null
    done | sed "s#^$PKG_DIR/##" | grep -vE '^[^:]*/data/' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|\*|/\*)' \
      | grep -v 'gauntlet-ignore' | filter_scope_lines "$PKG_REL/")"
  [ -z "$hits" ] && return 0
  printf '%s\n' "$hits"
  printf '\ntry/catch hors de la couche data : l'"'"'I/O et son try/catch vivent dans */data/, qui rend un Result (ou le\n'
  printf 'type d'"'"'erreur du projet) ; domain et ui composent des résultats, sans try/catch ni runCatching.\n'
  return 1
}

# deps — direction des couches. La couche d'un fichier est le premier segment domain|data|ui|presentation|di de
# son chemin sous src/main ; celle d'un import, le même segment dans l'import, s'il partage le paquet du fichier
# jusqu'à la couche (`com.x.login.ui` importe `com.x.login.data.…` → ui → data). Autorisé : deps.<couche> de la
# config (comme Flutter ; presentation et ui suivent deps.presentation, di suit deps.injection). Domaine pur : ni
# android.*, ni androidx.* (sauf androidx.annotation), ni deps.domain_forbidden_packages. La présentation ne voit
# aucun *Repository ; une vue (fichier ui hors *ViewModel.kt) ne voit aucun *UseCase.
# Mode extend : une violation sur une ligne non touchée est de la dette (debt_deps.txt), pas bloquante.
KT_LAYERS="domain data ui presentation di"
kt_layer_of() { # <chemin> → couche, vide sinon
  local seg
  for seg in $(printf '%s' "$1" | tr '/.' '  '); do
    case " $KT_LAYERS " in *" $seg "*) printf '%s' "$seg"; return ;; esac
  done
}
kt_allowed() { # <couche> → couches qu'elle peut importer
  case "$1" in
    ui|presentation) cfg_list deps.presentation ;;
    di) cfg_list deps.injection ;;
    *) cfg_list "deps.$1" ;;
  esac | tr '\n' ' '
}
check_deps() {
  local d f ln line imp layer target allowed prefix forbidden exempt g viol="" mine p
  forbidden="$(cfg_list deps.domain_forbidden_packages)"
  exempt="$(cfg_list deps.exempt)"
  for d in $(stack_list src_dirs); do
    [ -d "$PKG_DIR/$d" ] || continue
    while IFS= read -r line; do
      f="${line%%:*}"; ln="${line#*:}"; ln="${ln%%:*}"
      for g in $exempt; do
        # shellcheck disable=SC2053
        [[ "$f" == $g ]] && continue 2
      done
      layer="$(kt_layer_of "${f#$d/}")"; [ -n "$layer" ] || continue
      imp="$(printf '%s' "${line#*:*:}" | sed -E 's/^[[:space:]]*import[[:space:]]+([A-Za-z0-9_.*`]+).*/\1/')"
      # Paquet du fichier jusqu'à sa couche : `src/main/kotlin/com/x/login/ui/A.kt` → `com.x.login.`
      prefix="$(sed -n 's/^[[:space:]]*package[[:space:]]\{1,\}\([A-Za-z0-9_.]*\).*/\1/p' "$PKG_DIR/$f" | head -1)"
      prefix="$(printf '%s' ".$prefix." | sed -E "s/\.$layer(\..*)?\.$/./")"; prefix="${prefix#.}"
      if [ -n "$prefix" ] && [[ "$imp" == "$prefix"* ]]; then
        target="$(kt_layer_of "${imp#$prefix}")"
        target="${target:-}"; [ "$target" = "${imp#$prefix}" ] && target=""
        if [ -n "$target" ] && [ "$target" != "$layer" ]; then
          allowed="$(kt_allowed "$layer")"
          # ui et presentation sont la même couche sous deux noms
          case "$layer:$target" in ui:presentation|presentation:ui) ;; *)
            grep -qw "$target" <<<"$allowed" || viol+="$f:$ln: $layer → $target interdit (autorisé : ${allowed:-rien})"$'\n' ;;
          esac
        fi
      fi
      if [ "$layer" = domain ]; then
        case "$imp" in
          androidx.annotation.*) ;;
          android.*|androidx.*) viol+="$f:$ln: domain importe $imp (domaine impur : pas d'Android dans le domaine)"$'\n' ;;
        esac
        for p in $forbidden; do
          [[ "$imp" == "$p".* ]] && viol+="$f:$ln: domain importe $p (domaine impur)"$'\n'
        done
      fi
    done < <(grep -rnE --include='*.kt' --include='*.java' '^[[:space:]]*import[[:space:]]' "$PKG_DIR/$d" 2>/dev/null | sed "s#^$PKG_DIR/##" | drop_generated)
    # Présentation : aucun repository ; une vue, aucun use case (elle lit son ViewModel).
    while IFS= read -r line; do
      f="${line%%:*}"; ln="${line#*:}"; ln="${ln%%:*}"
      case "$(kt_layer_of "${f#$d/}")" in ui|presentation) ;; *) continue ;; esac
      for g in $exempt; do
        # shellcheck disable=SC2053
        [[ "$f" == $g ]] && continue 2
      done
      if printf '%s' "${line#*:*:}" | grep -qE "$PRESENTATION_REPOSITORY_KT_RE"; then
        target="$(printf '%s' "${line#*:*:}" | grep -oE "$PRESENTATION_REPOSITORY_KT_RE" | head -1 | tr -cd 'A-Za-z0-9_')"
        viol+="$f:$ln: presentation → repository ($target) interdit : passer par un use case"$'\n'
      elif [[ "$f" != *ViewModel.kt ]] && printf '%s' "${line#*:*:}" | grep -qE "$VIEW_USECASE_KT_RE"; then
        target="$(printf '%s' "${line#*:*:}" | grep -oE "$VIEW_USECASE_KT_RE" | head -1 | tr -cd 'A-Za-z0-9_')"
        viol+="$f:$ln: vue → use case ($target) interdit : la vue lit son ViewModel"$'\n'
      fi
    done < <(grep -rnE --include='*.kt' "$PRESENTATION_REPOSITORY_KT_RE|$VIEW_USECASE_KT_RE" "$PKG_DIR/$d" 2>/dev/null \
               | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|\*|/\*)' | grep -v 'gauntlet-ignore' | sed "s#^$PKG_DIR/##" | drop_generated)
  done
  mine="$(printf '%s\n' "$viol" | grep -v '^$' | filter_scope_lines "$PKG_REL/")"
  printf '%s\n' "$viol" | grep -v '^$' \
    | M="$mine" awk 'BEGIN { n=split(ENVIRON["M"], a, "\n"); for (i=1; i<=n; i++) own[a[i]]=1 } !($0 in own)' > "$GAUNTLET_OUT/debt_deps.txt"
  if [ -s "$GAUNTLET_OUT/debt_deps.txt" ]; then
    info "dette existante (lignes que la feature n'a pas touchées, non bloquant, voir debt_deps.txt) :"
    sed 's/^/   · /' "$GAUNTLET_OUT/debt_deps.txt" | head -15
  fi
  if [ -n "$mine" ]; then printf '%s\n' "$mine" | sed 's/^/   ✗ /'; ko "dépendances entre couches violées par la feature"; return 1; fi
  info "couches respectées"
}
PRESENTATION_REPOSITORY_KT_RE='(^|[^A-Za-z0-9_])[A-Z][A-Za-z0-9_]*Repository([^A-Za-z0-9_]|$)'
VIEW_USECASE_KT_RE='(^|[^A-Za-z0-9_])[A-Z][A-Za-z0-9_]*(Usecase|UseCase)([^A-Za-z0-9_]|$)'

# stub_check — après ARCHITECT : dans les fichiers de stub.include, chaque fonction avec un corps est un stub :
# `= TODO()`, ou un corps dont la première instruction est TODO(…) / throw NotImplementedError(…). Une fonction
# abstraite ou d'interface (sans corps) n'a rien à prouver. Mode extend, rejeu : seules les fonctions absentes de la
# base comptent (une signature existante qui change n'est pas un contrat neuf). Lecture au niveau du texte, sans
# compilateur : une fonction locale ou une lambda nommée `fun` dans un corps compte aussi.
check_stub_check() {
  local files SCOPE_FILE SCOPE_ALL f base_names bad="" n=0; use_pass_scope
  # shellcheck disable=SC2046
  files="$(expand_globs "$PKG_DIR" $(cfg_list stub.include | tr '\n' ' ') | drop_generated)"
  [ -n "$files" ] || { ko "aucun fichier ne correspond à stub.include"; return 1; }
  files="$(printf '%s\n' "$files" | filter_scope_files "$PKG_REL/")"
  if [ -z "$files" ] && [ -n "${PASS_BASE:-}" ]; then
    info "aucun fichier d'implémentation du package modifié $(pass_label) : le rejeu ne pose pas de contrat ici"; return 0
  fi
  [ -n "$files" ] || { ko "aucun fichier d'implémentation dans le périmètre — l'architect n'a posé aucun contrat"; return 1; }
  for f in $files; do
    n=$((n + 1))
    base_names=""
    [ "$SCOPE_ALL" = 1 ] || base_names="$(show_at "${PASS_BASE:-$(merge_base)}" "$PKG_REL/$f" | kt_funs | cut -f2 | sort -u | tr '\n' ' ')"
    bad="$bad$(kt_funs < "$PKG_DIR/$f" | awk -F'\t' -v file="$f" -v base=" $base_names " '
      $3 == "body" && index(base, " " $2 " ") == 0 { print file ":" $1 ": fun " $2 " a un corps qui n'\''est pas un stub (TODO())" }')"$'\n'
  done
  bad="$(printf '%s' "$bad" | grep -v '^$')"
  info "$n fichier(s) inspecté(s)"
  [ -z "$bad" ] && return 0
  printf '%s\n' "$bad" | sed 's/^/   ✗ /'
  ko "fonctions implémentées avant les tests : l'architect pose des stubs TODO(), l'implementer les remplit"
  return 1
}
# kt_funs — stdin : un fichier Kotlin → « ligne<TAB>nom<TAB>stub|body|abstract » par déclaration `fun`.
# La signature court jusqu'au `=` ou au `{` hors parenthèses. Elle continue sur la ligne suivante tant qu'une
# parenthèse est ouverte, ou si cette ligne commence par `=`, `{`, `:`, `)`, `where` ; sinon la fonction est
# abstraite (interface, abstract) et la ligne est lue pour elle-même.
kt_funs() {
  awk '
    function flush(kind) { if (name != "") print start "\t" name "\t" kind; name = ""; sig = ""; pending = 0 }
    function is_stub(s) { return s ~ /^[[:space:]]*(TODO\(|throw[[:space:]]+NotImplementedError)/ }
    # decide — signature finie ? `= …` (corps expression) ou `{` (bloc) hors parenthèses ; sinon pending.
    function decide(   i, c, rest) {
      depth = 0
      for (i = 1; i <= length(sig); i++) {
        c = substr(sig, i, 1)
        if (c == "(") depth++
        else if (c == ")") depth--
        else if (depth == 0 && c == "=" && substr(sig, i + 1, 1) != "=") {
          flush(is_stub(substr(sig, i + 1)) ? "stub" : "body"); return
        } else if (depth == 0 && c == "{") {
          rest = substr(sig, i + 1)
          if (is_stub(rest)) { flush("stub"); return }
          if (rest ~ /[^[:space:]]/) { flush("body"); return }
          pending = 0; want_body = 1; return
        }
      }
      pending = 1
    }
    {
      line = $0; sub(/\/\/.*$/, "", line)
      if (want_body) {
        if (line ~ /^[[:space:]]*$/) next
        want_body = 0; flush(is_stub(line) ? "stub" : "body"); next
      }
      if (pending) {
        if (depth > 0 || line ~ /^[[:space:]]*(=|\{|:|\)|where[[:space:]])/) { sig = sig " " line; decide(); next }
        flush("abstract")
      }
      if (match(line, /(^|[^A-Za-z0-9_])fun[[:space:]]+(<[^>]*>[[:space:]]*)?([A-Za-z0-9_]+\.)?[A-Za-z0-9_`]+[[:space:]]*\(/)) {
        decl = substr(line, RSTART, RLENGTH); sub(/\($/, "", decl); sub(/[[:space:]]+$/, "", decl)
        n = split(decl, parts, /[[:space:].]+/); name = parts[n]; start = NR; sig = substr(line, RSTART)
        decide()
      }
    }
    END { if (want_body) flush("body"); else if (pending) flush("abstract") }'
}
