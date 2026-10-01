"""RUNEBOUND M06 environment prop kit (Blender 5.2 headless) — reusable
building blocks per biome kit (and for the M08+ open zones).

  assets/models/env/<kit>/<prop>.glb + assets/textures/env/<prop>_atlas.png
  kits: highlands (ash raiders), runehold (settlement, rh_*), spire (sp_*)

Props are static meshes at the ENVIRONMENT texel density (32 px/m), baked with
the same pixel-atlas method as characters. Materials are matched by NAME in
Godot (SetPieces.prop): <prop>_body (atlas), <prop>_cloth (atlas + wind
sway, e.g. hide banners), <prop>_glow (dim environment emissive). Walk-through
props stay <= 0.4 m tall (no new collision in M06); tall props go on collider
tops or outside the playable area. Scatter items (ash_tuft, stone_cluster)
are instanced by scripts/world/scatter.gd. Z-up, props face -Y.

Run: & "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python tools/modelgen/generate_props.py
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import atlas, rig  # noqa: E402

ROOT = rig.ROOT
SPEC = rig.load_spec()
HL = SPEC["palettes"]["highlands"]
CM = SPEC["palettes"]["cinder_marauder"]
RH = SPEC["palettes"]["runehold"]
RB = SPEC["palettes"]["runebreaker"]
ROLES = SPEC["color_roles"]
ENV_DENSITY = SPEC["texel_density"]["environment_px_per_m"]
OUT_ENV = os.path.join(ROOT, "assets", "models", "env")
OUT_TEX = os.path.join(ROOT, "assets", "textures", "env")


GLOW = 1   # material slot index used by pm parts for the glow material
CLOTH = 2  # ... and for wind-swayed cloth (slots are compacted on export)
GLOW_B = 3  # second emissive colour (e.g. rune inlay + lit window on one prop)


def finish(pm, name, glow_hex=None, glow_strength=0.8, cloth=False, kit="highlands", glows=None,
           sizes=(32, 64, 128, 256), axis_aligned=False):
    """Materials in slot order body, glow?, cloth?, extra glows — parts use
    GLOW / CLOTH / GLOW_B; unused slots are dropped and the indices remapped
    before export. glows: {slot: (suffix, hex, strength)}; every emissive
    material name ends in _glow (SetPieces matches by name)."""
    slots = {0: rig.make_material(name + "_body", "#FFFFFF")}
    glow_slots = []
    if glow_hex is not None:
        slots[GLOW] = rig.make_material(name + "_glow", glow_hex, emission_hex=glow_hex, strength=glow_strength)
        glow_slots.append(GLOW)
    if cloth:
        slots[CLOTH] = rig.make_material(name + "_cloth", "#FFFFFF")
    for slot, (suffix, hexc, strength) in (glows or {}).items():
        slots[slot] = rig.make_material("%s_%s_glow" % (name, suffix), hexc, emission_hex=hexc, strength=strength)
        glow_slots.append(slot)
    order = sorted(slots)
    remap = {old: new for new, old in enumerate(order)}
    for f in pm.bm.faces:
        f.material_index = remap.get(f.material_index, 0)
    obj = pm.to_object(name, [slots[i] for i in order], None)
    size = atlas.unwrap(obj, ENV_DENSITY, sizes=sizes, axis_aligned=axis_aligned)
    os.makedirs(OUT_TEX, exist_ok=True)
    atlas.bake(obj, size, os.path.join(OUT_TEX, name + "_atlas.png"),
               skip_material_indices=tuple(remap[k] for k in glow_slots))
    rig.export_glb(os.path.join(OUT_ENV, kit, name + ".glb"))


def glow_object(name, parts):
    """Separate emissive-only object in the same GLB (animated in Godot by
    node name, e.g. hearth flames). parts: [(hex, strength, build(pm, idx))]."""
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    mats = []
    for k, (hexc, strength, build) in enumerate(parts):
        mats.append(rig.make_material("%s_%d_glow" % (name, k), hexc, emission_hex=hexc, strength=strength))
        build(pm, k)
    return pm.to_object(name, mats, None)


def bonfire():
    rig.reset_scene()
    rnd = random.Random(31)
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    stone = pm.paint(HL["basalt"], 3)
    wood = pm.paint(CM["wood"], 1, "hide")
    for k in range(9):
        a = k * math.tau / 9 + rnd.uniform(-0.1, 0.1)
        r = 0.62 + rnd.uniform(-0.04, 0.05)
        s = rnd.uniform(0.13, 0.18)
        pm.loft(None, [(0.0, s, s * 0.9, 0, 0), (s * 1.2, s * 0.8, s * 0.7, 0, 0), (s * 1.6, s * 0.35, s * 0.3, 0, 0)],
                sides=6, center=(math.cos(a) * r, math.sin(a) * r, 0.0), rot=(0, 0, a), paint=stone)
    for k in range(4):
        a = k * math.tau / 4 + 0.4
        pm.loft(None, [(0.0, 0.055, 0.055, 0, 0), (0.95, 0.045, 0.045, 0, 0)], sides=6,
                center=(math.cos(a) * 0.45, math.sin(a) * 0.45, 0.06), rot=(1.25, 0, a + math.pi / 2), paint=wood)
    pm.loft(None, [(0.0, 0.34, 0.34, 0, 0), (0.05, 0.3, 0.3, 0, 0)], sides=8, mat_index=GLOW)   # ember bed
    finish(pm, "bonfire", SPEC["color_roles"]["fire"]["body"], 1.0)


def rune_monolith():
    """Wraps the 1.2 x 4 x 1.2 greybox collider: half-width stays >= 0.62."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    stone = pm.paint(HL["basalt"], 3, "plate")
    top = pm.paint(HL["ash_top"], 2)
    pm.loft(None, [(-0.1, 0.8, 0.8, 0, 0), (0.4, 0.74, 0.74, 0, 0), (2.4, 0.68, 0.68, 0, 0), (3.9, 0.63, 0.63, 0, 0),
                   (4.06, 0.5, 0.5, 0, 0), (4.3, 0.18, 0.18, 0, 0)], sides=6, paint=stone)
    pm.loft(None, [(4.05, 0.52, 0.52, 0, 0), (4.1, 0.44, 0.44, 0, 0)], sides=6, paint=top)
    # carved rune channel down the front face (dim teal: ancient rune magic)
    for z0, z1, dx in ((0.8, 1.6, 0.0), (1.7, 2.3, 0.14), (2.4, 3.3, -0.1)):
        pm.box(None, (0.07, 0.03, z1 - z0), (dx, -0.69, (z0 + z1) * 0.5), mat_index=GLOW)
    finish(pm, "rune_monolith", SPEC["color_roles"]["player_accent"]["body"], 0.8)


def banner_pole():
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    wood = pm.paint(CM["wood"], 2, "hide")
    hide = pm.paint(CM["hide"], 2, "hide")
    bone = pm.paint(CM["bone"], 2)
    pm.loft(None, [(0.0, 0.06, 0.06, 0, 0), (3.1, 0.045, 0.045, 0, 0)], sides=6, paint=wood)
    pm.box(None, (0.9, 0.05, 0.05), (0.32, 0, 2.95), paint=wood)                    # crossbar
    # hide banner + glyph sway in the wind (cloth slot, anchored at the bar)
    pm.box(None, (0.7, 0.02, 1.25), (0.36, -0.02, 2.28), paint=hide, mat_index=CLOTH)
    pm.box(None, (0.16, 0.025, 0.4), (0.36, -0.035, 2.4), paint=bone, mat_index=CLOTH)
    pm.loft(None, [(3.1, 0.07, 0.07, 0, 0), (3.35, 0.004, 0.004, 0, 0)], sides=4, paint=bone)  # spike
    finish(pm, "banner_pole", cloth=True)


def charred_tree():
    rig.reset_scene()
    rnd = random.Random(7)
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    bark = pm.paint(HL["basalt"], 1, "hide")
    ash = pm.paint(HL["ash_top"], 1)
    pm.loft(None, [(-0.1, 0.26, 0.24, 0, 0), (0.6, 0.18, 0.17, 0.03, 0), (1.9, 0.12, 0.12, -0.05, 0.02),
                   (3.2, 0.06, 0.06, 0.08, 0.0), (3.6, 0.01, 0.01, 0.12, 0.0)], sides=6, paint=bark)
    for k, (z, a, ln) in enumerate(((1.5, 0.6, 1.1), (2.1, 2.7, 0.9), (2.6, 4.4, 0.8), (1.1, 3.6, 0.7))):
        pm.loft(None, [(0.0, 0.07, 0.07, 0, 0), (ln, 0.012, 0.012, 0, 0)], sides=5,
                center=(0, 0, z), rot=(rnd.uniform(0.7, 1.0), 0, a), paint=bark)
    pm.loft(None, [(-0.1, 0.4, 0.38, 0, 0), (0.08, 0.3, 0.28, 0, 0)], sides=7, paint=ash)  # ash mound at the foot
    finish(pm, "charred_tree")


def bone_pile():
    rig.reset_scene()
    rnd = random.Random(19)
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    bone = pm.paint(CM["bone"], 2)
    for k in range(6):
        a = rnd.uniform(0, math.tau)
        r = rnd.uniform(0.0, 0.28)
        pm.loft(None, [(0.0, 0.025, 0.025, 0, 0), (rnd.uniform(0.25, 0.4), 0.02, 0.02, 0, 0)], sides=5,
                center=(math.cos(a) * r, math.sin(a) * r, 0.03), rot=(math.pi / 2, 0, rnd.uniform(0, math.tau)), paint=bone)
    pm.loft(None, [(0.0, 0.09, 0.08, 0.05, 0.02), (0.1, 0.1, 0.09, 0.05, 0.02), (0.17, 0.06, 0.05, 0.05, 0.02)],
            sides=6, paint=bone)   # skull
    finish(pm, "bone_pile")


def ash_tuft():
    """Scatter item: dead-grass tuft, solid tapered blades (no alpha cards).
    Edge-band only — it stands taller than the 0.02 m combat-space limit.
    The whole tuft is cloth: it sways from the base."""
    rig.reset_scene()
    rnd = random.Random(23)
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    grass = pm.paint(HL["dead_grass"], 2)
    dry = pm.paint(HL["dead_grass"], 3)
    for k in range(7):
        a = k * math.tau / 7 + rnd.uniform(-0.3, 0.3)
        h = rnd.uniform(0.17, 0.3)
        lean = rnd.uniform(0.05, 0.12)
        r0 = rnd.uniform(0.0, 0.05)
        cx, cy = math.cos(a) * r0, math.sin(a) * r0
        pm.loft(None, [(0.0, 0.016, 0.01, cx, cy), (h, 0.002, 0.002, cx + math.cos(a) * lean, cy + math.sin(a) * lean)],
                sides=3, phase=a, paint=grass if k % 3 else dry, mat_index=CLOTH)
    finish(pm, "ash_tuft", cloth=True)


