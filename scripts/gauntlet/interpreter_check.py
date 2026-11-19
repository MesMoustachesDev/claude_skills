#!/usr/bin/env python3
"""interpreter_check.py <cwd> [scratchpad] — lit une commande Bash sur stdin ; si elle lance un interpréteur
avec du code que personne n'a relu, imprime la raison (une ligne) ; sinon n'imprime rien.

Utilisé par hooks/no-interpreter.sh, pour les sous-agents feature-* et fix-* (ADR 0017). Refusé :
  - python, perl, ruby, node, deno, bun, php avec du code inline : `-c`, `-e` (et leurs cousins : `-pe`,
    `-0pi`, `node -p`, `php -r`), `-` ou `/dev/stdin`, un heredoc, `<<<`, ou sans script (code lu sur
    l'entrée standard, `… | python3`) ;
  - les mêmes derrière `bash -c`, `sh -c`, `eval`, `env`, `xargs`, `find -exec`, `timeout`, `fvm`, un
    chemin absolu (`/usr/bin/python3`) : on regarde à travers ;
  - l'exécution d'un script écrit pendant la session : sous le scratchpad ou /tmp, absent, ou, dans un
    dépôt git, non suivi, ignoré ou modifié depuis HEAD. Vaut pour les interpréteurs ci-dessus, `dart`
    (`dart run x.dart`), `bash x.sh` / `source`, et un exécutable lancé par son chemin (`./gen.sh`) ;
  - un shell qui lit son script sur l'entrée standard (`bash <<EOF`, `… | sh`) ;
  - les éditions en place `perl -pi`, `awk -i inplace`.
Permis : les scripts du pipeline (`python3 [-I] ~/.claude/scripts/…`, `$HOME/…` ou chemin absolu
équivalent), un module (`python3 -m json.tool`, `-m pytest`), les lanceurs de tests (`node --test`,
`deno test`, `bun test`), `--version`, et un script suivi et inchangé du projet.

Ce n'est pas un parseur shell : un exécutable lancé par un chemin dont une variable reste inconnue passe
(on ne décide pas sur un chemin inconnu), et awk sans `-i inplace` passe. Le gauntlet reste le filet.
"""
import os
import re
import shlex
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bash_write_targets import OPS, strip_heredocs  # noqa: E402

PIPELINE_SCRIPTS = os.path.realpath(os.path.expanduser("~/.claude/scripts")) + os.sep
INTERP = re.compile(r"(python[0-9.]*|pythonw|perl[0-9.]*|ruby[0-9.]*|node|nodejs|deno|bun|php[0-9.]*)")
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
WRAPPERS = {"time", "nohup", "command", "exec", "builtin", "caffeinate", "rtk", "fvm", "then", "do",
            "else", "elif", "if", "while", "until", "!", "{", "}"}
STDIN_REDIRS = ("<<", "<<-", "<<<")


class Deny(Exception):
    pass


class Ctx:
    def __init__(self, cwd, scratch):
        self.cwd, self.scratch = cwd, scratch
        # INTERPRETER_TMP_DIRS (a:b) : surcharge pour les tests, dont le dépôt vit sous $TMPDIR
        dirs = os.environ.get("INTERPRETER_TMP_DIRS", "").split(":") if os.environ.get("INTERPRETER_TMP_DIRS") \
            else ["/tmp", "/private/tmp", "/var/folders", os.environ.get("TMPDIR", "/tmp")]
        self.tmp = [os.path.realpath(p) + os.sep for p in dirs if p]
        if scratch:
            self.tmp.append(os.path.realpath(scratch) + os.sep)


