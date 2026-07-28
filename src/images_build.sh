#!/bin/bash

__pathfile='./.path'

###############################################################################

if ! [ -e "${__pathfile}" ]; then
    echo "${PATH}" >"${__pathfile}"
    [ "$(env | sed -r -e '/^(PWD|SHLVL|_|PATH)=/d')" ] && exec -c "$0" "$@"
fi

export PATH="$(cat "${__pathfile}")"
rm "${__pathfile}"

###############################################################################

__hashfunc='sha256sum'

########################################
# Options (plain shell variables)
########################################
#
# These are deliberately NOT exported and NOT in __ENVIRONMENT_LIST: the env
# hash written to each .hash file is taken from `printenv`, so anything exported
# here would change every hash and force a full re-encode of the whole site.
#
__dry_run='false'
__prune='true'
__reference_gate='true'

__usage() {
    cat <<'EOF'
Usage: images_build.sh [options]

Generates the served image set from every */src/ directory that carries a .env.

Under ./content/, generation is gated on references: an image is only built if
something in the site actually points at it, and generated files that nothing
points at any more are deleted. ./static/ is always built in full and never
pruned (favicons and the like are referenced by the theme, not by posts).

AVIF encoding is libaom via avifenc at AVIF_SPEED, with chroma subsampling chosen
per source (photographs 4:2:0, screenshots and plots 4:4:4) and Exif/XMP dropped
while any colour profile is kept. Each output's quality is binary-searched for its
SSIMULACRA2 target; every encode is logged to src/encode-log.tsv and the search's
seed model is re-fitted from that log on every encode, and at the start and end of
the run, so it converges in fewer probes over time. The log is disposable; the
fitted src/q-model.env is committed.

Options:
  -n, --dry-run   Report what would be generated and deleted; change nothing.
      --no-prune  Generate as usual, but delete nothing.
      --no-gate   Ignore references entirely: build everything, prune nothing
                  (the pre-reference-gating behaviour).
      --refit-interval N
                  Re-fit the quality-seed model every N encodes during the build
                  (default 1 — every encode; 0 for start/end of build only).
  -h, --help      This text.
EOF
}

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        -n | --dry-run) __dry_run='true' ;;
        --no-prune) __prune='false' ;;
        --no-gate)
            __reference_gate='false'
            __prune='false'
            ;;
        --refit-interval)
            shift
            __refit_interval_override="${1}"
            ;;
        -h | --help)
            __usage
            exit 0
            ;;
        *)
            echo "Unknown option: ${1}"
            __usage
            exit 1
            ;;
    esac
    shift
done

__needed_programs="${__hashfunc}
magick
identify
avifenc
bc
ssimulacra2"

export __fatal_error='false'

while read -r __program; do
    if ! which "${__program}" &>/dev/null; then
        echo "Need '${__program}'"
        export __fatal_error='true'
    fi
done <<<"${__needed_programs}"

###############################################################################
# Variables
###############################################################################

__ignore_variables='PWD
SHLVL
_
OLDPWD
PATH'

# Max concurrent per-image size encodes. Each AVIF variant runs its own
# SSIMULACRA2 binary search (the bottleneck); the search is sequential but the
# sizes are independent, so they run in parallel up to this bound. Not part of
# the env hash (a runtime perf knob, doesn't affect output).
__avif_jobs="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)"

# Self-optimisation. Every encode is appended to __encode_log, and at the end of
# a run q_regression.py re-fits the seed model from it and rewrites
# __seed_model, which the next run reads back — so the search starts closer to
# the answer the more this site is built.
#
# The raw log is disposable and gitignored (it grows without bound and is
# machine-local); the fitted model is four numbers and is committed, so a fresh
# clone inherits a converged search instead of relearning it.
#
# Neither file can change an output byte: they only choose where the search
# starts, and every candidate is still verified against the real SSIMULACRA2
# target. Both are plain shell variables, never exported — the .hash fingerprint
# comes from `printenv`, so exporting them would invalidate every cached encode.
__encode_log='src/encode-log.tsv'
__seed_model='src/q-model.env'

# Refit cadence, in new encodes. 1 means every single encode re-fits the model,
# which is what the measurements support: a refit is ~30ms (~53ms at a 20k-row
# log), almost all of it Python startup, against ~37s for the encode that
# triggers it — 0.08%. Refits are also lock-guarded, so when a dozen encodes
# finish at once only one fits and the rest skip for ~3ms.
#
# The payoff is that the search adapts continuously instead of in steps: every
# output learns from every output before it, including ones still being encoded
# in sibling subshells, since __avif_seed re-reads the model per output.
# 0 disables mid-build refits (the start- and end-of-build ones still happen).
__refit_interval="${__refit_interval_override:-1}"

# Starting-quality model for the SSIMULACRA2 search: q ~= a + b*ln(width),
# fit by least squares over a corpus of prior encodes (see q_regression.py).
# The normal ladder targets a fixed score so q is nearly flat (b ~= 0); the -hq
# ladder needs more bits at larger widths so q climbs with ln(width). These
# only seed the search — it still verifies every candidate against the true
# SSIMULACRA2 target, so the chosen q (and every output byte) is independent of
# them. Like __avif_jobs, a pure perf knob: kept out of __ENVIRONMENT_LIST so
# it never enters the env hash and a re-fit doesn't invalidate existing files.
__avif_seed_a='48.6'
__avif_seed_b='-0.84'
__avif_seed_hq_a='51.6'
__avif_seed_hq_b='4.43'

# Per-subsampling seeds, filled in by the fitted model when it has enough data for
# a mode. 4:2:0 photographs and 4:4:4 screenshots sit on different curves — on this
# corpus the normal-variant intercept differs by ~15 quality points — so one line
# through both starts the 4:4:4 searches far from the answer. Empty means "no fit
# for this mode yet"; __avif_seed then falls back to the pair above.
__avif_seed_420_a=''
__avif_seed_420_b=''
__avif_seed_444_a=''
__avif_seed_444_b=''
__avif_seed_hq_420_a=''
__avif_seed_hq_420_b=''
__avif_seed_hq_444_a=''
__avif_seed_hq_444_b=''

# First-step slopes for the secant search, in SSIMULACRA2 points per quality
# point, measured by sweeping quality on one photograph and one screenshot:
#
#   photo 4:2:0 near score 65 (q50-60)   1.0 - 1.5
#   photo 4:2:0 near score 85 (q80-90)   0.33 - 0.45
#   screenshot 4:4:4, whole range        0.19 - 0.29
#
# Only the *first* step uses these; from the second probe on, the search uses the
# secant through this image's own two measurements, which beats any table. Being
# wrong here costs a probe, never an output byte.
__avif_slope_normal='1.2'
__avif_slope_hq='0.4'
__avif_slope_444_normal='0.25'
__avif_slope_444_hq='0.2'

########################################
# Default Options
########################################

__PROCESS_JPEG=true
__depends__PROCESS_JPEG=(JPEG_RESCALE JPEG_CONVERT_LOSSLESS)
# false/auto
__JPEG_RESCALE=auto
__depends__JPEG_RESCALE=(JPEG_RESCALE_THRESHOLD)
# for auto, in KP
__JPEG_RESCALE_THRESHOLD=2000
__JPEG_CONVERT_LOSSLESS=false

__PROCESS_PNG=true
__depends__PROCESS_PNG=(PNG_RESCALE PNG_CONVERT_LOSSLESS)
# false/auto
__PNG_RESCALE=auto
__depends__PNG_RESCALE=(PNG_RESCALE_THRESHOLD)
# for auto, in KP
__PNG_RESCALE_THRESHOLD=2000
__PNG_CONVERT_LOSSLESS=true

__PROCESS_SCRIPT=false

__AVIF_QUALITY='45'
__AVIF_SIZES=''
__RESCALE_FILTER='Welsh'

