"""Rig v3 review renders (Blender headless, Workbench, nothing written to assets/).

  blender --background --factory-startup --python tools/modelgen/ai_view.py -- raw <candidate dir> <height> <out.png> [--split] [--tris N]
      the cleaned, normalized raw.glb from the front, the side and the back with a
      0.1 m grid behind it (thick lines every 0.5 m): place landmarks by hand when
      --detect misses (ortho, 1000 px tall, (height + 0.3) m across the frame height,
      x = 0 and z = height / 2 at the image centre, front = -Y). --split cleans like a
      fit.json rev 2, --tris N decimates like ai_fit (budget minus kit and weapon).
  blender ... ai_view.py -- arms <candidate dir> <height>
      per 4 cm band the outermost vertex cluster on each side (the arm): x/y range
      for the shoulder, elbow, wrist and hand landmarks.
  blender ... ai_view.py -- zoom <class> <look> <candidate dir> <out dir> <clip,clip,...>
      ai_fit.build with big, close contact sheets (3/4 front, front, side) for a few clips.
"""
import math
import os
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import bpy  # noqa: E402
import numpy as np  # noqa: E402

from lib import aimesh, rig  # noqa: E402


def _load(src, height, split_fans=False, tris=0):
    rig.reset_scene()
    obj = aimesh.load(os.path.join(src, "raw.glb"), "view")
    aimesh.clean(obj, split_fans=split_fans)
    aimesh.normalize(obj, 0.0, height)
    if tris:
        print("ai_view: decimate %d -> %d" % aimesh.decimate(obj, tris))
    return obj


def raw(src, height, out, split_fans=False, tris=0):
    _load(src, height, split_fans, tris)
    for i in range(0, int(height * 10) + 2):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0.6, i * 0.1))
        bpy.context.active_object.scale = (2.0, 0.01, 0.003 if i % 5 else 0.008)
    for i in range(-8, 9):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(i * 0.1, 0.6, height / 2))
        bpy.context.active_object.scale = (0.003 if i % 5 else 0.008, 0.01, height + 0.2)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "FLAT"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x, sc.render.resolution_y = 700, 1000
    cam_data = bpy.data.cameras.new("view_cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = height + 0.3
    cam = bpy.data.objects.new("view_cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    for name, loc, rot in (("front", (0, -5, height / 2), (math.pi / 2, 0, 0)),
                           ("side", (5, 0, height / 2), (math.pi / 2, 0, math.pi / 2)),
                           ("back", (0, 5, height / 2), (math.pi / 2, 0, math.pi))):
        cam.location, cam.rotation_euler = loc, rot
        sc.render.filepath = out.replace(".png", "_%s.png" % name)
        bpy.ops.render.render(write_still=True)
        print("ai_view:", sc.render.filepath)


def arms(src, height):
    obj = _load(src, height)
    co = np.array([obj.matrix_world @ v.co for v in obj.data.vertices])
    for side, sgn in (("L", 1.0), ("R", -1.0)):
        print("ai_view: side", side)
        for z in np.arange(min(1.6, height - 0.2), 0.6, -0.04):
            band = co[(co[:, 2] > z - 0.02) & (co[:, 2] <= z + 0.02)]
            band = band[band[:, 0] * sgn > 0.05]
            if not len(band):
                continue
            xs = np.sort(band[:, 0] * sgn)
            gaps = np.where(np.diff(xs) > 0.012)[0]
            cut = xs[gaps[-1] + 1] if len(gaps) else xs[0]
            arm = band[band[:, 0] * sgn >= cut]
            ax = np.sort(arm[:, 0] * sgn)
            print("ai_view:   z %.2f  |x| %.3f..%.3f  y %.3f..%.3f  n %4d  %s" % (
                z, ax[0], ax[-1], arm[:, 1].min(), arm[:, 1].max(), len(arm),
                "gap from %.3f" % xs[gaps[-1]] if len(gaps) else "joined"))


def zoom(char, look, src, out, clips):
    from lib import sheets
    import ai_fit
    sheets.TILE = 420
    sheets.VIEWS = (
        ("front34", (-2.3, -3.4, 1.4), 1.7),
        ("front", (0.0, -4.0, 1.0), 1.7),
        ("side", (-4.0, 0.0, 0.95), 1.7),
    )
    render = sheets.render

    def some(body, arm, atlas_path, cl, out_dir):
        render(body, arm, atlas_path, [c for c in cl if c[0] in clips], out_dir)

    sheets.render = some
    ai_fit.build(char, look, src, out=out, sheets=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    cmd = args[0]
    if cmd == "raw":  # [--split] [--tris N]: the rev 2 clean and ai_fit's decimation
        tris = int(args[args.index("--tris") + 1]) if "--tris" in args else 0
        raw(args[1], float(args[2]), args[3], "--split" in args, tris)
    elif cmd == "arms":
        arms(args[1], float(args[2]))
    elif cmd == "zoom":
        zoom(args[1], args[2], args[3], args[4], args[5].split(","))
    else:
        raise SystemExit("ai_view: raw | arms | zoom")


main()
