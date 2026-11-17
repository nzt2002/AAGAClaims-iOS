#!/usr/bin/env python3
"""Adds a TestFlight build to the internal beta groups, once Apple has finished processing it.

  Tools/assign-build.py <build number> [version]

Groups don't get new builds by themselves, so without this nobody sees an upload. Group names come from
ASC_BETA_GROUPS in ~/.appstoreconnect/aaga-claims.env (comma separated; default "Platform Preview,testers").
Uses the same App Store Connect API key as release.sh.
"""
import base64, json, os, subprocess, sys, time

BUNDLE = "com.accurateadjustmentsga.claims"
BASE = "https://api.appstoreconnect.apple.com"


def load_env(path):
    env = {}
    for line in open(path):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            env[k] = v.strip().strip('"')
    return env


def token(key_id, issuer):
    b = lambda x: base64.urlsafe_b64encode(x).rstrip(b"=")
    head = b(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    body = b(json.dumps({"iss": issuer, "exp": int(time.time()) + 1100, "aud": "appstoreconnect-v1"}).encode())
    signing = head + b"." + body
    key = os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{key_id}.p8")
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key], input=signing, capture_output=True, check=True).stdout
    i = 2 if der[1] < 0x80 else 3
    rl = der[i + 1]; r = der[i + 2:i + 2 + rl]
    j = i + 2 + rl; sl = der[j + 1]; s = der[j + 2:j + 2 + sl]
    raw = r.lstrip(b"\0").rjust(32, b"\0") + s.lstrip(b"\0").rjust(32, b"\0")
    return (signing + b"." + b(raw)).decode()


def call(tok, path, method="GET", payload=None):
    cmd = ["curl", "-gsS", "-X", method, "-H", f"Authorization: Bearer {tok}", "-w", "\n%{http_code}"]
    if payload is not None:
        cmd += ["-H", "Content-Type: application/json", "-d", json.dumps(payload)]
    out = subprocess.run(cmd + [BASE + path], capture_output=True, text=True, check=True).stdout
    text, code = out.rsplit("\n", 1)
    return int(code), (json.loads(text) if text.strip() else {})


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    number = sys.argv[1]
    env = load_env(os.path.expanduser("~/.appstoreconnect/aaga-claims.env"))
    tok = token(env["ASC_KEY_ID"], env["ASC_ISSUER_ID"])
    names = os.environ.get("ASC_BETA_GROUPS") or env.get("ASC_BETA_GROUPS", "Platform Preview,testers")
    wanted = [g.strip() for g in names.split(",") if g.strip()]

    _, apps = call(tok, f"/v1/apps?filter[bundleId]={BUNDLE}")
    app = apps["data"][0]["id"]

    build = None
    for _ in range(80):  # up to about 20 minutes
        _, builds = call(tok, f"/v1/builds?filter[app]={app}&filter[version]={number}&sort=-uploadedDate&limit=1")
        if builds.get("data"):
            build = builds["data"][0]
            if build["attributes"]["processingState"] == "VALID":
                break
            if build["attributes"]["processingState"] in ("FAILED", "INVALID"):
                sys.exit(f"Build {number} failed processing.")
        time.sleep(15)
    else:
        sys.exit(f"Build {number} is still processing; run this again later: Tools/assign-build.py {number}")

    _, groups = call(tok, f"/v1/apps/{app}/betaGroups?limit=50")
    by_name = {g["attributes"]["name"]: g["id"] for g in groups["data"]}
    for name in wanted:
        if name not in by_name:
            print(f"  no beta group called {name!r}; skipped")
            continue
        code, _ = call(tok, f"/v1/betaGroups/{by_name[name]}/relationships/builds", "POST",
                       {"data": [{"type": "builds", "id": build["id"]}]})
        print(f"  {name}: {'added' if code in (200, 204) else f'failed ({code})'}")


main()
