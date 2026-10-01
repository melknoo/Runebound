"""RUNEBOUND world bake (M08): declarative layout -> heightmap, path mask, map.

Run:  python tools/worldgen/bake.py
Out:  assets/world/highlands/height.r16      uint16 LE, row 0 = north (z = -192),
                                             height = v / 65535 * height_max
      assets/world/highlands/path_mask.png   L8, 2 px/m, routes + trampled camp floors
      assets/world/highlands/map.png         RGBA pixel-style map (no markers)
      assets/world/highlands/biome_mask.png  RGBA, 1 px/m, M12 sub-biome weights
                                             (R village, G burnt forest, B bone field)
      assets/world/highlands/layout.json     the layout plus baked POI heights

Deterministic: a second run is byte-identical. The bake asserts the layout
rules (pad flatness, route grade, camp spacing, POI density) so a bad layout
fails here, not in play.
"""
from __future__ import annotations

import json
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from highlands_layout import LAYOUT  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "world", "highlands")
MAP_PX_PER_M = 2
BIOME_PX_PER_M = 1
PAD_BLEND = 10.0
# M12: every POI type the zone knows (an unknown one is a layout typo), the
# small ones (lore objects, collectibles, scenes) that neither need nor give
# the 80 m density, and the trampled-floor radius per type in the path mask.
KNOWN_TYPES = {"spawn", "portal", "waypoint", "camp", "chest", "landmark", "ruin", "ambush", "dungeon",
               "elite_patrol", "arena", "village", "puzzle_braziers", "puzzle_boulder", "puzzle_monolith",
               "puzzle_dodge", "trial", "nest", "cursed", "cave", "lore", "ghost", "shard", "vignette"}
SMALL_TYPES = {"lore", "ghost", "shard", "vignette"}
FLOOR_RADIUS = {"camp": 6.5, "ruin": 5.0, "ambush": 3.5, "arena": 12.0, "spawn": 5.0, "waypoint": 3.0,
                "dungeon": 4.0, "village": 8.0, "trial": 5.0, "nest": 5.0, "cursed": 6.0, "cave": 3.5,
                "puzzle_braziers": 4.0, "puzzle_monolith": 4.0, "puzzle_dodge": 3.0}
ROUTE_BLEND = 6.0
BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32) / 16.0 - 0.5


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

def smoothstep(t: np.ndarray | float) -> np.ndarray | float:
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def value_noise(res: int, cells: int, rng: np.random.Generator) -> np.ndarray:
    """Non-tiling smooth value noise in [0, 1] over a res x res grid."""
    grid = rng.random((cells + 2, cells + 2)).astype(np.float32)
    coords = np.arange(res, dtype=np.float32) * cells / (res - 1)
    i0 = np.floor(coords).astype(int)
    i1 = np.minimum(i0 + 1, cells + 1)
    t = coords - np.floor(coords)
    t = t * t * (3.0 - 2.0 * t)
    ty, tx = np.meshgrid(t, t, indexing="ij")
    y0, x0 = np.meshgrid(i0, i0, indexing="ij")
    y1, x1 = np.meshgrid(i1, i1, indexing="ij")
    top = grid[y0, x0] * (1 - tx) + grid[y0, x1] * tx
    bottom = grid[y1, x0] * (1 - tx) + grid[y1, x1] * tx
    return top * (1 - ty) + bottom * ty


def fbm(res: int, octaves: list, rng: np.random.Generator) -> np.ndarray:
    out = np.zeros((res, res), dtype=np.float32)
    total = 0.0
    for cells, weight in octaves:
        out += value_noise(res, int(cells), rng) * weight
        total += weight
    return out / max(total, 1e-6)


