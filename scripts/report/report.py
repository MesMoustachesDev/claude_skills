#!/usr/bin/env python3
"""report.py — rapport HTML lu par le dev aux arrêts des pipelines /feature et /fix.

Usage :
  report.py feature <nom> [étape]   → .claude/features/<nom>/report.html
  report.py fix <nom> [étape]       → .claude/fixes/<nom>/report.html

Étapes feature : spec | contracts | tests | mutants | qa | evidence (section ouverte en premier).
Étapes fix     : repro | review | ui | evidence.

Aucun LLM : le rapport est assemblé à partir des fichiers que le pipeline produit déjà (spec.md,
pipeline.json, tests.md, repro.json, diagnosis.md, review.json…) et du code du package. Les blocs
Markdown et Mermaid sont rendus côté navigateur (marked + mermaid via CDN). Imprime le chemin écrit.
Si .claude/features/<nom>/archi.json existe (écrit par Sophie), la section Architecture est la vue
interactive d'archi.js / archi.css : résumé, décisions ↔ carte ↔ parcours ↔ fichiers, plan vs code.
"""
from __future__ import annotations

import glob
import html
import json
import os
import re
import subprocess
import sys
from datetime import datetime

MARKED = "https://cdnjs.cloudflare.com/ajax/libs/marked/12.0.2/marked.min.js"
MERMAID = "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"
LAYERS = ["presentation", "domain", "data", "injection"]


# --- utilitaires ---------------------------------------------------------------------------------

def sh(*args: str, cwd: str | None = None) -> str:
    try:
        return subprocess.run(args, cwd=cwd, capture_output=True, text=True, check=False).stdout
    except OSError:
        return ""


def read(path: str) -> str | None:
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def read_json(path: str) -> dict | None:
    txt = read(path)
    if txt is None:
        return None
    try:
        return json.loads(txt)
    except json.JSONDecodeError:
        return None


def esc(s: object) -> str:
    return html.escape(str(s if s is not None else ""))


def mm_label(s: str) -> str:
    """Texte sûr dans un label Mermaid entre guillemets."""
    return s.replace('"', "'").replace("<", "‹").replace(">", "›").replace("\n", "<br/>")


def mm_id(s: str) -> str:
    return "n_" + re.sub(r"[^A-Za-z0-9_]", "_", s)


class Page:
    """Accumule les sections ; chaque bloc Markdown est stocké brut et rendu par marked."""

    def __init__(self, title: str, focus: str | None):
        self.title = title
        self.focus = focus
        self.also_open: list[str] = []  # sections ouvertes et remontées juste après le focus
        self.sections: list[tuple[str, str, str, str]] = []  # (id, titre, badge, html)
        self.md_blocks: list[str] = []

    def md(self, text: str | None) -> str:
        if not text:
            return '<p class="muted">absent</p>'
        idx = len(self.md_blocks)
        self.md_blocks.append(text)
        return f'<div class="md" data-md="{idx}"></div>'

    def add(self, sid: str, title: str, body: str, badge: str = "") -> None:
        self.sections.append((sid, title, badge, body))

    def render(self, header: str) -> str:
        rank = lambda sid: 0 if sid == self.focus else 1 + self.also_open.index(sid) if sid in self.also_open \
            else 1 + len(self.also_open)
        order = sorted(self.sections, key=lambda s: rank(s[0]))
        opened = {self.focus, *self.also_open}
        nav = "".join(f'<a href="#{sid}">{esc(t)}</a>' for sid, t, _, _ in order)
        secs = "".join(
            f'<details id="{sid}" class="sec{" focus" if sid == self.focus else ""}"'
            f'{" open" if sid in opened or self.focus is None else ""}>'
            f'<summary><h2>{esc(t)}</h2>{b}</summary><div class="body">{body}</div></details>'
            for sid, t, b, body in order
        )
        blocks = "".join(
            f'<script type="text/markdown" id="md-{i}">' + t.replace("</", "<\\/") + "</script>"
            for i, t in enumerate(self.md_blocks)
        )
        return TEMPLATE.format(title=esc(self.title), header=header, nav=nav, sections=secs,
                               blocks=blocks, marked=MARKED, mermaid=MERMAID,
                               archi_css=asset("archi.css"), archi_js=asset("archi.js").replace("</script", "<\\/script"))


def asset(name: str) -> str:
    return read(os.path.join(os.path.dirname(os.path.abspath(__file__)), name)) or ""


def badge(text: str, kind: str = "") -> str:
    return f'<span class="badge {kind}">{esc(text)}</span>'


def status_kind(v: object) -> str:
    s = str(v).upper()
    if s in ("PASSED", "TRUE", "OK", "YES", "GREEN", "VALIDÉE", "VALIDEE"):
        return "ok"
    if s in ("FAILED", "FALSE", "KO", "NO", "RED"):
        return "ko"
    return "warn"


def table(headers: list[str], rows: list[list[str]], raw: bool = False) -> str:
    if not rows:
        return '<p class="muted">aucun</p>'
    th = "".join(f"<th>{esc(h)}</th>" for h in headers)
    tr = "".join("<tr>" + "".join(f"<td>{c if raw else esc(c)}</td>" for c in r) + "</tr>" for r in rows)
    return f'<div class="tw"><table><thead><tr>{th}</tr></thead><tbody>{tr}</tbody></table></div>'


def timeline(state: dict | None) -> str:
    if not state:
        return ""
    chips = []
    for k, v in (state.get("stages") or {}).items():
        val = v.get("status", v) if isinstance(v, dict) else v
        chips.append(f'<span class="chip {status_kind(val)}">{esc(k)}</span>')
    for k in (state.get("human_gates") or {}):
        chips.append(f'<span class="chip human">✔ {esc(k)}</span>')
    return f'<div class="timeline">{"".join(chips)}</div>' if chips else ""


def gauntlet_results(out_dir: str) -> str:
    rows = []
    for p in sorted(glob.glob(os.path.join(out_dir, "last_*.json"))):
        j = read_json(p) or {}
        ok = j.get("ok")
        rows.append([badge("vert" if ok else "rouge", "ok" if ok else "ko"), esc(j.get("profile", "")),
                     esc(j.get("date", "")), esc(" ".join(j.get("failed") or []))])
    return table(["", "profil", "date", "checks en échec"], rows, raw=True)


