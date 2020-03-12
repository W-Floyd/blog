#!/bin/bash

git pull

HUGO_ENV=production hugo --gc --minify

exit
