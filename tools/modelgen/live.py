r"""Live preview loop (Blender GUI + Blender MCP, ASSET_MANIFEST "Live Blender"):
rebuild one tools/modelgen builder inside the open Blender session without
writing anything to assets/.

The generator scripts stay the only source (ART_BIBLE "Construction"). Every
build() reloads lib + both generators, so a script edit shows up on the next
call, and swaps three functions for the duration of that build:
  rig.reset_scene  empties the open scene in place (read_factory_settings would
                   reset the preferences and unload the MCP add-on)
  rig.export_glb   skipped
  atlas.bake       writes to %TEMP%/runebound_live instead of assets/textures,
                   and the atlas is put on the model's body slots
A size/mtime fingerprint of assets/ before and after raises if a build wrote
there anyway. The headless path (blender --background --python generate_*.py)
never imports this module.

Through the MCP's execute_blender_code:
  import sys; sys.dont_write_bytecode = True
  p = r"D:\fable_test\tools\modelgen"; p in sys.path or sys.path.insert(0, p)
  import importlib, live; importlib.reload(live)
  live.build("runebreaker"); live.pose("cleave_r", 7); live.view("front34")
then get_viewport_screenshot, or live.snap("label") for a PNG in
%TEMP%/runebound_live/shots. build(name, bake=False) skips the UV unwrap and
the atlas (white body, glow colours, ~0.1 s) for quick form checks; baked,
the Runebreaker takes ~3 s and a prop 16-22 s, almost all of it UV packing
(no MCP timeout at 22 s). Names: character keys
(runebreaker, marauder, ...) or prop functions (waypoint_shrine, ...).
"""
import importlib
import os
import sys
import tempfile
import time

import bpy
from mathutils import Quaternion, Vector

sys.dont_write_bytecode = True  # lib/__pycache__ is tracked: live runs must not rewrite it
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
from lib import atlas, rig, sheets  # noqa: E402

LIBS = ("lib.rig", "lib.pose", "lib.atlas", "lib.sheets")
GENERATORS = ("generate_characters_v2", "generate_props")
LIVE_DIR = os.path.join(tempfile.gettempdir(), "runebound_live")
SHOT_DIR = os.path.join(LIVE_DIR, "shots")
GROUND = "live_ground"
# Eye directions (model -> viewer), the lib.sheets views: the model faces -Y,
# its right is -X.
VIEWS = {
    "front34": (-2.3, -3.4, 0.45),
    "side": (-1.0, 0.0, 0.0),
    "front": (0.0, -1.0, 0.0),
    "back": (0.0, 1.0, 0.0),
    "top": (0.0, 0.0, 1.0),
}


def _load():
    """(Re)import lib, then both generators, so the build sees every edit.
    Reloads run in place: `rig`/`atlas`/`sheets` above stay valid."""
    mods = []
    for name in LIBS + GENERATORS:
        mod = sys.modules.get(name)
        mods.append(importlib.reload(mod) if mod is not None else importlib.import_module(name))
    sys.path[:] = list(dict.fromkeys(sys.path))  # every generator import inserts HERE again
    return mods[-2:]


def _view3d():
    """(window, area, region, space) of the first 3D viewport, the one the
    add-on's screenshot captures; all None in background mode (the startup
    file has a window there too, but nothing draws it)."""
    wm = bpy.context.window_manager
    for win in (wm.windows if wm is not None and not bpy.app.background else ()):
        for area in win.screen.areas:
            if area.type == "VIEW_3D":
                region = next(r for r in area.regions if r.type == "WINDOW")
                return win, area, region, area.spaces.active
    return None, None, None, None


def _redraw():
    """Draw the viewport region once so region_3d.view_matrix follows a new
    view. The add-on's screenshot reads that matrix, and a Blender window in
    the background (behind the editor) never redraws on its own; DRAW_WIN_SWAP
    is skipped there too, only a region DRAW (~150 ms) recomputes it."""
    win, area, region, _space = _view3d()
    if area is not None:
        with bpy.context.temp_override(window=win, area=area, region=region):
            bpy.ops.wm.redraw_timer(type="DRAW", iterations=1)