def stone_cluster():
    """Scatter item: a few faceted basalt stones hugging obstacle bases."""
    rig.reset_scene()
    rnd = random.Random(41)
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    stone = pm.paint(HL["basalt"], 3)
    top = pm.paint(HL["ash_top"], 1)
    for k in range(3):
        a = k * math.tau / 3 + rnd.uniform(-0.4, 0.4)
        r = 0.0 if k == 0 else rnd.uniform(0.12, 0.2)
        s = rnd.uniform(0.06, 0.1) * (1.4 if k == 0 else 1.0)
        cx, cy = math.cos(a) * r, math.sin(a) * r
        pm.loft(None, [(-0.02, s, s * 0.85, cx, cy), (s * 0.8, s * 0.8, s * 0.7, cx, cy), (s * 1.3, s * 0.3, s * 0.25, cx, cy)],
                sides=5, phase=rnd.uniform(0, 1), paint=stone)
        pm.loft(None, [(s * 1.25, s * 0.32, s * 0.27, cx, cy), (s * 1.34, s * 0.12, s * 0.1, cx, cy)],
                sides=5, paint=top)
    finish(pm, "stone_cluster")


def log_seat():
    """Camp seat: a charred log on the ground, 0.32 m tall (walk-through)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    wood = pm.paint(CM["wood"], 2, "hide")
    cut = pm.paint(CM["wood"], 3)
    pm.loft(None, [(-0.55, 0.16, 0.15, 0, 0), (0.0, 0.17, 0.16, 0, 0), (0.55, 0.15, 0.14, 0, 0)],
            sides=7, center=(0, 0, 0.15), rot=(0, math.pi / 2, 0), paint=wood)
    for x in (-0.56, 0.56):
        pm.loft(None, [(-0.01, 0.13, 0.12, 0, 0), (0.01, 0.13, 0.12, 0, 0)],
                sides=7, center=(x, 0, 0.15), rot=(0, math.pi / 2, 0), paint=cut)
    finish(pm, "log_seat")


# ---------------------------------------------------------------------------
# Runehold kit (settlement): granite, warm wood, teal Runebreaker cloth. Big
# surfaces (walls, hut bodies, sod roofs) are world-mapped terrain materials
# built in code (SetPieces.masonry_wall / hut); these props are the trim.
# ---------------------------------------------------------------------------

HUT = (5.0, 4.4, 2.8)  # hut body collider (x, depth, height); door on -Y


def _face_box(pm, face, t, out, size_along, depth, z, height, **kw):
    """Box on a hut wall face: face = (cx, cy, nx, ny) centre + outward normal,
    t metres along the face, `out` metres proud of it."""
    cx, cy, nx, ny = face
    ax, ay = (0, 1) if nx else (1, 0)
    size = (size_along if ax else depth, size_along if ay else depth, height)
    pm.box(None, size, (cx + ax * t + nx * out, cy + ay * t + ny * out, z), **kw)


def rh_hut_trim():
    """Timber frame, door, rune lintel and lit shuttered windows for the hut
    body box. Everything hugs the collider (<= 0.15 m proud)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    w, d, h = HUT[0] * 0.5, HUT[1] * 0.5, HUT[2]
    wood = pm.paint(RH["wood"], 2, "bark")
    planks = pm.paint(RH["wood"], 2, "planks")
    iron = pm.paint(RB["iron"], 1)
    stone = pm.paint(RH["granite"], 3)
    for sx in (-1, 1):
        for sy in (-1, 1):
            pm.box(None, (0.26, 0.26, h - 0.02), (sx * w, sy * d, h * 0.5), paint=wood)      # corner posts
    for sy in (-1, 1):
        pm.box(None, (HUT[0], 0.14, 0.2), (0, sy * (d + 0.07), h - 0.12), paint=wood)          # wall plates
    for sx in (-1, 1):
        pm.box(None, (0.14, HUT[1], 0.2), (sx * (w + 0.07), 0, h - 0.12), paint=wood)
    # door (front, -Y): plank leaf, iron bands + ring, granite jambs, rune lintel
    pm.box(None, (1.1, 0.06, 1.92), (0, -d - 0.03, 0.96), paint=planks)
    for z in (0.42, 1.5):
        pm.box(None, (1.12, 0.07, 0.07), (0, -d - 0.045, z), paint=iron)
    pm.box(None, (0.09, 0.08, 0.09), (0.36, -d - 0.08, 0.98), paint=iron)
    for sx in (-1, 1):
        pm.box(None, (0.18, 0.16, 2.02), (sx * 0.64, -d - 0.05, 1.01), paint=stone)
    pm.box(None, (1.56, 0.2, 0.3), (0, -d - 0.07, 2.17), paint=stone)
    pm.box(None, (0.62, 0.02, 0.09), (0, -d - 0.175, 2.17), mat_index=GLOW)                   # rune inlay
    # windows: granite sill + lintel, lit pane, open shutters (sides + back)
    for face in ((w, 0.55, 1, 0), (-w, -0.55, -1, 0), (1.25, d, 0, 1)):
        _face_box(pm, face, 0.0, 0.05, 0.8, 0.12, 1.22, 0.08, paint=stone)
        _face_box(pm, face, 0.0, 0.05, 0.8, 0.12, 1.93, 0.1, paint=stone)
        _face_box(pm, face, 0.0, 0.015, 0.52, 0.03, 1.57, 0.62, mat_index=GLOW_B)            # lit pane
        _face_box(pm, face, 0.0, 0.03, 0.06, 0.05, 1.57, 0.64, paint=wood)                   # mullion
        for side in (-1, 1):
            _face_box(pm, face, side * 0.46, 0.04, 0.3, 0.05, 1.57, 0.64, paint=planks)       # shutters
    finish(pm, "rh_hut_trim", kit="runehold", sizes=(64, 128, 256, 512), axis_aligned=True,
           glows={GLOW: ("rune", ROLES["player_accent"]["body"], 0.8),
                  GLOW_B: ("window", ROLES["hearth"]["body"], 0.8)})


def rh_wall_banner():
    """Runebreaker banner for a wall face: origin = pole centre, cloth hangs to
    -Z facing -Y; brackets hold it 0.1 m off the wall (+Y) so the sway never
    clips into the masonry."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    wood = pm.paint(RH["wood"], 2, "bark")
    iron = pm.paint(RB["iron"], 2)
    teal = pm.paint(RB["teal_cloth"], 2, "cloth")
    teal_dark = pm.paint(RB["teal_cloth"], 1)
    gold = pm.paint(RB["gold_trim"], 3)
    pm.loft(None, [(-0.62, 0.035, 0.035, 0, 0), (0.62, 0.035, 0.035, 0, 0)], sides=6, rot=(0, math.pi / 2, 0), paint=wood)
    for sx in (-1, 1):
        pm.box(None, (0.07, 0.07, 0.07), (sx * 0.65, 0, 0), paint=iron)                     # finials
        pm.box(None, (0.05, 0.12, 0.05), (sx * 0.4, 0.07, 0), paint=iron)                    # wall brackets
    pm.box(None, (0.9, 0.03, 1.45), (0, -0.02, -0.76), paint=teal, mat_index=CLOTH)
    for sx in (-1, 1):
        pm.box(None, (0.4, 0.03, 0.3), (sx * 0.25, -0.02, -1.62), paint=teal, mat_index=CLOTH)  # swallowtail
    for z in (-0.12, -1.38):
        pm.box(None, (0.9, 0.035, 0.06), (0, -0.024, z), paint=gold, mat_index=CLOTH)
    pm.box(None, (0.3, 0.035, 0.3), (0, -0.026, -0.72), rot=(0, math.pi / 4, 0), paint=gold, mat_index=CLOTH)
    pm.box(None, (0.14, 0.04, 0.14), (0, -0.03, -0.72), rot=(0, math.pi / 4, 0), paint=teal_dark, mat_index=CLOTH)
    finish(pm, "rh_wall_banner", cloth=True, kit="runehold", axis_aligned=True)


def rh_pine():
    rig.reset_scene()
    rnd = random.Random(53)
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    bark = pm.paint(RH["bark"], 2, "bark")
    needles = pm.paint(RH["canopy"], 2, "hide")
    pm.loft(None, [(-0.1, 0.22, 0.21, 0, 0), (0.7, 0.16, 0.16, 0, 0), (3.0, 0.1, 0.1, 0, 0), (5.1, 0.04, 0.04, 0, 0)],
            sides=6, paint=bark)
    for z, r, hgt in ((1.0, 1.55, 1.75), (1.95, 1.28, 1.55), (2.85, 1.0, 1.4), (3.7, 0.7, 1.25), (4.45, 0.42, 1.05)):
        ph = rnd.uniform(0.0, 1.0)
        lean = (rnd.uniform(-0.06, 0.06), rnd.uniform(-0.06, 0.06))
        pm.loft(None, [(z, r * 0.5, r * 0.48, 0, 0), (z + 0.14, r, r * 0.94, 0, 0), (z + 0.4, r * 0.84, r * 0.8, lean[0], lean[1]),
                       (z + hgt, 0.03, 0.03, lean[0] * 2, lean[1] * 2)], sides=8, phase=ph, paint=needles)
    finish(pm, "rh_pine", kit="runehold", sizes=(64, 128, 256, 512))


def rh_oak():
    rig.reset_scene()
    rnd = random.Random(61)
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    bark = pm.paint(RH["bark"], 2, "bark")
    leaves = pm.paint(RH["canopy"], 3, "hide")
    pm.loft(None, [(-0.1, 0.34, 0.32, 0, 0), (0.4, 0.25, 0.24, 0, 0), (1.6, 0.19, 0.18, 0.06, 0), (2.5, 0.14, 0.13, 0.1, 0.04)],
            sides=7, paint=bark)
    for a, tilt in ((0.4, 0.8), (2.5, 0.9), (4.3, 0.75)):
        pm.loft(None, [(0.0, 0.09, 0.09, 0, 0), (1.1, 0.04, 0.04, 0, 0)], sides=5, center=(0, 0, 1.9),
                rot=(tilt, 0, a), paint=bark)
    for cx, cy, cz, r in ((0.1, 0.0, 3.35, 1.45), (0.95, 0.35, 2.95, 1.0), (-0.85, -0.3, 3.0, 1.05),
                          (0.15, -0.75, 3.95, 0.85), (-0.3, 0.7, 3.85, 0.8)):
        ph = rnd.uniform(0.0, 1.0)
        pm.loft(None, [(cz - r * 0.78, r * 0.45, r * 0.42, cx, cy), (cz - r * 0.38, r * 0.92, r * 0.88, cx, cy),
                       (cz + r * 0.05, r, r * 0.96, cx, cy), (cz + r * 0.45, r * 0.8, r * 0.76, cx, cy),
                       (cz + r * 0.8, r * 0.38, r * 0.36, cx, cy)], sides=8, phase=ph, paint=leaves)
    finish(pm, "rh_oak", kit="runehold", sizes=(64, 128, 256, 512))


def _tongues(spec):
    def build(fpm, k):
        for cx, cy, h, r, ph in spec:
            fpm.loft(None, [(0.12, r, r * 0.9, cx, cy), (0.12 + h * 0.4, r * 0.8, r * 0.75, cx * 1.1, cy * 1.1),
                            (0.12 + h, 0.02, 0.02, cx * 0.4, cy * 0.4)], sides=5, phase=ph, mat_index=k)
    return build


def rh_hearth_fire():
    """Runehold hearth heart: crossed logs over an ember bed (atlas mesh) plus a
    separate `flames` object Godot flickers by node name."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    wood = pm.paint(RH["wood"], 1, "bark")
    char = pm.paint(HL["basalt"], 1)
    for yaw, z, ln, r in ((30, 0.1, 1.0, 0.11), (-40, 0.27, 0.9, 0.1), (78, 0.18, 0.84, 0.09)):
        pm.loft(None, [(-ln * 0.5, r, r * 0.95, 0, 0), (ln * 0.5, r * 0.9, r * 0.85, 0, 0)], sides=6,
                center=(0, 0, z), rot=(0, math.pi / 2, math.radians(yaw)), paint=wood)
    pm.loft(None, [(-0.02, 0.5, 0.5, 0, 0), (0.03, 0.46, 0.46, 0, 0)], sides=9, paint=char)
    pm.loft(None, [(0.03, 0.4, 0.4, 0, 0), (0.05, 0.34, 0.34, 0, 0)], sides=9, mat_index=GLOW)   # ember bed
    glow_object("flames", [
        (ROLES["fire"]["body"], 1.0, _tongues(((0.0, 0.05, 1.05, 0.2, 0.2), (0.16, -0.12, 0.8, 0.15, 0.9),
                                                (-0.15, -0.08, 0.72, 0.14, 0.5), (-0.05, 0.2, 0.6, 0.12, 0.1)))),
        (ROLES["fire"]["core"], 1.0, _tongues(((0.03, -0.12, 0.62, 0.12, 0.3), (-0.07, 0.02, 0.5, 0.1, 0.7)))),
    ])
    finish(pm, "rh_hearth_fire", ROLES["fire"]["edge"], 0.8, kit="runehold")


