#!/usr/bin/env python3
"""Rejoue de vraies étapes de features mergées, avec le vrai agent, ses hooks et son gate, sur un ou
plusieurs modèles, et juge chaque passe par ce qu'on sait déjà de la feature.

    pipeline/bench/replay/replay.py --stage green --model sonnet --model opus --runs 3
    pipeline/bench/replay/replay.py --feature report_port --stage red --model sonnet
    pipeline/bench/replay/replay.py --stage review --dry      # prépare, joue le juge sans agent

Une passe : worktree détaché du dépôt au commit où l'étape commençait (`cases.json`), avec
`.claude/features/<nom>/` tel qu'à la fin de la feature, moins ce que l'étape et les suivantes ont
produit, et `pipeline.json` remis à cette étape. Les règles du projet (`.claude/rules/`) sont celles
de develop aujourd'hui : on mesure le pipeline actuel. L'agent est lancé comme l'orchestrateur le
lance (prompt des steps de /feature, « Racine : <worktree> »), avec ses hooks : son gate de fin
tourne, ses tentatives se comptent dans pipeline.json.

Juges :
  red     gate red ; puis la vraie implémentation (le code non-test du commit `impl`) posée sous ses
          tests : le gate green doit passer (des tests qui refusent le code mergé sont faux) ;
          `--mutation` ajoute le score de mutation de ses tests sur ce code.
  green   gate green, tentatives, fichiers écrits.
  review  constats de la vraie revue (critical + suggestions) retrouvés, même fichier à ±8 lignes ;
          constats en plus comptés à part.

Rien n'est poussé ni commité : push, commit, reset, checkout et les CLI GitLab/GitHub sont refusés à
l'agent, et le worktree est supprimé après le juge (`--keep` le garde). Le transcript de chaque passe
est gardé (session nommée), son id dans les résultats. `total_cost_usd` est un équivalent API : sur
l'abonnement, c'est du quota consommé.
"""

import argparse
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
LOCAL = Path.home() / '.claude-local' / 'bench'
CASES = LOCAL / 'cases.json'
CLAUDE = HERE.parent.parent.parent
GAUNTLET = CLAUDE / 'scripts' / 'gauntlet.sh'
AGENT = {'red': 'feature-test-writer', 'green': 'feature-implementer', 'review': 'feature-reviewer'}
ORDER = ['cadrage', 'contracts_draft', 'dedup', 'spec_lint', 'spec_review', 'contracts', 'spec', 'red_data',
         'red_presentation', 'red', 'tests_review', 'green_data', 'green_presentation', 'green', 'clean',
         'dedup_clean', 'review', 'suggestions', 'harden', 'qa', 'polish', 'evidence']
# Ce que l'étape et les suivantes produisent : absent au départ de la passe.
PRODUCED = {
    'red': ['tests.md', 'tests_review.json', 'tests_review.md', 'history/tests_review_1.json'],
    'green': [],
    'review': ['review.json', 'review.md'],
}
LATER = ['review.json', 'review.md', 'evidence.md', 'mutants.md', 'qa.md', 'qa', 'report.html', '.gauntlet',
         'history/review_1.json', 'history/review_2.json']
TOOLS = ('Read Edit Write MultiEdit Glob Grep TodoWrite Bash(fvm:*) Bash(dart:*) Bash(flutter:*) Bash(rtk:*) '
         'Bash(git diff:*) Bash(git log:*) Bash(git show:*) Bash(git status:*) Bash(git merge-base:*) '
         'Bash(git rev-parse:*) Bash(git ls-files:*) Bash(git grep:*) Bash(ls:*) Bash(cat:*) Bash(head:*) '
         'Bash(tail:*) Bash(wc:*) Bash(grep:*) Bash(rg:*) Bash(find:*) Bash(jq:*) Bash(sed -n:*) Bash(sort:*) '
         f'Bash({GAUNTLET}:*) Bash(~/.claude/scripts/gauntlet.sh:*) Bash(~/.claude/scripts/pipeline.sh:*) '
         f'Bash(bash {GAUNTLET}:*)')
DENIED = ('Bash(git push:*) Bash(git commit:*) Bash(git reset:*) Bash(git checkout:*) Bash(git switch:*) '
          'Bash(git rebase:*) Bash(git merge:*) Bash(git worktree:*) Bash(rtk git push:*) Bash(rtk git commit:*) '
          'Bash(glab:*) Bash(gh:*) Bash(rtk glab:*) Bash(rtk gh:*)')


