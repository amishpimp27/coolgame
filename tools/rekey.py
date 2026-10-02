"""Re-key character renders with a trained anime segmentation model.

Why this replaced the old keyer
-------------------------------
The previous version flooded in from the frame border and deleted any pixel
that was low-saturation and reasonably bright. That is a fine rule for a flat
white plate and a terrible rule for a character: it also deleted pale skin,
white tights, thin anti-aliased limbs and translucent bodies, and it left
white background showing through anywhere the character was not connected to
the border. Rach lost her spider legs, Sylith lost her tail, Willa dissolved.

This version asks a model trained on anime characters (ISNet-anime) where the
character is, and then does real edge work:

1. Pad to a square before inference, because the network resizes its input to a
   fixed 1024x1024 -- feeding it a tall 768x1344 image squashes the aspect.
2. Guided-filter the mask against the actual image so the alpha snaps to real
   luminance edges instead of the mask's own blurry outline.
3. Push the alpha through a contrast curve to kill the soft grey band.
4. Defringe: colour every partly-transparent edge pixel from its nearest fully
   opaque neighbour, so the white plate stops bleeding into a halo.

Usage:  python tools/rekey.py [id ...]        (default: every character)
"""
import os
import sys
import time

import numpy as np
from PIL import Image
from scipy import ndimage

from rembg import new_session, remove

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RAW = os.path.join(ROOT, "assets", "raw")
SPR = os.path.join(ROOT, "assets", "sprites")
BUST = os.path.join(ROOT, "assets", "busts")

CHARS = ["vaelira", "rach", "sylith", "mora", "nyx", "fenra", "rin",
         "sebille", "tillia", "griz", "willa", "cindra", "player"]

MODEL = "isnet-anime"

# Alpha curve: below LO -> fully transparent, above HI -> fully opaque, smooth
# ramp between. Kills the grey wash the upscaled network mask leaves behind
# while keeping a couple of pixels of anti-aliasing.
LO, HI = 0.30, 0.72


def guided_filter(guide: np.ndarray, src: np.ndarray, r: int, eps: float) -> np.ndarray:
    """Edge-aware filter: `src` is smoothed, but only where `guide` is flat.

    This is what turns a blurry 1024x1024 network mask into an alpha channel
    that follows the character's real outline.
    """
    k = 2 * r + 1
    box = lambda x: ndimage.uniform_filter(x, k, mode="reflect")
    mean_g = box(guide)
    mean_s = box(src)
    corr_gg = box(guide * guide)
    corr_gs = box(guide * src)
    var_g = corr_gg - mean_g * mean_g
    cov_gs = corr_gs - mean_g * mean_s
    a = cov_gs / (var_g + eps)
    b = mean_s - a * mean_g
    return box(a) * guide + box(b)


def defringe(rgb: np.ndarray, alpha: np.ndarray) -> np.ndarray:
    """Pull colour inward from opaque pixels, so edges carry no plate colour.

    A semi-transparent pixel still holds whatever colour the render put there,
    which for an anti-aliased edge against a white plate is white. Composited
    over a dark background that reads as a halo. Copying the nearest opaque
    colour outward removes it.
    """
    opaque = alpha >= 0.995
    if not opaque.any():
        return rgb
    _, idx = ndimage.distance_transform_edt(~opaque, return_indices=True)
    filled = rgb[idx[0], idx[1]]
    edge = (alpha > 0.02) & ~opaque
    out = rgb.copy()
    out[edge] = filled[edge]
    return out


def key_one(session, name: str) -> float:
    src = os.path.join(RAW, "char_%s.png" % name)
    if not os.path.exists(src):
        raise FileNotFoundError(src)
    im = Image.open(src).convert("RGB")
    w, h = im.size
    t0 = time.time()

    # square-pad so the fixed-size network input keeps the original aspect
    side = max(w, h)
    pad = Image.new("RGB", (side, side), (255, 255, 255))
    ox, oy = (side - w) // 2, (side - h) // 2
    pad.paste(im, (ox, oy))

    cut = remove(pad, session=session, alpha_matting=False, post_process_mask=False)
    mask = np.asarray(cut, dtype=np.uint8)[:, :, 3].astype(np.float32) / 255.0
    mask = mask[oy:oy + h, ox:ox + w]

    rgb = np.asarray(im, dtype=np.float32) / 255.0
    lum = rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32)

    # snap the mask to real image edges, then tighten the ramp
    alpha = guided_filter(lum, mask, r=6, eps=1e-4)
    alpha = np.clip((alpha - LO) / (HI - LO), 0.0, 1.0)
    alpha = alpha * alpha * (3.0 - 2.0 * alpha)          # smoothstep, keeps AA

    rgb = defringe(rgb, alpha)

    out = np.concatenate([np.clip(rgb * 255.0, 0, 255), alpha[:, :, None] * 255.0], axis=2)
    sprite = Image.fromarray(out.astype(np.uint8), "RGBA")

    # Trim to the character. The game sizes characters by texture height, so any
    # empty margin baked into the render becomes a size error: a girl whose art
    # nearly fills the frame renders visibly larger than one drawn with more
    # padding, at an identical target height. Cropping makes texture height
    # equal character height, which is what the scale maths assumes.
    bbox = sprite.getbbox()
    if bbox:
        sprite = sprite.crop(bbox)
    sprite.save(os.path.join(SPR, "%s.png" % name))

    # Portrait for the journal: head down to about mid-thigh.
    w, h = sprite.size
    bust_h = max(1, int(h * 0.52))
    bust_w = min(w, int(bust_h * 1.6))
    sprite.crop(((w - bust_w) // 2, 0, (w - bust_w) // 2 + bust_w, bust_h)).save(
        os.path.join(BUST, "%s.png" % name))

    return time.time() - t0


def audit_sheet() -> None:
    """Every sprite on magenta at true in-game size, 2x magnified.

    Magenta is not a colour the art contains, so a single glance shows erased
    parts (magenta inside the silhouette) and leftover plate (grey/white).
    """
    ids = [n for n in CHARS if os.path.exists(os.path.join(SPR, "%s.png" % n))]
    h = 205
    cells = []
    for n in ids:
        im = Image.open(os.path.join(SPR, "%s.png" % n)).convert("RGBA")
        im = im.resize((max(1, int(im.width * h / im.height)), h), Image.LANCZOS)
        cells.append((n, im))
    pad = 14
    width = sum(c[1].width for c in cells) + pad * (len(cells) + 1)
    sheet = Image.new("RGB", (width, h + 40), (255, 0, 200))
    x = pad
    for n, im in cells:
        sheet.paste(im, (x, 26), im)
        x += im.width + pad
    sheet = sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST)
    sheet.save(os.path.join(HERE, "key_audit.png"))
    print("audit sheet -> tools/key_audit.png  (%s)" % (sheet.size,))


def main() -> int:
    names = [a for a in sys.argv[1:] if not a.startswith("-")] or CHARS
    print("loading %s ..." % MODEL)
    session = new_session(MODEL)
    print("model ready\n")
    bad = []
    for n in names:
        try:
            dt = key_one(session, n)
            a = np.asarray(Image.open(os.path.join(SPR, "%s.png" % n)))[:, :, 3]
            cover = 100.0 * (a > 127).mean()
            print("OK   %-9s %5.1fs  opaque %5.1f%%" % (n, dt, cover))
            if cover < 4.0:
                bad.append(n)
        except Exception as e:
            bad.append(n)
            print("FAIL %-9s %s" % (n, e))
    print("\nsuspiciously empty: %s" % (bad or "none"))
    audit_sheet()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
