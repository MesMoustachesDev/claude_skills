#!/usr/bin/env python3
"""kotlin_dedup.py — la roue réinventée par la responsabilité, pour Kotlin : version Android de
`dup_check.dart --candidates` (stacks/flutter). Le script ne juge pas ; il écrit, pour chaque déclaration
réutilisable du package (classe, interface, object, data class, enum, typealias, fonction top-level,
extension, fichier de fonctions top-level), les déclarations Kotlin du reste du repo qui LUI RESSEMBLENT,
avec leur signature et leur KDoc. L'agent feature-dedup lit le JSON et tranche.

  kotlin_dedup.py --root <racine du repo> --package <dossier du module> --out <dedup_candidates.json>
                  [--scope <fichier>] [--ignore-names a,b] [--ds-prefix com.x.design.,…]

--scope : périmètre du mode extend, « chemin » (fichier entier) ou « chemin:ligne », relatifs à --root ; vide ou
absent, tout le module est cible. Hors périmètre, le reste du module compte comme « existant ».
Score d'une paire = tokens de nom partagés pondérés IDF (un token présent partout ne vaut rien) + même rôle
(suffixe : UseCase, Mapper…) + même paquet Kotlin + même receveur ou supertype + mêmes types de paramètres +
types partagés dans les signatures. Même famille seulement (type ↔ type, fonction ↔ fonction, composable ↔ composable). Sans réseau ni
dépendance : un lexer qui blanchit commentaires, chaînes et annotations, puis des déclarations par regex au
niveau des accolades. Les fichiers générés (GAUNTLET_GENERATED_ERE, generated.exclude) et les tests sont exclus.
"""
import argparse
import json
import math
import os
import re
import subprocess
import sys

# Conventions et overrides : jamais des doublons (comme _skipNames de dup_check.dart).
SKIP_NAMES = {
    'toString', 'equals', 'hashCode', 'invoke', 'copy', 'main', 'onCreate', 'onDestroy', 'toEntity', 'toModel',
    'toDomain', 'toData', 'run', 'get', 'set', 'save', 'delete', 'update', 'create', 'of', 'from', 'parse',
    'empty', 'initial', 'Companion',
}
STOP_TOKENS = {
    'get', 'set', 'on', 'to', 'from', 'is', 'has', 'use', 'case', 'usecase', 'impl', 'entity', 'model', 'dao',
    'data', 'source', 'repository', 'remote', 'local', 'screen', 'view', 'ui', 'state', 'event', 'module', 'di',
    'the', 'a', 'an', 'ext', 'extension', 'extensions', 'mapper', 'item', 'list', 'with', 'by', 'for', 'of', 'in',
    'and', 'or', 'new', 'all', 'kt', 'default', 'content',
}
# Types de l'architecture, un jeu par feature : jamais des roues (ViewModel, état d'écran, module Hilt…).
# Les use cases, mappers et repositories restent candidats : c'est là que la roue se réinvente.
ARCH_SUFFIX = re.compile(
    r'(Impl|ViewModel|UiState|UiEvent|UiAction|Event|Action|Intent|TestTags|Keys|Route|Routes|Destination|'
    r'Screen|Module|Component|Dao|Database|Activity|Fragment|Application|Receiver|Preview|Previews)$')
# Types trop courants pour rapprocher deux déclarations.
COMMON_TYPES = {
    'String', 'Int', 'Long', 'Boolean', 'Double', 'Float', 'Short', 'Byte', 'Char', 'Unit', 'Any', 'Nothing',
    'List', 'MutableList', 'Map', 'MutableMap', 'Set', 'MutableSet', 'Collection', 'Iterable', 'Sequence',
    'Array', 'Pair', 'Triple', 'Flow', 'StateFlow', 'MutableStateFlow', 'SharedFlow', 'Result', 'Inject',
    'Modifier', 'Context', 'T', 'R', 'K', 'V', 'E', 'Composable', 'Throwable', 'Exception', 'Instant',
    'LocalDate', 'LocalDateTime', 'ZoneId', 'Duration', 'UUID', 'Job', 'CoroutineScope', 'Dispatchers',
}
MODIFIERS = (r'public|internal|private|protected|abstract|open|sealed|data|enum|annotation|inline|value|inner|'
             r'suspend|operator|infix|tailrec|external|expect|actual|const|override|lateinit|final')
