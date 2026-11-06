#!/usr/bin/env python3
"""Vérifie un prospect proposé par le modèle avant toute écriture (Notion, The Engine).

Usage : verifier_prospect.py prospect.json   (ou - pour stdin)
JSON : {name, linkedin_url, company, role, signal: {type, date, url, line}, message, relance}
Sortie : ERREUR (refus, code 1) et ATTENTION (à juger, code 0).
"""
import json
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

from local_config import lire_clients

ICI = Path(__file__).resolve().parent
VERIFIER_ECRIRE = ICI.parent / "ecrire-linkedin" / "verifier.py"
CLES = ("name", "linkedin_url", "company", "role", "signal", "message", "relance")
CLES_SIGNAL = ("type", "date", "url", "line")
MAX_MESSAGE, MAX_RELANCE, MAX_AGE_JOURS = 400, 300, 14


def _verifier_texte(texte: str, verifier_py: Path) -> tuple[list[str], list[str]]:
    r = subprocess.run([sys.executable, str(verifier_py), "message", "-"], input=texte,
                       capture_output=True, text=True)
    erreurs, attentions = [], []
    for ligne in r.stdout.splitlines():
        for prefixe, liste in (("ERREUR", erreurs), ("ATTENTION", attentions)):
            if ligne.startswith(prefixe):
                liste.append(ligne[len(prefixe):].strip(" :"))
    if r.returncode != 0 and not erreurs:
        erreurs.append(f"le vérificateur d'ecrire-linkedin a échoué (code {r.returncode}) : {r.stderr.strip()[:200]}")
    return erreurs, attentions


def verifier(prospect: dict, aujourd_hui: date, clients: list[str], verifier_py: Path) -> tuple[list[str], list[str]]:
    erreurs, attentions = [], []
    manquantes = [c for c in CLES if not prospect.get(c)]
    signal = prospect.get("signal") if isinstance(prospect.get("signal"), dict) else {}
    manquantes += [f"signal.{c}" for c in CLES_SIGNAL if not signal.get(c)]
    if manquantes:
        return [f"clés manquantes : {', '.join(manquantes)}"], []

    if not re.fullmatch(r"https://linkedin\.com/in/[a-z0-9-]+", prospect["linkedin_url"]):
        erreurs.append(f"linkedin_url n'est pas un profil canonique : {prospect['linkedin_url']}")
    if signal["type"] not in ("offre", "levee"):
        erreurs.append(f"signal.type doit valoir offre ou levee : {signal['type']}")
    try:
        age = (aujourd_hui - date.fromisoformat(signal["date"])).days
        if age < 0 or age > MAX_AGE_JOURS:
            erreurs.append(f"signal.date hors des {MAX_AGE_JOURS} derniers jours : {signal['date']}")
    except ValueError:
        erreurs.append(f"signal.date n'est pas une date ISO : {signal['date']}")
    if not re.match(r"^https?://", signal["url"]):
        erreurs.append(f"signal.url n'est pas une URL : {signal['url']}")
    if len(prospect["message"]) > MAX_MESSAGE:
        erreurs.append(f"message trop long : {len(prospect['message'])} caractères (max {MAX_MESSAGE})")
    if len(prospect["relance"]) > MAX_RELANCE:
        erreurs.append(f"relance trop longue : {len(prospect['relance'])} caractères (max {MAX_RELANCE})")

    if not clients:
        attentions.append("~/.claude-local/clients.txt absent ou vide : les noms des clients ne sont pas vérifiés")
    for quoi in ("message", "relance"):
        for nom in clients:
            if re.search(rf"\b{re.escape(nom)}\b", prospect[quoi], re.IGNORECASE):
                erreurs.append(f"{quoi} : client cité par son nom ({nom})")
        e, a = _verifier_texte(prospect[quoi], verifier_py)
        erreurs += [f"{quoi} : {x}" for x in e]
        attentions += [f"{quoi} : {x}" for x in a]
    return erreurs, attentions


def main() -> int:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    brut = sys.stdin.read() if sys.argv[1] == "-" else Path(sys.argv[1]).read_text(encoding="utf-8")
    try:
        prospect = json.loads(brut)
    except json.JSONDecodeError as e:
        print(f"ERREUR : JSON illisible ({e})")
        return 1
    if not isinstance(prospect, dict):
        print("ERREUR : le JSON doit être un objet")
        return 1
    erreurs, attentions = verifier(prospect, date.today(), lire_clients(), VERIFIER_ECRIRE)
    for e in erreurs:
        print(f"ERREUR : {e}")
    for a in attentions:
        print(f"ATTENTION : {a}")
    if not erreurs and not attentions:
        print("OK")
    return 1 if erreurs else 0


if __name__ == "__main__":
    sys.exit(main())
