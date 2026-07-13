#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import statistics
import time
from dataclasses import dataclass
from urllib import error, request


@dataclass(frozen=True)
class Probe:
    name: str
    method: str
    path: str
    body: dict | None = None


PROBES = (
    Probe("root", "GET", "/"),
    Probe("health", "GET", "/core/health"),
    Probe("latency", "GET", "/core/latency"),
    Probe(
        "voice_interpret",
        "POST",
        "/voice/interpret",
        {"transcript": "OSvoz abre terminal", "language": "es"},
    ),
)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Measure local OSvoz backend latency for hot-path routes."
    )
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    parser.add_argument("--samples", type=int, default=10)
    parser.add_argument("--timeout", type=float, default=2.0)
    args = parser.parse_args()

    if args.samples < 1:
        parser.error("--samples must be at least 1")

    failures = 0
    print(f"base_url={args.base_url} samples={args.samples}")
    for probe in PROBES:
        values: list[float] = []
        for _ in range(args.samples):
            try:
                values.append(_measure(args.base_url, probe, args.timeout))
            except (OSError, error.URLError, TimeoutError) as exc:
                failures += 1
                print(f"{probe.name} error={exc}")
        if values:
            print(_summary(probe.name, values))
    return 1 if failures else 0


def _measure(base_url: str, probe: Probe, timeout: float) -> float:
    body = None
    headers = {}
    if probe.body is not None:
        body = json.dumps(probe.body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = request.Request(
        f"{base_url}{probe.path}",
        data=body,
        headers=headers,
        method=probe.method,
    )
    started = time.perf_counter()
    with request.urlopen(req, timeout=timeout) as response:
        response.read()
    return (time.perf_counter() - started) * 1000


def _summary(name: str, values: list[float]) -> str:
    ordered = sorted(values)
    p50 = statistics.median(ordered)
    p95 = _percentile(ordered, 95)
    return (
        f"{name} count={len(values)} "
        f"min_ms={ordered[0]:.2f} p50_ms={p50:.2f} "
        f"p95_ms={p95:.2f} max_ms={ordered[-1]:.2f}"
    )


def _percentile(values: list[float], percentile: int) -> float:
    index = (len(values) - 1) * (percentile / 100)
    lower = int(index)
    upper = min(lower + 1, len(values) - 1)
    if lower == upper:
        return values[lower]
    weight = index - lower
    return values[lower] * (1 - weight) + values[upper] * weight


if __name__ == "__main__":
    raise SystemExit(main())
