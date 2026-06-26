#!/bin/bash

__pathfile='./.path'

###############################################################################

if ! [ -e "${__pathfile}" ]; then
    echo "${PATH}" >"${__pathfile}"
    [ "$(env | sed -r -e '/^(PWD|SHLVL|_|PATH)=/d')" ] && exec -c $0
fi

export PATH="$(cat "${__pathfile}")"
rm "${__pathfile}"

###############################################################################

__hashfunc='sha256sum'

__needed_programs="${__hashfunc}
magick
identify
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
__AVIF_PRESET='placebo'
__AVIF_SIZES=''
__RESCALE_FILTER='Welsh'

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
AVIF_PRESET
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
# __avif_probe <quality>
########################################
#
# AVIF Probe
# Encodes __src at the given quality (honouring __resize) and scores the
# decoded result against __ref with SSIMULACRA2. Returns 0 (success) iff the
# score meets __target. Reads __src/__resize/__ta/__tp/__ref/__target from its
# caller via bash dynamic scoping, so it only takes the quality to try.
#
########################################

__avif_probe() {

    local __q="${1}" __score

    if [ -n "${__resize}" ]; then
        magick "${__src}" -auto-orient -quality "${__q}" -define "heic:preset=${AVIF_PRESET}" -resize "${__resize}" "${__ta}"
    else
        magick "${__src}" -auto-orient -quality "${__q}" -define "heic:preset=${AVIF_PRESET}" "${__ta}"
    fi
    magick "${__ta}" "${__tp}"
    __score="$(ssimulacra2 "${__ref}" "${__tp}")"
    awk "BEGIN{exit !(${__score} >= ${__target})}"

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

    if [ "${__variant}" == 'hq' ]; then
        __a="${__avif_seed_hq_a}"
        __b="${__avif_seed_hq_b}"
    else
        __a="${__avif_seed_a}"
        __b="${__avif_seed_b}"
    fi

    awk "BEGIN{printf \"%d\", ${__a} + ${__b} * log(${__w}) + 0.5}"

}

########################################
# __avif_quality <source> <resize-spec-or-empty> [<target>] [<qmax>] [<variant>]
########################################
#
# AVIF Quality
# Echoes the AVIF quality to encode at. Without AVIF_SSIMULACRA2 set, this is
# just the fixed AVIF_QUALITY. With it set, binary-searches
# [AVIF_QUALITY_MIN, AVIF_QUALITY_MAX] for the lowest quality whose decoded
# output scores at least the target SSIMULACRA2 value against the source
# resized the same way (a lossless PNG reference), i.e. the smallest file that
# still meets the perceptual bar. <resize-spec> is the magick -resize argument
# the real encode will use (e.g. "800>"), or empty for no resize.
#
########################################

__avif_quality() {

    local __src="${1}" __resize="${2}" __target="${3:-${AVIF_SSIMULACRA2}}" __qmax="${4:-${AVIF_QUALITY_MAX}}" __variant="${5:-normal}"

    if [ -z "${__target}" ]; then
        echo "${AVIF_QUALITY}"
        return
    fi

    local __dir __ref __ta __tp __lo __hi __mid __best __width __seed __step __p
    __dir="$(mktemp -d)"
    __ref="${__dir}/ref.png"
    __ta="${__dir}/t.avif"
    __tp="${__dir}/t.png"

    if [ -n "${__resize}" ]; then
        magick "${__src}" -auto-orient -resize "${__resize}" "${__ref}"
    else
        magick "${__src}" -auto-orient "${__ref}"
    fi

    # Seed the search at the model's predicted quality for this reference's
    # actual width (read off the resized reference, so area/rescale specs and
    # full-size encodes all resolve correctly), clamped into the search range.
    __width="$(identify -format '%w' "${__ref}" 2>/dev/null)"
    [ -z "${__width}" ] && __width=1280
    __seed="$(__avif_seed "${__width}" "${__variant}")"
    [ "${__seed}" -lt "${AVIF_QUALITY_MIN}" ] && __seed="${AVIF_QUALITY_MIN}"
    [ "${__seed}" -gt "${__qmax}" ] && __seed="${__qmax}"

    # Exponential (gallop) search from the seed. The score is monotonic in
    # quality, so probing the seed tells us which way the lowest-passing quality
    # lies; we then double the step outward until we bracket it, and binary-
    # search the (small) remaining gap. This returns the exact same quality the
    # old midpoint binary search would have — only the probes taken differ — so
    # outputs and .hash files are unchanged; a good seed just trials fewer.
    __best="${__qmax}"
    if __avif_probe "${__seed}"; then
        # Seed meets the target: the lowest passing quality is at or below it.
        __best="${__seed}"
        __lo="${AVIF_QUALITY_MIN}"
        __hi=$((__seed - 1))
        __step=1
        while [ "${__lo}" -le "${__hi}" ]; do
            __p=$((__seed - __step))
            [ "${__p}" -lt "${AVIF_QUALITY_MIN}" ] && __p="${AVIF_QUALITY_MIN}"
            if __avif_probe "${__p}"; then
                __best="${__p}"
                __hi=$((__p - 1))
                [ "${__p}" -eq "${AVIF_QUALITY_MIN}" ] && break
                __step=$((__step * 2))
            else
                __lo=$((__p + 1))
                break
            fi
        done
    else
        # Seed misses: the lowest passing quality (if any) is above it.
        __lo=$((__seed + 1))
        __hi="${__qmax}"
        __step=1
        while [ "${__lo}" -le "${__hi}" ]; do
            __p=$((__seed + __step))
            [ "${__p}" -gt "${__qmax}" ] && __p="${__qmax}"
            if __avif_probe "${__p}"; then
                __best="${__p}"
                __hi=$((__p - 1))
                break
            else
                __lo=$((__p + 1))
                # Even qmax misses: nothing meets the target, keep best=qmax
                # (matching the old search) and skip the binary pass.
                [ "${__p}" -eq "${__qmax}" ] && { __lo=1; __hi=0; break; }
                __step=$((__step * 2))
            fi
        done
    fi

    # Binary-search whatever gap the gallop left bracketed.
    while [ "${__lo}" -le "${__hi}" ]; do
        __mid=$(((__lo + __hi) / 2))
        if __avif_probe "${__mid}"; then
            __best="${__mid}"
            __hi=$((__mid - 1))
        else
            __lo=$((__mid + 1))
        fi
    done

    rm -rf "${__dir}"
    echo "${__best}"

}

