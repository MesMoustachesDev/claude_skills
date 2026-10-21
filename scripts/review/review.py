#!/usr/bin/env python3
"""review.py — état et mécanique de /reviewPR. Usage : voir ../review.sh.

La cible, le worktree, l'état des trois agents, la fusion des remarques, le tri fait dans le cockpit et
la publication sur la MR vivent ici, pas dans le prompt de l'orchestrateur.
"""
import datetime
import json
import os
import re
import shutil
import subprocess
import sys

HOME = os.path.expanduser("~")
STATE_ROOT = os.path.join(HOME, ".cache", "gauntlet", "review")
GAUNTLET_OUT_ROOT = os.path.join(HOME, ".cache", "gauntlet", "pr")
STEPS_DIR = os.path.join(HOME, ".claude", "pipeline", "review", "steps")
PR_GAUNTLET = os.path.join(HOME, ".claude", "scripts", "pr_gauntlet.sh")
GAUNTLET = os.path.join(HOME, ".claude", "scripts", "gauntlet.sh")
ROLES = ("archi", "code", "qa")
AGENT_DONE = {"done", "skipped", "failed"}
SEVERITY_ORDER = {"critical": 0, "suggestion": 1, "question": 2}

ORDER = [
    ("gauntlet", "2", "Gauntlet sur la branche, worktree conservé", "2_gauntlet.md"),
    ("context", "3", "Le pourquoi avant le comment", "3_contexte.md"),
    ("agents", "4", "Trois relectures en parallèle (archi, code, QA)", "4_agents.md"),
    ("briefing", "5", "Fusion des remarques, briefing, cockpit", "5_briefing.md"),
    ("triage", "6", "Tri des remarques par Thibault", "6_triage.md"),
    ("posted", "7", "Publication validée sur la MR", "7_publication.md"),
    ("synthesis", "8", "Synthèse finale et suppression du worktree", "8_synthese.md"),
]


def die(msg, code=2):
    print(f"[ABORT] {msg}", file=sys.stderr)
    sys.exit(code)


def now():
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def run(cmd, cwd=None, check=True, **kw):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, **kw)
    if check and r.returncode != 0:
        die(f"{' '.join(cmd[:3])}… : {(r.stderr or r.stdout).strip()[:400]}")
    return r


def git(*args, cwd=None, check=True):
    return run(["git", *args], cwd=cwd, check=check).stdout.strip()


def doc_id(s):
    return re.sub(r"[^A-Za-z0-9_\-.~:@+]", "-", s.replace("/", "~"))[:200]


def project_root():
    return git("rev-parse", "--show-toplevel")


def project_name(root):
    common = git("rev-parse", "--path-format=absolute", "--git-common-dir", cwd=root)
    return re.sub(r"[^A-Za-z0-9_.-]", "-", os.path.basename(os.path.dirname(common.rstrip("/")))) or "projet"


# ---------------------------------------------------------------------------
# État
# ---------------------------------------------------------------------------
class Review:
    def __init__(self, slug):
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", slug or ""):
            die(f"slug invalide : {slug!r}")
        self.slug = slug
        self.dir = os.path.join(STATE_ROOT, slug)
        self.path = os.path.join(self.dir, "review.json")
        if not os.path.isfile(self.path):
            die(f"revue inconnue : {slug} (review.sh init d'abord)")
        with open(self.path, encoding="utf-8") as f:
            self.s = json.load(f)

    def save(self):
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(self.s, f, ensure_ascii=False, indent=2)
            f.write("\n")
        os.replace(tmp, self.path)

    def file(self, name):
        return os.path.join(self.dir, name)


def stage_done(s, key):
    if key == "agents":
        agents = s.get("agents") or {}
        return all((agents.get(r) or {}).get("status") in AGENT_DONE for r in ROLES)
    return (s.get("stages") or {}).get(key, {}).get("status") == "PASSED"


def next_step(s):
    for key, step, title, fname in ORDER:
        if not stage_done(s, key):
            return {"key": key, "step": step, "title": title, "file": fname}
    return {"key": "done", "step": "—", "title": "Revue terminée", "file": None}


