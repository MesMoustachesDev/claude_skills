#!/usr/bin/env python3
"""mr.py — la MR qu'un relecteur lit, pas le rapport du pipeline.

Partagé par /feature (étape 9) et /fix (étape 5). evidence.md reste la page du dev ; mr.md est la
description de MR, écrite pour un collègue qui ne connaît ni le pipeline ni ses agents.

Usage (depuis le worktree) :
  mr.py check <mr.md> <base>        refuse un corps de MR qui parle du pipeline, ou une branche qui
                                    embarque ses fichiers ; code de sortie 1 avec la liste des refus
  mr.py untrack <feature|fix> <nom> <base>
                                    ramène .claude/ à son état de la base, en un commit (le gel de /fix
                                    commite repro.json et diagnosis.md) ; les fichiers restent sur disque
  mr.py archive <feature|fix> <nom> <base>
                                    copie .claude/<features|fixes>/<nom>/ dans le checkout principal,
                                    sous .claude/archive/ (exclu localement), et y recopie les règles
                                    .claude/rules/ que le run a changées, non commitées
"""
import glob
import os
import re
import shutil
import subprocess
import sys

MAX_LINES = 60
AGENTS_DIR = os.path.expanduser("~/.claude/agents")
# Le vocabulaire du pipeline : un relecteur ne le connaît pas.
JARGON = (r"\bre-?gel", r"\bgel(é|ée|és|ées)?\b", r"\bgabarit", r"\bgauntlet", r"\bevidence\b",
          r"pipeline\.json", r"\borchestrat", r"DÉCISION \(", r"\bcockpit", r"(^|\s)/(feature|fix|epic)\b",
          r"\blearn\b", r"\bsous-agent", r"\bsubagent", r"\bmutants? expliqués")
PATHS = (r"~/\.claude", r"(^|[\s`(])\.claude/")
REQUIRED = ("## Summary", "## Changes", "## Test plan")


def git(cwd, *args, check=True):
    r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    if check and r.returncode != 0:
        sys.exit(f"git {' '.join(args)} : {r.stderr.strip()}")
    return r.stdout.strip()


def agent_names():
    """Le prénom de chaque agent, tiré de sa description (« Sophie — Étape 1… »)."""
    names = set()
    for path in glob.glob(os.path.join(AGENTS_DIR, "*.md")):
        with open(path, encoding="utf-8") as f:
            m = re.search(r"^description:\s*[\"']?([A-ZÀ-Ý][\wÀ-ſ-]+)[ ,]", f.read(), re.M)
        if m:
            names.add(m.group(1))
    return names | {"Thibault"}


def cmd_check(body_path, base):
    with open(body_path, encoding="utf-8") as f:
        body = f.read()
    lines = body.splitlines()
    refus = []
    if len(lines) > MAX_LINES:
        refus.append(f"{len(lines)} lignes (max {MAX_LINES}) : le détail reste dans evidence.md")
    for h in REQUIRED:
        if not any(l.strip() == h for l in lines):
            refus.append(f"section « {h} » absente")
    names = agent_names()
    for i, line in enumerate(lines, 1):
        for n in sorted(names):
            if re.search(rf"\b{re.escape(n)}\b", line):
                refus.append(f"l.{i} : « {n} » (un agent ou le dev, inconnu du relecteur)")
        for p in JARGON:
            if re.search(p, line, re.I):
                refus.append(f"l.{i} : vocabulaire du pipeline ({re.search(p, line, re.I).group(0).strip()})")
        for p in PATHS:
            if re.search(p, line):
                refus.append(f"l.{i} : chemin .claude")
    mb = git(".", "merge-base", base, "HEAD")
    for f in git(".", "diff", "--name-only", f"{mb}...HEAD").splitlines():
        if f.startswith(".claude/"):
            refus.append(f"branche : {f} (fichier du pipeline dans le diff de la MR)")
    if refus:
        print("\n".join(refus))
        sys.exit(1)
    print(f"ok · {len(lines)} lignes")


def run_dir(kind, name):
    return os.path.join(".claude", "features" if kind == "feature" else "fixes", name)


def cmd_untrack(kind, name, base):
    """Ramène tout .claude/ à son état de la base, dans un commit ; les fichiers restent sur disque
    (lance archive avant : les règles modifiées y sont recopiées dans le checkout principal)."""
    mb = git(".", "merge-base", base, "HEAD")
    rows = [l.split("\t") for l in git(".", "diff", "--name-status", "--no-renames", f"{mb}...HEAD", "--", ".claude").splitlines()]
    if not rows:
        print("rien à retirer")
        return
    added = [f for st, f in rows if st == "A"]
    others = [f for st, f in rows if st != "A"]
    if added:
        git(".", "rm", "-r", "-q", "--cached", "--", *added)
    if others:
        git(".", "checkout", mb, "--", *others)
    git(".", "commit", "-q", "-m", "chore: remove working files from the branch")
    print(f"retirés de la branche : {len(added)} ajoutés (gardés sur disque), {len(others)} remis comme sur la base"
          f" · {git('.', 'rev-parse', '--short', 'HEAD')}")


def cmd_archive(kind, name, base):
    common = os.path.abspath(git(".", "rev-parse", "--git-common-dir"))
    main = os.path.dirname(common)
    src = run_dir(kind, name)
    dst = os.path.join(main, ".claude", "archive", os.path.basename(os.path.dirname(src)), name)
    exclude = os.path.join(common, "info", "exclude")
    os.makedirs(os.path.dirname(exclude), exist_ok=True)
    have = open(exclude, encoding="utf-8").read() if os.path.exists(exclude) else ""
    if ".claude/archive/" not in have.split("\n"):
        with open(exclude, "a", encoding="utf-8") as f:
            f.write(("" if have.endswith("\n") or not have else "\n") + ".claude/archive/\n")
    if os.path.abspath(src) != os.path.abspath(dst):
        shutil.copytree(src, dst, dirs_exist_ok=True)
    print(f"archivé : {dst}")
    # Règles de projet ajoutées par le run : recopiées dans le checkout principal, non commitées.
    mb = git(".", "merge-base", base, "HEAD")
    files = sorted(set(git(".", "diff", "--name-only", mb, "--", ".claude/rules").splitlines())
                   | set(git(".", "ls-files", "--others", "--exclude-standard", "--", ".claude/rules").splitlines()))
    for f in files:
        if os.path.isfile(f):
            os.makedirs(os.path.dirname(os.path.join(main, f)), exist_ok=True)
            shutil.copy2(f, os.path.join(main, f))
            print(f"règle recopiée, à commiter à part : {os.path.join(main, f)}")


def main():
    a = sys.argv[1:]
    if a[:1] == ["check"] and len(a) == 3:
        cmd_check(a[1], a[2])
    elif a[:1] == ["untrack"] and len(a) == 4 and a[1] in ("feature", "fix"):
        cmd_untrack(a[1], a[2], a[3])
    elif a[:1] == ["archive"] and len(a) == 4 and a[1] in ("feature", "fix"):
        cmd_archive(a[1], a[2], a[3])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
