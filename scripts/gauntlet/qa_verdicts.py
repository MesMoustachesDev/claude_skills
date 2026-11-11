#!/usr/bin/env python3
"""qa_verdicts.py — juge le tableau de verdicts de qa.md quand la QA s'est faite sans flow (feature sans écran).

    qa_verdicts.py --spec spec.md --qa qa.md --raw <dossier> --platform android

Chaque scénario de §4 doit avoir sa ligne dans un tableau de qa.md dont une colonne porte le nom de la
plateforme (casse ignorée). Le scénario se reconnaît à son titre exact, casse et espaces ignorés.
Verdict : ✓ (« ✓ avec réserve » compris), ✗, ou « non vérifié ». Rouge si un scénario manque, si un
verdict est ✗, « non vérifié » ou autre chose, ou si une ligne ✓ ne cite entre backticks aucun fichier
existant de <dossier> (la sortie brute de l'appel). Sortie 0 vert, 1 rouge, 2 entrée illisible.
"""
import argparse
import re
import sys
from pathlib import Path

SECTION = re.compile(r'^##\s+(\d+)\.')
SCENARIO = re.compile(r'^\s*Scenario(?: Outline)?:\s*(.+?)\s*$')
TICK = re.compile(r'`([^`\s]+)`')


def norm(text: str) -> str:
    return re.sub(r'\s+', ' ', text.strip().lower())


def scenarios(spec: str) -> list[str]:
    out, section = [], None
    for line in spec.splitlines():
        m = SECTION.match(line)
        if m:
            section = m.group(1)
            continue
        s = SCENARIO.match(line) if section == '4' else None
        if s:
            out.append(s.group(1))
    return out


def cells(line: str) -> list[str]:
    return [c.strip() for c in line.strip().strip('|').split('|')]


def rows(qa: str, platform: str):
    """(titre normalisé, verdict, ligne entière) des tableaux de qa.md qui ont une colonne <platform>."""
    header = None
    for line in qa.splitlines():
        if not line.lstrip().startswith('|'):
            header = None
            continue
        c = cells(line)
        if header is None:
            header = [norm(x) for x in c]
            continue
        if all(re.fullmatch(r':?-+:?', x) for x in c if x):
            continue
        if platform not in header or 'scénario' not in header:
            continue
        get = dict(zip(header, c))
        yield norm(get.get('scénario', '')), get.get(platform, '').strip(), line


def verdict(cell: str) -> str:
    v = norm(cell)
    if v.startswith('✓'):
        return 'ok'
    if v.startswith('✗'):
        return 'ko'
    if v.startswith('non vérifié'):
        return 'unchecked'
    return 'unknown'


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--spec', required=True)
    ap.add_argument('--qa', required=True)
    ap.add_argument('--raw', required=True)
    ap.add_argument('--platform', required=True)
    a = ap.parse_args()
    try:
        spec = Path(a.spec).read_text(encoding='utf-8')
        qa = Path(a.qa).read_text(encoding='utf-8')
    except OSError as e:
        print(f'illisible : {e}')
        return 2
    titles = scenarios(spec)
    if not titles:
        print('aucun scénario en §4 de la spec')
        return 2
    raw = Path(a.raw)
    found: dict[str, list[tuple[str, str]]] = {}
    for title, cell, line in rows(qa, norm(a.platform)):
        found.setdefault(title, []).append((cell, line))
    problems, passed = [], 0
    for t in titles:
        got = found.get(norm(t))
        if not got:
            problems.append(f'« {t} » : pas de verdict {a.platform} dans qa.md')
            continue
        if len(got) > 1:
            problems.append(f'« {t} » : {len(got)} lignes de verdict, une seule attendue')
            continue
        cell, line = got[0]
        v = verdict(cell)
        if v == 'ko':
            problems.append(f'« {t} » : ✗')
        elif v == 'unchecked':
            problems.append(f'« {t} » : non vérifié')
        elif v == 'unknown':
            problems.append(f'« {t} » : verdict « {cell} » (attendu ✓, ✗ ou non vérifié)')
        elif not any((raw / Path(name).name).is_file() for name in TICK.findall(line)):
            problems.append(f'« {t} » : ✓ sans sortie brute citée (`fichier` de {raw.name}/ entre backticks)')
        else:
            passed += 1
    print(f'{passed}/{len(titles)} scénario(s) ✓ avec sortie brute ({a.platform})')
    for p in problems:
        print(f'   {p}')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
