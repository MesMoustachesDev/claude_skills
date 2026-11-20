#!/usr/bin/env bash
# Repro — le banc (replay.py, run.py) lançait l'agent par `claude -p --agent`, qui ne précharge pas le champ
# `skills:` du frontmatter : chaque avant / après sur un skill ne mesurait que le corps du prompt.
# pipeline/bench/skills.py construit ce que reçoit un vrai sous-agent, et vérifie la phrase propre de chaque
# skill dans le transcript.
#   construction : commande ($ARGUMENTS vidé), skill (frontmatter retiré, « Base directory »), skill de plugin ;
#   un skill introuvable refuse la passe ;
#   contrôle : reçu une fois → rien ; absent, ou seulement lu par un outil → cassée ; reçu deux fois → cassée.
source "$(dirname "$0")/fixture.sh"

SKILLS="$TESTS_DIR/../../../pipeline/bench/skills.py"
H="$TMP_ROOT/home"; R="$H/.claude"
mkdir -p "$R/agents" "$R/commands" "$R/skills/grille" "$R/plugins/cache/mkt/plug/1.0/.claude-plugin" \
         "$R/plugins/cache/mkt/plug/1.0/skills/preuve" "$R/projects/-tmp-wt"
cat > "$R/agents/ivan.md" <<'MD'
---
name: ivan
description: un agent
skills:
  - tester
  - grille
  - plug:preuve
hooks:
  PreToolUse: []
---

Tu es Ivan. Tu fais passer les tests au vert.
MD
cat > "$R/commands/tester.md" <<'MD'
# Tester

La cible est : **$ARGUMENTS**
On écrit le test avant le code, toujours, et on le regarde échouer.
MD
cat > "$R/skills/grille/SKILL.md" <<'MD'
---
name: grille
description: la grille
---

# Grille
Chaque constat cite son fichier et sa ligne, sinon il ne compte pas.
MD
echo '{"name":"plug","version":"1.0"}' > "$R/plugins/cache/mkt/plug/1.0/.claude-plugin/plugin.json"
cat > "$R/plugins/cache/mkt/plug/1.0/skills/preuve/SKILL.md" <<'MD'
---
name: preuve
description: la preuve
---
Pas de « c'est fait » sans la sortie de la commande qui le prouve.
MD

py() { OUT="$(HOME="$H" python3 -I - "$SKILLS" "$R" "$H" "$@" 2>&1)"; RC=$?; }

echo "construction du message"
py <<'PY'
import sys, importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location('skills', sys.argv[1]); S = importlib.util.module_from_spec(spec); spec.loader.exec_module(S)
pre = S.preload('ivan', 'Racine : /tmp/wt', Path(sys.argv[2]), Path(sys.argv[3]))
texts = [b['text'] for b in pre['content']]
print('blocs', len(texts))
print('prompt-en-tete', texts[0] == 'Racine : /tmp/wt')
print('entete', texts[1] == '<command-message>tester</command-message>\n<command-name>tester</command-name>\n<skill-format>true</skill-format>')
print('commande', texts[2].startswith('# Tester\n') and '$ARGUMENTS' not in texts[2] and '**' in texts[2])
print('skill', texts[4] == f"Base directory for this skill: {Path(sys.argv[2])}/skills/grille\n\n# Grille\nChaque constat cite son fichier et sa ligne, sinon il ne compte pas.\n")
print('plugin', texts[6].startswith('Base directory for this skill: ') and texts[6].endswith("\n\nPas de « c'est fait » sans la sortie de la commande qui le prouve.\n"))
print('marqueurs', [s['marker'] for s in pre['skills']])
print('controle', S.check(pre['skills'], texts))
PY
expect_rc 0 "preload"
expect_out "blocs 7" "prompt, puis en-tête et corps de chaque skill"
expect_out "prompt-en-tete True" "le prompt de la tâche vient d'abord"
expect_out "entete True" "en-tête comme chez un sous-agent"
expect_out "commande True" "commande : corps, \$ARGUMENTS vidé"
expect_out "skill True" "skill : frontmatter retiré, « Base directory » du dossier"
expect_out "plugin True" "skill de plugin trouvé dans le cache"
expect_out "On écrit le test avant le code" "phrase propre de la commande"
expect_out "controle {'tester': 'reçu', 'grille': 'reçu', 'plug:preuve': 'reçu'}" "message construit : chaque skill une fois"

echo "skill introuvable"
sed -i.bak 's/  - plug:preuve/  - plug:absent/' "$R/agents/ivan.md"
OUT="$(HOME="$H" python3 "$SKILLS" ivan --root "$R" --home "$H" 2>&1)"; RC=$?
expect_rc 1 "skills.py refuse"
expect_out "plug:absent" "le nom manquant est dit"
mv "$R/agents/ivan.md.bak" "$R/agents/ivan.md"

echo "contrôle dans le transcript"
py <<'PY'
import sys, json, importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location('skills', sys.argv[1]); S = importlib.util.module_from_spec(spec); spec.loader.exec_module(S)
root, home = Path(sys.argv[2]), Path(sys.argv[3])
pre = S.preload('ivan', 'Racine : /tmp/wt', root, home)
def write(sid, msgs):
    (home / '.claude/projects/-tmp-wt' / f'{sid}.jsonl').write_text(''.join(json.dumps(m) + '\n' for m in msgs))
user = {'type': 'user', 'message': {'role': 'user', 'content': pre['content']}}
write('recu', [user, {'type': 'assistant', 'message': {'content': [{'type': 'text', 'text': 'ok'}]}}])
print('recu', S.broken(S.check_transcript(pre['skills'], 'recu', home)) or 'vide')
# Seulement le prompt ; l'agent ouvre lui-même la commande : un tool_result ne compte pas.
only = {'type': 'user', 'message': {'role': 'user', 'content': pre['content'][:1]}}
tool = {'type': 'user', 'message': {'role': 'user', 'content': [{'type': 'tool_result', 'content': pre['content'][2]['text']}]}}
write('absent', [only, tool])
print('absent', S.broken(S.check_transcript(pre['skills'], 'absent', home)))
meta = {'type': 'user', 'isMeta': True, 'message': {'role': 'user', 'content': pre['content'][3:5]}}
write('double', [user, meta])
print('double', S.broken(S.check_transcript(pre['skills'], 'double', home)))
print('sans-transcript', S.broken(S.check_transcript(pre['skills'], 'inconnu', home)))
PY
expect_rc 0 "check_transcript"
expect_out "recu vide" "chaque skill reçu une fois : passe gardée"
expect_out "absent passe cassée : skills préchargés tester absent, grille absent, plug:preuve absent" "skills absents (lu par un outil ne compte pas) : passe cassée"
expect_out "double passe cassée : skills préchargés grille reçu 2 fois" "skill reçu deux fois : passe cassée"
expect_out "sans-transcript passe cassée" "pas de transcript : passe cassée"
finish
