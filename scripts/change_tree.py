#!/usr/bin/env python3
"""change_tree.py — l'arbre du changement, mesuré : fichiers groupés par package et par couche, volume,
fichiers générés, et part de reformatage (instructions comparées sans espaces ni retours à la ligne).

Partagé par /reviewPR (briefing), /feature (visite guidée, evidence) et /fix (evidence). Le script
mesure ; la colonne « rôle » (une ligne par fichier : ce que le changement y fait) reste à écrire par
qui lit le diff — elle est laissée en `<rôle>`.

Usage : change_tree.py <base> [--head <rev>] [-C <dossier du repo>] [--json]
  <base>   le merge-base (ou tout commit de départ)
  --head   un commit ; absent : l'arbre de travail (modifications non commitées comprises)
"""
import difflib
import fnmatch
import json
import os
import re
import subprocess
import sys

LAYERS = ("data", "domain", "presentation")
GENERATED = ("*.g.dart", "*.freezed.dart", "*.gr.dart", "*.config.dart", "*.mocks.dart", "*.gen.dart",
             "*/l10n/generated/*", "*/generated/*", "pubspec.lock", "*.pbxproj")
REFORMAT_MIN = 20       # en dessous, pas de verdict de reformatage
REFORMAT_RATIO = 0.25   # moins d'un changement réel pour 4 lignes du diff → « le reste = reformat »


def git(cwd, *args):
    r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"git {' '.join(args)} : {r.stderr.strip()}")
    return r.stdout


def numstat(cwd, base, head, extra=()):
    rng = [base, head] if head else [base]
    out = {}
    for line in git(cwd, "diff", "--numstat", "-M", *extra, *rng).splitlines():
        a, d, path = line.split("\t", 2)
        if " => " in path:  # renommage : a/{x => y}/b
            path = re.sub(r"\{([^{}]*) => ([^{}]*)\}", r"\2", path).replace("//", "/")
            path = path.split(" => ")[-1]
        out[path] = (int(a) if a != "-" else 0, int(d) if d != "-" else 0, a == "-")
    return out


def content(cwd, rev, path):
    if rev is None:
        try:
            with open(os.path.join(cwd, path), encoding="utf-8", errors="replace") as f:
                return f.read()
        except OSError:
            return ""
    r = subprocess.run(["git", "show", f"{rev}:{path}"], cwd=cwd, capture_output=True, text=True, errors="replace")
    return r.stdout if r.returncode == 0 else ""


STATEMENT = re.compile(r"[^;{}]*[;{}]|[^;{}]+$")


def statements(text):
    """Le code sans aucun espace ni retour à la ligne, découpé en instructions (; { }) : un reformatage
    (dart format, indentation, retours à la ligne, virgules finales mises à part) ne change rien ici."""
    flat = re.sub(r"\s+", "", text)
    flat = re.sub(r",([)\]}])", r"\1", flat)  # virgule finale ajoutée ou retirée par le formateur
    return [m.group(0) for m in STATEMENT.finditer(flat) if m.group(0)]


def real_changes(cwd, base, head, path, old_path=None):
    """Nombre d'instructions réellement ajoutées, retirées ou modifiées, formatage ignoré."""
    a = statements(content(cwd, base, old_path or path))
    b = statements(content(cwd, head, path))
    n = 0
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        if op != "equal":
            n += max(i2 - i1, j2 - j1)
    return n


def statuses(cwd, base, head):
    rng = [base, head] if head else [base]
    st = {}
    for line in git(cwd, "diff", "--name-status", "-M", *rng).splitlines():
        parts = line.split("\t")
        st[parts[-1]] = parts[0][0]
    if not head:
        for p in git(cwd, "ls-files", "--others", "--exclude-standard").splitlines():
            st.setdefault(p, "A")
    return st


def untracked_numstat(cwd):
    out = {}
    for p in git(cwd, "ls-files", "--others", "--exclude-standard").splitlines():
        try:
            with open(os.path.join(cwd, p), encoding="utf-8", errors="replace") as f:
                out[p] = (sum(1 for _ in f), 0, False)
        except OSError:
            pass
    return out


def has_pubspec(cwd, head, d):
    rel = os.path.join(d, "pubspec.yaml") if d else "pubspec.yaml"
    if head:
        return subprocess.run(["git", "cat-file", "-e", f"{head}:{rel}"], cwd=cwd, capture_output=True).returncode == 0
    return os.path.isfile(os.path.join(cwd, rel))


