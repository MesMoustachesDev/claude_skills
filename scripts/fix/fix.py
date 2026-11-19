#!/usr/bin/env python3
"""fix/fix.py — l'état d'un /fix (fix.json), écrit par script et jamais à la main (ADR 0003).

À lancer depuis le worktree du fix. Chaque commande relit fix.json sous verrou (scripts/statefile.py) et n'y
réapplique que ce qu'elle a changé : ce que fix-gate.sh écrit entre-temps (stages, attempts) est gardé.
Les verdicts de gate (stages.red, stages.green, stages.review…) ne s'écrivent que par un script : le hook de fin
d'agent (fix-gate.sh) ou `review-pass`, qui joue le gauntlet. `pass` et `skip` les refusent.

  init <nom> "<description>" --base-branch <b> [--graphify ok|stale|absent|failed|échec] [--graph <chemin>]
                                     crée fix.json (base_sha = HEAD, phase repro) et .claude/fixes/.current
  agent <nom> reproducer|implementer|reviewer <agentId>    agents.<rôle>, pour reprendre l'agent par SendMessage
  after <nom> <profil>               au rapport d'un agent : attend son hook de fin, et l'agent renvoyé au travail
                                     si le gate est rouge ; dit quoi faire. Exit 4 : relance la même commande
  gate <nom> plan proposed|alternative|other     human_gates.plan (choix de Thibault sur le plan)
  gate <nom> ui                      human_gates.ui (captures avant / après validées)
  freeze <nom> "<bug en une phrase>" gel : commit des tests, manifestes, repro.json, diagnosis.md, shots/red ;
                                     freeze_sha, human_gates.repro, phase impl. Exige stages.red PASSED et le plan
  refreeze <nom> hygiene|technique|diagnostic|couverture "<ce qui change>"
                                     re-gel des tests modifiés (et repro.json, diagnosis.md) ; nouveau freeze_sha,
                                     trace dans refreezes
  phase <nom> repro|impl|arbitrate   fix.json → phase (fix-gate.sh en tire le profil de Bastien)
  arbitrate <nom> open "<test>" "<contestation de Fanny>"   phase arbitrate, trace, loops.arbitrate
                                     (exit 3 au-delà de 2 : point imprévu)
  arbitrate <nom> close juste|corrige    verdict de Bastien sur la dernière contestation ; phase impl
  deviation <nom> "<raison>" <fichier>…  écart au plan accepté par Thibault (plan_deviations, lu par Victor)
  review-pass <nom>                  verdict de revue : review.json → debt reporté dans fix.json, puis le gauntlet
                                     review_verdict ; vert → stages.review = PASSED (exit 0), sinon exit 1
  loop <nom> review|arbitrate|ui     compteur de boucle ; review : review.json archivé dans history/review_<n>.json.
                                     Exit 3 au-delà de 2 : point imprévu, Thibault tranche
  debt <nom> <source> <fichier> "<problème>" [--line N]    dette existante (sort dans l'evidence)
  accept <nom> review "<raison>"     acceptation de Thibault : trace dans accepted, et accepted: true + raison sur
                                     chaque critique restante de review.json ; rejoue ensuite review-pass
  set <nom> suggestions.<id> '{"decision":"applied|skipped|debt","note":"…"}'
  set <nom> issue '<référence stockée de tracker.md>'
  set <nom> watchdog_cron <id>       les seules autres clés écrites par l'orchestrateur
  ask <nom> "<question>"             ce qu'on attend de Thibault ("" pour effacer) ; même chose que fix/steps.py ask
  recap <nom> <fichier.json>         résumé « Reprendre le fil » (schéma de pipeline.sh recap)
  pass <nom> evidence                étape 5 terminée : stages.evidence, attente effacée, .claude/fixes/.current retiré
  skip <nom> evidence "<raison>"

Les commandes génériques (gate, loop, debt, accept, ask, recap, set, pass, skip, l'attente des hooks) sont celles
de scripts/pipeline/pipeline.py, appliquées à fix.json par la classe Fix de fix/steps.py.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [HERE, os.path.dirname(HERE), os.path.join(os.path.dirname(HERE), "pipeline")]
import pipeline as pl  # noqa: E402
import statefile  # noqa: E402
from statefile import die, now  # noqa: E402
from steps import Fix  # noqa: E402

GAUNTLET = os.path.join(os.path.dirname(HERE), "fix_gauntlet.sh")
LIB = os.path.join(HERE, "lib.sh")
GATE_STAGES = {"red", "green", "review", "repro_report", "review_report", "review_verdict"}
HAND_STAGES = {"evidence"}
PLAN_CHOICES = {"proposed", "alternative", "other"}
PHASES = {"repro", "impl", "arbitrate"}
ROLES = {"reproducer", "implementer", "reviewer"}
REFREEZE_CAUSES = {"hygiene", "technique", "diagnostic", "couverture"}
GRAPHIFY = {"ok": "ok", "stale": "stale", "absent": "absent", "failed": "failed", "échec": "failed"}
SUGGESTION_DECISIONS = {"applied", "skipped", "debt"}
# Fichiers du dossier du fix qui se gèlent avec les tests ; le reste (fix.json, .gauntlet/, report.html) n'est pas suivi.
FROZEN_FIX_FILES = ("repro.json", "diagnosis.md")


def need(args, n, usage):
    if len(args) < n:
        die(f"usage : {usage}")


# ---------------------------------------------------------------------------
# Création
# ---------------------------------------------------------------------------
def cmd_init(fx, args):
    need(args, 1, 'init <nom> "<description>" --base-branch <b> [--graphify …] [--graph <chemin>]')
    if fx.p:
        die(f"{fx.path} existe déjà : reprise, pas init")
    desc, opts = args[0], dict(zip(args[1::2], args[2::2]))
    base_branch = opts.get("--base-branch")
    if not base_branch:
        die("--base-branch <branche du checkout principal> est obligatoire")
    if not pl.git("rev-parse", "--verify", "--quiet", f"{base_branch}^{{commit}}", cwd=fx.root, check=False):
        die(f"--base-branch {base_branch} : branche introuvable")
    graphify = GRAPHIFY.get(opts.get("--graphify", "absent"))
    if graphify is None:
        die(f"--graphify : {' | '.join(GRAPHIFY)}")
    graph = opts.get("--graph") if graphify == "ok" else None
    if graphify == "ok" and not graph:
        die("--graphify ok : --graph <valeur de graph= de graphify.sh prepare> est obligatoire")
    fx.p = {
        "fix": fx.name, "description": desc, "branch": f"fix/{fx.name}", "base_branch": base_branch,
        "base_sha": pl.git("rev-parse", "HEAD", cwd=fx.root), "created": now(), "phase": "repro", "max_attempts": 5,
        "stages": {}, "attempts": {}, "freeze_sha": None, "refreezes": [], "suggestions": {}, "debt": [], "loops": {},
        "human_gates": {}, "arbitrations": [], "agents": {}, "accepted": [], "issue": None,
        "graphify": graphify, "graphify_graph": graph,
    }
    fx.save()
    with open(os.path.join(fx.root, ".claude", "fixes", ".current"), "w", encoding="utf-8") as f:
        f.write(fx.name + "\n")
    print(f"fix.json créé : {os.path.relpath(fx.path, fx.root)} · base {base_branch}@{fx.p['base_sha'][:10]} · graphify {graphify}")


def cmd_agent(fx, args):
    need(args, 2, "agent <nom> reproducer|implementer|reviewer <agentId>")
    role, agent_id = args[0], args[1].strip()
    if role not in ROLES:
        die(f"rôle : {' | '.join(sorted(ROLES))}")
    if not agent_id or any(ch.isspace() for ch in agent_id):
        die("agentId : un identifiant, sans espace")
    fx.p.setdefault("agents", {})[role] = agent_id
    fx.save()
    print(f"agents.{role} = {agent_id}")


# ---------------------------------------------------------------------------
# Attente au rapport d'un agent (ADR 0005)
# ---------------------------------------------------------------------------
def cmd_after(fx, args):
    """Au rapport (hand-back) d'un agent, dans le même tour : attend que le hook de fin de son gate ait démarré puis
    fini, et, gate rouge, que l'agent renvoyé au travail ait un nouveau verdict (pipeline.wait_hooks, wait_agents).
    Ni le rapport suivant ni la notification de fin ne relancent un tour à coup sûr (cas réel : gate green de Fanny
    passé, Victor jamais lancé). Exit 4 au bout du budget (PIPELINE_WAIT_MAX, 540 s) : relancer la même commande."""
    need(args, 1, "after <nom> <profil>")
    profile = args[0]
    pl.pop_after(["--after", profile])   # démarre le chrono du budget
    if not pl.wait_hooks(fx, profile):
        print(f"hook      : aucun hook de fin vu pour {profile} en {pl.AFTER_WAIT} s — rejoue le gate "
              f"({fx.gate_cmd(profile)}) et dis-le ; ne relance pas l'agent")
        return
    pl.wait_agents(fx, [profile])
    st = pl._status((fx.p.get("stages") or {}).get(profile))
    tries = (fx.p.get("attempts") or {}).get(profile)
    if st == "PASSED":
        print(f"hook      : {profile} = PASSED — lance l'étape suivante, dans ce tour")
    elif st == "FAILED":
        print(f"hook      : {profile} FAILED après {tries} tentatives — point imprévu : le dev décide (AskUserQuestion)")
    else:
        print(f"hook      : {profile} = {st or 'vide'} — le hook n'a rien écrit : rejoue le gate ({fx.gate_cmd(profile)}) et dis-le")


# ---------------------------------------------------------------------------
# Points d'étape, gel
# ---------------------------------------------------------------------------
def cmd_gate(fx, args):
    need(args, 1, "gate <nom> plan proposed|alternative|other | gate <nom> ui")
    gate = args[0]
    if gate == "plan":
        need(args, 2, "gate <nom> plan proposed|alternative|other")
        if args[1] not in PLAN_CHOICES:
            die(f"choix du plan : {' | '.join(sorted(PLAN_CHOICES))}")
        pl.cmd_gate(fx, ["plan", f"choice={args[1]}"])
    elif gate == "ui":
        pl.cmd_gate(fx, ["ui"])
    else:
        die("point d'étape : plan | ui (repro est posé par freeze)")


def classify(fx, files):
    """{fichier: "test"|"manifest"|"probe"|""} selon fix/lib.sh (is_test_path, is_manifest_path, is_probe_path) :
    la même règle que le gate et que fix-restrict-writes.sh, pas une copie."""
    if not files:
        return {}
    script = ('source "$1"; fix_context "$2" || exit 1; shift 2; for f; do '
              'if is_probe_path "$f"; then k=probe; elif is_test_path "$f"; then k=test; '
              'elif is_manifest_path "$f"; then k=manifest; else k=-; fi; printf "%s\\t%s\\n" "$k" "$f"; done')
    r = subprocess.run(["bash", "-c", script, "_", LIB, fx.name, *files], cwd=fx.root, capture_output=True, text=True)
    if r.returncode != 0:
        die(f"classement des fichiers (fix/lib.sh) : {r.stderr.strip()}")
    out = {}
    for line in r.stdout.splitlines():
        kind, _, f = line.partition("\t")
        out[f] = "" if kind == "-" else kind
    return out


def changed(fx):
    """Fichiers modifiés depuis HEAD, non suivis compris, relatifs à la racine (sous-modules descendus, comme le gate)."""
    script = 'source "$1"; fix_context "$2" || exit 1; changed_since HEAD'
    r = subprocess.run(["bash", "-c", script, "_", LIB, fx.name], cwd=fx.root, capture_output=True, text=True)
    return [f for f in r.stdout.splitlines() if f]


def fix_rel(fx, f):
    return os.path.relpath(os.path.join(fx.dir, f), fx.root)


def frozen_files(fx, manifests):
    """Ce que le gel emporte : tests (jamais un probe zz_probe_*), manifestes touchés au gel initial, repro.json et
    diagnosis.md, captures shots/red/."""
    files = changed(fx)
    kinds = classify(fx, [f for f in files if not f.startswith(".claude/")])
    keep = {"test", "manifest"} if manifests else {"test"}
    out = [f for f, k in kinds.items() if k in keep]
    own = {fix_rel(fx, x) for x in FROZEN_FIX_FILES}
    shots = fix_rel(fx, "shots/red") + "/"
    out += [f for f in files if f in own or f.startswith(shots)]
    return sorted(set(out))


def cmd_freeze(fx, args):
    need(args, 1, 'freeze <nom> "<bug en une phrase>"')
    if fx.p.get("freeze_sha"):
        die(f"déjà gelé @{fx.p['freeze_sha'][:10]} : un nouveau gel passe par refreeze")
    red = pl._status((fx.p.get("stages") or {}).get("red"))
    if red != "PASSED":
        die(f"stages.red = {red or 'vide'} : on ne gèle qu'un test rouge pour la bonne raison (gate red vert)")
    if not (fx.p.get("human_gates") or {}).get("plan"):
        die("human_gates.plan absent : Thibault valide le plan avant le gel (gate <nom> plan …)")
    files = frozen_files(fx, manifests=True)
    if not any(classify(fx, files).get(f) == "test" for f in files):
        die("aucun test modifié depuis HEAD : rien à geler")
    sha = pl.commit(fx, files, f"test({fx.name}): reproduce {args[0]} (frozen)")
    fx.p["freeze_sha"] = sha
    fx.p.setdefault("human_gates", {})["repro"] = {"at": now(), "by": "user", "sha": sha}
    fx.p["phase"] = "impl"
    pl.clear_waiting(fx.p)
    fx.save()
    print(f"gel : {sha[:10]} · {len(files)} fichiers · phase impl")
    for f in files:
        print(f"  {f}")


def cmd_refreeze(fx, args):
    need(args, 2, f'refreeze <nom> {"|".join(sorted(REFREEZE_CAUSES))} "<ce qui change>"')
    cause, what = args[0], args[1]
    if cause not in REFREEZE_CAUSES:
        die(f"cause : {' | '.join(sorted(REFREEZE_CAUSES))}")
    if not fx.p.get("freeze_sha"):
        die("pas encore gelé : le premier gel passe par freeze")
    files = frozen_files(fx, manifests=False)
    if not files:
        die("aucun test ni repro.json / diagnosis.md modifié : rien à re-geler")
    pl.record_refreeze(fx, "freeze_sha", files, cause, fx.step_key(), what)


def cmd_phase(fx, args):
    need(args, 1, "phase <nom> repro|impl|arbitrate")
    if args[0] not in PHASES:
        die(f"phase : {' | '.join(sorted(PHASES))}")
    old = fx.p.get("phase")
    fx.p["phase"] = args[0]
    fx.save()
    print(f"phase : {old or '—'} → {args[0]}")


def cmd_arbitrate(fx, args):
    need(args, 1, 'arbitrate <nom> open "<test>" "<contestation>" | arbitrate <nom> close juste|corrige')
    arbs = fx.p.setdefault("arbitrations", [])
    if args[0] == "open":
        need(args, 3, 'arbitrate <nom> open "<test>" "<contestation>"')
        arbs.append({"at": now(), "test": args[1], "claim": args[2]})
        fx.p["phase"] = "arbitrate"
        fx.save()
        print(f"arbitrage ouvert ({len(arbs)}) · phase arbitrate")
        pl.cmd_loop(fx, ["arbitrate"])   # exit 3 au-delà du plafond
    elif args[0] == "close":
        need(args, 2, "arbitrate <nom> close juste|corrige")
        if args[1] not in ("juste", "corrige"):
            die("verdict : juste (le test reste) | corrige (test corrigé, re-gel fait)")
        if not arbs or arbs[-1].get("verdict"):
            die("aucun arbitrage ouvert")
        if args[1] == "corrige" and not any(r.get("at", "") >= arbs[-1]["at"] for r in fx.p.get("refreezes") or []):
            die("test corrigé : re-gèle d'abord (refreeze <nom> <cause> …) une fois la correction validée par Thibault")
        arbs[-1].update({"verdict": args[1], "closed_at": now()})
        fx.p["phase"] = "impl"
        fx.save()
        print(f"arbitrage clos : test {args[1]} · phase impl")
    else:
        die("arbitrate <nom> open|close …")


def cmd_deviation(fx, args):
    need(args, 2, 'deviation <nom> "<raison>" <fichier>…')
    entry = {"at": now(), "files": args[1:], "reason": args[0]}
    fx.p.setdefault("plan_deviations", []).append(entry)
    fx.save()
    print(f"écart au plan tracé ({len(fx.p['plan_deviations'])}) : {', '.join(args[1:])}")


# ---------------------------------------------------------------------------
# Revue
# ---------------------------------------------------------------------------
def review_file(fx):
    return os.path.join(fx.dir, "review.json")


def cmd_review_pass(fx, args):
    """Verdict de la revue de Victor, tranché par le gauntlet (ADR 0003) : jamais écrit à la main."""
    review = statefile.load(review_file(fx), default={"_absent": True})
    if review.get("_absent"):
        die("review.json absent : Victor n'a pas rendu sa revue")
    debt = fx.p.setdefault("debt", [])
    added = 0
    for d in review.get("debt") or []:
        if not isinstance(d, dict) or not d.get("file") or not d.get("issue"):
            continue
        entry = {"source": "review", "file": d["file"], "issue": d["issue"]}
        if isinstance(d.get("line"), int):
            entry["line"] = d["line"]
        if entry not in debt:
            debt.append(entry)
            added += 1
    r = subprocess.run(["bash", GAUNTLET, "review_verdict", fx.name], cwd=fx.root, capture_output=True, text=True)
    ok = r.returncode == 0
    if ok:
        fx.p.setdefault("stages", {})["review"] = {"status": "PASSED", "at": now()}
    fx.save()
    print("\n".join(l for l in r.stdout.splitlines() if l.strip())[-3000:])
    print(f"dette reportée depuis review.json : {added}")
    print("stages.review = PASSED — suggestions à montrer à Thibault, puis étape 4 ou 5" if ok
          else "revue rouge : critiques ou « à vérifier » ouverts (ci-dessus) — loop <nom> review, puis Fanny / Bastien")
    sys.exit(0 if ok else 1)


def cmd_accept(fx, args):
    need(args, 2, 'accept <nom> review "<raison>"')
    if args[0] != "review":
        die("accept : seule la revue s'accepte (accept <nom> review \"<raison>\")")
    reason = args[1]
    n = [0]

    def mark(rv):
        for c in rv.get("critical") or []:
            if isinstance(c, dict) and c.get("accepted") is not True:
                c["accepted"], c["accepted_reason"] = True, reason
                n[0] += 1
    if not os.path.isfile(review_file(fx)):
        die("review.json absent : rien à accepter")
    statefile.update(review_file(fx), mark)
    pl.cmd_accept(fx, ["review", reason])
    print(f"{n[0]} critique(s) acceptée(s) dans review.json — rejoue review-pass {fx.name}")


def cmd_loop(fx, args):
    need(args, 1, "loop <nom> review|arbitrate|ui")
    if args[0] not in ("review", "arbitrate", "ui"):
        die("boucle : review | arbitrate | ui")
    if args[0] == "arbitrate":
        die("loops.arbitrate se compte à l'ouverture d'un arbitrage (arbitrate <nom> open …)")
    pl.cmd_loop(fx, args[:1])


# ---------------------------------------------------------------------------
# Écritures simples
# ---------------------------------------------------------------------------
def cmd_set(fx, args):
    need(args, 2, "set <nom> suggestions.<id>|issue|watchdog_cron <valeur>")
    key, raw = args[0], args[1]
    if key.startswith("suggestions."):
        sid = key.split(".", 1)[1]
        if not sid or not sid.replace("_", "").replace("-", "").isalnum():
            die(f"identifiant de suggestion invalide : {sid!r}")
        try:
            val = json.loads(raw)
        except json.JSONDecodeError:
            die("suggestion : JSON attendu, {\"decision\": \"applied|skipped|debt\", \"note\": \"…\"}")
        if not isinstance(val, dict) or val.get("decision") not in SUGGESTION_DECISIONS \
                or set(val) - {"decision", "note"} or not isinstance(val.get("note", ""), str):
            die("suggestion : {\"decision\": \"applied|skipped|debt\", \"note\": \"…\"} et rien d'autre")
    elif key == "issue":
        try:
            val = json.loads(raw)
        except json.JSONDecodeError:
            die("issue : JSON attendu (la référence stockée de ~/.claude/pipeline/tracker.md)")
        if not isinstance(val, dict) or not isinstance(val.get("status"), str):
            die("issue : un objet avec au moins status (none | to_create | existing | created)")
    elif key == "watchdog_cron":
        if not raw.strip() or any(ch.isspace() for ch in raw.strip()):
            die("watchdog_cron : l'id rendu par CronCreate, sans espace")
    else:
        die("set : suggestions.<id> | issue | watchdog_cron — le reste a sa commande (voir --help)")
    pl.cmd_set(fx, [key, raw])


def cmd_pass(fx, args):
    need(args, 1, "pass <nom> evidence")
    if args[0] in GATE_STAGES:
        die(f"stages.{args[0]} est un verdict de gate : écrit par le hook de fin d'agent ou review-pass, jamais à la main (ADR 0003)")
    if args[0] not in HAND_STAGES:
        die(f"pass : {' | '.join(sorted(HAND_STAGES))}")
    pl.clear_waiting(fx.p)
    pl.cmd_pass(fx, args[:1])
    cur = os.path.join(fx.root, ".claude", "fixes", ".current")
    if os.path.isfile(cur) and open(cur, encoding="utf-8").read().strip() == fx.name:
        os.unlink(cur)
        print(".claude/fixes/.current retiré")


def cmd_skip(fx, args):
    need(args, 2, 'skip <nom> evidence "<raison>"')
    if args[0] in GATE_STAGES:
        die(f"stages.{args[0]} est un verdict de gate : il ne se saute pas à la main (ADR 0003)")
    if args[0] not in HAND_STAGES:
        die(f"skip : {' | '.join(sorted(HAND_STAGES))}")
    pl.cmd_skip(fx, args[:2])


COMMANDS = {
    "init": cmd_init, "agent": cmd_agent, "after": cmd_after, "gate": cmd_gate, "freeze": cmd_freeze,
    "refreeze": cmd_refreeze, "phase": cmd_phase, "arbitrate": cmd_arbitrate, "deviation": cmd_deviation,
    "review-pass": cmd_review_pass, "loop": cmd_loop, "debt": pl.cmd_debt, "accept": cmd_accept, "set": cmd_set,
    "ask": pl.cmd_ask, "recap": pl.cmd_recap, "pass": cmd_pass, "skip": cmd_skip,
}


def main(argv):
    if len(argv) < 2 or argv[0] in ("-h", "--help") or argv[0] not in COMMANDS:
        print(__doc__)
        sys.exit(0 if argv[:1] in (["-h"], ["--help"]) else 2)
    cmd, name, rest = argv[0], argv[1], argv[2:]
    COMMANDS[cmd](Fix(name, must_exist=cmd != "init"), rest)


if __name__ == "__main__":
    main(sys.argv[1:])
