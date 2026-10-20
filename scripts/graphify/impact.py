#!/usr/bin/env python3
"""impact.py — consommateurs hors package et ordre de lecture d'un diff, depuis le graphe graphify.

Voir ~/.claude/docs/superpowers/specs/2026-10-20-graphify-partage-design.md §3.1.
Écrit <out>/impact.json et <out>/impact.md ; stdout : "<status>\t<détail>". Sort en 0 sauf crash.
"""
import argparse, json, os, re, subprocess, sys

STRUCT = {"defines", "contains"}
H_CONS = "### Consommateurs hors package non touchés"
H_DEPS = "### Dépendances"
H_READ = "### Ordre de lecture du diff"


def git(w, *a):
    r = subprocess.run(["git", "-C", w, *a], capture_output=True, text=True)
    return r.returncode, r.stdout


def parse_pubspec(path):
    name, deps, sect = None, set(), None
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            if not line.startswith(" "):
                m = re.match(r"name:\s*([^\s#]+)", line)
                if m:
                    name = m.group(1).strip("'\"")
                m = re.match(r"(\w+):", line)
                sect = m.group(1) if m else None
            elif sect in ("dependencies", "dev_dependencies"):
                m = re.match(r"  ([A-Za-z0-9_]+)\s*:", line)
                if m:
                    deps.add(m.group(1))
    return name, deps


def parse_package_json(path):
    try:
        j = json.load(open(path, encoding="utf-8"))
    except Exception:
        return None, set()
    deps = set(j.get("dependencies", {})) | set(j.get("devDependencies", {}))
    return j.get("name"), deps


class Pkgs:
    """Package d'un fichier : pubspec.yaml le plus proche au-dessus, puis package.json, sinon '.'."""

    def __init__(self, wt):
        self.wt, self.cache, self.info = wt, {}, {}

    def of(self, rel):
        d = os.path.dirname(rel) or "."
        if d in self.cache:
            return self.cache[d]
        res = "."
        for marker in ("pubspec.yaml", "package.json"):
            cur = d
            while True:
                if os.path.isfile(os.path.join(self.wt, cur, marker)):
                    res = cur
                    break
                if cur in (".", "", "/"):
                    break
                cur = os.path.dirname(cur) or "."
            if res != ".":
                break
        self.cache[d] = res
        return res

    def meta(self, pkg):
        """(kind, name, deps) ; kind = 'dart' | 'node' | None."""
        if pkg in self.info:
            return self.info[pkg]
        p = os.path.join(self.wt, pkg)
        if os.path.isfile(os.path.join(p, "pubspec.yaml")):
            n, ds = parse_pubspec(os.path.join(p, "pubspec.yaml"))
            m = ("dart", n, ds)
        elif os.path.isfile(os.path.join(p, "package.json")):
            n, ds = parse_package_json(os.path.join(p, "package.json"))
            m = ("node", n, ds)
        else:
            m = (None, None, set())
        self.info[pkg] = m
        return m


