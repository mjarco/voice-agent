#!/usr/bin/env python3
"""The slowest test files of the suite (#423).

    flutter test --reporter json | scripts/test-times.py [--top N]
    make test-times [TOP=N]

Reads the JSON reporter's events from stdin and prints, per test file, the
time from its first test start to its last test end (its own wall time, which
overlaps with other files when tests run concurrently), the number of tests,
and the slowest test in it. Exits with the test run's own status: 1 when any
test failed or errored, else 0.
"""

import argparse
import json
import os
import sys


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, default=20)
    args = ap.parse_args()

    suites: dict[int, str] = {}
    tests: dict[int, tuple[int, str, int]] = {}  # id -> (suite, name, start ms)
    files: dict[str, dict] = {}
    failed = False
    failures: list[str] = []
    total_ms = 0

    for line in sys.stdin:
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        kind = ev.get("type")
        if kind == "suite":
            path = ev["suite"].get("path") or "?"
            suites[ev["suite"]["id"]] = os.path.relpath(path) if os.path.isabs(path) else path
        elif kind == "testStart":
            t = ev["test"]
            if t.get("url") is None and t["name"].startswith("loading "):
                continue  # the loader pseudo-test
            tests[t["id"]] = (t["suiteID"], t["name"], ev["time"])
        elif kind == "testDone":
            if ev.get("hidden"):
                continue
            start = tests.get(ev["testID"])
            if ev.get("result") != "success":
                failed = True
                where = suites.get(start[0], "?") if start else "?"
                failures.append(f"{ev.get('result')}: {where} — {start[1] if start else ev['testID']}")
            if start is None:
                continue
            suite_id, name, t0 = start
            path = suites.get(suite_id, "?")
            f = files.setdefault(path, {"first": t0, "last": t0, "n": 0, "slow": (0, "")})
            f["first"] = min(f["first"], t0)
            f["last"] = max(f["last"], ev["time"])
            f["n"] += 1
            took = ev["time"] - t0
            if took > f["slow"][0]:
                f["slow"] = (took, name)
        elif kind == "error":
            failed = True
        elif kind == "done":
            total_ms = ev["time"]
            if ev.get("success") is False:
                failed = True

    rows = sorted(files.items(), key=lambda kv: kv[1]["last"] - kv[1]["first"], reverse=True)
    n_tests = sum(f["n"] for f in files.values())
    print(f"{len(files)} files, {n_tests} tests, run {total_ms / 1000:.1f} s")
    print(f"{'file s':>7} {'tests':>5} {'slowest s':>9}  file — slowest test")
    for path, f in rows[: args.top]:
        wall = (f["last"] - f["first"]) / 1000
        slow_s, slow_name = f["slow"]
        print(f"{wall:7.1f} {f['n']:5d} {slow_s / 1000:9.1f}  {path} — {slow_name[:70]}")
    for f in failures:
        print(f"FAILED {f}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
