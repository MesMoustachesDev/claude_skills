#!/usr/bin/env python3
"""review.py — état et mécanique de /reviewPR. Usage : voir ../review.sh.

La cible, le worktree, l'état des trois agents, la fusion des remarques, le tri fait dans le cockpit et
la publication sur la MR vivent ici, pas dans le prompt de l'orchestrateur.
"""
import datetime
import difflib
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
    ("preflight", "1", "Préflight : ce qui manque, demandé avant de lancer quoi que ce soit", "1_preflight.md"),
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
    for area, d in ((s.get("preflight") or {}).get("decisions") or {}).items():
        print(f"décidé    : {area} — {d['decision']}")
    if n["key"] == "preflight" and s.get("preflight") and preflight_open(s):
        print(f"à trancher: {', '.join(preflight_open(s))}")
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
    if args[0] == "preflight" and preflight_open(r.s):
        die(f"préflight non tranché : {', '.join(preflight_open(r.s))} — review.sh decide d'abord")
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


def project_flutter(wt):
    """La commande flutter du projet (clé `flutter` de la config, ex. « fvm flutter »)."""
    try:
        for line in open(os.path.join(wt, ".claude", "rules", "feature_pipeline.md"), encoding="utf-8"):
            m = re.match(r"\s*flutter\s*=\s*(.+?)\s*$", line)
            if m:
                return m.group(1).split()
    except OSError:
        pass
    return ["flutter"]


def package_dir(r, package):
    wt = r.s.get("worktree")
    if not wt or not os.path.isdir(wt):
        die("pas de worktree : review.sh gauntlet d'abord")
    d = os.path.normpath(os.path.join(wt, package))
    if not d.startswith(os.path.normpath(wt)) or not os.path.isfile(os.path.join(d, "pubspec.yaml")):
        die(f"{package} n'est pas un package Dart du worktree (pas de pubspec.yaml)")
    return wt, d


def flutter_test(r, wt, pkg_dir, targets, log_name):
    # Même PATH que le gauntlet : les exécutables pub (fvm…) d'abord.
    env = dict(os.environ, PATH=os.pathsep.join([os.path.join(HOME, ".pub-cache", "bin"), os.environ.get("PATH", "")]))
    cmd = [*project_flutter(wt), "test", *targets, "--reporter", "expanded"]
    try:
        p = subprocess.run(cmd, cwd=pkg_dir, capture_output=True, text=True, stdin=subprocess.DEVNULL, env=env)
    except FileNotFoundError:
        print(f"« {cmd[0]} » introuvable : clé `flutter` de feature_pipeline.md, ou SDK absent de ce PATH — tests non joués")
        return 127
    log = r.file(log_name)
    with open(log, "w", encoding="utf-8") as f:
        f.write(p.stdout + p.stderr)
    tail = [l for l in (p.stdout + p.stderr).splitlines() if re.search(r"\+\d+|All tests passed|Some tests failed|\[E\]|FAILED|Error", l)]
    print("\n".join(tail[-25:]))
    print(f"{'vert' if p.returncode == 0 else 'rouge (exit ' + str(p.returncode) + ')'} · log complet : {log}")
    return p.returncode


def cmd_run_tests(r, args):
    """Rejoue des tests EXISTANTS du worktree (ceux qui prouvent un scénario promis par la MR)."""
    if len(args) < 2:
        die("usage : run-tests <slug> <package> <test/…_test.dart>…")
    wt, d = package_dir(r, args[0])
    for t in args[1:]:
        if not os.path.isfile(os.path.join(d, t)):
            die(f"test introuvable dans {args[0]} : {t}")
    sys.exit(flutter_test(r, wt, d, args[1:], f"run_tests_{doc_id(args[0])}.log"))