def images(base_dir: str, pattern: str, caption_from_dir: bool = True) -> str:
    files = sorted(glob.glob(os.path.join(base_dir, pattern)))
    if not files:
        return ""
    cells = []
    for f in files:
        rel = os.path.relpath(f, base_dir)
        cap = rel if caption_from_dir else os.path.basename(f)
        cells.append(f'<figure><a href="{esc(rel)}"><img src="{esc(rel)}" loading="lazy"></a>'
                     f'<figcaption>{esc(cap)}</figcaption></figure>')
    return f'<div class="gallery">{"".join(cells)}</div>'


def diff_block(diff: str) -> str:
    if not diff.strip():
        return '<p class="muted">aucun diff</p>'
    lines = []
    for ln in diff.splitlines():
        cls = "add" if ln.startswith("+") and not ln.startswith("+++") else \
              "del" if ln.startswith("-") and not ln.startswith("---") else \
              "hunk" if ln.startswith("@@") else ""
        lines.append(f'<span class="{cls}">{esc(ln)}</span>')
    return f'<pre class="diff">{chr(10).join(lines)}</pre>'


def layer_of(path: str) -> str:
    for l in LAYERS:
        if f"/{l}/" in f"/{path}":
            return l
    parts = path.split("/")
    return parts[-2] if len(parts) > 1 else "racine"


# --- spec ----------------------------------------------------------------------------------------

def spec_sections(spec: str) -> dict[str, str]:
    """{'1': '...', '8': '...'} — sections '## N. Titre' de la spec."""
    out: dict[str, str] = {}
    cur = None
    buf: list[str] = []
    for ln in spec.splitlines():
        m = re.match(r"^##\s+(\d+)\.", ln)
        if m:
            if cur:
                out[cur] = "\n".join(buf).strip()
            cur, buf = m.group(1), [ln]
        elif cur:
            buf.append(ln)
    if cur:
        out[cur] = "\n".join(buf).strip()
    return out


def parse_md_table(md: str) -> tuple[list[str], list[list[str]]]:
    rows = [l.strip() for l in md.splitlines() if l.strip().startswith("|")]
    rows = [r for r in rows if not re.match(r"^\|[\s:|-]+\|$", r)]
    if not rows:
        return [], []
    split = lambda r: [c.strip() for c in r.strip("|").split("|")]
    return split(rows[0]), [split(r) for r in rows[1:] if any(c.strip() for c in split(r))]


def decisions_html(sec9: str | None) -> str:
    if not sec9:
        return '<p class="muted">§9 absente</p>'
    head, rows = parse_md_table(sec9)
    if not rows:
        return '<p class="muted">aucune décision</p>'
    h = [c.lower() for c in head]

    def col(row: list[str], *names: str) -> str:
        for n in names:
            for i, c in enumerate(h):
                if n in c and i < len(row):
                    return row[i]
        return ""

    cards = []
    for r in rows:
        st = col(r, "statut") or "—"
        kind = "ok" if "valid" in st.lower() else "human" if "modif" in st.lower() else "warn"
        cards.append(
            f'<div class="decision {kind}"><div class="dh"><b>{esc(col(r, "id"))}</b> '
            f'<span class="dt">{esc(col(r, "sujet", "domaine"))}</span>{badge(st, kind)}</div>'
            f'<div class="dp"><span class="lbl">Proposé</span>{esc(col(r, "décision", "decision", "choix"))}</div>'
            f'<div class="da"><span class="lbl">Alternative</span>{esc(col(r, "alternative"))}</div>'
            f'<div class="dr"><span class="lbl">Raison</span>{esc(col(r, "raison"))}</div></div>')
    return f'<div class="decisions">{"".join(cards)}</div>'


GHERKIN_STEP = re.compile(r"^(Given|When|Then|And|But|\*)\s+(.*)$")


def parse_gherkin(text: str) -> dict:
    """{background: [(mot-clé, texte)], scenarios: [{title, outline, steps, examples}]} — §4 ou un .feature."""
    out: dict = {"background": [], "scenarios": []}
    cur = None
    for raw in text.splitlines():
        ln = raw.strip()
        if not ln or ln.startswith(("#", "@", "```", "Feature:")):
            continue
        if ln.startswith("Background:"):
            cur = {"steps": out["background"]}
            continue
        m = re.match(r"^Scenario( Outline)?:\s*(.*)$", ln)
        if m:
            cur = {"title": m.group(2).strip(), "outline": bool(m.group(1)), "steps": [], "examples": []}
            out["scenarios"].append(cur)
            continue
        if cur is None:
            continue
        if ln.startswith("Examples:"):
            cur["in_examples"] = True
            continue
        if ln.startswith("|") and cur.get("in_examples"):
            cur["examples"].append([c.strip() for c in ln.strip("|").split("|")])
            continue
        m = GHERKIN_STEP.match(ln)
        if m:
            cur["steps"].append((m.group(1), m.group(2)))
    return out


def spec_scenarios(spec: str) -> list[str]:
    return [m.strip() for m in re.findall(r"^\s*Scenario(?: Outline)?:\s*(.+)$", spec, re.M)]


def spec_class_names(sec5: str | None) -> set[str]:
    if not sec5:
        return set()
    names = set()
    for block in re.findall(r"```dart\n(.*?)```", sec5, re.S):
        names |= set(re.findall(r"\bclass\s+(\w+)", block))
    return {n for n in names if "{" not in n}


# --- code Dart -----------------------------------------------------------------------------------

CLASS_RE = re.compile(
    r"^\s*((?:abstract|sealed|final|base|interface|mixin)\s+)*class\s+(\w+)(?:<[^{]*?>)?"
    r"(?:\s+extends\s+(\w+)(?:<[^{]*?>)?)?(?:\s+with\s+[\w\s,<>]+?)?"
    r"(?:\s+implements\s+([\w\s,<>]+?))?\s*\{", re.M)