# ---------------------------------------------------------------------------
# init : résolution de la cible
# ---------------------------------------------------------------------------
def resolve(root, target):
    num = None
    m = re.fullmatch(r"[!#]?(\d+)", target) or re.search(r"(?:merge_requests|pull)/(\d+)", target)
    if m:
        num = m.group(1)
    remote = "origin" if "origin" in git("remote", cwd=root).split() else (git("remote", cwd=root).split() or ["origin"])[0]
    info = {"target": target, "remote": remote, "number": num, "kind": "branch"}
    if num and shutil.which("glab"):
        r = run(["glab", "mr", "view", num, "--output", "json"], cwd=root, check=False)
        if r.returncode == 0 and r.stdout.strip():
            j = json.loads(r.stdout)
            info.update(kind="gitlab", source=j.get("source_branch"), base=j.get("target_branch"),
                        title=j.get("title"), description=j.get("description") or "",
                        author=(j.get("author") or {}).get("username"), url=j.get("web_url"),
                        labels=j.get("labels") or [], diff_refs=j.get("diff_refs") or {})
            return info
    if num and shutil.which("gh"):
        r = run(["gh", "pr", "view", num, "--json", "headRefName,baseRefName,title,body,author,url,labels,headRefOid"],
                cwd=root, check=False)
        if r.returncode == 0 and r.stdout.strip():
            j = json.loads(r.stdout)
            info.update(kind="github", source=j.get("headRefName"), base=j.get("baseRefName"),
                        title=j.get("title"), description=j.get("body") or "",
                        author=(j.get("author") or {}).get("login"), url=j.get("url"),
                        labels=[l.get("name") for l in j.get("labels") or []], head_sha=j.get("headRefOid"))
            return info
    if num:
        die(f"impossible de résoudre {target} : glab/gh absent ou MR introuvable")
    info.update(source=target.replace(f"{remote}/", "", 1), base=None, title=None, description="", author=None, url=None)
    return info


def cmd_init(args):
    if not args:
        die("usage : init <branche | !N | #N | URL>")
    root = project_root()
    info = resolve(root, args[0])
    slug = f"mr-{info['number']}" if info["number"] else re.sub(r"[^A-Za-z0-9_.-]", "_", info["source"])
    d = os.path.join(STATE_ROOT, slug)
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, "review.json")
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            old = json.load(f)
        if old.get("project_root") == root and not stage_done(old, "synthesis"):
            print(f"reprise : revue {slug} déjà en cours (étape suivante : review.sh next {slug})")
            print(json.dumps({"slug": slug, "dir": d, "key": old.get("key")}, ensure_ascii=False))
            return
    project = project_name(root)
    s = {
        "slug": slug, "key": doc_id(f"{project}--{slug}"), "project": project, "project_root": root,
        **info, "created": now(), "dir": d,
        "gauntlet_out": os.path.join(GAUNTLET_OUT_ROOT, re.sub(r"[^A-Za-z0-9_]", "_", (info["source"] or slug).replace("origin/", "", 1))),
        "worktree": None, "stages": {}, "agents": {r: {"status": "pending"} for r in ROLES},
        "triage": {}, "posted": [], "cockpit": {},
    }
    with open(path, "w", encoding="utf-8") as f:
        json.dump(s, f, ensure_ascii=False, indent=2)
    print(f"revue {slug} : {info.get('source')} → {info.get('base') or '(base de la config)'}"
          + (f" · « {info['title']} » par {info['author']}" if info.get("title") else ""))
    print(json.dumps({"slug": slug, "dir": d, "key": s["key"]}, ensure_ascii=False))


# ---------------------------------------------------------------------------
# next / status / bookkeeping
# ---------------------------------------------------------------------------
def cmd_next(r, args):
    n = next_step(r.s)
    s = r.s
    info = {"slug": r.slug, "key": s["key"], **n, "step_file": os.path.join(STEPS_DIR, n["file"]) if n["file"] else None,
            "dir": r.dir, "gauntlet_report": os.path.join(s["gauntlet_out"], "report.md"), "worktree": s.get("worktree"),
            "agents": {k: v.get("status") for k, v in (s.get("agents") or {}).items()}}
    if "--json" in args:
        print(json.dumps(info, ensure_ascii=False, indent=2))
        return
    print(f"étape     : {n['step']} — {n['title']}")
    if info["step_file"]:
        print(f"lis       : {info['step_file']}")
    print(f"revue     : {s.get('source')} → {s.get('base')} · {s.get('title') or 'sans titre'} · clé cockpit {s['key']}")
    print(f"dossier   : {r.dir}")
    if s.get("worktree"):
        print(f"worktree  : {s['worktree']}")
    if os.path.isfile(info["gauntlet_report"]):
        print(f"gauntlet  : {info['gauntlet_report']}")
    print("agents    : " + ", ".join(f"{k} {v}" for k, v in info["agents"].items()))
    if (s.get("cockpit") or {}).get("waiting"):
        print(f"cockpit   : en attente — {s['cockpit']['waiting']}")