def sh(argv, cwd=None, timeout=3600, env=None):
    return subprocess.run(argv, cwd=cwd, capture_output=True, text=True, timeout=timeout, env=env)


def git(repo, *args):
    run = sh(['git', '-C', str(repo), *args])
    if run.returncode:
        raise RuntimeError(f"git {' '.join(args)} : {run.stderr.strip()[:300]}")
    return run.stdout


def branch_point(repo: Path, name: str, docs: str) -> str:
    """Le commit d'où la feature est partie : le parent de son plus ancien commit `(<nom>)`.

    La branche est mergée depuis : sa merge-base avec develop serait le commit lui-même, et le
    périmètre d'une feature en extend tomberait à zéro.
    """
    own = [l.split(' ', 1)[0] for l in git(repo, 'log', '--first-parent', '--format=%H %s', docs).splitlines()
           if f'({name})' in l]
    return git(repo, 'rev-parse', f'{own[-1]}^').strip()


def submodules(repo: Path, wt: Path, commit: str) -> bool:
    """Pose chaque submodule (dskit) dans la version que `commit` épingle, tirée du clone du checkout
    principal. Une copie du checkout principal donnerait la version d'aujourd'hui : le code d'il y a
    un mois ne compile plus contre elle. Vrai si un submodule a changé (pub get à refaire)."""
    if not (wt / '.gitmodules').exists():
        return False
    changed = False
    paths = sh(['git', '-C', str(wt), 'config', '--file', '.gitmodules', '--get-regexp', r'submodule\..*\.path']).stdout
    for sub in (l.split()[1] for l in paths.splitlines() if len(l.split()) > 1):
        pinned = git(wt, 'rev-parse', f'{commit}:{sub}').strip()
        dest = wt / sub
        stamp = dest / '.replay-pin'
        if stamp.exists() and stamp.read_text().strip() == pinned:
            continue
        shutil.rmtree(dest, ignore_errors=True)
        dest.mkdir(parents=True)
        archive = subprocess.run(['git', '-C', str(repo / sub), 'archive', pinned], capture_output=True)
        if archive.returncode:
            raise RuntimeError(f'{sub} @ {pinned[:8]} absent du clone principal : git -C {repo / sub} fetch')
        subprocess.run(['tar', '-x', '-C', str(dest)], input=archive.stdout, check=True)
        stamp.write_text(pinned + '\n')
        changed = True
    return changed


def pub_get(app: Path) -> None:
    got = sh(['fvm', 'flutter', 'pub', 'get'], cwd=app, timeout=900)
    if got.returncode or 'Failed to update packages' in got.stdout + got.stderr:
        raise RuntimeError(f'pub get : {(got.stdout + got.stderr).strip()[-300:]}')


def prepare(repo: Path, name: str, case: dict, stage: str) -> Path:
    step = case[stage]
    wt = Path(tempfile.mkdtemp(prefix=f'replay-{name[:20]}-{stage}-'))
    wt.rmdir()
    git(repo, 'worktree', 'add', '--detach', str(wt), step['start'])
    # Les fichiers de la feature à la fin, puis les règles actuelles du projet.
    feat = f'.claude/features/{name}'
    for path, ref in ((feat, case['docs']), ('.claude/rules', 'develop')):
        archive = subprocess.run(['git', '-C', str(repo), 'archive', ref, path], capture_output=True, check=True)
        subprocess.run(['tar', '-x', '-C', str(wt)], input=archive.stdout, check=True)
    fdir = wt / feat
    for rel in PRODUCED[stage] + LATER:
        target = fdir / rel
        if target.is_dir():
            shutil.rmtree(target)
        elif target.exists():
            target.unlink()
    pipe = json.loads((fdir / 'pipeline.json').read_text())
    at = ORDER.index(stage)
    for key in list(pipe.get('stages', {})):
        if key in ORDER and ORDER.index(key) >= at or key not in ORDER:
            pipe['stages'][key] = 'PENDING'
    for key in list(pipe.get('attempts', {})):
        if key in ORDER and ORDER.index(key) >= at:
            pipe['attempts'][key] = 0
    if stage in ('red', 'green'):
        for key in ('red_data', 'red_presentation', 'green_data', 'green_presentation'):
            pipe.get('stages', {}).pop(key, None)
    if stage == 'red':
        pipe.pop('tests_freeze_sha', None)
    else:
        pipe['tests_freeze_sha'] = git(repo, 'rev-parse', step['frozen']).strip()
    pipe['base'] = branch_point(repo, name, case['docs'])
    for key in ('suggestions', 'debt', 'loops', 'harden_todo', 'hardening', 'refreezes', 'suspect_tests'):
        pipe.pop(key, None)
    (fdir / 'pipeline.json').write_text(json.dumps(pipe, ensure_ascii=False, indent=2) + '\n')
    (wt / '.claude' / 'features' / '.current').write_text(name + '\n')
    submodules(repo, wt, 'HEAD')
    # Worktree neuf : pas de .dart_tool. Le projet est un workspace pub, un seul pub get à sa racine.
    app = wt / case.get('app_dir', 'flutter_app')
    pub_get(app)
    if stage == 'review':
        sh(['bash', str(GAUNTLET), 'maintain', name], cwd=wt)
    return wt


