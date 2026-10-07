#!/usr/bin/env python3
"""business_rules.py — les règles métier d'un répertoire, lues dans ses fichiers Gherkin (.feature).

Usage :
  business_rules.py [répertoire] [--out <fichier.html>]

Cherche tous les .feature sous le répertoire (défaut : courant), hors dépendances et artefacts
(vendor, node_modules, build, Pods, .dart_tool, worktrees de .claude…), les regroupe par package
(dossier parent le plus proche qui a un pubspec.yaml ou un package.json) et écrit une page HTML
autonome : navigation par package et feature, recherche plein texte, filtre par tag, scénarios
dépliables avec leurs steps, tables et exemples, et une liste de signalements (feature sans scénario,
scénario sans Then, titres en double).

Sortie par défaut : <racine git>/.claude/business_rules.html (ou <répertoire>/business_rules.html hors
git). Aucun LLM. Imprime le chemin écrit et un résumé court : c'est tout ce que l'agent doit lire.
"""
from __future__ import annotations

import html
import json
import os
import re
import subprocess
import sys
import textwrap
from datetime import datetime

SKIP_DIRS = {".git", "node_modules", ".dart_tool", "build", "Pods", "vendor", ".symlinks", "ephemeral",
             ".fvm", ".pub-cache", "dist", "target", ".venv", "venv", "__pycache__", ".gradle", "DerivedData"}
PACKAGE_MARKERS = ("pubspec.yaml", "package.json")

# Mots-clés Gherkin, anglais et français (# language: fr).
KW = {
    "feature": ("Feature", "Business Need", "Ability", "Fonctionnalité"),
    "rule": ("Rule", "Règle"),
    "background": ("Background", "Contexte"),
    "outline": ("Scenario Outline", "Scenario Template", "Plan du scénario", "Plan du Scénario"),
    "scenario": ("Scenario", "Example", "Scénario", "Exemple"),
    "examples": ("Examples", "Scenarios", "Exemples"),
}
STEP_KW = ("Given", "When", "Then", "And", "But", "*", "Soit", "Etant donné que", "Étant donné que",
           "Etant donné", "Étant donné", "Quand", "Lorsque", "Alors", "Donc", "Et que", "Et", "Mais que", "Mais")
THEN_KW = {"Then", "Alors", "Donc"}


# --- découverte -----------------------------------------------------------------------------------

def find_features(root: str) -> list[str]:
    out = []
    for d, dirs, files in os.walk(root):
        rel = os.path.relpath(d, root)
        dirs[:] = sorted(x for x in dirs if x not in SKIP_DIRS
                         and not (x == "worktrees" and os.path.basename(d) == ".claude"))
        if rel != "." and any(p in SKIP_DIRS for p in rel.split(os.sep)):
            continue
        out += [os.path.join(d, f) for f in sorted(files) if f.endswith(".feature")]
    return out


def excluded_worktrees(root: str) -> list[tuple[str, int]]:
    """Worktrees de .claude/worktrees qui contiennent des .feature (exclus du rapport, signalés)."""
    out = []
    for d, dirs, _ in os.walk(root):
        dirs[:] = [x for x in dirs if x not in SKIP_DIRS]
        if os.path.basename(d) == "worktrees" and os.path.basename(os.path.dirname(d)) == ".claude":
            for w in sorted(dirs):
                n = len(find_features(os.path.join(d, w)))
                if n:
                    out.append((os.path.relpath(os.path.join(d, w), root), n))
            dirs[:] = []
    return out


def package_of(path: str, root: str) -> str:
    d = os.path.dirname(path)
    while True:
        if any(os.path.isfile(os.path.join(d, m)) for m in PACKAGE_MARKERS):
            rel = os.path.relpath(d, root)
            return "." if rel == "." else rel
        if os.path.abspath(d) == os.path.abspath(root) or os.path.dirname(d) == d:
            return os.path.relpath(os.path.dirname(path), root)
        d = os.path.dirname(d)