class Field:
    """Height field on a regular grid: h[iz, ix], world x = ox + ix, z = oz + iz."""

    def __init__(self, res: int, origin: tuple[float, float]):
        self.res = res
        self.ox, self.oz = origin
        self.h = np.zeros((res, res), dtype=np.float32)
        self.route_w = np.zeros((res, res), dtype=np.float32)
        self.route_core = np.zeros((res, res), dtype=np.float32)
        xs = self.ox + np.arange(res, dtype=np.float32)
        zs = self.oz + np.arange(res, dtype=np.float32)
        self.X, self.Z = np.meshgrid(xs, zs)  # X[iz, ix], Z[iz, ix]

    def sample(self, x, z):
        """Bilinear height at world (x, z); arrays or scalars."""
        fx = np.clip(np.asarray(x, dtype=np.float32) - self.ox, 0, self.res - 1.001)
        fz = np.clip(np.asarray(z, dtype=np.float32) - self.oz, 0, self.res - 1.001)
        ix = np.floor(fx).astype(int)
        iz = np.floor(fz).astype(int)
        tx = fx - ix
        tz = fz - iz
        h = self.h
        return ((h[iz, ix] * (1 - tx) + h[iz, ix + 1] * tx) * (1 - tz)
                + (h[iz + 1, ix] * (1 - tx) + h[iz + 1, ix + 1] * tx) * tz)

    def window(self, x0: float, z0: float, x1: float, z1: float, margin: float):
        """Index slices covering the world box plus margin (clamped)."""
        ix0 = max(int(math.floor(min(x0, x1) - margin - self.ox)), 0)
        ix1 = min(int(math.ceil(max(x0, x1) + margin - self.ox)) + 1, self.res)
        iz0 = max(int(math.floor(min(z0, z1) - margin - self.oz)), 0)
        iz1 = min(int(math.ceil(max(z0, z1) + margin - self.oz)) + 1, self.res)
        return slice(iz0, iz1), slice(ix0, ix1)


def seg_distance(X, Z, a, b):
    """Distance from grid points to segment a-b and the segment parameter t."""
    ax, az = a
    bx, bz = b
    abx, abz = bx - ax, bz - az
    ab2 = max(abx * abx + abz * abz, 1e-6)
    t = np.clip(((X - ax) * abx + (Z - az) * abz) / ab2, 0.0, 1.0)
    px = ax + abx * t
    pz = az + abz * t
    return np.hypot(X - px, Z - pz), t


def resample(points: list, step: float = 1.0) -> np.ndarray:
    out = [np.array(points[0], dtype=np.float32)]
    for a, b in zip(points[:-1], points[1:]):
        a = np.array(a, dtype=np.float32)
        b = np.array(b, dtype=np.float32)
        n = max(int(math.ceil(np.linalg.norm(b - a) / step)), 1)
        for k in range(1, n + 1):
            out.append(a + (b - a) * (k / n))
    return np.array(out)


# ---------------------------------------------------------------------------
# terrain stages
# ---------------------------------------------------------------------------

def build_base(f: Field, lay: dict, rng: np.random.Generator) -> None:
    base = lay["base"]
    size = lay["size_m"]
    south = (f.Z - f.oz) / size  # 0 north .. 1 south
    f.h += base["north_y"] + (base["south_y"] - base["north_y"]) * south
    f.h += (fbm(f.res, base["noise_octaves"], rng) - 0.5) * 2.0 * base["amplitude"]


def add_ridges(f: Field, lay: dict) -> None:
    for r in lay["ridges"]:
        sigma = r["width"] / 2.355  # width ~ FWHM
        zs, xs = f.window(r["a"][0], r["a"][1], r["b"][0], r["b"][1], r["width"] * 1.5)
        d, _ = seg_distance(f.X[zs, xs], f.Z[zs, xs], r["a"], r["b"])
        f.h[zs, xs] += r["height"] * np.exp(-0.5 * (d / sigma) ** 2)


def add_plateaus(f: Field, lay: dict) -> None:
    for p in lay["plateaus"]:
        d = np.hypot(f.X - p["pos"][0], f.Z - p["pos"][1])
        w = smoothstep(1.0 - (d - p["radius"]) / p["blend"])
        f.h += p["height"] * w


