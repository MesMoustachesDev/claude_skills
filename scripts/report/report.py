#!/usr/bin/env python3
"""report.py — rapport HTML lu par le dev aux arrêts des pipelines /feature et /fix.

Usage :
  report.py feature <nom> [étape]   → .claude/features/<nom>/report.html
  report.py fix <nom> [étape]       → .claude/fixes/<nom>/report.html

Étapes feature : cadrage | contracts | spec | tests | tour | evidence (section ouverte en premier ;
                 mutants et qa restent acceptés et ouvrent la visite guidée quand elle existe).
Étapes fix     : repro | review | ui | evidence.

Aucun LLM : le rapport est assemblé à partir des fichiers que le pipeline produit déjà (spec.md,
pipeline.json, tests.md, repro.json, diagnosis.md, review.json…) et du code du package. Les blocs
Markdown et Mermaid sont rendus côté navigateur (marked + mermaid via CDN). Imprime le chemin écrit.
Pas de vue d'architecture : l'architecture est dans les contrats que le dev écrit lui-même. Le rapport
montre une séquence par scénario d'acceptation — celle du cadrage (cadrage.md, `### C<n>` + sequenceDiagram)
et, après les tests, la même redessinée depuis le test d'acceptation réel, avec les écarts — et, à la fin,
la visite guidée du code (review.json → tour) avec mutants, captures et suggestions rattachés à chaque étape.
archi.json ne sert plus qu'à relier chaque C<n> à son scénario de §4 (`sequences`).
"""
from __future__ import annotations

import glob
import html
import json
import os
import re
import subprocess
import unicodedata
import sys
from datetime import datetime

MARKED = "https://cdnjs.cloudflare.com/ajax/libs/marked/12.0.2/marked.min.js"
MERMAID = "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"
LAYERS = ["presentation", "domain", "data", "injection"]
FEATURE_STAGES = ("cadrage", "contracts", "spec", "tests", "tour", "evidence", "mutants", "qa")
FIX_STAGES = ("repro", "review", "ui", "evidence")


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
        if self.focus and self.focus not in {sid for sid, _, _, _ in self.sections}:
            raise ValueError(f"section « {self.focus} » absente du rapport : l'étape demandée n'a pas encore ses fichiers")
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
                               blocks=blocks, marked=MARKED, mermaid=MERMAID)


def badge(text: str, kind: str = "") -> str:
    return f'<span class="badge {kind}">{esc(text)}</span>'


def status_kind(v: object) -> str:
    s = str(v).upper()
    if s in ("PASSED", "TRUE", "OK", "YES", "GREEN", "VALIDÉE", "VALIDEE"):
        return "ok"
    if s in ("FAILED", "FALSE", "KO", "NO", "RED"):
        return "ko"
    if s == "SKIPPED":
        return "skip"
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
    if state.get("size"):
        chips.append(f'<span class="chip">gabarit {esc(state["size"])}</span>')
    for k, v in (state.get("stages") or {}).items():
        val = v.get("status", v) if isinstance(v, dict) else v
        kind = status_kind(val)
        if kind == "skip":
            reason = v.get("reason", "") if isinstance(v, dict) else ""
            chips.append(f'<span class="chip skip" title="{esc(reason)}">{esc(k)} · sautée</span>')
        else:
            chips.append(f'<span class="chip {kind}">{esc(k)}</span>')
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
    files = sorted(glob.glob(os.path.join(base_dir, pattern), recursive=True))
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
        lines.append(f'<span class="{cls}">{esc(ln) or " "}</span>')
    return f'<pre class="diff">{"".join(lines)}</pre>'


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
    """§9 : ce que les contrats ne montrent pas (package, dépendances), en table."""
    head, rows = parse_md_table(sec9 or "")
    if not rows:
        return '<p class="muted">aucune ligne en §9</p>'
    h = [c.lower() for c in head]

    def col(row: list[str], *names: str) -> str:
        for n in names:
            for i, c in enumerate(h):
                if n in c and i < len(row):
                    return row[i]
        return ""

    out = []
    for r in rows:
        st = col(r, "statut") or "—"
        kind = "ok" if "valid" in st.lower() else "human" if "modif" in st.lower() else "warn"
        out.append([esc(col(r, "id")), esc(col(r, "sujet", "domaine")), esc(col(r, "décision", "decision", "choix")),
                    esc(col(r, "alternative")), esc(col(r, "raison")), badge(st, kind)])
    return table(["ID", "Sujet", "Décision", "Alternative", "Raison", "Statut"], out, raw=True)


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


# --- code Dart -----------------------------------------------------------------------------------

TEST_RE = re.compile(r"\b(test|testWidgets|blocTest(?:<[^>]*>)?|group)\(\s*\n?\s*(['\"])(.+?)\2", re.S)


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


def norm(s: object) -> str:
    return re.sub(r"\s+", " ", str(s or "").strip().lower())


def scenario_key(title: object) -> str:
    """Titre normalisé d'un scénario, Outline compris : bdd_widget_test génère
    `Outline: <titre> (<exemple>)` pour chaque ligne d'Examples."""
    t = norm(title)
    if t.startswith("outline:"):
        t = re.sub(r"\s*\([^()]*\)$", "", t[len("outline:"):].strip())
    return t


