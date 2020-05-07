#!/bin/bash

__target_prefix='./static/images'
__source_prefix='../blog-images/dirs'

__copy_reduced() {
    __copy "${__target_prefix}/reduced/${1}/" "${__source_prefix}/${1}/reduced/"
}

__copy_original() {
    __copy "${__target_prefix}/original/${1}/" "${__source_prefix}/${1}/"
}

__copy() {
    __target="${1}"
    __source="${2}"

    if [ -d "${__target}" ]; then
        rm -r "${__target}"
    fi

    mkdir -p "$(dirname "${__target}")"

    while read -r __file; do
        cp -r "${__file}" "${__target}"
    done < <(find "${__source}" -maxdepth 1 -type f -iname '*.jpg')

}

__func() {
    __copy_reduced "${1}"
    __copy_original "${1}"
}

__func 'clickbait'

__func 'midiMixer/v1'

__func 'midiMixer/handwired'

exit
