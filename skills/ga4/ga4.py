#!/usr/bin/env python3
"""GA4 Admin from the command line: list properties, custom dimensions and metrics, and create them.

    ga4.py whoami                                   token check + accounts and properties visible
    ga4.py defs <property>                          custom dimensions and metrics of a property
    ga4.py add-dim <property> <param> <display> [--scope EVENT|USER] [--desc TEXT] [--dry-run]
    ga4.py add-metric <property> <param> <display> [--unit STANDARD|SECONDS|...] [--desc TEXT] [--dry-run]

<property> is a numeric property id, or a project key of ~/.claude-local/ga4.ini (`<key> = <property id>`).
Creating something that already exists is not an error (ALREADY_EXISTS is reported and skipped).
Auth: the application default credentials of gcloud, which must carry the analytics.edit scope; when they
do not, the script prints the one command that fixes it (an interactive Google sign-in: the user runs it).
Standard library only.
"""
import argparse
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

API = "https://analyticsadmin.googleapis.com/v1alpha"
LOCAL_INI = os.path.expanduser("~/.claude-local/ga4.ini")
CLIENT_FILE = os.path.expanduser("~/.config/gcloud/ga-client.json")
SCOPES = ",".join([
    "https://www.googleapis.com/auth/analytics.edit",
    "https://www.googleapis.com/auth/analytics.readonly",
    "https://www.googleapis.com/auth/cloud-platform",
])
REAUTH = (
    f'gcloud auth application-default login --client-id-file="{CLIENT_FILE}" --scopes={SCOPES}'
    if os.path.exists(CLIENT_FILE)
    else f"gcloud auth application-default login --scopes={SCOPES}"
)


def fail(message: str, code: int = 1) -> None:
    print(f"ga4: {message}", file=sys.stderr)
    sys.exit(code)


def token() -> str:
    try:
        out = subprocess.run(
            ["gcloud", "auth", "application-default", "print-access-token"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as e:
        fail(f"no application default credentials ({e}). Run once:\n  {REAUTH}", 3)
    return out.splitlines()[-1]


def call(method: str, path: str, body: dict | None = None) -> dict:
    req = urllib.request.Request(
        f"{API}/{path}", method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as e:
        payload = json.loads(e.read() or b"{}").get("error", {})
        status, message = payload.get("status", ""), payload.get("message", str(e))
        if e.code in (401, 403) and ("scope" in message.lower() or e.code == 401):
            fail(f"{message}\nThe credentials lack the Analytics scope. Run once (Google sign-in):\n  {REAUTH}", 3)
        return {"_error": status or str(e.code), "_message": message}


def property_id(ref: str) -> str:
    if ref.isdigit():
        return ref
    if os.path.exists(LOCAL_INI):
        for line in open(LOCAL_INI, encoding="utf-8"):
            key, _, value = line.partition("=")
            if key.strip() == ref and value.strip():
                return value.split("#")[0].strip()
    fail(f"unknown property {ref!r}: give its numeric id, or add `{ref} = <id>` to {LOCAL_INI} (ga4.py whoami lists them)")


def paged(path: str, key: str) -> list:
    items, token_ = [], ""
    while True:
        sep = "&" if "?" in path else "?"
        page = call("GET", f"{path}{sep}pageSize=200" + (f"&pageToken={token_}" if token_ else ""))
        if "_error" in page:
            fail(f"{page['_error']}: {page['_message']}")
        items += page.get(key, [])
        token_ = page.get("nextPageToken", "")
        if not token_:
            return items


def whoami(_args) -> None:
    for account in paged("accountSummaries", "accountSummaries"):
        print(f"{account.get('displayName')} ({account.get('account')})")
        for prop in account.get("propertySummaries", []):
            print(f"  {prop['property'].split('/')[-1]:>12}  {prop.get('displayName')}")


def defs(args) -> None:
    prop = f"properties/{property_id(args.property)}"
    for d in sorted(paged(f"{prop}/customDimensions", "customDimensions"), key=lambda d: d["parameterName"]):
        print(f"dim     {d.get('scope', ''):<6} {d['parameterName']:<28} {d.get('displayName', '')}")
    for m in sorted(paged(f"{prop}/customMetrics", "customMetrics"), key=lambda m: m["parameterName"]):
        print(f"metric  {m.get('measurementUnit', ''):<8} {m['parameterName']:<26} {m.get('displayName', '')}")


def create(args, kind: str, body: dict) -> None:
    prop = f"properties/{property_id(args.property)}"
    label = f"{kind} {body['parameterName']} on {prop}"
    if args.dry_run:
        print(f"[dry-run] would create {label}: {json.dumps(body, ensure_ascii=False)}")
        return
    result = call("POST", f"{prop}/{kind}", body)
    if result.get("_error") == "ALREADY_EXISTS":
        print(f"already exists: {label}")
    elif "_error" in result:
        fail(f"{label}: {result['_error']}: {result['_message']}")
    else:
        print(f"created: {label} ({result.get('name')})")


def add_dim(args) -> None:
    create(args, "customDimensions", {
        "parameterName": args.param, "displayName": args.display, "scope": args.scope,
        "description": args.desc, "disallowAdsPersonalization": False,
    })


def add_metric(args) -> None:
    create(args, "customMetrics", {
        "parameterName": args.param, "displayName": args.display, "scope": "EVENT",
        "measurementUnit": args.unit, "description": args.desc,
    })


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("whoami").set_defaults(func=whoami)
    p = sub.add_parser("defs")
    p.add_argument("property")
    p.set_defaults(func=defs)
    for name, func in (("add-dim", add_dim), ("add-metric", add_metric)):
        p = sub.add_parser(name)
        p.add_argument("property")
        p.add_argument("param")
        p.add_argument("display")
        p.add_argument("--desc", default="")
        p.add_argument("--dry-run", action="store_true")
        if name == "add-dim":
            p.add_argument("--scope", default="EVENT", choices=["EVENT", "USER"])
        else:
            p.add_argument("--unit", default="STANDARD")
        p.set_defaults(func=func)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
