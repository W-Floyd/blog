#!/bin/bash
#
# make-lossless-comparison.sh
#
# A PROCESS_SCRIPT build step (see src/images_build.sh). Run from the post's
# media/ directory, it implements the -r/-d/-t script interface and, with no
# args, encodes a handful of representative images losslessly as PNG, WebP and
# AVIF so the post can quote real, build-fresh byte counts (via the `filesize`
# shortcode) for the lossless-format comparison.
#
# Fairness: for each sample a single canonical PNG is rendered first, and *that*
# exact pixel data is what gets encoded to WebP and AVIF — so all three columns
# describe the same image, not three different resizes of a source.
#
# Fairness also means each column runs its encoder as hard as it will go. The PNG
# used to be a plain ImageMagick write while WebP got `-z 9` and AVIF `-s 0`,
# which quietly stacked the comparison against PNG: running oxipng with Zopfli
# over it takes 12-42% off these samples. WebP still wins every category, but by
# noticeably less, and a comparison is only worth quoting if every format is
# given its best shot.
#
# Outputs land in media/lossless/ (NOT src/), so the build's PNG pass leaves
# them alone and the .png stays a real PNG rather than being turned into WebP.
#
set -euo pipefail

###############################################################################
# Config
###############################################################################

# Output directory. This unit's own dir (the build runs the script from there),
# kept separate from the responsive media/ tree and with image re-encoding
# disabled in .env, so these deliberately-formatted samples are never touched by
# the JPEG/PNG -> AVIF/WebP passes.
OUT_DIR="${OUT_DIR:-.}"

# Samples: "tag|source-path|magick-pre-ops". The source is rendered to
# OUT_DIR/<tag>.png with the given ops (empty = verbatim re-encode), then that
# PNG is encoded to WebP and AVIF. Paths are relative to this unit's dir
# (content/posts/web-nice-things/media/lossless/).
#
# A photograph (lots of imperceptible detail) and three synthetic images
# (screenshot, plot, UI capture) so the per-content-type pattern is visible.
SAMPLES=(
    "photo|../demo/src/DSC_3587.JPG|-resize 1440x"
    "screenshot|../../../energy-rates/media/src/dev-tools.png|"
    "plot|../../../smart-yogurt-maker-part-01/media/src/log.png|"
    "ui|../../../smart-yogurt-maker-part-02/media/src/Screenshot from 2022-01-27 12-20-17.png|"
)

###############################################################################
# Derived target/dependency lists (needed by -t/-d)
###############################################################################

__targets() {
    local s tag
    for s in "${SAMPLES[@]}"; do
        tag="${s%%|*}"
        printf '%s\n' "${OUT_DIR}/${tag}.png" "${OUT_DIR}/${tag}.webp" "${OUT_DIR}/${tag}.avif"
    done
}

__deps() {
    local s rest src
    for s in "${SAMPLES[@]}"; do
        rest="${s#*|}"      # strip tag
        src="${rest%%|*}"   # source path, before the ops field
        printf '%s\n' "${src}"
    done
}

###############################################################################
# Script interface
###############################################################################

case "${1:-}" in
    -r)
        printf '%s\n' magick cwebp avifenc oxipng
        exit
        ;;
    -d)
        __deps
        exit
        ;;
    -t)
        __targets
        exit
        ;;
esac

###############################################################################
# Generate
###############################################################################

mkdir -p "${OUT_DIR}"

for s in "${SAMPLES[@]}"; do
    tag="${s%%|*}"
    rest="${s#*|}"
    src="${rest%%|*}"
    ops="${rest#*|}"

    [ -f "${src}" ] || { echo "missing source: ${src}"; exit 1; }

    png="${OUT_DIR}/${tag}.png"
    webp="${OUT_DIR}/${tag}.webp"
    avif="${OUT_DIR}/${tag}.avif"

    # 1. Canonical lossless PNG sample (the shared input for all three columns).
    #    -strip drops metadata so the comparison is pixels, not embedded EXIF.
    magick "${src}" ${ops} -strip "${png}"

    #    Then optimise it as hard as the other two columns are optimised. This is
    #    lossless recompression only -- the pixels the WebP and AVIF encoders see
    #    below are unchanged, so all three columns still describe one image.
    oxipng -o max --zopfli --zi 255 --ziwi 50 --strip safe -a -q "${png}"

    # 2. WebP lossless (VP8L), maximum effort.
    cwebp -quiet -lossless -z 9 "${png}" -o "${webp}"

    # 3. AVIF lossless, slowest/best speed setting.
    avifenc -l -s 0 "${png}" "${avif}" >/dev/null 2>&1

    echo "  ${tag}: png=$(du -h "${png}" | cut -f1) webp=$(du -h "${webp}" | cut -f1) avif=$(du -h "${avif}" | cut -f1)"
done

echo "wrote lossless samples to ${OUT_DIR}/"
