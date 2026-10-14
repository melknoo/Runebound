r"""Rig v3 ingest (live Blender + Blender MCP): turn one imported AI generation
into a compact, committable source for tools/modelgen/ai_fit.py.

AI base meshes (Tripo / Hyper3D Rodin through "MCP for Blender" Premium) are
input data like the palette: the build (ai_fit.py, headless) only ever reads
the compacted file this module writes, never the generator again.

  candidate(obj_name, char_id, tag, meta)  joins the imported object(s),
      decimates to <= MAX_TRIS, keeps only the base colour (<= MAX_TEX px),
      writes %TEMP%/runebound_ai/<char_id>/<tag>/raw.glb + manifest.json
  ingest_dir(dir)  the same for ai_gen.py output (<dir>/trellis.glb + gen.json),
      headless: blender --background --python ai_ingest.py -- <dir> [--promote]
  promote(dir)  copies a candidate to tools/modelgen/ai_src/<key>/
      (the only path that writes into the repo; commit only the chosen one)

Through the MCP's execute_blender_code, after import_generated_asset*:
  import sys; sys.dont_write_bytecode = True
  p = r"D:\fable_test\tools\modelgen"; p in sys.path or sys.path.insert(0, p)
  import importlib, ai_ingest; importlib.reload(ai_ingest)
  ai_ingest.candidate("rb_tripo_1", "runebreaker", "tripo_1", dict(service="tripo", ...))

manifest.json never holds download URLs (signed) or keys.
"""
import datetime
import hashlib
import json
import os
import shutil
import sys
import tempfile

import bpy

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
from lib import rig  # noqa: E402

SRC_DIR = os.path.join(HERE, "ai_src")
CAND_DIR = os.path.join(tempfile.gettempdir(), "runebound_ai")
MAX_TRIS = 50000
MAX_TEX = 2048
JPEG_QUALITY = 90

# Checked 2026-10-14 (ai_fit --credits copies this into ASSET_MANIFEST):
LICENSE = {
    "route": "MCP for Blender Premium (mcp-for-blender.com), paid plan",
    "terms": {
        "mcp_for_blender": "https://mcp-for-blender.com/terms (updated 2026-10-01): 'What you create is yours'; "
                           "outputs come from third-party providers, the user checks fitness for purpose",
        "tripo": "https://www.tripo3d.ai/help/privacy-policy/can-i-use-models-commercially : paid users may use, "
                 "modify, distribute and commercially exploit generated models",
        "rodin": "https://hyper3d.ai/legal/copyright-license : licence to sell, redistribute, modify, publish; "
                 "no competing service, no training of competing AI models",
    },
    "checked": "2026-10-14",
    "commercial": True,
    "public_redistribution": True,
}


