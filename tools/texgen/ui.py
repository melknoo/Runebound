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
import math
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
UI_DIR = os.path.join(ROOT, "assets", "ui")
SPEC = json.load(open(os.path.join(ROOT, "assets", "art_spec.json"), encoding="utf-8"))
ROLES = SPEC["color_roles"]
PALETTES = SPEC["palettes"]


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


def icon_coin() -> Image.Image:
    """M07b gold counter: a rune-notched coin in Resonance gold."""
    img, d = canvas()
    hot = rgb(ROLES["resonance"].get("hot", ROLES["resonance"]["body"]))
    dim = rgb("#A67A22")
    d.ellipse([3, 4, 16, 17], fill=dim)                          # underside / rim shadow
    d.ellipse([3, 3, 16, 16], fill=GOLD)                         # face
    d.ellipse([6, 6, 13, 13], fill=hot)                          # polished centre
    d.line([9, 7, 9, 12], fill=dim)                              # rune notch
    d.line([7, 9, 11, 9], fill=dim)
    img.putpixel((6, 5), (255, 255, 255, 230))                   # glint
    return outlined(img)


def icon_healing_draught() -> Image.Image:
    """M10b consumable: a round flask of health-red draught with a cork and a
    glint - the colour of the HUD's health bar it refills."""
    img, d = canvas()
    health = ROLES["health"]
    red, hot, edge = rgb(health["body"]), rgb(health["hot"]), rgb(health["edge"])
    glass = rgb("#B8C4D0")
    d.ellipse([4, 7, 15, 18], fill=glass)                         # the bulb (glass rim)
    d.ellipse([5, 9, 14, 17], fill=red)                           # the draught inside
    d.chord([5, 9, 14, 17], 50, 130, fill=edge)                   # a thin shadow at the bottom
    d.line([6, 10, 13, 10], fill=hot)                             # its flat, lit surface
    d.rectangle([8, 3, 11, 7], fill=glass)                        # the neck
    d.rectangle([8, 1, 11, 3], fill=rgb("#7A5436"))               # the cork
    d.line([8, 1, 11, 1], fill=rgb("#A8784E"))
    img.putpixel((7, 10), (255, 255, 255, 235))                   # glint
    img.putpixel((7, 11), (255, 255, 255, 150))
    return outlined(img)


def icon_rune_bolt() -> Image.Image:
    """M10 Elementalist basic attack: an arcane dart in the player teal, a
    rune-cut head with a stepped wake (the hero's own bolt, never void violet)."""
    img, d = canvas()
    d.polygon([(18, 1), (15, 8), (10, 10), (11, 4)], fill=ACCENT)       # kite head, tip up-right
    d.polygon([(18, 1), (15, 8), (13, 7)], fill=ACCENT_DIM)             # shaded flank
    d.line([12, 8, 17, 2], fill=ACCENT_HOT)                             # hot spine
    d.rectangle([7, 10, 9, 12], fill=ACCENT)                            # wake, stepping down
    d.rectangle([4, 13, 5, 14], fill=ACCENT_DIM)
    img.putpixel((2, 16), ACCENT_DIM)
    img.putpixel((1, 18), ACCENT_DIM)
    img.putpixel((12, 6), rgb("#FFFFFF"))                               # rune glint
    img.putpixel((8, 11), ACCENT_HOT)
    return outlined(img)


def icon_rune_wall() -> Image.Image:
    """M10 tank block: the rune blade held across, a teal ward arcing over it,
    a spark where a blow glances off."""
    img, d = canvas()
    phys = ROLES["physical"]
    hot = rgb(ROLES["resonance"]["hot"])
    d.chord([2, 1, 18, 17], 180, 360, fill=ACCENT_DIM, outline=ACCENT)    # the ward, upper half-disc
    d.arc([5, 4, 15, 14], 200, 340, fill=ACCENT_HOT)                         # inner rim
    for x in (6, 10, 14):
        img.putpixel((x, 5 if x != 10 else 3), GOLD)                        # rune ticks on the ward
    d.line([1, 12, 15, 12], fill=rgb(phys["body"]), width=3)                 # blade across, below the ward
    d.line([1, 12, 15, 12], fill=rgb(phys["core"]))
    d.line([15, 10, 15, 14], fill=GOLD, width=2)                             # guard
    d.line([16, 12, 18, 12], fill=rgb("#624531"), width=2)                   # grip
    for x, y in ((3, 8), (1, 7), (4, 6)):
        img.putpixel((x, y), hot)                                            # glancing spark
    return outlined(img)


