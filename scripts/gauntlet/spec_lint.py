#!/usr/bin/env python3
"""spec_lint.py — vérifications mécaniques de spec.md, avant la critique de Camille.

Usage : spec_lint.py <spec.md> <package> <racine du workspace> <archi.json ou -> <plafond en octets>

Ce qu'une relecture humaine trouve aussi, mais qu'un script trouve sans coût ni oubli (cas réel :
refactor_feature, 3 des 10 bloquants de la première critique) :
  - clés : chaque clé citée ('<préfixe>_x', <Name>Keys.x ou <Name>TestTags.x) existe dans le fichier de clés du
    package (keys.dart en Flutter, *TestTags.kt en Android) ;
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

# Extensions des sources du langage du package (stack.ini → extensions, passées par le gauntlet) ; défaut Dart.
EXTS = tuple(e.strip() for e in (os.environ.get("SPEC_LINT_EXT") or ".dart").split(",") if e.strip())
KOTLIN = any(e in (".kt", ".kts", ".java") for e in EXTS)
DECL = re.compile(r"^\s*(?:@\w+\s+)*(?:(?:abstract|sealed|final|base|interface|mixin)\s+)*"
                  r"(?:class|mixin|enum|typedef|extension(?:\s+type)?)\s+([A-Z]\w*)", re.M)
KT_DECL = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|internal|private|protected|data|sealed|abstract|"
                     r"open|enum|annotation|value|inline|inner|fun|expect|actual)\s+)*"
                     r"(?:class|interface|object|typealias)\s+([A-Z]\w*)", re.M)
# Types du SDK et des paquets d'erreur qu'une §5 cite sans qu'ils soient des contrats du workspace.
SDK_TYPES = {"Either", "Left", "Right", "Unit", "Option", "Some", "None", "Stream", "Future", "FutureOr", "List",
             "Map", "Set", "Iterable", "String", "Object", "Exception", "Error", "Duration", "DateTime", "Uri",
             "Uint8List", "Widget", "BuildContext", "Bloc", "Cubit", "Emitter", "Equatable", "StreamController",
             "StreamSubscription", "Completer", "Timer", "Function", "Record", "Null", "Never", "Type",
             # Kotlin, coroutines, Android
             "Result", "Any", "Nothing", "Int", "Long", "Boolean", "Double", "Float", "Throwable", "Pair", "Triple",
             "Flow", "StateFlow", "MutableStateFlow", "SharedFlow", "Job", "CoroutineScope", "Dispatchers", "Lazy",
             "Context", "Intent", "Activity", "Settings", "Composable", "Modifier", "ViewModel", "SavedStateHandle"}
# Generated files (feature_pipeline.md → generated.exclude), the regex the gauntlet exports.
GENERATED = re.compile(os.environ.get("GAUNTLET_GENERATED_ERE") or r"\.(g|freezed)\.dart$")
SKIP_DIRS = {".dart_tool", "build", ".git", "node_modules", "ios", "macos", "linux", "windows", "web"}
if not KOTLIN:
    SKIP_DIRS.add("android")  # le dossier natif d'une app Flutter ; dans un projet Android, c'est le code


def src_files(root):
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if x not in SKIP_DIRS and not x.startswith(".")]
        for f in files:
            if f.endswith(EXTS) and not GENERATED.search(os.path.join(d, f)):
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
    # Fichier de clés : keys.dart (Flutter, sous lib/) ou XxxTestTags.kt (Android, `object XxxTestTags`).
    if KOTLIN:
        keys_files = [p for p in src_files(pkg) if os.path.basename(p).endswith("TestTags.kt")]
        cls_re, entry_re = r"object\s+(\w*TestTags)\b", r"const\s+val\s+(\w+)\s*(?::\s*String\s*)?=\s*\"([^\"]*)\""
    else:
        keys_files = [p for p in src_files(os.path.join(pkg, "lib")) if re.search(r"(^|_)keys\.dart$", os.path.basename(p))]
        cls_re, entry_re = r"class\s+(\w*Keys)\b", r"static\s+const\s+(?:String\s+)?(\w+)\s*=\s*'([^']*)'"
    values, names, classes = set(), set(), set()
    for p in keys_files:
        src = read(p)
        classes |= set(re.findall(cls_re, src))
        for name, val in re.findall(entry_re, src):
            names.add(name)
            values.add(val)
    if values:
        prefix = os.path.commonprefix(sorted(values))
        prefix = prefix[: prefix.rfind("_") + 1] if "_" in prefix else ""
        if len(prefix) >= 4:
            for tok in sorted(set(re.findall(rf"['\"]({re.escape(prefix)}[a-z0-9_]*)['\"]", spec))):
                if tok in values or any(v.endswith("_") and tok.startswith(v) and tok[len(v):].isdigit() for v in values):
                    continue
                ko(tok, f"✗ clé '{tok}' citée par la spec, absente du fichier de clés du package — contrat à compléter (Thibault) ou clé mal écrite")
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
        for p in src_files(root):
            for name in (KT_DECL if p.endswith((".kt", ".kts", ".java")) else DECL).findall(read(p)):
                index.setdefault(name, set()).add(p)
    for tok in sorted(set(t for t in re.findall(r"`([A-Z]\w*)(?:<[^`]*>)?`", section(spec, 5)))):
        if tok not in index and tok not in SDK_TYPES:
            ko(tok, f"✗ §5 cite `{tok}`, introuvable dans le package et le workspace — renommé, ou pas encore écrit ?")
    for code in re.findall(r"`([^`\n]+)`", spec):
        for cls, member in re.findall(r"(?<![\w…])([A-Z]\w*)\.([a-z_]\w*)", code):
            if member in ("kt", "kts", "java", "dart") or cls in SDK_TYPES:
                continue  # `Fichier.kt` est un nom de fichier ; `Result.success`, un type du SDK même homonyme
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
