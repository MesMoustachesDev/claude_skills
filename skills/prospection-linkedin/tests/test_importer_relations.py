import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ICI = Path(__file__).resolve().parent
sys.path.insert(0, str(ICI.parent))

from importer_relations import canoniser_url, classer, fiches, lire_connections  # noqa: E402

FIXTURE = ICI / "fixtures" / "Connections.csv"


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

    def test_classer_ignore_l_entreprise(self):
        # L'export donne l'entreprise actuelle : y avoir travaillé ne fait pas de quelqu'un un collègue.
        self.assertIsNone(classer("Développeur"))
        self.assertEqual(classer("CTO"), "décideur")
        self.assertEqual(classer("Head of Mobile"), "décideur")
        self.assertEqual(classer("CTO & co-founder"), "décideur")
        self.assertEqual(classer("Fondatrice"), "décideur")
        self.assertIsNone(classer("Lead Talent Acquisition"))
        self.assertIsNone(classer("Leader d'opinion"))

    def test_classer_cofondateurs(self):
        for poste in ("Co-fondateur", "CEO & Co-fondatrice", "Cofounder", "Co-Founder & CPO"):
            self.assertEqual(classer(poste), "décideur", poste)

    def test_canoniser_url_sans_schema_ou_en_majuscules(self):
        self.assertEqual(canoniser_url("www.linkedin.com/in/x-y"), "https://linkedin.com/in/x-y")
        self.assertEqual(canoniser_url("linkedin.com/in/x-y/"), "https://linkedin.com/in/x-y")
        self.assertEqual(canoniser_url("https://WWW.LINKEDIN.COM/in/X-Y"), "https://linkedin.com/in/x-y")
        self.assertEqual(canoniser_url("https://evillinkedin.com/in/x-y"), "")

    def test_lire_connections_champ_sur_deux_lignes_et_ligne_courte(self):
        with tempfile.TemporaryDirectory() as d:
            csv_path = Path(d) / "Connections.csv"
            csv_path.write_text("First Name,Last Name,URL,Email Address,Company,Position,Connected On\n"
                                'Ana,Lopez,https://linkedin.com/in/ana,,Startup X,"Head of Mobile\nFlutter",01 Jan 2025\n'
                                "Bob,Court\n", encoding="utf-8")
            relations = lire_connections(csv_path)
        self.assertEqual(relations[0]["poste"], "Head of Mobile\nFlutter")
        self.assertEqual(relations[1]["url"], "")

    def test_fiches_ecarte_les_doublons(self):
        relations = lire_connections(FIXTURE)
        resultat = fiches(relations, {"https://linkedin.com/in/marc-bernard"}, set())
        self.assertEqual([f["Name"] for f in resultat], ["Paul Durand"])
        paul = resultat[0]
        self.assertEqual(paul["Notes"], "relation LinkedIn, CTO, co-founder chez Startup X")
        self.assertEqual(paul["LinkedIn URL"], "https://linkedin.com/in/paul-durand")
        self.assertEqual(paul["Statut"], "À contacter")
        self.assertEqual(paul["Source"], "Réseau")
        self.assertEqual(set(paul), {"Name", "LinkedIn URL", "Entreprise", "Rôle", "Statut", "Source",
                                     "Notes", "categorie"})

    def test_fiches_jamais_collegue(self):
        relations = lire_connections(FIXTURE)
        resultat = fiches(relations, set(), set())
        self.assertNotIn("Jeanne Martin", [f["Name"] for f in resultat])
        self.assertTrue(all(not f["Notes"].startswith("collègue") for f in resultat))

    def test_fiches_ecarte_un_nom_existant(self):
        relations = lire_connections(FIXTURE)
        resultat = fiches(relations, set(), {"paul durand"})
        self.assertEqual([f["Name"] for f in resultat], ["Marc Bernard"])

    def test_cli(self):
        with tempfile.TemporaryDirectory() as d:
            existants = Path(d) / "existants.json"
            existants.write_text(json.dumps({"urls": [], "noms": []}))
            sortie = Path(d) / "fiches.json"
            r = subprocess.run([sys.executable, str(ICI.parent / "importer_relations.py"), str(FIXTURE),
                                str(existants), "--sortie", str(sortie)],
                               capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertNotIn("collègue", r.stdout)
            self.assertIn("décideur : 2", r.stdout)
            self.assertEqual(len(json.loads(sortie.read_text())), 2)


if __name__ == "__main__":
    unittest.main()
