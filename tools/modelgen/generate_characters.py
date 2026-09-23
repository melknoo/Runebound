"""RUNEBOUND character model generator (Blender headless).

Builds three stylized low-poly character bodies (beveled chunky forms,
flat materials, emissive accents) and exports GLBs for Godot:
  assets/models/player_runebreaker.glb
  assets/models/enemy_rusher.glb
  assets/models/enemy_caster.glb

Weapons are NOT included — the game builds them in code so ability
animations can swing their pivots.

Run:  & "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python tools/modelgen/generate_characters.py
"""
import os
import bpy

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "models")
os.makedirs(OUT, exist_ok=True)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def make_mat(name, color, rough=0.8, emission=None, strength=2.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    return m


def _finish(ob, material, bevel):
    if bevel > 0:
        mod = ob.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
        bpy.ops.object.modifier_apply(modifier=mod.name)
    ob.data.materials.append(material)
    bpy.ops.object.shade_flat()
    return ob


def box(size, loc, material, bevel=0.025, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    ob = bpy.context.active_object
    ob.scale = size
    bpy.ops.object.transform_apply(scale=True)
    return _finish(ob, material, bevel)


def cone(r1, r2, depth, loc, material, verts=10, bevel=0.0, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2,
                                    depth=depth, location=loc, rotation=rot)
    return _finish(bpy.context.active_object, material, bevel)


def sphere(r, loc, material, segments=10, rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=segments,
                                         ring_count=rings, location=loc)
    return _finish(bpy.context.active_object, material, 0.0)


def join_and_export(parts, filename):
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.name = os.path.splitext(filename)[0]
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    path = os.path.join(OUT, filename)
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True)
    print("exported:", path)


def build_player():
    clear_scene()
    iron = make_mat("iron", (0.30, 0.32, 0.42))
    dark = make_mat("dark_iron", (0.18, 0.19, 0.26))
    teal = make_mat("teal", (0.13, 0.52, 0.52), rough=0.6)
    glow = make_mat("rune_glow", (1.0, 0.55, 0.2), emission=(1.0, 0.5, 0.15), strength=3.0)
    skin = make_mat("skin", (0.85, 0.68, 0.55))

    parts = []
    # legs (Z up: heights are z)
    parts.append(box((0.2, 0.26, 0.5), (-0.13, 0, 0.27), dark))
    parts.append(box((0.2, 0.26, 0.5), (0.13, 0, 0.27), dark))
    # belt
    parts.append(box((0.52, 0.36, 0.16), (0, 0, 0.6), teal))
    # torso: hips + broad chest
    parts.append(box((0.5, 0.34, 0.28), (0, 0, 0.8), iron))
    parts.append(box((0.7, 0.42, 0.42), (0, 0, 1.14), iron, bevel=0.05))
    # chest sigil
    parts.append(box((0.16, 0.06, 0.22), (0, -0.22, 1.14), glow, bevel=0.0))
    # pauldrons
    parts.append(box((0.3, 0.36, 0.24), (-0.48, 0, 1.32), teal, bevel=0.05, rot=(0, -0.12, 0)))
    parts.append(box((0.3, 0.36, 0.24), (0.48, 0, 1.32), teal, bevel=0.05, rot=(0, 0.12, 0)))
    # arms
    parts.append(box((0.16, 0.2, 0.5), (-0.5, 0, 0.95), dark))
    parts.append(box((0.16, 0.2, 0.5), (0.5, 0, 0.95), dark))
    # head: helmet with emissive visor slit + crest
    parts.append(sphere(0.13, (0, 0, 1.48), skin))
    parts.append(box((0.3, 0.32, 0.26), (0, 0, 1.6), iron, bevel=0.05))
    parts.append(box((0.26, 0.05, 0.05), (0, -0.16, 1.58), glow, bevel=0.0))
    parts.append(box((0.06, 0.3, 0.12), (0, 0, 1.76), teal, bevel=0.02))
    join_and_export(parts, "player_runebreaker.glb")


def build_rusher():
    clear_scene()
    rust = make_mat("rust", (0.68, 0.30, 0.20))
    dark = make_mat("dark_rust", (0.42, 0.20, 0.15))
    bone = make_mat("bone", (0.85, 0.80, 0.68), rough=0.65)
    gold = make_mat("gold_eyes", (1.0, 0.85, 0.3), emission=(1.0, 0.8, 0.25), strength=3.0)

    parts = []
    # stubby legs
    parts.append(box((0.24, 0.3, 0.34), (-0.2, 0, 0.19), dark))
    parts.append(box((0.24, 0.3, 0.34), (0.2, 0, 0.19), dark))
    # massive torso, wider at the top
    parts.append(box((0.8, 0.55, 0.45), (0, 0, 0.58), rust, bevel=0.06))
    parts.append(box((0.95, 0.6, 0.4), (0, 0, 0.94), rust, bevel=0.07))
    # shoulder slabs
    parts.append(box((0.3, 0.45, 0.3), (-0.55, 0, 1.05), dark, bevel=0.05, rot=(0, -0.2, 0)))
    parts.append(box((0.3, 0.45, 0.3), (0.55, 0, 1.05), dark, bevel=0.05, rot=(0, 0.2, 0)))
    # thick arms
    parts.append(box((0.2, 0.24, 0.55), (-0.58, 0, 0.62), rust))
    parts.append(box((0.2, 0.24, 0.55), (0.58, 0, 0.62), rust))
    # head: low box with jaw, horns, glowing eyes
    parts.append(box((0.38, 0.36, 0.3), (0, -0.08, 1.3), dark, bevel=0.04))
    parts.append(box((0.42, 0.14, 0.12), (0, -0.2, 1.2), bone, bevel=0.02))
    parts.append(box((0.3, 0.05, 0.06), (0, -0.27, 1.33), gold, bevel=0.0))
    parts.append(cone(0.07, 0.0, 0.25, (-0.24, -0.05, 1.5), bone, verts=6, rot=(0.3, 0, -0.3)))
    parts.append(cone(0.07, 0.0, 0.25, (0.24, -0.05, 1.5), bone, verts=6, rot=(0.3, 0, 0.3)))
    join_and_export(parts, "enemy_rusher.glb")


def build_caster():
    clear_scene()
    violet = make_mat("violet_robe", (0.42, 0.27, 0.62))
    dark = make_mat("dark_violet", (0.25, 0.15, 0.4))
    magenta = make_mat("magenta_eyes", (0.85, 0.45, 1.0), emission=(0.75, 0.35, 1.0), strength=3.0)

    parts = []
    # robe: tall tapered cone with a flared hem
    parts.append(cone(0.5, 0.2, 1.35, (0, 0, 0.675), violet, verts=10))
    parts.append(cone(0.55, 0.48, 0.18, (0, 0, 0.09), dark, verts=10))
    # sash
    parts.append(box((0.42, 0.42, 0.1), (0, 0, 0.95), dark, bevel=0.02))
    # shoulders
    parts.append(box((0.62, 0.3, 0.16), (0, 0, 1.38), dark, bevel=0.04))
    # hood: sharp cone, tilted forward
    parts.append(cone(0.3, 0.0, 0.55, (0, -0.03, 1.72), dark, verts=8, rot=(0.15, 0, 0)))
    # face void + glowing eyes
    parts.append(box((0.26, 0.1, 0.2), (0, -0.16, 1.52), make_mat("void", (0.05, 0.03, 0.08), rough=1.0), bevel=0.0))
    parts.append(box((0.18, 0.04, 0.045), (0, -0.22, 1.54), magenta, bevel=0.0))
    join_and_export(parts, "enemy_caster.glb")


def build_assassin():
    clear_scene()
    teal = make_mat("assassin_teal", (0.14, 0.4, 0.45))
    dark = make_mat("assassin_dark", (0.08, 0.2, 0.24))
    cyan = make_mat("assassin_eyes", (0.5, 1.0, 0.9), emission=(0.4, 1.0, 0.85), strength=3.0)

    parts = []
    # slim legs, lean crouched torso
    parts.append(box((0.14, 0.2, 0.5), (-0.1, 0, 0.27), dark))
    parts.append(box((0.14, 0.2, 0.5), (0.1, 0, 0.27), dark))
    parts.append(box((0.34, 0.26, 0.5), (0, 0.03, 0.75), teal, bevel=0.04, rot=(0.15, 0, 0)))
    # scarf/shoulder wrap
    parts.append(box((0.44, 0.32, 0.14), (0, 0.02, 1.04), dark, bevel=0.04))
    # trailing scarf tail
    parts.append(box((0.1, 0.4, 0.08), (0.12, 0.28, 0.95), dark, bevel=0.02, rot=(0.5, 0, 0)))
    # thin arms
    parts.append(box((0.1, 0.14, 0.42), (-0.26, -0.05, 0.78), teal))
    parts.append(box((0.1, 0.14, 0.42), (0.26, -0.05, 0.78), teal))
    # hooded head, low and forward
    parts.append(box((0.26, 0.28, 0.24), (0, -0.06, 1.28), teal, bevel=0.05))
    parts.append(cone(0.16, 0.02, 0.3, (0, 0.06, 1.46), dark, verts=6, rot=(0.3, 0, 0)))
    # narrow glowing eye slit
    parts.append(box((0.16, 0.04, 0.035), (0, -0.19, 1.28), cyan, bevel=0.0))
    join_and_export(parts, "enemy_assassin.glb")


def build_brute():
    clear_scene()
    stone = make_mat("brute_stone", (0.42, 0.45, 0.4))
    dark = make_mat("brute_dark", (0.26, 0.29, 0.26))
    moss = make_mat("brute_moss", (0.3, 0.45, 0.3), rough=0.9)
    ember = make_mat("brute_eyes", (1.0, 0.5, 0.2), emission=(1.0, 0.45, 0.15), strength=3.0)

    parts = []
    # stumpy legs
    parts.append(box((0.34, 0.4, 0.4), (-0.3, 0, 0.22), dark))
    parts.append(box((0.34, 0.4, 0.4), (0.3, 0, 0.22), dark))
    # colossal torso: two stacked slabs, wider on top
    parts.append(box((1.05, 0.7, 0.6), (0, 0, 0.75), stone, bevel=0.08))
    parts.append(box((1.25, 0.75, 0.55), (0, 0, 1.3), stone, bevel=0.1))
    # moss patches on the shoulders
    parts.append(box((0.4, 0.5, 0.1), (-0.45, 0, 1.62), moss, bevel=0.03))
    parts.append(box((0.3, 0.4, 0.08), (0.5, 0.05, 1.6), moss, bevel=0.03))
    # small sunken head between the shoulders
    parts.append(box((0.42, 0.4, 0.3), (0, -0.12, 1.62), dark, bevel=0.05))
    parts.append(box((0.32, 0.06, 0.06), (0, -0.32, 1.64), ember, bevel=0.0))
    # massive arms hanging low (fists are code-built pivots in game)
    parts.append(box((0.3, 0.36, 0.85), (-0.78, 0, 0.95), stone, bevel=0.06))
    parts.append(box((0.3, 0.36, 0.85), (0.78, 0, 0.95), stone, bevel=0.06))
    join_and_export(parts, "enemy_brute.glb")


def build_warden():
    clear_scene()
    stone = make_mat("warden_stone", (0.38, 0.36, 0.46))
    dark = make_mat("warden_dark", (0.24, 0.22, 0.32))
    core = make_mat("warden_core", (0.4, 1.0, 0.9), emission=(0.35, 0.95, 0.85), strength=3.5)

    parts = []
    # broad shield-like front slab: reads as "don't hit me from here"
    parts.append(box((0.9, 0.25, 1.1), (0, -0.32, 0.75), stone, bevel=0.06))
    # blocky body behind the slab
    parts.append(box((0.6, 0.45, 0.9), (0, 0.1, 0.7), dark, bevel=0.05))
    parts.append(box((0.7, 0.5, 0.5), (0, 0.1, 1.25), stone, bevel=0.06))
    # head slit
    parts.append(box((0.4, 0.18, 0.22), (0, -0.05, 1.55), dark, bevel=0.03))
    parts.append(box((0.26, 0.05, 0.04), (0, -0.16, 1.55), core, bevel=0.0))
    # stumpy legs
    parts.append(box((0.26, 0.3, 0.45), (-0.22, 0, 0.24), dark))
    parts.append(box((0.26, 0.3, 0.45), (0.22, 0, 0.24), dark))
    # arms as slabs
    parts.append(box((0.22, 0.3, 0.7), (-0.52, 0, 0.8), stone, bevel=0.05))
    parts.append(box((0.22, 0.3, 0.7), (0.52, 0, 0.8), stone, bevel=0.05))
    # EXPOSED RUNE CORE ON THE BACK: the weak point must read at a glance
    parts.append(box((0.3, 0.12, 0.3), (0, 0.35, 0.85), core, bevel=0.02))
    join_and_export(parts, "enemy_warden.glb")


def build_vessel():
    clear_scene()
    crystal = make_mat("vessel_crystal", (0.45, 0.32, 0.68), rough=0.45)
    dark = make_mat("vessel_dark", (0.22, 0.16, 0.38))
    core = make_mat("vessel_core", (0.75, 0.5, 1.0), emission=(0.7, 0.4, 1.0), strength=4.0)

    parts = []
    # floating shard body: stacked rotated prisms around a glowing heart
    parts.append(sphere(0.45, (0, 0, 1.6), core))
    for i, (loc, rot, sz) in enumerate([
        ((0, 0, 2.35), (0, 0, 0.4), (0.5, 1.1, 0.5)),
        ((-0.55, 0, 1.75), (0.3, 0, 0.9), (0.4, 1.0, 0.4)),
        ((0.55, 0, 1.7), (-0.3, 0, -0.8), (0.42, 1.05, 0.42)),
        ((0, 0.35, 1.3), (0.9, 0.2, 0), (0.36, 0.9, 0.36)),
        ((0, -0.4, 1.9), (-0.8, 0, 0.3), (0.34, 0.85, 0.34)),
    ]):
        bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=sz[0], radius2=0.05,
                                        depth=sz[1], location=loc, rotation=rot)
        parts.append(_finish(bpy.context.active_object, crystal if i % 2 == 0 else dark, 0.0))
    # jagged skirt of small shards below
    for k in range(6):
        a = k * 3.14159 * 2 / 6
        import math
        loc = (math.cos(a) * 0.7, math.sin(a) * 0.7, 0.85)
        bpy.ops.mesh.primitive_cone_add(vertices=5, radius1=0.18, radius2=0.02,
                                        depth=0.6, location=loc, rotation=(3.14159, 0, 0))
        parts.append(_finish(bpy.context.active_object, dark, 0.0))
    join_and_export(parts, "boss_vessel.glb")


build_player()
build_rusher()
build_caster()
build_assassin()
build_brute()
build_warden()
build_vessel()
print("all characters exported.")
