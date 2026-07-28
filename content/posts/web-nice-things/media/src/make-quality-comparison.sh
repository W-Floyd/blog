#!/bin/bash
#
# make-quality-comparison.sh
#
# A PROCESS_SCRIPT build step (see src/images_build.sh). Run from the post's
# media/ directory by the build, it implements the -r/-d/-t script interface:
#   -r  list required programs
#   -d  list dependency files (re-run when these change)
#   -t  list the files this script produces
# Run with no arguments, it generates those files.
#
# It demonstrates the visual-fidelity difference between the two AVIF ladders
# the build produces: the bandwidth-tuned "normal" encode (AVIF_SSIMULACRA2=65)
# and its higher-quality "-hq" sibling (AVIF_HQ_SSIMULACRA2=85). It takes the
# highest-resolution normal and -hq variants of one source image, crops the same
# small patch from each, and scales that patch up with no smoothing (point
# filter) so the per-pixel compression differences are easy to see, then
# assembles a labelled side-by-side panel plus a context shot.
#
# Outputs are written into src/ as PNG, so the build's PNG pass picks them up
# and converts them to *lossless* WebP — the comparison itself adds no artifacts;
# the only ones you see are baked into the AVIF inputs.
#
set -euo pipefail

###############################################################################
# Config — override any of these from the environment.
###############################################################################

# Where the processed AVIF variants live (relative to media/, where the build
# runs this), and the stem to compare.
SRC_DIR="${SRC_DIR:-../../smart-yogurt-maker-part-01/media}"
STEM="${STEM:-IMG_20220125_113949_cleaned}"

# Crop patch in the *full-resolution* image: WIDTHxHEIGHT+X+Y.
# Default lands on the module's etched text, where the normal and -hq encodes
# diverge most (high-frequency detail is where the bit budget shows).
#
# Kept deliberately small. At 4x this is the single heaviest asset on the page
# that hosts it, and it is lossless by necessity, so panel area is the only lever
# on its size. 240px keeps the etched text and its surrounding flat solder mask
# — enough to show both blocking and banding — at ~45% of the area a 360px crop
# needed. Centred on the same point the larger crop was.
CROP="${CROP:-240x240+2380+1900}"

# Integer upscale factor for display, applied with no interpolation so each
# encoded pixel stays a crisp block.
ZOOM="${ZOOM:-4}"

# Where to write the results. src/ so the PNG pass converts them to WebP.
OUT_DIR="${OUT_DIR:-./src}"

# Font for the panel labels. ImageMagick's default font is often unset on macOS;
# point at a system font (override FONT for another platform).
FONT="${FONT:-/System/Library/Fonts/Supplemental/Arial.ttf}"

###############################################################################
# Resolve the input variants (needed by -d/-t and the encode alike).
###############################################################################

# Highest-resolution variant = the largest width emitted for this stem. The
# native (100%) width is always one of them, so this is the full-detail image.
__largest_width() {
    local prefix="$1"
    ls "${SRC_DIR}"/${prefix}-[0-9]*.avif 2>/dev/null \
        | sed -E 's/.*-([0-9]+)\.avif$/\1/' \
        | sort -rn | head -n1
}

NORMAL_W="$(__largest_width "${STEM}")"
HQ_W="$(__largest_width "${STEM}-hq")"
NORMAL_AVIF="${SRC_DIR}/${STEM}-${NORMAL_W}.avif"
HQ_AVIF="${SRC_DIR}/${STEM}-hq-${HQ_W}.avif"

NORMAL_CROP="${OUT_DIR}/quality-normal-crop.png"
HQ_CROP="${OUT_DIR}/quality-hq-crop.png"
PANEL="${OUT_DIR}/quality-comparison.png"
CONTEXT="${OUT_DIR}/quality-comparison-context.png"

###############################################################################
# Script interface
###############################################################################

case "${1:-}" in
    -r)
        printf '%s\n' magick identify
        exit
        ;;
    -d)
        printf '%s\n' "${NORMAL_AVIF}" "${HQ_AVIF}"
        exit
        ;;
    -t)
        printf '%s\n' "${PANEL}" "${NORMAL_CROP}" "${HQ_CROP}" "${CONTEXT}"
        exit
        ;;
esac

###############################################################################
# Generate
###############################################################################

[ -n "${NORMAL_W}" ] || { echo "no normal variants for '${STEM}' in ${SRC_DIR}"; exit 1; }
[ -n "${HQ_W}" ] || { echo "no -hq variants for '${STEM}' in ${SRC_DIR}"; exit 1; }

echo "normal: ${NORMAL_AVIF} (${NORMAL_W}px wide, $(du -h "${NORMAL_AVIF}" | cut -f1))"
echo "hq:     ${HQ_AVIF} (${HQ_W}px wide, $(du -h "${HQ_AVIF}" | cut -f1))"
echo "crop:   ${CROP}  zoom: ${ZOOM}x"

mkdir -p "${OUT_DIR}"

# Crop the same patch from each, then point-scale it up. -filter point keeps the
# blow-up faithful to the encoded pixels (no blur to hide blocking/banding).
__crop_zoom() {
    local in="$1" out="$2"
    magick "${in}" -crop "${CROP}" +repage \
        -filter point -resize "$((ZOOM * 100))%" \
        "${out}"
}

__crop_zoom "${NORMAL_AVIF}" "${NORMAL_CROP}"
__crop_zoom "${HQ_AVIF}" "${HQ_CROP}"

# Context shot: the full image scaled down with the crop region outlined, so a
# reader can see where in the photo the patch came from.
CROP_W="${CROP%%x*}"; rest="${CROP#*x}"
CROP_H="${rest%%+*}"; rest="${rest#*+}"
CROP_X="${rest%%+*}"; CROP_Y="${rest##*+}"
magick "${NORMAL_AVIF}" -resize 640x \
    -fill none -stroke red -strokewidth 3 \
    -draw "rectangle $((CROP_X * 640 / NORMAL_W)),$((CROP_Y * 640 / NORMAL_W)) $(((CROP_X + CROP_W) * 640 / NORMAL_W)),$(((CROP_Y + CROP_H) * 640 / NORMAL_W))" \
    "${CONTEXT}"

# Labelled side-by-side panel. Labels carry the SSIMULACRA2 target each ladder
# was encoded to, so the panel is self-explanatory. Label size scales with the
# zoomed crop width so it stays legible at any CROP/ZOOM.
CROP_PX="${CROP%%x*}"
PT=$(( CROP_PX * ZOOM / 24 ))
BAR=$(( PT * 3 / 2 ))
magick -font "${FONT}" \
    \( "${NORMAL_CROP}" -gravity South -background '#0008' -fill white \
        -pointsize "${PT}" -splice "0x${BAR}" -annotate "+0+$((PT / 4))" "normal · SSIMULACRA2 65" \) \
    \( "${HQ_CROP}" -gravity South -background '#0008' -fill white \
        -pointsize "${PT}" -splice "0x${BAR}" -annotate "+0+$((PT / 4))" "hq · SSIMULACRA2 85" \) \
    +smush 16 -background white -bordercolor white -border 16 \
    "${PANEL}"

echo
echo "wrote (PNG -> lossless WebP on build):"
echo "  ${PANEL}            (side-by-side panel)"
echo "  ${NORMAL_CROP}    (normal crop, ${ZOOM}x)"
echo "  ${HQ_CROP}        (hq crop, ${ZOOM}x)"
echo "  ${CONTEXT} (full image with crop region marked)"
