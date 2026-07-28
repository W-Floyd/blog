#!/bin/bash
#
# favicon_build.sh
#
# Renders every site icon from the one SVG master, so the whole set stays in
# sync with a single edit and nothing is hand-maintained.
#
# This unit sets PROCESS_PNG=false, so the build's image passes never touch these
# files: what this script writes is what ships. That means optimising here, not
# relying on a later pass.
#
# rsvg-convert emits a full RGBA PNG with no attempt at compression — the 180px
# touch icon came out at 21 KB that way. These are flat gradient artwork, so
# palette quantisation is essentially free visually (measured SSIMULACRA2 92.4 at
# 180px, indistinguishable at the sizes these are ever drawn at) and cuts them by
# roughly 60%. Worth doing: Firefox treats apple-touch-icon as a rich-icon
# candidate and fetches the largest declared icon on first visit for its New Tab
# tiles, so this is not a cost paid only by people adding the site to an iOS home
# screen.
#
set -euo pipefail

__source='favicon.svg'

# Every output, as "<file>:<pixel size>". One list drives -t and the render loop
# so they cannot drift.
#
#   favicon-16/32       classic bitmap favicons, for anything that ignores the SVG
#   apple-touch-icon    iOS/iPadOS home screen, Safari favourites, and Firefox's
#                       rich-icon cache. Apple's slot takes no SVG, hence 180px.
#   android-chrome-*    site.webmanifest icons (PWA install, Android home screen)
#
# The android-chrome pair was referenced by site.webmanifest but had never been
# generated, so it 404'd on every client that read the manifest.
#
# No Windows tile: browserconfig.xml and its mstile PNG were removed with it.
# Nothing linked to that file -- IE simply probed /browserconfig.xml by
# convention -- and IE11 and legacy Edge are both end-of-life, so it was an asset
# no current browser would ever ask for.
__outputs='favicon-16x16.png:16
favicon-32x32.png:32
apple-touch-icon.png:180
android-chrome-192x192.png:192
android-chrome-512x512.png:512'

if [ "${1:-}" == '-r' ]; then
    echo 'rsvg-convert'
    echo 'pngquant'
    echo 'oxipng'
    exit
fi

if [ "${1:-}" == '-d' ]; then
    echo "${__source}"
    exit
fi

if [ "${1:-}" == '-t' ]; then
    cut -d: -f1 <<<"${__outputs}"
    exit
fi

# Two stages, in this order, because they do different jobs and compose:
#
#   pngquant  lossy: reduces to a palette. This is where the bulk of the saving
#             is (~60%), and it is free visually on flat gradient artwork at the
#             sizes icons are drawn — measured SSIMULACRA2 92.4 on the 180px
#             touch icon, indistinguishable magnified 3x.
#   oxipng    lossless: recompresses the palettised result with Zopfli. Another
#             ~20% for no quality cost at all; verified pixel-identical.
#
# Running only the lossless stage would leave these at ~17 KB rather than ~7 KB;
# running only the lossy one leaves ~20% on the table. Hence both.
#
# Maximum Zopfli effort (--zi 255) is deliberate but almost symbolic: it buys
# 2-11 bytes over the default 15 iterations. It costs ~8s across the whole set,
# for a script that only runs when the SVG changes, so there is no reason not to.
# --ziwi caps the wasted work by stopping after 50 iterations with no improvement.
# -a lets it rewrite the colour values of fully transparent pixels, which cannot
# be seen: no help after quantisation, but it is what shrinks the two small
# favicons that pngquant declines to touch.
#
# Neither stage is allowed to make a file worse: if pngquant cannot hit its
# quality floor it exits non-zero and writes nothing, and each stage keeps the
# previous bytes unless the new ones are actually smaller.
__shrink() {
    local __file="${1}" __tmp="${1}.opt" __orig __quant __final

    __orig="$(wc -c <"${__file}")"

    # Stage 1: quantise.
    if pngquant --quality=90-100 --speed 1 --strip \
        --force --output "${__tmp}" "${__file}" 2>/dev/null; then
        if [ "$(wc -c <"${__tmp}")" -lt "${__orig}" ]; then
            mv "${__tmp}" "${__file}"
        else
            rm -f "${__tmp}"
        fi
    else
        rm -f "${__tmp}"
    fi
    __quant="$(wc -c <"${__file}")"

    # Stage 2: lossless recompress, in place. oxipng only writes when it wins.
    oxipng -o max --zopfli --zi 255 --ziwi 50 --strip safe -a -q "${__file}" 2>/dev/null || true
    __final="$(wc -c <"${__file}")"

    if [ "${__final}" -ge "${__orig}" ]; then
        printf '  %s: already minimal (%d B)\n' "${__file}" "${__final}"
        return
    fi

    printf '  %s: %d -> %d B (-%d%%, quantise %d, zopfli %d)\n' \
        "${__file}" "${__orig}" "${__final}" \
        "$(((__orig - __final) * 100 / __orig))" \
        "$((__orig - __quant))" "$((__quant - __final))"
}

while IFS=: read -r __file __size; do
    [ -n "${__file}" ] || continue
    rsvg-convert -w "${__size}" -h "${__size}" "${__source}" -o "${__file}"
    __shrink "${__file}"
done <<<"${__outputs}"

exit
