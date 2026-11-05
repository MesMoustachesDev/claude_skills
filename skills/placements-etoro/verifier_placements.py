#!/usr/bin/env python3
"""Décide des placements à proposer à partir du payload du Trading Bot et des montants lus par le modèle.

Usage : verifier_placements.py <payload.json> <allocations.json | -> [regles.json]
  payload.json      : le bloc routine-fire-payload envoyé par n8n
  allocations.json  : ce que le modèle a lu dans summaryText, {"profil": "...", "allocations": [{"symbol", "montant"}]}
  regles.json       : par défaut celui à côté de ce script
Sortie : le rendu Markdown avec les commandes etoro-ordre. Code 1 si une entrée sort du schéma : rien n'est proposé.

Le modèle traduit, le script décide : seuls le symbole et le montant viennent du texte du LLM.
Signal, score, SL et TP viennent des champs structurés de Analyze All, et le script refuse tout ce qui ne passe pas.
"""
import json
import math
import re
import sys
from pathlib import Path

SYMBOLE = re.compile(r"^[A-Z0-9][A-Z0-9.\-]{0,14}$")
REGLES = {"profil": str, "budget_mensuel": (int, float), "fraction_jour": (int, float), "score_min": (int, float),
          "minimum_ordre": (int, float), "regrouper_sous_minimum": bool, "renforcer_si_detenu": bool, "compte": str}


class Refus(Exception):
    pass


def lire(path):
    try:
        return json.load(sys.stdin) if path == "-" else json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        raise Refus(f"{path} : JSON illisible ({e})")


def nombre(valeur, quoi):
    """Les prix arrivent en texte (toFixed) : on accepte un nombre ou un texte qui en est un, rien d'autre."""
    if isinstance(valeur, bool):
        raise Refus(f"{quoi} : pas un nombre ({valeur!r})")
    try:
        n = float(valeur)
    except (TypeError, ValueError):
        raise Refus(f"{quoi} : pas un nombre ({valeur!r})")
    if not math.isfinite(n):
        raise Refus(f"{quoi} : pas un nombre ({valeur!r})")
    return n


def verifier_regles(regles):
    for cle, type_ in REGLES.items():
        if not isinstance(regles.get(cle), type_) or (type_ is not bool and isinstance(regles.get(cle), bool)):
            raise Refus(f"regles.json : « {cle} » manquant ou mal typé")
    if regles["compte"] not in ("demo", "reel"):
        raise Refus("regles.json : « compte » vaut demo ou reel")
    if not 0 < regles["fraction_jour"] <= 1:
        raise Refus("regles.json : « fraction_jour » entre 0 et 1")


def verifier_payload(payload):
    if not isinstance(payload, dict):
        raise Refus("payload : objet attendu")
    results = payload.get("results")
    etoro = payload.get("etoro")
    if not isinstance(results, list) or not isinstance(etoro, dict):
        raise Refus("payload : « results » (liste) et « etoro » (objet) attendus")
    actifs = {}
    for i, r in enumerate(results):
        if not isinstance(r, dict) or not isinstance(r.get("symbol"), str) or not isinstance(r.get("tagCT"), str):
            raise Refus(f"payload : results[{i}] sans symbol ou tagCT")
        actifs[r["symbol"].upper()] = r
    cash = nombre(etoro.get("cash"), "etoro.cash")
    positions = etoro.get("positions")
    if not isinstance(positions, list):
        raise Refus("payload : « etoro.positions » (liste) attendu")
    for i, p in enumerate(positions):
        if not isinstance(p, dict) or not isinstance(p.get("symbol"), str) or not re.fullmatch(r"\d{1,20}", str(p.get("positionId", ""))):
            raise Refus(f"payload : etoro.positions[{i}] sans symbol ou positionId numérique")
    return actifs, cash, positions


def verifier_allocations(alloc):
    if not isinstance(alloc, dict) or set(alloc) != {"profil", "allocations"} or not isinstance(alloc["allocations"], list):
        raise Refus("allocations : {\"profil\", \"allocations\": [...]} attendu, sans autre champ")
    vues = set()
    for i, a in enumerate(alloc["allocations"]):
        if not isinstance(a, dict) or set(a) != {"symbol", "montant"}:
            raise Refus(f"allocations[{i}] : {{\"symbol\", \"montant\"}} attendu, sans autre champ")
        if not isinstance(a["symbol"], str) or not SYMBOLE.fullmatch(a["symbol"]):
            raise Refus(f"allocations[{i}] : symbole invalide ({a['symbol']!r})")
        if a["symbol"] in vues:
            raise Refus(f"allocations[{i}] : {a['symbol']} en double")
        vues.add(a["symbol"])
        if isinstance(a["montant"], bool) or not isinstance(a["montant"], (int, float)) or not 0 < a["montant"] <= 10000:
            raise Refus(f"allocations[{i}] : montant hors bornes ({a['montant']!r})")


