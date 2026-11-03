#!/usr/bin/env python3
"""Ce que Claude Code charge vraiment, demandé à la CLI sans appeler le modèle (1 s).

    scripts/claude_inventory.py                 agents et commandes du pipeline : chargés ? modèle valide ?
    scripts/claude_inventory.py --model sonnet  ce modèle existe-t-il pour ce compte ? (code 0 / 1)
    scripts/claude_inventory.py --json          la réponse brute d'initialize

`claude -p --input-format stream-json` répond à la requête de contrôle `initialize` avec les commandes
et skills chargés, les agents (et leur modèle), les modèles du compte. Hooks coupés (un SessionStart
croirait à une session), serveurs MCP non démarrés, aucun transcript (repris de vibe-manager, ADR 0037).
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

HOME = Path.home() / '.claude'


def initialize(cwd: str | None = None) -> dict:
    request = json.dumps({'type': 'control_request', 'request_id': 'inventory', 'request': {'subtype': 'initialize'}})
    run = subprocess.run(
        ['claude', '-p', '--input-format', 'stream-json', '--output-format', 'stream-json', '--verbose',
         '--no-session-persistence', '--settings', '{"disableAllHooks":true}', '--strict-mcp-config'],
        input=request + '\n', capture_output=True, text=True, timeout=60, cwd=cwd,
    )
    for line in run.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if message.get('type') == 'control_response':
            return message['response']['response']
    raise SystemExit(f'initialize sans réponse : {run.stderr.strip()[:300]}')


def model_names(answer: dict) -> set[str]:
    names = set()
    for m in answer.get('models', []):
        names.update(filter(None, [m.get('value'), m.get('resolvedModel')]))
    return names | {'inherit'}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--model', action='append', help='modèle à valider (alias ou id)')
    parser.add_argument('--json', action='store_true')
    parser.add_argument('--cwd', help='projet depuis lequel lire (commandes et agents du projet)')
    args = parser.parse_args()

    answer = initialize(args.cwd)
    if args.json:
        print(json.dumps(answer, ensure_ascii=False, indent=2))
        return 0
    models = model_names(answer)
    if args.model:
        unknown = [m for m in args.model if m not in models]
        for m in unknown:
            print(f'modèle inconnu pour ce compte : {m} (connus : {", ".join(sorted(models - {"inherit"}))})')
        return 1 if unknown else 0

    loaded_agents = {a['name']: a for a in answer.get('agents', [])}
    loaded_commands = {c['name'] for c in answer.get('commands', [])}
    problems = []
    rows = []
    for path in sorted((HOME / 'agents').glob('*.md')):
        agent = loaded_agents.get(path.stem)
        if not agent:
            problems.append(f'agent non chargé : {path.stem} ({path})')
            continue
        model = agent.get('model') or 'inherit'
        if model not in models:
            problems.append(f'agent {path.stem} : modèle {model} inconnu pour ce compte')
        rows.append(f'  {path.stem:36} {model}')
    for path in sorted((HOME / 'commands').glob('*.md')):
        if path.stem not in loaded_commands:
            problems.append(f'commande non chargée : /{path.stem}')
    for path in sorted((HOME / 'skills').glob('*/SKILL.md')):
        if path.parent.name not in loaded_commands:
            problems.append(f'skill non chargé : {path.parent.name}')

    account = answer.get('account') or {}
    print(f"Claude Code {answer.get('claude_code_version')} · {account.get('subscriptionType', '?')} · "
          f"{len(loaded_commands)} commandes et skills · {len(loaded_agents)} agents")
    print('Agents du pipeline et leur modèle :')
    print('\n'.join(rows))
    if problems:
        print('\nÀ regarder :')
        print('\n'.join(f'  - {p}' for p in problems))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
