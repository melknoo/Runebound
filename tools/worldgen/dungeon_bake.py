"""RUNEBOUND dungeon bake (M13): declarative interior layout -> layout.json + map.png.

Run:  python tools/worldgen/dungeon_bake.py [cistern ...]     (no argument: every dungeon)
Out:  assets/world/<id>/layout.json   rooms, doors, merged wall boxes and the POIs with
                                      their floor heights (read by DungeonLayout)
      assets/world/<id>/map.png       pixel-style map (no markers; secret rooms left out)

A dungeon is rooms (axis-aligned rectangles with a floor height or a slope),
connectors (door gaps between two rooms) and points of interest. Rooms stand
apart by a wall gap; a connector carves a doorway through it. The bake
rasterises everything on a 0.5 m grid, grows the walls around the walkable
cells, merges them into a few boxes and asserts the layout rules, so a bad
layout fails here, not in play:
  * ids carry the dungeon's prefix and never collide (with each other or the
    Highlands: SaveGame keeps puzzle states and camps in flat dictionaries)
  * rooms never overlap and are at least 5 m wide (the camera's spring arm)
  * doors at least 4 m wide, bridging a gap of at most 3 m, with the same
    floor on both sides and inside both rooms
  * every room is reachable from the entry with all gates open; rooms tagged
    "secret" only through a "secret" door; a shortcut joins a far room with
    the entry's neighbourhood
  * combat rooms (tag or a camp / arena in them) at least 16 x 16 m
  * features stand 1.5 m clear of walls, camp triggers stay in their room
Deterministic: a second run is byte-identical.
"""
from __future__ import annotations

import importlib
import json
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from bake import BAYER4, hex_rgb  # noqa: E402
from highlands_layout import LAYOUT as HIGHLANDS  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
## dungeon id -> layout module (tools/worldgen/<module>.py, LAYOUT dict); "lab"
## is the test room of the puzzle kit (scenes/puzzle_lab.tscn, never reachable)
DUNGEONS = {"cistern": "cistern_layout", "lab": "lab_layout"}
GRID = 0.5            # m per raster cell
MAP_PX_PER_M = 3
WALL_REACH = 2.0      # m of wall grown around every walkable cell
BOUNDS_MARGIN = 4.0
MIN_ROOM = 5.0
MIN_DOOR = 4.0
MAX_GAP = 3.0
MIN_COMBAT = 16.0
FEATURE_CLEAR = 1.5
SPOT_CLEAR = 1.0
DOOR_KINDS = {"open", "gate", "secret", "shortcut"}
KNOWN_TYPES = {"portal", "camp", "chest", "lore", "rune", "arena", "tome", "light",
               "lever", "plate", "block", "reset", "beam", "water",
               "carrier", "element", "ice", "trap", "collapse"}
FEATURE_TYPES = {"camp", "chest", "rune", "arena", "tome", "portal", "lever", "plate", "block", "reset", "beam",
                 "carrier", "element"}
## POIs that belong in a channel (the water itself, an ice socket, a pit's tiles)
IN_CHANNEL_TYPES = {"water", "ice", "collapse"}
WATER_COLOR = "#1C4652"
COMBAT_TYPES = {"camp", "arena"}


# ---------------------------------------------------------------------------
# geometry
# ---------------------------------------------------------------------------

def floor_at(room: dict, x: float, z: float) -> float:
    """Floor height of a room at (x, z): flat, or a slope along x / z over a span."""
    slope = room.get("slope")
    if not slope:
        return float(room["floor"])
    c = x if slope["axis"] == "x" else z
    a, b = slope["span"]
    t = min(max((c - a) / (b - a), 0.0), 1.0)
    return float(slope["y"][0] + (slope["y"][1] - slope["y"][0]) * t)


def inside(rect, x: float, z: float, margin: float = 0.0) -> bool:
    return rect[0] + margin <= x <= rect[2] - margin and rect[1] + margin <= z <= rect[3] - margin


