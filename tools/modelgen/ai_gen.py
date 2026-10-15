r"""Rig v3 generation (plain Python, no Blender): free AI base meshes for
tools/modelgen/ai_ingest.py -> ai_fit.py.

  concept  FLUX.1-schnell (Apache-2.0, HF Space black-forest-labs/FLUX.1-schnell)
           paints a front-view A-pose concept from PROMPTS[key] (<class>/<look> or <enemy>)
  mesh     TRELLIS.2 (MIT, HF Space microsoft/TRELLIS.2) lifts a concept to a
           textured GLB (PBR, WebP textures)

Both Spaces run on ZeroGPU: a free Hugging Face account has a few GPU minutes
a day (about one mesh). The token is read from .env (HF_TOKEN, a read token;
.env is git-ignored and never printed). Everything lands in
%TEMP%/runebound_ai/<char>/ ; nothing here writes into the repo.

The background is keyed to alpha here, so the Space's own preprocess keeps
the alpha and never calls its background remover (BRIA RMBG 2.0 is
non-commercial). Seeds, Space revisions and every parameter go into
gen.json next to each output (ai_ingest copies them into the manifest).

  python tools/modelgen/ai_gen.py concept runebreaker/base --seeds 11 12 13
  python tools/modelgen/ai_gen.py mesh runebreaker/base concept_12.png --seed 7
"""
import argparse
import datetime
import json
import os
import shutil
import sys
import tempfile
import urllib.request

# The owner's Windows proxy is a bare "socks=" entry that httpx rejects; the
# Spaces are reached directly (this process only, the system stays as it is).
urllib.request.getproxies = lambda: {}

import numpy as np  # noqa: E402
from PIL import Image, ImageFilter  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(tempfile.gettempdir(), "runebound_ai")
FLUX = "black-forest-labs/FLUX.1-schnell"
TRELLIS = "microsoft/TRELLIS.2"

# Shared framing: what ai_fit needs to rig the result (A-pose, open silhouette,
# empty fists, weapons and glow stay script kit) + the house style.
FRAME = ("full body character concept, front view, orthographic, standing straight in an A-pose with both arms "
         "held 45 degrees down and away from the body, elbows straight, legs slightly apart, feet flat, "
         "empty clenched fists, no weapon, no cape, nothing held, plain light grey background, even soft "
         "lighting, no cast shadow, stylized fantasy RPG game character, chunky exaggerated proportions, "
         "clean readable shapes, hand-painted texture style, high detail")

# Weapons (keys "<class>/<look>/weapon"): one upright object, its flat to the
# camera, so lib.fit.place_weapon can lay it along the rig's forward axis.
OBJECT_FRAME = ("a single object, standing perfectly upright and vertical with the tip pointing up and the "
                "pommel or butt at the bottom, the whole object in view, flat side facing the camera, centred, "
                "plain light grey background, even soft lighting, no cast shadow, nothing else in the picture, "
                "stylized fantasy RPG game asset, chunky readable shapes, hand-painted texture style, high detail")

