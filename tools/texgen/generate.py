"""RUNEBOUND pixel texture generator.

Generates all VFX sprites and environment textures as low-res pixel art,
palette-constrained per docs/ART_BIBLE.md. Deterministic (seeded).

Run:  python tools/texgen/generate.py
"""
from __future__ import annotations

import os
import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
VFX_DIR = os.path.join(ROOT, "assets", "vfx")
TEX_DIR = os.path.join(ROOT, "assets", "textures")

rng = np.random.default_rng(1207)


def save(img: np.ndarray, folder: str, name: str) -> None:
    os.makedirs(folder, exist_ok=True)
    arr = np.clip(img, 0, 255).astype(np.uint8)
    Image.fromarray(arr, "RGBA").save(os.path.join(folder, f"{name}.png"))
    print(f"  {name}.png ({arr.shape[1]}x{arr.shape[0]})")


def canvas(size: int) -> np.ndarray:
    return np.zeros((size, size, 4), dtype=np.float32)


def coords(size: int):
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    cx = cy = (size - 1) / 2
    r = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
    ang = np.arctan2(y - cy, x - cx)
    return x, y, r, ang


def put(img, mask, color):
    for i, c in enumerate(color):
        img[..., i] = np.where(mask, c, img[..., i])


# --- VFX sprites -----------------------------------------------------------

def gen_spark():
    img = canvas(16)
    x, y, r, _ = coords(16)
    plus = ((np.abs(x - 7.5) < 1.2) & (np.abs(y - 7.5) < 6)) | ((np.abs(y - 7.5) < 1.2) & (np.abs(x - 7.5) < 6))
    diag = (np.abs((x - 7.5) - (y - 7.5)) < 1.0) & (r < 4.2)
    diag |= (np.abs((x - 7.5) + (y - 7.5)) < 1.0) & (r < 4.2)
    put(img, plus | diag, (255, 255, 255, 255))
    put(img, r < 2.2, (255, 255, 255, 255))
    save(img, VFX_DIR, "spark")


def gen_ember():
    img = canvas(16)
    x, y, r, _ = coords(16)
    blob = r < 4.5
    jitter = rng.random((16, 16)) < 0.35
    edge = (r >= 4.5) & (r < 6.0) & jitter
    put(img, blob | edge, (255, 255, 255, 255))
    save(img, VFX_DIR, "ember")


def gen_dust():
    img = canvas(16)
    x, y, r, _ = coords(16)
    n = rng.random((16, 16))
    body = (r < 5.5) & (n > 0.15)
    fringe = (r >= 5.5) & (r < 7.0) & (n > 0.6)
    put(img, body, (255, 255, 255, 230))
    put(img, fringe, (255, 255, 255, 140))
    save(img, VFX_DIR, "dust")


def gen_shard():
    img = canvas(16)
    x, y, r, _ = coords(16)
    # Angular chunk: triangle-ish rock shard
    tri = (y > 3) & (y < 13) & (np.abs(x - 7.5) < (y - 2) * 0.55) & (x + y > 9)
    put(img, tri, (255, 255, 255, 255))
    save(img, VFX_DIR, "shard")


def gen_smoke():
    img = canvas(24)
    x, y, r, _ = coords(24)
    n = rng.random((24, 24))
    body = (r < 8.5) & (n > 0.2)
    holes = (n > 0.85) & (r < 8.5)
    put(img, body, (255, 255, 255, 200))
    put(img, holes, (255, 255, 255, 0))
    fringe = (r >= 8.5) & (r < 10.5) & (n > 0.55)
    put(img, fringe, (255, 255, 255, 110))
    save(img, VFX_DIR, "smoke")


def gen_flash():
    img = canvas(32)
    x, y, r, ang = coords(32)
    star = np.zeros((32, 32), dtype=bool)
    for k in range(8):
        a = k * np.pi / 4
        d = np.abs(np.sin(ang - a)) * r
        star |= (d < 1.6) & (r < (14 if k % 2 == 0 else 9))
    core = r < 5
    ringm = (r > 6) & (r < 8) & (rng.random((32, 32)) < 0.5)
    alpha = np.where(core, 255, np.where(star, 220, np.where(ringm, 160, 0)))
    put(img, core | star | ringm, (255, 255, 255, 0))
    img[..., 3] = alpha
    img[..., 0] = 255
    img[..., 1] = 255
    img[..., 2] = 255
    save(img, VFX_DIR, "flash")


