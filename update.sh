#!/bin/bash

git pull

if [ -d './static/images/generated/' ]; then
    rm -r './static/images/generated/'
fi

git submodule update --remote --merge

find src -iname '*.sh' | while read -r __file; do
    time ./${__file} "$(dirname "${__file}")/"
done

HUGO_ENV=production hugo --gc --minify

exit
