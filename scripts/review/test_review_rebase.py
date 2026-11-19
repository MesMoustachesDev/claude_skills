#!/usr/bin/env python3
"""Rejeu à blanc : une MR GitLab rebasée entre la relecture des agents et la publication.

    python3 scripts/review/test_review_rebase.py

Monte un remote nu et deux clones (celui du projet, où tourne review.sh, et celui de l'auteur de la MR), un faux
`glab` sur le PATH (il rend la MR telle qu'un fichier JSON la décrit et journalise ce qu'on lui poste), un HOME
jetable pour l'état de la revue. Puis :

1. la MR est à H1 ; l'agent code relit H1 et pose F1 (ligne 5, ajoutée par la MR) et F2 (ligne 6, idem) ;
2. l'auteur rebase sur develop (3 lignes ajoutées en tête du même fichier) et réécrit la ligne de F2 : H2,
   que le clone du projet n'a pas encore ;
3. `review.sh next` doit signaler que l'agent a relu H1 alors que la MR est à H2 ;
4. `review.sh post` (aperçu) puis `post --go` doivent placer F1 en ligne, à la ligne 8 de H2, avec les diff_refs
   de H2, et poster F2 en commentaire général cité au commit relu.
Rien ne sort de la machine : la forge est le faux glab.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REVIEW_SH = os.path.join(os.path.dirname(HERE), "review.sh")

FAKE_GLAB = r"""#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
if a[:2] == ["mr", "view"]:
    sys.stdout.write(open(os.environ["STUB_MR_JSON"]).read()); sys.exit(0)
with open(os.environ["STUB_LOG"], "a") as f:
    f.write(json.dumps({"args": a, "stdin": sys.stdin.read() if "--input" in a else None}) + "\n")