def gen_glyph():
    img = canvas(32)
    # Angular rune: connected strokes on a coarse grid
    pts = [(8, 24), (8, 8), (24, 8), (16, 16), (24, 24), (16, 28)]
    mask = np.zeros((32, 32), dtype=bool)
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        steps = max(abs(x1 - x0), abs(y1 - y0)) + 1
        for t in np.linspace(0, 1, steps * 2):
            xi = int(round(x0 + (x1 - x0) * t))
            yi = int(round(y0 + (y1 - y0) * t))
            mask[max(yi - 1, 0):yi + 1, max(xi - 1, 0):xi + 1] = True
    put(img, mask, (255, 255, 255, 255))
    save(img, VFX_DIR, "glyph")


def gen_ring():
    img = canvas(64)
    x, y, r, _ = coords(64)
    ringm = (r > 24) & (r < 30)
    notch = rng.random((64, 64)) > 0.12  # broken pixel edge
    put(img, ringm & notch, (255, 255, 255, 255))
    save(img, VFX_DIR, "ring")


def gen_slash():
    img = canvas(64)
    x, y, r, ang = coords(64)
    # Crescent arc opening downward, thick in the middle, tapered ends
    arc = (r > 18) & (r < 30) & (ang > -2.6) & (ang < -0.5)
    taper = np.clip((np.cos((ang + 1.55) * 1.5)), 0, 1)
    thick = (r > 18 + (1 - taper) * 8) & (r < 30 - (1 - taper) * 4)
    m = arc & thick
    put(img, m, (255, 255, 255, 235))
    inner = m & (r < 22)
    put(img, inner, (255, 255, 255, 255))
    save(img, VFX_DIR, "slash")


def gen_scorch():
    img = canvas(64)
    x, y, r, ang = coords(64)
    n = rng.random((64, 64))
    radius = 22 + np.sin(ang * 5 + 1.3) * 4 + n * 4
    body = r < radius
    alpha = np.where(r < radius * 0.5, 220, np.where(body, 150, 0))
    alpha = np.where(body & (n > 0.8), 60, alpha)
    img[..., 0] = 20
    img[..., 1] = 12
    img[..., 2] = 10
    img[..., 3] = alpha
    # hot rim remnants
    rim = body & (r > radius * 0.75) & (n > 0.75)
    put(img, rim, (200, 90, 30, 180))
    save(img, VFX_DIR, "scorch")


def gen_cracks():
    img = canvas(64)
    mask = np.zeros((64, 64), dtype=bool)
    for k in range(7):
        a = k * (2 * np.pi / 7) + rng.random() * 0.5
        x0, y0 = 31.5, 31.5
        for step in range(26):
            x0 += np.cos(a) * 1.0
            y0 += np.sin(a) * 1.0
            a += (rng.random() - 0.5) * 0.5
            xi, yi = int(x0), int(y0)
            if 0 <= xi < 64 and 0 <= yi < 64:
                mask[yi, xi] = True
                if step < 14 and xi + 1 < 64:
                    mask[yi, xi + 1] = True
    img[..., 0] = 15
    img[..., 1] = 10
    img[..., 2] = 8
    img[..., 3] = np.where(mask, 230, 0)
    save(img, VFX_DIR, "cracks")


def gen_telegraph():
    img = canvas(64)
    x, y, r, _ = coords(64)
    disc = r < 29
    rim = (r > 26) & (r < 29)
    alpha = np.where(rim, 255, np.where(disc, 90, 0))
    img[..., 0] = 255
    img[..., 1] = 255
    img[..., 2] = 255
    img[..., 3] = alpha
    save(img, VFX_DIR, "telegraph")


# --- Environment textures --------------------------------------------------

FLOOR_PAL = [(52, 44, 62), (62, 53, 74), (72, 62, 84), (45, 38, 55)]
STONE_PAL = [(88, 80, 102), (102, 94, 118), (76, 68, 90), (95, 87, 110)]


