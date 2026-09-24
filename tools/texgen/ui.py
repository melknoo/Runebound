"""RUNEBOUND M06 UI kit (HUD v2): 9-slice frames and ability icons as pixel
art, drawn from the colour roles in assets/art_spec.json.

Art is drawn at 1x and SAVED at 2x (nearest), so Godot draws it 1:1: chunky
2-px art pixels that stay crisp under any filter. Text stays 1x (Pixelify 20).
  assets/ui/frame.png          24x24 art -> 48x48 panel frame (9-slice margin 16)
  assets/ui/slot.png           22x22 art -> 44x44 ability slot
  assets/ui/bar.png            12x12 art -> 24x24 bar frame (9-slice margin 6)
  assets/ui/button*.png        24x24 art -> 48x48 button states (margin 16)
  assets/ui/cooldown.png       20x20 art -> 40x40 radial cooldown fill
  assets/ui/icons/<id>.png     20x20 art -> 40x40 ability icons

Every icon is drawn in its element's colour role and gets a 1-px dark outline,
so it reads on any slot. Deterministic. Run: python tools/texgen/ui.py
"""
from __future__ import annotations

import json
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
UI_DIR = os.path.join(ROOT, "assets", "ui")
SPEC = json.load(open(os.path.join(ROOT, "assets", "art_spec.json"), encoding="utf-8"))
ROLES = SPEC["color_roles"]


def rgb(h: str, a: int = 255) -> tuple:
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (a,)


INK = rgb(SPEC["outline"]["color"])          # outline / deepest shadow
PANEL = rgb("#161220", 240)
PANEL_HI = rgb("#241C33", 245)
ACCENT = rgb(ROLES["player_accent"]["body"])
ACCENT_HOT = rgb(ROLES["player_accent"]["hot"])
ACCENT_DIM = rgb("#1F5E5A")
GOLD = rgb(ROLES["resonance"]["body"])


SCALE = 2


