import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from local_config import est_ancienne_boite, lire_anciennes_boites, lire_clients  # noqa: E402

GABARIT = """# Prospection : valeurs hors du repo public
## Anciennes boîtes
- Boîte A | variantes : boite a, boîte a sas | années : 2019-2021
- Boîte B | années : 2022
"""


class LocalConfigTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = Path(self.dir.name) / "prospection.md"
        self.path.write_text(GABARIT, encoding="utf-8")

    def tearDown(self):
        self.dir.cleanup()

    def test_lit_deux_boites(self):
        boites = lire_anciennes_boites(self.path)
        self.assertEqual(len(boites), 2)
        self.assertEqual(boites[0].nom, "Boîte A")
        self.assertEqual(len(boites[0].variantes), 2)
        self.assertEqual(boites[0].annees, "2019-2021")
        self.assertEqual(boites[1].variantes, ())
        self.assertEqual(boites[1].annees, "2022")

    def test_est_ancienne_boite_sans_accent(self):
        boites = lire_anciennes_boites(self.path)
        self.assertEqual(est_ancienne_boite("BOITE A SAS", boites).nom, "Boîte A")
        self.assertIsNone(est_ancienne_boite("Startup X", boites))

    def test_ne_lit_que_la_section_anciennes_boites(self):
        self.path.write_text(GABARIT + "## Noms à ne jamais publier\n- Startup X\n", encoding="utf-8")
        self.assertEqual([b.nom for b in lire_anciennes_boites(self.path)], ["Boîte A", "Boîte B"])

    def test_fichier_absent(self):
        with self.assertRaises(FileNotFoundError):
            lire_anciennes_boites(Path("/nulle/part"))
        self.assertEqual(lire_clients(Path("/nulle/part")), [])


if __name__ == "__main__":
    unittest.main()