def decider(payload, alloc, regles):
    verifier_regles(regles)
    actifs, cash, positions = verifier_payload(payload)
    verifier_allocations(alloc)
    detenus = {}
    for p in positions:
        detenus.setdefault(p["symbol"].upper(), []).append(p)

    achats, rejets = [], []
    for a in alloc["allocations"]:
        sym, montant = a["symbol"], float(a["montant"])
        r = actifs.get(sym)
        if r is None:
            rejets.append((sym, "absent de l'analyse du bot"))
            continue
        if "BUY" not in r["tagCT"]:
            rejets.append((sym, f"signal {r['tagCT']}, pas un achat"))
            continue
        score = nombre(r.get("globalScore"), f"{sym}.globalScore")
        if score <= regles["score_min"]:
            rejets.append((sym, f"score {score:g} ≤ {regles['score_min']:g} (seuil du profil)"))
            continue
        if sym in detenus and not regles["renforcer_si_detenu"]:
            rejets.append((sym, "déjà en portefeuille, pas de renforcement"))
            continue
        try:
            prix = nombre(r.get("price"), f"{sym}.price")
            plans = {nom: (nombre(r.get(f"sl_{nom}"), f"{sym}.sl_{nom}"), nombre(r.get(f"tp_{nom}"), f"{sym}.tp_{nom}"))
                     for nom in ("safe", "trend")}
        except Refus as e:
            rejets.append((sym, f"plan incomplet ({e})"))
            continue
        incoherent = [nom for nom, (sl, tp) in plans.items() if not sl < prix < tp]
        if incoherent:
            rejets.append((sym, f"SL/TP incohérents avec le prix ({', '.join(incoherent)})"))
            continue
        if "50%" in str(r.get("positionAdvice", "")):
            montant /= 2
        achats.append({"symbol": sym, "score": score, "prix": prix, "plans": plans, "montant": montant,
                       "conseil": r.get("positionAdvice", ""), "raison": r.get("reasonCT", "")})

    budget = min(regles["budget_mensuel"] * regles["fraction_jour"], cash)
    total = sum(a["montant"] for a in achats)
    if total > budget > 0:
        for a in achats:
            a["montant"] = math.floor(a["montant"] * budget / total * 100) / 100
    elif budget <= 0:
        for a in achats:
            rejets.append((a["symbol"], "pas de cash disponible"))
        achats = []
    gardes = [a for a in achats if a["montant"] >= regles["minimum_ordre"]]
    petits = [a for a in achats if a["montant"] < regles["minimum_ordre"]]
    if petits and regles["regrouper_sous_minimum"]:
        # Le budget des ordres trop petits va au mieux noté d'entre eux, s'il atteint alors le minimum.
        meilleur = max(petits, key=lambda a: a["score"])
        regroupe = sum(a["montant"] for a in petits)
        if regroupe >= regles["minimum_ordre"]:
            for a in petits:
                if a is not meilleur:
                    rejets.append((a["symbol"], f"{a['montant']:.2f} regroupés sur {meilleur['symbol']} (sous le minimum d'ordre)"))
            meilleur["montant"] = regroupe
            gardes.append(meilleur)
            petits = []
    for a in petits:
        rejets.append((a["symbol"], f"{a['montant']:.2f} sous le minimum d'ordre ({regles['minimum_ordre']:g})"))

    clotures = []
    for sym, r in actifs.items():
        if "SELL" in r["tagCT"] and sym in detenus:
            for p in detenus[sym]:
                clotures.append({"symbol": sym, "positionId": str(p["positionId"]), "tag": r["tagCT"],
                                 "raison": r.get("reasonCT", "")})
    return {"cash": cash, "budget": budget, "achats": gardes, "rejets": rejets, "clotures": clotures}


def rendre(d, regles):
    reel = " --real" if regles["compte"] == "reel" else ""
    compte = "RÉEL" if reel else "démo"
    lignes = [f"Cash disponible : {d['cash']:.2f} · budget du jour : {d['budget']:.2f} · compte : {compte}", ""]
    if d["achats"]:
        lignes += ["| Actif | Score | Montant | SAFE (SL → TP) | TREND (SL → TP) | Raison |", "|---|---|---|---|---|---|"]
        for a in d["achats"]:
            (ss, ts), (st, tt) = a["plans"]["safe"], a["plans"]["trend"]
            lignes.append(f"| {a['symbol']} | {a['score']:g} | {a['montant']:.2f} | {ss:g} → {ts:g} | {st:g} → {tt:g} | {a['raison']} |")
    else:
        lignes.append("Aucun achat retenu aujourd'hui.")
    if d["clotures"]:
        lignes += ["", "Clôtures proposées :"]
        lignes += [f"- {c['symbol']} (position {c['positionId']}) : {c['tag']}, {c['raison']}" for c in d["clotures"]]
    if d["rejets"]:
        lignes += ["", "Écartés :"] + [f"- {s} : {pourquoi}" for s, pourquoi in d["rejets"]]
    commandes = []
    for a in d["achats"]:
        for nom in ("safe", "trend"):
            sl, tp = a["plans"][nom]
            commandes.append(f"etoro-ordre buy {a['symbol']} {a['montant']:.2f} --sl {sl:g} --tp {tp:g}{reel}   # {nom.upper()}")
    commandes += [f"etoro-ordre close {c['positionId']}{reel}   # {c['symbol']}" for c in d["clotures"]]
    if commandes:
        lignes += ["", "Commandes (une seule par achat : SAFE ou TREND) :", "```bash", *commandes, "```"]
    return "\n".join(lignes)


def main(argv):
    if len(argv) not in (3, 4):
        sys.exit(__doc__)
    regles_path = argv[3] if len(argv) == 4 else Path(__file__).with_name("regles.json")
    try:
        regles = lire(str(regles_path))
        d = decider(lire(argv[1]), lire(argv[2]), regles)
    except Refus as e:
        print(f"ERREUR : {e}. Aucun placement proposé.", file=sys.stderr)
        return 1
    print(rendre(d, regles))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
