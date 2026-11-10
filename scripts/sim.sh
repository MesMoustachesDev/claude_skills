#!/usr/bin/env bash
# sim.sh — un simulateur iOS par run (fix, feature, revue), cloné d'un simulateur modèle.
#
# Usage :
#   sim.sh ensure <nom>   clone le modèle en « <modèle> · <nom> » s'il n'existe pas, le boote, imprime son UDID
#   sim.sh remove <nom>   shutdown puis delete du clone (rien à faire s'il n'existe pas)
#   sim.sh udid <nom>     UDID du clone, exit 1 s'il n'existe pas
#   sim.sh list           clones du modèle
#   sim.sh base           nom du modèle résolu, exit 1 si aucun n'est configuré
#
# Le modèle : --base <nom|udid>, sinon $SIM_BASE, sinon `ios.simulator_base` du bloc ini de
# .claude/rules/feature_pipeline.md (racine du repo courant). Il est déjà connecté au compte de test et
# porte les données de QA (rapports téléchargés) : chaque clone part de cet état. Il doit être éteint pour
# être cloné ; un clone existant, lui, se reboote sans le modèle.
#
# --like <nom|udid> à la place de --base : pas de modèle préparé, « <nom> · <run> » est créé neuf
# (simctl create, même type d'appareil et même runtime que <nom>), sans compte ni données. Le simulateur
# <nom> lui-même n'est jamais touché, allumé ou non : /reviewPR s'en sert quand ios.simulator_base est vide,
# pour ne jamais installer une app de revue sur le simulateur partagé (ios.simulator).
# Seul l'UDID va sur stdout ; les messages vont sur stderr.
set -u
set -o pipefail

msg() { printf 'sim.sh: %s\n' "$*" >&2; }
die() { msg "$*"; exit 2; }

base_name() {
  [ -n "${SIM_BASE:-}" ] && { printf '%s' "$SIM_BASE"; return; }
  local root cfg
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  cfg="$root/.claude/rules/feature_pipeline.md"
  [ -f "$cfg" ] || return 0
  awk '/^```ini/{f=1;next} /^```/{f=0} f' "$cfg" | grep -E '^[[:space:]]*ios\.simulator_base[[:space:]]*=' \
    | head -1 | sed 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//'
}

# device_field <nom|udid> <champ> — udid | state | name, du premier simulateur disponible qui correspond
device_field() {
  xcrun simctl list devices available -j \
    | jq -r --arg k "$1" --arg f "$2" '[.devices[][] | select(.name==$k or .udid==$k)][0][$f] // empty'
}

how_to_create() {
  cat >&2 <<EOF

Le simulateur modèle « $1 » n'existe pas. Pour le créer une fois :
  1. Partir d'un simulateur déjà connecté au compte de test (éteint) :
       xcrun simctl shutdown <udid> && xcrun simctl clone <udid> "$1"
     ou d'un neuf :
       xcrun simctl create "$1" "iPhone 18 Pro"
  2. Le préparer : xcrun simctl boot "$1" && open -a Simulator, installer l'app staging, se connecter au
     compte de test, télécharger les rapports dont les flows ont besoin.
  3. L'éteindre : xcrun simctl shutdown "$1"   (un modèle allumé ne se clone pas)
  4. Le nommer dans .claude/rules/feature_pipeline.md : ios.simulator_base = $1
EOF
}

# Clonage sérialisé : deux runs qui clonent en même temps le même nom ne créent pas deux appareils.
LOCK="${TMPDIR:-/tmp}/claude-sim.lock"
lock() {
  local t=180
  until mkdir "$LOCK" 2>/dev/null; do
    # Verrou de plus de 10 minutes : un sim.sh tué en plein clonage.
    [ -n "$(find "$LOCK" -maxdepth 0 -mmin +10 2>/dev/null)" ] && { rmdir "$LOCK" 2>/dev/null; continue; }
    t=$((t-1)); [ "$t" -gt 0 ] || die "verrou $LOCK tenu depuis 3 minutes"
    sleep 1
  done
  trap 'rmdir "$LOCK" 2>/dev/null' EXIT
}