def changed_files(root: str, base: str, *paths: str) -> list[dict]:
    """Fichiers touchés par la branche (commits + working tree + non suivis), hors .claude/."""
    mb = sh("git", "merge-base", base, "HEAD", cwd=root).strip() or base
    out: dict[str, str] = {}
    for ln in sh("git", "diff", "--name-status", "-M", mb, "--", *paths, cwd=root).splitlines():
        parts = ln.split("\t")
        if len(parts) < 2:
            continue
        code, path = parts[0][0], parts[-1]
        out[path] = {"A": "new", "D": "deleted", "R": "new"}.get(code, "modified")
    for path in sh("git", "ls-files", "--others", "--exclude-standard", "--", *paths, cwd=root).split("\n"):
        if path:
            out[path] = "new"
    return [{"path": p, "status": s} for p, s in sorted(out.items()) if not p.startswith(".claude/")]


def resolve(root: str, pkg_rel: str, path: str) -> str | None:
    """Chemin relatif à la racine d'un fichier cité relatif au package ou à la racine."""
    for cand in (os.path.join(pkg_rel, path), path):
        if os.path.isfile(os.path.join(root, cand)):
            return cand
    return None


def symbol_line(src: str, symbol: str) -> int | None:
    """Ligne (1-based) de la définition d'un symbole Dart (`Classe.methode`, `methode`, `Classe`)."""
    name = re.escape(symbol.split(".")[-1])
    owner = symbol.split(".")[0] if "." in symbol else None
    lines = src.splitlines()
    start = 0
    if owner:
        for i, ln in enumerate(lines):
            if re.search(rf"\b(class|mixin|extension)\s+{re.escape(owner)}\b", ln):
                start = i
                break
    for i in range(start, len(lines)):
        ln = lines[i].strip()
        if ln.startswith("//"):
            continue
        if re.search(rf"\b(class|mixin|enum|extension)\s+{name}\b", ln) or \
                (re.search(rf"\b{name}\s*(<[^>]*>)?\s*\(", ln) and not re.match(r"(return|await|if|final|var)\b", ln)
                 and not ln.rstrip().endswith(";")):
            return i + 1
    return None


def excerpt(root: str, rel: str, line: int, before: int = 1, after: int = 9) -> str:
    lines = (read(os.path.join(root, rel)) or "").splitlines()
    lo, hi = max(0, line - 1 - before), min(len(lines), line + after)
    return "\n".join(f"{i + 1:>4}  {lines[i]}" for i in range(lo, hi))


# --- scénarios -----------------------------------------------------------------------------------

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
        s = by_title.get(norm(p.get("title")))
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


# --- séquences : cadrage (comportement) ↔ test d'acceptation (réel) ------------------------------

SEQ_HEAD = re.compile(r"^#{2,4}\s+(C\d+)\b\s*[—:.\-–]*\s*(.*)$", re.M)
SEQ_MSG = re.compile(r"^\s*([\w]+)\s*(--?>>|--?x|--?\)|--?>)[+-]?\s*([\w]+)\s*:\s*(.*)$")
SEQ_PART = re.compile(r"^\s*(participant|actor)\s+(\w+)(?:\s+as\s+(.*))?$")
CADRAGE_ROLES = {"U": "Utilisateur", "E": "Écran", "A": "App"}   # tout autre id = serveur, stockage, plateforme


def cadrage_sequences(cadrage: str | None) -> list[dict]:
    """Les comportements C1…Cn de cadrage.md, chacun avec son sequenceDiagram Mermaid."""
    if not cadrage:
        return []
    heads = list(SEQ_HEAD.finditer(cadrage))
    out = []
    for i, h in enumerate(heads):
        body = cadrage[h.end(): heads[i + 1].start() if i + 1 < len(heads) else len(cadrage)]
        m = re.search(r"```mermaid\s*\n(.*?)```", body, re.S)
        if not m or "sequenceDiagram" not in m.group(1):
            continue
        mermaid = m.group(1).strip()
        steps = []
        for ln in mermaid.splitlines():
            mm = SEQ_MSG.match(ln)
            if not mm:
                continue
            a, b, msg = mm.group(1), mm.group(3), mm.group(4).strip()
            if a == "U" and b == "E":
                kind = "action"
            elif a == "E" and b == "U":
                kind = "visible"
            elif a not in CADRAGE_ROLES and b in CADRAGE_ROLES:
                kind = "response"
            elif a in CADRAGE_ROLES and b not in CADRAGE_ROLES:
                kind = "request"
            else:
                kind = "internal"
            steps.append({"from": a, "to": b, "msg": msg, "kind": kind, "n": len(steps) + 1})
        # un `;` ou un `#` dans un message coupe ou casse la ligne Mermaid
        safe = []
        for ln in mermaid.splitlines():
            mm = SEQ_MSG.match(ln)
            safe.append(f"  {mm.group(1)}{mm.group(2)}{mm.group(3)}: {seq_text(mm.group(4), 200)}" if mm else ln)
        out.append({"id": h.group(1), "title": h.group(2).strip(), "mermaid": "\n".join(safe), "steps": steps})
    return out


ACTION_RE = re.compile(r"\btester\.(tap|tapAt|longPress|enterText|drag|dragFrom|fling|press|sendKeyEvent|"
                       r"sendKeyDownEvent|showKeyboard|testTextInput)\b|\benterText\(")
RESPONSE_RE = re.compile(r"\bwhen\(|\.thenAnswer\(|\.thenReturn\(|\.thenThrow\(|\b\w*(?:[cC]ontroller|sink)\.add(?:Error)?\(|"
                         r"\bFake\w*\(|\bwhenListen\(")
