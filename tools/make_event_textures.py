"""Erzeugt die Texturen der Rennausstattung (eigene Grafik, kein fremdes Material): Zuschauer in Draufsicht, Werbebanner,
Startportal-Schriftzug und Schachbrett. Sie liegen in game/assets/event/ und werden in world.gd (event_material) den
Platzhalter-Materialien E_* des Dioramas zugewiesen (tools/diorama.py, Abschnitt Rennausstattung).

Schrift: Outfit (SIL Open Font License, game/assets/Outfit.ttf).
Aufruf:  python tools/make_event_textures.py [ausgabeordner]
Benötigt numpy und Pillow.
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "game", "assets", "event")
FONT_FILE = os.path.join(ROOT, "game", "assets", "Outfit.ttf")
os.makedirs(OUT, exist_ok=True)


def font(size, weight="Black"):
    f = ImageFont.truetype(FONT_FILE, size)
    f.set_variation_by_name(weight)
    return f


# ---------------------------------------------------------------- Zuschauer (Draufsicht)
PPM = 256                      # Bildpunkte je Meter
TILE_M, STRIP_M = 6.0, 1.25    # Kachel: 6 m lang (kachelt entlang des Streifens), 1,25 m breit (zwei Reihen)
JACKETS = ["#d62828", "#1d4ed8", "#f5c518", "#f2f2f2", "#1b1b1f", "#2f9e44", "#f77f00", "#7b2cbf", "#0ea5a5", "#e85d9e",
           "#6b7280", "#c8b08a", "#8f1d1d", "#14532d", "#3b82f6"]
HAIR = ["#15120f", "#2b1d12", "#4a2f1a", "#c9a24a", "#9a9a9a", "#7a2e12", "#0d0d0d", "#3a2a1c"]
SKIN = ["#f1c7a0", "#e0a97e", "#b97a4f", "#8a5a3a", "#f6d6b8"]


def person(d, cx, cy, rot, rng, scale=1.0):
    """Eine Person in Draufsicht auf einer eigenen Ebene (RGBA) zeichnen und an (cx, cy) einfügen."""
    jacket = rng.choice(JACKETS)
    hair = rng.choice(HAIR)
    skin = rng.choice(SKIN)
    w, h = int(0.46 * PPM * scale), int(0.27 * PPM * scale)
    size = int(0.9 * PPM)
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    c = size // 2
    # Arme (an den Schulterenden), Schultern (Jacke), etwas dunklerer Rand für Tiefe
    arm_w, arm_h = int(0.13 * PPM * scale), int(0.22 * PPM * scale)
    for sx in (-1, 1):
        ld.ellipse([c + sx * w // 2 - arm_w // 2, c - arm_h // 2 - 4, c + sx * w // 2 + arm_w // 2, c + arm_h // 2 - 4], fill=jacket)
    ld.ellipse([c - w // 2, c - h // 2, c + w // 2, c + h // 2], fill=jacket, outline=(0, 0, 0, 90), width=3)
    # Hände (Hautfarbe) an den Armenden
    for sx in (-1, 1):
        ld.ellipse([c + sx * w // 2 - 7, c + arm_h // 2 - 12, c + sx * w // 2 + 7, c + arm_h // 2 + 2], fill=skin)
    # Kopf: Haar oben, Gesichtsstreifen zur Straße (nach unten)
    r = int(0.090 * PPM * scale)
    ld.ellipse([c - r, c - r - 6, c + r, c + r - 6], fill=hair)
    if rng.random() < 0.45:                      # Gesicht oben (die Menge schaut zur Straße)
        ld.ellipse([c - r + 7, c - r - 4, c + r - 7, c - r + 13], fill=skin)
    if rng.random() < 0.18:                      # Mütze
        cap = rng.choice(JACKETS)
        ld.ellipse([c - r - 1, c - r - 7, c + r + 1, c + r - 5], fill=cap)
    layer = layer.rotate(math.degrees(rot), resample=Image.BICUBIC)
    d.alpha_composite(layer, (int(cx - size / 2), int(cy - size / 2)))


def crowd():
    rng = random.Random(21)
    W, H = int(TILE_M * PPM), int(STRIP_M * PPM)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    people = []
    for row, (cy, n) in enumerate(((0.30, 11), (0.83, 10))):
        for k in range(n):
            x = (k + 0.5 + rng.uniform(-0.18, 0.18)) / n * W + (0.0 if row == 0 else 0.5 / n * W)
            y = (cy + rng.uniform(-0.05, 0.05)) * PPM
            people.append((x, y, rng.uniform(-0.45, 0.45), rng.uniform(0.92, 1.08)))
    for x, y, rot, sc in people:                  # weiche Schatten (mit Umbruch an den Kachelrändern)
        for dx in (-W, 0, W):
            sd.ellipse([x + dx - 0.29 * PPM + 14, y - 0.2 * PPM + 12, x + dx + 0.29 * PPM + 14, y + 0.2 * PPM + 12], fill=(0, 0, 0, 120))
    shadow = shadow.filter(ImageFilter.GaussianBlur(7))
    img.alpha_composite(shadow)
    for x, y, rot, sc in sorted(people, key=lambda p: p[1]):     # hintere Reihe zuerst
        for dx in (-W, 0, W):
            person(img, x + dx, y, rot, rng, sc)
    img.save(os.path.join(OUT, "menge.png"))


# ---------------------------------------------------------------- Werbebanner
CELL_W, CELL_H = 1024, 256
BANNERS = [
    ("DRAW2RACE", "#d62828", "#ffffff", "check"),
    ("TURBO", "#f5c518", "#15120f", "hazard"),
    ("NIGHT RUN", "#0f1f4a", "#ffffff", "neon"),
    ("CITY GRAND PRIX", "#14532d", "#ffffff", "gold"),
    ("NITRO", "#111114", "#f5c518", "flame"),
    ("FULL THROTTLE", "#f77f00", "#ffffff", "plain"),
    ("PIT STOP", "#f2f2f2", "#15120f", "red"),
    ("RACE WEEK", "#0ea5a5", "#ffffff", "plain"),
]


def fit_text(d, text, box_w, box_h, weight="Black", pad=0.86):
    size = int(box_h)
    while size > 10:
        f = font(size, weight)
        bb = d.textbbox((0, 0), text, font=f)
        if bb[2] - bb[0] <= box_w * pad and bb[3] - bb[1] <= box_h * pad:
            return f, bb
        size -= 4
    return font(10, weight), d.textbbox((0, 0), text, font=font(10, weight))


def checker_band(d, x0, y0, x1, y1, sq):
    for yy in range(math.ceil((y1 - y0) / sq)):
        for xx in range(math.ceil((x1 - x0) / sq)):
            col = "#ffffff" if (xx + yy) % 2 == 0 else "#111114"
            d.rectangle([x0 + xx * sq, y0 + yy * sq, min(x1, x0 + (xx + 1) * sq) - 1, min(y1, y0 + (yy + 1) * sq) - 1], fill=col)


def banner_cell(text, bg, fg, style, w=CELL_W, h=CELL_H):
    img = Image.new("RGB", (w, h), bg)
    d = ImageDraw.Draw(img)
    inner = [0, 0, w, h]
    if style == "check":
        checker_band(d, 0, 0, 56, h, 28)
        checker_band(d, w - 56, 0, w, h, 28)
        inner = [70, 0, w - 70, h]
    elif style == "hazard":
        for k in range(-6, 30):
            d.polygon([(k * 50, h), (k * 50 + 25, h), (k * 50 + 25 + 28, h - 28), (k * 50 + 28, h - 28)], fill="#15120f")
            d.polygon([(k * 50, 0), (k * 50 + 25, 0), (k * 50 + 25 + 28, 28), (k * 50 + 28, 28)], fill="#15120f")
        inner = [0, 30, w, h - 30]
    elif style == "neon":
        d.rectangle([10, 10, w - 11, h - 11], outline="#3ad6ff", width=6)
        inner = [24, 14, w - 24, h - 14]
    elif style == "gold":
        d.rectangle([0, 0, w, 16], fill="#e0b84a")
        d.rectangle([0, h - 16, w, h], fill="#e0b84a")
        inner = [0, 16, w, h - 16]
    elif style == "flame":
        for k in range(0, 16):
            x = k * 70 + 20
            d.polygon([(x, h), (x + 30, h - 70 - 20 * (k % 3)), (x + 60, h)], fill="#f77f00")
            d.polygon([(x + 14, h), (x + 30, h - 40 - 10 * (k % 3)), (x + 46, h)], fill="#f5c518")
        inner = [0, 0, w, h - 50]
    elif style == "red":
        d.rectangle([0, 0, w, 22], fill="#d62828")
        d.rectangle([0, h - 22, w, h], fill="#d62828")
        inner = [0, 22, w, h - 22]
    bw, bh = inner[2] - inner[0], inner[3] - inner[1]
    f, bb = fit_text(d, text, bw, bh)
    tx = inner[0] + (bw - (bb[2] - bb[0])) / 2 - bb[0]
    ty = inner[1] + (bh - (bb[3] - bb[1])) / 2 - bb[1]
    if style == "neon":
        glow = Image.new("RGB", (w, h), (0, 0, 0))
        ImageDraw.Draw(glow).text((tx, ty), text, font=f, fill="#3ad6ff")
        glow = glow.filter(ImageFilter.GaussianBlur(9))
        img = Image.fromarray(np.clip(np.asarray(img, np.float32) + np.asarray(glow, np.float32) * 0.9, 0, 255).astype(np.uint8))
        d = ImageDraw.Draw(img)
    d.text((tx, ty), text, font=f, fill=fg)
    return img


def banners():
    cols, rows = 2, 4
    atlas = Image.new("RGB", (CELL_W * cols, CELL_H * rows))
    for i, (text, bg, fg, style) in enumerate(BANNERS):
        atlas.paste(banner_cell(text, bg, fg, style), ((i % cols) * CELL_W, (i // cols) * CELL_H))
    atlas.save(os.path.join(OUT, "banner.png"))


# ---------------------------------------------------------------- Startportal und Schachbrett
def portal():
    w, h = 2048, 200
    img = Image.new("RGB", (w, h), "#101015")
    d = ImageDraw.Draw(img)
    checker_band(d, 0, 0, 200, h, 50)
    checker_band(d, w - 200, 0, w, h, 50)
    d.rectangle([200, 0, w - 201, 10], fill="#f5c518")
    d.rectangle([200, h - 11, w - 201, h], fill="#f5c518")
    text = "START  /  ZIEL"
    f, bb = fit_text(d, text, w - 440, h - 40)
    d.text((200 + (w - 400 - (bb[2] - bb[0])) / 2 - bb[0], (h - (bb[3] - bb[1])) / 2 - bb[1]), text, font=f, fill="#ffffff")
    img.save(os.path.join(OUT, "portal.png"))


def checker():
    img = Image.new("RGB", (128, 128), "#ffffff")
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 63, 63], fill="#111114")
    d.rectangle([64, 64, 127, 127], fill="#111114")
    img.save(os.path.join(OUT, "schach.png"))


crowd()
banners()
portal()
checker()
print("Rennausstattung: Texturen in", OUT)
