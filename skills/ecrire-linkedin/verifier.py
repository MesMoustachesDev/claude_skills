#!/usr/bin/env python3
"""Vérifie mécaniquement un texte LinkedIn contre les règles du skill ecrire-linkedin.

Usage : verifier.py post|commentaire|message <fichier>   (ou - pour stdin)
Sortie : ERREUR (à corriger, code 1) et ATTENTION (à juger). Ne remplace pas la relecture.
"""
import re
import sys
import unicodedata

if len(sys.argv) != 3 or sys.argv[1] not in ("post", "commentaire", "message"):
    sys.exit(__doc__)
mode, path = sys.argv[1], sys.argv[2]
texte = sys.stdin.read() if path == "-" else open(path, encoding="utf-8").read()
texte = texte.strip()
bas = texte.lower()

erreurs, attentions = [], []


def cherche(motifs, liste, quoi):
    for motif in motifs:
        m = re.search(motif, bas)
        if m:
            liste.append(f"{quoi} : « {texte[m.start():m.end()]} »")


# Caractères qu'on ne tape pas au clavier
for car, nom in [("—", "tiret cadratin"), ("–", "tiret demi-cadratin"), ("’", "apostrophe typographique"),
                 ("…", "points de suspension en un caractère (taper ...)")]:
    if car in texte:
        erreurs.append(f"{nom} ({texte.count(car)}x)")
for car in "→←⇒⇨➜➡•▸►▪◦✓✔":
    if car in texte:
        erreurs.append(f"symbole non tapable « {car} »")

# Emojis
INTERDITS = "🚀💡🎯🔥✅👉💪🙌📈✨⚡️🧠📌"
for e in INTERDITS:
    if e in texte:
        erreurs.append(f"emoji d'influenceur {e}")
emojis = [c for c in texte if unicodedata.category(c) == "So"]
if len(emojis) > 1:
    attentions.append(f"{len(emojis)} emojis (un seul au maximum)")

if re.search(r"(^|\s)#\w", texte):
    erreurs.append("hashtag")

# Faits interdits
cherche([r"runrox[^.\n]{0,40}flutter", r"flutter[^.\n]{0,40}runrox"], erreurs, "RunRox n'est pas en Flutter")
cherche([r"\baudin\b", r"my-?center", r"\bwifirst\b"], erreurs, "client cité par son nom")
cherche([r"\[à compléter", r"\[x\]", r"\btodo\b", r"\[\.\.\.\]"], erreurs, "trou laissé dans le texte")
cherche([r"\d[\d  .]*\s?k?\s(vues|votes|upvotes|likes|réactions|points|impressions|abonnés)\b",
         r"\d[\d  .]*\s?k?\s(commentaires|reposts|partages)\b"],
        erreurs, "chiffre d'audience d'une source (on s'en fout)")

# Tournures IA, communes à tout
TOURNURES = [
    r"c'est un peu (le|la|les|comme)\b", r"c'est comme\b", r"c'est l'équivalent", r"version 2\.0",
    r"\ble vrai (sujet|problème|boulot|enjeu)", r"\bla vraie (question|liberté|valeur)",
    r"le plus (dur|flippant|important),? c'est", r"le problème n'est pas", r"ce qui fait la différence",
    r"\bgame changer", r"changer la donne", r"faire la différence", r"créer de la valeur",
    r"dans un monde où", r"\blevier\b", r"\bc'est (la )?clé\b", r"\bpassionnant", r"\binspirant",
    r"\bpépite", r"\bincontournable", r"\bcrucial", r"merci pour (ce|le) partage", r"\bsuper post\b",
    r"réalité check", r"plot twist", r"le saviez-vous", r"\bmindset\b", r"\binsight",
]
cherche(TOURNURES, erreurs, "tournure IA")

if mode in ("commentaire", "message"):
    for car, nom in [("«", "guillemet « (guillemets droits en commentaire)"), ("»", "guillemet »"), (";", "point-virgule")]:
        if car in texte:
            erreurs.append(nom)
    cherche([r"^(exactement|tellement vrai|totalement d'accord|bien vu|smart|top ?!|très juste)",
             r"\bje vois que\b", r"\bje retiens\b", r"\bvaut mieux que\b", r"\bpas forcément\b",
             r"\breste toujours\b", r"\bau final\b", r"\bfinalement\b", r"\ben réalité\b",
             r"la question qui me vient", r"\bma question\b", r"\bje me demande\b",
             r"\bje l'ai toujours dit", r"\bessentiel", r"\bfondamental", r"tout change|change tout",
             r"\bau service de\b", r"et toi,? tu en penses quoi", r"curieux de voir", r"hâte de lire"],
            erreurs, "liste noire des commentaires")
    cherche([r"^[^,.!?\n]{3,60} sans [^,.!?\n]{3,40}, c'est"], erreurs, "formule « X sans Y, c'est Z »")
    mots = len(texte.split())
    limite = 60 if mode == "commentaire" else 80
    if mots > limite:
        erreurs.append(f"{mots} mots (max {limite})")
    elif mode == "commentaire" and mots > 20:
        attentions.append(f"{mots} mots : plus de 20, seulement pour une correction, un retour d'expérience ou une vraie réponse")
    if "http" in bas:
        erreurs.append("lien dans un commentaire ou un message")

if mode == "post":
    n = len(texte)
    if n > 3000:
        erreurs.append(f"{n} caractères (max 3000 pour The Engine)")
    elif n < 400:
        attentions.append(f"{n} caractères, court pour un post")
    lignes = [l.strip() for l in texte.splitlines() if l.strip()]
    ps = next((i for i, l in enumerate(lignes) if re.match(r"^p\.?s\b", l.lower())), None)
    if ps is None:
        erreurs.append("pas de PS")
    elif ps > 0 and lignes[ps - 1].endswith("?"):
        erreurs.append("la dernière ligne avant le PS est une question, il faut une punchline")
    if not any(l.endswith(":") for l in lignes) or not any(l.startswith("- ") for l in lignes):
        attentions.append("pas de ligne finie par « : » suivie d'une liste en « - »")
    if "(" not in texte:
        attentions.append("pas de parenthèses")

for e in erreurs:
    print(f"ERREUR     {e}")
for a in attentions:
    print(f"ATTENTION  {a}")
if not erreurs and not attentions:
    print("OK")
sys.exit(1 if erreurs else 0)
