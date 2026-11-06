"""stacklib.py — le langage d'un chemin et ses valeurs, pour les scripts Python du pipeline (pipeline.py,
review.py, report.py). Passe par scripts/stack.sh, seule source de la détection et des valeurs (ADR 0011) ;
les langages lus sont ceux de ce checkout (stacks/ à côté de scripts/), comme pour le gauntlet.

    import stacklib
    stacklib.get_list("contract_globs", "/repo/features/login")   # ['*/domain/*', '*/keys.dart', …]
    stacklib.is_package("/repo/features/login")                   # True : un marqueur (pubspec.yaml…) est là
"""
import functools
import os
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
STACK_SH = os.path.join(HERE, "stack.sh")
STACKS = os.environ.get("CLAUDE_STACKS_DIR") or os.path.join(os.path.dirname(HERE), "stacks")


@functools.lru_cache(maxsize=None)
def _run(*args):
    env = dict(os.environ, CLAUDE_STACKS_DIR=STACKS)
    p = subprocess.run(["bash", STACK_SH, *args], capture_output=True, text=True, env=env)
    return p.returncode, p.stdout.rstrip("\n")


def detect(path):
    """Le langage du package qui contient path ('flutter', 'android'…), '' si aucun marqueur."""
    rc, out = _run("detect", path)
    return out if rc == 0 else ""


def get(key, path):
    """Valeur de key pour le langage de path : config du projet, sinon stack.ini ; '' si aucune."""
    rc, out = _run("get", key, path)
    return out if rc == 0 else ""


def get_list(key, path):
    """Valeur à virgules en liste, vides ignorés."""
    return [v.strip() for v in get(key, path).split(",") if v.strip()]


@functools.lru_cache(maxsize=None)
def markers():
    """Marqueurs de package de tous les langages connus (pubspec.yaml, build.gradle.kts…)."""
    return tuple(m for m in _run("markers")[1].splitlines() if m)


def is_package(d):
    """d porte le marqueur d'un langage connu."""
    return any(os.path.exists(os.path.join(d, m)) for m in markers())
