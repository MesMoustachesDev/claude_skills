#!/usr/bin/env python3
"""pipeline.py — état et comptabilité du feature pipeline. Usage : voir ../pipeline.sh.

Tout ce qui est déterministe dans /feature (ordre de reprise, étapes sautées, compteurs de boucles,
commits de contrats et de gel, documents du cockpit) vit ici, pas dans le prompt de l'orchestrateur.
"""
import datetime
import fnmatch
import hashlib
import json
import os
import re
import subprocess
import sys

STEPS_DIR = os.path.expanduser("~/.claude/pipeline/feature/steps")

# Ordre de reprise : (clé d'état, étape, titre, fichier d'étape, agent).
# Une clé « hg.x » est un point d'étape (human_gates.x), les autres sont des stages.
ORDER = [
    ("cadrage", "0b", "Cadrage fonctionnel", "0b_cadrage.md", "Sophie (feature-specifier, mode cadrage), puis toi avec Thibault"),
    ("contracts_draft", "0c", "Brouillon de contrats", "0c_contracts_draft.md", "Arthur (feature-architect, mode brouillon)"),
    ("dedup", "0d", "Roue réinventée sur le brouillon", "0d_dedup.md", "Denis (feature-dedup)"),
    ("hg.contracts", "0e", "Point d'étape « contrats » : Thibault les écrit", "0e_contracts.md", "Thibault (+ Arthur en mode application)"),
    ("spec", "1", "Spec, critique, point d'étape « spec »", "1_spec.md", "Sophie (feature-specifier) puis Camille (feature-spec-critic)"),
    ("contracts", "2", "Complétion du scaffold", "2_scaffold.md", "Arthur (feature-architect, mode complétion)"),
    ("red", "3", "Tests", "3_tests.md", "Théo (feature-test-writer)"),
    ("hg.tests", "3b", "Revue des tests, point d'étape « tests », gel", "3_tests.md", "Gaëlle (feature-test-reviewer)"),
    ("green", "4", "Implémentation", "4_impl.md", "Ivan (feature-implementer)"),
    ("clean", "5", "Nettoyage", "5_clean.md", "Nina (feature-cleaner)"),
    ("dedup_clean", "5b", "Roue réinventée, second passage", "5_clean.md", "Denis (feature-dedup)"),
    ("review", "6", "Revue", "6_review.md", "Romain (feature-reviewer)"),
    ("hg.suggestions", "6", "Suggestions de revue à trancher", "6_review.md", "toi avec Thibault"),
    ("harden", "7", "Durcissement", "7_harden.md", "Hugo (feature-hardener)"),
    ("qa", "8", "QA", "8_qa.md", "Quentin (feature-qa)"),
    ("hg.tour", "8b", "Point d'étape « visite guidée »", "8b_tour.md", "toi avec Thibault"),
    ("evidence", "9", "Evidence, commits, MR", "9_evidence.md", "toi"),
]
DONE = {"PASSED", "SKIPPED"}
LOOP_MAX = {"spec": {"S": 0, "M": 2, "L": 0}, "tests": 2, "review": 2, "dedup_clean": 2, "tour": 2}
REFREEZE_CAUSES = {"hygiene", "technique", "contrat", "spec", "interne"}
GATE_LABELS = {
    "cadrage": "Cadrage validé", "contracts": "Contrats écrits", "spec": "Spec validée",
    "tests": "Tests validés et gelés", "suggestions": "Suggestions de revue tranchées", "tour": "Visite guidée validée",
}


def die(msg, code=2):
    print(f"[ABORT] {msg}", file=sys.stderr)
    sys.exit(code)


def now():
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def git(*args, cwd=None, check=True):
    r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    if check and r.returncode != 0:
        die(f"git {' '.join(args)} : {r.stderr.strip()}")
    return r.stdout.strip()


# ---------------------------------------------------------------------------
# Contexte
# ---------------------------------------------------------------------------
class Ctx:
    def __init__(self, name, must_exist=True):
        if not re.fullmatch(r"[a-z][a-z0-9_]*", name or ""):
            die(f"nom de feature invalide : {name!r}")
        self.name = name
        self.root = git("rev-parse", "--show-toplevel")
        self.dir = os.path.join(self.root, ".claude", "features", name)
        self.path = os.path.join(self.dir, "pipeline.json")
        self.cfg_file = os.path.join(self.root, ".claude", "rules", "feature_pipeline.md")
        if must_exist and not os.path.isfile(self.path):
            die(f"pipeline.json absent : {self.path} (nouvelle feature : étape 0, puis pipeline.sh init)")
        self.p = self._load() if os.path.isfile(self.path) else {}

    def _load(self):
        with open(self.path, encoding="utf-8") as f:
            return json.load(f)

    def save(self):
        os.makedirs(self.dir, exist_ok=True)
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(self.p, f, ensure_ascii=False, indent=2)
            f.write("\n")
        os.replace(tmp, self.path)

    def cfg(self, key, default=""):
        try:
            text = open(self.cfg_file, encoding="utf-8").read()
        except OSError:
            return default
        for block in re.findall(r"```ini\n(.*?)```", text, re.S):
            for line in block.splitlines():
                m = re.match(rf"\s*{re.escape(key)}\s*=\s*(.*?)\s*$", line)
                if m and m.group(1):
                    return m.group(1)
        return default

    def cfg_list(self, key):
        return [v.strip() for v in self.cfg(key).split(",") if v.strip()]

    @property
    def size(self):
        return self.p.get("size") or "M"

    @property
    def package(self):
        pkg = self.p.get("package") or self.cfg("package_path", "features/{name}").replace("{name}", self.name)
        return pkg.rstrip("/")

    def base(self):
        return self.p.get("base") or self.cfg("base_branch", "develop")

    def project(self):
        common = git("rev-parse", "--path-format=absolute", "--git-common-dir", cwd=self.root)
        name = os.path.basename(os.path.dirname(common.rstrip("/")))
        return re.sub(r"[^A-Za-z0-9_.-]", "-", name) or "projet"