# Encoder effort, passed to `avifenc -s`: 0 is slowest and smallest, 10 fastest
# and largest. Measured on a 1280px photo at a fixed SSIMULACRA2 target, speed 0
# is ~13% smaller than speed 6 and ~15% smaller than what ImageMagick/libheif
# produced, at roughly 10x the encode time. This replaced AVIF_PRESET, which set
# `heic:preset=placebo` — a define ImageMagick silently ignores (identical bytes
# with the preset unset, or set to a nonsense value), so it never bought
# anything.
__AVIF_SPEED='0'

# Chroma subsampling: 420 halves the chroma planes, 444 keeps them full. 420 is
# right for photographs, where the loss is invisible; 444 is right for
# screenshots, plots and UI captures, where hard coloured edges and small text
# sit exactly where 420 blurs. Measured on a Grafana capture: 444 reached the
# same SSIMULACRA2 in ~6% fewer bytes *and* held the edges better, so for
# synthetic content it wins on both axes.
#
# 'auto' decides per source, because directories here are mixed — a post can hold
# both photographs and a screenshot of a spreadsheet. '420' or '444' forces one.
__AVIF_SUBSAMPLING='auto'

# How 'auto' decides: the share of the image occupied by its single most common
# colour. Screenshots have a flat background and score high (measured here:
# 66-97%); photographs have none and score low (2.5-4%). An order of magnitude
# of daylight between the two, so the threshold is not delicate. Unique-colour
# count was tried first and is useless — dark photos have as few colours as a
# screenshot does.
__AVIF_SUBSAMPLING_THRESHOLD='25'

# Perceptual-quality targeting. When AVIF_SSIMULACRA2 is non-empty, each AVIF
# output is encoded at the *lowest* quality (binary-searched in
# [AVIF_QUALITY_MIN, AVIF_QUALITY_MAX]) whose decoded result scores at least
# this SSIMULACRA2 value against the losslessly-resized source. This overrides
# the fixed AVIF_QUALITY and keeps perceived quality constant across images and
# sizes (a fixed quality number drifts with content and encoder version).
# The `ssimulacra2` binary is a required dependency of this script.
# Default-on globally at 75 (high quality); a .env opts out with
# AVIF_SSIMULACRA2='' to fall back to the fixed AVIF_QUALITY.
__AVIF_SSIMULACRA2='65'
__AVIF_QUALITY_MIN='30'
__AVIF_QUALITY_MAX='85'

# High-quality companion. When non-empty, every AVIF output also gets a `-hq`
# sibling (<stem>-hq-<width>.avif / <stem>-hq.avif) encoded to this higher
# SSIMULACRA2 target — a high-quality version for full-resolution viewing,
# kept separate from the bandwidth-tuned ladder. The -hq search uses a quality
# ceiling of 99 (the normal AVIF_QUALITY_MAX is too low to reach this); 100 is
# avoided because libheif/AOM switches to lossless mode there, which conflicts
# with the chroma-deltaq the placebo preset enables and aborts the encode. 85 is
# "artifacts very hard to spot even at full size"; above ~85 the curve gets
# steep for little perceptual gain.
__AVIF_HQ_SSIMULACRA2='85'

# Named width ladder, exported only while a .env is being sourced so a .env can
# opt into the responsive set without repeating the numbers:
#   AVIF_SIZES="${SIZES_DEFAULT}"
# A single ladder serves both content-column and full-width images: it brackets
# the display sizes of both across pixel densities, the per-image `sizes`
# attribute decides which rungs are actually fetched, and __effective_sizes
# drops rungs at/above each image's native width (folding them into the always-
# emitted native variant), so the list self-trims and is safe everywhere.
#
# It is the union of two intents, so coverage is tight at every density:
#   - device/viewport widths (full-width images): 400 640 960 1280 1920 2560 3840
#   - content-column multiples (860px col x .5/1/1.5/2/2.5/3): 432 864 1296 1728 2160 2592
# The two 1280/1296 and 2560/2592 near-pairs are kept deliberately (device vs
# content-multiple); the few extra KB are intentional for exact coverage.
__SIZES_DEFAULT='400,432,640,864,960,1280,1296,1728,1920,2160,2560,2592,3840'

__SIZE_LADDERS='SIZES_DEFAULT'

__ENVIRONMENT_LIST='PROCESS_JPEG
PROCESS_PNG
PROCESS_SCRIPT
JPEG_RESCALE
JPEG_RESCALE_THRESHOLD
JPEG_CONVERT_LOSSLESS
PNG_RESCALE
PNG_RESCALE_THRESHOLD
PNG_CONVERT_LOSSLESS
AVIF_QUALITY
AVIF_SPEED
AVIF_SUBSAMPLING
AVIF_SUBSAMPLING_THRESHOLD
AVIF_SIZES
AVIF_SSIMULACRA2
AVIF_QUALITY_MIN
AVIF_QUALITY_MAX
AVIF_HQ_SSIMULACRA2
RESCALE_FILTER'

###############################################################################
# Functions
###############################################################################

__fatal_error_handler() {
    if [ "${__fatal_error}" == 'true' ]; then
        echo 'Fatal Error: Exiting'
        exit 1
    fi || exit 1
}

########################################
# __set_env <env file>
########################################
#
# Set Environment
# Sets the environment from a file
#
########################################

__set_env() {

    while read -r __line; do
        __varname="$(sed 's/^/__/' <<<"${__line}")"
        export "${__line}=${!__varname}"
    done <<<"${__ENVIRONMENT_LIST}"

    # Expose named ladders for reference inside the .env. They are not part of
    # __ENVIRONMENT_LIST, so the cleanup pass below unsets them afterwards and
    # they never enter the env hash (only the resolved AVIF_SIZES value does).
    while read -r __line; do
        __varname="$(sed 's/^/__/' <<<"${__line}")"
        export "${__line}=${!__varname}"
    done <<<"${__SIZE_LADDERS}"

    if [ "${#}" -gt 0 ]; then
        set -o allexport
        source "${1}"
        set +o allexport
    fi

    while read -r __line; do
        if ! [ "${__line}" == "" ]; then
            unset "${__line}"
        fi
    done <<<"$(printenv | sed 's/^\([^=]*\)=.*/\1/' | grep -Fxv "${__ignore_variables}" | grep -Fxv "${__ENVIRONMENT_LIST}")"

    __resolve_env

}

__resolve_env() {

    __old_hash=""
    __current_hash="$(__hash_env)"

    while [ "${__old_hash}" != "${__current_hash}" ]; do

        while read -r __check_set; do
            if [ "${!__check_set}" == 'false' ]; then
                eval "__arr=\"\${__depends__${__check_set}[@]}\""
                for __item in ${__arr[@]}; do
                    if ! [ "${!__item}" == 'false' ]; then
                        export "${__item}"='false'
                    fi
                done
            fi
        done < <(set | grep -e '^__depends__' | sed 's/^__depends__\([^=]*\)=.*/\1/')
        __old_hash="${__current_hash}"
        __current_hash="$(__hash_env)"

    done

    __need="$(
        {
            while read -r __check_set; do
                if ! [ "${!__check_set}" == 'false' ]; then
                    eval "__arr=\"\${__depends__${__check_set}[@]}\""
                    for item in ${__arr[@]}; do
                        echo "${item}"
                    done
                fi
            done < <(set | grep -e '^__depends__' | sed 's/^__depends__\([^=]*\)=.*/\1/')
            while read -r __item; do
                if ! [ "${!__item}" == 'false' ]; then
                    echo "${__item}"
                fi
            done <<<"${__ENVIRONMENT_LIST}"
        } | sort | uniq
    )"

    __does_not_exist="$(grep -Fxv "${__ENVIRONMENT_LIST}" <<<"${__need}")"
    if [ "${__does_not_exist}" != "" ]; then
        echo 'Error:'
        echo "${__does_not_exist}"
        echo 'Does not exist!
'
    fi

    while read -r __unset; do
        if [ "${__unset}" != "" ]; then
            unset "${__unset}"
        fi
    done < <(__print_env | sed -e 's/^\([^=]*\)=.*/\1/' | grep -Fxv "${__need}")

}

########################################
# __print_env
########################################
#
# Print Environment
# Prints the environment
#
########################################