DECL = re.compile(r'(?m)^[ \t]*((?:(?:' + MODIFIERS + r')\s+)*)(fun\s+interface|class|interface|object|typealias|fun|val|var)\b')
IDENT = re.compile(r'`?([A-Za-z_][A-Za-z0-9_]*)`?')
ROLE = re.compile(r'(UseCase|DataSource|[A-Z][a-z0-9]+)$')
TYPE_FAMILY = {'classe', 'interface', 'object', 'enum', 'typealias', 'fichier'}


# ---------------------------------------------------------------------------------------------------------------
# Lexer : blanchit commentaires et chaînes (lignes conservées), puis les annotations
# ---------------------------------------------------------------------------------------------------------------
def strip_comments_strings(src):
    out = list(src)
    n = len(src)

    def blank(a, b):
        for k in range(a, min(b, n)):
            if out[k] != '\n':
                out[k] = ' '

    def skip_string(i):
        """i sur l'ouverture d'une chaîne ; rend l'indice après sa fermeture (gabarits ${…} compris)."""
        triple = src.startswith('"""', i)
        j = i + (3 if triple else 1)
        while j < n:
            if triple and src.startswith('"""', j):
                j += 3
                while j < n and src[j] == '"':
                    j += 1
                return j
            c = src[j]
            if not triple and c == '\\':
                j += 2
                continue
            if not triple and c in '"\n':
                return j + 1
            if src.startswith('${', j):
                j = skip_code(j + 2, '}')
                continue
            j += 1
        return j

    def skip_code(j, closer):
        depth = 0
        while j < n:
            if src.startswith('//', j):
                j = src.find('\n', j)
                j = n if j < 0 else j
            elif src.startswith('/*', j):
                j = skip_block_comment(j)
            elif src[j] == '"':
                j = skip_string(j)
            elif src[j] == '{':
                depth += 1
                j += 1
            elif src[j] == closer and depth == 0:
                return j + 1
            elif src[j] == '}':
                depth -= 1
                j += 1
            else:
                j += 1
        return j

    def skip_block_comment(j):
        depth = 0
        while j < n:
            if src.startswith('/*', j):
                depth += 1
                j += 2
            elif src.startswith('*/', j):
                depth -= 1
                j += 2
                if depth == 0:
                    return j
            else:
                j += 1
        return j

    i = 0
    while i < n:
        if src.startswith('//', i):
            e = src.find('\n', i)
            e = n if e < 0 else e
            blank(i, e)
            i = e
        elif src.startswith('/*', i):
            e = skip_block_comment(i)
            blank(i, e)
            i = e
        elif src[i] == '"':
            e = skip_string(i)
            blank(i, e)
            i = e
        elif src[i] == "'":
            m = re.match(r"'(\\.[^']*|[^'\\])'", src[i:])
            e = i + (m.end() if m else 1)
            blank(i, e)
            i = e
        else:
            i += 1
    return ''.join(out)


def blank_annotations(code):
    """@Foo, @Foo(…), @field:Foo(…) → espaces ; rend aussi [(début, fin, nom)]."""
    out = list(code)
    spans = []
    for m in re.finditer(r'@([A-Za-z_][\w.]*:)?([A-Za-z_][\w.]*)', code):
        if any(a <= m.start() < b for a, b, _ in spans[-1:]):
            continue
        e = m.end()
        k = e
        while k < len(code) and code[k] in ' \t':
            k += 1
        if k < len(code) and code[k] == '(':
            e = match_close(code, k, '(', ')')
        spans.append((m.start(), e, m.group(2).split('.')[-1]))
        for p in range(m.start(), e):
            if out[p] != '\n':
                out[p] = ' '
    return ''.join(out), spans


def match_close(code, i, o, c):
    depth = 0
    for j in range(i, len(code)):
        if code[j] == o:
            depth += 1
        elif code[j] == c:
            depth -= 1
            if depth == 0:
                return j + 1
    return len(code)


def brace_depths(code):
    depths = [0] * (len(code) + 1)
    d = 0
    for i, ch in enumerate(code):
        depths[i] = d
        if ch == '{':
            d += 1
        elif ch == '}':
            d = max(0, d - 1)
    depths[len(code)] = d
    return depths