FIELD_RE = re.compile(r"^\s*(?:final|late final|late)\s+([A-Z]\w*)(?:<[^;=]*>)?\??\s+_?\w+\s*;", re.M)
PROVIDER_RE = re.compile(r"^final\s+(_?\w+Provider)\b\s*=", re.M)
TEST_RE = re.compile(r"\b(test|testWidgets|blocTest(?:<[^>]*>)?|group)\(\s*\n?\s*(['\"])(.+?)\2", re.S)


def scan_package(root: str, pkg_rel: str, scope: set[str] | None) -> dict:
    pkg = os.path.join(root, pkg_rel)
    classes: dict[str, dict] = {}
    providers: list[tuple[str, str]] = []
    for path in sorted(glob.glob(os.path.join(pkg, "lib", "**", "*.dart"), recursive=True)):
        if path.endswith((".g.dart", ".freezed.dart")):
            continue
        rel = os.path.relpath(path, root)
        src = read(path) or ""
        is_new = scope is None or rel in scope
        for m in CLASS_RE.finditer(src):
            mods, name, ext, impl = m.group(1) or "", m.group(2), m.group(3), m.group(4)
            classes[name] = {
                "file": rel, "layer": layer_of(os.path.relpath(path, pkg)), "abstract": bool(
                    re.search(r"abstract|interface|sealed", mods)), "sealed": "sealed" in mods,
                "extends": ext, "implements": [re.sub(r"<.*", "", i).strip() for i in (impl or "").split(",") if i.strip()],
                "fields": set(FIELD_RE.findall(src[m.end():_class_end(src, m.end())])), "new": is_new}
        for p in PROVIDER_RE.findall(src):
            providers.append((p, os.path.relpath(path, pkg)))
    return {"classes": classes, "providers": providers}


def _class_end(src: str, start: int) -> int:
    depth = 1
    i = start
    while i < len(src) and depth:
        depth += {"{": 1, "}": -1}.get(src[i], 0)
        i += 1
    return i


def arch_mermaid(scan: dict) -> str:
    cls = scan["classes"]
    sealed = {n for n, c in cls.items() if c["sealed"]}
    # Les sous-classes d'un sealed (events, states) sont repliées dans le parent.
    sub_count: dict[str, int] = {}
    shown = {}
    for n, c in cls.items():
        if n.startswith("_"):
            continue
        if c["extends"] in sealed:
            sub_count[c["extends"]] = sub_count.get(c["extends"], 0) + 1
        else:
            shown[n] = c
    if not shown:
        return ""
    lines = ["flowchart LR"]
    for layer in LAYERS + sorted({c["layer"] for c in shown.values()} - set(LAYERS)):
        members = [n for n, c in shown.items() if c["layer"] == layer]
        if not members:
            continue
        lines.append(f'  subgraph {mm_id("L_" + layer)}["{layer}"]')
        for n in members:
            c = shown[n]
            label = f"«interface»\n{n}" if c["abstract"] and not c["sealed"] else n
            if n in sub_count:
                label += f"\n+{sub_count[n]} variantes"
            lines.append(f'    {mm_id(n)}["{mm_label(label)}"]')
            lines.append(f'    class {mm_id(n)} {"fresh" if c["new"] else "old"}')
        lines.append("  end")
    for n, c in shown.items():
        for i in c["implements"]:
            if i in shown:
                lines.append(f"  {mm_id(n)} -.->|implements| {mm_id(i)}")
        if c["extends"] in shown and c["extends"] not in sealed:
            lines.append(f"  {mm_id(n)} -.->|extends| {mm_id(c['extends'])}")
        for f in sorted(c["fields"]):
            if f in shown and f != n:
                lines.append(f"  {mm_id(n)} --> {mm_id(f)}")
    lines.append("  classDef fresh fill:#dbeafe,stroke:#2563eb,color:#0b1d3a")
    lines.append("  classDef old fill:#f3f4f6,stroke:#9ca3af,color:#4b5563,stroke-dasharray:3 3")
    return "\n".join(lines)


def path_deps(root: str, pkg_rel: str) -> list[str]:
    txt = read(os.path.join(root, pkg_rel, "pubspec.yaml")) or ""
    m = re.search(r"^dependencies:\n((?:[ \t].*\n|\n)*)", txt, re.M)
    if not m:
        return []
    return re.findall(r"^  (\w+):\s*\n\s+path:", m.group(1), re.M)


def hosted_deps(root: str, pkg_rel: str) -> list[str]:
    txt = read(os.path.join(root, pkg_rel, "pubspec.yaml")) or ""
    m = re.search(r"^dependencies:\n((?:[ \t].*\n|\n)*)", txt, re.M)
    if not m:
        return []
    return re.findall(r"^  (\w+):\s*['\"]?[\^~>=<\d]", m.group(1), re.M)


def test_inventory(root: str, pkg_rel: str) -> tuple[list[list[str]], list[str]]:
    rows = []
    scenarios = []
    for path in sorted(glob.glob(os.path.join(root, pkg_rel, "test", "**", "*"), recursive=True)):
        if path.endswith(".feature"):
            scenarios += spec_scenarios(read(path) or "")
        if not path.endswith("_test.dart"):
            continue
        src = read(path) or ""
        names = [m.group(3) for m in TEST_RE.finditer(src) if m.group(1) != "group"]
        rel = os.path.relpath(path, os.path.join(root, pkg_rel, "test"))
        rows.append([rel, str(len(names)), "".join(f"<li>{esc(n)}</li>" for n in names[:40])
                     + ("<li>…</li>" if len(names) > 40 else "")])
    return rows, scenarios


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s.strip().lower())


# --- archi.json : vue interactive de l'architecture ----------------------------------------------

ARCHI_LAYERS = ("presentation", "domain", "data", "injection", "external")
CONTRACT_SUFFIX = re.compile(r"(Page|Bloc|Cubit|UseCase|Repository|RepositoryImpl|DataSource|DataSourceImpl|"
                             r"Entity|DataModel|Mapper)$")


def decisions_rows(sec9: str | None) -> list[dict]:
    head, rows = parse_md_table(sec9 or "")
    h = [c.lower() for c in head]

    def col(row: list[str], *names: str) -> str:
        for n in names:
            for i, c in enumerate(h):
                if n in c and i < len(row):
                    return row[i]
        return ""

    return [{"id": col(r, "id"), "subject": col(r, "sujet", "domaine"),
             "proposed": col(r, "décision", "decision", "choix"), "alternative": col(r, "alternative"),
             "reason": col(r, "raison"), "status": col(r, "statut") or "—"} for r in rows]


