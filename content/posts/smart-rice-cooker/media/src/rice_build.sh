#!/bin/bash

if [ "${1}" == '-r' ]; then
    echo 'fdp'
    echo 'sed'
    exit
fi

if [ "${1}" == '-d' ]; then
    echo 'src/rice_connections.dot'
    exit
fi

__target='connections.svg'

if [ "${1}" == '-t' ]; then
    echo "${__target}"
    exit
fi

sed -e 's/\[depend_value\]/[color=blue]/' \
    -e 's/\[proxy_value\]/\[color=deepskyblue\]/' \
    -e 's/\[proxy_function\]/\[color=dodgerblue\]/' \
    -e 's/\[documented\]/\[fillcolor=darkolivegreen1\]/' \
    -e 's/\[done\]/\[fillcolor=chartreuse\]/' \
    -e 's/\[depend_function\]/\[color=cornflowerblue\]/' 'src/rice_connections.dot' | fdp -Ln5 -Tsvg >"${__target}"

exit