def rh_hearth_stone():
    """Wraps one 0.35 x 0.3 x 0.35 hearth-ring collider (origin at its base)."""
    rig.reset_scene()
    rnd = random.Random(67)
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    stone = pm.paint(RH["granite"], 2)
    top = pm.paint(RH["granite"], 3)
    pm.loft(None, [(-0.02, 0.29, 0.28, 0, 0), (0.22, 0.3, 0.29, 0, 0), (0.33, 0.25, 0.24, 0, 0)],
            sides=6, phase=rnd.uniform(0, 1), paint=stone)
    pm.loft(None, [(0.33, 0.25, 0.24, 0, 0), (0.38, 0.16, 0.15, 0, 0)], sides=6, paint=top)
    finish(pm, "rh_hearth_stone", kit="runehold")


def rh_grass_tuft():
    """Scatter item: living grass (fuller and taller than ash tufts), cloth."""
    rig.reset_scene()
    rnd = random.Random(71)
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    grass = pm.paint(RH["turf"], 2)
    tip = pm.paint(RH["turf"], 3)
    for k in range(10):
        a = k * math.tau / 10 + rnd.uniform(-0.3, 0.3)
        h = rnd.uniform(0.2, 0.38)
        lean = rnd.uniform(0.04, 0.12)
        r0 = rnd.uniform(0.0, 0.06)
        cx, cy = math.cos(a) * r0, math.sin(a) * r0
        pm.loft(None, [(0.0, 0.018, 0.011, cx, cy), (h, 0.002, 0.002, cx + math.cos(a) * lean, cy + math.sin(a) * lean)],
                sides=3, phase=a, paint=tip if k % 4 == 0 else grass, mat_index=CLOTH)
    finish(pm, "rh_grass_tuft", cloth=True, kit="runehold")


def rh_stone_cluster():
    """Scatter item: granite stones with moss on top."""
    rig.reset_scene()
    rnd = random.Random(73)
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    stone = pm.paint(RH["granite"], 2)
    moss = pm.paint(RH["moss"], 2)
    for k in range(3):
        a = k * math.tau / 3 + rnd.uniform(-0.4, 0.4)
        r = 0.0 if k == 0 else rnd.uniform(0.12, 0.2)
        s = rnd.uniform(0.06, 0.1) * (1.4 if k == 0 else 1.0)
        cx, cy = math.cos(a) * r, math.sin(a) * r
        pm.loft(None, [(-0.02, s, s * 0.85, cx, cy), (s * 0.8, s * 0.8, s * 0.7, cx, cy), (s * 1.2, s * 0.35, s * 0.3, cx, cy)],
                sides=5, phase=rnd.uniform(0, 1), paint=stone)
        pm.loft(None, [(s * 1.15, s * 0.37, s * 0.32, cx, cy), (s * 1.26, s * 0.15, s * 0.12, cx, cy)], sides=5, paint=moss)
    finish(pm, "rh_stone_cluster", kit="runehold")


def rh_weapon_rack():
    """Wall-hugging training rack (0.26 m deep: the 0.42 m player capsule can
    never walk into it): posts, two rails, practice swords, a round shield."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    wood = pm.paint(RH["wood"], 2, "bark")
    steel = pm.paint(RB["steel"], 2)
    teal = pm.paint(RB["teal_cloth"], 2)
    iron = pm.paint(RB["iron"], 2)
    for sx in (-1, 1):
        pm.box(None, (0.1, 0.1, 1.45), (sx * 0.75, 0.07, 0.72), paint=wood)
    for z in (0.35, 1.2):
        pm.box(None, (1.6, 0.08, 0.08), (0, 0.07, z), paint=wood)
    for k, x in enumerate((-0.5, -0.25, 0.0)):
        tilt = 0.08 * (k - 1)
        pm.box(None, (0.07, 0.025, 1.0), (x, -0.02, 0.78), rot=(0, tilt, 0), paint=steel)       # blade
        pm.box(None, (0.2, 0.05, 0.04), (x + 0.02, -0.02, 1.3), rot=(0, tilt, 0), paint=iron)   # guard
        pm.box(None, (0.04, 0.04, 0.2), (x + 0.03, -0.02, 1.42), rot=(0, tilt, 0), paint=wood)  # grip
    pm.loft(None, [(-0.03, 0.34, 0.34, 0, 0), (0.03, 0.34, 0.34, 0, 0)], sides=10, center=(0.42, -0.04, 0.78),
            rot=(math.pi / 2, 0, 0), paint=teal)
    pm.loft(None, [(-0.045, 0.09, 0.09, 0, 0), (0.045, 0.09, 0.09, 0, 0)], sides=8, center=(0.42, -0.06, 0.78),
            rot=(math.pi / 2, 0, 0), paint=iron)
    finish(pm, "rh_weapon_rack", kit="runehold", axis_aligned=True)


def rh_training_post():
    """Wall-hugging pell: a scarred post with a straw-wrapped band (0.28 deep)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    wood = pm.paint(RH["wood"], 2, "bark")
    straw = pm.paint(HL["dead_grass"], 2, "cloth")
    pm.box(None, (0.26, 0.26, 1.7), (0, 0, 0.85), paint=wood)
    pm.box(None, (0.3, 0.28, 0.5), (0, -0.01, 1.05), paint=straw)
    pm.box(None, (0.7, 0.1, 0.1), (0, -0.05, 1.45), paint=wood)
    finish(pm, "rh_training_post", kit="runehold", axis_aligned=True)


# ---------------------------------------------------------------------------
# Spire kit (interior): violet stone, lavender crystal, teal ancient runes.
# Walls, floor and blocks are world-mapped terrain roles built in code; these
# props wrap colliders, hug walls (<= 0.3 m) or float above head height.
# ---------------------------------------------------------------------------

SP = SPEC["palettes"]["spire"]


def _crystal(pm, paint, center, r, h, tilt=(0.0, 0.0), sides=6, phase=None):
    """Faceted crystal: flared base, long prism, pointed tip (local Z up)."""
    cx, cy, cz = center
    pm.loft(None, [(0.0, r * 0.8, r * 0.8, 0, 0), (h * 0.12, r, r, 0, 0), (h * 0.72, r * 0.9, r * 0.9, 0, 0),
                   (h, 0.02, 0.02, 0, 0)], sides=sides, center=(cx, cy, cz), rot=(tilt[0], tilt[1], 0.0),
            phase=phase, paint=paint)


def sp_crystal_pillar():
    """Wraps a 1.2 x 4 x 1.2 accent collider: a hex crystal (apothem >= 0.85,
    contains the box at any yaw) on a broken stone plinth, satellite crystals
    and a faint core glow line."""
    rig.reset_scene()
    rnd = random.Random(83)
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    stone = pm.paint(SP["wall"], 3)
    crystal = pm.paint(SP["crystal"], 2)
    crystal_hi = pm.paint(SP["crystal"], 3)
    pm.loft(None, [(-0.05, 1.12, 1.12, 0, 0), (0.35, 1.08, 1.08, 0, 0), (0.45, 1.0, 1.0, 0, 0)], sides=8, paint=stone)
    pm.loft(None, [(0.4, 0.99, 0.99, 0, 0), (0.6, 1.0, 1.0, 0, 0), (3.2, 0.99, 0.99, 0, 0), (4.1, 0.55, 0.55, 0, 0),
                   (4.45, 0.02, 0.02, 0, 0)], sides=6, paint=crystal)
    for k in range(4):
        a = k * math.tau / 4 + rnd.uniform(-0.3, 0.3)
        _crystal(pm, crystal_hi if k % 2 else crystal, (math.cos(a) * 0.95, math.sin(a) * 0.95, 0.35),
                 rnd.uniform(0.18, 0.28), rnd.uniform(0.9, 1.6), tilt=(math.cos(a) * 0.45, -math.sin(a) * 0.45))
    for z0, z1 in ((0.9, 1.9), (2.2, 3.0)):
        pm.box(None, (0.06, 0.03, z1 - z0), (0.0, -0.87, (z0 + z1) * 0.5), mat_index=GLOW)
    finish(pm, "sp_crystal_pillar", SPEC["palettes"]["spire"]["rune"], 0.8, kit="spire", sizes=(64, 128, 256, 512))