def icon_rune_chain() -> Image.Image:
    """M10 pull: a gold rune chain snaking in from the top right, its rune hook
    biting, an arrow back towards the hero."""
    img, d = canvas()
    hot = rgb(ROLES["resonance"]["hot"])
    dim = rgb("#A67A22")
    for i, (x, y) in enumerate(((3, 14), (6, 11), (9, 8), (12, 5))):
        d.ellipse([x, y, x + 4, y + 3], outline=GOLD if i % 2 == 0 else dim)  # links, alternating light
    d.ellipse([14, 1, 19, 6], fill=ACCENT_DIM, outline=ACCENT)               # the rune hook
    img.putpixel((16, 3), ACCENT_HOT)
    img.putpixel((17, 4), ACCENT_HOT)
    d.line([1, 19, 5, 15], fill=hot)                                         # pull arrow
    d.line([1, 19, 1, 16], fill=hot)
    d.line([1, 19, 4, 19], fill=hot)
    return outlined(img)


def icon_warden_leap() -> Image.Image:
    """M10 leap: a high arc of steel ending in a gold impact on the ground."""
    img, d = canvas()
    phys = ROLES["physical"]
    hot = rgb(ROLES["resonance"]["hot"])
    d.arc([2, 3, 18, 25], 200, 330, fill=rgb(phys["edge"]), width=2)       # the flight arc
    d.arc([2, 3, 18, 25], 215, 320, fill=rgb(phys["body"]))
    d.polygon([(15, 12), (18, 12), (16, 15)], fill=rgb(phys["core"]))       # arrow head coming down
    d.line([10, 18, 19, 18], fill=GOLD)                                      # ground line
    for x, y in ((12, 17), (14, 16), (16, 16), (18, 17)):
        img.putpixel((x, y), hot)                                            # impact burst
    d.line([15, 18, 13, 19], fill=GOLD)
    d.line([16, 18, 18, 19], fill=GOLD)
    d.line([2, 17, 6, 17], fill=rgb(phys["edge"]))                           # take-off scuff
    return outlined(img)


def icon_warding_rune() -> Image.Image:
    """M10 ally ward: a rune circle on the ground (seen at an angle) with a
    shield glyph standing in it."""
    img, d = canvas()
    hot = rgb(ROLES["resonance"]["hot"])
    d.ellipse([1, 11, 18, 19], outline=ACCENT)                               # the ground circle
    d.ellipse([4, 13, 15, 17], outline=ACCENT_DIM)
    for x, y in ((2, 15), (17, 15), (9, 19), (9, 11)):
        img.putpixel((x, y), GOLD)                                           # rune marks on the ring
    shield = [(9, 2), (14, 4), (13, 10), (9, 14), (5, 10), (4, 4)]
    d.polygon(shield, fill=ACCENT_DIM, outline=ACCENT_HOT)                   # the glyph above it
    d.line([9, 4, 9, 11], fill=GOLD)
    d.line([7, 7, 11, 7], fill=hot)
    return outlined(img)


