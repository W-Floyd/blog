#!/bin/bash

__target='../static/images/generated/rice/connections.svg'

mkdir -p "$(dirname "${__target}")"

sed -e 's/\[depend_value\]/[color=blue]/' \
-e 's/\[proxy_value\]/\[color=deepskyblue\]/' \
-e 's/\[proxy_function\]/\[color=dodgerblue\]/' \
-e 's/\[documented\]/\[fillcolor=darkolivegreen1\]/' \
-e 's/\[done\]/\[fillcolor=chartreuse\]/' \
-e 's/\[depend_function\]/\[color=cornflowerblue\]/' connections.dot | fdp -Ln5 -Tsvg > "${__target}"

exit