# --- parsing --------------------------------------------------------------------------------------

def _kw(line: str, group: str) -> str | None:
    for k in sorted(KW[group], key=len, reverse=True):
        if line.startswith(k + ":"):
            return line[len(k) + 1:].strip()
    return None


def _step(line: str) -> tuple[str, str] | None:
    for k in sorted(STEP_KW, key=len, reverse=True):
        if line == k or line.startswith(k + " "):
            return k, line[len(k):].strip()
    return None


def _cells(line: str) -> list[str]:
    return [c.strip().replace("\\|", "|") for c in re.split(r"(?<!\\)\|", line.strip()[1:-1])]


def parse_feature(path: str) -> dict:
    feat = {"title": "", "description": [], "tags": [], "background": None, "rules": [], "line": 1}
    rule = {"title": None, "description": [], "background": None, "scenarios": [], "tags": []}
    feat["rules"].append(rule)
    pending_tags: list[str] = []
    scen = None          # scénario courant
    block = None         # là où vont les steps : background ou scénario
    target = None        # description en cours (feature / rule / scénario)
    examples = None      # bloc Examples courant
    doc = None           # docstring ouverte : (délimiteur, lignes)
    lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    for n, raw in enumerate(lines, 1):
        line = raw.strip()
        if doc is not None:
            if line.startswith(doc[0]):
                if block and block["steps"]:
                    block["steps"][-1]["doc"] = textwrap.dedent("\n".join(doc[1])).strip("\n")
                doc = None
            else:
                doc[1].append(raw)
            continue
        if not line or line.startswith("#"):
            continue
        if line.startswith("@"):
            pending_tags += re.findall(r"@[^\s@]+", line)
            continue
        if line.startswith(('"""', "```")):
            doc = (line[:3], [])
            continue
        if line.startswith("|"):
            if examples is not None:
                examples["rows"].append(_cells(line))
            elif block and block["steps"]:
                block["steps"][-1].setdefault("table", []).append(_cells(line))
            continue
        t = _kw(line, "feature")
        if t is not None:
            feat.update(title=t, tags=pending_tags, line=n)
            pending_tags, target = [], feat["description"]
            continue
        t = _kw(line, "rule")
        if t is not None:
            if rule["title"] is None and not rule["scenarios"] and not rule["background"]:
                feat["rules"].remove(rule)
            rule = {"title": t, "description": [], "background": None, "scenarios": [], "tags": pending_tags}
            feat["rules"].append(rule)
            pending_tags, target, scen, examples, block = [], rule["description"], None, None, None
            continue
        t = _kw(line, "background")
        if t is not None:
            bg = {"steps": []}
            if rule["title"] is None:
                feat["background"] = bg
            else:
                rule["background"] = bg
            block, target, examples, pending_tags = bg, None, None, []
            continue
        t = _kw(line, "outline")
        outline = t is not None
        if t is None:
            t = _kw(line, "scenario")
        if t is not None:
            scen = {"title": t, "outline": outline, "tags": pending_tags, "steps": [], "examples": [],
                    "line": n, "description": []}
            rule["scenarios"].append(scen)
            block, target, examples, pending_tags = scen, scen["description"], None, []
            continue
        t = _kw(line, "examples")
        if t is not None and scen is not None:
            examples = {"title": t, "tags": pending_tags, "rows": []}
            scen["examples"].append(examples)
            pending_tags, target = [], None
            continue
        st = _step(line)
        if st and block is not None:
            block["steps"].append({"kw": st[0], "text": st[1]})
            target, examples = None, None
            continue
        if target is not None:
            target.append(line)
    if not any(r["scenarios"] or r["background"] or r["title"] for r in feat["rules"]):
        feat["rules"] = [r for r in feat["rules"] if r["title"]]
    return feat


# --- signalements ---------------------------------------------------------------------------------