# ---------------------------------------------------------------------------
# État
# ---------------------------------------------------------------------------
def state_of(p, key):
    """Statut d'une clé d'ORDER : PASSED, SKIPPED, RED, FAILED, ou None (pas encore jouée)."""
    if key.startswith("hg."):
        return "PASSED" if (p.get("human_gates") or {}).get(key[3:]) else None
    st = (p.get("stages") or {}).get(key)
    if not st:
        return None
    status = st.get("status") if isinstance(st, dict) else st
    if key == "contracts":
        # stages.contracts antérieur à la validation de la spec = reste de 0c/0e (voir 0. Préconditions).
        spec_at = ((p.get("human_gates") or {}).get("spec") or {}).get("at")
        if not spec_at or (isinstance(st, dict) and (st.get("at") or "") < spec_at):
            return None
    return status


def find_pipeline(c, name):
    """(pipeline.json, dossier de la feature) d'une autre feature de ce repo : ici, ou dans un des worktrees."""
    roots = [c.root]
    porcelain = git("worktree", "list", "--porcelain", cwd=c.root, check=False)
    roots += [l[len("worktree "):] for l in porcelain.splitlines() if l.startswith("worktree ")]
    for r in dict.fromkeys(roots):
        d = os.path.join(r, ".claude", "features", name)
        f = os.path.join(d, "pipeline.json")
        if os.path.isfile(f):
            try:
                with open(f, encoding="utf-8") as fh:
                    return json.load(fh), d
            except (OSError, json.JSONDecodeError):
                continue
    return None, None


def split_status(c):
    """État de chaque sous-feature d'une feature découpée (L), lu dans son propre pipeline.json."""
    out = []
    for i, sub in enumerate(c.p.get("split") or []):
        name = sub.get("name", "")
        sp, _ = find_pipeline(c, name)
        if sp is None:
            state = {"started": False, "done": False, "step": None, "title": "pas démarrée", "status": None}
        else:
            n = next_step(sp)
            state = {"started": True, "done": n["key"] == "done", "step": n["step"], "title": n["title"], "status": n["status"]}
        out.append({"index": i + 1, "name": name, "package": sub.get("package"), "size": sub.get("size"),
                    "depends_on": sub.get("depends_on") or [], "key": None, **state})
    return out


def next_step(p):
    if not p:
        return {"key": None, "step": "0", "title": "Préconditions puis cadrage (nouvelle feature)",
                "file": "00_preconditions.md", "agent": "toi", "status": None, "extra_files": ["0b_cadrage.md"]}
    if p.get("size") == "L" and p.get("split"):
        return {"key": "split", "step": "L", "title": "Feature découpée : ne rien lancer", "file": "0b_cadrage.md",
                "agent": "—", "status": "SPLIT"}
    for key, step, title, fname, agent in ORDER:
        status = state_of(p, key)
        if status in DONE:
            continue
        return {"key": key, "step": step, "title": title, "file": fname, "agent": agent, "status": status}
    return {"key": "done", "step": "—", "title": "Pipeline terminé", "file": None, "agent": "—", "status": "DONE"}


def inputs(c):
    """Faits à passer aux agents : chemins existants et valeurs de pipeline.json."""
    rel = lambda f: os.path.relpath(os.path.join(c.dir, f), c.root)
    out = {}
    for f in ("cadrage.md", "spec.md", "archi.json", "tests.md", "dedup.md", "review.json", "mutants.md", "qa.md"):
        if os.path.isfile(os.path.join(c.dir, f)):
            out[f] = rel(f)
    con = c.p.get("contracts") or {}
    if con.get("sha"):
        out["contracts.sha"] = con["sha"]
    elif con.get("draft_sha"):
        out["contracts.draft_sha"] = con["draft_sha"]
    if con.get("files"):
        out["contracts.files"] = con["files"]
    for k in ("tests_freeze_sha", "graphify_graph", "pass_base"):
        if c.p.get(k):
            out[k] = c.p[k]
    return out


