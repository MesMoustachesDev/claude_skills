#!/usr/bin/env bash
# hooks/lib.sh — ce que partagent les hooks de zone (pipeline-restrict-writes.sh, fix-restrict-writes.sh), les
# gates de fin d'agent (pipeline-gate.sh, fix-gate.sh) et no-interpreter.sh. Sourcé, pas exécuté.
#
# Chemins : ceux de ce checkout (le dossier du hook), jamais $HOME/.claude en dur, pour qu'un worktree de
# ~/.claude se teste lui-même. PIPELINE_GAUNTLET_ROOT surcharge le dossier du gauntlet (tests des hooks).
#
#   hook_input                 lit l'entrée JSON : input agent cwd scratch tool log_cmd
#   hook_deny <raison> [raison au journal]   refuse l'outil (PreToolUse), l'écrit au journal, sort du hook
#   hook_ctx_deny <raison>     contexte illisible : refuse Edit, Write et Serena ; Bash passe (le gate reste le filet)
#   hook_targets               les fichiers visés : skind served targets (Serena, Bash, chemin)
#   hook_normalize <chemin>    absolu canonique, relatif à $cwd ; le fichier et ses parents peuvent manquer
#   hook_check_common <fichier> <refus hors du projet>   ce que toutes les zones refusent ou laissent passer
#   hook_run_root feature|fix <cwd> [fichier] [transcript]   le worktree du run et son nom : HOOK_ROOT HOOK_RUN
#   gate_run <commande du gate…>   joue le gate d'un agent qui s'arrête et décide s'il peut sortir
#
# L'appelant pose HOOK_NAME (nom du hook au journal) et HOOK_LABEL (préfixe des refus communs : « pipeline »,
# « fix ») ; HOOK_DENY_SUFFIX s'ajoute à chaque refus (fix : « écriture par Bash : même zone… »).

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAUNTLET_ROOT="${PIPELINE_GAUNTLET_ROOT:-$(cd "$HOOKS_DIR/../scripts/gauntlet" && pwd)}"
HOOK_SCRIPTS="$(cd "$GAUNTLET_ROOT/.." && pwd)"
# Journal (ADR 0019) : une ligne par décision dans <dossier du run>/.gauntlet/hooks.jsonl ; jamais bloquant.
source "$GAUNTLET_ROOT/hook_log.sh"
# shellcheck source=../scripts/gauntlet/lib.sh
source "$GAUNTLET_ROOT/lib.sh"   # hook_worktree_root, hook_agent_transcript ; init_project_context (pipeline)
source "$GAUNTLET_ROOT/serena_guard.sh"
RUN_DIR=""; LOG_TARGET=""; HOOK_DENY_SUFFIX="${HOOK_DENY_SUFFIX:-}"

hook_input() {
  input="$(cat)"
  agent="$(jq -r '.agent_type // empty' <<<"$input")"
  cwd="$(jq -r '.cwd // empty' <<<"$input")"
  scratch="$(jq -r '.scratchpad_dir // empty' <<<"$input")"
  tool="$(jq -r '.tool_name // empty' <<<"$input")"
  log_cmd="$(jq -r '.tool_input.command // empty' <<<"$input")"
}

# hook_log_decision <issue> <raison> — le dossier du run est cherché une fois, au premier besoin.
hook_log_decision() {
  [ -n "$RUN_DIR" ] || RUN_DIR="$(hook_run_dir "$agent" "${cwd:-$PWD}" "$input" "${file:-}")"
  hook_log "$RUN_DIR" "$HOOK_NAME" "$agent" "$tool" "${LOG_TARGET:-${file:-$log_cmd}}" "$1" "$2${log_cmd:+ — bash: $log_cmd}"
}

