#!/bin/bash

[ "$(env | /bin/sed -r -e '/^(PWD|SHLVL|_)=/d')" ] && exec -c $0

###############################################################################
# Variables
###############################################################################

__ignore_variables='PWD
SHLVL
_
OLDPWD'

########################################
# Default Options
########################################

__global_scale='40'

__PROCESS_JPEG=true
__depends__PROCESS_JPEG=(JPEG_OPTIMIZE JPEG_RESCALE)
__JPEG_OPTIMIZE=true
__JPEG_RESCALE=true
__depends__JPEG_RESCALE=(JPEG_SCALE JPEG_QUALITY)
__JPEG_QUALITY=40
__JPEG_SCALE="${__global_scale}"

__PROCESS_PNG=true
__depends__PROCESS_PNG=(PNG_OPTIMIZE PNG_RESCALE)
__PNG_OPTIMIZE=false
__depends__PNG_OPTIMIZE=(PNG_EFFORT)
__PNG_EFFORT=9
__PNG_RESCALE=true
__depends__PNG_RESCALE=(PNG_SCALE)
__PNG_SCALE="${__global_scale}"

__ENVIRONMENT_LIST='JPEG_QUALITY
JPEG_RESCALE
JPEG_SCALE
JPEG_OPTIMIZE
PROCESS_JPEG
PROCESS_PNG
PNG_OPTIMIZE
PNG_EFFORT
PNG_RESCALE
PNG_SCALE'

###############################################################################
# Functions
###############################################################################

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
            if ! [ "${!__check_set}" == 'true' ]; then
                eval "__arr=\"\${__depends__${__check_set}[@]}\""
                for __item in ${__arr[@]}; do
                    if [ "${!__item}" == 'true' ]; then
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
                if [ "${!__check_set}" == 'true' ]; then
                    eval "__arr=\"\${__depends__${__check_set}[@]}\""
                    for item in ${__arr[@]}; do
                        echo "${item}"
                    done
                fi
            done < <(set | grep -e '^__depends__' | sed 's/^__depends__\([^=]*\)=.*/\1/')
            while read -r __item; do
                if [ "${!__item}" == 'true' ]; then
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

    __print_env | md5sum - | sed 's/ .*//'

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

    if [ "${PROCESS_JPEG}" == 'true' ]; then
        __process_generic_image jpeg
    fi

    if [ "${PROCESS_PNG}" == 'true' ]; then
        __process_generic_image png
    fi

}

__find_jpeg() {
    find './src/' -type f \( -iname \*.jpg -o -iname \*.jpeg \)
}

__find_png() {
    find './src/' -type f \( -iname \*.png \)
}

__process_generic_image() {

    while read -r __var; do
        #local "${__var}"
        if [ "${__var}" != "__PROCESS_${1^^}" ]; then
            eval "${__var#__}"='false'
        fi
    done < <(set | grep -E '^__PROCESS_' | sed 's/^\([^=]*\)=.*/\1/')

    __resolve_env

    "__find_${1}" | while read -r __source_file; do

        export FILE_HASH="$(md5sum "${__source_file}")"

        __target="$(sed 's|^\./src/|./|' <<<"${__source_file}")"

        if ! __check_file "${__source_file}"; then

            echo "Processing: ${__target}"

            echo "$(__hash_env)" >"$(__get_hash_file "${__source_file}")"

            __target_dir="$(dirname "${__target}")"

            mkdir -p "${__target_dir}"

            if [ -e "${__target}" ]; then
                rm "${__target}"
            fi

            if [ "${__JPEG_RESCALE}" == 'true' ]; then
                convert "${__source_file}" -quality "${JPEG_QUALITY}" -auto-orient -resize "${JPEG_SCALE}"% "${__target}"
            else
                cp "${__source_file}" "${__target}"
            fi

            if [ "${__JPEG_OPTIMIZE}" == 'true' ]; then
                jpegoptim -s "${__target}" 1>/dev/null
            fi

        fi

        unset FILE_HASH

    done

    __set_env './src/.env'

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
# __check_file <file>
########################################
#
# Check File
# Checks if a given file is current
#
########################################

__check_file() {

    __hash_file="$(__get_hash_file "${1}")"

    __target="$(sed 's|^\./src/|./|' <<<"${1}")"

    if ! [ -e "${__target}" ]; then
        return 1
    fi

    if [ -e "${__hash_file}" ]; then
        __file_hash="$(cat "${__hash_file}")"
        if [ "${__file_hash}" == "$(__hash_env)" ]; then
            return 0
        fi
    fi

    return 1

}

###############################################################################

{

    pushd "$(dirname "$0")"

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