def _fingerprint():
    out = {}
    for dirpath, _dirs, files in os.walk(os.path.join(rig.ROOT, "assets")):
        for fn in files:
            path = os.path.join(dirpath, fn)
            st = os.stat(path)
            out[path] = (st.st_size, st.st_mtime_ns)
    return out


def _live_reset():
    """rig.reset_scene without read_factory_settings: the Scene itself stays
    (the MCP add-on keeps its server state on it), its contents go. Actions
    carry a fake user and would survive a purge: a leftover `idle` turns the
    new one into `idle.001`, and builders look clips up by name."""
    obj = bpy.context.object
    if obj is not None and obj.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    data = bpy.data
    data.batch_remove([*data.objects, *data.meshes, *data.armatures, *data.materials, *data.actions,
                       *data.cameras, *data.lights, *data.curves, *data.collections,
                       *[img for img in data.images if img.type == "IMAGE"]])
    bpy.context.view_layer.update()  # else view_layer.objects still lists the removed bases (None)
    scene = bpy.context.scene
    scene.render.fps = rig.FPS
    scene.render.fps_base = 1.0
    return scene


def _skip_export(path, active_action=None, arm_obj=None):
    print("live: export skipped:", os.path.relpath(path, rig.ROOT))


def _preview_bake(orig_bake):
    def bake(obj, size, path, skip_material_indices=(1,)):
        out = os.path.join(LIVE_DIR, os.path.basename(path))
        orig_bake(obj, size, out, skip_material_indices=skip_material_indices)
        mat = sheets._preview_material(out)
        for i, slot in enumerate(obj.material_slots):
            if i not in skip_material_indices:
                slot.material = mat
    return bake


def _no_unwrap(obj, target_px_per_m, sizes=(64, 128, 256, 512), axis_aligned=False):
    return sizes[-1]  # UV packing is most of a prop's build time (~11 s for the shrine)


def _no_bake(obj, size, path, skip_material_indices=(1,)):
    print("live: atlas skipped:", os.path.basename(path))


def _stage(scene):
    """Contact-sheet look in the viewport: Solid + studio light + texture,
    Standard view transform, emissive parts in their glow colour (Solid mode
    shows the viewport colour, not the node tree), a ground plate, rig hidden."""
    scene.view_settings.view_transform = "Standard"
    for mat in bpy.data.materials:
        bsdf = mat.node_tree.nodes.get("Principled BSDF") if mat.node_tree else None
        if bsdf is None or any(n.type == "TEX_IMAGE" for n in mat.node_tree.nodes):
            continue
        glow = bsdf.inputs["Emission Strength"].default_value > 0.0
        c = bsdf.inputs["Emission Color" if glow else "Base Color"].default_value
        mat.diffuse_color = (c[0], c[1], c[2], 1.0)
    s = 2.0
    mesh = bpy.data.meshes.new(GROUND)
    mesh.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
    gmat = bpy.data.materials.new(GROUND)
    gmat.diffuse_color = (0.32, 0.3, 0.3, 1.0)
    mesh.materials.append(gmat)
    scene.collection.objects.link(bpy.data.objects.new(GROUND, mesh))
    _win, _area, _region, space = _view3d()
    if space is not None:
        space.shading.type = "SOLID"
        space.shading.light = "STUDIO"
        space.shading.color_type = "TEXTURE"
    for obj in scene.objects:
        obj.select_set(False)  # no selection outline in the shots
        if obj.type == "ARMATURE":
            obj.hide_set(True)
            if "idle" in bpy.data.actions:
                pose("idle", 0)