__print_env() {

    printenv | grep -xvf <(sed 's|\(.*\)|^\1=.*|' <<<"${__ignore_variables}") | sort

}

########################################
# __hash_env
########################################
#
# Hash Environment
# Hashes the environment
#
########################################

__hash_env() {

    __print_env | "${__hashfunc}" - | sed 's/ .*//'

}

########################################
# __clear_env
########################################
#
# Clear Environment
# Clears the environment
#
########################################

__clear_env() {

    while read -r __var; do
        unset "${__var}"
    done <<<"${__ENVIRONMENT_LIST}"

}

__unset_unused() {
    while read -r __var; do
        #local "${__var}"
        if [ "${__var}" != "__PROCESS_$(echo "${1}" | tr '[:lower:]' '[:upper:]')" ]; then
            eval "${__var#__}"='false'
        fi
    done < <(set | grep -E '^__PROCESS_' | sed 's/^\([^=]*\)=.*/\1/')

    __resolve_env
}

###############################################################################
# Reference gating
###############################################################################
#
# Only images something actually points at are worth encoding or keeping. The
# reference corpus is every file that can name an image:
#
#   content/**/*.{md,html}   posts and pages (excluding */src/, which holds the
#                            sources and generator scripts themselves — a
#                            script mentioning its own output is not a
#                            reference to it)
#   layouts/**               site templates, e.g. _partials/home/avatar.html,
#                            which builds "media/avatar-<width>.avif" at render
#                            time
#   config.toml              params naming site images
#
# A source is referenced when the corpus contains its *page-relative stem* —
# `media/demo/DSC_3587` for content/posts/web-nice-things/media/src/DSC_3587.JPG
# — followed by a non-word character. Matching on the stem rather than on whole
# filenames deliberately catches every way a reference is written:
#
#   {{< image src="media/photo.avif" >}}        the logical name
#   ![alt](media/photo-4032.avif)               a ladder rung by name
#   {{< filesize "media/photo-hq-5568.avif" >}} an -hq rung
#   print "media/avatar-" $w ".avif"            a name built in a template
#
# and it is one-sided: an unrelated match keeps files that could have been
# dropped, it never drops files that are in use.
#
# Theme templates are not scanned (they live in the module cache and address
# site images through params, which config.toml covers). If a future template
# reaches for a content image by a name assembled from pieces too small to
# match, that image needs a mention in the corpus — or run with --no-gate.
#

########################################
# __build_reference_corpus
########################################
#
# Build Reference Corpus
# Concatenates the corpus into one temp file, once per run. Percent-escapes are
# decoded so a markdown link's `media/Screenshot%20from%202022.webp` matches the
# space in the real filename.
#
########################################

__build_reference_corpus() {

    __reference_corpus="$(mktemp)"

    {
        find './content/' -type f \( -iname '*.md' -o -iname '*.html' \) ! -path '*/src/*' -exec cat {} +
        find './layouts/' -type f -exec cat {} +
        cat './config.toml'

        # A generator script's declared dependencies are references too, and they
        # reach across units: make-quality-comparison.sh composites another
        # post's generated ../../smart-yogurt-maker-part-01/media/…-4032.avif
        # rungs. Without these, an image used only as a script input would be
        # pruned and the script would break on the next run.
        find './content/' -type f -iwholename '*/src/*.sh' | while IFS= read -r __script; do
            (
                cd "$(dirname "${__script}")/../" || exit 0
                "./src/$(basename "${__script}")" -d
            )
        done
    } 2>/dev/null | sed 's/%20/ /g' >"${__reference_corpus}"

}

########################################
# __page_prefix <output directory>
########################################
#
# Page Prefix
# Echoes the path of an output directory relative to the page that owns it, i.e.
# the prefix references are written with. Walks up to the nearest page bundle
# (a directory holding index.md / _index.md), stopping at ./content for images
# owned by the site root rather than by a post.
#
#   ./content/posts/web-nice-things/media/demo -> media/demo
#   ./content/media                            -> media
#
########################################

__page_prefix() {

    local __dir="${1%/}" __root

    __root="${__dir}"

    while [ "${__root}" != './content' ] && [ "${__root}" != '.' ] && [ "${__root}" != '/' ]; do
        if [ -e "${__root}/index.md" ] || [ -e "${__root}/_index.md" ]; then
            break
        fi
        __root="$(dirname "${__root}")"
    done

    if [ "${__dir}" == "${__root}" ]; then
        echo ''
    else
        echo "${__dir#"${__root}"/}"
    fi

}

########################################
# __reference <path>
########################################
#
# Reference
# Echoes the page-relative, extension-stripped name a given path is referred to
# by. Takes either a source under ./src/ or an output path in the current
# directory; both reduce to the same reference.
#
#   ./src/fob/pcb_back.jpg -> media/fob/pcb_back
#   ./photo.avif           -> media/lossless/photo
#
########################################

__reference() {

    local __path="${1#./}"

    __path="${__path#src/}"
    __path="${__path%.*}"

    if [ -n "${__current_page_prefix}" ]; then
        echo "${__current_page_prefix}/${__path}"
    else
        echo "${__path}"
    fi

}

########################################
# __is_referenced <path>
########################################
#
# Is Referenced
# True when the corpus points at the given source/output path. Always true
# outside the gate (./static/, or --no-gate), so callers need no special case.
#
########################################

__is_referenced() {

    local __ref __escaped

    if [ "${__reference_gate}" != 'true' ] || [ "${__gate_directory}" != 'true' ]; then
        return 0
    fi

    __ref="$(__reference "${1}")"

    # Escape ERE metacharacters in the stem; filenames here contain dots,
    # brackets and spaces. `/` is left alone (escaping it is undefined in ERE).
    __escaped="$(printf '%s' "${__ref}" | sed 's/[][\\.^$*+?(){}|]/\\&/g')"

    # Trailing non-word boundary so `media/photo` does not match `media/photo2`
    # while still matching `media/photo.avif`, `media/photo-800.avif` and the
    # template-built `media/photo-`.
    grep -qE "${__escaped}([^A-Za-z0-9_]|\$)" "${__reference_corpus}"

}

########################################
# __process <.env>
########################################
#
# Process
# Call this once situated in the correct
# directory to process
#
########################################

__process() {

    if [ "${PROCESS_SCRIPT}" == 'true' ]; then

        (
            __process_scripts -r

            __fatal_error_handler

            __process_scripts
        )
    fi

    if [ "${PROCESS_JPEG}" == 'true' ]; then
        (__process_generic_image jpeg)
    fi

    if [ "${PROCESS_PNG}" == 'true' ]; then
        (__process_generic_image png)
    fi

    # Last, so it sees the sources the script pass may just have written.
    if [ "${__prune}" == 'true' ] && [ "${__gate_directory}" == 'true' ]; then
        (__prune_outputs)
    fi

}

__find_jpeg() {
    find './src/' -type f \( -iname \*.jpg -o -iname \*.jpeg \)
}

__find_png() {
    find './src/' -type f \( -iname \*.png \)
}

########################################
# __effective_sizes <source>
########################################
#
# Effective Sizes
# Given AVIF_SIZES and a source image, echoes the widths to actually emit:
# every requested width smaller than the source's native width, plus always a
# single native-width entry (the 100% variant). Requested widths at or above
# native collapse into that one native entry, so there's no upscaling and no
# duplicate native-size files. A full-resolution variant is always produced so
# the served `media/` dir alone can satisfy a "view full image" link — the
# `src/` originals are not served. Both __process and __check_file use this so
# the emitted file set and the "is it current?" prediction stay in sync.
#
########################################