def cmd_probe(r, args):
    """Joue des tests JETABLES écrits par Maëlle dans <revue>/probes/ : copiés le temps du run dans
    <package>/test/_review_probe/ du worktree, puis retirés. Le repo n'est jamais modifié."""
    if not args:
        die("usage : probe <slug> <package> [fichiers de probes/…]")
    wt, d = package_dir(r, args[0])
    src = r.file("probes")
    files = args[1:] or (sorted(f for f in os.listdir(src) if f.endswith("_test.dart")) if os.path.isdir(src) else [])
    if not files:
        die(f"aucun test jetable dans {src} (fichiers *_test.dart)")
    dest = os.path.join(d, "test", "_review_probe")
    shutil.rmtree(dest, ignore_errors=True)
    os.makedirs(dest)
    try:
        for f in files:
            shutil.copy(os.path.join(src, os.path.basename(f)), dest)
        rc = flutter_test(r, wt, d, ["test/_review_probe"], f"probe_{doc_id(args[0])}.log")
    finally:
        shutil.rmtree(dest, ignore_errors=True)
    sys.exit(rc)


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
            qa = {"scenarios": data.get("scenarios") or [], "summary": data.get("summary"), "device": data.get("device")}
        for x in data.get("findings") or []:
            missing = [k for k in REQUIRED if not x.get(k)]
            if missing or x.get("severity") not in SEVERITY_ORDER:
                problems.append(f"{role} : remarque « {x.get('title', '?')} » incomplète ({', '.join(missing) or 'severity'})")
                continue
            merged.append({**x, "role": role})
    # Doublons : même fichier, lignes proches, et titre ou problème qui se ressemblent → une seule remarque
    # (la plus grave garde son texte, les autres vont dans `also`). Puis les fusions décidées à la main
    # (review.sh merge), mémorisées par clé et réappliquées à chaque fusion.
    merged.sort(key=lambda x: SEVERITY_ORDER[x["severity"]])
    out = []
    for x in merged:
        twin = next((y for y in out if same_issue(x, y)), None)
        if twin:
            absorb(twin, x)
        else:
            out.append(x)
    for group in r.s.get("merges") or []:
        keys = [list(k) for k in group]
        items = [y for y in out if finding_key(y) in keys or any(finding_key(a) in keys for a in y.get("also") or [])]
        if len(items) > 1:
            items.sort(key=lambda y: SEVERITY_ORDER[y["severity"]])
            for y in items[1:]:
                absorb(items[0], y)
                out.remove(y)
    out.sort(key=lambda x: (SEVERITY_ORDER[x["severity"]], x.get("file") or "~", x.get("line") or 0))
    changed = diff_lines(r)
    # Numéros stables : une remarque garde son F<n> d'une fusion à l'autre (le tri y est accroché) ;
    # une remarque fusionnée laisse un trou, elle ne décale pas les autres.
    ids = r.s.setdefault("finding_ids", {})
    nxt = max([int(v[1:]) for v in ids.values()] + [0]) + 1
    for x in out:
        k = json.dumps(finding_key(x), ensure_ascii=False)
        if k not in ids:
            ids[k] = f"F{nxt}"
            nxt += 1
        x["id"] = ids[k]
    r.save()
    for x in out:
        if x.get("file") and x.get("line"):
            x["snippet"] = (diff_snippet(r, x["file"], int(x["line"]))
                            or snippet(r, x["file"], int(x["line"]), changed.get(x["file"], set())))
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


def finding_key(x):
    return [x.get("file"), x.get("line"), (x.get("title") or "").strip().lower()]


def similar(a, b, threshold=0.55):
    a, b = (a or "").lower(), (b or "").lower()
    return bool(a and b) and difflib.SequenceMatcher(None, a, b).ratio() >= threshold


def same_issue(x, y):
    if x.get("file") != y.get("file"):
        return False
    lx, ly = x.get("line"), y.get("line")
    near = (lx is None and ly is None) or (lx is not None and ly is not None and abs(int(lx) - int(ly)) <= 3)
    if not near:
        return False
    return (x["title"].strip().lower() == y["title"].strip().lower() or similar(x["title"], y["title"])
            or similar(x.get("problem"), y.get("problem"), 0.6))


def absorb(primary, other):
    """`other` est le même problème que `primary` : il disparaît de la liste, son point de vue reste lisible."""
    roles = set(primary["role"].split("+")) | set(other["role"].split("+"))
    primary["role"] = "+".join(r for r in ("archi", "code", "qa") if r in roles)
    also = primary.setdefault("also", [])
    also.append({k: other.get(k) for k in ("role", "severity", "title", "file", "line", "problem", "evidence", "suggestion")})
    also.extend(other.get("also") or [])
    if other.get("evidence") and other["evidence"] not in (primary.get("evidence") or ""):
        primary["evidence"] = (primary.get("evidence") or "") + ("\n" if primary.get("evidence") else "") + other["evidence"]


