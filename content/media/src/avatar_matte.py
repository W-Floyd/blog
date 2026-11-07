# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "pillow"]
# ///
# Cut the subject out of a white backdrop with a precomputed matte.
# Where alpha is soft (hair), the photo's colour is mostly backdrop, so edge colour
# comes from the subject instead: interior colour spread outward (normalized
# convolution over opaque pixels) caps the unmixed colour.
# usage: avatar_matte.py source.png alpha.png out.png [edge_power] [erode_px]
import sys
import numpy as np
from PIL import Image

src, al, out = sys.argv[1:4]
pw = float(sys.argv[4]) if len(sys.argv) > 4 else 16
erode = float(sys.argv[5]) if len(sys.argv) > 5 else 8
rgb = np.asarray(Image.open(src).convert("RGB")).astype(np.float64) / 255
a = np.asarray(Image.open(al).convert("L")).astype(np.float64) / 255


def blur(x, r):
    p = int(3 * r)
    xp = np.pad(x, p, mode="edge")
    fy, fx = np.fft.fftfreq(xp.shape[0]), np.fft.fftfreq(xp.shape[1])
    g = np.exp(-2 * (np.pi * r) ** 2 * (fy[:, None] ** 2 + fx[None, :] ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(xp) * g))[p:-p, p:-p]


w = (a > 0.97).astype(np.float64)
if erode:
    # sample colour from deeper inside the hair, past its backdrop-tinted fringe
    w = (blur(w, erode) > 0.98).astype(np.float64)
lin = rgb**2.2
est = np.zeros_like(lin)
# coarse to fine: far fringe pixels still get a colour, near ones get local colour
for r in (24, 8, 3):
    den = blur(w, r)
    e = np.dstack([blur(lin[..., c] * w, r) for c in range(3)]) / np.maximum(den, 1e-6)[..., None]
    est = np.where((den > 0.02)[..., None], e, est)
unmix = np.clip((rgb - (1 - a[..., None])) / np.maximum(a, 0.05)[..., None], 0, 1) ** 2.2
t = (a**pw)[..., None]
# edge colour never brighter than the subject's own: brightness there is backdrop
fg = t * unmix + (1 - t) * np.minimum(unmix, est)
Image.fromarray((np.dstack([fg ** (1 / 2.2), a]) * 255).round().astype(np.uint8)).save(out)
