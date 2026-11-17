#!/usr/bin/env python3
"""fetch_redirect.py — fetch() côté serveur qui suit les redirections d'une URL non constante.

Usage : fetch_redirect.py <racine> <fichier relatif>...

Signale, en [WARN] fichier:ligne, chaque appel `fetch(url, options)` d'un fichier JS/TS serveur dont :
  - l'URL ne vient pas d'une constante (littéral sans interpolation, NOM_EN_MAJUSCULES, `const x = '…'`
    du même fichier, ou littéral dont l'origine `https://hôte/` est écrite et seul le chemin varie) ;
  - et les options ne disent pas `redirect: 'manual'` ou `redirect: 'error'` (absentes, sans clé redirect,
    `redirect: 'follow'`, ou une valeur qu'on ne peut pas lire).
Une redirection suivie mène l'appel où la réponse veut, hôte interne compris (SSRF), même si l'URL de départ
a été vérifiée. Heuristique : jamais bloquant, sort toujours 0.

Hors champ : tests, fichiers sous un dossier client (public, static, client, browser, frontend, www).
"""
import re
import sys
from pathlib import Path

EXTS = (".js", ".mjs", ".cjs", ".ts", ".mts", ".cts")
CLIENT_DIRS = {"public", "static", "client", "browser", "frontend", "www"}
TEST_RE = re.compile(r"(^|/)(__tests__|__mocks__|tests?|spec)/|\.(test|spec)\.[cm]?[jt]s$")
SAFE_REDIRECTS = {"manual", "error"}


def in_scope(rel):
    if not rel.endswith(EXTS) or rel.endswith(".d.ts"):
        return False
    parts = rel.split("/")
    if "node_modules" in parts or CLIENT_DIRS & set(parts[:-1]):
        return False
    return not TEST_RE.search(rel)


def blank_comments(src):
    """Remplace les commentaires par des espaces (lignes et chaînes gardées)."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c in "'\"`":
            j = skip_string(src, i)
            out.append(src[i:j]); i = j
        elif src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i)); i = j
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(re.sub(r"[^\n]", " ", src[i:j])); i = j
        else:
            out.append(c); i += 1
    return "".join(out)


def skip_string(src, i):
    """Index juste après la chaîne qui commence en i."""
    q, j, n = src[i], i + 1, len(src)
    while j < n:
        if src[j] == "\\":
            j += 2; continue
        if src[j] == q:
            return j + 1
        if q == "`" and src.startswith("${", j):
            j = skip_balanced(src, j + 1); continue
        if q != "`" and src[j] == "\n":
            return j
        j += 1
    return n


def skip_balanced(src, i):
    """src[i] est ( [ ou { : index juste après sa fermeture."""
    depth, j, n = 0, i, len(src)
    while j < n:
        c = src[j]
        if c in "'\"`":
            j = skip_string(src, j); continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                return j + 1
        j += 1
    return n


def split_args(inner):
    args, start, j, n = [], 0, 0, len(inner)
    while j < n:
        c = inner[j]
        if c in "'\"`":
            j = skip_string(inner, j); continue
        if c in "([{":
            j = skip_balanced(inner, j); continue
        if c == ",":
            args.append(inner[start:j].strip()); start = j + 1
        j += 1
    last = inner[start:].strip()
    if last:
        args.append(last)
    return args


def is_literal(expr):
    m = re.fullmatch(r"(['\"])(.*)\1", expr, re.S) or re.fullmatch(r"`([^`]*)`", expr, re.S)
    return bool(m) and "${" not in expr


def fixed_origin(expr):
    """`https://hôte/…${x}` ou 'https://hôte/' + x : l'hôte est écrit dans le code, seul le chemin varie."""
    return bool(re.match(r"""[`'"]https?://[^/`'"$\s]+/""", expr))


def constants(src):
    """Noms liés par `const x = <littéral>` dans le fichier."""
    names = set()
    for m in re.finditer(r"\bconst\s+([A-Za-z_$][\w$]*)\s*=\s*", src):
        j = m.end()
        if j < len(src) and src[j] in "'\"`":
            k = skip_string(src, j)
            if is_literal(src[j:k]):
                names.add(m.group(1))
    return names


def object_of(src, name):
    """Texte de l'objet littéral lié à <name> (`const|let|var name = {…}`), sinon None."""
    m = re.search(r"\b(?:const|let|var)\s+" + re.escape(name) + r"\s*=\s*\{", src)
    if not m:
        return None
    start = m.end() - 1
    return src[start:skip_balanced(src, start)]


def redirect_problem(src, args):
    """None si les options refusent les redirections, sinon pourquoi."""
    if len(args) < 2:
        return "pas d'options : redirect vaut 'follow' par défaut"
    opts = args[1]
    if re.fullmatch(r"[A-Za-z_$][\w$]*", opts):
        opts = object_of(src, opts) or ""
        if not opts:
            return f"options ({args[1]}) illisibles ici : redirect non vérifiable"
    if not opts.startswith("{"):
        return "options non littérales : redirect non vérifiable"
    m = re.search(r"\bredirect\s*:\s*(\S[^,}\n]*)", opts)
    if not m:
        return "pas de clé redirect : 'follow' par défaut"
    value = m.group(1).strip()
    lit = re.fullmatch(r"(['\"`])(\w+)\1", value)
    if not lit:
        return f"redirect: {value} n'est pas un littéral : non vérifiable"
    if lit.group(2) in SAFE_REDIRECTS:
        return None
    return f"redirect: '{lit.group(2)}'"


def scan(path, rel):
    try:
        raw = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []
    src = blank_comments(raw)
    consts = constants(src)
    found = []
    for m in re.finditer(r"(?<![\w$.])fetch\s*\(|\bglobalThis\.fetch\s*\(", src):
        before = src[max(0, m.start() - 12):m.start()]
        if re.search(r"\bfunction\s*$", before):
            continue
        open_at = m.end() - 1
        close_at = skip_balanced(src, open_at)
        after = src[close_at:close_at + 40].lstrip()
        if after.startswith("{") or after.startswith(":"):
            continue  # définition de méthode fetch(…) { … }
        args = split_args(src[open_at + 1:close_at - 1])
        if not args:
            continue
        url = args[0]
        if is_literal(url) or fixed_origin(url) or re.fullmatch(r"[A-Z][A-Z0-9_]*", url) or url in consts:
            continue
        why = redirect_problem(src, args)
        if why:
            line = src.count("\n", 0, m.start()) + 1
            shown = url if len(url) <= 40 else url[:37] + "…"
            found.append(f"{rel}:{line} — fetch({shown}) suit les redirections ({why})")
    return found


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    root = Path(argv[1])
    hits = []
    for rel in argv[2:]:
        rel = rel.strip()
        if rel and in_scope(rel) and (root / rel).is_file():
            hits += scan(root / rel, rel)
    for h in hits:
        print(f"[WARN] {h}")
    if hits:
        print("       URL non constante : une redirection suivie peut mener vers un hôte interne (SSRF). "
              "redirect: 'manual', puis revalider chaque Location (protocole, hôte exact) avant de la suivre.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