ASSERT_RE = re.compile(r"\bexpect(?:Later)?\(")
FUNC_DEF = re.compile(r"^\s*(?:Future<void>|void|Future<\w+>)\s+(\w+)\s*\(", re.M)
STEP_CALL = re.compile(r"await\s+(\w+)\(\s*tester\b\s*(?:,\s*(.*?))?\s*,?\s*\);", re.S)
TEST_WIDGETS = re.compile(r"""testWidgets\(\s*('''|\"\"\"|'|")(.+?)\1\s*,\s*\(\s*tester\s*,?\s*\)\s*async\s*\{""", re.S)


def _dart_functions(paths: list[str]) -> dict[str, tuple[str, int, str, int]]:
    """{nom: (fichier, ligne de définition, corps, offset du corps dans le fichier)}."""
    out = {}
    for p in paths:
        src = read(p) or ""
        for m in FUNC_DEF.finditer(src):
            i = src.find("{", m.end())
            arrow = src.find("=>", m.end())
            if arrow != -1 and (i == -1 or arrow < i):
                start, end = arrow, src.find(";", arrow) + 1
            elif i != -1:
                start, end = i, _block_end(src, i + 1)
            else:
                continue
            out.setdefault(m.group(1), (p, src[:m.start()].count("\n") + 1, src[start:end], start))
    return out


def _relative_imports(path: str) -> list[str]:
    here = os.path.dirname(path)
    return [os.path.normpath(os.path.join(here, i))
            for i in re.findall(r"^import\s+'(\.{1,2}/[^']+)';", read(path) or "", re.M)]


def _block_end(src: str, start: int) -> int:
    depth = 1
    i = start
    while i < len(src) and depth:
        depth += {"{": 1, "}": -1}.get(src[i], 0)
        i += 1
    return i


def _step_kind(kw: str, prev: str, full: str) -> str:
    """Nature d'un step : son mot-clé Gherkin (And/But héritent du précédent), précisé par son corps —
    un tap dans un Given reste une action, un faux configuré dans un When reste une réponse."""
    k = kw if kw in ("Given", "When", "Then") else prev
    if k == "Then":
        return "assert"
    if ACTION_RE.search(full):
        return "action"
    if RESPONSE_RE.search(full):
        return "response"
    if k == "When":
        return "action"
    if k == "Given":
        return "setup"
    return "assert" if ASSERT_RE.search(full) else "setup"


def test_sequences(root: str, pkg_rel: str) -> dict[str, dict]:
    """{titre normalisé: {title, file, steps, examples}} — séquence réelle de chaque scénario d'acceptation,
    lue dans le test généré par bdd_widget_test (un testWidgets par scénario → appels de steps) et le
    corps de chaque step (un niveau de helpers, importés compris)."""
    pkg = os.path.join(root, pkg_rel)
    test_dir = os.path.join(pkg, "test")
    feature_files = glob.glob(os.path.join(test_dir, "**", "*.feature"), recursive=True)
    feats = {}
    for f in feature_files:
        g = parse_gherkin(read(f) or "")
        for sc in g["scenarios"]:
            feats[scenario_key(sc["title"])] = g["background"] + sc["steps"]
    out: dict[str, dict] = {}
    # bdd_widget_test génère <x>_test.dart à côté de <x>.feature ; à défaut, tout test qui importe ./step/
    generated = [f[: -len(".feature")] + "_test.dart" for f in feature_files]
    candidates = [f for f in generated if os.path.isfile(f)] or [
        f for f in glob.glob(os.path.join(test_dir, "**", "*_test.dart"), recursive=True)
        if re.search(r"^import\s+'\./step/", read(f) or "", re.M)]
    for tf in candidates:
        src = read(tf) or ""
        if "testWidgets(" not in src:
            continue
        step_files = {*_relative_imports(tf), *glob.glob(os.path.join(os.path.dirname(tf), "step", "*.dart"))}
        step_files = {p for p in step_files if os.path.isfile(p)}
        helper_files = {h for p in step_files for h in _relative_imports(p) if os.path.isfile(h)}
        funcs = _dart_functions(sorted(step_files | helper_files))
        local = _dart_functions([tf])
        for m in TEST_WIDGETS.finditer(src):
            title = re.sub(r"\s+", " ", m.group(2)).strip()
            key = scenario_key(title)
            if key in out:                      # Outline : un testWidgets par ligne d'Examples
                out[key]["examples"] += 1
                continue
            body = src[m.end():_block_end(src, m.end())]
            calls = []
            for c in STEP_CALL.finditer(body):
                if c.group(1) in local and c.group(1) not in funcs:   # bddSetUp (Background) : on déplie
                    calls += [(d.group(1), d.group(2) or "") for d in STEP_CALL.finditer(local[c.group(1)][2])]
                else:
                    calls.append((c.group(1), c.group(2) or ""))
            texts = feats.get(key, [])
            steps = []
            prev = ""
            for i, (fn, args) in enumerate(calls):
                args = re.sub(r"\s+", " ", args).strip().rstrip(",")
                kw, text = texts[i] if len(texts) == len(calls) else ("", f"{fn}({args})")
                path, line, fbody, start = funcs.get(fn, (None, 0, "", 0))
                helpers = [funcs[h][2] for h in set(re.findall(r"\b(\w+)\(", fbody)) if h in funcs and h != fn]
                kind = _step_kind(kw, prev, fbody + "".join(helpers))
                prev = kw if kw in ("Given", "When", "Then") else prev
                at = line
                rx = {"action": ACTION_RE, "response": RESPONSE_RE, "assert": ASSERT_RE}.get(kind)
                hit = rx.search(fbody) if rx and path else None
                if hit:
                    at = (read(path) or "")[:start + hit.start()].count("\n") + 1
                steps.append({"kw": kw, "text": text, "fn": fn, "kind": kind,
                              "at": f"{os.path.relpath(path, pkg)}:{at}" if path else ""})
            out[key] = {"title": key if title.lower().startswith("outline:") else title,
                        "file": os.path.relpath(tf, pkg), "steps": steps, "examples": 1}
    return out


