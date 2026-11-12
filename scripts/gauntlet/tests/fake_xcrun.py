#!/usr/bin/env python3
"""fake_xcrun.py — `xcrun simctl` simulé pour les tests de sim.sh et review.sh : appareils dans $FAKE_SIMS (JSON).

Couvre ce dont sim.sh et review.py se servent : list devices available -j, clone, create, bootstatus -b,
shutdown, delete. Chaque appel est journalisé dans $FAKE_SIMS.log.
"""
import json
import os
import sys
import uuid

path = os.environ["FAKE_SIMS"]
with open(path) as f:
    devices = json.load(f)
with open(path + ".log", "a") as f:
    f.write(" ".join(sys.argv[1:]) + "\n")


def find(key):
    return next((d for d in devices if key in (d["name"], d["udid"])), None)


def save():
    with open(path, "w") as f:
        json.dump(devices, f)


args = sys.argv[1:]
if args[:1] != ["simctl"]:
    sys.exit(f"fake_xcrun: {args}")
cmd, rest = args[1], args[2:]
if cmd == "list":
    by_rt = {}
    for d in devices:
        by_rt.setdefault(d["runtime"], []).append({k: d[k] for k in ("name", "udid", "state", "deviceTypeIdentifier")})
    print(json.dumps({"devices": by_rt}))
elif cmd in ("clone", "create"):
    # clone <source> <nom> ; create <nom> <type> <runtime>
    src = find(rest[0]) if cmd == "clone" else None
    if cmd == "clone" and not src:
        sys.exit("clone: source inconnue")
    name = rest[1] if cmd == "clone" else rest[0]
    new = {"name": name, "udid": str(uuid.uuid4()).upper(), "state": "Shutdown",
           "deviceTypeIdentifier": src["deviceTypeIdentifier"] if src else rest[1],
           "runtime": src["runtime"] if src else rest[2]}
    devices.append(new)
    save()
    print(new["udid"])
elif cmd == "bootstatus":
    d = find(rest[0])
    if not d:
        sys.exit(1)
    d["state"] = "Booted"
    save()
elif cmd == "shutdown":
    d = find(rest[0])
    if d:
        d["state"] = "Shutdown"
        save()
elif cmd == "delete":
    d = find(rest[0])
    if not d:
        sys.exit(1)
    devices.remove(d)
    save()
else:
    sys.exit(f"fake_xcrun: simctl {cmd} non simulé")
