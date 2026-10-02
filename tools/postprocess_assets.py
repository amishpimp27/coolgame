#!/usr/bin/env python
"""Turn the raw NoobAI renders into game-ready assets.

  assets/raw/char_*.png  ->  assets/sprites/<id>.png   (background keyed out, cropped)
                             assets/busts/<id>.png     (head+shoulders crop for UI)
  assets/raw/bg_*.png    ->  assets/backgrounds/<id>.png (1280x720, bottom-anchored)

Background removal is a border flood fill over pixels close to the corner colour,
not a luminance key: a luminance key would eat pale pink hair and white shirts.
"""
import os
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(HERE, "assets", "raw")
SPRITES = os.path.join(HERE, "assets", "sprites")
BUSTS = os.path.join(HERE, "assets", "busts")
BGS = os.path.join(HERE, "assets", "backgrounds")

TOLERANCE = 26      # per-channel max distance from the background colour
FEATHER = 0.7       # gaussian radius applied to the alpha edge
BG_W, BG_H = 1280, 720


def background_mask(arr: np.ndarray) -> np.ndarray:
    """True where a pixel looks like backdrop.

    NoobAI does not always give a flat white plate: several renders came back
    with a radial grey gradient (bright behind the character, darker at the
    corners). A distance test around one corner colour misses the bright middle
    and leaves a ghost rectangle behind the sprite. Backdrop is therefore
    identified by *low saturation + high luminance*, with the luminance floor
    adapted from the border ring so darker gradients still key out.
    """
    h, w, _ = arr.shape
    a = arr.astype(np.int16)
    ring = np.concatenate([
        a[0:10, :].reshape(-1, 3), a[h - 10:h, :].reshape(-1, 3),
        a[:, 0:10].reshape(-1, 3), a[:, w - 10:w].reshape(-1, 3),
    ])
    ring_lum = float(np.median(ring.max(axis=1) * 0.5 + ring.min(axis=1) * 0.5))
    hi = a.max(axis=2)
    lo = a.min(axis=2)
    sat = hi - lo
    lum = (hi + lo) // 2
    floor = max(115.0, ring_lum - 110.0)
    close = (sat <= 22) & (lum >= floor)
    return close, np.array([ring_lum, ring_lum, ring_lum]), sat, lum