class Graph:
    def __init__(self, data):
        if not isinstance(data, dict):
            raise ValueError("graph.json n'est pas un objet")
        self.data = data
        self.nodes = {n["id"]: n for n in data.get("nodes", []) if isinstance(n, dict) and "id" in n}
        self.adj = {i: [] for i in self.nodes}
        for lk in data.get("links", data.get("edges", [])):
            if lk.get("relation") in STRUCT:
                continue
            s, t = lk.get("source"), lk.get("target")
            if isinstance(s, dict): s = s.get("id")
            if isinstance(t, dict): t = t.get("id")
            if s in self.adj: self.adj[s].append((t, lk))
            if t in self.adj and t != s: self.adj[t].append((s, lk))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--worktree", required=True)
    ap.add_argument("--graph-dir", default="")
    ap.add_argument("--base", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--ignore-packages", default="core")
    ap.add_argument("--main", default="")
    a = ap.parse_args()

    W = os.path.abspath(a.worktree)
    gdir = os.path.join(W, a.graph_dir, "graphify-out")
    gjson = os.path.join(gdir, "graph.json")
    rel_graph = os.path.join(a.graph_dir, "graphify-out", "graph.json")
    os.makedirs(a.out, exist_ok=True)
    res = {"status": "ok", "reason": "", "graph": rel_graph, "built_at_commit": "", "base": "",
           "consumers": [], "dependencies": [], "reading_order": [], "not_in_graph": []}

    def finish(status, reason=""):
        res["status"], res["reason"] = status, reason
        with open(os.path.join(a.out, "impact.json"), "w", encoding="utf-8") as fh:
            json.dump(res, fh, ensure_ascii=False, indent=2)
        with open(os.path.join(a.out, "impact.md"), "w", encoding="utf-8") as fh:
            fh.write(render_md(res))
        n = sum(1 for c in res["consumers"] if not c["touched"])
        detail = reason if status in ("failed", "absent") else \
            "%d consommateur(s) hors package non touché(s), %d fichier(s) à lire" % (n, len(res["reading_order"]))
        if status == "absent":
            detail = ""
        print("%s\t%s" % (status, detail))

    if not os.path.isfile(gjson):
        return finish("absent")
    try:
        graph = Graph(json.load(open(gjson, encoding="utf-8")))
    except Exception as e:
        return finish("failed", "graph.json illisible (%s)" % e)
    res["built_at_commit"] = graph.data.get("built_at_commit", "") or ""

    # racine de scan, côté worktree
    rootf = os.path.join(gdir, ".graphify_root")
    if not os.path.isfile(rootf):
        return finish("failed", ".graphify_root manquant")
    raw = open(rootf, encoding="utf-8").read().strip()
    if not raw:
        return finish("failed", ".graphify_root vide")
    realW = os.path.realpath(W)
    if os.path.isabs(raw):
        scan = os.path.realpath(raw)
        mainco = os.path.realpath(a.main) if a.main else realW
        if scan == mainco or scan.startswith(mainco + os.sep):
            scan = os.path.join(realW, os.path.relpath(scan, mainco))
    else:
        scan = os.path.realpath(os.path.join(W, a.graph_dir, raw))
    scan_rel = os.path.relpath(scan, realW)
    if scan_rel == "." or scan_rel.startswith(".."):
        scan_rel = ""

    st = os.path.join(gdir, ".prepare_status")
    status = "ok"
    if os.path.isfile(st) and open(st, encoding="utf-8").read().strip() == "stale":
        status = "stale"

    # fichiers changés (arbre de travail compris) ∪ non suivis
    rc, mb = git(W, "merge-base", a.base, "HEAD")
    mb = mb.strip()
    if rc != 0 or not mb:
        rc, mb = git(W, "rev-parse", "--verify", "-q", a.base + "^{commit}")
        mb = mb.strip()
        if rc != 0 or not mb:
            return finish("failed", "base introuvable : %s" % a.base)
    res["base"] = mb
    changed = []
    for args in (("diff", "--name-only", "-z", mb), ("ls-files", "--others", "--exclude-standard", "-z")):
        rc, o = git(W, *args)
        if rc != 0:
            return finish("failed", "git %s a échoué" % args[0])
        for f in o.split("\0"):
            if f and f not in changed and "graphify-out" not in f.split("/"):
                changed.append(f)
    cset = set(changed)

    def file_of(sf):
        cands = [os.path.normpath(os.path.join(scan_rel, sf)), sf]
        for c in cands:
            if c in cset: return c
        for c in cands:
            if os.path.exists(os.path.join(W, c)): return c
        return cands[0]

    ignore = {x.strip() for x in a.ignore_packages.split(",") if x.strip()}
    pk = Pkgs(W)

    def ignored(pkg):
        kind, name, _ = pk.meta(pkg)
        return pkg in ignore or os.path.basename(pkg) in ignore or (name in ignore if name else False)

    def touched_nodes(g, only_missing_in=None):
        out = []
        for i, n in g.nodes.items():
            sf = n.get("source_file")
            if not sf or file_of(sf) not in cset: continue
            if only_missing_in is not None and i in only_missing_in.nodes: continue
            out.append(i)
        return out

    consumers, deps, seen_c, seen_d = [], [], set(), set()

    def collect(g, ids, removed):
        for i in ids:
            n = g.nodes[i]
            if str(n.get("label", "")).startswith("_"): continue
            tfile = file_of(n["source_file"]); tpkg = pk.of(tfile)
            for oid, lk in g.adj.get(i, []):
                o = g.nodes.get(oid)
                if not o or not o.get("source_file"): continue
                if str(o.get("label", "")).startswith("_"): continue
                ofile = file_of(o["source_file"]); opkg = pk.of(ofile)
                if opkg == tpkg or ignored(opkg): continue
                tk, tname, _ = pk.meta(tpkg); ok_, _, odeps = pk.meta(opkg)
                label_o, label_t = o.get("label", oid), n.get("label", i)
                if tk == "dart" and ok_ == "dart":
                    is_cons, classified = (tname in odeps), True
                else:
                    is_cons, classified = True, False
                if is_cons:
                    key = (ofile, label_o, label_t)
                    if key in seen_c: continue
                    seen_c.add(key)
                    loc = lk.get("source_location") if lk.get("source_file") and \
                        file_of(lk["source_file"]) == ofile else None
                    consumers.append({"package": opkg, "file": ofile, "symbol": label_o, "via": label_t,
                                      "via_file": tfile, "relation": lk.get("relation", ""),
                                      "location": loc or o.get("source_location", ""),
                                      "touched": ofile in cset, "classified": classified, "removed": removed})
                else:
                    key = (opkg, label_o, label_t)
                    if key in seen_d: continue
                    seen_d.add(key)
                    deps.append({"package": opkg, "symbol": label_o, "via": label_t})

    collect(graph, touched_nodes(graph), False)
    basef = os.path.join(gdir, "graph.base.json")
    if os.path.isfile(basef):
        try:
            base_g = Graph(json.load(open(basef, encoding="utf-8")))
            collect(base_g, touched_nodes(base_g, only_missing_in=graph), True)
        except Exception as e:
            sys.stderr.write("graph.base.json ignoré : %s\n" % e)

    # ordre de lecture : degré décroissant, puis hors graphe dans l'ordre du diff
    degree = {}
    for i, n in graph.nodes.items():
        sf = n.get("source_file")
        if not sf: continue
        f = file_of(sf)
        if f in cset:
            degree[f] = degree.get(f, 0) + len(graph.adj.get(i, []))
    order = {f: k for k, f in enumerate(changed)}
    in_graph = sorted(degree, key=lambda f: (-degree[f], order[f]))
    res["reading_order"] = [{"file": f, "degree": degree[f]} for f in in_graph]
    res["not_in_graph"] = [f for f in changed if f not in degree]
    res["consumers"] = sorted(consumers, key=lambda c: (c["package"], c["symbol"], c["via"], c["removed"]))
    res["dependencies"] = sorted(deps, key=lambda d: (d["package"], d["symbol"], d["via"]))
    finish(status)


def render_md(r):
    L = []
    if r["status"] == "stale":
        L += ["> ⚠ Graphe de la base (update en échec) : les symboles ajoutés par le diff manquent.", ""]
    elif r["status"] in ("absent", "failed"):
        L += ["> ⚠ Impact non calculé (%s)." % (r["reason"] or r["status"]), ""]
    L += [H_CONS, ""]
    rows = [c for c in r["consumers"] if not c["touched"]]
    if rows:
        L += ["| Package | Symbole | Via | Fichier:ligne |", "|---|---|---|---|"]
        for c in rows:
            via = c["via"] + (" (supprimé)" if c.get("removed") else "")
            L.append("| %s | %s | %s | %s:%s |" % (c["package"], c["symbol"], via, c["file"], c["location"]))
    else:
        L.append("—")
    L += ["", H_DEPS, ""]
    if r["dependencies"]:
        by = {}
        for d in r["dependencies"]:
            by.setdefault(d["package"], []).append("%s via %s" % (d["symbol"], d["via"]))
        for p in sorted(by):
            L.append("- %s : %s" % (p, ", ".join(by[p])))
    else:
        L.append("—")
    L += ["", H_READ, ""]
    if r["reading_order"]:
        for k, x in enumerate(r["reading_order"], 1):
            L.append("%d. %s (degré %d)" % (k, x["file"], x["degree"]))
    if r["not_in_graph"]:
        L += ["", "Hors graphe : " + ", ".join(r["not_in_graph"])]
    if not r["reading_order"] and not r["not_in_graph"]:
        L.append("—")
    return "\n".join(L) + "\n"


if __name__ == "__main__":
    main()
