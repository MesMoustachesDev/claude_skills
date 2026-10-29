#!/usr/bin/env python3
"""bash_write_targets.py <cwd> — lit une commande Bash sur stdin, imprime les fichiers qu'elle écrit.

Utilisé par hooks/pipeline-restrict-writes.sh : une écriture par Bash passe par la même zone que
Edit/Write. Ce qui est reconnu, chemin absolu par ligne :
  - redirections `> f`, `>> f`, `&> f` (heredoc `cat > f <<EOF` compris) ;
  - éditions en place `sed -i`, `perl -i` / `-pi` : les arguments qui sont des fichiers existants ;
  - `tee f…`, la destination de `cp` / `mv` / `install`, la source de `mv`, et `rm` (`git mv` / `git rm`
    compris).
Les `cd <dir>` de la commande déplacent la base des chemins relatifs. Ce n'est pas un parseur shell :
`python -c "open(…, 'w')"`, `dart format` ou un script qui écrit restent invisibles, et le gate
(test_freeze_check) reste le filet. Une commande illisible (guillemets non fermés) : redirections
seulement, par expression régulière.
"""
import glob
import os
import re
import shlex
import sys

OPS = {";", "&&", "||", "|", "&", "(", ")", "|&", ";;"}
REDIRS = {">", ">>", "&>", "&>>", ">|"}
IGNORED = ("/dev/",)


def strip_heredocs(cmd):
    """Retire le corps des heredocs : du texte libre (apostrophes) que shlex ne sait pas lire."""
    out, delim, dash = [], None, False
    for line in cmd.split("\n"):
        if delim is not None:
            if (line.lstrip("\t") if dash else line) == delim:
                delim = None
            continue
        out.append(line)
        m = re.search(r"<<(-?)\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2", line)
        if m:
            dash, delim = m.group(1) == "-", m.group(3)
    return "\n".join(out)


def segments(tokens):
    seg = []
    for t in tokens:
        if t in OPS or t == "\n":
            if seg:
                yield seg
            seg = []
        else:
            seg.append(t)
    if seg:
        yield seg


def resolve(base, p):
    p = os.path.expanduser(p)
    return os.path.normpath(p if os.path.isabs(p) else os.path.join(base, p))


def expand(tok, env):
    """$VAR et ${VAR} connus (assignés plus tôt dans la commande, ou HOME…) ; None si une variable reste
    inconnue (variable de boucle, $(…)) : le chemin n'est pas connu, on ne décide pas dessus."""
    out = re.sub(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?", lambda m: env.get(m.group(1), "\0"), tok)
    return None if "\0" in out or "$" in out else out


def paths(base, tok, env, existing=False):
    """Le ou les chemins d'un mot : variables développées, globs développés (`lib/*.dart`)."""
    tok = expand(tok, env)
    if tok is None:
        return []
    if any(c in tok for c in "*?["):
        return [os.path.normpath(p) for p in glob.glob(resolve(base, tok))]
    p = resolve(base, tok)
    return [p] if not existing or os.path.isfile(p) else []


def targets(cmd, cwd):
    body = strip_heredocs(cmd).replace("\\\n", " ")
    body = body.replace("\n", " ; ")          # une ligne = une commande (un `cd` seul sur sa ligne)
    try:
        lex = shlex.shlex(body, posix=True, punctuation_chars=";&|()<>")
        lex.whitespace_split = True
        lex.commenters = ""
        tokens = list(lex)
    except ValueError:
        return [resolve(cwd, m) for m in re.findall(r"(?:^|[^<0-9&])>>?\s*([^\s;&|<>'\"]+)", body)
                if "$" not in m and not m.startswith(IGNORED)]
    found, base = [], cwd
    env = {k: v for k, v in os.environ.items() if k in ("HOME", "TMPDIR", "USER")}
    for seg in segments(tokens):
        words, i = [], 0
        while i < len(seg):
            t = seg[i]
            if t in REDIRS or re.fullmatch(r"[0-9]+>>?", t):
                if i + 1 < len(seg) and not seg[i + 1].startswith("&"):
                    found += paths(base, seg[i + 1], env)
                i += 2
                continue
            if t in ("<", "<<", "<<<", "<<-"):
                i += 2
                continue
            words.append(t)
            i += 1
        if words and words[0] in ("export", "local", "readonly"):
            words = words[1:]
        while words and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", words[0]):   # VAR=valeur [cmd …]
            k, v = words[0].split("=", 1)
            v = expand(v, env)
            if v is not None:
                env[k] = v
            else:
                env.pop(k, None)
            words = words[1:]
        if not words:
            continue
        prog, args = os.path.basename(words[0]), words[1:]
        if prog == "git" and args[:1] in (["mv"], ["rm"]):
            prog, args = args[0], args[1:]
        if prog == "cd" and args:
            base = next(iter(paths(base, args[0], env)), base)
        elif prog in ("sed", "gsed", "perl") and any(re.fullmatch(r"-[a-zA-Z]*i.*|--in-place.*", a) for a in args):
            found += [p for a in args if not a.startswith("-") for p in paths(base, a, env, existing=True)]
        elif prog == "tee":
            found += [p for a in args if not a.startswith("-") for p in paths(base, a, env)]
        elif prog in ("cp", "mv", "install"):
            plain = [a for a in args if not a.startswith("-")]
            dest = paths(base, plain[-1], env) if len(plain) >= 2 else []
            if dest:
                srcs = [p for a in plain[:-1] for p in paths(base, a, env)]
                found += ([os.path.join(dest[0], os.path.basename(s)) for s in srcs]
                          if os.path.isdir(dest[0]) or plain[-1].endswith("/") else dest)
                if prog == "mv":
                    found += srcs                                       # la source disparaît
        elif prog == "rm":
            found += [p for a in args if not a.startswith("-") for p in paths(base, a, env)]
    return [f for f in dict.fromkeys(found) if not f.startswith(IGNORED)]


if __name__ == "__main__":
    for f in targets(sys.stdin.read(), sys.argv[1] if len(sys.argv) > 1 else os.getcwd()):
        print(f)
