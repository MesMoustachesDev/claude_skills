#!/usr/bin/env python3
"""fix/steps.py — l'étape courante d'un /fix, et ce qu'il attend de Thibault.

À lancer depuis le worktree du fix. L'état vient de .claude/fixes/<nom>/fix.json et repro.json. Ce script
n'écrit dans fix.json que `waiting` et `waiting_at` (la question posée à Thibault) ; tout le reste de l'état
passe par fix/fix.py, qui s'appuie sur la classe Fix d'ici.

  fix/steps.py next <nom> [--json]     étape courante (première ni passée ni sautée), étapes, attente
  fix/steps.py ask <nom> "<question>"  ce qu'on attend de Thibault, posé avant la question ("" pour effacer)

Lus par le watchdog du fix (fix/watchdog.py) et par le mod pipeline-view (`next --json`).
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [os.path.dirname(HERE), os.path.join(os.path.dirname(HERE), "pipeline")]
import statefile  # noqa: E402  (scripts/statefile.py : lecture, écriture sous verrou)
import pipeline as pl  # noqa: E402  (état partagé avec /feature : Ctx, commandes génériques, attente des hooks)
from statefile import die  # noqa: E402

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
LOOP_MAX = {"review": 2, "arbitrate": 2, "ui": 2}


class Fix(pl.Ctx):
    """fix.json d'un /fix, avec l'interface de pipeline.Ctx : les commandes de pipeline.py (pass, gate, loop,
    debt, accept, ask, recap, set…) et l'attente des hooks (wait_hooks, wait_agents) s'y appliquent telles
    quelles. `save` : sous verrou (statefile), seul ce que la commande a changé est réécrit sur fix.json relu ;
    ce que fix-gate.sh y a écrit entre-temps est gardé."""

    def __init__(self, name, must_exist=True):
        if not re.fullmatch(r"[a-z][a-z0-9_]*", name or ""):
            die(f"nom de fix invalide : {name!r}")
        self.name = name
        self.root = pl.git("rev-parse", "--show-toplevel", check=False) or die("pas dans un repo git")
        self.dir = os.path.join(self.root, ".claude", "fixes", name)
        self.path = os.path.join(self.dir, "fix.json")
        self.cfg_file = os.path.join(self.root, ".claude", "rules", "feature_pipeline.md")
        if must_exist and not os.path.isfile(self.path):
            die(f"fix.json absent : {self.path}")
        self.reload()

    @property
    def f(self):
        return self.p

    def step_key(self):
        return steps(self)[1]["key"]

    def gate_cmd(self, profile):
        return f"fix_gauntlet.sh {profile} {self.name}"

    def loop_max(self, name):
        return LOOP_MAX.get(name, 2)

    def loop_verdict(self, name):
        return "review.json" if name == "review" else None

    def repro(self):
        try:
            return json.loads(statefile.read_text(os.path.join(self.dir, "repro.json")) or "{}")
        except json.JSONDecodeError:
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
    pl.cmd_ask(fx, args)


COMMANDS = {"next": cmd_next, "ask": cmd_ask}

if __name__ == "__main__":
    a = sys.argv[1:]
    if len(a) < 2 or a[0] not in COMMANDS:
        print(__doc__)
        sys.exit(0 if a and a[0] in ("-h", "--help") else 2)
    COMMANDS[a[0]](Fix(a[1]), a[2:])