def cmd_next(c, args):
    n = next_step(c.p)
    attempts = (c.p.get("attempts") or {})
    profile = n["key"] if n["key"] and not n["key"].startswith("hg.") else None
    info = {
        "feature": c.name, **n,
        "step_file": os.path.join(STEPS_DIR, n["file"]) if n["file"] else None,
        "size": c.size, "mode": c.p.get("mode"), "package": c.p.get("package"),
        "attempts": attempts.get(profile) if profile else None,
        "loops": c.p.get("loops") or {},
        "inputs": inputs(c) if c.p else {},
    }
    if "--json" in args:
        print(json.dumps(info, ensure_ascii=False, indent=2))
        return
    print(f"étape     : {n['step']} — {n['title']}")
    if info["step_file"]:
        extra = "".join(f", puis {os.path.join(STEPS_DIR, f)}" for f in n.get("extra_files", []))
        print(f"lis       : {info['step_file']}{extra}")
    print(f"agent     : {n['agent']}")
    if c.p:
        print(f"gabarit   : {c.size} · mode : {c.p.get('mode')} · package : {c.p.get('package')}")
    if n["status"] in ("RED", "FAILED"):
        print(f"état      : {n['status']} ({info['attempts'] or 0} tentatives) — FAILED : point imprévu, Thibault décide ; ne rejoue pas en silence")
    if n["key"] == "split":
        for s_ in split_status(c):
            state = "terminée" if s_["done"] else (f"étape {s_['step']} — {s_['title']}" if s_["started"] else "pas démarrée")
            deps = f" (après {', '.join(s_['depends_on'])})" if s_["depends_on"] else ""
            print(f"sous-feature {s_['index']}/{len(c.p['split'])} : {s_['name']}{deps} — {state}")
    if c.p.get("parent"):
        pp, _ = find_pipeline(c, c.p["parent"])
        names = [x.get("name") for x in (pp or {}).get("split") or []]
        pos = f"{names.index(c.name) + 1}/{len(names)}" if c.name in names else "?"
        print(f"parent    : sous-feature {pos} de {c.p['parent']}")
    if n["key"] == "hg.suggestions":
        print("note      : revue verte, il reste à montrer les suggestions et à poser human_gates.suggestions")
    for k, v in info["inputs"].items():
        v = ", ".join(v) if isinstance(v, list) else v
        print(f"entrée    : {k} = {v}")
    note = (c.p.get("cockpit") or {}).get("waiting")
    if note:
        print(f"cockpit   : en attente — {note}")


def cmd_status(c, args):
    p = c.p
    print(f"Feature {c.name} · gabarit {c.size} ({p.get('size_reason') or '—'}) · mode {p.get('mode')} · package {p.get('package')}")
    issue = p.get("issue")
    if issue:
        print(f"Issue : #{issue.get('iid')} {issue.get('url', '')}")
    print()
    print("| Étape | Clé | Statut | Tentatives | Date |")
    print("|---|---|---|---|---|")
    attempts = p.get("attempts") or {}
    for key, step, title, _, _ in ORDER:
        status = state_of(p, key) or "—"
        if key.startswith("hg."):
            at = ((p.get("human_gates") or {}).get(key[3:]) or {}).get("at", "")
            tries = ""
        else:
            st = (p.get("stages") or {}).get(key) or {}
            at = st.get("at", "") if isinstance(st, dict) else ""
            if isinstance(st, dict) and st.get("status") == "SKIPPED":
                status = f"SKIPPED ({st.get('reason', '')})"
            tries = attempts.get(key, "")
        print(f"| {step} {title} | {key} | {status} | {tries} | {at} |")
    if p.get("split"):
        print("\nDécoupage :")
        for s in p["split"]:
            print(f"- {s.get('name')} ({s.get('package')}, {s.get('size')}) dépend de {s.get('depends_on') or '—'}")
    n = next_step(p)
    print(f"\nProchaine étape : {n['step']} — {n['title']}")


# ---------------------------------------------------------------------------
# Écritures simples
# ---------------------------------------------------------------------------
def cmd_init(c, args):
    if c.p:
        die(f"{c.path} existe déjà : reprise, pas init")
    opts = dict(zip(args[::2], args[1::2]))
    mode = opts.get("--mode", "create")
    if mode not in ("create", "extend"):
        die("--mode create|extend")
    c.p = {
        "feature": c.name, "mode": mode, "package": opts.get("--package") or c.package,
        "branch": f"feature/{c.name}", "base": opts.get("--base") or c.base(),
        "size": None, "size_reason": None, "size_changes": [], "split": [],
        "created": now(), "stages": {}, "human_gates": {}, "attempts": {}, "contracts": {},
        "tests_freeze_sha": None, "refreezes": [], "suggestions": {}, "debt": [], "loops": {}, "accepted": [],
        "issue": None, "graphify_graph": None,
    }
    parent = opts.get("--parent")
    if parent:
        pp, _ = find_pipeline(c, parent)
        names = [x.get("name") for x in (pp or {}).get("split") or []]
        if pp is None:
            die(f"feature parente introuvable : {parent} (aucun pipeline.json dans ce repo ni ses worktrees)")
        if c.name not in names:
            die(f"{c.name} n'est pas dans le découpage de {parent} : {', '.join(names) or 'aucune sous-feature'}")
        c.p["parent"] = parent
    c.save()
    print(f"pipeline.json créé : {os.path.relpath(c.path, c.root)}")
    if parent:
        _, pdir = find_pipeline(c, parent)
        extract = os.path.join(pdir, "split", f"{c.name}.md")
        print(f"sous-feature {names.index(c.name) + 1}/{len(names)} de {parent} · extrait du cadrage : {extract}")