__effective_sizes() {

    local __native __size __dims __w __h __orient

    # Use the auto-oriented width: conversion applies -auto-orient, so a photo
    # with a rotating EXIF orientation (5-8) has its width/height swapped in the
    # output. Reading the stored width here would mislabel and, with a wide
    # ladder, duplicate the native variant.
    __dims="$(identify -format '%w %h %[orientation]\n' "${1}" 2>/dev/null | head -n1)"
    __w="${__dims%% *}"
    __h="$(echo "${__dims}" | cut -d' ' -f2)"
    __orient="${__dims##* }"

    case "${__orient}" in
        LeftTop | RightTop | RightBottom | LeftBottom) __native="${__h}" ;;
        *) __native="${__w}" ;;
    esac

    if [ -z "${__native}" ]; then
        echo "${AVIF_SIZES}" | tr ',' '\n' | sed '/^$/d'
        return
    fi

    while read -r __size; do
        if [ -z "${__size}" ]; then
            continue
        fi
        if [ "${__size}" -lt "${__native}" ]; then
            echo "${__size}"
        fi
    done < <(echo "${AVIF_SIZES}" | tr ',' '\n')

    # Always emit the native (100%) width.
    echo "${__native}"

}

########################################
# __avif_subsampling <source>
########################################
#
# AVIF Subsampling
# Echoes 420 or 444 for a given source. With AVIF_SUBSAMPLING set to 420 or 444
# that value is returned unchanged; 'auto' classifies the source by the share of
# it covered by its single most common colour (see AVIF_SUBSAMPLING_THRESHOLD).
#
# The probe is point-resampled down first: interpolation would invent colours and
# destroy the very signal being measured, while point sampling leaves a flat
# background flat. Called once per source, not once per ladder rung.
#
########################################

__avif_subsampling() {

    local __src="${1}" __top __px

    if [ "${AVIF_SUBSAMPLING}" != 'auto' ]; then
        echo "${AVIF_SUBSAMPLING}"
        return
    fi

    # Most common colour's pixel count, over a 500x500 point-sampled copy.
    __top="$(magick "${__src}" -filter point -resize '500x500>' -format %c histogram:info:- 2>/dev/null |
        sort -rn | head -n1 | awk '{print $1}')"
    __px="$(magick "${__src}" -filter point -resize '500x500>' -format '%[fx:w*h]' info: 2>/dev/null)"

    if [ -z "${__top}" ] || [ -z "${__px}" ] || [ "${__px}" -eq 0 ]; then
        echo '420'
        return
    fi

    awk -v t="${__top}" -v p="${__px}" -v thr="${AVIF_SUBSAMPLING_THRESHOLD}" \
        'BEGIN{print (100*t/p >= thr) ? "444" : "420"}'

}

########################################
# __log_encode <output> <width> <variant> <target> <quality> <probes>
########################################
#
# Log Encode
# Appends one row describing a finished encode. Written from parallel subshells,
# so it is a single short append — atomic in practice on every filesystem this
# runs on. The header is written once, when the file is created.
#
# Columns carry the encoder config (subsampling, speed) because a quality number
# only means something relative to them: mixing configs in one fit would produce
# a model that fits neither.
#
########################################

__log_encode() {

    local __out="${1}" __width="${2}" __variant="${3}" __target="${4}"
    local __quality="${5}" __probes="${6}" __score="${7:-}" __bytes

    if [ -z "${__encode_log_abs}" ]; then
        return
    fi

    if ! [ -e "${__encode_log_abs}" ]; then
        printf 'ts\tpath\tvariant\twidth\ttarget\tquality\tbytes\tprobes\tsubsampling\tspeed\tscore\n' \
            >>"${__encode_log_abs}"
    fi

    __bytes="$(wc -c <"${__out}" 2>/dev/null | tr -d ' ')"

    # The achieved score is recorded, not only the quality: it is what
    # separates "clamped at the ceiling but passed by a hair" from
    # "clamped and never got there", which quality alone cannot express.
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "${__out#./}" "${__variant}" "${__width}" \
        "${__target}" "${__quality}" "${__bytes:-0}" "${__probes}" \
        "${__source_subsampling:-${AVIF_SUBSAMPLING}}" "${AVIF_SPEED}" "${__score}" \
        >>"${__encode_log_abs}"

    __maybe_refit

}

########################################
# __maybe_refit
########################################
#
# Maybe Refit
# Re-fits the seed model mid-build once enough new encodes have accumulated.
# Called from __log_encode, so it runs inside whichever encode subshell finished
# last — which makes the concurrency the interesting part:
#
#   - A mkdir lock keeps one refit running at a time; losers skip rather than
#     queue, since the next encode will trigger one anyway.
#   - The row count at the last refit lives in a file, not a variable, because
#     subshells cannot hand state back to the parent.
#   - q_regression.py writes the model via temp + rename, so an encode reading
#     seeds never sees a half-written file.
#
########################################

__maybe_refit() {

    local __rows __last __lock __fit

    if [ "${__have_python}" != 'true' ] || [ "${__refit_interval}" -le 0 ]; then
        return
    fi

    __rows="$(wc -l <"${__encode_log_abs}" 2>/dev/null | tr -d ' ')"
    if [ -z "${__rows}" ]; then
        return
    fi

    __last=0
    if [ -e "${__refit_state}" ]; then
        __last="$(tr -d ' \n' <"${__refit_state}" 2>/dev/null)"
        [ -z "${__last}" ] && __last=0
    fi

    if [ "$((__rows - __last))" -lt "${__refit_interval}" ]; then
        return
    fi

    __lock="${__encode_log_abs}.lock"
    if ! mkdir "${__lock}" 2>/dev/null; then
        return
    fi

    echo "${__rows}" >"${__refit_state}"

    # In --quiet mode q_regression.py prints only when the coefficients actually
    # changed, so refitting after every encode stays silent until the model moves.
    __fit="$(python3 "${__repo_root}/q_regression.py" \
        --log "${__encode_log_abs}" --config "${__AVIF_SPEED}" \
        --emit "${__seed_model_abs}" --quiet 2>&1)"

    # To stderr, and as a single echo: this runs inside the command substitution
    # that captures __avif_make's chosen quality, so a stray stdout write would be
    # parsed as part of the quality number, and parallel encodes would interleave
    # half-lines.
    if [ -n "${__fit}" ]; then
        echo "  seed model: ${__fit}" >&2
    fi

    rmdir "${__lock}" 2>/dev/null

}

########################################
# __load_seed_model
########################################
#
# Load Seed Model
# Reads the committed coefficients over the built-in defaults. Parsed key by key
# against a whitelist rather than sourced, so a corrupt or hostile model file
# cannot run code or export anything into the env hash.
#
########################################

__load_seed_model() {

    local __line __key __value

    if ! [ -e "${__seed_model_abs}" ]; then
        return
    fi

    while IFS='=' read -r __key __value; do
        case "${__key}" in
            AVIF_SEED_A) __avif_seed_a="${__value}" ;;
            AVIF_SEED_B) __avif_seed_b="${__value}" ;;
            AVIF_SEED_HQ_A) __avif_seed_hq_a="${__value}" ;;
            AVIF_SEED_HQ_B) __avif_seed_hq_b="${__value}" ;;
            AVIF_SEED_420_A) __avif_seed_420_a="${__value}" ;;
            AVIF_SEED_420_B) __avif_seed_420_b="${__value}" ;;
            AVIF_SEED_444_A) __avif_seed_444_a="${__value}" ;;
            AVIF_SEED_444_B) __avif_seed_444_b="${__value}" ;;
            AVIF_SEED_HQ_420_A) __avif_seed_hq_420_a="${__value}" ;;
            AVIF_SEED_HQ_420_B) __avif_seed_hq_420_b="${__value}" ;;
            AVIF_SEED_HQ_444_A) __avif_seed_hq_444_a="${__value}" ;;
            AVIF_SEED_HQ_444_B) __avif_seed_hq_444_b="${__value}" ;;
        esac
    done <"${__seed_model_abs}"

}

########################################
# __refit_seed_model
########################################
#
# Refit Seed Model
# Re-fits the seed model from the accumulated log and rewrites the committed
# coefficients. Runs once, at the end of a build that produced encodes. Fits only
# rows matching the config just used, and q_regression.py declines to fit a
# variant with too few points, so a one-image build cannot wreck the model.
#
########################################

