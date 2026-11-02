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
  blender ... ai_view.py -- zoom <class> <look | -> <candidate dir> <out dir> <clip,clip,...> [frame m]
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
    obj = _load(src, height, split_fans, tris)
    co = np.array([obj.matrix_world @ v.co for v in obj.data.vertices])
    reach = max(np.abs(co[:, 0]).max(), np.abs(co[:, 1]).max())
    # the frame (700 x 1000 px) fits the tallest or the widest extent: the
    # pixel scale is printed so landmarks can be read off the grid
    scale = max(height, 2.0 * reach / 0.7) + 0.3
    centre = height / 2 if scale <= height + 0.31 else scale / 2 - 0.15
    print("ai_view: %.5f m/px, image centre at z %.3f" % (scale / 1000.0, centre))
    for i in range(0, int(scale * 10) + 2):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0.6 + reach, i * 0.1))
        bpy.context.active_object.scale = (2.0 * scale, 0.01, 0.003 if i % 5 else 0.008)
    for i in range(-int(scale * 5) - 1, int(scale * 5) + 2):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(i * 0.1, 0.6 + reach, scale / 2))
        bpy.context.active_object.scale = (0.003 if i % 5 else 0.008, 0.01, scale + 0.2)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "FLAT"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x, sc.render.resolution_y = 700, 1000
    cam_data = bpy.data.cameras.new("view_cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = scale
    cam = bpy.data.objects.new("view_cam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    d = 5 + reach
    for name, loc, rot in (("front", (0, -d, centre), (math.pi / 2, 0, 0)),
                           ("side", (d, 0, centre), (math.pi / 2, 0, math.pi / 2)),
                           ("back", (0, d, centre), (math.pi / 2, 0, math.pi))):
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


def zoom(char, look, src, out, clips, frame=1.7):
    """frame: metres across the tile (small creatures: about twice their size)."""
    from lib import sheets
    import ai_fit
    sheets.TILE = 420
    sheets.TARGET = (0.0, 0.0, min(0.95, frame * 0.45))
    k = frame / 1.7
    sheets.VIEWS = (
        ("front34", (-2.3 * k, -3.4 * k, 1.4 * k), frame),
        ("front", (0.0, -4.0 * k, sheets.TARGET[2]), frame),
        ("side", (-4.0 * k, 0.0, sheets.TARGET[2]), frame),
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
        zoom(args[1], None if args[2] in ("", "-") else args[2], args[3], args[4], args[5].split(","),
             float(args[6]) if len(args) > 6 else 1.7)
    else:
        raise SystemExit("ai_view: raw | arms | zoom")


main()