def cmd_size(c, args):
    if len(args) < 2 or args[0] not in ("S", "M", "L"):
        die("usage : size <nom> S|M|L \"<raison>\"")
    new, reason = args[0], args[1]
    old = c.p.get("size")
    if old and old != new:
        c.p.setdefault("size_changes", []).append({"at": now(), "from": old, "to": new, "reason": reason})
    c.p["size"], c.p["size_reason"] = new, reason
    c.save()
    rerun = []
    if old == "S" and new == "M":
        rerun = [k for k, st in (c.p.get("stages") or {}).items() if isinstance(st, dict) and st.get("status") == "SKIPPED"]
    print(f"gabarit : {old or '—'} → {new}" + (f" ; étapes SKIPPED à rejouer avant d'aller plus loin : {', '.join(rerun)}" if rerun else ""))


def cmd_pass(c, args):
    c.p.setdefault("stages", {})[args[0]] = {"status": "PASSED", "at": now()}
    c.save()
    print(f"stages.{args[0]} = PASSED")


def cmd_skip(c, args):
    if len(args) < 2:
        die("usage : skip <nom> <étape> \"<raison>\"")
    c.p.setdefault("stages", {})[args[0]] = {"status": "SKIPPED", "at": now(), "reason": args[1]}
    c.save()
    print(f"stages.{args[0]} = SKIPPED ({args[1]})")


def parse_kv(items):
    out = {}
    for it in items:
        k, _, v = it.partition("=")
        try:
            out[k] = json.loads(v)
        except json.JSONDecodeError:
            out[k] = v
    return out


def cmd_gate(c, args):
    gate = args[0]
    c.p.setdefault("human_gates", {})[gate] = {"at": now(), "by": "user", **parse_kv(args[1:])}
    c.save()
    print(f"human_gates.{gate} posé")


def cmd_loop(c, args):
    name = args[0]
    mx = LOOP_MAX.get(name, 2)
    if isinstance(mx, dict):
        mx = mx.get(c.size, 2)
    loops = c.p.setdefault("loops", {})
    loops[name] = loops.get(name, 0) + 1
    c.save()
    if loops[name] > mx:
        print(f"loops.{name} = {loops[name]} > {mx} : plafond dépassé, plus de relance — montre les bloquants à Thibault, il tranche")
        sys.exit(3)
    print(f"loops.{name} = {loops[name]}/{mx}")


def cmd_debt(c, args):
    if len(args) < 3:
        die("usage : debt <nom> <source> <fichier> \"<problème>\" [--line N]")
    entry = {"source": args[0], "file": args[1], "issue": args[2]}
    if "--line" in args:
        entry["line"] = int(args[args.index("--line") + 1])
    debt = c.p.setdefault("debt", [])
    if entry not in debt:
        debt.append(entry)
    c.save()
    print(f"dette ajoutée ({len(debt)} au total)")


def cmd_accept(c, args):
    if len(args) < 2:
        die("usage : accept <nom> <étape> \"<raison>\"")
    c.p.setdefault("accepted", []).append({"stage": args[0], "at": now(), "reason": args[1]})
    c.save()
    print(f"acceptation tracée ({args[0]})")


def cmd_set(c, args):
    key, raw = args[0], args[1]
    try:
        val = json.loads(raw)
    except json.JSONDecodeError:
        val = raw
    node = c.p
    parts = key.split(".")
    for part in parts[:-1]:
        node = node.setdefault(part, {})
    node[parts[-1]] = val
    c.save()
    print(f"{key} écrit")


def cmd_say(c, args):
    if "--report" in args:
        i = args.index("--report")
        c.p.setdefault("cockpit", {})["report_step"] = args[i + 1]
        args = args[:i] + args[i + 2:]
    c.p.setdefault("cockpit", {})["waiting"] = args[0] if args and args[0] else None
    c.p["cockpit"]["at"] = now()
    c.save()
    print("message du cockpit écrit")


def cmd_after_architect(c, args):
    """0c/0e : le hook d'Arthur écrit stages.contracts, qui appartient à l'étape 2."""
    if state_of(c.p, "hg.spec") == "PASSED":
        print("spec validée : stages.contracts appartient bien à l'étape 2, rien à déplacer")
        return
    stages = c.p.setdefault("stages", {})
    if "contracts" in stages:
        stages["contracts_draft"] = stages.pop("contracts")
    c.p.setdefault("attempts", {})["contracts"] = 0
    c.save()
    st = stages.get("contracts_draft") or {}
    print(f"stages.contracts_draft = {st.get('status', '—')} ; attempts.contracts = 0")
    if st.get("status") == "FAILED":
        print("brouillon FAILED : point imprévu (rapport d'Arthur + 40 dernières lignes de last_contracts.log)")


