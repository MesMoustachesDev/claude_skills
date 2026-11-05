#!/usr/bin/env python3
"""Ajoute une règle à un fichier de ~/.claude et la commite aussitôt.

    rule_add.py <fichier> "<ligne>" [--after "<ligne existante>"]

<fichier> : chemin sous ~/.claude (create_test.md, answers.md, un template, review_grid.md…).
La ligne s'insère après la première ligne qui contient le texte de --after (la fin de la section visée,
en pratique sa dernière puce), sinon à la fin du fichier. Puis `git commit` de ce seul fichier, dans
~/.claude. Refuse un fichier qui a déjà des changements non commités : ils sont à quelqu'un d'autre.

C'est le seul chemin d'une règle de learn (9b) ou d'une réponse de Thibault vers ~/.claude : le hook
claude-home-guard.sh refuse les écritures directes dans le checkout principal.
"""

import argparse
import subprocess
import sys
from pathlib import Path

HOME = Path.home() / '.claude'


def git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(['git', '-C', str(HOME), *args], capture_output=True, text=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('file')
    parser.add_argument('line')
    parser.add_argument('--after', default='')
    args = parser.parse_args()

    path = Path(args.file.replace('~', str(Path.home()), 1)).resolve()
    try:
        rel = path.relative_to(HOME.resolve())
    except ValueError:
        print(f'refusé : {path} n\'est pas sous ~/.claude')
        return 2
    if not path.is_file():
        print(f'refusé : {rel} n\'existe pas')
        return 2
    if git('status', '--porcelain', '--', str(rel)).stdout.strip():
        print(f'refusé : {rel} a déjà des changements non commités (git -C ~/.claude diff -- {rel})')
        return 2
    line = args.line.rstrip('\n')
    lines = path.read_text().splitlines(keepends=True)
    if any(l.rstrip('\n') == line for l in lines):
        print(f'déjà là : {rel}')
        return 0
    at = next((i + 1 for i, l in enumerate(lines) if args.after and args.after in l), len(lines))
    if at == len(lines) and lines and not lines[-1].endswith('\n'):
        lines[-1] += '\n'
    lines.insert(at, line + '\n')
    path.write_text(''.join(lines))
    summary = line.lstrip('-*0123456789. ').replace('**', '')[:60]
    commit = git('commit', '-q', '-m', f'rules({rel.stem}): {summary}', '--', str(rel))
    if commit.returncode:
        print(f'écrit mais pas commité : {commit.stderr.strip()}')
        return 1
    print(f'{rel} : règle ajoutée ligne {at + 1}, commit {git("rev-parse", "--short", "HEAD").stdout.strip()}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