def cmd_status(r, args):
    s = r.s
    print(f"Revue {r.slug} · {s.get('source')} → {s.get('base')} · {s.get('url') or ''}")
    for key, step, title, _ in ORDER:
        print(f"- {step} {title} : {'fait' if stage_done(s, key) else '—'}")
    for role in ROLES:
        a = s["agents"].get(role) or {}
        print(f"  · {role} : {a.get('status')} {('— ' + a['summary']) if a.get('summary') else ''}")
    print(f"worktree : {s.get('worktree') or 'aucun'}")


def cmd_pass(r, args):
    r.s.setdefault("stages", {})[args[0]] = {"status": "PASSED", "at": now()}
    r.save()
    print(f"{args[0]} : fait")


def cmd_say(r, args):
    r.s.setdefault("cockpit", {})["waiting"] = args[0] if args and args[0] else None
    r.save()
    print("message du cockpit écrit")


def cmd_agent(r, args):
    if len(args) < 2 or args[0] not in ROLES or args[1] not in ("running", "done", "skipped", "failed"):
        die("usage : agent <slug> <archi|code|qa> <running|done|skipped|failed> [\"<résumé>\"]")
    a = r.s.setdefault("agents", {}).setdefault(args[0], {})
    a.update({"status": args[1], "at": now()})
    if len(args) > 2:
        a["summary"] = args[2]
    if args[1] == "done" and not os.path.isfile(r.file(f"findings_{args[0]}.json")):
        a["status"] = "failed"
        a["summary"] = (a.get("summary") or "") + " (findings_" + args[0] + ".json absent)"
    r.save()
    print(f"agent {args[0]} : {a['status']}")


# ---------------------------------------------------------------------------
# gauntlet / worktree / QA
# ---------------------------------------------------------------------------
def cmd_gauntlet(r, args):
    s = r.s
    old = remove_worktree(s)  # un nouveau run sort un nouveau worktree : l'ancien ne doit pas traîner
    if old:
        print(f"ancien worktree supprimé : {old}")
    cmd = [PR_GAUNTLET, s["target"], "--keep", "--out", s["gauntlet_out"]]
    if s.get("base"):
        cmd += ["--base", s["base"]]
    if "--mutation" in args:
        cmd.append("--mutation")
    p = subprocess.run(cmd, cwd=s["project_root"], capture_output=True, text=True)
    out = p.stdout + p.stderr
    with open(r.file("gauntlet.log"), "w", encoding="utf-8") as f:
        f.write(out)
    m = re.search(r"worktree conservé : (\S.*)$", out, re.M)
    if m:
        s["worktree"] = m.group(1).strip()
    report = read_text(os.path.join(s["gauntlet_out"], "report.md")) or ""
    m = re.search(r"^# Gauntlet PR — `[^`]+` → `([^`]+)`", report, re.M)
    if m and not s.get("base"):
        s["base"] = m.group(1)  # branche sans MR : la base vient de la config, résolue par pr_gauntlet
    s.setdefault("stages", {})["gauntlet"] = {"status": "PASSED", "at": now(), "exit": p.returncode}
    r.save()
    report = os.path.join(s["gauntlet_out"], "report.md")
    print(f"gauntlet : {'vert' if p.returncode == 0 else 'rouge (exit ' + str(p.returncode) + ')'} · rapport {report}")
    print(f"worktree : {s.get('worktree') or 'non conservé (échec avant sa création ?) — voir ' + r.file('gauntlet.log')}")


