#!/usr/bin/env python3
"""La liste des tests, décidée avant d'en écrire un (étape 3a).

    test_plan.py items <spec.md>
    test_plan.py check <spec.md> <tests_plan.json> <package>[,<package writes.extra>…]
    test_plan.py match <tests_plan.json> <racine du projet> <package>[,<package writes.extra>…] <base>

`items` : ce que la spec demande de prouver, numéroté — S<n> les scénarios de §4, K<n> les contrats de §5,
D<n> les lignes des tables et les règles numérotées de §6, E<n> les erreurs de §7.

`check` : la liste de Théo (le modèle propose, le script décide : décodée strictement, refusée au premier
champ faux). Assez : chaque item est prouvé par un test ou écarté avec sa raison, chaque scénario a son test
d'acceptation. Sobre : chaque test prouve au moins un item, aucun test n'est listé deux fois. Les items
prouvés par beaucoup de tests sont listés pour Gaëlle, sans bloquer : c'est elle qui juge un doublon.

`match` (gate red) : les tests écrits sont ceux de la liste, ni plus ni moins. Un test se compare par son
fichier et son nom ; un scénario par son titre dans le `.feature`. En mode extend, seuls les tests ajoutés
depuis <base> comptent.

Fichiers de test reconnus, par langage : Dart, `<package>/test/**/*_test.dart` et `<package>/test/**/*.feature` ;
Kotlin (module Gradle), `<module>/src/test/**/*Test(s).kt`, `<module>/src/androidTest/**/*.kt` et les `.feature` sous
`src/test` ou `src/androidTest` (Cucumber, d'ordinaire `src/test/resources`). Un nom de test Kotlin est celui de la
méthode JUnit (`@Test`, `@ParameterizedTest`…) : le texte entre backticks, l'identifiant sinon, `@DisplayName`
s'il y en a un.

<package> peut être une liste séparée par des virgules : le package de la feature, puis les packages de
writes.extra où elle a le droit d'écrire des tests (un appel dans features/user, son acceptation à côté).

Sortie : une ligne « ✗ … » par problème (exit 1), « ? … » pour un signal à Gaëlle.
"""

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_dups import names as test_names  # noqa: E402

LAYERS = {'mapper', 'parser', 'model', 'data_source', 'service', 'repository', 'use_case', 'bloc', 'widget',
          'acceptance', 'injection', 'other'}
TEST_FIELDS = {'file', 'name', 'layer', 'proves'}
SKIP_FIELDS = {'items', 'why'}
SECTION = re.compile(r'^##\s+(\d+)\.')
SCENARIO = re.compile(r'^\s*Scenario(?: Outline)?:\s*(.+?)\s*$')
CROWD = 4  # au-delà, un item prouvé par autant de tests est signalé à Gaëlle


def norm(name: str) -> str:
    return re.sub(r'\s+', ' ', name.strip().lower())


def items(spec: str) -> list[dict]:
    out, section, sub, counts = [], None, '', {'S': 0, 'K': 0, 'D': 0, 'E': 0}
    kind_of = {'4': 'S', '5': 'K', '6': 'D', '7': 'E'}

    def add(kind, text):
        counts[kind] += 1
        out.append({'id': f'{kind}{counts[kind]}', 'section': f'§{section}', 'text': text})

    in_header = False
    for line in spec.splitlines():
        m = SECTION.match(line)
        if m:
            section, sub, in_header = m.group(1), '', False
            continue
        if line.startswith('#'):
            sub = line.lstrip('#').strip()
            continue
        kind = kind_of.get(section)
        if not kind:
            continue
        if kind == 'S':
            s = SCENARIO.match(line)
            if s:
                add('S', s.group(1))
            continue
        if kind == 'D' and re.match(r'^\d+\.\s+\S', line):  # une règle numérotée (étapes d'un chargement)
            add('D', f"{sub} : {line.strip()}" if sub else line.strip())
            continue
        if not line.startswith('|'):
            in_header = False
            continue
        cells = [c.strip() for c in line.strip().strip('|').split('|')]
        if not in_header:  # première ligne d'une table : l'en-tête
            in_header = True
            continue
        if all(re.fullmatch(r':?-+:?', c) for c in cells if c):
            continue
        if cells and cells[0]:
            add(kind, f'{sub} : {cells[0]}' if sub and kind == 'D' else cells[0])
    return out


def packages(arg: str) -> list[str]:
    """Le package de la feature, puis ceux de writes.extra : « a,b » → [a, b]."""
    return [p for p in arg.split(',') if p]