def findings(features: list[dict]) -> list[tuple[str, str]]:
    out = []
    for f in features:
        scen = [s for r in f["rules"] for s in r["scenarios"]]
        where = f'{f["rel"]}'
        if not f["title"]:
            out.append((where, "fichier sans ligne Feature:"))
        if not scen:
            out.append((where, "aucun scénario"))
        seen: dict[str, int] = {}
        for s in scen:
            key = s["title"].strip().lower()
            if key in seen:
                out.append((f'{where}:{s["line"]}', f"titre en double avec la ligne {seen[key]} : « {s['title']} »"))
            seen.setdefault(key, s["line"])
            if not s["title"].strip():
                out.append((f'{where}:{s["line"]}', "scénario sans titre"))
            if not any(st["kw"] in THEN_KW for st in s["steps"]):
                out.append((f'{where}:{s["line"]}', f"pas de Then : « {s['title']} »"))
            if s["outline"] and not any(len(e["rows"]) > 1 for e in s["examples"]):
                out.append((f'{where}:{s["line"]}', f"Scenario Outline sans exemples : « {s['title']} »"))
    return out


# --- rendu ----------------------------------------------------------------------------------------

def esc(s: object) -> str:
    return html.escape(str(s if s is not None else ""))


def fmt_step(text: str) -> str:
    return re.sub(r"(\{[^}]*\}|&quot;[^&]*?&quot;|&lt;[\w\s-]+&gt;)", r"<code>\1</code>", esc(text))


def table_html(rows: list[list[str]], cls: str = "") -> str:
    if not rows:
        return ""
    head = "".join(f"<th>{esc(c)}</th>" for c in rows[0])
    body = "".join("<tr>" + "".join(f"<td>{fmt_step(c)}</td>" for c in r) + "</tr>" for r in rows[1:])
    return f'<div class="tw"><table class="{cls}"><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table></div>'


def steps_html(steps: list[dict]) -> str:
    out = []
    for st in steps:
        out.append(f'<div class="st"><span class="kw">{esc(st["kw"])}</span> {fmt_step(st["text"])}</div>')
        if st.get("table"):
            out.append(table_html(st["table"], "dt"))
        if st.get("doc") is not None:
            out.append(f'<pre class="doc">{esc(st["doc"])}</pre>')
    return "".join(out)


def tags_html(tags: list[str]) -> str:
    return "".join(f'<span class="tag" data-tag="{esc(t)}">{esc(t)}</span>' for t in tags)


def scenario_html(s: dict, inherited: list[str]) -> str:
    tags = inherited + s["tags"] + [t for e in s["examples"] for t in e["tags"]]
    n_ex = sum(max(len(e["rows"]) - 1, 0) for e in s["examples"])
    badge = f'<span class="badge">plan × {n_ex}</span>' if s["outline"] else ""
    search = " ".join([s["title"], *(st["text"] for st in s["steps"])]).lower()
    desc = f'<p class="desc">{esc(" ".join(s["description"]))}</p>' if s["description"] else ""
    ex = "".join((f'<div class="exh">Exemples{(" : " + esc(e["title"])) if e["title"] else ""} {tags_html(e["tags"])}</div>'
                  + table_html(e["rows"], "ex")) for e in s["examples"])
    return (f'<details class="sc" data-search="{esc(search)}" data-tags="{esc(" ".join(tags))}">'
            f'<summary><span class="sct">{esc(s["title"]) or "<i>sans titre</i>"}</span>{badge}{tags_html(s["tags"])}'
            f'<span class="ln">l.{s["line"]}</span></summary><div class="scb">{desc}{steps_html(s["steps"])}{ex}</div></details>')


