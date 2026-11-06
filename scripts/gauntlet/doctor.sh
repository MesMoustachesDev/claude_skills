#!/usr/bin/env bash
# doctor.sh — vérifie que le projet et la machine peuvent faire tourner le pipeline. Sourcé par gauntlet.sh.

DOCTOR_RC=0
need() { # need <label> <cmd...>
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$label"; else ko "$label"; DOCTOR_RC=1; fi
}
warn_if() { # warn_if <label> <cmd...>  (non bloquant)
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$label"; else printf '[WARN] %s\n' "$label"; fi
}
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

run_doctor() {
  section "outils"
  need "git"  git --version
  need "jq"   jq --version
  need "bash ≥ 4 ($BASH_VERSION)" ver_ge "${BASH_VERSION%%(*}" 4.0
  need "maestro" maestro --version

  # Outils du langage de l'app (stacks/<langage>/checks.sh → stack_doctor).
  section "langage : ${STACK:-non reconnu}"
  if declare -F stack_doctor >/dev/null; then stack_doctor
  else printf '[N/A]  outils du langage : non applicable à %s (pas de stack_doctor)\n' "${STACK:-ce projet, langage non reconnu}"; fi

  section "configuration ($CFG_FILE)"
  need "package_path défini" test -n "$(cfg package_path)"
  need "base_branch existe ($BASE_BRANCH)" git -C "$PROJECT_ROOT" rev-parse --verify "$BASE_BRANCH"
  need "create_feature_rules.md présent" test -f "$PROJECT_ROOT/.claude/rules/create_feature_rules.md"
  # Règles que Claude Code charge d'office dans chaque agent, depuis .claude/rules/ du projet. Absente : le preflight
  # (steps/00_preconditions.md) demande à Thibault de la créer depuis le template, de copier le template tel quel,
  # ou de s'en passer (rules.none).
  for r in create_screen_rules.md pr_rules.md; do
    if [ -f "$PROJECT_ROOT/.claude/rules/$r" ] || compgen -G "$PROJECT_ROOT/*/.claude/rules/$r" >/dev/null; then ok "$r (règle du projet)"
    elif cfg_list rules.none | grep -qxF "$r"; then ok "$r : sans objet pour ce projet (rules.none)"
    else printf '[WARN] RÈGLE ABSENTE : %s — aucun agent ne la reçoit ; à trancher au preflight\n' "$r"; fi
  done
  # Tracker des tickets (~/.claude/pipeline/tracker.md). Vide = défaut (gitlab si le remote l'est, sinon none).
  case "$(cfg tracker)" in
    ""|none) ok "tracker : $(cfg tracker none)" ;;
    gitlab)
      need "tracker gitlab : glab authentifié — glab auth login" glab auth status
      if [ -n "$(cfg tracker.gitlab.project)" ]; then
        need "tracker gitlab : projet $(cfg tracker.gitlab.project) accessible" \
          sh -c "cd '$PROJECT_ROOT' && glab repo view '$(cfg tracker.gitlab.project)' -F json"
      fi ;;
    notion) need "tracker notion : tracker.notion.database renseigné — /feature init" test -n "$(cfg tracker.notion.database)" ;;
    *) ko "tracker inconnu : $(cfg tracker) (gitlab | notion | none)"; DOCTOR_RC=1 ;;
  esac

  section "plateformes QA"
  for p in $(cfg_list qa.platforms); do
    case "$p" in
      android)
        need "adb" adb --version
        need "AVD '$(cfg android.avd)' existe" sh -c "'$HOME/Library/Android/sdk/emulator/emulator' -list-avds | grep -qx '$(cfg android.avd)'"
        need "android.app_id renseigné" sh -c "[ -n '$(cfg android.app_id)' ] && [ '$(cfg android.app_id)' != com.example.app ]"
        ;;
      ios)
        need "xcrun simctl" xcrun simctl help
        if [ -n "$(cfg ios.simulator_base)" ]; then
          need "simulateur modèle '$(cfg ios.simulator_base)' disponible (sim.sh)" sh -c "xcrun simctl list devices available | grep -q '    $(cfg ios.simulator_base) ('"
        else
          need "simulateur '$(cfg ios.simulator)' disponible" sh -c "xcrun simctl list devices available | grep -q '$(cfg ios.simulator) ('"
        fi
        need "ios.app_id renseigné" sh -c "[ -n '$(cfg ios.app_id)' ] && [ '$(cfg ios.app_id)' != com.example.app ]"
        ;;
      *) ko "plateforme inconnue : $p"; DOCTOR_RC=1 ;;
    esac
  done

  section "résumé"
  [ "$DOCTOR_RC" = 0 ] && ok "le projet peut faire tourner le pipeline" || ko "corriger les points ci-dessus avant /feature"
  return $DOCTOR_RC
}