def icon_flame_wall() -> Image.Image:
    """M10 Elementalist: a low wall of flame tongues standing on a line."""
    img, d = canvas()
    fire = ROLES["fire"]
    edge, body, core = rgb(fire["edge"]), rgb(fire["body"]), rgb(fire["core"])
    d.line([1, 17, 18, 17], fill=edge, width=2)                                # the burning line
    for x, h in ((2, 7), (6, 11), (10, 13), (14, 10), (17, 6)):
        d.polygon([(x - 2, 17), (x, 17 - h), (x + 2, 17)], fill=body)         # flame tongues
        d.line([x, 16, x, 17 - h + 3], fill=core)
    for x, y in ((4, 6), (12, 2), (16, 8)):
        img.putpixel((x, y), core)                                            # sparks
    return outlined(img)


def icon_ball_lightning() -> Image.Image:
    """M10 Elementalist: a crackling orb with forks reaching out."""
    img, d = canvas()
    lt = ROLES["lightning"]
    edge, body, core = rgb(lt["edge"]), rgb(lt["body"]), rgb(lt["core"])
    d.ellipse([5, 5, 14, 14], fill=edge)
    d.ellipse([6, 6, 13, 13], fill=body)
    d.ellipse([8, 8, 11, 11], fill=core)
    for pts in (((14, 7), (16, 5), (18, 6)), ((5, 12), (3, 14), (1, 13)), ((12, 14), (13, 17), (11, 19)),
                ((7, 5), (6, 2), (8, 1))):
        d.line([pts[0], pts[1]], fill=body)
        d.line([pts[1], pts[2]], fill=core)
    return outlined(img)


def icon_ember_fall() -> Image.Image:
    """M10 Elementalist: a burning rock plunging down onto a ground burst."""
    img, d = canvas()
    fire = ROLES["fire"]
    edge, body, core = rgb(fire["edge"]), rgb(fire["body"]), rgb(fire["core"])
    rock = rgb(PALETTES["highlands"]["basalt"][2]) if "basalt" in PALETTES.get("highlands", {}) else rgb("#3A3438")
    d.line([3, 1, 9, 9], fill=edge, width=3)                                   # the fiery tail
    d.line([4, 1, 9, 8], fill=body)
    d.ellipse([7, 6, 13, 12], fill=rock)                                       # the rock
    d.ellipse([10, 9, 13, 12], fill=core)                                      # its molten face
    d.line([4, 18, 18, 18], fill=edge)                                         # ground
    d.polygon([(8, 18), (11, 13), (14, 18)], fill=body)                        # impact burst
    for x, y in ((6, 16), (16, 15), (12, 12)):
        img.putpixel((x, y), core)
    return outlined(img)


# ---------------------------------------------------------------------------
# Drafts from the 2026-09-29 icon comparison (ROADMAP "Icon-Quelle"). Not saved
# by main() yet: register each under its ability id once the ability exists
# (the taunt is Rune Challenge since M10; frost nova comes with M10 phase 3,
# the healing zone with M11).
# ---------------------------------------------------------------------------

# The root druid's ramp (hue ~100 deg, yellower than the player teal): since
# M11 color_roles.nature in art_spec.json (its "hot" is the icons' core).
NATURE = {"edge": ROLES["nature"]["edge"], "body": ROLES["nature"]["body"], "core": ROLES["nature"]["hot"]}


def icon_taunt() -> Image.Image:
    """War cry: the Runebreaker's great helm with a T visor, gold shout arcs to both sides."""
    img, d = canvas()
    phys = ROLES["physical"]
    edge, body, core = rgb(phys["edge"]), rgb(phys["body"]), rgb(phys["core"])
    hot = rgb(ROLES["resonance"]["hot"])
    d.rectangle([6, 5, 13, 16], fill=edge)                       # helm shell (shadowed steel)
    d.line([7, 4, 12, 4], fill=edge)                             # rounded crown
    d.rectangle([6, 5, 9, 16], fill=body)                        # lit half
    d.line([7, 4, 9, 4], fill=body)
    d.line([6, 5, 6, 8], fill=core)                              # glint
    d.line([6, 7, 13, 7], fill=GOLD)                             # rune band
    img.putpixel((9, 7), hot)
    d.line([7, 10, 12, 10], fill=INK)                            # T visor
    d.line([9, 11, 9, 14], fill=INK)
    d.line([10, 11, 10, 14], fill=INK)
    d.arc([2, 4, 17, 17], 320, 40, fill=GOLD)                    # inner shout arcs
    d.arc([2, 4, 17, 17], 140, 220, fill=GOLD)
    d.arc([0, 2, 19, 19], 325, 35, fill=hot)                     # outer arcs
    d.arc([0, 2, 19, 19], 145, 215, fill=hot)
    return outlined(img)


