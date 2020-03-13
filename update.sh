#!/bin/bash

git pull

find src -iname '*.sh' | while read -r __file; do
    time ./${1}
done

HUGO_ENV=production hugo --gc --minify

exit
