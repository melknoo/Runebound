"""RUNEBOUND biome texture kit (M06): tileable pixel-art surfaces generated
from the palettes in assets/art_spec.json.

Every texture tiles seamlessly (periodic noise, wrap-around Voronoi) at the
environment texel density (64 px tile = 2 m at 32 px/m). Pixel-art rules:
values are quantized onto a palette ramp, transitions use a 4x4 Bayer
dither, clusters get a one-step emboss from a top-left light, and every
texture has its own seed so adding one never reshuffles the others.

Run:  python tools/texgen/biome.py      (also called by generate.py)
Out:  assets/textures/biome/*.png
"""
from __future__ import annotations

import json
import os
import zlib

import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "textures", "biome")
BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32) / 16.0 - 0.5


def load_spec() -> dict:
    with open(os.path.join(ROOT, "assets", "art_spec.json"), encoding="utf-8") as f:
        return json.load(f)


def rng_for(name: str) -> np.random.Generator:
    return np.random.default_rng(zlib.crc32(name.encode("utf-8")))


def hex_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


# ---------------------------------------------------------------------------
# Tileable fields
# ---------------------------------------------------------------------------

def value_noise(size: int, cells: int, rng: np.random.Generator) -> np.ndarray:
    """Periodic smooth value noise in [0, 1] (smoothstep-interpolated grid)."""
    grid = rng.random((cells, cells)).astype(np.float32)
    coords = np.arange(size, dtype=np.float32) * cells / size
    i0 = np.floor(coords).astype(int) % cells
    i1 = (i0 + 1) % cells
    t = coords - np.floor(coords)
    t = t * t * (3.0 - 2.0 * t)
    ty, tx = np.meshgrid(t, t, indexing="ij")
    y0, x0 = np.meshgrid(i0, i0, indexing="ij")
    y1, x1 = np.meshgrid(i1, i1, indexing="ij")
    top = grid[y0, x0] * (1 - tx) + grid[y0, x1] * tx
    bottom = grid[y1, x0] * (1 - tx) + grid[y1, x1] * tx
    return top * (1 - ty) + bottom * ty


def fbm(size: int, rng: np.random.Generator, octaves=((4, 0.55), (8, 0.3), (16, 0.15))) -> np.ndarray:
    total = np.zeros((size, size), dtype=np.float32)
    for cells, amp in octaves:
        total += value_noise(size, cells, rng) * amp
    lo, hi = total.min(), total.max()
    return (total - lo) / max(hi - lo, 1e-6)


def voronoi(size: int, points: int, rng: np.random.Generator):
    """Wrap-around Voronoi: (F1, F2, nearest-id) in pixels."""
    pts = rng.random((points, 2)) * size
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    d = np.empty((points, size, size), dtype=np.float32)
    for k, (px, py) in enumerate(pts):
        dx = np.abs(x - px)
        dy = np.abs(y - py)
        dx = np.minimum(dx, size - dx)
        dy = np.minimum(dy, size - dy)
        d[k] = np.sqrt(dx * dx + dy * dy)
    order = np.argsort(d, axis=0)
    f1 = np.take_along_axis(d, order[0:1], axis=0)[0]
    f2 = np.take_along_axis(d, order[1:2], axis=0)[0]
    return f1, f2, order[0]


