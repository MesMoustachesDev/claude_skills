#!/usr/bin/env python3
"""hook_journal.py — lit le journal des décisions des hooks d'un run (ADR 0019).

Écrit par scripts/gauntlet/hook_log.sh dans <run>/.gauntlet/hooks.jsonl (<run> = .claude/features/<nom> ou
.claude/fixes/<nom>) ; lu ici, et seulement ici, par learn.py extract, le rapport (report.py) et l'evidence.

    hook_journal.py summary <dossier du run>     Markdown pour l'evidence ; rien si le journal est vide

Ce qu'on en tire :
  - les refus par agent et par étape (deny, et les gates red / failed) ;
  - les contournements : un refus sur un fichier, puis une écriture permise du même fichier par un autre
    outil, ou d'un fichier du même nom ailleurs (la copie d'un test gelé) ;
  - les refus répétés : le même agent refusé au moins deux fois sur la même zone.
"""
import json
import os
import sys
from collections import Counter, OrderedDict

# L'étape d'un agent. Les gates écrivent aussi leur profil (stage) : il sert quand l'agent est inconnu.
STAGES = {
    "feature-specifier": "1 spec", "feature-spec-critic": "1 spec", "feature-architect": "2 contrats",
    "feature-dedup": "2 contrats", "feature-test-planner": "3a liste", "feature-test-writer": "3 tests",
    "feature-test-writer-data": "3 tests", "feature-test-writer-presentation": "3 tests",
    "feature-test-reviewer": "3 tests", "feature-implementer": "4 green", "feature-implementer-data": "4 green",
    "feature-implementer-presentation": "4 green", "feature-cleaner": "5 clean", "feature-reviewer": "6 revue",
    "feature-hardener": "7 mutation", "feature-qa": "8 qa", "feature-polisher": "8c polish",
    "fix-reproducer": "1 repro", "fix-implementer": "2 correction", "fix-reviewer": "3 revue",
}
REFUSALS = ("deny", "ask", "red", "failed")


def load(run_dir):
    path = os.path.join(run_dir, ".gauntlet", "hooks.jsonl")
    rows = []
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                try:
                    r = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if isinstance(r, dict):
                    rows.append(r)
    except OSError:
        pass
    return rows


def stage_of(row):
    """L'étape de l'agent (une ligne par agent et étape, refus et gates ensemble) ; à défaut, celle de la ligne."""
    return STAGES.get(row.get("agent", "")) or row.get("stage") or "?"


def counts(rows):
    """{(agent, étape): Counter(issue)} pour les refus seulement, dans l'ordre d'apparition."""
    out = OrderedDict()
    for r in rows:
        if r.get("outcome") in REFUSALS:
            out.setdefault((r.get("agent", "?"), stage_of(r)), Counter())[r["outcome"]] += 1
    return out


def _is_path(t):
    return bool(t) and "\n" not in t and " " not in t.strip() and ("/" in t or "." in t)


def bypasses(rows):
    """Refus d'un fichier, puis écriture permise par le même agent :
      - du même fichier par un autre outil (Edit refusé, Bash passé) ;
      - d'un fichier du même nom ailleurs (test gelé refusé, recopié à la racine du package : cas réel).
    Un interpréteur refusé puis le fichier écrit par Edit n'en est pas un : c'est ce que le refus demande.
    Rend [(refus, écriture, comment)]."""
    found, seen = [], set()
    for i, d in enumerate(rows):
        tgt = d.get("target", "")
        if d.get("outcome") != "deny" or not _is_path(tgt):
            continue
        for a in rows[i + 1:]:
            at = a.get("target", "")
            if a.get("outcome") != "allow" or a.get("agent") != d.get("agent") or not _is_path(at):
                continue
            how = ("autre outil" if at == tgt and a.get("tool") != d.get("tool")
                   else "copie" if at != tgt and os.path.basename(at) == os.path.basename(tgt) else "")
            if how and (i, at) not in seen:
                seen.add((i, at))
                found.append((d, a, how))
                break
    return found


def _zone(row):
    t = row.get("target", "")
    if _is_path(t):
        return os.path.dirname(t) or t
    return (row.get("reason", "").split(" : ")[-1])[:60]


def repeats(rows, min_count=2):
    """Le même agent refusé au moins min_count fois sur la même zone : [(agent, hook, zone, n, exemple)]."""
    c, ex = Counter(), {}
    for r in rows:
        if r.get("outcome") == "deny":
            k = (r.get("agent", "?"), r.get("hook", "?"), _zone(r))
            c[k] += 1
            ex.setdefault(k, r)
    return [(a, h, z, n, ex[(a, h, z)]) for (a, h, z), n in c.items() if n >= min_count]


def _cut(s, n):
    s = " ".join(str(s or "").split())
    return s if len(s) <= n else s[: n - 1] + "…"


def summary_md(run_dir):
    rows = load(run_dir)
    cnt = counts(rows)
    if not cnt:
        return ""
    lines = ["## Refus des hooks", "", "| Agent | Étape | Refus | Gate rouge | Gate FAILED |", "|---|---|---|---|---|"]
    for (agent, stage), c in cnt.items():
        lines.append(f"| {agent} | {stage} | {c['deny'] + c['ask']} | {c['red']} | {c['failed']} |")
    bp = bypasses(rows)
    if bp:
        lines += ["", "Refus suivis d'un contournement (même fichier écrit par un autre chemin) :", ""]
        for d, a, how in bp:
            lines.append(f"- {d.get('agent')} : `{_cut(d.get('target'), 80)}` refusé par {d.get('hook')} "
                         f"({d.get('tool')}), puis `{_cut(a.get('target'), 80)}` écrit par {a.get('tool')} ({how})"
                         f" — {_cut(d.get('reason'), 120)}")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] != "summary":
        print("usage : hook_journal.py summary <dossier du run>", file=sys.stderr)
        sys.exit(2)
    sys.stdout.write(summary_md(sys.argv[2]))