def icon_frost_nova() -> Image.Image:
    """A ring of angular ice shards bursting out of a bright core."""
    img, d = canvas()
    fr = ROLES["frost"]
    edge, body, core = rgb(fr["edge"]), rgb(fr["body"]), rgb(fr["core"])
    cx = cy = 9.5
    for k in range(8):
        a = k * math.tau / 8 - math.pi / 2
        r_out = 9.2 if k % 2 == 0 else 7.2
        tip = (cx + math.cos(a) * r_out, cy + math.sin(a) * r_out)
        side = a + math.pi / 2
        base = 4.0
        w = 1.9 if k % 2 == 0 else 1.5
        left = (cx + math.cos(a) * base + math.cos(side) * w, cy + math.sin(a) * base + math.sin(side) * w)
        right = (cx + math.cos(a) * base - math.cos(side) * w, cy + math.sin(a) * base - math.sin(side) * w)
        mid = (cx + math.cos(a) * (base + 0.6), cy + math.sin(a) * (base + 0.6))
        d.polygon([left, tip, mid], fill=body)                   # lit face
        d.polygon([mid, tip, right], fill=edge)                  # shadow face
    d.ellipse([6, 6, 13, 13], fill=edge)                         # nova ring
    d.ellipse([7, 7, 12, 12], fill=INK)
    d.polygon([(9.5, 7.5), (11.5, 9.5), (9.5, 11.5), (7.5, 9.5)], fill=core)   # core crystal
    return outlined(img)


def icon_healing_zone() -> Image.Image:
    """A rune circle on the ground, a sprout rising from it, healing motes above."""
    img, d = canvas()
    edge, body, core = rgb(NATURE["edge"]), rgb(NATURE["body"]), rgb(NATURE["core"])
    d.ellipse([1, 12, 18, 18], fill=edge)                        # zone on the ground
    d.ellipse([2, 13, 17, 17], outline=body)                     # rune ring
    for x, y in ((4, 14), (15, 14), (9, 17), (10, 13)):
        img.putpixel((x, y), core)                               # ring runes
    d.line([9, 15, 9, 8], fill=body)                             # stem
    d.line([10, 15, 10, 9], fill=edge)
    leaves = {9: (4, 5), 10: (4, 7), 11: (5, 8), 12: (7, 8)}     # left leaf, row: (x0, x1)
    leaves_r = {8: (14, 15), 9: (12, 15), 10: (11, 14), 11: (11, 12)}
    for rows in (leaves, leaves_r):
        for y, (x0, x1) in rows.items():
            d.line([x0, y, x1, y], fill=body)
    img.putpixel((5, 10), core)                                  # leaf veins
    img.putpixel((13, 9), core)
    img.putpixel((9, 8), core)                                   # bud
    d.rectangle([13, 1, 14, 6], fill=core)                       # healing cross
    d.rectangle([11, 3, 16, 4], fill=core)
    for x, y in ((4, 5), (3, 6), (4, 6), (5, 6), (4, 7)):
        img.putpixel((x, y), body)                               # small rising cross
    return outlined(img)


# ---------------------------------------------------------------------------
# M11 root druid: nature green on bark brown (thorns, roots, totems, blooms).
# ---------------------------------------------------------------------------

BARK = {"edge": "#2A1C18", "body": "#54392C", "core": "#7A5640"}


def _nat() -> tuple:
    return rgb(NATURE["edge"]), rgb(NATURE["body"]), rgb(NATURE["core"])


