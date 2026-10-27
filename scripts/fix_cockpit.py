#!/usr/bin/env python3
"""fix_cockpit.py — la page de cockpit d'un /fix et sa carte dans l'Accueil.

À lancer depuis le worktree du fix. L'état vient de .claude/fixes/<nom>/fix.json, repro.json,
diagnosis.md et report.html (écrits par l'orchestrateur, Bastien et fix_gauntlet.sh) : ce script ne les
modifie pas, sauf la clé `cockpit` de fix.json (url de la page, message « en attente de toi »).

  fix_cockpit.py page <nom> <dossier>                       copie de la page titrée « Fix <nom> »
  fix_cockpit.py set-url <nom> <url>                        url de la page publiée
  fix_cockpit.py say <nom> "<texte>"                        « en attente de toi » ("" pour effacer)
  fix_cockpit.py push <nom> <dossier> [--versions id=v,…] [--hub-version N]
                                                            documents de la page (writes) et de l'Accueil (hub_writes)
  fix_cockpit.py page-deleted <nom>                         la page a été supprimée (carte gardée)
"""
import datetime
import hashlib
import json
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
COCKPIT_SRC = os.path.join(HOME, ".claude", "scripts", "cockpit", "cockpit.html")
REPORT_CHUNK = 90_000
IMG_RE = re.compile(r"<img\b[^>]*\bsrc=\"([^\"]*)\"[^>]*>", re.I)


def die(msg, code=2):
    print(f"[ABORT] {msg}", file=sys.stderr)
    sys.exit(code)


def now():
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def git(*args, cwd=None):
    r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


