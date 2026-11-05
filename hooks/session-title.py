#!/usr/bin/env python3
"""UserPromptSubmit — nomme la conversation d'après la commande du pipeline qui la lance.

    /feature error_redirect Redirection après une erreur d'upload
      → « Feature · error_redirect — Redirection après une erreur d'upload »
    /fix heic_plan_rotation          → « Fix · heic_plan_rotation »
    /reviewPR 93                     → « Revue MR · !93 »
    /fix_mr_comments                 → « Commentaires MR · <branche courante> »

Le titre ne se pose qu'une fois par conversation et par cible : le watchdog renvoie
`/feature <nom> watchdog` toutes les quelques minutes, et une reprise sans description ne doit pas
effacer celle du premier lancement. `help`, `list`, `init` ne nomment rien.
Sortie : rien, ou {"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "sessionTitle": …}}.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

STATE = Path.home() / '.claude' / 'state' / 'session-titles'
SUBCOMMANDS = {'status', 'cockpit', 'watchdog', 'accept'}
OPTIONS_WITH_VALUE = {'--in', '--parent'}


def short(text: str, limit: int = 60) -> str:
    text = ' '.join(text.split())
    return text if len(text) <= limit else text[:limit - 1].rstrip() + '…'


def mr(target: str) -> str:
    m = re.search(r'(?:merge_requests/|!|#)?(\d+)\s*$', target)
    return f'!{m.group(1)}' if m else short(target, 40)


def branch(cwd: str) -> str:
    run = subprocess.run(['git', '-C', cwd, 'branch', '--show-current'], capture_output=True, text=True)
    return run.stdout.strip() or Path(cwd).name


def title(prompt: str, cwd: str) -> tuple[str, str] | None:
    """(cible, titre), ou None si le prompt n'est pas une commande à nommer."""
    m = re.match(r'^\s*/(feature|fix|reviewPR|fix_mr_comments)(?:\s+(.*))?$', prompt, re.S)
    if not m:
        return None
    command, rest = m.group(1), (m.group(2) or '').strip()
    args = rest.split()
    if command in ('feature', 'fix'):
        if not args or not re.fullmatch(r'[a-z0-9][a-z0-9_]*', args[0]) or args[0] in ('help', 'list', 'init'):
            return None
        # La description est le texte tel qu'écrit (apostrophes comprises), après le nom et les options.
        tokens = list(re.finditer(r'\S+', rest))[1:]
        desc, k = '', 0
        while k < len(tokens):
            a = tokens[k].group()
            if a in OPTIONS_WITH_VALUE:
                k += 2
                continue
            if a not in SUBCOMMANDS:
                desc = rest[tokens[k].start():].strip().strip('"\'«» ')
            break
        head = f"{'Feature' if command == 'feature' else 'Fix'} · {args[0]}"
        return f'{command}:{args[0]}', head + (f' — {short(desc)}' if desc else '')
    if command == 'reviewPR':
        if not args:
            return None
        return f'reviewPR:{args[0]}', f'Revue MR · {mr(args[0])}'
    target = mr(args[0]) if args else branch(cwd)
    return f'fix_mr_comments:{target}', f'Commentaires MR · {target}'


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0
    found = title(str(event.get('prompt') or ''), str(event.get('cwd') or '.'))
    session = re.sub(r'[^A-Za-z0-9_-]', '', str(event.get('session_id') or ''))
    if not found or not session:
        return 0
    target, new = found
    marker = STATE / session
    if marker.exists() and marker.read_text().strip() == target:
        return 0
    STATE.mkdir(parents=True, exist_ok=True)
    marker.write_text(target + '\n')
    print(json.dumps({'hookSpecificOutput': {'hookEventName': 'UserPromptSubmit', 'sessionTitle': new}},
                     ensure_ascii=False))
    return 0


if __name__ == '__main__':
    sys.exit(main())