def changed_files(root: str, base: str) -> list[dict]:
    """Fichiers touchés par la branche (commits + working tree + non suivis), hors .claude/."""
    mb = sh("git", "merge-base", base, "HEAD", cwd=root).strip() or base
    out: dict[str, str] = {}
    for ln in sh("git", "diff", "--name-status", "-M", mb, cwd=root).splitlines():
        parts = ln.split("\t")
        if len(parts) < 2:
            continue
        code, path = parts[0][0], parts[-1]
        out[path] = {"A": "new", "D": "deleted", "R": "new"}.get(code, "modified")
    for path in sh("git", "ls-files", "--others", "--exclude-standard", cwd=root).split("\n"):
        if path:
            out[path] = "new"
    return [{"path": p, "status": s} for p, s in sorted(out.items()) if not p.startswith(".claude/")]


def archi_payload(archi: dict, decisions: list[dict], sec4: str | None, sec5: str | None, root: str, state: dict,
                  scan: dict | None) -> dict:
    nodes = archi.get("nodes") or []
    ids = {n.get("id") for n in nodes}
    alt_ids = {a.get("id") for d in (archi.get("decisions") or {}).values()
               for a in ((d or {}).get("alternative") or {}).get("add") or []}
    warnings = []
    for n in nodes:
        if n.get("layer") not in ARCHI_LAYERS:
            warnings.append(f"{n.get('id')} : layer « {n.get('layer')} » inconnu ({', '.join(ARCHI_LAYERS)})")
        if n.get("status") in ("new", "modified") and not n.get("file"):
            warnings.append(f"{n.get('id')} : statut {n.get('status')} sans « file »")
    for e in archi.get("edges") or []:
        for k in ("from", "to"):
            if e.get(k) not in ids:
                warnings.append(f"arête {e.get('from')} → {e.get('to')} : {e.get(k)} n'est pas un nœud")
    for f in archi.get("flows") or []:
        for s in f.get("steps") or []:
            for k in ("from", "to"):
                if s.get(k) != "user" and s.get(k) not in ids:
                    warnings.append(f"parcours « {f.get('title')} » : {s.get(k)} n'est pas un nœud")
    anchored = {d for n in nodes for d in n.get("decisions") or []}
    anchored |= {d for f in archi.get("files") or [] for d in f.get("decisions") or []}
    anchored |= {s.get("decision") for f in archi.get("flows") or [] for s in f.get("steps") or []}
    anchored |= set((archi.get("decisions") or {}).keys())
    for d in decisions:
        if d["id"] and d["id"] not in anchored:
            warnings.append(f"{d['id']} ({d['subject']}) n'est rattachée à aucun nœud, fichier ou étape")
    titles = {norm(sc["title"]) for sc in parse_gherkin(sec4 or "")["scenarios"]}
    for p in archi.get("scenarios") or []:
        if norm(p.get("title", "")) not in titles:
            warnings.append(f"scénario « {p.get('title')} » : titre absent de §4")
        if p.get("kind") not in ("nominal", "limite", "erreur"):
            warnings.append(f"scénario « {p.get('title')} » : kind « {p.get('kind')} » inconnu (nominal, limite, erreur)")
    contracts = {c for c in spec_class_names(sec5) if CONTRACT_SUFFIX.search(c)}
    for c in sorted(contracts - ids - alt_ids):
        warnings.append(f"{c} est un contrat de §5 absent de la carte")

    planned = {}
    for n in nodes:
        if n.get("file") and n.get("status") in ("new", "modified"):
            planned[n["file"]] = {"path": n["file"], "status": n["status"], "node": n["id"],
                                  "decisions": n.get("decisions") or [], "why": n.get("note", "")}
    for f in archi.get("files") or []:
        planned.setdefault(f.get("path"), {**f, "decisions": f.get("decisions") or []})

    real = None
    files_real = changed_files(root, state.get("base") or "HEAD")
    if scan is not None or files_real:
        real = {"files": files_real, "present": [], "unplanned": [], "edges": []}
        if scan is not None:
            cls = scan["classes"]
            sealed = {k for k, v in cls.items() if v["sealed"]}
            real["present"] = sorted(n for n in ids if n in cls)
            extra = [k for k, v in cls.items() if v["new"] and k not in ids and not k.startswith("_")
                     and v["extends"] not in sealed and v["layer"] in ("presentation", "domain", "data", "injection")]
            real["unplanned"] = [{"id": k, "layer": cls[k]["layer"], "file": cls[k]["file"],
                                  "kind": "interface" if cls[k]["abstract"] and not cls[k]["sealed"] else ""}
                                 for k in sorted(extra)]
            known = ids | set(extra)
            for k in extra:
                c = cls[k]
                for t in sorted(c["fields"]) + c["implements"]:
                    if t in known and t != k:
                        real["edges"].append({"from": k, "to": t,
                                              "kind": "implements" if t in c["implements"] else ""})
    return {"archi": archi, "decisions": decisions, "planned_files": list(planned.values()),
            "real": real, "warnings": warnings}


SC_KINDS = (("nominal", "Parcours nominaux", "ok"), ("limite", "Cas limites", "warn"), ("erreur", "Erreurs", "ko"))


def gherkin_steps_html(steps: list) -> str:
    def fmt(t: str) -> str:
        return re.sub(r"(&quot;.*?&quot;|&#x27;.*?&#x27;|\{[^}]*\}|&lt;[^&]*&gt;)", r"<code>\1</code>", esc(t))
    return "".join(f'<div class="gk"><span class="kw">{esc(k)}</span> {fmt(t)}</div>' for k, t in steps)


