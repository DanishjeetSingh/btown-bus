#!/usr/bin/env python3
"""Records the Bloomington Transit and IU Campus Bus live feeds (ETA Spot), to build better arrival predictions later.

Everything the feeds say is kept raw, so any future model can be trained from it without collecting again:
  - every bus (position, next and last stop, the feed's own short-range predictions), every 15 s
  - every stop's predicted arrivals, every 60 s
  - routes, stops and patterns, every 6 hours (saved only when they change)

Raw data goes to DATA_DIR/YYYY-MM-DD/HH-<kind>.jsonl (local time), xz-compressed once each hour is over.
Raw data stops being saved once DATA_DIR reaches BTOWN_BUDGET_GB, so a home-folder quota never fills up. The one
part that can never be recovered later, the moment each bus leaves each stop, is always written to EVENTS_DIR.

Runs until killed. A second copy exits straight away, so cron can start it every few minutes as a watchdog.
Standard library only. `--once` does a single round and exits, for testing.
"""
import argparse
import fcntl
import gzip
import hashlib
import json
import lzma
import os
import shutil
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

FEEDS = {
    "bt": "https://bloomingtontransit.etaspot.net/service.php",
    "iu": "https://iucbs.etaspot.net/service.php",
}
DATA_DIR = Path(os.environ.get("BTOWN_DATA", str(Path.home() / "btown-bus-collector" / "data")))
EVENTS_DIR = Path(os.environ.get("BTOWN_EVENTS", str(Path.home() / "btown-bus-collector" / "events")))
BUDGET_BYTES = float(os.environ.get("BTOWN_BUDGET_GB", "2")) * 1e9
LOCK = Path("/tmp/btown-bus-collector.lock")  # local disk; file locks on network drives aren't reliable
LOCAL = ZoneInfo("America/Indiana/Indianapolis")

VEHICLES_EVERY = 15
ETAS_EVERY = 60
STATIC_EVERY = 6 * 60 * 60
# Bloomington Transit rejects a request listing all ~530 stops (the URL gets too long), so ask in batches.
STOP_BATCH = 100
USER_AGENT = "btown-bus-collector (github.com/DanishjeetSingh/btown-bus)"


def log(message):
    print(f"{datetime.now(LOCAL):%Y-%m-%d %H:%M:%S} {message}", flush=True)


