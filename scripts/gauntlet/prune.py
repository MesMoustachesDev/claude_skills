#!/usr/bin/env python3
"""Élagage vérifié des tests : retire des tests candidats, garde le retrait seulement si rien n'est perdu.

    prune.py --root <projet> --package <package relatif> --feature <nom> --flutter "<cmd>"
             --gauntlet <gauntlet.sh> <candidates.json> [--no-mutation]

Lancé par `gauntlet.sh prune <feature> <candidates.json>`. Le modèle propose, le script décide : la liste
vient d'Élise (agent test-pruner), elle est décodée strictement et refusée entière si un candidat ne passe pas.
Pour un lot de candidats :
  1. les retire du code (le bloc `test(...)` entier, du nom jusqu'à sa parenthèse fermante) ;
  2. la suite du package doit rester verte ;
  3. les lignes couvertes de lib/ (lcov) doivent être les mêmes ;
  4. le score de mutation du gauntlet (périmètre de la feature) ne doit pas baisser.
Un lot qui perd quelque chose est coupé en deux et chaque moitié rejouée, jusqu'au candidat seul.
Écrit le verdict dans <candidates>.result.json et laisse les retraits acceptés dans le worktree, non commités.
Exit 0 : élagage joué ; 2 : liste refusée ou suite de référence rouge.
"""

import argparse
import json
import re
import shlex
import subprocess
import sys
from pathlib import Path

KINDS = {'deja_prouve', 'variante', 'transmission', 'rendu'}
FIELDS = {'file', 'line', 'name', 'kind', 'proved_by', 'why'}
CALL = re.compile(r'\b(testWidgets|blocTest|test)\b\s*(<[^>(]*>)?\(')


def decode(raw: str, root: Path, package: str) -> list[dict]:
    """La liste d'Élise, ou ValueError : champs connus, valeurs bornées, fichiers du package."""
    data = json.loads(raw)
    if not isinstance(data, dict) or set(data) != {'candidates'} or not isinstance(data['candidates'], list):
        raise ValueError('attendu : {"candidates": [...]}')
    out, seen = [], set()
    for i, c in enumerate(data['candidates']):
        where = f'candidat {i + 1}'
        if not isinstance(c, dict) or set(c) != FIELDS:
            raise ValueError(f'{where} : champs attendus {sorted(FIELDS)}')
        f, line, name = c['file'], c['line'], c['name']
        if not isinstance(f, str) or f.startswith('/') or '..' in Path(f).parts \
                or not f.startswith(package.rstrip('/') + '/test/') or not f.endswith('_test.dart'):
            raise ValueError(f'{where} : {f!r} n\'est pas un fichier de test du package {package}')
        if not (root / f).is_file():
            raise ValueError(f'{where} : {f} introuvable')
        if not isinstance(line, int) or isinstance(line, bool) or line < 1:
            raise ValueError(f'{where} : ligne {line!r} invalide')
        if not isinstance(name, str) or not name.strip() or len(name) > 300 or '\n' in name:
            raise ValueError(f'{where} : nom de test invalide')
        if c['kind'] not in KINDS:
            raise ValueError(f"{where} : kind {c['kind']!r} hors de {sorted(KINDS)}")
        for k in ('proved_by', 'why'):
            if not isinstance(c[k], str) or not c[k].strip() or len(c[k]) > 1000:
                raise ValueError(f'{where} : {k} vide ou trop long')
        if (f, name) in seen:
            raise ValueError(f'{where} : « {name} » proposé deux fois')
        seen.add((f, name))
        out.append(c)
    return out


def call_span(lines: list[str], start: int) -> tuple[int, int]:
    """Lignes [start, end] du bloc qui commence à `start` (index 0), parenthèses équilibrées hors chaînes."""
    depth, i, seen = 0, start, False
    while i < len(lines):
        s, j = lines[i], 0
        while j < len(s):
            if s.startswith('//', j):
                break
            q = next((q for q in ("'''", '"""', "'", '"') if s.startswith(q, j)), None)
            if q:
                k = s.find(q, j + len(q))
                while k == -1 and len(q) == 3 and i + 1 < len(lines):
                    i, s, j = i + 1, lines[i + 1], 0
                    k = s.find(q)
                j = (k + len(q)) if k != -1 else len(s)
                continue
            c = s[j]
            if c == '(':
                depth, seen = depth + 1, True
            elif c == ')':
                depth -= 1
                if seen and depth == 0:
                    return start, i
            j += 1
        i += 1
    raise ValueError(f'bloc non fermé à la ligne {start + 1}')


def remove(text: str, cands: list[dict]) -> str:
    """Le fichier sans les tests `cands`, ou ValueError si l'un d'eux est introuvable."""
    lines = text.splitlines(keepends=True)
    spans = []
    for c in cands:
        at = c['line'] - 1
        # Le nom peut avoir bougé de quelques lignes : on cherche l'appel qui porte ce nom.
        near = [k for k in range(max(0, at - 5), min(len(lines), at + 6)) if c['name'] in lines[k]]
        # Des retraits plus haut dans le fichier ont décalé les lignes : on cherche partout.
        hits = near or [k for k in range(len(lines)) if c['name'] in lines[k]]
        if not hits:
            raise ValueError(f"{c['file']}:{c['line']} : test « {c['name']} » introuvable")
        k = hits[0]
        while k >= 0 and not CALL.search(lines[k]):
            k -= 1
        if k < 0 or hits[0] - k > 2:
            raise ValueError(f"{c['file']}:{c['line']} : « {c['name']} » n'est pas le nom d'un test")
        spans.append(call_span(lines, k))
    for a, b in sorted(set(spans), reverse=True):
        end = b + 1
        if end < len(lines) and lines[end].strip() == '':
            end += 1
        del lines[a:end]
    return ''.join(lines)


