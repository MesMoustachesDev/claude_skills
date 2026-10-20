"""Extrait uniquement mes messages (pas ceux de Claude, pas les outils)
des sessions Claude Code récentes, pour repérer mes tics de langage.

Usage : python3 extract_my_messages.py [nb_sessions]
Sortie : messages_extraits.txt à côté de ce script.
"""
import glob
import json
import os
import sys

N_SESSIONS = int(sys.argv[1]) if len(sys.argv) > 1 else 40
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "messages_extraits.txt")

files = sorted(
    glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl")),
    key=os.path.getmtime,
    reverse=True,
)[:N_SESSIONS]

messages = []
for path in files:
    with open(path, errors="ignore") as f:
        for line in f:
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            if entry.get("type") != "user" or entry.get("isMeta"):
                continue
            content = entry.get("message", {}).get("content")
            if isinstance(content, list):
                content = " ".join(
                    part.get("text", "")
                    for part in content
                    if isinstance(part, dict) and part.get("type") == "text"
                )
            if not isinstance(content, str):
                continue
            content = content.strip()
            # Ignore les messages système, commandes et collages longs
            if not content or content.startswith("<") or len(content) > 600:
                continue
            messages.append(content)

messages = list(dict.fromkeys(messages))
with open(OUT, "w") as f:
    f.write("\n---\n".join(messages))
print(f"{len(messages)} messages extraits de {len(files)} sessions -> {OUT}")