def expand(tok, env):
    """$VAR, ${VAR} et ~ ; None si une variable reste inconnue (boucle, $(…))."""
    out = re.sub(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?", lambda m: env.get(m.group(1), "\0"), tok)
    if "\0" in out or "$" in out or "`" in out:
        return None
    return os.path.expanduser(out)


def resolve(base, tok, env):
    p = expand(tok, env)
    if p is None or base is None and not os.path.isabs(p):
        return None
    return os.path.realpath(p if os.path.isabs(p) else os.path.join(base, p))


def written_in_session(path, ctx):
    """Une raison si le script a pu être écrit pendant la session, None s'il est relu (suivi, inchangé)."""
    if path.startswith(PIPELINE_SCRIPTS):
        return None
    if any(path.startswith(t) for t in ctx.tmp):
        return "script dans le scratchpad ou /tmp, écrit pendant la session"
    if not os.path.isfile(path):
        return "script absent (écrit dans la même commande ?)"
    if "/node_modules/" in path:
        return None
    d = os.path.dirname(path)
    try:
        r = subprocess.run(["git", "-C", d, "status", "--porcelain", "--ignored", "--", path],
                           capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if r.returncode != 0:                   # hors de tout dépôt : un outil installé
        return None
    st = r.stdout[:2]
    if st == "??":
        return "script non suivi par git, écrit pendant la session"
    if st == "!!":
        return "script ignoré par git, écrit pendant la session"
    if st.strip():
        return "script modifié depuis le dernier commit"
    return None


def deny_script(tok, base, env, ctx, prog, strict=True):
    """Le script `tok` lancé par `prog` : refusé s'il a pu être écrit pendant la session."""
    p = resolve(base, tok, env)
    if p is None:
        if strict:
            raise Deny(f"{prog} {tok} : chemin du script inconnu (variable ou dossier non résolu)")
        return
    why = written_in_session(p, ctx)
    if why:
        raise Deny(f"{prog} {tok} : {why}")


def has_stdin_code(seg):
    return any(t in STDIN_REDIRS for t in seg)


def check_interp(prog, args, seg, base, env, ctx, piped):
    """python, perl, ruby, node, deno, bun, php."""
    fam = re.match(r"[a-z]+", prog).group(0)
    fam = {"pythonw": "python", "nodejs": "node"}.get(fam, fam)
    inline_flags = {"python": "c", "perl": "eE", "ruby": "e", "node": "ep", "php": "rRBEF", "bun": "e",
                    "deno": ""}[fam]
    if len(args) == 1 and args[0] in ("--version", "-V", "-v", "--help", "-h"):
        return
    i = 0
    while i < len(args):
        a = args[i]
        if fam == "node" and a in ("--eval", "--print"):
            raise Deny(f"{prog} {a} : code inline")
        if fam == "node" and a == "--test":                     # lanceur de tests du projet
            files = [resolve(base, f, env) for f in args[i + 1:] if not f.startswith("-")]
            if any(p and any(p.startswith(t) for t in ctx.tmp) for p in files + [base]):
                raise Deny(f"{prog} --test dans le scratchpad ou /tmp : tests copiés hors du projet")
            return
        if fam in ("deno", "bun") and a in ("eval", "repl"):
            raise Deny(f"{prog} {a} : code inline")
        if fam in ("deno", "bun") and a in ("test", "fmt", "lint", "check", "install", "add", "upgrade"):
            return
        if fam in ("deno", "bun") and a == "run":
            i += 1
            continue
        if a == "-":
            raise Deny(f"{prog} - : code lu sur l'entrée standard")
        if a == "--":
            i += 1
            break
        if a.startswith("--"):
            i += 1
            continue
        if not (a.startswith("-") and len(a) > 1):
            break
        flags = a[1:]
        if fam == "perl" and flags[:1] in ("M", "m", "I", "x", "V"):
            i += 1                                              # -Mstrict, -Ilib : valeur collée
            continue
        if fam == "python" and flags[:1] in ("W", "X"):
            i += 1 if len(flags) > 1 else 2
            continue
        letters = re.sub(r"^0[0-7]*", "", flags) if fam == "perl" else flags
        if any(c in inline_flags for c in letters):
            raise Deny(f"{prog} {a} : code inline")
        if fam == "perl" and "i" in letters:
            raise Deny(f"{prog} {a} : édition en place (perl -pi), invisible au hook d'écriture")
        if fam == "python" and "m" in letters:
            return                                              # module : python3 -m json.tool
        if fam == "php" and letters == "f" and i + 1 < len(args):
            i += 1
            break
        i += 1 if not (fam == "node" and letters == "r") else 2
    rest = args[i:]
    if not rest:
        if has_stdin_code(seg) or piped:
            raise Deny(f"{prog} : code lu sur l'entrée standard (heredoc, <<< ou tube)")
        raise Deny(f"{prog} sans script : code lu sur l'entrée standard")
    script = rest[0]
    if script in ("/dev/stdin", "/dev/fd/0") or script.startswith("<("):
        raise Deny(f"{prog} {script} : code lu sur l'entrée standard")
    if fam in ("deno", "bun") and not re.search(r"[/.]", script):
        return                                                  # `bun run build` : script de package.json
    deny_script(script, base, env, ctx, prog)


def check_segment(words, seg, base, env, ctx, piped, depth):
    while words:
        w = words[0].lstrip("`")
        if w in WRAPPERS or w == "":
            words = words[1:]
            continue
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", w):
            words = words[1:]
            continue
        if w == "env":
            words = words[1:]
            while words and (words[0].startswith("-") or "=" in words[0]):
                words = words[1:]
            continue
        if w in ("timeout", "gtimeout"):
            words = words[1:]
            while words and words[0].startswith("-"):
                words = words[1:]
            words = words[1:]                                   # la durée
            continue
        if w in ("nice", "stdbuf", "sudo"):
            words = words[1:]
            while words and words[0].startswith("-"):
                words = words[2:] if words[0] in ("-n", "-u") else words[1:]
            continue
        break
    if not words:
        return
    first = words[0].lstrip("`")
    prog, args = os.path.basename(first), words[1:]

    if prog == "eval":
        text = " ".join(args)
        if "$" in text:
            raise Deny("eval d'une variable : code inconnu")
        return check(text, base, env, ctx, depth + 1)
    if prog in SHELLS:
        i = 0
        while i < len(args) and args[i].startswith("-") and args[i] != "-":
            if "c" in args[i][1:] and not args[i].startswith("--"):
                if i + 1 >= len(args):
                    raise Deny(f"{prog} -c sans commande")
                return check(args[i + 1], base, env, ctx, depth + 1)
            if args[i] in ("-s",):
                raise Deny(f"{prog} -s : script lu sur l'entrée standard")
            i += 1
        rest = args[i:]
        if not rest or rest[0] == "-":
            if has_stdin_code(seg) or piped:
                raise Deny(f"{prog} : script lu sur l'entrée standard (heredoc ou tube), invisible aux hooks")
            return                                              # shell interactif : rien à juger
        deny_script(rest[0], base, env, ctx, prog)
        return
    if prog in ("source", "."):
        if args:
            deny_script(args[0], base, env, ctx, prog)
        return
    if prog == "xargs":
        i = 0
        while i < len(args) and args[i].startswith("-"):
            i += 2 if args[i] in ("-I", "-n", "-P", "-L", "-d", "-E", "-s", "-a") else 1
        if i < len(args):
            return check_segment(args[i:], seg, base, env, ctx, True, depth)
        return
    if prog in ("find",):
        for k, a in enumerate(args):
            if a in ("-exec", "-execdir", "-ok", "-okdir") and k + 1 < len(args):
                end = next((j for j in range(k + 1, len(args)) if args[j] in ("+", ";")), len(args))
                check_segment(args[k + 1:end], seg, base, env, ctx, False, depth)
        return
    if prog in ("awk", "gawk"):
        for k, a in enumerate(args):
            if (a == "-i" and k + 1 < len(args) and args[k + 1] == "inplace") or a in ("-iinplace",
                                                                                      "--include=inplace"):
                raise Deny(f"{prog} -i inplace : édition en place, invisible au hook d'écriture")
        return
    if INTERP.fullmatch(prog):
        return check_interp(prog, args, seg, base, env, ctx, piped)
    if prog == "dart":
        rest = [a for a in args if not a.startswith("-")]
        if rest[:1] == ["run"]:
            rest = rest[1:]
        if rest and rest[0].endswith(".dart"):
            deny_script(rest[0], base, env, ctx, "dart")
        return
    if "/" in first:                                            # ./gen.sh, /tmp/x, $S/run.sh
        deny_script(first, base, env, ctx, "exécutable", strict=False)


def check(cmd, cwd, env, ctx, depth=0):
    if depth > 5:
        raise Deny("commande imbriquée trop profond")
    body = strip_heredocs(cmd).replace("\\\n", " ").replace("\n", " ; ")
    try:
        lex = shlex.shlex(body, posix=True, punctuation_chars=";&|()<>")
        lex.whitespace_split = True
        lex.commenters = ""
        tokens = list(lex)
    except ValueError:
        if INTERP.search(body):
            raise Deny("commande illisible (guillemets non fermés) qui nomme un interpréteur")
        return
    base, seg, piped = cwd, [], False
    segs = []
    for t in tokens + [";"]:
        if t in OPS:
            if seg:
                segs.append((seg, piped))
            piped = t in ("|", "|&")
            seg = []
        else:
            seg.append(t)
    for seg, piped in segs:
        words, i = [], 0
        while i < len(seg):
            t = seg[i]
            if t in (">", ">>", "&>", "&>>", ">|", "<") or t in STDIN_REDIRS or re.fullmatch(r"[0-9]+>>?", t):
                i += 2
                continue
            words.append(t)
            i += 1
        w0 = words[0] if words else ""
        if w0 in ("export", "local", "readonly"):
            words = words[1:]
        while words and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", words[0]):
            k, v = words[0].split("=", 1)
            v = expand(v, env)
            if v is not None:
                env[k] = v
            else:
                env.pop(k, None)
            words = words[1:]
        if words and words[0] == "cd":
            base = resolve(base, words[1], env) if len(words) > 1 else os.path.expanduser("~")
            continue
        if words:
            check_segment(words, seg, base, env, ctx, piped, depth)


def reason(cmd, cwd, scratch=""):
    try:
        check(cmd, os.path.realpath(cwd), dict(os.environ), Ctx(cwd, scratch))
    except Deny as e:
        return str(e)
    return None


if __name__ == "__main__":
    r = reason(sys.stdin.read(), sys.argv[1] if len(sys.argv) > 1 else os.getcwd(),
               sys.argv[2] if len(sys.argv) > 2 else "")
    if r:
        print(r)
