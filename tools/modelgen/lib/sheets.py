"""Per-clip contact sheets (M06 review aid, Blender headless Workbench).

render() tiles chosen frames of each clip from three orthographic views into
captures_contact/<character>/<clip>.png:
  row 1  3/4 front (character's right-front)
  row 2  right side (foot contact, lean, arcs in depth)
  row 3  top down, character front at the bottom (sweep direction)
Columns are the requested frames, left to right. Call it AFTER export: it
swaps in a textured preview material and adds a ground plane.
"""
import os

import bpy
import numpy as np

TILE = 200
TARGET = (0.0, 0.0, 0.95)
VIEWS = (
    ("front34", (-2.3, -3.4, 1.4), 2.8),
    ("side", (-4.0, 0.0, 0.95), 2.8),
    ("top", (0.0, 0.0, 6.0), 3.2),
)


def _load(path):
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    buf = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    bpy.data.images.remove(img)
    return buf.reshape(h, w, 4)


def _save(arr, path):
    h, w = arr.shape[:2]
    img = bpy.data.images.new("contact_sheet", w, h, alpha=False)
    img.pixels.foreach_set(np.ascontiguousarray(arr, dtype=np.float32).ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def _preview_material(atlas_path):
    img = bpy.data.images.load(atlas_path, check_existing=True)
    mat = bpy.data.materials.new("sheet_preview")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    mat.node_tree.links.new(tex.outputs["Color"], nodes["Principled BSDF"].inputs["Base Color"])
    return mat


def _setup_scene(scene):
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = TILE
    scene.render.resolution_y = TILE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("sheet_world")
    scene.world.color = (0.16, 0.14, 0.18)
    ground_mesh = bpy.data.meshes.new("sheet_ground")
    s = 1.6
    ground_mesh.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
    ground = bpy.data.objects.new("sheet_ground", ground_mesh)
    scene.collection.objects.link(ground)
    gmat = bpy.data.materials.new("sheet_ground")
    gmat.diffuse_color = (0.32, 0.3, 0.3, 1.0)
    ground_mesh.materials.append(gmat)
    cam = bpy.data.objects.new("sheet_cam", bpy.data.cameras.new("sheet_cam"))
    cam.data.type = "ORTHO"
    scene.collection.objects.link(cam)
    scene.camera = cam
    target = bpy.data.objects.new("sheet_target", None)
    target.location = TARGET
    scene.collection.objects.link(target)
    return cam, target


def _aim(cam, target, pos, scale):
    cam.data.ortho_scale = scale
    cam.location = pos
    for c in list(cam.constraints):
        cam.constraints.remove(c)
    if abs(pos[0]) < 1e-6 and abs(pos[1]) < 1e-6:
        cam.rotation_euler = (0.0, 0.0, 0.0)  # straight down, +Y (character's back) at the top
        return
    c = cam.constraints.new("TRACK_TO")
    c.target = target
    c.track_axis = "TRACK_NEGATIVE_Z"
    c.up_axis = "UP_Y"


def _use_action(arm, action):
    arm.animation_data.action = action
    slots = getattr(action, "slots", None)
    if slots is not None and len(slots) > 0 and getattr(arm.animation_data, "action_slot", None) is None:
        arm.animation_data.action_slot = slots[0]


def render(body, arm, atlas_path, clips, out_dir):
    """clips: [(action_name, [frames])] -> one sheet PNG per clip."""
    scene = bpy.context.scene
    cam, target = _setup_scene(scene)
    body.material_slots[0].material = _preview_material(atlas_path)
    os.makedirs(out_dir, exist_ok=True)
    gdignore = os.path.join(os.path.dirname(out_dir.rstrip("\\/")), ".gdignore")
    if not os.path.exists(gdignore):
        open(gdignore, "w").close()
    tmp = os.path.join(out_dir, "_tile.png")
    for name, frames in clips:
        _use_action(arm, bpy.data.actions[name])
        rows = []
        for _view, pos, scale in VIEWS:
            _aim(cam, target, pos, scale)
            tiles = []
            for fr in frames:
                scene.frame_set(fr)
                scene.render.filepath = tmp
                bpy.ops.render.render(write_still=True)
                tiles.append(_load(tmp))
            rows.append(np.concatenate(tiles, axis=1))
        # Blender pixel rows run bottom-up: the first view goes last to land on top.
        _save(np.concatenate(rows[::-1], axis=0), os.path.join(out_dir, name + ".png"))
        print("sheet:", name, frames)
    if os.path.exists(tmp):
        os.remove(tmp)
