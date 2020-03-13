#!/bin/bash

git pull --recurse-submodules

if [ -d './static/images/reduced/' ]; then
    rm -r './static/images/reduced/'
fi

if [ -d './static/images/generated/' ]; then
    rm -r './static/images/generated/'
fi

find src -iname '*.sh' | while read -r __file; do
    time ./${__file} "$(dirname "${__file}")/"
done

rm -r public

HUGO_ENV=production hugo --gc --minify

exit
