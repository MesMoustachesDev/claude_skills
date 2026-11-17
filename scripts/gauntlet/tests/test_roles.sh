#!/usr/bin/env bash
# Rôles (ADR 0016) — roles_index produit l'index du workspace par rôle, même avant que le package de la
# feature existe (GAUNTLET_PACKAGE sur un package partagé) ; roles exige un rôle du vocabulaire sur chaque
# déclaration réutilisable ajoutée, et n'est pas applicable sans vocabulaire ; dedup_candidates rapproche
# deux déclarations du même rôle quels que soient leurs noms.
source "$(dirname "$0")/fixture.sh"
need_fvm

R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R" "ds.package = design"
F=app/features
mk_pkg "$R/$F/core" core
mk_pkg "$R/$F/design" design
mk_pkg "$R/$F/home" home
cat > "$R/$F/design/lib/empty.dart" <<'X'
/// Bloc affiché quand une liste n'a rien à montrer.
/// rôle: état-vide
class DesignEmptyState extends StatelessWidget {}
X
cat > "$R/$F/core/lib/tools.dart" <<'X'
String formatBytes(int n) => '$n';
X
commit "$R" "develop" >/dev/null
git -C "$R" checkout -q -b feature/x

echo "roles_index — sans vocabulaire, avant le package de la feature"
mkdir -p "$R/.claude/features/x"
OUT="$(cd "$R" && GAUNTLET_PACKAGE="$F/core" bash "$GAUNTLET" roles_index x 2>&1)"; RC=$?
expect_rc 0 "producteur toujours vert"
I="$R/.claude/features/x/roles_index.md"
[ -f "$I" ] && _pass "roles_index.md écrit" || _fail "roles_index.md absent"
grep -qF '`DesignEmptyState` (classe, design)' "$I" && _pass "déclaration marquée indexée" || _fail "DesignEmptyState absent de l'index"
grep -qF '`formatBytes` (fonction, core)' "$I" && _pass "déclaration sans rôle du package partagé listée" || _fail "formatBytes absent"

pipeline "$R" x '{"mode":"extend","package":"app/features/home"}'
mkdir -p "$R/$F/home/lib/src/presentation"
cat > "$R/$F/home/lib/src/presentation/home_empty.dart" <<'X'
/// rôle: état-vide
class HomeEmptyContent extends StatelessWidget {}

class HomeCard extends StatelessWidget {}
X

echo "roles — sans vocabulaire : non applicable"
run_g "$R" roles x
expect_rc 0 "pas de vocabulaire, pas de blocage"
expect_out "pas de vocabulaire de rôles" "raison dite"

echo "roles — avec vocabulaire"
printf '# Rôles\n- `état-vide` : un bloc sans données\n' > "$R/.claude/rules/roles.md"
run_g "$R" roles x
expect_rc 1 "une déclaration sans rôle bloque"
expect_out "sans rôle    classe HomeCard" "HomeCard nommée"
expect_no_out "HomeEmptyContent" "la déclaration marquée passe"

echo "roles — rôle hors vocabulaire"
sed -i '' 's#^class HomeCard#/// rôle: bidule\nclass HomeCard#' "$R/$F/home/lib/src/presentation/home_empty.dart" 2>/dev/null \
  || sed -i 's#^class HomeCard#/// rôle: bidule\nclass HomeCard#' "$R/$F/home/lib/src/presentation/home_empty.dart"
grep -q 'bidule' "$R/$F/home/lib/src/presentation/home_empty.dart" || printf '/// rôle: bidule\nclass HomeBidule extends StatelessWidget {}\n' >> "$R/$F/home/lib/src/presentation/home_empty.dart"
run_g "$R" roles x
expect_rc 1 "un mot hors vocabulaire bloque"
expect_out "hors vocab." "signalé hors vocabulaire"

echo "dedup_candidates — même rôle, noms sans token commun"
run_g "$R" dedup_candidates x
C="$R/.claude/features/x/dedup_candidates.json"
python3 -c "
import json,sys; d=json.load(open('$C'))
ok=any(e['target']['name']=='HomeEmptyContent' and any(c['name']=='DesignEmptyState' and c.get('match')=='rôle' for c in e['candidates']) for e in d['entries'])
sys.exit(0 if ok else 1)" && _pass "HomeEmptyContent ↔ DesignEmptyState par le rôle" || _fail "paire par rôle absente"

