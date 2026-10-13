# Regenerates Support/AppIcon.png and the extension icons from Support/AppIcon-source.webp.
# Usage (from repo root): python3 apps/macos/scripts/make_icon.py apps/macos/Support/AppIcon-source.webp . /tmp/icon-preview.png
import sys
import numpy as np
from PIL import Image

src, root = sys.argv[1], sys.argv[2]
rgb = np.asarray(Image.open(src).convert("RGB")).astype(np.float32) / 255.0
mx = rgb.max(axis=2)

# Tile region: everything inside the tile is bright; find its bounds.
x0, x1, y0, y1 = 122, 1122, 112, 1112

# Alpha from "composited over black": a = max channel (boosted), colour = rgb / a.
alpha = np.clip(mx * 2.2, 0, 1)
# Inside the tile, force fully opaque (fill a superellipse fitted to the bounds).
# Trace the real (convex) tile outline row by row from bright pixels.
bright = mx > 0.45
inside = np.zeros_like(bright)
extents = {}
for y in range(y0, y1 + 1):
    cols = np.where(bright[y, x0 - 5:x1 + 6])[0]
    if len(cols):
        extents[y] = (x0 - 5 + cols[0] + 3, x0 - 5 + cols[-1] - 2)
# A convex tile only narrows moving away from its middle; this drops the
# glow under the bottom edge.
mid = (y0 + y1) // 2
for rng in (range(mid, y1 + 1), range(mid, y0 - 1, -1)):
    prev = None
    for y in rng:
        if y not in extents:
            prev = (0, -1); continue
        l, r = extents[y]
        if prev is not None:
            l, r = max(l, prev[0]), min(r, prev[1])
        extents[y] = prev = (l, r)
# The top edge has no glow, so mirror the top half's outline onto the bottom.
for y in range(mid + 1, y1 + 30):
    t = y0 + y1 - y
    extents[y] = extents.get(t, (0, -1)) if t >= y0 else (0, -1)
for y, (l, r) in extents.items():
    if r > l:
        inside[y, l:r] = True
# Antialias the edge: blend the traced mask with the luminance-derived alpha.
from PIL import ImageFilter
soft = np.asarray(Image.fromarray((inside * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))) / 255.0
alpha = np.maximum(soft, alpha * 0.75 * (1 - soft))
color = np.where(alpha[..., None] > 1e-3, np.clip(rgb / np.maximum(alpha[..., None], 1e-3), 0, 1), 0)

out = np.dstack([color, alpha])
img = Image.fromarray((out * 255).astype(np.uint8), "RGBA")

# Fit to Apple's 1024 grid: tile body 824px wide, centred, 100px margins.
scale = 824 / (x1 - x0)
size = round(img.width * scale)
img = img.resize((size, size), Image.LANCZOS)
canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
ox = round(100 - x0 * scale)
oy = round(100 - y0 * scale)
canvas.alpha_composite(img, (ox, oy)) if ox >= 0 and oy >= 0 else canvas.paste(img, (ox, oy), img)
canvas.save(f"{root}/apps/macos/Support/AppIcon.png")

# Extension icons: tighter crop (no glow) so they read at 16px.
tile = canvas.crop((92, 92, 932, 932))
for s in (16, 32, 48, 128):
    tile.resize((s, s), Image.LANCZOS).save(f"{root}/extensions/browser/icons/icon-{s}.png")

# Preview on light and dark backgrounds.
prev = Image.new("RGBA", (2048, 1024), (236, 236, 240, 255))
prev.paste((28, 28, 30, 255), (1024, 0, 2048, 1024))
prev.alpha_composite(canvas, (0, 0)); prev.alpha_composite(canvas, (1024, 0))
prev.convert("RGB").resize((1024, 512), Image.LANCZOS).save(sys.argv[3])
print("ok", ox, oy, size)
