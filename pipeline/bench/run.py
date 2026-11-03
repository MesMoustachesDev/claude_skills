#!/usr/bin/env python3
"""Le banc de tâches des agents du pipeline : chaque tâche de `tasks/`, jouée par son agent sur un
ou plusieurs modèles, jugée par son `verify.sh`.

    pipeline/bench/run.py --model sonnet --model opus
    pipeline/bench/run.py --task green_cart --model sonnet --label essai
    pipeline/bench/run.py --dry          # prépare et juge sans agent : le stub doit échouer

Une tâche est un dossier : `repo/` (copié dans un dossier jetable), `setup.sh` (y prépare le dépôt
et le commite), `prompt.md` (donné à l'agent), `verify.sh` (juge, code 0 = réussi, dernière ligne =
le détail), `task.json` (`agent`, `timeout_s`, `what`). `setup.sh` et `verify.sh` reçoivent le
dossier de la tâche dans `TASK_DIR`, pour ce que l'agent ne doit pas voir (`hidden/`, `change/`).

L'agent joue avec son prompt (`agents/<nom>.md`) mais sans ses hooks : la garde des écritures et le
gate supposent un vrai projet du pipeline. Le banc mesure le prompt et le modèle, pas l'outillage.

Noté par run : réussite, détail du juge, tours, durée, tokens, et `total_cost_usd` de `claude -p` :
l'équivalent au tarif de l'API, pas une facture (sur l'abonnement, c'est du quota consommé).
`--budget-usd` plafonne un run sur ce même équivalent. Écrit dans
`results/<date>-<label>.json` et un tableau Markdown à côté. Ça coûte : jamais en CI.
"""

import argparse
import datetime
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

BENCH = Path(__file__).resolve().parent
AGENTS = BENCH.parent.parent / 'agents'
TOOLS = 'Read Edit Write Glob Grep Bash(dart:*) Bash(git diff:*) Bash(git log:*) Bash(git show:*) Bash(git status:*) Bash(ls:*) Bash(cat:*)'


def prepare(task: Path) -> Path:
    work = Path(tempfile.mkdtemp(prefix=f'bench-{task.name}-'))
    shutil.copytree(task / 'repo', work, dirs_exist_ok=True)
    env = {**os.environ, 'TASK_DIR': str(task)}
    subprocess.run(['bash', str(task / 'setup.sh')], cwd=work, env=env, check=True, capture_output=True)
    return work


def judge(task: Path, work: Path) -> tuple[bool, str]:
    env = {**os.environ, 'TASK_DIR': str(task)}
    run = subprocess.run(['bash', str(task / 'verify.sh')], cwd=work, env=env, capture_output=True, text=True, timeout=600)
    lines = (run.stdout + run.stderr).strip().splitlines()
    return run.returncode == 0, lines[-1] if lines else ''


def bench_agent(name: str) -> dict:
    """La définition `--agents` d'un agent du pipeline : son prompt, sans hooks ni modèle imposé."""
    text = (AGENTS / f'{name}.md').read_text()
    _, front, body = text.split('---', 2)
    description = next((l.split(':', 1)[1].strip() for l in front.splitlines() if l.startswith('description:')), name)
    return {f'bench-{name}': {'description': description, 'prompt': body.strip()}}


