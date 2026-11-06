# shellcheck shell=bash
# test_dups — candidats doublons : un même nom de test dans deux fichiers (le package et ceux où la feature
# a écrit des tests). Ne bloque pas : un nom générique (« maps every field ») peut désigner deux classes.
# La liste va dans .gauntlet/test_dups.txt, que Gaëlle tranche (create_test.md, principe 18).
check_test_dups() {
  [ -d "$PKG_DIR/test" ] || return 0
  local out="$GAUNTLET_OUT/test_dups.txt" all hits names
  # shellcheck disable=SC2046
  all="$(python3 "$GAUNTLET_ROOT/test_dups.py" "$PROJECT_ROOT" "$PKG_REL" $(extra_test_packages 2>/dev/null))"
  # Seuls les noms dont une occurrence au moins est dans le périmètre de la feature.
  names="$(printf '%s\n' "$all" | grep -v '^$' | filter_scope_lines "" | sed -E 's/^[^:]+:[0-9]+: //' | sort -u)"
  if [ -z "$names" ]; then : > "$out"; info "aucun nom de test en double"; return 0; fi
  hits="$(printf '%s\n' "$all" | awk -v names="$names" '
    BEGIN { n = split(names, a, "\n"); for (i = 1; i <= n; i++) keep[a[i]] = 1 }
    { name = $0; sub(/^[^:]+:[0-9]+: /, "", name); if (name in keep) print }')"
  printf '%s\n' "$hits" > "$out"
  info "$(printf '%s\n' "$names" | grep -c .) nom(s) de test en double, à trancher par Gaëlle : ${out#"$PROJECT_ROOT"/}"
  printf '%s\n' "$hits" | head -12 | sed 's/^/   ? /'
  return 0
}
