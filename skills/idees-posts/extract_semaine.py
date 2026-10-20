"""Extrait mes messages des sessions Claude Code des N derniers jours,
groupés par projet, pour y chercher des idées de posts LinkedIn.

Usage : python3 extract_semaine.py [nb_jours]   (7 par défaut)
Sortie : semaine.txt à côté de ce script. À supprimer après usage
(il peut contenir des noms de clients, des emails, des ids).
"""
import glob
import json
import os
import sys
import time
from datetime import datetime, timezone

DAYS = int(sys.argv[1]) if len(sys.argv) > 1 else 7
SINCE = time.time() - DAYS * 86400
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "semaine.txt")
HOME_PREFIX = os.path.expanduser("~").replace("/", "-")


def project_name(path):
    """-Users-moi-work-cookbooker -> cookbooker"""
    folder = os.path.basename(os.path.dirname(path))
    name = folder.replace(HOME_PREFIX, "").strip("-")
    if "scratch-workspaces" in name:
        return "sans dossier"
    return name.split("-claude-worktrees-")[0].removeprefix("work-") or "home"


def message_time(entry):
    ts = entry.get("timestamp")
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


files = [
    f
    for f in glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl"))
    if os.path.getmtime(f) >= SINCE
]

by_project = {}
for path in sorted(files, key=os.path.getmtime):
    project = project_name(path)
    with open(path, errors="ignore") as f:
        for line in f:
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            if entry.get("type") != "user" or entry.get("isMeta"):
                continue
            ts = message_time(entry)
            if ts is not None and ts < SINCE:
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
            # Ignore les messages système, commandes, interruptions et gros collages
            if (
                not content
                or content.startswith("<")
                or content.startswith("[Request interrupted")
                or len(content) > 1500
            ):
                continue
            day = datetime.fromtimestamp(ts or os.path.getmtime(path)).strftime("%a %d/%m")
            by_project.setdefault(project, []).append(f"[{day}] {content}")

total = 0
with open(OUT, "w") as out:
    for project, messages in by_project.items():
        messages = list(dict.fromkeys(messages))
        total += len(messages)
        out.write(f"\n===== {project} ({len(messages)} messages) =====\n")
        out.write("\n---\n".join(messages))
        out.write("\n")

print(f"{total} messages, {len(by_project)} projets, {DAYS} derniers jours -> {OUT}")