PROMPTS = {
    # "<class>/<look>" for heroes (Rig v3 gear looks by rarity, same body under
    # every look so the regions swap cleanly), "<enemy>" for enemies.
    # ART_BIBLE section 7 + palettes in assets/art_spec.json.
    "runebreaker/rare": ("a heroic rune knight, broad V-shaped torso, about 4.5 heads tall, oversized domed steel-grey "
                         "iron pauldrons with gold trim, large armoured gauntlets, heavy plated boots, bucket great helm "
                         "with a narrow visor slit and a short teal crest on top, blue-grey iron plate armour, teal cloth "
                         "tabard hanging front and back, brown leather belt with a gold buckle, leather thighs, glowing "
                         "gold rune circle engraved on the chest plate"),
    "runebreaker/base": ("a stocky young warrior with the build of a heroic rune knight, broad V-shaped torso, about 4.5 "
                         "heads tall, bare head with short dark brown hair and a short beard, quilted teal-grey padded "
                         "gambeson reaching mid-thigh, brown leather belt, plain brown wool trousers, cloth-wrapped "
                         "forearms and leather fingerless gloves, simple brown leather boots to the shin"),
    "runebreaker/bare": ("a stocky young warrior with the build of a heroic rune knight, broad V-shaped torso, about "
                         "4.5 heads tall, bare head with short dark brown hair and a short beard, a plain off-white "
                         "linen undershirt with short sleeves, plain grey-brown linen trousers tied with a cord, bare "
                         "forearms and bare hands, barefoot"),
    "runebreaker/common": ("a stocky rune knight squire with the build of a heroic rune knight, broad V-shaped torso, "
                           "about 4.5 heads tall, simple dented iron half-plate breastplate over a teal-grey padded "
                           "gambeson, open-faced round iron kettle helmet over a short beard, mail sleeves, brown "
                           "leather belt, leather gloves with iron knuckle plates, iron-capped leather boots"),
    "runebreaker/magic": ("a heroic rune knight, broad V-shaped torso, about 4.5 heads tall, blued-steel chainmail "
                          "hauberk under a steel breastplate, rounded steel pauldrons, steel nasal helm with a short "
                          "teal plume, teal tabard with a steel-blue trim, steel gauntlets, steel greaves over "
                          "leather boots, brown leather belt with a steel buckle"),
    "runebreaker/legendary": ("a legendary rune knight, broad V-shaped torso, about 4.5 heads tall, ornate full plate "
                              "of polished steel and gold, glowing teal runes etched into every plate, winged great "
                              "helm with a narrow glowing visor and a tall teal crest, huge layered pauldrons with "
                              "gold edges, long teal tabard with gold embroidery, gold-trimmed gauntlets and sabatons"),
    "runebreaker/base/weapon": ("a plain recruit's longsword, straight iron blade, simple iron crossguard, "
                                "leather-wrapped grip, round iron pommel"),
    "runebreaker/common/weapon": ("a sturdy iron longsword, broad straight blade with a fuller, squared iron "
                                  "crossguard, brown leather grip, faceted iron pommel"),
    "runebreaker/magic/weapon": ("a blued-steel rune longsword, broad blade with a thin teal rune line along the "
                                 "fuller, steel crossguard with small curled tips, teal-wrapped grip, steel pommel"),
    "runebreaker/rare/weapon": ("an ornate rune knight's longsword, broad steel blade with glowing teal runes "
                                "engraved along the fuller, gold-trimmed crossguard, leather grip, gold pommel"),
    "runebreaker/legendary/weapon": ("a legendary runeblade, massive broad steel blade covered in glowing teal "
                                     "runes, winged gold crossguard with a teal gem, gold-wrapped grip, large gold "
                                     "pommel with a glowing rune stone"),
    "marauder": ("a hunched ash raider brute leaning forward, bulky barrel chest, heavy muscular forearms and big "
                 "fists, rust-red leathery hide skin, one huge rusty iron shoulder plate on the left shoulder with "
                 "three bone spikes, rusted plate chest guard, bone jaw guard over the mouth, two curved bone horns, "
                 "small glowing amber eyes, ragged hide loincloth skirt, wrapped hide boots"),
}


def _token():
    path = os.path.join(ROOT, ".env")
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            key, _, value = line.strip().partition("=")
            if key == "HF_TOKEN" and value:
                return value.strip().strip('"')
    token = os.environ.get("HF_TOKEN")
    if not token:
        print("ai_gen: no HF_TOKEN (.env line HF_TOKEN=hf_..., a free read token): anonymous, smaller GPU quota")
    return token or None


def _client(space, token):
    from gradio_client import Client
    return Client(space, token=token, verbose=False)


def _revision(space, token):
    try:
        import huggingface_hub
        return huggingface_hub.space_info(space, token=token).sha
    except Exception as exc:  # recorded, never fatal
        return "unknown (%s)" % type(exc).__name__


def _write_json(path, data):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def _quota_hint(exc):
    text = str(exc)
    if "quota" in text.lower() or "exceeded" in text.lower():
        sys.exit("ai_gen: ZeroGPU quota used up for today (%s) - try again after the reset" % text[:200])
    raise exc


def _components(mask):
    """4-connected labels of a bool mask (pure Python, no scipy): (labels, sizes)."""
    h, w = mask.shape
    label = np.zeros((h, w), np.int32)
    sizes = [0]
    for y0 in range(h):
        for x0 in range(w):
            if mask[y0, x0] and not label[y0, x0]:
                n = len(sizes)
                count = 0
                stack = [(y0, x0)]
                while stack:
                    y, x = stack.pop()
                    if y < 0 or y >= h or x < 0 or x >= w or not mask[y, x] or label[y, x]:
                        continue
                    label[y, x] = n
                    count += 1
                    stack += [(y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)]
                sizes.append(count)
    return label, sizes


def key_background(src, dst, tol=34, hole_tol=16, hole_min=120):
    """Plain backdrop -> alpha (soft 1-px edge). Background = near-backdrop
    pixels reached from the border, plus the pale neutral ground shadow in the
    bottom band of the figure, plus enclosed backdrop holes (between the legs,
    under the arms; stricter tolerance so pale armour is never punched).
    Only the largest opaque component stays (stray props, signatures)."""
    img = Image.open(src).convert("RGB")
    a = np.asarray(img).astype(np.int32)
    h, w, _ = a.shape
    border = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
    bg = np.median(border, axis=0)
    diff = np.abs(a - bg).max(axis=2)
    chroma = a.max(axis=2) - a.min(axis=2)
    lum = a.mean(axis=2)
    near = diff <= tol
    rows = np.where((~near).any(axis=1))[0]
    band = np.zeros((h, w), bool)
    if len(rows):
        band[int(rows[-1] - 0.12 * (rows[-1] - rows[0])):, :] = True
    passable = near | (band & (chroma < 4) & (lum > 110))
    lab, _sizes = _components(passable)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bgmask = np.isin(lab, list(edge))
    holes, hsizes = _components((diff <= hole_tol) & ~bgmask)
    for n, size in enumerate(hsizes):
        if n and size >= hole_min:
            bgmask |= holes == n
    label, sizes = _components(~bgmask)
    keep = int(np.argmax(sizes))
    alpha = Image.fromarray(((label == keep) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))
    out = img.convert("RGBA")
    out.putalpha(alpha)
    out.save(dst)
    return float((label == keep).mean())


