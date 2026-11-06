#!/bin/bash
#
# Compressed size of a sample page against zopfli's iteration count, with gzip -9
# as the baseline. Runs in the image the Dockerfile compresses with, so the
# numbers match what ships.
#
# The sample is the minified smart-yogurt-maker-part-01 page, from a fresh
# build. The output is a snapshot: it is only regenerated when this script
# changes, not when that post does. No timings: CPU time is linear in
# iterations (~0.1s + 6.8ms each, on this sample), and leaving it out keeps the
# output deterministic.
set -euo pipefail

__root="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
__target='zopfli-iterations.json'

if [ "${1:-}" == '-r' ]; then
    echo 'hugo'
    echo 'docker'
    exit
fi

if [ "${1:-}" == '-d' ]; then
    exit
fi

if [ "${1:-}" == '-t' ]; then
    echo "${__target}"
    exit
fi

__site="$(mktemp -d)"
trap 'rm -rf "${__site}"' EXIT
hugo --minify -s "${__root}" -d "${__site}" >/dev/null
__sample="$(find "${__site}" -path '*/smart-yogurt-maker-part-01/index.html')"
[ -n "${__sample}" ] || { echo 'sample page not found' >&2; exit 1; }

docker run --rm -i -v "${__sample}:/sample:ro" alpine sh -eu >"${__target}.tmp" <<'SH'
apk add -q --no-cache zopfli >/dev/null
g=$(gzip -9 -c /sample | wc -c)
its='1 2 4 8 16 32 64 128 256 512 1024 2048'
join() { tr '\n' ',' | sed 's/,$//'; }
# Columnar, one array per series, as the uplot shortcode takes it.
printf '{"original_bytes":%d,"iterations":[%s],"zopfli":[%s],"gzip -9":[%s]}\n' \
    "$(wc -c </sample)" \
    "$(printf '%s\n' $its | join)" \
    "$(for i in $its; do zopfli --i"$i" -c /sample | wc -c; done | join)" \
    "$(for i in $its; do echo "$g"; done | join)"
SH
mv "${__target}.tmp" "${__target}"