def scenarios_section(sec4: str | None, picks: list | None, covered: set | None) -> tuple[str, str]:
    """(html, badge) — scénarios §4 : les représentatifs choisis dans archi.json, puis tous, repliés."""
    g = parse_gherkin(sec4 or "")
    scen = g["scenarios"]
    if not scen:
        return '<p class="muted">aucun scénario en §4</p>', badge("0 scénario", "ko")
    by_title = {norm(s["title"]): s for s in scen}

    def cov(title: str) -> str:
        if covered is None:
            return ""
        return badge("dans un .feature", "ok") if norm(title) in covered else badge("absent des .feature", "ko")

    def body(s: dict) -> str:
        ex = ""
        if s["examples"]:
            ex = table(s["examples"][0], s["examples"][1:])
        return gherkin_steps_html(s["steps"]) + ex

    out = []
    if g["background"]:
        out.append('<p class="hint">Contexte commun à tous les scénarios :</p>'
                   f'<div class="sc-bg">{gherkin_steps_html(g["background"])}</div>')
    picked = {}
    for p in picks or []:
        s = by_title.get(norm(p.get("title", "")))
        if s:
            picked[norm(s["title"])] = p
    if picked:
        out.append('<p class="hint">Une sélection représentative, résumée en français. Tous les scénarios sont plus bas.</p>')
        for kind, label, k in SC_KINDS:
            items = [(p, by_title[t]) for t, p in picked.items() if p.get("kind") == kind]
            if not items:
                continue
            cards = "".join(
                f'<div class="sc-card {k}"><div class="sc-fr">{esc(p.get("fr", ""))}</div>'
                f'<div class="sc-title">{esc(s["title"])} {cov(s["title"])}</div>{body(s)}</div>'
                for p, s in items)
            out.append(f'<h3>{label} <span class="badge {k}">{len(items)}</span></h3><div class="sc-grid">{cards}</div>')
    kinds = {kind: (label, k) for kind, label, k in SC_KINDS}

    def kind_badge(title: str) -> str:
        kind = (picked.get(norm(title)) or {}).get("kind")
        return " " + badge(*kinds[kind]) if kind in kinds else ""

    rows = "".join(f'<details class="sc-row"><summary>{esc(s["title"])}{kind_badge(s["title"])} {cov(s["title"])}'
                   f'</summary>{body(s)}</details>' for s in scen)
    out.append(f"<details class='sub'{'' if picked else ' open'}><summary><h3>Tous les scénarios ({len(scen)})</h3></summary>{rows}</details>")
    missing = 0 if covered is None else sum(1 for s in scen if norm(s["title"]) not in covered)
    b = badge(f"{len(scen)} scénarios", "") + (badge(f"{missing} sans .feature", "ko") if missing else "")
    return "".join(out), b


def archi_section(payload: dict, stage: str | None) -> str:
    data = json.dumps({**payload, "stage": stage or ""}, ensure_ascii=False).replace("</", "<\\/")
    return (f'<script type="application/json" id="archi-data">{data}</script>'
            '<div id="archi-app"><p class="muted">chargement…</p></div>')


# --- feature -------------------------------------------------------------------------------------