def cmd_merge(r, args):
    """Fusionne des remarques que seul le sens rapproche : review.sh merge <slug> F2 F3 [F4…]. La première
    (la plus grave) reste ; le tri déjà fait sur les autres est retiré."""
    if len(args) < 2:
        die("usage : merge <slug> F<n> F<m> [F<k>…]")
    f = load_findings(r)
    by_id = {x["id"]: x for x in f["findings"]}
    missing = [i for i in args if i not in by_id]
    if missing:
        die(f"remarques inconnues : {', '.join(missing)}")
    group = [finding_key(by_id[i]) for i in args]
    r.s.setdefault("merges", []).append(group)
    triage = r.s.get("triage") or {}
    dropped = [i for i in args[1:] if triage.pop(i, None)]
    r.save()
    cmd_findings(r, [])
    if dropped:
        print(f"tri retiré sur {', '.join(dropped)} (fusionnées) : seul le tri de la remarque restante compte")


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


VOICE_FILE = os.path.join(HOME, ".claude", "skills", "ecrire-linkedin", "voix.md")
VOICE_REVIEW = os.path.join(HOME, ".claude", "pipeline", "review", "voix_revue.md")


def voice_text():
    """Ma voix pour un commentaire de MR : voix_revue.md, plus les « Règles de style » de voix.md (source unique)."""
    review = read_text(VOICE_REVIEW) or ""
    voix = read_text(VOICE_FILE) or ""
    m = re.search(r"^## Règles de style\n(.*?)(?=^## |\Z)", voix, re.M | re.S)
    rules = m.group(1).strip() if m else ""
    return (review + ("\n\n## Règles de style (voix.md)\n" + rules if rules else "")).strip() or None


# Vérification mécanique d'un commentaire (même esprit que skills/ecrire-linkedin/verifier.py, adapté à la revue)
CHECK_ERRORS = [
    (r"—|–", "tiret cadratin ou demi-cadratin"), (r"’", "apostrophe typographique"), (r"…", "points de suspension en un caractère"),
    (r"[→←⇒➜➡•▸►▪◦✓✔]", "symbole non tapé au clavier"),
    (r"c'est un peu (le|la|les|comme)\b|c'est comme\b|le problème n'est pas|ce qui fait la différence|\blevier\b|\bcrucial|"
     r"game changer|changer la donne|\bau final\b|\bfinalement\b|\ben réalité\b|\bessentiel|\bfondamental", "tournure IA"),
    (r"\bnous\b|\bnotre\b", "« nous » (écris en ton nom)"),
    (r"super travail|petite remarque|n'hésite pas|beau travail|bravo", "formule creuse"),
    (r"coder avec ses pieds|branquignol|\brelou\b|c'est quoi ce délire|t'as cru|on se calme|faire joujou|pignouf|mdr", "pique hors revue (voix_revue.md)"),
]


def comment_issues(text):
    low = (text or "").lower()
    return [label for rx, label in CHECK_ERRORS if re.search(rx, low)]


def cmd_check_comments(r, args):
    f = load_findings(r)
    triage = r.s.get("triage") or {}
    bad = 0
    for x in f["findings"]:
        t = triage.get(x["id"])
        if not t or t["decision"] != "comment":
            continue
        issues = comment_issues(t.get("text"))
        if issues:
            bad += 1
            print(f"{x['id']} : {', '.join(issues)}")
    print("commentaires conformes à ta voix" if not bad else f"{bad} commentaire(s) à corriger avant de les montrer")
    sys.exit(1 if bad else 0)


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
        "preflight": s.get("preflight"),
        "voice": voice_text(),
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
def diff_range(r):
    """(dossier où lancer git, merge-base, tête de la MR) : le worktree s'il existe, sinon le repo du projet."""
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
    return cwd, mb, head


