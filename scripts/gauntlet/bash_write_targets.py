#!/usr/bin/env python3
"""bash_write_targets.py <cwd> — lit une commande Bash sur stdin, imprime les fichiers qu'elle écrit.

Utilisé par hooks/pipeline-restrict-writes.sh : une écriture par Bash passe par la même zone que
Edit/Write. Ce qui est reconnu, chemin absolu par ligne :
  - redirections `> f`, `>> f`, `&> f` (heredoc `cat > f <<EOF` compris) ;
  - éditions en place `sed -i`, `perl -i` / `-pi` : les arguments qui sont des fichiers existants ;
  - `tee f…`, la destination de `cp` / `mv` / `install` / `rsync`, la source de `mv`, et `rm` (`git mv` /
    `git rm` compris) ;
  - `dd of=f` ;
  - les fichiers d'un patch appliqué par `git apply` ou `patch` (fichier, `< f`, heredoc ou `<<<`) ;
  - les fichiers rétablis par `git checkout [<rev>] -- f…` et `git restore f…`.
Les `cd <dir>` de la commande déplacent la base des chemins relatifs. Ce n'est pas un parseur shell :
`python -c "open(…, 'w')"`, `dart format` ou un script qui écrit restent invisibles ici. Les interpréteurs
inline et les scripts écrits pendant la session (`dart run /tmp/x.dart` compris) sont refusés aux
sous-agents par hooks/no-interpreter.sh (ADR 0017) ; le gate (test_freeze_check) reste le filet. Une
commande illisible (guillemets non fermés) : redirections seulement, par expression régulière.
"""
import glob
import os
import re
import shlex
import subprocess
import sys

OPS = {";", "&&", "||", "|", "&", "(", ")", "|&", ";;"}
REDIRS = {">", ">>", "&>", "&>>", ">|"}
IGNORED = ("/dev/",)


def strip_heredocs(cmd, bodies=None):
    """Retire le corps des heredocs : du texte libre (apostrophes) que shlex ne sait pas lire. `bodies`
    (liste) reçoit le corps de chacun, dans l'ordre des `<<` de la commande."""
    out, delim, dash, body = [], None, False, []
    for line in cmd.split("\n"):
        if delim is not None:
            if (line.lstrip("\t") if dash else line) == delim:
                delim = None
                if bodies is not None:
                    bodies.append("\n".join(body))
            else:
                body.append(line)
            continue
        out.append(line)
        m = re.search(r"<<(-?)\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2", line)
        if m:
            dash, delim, body = m.group(1) == "-", m.group(3), []
    return "\n".join(out)


def patch_paths(text, strip):
    """Les chemins d'un patch unifié (`--- a/f`, `+++ b/f`), `strip` composants retirés (`-pN`)."""
    found = []
    for line in text.split("\n"):
        if line.startswith(("+++ ", "--- ")):
            p = line[4:].split("\t")[0].strip().strip('"')
            if p and p != "/dev/null":
                parts = p.split("/")
                found.append("/".join(parts[strip:]) if len(parts) > strip else parts[-1])
        elif line.startswith(("rename to ", "copy to ")):
            found.append(line.split(" ", 2)[2].strip())
    return list(dict.fromkeys(found))


