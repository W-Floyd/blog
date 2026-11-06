#!/bin/bash
#
# Builds the site as the Dockerfile does and compresses every text file it
# ships in the same image, so the numbers match what ships. Two outputs:
#
#   compression-by-size.json  How each encoder the Dockerfile uses (at its
#       settings there) compares to zopfli, by file size: files are binned by
#       power-of-two size, and each bin gets the median of each encoder's output
#       relative to zopfli's. Relative per file, so how compressible a file is
#       cancels out and only the encoders' differences remain.
#
#   transfer-sizes.json  Bytes a brotli-capable browser transfers for a few
#       pages and for the whole site, before (Caddy compressing on the fly:
#       zstd at its default level, about -3, from 512 B) and now (brotli -Z
#       wherever it is smaller, as the build keeps it).
#
# The outputs are a snapshot: they depend on the whole site, so they are only
# regenerated when this script changes, not when posts do.
set -euo pipefail

__root="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
__chart='compression-by-size.json'
__table='transfer-sizes.json'

if [ "${1:-}" == '-r' ]; then
    echo 'hugo'
    echo 'docker'
    exit
fi

if [ "${1:-}" == '-d' ]; then
    exit
fi

if [ "${1:-}" == '-t' ]; then
    echo "${__chart}"
    echo "${__table}"
    exit
fi

__work="$(mktemp -d)"
trap 'rm -rf "${__work}"' EXIT
__site="${__work}/site"
__sizes="${__work}/sizes"
hugo --minify -s "${__root}" -d "${__site}" >/dev/null

# One line per text file: path, original, brotli -Z, zstd -22, zopfli, zstd -3.
# Keep the find and encoder flags in step with the Dockerfile's compress stage.
docker run --rm -i -v "${__site}:/srv:ro" alpine sh -eu >"${__sizes}" <<'SH'
apk add -q --no-cache brotli zstd zopfli >/dev/null
find /srv -type f \
    -regex '.*\.\(html\|css\|js\|mjs\|xml\|svg\|json\|txt\|ico\|webmanifest\)' \
    -print0 | xargs -0 -n1 -P "$(nproc)" sh -c '
        printf "%s %d %d %d %d %d\n" "${1#/srv/}" "$(wc -c <"$1")" \
            "$(brotli -Z -c "$1" | wc -c)" \
            "$(zstd --ultra -22 -q -c "$1" | wc -c)" \
            "$(zopfli --i4 -c "$1" | wc -c)" \
            "$(zstd -3 -q -c "$1" | wc -c)"' _
SH

awk '
    function median(list,   a, n, i, j, t) {
        n = split(list, a, " ")
        for (i = 2; i <= n; i++)
            for (j = i; j > 1 && a[j - 1] + 0 > a[j] + 0; j--) { t = a[j]; a[j] = a[j - 1]; a[j - 1] = t }
        return n % 2 ? a[(n + 1) / 2] : (a[n / 2] + a[n / 2 + 1]) / 2
    }
    function join(a,   s, k) {
        for (k = lo; k <= hi; k++) if (k in count) s = s (s == "" ? "" : ",") a[k]
        return "[" s "]"
    }
    {
        k = int(log($2) / log(2))
        size[k] = size[k] " " $2
        br[k] = br[k] " " $3 / $5
        zs[k] = zs[k] " " $4 / $5
        count[k]++
        if (NR == 1 || k < lo) lo = k
        if (NR == 1 || k > hi) hi = k
    }
    END {
        for (k = lo; k <= hi; k++) if (k in count) {
            x[k] = median(size[k])
            b[k] = sprintf("%.3f", median(br[k]))
            z[k] = sprintf("%.3f", median(zs[k]))
            one[k] = 1
        }
        # Keys are the chart legend: name each encoder by its exact flags.
        printf "{\"bytes\":%s,\"files\":%s,\"brotli -Z\":%s,\"zstd --ultra -22\":%s,\"zopfli --i4\":%s}\n",
            join(x), join(count), join(b), join(z), join(one)
    }' "${__sizes}" >"${__chart}.tmp"

# A page's HTML plus the same-origin CSS and JS it links.
__page_files() {
    echo "${1}"
    grep -oE '(href|src)=[^ >]+\.(css|js)' "${__site}/${1}" |
        sed -E 's/^(href|src)=//; s/"//g' | grep '^/' | sed 's#^/##' | sort -u
}

# "<before> <now>" bytes over the files named on stdin.
__transfer() {
    awk '
        NR == FNR { want[$0] = 1; n++; next }
        $1 in want {
            found++
            before += $2 >= 512 ? $6 : $2
            now += $3 < $2 ? $3 : $2
        }
        END {
            if (found != n) { print "missing files for a page" > "/dev/stderr"; exit 1 }
            print before, now
        }' - "${__sizes}"
}

__post="$(cd "${__site}" && find . -path '*/web-nice-things/index.html' | sed 's#^\./##')"

{
    echo '{"columns":["Transferred","Before","Now"],"rows":['
    sep=''
    while IFS='|' read -r label page; do
        read -r before now < <(__page_files "${page}" | __transfer)
        printf '%s["%s",%d,%d]\n' "${sep}" "${label}" "${before}" "${now}"
        sep=','
    done <<EOF
Home page (HTML + CSS + JS)|index.html
Post list|posts/index.html
This post, including the charts' uPlot|${__post}
EOF
    read -r before now < <(cut -d' ' -f1 "${__sizes}" | __transfer)
    printf ',["%s",%d,%d]\n' 'Every text file on the site' "${before}" "${now}"
    echo ']}'
} >"${__table}.tmp"

mv "${__chart}.tmp" "${__chart}"
mv "${__table}.tmp" "${__table}"
