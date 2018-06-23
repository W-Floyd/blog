#!/bin/bash

sed -e 's/\[depend_value\]/[color=blue]/' \
-e 's/\[proxy_value\]/\[color=deepskyblue\]/' \
-e 's/\[proxy_function\]/\[color=dodgerblue\]/' \
-e 's/\[documented\]/\[fillcolor=darkolivegreen1\]/' \
-e 's/\[done\]/\[fillcolor=chartreuse\]/' \
-e 's/\[depend_function\]/\[color=cornflowerblue\]/' connections.dot | fdp -Ln5 -Tsvg > '../static/rice/connections.svg'

exit
