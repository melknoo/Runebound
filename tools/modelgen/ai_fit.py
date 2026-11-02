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
import mathutils

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
REV = 2  # the fit.json revision new proposals get (see build)
IMP3_BONES = {**gen.IMP_BONES, "shoulder_x": 0.15, "arm_len": 0.34}  # the downloaded imp's shorter, T-pose arms
# the downloaded hare stands tall on long legs; the legacy template crouches (warped
# onto it, the haunches tore): a v3 template from its own joints, the clips re-pose it
HARE3 = {"hip": (0.066, 0.173), "shoulder": (-0.083, 0.19), "neck": (-0.108, 0.206), "head": (-0.183, 0.227),
         "jaw0": (-0.15, 0.2), "jaw1": (-0.18, 0.205), "tail": (0.108, 0.206),
         "f_top": (-0.1, 0.14), "f_elbow": (-0.083, 0.098), "f_wrist": (-0.087, 0.032), "f_toe": (-0.12, 0.007),
         "h_top": (0.075, 0.131), "h_stifle": (0.087, 0.098), "h_hock": (0.116, 0.073), "h_ankle": (0.116, 0.015),
         "h_toe": (0.091, 0.005), "leg_x": 0.023}
REGION_MIN = {"helm": 400, "gloves": 400}  # tris below which a look's head or hands count as starved
EL3_BONES = {**gen.EL_BONES, "shoulder_x": 0.19, "arm_len": 0.44}  # the slender AI mage (concept 90): narrow shoulders, short forearms

