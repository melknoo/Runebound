"""Rig v3: fit an AI body onto an EXISTING template skeleton (Blender headless,
used by tools/modelgen/ai_fit.py).

The final armature is the legacy one, bone for bone (generate_characters_v2's
templates, roll 0, arms hanging): the mesh is warped onto it, never the other
way round, so every *_clips(arm) function, lib.pose intent, smoke-pinned clip
length and the Godot side keep working unchanged.

  detect()      proposes landmarks (template joints placed on the mesh's own
                A-pose) for <src>/fit.json; the build reads only that JSON
  fit_armature  template names/parents at the landmarks (inherit_scale NONE)
  auto_weights  bone heat, voxel-proxy fallback, top 4 influences, normalized
  warp()        poses every fit bone onto its template joint (minimal swing +
                length scale), applies it to the mesh, drops the fit rig
  snapper()     seats script-kit glow decals on the AI surface
  join_body()   AI faces (paint -1, slot 0) + script kit -> one mesh, slots in order
  verify()      the Godot contract as numbers (ai_fit_report.json)
"""
import json
import math

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

from . import rig

NO_DEFORM = ("root",)


def _select_only(objs, active=None):
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for o in bpy.context.view_layer.objects:
        if o is not None:
            o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or objs[0]


def _r(v):
    return [round(float(c), 4) for c in v]


# ---------------------------------------------------------------------------
# Landmarks
# ---------------------------------------------------------------------------

def detect(obj, bones):
    """Template joints placed on the mesh: torso/head from the template,
    arms aimed at the fists found on the mesh (A-pose), legs over the feet.
    A proposal for fit.json; review the landmark sheet and edit numbers."""
    tmpl = {n: (Vector(h), Vector(t)) for n, _p, h, t in bones}
    lm = {n: [_r(h), _r(t)] for n, (h, t) in tmpl.items()}
    co = [v.co.copy() for v in obj.data.vertices]
    height = max(c.z for c in co)
    if "upper_arm.L" in tmpl:
        for side, sx in (("L", 1.0), ("R", -1.0)):
            shoulder = tmpl["upper_arm." + side][0]
            region = [c for c in co if c.x * sx > abs(shoulder.x) * 1.05 and 0.3 * height < c.z < shoulder.z - 0.12
                      and abs(c.y - shoulder.y) < 0.3]  # A-pose arms stay in the body plane
            if not region:
                continue
            tip = max(region, key=lambda c: ((c - shoulder).length, -c.z))
            reach = (tip - shoulder).length
            arm_len = (tmpl["hand." + side][0] - shoulder).length

            def shell(r, band=0.035):
                """Centre of the arm where a sphere of radius r around the
                shoulder cuts it: follows a bent elbow, unlike a straight line."""
                pts = [c for c in region if abs((c - shoulder).length - r) < band]
                if not pts:
                    return shoulder + (tip - shoulder) * (r / reach)
                return sum(pts, Vector()) / len(pts)
            wrist = shell(min(reach - 0.1, arm_len * 1.15))
            # a bent arm's elbow is not half way along the chord: pick the
            # radius where upper : fore matches the template's ratio
            t_up = (tmpl["upper_arm." + side][1] - tmpl["upper_arm." + side][0]).length
            t_fo = (tmpl["forearm." + side][1] - tmpl["forearm." + side][0]).length
            chord = (wrist - shoulder).length
            best = None
            for k in range(40, 96):
                r = chord * k / 100.0
                e = shell(r)
                err = abs(r / max((wrist - e).length, 1e-4) - t_up / t_fo)
                if best is None or err < best[0]:
                    best = (err, e)
            elbow = best[1]
            d = (tip - wrist).normalized()
            lm["upper_arm." + side] = [_r(shoulder), _r(elbow)]
            lm["forearm." + side] = [_r(elbow), _r(wrist)]
            lm["hand." + side] = [_r(wrist), _r(wrist + d * 0.1)]
    if "thigh.L" in tmpl:
        low = [c for c in co if c.z < 0.08 * height]
        for side, sx in (("L", 1.0), ("R", -1.0)):
            foot = [c for c in low if c.x * sx > 0.0]
            if not foot:
                continue
            fx = sum(c.x for c in foot) / len(foot)
            for b in ("thigh.", "shin.", "foot."):
                h, t = tmpl[b + side]
                lm[b + side] = [_r((fx, h.y, h.z)), _r((fx, t.y, t.z))]
    return lm