def door_rect(door: dict, a: dict, b: dict, problems: list) -> tuple[list, str]:
    """The doorway through the wall gap between rooms a and b at door["at"]:
    [x0, z0, x1, z1] and the axis the hero walks along ("x" or "z")."""
    ra, rb = a["rect"], b["rect"]
    w = float(door.get("width", MIN_DOOR))
    ax, az = door["at"]
    if ra[2] <= rb[0] or rb[2] <= ra[0]:  # side by side along x: the gap runs along x
        g0, g1 = (ra[2], rb[0]) if ra[2] <= rb[0] else (rb[2], ra[0])
        rect = [g0, az - w * 0.5, g1, az + w * 0.5]
        axis = "x"
        lateral = [(ra[1], ra[3]), (rb[1], rb[3])]
        lo, hi = az - w * 0.5, az + w * 0.5
    elif ra[3] <= rb[1] or rb[3] <= ra[1]:  # one above the other along z
        g0, g1 = (ra[3], rb[1]) if ra[3] <= rb[1] else (rb[3], ra[1])
        rect = [ax - w * 0.5, g0, ax + w * 0.5, g1]
        axis = "z"
        lateral = [(ra[0], ra[2]), (rb[0], rb[2])]
        lo, hi = ax - w * 0.5, ax + w * 0.5
    else:
        problems.append("%s: rooms %s and %s overlap, no wall gap" % (door["id"], a["id"], b["id"]))
        return [ax, az, ax, az], "x"
    gap = g1 - g0
    if gap <= 0.0 or gap > MAX_GAP + 1e-6:
        problems.append("%s: wall gap %.1f m (0 < gap <= %.0f)" % (door["id"], gap, MAX_GAP))
    if w < MIN_DOOR - 1e-6:
        problems.append("%s: door %.1f m wide (< %.0f)" % (door["id"], w, MIN_DOOR))
    for (l0, l1), room in zip(lateral, (a, b)):
        if lo < l0 + 0.5 or hi > l1 - 0.5:
            problems.append("%s: door runs past the side of %s" % (door["id"], room["id"]))
    return rect, axis


def door_floor(door: dict, a: dict, b: dict, axis: str, rect: list, problems: list) -> float:
    cx = (rect[0] + rect[2]) * 0.5
    cz = (rect[1] + rect[3]) * 0.5
    if axis == "x":
        fa = floor_at(a, min(max(cx, a["rect"][0]), a["rect"][2]), cz)
        fb = floor_at(b, min(max(cx, b["rect"][0]), b["rect"][2]), cz)
    else:
        fa = floor_at(a, cx, min(max(cz, a["rect"][1]), a["rect"][3]))
        fb = floor_at(b, cx, min(max(cz, b["rect"][1]), b["rect"][3]))
    if abs(fa - fb) > 0.05:
        problems.append("%s: floors differ across the door (%.2f / %.2f)" % (door["id"], fa, fb))
    return round(fa, 3)


