# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "torch", "torchvision", "transformers==5.22.2",
#   "timm", "kornia", "einops",  # BiRefNet's remote code
#   "numpy", "pillow",
# ]
# ///
# Regenerates avatar-alpha.png and avatar-normals.png, the model outputs that
# avatar_build.sh and avatar-relight.js consume. Not part of the image build
# (which only runs *.sh): run by hand, after changing the crop.
#
#   uv run avatar_models.py matte    # -> avatar-alpha.png
#   uv run avatar_models.py normals  # -> avatar-normals.png, needs the alpha
#
# Run from this directory. Needs ~3 GB of weights and a fast link; CPU works
# (BiRefNet_HR at 2048 is minutes, Depth Pro ~18 min on 20 threads). On the
# home server's Arc A380, Depth Pro is ~50 s, but the host lacks the Level Zero
# runtime and PyPI's torch has no XPU build, so run it in a container:
#
#   docker run --rm --device /dev/dri -v "$PWD:/w" -w /w \
#     -v ~/.cache/huggingface:/root/.cache/huggingface debian:sid sh -c '
#       apt-get update && apt-get install -y curl libze1 libze-intel-gpu1 intel-opencl-icd &&
#       curl -LsSf https://astral.sh/uv/install.sh | sh &&
#       ~/.local/bin/uv run --index https://download.pytorch.org/whl/xpu avatar_models.py normals'
#
# Matte: BiRefNet_HR-matting alone is soft and pulls the hair edge in; ViTMatte
# alone (on a macOS Vision mask trimap) keeps strands but leaves white fringe.
# BiRefNet's matte as ViTMatte's trimap gets both.
#
# The committed avatar-normals.png came from that earlier Vision-trimap
# ViTMatte matte; normals only use alpha > 0.5, so the current matte gives a
# near-identical map.
import re
import sys

import numpy as np
import torch
from PIL import Image, ImageFilter

# Pinned: BiRefNet runs repo code (trust_remote_code).
BIREFNET = ("ZhengPeng7/BiRefNet_HR-matting", "5d6b6f8adcb5b417c871b1d84ceaae9871355b7f")
VITMATTE = ("hustvl/vitmatte-base-composition-1k", "bf486d01a7d9e3dbcc8400f7942835caf0eaf76e")
DEPTHPRO = ("apple/DepthPro-hf", "de816c8ce7168afcb231f96d501d72b869d0beda")

ALPHA, NORMALS = "avatar-alpha.png", "avatar-normals.png"


def crop():
    # Same crop as avatar_build.sh, read from it so there's one copy.
    w, h, x, y = map(int, re.search(r"__crop='(\d+)x(\d+)\+(\d+)\+(\d+)'", open("avatar_build.sh").read()).groups())
    return Image.open("headshot.jpg").convert("RGB").crop((x, y, x + w, y + h))


def device():
    if torch.cuda.is_available():
        return "cuda", torch.float16
    if hasattr(torch, "xpu") and torch.xpu.is_available():
        return "xpu", torch.float16
    return "cpu", torch.float32


def blur(x, r):
    # FFT Gaussian in float: a uint8 blur of the matte bands the normals.
    p = int(3 * r)
    xp = np.pad(x, p, mode="edge")
    fy, fx = np.fft.fftfreq(xp.shape[0]), np.fft.fftfreq(xp.shape[1])
    g = np.exp(-2 * (np.pi * r) ** 2 * (fy[:, None] ** 2 + fx[None, :] ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(xp) * g))[p:-p, p:-p]


def matte():
    from transformers import AutoModelForImageSegmentation, VitMatteForImageMatting, VitMatteImageProcessor
    import torchvision.transforms as T

    im = crop()
    # BiRefNet's remote code is only checked in fp32 on CPU.
    m = AutoModelForImageSegmentation.from_pretrained(BIREFNET[0], revision=BIREFNET[1], trust_remote_code=True).eval().float()
    x = T.Compose([T.Resize((2048, 2048)), T.ToTensor(), T.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225])])(im)[None]
    with torch.no_grad():
        p = m(x)[-1].sigmoid()[0, 0].numpy()
    guide = Image.fromarray((p * 255).round().astype(np.uint8)).resize(im.size, Image.LANCZOS)

    # Trimap: confident core and backdrop, unknown band wide enough for the hair.
    fg = guide.point(lambda v: 255 if v > 240 else 0).filter(ImageFilter.MinFilter(15))
    bg = guide.point(lambda v: 255 if v > 15 else 0).filter(ImageFilter.MaxFilter(41))
    tri = np.full((im.height, im.width), 128, np.uint8)
    tri[np.asarray(bg) == 0] = 0
    tri[np.asarray(fg) == 255] = 255

    proc = VitMatteImageProcessor.from_pretrained(VITMATTE[0], revision=VITMATTE[1])
    m = VitMatteForImageMatting.from_pretrained(VITMATTE[0], revision=VITMATTE[1]).eval()
    with torch.no_grad():
        a = m(**proc(images=im, trimaps=Image.fromarray(tri), return_tensors="pt")).alphas[0, 0]
    a = a[: im.height, : im.width].numpy()
    Image.fromarray((a * 255).round().astype(np.uint8)).save(ALPHA)


def normals():
    from transformers import DepthProForDepthEstimation, DepthProImageProcessorFast

    im = crop()
    dev, dt = device()
    proc = DepthProImageProcessorFast.from_pretrained(DEPTHPRO[0], revision=DEPTHPRO[1])
    m = DepthProForDepthEstimation.from_pretrained(DEPTHPRO[0], revision=DEPTHPRO[1], torch_dtype=dt).eval().to(dev)
    with torch.no_grad():
        out = m(**{k: v.to(dev, dt) for k, v in proc(images=im, return_tensors="pt").items()})
    # post-processing expects fp32 CPU tensors
    out.predicted_depth = out.predicted_depth.float().cpu()
    if getattr(out, "field_of_view", None) is not None:
        out.field_of_view = out.field_of_view.float().cpu()
    z = proc.post_process_depth_estimation(out, target_sizes=[(im.height, im.width)])[0]["predicted_depth"].numpy()
    z = z.astype(np.float32).astype(np.float64)

    a = np.asarray(Image.open(ALPHA).convert("L")).astype(np.float32) / 255
    W = a.shape[1]
    inside = a > 0.5
    # Backdrop depth is meaningless: pull it to the subject's edge depth so the
    # silhouette isn't a cliff, then smooth away skin and hair texture.
    z = np.where(inside, z, np.median(z[inside & (blur(a, 3) < 0.9)]))
    z = blur(z, W * 0.006)
    dzdv, dzdu = np.gradient(z)
    n = np.dstack([dzdu, dzdv, z / (3.0 * W)])  # x right, y down, z toward viewer; focal ~3W
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    # Black outside the mask: the shader reads b < .3 as "no normal".
    Image.fromarray(((n * 0.5 + 0.5) * 255 * inside[..., None]).astype(np.uint8)).save(NORMALS)


{"matte": matte, "normals": normals}[sys.argv[1]]()
