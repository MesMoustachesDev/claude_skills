#!/usr/bin/env bash
# pipeline.sh recap — le résumé « Reprendre le fil » du panneau pipeline-view.
# L'orchestrateur l'écrit à chaque point d'étape à partir de sa propre lecture de discussion.md : c'est un texte de
# modèle. Le script décide : schéma fermé, bornes de longueur, une ligne par chaîne ; hors schéma, refus et
# pipeline.json intact. `set recap…` est refusé pour que la validation ne se contourne pas.
source "$(dirname "$0")/fixture.sh"

PIPELINE_SH="$TESTS_DIR/../../pipeline.sh"
R="$TMP_ROOT/repo"; mk_repo "$R"; write_cfg "$R"
pipeline "$R" x '{"mode":"new","package":"app/features/feat","stages":{}}'
PIPE="$R/.claude/features/x/pipeline.json"
J="$TMP_ROOT/recap.json"
recap() { printf '%s' "$1" > "$J"; OUT="$(cd "$R" && bash "$PIPELINE_SH" recap x "$J" 2>&1)"; RC=$?; }
setp() { OUT="$(cd "$R" && bash "$PIPELINE_SH" set x "$1" "$2" 2>&1)"; RC=$?; }
# refused <json> <mot attendu dans le message> <libellé> — refus, et pipeline.json inchangé octet pour octet
refused() {
  cp "$PIPE" "$TMP_ROOT/before.json"
  recap "$1"
  expect_rc 2 "$3"
  expect_out "$2" "$3 : le message nomme « $2 »"
  cmp -s "$PIPE" "$TMP_ROOT/before.json" && _pass "$3 : pipeline.json intact" || _fail "$3 : pipeline.json modifié"
}
L81="$(printf 'a%.0s' $(seq 81))"
L80="$(printf 'a%.0s' $(seq 80))"

echo "recap valide — écrit, avec l'heure et l'étape courante"
recap "{\"goal\":\"$L80\",\"decided\":[\"une décision\",\"une autre\"]}"
expect_rc 0 "recap accepté"
OUT="$(jq -r '.recap.goal' "$PIPE")"; expect_out "$L80" "goal écrit (80 caractères acceptés)"
OUT="$(jq -c '[.recap.decided, .recap.open, .recap.aside]' "$PIPE")"
expect_out '[["une décision","une autre"],[],[]]' "listes absentes → []"
OUT="$(jq -r '.recap.at' "$PIPE")"; [ -n "$OUT" ] && [ "$OUT" != null ] && _pass "at posé" || _fail "at absent"
KEY="$(cd "$R" && bash "$PIPELINE_SH" next x --json | jq -r .key)"
OUT="$(jq -r '.recap.stage' "$PIPE")"; expect_out "$KEY" "stage = clé de pipeline.sh next ($KEY)"

echo "hors bornes — refusé, pipeline.json intact"
refused "{\"goal\":\"$L81\"}" goal "goal de 81 caractères"
refused '{"goal":"g","decided":["1","2","3","4","5","6"]}' decided "6 décisions"
refused '{"goal":"g","open":["1","2","3","4"]}' open "4 questions ouvertes"
refused '{"goal":"g","aside":["1","2","3","4"]}' aside "4 hors périmètre"
refused "{\"goal\":\"g\",\"decided\":[\"$L81\"]}" decided "décision de 81 caractères"

echo "forme — refusé, pipeline.json intact"
refused '{"goal":"g","decided":["deux\nlignes"]}' decided "chaîne sur deux lignes"
refused '{"goal":"g","decided":[""]}' decided "chaîne vide"
refused '{"goal":"g","decided":"x"}' decided "decided pas une liste"
refused '{"goal":3}' goal "goal nombre"
refused '{"decided":["a"]}' goal "goal absent"
refused '{"goal":"g","why":"x"}' why "champ inconnu"
refused '[1]' objet "pas un objet"
refused 'pas du json' JSON "fichier illisible"
cp "$PIPE" "$TMP_ROOT/before.json"
OUT="$(cd "$R" && bash "$PIPELINE_SH" recap x "$TMP_ROOT/absent.json" 2>&1)"; RC=$?
expect_rc 2 "fichier absent"
cmp -s "$PIPE" "$TMP_ROOT/before.json" && _pass "fichier absent : pipeline.json intact" || _fail "fichier absent : pipeline.json modifié"

echo "set — recap ne s'écrit que par pipeline.sh recap"
setp recap '{}'
expect_rc 2 "set recap refusé"
expect_out "pipeline.sh recap" "le refus dit quoi utiliser"
setp recap.goal '"a"'
expect_rc 2 "set recap.goal refusé"

finish
