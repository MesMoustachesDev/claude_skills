#!/usr/bin/env python3
"""fix/steps.py — l'étape courante d'un /fix, et ce qu'il attend de Thibault.

À lancer depuis le worktree du fix. L'état vient de .claude/fixes/<nom>/fix.json et repro.json. Ce script
n'écrit dans fix.json que `waiting` et `waiting_at` (la question posée à Thibault).

  fix/steps.py next <nom> [--json]     étape courante (première ni passée ni sautée), étapes, attente
  fix/steps.py ask <nom> "<question>"  ce qu'on attend de Thibault, posé avant la question ("" pour effacer)

Lus par le watchdog du fix (fix/watchdog.py) et par le mod pipeline-view (`next --json`).
"""
import datetime
import json
import os
import re
import subprocess
import sys

# (clé, étape, titre). Une clé « hg.x » est un point d'étape (human_gates.x) ; hg.ui seulement pour un bug d'écran.
ORDER = [
    ("red", "1", "Reproduction (Bastien)"),
    ("hg.repro", "1", "Ton arrêt : diagnostic, test rouge, plan"),
    ("green", "2", "Correction (Fanny)"),
    ("review", "3", "Revue (Victor)"),
    ("hg.ui", "4", "Captures avant / après"),
    ("evidence", "5", "Evidence, commits"),
]
DONE = {"key": "done", "step": "—", "title": "Fix terminé", "status": "DONE"}


def die(msg, code=2):
    print(f"[ABORT] {msg}", file=sys.stderr)
    sys.exit(code)


def now():
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def git(*args, cwd=None):
    r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""


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
    """(étapes, étape courante) : la courante est la première ni passée ni sautée, `done` sinon."""
    ui = (fx.repro().get("kind") or fx.f.get("kind")) == "ui"
    out, current = [], None
    for k, n, t in ORDER:
        if k == "hg.ui" and not ui:
            continue
        st = (fx.f.get("stages") or {}).get(k) if not k.startswith("hg.") else None
        status = "PASSED" if passed(fx.f, k) else ((st.get("status") if isinstance(st, dict) else st) or "TODO")
        if status != "PASSED" and current is None:
            current = {"key": k, "step": n, "title": t, "status": status}
        out.append({"key": k, "step": n, "title": t, "status": status})
    return out, current or dict(DONE)


def cmd_next(fx, args):
    st, cur = steps(fx)
    waiting = None if cur["key"] == "done" else fx.f.get("waiting")
    info = {"fix": fx.name, **cur, "stages": st, "waiting": waiting or None, "waiting_at": fx.f.get("waiting_at") if waiting else None}
    if "--json" in args:
        print(json.dumps(info, ensure_ascii=False, indent=2))
        return
    print(f"étape     : {cur['step']} — {cur['title']} ({cur['status']})")
    if waiting:
        print(f"attente   : {waiting} (depuis {info['waiting_at']})")


def cmd_ask(fx, args):
    text = (args[0] if args else "").strip()
    if "\n" in text or len(text) > 200:
        die("ask : une ligne, 200 caractères au plus")
    fx.f.pop("cockpit", None)   # ancienne clé, avant le retrait du cockpit (2026-11-19)
    fx.f["waiting"] = text or None
    fx.f["waiting_at"] = now() if text else None
    fx.save()
    print(f"attente : {text}" if text else "attente effacée")


COMMANDS = {"next": cmd_next, "ask": cmd_ask}

if __name__ == "__main__":
    a = sys.argv[1:]
    if len(a) < 2 or a[0] not in COMMANDS:
        print(__doc__)
        sys.exit(0 if a and a[0] in ("-h", "--help") else 2)
    COMMANDS[a[0]](Fix(a[1]), a[2:])
