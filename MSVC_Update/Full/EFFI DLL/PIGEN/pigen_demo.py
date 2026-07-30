"""Demonstrate the PIGEN CFFI extension."""

from __future__ import annotations

import argparse
import math
from collections.abc import Sequence

from _pigen_wrapper import lib


DEFAULT_SAMPLE_COUNTS = (1_000, 10_000, 100_000, 1_000_000)


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Estimate pi using the compiled PIGEN CFFI extension."
    )
    parser.add_argument(
        "samples",
        nargs="*",
        type=int,
        default=DEFAULT_SAMPLE_COUNTS,
        help=(
            "Monte Carlo sample counts to run "
            f"(default: {' '.join(map(str, DEFAULT_SAMPLE_COUNTS))})"
        ),
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)

    if any(n <= 0 for n in args.samples):
        raise SystemExit("error: every sample count must be greater than zero")

    print("PIGEN Monte Carlo pi approximation")
    print()
    print(f"{'samples':>12}  {'estimate':>12}  {'absolute error':>15}")

    for n in args.samples:
        estimate = lib.pi_approx(n)
        error = abs(estimate - math.pi)
        print(f"{n:12,d}  {estimate:12.8f}  {error:15.8f}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