def sp_wall_arch():
    """Relief arch for a wall face (0.28 m deep, front -Y): two pilasters, a
    broken round arch with a rune keystone. 3.6 m wide, 5.6 m tall."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    stone = pm.paint(SP["wall"], 3, "masonry")
    trim = pm.paint(SP["wall"], 4)
    for sx in (-1, 1):
        pm.box(None, (0.5, 0.26, 4.2), (sx * 1.55, -0.13, 2.1), paint=stone)             # pilasters
        pm.box(None, (0.64, 0.3, 0.22), (sx * 1.55, -0.15, 4.25), paint=trim)            # capitals
        pm.box(None, (0.64, 0.3, 0.2), (sx * 1.55, -0.15, 0.1), paint=trim)              # bases
    segs = 9
    for k in range(segs):
        if k in (5, 6):
            continue  # the break
        a0 = math.pi * k / segs
        a1 = math.pi * (k + 1) / segs
        am = (a0 + a1) * 0.5
        r = 1.55
        cx, cz = math.cos(am) * r, 4.36 + math.sin(am) * r * 0.8
        pm.box(None, (0.56, 0.26, 0.4), (cx, -0.13, cz), rot=(0.0, -(am - math.pi / 2), 0.0), paint=stone)
    pm.box(None, (0.3, 0.3, 0.44), (0.0, -0.15, 4.36 + 1.55 * 0.8 + 0.05), paint=trim)   # keystone
    pm.box(None, (0.12, 0.02, 0.22), (0.0, -0.305, 4.36 + 1.55 * 0.8 + 0.05), mat_index=GLOW)
    finish(pm, "sp_wall_arch", SPEC["palettes"]["spire"]["rune"], 0.8, kit="spire", sizes=(64, 128, 256, 512),
           axis_aligned=True)


def sp_beacon():
    """Torch v2: a crystal floating above head height (origin = its centre),
    plus an `orbit` object of three small shards Godot spins by node name."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    crystal = pm.paint(SP["crystal"], 3)
    pm.loft(None, [(-0.42, 0.02, 0.02, 0, 0), (-0.1, 0.16, 0.16, 0, 0), (0.12, 0.16, 0.16, 0, 0), (0.46, 0.02, 0.02, 0, 0)],
            sides=5, paint=crystal)
    pm.loft(None, [(-0.2, 0.02, 0.02, 0, 0), (0.0, 0.09, 0.09, 0, 0), (0.22, 0.02, 0.02, 0, 0)], sides=5,
            center=(0, -0.13, 0), mat_index=GLOW)                                           # lit core facet

    def shards(fpm, k):
        for j in range(3):
            a = j * math.tau / 3
            fpm.loft(None, [(-0.1, 0.02, 0.02, 0, 0), (0.0, 0.05, 0.05, 0, 0), (0.12, 0.02, 0.02, 0, 0)], sides=4,
                     center=(math.cos(a) * 0.42, math.sin(a) * 0.42, 0.05 * (j - 1)), rot=(0.3, 0.2 * j, 0), mat_index=k)
    glow_object("orbit", [(SPEC["palettes"]["spire"]["crystal"][4], 0.8, shards)])
    finish(pm, "sp_beacon", SPEC["palettes"]["spire"]["rune"], 1.0, kit="spire")


def sp_shard():
    """Floating debris shard (decor above head height, origin = centre)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    crystal = pm.paint(SP["crystal"], 2)
    stone = pm.paint(SP["wall"], 3)
    pm.loft(None, [(-0.5, 0.03, 0.03, 0, 0), (-0.05, 0.2, 0.17, 0, 0), (0.3, 0.14, 0.12, 0.03, 0), (0.7, 0.02, 0.02, 0.06, 0)],
            sides=5, paint=crystal)
    pm.loft(None, [(-0.62, 0.14, 0.12, 0, 0), (-0.42, 0.2, 0.18, 0, 0), (-0.3, 0.12, 0.1, 0, 0)], sides=5, paint=stone)
    finish(pm, "sp_shard", kit="spire")


def sp_crystal_cluster():
    """Scatter item: small crystals growing at wall and block bases (<= 0.3 m)."""
    rig.reset_scene()
    rnd = random.Random(89)
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    crystal = pm.paint(SP["crystal"], 2)
    crystal_hi = pm.paint(SP["crystal"], 3)
    for k in range(4):
        a = k * math.tau / 4 + rnd.uniform(-0.4, 0.4)
        r = 0.0 if k == 0 else rnd.uniform(0.07, 0.14)
        _crystal(pm, crystal_hi if k == 0 else crystal, (math.cos(a) * r, math.sin(a) * r, -0.02),
                 rnd.uniform(0.03, 0.05), rnd.uniform(0.14, 0.3), tilt=(math.cos(a) * 0.4, -math.sin(a) * 0.4), sides=5)
    finish(pm, "sp_crystal_cluster", kit="spire")


def sp_rubble():
    """Scatter item: broken masonry chunks (<= 0.2 m)."""
    rig.reset_scene()
    rnd = random.Random(97)
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    stone = pm.paint(SP["wall"], 3)
    top = pm.paint(SP["wall"], 4)
    for k in range(4):
        a = k * math.tau / 4 + rnd.uniform(-0.5, 0.5)
        r = 0.0 if k == 0 else rnd.uniform(0.1, 0.22)
        s = rnd.uniform(0.05, 0.09) * (1.5 if k == 0 else 1.0)
        pm.box(None, (s * 2, s * 1.6, s * 1.2), (math.cos(a) * r, math.sin(a) * r, s * 0.55),
               rot=(rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3), rnd.uniform(0, math.pi)), paint=stone if k else top)
    finish(pm, "sp_rubble", kit="spire")


# ---------------------------------------------------------------------------
# Common kit (every zone): portal frame + plate, treasure chest, loot shapes.
# ---------------------------------------------------------------------------

PORTAL_A, PORTAL_B, PORTAL_Y = 1.25, 1.55, 1.45   # gate ellipse half-sizes + centre height


def portal_arch():
    """Floating stones on the gate's upper arc (all >= 2.2 m: never in the
    walk space, sealed portals included), a rune keystone. Front/back
    symmetric (the gate faces +-Y)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    stone = pm.paint(RH["granite"], 3)
    stone_hi = pm.paint(RH["granite"], 4)
    for k, deg in enumerate((32, 58, 90, 122, 148)):
        t = math.radians(deg)
        x = math.cos(t) * (PORTAL_A + 0.18)
        z = PORTAL_Y + math.sin(t) * (PORTAL_B + 0.18)
        w = 0.46 if deg == 90 else 0.36
        pm.box(None, (w, 0.34, 0.32), (x, 0.0, z), rot=(0.0, -(t - math.pi / 2), 0.0),
               paint=stone_hi if deg == 90 else stone)
    pm.box(None, (0.16, 0.36, 0.2), (0.0, 0.0, PORTAL_Y + PORTAL_B + 0.18), mat_index=GLOW)      # keystone rune
    finish(pm, "portal_arch", ROLES["player_accent"]["body"], 0.8, kit="common", axis_aligned=True)


def portal_plate():
    """Flush octagonal rune plate under the gate (0.02 m: walkable floor
    stays flat); the inlay is lines only (rings belong to player VFX)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    stone = pm.paint(RH["flagstone"], 2)
    pm.loft(None, [(0.0, 1.35, 1.35, 0, 0), (0.02, 1.33, 1.33, 0, 0)], sides=8, phase=math.pi / 8, paint=stone)
    for k in range(8):
        a0 = k * math.tau / 8 + math.pi / 8
        a1 = a0 + math.tau / 8
        r = 1.08
        x0, y0, x1, y1 = math.cos(a0) * r, math.sin(a0) * r, math.cos(a1) * r, math.sin(a1) * r
        ln = math.hypot(x1 - x0, y1 - y0)
        pm.box(None, (ln, 0.05, 0.012), ((x0 + x1) / 2, (y0 + y1) / 2, 0.021),
               rot=(0, 0, math.atan2(y1 - y0, x1 - x0)), mat_index=GLOW)
    for k in range(4):
        a = k * math.pi / 2 + math.pi / 4
        pm.box(None, (0.62, 0.05, 0.012), (math.cos(a) * 0.62, math.sin(a) * 0.62, 0.021), rot=(0, 0, a), mat_index=GLOW)
    finish(pm, "portal_plate", ROLES["player_accent"]["body"], 0.8, kit="common")


def treasure_chest():
    """Wraps the chest collider (1.0 x 0.65 footprint, 0.8 tall): banded
    body with a rune lock; the lid is its own object (`lid`, hinged at the
    back edge: origin on the hinge) so Godot can swing it open."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    wood = pm.paint(RH["wood"], 2, "planks")
    iron = pm.paint(RB["iron"], 2)
    gold = pm.paint(RB["gold_trim"], 2)
    pm.box(None, (1.04, 0.69, 0.56), (0, 0, 0.28), paint=wood)
    for x in (-0.36, 0.36):
        pm.box(None, (0.08, 0.72, 0.58), (x, 0, 0.29), paint=iron)
    pm.box(None, (1.06, 0.71, 0.06), (0, 0, 0.03), paint=iron)
    pm.box(None, (0.2, 0.05, 0.2), (0, -0.36, 0.46), paint=gold)                                     # lock plate
    pm.box(None, (0.08, 0.02, 0.1), (0, -0.39, 0.46), mat_index=GLOW)                                 # rune lock
    lid_pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    lwood = lid_pm.paint(RH["wood"], 3, "planks")
    liron = lid_pm.paint(RB["iron"], 2)
    # lid geometry relative to the hinge at the back top edge (y +0.345, z 0.56)
    lid_pm.box(None, (1.04, 0.69, 0.2), (0, -0.345, 0.1), paint=lwood)
    for x in (-0.36, 0.36):
        lid_pm.box(None, (0.08, 0.72, 0.22), (x, -0.345, 0.1), paint=liron)
    lid_mat = rig.make_material("treasure_chest_lid", "#FFFFFF")
    lid = lid_pm.to_object("lid", [lid_mat], None)
    size = atlas.unwrap(lid, ENV_DENSITY, sizes=(32, 64, 128), axis_aligned=True)
    atlas.bake(lid, size, os.path.join(OUT_TEX, "treasure_chest_lid_atlas.png"), skip_material_indices=())
    lid.location = (0, 0.345, 0.56)
    finish(pm, "treasure_chest", SPEC["color_roles"]["resonance"]["body"], 0.8, kit="common", axis_aligned=True)


def _loot_finish(pm, name):
    finish(pm, name, "#FFFFFF", 1.0, kit="common")