def add_rim(f: Field, lay: dict, rng: np.random.Generator) -> None:
    rim = lay["rim"]
    half = lay["size_m"] * 0.5
    cheb = np.maximum(np.abs(f.X), np.abs(f.Z))
    t = np.clip((cheb - rim["start_m"]) / (half - rim["start_m"]), 0.0, 1.0)
    jag = (value_noise(f.res, 24, rng) - 0.5) * 6.0
    f.h += rim["height"] * t * t + jag * t


def add_bump(f: Field, lay: dict) -> None:
    b = lay.get("test_bump")
    if not b:
        return
    d = np.hypot(f.X - b["pos"][0], f.Z - b["pos"][1])
    f.h += b["height"] * smoothstep(1.0 - d / b["radius"])


def pad_list(lay: dict) -> list:
    """(x, z, pad_radius) for every flat pad in the layout (portals included)."""
    pads = []
    for poi in lay["pois"]:
        if poi.get("pad", 0) > 0:
            pads.append((poi["pos"][0], poi["pos"][1], float(poi["pad"])))
        for sub in poi.get("portals", []):
            pads.append((sub["pos"][0], sub["pos"][1], 5.0))
    return pads


def carve_routes(f: Field, lay: dict) -> dict:
    """Grade each route, then blend the terrain toward the route profile.
    Profiles keep the flat pads they cross (the pads were flattened before),
    and `f.route_w` remembers the corridor so the second pad pass leaves it."""
    profiles = {}
    pads = pad_list(lay)
    f.route_w = np.zeros_like(f.h)
    f.route_core = np.zeros_like(f.h)
    # pads are untouchable for the carve (hard edge: inside = pad height,
    # outside = the graded profile, which is fixed to that height at the edge)
    pad_w = np.zeros_like(f.h)
    for px, pz, pr in pads:
        d = np.hypot(f.X - px, f.Z - pz)
        pad_w = np.maximum(pad_w, (d <= pr).astype(np.float32))
    for route in lay["routes"]:
        pts = resample(route["points"], 1.0)
        h = f.sample(pts[:, 0], pts[:, 1]).astype(np.float32)
        grade = float(route["grade_max"])
        if "test_grade" in route:
            # straight test ramp: exact constant grade from the start height
            h = h[0] + np.arange(len(h), dtype=np.float32) * route["test_grade"]
        else:
            k = 21
            raw = h.copy()
            # samples inside an earlier route's corridor follow that terrain
            cz = np.clip(np.round(pts[:, 1] - f.oz).astype(int), 0, f.res - 1)
            cx = np.clip(np.round(pts[:, 0] - f.ox).astype(int), 0, f.res - 1)
            in_prev = f.route_core[cz, cx] > 0.5
            pad = np.pad(h, (k // 2, k // 2), mode="edge")
            h = np.convolve(pad, np.ones(k, dtype=np.float32) / k, mode="valid")
            # samples whose corridor touches a pad sit at the pad's height
            # (flat plateau); the grade clamp then bends the approaches, never
            # the pad
            half_w = route["width"] * 0.5
            fixed = np.zeros(len(h), dtype=bool)
            # junctions: a route's ends meet earlier routes (or pads) at the
            # height the terrain already has there
            h[0], h[-1] = raw[0], raw[-1]
            fixed[0] = fixed[-1] = True
            h[in_prev] = raw[in_prev]
            fixed |= in_prev
            for px, pz, pr in pads:
                inside = np.hypot(pts[:, 0] - px, pts[:, 1] - pz) <= pr + half_w
                if np.any(inside):
                    h[inside] = float(f.sample(px, pz))
                    fixed |= inside
            for _ in range(4):
                for i in range(1, len(h)):
                    if not fixed[i]:
                        h[i] = min(max(h[i], h[i - 1] - grade), h[i - 1] + grade)
                for i in range(len(h) - 2, -1, -1):
                    if not fixed[i]:
                        h[i] = min(max(h[i], h[i + 1] - grade), h[i + 1] + grade)
        half_w = route["width"] * 0.5
        # nearest segment wins: every cell takes the profile height of the
        # closest point on the route (blending per segment would let farther,
        # higher segments pull the corridor back up)
        best_d = np.full_like(f.h, np.inf)
        best_h = np.zeros_like(f.h)
        for i in range(len(pts) - 1):
            a, b = pts[i], pts[i + 1]
            zs, xs = f.window(a[0], a[1], b[0], b[1], half_w + ROUTE_BLEND + 1.0)
            d, t = seg_distance(f.X[zs, xs], f.Z[zs, xs], a, b)
            hr = h[i] * (1 - t) + h[i + 1] * t
            closer = d < best_d[zs, xs]
            best_d[zs, xs] = np.where(closer, d, best_d[zs, xs])
            best_h[zs, xs] = np.where(closer, hr, best_h[zs, xs])
        # earlier routes keep their core where a later one joins them; the
        # joining route may re-grade their outer blend (its approach ramp)
        w = smoothstep(1.0 - (best_d - half_w) / ROUTE_BLEND) * (1.0 - pad_w) * (1.0 - f.route_core)
        f.h = f.h * (1 - w) + best_h * w
        f.route_w = np.maximum(f.route_w, w)
        f.route_core = np.maximum(f.route_core, smoothstep((w - 0.6) / 0.4))
        profiles[route["id"]] = (pts, h)
    return profiles


def flatten_pads(f: Field, lay: dict, keep_routes: bool = False) -> None:
    """Flat pads under every POI (cosine blend to pad + PAD_BLEND). With
    `keep_routes`, graded route corridors are left alone (they already pass
    through the pad at its height)."""
    for poi in lay["pois"]:
        pads = [(poi["pos"], poi.get("pad", 0))]
        for sub in poi.get("portals", []):
            pads.append((sub["pos"], 5))
        for pos, pad in pads:
            if pad <= 0:
                continue
            if "pad_from" in poi:
                target = float(f.sample(poi["pad_from"][0], poi["pad_from"][1]))
            else:
                d0 = np.hypot(f.X - pos[0], f.Z - pos[1])
                inside = d0 <= max(pad * 0.5, 1.5)
                target = float(f.h[inside].mean())
            d = np.hypot(f.X - pos[0], f.Z - pos[1])
            w = smoothstep(1.0 - (d - pad) / PAD_BLEND)
            if keep_routes:
                w = w * (1.0 - f.route_w)
            f.h = f.h * (1 - w) + target * w


# ---------------------------------------------------------------------------
# outputs
# ---------------------------------------------------------------------------

def write_height(f: Field, lay: dict) -> None:
    hmax = float(lay["height_max"])
    assert f.h.min() >= 0.0, "terrain below 0: raise base heights (min %.2f)" % f.h.min()
    assert f.h.max() <= hmax, "terrain above height_max (max %.2f)" % f.h.max()
    q = np.round(f.h / hmax * 65535.0).astype("<u2")
    with open(os.path.join(OUT_DIR, "height.r16"), "wb") as fh:
        fh.write(q.tobytes())
    # quantized field for the map and the baked POI heights: what the game sees
    f.h = q.astype(np.float32) / 65535.0 * hmax


def map_grid(lay: dict):
    res = lay["size_m"] * MAP_PX_PER_M
    ox, oz = lay["origin"]
    xs = ox + (np.arange(res, dtype=np.float32) + 0.5) / MAP_PX_PER_M
    zs = oz + (np.arange(res, dtype=np.float32) + 0.5) / MAP_PX_PER_M
    return np.meshgrid(xs, zs)


def write_path_mask(f: Field, lay: dict, rng: np.random.Generator) -> None:
    X, Z = map_grid(lay)
    res = X.shape[0]
    mask = np.zeros((res, res), dtype=np.float32)
    jitter = (value_noise(res, 96, rng) - 0.5) * 1.6
    ox, oz = lay["origin"]

    def win(x0, z0, x1, z1, m):
        ix0 = max(int((min(x0, x1) - m - ox) * MAP_PX_PER_M), 0)
        ix1 = min(int((max(x0, x1) + m - ox) * MAP_PX_PER_M) + 2, res)
        iz0 = max(int((min(z0, z1) - m - oz) * MAP_PX_PER_M), 0)
        iz1 = min(int((max(z0, z1) + m - oz) * MAP_PX_PER_M) + 2, res)
        return slice(iz0, iz1), slice(ix0, ix1)

    for route in lay["routes"]:
        if "test_grade" in route or route.get("secret"):
            continue  # M12: secret routes leave no trail (ground or map)
        half_w = route["width"] * 0.5
        pts = resample(route["points"], 2.0)
        for a, b in zip(pts[:-1], pts[1:]):
            zs, xs = win(a[0], a[1], b[0], b[1], half_w + 2.0)
            d, _ = seg_distance(X[zs, xs], Z[zs, xs], a, b)
            edge = half_w + jitter[zs, xs]
            mask[zs, xs] = np.maximum(mask[zs, xs], smoothstep((edge - d) / 0.75 + 0.5))
    for poi in lay["pois"]:
        if poi["type"] in FLOOR_RADIUS and not poi.get("secret"):
            r = FLOOR_RADIUS[poi["type"]]
            zs, xs = win(poi["pos"][0], poi["pos"][1], poi["pos"][0], poi["pos"][1], r + 2.0)
            d = np.hypot(X[zs, xs] - poi["pos"][0], Z[zs, xs] - poi["pos"][1])
            edge = r + jitter[zs, xs]
            mask[zs, xs] = np.maximum(mask[zs, xs], smoothstep((edge - d) / 1.0 + 0.5))
    img = Image.fromarray((np.clip(mask, 0, 1) * 255).astype(np.uint8), mode="L")
    img.save(os.path.join(OUT_DIR, "path_mask.png"))


def hex_rgb(h: str):
    h = h.lstrip("#")
    return np.array([int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)], dtype=np.float32)


# ---------------------------------------------------------------------------
# M12 sub-biomes
# ---------------------------------------------------------------------------

def shape_distance(X, Z, shape: dict):
    """Signed distance (m) from grid points to a biome shape's edge (< 0 inside)."""
    if "circle" in shape:
        x, z, r = shape["circle"]
        return np.hypot(X - x, Z - z) - r
    a, b, r = shape["capsule"]
    d, _ = seg_distance(X, Z, a, b)
    return d - r


def biome_weights(lay: dict, X, Z, rng: np.random.Generator) -> np.ndarray:
    """(biomes, rows, cols) weights in [0, 1] at the grid points; each biome is
    1 inside its shapes and fades over `blend_m` with a ragged (noisy) edge;
    where several overlap they share (the sum never exceeds 1)."""
    biomes = lay.get("biomes", [])
    res = X.shape[0]
    out = np.zeros((max(len(biomes), 1), res, res), dtype=np.float32)
    for k, biome in enumerate(biomes):
        d = np.full(X.shape, np.inf, dtype=np.float32)
        for shape in biome["shapes"]:
            d = np.minimum(d, shape_distance(X, Z, shape))
        blend = float(biome.get("blend_m", 12.0))
        ragged = (value_noise(res, 40, rng) - 0.5) * blend * 0.9 + (value_noise(res, 110, rng) - 0.5) * blend * 0.35
        out[k] = smoothstep(0.5 - (d + ragged) / blend)
    total = out.sum(axis=0)
    over = total > 1.0
    out[:, over] /= total[over]
    return out[:len(biomes)]


def biome_grid(lay: dict):
    res = lay["size_m"] * BIOME_PX_PER_M
    ox, oz = lay["origin"]
    xs = ox + (np.arange(res, dtype=np.float32) + 0.5) / BIOME_PX_PER_M
    zs = oz + (np.arange(res, dtype=np.float32) + 0.5) / BIOME_PX_PER_M
    return np.meshgrid(xs, zs)


def write_biome_mask(weights: np.ndarray) -> None:
    res = weights.shape[1]
    out = np.zeros((res, res, 4), dtype=np.uint8)
    for k in range(min(weights.shape[0], 3)):
        out[..., k] = np.round(np.clip(weights[k], 0, 1) * 255).astype(np.uint8)
    out[..., 3] = 255
    Image.fromarray(out, mode="RGBA").save(os.path.join(OUT_DIR, "biome_mask.png"))


def biome_at(lay: dict, weights: np.ndarray, x: float, z: float) -> str:
    """The biome id at a point ("ash" unless one biome holds >= half)."""
    biomes = lay.get("biomes", [])
    if not biomes:
        return "ash"
    ox, oz = lay["origin"]
    res = weights.shape[1]
    ix = int(np.clip((x - ox) * BIOME_PX_PER_M, 0, res - 1))
    iz = int(np.clip((z - oz) * BIOME_PX_PER_M, 0, res - 1))
    w = weights[:, iz, ix]
    k = int(np.argmax(w))
    return biomes[k]["id"] if w[k] >= 0.5 else "ash"


def map_ramps(spec_pal: dict) -> list:
    """Height ramps for the map: the ash and, M12, one per sub-biome."""
    hl = spec_pal["highlands"]
    ash = [hex_rgb(c) for c in hl["ash_ground"]] + [hex_rgb(hl["ash_top"][2]), hex_rgb(hl["ash_top"][3])]
    vl = spec_pal["village"]
    village = [hex_rgb(c) for c in vl["earth"]] + [hex_rgb(vl["dead_grass"][2]), hex_rgb(vl["dead_grass"][3])]
    bf = spec_pal["burnt_forest"]
    forest = [hex_rgb(c) for c in bf["char"]] + [hex_rgb(bf["soot"][1]), hex_rgb(bf["soot"][2])]
    bn = spec_pal["bone_field"]
    bones = [hex_rgb(c) for c in bn["dust"]] + [hex_rgb(bn["bone_dark"][0]), hex_rgb(bn["bone_dark"][1])]
    return [ash, village, forest, bones]


def write_map(f: Field, lay: dict, weights: np.ndarray) -> None:
    with open(os.path.join(ROOT, "assets", "art_spec.json"), encoding="utf-8") as fh:
        palettes = json.load(fh)["palettes"]
    pal = palettes["highlands"]
    X, Z = map_grid(lay)
    res = X.shape[0]
    h = f.sample(X, Z)
    hmin, hmax = float(h.min()), float(np.percentile(h, 99.0))
    t = np.clip((h - hmin) / max(hmax - hmin, 1e-3), 0.0, 1.0)
    ramps = map_ramps(palettes)
    bayer = np.tile(BAYER4, (res // 4 + 1, res // 4 + 1))[:res, :res]
    idx = np.clip(np.floor(t * (len(ramps[0]) - 1) + 0.5 + bayer * 0.9).astype(int), 0, len(ramps[0]) - 1)
    # M12: each map pixel takes the ash or a sub-biome ramp, picked by the
    # dithered biome weights (a stepped, pixel-style edge)
    scale = res // weights.shape[1]
    w_map = np.repeat(np.repeat(weights, scale, axis=1), scale, axis=2)[:, :res, :res]
    pick = np.zeros((res, res), dtype=int)
    threshold = bayer + 0.5
    cum = np.zeros((res, res), dtype=np.float32)
    for k in range(w_map.shape[0]):
        cum = cum + w_map[k]
        pick = np.where((pick == 0) & (threshold < cum), k + 1, pick)
    rgb = np.zeros((res, res, 3), dtype=np.float32)
    for k, ramp in enumerate(ramps[:w_map.shape[0] + 1]):
        sel = pick == k
        rgb[sel] = np.array(ramp)[idx[sel]]
    # hillshade from the north-west, quantized to three steps
    gz, gx = np.gradient(h, 1.0 / MAP_PX_PER_M)
    shade = np.clip(1.0 + (-gx * 0.6 - gz * 0.6) * 0.35, 0.72, 1.18)
    shade = np.round(shade * 6.0) / 6.0
    rgb = rgb * shade[..., None]
    # contour lines every 4 m
    contour = (np.floor(h / 4.0) != np.floor(np.roll(h, 1, axis=0) / 4.0)) | \
              (np.floor(h / 4.0) != np.floor(np.roll(h, 1, axis=1) / 4.0))
    rgb[contour] = rgb[contour] * 0.72
    # rim mountains: basalt
    cheb = np.maximum(np.abs(X), np.abs(Z))
    rimmask = cheb > lay["rim"]["start_m"] + 6.0
    rgb[rimmask] = hex_rgb(pal["basalt"][1]) * shade[rimmask][..., None]
    # routes in trail colour from the mask
    mask = np.array(Image.open(os.path.join(OUT_DIR, "path_mask.png")), dtype=np.float32) / 255.0
    trail = hex_rgb(pal["dead_grass"][2])
    on = mask > 0.5
    rgb[on] = trail * shade[on][..., None]
    out = np.zeros((res, res, 4), dtype=np.uint8)
    out[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    out[..., 3] = 255
    Image.fromarray(out, mode="RGBA").save(os.path.join(OUT_DIR, "map.png"))


def validate(f: Field, lay: dict, profiles: dict) -> list[str]:
    problems = []
    gz, gx = np.gradient(f.h, 1.0)
    slope = np.hypot(gx, gz)
    camps = [p for p in lay["pois"] if p["type"] == "camp"]
    spawn = next(p for p in lay["pois"] if p["type"] == "spawn")
    for poi in lay["pois"]:
        pad = poi.get("pad", 0)
        if pad >= 3:
            d = np.hypot(f.X - poi["pos"][0], f.Z - poi["pos"][1])
            s = slope[d <= pad - 1.5].max() if np.any(d <= pad - 1.5) else 0.0
            if s > math.tan(math.radians(3.0)) + 0.02:
                problems.append("%s: pad slope %.3f" % (poi["id"], s))
    for i, a in enumerate(camps):
        da = math.dist(a["pos"], spawn["pos"])
        if da < 40.0:
            problems.append("%s: %.1f m from spawn (< 40)" % (a["id"], da))
        for b in camps[i + 1:]:
            d = math.dist(a["pos"], b["pos"])
            if d < 45.0:
                problems.append("%s-%s: camps %.1f m apart (< 45)" % (a["id"], b["id"], d))
    # density: every POI has a neighbour within 80 m (M12: the small ones -
    # lore, collectibles, scenes - neither need nor give it)
    major = [p for p in lay["pois"] if p["type"] not in SMALL_TYPES]
    for poi in major:
        best = min(math.dist(poi["pos"], o["pos"]) for o in major if o is not poi)
        if best > 80.0:
            problems.append("%s: nearest POI %.1f m (> 80)" % (poi["id"], best))
    # M12: known types only; nests and trial shrines keep clear of camps;
    # small POIs stay off the trails
    for poi in lay["pois"]:
        if poi["type"] not in KNOWN_TYPES:
            problems.append("%s: unknown POI type '%s'" % (poi["id"], poi["type"]))
        if poi["type"] in ("nest", "trial"):
            for c in camps:
                d = math.dist(poi["pos"], c["pos"])
                if d < 35.0:
                    problems.append("%s: %.1f m from %s (< 35)" % (poi["id"], d, c["id"]))
        if poi["type"] in SMALL_TYPES:
            for route in lay["routes"]:
                if route.get("secret") or "test_grade" in route:
                    continue
                for a, b in zip(route["points"][:-1], route["points"][1:]):
                    d, _ = seg_distance(np.array([poi["pos"][0]], dtype=np.float32),
                                        np.array([poi["pos"][1]], dtype=np.float32), a, b)
                    if float(d[0]) < route["width"] * 0.5 + 1.0:
                        problems.append("%s: on route %s" % (poi["id"], route["id"]))
                        break
    # route grade after pads
    for route in lay["routes"]:
        pts = resample(route["points"], 1.0)
        h = f.sample(pts[:, 0], pts[:, 1])
        g = np.abs(np.diff(h)).max()
        if g > route["grade_max"] + 0.06:
            problems.append("route %s: grade %.2f (> %.2f)" % (route["id"], g, route["grade_max"]))
    return problems


def write_layout(f: Field, lay: dict, weights: np.ndarray) -> None:
    out = json.loads(json.dumps(lay))  # deep copy, tuples -> lists
    for poi in out["pois"]:
        poi["y"] = round(float(f.sample(poi["pos"][0], poi["pos"][1])), 3)
        poi["biome"] = biome_at(lay, weights, poi["pos"][0], poi["pos"][1])
        for sub in poi.get("portals", []):
            sub["y"] = round(float(f.sample(sub["pos"][0], sub["pos"][1])), 3)
        if "patrol" in poi:
            poi["patrol_y"] = [round(float(f.sample(p[0], p[1])), 3) for p in poi["patrol"]]
    for area in out["areas"]:
        area["y"] = round(float(f.sample(area["pos"][0], area["pos"][1])), 3)
        area["biome"] = biome_at(lay, weights, area["pos"][0], area["pos"][1])
    out["baked"] = {
        "height_file": "height.r16",
        "min_y": round(float(f.h.min()), 3),
        "max_y": round(float(f.h.max()), 3),
        "map_px_per_m": MAP_PX_PER_M,
        "mask_bounds": [lay["origin"][0], lay["origin"][1], lay["size_m"], lay["size_m"]],
        "biome_file": "biome_mask.png",
        "biome_px_per_m": BIOME_PX_PER_M,
        "biome_ids": [b["id"] for b in lay.get("biomes", [])],
    }
    with open(os.path.join(OUT_DIR, "layout.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=1)
        fh.write("\n")


def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)
    lay = LAYOUT
    rng = np.random.default_rng(lay["seed"])
    f = Field(lay["resolution"], tuple(lay["origin"]))
    build_base(f, lay, rng)
    add_ridges(f, lay)
    add_plateaus(f, lay)
    add_rim(f, lay, rng)
    add_bump(f, lay)
    # pads first so the route grading already sees the flat plateaus, then
    # the routes, then the pads again (the route carve may have tilted them)
    flatten_pads(f, lay)
    profiles = carve_routes(f, lay)
    flatten_pads(f, lay, keep_routes=True)
    write_height(f, lay)
    problems = validate(f, lay, profiles)
    write_path_mask(f, lay, np.random.default_rng(lay["seed"] + 1))
    # M12: the sub-biome weights have their own generator, so the height and
    # the path mask stay byte-identical whatever the biomes do
    bx, bz = biome_grid(lay)
    weights = biome_weights(lay, bx, bz, np.random.default_rng(lay["seed"] + 2))
    write_biome_mask(weights)
    write_map(f, lay, weights)
    write_layout(f, lay, weights)
    print("height %.1f..%.1f m, %d POIs, %d routes, %d biomes" % (f.h.min(), f.h.max(), len(lay["pois"]),
                                                                len(lay["routes"]), len(lay.get("biomes", []))))
    for p in problems:
        print("  LAYOUT PROBLEM: " + p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
