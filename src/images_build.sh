#!/bin/bash

###############################################################################

[ "$(env | /bin/sed -r -e '/^(PWD|SHLVL|_|PATH)=/d')" ] && exec -c $0

export PATH

###############################################################################

__hashfunc='sha256sum'

__needed_programs="${__hashfunc}
convert
identify
bc"

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

########################################
# Default Options
########################################

__PROCESS_JPEG=true
__depends__PROCESS_JPEG=(JPEG_RESCALE JPEG_CONVERT_LOSSLESS JPEG_TARGET_SIZE)
# false/auto
__JPEG_RESCALE=auto
__depends__JPEG_RESCALE=(JPEG_RESCALE_THRESHOLD)
# for auto, in KP
__JPEG_RESCALE_THRESHOLD=2000
__JPEG_CONVERT_LOSSLESS=false
__JPEG_TARGET_SIZE=true
__depends__JPEG_TARGET_SIZE=(JPEG_TARGET_SIZE_BYTES)
__JPEG_TARGET_SIZE_BYTES=150000

__PROCESS_PNG=true
__depends__PROCESS_PNG=(PNG_RESCALE PNG_CONVERT_LOSSLESS)
# false/auto
__PNG_RESCALE=auto
__depends__PNG_RESCALE=(PNG_RESCALE_THRESHOLD)
# for auto, in KP
__PNG_RESCALE_THRESHOLD=2000
__PNG_CONVERT_LOSSLESS=true
__PNG_TARGET_SIZE=false
__depends__PNG_TARGET_SIZE=(PNG_TARGET_SIZE_BYTES)
__PNG_TARGET_SIZE_BYTES=200000

__PROCESS_SCRIPT=false

__WEBP_METHOD='6'
__WEBP_QUALITY='50'

__ENVIRONMENT_LIST='PROCESS_JPEG
PROCESS_PNG
PROCESS_SCRIPT
JPEG_RESCALE
JPEG_RESCALE_THRESHOLD
JPEG_TARGET_SIZE
JPEG_TARGET_SIZE_BYTES
JPEG_CONVERT_LOSSLESS
PNG_RESCALE
PNG_RESCALE_THRESHOLD
PNG_TARGET_SIZE
PNG_TARGET_SIZE_BYTES
PNG_CONVERT_LOSSLESS
WEBP_METHOD
WEBP_QUALITY'

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
        if [ "${__var}" != "__PROCESS_${1^^}" ]; then
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

__process_generic_image() {

    __set_env './src/.env'

    __unset_unused "${1}"

    "__find_${1}" | while read -r __source_file; do

        export FILE_HASH="$("${__hashfunc}" "${__source_file}")"

        __target="$(sed -e 's|^\./src/|./|' -e 's/[^\.]*$/webp/' <<<"${__source_file}")"

        if ! __check_file "${__source_file}"; then

            echo "Processing: ${__target}"

            echo "$(__hash_env)" >"$(__get_hash_file "${__source_file}")"

            __target_dir="$(dirname "${__target}")"

            mkdir -p "${__target_dir}"

            if [ -e "${__target}" ]; then
                rm "${__target}"
            fi

            __img_rescale="${1^^}_RESCALE"
            __img_rescale_threshold="${1^^}_RESCALE_THRESHOLD"
            __img_convert_lossless="${1^^}_CONVERT_LOSSLESS"
            __img_convert_target_size="${1^^}_TARGET_SIZE"
            __img_convert_target_size_bytes="${1^^}_TARGET_SIZE_BYTES"

            __print_env

            __convert_options=("-auto-orient" "-quality" "${__WEBP_QUALITY}" "-define" "webp:method=${__WEBP_METHOD}")

            if [ "${!__img_convert_lossless}" == 'true' ]; then
                __convert_options+=("-define" "webp:lossless=true")
            fi

            if [ "${!__img_rescale}" == 'auto' ] && [ "$(identify -format '(%w*%h)/1000\n' "${__source_file}" | bc)" -gt "${!__img_rescale_threshold}" ]; then
                __convert_options+=("-resize" "$((__img_rescale_threshold * 1000))@>")
            fi

            convert "${__source_file}" ${__convert_options[@]} "${__target}"

            if [ "${!__img_convert_target_size}" == 'true' ] && [ "$(stat -c '%s' "${__target}")" -gt "${!__img_convert_target_size_bytes}" ] && ! [ "${!__img_convert_lossless}" == 'true' ]; then
                echo "File too large, resizing"
                rm "${__target}"
                __convert_options+=("-define" "webp:target-size=${!__img_convert_target_size_bytes}" "-define" "webp:pass=8")
                convert "${__source_file}" ${__convert_options[@]} "${__target}"
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

        __targets="$(sed -e 's|^\./src/|./|' -e 's/\(jpeg\|jpg\|png\)$/webp/' <<<"${__source_file}")"

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

find './content/' -type f -iwholename '*/src/.env' | while read -r __file; do

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
