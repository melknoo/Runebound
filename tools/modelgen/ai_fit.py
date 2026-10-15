r"""Rig v3 build (Blender 5.2 headless): AI body + script kit -> game GLB + atlas.

  <src>/raw.glb      compacted AI generation (ai_gen.py -> ai_ingest.py)
  <src>/fit.json     yaw, height, landmarks (data, reviewed; --detect proposes)
  -> assets/models/chars/<glb>.glb + assets/textures/char/<atlas>_atlas.png
     (or --out DIR for a preview that leaves assets/ alone)

The skeleton, clips and Godot contract are the legacy ones from
generate_characters_v2 (see lib/fit.py): one skinned mesh, slots 0 body /
1 glow / 2 weapon, clip names + lengths unchanged.

  blender --background --factory-startup --python-exit-code 1 --python tools/modelgen/ai_fit.py --
      runebreaker [--look rare] [--src DIR] [--detect] [--out DIR] [--sheets]
<src> defaults to tools/modelgen/ai_src/<char>[/<look>]/. --detect writes a
fit.json proposal (if none exists) and <src>/landmarks.png, then stops.
Heroes build one GLB per gear look (all looks without --look):
assets/models/chars/hero/<char>/<look>.glb with the meshes rg_helm, rg_chest,
rg_gloves, rg_boots, rg_weapon on the shared skeleton (lib/fit.split_regions)
+ assets/textures/char/hero/<char>_<look>_atlas.png.
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
KIT_TRIS = 700          # reserve for the script kit (visor, rune sword) inside the budget
UV_MARGIN = 0.003       # ~3 px at 1024: an AI body unwraps into hundreds of islands

# Rig v3 skeletons: the legacy ones with proportions the AI bodies share (the
# legacy Runebreaker's arms reach 0.82 m, an AI knight's wrist sits ~0.1 higher;
# clips re-solve their reach intents on whatever armature they are keyed on).
RB3_BONES = {**gen.RB_BONES, "arm_len": 0.52}

AI = {
    # heroes: one source + GLB per gear look (--look), cut into gear regions
    "runebreaker": dict(rig="runebreaker", glb="runebreaker", atlas="runebreaker", palette="runebreaker",
                        bone_args=RB3_BONES, kit=gen.runebreaker_kit,
                        clips=gen.runebreaker_clips, skip=(1,), budget=10000, height=1.97,
                        looks={"bare": {"visor": False, "sword": False}, "base": {"visor": False, "tier": "base"},
                               "common": {"visor": False, "tier": "common"}, "magic": {"visor": False, "tier": "magic"},
                               "rare": {"tier": "rare"}, "legendary": {"tier": "legendary"}},
                        grip=gen.runebreaker_grip, weapon=dict(length=1.3, grip_frac=0.08, tris=1600)),
    "marauder": dict(rig="marauder", glb="cinder_marauder", atlas="cinder_marauder", palette="cinder_marauder",
                     bone_args=gen.CM_BONES, kit=gen.marauder_kit,
                     clips=gen.marauder_clips, skip=(1, 2), budget=6000, height=1.85),
}


def _read_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _paths(cfg, char, look, out):
    """(glb path, atlas path, atlas id, contact-sheet dir) for a build."""
    if look is None:
        glb_dir = out or os.path.join(rig.ROOT, "assets", "models", "chars")
        tex_dir = out or gen.TEX_DIR
        name = cfg["atlas"]
        return (os.path.join(glb_dir, cfg["glb"] + ".glb"), os.path.join(tex_dir, name + "_atlas.png"), name,
                os.path.join(out or gen.SHEET_DIR, cfg["glb"]))
    glb_dir = out or os.path.join(rig.ROOT, "assets", "models", "chars", "hero", char)
    tex_dir = out or os.path.join(gen.TEX_DIR, "hero")
    name = "%s_%s" % (char, look)
    return (os.path.join(glb_dir, look + ".glb"), os.path.join(tex_dir, name + "_atlas.png"), "hero/" + name,
            os.path.join(out or gen.SHEET_DIR, "hero_" + name))


def build(char, look=None, src=None, detect=False, out=None, sheets=False):
    cfg = AI[char]
    if cfg.get("looks") and look is None:
        raise ValueError("%s is a hero: pass --look (%s)" % (char, ", ".join(cfg["looks"])))
    label = char if look is None else "%s/%s" % (char, look)
    src = src or os.path.join(HERE, "ai_src", *label.split("/"))
    fit_path = os.path.join(src, "fit.json")
    rig.reset_scene()
    gen.POSERS.clear()
    gen.SHEETS.clear()
    bones = gen.humanoid_bones(**cfg["bone_args"])
    have_fit = os.path.exists(fit_path)
    fj = _read_json(fit_path) if have_fit else {"yaw_deg": 0.0, "height": cfg["height"]}
    obj = aimesh.load(os.path.join(src, "raw.glb"), cfg["glb"] + "_ai")
    dropped = aimesh.clean(obj)
    aimesh.normalize(obj, fj["yaw_deg"], fj["height"])
    has_weapon = look is not None and os.path.exists(os.path.join(src, "weapon", "raw.glb"))
    weapon_tris = int(cfg["weapon"]["tris"]) if has_weapon else 0
    tris_in, tris_out = aimesh.decimate(obj, cfg["budget"] - KIT_TRIS - weapon_tris)
    print("ai_fit: %s  %d -> %d tris, %d specks dropped" % (label, tris_in, tris_out, dropped))

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

    kit_args = dict((cfg.get("looks") or {}).get(look, {}))
    weapon_src = os.path.join(src, "weapon")
    if has_weapon:
        # the look's AI weapon replaces the script sword (lib.fit.place_weapon)
        wcfg = dict(cfg["weapon"])
        if os.path.exists(os.path.join(weapon_src, "fit.json")):
            wcfg.update(_read_json(os.path.join(weapon_src, "fit.json")))
        weapon = aimesh.load(os.path.join(weapon_src, "raw.glb"), cfg["glb"] + "_weapon")
        aimesh.clean(weapon)
        if wcfg.get("yaw_deg"):
            aimesh.normalize(weapon, float(wcfg["yaw_deg"]), 1.0)
        aimesh.decimate(weapon, int(wcfg["tris"]))
        fit.place_weapon(weapon, cfg["grip"](cfg["bone_args"]), float(wcfg["length"]), float(wcfg["grip_frac"]))
        aimesh.smooth(weapon)
        obj = fit.join_weapon(obj, weapon)
        kit_args["sword"] = False
        print("ai_fit: %s weapon from %s" % (label, weapon_src))

    pm = rig.PartMesh(px_per_m=PX_PER_M)
    mats = cfg["kit"](pm, fit.snapper(obj), cfg["bone_args"], **kit_args)
    kit = pm.to_object(cfg["glb"] + "_kit", mats, arm)
    body = fit.join_body(obj, kit, mats, cfg["glb"], arm)
    cfg["clips"](arm)

    glb_path, atlas_path, atlas_id, sheet_dir = _paths(cfg, char, look, out)
    os.makedirs(os.path.dirname(atlas_path), exist_ok=True)
    size = atlas.unwrap(body, PX_PER_M, sizes=ATLAS_SIZES, upscale=False, margin=UV_MARGIN)
    base_lin, ao = texbake.transfer(body, size)
    ramps = texbake.ramps_of(gen.PAL[cfg["palette"]])
    base = texbake.quantize(base_lin, ao, ramps)
    atlas.bake(body, size, atlas_path, skip_material_indices=cfg["skip"], base=base)
    body.data.uv_layers.remove(body.data.uv_layers[aimesh.SRC_UV])
    report = fit.verify(body, arm, bones, cfg["budget"], atlas_path, [h for r in ramps for h in r])

    parts = [body]
    if look is not None:
        regions = fit.split_regions(body)
        parts = [regions[r] for r in sorted(regions)]
        report["regions"] = {r: sum(len(p.vertices) - 2 for p in o.data.polygons) for r, o in sorted(regions.items())}
    rig.export_glb(glb_path, active_action=bpy.data.actions["idle"], arm_obj=arm)

    src_rel = src if os.path.splitdrive(src)[0].lower() != os.path.splitdrive(rig.ROOT)[0].lower()         else os.path.relpath(src, rig.ROOT)
    report.update({"char": char, "look": look, "atlas_id": atlas_id, "src": src_rel.replace("\\", "/"),
                   "weights": method, "nearest_bone_fill": leftovers, "length_ratios": ratios, "atlas_px": size,
                   "px_per_m": PX_PER_M})
    os.makedirs(sheet_dir, exist_ok=True)
    fit.write_json(os.path.join(sheet_dir, "ai_fit_report.json"), report)
    bad = {k: v for k, v in ratios.items() if not 0.8 <= v <= 1.25}
    print("ai_fit: %s ok=%s tris=%d atlas=%d weights=%s off-palette=%s ratios-out=%s regions=%s" % (
        label, report["ok"], report["tris"], size, method, report.get("atlas_off_palette"), bad,
        report.get("regions")))
    if sheets:
        from lib import sheets as sheet_lib
        for part in parts[1:]:
            part.material_slots[0].material = sheet_lib._preview_material(atlas_path)
        sheet_lib.render(parts[0], arm, atlas_path, gen.SHEETS.get(arm.name, []), sheet_dir)
    return report


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {}
    names = []
    it = iter(args)
    for a in it:
        if a in ("--src", "--out", "--look"):
            opts[a[2:]] = next(it)
        elif a.startswith("--"):
            opts[a[2:]] = True
        else:
            names.append(a)
    for name in names or sorted(AI):
        looks = [opts["look"]] if "look" in opts else ([None] if not AI[name].get("looks") else list(AI[name]["looks"]))
        for look in looks:
            label = name if look is None else "%s/%s" % (name, look)
            if not opts.get("src") and not os.path.exists(os.path.join(HERE, "ai_src", *label.split("/"), "raw.glb")):
                print("ai_fit: %s has no source yet (tools/modelgen/ai_src/%s), skipped" % (label, label))
                continue
            build(name, look=look, src=opts.get("src"), detect=bool(opts.get("detect")), out=opts.get("out"),
                  sheets=bool(opts.get("sheets")))
    print("ai_fit done.")


if __name__ == "__main__":
    main()