def loot_blade():
    """Ground-drop shape for weapons (glow slot = rarity colour in Godot)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    steel = pm.paint(RB["steel"], 3)
    wood = pm.paint(RH["wood"], 2)
    pm.box(None, (0.07, 0.025, 0.46), (0, 0, 0.23), taper=0.3, paint=steel)
    pm.box(None, (0.22, 0.05, 0.04), (0, 0, -0.02), mat_index=GLOW)
    pm.box(None, (0.04, 0.04, 0.16), (0, 0, -0.12), paint=wood)
    _loot_finish(pm, "loot_blade")


def loot_armor():
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    iron = pm.paint(RB["iron"], 3, "plate")
    pm.loft(None, [(-0.16, 0.17, 0.1, 0, 0), (0.05, 0.2, 0.12, 0, 0), (0.16, 0.14, 0.09, 0, 0)], sides=6, paint=iron)
    for x in (-1, 1):
        pm.loft(None, [(0.08, 0.07, 0.07, 0.2 * x, 0), (0.17, 0.08, 0.08, 0.2 * x, 0), (0.22, 0.03, 0.03, 0.19 * x, 0)],
                sides=5, paint=iron)
    pm.box(None, (0.1, 0.02, 0.1), (0, -0.12, 0.02), mat_index=GLOW)
    _loot_finish(pm, "loot_armor")


def loot_relic():
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    gold = pm.paint(RB["gold_trim"], 2)
    pm.loft(None, [(-0.14, 0.02, 0.02, 0, 0), (0.0, 0.1, 0.1, 0, 0), (0.14, 0.02, 0.02, 0, 0)], sides=4, mat_index=GLOW)
    for k in range(3):
        a = k * math.tau / 3
        pm.box(None, (0.04, 0.03, 0.2), (math.cos(a) * 0.12, math.sin(a) * 0.12, 0), rot=(0, 0, a), paint=gold)
    _loot_finish(pm, "loot_relic")


def loot_helm():
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    iron = pm.paint(RB["iron"], 3, "plate")
    pm.loft(None, [(-0.1, 0.13, 0.14, 0, 0), (0.05, 0.14, 0.15, 0, 0), (0.14, 0.1, 0.11, 0, 0), (0.18, 0.03, 0.03, 0, 0)],
            sides=8, paint=iron)
    pm.box(None, (0.16, 0.02, 0.03), (0, -0.14, 0.0), mat_index=GLOW)                          # visor slit
    _loot_finish(pm, "loot_helm")


def loot_gloves():
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    iron = pm.paint(RB["iron"], 3, "plate")
    pm.box(None, (0.13, 0.08, 0.14), (0, 0, -0.04), paint=iron)
    for k in range(4):
        pm.box(None, (0.025, 0.05, 0.1), (-0.045 + k * 0.03, 0, 0.08), paint=iron)
    pm.box(None, (0.14, 0.09, 0.02), (0, 0, -0.1), mat_index=GLOW)                             # cuff band
    _loot_finish(pm, "loot_gloves")


def loot_boots():
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    iron = pm.paint(RB["iron"], 3, "plate")
    pm.box(None, (0.09, 0.1, 0.22), (0, 0.02, 0.0), paint=iron)
    pm.box(None, (0.1, 0.2, 0.07), (0, -0.05, -0.1), paint=iron)
    pm.box(None, (0.1, 0.11, 0.02), (0, 0.02, 0.1), mat_index=GLOW)                            # cuff band
    _loot_finish(pm, "loot_boots")


def loot_ring():
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    gold = pm.paint(RB["gold_trim"], 3)
    for k in range(8):
        a = k * math.tau / 8
        pm.box(None, (0.05, 0.03, 0.03), (math.cos(a) * 0.09, 0, math.sin(a) * 0.09), rot=(0, -a, 0), paint=gold)
    pm.loft(None, [(0.08, 0.01, 0.01, 0, 0), (0.12, 0.04, 0.04, 0, 0), (0.16, 0.01, 0.01, 0, 0)], sides=4, mat_index=GLOW)
    _loot_finish(pm, "loot_ring")


def legendary_cindermaw():
    """Cindermaw: a hooked, notched blade with a molten edge (legendary drop)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    char = pm.paint(HL["basalt"], 2)
    gold = pm.paint(RB["gold_trim"], 3)
    pm.box(None, (0.1, 0.03, 0.5), (0, 0, 0.26), taper=0.45, paint=char)
    pm.box(None, (0.03, 0.035, 0.46), (0.045, 0, 0.25), taper=0.4, mat_index=GLOW)                  # molten edge
    pm.box(None, (0.08, 0.03, 0.12), (-0.07, 0, 0.44), rot=(0, 0.5, 0), paint=char)                 # hook
    pm.box(None, (0.26, 0.06, 0.05), (0, 0, -0.02), paint=gold)
    pm.box(None, (0.045, 0.045, 0.16), (0, 0, -0.12), paint=char)
    finish(pm, "legendary_cindermaw", ROLES["fire"]["body"], 1.0, kit="common")


def legendary_conductors_oath():
    """Conductor's Oath: a caged storm core with three prongs (relic)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    iron = pm.paint(RB["iron"], 3)
    pm.loft(None, [(-0.12, 0.02, 0.02, 0, 0), (0.0, 0.09, 0.09, 0, 0), (0.12, 0.02, 0.02, 0, 0)], sides=5, mat_index=GLOW)
    for k in range(3):
        a = k * math.tau / 3
        pm.loft(None, [(-0.18, 0.015, 0.015, math.cos(a) * 0.1, math.sin(a) * 0.1),
                       (0.0, 0.02, 0.02, math.cos(a) * 0.15, math.sin(a) * 0.15),
                       (0.2, 0.004, 0.004, math.cos(a) * 0.05, math.sin(a) * 0.05)], sides=4, paint=iron)
    finish(pm, "legendary_conductors_oath", ROLES["lightning"]["body"], 1.0, kit="common")


def legendary_glacier_heart():
    """Glacier Heart: a breastplate with a frost crystal heart (armor)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    steel = pm.paint(RB["steel"], 3, "plate")
    pm.loft(None, [(-0.16, 0.17, 0.1, 0, 0), (0.05, 0.2, 0.12, 0, 0), (0.16, 0.14, 0.09, 0, 0)], sides=6, paint=steel)
    pm.loft(None, [(-0.1, 0.02, 0.02, 0, -0.12), (0.0, 0.07, 0.05, 0, -0.13), (0.14, 0.01, 0.01, 0, -0.12)],
            sides=4, mat_index=GLOW)
    for x in (-1, 1):
        pm.loft(None, [(0.1, 0.03, 0.03, 0.14 * x, -0.06), (0.26, 0.004, 0.004, 0.2 * x, -0.04)], sides=4, mat_index=GLOW)
    finish(pm, "legendary_glacier_heart", ROLES["frost"]["body"], 1.0, kit="common")


def waypoint_shrine():
    """M08 waypoint shrine: stepped basalt plinth, a rune pillar with carved
    channels and a crystal brazier (glow) on top. Wraps a 1.2 x 2.2 x 1.2
    collider (the plinth steps are wider but only 0.4 m tall: walk-through)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    stone = pm.paint(HL["basalt"], 2, "plate")
    dark = pm.paint(HL["basalt"], 1)
    top = pm.paint(HL["ash_top"], 2)
    pm.box(None, (1.6, 1.6, 0.22), (0, 0, 0.01), paint=stone)
    pm.box(None, (1.26, 1.26, 0.2), (0, 0, 0.22), paint=dark)
    pm.box(None, (0.64, 0.64, 1.2), (0, 0, 0.92), paint=stone)
    pm.box(None, (0.74, 0.74, 0.14), (0, 0, 1.59), paint=top)
    pm.box(None, (0.5, 0.5, 0.16), (0, 0, 1.74), paint=dark)
    # carved rune channels on all four faces
    for (cx, cy, sx, sy) in ((0, -0.33, 0.07, 0.03), (0, 0.33, 0.07, 0.03), (-0.33, 0, 0.03, 0.07), (0.33, 0, 0.03, 0.07)):
        pm.box(None, (sx, sy, 0.7), (cx, cy, 0.95), mat_index=GLOW)
        pm.box(None, (sx * 3.0, sy * 3.0 if sy > sx else sy, 0.05), (cx, cy, 1.36), mat_index=GLOW)
    # crystal brazier: a cluster of shards standing in the top bowl
    for (dx, dy, h, rz) in ((0, 0, 0.55, 0.0), (0.11, 0.06, 0.38, 0.5), (-0.1, 0.08, 0.32, -0.6), (0.02, -0.12, 0.42, 0.3)):
        pm.box(None, (0.12, 0.12, h), (dx, dy, 1.82 + h * 0.5), rot=(0.0, 0.0, rz), mat_index=GLOW, taper=0.35)
    finish(pm, "waypoint_shrine", ROLES["player_accent"]["body"], 0.9, kit="common")


# ---------------------------------------------------------------------------
# M12 Highlands sub-biomes: the abandoned village (vl_*), the burnt forest
# (bf_*), the bone field (bn_*) and the places that tell a story (vg_*). All
# in the highlands kit; anything over 0.4 m gets a collider in the zone
# (PoiBuilder.blocker), the ribs and the skull stand on their own colliders.
# ---------------------------------------------------------------------------

VL = SPEC["palettes"]["village"]
BF = SPEC["palettes"]["burnt_forest"]
BN = SPEC["palettes"]["bone_field"]


def _beam(pm, a, b, w, paint, h=None):
    """A square beam from point a to point b (metres, Z up)."""
    dx, dy, dz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    length = math.sqrt(dx * dx + dy * dy + dz * dz)
    pitch = math.asin(max(-1.0, min(1.0, dz / max(length, 1e-6))))
    yaw = math.atan2(-dx, dy)
    centre = ((a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5, (a[2] + b[2]) * 0.5)
    pm.box(None, (w, length, h if h is not None else w), centre, rot=(pitch, 0.0, yaw), paint=paint)


def vl_rafters():
    """Charred roof timbers of a ruined village house: a sagging ridge beam
    and rafter pairs, some broken, on top of 2.4 m walls (5 x 4.4 m)."""
    rig.reset_scene()
    rnd = random.Random(101)
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    timber = pm.paint(VL["timber"], 1, "bark")
    burnt = pm.paint(BF["bark"], 2, "bark")
    _beam(pm, (-2.6, 0.0, 3.5), (2.6, 0.0, 3.3), 0.2, timber)
    for k, x in enumerate((-2.2, -0.75, 0.75, 2.2)):
        for side in (-1, 1):
            if (k, side) in ((1, 1), (3, -1)):
                # broken rafter: only the lower stub, hanging a little
                _beam(pm, (x, side * 2.25, 2.4), (x + 0.1, side * 1.3, 2.75), 0.13, burnt)
                continue
            _beam(pm, (x + rnd.uniform(-0.05, 0.05), side * 2.25, 2.4), (x, 0.0, 3.45), 0.14,
                  burnt if rnd.random() < 0.5 else timber)
    for side in (-1, 1):
        _beam(pm, (-2.6, side * 2.2, 2.42), (2.6, side * 2.2, 2.42), 0.18, timber)  # wall plates
    finish(pm, "vl_rafters")


def vl_fence():
    """A broken farm fence, 2.4 m: three posts (one leaning), two rails, one
    rail hanging off. 0.95 m tall (collider in the zone)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    wood = pm.paint(VL["timber"], 2, "planks")
    dark = pm.paint(VL["timber"], 1, "bark")
    for x, tilt in ((-1.15, 0.0), (0.0, 0.12), (1.15, -0.05)):
        pm.box(None, (0.12, 0.12, 0.95), (x, 0.0, 0.47), rot=(0.0, tilt, 0.0), paint=dark, taper=0.85)
    _beam(pm, (-1.2, -0.08, 0.72), (1.2, -0.08, 0.7), 0.07, wood, h=0.12)
    _beam(pm, (-1.2, -0.08, 0.35), (0.1, -0.08, 0.36), 0.07, wood, h=0.12)
    _beam(pm, (0.1, -0.08, 0.36), (1.05, -0.12, 0.05), 0.07, wood, h=0.12)  # the fallen half
    finish(pm, "vl_fence")