def build(name, bake=True):
    """Build one character (key) or prop (function name) live; exports nothing."""
    chars, props = _load()
    fn = getattr(chars, "build_" + name, None) or getattr(props, name, None)
    if fn is None:
        raise ValueError("no builder %r in %s" % (name, " / ".join(GENERATORS)))
    os.makedirs(LIVE_DIR, exist_ok=True)
    before = _fingerprint()
    saved = (rig.reset_scene, rig.export_glb, atlas.unwrap, atlas.bake)
    rig.reset_scene, rig.export_glb = _live_reset, _skip_export
    if bake:
        atlas.bake = _preview_bake(saved[3])
    else:
        atlas.unwrap, atlas.bake = _no_unwrap, _no_bake
    t0 = time.perf_counter()
    try:
        win, area, region, _space = _view3d()
        if area is None:
            fn()
        else:
            with bpy.context.temp_override(window=win, area=area, region=region):
                fn()
    finally:
        rig.reset_scene, rig.export_glb, atlas.unwrap, atlas.bake = saved
    elapsed = time.perf_counter() - t0
    after = _fingerprint()
    changed = sorted(p for p in set(before) | set(after) if before.get(p) != after.get(p))
    if changed:
        raise RuntimeError("live build wrote to assets/: " + ", ".join(os.path.relpath(p, rig.ROOT) for p in changed))
    scene = bpy.context.scene
    _stage(scene)
    print("live: %s built in %.1f s (atlas %s), assets/ untouched" % (name, elapsed, "baked" if bake else "off"))
    for obj in scene.objects:
        if obj.type == "MESH" and obj.name != GROUND:
            print("  mesh %-20s %5d verts  %s" % (obj.name, len(obj.data.vertices),
                                                ", ".join(m.name for m in obj.data.materials)))
    for act in bpy.data.actions:
        print("  clip %-22s %3d-%d" % (act.name, act.frame_range[0], act.frame_range[1]))


def _rig():
    return next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")


def pose(clip, frame=0):
    """Show `clip` at `frame` on the built rig (scene range = the clip)."""
    arm = _rig()
    act = bpy.data.actions[clip]
    sheets._use_action(arm, act)
    scene = bpy.context.scene
    scene.frame_start, scene.frame_end = int(act.frame_range[0]), int(act.frame_range[1])
    scene.frame_set(frame)
    print("live: pose %s @%d (%d-%d)" % (clip, frame, scene.frame_start, scene.frame_end))


def _bounds():
    pts = [o.matrix_world @ Vector(c) for o in bpy.context.scene.objects
           if o.type == "MESH" and o.name != GROUND for c in o.bound_box]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    return lo, hi


def view(name="front34", margin=1.1):
    """Aim the first 3D viewport at the model from a VIEWS direction,
    orthographic like the contact sheets."""
    space = _view3d()[3]
    if space is None:
        print("live: no 3D viewport (background mode)")
        return
    lo, hi = _bounds()
    r3d = space.region_3d
    r3d.view_perspective = "ORTHO"
    if name == "top":
        r3d.view_rotation = Quaternion()  # straight down, +Y (the back) at the top
    else:
        r3d.view_rotation = (-Vector(VIEWS[name])).to_track_quat("-Z", "Y")
    r3d.view_location = (lo + hi) * 0.5
    r3d.view_distance = (hi - lo).length * margin
    _redraw()


def snap(label, max_size=1000):
    """Save the first 3D viewport to shots/<label>.png with the add-on's own
    offscreen capture."""
    server = getattr(bpy.types, "blendermcp_server", None)
    if server is None or _view3d()[1] is None:
        raise RuntimeError("snap needs the GUI with the MCP for Blender add-on running")
    os.makedirs(SHOT_DIR, exist_ok=True)
    path = os.path.join(SHOT_DIR, label + ".png")
    _redraw()
    result = server.get_viewport_screenshot(max_size=max_size, filepath=path)
    if "error" in result:
        raise RuntimeError("snap: " + result["error"])
    print("live: shot", path, "%dx%d" % (result["width"], result["height"]))
    return path