hook_deny() {
  hook_log_decision deny "${2:-$1}"
  jq -n --arg r "$1$HOOK_DENY_SUFFIX" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

hook_ctx_deny() { [ "$tool" = Bash ] && exit 0; hook_deny "$1"; }

# Serena (ADR 0018) : liste fermée d'outils. La lecture passe si le serveur de l'agent sert bien ce worktree
# (vérifié par l'appelant, qui connaît le worktree) ; un outil d'écriture va à la même zone qu'un Edit du
# fichier de relative_path ; tout autre outil Serena est refusé. Bash : les fichiers que la commande écrit
# (bash_write_targets.py). Sinon file_path ou notebook_path.
hook_targets() {
  local rp
  skind="$(serena_kind "$tool")"; served=""; targets=""
  if [ -n "$skind" ]; then
    [ "$skind" = other ] && hook_deny "$HOOK_LABEL : outil Serena hors liste ($tool). Permis : $SERENA_READ_TOOLS. Un refus se rapporte, il ne se contourne pas."
    served="$(serena_served "${cwd:-$PWD}")"
    [ -n "$served" ] || hook_deny "$HOOK_LABEL : Serena ne sert aucun worktree connu. Cherche les usages avec grep, et dis-le dans ton rapport."
    if [ "$skind" = write ]; then
      rp="$(jq -r '.tool_input.relative_path // empty' <<<"$input")"
      [ -n "$rp" ] || hook_deny "$HOOK_LABEL : $tool sans relative_path."
      targets="$(serena_target "$served" "$rp")"
    fi
  elif [ "$tool" = Bash ]; then
    targets="$(jq -r '.tool_input.command // empty' <<<"$input" | python3 "$GAUNTLET_ROOT/bash_write_targets.py" "${cwd:-$PWD}")"
  else
    targets="$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")"
  fi
  return 0
}