def _bark() -> tuple:
    return rgb(BARK["edge"]), rgb(BARK["body"]), rgb(BARK["core"])


def icon_thorn_volley() -> Image.Image:
    """Basic attack: three thorns fanning out to the upper right, green-tipped."""
    img, d = canvas()
    n_edge, n_body, n_core = _nat()
    b_edge, b_body, b_core = _bark()
    for (x0, y0, x1, y1) in ((2, 17, 11, 4), (3, 18, 16, 8), (1, 13, 7, 1)):
        d.line([x0, y0, x1, y1], fill=b_body, width=2)            # thorn shaft
        d.line([x0, y0, x1, y1], fill=b_core)
        d.polygon([(x1, y1), (x1 - 3, y1 + 1), (x1 - 1, y1 + 3)], fill=n_body)   # green tip
        img.putpixel((x1, y1), n_core)
    img.putpixel((5, 12), n_edge)                                   # little barbs
    img.putpixel((9, 13), n_edge)
    img.putpixel((4, 8), n_edge)
    return outlined(img)


def icon_mending_bloom() -> Image.Image:
    """Start heal: a bud bursting open, a healing cross in its heart."""
    img, d = canvas()
    n_edge, n_body, n_core = _nat()
    d.line([9, 18, 9, 11], fill=n_edge, width=2)                    # stem
    d.polygon([(9, 15), (4, 13), (6, 16)], fill=n_body)             # leaves
    d.polygon([(10, 16), (15, 13), (14, 17)], fill=n_edge)
    for k in range(5):                                              # petals
        a = k * math.tau / 5 - math.pi / 2
        cx, cy = 9.5 + math.cos(a) * 4.2, 7.5 + math.sin(a) * 4.2
        d.ellipse([cx - 2.4, cy - 2.4, cx + 2.4, cy + 2.4], fill=n_body if k % 2 == 0 else n_edge)
    d.ellipse([6, 4, 13, 11], fill=n_body)
    d.rectangle([9, 5, 10, 10], fill=n_core)                        # healing cross
    d.rectangle([7, 7, 12, 8], fill=n_core)
    return outlined(img)


def icon_barkskin() -> Image.Image:
    """Shield: a bark-plated kite shield, a green leaf vein down its middle."""
    img, d = canvas()
    n_edge, n_body, n_core = _nat()
    b_edge, b_body, b_core = _bark()
    d.polygon([(3, 2), (16, 2), (16, 9), (9.5, 18), (3, 9)], fill=b_edge)
    d.polygon([(4, 3), (9, 3), (9, 16), (4, 9)], fill=b_core)       # lit half
    d.polygon([(10, 3), (15, 3), (15, 9), (10, 16)], fill=b_body)
    for y in (5, 8, 11):                                            # bark grain
        d.line([5, y, 8, y + 1], fill=b_body)
        d.line([11, y + 1, 14, y], fill=b_edge)
    d.line([9, 3, 9, 16], fill=n_body)                              # leaf vein
    d.line([10, 3, 10, 15], fill=n_edge)
    img.putpixel((9, 4), n_core)
    return outlined(img)


def icon_regrowth() -> Image.Image:
    """Heal over time: a sprout curling round in a circle, leaves along it."""
    img, d = canvas()
    n_edge, n_body, n_core = _nat()
    d.arc([2, 2, 17, 17], 110, 400, fill=n_body, width=2)           # the curl
    d.arc([3, 3, 16, 16], 120, 390, fill=n_edge)
    d.polygon([(3, 12), (0, 16), (5, 15)], fill=n_body)             # arrow tip: it comes round again
    for (x, y) in ((15, 5), (16, 12), (6, 2)):
        d.ellipse([x - 2, y - 1, x + 1, y + 1], fill=n_body)        # leaves on the curl
        img.putpixel((x - 1, y), n_core)
    d.line([9, 13, 9, 8], fill=n_edge)                              # seedling in the middle
    d.polygon([(9, 9), (6, 7), (8, 10)], fill=n_body)
    d.polygon([(10, 8), (13, 6), (11, 10)], fill=n_body)
    img.putpixel((9, 8), n_core)
    return outlined(img)