def cmd_qa(r, args):
    s = r.s
    wt = s.get("worktree")
    if not wt or not os.path.isdir(wt):
        die("pas de worktree : review.sh gauntlet d'abord")
    flows = r.file("maestro")
    if not os.path.isdir(flows) or not any(f.endswith(".yaml") for f in os.listdir(flows)):
        die(f"aucun flow dans {flows}")
    cfg = os.path.join(wt, ".claude", "rules", "feature_pipeline.md")
    app_dir = "."
    try:
        for line in open(cfg, encoding="utf-8"):
            m = re.match(r"\s*app_dir\s*=\s*(\S+)", line)
            if m:
                app_dir = m.group(1)
    except OSError:
        die("config du projet absente dans le worktree : QA impossible")
    env = dict(os.environ, GAUNTLET_MODE="extend", GAUNTLET_PACKAGE=app_dir.rstrip("/") or ".",
               GAUNTLET_FEATURES_ROOT=os.path.join(s["gauntlet_out"], "features"), GAUNTLET_CFG=cfg,
               GAUNTLET_QA_FLOWS=flows)
    if "--all-platforms" not in args:
        env["GAUNTLET_SIZE"] = "S"  # une plateforme : qa.platform_s, sinon la première de qa.platforms
    p = subprocess.run([GAUNTLET, "qa", "review"], cwd=wt, env=env, capture_output=True, text=True)
    shots = os.path.join(s["gauntlet_out"], "features", "review", "qa")
    print((p.stdout + p.stderr)[-3000:])
    print(f"captures : {shots}")
    sys.exit(p.returncode)


def safe_tmp(path):
    tmp = os.environ.get("TMPDIR", "/tmp")
    return any(path.startswith(p) for p in (tmp, "/tmp/", "/private/tmp/", "/var/folders/", "/private/var/folders/"))


def remove_worktree(s):
    """Supprime le worktree de la revue ; rm -rf seulement dans le dossier temporaire créé par pr_gauntlet."""
    wt = s.get("worktree")
    if not wt:
        return None
    run(["git", "worktree", "remove", "--force", wt], cwd=s["project_root"], check=False)
    parent = os.path.dirname(wt)
    if os.path.isdir(parent) and safe_tmp(parent):
        shutil.rmtree(parent, ignore_errors=True)
    elif os.path.isdir(parent):
        print(f"{parent} hors du dossier temporaire : non supprimé")
    run(["git", "worktree", "prune"], cwd=s["project_root"], check=False)
    s.setdefault("worktrees_removed", []).append({"path": wt, "at": now()})
    s["worktree"] = None
    return wt


def cmd_cleanup(r, args):
    s = r.s
    wt = remove_worktree(s)
    print(f"worktree supprimé : {wt}" if wt else "aucun worktree à supprimer")
    s.setdefault("stages", {})["synthesis"] = {"status": "PASSED", "at": now()}
    r.save()
    print(f"conservés : {r.dir} (état, remarques, flows) et {s['gauntlet_out']} (rapport, captures)")


# ---------------------------------------------------------------------------
# Remarques
# ---------------------------------------------------------------------------
REQUIRED = ("severity", "title", "problem")


def cmd_findings(r, args):
    merged, problems, grids, qa = [], [], {}, None
    for role in ROLES:
        f = r.file(f"findings_{role}.json")
        if not os.path.isfile(f):
            continue
        try:
            with open(f, encoding="utf-8") as fh:
                data = json.load(fh)
        except json.JSONDecodeError as e:
            problems.append(f"{role} : JSON invalide ({e})")
            continue
        if data.get("grid"):
            grids[role] = data["grid"]
        if role == "qa":
            qa = {"scenarios": data.get("scenarios") or [], "summary": data.get("summary")}
        for x in data.get("findings") or []:
            missing = [k for k in REQUIRED if not x.get(k)]
            if missing or x.get("severity") not in SEVERITY_ORDER:
                problems.append(f"{role} : remarque « {x.get('title', '?')} » incomplète ({', '.join(missing) or 'severity'})")
                continue
            merged.append({**x, "role": role})
    # même fichier, même ligne, même titre : une seule remarque, rôles fusionnés
    seen, out = {}, []
    for x in merged:
        k = (x.get("file"), x.get("line"), x["title"].strip().lower())
        if k in seen:
            seen[k]["role"] += f"+{x['role']}"
            continue
        seen[k] = x
        out.append(x)
    out.sort(key=lambda x: (SEVERITY_ORDER[x["severity"]], x.get("file") or "~", x.get("line") or 0))
    changed = diff_lines(r)
    for i, x in enumerate(out, 1):
        x["id"] = f"F{i}"
        if x.get("file") and x.get("line"):
            x["snippet"] = snippet(r, x["file"], int(x["line"]), changed.get(x["file"], set()))
        x.setdefault("comment", f"{x['problem']}" + (f"\n\nSuggestion : {x['suggestion']}" if x.get("suggestion") else ""))
    result = {"findings": out, "grids": grids, "qa": qa, "problems": problems, "at": now()}
    with open(r.file("findings.json"), "w", encoding="utf-8") as fh:
        json.dump(result, fh, ensure_ascii=False, indent=2)
    counts = {k: sum(1 for x in out if x["severity"] == k) for k in SEVERITY_ORDER}
    print(f"{len(out)} remarques : {counts['critical']} critiques, {counts['suggestion']} suggestions, {counts['question']} questions")
    for p in problems:
        print(f"[WARN] {p}")


