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
HUE_L_WEIGHT = 0.3  # lightness' share when picking the ramp (hue and chroma decide)
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


def _bake(obj, kind, target, sources=(), src_uv=None, dst_uv="UVMap", samples=1):
    """Bake `kind` into `target` on the final UVs. `sources`: one image per
    face source (face attribute "src_id": 0 the AI body, 1 an AI weapon, ...);
    the object's slots and indices are swapped for the bake and restored."""
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
    me = obj.data
    n = len(me.polygons)
    saved_mats = list(me.materials)
    saved_idx = np.empty(n, dtype=np.int32)
    me.polygons.foreach_get("material_index", saved_idx)
    src_attr = me.attributes.get("src_id")
    src_ids = np.zeros(n, dtype=np.int32)
    if src_attr is not None:
        src_attr.data.foreach_get("value", src_ids)
    mats = [_bake_material(target, img, src_uv) for img in sources] or [_bake_material(target)]
    me.materials.clear()
    for m in mats:
        me.materials.append(m)
    me.polygons.foreach_set("material_index", np.clip(src_ids, 0, len(mats) - 1) if sources else np.zeros(n, np.int32))
    for o in bpy.context.view_layer.objects:
        if o is not None:
            o.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    try:
        bpy.ops.object.bake(type=kind, uv_layer=dst_uv, use_clear=True, margin=4)
    finally:
        me.materials.clear()
        for m in saved_mats:
            me.materials.append(m)
        me.polygons.foreach_set("material_index", saved_idx)
        for m in mats:
            bpy.data.materials.remove(m)


def transfer(obj, size, src_uv="src"):
    """(base linear rgb (size, size, 3), ao (size, size)), rows bottom-up.
    obj["src_images"]: the AI source images by face "src" id (obj["src_image"]
    alone for a body without an AI weapon)."""
    names = list(obj.get("src_images", [])) or [obj["src_image"]]
    col = _image("rigv3_base", size)
    _bake(obj, "EMIT", col, sources=[bpy.data.images[nm] for nm in names], src_uv=src_uv)
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
    """Ramp colour per texel in OKLab after lifting the body's median
    lightness to `lift_target` (gain 1..LIFT_MAX, hue kept): the ramp by hue
    and chroma, the step by lightness; AO darkens one step; isolated texels (all 4 neighbours agree on another colour) take that
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
    # two stages: the ramp by hue and chroma (lightness counts a little), then
    # the step within it by lightness - a lifted skin stays skin, not gold
    ramp_of = np.array([e[0] for e in entries])
    n_ramps = len(ramps)
    idx = np.empty(len(lab), dtype=np.int32)
    for i in range(0, len(lab), chunk):
        part = lab[i:i + chunk]
        d = (part[:, None, 1:] - pal_lab[None, :, 1:]) ** 2
        cost = d.sum(axis=2) + (HUE_L_WEIGHT * (part[:, None, 0] - pal_lab[None, :, 0])) ** 2
        ramp_cost = np.full((len(part), n_ramps), np.inf, dtype=np.float32)
        for r in range(n_ramps):
            ramp_cost[:, r] = cost[:, ramp_of == r].min(axis=1)
        best_ramp = ramp_cost.argmin(axis=1)
        dl = np.abs(part[:, None, 0] - pal_lab[None, :, 0])
        dl[ramp_of[None, :] != best_ramp[:, None]] = np.inf
        idx[i:i + chunk] = dl.argmin(axis=1)
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