def seq_text(s: str, n: int = 80) -> str:
    """Texte sûr pour un message de sequenceDiagram."""
    s = re.sub(r"[;#]", lambda m: {";": ",", "#": "#35;"}[m.group(0)], s).replace("\n", " ").strip()
    return s if len(s) <= n else s[: n - 1] + "…"


def test_mermaid(seq: dict) -> str:
    kinds = {s["kind"] for s in seq["steps"]}
    lines = ["sequenceDiagram", "  actor T as Test (utilisateur simulé)", "  participant E as Écran (widget)"]
    if "response" in kinds:
        lines.append("  participant F as Faux repository / serveur")
    for s in seq["steps"]:
        txt = seq_text(s["text"], 56)
        if s["kind"] == "action":
            lines.append(f"  T->>E: {txt}")
        elif s["kind"] == "response":
            lines.append(f"  F-->>E: {txt}")
        elif s["kind"] == "assert":
            lines.append(f"  E-->>T: ✓ {txt}")
        else:
            lines.append(f"  T->>E: pump · {txt}")
    if len(lines) == 3:
        lines.append("  Note over T,E: aucun step trouvé")
    return "\n".join(lines)


def seq_gaps(cad: dict | None, test: dict | None) -> list[tuple[str, str]]:
    """Écarts (sens, texte) entre la séquence du cadrage et celle du test. Heuristique, à confirmer."""
    if cad is None or test is None:
        return []
    c = {k: [s for s in cad["steps"] if s["kind"] == k] for k in ("action", "request", "response", "visible")}
    t = {k: [s for s in test["steps"] if s["kind"] == k] for k in ("action", "response", "assert")}
    gaps = []
    for s in c["action"][len(t["action"]):]:
        gaps.append(("cadrage", f"action « {s['msg']} » (étape {s['n']}) : aucune action correspondante dans le test"))
    for s in t["action"][len(c["action"]):]:
        gaps.append(("test", f"action « {s['text']} » ({s['at']}) : absente du cadrage"))
    if c["response"] and not t["response"]:
        for s in c["response"]:
            gaps.append(("cadrage", f"réponse « {s['msg']} » (étape {s['n']}) : le test ne configure aucun faux repository / serveur"))
    elif t["response"] and not (c["response"] or c["request"]):
        for s in t["response"]:
            gaps.append(("test", f"réponse simulée « {s['text']} » ({s['at']}) : le cadrage ne parle d'aucun serveur"))
    if c["visible"] and not t["assert"]:
        gaps.append(("cadrage", f"{len(c['visible'])} résultat(s) visible(s) au cadrage, aucune assertion dans le test"))
    elif len(t["assert"]) < len(c["visible"]):
        for s in c["visible"][len(t["assert"]):]:
            gaps.append(("cadrage", f"résultat « {s['msg']} » (étape {s['n']}) : peut-être non vérifié "
                                    f"({len(c['visible'])} résultats, {len(t['assert'])} assertions)"))
    return gaps


