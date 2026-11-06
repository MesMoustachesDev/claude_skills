#!/usr/bin/env python3
"""reports.py — lit les rapports XML de Gradle pour les checks Android du gauntlet (stacks/android/checks*.sh).

  reports.py junit <dossier de résultats> <dossier du package> <dossier de test>…
      une ligne JSON par test : {file, name, result, skipped}, `file` relatif au package (le fichier source de la
      classe de test, retrouvé par son paquet et son nom), comme test_results de Flutter.
  reports.py coverage <rapport JaCoCo ou Kover XML> <dossier du package> <dossier source>…
      « chemin relatif au package:ligne 0|1 » pour chaque ligne instrumentée (1 = au moins une instruction couverte).
  reports.py lint <lint-results.xml> <dossier du package>
      « chemin:ligne:sévérité:id: message » des issues Android lint (Warning, Error, Fatal), chemins relatifs au package.
  reports.py checkstyle <rapport.xml> <dossier du package>
      « chemin:ligne:sévérité:règle: message » (detekt, format checkstyle).
  reports.py pitest <mutations.xml> <dossier du package> <dossier source>…
      « chemin:ligne statut mutateur description » par mutant (pitest, outputFormats XML).

Les chemins hors du package sont gardés absolus : le check les ignore (hors périmètre).
"""
import glob
import json
import os
import sys
import xml.etree.ElementTree as ET


def rel(path, pkg):
    path = path[7:] if path.startswith("file://") else path
    # /var/… et /private/var/… sur macOS : le rapport et le gauntlet ne nomment pas toujours le dossier pareil.
    for cand in (path, os.path.realpath(path)):
        for p in (pkg, os.path.realpath(pkg)):
            if cand.startswith(p.rstrip("/") + "/"):
                return cand[len(p.rstrip("/")) + 1:]
    return path


def source_index(pkg, dirs):
    """{(paquet, nom de fichier sans extension) : chemin relatif}, lu sur la ligne `package` de chaque source."""
    idx = {}
    for d in dirs:
        for f in glob.glob(os.path.join(pkg, d, "**", "*.kt"), recursive=True) + \
                glob.glob(os.path.join(pkg, d, "**", "*.java"), recursive=True):
            name = os.path.splitext(os.path.basename(f))[0]
            pk = ""
            try:
                with open(f, encoding="utf-8", errors="replace") as fh:
                    for line in fh:
                        s = line.strip()
                        if s.startswith("package "):
                            pk = s[8:].strip().rstrip(";").split()[0]
                            break
            except OSError:
                continue
            idx.setdefault((pk, name), os.path.relpath(f, pkg))
            idx.setdefault(("*", name), os.path.relpath(f, pkg))
    return idx


def junit(results, pkg, dirs):
    idx = source_index(pkg, dirs)
    for x in sorted(glob.glob(os.path.join(results, "**", "TEST-*.xml"), recursive=True)):
        try:
            root = ET.parse(x).getroot()
        except ET.ParseError:
            continue
        for tc in root.iter("testcase"):
            cls = tc.get("classname", "")
            outer = cls.split("$")[0]
            pk, _, name = outer.rpartition(".")
            f = idx.get((pk, name)) or idx.get(("*", name)) or cls
            if tc.find("failure") is not None:
                result = "failure"
            elif tc.find("error") is not None:
                result = "error"
            else:
                result = "success"
            print(json.dumps({"file": f, "name": tc.get("name", ""), "result": result,
                              "skipped": tc.find("skipped") is not None}, ensure_ascii=False))


def coverage(report, pkg, dirs):
    idx = source_index(pkg, dirs)
    root = ET.parse(report).getroot()
    for p in root.iter("package"):
        pk = (p.get("name") or "").replace("/", ".")
        for sf in p.findall("sourcefile"):
            name = os.path.splitext(sf.get("name", ""))[0]
            f = idx.get((pk, name)) or os.path.join((p.get("name") or ""), sf.get("name", ""))
            for ln in sf.findall("line"):
                print(f"{f}:{ln.get('nr')} {1 if int(ln.get('ci', '0')) > 0 else 0}")


def lint(report, pkg):
    root = ET.parse(report).getroot()
    for issue in root.iter("issue"):
        sev = issue.get("severity", "")
        if sev not in ("Warning", "Error", "Fatal"):
            continue
        for loc in issue.findall("location")[:1]:
            msg = " ".join((issue.get("message") or "").split())
            print(f"{rel(loc.get('file', '?'), pkg)}:{loc.get('line', '0')}:{sev}:{issue.get('id', '')}: {msg}")


def checkstyle(report, pkg):
    root = ET.parse(report).getroot()
    for f in root.iter("file"):
        path = rel(f.get("name", "?"), pkg)
        for e in f.findall("error"):
            msg = " ".join((e.get("message") or "").split())
            src = (e.get("source") or "").rsplit(".", 1)[-1]
            print(f"{path}:{e.get('line', '0')}:{e.get('severity', '')}:{src}: {msg}")


def pitest(report, pkg, dirs):
    idx = source_index(pkg, dirs)
    root = ET.parse(report).getroot()
    for m in root.iter("mutation"):
        cls = (m.findtext("mutatedClass") or "").split("$")[0]
        pk = cls.rpartition(".")[0]
        src = os.path.splitext(m.findtext("sourceFile") or "")[0]
        f = idx.get((pk, src)) or idx.get(("*", src)) or (m.findtext("sourceFile") or "?")
        mut = (m.findtext("mutator") or "").rsplit(".", 1)[-1]
        desc = " ".join((m.findtext("description") or "").split())
        print(f"{f}:{m.findtext('lineNumber') or '0'} {m.get('status', '?')} {mut} {desc}")


def main(argv):
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    cmd, a, b, rest = argv[0], argv[1], argv[2], argv[3:]
    if cmd == "junit":
        junit(a, b, rest)
    elif cmd == "coverage":
        coverage(a, b, rest)
    elif cmd == "lint":
        lint(a, b)
    elif cmd == "checkstyle":
        checkstyle(a, b)
    elif cmd == "pitest":
        pitest(a, b, rest)
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