def fit_armature(name, bones, landmarks):
    arm = rig.build_armature(name + "_fit", [(n, p, landmarks[n][0], landmarks[n][1]) for n, p, _h, _t in bones])
    for b in arm.data.bones:
        b.inherit_scale = "NONE"
        b.use_deform = b.name not in NO_DEFORM
    return arm


# ---------------------------------------------------------------------------
# Weights
# ---------------------------------------------------------------------------

def _weightless(obj):
    return [v.index for v in obj.data.vertices if sum(g.weight for g in v.groups) <= 1e-6]


def _heat(obj, arm):
    for vg in list(obj.vertex_groups):
        obj.vertex_groups.remove(vg)
    for m in [m for m in obj.modifiers if m.type == "ARMATURE"]:
        obj.modifiers.remove(m)
    _select_only([obj, arm], active=arm)
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")


def _segment_dist(p, a, b):
    ab = b - a
    t = 0.0 if ab.length_squared < 1e-12 else max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * t)).length


def _nearest_bone(obj, arm, idx):
    segs = [(b.name, b.head_local, b.tail_local) for b in arm.data.bones if b.use_deform]
    for i in idx:
        p = obj.data.vertices[i].co
        name = min(segs, key=lambda s: _segment_dist(p, s[1], s[2]))[0]
        vg = obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
        vg.add([i], 1.0, "REPLACE")


def auto_weights(obj, arm, voxel=0.012):
    """Bone heat on the mesh; if verts stay weightless (loose shells,
    intersections), heat on a voxel-remeshed proxy and transfer; leftovers
    go to their nearest bone. Then top-4 influences, normalized."""
    _heat(obj, arm)
    method = "heat"
    if len(_weightless(obj)) > 0.002 * len(obj.data.vertices):
        method = "proxy"
        proxy = obj.copy()
        proxy.data = obj.data.copy()
        bpy.context.scene.collection.objects.link(proxy)
        for vg in list(proxy.vertex_groups):
            proxy.vertex_groups.remove(vg)
        for m in list(proxy.modifiers):
            proxy.modifiers.remove(m)
        rem = proxy.modifiers.new("vox", "REMESH")
        rem.mode = "VOXEL"
        rem.voxel_size = voxel
        _select_only([proxy])
        bpy.ops.object.modifier_apply(modifier=rem.name)
        _heat(proxy, arm)
        for vg in list(obj.vertex_groups):
            obj.vertex_groups.remove(vg)
        for vg in proxy.vertex_groups:
            obj.vertex_groups.new(name=vg.name)
        dt = obj.modifiers.new("wt", "DATA_TRANSFER")
        dt.object = proxy
        dt.use_vert_data = True
        dt.data_types_verts = {"VGROUP_WEIGHTS"}
        dt.vert_mapping = "POLYINTERP_NEAREST"
        dt.layers_vgroup_select_src = "ALL"
        dt.layers_vgroup_select_dst = "NAME"
        _select_only([obj])
        bpy.ops.object.modifier_move_to_index(modifier=dt.name, index=0)
        bpy.ops.object.modifier_apply(modifier=dt.name)
        bpy.data.objects.remove(proxy)
        bpy.context.view_layer.update()
    left = _weightless(obj)
    if left:
        _nearest_bone(obj, arm, left)
    _limit_normalize(obj, 4)
    return method, len(left)


def _limit_normalize(obj, limit):
    names = {vg.index: vg.name for vg in obj.vertex_groups}
    groups = {vg.name: vg for vg in obj.vertex_groups}
    for v in obj.data.vertices:
        ws = sorted(((g.weight, names[g.group]) for g in v.groups if g.weight > 1e-4), reverse=True)
        keep = ws[:limit]
        total = sum(w for w, _n in keep) or 1.0
        for g in list(v.groups):
            groups[names[g.group]].remove([v.index])
        for w, n in keep:
            groups[n].add([v.index], w / total, "REPLACE")