__refit_seed_model() {

    local __label="${1:-this build}"

    if [ "${__dry_run}" == 'true' ] || ! [ -e "${__encode_log_abs}" ]; then
        return
    fi

    if ! which python3 &>/dev/null; then
        echo 'Note: python3 not found; skipping seed-model refit.'
        return
    fi

    echo
    echo "Refitting quality-seed model from ${__label}:"
    # __AVIF_SPEED, not AVIF_SPEED: this runs after __clear_env, and filtering on
    # an unset variable silently matches nothing. A .env that overrides AVIF_SPEED
    # keeps its rows out of this fit, which is correct — a quality number only
    # means something relative to the speed it was found at.
    python3 "${__repo_root}/q_regression.py" \
        --log "${__encode_log_abs}" \
        --config "${__AVIF_SPEED}" \
        --emit "${__seed_model_abs}" 2>&1 | sed 's/^/  /'

}

########################################
# __avif_reference <source> <resize-spec-or-empty> <filter-or-empty> <output png>
########################################
#
# AVIF Reference
# Renders the exact pixels an AVIF output is made from: auto-oriented, resized to
# the target width, everything but the colour profile stripped, written
# losslessly. Both the quality search and the final encode work from this one
# file, so the pixels scored are the pixels shipped, and a resize happens once
# per output rather than once per probe.
#
# Only Exif/XMP/8BIM are dropped (`+profile '!icc,*'`); an ICC profile is kept
# and travels into the AVIF. Some sources here carry a display profile, so a
# blanket `-strip` would silently reinterpret their colour. Exif is dropped
# because it is pure passenger weight — 77KB per output on one of this site's
# photo sets, up to 94% of a small ladder rung — and because camera Exif carries
# serial numbers and GPS.
#
########################################

__avif_reference() {

    local __src="${1}" __resize="${2}" __filter="${3}" __out="${4}"
    local __opts=()

    if [ -n "${__resize}" ]; then
        __opts=("-resize" "${__resize}")
        if [ -n "${__filter}" ]; then
            __opts+=("-filter" "${__filter}")
        fi
    fi

    magick "${__src}" -auto-orient "${__opts[@]}" +profile '!icc,*' "${__out}"

}

########################################
# __avif_encode <reference png> <quality> <output>
########################################
#
# AVIF Encode
# The single place an AVIF is produced. libaom via avifenc rather than
# ImageMagick/libheif: it is the only front end here that exposes encoder effort
# (`-s`) and subsampling, and libheif's ignored preset left every encode at its
# default speed. Range is pinned to full to match what the pipeline has always
# emitted. The reference is already stripped, so --ignore-exif/--ignore-xmp are
# belt and braces for source formats magick hands through differently.
#
########################################

__avif_encode() {

    local __err

    # avifenc has no quiet flag, so its progress chatter is dropped — but its
    # stderr is captured rather than discarded and surfaced on failure. Silently
    # swallowing it once turned a bad flag into a cascade of "file not found" and
    # empty SSIMULACRA2 scores several layers away.
    __err="$(avifenc \
        -y "${__source_subsampling:-420}" -r full \
        -q "${2}" -s "${AVIF_SPEED}" \
        --ignore-exif --ignore-xmp \
        "${1}" "${3}" 2>&1 >/dev/null)"

    if ! [ -s "${3}" ]; then
        echo "Error: avifenc failed for ${3}" >&2
        [ -n "${__err}" ] && sed 's/^/  /' <<<"${__err}" >&2
        return 1
    fi

}

########################################
# __avif_slope <variant>
########################################
#
# AVIF Slope
# Echoes the expected SSIMULACRA2 gain per quality point for this source, used
# for the secant search's opening step. Picked by variant and by the source's
# resolved subsampling, since a 4:4:4 screenshot's curve is roughly five times
# flatter than a photograph's near the normal target.
#
########################################

__avif_slope() {

    local __variant="${1}" __name

    if [ "${__source_subsampling:-420}" == '444' ]; then
        __name="__avif_slope_444_${__variant}"
    else
        __name="__avif_slope_${__variant}"
    fi

    echo "${!__name:-1.0}"

}

########################################
# __avif_probe <quality>
########################################
#
# AVIF Probe
# Encodes __ref at the given quality and scores the decoded result against it
# with SSIMULACRA2. Returns 0 (success) iff the score meets __target. Reads
# __ref/__ta/__tp/__target from its caller via bash dynamic scoping, so it only
# takes the quality to try.
#
########################################

__avif_probe() {

    local __q="${1}"

    __probes=$((__probes + 1))
    __avif_encode "${__ref}" "${__q}" "${__ta}"
    magick "${__ta}" "${__tp}"

    # The score is left in __last_score for the caller. It used to be collapsed
    # straight into a pass/fail here, which threw away the one number that says
    # *how far* the probe missed — and so left the search stepping blind.
    __last_score="$(ssimulacra2 "${__ref}" "${__tp}")"

    awk "BEGIN{exit !(${__last_score} >= ${__target})}"

}

########################################
# __avif_seed <width> <variant>
########################################
#
# AVIF Seed
# Predicts a starting quality for the given output width and variant
# (normal|hq) from the q ~= a + b*ln(width) model. Clamped by the caller. Pure
# guess: the search verifies it, so a stale model only costs a few extra probes.
#
########################################

__avif_seed() {

    local __w="${1}" __variant="${2}" __a __b

    # Pick up any refit that landed since the last output, including one written
    # by a sibling encode subshell.
    __load_seed_model

    local __prefix='__avif_seed_'
    if [ "${__variant}" == 'hq' ]; then
        __prefix='__avif_seed_hq_'
    fi

    # Prefer the fit for this source's subsampling; fall back to the combined one
    # when that mode has not accumulated enough encodes to fit on its own.
    local __sub_a="${__prefix}${__source_subsampling:-}_a"
    local __sub_b="${__prefix}${__source_subsampling:-}_b"
    if [ -n "${__source_subsampling:-}" ] && [ -n "${!__sub_a}" ]; then
        __a="${!__sub_a}"
        __b="${!__sub_b}"
    else
        local __gen_a="${__prefix}a" __gen_b="${__prefix}b"
        __a="${!__gen_a}"
        __b="${!__gen_b}"
    fi

    awk "BEGIN{printf \"%d\", ${__a} + ${__b} * log(${__w}) + 0.5}"

}

########################################
# __avif_make <source> <resize-spec-or-empty> <filter-or-empty> <output>
#             [<target>] [<qmax>] [<variant>]
########################################
#
# AVIF Make
# Produces one AVIF output and echoes the quality it was encoded at. Without
# AVIF_SSIMULACRA2 set that quality is just AVIF_QUALITY. With it set, the
# quality is binary-searched in [AVIF_QUALITY_MIN, AVIF_QUALITY_MAX] for the
# lowest one whose decoded result scores at least the target SSIMULACRA2 value
# against the losslessly-resized source, i.e. the smallest file that still meets
# the perceptual bar.
#
# Search and final encode share one reference render (see __avif_reference), so
# the scored pixels are the shipped pixels and the resize is done once rather
# than once per probe.
#
# NOTE: the quality numbers here are libaom's via avifenc, which are NOT the
# libheif numbers this pipeline used before — a given number means a different
# quantizer. Only the SSIMULACRA2 targets are stable across that change, which is
# the point of targeting a score rather than a number. The __avif_seed model was
# fitted against libheif and is now merely a starting guess; re-run
# q_regression.py over the new encodes to make the search converge in fewer
# probes again.
#
########################################

