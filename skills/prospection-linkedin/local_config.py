"""Valeurs hors du repo public : anciennes boîtes (~/.claude-local/prospection.md) et clients (clients.txt)."""
import unicodedata
from dataclasses import dataclass
from pathlib import Path

LOCAL = Path.home() / ".claude-local"
PROSPECTION = LOCAL / "prospection.md"
CLIENTS = LOCAL / "clients.txt"


@dataclass(frozen=True)
class Boite:
    nom: str
    variantes: tuple[str, ...]
    annees: str


def normaliser(texte: str) -> str:
    """Sans accents, sans casse, espaces réduits."""
    sans = "".join(c for c in unicodedata.normalize("NFKD", texte) if not unicodedata.combining(c))
    return " ".join(sans.casefold().split())


def lire_anciennes_boites(path: Path = PROSPECTION) -> list[Boite]:
    """Lignes `- Nom | variantes : a, b | années : 2019-2021` ; variantes et années facultatives."""
    boites = []
    for ligne in path.read_text(encoding="utf-8").splitlines():
        if not ligne.startswith("- "):
            continue
        morceaux = [m.strip() for m in ligne[2:].split("|")]
        variantes, annees = (), ""
        for m in morceaux[1:]:
            cle, _, valeur = m.partition(":")
            cle = normaliser(cle)
            if cle == "variantes":
                variantes = tuple(v.strip() for v in valeur.split(",") if v.strip())
            elif cle == "annees":
                annees = valeur.strip()
        boites.append(Boite(morceaux[0], variantes, annees))
    return boites


def lire_clients(path: Path = CLIENTS) -> list[str]:
    """Un nom par ligne, `#` en commentaire. Liste vide si le fichier manque."""
    if not path.is_file():
        return []
    return [l.strip() for l in path.read_text(encoding="utf-8").splitlines() if l.strip() and not l.startswith("#")]


def est_ancienne_boite(entreprise: str, boites: list[Boite]) -> Boite | None:
    cible = normaliser(entreprise)
    if not cible:
        return None
    for b in boites:
        if cible in {normaliser(n) for n in (b.nom, *b.variantes)}:
            return b
    return None