def read_text(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def doc_id(s):
    return re.sub(r"[^A-Za-z0-9_\-.~:@+]", "-", s.replace("/", "~"))[:200]


class Fix:
    def __init__(self, name):
        if not re.fullmatch(r"[a-z][a-z0-9_]*", name or ""):
            die(f"nom de fix invalide : {name!r}")
        self.name = name
        self.root = git("rev-parse", "--show-toplevel") or die("pas dans un repo git")
        self.dir = os.path.join(self.root, ".claude", "fixes", name)
        self.path = os.path.join(self.dir, "fix.json")
        if not os.path.isfile(self.path):
            die(f"fix.json absent : {self.path}")
        with open(self.path, encoding="utf-8") as f:
            self.f = json.load(f)

    def save(self):
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(self.f, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
        os.replace(tmp, self.path)

    def project(self):
        common = git("rev-parse", "--path-format=absolute", "--git-common-dir", cwd=self.root)
        return re.sub(r"[^A-Za-z0-9_.-]", "-", os.path.basename(os.path.dirname(common.rstrip("/")))) or "projet"

    def key(self):
        return doc_id(f"{self.project()}--fix-{self.name}")

    def repro(self):
        try:
            with open(os.path.join(self.dir, "repro.json"), encoding="utf-8") as fh:
                return json.load(fh)
        except (OSError, json.JSONDecodeError):
            return {}


def passed(f, key):
    if key.startswith("hg."):
        return bool((f.get("human_gates") or {}).get(key[3:]))
    st = (f.get("stages") or {}).get(key)
    return (st.get("status") if isinstance(st, dict) else st) in ("PASSED", "SKIPPED")


def steps(fx):
    ui = (fx.repro().get("kind") or fx.f.get("kind")) == "ui"
    order = [("red", "1", "Reproduction (Bastien)"), ("hg.repro", "1", "Ton arrêt : diagnostic, test rouge, plan"),
             ("green", "2", "Correction (Fanny)"), ("review", "3", "Revue (Victor)")]
    if ui:
        order.append(("hg.ui", "4", "Captures avant / après"))
    order.append(("evidence", "5", "Evidence, commits"))
    out, current = [], None
    for k, n, t in order:
        st = (fx.f.get("stages") or {}).get(k) if not k.startswith("hg.") else None
        status = "PASSED" if passed(fx.f, k) else ((st.get("status") if isinstance(st, dict) else None) or "TODO")
        if status != "PASSED" and current is None:
            current = {"key": k, "step": n, "title": t, "status": status}
        out.append({"key": k, "step": n, "title": t, "status": status})
    return out, current or {"key": "done", "step": "—", "title": "Fix terminé", "status": "DONE"}


def report_docs(fx, key, out_dir):
    html = read_text(os.path.join(fx.dir, "report.html"))
    if html is None:
        return None, []
    html = IMG_RE.sub(lambda m: f'<span class="ck-img">capture : {m.group(1)} (dans la session)</span>', html)
    h = hashlib.sha1(html.encode("utf-8")).hexdigest()[:12]
    parts = [html[i:i + REPORT_CHUNK] for i in range(0, len(html), REPORT_CHUNK)] or [""]
    os.makedirs(os.path.join(out_dir, "report"), exist_ok=True)
    writes = []
    for i, part in enumerate(parts):
        fp = os.path.join(out_dir, "report", f"{h}-{i}.json")
        with open(fp, "w", encoding="utf-8") as fh:
            json.dump({"hash": h, "i": i, "html": part}, fh, ensure_ascii=False)
        writes.append({"op": "set", "collection": f"fixes/{key}/report", "doc_id": f"r-{h}-{i}", "file_path": fp})
    mt = datetime.datetime.fromtimestamp(os.path.getmtime(os.path.join(fx.dir, "report.html")), datetime.timezone.utc)
    return {"hash": h, "n": len(parts), "generated_at": mt.replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            "step": (fx.f.get("cockpit") or {}).get("report_step")}, writes


def parse_ask(args):
    """`--ask <id> --options "A|B|C"` : la question du point d'étape, avec ses réponses, pour la page."""
    if "--ask" not in args:
        return args, None
    i = args.index("--ask")
    ask_id = args[i + 1]
    rest = args[:i] + args[i + 2:]
    opts = []
    if "--options" in rest:
        j = rest.index("--options")
        opts = [o.strip() for o in rest[j + 1].split("|") if o.strip()]
        rest = rest[:j] + rest[j + 2:]
    if not re.fullmatch(r"[A-Za-z0-9_.-]{1,60}", ask_id) or not opts:
        die("--ask <id> (lettres, chiffres, _ . -) --options \"Réponse 1|Réponse 2\"")
    return rest, {"id": ask_id, "options": opts, "at": now()}


def cmd_page(fx, args):
    if not args:
        die("usage : page <nom> <dossier>")
    html = read_text(COCKPIT_SRC) or die(f"page source introuvable : {COCKPIT_SRC}")
    html = re.sub(r"<title>.*?</title>", f'<title>Fix {fx.name}</title>\n<meta name="cockpit-role" content="item">', html, count=1)
    os.makedirs(args[0], exist_ok=True)
    path = os.path.join(os.path.abspath(args[0]), f"cockpit-fix-{fx.name}.html")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(html)
    print(path)


def cmd_set_url(fx, args):
    if not args or not args[0].startswith("https://"):
        die("usage : set-url <nom> <url de l'artifact>")
    fx.f.setdefault("cockpit", {})["url"] = args[0]
    fx.save()
    print(f"page du fix : {args[0]}")


def cmd_say(fx, args):
    args, ask = parse_ask(args)
    c = fx.f.setdefault("cockpit", {})
    c["ask"] = ask
    if "--report" in args:
        i = args.index("--report")
        c["report_step"] = args[i + 1]
        args = args[:i] + args[i + 2:]
    c["waiting"] = args[0] if args and args[0] else None
    fx.save()
    print("message du cockpit écrit")


def cmd_page_deleted(fx, args):
    fx.f.setdefault("cockpit", {})["deleted"] = True
    fx.save()
    print("page marquée supprimée : rafraîchis seulement l'Accueil (hub_writes)")


def cmd_push(fx, args):
    if not args:
        die("usage : push <nom> <dossier> [--versions id=v,…] [--hub-version N]")
    out_dir = os.path.abspath(args[0])
    os.makedirs(out_dir, exist_ok=True)
    versions = {}
    if "--versions" in args:
        for pair in filter(None, (x.strip() for x in args[args.index("--versions") + 1].split(","))):
            k, _, v = pair.partition("=")
            versions[k.strip()] = int(v)
    key, f, rp = fx.key(), fx.f, fx.repro()
    st, cur = steps(fx)
    done = cur["key"] == "done"
    report, report_writes = report_docs(fx, key, out_dir)
    plan = rp.get("fix_plan") or {}
    gates = f.get("human_gates") or {}
    decisions = []
    if gates.get("plan"):
        choice = {"proposed": "plan proposé", "alternative": "alternative", "other": "autre voie"}.get(gates["plan"].get("choice"), gates["plan"].get("choice"))
        decisions.append({"at": gates["plan"].get("at"), "kind": "gate", "text": f"Plan validé ({choice})"})
    if gates.get("repro"):
        decisions.append({"at": gates["repro"].get("at"), "kind": "gate", "text": f"Diagnostic et test validés, gelés ({str(f.get('freeze_sha') or '')[:8]})"})
    for d in f.get("plan_deviations") or []:
        decisions.append({"at": d.get("at"), "kind": "contract", "text": f"Écart au plan accepté : {d.get('reason')}"})
    for sid, sg in (f.get("suggestions") or {}).items():
        if sg.get("decision") in ("applied", "skipped"):
            decisions.append({"at": sg.get("at"), "kind": "suggestion", "text": f"Suggestion {sid} {'retenue' if sg['decision'] == 'applied' else 'écartée'}"})
    if gates.get("ui"):
        decisions.append({"at": gates["ui"].get("at"), "kind": "gate", "text": "Captures avant / après validées"})
    cockpit = f.get("cockpit") or {}
    doc = {
        "kind": "fix", "project": fx.project(), "feature": fx.name, "key": key,
        "title": f.get("description") or fx.name, "branch": f.get("branch"),
        "step": cur, "waiting": None if done else cockpit.get("waiting"),
        "ask": cockpit.get("ask") if cockpit.get("waiting") and not done else None, "stages": st,
        "decisions": sorted(decisions, key=lambda d: d.get("at") or ""),
        "diagnosis_md": (read_text(os.path.join(fx.dir, "diagnosis.md")) or "")[:60_000] or None,
        "root_cause": rp.get("root_cause"), "root_cause_location": rp.get("root_cause_location"),
        "miss_reason": rp.get("miss_reason"),
        "plan": {k: plan.get(k) for k in ("layer", "approach", "files", "rejected")} if plan else None,
        "report": report, "updated_at": now(),
    }
    fp = os.path.join(out_dir, "fix.json")
    with open(fp, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, ensure_ascii=False)
    w = {"op": "set", "collection": "fixes", "doc_id": key, "file_path": fp}
    if key in versions:
        w["if_version"] = versions[key]
    ev = (f.get("stages") or {}).get("evidence") or {}
    index = {"kind": "fix", "key": key, "project": fx.project(), "title": f.get("description") or fx.name,
             "url": None if cockpit.get("deleted") else cockpit.get("url"), "page_deleted": bool(cockpit.get("deleted")),
             "step": {"step": cur["step"], "title": cur["title"]}, "waiting": doc["waiting"], "done": done,
             "done_at": ev.get("at") if done else None,
             "outcome": (f"cause : {rp.get('root_cause')}"[:200] if rp.get("root_cause") else "evidence prête") if done else None,
             "updated_at": now()}
    ip = os.path.join(out_dir, "index.json")
    with open(ip, "w", encoding="utf-8") as fh:
        json.dump(index, fh, ensure_ascii=False)
    hub = {"op": "set", "collection": "index", "doc_id": key, "file_path": ip}
    if "--hub-version" in args:
        hub["if_version"] = int(args[args.index("--hub-version") + 1])
    print(json.dumps({"key": key, "page": cockpit.get("url"), "writes": [w] + report_writes, "hub_writes": [hub]},
                     ensure_ascii=False, indent=2))


COMMANDS = {"page": cmd_page, "set-url": cmd_set_url, "say": cmd_say, "push": cmd_push, "page-deleted": cmd_page_deleted}

if __name__ == "__main__":
    a = sys.argv[1:]
    if len(a) < 2 or a[0] not in COMMANDS:
        print(__doc__)
        sys.exit(0 if a and a[0] in ("-h", "--help") else 2)
    COMMANDS[a[0]](Fix(a[1]), a[2:])
