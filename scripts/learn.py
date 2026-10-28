#!/usr/bin/env python3
"""learn.py — mémoire des erreurs récurrentes de /feature et /fix (contrat : ~/.claude/pipeline/learn.md).

Ce qui est déterministe est ici : extraire les signaux d'un run, tenir le registre, compter les
récurrences. Ce qui demande du jugement (rattacher un signal à un pattern, rédiger la règle) reste à
l'orchestrateur.

  learn.py extract <dossier du run>          signaux pas encore étiquetés (JSON) + patterns connus
  learn.py record <labels.json>              enregistre les étiquettes {"run": clé, "patterns": {slug: desc}, "labels": [{id, pattern}]}
  learn.py candidates [--min-runs N]         patterns récurrents à proposer (défaut : 2 runs distincts)
  learn.py examples <slug>                   signaux rattachés à un pattern
  learn.py promote <slug> <fichier> "<règle>"   la règle a été ajoutée là, sur accord de Thibault
  learn.py reject <slug> "<raison>"          refusé ; reproposé seulement après 2 runs de plus
  learn.py scan <racine>...                  runs terminés (evidence.md) pas encore passés par learn
"""
import datetime
import glob
import json
import os
import sys

HOME = os.environ.get("LEARN_HOME") or os.path.expanduser("~/.claude/pipeline/lessons")
LEDGER = os.path.join(HOME, "ledger.jsonl")
PATTERNS = os.path.join(HOME, "patterns.json")
PENDING = os.path.join(HOME, "pending")
NOISE = "noise"


def die(msg):
    print(f"learn: {msg}", file=sys.stderr)
    sys.exit(2)


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_json(path, default=None):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return default


def save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(tmp, path)


def ledger():
    rows = []
    if os.path.isfile(LEDGER):
        with open(LEDGER, encoding="utf-8") as f:
            rows = [json.loads(line) for line in f if line.strip()]
    return rows


def run_identity(run_dir):
    """(clé, projet, pipeline, nom) depuis <racine>/.claude/{features,fixes}/<nom>/."""
    run_dir = os.path.abspath(run_dir.rstrip("/"))
    name = os.path.basename(run_dir)
    kind_dir = os.path.basename(os.path.dirname(run_dir))
    if kind_dir not in ("features", "fixes"):
        die(f"pas un dossier de run (.claude/features/<nom> ou .claude/fixes/<nom>) : {run_dir}")
    root = os.path.dirname(os.path.dirname(os.path.dirname(run_dir)))
    # Un run dans un worktree appartient au projet du checkout principal.
    if "/.claude/worktrees/" in root:
        root = root.split("/.claude/worktrees/")[0]
    project = os.path.basename(root)
    pipeline = "feature" if kind_dir == "features" else "fix"
    return f"{project}/{pipeline}/{name}", project, pipeline, name


def verdict_files(run_dir, filename):
    """Le verdict final et ceux archivés à chaque boucle (history/<stem>_<n>.json)."""
    stem = filename.rsplit(".", 1)[0]
    paths = sorted(glob.glob(os.path.join(run_dir, "history", f"{stem}_*.json")))
    final = os.path.join(run_dir, filename)
    if os.path.isfile(final):
        paths.append(final)
    return paths


def short(text, n=400):
    text = " ".join(str(text or "").split())
    return text if len(text) <= n else text[: n - 1] + "…"


