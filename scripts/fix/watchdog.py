#!/usr/bin/env python3
"""fix/watchdog.py — le /fix est-il bloqué ? Même verdict que `pipeline.sh watchdog` pour /feature (ADR 0005).

  fix_gauntlet.sh watchdog <nom> [--json] [--notify]     (depuis le worktree du fix)

done | working | waiting_thibault | stalled | idle. L'étape vient de fix_cockpit.py → steps() ; l'attente
de Thibault de fix.json → cockpit.waiting (posé par `fix_cockpit.py say`) ; « ça tourne » des hooks de
.gauntlet/hook_*.running et des sous-agents des sessions de ce worktree. Seuil watchdog.minutes de
.claude/rules/feature_pipeline.md (défaut 20). --notify : notify.sh, au plus une fois par verdict et par
watchdog.renotify_minutes, état dans .watchdog.json ; un blocage n'est signalé qu'après deux délais.
Cas réel : gate green de Fanny passé, Victor jamais lancé, personne ne l'a vu jusqu'au retour du dev.
"""
import glob
import json
import os
import subprocess
import sys
import types

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [os.path.join(HERE, ".."), os.path.join(HERE, "..", "pipeline")]
import fix_cockpit  # noqa: E402
import pipeline as pl  # noqa: E402


def verdict(fx):
    cfg = types.SimpleNamespace(cfg_file=os.path.join(fx.root, ".claude", "rules", "feature_pipeline.md"))
    minutes = int(pl.Ctx.cfg(cfg, "watchdog.minutes", "20") or 20)
    t = pl.time_now()
    _, n = fix_cockpit.steps(fx)
    v = {"fix": fx.name, "minutes": minutes, "step": n["step"], "title": n["title"], "now": pl._iso(t)}
    if n["key"] == "done":
        return {**v, "verdict": "done", "detail": n["title"]}
    gdir = os.path.join(fx.dir, ".gauntlet")
    events = [(pl._mtime(fx.path), "fix.json écrit")]
    for d, _, files in os.walk(fx.dir):
        if "/history" in d:
            continue
        for f in files:
            if not f.startswith(".watchdog"):
                events.append((pl._mtime(os.path.join(d, f)), os.path.relpath(os.path.join(d, f), fx.dir)))
    sessions = pl._worktree_sessions(fx.root)
    agents = []
    for s in sessions:
        for sub in glob.glob(os.path.expanduser(f"~/.claude/projects/*/{s.get('session') or ''}/subagents/*.jsonl")):
            m = pl._mtime(sub)
            events.append((m, "transcript d'un sous-agent"))
            if t - m < minutes * 60:
                agents.append(os.path.basename(sub)[:-6])
    last_ts, last_what = max(events)
    idle_min = int((t - last_ts) / 60)
    v.update({"last_activity": pl._iso(last_ts), "last_what": last_what, "idle_minutes": idle_min})
    hooks = pl._alive_hooks(gdir)
    if hooks or agents:
        what = (["gate en cours : " + ", ".join(hooks)] if hooks else []) + ([f"{len(agents)} sous-agent(s) actif(s)"] if agents else [])
        return {**v, "verdict": "working", "detail": " · ".join(what)}
    ck = fx.f.get("cockpit") or {}
    waiting = ck.get("waiting")
    perm = [s for s in sessions if s.get("state") == "waiting"]
    if waiting or perm or n["status"] == "FAILED":
        since = pl._parse_at(ck.get("at")) if waiting else (min(x.get("at", 0) for x in perm) / 1000 if perm else last_ts)
        detail = waiting or (f"la session attend : {perm[0].get('waitingOn') or 'une réponse'}" if perm
                             else f"étape {n['step']} FAILED : le dev décide")
        wm = int((t - (since or last_ts)) / 60)
        return {**v, "verdict": "waiting_thibault", "waiting_minutes": wm, "alert": wm >= minutes, "detail": detail}
    if idle_min >= minutes:
        gate = ""
        lasts = sorted(((pl._mtime(os.path.join(gdir, f)), f) for f in (os.listdir(gdir) if os.path.isdir(gdir) else [])
                        if f.startswith("last_") and f.endswith(".json")), reverse=True)
        if lasts and lasts[0][0] >= last_ts - 1:
            try:
                ok = json.load(open(os.path.join(gdir, lasts[0][1]))).get("ok")
            except (OSError, json.JSONDecodeError):
                ok = None
            gate = f" ; dernier gate joué : {lasts[0][1][5:-5]} ({'vert' if ok else 'rouge'}) à {pl._iso(lasts[0][0])}, personne ne l'a lu"
        detail = (f"rien ne tourne depuis {pl._iso(last_ts)} ({last_what}) et aucune question n'attend Thibault ; "
                  f"étape suivante {n['step']} — {n['title']} non lancée" + gate)
        return {**v, "verdict": "stalled", "alert": True, "detail": detail,
                "action": f"reprendre /fix {fx.name} à l'étape {n['step']} ({n['title']})"}
    return {**v, "verdict": "idle", "detail": f"calme depuis {idle_min} min (seuil {minutes})"}


def main(args):
    if not args or args[0] in ("-h", "--help"):
        print(__doc__)
        sys.exit(0 if args else 2)
    fx = fix_cockpit.Fix(args[0])
    v = verdict(fx)
    if "--notify" in args and v.get("alert"):
        cfg = types.SimpleNamespace(cfg_file=os.path.join(fx.root, ".claude", "rules", "feature_pipeline.md"))
        state_f = os.path.join(fx.dir, ".watchdog.json")
        try:
            last = json.load(open(state_f))
        except (OSError, json.JSONDecodeError):
            last = {}
        renotify = int(pl.Ctx.cfg(cfg, "watchdog.renotify_minutes", "120") or 120) * 60
        late_enough = v["verdict"] != "stalled" or v["idle_minutes"] >= 2 * v["minutes"]
        if late_enough and (last.get("verdict") != v["verdict"] or pl.time_now() - last.get("ts", 0) >= renotify):
            title = f"/fix {fx.name} — " + ("attend ta réponse" if v["verdict"] == "waiting_thibault" else "bloqué")
            subprocess.run(["bash", os.path.join(HERE, "..", "notify.sh"), "--needs-you", title, v["detail"]], check=False)
            with open(state_f, "w") as fh:
                json.dump({"verdict": v["verdict"], "ts": pl.time_now()}, fh)
            v["notified"] = True
    if "--json" in args:
        print(json.dumps(v, ensure_ascii=False, indent=2))
        return
    print(f"verdict   : {v['verdict']} — {v['detail']}")
    print(f"étape     : {v['step']} — {v['title']}")
    if "last_activity" in v:
        print(f"activité  : dernière à {v['last_activity']} ({v['last_what']}), il y a {v['idle_minutes']} min · seuil {v['minutes']} min")
    if v.get("action"):
        print(f"à faire   : {v['action']}")
    if v.get("notified"):
        print("notifié   : oui (notify.sh)")


if __name__ == "__main__":
    main(sys.argv[1:])
