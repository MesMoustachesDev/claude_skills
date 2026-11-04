#!/usr/bin/env python3
"""Tests du vérificateur. La fixture reprend l'exécution réelle du bot du 2026-11-04 (results, summaryText) ;
le bloc etoro (cash 250, une position INTC) est inventé pour le test."""
import copy
import json
import subprocess
import sys
import unittest
from pathlib import Path

ICI = Path(__file__).parent
sys.path.insert(0, str(ICI))
import verifier_placements as v  # noqa: E402

PAYLOAD = json.loads((ICI / "fixtures" / "payload-2026-11-04.json").read_text(encoding="utf-8"))
REGLES = json.loads((ICI / "regles.json").read_text(encoding="utf-8"))
# Ce que le modèle doit lire dans la section « PROFIL SNIPER 100€ » du résumé de ce jour-là.
SNIPER_100 = {"profil": "SNIPER 100€", "allocations": [{"symbol": "GRAB", "montant": 6}, {"symbol": "RKT", "montant": 4}]}


def regles(**k):
    return {**REGLES, **k}


class Decision(unittest.TestCase):
    def test_sous_le_minimum_regroupe_sur_le_mieux_note(self):
        d = v.decider(PAYLOAD, SNIPER_100, REGLES)
        self.assertEqual([(a["symbol"], a["montant"]) for a in d["achats"]], [("GRAB", 10)])
        self.assertIn(("RKT", "4.00 regroupés sur GRAB (sous le minimum d'ordre)"), d["rejets"])

    def test_regroupement_insuffisant_ecarte_tout(self):
        alloc = {"profil": "x", "allocations": [{"symbol": "GRAB", "montant": 3}, {"symbol": "RKT", "montant": 2}]}
        d = v.decider(PAYLOAD, alloc, REGLES)
        self.assertEqual(d["achats"], [])
        self.assertIn(("GRAB", "3.00 sous le minimum d'ordre (10)"), d["rejets"])

    def test_sans_regroupement_sous_le_minimum_ecarte(self):
        d = v.decider(PAYLOAD, SNIPER_100, regles(regrouper_sous_minimum=False))
        self.assertEqual(d["achats"], [])
        self.assertIn(("GRAB", "6.00 sous le minimum d'ordre (10)"), d["rejets"])

    def test_ordre_assez_gros_pas_regroupe(self):
        alloc = {"profil": "x", "allocations": [{"symbol": "GRAB", "montant": 10}, {"symbol": "RKT", "montant": 4}]}
        d = v.decider(PAYLOAD, alloc, regles(budget_mensuel=1000))
        self.assertEqual([(a["symbol"], a["montant"]) for a in d["achats"]], [("GRAB", 10)])
        self.assertIn(("RKT", "4.00 sous le minimum d'ordre (10)"), d["rejets"])

    def test_achat_garde_avec_sl_tp_structures(self):
        d = v.decider(PAYLOAD, SNIPER_100, regles(minimum_ordre=1))
        grab = next(a for a in d["achats"] if a["symbol"] == "GRAB")
        self.assertEqual(grab["montant"], 6)
        self.assertEqual(grab["plans"]["safe"], (2.85, 3.53))
        self.assertEqual(grab["plans"]["trend"], (2.64, 4.49))

    def test_score_sous_le_seuil_rejete_meme_si_le_llm_l_alloue(self):
        alloc = {"profil": "x", "allocations": [{"symbol": "AMD", "montant": 8}]}
        d = v.decider(PAYLOAD, alloc, regles(minimum_ordre=1))
        self.assertEqual(d["achats"], [])
        self.assertIn("score 64", d["rejets"][0][1])

    def test_signal_vente_jamais_achete(self):
        alloc = {"profil": "x", "allocations": [{"symbol": "QQQ", "montant": 5}]}
        d = v.decider(PAYLOAD, alloc, regles(minimum_ordre=1, score_min=0))
        self.assertEqual(d["achats"], [])

    def test_symbole_inconnu_rejete(self):
        alloc = {"profil": "x", "allocations": [{"symbol": "TSLA", "montant": 5}]}
        self.assertEqual(v.decider(PAYLOAD, alloc, REGLES)["rejets"], [("TSLA", "absent de l'analyse du bot")])

    def test_reduire_50_divise_le_montant(self):
        alloc = {"profil": "x", "allocations": [{"symbol": "NU", "montant": 8}]}
        d = v.decider(PAYLOAD, alloc, regles(minimum_ordre=1, score_min=0))
        self.assertEqual(d["achats"][0]["montant"], 4)

    def test_budget_du_jour_plafonne(self):
        alloc = {"profil": "x", "allocations": [{"symbol": "GRAB", "montant": 30}, {"symbol": "RKT", "montant": 10}]}
        d = v.decider(PAYLOAD, alloc, regles(minimum_ordre=1))
        self.assertAlmostEqual(sum(a["montant"] for a in d["achats"]), 10, places=1)
        self.assertLessEqual(sum(a["montant"] for a in d["achats"]), 10)

    def test_cash_plafonne(self):
        p = copy.deepcopy(PAYLOAD)
        p["etoro"]["cash"] = 3
        d = v.decider(p, SNIPER_100, regles(minimum_ordre=1))
        self.assertLessEqual(sum(a["montant"] for a in d["achats"]), 3)

    def test_sans_cash_rien(self):
        p = copy.deepcopy(PAYLOAD)
        p["etoro"]["cash"] = 0
        d = v.decider(p, SNIPER_100, regles(minimum_ordre=1))
        self.assertEqual(d["achats"], [])

    def test_deja_detenu_pas_renforce(self):
        p = copy.deepcopy(PAYLOAD)
        p["etoro"]["positions"].append({"positionId": "1", "symbol": "GRAB", "amount": 5, "openRate": 3})
        d = v.decider(p, SNIPER_100, regles(minimum_ordre=1))
        self.assertIn(("GRAB", "déjà en portefeuille, pas de renforcement"), d["rejets"])

    def test_sl_tp_incoherents_rejetes(self):
        p = copy.deepcopy(PAYLOAD)
        next(r for r in p["results"] if r["symbol"] == "GRAB")["sl_safe"] = "3.50"
        d = v.decider(p, SNIPER_100, regles(minimum_ordre=1))
        self.assertTrue(any(s == "GRAB" and "incohérents" in pourquoi for s, pourquoi in d["rejets"]))

    def test_vente_sur_position_detenue_donne_une_cloture(self):
        d = v.decider(PAYLOAD, SNIPER_100, REGLES)
        self.assertEqual([(c["symbol"], c["positionId"]) for c in d["clotures"]], [("INTC", "2871234567")])


