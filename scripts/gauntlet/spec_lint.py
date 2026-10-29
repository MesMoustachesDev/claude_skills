#!/usr/bin/env python3
"""spec_lint.py — vérifications mécaniques de spec.md, avant la critique de Camille.

Usage : spec_lint.py <spec.md> <package> <racine du workspace> <archi.json ou -> <plafond en octets>

Ce qu'une relecture humaine trouve aussi, mais qu'un script trouve sans coût ni oubli (cas réel :
refactor_feature, 3 des 10 bloquants de la première critique) :
  - clés : chaque clé citée ('<préfixe>_x' ou <Name>Keys.x) existe dans les keys.dart du package ;
  - §7 : chaque ligne d'erreur cite le scénario qui la prouve (C<n>), ou dit « hors scénario : <raison> » ;
  - symboles : chaque symbole de §5 existe dans le workspace ; chaque `Classe.membre` cité, dont la classe
    est du workspace, existe dans le fichier de cette classe ;
  - archi.json : chaque scénario relié à un C<n> est un titre de §4 ;
  - taille : la spec tient dans le plafond du gabarit.
`<!-- spec_lint: ignore <jeton> -->` dans la spec exempte un jeton (faux positif assumé).
Sortie : une ligne « ✗ … » par problème ; exit 1 s'il y en a.
"""
import json
import os
import re
import sys

DECL = re.compile(r"^\s*(?:@\w+\s+)*(?:(?:abstract|sealed|final|base|interface|mixin)\s+)*"
                  r"(?:class|mixin|enum|typedef|extension(?:\s+type)?)\s+([A-Z]\w*)", re.M)
# Types du SDK et des paquets d'erreur qu'une §5 cite sans qu'ils soient des contrats du workspace.
SDK_TYPES = {"Either", "Left", "Right", "Unit", "Option", "Some", "None", "Stream", "Future", "FutureOr", "List",
             "Map", "Set", "Iterable", "String", "Object", "Exception", "Error", "Duration", "DateTime", "Uri",
             "Uint8List", "Widget", "BuildContext", "Bloc", "Cubit", "Emitter", "Equatable", "StreamController",
             "StreamSubscription", "Completer", "Timer", "Function", "Record", "Null", "Never", "Type"}
SKIP_DIRS = {".dart_tool", "build", ".git", "node_modules", "ios", "android", "macos", "linux", "windows", "web"}


def dart_files(root):
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x not in SKIP_DIRS and not x.startswith(".")]
        for f in files:
            if f.endswith(".dart") and not f.endswith((".g.dart", ".freezed.dart")):
                yield os.path.join(d, f)


