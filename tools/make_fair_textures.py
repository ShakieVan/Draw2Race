"""Erzeugt die Texturen des Themas "fair" (Fun Fair Eight) nach game/assets/dio/fair/ (prozedural bzw. aus ambientCG CC0).

  gras_getreten(.jpg/_n.jpg)   Rasen, an vielen Stellen abgetreten (Grundlage: ambientCG Grass005, CC0)
  saegespaene(.jpg/_n.jpg)     Sägemehl und Hackschnitzel (eigene prozedurale Textur)
  erde_platt(.jpg/_n.jpg)      festgetretene Erde mit Kies und Strohresten (eigene prozedurale Textur)
  planken(.jpg/_n.jpg)         wetterfeste Holzbretter, waagerecht, neutral (Farbton kommt aus der Vertexfarbe)
  schilder.jpg                 Schildertafel (Atlas, 4 x 4 Schilder zu 256 x 128): Beschriftung mit Barlow Condensed (OFL)
Aufruf: python tools/make_fair_textures.py   (E:/Draw2Race-AudioLab/analyse/.venv/Scripts/python.exe: numpy, scipy, Pillow)
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "assets", "dio", "fair")
os.makedirs(OUT, exist_ok=True)
N = 1024


def pnoise(scale_px, seed, n=N):
    """Nahtloses Rauschen (Frequenzraum), Mittelwert 0, Streuung 1."""
    r = np.random.default_rng(seed)
    f = np.fft.fft2(r.standard_normal((n, n)))
    ky = np.fft.fftfreq(n)[:, None]
    kx = np.fft.fftfreq(n)[None, :]
    k = np.sqrt(kx ** 2 + ky ** 2) * scale_px
    x = np.real(np.fft.ifft2(f * np.exp(-k ** 2)))
    return (x - x.mean()) / (x.std() + 1e-9)


def normal_from_height(h, strength):
    h = ndi.gaussian_filter(h, 0.6, mode="wrap")
    gy, gx = np.gradient(h)
    nx, ny, nz = -gx * strength, gy * strength, np.ones_like(h)
    nn = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
    return np.stack([nx / nn, ny / nn, nz / nn], -1) * 0.5 + 0.5


def save_pair(name, col, normal, quality=92):
    Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, name + ".jpg"), quality=quality)
    Image.fromarray((np.clip(normal, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, name + "_n.jpg"), quality=quality)


def stamp(layer, mask_fn, cx, cy, wrap=True):
    pass


def wrap_idx(a, n=N):
    return np.arange(a[0], a[1]) % n


# ---------------------------------------------------------------- Rasen, abgetreten
def make_grass():
    src = Image.open(os.path.join(ROOT, "art", "texturen", "Grass005", "Grass005_1K-JPG_Color.jpg")).convert("RGB")
    g = np.asarray(src, np.float32) / 255.0
    lum = g @ np.array([0.3, 0.59, 0.11], np.float32)
    # Grün leicht zum Gelb-Olivton ziehen (Sommerrasen)
    g = g * np.array([1.0, 0.93, 0.70], np.float32)
    worn = pnoise(70, 21) * 0.8 + pnoise(22, 22) * 0.45 + pnoise(7, 23) * 0.2
    m = smooth(worn, 0.35, 1.05)                                        # abgetretene Stellen
    dry = np.array([0.50, 0.43, 0.24], np.float32)
    fine = 0.82 + 0.3 * pnoise(1.6, 24)[..., None]
    dry_col = dry[None, None, :] * fine * (lum[..., None] / lum.mean()) ** 0.7
    straw = smooth(pnoise(11, 25), 0.9, 1.7)[..., None]                  # einzelne Strohbüschel
    dry_col = dry_col * (1 - straw * 0.5) + np.array([0.70, 0.60, 0.34], np.float32) * straw * 0.5
    col = g * (1 - m[..., None] * 0.78) + dry_col * (m[..., None] * 0.78)
    nrm = np.asarray(Image.open(os.path.join(ROOT, "art", "texturen", "Grass005", "Grass005_1K-JPG_NormalGL.jpg")).convert("RGB"), np.float32) / 255.0
    flat = np.array([0.5, 0.5, 1.0], np.float32)
    nrm = nrm * (1 - m[..., None] * 0.55) + flat * (m[..., None] * 0.55)
    save_pair("gras_getreten", col, nrm)


def smooth(x, e0, e1):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- Sägemehl und Hackschnitzel
def draw_chips(col, height, rng, count, length, width, palette, seed_shadow=True):
    n = N
    img = Image.fromarray((col * 255).astype(np.uint8))
    hmap = Image.fromarray((height * 255).astype(np.uint8))
    dr = ImageDraw.Draw(img)
    dh = ImageDraw.Draw(hmap)
    for _ in range(count):
        cx, cy = rng.uniform(0, n), rng.uniform(0, n)
        ang = rng.uniform(0, np.pi)
        L = rng.uniform(*length)
        W = rng.uniform(*width)
        c = tuple(int(v * 255) for v in palette[rng.integers(len(palette))] * rng.uniform(0.85, 1.12))
        dx, dy = np.cos(ang) * L / 2, np.sin(ang) * L / 2
        px, py = -np.sin(ang) * W / 2, np.cos(ang) * W / 2
        for ox in (-n, 0, n):
            for oy in (-n, 0, n):
                if -L < cx + ox < n + L and -L < cy + oy < n + L:
                    poly_ = [(cx + ox - dx + px, cy + oy - dy + py), (cx + ox + dx * 0.9 + px * 0.7, cy + oy + dy * 0.9 + py * 0.7),
                             (cx + ox + dx, cy + oy + dy), (cx + ox + dx * 0.9 - px * 0.7, cy + oy + dy * 0.9 - py * 0.7),
                             (cx + ox - dx - px, cy + oy - dy - py)]
                    if seed_shadow:
                        sh = [(x + 1.6, y + 1.6) for x, y in poly_]
                        dr.polygon(sh, fill=tuple(int(v * 0.72) for v in c))
                    dr.polygon(poly_, fill=c)
                    # Maserung: dunklere Linie längs
                    dr.line([(cx + ox - dx * 0.8, cy + oy - dy * 0.8), (cx + ox + dx * 0.8, cy + oy + dy * 0.8)], fill=tuple(int(v * 0.8) for v in c), width=1)
                    dh.polygon(poly_, fill=int(rng.uniform(150, 230)))
    return np.asarray(img, np.float32) / 255.0, np.asarray(hmap, np.float32) / 255.0


def make_sawdust():
    rng = np.random.default_rng(5)
    base = np.array([0.86, 0.73, 0.52], np.float32)
    f1 = pnoise(1.3, 31)
    f2 = pnoise(4.0, 32)
    f3 = pnoise(40, 33)
    t = 1.0 + 0.06 * f1 + 0.06 * f2 + 0.05 * f3
    col = base[None, None, :] * t[..., None]
    col[..., 2] *= 1.0 - 0.04 * f3                                    # Farbstich leicht zwischen hell und dunkel
    height = 0.35 + 0.08 * f1 + 0.05 * f2
    palette = [np.array(c, np.float32) for c in ((0.86, 0.70, 0.46), (0.74, 0.55, 0.32), (0.64, 0.44, 0.24), (0.90, 0.78, 0.56), (0.55, 0.38, 0.20))]
    col, height = draw_chips(np.clip(col, 0, 1), np.clip(height, 0, 1), rng, 700, (6, 17), (1.8, 4.0), palette)
    # Dunklere feuchte Flecken
    wet = smooth(pnoise(55, 34), 0.8, 1.6)[..., None]
    col = col * (1 - wet * 0.12)
    save_pair("saegespaene", col, normal_from_height(height, 4.5))


# ---------------------------------------------------------------- Erde, festgetreten
def make_dirt():
    rng = np.random.default_rng(8)
    base = np.array([0.50, 0.40, 0.29], np.float32)
    big = pnoise(90, 41)
    mid = pnoise(18, 42)
    fine = pnoise(1.4, 43)
    t = 1.0 + 0.09 * big + 0.07 * mid + 0.08 * fine
    col = base[None, None, :] * t[..., None]
    col = col * (1 + 0.05 * pnoise(60, 44)[..., None] * np.array([0.6, 0.2, -0.3], np.float32))   # leichte Farbtonwolken
    height = 0.4 + 0.15 * mid + 0.1 * fine + 0.1 * big
    img = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8))
    hmap = Image.fromarray((np.clip(height, 0, 1) * 255).astype(np.uint8))
    dr = ImageDraw.Draw(img)
    dh = ImageDraw.Draw(hmap)
    n = N
    for _ in range(520):                                                 # Kieselsteine
        cx, cy = rng.uniform(0, n), rng.uniform(0, n)
        r = rng.uniform(1.4, 4.6)
        tone = rng.choice([0.62, 0.72, 0.52, 0.8])
        c = (int(255 * tone * 0.95), int(255 * tone * 0.9), int(255 * tone * 0.82))
        for ox in (-n, 0, n):
            for oy in (-n, 0, n):
                if -8 < cx + ox < n + 8 and -8 < cy + oy < n + 8:
                    dr.ellipse([cx + ox - r + 1.2, cy + oy - r + 1.2, cx + ox + r + 1.2, cy + oy + r + 1.2], fill=(40, 32, 24))
                    dr.ellipse([cx + ox - r, cy + oy - r, cx + ox + r, cy + oy + r], fill=c)
                    dh.ellipse([cx + ox - r, cy + oy - r, cx + ox + r, cy + oy + r], fill=225)
    for _ in range(160):                                                 # Strohhalme
        cx, cy = rng.uniform(0, n), rng.uniform(0, n)
        ang = rng.uniform(0, np.pi)
        L = rng.uniform(8, 22)
        c = (int(255 * rng.uniform(0.62, 0.8)), int(255 * rng.uniform(0.5, 0.64)), int(255 * rng.uniform(0.25, 0.36)))
        for ox in (-n, 0, n):
            for oy in (-n, 0, n):
                if -L < cx + ox < n + L and -L < cy + oy < n + L:
                    dr.line([(cx + ox, cy + oy), (cx + ox + np.cos(ang) * L, cy + oy + np.sin(ang) * L)], fill=c, width=1)
    col = np.asarray(img, np.float32) / 255.0
    height = np.asarray(hmap, np.float32) / 255.0
    save_pair("erde_platt", col, normal_from_height(height, 3.2))


# ---------------------------------------------------------------- Holzbretter (neutral)
def make_planks():
    rng = np.random.default_rng(12)
    boards = 8
    h = N // boards
    col = np.zeros((N, N, 3), np.float32)
    height = np.zeros((N, N), np.float32)
    x = np.arange(N)[None, :] / N
    for b in range(boards):
        y0 = b * h
        tone = rng.uniform(0.82, 1.1)
        gr = pnoise(2.2, 100 + b, N)[y0:y0 + h]                           # Rauschen quer
        # Maserung: Wellen längs der Bretter (periodisch), mit Rauschen gestört
        yy = (np.arange(h)[:, None] / h)
        warp = pnoise(160, 200 + b, N)[y0:y0 + h] * 0.03
        grain = np.sin(2 * np.pi * (yy * rng.integers(7, 13) + warp * 5 + x * 0.0)) * 0.5 + 0.5
        long_streak = pnoise(260, 300 + b, N)[y0:y0 + h]
        base = np.array([0.70, 0.62, 0.50], np.float32) * tone
        c = base[None, None, :] * (1 + 0.10 * (grain[..., None] - 0.5) + 0.025 * long_streak[..., None] + 0.04 * gr[..., None])
        # Fugen oben/unten
        edge = np.minimum(np.arange(h), h - 1 - np.arange(h))[:, None]
        c *= (0.35 + 0.65 * smooth(edge.astype(np.float32), 0.0, 3.0))[..., None]
        # Äste
        for _ in range(rng.integers(0, 3)):
            cx = rng.uniform(0, N)
            cy = rng.uniform(h * 0.25, h * 0.75)
            for xx in range(-14, 15):
                for yy_ in range(-8, 9):
                    d = np.hypot(xx / 14.0, yy_ / 8.0)
                    if d < 1.0:
                        px, py = int(cx + xx) % N, int(cy + yy_)
                        if 0 <= py < h:
                            c[py, px] *= 0.72 + 0.25 * d
        # Nagelköpfe an den Brettenden (periodisch, daher an zwei Stellen)
        for nx_ in (30, N // 2 + 30):
            for ny_ in (int(h * 0.3), int(h * 0.7)):
                c[ny_ - 1:ny_ + 2, nx_ - 1:nx_ + 2] *= 0.45
        col[y0:y0 + h] = c
        height[y0:y0 + h] = 0.5 + 0.12 * (grain - 0.5) + 0.2 * smooth(edge.astype(np.float32), 0.0, 3.0)
    save_pair("planken", col, normal_from_height(height, 6.0))


# ---------------------------------------------------------------- Schilder-Atlas
SIGNS = [  # (Text, Grundfarbe, Textfarbe, Rahmenfarbe)
    ("POMMES", "c0281c", "ffd23a", "ffe9a0"), ("BRATWURST", "a31d16", "fff3d0", "e9b23a"),
    ("ZUCKERWATTE", "e0599a", "ffffff", "ffe0ef"), ("GEBR. MANDELN", "6b3a1c", "ffe6b0", "e0a860"),
    ("CREPES", "fff0d2", "1b4a8a", "d5483a"), ("EIS", "1fa7b8", "ffffff", "ffe27a"),
    ("DOSEN WERFEN", "1f4fa6", "ffd23a", "ffffff"), ("SCHIESSEN", "1f7a3c", "ffe27a", "ffffff"),
    ("ENTENANGELN", "f2c21b", "1b4a8a", "d5483a"), ("LOS - GLÜCK", "6a2a8a", "ffd75a", "ffffff"),
    ("KASSE", "b3231b", "ffffff", "ffd23a"), ("EINLASS", "20232e", "ffd75a", "ffd75a"),
    ("BIER", "d98a1a", "fff3d0", "8a4a0a"), ("RIESENRAD", "2457b3", "ffffff", "ffd23a"),
    ("AUTOSCOOTER", "c0281c", "ffe27a", "ffffff"), ("KARUSSELL", "2f8a4a", "fff3d0", "ffd23a"),
]
SIGN_W, SIGN_H = 256, 128


def make_signs():
    atlas = Image.new("RGB", (SIGN_W * 4, SIGN_H * 4), (40, 40, 40))
    font_path = "C:/Windows/Fonts/BarlowCondensed-Bold.ttf"
    for i, (text, bg, fg, rim) in enumerate(SIGNS):
        cx, cy = (i % 4) * SIGN_W, (i // 4) * SIGN_H
        tile = Image.new("RGB", (SIGN_W, SIGN_H), "#" + bg)
        d = ImageDraw.Draw(tile)
        # leichte Farbverläufe und Rahmen
        for y in range(SIGN_H):
            k = 0.92 + 0.12 * (1 - abs(y - SIGN_H / 2) / (SIGN_H / 2))
            d.line([(0, y), (SIGN_W, y)], fill=tuple(min(255, int(int(bg[j:j + 2], 16) * k)) for j in (0, 2, 4)))
        d.rectangle([5, 5, SIGN_W - 6, SIGN_H - 6], outline="#" + rim, width=4)
        d.rectangle([12, 12, SIGN_W - 13, SIGN_H - 13], outline="#" + rim, width=1)
        size = 92
        while True:
            font = ImageFont.truetype(font_path, size)
            bb = d.textbbox((0, 0), text, font=font)
            if bb[2] - bb[0] <= SIGN_W - 44 and bb[3] - bb[1] <= SIGN_H - 40 or size < 24:
                break
            size -= 2
        tx = (SIGN_W - (bb[2] - bb[0])) / 2 - bb[0]
        ty = (SIGN_H - (bb[3] - bb[1])) / 2 - bb[1]
        d.text((tx + 2.5, ty + 2.5), text, font=font, fill=(0, 0, 0))
        d.text((tx, ty), text, font=font, fill="#" + fg)
        # Sterne an den Ecken
        for sx, sy in ((22, 22), (SIGN_W - 22, 22), (22, SIGN_H - 22), (SIGN_W - 22, SIGN_H - 22)):
            d.regular_polygon((sx, sy, 5), 5, fill="#" + rim)
        atlas.paste(tile, (cx, cy))
    atlas.save(os.path.join(OUT, "schilder.jpg"), quality=92)


if __name__ == "__main__":
    which = sys.argv[1:] or ["gras", "saege", "erde", "planken", "schilder"]
    if "gras" in which:
        make_grass()
    if "saege" in which:
        make_sawdust()
    if "erde" in which:
        make_dirt()
    if "planken" in which:
        make_planks()
    if "schilder" in which:
        make_signs()
    print("Texturen nach", OUT)
