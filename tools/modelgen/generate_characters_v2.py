"""RUNEBOUND M06 character generator (Blender 5.2 headless): rigged,
atlas-baked, animated characters for the gold target.

  assets/models/chars/runebreaker.glb     + assets/textures/char/runebreaker_atlas.png
  assets/models/chars/cinder_marauder.glb + assets/textures/char/cinder_marauder_atlas.png
  assets/models/chars/duskweaver.glb      + assets/textures/char/duskweaver_atlas.png

Conventions: Z-up, faces -Y (Godot instances with rotation.y = PI), R = -X.
Bone-local rotations (radians, XYZ euler; X is applied first):
  * limbs hanging down (arms, legs, robe hem): +X swings the limb BACK, -X
    forward; +Z swings a hanging limb toward the character's right (-X) --
    once an arm is raised overhead, +Z moves its hand toward the LEFT;
  * upward bones (hips/spine/chest/head): +X bows forward, +Y twists toward
    the character's left, +Z bends toward the character's right.
Bone-local locations of upward bones are (left, UP, forward): a hip drop is
{"loc": (0, -d, 0)} (`crouch()` keeps the feet planted).
Material slots: 0 body (atlas), 1 glow (emissive), 2 telegraph weapon (enemies).
Clips are 60 fps, start at frame 0, carry no root motion. Lengths and contact
frames come from the gameplay timings (resources/abilities/*.tres, enemy and
Player consts); tests/smoke_test.gd pins them. Every key is a FULL pose over
the character's stance, so crossfades between clips never pop limbs to rest.

Run:
  & "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background
      --python tools/modelgen/generate_characters_v2.py -- [runebreaker] [marauder] [duskweaver]
      [stonehulk] [veilstalker] [warden] [colossus] [vessel] [--sheets]
--sheets also renders per-clip contact sheets to captures_contact/ (review).
"""
import math
import os
import re
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import atlas, pose, rig  # noqa: E402
from lib.pose import pos, way  # noqa: E402

ROOT = rig.ROOT
SPEC = rig.load_spec()
PAL = SPEC["palettes"]
ROLES = SPEC["color_roles"]
CHAR_DENSITY = SPEC["texel_density"]["character_px_per_m"]
TEX_DIR = os.path.join(ROOT, "assets", "textures", "char")
SHEET_DIR = os.path.join(ROOT, "captures_contact")

EXPO_IN = ("EXPO", "EASE_IN")
EXPO_OUT = ("EXPO", "EASE_OUT")
BACK_OUT = ("BACK", "EASE_OUT")
QUART_OUT = ("QUART", "EASE_OUT")


def ability_timing(name):
    """startup/active/recovery from the ability .tres (gameplay is authoritative)."""
    text = open(os.path.join(ROOT, "resources", "abilities", name + ".tres"), encoding="utf-8").read()
    out = {}
    for key in ("startup", "active", "recovery"):
        m = re.search(r"^%s = ([0-9.]+)" % key, text, re.M)
        out[key] = float(m.group(1)) if m else 0.0
    return out


def const_from(script, name):
    text = open(os.path.join(ROOT, "scripts", script), encoding="utf-8").read()
    return float(re.search(r"const %s := ([0-9.]+)" % name, text).group(1))


def f(seconds):
    return int(round(seconds * rig.FPS))


def humanoid_bones(hip, chest_top, shoulder_x, arm_len, leg_x, head_base, head_top, lean=0.0):
    knee = hip * 0.55
    bones = [
        ("root", None, (0, 0, 0), (0, 0, 0.25)),
        ("hips", "root", (0, 0, hip), (0, lean * 0.3, hip + 0.14)),
        ("spine", "hips", (0, lean * 0.3, hip + 0.14), (0, lean * 0.6, (hip + chest_top) * 0.5 + 0.05)),
        ("chest", "spine", (0, lean * 0.6, (hip + chest_top) * 0.5 + 0.05), (0, lean, chest_top)),
        ("head", "chest", (0, lean * 1.3, head_base), (0, lean * 1.3, head_top)),
    ]
    shoulder_z = chest_top - 0.06
    for side, x in (("L", 1.0), ("R", -1.0)):
        sx = shoulder_x * x
        elbow = shoulder_z - arm_len * 0.52
        wrist = shoulder_z - arm_len
        bones += [
            ("upper_arm." + side, "chest", (sx, lean, shoulder_z), (sx * 1.1, lean, elbow)),
            ("forearm." + side, "upper_arm." + side, (sx * 1.1, lean, elbow), (sx * 1.14, lean, wrist)),
            ("hand." + side, "forearm." + side, (sx * 1.14, lean, wrist), (sx * 1.14, lean, wrist - 0.1)),
            ("thigh." + side, "hips", (leg_x * x, 0, hip), (leg_x * x, 0, knee)),
            ("shin." + side, "thigh." + side, (leg_x * x, 0, knee), (leg_x * x, 0, 0.1)),
            ("foot." + side, "shin." + side, (leg_x * x, 0, 0.1), (leg_x * x, -0.18, 0.04)),
        ]
    return bones


def crouch(drop, leg_len, hips_rot=(0.0, 0.0, 0.0)):
    """Both legs bent so the hips sink by `drop` with the feet staying under
    them on the ground: thigh forward a, shin back 2a (absolute a), foot level."""
    a = math.acos(max(-1.0, min(1.0, 1.0 - drop / leg_len)))
    pose = {"hips": {"rot": hips_rot, "loc": (0.0, -drop, 0.0)}}
    for side in ("L", "R"):
        pose["thigh." + side] = (-a, 0.0, 0.0)
        pose["shin." + side] = (2.0 * a, 0.0, 0.0)
        pose["foot." + side] = (-a, 0.0, 0.0)
    return pose


def keyed(base):
    """Key helper: every key = the stance with this key's overrides on top.
    The stance must list every bone any clip keys (incl. hands a solved
    intent writes): a bone missing from some keys holds its neighbours'
    value there instead of the stance's."""
    def make(overrides=None):
        pose = dict(base)
        pose.update(overrides or {})
        return pose
    return make


def action(arm, name, keys, interpolation=None, sheet=None):
    """Resolve pose intents (lib.pose), key the clip, and remember which
    frames its contact sheet shows."""
    poser = POSERS.setdefault(arm.name, pose.Poser(arm))
    keys = pose.compatible([(frame, poser.apply(p)) for frame, p in keys])
    rig.make_action(arm, name, keys, interpolation)
    frames = sheet if sheet is not None else sorted({k[0] for k in keys})
    SHEETS.setdefault(arm.name, []).append((name, frames))


SHEETS = {}
POSERS = {}


def finish(body, arm, atlas_name, glb_name, skip_slots, sheets):
    size = atlas.unwrap(body, CHAR_DENSITY)
    os.makedirs(TEX_DIR, exist_ok=True)
    atlas_path = os.path.join(TEX_DIR, atlas_name + "_atlas.png")
    atlas.bake(body, size, atlas_path, skip_material_indices=skip_slots)
    rig.export_glb(os.path.join(ROOT, "assets", "models", "chars", glb_name + ".glb"),
                   active_action=bpy.data.actions["idle"], arm_obj=arm)
    if sheets:
        from lib import sheets as sheet_lib
        sheet_lib.render(body, arm, atlas_path, SHEETS.get(arm.name, []), os.path.join(SHEET_DIR, glb_name))


# ---------------------------------------------------------------------------
# RUNEBREAKER — heroic-chunky rune knight, ~4.5 heads, <= 2.0 m incl. crest
# ---------------------------------------------------------------------------

RB_LEG = 0.88 - 0.1  # hip height minus ankle: thigh 0.396 + shin 0.384


def build_runebreaker(sheets=False):
    rig.reset_scene()
    arm = rig.build_armature("runebreaker", humanoid_bones(
        hip=0.88, chest_top=1.5, shoulder_x=0.34, arm_len=0.62, leg_x=0.14, head_base=1.52, head_top=1.86))
    rb = PAL["runebreaker"]
    pm = rig.PartMesh(px_per_m=CHAR_DENSITY)
    # value bands: key planes 40-70 % vs ash ground ~25 % (ART_BIBLE)
    iron = pm.paint(rb["iron"], 3, "plate")
    dark = pm.paint(rb["iron"], 2, "plate")
    teal = pm.paint(rb["teal_cloth"], 3, "cloth")
    leather = pm.paint(rb["leather"], 2, "hide")
    gold = pm.paint(rb["gold_trim"], 2)
    steel = pm.paint(rb["steel"], 2)

    for side, x in (("L", 1.0), ("R", -1.0)):
        lx = 0.14 * x
        # boots: long flared toe box + teal cuff
        pm.loft("foot." + side, [(0.0, 0.11, 0.17, lx, -0.05), (0.08, 0.115, 0.16, lx, -0.04),
                                 (0.17, 0.1, 0.11, lx, 0.0)], paint=dark)
        pm.loft("shin." + side, [(0.16, 0.105, 0.105, lx, 0.0), (0.22, 0.11, 0.11, lx, 0.0)], paint=teal)
        # greaves + knee cop
        pm.loft("shin." + side, [(0.2, 0.085, 0.09, lx, 0.0), (0.36, 0.1, 0.105, lx, -0.005),
                                 (0.5, 0.09, 0.095, lx, 0.0)], paint=iron)
        pm.loft("shin." + side, [(0.46, 0.07, 0.05, lx, -0.09), (0.56, 0.075, 0.06, lx, -0.1)], paint=steel, sides=6)
        # thighs + tasset plates hanging from the belt
        pm.loft("thigh." + side, [(0.5, 0.095, 0.1, lx, 0.0), (0.74, 0.115, 0.12, lx, 0.0),
                                  (0.88, 0.12, 0.12, lx, 0.0)], paint=leather)
        pm.box("thigh." + side, (0.2, 0.05, 0.26), (lx * 1.1, -0.1, 0.74), rot=(0.12, 0.0, -0.1 * x), paint=iron)
        # pauldrons: oversized domes with a teal rim
        sx = 0.36 * x
        pm.loft("upper_arm." + side, [(1.3, 0.2, 0.21, sx, 0.0), (1.34, 0.21, 0.22, sx, 0.0)], paint=teal)
        pm.loft("upper_arm." + side, [(1.33, 0.2, 0.21, sx, 0.0), (1.45, 0.215, 0.22, sx, 0.0),
                                      (1.55, 0.16, 0.17, sx, 0.0), (1.6, 0.08, 0.09, sx, 0.0)], paint=iron)
        pm.box("upper_arm." + side, (0.06, 0.14, 0.05), (sx * 1.02, 0.0, 1.6), paint=gold)
        # arms + gauntlets (~1.4x)
        pm.loft("upper_arm." + side, [(1.36, 0.075, 0.08, sx * 1.02, 0.0), (1.14, 0.07, 0.075, sx * 1.08, 0.0)], paint=dark)
        pm.loft("forearm." + side, [(1.15, 0.07, 0.075, sx * 1.1, 0.0), (1.0, 0.1, 0.1, sx * 1.12, 0.0),
                                    (0.93, 0.105, 0.105, sx * 1.13, 0.0)], paint=iron)
        pm.box("hand." + side, (0.15, 0.17, 0.15), (sx * 1.14, -0.01, 0.84), paint=dark)

    # belt + buckle, tabard front/back
    pm.loft("hips", [(0.83, 0.21, 0.15, 0, 0), (0.96, 0.23, 0.16, 0, 0)], paint=leather)
    pm.box("hips", (0.12, 0.04, 0.1), (0, -0.165, 0.9), paint=gold)
    pm.box("hips", (0.24, 0.025, 0.42), (0, -0.155, 0.64), paint=teal)
    pm.box("hips", (0.3, 0.025, 0.44), (0, 0.16, 0.64), paint=teal)
    # V-torso: waist -> barrel chest -> shoulders
    pm.loft("spine", [(0.95, 0.2, 0.14, 0, 0), (1.08, 0.23, 0.16, 0, 0), (1.2, 0.28, 0.19, 0, 0)], paint=dark)
    pm.loft("chest", [(1.19, 0.29, 0.19, 0, 0), (1.32, 0.34, 0.22, 0, -0.01), (1.45, 0.34, 0.21, 0, 0),
                      (1.53, 0.22, 0.15, 0, 0)], paint=iron)
    pm.loft("chest", [(1.5, 0.12, 0.1, 0, 0), (1.56, 0.1, 0.09, 0, 0)], paint=dark)          # gorget
    pm.loft("chest", [(1.28, 0.07, 0.03, 0, -0.215), (1.4, 0.07, 0.03, 0, -0.215)], sides=6, mat_index=1)  # sigil
    # bucket helm, visor slit (glow), teal crest
    pm.loft("head", [(1.53, 0.15, 0.15, 0, 0), (1.62, 0.175, 0.18, 0, -0.005), (1.75, 0.17, 0.175, 0, 0),
                     (1.84, 0.1, 0.11, 0, 0.01)], paint=iron)
    pm.box("head", (0.21, 0.03, 0.035), (0, -0.182, 1.68), mat_index=1)
    pm.box("head", (0.05, 0.32, 0.13), (0, 0.02, 1.9), paint=teal)
    # rune sword in the right fist (rest: blade pointing forward), glow groove
    hx = -0.36 * 1.14
    pm.box("hand.R", (0.05, 0.05, 0.24), (hx, -0.01, 0.84), paint=leather)                   # grip
    pm.box("hand.R", (0.3, 0.07, 0.05), (hx, -0.1, 0.84), paint=gold)                        # guard
    pm.loft("hand.R", [(0.0, 0.07, 0.02, 0, 0), (0.95, 0.065, 0.02, 0, 0), (1.1, 0.012, 0.012, 0, 0)],
            sides=4, center=(hx, -0.12, 0.84), rot=(1.5708, 0, 0), paint=steel, mat_index=2)  # blade along -Y
    # (slot 2 = the blade: baked in the atlas like the body, swappable in Godot
    # for a legendary weapon's look, e.g. Cindermaw's molten edge)
    pm.box("hand.R", (0.018, 0.8, 0.026), (hx, -0.6, 0.84), mat_index=1)                     # rune groove

    mat_body = rig.make_material("rb_body", "#FFFFFF")
    mat_glow = rig.make_material("rb_glow", ROLES["resonance"]["body"], emission_hex=ROLES["resonance"]["body"], strength=3.0)
    mat_blade = rig.make_material("rb_blade", "#FFFFFF")
    body = pm.to_object("runebreaker", [mat_body, mat_glow, mat_blade], arm)

    runebreaker_clips(arm)
    finish(body, arm, "runebreaker", "runebreaker", (1,), sheets)