__avif_make() {

    local __src="${1}" __resize="${2}" __filter="${3}" __out="${4}"
    local __target="${5:-${AVIF_SSIMULACRA2}}" __qmax="${6:-${AVIF_QUALITY_MAX}}" __variant="${7:-normal}"

    local __dir __ref __ta __tp __lo __hi __mid __best __width __seed __step __p
    local __probes=0 __last_score=""
    __dir="$(mktemp -d)"
    __ref="${__dir}/ref.png"
    __ta="${__dir}/t.avif"
    __tp="${__dir}/t.png"

    __avif_reference "${__src}" "${__resize}" "${__filter}" "${__ref}"

    if [ -z "${__target}" ]; then
        __avif_encode "${__ref}" "${AVIF_QUALITY}" "${__out}"
        __log_encode "${__out}" "$(identify -format '%w' "${__ref}" 2>/dev/null)" \
            "${__variant}" 'fixed' "${AVIF_QUALITY}" 0 ''
        rm -rf "${__dir}"
        echo "${AVIF_QUALITY}"
        return
    fi

    # Seed the search at the model's predicted quality for this reference's
    # actual width (read off the resized reference, so area/rescale specs and
    # full-size encodes all resolve correctly), clamped into the search range.
    # Read the reference's real width, retrying once: on a loaded machine
    # ImageMagick occasionally fails even a trivial identify, and this used to
    # fall back to a hard-coded 1280. That silently seeded the search for the
    # wrong size and, worse, wrote 1280 into the log as training data -- one
    # 3840px hq output was recorded as a 1280px one needing q=99, exactly the
    # kind of row that poisons a fit. Nothing is invented now: an unreadable
    # width means no seed (mid-range instead) and width 0 in the log, which
    # q_regression.py skips.
    __width="$(identify -format '%w' "${__ref}" 2>/dev/null)"
    if [ -z "${__width}" ]; then
        __width="$(identify -format '%w' "${__ref}" 2>/dev/null)"
    fi
    if [ -z "${__width}" ]; then
        echo "Warning: could not read reference width for ${__out}; seeding mid-range" >&2
        __width=0
    fi
    if [ "${__width}" -gt 0 ]; then
        __seed="$(__avif_seed "${__width}" "${__variant}")"
    else
        __seed=$(((AVIF_QUALITY_MIN + __qmax) / 2))
    fi
    [ "${__seed}" -lt "${AVIF_QUALITY_MIN}" ] && __seed="${AVIF_QUALITY_MIN}"
    [ "${__seed}" -gt "${__qmax}" ] && __seed="${__qmax}"

    # Damped secant search for the lowest quality meeting the target.
    #
    # The score is monotonic in quality, so this is a root-find on
    # (score(q) - target), and each probe reports not just pass/fail but how far
    # off it was. Dividing that miss by the local slope gives the step, which is
    # what a doubling gallop cannot do: the slope varies enormously by content
    # and target. Measured on this corpus, near SSIMULACRA2 65 a photograph moves
    # ~1.2 score points per quality point, near 85 only ~0.4, and a 4:4:4
    # screenshot ~0.2 — so the same +1 step is a sensible nudge in one case and a
    # near-no-op in another, which is why 4:4:4 searches were the most expensive.
    #
    # After two probes the slope comes from this image's own pair (a true secant)
    # rather than the table, so content-specific behaviour is picked up within a
    # single search.
    #
    # A bracket of (highest failing, lowest passing) is maintained throughout and
    # every proposal is clamped inside it, so this cannot diverge or oscillate;
    # if a proposal repeats a probed quality the bracket is bisected instead. The
    # search ends when the bracket is adjacent — which *proves* minimality, and is
    # the same answer the old gallop returned, so outputs and .hash files are
    # unchanged. Only the number of probes differs.
    local __lo_fail=$((AVIF_QUALITY_MIN - 1))
    local __hi_pass=$((__qmax + 1))
    local __prev_q='' __prev_s='' __iter=0 __slope __next __best_score=''

    __best="${__qmax}"
    __q="${__seed}"

    while [ "${__iter}" -lt 20 ]; do

        __iter=$((__iter + 1))

        if __avif_probe "${__q}"; then
            __hi_pass="${__q}"
            __best="${__q}"
            __best_score="${__last_score}"
        else
            __lo_fail="${__q}"
        fi

        # Adjacent bracket: __hi_pass passes, the quality below it fails. Done.
        if [ "$((__hi_pass - __lo_fail))" -le 1 ]; then
            break
        fi

        # Boundaries: the floor already passes, or the ceiling still fails. The
        # latter keeps __best at __qmax, matching the previous search.
        if [ "${__hi_pass}" -le "${AVIF_QUALITY_MIN}" ] || [ "${__lo_fail}" -ge "${__qmax}" ]; then
            break
        fi

        # Slope: this image's own secant once two probes disagree, otherwise the
        # measured default for this variant and subsampling. A non-positive
        # secant means noise rather than signal, so fall back to the table.
        __slope="$(__avif_slope "${__variant}")"
        if [ -n "${__prev_q}" ] && [ "${__prev_q}" != "${__q}" ]; then
            __slope="$(awk -v s1="${__prev_s}" -v s2="${__last_score}" \
                -v q1="${__prev_q}" -v q2="${__q}" -v fb="${__slope}" \
                'BEGIN{d=(s2-s1)/(q2-q1); print (d > 0.01) ? d : fb}')"
        fi

        # Damped so a convex curve does not overshoot, and always at least one
        # step in the direction of the miss.
        __next="$(awk -v q="${__q}" -v s="${__last_score}" -v t="${__target}" -v m="${__slope}" \
            'BEGIN{
                d = 0.8 * (t - s) / m;
                if (d > 0 && d < 1) d = 1;
                if (d < 0 && d > -1) d = -1;
                printf "%d", q + (d > 0 ? d + 0.5 : d - 0.5);
            }')"

        # Keep the proposal strictly inside the bracket.
        [ "${__next}" -le "${__lo_fail}" ] && __next=$((__lo_fail + 1))
        [ "${__next}" -ge "${__hi_pass}" ] && __next=$((__hi_pass - 1))

        # A repeat would waste a probe; bisect what is left instead.
        if [ "${__next}" -eq "${__q}" ]; then
            __next=$(((__lo_fail + __hi_pass) / 2))
            if [ "${__next}" -eq "${__q}" ]; then
                break
            fi
        fi

        __prev_q="${__q}"
        __prev_s="${__last_score}"
        __q="${__next}"

    done

    # Encode the deliverable at the quality the search settled on. The last probe
    # is not necessarily the winning one, so this is a real encode rather than a
    # copy of whatever __ta happens to hold.
    __avif_encode "${__ref}" "${__best}" "${__out}"

    __log_encode "${__out}" "${__width}" "${__variant}" "${__target}" "${__best}" \
        "${__probes}" "${__best_score}"

    rm -rf "${__dir}"
    echo "${__best}"

}

