#!/usr/bin/env python3
"""format_only.py <ancien> <nouveau> — lignes de <nouveau> qui ne changent que par le format.

Compare les deux versions d'un fichier Dart token par token : espaces et retours à la ligne ignorés,
virgule finale avant `)`, `]` ou `}` ignorée (dart format l'ajoute ou la retire en style « tall »).
Imprime le numéro (1-based) de chaque ligne de <nouveau> dont tous les tokens existent à l'identique
dans <ancien>, au même rang : ligne recoupée, recollée, réindentée, ou vide. Une ligne qui porte un
seul token ajouté ou modifié n'est pas imprimée. Un fichier illisible n'imprime rien.
"""
import difflib
import re
import sys

TOKEN = re.compile(r"""
    '''.*?''' | \"\"\".*?\"\"\"          # chaînes multilignes
  | r?'(?:\\.|[^'\\\n])*' | r?"(?:\\.|[^"\\\n])*"
  | //[^\n]*                            # commentaire de ligne : un token, le texte compte
  | /\*.*?\*/
  | [A-Za-z_$][A-Za-z0-9_$]*
  | \d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?
  | \S
""", re.S | re.X)
CLOSERS = {")", "]", "}"}


def tokens(text):
    """[(token, ligne)] sans les virgules finales ; ligne = 1-based, celle où le token commence."""
    out, line, pos = [], 1, 0
    for m in TOKEN.finditer(text):
        line += text.count("\n", pos, m.start())
        pos = m.start()
        out.append((m.group(), line))
    return [t for i, t in enumerate(out)
            if not (t[0] == "," and i + 1 < len(out) and out[i + 1][0] in CLOSERS)]


def main(old_path, new_path):
    try:
        with open(old_path, encoding="utf-8") as f:
            old = tokens(f.read())
        with open(new_path, encoding="utf-8") as f:
            new_text = f.read()
    except (OSError, UnicodeDecodeError):
        return
    new = tokens(new_text)
    changed = set()
    sm = difflib.SequenceMatcher(None, [t for t, _ in old], [t for t, _ in new], autojunk=False)
    for op, _, _, j1, j2 in sm.get_opcodes():
        if op != "equal":
            changed.update(line for _, line in new[j1:j2])
    # Un token multiligne (chaîne, commentaire bloc) modifié marque toutes ses lignes.
    for tok, line in new:
        if line in changed and "\n" in tok:
            changed.update(range(line, line + tok.count("\n") + 1))
    total = new_text.count("\n") + (0 if new_text.endswith("\n") else 1)
    for n in range(1, total + 1):
        if n not in changed:
            print(n)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    main(sys.argv[1], sys.argv[2])
