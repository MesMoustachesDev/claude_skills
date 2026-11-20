#!/usr/bin/env python3
"""retro.py — mesures de la retro technique du vendredi sur /feature et /fix (skill retro-vendredi).

Aucun LLM : tout se lit sur disque. Le modèle commente et propose ; ce script mesure et décide de ce
qui est valide (règle « le modèle traduit, le script décide »).

  retro.py collect [--weeks N]           mesure tous les runs, écrit <OUT>/AAAA-Www.json et .html, imprime
                                         le chemin du JSON (N semaines comparées, défaut 4)
  retro.py check <propositions.json>     valide les propositions du modèle (schéma strict, 3 au plus) ;
                                         code 0 et les imprime normalisées, sinon code 2 et la raison
  retro.py record <propositions.json> <id> applied|rejected [<commit ou raison>]
                                         note la décision de Thibault dans <OUT>/actions.jsonl
  retro.py followup                      pour chaque action appliquée : la métrique visée, avant / après

Sources :
  - runs : <racine>/**/.claude/{features,fixes}/<nom>/ (et archive/, et les worktrees, la copie la plus
    récente gagne) — pipeline.json ou fix.json, review.json, repro.json, .gauntlet/hooks.jsonl ;
  - consommation et temps actif : transcripts ~/.claude/projects/**.jsonl, rattachés au run par gitBranch
    (feature/<nom>, fix/<nom>) ; agent = subagents/<id>.meta.json → agentType, sinon « orchestrateur ».

Sorties hors du repo public (elles nomment des projets) : RETRO_OUT, défaut ~/.claude-local/retro.
Racines des projets : RETRO_ROOTS (séparées par « : »), défaut ~/work.
"""
from __future__ import annotations

import glob
import html
import json
import os
import re
import statistics
import sys
from datetime import datetime, timedelta, timezone

HOME = os.path.expanduser("~")
OUT = os.environ.get("RETRO_OUT") or os.path.join(HOME, ".claude-local", "retro")
ROOTS = [os.path.expanduser(r) for r in (os.environ.get("RETRO_ROOTS") or "~/work").split(":") if r]
PROJECTS = os.environ.get("RETRO_TRANSCRIPTS") or os.path.join(HOME, ".claude", "projects")
CACHE = os.path.join(OUT, "cache.json")
CACHE_VERSION = 2  # à monter dès que scan_transcript change : le cache est alors recalculé
ACTIONS = os.path.join(OUT, "actions.jsonl")
CLAUDE_HOME = os.path.join(HOME, ".claude")

# Poids relatifs au prix d'un token d'entrée non caché (même rapport pour tous les modèles Claude) :
# écriture de cache 1,25×, lecture de cache 0,1×, sortie 5×. « unités » = coût relatif, pas des euros.
WEIGHTS = {"input": 1.0, "cache_create": 1.25, "cache_read": 0.1, "output": 5.0}
IDLE = 300  # un écart de plus de 5 min entre deux messages = attente (Thibault, tâche de fond), pas du travail
PAUSE = 8 * 3600  # au-delà de 8 h : nuit, week-end ; ni travail ni attente

# Métriques qu'une proposition peut viser : clé → (libellé, sens souhaité). Liste fermée.
METRICS = {
    "units_per_run": ("unités de coût par run", "down"),
    "active_h_per_run": ("heures de travail des agents par run", "down"),
    "wait_h_per_run": ("heures d'attente par run", "down"),
    "lead_h_per_run": ("délai création → evidence (h)", "down"),
    "red_per_run": ("étapes RED/FAILED par run", "down"),
    "retries_per_run": ("tentatives + boucles par run", "down"),
    "refreezes_per_run": ("regels des tests par run", "down"),
    "accepted_per_run": ("étapes acceptées rouges par run", "down"),
    "criticals_per_run": ("critiques de revue par run", "down"),
    "suggestions_per_run": ("suggestions de revue par run", "down"),
    "missing_tests_per_run": ("tests manquants vus en revue par run", "down"),
    "hook_denials_per_run": ("refus de hooks par run", "down"),
    "spawns_per_run": ("lancements d'agents par run", "down"),
}
KINDS = {"rule", "agent_prompt", "agent_model", "pipeline_step", "command", "other"}