def concept(char, seeds, steps=4):
    token = _token()
    client = _client(FLUX, token)
    rev = _revision(FLUX, token)
    out = os.path.join(OUT_DIR, char)
    os.makedirs(out, exist_ok=True)
    prompt = "%s, %s" % (PROMPTS[char], OBJECT_FRAME if char.endswith("/weapon") else FRAME)
    for seed in seeds:
        try:
            result, used = client.predict(prompt=prompt, seed=seed, randomize_seed=False, width=768, height=1024,
                                          num_inference_steps=steps, api_name="/infer")
        except Exception as exc:
            _quota_hint(exc)
        path = result["path"] if isinstance(result, dict) else result
        dst = os.path.join(out, "concept_%d.png" % seed)
        shutil.copyfile(path, dst)
        cover = key_background(dst, os.path.join(out, "concept_%d_rgba.png" % seed))
        _write_json(os.path.join(out, "concept_%d.json" % seed), {
            "space": FLUX, "space_revision": rev, "model_license": "Apache-2.0", "prompt": prompt,
            "key": char, "seed": int(used), "width": 768, "height": 1024, "steps": steps,
            "date": datetime.date.today().isoformat(), "foreground_cover": round(cover, 4)})
        print("ai_gen: concept %s seed %d -> %s (subject %.0f %% of the frame)" % (char, seed, dst, cover * 100))


def mesh(char, concept_png, seed, resolution="1024", decimation=100000, texture=2048):
    token = _token()
    out_root = os.path.join(OUT_DIR, char)
    src = concept_png if os.path.isabs(concept_png) else os.path.join(out_root, concept_png)
    rgba = src if src.endswith("_rgba.png") else src.replace(".png", "_rgba.png")
    if not os.path.exists(rgba):
        key_background(src, rgba)
    from gradio_client import handle_file
    client = _client(TRELLIS, token)
    rev = _revision(TRELLIS, token)
    tag = "trellis_%s_s%d" % (os.path.splitext(os.path.basename(src))[0].replace("_rgba", ""), seed)
    out = os.path.join(out_root, tag)
    os.makedirs(out, exist_ok=True)
    try:
        client.predict(api_name="/start_session")
        prepped = client.predict(handle_file(rgba), api_name="/preprocess_image")  # CPU, keeps our alpha
        client.predict(handle_file(prepped["path"] if isinstance(prepped, dict) else prepped), seed, resolution,
                       api_name="/image_to_3d")
        glb, _dl = client.predict(decimation, texture, api_name="/extract_glb")
    except Exception as exc:
        _quota_hint(exc)
    dst = os.path.join(out, "trellis.glb")
    shutil.copyfile(glb["path"] if isinstance(glb, dict) else glb, dst)
    shutil.copyfile(rgba, os.path.join(out, "input_rgba.png"))
    concept_meta = os.path.splitext(src.replace("_rgba", ""))[0] + ".json"
    _write_json(os.path.join(out, "gen.json"), {
        "key": char, "service": "TRELLIS.2 (microsoft/TRELLIS.2-4B, MIT) via HF Space " + TRELLIS,
        "space_revision": rev, "model_license": "MIT", "seed": seed, "resolution": resolution,
        "decimation_target": decimation, "texture_size": texture,
        "concept": json.load(open(concept_meta, encoding="utf-8")) if os.path.exists(concept_meta) else None,
        "date": datetime.date.today().isoformat()})
    print("ai_gen: mesh %s -> %s (%.1f MB)" % (char, dst, os.path.getsize(dst) / 1e6))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("concept")
    c.add_argument("char", choices=sorted(PROMPTS))
    c.add_argument("--seeds", type=int, nargs="+", default=[1])
    c.add_argument("--steps", type=int, default=4)
    m = sub.add_parser("mesh")
    m.add_argument("char", choices=sorted(PROMPTS))
    m.add_argument("concept")
    m.add_argument("--seed", type=int, default=1)
    m.add_argument("--resolution", default="1024", choices=("512", "1024", "1536"))
    m.add_argument("--texture", type=int, default=2048)
    args = ap.parse_args()
    if args.cmd == "concept":
        concept(args.char, args.seeds, args.steps)
    else:
        mesh(args.char, args.concept, args.seed, args.resolution, texture=args.texture)


if __name__ == "__main__":
    main()