def prompt(wt: Path, name: str, case: dict, stage: str) -> str:
    feat = f'.claude/features/{name}'
    pkg = case['package']
    head = f'Racine : {wt}\nFeature : {name}. Package : {pkg}. Spec : {feat}/spec.md.\n'
    if stage == 'red':
        return head + (
            f'Tu es Théo complet (les deux couches, pas de moitié en parallèle). Lis aussi {feat}/cadrage.md et '
            f'{feat}/archi.json : chaque séquence C<n> est un scénario d\'acceptation, relié à son titre de §4 par '
            "archi.json → sequences ; chaque action, réponse du use case mocké et résultat visible qu'elle montre "
            'doit avoir son step. Règles de test : ~/.claude/commands/create_test.md. Écris toute la suite, puis '
            'rends la main quand le gate red est vert.')
    if stage == 'green':
        screen = ' Règles d\'écran : .claude/rules/create_screen_rules.md si la feature a une page.'
        return head + (
            f'Tu es Ivan complet (les deux couches). Tests gelés : {feat}/tests.md.{screen} '
            'Implémente les stubs jusqu\'au vert du gate green, sans toucher aux tests.')
    frozen = case['review']['frozen']
    return head + (
        f'Deux bases : la merge-base avec develop (le périmètre de la feature) et tests_freeze_sha {frozen} (ce '
        f'qu\'Ivan et Nina ont écrit depuis le gel). Lis {feat}/tests.md, {feat}/.gauntlet/last_maintain.log, '
        f'{feat}/dedup.md s\'il existe, .claude/rules/pr_rules.md s\'il existe, .claude/rules/create_feature_rules.md, '
        '.claude/rules/create_screen_rules.md s\'il existe, ~/.claude/commands/reviewPR.md, les contrats de '
        f'Thibault (pipeline.json → contracts, la référence) et {feat}/archi.json. Écris {feat}/review.json, '
        'visite guidée comprise.')


def gate(wt: Path, name: str, profile: str) -> tuple[bool, str]:
    run = sh(['bash', str(GAUNTLET), profile, name], cwd=wt, timeout=5400)
    lines = [l for l in (run.stdout + run.stderr).splitlines() if l.strip()]
    return run.returncode == 0, (lines[-1] if lines else '')[:160]


def findings(path: Path) -> list[dict]:
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return []
    return [f for key in ('critical', 'suggestions') for f in data.get(key) or [] if isinstance(f, dict)]


def matches(a: dict, b: dict) -> bool:
    same_file = Path(str(a.get('file', ''))).name == Path(str(b.get('file', ''))).name != ''
    try:
        close = abs(int(a.get('line') or -999) - int(b.get('line') or 999)) <= 8
    except (TypeError, ValueError):
        close = False
    return same_file and close