def read_file(p):
    try:
        with open(p, errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def git_top(base):
    try:
        r = subprocess.run(["git", "-C", base, "rev-parse", "--show-toplevel"], capture_output=True, text=True,
                           timeout=10)
        return r.stdout.strip() if r.returncode == 0 and r.stdout.strip() else base
    except (OSError, subprocess.TimeoutExpired):
        return base


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
    bodies = []
    body = strip_heredocs(cmd, bodies).replace("\\\n", " ")
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
    hd = 0                                      # rang du prochain heredoc
    for seg in segments(tokens):
        words, i, stdin = [], 0, None           # stdin : le texte lu sur l'entrée standard, s'il est connu
        while i < len(seg):
            t = seg[i]
            if t in REDIRS or re.fullmatch(r"[0-9]+>>?", t):
                if i + 1 < len(seg) and not seg[i + 1].startswith("&"):
                    found += paths(base, seg[i + 1], env)
                i += 2
                continue
            if t in ("<<", "<<-"):
                stdin = bodies[hd] if hd < len(bodies) else ""
                hd += 1
                i += 2
                continue
            if t == "<<<":
                stdin = seg[i + 1] if i + 1 < len(seg) else ""
                i += 2
                continue
            if t == "<":
                src = paths(base, seg[i + 1], env) if i + 1 < len(seg) else []
                stdin = read_file(src[0]) if src else ""
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
        if prog == "git":
            while args and args[0] in ("-C", "-c"):         # git -C <dir> … : la base change
                if args[0] == "-C" and len(args) > 1:
                    base = next(iter(paths(base, args[1], env)), base)
                args = args[2:]
        if prog == "git" and args[:1] in (["mv"], ["rm"], ["apply"], ["checkout"], ["restore"]):
            prog, args = "git-" + args[0] if args[0] in ("apply", "checkout", "restore") else args[0], args[1:]
        if prog == "cd" and args:
            base = next(iter(paths(base, args[0], env)), base)
        elif prog in ("sed", "gsed", "perl") and any(re.fullmatch(r"-[a-zA-Z]*i.*|--in-place.*", a) for a in args):
            found += [p for a in args if not a.startswith("-") for p in paths(base, a, env, existing=True)]
        elif prog == "tee":
            found += [p for a in args if not a.startswith("-") for p in paths(base, a, env)]
        elif prog in ("cp", "mv", "install"):
            plain, k = [], 0
            while k < len(args):
                if prog == "install" and args[k] in ("-m", "-o", "-g", "-f", "-S"):   # install -m 644 a b
                    k += 2
                    continue
                if not args[k].startswith("-"):
                    plain.append(args[k])
                k += 1
            dest = paths(base, plain[-1], env) if len(plain) >= 2 else []
            if dest:
                srcs = [p for a in plain[:-1] for p in paths(base, a, env)]
                found += ([os.path.join(dest[0], os.path.basename(s)) for s in srcs]
                          if os.path.isdir(dest[0]) or plain[-1].endswith("/") else dest)
                if prog == "mv":
                    found += srcs                                       # la source disparaît
        elif prog == "rm":
            found += [p for a in args if not a.startswith("-") for p in paths(base, a, env)]
        elif prog == "dd":
            found += [p for a in args if a.startswith("of=") for p in paths(base, a[3:], env)]
        elif prog == "rsync":
            plain, k = [], 0
            while k < len(args):
                if args[k] in ("-e", "--rsh", "--exclude", "--include", "--filter", "-f", "--files-from"):
                    k += 2
                    continue
                if not args[k].startswith("-"):
                    plain.append(args[k])
                k += 1
            if len(plain) >= 2 and not re.match(r"^[^/]*:", plain[-1]):       # host:chemin : distant
                dest = paths(base, plain[-1], env)
                if dest:
                    srcs = [a for a in plain[:-1] if not re.match(r"^[^/]*:", a)]
                    found += ([dest[0] if s.endswith("/") else os.path.join(dest[0], os.path.basename(s.rstrip("/")))
                               for s in srcs]
                              if os.path.isdir(dest[0]) or plain[-1].endswith("/") else dest)
        elif prog in ("git-apply", "patch"):
            # git apply [-pN] <patch>… | git apply < f | git apply <<EOF ; patch -pN < f | patch -i f | patch <f>
            strip, files, k, patch_file = (1 if prog == "git-apply" else 0), [], 0, None
            check_only = False
            while k < len(args):
                a = args[k]
                m = re.fullmatch(r"-p([0-9]+)|--strip=([0-9]+)", a)
                if m:
                    strip = int(m.group(1) or m.group(2))
                elif a in ("-p", "--strip") and k + 1 < len(args):
                    strip, k = int(args[k + 1]) if args[k + 1].isdigit() else strip, k + 1
                elif a in ("-i", "--input") and k + 1 < len(args):
                    patch_file, k = args[k + 1], k + 1
                elif a.startswith("--input="):
                    patch_file = a.split("=", 1)[1]
                elif a in ("--check", "--stat", "--numstat", "--summary", "--dry-run", "--cached"):
                    check_only = True
                elif a in ("-o", "--output", "-d", "--directory", "-r", "--reject-file", "-B", "-z", "-D",
                           "-F", "--fuzz", "-V"):
                    k += 1
                elif not a.startswith("-"):
                    files.append(a)
                k += 1
            if check_only:
                continue
            if prog == "patch" and files:                       # patch <fichier> [<patch>] : la cible est nommée
                found += paths(base, files[0], env)
                continue
            srcs = files if prog == "git-apply" else [patch_file] if patch_file else []
            texts = [read_file(p) for f in srcs for p in paths(base, f, env)] or [stdin or ""]
            root = git_top(base) if prog == "git-apply" else base   # git apply : chemins depuis la racine
            for text in texts:
                found += [resolve(root, p) for p in patch_paths(text, strip)]
        elif prog == "git-checkout":
            if "--" in args:
                found += [p for a in args[args.index("--") + 1:] for p in paths(base, a, env)]
            else:
                plain = [a for a in args if not a.startswith("-")]
                cand = plain[1:] if len(plain) >= 2 else plain                    # <rev> <f>… ou <f>
                found += [p for a in cand for p in paths(base, a, env) if os.path.exists(p)]
        elif prog == "git-restore":
            plain, k, worktree, staged = [], 0, False, False
            while k < len(args):
                a = args[k]
                if a in ("-s", "--source"):
                    k += 1
                elif a in ("-S", "--staged"):
                    staged = True
                elif a in ("-W", "--worktree"):
                    worktree = True
                elif a != "--" and not a.startswith("-"):
                    plain.append(a)
                k += 1
            if worktree or not staged:                          # --staged seul : l'index, pas les fichiers
                found += [p for a in plain for p in paths(base, a, env)]
    return [f for f in dict.fromkeys(found) if not f.startswith(IGNORED)]


if __name__ == "__main__":
    for f in targets(sys.stdin.read(), sys.argv[1] if len(sys.argv) > 1 else os.getcwd()):
        print(f)