def sequences_section(cad: list[dict], mapping: list[dict], tests: dict[str, dict] | None,
                      sec4: str | None) -> tuple[str, str]:
    """(html, badge) — un bloc par scénario d'acceptation : cadrage | test réel, écarts."""
    by_id = {str(m.get("id")): m for m in mapping if m.get("id")}
    titles = {scenario_key(s["title"]) for s in parse_gherkin(sec4 or "")["scenarios"]}
    warnings = []
    if mapping:
        for c in cad:
            if c["id"] not in by_id:
                warnings.append(f"{c['id']} : aucun scénario de §4 ne lui correspond (archi.json → sequences)")
        for m in mapping:
            if titles and scenario_key(m.get("scenario")) not in titles:
                warnings.append(f"{m.get('id')} : scénario « {m.get('scenario')} » absent de §4")
            if cad and str(m.get("id")) not in {c["id"] for c in cad}:
                warnings.append(f"{m.get('id')} : absent des séquences de cadrage.md")
    blocks = []
    n_gaps = 0
    items = [(c, by_id.get(c["id"])) for c in cad]
    if not cad:   # format antérieur : pas de séquence au cadrage, on montre au moins les tests
        items = [(None, m) for m in mapping]
    for c, m in items:
        title = (m or {}).get("scenario")
        t = (tests or {}).get(scenario_key(title)) if title and tests is not None else None
        gaps = seq_gaps(c, t)
        n_gaps += len(gaps)
        head = (f'<b>{esc(c["id"] if c else (m or {}).get("id", ""))}</b> {esc(c["title"] if c else "")}'
                + (f' {badge((m or {}).get("kind"), {"nominal": "ok", "limite": "warn", "erreur": "ko"}.get((m or {}).get("kind"), ""))}'
                   if (m or {}).get("kind") else ""))
        sub = (f'<div class="sc-fr">{esc(m.get("fr", ""))}</div>' if m and m.get("fr") else "") + \
              (f'<div class="sc-title">§4 : {esc(title)}</div>' if title else
               '<div class="hint">pas encore relié à un scénario de §4 (écrit avec la spec)</div>')
        left = (f'<div><div class="seq-h">Cadrage (comportement attendu)</div><pre class="mermaid">{esc(c["mermaid"])}</pre></div>'
                if c else '<div><div class="seq-h">Cadrage</div><p class="muted">pas de séquence au cadrage (format antérieur)</p></div>')
        if t:
            loc = "".join(f'<li><code>{esc(s["at"])}</code> {esc(s["kind"])} — {esc(s["text"])}</li>' for s in t["steps"])
            ex = f' {badge(str(t["examples"]) + " exemples")}' if t.get("examples", 1) > 1 else ""
            right = (f'<div><div class="seq-h">Test réel <code>{esc(t["file"])}</code>{ex}</div>'
                     f'<pre class="mermaid">{esc(test_mermaid(t))}</pre>'
                     f'<details class="sub"><summary>steps et fichiers</summary><ul class="loc">{loc}</ul></details></div>')
        elif tests is not None and title:
            right = '<div><div class="seq-h">Test réel</div>' + badge("aucun testWidgets pour ce scénario", "ko") + "</div>"
            n_gaps += 1
        else:
            right = ""
        g = ""
        if gaps:
            g = '<ul class="gaps">' + "".join(
                f'<li>{badge("au cadrage, pas au test" if side == "cadrage" else "au test, pas au cadrage", "ko" if side == "cadrage" else "warn")} {esc(txt)}</li>'
                for side, txt in gaps) + "</ul>"
        elif t and c:
            g = f'<p>{badge("aucun écart détecté", "ok")}</p>'
        blocks.append(f'<div class="seq-block"><div class="seq-head">{head}</div>{sub}'
                      f'<div class="seq-pair{" one" if not right else ""}">{left}{right}</div>{g}</div>')
    if not blocks:
        return '<p class="muted">aucune séquence (cadrage.md sans comportement C1…Cn)</p>', ""
    warn_html = ('<ul class="gaps">' + "".join(f'<li>{badge("incohérence", "ko")} {esc(w)}</li>' for w in warnings)
                 + "</ul>") if warnings else ""
    hint = ('<p class="hint">À gauche, le comportement validé au cadrage. À droite, le même scénario redessiné '
            "depuis le test d'acceptation réel (steps bdd_widget_test : pump, tap/saisie, réponse du faux, assertion). "
            "Les écarts sont détectés par script : à confirmer en lisant les deux.</p>") if tests is not None else ""
    b = badge(f"{len(blocks)} séquence(s)") + (badge(f"{n_gaps} écart(s)", "ko") if n_gaps else "") + \
        (badge(f"{len(warnings)} incohérence(s)", "ko") if warnings else "")
    return warn_html + hint + "".join(blocks), b


# --- contrats écrits par le dev -----------------------------------------------------------------

DECISION_MARK = "DÉCISION (Thibault)"


def contracts_section(root: str, pkg_rel: str, state: dict, fdir: str, page: "Page") -> tuple[str, str]:
    c = state.get("contracts") or {}
    draft, mine = c.get("draft_sha"), c.get("sha")
    out = []
    marks = []
    for p in sorted(glob.glob(os.path.join(root, pkg_rel, "lib", "**", "*.dart"), recursive=True)):
        for i, ln in enumerate((read(p) or "").splitlines(), 1):
            if DECISION_MARK in ln:
                marks.append([f"<code>{esc(os.path.relpath(p, root))}:{i}</code>", esc(ln.strip().lstrip("/ "))])
    if marks:
        out.append(f"<h3>Décisions encore ouvertes dans le code ({len(marks)})</h3>"
                   '<p class="hint">Chaque commentaire <code>' + esc(DECISION_MARK) + "</code> est une question d'Arthur : "
                   "garde, change, puis efface le commentaire.</p>" + table(["où", "question"], marks, raw=True))
    if c.get("files"):
        files = [str(f) for f in c["files"]]
    elif draft:
        files = sh("git", "diff", "--name-only", f"{draft}~1", draft, "--", pkg_rel, cwd=root).split()
    else:
        files = [f["path"] for f in changed_files(root, state.get("base") or "HEAD", pkg_rel)
                 if re.search(r"/domain/|keys\.dart$|_event\.dart$|_state\.dart$", f["path"])]
    if files:
        out.append("<h3>Fichiers de contrats</h3><ul class='loc'>" + "".join(f"<li><code>{esc(f)}</code></li>" for f in files) + "</ul>")
    if draft and mine:
        d = sh("git", "diff", draft, mine, "--", pkg_rel, cwd=root)
        out.append(f"<h3>Ce que tu as changé dans le brouillon d'Arthur</h3>"
                   f"<p class='hint'>{esc(draft[:8])} (brouillon) → {esc(mine[:8])} (contracts by Thibault)</p>" + diff_block(d))
    elif draft:
        d = sh("git", "diff", draft, "--", pkg_rel, cwd=root)
        out.append("<h3>Tes modifications en cours (non commitées)</h3>" + diff_block(d))
    deps, hosted = path_deps(root, pkg_rel), hosted_deps(root, pkg_rel)
    out.append("<h3>Dépendances du package</h3>" + table(["type", "packages"], [
        ["workspace (path)", ", ".join(deps) or "—"], ["hébergées (pub.dev)", ", ".join(hosted) or "—"]]))
    dd = read(os.path.join(fdir, "dedup.md"))
    if dd:
        out.append("<h3>Déjà existant ailleurs (Denis)</h3>" + page.md(dd))
    b = (badge(f"{len(marks)} décision(s) ouverte(s)", "ko") if marks else "") + \
        (badge("écrits par Thibault", "human") if mine else badge("brouillon", "warn") if draft else "")
    return "".join(out) or '<p class="muted">aucun contrat</p>', b


# --- visite guidée -------------------------------------------------------------------------------