def judge(repo: Path, wt: Path, name: str, case: dict, stage: str, mutation: bool) -> dict:
    fdir = wt / '.claude' / 'features' / name
    pipe = json.loads((fdir / 'pipeline.json').read_text())
    tries = (pipe.get('attempts') or {}).get(stage, 0)
    written = [l for l in git(wt, 'status', '--porcelain').splitlines() if '.claude/' not in l]
    out = {'attempts': tries, 'files_written': len(written)}
    if stage == 'green':
        ok, detail = gate(wt, name, 'green')
        return {**out, 'ok': ok, 'detail': f'green {"vert" if ok else "rouge"} · {detail}'}
    if stage == 'red':
        red_ok, red_detail = gate(wt, name, 'red')
        start, impl = case['red']['start'], case['red']['impl']
        code = [p for p in git(repo, 'diff', '--name-only', '--diff-filter=AMR', start, impl).splitlines()
                if '/test/' not in p and not p.startswith('.claude/') and not p.endswith('_test.dart')]
        if code:
            git(wt, 'checkout', impl, '--', *code)
        if submodules(repo, wt, impl):
            pub_get(wt / case.get('app_dir', 'flutter_app'))
        # Le check `test` seul : le code mergé ne passe pas toujours le formateur d'aujourd'hui.
        green_ok, green_detail = gate(wt, name, 'test')
        detail = f'red {"vert" if red_ok else "rouge"} · suite sur le code mergé : {"verte" if green_ok else "rouge"}'
        score = None
        if mutation and green_ok:
            # Le score est sur la ligne « mutants : …, score : N % », pas sur la dernière.
            run = sh(['bash', str(GAUNTLET), 'mutation', name], cwd=wt, timeout=5400)
            found = re.search(r'score : (\d+)%', run.stdout + run.stderr)
            score = float(found.group(1)) if found else None
            trivial = re.search(r'aucune mutation possible|aucune ligne à muter|aucun fichier à muter', run.stdout)
            detail += ' · mutation ' + (f'{score:.0f} %' if score is not None else 'sans mutant' if trivial else '—')
        return {**out, 'ok': red_ok and green_ok, 'detail': detail if green_ok else f'{detail} ({green_detail})',
                'mutation': score}
    truth_path = Path(tempfile.mktemp(suffix='.json'))
    truth_path.write_text(git(repo, 'show', f"{case['docs']}:.claude/features/{name}/{case['review']['truth']}"))
    truth = findings(truth_path)
    truth_path.unlink()
    got = findings(fdir / 'review.json')
    found = [t for t in truth if any(matches(t, g) for g in got)]
    extra = [g for g in got if not any(matches(g, t) for t in truth)]
    ok = bool(got) and len(found) == len(truth)
    return {**out, 'ok': ok, 'detail': f'vraie revue retrouvée : {len(found)}/{len(truth)} · constats en plus : {len(extra)}',
            'recall': round(len(found) / len(truth), 2) if truth else None, 'extra': len(extra),
            'missed': [f"{Path(str(t.get('file'))).name}:{t.get('line')} {str(t.get('summary', ''))[:80]}"
                       for t in truth if t not in found]}


def play(repo, name, case, stage, model, mutation, keep, dry) -> dict:
    wt = prepare(repo, name, case, stage)
    session = str(uuid.uuid4())
    started = time.time()
    result = {}
    try:
        if not dry:
            argv = ['claude', '-p', prompt(wt, name, case, stage), '--agent', AGENT[stage], '--model', model,
                    '--output-format', 'json',
                    # acceptEdits tient tout `.claude/` pour sensible et refuse review.json : ni règle
                    # Write(...) ni hook allow n'y font rien. Accordé par Thibault pour le banc seul
                    # (2026-11-04) : worktree jetable, DENIED et les hooks de l'agent tiennent toujours.
                    '--permission-mode', 'bypassPermissions',
                    '--allowedTools', TOOLS, '--disallowedTools', DENIED,
                    '--strict-mcp-config', '--session-id', session]
            try:
                run = sh(argv, cwd=wt, timeout=7200)
                lines = run.stdout.strip().splitlines()
                result = json.loads(lines[-1]) if lines else {}
            except (subprocess.TimeoutExpired, json.JSONDecodeError):
                result = {}
        verdict = judge(repo, wt, name, case, stage, mutation)
    finally:
        if not keep:
            sh(['git', '-C', str(repo), 'worktree', 'remove', '--force', str(wt)])
    usage = result.get('usage') or {}
    models = sorted((result.get('modelUsage') or {}).keys())
    return {
        'feature': name, 'stage': stage, 'agent': AGENT[stage], 'model': model, 'models_used': models,
        **verdict,
        'turns': result.get('num_turns'), 'wall_s': round(time.time() - started),
        'output_tokens': usage.get('output_tokens') or 0,
        'cost_usd': result.get('total_cost_usd'), 'session': '' if dry else session,
        'agent_error': not dry and (not result or bool(result.get('is_error'))),
        'worktree': str(wt) if keep else '',
        'answer': (result.get('result') or '')[-500:],
    }


def table(rows: list[dict]) -> str:
    head = ('| Feature | Étape | Modèle | Réussi | Juge | Tentatives | Fichiers | Tours | Durée | Équivalent API |\n'
            '|---|---|---|---|---|---|---|---|---|---|\n')
    return head + ''.join(
        f"| {r['feature']} | {r['stage']} | {r['model']} | {'oui' if r['ok'] else 'non'} | {r['detail']} "
        f"| {r.get('attempts', '—')} | {r.get('files_written', '—')} | {r.get('turns') or '—'} | {round(r['wall_s'] / 60)} min "
        f"| {'—' if r.get('cost_usd') is None else f'{r['cost_usd']:.2f} $'} |\n" for r in rows)