def feature_report(root: str, name: str, focus: str | None) -> str:
    fdir = os.path.join(root, ".claude", "features", name)
    state = read_json(os.path.join(fdir, "pipeline.json")) or {}
    pkg_rel = (state.get("package") or f"features/{name}").rstrip("/")
    mode = state.get("mode", "create")
    spec = read(os.path.join(fdir, "spec.md")) or ""
    secs = spec_sections(spec)
    archi = read_json(os.path.join(fdir, "archi.json"))
    page = Page(f"{name} · feature", {"spec": "archi", "contracts": "archi" if archi else "real", "tests": "tests",
                                      "mutants": "mutants", "qa": "qa", "evidence": "archi"}.get(focus or "", focus))

    scan = None
    if os.path.isdir(os.path.join(root, pkg_rel, "lib")):
        scope = None
        if mode == "extend":
            base = state.get("base") or "HEAD"
            mb = sh("git", "merge-base", base, "HEAD", cwd=root).strip() or base
            scope = set(sh("git", "diff", "--name-only", mb, "--", pkg_rel, cwd=root).split()) | \
                set(sh("git", "ls-files", "--others", "--exclude-standard", "--", pkg_rel, cwd=root).split())
        scan = scan_package(root, pkg_rel, scope)

    # Architecture proposée / validée
    n_dec = len(parse_md_table(secs.get("9", ""))[1])
    if archi:
        payload = archi_payload(archi, decisions_rows(secs.get("9")), secs.get("4"), secs.get("5"), root, state, scan)
        page.add("archi", "Architecture",
                 archi_section(payload, focus)
                 + "<details class='sub'><summary><h3>§8 en détail (dépendances, routes, l10n, machines d'états)</h3>"
                 "</summary>" + page.md(secs.get("8")) + "</details>",
                 badge(f"{n_dec} décisions") + (badge(f"{len(payload['warnings'])} incohérence(s)", "ko")
                                               if payload["warnings"] else ""))
    else:
        page.add("archi", "Architecture : décisions",
                 '<p class="hint">Chaque ligne de §9 est une décision que tu valides ou modifies. '
                 "Statut <i>proposée</i> = pas encore tranchée par toi. (Pas d'archi.json : vue simple.)</p>"
                 + decisions_html(secs.get("9")) + "<h3>§8 Architecture (proposée par le specifier)</h3>"
                 + page.md(secs.get("8")),
                 badge(f"{n_dec} décisions"))

    # Scénarios d'acceptation : ce qui sera testé, lisible avant la spec entière
    feat_scen = test_inventory(root, pkg_rel)[1] if scan is not None else []
    sc_html, sc_badge = scenarios_section(secs.get("4"), (archi or {}).get("scenarios"),
                                          {norm(x) for x in feat_scen} if feat_scen else None)
    page.add("scenarios", "Scénarios : ce qui sera testé", sc_html, sc_badge)
    if focus in ("spec", "tests"):
        page.also_open.append("scenarios")

    # Architecture réelle (après le scaffold de l'architect)
    if scan is not None:
        diagram = "" if archi else arch_mermaid(scan)
        in_code = set(scan["classes"])
        expected = spec_class_names(secs.get("5"))
        missing = sorted(expected - in_code)
        extra = sorted(n for n, c in scan["classes"].items()
                       if c["new"] and n not in expected and not n.startswith("_") and c["layer"] in ("domain", "presentation")
                       and not c["extends"] in {k for k, v in scan["classes"].items() if v["sealed"]})
        sec8 = secs.get("8", "")
        deps = path_deps(root, pkg_rel)
        hosted = hosted_deps(root, pkg_rel)
        undeclared = [d for d in deps + hosted if d not in sec8 and d not in ("flutter",)]
        gaps = []
        if missing:
            gaps.append(f"<li>{badge('spec → code', 'ko')} prévus en §5, absents du code : {esc(', '.join(missing))}</li>")
        if undeclared:
            gaps.append(f"<li>{badge('dépendances', 'ko')} dans pubspec, non nommées en §8 : {esc(', '.join(undeclared))}</li>")
        if extra:
            gaps.append(f"<li>{badge('hors spec', 'warn')} classes domain/presentation non nommées en §5 : {esc(', '.join(extra))}</li>")
        gap_html = (f'<ul class="gaps">{"".join(gaps)}</ul>' if gaps
                    else f'<p>{badge("aucun écart détecté avec la spec", "ok")}</p>')
        legend = ("" if archi else
                  '<p class="hint">Généré depuis le code de <code>' + esc(pkg_rel) + "</code>. "
                  "Bleu : ajouté par cette feature. Gris pointillé : existant. Flèche pleine : dépendance "
                  "injectée (champ). Pointillée : implements/extends. Events/states repliés dans leur sealed.</p>")
        prov = table(["provider", "fichier"], [[p, f] for p, f in scan["providers"]])
        page.add("real", "Code scaffoldé : écarts, dépendances, providers" if archi else "Architecture réelle (code)",
                 gap_html + legend + (f'<pre class="mermaid">{esc(diagram)}</pre>' if diagram else "")
                 + "<h3>Dépendances du package</h3>"
                 + table(["type", "packages"], [["workspace (path)", ", ".join(deps) or "—"],
                                                ["hébergées (pub.dev)", ", ".join(hosted) or "—"]])
                 + "<h3>Providers</h3>" + prov,
                 badge(f"{len(gaps)} écart(s)", "ko" if gaps else "ok"))

        # Tests
        rows, feat_scen = test_inventory(root, pkg_rel)
        scen = spec_scenarios(secs.get("4", ""))
        have = {norm(s) for s in feat_scen}
        matrix = [[esc(s), badge("dans un .feature", "ok") if norm(s) in have else badge("absent", "ko")]
                  for s in scen]
        total = sum(int(r[1]) for r in rows)
        page.add("tests", "Tests",
                 "<h3>Scénarios d'acceptation (spec §4) × .feature</h3>"
                 + table(["scénario", "couverture"], matrix, raw=True)
                 + f"<h3>Tests unitaires et widget ({total})</h3>"
                 + "".join(f'<div class="tfile"><code>{esc(r[0])}</code> {badge(r[1])}<ul>{r[2]}</ul></div>'
                           for r in rows)
                 + "<h3>tests.md</h3>" + page.md(read(os.path.join(fdir, "tests.md")))
                 + "<h3>Revue des tests</h3>" + page.md(read(os.path.join(fdir, "tests_review.md"))),
                 badge(f"{len(scen)} scénarios · {total} tests"))

    # Spec (le reste)
    rest = "\n\n".join(v for k, v in sorted(secs.items(), key=lambda kv: int(kv[0])) if k not in ("8", "9"))
    page.add("spec", "Spec (fonctionnel, contrats, données, erreurs)", page.md(rest or spec or None))

    for sid, title, fname in (("review", "Revue", "review.md"), ("mutants", "Mutants", "mutants.md")):
        txt = read(os.path.join(fdir, fname))
        if txt:
            page.add(sid, title, page.md(txt))
    qa = read(os.path.join(fdir, "qa.md"))
    if qa:
        page.add("qa", "QA device", page.md(qa) + images(fdir, "qa/*/*.png"))
    page.add("gauntlet", "Gauntlet", gauntlet_results(os.path.join(fdir, ".gauntlet")))

    header = (f"<h1>{esc(name)}</h1><p class='meta'>feature · mode {esc(mode)} · <code>{esc(pkg_rel)}</code>"
              f" · base {esc(state.get('base', '?'))} · étape <b>{esc(focus or '—')}</b> · "
              f"{datetime.now():%Y-%m-%d %H:%M}</p>{timeline(state)}")
    out = os.path.join(fdir, "report.html")
    with open(out, "w", encoding="utf-8") as f:
        f.write(page.render(header))
    return out


# --- fix -----------------------------------------------------------------------------------------