def read(p):
    try:
        with open(p, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def section(spec, n):
    m = re.search(rf"(?m)^## {n}\..*?$(.*?)(?=^## \d+\.|\Z)", spec, re.S)
    return m.group(1) if m else ""


def main(spec_path, pkg, workspace, archi_path, cap):
    spec = read(spec_path)
    ignored = set(re.findall(r"<!--\s*spec_lint:\s*ignore\s+(\S+)\s*-->", spec))
    problems = []

    def ko(token, msg):
        if token not in ignored:
            problems.append(msg)

    # --- clés ---------------------------------------------------------------------------------
    keys_files = [p for p in dart_files(os.path.join(pkg, "lib")) if re.search(r"(^|_)keys\.dart$", os.path.basename(p))]
    values, names, classes = set(), set(), set()
    for p in keys_files:
        src = read(p)
        classes |= set(re.findall(r"class\s+(\w*Keys)\b", src))
        for name, val in re.findall(r"static\s+const\s+(?:String\s+)?(\w+)\s*=\s*'([^']*)'", src):
            names.add(name)
            values.add(val)
    if values:
        prefix = os.path.commonprefix(sorted(values))
        prefix = prefix[: prefix.rfind("_") + 1] if "_" in prefix else ""
        if len(prefix) >= 4:
            for tok in sorted(set(re.findall(rf"'({re.escape(prefix)}[a-z0-9_]*)'", spec))):
                if tok in values or any(v.endswith("_") and tok.startswith(v) and tok[len(v):].isdigit() for v in values):
                    continue
                ko(tok, f"✗ clé '{tok}' citée par la spec, absente des keys.dart du package — contrat à compléter (Thibault) ou clé mal écrite")
    for cls in classes:
        for name in sorted(set(re.findall(rf"\b{cls}\.(\w+)", spec))):
            if name not in names and len(name) > 1:  # `Keys.x` : un nom générique de la prose, pas une clé
                ko(f"{cls}.{name}", f"✗ {cls}.{name} cité par la spec, absent de {cls} — contrat à compléter (Thibault) ou nom mal écrit")

    # --- §7 : chaque erreur a son scénario --------------------------------------------------------
    rows = [l for l in section(spec, 7).splitlines() if l.strip().startswith("|")]
    for row in rows[2:] if len(rows) > 2 else []:
        cells = [c.strip() for c in row.strip().strip("|").split("|")]
        if not cells or set(cells[0]) <= {"-", " ", ":"} or re.search(r"\bC\d+", row) or "hors scénario" in row:
            continue
        label = re.sub(r"\s+", " ", cells[0])[:70]
        ko(label, f"✗ §7 « {label} » ne cite aucun scénario (C<n>) : ajoute le scénario qui la prouve, ou « hors scénario : <raison> »")

    # --- symboles ---------------------------------------------------------------------------------
    index = {}
    for root in {pkg, workspace}:
        for p in dart_files(root):
            for name in DECL.findall(read(p)):
                index.setdefault(name, set()).add(p)
    for tok in sorted(set(t for t in re.findall(r"`([A-Z]\w*)(?:<[^`]*>)?`", section(spec, 5)))):
        if tok not in index and tok not in SDK_TYPES:
            ko(tok, f"✗ §5 cite `{tok}`, introuvable dans le package et le workspace — renommé, ou pas encore écrit ?")
    for code in re.findall(r"`([^`\n]+)`", spec):
        for cls, member in re.findall(r"(?<![\w…])([A-Z]\w*)\.([a-z_]\w*)", code):
            files = index.get(cls)
            if not files or cls in classes:
                continue  # pas une classe du workspace (Flutter, plugin…) ; les clés sont vérifiées plus haut
            if not any(re.search(rf"\b{re.escape(member)}\b", read(p)) for p in files):
                ko(f"{cls}.{member}", f"✗ `{cls}.{member}` : {cls} existe ({os.path.relpath(sorted(files)[0], workspace)}) mais pas de membre {member}")

    # --- archi.json --------------------------------------------------------------------------------
    if archi_path != "-" and os.path.isfile(archi_path):
        titles = set(t.strip() for t in re.findall(r"(?m)^\s*Scenario(?: Outline)?:\s*(.+)$", section(spec, 4)))
        try:
            seqs = json.load(open(archi_path, encoding="utf-8")).get("sequences") or []
        except (OSError, ValueError):
            seqs = []
            problems.append("✗ archi.json illisible")
        for s in seqs:
            if s.get("scenario") and s["scenario"].strip() not in titles:
                ko(s["scenario"], f"✗ archi.json : {s.get('id')} pointe vers « {s['scenario']} », absent des scénarios de §4")

    # --- taille --------------------------------------------------------------------------------------
    size = len(spec.encode("utf-8"))
    if cap and size > cap:
        problems.append(f"✗ spec de {size} octets, plafond du gabarit {cap} : coupe ce qui répète les contrats ou le cadrage")

    for p in problems:
        print(p)
    print(f"spec_lint : {len(problems)} problème(s) — {len(keys_files)} fichier(s) de clés, {len(index)} symboles indexés, {size} octets")
    return 1 if problems else 0


if __name__ == "__main__":
    if len(sys.argv) != 6:
        sys.exit(__doc__)
    sys.exit(main(*sys.argv[1:5], int(sys.argv[5])))
