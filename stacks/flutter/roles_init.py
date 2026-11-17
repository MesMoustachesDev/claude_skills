#!/usr/bin/env python3
"""roles_init.py — `/feature init roles` (ADR 0016) : le modèle propose, ce script décide.

Le modèle lit roles_todo.json (gauntlet.sh roles_todo : les déclarations sans rôle des packages partagés et du
design system) et écrit une proposition :

  {"roles": [{"mot": "état-vide", "description": "un bloc affiché quand il n'y a rien à montrer",
              "declarations": ["design/lib/empty.dart:1", "..."]}]}

Ce script la décode strictement — clés connues, mots courts en minuscules, chaque déclaration de la liste
attribuée une fois et une seule, aucune inconnue — et la refuse sinon. Il n'exécute rien de ce qu'elle dit.

  roles_init.py check --todo <roles_todo.json> --proposal <p.json> --vocab <.claude/roles.md> --root <features_root>
      à blanc : ce qui changerait (vocabulaire, lignes insérées par fichier). Exit 1 si la proposition est refusée.
  roles_init.py apply  (mêmes options)
      écrit le vocabulaire et insère `/// rôle: <mot>` à la ligne prévue, en partant du bas de chaque fichier.
"""
import argparse
import json
import os
import re
import sys
from collections import defaultdict

WORD = re.compile(r"^[a-zà-öø-ÿ0-9]+(-[a-zà-öø-ÿ0-9]+)*$")
VOCAB_LINE = re.compile(r"^\s*[-*]\s*`([^`]+)`")


def refuse(errors):
    print("REFUSÉ — la proposition ne passe pas :")
    for e in errors[:40]:
        print(f"  ✗ {e}")
    if len(errors) > 40:
        print(f"  … et {len(errors) - 40} autres")
    sys.exit(1)


def read_vocab(path):
    if not os.path.exists(path):
        return {}
    out = {}
    for line in open(path, encoding="utf-8"):
        m = VOCAB_LINE.match(line)
        if m:
            out[m.group(1).lower()] = line.strip()
    return out


def validate(todo, proposal, vocab):
    errors = []
    if not isinstance(proposal, dict) or set(proposal) != {"roles"} or not isinstance(proposal["roles"], list):
        refuse(['attendu exactement {"roles": [...]}'])
    decls = {d["id"]: d for d in todo["declarations"]}
    seen_words, assigned = set(), {}
    for i, r in enumerate(proposal["roles"]):
        where = f"roles[{i}]"
        if not isinstance(r, dict) or set(r) != {"mot", "description", "declarations"}:
            errors.append(f"{where} : clés attendues mot, description, declarations")
            continue
        mot, desc, ids = r["mot"], r["description"], r["declarations"]
        if not isinstance(mot, str) or not WORD.match(mot) or not 2 <= len(mot) <= 30:
            errors.append(f"{where} : mot « {mot} » invalide (minuscules, chiffres, tirets, 2 à 30 caractères)")
            continue
        if mot in seen_words:
            errors.append(f"{where} : « {mot} » proposé deux fois")
        seen_words.add(mot)
        if mot not in vocab and (not isinstance(desc, str) or not desc.strip() or len(desc) > 140 or "\n" in desc):
            errors.append(f"{where} : « {mot} » est nouveau, il lui faut une description d'une ligne (≤ 140 caractères)")
        if not isinstance(ids, list) or not ids or not all(isinstance(x, str) for x in ids):
            errors.append(f"{where} : declarations doit être une liste non vide d'identifiants fichier:ligne")
            continue
        for x in ids:
            if x not in decls:
                errors.append(f"{where} : {x} n'est pas dans roles_todo.json")
            elif x in assigned:
                errors.append(f"{x} reçoit deux rôles : {assigned[x]} et {mot}")
            else:
                assigned[x] = mot
    for x in decls:
        if x not in assigned:
            errors.append(f"{x} ({decls[x]['name']}) n'a pas de rôle")
    if errors:
        refuse(errors)
    return assigned, {r["mot"]: r["description"].strip() for r in proposal["roles"] if r["mot"] not in vocab}


