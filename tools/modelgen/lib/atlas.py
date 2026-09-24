"""Per-character pixel atlas bake (M06, Blender headless).

unwrap(): Smart-UV + pack, then scale every island so the atlas hits the
target texel density exactly (px per metre is what keeps characters and the
world one language).
bake(): rasterizes the atlas in Python from each face's paint (palette ramp +
base step + pattern, see rig.PartMesh.paint):
  * baked light: ramp step from the face normal vs a fixed top-front-left key,
    ordered-dithered so curved lofts band like pixel art;
  * raycast AO (BVHTree): crevices and part overlaps drop one step;
  * 1-px highlight along convex sharp polygon edges that face up;
  * optional pattern (cloth weave, hide speckle, plate seams);
  * 2-px colour bleed into the gaps so mipmaps never pull in black.
Pixels are written as sRGB bytes straight from the art_spec hex values.
"""
import json
import math

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

from . import rig

BAYER = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))
# Baked light is sky light from straight above only: it must never contradict
# a zone's real-time sun direction (the toon lighting adds that on top).
KEY = Vector((0.0, 0.0, 1.0))
SHARP_DEG = 28.0


def _select_only(obj):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def _uv_area(me):
    uv = me.uv_layers.active.data
    total = 0.0
    for poly in me.polygons:
        pts = [uv[i].uv for i in poly.loop_indices]
        s = 0.0
        for k in range(len(pts)):
            a, b = pts[k], pts[(k + 1) % len(pts)]
            s += a.x * b.y - b.x * a.y
        total += abs(s) * 0.5
    return total


def unwrap(obj, target_px_per_m, sizes=(64, 128, 256, 512), axis_aligned=False):
    """Returns the atlas size in px (square) that holds `target_px_per_m`.
    axis_aligned: pack islands only in 90-degree turns, so straight edges of
    built props (planks, masonry, frames) run along the texel grid instead of
    as jagged diagonals."""
    _select_only(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60.0), island_margin=0.0,
                             area_weight=0.0, correct_aspect=True, scale_to_bounds=False)
    bpy.ops.uv.average_islands_scale()
    if axis_aligned:
        bpy.ops.uv.pack_islands(rotate=True, rotate_method="CARDINAL", margin=0.02)
    else:
        bpy.ops.uv.pack_islands(rotate=True, margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")
    me = obj.data
    area3d = sum(p.area for p in me.polygons)
    area_uv = _uv_area(me)
    chosen = sizes[-1]
    density = chosen * math.sqrt(area_uv / area3d)
    for size in sizes:
        d = size * math.sqrt(area_uv / area3d)
        if d >= target_px_per_m:
            chosen, density = size, d
            break
    scale = target_px_per_m / density
    for loop in me.uv_layers.active.data:
        loop.uv = loop.uv * scale
    return chosen


def _sharp_edges(me):
    """Set of vertex-index pairs for convex sharp edges whose faces look up-ish."""
    bm = bmesh.new()
    bm.from_mesh(me)
    sharp = set()
    for e in bm.edges:
        if len(e.link_faces) != 2:
            continue
        f0, f1 = e.link_faces
        ang = math.degrees(f0.normal.angle(f1.normal, 0.0))
        if ang < SHARP_DEG:
            continue
        # convex: each face's centre lies behind the other face's plane
        c1 = f1.calc_center_median()
        if (c1 - e.verts[0].co).dot(f0.normal) > 0.001:
            continue
        if (f0.normal + f1.normal).z < 0.15:
            continue
        sharp.add(tuple(sorted((e.verts[0].index, e.verts[1].index))))
    bm.free()
    return sharp


def _seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    ll = dx * dx + dy * dy
    t = 0.0 if ll < 1e-12 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / ll))
    qx, qy = ax + dx * t, ay + dy * t
    return math.hypot(px - qx, py - qy)