def slug(s: object) -> str:
    t = unicodedata.normalize("NFKD", str(s or "")).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "_", t).strip("_")


def as_int(v: object, default: int = 1) -> int:
    try:
        return max(1, int(str(v).split(":")[-1]))
    except (TypeError, ValueError):
        return default


def mutants_rows(md: str | None) -> list[dict]:
    head, rows = parse_md_table(md or "")
    if not head:
        return []
    h = [c.lower() for c in head]
    idx = lambda *ns: next((i for i, c in enumerate(h) for n in ns if n in c), None)
    fi, mi, vi, ei = idx("fichier"), idx("mutation"), idx("verdict"), idx("explication")
    out = []
    for r in rows:
        loc = r[fi] if fi is not None and fi < len(r) else ""
        out.append({"loc": loc.strip("` "), "mutation": r[mi] if mi is not None and mi < len(r) else "",
                    "verdict": r[vi] if vi is not None and vi < len(r) else "",
                    "why": r[ei] if ei is not None and ei < len(r) else ""})
    return out


def tour_section(root: str, pkg_rel: str, fdir: str, state: dict, review: dict,
                 mapping: list[dict]) -> tuple[str, str]:
    tour = review.get("tour") or []
    if isinstance(tour, dict):
        tour = tour.get("steps") or list(tour.values())
    tour = [st for st in tour if isinstance(st, dict)] if isinstance(tour, list) else []
    if not tour:
        return '<p class="muted">pas de visite guidée (review.json → tour absent)</p>', badge("absente", "ko")
    c2s = {str(m.get("id")): m.get("scenario") for m in mapping}
    muts = mutants_rows(read(os.path.join(fdir, "mutants.md")))
    decided = state.get("suggestions") or {}
    # une suggestion reclassée en dette (hors diff) n'est ni à trancher ni « non appliquée »
    sugg = [x for x in review.get("suggestions") or [] if isinstance(x, dict)
            and (decided.get(str(x.get("id"))) or {}).get("decision") != "debt"]
    suspects = [x for x in state.get("suspect_tests") or [] if isinstance(x, dict)]
    shots = sorted(glob.glob(os.path.join(fdir, "qa", "**", "*.png"), recursive=True))
    used_m, used_s, used_p, used_t = set(), set(), set(), set()

    def same_file(a: object, b: object) -> bool:
        a, b = str(a or "").split(":")[0].strip("` "), str(b or "").split(":")[0].strip("` ")
        return bool(a and b) and (a.endswith(b) or b.endswith(a))

    steps_html = []
    for n, st in enumerate(tour, 1):
        st_file = str(st.get("file") or "")
        rel = resolve(root, pkg_rel, st_file) if st_file else None
        line = as_int(st.get("line"))
        moved = ""
        if rel and st.get("symbol"):
            found = symbol_line(read(os.path.join(root, rel)) or "", str(st["symbol"]))
            if found and found != line:
                moved = f" (ligne {line} au moment de la revue)"
                line = found
        where = f"{rel or st_file or '?'}:{line}"
        refs = []
        scen = []
        impl = st.get("implements") or []
        for r in [str(x) for x in (impl if isinstance(impl, list) else [impl])]:
            if r in c2s:
                refs.append(badge(f"{r} · {c2s[r]}", "ok"))
                scen.append(c2s[r])
            elif re.match(r"^[A-Z]\d+$", str(r)):
                refs.append(badge(r, "human"))
            else:
                refs.append(badge(r, "ok"))
                scen.append(r)
        att = []
        for i, m in enumerate(muts):
            if st_file and same_file(m["loc"], st_file):
                used_m.add(i)
                att.append(f'<li>{badge("mutant " + m["verdict"], "warn")} <code>{esc(m["loc"])}</code> {esc(m["mutation"])} — {esc(m["why"])}</li>')
        for i, s in enumerate(sugg):
            if st_file and same_file(s.get("file"), st_file):
                used_s.add(i)
                sid = str(s.get("id") or "S?")
                dec = str((decided.get(sid) or {}).get("decision", "à trancher"))
                att.append(f'<li>{badge(sid + " · " + dec, "ok" if dec == "applied" else "human")} '
                           f'{esc(s.get("summary", ""))} — {esc(s.get("problem", ""))}</li>')
        for j, x in enumerate(suspects):
            if st_file and same_file(x.get("file"), st_file):
                used_t.add(j)
                att.append(f'<li>{badge("test suspect · " + str(x.get("by") or "?"), "ko")} '
                           f'<code>{esc(x.get("file"))}:{esc(x.get("line"))}</code> {esc(x.get("why"))}</li>')
        pics = []
        for i, p in enumerate(shots):
            b = slug(os.path.basename(p))
            if any(slug(t)[:24] and slug(t)[:24] in b for t in scen):
                used_p.add(i)
                r = os.path.relpath(p, fdir)
                pics.append(f'<figure><a href="{esc(r)}"><img src="{esc(r)}" loading="lazy"></a><figcaption>{esc(r)}</figcaption></figure>')
        code = f'<pre class="code">{esc(excerpt(root, rel, line))}</pre>' if rel else badge("fichier introuvable", "ko")
        steps_html.append(
            f'<div class="tour-step"><div class="tour-h"><span class="tour-n">{n}</span> {badge(st.get("layer") or "", "")} '
            f'<code>{esc(where)}</code>{esc(moved)} {"".join(refs)}</div>'
            f'<p>{esc(st.get("what", ""))}</p>{code}'
            + (f'<ul class="att">{"".join(att)}</ul>' if att else "")
            + (f'<div class="gallery">{"".join(pics)}</div>' if pics else "") + "</div>")
    left = [f'<li>{badge("mutant " + m["verdict"], "warn")} <code>{esc(m["loc"])}</code> {esc(m["why"])}</li>'
            for i, m in enumerate(muts) if i not in used_m]
    left += [f'<li>{badge(str(s.get("id") or "S?"), "human")} <code>{esc(s.get("file"))}</code> {esc(s.get("summary"))}</li>'
             for i, s in enumerate(sugg) if i not in used_s]
    left += [f'<li>{badge("test suspect · " + str(x.get("by") or "?"), "ko")} <code>{esc(x.get("file"))}:{esc(x.get("line"))}</code> '
             f'{esc(x.get("why"))}</li>' for j, x in enumerate(suspects) if j not in used_t]
    rest_pics = [p for i, p in enumerate(shots) if i not in used_p]
    qa = read(os.path.join(fdir, "qa.md")) or ""
    ko = [l.strip() for l in qa.splitlines() if l.startswith("|") and "✗" in l]
    head = ""
    if ko:
        head = "<h3>Défauts signalés par Quentin</h3><ul class='gaps'>" + "".join(
            f"<li>{badge('✗', 'ko')} {esc(' · '.join(c.strip() for c in l.strip('|').split('|') if c.strip() not in ('', '—', '-')))}</li>"
            for l in ko) + "</ul>"
    tail = ""
    if left:
        tail += "<h3>Non rattachés à une étape</h3><ul class='att'>" + "".join(left) + "</ul>"
    if rest_pics:
        tail += "<h3>Autres captures</h3>" + images(fdir, "qa/**/*.png") if len(rest_pics) == len(shots) else \
            "<h3>Autres captures</h3><div class='gallery'>" + "".join(
                f'<figure><a href="{esc(os.path.relpath(p, fdir))}"><img src="{esc(os.path.relpath(p, fdir))}" loading="lazy"></a>'
                f'<figcaption>{esc(os.path.relpath(p, fdir))}</figcaption></figure>' for p in rest_pics) + "</div>"
    hint = ('<p class="hint">Dans l\'ordre du flux de données. Ouvre chaque fichier à la ligne indiquée dans ton IDE ; '
            "mutants, captures et suggestions sont rattachés à l'étape qu'ils concernent.</p>")
    b = badge(f"{len(tour)} étapes") + (badge(f"{len(ko)} défaut(s) QA", "ko") if ko else "")
    return head + hint + "".join(steps_html) + tail, b