def diff_snippet(r, path, line, radius=None):
    """L'extrait du diff autour de la remarque : contexte, lignes SUPPRIMÉES et ajoutées par la MR, avec leurs
    numéros (ancien / nouveau). None si la ligne visée n'est pas dans un hunk (le code autour n'a pas bougé)."""
    radius = radius or SNIPPET_RADIUS
    cwd, mb, head = diff_range(r)
    if not mb:
        return None
    out = git("diff", f"-U{radius}", mb, head, "--", path, cwd=cwd, check=False)
    hunks, cur, o, n = [], None, 0, 0
    for l in out.splitlines():
        m = re.match(r"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@", l)
        if m:
            o, n = int(m.group(1)), int(m.group(2))
            cur = []
            hunks.append(cur)
            continue
        if cur is None or l.startswith("\\"):
            continue
        if l.startswith("+"):
            cur.append({"o": None, "n": n, "k": "+", "t": l[1:][:240]}); n += 1
        elif l.startswith("-"):
            cur.append({"o": o, "n": None, "k": "-", "t": l[1:][:240]}); o += 1
        else:
            cur.append({"o": o, "n": n, "k": " ", "t": l[1:][:240]}); o += 1; n += 1
    for h in hunks:
        news = [x["n"] for x in h if x["n"] is not None]
        if news and min(news) <= line <= max(news):
            # fenêtre de `radius` lignes de la nouvelle version autour de la cible, suppressions comprises
            keep = [x for x in h if x["n"] is None or abs(x["n"] - line) <= radius]
            # une suppression n'est gardée que si elle tombe entre deux lignes gardées
            idx = [i for i, x in enumerate(h) if x in keep and x["n"] is not None]
            lo, hi = (min(idx), max(idx)) if idx else (0, len(h) - 1)
            rows = [x for i, x in enumerate(h) if lo <= i <= hi]
            return {"rows": rows, "target": line}
    return None


def diff_lines(r):
    """Lignes ajoutées ou modifiées par la MR, par fichier (côté nouvelle version) : où un commentaire en ligne est accepté."""
    cwd, mb, head = diff_range(r)
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


# ---------------------------------------------------------------------------
# Préflight : tout ce qui empêcherait une partie de la revue, vérifié et tranché AVANT le gauntlet
# ---------------------------------------------------------------------------
PLACEHOLDER = re.compile(r"com\.example|\{[^}]*\}|<[^>]+>|TODO|à renseigner", re.I)


def cfg_value(text, key):
    for block in re.findall(r"```ini\n(.*?)```", text or "", re.S):
        for line in block.splitlines():
            m = re.match(rf"\s*{re.escape(key)}\s*=\s*(.*?)\s*$", line)
            if m:
                return m.group(1)
    return ""


def find_graph(root):
    if os.path.isfile(os.path.join(root, "graphify-out", "graph.json")):
        return os.path.join(root, "graphify-out", "graph.json")
    for d in sorted(os.listdir(root)):
        g = os.path.join(root, d, "graphify-out", "graph.json")
        if os.path.isfile(g):
            return g
    return None