def _tris(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def _sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _meshes_under(name):
    root = bpy.data.objects[name]
    out = [root] if root.type == "MESH" else []
    out += [o for o in root.children_recursive if o.type == "MESH"]
    if not out:
        raise ValueError("no mesh under %r" % name)
    return out


def _activate(objs):
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def _join(name):
    """One mesh object with world transforms applied and no parents."""
    objs = _meshes_under(name)
    for o in objs:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    _activate(objs)
    if len(objs) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj


def _base_image(mat):
    """The image feeding Principled Base Color (directly or through one node)."""
    if mat is None or mat.node_tree is None:
        return None
    for node in mat.node_tree.nodes:
        if node.type != "BSDF_PRINCIPLED":
            continue
        links = node.inputs["Base Color"].links
        while links:
            src = links[0].from_node
            if src.type == "TEX_IMAGE":
                return src.image
            ins = [i for i in src.inputs if i.is_linked]
            links = ins[0].links if ins else None
    imgs = [n.image for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image is not None]
    return imgs[0] if len(imgs) == 1 else None


def _base_only(obj):
    """Every material becomes Principled + its base-colour image (<= MAX_TEX):
    normal/roughness/metal maps are dropped, the bake only reads colour."""
    sizes = []
    for i, slot in enumerate(obj.material_slots):
        img = _base_image(slot.material)
        mat = bpy.data.materials.new("ai_base_%d" % i)
        mat.use_nodes = True
        nodes = mat.node_tree.nodes
        bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
        if img is not None:
            sizes.append(tuple(img.size))
            if max(img.size) > MAX_TEX:
                k = MAX_TEX / float(max(img.size))
                img.scale(max(1, int(img.size[0] * k)), max(1, int(img.size[1] * k)))
            tex = nodes.new("ShaderNodeTexImage")
            tex.image = img
            mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        slot.material = mat
    return sizes


def _weld(obj, dist=1e-5):
    """glTF splits vertices along UV seams and normal breaks: weld them first,
    or the decimation collapses each side on its own and tears the surface
    into hundreds of shells (seen on the first TRELLIS Runebreaker)."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=dist)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def _decimate(obj, max_tris):
    _weld(obj)
    before = _tris(obj)
    if before > max_tris:
        mod = obj.modifiers.new("compact", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = max_tris / float(before)
        _activate([obj])
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return before, _tris(obj)


def _export(obj, path):
    _activate([obj])
    props = {p.identifier for p in bpy.ops.export_scene.gltf.get_rna_type().properties}
    kw = dict(filepath=path, export_format="GLB", use_selection=True, export_animations=False,
              export_skins=False, export_yup=True, export_apply=False, export_image_format="JPEG")
    for key in ("export_image_quality", "export_jpeg_quality"):
        if key in props:
            kw[key] = JPEG_QUALITY
            break
    bpy.ops.export_scene.gltf(**kw)


def candidate(obj_name, char_id, tag, meta, out=None):
    """Compact the imported generation `obj_name` into a review candidate.
    meta: service, prompt, request_id, quality, bbox_condition, ... (no URLs, no keys)."""
    for bad in ("url", "api_key", "apikey", "token", "secret", "password"):
        if any(bad in k.lower() for k in meta):
            raise ValueError("manifest meta must not carry %r fields" % bad)
    out = out or os.path.join(CAND_DIR, char_id, tag)
    os.makedirs(out, exist_ok=True)
    obj = _join(obj_name)
    obj.name = "%s_%s" % (char_id, tag)
    lo = [min((obj.matrix_world @ v.co)[i] for v in obj.data.vertices) for i in range(3)]
    hi = [max((obj.matrix_world @ v.co)[i] for v in obj.data.vertices) for i in range(3)]
    tex_sizes = _base_only(obj)
    tris_in, tris_out = _decimate(obj, MAX_TRIS)
    glb = os.path.join(out, "raw.glb")
    _export(obj, glb)
    manifest = {
        "char_id": char_id,
        "tag": tag,
        "date": datetime.date.today().isoformat(),
        **meta,
        "original": {"tris": tris_in, "textures": tex_sizes,
                     "bbox_min": [round(c, 4) for c in lo], "bbox_max": [round(c, 4) for c in hi]},
        "compact": {"max_tris": MAX_TRIS, "tris": tris_out, "max_tex": MAX_TEX, "jpeg_quality": JPEG_QUALITY,
                    "blender": bpy.app.version_string, "sha256": _sha256(glb),
                    "bytes": os.path.getsize(glb)},
        "license": LICENSE,
    }
    with open(os.path.join(out, "manifest.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    print("ai_ingest: %s/%s  %d -> %d tris, %.2f MB, textures %s" % (
        char_id, tag, tris_in, tris_out, manifest["compact"]["bytes"] / 1e6, tex_sizes))
    return out


def ingest_dir(cand):
    """Headless path for ai_gen.py output: <cand>/trellis.glb + gen.json ->
    <cand>/raw.glb + manifest.json (same compaction as candidate())."""
    cand = os.path.abspath(cand)
    tag = os.path.basename(cand)
    with open(os.path.join(cand, "gen.json"), encoding="utf-8") as f:
        meta = json.load(f)
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(cand, "trellis.glb"))
    new = [o for o in bpy.data.objects if o not in before]
    root = next((o for o in new if o.parent is None), new[0])
    char_id = meta.get("key") or os.path.basename(os.path.dirname(cand))
    return candidate(root.name, char_id, tag, meta, out=cand)


def promote(cand):
    """Copy a reviewed candidate dir into the repo: tools/modelgen/ai_src/<key>/
    (key from its manifest, e.g. runebreaker/rare)."""
    cand = os.path.abspath(cand)
    with open(os.path.join(cand, "manifest.json"), encoding="utf-8") as f:
        key = json.load(f)["char_id"]
    dst = os.path.join(SRC_DIR, *key.split("/"))
    os.makedirs(dst, exist_ok=True)
    for fn in ("raw.glb", "manifest.json", "fit.json", "input_rgba.png"):
        if os.path.exists(os.path.join(cand, fn)):
            shutil.copyfile(os.path.join(cand, fn), os.path.join(dst, fn))
    print("ai_ingest: promoted", key, "->", os.path.relpath(dst, rig.ROOT))
    return dst


if __name__ == "__main__":
    # blender --background --factory-startup --python tools/modelgen/ai_ingest.py -- <candidate dir> [--promote]
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for d in [a for a in args if not a.startswith("--")]:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        ingest_dir(d)
        if "--promote" in args:
            promote(d)
