"""Blatttextur aus einem freigestellten Baumbild (ChatGPT-Bild, RGBA): Kronenmitte ausschneiden, Löcher schließen,
Beleuchtung herausrechnen (Hochpass), spiegelnd zu einer nahtlosen 1024er-Kachel legen.
Aufruf: python tools/make_leaf_texture.py <freigestellt.png> <aus.jpg>
"""
import sys

import numpy as np
from PIL import Image, ImageFilter

src, dst = sys.argv[1], sys.argv[2]
img = Image.open(src).convert("RGBA")
w, h = img.size
box = img.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox()
x0, y0, x1, y1 = box
cw, ch = x1 - x0, y1 - y0
# Kronenmitte: mittlere 46 % der Breite, oberes bis mittleres Drittel der Baumhöhe.
crop = img.crop((int(x0 + cw * 0.27), int(y0 + ch * 0.10), int(x0 + cw * 0.73), int(y0 + ch * 0.50)))
a = np.asarray(crop).astype(np.float32) / 255.0
rgb, alpha = a[..., :3], a[..., 3:]
solid = alpha[..., 0] > 0.5
mean = rgb[solid].mean(axis=0) if solid.any() else np.array([0.25, 0.4, 0.15])
# Lücken mit einem dunklen Blattgrün füllen (wirkt wie Schatten zwischen den Blättern).
rgb = np.where(solid[..., None], rgb, mean * 0.55)
tex = Image.fromarray((rgb * 255).astype(np.uint8)).resize((512, 512), Image.LANCZOS)
t = np.asarray(tex).astype(np.float32) / 255.0
# Beleuchtung herausrechnen: durch die stark geglättete Fassung teilen, mit dem Mittelwert wieder multiplizieren.
low = np.asarray(tex.filter(ImageFilter.GaussianBlur(48))).astype(np.float32) / 255.0
flat = np.clip(t / np.maximum(low, 0.02) * mean, 0.0, 1.0)
tile = Image.fromarray((flat * 255).astype(np.uint8))
sheet = Image.new("RGB", (1024, 1024))
sheet.paste(tile, (0, 0))
sheet.paste(tile.transpose(Image.FLIP_LEFT_RIGHT), (512, 0))
sheet.paste(tile.transpose(Image.FLIP_TOP_BOTTOM), (0, 512))
sheet.paste(tile.transpose(Image.ROTATE_180), (512, 512))
sheet.save(dst, quality=90)
print("BLATT", dst, [round(float(c), 2) for c in mean])