def is_test_file(f: str, package: str) -> bool:
    """Un fichier de test du package (Dart) ou du module (Kotlin), d'après le chemin seul."""
    for p in packages(package):
        p = p.rstrip('/') + '/'
        if not f.startswith(p):
            continue
        rest = f[len(p):]
        if rest.startswith('test/') and (f.endswith('_test.dart') or f.endswith('.feature')):
            return True
        if rest.startswith('src/test/') and (re.search(r'Tests?\.kt$', f) or f.endswith('.feature')):
            return True
        if rest.startswith('src/androidTest/') and (f.endswith('.kt') or f.endswith('.feature')):
            return True
    return False


def decode(raw: str, ids: set[str], package: str) -> tuple[list[dict], list[dict]]:
    data = json.loads(raw)
    if not isinstance(data, dict) or set(data) - {'tests', 'not_tested'} or not isinstance(data.get('tests'), list):
        raise ValueError('attendu : {"tests": [...], "not_tested": [...]}')
    skips = data.get('not_tested', [])
    if not isinstance(skips, list):
        raise ValueError('not_tested : une liste')
    seen = set()
    for i, t in enumerate(data['tests']):
        where = f'test {i + 1}'
        if not isinstance(t, dict) or set(t) != TEST_FIELDS:
            raise ValueError(f'{where} : champs attendus {sorted(TEST_FIELDS)}')
        f = t['file']
        if not isinstance(f, str) or f.startswith('/') or '..' in Path(f).parts \
                or not is_test_file(f, package):
            raise ValueError(f"{where} : {f!r} n'est pas un fichier de test du package {package}")
        if not isinstance(t['name'], str) or not t['name'].strip() or len(t['name']) > 300 or '\n' in t['name']:
            raise ValueError(f'{where} : nom invalide')
        if t['layer'] not in LAYERS:
            raise ValueError(f"{where} : layer {t['layer']!r} hors de {sorted(LAYERS)}")
        if (t['layer'] == 'acceptance') != f.endswith('.feature'):
            raise ValueError(f'{where} : un test d\'acceptation est un scénario du .feature, et lui seul')
        if not isinstance(t['proves'], list) or not t['proves'] or not all(isinstance(p, str) for p in t['proves']):
            raise ValueError(f"{where} « {t['name']} » : proves vide (un test qui ne prouve aucun item n'a pas sa place)")
        unknown = [p for p in t['proves'] if p not in ids]
        if unknown:
            raise ValueError(f'{where} : items inconnus {unknown} (test_plan.py items <spec>)')
        key = (f, norm(t['name']))
        if key in seen:
            raise ValueError(f"{where} : « {t['name']} » listé deux fois dans {f}")
        seen.add(key)
    for i, s in enumerate(skips):
        where = f'not_tested {i + 1}'
        if not isinstance(s, dict) or set(s) != SKIP_FIELDS or not isinstance(s['items'], list) or not s['items']:
            raise ValueError(f'{where} : champs attendus {sorted(SKIP_FIELDS)}')
        if not isinstance(s['why'], str) or not s['why'].strip() or len(s['why']) > 500:
            raise ValueError(f'{where} : why vide ou trop long')
        unknown = [p for p in s['items'] if p not in ids]
        if unknown:
            raise ValueError(f'{where} : items inconnus {unknown}')
    return data['tests'], skips


def check(spec_path: str, plan_path: str, package: str) -> int:
    its = items(Path(spec_path).read_text())
    ids = {i['id'] for i in its}
    try:
        tests, skips = decode(Path(plan_path).read_text(), ids, package)
    except (ValueError, OSError) as e:
        print(f'✗ liste refusée : {e}')
        return 1
    proved: dict[str, list[dict]] = {}
    for t in tests:
        for p in t['proves']:
            proved.setdefault(p, []).append(t)
    skipped = {p for s in skips for p in s['items']}
    bad = 0
    for it in its:
        i = it['id']
        if i in proved and i in skipped:
            print(f"✗ {i} ({it['text'][:80]}) : à la fois prouvé et écarté")
            bad += 1
        elif i not in proved and i not in skipped:
            print(f"✗ {i} {it['section']} ({it['text'][:80]}) : aucun test ne le prouve, et il n'est pas écarté")
            bad += 1
        elif it['id'].startswith('S') and i in proved and not any(t['layer'] == 'acceptance' for t in proved[i]):
            print(f"✗ {i} ({it['text'][:80]}) : scénario sans test d'acceptation")
            bad += 1
    for i, ts in sorted(proved.items()):
        if len(ts) >= CROWD:
            layers = sorted({t['layer'] for t in ts})
            print(f"? {i} prouvé par {len(ts)} tests ({', '.join(layers)}) : un comportement, un étage ?")
    n_acc = sum(t['layer'] == 'acceptance' for t in tests)
    print(f'liste : {len(tests)} tests ({n_acc} scénarios), {len(its)} items, {len(skipped)} écartés')
    return 1 if bad else 0