def fix_report(root: str, name: str, focus: str | None) -> str:
    fdir = os.path.join(root, ".claude", "fixes", name)
    state = read_json(os.path.join(fdir, "fix.json")) or {}
    repro = read_json(os.path.join(fdir, "repro.json")) or {}
    plan = repro.get("fix_plan") or {}
    page = Page(f"{name} · fix", {"repro": "plan", "review": "real", "ui": "shots",
                                  "evidence": "plan"}.get(focus or "", focus))

    # Cause + plan
    loc = repro.get("root_cause_location", "?")
    planned = plan.get("files") or []
    diag = ["flowchart LR"]
    diag.append(f'  cause["{mm_label("Cause racine\n" + loc)}"]:::ko')
    for i, f in enumerate(planned):
        diag.append(f'  f{i}["{mm_label(layer_of(f) + "\n" + f)}"]:::plan')
        diag.append(f"  cause --> f{i}")
    diag += ["  classDef ko fill:#fee2e2,stroke:#dc2626,color:#450a0a",
             "  classDef plan fill:#dbeafe,stroke:#2563eb,color:#0b1d3a"]
    facts = table(["", ""], [
        ["Cause racine", esc(repro.get("root_cause"))],
        ["Emplacement", f"<code>{esc(loc)}</code>"],
        ["Raté par les tests", esc(repro.get("miss_reason"))],
        ["Type de test", esc(repro.get("kind"))],
        ["Échec attendu", f"<code>{esc(repro.get('expected_failure'))}</code>"],
        ["Suite avant le fix", badge(repro.get("baseline_suite", "?"), status_kind(repro.get("baseline_suite")))],
    ], raw=True)
    plan_html = (table(["", ""], [
        ["Couche visée", esc(plan.get("layer"))],
        ["Approche", esc(plan.get("approach"))],
        ["Fichiers prévus", "<br>".join(f"<code>{esc(f)}</code>" for f in planned) or "—"],
        ["Alternative écartée", esc(plan.get("rejected"))],
        ["Hors périmètre volontaire", esc(plan.get("out_of_scope", "—"))],
    ], raw=True) + (f'<pre class="mermaid">{esc(chr(10).join(diag))}</pre>' if planned else "")
        if plan else f'<p>{badge("repro.json sans fix_plan", "ko")}</p>')
    page.add("plan", "Diagnostic et plan de correction",
             facts + "<h3>Plan de correction (à valider)</h3>" + plan_html,
             badge(plan.get("layer", "plan ?"), "warn" if plan else "ko"))

    # Test rouge
    base_sha = state.get("base_sha")
    tdiff = sh("git", "diff", base_sha, "--", *repro.get("test_files", []), cwd=root) if base_sha else ""
    if not tdiff.strip() and repro.get("test_files"):
        tdiff = sh("git", "diff", "--no-index", "/dev/null", *repro["test_files"][:1], cwd=root)
    target_out = read(os.path.join(fdir, ".gauntlet", "target.out")) or ""
    exp = repro.get("expected_failure", "")
    hits = [l for l in target_out.splitlines() if exp and exp in l][:3]
    page.add("test", "Test de reproduction",
             (f"<p>Ligne d'échec relevée : <code>{esc(hits[0])}</code></p>" if hits else "")
             + diff_block(tdiff), badge(f"{len(repro.get('test_files', []))} fichier(s)"))

    # Réel vs plan (après correction)
    freeze = state.get("freeze_sha")
    if freeze:
        changed = [f for f in sh("git", "diff", "--name-only", freeze, cwd=root).split()
                   if not f.startswith(".claude/")]
        changed += [f for f in sh("git", "ls-files", "--others", "--exclude-standard", cwd=root).split()
                    if not f.startswith(".claude/")]
        changed = sorted(set(changed))
        accepted = {f for d in state.get("plan_deviations") or [] for f in d.get("files") or []}
        rows = []
        for f in changed:
            lbl, k = ("prévu", "ok") if f in planned else ("écart accepté", "human") if f in accepted \
                else ("non prévu", "ko")
            rows.append([badge(lbl, k), esc(layer_of(f)), f"<code>{esc(f)}</code>"])
        for f in planned:
            if f not in changed:
                rows.append([badge("prévu, non touché", "warn"), esc(layer_of(f)), f"<code>{esc(f)}</code>"])
        review = read_json(os.path.join(fdir, "review.json")) or {}
        crit = [[esc(c.get("file")), esc(c.get("line")), esc(c.get("rule")), esc(c.get("summary")),
                 badge("accepté", "warn") if c.get("accepted") else ""] for c in review.get("critical", [])]
        out_of_plan = sum(1 for r in rows if "non prévu" in r[0])
        page.add("real", "Correction vs plan",
                 table(["", "couche", "fichier"], rows, raw=True)
                 + (f"<p>Plan respecté selon le reviewer : {badge(review.get('plan_respected', '?'), status_kind(review.get('plan_respected')))}"
                    f" · cause traitée : {badge(review.get('root_cause_addressed', '?'), status_kind(review.get('root_cause_addressed')))}</p>"
                    if review else "")
                 + "<h3>Critiques</h3>" + table(["fichier", "ligne", "règle", "constat", ""], crit, raw=True)
                 + "<h3>Diff de correction</h3>" + diff_block(sh("git", "diff", freeze, "--", ".", ":!.claude", cwd=root)),
                 badge(f"{out_of_plan} non prévu(s)", "ko" if out_of_plan else "ok"))

    shots = images(fdir, "shots/*/*.png")
    if shots:
        page.add("shots", "Captures (red | green)", shots)
    page.add("diagnosis", "diagnosis.md", page.md(read(os.path.join(fdir, "diagnosis.md"))))
    rv = read(os.path.join(fdir, "review.md"))
    if rv:
        page.add("review", "review.md", page.md(rv))
    page.add("gauntlet", "Gauntlet", gauntlet_results(os.path.join(fdir, ".gauntlet")))

    header = (f"<h1>{esc(name)}</h1><p class='meta'>fix · <code>{esc(repro.get('package', '?'))}</code> · "
              f"base {esc((base_sha or '?')[:8])} · gel {esc((freeze or '—')[:8])} · étape <b>{esc(focus or '—')}</b> · "
              f"{datetime.now():%Y-%m-%d %H:%M}</p>{timeline(state)}")
    out = os.path.join(fdir, "report.html")
    with open(out, "w", encoding="utf-8") as f:
        f.write(page.render(header))
    return out


# --- gabarit -------------------------------------------------------------------------------------

