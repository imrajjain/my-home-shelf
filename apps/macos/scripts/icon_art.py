#!/usr/bin/env python3
"""Draws the layers of Support/Shelf.icon: a topographic wallpaper of soft
contour blobs, and a contour-layered flower. Deterministic, so re-running it
gives the same icon. Usage: python3 scripts/icon_art.py"""
import math, os, random

OUT = os.path.join(os.path.dirname(__file__), "..", "Support", "Shelf.icon", "Assets")
SIZE = 1024

def blob(cx, cy, r, seed, wobble=0.10, stretch=(1.0, 1.0), angle=0.0, points=72):
    """A closed, smooth, organic loop: a circle whose radius ripples with a
    few low sine harmonics. Returns an SVG path through Catmull-Rom curves."""
    rnd = random.Random(seed)
    harmonics = [(k, rnd.uniform(0, 2 * math.pi), wobble * rnd.uniform(0.4, 1.0) / (1 + (k - 2) * 0.6))
                 for k in (2, 3, 4, 5)]
    pts = []
    for i in range(points):
        t = 2 * math.pi * i / points
        rr = r * (1 + sum(a * math.sin(k * t + p) for k, p, a in harmonics))
        x, y = rr * math.cos(t) * stretch[0], rr * math.sin(t) * stretch[1]
        ca, sa = math.cos(angle), math.sin(angle)
        pts.append((cx + x * ca - y * sa, cy + x * sa + y * ca))
    d = f"M{pts[0][0]:.1f} {pts[0][1]:.1f}"
    n = len(pts)
    for i in range(n):
        p0, p1, p2, p3 = pts[i - 1], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        d += f" C{c1[0]:.1f} {c1[1]:.1f} {c2[0]:.1f} {c2[1]:.1f} {p2[0]:.1f} {p2[1]:.1f}"
    return d + " Z"

def svg(paths):
    body = "\n".join(f'  <path fill="{c}" d="{d}"/>' for c, d in paths)
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 {SIZE} {SIZE}">\n{body}\n</svg>\n'

# Contour clusters, light ring to dark core, each anchored off a corner so
# the middle stays an open clearing for the flower.
CLUSTERS = [
    # (name, center, colors light→dark, seed, stretch, tilt) — soft pastels, close in tone
    ("sage",     (90, 60),   ["#DDE6C4", "#C3D2A3", "#A6BC84", "#8AA46A"], 11, (1.25, 0.85), 0.35),
    ("lavender", (960, 110), ["#ECDDF2", "#DCC6EA", "#C7A9DE", "#B08ED0"], 29, (1.15, 0.95), -0.5),
    ("butter",   (70, 960),  ["#FBEFC4", "#F8E2A0", "#F4D27E", "#EEC062"], 37, (1.2, 0.9), -0.4),
    ("sea",      (980, 950), ["#D5ECEC", "#B4DCE0", "#8FC8D2", "#6FB2C4"], 41, (1.25, 0.88), 0.45),
]

def cluster(center, colors, seed, stretch, tilt):
    """One corner's contours. Each is its own glass layer in the icon, over
    a pale sky fill, so the background reads as glass rather than paper."""
    cx, cy = center
    n = len(colors)
    paths = []
    for i, color in enumerate(colors):
        r = 460 * (1 - i / (n + 0.5))
        # Inner rings drift outward toward the corner, like real contours.
        dx, dy = (i * 16 * (-1 if cx < 512 else 1), i * 12 * (-1 if cy < 512 else 1))
        paths.append((color, blob(cx + dx, cy + dy, r, seed + i, wobble=0.09,
                                  stretch=stretch, angle=tilt)))
    return svg(paths)

def flower():
    cx, cy = 512, 516
    rings = ["#FBD3E2", "#F5A9C7", "#E9779F"]   # blush → rose → deep pink
    paths = []
    # Ring by ring across all petals, so each contour reads as one bloom.
    for i, color in enumerate(rings):
        for k in range(5):
            a = -math.pi / 2 + k * 2 * math.pi / 5
            dist = 178 - i * 26          # inner rings drift toward the heart
            px, py = cx + dist * math.cos(a), cy + dist * math.sin(a)
            scale = 1 - i * 0.24
            paths.append((color, blob(px, py, 150 * scale, 100 + k * 10 + i, wobble=0.08,
                                      stretch=(1.0, 0.78), angle=a)))
    paths.append(("#FFE7A3", blob(cx, cy, 92, 7, wobble=0.07)))
    paths.append(("#F6C55E", blob(cx, cy, 50, 8, wobble=0.09)))
    return svg(paths)

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name in os.listdir(OUT):
        os.remove(os.path.join(OUT, name))
    for name, center, colors, seed, stretch, tilt in CLUSTERS:
        open(os.path.join(OUT, f"{name}.svg"), "w").write(cluster(center, colors, seed, stretch, tilt))
    open(os.path.join(OUT, "flower.svg"), "w").write(flower())
    print("Wrote", ", ".join(sorted(os.listdir(OUT))))