class Pruner:
    def __init__(self, args):
        self.root, self.package, self.feature = Path(args.root), args.package, args.feature
        self.flutter, self.gauntlet, self.mutation = shlex.split(args.flutter), args.gauntlet, not args.no_mutation

    def sh(self, argv, cwd):
        return subprocess.run(argv, cwd=cwd, capture_output=True, text=True, timeout=7200)

    def covered(self) -> set[tuple[str, int]] | None:
        pkg = self.root / self.package
        if self.sh([*self.flutter, 'test', '--coverage'], cwd=pkg).returncode:
            return None
        hit, src = set(), ''
        for line in (pkg / 'coverage/lcov.info').read_text().splitlines():
            if line.startswith('SF:'):
                src = line[3:]
            elif line.startswith('DA:'):
                n, count = line[3:].split(',')[:2]
                if int(count) > 0 and '/lib/' in '/' + src:
                    hit.add((src, int(n)))
        return hit

    def score(self) -> float | None:
        if not self.mutation:
            return None
        run = self.sh(['bash', self.gauntlet, 'mutation', self.feature], cwd=self.root)
        m = re.search(r'score : (\d+)%', run.stdout + run.stderr)
        return float(m.group(1)) if m else None

    def apply(self, batch: list[dict]) -> dict[Path, str]:
        """Retire `batch` ; rend le contenu d'origine des fichiers touchés, pour revenir en arrière."""
        before: dict[Path, str] = {}
        by_file: dict[str, list[dict]] = {}
        for c in batch:
            by_file.setdefault(c['file'], []).append(c)
        try:
            for rel, cs in by_file.items():
                p = self.root / rel
                before[p] = p.read_text()
                p.write_text(remove(before[p], cs))
        except ValueError:
            self.restore(before)
            raise
        return before

    @staticmethod
    def restore(before: dict[Path, str]) -> None:
        for p, text in before.items():
            p.write_text(text)

    def run(self, cands: list[dict]) -> dict:
        base_cov, base_mut = self.covered(), self.score()
        if base_cov is None:
            raise RuntimeError('la suite de référence est rouge : rien à mesurer')
        if self.mutation and base_mut is None:
            raise RuntimeError('pas de score de mutation de référence (gauntlet.sh mutation)')
        print(f'référence : {len(base_cov)} lignes couvertes, mutation {base_mut}', flush=True)
        accepted, rejected, log, queue = [], [], [], [cands]
        while queue:
            batch = queue.pop(0)
            try:
                before = self.apply(batch)
            except ValueError as e:
                if len(batch) == 1:
                    rejected.append({**batch[0], 'verdict': f'non appliqué : {e}'})
                else:
                    queue += [batch[:len(batch) // 2], batch[len(batch) // 2:]]
                continue
            cov, mut = self.covered(), self.score()
            lost = None if cov is None else sorted(base_cov - cov)
            ok = cov is not None and not lost and (not self.mutation or (mut is not None and mut >= base_mut))
            log.append({'size': len(batch), 'suite': cov is not None, 'lines_lost': len(lost or []), 'mutation': mut})
            print(f"lot de {len(batch)} : {'gardé' if ok else 'perd quelque chose'} {log[-1]}", flush=True)
            if ok:
                accepted += batch
                continue
            self.restore(before)
            if len(batch) == 1:
                why = 'suite rouge' if cov is None else (
                    f'{len(lost)} ligne(s) de lib/ plus couvertes' if lost else f'mutation {mut} < {base_mut}')
                rejected.append({**batch[0], 'verdict': why})
            else:
                queue += [batch[:len(batch) // 2], batch[len(batch) // 2:]]
        return {'baseline': {'covered': len(base_cov), 'mutation': base_mut},
                'accepted': accepted, 'rejected': rejected, 'runs': log}


def main() -> int:
    ap = argparse.ArgumentParser()
    for a in ('--root', '--package', '--feature', '--flutter', '--gauntlet'):
        ap.add_argument(a, required=True)
    ap.add_argument('--no-mutation', action='store_true')
    ap.add_argument('candidates')
    args = ap.parse_args()
    path = Path(args.candidates)
    try:
        cands = decode(path.read_text(), Path(args.root), args.package)
    except (ValueError, OSError) as e:
        print(f'liste refusée : {e}')
        return 2
    try:
        result = Pruner(args).run(cands)
    except RuntimeError as e:
        print(e)
        return 2
    out = path.with_suffix('.result.json')
    out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(f"{len(result['accepted'])} retirés, {len(result['rejected'])} gardés → {out}")
    return 0


if __name__ == '__main__':
    sys.exit(main())
