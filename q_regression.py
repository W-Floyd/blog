#!/usr/bin/env python3
"""Fit the AVIF quality-seed model from encode logs.

The image pipeline binary-searches each output's quality for a SSIMULACRA2
target. That search is seeded from a model, q ~= a + b*ln(width), so it starts
close and converges in fewer probes. This script fits that model from what the
pipeline actually produced, and writes the coefficients back out for the pipeline
to read on its next run — so the search gets cheaper the more the site is built.

Two input formats:

  TSV  (--log)  the structured log src/images_build.sh appends to, one row per
                encode, with the encoder config alongside. Preferred: it can be
                filtered per config, and a quality number means different things
                under different encoders.
  text          legacy stdout capture, lines like
                    ./fob/opened-hq-400.avif q=76

Usage:
    python3 q_regression.py --log src/encode-log.tsv --config 0/420 \\
        --emit src/q-model.env
    python3 q_regression.py old-build-output.txt        # legacy report only
"""

import argparse
import math
import os
import re
import sys
from collections import defaultdict

# Legacy text format: <stuff>-[hq-]<width>.avif q=<q>
LINE_RE = re.compile(r"-(?:(hq)-)?(\d+)\.avif\s+q=(\d+)\b")

TSV_FIELDS = ('path', 'variant', 'width', 'target', 'quality',
              'bytes', 'probes', 'subsampling', 'speed')


def parse_text(paths):
    rows = []
    for path in paths:
        with open(path) as fh:
            for line in fh:
                if '.avif q=' not in line:
                    continue
                m = LINE_RE.search(line)
                if not m:
                    continue
                rows.append({
                    'variant': 'hq' if m.group(1) else 'normal',
                    'width': int(m.group(2)),
                    'quality': int(m.group(3)),
                    'probes': None,
                    'speed': None,
                    'subsampling': None,
                })
    return rows


def parse_tsv(path, config=None):
    """Read the structured log.

    `config` filters rows to one encoder configuration: 'SPEED' keeps every
    subsampling, 'SPEED/SUBSAMPLING' narrows further. Speed is the parameter that
    moves the quality-to-score mapping most, so filtering on it alone is the
    useful default; a build that mixes 4:2:0 and 4:4:4 sources still contributes
    every row to one model, which only ever affects where the search starts.
    """
    rows = []
    want_speed = want_sub = None
    if config:
        want_speed, _, want_sub = config.partition('/')
        want_sub = want_sub or None
    with open(path) as fh:
        header = None
        for line in fh:
            line = line.rstrip('\n')
            if not line or line.startswith('#'):
                continue
            parts = line.split('\t')
            if header is None and parts[0] == 'ts':
                header = parts
                continue
            if header is None:
                header = ['ts'] + list(TSV_FIELDS)
            row = dict(zip(header, parts))
            try:
                r = {
                    'variant': row['variant'],
                    'width': int(row['width']),
                    'quality': int(row['quality']),
                    'probes': int(row['probes']) if row.get('probes', '').isdigit() else None,
                    'speed': row.get('speed'),
                    'subsampling': row.get('subsampling'),
                }
            except (KeyError, ValueError):
                continue
            # width 0 means the reference width was unreadable at encode time; the
            # row records a real encode but cannot inform a width-based fit.
            if r['width'] <= 0:
                continue
            if want_speed is not None and r['speed'] != want_speed:
                continue
            if want_sub is not None and r['subsampling'] != want_sub:
                continue
            rows.append(r)
    return rows


def fit_linear(xs, ys):
    """Ordinary least squares: y = a + b*x. Returns (a, b, r2, rmse)."""
    n = len(xs)
    mx = sum(xs) / n
    my = sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    b = sxy / sxx if sxx else 0.0
    a = my - b * mx
    ss_tot = sum((y - my) ** 2 for y in ys)
    ss_res = sum((y - (a + b * x)) ** 2 for x, y in zip(xs, ys))
    r2 = 1 - ss_res / ss_tot if ss_tot else 1.0
    rmse = math.sqrt(ss_res / n)
    return a, b, r2, rmse


