"""Writes captures_shots/REVIEW.html: every M06/M07 review capture on one local
page, before/after (legacy look) pairs side by side, contact sheets at the end.
Run after the shot lists:  python tools/make_review_page.py
"""
import html
import os

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
SHOTS = os.path.join(ROOT, "captures_shots")
CONTACT = os.path.join(ROOT, "captures_contact")

SECTIONS = [
    ("vignette", "Gold target - Ashen Highlands South"),
    ("c3_runehold", "Runehold hub (C3)"),
    ("c3_lab", "Training grounds / Combat Lab (C3)"),
    ("c4_spire", "Shattered Spire (C4)"),
    ("c12_rigs", "Enemy cast + bosses (C1/C2/C4)"),
    ("c5_props", "Portals, chest, loot, elites (C5)"),
    ("b2_clips", "Hero + Marauder + Duskweaver clips (B2)"),
    ("b4_vfx", "VFX v2 (B4)"),
    ("b5_hud", "HUD v2 (B5)"),
    ("m07_progression", "M07 progression: XP, talents, abilities 7-8"),
]


def pngs(folder):
    if not os.path.isdir(folder):
        return []
    return sorted(f for f in os.listdir(folder) if f.endswith(".png"))


def main():
    parts = ["<!doctype html><meta charset='utf-8'><title>RUNEBOUND review</title>",
             "<style>body{background:#15121c;color:#e6e1d6;font:14px sans-serif;margin:24px}"
             "h2{color:#3cbeb4;margin-top:40px}figure{display:inline-block;margin:6px;vertical-align:top}"
             "img{width:640px;image-rendering:pixelated;border:1px solid #333}"
             "figcaption{color:#a9a2b4;font-size:12px}.pair{white-space:nowrap}"
             "img.sheet{width:auto;max-width:980px}</style>",
             "<h1>RUNEBOUND - M06 / M07 review captures</h1>",
             "<p>Left: new look. Right: the same framing with the pre-M06 look (legacy), where one exists. "
             "Style Gate checklist: docs/ART_BIBLE.md section 16, gate self-review section 17.</p>"]
    for key, title in SECTIONS:
        files = pngs(os.path.join(SHOTS, key))
        if not files:
            continue
        legacy = set(pngs(os.path.join(SHOTS, key + "_legacy")))
        parts.append("<h2>%s</h2>" % html.escape(title))
        for f in files:
            parts.append("<div class='pair'>")
            parts.append("<figure><img src='%s/%s'><figcaption>%s</figcaption></figure>" % (key, f, html.escape(f)))
            if f in legacy:
                parts.append("<figure><img src='%s_legacy/%s'><figcaption>legacy</figcaption></figure>" % (key, f))
            parts.append("</div>")
    if os.path.isdir(CONTACT):
        parts.append("<h2>Clip contact sheets (3/4, side, top per key frame)</h2>")
        for char in sorted(os.listdir(CONTACT)):
            for f in pngs(os.path.join(CONTACT, char)):
                parts.append("<figure><img class='sheet' src='../captures_contact/%s/%s'>"
                             "<figcaption>%s / %s</figcaption></figure>" % (char, f, html.escape(char), html.escape(f)))
    out = os.path.join(SHOTS, "REVIEW.html")
    with open(out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(parts))
    print("wrote", out)


if __name__ == "__main__":
    main()
