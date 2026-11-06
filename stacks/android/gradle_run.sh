#!/usr/bin/env bash
# gradle_run.sh — lance une tâche Gradle sur le module du dossier courant, depuis la racine Gradle.
#
#   gradle_run.sh <arg>…      depuis un module (ou un dossier dedans)
#   gradle_run.sh --where     « racine<TAB>chemin du module<TAB>android|jvm », rien lancé
#
# Les commandes du langage (stack.ini → test_cmd, test_files_cmd, analyze_cmd…) tournent dans le dossier du
# package, comme `flutter test`. Gradle, lui, se lance depuis la racine (settings.gradle.kts, ./gradlew) avec des
# tâches qualifiées. Ce lanceur fait le lien :
#   :<tâche>       → <module>:<tâche>     (`:testDebugUnitTest` → `:feature:login:testDebugUnitTest`) ;
#                    une tâche déjà qualifiée par ce module reste telle quelle
#   toujours       → --init-script test_logging.gradle (message d'assertion d'un test rouge sur la console)
#   :@unitTest     → la tâche de tests unitaires du type de module (unit_test_task, jvm_unit_test_task)
#   :@compile      → la compilation des tests, qui compile aussi le code (compile_task, jvm_compile_task)
#   :@lint         → Android lint (lint_task, jvm_lint_task)
#   <fichier>.kt   → --tests <paquet>.<Classe> (un fichier de test donné en argument, /reviewPR run-tests)
#   le reste       → tel quel (--continue, -P…)
# Type de module : « android » si son build cite android (com.android.library, un plugin de convention
# *.android.*, un bloc android {}), sinon « jvm » (un module domaine en kotlin("jvm")). GRADLE_MODULE_KIND force.
# La commande Gradle : variable GRADLE, sinon la clé `gradle` (./gradlew), relative à la racine.
# GRADLE_RUN_DRY=1 : affiche la commande au lieu de la lancer.
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_SH="$here/../../scripts/stack.sh"
# Les langages de ce checkout (un worktree de ~/.claude se teste avec les siens), sauf si le gauntlet les a posés.
export CLAUDE_STACKS_DIR="${CLAUDE_STACKS_DIR:-$(cd "$here/.." && pwd)}"

# up <dossier> <fichier>… — le premier dossier, de <dossier> vers /, qui contient l'un des fichiers
up() {
  local d="$1" f; shift
  while :; do
    for f in "$@"; do [ -e "$d/$f" ] && { printf '%s' "$d"; return 0; }; done
    [ "$d" = / ] && return 1
    d="$(dirname "$d")"
  done
}

start="$(pwd -P)"
module="$(up "$start" build.gradle.kts build.gradle)" || module=""
root="$(up "${module:-$start}" settings.gradle.kts settings.gradle)" \
  || root="$(up "${module:-$start}" gradlew)" \
  || { echo "gradle_run.sh : aucune racine Gradle (settings.gradle.kts) au-dessus de $start" >&2; exit 2; }
[ -n "$module" ] || module="$root"
case "$module" in "$root"/*) ;; *) module="$root" ;; esac
path=""; [ "$module" = "$root" ] || path=":$(printf '%s' "${module#"$root"/}" | tr '/' ':')"

kind="${GRADLE_MODULE_KIND:-}"
if [ -z "$kind" ]; then
  kind=jvm
  for b in "$module/build.gradle.kts" "$module/build.gradle"; do
    [ -f "$b" ] && grep -v '^[[:space:]]*//' "$b" | grep -qiE 'android' && kind=android
  done
fi

if [ "${1:-}" = --where ]; then printf '%s\t%s\t%s\n' "$root" "$path" "$kind"; exit 0; fi

# Valeurs du langage, d'un coup (la config du projet prime : STACK_CFG si le gauntlet la passe).
vals="$(bash "$STACK_SH" vals "$module" gradle unit_test_task jvm_unit_test_task compile_task jvm_compile_task lint_task jvm_lint_task 2>/dev/null)"
val() { printf '%s\n' "$vals" | sed -n "${1}p"; }
gradle="${GRADLE:-$(val 1)}"; gradle="${gradle:-./gradlew}"
task_for() { # task_for <alias> → la tâche du type de module
  case "$1:$kind" in
    unitTest:android) val 2 ;; unitTest:jvm) val 3 ;;
    compile:android)  val 4 ;; compile:jvm)  val 5 ;;
    lint:android)     val 6 ;; lint:jvm)     val 7 ;;
  esac
}

args=()
for a in "$@"; do
  case "$a" in
    :@*)
      t="$(task_for "${a#:@}")"
      [ -n "$t" ] || { echo "gradle_run.sh : alias inconnu $a (unitTest, compile, lint)" >&2; exit 2; }
      args+=("$path:$t") ;;
    "$path":*) args+=("$a") ;;  # déjà qualifiée (`-x :mobile:processDebugGoogleServices`)
    :*) args+=("$path$a") ;;
    *.kt|*.java)
      f="$a"; [ -f "$f" ] || f="$start/$a"
      if [ -f "$f" ]; then
        pkg="$(sed -n 's/^[[:space:]]*package[[:space:]]\{1,\}\([A-Za-z0-9_.]*\).*/\1/p' "$f" | head -1)"
        cls="$(basename "$f")"; cls="${cls%.*}"
        args+=(--tests "${pkg:+$pkg.}$cls")
      else
        args+=("$a")
      fi ;;
    *) args+=("$a") ;;
  esac
done
# Le message d'assertion d'un test rouge sur la console (test_logging.gradle) : le gate red le lit.
args+=(--init-script "$here/test_logging.gradle")

if [ "${GRADLE_RUN_DRY:-0}" = 1 ]; then printf 'cd %s && %s' "$root" "$gradle"; printf ' %s' ${args[@]+"${args[@]}"}; printf '\n'; exit 0; fi
cd "$root" || exit 2
# shellcheck disable=SC2086
exec $gradle ${args[@]+"${args[@]}"}