def main():
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('logs', nargs='*', help='legacy text logs')
    ap.add_argument('--log', help='structured TSV log')
    ap.add_argument('--config', help='fit only rows matching SPEED or SPEED/SUBSAMPLING')
    ap.add_argument('--emit', help='write shell-sourceable coefficients here')
    ap.add_argument('--min-points', type=int, default=20,
                    help='refuse to fit a variant with fewer points (default 20)')
    ap.add_argument('--quiet', action='store_true',
                    help='one summary line only, for mid-build refits')
    args = ap.parse_args()

    if args.log:
        rows = parse_tsv(args.log, args.config)
    elif args.logs:
        rows = parse_text(args.logs)
    else:
        ap.error('need --log FILE or one or more text logs')

    if not rows:
        sys.exit('No usable data points found.')

    # Fit each variant twice over: once across all subsampling modes (the
    # fallback, used when a mode has too little data of its own) and once per
    # mode. 4:2:0 photographs and 4:4:4 screenshots sit on genuinely different
    # quality-to-score curves — measured here, 4:4:4 needed 8.6 search probes
    # against 6.0 for 4:2:0 — and one line through both fits neither well.
    groups = {}
    for r in rows:
        groups.setdefault((r['variant'], None), []).append(r)
        if r.get('subsampling'):
            groups.setdefault((r['variant'], r['subsampling']), []).append(r)

    def key_for(variant, sub):
        return ('AVIF_SEED_'
                + ('HQ_' if variant == 'hq' else '')
                + (f'{sub}_' if sub else ''))

    fits = {}
    report = []
    for variant in ('normal', 'hq'):
        for sub in (None, '420', '444'):
            data = groups.get((variant, sub))
            label = f"{variant}/{sub or 'all'}"
            if not data:
                continue
            if len(data) < args.min_points:
                report.append(f'  {label:<14} skipped: {len(data)} points '
                              f'(< {args.min_points})')
                continue
            xs = [math.log(r['width']) for r in data]
            ys = [r['quality'] for r in data]
            a, b, r2, rmse = fit_linear(xs, ys)
            fits[key_for(variant, sub)] = (a, b, r2, rmse, len(data), label)
            probes = [r['probes'] for r in data if r['probes'] is not None]
            pstat = f', mean {sum(probes) / len(probes):.1f} probes' if probes else ''
            report.append(f'  {label:<14} q = {a:7.3f} + {b:6.3f}*ln(w)   '
                          f'R^2 {r2:.3f}  RMSE {rmse:4.1f}  n={len(data)}{pstat}')

    if args.quiet:
        pass  # quiet mode reports from the emit block, and only on a real change
    else:
        print(f'Fitted from {len(rows)} encodes'
              + (f' (config {args.config})' if args.config else ''))
        for line in report:
            print(line)

    if args.emit:
        if not fits:
            if not args.quiet:
                print(f'Not writing {args.emit}: no variant had enough data.')
            return
        lines = [
            '# Generated by q_regression.py from the encode log. Committed so a',
            '# fresh clone starts with a converged search; rewritten by any build',
            '# that produces new encodes. These are search *seeds* only — every',
            '# candidate is still verified against the real SSIMULACRA2 target, so',
            '# a stale model costs extra probes and never changes an output byte.',
        ]
        if args.config:
            lines.append(f'# Fitted for encoder speed/subsampling {args.config}.')
        lines.append('#')
        lines.append('# Keys without a subsampling suffix are the fallback fit across all')
        lines.append('# modes; a 420/444 key wins when the source resolves to that mode.')
        for prefix, (a, b, r2, rmse, n, label) in fits.items():
            lines += [
                f'# {label}: R^2 {r2:.3f}, RMSE {rmse:.1f}, n={n}',
                f'{prefix}A={a:.3f}',
                f'{prefix}B={b:.3f}',
            ]
        # Refitting after every encode means most fits reproduce the coefficients
        # already on disk. Comparing the emitted AVIF_SEED_* lines (the only lines
        # that affect behaviour — the comments carry an ever-growing n) lets an
        # unchanged fit skip both the write and the report: no churn on a committed
        # file, and mid-build output that shows the model moving rather than a
        # heartbeat.
        def coefficients(text):
            return [ln for ln in text.splitlines() if ln.startswith('AVIF_SEED_')]

        new = '\n'.join(lines) + '\n'
        try:
            with open(args.emit) as fh:
                unchanged = coefficients(fh.read()) == coefficients(new)
        except OSError:
            unchanged = False

        if unchanged:
            if not args.quiet:
                print(f'{args.emit} already current')
            return

        # Written via temp + rename: mid-build refits run while other encodes are
        # reading this file, and a half-written model must never be observable.
        tmp = args.emit + f'.tmp.{os.getpid()}'
        with open(tmp, 'w') as fh:
            fh.write(new)
        os.replace(tmp, args.emit)

        if args.quiet:
            bits = [f'{label} q={a:.1f}{b:+.2f}ln(w) n={n}'
                    for (a, b, _r2, _rmse, n, label) in fits.values()]
            print(f'{len(rows)} encodes -> ' + '; '.join(bits))
        else:
            print(f'Wrote {args.emit}')


if __name__ == '__main__':
    main()
