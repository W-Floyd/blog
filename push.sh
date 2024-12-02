#!/bin/bash

docker build -t w-floyd/blog . || {
    echo 'Failure to build'
    exit
}

docker save w-floyd/blog | bzip2 | pv | ssh "${1}" docker load
ssh "${1}" \
    docker-compose \
    -f /root/server-config/docker-compose.yml \
    --project-directory /root/server-config \
    up --remove-orphans -d

exit