def icon_root_grasp() -> Image.Image:
    """Roots clawing up out of the ground like a grasping hand."""
    img, d = canvas()
    n_edge, n_body, n_core = _nat()
    b_edge, b_body, b_core = _bark()
    d.rectangle([0, 16, 19, 19], fill=b_edge)                       # ground
    d.line([0, 16, 19, 16], fill=b_body)
    for (x0, x1, top, bend) in ((3, 1, 6, -2), (7, 6, 3, -1), (11, 12, 2, 1), (15, 17, 5, 2)):
        d.line([x0, 16, x0 + bend, 10], fill=b_body, width=2)       # root fingers
        d.line([x0 + bend, 10, x1, top], fill=b_body, width=2)
        d.line([x0, 16, x0 + bend, 10], fill=b_core)
        img.putpixel((x1, top), n_core)                              # green tips
        img.putpixel((x1, top + 1), n_body)
    d.line([4, 12, 16, 12], fill=n_edge)                             # the root's bind
    return outlined(img)


def icon_thornfield() -> Image.Image:
    """A patch of thorn spikes on the ground, a green haze over it."""
    img, d = canvas()
    n_edge, n_body, n_core = _nat()
    b_edge, b_body, b_core = _bark()
    d.ellipse([0, 12, 19, 19], fill=b_edge)                         # the patch
    d.ellipse([2, 13, 17, 18], outline=n_edge)
    for (x, h) in ((3, 6), (6, 9), (9, 11), (12, 8), (15, 10), (17, 5)):
        d.polygon([(x - 1, 16), (x + 1, 16), (x, 16 - h)], fill=b_core)   # spikes
        img.putpixel((x, 16 - h), n_core)
        img.putpixel((x, 17 - h), n_body)
    for (x, y) in ((5, 4), (11, 2), (14, 5)):
        img.putpixel((x, y), n_body)                                # haze motes
    return outlined(img)


def icon_growth_totem() -> Image.Image:
    """A carved wooden totem with glowing eyes and a leaf crown, a buff ring at its foot."""
    img, d = canvas()
    n_edge, n_body, n_core = _nat()
    b_edge, b_body, b_core = _bark()
    d.ellipse([2, 15, 17, 19], outline=n_body)                      # aura ring
    d.rectangle([6, 5, 13, 17], fill=b_body)                        # the post
    d.rectangle([6, 5, 8, 17], fill=b_core)
    d.line([6, 10, 13, 10], fill=b_edge)                             # carved bands
    d.line([6, 14, 13, 14], fill=b_edge)
    img.putpixel((8, 7), n_core)                                     # eyes
    img.putpixel((11, 7), n_core)
    d.line([8, 12, 11, 12], fill=n_body)                             # mouth rune
    d.polygon([(9, 5), (4, 1), (7, 5)], fill=n_body)                 # leaf crown
    d.polygon([(10, 5), (15, 1), (12, 5)], fill=n_body)
    d.polygon([(9, 5), (10, 0), (11, 5)], fill=n_edge)
    img.putpixel((3, 12), n_core)                                    # rising motes
    img.putpixel((16, 10), n_core)
    return outlined(img)


def icon_wild_bloom() -> Image.Image:
    """The great heal: a flower blowing wide open, petals and light flying out."""
    img, d = canvas()
    n_edge, n_body, n_core = _nat()
    for k in range(8):
        a = k * math.tau / 8
        x1, y1 = 9.5 + math.cos(a) * 9.0, 9.5 + math.sin(a) * 9.0
        d.line([9.5, 9.5, x1, y1], fill=n_edge)                      # light rays
    for k in range(6):
        a = k * math.tau / 6 + 0.3
        cx, cy = 9.5 + math.cos(a) * 5.0, 9.5 + math.sin(a) * 5.0
        d.ellipse([cx - 2.6, cy - 2.6, cx + 2.6, cy + 2.6], fill=n_body)   # petals
    d.ellipse([6, 6, 13, 13], fill=n_core)                           # bright heart
    d.ellipse([8, 8, 11, 11], fill=n_body)
    for (x, y) in ((1, 2), (18, 3), (2, 17), (17, 17)):
        img.putpixel((x, y), n_core)                                 # flying petals
    return outlined(img)


