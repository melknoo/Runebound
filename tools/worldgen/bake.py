"""RUNEBOUND world bake (M08): declarative layout -> heightmap, path mask, map.

Run:  python tools/worldgen/bake.py
Out:  assets/world/highlands/height.r16      uint16 LE, row 0 = north (z = -192),
                                             height = v / 65535 * height_max
      assets/world/highlands/path_mask.png   L8, 2 px/m, routes + trampled camp floors
      assets/world/highlands/map.png         RGBA pixel-style map (no markers)
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
PAD_BLEND = 10.0
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
        if "test_grade" in route:
            continue
        half_w = route["width"] * 0.5
        pts = resample(route["points"], 2.0)
        for a, b in zip(pts[:-1], pts[1:]):
            zs, xs = win(a[0], a[1], b[0], b[1], half_w + 2.0)
            d, _ = seg_distance(X[zs, xs], Z[zs, xs], a, b)
            edge = half_w + jitter[zs, xs]
            mask[zs, xs] = np.maximum(mask[zs, xs], smoothstep((edge - d) / 0.75 + 0.5))
    for poi in lay["pois"]:
        if poi["type"] in ("camp", "ruin", "ambush", "arena", "spawn", "waypoint", "dungeon"):
            r = {"camp": 6.5, "ruin": 5.0, "ambush": 3.5, "arena": 12.0, "spawn": 5.0, "waypoint": 3.0,
                 "dungeon": 4.0}[poi["type"]]
            zs, xs = win(poi["pos"][0], poi["pos"][1], poi["pos"][0], poi["pos"][1], r + 2.0)
            d = np.hypot(X[zs, xs] - poi["pos"][0], Z[zs, xs] - poi["pos"][1])
            edge = r + jitter[zs, xs]
            mask[zs, xs] = np.maximum(mask[zs, xs], smoothstep((edge - d) / 1.0 + 0.5))
    img = Image.fromarray((np.clip(mask, 0, 1) * 255).astype(np.uint8), mode="L")
    img.save(os.path.join(OUT_DIR, "path_mask.png"))


def hex_rgb(h: str):
    h = h.lstrip("#")
    return np.array([int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)], dtype=np.float32)


def write_map(f: Field, lay: dict) -> None:
    with open(os.path.join(ROOT, "assets", "art_spec.json"), encoding="utf-8") as fh:
        pal = json.load(fh)["palettes"]["highlands"]
    X, Z = map_grid(lay)
    res = X.shape[0]
    h = f.sample(X, Z)
    hmin, hmax = float(h.min()), float(np.percentile(h, 99.0))
    t = np.clip((h - hmin) / max(hmax - hmin, 1e-3), 0.0, 1.0)
    ramp = [hex_rgb(c) for c in pal["ash_ground"]] + [hex_rgb(pal["ash_top"][2]), hex_rgb(pal["ash_top"][3])]
    bayer = np.tile(BAYER4, (res // 4 + 1, res // 4 + 1))[:res, :res]
    idx = np.clip(np.floor(t * (len(ramp) - 1) + 0.5 + bayer * 0.9).astype(int), 0, len(ramp) - 1)
    rgb = np.stack([np.array(ramp)[idx][..., c] for c in range(3)], axis=-1)
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
    # density: every POI has a neighbour within 80 m
    for poi in lay["pois"]:
        best = min(math.dist(poi["pos"], o["pos"]) for o in lay["pois"] if o is not poi)
        if best > 80.0:
            problems.append("%s: nearest POI %.1f m (> 80)" % (poi["id"], best))
    # route grade after pads
    for route in lay["routes"]:
        pts = resample(route["points"], 1.0)
        h = f.sample(pts[:, 0], pts[:, 1])
        g = np.abs(np.diff(h)).max()
        if g > route["grade_max"] + 0.06:
            problems.append("route %s: grade %.2f (> %.2f)" % (route["id"], g, route["grade_max"]))
    return problems


def write_layout(f: Field, lay: dict) -> None:
    out = json.loads(json.dumps(lay))  # deep copy, tuples -> lists
    for poi in out["pois"]:
        poi["y"] = round(float(f.sample(poi["pos"][0], poi["pos"][1])), 3)
        for sub in poi.get("portals", []):
            sub["y"] = round(float(f.sample(sub["pos"][0], sub["pos"][1])), 3)
        if "patrol" in poi:
            poi["patrol_y"] = [round(float(f.sample(p[0], p[1])), 3) for p in poi["patrol"]]
    for area in out["areas"]:
        area["y"] = round(float(f.sample(area["pos"][0], area["pos"][1])), 3)
    out["baked"] = {
        "height_file": "height.r16",
        "min_y": round(float(f.h.min()), 3),
        "max_y": round(float(f.h.max()), 3),
        "map_px_per_m": MAP_PX_PER_M,
        "mask_bounds": [lay["origin"][0], lay["origin"][1], lay["size_m"], lay["size_m"]],
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
    write_map(f, lay)
    write_layout(f, lay)
    print("height %.1f..%.1f m, %d POIs, %d routes" % (f.h.min(), f.h.max(), len(lay["pois"]), len(lay["routes"])))
    for p in problems:
        print("  LAYOUT PROBLEM: " + p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