# create_like <modèle> <nom du nouveau> — simulateur neuf, même type d'appareil et même runtime que <modèle>
create_like() {
  local spec dt rt
  spec="$(xcrun simctl list devices available -j | jq -r --arg k "$1" \
    '[.devices | to_entries[] | .key as $rt | .value[] | select(.name==$k or .udid==$k) | "\(.deviceTypeIdentifier) \($rt)"][0] // empty')"
  [ -n "$spec" ] || die "simulateur « $1 » introuvable : rien à imiter (ios.simulator de la config)"
  read -r dt rt <<<"$spec"
  msg "création de « $2 » ($dt, $rt)"
  xcrun simctl create "$2" "$dt" "$rt" 2>&1
}

cmd_ensure() {
  local name="$1" base="$2" clone udid state
  clone="$base · $name"
  lock
  udid="$(device_field "$clone" udid)"
  if [ -z "$udid" ] && [ "$like" = 1 ]; then
    udid="$(create_like "$base" "$clone")" || die "simctl create a échoué : $udid"
  elif [ -z "$udid" ]; then
    [ -n "$(device_field "$base" udid)" ] || { how_to_create "$base"; exit 2; }
    state="$(device_field "$base" state)"
    [ "$state" = Shutdown ] || die "le modèle « $base » est $state : il ne se clone qu'éteint. Si personne ne s'en sert : xcrun simctl shutdown \"$base\""
    msg "clonage de « $base » en « $clone »"
    udid="$(xcrun simctl clone "$base" "$clone" 2>&1)" || die "simctl clone a échoué : $udid"
  fi
  rmdir "$LOCK" 2>/dev/null; trap - EXIT
  # bootstatus -b : boote s'il le faut et attend la fin du démarrage.
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || die "« $clone » ($udid) n'a pas booté"
  printf '%s\n' "$udid"
}

cmd_remove() {
  local clone="$2 · $1" udid
  udid="$(device_field "$clone" udid)"
  [ -n "$udid" ] || { msg "« $clone » n'existe pas : rien à supprimer"; return 0; }
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  xcrun simctl delete "$udid" || die "simctl delete $udid a échoué"
  msg "« $clone » ($udid) supprimé"
}

base=""; like=0
[ "${1:-}" = --base ] && { base="${2:-}"; shift 2; }
[ "${1:-}" = --like ] && { base="${2:-}"; like=1; shift 2; }
action="${1:-}"; name="${2:-}"
case "$action" in
  ""|-h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
esac
[ -n "$base" ] || base="$(base_name)"
[ "$action" = base ] && { [ -n "$base" ] || exit 1; printf '%s\n' "$base"; exit 0; }
[ -n "$base" ] || die "pas de simulateur modèle : --base <nom>, SIM_BASE, ou ios.simulator_base dans .claude/rules/feature_pipeline.md"
case "$action" in
  list) xcrun simctl list devices available -j \
          | jq -r --arg p "$base · " '.devices[][] | select(.name|startswith($p)) | "\(.udid)  \(.state)  \(.name)"' ;;
  ensure|remove|udid)
    [ -n "$name" ] || die "usage: sim.sh $action <nom>"
    case "$name" in *[!A-Za-z0-9._-]*) die "nom « $name » : lettres, chiffres, . _ - seulement" ;; esac
    case "$action" in
      ensure) cmd_ensure "$name" "$base" ;;
      remove) cmd_remove "$name" "$base" ;;
      udid) u="$(device_field "$base · $name" udid)"; [ -n "$u" ] || exit 1; printf '%s\n' "$u" ;;
    esac ;;
  *) die "action inconnue : $action (ensure | remove | udid | list | base)" ;;
esac