def _brick_texture(size, pal, brick_w, brick_h, mortar_color):
    img = np.zeros((size, size, 4), dtype=np.float32)
    img[..., 3] = 255
    for by in range(0, size, brick_h):
        offset = (by // brick_h % 2) * (brick_w // 2)
        for bx in range(-brick_w, size + brick_w, brick_w):
            c = pal[rng.integers(len(pal))]
            x0 = bx + offset
            noise = rng.integers(-4, 5, size=(brick_h, brick_w, 3))
            for i in range(3):
                ys, ye = by, min(by + brick_h - 1, size)
                xs, xe = max(x0, 0), min(x0 + brick_w - 1, size)
                if ys >= ye or xs >= xe:
                    continue
                img[ys:ye, xs:xe, i] = c[i] + noise[: ye - ys, : xe - xs, i]
    # mortar lines
    for by in range(0, size, brick_h):
        img[by, :, :3] = mortar_color
    for by in range(0, size, brick_h):
        offset = (by // brick_h % 2) * (brick_w // 2)
        for bx in range(-brick_w, size + brick_w, brick_w):
            x0 = bx + offset
            if 0 <= x0 < size:
                img[by:by + brick_h, x0, :3] = mortar_color
    return img


def gen_floor():
    img = _brick_texture(64, FLOOR_PAL, 16, 16, (30, 25, 40))
    # sparse, subdued moss accents — dense bright speckle read as noise in game
    n = rng.random((64, 64))
    accent = n > 0.996
    put_rgb = (52, 78, 70)
    for i in range(3):
        img[..., i] = np.where(accent, put_rgb[i], img[..., i])
    save(img, TEX_DIR, "floor")


def gen_stone():
    img = _brick_texture(64, STONE_PAL, 32, 12, (50, 44, 62))
    save(img, TEX_DIR, "stone")


def gen_rune_stone():
    img = _brick_texture(64, STONE_PAL, 32, 12, (50, 44, 62))
    # teal rune strokes carved across
    pts = [(16, 48), (16, 20), (40, 20), (30, 34), (46, 44)]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        steps = max(abs(x1 - x0), abs(y1 - y0)) + 1
        for t in np.linspace(0, 1, steps * 2):
            xi = int(round(x0 + (x1 - x0) * t))
            yi = int(round(y0 + (y1 - y0) * t))
            img[yi:yi + 2, xi:xi + 2, 0] = 60
            img[yi:yi + 2, xi:xi + 2, 1] = 190
            img[yi:yi + 2, xi:xi + 2, 2] = 180
    save(img, TEX_DIR, "rune_stone")


ASH_PAL = [(74, 62, 56), (86, 72, 64), (64, 54, 50), (92, 78, 66)]
ASH_ROCK_PAL = [(96, 82, 72), (110, 94, 82), (84, 72, 64), (102, 88, 78)]


def gen_ash_ground():
    img = np.zeros((64, 64, 4), dtype=np.float32)
    img[..., 3] = 255
    n = rng.random((64, 64))
    # Cracked ash flats: irregular cells via coarse noise threshold bands
    base = rng.integers(0, len(ASH_PAL), size=(8, 8))
    for y in range(64):
        for x in range(64):
            c = ASH_PAL[base[y // 8, x // 8]]
            jitter = rng.integers(-5, 6)
            for i in range(3):
                img[y, x, i] = c[i] + jitter
    # ember flecks + dark cracks
    cracks = n < 0.04
    embers = n > 0.995
    for i, v in enumerate((38, 30, 28)):
        img[..., i] = np.where(cracks, v, img[..., i])
    for i, v in enumerate((200, 110, 40)):
        img[..., i] = np.where(embers, v, img[..., i])
    save(img, TEX_DIR, "ash_ground")


def gen_ash_rock():
    img = _brick_texture(64, ASH_ROCK_PAL, 32, 10, (58, 48, 42))
    save(img, TEX_DIR, "ash_rock")


SPIRE_PAL = [(38, 30, 54), (46, 38, 64), (32, 26, 46), (52, 42, 72)]
SPIRE_WALL_PAL = [(52, 44, 76), (62, 52, 88), (44, 36, 66), (58, 48, 82)]


def gen_spire_floor():
    img = _brick_texture(64, SPIRE_PAL, 16, 16, (22, 18, 34))
    # teal rune inlays on some tiles
    for _ in range(3):
        bx, by = rng.integers(0, 4) * 16, rng.integers(0, 4) * 16
        pts = [(4, 12), (4, 4), (12, 4), (8, 8), (12, 12)]
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            steps = max(abs(x1 - x0), abs(y1 - y0)) + 1
            for tt in np.linspace(0, 1, steps * 2):
                xi = bx + int(round(x0 + (x1 - x0) * tt))
                yi = by + int(round(y0 + (y1 - y0) * tt))
                if xi < 63 and yi < 63:
                    img[yi, xi, 0] = 70
                    img[yi, xi, 1] = 200
                    img[yi, xi, 2] = 190
    save(img, TEX_DIR, "spire_floor")


def gen_spire_wall():
    img = _brick_texture(64, SPIRE_WALL_PAL, 32, 8, (30, 24, 46))
    # violet crystal seams
    n = rng.random((64, 64))
    seams = n > 0.992
    for i, v in enumerate((150, 90, 220)):
        img[..., i] = np.where(seams, v, img[..., i])
    save(img, TEX_DIR, "spire_wall")


if __name__ == "__main__":
    print("VFX sprites:")
    gen_spark(); gen_ember(); gen_dust(); gen_shard(); gen_smoke()
    gen_flash(); gen_glyph(); gen_ring(); gen_slash(); gen_scorch()
    gen_cracks(); gen_telegraph()
    print("Environment textures:")
    gen_floor(); gen_stone(); gen_rune_stone(); gen_ash_ground(); gen_ash_rock()
    gen_spire_floor(); gen_spire_wall()
    print("done.")
