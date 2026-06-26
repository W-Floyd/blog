#!/usr/bin/env python3
"""Parse AVIF encode log lines and fit q-vs-size regressions.

Reads lines like:
    ./fob/opened-hq-400.avif q=76
    ./handwired/20190811_004928-640.avif q=32

Extracts (size, variant, q), fits a regression of q against size for each
variant (normal / hq), and prints suggested starting q values per size.

Usage:
    python3 q_regression.py [logfile ...]      # defaults to test.txt
"""

import re
import sys
import math
from collections import defaultdict

# Matches: <stuff>-[hq-]<size>.avif q=<q>
LINE_RE = re.compile(r"-(?:(hq)-)?(\d+)\.avif\s+q=(\d+)\b")


def parse(paths):
    """Yield (variant, size, q) tuples from the given log files."""
    rows = []
    for path in paths:
        with open(path) as fh:
            for line in fh:
                if ".avif q=" not in line:
                    continue
                m = LINE_RE.search(line)
                if not m:
                    continue
                variant = "hq" if m.group(1) else "normal"
                size = int(m.group(2))
                q = int(m.group(3))
                rows.append((variant, size, q))
    return rows


def fit_linear(xs, ys):
    """Ordinary least squares: y = a + b*x. Returns (a, b, r2)."""
    n = len(xs)
    mx = sum(xs) / n
    my = sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    b = sxy / sxx if sxx else 0.0
    a = my - b * mx
    # R^2
    ss_tot = sum((y - my) ** 2 for y in ys)
    ss_res = sum((y - (a + b * x)) ** 2 for x, y in zip(xs, ys))
    r2 = 1 - ss_res / ss_tot if ss_tot else 1.0
    return a, b, r2


def main():
    paths = sys.argv[1:] or ["test.txt"]
    rows = parse(paths)
    if not rows:
        sys.exit("No matching lines found.")

    by_variant = defaultdict(list)
    for variant, size, q in rows:
        by_variant[variant].append((size, q))

    # Standard size ladder seen in the logs (sorted unique sizes).
    all_sizes = sorted({size for _, size, _ in rows})

    print(f"Parsed {len(rows)} data points "
          f"({', '.join(f'{v}={len(d)}' for v, d in by_variant.items())})\n")

    fits = {}
    for variant in ("normal", "hq"):
        data = by_variant.get(variant)
        if not data:
            continue
        xs = [math.log(s) for s, _ in data]   # log(size) — q scales sub-linearly
        ys = [q for _, q in data]
        a, b, r2 = fit_linear(xs, ys)
        fits[variant] = (a, b, r2)
        print(f"=== {variant} ===")
        print(f"  model:  q = {a:.3f} + {b:.3f} * ln(size)")
        print(f"  R^2  =  {r2:.4f}   (n={len(data)})")

        # Residual spread, useful for choosing min/max bounds.
        resid = [q - (a + b * math.log(s)) for s, q in data]
        resid.sort()
        rmse = math.sqrt(sum(r * r for r in resid) / len(resid))
        print(f"  RMSE =  {rmse:.2f}   residual range [{resid[0]:.1f}, {resid[-1]:.1f}]\n")

    # Suggested starting q per size.
    print("=== suggested starting q (clamped 1..100) ===")
    header = f"{'size':>6} | " + " | ".join(f"{v:>7}" for v in fits)
    print(header)
    print("-" * len(header))
    for s in all_sizes:
        cells = []
        for variant in fits:
            a, b, _ = fits[variant]
            pred = a + b * math.log(s)
            cells.append(f"{max(1, min(100, round(pred))):>7}")
        print(f"{s:>6} | " + " | ".join(cells))


if __name__ == "__main__":
    main()
