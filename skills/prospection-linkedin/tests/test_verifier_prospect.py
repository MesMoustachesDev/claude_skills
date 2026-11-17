import copy
import json
import subprocess
import sys
import tempfile
import unittest
from datetime import date, timedelta
from pathlib import Path

ICI = Path(__file__).resolve().parent
sys.path.insert(0, str(ICI.parent))

from verifier_prospect import verifier  # noqa: E402

AUJOURD_HUI = date(2026, 11, 6)
VALIDE = {
    "name": "Paul Durand",
    "linkedin_url": "https://linkedin.com/in/paul-durand",
    "company": "Startup X",
    "role": "CTO",
    "signal": {"type": "offre", "date": "2026-11-04", "url": "https://example.com/offre", "line": "recrute un dev Flutter"},
    "message": "Salut Paul, vous cherchez un dev Flutter pour l'app de réservation. Tu veux qu'on en parle ?",
    "relance": "Le recrutement avance de ton côté ?",
}


def faux_verificateur(dossier: Path, sortie: str, code: int) -> Path:
    script = dossier / "verifier.py"
    script.write_text(f"import sys\nsys.stdin.read()\nprint({sortie!r})\nsys.exit({code})\n")
    return script


class VerifierProspectTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.ok = faux_verificateur(Path(self.dir.name), "", 0)

    def tearDown(self):
        self.dir.cleanup()

    def prospect(self, **changements):
        p = copy.deepcopy(VALIDE)
        for cle, valeur in changements.items():
            if cle.startswith("signal_"):
                p["signal"][cle[7:]] = valeur
            else:
                p[cle] = valeur
        return p

    def lancer(self, prospect, clients=("Acme",), verificateur=None):
        return verifier(prospect, AUJOURD_HUI, list(clients), verificateur or self.ok)

    def test_valide(self):
        self.assertEqual(self.lancer(self.prospect()), ([], []))

    def test_cle_manquante(self):
        p = self.prospect()
        del p["relance"]
        erreurs, _ = self.lancer(p)
        self.assertTrue(any("relance" in e for e in erreurs), erreurs)

    def test_url_entreprise_refusee(self):
        erreurs, _ = self.lancer(self.prospect(linkedin_url="https://linkedin.com/company/x"))
        self.assertTrue(any("linkedin_url" in e for e in erreurs), erreurs)

    def test_type_de_signal_inconnu(self):
        erreurs, _ = self.lancer(self.prospect(signal_type="rumeur"))
        self.assertTrue(any("signal.type" in e for e in erreurs), erreurs)

    def test_date_trop_vieille(self):
        erreurs, _ = self.lancer(self.prospect(signal_date=(AUJOURD_HUI - timedelta(days=15)).isoformat()))
        self.assertTrue(any("14" in e for e in erreurs), erreurs)

    def test_date_future_ou_illisible(self):
        erreurs, _ = self.lancer(self.prospect(signal_date="2026-11-07"))
        self.assertTrue(erreurs)
        erreurs, _ = self.lancer(self.prospect(signal_date="hier"))
        self.assertTrue(erreurs)

    def test_url_du_signal(self):
        erreurs, _ = self.lancer(self.prospect(signal_url="example.com/offre"))
        self.assertTrue(any("signal.url" in e for e in erreurs), erreurs)

    def test_message_trop_long(self):
        erreurs, _ = self.lancer(self.prospect(message="a" * 401))
        self.assertTrue(any("400" in e for e in erreurs), erreurs)

    def test_relance_trop_longue(self):
        erreurs, _ = self.lancer(self.prospect(relance="a" * 301))
        self.assertTrue(any("300" in e for e in erreurs), erreurs)

    def test_client_nomme(self):
        erreurs, _ = self.lancer(self.prospect(message="Comme chez Acme, on a refait l'app."))
        self.assertTrue(any("client" in e for e in erreurs), erreurs)

    def test_clients_absent_attention(self):
        erreurs, attentions = self.lancer(self.prospect(), clients=())
        self.assertEqual(erreurs, [])
        self.assertTrue(any("clients.txt" in a for a in attentions), attentions)

    def test_erreur_du_verificateur_ecrire_linkedin(self):
        faux = faux_verificateur(Path(self.dir.name), "ERREUR : tournure IA", 1)
        erreurs, _ = self.lancer(self.prospect(), verificateur=faux)
        self.assertTrue(any("tournure IA" in e for e in erreurs), erreurs)

    def test_attention_du_verificateur_ecrire_linkedin(self):
        faux = faux_verificateur(Path(self.dir.name), "ATTENTION : phrase longue", 0)
        erreurs, attentions = self.lancer(self.prospect(), verificateur=faux)
        self.assertEqual(erreurs, [])
        self.assertTrue(any("phrase longue" in a for a in attentions), attentions)

    def test_role_non_decideur(self):
        erreurs, _ = self.lancer(self.prospect(role="Talent Acquisition"))
        self.assertTrue(any("décideur" in e for e in erreurs), erreurs)

    def test_slug_avec_accent_encode(self):
        erreurs, _ = self.lancer(self.prospect(linkedin_url="https://linkedin.com/in/marie-l%c3%a9a-12"))
        self.assertEqual(erreurs, [])

    def fm(self, type_, age, **changements):
        changements.setdefault("signal_url", "https://www.linkedin.com/posts/x_activity-1")
        return self.prospect(signal_type=type_, signal_date=(AUJOURD_HUI - timedelta(days=age)).isoformat(),
                             **changements)

    def test_freelance_dans_sa_fenetre(self):
        self.assertEqual(self.lancer(self.fm("freelance", 40))[0], [])

    def test_freelance_trop_recent_reste_a_mission_linkedin(self):
        erreurs, _ = self.lancer(self.fm("freelance", 10))
        self.assertTrue(any("21" in e for e in erreurs), erreurs)

    def test_freelance_trop_vieux(self):
        erreurs, _ = self.lancer(self.fm("freelance", 91))
        self.assertTrue(any("90" in e for e in erreurs), erreurs)

    def test_signal_fm_hors_linkedin(self):
        erreurs, _ = self.lancer(self.fm("freelance", 40, signal_url="https://example.com/x"))
        self.assertTrue(any("post LinkedIn" in e for e in erreurs), erreurs)

    def test_fin_de_mission_proche(self):
        fin = (AUJOURD_HUI + timedelta(days=20)).isoformat()
        self.assertEqual(self.lancer(self.fm("fin_mission", 60, signal_fin=fin))[0], [])

    def test_fin_de_mission_trop_loin_passee_ou_absente(self):
        for fin in ((AUJOURD_HUI + timedelta(days=31)).isoformat(), (AUJOURD_HUI - timedelta(days=1)).isoformat()):
            erreurs, _ = self.lancer(self.fm("fin_mission", 60, signal_fin=fin))
            self.assertTrue(any("signal.fin" in e for e in erreurs), (fin, erreurs))
        erreurs, _ = self.lancer(self.fm("fin_mission", 60))
        self.assertTrue(any("signal.fin" in e for e in erreurs), erreurs)

    def test_entreprise_vide_acceptee_pour_un_signal_fm(self):
        erreurs, attentions = self.lancer(self.fm("freelance", 40, company=""))
        self.assertEqual(erreurs, [])
        self.assertTrue(any("non nommée" in a for a in attentions), attentions)

    def test_entreprise_vide_refusee_pour_une_offre(self):
        erreurs, _ = self.lancer(self.prospect(company=""))
        self.assertTrue(any("company" in e for e in erreurs), erreurs)

    def test_cli_code_de_retour(self):
        script = ICI.parent / "verifier_prospect.py"
        mauvais = self.prospect(linkedin_url="https://linkedin.com/company/x")
        r = subprocess.run([sys.executable, str(script), "-"], input=json.dumps(mauvais),
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("ERREUR", r.stdout)


if __name__ == "__main__":
    unittest.main()