def dither(shape: tuple[int, int], strength: float) -> np.ndarray:
    return np.tile(BAYER4, (shape[0] // 4, shape[1] // 4)) * strength


def quantize(field: np.ndarray, steps: int, dither_strength: float = 0.6) -> np.ndarray:
    """Field in [0,1] -> integer ramp index with ordered dither on the edges."""
    v = field * steps + dither(field.shape, dither_strength)
    return np.clip(np.floor(v), 0, steps - 1).astype(int)


def emboss(height: np.ndarray, threshold: float = 0.04) -> np.ndarray:
    """+1 where the surface faces the top-left light, -1 where it turns away."""
    slope = (np.roll(height, 1, axis=1) - height) + (np.roll(height, 1, axis=0) - height)
    out = np.zeros_like(height, dtype=int)
    out[slope < -threshold] = 1
    out[slope > threshold] = -1
    return out


def paint(index: np.ndarray, ramp: list[str]) -> np.ndarray:
    colors = np.array([hex_rgb(c) for c in ramp], dtype=np.float32)
    idx = np.clip(index, 0, len(ramp) - 1)
    rgba = np.empty(idx.shape + (4,), dtype=np.float32)
    rgba[..., :3] = colors[idx]
    rgba[..., 3] = 255
    return rgba


def save(name: str, rgba: np.ndarray) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    arr = np.clip(rgba, 0, 255).astype(np.uint8)
    Image.fromarray(arr, "RGBA").save(os.path.join(OUT_DIR, f"{name}.png"))
    print(f"  biome/{name}.png ({arr.shape[1]}x{arr.shape[0]})")


# ---------------------------------------------------------------------------
# Ashen Highlands
# ---------------------------------------------------------------------------

def ash_surface(name: str, ramp: list[str], base: int, pebbles: int, cracks: bool) -> None:
    """Calm play-surface: two neighbouring ramp steps with sparse dithered
    patches, few embossed pebbles, optional crack lines. The ground is the
    backdrop for telegraphs and characters (value band 25-40), so contrast
    stays low and noise stays sparse."""
    size = 64
    rng = rng_for(name)
    height = fbm(size, rng, ((4, 0.7), (8, 0.3)))
    # 0/1 around the base step; dither only near the threshold (sparse patches)
    idx = np.full((size, size), base, dtype=int)
    patch = height + dither((size, size), 0.18) > 0.62
    idx = np.where(patch, base + 1, idx)
    f1, f2, _ = voronoi(size, pebbles, rng)
    pebble = f1 < 1.6 + rng.random() * 0.4
    idx = np.where(pebble, base + 1, idx)
    shadow = np.roll(np.roll(pebble, 1, axis=0), 1, axis=1) & ~pebble
    idx = np.where(shadow, base - 1, idx)
    if cracks:
        edge = (f2 - f1) < 0.8
        idx = np.where(edge & (height > 0.4), base - 1, idx)
    save(name, paint(np.clip(idx, 0, len(ramp) - 1), ramp))


def basalt_columns(name: str, ramp: list[str]) -> None:
    """Vertical columnar basalt for cliff/ridge sides (world V = height)."""
    size = 64
    rng = rng_for(name)
    idx = np.zeros((size, size), dtype=int)
    x = 0
    widths = []
    while x < size:
        w = int(rng.integers(5, 14))
        widths.append(min(w, size - x))
        x += w
    x = 0
    rough = fbm(size, rng, ((4, 0.6), (8, 0.4)))
    for w in widths:
        base = int(rng.integers(1, 3))
        # few, irregular joints (periodic in y so the tile still wraps)
        period = int(rng.choice([32, 64]))
        phase = int(rng.integers(0, period))
        col = np.full((size, w), base, dtype=int)
        shade = rough[:, x:x + w]
        col = col + np.where(shade > 0.72, 1, 0) - np.where(shade < 0.22, 1, 0)
        col[:, 0] += 1            # lit left edge
        if w > 6:
            col[:, -1] -= 1       # shadowed right edge (narrow columns stay flat)
        joint_rows = ((np.arange(size) + phase) % period) == 0
        # joints are chipped, not ruled: only part of the column width
        chip = rng.integers(0, max(w - 2, 1))
        for yy in np.nonzero(joint_rows)[0]:
            col[yy, chip:chip + max(w // 2, 2)] = 0
        idx[:, x:x + w] = col
        x += w
    save(name, paint(np.clip(idx, 0, len(ramp) - 1), ramp))


def strata_rock(name: str, ramp: list[str]) -> None:
    """Horizontally layered ash rock for cliff and ridge sides: bands of blocky
    clusters, a dark crack under every band and a lit lip on top of it —
    reads as stratified rock (never as planks) and matches RockHull ledges."""
    size = 64
    rng = rng_for(name)
    idx = np.zeros((size, size), dtype=int)
    y = 0
    bands = []
    while y < size:
        hgt = int(rng.integers(7, 14))
        bands.append((y, min(hgt, size - y)))
        y += hgt
    f1, f2, cell = voronoi(size, 40, rng)
    rough = fbm(size, rng, ((4, 0.5), (8, 0.35), (16, 0.15)))
    for y0, hgt in bands:
        base = int(rng.integers(1, 3))
        rows = slice(y0, y0 + hgt)
        band = np.full((hgt, size), base, dtype=int)
        blocks = (cell[rows] % 3 == 0)
        band = np.where(blocks, base + 1, band)
        band = np.where(rough[rows] < 0.25, base - 1, band)
        edges = (f2[rows] - f1[rows]) < 0.9
        band = np.where(edges, base - 1, band)
        band[0, :] = np.minimum(band[0, :] + 1, len(ramp) - 1)   # lit lip
        band[-1, :] = 0                                          # crack below
        idx[rows] = band
    save(name, paint(np.clip(idx, 0, len(ramp) - 1), ramp))


def macro_noise(name: str) -> None:
    """Smooth grayscale blend mask, sampled with linear filtering at km scale."""
    size = 64
    rng = rng_for(name)
    field = fbm(size, rng, ((2, 0.6), (4, 0.3), (8, 0.1)))
    rgba = np.empty((size, size, 4), dtype=np.float32)
    rgba[..., 0] = rgba[..., 1] = rgba[..., 2] = field * 255
    rgba[..., 3] = 255
    save(name, rgba)


def sky_clouds(name: str) -> None:
    """Three-level pixel cloud mask (R) for the sky shader, tileable 128x64."""
    w, h = 128, 64
    rng = rng_for(name)
    big = np.tile(fbm(64, rng, ((4, 0.6), (8, 0.3), (16, 0.1))), (1, 2))
    streak = np.repeat(fbm(64, rng, ((8, 0.7), (16, 0.3)))[::2, :], 2, axis=0)
    field = np.clip(big * 0.75 + np.tile(streak, (1, 2)) * 0.25, 0, 1)
    level = quantize(field, 3, 0.5)
    rgba = np.zeros((h, w, 4), dtype=np.float32)
    rgba[..., 0] = rgba[..., 1] = rgba[..., 2] = level * 127.5
    rgba[..., 3] = 255
    save(name, rgba)


def flagstones(name: str, ramp: list[str], earth: list[str]) -> None:
    """Irregular flagstone paving: Voronoi slabs one or two steps apart, dark
    joints with earth showing through, a lit top-left lip per slab. 128 px
    (4 m) tile: large paved areas would show a 2 m repeat."""
    size = 128
    rng = rng_for(name)
    f1, f2, cell = voronoi(size, 56, rng)
    rough = fbm(size, rng, ((4, 0.6), (8, 0.4)))
    idx = 1 + (cell % 3 == 0).astype(int) + (rough > 0.7).astype(int)
    lit = emboss(-f1 / 8.0, 0.05) > 0
    idx = np.where(lit, idx + 1, idx)
    rgba = paint(np.clip(idx, 0, len(ramp) - 1), ramp)
    joint = (f2 - f1) < 1.3
    rgba[joint] = paint(np.full(joint.sum(), 1), earth)
    save(name, rgba)


def masonry(name: str, ramp: list[str]) -> None:
    """Coursed stone for walls and huts (world V = height): rows of blocks of
    varying width, recessed joints, a lit top edge on every block."""
    size = 64
    rng = rng_for(name)
    idx = np.zeros((size, size), dtype=int)
    rough = fbm(size, rng, ((4, 0.5), (8, 0.5)))
    y = 0
    while y < size:
        hgt = min(int(rng.integers(8, 13)), size - y)
        x = int(rng.integers(0, 10))
        start = x
        while x < start + size:
            w = int(rng.integers(10, 22))
            base = int(rng.integers(1, 4))
            for xx in range(x, min(x + w, start + size)):
                col = xx % size
                idx[y:y + hgt, col] = base
                idx[y, col] = min(base + 1, len(ramp) - 1)           # lit top edge
            idx[y:y + hgt, (x + w - 1) % size] = 0                   # vertical joint
            x += w
        idx[y + hgt - 1, :] = 0                                      # bed joint
        y += hgt
    idx = np.where((rough > 0.78) & (idx > 0), idx - 1, idx)        # weathering
    save(name, paint(np.clip(idx, 0, len(ramp) - 1), ramp))


def floor_tiles(name: str, ramp: list[str]) -> None:
    """Large dressed floor slabs (1 m = 32 px) in a 4 m tile: one ramp step per
    slab (+-1 at random), dark joints, a lit top-left lip, a few cracks and
    worn corners. Calm enough to read telegraphs on."""
    size, slab = 128, 32
    rng = rng_for(name)
    rough = fbm(size, rng, ((8, 0.6), (16, 0.4)))
    idx = np.zeros((size, size), dtype=int)
    for ty in range(size // slab):
        for tx in range(size // slab):
            base = int(rng.choice([1, 2, 2, 3]))
            y0, x0 = ty * slab, tx * slab
            idx[y0:y0 + slab, x0:x0 + slab] = base
            idx[y0 + 1, x0 + 1:x0 + slab - 1] = min(base + 1, len(ramp) - 1)      # lit lip
            idx[y0 + 1:y0 + slab - 1, x0 + 1] = min(base + 1, len(ramp) - 1)
            if rng.random() < 0.3:                                                 # crack
                cx, cy = x0 + int(rng.integers(6, slab - 6)), y0 + int(rng.integers(6, slab - 6))
                for k in range(int(rng.integers(6, 14))):
                    idx[cy % size, cx % size] = max(base - 1, 0)
                    cx += int(rng.integers(0, 2))
                    cy += int(rng.integers(-1, 2))
    wear = rough + dither((size, size), 0.2) > 0.72
    idx = np.where(wear & (idx > 1), idx - 1, idx)
    for k in range(0, size, slab):
        idx[k, :] = 0                                                              # joints
        idx[:, k] = 0
    save(name, paint(np.clip(idx, 0, len(ramp) - 1), ramp))


def crystal_facets(name: str, ramp: list[str]) -> None:
    """Faceted crystal (Spire): Voronoi facets shaded by a fake normal, bright
    ridges between facets."""
    size = 64
    rng = rng_for(name)
    f1, f2, cell = voronoi(size, 18, rng)
    idx = cell % 4
    ridge = (f2 - f1) < 1.0
    idx = np.where(ridge, len(ramp) - 1, idx)
    save(name, paint(np.clip(idx, 0, len(ramp) - 1), ramp))


def turf(name: str, ramp: list[str]) -> None:
    """Meadow / sod roof seen from above: short blade strokes (2-3 px, leaning
    with a shared wind) over a two-step base, a few lit tips."""
    size = 64
    rng = rng_for(name)
    height = fbm(size, rng, ((4, 0.6), (8, 0.4)))
    idx = np.where(height + dither((size, size), 0.2) > 0.55, 2, 1)
    for _ in range(170):
        x, y = int(rng.integers(0, size)), int(rng.integers(0, size))
        length = int(rng.integers(2, 4))
        shade = 3 if rng.random() < 0.25 else (0 if rng.random() < 0.35 else 2)
        for k in range(length):
            idx[(y - k) % size, (x + (k // 2)) % size] = shade
    save(name, paint(np.clip(idx, 0, len(ramp) - 1), ramp))


def generate_runehold() -> None:
    spec = load_spec()
    pal = spec["palettes"]["runehold"]
    print("Biome textures (Runehold):")
    flagstones("rh_flagstone", pal["flagstone"], pal["earth"])
    ash_surface("rh_earth", pal["earth"], 2, pebbles=8, cracks=False)
    ash_surface("rh_granite_top", pal["granite"], 2, pebbles=6, cracks=False)
    masonry("rh_masonry", pal["granite"])
    ash_surface("rh_moss", pal["moss"], 1, pebbles=10, cracks=False)
    turf("rh_turf", pal["turf"])


def generate_spire() -> None:
    spec = load_spec()
    pal = spec["palettes"]["spire"]
    print("Biome textures (Shattered Spire):")
    floor_tiles("sp_floor", pal["floor"])
    masonry("sp_wall", pal["wall"])
    ash_surface("sp_wall_top", pal["wall"], 2, pebbles=6, cracks=True)
    crystal_facets("sp_crystal", pal["crystal"])


def generate_highlands() -> None:
    spec = load_spec()
    pal = spec["palettes"]["highlands"]
    print("Biome textures (Ashen Highlands):")
    ash_surface("hl_ash_a", pal["ash_ground"], 2, pebbles=10, cracks=False)
    ash_surface("hl_ash_b", pal["ash_ground"], 1, pebbles=6, cracks=True)
    ash_surface("hl_ash_top", pal["ash_top"], 1, pebbles=8, cracks=False)
    ash_surface("hl_trail", pal["ash_ground"], 3, pebbles=14, cracks=False)  # M08 trodden trails (path mask)
    masonry("hl_masonry", pal["basalt"])  # M08 ruin walls
    basalt_columns("hl_basalt", pal["basalt"])
    strata_rock("hl_strata", pal["basalt"])
    macro_noise("macro_noise")
    sky_clouds("sky_clouds")


if __name__ == "__main__":
    generate_highlands()
    generate_runehold()
    generate_spire()
    print("done.")
