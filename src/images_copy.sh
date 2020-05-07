#!/bin/bash

__func() {
    __target="${1}"
    __source="${2}"

    if [ -d "${__target}" ]; then
        rm -r "${__target}"
    fi

    mkdir -p "$(dirname "${__target}")"

    cp -r "${__source}" "${__target}"

}

__func './static/images/reduced/clickbait' '../blog-images/dirs/clickbait/reduced'

__func './static/images/reduced/midiMixer/v1' '../blog-images/dirs/midiMixer/v1/reduced'

__func './static/images/reduced/midiMixer/handwired' '../blog-images/dirs/midiMixer/handwired/reduced'

exit