def header_end(code, i):
    """Fin de l'en-tête qui commence en i : `{` ou `=` hors parenthèses, ou fin de ligne quand rien ne continue."""
    depth = 0
    j = i
    while j < len(code) and j - i < 2000:
        c = code[j]
        if c in '([<' and not (c == '<' and code[j - 1:j] in ('=', ' ') and depth == 0 and code[j + 1:j + 2] == ' '):
            depth += 1
        elif c in ')]>' and depth > 0 and not (c == '>' and code[j - 1] == '-'):
            depth -= 1
        elif depth == 0 and c == '{':
            return j
        elif depth == 0 and c == '=' and code[j + 1:j + 2] != '=' and code[j - 1:j] not in '!<>=':
            return j
        elif depth == 0 and c == '\n':
            before = code[i:j].rstrip()
            after = code[j:].lstrip()
            if not before.endswith((':', ',', '.')) and not after.startswith((':', ',', '.', 'where ', '->')):
                return j
        j += 1
    return j


def split_top(s, sep=','):
    parts, depth, cur = [], 0, []
    for c in s:
        if c in '([<{':
            depth += 1
        elif c in ')]>}':
            depth -= 1
        if c == sep and depth == 0:
            parts.append(''.join(cur))
            cur = []
        else:
            cur.append(c)
    if ''.join(cur).strip():
        parts.append(''.join(cur))
    return parts


def first_parens(s, start=0):
    i = s.find('(', start)
    if i < 0:
        return None, start
    e = match_close(s, i, '(', ')')
    return s[i + 1:e - 1], e


def param_types(params):
    if params is None:
        return ''
    types = []
    for p in split_top(params):
        if ':' not in p:
            continue
        t = p.split(':', 1)[1].split('=')[0]
        types.append(re.sub(r'\s+', '', t))
    return ','.join(types)


def type_names(text):
    return {t for t in re.findall(r'\b([A-Z][A-Za-z0-9_]*)\b', text) if t not in COMMON_TYPES}


def supertypes_of(rest):
    """`(…) : A(), B<T> where …` → {A, B} ; rest = l'en-tête après le nom."""
    depth = 0
    for k, c in enumerate(rest):
        if c in '(<[':
            depth += 1
        elif c in ')>]':
            depth -= 1
        elif c == ':' and depth == 0:
            sup = re.split(r'\bwhere\b', rest[k + 1:])[0]
            names = set()
            for p in split_top(sup):
                m = re.match(r'\s*([\w.]+)', p)
                if m:
                    names.add(m.group(1).split('.')[-1])
            return names
    return set()


# ---------------------------------------------------------------------------------------------------------------
# Déclarations
# ---------------------------------------------------------------------------------------------------------------
class Decl:
    def __init__(self, **kw):
        self.__dict__.update(kw)

    @property
    def bare(self):
        return self.name.split('.')[-1]

    def json(self):
        d = {'kind': self.kind, 'name': self.name, 'file': self.file, 'line': self.line, 'package': self.pkg,
             'signature': self.signature, 'doc': self.doc}
        if self.on:
            d['on'] = self.on
        return d


def kdoc_before(src, code, start):
    """La KDoc qui précède la déclaration (seuls des blancs et des annotations entre les deux)."""
    k = src.rfind('*/', 0, start)
    if k < 0 or code[k + 2:start].strip():
        return ''
    b = src.rfind('/**', 0, k)
    if b < 0:
        return ''
    lines = [re.sub(r'^\s*\*\s?', '', l) for l in src[b + 3:k].splitlines()]
    text = []
    for l in lines:
        if l.strip().startswith('@'):
            break
        if not l.strip() and text:
            break
        if l.strip():
            text.append(l.strip())
    doc = ' '.join(text)
    return doc[:300]