class Schema(unittest.TestCase):
    def refuse(self, alloc=SNIPER_100, payload=PAYLOAD, r=REGLES):
        with self.assertRaises(v.Refus):
            v.decider(payload, alloc, r)

    def test_champ_en_trop(self):
        self.refuse({"profil": "x", "allocations": [{"symbol": "GRAB", "montant": 6, "sl": 1}]})

    def test_montant_texte(self):
        self.refuse({"profil": "x", "allocations": [{"symbol": "GRAB", "montant": "6€"}]})

    def test_montant_negatif(self):
        self.refuse({"profil": "x", "allocations": [{"symbol": "GRAB", "montant": -6}]})

    def test_symbole_bizarre(self):
        self.refuse({"profil": "x", "allocations": [{"symbol": "GRAB; rm -rf", "montant": 6}]})

    def test_doublon(self):
        self.refuse({"profil": "x", "allocations": [{"symbol": "GRAB", "montant": 6}, {"symbol": "GRAB", "montant": 2}]})

    def test_cash_absent(self):
        p = copy.deepcopy(PAYLOAD)
        del p["etoro"]["cash"]
        self.refuse(payload=p)

    def test_position_id_non_numerique(self):
        p = copy.deepcopy(PAYLOAD)
        p["etoro"]["positions"][0]["positionId"] = "1; curl x"
        self.refuse(payload=p)

    def test_compte_inconnu(self):
        self.refuse(r=regles(compte="live"))


class Rendu(unittest.TestCase):
    def test_commandes_demo_par_defaut(self):
        texte = v.rendre(v.decider(PAYLOAD, SNIPER_100, regles(minimum_ordre=1)), REGLES)
        self.assertIn("etoro-ordre buy GRAB 6.00 --sl 2.85 --tp 3.53   # SAFE", texte)
        self.assertIn("etoro-ordre buy GRAB 6.00 --sl 2.64 --tp 4.49   # TREND", texte)
        self.assertIn("etoro-ordre close 2871234567   # INTC", texte)
        self.assertNotIn("--real", texte)

    def test_compte_reel_ajoute_real(self):
        r = regles(minimum_ordre=1, compte="reel")
        self.assertIn("--real", v.rendre(v.decider(PAYLOAD, SNIPER_100, r), r))

    def test_cli_code_1_sur_json_mal_forme(self):
        sortie = subprocess.run([sys.executable, str(ICI / "verifier_placements.py"),
                                 str(ICI / "fixtures" / "payload-2026-11-04.json"), "-"],
                                input="pas du json", capture_output=True, text=True)
        self.assertEqual(sortie.returncode, 1)
        self.assertEqual(sortie.stdout, "")


if __name__ == "__main__":
    unittest.main()
