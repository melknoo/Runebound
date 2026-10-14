"""Rig v3: AI texture -> palette pixel atlas (Blender headless, Cycles CPU).

transfer()  bakes the AI base colour from its own unwrap (UV map `src`) onto
            the final atlas unwrap (`UVMap`) of the same mesh: no ray casting,
            exact; plus Cycles AO on the posed-at-rest body + kit
quantize()  maps every texel to the nearest colour of the character's
            art_spec ramps (OKLab), one step darker in AO, isolated texels
            take their neighbours' colour; no dither (ART_BIBLE)
The result goes to lib.atlas.bake(base=...), which paints the script kit's
faces over it, so the atlas holds palette colours only.
"""
import os

import bpy
import numpy as np

from . import rig

AO_STEP = 0.35     # Cycles AO below this -> one ramp step darker (crevices only)
LIFT_TARGET = 0.55  # OKLab L the body's median is lifted to: ART_BIBLE key planes 40-70 L*
LIFT_MAX = 1.6      # AI paintings run dark (the first Runebreaker gambeson sat at ~27 L*)
AO_DISTANCE = 0.18  # metres, like lib.atlas's probe


def _linear_to_srgb(c):
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(np.clip(c, 0.0, None), 1.0 / 2.4) - 0.055)


def _oklab(lin):
    """linear sRGB (..., 3) -> OKLab (..., 3)"""
    m1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929],
                   [0.2119034982, 0.6806995451, 0.1073969566],
                   [0.0883024619, 0.2817188376, 0.6299787005]], dtype=np.float32)
    m2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468],
                   [1.9779984951, -2.4285922050, 0.4505937099],
                   [0.0259040371, 0.7827717662, -0.8086757660]], dtype=np.float32)
    lms = np.cbrt(np.clip(lin, 0.0, None) @ m1.T)
    return lms @ m2.T


def _image(name, size, float_buffer=True):
    old = bpy.data.images.get(name)
    if old is not None:
        bpy.data.images.remove(old)
    return bpy.data.images.new(name, size, size, alpha=False, float_buffer=float_buffer)


def _pixels(img):
    w, h = img.size
    buf = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    return buf.reshape(h, w, 4)


def _bake_material(target, src_image=None, src_uv=None):
    mat = bpy.data.materials.new("rigv3_bake")
    mat.use_nodes = True
    nt = mat.node_tree
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    if src_image is not None:
        uv = nt.nodes.new("ShaderNodeUVMap")
        uv.uv_map = src_uv
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = src_image
        tex.interpolation = "Linear"
        emit = nt.nodes.new("ShaderNodeEmission")
        nt.links.new(uv.outputs["UV"], tex.inputs["Vector"])
        nt.links.new(tex.outputs["Color"], emit.inputs["Color"])
        nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    tgt = nt.nodes.new("ShaderNodeTexImage")
    tgt.image = target
    for n in nt.nodes:
        n.select = False
    tgt.select = True
    nt.nodes.active = tgt
    return mat


def _bake(obj, kind, target, src_image=None, src_uv=None, dst_uv="UVMap", samples=1):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.seed = 0
    scene.render.bake.margin = 4
    scene.render.bake.margin_type = "EXTEND"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("rigv3_world")
    scene.world.light_settings.distance = AO_DISTANCE
    saved = [s.material for s in obj.material_slots]
    mat = _bake_material(target, src_image, src_uv)
    for s in obj.material_slots:
        s.material = mat
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    try:
        bpy.ops.object.bake(type=kind, uv_layer=dst_uv, use_clear=True, margin=4)
    finally:
        for s, m in zip(obj.material_slots, saved):
            s.material = m
        bpy.data.materials.remove(mat)


def transfer(obj, size, src_uv="src"):
    """(base linear rgb (size, size, 3), ao (size, size)), rows bottom-up."""
    src = bpy.data.images[obj["src_image"]]
    col = _image("rigv3_base", size)
    _bake(obj, "EMIT", col, src_image=src, src_uv=src_uv)
    ao = _image("rigv3_ao", size)
    _bake(obj, "AO", ao, samples=32)
    base, occ = _pixels(col)[:, :, :3].copy(), _pixels(ao)[:, :, 0].copy()
    dump = os.environ.get("RIGV3_DUMP")
    if dump:  # review aid: the raw bake before quantization
        np.save(os.path.join(dump, "base_lin.npy"), base)
        np.save(os.path.join(dump, "ao.npy"), occ)
    return base, occ


def ramps_of(palette):
    """art_spec palette dict -> its ramps (lists of hex), in key order."""
    return [v for v in palette.values() if isinstance(v, list)]


def quantize(base_lin, ao, ramps, ao_step=AO_STEP, lift_target=LIFT_TARGET, chunk=1 << 18):
    """Nearest ramp colour per texel in OKLab after lifting the body's median
    lightness to `lift_target` (gain 1..LIFT_MAX, hue kept); AO darkens one
    step; isolated texels (all 4 neighbours agree on another colour) take that
    colour. Returns sRGB floats (size, size, 3) holding palette colours only."""
    entries = [(ri, si) for ri, ramp in enumerate(ramps) for si in range(len(ramp))]
    pal_srgb = np.array([rig.hex_to_srgb(ramps[ri][si]) for ri, si in entries], dtype=np.float32)
    pal_lin = np.array([rig.hex_to_linear(ramps[ri][si]) for ri, si in entries], dtype=np.float32)
    pal_lab = _oklab(pal_lin)
    h, w, _ = base_lin.shape
    lab = _oklab(base_lin.reshape(-1, 3).astype(np.float32))
    covered = base_lin.reshape(-1, 3).max(axis=1) > 0.002
    if covered.any() and lift_target:
        gain = float(np.clip(lift_target / max(np.median(lab[covered, 0]), 1e-3), 1.0, LIFT_MAX))
        lab[:, 0] = np.minimum(lab[:, 0] * gain, 0.97)
        print("texbake: lightness gain %.2f" % gain)
    idx = np.empty(len(lab), dtype=np.int32)
    for i in range(0, len(lab), chunk):
        d = ((lab[i:i + chunk, None, :] - pal_lab[None, :, :]) ** 2).sum(axis=2)
        idx[i:i + chunk] = d.argmin(axis=1)
    idx = idx.reshape(h, w)
    # AO: one step down the same ramp
    lookup = {e: k for k, e in enumerate(entries)}
    down = np.array([lookup[(r, max(s - 1, 0))] for r, s in entries])
    idx = np.where(ao < ao_step, down[idx], idx)
    # isolated texels
    up, dn = np.roll(idx, 1, 0), np.roll(idx, -1, 0)
    lf, rt = np.roll(idx, 1, 1), np.roll(idx, -1, 1)
    lonely = (up == dn) & (dn == lf) & (lf == rt) & (up != idx)
    idx = np.where(lonely, up, idx)
    return pal_srgb[idx]