__process_generic_image() {

    __set_env './src/.env'

    __unset_unused "${1}"

    "__find_${1}" | while read -r __source_file; do

        export FILE_HASH="$("${__hashfunc}" "${__source_file}")"

        if ! __check_file "${__source_file}"; then

            __img_rescale="$(echo "${1}" | tr '[:lower:]' '[:upper:]')_RESCALE"
            __img_rescale_threshold="$(echo "${1}" | tr '[:lower:]' '[:upper:]')_RESCALE_THRESHOLD"
            __img_convert_lossless="$(echo "${1}" | tr '[:lower:]' '[:upper:]')_CONVERT_LOSSLESS"

            __output_format='avif'
            if [ "${!__img_convert_lossless}" == 'true' ]; then
                __output_format='webp'
            fi

            __target="$(sed -e 's|^\./src/|./|' -e "s/[^\.]*$/${__output_format}/" <<<"${__source_file}")"

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
                    magick "${__source_file}" -auto-orient -quality 100 -define "webp:lossless=true" -define "webp:method=6" "${__resize_opts[@]}" "${__target}"
                else
                    __q="$(__avif_quality "${__source_file}" "${__resize}")"
                    echo "  ${__target} q=${__q}"
                    magick "${__source_file}" -auto-orient -quality "${__q}" -define "heic:preset=${AVIF_PRESET}" "${__resize_opts[@]}" "${__target}"
                    if [ -n "${AVIF_HQ_SSIMULACRA2}" ]; then
                        __thq="${__target%.avif}-hq.avif"
                        __qhq="$(__avif_quality "${__source_file}" "${__resize}" "${AVIF_HQ_SSIMULACRA2}" 99 hq)"
                        echo "  ${__thq} q=${__qhq}"
                        magick "${__source_file}" -auto-orient -quality "${__qhq}" -define "heic:preset=${AVIF_PRESET}" "${__resize_opts[@]}" "${__thq}"
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
                        __vtarget="$(sed -e 's|^\./src/|./|' -e "s/\.[^\.]*$/-${__size}.${__output_format}/" <<<"${__source_file}")"
                        __vq="$(__avif_quality "${__source_file}" "${__size}>")"
                        echo "  ${__vtarget} q=${__vq}"
                        magick "${__source_file}" -auto-orient -quality "${__vq}" -define "heic:preset=${AVIF_PRESET}" "-resize" "${__size}>" "${__vtarget}"
                        if [ -n "${AVIF_HQ_SSIMULACRA2}" ]; then
                            __vhq="$(sed -e 's|^\./src/|./|' -e "s/\.[^\.]*$/-hq-${__size}.${__output_format}/" <<<"${__source_file}")"
                            __vqhq="$(__avif_quality "${__source_file}" "${__size}>" "${AVIF_HQ_SSIMULACRA2}" 99 hq)"
                            echo "  ${__vhq} q=${__vqhq}"
                            magick "${__source_file}" -auto-orient -quality "${__vqhq}" -define "heic:preset=${AVIF_PRESET}" "-resize" "${__size}>" "${__vhq}"
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
__process_scripts() {

    __unset_unused SCRIPT

    while read -r __source_file; do

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

        __filename="$(basename -- "${__source}")"

        if [ "${__filename##*.}" == 'png' ] && [ "${PNG_CONVERT_LOSSLESS}" == 'true' ]; then
            __output_format='webp'
        else
            __output_format='avif'
        fi

        # Sized targets only for lossy AVIF; lossless WebP is always single.
        if [ -z "${AVIF_SIZES}" ] || [ "${__output_format}" == 'webp' ]; then
            __targets="$(sed -e 's|^\./src/|./|' -Ee "s/\.(jpeg|jpg|png)$/.${__output_format}/" <<<"${__source_file}")"
        else
            __targets="$(
                while read -r __size; do
                    sed -e 's|^\./src/|./|' -e "s/\.[^\.]*$/-${__size}.${__output_format}/" <<<"${__source_file}"
                done < <(__effective_sizes "${__source_file}")
            )"
        fi

        # Each AVIF target also has a -hq sibling when high-quality is enabled.
        if [ "${__output_format}" == 'avif' ] && [ -n "${AVIF_HQ_SSIMULACRA2}" ]; then
            __targets="${__targets}
$(sed -E 's/(-[0-9]+)?\.avif$/-hq\1.avif/' <<<"${__targets}")"
        fi

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

find './content/' './static/' -type f -iwholename '*/src/.env' | while read -r __file; do

    __parent_directory="$(sed 's|src/.env$||' <<<"${__file}")"

    __set_env "${__file}"

    pushd "${__parent_directory}" &>/dev/null

    __process "${__file}"

    popd &>/dev/null

    __clear_env

done

###############################################################################

popd &>/dev/null

exit