def vl_well():
    """The village well: a fieldstone ring, a dark shaft, a timber frame with
    a crank and a bucket. 1.8 m tall (collider in the zone)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    stone = pm.paint(VL["cobble"], 2, "masonry")
    cap = pm.paint(VL["cobble"], 3)
    shaft = pm.paint(BF["bark"], 0)
    wood = pm.paint(VL["timber"], 2, "planks")
    iron = pm.paint(RB["iron"], 1)
    pm.loft(None, [(0.0, 0.85, 0.85, 0, 0), (0.62, 0.82, 0.82, 0, 0)], sides=10, paint=stone)
    pm.loft(None, [(0.62, 0.86, 0.86, 0, 0), (0.72, 0.84, 0.84, 0, 0)], sides=10, paint=cap)
    pm.loft(None, [(0.6, 0.62, 0.62, 0, 0), (0.74, 0.62, 0.62, 0, 0)], sides=10, paint=shaft)
    for x in (-0.78, 0.78):
        pm.box(None, (0.12, 0.12, 1.15), (x, 0.0, 1.25), paint=wood)
    _beam(pm, (-0.9, 0.0, 1.78), (0.9, 0.0, 1.78), 0.1, wood)
    pm.loft(None, [(-0.03, 0.09, 0.09, 0, 0), (0.03, 0.09, 0.09, 0, 0)], sides=8, center=(0.92, 0.0, 1.78),
            rot=(0.0, math.pi / 2, 0.0), paint=iron)
    pm.box(None, (0.03, 0.03, 0.55), (0.0, 0.0, 1.47), paint=iron)  # rope
    pm.loft(None, [(0.0, 0.13, 0.13, 0, 0), (0.22, 0.15, 0.15, 0, 0)], sides=8, center=(0.0, 0.0, 0.98), paint=wood)
    finish(pm, "vl_well")


def vl_grave():
    """A weathered headstone on a low mound, leaning (0.85 m)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    stone = pm.paint(VL["cobble"], 3, "plate")
    moss = pm.paint(VL["dead_grass"], 1)
    earth = pm.paint(VL["earth"], 2)
    pm.loft(None, [(0.0, 0.32, 0.75, 0, -0.45), (0.14, 0.25, 0.65, 0, -0.45), (0.2, 0.12, 0.4, 0, -0.45)],
            sides=8, paint=earth)
    pm.box(None, (0.55, 0.13, 0.78), (0.0, 0.0, 0.4), rot=(0.12, 0.05, 0.0), paint=stone)
    pm.loft(None, [(0.0, 0.27, 0.065, 0, 0), (0.12, 0.2, 0.065, 0, 0), (0.17, 0.08, 0.065, 0, 0)], sides=8,
            center=(0.0, 0.05, 0.78), rot=(0.12, 0.05, 0.0), paint=stone)
    pm.box(None, (0.5, 0.15, 0.12), (0.0, 0.02, 0.06), paint=moss)
    finish(pm, "vl_grave")


def vl_grave_cross():
    """A wooden grave marker: a cross of split planks on a mound (1.0 m)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    wood = pm.paint(VL["timber"], 2, "planks")
    earth = pm.paint(VL["earth"], 2)
    pm.loft(None, [(0.0, 0.3, 0.7, 0, -0.4), (0.15, 0.22, 0.6, 0, -0.4), (0.2, 0.1, 0.35, 0, -0.4)], sides=8, paint=earth)
    pm.box(None, (0.1, 0.07, 1.0), (0.0, 0.0, 0.5), rot=(0.0, -0.1, 0.0), paint=wood)
    pm.box(None, (0.52, 0.07, 0.1), (-0.05, -0.01, 0.75), rot=(0.0, 0.1, 0.0), paint=wood)
    finish(pm, "vl_grave_cross")


def vl_barricade():
    """Planks nailed across a cart wheel and barrels: the last barricade of
    the village, 2.6 m wide, 1.3 m tall (collider in the zone)."""
    rig.reset_scene()
    rnd = random.Random(113)
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    wood = pm.paint(VL["timber"], 2, "planks")
    dark = pm.paint(VL["timber"], 1, "planks")
    iron = pm.paint(RB["iron"], 1)
    for x in (-0.95, 0.95):
        pm.loft(None, [(0.0, 0.3, 0.3, 0, 0), (0.45, 0.35, 0.35, 0, 0), (0.9, 0.3, 0.3, 0, 0)], sides=8,
                center=(x, 0.1, 0.0), paint=dark)
        for z in (0.12, 0.78):
            pm.loft(None, [(-0.02, 0.32, 0.32, 0, 0), (0.02, 0.32, 0.32, 0, 0)], sides=8, center=(x, 0.1, z), paint=iron)
    for k in range(5):
        y = -0.25 + rnd.uniform(-0.04, 0.04)
        _beam(pm, (-1.35, y, 0.25 + k * 0.22 + rnd.uniform(-0.1, 0.1)), (1.35, y, 0.35 + k * 0.2 + rnd.uniform(-0.15, 0.15)),
              0.06, wood if k % 2 else dark, h=0.18)
    pm.loft(None, [(-0.04, 0.55, 0.55, 0, 0), (0.04, 0.55, 0.55, 0, 0)], sides=12, center=(0.15, -0.35, 0.62),
            rot=(math.pi / 2, 0.0, 0.1), paint=dark)  # cart wheel
    finish(pm, "vl_barricade")


def vl_cart():
    """An overturned hand cart with a broken wheel and spilt sacks (2.4 x
    1.3 m, 1.0 m tall; collider in the zone)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    wood = pm.paint(VL["timber"], 2, "planks")
    dark = pm.paint(VL["timber"], 1, "bark")
    sack = pm.paint(VL["thatch"], 2, "cloth")
    pm.box(None, (1.7, 1.1, 0.1), (0.0, 0.0, 0.5), rot=(1.25, 0.0, 0.0), paint=wood)          # bed on its side
    pm.box(None, (1.7, 0.08, 0.45), (0.0, -0.32, 0.25), paint=dark)                            # side board
    pm.box(None, (1.7, 0.08, 0.4), (0.0, 0.48, 0.85), rot=(1.25, 0.0, 0.0), paint=dark)
    _beam(pm, (0.85, 0.2, 0.15), (1.9, 0.45, 0.05), 0.08, dark)                                 # shafts
    _beam(pm, (0.85, -0.2, 0.25), (1.85, -0.6, 0.05), 0.08, dark)
    pm.loft(None, [(-0.04, 0.48, 0.48, 0, 0), (0.04, 0.48, 0.48, 0, 0)], sides=12, center=(-0.3, 0.62, 0.95),
            rot=(0.25, 0.0, 0.0), paint=dark)
    pm.loft(None, [(-0.04, 0.48, 0.48, 0, 0), (0.04, 0.48, 0.48, 0, 0)], sides=12, center=(-0.9, -1.0, 0.05),
            rot=(0.0, 0.0, 0.4), paint=dark)                                                    # the loose wheel
    for (x, y, r) in ((0.3, -0.85, 0.24), (0.75, -0.7, 0.2), (-0.2, -0.75, 0.18)):
        pm.loft(None, [(0.0, r, r * 0.8, 0, 0), (r * 0.9, r * 1.05, r * 0.85, 0, 0), (r * 1.4, r * 0.4, r * 0.35, 0, 0)],
                sides=7, center=(x, y, 0.0), paint=sack)
    finish(pm, "vl_cart")


def bf_snag():
    """A tall dead trunk of the burnt forest: thick, its top snapped off,
    two stub branches, dim ember cracks low on the bark (4.6 m)."""
    rig.reset_scene()
    rnd = random.Random(131)
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    bark = pm.paint(BF["bark"], 1, "bark")
    char = pm.paint(BF["bark"], 2, "bark")
    soot = pm.paint(BF["soot"], 0)
    pm.loft(None, [(-0.1, 0.42, 0.4, 0, 0), (0.4, 0.3, 0.29, 0.02, 0), (2.2, 0.24, 0.23, -0.06, 0.03),
                   (3.9, 0.18, 0.17, 0.05, 0.0), (4.3, 0.14, 0.12, 0.08, 0.02), (4.6, 0.05, 0.08, 0.13, 0.0)],
            sides=7, paint=bark)
    for (z, a, ln) in ((2.6, 0.8, 0.9), (3.3, 3.6, 0.7), (1.8, 5.2, 0.45)):
        pm.loft(None, [(0.0, 0.08, 0.08, 0, 0), (ln, 0.02, 0.02, 0, 0)], sides=5, center=(0, 0, z),
                rot=(rnd.uniform(0.9, 1.15), 0, a), paint=char)
    for (z, a) in ((0.55, 0.4), (1.05, 2.3), (0.75, 4.1)):  # ember cracks, dim
        pm.box(None, (0.05, 0.03, 0.42), (math.cos(a) * 0.31, math.sin(a) * 0.31, z), rot=(0, 0, a), mat_index=GLOW)
    pm.loft(None, [(-0.1, 0.62, 0.6, 0, 0), (0.1, 0.45, 0.43, 0, 0)], sides=8, paint=soot)  # soot at the foot
    finish(pm, "bf_snag", BF["ember"][1], 0.7)


