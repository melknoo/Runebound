"""RUNEBOUND UI font: Pixelify Sans with redrawn, grid-exact numerals.

Why (user, 2026-09-24): Pixelify's digits are not on its pixel grid (they are
643 units tall on a 50-unit pixel), so at the UI's 20 px they rasterize into
look-alikes: 2 reads as 3, 5 as S. Letters are fine and stay untouched.

What it does:
  1. instances the variable Pixelify Sans at its default weight (static font),
  2. replaces 0-9 with 5x7 matrix digits whose cells are 100 x 100 units
     = 2 x 2 px at 20 px, 4 x 4 at 40, 6 x 6 at 60 (every crisp UI size),
  3. gives all ten the same advance (tabular: columns of numbers line up),
  4. renames the family (OFL: a Modified Version gets its own name).

Output: assets/fonts/RuneboundPixel.ttf (+ OFL_RuneboundPixel.txt).
Run: python tools/fontgen/numerals.py
"""
import os
import shutil

from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
FONTS = os.path.join(ROOT, "assets", "fonts")
SRC = os.path.join(FONTS, "PixelifySans.ttf")
OUT = os.path.join(FONTS, "RuneboundPixel.ttf")
FAMILY = "Runebound Pixel"
PS_NAME = "RuneboundPixel-Regular"

CELL = 100          # one matrix cell = 2 font pixels of 50 units (the 1/20 em grid)
LSB = 50            # left side bearing: one font pixel
ADVANCE = 600       # 50 + 5 cells + 50  -> 12 px at 20 px, identical for every digit

# 5 x 7 matrices, top row first. Shapes chosen so no digit shares a silhouette
# with a letter or another digit at 2 px strokes: open-top 4, flat-top 5 with
# a hard corner, a 3 with a notched middle, a 2 with a flat foot.
DIGITS = {
    "zero": [
        ".###.",
        "#...#",
        "#..##",
        "#.#.#",
        "##..#",
        "#...#",
        ".###.",
    ],
    "one": [
        "..#..",
        ".##..",
        "..#..",
        "..#..",
        "..#..",
        "..#..",
        ".###.",
    ],
    "two": [
        ".###.",
        "#...#",
        "....#",
        "...#.",
        "..#..",
        ".#...",
        "#####",
    ],
    "three": [
        "####.",
        "....#",
        "....#",
        ".###.",
        "....#",
        "....#",
        "####.",
    ],
    "four": [
        "#...#",
        "#...#",
        "#...#",
        "#####",
        "....#",
        "....#",
        "....#",
    ],
    "five": [
        "#####",
        "#....",
        "####.",
        "....#",
        "....#",
        "#...#",
        ".###.",
    ],
    "six": [
        ".###.",
        "#....",
        "#....",
        "####.",
        "#...#",
        "#...#",
        ".###.",
    ],
    "seven": [
        "#####",
        "....#",
        "...#.",
        "..#..",
        "..#..",
        "..#..",
        "..#..",
    ],
    "eight": [
        ".###.",
        "#...#",
        "#...#",
        ".###.",
        "#...#",
        "#...#",
        ".###.",
    ],
    "nine": [
        ".###.",
        "#...#",
        "#...#",
        ".####",
        "....#",
        "....#",
        ".###.",
    ],
}


def draw_matrix(rows):
    """One clockwise rectangle per horizontal run of filled cells (no overlaps)."""
    pen = TTGlyphPen(None)
    height = len(rows)
    for r, row in enumerate(rows):
        y0 = (height - 1 - r) * CELL   # bottom row sits on the baseline
        y1 = y0 + CELL
        c = 0
        while c < len(row):
            if row[c] != "#":
                c += 1
                continue
            start = c
            while c < len(row) and row[c] == "#":
                c += 1
            x0 = LSB + start * CELL
            x1 = LSB + c * CELL
            pen.moveTo((x0, y0))
            pen.lineTo((x0, y1))
            pen.lineTo((x1, y1))
            pen.lineTo((x1, y0))
            pen.closePath()
    return pen.glyph()


def rename(font):
    names = {1: FAMILY, 2: "Regular", 3: "1.000;RUNEBOUND;" + PS_NAME, 4: FAMILY + " Regular",
             6: PS_NAME, 16: FAMILY, 17: "Regular"}
    table = font["name"]
    for rec in list(table.names):
        if rec.nameID in (1, 3, 4, 6, 16, 17, 25):
            table.removeNames(nameID=rec.nameID)
    for name_id, text in names.items():
        table.setName(text, name_id, 3, 1, 0x409)
        table.setName(text, name_id, 1, 0, 0)


def main():
    font = TTFont(SRC)
    if "fvar" in font:
        font = instancer.instantiateVariableFont(font, {"wght": 400})
    glyf = font["glyf"]
    hmtx = font["hmtx"]
    for name, rows in DIGITS.items():
        assert len(rows) == 7 and all(len(r) == 5 for r in rows), name
        glyph = draw_matrix(rows)
        glyf[name] = glyph
        glyph.recalcBounds(glyf)
        hmtx[name] = (ADVANCE, glyph.xMin)
    rename(font)
    font.save(OUT)
    shutil.copyfile(os.path.join(FONTS, "OFL_PixelifySans.txt"), os.path.join(FONTS, "OFL_RuneboundPixel.txt"))
    with open(os.path.join(FONTS, "OFL_RuneboundPixel.txt"), "a", encoding="utf-8", newline="\n") as f:
        f.write("\n\n---\nRunebound Pixel is a Modified Version of Pixelify Sans (SIL OFL 1.1):\n"
                "static instance at wght 400, digits 0-9 redrawn on the pixel grid\n"
                "(tools/fontgen/numerals.py). Same license.\n")
    print("font: %s (digits redrawn: %d)" % (os.path.relpath(OUT, ROOT), len(DIGITS)))


if __name__ == "__main__":
    main()
