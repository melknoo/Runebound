"""Rig v3: give every hero look GLB and atlas the legacy rigs' import settings
(60 fps clips, named skins, shadow meshes; atlases lossless with mipmaps).

Godot writes a fresh .import with its defaults the first time it sees a new
file (30 fps, no named skins, 3D textures VRAM-compressed), so after a new
look: tools\\run_godot.cmd import, then this, then import again.

  python tools/modelgen/hero_import.py
"""
import glob
import os

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
TEMPLATES = (
    ("assets/models/chars/hero/*/*.glb.import", "assets/models/chars/runebreaker.glb.import"),
    ("assets/textures/char/hero/*.png.import", "assets/textures/char/runebreaker_atlas.png.import"),
)


def params(path):
    text = open(path, encoding="utf-8").read().replace("\r\n", "\n")
    return text[text.index("[params]"):]


def main():
    changed = 0
    for pattern, template in TEMPLATES:
        want = params(os.path.join(ROOT, template))
        for path in sorted(glob.glob(os.path.join(ROOT, pattern))):
            text = open(path, encoding="utf-8").read().replace("\r\n", "\n")
            fixed = text[:text.index("[params]")] + want
            if fixed != text:
                open(path, "w", encoding="utf-8", newline="\n").write(fixed)
                changed += 1
                print("hero_import: settings ->", os.path.relpath(path, ROOT))
    print("hero_import: %d file(s) changed" % changed)


if __name__ == "__main__":
    main()