def extract_signals(run_dir):
    key, project, pipeline, name = run_identity(run_dir)
    state = load_json(os.path.join(run_dir, "pipeline.json" if pipeline == "feature" else "fix.json"), {}) or {}
    decisions = state.get("suggestions") or {}
    signals, seen = [], set()

    def add(kind, source, text, rule=None, file=None, extra=None):
        dedup = (kind, file, short(text, 120))
        if not text or dedup in seen:
            return
        seen.add(dedup)
        sig = {"id": f"{key}#{kind}:{len(signals) + 1}", "run": key, "project": project,
               "pipeline": pipeline, "kind": kind, "source": source, "text": short(text)}
        if rule:
            sig["rule"] = rule
        if file:
            sig["file"] = file
        if extra:
            sig.update(extra)
        signals.append(sig)

    for path in verdict_files(run_dir, "review.json"):
        src = os.path.relpath(path, run_dir)
        d = load_json(path, {}) or {}
        for c in d.get("critical") or []:
            add("review_critical", src, f"{c.get('summary', '')} — {c.get('fix', '')}", c.get("rule"), c.get("file"))
        for s in d.get("suggestions") or []:
            decision = (decisions.get(s.get("id")) or {}).get("decision")
            if decision == "debt":
                continue
            add("suggestion", src, f"{s.get('summary', '')} : {s.get('problem', '')}", s.get("rule"), s.get("file"),
                {"decision": decision} if decision else None)
        for m in d.get("missing_tests") or []:
            add("missing_test", src, f"{m.get('scenario', '')} — {m.get('why', '')}")

    for filename, kind in (("spec_review.json", "spec_blocking"), ("tests_review.json", "tests_blocking")):
        for path in verdict_files(run_dir, filename):
            d = load_json(path, {}) or {}
            for b in (d.get("blocking") or []) + (d.get("resolved_blocking") or []):
                add(kind, os.path.relpath(path, run_dir),
                    b.get("issue") or b.get("summary") or json.dumps(b, ensure_ascii=False),
                    b.get("section") or b.get("rule"), b.get("file"))

    for path in verdict_files(run_dir, "dedup.json"):
        for v in (load_json(path, {}) or {}).get("verdicts") or []:
            if v.get("verdict") in ("duplicate", "extend"):
                t, e = v.get("target") or {}, v.get("existing") or {}
                add("reinvented", os.path.relpath(path, run_dir),
                    f"{t.get('name')} refait {e.get('name')} ({e.get('package', '')}) : {v.get('reason', '')}",
                    v.get("verdict"), t.get("file"))

    if pipeline == "fix":
        repro = load_json(os.path.join(run_dir, "repro.json"), {}) or {}
        if repro.get("miss_reason"):
            add("miss", "repro.json", f"{repro.get('root_cause', '')}", repro.get("miss_reason"),
                repro.get("root_cause_location"))
        for d in state.get("plan_deviations") or []:
            add("plan_deviation", "fix.json", d.get("reason"), None, ", ".join(d.get("files") or []))
        for a in state.get("arbitrations") or []:
            add("arbitration", "fix.json", f"{a.get('test', '')} : {a.get('claim', '')}")

    for r in state.get("refreezes") or []:
        add("refreeze", "pipeline.json" if pipeline == "feature" else "fix.json",
            # Ancien format (avant les causes) : seulement « reason ».
            f"re-gel {r.get('cause')} à l'étape {r.get('stage', '?')} : {', '.join(r.get('files') or [])}"
            if r.get("cause") else f"re-gel : {r.get('reason', '')}", r.get("cause"))
    for a in state.get("accepted") or []:
        add("accepted", "state", f"{a.get('stage')} : {a.get('reason')}", a.get("stage"))

    return key, signals


def cmd_extract(args):
    if len(args) != 1:
        die("usage : extract <dossier du run>")
    key, signals = extract_signals(args[0])
    known = {r["id"] for r in ledger()}
    fresh = [s for s in signals if s["id"] not in known]
    os.makedirs(PENDING, exist_ok=True)
    save_json(os.path.join(PENDING, key.replace("/", "__") + ".json"), fresh)
    patterns = load_json(PATTERNS, {}) or {}
    print(json.dumps({"run": key, "signals": fresh,
                      "known_patterns": {k: v["desc"] for k, v in patterns.items()}},
                     ensure_ascii=False, indent=1))