# ---------------------------------------------------------------------------
# Git : contrats, gel
# ---------------------------------------------------------------------------
CONTRACT_GLOBS = ("*/domain/*", "*/keys.dart", "*_event.dart", "*_state.dart")


def repo_of(c, rel_path):
    """(racine du repo qui contient rel_path, préfixe relatif à c.root). Gère les submodules."""
    d = os.path.join(c.root, rel_path)
    while not os.path.isdir(d):
        d = os.path.dirname(d)
    top = git("rev-parse", "--show-toplevel", cwd=d)
    prefix = os.path.relpath(top, c.root)
    return top, "" if prefix == "." else prefix + "/"


def merge_base(c, cwd):
    base = c.base()
    for ref in (f"origin/{base}", base):
        mb = git("merge-base", "HEAD", ref, cwd=cwd, check=False)
        if mb:
            return mb
    die(f"merge-base introuvable avec {base}")


def changed_files(c, rel_dir, since):
    """Fichiers modifiés depuis <since> sous rel_dir, arbre de travail et non suivis compris (relatifs à c.root)."""
    top, pre = repo_of(c, rel_dir)
    inner = rel_dir[len(pre):] if pre and rel_dir.startswith(pre) else rel_dir
    names = git("diff", "--name-only", since, "--", inner or ".", cwd=top).splitlines()
    names += git("ls-files", "--others", "--exclude-standard", "--", inner or ".", cwd=top).splitlines()
    return sorted({pre + n for n in names if n})


def compute_contract_files(c):
    lib = f"{c.package}/lib"
    top, _ = repo_of(c, lib)
    since = merge_base(c, top)
    files = [f for f in changed_files(c, lib, since) if os.path.isfile(os.path.join(c.root, f))]
    return [f for f in files if any(fnmatch.fnmatch(f, g) for g in CONTRACT_GLOBS)]


def cmd_contracts_files(c, args):
    files = compute_contract_files(c)
    c.p.setdefault("contracts", {})["files"] = files
    c.save()
    print("\n".join(files) or "(aucun fichier de contrat)")


def allowed_for_commit(c, f):
    app = c.cfg("app_dir", ".").strip("/")
    roots = {"pubspec.yaml", "pubspec.lock"}
    if app and app != ".":
        roots |= {f"{app}/pubspec.yaml", f"{app}/pubspec.lock"}
    if f.startswith(c.package + "/") or f in roots:
        return True
    for g in c.cfg_list("writes.extra"):
        if fnmatch.fnmatch(f, g) or (g.endswith("/**") and f.startswith(g[:-2])):
            return True
    return False


def commit(c, files, message, allow_empty=False):
    """git add des seuls fichiers donnés (jamais -A), groupés par repo (submodules), puis commit."""
    by_repo = {}
    for f in files:
        top, pre = repo_of(c, os.path.dirname(f) or ".")
        by_repo.setdefault((top, pre), []).append(f[len(pre):])
    if not by_repo:
        by_repo[(c.root, "")] = []
    shas = []
    for (top, _), fs in by_repo.items():
        if fs:
            git("add", "--", *fs, cwd=top)
        args = ["commit", "-m", message] + (["--allow-empty"] if allow_empty else [])
        r = subprocess.run(["git", *args], cwd=top, capture_output=True, text=True)
        if r.returncode != 0 and "nothing to commit" not in (r.stdout + r.stderr):
            die(f"commit refusé dans {top} : {(r.stderr or r.stdout).strip()}")
        shas.append(git("rev-parse", "HEAD", cwd=top))
    return shas[-1]


def cmd_commit_contracts(c, args):
    if not args or args[0] not in ("draft", "thibault", "reedit"):
        die("usage : commit-contracts <nom> draft|thibault|reedit [\"<quoi>\"] [fichiers…]")
    kind, rest = args[0], args[1:]
    con = c.p.setdefault("contracts", {})
    if kind == "draft":
        top, _ = repo_of(c, c.package)
        since = merge_base(c, top)
        files = [f for f in changed_files(c, c.package, since) + changed_files(c, ".", since)
                 if allowed_for_commit(c, f)]
        sha = commit(c, sorted(set(files)), f"chore({c.name}): contracts draft (Arthur)")
        con["draft_sha"] = sha
        con["files"] = compute_contract_files(c)
        print(f"brouillon commité : {sha[:10]} · {len(con['files'])} fichiers de contrats")
    elif kind == "thibault":
        if not con.get("draft_sha"):
            die("contracts.draft_sha absent : le brouillon n'a pas été commité")
        files = [f for f in changed_files(c, ".", con["draft_sha"]) if allowed_for_commit(c, f)]
        sha = commit(c, files, f"feat({c.name}): contracts (by Thibault)", allow_empty=True)
        con["sha"] = sha
        con["files"] = compute_contract_files(c)
        c.p.setdefault("human_gates", {})["contracts"] = {"at": now(), "by": "user", "sha": sha}
        print(f"contrats de Thibault commités : {sha[:10]} · {len(files)} fichiers modifiés depuis le brouillon")
    else:
        what, files = (rest[0] if rest else ""), rest[1:]
        if not what or not files:
            die("reedit : donne « <quoi> » et les seuls fichiers que Thibault a édités")
        bad = [f for f in files if not allowed_for_commit(c, f)]
        if bad:
            die(f"hors périmètre de la feature : {', '.join(bad)}")
        sha = commit(c, files, f"feat({c.name}): contracts (by Thibault) — {what}")
        con["sha"] = sha
        known = set(con.get("files") or [])
        con["files"] = sorted(known | set(compute_contract_files(c)))
        con.setdefault("reedits", []).append({"at": now(), "sha": sha, "what": what, "files": files})
        print(f"réédition commitée : {sha[:10]}")
    c.save()