class Raster:
    """The layout on a GRID raster: room / door index per cell, floor, walls."""

    def __init__(self, lay: dict, rooms: list, doors: list, problems: list):
        xs0 = min(r["rect"][0] for r in rooms) - BOUNDS_MARGIN
        zs0 = min(r["rect"][1] for r in rooms) - BOUNDS_MARGIN
        xs1 = max(r["rect"][2] for r in rooms) + BOUNDS_MARGIN
        zs1 = max(r["rect"][3] for r in rooms) + BOUNDS_MARGIN
        size = math.ceil(max(xs1 - xs0, zs1 - zs0) / 4.0) * 4.0  # square: the map window is
        self.ox = math.floor(((xs0 + xs1) - size) * 0.5)
        self.oz = math.floor(((zs0 + zs1) - size) * 0.5)
        self.size = size
        self.res = int(round(size / GRID))
        c = (np.arange(self.res, dtype=np.float64) + 0.5) * GRID
        self.X, self.Z = np.meshgrid(self.ox + c, self.oz + c)  # [iz, ix]
        self.room = np.full((self.res, self.res), -1, dtype=np.int32)
        self.door = np.full((self.res, self.res), -1, dtype=np.int32)
        self.floor = np.zeros((self.res, self.res), dtype=np.float64)
        self.water = np.zeros((self.res, self.res), dtype=bool)
        for k, r in enumerate(rooms):
            x0, z0, x1, z1 = r["rect"]
            sel = (self.X > x0) & (self.X < x1) & (self.Z > z0) & (self.Z < z1)
            clash = sel & (self.room >= 0)
            if clash.any():
                other = rooms[int(self.room[clash][0])]["id"]
                problems.append("%s overlaps %s" % (r["id"], other))
            self.room[sel] = k
            if r.get("slope"):
                s = r["slope"]
                coord = self.X if s["axis"] == "x" else self.Z
                t = np.clip((coord - s["span"][0]) / (s["span"][1] - s["span"][0]), 0.0, 1.0)
                self.floor[sel] = (s["y"][0] + (s["y"][1] - s["y"][0]) * t)[sel]
            else:
                self.floor[sel] = float(r["floor"])
            for ch in r.get("channels", []):
                cx0, cz0, cx1, cz1 = ch["rect"]
                csel = sel & (self.X > cx0) & (self.X < cx1) & (self.Z > cz0) & (self.Z < cz1)
                self.floor[csel] = float(r.get("floor", 0.0)) - float(ch["depth"])
                self.water[csel] = True
        for k, d in enumerate(doors):
            x0, z0, x1, z1 = d["rect"]
            sel = (self.X > x0) & (self.X < x1) & (self.Z > z0) & (self.Z < z1)
            if (sel & (self.room >= 0)).any():
                problems.append("%s: doorway cuts into a room" % d["id"])
            self.door[sel] = k
            self.floor[sel] = d["floor"]
        self.walk = (self.room >= 0) | (self.door >= 0)

    def cell(self, x: float, z: float) -> tuple[int, int]:
        ix = int(math.floor((x - self.ox) / GRID))
        iz = int(math.floor((z - self.oz) / GRID))
        return min(max(iz, 0), self.res - 1), min(max(ix, 0), self.res - 1)

    def clear_around(self, x: float, z: float, radius: float) -> bool:
        """True when every cell within `radius` of (x, z) is walkable."""
        d = np.hypot(self.X - x, self.Z - z)
        return bool(self.walk[d <= radius].all())


def dilate_max(values: np.ndarray, reach: int) -> np.ndarray:
    """Square max filter (separable) with half-width `reach` cells."""
    out = values.copy()
    for axis in (0, 1):
        src = out.copy()
        for s in range(1, reach + 1):
            out = np.maximum(out, np.roll(src, s, axis=axis))
            out = np.maximum(out, np.roll(src, -s, axis=axis))
    return out


def wall_tops(ras: Raster, rooms: list, doors: list, walk: np.ndarray) -> np.ndarray:
    """Top height of every wall cell (NaN where no wall): the highest
    floor + wall height of the walkable cells within WALL_REACH."""
    top = np.full(ras.room.shape, -1e9, dtype=np.float64)
    for k, r in enumerate(rooms):
        sel = (ras.room == k) & walk
        top[sel] = ras.floor[sel] + float(r["wall_h"])
    for k, d in enumerate(doors):
        sel = (ras.door == k) & walk
        top[sel] = ras.floor[sel] + d["wall_h"]
    grown = dilate_max(top, int(round(WALL_REACH / GRID)))
    walls = (grown > -1e8) & ~walk
    out = np.full(ras.room.shape, np.nan)
    out[walls] = np.ceil(grown[walls] * 2.0) / 2.0
    return out


def merge_walls(ras: Raster, tops: np.ndarray) -> list:
    """Greedy rectangles of equal-top wall cells: runs per row, merged down."""
    rects = []
    open_runs: dict = {}
    for iz in range(ras.res + 1):
        runs = {}
        if iz < ras.res:
            row = tops[iz]
            ix = 0
            while ix < ras.res:
                if np.isnan(row[ix]):
                    ix += 1
                    continue
                t = float(row[ix])
                j = ix
                while j + 1 < ras.res and not np.isnan(row[j + 1]) and float(row[j + 1]) == t:
                    j += 1
                runs[(ix, j, t)] = True
                ix = j + 1
        for key in list(open_runs):
            if key not in runs:
                i0, i1, t = key
                z0 = open_runs.pop(key)
                rects.append({"rect": [ras.ox + i0 * GRID, ras.oz + z0 * GRID,
                                       ras.ox + (i1 + 1) * GRID, ras.oz + iz * GRID], "top": t})
        for key in runs:
            if key not in open_runs:
                open_runs[key] = iz
    rects.sort(key=lambda w: (w["rect"][1], w["rect"][0]))
    return rects