AI = {
    # heroes: one source + GLB per gear look (--look), cut into gear regions
    "runebreaker": dict(rig="runebreaker", glb="runebreaker", atlas="runebreaker", palette="runebreaker",
                        bone_args=RB3_BONES, kit=gen.runebreaker_kit,
                        clips=gen.runebreaker_clips, skip=(1,), budget=10000, height=1.97,
                        looks={"bare": {"visor": False, "sword": False}, "base": {"visor": False, "tier": "base"},
                               "common": {"visor": False, "tier": "common"}, "magic": {"tier": "magic"},  # concept 62: a closed helm with a visor
                               "rare": {"tier": "rare"}, "legendary": {"tier": "legendary"}},
                        grip=gen.runebreaker_grip, weapon=dict(length=1.3, grip_frac=0.08, tris=1600)),
    "elementalist": dict(rig="elementalist", glb="elementalist", atlas="elementalist", palette="elementalist",
                         bone_args=EL3_BONES, kit=gen.elementalist_kit, clips=gen.elementalist_clips, skip=(1,),
                         budget=10000, height=1.85,
                         looks={"bare": {"circlet": False, "weapon": False}, "base": {"tier": "base"},
                                "common": {"tier": "common"}, "magic": {"tier": "magic"}, "rare": {"tier": "rare"},
                                "legendary": {"tier": "legendary"}},
                         grip=gen.elementalist_grip, weapon=dict(length=0.8, grip_frac=0.15, tris=1200),
                         robe_radius=0.15),  # the coat's skirt stays with the chest
    "druid": dict(rig="druid", glb="druid", atlas="druid", palette="druid",
                  bone_args=gen.DR_BONES, kit=gen.druid_kit, clips=gen.druid_clips, skip=(1,),
                  budget=10000, height=1.98,
                  looks={"bare": {"weapon": False}, "base": {"tier": "base"}, "common": {"tier": "common"},
                         "magic": {"tier": "magic"}, "rare": {"tier": "rare"}, "legendary": {"tier": "legendary"}},
                  grip=gen.druid_grip, weapon=dict(length=1.6, grip_frac=0.35, tris=1400),
                  robe_radius=0.14),  # the robe's long skirt stays with the chest
    "marauder": dict(rig="marauder", glb="cinder_marauder", atlas="cinder_marauder", palette="cinder_marauder",
                     bone_args=gen.CM_BONES, kit=gen.marauder_kit,
                     clips=gen.marauder_clips, skip=(1, 2), budget=6000, height=1.85),
    # enemies from downloaded models (ai_ingest.ingest_ext; one mesh each, the
    # legacy GLB name, skeleton and clips): "bones" builds a non-humanoid
    # template, "src" shares one source between a family and its boss (each
    # with its own "fit" file, the landmarks differ with the scale)
    "imp": dict(rig="imp", glb="kiln_imp", atlas="kiln_imp", palette="kiln_imp", src="kiln_imp",
                bone_args=IMP3_BONES, kit=gen.imp_kit, clips=gen.imp_clips, skip=(1,), budget=6000, kit_tris=100,
                height=1.23),
    "beetle": dict(rig="beetle", glb="cinder_beetle", atlas="cinder_beetle", palette="cinder_beetle", src="cinder_beetle",
                   bones=lambda: gen.quadruped_bones(gen.BEETLE), kit=gen.beetle_kit, kit_args=dict(s=1.0),
                   clips=lambda arm: gen.beetle_clips(arm, 1.0), skip=(1,), budget=6000, kit_tris=100, height=0.75),
    "broodmother": dict(rig="broodmother", glb="broodmother", atlas="broodmother", palette="broodmother",
                        src="cinder_beetle", fit="fit_broodmother.json",
                        bones=lambda: gen.quadruped_bones(gen._scaled(gen.BEETLE, 1.6, (0.95, 0.4))),
                        kit=gen.beetle_kit, kit_args=dict(s=1.6, sac=True, pal_key="broodmother"),
                        clips=lambda arm: gen.broodmother_clips(arm, 1.6), skip=(1,), budget=12000, kit_tris=300,
                        height=1.2),
    "lurker": dict(rig="lurker", glb="channel_lurker", atlas="channel_lurker", palette="channel_lurker",
                   src="channel_lurker", bones=lambda: gen.serpent_bones(1.0), kit=gen.serpent_kit,
                   kit_args=dict(s=1.0, thick=1.0, pal_key="channel_lurker"),
                   clips=lambda arm: gen.lurker_clips(arm, 1.0), skip=(1,), budget=6000, kit_tris=50, height=2.1,
                   max_height=2.2),
    "deepmaw": dict(rig="deepmaw", glb="deepmaw", atlas="deepmaw", palette="deepmaw", src="channel_lurker",
                    fit="fit_deepmaw.json", bones=lambda: gen.serpent_bones(1.3), kit=gen.serpent_kit,
                    kit_args=dict(s=1.3, thick=1.9, pal_key="deepmaw"), girth=1.45,
                    clips=lambda arm: gen.deepmaw_clips(arm, 1.3), skip=(1,), budget=12000, kit_tris=50, height=2.8,
                    max_height=3.0),
    "hare": dict(rig="hare", glb="ash_hare", atlas="ash_hare", palette="ash_hare", src="ash_hare",
                 bones=lambda: gen.quadruped_bones(HARE3), kit=gen.hare_kit, clips=gen.hare_clips, skip=(),
                 budget=2000, kit_tris=0, height=0.37),
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
    src = src or os.path.join(HERE, "ai_src", *cfg.get("src", label).split("/"))
    fit_path = os.path.join(src, cfg.get("fit", "fit.json"))
    rig.reset_scene()
    gen.POSERS.clear()
    gen.SHEETS.clear()
    bones = cfg["bones"]() if "bones" in cfg else gen.humanoid_bones(**cfg["bone_args"])
    have_fit = os.path.exists(fit_path)
    # fit.json "rev" 2 (new proposals): fused fans split (lib.aimesh.clean), the
    # palette ramp picked before the lightness lift (lib.texbake.quantize);
    # sources without it (the Runebreaker's) keep building byte-identically
    fj = _read_json(fit_path) if have_fit else {"rev": REV, "yaw_deg": 0.0, "height": cfg["height"]}
    rev = int(fj.get("rev", 1))
    obj = aimesh.load(os.path.join(src, "raw.glb"), cfg["glb"] + "_ai")
    dropped = aimesh.clean(obj, split_fans=rev >= 2)
    aimesh.normalize(obj, fj["yaw_deg"], fj["height"])
    if cfg.get("girth"):  # a fatter body than the source (the Deepmaw from the lurker's eel)
        g = float(cfg["girth"])
        obj.data.transform(mathutils.Matrix.Diagonal((g, g, 1.0, 1.0)))
    has_weapon = look is not None and os.path.exists(os.path.join(src, "weapon", "raw.glb"))
    weapon_tris = int(cfg["weapon"]["tris"]) if has_weapon else 0
    tris_in, tris_out = aimesh.decimate(obj, cfg["budget"] - cfg.get("kit_tris", KIT_TRIS) - weapon_tris)
    print("ai_fit: %s  %d -> %d tris, %d specks dropped" % (label, tris_in, tris_out, dropped))

    if detect:
        if not have_fit:
            fj["landmarks"] = fit.detect(obj, bones)
            fit.write_json(fit_path, fj)
            print("ai_fit: proposal ->", fit_path)
        fit.landmark_sheet(obj, fj["landmarks"], os.path.join(src, "landmarks.png"))
        return None

    fit_arm = fit.fit_armature(cfg["rig"], bones, fj["landmarks"])
    method, leftovers = fit.auto_weights(obj, fit_arm, limb_radius=fj.get("limb_radius"))
    ratios = fit.warp(obj, fit_arm, bones)
    aimesh.smooth(obj)
    arm = rig.build_armature(cfg["rig"], bones)

    kit_args = dict((cfg.get("looks") or {}).get(look, {}))
    kit_args.update(cfg.get("kit_args", {}))
    kit_args.update(fj.get("kit", {}))  # per-source kit tweaks (e.g. the circlet gem's height)
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
    mats = cfg["kit"](pm, fit.snapper(obj), cfg.get("bone_args"), **kit_args)
    kit = pm.to_object(cfg["glb"] + "_kit", mats, arm)
    body = fit.join_body(obj, kit, mats, cfg["glb"], arm)
    cfg["clips"](arm)

    glb_path, atlas_path, atlas_id, sheet_dir = _paths(cfg, char, look, out)
    os.makedirs(os.path.dirname(atlas_path), exist_ok=True)
    size = atlas.unwrap(body, PX_PER_M, sizes=ATLAS_SIZES, upscale=False, margin=UV_MARGIN)
    base_lin, ao = texbake.transfer(body, size)
    ramps = texbake.ramps_of(gen.PAL[cfg["palette"]])
    base = texbake.quantize(base_lin, ao, ramps, ramp_unlifted=rev >= 2)
    atlas.bake(body, size, atlas_path, skip_material_indices=cfg["skip"], base=base)
    body.data.uv_layers.remove(body.data.uv_layers[aimesh.SRC_UV])
    report = fit.verify(body, arm, bones, cfg["budget"], atlas_path, [h for r in ramps for h in r],
                        all_slots=look is None, max_height=cfg.get("max_height", 2.0))

    parts = [body]
    if look is not None:
        regions = fit.split_regions(body, bones=bones, robe_radius=cfg.get("robe_radius"))
        parts = [regions[r] for r in sorted(regions)]
        report["regions"] = {r: sum(len(p.vertices) - 2 for p in o.data.polygons) for r, o in sorted(regions.items())}
        # collapse decimation starves the head and hands when it cannot thin
        # fused folds elsewhere (lib.aimesh.clean): flag it
        starved = {r: n for r, n in report["regions"].items() if r in REGION_MIN and n < REGION_MIN[r]}
        report["regions_ok"] = not starved
        report["ok"] = report["ok"] and not starved
        if starved:
            print("ai_fit: %s decimation starved %s" % (label, starved))
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
            key = AI[name].get("src", label)
            fit_name = AI[name].get("fit", "fit.json")
            src_dir = os.path.join(HERE, "ai_src", *key.split("/"))
            if not opts.get("src") and not (os.path.exists(os.path.join(src_dir, "raw.glb"))
                                            and os.path.exists(os.path.join(src_dir, fit_name))):
                print("ai_fit: %s has no source yet (tools/modelgen/ai_src/%s/%s), skipped" % (label, key, fit_name))
                continue
            build(name, look=look, src=opts.get("src"), detect=bool(opts.get("detect")), out=opts.get("out"),
                  sheets=bool(opts.get("sheets")))
    print("ai_fit done.")


if __name__ == "__main__":
    main()