def cmd_freeze(c, args):
    test_dir = f"{c.package}/test"
    files = changed_files(c, test_dir, "HEAD") + [f for f in changed_files(c, c.package, "HEAD") if f.endswith("pubspec.yaml")]
    sha = commit(c, sorted(set(files)), f"test({c.name}): acceptance and unit tests (frozen)", allow_empty=True)
    c.p["tests_freeze_sha"] = sha
    c.p.setdefault("human_gates", {})["tests"] = {"at": now(), "by": "user", "sha": sha}
    c.p.setdefault("stages", {})["red"] = {"status": "PASSED", "at": now()}
    c.save()
    print(f"tests gelés : {sha[:10]} ({len(files)} fichiers)")


def cmd_refreeze(c, args):
    if len(args) < 2 or args[0] not in REFREEZE_CAUSES:
        die(f"usage : refreeze <nom> <{'|'.join(sorted(REFREEZE_CAUSES))}> <étape> [\"<quoi>\"]")
    cause, stage = args[0], args[1]
    what = args[2] if len(args) > 2 else cause
    files = changed_files(c, f"{c.package}/test", "HEAD")
    if not files:
        die("aucun test modifié : rien à re-geler")
    sha = commit(c, files, f"test({c.name}): {what} (refrozen)")
    c.p["tests_freeze_sha"] = sha
    c.p.setdefault("refreezes", []).append({"at": now(), "sha": sha, "cause": cause, "files": files, "stage": stage})
    c.save()
    print(f"re-gel : {sha[:10]} · cause {cause} · {len(files)} fichiers")


# ---------------------------------------------------------------------------
# Cockpit (artifact partagé, documents écrits via ArtifactData file_path)
# ---------------------------------------------------------------------------
def doc_id(s):
    return re.sub(r"[^A-Za-z0-9_\-.~:@+]", "-", s.replace("/", "~"))[:200]


def sha1(text):
    return hashlib.sha1(text.encode("utf-8")).hexdigest()