def runebreaker_clips(arm):
    # Ready stance: athletic knee bend, sword angled up-forward in the right
    # fist, left hand loose. Every clip keys the full stance underneath.
    ready = {
        **crouch(0.02, RB_LEG),
        "spine": (0.03, 0, 0), "chest": (0.05, 0, 0), "head": (0.0, 0, 0),
        "upper_arm.R": (-0.55, 0, 0.35), "forearm.R": (-0.6, 0, 0), "hand.R": (0.0, 0, 0),
        "upper_arm.L": (-0.15, 0, -0.18), "forearm.L": (-0.35, 0, 0), "hand.L": (0.0, 0, 0),
    }
    k = keyed(ready)

    action(arm, "idle", [
        (0, k()),
        (45, k({"chest": (0.02, 0, 0), "upper_arm.L": (-0.12, 0, -0.22), "head": (-0.03, 0, 0),
                "hips": {"rot": (0, 0, 0), "loc": (0, -0.012, 0)}})),
        (90, k()),
    ], sheet=[0, 45])

    run_keys = []
    for frame, s in ((0, 1.0), (18, -1.0), (36, 1.0)):
        run_keys.append((frame, k({
            "thigh.L": (-0.75 * s, 0, 0), "thigh.R": (0.75 * s, 0, 0),
            "shin.L": (0.25 + 0.55 * max(-s, 0), 0, 0), "shin.R": (0.25 + 0.55 * max(s, 0), 0, 0),
            "foot.L": (0.0, 0, 0), "foot.R": (0.0, 0, 0),
            "upper_arm.L": (0.5 * s, 0, -0.15), "upper_arm.R": (-0.55 - 0.25 * s, 0, 0.3),
            "forearm.L": (-0.7, 0, 0), "forearm.R": (-0.7, 0, 0),
            "spine": (0.14, 0.12 * s, 0), "chest": (0.04, -0.08 * s, 0),
            "hips": {"rot": (0, 0, 0), "loc": (0, -0.01, 0)},
        })))
    for frame in (9, 27):
        # passing pose: body at its highest (hips bob UP = local Y)
        run_keys.append((frame, {"hips": {"rot": (0, 0, 0), "loc": (0, 0.035, 0)}}))
    run_keys.sort(key=lambda key: key[0])
    action(arm, "run", run_keys, sheet=[0, 9, 18, 27])

    # --- Rune Cleave: contact frame = the timer-driven hit (startup) --------
    cleave = ability_timing("rune_cleave")
    c = f(cleave["startup"])                                              # 7
    end = f(cleave["startup"] + cleave["active"] + cleave["recovery"])    # 28
    lunge = {"thigh.L": (-0.38, 0, 0), "shin.L": (0.5, 0, 0), "foot.L": (-0.12, 0, 0),
             "thigh.R": (0.12, 0, 0), "shin.R": (0.32, 0, 0), "foot.R": (-0.44, 0, 0)}
    swing_ease = {c - 3: EXPO_IN, c: BACK_OUT, c + 5: QUART_OUT}
    elbow_down = way(left=-0.3, up=-1.0)
    # The blade sweeps flat at chest height through the hit sphere (r 1.5,
    # 1.2 m ahead, 1.0 m up): wind-up on one side, contact straight ahead with
    # the blade trailing the sweep, follow-through out on the other side.
    # cleave_r (_melee_flip == false): forehand, sword sweeps right -> left.
    action(arm, "cleave_r", [
        (0, k()),
        (c - 3, k({"chest": (0.05, -0.55, 0), "spine": (0.05, -0.2, 0), "upper_arm.L": (-0.3, 0, -0.35),
                   "_reach.R": (pos(fwd=-0.1, left=-0.5, up=1.55), way(fwd=-0.3, left=-0.3, up=-1.0)),
                   "_blade.R": way(fwd=-0.5, left=-0.5, up=0.7)})),
        (c, k({**lunge, "chest": (0.1, 0.45, 0), "spine": (0.08, 0.2, 0), "upper_arm.L": (0.2, 0, -0.3),
               "_reach.R": (pos(fwd=0.5, left=0.0, up=1.22), elbow_down),
               "_blade.R": way(fwd=1.0, left=-0.3)})),
        (c + 5, k({**lunge, "chest": (0.1, 0.7, 0), "spine": (0.08, 0.3, 0), "upper_arm.L": (0.3, 0, -0.3),
                   "_reach.R": (pos(fwd=0.3, left=0.45, up=1.15), elbow_down),
                   "_blade.R": way(fwd=-0.1, left=1.0, up=-0.1)})),
        (end, k()),
    ], swing_ease)
    # cleave_l (_melee_flip == true, the combo opener): backhand, left -> right.
    action(arm, "cleave_l", [
        (0, k()),
        (c - 3, k({"chest": (0.05, 0.55, 0), "spine": (0.05, 0.2, 0),
                   "upper_arm.L": (-0.2, 0, -0.1), "forearm.L": (-0.6, 0, 0),
                   "_reach.R": (pos(fwd=0.25, left=0.2, up=1.45), way(fwd=0.2, left=-0.5, up=-1.0)),
                   "_blade.R": way(fwd=-0.3, left=1.0, up=0.25)})),
        (c, k({**lunge, "chest": (0.1, -0.35, 0), "spine": (0.08, -0.15, 0), "upper_arm.L": (0.25, 0, -0.35),
               "_reach.R": (pos(fwd=0.45, left=-0.1, up=1.22), elbow_down),
               "_blade.R": way(fwd=1.0, left=0.3)})),
        (c + 5, k({**lunge, "chest": (0.1, -0.65, 0), "spine": (0.08, -0.3, 0), "upper_arm.L": (0.35, 0, -0.3),
                   "_reach.R": (pos(fwd=0.2, left=-0.5, up=1.2), elbow_down),
                   "_blade.R": way(fwd=-0.1, left=-1.0, up=-0.05)})),
        (end, k()),
    ], swing_ease)

    # --- Dodge: low dash over DODGE_DURATION, landing in DODGE_RECOVERY ------
    dash_t = f(const_from("player/player.gd", "DODGE_DURATION"))          # 14
    dodge_end = f(const_from("player/player.gd", "DODGE_DURATION") + const_from("player/player.gd", "DODGE_RECOVERY"))  # 19
    dash = k({"hips": {"rot": (0, 0, 0), "loc": (0, -0.12, 0)},
              "spine": (0.38, 0, 0), "chest": (0.2, 0, 0), "head": (-0.4, 0, 0),
              "thigh.L": (-0.95, 0, 0), "shin.L": (1.15, 0, 0), "foot.L": (-0.2, 0, 0),
              "thigh.R": (0.5, 0, 0), "shin.R": (0.35, 0, 0), "foot.R": (0.3, 0, 0),
              "upper_arm.R": (0.55, 0, 0.35), "forearm.R": (-0.35, 0, 0), "_blade.R": way(fwd=-1.0, up=0.2),
              "upper_arm.L": (0.6, 0, -0.35), "forearm.L": (-0.45, 0, 0)})
    land = k({**crouch(0.08, RB_LEG), "spine": (0.2, 0, 0), "chest": (0.1, 0, 0), "head": (-0.15, 0, 0),
              "upper_arm.R": (-0.3, 0, 0.4), "forearm.R": (-0.6, 0, 0), "upper_arm.L": (0.1, 0, -0.3)})
    action(arm, "dodge", [
        (0, k()),
        (3, dash),
        (dash_t - 3, {**dash, "thigh.L": (-0.8, 0, 0), "shin.L": (0.95, 0, 0), "thigh.R": (0.35, 0, 0)}),
        (dash_t + 1, land),
        (dodge_end, k()),
    ], {0: EXPO_OUT, dash_t - 3: QUART_OUT, dash_t + 1: QUART_OUT})

    # --- Ember Lance: left-hand thrust, release = startup (projectile spawn) --
    em = ability_timing("ember_lance")
    rel = f(em["startup"])                                                # 8
    thrust = k({"chest": (0.12, -0.3, 0), "spine": (0.06, -0.12, 0), "head": (0, 0.15, 0),
                "upper_arm.R": (-0.3, 0, 0.55), "thigh.L": (-0.32, 0, 0), "shin.L": (0.45, 0, 0), "foot.L": (-0.13, 0, 0),
                "_reach.L": (pos(fwd=0.65, left=0.05, up=1.35), way(left=1.0, up=-1.0))})
    action(arm, "ember", [
        (0, k()),
        (rel - 3, k({"chest": (0.0, 0.4, 0), "spine": (0.0, 0.15, 0), "upper_arm.R": (-0.45, 0, 0.45),
                     "_reach.L": (pos(fwd=-0.15, left=0.45, up=1.55), way(fwd=-0.3, left=1.0, up=-0.6))})),
        (rel, thrust),
        (rel + 6, {**thrust, "chest": (0.1, -0.34, 0),
                   "_reach.L": (pos(fwd=0.62, left=0.07, up=1.37), way(left=1.0, up=-1.0))}),
        (rel + 16, k()),
    ], {rel - 3: EXPO_IN, rel: BACK_OUT, rel + 6: QUART_OUT})

    # --- Earthbreaker: rise (velocity-driven jump) + separate impact clip ----
    # The rise holds its falling pose until the gameplay slam fires the
    # impact clip (Player emits action_started("earthbreaker_impact")).
    eb = ability_timing("earthbreaker")
    top = f(eb["startup"])                                                # 23
    # two-handed grip: both wrists together, elbows out
    def grip(target, blade, elbows_up=0.0):
        return {"_reach.R": (target + pos(left=-0.07), way(left=-1.0, up=elbows_up)),
                "_reach.L": (target + pos(left=0.07, up=-0.02), way(left=1.0, up=elbows_up)),
                "_blade.R": blade}
    overhead = {"chest": (-0.22, 0, 0), "spine": (-0.12, 0, 0), "head": (0.05, 0, 0),
                **grip(pos(fwd=-0.05, up=1.97), way(fwd=-0.7, up=0.6), elbows_up=0.2)}
    tuck = {"hips": {"rot": (0, 0, 0), "loc": (0, 0, 0)},
            "thigh.L": (-0.95, 0, 0), "shin.L": (1.3, 0, 0), "foot.L": (-0.35, 0, 0),
            "thigh.R": (-0.6, 0, 0), "shin.R": (1.1, 0, 0), "foot.R": (-0.5, 0, 0)}
    falling = k({**tuck, "chest": (0.45, 0, 0), "spine": (0.28, 0, 0), "head": (-0.35, 0, 0),
                 **grip(pos(fwd=0.55, up=1.3), way(fwd=1.0, up=0.7), elbows_up=-1.0)})
    action(arm, "earthbreaker_rise", [
        (0, k()),
        (4, k({**crouch(0.12, RB_LEG), "spine": (0.3, 0, 0), "chest": (0.15, 0, 0), "head": (-0.25, 0, 0),
               "upper_arm.R": (-0.35, 0, -0.25), "forearm.R": (-0.5, 0, 0),
               "upper_arm.L": (-0.45, 0, 0.35), "forearm.L": (-0.5, 0, 0)})),
        (12, k({**tuck, **overhead, "chest": (-0.1, 0, 0)})),
        (top, k({**tuck, **overhead})),
        (top + 4, falling),
        (60, falling),
    ], {0: QUART_OUT, 4: EXPO_OUT, 12: QUART_OUT, top: EXPO_IN}, sheet=[0, 4, 12, top, top + 4])
    slam = k({**crouch(0.25, RB_LEG), "spine": (0.5, 0, 0), "chest": (0.35, 0, 0), "head": (-0.4, 0, 0),
              **grip(pos(fwd=0.6, up=0.72), way(fwd=0.45, up=-1.0), elbows_up=-0.5)})
    eb_rec = f(eb["recovery"])                                            # 18
    action(arm, "earthbreaker_impact", [
        (0, slam),
        (3, {**slam, "spine": (0.55, 0, 0)}),
        (eb_rec - 6, k({**crouch(0.1, RB_LEG), "spine": (0.2, 0, 0), "chest": (0.1, 0, 0),
                        "upper_arm.R": (-0.6, 0, 0.3), "forearm.R": (-0.4, 0, 0), "upper_arm.L": (-0.3, 0, -0.2)})),
        (eb_rec + 6, k()),
    ], {3: QUART_OUT, eb_rec - 6: QUART_OUT})

    # --- Storm Step: lightning lunge for the dash, settle in recovery --------
    ss = ability_timing("storm_step")
    dash_end = f(ss["active"])                                            # 7
    ss_end = f(ss["active"] + ss["recovery"]) + 4                          # 16
    lunge_ss = k({"hips": {"rot": (0, 0, 0), "loc": (0, -0.14, 0)},
                  "spine": (0.5, 0, 0), "chest": (0.25, 0, 0), "head": (-0.6, 0, 0),
                  "thigh.L": (-1.05, 0, 0), "shin.L": (0.95, 0, 0), "foot.L": (0.1, 0, 0),
                  "thigh.R": (0.65, 0, 0), "shin.R": (0.25, 0, 0), "foot.R": (0.4, 0, 0),
                  "_reach.R": (pos(fwd=-0.25, left=-0.4, up=0.95), way(left=-1.0, up=-0.5)),
                  "_blade.R": way(fwd=-1.0, up=-0.15),
                  "upper_arm.L": (0.75, 0, -0.35), "forearm.L": (-0.3, 0, 0)})
    action(arm, "storm_step", [
        (0, k()),
        (2, lunge_ss),
        (dash_end, {**lunge_ss, "spine": (0.45, 0, 0)}),
        (ss_end, k()),
    ], {0: EXPO_OUT, dash_end: QUART_OUT})

    # --- Upper-body gestures (played over running legs by the AnimationTree) --
    # chain_spark: the sword points at the first target (arcs leave its tip)
    point = k({"chest": (0.08, -0.35, 0), "spine": (0.04, -0.12, 0), "head": (0, 0.25, 0),
               "upper_arm.L": (0.3, 0, -0.35), "forearm.L": (-0.5, 0, 0),
               "_reach.R": (pos(fwd=0.45, left=-0.25, up=1.38), way(left=-1.0, up=-0.5)),
               "_blade.R": way(fwd=1.0, up=0.05)})
    action(arm, "chain_spark", [
        (0, k()),
        (4, point),
        (9, {**point, "chest": (0.06, -0.3, 0),
             "_reach.R": (pos(fwd=0.4, left=-0.26, up=1.42), way(left=-1.0, up=-0.5))}),
        (22, k()),
    ], {0: EXPO_OUT, 4: QUART_OUT, 9: QUART_OUT})
    # fracture_rune: blade raised, then stabbed toward the rune on the ground
    raised = k({"chest": (-0.1, 0, 0), "upper_arm.L": (-0.6, 0, -0.5), "forearm.L": (-0.8, 0, 0),
                "_reach.R": (pos(fwd=0.15, left=-0.3, up=1.95), way(fwd=-0.2, left=-1.0)),
                "_blade.R": way(fwd=0.25, up=1.0)})
    stab = k({"chest": (0.3, 0, 0), "spine": (0.15, 0, 0), "head": (-0.2, 0, 0),
              "_reach.R": (pos(fwd=0.5, left=-0.2, up=1.0), way(left=-1.0, up=-0.3)),
              "_blade.R": way(fwd=0.75, up=-0.65),
              "_reach.L": (pos(fwd=0.4, left=0.25, up=1.0), way(left=1.0, up=-0.5))})
    action(arm, "fracture_rune", [
        (0, k()),
        (3, raised),
        (6, stab),
        (12, {**stab, "chest": (0.26, 0, 0)}),
        (26, k()),
    ], {0: QUART_OUT, 3: EXPO_IN, 6: BACK_OUT, 12: QUART_OUT})

    # --- M07 talent abilities ------------------------------------------------
    # runic_guard (upper body): blade upright before the face, left fist out
    # with the rune palm forward: the ward is raised (Resonance barrier).
    ward = k({"chest": (-0.06, 0, 0), "head": (0.06, 0, 0),
              "_reach.R": (pos(fwd=0.34, left=-0.12, up=1.24), way(left=-1.0, up=-0.6)),
              "_blade.R": way(fwd=0.1, up=1.0),
              "_reach.L": (pos(fwd=0.46, left=0.2, up=1.36), way(left=1.0, up=-0.4)), "hand.L": (-0.4, 0, 0)})
    action(arm, "runic_guard", [
        (0, k()),
        (4, ward),
        (16, {**ward, "chest": (-0.03, 0, 0)}),
        (32, k()),
    ], {0: BACK_OUT, 16: QUART_OUT})
    # resonance_burst (full body, instant): a short gather, then arms flung
    # wide and the chest thrown up as the nova leaves; settle back to ready.
    burst = k({**crouch(0.06, RB_LEG), "chest": (-0.32, 0, 0), "spine": (-0.1, 0, 0), "head": (-0.25, 0, 0),
               "upper_arm.R": (-0.2, 0, 1.3), "forearm.R": (-0.2, 0, 0), "_blade.R": way(left=-1.0, up=0.4),
               "upper_arm.L": (-0.2, 0, -1.3), "forearm.L": (-0.2, 0, 0)})
    action(arm, "resonance_burst", [
        (0, k({**crouch(0.1, RB_LEG), "chest": (0.25, 0, 0), "upper_arm.R": (-0.3, 0, -0.1),
               "upper_arm.L": (-0.3, 0, 0.1)})),
        (3, burst),
        (12, {**burst, "chest": (-0.26, 0, 0)}),
        (32, k()),
    ], {0: EXPO_OUT, 3: BACK_OUT, 12: QUART_OUT})

    # --- Hit flinch: ADDITIVE (keys are offsets from rest, zero at both ends) --
    zero = {b: (0.0, 0.0, 0.0) for b in ("spine", "chest", "head", "upper_arm.L", "upper_arm.R")}
    action(arm, "flinch", [
        (0, zero),
        (3, {"spine": (-0.12, 0, 0), "chest": (-0.22, 0.08, 0), "head": (-0.25, 0, 0),
             "upper_arm.L": (0.25, 0, -0.15), "upper_arm.R": (0.15, 0, 0.1)}),
        (16, zero),
    ], {0: EXPO_OUT, 3: QUART_OUT})