# --- feature -------------------------------------------------------------------------------------

def feature_report(root: str, name: str, focus: str | None) -> str:
    fdir = os.path.join(root, ".claude", "features", name)
    state = read_json(os.path.join(fdir, "pipeline.json")) or {}
    pkg_rel = (state.get("package") or f"features/{name}").rstrip("/")
    mode = state.get("mode", "create")
    spec = read(os.path.join(fdir, "spec.md")) or ""
    secs = spec_sections(spec)
    archi = read_json(os.path.join(fdir, "archi.json")) or {}
    review = read_json(os.path.join(fdir, "review.json")) or {}
    cadrage = read(os.path.join(fdir, "cadrage.md"))
    has_tour = bool(review.get("tour"))
    first = {"cadrage": "cadrage", "contracts": "contracts", "spec": "scenarios", "tests": "sequences",
             "tour": "tour", "mutants": "tour" if has_tour else "mutants", "qa": "tour" if has_tour else "qa",
             "evidence": "tour" if has_tour else "scenarios"}
    page = Page(f"{name} · feature", first.get(focus or "", focus))
    has_code = os.path.isdir(os.path.join(root, pkg_rel, "lib"))
    has_tests = os.path.isdir(os.path.join(root, pkg_rel, "test")) and bool(state.get("tests_freeze_sha")
                                                                            or (state.get("stages") or {}).get("red"))

    # Cadrage : ce qui va être fait, avec une séquence par comportement
    if cadrage:
        page.add("cadrage", "Cadrage", page.md(cadrage))

    # Séquences : cadrage | test réel, côte à côte
    cad = cadrage_sequences(cadrage)
    mapping = [m for m in archi.get("sequences") or [] if isinstance(m, dict)] or [
        {"id": f"S{i}", "scenario": p.get("title"), "kind": p.get("kind"), "fr": p.get("fr")}
        for i, p in enumerate(archi.get("scenarios") or [], 1) if isinstance(p, dict)]
    # Acceptance scenarios may also live in other packages (pipeline.json → acceptance_packages)
    accept_pkgs = [pkg_rel] + [p for p in state.get("acceptance_packages") or [] if p != pkg_rel]
    tests = None
    if has_tests:
        tests = {}
        for ap in accept_pkgs:
            tests.update(test_sequences(root, ap))
    # au cadrage (pas encore de lien avec §4 ni de test), les séquences sont dans la section Cadrage
    if mapping or tests is not None:
        sq_html, sq_badge = sequences_section(cad, mapping, tests, secs.get("4"))
        page.add("sequences", "Séquences : cadrage ↔ tests d'acceptation" if tests is not None else "Séquences du cadrage",
                 sq_html, sq_badge)
        if focus in ("spec",):
            page.also_open.append("sequences")

    # Contrats : écrits par le dev dans le code
    if has_code and (state.get("contracts") or focus == "contracts"):
        ct_html, ct_badge = contracts_section(root, pkg_rel, state, fdir, page)
        page.add("contracts", "Contrats (dans le code)", ct_html, ct_badge)

    # Scénarios d'acceptation : ce qui sera testé
    inv_rows, feat_scen = test_inventory(root, pkg_rel) if has_code else ([], [])
    for ap in accept_pkgs[1:]:
        if has_code and os.path.isdir(os.path.join(root, ap, "test")):
            feat_scen = list(feat_scen) + list(test_inventory(root, ap)[1])
    picks = [{"title": m.get("scenario"), "kind": m.get("kind"), "fr": m.get("fr")} for m in mapping]
    sc_html, sc_badge = scenarios_section(secs.get("4"), picks, {norm(x) for x in feat_scen} if feat_scen else None)
    if secs.get("4"):
        page.add("scenarios", "Scénarios : ce qui sera testé", sc_html, sc_badge)
        if focus == "tests":
            page.also_open.append("scenarios")

    # §9 : ce que les contrats ne montrent pas (package, dépendances)
    if secs.get("9"):
        page.add("decisions", "Package et dépendances (§9)", decisions_html(secs.get("9")),
                 badge(f"{len(parse_md_table(secs['9'])[1])} ligne(s)"))
        if focus == "spec":
            page.also_open.append("decisions")

    # Visite guidée (après la QA)
    if has_tour or focus == "tour":
        t_html, t_badge = tour_section(root, pkg_rel, fdir, state, review, mapping)
        page.add("tour", "Visite guidée du code", t_html, t_badge)

    # Tests
    if has_code and os.path.isdir(os.path.join(root, pkg_rel, "test")):
        rows = inv_rows
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
    rest = "\n\n".join(v for k, v in sorted(secs.items(), key=lambda kv: int(kv[0])) if k != "9")
    if spec:
        page.add("spec", "Spec (fonctionnel, contrats, données, erreurs, §8)", page.md(rest or spec))

    for sid, title, fname in (("review", "Revue", "review.md"), ("mutants", "Mutants", "mutants.md")):
        txt = read(os.path.join(fdir, fname))
        if txt:
            page.add(sid, title, page.md(txt))
    qa = read(os.path.join(fdir, "qa.md"))
    if qa:
        page.add("qa", "QA device", page.md(qa) + images(fdir, "qa/**/*.png"))
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
.tfile {{ margin:10px 0; }} .tfile ul {{ margin:4px 0 0; padding-left:20px; font-size:14px; }}
.gaps {{ padding-left:18px; }} .gaps li {{ margin:4px 0; }}
pre {{ background:var(--code); padding:12px; border-radius:8px; overflow-x:auto; font-size:13px; }}
pre.mermaid {{ background:#fff; text-align:center; overflow:auto; max-height:80vh; }}
.seq-block {{ border:1px solid var(--line); border-radius:8px; padding:10px 12px; margin:12px 0; }}
.seq-head {{ display:flex; gap:8px; align-items:center; flex-wrap:wrap; }} .seq-h {{ font-size:12px; color:var(--muted); text-transform:uppercase; letter-spacing:.03em; margin:8px 0 4px; }}
.seq-pair {{ display:grid; grid-template-columns:1fr 1fr; gap:12px; }} .seq-pair.one {{ grid-template-columns:1fr; }}
@media (max-width:760px) {{ .seq-pair {{ grid-template-columns:1fr; }} }}
.sc-grid {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(320px,1fr)); gap:10px; }}
.sc-card {{ border:1px solid var(--line); border-left:4px solid var(--c); border-radius:8px; padding:10px 12px; background:var(--card); }}
.sc-fr {{ font-weight:600; margin-bottom:2px; }}
.sc-title {{ font-size:12px; color:var(--muted); margin-bottom:6px; }}
.sc-bg {{ border:1px dashed var(--line); border-radius:8px; padding:6px 10px; margin-bottom:8px; }}
.gk {{ font:13px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace; padding-left:2px; overflow-wrap:anywhere; }}
.gk .kw {{ color:var(--accent); font-weight:700; display:inline-block; min-width:44px; }}
.gk code {{ font-size:12px; }}
.sc-row {{ border-bottom:1px solid var(--line); padding:4px 0; }}
.sc-row > summary {{ cursor:pointer; padding:4px 0; font-size:14px; list-style:revert; display:list-item; }}
.sc-row > .gk:first-of-type {{ margin-top:4px; }}
.sc-row[open] {{ padding-bottom:8px; }}
ul.loc, ul.att {{ padding-left:18px; font-size:13px; }} ul.att li {{ margin:4px 0; }}
.tour-step {{ border:1px solid var(--line); border-radius:8px; padding:10px 12px; margin:12px 0; }}
.tour-h {{ display:flex; gap:8px; align-items:center; flex-wrap:wrap; }}
.tour-n {{ display:inline-grid; place-items:center; width:24px; height:24px; border-radius:50%; background:var(--accent); color:#fff; font-size:13px; font-weight:700; }}
pre.code {{ font-size:12px; line-height:1.45; }}
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
    stages = FEATURE_STAGES if kind == "feature" else FIX_STAGES
    if focus is not None and focus not in stages:
        print(f"étape inconnue « {focus} » : {' | '.join(stages)}", file=sys.stderr)
        return 2
    root = sh("git", "rev-parse", "--show-toplevel").strip()
    if not root:
        print("pas dans un repo git", file=sys.stderr)
        return 1
    d = os.path.join(root, ".claude", "features" if kind == "feature" else "fixes", name)
    if not os.path.isdir(d):
        print(f"inconnu : {d}", file=sys.stderr)
        return 1
    try:
        print(feature_report(root, name, focus) if kind == "feature" else fix_report(root, name, focus))
    except ValueError as e:
        print(str(e), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