__process_generic_image() {

    __set_env './src/.env'

    __unset_unused "${1}"

    "__find_${1}" | while IFS= read -r __source_file; do

        # Nothing points at it: don't spend an encode on it. __prune_outputs
        # clears out anything it produced on an earlier run.
        if ! __is_referenced "${__source_file}"; then
            echo "Unreferenced, skipping: ${__source_file}"
            continue
        fi

        export FILE_HASH="$("${__hashfunc}" "${__source_file}")"

        if ! __check_file "${__source_file}"; then

            # Classify once per source rather than per ladder rung: the probe
            # reads a histogram, and every rung of one source gets the same
            # answer anyway. Plain variable, so the parallel encode subshells
            # below inherit it without it reaching the env hash.
            __source_subsampling="$(__avif_subsampling "${__source_file}")"

            __img_rescale="$(echo "${1}" | tr '[:lower:]' '[:upper:]')_RESCALE"
            __img_rescale_threshold="$(echo "${1}" | tr '[:lower:]' '[:upper:]')_RESCALE_THRESHOLD"
            __img_convert_lossless="$(echo "${1}" | tr '[:lower:]' '[:upper:]')_CONVERT_LOSSLESS"

            __output_format='avif'
            if [ "${!__img_convert_lossless}" == 'true' ]; then
                __output_format='webp'
            fi

            __target="$(sed -e 's|^\./src/|./|' -e "s/[^\.]*$/${__output_format}/" <<<"${__source_file}")"

            if [ "${__dry_run}" == 'true' ]; then
                echo "Would process: ${__target}"
                unset FILE_HASH
                continue
            fi

            echo "Processing: ${__target}"

            echo "$(__hash_env)" >"$(__get_hash_file "${__source_file}")"

            __target_dir="$(dirname "${__target}")"

            mkdir -p "${__target_dir}"

            if [ -e "${__target}" ]; then
                rm "${__target}"
            fi

            __print_env

            __lossless=false
            if [ "${!__img_convert_lossless}" == 'true' ] && [ "${__output_format}" == 'webp' ]; then
                __lossless=true
            fi

            # The size ladder applies only to lossy AVIF. Lossless WebP always
            # emits a single full-size image (with optional auto-rescale), as do
            # AVIF outputs when no AVIF_SIZES ladder is configured.
            if [ "${__lossless}" == 'true' ] || [ -z "${AVIF_SIZES}" ]; then
                __resize=''
                __resize_opts=()
                if [ "${!__img_rescale}" == 'auto' ] && [ "$(identify -format '(%w*%h)/1000\n' "${__source_file}" | bc)" -gt "${!__img_rescale_threshold}" ]; then
                    __resize="$((__img_rescale_threshold * 1000))@>"
                    __resize_opts=("-resize" "${__resize}" "-filter" "${RESCALE_FILTER}")
                fi
                if [ "${__lossless}" == 'true' ]; then
                    magick "${__source_file}" -auto-orient -quality 100 -define "webp:lossless=true" -define "webp:method=6" "${__resize_opts[@]}" +profile '!icc,*' "${__target}"
                else
                    __q="$(__avif_make "${__source_file}" "${__resize}" "${RESCALE_FILTER}" "${__target}")"
                    echo "  ${__target} q=${__q}"
                    if [ -n "${AVIF_HQ_SSIMULACRA2}" ]; then
                        __thq="${__target%.avif}-hq.avif"
                        __qhq="$(__avif_make "${__source_file}" "${__resize}" "${RESCALE_FILTER}" "${__thq}" "${AVIF_HQ_SSIMULACRA2}" 99 hq)"
                        echo "  ${__thq} q=${__qhq}"
                    fi
                fi
            else
                # Sizes are independent: run their searches/encodes in parallel,
                # bounded to __avif_jobs (sliding window; bash-3.2-safe wait).
                # Largest first (descending) so the longest jobs start earliest,
                # minimizing makespan instead of trailing behind small ones.
                __pids=()
                while read -r __size; do
                    (
                        # No -filter here, matching every rung generated to date:
                        # the ladder has always used magick's default resampling,
                        # and RESCALE_FILTER applies to the auto-rescale path only.
                        __vtarget="$(sed -e 's|^\./src/|./|' -e "s/\.[^\.]*$/-${__size}.${__output_format}/" <<<"${__source_file}")"
                        __vq="$(__avif_make "${__source_file}" "${__size}>" '' "${__vtarget}")"
                        echo "  ${__vtarget} q=${__vq}"
                        if [ -n "${AVIF_HQ_SSIMULACRA2}" ]; then
                            __vhq="$(sed -e 's|^\./src/|./|' -e "s/\.[^\.]*$/-hq-${__size}.${__output_format}/" <<<"${__source_file}")"
                            __vqhq="$(__avif_make "${__source_file}" "${__size}>" '' "${__vhq}" "${AVIF_HQ_SSIMULACRA2}" 99 hq)"
                            echo "  ${__vhq} q=${__vqhq}"
                        fi
                    ) &
                    __pids+=("${!}")
                    if [ "${#__pids[@]}" -ge "${__avif_jobs}" ]; then
                        wait "${__pids[0]}"
                        __pids=("${__pids[@]:1}")
                    fi
                done < <(__effective_sizes "${__source_file}" | sort -rn)
                wait
            fi

        fi

        unset FILE_HASH

    done

}

########################################
# __process_scripts <-r>
########################################
#
# Process
# Call this to process scripts, or call
# with '-r' to check required programs
#
########################################
########################################
# __script_is_referenced <script>
########################################
#
# Script Is Referenced
# True when a generator script is worth running: any of its declared targets is
# referenced, or any target lands in ./src/ (making it a source for the image
# passes, whose own gating then decides — e.g. make-quality-comparison.sh writes
# PNGs into src/ that the PNG pass turns into the served WebPs).
#
########################################

