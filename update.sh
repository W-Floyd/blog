#!/bin/bash

git pull

find src -iname '*.sh' | while read -r __file; do
    time ./${__file}
done

HUGO_ENV=production hugo --gc --minify

exit
