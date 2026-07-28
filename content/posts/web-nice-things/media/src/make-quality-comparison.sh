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
# It demonstrates the visual-fidelity difference between the site's two AVIF
# targets: the bandwidth-tuned ladder (AVIF_SSIMULACRA2=65) and its higher-quality
# -hq sibling (AVIF_HQ_SSIMULACRA2=85).
#
# The figure is deliberately one crop, not two. This script only ever *crops*,
# losslessly, straight from the pipeline's own source photograph into a PNG. The
# build's ordinary AVIF pass then encodes that one PNG twice — once to 65, once to
# 85 — and both encodes are served exactly as they come out. So the two images on
# the page are real outputs of the real encoder at the real targets, with no
# generation of loss between the encoder and the reader.
#
# That is the whole reason for the arrangement. Earlier versions cropped from an
# already-encoded AVIF and then re-encoded the crop, which meant the figure showed
# the delivery encode's artifacts layered over the ones being compared. Cropping
# before any encoding removes that entirely.
#
# Crops are emitted at native scale — one pixel per source pixel, no magnification
# baked in. Enlargement is a display concern, done in CSS by the page, so it
# follows the reader's layout and pixel density instead of a factor chosen here,
# and costs nothing on the wire.
#
set -euo pipefail

###############################################################################
# Config — override any of these from the environment.
###############################################################################

# The pipeline's source photograph, not one of its AVIF outputs: cropping has to
# happen before any lossy encode for the figure to mean what it claims. This is
# the same file the responsive ladder for that post is built from, so the crop
# carries exactly the detail the real encoder is given.
#
# (A lossless .xcf master sits beside it, but this JPEG is what the pipeline
# actually encodes, so it is the honest input for a figure about that pipeline.)
SRC_IMG="${SRC_IMG:-../../smart-yogurt-maker-part-01/media/src/IMG_20220125_113949_cleaned.jpg}"

# Crop patch in the *full-resolution* source: WIDTHxHEIGHT+X+Y.
# Default lands on the module's etched text, where the two targets diverge most
# (high-frequency detail is where the bit budget shows).
#
# 240px keeps the etched text and its surrounding flat solder mask, which is
# enough to show both blocking and banding. It also sets how far the page can
# enlarge it: displayed two-up in an 860px column, each crop gets ~430 CSS px, so
# 240px is already a ~1.8x upscale on a 1x display and roughly 1:1 on a 2x one.
# Growing this makes the crop sharper but the enlargement weaker.
CROP="${CROP:-240x240+2380+1900}"

# Where to write the crop. src/ so the build's PNG pass encodes it (to 65 and 85,
# per this unit's .env).
OUT_DIR="${OUT_DIR:-./src}"

CROP_PNG="${OUT_DIR}/quality-crop.png"

# The context shot is written into a *sibling unit* (../context/), not this one.
# It is a whole photograph and wants the site's ordinary target and its full
# responsive ladder, where the crop wants exactly two encodes and no ladder at
# all; those are per-unit .env settings, so the two cannot share a unit. Keeping
# it a target of this script rather than giving that unit its own generator means
# CROP is defined exactly once: a second copy could drift and silently outline a
# region the crop did not come from.
#
# Safe by the build's own rules: a directory carrying its own src/.env is a
# separate unit that prunes itself, and prune candidates only come from
# directories mirroring this unit's ./src/ tree, which ../context/ is not.
# Note the two units are not ordered relative to each other, so a CROP change can
# land in the context AVIF one build later than in the crop.
CONTEXT_DIR="${CONTEXT_DIR:-./context/src}"
CONTEXT="${CONTEXT_DIR}/quality-comparison-context.png"

###############################################################################
# Script interface
###############################################################################

case "${1:-}" in
    -r)
        printf '%s\n' magick identify
        exit
        ;;
    -d)
        printf '%s\n' "${SRC_IMG}"
        exit
        ;;
    -t)
        printf '%s\n' "${CROP_PNG}" "${CONTEXT}"
        exit
        ;;
esac

###############################################################################
# Generate
###############################################################################

[ -e "${SRC_IMG}" ] || { echo "source not found: ${SRC_IMG}"; exit 1; }

SRC_W="$(identify -format '%w' "${SRC_IMG}")"
SRC_H="$(identify -format '%h' "${SRC_IMG}")"

echo "source: ${SRC_IMG} (${SRC_W}x${SRC_H}, $(du -h "${SRC_IMG}" | cut -f1))"
echo "crop:   ${CROP} (native scale, lossless; encoded to 65 and 85 by the build)"

mkdir -p "${OUT_DIR}" "${CONTEXT_DIR}"

# Parse the crop geometry once; both the crop and the context rectangle need it.
CROP_W="${CROP%%x*}"; rest="${CROP#*x}"
CROP_H="${rest%%+*}"; rest="${rest#*+}"
CROP_X="${rest%%+*}"; CROP_Y="${rest##*+}"

# Refuse a crop that falls outside the source rather than silently producing a
# clipped, smaller patch than the context rectangle claims.
if [ "$((CROP_X + CROP_W))" -gt "${SRC_W}" ] || [ "$((CROP_Y + CROP_H))" -gt "${SRC_H}" ]; then
    echo "crop ${CROP} falls outside ${SRC_W}x${SRC_H}" >&2
    exit 1
fi

# The crop itself: no resize, no filter, no re-encode. PNG out, so the only lossy
# step in the whole figure is the build's AVIF encode of this file.
magick "${SRC_IMG}" -crop "${CROP}" +repage "${CROP_PNG}"

# Context shot: the full frame at native resolution with the crop region
# outlined, so a reader can see where in the photo the patch came from. Emitted
# full-size rather than pre-shrunk so the build's own responsive ladder decides
# the served sizes — the same treatment every other photograph on the site gets,
# instead of one hardcoded width that is wrong at most viewports.
#
# Drawn on the same source the crop comes from, in the crop's own coordinate
# space, so there is no scaling arithmetic to get wrong and no chance of the
# outline disagreeing with the patch.
#
# Stroke scaled to the image, not fixed: 3px was legible on a 640px render and
# would be a near-invisible hairline at 4032px. It also has to survive the
# ladder's smallest rungs, where the whole frame is 400px wide.
STROKE=$(( SRC_W / 200 ))
[ "${STROKE}" -lt 2 ] && STROKE=2

magick "${SRC_IMG}" \
    -fill none -stroke red -strokewidth "${STROKE}" \
    -draw "rectangle ${CROP_X},${CROP_Y} $((CROP_X + CROP_W)),$((CROP_Y + CROP_H))" \
    "${CONTEXT}"

# Labels are not burned in. The old composed panel had to carry them because it
# was one indivisible picture; two separate images are labelled by the page
# instead, which keeps the text selectable, translatable and legible at any size,
# and keeps synthetic high-contrast glyphs out of a figure whose subject is
# photographic compression.

echo
echo "wrote:"
echo "  ${CROP_PNG}   (${CROP_W}x${CROP_H} lossless crop -> AVIF at 65 and 85)"
echo "  ${CONTEXT} (full frame, crop region marked -> AVIF ladder)"