__script_is_referenced() {

    local __target

    if [ "${__reference_gate}" != 'true' ] || [ "${__gate_directory}" != 'true' ]; then
        return 0
    fi

    while IFS= read -r __target; do
        if [ -z "${__target}" ]; then
            continue
        fi
        case "${__target}" in
            ./src/* | src/*) return 0 ;;
        esac
        if __is_referenced "${__target}"; then
            return 0
        fi
    done < <("${1}" -t)

    return 1

}

__process_scripts() {

    __unset_unused SCRIPT

    while IFS= read -r __source_file; do

        if ! __script_is_referenced "${__source_file}"; then
            if [ "${1}" != '-r' ]; then
                echo "Unreferenced, skipping: ${__source_file}"
            fi
            continue
        fi

        export FILE_HASH="$(
            {
                "${__hashfunc}" "${__source_file}"
                "${__source_file}" -d
                "${__source_file}" -d | sort | while read -r __file; do
                    "${__hashfunc}" "${__file}"
                done
            } | sort | "${__hashfunc}" -
        )"

        if ! __check_file "${__source_file}" "$("${__source_file}" -t)"; then

            if [ "${1}" == '-r' ]; then

                while read -r __program; do
                    if ! which "${__program}" &>/dev/null; then
                        echo "$(pwd)${__source_file:1} needs '${__program}'"
                        export __fatal_error='true'
                    fi
                done < <("${__source_file}" -r)

            elif [ "${__dry_run}" == 'true' ]; then

                echo "Would run: ${__source_file}"

            else

                echo "Running: ${__source_file}"
                echo "$(__hash_env)" >"$(__get_hash_file "${__source_file}")"

                __target_files="$("${__source_file}" -t)"

                "${__source_file}"

                while read -r __file; do
                    if ! [ -a "${__file}" ]; then
                        echo "Warning: $(pwd)${__source_file:1} failed to create ${__file}"
                    fi
                done <<<"${__target_files}"

            fi
        fi

        unset FILE_HASH

    done < <(find './src/' -type f \( -iname \*.sh \))

}

########################################
# __prune_outputs
########################################
#
# Prune Outputs
# Deletes generated files in this unit's output directories that the current
# sources and references no longer account for: outputs of a source nothing
# points at any more, leftovers of a source that has been deleted or renamed,
# ladder rungs from a since-narrowed AVIF_SIZES, and .hash files whose source is
# gone or unreferenced (so re-referencing later rebuilds cleanly).
#
# It works by *whitelist*, never by guessing which names look generated: the
# expected set is exactly __predict_targets for every referenced source plus the
# declared targets of every referenced script, and a candidate is deleted only if
# it is absent from that set. Reversing this — reducing a filename back to a stem
# by stripping -hq/-<width> — is ambiguous for a source that itself ends in
# -<digits>, and would risk deleting a live file.
#
# Deliberately narrow, so nothing outside the pipeline's own output can be hit:
#   - Candidates come only from output directories mirroring a directory in
#     ./src/, at depth 1 (so a nested unit with its own src/.env is left to its
#     own pass), and only with an extension this pipeline emits.
#   - Anything under ./src/ is a source and is never deleted; only its .hash
#     bookkeeping is.
#   - Declared targets of an unreferenced script are added as candidates
#     whatever their extension, since the script alone accounts for them.
#
########################################

__prune_outputs() {

    local __expected __candidates __source __script __target __directory __mirror

    __expected="$(mktemp)"
    __candidates="$(mktemp)"

    # Expected: every output of every referenced source.
    while IFS= read -r __source; do
        if [ -n "${__source}" ] && __is_referenced "${__source}"; then
            __predict_targets "${__source}" >>"${__expected}"
        fi
    done < <(
        __find_jpeg
        __find_png
    )

    # Expected: declared targets of referenced scripts. Unreferenced scripts
    # instead contribute their targets as candidates.
    while IFS= read -r __script; do
        if [ -z "${__script}" ]; then
            continue
        fi
        if __script_is_referenced "${__script}"; then
            "${__script}" -t >>"${__expected}"
        else
            "${__script}" -t >>"${__candidates}"
        fi
    done < <(find './src/' -type f \( -iname \*.sh \))

    # Candidates: pipeline-format files in the output directories mirroring
    # ./src/'s own directory tree.
    while IFS= read -r __directory; do

        __mirror=".${__directory#./src}"
        __mirror="${__mirror%/}"
        [ -z "${__mirror}" ] && __mirror='.'

        if ! [ -d "${__mirror}" ]; then
            continue
        fi

        # A nested directory carrying its own src/.env is a separate unit; its
        # own pass prunes it. (The current unit's own directory is exempt: it is
        # the one holding the src/.env being processed.)
        if [ "${__mirror}" != '.' ] && [ -e "${__mirror}/src/.env" ]; then
            continue
        fi

        find "${__mirror}" -maxdepth 1 -type f \( -iname \*.avif -o -iname \*.webp \) >>"${__candidates}"

    done < <(find './src' -type d)

    # Delete candidates the expected set does not account for.
    while IFS= read -r __target; do

        if [ -z "${__target}" ] || ! [ -e "${__target}" ]; then
            continue
        fi

        if grep -Fxq "${__target}" "${__expected}"; then
            continue
        fi

        if [ "${__dry_run}" == 'true' ]; then
            echo "Would delete: ${__target}"
        else
            echo "Deleting: ${__target}"
            rm -f "${__target}"
        fi

    done < <(sort -u "${__candidates}")

    # Stale bookkeeping: a .hash whose source is gone or unreferenced.
    while IFS= read -r __target; do

        if [ -z "${__target}" ]; then
            continue
        fi

        __source="${__target%.hash}"

        if [ -e "${__source}" ]; then
            # A script's own name is never referenced; ask what it produces.
            case "${__source}" in
                *.sh)
                    if __script_is_referenced "${__source}"; then
                        continue
                    fi
                    ;;
                *)
                    if __is_referenced "${__source}"; then
                        continue
                    fi
                    ;;
            esac
        fi

        if [ "${__dry_run}" == 'true' ]; then
            echo "Would delete: ${__target}"
        else
            echo "Deleting: ${__target}"
            rm -f "${__target}"
        fi

    done < <(find './src/' -type f -name \*.hash)

    rm -f "${__expected}" "${__candidates}"

}

########################################
# __get_hash_file <file>
########################################
#
# Get Hash File
# Returns the hash path for a given file
#
########################################

__get_hash_file() {
    echo "${1}.hash"
}

########################################
# __predict_targets <source>
########################################
#
# Predict Targets
# Echoes every output filename a given source produces under the current
# environment. The single source of truth for the emitted file set: __check_file
# asks it whether everything is present, and __prune_outputs asks it which files
# in a directory are meant to be there — so a file the pipeline would emit can
# never be mistaken for an orphan.
#
########################################

__predict_targets() {

    local __source="${1}" __filename __extension __output_format __targets

    __filename="$(basename -- "${__source}")"
    __extension="$(echo "${__filename##*.}" | tr '[:upper:]' '[:lower:]')"

    # Lossless conversion is per input type; anything else is lossy AVIF.
    __output_format='avif'
    if [ "${__extension}" == 'png' ] && [ "${PNG_CONVERT_LOSSLESS}" == 'true' ]; then
        __output_format='webp'
    elif [ "${__extension}" == 'jpg' ] || [ "${__extension}" == 'jpeg' ]; then
        if [ "${JPEG_CONVERT_LOSSLESS}" == 'true' ]; then
            __output_format='webp'
        fi
    fi

    # Sized targets only for lossy AVIF; lossless WebP is always single.
    if [ -z "${AVIF_SIZES}" ] || [ "${__output_format}" == 'webp' ]; then
        __targets="$(sed -e 's|^\./src/|./|' -Ee "s/\.[^\.]*$/.${__output_format}/" <<<"${__source}")"
    else
        __targets="$(
            while IFS= read -r __size; do
                sed -e 's|^\./src/|./|' -e "s/\.[^\.]*$/-${__size}.${__output_format}/" <<<"${__source}"
            done < <(__effective_sizes "${__source}")
        )"
    fi

    # Each AVIF target also has a -hq sibling when high-quality is enabled.
    if [ "${__output_format}" == 'avif' ] && [ -n "${AVIF_HQ_SSIMULACRA2}" ]; then
        __targets="${__targets}
$(sed -E 's/(-[0-9]+)?\.avif$/-hq\1.avif/' <<<"${__targets}")"
    fi

    sed '/^$/d' <<<"${__targets}"

}

########################################
# __check_file <source> [<target> ...]
########################################
#
# Check File
# Checks if a given file is current
#
########################################

__check_file() {

    __source="${1}"

    shift

    __hash_file="$(__get_hash_file "${__source}")"

    __targets=''

    if [ "${#}" == '0' ]; then

        __targets="$(__predict_targets "${__source}")"

    else

        until [ "${#}" == '0' ]; do

            __targets="${1}
${__targets}"

            shift

        done

    fi

    local __target

    while read -r __target; do

        if ! [ -e "${__target}" ]; then
            return 1
        fi

    done < <(sed '/^$/d' <<<"${__targets}")

    if [ -e "${__hash_file}" ]; then
        __file_hash="$(cat "${__hash_file}")"
        if [ "${__file_hash}" == "$(__hash_env)" ]; then
            return 0
        fi
    fi

    return 1

}

###############################################################################

__fatal_error_handler || exit 1

{

    pushd "$(dirname "${0}")"

    pushd ../

} &>/dev/null

###############################################################################

# Absolute paths for the self-optimisation files: processing pushd's into each
# unit directory, so relative paths would land wherever the loop happens to be.
__repo_root="$(pwd)"
__encode_log_abs="${__repo_root}/${__encode_log}"
__seed_model_abs="${__repo_root}/${__seed_model}"
__refit_state="${__encode_log_abs}.refit-at"

# The score column arrived after this log already had rows. Bring the header up to
# date so the fitter can see the new field; existing rows simply end one column
# short, which the parser tolerates because score is last.
if [ -e "${__encode_log_abs}" ] && ! head -n1 "${__encode_log_abs}" | grep -q 'score'; then
    awk 'NR==1 {print $0 "\tscore"; next} {print}' "${__encode_log_abs}" \
        >"${__encode_log_abs}.migrating" &&
        mv "${__encode_log_abs}.migrating" "${__encode_log_abs}"
fi

__have_python='false'
if which python3 &>/dev/null; then
    __have_python='true'
fi

# Refit before doing anything, so this run starts from every encode ever logged
# rather than from whatever the committed model last captured — a previous run
# that was interrupted after its last mid-build refit leaves data behind
# otherwise. Then load whatever that produced.
__refit_seed_model 'the accumulated log'
__load_seed_model

__build_reference_corpus

trap 'rm -f "${__reference_corpus}"; rmdir "${__encode_log_abs}.lock" 2>/dev/null' EXIT

find './content/' './static/' -type f -iwholename '*/src/.env' | while IFS= read -r __file; do

    __parent_directory="$(sed 's|src/.env$||' <<<"${__file}")"

    # Reference gating covers ./content/ only. ./static/ holds site assets
    # (favicons, the pinned-tab SVG) that the theme's head partials reference by
    # paths assembled outside this repo, so it is always built in full.
    case "${__file}" in
        ./content/*) __gate_directory='true' ;;
        *) __gate_directory='false' ;;
    esac

    __current_page_prefix="$(__page_prefix "${__parent_directory}")"

    __set_env "${__file}"

    pushd "${__parent_directory}" &>/dev/null

    __process "${__file}"

    popd &>/dev/null

    __clear_env

done

###############################################################################

# Final refit over everything this build produced, including the encodes that
# landed after the last mid-build refit.
__refit_seed_model

popd &>/dev/null

exit