KT_TEST_ANN = re.compile(r'@(?:org\.junit\.(?:jupiter\.api\.)?)?(Test|ParameterizedTest|RepeatedTest|TestFactory|TestTemplate)\b')
KT_DISPLAY = re.compile(r'@DisplayName\(\s*"((?:[^"\\]|\\.)*)"\s*\)')
KT_FUN = re.compile(r'\bfun\s+(?:`([^`]+)`|([A-Za-z_][A-Za-z0-9_]*))\s*\(')


def kotlin_test_names(path: Path):
    """(ligne, nom normalisé) des méthodes JUnit : @Test puis le `fun` qui suit (backticks compris)."""
    lines = path.read_text(errors='replace').splitlines()
    i = 0
    while i < len(lines):
        if not KT_TEST_ANN.search(re.sub(r'//.*', '', lines[i])):
            i += 1
            continue
        display = None
        for j in range(i, min(i + 8, len(lines))):
            d = KT_DISPLAY.search(lines[j])
            display = display or (d.group(1) if d else None)
            f = KT_FUN.search(lines[j])
            if f:
                yield j + 1, norm(display or f.group(1) or f.group(2))
                i = j
                break
        i += 1


def test_files(tdir: Path, kotlin: bool):
    if not tdir.is_dir():
        return []
    if not kotlin:
        return sorted(tdir.rglob('*_test.dart'))
    return sorted(p for p in tdir.rglob('*.kt') if tdir.name == 'androidTest' or re.search(r'Tests?\.kt$', p.name))


def written(root: Path, package: str, base: str) -> set[tuple[str, str]]:
    """(fichier, nom normalisé) des tests et scénarios du package, moins ceux qui existaient à <base>."""
    def at_base(rel: str) -> str:
        if not base:
            return ''
        run = subprocess.run(['git', 'show', f'{base}:{rel}'], cwd=root, capture_output=True, text=True)
        return run.stdout if run.returncode == 0 else ''

    def scenarios(text: str) -> set[str]:
        return {norm(m.group(1)) for m in map(SCENARIO.match, text.splitlines()) if m}

    out = set()
    for pkg in packages(package):
        out |= _written_in(root, pkg, at_base, scenarios)
    return out


def _written_in(root: Path, package: str, at_base, scenarios) -> set[tuple[str, str]]:
    out = set()
    # Dart : <package>/test ; Kotlin : <module>/src/test et src/androidTest
    dirs = [(root / package / 'test', False), (root / package / 'src' / 'test', True),
            (root / package / 'src' / 'androidTest', True)]
    for tdir, kotlin in dirs:
        names_of = kotlin_test_names if kotlin else test_names
        for path in test_files(tdir, kotlin):
            if not kotlin and path.with_name(path.name[:-len('_test.dart')] + '.feature').exists():
                continue  # généré par bdd_widget_test depuis le .feature, dont les scénarios comptent déjà
            rel = str(path.relative_to(root))
            old = at_base(rel)
            before = set()
            if old:
                with tempfile.TemporaryDirectory() as d:
                    tmp = Path(d) / path.name
                    tmp.write_text(old)
                    before = {n for _, n in names_of(tmp)}
            out |= {(rel, n) for _, n in names_of(path) if n not in before}
        for path in sorted(tdir.rglob('*.feature')) if tdir.is_dir() else []:
            rel = str(path.relative_to(root))
            out |= {(rel, n) for n in scenarios(path.read_text()) - scenarios(at_base(rel))}
    return out


def match(plan_path: str, root: str, package: str, base: str) -> int:
    plan = json.loads(Path(plan_path).read_text())
    planned = {(t['file'], norm(t['name'])) for t in plan['tests']}
    have = written(Path(root), package, base)
    bad = 0
    for f, n in sorted(planned - have):
        print(f'✗ prévu, pas écrit : {f} — {n}')
        bad += 1
    for f, n in sorted(have - planned):
        print(f'✗ écrit, pas prévu : {f} — {n} (ajoute-le à tests_plan.json avec ce qu\'il prouve, ou retire-le)')
        bad += 1
    print(f'{len(have)} test(s) écrits, {len(planned)} prévus')
    return 1 if bad else 0


def main() -> int:
    cmd, args = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ('', [])
    if cmd == 'items' and len(args) == 1:
        for it in items(Path(args[0]).read_text()):
            print(f"{it['id']}\t{it['section']}\t{it['text']}")
        return 0
    if cmd == 'check' and len(args) == 3:
        return check(*args)
    if cmd == 'match' and len(args) == 4:
        return match(*args)
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main())