# ---------------------------------------------------------------------------
# rules
# ---------------------------------------------------------------------------

def reachable(rooms: list, doors: list, start: str, kinds: set) -> dict:
    """Room id -> steps from `start` over doors of the given kinds."""
    links: dict = {r["id"]: [] for r in rooms}
    for d in doors:
        if d["kind"] in kinds:
            links[d["a"]].append(d["b"])
            links[d["b"]].append(d["a"])
    dist = {start: 0}
    queue = [start]
    while queue:
        here = queue.pop(0)
        for nxt in links[here]:
            if nxt not in dist:
                dist[nxt] = dist[here] + 1
                queue.append(nxt)
    return dist


def all_ids(lay: dict) -> list:
    out = [r["id"] for r in lay["rooms"]] + [d["id"] for d in lay["connectors"]]
    out += [p["id"] for p in lay["pois"]]
    return out


def highlands_ids() -> set:
    ids = {p["id"] for p in HIGHLANDS["pois"]}
    for p in HIGHLANDS["pois"]:
        for sub in p.get("portals", []):
            ids.add(sub["id"])
    return ids


def validate(lay: dict, rooms: list, doors: list, ras: Raster, others: set) -> list:
    problems = []
    prefix = lay["prefix"]
    seen = set()
    for i in all_ids(lay):
        if not i.startswith(prefix):
            problems.append("%s: id without the prefix %s" % (i, prefix))
        if i in seen:
            problems.append("%s: id used twice" % i)
        if i in others:
            problems.append("%s: id also used elsewhere (Highlands / another dungeon)" % i)
        seen.add(i)
    by_id = {r["id"]: r for r in rooms}
    for r in rooms:
        x0, z0, x1, z1 = r["rect"]
        if min(x1 - x0, z1 - z0) < MIN_ROOM - 1e-6:
            problems.append("%s: %.1f m wide (< %.0f)" % (r["id"], min(x1 - x0, z1 - z0), MIN_ROOM))
    for d in doors:
        if d["kind"] not in DOOR_KINDS:
            problems.append("%s: unknown door kind '%s'" % (d["id"], d["kind"]))
    # reachability: all gates open; secret rooms only through secret doors
    entry = lay["entry"]
    public = reachable(rooms, doors, entry, {"open", "gate", "shortcut"})
    full = reachable(rooms, doors, entry, DOOR_KINDS)
    for r in rooms:
        secret = "secret" in r.get("tags", [])
        if r["id"] not in full:
            problems.append("%s: unreachable" % r["id"])
        elif secret and r["id"] in public:
            problems.append("%s: a secret room reachable without a secret door" % r["id"])
        elif not secret and r["id"] not in public:
            problems.append("%s: only reachable through a secret door" % r["id"])
    long_way = reachable(rooms, doors, entry, {"open", "gate", "secret"})
    shortcuts = [d for d in doors if d["kind"] == "shortcut"]
    if lay.get("require_shortcut", True) and not shortcuts:
        problems.append("no shortcut back to the entry")
    for d in shortcuts:
        da, db = long_way.get(d["a"], 99), long_way.get(d["b"], 99)
        if min(da, db) > 2 or abs(da - db) < 3:
            problems.append("%s: not a shortcut (rooms %d and %d steps from the entry)" % (d["id"], da, db))
    # channels: inside their (flat) room, prefixed; nothing stands in them
    channels = {}
    for r in rooms:
        for ch in r.get("channels", []):
            channels[ch["id"]] = (ch, r)
            if not ch["id"].startswith(prefix):
                problems.append("%s: id without the prefix %s" % (ch["id"], prefix))
            if r.get("slope"):
                problems.append("%s: a channel in a sloped room" % ch["id"])
            cx0, cz0, cx1, cz1 = ch["rect"]
            x0, z0, x1, z1 = r["rect"]
            if cx0 < x0 or cz0 < z0 or cx1 > x1 or cz1 > z1:
                problems.append("%s: runs past its room %s" % (ch["id"], r["id"]))
    # rooms that fight
    for p in lay["pois"]:
        if p["type"] in COMBAT_TYPES:
            room = by_id.get(p.get("room", ""), None)
            if room is not None and "combat" not in room.get("tags", []):
                room.setdefault("tags", []).append("combat")
    for r in rooms:
        if "combat" in r.get("tags", []) or "arena" in r.get("tags", []):
            x0, z0, x1, z1 = r["rect"]
            if min(x1 - x0, z1 - z0) < MIN_COMBAT - 1e-6:
                problems.append("%s: combat room %.0f x %.0f m (< %.0f)" % (r["id"], x1 - x0, z1 - z0, MIN_COMBAT))
    # points of interest
    for p in lay["pois"]:
        if p["type"] not in KNOWN_TYPES:
            problems.append("%s: unknown POI type '%s'" % (p["id"], p["type"]))
        room = by_id.get(p.get("room", ""))
        if room is None:
            problems.append("%s: not inside a room" % p["id"])
            continue
        x, z = p["pos"]
        if p["type"] in FEATURE_TYPES and not ras.clear_around(x, z, FEATURE_CLEAR):
            problems.append("%s: closer than %.1f m to a wall" % (p["id"], FEATURE_CLEAR))
        spots = [p["pos"]] + [s[:2] for s in p.get("spots", [])] + [m[:2] for m in p.get("mirrors", [])]
        spots += [t[:2] for t in p.get("targets", []) if isinstance(t, list)]
        if p.get("receiver"):
            spots.append(p["receiver"])
        if p["type"] not in IN_CHANNEL_TYPES and any(ras.water[ras.cell(s[0], s[1])] for s in spots):
            problems.append("%s: stands in a channel" % p["id"])
        if p["type"] == "element":
            for t in p.get("targets", []):
                if not ras.clear_around(t[0], t[1], FEATURE_CLEAR):
                    problems.append("%s: a target closer than %.1f m to a wall" % (p["id"], FEATURE_CLEAR))
        if p["type"] in ("ice", "collapse"):
            ch = channels.get(p.get("channel", ""))
            if ch is None:
                problems.append("%s: unknown channel" % p["id"])
            elif p["type"] == "ice":
                cx0, cz0, cx1, cz1 = ch[0]["rect"]
                s = p.get("strip", [0, 0, 0, 0])
                if not inside(ch[0]["rect"], x, z) or s[0] < cx0 or s[1] < cz0 or s[2] > cx1 or s[3] > cz1:
                    problems.append("%s: its socket or strip lies outside its channel" % p["id"])
        if p["type"] == "trap":
            for q in p.get("lane", []):
                if not inside(room["rect"], q[0], q[1]):
                    problems.append("%s: its lane runs past its room" % p["id"])
        for m in p.get("mirrors", []) + ([p["receiver"]] if p.get("receiver") else []):
            if not ras.clear_around(m[0], m[1], FEATURE_CLEAR):
                problems.append("%s: a mirror / receiver closer than %.1f m to a wall" % (p["id"], FEATURE_CLEAR))
        if p["type"] == "water":
            ch = channels.get(p.get("channel", ""))
            if ch is None:
                problems.append("%s: unknown channel" % p["id"])
            else:
                cx0, cz0, cx1, cz1 = ch[0]["rect"]
                for w in p.get("walkways", []):
                    if w[0] < cx0 or w[1] < cz0 or w[2] > cx1 or w[3] > cz1:
                        problems.append("%s: a walkway outside its channel" % p["id"])
        if p["type"] == "block":
            gx0, gz0, gx1, gz1 = p["grid"]
            if not inside(room["rect"], gx0, gz0) or not inside(room["rect"], gx1, gz1):
                problems.append("%s: its grid runs past the room" % p["id"])
            if not inside(p["grid"], x, z):
                problems.append("%s: its home lies outside its grid" % p["id"])
        if p["type"] == "camp":
            x0, z0, x1, z1 = room["rect"]
            edge = min(x - x0, x1 - x, z - z0, z1 - z)
            if float(p.get("radius", 10.0)) > edge + 1.0:
                problems.append("%s: trigger %.0f m reaches past its room (edge %.1f m)" % (p["id"], p["radius"], edge))
            for s in p.get("spots", []):
                if not inside(room["rect"], s[0], s[1]) or not ras.clear_around(s[0], s[1], SPOT_CLEAR):
                    problems.append("%s: spot %s not clear inside %s" % (p["id"], s, room["id"]))
            if len(p.get("spots", [])) < len(p.get("composition", [])):
                problems.append("%s: fewer spots than enemies" % p["id"])
    return problems


