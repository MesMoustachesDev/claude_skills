#!/usr/bin/env bash
# graphify.sh impact — consommateurs hors package, dépendances, ordre de lecture (spec graphify partagé §3.1, §3.3).
# Pas de Flutter ni de fvm : le graphe est un JSON écrit à la main.
source "$(dirname "$0")/fixture.sh"
source "$(dirname "$0")/graphify_fixture.sh"

new_repo() { local d="$TMP_ROOT/$1/with space/repo"; mk_impact_repo "$d" "${2:-plain}"; REPO="$d"; }
CONSUMER='len(d["consumers"])==1 and all(d["consumers"][0].get(k)==v for k,v in {"package":"features/b","symbol":"B_Bloc","via":"A_Repo","touched":False,"classified":True,"removed":False}.items())'

echo "impact_consumer"
new_repo consumer
run_impact "$REPO"
expect_rc 0 "sortie 0"
expect_out "graphify: ok" "dernière ligne d'état"
expect_json "$REPO/out/impact.json" "d['status']=='ok'" "status ok"
expect_json "$REPO/out/impact.json" "$CONSUMER" "b/B_Bloc via A_Repo, non touché, classé (seul consommateur)"
expect_json "$REPO/out/impact.json" "any(x['package']=='features/design' for x in d['dependencies'])" "design en dépendance"
expect_json "$REPO/out/impact.json" "not any('core' in json.dumps(x) or 'SDK_Future' in json.dumps(x) or '_priv' in json.dumps(x) for x in d['consumers']+d['dependencies'])" "ni core, ni SDK_Future, ni _priv"

echo "impact_uncommitted_counts"
expect_json "$REPO/out/impact.json" "len(d['consumers'])>0" "le fichier modifié non commité est dans le diff"

echo "impact_touched"
echo "// b modifié" >> "$REPO/features/b/lib/src/bloc.dart"
run_impact "$REPO"
expect_json "$REPO/out/impact.json" "len(d['consumers'])==1 and d['consumers'][0]['touched'] is True" "consommateur modifié par la PR → touched"

echo "impact_reading_order"
new_repo order
echo "void main() {}" > "$REPO/features/a/test/x_test.dart"
run_impact "$REPO"
expect_json "$REPO/out/impact.json" "d['reading_order'][0]['file']=='features/a/lib/src/data/foo_impl.dart'" "ordre de lecture : fichier d'A_Repo en tête"
expect_json "$REPO/out/impact.json" "'features/a/test/x_test.dart' in d['not_in_graph']" "test hors graphe"

echo "impact_scan_root_is_repo_root"
new_repo rootscan rootscan
run_impact "$REPO"
expect_json "$REPO/out/impact.json" "$CONSUMER" "racine de scan = racine du repo : mêmes consommateurs"

echo "impact_removed_symbol"
new_repo removed
python3 - "$REPO" <<'PY'
import json, sys
r = sys.argv[1]
d = json.load(open(r + "/graphify-out/graph.json"))
d["nodes"].append({"id": "A_Old", "label": "A_Old", "source_file": "a/lib/src/data/foo_impl.dart", "source_location": "L50"})
d["links"].append({"source": "B_Bloc", "target": "A_Old", "relation": "calls", "source_file": "b/lib/src/bloc.dart", "source_location": "L60"})
json.dump(d, open(r + "/graphify-out/graph.base.json", "w"))
PY
run_impact "$REPO"
expect_json "$REPO/out/impact.json" "any(c['symbol']=='B_Bloc' and c['via']=='A_Old' and c['removed'] is True for c in d['consumers']) and any(c['via']=='A_Repo' and c['removed'] is False for c in d['consumers'])" "B_Bloc via A_Old supprimé"

echo "impact_removed_symbol_renamed_file"
new_repo renamed
python3 - "$REPO" <<'PY'
import json, sys
r = sys.argv[1]
d = json.load(open(r + "/graphify-out/graph.json"))
d["nodes"].append({"id": "A_Old", "label": "A_Old", "source_file": "a/lib/src/data/foo_impl.dart", "source_location": "L50"})
d["links"].append({"source": "B_Bloc", "target": "A_Old", "relation": "calls", "source_file": "b/lib/src/bloc.dart", "source_location": "L60"})
json.dump(d, open(r + "/graphify-out/graph.base.json", "w"))
d["nodes"] = [n for n in d["nodes"] if n["id"] != "A_Old"]
d["links"] = [l for l in d["links"] if "A_Old" not in (l["source"], l["target"])]
json.dump(d, open(r + "/graphify-out/graph.json", "w"))
PY
git -C "$REPO" mv features/a/lib/src/data/foo_impl.dart features/a/lib/src/data/repo_impl.dart
commit "$REPO" "rename" >/dev/null
run_impact "$REPO"
expect_json "$REPO/out/impact.json" "any(c['symbol']=='B_Bloc' and c['via']=='A_Old' and c['removed'] is True for c in d['consumers'])" "fichier renommé : B_Bloc via A_Old supprimé toujours listé"

echo "impact_ignore_cfg"
new_repo ignore
mkdir -p "$REPO/.claude/rules"
printf '# t\n```ini\ngraphify.ignore_packages = b\n```\n' > "$REPO/.claude/rules/feature_pipeline.md"
run_impact "$REPO"
expect_json "$REPO/out/impact.json" "d['consumers']==[]" "ignore_packages = b → aucun consommateur"

echo "impact_absent"
A="$TMP_ROOT/absent/with space/repo"; mk_repo "$A"; echo x > "$A/f.txt"; commit "$A" develop >/dev/null
OUT="$(bash "$GRAPHIFY_SH" impact "$A" develop 2>/dev/null)"; RC=$?
expect_rc 0 "sortie 0 sans graphe"
[ "$(printf '%s\n' "$OUT" | tail -1)" = "graphify: absent" ] && _pass "dernière ligne « graphify: absent »" || _fail "dernière ligne"
expect_json "$A/graphify-out/impact/impact.json" "d['status']=='absent'" "impact.json status absent (--out par défaut)"

echo "impact_corrupt"
new_repo corrupt
printf '{' > "$REPO/graphify-out/graph.json"
run_impact "$REPO"
expect_rc 0 "sortie 0 graphe corrompu"
expect_json "$REPO/out/impact.json" "d['status']=='failed'" "status failed"
expect_out "graphify: échec" "ligne d'état échec"

echo "impact_stale"
new_repo stale
printf 'stale' > "$REPO/graphify-out/.prepare_status"
run_impact "$REPO"
expect_json "$REPO/out/impact.json" "d['status']=='stale' and len(d['consumers'])==1" "stale : impact calculé quand même"
expect_file_has "$REPO/out/impact.md" "⚠" "avertissement en tête de impact.md"

echo "impact_md"
new_repo md
run_impact "$REPO"
expect_file_has "$REPO/out/impact.md" "### Consommateurs hors package non touchés" "section consommateurs"
expect_file_has "$REPO/out/impact.md" "| features/b | B_Bloc | A_Repo |" "ligne consommateur"
expect_file_has "$REPO/out/impact.md" "### Dépendances" "section dépendances"
expect_file_has "$REPO/out/impact.md" "### Ordre de lecture du diff" "section ordre de lecture"

finish
