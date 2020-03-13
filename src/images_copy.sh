#!/bin/bash

__target='./static/images/reduced/clickbait'
__source='../blog-images/dirs/clickbait/reduced'

if [ -d "${__target}" ]; then
    rm -r "${__target}"
fi

mkdir -p "$(dirname "${__target}")"

cp -r "${__source}" "${__target}"

exit
