#!/usr/bin/env bash
# serena_guard.sh — sourcé par les hooks *-restrict-writes.sh (ADR 0018). La config de Serena n'est pas la
# barrière (un .serena/project.yml peut rouvrir serena_repl) : les hooks gardent leur propre liste fermée.
#
#   serena_kind <tool_name>    read | write | other ; rien si ce n'est pas un outil mcp__serena__*
#   serena_served <cwd>        le worktree que sert le serveur Serena de l'agent (scripts/serena.sh which)
#   serena_target <worktree> <relative_path>   le fichier visé par un outil d'écriture, absolu et normalisé
#   in_serena_dir <chemin absolu>   vrai sous un dossier .serena/ (config de Serena : personne n'y écrit)
SERENA_READ_TOOLS="find_symbol get_symbols_overview find_referencing_symbols find_implementations find_declaration get_diagnostics_for_file"
# Préparés et passés par la zone de Edit, donnés à aucun agent pour l'instant (point 9 du plan).
SERENA_WRITE_TOOLS="replace_symbol_body insert_after_symbol insert_before_symbol safe_delete_symbol"
SERENA_SH="${SERENA_SH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/serena.sh}"

serena_kind() {
  local t="${1#mcp__serena__}" x
  [ "$t" != "$1" ] || return 0
  for x in $SERENA_READ_TOOLS; do [ "$t" = "$x" ] && { echo read; return 0; }; done
  for x in $SERENA_WRITE_TOOLS; do [ "$t" = "$x" ] && { echo write; return 0; }; done
  echo other
}

serena_served() { bash "$SERENA_SH" which "$1" 2>/dev/null; }

# relative_path joint au worktree, `..` résolus sans suivre de lien (le fichier peut ne pas exister) ;
# un chemin absolu est pris tel quel. Le hook décide ensuite comme pour un Edit de ce fichier.
serena_target() {
  local w="$1" r="$2" p out="" part
  case "$r" in /*) p="$r" ;; *) p="$w/$r" ;; esac
  local IFS=/
  for part in $p; do
    case "$part" in ""|.) ;; ..) out="${out%/*}" ;; *) out="$out/$part" ;; esac
  done
  printf '%s' "${out:-/}"
}

in_serena_dir() { case "$1" in */.serena|*/.serena/*) return 0 ;; esac; return 1; }
