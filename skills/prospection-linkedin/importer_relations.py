#!/usr/bin/env python3
"""Export LinkedIn (Connections.csv) → fiches « À contacter / Réseau » à créer dans Leads CTO.

Usage : importer_relations.py Connections.csv existants.json [--sortie fiches.json] [--boites prospection.md]
existants.json = {"urls": [...], "noms": [...]} exporté par la session depuis Leads CTO.
Le script n'écrit que le fichier de sortie : c'est la session qui crée les fiches, après le oui de Thibault.
"""
import argparse
import csv
import json
import re
import sys
from collections import Counter
from pathlib import Path
from urllib.parse import urlparse

from local_config import PROSPECTION, est_ancienne_boite, lire_anciennes_boites, normaliser

DECIDEURS = ["cto", "cpo", "vp eng", "vp engineering", "head of", "lead", "fondateur", "fondatrice", "founder",
             "co-founder", "cofondateur", "cofondatrice", "directeur technique", "directrice technique",
             "engineering manager"]
EXCLUS = ["recruteur", "recruteuse", "recruiter", "recruiting", "talent", "rh", "hr", "sales", "commercial",
          "commerciale", "freelance", "independant", "independante"]


def _contient(texte: str, mots: list[str]) -> bool:
    return any(re.search(rf"(?<![\w-]){re.escape(m)}(?![\w-])", texte) for m in mots)


def canoniser_url(url: str) -> str:
    """https://linkedin.com/in/<slug en minuscules>, ou "" si ce n'est pas un profil."""
    p = urlparse(url.strip())
    if not p.netloc.endswith("linkedin.com"):
        return ""
    m = re.match(r"^/in/([^/]+)", p.path)
    return f"https://linkedin.com/in/{m.group(1).lower()}" if m else ""


def classer(poste: str, entreprise: str, boites) -> str | None:
    if est_ancienne_boite(entreprise, boites):
        return "collègue"
    p = normaliser(poste)
    if _contient(p, EXCLUS):
        return None
    return "décideur" if _contient(p, DECIDEURS) else None


def lire_connections(path: Path) -> list[dict]:
    lignes = path.read_text(encoding="utf-8-sig").splitlines()
    debut = next((i for i, l in enumerate(lignes) if l.startswith("First Name")), None)
    if debut is None:
        raise ValueError(f"{path} : pas de ligne d'en-tête « First Name »")
    return [{"prenom": r["First Name"].strip(), "nom": r["Last Name"].strip(), "url": r["URL"].strip(),
             "entreprise": (r["Company"] or "").strip(), "poste": (r["Position"] or "").strip(),
             "connecte_le": (r["Connected On"] or "").strip()}
            for r in csv.DictReader(lignes[debut:])]


def fiches(relations, boites, urls_existantes: set[str], noms_existants: set[str]) -> list[dict]:
    urls = {canoniser_url(u) for u in urls_existantes} - {""}
    noms = {normaliser(n) for n in noms_existants}
    resultat = []
    for r in relations:
        url = canoniser_url(r["url"])
        nom = f"{r['prenom']} {r['nom']}".strip()
        categorie = classer(r["poste"], r["entreprise"], boites)
        if not url or not categorie or url in urls or normaliser(nom) in noms:
            continue
        if categorie == "collègue":
            b = est_ancienne_boite(r["entreprise"], boites)
            notes = f"collègue chez {b.nom}" + (f" ({b.annees})" if b.annees else "")
        else:
            notes = f"relation LinkedIn, {r['poste']} chez {r['entreprise']}"
        resultat.append({"Name": nom, "LinkedIn URL": url, "Entreprise": r["entreprise"], "Rôle": r["poste"],
                         "Statut": "À contacter", "Source": "Réseau", "Notes": notes, "categorie": categorie})
        urls.add(url)
    return resultat


def main() -> int:
    a = argparse.ArgumentParser()
    a.add_argument("connections", type=Path)
    a.add_argument("existants", type=Path)
    a.add_argument("--sortie", type=Path, default=Path("fiches.json"))
    a.add_argument("--boites", type=Path, default=PROSPECTION)
    args = a.parse_args()
    boites = lire_anciennes_boites(args.boites)
    existants = json.loads(args.existants.read_text(encoding="utf-8"))
    relations = lire_connections(args.connections)
    resultat = fiches(relations, boites, set(existants.get("urls", [])), set(existants.get("noms", [])))
    args.sortie.write_text(json.dumps(resultat, ensure_ascii=False, indent=2), encoding="utf-8")
    compte = Counter(f["categorie"] for f in resultat)
    print(f"{len(relations)} relations lues, {len(resultat)} fiches à créer → {args.sortie}")
    for cat in ("collègue", "décideur"):
        print(f"{cat} : {compte[cat]}")
        for f in [f for f in resultat if f["categorie"] == cat][:10]:
            print(f"  - {f['Name']} | {f['Rôle']} | {f['Entreprise']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