# ---------------------------------------------------------------------------
# M08 map / compass icons: 12x12 art -> 24x24, one colour role each, ink outline.
# ---------------------------------------------------------------------------

def canvas12() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGBA", (12, 12), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def mk_player() -> Image.Image:
    img, d = canvas12()
    d.polygon([(6, 1), (10, 10), (6, 8), (2, 10)], fill=ACCENT_HOT)
    d.line([6, 3, 6, 8], fill=ACCENT)
    return outlined(img)


def mk_waypoint() -> Image.Image:
    img, d = canvas12()
    d.polygon([(6, 1), (10, 6), (6, 10), (2, 6)], fill=ACCENT)
    d.polygon([(6, 3), (8, 6), (6, 8), (4, 6)], fill=ACCENT_HOT)
    d.point((6, 6), fill=(255, 255, 255, 240))
    return outlined(img)


def mk_portal() -> Image.Image:
    img, d = canvas12()
    d.ellipse([1, 1, 10, 10], outline=ACCENT, width=2)
    d.point((6, 1), fill=ACCENT_HOT)
    d.point((6, 10), fill=ACCENT_HOT)
    return outlined(img)


def mk_camp() -> Image.Image:
    img, d = canvas12()
    fire, core = rgb(ROLES["fire"]["body"]), rgb(ROLES["fire"]["core"])
    d.rectangle([2, 9, 9, 10], fill=rgb("#4A2A1C"))
    d.polygon([(6, 1), (9, 6), (8, 9), (4, 9), (3, 6)], fill=fire)
    d.polygon([(6, 4), (7, 7), (6, 9), (5, 7)], fill=core)
    return outlined(img)


def mk_camp_cleared() -> Image.Image:
    img, d = canvas12()
    grey = rgb("#6A6070")
    d.rectangle([2, 9, 9, 10], fill=rgb("#3A3038"))
    d.polygon([(6, 2), (9, 6), (8, 9), (4, 9), (3, 6)], outline=grey)
    d.line([3, 3, 9, 9], fill=grey)
    return outlined(img)


def mk_chest() -> Image.Image:
    img, d = canvas12()
    d.rectangle([1, 4, 10, 10], fill=GOLD)
    d.rectangle([1, 3, 10, 5], fill=rgb("#A67A22"))
    d.rectangle([5, 6, 6, 8], fill=INK)
    return outlined(img)


def mk_ruin() -> Image.Image:
    img, d = canvas12()
    stone = rgb("#7A6F78")
    d.rectangle([1, 3, 3, 10], fill=stone)
    d.rectangle([8, 5, 10, 10], fill=stone)
    d.rectangle([1, 2, 5, 3], fill=stone)
    d.rectangle([5, 9, 6, 10], fill=stone)
    return outlined(img)


def mk_landmark() -> Image.Image:
    img, d = canvas12()
    d.polygon([(5, 1), (7, 1), (8, 10), (4, 10)], fill=rgb("#8A8290"))
    d.line([6, 3, 6, 7], fill=ACCENT_DIM)
    return outlined(img)


def mk_boss() -> Image.Image:
    img, d = canvas12()
    red = rgb(ROLES["threat"]["body"])
    d.rectangle([2, 1, 9, 8], fill=red)
    d.rectangle([3, 8, 8, 10], fill=red)
    d.rectangle([3, 3, 4, 5], fill=INK)
    d.rectangle([7, 3, 8, 5], fill=INK)
    d.point((6, 9), fill=INK)
    return outlined(img)