def bake(obj, size, path, skip_material_indices=(1,)):
    """Rasterize the atlas at `size` px square; faces on skipped material slots
    (emissive glow) keep a flat material and are not painted."""
    me = obj.data
    paints = json.loads(obj["paints"])
    ramps = [[rig.hex_to_srgb(h) for h in p["ramp"]] for p in paints]
    paint_of = [a.value for a in me.attributes["paint"].data]
    uv = me.uv_layers.active.data
    me.calc_loop_triangles()
    bm = bmesh.new()
    bm.from_mesh(me)
    bvh = BVHTree.FromBMesh(bm)
    bm.free()
    sharp = _sharp_edges(me)
    verts = me.vertices
    loops = me.loops

    color = [[None] * size for _ in range(size)]
    dirs = [Vector(d).normalized() for d in ((0.3, 0.3, 1), (-0.3, 0.3, 1), (0.3, -0.3, 1), (-0.3, -0.3, 1))]

    for tri in me.loop_triangles:
        poly = me.polygons[tri.polygon_index]
        if poly.material_index in skip_material_indices:
            continue
        paint = paints[paint_of[tri.polygon_index]]
        ramp = ramps[paint_of[tri.polygon_index]]
        n = poly.normal
        uvs = [uv[li].uv * size for li in tri.loops]
        cos = [verts[loops[li].vertex_index].co for li in tri.loops]
        vidx = [loops[li].vertex_index for li in tri.loops]
        # polygon-boundary edges of this triangle that are sharp + convex
        poly_edges = {tuple(sorted(k)) for k in poly.edge_keys}
        hi_edges = []
        for a, b in ((0, 1), (1, 2), (2, 0)):
            key = tuple(sorted((vidx[a], vidx[b])))
            if key in poly_edges and key in sharp:
                hi_edges.append((uvs[a], uvs[b]))
        # AO basis: rotate the up-hemisphere probe directions around the normal
        tangent = n.orthogonal().normalized()
        bitangent = n.cross(tangent)
        probes = [(tangent * d.x + bitangent * d.y + n * d.z).normalized() for d in dirs]
        light = n.dot(KEY)

        x0 = max(int(math.floor(min(p.x for p in uvs))), 0)
        x1 = min(int(math.ceil(max(p.x for p in uvs))), size - 1)
        y0 = max(int(math.floor(min(p.y for p in uvs))), 0)
        y1 = min(int(math.ceil(max(p.y for p in uvs))), size - 1)
        (ax, ay), (bx, by), (cx, cy) = (uvs[0].x, uvs[0].y), (uvs[1].x, uvs[1].y), (uvs[2].x, uvs[2].y)
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-9:
            continue
        for py in range(y0, y1 + 1):
            for px in range(x0, x1 + 1):
                fx, fy = px + 0.5, py + 0.5
                w0 = ((by - cy) * (fx - cx) + (cx - bx) * (fy - cy)) / den
                w1 = ((cy - ay) * (fx - cx) + (ax - cx) * (fy - cy)) / den
                w2 = 1.0 - w0 - w1
                if w0 < -0.02 or w1 < -0.02 or w2 < -0.02:
                    continue
                pos = cos[0] * w0 + cos[1] * w1 + cos[2] * w2
                # Facets have one normal each: a solid step per facet. (Dithering
                # a constant light term turned whole plates into checkerboards.)
                shade = paint["base"] + int(round(light * 1.2 - 0.15))
                occluded = 0
                for d in probes:
                    hit = bvh.ray_cast(pos + n * 0.004, d, 0.18)
                    if hit[0] is not None:
                        occluded += 1
                if occluded >= 2:
                    shade -= 1
                for (ea, eb) in hi_edges:
                    if _seg_dist(fx, fy, ea.x, ea.y, eb.x, eb.y) <= 1.0:
                        shade += 1
                        break
                pattern = paint.get("pattern", "plain")
                # object-space patterns (built props): independent of how the
                # UV island was turned. u = horizontal coordinate on the face.
                u = pos.x if abs(n.y) >= abs(n.x) else pos.y
                if abs(n.z) > 0.7:
                    u = pos.x
                if pattern == "planks" and (u % 0.19) < 1.0 / 32.0:
                    shade -= 1
                elif pattern == "masonry":
                    course = math.floor(pos.z / 0.3)
                    if (pos.z % 0.3) < 1.0 / 32.0 or ((u + course * 0.23) % 0.46) < 1.0 / 32.0:
                        shade -= 1
                elif pattern == "bark" and (int(math.floor(u * 32.0)) * 7 + int(math.floor(pos.z * 8.0)) * 3) % 5 == 0:
                    shade -= 1
                if pattern == "cloth" and (py % 4 == 0):
                    shade -= 1
                elif pattern == "hide" and ((px * 7 + py * 13) % 11 == 0):
                    shade -= 1
                elif pattern == "plate" and (py % 16 == 0):
                    shade -= 1
                shade = max(0, min(len(ramp) - 1, shade))
                color[py][px] = ramp[shade]

    # 2-px bleed so mip levels never average in empty (black) texels
    for _ in range(2):
        grown = [row[:] for row in color]
        for y in range(size):
            for x in range(size):
                if color[y][x] is not None:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < size and 0 <= ny < size and color[ny][nx] is not None:
                        grown[y][x] = color[ny][nx]
                        break
        color = grown

    img = bpy.data.images.new(obj.name + "_atlas_%d" % size, size, size, alpha=False)
    pixels = []
    fill = ramps[0][0]
    for y in range(size):
        for x in range(size):
            c = color[y][x] or fill
            pixels.extend((c[0], c[1], c[2], 1.0))
    img.pixels = pixels
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    print("atlas:", path, size)