def read_text(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def show(c, rev, path):
    top, pre = repo_of(c, os.path.dirname(path) or ".")
    r = subprocess.run(["git", "show", f"{rev}:{path[len(pre):]}"], cwd=top, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def decisions_log(c):
    p, out = c.p, []
    for gate, label in GATE_LABELS.items():
        g = (p.get("human_gates") or {}).get(gate)
        if not g:
            continue
        detail = []
        if gate == "cadrage":
            detail = [f"gabarit {g.get('size') or p.get('size') or '?'}", f"package {g.get('package') or p.get('package')}"]
        if g.get("sha"):
            detail.append(f"commit {str(g['sha'])[:8]}")
        if g.get("returned"):
            detail.append(f"étapes renvoyées : {', '.join(map(str, g['returned']))}")
        out.append({"at": g.get("at"), "kind": "gate", "text": label + (f" ({', '.join(detail)})" if detail else "")})
    if p.get("size_reason"):
        out.append({"at": p.get("created"), "kind": "size", "text": f"Gabarit {p.get('size')} : {p['size_reason']}"})
    for ch in p.get("size_changes") or []:
        out.append({"at": ch.get("at"), "kind": "size", "text": f"Reclassement {ch.get('from')} → {ch.get('to')} : {ch.get('reason')}"})
    for sid, s in (p.get("suggestions") or {}).items():
        if s.get("decision") in ("applied", "skipped"):
            verb = "retenue" if s["decision"] == "applied" else "écartée"
            out.append({"at": s.get("at"), "kind": "suggestion", "text": f"Suggestion {sid} {verb}" + (f" : {s['note']}" if s.get("note") else "")})
    for a in p.get("accepted") or []:
        out.append({"at": a.get("at"), "kind": "accept", "text": f"Accepté à l'étape {a.get('stage')} : {a.get('reason')}"})
    for r in (p.get("contracts") or {}).get("reedits") or []:
        out.append({"at": r.get("at"), "kind": "contract", "text": f"Contrat modifié : {r.get('what')}"})
    top, _ = repo_of(c, c.package)
    log = git("log", "--format=%H%x1f%cI%x1f%s", "--grep=by Thibault", "-n", "20", cwd=top, check=False)
    gate_shas = {str(g.get("sha")) for g in (p.get("human_gates") or {}).values() if isinstance(g, dict) and g.get("sha")}
    gate_shas |= {str(r.get("sha")) for r in (p.get("contracts") or {}).get("reedits") or []}
    for line in log.splitlines():
        h, at, subject = (line.split("\x1f") + ["", ""])[:3]
        if subject and h not in gate_shas:
            out.append({"at": at, "kind": "commit", "text": subject})
    return sorted(out, key=lambda e: e.get("at") or "")


REPORT_CHUNK = 90_000  # caractères par document (un document db fait au plus 256 Ko une fois sérialisé)
IMG_RE = re.compile(r"<img\b[^>]*\bsrc=\"([^\"]*)\"[^>]*>", re.I)


def report_docs(c, key, out_dir):
    """Le dernier report.html de la feature, découpé en morceaux. Les ids portent l'empreinte du
    rapport : un nouveau rapport crée de nouveaux documents, jamais d'écrasement (pas de version à lire)."""
    path = os.path.join(c.dir, "report.html")
    html = read_text(path)
    if html is None:
        return None, []
    # Les captures sont des fichiers locaux : illisibles depuis l'artifact, remplacées par leur chemin.
    html = IMG_RE.sub(lambda m: f'<span class="ck-img">capture : {m.group(1)} (dans la session)</span>', html)
    h = sha1(html)[:12]
    parts = [html[i:i + REPORT_CHUNK] for i in range(0, len(html), REPORT_CHUNK)] or [""]
    os.makedirs(os.path.join(out_dir, "report"), exist_ok=True)
    writes = []
    for i, part in enumerate(parts):
        fp = os.path.join(out_dir, "report", f"{h}-{i}.json")
        with open(fp, "w", encoding="utf-8") as fh:
            json.dump({"hash": h, "i": i, "html": part}, fh, ensure_ascii=False)
        writes.append({"op": "set", "collection": f"features/{key}/report", "doc_id": f"r-{h}-{i}", "file_path": fp})
    mtime = datetime.datetime.fromtimestamp(os.path.getmtime(path), datetime.timezone.utc).replace(microsecond=0)
    meta = {"hash": h, "n": len(parts), "generated_at": mtime.isoformat().replace("+00:00", "Z"),
            "step": (c.p.get("cockpit") or {}).get("report_step")}
    return meta, writes


TREE_MAX = 3000


def package_tree(c):
    """Fichiers du package (suivis et nouveaux, hors ignorés), relatifs à c.root : l'arbre du cockpit."""
    top, pre = repo_of(c, c.package)
    inner = c.package[len(pre):] if pre else c.package
    names = git("ls-files", "-co", "--exclude-standard", "--", inner, cwd=top).splitlines()
    files = sorted({pre + n for n in names if n})
    return files[:TREE_MAX]


def cmd_cockpit_push(c, args):
    if not args:
        die("usage : cockpit-push <nom> <dossier>")
    out_dir = os.path.abspath(args[0])
    versions = {}
    if "--versions" in args:
        raw = args[args.index("--versions") + 1]
        for pair in filter(None, (x.strip() for x in raw.split(","))):
            k, _, v = pair.partition("=")
            versions[k.strip().replace("@", "~")] = int(v)
    key = doc_id(f"{c.project()}--{c.name}")
    os.makedirs(os.path.join(out_dir, "contracts"), exist_ok=True)
    con = c.p.get("contracts") or {}
    files = con.get("files") or []
    draft_rev = con.get("draft_sha")
    entries, writes = [], []
    for f in files:
        current = read_text(os.path.join(c.root, f))
        if current is None:
            continue
        draft = show(c, draft_rev, f) if draft_rev else None
        decisions = [{"line": i + 1, "text": l.strip()} for i, l in enumerate(current.splitlines()) if "DÉCISION (Thibault" in l]
        fid = doc_id(f)
        doc = {"path": f, "draft": draft if draft is not None else "", "has_draft": draft is not None,
               "current": current, "current_hash": sha1(current), "decisions": decisions, "updated_at": now()}
        fp = os.path.join(out_dir, "contracts", fid + ".json")
        with open(fp, "w", encoding="utf-8") as fh:
            json.dump(doc, fh, ensure_ascii=False)
        entries.append({"id": fid, "path": f, "decisions": len(decisions),
                        "changed": draft is not None and draft != current})
        writes.append({"op": "set", "collection": f"features/{key}/contracts", "doc_id": fid, "file_path": fp})
    stages = []
    for k, step, title, _, _ in ORDER:
        st = (c.p.get("stages") or {}).get(k) if not k.startswith("hg.") else None
        stages.append({"key": k, "step": step, "title": title, "status": state_of(c.p, k) or "TODO",
                       "reason": st.get("reason") if isinstance(st, dict) else None})
    tree = package_tree(c)
    report, report_writes = report_docs(c, key, out_dir)
    writes += report_writes
    n = next_step(c.p)
    feature = {
        "project": c.project(), "feature": c.name, "key": key, "branch": c.p.get("branch"),
        "size": c.size, "size_reason": c.p.get("size_reason"), "mode": c.p.get("mode"), "package": c.package,
        "step": {"step": n["step"], "title": n["title"], "status": n["status"]},
        "waiting": (c.p.get("cockpit") or {}).get("waiting"),
        "stages": stages, "decisions": decisions_log(c),
        "contracts": {"draft_sha": draft_rev, "sha": con.get("sha"), "files": entries},
        "tree": tree,
        "report": report,
        "split": None,
        "parent": None,
        "updated_at": now(),
    }
    project = c.project()
    if c.p.get("split"):
        subs = split_status(c)
        for s_ in subs:
            s_["key"] = doc_id(f"{project}--{s_['name']}")
        feature["split"] = subs
    if c.p.get("parent"):
        pp, _ = find_pipeline(c, c.p["parent"])
        names = [x.get("name") for x in (pp or {}).get("split") or []]
        feature["parent"] = {"name": c.p["parent"], "key": doc_id(f"{project}--{c.p['parent']}"),
                             "index": names.index(c.name) + 1 if c.name in names else None, "total": len(names)}
    fp = os.path.join(out_dir, "feature.json")
    with open(fp, "w", encoding="utf-8") as fh:
        json.dump(feature, fh, ensure_ascii=False)
    writes.insert(0, {"op": "set", "collection": "features", "doc_id": key, "file_path": fp})
    for w in writes:
        if w["doc_id"] in versions:
            w["if_version"] = versions[w["doc_id"]]
    manifest = {"key": key, "writes": writes}
    with open(os.path.join(out_dir, "writes.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, ensure_ascii=False, indent=2)
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


def _edit_fields(doc):
    """Un document lu via ArtifactData out_dir : les champs sont à la racine ou sous data/fields."""
    for k in ("data", "fields", "document"):
        if isinstance(doc.get(k), dict) and "content" in doc[k]:
            return doc[k], doc.get("version")
    return doc, doc.get("version") or doc.get("_version")


def cmd_cockpit_pull(c, args):
    if not args:
        die("usage : cockpit-pull <nom> <dossier lu par ArtifactData out_dir>")
    in_dir = os.path.abspath(args[0])
    key = doc_id(f"{c.project()}--{c.name}")
    edits_dir = os.path.join(in_dir, "features", key, "edits")
    allowed = set((c.p.get("contracts") or {}).get("files") or [])
    applied, conflicts, ignored, writes = [], [], [], []
    out_dir = os.path.join(in_dir, "_applied")
    os.makedirs(out_dir, exist_ok=True)
    for fn in sorted(os.listdir(edits_dir)) if os.path.isdir(edits_dir) else []:
        if not fn.endswith(".json"):
            continue
        with open(os.path.join(edits_dir, fn), encoding="utf-8") as fh:
            raw = json.load(fh)
        e, version = _edit_fields(raw)
        if e.get("status") != "pending":
            continue
        path = e.get("path", "")
        if path not in allowed:
            ignored.append(f"{path} : pas un fichier de contracts.files")
            continue
        target = os.path.join(c.root, path)
        current = read_text(target) or ""
        if e.get("base_hash") and e["base_hash"] != sha1(current):
            conflicts.append(f"{path} : le fichier a changé sur disque depuis l'ouverture dans le cockpit")
            status = "conflict"
        else:
            with open(target, "w", encoding="utf-8") as fh:
                fh.write(e.get("content", ""))
            applied.append(path)
            status = "applied"
        fid = doc_id(path)  # le nom du fichier lu épelle « ~ » en « @ » : l'id vient du chemin
        fp = os.path.join(out_dir, fid + ".json")
        with open(fp, "w", encoding="utf-8") as fh:
            json.dump({"status": status, "resolved_at": now()}, fh)
        w = {"op": "update", "collection": f"features/{key}/edits", "doc_id": fid, "file_path": fp}
        if version:
            w["if_version"] = version
        else:
            w["if_version"] = "<version donnée par la lecture ArtifactData>"
        writes.append(w)
    print(json.dumps({"applied": applied, "conflicts": conflicts, "ignored": ignored, "writes": writes},
                     ensure_ascii=False, indent=2))


COMMANDS = {
    "next": cmd_next, "status": cmd_status, "init": cmd_init, "size": cmd_size, "pass": cmd_pass,
    "skip": cmd_skip, "gate": cmd_gate, "loop": cmd_loop, "debt": cmd_debt, "accept": cmd_accept, "set": cmd_set, "say": cmd_say,
    "after-architect": cmd_after_architect, "contracts-files": cmd_contracts_files,
    "commit-contracts": cmd_commit_contracts, "freeze": cmd_freeze, "refreeze": cmd_refreeze,
    "cockpit-push": cmd_cockpit_push, "cockpit-pull": cmd_cockpit_pull,
}


def main(argv):
    if len(argv) < 2 or argv[0] in ("-h", "--help") or argv[0] not in COMMANDS:
        here = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "pipeline.sh")
        with open(here, encoding="utf-8") as f:
            print("".join(l[2:] for l in f.readlines()[1:] if l.startswith("#")))
        sys.exit(0 if len(argv) and argv[0] in ("-h", "--help") else 2)
    cmd, name, rest = argv[0], argv[1], argv[2:]
    c = Ctx(name, must_exist=cmd not in ("init", "next", "status"))
    if cmd == "status" and not c.p:
        die("pipeline.json absent : aucune feature de ce nom dans ce worktree")
    COMMANDS[cmd](c, rest)


if __name__ == "__main__":
    main(sys.argv[1:])