def feature_html(f: dict, fid: str) -> str:
    n = sum(len(r["scenarios"]) for r in f["rules"])
    desc = f'<p class="desc">{esc(" ".join(f["description"]))}</p>' if f["description"] else ""
    bg = (f'<div class="bg"><div class="bgh">Contexte commun</div>{steps_html(f["background"]["steps"])}</div>'
          if f["background"] and f["background"]["steps"] else "")
    body = []
    for r in f["rules"]:
        sc = "".join(scenario_html(s, f["tags"] + r["tags"]) for s in r["scenarios"])
        if r["title"] is None:
            body.append(sc)
            continue
        rbg = (f'<div class="bg"><div class="bgh">Contexte de la règle</div>{steps_html(r["background"]["steps"])}</div>'
               if r["background"] and r["background"]["steps"] else "")
        rdesc = f'<p class="desc">{esc(" ".join(r["description"]))}</p>' if r["description"] else ""
        body.append(f'<div class="rule"><div class="rh"><span class="rk">Règle</span> {esc(r["title"])} {tags_html(r["tags"])}'
                    f'</div>{rdesc}{rbg}{sc}</div>')
    return (f'<article class="feat" id="{fid}"><header><h3>{esc(f["title"]) or esc(os.path.basename(f["rel"]))}</h3>'
            f'<span class="badge">{n} scénario{"s" if n > 1 else ""}</span>{tags_html(f["tags"])}'
            f'<div class="path">{esc(f["rel"])}</div></header>{desc}{bg}{"".join(body)}</article>')


def render(root: str, features: list[dict], found: list[tuple[str, str]]) -> str:
    pkgs: dict[str, list[dict]] = {}
    for f in features:
        pkgs.setdefault(f["package"], []).append(f)
    all_tags = sorted({t for f in features for t in f["tags"] + [t for r in f["rules"] for s in r["scenarios"]
                                                                   for t in s["tags"] + r["tags"]]})
    n_sc = sum(len(r["scenarios"]) for f in features for r in f["rules"])
    nav, main = [], []
    for i, (pkg, fs) in enumerate(sorted(pkgs.items())):
        pid = f"p{i}"
        items = []
        secs = []
        for j, f in enumerate(sorted(fs, key=lambda x: (x["title"] or x["rel"]).lower())):
            fid = f"{pid}f{j}"
            n = sum(len(r["scenarios"]) for r in f["rules"])
            items.append(f'<li><a href="#{fid}" data-feat="{fid}">{esc(f["title"] or os.path.basename(f["rel"]))}'
                         f' <span class="cnt">{n}</span></a></li>')
            secs.append(feature_html(f, fid))
        total = sum(len(r["scenarios"]) for f in fs for r in f["rules"])
        nav.append(f'<li class="pk"><a href="#{pid}" data-pkg="{pid}">{esc(pkg)} <span class="cnt">{total}</span></a>'
                   f'<ul>{"".join(items)}</ul></li>')
        main.append(f'<section class="pkg" id="{pid}"><h2>{esc(pkg)} <span class="cnt">{len(fs)} feature'
                    f'{"s" if len(fs) > 1 else ""} · {total} scénarios</span></h2>{"".join(secs)}</section>')
    found_html = ""
    if found:
        rows = "".join(f"<li><code>{esc(w)}</code> {esc(m)}</li>" for w, m in found)
        found_html = (f'<details class="found"><summary>{len(found)} signalement{"s" if len(found) > 1 else ""} '
                      f'(scénario sans Then, doublons, features vides…)</summary><ul>{rows}</ul></details>')
    tags = "".join(f'<button class="tchip" data-tag="{esc(t)}">{esc(t)}</button>' for t in all_tags)
    return TEMPLATE.format(
        root=esc(root), date=f"{datetime.now():%Y-%m-%d %H:%M}", n_pkg=len(pkgs), n_feat=len(features),
        n_sc=n_sc, nav="".join(nav), main="".join(main) or '<p class="muted">Aucun fichier .feature trouvé.</p>',
        found=found_html, tags=(f'<div class="tags">{tags}</div>' if tags else ""), js=JS)


