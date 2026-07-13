import argparse
import json
import math
import random
import statistics
import time

from ml_provider import MLProviderManager


DEFAULT_ITERATIONS = 1000
DEFAULT_FEATURE_COUNT = 64


class MLProviderEvaluator:
    @staticmethod
    def run(
        iterations: int = DEFAULT_ITERATIONS,
        feature_count: int = DEFAULT_FEATURE_COUNT,
        seed: int = 42,
    ) -> dict:
        provider_status = MLProviderManager.status()
        provider = provider_status["provider"]
        random_source = random.Random(seed)
        base_features = [
            random_source.uniform(-1.0, 1.0) for _ in range(feature_count)
        ]

        cold_started = time.perf_counter()
        cold_result = MLProviderManager.audio_embedding(base_features)
        cold_latency_ms = (time.perf_counter() - cold_started) * 1000
        if not cold_result.get("success"):
            return {
                "success": False,
                "provider": provider,
                "compatibility": provider_status.get("frameworks"),
                "operational": provider_status.get("operational"),
                "error": cold_result.get("error", "provider_failed"),
                "message": cold_result.get("message", "Provider failed."),
            }

        repeated = [
            MLProviderManager.audio_embedding(base_features)["embedding"]
            for _ in range(5)
        ]
        deterministic = all(embedding == repeated[0] for embedding in repeated)

        latencies_ms = []
        failures = []
        embedding_dimensions = len(cold_result["embedding"])
        for index in range(iterations):
            features = [
                random_source.uniform(-1.0, 1.0)
                for _ in range(1 + (index % max(feature_count, 1)))
            ]
            started = time.perf_counter()
            result = MLProviderManager.audio_embedding(features)
            latencies_ms.append((time.perf_counter() - started) * 1000)
            if not result.get("success"):
                failures.append(
                    {
                        "index": index,
                        "error": result.get("error", "unknown_error"),
                    }
                )
                continue
            embedding = result["embedding"]
            if len(embedding) != embedding_dimensions:
                failures.append(
                    {
                        "index": index,
                        "error": "embedding_dimension_changed",
                    }
                )
            elif not all(math.isfinite(float(value)) for value in embedding):
                failures.append(
                    {
                        "index": index,
                        "error": "embedding_contains_non_finite_value",
                    }
                )

        sorted_latencies = sorted(latencies_ms)
        return {
            "success": not failures and deterministic,
            "provider": provider,
            "compatibility": provider_status["frameworks"],
            "stress": {
                "iterations": iterations,
                "failures": failures[:10],
                "failure_count": len(failures),
                "deterministic_repeated_input": deterministic,
                "embedding_dimensions": embedding_dimensions,
            },
            "latency_ms": {
                "cold_start": round(cold_latency_ms, 4),
                "min": round(sorted_latencies[0], 4),
                "mean": round(statistics.fmean(sorted_latencies), 4),
                "p50": round(_percentile(sorted_latencies, 50), 4),
                "p95": round(_percentile(sorted_latencies, 95), 4),
                "p99": round(_percentile(sorted_latencies, 99), 4),
                "max": round(sorted_latencies[-1], 4),
            },
        }


def _percentile(values: list[float], percentile: int) -> float:
    if not values:
        return 0.0
    rank = ((len(values) - 1) * percentile) / 100
    lower = math.floor(rank)
    upper = math.ceil(rank)
    if lower == upper:
        return values[int(rank)]
    weight = rank - lower
    return (values[lower] * (1 - weight)) + (values[upper] * weight)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--iterations", type=int, default=DEFAULT_ITERATIONS)
    parser.add_argument("--features", type=int, default=DEFAULT_FEATURE_COUNT)
    parser.add_argument("--seed", type=int, default=42)
    arguments = parser.parse_args()
    result = MLProviderEvaluator.run(
        iterations=arguments.iterations,
        feature_count=arguments.features,
        seed=arguments.seed,
    )
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result["success"] else 1)


if __name__ == "__main__":
    main()