def parse_file(path, rel, pkg):
    with open(path, encoding='utf-8', errors='replace') as f:
        src = f.read()
    c1 = strip_comments_strings(src)
    code, ann_spans = blank_annotations(c1)
    depths = brace_depths(code)
    m = re.search(r'(?m)^\s*package\s+([\w.]+)', code)
    kpkg = m.group(1) if m else ''
    decls = []
    funs = []  # fonctions top-level publiques, pour la pseudo-déclaration « fichier »
    for m in DECL.finditer(code):
        start = m.start(1) if m.group(1) else m.start(2)
        if depths[start] != 0:
            continue
        mods = m.group(1).split()
        kw = re.sub(r'\s+', ' ', m.group(2))
        line = code.count('\n', 0, start) + 1
        prev = len(code[:start].rstrip())
        anns = {name for a, b, name in ann_spans if prev <= a < start or (a < start and b > prev)}
        if 'Preview' in anns:
            continue
        end = header_end(code, m.end(2))
        header = code[m.end(2):end]
        sig = re.sub(r'\s+', ' ', (' '.join(mods) + ' ' + kw + header).strip())
        public = 'private' not in mods
        on = None
        if kw == 'typealias':
            nm = IDENT.match(header.lstrip())
            if not nm:
                continue
            name, kind = nm.group(1), 'typealias'
            sig = re.sub(r'\s+', ' ', (kw + code[m.end(2):code.find('\n', m.end(2))]).strip())
            rest = ''
        elif kw in ('class', 'interface', 'object', 'fun interface'):
            nm = IDENT.match(header.lstrip())
            if not nm:
                continue
            name = nm.group(1)
            kind = {'class': 'enum' if 'enum' in mods else 'classe', 'object': 'object'}.get(kw, 'interface')
            rest = header.lstrip()[nm.end():]
        else:  # fun, val, var : `[<T>] [Receveur.]nom`
            h = header.lstrip()
            if h.startswith('<'):
                h = h[match_close(h, 0, '<', '>'):].lstrip()
            stop = len(h)
            depth = 0
            for k, ch in enumerate(h):
                if ch == '<':
                    depth += 1
                elif ch == '>':
                    depth -= 1
                elif depth == 0 and ch in '(:=\n ' and k > 0 and (ch != ' ' or h[k - 1] not in '.,'):
                    if ch == ' ' and h[k + 1:k + 2] in ('.', '<'):
                        continue
                    stop = k
                    break
            path_ = h[:stop].strip()
            depth, cut = 0, -1
            for k, ch in enumerate(path_):
                if ch == '<':
                    depth += 1
                elif ch == '>':
                    depth -= 1
                elif ch == '.' and depth == 0:
                    cut = k
            if cut >= 0:
                on = path_[:cut].strip()
                nm = IDENT.match(path_[cut + 1:])
            else:
                nm = IDENT.match(path_)
            if not nm:
                continue
            if kw in ('val', 'var') and on is None:
                continue  # propriété top-level : constante ou CompositionLocal, pas une roue
            receiver = re.sub(r'[<?].*$', '', on).split('.')[-1] if on else None
            name = f'{receiver}.{nm.group(1)}' if receiver else nm.group(1)
            on = receiver
            kind = 'extension' if on else 'fonction'
            rest = h[stop:]
        params, after = first_parens(rest) if kind != 'typealias' else (None, 0)
        if kind in ('classe', 'enum', 'object', 'interface') and params is not None and rest.lstrip()[:1] not in ('(', 'c', '<', 'p', 'i'):
            params = None  # pas de constructeur primaire : la parenthèse appartient au supertype
        types = type_names(header)
        sups = supertypes_of(rest) if kind in ('classe', 'enum', 'object', 'interface') else set()
        invoke_ret = ''
        if kind in ('classe', 'object', 'interface') and end < len(code) and code[end] == '{':
            body_end = match_close(code, end, '{', '}')
            for fm in re.finditer(r'(?m)^[ \t]*((?:(?:' + MODIFIERS + r')\s+)*)fun\b', code[end:body_end]):
                fs = end + fm.start()
                if depths[fs] != depths[end] + 1 or 'private' in fm.group(1).split():
                    continue
                fh = code[end + fm.end():header_end(code, end + fm.end())]
                types |= type_names(fh)
                if re.match(r'\s*invoke\s*\(', fh):
                    _, a = first_parens(fh)
                    r = re.match(r'\s*:\s*(.+)', fh[a:], re.S)
                    invoke_ret = re.sub(r'\s+', '', r.group(1)) if r else 'Unit'
                    sig += ' { ' + re.sub(r'\s+', ' ', 'fun' + fh).strip() + ' }'
        types.discard(name.split('.')[-1])
        d = Decl(kind=kind, name=name, file=rel, line=line, pkg=pkg, kpkg=kpkg, public=public, on=on,
                 signature=sig[:400], doc=kdoc_before(src, c1, start), params=param_types(params),
                 types=types, sups=sups - COMMON_TYPES, invoke=invoke_ret,
                 composable='Composable' in anns, lines={line})
        decls.append(d)
        if kind in ('fonction', 'extension') and public:
            funs.append(d)
    stem = os.path.splitext(os.path.basename(rel))[0]
    if funs and not any(d.name == stem for d in decls):
        decls.append(Decl(kind='fichier', name=stem, file=rel, line=funs[0].line, pkg=pkg, kpkg=kpkg, public=True,
                          on=None, signature='; '.join(f.signature for f in funs)[:400],
                          doc=funs[0].doc, params='', types=set().union(*(f.types for f in funs)) - {stem},
                          sups=set(), invoke='', composable=False, lines={f.line for f in funs}))
    return decls