TEMPLATE = """<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Règles métier</title>
<style>
:root {{ --bg:#fafaf9; --fg:#1c1917; --muted:#78716c; --card:#fff; --line:#e7e5e4; --accent:#2563eb;
  --code:#f5f5f4; --warn:#a16207; --warn-bg:#fef9c3; --hl:#ede9fe; }}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{ --bg:#0c0a09; --fg:#e7e5e4; --muted:#a8a29e;
  --card:#1c1917; --line:#292524; --accent:#60a5fa; --code:#292524; --warn:#facc15; --warn-bg:#422006; --hl:#2e1065; }} }}
* {{ box-sizing:border-box; }}
body {{ margin:0; background:var(--bg); color:var(--fg); font:15px/1.55 -apple-system,BlinkMacSystemFont,"Inter",system-ui,sans-serif; }}
.top {{ position:sticky; top:0; z-index:3; background:var(--bg); border-bottom:1px solid var(--line); padding:14px 16px 10px; }}
.top h1 {{ margin:0; font-size:22px; }} .meta {{ color:var(--muted); font-size:13px; margin:2px 0 10px; overflow-wrap:anywhere; }}
.bar {{ display:flex; gap:8px; flex-wrap:wrap; align-items:center; }}
.bar input {{ flex:1; min-width:200px; font:inherit; padding:7px 10px; border-radius:8px; border:1px solid var(--line); background:var(--card); color:var(--fg); }}
.btn,.tchip {{ font:inherit; font-size:13px; padding:5px 10px; border-radius:999px; border:1px solid var(--line); background:var(--card); color:var(--fg); cursor:pointer; }}
.tchip.on {{ background:var(--accent); border-color:var(--accent); color:#fff; }}
.tags {{ display:flex; gap:6px; flex-wrap:wrap; margin-top:8px; }}
.count {{ color:var(--muted); font-size:13px; }}
.layout {{ display:grid; grid-template-columns:260px 1fr; gap:24px; max-width:1300px; margin:0 auto; padding:16px; }}
nav {{ position:sticky; top:calc(var(--top, 150px) + 12px); align-self:start; max-height:calc(100vh - var(--top, 150px) - 24px); overflow:auto; font-size:14px; }}
nav ul {{ list-style:none; margin:0; padding:0; }} nav ul ul {{ padding-left:12px; margin:2px 0 10px; border-left:1px solid var(--line); }}
nav a {{ color:var(--fg); text-decoration:none; display:block; padding:2px 6px; border-radius:4px; overflow-wrap:anywhere; }}
nav a:hover {{ background:var(--code); }} nav .pk > a {{ font-weight:600; }}
.cnt {{ color:var(--muted); font-size:12px; font-weight:400; }}
.hidden {{ display:none !important; }}
.pkg,.feat {{ scroll-margin-top:calc(var(--top, 150px) + 12px); }}
.pkg h2 {{ font-size:18px; margin:8px 0 10px; padding-bottom:4px; border-bottom:2px solid var(--line); overflow-wrap:anywhere; }}
.feat {{ background:var(--card); border:1px solid var(--line); border-radius:10px; padding:12px 16px; margin:0 0 14px; }}
.feat header {{ display:flex; flex-wrap:wrap; gap:8px; align-items:baseline; }}
.feat h3 {{ margin:0; font-size:16px; }} .path {{ width:100%; color:var(--muted); font-size:12px; font-family:ui-monospace,Menlo,monospace; overflow-wrap:anywhere; }}
.desc {{ color:var(--muted); margin:6px 0; }}
.badge {{ font-size:12px; padding:1px 8px; border-radius:999px; background:var(--code); color:var(--muted); white-space:nowrap; }}
.tag {{ font-size:11px; padding:0 6px; border-radius:4px; background:var(--warn-bg); color:var(--warn); margin-left:4px; cursor:pointer; }}
.bg {{ border:1px dashed var(--line); border-radius:8px; padding:6px 10px; margin:8px 0; }}
.bgh {{ font-size:12px; color:var(--muted); text-transform:uppercase; letter-spacing:.04em; }}
.rule {{ border-left:3px solid var(--accent); padding-left:12px; margin:12px 0; }}
.rh {{ font-weight:600; }} .rk {{ font-size:11px; text-transform:uppercase; letter-spacing:.05em; color:var(--accent); margin-right:4px; }}
.sc {{ border-bottom:1px solid var(--line); }} .sc:last-child {{ border-bottom:0; }}
.sc > summary {{ cursor:pointer; padding:6px 0; display:flex; gap:6px; align-items:baseline; flex-wrap:wrap; }}
.sct {{ flex:1; min-width:200px; }} .ln {{ color:var(--muted); font-size:11px; font-family:ui-monospace,Menlo,monospace; }}
.scb {{ padding:0 0 10px 18px; }}
.st {{ font:13px/1.6 ui-monospace,SFMono-Regular,Menlo,monospace; overflow-wrap:anywhere; }}
.st .kw {{ color:var(--accent); font-weight:700; display:inline-block; min-width:48px; }}
code {{ background:var(--code); padding:0 4px; border-radius:4px; font-size:12px; }}
.tw {{ overflow-x:auto; margin:4px 0 6px; }} table {{ border-collapse:collapse; font-size:13px; }}
th,td {{ border:1px solid var(--line); padding:3px 8px; text-align:left; }} th {{ color:var(--muted); }}
.exh {{ font-size:12px; color:var(--muted); margin-top:6px; }}
pre.doc {{ background:var(--code); padding:8px; border-radius:6px; font-size:12px; overflow-x:auto; margin:4px 0; }}
.found {{ background:var(--warn-bg); color:var(--warn); border-radius:8px; padding:8px 12px; margin-bottom:14px; font-size:14px; }}
.found summary {{ cursor:pointer; font-weight:600; }} .found ul {{ margin:6px 0 0; padding-left:18px; }}
.found code {{ background:transparent; }}
.muted {{ color:var(--muted); }}
mark {{ background:var(--hl); color:inherit; border-radius:2px; }}
@media (max-width:820px) {{ .layout {{ grid-template-columns:1fr; }} nav {{ position:static; max-height:none; }} }}
</style></head><body>
<div class="top"><h1>Règles métier</h1>
<div class="meta">{root} · {n_pkg} package(s) · {n_feat} feature(s) · {n_sc} scénarios · généré le {date}</div>
<div class="bar"><input id="q" type="search" placeholder="Chercher dans les titres et les steps…" autocomplete="off">
<button class="btn" id="open">Tout déplier</button><button class="btn" id="close">Tout replier</button>
<span class="count" id="count"></span></div>{tags}</div>
<div class="layout"><nav><ul>{nav}</ul></nav><main>{found}{main}</main></div>
<script>{js}</script>
</body></html>
"""