def bf_log():
    """A fallen charred trunk, 3.6 m, 0.55 m high (collider in the zone)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    bark = pm.paint(BF["bark"], 1, "bark")
    cut = pm.paint(BF["bark"], 3)
    pm.loft(None, [(-1.8, 0.28, 0.26, 0, 0), (-0.4, 0.26, 0.25, 0, 0.02), (1.0, 0.24, 0.23, 0, -0.02), (1.8, 0.2, 0.19, 0, 0)],
            sides=7, center=(0, 0, 0.26), rot=(0, math.pi / 2, 0), paint=bark)
    pm.loft(None, [(-0.01, 0.27, 0.25, 0, 0), (0.01, 0.27, 0.25, 0, 0)], sides=7, center=(-1.81, 0, 0.26),
            rot=(0, math.pi / 2, 0), paint=cut)
    pm.loft(None, [(0.0, 0.06, 0.06, 0, 0), (0.6, 0.015, 0.015, 0, 0)], sides=5, center=(0.4, 0.1, 0.45),
            rot=(0.6, 0.0, 0.5), paint=bark)
    finish(pm, "bf_log")


def bf_stump():
    """A smouldering stump, 0.35 m (walk-through): ember glow in its cracked top."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    bark = pm.paint(BF["bark"], 1, "bark")
    top = pm.paint(BF["bark"], 0)
    pm.loft(None, [(-0.05, 0.36, 0.34, 0, 0), (0.12, 0.28, 0.27, 0, 0), (0.33, 0.25, 0.24, 0, 0)], sides=8, paint=bark)
    pm.loft(None, [(0.33, 0.24, 0.23, 0, 0), (0.35, 0.2, 0.19, 0, 0)], sides=8, paint=top)
    for a in (0.3, 1.9, 3.8, 5.1):
        pm.box(None, (0.16, 0.025, 0.02), (math.cos(a) * 0.1, math.sin(a) * 0.1, 0.355), rot=(0, 0, a), mat_index=GLOW)
    finish(pm, "bf_stump", BF["ember"][2], 0.9)


def bn_rib():
    """A giant rib of the bone field: rises from the dust and bends over,
    7 m tall, 0.5 m thick at the root (collider at the root in the zone)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    bone = pm.paint(HL["bone"], 1, "plate")
    dark = pm.paint(BN["bone_dark"], 1)
    pts = [(0.0, 0.0, -0.3), (0.0, -0.4, 1.6), (0.0, -0.5, 3.4), (0.0, -0.1, 5.0), (0.0, 0.9, 6.3), (0.0, 2.2, 6.9), (0.0, 3.3, 6.7)]
    widths = [0.5, 0.44, 0.38, 0.32, 0.26, 0.2, 0.12]
    for (a, b, w0, w1) in zip(pts, pts[1:], widths, widths[1:]):
        _beam(pm, a, b, (w0 + w1) * 0.5, bone, h=(w0 + w1) * 0.35)
    pm.loft(None, [(-0.3, 0.55, 0.45, 0, 0), (0.15, 0.4, 0.34, 0, 0)], sides=7, paint=dark)  # root in the dust
    finish(pm, "bn_rib")


def bn_skull():
    """The giant skull: a long cranium, dark sockets, a broken horn, the jaw
    sunk into the dust; 3.4 m long, 2.1 m tall (box collider in the zone)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    bone = pm.paint(HL["bone"], 1, "plate")
    pale = pm.paint(HL["bone"], 2)
    dark = pm.paint(BF["bark"], 0)
    pm.loft(None, [(-1.7, 0.55, 0.5, 0, 0.55), (-0.9, 0.95, 0.85, 0, 0.75), (0.2, 1.05, 0.95, 0, 0.85),
                   (1.1, 0.8, 0.75, 0, 0.8), (1.7, 0.35, 0.35, 0, 0.6)], sides=8, rot=(0.0, math.pi / 2, 0.0), paint=bone)
    for side in (-1, 1):
        pm.loft(None, [(-0.05, 0.26, 0.2, 0, 0), (0.05, 0.24, 0.18, 0, 0)], sides=7,
                center=(-0.85, side * 0.62, 1.35), rot=(math.pi / 2, 0.0, 0.0), paint=dark)  # sockets
    pm.loft(None, [(0.0, 0.2, 0.2, 0, 0), (1.1, 0.12, 0.12, 0.25, 0), (1.7, 0.04, 0.04, 0.6, 0)], sides=6,
            center=(0.2, 0.7, 1.6), rot=(0.9, 0.0, -0.4), paint=pale)                       # the horn left
    pm.loft(None, [(0.0, 0.2, 0.2, 0, 0), (0.45, 0.16, 0.16, 0.05, 0)], sides=6,
            center=(0.2, -0.7, 1.6), rot=(-0.9, 0.0, 0.4), paint=pale)                      # the broken one
    pm.box(None, (1.9, 0.9, 0.3), (-0.6, 0.0, 0.12), rot=(0.0, 0.08, 0.0), paint=bone)     # jaw in the dust
    for k in range(5):
        pm.box(None, (0.12, 0.12, 0.3), (-1.45 + k * 0.28, 0.42, 0.42), paint=pale, taper=0.4)
        pm.box(None, (0.12, 0.12, 0.3), (-1.45 + k * 0.28, -0.42, 0.42), paint=pale, taper=0.4)
    finish(pm, "bn_skull")


def bn_vertebra():
    """A giant vertebra half sunk in the dust: a disc, a spine and two wings
    (1.6 m wide, 1.2 m tall; collider in the zone)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    bone = pm.paint(HL["bone"], 1, "plate")
    dark = pm.paint(BN["bone_dark"], 2)
    pm.loft(None, [(-0.35, 0.5, 0.5, 0, 0), (0.35, 0.52, 0.52, 0, 0)], sides=9, center=(0.0, 0.0, 0.25),
            rot=(math.pi / 2, 0.0, 0.0), paint=bone)
    pm.box(None, (0.22, 0.2, 0.75), (0.0, 0.05, 0.95), rot=(0.25, 0.0, 0.0), paint=bone, taper=0.45)
    for side in (-1, 1):
        _beam(pm, (side * 0.35, 0.0, 0.45), (side * 0.85, 0.08, 0.62), 0.16, bone, h=0.2)
    pm.loft(None, [(-0.36, 0.2, 0.2, 0, 0), (0.36, 0.2, 0.2, 0, 0)], sides=8, center=(0.0, 0.0, 0.25),
            rot=(math.pi / 2, 0.0, 0.0), paint=dark)
    finish(pm, "bn_vertebra")


def vg_fallen():
    """A fallen soldier of the old guard, lying where he fell: helm, mail,
    a split shield and the sword beside him. 0.35 m (walk-through)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    iron = pm.paint(RB["iron"], 1, "plate")
    mail = pm.paint(RB["iron"], 2, "cloth")
    cloth = pm.paint(CM["hide"], 1, "cloth")
    wood = pm.paint(VL["timber"], 2, "planks")
    steel = pm.paint(RB["steel"], 1)
    pm.box(None, (0.42, 0.62, 0.24), (0.0, 0.0, 0.13), rot=(0.0, 0.0, 0.08), paint=mail)          # torso
    pm.loft(None, [(0.0, 0.14, 0.15, 0, 0), (0.2, 0.15, 0.16, 0, 0), (0.3, 0.1, 0.11, 0, 0)], sides=7,
            center=(0.05, 0.42, 0.12), rot=(-1.45, 0.0, 0.2), paint=iron)                            # helm
    for x in (-0.12, 0.13):
        pm.box(None, (0.15, 0.7, 0.14), (x, -0.6, 0.08), rot=(0.0, 0.0, x * 0.6), paint=cloth)     # legs
    pm.box(None, (0.12, 0.55, 0.11), (0.33, 0.05, 0.08), rot=(0.0, 0.0, -0.6), paint=mail)        # arm
    pm.loft(None, [(-0.03, 0.36, 0.36, 0, 0), (0.03, 0.36, 0.36, 0, 0)], sides=10, center=(-0.6, 0.15, 0.06),
            rot=(0.1, 0.0, 0.0), paint=wood)                                                         # shield, flat
    pm.box(None, (0.05, 0.72, 0.05), (-0.6, 0.15, 0.1), paint=iron)                                 # its split
    pm.box(None, (0.06, 0.95, 0.025), (0.7, 0.35, 0.03), rot=(0.0, 0.0, 0.5), paint=steel)       # sword
    pm.box(None, (0.24, 0.05, 0.04), (0.47, -0.05, 0.04), rot=(0.0, 0.0, 0.5), paint=iron)
    finish(pm, "vg_fallen")


def vg_tent():
    """A collapsed raider tent: hides slumped over snapped poles (2.6 x 2.2
    m, 1.2 m tall; collider in the zone)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    hide = pm.paint(CM["hide"], 1, "hide")
    hide2 = pm.paint(CM["hide"], 2, "hide")
    wood = pm.paint(CM["wood"], 1, "bark")
    _beam(pm, (-1.2, 0.0, 0.05), (0.2, 0.1, 1.15), 0.09, wood)
    _beam(pm, (1.2, 0.1, 0.05), (0.15, 0.05, 1.2), 0.09, wood)
    _beam(pm, (0.2, 0.1, 1.15), (0.9, -0.7, 0.4), 0.08, wood)     # the snapped ridge
    pm.loft(None, [(0.0, 1.35, 1.1, 0, 0), (0.45, 1.15, 0.95, 0.05, 0), (0.9, 0.55, 0.45, 0.15, 0.05), (1.12, 0.12, 0.1, 0.2, 0.05)],
            sides=8, paint=hide)
    pm.box(None, (0.9, 0.7, 0.05), (-0.9, -0.95, 0.06), rot=(0.1, 0.05, 0.4), paint=hide2)
    finish(pm, "vg_tent")


def vg_spears():
    """The last stand: broken spears driven into the ground in a ring, two
    shields leaning on them (r 0.9 m, 1.6 m; one collider in the zone)."""
    rig.reset_scene()
    rnd = random.Random(151)
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    wood = pm.paint(VL["timber"], 2, "planks")
    iron = pm.paint(RB["iron"], 1)
    shield = pm.paint(CM["rust_plate"], 1, "plate")
    for k in range(7):
        a = k * math.tau / 7 + rnd.uniform(-0.2, 0.2)
        r = 0.75 + rnd.uniform(-0.1, 0.1)
        h = rnd.uniform(0.9, 1.6)
        lean = rnd.uniform(0.1, 0.35)
        base = (math.cos(a) * r, math.sin(a) * r, -0.1)
        tip = (math.cos(a) * (r + lean), math.sin(a) * (r + lean), h)
        _beam(pm, base, tip, 0.05, wood)
        if h > 1.25:
            pm.box(None, (0.07, 0.03, 0.22), tip, rot=(0.0, 0.0, a), paint=iron, taper=0.2)
    for (a, tilt) in ((0.6, 0.35), (3.3, -0.3)):
        pm.loft(None, [(-0.03, 0.36, 0.42, 0, 0), (0.03, 0.36, 0.42, 0, 0)], sides=10,
                center=(math.cos(a) * 0.95, math.sin(a) * 0.95, 0.42), rot=(math.pi / 2 - 0.3, 0.0, a + math.pi / 2), paint=shield)
    finish(pm, "vg_spears")


M12_PROPS = (vl_rafters, vl_fence, vl_well, vl_grave, vl_grave_cross, vl_barricade, vl_cart,
             bf_snag, bf_log, bf_stump, bn_rib, bn_skull, bn_vertebra, vg_fallen, vg_tent, vg_spears)


def lore_note():
    """M12 lore: a note nailed to a split stake, 0.9 m (thin, walk-through)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    wood = pm.paint(VL["timber"], 2, "planks")
    paper = pm.paint(HL["bone"], 2, "cloth")
    ink = pm.paint(HL["bone"], 0)
    pm.box(None, (0.07, 0.07, 0.95), (0.0, 0.0, 0.45), rot=(0.05, 0.0, 0.0), paint=wood, taper=0.8)
    pm.box(None, (0.3, 0.012, 0.36), (0.0, -0.05, 0.72), rot=(0.05, 0.08, 0.0), paint=paper)
    for k in range(4):
        pm.box(None, (0.2 - k * 0.03, 0.004, 0.012), (-0.01, -0.058, 0.8 - k * 0.055), rot=(0.05, 0.08, 0.0), paint=ink)
    pm.box(None, (0.03, 0.03, 0.03), (0.0, -0.06, 0.88), paint=pm.paint(RB["iron"], 1))  # the nail
    finish(pm, "lore_note")


