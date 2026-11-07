#!/bin/bash
#
# Crops headshot.jpg to a square around the face and cuts it out with
# avatar-alpha.png, as avatar.png, which the image pass then encodes like any
# other source. PNG so the only lossy step after the camera's JPEG is the AVIF
# encode.
#
# avatar-alpha.png (BiRefNet-matting, HR) and avatar-normals.png (from Apple
# Depth Pro depth) are model outputs on this exact crop, kept rather than
# regenerated: change the crop and both must be redone.
set -euo pipefail

__source='src/headshot.jpg'
__alpha='src/avatar-alpha.png'
__matte='src/avatar_matte.py'
__target='src/avatar.png'

# WxH+X+Y, tweak to taste. Started as the largest square centred on the face
# macOS Vision found (box 270x270 at 294,222 in an 800x1000 export of this
# photo, scaled 1.875x to this 1500x1875 one); the top edge is the limit.
__crop='1338x1338+135+0'

if [ "${1:-}" == '-r' ]; then
    echo 'magick'
    echo 'uv'
    exit
fi

if [ "${1:-}" == '-d' ]; then
    echo "${__source}"
    echo "${__alpha}"
    echo "${__matte}"
    exit
fi

if [ "${1:-}" == '-t' ]; then
    echo "${__target}"
    exit
fi

__tmp="$(mktemp -d)"
trap 'rm -rf "${__tmp}"' EXIT

magick "${__source}" -crop "${__crop}" +repage -strip "${__tmp}/crop.png"
uv run --quiet --script "${__matte}" "${__tmp}/crop.png" "${__alpha}" "${__target}"
