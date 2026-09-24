"""Shared Blender-headless helpers for RUNEBOUND rigged characters (M06).

Conventions (match the existing pipeline):
- Blender Z-up, character faces -Y. Godot instances the GLB with rotation.y = PI.
- Rigid skinning: every body part is weighted 1.0 to exactly one bone, so the
  chunky faceted parts never smear.
- Colors come from assets/art_spec.json as sRGB hex and are converted to
  linear before they touch Blender (Blender's Base Color is linear; writing
  sRGB values there made every model render lighter than its palette).
- Clips are authored at 60 fps, start at frame 0, carry no root motion.
"""
import json
import math
import os

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
FPS = 60


# ---------------------------------------------------------------------------
# Spec + color
# ---------------------------------------------------------------------------

def load_spec():
    with open(os.path.join(ROOT, "assets", "art_spec.json"), encoding="utf-8") as f:
        return json.load(f)


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_to_srgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def hex_to_linear(h):
    return tuple(srgb_to_linear(c) for c in hex_to_srgb(h))


# ---------------------------------------------------------------------------
# Scene
# ---------------------------------------------------------------------------

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.render.fps_base = 1.0
    return scene


def make_material(name, color_hex, emission_hex=None, strength=0.0, roughness=0.85):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*hex_to_linear(color_hex), 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    if emission_hex is not None:
        bsdf.inputs["Emission Color"].default_value = (*hex_to_linear(emission_hex), 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    return mat


# ---------------------------------------------------------------------------
# Armature
# ---------------------------------------------------------------------------

def build_armature(name, bones):
    """bones: list of (name, parent_or_None, head_xyz, tail_xyz)."""
    arm_data = bpy.data.armatures.new(name + "_armature")
    arm_obj = bpy.data.objects.new(name + "_rig", arm_data)
    bpy.context.scene.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    arm_obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    edit = arm_data.edit_bones
    for bone_name, parent, head, tail in bones:
        b = edit.new(bone_name)
        b.head = Vector(head)
        b.tail = Vector(tail)
        if parent is not None:
            b.parent = edit[parent]
            b.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


# ---------------------------------------------------------------------------
# Mesh parts (one bmesh, rigid vertex groups, fixed-density box UVs)
# ---------------------------------------------------------------------------

class PartMesh:
    """Accumulates rigid parts into one mesh. Each part: bone + material slot +
    paint (palette ramp + base step + pattern) used by lib.atlas to bake the
    per-character pixel atlas."""

    def __init__(self, px_per_m=64, atlas_px=128):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.paint_layer = self.bm.faces.layers.int.new("paint")
        self.paints = [{"ramp": ["#808080"], "base": 0, "pattern": "plain"}]
        self.groups = {}
        self.uv_scale = px_per_m / float(atlas_px)

    def paint(self, ramp, base, pattern="plain"):
        """Register a paint and return its index for box()/loft()."""
        self.paints.append({"ramp": list(ramp), "base": int(base), "pattern": pattern})
        return len(self.paints) - 1

    def _finish_part(self, verts, bone, mat_index, paint=0):
        faces = {f for v in verts for f in v.link_faces}
        for f in faces:
            f.material_index = mat_index
            f.smooth = False
            f[self.paint_layer] = paint
        self.groups.setdefault(bone, []).extend(verts)
        self._box_uv(faces)

    def loft(self, bone, rings, sides=8, center=(0.0, 0.0, 0.0), rot=(0.0, 0.0, 0.0),
             mat_index=0, paint=0, phase=None):
        """Faceted form lofted through cross-section rings (local Z up).
        rings: [(z, rx, ry, cx, cy), ...] ellipse half-sizes + centre offset.
        sides=8 reads as a chamfered block, 6 as hex; tapering rings give barrel
        chests, domed pauldrons, flared boots instead of boxes."""
        if phase is None:
            phase = math.pi / sides
        loops = []
        for z, rx, ry, cx, cy in rings:
            ring = []
            for k in range(sides):
                a = phase + 2.0 * math.pi * k / sides
                ring.append(self.bm.verts.new((cx + rx * math.cos(a), cy + ry * math.sin(a), z)))
            loops.append(ring)
        faces = []
        for r0, r1 in zip(loops, loops[1:]):
            for k in range(sides):
                faces.append(self.bm.faces.new((r0[k], r0[(k + 1) % sides], r1[(k + 1) % sides], r1[k])))
        faces.append(self.bm.faces.new(list(reversed(loops[0]))))
        faces.append(self.bm.faces.new(loops[-1]))
        verts = [v for ring in loops for v in ring]
        m = Euler(rot).to_matrix().to_4x4()
        m.translation = Vector(center)
        bmesh.ops.transform(self.bm, matrix=m, verts=verts)
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)
        self.bm.normal_update()
        self._finish_part(verts, bone, mat_index, paint)
        return verts

    def _box_uv(self, faces):
        # Dominant-axis projection in object space at the fixed texel density:
        # consistent pixels on every part without hand unwrapping.
        s = self.uv_scale
        for f in faces:
            n = f.normal
            ax = max(range(3), key=lambda i: abs(n[i]))
            for loop in f.loops:
                co = loop.vert.co
                if ax == 2:
                    uv = (co.x, co.y)
                elif ax == 0:
                    uv = (co.y, co.z)
                else:
                    uv = (co.x, co.z)
                loop[self.uv].uv = (uv[0] * s, uv[1] * s)

    def box(self, bone, size, center, rot=(0.0, 0.0, 0.0), mat_index=0, taper=1.0, paint=0):
        """Chunky box; `taper` < 1 narrows the +Z end (forms, not boxes)."""
        ret = bmesh.ops.create_cube(self.bm, size=1.0)
        verts = ret["verts"]
        for v in verts:
            t = taper if v.co.z > 0 else 1.0
            v.co = Vector((v.co.x * size[0] * t, v.co.y * size[1] * t, v.co.z * size[2]))
        m = Euler(rot).to_matrix().to_4x4()
        m.translation = Vector(center)
        bmesh.ops.transform(self.bm, matrix=m, verts=verts)
        self.bm.normal_update()
        self._finish_part(verts, bone, mat_index, paint)
        return verts

    def to_object(self, name, materials, armature):
        self.bm.verts.index_update()
        self.bm.normal_update()
        indices = {bone: [v.index for v in verts] for bone, verts in self.groups.items()}
        mesh = bpy.data.meshes.new(name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        for mat in materials:
            mesh.materials.append(mat)
        for bone, idx in indices.items():
            if bone is None:
                continue  # static props: no skinning
            vg = obj.vertex_groups.new(name=bone)
            vg.add(idx, 1.0, "REPLACE")
        if armature is not None:
            mod = obj.modifiers.new("Armature", "ARMATURE")
            mod.object = armature
            obj.parent = armature
        obj["paints"] = json.dumps(self.paints)
        return obj


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

def _fcurves(action, obj):
    """F-curves of `action` for obj's slot (Blender 4.4+ slotted actions)."""
    legacy = getattr(action, "fcurves", None)
    if legacy is not None and len(legacy) > 0:
        return legacy
    slot = obj.animation_data.action_slot
    for layer in action.layers:
        for strip in layer.strips:
            bag = strip.channelbag(slot)
            if bag is not None:
                return bag.fcurves
    return []


def make_action(arm_obj, name, keys, interpolation=None):
    """keys: list of (frame, {bone: (rx, ry, rz) radians | {"rot":..., "loc":...}}).
    interpolation: optional dict frame -> ("BACK"|"EXPO"|"QUART"|"CONSTANT"|..., easing).
    Unkeyed bones stay at rest. Returns the action."""
    if arm_obj.animation_data is None:
        arm_obj.animation_data_create()
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    arm_obj.animation_data.action = action
    for pb in arm_obj.pose.bones:
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = Euler((0.0, 0.0, 0.0))
        pb.location = Vector((0.0, 0.0, 0.0))
    for frame, pose in keys:
        for bone, value in pose.items():
            pb = arm_obj.pose.bones[bone]
            rot = value.get("rot") if isinstance(value, dict) else value
            loc = value.get("loc") if isinstance(value, dict) else None
            if rot is not None:
                pb.rotation_euler = Euler(rot)
                pb.keyframe_insert("rotation_euler", frame=frame, group=bone)
            if loc is not None:
                pb.location = Vector(loc)
                pb.keyframe_insert("location", frame=frame, group=bone)
    if interpolation:
        for fc in _fcurves(action, arm_obj):
            for kp in fc.keyframe_points:
                spec = interpolation.get(int(round(kp.co.x)))
                if spec is not None:
                    kp.interpolation = spec[0]
                    if len(spec) > 1 and spec[1]:
                        kp.easing = spec[1]
    frames = [k[0] for k in keys]
    action.use_frame_range = True
    action.frame_start = min(frames)
    action.frame_end = max(frames)
    return action


def export_glb(path, active_action=None, arm_obj=None):
    if arm_obj is not None and active_action is not None:
        arm_obj.animation_data.action = active_action
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=False,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_force_sampling=True,
        export_anim_slide_to_zero=True,
        export_anim_single_armature=True,
        export_image_format="NONE",
        export_skins=True,
        export_def_bones=False,
        export_yup=True,
        export_apply=False,
    )
    print("exported:", path)