def hollow(row: dict) -> bool:
    """Une passe qui n'a rien produit : le banc est cassé, pas l'agent (campagne du 2026-11-03,
    10 h de passes sans review.json ni test compilable)."""
    if row['detail'].startswith('passe cassée') or row.get('agent_error'):
        return True
    if row['stage'] == 'review':
        return row.get('recall') == 0 and row.get('extra') == 0
    if ' · mutation —' in row['detail']:  # suite verte mais score introuvable : juge à revoir
        return True
    return row.get('files_written') == 0


def summary(rows: list[dict]) -> str:
    groups: dict[tuple, list] = {}
    for r in rows:
        groups.setdefault((r['stage'], r['model']), []).append(r)
    lines = ['| Étape | Modèle | Réussites | Rappel moyen (review) | Mutation moyenne (red) | Équivalent API moyen |',
             '|---|---|---|---|---|---|']
    for (stage, model), rs in sorted(groups.items()):
        ok = sum(r['ok'] for r in rs)
        recall = [r['recall'] for r in rs if r.get('recall') is not None]
        mut = [r['mutation'] for r in rs if r.get('mutation') is not None]
        cost = [r['cost_usd'] for r in rs if r.get('cost_usd') is not None]
        avg = lambda xs, f: f(sum(xs) / len(xs)) if xs else '—'
        lines.append(f"| {stage} | {model} | {ok}/{len(rs)} | {avg(recall, lambda x: f'{x:.0%}')} "
                     f"| {avg(mut, lambda x: f'{x:.0f} %')} | {avg(cost, lambda x: f'{x:.2f} $')} |")
    return '\n'.join(lines) + '\n'


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--feature', action='append', help='feature de cases.json (défaut : toutes)')
    parser.add_argument('--stage', action='append', choices=list(AGENT), help='étape (défaut : toutes)')
    parser.add_argument('--model', action='append', help='modèle, répétable (défaut : sonnet)')
    parser.add_argument('--runs', type=int, default=1, help='passes par feature, étape et modèle')
    parser.add_argument('--mutation', action='store_true', help='red : score de mutation (long)')
    parser.add_argument('--keep', action='store_true', help='garde les worktrees')
    parser.add_argument('--dry', action='store_true', help='prépare et juge sans agent')
    parser.add_argument('--label', default='')
    args = parser.parse_args()

    # Les cas nomment un projet client : hors du repo, dans ~/.claude-local/bench/cases.json.
    cases = json.loads(CASES.read_text())
    repo = Path(os.path.expanduser(cases['repo']))
    models = args.model or ['sonnet']
    if not args.dry:
        check = sh([sys.executable, str(CLAUDE / 'scripts' / 'claude_inventory.py'), *sum((['--model', m] for m in models), [])])
        if check.returncode:
            print(check.stdout.strip())
            return 2
    out = LOCAL / 'results' / f"replay-{datetime.datetime.now():%Y-%m-%d_%H%M}{'-' + args.label if args.label else ''}"
    out.parent.mkdir(parents=True, exist_ok=True)
    rows = []
    for name in args.feature or list(cases['features']):
        for stage in args.stage or list(AGENT):
            for model in (['—'] if args.dry else models):
                for n in range(args.runs):
                    print(f'{name} · {stage} · {model} · passe {n + 1}/{args.runs} …', flush=True)
                    try:
                        row = play(repo, name, cases['features'][name], stage, model, args.mutation, args.keep, args.dry)
                    except Exception as e:  # une passe cassée n'arrête pas la campagne
                        row = {'feature': name, 'stage': stage, 'model': model, 'ok': False,
                               'detail': f'passe cassée : {e}'[:200], 'wall_s': 0}
                    print(f"  {'✓' if row['ok'] else '✗'} {row['detail']}", flush=True)
                    rows.append(row)
                    # Écrit au fil de l'eau : une campagne de plusieurs heures interrompue garde ses passes.
                    out.with_suffix('.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n')
                    out.with_suffix('.md').write_text(summary(rows) + '\n' + table(rows))
                    if not args.dry and len(rows) >= 2 and all(hollow(r) for r in rows[-2:]):
                        print('\nDeux passes de suite sans rien produire : campagne arrêtée, le banc est à revoir.')
                        return 3
    print(f'\n{summary(rows)}\n{table(rows)}\n→ {out}.md')
    return 0


if __name__ == '__main__':
    sys.exit(main())