def save(img: Image.Image, *parts: str) -> None:
    path = os.path.join(UI_DIR, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img = img.resize((img.width * SCALE, img.height * SCALE), Image.NEAREST)
    img.save(path)
    print("  ui/" + "/".join(parts), img.size)


def frame(size: int, fill, rim, rim_hi, corner=True) -> Image.Image:
    """Bevelled pixel frame: ink outline, light top-left rim, dark bottom-right."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, size - 1, size - 1], fill=INK)
    d.rectangle([1, 1, size - 2, size - 2], fill=rim)
    d.rectangle([2, 2, size - 3, size - 3], fill=fill)
    d.line([1, 1, size - 2, 1], fill=rim_hi)
    d.line([1, 1, 1, size - 2], fill=rim_hi)
    if corner:  # rune-cut corners: the Runebreaker's squares + circles language
        for x, y in ((0, 0), (size - 1, 0), (0, size - 1), (size - 1, size - 1)):
            img.putpixel((x, y), (0, 0, 0, 0))
        for x, y in ((3, 3), (size - 4, 3), (3, size - 4), (size - 4, size - 4)):
            img.putpixel((x, y), rim_hi)
    return img


def outlined(icon: Image.Image) -> Image.Image:
    """1-px ink outline around every opaque pixel (8-neighbour dilation)."""
    a = np.array(icon)
    alpha = a[..., 3] > 0
    grown = alpha.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            grown |= np.roll(np.roll(alpha, dy, 0), dx, 1)
    out = np.zeros_like(a)
    out[grown] = INK
    out[alpha] = a[alpha]
    return Image.fromarray(out, "RGBA")


def canvas() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGBA", (20, 20), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def icon_melee() -> Image.Image:
    img, d = canvas()
    steel, steel_hi = rgb(ROLES["physical"]["body"]), rgb(ROLES["physical"]["core"])
    d.arc([1, 1, 18, 18], 200, 340, fill=GOLD, width=2)          # rune-edged sweep
    d.line([4, 16, 15, 5], fill=steel, width=2)                  # blade
    d.line([5, 16, 16, 5], fill=steel_hi)
    d.line([3, 13, 7, 17], fill=GOLD, width=2)                   # guard
    d.line([2, 18, 4, 16], fill=rgb("#624531"), width=2)         # grip
    img.putpixel((12, 8), GOLD)                                   # rune glint
    return outlined(img)


def icon_ember() -> Image.Image:
    img, d = canvas()
    fire = ROLES["fire"]
    d.polygon([(2, 17), (9, 8), (12, 11)], fill=rgb(fire["edge"]))    # flame tail
    d.polygon([(4, 16), (10, 9), (12, 11)], fill=rgb(fire["body"]))
    d.polygon([(10, 9), (17, 2), (12, 11)], fill=rgb(fire["body"]))   # lance head
    d.line([11, 10, 16, 3], fill=rgb(fire["core"]))
    for x, y in ((3, 12), (6, 18), (1, 15)):
        img.putpixel((x, y), rgb(fire["core"]))                        # sparks
    return outlined(img)


def icon_earthbreaker() -> Image.Image:
    img, d = canvas()
    phys = ROLES["physical"]
    d.line([10, 1, 10, 11], fill=rgb(phys["body"]), width=3)            # blade driven down
    d.line([6, 3, 14, 3], fill=GOLD, width=2)                           # guard
    d.line([1, 14, 18, 14], fill=rgb("#8A6B55"), width=2)               # ground
    for x0, x1, y1 in ((9, 4, 18), (11, 16, 18), (10, 10, 19)):
        d.line([x0, 15, x1, y1], fill=rgb(phys["edge"]))                # cracks
    d.arc([2, 8, 17, 20], 180, 360, fill=GOLD)                          # shock arc
    return outlined(img)


def icon_storm_step() -> Image.Image:
    img, d = canvas()
    lit = ROLES["lightning"]
    bolt = [(12, 1), (6, 10), (10, 10), (7, 19), (15, 8), (11, 8), (14, 1)]
    d.polygon(bolt, fill=rgb(lit["body"]))
    d.line([12, 2, 8, 9], fill=rgb(lit["core"]))
    for y in (6, 11, 15):
        d.line([1, y, 4, y], fill=rgb(lit["edge"]))                     # speed lines
    return outlined(img)


def icon_chain_spark() -> Image.Image:
    img, d = canvas()
    lit = ROLES["lightning"]
    nodes = [(3, 15), (9, 5), (16, 13)]
    d.line([3, 15, 6, 11, 5, 9, 9, 5], fill=rgb(lit["body"]))
    d.line([9, 5, 12, 9, 11, 11, 16, 13], fill=rgb(lit["body"]))
    for x, y in nodes:
        d.rectangle([x - 1, y - 1, x + 1, y + 1], fill=rgb(lit["edge"]))
        img.putpixel((x, y), rgb(lit["core"]))
    return outlined(img)


def icon_fracture_rune() -> Image.Image:
    img, d = canvas()
    fr = ROLES["frost"]
    hexagon = [(10, 2), (17, 6), (17, 14), (10, 18), (3, 14), (3, 6)]
    d.polygon(hexagon, outline=rgb(fr["body"]))
    d.polygon([(10, 5), (14, 10), (10, 15), (6, 10)], fill=rgb(fr["edge"]))   # rune core
    d.line([10, 5, 10, 15], fill=rgb(fr["core"]))
    for x, y in ((1, 2), (18, 1), (18, 18)):
        img.putpixel((x, y), rgb(fr["core"]))                                  # shards
    return outlined(img)


def icon_dodge() -> Image.Image:
    img, d = canvas()
    d.arc([2, 3, 16, 17], 110, 350, fill=ACCENT, width=2)                # dash curve
    d.polygon([(14, 3), (19, 6), (14, 9)], fill=ACCENT_HOT)              # arrow head
    for y in (12, 15):
        d.line([1, y, 5, y], fill=ACCENT_DIM)                            # streaks
    return outlined(img)


# --- item icons (inventory): 16x16 art, saved 32x32; neutral materials, the
# rarity reads from the row's text colour. Legendaries get their own art.

def item_canvas() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


STEEL = rgb("#A8AFBC")
STEEL_HI = rgb("#D2D8E2")
IRON = rgb("#4F5766")
IRON_HI = rgb("#838D9C")
WOOD = rgb("#624531")


def item_weapon() -> Image.Image:
    img, d = item_canvas()
    d.line([3, 12, 13, 2], fill=STEEL, width=2)
    d.line([4, 12, 13, 3], fill=STEEL_HI)
    d.line([2, 9, 6, 13], fill=GOLD, width=2)
    d.line([1, 15, 3, 13], fill=WOOD, width=2)
    return outlined(img)


def item_armor() -> Image.Image:
    img, d = item_canvas()
    d.polygon([(3, 3), (6, 2), (10, 2), (13, 3), (13, 8), (11, 14), (5, 14), (3, 8)], fill=IRON)
    d.line([4, 4, 12, 4], fill=IRON_HI)
    d.line([8, 5, 8, 12], fill=IRON_HI)
    d.rectangle([1, 3, 3, 6], fill=IRON_HI)
    d.rectangle([13, 3, 15, 6], fill=IRON_HI)
    return outlined(img)


def item_relic() -> Image.Image:
    img, d = item_canvas()
    d.ellipse([3, 1, 12, 8], outline=GOLD)
    d.polygon([(8, 7), (12, 11), (8, 15), (4, 11)], fill=rgb(ROLES["player_accent"]["body"]))
    d.line([8, 8, 8, 14], fill=rgb(ROLES["player_accent"]["hot"]))
    return outlined(img)


def item_helm() -> Image.Image:
    img, d = item_canvas()
    d.pieslice([2, 2, 13, 15], 180, 360, fill=IRON)
    d.rectangle([2, 8, 13, 12], fill=IRON)
    d.line([4, 9, 11, 9], fill=rgb("#16121C"), width=1)       # visor slit
    d.line([7, 1, 8, 1], fill=rgb(ROLES["player_accent"]["body"]))
    d.line([3, 4, 12, 4], fill=IRON_HI)
    return outlined(img)


def item_gloves() -> Image.Image:
    img, d = item_canvas()
    d.rectangle([4, 7, 11, 14], fill=IRON)                    # cuff + back of hand
    for x in (4, 6, 8, 10):
        d.rectangle([x, 2, x + 1, 7], fill=IRON_HI)           # fingers
    d.rectangle([12, 6, 13, 10], fill=IRON_HI)                # thumb
    d.line([4, 12, 11, 12], fill=GOLD)
    return outlined(img)


def item_boots() -> Image.Image:
    img, d = item_canvas()
    d.rectangle([4, 2, 9, 11], fill=IRON)
    d.rectangle([4, 11, 14, 14], fill=IRON)
    d.line([4, 5, 9, 5], fill=IRON_HI)
    d.line([4, 11, 14, 11], fill=GOLD)
    return outlined(img)


def item_ring() -> Image.Image:
    img, d = item_canvas()
    d.ellipse([3, 5, 12, 14], outline=GOLD, width=2)
    d.polygon([(7, 1), (10, 4), (7, 7), (4, 4)], fill=rgb(ROLES["player_accent"]["body"]))
    d.point((7, 3), fill=rgb(ROLES["player_accent"]["hot"]))
    return outlined(img)


def legendary_cindermaw() -> Image.Image:
    img, d = item_canvas()
    fire = ROLES["fire"]
    d.polygon([(3, 12), (11, 1), (14, 2), (6, 13)], fill=rgb("#2A2428"))
    d.line([6, 12, 13, 3], fill=rgb(fire["body"]))
    d.line([7, 12, 13, 4], fill=rgb(fire["core"]))
    d.line([2, 9, 6, 13], fill=GOLD, width=2)
    d.line([1, 15, 3, 13], fill=rgb("#2A2428"), width=2)
    return outlined(img)


def legendary_conductors_oath() -> Image.Image:
    img, d = item_canvas()
    lit = ROLES["lightning"]
    for x in (4, 8, 12):
        d.line([x, 2, 8, 8], fill=IRON_HI)
        d.line([x, 14, 8, 8], fill=IRON_HI)
    d.rectangle([6, 6, 10, 10], fill=rgb(lit["body"]))
    d.rectangle([7, 7, 9, 9], fill=rgb(lit["core"]))
    for x, y in ((1, 5), (14, 11), (13, 1)):
        img.putpixel((x, y), rgb(lit["edge"]))
    return outlined(img)


def legendary_glacier_heart() -> Image.Image:
    img, d = item_canvas()
    fr = ROLES["frost"]
    d.polygon([(3, 3), (6, 2), (10, 2), (13, 3), (13, 8), (11, 14), (5, 14), (3, 8)], fill=STEEL)
    d.polygon([(8, 4), (11, 8), (8, 12), (5, 8)], fill=rgb(fr["body"]))
    d.line([8, 5, 8, 11], fill=rgb(fr["core"]))
    img.putpixel((2, 1), rgb(fr["core"]))
    img.putpixel((14, 13), rgb(fr["core"]))
    return outlined(img)


def icon_runic_guard() -> Image.Image:
    img, d = canvas()
    shield = [(10, 1), (17, 4), (16, 12), (10, 18), (4, 12), (3, 4)]
    d.polygon(shield, fill=rgb("#1F5E5A"), outline=ACCENT)
    d.polygon([(10, 5), (13, 9), (10, 14), (7, 9)], fill=GOLD)                  # rune diamond
    d.line([10, 6, 10, 13], fill=rgb(ROLES["resonance"]["hot"]))
    return outlined(img)


def icon_resonance_burst() -> Image.Image:
    img, d = canvas()
    hot = rgb(ROLES["resonance"]["hot"])
    for k in range(8):
        import math
        a = k * math.tau / 8
        d.line([10, 10, 10 + int(round(math.cos(a) * 8)), 10 + int(round(math.sin(a) * 8))], fill=GOLD)
    d.ellipse([6, 6, 14, 14], fill=GOLD)
    d.ellipse([8, 8, 12, 12], fill=hot)
    return outlined(img)


def main() -> None:
    print("UI kit:")
    save(frame(24, PANEL, ACCENT_DIM, ACCENT), "frame.png")
    save(frame(22, rgb("#100C18", 235), rgb("#2E2A3A"), rgb("#4A4458")), "slot.png")
    save(frame(12, rgb("#0E0A14", 230), rgb("#2E2A3A"), rgb("#4A4458"), corner=False), "bar.png")
    save(frame(24, PANEL_HI, ACCENT_DIM, ACCENT), "button.png")
    save(frame(24, rgb("#2C2440", 250), ACCENT, ACCENT_HOT), "button_hover.png")
    save(frame(24, rgb("#0E0A14", 250), ACCENT_DIM, ACCENT_DIM), "button_pressed.png")
    cd = Image.new("RGBA", (20, 20), (13, 10, 20, 205))
    save(cd, "cooldown.png")
    for name, fn in (("rune_cleave", icon_melee), ("ember_lance", icon_ember), ("earthbreaker", icon_earthbreaker),
                     ("storm_step", icon_storm_step), ("chain_spark", icon_chain_spark),
                     ("fracture_rune", icon_fracture_rune), ("dodge", icon_dodge),
                     ("runic_guard", icon_runic_guard), ("resonance_burst", icon_resonance_burst)):
        save(fn(), "icons", name + ".png")
    for name, fn in (("weapon", item_weapon), ("armor", item_armor), ("relic", item_relic),
                     ("helm", item_helm), ("gloves", item_gloves), ("boots", item_boots), ("ring", item_ring),
                     ("cindermaw", legendary_cindermaw), ("conductors_oath", legendary_conductors_oath),
                     ("glacier_heart", legendary_glacier_heart)):
        save(fn(), "items", name + ".png")


if __name__ == "__main__":
    main()