SNIPPET_RADIUS = 7


def file_at_head(r, path):
    """Le fichier tel que la MR le laisse : dans le worktree s'il existe encore, sinon via git show."""
    s = r.s
    wt = s.get("worktree")
    if wt and os.path.isfile(os.path.join(wt, path)):
        return read_text(os.path.join(wt, path))
    for ref in (f"{s['remote']}/{s['source']}", s["source"]):
        p = subprocess.run(["git", "show", f"{ref}:{path}"], cwd=s["project_root"], capture_output=True, text=True)
        if p.returncode == 0:
            return p.stdout
    return None


def snippet(r, path, line, changed):
    """Les lignes autour de la remarque, avec celles que la MR a ajoutées ou modifiées."""
    text = file_at_head(r, path)
    if text is None:
        return None
    lines = text.splitlines()
    start = max(1, line - SNIPPET_RADIUS)
    end = min(len(lines), line + SNIPPET_RADIUS)
    return {"start": start, "lines": [l[:240] for l in lines[start - 1:end]],
            "changed": sorted(n for n in changed if start <= n <= end), "target": line}


def parse_context(text):
    """context.md en sections « ## Titre » : objectif, résumé, ce qui existait, ce qui est promis."""
    out, cur = {}, None
    for line in (text or "").splitlines():
        m = re.match(r"^##\s+(.*)$", line)
        if m:
            cur = m.group(1).strip().lower()
            out[cur] = []
        elif cur:
            out[cur].append(line)
    pick = lambda *names: next(("\n".join(v).strip() for k, v in out.items() if any(n in k for n in names)), None)
    return {"why": pick("pourquoi", "objectif"), "what": pick("ce que fait", "résumé", "resume"),
            "delta": pick("existait"), "visible": pick("visible", "promet"), "neighbor": pick("voisin")}


def load_findings(r):
    try:
        with open(r.file("findings.json"), encoding="utf-8") as fh:
            return json.load(fh)
    except OSError:
        return {"findings": [], "grids": {}, "qa": None, "problems": []}


# ---------------------------------------------------------------------------
# Cockpit
# ---------------------------------------------------------------------------
def read_text(path, limit=None):
    try:
        with open(path, encoding="utf-8") as f:
            t = f.read()
    except OSError:
        return None
    if limit and len(t) > limit:
        t = t[:limit] + f"\n\n… (tronqué, {len(t)} caractères : fichier complet {path})"
    return t


def cmd_cockpit_push(r, args):
    if not args:
        die("usage : cockpit-push <slug> <dossier> [--versions id=v,…]")
    out_dir = os.path.abspath(args[0])
    os.makedirs(out_dir, exist_ok=True)
    versions = {}
    if "--versions" in args:
        for pair in filter(None, (x.strip() for x in args[args.index("--versions") + 1].split(","))):
            k, _, v = pair.partition("=")
            versions[k.strip().replace("@", "~")] = int(v)
    s, f = r.s, load_findings(r)
    n = next_step(s)
    doc = {
        "kind": "review", "project": s["project"], "slug": r.slug, "key": s["key"], "number": s.get("number"),
        "title": s.get("title") or s.get("source"), "author": s.get("author"), "url": s.get("url"),
        "source": s.get("source"), "base": s.get("base"), "labels": s.get("labels") or [],
        "step": {"step": n["step"], "title": n["title"], "key": n["key"]},
        "waiting": (s.get("cockpit") or {}).get("waiting"),
        "agents": {k: {"status": v.get("status"), "summary": v.get("summary")} for k, v in (s.get("agents") or {}).items()},
        "briefing_md": read_text(r.file("briefing.md"), 60_000),
        "context": parse_context(read_text(r.file("context.md"))),
        "description_md": (s.get("description") or "")[:20_000],
        "gauntlet_md": read_text(os.path.join(s["gauntlet_out"], "report.md"), 60_000),
        "findings": f.get("findings") or [], "grids": f.get("grids") or {}, "qa": f.get("qa"),
        "triage": s.get("triage") or {}, "posted": s.get("posted") or [],
        "updated_at": now(),
    }
    fp = os.path.join(out_dir, "review.json")
    with open(fp, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, ensure_ascii=False)
    w = {"op": "set", "collection": "reviews", "doc_id": s["key"], "file_path": fp}
    if s["key"] in versions:
        w["if_version"] = versions[s["key"]]
    manifest = {"key": s["key"], "writes": [w]}
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