def cmd_preflight(r, args):
    s, root = r.s, r.s["project_root"]
    items = []
    add = lambda id_, area, status, detail, fix=None: items.append(
        {"id": id_, "area": area, "status": status, "detail": detail, "fix": fix})
    cfg_path = os.path.join(root, ".claude", "rules", "feature_pipeline.md")
    cfg = read_text(cfg_path)
    if cfg is None:
        add("config", "projet", "warn", "pas de .claude/rules/feature_pipeline.md : le gauntlet prend le template générique "
            "(pas de QA device, seuils par défaut)", "/feature init dans le projet")
    # Outillage : le doctor du gauntlet (SDK épinglé, outils Dart du gauntlet, linter, maestro, plateformes QA)
    if cfg is not None:
        p = subprocess.run([GAUNTLET, "doctor"], cwd=root, capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=600)
        section = "outils"
        for line in re.sub(r"\x1b\[[0-9;]*m", "", p.stdout + p.stderr).splitlines():
            m = re.match(r"\s*== (.+?) ==", line)
            if m:
                section = m.group(1)
                continue
            m = re.match(r"\[(FAIL|WARN)\]\s+(.*)", line)
            if not m or section == "résumé":
                continue
            area = "qa" if section.startswith("plateformes") else "outillage"
            label = m.group(2)
            if re.search(r"create_feature_rules|brick|mason|package_path", label) or ("mutation_test" in label and "--mutation" not in args):
                continue  # utiles à /feature, pas à une revue
            fix = label.split(" — ", 1)[1] if " — " in label else None
            add(f"doctor:{len(items)}", area, "block" if m.group(1) == "FAIL" else "warn", label, fix)
    # QA : appIds réels, compte de test référencé (le doctor ne voit pas le compte)
    if cfg is not None:
        platforms = [x.strip() for x in cfg_value(cfg, "qa.platforms").split(",") if x.strip()]
        if not platforms:
            add("qa:platforms", "qa", "block", "qa.platforms vide : pas de QA sur device")
        for pf in platforms:
            v = cfg_value(cfg, f"{pf}.app_id")
            if (not v or PLACEHOLDER.search(v)) and not any(f"{pf}.app_id" in i["detail"] for i in items):
                add(f"qa:{pf}.app_id", "qa", "block", f"{pf}.app_id = « {v or 'vide'} » : valeur de template")
        notes = cfg.split("## Notes pour les agents", 1)[-1] if "## Notes pour les agents" in cfg else ""
        acct = next((l for l in notes.splitlines() if re.search(r"compte de test", l, re.I)), "")
        if not acct or PLACEHOLDER.search(acct):
            add("qa:account", "qa", "warn", "compte de test QA non référencé dans « Notes pour les agents » : "
                "scénarios connectés impossibles sur device")
    # Graphe graphify : sans lui, pas d'impact calculé ni d'ordre de lecture
    if not find_graph(root):
        add("graphify", "graphe", "warn", "pas de graphe graphify dans le projet : pas d'impact hors package calculé "
            "ni d'ordre de lecture (Alice lira les consommateurs à la main)", "/graphify sur le projet")
    # Publication : l'outil de la forge doit être authentifié, sinon on le découvre à l'étape 7
    tool = {"gitlab": ["glab", "auth", "status"], "github": ["gh", "auth", "status"]}.get(s["kind"])
    if tool:
        ok = shutil.which(tool[0]) and subprocess.run(tool, cwd=root, capture_output=True).returncode == 0
        if not ok:
            add("forge:auth", "publication", "block", f"{tool[0]} non authentifié : les commentaires ne pourront pas être publiés",
                f"{tool[0]} auth login")
    s["preflight"] = {"at": now(), "items": items, "decisions": (s.get("preflight") or {}).get("decisions", {})}
    r.save()
    with open(r.file("preflight.json"), "w", encoding="utf-8") as f:
        json.dump(s["preflight"], f, ensure_ascii=False, indent=2)
    if not items:
        print("préflight : tout est prêt (outillage, QA, graphe, publication)")
        return
    by = {}
    for it in items:
        by.setdefault(it["area"], []).append(it)
    for area, its in by.items():
        print(f"\n{area} :")
        for it in its:
            print(f"  [{it['status'].upper()}] {it['id']} — {it['detail']}" + (f"  → {it['fix']}" if it.get("fix") else ""))
    print(f"\n{sum(1 for i in items if i['status'] == 'block')} bloquants, {sum(1 for i in items if i['status'] == 'warn')} avertissements"
          " — à trancher avec Thibault avant le gauntlet (étape 1)")


def cmd_decide(r, args):
    """Trace la décision de Thibault sur un domaine du préflight (qa, graphe, outillage, publication, projet)."""
    if len(args) < 2:
        die("usage : decide <slug> <domaine> \"<décision>\"")
    pf = r.s.setdefault("preflight", {"items": []})
    pf.setdefault("decisions", {})[args[0]] = {"decision": args[1], "at": now()}
    r.save()
    print(f"décision {args[0]} : {args[1]}")


def preflight_open(s):
    pf = s.get("preflight") or {}
    areas = {i["area"] for i in pf.get("items") or []}
    return sorted(areas - set((pf.get("decisions") or {}).keys()))


COMMANDS = {
    "next": cmd_next, "status": cmd_status, "pass": cmd_pass, "say": cmd_say, "agent": cmd_agent,
    "gauntlet": cmd_gauntlet, "qa": cmd_qa, "run-tests": cmd_run_tests, "probe": cmd_probe, "cleanup": cmd_cleanup, "findings": cmd_findings,
    "cockpit-push": cmd_cockpit_push, "preflight": cmd_preflight, "merge": cmd_merge,
    "check-comments": cmd_check_comments, "decide": cmd_decide, "triage-pull": cmd_triage_pull, "post": cmd_post,
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
