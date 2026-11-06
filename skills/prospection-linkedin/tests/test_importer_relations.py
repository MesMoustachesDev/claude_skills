import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ICI = Path(__file__).resolve().parent
sys.path.insert(0, str(ICI.parent))

from importer_relations import canoniser_url, classer, fiches, lire_connections  # noqa: E402
from local_config import Boite  # noqa: E402

FIXTURE = ICI / "fixtures" / "Connections.csv"
BOITES = [Boite("Boîte A", ("boite a sas",), "2019-2021")]


class ImporterRelationsTest(unittest.TestCase):
    def test_lire_connections_saute_les_notes(self):
        relations = lire_connections(FIXTURE)
        self.assertEqual(len(relations), 5)
        paul = next(r for r in relations if r["prenom"] == "Paul")
        self.assertEqual(paul["poste"], "CTO, co-founder")
        self.assertEqual(paul["entreprise"], "Startup X")
        self.assertEqual(paul["connecte_le"], "03 Jan 2023")

    def test_canoniser_url(self):
        self.assertEqual(canoniser_url("https://www.linkedin.com/in/Jean-Dupont-123/?trk=x"),
                         "https://linkedin.com/in/jean-dupont-123")
        self.assertEqual(canoniser_url("https://fr.linkedin.com/in/jean-dupont-123"),
                         "https://linkedin.com/in/jean-dupont-123")
        self.assertEqual(canoniser_url("https://linkedin.com/company/x"), "")
        self.assertEqual(canoniser_url(""), "")

    def test_classer_collegue_avant_decideur(self):
        self.assertEqual(classer("Développeur", "Boîte A SAS", BOITES), "collègue")
        self.assertEqual(classer("CTO", "Boîte A", BOITES), "collègue")
        self.assertEqual(classer("Head of Mobile", "Startup X", BOITES), "décideur")
        self.assertEqual(classer("CTO & co-founder", "Startup X", BOITES), "décideur")
        self.assertEqual(classer("Fondatrice", "Startup X", BOITES), "décideur")
        self.assertIsNone(classer("Lead Talent Acquisition", "Cabinet Y", BOITES))
        self.assertIsNone(classer("Développeur", "Startup X", BOITES))
        self.assertIsNone(classer("Leader d'opinion", "Startup X", BOITES))

    def test_fiches_ecarte_les_doublons(self):
        relations = lire_connections(FIXTURE)
        resultat = fiches(relations, BOITES, {"https://linkedin.com/in/marc-bernard"}, set())
        noms = [f["Name"] for f in resultat]
        self.assertEqual(noms, ["Jeanne Martin", "Paul Durand"])
        jeanne, paul = resultat
        self.assertEqual(jeanne["Notes"], "collègue chez Boîte A (2019-2021)")
        self.assertEqual(jeanne["LinkedIn URL"], "https://linkedin.com/in/jeanne-martin-123")
        self.assertEqual(paul["Notes"], "relation LinkedIn, CTO, co-founder chez Startup X")
        for f in resultat:
            self.assertEqual(f["Statut"], "À contacter")
            self.assertEqual(f["Source"], "Réseau")
            self.assertEqual(set(f), {"Name", "LinkedIn URL", "Entreprise", "Rôle", "Statut", "Source",
                                      "Notes", "categorie"})

    def test_fiches_ecarte_un_nom_existant(self):
        relations = lire_connections(FIXTURE)
        resultat = fiches(relations, BOITES, set(), {"paul durand"})
        self.assertEqual([f["Name"] for f in resultat], ["Jeanne Martin", "Marc Bernard"])

    def test_cli(self):
        with tempfile.TemporaryDirectory() as d:
            existants = Path(d) / "existants.json"
            existants.write_text(json.dumps({"urls": [], "noms": []}))
            sortie = Path(d) / "fiches.json"
            r = subprocess.run([sys.executable, str(ICI.parent / "importer_relations.py"), str(FIXTURE),
                                str(existants), "--sortie", str(sortie), "--boites", str(ICI / "fixtures" / "prospection.md")],
                               capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("collègue : 1", r.stdout)
            self.assertIn("décideur : 2", r.stdout)
            self.assertEqual(len(json.loads(sortie.read_text())), 3)


if __name__ == "__main__":
    unittest.main()