# --- utilitaires ---------------------------------------------------------------------------------

def die(msg: str, code: int = 2) -> None:
    print(f"retro: {msg}", file=sys.stderr)
    sys.exit(code)


def load(path: str, default=None):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return default


def save(path: str, data) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    os.replace(tmp, path)


def ts(s) -> datetime | None:
    if not isinstance(s, str) or not s:
        return None
    try:
        d = datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return None
    return d if d.tzinfo else d.replace(tzinfo=timezone.utc)


def week_of(d: datetime) -> str:
    y, w, _ = d.isocalendar()
    return f"{y}-W{w:02d}"


def median(xs):
    xs = [x for x in xs if x is not None]
    return statistics.median(xs) if xs else None


# --- runs ----------------------------------------------------------------------------------------

SKIP = {"node_modules", "build", ".dart_tool", ".git", "Pods", ".gradle", "DerivedData", ".pub-cache",
        "ios", "android", "macos", "linux", "windows", "web", "lib", "test", "assets", ".fvm", "graphify-out"}


def claude_dirs(root: str, depth: int = 3):
    """Les dossiers .claude à 3 niveaux au plus sous root, plus ceux des worktrees .claude/worktrees/*/."""
    def walk(d: str, left: int):
        try:
            entries = os.scandir(d)
        except OSError:
            return
        for en in entries:
            if not en.is_dir(follow_symlinks=False):
                continue
            if en.name == ".claude":
                yield en.path
                for wt in glob.glob(os.path.join(en.path, "worktrees", "*", ".claude")):
                    yield wt
            elif left > 0 and en.name not in SKIP and not en.name.startswith("."):
                yield from walk(en.path, left - 1)
    yield from walk(root, depth)


def run_dirs() -> dict:
    """(projet, kind, nom) → dossier le plus récent parmi la copie principale, l'archive et les worktrees."""
    found = {}
    for root in ROOTS:
        for dot in claude_dirs(root):
            # projet = le dossier qui porte .claude, en remontant hors d'un worktree
            proj_dir = os.path.dirname(dot)
            if "/.claude/worktrees/" in dot:
                proj_dir = dot.split("/.claude/worktrees/")[0]
            project = os.path.relpath(proj_dir, root)
            for kind, sub in (("feature", "features"), ("fix", "fixes")):
                for base in (os.path.join(dot, sub), os.path.join(dot, "archive", sub)):
                    for d in glob.glob(os.path.join(base, "*", "")):
                        state = os.path.join(d, "pipeline.json" if kind == "feature" else "fix.json")
                        if not os.path.exists(state):
                            continue
                        key = (project, kind, os.path.basename(os.path.dirname(d)))
                        m = os.path.getmtime(state)
                        if key not in found or m > found[key][1]:
                            found[key] = (d, m)
    return {k: v[0] for k, v in found.items()}


def count_list(x) -> int:
    return len(x) if isinstance(x, (list, dict)) else 0


