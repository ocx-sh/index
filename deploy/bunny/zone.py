#!/usr/bin/env python3
"""Keep the index.ocx.sh pull zone's cache setting in git instead of in dashboard clicks.

The wire files (config.json, c/, p/) must reach a client fresh: README, "Cache Rule".
A Bunny pull zone caches at the edge for its own lifetime whatever Cache-Control the
response carries, so the zone itself has to be told not to.

  python3 deploy/bunny/zone.py plan     # diff the live settings against ZONE_SETTINGS
  python3 deploy/bunny/zone.py apply    # push the differing settings, read them back, purge
  python3 deploy/bunny/zone.py verify   # probe the live edge for cached answers; needs no key

Env: BUNNY_API_KEY (account key, NOT a storage zone password; local only, never a CI secret),
     BUNNY_PULLZONE_ID (default 6855500), BUNNY_PUBLIC_HOST (default index.ocx.sh).
"""
import json
import os
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
import sys
import urllib.error
import urllib.request

ZONE = os.environ.get("BUNNY_PULLZONE_ID", "6855500")
PUBLIC = os.environ.get("BUNNY_PUBLIC_HOST", "index.ocx.sh")
API = f"https://api.bunny.net/pullzone/{ZONE}"

EDGE_TTL = 10  # seconds a wire file may sit at the edge after a deploy replaced it

# Anything not listed is left exactly as the dashboard has it.
ZONE_SETTINGS = {
    # Edge cache lifetime in seconds; 0 is the dashboard's "Override: do not cache", -1 respects
    # the origin's Cache-Control. Storage sends none, so before this a package root sat at the
    # edge for days: on 2026-11-15 ocx still listed ocx/cli 0.6.6 after 0.6.7 was deployed.
    # Not 0: a BYPASS answer comes straight from storage, which ignores If-None-Match, so the
    # edge stopped answering 304 and every client conditional GET became a full 200 (smoke
    # test, 2026-11-15). Only a cached copy gets 304s, so the edge caches, briefly.
    # ponytail: one short TTL for every path; cache /p/*/o/sha256/* (immutable) longer with an
    # edge rule if storage load ever matters.
    "CacheControlMaxAgeOverride": EDGE_TTL,
}

# Wire paths every deploy has; `verify` asks for each this many times.
PROBES = ["/config.json", "/c/index.json"]
PROBE_ROUNDS = 5


def call(method, url, data=None):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(
        url,
        data=body,
        method=method,
        headers={"AccessKey": os.environ["BUNNY_API_KEY"], "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:300]


def zone_diff():
    """[(key, current, desired)] for every ZONE_SETTINGS key that differs."""
    status, zone = call("GET", API)
    if not isinstance(zone, dict):
        sys.exit(f"could not read pull zone {ZONE}: HTTP {status} {zone}")
    missing = [k for k in ZONE_SETTINGS if k not in zone]
    if missing:
        # A renamed API field must not read as "no drift" forever.
        sys.exit(f"pull zone has no such field(s): {', '.join(missing)}")
    return [(k, zone[k], v) for k, v in ZONE_SETTINGS.items() if zone[k] != v]


def show(diff):
    for key, current, desired in diff:
        print(f"  {key:28} {current!s:>8} -> {desired}")


def cmd_plan():
    diff = zone_diff()
    show(diff) if diff else print("  zone settings already match")
    return 0


def cmd_apply():
    diff = zone_diff()
    if not diff:
        print("  zone settings already match, nothing to apply")
        return 0
    show(diff)
    status, resp = call("POST", API, {k: desired for k, _, desired in diff})
    if status not in (200, 201, 204):
        sys.exit(f"update rejected: HTTP {status} {resp}")
    # The API answers 2xx for a value it clamped or ignored: only a read-back proves the write.
    left = zone_diff()
    if left:
        show(left)
        sys.exit("some settings did not take effect")
    print("  all settings confirmed")
    # Copies cached under the old lifetime stay until they expire or are dropped.
    status, _ = call("POST", f"{API}/purgeCache")
    if status not in (200, 204):
        sys.exit(f"purgeCache failed: HTTP {status}")
    print("  edge cache dropped")
    return 0


def cmd_verify():
    """Fails when the edge answers a wire path from a copy older than EDGE_TTL."""
    bad = 0
    for path in PROBES:
        states = []
        for _ in range(PROBE_ROUNDS):
            # ocx sends no Accept-Encoding; that variant is the one that went stale.
            req = urllib.request.Request(f"https://{PUBLIC}{path}", headers={"Accept-Encoding": "identity"})
            with urllib.request.urlopen(req, timeout=30) as r:
                r.read()
                state = r.headers.get("CDN-Cache", "<absent>")
                # CDN-CachedAt is "MM/DD/YYYY HH:MM:SS" UTC; its distance to Date is the copy's age.
                cached_at = datetime.strptime(r.headers["CDN-CachedAt"], "%m/%d/%Y %H:%M:%S")
                age = (parsedate_to_datetime(r.headers["Date"]) - cached_at.replace(tzinfo=timezone.utc)).total_seconds()
                states.append((state, age))
        old = [s for s, age in states if s == "STALE" or age > EDGE_TTL + 2]
        bad += bool(old)
        shown = " ".join(f"{s}@{age:.0f}s" for s, age in states)
        print(f"  [{'XX' if old else 'OK'}] {path:16} CDN-Cache: {shown}")
    print(f"  {'edge serves wire files older than the TTL' if bad else f'no answer older than {EDGE_TTL}s'}")
    return 1 if bad else 0


if __name__ == "__main__":
    commands = {"plan": cmd_plan, "apply": cmd_apply, "verify": cmd_verify}
    command = commands.get(sys.argv[1] if len(sys.argv) > 1 else "plan")
    if command is None:
        print(__doc__)
        sys.exit(2)
    sys.exit(command())