# ---------------------------------------------------------------------------
# outputs
# ---------------------------------------------------------------------------

def write_map(lay: dict, ras: Raster, public_walk: np.ndarray, out_dir: str) -> None:
    """Map image over the square bounds: floors shaded by height, walls,
    secret rooms and their doors left out (drawn as plain background)."""
    with open(os.path.join(ROOT, "assets", "art_spec.json"), encoding="utf-8") as fh:
        pal = json.load(fh)["palettes"][lay.get("map_palette", "spire")]
    floor_ramp = np.array([hex_rgb(c) for c in pal["floor"]])
    wall_ramp = np.array([hex_rgb(c) for c in pal["wall"]])
    bg = hex_rgb(pal["background"])
    res = int(round(ras.size * MAP_PX_PER_M))
    c = (np.arange(res, dtype=np.float64) + 0.5) / MAP_PX_PER_M
    X, Z = np.meshgrid(ras.ox + c, ras.oz + c)
    ix = np.clip(np.floor((X - ras.ox) / GRID).astype(int), 0, ras.res - 1)
    iz = np.clip(np.floor((Z - ras.oz) / GRID).astype(int), 0, ras.res - 1)
    walk = public_walk[iz, ix]
    grown = dilate_max(public_walk.astype(np.float64), int(round(WALL_REACH / GRID))) > 0.5
    wall = grown[iz, ix] & ~walk
    h = ras.floor[iz, ix]
    hmin, hmax = float(ras.floor[public_walk].min()), float(ras.floor[public_walk].max())
    t = np.clip((h - hmin) / max(hmax - hmin, 1.0), 0.0, 1.0)
    bayer = np.tile(BAYER4, (res // 4 + 1, res // 4 + 1))[:res, :res]
    idx = np.clip(np.floor(1.0 + t * 2.0 + 0.5 + bayer * 0.9).astype(int), 0, len(floor_ramp) - 1)
    rgb = np.tile(bg, (res, res, 1))
    rgb[walk] = floor_ramp[idx[walk]]
    wet = walk & ras.water[iz, ix]
    water = hex_rgb(pal.get("water", WATER_COLOR))
    rgb[wet] = water[None, :] * (0.92 + 0.16 * (bayer[wet] + 0.5))[:, None]
    # walls: the face next to a floor lighter than the mass behind it
    near = dilate_max(public_walk.astype(np.float64), 1)[iz, ix] > 0.5
    rgb[wall] = wall_ramp[1]
    rgb[wall & near] = wall_ramp[3]
    # a darker rim on the floor along the walls (reads as depth)
    edge = walk & (dilate_max((~public_walk).astype(np.float64), 1)[iz, ix] > 0.5)
    rgb[edge] = rgb[edge] * 0.78
    out = np.zeros((res, res, 4), dtype=np.uint8)
    out[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    out[..., 3] = 255
    Image.fromarray(out, mode="RGBA").save(os.path.join(out_dir, "map.png"))


def bake(key: str, others: set) -> int:
    lay = importlib.import_module(DUNGEONS[key]).LAYOUT
    problems: list = []
    rooms = json.loads(json.dumps(lay["rooms"]))
    by_id = {r["id"]: r for r in rooms}
    for r in rooms:
        r.setdefault("wall_h", lay.get("wall_h", 7.0))
        r.setdefault("tags", [])
    doors = []
    for c in lay["connectors"]:
        d = json.loads(json.dumps(c))
        d.setdefault("kind", "open")
        d.setdefault("inputs", [])
        d.setdefault("width", MIN_DOOR)
        a, b = by_id.get(d["a"]), by_id.get(d["b"])
        if a is None or b is None:
            problems.append("%s: unknown room" % d["id"])
            continue
        d["rect"], d["axis"] = door_rect(d, a, b, problems)
        d["floor"] = door_floor(d, a, b, d["axis"], d["rect"], problems)
        d["wall_h"] = min(a["wall_h"], b["wall_h"])
        doors.append(d)
    pois = json.loads(json.dumps(lay["pois"]))
    for p in pois:
        x, z = p["pos"]
        room = next((r for r in rooms if inside(r["rect"], x, z)), None)
        p["room"] = room["id"] if room else ""
        p["y"] = round(floor_at(room, x, z), 3) if room else 0.0
        for k, s in enumerate(p.get("spots", [])):
            p.setdefault("spots_y", []).append(round(floor_at(room, s[0], s[1]), 3) if room else 0.0)
    lay_checked = dict(lay)
    lay_checked["pois"] = pois
    ras = Raster(lay, rooms, doors, problems)
    problems += validate(lay_checked, rooms, doors, ras, others)
    tops = wall_tops(ras, rooms, doors, ras.walk)
    walls = merge_walls(ras, tops)
    base_y = round(min(float(ras.floor[ras.walk].min()), 0.0) - 1.0, 3)
    secret_rooms = {k for k, r in enumerate(rooms) if "secret" in r["tags"]}
    secret_ids = {rooms[k]["id"] for k in secret_rooms}
    secret_doors = {k for k, d in enumerate(doors) if d["kind"] == "secret" or d["a"] in secret_ids or d["b"] in secret_ids}
    public_walk = ras.walk.copy()
    for k in secret_rooms:
        public_walk &= ras.room != k
    for k in secret_doors:
        public_walk &= ras.door != k
    out_dir = os.path.join(ROOT, "assets", "world", lay["id"])
    os.makedirs(out_dir, exist_ok=True)
    write_map(lay, ras, public_walk, out_dir)
    out = {
        "id": lay["id"],
        "prefix": lay["prefix"],
        "entry": lay["entry"],
        "size_m": ras.size,
        "origin": [ras.ox, ras.oz],
        "base_y": base_y,
        "rooms": rooms,
        "doors": doors,
        "walls": walls,
        "channels": [dict(ch, room=r["id"], floor=float(r.get("floor", 0.0))) for r in rooms for ch in r.get("channels", [])],
        "pois": pois,
        "areas": [],
        "baked": {"map_px_per_m": MAP_PX_PER_M, "grid_m": GRID, "wall_reach_m": WALL_REACH},
    }
    for r in rooms:
        if r.get("name_key"):
            x0, z0, x1, z1 = r["rect"]
            cx, cz = (x0 + x1) * 0.5, (z0 + z1) * 0.5
            out["areas"].append({"id": r["id"], "name_key": r["name_key"], "pos": [cx, cz],
                                 "y": round(floor_at(r, cx, cz), 3), "rect": r["rect"]})
    with open(os.path.join(out_dir, "layout.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=1)
        fh.write("\n")
    print("%s: %d rooms, %d doors, %d wall boxes, %d POIs, %.0f m square" % (
        lay["id"], len(rooms), len(doors), len(walls), len(pois), ras.size))
    for p in problems:
        print("  LAYOUT PROBLEM: " + p)
    return 1 if problems else 0


def main() -> int:
    keys = sys.argv[1:] or list(DUNGEONS)
    status = 0
    for key in keys:
        if key not in DUNGEONS:
            print("unknown dungeon '%s' (known: %s)" % (key, ", ".join(DUNGEONS)))
            return 1
        others = highlands_ids()
        for other in DUNGEONS:
            if other != key:
                others.update(all_ids(importlib.import_module(DUNGEONS[other]).LAYOUT))
        status |= bake(key, others)
    return status


if __name__ == "__main__":
    sys.exit(main())