def mk_dungeon() -> Image.Image:
    img, d = canvas12()
    void = rgb(ROLES["void"]["body"]) if "void" in ROLES else rgb("#7A4FB0")
    d.rectangle([2, 5, 9, 10], fill=void)
    d.ellipse([2, 1, 9, 8], fill=void)
    d.rectangle([5, 5, 6, 10], fill=INK)
    return outlined(img)


def knob(fill, rim, rim_hi) -> Image.Image:
    """M17a settings: a slider grabber, 8x12 art (bevelled like frame())."""
    w, h = 8, 12
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w - 1, h - 1], fill=INK)
    d.rectangle([1, 1, w - 2, h - 2], fill=rim)
    d.rectangle([2, 2, w - 3, h - 3], fill=fill)
    d.line([1, 1, w - 2, 1], fill=rim_hi)
    d.line([1, 1, 1, h - 2], fill=rim_hi)
    for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        img.putpixel((x, y), (0, 0, 0, 0))
    return img


def check_box(on: bool) -> Image.Image:
    """M17a settings: a checkbox, 12x12 art; ticked = an accent block inside."""
    img = frame(12, rgb("#100C18", 235), rgb("#2E2A3A"), rgb("#4A4458"), corner=False)
    if on:
        d = ImageDraw.Draw(img)
        d.rectangle([3, 3, 8, 8], fill=ACCENT)
        d.line([3, 3, 8, 3], fill=ACCENT_HOT)
        d.line([3, 3, 3, 8], fill=ACCENT_HOT)
    return img


def main() -> None:
    print("UI kit:")
    for name, fn in (("player", mk_player), ("waypoint", mk_waypoint), ("portal", mk_portal), ("camp", mk_camp),
                     ("camp_cleared", mk_camp_cleared), ("chest", mk_chest), ("ruin", mk_ruin),
                     ("landmark", mk_landmark), ("boss", mk_boss), ("dungeon", mk_dungeon)):
        save(fn(), "map", name + ".png")
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
                     ("runic_guard", icon_runic_guard), ("resonance_burst", icon_resonance_burst),
                     ("rune_bolt", icon_rune_bolt), ("rune_challenge", icon_taunt), ("rune_wall", icon_rune_wall),
                     ("rune_chain", icon_rune_chain), ("warden_leap", icon_warden_leap),
                     ("warding_rune", icon_warding_rune), ("frost_nova", icon_frost_nova),
                     ("flame_wall", icon_flame_wall), ("ball_lightning", icon_ball_lightning),
                     ("ember_fall", icon_ember_fall), ("coin", icon_coin),
                     ("healing_draught", icon_healing_draught),
                     ("thorn_volley", icon_thorn_volley), ("mending_bloom", icon_mending_bloom),
                     ("barkskin", icon_barkskin), ("regrowth", icon_regrowth), ("root_grasp", icon_root_grasp),
                     ("renewal_grove", icon_healing_zone), ("thornfield", icon_thornfield),
                     ("growth_totem", icon_growth_totem), ("wild_bloom", icon_wild_bloom)):
        save(fn(), "icons", name + ".png")
    for name, fn in (("weapon", item_weapon), ("armor", item_armor), ("relic", item_relic),
                     ("helm", item_helm), ("gloves", item_gloves), ("boots", item_boots), ("ring", item_ring),
                     ("cindermaw", legendary_cindermaw), ("conductors_oath", legendary_conductors_oath),
                     ("glacier_heart", legendary_glacier_heart)):
        save(fn(), "items", name + ".png")
    # M17a settings widgets
    save(knob(ACCENT, ACCENT_DIM, ACCENT_HOT), "grabber.png")
    save(knob(ACCENT_HOT, ACCENT, rgb("#FFFFFF")), "grabber_hover.png")
    save(check_box(False), "check_off.png")
    save(check_box(True), "check_on.png")


if __name__ == "__main__":
    main()