def flood_from_border(close: np.ndarray) -> np.ndarray:
    """4-connected flood fill of the background region starting at the borders."""
    h, w = close.shape
    reachable = np.zeros((h, w), dtype=bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if close[y, x] and not reachable[y, x]:
                reachable[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if close[y, x] and not reachable[y, x]:
                reachable[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        if y > 0 and close[y - 1, x] and not reachable[y - 1, x]:
            reachable[y - 1, x] = True
            q.append((y - 1, x))
        if y < h - 1 and close[y + 1, x] and not reachable[y + 1, x]:
            reachable[y + 1, x] = True
            q.append((y + 1, x))
        if x > 0 and close[y, x - 1] and not reachable[y, x - 1]:
            reachable[y, x - 1] = True
            q.append((y, x - 1))
        if x < w - 1 and close[y, x + 1] and not reachable[y, x + 1]:
            reachable[y, x + 1] = True
            q.append((y, x + 1))
    return reachable


def smooth_mask(arr: np.ndarray) -> np.ndarray:
    """True where the image is locally featureless.

    A colour test cannot key a saturated backdrop (one render came back with a
    brown vignette behind a red-haired dragon girl). Backdrops are, however,
    always *smooth*, while the character is bounded by dark line art, so a
    gradient-magnitude test separates them regardless of hue. Flat areas inside
    the character are safe because the outline around them stops the flood.
    """
    g = arr.astype(np.float32).mean(axis=2)
    gy = np.zeros_like(g)
    gx = np.zeros_like(g)
    gy[1:-1, :] = g[2:, :] - g[:-2, :]
    gx[:, 1:-1] = g[:, 2:] - g[:, :-2]
    mag = np.sqrt(gx * gx + gy * gy)
    return mag < 9.0


# Some renders come back on a saturated backdrop that the colour test cannot
# catch at all. The smooth-region pass handles those, but it also eats the flat
# interior of any large shape that happens to touch the frame edge (it hollowed
# out a fox girl's tails and a dryad's canopy), so it is opt-in per character
# rather than an automatic fallback.
SMOOTH_FALLBACK_IDS = {"cindra"}


def key_alpha(arr: np.ndarray, id_: str) -> tuple:
    """Return (backdrop_mask, ring_colour, coverage) for one render."""
    close, bg, _sat, _lum = background_mask(arr)
    reach = flood_from_border(close)
    if id_ in SMOOTH_FALLBACK_IDS:
        smooth = flood_from_border(smooth_mask(arr))
        if smooth.mean() > reach.mean():
            return smooth, bg, smooth.mean()
    return reach, bg, reach.mean()


def key_sprite(src: str, id_: str) -> bool:
    img = Image.open(src).convert("RGB")
    arr = np.asarray(img)
    reachable, bg, coverage = key_alpha(arr, id_)
    if coverage < 0.05:
        print("  ! %s: only %.1f%% backdrop detected -- key may have failed" % (id_, coverage * 100))
    alpha = np.where(reachable, 0.0, 255.0)
    a_img = Image.fromarray(alpha.astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(FEATHER))
    # Erode the soft edge: the anti-aliased rim is a blend of character and
    # backdrop, so keeping it would leave a grey halo once the plate is gone.
    a = np.asarray(a_img).astype(np.float32)
    a = np.clip((a - 46.0) * (255.0 / (255.0 - 46.0)), 0, 255)
    out = img.convert("RGBA")
    out.putalpha(Image.fromarray(a.astype(np.uint8), "L"))

    bbox = out.getbbox()
    if bbox is None:
        print("  ! %s: nothing left after keying" % id_)
        return False
    pad = 6
    bbox = (max(0, bbox[0] - pad), max(0, bbox[1] - pad),
            min(out.width, bbox[2] + pad), min(out.height, bbox[3] + pad))
    full = out.crop(bbox)
    full.save(os.path.join(SPRITES, "%s.png" % id_))

    # Bust: top 58% of the silhouette, keeps hair and shoulders for UI cards.
    top = bbox[1]
    cut = bbox[1] + int((bbox[3] - bbox[1]) * 0.58)
    bust = out.crop((bbox[0], top, bbox[2], cut))
    bust.thumbnail((420, 560), Image.LANCZOS)
    bust.save(os.path.join(BUSTS, "%s.png" % id_))
    print("  %-12s ring=%3d cover=%5.1f%%  sprite=%dx%d  bust=%dx%d"
          % (id_, int(bg[0]), coverage * 100,
             full.width, full.height, bust.width, bust.height))
    return True


def prep_background(src: str, id_: str) -> bool:
    img = Image.open(src).convert("RGB")
    scale = max(BG_W / img.width, BG_H / img.height)
    new = (int(round(img.width * scale)), int(round(img.height * scale)))
    img = img.resize(new, Image.LANCZOS)
    # Bottom-anchored crop: keeps the floor and furniture, trims the ceiling.
    top = new[1] - BG_H
    left = max(0, (new[0] - BG_W) // 2)
    img = img.crop((left, top, left + BG_W, top + BG_H))
    img.save(os.path.join(BGS, "%s.png" % id_))
    print("  bg %-16s -> 1280x720" % id_)
    return True


def contact_sheet(ids) -> None:
    """One image showing every keyed sprite on a checkerboard, for eyeballing."""
    cell_w, cell_h = 200, 340
    cols = 7
    rows = (len(ids) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell_w, rows * cell_h), (30, 26, 36, 255))
    checker = Image.new("RGBA", (cell_w, cell_h))
    for y in range(0, cell_h, 20):
        for x in range(0, cell_w, 20):
            c = (70, 70, 78, 255) if ((x // 20) + (y // 20)) % 2 == 0 else (44, 44, 50, 255)
            checker.paste(c, (x, y, x + 20, y + 20))
    for i, id_ in enumerate(ids):
        path = os.path.join(SPRITES, "%s.png" % id_)
        if not os.path.exists(path):
            continue
        sp = Image.open(path).convert("RGBA")
        sp.thumbnail((cell_w - 16, cell_h - 30), Image.LANCZOS)
        cx = (i % cols) * cell_w
        cy = (i // cols) * cell_h
        sheet.paste(checker, (cx, cy))
        sheet.alpha_composite(sp, (cx + (cell_w - sp.width) // 2,
                                   cy + cell_h - 22 - sp.height))
        ImageDraw.Draw(sheet).text((cx + 6, cy + cell_h - 20), id_, fill=(255, 210, 235, 255))
    sheet.save(os.path.join(HERE, "tools", "contact_sheet.png"))
    print("contact sheet -> tools/contact_sheet.png (%dx%d)" % sheet.size)


def main():
    for d in (SPRITES, BUSTS, BGS):
        os.makedirs(d, exist_ok=True)
    chars, bgs = [], []
    for f in sorted(os.listdir(RAW)):
        if f.startswith("char_") and f.endswith(".png"):
            chars.append(f[5:-4])
        elif f.startswith("bg_") and f.endswith(".png"):
            bgs.append(f[3:-4])
    print("Keying %d character sprites..." % len(chars))
    fails = []
    for id_ in chars:
        if not key_sprite(os.path.join(RAW, "char_%s.png" % id_), id_):
            fails.append(id_)
    print("Preparing %d backgrounds..." % len(bgs))
    for id_ in bgs:
        if not prep_background(os.path.join(RAW, "bg_%s.png" % id_), id_):
            fails.append(id_)
    contact_sheet(chars)
    print("\nFAILED: %s" % (fails or "none"))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