hook_normalize() {
  local p="$1" rest=""
  case "$p" in /*) ;; *) p="$cwd/$p" ;; esac
  while [ ! -d "$p" ] && [ "$p" != "/" ]; do rest="/$(basename "$p")$rest"; p="$(dirname "$p")"; done
  printf '%s%s' "$(cd "$p" && pwd -P)" "$rest"
}

# hook_check_common <fichier> <refus hors du projet> — avant la zone de l'agent. Pose abs, rel, LOG_TARGET,
# IN_ZONE. Rend 0 : fichier dans $PROJECT_ROOT, la zone de l'agent décide (IN_ZONE=1). Rend 1 : permis sans
# zone (brouillon du scratchpad, hors du projet par Bash : journaux, /tmp). Un refus sort du hook.
hook_check_common() {
  local file="$1"
  abs="$(hook_normalize "$file")"; LOG_TARGET="$abs"; IN_ZONE=0
  in_serena_dir "$abs" && hook_deny "$HOOK_LABEL : .serena/ est la config de Serena, réécrite par serena.sh à chaque démarrage ; personne n'y écrit (ADR 0018). Refusé : $file"
  [ "$skind" = write ] && serena_generated "$abs" && hook_deny "$HOOK_LABEL : $file est un fichier généré : Serena n'y écrit pas, la prochaine génération l'écraserait. Change sa source et relance le générateur (build_runner, gen-l10n)."
  [ -n "$scratch" ] && [[ "$abs" == "$scratch"/* ]] && return 1
  if [[ "$abs" != "$PROJECT_ROOT"/* ]]; then
    [ "$tool" = Bash ] && return 1
    hook_deny "$2"
  fi
  rel="${abs#$PROJECT_ROOT/}"; LOG_TARGET="$rel"; IN_ZONE=1
  return 0
}

# hook_run_root feature|fix <cwd> [fichier] [transcript de l'agent] — le run de l'agent.
#   HOOK_ROOT : le worktree du run (hook_worktree_root : fichier écrit, cwd, prompt de l'agent), sinon <cwd> :
#               un sous-agent hérite parfois du cwd du checkout principal (session ouverte sur le projet, reprise).
#   HOOK_RUN  : son nom, branche feature/<nom> | fix/<nom> de HOOK_ROOT, sinon .claude/features|fixes/.current
#               de sa racine git ; vide s'il est inconnu.
# Rend 1 si HOOK_ROOT n'est pas dans un dépôt git.
hook_run_root() {
  local kind="$1" top
  HOOK_ROOT="$2"; HOOK_RUN=""
  top="$(hook_worktree_root "$kind" "$2" "${3:-}" "${4:-}")" && HOOK_ROOT="$top"
  top="$(git -C "$HOOK_ROOT" rev-parse --show-toplevel 2>/dev/null)" || return 1
  HOOK_RUN="$(_git_named "$top" "$kind/" "$( [ "$kind" = fix ] && echo fixes || echo features )")"
  return 0
}

# gate_run <commande du gate…> — joue le gate de $profile, écrit le verdict, et sort du hook :
#   vert → gate_set PASSED 0, exit 0 ;
#   rouge, moins de $max tentatives → gate_set RED, exit 2, la sortie du gate sur stderr (l'agent continue) ;
#   rouge à la $max-ième → gate_set FAILED, exit 0 : l'agent sort et rapporte, l'orchestrateur appelle le dev.
# Attend : agent profile max attempts (tentatives déjà comptées) PROJECT_ROOT, GATE_DIR (dossier du run),
# GATE_OUT (où le gate écrit last_<profil>.{log,json} : <run>/.gauntlet, ou son sous-dossier de couche), et une
# fonction gate_set <statut> <tentatives>. Facultatifs : GATE_LOG_LABEL
# (« Sortie du gauntlet »), GATE_FAILED_HINT (fin du message FAILED).
# Marqueur « gate en cours » (<run>/.gauntlet/hook_<profil>.running) : le rapport de l'agent arrive à l'orchestrateur avant la
# fin de ce hook ; pipeline.sh next/join, fix.py after et les gauntlets attendent qu'il disparaisse (hook_wait.sh).
gate_log() {   # gate_log <issue> <raison> — journal (ADR 0019), avec les checks rouges du dernier gate
  local failed; failed="$(jq -r '(.failed // []) | join(" ")' "$GATE_OUT/last_${profile}.json" 2>/dev/null)"
  hook_log "$GATE_DIR" "$HOOK_NAME" "$agent" Stop "" "$1" "$2${failed:+ : $failed}" "$profile"
}
gate_run() {
  local log="$GATE_OUT/last_${profile}.log"
  mkdir -p "$GATE_DIR/.gauntlet"
  GATE_RUNNING="$GATE_DIR/.gauntlet/hook_${profile}.running"
  echo "$$ $(date +%s) $agent" > "$GATE_RUNNING"
  trap 'rm -f "$GATE_RUNNING"' EXIT
  export PIPELINE_GATE_HOOK=1
  if "$@" >/dev/null 2>&1; then
    gate_set PASSED 0
    exit 0
  fi
  attempts=$((attempts+1))
  if [ "$attempts" -ge "$max" ]; then
    gate_set FAILED "$attempts"
    gate_log failed "gate $profile rouge après $attempts tentatives, étape FAILED"
    {
      echo "$HOOK_NAME : gate '$profile' toujours rouge après $attempts tentatives. Étape marquée FAILED."
      echo "Arrête-toi et rends un rapport : ce qui bloque, ce que tu as essayé, ce que tu recommandes${GATE_FAILED_HINT:-}."
    } >&2
    exit 0
  fi
  gate_set RED "$attempts"
  gate_log red "gate $profile rouge (tentative $attempts/$max)"
  {
    echo "GATE '$profile' ROUGE (tentative $attempts/$max) — tu ne peux pas t'arrêter tant que ce n'est pas vert."
    echo "${GATE_LOG_LABEL:-Sortie} (${log#$PROJECT_ROOT/}) :"
    echo "----------------------------------------------------------------"
    grep -vE '^\s*$' "$log" | tail -60
    echo "----------------------------------------------------------------"
    echo "Corrige, puis termine à nouveau : le gate se relancera automatiquement."
  } >&2
  exit 2
}
