#!/usr/bin/env python3
"""statefile.py — lire et écrire un fichier d'état JSON du pipeline (pipeline.json, fix.json, review.json,
patterns.json de learn) sans perdre une écriture concurrente.

    import statefile
    state = statefile.load(path)                       # {} si absent
    state = statefile.update(path, fn)                 # verrou, relit, fn(state) le modifie, écrit
    state = statefile.save_changes(path, base, ours)   # verrou, relit, applique ce qui a changé de base à ours

`update` prend `fcntl.flock` sur `<fichier>.lock`, relit le fichier sous le verrou, applique `fn`, écrit
dans un `.tmp` unique puis `os.replace` : deux écrivains ne s'effacent plus. `save_changes` sert aux
scripts qui chargent l'état au début d'une commande et le modifient ensuite (pipeline.py, review.py,
fix/steps.py) : seul ce que la commande a changé est réappliqué sur l'état relu, le reste (une clé
écrite entre-temps par un hook ou une autre commande) est gardé. Une liste rallongée par la commande
reçoit ses ajouts à la suite de la liste relue.

En ligne de commande, pour les hooks shell (même verrou) :

    statefile.py jq <fichier> <filtre jq> [arguments de jq…]   applique le filtre sous le verrou
"""
import datetime
import fcntl
import json
import os
import subprocess
import sys
import tempfile

_MISSING = object()


def die(msg, code=2):
    print(f"[ABORT] {msg}", file=sys.stderr)
    sys.exit(code)


def now():
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def read_text(path, limit=None):
    """Le texte du fichier, None s'il est illisible ; `limit` : tronqué, avec la mention du fichier complet."""
    try:
        with open(path, encoding="utf-8") as f:
            t = f.read()
    except OSError:
        return None
    if limit and len(t) > limit:
        t = t[:limit] + f"\n\n… (tronqué, {len(t)} caractères : fichier complet {path})"
    return t


def load(path, default=None):
    """L'état du fichier ; `default` ({} si non précisé) s'il est absent. Un JSON cassé arrête tout."""
    text = read_text(path)
    if text is None:
        return {} if default is None else default
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        die(f"{path} : JSON illisible ({e})")


def _write(path, state):
    d = os.path.dirname(os.path.abspath(path))
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=os.path.basename(path) + ".", suffix=".tmp", dir=d)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(state, f, ensure_ascii=False, indent=2)
            f.write("\n")
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


class _Lock:
    def __init__(self, path):
        self.path = path + ".lock"

    def __enter__(self):
        os.makedirs(os.path.dirname(os.path.abspath(self.path)), exist_ok=True)
        self.fd = os.open(self.path, os.O_RDWR | os.O_CREAT, 0o644)
        fcntl.flock(self.fd, fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        fcntl.flock(self.fd, fcntl.LOCK_UN)
        os.close(self.fd)


def update(path, fn, default=None):
    """Sous le verrou : relit, `fn(state)` (modifie sur place ou rend le nouvel état), écrit. Rend l'état écrit."""
    with _Lock(path):
        state = load(path, default)
        out = fn(state)
        state = state if out is None else out
        _write(path, state)
        return state


def merge(base, ours, theirs):
    """Ce qui a changé de `base` à `ours`, réappliqué sur `theirs` (l'état relu)."""
    if ours == base:
        return theirs
    if isinstance(ours, dict) and isinstance(base, dict) and isinstance(theirs, dict):
        out = dict(theirs)
        for k in set(base) | set(ours):
            o, b = ours.get(k, _MISSING), base.get(k, _MISSING)
            if o == b:
                continue
            if o is _MISSING:
                out.pop(k, None)
                continue
            out[k] = merge(b, o, theirs.get(k, _MISSING)) if b is not _MISSING else o
        return out
    if isinstance(ours, list) and isinstance(base, list) and isinstance(theirs, list) and ours[:len(base)] == base:
        return theirs + [x for x in ours[len(base):] if x not in theirs]
    return ours   # valeur changée par la commande : la sienne l'emporte


def save_changes(path, base, ours):
    """Sous le verrou : relit l'état et y applique ce que la commande a changé depuis `base`. Rend l'état écrit."""
    return update(path, lambda theirs: merge(base, ours, theirs))


def _cli(argv):
    if len(argv) < 3 or argv[0] != "jq":
        print(__doc__)
        sys.exit(0 if argv[:1] in (["-h"], ["--help"]) else 2)
    path, args = argv[1], argv[2:]

    def apply(state):
        r = subprocess.run(["jq", *args], input=json.dumps(state), capture_output=True, text=True)
        if r.returncode != 0:
            die(f"jq : {r.stderr.strip()}")
        try:
            return json.loads(r.stdout)
        except json.JSONDecodeError:
            die("jq : sortie qui n'est pas un JSON")

    update(path, apply)


if __name__ == "__main__":
    _cli(sys.argv[1:])
