r"""Rig v3 build (Blender 5.2 headless): AI body + script kit -> game GLB + atlas.

  <src>/raw.glb      compacted AI generation (ai_gen.py -> ai_ingest.py)
  <src>/fit.json     yaw, height, landmarks (data, reviewed; --detect proposes)
  -> assets/models/chars/<glb>.glb + assets/textures/char/<atlas>_atlas.png
     (or --out DIR for a preview that leaves assets/ alone)

The skeleton, clips and Godot contract are the legacy ones from
generate_characters_v2 (see lib/fit.py): one skinned mesh, slots 0 body /
1 glow / 2 weapon, clip names + lengths unchanged.

  blender --background --factory-startup --python-exit-code 1 --python tools/modelgen/ai_fit.py --
      runebreaker [--src DIR] [--detect] [--out DIR] [--sheets]
<src> defaults to tools/modelgen/ai_src/<char>/. --detect writes a fit.json
proposal (if none exists) and <src>/landmarks.png, then stops.
"""
import json
import os
import sys

import bpy

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import generate_characters_v2 as gen  # noqa: E402
from lib import aimesh, atlas, fit, rig, texbake  # noqa: E402

PX_PER_M = 128          # art_spec texel_density.character_px_per_m (Rig v3)
ATLAS_SIZES = (256, 512, 1024)
KIT_TRIS = 400          # reserve for the script kit inside the budget

AI = {
    "runebreaker": dict(rig="runebreaker", glb="runebreaker", atlas="runebreaker", palette="runebreaker",
                        bones=lambda: gen.humanoid_bones(**gen.RB_BONES), kit=gen.runebreaker_kit,
                        clips=gen.runebreaker_clips, skip=(1,), budget=10000, height=1.97),
    "marauder": dict(rig="marauder", glb="cinder_marauder", atlas="cinder_marauder", palette="cinder_marauder",
                     bones=lambda: gen.humanoid_bones(**gen.CM_BONES), kit=gen.marauder_kit,
                     clips=gen.marauder_clips, skip=(1, 2), budget=6000, height=1.85),
}


def _read_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def build(char, src=None, detect=False, out=None, sheets=False):
    cfg = AI[char]
    src = src or os.path.join(HERE, "ai_src", char)
    fit_path = os.path.join(src, "fit.json")
    rig.reset_scene()
    gen.POSERS.clear()
    gen.SHEETS.clear()
    bones = cfg["bones"]()
    have_fit = os.path.exists(fit_path)
    fj = _read_json(fit_path) if have_fit else {"yaw_deg": 0.0, "height": cfg["height"]}
    obj = aimesh.load(os.path.join(src, "raw.glb"), cfg["glb"] + "_ai")
    dropped = aimesh.clean(obj)
    aimesh.normalize(obj, fj["yaw_deg"], fj["height"])
    tris_in, tris_out = aimesh.decimate(obj, cfg["budget"] - KIT_TRIS)
    print("ai_fit: %s  %d -> %d tris, %d specks dropped" % (char, tris_in, tris_out, dropped))

    if detect:
        if not have_fit:
            fj["landmarks"] = fit.detect(obj, bones)
            fit.write_json(fit_path, fj)
            print("ai_fit: proposal ->", fit_path)
        fit.landmark_sheet(obj, fj["landmarks"], os.path.join(src, "landmarks.png"))
        return None

    fit_arm = fit.fit_armature(cfg["rig"], bones, fj["landmarks"])
    method, leftovers = fit.auto_weights(obj, fit_arm)
    ratios = fit.warp(obj, fit_arm, bones)
    aimesh.smooth(obj)
    arm = rig.build_armature(cfg["rig"], bones)

    pm = rig.PartMesh(px_per_m=PX_PER_M)
    mats = cfg["kit"](pm, fit.snapper(obj))
    kit = pm.to_object(cfg["glb"] + "_kit", mats, arm)
    body = fit.join_body(obj, kit, mats, cfg["glb"], arm)
    cfg["clips"](arm)

    tex_dir = out or gen.TEX_DIR
    glb_dir = out or os.path.join(rig.ROOT, "assets", "models", "chars")
    os.makedirs(tex_dir, exist_ok=True)
    atlas_path = os.path.join(tex_dir, cfg["atlas"] + "_atlas.png")
    size = atlas.unwrap(body, PX_PER_M, sizes=ATLAS_SIZES, upscale=False)
    base_lin, ao = texbake.transfer(body, size)
    ramps = texbake.ramps_of(gen.PAL[cfg["palette"]])
    base = texbake.quantize(base_lin, ao, ramps)
    atlas.bake(body, size, atlas_path, skip_material_indices=cfg["skip"], base=base)
    body.data.uv_layers.remove(body.data.uv_layers[aimesh.SRC_UV])
    rig.export_glb(os.path.join(glb_dir, cfg["glb"] + ".glb"), active_action=bpy.data.actions["idle"], arm_obj=arm)

    report = fit.verify(body, arm, bones, cfg["budget"], atlas_path, [h for r in ramps for h in r])
    src_rel = src if os.path.splitdrive(src)[0].lower() != os.path.splitdrive(rig.ROOT)[0].lower() \
        else os.path.relpath(src, rig.ROOT)
    report.update({"char": char, "src": src_rel.replace("\\", "/"), "weights": method,
                   "nearest_bone_fill": leftovers, "length_ratios": ratios, "atlas_px": size,
                   "px_per_m": PX_PER_M})
    rep_dir = os.path.join(gen.SHEET_DIR, cfg["glb"])
    os.makedirs(rep_dir, exist_ok=True)
    fit.write_json(os.path.join(out or rep_dir, "ai_fit_report.json"), report)
    bad = {k: v for k, v in ratios.items() if not 0.8 <= v <= 1.25}
    print("ai_fit: %s ok=%s tris=%d atlas=%d weights=%s off-palette=%s ratios-out=%s" % (
        char, report["ok"], report["tris"], size, method, report.get("atlas_off_palette"), bad))
    if sheets:
        from lib import sheets as sheet_lib
        sheet_lib.render(body, arm, atlas_path, gen.SHEETS.get(arm.name, []), os.path.join(out or gen.SHEET_DIR,
                                                                                          cfg["glb"]))
    return report


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {}
    names = []
    it = iter(args)
    for a in it:
        if a in ("--src", "--out"):
            opts[a[2:]] = next(it)
        elif a.startswith("--"):
            opts[a[2:]] = True
        else:
            names.append(a)
    for name in names or sorted(AI):
        build(name, src=opts.get("src"), detect=bool(opts.get("detect")), out=opts.get("out"),
              sheets=bool(opts.get("sheets")))
    print("ai_fit done.")


if __name__ == "__main__":
    main()