def plan(todo, assigned, root):
    """Par fichier : (ligne d'insertion, texte) — l'indentation est celle de la ligne visée."""
    by_file = defaultdict(list)
    errors = []
    for d in todo["declarations"]:
        path = os.path.join(root, d["file"])
        if not os.path.exists(path):
            errors.append(f"{d['file']} introuvable sous {root}")
            continue
        lines = open(path, encoding="utf-8").read().split("\n")
        at = d["role_line"]
        if not 1 <= at <= len(lines):
            errors.append(f"{d['id']} : ligne {at} hors du fichier (le code a bougé depuis roles_todo.json ?)")
            continue
        if d["name"].split(".")[-1] not in "\n".join(lines[at - 1:at + 4]):
            errors.append(f"{d['id']} : {d['name']} n'est plus à la ligne {at} (relance gauntlet.sh roles_todo)")
            continue
        indent = re.match(r"\s*", lines[at - 1]).group(0)
        by_file[d["file"]].append((at, f"{indent}/// rôle: {assigned[d['id']]}", d["name"]))
    if errors:
        refuse(errors)
    return by_file


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["check", "apply"])
    ap.add_argument("--todo", required=True)
    ap.add_argument("--proposal", required=True)
    ap.add_argument("--vocab", required=True)
    ap.add_argument("--root", required=True)
    a = ap.parse_args()
    todo = json.load(open(a.todo, encoding="utf-8"))
    try:
        proposal = json.load(open(a.proposal, encoding="utf-8"))
    except json.JSONDecodeError as e:
        refuse([f"JSON illisible : {e}"])
    vocab = read_vocab(a.vocab)
    assigned, new_words = validate(todo, proposal, vocab)
    by_file = plan(todo, assigned, a.root)

    counts = defaultdict(int)
    for m in assigned.values():
        counts[m] += 1
    print(f"{len(assigned)} déclaration(s), {len(counts)} rôle(s) dont {len(new_words)} nouveau(x), {len(by_file)} fichier(s)")
    print("\nVocabulaire :")
    for m in sorted(counts):
        tag = "nouveau" if m in new_words else "existant"
        print(f"  {m:<24} {counts[m]:>3} décl.  ({tag}){' — ' + new_words[m] if m in new_words else ''}")
    print("\nInsertions :")
    for f in sorted(by_file):
        for at, text, name in sorted(by_file[f]):
            print(f"  {f}:{at}  {text.strip()}   ({name})")

    if a.cmd == "check":
        print("\nÀ blanc : rien n'a été écrit.")
        return
    for f, items in by_file.items():
        path = os.path.join(a.root, f)
        lines = open(path, encoding="utf-8").read().split("\n")
        for at, text, _ in sorted(items, reverse=True):
            lines.insert(at - 1, text)
        open(path, "w", encoding="utf-8").write("\n".join(lines))
    if new_words:
        os.makedirs(os.path.dirname(a.vocab) or ".", exist_ok=True)
        head = "" if os.path.exists(a.vocab) else (
            "# Rôles des déclarations\n\nVocabulaire fermé (ADR 0016 du pipeline) : chaque widget, fonction ou extension "
            "réutilisable porte `/// rôle: <mot>` dans sa doc, le mot pris ici. Un mot dit ce que la déclaration rend "
            "ou calcule, pas où elle vit.\n\n")
        with open(a.vocab, "a", encoding="utf-8") as out:
            out.write(head + "".join(f"- `{m}` : {new_words[m]}\n" for m in sorted(new_words)))
    print(f"\nÉcrit : {sum(len(v) for v in by_file.values())} ligne(s) dans {len(by_file)} fichier(s)"
          f"{', ' + str(len(new_words)) + ' mot(s) ajouté(s) à ' + a.vocab if new_words else ''}.")


if __name__ == "__main__":
    main()