# ---------------------------------------------------------------------------------------------------------------
# Fichiers du repo
# ---------------------------------------------------------------------------------------------------------------
def kotlin_files(root):
    try:
        out = subprocess.run(['git', '-C', root, 'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', '*.kt'],
                             capture_output=True, check=True).stdout.decode()
        files = [f for f in out.split('\0') if f]
    except (subprocess.CalledProcessError, FileNotFoundError):
        files = []
        for d, dirs, names in os.walk(root):
            dirs[:] = [x for x in dirs if not x.startswith('.') and x != 'build']
            files += [os.path.relpath(os.path.join(d, n), root) for n in names if n.endswith('.kt')]
    gen = os.environ.get('GAUNTLET_GENERATED_ERE')
    gen_re = re.compile(gen) if gen else None
    keep = []
    for f in sorted(set(files)):
        parts = f.split('/')
        if any(p.startswith('.') or p == 'build' for p in parts[:-1]):
            continue
        if 'src' not in parts:
            continue
        sourceset = parts[parts.index('src') + 1] if parts.index('src') + 1 < len(parts) else ''
        if 'test' in sourceset.lower():
            continue  # src/test, src/androidTest, src/testFixtures
        if gen_re and gen_re.search(f):
            continue
        if os.path.isfile(os.path.join(root, f)):
            keep.append(f)
    return keep


MODULE_CACHE = {}


def module_of(root, rel):
    """Le module Gradle du fichier : le dossier parent le plus proche qui porte un build.gradle(.kts)."""
    d = os.path.dirname(rel)
    while d:
        if d not in MODULE_CACHE:
            MODULE_CACHE[d] = any(os.path.isfile(os.path.join(root, d, b)) for b in ('build.gradle.kts', 'build.gradle'))
        if MODULE_CACHE[d]:
            return d
        d = os.path.dirname(d)
    return rel.split('/')[0]


# ---------------------------------------------------------------------------------------------------------------
# Score
# ---------------------------------------------------------------------------------------------------------------
def name_tokens(name):
    bare = name.split('.')[-1]
    s = re.sub(r'([a-z0-9])([A-Z])', r'\1 \2', bare)
    s = re.sub(r'([A-Z]+)([A-Z][a-z])', r'\1 \2', s).lower()
    return {stem(t) for t in re.split(r'[^a-z0-9]+', s) if len(t) > 1 and t not in STOP_TOKENS}


def stem(t):
    for suf in ('ies', 'ing', 'ers', 'er', 'es', 's'):
        if len(t) > 4 and t.endswith(suf):
            return t[:-len(suf)] + ('y' if suf == 'ies' else '')
    return t


def family(d):
    """type ↔ type, fonction ↔ fonction, composable ↔ composable"""
    return 'type' if d.kind in TYPE_FAMILY else 'composable' if d.composable else 'callable'


def role(d):
    m = ROLE.search(d.bare)
    return m.group(1) if m and d.kind != 'fonction' and d.kind != 'extension' else None


