#!/bin/bash

__source='favicon.svg'

if [ "${1}" == '-r' ]; then
    echo 'rsvg-convert'
    exit
fi

if [ "${1}" == '-d' ]; then
    echo "${__source}"
    exit
fi

if [ "${1}" == '-t' ]; then
    echo 'favicon-16x16.png'
    echo 'favicon-32x32.png'
    echo 'apple-touch-icon.png'
    exit
fi

rsvg-convert -w 16 -h 16 "${__source}" -o 'favicon-16x16.png'
rsvg-convert -w 32 -h 32 "${__source}" -o 'favicon-32x32.png'
rsvg-convert -w 180 -h 180 "${__source}" -o 'apple-touch-icon.png'

exit