print("{}")
"""


class RebaseDuringReview(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="review-rebase-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        t = self.tmp
        gitcfg = os.path.join(t, "gitconfig")
        with open(gitcfg, "w") as f:
            f.write("[user]\n\tname = Test\n\temail = test@example.invalid\n[init]\n\tdefaultBranch = develop\n")
        os.makedirs(os.path.join(t, "bin"))
        glab = os.path.join(t, "bin", "glab")
        with open(glab, "w") as f:
            f.write(FAKE_GLAB)
        os.chmod(glab, 0o755)
        self.mr_json = os.path.join(t, "mr.json")
        self.log = os.path.join(t, "posted.log")
        self.env = {**os.environ, "HOME": os.path.join(t, "home"), "GIT_CONFIG_GLOBAL": gitcfg,
                    "GIT_CONFIG_NOSYSTEM": "1", "PATH": os.path.join(t, "bin") + os.pathsep + os.environ["PATH"],
                    "STUB_MR_JSON": self.mr_json, "STUB_LOG": self.log}
        os.makedirs(self.env["HOME"])
        self.remote = os.path.join(t, "remote.git")
        self.proj = os.path.join(t, "proj")
        self.author = os.path.join(t, "author")
        self.sh("git", "init", "-q", "--bare", self.remote)
        self.sh("git", "clone", "-q", self.remote, self.author)
        self.write(self.author, "lib/a.dart", [f"l{i}" for i in range(1, 11)])
        self.commit(self.author, "base")
        self.sh("git", "push", "-q", "origin", "develop", cwd=self.author)
        self.sh("git", "checkout", "-q", "-b", "feat", cwd=self.author)
        lines = [f"l{i}" for i in range(1, 11)]
        lines[4:4] = ["BUG", "OTHER"]           # lignes 5 et 6, ajoutées par la MR
        self.write(self.author, "lib/a.dart", lines)
        self.commit(self.author, "feat: ajoute BUG et OTHER")
        self.sh("git", "push", "-q", "origin", "feat", cwd=self.author)
        self.h1 = self.rev(self.author, "HEAD")
        self.sh("git", "clone", "-q", self.remote, self.proj)
        self.set_mr(self.h1)

    # -- outils ------------------------------------------------------------------------------------
    def sh(self, *cmd, cwd=None, inp=None):
        p = subprocess.run(cmd, cwd=cwd, env=self.env, capture_output=True, text=True, input=inp)
        if p.returncode != 0:
            raise AssertionError(f"{' '.join(cmd)} : {p.stdout}{p.stderr}")
        return p.stdout

    def review(self, *args):
        return self.sh(REVIEW_SH, *args, cwd=self.proj)

    def write(self, repo, rel, lines):
        path = os.path.join(repo, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write("\n".join(lines) + "\n")

    def commit(self, repo, msg):
        self.sh("git", "add", "-A", cwd=repo)
        self.sh("git", "commit", "-q", "-m", msg, cwd=repo)

    def rev(self, repo, ref):
        return self.sh("git", "rev-parse", ref, cwd=repo).strip()

    def set_mr(self, head):
        develop = self.rev(self.author, "origin/develop")
        base = self.sh("git", "merge-base", head, develop, cwd=self.author).strip()
        with open(self.mr_json, "w") as f:
            json.dump({"source_branch": "feat", "target_branch": "develop", "title": "MR de test", "description": "",
                       "author": {"username": "auteur"}, "web_url": "https://forge.invalid/mr/7", "labels": [],
                       "sha": head, "diff_refs": {"base_sha": base, "start_sha": develop, "head_sha": head}}, f)
        return base, develop

    def state_path(self):
        return os.path.join(self.env["HOME"], ".cache", "gauntlet", "review", "mr-7", "review.json")

    def edit_state(self, fn):
        with open(self.state_path()) as f:
            s = json.load(f)
        fn(s)
        with open(self.state_path(), "w") as f:
            json.dump(s, f)

    # -- le scénario -------------------------------------------------------------------------------
    def test_post_after_rebase_lands_on_new_head(self):
        self.review("init", "!7")
        # Le gauntlet a sorti H1 (son worktree n'existe plus : c'est le cas qui a fait perdre une revue).
        self.edit_state(lambda s: s.update(gauntlet_head=self.h1))
        self.review("agent", "mr-7", "code", "running")
        d = os.path.dirname(self.state_path())
        with open(os.path.join(d, "findings_code.json"), "w") as f:
            json.dump({"findings": [
                {"severity": "critical", "title": "BUG", "problem": "p1", "file": "lib/a.dart", "line": 5},
                {"severity": "suggestion", "title": "OTHER", "problem": "p2", "file": "lib/a.dart", "line": 6}]}, f)
        self.review("agent", "mr-7", "code", "done")
        self.review("findings", "mr-7")
        with open(os.path.join(d, "findings.json")) as f:
            ids = {x["title"]: x["id"] for x in json.load(f)["findings"]}
        self.edit_state(lambda s: s.update(triage={
            ids["BUG"]: {"decision": "comment", "text": "Ce BUG casse l1."},
            ids["OTHER"]: {"decision": "comment", "text": "OTHER mérite un nom."}}))

        # L'auteur rebase sur develop (3 lignes en tête) et réécrit OTHER : H2, inconnu du clone du projet.
        self.sh("git", "checkout", "-q", "develop", cwd=self.author)
        self.write(self.author, "lib/a.dart", ["h1", "h2", "h3"] + [f"l{i}" for i in range(1, 11)])
        self.commit(self.author, "develop bouge")
        self.sh("git", "push", "-q", "origin", "develop", cwd=self.author)
        self.sh("git", "checkout", "-q", "feat", cwd=self.author)
        self.sh("git", "rebase", "-q", "develop", cwd=self.author)
        with open(os.path.join(self.author, "lib/a.dart")) as f:
            lines = f.read().splitlines()
        lines[lines.index("OTHER")] = "OTHER2"
        self.write(self.author, "lib/a.dart", lines)
        self.commit(self.author, "fix: renomme OTHER")
        self.sh("git", "push", "-q", "-f", "origin", "feat", cwd=self.author)
        h2 = self.rev(self.author, "HEAD")
        base2, start2 = self.set_mr(h2)
        self.assertNotEqual(subprocess.run(["git", "cat-file", "-e", f"{h2}^{{commit}}"], cwd=self.proj,
                                           env=self.env, capture_output=True).returncode, 0, "le clone du projet ne doit pas encore avoir H2")

        out = self.review("next", "mr-7")
        self.assertIn(f"la MR a bougé : {self.h1[:8]} → {h2[:8]}", out)
        self.assertIn(f"code a relu {self.h1[:8]}", out)
        nxt = json.loads(self.review("next", "mr-7", "--json"))
        self.assertEqual(nxt["head_sha"], h2)
        self.assertEqual(nxt["head_moved"], {"gauntlet": self.h1, "code": self.h1})

        preview = self.review("post", "mr-7")
        self.assertIn(f"tête de la MR (relue sur la forge) : {h2}", preview)
        self.assertIn(f"{ids['BUG']} (en ligne, ligne 8)", preview)
        self.assertIn(f"recalée : ligne 5 relue sur {self.h1[:8]} → ligne 8 sur {h2[:8]}", preview)
        self.assertIn(f"{ids['OTHER']} (commentaire général)", preview)
        self.assertIn(f"`lib/a.dart:6` (au commit {self.h1[:8]})", preview)
        self.assertFalse(os.path.exists(self.log), "l'aperçu ne poste rien")

        self.review("post", "mr-7", "--go")
        with open(self.log) as f:
            calls = [json.loads(l) for l in f]
        inline = [c for c in calls if c["stdin"]]
        self.assertEqual(len(inline), 1)
        pos = json.loads(inline[0]["stdin"])["position"]
        self.assertEqual(pos, {"position_type": "text", "base_sha": base2, "start_sha": start2, "head_sha": h2,
                               "new_path": "lib/a.dart", "old_path": "lib/a.dart", "new_line": 8})
        note = [c for c in calls if c["args"][:2] == ["mr", "note"]]
        self.assertEqual(len(note), 1)
        self.assertTrue(note[0]["args"][-1].startswith(f"`lib/a.dart:6` (au commit {self.h1[:8]}) — OTHER"))
        with open(self.state_path()) as f:
            s = json.load(f)
        self.assertEqual({p["id"]: (p["inline"], p["line"], p["head_sha"]) for p in s["posted"]},
                         {ids["BUG"]: (True, 8, h2), ids["OTHER"]: (False, None, h2)})
        self.assertEqual(s["diff_refs"]["head_sha"], h2)


class MapLine(unittest.TestCase):
    """map_line seul : insertions, suppressions et modifications avant, sur et après la ligne."""

    def test_cases(self):
        sys.path.insert(0, HERE)
        import review  # noqa: E402
        with tempfile.TemporaryDirectory() as t:
            env = {**os.environ, "GIT_CONFIG_GLOBAL": os.devnull, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@x.invalid",
                   "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@x.invalid"}
            run = lambda *c: subprocess.run(c, cwd=t, env=env, check=True, capture_output=True, text=True).stdout.strip()
            run("git", "init", "-q")

            def snap(lines):
                with open(os.path.join(t, "f"), "w") as f:
                    f.write("\n".join(lines) + "\n")
                run("git", "add", "f")
                run("git", "commit", "-q", "-m", "x")
                return run("git", "rev-parse", "HEAD")
            old = snap([f"l{i}" for i in range(1, 11)])
            new = snap(["top"] + [f"l{i}" for i in range(1, 4)] + [f"l{i}" for i in range(5, 7)] + ["L7"]
                       + [f"l{i}" for i in range(8, 11)] + ["end"])
            # top inséré (+1), l4 supprimée (-1), l7 modifiée
            self.assertEqual(review.map_line(t, old, new, "f", 1), 2)
            self.assertEqual(review.map_line(t, old, new, "f", 3), 4)
            self.assertIsNone(review.map_line(t, old, new, "f", 4))
            self.assertEqual(review.map_line(t, old, new, "f", 5), 5)
            self.assertIsNone(review.map_line(t, old, new, "f", 7))
            self.assertEqual(review.map_line(t, old, new, "f", 10), 10)
            self.assertIsNone(review.map_line(t, old, "0" * 40, "f", 3))


if __name__ == "__main__":
    unittest.main()