def fetch(agency, service, **params):
    query = urllib.parse.urlencode({"service": service, **params})
    request = urllib.request.Request(f"{FEEDS[agency]}?{query}", headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.loads(response.read())


class Store:
    """Appends records to this hour's file of each kind, and compresses files from earlier hours."""

    def __init__(self):
        self.full = False

    def check_budget(self):
        used = sum(path.stat().st_size for path in DATA_DIR.rglob("*") if path.is_file()) if DATA_DIR.exists() else 0
        full = used >= BUDGET_BYTES
        if full and not self.full:
            log(f"raw data reached {used / 1e9:.2f} GB; no longer saving raw snapshots (stop events continue)")
        self.full = full

    def write(self, kind, record):
        if self.full:
            return
        now = datetime.now(LOCAL)
        folder = DATA_DIR / f"{now:%Y-%m-%d}"
        folder.mkdir(parents=True, exist_ok=True)
        with open(folder / f"{now:%H}-{kind}.jsonl", "a") as file:
            file.write(json.dumps(record, separators=(",", ":")) + "\n")

    def compress_finished_hours(self):
        current = datetime.now(LOCAL).strftime("%Y-%m-%d/%H")
        for path in DATA_DIR.glob("*/*.jsonl"):
            if f"{path.parent.name}/{path.name[:2]}" == current:
                continue
            with open(path, "rb") as source, lzma.open(f"{path}.xz", "wb") as target:
                shutil.copyfileobj(source, target)
            path.unlink()
        self.check_budget()


class Events:
    """Each time a bus's last stop changes, it has just left that stop: the ground truth predictions are graded on."""

    def __init__(self):
        self.last_stop = {}

    def update(self, agency, vehicles, fetched_at):
        rows = []
        for vehicle in vehicles:
            key = (agency, str(vehicle.get("equipmentID")))
            stop = vehicle.get("lastStopID")
            if not stop or str(stop) == "0":
                continue
            previous = self.last_stop.get(key)
            self.last_stop[key] = stop
            if previous is not None and previous != stop:
                rows.append({
                    "t": fetched_at, "receive": vehicle.get("receiveTime"), "agency": agency,
                    "vehicle": vehicle.get("equipmentID"), "route": vehicle.get("routeID"),
                    "pattern": vehicle.get("patternID"), "trip": vehicle.get("tripID"),
                    "block": vehicle.get("blockID"), "left": stop, "next": vehicle.get("nextStopID"),
                    "onSchedule": vehicle.get("onSchedule"), "load": vehicle.get("load"),
                })
        if rows:
            EVENTS_DIR.mkdir(parents=True, exist_ok=True)
            with gzip.open(EVENTS_DIR / f"{datetime.now(LOCAL):%Y-%m-%d}-left-stop.jsonl.gz", "at") as file:
                for row in rows:
                    file.write(json.dumps(row, separators=(",", ":")) + "\n")
        return len(rows)


class Collector:
    def __init__(self):
        self.store = Store()
        self.events = Events()
        self.stop_ids = {agency: [] for agency in FEEDS}
        self.last_vehicles = {}
        self.static_hashes = {}
        self.counts = {"vehicles": 0, "etas": 0, "events": 0, "errors": 0}

    def static(self):
        for agency in FEEDS:
            for service in ("get_routes", "get_stops", "get_patterns"):
                try:
                    data = fetch(agency, service)
                except Exception as error:
                    self.failed(agency, service, error)
                    continue
                if service == "get_stops":
                    self.stop_ids[agency] = sorted({str(stop["id"]) for stop in data.get("get_stops", [])})
                text = json.dumps(data, sort_keys=True, separators=(",", ":"))
                digest = hashlib.sha256(text.encode()).hexdigest()
                if self.static_hashes.get((agency, service)) == digest:
                    continue
                self.static_hashes[(agency, service)] = digest
                folder = DATA_DIR / "static"
                folder.mkdir(parents=True, exist_ok=True)
                with gzip.open(folder / f"{agency}-{service}-{datetime.now(LOCAL):%Y-%m-%dT%H%M}.json.gz", "wt") as file:
                    file.write(text)

    def vehicles(self):
        for agency in FEEDS:
            try:
                data = fetch(agency, "get_vehicles", includeETAData="1", orderedETAArray="1")
            except Exception as error:
                self.failed(agency, "get_vehicles", error)
                continue
            fetched_at = time.time()
            vehicles = data.get("get_vehicles", [])
            self.counts["events"] += self.events.update(agency, vehicles, fetched_at)
            # The feed often hasn't changed since the last ask; don't store the same snapshot twice.
            text = json.dumps(vehicles, sort_keys=True)
            if self.last_vehicles.get(agency) == text:
                continue
            self.last_vehicles[agency] = text
            self.store.write("vehicles", {"t": fetched_at, "agency": agency, "vehicles": vehicles})
            self.counts["vehicles"] += 1

    def etas(self):
        for agency, ids in self.stop_ids.items():
            stops = []
            for start in range(0, len(ids), STOP_BATCH):
                try:
                    data = fetch(agency, "get_stop_etas", stopIDs=",".join(ids[start:start + STOP_BATCH]))
                except Exception as error:
                    self.failed(agency, "get_stop_etas", error)
                    continue
                stops += data.get("get_stop_etas", [])
            if stops:
                self.store.write("etas", {"t": time.time(), "agency": agency, "stops": stops})
                self.counts["etas"] += 1

    def failed(self, agency, service, error):
        self.counts["errors"] += 1
        # One line per failure is plenty; the feeds blip now and then.
        log(f"{agency} {service} failed: {error}")

    def run(self, once=False):
        log(f"started, saving to {DATA_DIR} and {EVENTS_DIR}")
        self.store.check_budget()
        next_static = next_vehicles = next_etas = 0.0
        hour = datetime.now(LOCAL).hour
        while True:
            now = time.time()
            if now >= next_static:
                self.static()
                next_static = now + STATIC_EVERY
            if now >= next_vehicles:
                self.vehicles()
                next_vehicles = max(next_vehicles + VEHICLES_EVERY, now + 1)
            if now >= next_etas:
                self.etas()
                next_etas = max(next_etas + ETAS_EVERY, now + 1)
            if once:
                self.store.compress_finished_hours()
                log(f"one round done: {self.counts}")
                return
            if datetime.now(LOCAL).hour != hour:
                hour = datetime.now(LOCAL).hour
                self.store.compress_finished_hours()
                log(f"last hour: {self.counts}")
                self.counts = dict.fromkeys(self.counts, 0)
            time.sleep(max(0.5, min(next_vehicles, next_etas, next_static) - time.time()))


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--once", action="store_true", help="do one round and exit")
    args = parser.parse_args()
    lock = open(LOCK, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return  # already running
    Collector().run(once=args.once)


if __name__ == "__main__":
    sys.exit(main())