TEMPLATE = """<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title>
<style>
:root {{ --bg:#fafaf9; --fg:#1c1917; --muted:#78716c; --card:#fff; --line:#e7e5e4; --accent:#2563eb;
  --ok:#15803d; --ok-bg:#dcfce7; --ko:#b91c1c; --ko-bg:#fee2e2; --warn:#a16207; --warn-bg:#fef9c3;
  --human:#6d28d9; --human-bg:#ede9fe; --code:#f5f5f4; }}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{ --bg:#0c0a09; --fg:#e7e5e4;
  --muted:#a8a29e; --card:#1c1917; --line:#292524; --accent:#60a5fa; --ok:#4ade80; --ok-bg:#052e16;
  --ko:#f87171; --ko-bg:#450a0a; --warn:#facc15; --warn-bg:#422006; --human:#c4b5fd; --human-bg:#2e1065; --code:#292524; }} }}
* {{ box-sizing:border-box; }}
body {{ margin:0; background:var(--bg); color:var(--fg); font:15px/1.55 -apple-system,BlinkMacSystemFont,"Inter",system-ui,sans-serif; }}
main {{ max-width:1100px; margin:0 auto; padding:24px 16px 80px; }}
h1 {{ margin:0 0 4px; font-size:26px; }} h2 {{ display:inline; font-size:18px; margin:0; }} h3 {{ font-size:15px; margin:22px 0 8px; }}
.meta {{ color:var(--muted); margin:0 0 12px; }}
code {{ overflow-wrap:anywhere; background:var(--code); padding:1px 5px; border-radius:4px; font-size:13px; }}
nav {{ position:sticky; top:0; background:var(--bg); padding:8px 0; display:flex; gap:12px; flex-wrap:wrap; border-bottom:1px solid var(--line); z-index:2; }}
nav a {{ color:var(--accent); text-decoration:none; font-size:14px; }}
.sec {{ background:var(--card); border:1px solid var(--line); border-radius:10px; margin:16px 0; }}
.sec.focus {{ border-color:var(--accent); box-shadow:0 0 0 2px color-mix(in srgb, var(--accent) 25%, transparent); }}
summary {{ cursor:pointer; padding:14px 18px; display:flex; gap:10px; align-items:center; list-style:none; }}
summary::-webkit-details-marker {{ display:none; }}
.body {{ padding:0 18px 18px; overflow-x:auto; }}
.badge,.chip {{ display:inline-block; font-size:12px; padding:2px 8px; border-radius:999px; background:var(--code); color:var(--muted); white-space:nowrap; }}
.ok {{ --b:var(--ok-bg); --c:var(--ok); }} .ko {{ --b:var(--ko-bg); --c:var(--ko); }} .warn {{ --b:var(--warn-bg); --c:var(--warn); }} .human {{ --b:var(--human-bg); --c:var(--human); }}
.badge.ok,.badge.ko,.badge.warn,.badge.human,.chip.ok,.chip.ko,.chip.warn,.chip.human {{ background:var(--b); color:var(--c); }}
.timeline {{ display:flex; gap:6px; flex-wrap:wrap; }}
.hint {{ color:var(--muted); font-size:13px; }} .muted {{ color:var(--muted); }}
.tw {{ overflow-x:auto; }} table {{ border-collapse:collapse; width:100%; font-size:14px; }}
th,td {{ text-align:left; vertical-align:top; padding:6px 10px; border-bottom:1px solid var(--line); }}
th {{ color:var(--muted); font-weight:600; }}
.decisions {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(300px,1fr)); gap:12px; }}
.decision {{ border:1px solid var(--line); border-left:4px solid var(--c); border-radius:8px; padding:10px 12px; }}
.decision .dh {{ display:flex; gap:8px; align-items:center; margin-bottom:6px; }} .decision .dt {{ flex:1; color:var(--muted); }}
.decision div {{ margin:3px 0; }} .lbl {{ display:inline-block; min-width:88px; color:var(--muted); font-size:12px; text-transform:uppercase; letter-spacing:.03em; }}
.tfile {{ margin:10px 0; }} .tfile ul {{ margin:4px 0 0; padding-left:20px; font-size:14px; }}
.gaps {{ padding-left:18px; }} .gaps li {{ margin:4px 0; }}
pre {{ background:var(--code); padding:12px; border-radius:8px; overflow-x:auto; font-size:13px; }}
pre.mermaid {{ background:#fff; text-align:center; overflow:auto; max-height:80vh; }}
{archi_css}
pre.diff span {{ display:block; }} pre.diff .add {{ background:var(--ok-bg); color:var(--ok); }} pre.diff .del {{ background:var(--ko-bg); color:var(--ko); }} pre.diff .hunk {{ color:var(--accent); }}
.gallery {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(180px,1fr)); gap:10px; }}
.gallery img {{ width:100%; border-radius:6px; border:1px solid var(--line); }} figcaption {{ font-size:12px; color:var(--muted); }}
details.sub {{ margin-top:18px; border-top:1px solid var(--line); }} details.sub > summary {{ padding:10px 0; }}
.md table {{ margin:8px 0; }} .md blockquote {{ border-left:3px solid var(--line); margin:0; padding-left:12px; color:var(--muted); }}
</style></head><body><main>
{header}
<nav>{nav}</nav>
{sections}
</main>
{blocks}
<script src="{marked}"></script>
<script src="{mermaid}"></script>
<script>{archi_js}</script>
<script>
(function () {{
  const renderer = {{ code(code, lang) {{
    const c = typeof code === 'object' ? code.text : code; const l = typeof code === 'object' ? code.lang : lang;
    const e = c.replace(/&/g,'&amp;').replace(/</g,'&lt;');
    return l === 'mermaid' ? '<pre class="mermaid">' + e + '</pre>' : '<pre><code>' + e + '</code></pre>';
  }} }};
  if (window.marked) {{
    marked.use({{ renderer, gfm: true }});
    document.querySelectorAll('[data-md]').forEach(el => {{
      const src = document.getElementById('md-' + el.dataset.md).textContent;
      el.innerHTML = marked.parse(src.replace(/<!--[\\s\\S]*?-->/g, ''));
    }});
  }} else {{
    document.querySelectorAll('[data-md]').forEach(el => {{
      const pre = document.createElement('pre'); pre.textContent = document.getElementById('md-' + el.dataset.md).textContent; el.appendChild(pre);
    }});
  }}
  if (window.mermaid) {{
    mermaid.initialize({{ startOnLoad: false, theme: 'default', securityLevel: 'strict', flowchart: {{ htmlLabels: true, useMaxWidth: false }} }});
    const run = () => mermaid.run({{ querySelector: 'details[open] pre.mermaid:not([data-processed])' }});
    run(); document.querySelectorAll('details').forEach(d => d.addEventListener('toggle', run));
  }}
}})();
</script>
</body></html>
"""


def main() -> int:
    if len(sys.argv) < 3 or sys.argv[1] not in ("feature", "fix"):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    kind, name = sys.argv[1], sys.argv[2]
    focus = sys.argv[3] if len(sys.argv) > 3 else None
    root = sh("git", "rev-parse", "--show-toplevel").strip()
    if not root:
        print("pas dans un repo git", file=sys.stderr)
        return 1
    d = os.path.join(root, ".claude", "features" if kind == "feature" else "fixes", name)
    if not os.path.isdir(d):
        print(f"inconnu : {d}", file=sys.stderr)
        return 1
    print(feature_report(root, name, focus) if kind == "feature" else fix_report(root, name, focus))
    return 0


if __name__ == "__main__":
    sys.exit(main())