def core(t):
    """Flow<List<Workout>>, List<Workout>?, Result<Workout> → Workout"""
    inner = re.findall(r'[A-Z]\w*', t)
    inner = [x for x in inner if x not in COMMON_TYPES]
    return inner[-1] if inner else t


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', required=True)
    ap.add_argument('--package', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--scope')
    ap.add_argument('--ignore-names', default='')
    ap.add_argument('--ds-prefix', default='')
    a = ap.parse_args()
    root = os.path.realpath(a.root)
    pkg_rel = os.path.relpath(os.path.realpath(a.package), root)
    ignore = {s.strip() for s in a.ignore_names.split(',') if s.strip()}
    ds_prefixes = [s.strip() for s in a.ds_prefix.split(',') if s.strip()]

    scope_files, scope_lines = set(), set()
    if a.scope and os.path.isfile(a.scope):
        for l in open(a.scope, encoding='utf-8').read().splitlines():
            if not l:
                continue
            f, _, n = l.rpartition(':')
            if f and n.isdigit():
                scope_lines.add((f, int(n)))
            else:
                scope_files.add(l)
    scope_all = not scope_files and not scope_lines

    def in_scope(d):
        return scope_all or d.file in scope_files or any((d.file, n) in scope_lines for n in d.lines)

    decls = []
    for rel in kotlin_files(root):
        decls += parse_file(os.path.join(root, rel), rel, module_of(root, rel))
    in_pkg = [d for d in decls if d.pkg == pkg_rel or d.file.startswith(pkg_rel + '/')]
    target = [d for d in in_pkg if in_scope(d)]
    tset = {id(d) for d in target}
    others = [d for d in decls if id(d) not in tset]

    def reusable(d):
        return d.public and not ARCH_SUFFIX.search(d.bare) and not (d.on and ARCH_SUFFIX.search(d.on))

    pool = [(o, name_tokens(o.name)) for o in others if reusable(o)]
    df = {}
    for _, toks in pool:
        for t in toks:
            df[t] = df.get(t, 0) + 1
    n = len(pool) + 1

    def w(t):
        return math.log(n / (df.get(t, 0) + 1))

    entries, pairs = [], 0
    for d in target:
        if not reusable(d) or d.bare in SKIP_NAMES or d.bare in ignore:
            continue
        toks = name_tokens(d.name)
        r = role(d)
        scored = []
        for o, otoks in pool:
            if family(d) != family(o) or (o.file == d.file and o.name == d.name):
                continue
            if d.kind == 'fichier' and o.file == d.file or o.kind == 'fichier' and o.file == d.file:
                continue
            s = sum(w(t) for t in toks & otoks)
            if r and r == role(o):
                s += 1.5
            if d.kpkg and d.kpkg == o.kpkg:
                s += 1
            if d.on and d.on == o.on:
                s += 2
            if d.sups & o.sups:
                s += 2
            if d.params and d.params == o.params:
                s += 1
            if d.invoke and o.invoke and core(d.invoke) == core(o.invoke):
                s += 2
            s += min(3, len(d.types & o.types))
            if s >= 3.0 and (toks & otoks or s >= 4.0):
                scored.append((o, s))
        if not scored:
            continue
        scored.sort(key=lambda x: (-x[1], x[0].file, x[0].line))
        top = scored[:3]
        pairs += len(top)
        entries.append({'target': d.json(),
                        'candidates': [dict(o.json(), score=round(s, 1)) for o, s in top]})

    def is_widget(d):
        return d.composable and d.public and d.kind == 'fonction' and d.bare[:1].isupper()

    widgets = [d for d in target if is_widget(d) and re.search(r'/(ui|presentation)/', d.file)]
    catalog = [o for o in others if is_widget(o) and any(o.kpkg.startswith(p.rstrip('.')) for p in ds_prefixes)]
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, 'w', encoding='utf-8') as f:
        json.dump({'package': pkg_rel, 'targets': len(entries), 'pairs': pairs, 'entries': entries,
                   'widgets': [x.json() for x in widgets], 'design_catalog': [x.json() for x in catalog]},
                  f, indent=2, ensure_ascii=False)
        f.write('\n')
    print(f'   {len(target)} déclaration(s) du module dans le périmètre, {len(others)} ailleurs ; '
          f'{len(entries)} avec candidat(s), {pairs} paire(s) à juger ; {len(widgets)} composable(s) à comparer '
          f'au design system ({len(catalog)} composants) → {a.out}')


if __name__ == '__main__':
    sys.exit(main())