# ---------------------------------------------------------------------------
# Warp onto the template rest
# ---------------------------------------------------------------------------

def warp(obj, fit_arm, bones):
    """Pose each fit bone so its head sits on the template head and its axis
    on the template axis (minimal swing, no twist), scaled along the bone to
    the template length; bake that into the mesh (preserve volume) and drop
    the fit rig. Returns {bone: length ratio template/fit}."""
    tmpl = {n: (Vector(h), Vector(t)) for n, _p, h, t in bones}
    _select_only([fit_arm])
    bpy.ops.object.mode_set(mode="POSE")
    ratios = {}
    for name, _parent, _h, _t in bones:  # templates list parents first
        b = fit_arm.data.bones[name]
        pb = fit_arm.pose.bones[name]
        fd = b.tail_local - b.head_local
        th, tt = tmpl[name]
        td = tt - th
        s = td.length / fd.length if fd.length > 1e-6 else 1.0
        ratios[name] = round(s, 3)
        swing = fd.normalized().rotation_difference(td.normalized()).to_matrix().to_4x4()
        rest_rot = b.matrix_local.to_3x3().to_4x4()
        pb.matrix = Matrix.Translation(th) @ swing @ rest_rot @ Matrix.Diagonal((1.0, s, 1.0, 1.0))
        bpy.context.view_layer.update()
    bpy.ops.object.mode_set(mode="OBJECT")
    mod = next(m for m in obj.modifiers if m.type == "ARMATURE")
    mod.use_deform_preserve_volume = True
    _select_only([obj])
    bpy.ops.object.modifier_apply(modifier=mod.name)
    mw = obj.matrix_world.copy()
    obj.parent = None
    obj.matrix_world = mw
    bpy.data.objects.remove(fit_arm)
    bpy.context.view_layer.update()  # else view_layer.objects still lists the removed base (None)
    return ratios


# ---------------------------------------------------------------------------
# AI weapon of a look
# ---------------------------------------------------------------------------

def place_weapon(obj, grip, length, grip_frac=0.08, bone="hand.R"):
    """An AI weapon generated upright (pommel down, tip up), its flat facing
    the camera: centred on its long axis, scaled to `length`, its grip point
    (`grip_frac` of the length above the pommel) moved to `grip` and turned
    to point along -Y (the rig's rest: the weapon forward from the fist, as
    lib.pose's "_blade" intent expects), rigidly weighted to `bone`."""
    from . import aimesh
    me = obj.data
    lo, hi = aimesh.bounds(obj)
    s = length / max(hi.z - lo.z, 1e-6)
    me.transform(Matrix.Translation((-(lo.x + hi.x) * 0.5, -(lo.y + hi.y) * 0.5, -lo.z)))
    me.transform(Matrix.Diagonal((s, s, s, 1.0)))
    me.transform(Matrix.Translation((0.0, 0.0, -grip_frac * length)))
    me.transform(Matrix.Rotation(math.radians(90.0), 4, "X"))  # +Z (the tip) -> -Y
    me.transform(Matrix.Translation(Vector(grip)))
    me.update()
    for vg in list(obj.vertex_groups):
        obj.vertex_groups.remove(vg)
    vg = obj.vertex_groups.new(name=bone)
    vg.add(list(range(len(me.vertices))), 1.0, "REPLACE")


def join_weapon(body, weapon):
    """Joins the placed AI weapon into the AI body before the kit: face
    attribute "src" 1 (lib.texbake bakes it from its own image, split_regions
    makes it the weapon region), body["src_images"] = [body image, weapon image]."""
    images = [body["src_image"], weapon["src_image"]]
    for obj, sid in ((body, 0), (weapon, 1)):
        me = obj.data
        attr = me.attributes.get("src_id") or me.attributes.new("src_id", "INT", "FACE")
        attr.data.foreach_set("value", [sid] * len(me.polygons))
    _select_only([body, weapon], active=body)
    bpy.ops.object.join()
    body["src_images"] = images
    return body


