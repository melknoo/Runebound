"""Rig v3: AI base mesh import, cleanup, normalisation, decimation (Blender
headless, used by tools/modelgen/ai_fit.py).

The source is a compacted AI generation (tools/modelgen/ai_src/<id>/raw.glb,
written by ai_ingest.py): one textured mesh in an A-pose. Everything here is
deterministic for a given file and Blender version.
"""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

SRC_UV = "src"


def tris(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def _select_only(objs):
    for o in bpy.context.view_layer.objects:
        if o is not None:
            o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def base_image(obj):
    """The base-colour image of the AI material(s) (ai_ingest keeps only that)."""
    for slot in obj.material_slots:
        mat = slot.material
        if mat is None or mat.node_tree is None:
            continue
        for node in mat.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image is not None:
                return node.image
    raise ValueError("%s: no base colour image" % obj.name)


def load(path, name):
    """Import the GLB, join its meshes into one object with world transforms
    applied, rename its UV map to `src` (the AI texture's own unwrap)."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = sorted((o for o in new if o.type == "MESH"), key=lambda o: o.name)
    if not meshes:
        raise ValueError("%s: no mesh" % path)
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in new:
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    _select_only(meshes)
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.name = name
    obj.data.name = name
    uv = obj.data.uv_layers
    if len(uv) == 0:
        raise ValueError("%s: no UV map" % path)
    while len(uv) > 1:
        uv.remove(uv[-1])
    uv[0].name = SRC_UV
    img = base_image(obj)
    img.use_fake_user = True  # survives the material swap in fit.join_body
    obj["src_image"] = img.name
    return obj


def _islands(bm):
    """Face islands (edge-connected), in face-index order: deterministic."""
    seen = set()
    out = []
    for f0 in bm.faces:
        if f0.index in seen:
            continue
        isl = []
        stack = [f0]
        seen.add(f0.index)
        while stack:
            f = stack.pop()
            isl.append(f)
            for e in f.edges:
                for g in e.link_faces:
                    if g.index not in seen:
                        seen.add(g.index)
                        stack.append(g)
        out.append(isl)
    return out


def clean(obj, merge=1e-5, min_area_frac=0.003):
    """Weld coincident verts, drop degenerate faces and small loose shells
    (specks, floating bits) and loose verts. Returns the dropped shell count."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=merge)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-7)
    bm.faces.ensure_lookup_table()
    bm.faces.index_update()
    islands = _islands(bm)
    total = sum(f.calc_area() for f in bm.faces) or 1.0
    drop = [isl for isl in islands if sum(f.calc_area() for f in isl) / total < min_area_frac]
    if drop:
        bmesh.ops.delete(bm, geom=[f for isl in drop for f in isl], context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return len(drop)


def bounds(obj):
    co = [v.co for v in obj.data.vertices]
    lo = Vector([min(c[i] for c in co) for i in range(3)])
    hi = Vector([max(c[i] for c in co) for i in range(3)])
    return lo, hi


def normalize(obj, yaw_deg, height):
    """Turn the front to -Y (yaw about Z), scale uniformly to `height`, soles
    on z = 0, centred in x, feet centred in y."""
    me = obj.data
    me.transform(Matrix.Rotation(math.radians(yaw_deg), 4, "Z"))
    lo, hi = bounds(obj)
    s = height / (hi.z - lo.z)
    me.transform(Matrix.Diagonal((s, s, s, 1.0)))
    lo, hi = bounds(obj)
    feet = [v.co for v in me.vertices if v.co.z < lo.z + 0.06 * (hi.z - lo.z)]
    fy = (min(c.y for c in feet) + max(c.y for c in feet)) * 0.5
    me.transform(Matrix.Translation((-(lo.x + hi.x) * 0.5, -fy, -lo.z)))
    me.update()
    return s


def decimate(obj, target_tris):
    """Collapse-decimate to `target_tris` (UVs kept by the modifier)."""
    before = tris(obj)
    if before <= target_tris:
        return before, before
    mod = obj.modifiers.new("rigv3_decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = target_tris / float(before)
    mod.use_collapse_triangulate = True
    _select_only([obj])
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return before, tris(obj)


def smooth(obj, angle_deg=40.0):
    """Smooth normals with sharp edges above `angle_deg` (written as the mesh's
    sharp_edge attribute, so the glTF export keeps them without a modifier)."""
    _select_only([obj])
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle_deg), keep_sharp_edges=True)