def play(task: Path, meta: dict, model: str, agent: str, budget: float, keep: bool) -> dict:
    work = prepare(task)
    started = time.time()
    # Nommée avant d'exister : avec --keep, le transcript ~/.claude/projects/*/<id>.jsonl est celui du run.
    session = str(uuid.uuid4())
    argv = [
        'claude', '-p', (task / 'prompt.md').read_text(),
        '--agents', json.dumps(bench_agent(agent)), '--agent', f'bench-{agent}', '--model', model,
        '--output-format', 'json',
        '--permission-mode', 'acceptEdits', '--allowedTools', TOOLS,
        '--max-budget-usd', str(budget),
        '--strict-mcp-config',
        # Les hooks de l'utilisateur (rtk réécrit cat/ls, refusés ensuite) faussent la mesure.
        '--settings', '{"disableAllHooks":true}',
        *(['--session-id', session] if keep else ['--no-session-persistence']),
    ]
    try:
        run = subprocess.run(argv, cwd=work, capture_output=True, text=True, timeout=meta.get('timeout_s', 900))
        out = run.stdout
    except subprocess.TimeoutExpired as e:
        out = e.stdout.decode() if isinstance(e.stdout, bytes) else (e.stdout or '')
    wall = round(time.time() - started)
    try:
        result = json.loads(out.strip().splitlines()[-1]) if out.strip() else {}
    except json.JSONDecodeError:
        result = {}
    ok, detail = judge(task, work)
    usage = result.get('usage') or {}
    shutil.rmtree(work, ignore_errors=True)
    return {
        'task': task.name,
        'agent': agent,
        'model': model,
        'ok': ok,
        'detail': detail,
        'turns': result.get('num_turns'),
        'wall_s': wall,
        'input_tokens': (usage.get('input_tokens') or 0) + (usage.get('cache_read_input_tokens') or 0) + (usage.get('cache_creation_input_tokens') or 0),
        'output_tokens': usage.get('output_tokens') or 0,
        'cost_usd': result.get('total_cost_usd'),
        'agent_error': result.get('is_error', not result),
        'denials': len(result.get('permission_denials') or []),
        'answer': (result.get('result') or '')[-600:],
        'session': session if keep else '',
    }


def table(rows: list[dict]) -> str:
    head = '| Tâche | Agent | Modèle | Réussi | Juge | Tours | Durée | Tokens in / out | Équivalent API |\n|---|---|---|---|---|---|---|---|---|\n'
    body = ''.join(
        f"| {r['task']} | {r['agent']} | {r['model']} | {'oui' if r['ok'] else 'non'} | {r['detail']} | {r.get('turns') or '—'} "
        f"| {r.get('wall_s', 0)} s | {r.get('input_tokens', 0):,} / {r.get('output_tokens', 0):,} "
        f"| {'—' if r.get('cost_usd') is None else f'{r['cost_usd']:.2f} $'} |\n"
        for r in rows
    )
    return head + body


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--task', action='append', help='tâche (défaut : toutes)')
    parser.add_argument('--model', action='append', help='modèle, répétable (défaut : sonnet)')
    parser.add_argument('--agent', help="remplace l'agent de task.json")
    parser.add_argument('--label', default='', help='suffixe du fichier de résultats')
    parser.add_argument('--budget-usd', type=float, default=3.0, help='plafond par run')
    parser.add_argument('--dry', action='store_true', help='prépare et juge, sans agent')
    parser.add_argument('--keep', action='store_true', help='garde le transcript de chaque run (session nommée)')
    args = parser.parse_args()

    models = args.model or ['sonnet']
    # Tout ce qui peut refuser refuse avant le premier run : un modèle inconnu ne coûte rien.
    if not args.dry and subprocess.run([sys.executable, str(BENCH.parent.parent / 'scripts' / 'claude_inventory.py'), *sum((['--model', m] for m in models), [])]).returncode:
        return 2
    names = args.task or sorted(p.name for p in (BENCH / 'tasks').iterdir() if (p / 'task.json').exists())
    rows = []
    for name in names:
        task = BENCH / 'tasks' / name
        meta = json.loads((task / 'task.json').read_text())
        if args.dry:
            work = prepare(task)
            ok, detail = judge(task, work)
            shutil.rmtree(work, ignore_errors=True)
            print(f'{name} : stub {"réussi (le juge ne juge rien)" if ok else "échoue, bien"} · {detail}')
            continue
        for model in models:
            print(f'{name} · {model} …', flush=True)
            row = play(task, meta, model, args.agent or meta['agent'], args.budget_usd, args.keep)
            print(f"  {'✓' if row['ok'] else '✗'} {row['detail']} · {row['wall_s']} s · {row['cost_usd']} $", flush=True)
            rows.append(row)
    if not rows:
        return 0
    stamp = datetime.datetime.now().strftime('%Y-%m-%d_%H%M')
    out = BENCH / 'results' / f"{stamp}{'-' + args.label if args.label else ''}"
    out.parent.mkdir(exist_ok=True)
    out.with_suffix('.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n')
    out.with_suffix('.md').write_text(table(rows))
    print(f'\n{table(rows)}\n→ {out}.md')
    return 0 if all(r['ok'] for r in rows) else 1


if __name__ == '__main__':
    sys.exit(main())
