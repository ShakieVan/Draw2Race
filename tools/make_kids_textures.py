"""Erzeugt die Texturen des Themas "kids" (Toy Box Speedway, Kinderzimmer) nach game/assets/dio/kids/ (alles prozedural, kein Fremdmaterial).

  parkett(.jpg/_n.jpg)        Atlas aus 8 Dielen (je 128 x 1024 Bildpunkte = 3 m x 24 m): Maserung, Fugen, Astlöcher, verschiedene Holztöne
  parkett_licht.jpg           dieselbe Anordnung heller und wärmer (Fensterlicht auf dem Boden)
  teppich(.jpg/_n.jpg)        Spielteppich: dunkelblaue Wolle mit Sternen, Monden und Wölkchen (nahtlos, 12 m je Kachel)
  wolle(.jpg/_n.jpg)          neutrale Wollstruktur (nahtlos, 4 m je Kachel), Farbe kommt aus der Vertexfarbe (Teppichrand, Fransen)
  tapete.jpg                  Kinderzimmer-Tapete (nahtlos, 6 m je Kachel): Streifen, Sternchen
  zeichnung.jpg               Kinderzeichnung mit Wachsmalstiften auf Papier (Rennstrecke mit Auto, Sonne, Haus)
  lineal.jpg                  Holzlineal mit Skala
  lineal_wippe_oben.jpg       Oberseite des Wippen-Lineals (24 x 4 m, 128 Bildpunkte je Meter): Buche, Zentimeterskala 0-60 an beiden Kanten, Ziffern
  lineal_wippe_teile.png      Seiten- und Stirnflächen des Wippen-Lineals: Buchenkante (oben), rot-weiße Schraffur (unten)
  truhe.jpg                   Deckel der Spielzeugtruhe mit der Aufschrift TOY BOX
  spiel.jpg                   Atlas 4 x 4 Felder: Brettspiel, Kartenrücken, Herz-Ass, Pik-König, Heft, Stickerbogen, Bilderbuch, Puzzle
  sand(.jpg/_n.jpg)           Spielsand aus dem Sandkasten (nahtlos, 6 m je Kachel): warm, feine Körnung, Wellen, feuchte Flecken, Kiesel, Muschelsplitter
Aufruf: python tools/make_kids_textures.py   (E:/Draw2Race-AudioLab/analyse/.venv/Scripts/python.exe: numpy, scipy, Pillow)
Schriften: Caveat Bold (Handschrift, OFL), Barlow Condensed Bold (OFL).
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from scipy import ndimage as ndi

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "assets", "dio", "kids")
os.makedirs(OUT, exist_ok=True)
N = 1024


def pnoise(scale_px, seed, shape=(N, N)):
    """Nahtloses Rauschen (Frequenzraum), Mittelwert 0, Streuung 1; shape = (Höhe, Breite)."""
    h, w = shape
    r = np.random.default_rng(seed)
    f = np.fft.fft2(r.standard_normal((h, w)))
    ky = np.fft.fftfreq(h)[:, None]
    kx = np.fft.fftfreq(w)[None, :]
    k = np.sqrt(kx ** 2 + ky ** 2) * scale_px
    x = np.real(np.fft.ifft2(f * np.exp(-k ** 2)))
    return (x - x.mean()) / (x.std() + 1e-9)


def smooth(x, e0, e1):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def normal_from_height(h, strength, wrap=True):
    h = ndi.gaussian_filter(h, 0.6, mode="wrap" if wrap else "nearest")
    gy, gx = np.gradient(h)
    nx, ny, nz = -gx * strength, gy * strength, np.ones_like(h)
    nn = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
    return np.stack([nx / nn, ny / nn, nz / nn], -1) * 0.5 + 0.5


def save_rgb(name, arr, quality=92):
    Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, name), quality=quality)


# ---------------------------------------------------------------- Parkett
PLANK_W, PLANK_H, NPLANK = 128, 1024, 8
WOODS = [(0.74, 0.55, 0.36), (0.69, 0.50, 0.32), (0.79, 0.60, 0.40), (0.63, 0.46, 0.30), (0.72, 0.53, 0.35), (0.67, 0.50, 0.34), (0.77, 0.58, 0.39), (0.60, 0.43, 0.28)]


def make_parkett():
    atlas = np.zeros((PLANK_H, PLANK_W * NPLANK, 3), np.float32)
    atlas_l = np.zeros_like(atlas)
    height = np.zeros((PLANK_H, PLANK_W * NPLANK), np.float32)
    for k in range(NPLANK):
        rng = np.random.default_rng(100 + k)
        base = np.array(WOODS[k], np.float32)
        xs = np.arange(PLANK_W)[None, :] / PLANK_W
        ys = np.arange(PLANK_H)[:, None] / PLANK_H
        warp = pnoise(220, 200 + k, (PLANK_H, PLANK_W)) * 0.11 + pnoise(70, 300 + k, (PLANK_H, PLANK_W)) * 0.03
        rings = np.sin(2 * np.pi * (xs * rng.uniform(5, 9) + warp * 3.2 + ys * rng.uniform(0.3, 0.9)))
        fine = pnoise(1.0, 400 + k, (PLANK_H, PLANK_W))
        # Fasern: lang gestrecktes Rauschen
        fibre = ndi.gaussian_filter(rng.standard_normal((PLANK_H, PLANK_W)), (30, 0.7))
        fibre = fibre / (fibre.std() + 1e-9)
        t = 1.0 + 0.07 * rings + 0.06 * fibre + 0.025 * fine + 0.05 * pnoise(220, 500 + k, (PLANK_H, PLANK_W))
        col = base[None, None, :] * t[..., None]
        col[..., 2] *= 1.0 - 0.05 * rings
        h_ = 0.5 + 0.12 * rings + 0.08 * fibre
        # Astlöcher
        for _ in range(rng.integers(0, 3)):
            cx, cy = rng.uniform(20, PLANK_W - 20), rng.uniform(60, PLANK_H - 60)
            rx, ry = rng.uniform(6, 11), rng.uniform(12, 22)
            yy, xx = np.mgrid[0:PLANK_H, 0:PLANK_W]
            d = np.hypot((xx - cx) / rx, (yy - cy) / ry)
            m = np.clip(1 - d, 0, 1)
            col *= (1 - 0.45 * m[..., None])
            ring_k = np.sin(d * 9) * 0.5 + 0.5
            col *= (1 - 0.12 * (ring_k * (d < 1.6))[..., None])
            h_ -= 0.25 * m
        # Fugen und Kantenfase
        edge = np.minimum(np.minimum(np.arange(PLANK_W)[None, :], PLANK_W - 1 - np.arange(PLANK_W)[None, :]), np.minimum(np.arange(PLANK_H)[:, None], PLANK_H - 1 - np.arange(PLANK_H)[:, None]))
        joint = smooth(edge.astype(np.float32), 0.0, 3.0)
        col *= (0.28 + 0.72 * joint)[..., None]
        bevel = np.exp(-np.maximum(edge - 1.0, 0) / 2.5) * 0.12
        left = np.exp(-np.arange(PLANK_W)[None, :] / 2.5)
        col += (bevel * left * 0.6)[..., None]
        h_ = h_ * (0.3 + 0.7 * joint)
        atlas[:, k * PLANK_W:(k + 1) * PLANK_W] = col
        height[:, k * PLANK_W:(k + 1) * PLANK_W] = h_
        warm = np.array([1.12, 1.07, 0.95], np.float32)                  # sonnenbeschienen: heller, wärmer
        atlas_l[:, k * PLANK_W:(k + 1) * PLANK_W] = np.clip(col * warm[None, None, :] * 1.28 + 0.05 * joint[..., None], 0, 1)
    save_rgb("parkett.jpg", atlas)
    save_rgb("parkett_licht.jpg", atlas_l)
    nrm = normal_from_height(height, 5.0, wrap=False)
    save_rgb("parkett_n.jpg", nrm)


# ---------------------------------------------------------------- Teppich (Wolle)
def star_points(cx, cy, r, rot):
    pts = []
    for i in range(10):
        rr = r if i % 2 == 0 else r * 0.42
        a = rot + i * math.pi / 5
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return pts


def make_rug():
    rng = np.random.default_rng(7)
    base = np.array([0.075, 0.13, 0.30], np.float32)
    fibre = pnoise(1.1, 11)
    fibre2 = ndi.gaussian_filter(rng.standard_normal((N, N)), (0.6, 2.2))
    tuft = pnoise(3.0, 12)
    t = 1.0 + 0.12 * fibre + 0.10 * fibre2 / (fibre2.std() + 1e-9) + 0.12 * tuft + 0.07 * pnoise(60, 13)
    col = base[None, None, :] * t[..., None]
    img = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8)).convert("RGB")
    d = ImageDraw.Draw(img)
    hmap = Image.new("L", (N, N), 128)
    dh = ImageDraw.Draw(hmap)
    n = N

    def stamp(fn):
        for ox in (-n, 0, n):
            for oy in (-n, 0, n):
                fn(ox, oy)

    # Wölkchen (heller), Sterne (gelb/cremefarben), Monde, Punkte
    for _ in range(9):
        cx, cy = rng.uniform(0, n), rng.uniform(0, n)
        w = rng.uniform(70, 110)

        def cloud(ox, oy, cx=cx, cy=cy, w=w):
            for dx, dy, r in ((-0.3, 0.05, 0.22), (0.0, -0.08, 0.28), (0.3, 0.03, 0.22), (0.1, 0.1, 0.2), (-0.1, 0.1, 0.2)):
                x, y, rr = cx + ox + dx * w, cy + oy + dy * w, r * w * 0.9
                d.ellipse([x - rr, y - rr * 0.8, x + rr, y + rr * 0.8], fill=(46, 82, 150))
        stamp(cloud)
    for _ in range(26):
        cx, cy = rng.uniform(0, n), rng.uniform(0, n)
        r = rng.uniform(16, 34)
        rot = rng.uniform(0, 2 * math.pi)
        c = tuple(int(v) for v in rng.choice([(246, 214, 92), (250, 236, 190), (240, 190, 70)], axis=0))

        def star(ox, oy, cx=cx, cy=cy, r=r, rot=rot, c=c):
            d.polygon(star_points(cx + ox, cy + oy, r, rot), fill=c)
            dh.polygon(star_points(cx + ox, cy + oy, r, rot), fill=190)
        stamp(star)
    for _ in range(3):
        cx, cy = rng.uniform(0, n), rng.uniform(0, n)
        r = rng.uniform(46, 62)

        def moon(ox, oy, cx=cx, cy=cy, r=r):
            d.ellipse([cx + ox - r, cy + oy - r, cx + ox + r, cy + oy + r], fill=(250, 232, 150))
            d.ellipse([cx + ox - r * 0.55, cy + oy - r * 1.05, cx + ox + r * 1.35, cy + oy + r * 0.95], fill=(22, 36, 86))
            dh.ellipse([cx + ox - r, cy + oy - r, cx + ox + r, cy + oy + r], fill=190)
        stamp(moon)
    for _ in range(140):
        cx, cy = rng.uniform(0, n), rng.uniform(0, n)
        r = rng.uniform(2.0, 4.5)

        def dot(ox, oy, cx=cx, cy=cy, r=r):
            d.ellipse([cx + ox - r, cy + oy - r, cx + ox + r, cy + oy + r], fill=(196, 214, 246))
        stamp(dot)
    arr = np.asarray(img, np.float32) / 255.0
    arr = arr * (1.0 + 0.10 * fibre[..., None] + 0.06 * tuft[..., None])
    save_rgb("teppich.jpg", arr)
    hh = np.asarray(hmap, np.float32) / 255.0 * 0.5 + 0.35 * (fibre * 0.5 + 0.5) + 0.25 * (tuft * 0.5 + 0.5)
    save_rgb("teppich_n.jpg", normal_from_height(hh, 2.6))


def make_wool():
    rng = np.random.default_rng(21)
    fibre = pnoise(1.2, 31)
    fibre2 = ndi.gaussian_filter(rng.standard_normal((N, N)), (0.6, 2.4))
    fibre2 = fibre2 / (fibre2.std() + 1e-9)
    tuft = pnoise(3.2, 32)
    t = 0.86 + 0.07 * fibre + 0.06 * fibre2 + 0.08 * tuft + 0.04 * pnoise(70, 33)
    col = np.stack([t, t, t], -1)
    save_rgb("wolle.jpg", col)
    save_rgb("wolle_n.jpg", normal_from_height(0.5 + 0.3 * fibre + 0.2 * fibre2 + 0.35 * tuft, 2.4))


# ---------------------------------------------------------------- Tapete
def make_wallpaper():
    n = 512
    img = Image.new("RGB", (n, n), (244, 238, 222))
    d = ImageDraw.Draw(img)
    stripe = n // 8
    for i in range(8):
        if i % 2 == 0:
            d.rectangle([i * stripe, 0, (i + 1) * stripe - 1, n], fill=(214, 228, 236))
    rng = np.random.default_rng(3)
    for _ in range(26):
        cx, cy = rng.uniform(0, n), rng.uniform(0, n)
        r = rng.uniform(6, 11)
        for ox in (-n, 0, n):
            for oy in (-n, 0, n):
                d.polygon(star_points(cx + ox, cy + oy, r, rng.uniform(0, 1)), fill=(244, 206, 96))
    arr = np.asarray(img, np.float32) / 255.0
    arr *= 1.0 + 0.02 * pnoise(1.5, 41, (n, n))[..., None]
    save_rgb("tapete.jpg", arr)


# ---------------------------------------------------------------- Zeichnung
def crayon_line(d, pts, color, width=4, rng=None, jitter=1.4, passes=3):
    rng = rng or np.random.default_rng(0)
    for p in range(passes):
        pj = [(x + rng.normal(0, jitter), y + rng.normal(0, jitter)) for x, y in pts]
        col = tuple(int(np.clip(c * rng.uniform(0.92, 1.05), 0, 255)) for c in color)
        d.line(pj, fill=col, width=max(1, int(width + rng.normal(0, 0.8))), joint="curve")


def crayon_fill(d, poly_pts, color, rng, step=5, width=4, jitter=2.0):
    xs = [p[0] for p in poly_pts]
    ys = [p[1] for p in poly_pts]
    mask = Image.new("L", (512, 384), 0)
    ImageDraw.Draw(mask).polygon(poly_pts, fill=255)
    m = np.asarray(mask)
    for y in range(int(min(ys)), int(max(ys)), step):
        row = np.where(m[y] > 0)[0] if 0 <= y < m.shape[0] else []
        if len(row) > 2:
            x0, x1 = row.min(), row.max()
            crayon_line(d, [(x0 + rng.normal(0, 2), y), (x1 + rng.normal(0, 2), y + rng.normal(0, 2))], color, width, rng, jitter, 1)


def make_drawing():
    W, H = 512, 384
    rng = np.random.default_rng(9)
    paper = np.array([0.97, 0.955, 0.92], np.float32)
    base = np.ones((H, W, 3), np.float32) * paper
    base *= 1.0 + 0.012 * pnoise(1.3, 51, (H, W))[..., None] + 0.01 * pnoise(40, 52, (H, W))[..., None]
    img = Image.fromarray((np.clip(base, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    # Himmel: blaue Schraffur oben
    crayon_fill(d, [(14, 14), (498, 14), (498, 150), (14, 150)], (120, 175, 230), rng, step=7, width=5)
    # Wiese
    crayon_fill(d, [(14, 250), (498, 250), (498, 370), (14, 370)], (90, 190, 90), rng, step=6, width=5)
    # Sonne
    cx, cy, r = 420, 66, 30
    crayon_fill(d, [(cx + r * math.cos(a / 18 * 2 * math.pi), cy + r * math.sin(a / 18 * 2 * math.pi)) for a in range(18)], (255, 214, 60), rng, 4, 4)
    for k in range(12):
        a = k * math.pi / 6
        crayon_line(d, [(cx + (r + 8) * math.cos(a), cy + (r + 8) * math.sin(a)), (cx + (r + 24) * math.cos(a), cy + (r + 24) * math.sin(a))], (255, 190, 30), 4, rng)
    # Rennstrecke: grauer Ring mit Mittellinie
    track = [(305 + 150 * math.cos(a / 40 * 2 * math.pi), 245 + 58 * math.sin(a / 40 * 2 * math.pi) * (1 + 0.15 * math.cos(a / 40 * 4 * math.pi))) for a in range(41)]
    crayon_line(d, track, (110, 110, 118), 24, rng, 1.5, 4)
    for i in range(0, 40, 2):
        crayon_line(d, [track[i], track[i + 1]], (250, 245, 230), 4, rng, 0.8, 1)
    # Auto (rot) auf der Strecke
    car = [(262, 296), (347, 296), (347, 270), (325, 270), (313, 252), (283, 252), (273, 270), (262, 270)]
    crayon_fill(d, car, (220, 40, 40), rng, 4, 4)
    crayon_line(d, car + [car[0]], (150, 20, 20), 3, rng)
    for wx in (279, 331):
        d.ellipse([wx - 11, 290, wx + 11, 312], fill=(30, 30, 34))
        d.ellipse([wx - 5, 296, wx + 5, 306], fill=(180, 180, 190))
    crayon_fill(d, [(287, 258), (307, 258), (315, 270), (279, 270)], (170, 220, 250), rng, 4, 3)
    # Haus
    crayon_fill(d, [(26, 196), (96, 196), (96, 258), (26, 258)], (240, 170, 70), rng, 4, 4)
    crayon_fill(d, [(18, 196), (61, 158), (104, 196)], (200, 60, 50), rng, 4, 4)
    crayon_fill(d, [(54, 226), (72, 226), (72, 258), (54, 258)], (120, 70, 40), rng, 4, 4)
    # Baum
    crayon_fill(d, [(118, 205), (128, 205), (128, 258), (118, 258)], (120, 80, 40), rng, 4, 4)
    crayon_fill(d, [(123 + 26 * math.cos(a / 14 * 2 * math.pi), 186 + 24 * math.sin(a / 14 * 2 * math.pi)) for a in range(14)], (50, 160, 60), rng, 4, 5)
    # Zielflagge, Herzchen, Schrift
    crayon_line(d, [(440, 220), (440, 300)], (80, 60, 40), 4, rng)
    for i in range(3):
        for j in range(3):
            if (i + j) % 2 == 0:
                d.rectangle([442 + i * 9, 222 + j * 9, 450 + i * 9, 230 + j * 9], fill=(30, 30, 34))
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/Caveat-Bold.ttf", 44)
        d.text((60, 318), "MEIN AUTO", font=font, fill=(200, 40, 140))
        d.text((62, 320), "MEIN AUTO", font=font, fill=(214, 60, 156))
    except Exception:
        pass
    for hx, hy in ((60, 50), (110, 90)):
        pts = [(hx, hy + 8), (hx - 14, hy - 6), (hx - 7, hy - 14), (hx, hy - 6), (hx + 7, hy - 14), (hx + 14, hy - 6)]
        crayon_fill(d, pts, (235, 70, 120), rng, 3, 3)
    # Papierkante und Lochung
    arr = np.asarray(img, np.float32) / 255.0
    save_rgb("zeichnung.jpg", arr, 94)


# ---------------------------------------------------------------- Lineal
def make_ruler():
    W, H = 1024, 96
    img = Image.new("RGB", (W, H), (236, 196, 112))
    d = ImageDraw.Draw(img)
    arr = np.asarray(img, np.float32) / 255.0
    arr *= 1.0 + 0.04 * ndi.gaussian_filter(np.random.default_rng(1).standard_normal((H, W)), (0.6, 14))[..., None] * 6
    img = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    for i in range(0, 151):
        x = 18 + i * (W - 36) / 150
        ln = 40 if i % 10 == 0 else (28 if i % 5 == 0 else 16)
        d.line([(x, 0), (x, ln)], fill=(40, 30, 20), width=2 if i % 10 == 0 else 1)
    font = ImageFont.truetype("C:/Windows/Fonts/BarlowCondensed-Bold.ttf", 34)
    for i in range(0, 16):
        x = 18 + i * 10 * (W - 36) / 150
        d.text((x + 5, 42), str(i), font=font, fill=(40, 30, 20))
    d.rectangle([0, 0, W - 1, H - 1], outline=(150, 110, 50), width=3)
    img.save(os.path.join(OUT, "lineal.jpg"), quality=92)


# ---------------------------------------------------------------- Lineal der Wippe (Abkürzung im Kinderzimmer, tools/make_kids_ruler.py)
def beech(h, w, seed, base=(0.86, 0.70, 0.50)):
    """Buchenholz (lackiert): feine, lange Fasern, schwache Jahresringe, Markstrahlen als kurze dunkle Striche."""
    rng = np.random.default_rng(seed)
    fibre = ndi.gaussian_filter(rng.standard_normal((h, w)), (0.8, 40))
    fibre /= fibre.std() + 1e-9
    warp = pnoise(160, seed + 1, (h, w)) * 0.5
    rings = np.sin(2 * np.pi * (np.arange(h)[:, None] / h * 7.0 + warp))
    rays = (ndi.gaussian_filter(rng.standard_normal((h, w)), (0.6, 2.0)) > 1.9).astype(np.float32)
    t = 1.0 + 0.035 * fibre + 0.012 * rings - 0.05 * rays + 0.025 * pnoise(300, seed + 2, (h, w))
    return np.array(base, np.float32)[None, None, :] * t[..., None]


def make_ruler_seesaw():
    W, H = 3072, 512                                   # 24 m x 4 m: 128 Bildpunkte je Meter; links = Ausfahrtsende (0 cm), rechts = Einfahrtsende (60 cm)
    arr = beech(H, W, 71)
    # Kanten etwas dunkler (Fase), Lack glänzt hell in der Mitte
    yy = np.arange(H)[:, None] / H
    arr *= (0.9 + 0.1 * np.clip(np.minimum(yy, 1 - yy) / 0.04, 0, 1))[..., None]
    img = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    ink = (28, 22, 18)
    x0, x1 = 64, W - 64                                # Skala 0 bis 60 cm (0,4 m je Zentimeter, 6 m Rand für die Endkappen)
    font = ImageFont.truetype("C:/Windows/Fonts/BarlowCondensed-Bold.ttf", 66)
    small = ImageFont.truetype("C:/Windows/Fonts/BarlowCondensed-Bold.ttf", 30)
    for i in range(0, 601):
        x = x0 + i * (x1 - x0) / 600
        ln = 70 if i % 10 == 0 else (46 if i % 5 == 0 else 26)
        wd = 4 if i % 10 == 0 else 2
        d.line([(x, H - 1), (x, H - 1 - ln)], fill=ink, width=wd)       # Unterkante (Süden im Bild): Millimeter, Zentimeter länger
        if i % 10 == 0:
            d.line([(x, 0), (x, 40)], fill=ink, width=wd)                # Oberkante: nur Zentimeter
        elif i % 5 == 0:
            d.line([(x, 0), (x, 22)], fill=ink, width=2)
    mid = ImageFont.truetype("C:/Windows/Fonts/BarlowCondensed-Bold.ttf", 38)
    for k in range(0, 61):
        x = x0 + k * 10 * (x1 - x0) / 600
        txt = str(k)
        f_ = font if k % 5 == 0 else mid                                   # volle Fünfer groß, die übrigen Zentimeter klein
        tw = d.textlength(txt, font=f_)
        d.text((x - tw / 2, H - 1 - 76 - (74 if k % 5 == 0 else 44)), txt, font=f_, fill=ink)
    d.text((x0 + 12, 52), "cm", font=small, fill=ink)
    # Aufdruck in der Mitte (wie auf Schullinealen), dezent
    brand = ImageFont.truetype("C:/Windows/Fonts/BarlowCondensed-Bold.ttf", 92)
    txt = "TOY BOX  ·  60 cm"
    tw = d.textlength(txt, font=brand)
    d.text(((W - tw) / 2, 150), txt, font=brand, fill=(120, 74, 40))
    img = img.filter(ImageFilter.GaussianBlur(0.6))
    img.save(os.path.join(OUT, "lineal_wippe_oben.jpg"), quality=92)
    # Teile: oben Buchenkante (Seitenflächen, Maserung längs), unten links rot-weiße Schraffur (Stirn am Einfahrtsende)
    T = 512
    parts = np.ones((T, T, 3), np.float32)
    parts[:T // 2] = beech(T // 2, T, 72, base=(0.80, 0.63, 0.43))
    yy, xx = np.mgrid[0:T // 2, 0:T]
    stripe = ((xx + yy) // 48) % 2 == 0
    red = np.array((0.80, 0.10, 0.08), np.float32)
    white = np.array((0.95, 0.94, 0.90), np.float32)
    parts[T // 2:] = np.where(stripe[..., None], red, white)
    Image.fromarray((np.clip(parts, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, "lineal_wippe_teile.png"))


# ---------------------------------------------------------------- Truhendeckel
def make_chest():
    W, H = 512, 320
    base = np.ones((H, W, 3), np.float32) * np.array([0.72, 0.5, 0.3], np.float32)
    rng = np.random.default_rng(5)
    # Bretter längs
    for b in range(5):
        y0, y1 = b * H // 5, (b + 1) * H // 5
        tone = rng.uniform(0.9, 1.1)
        grain = ndi.gaussian_filter(rng.standard_normal((y1 - y0, W)), (0.8, 25))
        base[y0:y1] *= tone * (1 + 0.5 * grain / (grain.std() + 1e-9) * 0.05)[..., None]
        base[y0] *= 0.55
    img = Image.fromarray((np.clip(base, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    d.rectangle([6, 6, W - 7, H - 7], outline=(200, 40, 40), width=10)
    d.rectangle([22, 22, W - 23, H - 23], outline=(250, 240, 220), width=3)
    font = ImageFont.truetype("C:/Windows/Fonts/BarlowCondensed-Bold.ttf", 96)
    text = "TOY BOX"
    cols = [(228, 52, 52), (250, 196, 32), (60, 140, 230), (60, 180, 90), (250, 130, 40), (160, 90, 200), (228, 52, 52)]
    x = 40
    for i, ch in enumerate(text):
        bb = d.textbbox((0, 0), ch, font=font)
        cw = bb[2] - bb[0]
        if ch == " ":
            x += 18
            continue
        d.rounded_rectangle([x - 6, 104, x + cw + 8, 214], radius=12, fill=(250, 244, 226), outline=(110, 70, 40), width=3)
        d.text((x + 1 - bb[0], 110 - bb[1]), ch, font=font, fill=cols[i % len(cols)])
        x += cw + 16
    for sx, sy in ((50, 50), (W - 50, 50), (50, H - 50), (W - 50, H - 50)):
        d.polygon(star_points(sx, sy, 20, 0.3), fill=(250, 214, 80), outline=(160, 110, 30))
    img.save(os.path.join(OUT, "truhe.jpg"), quality=92)


# ---------------------------------------------------------------- Spielsachen-Atlas (4 x 4 Felder zu 256 Bildpunkten)
def make_spiel():
    """Spielbrett, Spielkarten, Heft, Stickerbogen, Bilderbuch, Puzzle (flach liegende Spielsachen); Feld (spalte, zeile) von links oben."""
    C = 256
    img = Image.new("RGB", (C * 4, C * 4), (240, 236, 224))
    d = ImageDraw.Draw(img)
    font_b = ImageFont.truetype("C:/Windows/Fonts/BarlowCondensed-Bold.ttf", 54)
    font_s = ImageFont.truetype("C:/Windows/Fonts/BarlowCondensed-Bold.ttf", 30)
    cols = [(214, 58, 42), (45, 95, 196), (47, 154, 76), (242, 194, 27)]

    def cell(i):
        return (i % 4) * C, (i // 4) * C

    # 0: Brettspiel (Kreuzbrett mit vier Häusern)
    ox, oy = cell(0)
    d.rectangle([ox, oy, ox + C - 1, oy + C - 1], fill=(242, 226, 186), outline=(110, 70, 40), width=6)
    step = 20
    mid = C // 2
    pts = set()
    for k in range(-5, 6):
        for off in (-20, 0, 20):
            pts.add((mid + k * step, mid + off))
            pts.add((mid + off, mid + k * step))
    for (px, py) in pts:
        d.ellipse([ox + px - 8, oy + py - 8, ox + px + 8, oy + py + 8], fill=(252, 250, 244), outline=(90, 60, 40), width=2)
    for k, (cx, cy) in enumerate(((40, 40), (C - 40, 40), (C - 40, C - 40), (40, C - 40))):
        d.rounded_rectangle([ox + cx - 30, oy + cy - 30, ox + cx + 30, oy + cy + 30], radius=10, fill=cols[k], outline=(60, 40, 30), width=3)
        for (dx, dy) in ((-12, -12), (12, -12), (-12, 12), (12, 12)):
            d.ellipse([ox + cx + dx - 7, oy + cy + dy - 7, ox + cx + dx + 7, oy + cy + dy + 7], fill=(252, 250, 244))
    d.ellipse([ox + mid - 12, oy + mid - 12, ox + mid + 12, oy + mid + 12], fill=(250, 214, 80), outline=(90, 60, 40), width=3)
    # 1: Kartenrücken
    ox, oy = cell(1)
    d.rounded_rectangle([ox + 20, oy + 6, ox + C - 20, oy + C - 6], radius=14, fill=(250, 250, 246), outline=(60, 60, 70), width=3)
    d.rounded_rectangle([ox + 30, oy + 16, ox + C - 30, oy + C - 16], radius=8, fill=(40, 70, 160))
    for i in range(-8, 18):
        d.line([(ox + 30 + i * 14, oy + 16), (ox + 30 + i * 14 + 190, oy + C - 16)], fill=(210, 220, 245), width=2)
        d.line([(ox + 30 + i * 14 + 190, oy + 16), (ox + 30 + i * 14, oy + C - 16)], fill=(210, 220, 245), width=2)
    d.rounded_rectangle([ox + 30, oy + 16, ox + C - 30, oy + C - 16], radius=8, outline=(250, 250, 246), width=6)
    # 2: Herz-Ass
    ox, oy = cell(2)
    d.rounded_rectangle([ox + 20, oy + 6, ox + C - 20, oy + C - 6], radius=14, fill=(252, 252, 248), outline=(60, 60, 70), width=3)
    d.text((ox + 34, oy + 14), "A", font=font_b, fill=(200, 30, 40))
    d.ellipse([ox + 78, oy + 84, ox + 128, oy + 134], fill=(200, 30, 40))
    d.ellipse([ox + 128, oy + 84, ox + 178, oy + 134], fill=(200, 30, 40))
    d.polygon([(ox + 80, oy + 118), (ox + 176, oy + 118), (ox + 128, oy + 190)], fill=(200, 30, 40))
    # 3: Pik-König
    ox, oy = cell(3)
    d.rounded_rectangle([ox + 20, oy + 6, ox + C - 20, oy + C - 6], radius=14, fill=(252, 252, 248), outline=(60, 60, 70), width=3)
    d.text((ox + 34, oy + 14), "K", font=font_b, fill=(25, 25, 30))
    d.ellipse([ox + 80, oy + 112, ox + 128, oy + 160], fill=(25, 25, 30))
    d.ellipse([ox + 128, oy + 112, ox + 176, oy + 160], fill=(25, 25, 30))
    d.polygon([(ox + 128, oy + 70), (ox + 82, oy + 132), (ox + 174, oy + 132)], fill=(25, 25, 30))
    d.polygon([(ox + 118, oy + 150), (ox + 138, oy + 150), (ox + 150, oy + 198), (ox + 106, oy + 198)], fill=(25, 25, 30))
    # 4: Heft (Seite mit Linien und Rand, Kritzelei)
    ox, oy = cell(4)
    d.rectangle([ox, oy, ox + C - 1, oy + C - 1], fill=(250, 250, 244))
    for yy in range(26, C, 16):
        d.line([(ox, oy + yy), (ox + C, oy + yy)], fill=(150, 185, 225), width=2)
    d.line([(ox + 40, oy), (ox + 40, oy + C)], fill=(225, 110, 110), width=3)
    rng = np.random.default_rng(12)
    xx, yy = 60, 90
    for _ in range(26):
        nx_, ny_ = xx + int(rng.integers(-14, 20)), yy + int(rng.integers(-18, 18))
        d.line([(ox + xx, oy + yy), (ox + nx_, oy + ny_)], fill=(40, 60, 170), width=3)
        xx, yy = min(max(nx_, 50), 230), min(max(ny_, 50), 200)
    d.text((ox + 52, oy + 18), "Hausaufgabe", font=font_s, fill=(40, 60, 170))
    # 5: Stickerbogen
    ox, oy = cell(5)
    d.rectangle([ox, oy, ox + C - 1, oy + C - 1], fill=(206, 228, 246))
    for r_ in range(4):
        for c_ in range(4):
            cx, cy = ox + 32 + c_ * 64, oy + 32 + r_ * 64
            col = cols[(r_ + c_) % 4]
            if (r_ + c_) % 3 == 0:
                d.polygon(star_points(cx, cy, 24, 0.2), fill=col, outline=(255, 255, 255))
            elif (r_ + c_) % 3 == 1:
                d.ellipse([cx - 24, cy - 16, cx, cy + 8], fill=col, outline=(255, 255, 255))
                d.ellipse([cx, cy - 16, cx + 24, cy + 8], fill=col, outline=(255, 255, 255))
                d.polygon([(cx - 22, cy), (cx + 22, cy), (cx, cy + 26)], fill=col, outline=(255, 255, 255))
            else:
                d.ellipse([cx - 20, cy - 20, cx + 20, cy + 20], fill=col, outline=(255, 255, 255), width=3)
                d.ellipse([cx - 8, cy - 8, cx + 8, cy + 8], fill=(255, 255, 255))
    # 6: Bilderbuch (Frosch)
    ox, oy = cell(6)
    d.rectangle([ox, oy, ox + C - 1, oy + C - 1], fill=(250, 226, 120), outline=(120, 80, 30), width=8)
    d.ellipse([ox + 54, oy + 70, ox + 202, oy + 190], fill=(90, 190, 90), outline=(40, 110, 50), width=4)
    for sx in (74, 182):
        d.ellipse([ox + sx - 26, oy + 52, ox + sx + 26, oy + 104], fill=(252, 252, 246), outline=(40, 110, 50), width=4)
        d.ellipse([ox + sx - 9, oy + 68, ox + sx + 9, oy + 90], fill=(20, 20, 20))
    d.arc([ox + 84, oy + 112, ox + 172, oy + 176], 20, 160, fill=(40, 90, 40), width=5)
    d.text((ox + 62, oy + 200), "FROSCH", font=font_s, fill=(60, 40, 20))
    # 7: Puzzle (Bild mit Teilen: Sonne, Hügel, Haus), unten rechts fehlen Teile
    ox, oy = cell(7)
    d.rectangle([ox, oy, ox + C - 1, oy + C - 1], fill=(120, 190, 240))
    d.ellipse([ox + 170, oy + 20, ox + 226, oy + 76], fill=(252, 214, 60))
    d.ellipse([ox - 60, oy + 150, ox + 200, oy + 330], fill=(110, 190, 90))
    d.ellipse([ox + 100, oy + 170, ox + 330, oy + 330], fill=(80, 165, 80))
    d.rectangle([ox + 54, oy + 114, ox + 120, oy + 176], fill=(230, 210, 180))
    d.polygon([(ox + 46, oy + 114), (ox + 87, oy + 74), (ox + 128, oy + 114)], fill=(200, 60, 50))
    d.rectangle([ox + 78, oy + 140, ox + 98, oy + 176], fill=(120, 80, 50))
    n_ = 8
    for i in range(1, n_):
        d.line([(ox + i * C // n_, oy), (ox + i * C // n_, oy + C)], fill=(60, 80, 100), width=1)
        d.line([(ox, oy + i * C // n_), (ox + C, oy + i * C // n_)], fill=(60, 80, 100), width=1)
    for (i, j) in ((6, 6), (7, 6), (6, 7), (7, 7), (5, 7)):
        d.rectangle([ox + i * C // n_, oy + j * C // n_, ox + (i + 1) * C // n_, oy + (j + 1) * C // n_], fill=(176, 140, 100), outline=(120, 90, 60))
    d.rectangle([ox, oy, ox + C - 1, oy + C - 1], outline=(60, 80, 100), width=3)
    img.save(os.path.join(OUT, "spiel.jpg"), quality=92)


# ---------------------------------------------------------------- Sand (Sandkasten-Malheur an der langsamen Stelle)
def make_sand():
    """Spielsand: warmes Beige mit feuchten dunkleren Flecken, sanften Wellen (Wind und Hand), feiner Körnung, einigen Kieseln und Muschelsplittern.
    Kachel 6 m: ein Bildpunkt = 6 mm; die sichtbaren Merkmale sind Flecken (0,3 bis 1 m), Wellen (Abstand 0,4 m), Kiesel (3 bis 8 cm)."""
    rng = np.random.default_rng(77)
    n1, n2, n3 = pnoise(190, 701), pnoise(60, 702), pnoise(14, 703)
    dry = np.array([0.86, 0.74, 0.50])
    mid = np.array([0.78, 0.65, 0.42])
    damp = np.array([0.62, 0.50, 0.32])
    base = dry[None, None, :] * (1 - smooth(n1, -0.6, 0.9))[..., None] + mid[None, None, :] * smooth(n1, -0.6, 0.9)[..., None]
    base = base * (1 - 0.8 * smooth(n2 - 0.4 * n1, 0.7, 1.7))[..., None] + damp[None, None, :] * (0.8 * smooth(n2 - 0.4 * n1, 0.7, 1.7))[..., None]
    # Wellen: gewölbte, leicht verbogene Linien (Sinus über verzerrter Koordinate)
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    warp = pnoise(150, 704) * 26 + pnoise(40, 705) * 5
    ripple = np.sin(2 * np.pi * (yy * 0.3 + xx * 0.8 + warp) / 68.0)
    grain = pnoise(1.3, 706) * 0.55 + pnoise(0.7, 707) * 0.45
    col = base * (1.0 + 0.045 * ripple + 0.055 * grain + 0.06 * n3)[..., None]
    img = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8))
    hgt = Image.fromarray(((ripple * 0.5 + 0.5) * 120 + grain * 14 + 60).clip(0, 255).astype(np.uint8)).convert("F")
    d, dh = ImageDraw.Draw(img), ImageDraw.Draw(hgt)

    def blob(x, y, rx, ry, rot, color, height):
        pts = [(x + rx * math.cos(t) * math.cos(rot) - ry * math.sin(t) * math.sin(rot), y + rx * math.cos(t) * math.sin(rot) + ry * math.sin(t) * math.cos(rot))
               for t in np.linspace(0, 2 * math.pi, 12, endpoint=False)]
        for dx in (-N, 0, N):
            for dy in (-N, 0, N):
                q = [(px + dx, py + dy) for px, py in pts]
                d.polygon(q, fill=tuple(int(c * 255) for c in color))
                dh.polygon(q, fill=height)

    # dunkle und helle Sandkörner (einzelne Bildpunkte bis kleine Klumpen)
    for _ in range(9000):
        x, y = rng.uniform(0, N, 2)
        r = rng.uniform(0.9, 2.2)
        g = rng.uniform(0.45, 0.95)
        blob(x, y, r, r * rng.uniform(0.6, 1.0), rng.uniform(0, 3), (0.80 * g, 0.66 * g, 0.44 * g) if rng.random() < 0.6 else (0.93, 0.83, 0.62), 150 + 40 * rng.random())
    # Kiesel
    for _ in range(70):
        x, y = rng.uniform(0, N, 2)
        r = rng.uniform(3.0, 8.0)
        g = rng.uniform(0.40, 0.72)
        tint = (g * 1.02, g * 0.95, g * 0.80)
        blob(x + 1.2, y + 1.2, r, r * 0.85, 0.0, tuple(c * 0.55 for c in tint), 100)
        blob(x, y, r, r * rng.uniform(0.6, 0.95), rng.uniform(0, 3), tint, 175 + r * 3)
        blob(x - r * 0.25, y - r * 0.25, r * 0.5, r * 0.4, 0.0, tuple(min(1, c * 1.2) for c in tint), 190 + r * 3)
    # Muschelsplitter (hell, rosa)
    for _ in range(14):
        x, y = rng.uniform(0, N, 2)
        r = rng.uniform(2.5, 5.5)
        blob(x, y, r, r * 0.5, rng.uniform(0, 3), (0.95, 0.80, 0.76) if rng.random() < 0.6 else (0.96, 0.93, 0.86), 185)
    arr = np.asarray(img, np.float32) / 255.0
    h = np.asarray(hgt, np.float32) / 255.0
    Image.fromarray((np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, "sand.jpg"), quality=92)
    Image.fromarray((normal_from_height(h * 9.0, 2.2) * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, "sand_n.jpg"), quality=92)


if __name__ == "__main__":
    which = sys.argv[1:] or ["parkett", "teppich", "wolle", "tapete", "zeichnung", "lineal", "truhe", "spiel", "sand", "lineal_wippe"]
    if "parkett" in which:
        make_parkett()
    if "teppich" in which:
        make_rug()
    if "wolle" in which:
        make_wool()
    if "tapete" in which:
        make_wallpaper()
    if "zeichnung" in which:
        make_drawing()
    if "lineal" in which:
        make_ruler()
    if "truhe" in which:
        make_chest()
    if "spiel" in which:
        make_spiel()
    if "sand" in which:
        make_sand()
    if "lineal_wippe" in which:
        make_ruler_seesaw()
    print("Texturen nach", OUT)