def cmd_triage_pull(r, args):
    """Le tri fait dans le cockpit (reviews/<clé>/triage/<id>) → review.json et comments.md."""
    if not args:
        die("usage : triage-pull <slug> <dossier lu par ArtifactData out_dir>")
    tdir = os.path.join(os.path.abspath(args[0]), "reviews", r.s["key"], "triage")
    f = load_findings(r)
    by_id = {x["id"]: x for x in f["findings"]}
    triage = r.s.setdefault("triage", {})
    for fn in sorted(os.listdir(tdir)) if os.path.isdir(tdir) else []:
        if not fn.endswith(".json"):
            continue
        with open(os.path.join(tdir, fn), encoding="utf-8") as fh:
            t = json.load(fh)
        fid = t.get("id") or fn[:-5]
        if fid not in by_id or t.get("decision") not in ("comment", "skip"):
            continue
        triage[fid] = {"decision": t["decision"], "text": (t.get("text") or "").strip() or by_id[fid].get("comment"),
                       "reason": t.get("reason"), "at": t.get("saved_at") or now()}
    if all(x["id"] in triage for x in f["findings"]):
        r.s.setdefault("stages", {})["triage"] = {"status": "PASSED", "at": now()}
    r.save()
    write_comments(r, f, triage)


def write_comments(r, f, triage):
    lines, todo = ["# Commentaires à publier — validation de Thibault requise avant tout envoi", ""], []
    for x in f["findings"]:
        t = triage.get(x["id"])
        if not t or t["decision"] != "comment":
            continue
        where = f"{x['file']}:{x['line']}" if x.get("file") and x.get("line") else (x.get("file") or "commentaire général")
        lines += [f"## {x['id']} · {where}", "", t["text"], ""]
        todo.append(x["id"])
    skipped = [x["id"] for x in f["findings"] if (triage.get(x["id"]) or {}).get("decision") == "skip"]
    pending = [x["id"] for x in f["findings"] if x["id"] not in triage]
    with open(r.file("comments.md"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    print(f"à commenter : {', '.join(todo) or 'aucun'} · écartées : {', '.join(skipped) or 'aucune'}"
          + (f" · NON TRIÉES : {', '.join(pending)}" if pending else ""))
    print(f"texte exact : {r.file('comments.md')}")


# ---------------------------------------------------------------------------
# Publication
# ---------------------------------------------------------------------------
def diff_lines(r):
    """Lignes ajoutées ou modifiées par la MR, par fichier (côté nouvelle version) : où un commentaire en ligne est accepté."""
    s = r.s
    wt = s.get("worktree")
    base = s.get("base")
    cwd = wt if wt and os.path.isdir(wt) else s["project_root"]
    head = "HEAD" if cwd == wt else f"{s['remote']}/{s['source']}"
    if cwd != wt and not git("rev-parse", "-q", "--verify", head, cwd=cwd, check=False):
        head = s["source"]  # branche locale seulement
    mb = ""
    for ref in ((f"{s['remote']}/{base}", base) if base else ()):
        mb = git("merge-base", head, ref, cwd=cwd, check=False)
        if mb:
            break
    if not mb:
        return {}
    out, cur, ln = {}, None, 0
    for line in git("diff", "-U0", mb, head, cwd=cwd, check=False).splitlines():
        if line.startswith("+++ "):
            cur = line[6:] if line.startswith("+++ b/") else None
        elif line.startswith("@@"):
            m = re.search(r"\+(\d+)(?:,(\d+))?", line)
            ln = int(m.group(1))
            count = int(m.group(2) or 1)
            if cur:
                out.setdefault(cur, set()).update(range(ln, ln + count))
    return out


def post_calls(r):
    s, f = r.s, load_findings(r)
    triage = s.get("triage") or {}
    in_diff = diff_lines(r)
    done = {p["id"] for p in s.get("posted") or []}
    calls = []
    for x in f["findings"]:
        t = triage.get(x["id"])
        if not t or t["decision"] != "comment" or x["id"] in done:
            continue
        body = t["text"]
        inline = x.get("file") and x.get("line") and int(x["line"]) in in_diff.get(x["file"], set())
        if s["kind"] == "gitlab":
            if inline:
                refs = s.get("diff_refs") or {}
                cmd = ["glab", "api", "--method", "POST", f"projects/:id/merge_requests/{s['number']}/discussions",
                       "-f", f"body={body}", "-f", "position[position_type]=text",
                       "-f", f"position[base_sha]={refs.get('base_sha')}", "-f", f"position[start_sha]={refs.get('start_sha')}",
                       "-f", f"position[head_sha]={refs.get('head_sha')}", "-f", f"position[new_path]={x['file']}",
                       "-f", f"position[old_path]={x['file']}", "-F", f"position[new_line]={int(x['line'])}"]
            else:
                where = f"`{x['file']}:{x['line']}` — " if x.get("file") and x.get("line") else (f"`{x['file']}` — " if x.get("file") else "")
                cmd = ["glab", "mr", "note", str(s["number"]), "-m", where + body]
        elif s["kind"] == "github":
            if inline:
                cmd = ["gh", "api", "--method", "POST", f"repos/{{owner}}/{{repo}}/pulls/{s['number']}/comments",
                       "-f", f"body={body}", "-f", f"commit_id={s.get('head_sha')}", "-f", f"path={x['file']}",
                       "-F", f"line={int(x['line'])}", "-f", "side=RIGHT"]
            else:
                where = f"`{x['file']}:{x['line']}` — " if x.get("file") and x.get("line") else ""
                cmd = ["gh", "pr", "comment", str(s["number"]), "--body", where + body]
        else:
            continue
        calls.append({"id": x["id"], "inline": bool(inline), "cmd": cmd})
    return calls


def cmd_post(r, args):
    s = r.s
    if s["kind"] not in ("gitlab", "github"):
        die("revue d'une branche sans MR/PR : rien à publier (les remarques sont dans la synthèse)")
    calls = post_calls(r)
    if not calls:
        print("rien à publier (aucune remarque retenue, ou déjà publiées)")
        return
    if "--go" not in args:
        print("APERÇU — rien n'est envoyé. Montre ce texte à Thibault ; --go seulement après son « go » explicite.")
        for c in calls:
            print(f"\n{c['id']} ({'en ligne' if c['inline'] else 'commentaire général'}) :")
            print("  " + " ".join(json.dumps(a, ensure_ascii=False) if " " in a or "\n" in a else a for a in c["cmd"]))
        return
    failed = []
    for c in calls:
        p = subprocess.run(c["cmd"], cwd=s["project_root"], capture_output=True, text=True)
        if p.returncode == 0:
            s.setdefault("posted", []).append({"id": c["id"], "inline": c["inline"], "at": now()})
            r.save()
            print(f"{c['id']} : publié")
        else:
            failed.append(c["id"])
            print(f"{c['id']} : ÉCHEC — {(p.stderr or p.stdout).strip()[:300]}")
    if not failed:
        s.setdefault("stages", {})["posted"] = {"status": "PASSED", "at": now()}
        r.save()
    sys.exit(1 if failed else 0)


COMMANDS = {
    "next": cmd_next, "status": cmd_status, "pass": cmd_pass, "say": cmd_say, "agent": cmd_agent,
    "gauntlet": cmd_gauntlet, "qa": cmd_qa, "cleanup": cmd_cleanup, "findings": cmd_findings,
    "cockpit-push": cmd_cockpit_push, "triage-pull": cmd_triage_pull, "post": cmd_post,
}


def main(argv):
    if not argv or argv[0] in ("-h", "--help") or (argv[0] not in COMMANDS and argv[0] != "init"):
        here = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "review.sh")
        with open(here, encoding="utf-8") as f:
            print("".join(l[2:] for l in f.readlines()[1:] if l.startswith("#")))
        sys.exit(0 if argv and argv[0] in ("-h", "--help") else 2)
    if argv[0] == "init":
        cmd_init(argv[1:])
        return
    if len(argv) < 2:
        die(f"usage : {argv[0]} <slug> …")
    COMMANDS[argv[0]](Review(argv[1]), argv[2:])


if __name__ == "__main__":
    main(sys.argv[1:])