# ---------------------------------------------------------------------------
# Script kit on the AI body
# ---------------------------------------------------------------------------

def snapper(obj, proud=0.004):
    """snap(verts): move a kit decal along +-Y so its front face sits `proud`
    metres in front of the body surface (most forward hit of a few rays)."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bvh = BVHTree.FromBMesh(bm)
    bm.free()

    def snap(verts):
        xs = [v.co.x for v in verts]
        zs = [v.co.z for v in verts]
        xm, zm = (min(xs) + max(xs)) * 0.5, (min(zs) + max(zs)) * 0.5
        hits = []
        for x, z in ((xm, zm), (min(xs), zm), (max(xs), zm), (xm, min(zs)), (xm, max(zs))):
            loc, _n, _i, _d = bvh.ray_cast(Vector((x, -3.0, z)), Vector((0.0, 1.0, 0.0)), 6.0)
            if loc is not None:
                hits.append(loc.y)
        if not hits:
            print("fit: snap found no surface at x=%.2f z=%.2f" % (xm, zm))
            return
        dy = (min(hits) - proud) - min(v.co.y for v in verts)
        for v in verts:
            v.co.y += dy
    return snap


def join_body(obj, kit, mats, name, arm):
    """AI faces -> slot 0 with paint -1 (lib.atlas leaves them to the
    quantized bake), then the kit joins in; slot order = `mats`."""
    me = obj.data
    me.materials.clear()
    for m in mats:
        me.materials.append(m)
    n = len(me.polygons)
    me.polygons.foreach_set("material_index", [0] * n)
    attr = me.attributes.get("paint") or me.attributes.new("paint", "INT", "FACE")
    attr.data.foreach_set("value", [-1] * n)
    paints = kit["paints"]
    _select_only([obj, kit], active=obj)
    bpy.ops.object.join()
    obj["paints"] = paints
    obj.name = name
    me.name = name
    for m in [m for m in obj.modifiers if m.type == "ARMATURE"]:
        obj.modifiers.remove(m)
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    obj.parent = arm
    me.uv_layers.active = me.uv_layers["UVMap"]
    src_attr = me.attributes.get("src_id")
    if src_attr is not None:  # the AI weapon shows on the weapon slot (Cindermaw's override)
        src = [a.value for a in src_attr.data]
        idx = [0] * len(me.polygons)
        me.polygons.foreach_get("material_index", idx)
        me.polygons.foreach_set("material_index", [2 if src[i] == 1 else idx[i] for i in range(len(idx))])
    return obj


# ---------------------------------------------------------------------------
# Gear regions (heroes: one look per rarity, swapped per slot at runtime)
# ---------------------------------------------------------------------------

HUMANOID_REGIONS = {
    "helm": ("head",),
    "chest": ("hips", "spine", "chest", "upper_arm.L", "upper_arm.R", "thigh.L", "thigh.R"),
    "gloves": ("forearm.L", "forearm.R", "hand.L", "hand.R"),
    "boots": ("shin.L", "shin.R", "foot.L", "foot.R"),
}
REGION_PREFIX = "rg_"


def split_regions(body, regions=HUMANOID_REGIONS, rings=2, weapon_bone="hand.R", bones=None, robe_radius=None):
    """Cut the joined body into one object per gear region (rg_helm, rg_chest,
    rg_gloves, rg_boots, rg_weapon). A face goes to the region most of its
    vertices' dominant bones belong to; script-kit faces on `weapon_bone` are
    the weapon. Every region then grows `rings` face rings into its AI
    neighbours, so pieces of different looks overlap instead of gapping.
    Each object keeps the armature, weights, slots and the shared atlas UVs.
    robe_radius (robed classes): a boots face farther than this from both
    shin bones is a robe or coat skirt and stays with the chest, so a long hem
    never splits at the knee when looks are mixed."""
    from collections import Counter
    me = body.data
    names = {vg.index: vg.name for vg in body.vertex_groups}
    dom = [names[max(v.groups, key=lambda g: g.weight).group] if len(v.groups) else "" for v in me.vertices]
    bone_region = {b: r for r, bones in regions.items() for b in bones}
    paint = [a.value for a in me.attributes["paint"].data]
    src_attr = me.attributes.get("src_id")
    src = [a.value for a in src_attr.data] if src_attr is not None else [0] * len(me.polygons)
    face_region = []
    for p in me.polygons:
        if (paint[p.index] != -1 and any(dom[i] == weapon_bone for i in p.vertices)) or src[p.index] == 1:
            face_region.append("weapon")  # script-kit parts in the fist, or the look's AI weapon
            continue
        votes = Counter(bone_region.get(dom[i], "chest") for i in p.vertices)
        face_region.append(max(sorted(votes), key=lambda r: votes[r]))
    if robe_radius and bones:
        shins = [(Vector(h), Vector(t)) for n, _p, h, t in bones if n.startswith("shin.")]
        for p in me.polygons:
            if face_region[p.index] == "boots" and src[p.index] != 1:
                c = p.center
                if min(_segment_dist(c, a, b) for a, b in shins) > robe_radius:
                    face_region[p.index] = "chest"
    sets = {r: {i for i, fr in enumerate(face_region) if fr == r} for r in sorted(set(face_region))}
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    for r in regions:
        cur = set(sets.get(r, ()))
        frontier = set(cur)
        for _ in range(rings):
            nxt = set()
            for fi in frontier:
                for e in bm.faces[fi].edges:
                    for g in e.link_faces:
                        if g.index not in cur and paint[g.index] == -1:
                            nxt.add(g.index)
            cur |= nxt
            frontier = nxt
        sets[r] = cur
    bm.free()
    out = {}
    for r, faces in sets.items():
        obj = body.copy()
        obj.data = me.copy()
        bpy.context.scene.collection.objects.link(obj)
        obj.name = REGION_PREFIX + r
        obj.data.name = REGION_PREFIX + r
        rb = bmesh.new()
        rb.from_mesh(obj.data)
        rb.faces.ensure_lookup_table()
        bmesh.ops.delete(rb, geom=[f for f in rb.faces if f.index not in faces], context="FACES")
        loose = [v for v in rb.verts if not v.link_faces]
        if loose:
            bmesh.ops.delete(rb, geom=loose, context="VERTS")
        rb.to_mesh(obj.data)
        rb.free()
        obj.data.validate(clean_customdata=False)  # glTF export warns on stray degenerate loops
        out[r] = obj
    bpy.data.objects.remove(body)
    bpy.context.view_layer.update()
    return out


# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------

def verify(body, arm, bones, budget, atlas_path=None, palette=None):
    me = body.data
    tri = sum(len(p.vertices) - 2 for p in me.polygons)
    used = sorted({p.material_index for p in me.polygons})
    tmpl = {n: (Vector(h), Vector(t)) for n, _p, h, t in bones}
    bone_err = max(max((b.head_local - tmpl[b.name][0]).length, (b.tail_local - tmpl[b.name][1]).length)
                   for b in arm.data.bones)
    over4 = zero = 0
    for v in me.vertices:
        ws = [g.weight for g in v.groups if g.weight > 1e-4]
        over4 += len(ws) > 4
        zero += sum(ws) < 1e-4
    lo = [min(v.co[i] for v in me.vertices) for i in range(3)]
    hi = [max(v.co[i] for v in me.vertices) for i in range(3)]
    names = {vg.index: vg.name for vg in body.vertex_groups}

    def dominant(v):
        return names[max(v.groups, key=lambda g: g.weight).group] if len(v.groups) else ""
    body_r = max(math.hypot(v.co.x, v.co.y) for v in me.vertices if not dominant(v).startswith("hand"))
    clips = {a.name: [int(a.frame_range[0]), int(a.frame_range[1])] for a in bpy.data.actions}
    report = {
        "tris": tri, "budget": budget, "tris_ok": tri <= budget,
        "bones": [b.name for b in arm.data.bones], "bones_ok": set(tmpl) == {b.name for b in arm.data.bones}
        and bone_err < 1e-5,
        "slots": [m.name for m in me.materials], "slots_used": used, "slots_ok": used == list(range(len(me.materials))),
        "weights_over4": over4, "weightless": zero, "weights_ok": over4 == 0 and zero == 0,
        "bbox_min": _r(lo), "bbox_max": _r(hi), "height_ok": hi[2] <= 2.0 + 1e-3,
        "body_radius_wo_hands": round(body_r, 3),
        "clips": clips,
    }
    if atlas_path and palette is not None:
        img = bpy.data.images.load(atlas_path, check_existing=False)
        px = list(img.pixels)
        bpy.data.images.remove(img)
        allowed = {tuple(round(c * 255) for c in rig.hex_to_srgb(h)) for h in palette}
        seen = {tuple(round(px[i + k] * 255) for k in range(3)) for i in range(0, len(px), 4)}
        report["atlas_off_palette"] = len(seen - allowed)
    report["ok"] = all(report[k] for k in ("tris_ok", "bones_ok", "slots_ok", "weights_ok", "height_ok"))
    return report


def write_json(path, data):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


# ---------------------------------------------------------------------------
# Review sheet: landmarks over the mesh (front + side, Workbench x-ray)
# ---------------------------------------------------------------------------

def _sticks(landmarks, r=0.02):
    bm = bmesh.new()
    for head, tail in landmarks.values():
        a, b = Vector(head), Vector(tail)
        d = b - a
        if d.length < 1e-4:
            continue
        ret = bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=r, radius2=r * 0.4, depth=d.length)
        m = Matrix.Translation((a + b) * 0.5) @ d.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
        bmesh.ops.transform(bm, matrix=m, verts=ret["verts"])
        ball = bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=6, radius=r * 1.8)
        bmesh.ops.translate(bm, vec=a, verts=ball["verts"])
    me = bpy.data.meshes.new("fit_sticks")
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new("fit_sticks", me)
    bpy.context.scene.collection.objects.link(obj)
    mat = bpy.data.materials.new("fit_sticks")
    mat.diffuse_color = (1.0, 0.1, 0.6, 1.0)
    me.materials.append(mat)
    return obj


def landmark_sheet(obj, landmarks, path, tile=520):
    """front | side | back of the mesh in x-ray with the landmark bones."""
    import os
    import numpy as np
    scene = bpy.context.scene
    sticks = _sticks(landmarks)
    scene.render.engine = "BLENDER_WORKBENCH"
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "OBJECT"
    sh.show_xray = True
    sh.xray_alpha = 0.3
    obj.color = (0.75, 0.75, 0.78, 1.0)
    sticks.color = (1.0, 0.1, 0.6, 1.0)
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = tile
    scene.render.resolution_y = tile
    scene.render.image_settings.file_format = "PNG"
    cam = bpy.data.objects.new("fit_cam", bpy.data.cameras.new("fit_cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 2.3
    scene.collection.objects.link(cam)
    scene.camera = cam
    tiles = []
    tmp = path + ".tile.png"
    for eye in ((0.0, -6.0, 1.0), (-6.0, 0.0, 1.0), (0.0, 6.0, 1.0)):
        cam.location = eye
        cam.rotation_euler = (Vector((0.0, 0.0, 1.0)) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(tmp, check_existing=False)
        buf = np.empty(tile * tile * 4, dtype=np.float32)
        img.pixels.foreach_get(buf)
        bpy.data.images.remove(img)
        tiles.append(buf.reshape(tile, tile, 4))
    os.remove(tmp)
    sheet = np.concatenate(tiles, axis=1)
    out = bpy.data.images.new("fit_sheet", sheet.shape[1], sheet.shape[0], alpha=False)
    out.pixels.foreach_set(np.ascontiguousarray(sheet).ravel())
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()
    bpy.data.images.remove(out)
    bpy.data.objects.remove(sticks)
    bpy.data.objects.remove(cam)
    sh.show_xray = False
    print("fit: landmark sheet", path)
