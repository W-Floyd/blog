#!/bin/bash
#
# Renders calculate.jq to the HTML Hugo's highlighter would emit, with chroma v3
# (scripts/highlight), since Hugo's chroma v2 has no jq lexer. The page includes
# the output with file-content.
set -euo pipefail

__tool="${REPO_ROOT:-$(git rev-parse --show-toplevel)}/scripts/highlight"
__source='calculate.jq'
__target='calculate.jq.chroma'

if [ "${1:-}" == '-r' ]; then
    echo 'go'
    exit
fi

if [ "${1:-}" == '-d' ]; then
    echo "${__source}"
    echo "${__tool}/main.go"
    echo "${__tool}/go.sum"
    exit
fi

if [ "${1:-}" == '-t' ]; then
    echo "${__target}"
    exit
fi

(cd "${__tool}" && go run . jq "${OLDPWD}/${__source}") >"${__target}.tmp"
mv "${__target}.tmp" "${__target}"