def lore_tablet():
    """M12 lore: a standing stone with carved lines, the old runes in them
    glowing faintly in the ancient-rune teal; 1.15 m (collider in the zone)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    stone = pm.paint(HL["basalt"], 3, "plate")
    moss = pm.paint(HL["ash_top"], 1)
    pm.box(None, (0.9, 0.3, 1.1), (0.0, 0.0, 0.5), rot=(0.04, 0.03, 0.0), paint=stone, taper=0.85)
    pm.box(None, (0.95, 0.36, 0.12), (0.0, 0.0, 0.03), paint=moss)
    for k in range(4):
        pm.box(None, (0.55 - (k % 2) * 0.15, 0.02, 0.035), (0.0, -0.16, 0.85 - k * 0.15), rot=(0.04, 0.03, 0.0),
               mat_index=GLOW)
    finish(pm, "lore_tablet", ROLES["player_accent"]["body"], 0.45)


def rune_shard():
    """M12 collectible: a shard of the Rune, pale stone cut by a teal rune
    line, 0.36 m (walk-through; it bobs and turns in the zone)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    stone = pm.paint(HL["bone"], 1, "plate")
    pm.box(None, (0.16, 0.1, 0.32), (0.0, 0.0, 0.17), rot=(0.15, 0.1, 0.3), paint=stone, taper=0.35)
    pm.box(None, (0.1, 0.07, 0.18), (0.08, 0.02, 0.09), rot=(-0.3, 0.2, 1.2), paint=stone, taper=0.4)
    pm.box(None, (0.025, 0.11, 0.22), (0.0, 0.0, 0.17), rot=(0.15, 0.1, 0.3), mat_index=GLOW, taper=0.4)
    finish(pm, "rune_shard", ROLES["player_accent"]["hot"], 0.9)


def ember_tuber_plant():
    """M12 food: ember tubers half sunk in the warm ash, their skins cracked
    with a dim ember glow, a few dry leaves; 0.25 m (walk-through)."""
    rig.reset_scene()
    rnd = random.Random(171)
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    skin = pm.paint(HL["rust_hide"], 1, "hide")
    leaf = pm.paint(HL["dead_grass"], 2)
    for k in range(3):
        a = k * math.tau / 3 + rnd.uniform(-0.3, 0.3)
        r = 0.09 if k else 0.0
        cx, cy = math.cos(a) * r, math.sin(a) * r
        s = rnd.uniform(0.07, 0.1)
        pm.loft(None, [(-0.03, s * 0.9, s * 0.8, cx, cy), (s * 0.6, s * 1.1, s, cx, cy), (s * 1.4, s * 0.4, s * 0.35, cx, cy)],
                sides=7, paint=skin)
        pm.box(None, (s * 0.9, 0.012, 0.012), (cx, cy - s * 0.95, s * 0.6), rot=(0.0, 0.0, a), mat_index=GLOW)
    for k in range(5):
        a = k * math.tau / 5 + 0.4
        pm.loft(None, [(0.0, 0.012, 0.008, 0, 0), (0.22, 0.003, 0.003, math.cos(a) * 0.12, math.sin(a) * 0.12)],
                sides=3, center=(0.0, 0.0, 0.08), paint=leaf)
    finish(pm, "ember_tuber_plant", BF["ember"][2], 0.8)


def cook_pot():
    """M12 food: a raider camp's iron cooking pot on three stones, a ladle in
    it, a dim ember glow under it; 0.38 m (walk-through)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    iron = pm.paint(RB["iron"], 1, "plate")
    rim = pm.paint(RB["iron"], 2)
    stone = pm.paint(HL["basalt"], 2)
    wood = pm.paint(CM["wood"], 2, "bark")
    stew = pm.paint(HL["rust_hide"], 2)
    for k in range(3):
        a = k * math.tau / 3
        pm.box(None, (0.12, 0.12, 0.1), (math.cos(a) * 0.2, math.sin(a) * 0.2, 0.05), rot=(0.0, 0.0, a), paint=stone)
    pm.loft(None, [(0.08, 0.14, 0.14, 0, 0), (0.18, 0.24, 0.24, 0, 0), (0.32, 0.22, 0.22, 0, 0), (0.36, 0.2, 0.2, 0, 0)],
            sides=10, paint=iron)
    pm.loft(None, [(0.355, 0.21, 0.21, 0, 0), (0.37, 0.215, 0.215, 0, 0)], sides=10, paint=rim)
    pm.loft(None, [(0.33, 0.18, 0.18, 0, 0), (0.345, 0.18, 0.18, 0, 0)], sides=10, paint=stew)
    pm.box(None, (0.025, 0.025, 0.4), (0.06, 0.02, 0.42), rot=(0.0, 0.5, 0.2), paint=wood)
    pm.box(None, (0.14, 0.14, 0.02), (0.0, 0.0, 0.03), mat_index=GLOW)
    finish(pm, "cook_pot", BF["ember"][1], 0.7)


M12_PROPS = M12_PROPS + (lore_note, lore_tablet, rune_shard, ember_tuber_plant, cook_pot)


def brazier():
    """M12 puzzle: a chapel brazier - a fieldstone pedestal with an iron bowl
    of cold coals (the fire is added in the zone when lit); 1.1 m (collider)."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    stone = pm.paint(VL["cobble"], 2, "masonry")
    cap = pm.paint(VL["cobble"], 3)
    iron = pm.paint(RB["iron"], 1, "plate")
    coal = pm.paint(BF["bark"], 0)
    pm.loft(None, [(0.0, 0.32, 0.32, 0, 0), (0.15, 0.26, 0.26, 0, 0), (0.75, 0.2, 0.2, 0, 0), (0.85, 0.27, 0.27, 0, 0)],
            sides=8, paint=stone)
    pm.loft(None, [(0.85, 0.28, 0.28, 0, 0), (0.9, 0.29, 0.29, 0, 0)], sides=8, paint=cap)
    pm.loft(None, [(0.9, 0.16, 0.16, 0, 0), (1.0, 0.34, 0.34, 0, 0), (1.1, 0.38, 0.38, 0, 0)], sides=10, paint=iron)
    pm.loft(None, [(1.04, 0.3, 0.3, 0, 0), (1.08, 0.31, 0.31, 0, 0)], sides=10, paint=coal)
    finish(pm, "brazier")


def bn_spikes():
    """M12 dodge run: a strip of bone spikes that bursts out of the dust (2.4 m
    wide, 0.9 m tall; the zone hides it below the ground between bursts)."""
    rig.reset_scene()
    rnd = random.Random(191)
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    bone = pm.paint(HL["bone"], 1, "plate")
    dark = pm.paint(BN["bone_dark"], 1)
    for k in range(7):
        x = -1.05 + k * 0.35 + rnd.uniform(-0.06, 0.06)
        y = rnd.uniform(-0.25, 0.25)
        h = rnd.uniform(0.6, 0.95)
        tilt = rnd.uniform(-0.18, 0.18)
        pm.box(None, (0.13, 0.13, h), (x, y, h * 0.5 - 0.05), rot=(tilt, rnd.uniform(-0.15, 0.15), rnd.uniform(0, 1.5)),
               paint=bone, taper=0.12)
    pm.box(None, (2.5, 0.7, 0.12), (0.0, 0.0, -0.02), paint=dark)
    finish(pm, "bn_spikes")


def rune_seal():
    """M12 puzzle: a round seal stone set into the ground with a rune ring
    (dark until the beam reaches it, then the zone lights it); 0.25 m."""
    rig.reset_scene()
    pm = rig.PartMesh(px_per_m=ENV_DENSITY)
    stone = pm.paint(HL["basalt"], 3, "plate")
    edge = pm.paint(HL["basalt"], 2)
    pm.loft(None, [(0.0, 1.05, 1.05, 0, 0), (0.18, 1.0, 1.0, 0, 0), (0.24, 0.92, 0.92, 0, 0)], sides=12, paint=edge)
    pm.loft(None, [(0.2, 0.88, 0.88, 0, 0), (0.26, 0.86, 0.86, 0, 0)], sides=12, paint=stone)
    for k in range(8):
        a = k * math.tau / 8
        pm.box(None, (0.24, 0.05, 0.02), (math.cos(a) * 0.6, math.sin(a) * 0.6, 0.265), rot=(0, 0, a + math.pi / 2), mat_index=GLOW)
    pm.box(None, (0.32, 0.06, 0.02), (0.0, 0.0, 0.265), rot=(0, 0, 0.6), mat_index=GLOW)
    pm.box(None, (0.32, 0.06, 0.02), (0.0, 0.0, 0.265), rot=(0, 0, -0.6), mat_index=GLOW)
    finish(pm, "rune_seal", ROLES["player_accent"]["body"], 0.5)


M12_PROPS = M12_PROPS + (brazier, bn_spikes, rune_seal)


if __name__ == "__main__":
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for fn in (bonfire, rune_monolith, banner_pole, charred_tree, bone_pile, ash_tuft, stone_cluster, log_seat,
               rh_hut_trim, rh_wall_banner, rh_pine, rh_oak, rh_hearth_fire, rh_hearth_stone, rh_grass_tuft,
               rh_stone_cluster, rh_weapon_rack, rh_training_post,
               sp_crystal_pillar, sp_wall_arch, sp_beacon, sp_shard, sp_crystal_cluster, sp_rubble,
               portal_arch, portal_plate, treasure_chest, loot_blade, loot_armor, loot_relic,
               loot_helm, loot_gloves, loot_boots, loot_ring,
               legendary_cindermaw, legendary_conductors_oath, legendary_glacier_heart, waypoint_shrine) + M12_PROPS:
        if not only or fn.__name__ in only:
            fn()
    print("props done.")