# ---------------------------------------------------------------------------
# CINDER MARAUDER — hunched ash raider: jagged wedges, horns, heavy forearms
# ---------------------------------------------------------------------------

def build_marauder(sheets=False):
    rig.reset_scene()
    arm = rig.build_armature("marauder", humanoid_bones(
        hip=0.74, chest_top=1.32, shoulder_x=0.38, arm_len=0.64, leg_x=0.17, head_base=1.3, head_top=1.55, lean=-0.14))
    cm = PAL["cinder_marauder"]
    pm = rig.PartMesh(px_per_m=CHAR_DENSITY)
    hide = pm.paint(cm["hide"], 3, "hide")
    plate = pm.paint(cm["rust_plate"], 2, "plate")
    bone = pm.paint(cm["bone"], 2)
    wood = pm.paint(cm["wood"], 2)

    for side, x in (("L", 1.0), ("R", -1.0)):
        lx = 0.17 * x
        pm.loft("foot." + side, [(0.0, 0.12, 0.16, lx, -0.04), (0.12, 0.11, 0.12, lx, -0.01)], paint=hide)
        pm.loft("shin." + side, [(0.1, 0.1, 0.1, lx, 0), (0.4, 0.12, 0.12, lx, 0)], paint=hide)
        pm.loft("thigh." + side, [(0.4, 0.13, 0.13, lx, 0), (0.74, 0.15, 0.15, lx, 0)], paint=plate)
        sx = 0.38 * x
        pm.loft("upper_arm." + side, [(1.26, 0.1, 0.1, sx * 1.02, -0.14), (1.0, 0.1, 0.1, sx * 1.1, -0.14)], paint=hide)
        # heavy forearms + fists (the silhouette says "hits hard")
        pm.loft("forearm." + side, [(0.98, 0.1, 0.1, sx * 1.12, -0.14), (0.8, 0.14, 0.14, sx * 1.14, -0.14),
                                    (0.72, 0.13, 0.13, sx * 1.14, -0.14)], paint=hide)
        pm.box("hand." + side, (0.18, 0.2, 0.17), (sx * 1.14, -0.15, 0.64), paint=hide)
    # asymmetry: one huge rust shoulder plate (left), bone spikes on it
    pm.loft("upper_arm.L", [(1.16, 0.2, 0.2, 0.43, -0.14), (1.3, 0.22, 0.22, 0.43, -0.14),
                            (1.4, 0.12, 0.13, 0.4, -0.14)], paint=plate, sides=6)
    for dx, dz in ((0.0, 0.0), (0.09, -0.05), (-0.08, -0.04)):
        pm.loft("upper_arm.L", [(1.36 + dz, 0.035, 0.035, 0.43 + dx, -0.14), (1.58 + dz, 0.004, 0.004, 0.45 + dx * 1.3, -0.12)],
                sides=4, paint=bone)
    # hips hide skirt, hunched barrel torso
    pm.loft("hips", [(0.5, 0.26, 0.2, 0, 0), (0.78, 0.24, 0.19, 0, 0)], paint=hide, sides=6)
    pm.loft("spine", [(0.8, 0.26, 0.2, 0, -0.04), (1.02, 0.33, 0.25, 0, -0.08)], paint=hide)
    pm.loft("chest", [(1.0, 0.34, 0.26, 0, -0.08), (1.18, 0.4, 0.28, 0, -0.12), (1.34, 0.3, 0.22, 0, -0.15)], paint=plate)
    # low head thrust forward: bone jaw, horns, big ember eyes (glow slot)
    pm.loft("head", [(1.28, 0.16, 0.16, 0, -0.2), (1.42, 0.18, 0.17, 0, -0.22), (1.55, 0.13, 0.13, 0, -0.2)], paint=hide)
    pm.box("head", (0.34, 0.14, 0.1), (0, -0.33, 1.3), paint=bone)                          # jaw
    pm.box("head", (0.26, 0.05, 0.06), (0, -0.375, 1.43), mat_index=1)                      # eyes
    for x in (1.0, -1.0):
        pm.loft("head", [(1.48, 0.05, 0.05, 0.14 * x, -0.2), (1.62, 0.035, 0.035, 0.24 * x, -0.16),
                         (1.72, 0.004, 0.004, 0.3 * x, -0.08)], sides=4, paint=bone)          # horns
    # raider axe in the right fist: haft forward, blade = telegraph slot 2
    hx = -0.38 * 1.14
    pm.loft("hand.R", [(0.0, 0.028, 0.028, 0, 0), (0.85, 0.03, 0.03, 0, 0)], sides=6,
            center=(hx, -0.1, 0.64), rot=(1.5708, 0, 0), paint=wood)
    pm.box("hand.R", (0.07, 0.3, 0.34), (hx, -0.8, 0.72), mat_index=2)

    mat_body = rig.make_material("cm_body", "#FFFFFF")
    mat_eyes = rig.make_material("cm_eyes", cm["eyes"], emission_hex=cm["eyes"], strength=3.0)
    mat_blade = rig.make_material("cm_blade", "#9A9AA6")
    body = pm.to_object("cinder_marauder", [mat_body, mat_eyes, mat_blade], arm)

    marauder_clips(arm)
    finish(body, arm, "cinder_marauder", "cinder_marauder", (1, 2), sheets)


