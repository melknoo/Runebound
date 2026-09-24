"""M06 A4 rig & animation spike: a throwaway biped that proves the pipeline
(Blender 5.2 headless -> rigid-skinned GLB with 60 fps actions -> Godot).

Run:  & "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python tools/modelgen/spike_rig.py
Output: assets/models/spike/spike_biped.glb
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import rig  # noqa: E402

rig.reset_scene()
spec = rig.load_spec()
iron = spec["palettes"]["runebreaker"]["iron"][2]           # #3A404D
glow = spec["color_roles"]["resonance"]["body"]             # #FFC34D

BONES = [
    ("root", None, (0, 0, 0), (0, 0, 0.25)),
    ("hips", "root", (0, 0, 0.9), (0, 0, 1.05)),
    ("spine", "hips", (0, 0, 1.05), (0, 0, 1.3)),
    ("chest", "spine", (0, 0, 1.3), (0, 0, 1.5)),
    ("head", "chest", (0, 0, 1.55), (0, 0, 1.85)),
]
for side, x in (("L", 1.0), ("R", -1.0)):
    BONES += [
        (f"upper_arm.{side}", "chest", (0.3 * x, 0, 1.45), (0.36 * x, 0, 1.15)),
        (f"forearm.{side}", f"upper_arm.{side}", (0.36 * x, 0, 1.15), (0.38 * x, 0, 0.92)),
        (f"hand.{side}", f"forearm.{side}", (0.38 * x, 0, 0.92), (0.38 * x, 0, 0.8)),
        (f"thigh.{side}", "hips", (0.13 * x, 0, 0.9), (0.13 * x, 0, 0.5)),
        (f"shin.{side}", f"thigh.{side}", (0.13 * x, 0, 0.5), (0.13 * x, 0, 0.1)),
        (f"foot.{side}", f"shin.{side}", (0.13 * x, 0, 0.1), (0.13 * x, -0.16, 0.05)),
    ]
arm = rig.build_armature("spike", BONES)

body = rig.PartMesh(px_per_m=spec["texel_density"]["character_px_per_m"], atlas_px=64)
body.box("hips", (0.46, 0.3, 0.26), (0, 0, 0.95), taper=1.1)
body.box("spine", (0.5, 0.32, 0.3), (0, 0, 1.2), taper=1.25)
body.box("chest", (0.66, 0.4, 0.32), (0, 0, 1.42), taper=0.9)
body.box("chest", (0.16, 0.06, 0.2), (0, -0.21, 1.4), mat_index=1)     # sigil (glow)
body.box("head", (0.3, 0.32, 0.3), (0, -0.02, 1.7), taper=0.85)
body.box("head", (0.06, 0.3, 0.12), (0, 0, 1.9))                      # crest
for side, x in (("L", 1.0), ("R", -1.0)):
    body.box(f"upper_arm.{side}", (0.34, 0.38, 0.24), (0.36 * x, 0, 1.46))  # pauldron
    body.box(f"upper_arm.{side}", (0.15, 0.17, 0.3), (0.35 * x, 0, 1.25))
    body.box(f"forearm.{side}", (0.17, 0.19, 0.26), (0.37 * x, 0, 1.02), taper=1.2)
    body.box(f"hand.{side}", (0.16, 0.18, 0.14), (0.38 * x, 0, 0.84))       # gauntlet
    body.box(f"thigh.{side}", (0.19, 0.24, 0.42), (0.13 * x, 0, 0.7))
    body.box(f"shin.{side}", (0.17, 0.21, 0.38), (0.13 * x, 0, 0.3))
    body.box(f"foot.{side}", (0.2, 0.34, 0.12), (0.13 * x, -0.05, 0.06))   # boot

mat_body = rig.make_material("body", iron)
mat_glow = rig.make_material("glow", glow, emission_hex=glow, strength=3.0)
body.to_object("spike_biped", [mat_body, mat_glow], arm)

# idle: 1 s breathing loop
idle = rig.make_action(arm, "idle", [
    (0, {"chest": (0.0, 0, 0), "upper_arm.L": (0, 0, -0.08), "upper_arm.R": (0, 0, 0.08)}),
    (30, {"chest": (-0.05, 0, 0), "upper_arm.L": (0, 0, -0.12), "upper_arm.R": (0, 0, 0.12)}),
    (60, {"chest": (0.0, 0, 0), "upper_arm.L": (0, 0, -0.08), "upper_arm.R": (0, 0, 0.08)}),
])

# run: 0.6 s cycle, counter-swinging arms, small hip bob (no root motion)
run_keys = []
for frame, s in ((0, 1.0), (18, -1.0), (36, 1.0)):
    run_keys.append((frame, {
        "thigh.L": (0.7 * s, 0, 0), "thigh.R": (-0.7 * s, 0, 0),
        "shin.L": (-0.5 * max(s, 0) - 0.1, 0, 0), "shin.R": (-0.5 * max(-s, 0) - 0.1, 0, 0),
        "upper_arm.L": (-0.6 * s, 0, -0.1), "upper_arm.R": (0.6 * s, 0, 0.1),
        "hips": {"loc": (0, 0, 0.0)},
    }))
for frame in (9, 27):
    run_keys.append((frame, {"hips": {"loc": (0, 0, 0.04)}}))
run_keys.sort(key=lambda k: k[0])
run = rig.make_action(arm, "run", run_keys)

# attack: anticipation (frame 5), contact at frame 7 (= Rune Cleave startup
# 0.12 s at 60 fps), BACK overshoot into follow-through, recover by frame 30
attack = rig.make_action(arm, "attack", [
    (0, {"upper_arm.R": (0, 0, 0.08), "chest": (0, 0, 0)}),
    (5, {"upper_arm.R": (-2.2, 0, 0.5), "chest": (0, 0, 0.35)}),
    (7, {"upper_arm.R": (0.2, 0, -0.9), "chest": (0, 0, -0.35)}),
    (14, {"upper_arm.R": (0.6, 0, -1.2), "chest": (0, 0, -0.45)}),
    (30, {"upper_arm.R": (0, 0, 0.08), "chest": (0, 0, 0)}),
], interpolation={5: ("EXPO", "EASE_IN"), 7: ("BACK", "EASE_OUT"), 14: ("QUART", "EASE_OUT")})

out = os.path.join(rig.ROOT, "assets", "models", "spike", "spike_biped.glb")
rig.export_glb(out, active_action=idle, arm_obj=arm)
print("spike: actions =", [a.name for a in __import__("bpy").data.actions])