echo "roles_todo + roles_init.py — la proposition du modèle, décodée strictement"
INIT="$TESTS_DIR/../../../stacks/flutter/roles_init.py"
run_g "$R" roles_todo x
T="$R/.claude/features/x/roles_todo.json"
grep -q '"name": "formatBytes"' "$T" && _pass "formatBytes à marquer" || _fail "formatBytes absent de roles_todo.json"
id="$(python3 -c "import json;print([d['id'] for d in json.load(open('$T'))['declarations'] if d['name']=='formatBytes'][0])")"
printf '{"roles":[{"mot":"Taille","description":"x","declarations":["%s"]}]}' "$id" > "$TMP_ROOT/bad.json"
OUT="$(python3 "$INIT" check --todo "$T" --proposal "$TMP_ROOT/bad.json" --vocab "$R/.claude/rules/roles.md" --root "$R/$F" 2>&1)"; RC=$?
expect_rc 1 "mot invalide refusé"
printf '{"roles":[{"mot":"taille-fichier","description":"une taille en octets lisible","declarations":["%s"]}]}' "$id" > "$TMP_ROOT/ok.json"
before="$(cat "$R/$F/core/lib/tools.dart")"
OUT="$(python3 "$INIT" check --todo "$T" --proposal "$TMP_ROOT/ok.json" --vocab "$R/.claude/rules/roles.md" --root "$R/$F" 2>&1)"; RC=$?
expect_rc 0 "proposition valide"
[ "$before" = "$(cat "$R/$F/core/lib/tools.dart")" ] && _pass "à blanc : code inchangé" || _fail "check a écrit dans le code"
OUT="$(python3 "$INIT" apply --todo "$T" --proposal "$TMP_ROOT/ok.json" --vocab "$R/.claude/rules/roles.md" --root "$R/$F" 2>&1)"; RC=$?
expect_rc 0 "apply"
grep -q '^/// rôle: taille-fichier$' "$R/$F/core/lib/tools.dart" && _pass "marqueur posé" || _fail "marqueur absent"
grep -q '`taille-fichier`' "$R/.claude/rules/roles.md" && _pass "mot ajouté au vocabulaire" || _fail "vocabulaire inchangé"
run_g "$R" roles_todo x
grep -q '"declarations": \[\]' "$T" && _pass "plus rien à marquer" || _fail "roles_todo non vide après apply"

echo "roles_todo + roles_init.py — variantes statiques d'un widget, // ignore:, ligne vide"
cat > "$R/$F/core/lib/extras.dart" <<'X'
class Gap extends StatelessWidget {
  static Widget get xs => const Gap();
}

extension Hex on Color {
  bool isDark() => true;
  // ignore: deprecated_member_use
  String hex() => '$value';
}
X
run_g "$R" roles_todo x
grep -q '"name": "xs"' "$T" && _fail "Gap.xs à marquer (variante d'un widget)" || _pass "variante statique d'un widget exclue"
python3 - "$T" "$TMP_ROOT/extras.json" <<'P'
import json, sys
d = json.load(open(sys.argv[1]))["declarations"]
ids = [x["id"] for x in d if x["file"].endswith("extras.dart")]
json.dump({"roles": [{"mot": "couleur", "description": "une couleur", "declarations": ids}]}, open(sys.argv[2], "w"))
P
OUT="$(python3 "$INIT" apply --todo "$T" --proposal "$TMP_ROOT/extras.json" --vocab "$R/.claude/rules/roles.md" --root "$R/$F" 2>&1)"; RC=$?
expect_rc 0 "apply sur extras.dart"
grep -B1 "String hex" "$R/$F/core/lib/extras.dart" | head -1 | grep -q 'ignore:' && _pass "// ignore: reste collé à sa ligne" || _fail "rôle inséré entre // ignore: et le code"
python3 -c "
l=open('$R/$F/core/lib/extras.dart').read().split('\n'); i=[n for n,x in enumerate(l) if 'String hex' in x][0]
import sys; sys.exit(0 if l[i-3].strip()=='' and 'rôle: couleur' in l[i-2] else 1)" && _pass "ligne vide avant la doc collée au membre précédent" || _fail "pas de ligne vide avant le rôle"

finish