JS = r"""
(function () {
  const q = document.getElementById('q'), count = document.getElementById('count');
  const top = document.querySelector('.top');
  const setTop = () => document.documentElement.style.setProperty('--top', top.offsetHeight + 'px');
  setTop(); window.addEventListener('resize', setTop);
  const scs = [...document.querySelectorAll('.sc')], on = new Set();
  function apply() {
    const terms = q.value.trim().toLowerCase().split(/\s+/).filter(Boolean);
    let n = 0;
    scs.forEach(s => {
      const okText = terms.every(t => s.dataset.search.includes(t) || s.closest('.feat').querySelector('h3').textContent.toLowerCase().includes(t));
      const tags = s.dataset.tags.split(' ');
      const okTag = [...on].every(t => tags.includes(t));
      const ok = okText && okTag;
      s.classList.toggle('hidden', !ok);
      if (ok) n++;
      if (terms.length && ok) s.open = true;
    });
    document.querySelectorAll('.rule').forEach(r => r.classList.toggle('hidden', !r.querySelector('.sc:not(.hidden)')));
    document.querySelectorAll('.feat').forEach(f => {
      const vis = !!f.querySelector('.sc:not(.hidden)') || (!terms.length && !on.size);
      f.classList.toggle('hidden', !vis);
      const a = document.querySelector('nav a[data-feat="' + f.id + '"]');
      if (a) a.parentElement.classList.toggle('hidden', !vis);
    });
    document.querySelectorAll('.pkg').forEach(p => {
      const vis = !!p.querySelector('.feat:not(.hidden)');
      p.classList.toggle('hidden', !vis);
      const a = document.querySelector('nav a[data-pkg="' + p.id + '"]');
      if (a) a.parentElement.classList.toggle('hidden', !vis);
    });
    count.textContent = (terms.length || on.size) ? n + ' / ' + scs.length + ' scénarios' : scs.length + ' scénarios';
  }
  q.addEventListener('input', apply);
  document.addEventListener('click', e => {
    const t = e.target.closest('[data-tag]');
    if (!t) return;
    e.preventDefault();
    const tag = t.dataset.tag;
    on.has(tag) ? on.delete(tag) : on.add(tag);
    document.querySelectorAll('.tchip').forEach(c => c.classList.toggle('on', on.has(c.dataset.tag)));
    apply();
  });
  document.getElementById('open').onclick = () => scs.forEach(s => { if (!s.classList.contains('hidden')) s.open = true; });
  document.getElementById('close').onclick = () => scs.forEach(s => s.open = false);
  apply();
})();
"""