def package_of(cwd, head, path, cache):
    d = os.path.dirname(path)
    while True:
        if d not in cache:
            cache[d] = has_pubspec(cwd, head, d)
        if cache[d]:
            return d
        if not d:
            return None
        d = os.path.dirname(d)


def group_of(pkg, path):
    """(groupe, nom affiché, rang de tri) — `code/presentation/` + `widget/filter_widget.dart`."""
    if pkg is None:
        d = os.path.dirname(path)
        return (d + "/" if d else "./"), os.path.basename(path), (9, d)
    rel = path[len(pkg) + 1:] if pkg else path
    name = os.path.basename(pkg) if pkg else "app"
    if rel.startswith("test/") or rel.startswith("integration_test/"):
        head, _, rest = rel.partition("/")
        return f"{name}/{head}/", rest, (8, name)
    for prefix in ("lib/src/", "lib/"):
        if rel.startswith(prefix):
            rel = rel[len(prefix):]
            break
    first, _, rest = rel.partition("/")
    if first in LAYERS and rest:
        return f"{name}/{first}/", rest, (LAYERS.index(first) + 1, name)
    return f"{name}/", rel, (0, name)


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        sys.exit(0 if argv else 2)
    base, head, cwd, as_json = argv[0], None, os.getcwd(), "--json" in argv
    if "--head" in argv:
        head = argv[argv.index("--head") + 1]
    if "-C" in argv:
        cwd = argv[argv.index("-C") + 1]
    cwd = git(cwd, "rev-parse", "--show-toplevel").strip()
    full = numstat(cwd, base, head)
    if not head:
        full.update(untracked_numstat(cwd))
    st = statuses(cwd, base, head)
    cache, rows = {}, []
    for path, (a, d, binary) in sorted(full.items()):
        pkg = package_of(cwd, head, path, cache)
        group, name, rank = group_of(pkg, path)
        total, useful = a + d, a + d
        notes = []
        kind = st.get(path, "M")
        if any(fnmatch.fnmatch(path, g) or fnmatch.fnmatch(os.path.basename(path), g) for g in GENERATED):
            notes.append("généré")
        elif binary:
            notes.append("binaire")
        elif kind == "M" and total >= REFORMAT_MIN:
            useful = real_changes(cwd, base, head, path)
            if useful < total * REFORMAT_RATIO:
                notes.append("⚠ " + (f"{useful} changement{'s' if useful > 1 else ''} réel{'s' if useful > 1 else ''}, le reste = reformat"
                                     if useful else "reformat seul"))
        if kind == "A":
            notes.append("nouveau")
        elif kind == "D":
            notes.append("supprimé")
        elif kind == "R":
            notes.append("renommé")
        rows.append({"path": path, "group": group, "name": name, "rank": rank, "added": a, "deleted": d,
                     "useful": useful, "notes": notes})
    rows.sort(key=lambda r: (r["rank"][1] or "", r["rank"][0], r["group"], r["name"]))
    if as_json:
        print(json.dumps({"base": base, "head": head or "worktree", "files": rows}, ensure_ascii=False, indent=2))
        return
    if not rows:
        print("(aucun fichier modifié)")
        return
    LONG = 14  # un groupe plus long que ça va sur sa propre ligne, ses fichiers en dessous
    gw = max([len(r["group"]) for r in rows if len(r["group"]) <= LONG] + [8]) + 2
    nw = max(len(r["name"]) for r in rows) + 2
    vw = max(len(f"+{r['added']}/-{r['deleted']}") for r in rows) + 3
    print("```")
    last = None
    for r in rows:
        g = r["group"] if r["group"] != last else ""
        if g and len(g) > LONG:
            print(g)
            g = ""
        last = r["group"]
        vol = f"+{r['added']}/-{r['deleted']}"
        note = (" " + " · ".join(r["notes"])) if r["notes"] else ""
        print(f"{g:<{gw}}{r['name']:<{nw}}{vol:<{vw}}<rôle>{note}")
    adds = sum(r["added"] for r in rows)
    dels = sum(r["deleted"] for r in rows)
    useful = sum(r["useful"] for r in rows if "généré" not in r["notes"])
    print("```")
    print(f"{len(rows)} fichiers · +{adds}/-{dels} · ≈{useful} changements réels (formatage et fichiers générés exclus)")


if __name__ == "__main__":
    main(sys.argv[1:])