def run_metrics(key, d: str) -> dict:
    project, kind, name = key
    st = load(os.path.join(d, "pipeline.json" if kind == "feature" else "fix.json"), {}) or {}
    stages = st.get("stages") if isinstance(st.get("stages"), dict) else {}
    stamps = [ts(v.get("at")) for v in stages.values() if isinstance(v, dict)]
    stamps = [s for s in stamps if s]
    created = ts(st.get("created"))
    ev = stages.get("evidence", {}) if isinstance(stages.get("evidence"), dict) else {}
    done = ev.get("status") in ("PASSED", "ACCEPTED") or os.path.exists(os.path.join(d, "evidence.md"))
    end = max(stamps) if stamps else None
    statuses = [v.get("status") for v in stages.values() if isinstance(v, dict)]
    review = load(os.path.join(d, "review.json"), {}) or {}
    if not isinstance(review, dict):
        review = {}
    repro = load(os.path.join(d, "repro.json"), {}) or {} if kind == "fix" else {}
    journals = glob.glob(os.path.join(d, ".gauntlet", "hooks.jsonl"))
    denials = 0 if journals else None  # journal des hooks absent (runs d'avant l'ADR 0019) : pas de donnée
    for hj in journals:
        with open(hj, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    if json.loads(line).get("outcome") == "deny":  # « red »/« failed » = verdict de gate, pas un refus
                        denials += 1
                except json.JSONDecodeError:
                    pass
    attempts = st.get("attempts") if isinstance(st.get("attempts"), dict) else {}
    loops = st.get("loops") if isinstance(st.get("loops"), dict) else {}
    branch = st.get("branch") or (f"{kind}/{name}")
    return {
        "project": project, "kind": kind, "name": name, "dir": d, "branch": branch,
        "size": st.get("size") if kind == "feature" else None,
        "done": bool(done), "abandoned": bool(st.get("abandoned")),
        "created": created.isoformat() if created else None,
        "end": end.isoformat() if end else None,
        "lead_h": round((end - created).total_seconds() / 3600, 1) if end and created and end > created else None,
        "red": sum(1 for s in statuses if s in ("RED", "FAILED")),
        "skipped": sum(1 for s in statuses if s == "SKIPPED"),
        "retries": sum(v for v in attempts.values() if isinstance(v, int)) + sum(v for v in loops.values() if isinstance(v, int)),
        "refreezes": count_list(st.get("refreezes")),
        "accepted": count_list(st.get("accepted")),
        "debt": count_list(st.get("debt")),
        "criticals": count_list(review.get("critical")),
        "suggestions": count_list(review.get("suggestions")),
        "missing_tests": count_list(review.get("missing_tests")),
        "hook_denials": denials,
        "miss_reason": repro.get("miss_reason") if isinstance(repro, dict) else None,
        "rules_added": count_list(st.get("rules_added")),
    }


# --- transcripts ---------------------------------------------------------------------------------

def scan_transcript(path: str, agent: str) -> dict:
    """branche → {agent: {tokens…, active_s, wait_s, models, spawns}} pour un fichier .jsonl."""
    out = {}
    last = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if '"gitBranch":"feature/' not in line and '"gitBranch":"fix/' not in line:
                continue
            try:
                e = json.loads(line)
            except json.JSONDecodeError:
                continue
            br = e.get("gitBranch") or ""
            t = ts(e.get("timestamp"))
            a = out.setdefault(br, {}).setdefault(agent, {
                "input": 0, "cache_create": 0, "cache_read": 0, "output": 0,
                "active_s": 0.0, "wait_s": 0.0, "models": {}, "spawns": 1 if agent != "orchestrateur" else 0})
            if t is not None:
                if br in last:
                    gap = (t - last[br]).total_seconds()
                    if 0 < gap <= IDLE:
                        a["active_s"] += gap
                    elif IDLE < gap <= PAUSE:
                        a["wait_s"] += gap
                last[br] = t
            msg = e.get("message") if isinstance(e.get("message"), dict) else {}
            u = msg.get("usage") if isinstance(msg.get("usage"), dict) else None
            if e.get("type") == "assistant" and u:
                a["input"] += u.get("input_tokens") or 0
                a["cache_create"] += u.get("cache_creation_input_tokens") or 0
                a["cache_read"] += u.get("cache_read_input_tokens") or 0
                a["output"] += u.get("output_tokens") or 0
                m = msg.get("model") or "?"
                a["models"][m] = a["models"].get(m, 0) + 1
    return out


def transcripts() -> dict:
    """branche → agent → agrégats, sur tous les transcripts, avec un cache par (chemin, taille, mtime)."""
    cache = load(CACHE, {}) or {}
    fresh = {}
    agg = {}
    for path in glob.glob(os.path.join(PROJECTS, "**", "*.jsonl"), recursive=True):
        try:
            sig = f"{CACHE_VERSION}:{os.path.getsize(path)}:{int(os.path.getmtime(path))}"
        except OSError:
            continue
        hit = cache.get(path)
        if hit and hit.get("sig") == sig:
            data = hit["data"]
        else:
            agent = "orchestrateur"
            if "/subagents/" in path:
                meta = load(path[:-len(".jsonl")] + ".meta.json", {}) or {}
                agent = meta.get("agentType") or "general-purpose"
            data = scan_transcript(path, agent)
        fresh[path] = {"sig": sig, "data": data}
        for br, agents in data.items():
            for ag, v in agents.items():
                a = agg.setdefault(br, {}).setdefault(ag, {
                    "input": 0, "cache_create": 0, "cache_read": 0, "output": 0,
                    "active_s": 0.0, "wait_s": 0.0, "models": {}, "spawns": 0})
                for k in ("input", "cache_create", "cache_read", "output", "active_s", "wait_s", "spawns"):
                    a[k] += v.get(k, 0)
                for m, n in v.get("models", {}).items():
                    a["models"][m] = a["models"].get(m, 0) + n
    save(CACHE, fresh)
    return agg


def units(a: dict) -> float:
    return sum(a.get(k, 0) * w for k, w in WEIGHTS.items())


# --- agrégation ----------------------------------------------------------------------------------

def attach_usage(runs: list, usage: dict) -> None:
    for r in runs:
        agents = usage.get(r["branch"], {})
        r["agents"] = {ag: {"units": round(units(v)), "output": v["output"], "active_h": round(v["active_s"] / 3600, 2),
                            "spawns": v["spawns"], "models": v["models"]} for ag, v in agents.items()}
        r["units"] = round(sum(units(v) for v in agents.values()))
        r["active_h"] = round(sum(v["active_s"] for v in agents.values()) / 3600, 2)
        orch = agents.get("orchestrateur", {})
        r["wait_h"] = round(orch.get("wait_s", 0) / 3600, 2)
        r["spawns"] = sum(v["spawns"] for ag, v in agents.items() if ag != "orchestrateur")


def per_run(rows: list, field: str):
    vals = [r.get(field) for r in rows if r.get(field) is not None]
    return round(sum(vals) / len(vals), 2) if vals else None


def summarize(rows: list) -> dict:
    s = {"runs": len(rows)}
    for key in METRICS:
        field = key.replace("_per_run", "")
        field = {"lead_h": "lead_h", "active_h": "active_h", "wait_h": "wait_h"}.get(field, field)
        s[key] = per_run(rows, field)
    s["units_median"] = median([r.get("units") for r in rows])
    return s


def agent_table(rows: list) -> dict:
    t = {}
    for r in rows:
        for ag, v in r.get("agents", {}).items():
            a = t.setdefault(ag, {"units": 0, "active_h": 0.0, "spawns": 0, "runs": 0, "models": {}})
            a["units"] += v["units"]
            a["active_h"] += v["active_h"]
            a["spawns"] += v["spawns"]
            a["runs"] += 1
            for m, n in v["models"].items():
                a["models"][m] = a["models"].get(m, 0) + n
    for a in t.values():
        a["units_per_run"] = round(a["units"] / a["runs"]) if a["runs"] else 0
        a["active_h"] = round(a["active_h"], 2)
    return dict(sorted(t.items(), key=lambda kv: -kv[1]["units"]))


def trend(cur, prev) -> str:
    if cur is None or prev is None:
        return "?"
    if prev == 0:
        return "=" if cur == 0 else "↑"
    r = (cur - prev) / abs(prev)
    return "=" if abs(r) < 0.15 else ("↑" if r > 0 else "↓")


def collect(weeks_back: int) -> str:
    keys = run_dirs()
    runs = [run_metrics(k, d) for k, d in sorted(keys.items())]
    attach_usage(runs, transcripts())
    now = datetime.now(timezone.utc)
    this_week = week_of(now)
    weeks = [week_of(now - timedelta(weeks=i)) for i in range(weeks_back + 1)]
    by_week = {w: [] for w in weeks}
    for r in runs:
        e = ts(r["end"])
        if e and r["done"] and week_of(e) in by_week:
            by_week[week_of(e)].append(r)
    in_progress = [r for r in runs if not r["done"] and not r["abandoned"] and r["end"]
                   and ts(r["end"]) > now - timedelta(days=7)]
    report = {"generated": now.isoformat(), "week": this_week, "weights": WEIGHTS, "metrics": METRICS, "kinds": {}}
    for kind in ("feature", "fix"):
        cur = [r for r in by_week[this_week] if r["kind"] == kind]
        before = [r for w in weeks[1:] for r in by_week[w] if r["kind"] == kind]
        cs, bs = summarize(cur), summarize(before)
        report["kinds"][kind] = {
            "this_week": cs,
            "previous_weeks": bs,
            "trend": {k: trend(cs.get(k), bs.get(k)) for k in METRICS},
            "weekly": {w: summarize([r for r in by_week[w] if r["kind"] == kind]) for w in weeks},
            "by_size": {sz: summarize([r for w in weeks for r in by_week[w] if r["kind"] == kind and r["size"] == sz])
                        for sz in ("S", "M", "L")} if kind == "feature" else {},
            "agents_this_week": agent_table(cur),
            "agents_previous": agent_table(before),
            "miss_reasons": _count([r["miss_reason"] for w in weeks for r in by_week[w] if r["kind"] == "fix"]) if kind == "fix" else {},
            "runs": [{k: v for k, v in r.items() if k != "dir"} for r in cur],
        }
    report["in_progress"] = [{k: r[k] for k in ("project", "kind", "name", "end", "red", "retries", "units")} for r in in_progress]
    report["actions_followup"] = followup_data(runs)
    os.makedirs(OUT, exist_ok=True)
    jpath = os.path.join(OUT, f"{this_week}.json")
    save(jpath, report)
    with open(os.path.join(OUT, f"{this_week}.html"), "w", encoding="utf-8") as f:
        f.write(render_html(report))
    return jpath


def _count(xs) -> dict:
    c = {}
    for x in xs:
        if x:
            c[x] = c.get(x, 0) + 1
    return dict(sorted(c.items(), key=lambda kv: -kv[1]))


# --- actions (propositions du modèle, décisions de Thibault) -------------------------------------

def check(path: str) -> list:
    data = load(path)
    if not isinstance(data, list):
        die("propositions : une liste JSON est attendue")
    if len(data) > 3:
        die("propositions : 3 au plus")
    allowed = {"id", "kind", "target", "change", "why", "metric", "pipeline", "evidence"}
    seen = set()
    for i, p in enumerate(data):
        if not isinstance(p, dict):
            die(f"proposition {i} : objet attendu")
        extra = set(p) - allowed
        if extra:
            die(f"proposition {i} : champs inconnus {sorted(extra)}")
        for k in ("id", "kind", "target", "change", "why", "metric", "pipeline"):
            if not isinstance(p.get(k), str) or not p[k].strip():
                die(f"proposition {i} : champ « {k} » manquant ou vide")
        if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{2,40}", p["id"]) or p["id"] in seen:
            die(f"proposition {i} : id invalide ou en double ({p['id']})")
        seen.add(p["id"])
        if p["kind"] not in KINDS:
            die(f"proposition {i} : kind hors liste {sorted(KINDS)}")
        if p["metric"] not in METRICS:
            die(f"proposition {i} : metric hors liste {sorted(METRICS)}")
        if p["pipeline"] not in ("feature", "fix", "both"):
            die(f"proposition {i} : pipeline = feature|fix|both")
        tgt = os.path.normpath(os.path.join(CLAUDE_HOME, p["target"]))
        if not tgt.startswith(CLAUDE_HOME + os.sep) or not os.path.exists(tgt):
            die(f"proposition {i} : target doit être un fichier existant sous ~/.claude ({p['target']})")
        if len(p["change"]) > 600 or len(p["why"]) > 600:
            die(f"proposition {i} : change et why tiennent en 600 caractères")
        ev = p.get("evidence", [])
        if not isinstance(ev, list) or not all(isinstance(x, str) for x in ev) or len(ev) > 5:
            die(f"proposition {i} : evidence = liste de 5 chaînes au plus")
    return data


def record(path: str, pid: str, decision: str, note: str) -> None:
    if decision not in ("applied", "rejected"):
        die("décision : applied|rejected")
    props = {p["id"]: p for p in check(path)}
    if pid not in props:
        die(f"pas de proposition {pid} dans {path}")
    report = load(path.replace(".proposals.json", ".json"), {}) or {}
    p = props[pid]
    kinds = ["feature", "fix"] if p["pipeline"] == "both" else [p["pipeline"]]
    baseline = {k: (report.get("kinds", {}).get(k, {}).get("previous_weeks", {}) or {}).get(p["metric"]) for k in kinds}
    entry = {**p, "decision": decision, "note": note, "at": datetime.now(timezone.utc).isoformat(), "baseline": baseline}
    os.makedirs(OUT, exist_ok=True)
    with open(ACTIONS, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    print(f"noté : {pid} {decision}")


def followup_data(runs: list) -> list:
    out = []
    if not os.path.exists(ACTIONS):
        return out
    with open(ACTIONS, encoding="utf-8") as f:
        entries = [json.loads(line) for line in f if line.strip()]
    for a in entries:
        if a.get("decision") != "applied":
            continue
        at = ts(a.get("at"))
        kinds = ["feature", "fix"] if a["pipeline"] == "both" else [a["pipeline"]]
        res = {}
        for k in kinds:
            after = [r for r in runs if r["kind"] == k and r["done"] and ts(r["end"]) and at and ts(r["end"]) > at]
            res[k] = {"runs_after": len(after), "after": summarize(after).get(a["metric"]) if after else None,
                      "before": (a.get("baseline") or {}).get(k)}
        out.append({"id": a["id"], "metric": a["metric"], "want": METRICS[a["metric"]][1], "applied": a["at"],
                    "change": a["change"], "result": res})
    return out


# --- HTML ----------------------------------------------------------------------------------------

def mu(x) -> str:
    """Unités en millions, lisibles."""
    return "" if x is None else f"{x / 1e6:.1f} M"


def cell(metric: str, v) -> str:
    if v is None:
        return ""
    return mu(v) if metric.startswith("units") else str(v)


def spark(vals: list) -> str:
    pts = [v for v in vals if v is not None]
    if len(pts) < 2:
        return ""
    hi, lo = max(pts), min(pts)
    rng = (hi - lo) or 1
    w, h, n = 90, 22, len(vals)
    coords = [(i * w / (n - 1), h - 2 - (v - lo) / rng * (h - 4)) for i, v in enumerate(vals) if v is not None]
    d = " ".join(f"{x:.1f},{y:.1f}" for x, y in coords)
    return f'<svg width="{w}" height="{h}" viewBox="0 0 {w} {h}"><polyline points="{d}" fill="none" stroke="currentColor" stroke-width="1.5"/></svg>'


def render_html(rep: dict) -> str:
    e = html.escape
    parts = [f"""<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Retro {e(rep['week'])}</title><style>
:root{{--bg:#fbfaf7;--fg:#1d1d1b;--mute:#6b6a65;--line:#e4e1d8;--up:#b4441f;--down:#2f7a4a}}
@media (prefers-color-scheme:dark){{:root{{--bg:#191917;--fg:#ecebe6;--mute:#9a988f;--line:#33322e;--up:#e0805e;--down:#6cc08b}}}}
body{{background:var(--bg);color:var(--fg);font:15px/1.5 -apple-system,system-ui,sans-serif;margin:0 auto;max-width:1000px;padding:24px 16px}}
h1{{font-size:22px}} h2{{font-size:18px;margin-top:32px;border-bottom:1px solid var(--line)}} small,.mute{{color:var(--mute)}}
table{{border-collapse:collapse;width:100%;margin:8px 0;font-variant-numeric:tabular-nums}} .wrap{{overflow-x:auto}}
td,th{{padding:4px 8px;border-bottom:1px solid var(--line);text-align:right}} td:first-child,th:first-child{{text-align:left}}
.bad{{color:var(--up)}} .good{{color:var(--down)}}
</style></head><body><h1>Retro technique, semaine {e(rep['week'])}</h1>
<p class="mute">Unités = coût relatif à un token d'entrée (cache écrit ×1,25, lu ×0,1, sortie ×5). Comparaison : cette semaine contre la moyenne par run des semaines d'avant.</p>"""]
    for kind, k in rep["kinds"].items():
        weeks = sorted(k["weekly"])
        parts.append(f"<h2>/{kind} — {k['this_week']['runs']} run(s) finis cette semaine, {k['previous_weeks']['runs']} avant</h2>")
        parts.append('<div class="wrap"><table><tr><th>Métrique</th><th>Cette semaine</th><th>Avant</th><th>Tendance</th><th>Semaines</th></tr>')
        for m, (label, want) in rep["metrics"].items():
            c, p, t = k["this_week"].get(m), k["previous_weeks"].get(m), k["trend"].get(m)
            cls = "" if t in ("=", "?") else ("good" if (t == "↓") == (want == "down") else "bad")
            parts.append(f"<tr><td>{e(label)}</td><td>{cell(m, c)}</td><td>{cell(m, p)}</td>"
                         f"<td class='{cls}'>{t}</td><td>{spark([k['weekly'][w].get(m) for w in weeks])}</td></tr>")
        parts.append("</table></div>")
        if k.get("by_size"):
            parts.append("<p><b>Par taille</b> (toutes les semaines comparées) : " + " · ".join(
                f"{sz} : {v['runs']} runs, {mu(v.get('units_per_run')) or '–'}, {v.get('lead_h_per_run') or '–'} h"
                for sz, v in k["by_size"].items()) + "</p>")
        if k.get("miss_reasons"):
            parts.append("<p><b>Pourquoi les tests ont laissé passer le bug</b> : " + ", ".join(f"{e(r)} {n}" for r, n in k["miss_reasons"].items()) + "</p>")
        parts.append('<div class="wrap"><table><tr><th>Agent</th><th>Unités / run</th><th>Avant</th><th>h actives</th><th>Lancements</th><th>Modèles</th></tr>')
        prev = k["agents_previous"]
        for ag, v in k["agents_this_week"].items():
            pv = prev.get(ag, {}).get("units_per_run")
            parts.append(f"<tr><td>{e(ag)}</td><td>{mu(v['units_per_run'])}</td><td>{mu(pv)}</td>"
                         f"<td>{v['active_h']}</td><td>{v['spawns']}</td><td>{e(', '.join(v['models']))}</td></tr>")
        parts.append("</table></div>")
        if k["runs"]:
            parts.append('<div class="wrap"><table><tr><th>Run</th><th>Taille</th><th>Unités</th><th>h actives</th><th>h attente</th><th>RED</th><th>Reprises</th><th>Regels</th><th>Critiques</th><th>Refus hooks</th></tr>')
            for r in k["runs"]:
                parts.append(f"<tr><td>{e(r['project'])} / {e(r['name'])}</td><td>{r['size'] or ''}</td><td>{mu(r['units'])}</td><td>{r['active_h']}</td>"
                             f"<td>{r['wait_h']}</td><td>{r['red']}</td><td>{r['retries']}</td><td>{r['refreezes']}</td><td>{r['criticals']}</td><td>{'' if r['hook_denials'] is None else r['hook_denials']}</td></tr>")
            parts.append("</table></div>")
    if rep.get("actions_followup"):
        parts.append("<h2>Suivi des changements appliqués</h2><ul>")
        for a in rep["actions_followup"]:
            res = "; ".join(f"/{k} : {v['before']} → {v['after']} ({v['runs_after']} runs)" for k, v in a["result"].items())
            parts.append(f"<li><b>{e(a['id'])}</b> ({e(a['metric'])}, visé {a['want']}) : {e(res)}<br><small>{e(a['change'])}</small></li>")
        parts.append("</ul>")
    if rep.get("in_progress"):
        parts.append("<h2>En cours</h2><ul>" + "".join(
            f"<li>/{e(r['kind'])} {e(r['project'])} / {e(r['name'])} : {r['red']} RED, {r['retries']} reprises, {mu(r['units'])}</li>"
            for r in rep["in_progress"]) + "</ul>")
    parts.append("</body></html>")
    return "\n".join(parts)


# --- main ----------------------------------------------------------------------------------------

def main(argv: list) -> None:
    if not argv:
        die(__doc__.strip().splitlines()[2])
    cmd = argv[0]
    if cmd == "collect":
        n = 4
        if "--weeks" in argv:
            n = int(argv[argv.index("--weeks") + 1])
        print(collect(n))
    elif cmd == "check" and len(argv) == 2:
        print(json.dumps(check(argv[1]), ensure_ascii=False, indent=1))
    elif cmd == "record" and len(argv) >= 4:
        record(argv[1], argv[2], argv[3], " ".join(argv[4:]))
    elif cmd == "followup":
        keys = run_dirs()
        runs = [run_metrics(k, d) for k, d in sorted(keys.items())]
        attach_usage(runs, transcripts())
        print(json.dumps(followup_data(runs), ensure_ascii=False, indent=1))
    else:
        die("usage : collect [--weeks N] | check <f> | record <f> <id> applied|rejected [note] | followup")


if __name__ == "__main__":
    main(sys.argv[1:])
