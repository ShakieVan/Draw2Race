"""Erzeugt die Texturen des Küstenstadions „Azure Coast Speedway“ (Thema coast, tools/dio_themes/coast.py): Werbebahn der Sicherheitsmauer,
Sitzschalen, Boxenblende, Transporter-Lackierungen, Videowand, Holzplanken der Promenade, Pflasterplatten, Beschilderung und Blumenbeet.
Alles eigene Grafik (kein Fremdmaterial); Schrift: Outfit (SIL Open Font License, game/assets/Outfit.ttf). Marken sind erfunden.
Ausgabe: game/assets/dio/coast/*.png (höchstens 1024 Bildpunkte je Seite).
Aufruf:  python tools/make_coast_stadium.py [ausgabeordner]      Benötigt numpy und Pillow.
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "game", "assets", "dio", "coast")
FONT_FILE = os.path.join(ROOT, "game", "assets", "Outfit.ttf")
os.makedirs(OUT, exist_ok=True)

AZURE, AZURE_D, NAVY = "#1b86c9", "#0e4f86", "#123a5c"
WHITE, OFFWHITE, SAND = "#f3f5f6", "#e2e5e6", "#e6d2a8"
CORAL, TEAL, GRAY = "#ef6a4c", "#16a0a3", "#a3a8ab"


def font(size, weight="Black"):
    f = ImageFont.truetype(FONT_FILE, size)
    f.set_variation_by_name(weight)
    return f


def text_fit(d, box, text, fill, weight="Black", max_size=200, align="center", pad=0.9):
    """Text so groß wie möglich in das Rechteck box = (x0, y0, x1, y1) einpassen."""
    x0, y0, x1, y1 = box
    size = max_size
    while size > 6:
        f = font(size, weight)
        l, t, r, b = d.textbbox((0, 0), text, font=f)
        if (r - l) <= (x1 - x0) * pad and (b - t) <= (y1 - y0) * pad:
            break
        size -= 2
    f = font(size, weight)
    l, t, r, b = d.textbbox((0, 0), text, font=f)
    if align == "center":
        x = x0 + ((x1 - x0) - (r - l)) / 2 - l
    elif align == "left":
        x = x0 + 8 - l
    else:
        x = x1 - 8 - (r - l) - l
    y = y0 + ((y1 - y0) - (b - t)) / 2 - t
    d.text((x, y), text, font=f, fill=fill)
    return f


def wave(d, box, color, amp, period, phase=0.0, width=3, base=None):
    """Wellenlinie über die Breite des Rechtecks; base = Höhe (Standard Mitte)."""
    x0, y0, x1, y1 = box
    base = (y0 + y1) / 2 if base is None else base
    pts = [(x, base + amp * math.sin((x - x0) / period * 2 * math.pi + phase)) for x in range(int(x0), int(x1) + 1, 2)]
    d.line(pts, fill=color, width=width)


def save(img, name):
    img.convert("RGBA").save(os.path.join(OUT, name))
    print("Textur:", name, img.size)


# ---------------------------------------------------------------- Sicherheitsmauer: Werbebahn (12 m, vier Felder zu 3 m, Höhe 0,9 m)
def make_wall():
    W, H = 1024, 80
    img = Image.new("RGB", (W, H), WHITE)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, 7], fill=AZURE)                      # azurblauer Streifen oben
    d.rectangle([0, H - 8, W, H], fill="#b9bdc0")              # Betonsockel unten
    panel_w = W // 4
    brands = [("AZURE", AZURE, WHITE, "wave"), ("SALTLINE", WHITE, NAVY, "bar"), ("DRAW2RACE", CORAL, WHITE, "check"), ("WAVETECH", NAVY, "#7fe0e0", "wave")]
    for k, (name, bg, fg, deco) in enumerate(brands):
        x0 = k * panel_w + 5
        x1 = (k + 1) * panel_w - 5
        d.rectangle([x0, 11, x1, H - 12], fill=bg, outline="#c4c8ca" if bg == WHITE else None)
        box = (x0 + 6, 13, x1 - 6, H - 14)
        if deco == "check":
            for i in range(6):
                for j in range(2):
                    if (i + j) % 2 == 0:
                        d.rectangle([x0 + 3 + i * 6, 13 + j * 6, x0 + 9 + i * 6, 19 + j * 6], fill="#ffffff")
            box = (x0 + 44, 13, x1 - 6, H - 14)
        elif deco == "wave":
            wave(d, (x0 + 4, 13, x1 - 4, H - 14), fg, 3, 40, width=2, base=H - 18)
        elif deco == "bar":
            d.rectangle([x0 + 4, H - 20, x1 - 4, H - 15], fill=CORAL)
            box = (x0 + 6, 13, x1 - 6, H - 22)
        text_fit(d, box, name, fg, max_size=60)
    # Betonfugen zwischen den Feldern
    for k in range(5):
        x = k * panel_w
        d.line([(x, 8), (x, H - 9)], fill="#aeb2b5", width=2)
    arr = np.asarray(img).astype(np.float32)
    rng = np.random.default_rng(3)
    arr += rng.normal(0, 2.2, arr.shape[:2])[..., None]                       # feine Körnung des Betons
    save(Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)), "mauer.png")


# ---------------------------------------------------------------- Sitzschalen (Draufsicht): Kachel 0,5 m (u) x 0,8 m (v, oben = Rückseite)
def make_seat(name, color):
    W, H = 128, 208
    img = Image.new("RGB", (W, H), "#8d9497")
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(len(name))
    d.rectangle([0, H - 6, W, H], fill="#7c8386")                               # Stufenkante vorne
    # Sitzfläche (vorn) und Lehne (hinten), gerundet
    edge = tuple(int(int(color.lstrip("#")[i:i + 2], 16) * 0.62) for i in (0, 2, 4))
    d.rounded_rectangle([14, 92, W - 14, 168], radius=14, fill=color, outline=edge, width=2)
    d.rounded_rectangle([18, 28, W - 18, 78], radius=14, fill=color, outline=edge, width=2)
    hi = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hi)
    hd.rounded_rectangle([24, 36, W - 24, 46], radius=5, fill=(255, 255, 255, 70))
    hd.rounded_rectangle([22, 100, W - 22, 112], radius=5, fill=(255, 255, 255, 60))
    img = Image.alpha_composite(img.convert("RGBA"), hi).convert("RGB")
    save(img, name)


# ---------------------------------------------------------------- Boxenblende (Schriftfeld, 10 m x 0,55 m)
def make_fascia():
    W, H = 1024, 64
    img = Image.new("RGB", (W, H), AZURE)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, 4], fill=WHITE)
    d.rectangle([0, H - 5, W, H], fill=WHITE)
    for i in range(0, 56, 8):                                                   # Zielflagge links und rechts
        for j in range(0, 48, 12):
            if ((i // 8) + (j // 12)) % 2 == 0:
                d.rectangle([14 + i, 8 + j, 14 + i + 7, 8 + j + 11], fill="#ffffff")
                d.rectangle([W - 70 + i, 8 + j, W - 70 + i + 7, 8 + j + 11], fill="#ffffff")
    text_fit(d, (84, 5, W - 84, H - 6), "AZURE COAST SPEEDWAY  /  PIT CENTER", WHITE, max_size=48, pad=0.95)
    save(img, "fascia.png")


# ---------------------------------------------------------------- Transporter-Lackierungen (Auflieger-Seite 8,4 m x 2,8 m)
def make_livery(name, base, band, accent, title, sub, text_col):
    W, H = 1024, 344
    img = Image.new("RGB", (W, H), base)
    d = ImageDraw.Draw(img, "RGBA")
    # große Welle im unteren Drittel
    for layer, (col, off, amp) in enumerate(((accent, 0, 26), (band, 22, 30))):
        pts = [(0, H)]
        for x in range(0, W + 1, 4):
            pts.append((x, H * 0.66 + off + amp * math.sin(x / W * 2 * math.pi * 1.5 + layer * 0.8) + 0.12 * x * (0.7 if layer else 0.5) * 0.0))
        pts.append((W, H))
        d.polygon(pts, fill=col)
    d.rectangle([0, H - 14, W, H], fill=NAVY if base != NAVY else AZURE)
    text_fit(d, (30, 28, W - 30, 150), title, text_col, max_size=130, align="left", pad=0.96)
    text_fit(d, (36, 150, W - 36, 205), sub, text_col, weight="Bold", max_size=44, align="left", pad=0.96)
    # kleine „Sponsorfelder“ am unteren Rand
    x = 60
    for label, bg, fg in (("SALTLINE", WHITE, NAVY), ("WAVETECH", NAVY, WHITE), ("DRAW2RACE", CORAL, WHITE)):
        d.rounded_rectangle([x, 262, x + 190, 306], radius=8, fill=bg)
        text_fit(d, (x + 6, 266, x + 184, 302), label, fg, max_size=34)
        x += 215
    # Startnummer
    d.ellipse([W - 180, 190, W - 60, 310], fill=WHITE)
    text_fit(d, (W - 172, 202, W - 68, 298), "07", NAVY, max_size=90)
    save(img, name)


# ---------------------------------------------------------------- Videowand (16:9): Leuchtbild (screen_e.png) und Tagbild (screen.png, gedimmt)
def make_screen():
    """Zwei Dateien: screen_e.png = Bild der LED-Wand (Emission, das Spiel schaltet es mit dem Fensterlicht), screen.png = dieselbe Grafik als Albedo
    (die Bildfläche trägt eine dunkle Vertexfarbe: tagsüber ein dunkles, nur schwach erkennbares Bild wie eine LED-Wand im Sonnenlicht, nachts
    überstrahlt das Laternenlicht des Spiels das Leuchtbild nicht). Große Schrift, damit sie aus der Rennkamera lesbar bleibt."""
    W, H = 1024, 576
    arr = np.zeros((H, W, 3), np.float32)
    yy = np.linspace(0, 1, H)[:, None]
    arr[..., 0] = 8 + 14 * yy
    arr[..., 1] = 34 + 40 * yy
    arr[..., 2] = 62 + 60 * yy
    img = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, 92], fill="#0d3b66")
    d.rectangle([0, 92, W, 98], fill=AZURE)
    text_fit(d, (28, 8, 700, 84), "AZURE COAST SPEEDWAY", WHITE, max_size=70, align="left", pad=0.96)
    d.ellipse([W - 232, 30, W - 190, 72], fill="#ff3b30")
    text_fit(d, (W - 178, 12, W - 24, 80), "LIVE", WHITE, weight="Bold", max_size=62, align="left", pad=0.96)
    rows = [("1", "AZURE", "23.84"), ("2", "SALTLINE", "+0.41"), ("3", "WAVETECH", "+0.97"), ("4", "DRAW2RACE", "+1.62")]
    cols = [AZURE, WHITE, TEAL, CORAL]
    for i, (p, n, t) in enumerate(rows):
        y = 116 + i * 94
        d.rectangle([20, y, W - 20, y + 84], fill="#124a78" if i % 2 == 0 else "#0e3a60")
        d.rectangle([20, y, 40, y + 84], fill=cols[i])
        text_fit(d, (58, y + 6, 130, y + 78), p, WHITE, max_size=84, align="left", pad=0.96)
        text_fit(d, (150, y + 8, 620, y + 76), n, WHITE, weight="Bold", max_size=72, align="left", pad=0.96)
        text_fit(d, (640, y + 8, W - 36, y + 76), t, "#8cf0f0", weight="Bold", max_size=72, align="right", pad=0.96)
    d.rectangle([0, 500, W, H], fill="#0a2a48")
    d.rectangle([0, 494, W, 500], fill=CORAL)
    text_fit(d, (28, 508, 420, 570), "LAP 1 / 2", WHITE, max_size=64, align="left", pad=0.96)
    wave(d, (440, 508, W - 20, 570), "#2aa7d8", 8, 120, width=5, base=540)
    text_fit(d, (560, 512, W - 28, 566), "SALTLINE  |  WAVETECH", "#a9d9ee", weight="Bold", max_size=40, align="right", pad=0.96)
    lit = np.clip(np.asarray(img).astype(np.float32) * 2.0 + 18.0, 0, 255)       # Leuchtbild kräftiger als das Albedo (Emission x Stärke des Fensterlichts < 1)
    Image.fromarray(lit.astype(np.uint8)).convert("RGBA").save(os.path.join(OUT, "screen_e.png"))
    day = np.asarray(img).astype(np.float32)                         # Tag: volles Bild; die dunkle Vertexfarbe der Bildfläche (SCREEN_V) macht daraus eine dunkle, schwach lesbare Wand
    Image.fromarray(np.clip(day, 0, 255).astype(np.uint8)).convert("RGBA").save(os.path.join(OUT, "screen.png"))
    print("Textur: screen.png / screen_e.png", img.size)


# ---------------------------------------------------------------- Promenade: Holzplanken (Kachel 2 m x 2 m, Planken längs u)
def make_planks():
    N = 512
    rng = np.random.default_rng(11)
    img = np.zeros((N, N, 3), np.float32)
    n_planks = 8
    ph = N // n_planks
    for r in range(n_planks):
        y0 = r * ph
        x = 0
        shift = int(rng.integers(0, N))
        # Planken in Längsrichtung, Stöße versetzt
        cuts = sorted({0, N} | {int((shift + k * 256) % N) for k in range(2)})
        for a, b in zip(cuts, cuts[1:]):
            base = np.array([186, 152, 108], np.float32) * (0.88 + 0.22 * rng.random())
            base += rng.normal(0, 3, 3)
            seg = np.tile(base, (ph, b - a, 1))
            grain = rng.normal(0, 1, (ph, 1)) * 4 + rng.normal(0, 2.0, (ph, b - a))
            grain = np.cumsum(grain, axis=1) * 0.02 + grain * 0.35
            seg += grain[..., None]
            img[y0:y0 + ph, a:b] = seg
            img[y0:y0 + ph, a:min(N, a + 3)] *= 0.55                          # Stoßfuge
        img[y0:y0 + 3] *= 0.5                                                 # Fuge zwischen den Planken
    img = np.clip(img, 0, 255)
    save(Image.fromarray(img.astype(np.uint8)), "planken.png")


# ---------------------------------------------------------------- Plätze: helle Sandplatten (Kachel 4 m, Platten 1 m)
def make_tiles():
    N = 512
    rng = np.random.default_rng(23)
    img = np.zeros((N, N, 3), np.float32)
    cell = N // 4
    for i in range(4):
        for j in range(4):
            base = np.array([226, 214, 188], np.float32) * (0.93 + 0.1 * rng.random())
            base += rng.normal(0, 2.5, 3)
            blk = np.tile(base, (cell, cell, 1))
            blk += rng.normal(0, 3.2, (cell, cell, 1))
            img[j * cell:(j + 1) * cell, i * cell:(i + 1) * cell] = blk
    for k in range(5):
        p = (k * cell) % N
        img[p:p + 3, :] = img[p:p + 3, :] * 0.0 + np.array([178, 168, 148])
        img[:, p:p + 3] = img[:, p:p + 3] * 0.0 + np.array([178, 168, 148])
    save(Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)), "platten.png")


# ---------------------------------------------------------------- Beschilderung (Atlas 1024 x 512)
SIGNS = [
    # Name, x0, y0, x1, y1, Text, Hintergrund, Schrift
    ("haupt", 0, 0, 1024, 128, "AZURE COAST SPEEDWAY", AZURE, WHITE),
    ("tribuene_a", 0, 128, 512, 256, "MAIN GRANDSTAND", NAVY, WHITE),
    ("tribuene_w", 512, 128, 1024, 256, "WEST STAND", AZURE_D, WHITE),
    ("tribuene_o", 0, 256, 512, 384, "EAST STAND", AZURE_D, WHITE),
    ("tribuene_s", 512, 256, 1024, 384, "SEA STAND", TEAL, WHITE),
    ("fahrerlager", 0, 384, 512, 512, "PADDOCK", CORAL, WHITE),
    ("willkommen", 512, 384, 1024, 512, "WELCOME TO THE COAST", SAND, NAVY),
]


def make_signs():
    img = Image.new("RGB", (1024, 512), "#ffffff")
    d = ImageDraw.Draw(img)
    for name, x0, y0, x1, y1, text, bg, fg in SIGNS:
        d.rectangle([x0, y0, x1 - 1, y1 - 1], fill=bg)
        d.rectangle([x0 + 4, y0 + 4, x1 - 5, y0 + 9], fill=WHITE if bg != SAND else NAVY)
        d.rectangle([x0 + 4, y1 - 10, x1 - 5, y1 - 5], fill=CORAL if bg != CORAL else WHITE)
        text_fit(d, (x0 + 20, y0 + 14, x1 - 20, y1 - 16), text, fg, max_size=110)
    save(img, "schilder.png")
    with open(os.path.join(OUT, "schilder.txt"), "w", encoding="utf-8") as fh:
        for name, x0, y0, x1, y1, *_ in SIGNS:
            fh.write(f"{name} {x0} {y0} {x1} {y1}\n")


# ---------------------------------------------------------------- Blumenbeet (Draufsicht, Kachel 2 m)
def make_flowers():
    N = 256
    rng = random.Random(5)
    img = Image.new("RGB", (N, N), "#2f5f2a")
    d = ImageDraw.Draw(img)
    for _ in range(420):                                                        # Laub
        x, y = rng.randrange(N), rng.randrange(N)
        r = rng.randrange(5, 12)
        g = rng.randrange(80, 150)
        for dx in (-N, 0, N):
            for dy in (-N, 0, N):
                d.ellipse([x - r + dx, y - r + dy, x + r + dx, y + r + dy], fill=(30 + rng.randrange(25), g, 36 + rng.randrange(20)))
    cols = ["#f0674b", "#ffffff", "#f7c948", "#e5457a", "#ff9a5c"]
    for _ in range(300):                                                        # Blüten
        x, y = rng.randrange(N), rng.randrange(N)
        r = rng.randrange(3, 7)
        c = rng.choice(cols)
        for dx in (-N, 0, N):
            for dy in (-N, 0, N):
                d.ellipse([x - r + dx, y - r + dy, x + r + dx, y + r + dy], fill=c)
                d.ellipse([x - 1 + dx, y - 1 + dy, x + 1 + dx, y + 1 + dy], fill="#f7e27a")
    save(img.filter(ImageFilter.SMOOTH), "blumen.png")


make_wall()
make_seat("sitz_az.png", AZURE)
make_seat("sitz_wh.png", "#eef1f2")
make_seat("sitz_co.png", CORAL)
make_seat("sitz_na.png", "#1d4f82")
make_seat("sitz_te.png", TEAL)
make_fascia()
make_livery("lkw_azure.png", "#f4f6f7", AZURE, TEAL, "AZURE RACING", "TEAM TRANSPORTER  /  COAST SERIES", NAVY)
make_livery("lkw_coral.png", CORAL, "#ffffff", "#f7b5a5", "SALTLINE", "MOTORSPORT  /  WE RACE THE TIDE", "#ffffff")
make_livery("lkw_navy.png", NAVY, AZURE, TEAL, "WAVETECH", "FACTORY TEAM  /  AZURE COAST", "#ffffff")
make_screen()
make_planks()
make_tiles()
make_signs()
make_flowers()
with open(os.path.join(OUT, "HERKUNFT.md"), "w", encoding="utf-8") as fh:
    fh.write("""# Texturen des Küstenstadions (Thema coast)

