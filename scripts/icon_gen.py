#!/usr/bin/env python3
"""Regenerate assets/icon_1024.png: a dark orange F on a near-black plate."""
from PIL import Image, ImageDraw, ImageFont
import pathlib, sys

S, SS = 1024, 4
W = S * SS
ORANGE = (210, 105, 30, 255)
BG_TOP, BG_BOT = (24, 24, 27), (9, 9, 11)

img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
margin = W * 0.085
corner = (W - margin * 2) * 0.225

plate = Image.new("RGBA", (W, W), (0, 0, 0, 0))
pd = ImageDraw.Draw(plate)
for y in range(int(margin), int(W - margin)):
    t = (y - margin) / (W - 2 * margin)
    pd.line([(0, y), (W, y)],
            fill=tuple(int(BG_TOP[i] + (BG_BOT[i] - BG_TOP[i]) * t) for i in range(3)) + (255,))
mask = Image.new("L", (W, W), 0)
ImageDraw.Draw(mask).rounded_rectangle([margin, margin, W - margin, W - margin],
                                       radius=corner, fill=255)
img.paste(plate, (0, 0), mask)

d = ImageDraw.Draw(img)

# The F is drawn from rectangles rather than set in a typeface, so the icon
# does not depend on a font being installed on the build machine.
stem_w = W * 0.115
arm_h = W * 0.105
top = W * 0.255
bottom = W * 0.745
left = W * 0.325
arm_top_w = W * 0.310
arm_mid_w = W * 0.235
r = stem_w * 0.28

d.rounded_rectangle([left, top, left + stem_w, bottom], radius=r, fill=ORANGE)
d.rounded_rectangle([left, top, left + arm_top_w, top + arm_h], radius=r, fill=ORANGE)
mid = (top + bottom) / 2 - arm_h * 0.65
d.rounded_rectangle([left, mid, left + arm_mid_w, mid + arm_h], radius=r, fill=ORANGE)

out = pathlib.Path(__file__).resolve().parent.parent / "assets" / "icon_1024.png"
out.parent.mkdir(exist_ok=True)
img.resize((S, S), Image.LANCZOS).save(out)
print("wrote", out)