def cmd_record(args):
    if len(args) != 1:
        die("usage : record <labels.json>")
    data = load_json(args[0])
    if not isinstance(data, dict) or "labels" not in data or "run" not in data:
        die('format attendu : {"run": clé, "patterns": {slug: desc}, "labels": [{"id": …, "pattern": slug|"noise"}]}')
    patterns = load_json(PATTERNS, {}) or {}
    for slug, desc in (data.get("patterns") or {}).items():
        patterns.setdefault(slug, {"desc": desc, "status": "open", "created": now()})
    pending = {}
    for path in glob.glob(os.path.join(PENDING, "*.json")):
        for s in load_json(path, []) or []:
            pending[s["id"]] = (s, path)
    known = {r["id"] for r in ledger()}
    rows, touched = [], set()
    for lab in data["labels"]:
        sid, slug = lab.get("id"), lab.get("pattern")
        if sid not in pending:
            die(f"signal inconnu (lance extract d'abord) : {sid}")
        if slug != NOISE and slug not in patterns:
            die(f"pattern inconnu, à déclarer dans \"patterns\" : {slug}")
        if sid in known:
            continue
        sig, path = pending[sid]
        rows.append({**sig, "pattern": slug, "at": now()})
        touched.add(path)
    # Marque le run comme passé par learn, même si tous ses signaux sont du bruit.
    if f"{data['run']}#done" not in known:
        rows.append({"id": f"{data['run']}#done", "run": data["run"], "kind": "_done", "pattern": NOISE, "at": now()})
    os.makedirs(HOME, exist_ok=True)
    with open(LEDGER, "a", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    save_json(PATTERNS, patterns)
    recorded = {r["id"] for r in ledger()}
    for path in touched:
        left = [s for s in load_json(path, []) or [] if s["id"] not in recorded]
        if left:
            save_json(path, left)
        else:
            os.remove(path)
    labelled = [r for r in rows if r["kind"] != "_done"]
    print(f"{len(labelled)} signaux enregistrés, {sum(1 for r in labelled if r['pattern'] == NOISE)} en bruit")


def pattern_stats():
    stats = {}
    for r in ledger():
        if r["pattern"] == NOISE:
            continue
        s = stats.setdefault(r["pattern"], {"runs": set(), "projects": set(), "kinds": set(), "n": 0})
        s["runs"].add(r["run"])
        s["projects"].add(r["project"])
        s["kinds"].add(r["kind"])
        s["n"] += 1
    return stats


def cmd_candidates(args):
    min_runs = int(args[args.index("--min-runs") + 1]) if "--min-runs" in args else 2
    patterns = load_json(PATTERNS, {}) or {}
    out = []
    for slug, s in sorted(pattern_stats().items(), key=lambda kv: -len(kv[1]["runs"])):
        p = patterns.get(slug, {})
        runs = len(s["runs"])
        status = p.get("status", "open")
        if status == "promoted":
            continue
        if status == "rejected" and runs < (p.get("rejected") or {}).get("runs", 0) + 2:
            continue
        if runs < min_runs:
            continue
        out.append({"pattern": slug, "desc": p.get("desc"), "runs": runs, "occurrences": s["n"],
                    "projects": sorted(s["projects"]), "kinds": sorted(s["kinds"]),
                    "previously_rejected": p.get("rejected")})
    print(json.dumps(out, ensure_ascii=False, indent=1))


def cmd_examples(args):
    if len(args) != 1:
        die("usage : examples <slug>")
    rows = [r for r in ledger() if r["pattern"] == args[0]]
    print(json.dumps(rows, ensure_ascii=False, indent=1))


def set_status(slug, status, payload):
    patterns = load_json(PATTERNS, {}) or {}
    if slug not in patterns:
        die(f"pattern inconnu : {slug}")
    patterns[slug]["status"] = status
    patterns[slug][status] = payload
    save_json(PATTERNS, patterns)
    print(f"{slug} : {status}")


def cmd_promote(args):
    if len(args) != 3:
        die('usage : promote <slug> <fichier> "<règle>"')
    set_status(args[0], "promoted", {"at": now(), "file": args[1], "rule": args[2]})


def cmd_reject(args):
    if len(args) != 2:
        die('usage : reject <slug> "<raison>"')
    runs = len(pattern_stats().get(args[0], {}).get("runs", ()))
    set_status(args[0], "rejected", {"at": now(), "reason": args[1], "runs": runs})


SKIP_DIRS = {"node_modules", ".git", "build", ".dart_tool", "Pods", ".gradle", "worktrees", "graphify-out"}


def run_dirs(root, max_depth=4):
    """Dossiers <projet>/.claude/{features,fixes}/<nom>/ terminés (evidence.md), sans descendre dans les builds."""
    base = root.rstrip("/").count("/")
    for cur, dirs, _ in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and (not d.startswith(".") or d == ".claude")]
        if os.path.basename(cur) == ".claude":
            for kind in ("features", "fixes"):
                for ev in sorted(glob.glob(os.path.join(cur, kind, "*", "evidence.md"))):
                    yield os.path.dirname(ev)
            dirs[:] = []
        elif cur.count("/") - base >= max_depth:
            dirs[:] = []


def cmd_scan(args):
    if not args:
        die("usage : scan <racine>...")
    done = {r["run"] for r in ledger() if r["kind"] == "_done"}
    for root in args:
        for run_dir in run_dirs(os.path.expanduser(root)):
            key = run_identity(run_dir)[0]
            if key not in done:
                print(run_dir)


COMMANDS = {"extract": cmd_extract, "record": cmd_record, "candidates": cmd_candidates,
            "examples": cmd_examples, "promote": cmd_promote, "reject": cmd_reject, "scan": cmd_scan}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print(__doc__)
        sys.exit(0 if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help") else 2)
    COMMANDS[sys.argv[1]](sys.argv[2:])