def marauder_clips(arm):
    windup = f(const_from("enemies/melee_rusher.gd", "WINDUP_TIME"))     # 33
    strike = f(const_from("enemies/melee_rusher.gd", "ATTACK_TIME"))     # 9
    recover = f(const_from("enemies/melee_rusher.gd", "RECOVER_TIME"))   # 42
    stance = {"spine": (0.18, 0, 0), "chest": (0.12, 0, 0), "head": (-0.25, 0, 0),
              "upper_arm.R": (-0.35, 0, 0.3), "forearm.R": (-0.5, 0, 0), "hand.R": (0.0, 0, 0),
              "upper_arm.L": (-0.2, 0, -0.25), "forearm.L": (-0.4, 0, 0), "hand.L": (0.0, 0, 0),
              "thigh.L": (-0.2, 0, 0), "thigh.R": (-0.2, 0, 0),
              "shin.L": (0.3, 0, 0), "shin.R": (0.3, 0, 0), "hips": {"rot": (0, 0, 0), "loc": (0, 0, 0)}}
    k = keyed(stance)
    action(arm, "idle", [
        (0, k()),
        (40, k({"chest": (0.16, 0.06, 0), "head": (-0.2, -0.1, 0)})),
        (80, k()),
    ], sheet=[0, 40])
    run_keys = []
    for frame, s in ((0, 1.0), (20, -1.0), (40, 1.0)):
        run_keys.append((frame, k({
            "thigh.L": (-0.2 - 0.6 * s, 0, 0), "thigh.R": (-0.2 + 0.6 * s, 0, 0),
            "shin.L": (0.3 + 0.5 * max(-s, 0), 0, 0), "shin.R": (0.3 + 0.5 * max(s, 0), 0, 0),
            "upper_arm.L": (0.35 * s, 0, -0.25), "upper_arm.R": (-0.35 - 0.3 * s, 0, 0.3),
            "spine": (0.3, 0.1 * s, 0)})))
    for frame in (10, 30):
        run_keys.append((frame, {"hips": {"rot": (0, 0, 0), "loc": (0, 0.05, 0)}}))
    run_keys.sort(key=lambda key: key[0])
    action(arm, "run", run_keys, sheet=[0, 10, 20, 30])
    # attack = windup (pose within ~60 %, then a trembling hold = the tell), a
    # 3-frame swing that CONTACTS exactly at `windup` (the gameplay hit fires on
    # entering ATTACK), follow-through over ATTACK_TIME, then recover.
    # The axe (haft modeled along -Y on hand.R, like the Runebreaker's sword)
    # is cocked back over the shoulder, then chopped so the blade lands on the
    # telegraph disc centre (1.1 m ahead, on the ground) at the contact frame.
    elbow_out = way(left=-1.0, up=-0.4)
    raised = k({"chest": (-0.12, 0, 0), "spine": (-0.05, 0, 0), "head": (-0.35, 0, 0), "upper_arm.L": (-0.6, 0, -0.5),
                "_reach.R": (pos(fwd=-0.05, left=-0.28, up=1.7), elbow_out),
                "_blade.R": way(fwd=-0.5, up=0.85)})
    tremble = {**raised, "chest": (-0.14, 0, 0),
               "_reach.R": (pos(fwd=-0.08, left=-0.29, up=1.72), elbow_out),
               "_blade.R": way(fwd=-0.55, up=0.83)}
    hold = int(windup * 0.6)
    slammed = k({"chest": (0.45, 0, 0), "spine": (0.35, 0, 0), "head": (-0.1, 0, 0), "upper_arm.L": (0.2, 0, -0.4),
                 "_reach.R": (pos(fwd=0.5, left=-0.2, up=0.75), elbow_out),
                 "_blade.R": way(fwd=0.55, up=-0.83)})
    follow = {**slammed, "chest": (0.5, 0, 0),
              "_reach.R": (pos(fwd=0.45, left=-0.2, up=0.62), elbow_out),
              "_blade.R": way(fwd=0.35, up=-0.94)}
    swing = windup - 3
    action(arm, "attack", [
        (0, k()),
        (hold, raised),
        (hold + (swing - hold) // 2, tremble),
        (swing, raised),
        (windup, slammed),
        (windup + strike, follow),
        (windup + strike + recover, k()),
    ], {hold: BACK_OUT, swing: EXPO_IN, windup + strike: QUART_OUT})
    # stagger: snapped back, arms flung, one step back; MEDIUM hits leave
    # STAGGER after 0.3 s (the CHASE state cuts the clip), HEAVY after 0.6 s.
    recoil = k({"spine": (-0.12, 0, 0), "chest": (-0.25, 0.15, 0), "head": (-0.45, 0.1, 0),
                "upper_arm.R": (0.35, 0, 0.7), "forearm.R": (-0.3, 0, 0),
                "upper_arm.L": (0.3, 0, -0.75), "forearm.L": (-0.3, 0, 0),
                "thigh.L": (-0.45, 0, 0), "shin.L": (0.55, 0, 0), "thigh.R": (0.05, 0, 0), "shin.R": (0.35, 0, 0)})
    action(arm, "stagger", [
        (0, k()),
        (3, recoil),
        (12, {**recoil, "chest": (-0.18, 0.1, 0), "head": (-0.35, 0.05, 0)}),
        (36, k()),
    ], {0: EXPO_OUT, 3: QUART_OUT, 12: QUART_OUT})


# ---------------------------------------------------------------------------
# DUSKWEAVER — legless void caster: tall cone robe, hood, hovering staff
# ---------------------------------------------------------------------------
# The staff floats beside the caster, weighted to the root bone: the staff
# orb stays the code-built telegraph + bolt origin at Visual (0.42, 1.7, 0)
# (= Blender (-0.42, 0, 1.7)), so no clip may move the staff.

ORB = (-0.42, 0.0, 1.7)


def caster_bones():
    bones = [
        ("root", None, (0, 0, 0), (0, 0, 0.25)),
        ("hips", "root", (0, 0, 0.95), (0, 0, 1.08)),
        ("hem", "hips", (0, 0, 0.62), (0, 0, 0.2)),          # hanging: lower robe sways
        ("spine", "hips", (0, 0, 1.08), (0, -0.01, 1.22)),
        ("chest", "spine", (0, -0.01, 1.22), (0, -0.03, 1.4)),
        ("head", "chest", (0, -0.03, 1.42), (0, -0.03, 1.7)),
    ]
    for side, x in (("L", 1.0), ("R", -1.0)):
        sx = 0.2 * x
        bones += [
            ("upper_arm." + side, "chest", (sx, -0.02, 1.36), (sx * 1.1, -0.02, 1.1)),
            ("forearm." + side, "upper_arm." + side, (sx * 1.1, -0.02, 1.1), (sx * 1.15, -0.02, 0.86)),
            ("hand." + side, "forearm." + side, (sx * 1.15, -0.02, 0.86), (sx * 1.15, -0.02, 0.78)),
        ]
    return bones


def build_duskweaver(sheets=False):
    rig.reset_scene()
    arm = rig.build_armature("duskweaver", caster_bones())
    dw = PAL["duskweaver"]
    pm = rig.PartMesh(px_per_m=CHAR_DENSITY)
    # Base 4: the caster fights at 7-12 m where fog lifts the ground; after
    # the 14-level luma posterize the robe must still clear it by >= 15 L*.
    robe = pm.paint(dw["robe"], 4, "cloth")
    robe_dark = pm.paint(dw["robe"], 2, "cloth")
    trim = pm.paint(dw["trim"], 1)
    void = pm.paint(dw["void"], 1)
    staff = pm.paint(dw["staff"], 2)

    # robe: tall cone. Upper skirt on the hips, a flared hem panel on its own
    # bone overlaps it so the hem can sway without opening a gap.
    pm.loft("hips", [(0.36, 0.36, 0.32, 0, 0.01), (0.7, 0.29, 0.25, 0, 0.0), (0.98, 0.22, 0.18, 0, 0.0)], paint=robe)
    pm.loft("hem", [(0.06, 0.5, 0.46, 0, 0.02), (0.24, 0.46, 0.42, 0, 0.02), (0.46, 0.37, 0.33, 0, 0.01)], paint=robe)
    pm.loft("hem", [(0.04, 0.51, 0.47, 0, 0.02), (0.1, 0.505, 0.465, 0, 0.02)], paint=trim)
    # narrow, slightly hunched torso + a lighter shoulder mantle (value read)
    pm.loft("spine", [(0.96, 0.21, 0.17, 0, 0.0), (1.22, 0.22, 0.17, 0, -0.01)], paint=robe_dark)
    pm.loft("chest", [(1.2, 0.23, 0.18, 0, -0.01), (1.34, 0.21, 0.16, 0, -0.02), (1.42, 0.14, 0.12, 0, -0.03)], paint=robe)
    pm.loft("chest", [(1.2, 0.3, 0.26, 0, 0.0), (1.33, 0.27, 0.23, 0, -0.01), (1.44, 0.16, 0.14, 0, -0.02)], paint=trim)
    # bell sleeves with trim cuffs; shadow hands
    for side, x in (("L", 1.0), ("R", -1.0)):
        sx = 0.2 * x
        pm.loft("upper_arm." + side, [(1.38, 0.07, 0.07, sx, -0.02), (1.1, 0.085, 0.085, sx * 1.1, -0.02)], paint=robe)
        pm.loft("forearm." + side, [(1.12, 0.085, 0.085, sx * 1.1, -0.02), (0.9, 0.13, 0.12, sx * 1.15, -0.02)], paint=robe)
        pm.loft("forearm." + side, [(0.93, 0.135, 0.125, sx * 1.15, -0.02), (0.87, 0.14, 0.13, sx * 1.15, -0.02)], paint=trim)
        pm.box("hand." + side, (0.07, 0.08, 0.1), (sx * 1.15, -0.03, 0.83), paint=void)
    # tall hood bending back at the tip, void face, violet eyes (glow slot)
    pm.loft("head", [(1.38, 0.17, 0.17, 0, 0.01), (1.52, 0.2, 0.21, 0, 0.0), (1.7, 0.15, 0.16, 0, 0.02),
                     (1.86, 0.06, 0.07, 0, 0.07), (1.96, 0.01, 0.01, 0, 0.12)], paint=robe_dark)
    pm.box("head", (0.2, 0.05, 0.17), (0, -0.185, 1.55), paint=void)
    for x in (1.0, -1.0):
        pm.box("head", (0.045, 0.02, 0.022), (0.045 * x, -0.212, 1.575), mat_index=1)
    # hovering staff (root bone): shaft, collar, three prongs cupping the orb
    ox, oy, _ = ORB
    pm.loft("root", [(0.3, 0.028, 0.028, ox, oy), (1.46, 0.032, 0.032, ox, oy)], sides=6, paint=staff)
    pm.loft("root", [(1.44, 0.055, 0.055, ox, oy), (1.52, 0.05, 0.05, ox, oy)], sides=6, paint=trim)
    for kk in range(3):
        a = 2.0 * math.pi * kk / 3.0 + 0.5
        pm.loft("root", [(1.5, 0.022, 0.022, ox + 0.05 * math.cos(a), oy + 0.05 * math.sin(a)),
                         (1.74, 0.014, 0.014, ox + 0.2 * math.cos(a), oy + 0.2 * math.sin(a)),
                         (1.86, 0.004, 0.004, ox + 0.16 * math.cos(a), oy + 0.16 * math.sin(a))],
                sides=4, paint=trim)

    mat_body = rig.make_material("dw_body", "#FFFFFF")
    mat_eyes = rig.make_material("dw_eyes", dw["eyes"], emission_hex=dw["eyes"], strength=3.0)
    body = pm.to_object("duskweaver", [mat_body, mat_eyes], arm)

    duskweaver_clips(arm)
    finish(body, arm, "duskweaver", "duskweaver", (1,), sheets)


def duskweaver_clips(arm):
    windup = f(const_from("enemies/ranged_caster.gd", "WINDUP_TIME"))    # 54
    staff_hand = way(fwd=-0.6, left=-0.6, up=-0.3)   # right elbow back and out
    # right hand hovers by the floating staff, left hand loose at the front
    stance = {"hips": {"rot": (0, 0, 0), "loc": (0, 0, 0)}, "hem": (0.0, 0, 0),
              "spine": (0.04, 0, 0), "chest": (0.06, 0, 0), "head": (-0.05, 0, 0),
              "_reach.R": (pos(fwd=0.07, left=-0.36, up=1.08), staff_hand), "hand.R": (0.0, 0, 0),
              "upper_arm.L": (-0.25, 0, -0.2), "forearm.L": (-0.6, 0, 0), "hand.L": (0.0, 0, 0)}
    k = keyed(stance)

    def hover(y):
        return {"hips": {"rot": (0, 0, 0), "loc": (0, y, 0)}}

    action(arm, "idle", [
        (0, k()),
        (30, k({**hover(0.02), "hem": (0.06, 0, 0.03), "chest": (0.03, 0, 0)})),
        (60, k({**hover(0.035), "chest": (0.08, 0, 0), "upper_arm.L": (-0.3, 0, -0.24)})),
        (90, k({**hover(0.015), "hem": (-0.04, 0, -0.03)})),
        (120, k()),
    ], sheet=[0, 30, 60, 90])
    # glide: one loop for chase, backpedal and recovery strafe (no legs), so it
    # leans only slightly; the hem flutters and trails.
    glide = k({"spine": (0.1, 0, 0), "chest": (0.1, 0, 0), "hem": (0.2, 0, 0),
               "upper_arm.L": (0.0, 0, -0.25), "_reach.R": (pos(fwd=0.03, left=-0.37, up=1.12), staff_hand)})
    action(arm, "glide", [
        (0, glide),
        (12, {**glide, **hover(0.02), "hem": (0.28, 0, 0.05)}),
        (24, glide),
        (36, {**glide, **hover(0.02), "hem": (0.16, 0, -0.05)}),
        (48, glide),
    ], sheet=[0, 12, 24, 36])
    # charge = the telegraph: gather, then both hands up by 60 % (right hand
    # toward the orb, left palm at the target), trembling hold until the bolt.
    orb_hand = way(left=-1.0, up=-0.5)
    palm_hand = way(left=1.0, up=-0.8)
    raised = k({**hover(0.06), "chest": (-0.2, 0, 0), "head": (-0.15, 0, 0), "hem": (0.15, 0, 0),
                "_reach.R": (pos(fwd=0.18, left=-0.3, up=1.5), orb_hand),
                "_reach.L": (pos(fwd=0.45, left=0.1, up=1.45), palm_hand), "hand.L": (-0.5, 0, 0)})
    hold = int(windup * 0.6)
    action(arm, "charge", [
        (0, k()),
        (8, k({"upper_arm.L": (0.25, 0, -0.35), "chest": (0.2, 0, 0), "head": (0.05, 0, 0), "hem": (-0.1, 0, 0),
               "_reach.R": (pos(fwd=-0.05, left=-0.33, up=0.98), staff_hand)})),
        (hold, raised),
        (hold + 11, {**raised, **hover(0.07), "chest": (-0.23, 0, 0),
                     "_reach.R": (pos(fwd=0.2, left=-0.31, up=1.53), orb_hand),
                     "_reach.L": (pos(fwd=0.47, left=0.09, up=1.47), palm_hand)}),
        (windup, raised),
    ], {8: QUART_OUT, hold: QUART_OUT})
    # cast: entering RECOVER (the bolt just left the orb) -> thrust, settle
    thrust = k({**hover(0.02), "chest": (0.28, 0, 0), "spine": (0.1, 0, 0), "head": (-0.2, 0, 0), "hem": (-0.2, 0, 0),
                "_reach.L": (pos(fwd=0.55, left=0.05, up=1.35), way(left=1.0, up=-1.0)), "hand.L": (-0.6, 0, 0),
                "_reach.R": (pos(fwd=0.15, left=-0.33, up=1.45), orb_hand)})
    action(arm, "cast", [
        (0, raised),
        (3, thrust),
        (10, {**thrust, "chest": (0.22, 0, 0)}),
        (24, k()),
    ], {0: EXPO_OUT, 10: QUART_OUT})
    recoil = k({"chest": (-0.35, 0.1, 0), "head": (-0.35, 0, 0), "spine": (-0.1, 0, 0),
                "_reach.R": (pos(fwd=-0.05, left=-0.62, up=1.2), way(fwd=-1.0, up=-0.3)),
                "_reach.L": (pos(fwd=-0.05, left=0.62, up=1.2), way(fwd=-1.0, up=-0.3)),
                "hem": (-0.35, 0, 0), **hover(-0.03)})
    action(arm, "stagger", [
        (0, k()),
        (3, recoil),
        (12, {**recoil, "chest": (-0.26, 0.06, 0), "hem": (-0.22, 0, 0)}),
        (36, k()),
    ], {0: EXPO_OUT, 3: QUART_OUT, 12: QUART_OUT})


# ---------------------------------------------------------------------------
# STONEHULK (Brute) — walking wall of weathered stone: slab torso, boulder
# shoulders, knuckles near the ground, moss on the up-facing planes
# ---------------------------------------------------------------------------

HULK_LEG = 0.7 - 0.1


def build_stonehulk(sheets=False):
    rig.reset_scene()
    arm = rig.build_armature("stonehulk", humanoid_bones(
        hip=0.7, chest_top=1.52, shoulder_x=0.46, arm_len=0.84, leg_x=0.22, head_base=1.46, head_top=1.7, lean=-0.12))
    sh = PAL["stonehulk"]
    pm = rig.PartMesh(px_per_m=CHAR_DENSITY)
    stone = pm.paint(sh["stone"], 3, "plate")
    stone_dark = pm.paint(sh["stone"], 2, "plate")
    stone_hi = pm.paint(sh["stone"], 4)
    moss = pm.paint(sh["moss"], 2, "hide")
    for side, x in (("L", 1.0), ("R", -1.0)):
        lx = 0.22 * x
        pm.box("foot." + side, (0.28, 0.36, 0.14), (lx, -0.05, 0.07), paint=stone_dark)
        pm.loft("shin." + side, [(0.1, 0.15, 0.15, lx, 0), (0.4, 0.17, 0.17, lx, 0)], sides=6, paint=stone_dark)
        pm.loft("thigh." + side, [(0.38, 0.17, 0.17, lx, 0), (0.72, 0.2, 0.2, lx, 0)], sides=6, paint=stone)
        sx = 0.46 * x
        pm.loft("upper_arm." + side, [(1.44, 0.13, 0.13, sx, -0.08), (1.06, 0.14, 0.14, sx * 1.1, -0.08)], sides=6, paint=stone)
        pm.loft("upper_arm." + side, [(1.34, 0.19, 0.19, sx * 1.02, -0.08), (1.5, 0.2, 0.2, sx * 1.02, -0.08),
                                      (1.6, 0.1, 0.1, sx * 1.0, -0.08)], sides=6, paint=stone_hi)       # boulder shoulder
        pm.loft("upper_arm." + side, [(1.58, 0.11, 0.11, sx, -0.08), (1.63, 0.06, 0.06, sx, -0.08)], sides=6, paint=moss)
        pm.loft("forearm." + side, [(1.04, 0.15, 0.15, sx * 1.1, -0.08), (0.8, 0.2, 0.19, sx * 1.14, -0.08),
                                    (0.7, 0.19, 0.18, sx * 1.14, -0.08)], sides=6, paint=stone)
        pm.box("hand." + side, (0.3, 0.3, 0.28), (sx * 1.14, -0.1, 0.55), paint=stone_dark)             # fists
    pm.loft("hips", [(0.55, 0.36, 0.26, 0, 0), (0.82, 0.38, 0.28, 0, 0)], sides=6, paint=stone_dark)
    pm.loft("spine", [(0.8, 0.38, 0.28, 0, -0.02), (1.05, 0.44, 0.32, 0, -0.06)], sides=8, paint=stone)
    pm.loft("chest", [(1.02, 0.46, 0.34, 0, -0.06), (1.3, 0.52, 0.36, 0, -0.1), (1.52, 0.4, 0.3, 0, -0.14)],
            sides=8, paint=stone)
    pm.loft("chest", [(1.45, 0.41, 0.3, 0, -0.12), (1.57, 0.28, 0.21, 0, -0.14)], sides=8, paint=moss)  # moss cap
    for sx in (-1.0, 1.0):
        pm.box("chest", (0.3, 0.12, 0.42), (0.17 * sx, 0.3, 1.32), rot=(-0.3, 0.0, 0.2 * sx), paint=stone_hi)  # back slabs
    pm.loft("head", [(1.44, 0.15, 0.14, 0, -0.26), (1.58, 0.16, 0.15, 0, -0.28), (1.68, 0.11, 0.1, 0, -0.26)],
            sides=6, paint=stone_dark)
    pm.box("head", (0.32, 0.1, 0.07), (0, -0.4, 1.61), paint=stone_hi)                                  # brow ridge
    pm.box("head", (0.22, 0.03, 0.035), (0, -0.425, 1.567), mat_index=1)                                # ember slit
    mats = [rig.make_material("sh_body", "#FFFFFF"),
            rig.make_material("sh_eyes", sh["eyes"], emission_hex=sh["eyes"], strength=3.0)]
    body = pm.to_object("stonehulk", mats, arm)
    stonehulk_clips(arm)
    finish(body, arm, "stonehulk", "stonehulk", (1,), sheets)


def stonehulk_clips(arm):
    windup = f(const_from("enemies/brute.gd", "WINDUP_TIME"))     # 54
    recover = f(const_from("enemies/brute.gd", "RECOVER_TIME"))   # 78
    stance = {**crouch(0.05, HULK_LEG), "spine": (0.15, 0, 0), "chest": (0.12, 0, 0), "head": (-0.3, 0, 0),
              "upper_arm.L": (-0.1, 0, -0.2), "upper_arm.R": (-0.1, 0, 0.2),
              "forearm.L": (-0.3, 0, 0), "forearm.R": (-0.3, 0, 0), "hand.L": (0.0, 0, 0), "hand.R": (0.0, 0, 0)}
    k = keyed(stance)
    action(arm, "idle", [
        (0, k()),
        (45, k({"chest": (0.17, 0.04, 0), "head": (-0.26, -0.06, 0), "upper_arm.L": (-0.14, 0, -0.23),
                "upper_arm.R": (-0.06, 0, 0.17)})),
        (90, k()),
    ], sheet=[0, 45])
    # heavy stomp: 36 frames per two steps, hips sway over the planted leg
    run_keys = []
    for frame, s in ((0, 1.0), (18, -1.0), (36, 1.0)):
        base = crouch(0.07, HULK_LEG, (0.0, 0.0, 0.07 * s))
        run_keys.append((frame, k({**base,
            "thigh.L": (-0.37 - 0.5 * s, 0, 0), "thigh.R": (-0.37 + 0.5 * s, 0, 0),
            "shin.L": (0.74 + 0.4 * max(-s, 0), 0, 0), "shin.R": (0.74 + 0.4 * max(s, 0), 0, 0),
            "upper_arm.L": (0.28 * s, 0, -0.22), "upper_arm.R": (-0.28 * s, 0, 0.22),
            "spine": (0.22, 0.08 * s, 0), "chest": (0.14, 0.06 * s, 0)})))
    for frame in (9, 27):
        run_keys.append((frame, {"hips": {"rot": (0, 0, 0), "loc": (0, -0.02, 0)}}))
    run_keys.sort(key=lambda key: key[0])
    action(arm, "run", run_keys, sheet=[0, 9, 18, 27])
    # slam: both fists overhead by 60 % of the windup, a trembling hold, then a
    # 4-frame drop that CONTACTS at `windup` (the hit fires entering RECOVER),
    # fists on the ground ahead, a heavy recovery back to stance.
    raised = k({**crouch(0.02, HULK_LEG), "spine": (-0.1, 0, 0), "chest": (-0.3, 0, 0), "head": (-0.15, 0, 0),
                "_reach.L": (pos(fwd=0.12, left=0.5, up=2.2), way(left=1.0, up=-0.2)),
                "_reach.R": (pos(fwd=0.12, left=-0.5, up=2.2), way(left=-1.0, up=-0.2))})
    tremble = {**raised, "chest": (-0.34, 0, 0),
               "_reach.L": (pos(fwd=0.08, left=0.51, up=2.23), way(left=1.0, up=-0.2)),
               "_reach.R": (pos(fwd=0.08, left=-0.51, up=2.23), way(left=-1.0, up=-0.2))}
    hold = int(windup * 0.6)
    swing = windup - 4
    slammed = k({**crouch(0.16, HULK_LEG, (0.25, 0, 0)), "spine": (0.35, 0, 0), "chest": (0.5, 0, 0), "head": (-0.2, 0, 0),
                 "_reach.L": (pos(fwd=0.95, left=0.22, up=0.24), way(left=1.0, up=0.3)),
                 "_reach.R": (pos(fwd=0.95, left=-0.22, up=0.24), way(left=-1.0, up=0.3))})
    action(arm, "slam", [
        (0, k()),
        (hold, raised),
        (hold + (swing - hold) // 2, tremble),
        (swing, raised),
        (windup, slammed),
        (windup + 12, {**slammed, "chest": (0.46, 0, 0)}),
        (windup + recover, k()),
    ], {hold: BACK_OUT, swing: EXPO_IN, windup + 12: QUART_OUT})
    recoil = k({"spine": (-0.1, 0, 0), "chest": (-0.22, 0.12, 0), "head": (-0.45, 0.1, 0),
                "upper_arm.L": (0.3, 0, -0.5), "upper_arm.R": (0.3, 0, 0.5)})
    action(arm, "stagger", [
        (0, k()), (4, recoil), (14, {**recoil, "chest": (-0.16, 0.08, 0)}), (40, k()),
    ], {0: EXPO_OUT, 4: QUART_OUT, 14: QUART_OUT})


# ---------------------------------------------------------------------------
# VEILSTALKER (Assassin) — low, lean skirmisher: slate cloak, bone mask,
# trailing scarf, twin daggers. Never the player's teal.
# ---------------------------------------------------------------------------

STALK_LEG = 0.74 - 0.1


def build_veilstalker(sheets=False):
    rig.reset_scene()
    bones = humanoid_bones(hip=0.74, chest_top=1.24, shoulder_x=0.19, arm_len=0.56, leg_x=0.11,
                           head_base=1.24, head_top=1.46, lean=-0.08)
    bones.append(("scarf", "chest", (0.05, 0.12, 1.24), (0.06, 0.16, 1.02)))   # hanging: sways behind
    bones.append(("scarf_tip", "scarf", (0.06, 0.16, 1.02), (0.07, 0.2, 0.8)))  # second joint: the tail bends
    arm = rig.build_armature("veilstalker", bones)
    vs = PAL["veilstalker"]
    pm = rig.PartMesh(px_per_m=CHAR_DENSITY)
    cloak = pm.paint(vs["cloak"], 4, "cloth")
    cloak_dark = pm.paint(vs["cloak"], 3, "cloth")
    wraps = pm.paint(vs["wraps"], 1, "cloth")
    mask = pm.paint(vs["mask"], 1)
    blade = pm.paint(vs["blade"], 1)
    for side, x in (("L", 1.0), ("R", -1.0)):
        lx = 0.11 * x
        pm.box("foot." + side, (0.1, 0.22, 0.08), (lx, -0.05, 0.04), paint=wraps)
        pm.loft("shin." + side, [(0.1, 0.055, 0.055, lx, 0), (0.4, 0.066, 0.066, lx, 0)], sides=6, paint=wraps)
        pm.loft("thigh." + side, [(0.4, 0.07, 0.07, lx, 0), (0.74, 0.088, 0.088, lx, 0)], sides=6, paint=cloak_dark)
        sx = 0.19 * x
        pm.loft("upper_arm." + side, [(1.2, 0.052, 0.052, sx, -0.08), (0.95, 0.056, 0.056, sx * 1.1, -0.08)], paint=cloak_dark)
        pm.loft("forearm." + side, [(0.95, 0.052, 0.052, sx * 1.1, -0.08), (0.72, 0.056, 0.056, sx * 1.14, -0.08)], paint=wraps)
        hx = sx * 1.14
        pm.box("hand." + side, (0.07, 0.08, 0.08), (hx, -0.1, 0.66), paint=wraps)
        # dagger along -Y from the fist (like the Marauder's axe haft)
        pm.loft("hand." + side, [(0.0, 0.012, 0.035, 0, 0), (0.36, 0.008, 0.024, 0, 0), (0.44, 0.002, 0.004, 0, 0)],
                sides=4, center=(hx, -0.12, 0.66), rot=(1.5708, 0, 0), paint=blade)
    pm.loft("hips", [(0.62, 0.17, 0.13, 0, 0), (0.8, 0.16, 0.12, 0, 0)], sides=6, paint=wraps)
    pm.box("hips", (0.26, 0.04, 0.34), (0, -0.13, 0.5), paint=cloak)                                  # tabard front
    pm.box("hips", (0.26, 0.04, 0.3), (0, 0.13, 0.52), paint=cloak_dark)                              # and back
    pm.loft("spine", [(0.8, 0.15, 0.11, 0, -0.03), (1.02, 0.17, 0.12, 0, -0.05)], paint=cloak)
    pm.loft("chest", [(1.0, 0.18, 0.13, 0, -0.05), (1.18, 0.2, 0.14, 0, -0.07), (1.26, 0.13, 0.1, 0, -0.08)], paint=cloak)
    pm.loft("chest", [(1.18, 0.15, 0.13, 0, -0.08), (1.3, 0.13, 0.12, 0, -0.08)], paint=wraps)       # scarf wrap
    pm.box("scarf", (0.12, 0.03, 0.24), (0.055, 0.14, 1.13), paint=wraps)                              # scarf tail
    pm.box("scarf_tip", (0.11, 0.03, 0.24), (0.065, 0.18, 0.91), taper=0.7, paint=wraps)
    pm.loft("head", [(1.24, 0.12, 0.13, 0, -0.09), (1.36, 0.13, 0.14, 0, -0.1), (1.48, 0.1, 0.11, 0, -0.08),
                     (1.55, 0.03, 0.04, 0, -0.03)], paint=cloak)                                          # cowl
    pm.box("head", (0.16, 0.04, 0.14), (0, -0.225, 1.36), paint=mask)                                 # bone mask
    pm.box("head", (0.11, 0.02, 0.022), (0, -0.248, 1.385), mat_index=1)                             # eye slit
    mats = [rig.make_material("vs_body", "#FFFFFF"),
            rig.make_material("vs_eyes", vs["eyes"], emission_hex=vs["eyes"], strength=3.0)]
    body = pm.to_object("veilstalker", mats, arm)
    veilstalker_clips(arm)
    finish(body, arm, "veilstalker", "veilstalker", (1,), sheets)


def veilstalker_clips(arm):
    windup = f(const_from("enemies/assassin.gd", "WINDUP_TIME"))   # 21
    guard_R = (pos(fwd=0.28, left=-0.22, up=0.92), way(left=-1.0, up=-0.4))
    guard_L = (pos(fwd=0.24, left=0.22, up=0.95), way(left=1.0, up=-0.4))
    fwd_blade = way(fwd=1.0, up=0.15)
    stance = {**crouch(0.12, STALK_LEG), "spine": (0.28, 0, 0), "chest": (0.1, 0, 0), "head": (-0.36, 0, 0),
              "_reach.R": guard_R, "_reach.L": guard_L, "_blade.R": fwd_blade, "_blade.L": fwd_blade,
              "scarf": (0.25, 0, 0), "scarf_tip": (0.25 * 0.6, 0, 0 * 0.5)}
    k = keyed(stance)
    action(arm, "idle", [
        (0, k()),
        (30, k({**crouch(0.14, STALK_LEG), "chest": (0.14, -0.06, 0), "head": (-0.3, 0.08, 0), "scarf": (0.35, 0, 0.08), "scarf_tip": (0.35 * 0.6, 0, 0.08 * 0.5)})),
        (60, k()),
    ], sheet=[0, 30])

    def run_cycle(name, length, amp, lean, scarf):
        keys = []
        half = length // 2
        for frame, s in ((0, 1.0), (half, -1.0), (length, 1.0)):
            keys.append((frame, k({**crouch(0.14, STALK_LEG),
                "thigh.L": (-0.4 - amp * s, 0, 0), "thigh.R": (-0.4 + amp * s, 0, 0),
                "shin.L": (0.8 + 0.7 * max(-s, 0), 0, 0), "shin.R": (0.8 + 0.7 * max(s, 0), 0, 0),
                "spine": (lean, 0.08 * s, 0), "chest": (0.1, 0.1 * s, 0), "head": (-0.5, -0.1 * s, 0),
                "_reach.R": (pos(fwd=0.05 - 0.12 * s, left=-0.24, up=0.88), way(left=-1.0, up=-0.2)),
                "_reach.L": (pos(fwd=0.05 + 0.12 * s, left=0.24, up=0.88), way(left=1.0, up=-0.2)),
                "_blade.R": way(fwd=-0.2, up=-1.0), "_blade.L": way(fwd=-0.2, up=-1.0),
                "scarf": (scarf, 0, 0.1 * s), "scarf_tip": (scarf * 0.6, 0, 0.1 * s * 0.5)})))
        for frame in (half // 2, half + half // 2):
            keys.append((frame, {"hips": {"rot": (0, 0, 0), "loc": (0, -0.1, 0)}}))
        keys.sort(key=lambda key: key[0])
        action(arm, name, keys, sheet=[0, half // 2, half])

    run_cycle("run", 24, 0.75, 0.5, 0.9)      # 6 m/s chase
    run_cycle("dash", 20, 0.9, 0.7, 1.2)      # 9.5 m/s dash-in: lower, longer
    # strafe: side shuffle (legs abduct in turn), torso square to the player
    strafe = []
    for frame, s in ((0, 1.0), (15, -1.0), (30, 1.0)):
        strafe.append((frame, k({**crouch(0.16, STALK_LEG),
            "thigh.L": (-0.45, 0, -0.35 * max(s, 0)), "thigh.R": (-0.45, 0, 0.35 * max(-s, 0)),
            "chest": (0.12, 0, -0.06 * s), "scarf": (0.4, 0, 0.3 * s), "scarf_tip": (0.4 * 0.6, 0, 0.3 * s * 0.5)})))
    for frame in (7, 22):
        strafe.append((frame, {"hips": {"rot": (0, 0, 0), "loc": (0, -0.08, 0)}}))
    strafe.sort(key=lambda key: key[0])
    action(arm, "strafe", strafe, sheet=[0, 7, 15, 22])
    # retreat: backstep facing the player, blades up in guard
    retreat = []
    for frame, s in ((0, 1.0), (18, -1.0), (36, 1.0)):
        retreat.append((frame, k({**crouch(0.1, STALK_LEG),
            "thigh.L": (-0.4 + 0.45 * s, 0, 0), "thigh.R": (-0.4 - 0.45 * s, 0, 0),
            "shin.L": (0.75 + 0.4 * max(s, 0), 0, 0), "shin.R": (0.75 + 0.4 * max(-s, 0), 0, 0),
            "spine": (0.05, 0, 0), "chest": (-0.05, 0.05 * s, 0), "head": (-0.2, 0, 0),
            "_reach.R": (pos(fwd=0.3, left=-0.2, up=1.1), way(left=-1.0, up=-0.6)),
            "_reach.L": (pos(fwd=0.34, left=0.18, up=1.05), way(left=1.0, up=-0.6)),
            "scarf": (0.1, 0, 0.1 * s), "scarf_tip": (0.1 * 0.6, 0, 0.1 * s * 0.5)})))
    action(arm, "retreat", retreat, sheet=[0, 18])
    # stab: coil (blades drawn back by the ears) for the windup, thrust both
    # blades through the 1.0 m disc ahead at `windup`, then spring back.
    coiled = k({**crouch(0.2, STALK_LEG), "spine": (0.35, 0, 0), "chest": (-0.1, 0, 0), "head": (-0.45, 0, 0),
                "_reach.R": (pos(fwd=-0.12, left=-0.2, up=1.28), way(left=-1.0, up=-0.5)),
                "_reach.L": (pos(fwd=-0.12, left=0.2, up=1.28), way(left=1.0, up=-0.5)),
                "_blade.R": way(fwd=1.0, up=0.2), "_blade.L": way(fwd=1.0, up=0.2), "scarf": (0.5, 0, 0), "scarf_tip": (0.5 * 0.6, 0, 0 * 0.5)})
    thrust = k({**crouch(0.18, STALK_LEG, (0.2, 0, 0)), "spine": (0.5, 0, 0), "chest": (0.25, 0, 0), "head": (-0.55, 0, 0),
                "thigh.L": (-1.0, 0, 0), "shin.L": (0.9, 0, 0), "thigh.R": (0.1, 0, 0), "shin.R": (0.7, 0, 0),
                "_reach.R": (pos(fwd=0.62, left=-0.1, up=0.95), way(left=-1.0, up=-0.2)),
                "_reach.L": (pos(fwd=0.62, left=0.1, up=0.98), way(left=1.0, up=-0.2)),
                "_blade.R": way(fwd=1.0, up=-0.1), "_blade.L": way(fwd=1.0, up=-0.1), "scarf": (1.2, 0, 0), "scarf_tip": (1.2 * 0.6, 0, 0 * 0.5)})
    action(arm, "stab", [
        (0, k()),
        (int(windup * 0.6), coiled),
        (windup - 2, {**coiled, "chest": (-0.14, 0, 0)}),
        (windup, thrust),
        (windup + 5, {**thrust, "chest": (0.3, 0, 0)}),
        (windup + 22, k()),
    ], {int(windup * 0.6): BACK_OUT, windup - 2: EXPO_IN, windup + 5: QUART_OUT})
    recoil = k({"spine": (-0.15, 0, 0), "chest": (-0.3, 0.2, 0), "head": (-0.55, 0.15, 0), "scarf": (1.0, 0, 0.3), "scarf_tip": (1.0 * 0.6, 0, 0.3 * 0.5),
                "_reach.R": (pos(fwd=-0.05, left=-0.4, up=1.05), way(fwd=-1.0, up=-0.3)),
                "_reach.L": (pos(fwd=-0.05, left=0.4, up=1.05), way(fwd=-1.0, up=-0.3))})
    action(arm, "stagger", [
        (0, k()), (3, recoil), (10, {**recoil, "chest": (-0.22, 0.12, 0)}), (30, k()),
    ], {0: EXPO_OUT, 3: QUART_OUT, 10: QUART_OUT})


# ---------------------------------------------------------------------------
# HOLLOW WARDEN — Spire construct: square slabs, bronze trim, a tower shield
# fused to the chest (front = "not here"), the teal rune core exposed on the
# back (= "hit here"); bladed forearms for the spin.
# ---------------------------------------------------------------------------

WARDEN_LEG = 0.78 - 0.1


def build_warden(sheets=False):
    rig.reset_scene()
    arm = rig.build_armature("warden", humanoid_bones(
        hip=0.78, chest_top=1.5, shoulder_x=0.36, arm_len=0.7, leg_x=0.18, head_base=1.48, head_top=1.72, lean=0.0))
    hw = PAL["hollow_warden"]
    pm = rig.PartMesh(px_per_m=CHAR_DENSITY)
    plate = pm.paint(hw["plate"], 3, "plate")
    plate_dark = pm.paint(hw["plate"], 2, "plate")
    plate_hi = pm.paint(hw["plate"], 4)
    bronze = pm.paint(hw["bronze"], 2)
    for side, x in (("L", 1.0), ("R", -1.0)):
        lx = 0.18 * x
        pm.box("foot." + side, (0.2, 0.3, 0.12), (lx, -0.04, 0.06), paint=plate_dark)
        pm.loft("shin." + side, [(0.1, 0.1, 0.1, lx, 0), (0.44, 0.12, 0.12, lx, 0)], sides=4, paint=plate_dark)
        pm.loft("thigh." + side, [(0.42, 0.13, 0.13, lx, 0), (0.78, 0.15, 0.15, lx, 0)], sides=4, paint=plate)
        sx = 0.36 * x
        pm.loft("upper_arm." + side, [(1.44, 0.1, 0.1, sx, 0), (1.1, 0.1, 0.1, sx * 1.1, 0)], sides=4, paint=plate)
        pm.loft("upper_arm." + side, [(1.36, 0.17, 0.16, sx * 1.05, 0), (1.52, 0.16, 0.15, sx * 1.05, 0)], sides=4, paint=plate_hi)
        pm.loft("forearm." + side, [(1.1, 0.1, 0.1, sx * 1.1, 0), (0.82, 0.12, 0.12, sx * 1.14, 0)], sides=4, paint=plate)
        pm.box("forearm." + side, (0.05, 0.34, 0.26), (sx * 1.14 + 0.1 * x, 0.02, 0.96), paint=bronze)  # blade fin
        pm.box("hand." + side, (0.14, 0.14, 0.14), (sx * 1.14, 0, 0.74), paint=plate_dark)
    pm.box("hips", (0.5, 0.34, 0.24), (0, 0, 0.82), paint=plate_dark)
    pm.loft("spine", [(0.9, 0.34, 0.26, 0, 0), (1.12, 0.38, 0.28, 0, 0)], sides=4, paint=plate)
    pm.loft("chest", [(1.1, 0.4, 0.3, 0, 0), (1.4, 0.44, 0.31, 0, 0), (1.52, 0.34, 0.26, 0, 0)], sides=4, paint=plate)
    # tower shield fused to the chest: covers the whole front
    pm.box("chest", (0.8, 0.1, 1.02), (0, -0.37, 1.08), paint=plate_hi)
    pm.box("chest", (0.86, 0.08, 0.08), (0, -0.39, 1.6), paint=bronze)
    pm.box("chest", (0.86, 0.08, 0.08), (0, -0.39, 0.58), paint=bronze)
    pm.box("chest", (0.08, 0.06, 0.8), (0, -0.43, 1.09), paint=bronze)                                # shield boss rib
    # exposed rune core on the back in a bronze frame (glow slot 1)
    pm.box("chest", (0.36, 0.06, 0.4), (0, 0.31, 1.24), paint=bronze)
    pm.box("chest", (0.24, 0.05, 0.28), (0, 0.34, 1.24), mat_index=1)
    pm.box("head", (0.26, 0.26, 0.28), (0, -0.02, 1.62), paint=plate_dark)
    pm.box("head", (0.3, 0.06, 0.06), (0, -0.05, 1.77), paint=bronze)                                 # crest
    pm.box("head", (0.18, 0.02, 0.03), (0, -0.155, 1.63), mat_index=1)                                # eye slit
    core = PAL["hollow_warden"]["core"]
    mats = [rig.make_material("hw_body", "#FFFFFF"), rig.make_material("hw_core", core, emission_hex=core, strength=3.0)]
    body = pm.to_object("hollow_warden", mats, arm)
    warden_clips(arm)
    finish(body, arm, "hollow_warden", "hollow_warden", (1,), sheets)


def warden_clips(arm):
    windup = f(const_from("enemies/hollow_warden.gd", "WINDUP_TIME"))    # 42
    recover = f(const_from("enemies/hollow_warden.gd", "RECOVER_TIME"))  # 66
    stance = {**crouch(0.04, WARDEN_LEG), "chest": (0.04, 0, 0), "head": (-0.04, 0, 0),
              "upper_arm.L": (-0.15, 0, -0.3), "upper_arm.R": (-0.15, 0, 0.3),
              "forearm.L": (-0.35, 0, 0), "forearm.R": (-0.35, 0, 0), "hand.L": (0.0, 0, 0), "hand.R": (0.0, 0, 0)}
    k = keyed(stance)
    action(arm, "idle", [
        (0, k()), (45, k({"chest": (0.07, 0.03, 0), "head": (-0.02, -0.05, 0)})), (90, k()),
    ], sheet=[0, 45])
    walk = []
    for frame, s in ((0, 1.0), (20, -1.0), (40, 1.0)):
        walk.append((frame, k({**crouch(0.05, WARDEN_LEG, (0, 0, 0.05 * s)),
            "thigh.L": (-0.3 - 0.4 * s, 0, 0), "thigh.R": (-0.3 + 0.4 * s, 0, 0),
            "shin.L": (0.6 + 0.35 * max(-s, 0), 0, 0), "shin.R": (0.6 + 0.35 * max(s, 0), 0, 0),
            "upper_arm.L": (0.15 * s, 0, -0.3), "upper_arm.R": (-0.15 * s, 0, 0.3), "chest": (0.06, 0.05 * s, 0)})))
    action(arm, "run", walk, sheet=[0, 20])
    # windup: brace low, arms flung wide and back, the chest coils against the
    # Visual's own -0.7 rad pre-turn (the spin itself stays gameplay-driven)
    spread = {"upper_arm.L": (0.35, 0, -1.35), "upper_arm.R": (0.35, 0, 1.35),
              "forearm.L": (-0.1, 0, 0), "forearm.R": (-0.1, 0, 0)}
    coiled = k({**crouch(0.14, WARDEN_LEG), "chest": (0.1, 0.45, 0), "spine": (0.05, 0.2, 0), **spread})
    action(arm, "windup", [
        (0, k()),
        (int(windup * 0.6), coiled),
        (windup, {**coiled, "chest": (0.12, 0.5, 0)}),
    ], {int(windup * 0.6): BACK_OUT})
    # spin (entering RECOVER): arms straight out while Visual turns 2pi in
    # 0.3 s, then fold back over the rest of the recovery
    out = {"upper_arm.L": (0.0, 0, -1.55), "upper_arm.R": (0.0, 0, 1.55), "forearm.L": (0.0, 0, 0), "forearm.R": (0.0, 0, 0)}
    spun = k({**crouch(0.1, WARDEN_LEG), "chest": (0.0, -0.3, 0), "spine": (0.0, -0.1, 0), **out})
    action(arm, "spin", [
        (0, coiled),
        (3, spun),
        (18, {**spun, "chest": (0.02, -0.1, 0)}),
        (18 + recover - 18, k()),
    ], {0: EXPO_OUT, 18: QUART_OUT})
    recoil = k({"chest": (-0.18, 0.1, 0), "head": (-0.3, 0.05, 0), "upper_arm.L": (0.25, 0, -0.6),
                "upper_arm.R": (0.25, 0, 0.6)})
    action(arm, "stagger", [
        (0, k()), (4, recoil), (14, {**recoil, "chest": (-0.12, 0.06, 0)}), (40, k()),
    ], {0: EXPO_OUT, 4: QUART_OUT, 14: QUART_OUT})


# ---------------------------------------------------------------------------
# ASHVEIN COLOSSUS — Highlands mini-boss, authored at base size (the code
# scales Visual x1.7): ash-grey basalt hulk, horned, ember veins + back
# crystals on slot 2 (code-owned: brighter on enrage), ember eyes on slot 1
# ---------------------------------------------------------------------------

COLOSSUS_LEG = 0.74 - 0.1


def build_colossus(sheets=False):
    rig.reset_scene()
    arm = rig.build_armature("colossus", humanoid_bones(
        hip=0.74, chest_top=1.56, shoulder_x=0.5, arm_len=0.86, leg_x=0.24, head_base=1.48, head_top=1.76, lean=-0.14))
    av = PAL["ashvein"]
    pm = rig.PartMesh(px_per_m=CHAR_DENSITY)
    basalt = pm.paint(av["basalt"], 3, "plate")
    basalt_dark = pm.paint(av["basalt"], 2, "plate")
    basalt_hi = pm.paint(av["basalt"], 4)
    char = pm.paint(av["char"], 1)
    VEIN = 2
    for side, x in (("L", 1.0), ("R", -1.0)):
        lx = 0.24 * x
        pm.box("foot." + side, (0.3, 0.4, 0.15), (lx, -0.06, 0.075), paint=basalt_dark)
        pm.loft("shin." + side, [(0.1, 0.16, 0.16, lx, 0), (0.42, 0.19, 0.19, lx, 0)], sides=6, paint=basalt_dark)
        pm.loft("thigh." + side, [(0.4, 0.19, 0.19, lx, 0), (0.76, 0.22, 0.22, lx, 0)], sides=6, paint=basalt)
        pm.box("thigh." + side, (0.03, 0.02, 0.26), (lx + 0.06 * x, -0.2, 0.58), rot=(0, 0.3 * x, 0), mat_index=VEIN)
        sx = 0.5 * x
        pm.loft("upper_arm." + side, [(1.48, 0.15, 0.15, sx, -0.08), (1.08, 0.16, 0.16, sx * 1.1, -0.08)], sides=6, paint=basalt)
        pm.loft("upper_arm." + side, [(1.36, 0.22, 0.22, sx * 1.02, -0.08), (1.54, 0.23, 0.23, sx * 1.02, -0.08),
                                      (1.66, 0.12, 0.12, sx, -0.08)], sides=6, paint=basalt_hi)
        pm.loft("forearm." + side, [(1.06, 0.17, 0.17, sx * 1.1, -0.08), (0.8, 0.23, 0.22, sx * 1.14, -0.08),
                                    (0.7, 0.22, 0.21, sx * 1.14, -0.08)], sides=6, paint=basalt)
        pm.box("forearm." + side, (0.03, 0.02, 0.3), (sx * 1.14, -0.31, 0.88), rot=(0, 0.25 * x, 0), mat_index=VEIN)
        pm.box("hand." + side, (0.34, 0.34, 0.3), (sx * 1.14, -0.1, 0.56), paint=basalt_dark)
    pm.loft("hips", [(0.56, 0.4, 0.29, 0, 0), (0.84, 0.42, 0.31, 0, 0)], sides=6, paint=basalt_dark)
    pm.loft("spine", [(0.82, 0.42, 0.31, 0, -0.02), (1.08, 0.48, 0.35, 0, -0.06)], sides=8, paint=basalt)
    pm.loft("chest", [(1.05, 0.5, 0.37, 0, -0.06), (1.34, 0.56, 0.39, 0, -0.1), (1.56, 0.44, 0.33, 0, -0.14)],
            sides=8, paint=basalt)
    for dx, dz, r in ((-0.18, 1.3, 0.35), (0.14, 1.18, -0.3), (0.0, 1.42, 0.1)):
        pm.box("chest", (0.03, 0.02, 0.34), (dx, -0.47, dz), rot=(0, r, 0), mat_index=VEIN)               # chest veins
    # fire crystals erupting from the back (slot 2: glow with the veins)
    for dx, dz, tilt in ((-0.24, 1.46, (0.5, 0.35)), (0.26, 1.5, (0.45, -0.4)), (0.0, 1.62, (0.75, 0.0))):
        pm.loft("chest", [(0.0, 0.07, 0.07, 0, 0), (0.32, 0.06, 0.06, 0, 0), (0.5, 0.005, 0.005, 0, 0)], sides=5,
                center=(dx, 0.26, dz), rot=(-tilt[0], tilt[1], 0), mat_index=VEIN)
    pm.loft("head", [(1.46, 0.17, 0.16, 0, -0.28), (1.6, 0.18, 0.17, 0, -0.3), (1.72, 0.12, 0.11, 0, -0.28)],
            sides=6, paint=basalt_dark)
    pm.box("head", (0.36, 0.14, 0.1), (0, -0.44, 1.49), paint=char)                                      # jaw
    pm.box("head", (0.24, 0.03, 0.04), (0, -0.46, 1.6), mat_index=1)                                     # eyes
    for x in (1.0, -1.0):
        pm.loft("head", [(1.62, 0.06, 0.06, 0.16 * x, -0.26), (1.72, 0.045, 0.045, 0.3 * x, -0.32),
                         (1.8, 0.02, 0.02, 0.38 * x, -0.44), (1.84, 0.004, 0.004, 0.36 * x, -0.54)], sides=4,
                paint=char)                                                                                  # horns
    mats = [rig.make_material("av_body", "#FFFFFF"),
            rig.make_material("av_eyes", av["eyes"], emission_hex=av["eyes"], strength=3.0),
            rig.make_material("av_veins", av["vein"], emission_hex=av["vein"], strength=1.0)]
    body = pm.to_object("ashvein_colossus", mats, arm)
    colossus_clips(arm)
    finish(body, arm, "ashvein_colossus", "ashvein_colossus", (1, 2), sheets)


def colossus_clips(arm):
    windup = f(0.9)          # base slam windup (enraged playback runs 0.9 / 0.65 faster)
    recover = f(1.2)
    charge_windup = f(0.8)
    stance = {**crouch(0.06, COLOSSUS_LEG), "spine": (0.16, 0, 0), "chest": (0.12, 0, 0), "head": (-0.32, 0, 0),
              "upper_arm.L": (-0.1, 0, -0.22), "upper_arm.R": (-0.1, 0, 0.22),
              "forearm.L": (-0.3, 0, 0), "forearm.R": (-0.3, 0, 0), "hand.L": (0.0, 0, 0), "hand.R": (0.0, 0, 0)}
    k = keyed(stance)
    action(arm, "idle", [
        (0, k()),
        (50, k({"chest": (0.18, 0.05, 0), "head": (-0.26, -0.08, 0), "upper_arm.L": (-0.15, 0, -0.26)})),
        (100, k()),
    ], sheet=[0, 50])
    walk = []
    for frame, s in ((0, 1.0), (24, -1.0), (48, 1.0)):
        walk.append((frame, k({**crouch(0.08, COLOSSUS_LEG, (0, 0, 0.08 * s)),
            "thigh.L": (-0.4 - 0.45 * s, 0, 0), "thigh.R": (-0.4 + 0.45 * s, 0, 0),
            "shin.L": (0.8 + 0.4 * max(-s, 0), 0, 0), "shin.R": (0.8 + 0.4 * max(s, 0), 0, 0),
            "upper_arm.L": (0.25 * s, 0, -0.22), "upper_arm.R": (-0.25 * s, 0, 0.22),
            "spine": (0.24, 0.1 * s, 0), "chest": (0.14, 0.08 * s, 0)})))
    for frame in (12, 36):
        walk.append((frame, {"hips": {"rot": (0, 0, 0), "loc": (0, -0.03, 0)}}))
    walk.sort(key=lambda key: key[0])
    action(arm, "run", walk, sheet=[0, 12, 24, 36])
    raised = k({**crouch(0.02, COLOSSUS_LEG), "spine": (-0.12, 0, 0), "chest": (-0.32, 0, 0), "head": (-0.12, 0, 0),
                "_reach.L": (pos(fwd=0.14, left=0.52, up=2.26), way(left=1.0, up=-0.2)),
                "_reach.R": (pos(fwd=0.14, left=-0.52, up=2.26), way(left=-1.0, up=-0.2))})
    hold = int(windup * 0.6)
    swing = windup - 4
    slammed = k({**crouch(0.18, COLOSSUS_LEG, (0.25, 0, 0)), "spine": (0.36, 0, 0), "chest": (0.52, 0, 0), "head": (-0.2, 0, 0),
                 "_reach.L": (pos(fwd=1.0, left=0.24, up=0.25), way(left=1.0, up=0.3)),
                 "_reach.R": (pos(fwd=1.0, left=-0.24, up=0.25), way(left=-1.0, up=0.3))})
    action(arm, "slam", [
        (0, k()), (hold, raised), (hold + (swing - hold) // 2, {**raised, "chest": (-0.36, 0, 0)}),
        (swing, raised), (windup, slammed), (windup + 12, {**slammed, "chest": (0.48, 0, 0)}),
        (windup + recover, k()),
    ], {hold: BACK_OUT, swing: EXPO_IN, windup + 12: QUART_OUT})
    # charge windup: head down, horns forward, arms swept back, a foot paws
    lowered = k({**crouch(0.14, COLOSSUS_LEG, (0.3, 0, 0)), "spine": (0.4, 0, 0), "chest": (0.3, 0, 0), "head": (-0.05, 0, 0),
                 "upper_arm.L": (0.7, 0, -0.35), "upper_arm.R": (0.7, 0, 0.35)})
    action(arm, "charge_windup", [
        (0, k()), (14, lowered),
        (26, {**lowered, "thigh.R": (-0.1, 0, 0), "shin.R": (0.6, 0, 0)}),
        (36, lowered), (charge_windup, {**lowered, "chest": (0.34, 0, 0)}),
    ], {14: BACK_OUT})
    charge = []
    for frame, s in ((0, 1.0), (12, -1.0), (24, 1.0)):
        charge.append((frame, k({**crouch(0.12, COLOSSUS_LEG, (0.35, 0, 0)), "spine": (0.45, 0.05 * s, 0),
            "chest": (0.3, 0, 0), "head": (-0.05, 0, 0),
            "thigh.L": (-0.7 - 0.7 * s, 0, 0), "thigh.R": (-0.7 + 0.7 * s, 0, 0),
            "shin.L": (0.7 + 0.8 * max(-s, 0), 0, 0), "shin.R": (0.7 + 0.8 * max(s, 0), 0, 0),
            "upper_arm.L": (0.7 + 0.3 * s, 0, -0.35), "upper_arm.R": (0.7 - 0.3 * s, 0, 0.35)})))
    action(arm, "charge", charge, sheet=[0, 12])
    dazed = k({"spine": (0.3, 0, 0), "chest": (0.25, 0, 0), "head": (0.2, 0.3, 0.1),
               "upper_arm.L": (-0.05, 0, -0.12), "upper_arm.R": (-0.05, 0, 0.12)})
    action(arm, "stun", [
        (0, dazed), (30, {**dazed, "head": (0.25, -0.3, -0.1), "chest": (0.28, -0.08, 0)}), (60, dazed),
    ], sheet=[0, 30])
    roar = k({"spine": (-0.15, 0, 0), "chest": (-0.35, 0, 0), "head": (-0.6, 0, 0),
              "upper_arm.L": (-0.3, 0, -1.1), "upper_arm.R": (-0.3, 0, 1.1), "forearm.L": (-0.6, 0, 0), "forearm.R": (-0.6, 0, 0)})
    action(arm, "roar", [(0, k()), (12, roar), (44, {**roar, "head": (-0.55, 0.1, 0)}), (70, k())],
           {12: BACK_OUT, 44: QUART_OUT})
    recoil = k({"spine": (-0.1, 0, 0), "chest": (-0.2, 0.1, 0), "head": (-0.4, 0.1, 0),
                "upper_arm.L": (0.3, 0, -0.5), "upper_arm.R": (0.3, 0, 0.5)})
    action(arm, "stagger", [(0, k()), (4, recoil), (14, {**recoil, "chest": (-0.15, 0.06, 0)}), (40, k())],
           {0: EXPO_OUT, 4: QUART_OUT, 14: QUART_OUT})


# ---------------------------------------------------------------------------
# THE VESSEL — Spire boss, authored at base size (code scales Visual x1.4):
# a floating lavender crystal with a violet heart, crystal blade arms, four
# orbiting shards. Phase 2 bursts its three body segments apart.
# ---------------------------------------------------------------------------

def vessel_bones():
    bones = [
        ("root", None, (0, 0, 0), (0, 0, 0.25)),
        ("body", "root", (0, 0, 0.6), (0, 0, 1.2)),
        ("low", "body", (0, 0, 1.0), (0, 0, 0.4)),       # hanging point segment
        ("mid", "body", (0, 0, 1.2), (0, 0, 1.6)),
        ("top", "mid", (0, 0, 1.6), (0, 0, 2.1)),
        ("orbit", "root", (0, 0, 1.3), (0, 0, 1.6)),
    ]
    for side, x in (("L", 1.0), ("R", -1.0)):
        bones += [
            ("arm." + side, "mid", (0.52 * x, 0, 1.75), (0.6 * x, 0, 1.25)),
            ("blade." + side, "arm." + side, (0.6 * x, 0, 1.25), (0.62 * x, 0, 0.6)),
        ]
    for i in range(4):
        a = i * math.tau / 4 + 0.4
        c = (math.cos(a) * 0.95, math.sin(a) * 0.95, 1.05 + 0.25 * (i % 2))
        bones.append(("shard.%d" % i, "orbit", c, (c[0], c[1], c[2] + 0.3)))
    return bones


def build_vessel(sheets=False):
    rig.reset_scene()
    arm = rig.build_armature("vessel", vessel_bones())
    vp = PAL["vessel"]
    pm = rig.PartMesh(px_per_m=CHAR_DENSITY)
    crystal = pm.paint(vp["crystal"], 3)
    crystal_dark = pm.paint(vp["crystal"], 2)
    crystal_hi = pm.paint(vp["crystal"], 4)
    stone = pm.paint(vp["stone"], 1, "plate")
    pm.loft("low", [(0.35, 0.02, 0.02, 0, 0), (0.7, 0.2, 0.18, 0, 0), (1.0, 0.36, 0.32, 0, 0)], sides=6, paint=crystal_dark)
    pm.loft("mid", [(1.02, 0.38, 0.34, 0, 0), (1.3, 0.44, 0.4, 0, 0), (1.58, 0.42, 0.38, 0, 0)], sides=6, paint=crystal)
    pm.box("mid", (0.5, 0.12, 0.34), (0, -0.36, 1.3), paint=stone)                                    # heart cage
    pm.loft("mid", [(1.18, 0.02, 0.02, 0, -0.44), (1.3, 0.13, 0.1, 0, -0.44), (1.42, 0.02, 0.02, 0, -0.44)],
            sides=4, mat_index=1)                                                                       # violet heart
    pm.loft("top", [(1.6, 0.4, 0.36, 0, 0), (1.84, 0.34, 0.3, 0, 0), (2.02, 0.14, 0.12, 0, 0)], sides=6, paint=crystal)
    for dx, dy, h in ((0.0, 0.0, 0.75), (0.2, 0.08, 0.5), (-0.2, 0.06, 0.55), (0.06, -0.18, 0.42)):
        pm.loft("top", [(1.92, 0.07, 0.07, dx, dy), (1.92 + h * 0.7, 0.05, 0.05, dx * 1.2, dy * 1.2),
                        (1.92 + h, 0.004, 0.004, dx * 1.35, dy * 1.35)], sides=5, paint=crystal_hi)       # crown
    for side, x in (("L", 1.0), ("R", -1.0)):
        pm.loft("arm." + side, [(1.8, 0.13, 0.12, 0.54 * x, 0), (1.52, 0.11, 0.1, 0.58 * x, 0),
                                (1.24, 0.08, 0.08, 0.6 * x, 0)], sides=5, paint=stone)
        pm.loft("blade." + side, [(1.26, 0.06, 0.12, 0.6 * x, 0), (0.9, 0.05, 0.16, 0.62 * x, -0.02),
                                  (0.5, 0.004, 0.02, 0.62 * x, -0.06)], sides=4, paint=crystal_hi)
    for i in range(4):
        a = i * math.tau / 4 + 0.4
        cx, cy, cz = math.cos(a) * 0.95, math.sin(a) * 0.95, 1.05 + 0.25 * (i % 2)
        pm.loft("shard.%d" % i, [(cz - 0.2, 0.01, 0.01, cx, cy), (cz, 0.08, 0.07, cx, cy), (cz + 0.28, 0.01, 0.01, cx, cy)],
                sides=4, phase=a, paint=crystal)
    heart = vp["heart"]
    mats = [rig.make_material("vv_body", "#FFFFFF"), rig.make_material("vv_heart", heart, emission_hex=heart, strength=3.0)]
    body = pm.to_object("vessel", mats, arm)
    vessel_clips(arm)
    finish(body, arm, "vessel", "vessel", (1,), sheets)


def vessel_clips(arm):
    windup = f(const_from("enemies/shattered_vessel.gd", "SLAM_WINDUP"))   # 48
    stance = {"root": (0, 0, 0), "body": {"rot": (0, 0, 0), "loc": (0, 0, 0)}, "mid": (0, 0, 0), "top": (0, 0, 0),
              "low": {"rot": (0, 0, 0), "loc": (0, 0, 0)}, "orbit": (0, 0, 0),
              "arm.L": (-0.1, 0, -0.25), "arm.R": (-0.1, 0, 0.25), "blade.L": (-0.2, 0, 0), "blade.R": (-0.2, 0, 0)}
    for i in range(4):
        stance["shard.%d" % i] = {"rot": (0, 0, 0), "loc": (0, 0, 0)}
    k = keyed(stance)

    def orbit(turn, spread=0.0, lift=0.0):
        """Orbit bone turn; each shard spins once per orbit and is pushed out
        radially by `spread` (upright bone: local (x, y, z) = world (x, z, -y))."""
        pose = {"orbit": (0, 0, turn)}
        for i in range(4):
            a = i * math.tau / 4 + 0.4
            pose["shard.%d" % i] = {"rot": (0, turn, 0),
                                    "loc": (math.cos(a) * spread, lift * (1 if i % 2 else -1), -math.sin(a) * spread)}
        return pose

    def float_keys(length, extra=None, spread=0.0):
        keys = []
        for j, frac in enumerate((0.0, 1 / 3, 2 / 3, 1.0)):
            bob = 0.05 * math.sin(frac * math.tau)
            keys.append((int(round(length * frac)), k({**(extra or {}), **orbit(frac * math.tau, spread, 0.04 * math.cos(frac * math.tau)),
                "body": {"rot": (0.03 * math.sin(frac * math.tau), 0, 0), "loc": (0, bob, 0)}})))
        return keys

    action(arm, "idle", float_keys(120), {0: ("LINEAR", None), 40: ("LINEAR", None), 80: ("LINEAR", None)},
           sheet=[0, 40, 80])
    action(arm, "run", float_keys(60, {"body": {"rot": (0.2, 0, 0), "loc": (0, 0, 0)}, "arm.L": (0.3, 0, -0.3),
                                       "arm.R": (0.3, 0, 0.3)}), {0: ("LINEAR", None), 20: ("LINEAR", None), 40: ("LINEAR", None)},
           sheet=[0, 20, 40])
    raised = k({"mid": (-0.25, 0, 0), "top": (-0.15, 0, 0), "arm.L": (-2.4, 0, -0.35), "arm.R": (-2.4, 0, 0.35),
                "blade.L": (-0.3, 0, 0), "blade.R": (-0.3, 0, 0), "body": {"rot": (-0.1, 0, 0), "loc": (0, 0.15, 0)}})
    slammed = k({"mid": (0.45, 0, 0), "top": (0.2, 0, 0), "arm.L": (-1.2, 0, -0.15), "arm.R": (-1.2, 0, 0.15),
                 "blade.L": (-0.2, 0, 0), "blade.R": (-0.2, 0, 0), "body": {"rot": (0.3, 0, 0), "loc": (0, -0.25, 0)}})
    hold = int(windup * 0.6)
    action(arm, "slam", [
        (0, k()), (hold, raised), (windup - 4, {**raised, "mid": (-0.3, 0, 0)}), (windup, slammed),
        (windup + 12, {**slammed, "mid": (0.4, 0, 0)}), (windup + 66, k()),
    ], {hold: BACK_OUT, windup - 4: EXPO_IN, windup + 12: QUART_OUT})
    burst = {"top": (-0.2, 0, 0), "low": {"rot": (0.3, 0, 0), "loc": (0, 0.35, 0)},
             "mid": (0, 0, 0), "arm.L": (-0.6, 0, -0.9), "arm.R": (-0.6, 0, 0.9), **orbit(0.6, 0.5, 0.1)}
    action(arm, "shatter", [
        (0, k()), (6, k({**burst, "body": {"rot": (0, 0, 0), "loc": (0, 0.3, 0)}})),
        (60, k({**burst, "body": {"rot": (0, 0, 0), "loc": (0, 0.2, 0)}})),
    ], {0: EXPO_OUT, 6: QUART_OUT})
    spread_extra = {"top": (-0.2, 0, 0), "low": {"rot": (0.3, 0, 0), "loc": (0, 0.35, 0)},
                    "arm.L": (-0.6, 0, -0.9), "arm.R": (-0.6, 0, 0.9)}
    p2 = float_keys(120, spread_extra, 0.5)
    p2 = [(fr, {**pose, "body": {"rot": pose["body"]["rot"], "loc": (0, 0.2 + pose["body"]["loc"][1], 0)}}) for fr, pose in p2]
    action(arm, "p2_idle", p2, {0: ("LINEAR", None), 40: ("LINEAR", None), 80: ("LINEAR", None)}, sheet=[0, 40])
    fan = k({**spread_extra, "arm.L": (-1.5, 0, -0.5), "arm.R": (-1.5, 0, 0.5), "mid": (0.2, 0, 0),
             "body": {"rot": (0.1, 0, 0), "loc": (0, 0.2, 0)}, **orbit(0.0, 0.5)})
    action(arm, "fan", [(0, k({**spread_extra, "body": {"rot": (0, 0, 0), "loc": (0, 0.2, 0)}, **orbit(0.0, 0.5)})),
                        (4, fan), (24, k({**spread_extra, "body": {"rot": (0, 0, 0), "loc": (0, 0.2, 0)}, **orbit(0.0, 0.5)}))],
           {4: QUART_OUT})
    recoil = k({"mid": (-0.3, 0.2, 0), "top": (-0.2, 0, 0), "arm.L": (0.4, 0, -0.6), "arm.R": (0.4, 0, 0.6),
                "body": {"rot": (-0.2, 0, 0), "loc": (0, 0.05, 0)}})
    action(arm, "stagger", [(0, k()), (4, recoil), (14, {**recoil, "mid": (-0.2, 0.1, 0)}), (40, k())],
           {0: EXPO_OUT, 4: QUART_OUT, 14: QUART_OUT})


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    want_sheets = "--sheets" in args
    builders = {"runebreaker": build_runebreaker, "marauder": build_marauder, "duskweaver": build_duskweaver,
                "stonehulk": build_stonehulk, "veilstalker": build_veilstalker, "warden": build_warden,
                "colossus": build_colossus, "vessel": build_vessel}
    only = [a for a in args if not a.startswith("--")] or list(builders)
    for name in only:
        builders[name](want_sheets)
    print("characters v2 done.")
