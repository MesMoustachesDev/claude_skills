#!/usr/bin/env python3
"""SubagentStart — met la doctrine de l'agent dans son contexte, au lieu de lui demander de la lire.

Les transcripts montraient des « lis X » sautés : `create_test.md` jamais relu par Théo en relance,
les règles d'écran lues 1 fois sur 5, `answers.md` 1 fois sur 9 chez Romain. Ce hook lit les fichiers
que `doctrine.json` associe au type d'agent et les rend en `additionalContext` : l'agent les a sous
les yeux dès son premier tour, quoi qu'en dise son prompt de lancement.

Entrée : agent_type, cwd. Sortie : rien (agent hors liste), ou
{"hookSpecificOutput": {"hookEventName": "SubagentStart", "additionalContext": …}}.
"""

import json
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
CONFIG = Path(__file__).with_name('doctrine.json')
TEMPLATES = HOME / '.claude/commands/templates/flutter'


def repo_root(cwd: str) -> Path | None:
    run = subprocess.run(['git', '-C', cwd, 'rev-parse', '--show-toplevel'], capture_output=True, text=True)
    return Path(run.stdout.strip()) if run.returncode == 0 else None


def resolve(ref: str, root: Path | None) -> tuple[Path, str] | None:
    """(fichier, d'où il vient), ou None s'il n'existe nulle part."""
    if ref.startswith('rules:'):
        name = ref[len('rules:'):]
        if root:
            for found in [root / '.claude/rules' / name, *sorted(root.glob(f'*/.claude/rules/{name}'))]:
                if found.is_file():
                    return found, 'règle du projet'
        template = TEMPLATES / name
        return (template, "template : le projet n'a pas le sien") if template.is_file() else None
    path = Path(ref.replace('~', str(HOME), 1))
    return (path, 'doctrine du pipeline') if path.is_file() else None


def main() -> int:
    try:
        event = json.load(sys.stdin)
        refs = json.loads(CONFIG.read_text())['agents'].get(str(event.get('agent_type') or ''), [])
    except (json.JSONDecodeError, OSError, KeyError):
        return 0
    if not refs:
        return 0
    root = repo_root(str(event.get('cwd') or '.'))
    parts, missing = [], []
    for ref in refs:
        found = resolve(ref, root)
        if not found:
            missing.append(ref)
            continue
        path, origin = found
        shown = str(path).replace(str(HOME), '~', 1)
        parts.append(f'<doctrine fichier="{shown}" origine="{origin}">\n{path.read_text().strip()}\n</doctrine>')
    if not parts:
        return 0
    head = ('Ces fichiers sont déjà dans ton contexte, en entier : ce sont les règles de ton étape. '
            'Applique-les ; ne les relis pas, et ne les cherche pas ailleurs. Là où ton prompt de lancement '
            'te demande de « lire » l\'un d\'eux, c\'est fait.')
    if missing:
        head += f" Introuvables, donc absents : {', '.join(missing)}."
    out = {'hookSpecificOutput': {'hookEventName': 'SubagentStart', 'additionalContext': head + '\n\n' + '\n\n'.join(parts)}}
    print(json.dumps(out, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    sys.exit(main())