Alle Dateien in diesem Ordner sind eigene, prozedural erzeugte Grafik (`tools/make_coast_stadium.py`), kein Fremdmaterial.
Schrift: Outfit (SIL Open Font License, `game/assets/Outfit.ttf`). Die Marken (AZURE, SALTLINE, WAVETECH, DRAW2RACE) sind erfunden.

| Datei | Verwendung |
|---|---|
| `mauer.png` | Werbebahn der Sicherheitsmauer (12 m, vier Felder) |
| `sitz_*.png` | Sitzschalen der Tribünen (Draufsicht, 0,5 m x 0,8 m) |
| `fascia.png` | Blende des Boxengebäudes |
| `lkw_*.png` | Lackierung der Team-Transporter |
| `screen.png`, `screen_e.png` | Bild der Videowand (Albedo, am Tag dunkel durch die Vertexfarbe) und Leuchtbild (Emission, vom Fensterlicht des Spiels geschaltet: nur Dämmerung und Nacht) |
| `planken.png`, `platten.png` | Promenade (Holz), Plätze (Sandplatten) |
| `schilder.png` (+ `schilder.txt`) | Beschilderung (Atlas) |
| `blumen.png` | Blumenbeete |

Die Bodentexturen Gras, Sand und Erde (Mischung im Boden-Shader) liegen in `game/assets/ground/`; der Beton der Tribünen und die Fahrbahn
stammen aus `art/texturen` (ambientCG, CC0).
""")
print("fertig:", OUT)