# --- main -----------------------------------------------------------------------------------------

def main() -> int:
    args = sys.argv[1:]
    out = None
    if "--out" in args:
        i = args.index("--out")
        if i + 1 >= len(args):
            print("--out attend un chemin", file=sys.stderr)
            return 2
        out = args[i + 1]
        del args[i:i + 2]
    if any(a in ("-h", "--help") for a in args) or len(args) > 1:
        print(__doc__.strip(), file=sys.stderr)
        return 0 if args and args[0] in ("-h", "--help") else 2
    root = os.path.abspath(args[0] if args else ".")
    if not os.path.isdir(root):
        print(f"répertoire introuvable : {root}", file=sys.stderr)
        return 1
    if out is None:
        git = subprocess.run(["git", "rev-parse", "--show-toplevel"], cwd=root, capture_output=True, text=True).stdout.strip()
        out = os.path.join(git, ".claude", "business_rules.html") if git else os.path.join(root, "business_rules.html")
    out = os.path.abspath(out)

    features = []
    for p in find_features(root):
        f = parse_feature(p)
        f["rel"] = os.path.relpath(p, root)
        f["package"] = package_of(p, root)
        features.append(f)
    found = findings(features)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(render(root, features, found))

    # Résumé court pour l'agent : il ne lit pas le HTML.
    n_sc = sum(len(r["scenarios"]) for f in features for r in f["rules"])
    pkgs: dict[str, list[int]] = {}
    for f in features:
        pkgs.setdefault(f["package"], [0, 0])
        pkgs[f["package"]][0] += 1
        pkgs[f["package"]][1] += sum(len(r["scenarios"]) for r in f["rules"])
    print(out)
    print(f"{len(pkgs)} package(s), {len(features)} feature(s), {n_sc} scénario(s), {len(found)} signalement(s)")
    for pkg, (nf, ns) in sorted(pkgs.items(), key=lambda kv: -kv[1][1])[:15]:
        print(f"  {pkg} : {nf} feature(s), {ns} scénario(s)")
    if len(pkgs) > 15:
        print(f"  … et {len(pkgs) - 15} autre(s) package(s)")
    kinds: dict[str, int] = {}
    for _, m in found:
        k = m.split(" :")[0].split(" avec")[0]
        kinds[k] = kinds.get(k, 0) + 1
    wts = excluded_worktrees(root)
    if wts:
        print(f"exclus : {sum(n for _, n in wts)} .feature dans {len(wts)} worktree(s) de .claude/worktrees "
              f"(à lancer sur le worktree lui-même) : " + ", ".join(w for w, _ in wts[:5]) + (" …" if len(wts) > 5 else ""))
    if kinds:
        print("signalements : " + ", ".join(f"{v} × {k}" for k, v in sorted(kinds.items(), key=lambda kv: -kv[1])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
