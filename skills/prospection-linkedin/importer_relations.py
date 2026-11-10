#!/usr/bin/env python3
"""Export LinkedIn (Connections.csv) → fiches « À contacter / Réseau » à créer dans Leads CTO.

Usage : importer_relations.py Connections.csv existants.json [--sortie fiches.json]
existants.json = {"urls": [...], "noms": [...]} exporté par la session depuis Leads CTO.
Le script n'écrit que le fichier de sortie : c'est la session qui crée les fiches, après le oui de Thibault.
Personne n'est classé « collègue » : la colonne Company est l'entreprise actuelle, elle ne dit pas qui a
travaillé avec Thibault. C'est lui qui le dit, chaque matin, en choisissant qui contacter.
"""
import argparse
import csv
import io
import json
import re
import sys
from collections import Counter
from pathlib import Path
from urllib.parse import urlparse

from local_config import normaliser

DECIDEURS = ["cto", "cpo", "vp eng", "vp engineering", "head of", "lead", "fondateur", "fondatrice", "founder",
             "co-founder", "cofounder", "cofondateur", "cofondatrice", "co-fondateur", "co-fondatrice",
             "directeur technique", "directrice technique", "engineering manager"]
EXCLUS = ["recruteur", "recruteuse", "recruiter", "recruiting", "talent", "rh", "hr", "sales", "commercial",
          "commerciale", "freelance", "independant", "independante"]


def _contient(texte: str, mots: list[str]) -> bool:
    return any(re.search(rf"(?<![\w-]){re.escape(m)}(?![\w-])", texte) for m in mots)


def canoniser_url(url: str) -> str:
    """https://linkedin.com/in/<slug en minuscules>, ou "" si ce n'est pas un profil."""
    url = url.strip()
    if url and not re.match(r"^https?://", url, re.IGNORECASE):
        url = "https://" + url
    p = urlparse(url)
    hote = p.netloc.lower()
    if hote != "linkedin.com" and not hote.endswith(".linkedin.com"):
        return ""
    m = re.match(r"^/in/([^/]+)", p.path)
    return f"https://linkedin.com/in/{m.group(1).lower()}" if m else ""


def classer(poste: str) -> str | None:
    p = normaliser(poste)
    if _contient(p, EXCLUS):
        return None
    return "décideur" if _contient(p, DECIDEURS) else None


def lire_connections(path: Path) -> list[dict]:
    texte = path.read_text(encoding="utf-8-sig")
    m = re.search(r"^First Name,", texte, re.MULTILINE)
    if m is None:
        raise ValueError(f"{path} : pas de ligne d'en-tête « First Name »")

    def champ(r, cle):
        return (r.get(cle) or "").strip()

    return [{"prenom": champ(r, "First Name"), "nom": champ(r, "Last Name"), "url": champ(r, "URL"),
             "entreprise": champ(r, "Company"), "poste": champ(r, "Position"),
             "connecte_le": champ(r, "Connected On")}
            for r in csv.DictReader(io.StringIO(texte[m.start():]))]


def fiches(relations, urls_existantes: set[str], noms_existants: set[str]) -> list[dict]:
    urls = {canoniser_url(u) for u in urls_existantes} - {""}
    noms = {normaliser(n) for n in noms_existants}
    resultat = []
    for r in relations:
        url = canoniser_url(r["url"])
        nom = f"{r['prenom']} {r['nom']}".strip()
        categorie = classer(r["poste"])
        if not url or not categorie or url in urls or normaliser(nom) in noms:
            continue
        notes = f"relation LinkedIn, {r['poste']}" + (f" chez {r['entreprise']}" if r["entreprise"] else "")
        resultat.append({"Name": nom, "LinkedIn URL": url, "Entreprise": r["entreprise"], "Rôle": r["poste"],
                         "Statut": "À contacter", "Source": "Réseau", "Notes": notes, "categorie": categorie})
        urls.add(url)
    return resultat


def main() -> int:
    a = argparse.ArgumentParser()
    a.add_argument("connections", type=Path)
    a.add_argument("existants", type=Path)
    a.add_argument("--sortie", type=Path, default=Path("fiches.json"))
    args = a.parse_args()
    existants = json.loads(args.existants.read_text(encoding="utf-8"))
    relations = lire_connections(args.connections)
    resultat = fiches(relations, set(existants.get("urls", [])), set(existants.get("noms", [])))
    args.sortie.write_text(json.dumps(resultat, ensure_ascii=False, indent=2), encoding="utf-8")
    compte = Counter(f["categorie"] for f in resultat)
    print(f"{len(relations)} relations lues, {len(resultat)} fiches à créer → {args.sortie}")
    for cat in ("décideur",):
        print(f"{cat} : {compte[cat]}")
        for f in [f for f in resultat if f["categorie"] == cat][:10]:
            print(f"  - {f['Name']} | {f['Rôle']} | {f['Entreprise']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
