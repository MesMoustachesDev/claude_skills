#!/usr/bin/env bash
# serena_guard.sh — sourcé par les hooks *-restrict-writes.sh (ADR 0018). La config de Serena n'est pas la
# barrière (un .serena/project.yml peut rouvrir serena_repl) : les hooks gardent leur propre liste fermée.
#
#   serena_kind <tool_name>    read | write | other ; rien si ce n'est pas un outil mcp__serena__*
#   serena_served <cwd>        le worktree que sert le serveur Serena de l'agent (scripts/serena.sh which)
#   serena_target <worktree> <relative_path>   le fichier visé par un outil d'écriture, absolu et normalisé
#   in_serena_dir <chemin absolu>   vrai sous un dossier .serena/ (config de Serena : personne n'y écrit)
SERENA_READ_TOOLS="find_symbol get_symbols_overview find_referencing_symbols find_implementations find_declaration get_diagnostics_for_file"
# Écriture (implementer, ses moitiés, cleaner : serena.sh serve --ecriture) : le fichier de relative_path
# passe par la zone de Edit. safe_delete_symbol et rename_symbol n'y sont pas : refusés comme tout outil
# inconnu (le premier casse une variable ou un champ, le second réécrit des fichiers que le hook ne voit pas).
SERENA_WRITE_TOOLS="replace_symbol_body insert_after_symbol insert_before_symbol"
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

# serena_generated <chemin> — vrai pour un fichier généré (*.g.dart, *.freezed.dart, l10n générée…) : Serena
# y écrit sans broncher (essai du 2026-11-19), la prochaine génération l'écraserait. Motifs : ceux du contexte
# du gauntlet ($GENERATED_ERE, stack et config du projet) s'il est chargé, sinon generated.exclude de la
# stack Flutter (Serena ne sert que Dart).
SERENA_STACK_INI="${SERENA_STACK_INI:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/stacks/flutter/stack.ini}"
serena_generated() {
  local ere="${GENERATED_ERE:-}" alts
  if [ -z "$ere" ]; then
    alts="$(grep -E '^[[:space:]]*generated\.exclude[[:space:]]*=' "$SERENA_STACK_INI" 2>/dev/null | head -1 \
      | sed 's/^[^=]*=//' | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' \
      | sed -e 's#^\*\*/##' -e 's/[].[^$+(){}|\\]/\\&/g' -e 's/\*\*/*/g' -e 's/\*/.*/g' -e 's#?#[^/]#g' | paste -sd '|' -)"
    [ -n "$alts" ] && ere="(^|/)($alts)$"
  fi
  [ -n "$ere" ] && printf '%s\n' "$1" | grep -qE "$ere"
}
