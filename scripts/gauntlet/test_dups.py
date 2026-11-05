#!/usr/bin/env python3
"""Les noms de test qui reviennent dans plusieurs fichiers d'un package.

    test_dups.py <racine du projet> <package> [<package>…]

Lit `<package>/test/**/*_test.dart` de chaque package (celui de la feature et ceux où elle a écrit des
tests), relève le nom de chaque `test(`, `testWidgets(`, `blocTest<…>(` (le nom peut
être sur la ligne suivante), et écrit, pour chaque nom présent dans au moins deux fichiers, une ligne par
occurrence : `<package>/test/<fichier>:<ligne>: <nom>`. Le même nom dans deux fichiers, c'est en général le même
comportement prouvé à deux étages (principe 18 de create_test.md). Une ligne qui porte
`// doublon voulu : <raison>` est ignorée.
"""

import re
import sys
from collections import defaultdict
from pathlib import Path

CALL = re.compile(r"\b(?:testWidgets|blocTest(?:<[^>(]*>)?|test)\(\s*$|\b(?:testWidgets|blocTest(?:<[^>(]*>)?|test)\(\s*(['\"]{1,3})(.+?)\1")
NAME = re.compile(r"^\s*(['\"]{1,3})(.+?)\1")


def names(path: Path):
    lines = path.read_text(errors='replace').splitlines()
    for i, line in enumerate(lines):
        m = CALL.search(line)
        if not m:
            continue
        at, name = i, m.group(2)
        if name is None and i + 1 < len(lines):
            n = NAME.match(lines[i + 1])
            at, name = i + 1, n.group(2) if n else None
        if name and 'doublon voulu' not in line and 'doublon voulu' not in lines[at]:
            yield at + 1, re.sub(r'\s+', ' ', name.strip().lower())


def main() -> int:
    root = Path(sys.argv[1])
    seen = defaultdict(list)
    for pkg in sys.argv[2:]:
        for path in sorted((root / pkg / 'test').rglob('*_test.dart')):
            for line, name in names(path):
                seen[name].append((str(path.relative_to(root)), line))
    for name, where in sorted(seen.items()):
        if len({f for f, _ in where}) > 1:
            for f, line in where:
                print(f'{f}:{line}: {name}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
