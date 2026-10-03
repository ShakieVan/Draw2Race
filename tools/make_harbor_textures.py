"""Erzeugt die Texturen des Hafen-Themas (tools/dio_themes/harbor.py): Boden-Sets für den Boden-Shader, Container-, Blech- und
Schildertexturen für die Blender-Materialien.

Alles prozedural (numpy, scipy, Pillow); Grundrauschen stammt aus eigenem FFT-Rauschen, die Asphaltkörnung aus der CC0-Textur
Asphalt031 (ambientCG, art/texturen). Ergebnis:
  game/assets/dio/harbor/            Boden-Shader (Name, Name_n): beton, asphalt, verschleiss  (Godot importiert sie mit Mipmaps)
  game/assets/dio/harbor/src/        Quellen der Blender-Materialien (Container, Blech ...), mit .gdignore: Godot ignoriert den Ordner,
                                     die glTF-Ausgabe von Blender bettet die Bilder in die .glb ein
Aufruf:  E:/Draw2Race-AudioLab/analyse/.venv/Scripts/python.exe tools/make_harbor_textures.py [Name ...]   (ohne Namen: alles)
Alle Texturen sind kachelbar (FFT-Rauschen, Zeichnen mit Umbruch). Größe höchstens 1024 px.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT = os.path.join(ROOT, "game", "assets", "dio", "harbor")
SRC = os.path.join(OUT, "src")
ART = os.path.join(ROOT, "art", "texturen")
FONT = os.path.join(ROOT, "game", "assets", "Outfit.ttf")


# ---------------------------------------------------------------- Werkzeuge
def tile_noise(n, beta=2.0, seed=0, shape=None):
    """Kachelbares Rauschen mit Leistungsspektrum 1/f^beta (FFT), Mittelwert 0, Streuung 1."""
    rng = np.random.default_rng(seed)
    h, w = shape if shape else (n, n)
    f = np.fft.fft2(rng.standard_normal((h, w)))
    fy = np.fft.fftfreq(h)[:, None]
    fx = np.fft.fftfreq(w)[None, :]
    r = np.sqrt(fx ** 2 + fy ** 2)
    r[0, 0] = 1.0
    f *= r ** (-beta / 2.0)
    f[0, 0] = 0.0
    out = np.real(np.fft.ifft2(f))
    return (out - out.mean()) / (out.std() + 1e-9)


def smooth(x, lo, hi):
    t = np.clip((x - lo) / (hi - lo), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def blur(a, sigma):
    return ndi.gaussian_filter(a, sigma, mode="wrap")


def srgb_to_lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def to_img(rgb):
    return Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")


def normal_from_height(h, strength):
    """OpenGL-Normalkarte (Y nach oben im Bild) aus einer Höhenkarte (Kachelränder umbrechen)."""
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5     # Zeilenindex wächst nach unten
    nx, ny, nz = -gx * strength, gy * strength, np.ones_like(h)
    ln = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
    return np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5


def draw_wrapped(mask, polyline, width=1, value=1.0):
    """Linienzug in eine kachelbare Maske zeichnen (alle neun Verschiebungen)."""
    n_h, n_w = mask.shape
    img = Image.fromarray((mask * 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    for dy in (-n_h, 0, n_h):
        for dx in (-n_w, 0, n_w):
            pts = [(x + dx, y + dy) for x, y in polyline]
            d.line(pts, fill=int(value * 255), width=width)
    return np.asarray(img).astype(np.float64) / 255.0


def random_walk(rng, start, direction, length, step=2.0, wobble=0.35):
    x, y = start
    a = direction
    pts = [(x, y)]
    for _ in range(int(length / step)):
        a += rng.normal(0, wobble)
        x += math.cos(a) * step
        y += math.sin(a) * step
        pts.append((x, y))
    return pts


def blobs(n, rng, count, rmin, rmax, noise_seed):
    """Weiche, unregelmäßige Flecken (0..1), kachelbar."""
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float64)
    wob = tile_noise(n, 2.6, noise_seed)
    out = np.zeros((n, n))
    for _ in range(count):
        cx, cy = rng.uniform(0, n, 2)
        r = rng.uniform(rmin, rmax)
        dx = np.minimum(np.abs(xs - cx), n - np.abs(xs - cx))
        dy = np.minimum(np.abs(ys - cy), n - np.abs(ys - cy))
        d = np.sqrt(dx ** 2 + dy ** 2) / (r * (1.0 + 0.35 * wob))
        out = np.maximum(out, np.clip(1.0 - d, 0.0, 1.0) ** 1.4)
    return out


def load_art(name, kind="Color", size=None):
    im = Image.open(os.path.join(ART, name, f"{name}_1K-JPG_{kind}.jpg")).convert("RGB")
    if size:
        im = im.resize((size, size), Image.LANCZOS)
    return np.asarray(im).astype(np.float64) / 255.0


def save(img, folder, name, quality=92):
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, name)
    if name.endswith(".png"):
        img.save(path, optimize=True)
    else:
        img.save(path, quality=quality, subsampling=0)
    print("  ", os.path.relpath(path, ROOT), img.size)


# ---------------------------------------------------------------- Beton: Platten mit Fugen (Kachel 8 m)
def make_beton(n=1024, seed=11):
    S = 8.0                                      # Kachelgröße in m
    px = S / n
    rng = np.random.default_rng(seed)
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float64)
    xm, ym = xs * px, ys * px
    # Grundton und Wolken
    lum = 0.665 + 0.030 * tile_noise(n, 2.6, seed + 1) + 0.020 * tile_noise(n, 1.8, seed + 2)
    # Betonkörnung der CC0-Textur Concrete034 (kachelt in x und y), verkleinert eingemischt
    conc = np.asarray(Image.open(os.path.join(ART, "Concrete034", "Concrete034_1K-JPG_Color.jpg")).convert("L").resize((n, n), Image.LANCZOS)).astype(np.float64) / 255.0
    conc = conc - blur(conc, 24)
    lum += conc * 0.35
    lum += 0.014 * tile_noise(n, 0.4, seed + 3)                     # feines Korn
    # Poren: kleine dunkle Punkte
    pores = np.zeros((n, n))
    pts = rng.uniform(0, n, (900, 2)).astype(int)
    pores[pts[:, 1] % n, pts[:, 0] % n] = rng.uniform(0.4, 1.0, 900)
    lum -= blur(pores, 0.9) * 0.9
    # Platten: 4 m x 4 m, zweite Reihe um 2 m versetzt
    slab_w = 4.0
    row = np.floor(ym / slab_w).astype(int)
    col_x = xm + np.where(row % 2 == 1, slab_w / 2, 0.0)
    col = np.floor(col_x / slab_w).astype(int)
    sid = (row * 7 + col * 3 + 11) % 17
    off = (np.sin(sid * 12.9898 + 0.5) * 43758.5453) % 1.0
    lum += (off - 0.5) * 0.06                                       # jede Platte etwas anders hell
    # Fugen
    fx = np.abs(((col_x + slab_w / 2) % slab_w) - slab_w / 2)         # Abstand zur senkrechten Fuge
    fy = np.abs(((ym + slab_w / 2) % slab_w) - slab_w / 2)            # Abstand zur waagerechten Fuge
    dj = np.minimum(fx, fy) / px                                      # Abstand in Pixeln
    groove = smooth(2.6 - dj, 0.0, 2.6)                               # dunkle Fuge ~5 px = 3,9 cm
    edge = smooth(5.5 - dj, 0.0, 3.0) * 0.5                           # Fasen-/Verschmutzungssaum
    lum = lum - groove * 0.30 - edge * 0.035
    # Haarrisse
    cracks = np.zeros((n, n))
    for _ in range(7):
        start = rng.uniform(0, n, 2)
        cracks = np.maximum(cracks, draw_wrapped(np.zeros((n, n)), random_walk(rng, start, rng.uniform(0, 6.28), rng.uniform(120, 420)), 1, rng.uniform(0.5, 1.0)))
    cracks = blur(cracks, 0.7)
    lum -= cracks * 0.28
    # Verschmutzung: dunkle Randzonen, Ölflecken (wenige, flach)
    oil = blobs(n, rng, 5, 25, 70, seed + 4)
    rust = blobs(n, rng, 4, 8, 22, seed + 5) * smooth(tile_noise(n, 1.0, seed + 6), 0.0, 1.2)
    lum -= oil * 0.075
    col_rgb = np.stack([lum, lum * 0.992, lum * 0.975], -1)
    col_rgb[..., 0] += rust * 0.045
    col_rgb[..., 1] += rust * 0.012
    col_rgb[..., 2] -= rust * 0.02
    color = to_img(col_rgb)
    height = conc * 1.2 + tile_noise(n, 0.5, seed + 3) * 0.12 - groove * 1.4 - cracks * 0.5 - blur(pores, 0.8) * 1.0
    normal = to_img(normal_from_height(height, 2.4))
    return color, normal


# ---------------------------------------------------------------- Asphalt (Kachel 6 m): Körnung von Asphalt031, Flicken und Risse
def make_asphalt(n=1024, seed=21):
    S = 6.0
    rng = np.random.default_rng(seed)
    base = load_art("Asphalt031", "Color")
    nrm_src = load_art("Asphalt031", "NormalGL")
    # Korn: 1024-Bild halbiert und 2x2 gekachelt -> feiner
    half = np.asarray(Image.fromarray((base * 255).astype(np.uint8)).resize((n // 2, n // 2), Image.LANCZOS)).astype(np.float64) / 255.0
    grain = np.tile(half, (2, 2, 1))
    lum_g = grain.mean(-1)
    lum_g = (lum_g - blur(lum_g, 30)) * 1.0
    nhalf = np.asarray(Image.fromarray((nrm_src * 255).astype(np.uint8)).resize((n // 2, n // 2), Image.LANCZOS)).astype(np.float64) / 255.0
    ngrain = np.tile(nhalf, (2, 2, 1))
    lum = 0.300 + lum_g * 0.55 + 0.022 * tile_noise(n, 2.4, seed + 1) + 0.015 * tile_noise(n, 1.6, seed + 2)
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float64)
    # Fahrspur-Polierung: Streifen mit etwas dunklerem/glatterem Belag
    lum -= 0.025 * smooth(np.sin(xs / n * 2 * math.pi * 2.0) * 0.5 + 0.5, 0.65, 0.95)
    # Flicken: rechteckige Reparaturstellen, leicht dunkler und glatter, scharfe Naht
    patch = np.zeros((n, n))
    for _ in range(3):
        w, h = rng.uniform(100, 330), rng.uniform(80, 260)
        x0, y0 = rng.uniform(0, n), rng.uniform(0, n)
        m = ((((xs - x0) % n) < w) & (((ys - y0) % n) < h)).astype(np.float64)
        patch = np.maximum(patch, m)
        edge = np.abs(m - blur(m, 1.2))
        lum -= edge * 0.9 * 0.12
    lum -= patch * 0.028
    # Querfuge des Asphaltfertigers
    seam = np.exp(-(((ys - n * 0.5) / 1.4) ** 2)) * 0.5
    lum -= seam * 0.10
    # Risse
    cracks = np.zeros((n, n))
    for _ in range(6):
        cracks = np.maximum(cracks, draw_wrapped(np.zeros((n, n)), random_walk(rng, rng.uniform(0, n, 2), rng.uniform(0, 6.28), rng.uniform(150, 500), 2.0, 0.28), 1, rng.uniform(0.6, 1.0)))
    cracks = blur(cracks, 0.8)
    lum -= cracks * 0.20
    oil = blobs(n, rng, 6, 18, 60, seed + 4)
    lum -= oil * 0.07
    rgb = np.stack([lum * 1.01, lum, lum * 0.985], -1)
    color = to_img(rgb)
    hgt = lum_g * 1.5 - seam * 1.0 - cracks * 1.0 - edge * 0.5
    nm = normal_from_height(hgt, 1.6)
    nm = nm * 0.5 + ngrain * 0.5
    nm /= np.linalg.norm(nm * 2 - 1, axis=-1, keepdims=True).clip(1e-6) * 0 + 1
    nrm = to_img(np.clip(nm, 0, 1))
    return color, nrm


# ---------------------------------------------------------------- Verschleiß (Kachel 8 m): dunkler, ölig, Reifenabrieb, Rost
def make_verschleiss(n=1024, seed=31):
    rng = np.random.default_rng(seed)
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float64)
    grain = load_art("Asphalt031", "Color").mean(-1)
    grain = np.tile(np.asarray(Image.fromarray((grain * 255).astype(np.uint8)).resize((n // 2, n // 2), Image.LANCZOS)).astype(np.float64) / 255.0, (2, 2))
    grain = grain - blur(grain, 25)
    lum = 0.205 + grain * 0.5 + 0.03 * tile_noise(n, 2.2, seed + 1) + 0.02 * tile_noise(n, 1.4, seed + 2)
    # Reifenabrieb: lange dunkle Schlieren in Fahrtrichtung (x), unregelmäßig
    streak = tile_noise(n, 0.0, seed + 3, shape=(n, n))
    streak = ndi.gaussian_filter(streak, (1.2, 40), mode="wrap")
    streak = (streak - streak.mean()) / streak.std()
    lum -= smooth(streak, 0.4, 2.2) * 0.07
    # Öl: dunkle, leicht glänzende Flecken mit Rand
    oil = blobs(n, rng, 9, 22, 90, seed + 4)
    oil_ring = blur(oil, 3.0) - blur(oil, 7.0)
    lum -= oil * 0.075
    lum += np.clip(oil_ring, 0, None) * 0.10
    # Rost- und Staubflecken
    rust = blobs(n, rng, 8, 10, 40, seed + 5) * smooth(tile_noise(n, 1.0, seed + 6), -0.3, 1.0)
    # Kiesel und Splitt
    grit = np.zeros((n, n))
    pts = rng.uniform(0, n, (3500, 2)).astype(int)
    grit[pts[:, 1] % n, pts[:, 0] % n] = rng.uniform(0.3, 1.0, 3500)
    grit = blur(grit, 1.1)
    lum += grit * 5.0 * 0.05
    cracks = np.zeros((n, n))
    for _ in range(5):
        cracks = np.maximum(cracks, draw_wrapped(np.zeros((n, n)), random_walk(rng, rng.uniform(0, n, 2), rng.uniform(0, 6.28), rng.uniform(100, 380), 2.0, 0.3), 1, rng.uniform(0.6, 1.0)))
    cracks = blur(cracks, 0.8)
    lum -= cracks * 0.15
    rgb = np.stack([lum + rust * 0.07, lum + rust * 0.025, lum * 0.97 - rust * 0.01], -1)
    color = to_img(rgb)
    hgt = grain * 1.6 + grit * 3.0 - cracks * 1.0 - oil * 0.2
    normal = to_img(normal_from_height(hgt, 1.8))
    return color, normal


# ---------------------------------------------------------------- Container (Seitenwand, Stirnseite mit Türen, Dach)
def rib_profile(coord, ribs):
    """Sinusähnliches Rippenprofil (0 Tal .. 1 Rücken) für die Koordinate coord in [0,1) mit ribs Rippen."""
    return 0.5 - 0.5 * np.cos(2 * math.pi * coord * ribs)


def make_container_seite(n=1024, seed=41):
    """Seitenwand eines 40-Fuß-Containers als Atlas aus vier Varianten übereinander (1024 x 1024, jede Variante 1024 x 256 für 2 m x 2,59 m;
    u wiederholt sich je 2 m, die Variante wählt harbor.py über v = k/4 ... (k+1)/4). Wellblech mit Längsholm oben und Sockelholm unten,
    Rostfahnen, Beulen, Ausbesserungsflächen; die Farbe kommt über die Vertexfarbe (Textur ist hell grau mit rostbrauner Tönung der Schäden).
    Varianten: 0 sauber mit leichtem Schmutz, 1 Rostfahnen vom oberen Holm, 2 ausgeblichen mit überlackierter Fläche, 3 stark verbraucht."""
    H, W = 256, n
    out_c = Image.new("RGB", (W, H * 4))
    out_n = Image.new("RGB", (W, H * 4))
    for variant in range(4):
        sd = seed + 17 * variant
        rng = np.random.default_rng(sd)
        ys, xs = np.mgrid[0:H, 0:W].astype(np.float64)
        u, v = xs / W, 1.0 - ys / H                         # v: 0 unten, 1 oben
        ribs = 26                                           # 2 m / 26 = 7,7 cm
        prof = rib_profile(u, ribs)
        top = smooth(v, 0.945, 0.96)
        bot = 1.0 - smooth(v, 0.05, 0.065)
        flat_band = np.maximum(top, bot)
        h = prof * (1.0 - flat_band) * 0.9 + flat_band * 0.55
        lum = 0.88 - 0.20 * (1.0 - prof) * (1.0 - flat_band) + 0.03 * np.sin(2 * math.pi * (u * ribs - 0.12)) * (1.0 - flat_band)
        # Schlieren (senkrecht, Regenwasser) und Sockelschmutz
        streak = ndi.gaussian_filter(tile_noise(0, 0.0, sd + 1, (H, W)), (14, 1.4), mode="wrap")
        streak = (streak - streak.mean()) / streak.std()
        amount = (0.08, 0.12, 0.09, 0.16)[variant]
        lum -= smooth(streak, 0.3, 2.0) * amount * (1.0 - v * 0.6)
        lum -= (1.0 - smooth(v, 0.0, 0.22)) * (0.07 + 0.03 * variant) * (0.5 + 0.5 * np.clip(tile_noise(0, 1.0, sd + 2, (H, W)), -1, 1))
        lum += 0.025 * tile_noise(0, 0.5, sd + 3, (H, W))
        # Beulen
        dents = np.zeros((H, W))
        for _ in range((3, 4, 6, 10)[variant]):
            cx, cy = rng.uniform(0, W), rng.uniform(H * 0.2, H * 0.8)
            r = rng.uniform(16, 60)
            dx = np.minimum(np.abs(xs - cx), W - np.abs(xs - cx))
            d = np.hypot(dx, (ys - cy) * 1.6) / r
            dents = np.maximum(dents, np.clip(1.0 - d, 0, 1) ** 1.6 * rng.uniform(0.4, 1.0))
        lum -= dents * 0.045
        h = h - dents * 0.6
        # Rost: Fahnen vom oberen Holm (Variante 1, 3), Flecken am Sockel (alle, stärker in 3), Steinschläge
        rust = np.zeros((H, W))
        n_drips = (0, 14, 3, 9)[variant]
        for _ in range(n_drips):
            cx = rng.uniform(0, W)
            ln = rng.uniform(0.2, 0.7) * H
            wd = rng.uniform(3, 10)
            dx = np.minimum(np.abs(xs - cx), W - np.abs(xs - cx))
            fall = np.clip((1.0 - v - 0.04) / max(ln / H, 1e-3), 0, 1)
            m = np.clip(1.0 - dx / (wd * (0.5 + 0.7 * (1 - fall))), 0, 1) * (1.0 - fall) ** 0.7 * (fall < 1.0) * (v < 0.96)
            rust = np.maximum(rust, m * rng.uniform(0.35, 0.9))
        base_rust = smooth(tile_noise(0, 1.2, sd + 4, (H, W)), 0.5, 1.6) * (1.0 - smooth(v, 0.0, (0.22, 0.35, 0.2, 0.55)[variant]))
        rust = np.maximum(rust, base_rust * (0.45, 0.7, 0.4, 1.0)[variant])
        chips = np.zeros((H, W))
        pts = rng.uniform(0, 1, (50 + 50 * variant, 2)) * (W, H)
        chips[pts[:, 1].astype(int) % H, pts[:, 0].astype(int) % W] = 1.0
        chips = np.clip(blur(chips, 2.0) * 22.0, 0, 1)
        rust = np.clip(np.maximum(rust, chips * 0.9), 0, 1)
        lum -= rust * 0.34
        # überlackierte Fläche (Variante 2): Rechteck mit leicht anderem Ton und scharfer Kante, Ausbleichen nach oben
        if variant == 2:
            pu0 = rng.uniform(0.1, 0.4)
            pu1 = pu0 + rng.uniform(0.25, 0.45)
            patch = ((u > pu0) & (u < pu1) & (v > 0.12) & (v < 0.88)).astype(np.float64)
            lum += patch * 0.05
            lum += smooth(v, 0.4, 1.0) * 0.05
            h += patch * 0.15
        # Schablone (Variante 3): Nummernblock, nur Abdunklung
        if variant == 3:
            img = Image.new("L", (W, H), 0)
            d_ = ImageDraw.Draw(img)
            try:
                fnt = ImageFont.truetype(FONT, 64)
            except OSError:
                fnt = ImageFont.load_default()
            d_.text((int(W * 0.50), int(H * 0.22)), "HRB 4417", font=fnt, fill=255)
            txt = np.asarray(img).astype(np.float64) / 255.0
            lum *= 1.0 - txt * 0.42
        # Farbe: Grau mit rostbrauner Tönung der Schäden
        tint = rust * 1.1
        rgb = np.stack([lum + tint * 0.20, lum - tint * 0.02, lum - tint * 0.16], -1)
        out_c.paste(to_img(rgb), (0, (3 - variant) * H))
        out_n.paste(to_img(normal_from_height(h * 2.8, 3.2)), (0, (3 - variant) * H))
    return out_c, out_n


def make_container_tuer(n=512, seed=42):
    """Stirnseite mit Türen (2,44 x 2,59 m): links Variante A (dunkle Schrift), rechts Variante B (helle Schrift); Atlas 1024 x 512."""
    out_c = Image.new("RGB", (n * 2, n))
    out_n = Image.new("RGB", (n * 2, n))
    for variant in (0, 1):
        rng = np.random.default_rng(seed + variant)
        ys, xs = np.mgrid[0:n, 0:n].astype(np.float64)
        u, v = xs / n, 1.0 - ys / n
        lum = np.full((n, n), 0.86 if variant == 0 else 0.74)
        h = np.zeros((n, n))
        post = (u < 0.06) | (u > 0.94) | (v < 0.05) | (v > 0.95)
        lum[post] *= 0.96
        h[post] = 0.7
        seam = np.abs(u - 0.5) < 0.006
        lum[seam] *= 0.25
        h[seam] = -1.0
        for hx in (0.10, 0.90):
            for hv in (0.14, 0.50, 0.86):
                m = (np.abs(u - hx) < 0.012) & (np.abs(v - hv) < 0.035)
                lum[m] *= 0.45
                h[m] = 0.5
        for rod in (0.20, 0.34, 0.66, 0.80):
            m = (np.abs(u - rod) < 0.010) & (v > 0.07) & (v < 0.93)
            lum[m] *= 0.62
            h[m] = 0.9
            for cv in (0.17, 0.50, 0.83):
                mm = (np.abs(u - rod) < 0.028) & (np.abs(v - cv) < 0.018)
                lum[mm] *= 0.7
                h[mm] = 1.1
        ribs = 0.5 - 0.5 * np.cos(2 * math.pi * v * 17)
        door = (u > 0.07) & (u < 0.93) & (v > 0.06) & (v < 0.94)
        lum[door] *= 0.93 + 0.07 * ribs[door]
        h[door] += ribs[door] * 0.25
        img = Image.new("L", (n, n), 0)
        d = ImageDraw.Draw(img)
        try:
            fnt = ImageFont.truetype(FONT, int(n * 0.050))
            fnt2 = ImageFont.truetype(FONT, int(n * 0.034))
        except OSError:
            fnt = fnt2 = ImageFont.load_default()
        owner = "DRWU" if variant == 0 else "HBRU"
        d.text((int(n * 0.54), int(n * 0.12)), owner, font=fnt, fill=255)
        d.text((int(n * 0.54), int(n * 0.18)), "%06d 7" % rng.integers(100000, 999999), font=fnt, fill=255)
        d.text((int(n * 0.54), int(n * 0.24)), "22G1", font=fnt2, fill=255)
        txt = np.asarray(img).astype(np.float64) / 255.0
        if variant == 0:
            lum = lum * (1 - txt * 0.78)
        else:
            lum = lum * (1 - txt) + txt * 0.98
        plate = (u > 0.60) & (u < 0.78) & (v > 0.34) & (v < 0.40)
        lum[plate] = 0.45
        lum -= (1.0 - smooth(v, 0.0, 0.25)) * 0.08
        lum += 0.025 * tile_noise(n, 0.5, seed + 9 + variant)
        dirt = ndi.gaussian_filter(tile_noise(n, 0.0, seed + 11), (30, 1.2), mode="wrap")
        lum -= smooth((dirt - dirt.mean()) / dirt.std(), 0.3, 1.5) * 0.04
        rgb = np.stack([lum, lum, lum], -1)
        out_c.paste(to_img(rgb), (variant * n, 0))
        out_n.paste(to_img(normal_from_height(h, 2.4)), (variant * n, 0))
    return out_c, out_n


def make_container_dach(n=512, seed=43):
    """Dach (2 x 2 m, wiederholt): Rippen quer zur Containerlänge, Rost und Schlieren."""
    rng = np.random.default_rng(seed)
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float64)
    v = ys / n
    ribs = 13
    prof = rib_profile(v, ribs)
    lum = 0.80 - 0.15 * (1.0 - prof) + 0.04 * tile_noise(n, 1.4, seed + 1) + 0.02 * tile_noise(n, 0.5, seed + 2)
    rust = blobs(n, rng, 16, 8, 38, seed + 3) * smooth(tile_noise(n, 1.0, seed + 4), -0.3, 1.0)
    streak = ndi.gaussian_filter(tile_noise(n, 0.0, seed + 5), (1.2, 30), mode="wrap")
    streak = (streak - streak.mean()) / streak.std()
    lum -= smooth(streak, 0.3, 2.0) * 0.07
    lum -= rust * 0.12
    rgb = np.stack([lum + rust * 0.07, lum, lum - rust * 0.07], -1)
    return to_img(rgb), to_img(normal_from_height(prof * 1.7 + tile_noise(n, 0.5, seed + 2) * 0.1, 3.0))


# ---------------------------------------------------------------- Wellblech für Hallen (Wand und Dach)
def make_blech_wand(n=512, seed=51):
    """Trapezblech senkrecht (2 x 2 m, Rippenabstand 20 cm) mit Schraubenreihen, Stoßfuge, Regenschlieren."""
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float64)
    u, v = xs / n, 1.0 - ys / n
    ribs = 10
    ph = (u * ribs) % 1.0
    prof = np.where((ph > 0.30) & (ph < 0.70), 1.0, np.where(ph <= 0.30, np.clip((ph - 0.05) / 0.25, 0, 1), np.clip((0.95 - ph) / 0.25, 0, 1)))
    lum = 0.80 - 0.22 * (1.0 - prof) + 0.03 * (np.where(ph < 0.5, 1.0, -1.0)) * (1.0 - prof)
    lum += 0.03 * tile_noise(n, 0.4, seed + 1)
    streak = ndi.gaussian_filter(tile_noise(n, 0.0, seed + 2), (28, 1.0), mode="wrap")
    streak = (streak - streak.mean()) / streak.std()
    lum -= smooth(streak, 0.3, 2.0) * 0.09 * (1.0 - v * 0.5)
    lum -= (1.0 - smooth(v, 0.0, 0.18)) * 0.07
    for row in (0.12, 0.62):
        for col in np.arange(0.5 / ribs, 1.0, 1.0 / ribs):
            m = np.hypot((u - col) * n, (v - row) * n) < 2.4
            lum[m] *= 0.55
    fuge = np.exp(-(((v - 0.5) * n) / 1.2) ** 2)
    lum -= fuge * 0.16
    rgb = np.stack([lum, lum, lum * 1.01], -1)
    return to_img(rgb), to_img(normal_from_height(prof * 2.0 - fuge, 3.4))


def make_blech_dach(n=512, seed=52):
    """Stehfalzdach (2 x 2 m, Bahnen zu 50 cm)."""
    rng = np.random.default_rng(seed)
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float64)
    u = xs / n
    pans = 4
    ph = (u * pans) % 1.0
    seam = np.exp(-((np.minimum(ph, 1 - ph) * n / pans) / 2.2) ** 2)
    ribs = rib_profile(ph * 3, 1)
    lum = 0.74 + 0.03 * ribs - 0.12 * seam
    lum += 0.03 * tile_noise(n, 0.4, seed + 1) + 0.04 * tile_noise(n, 1.8, seed + 2)
    streak = ndi.gaussian_filter(tile_noise(n, 0.0, seed + 3), (1.0, 26), mode="wrap")
    lum -= smooth((streak - streak.mean()) / streak.std(), 0.3, 2.0) * 0.06
    rust = blobs(n, rng, 10, 8, 30, seed + 4) * smooth(tile_noise(n, 1.0, seed + 5), -0.3, 1.0)
    lum -= rust * 0.10
    rgb = np.stack([lum + rust * 0.05, lum, lum - rust * 0.04], -1)
    return to_img(rgb), to_img(normal_from_height(seam * -1.2 + ribs * 0.4, 3.0))


# ---------------------------------------------------------------- Fahrzeuglack (verwittert, wird mit der Vertexfarbe des Fahrzeugs multipliziert)
def make_lack(n=512, seed=91):
    """Verwitterter Lack für Lkw, Lokomotive, Wagen, Stapler, Schlepper: Multiplikator zur Vertexfarbe (Mittel sRGB 0,91 = linear 0,8 wie der frühere
    Einheitslack). Senkrechte Regenschlieren, Staubsaum unten, stellenweise ausgebleichte (hellere) Flächen, kleine Rostpunkte und -läufer, feine Kratzer."""
    rng = np.random.default_rng(seed)
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float64)
    v = 1.0 - ys / n
    lum = 0.91 + 0.02 * tile_noise(n, 2.2, seed + 1) + 0.012 * tile_noise(n, 0.4, seed + 2)
    streak = ndi.gaussian_filter(tile_noise(n, 0.0, seed + 3), (24, 0.9), mode="wrap")
    streak = (streak - streak.mean()) / streak.std()
    lum -= smooth(streak, 0.5, 2.4) * 0.13
    lum -= (1.0 - smooth(v, 0.0, 0.2)) * 0.07
    lum += smooth(tile_noise(n, 2.8, seed + 4), 0.3, 1.5) * 0.05
    scratch = ndi.gaussian_filter(tile_noise(n, 0.0, seed + 6), (0.8, 7.0), mode="wrap")
    lum -= smooth((scratch - scratch.mean()) / scratch.std(), 1.5, 3.2) * 0.05
    spots = blobs(n, rng, 26, 1.5, 5.0, seed + 5) * smooth(tile_noise(n, 0.7, seed + 7), 0.0, 1.0)
    runs = ndi.gaussian_filter(spots, (14, 0.8), mode="wrap") * 2.2                       # Rostläufer nach unten
    low = blobs(n, rng, 12, 3, 10, seed + 8) * (1.0 - smooth(v, 0.0, 0.3)) * smooth(tile_noise(n, 0.9, seed + 9), -0.2, 0.9)       # Rost am unteren Rand
    rust = np.clip(spots + runs * 0.5 + low * 0.9, 0.0, 1.0)
    rgb = np.stack([lum * (1.0 - 0.04 * rust), lum * (1.0 - 0.20 * rust), lum * (1.0 - 0.46 * rust)], -1)
    return to_img(rgb), None


# ---------------------------------------------------------------- Lehm, Gewebeplane
def make_lehm(n=512, seed=61):
    rng = np.random.default_rng(seed)
    lum = 0.30 + 0.07 * tile_noise(n, 2.2, seed + 1) + 0.04 * tile_noise(n, 1.0, seed + 2) + 0.025 * tile_noise(n, 0.3, seed + 3)
    clods = blobs(n, rng, 70, 4, 14, seed + 4)
    lum += clods * 0.06 * tile_noise(n, 0.8, seed + 5)
    stones = np.zeros((n, n))
    pts = rng.uniform(0, n, (260, 2)).astype(int)
    stones[pts[:, 1] % n, pts[:, 0] % n] = rng.uniform(0.4, 1.0, 260)
    stones = blur(stones, 1.6) * 6.0
    rgb = np.stack([lum * 1.16 + stones * 0.09, lum * 0.98 + stones * 0.08, lum * 0.78 + stones * 0.07], -1)
    return to_img(rgb), to_img(normal_from_height(clods * 1.4 + stones * 1.5 + tile_noise(n, 0.5, seed + 3) * 0.2, 2.4))


def make_planen(n=256, seed=71):
    """Bauzaun-Blende / Gewebeplane: feines Gewebe, helle Grundfarbe (Farbe über Vertexfarbe), Ösen."""
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float64)
    weave = 0.5 + 0.25 * np.sin(xs * 2 * math.pi / 4.0) * np.sin(ys * 2 * math.pi / 4.0)
    lum = 0.80 + 0.06 * weave + 0.03 * tile_noise(n, 1.6, seed)
    for gy in (0.08, 0.92):
        m = np.hypot(xs - n * 0.5, ys - n * gy) < 5.0
        lum[m] *= 0.45
    rgb = np.stack([lum, lum, lum], -1)
    return to_img(rgb), to_img(normal_from_height(weave, 1.0))


def make_schotter(n=512, seed=81):
    """Gleisschotter (2 x 2 m): eckige graue Steine, dunkle Fugen."""
    rng = np.random.default_rng(seed)
    lum = 0.34 + 0.05 * tile_noise(n, 1.2, seed + 1)
    stones = np.zeros((n, n))
    for _ in range(2600):
        cx, cy = rng.uniform(0, n, 2)
        r = rng.uniform(3, 9)
        tone = rng.uniform(-0.12, 0.16)
        ys, xs = np.ogrid[int(cy) - 10:int(cy) + 11, int(cx) - 10:int(cx) + 11]
        m = (np.hypot(xs - cx, ys - cy) < r)
        yy, xx = np.nonzero(m)
        stones[(yy + int(cy) - 10) % n, (xx + int(cx) - 10) % n] = tone + 0.5
    lum = lum + (stones - 0.25) * 0.5 * (stones > 0)
    lum = ndi.gaussian_filter(lum, 0.7, mode="wrap") + 0.04 * tile_noise(n, 0.3, seed + 2)
    rgb = np.stack([lum, lum * 0.99, lum * 0.96], -1)
    return to_img(rgb), to_img(normal_from_height(lum * 3.0, 2.5))


# ---------------------------------------------------------------- Ausgabe
def make_ground():
    for name, fn in (("beton", make_beton), ("asphalt", make_asphalt), ("verschleiss", make_verschleiss)):
        color, normal = fn()
        save(color, OUT, name + ".jpg")
        save(normal, OUT, name + "_n.jpg")


def make_src():
    for name, fn in (("container_seite", make_container_seite), ("container_tuer", make_container_tuer), ("container_dach", make_container_dach),
                     ("blech_wand", make_blech_wand), ("blech_dach", make_blech_dach), ("lehm", make_lehm), ("planen", make_planen), ("schotter", make_schotter),
                     ("lack", make_lack), ("riffelblech", make_riffelblech)):
        color, normal = fn()
        save(color, SRC, name + ".png")
        if normal is not None:
            save(normal, SRC, name + "_n.png")


def make_lack_only():
    color, _ = make_lack()
    save(color, SRC, "lack.png")


# ---------------------------------------------------------------- Riffelblech (Stahldeck der Containerterrasse, Fassung 2 von Harbour Run)
def make_riffelblech(n=512, seed=95):
    """Tränenblech (1 x 1 m, Raster 2,9 cm): linsenförmige Warzen abwechselnd quer und längs, Laufspuren blank gescheuert, Kratzer, leichter Rost
    in den Mulden. Neutralgrau; Farbe kommt aus der Vertexfarbe."""
    rng = np.random.default_rng(seed)
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float64)
    cells = 34
    cu, cv = (xs / n * cells) % 1.0, (ys / n * cells) % 1.0
    iu, iv = np.floor(xs / n * cells).astype(int), np.floor(ys / n * cells).astype(int)
    alt = (iu + iv) % 2 == 0
    du, dv = cu - 0.5, cv - 0.5
    a = np.where(alt, du, dv)
    b = np.where(alt, dv, du)
    lens = np.clip(1.0 - (a / 0.36) ** 2 - (b / 0.10) ** 2, 0.0, 1.0) ** 0.6
    wear = smooth(tile_noise(n, 2.2, seed + 1), -0.2, 1.4)
    lum = 0.50 + 0.10 * lens * (1.0 - 0.6 * wear) + 0.10 * wear
    lum += 0.03 * tile_noise(n, 0.6, seed + 2)
    scratch = np.zeros((n, n))
    for _ in range(60):
        x0, y0 = rng.uniform(0, n, 2)
        ang = rng.uniform(-0.35, 0.35) + (0.0 if rng.random() < 0.7 else math.pi / 2)
        ln = rng.uniform(30, 160)
        pts = [(x0 + math.cos(ang) * t, y0 + math.sin(ang) * t) for t in np.linspace(0, ln, 24)]
        draw_wrapped(scratch, pts, 1, 1.0)
    scratch = blur(scratch, 0.6)
    lum += np.clip(scratch, 0, 1) * 0.16
    rust = smooth(tile_noise(n, 1.2, seed + 3), 0.8, 2.0) * (1.0 - lens)
    lum -= rust * 0.10
    rgb = np.stack([lum + rust * 0.08, lum + rust * 0.01, lum * 1.02 - rust * 0.05], -1)
    return to_img(rgb), to_img(normal_from_height(lens * 1.2, 2.6))


def make_riffel_only():
    color, normal = make_riffelblech()
    save(color, SRC, "riffelblech.png")
    save(normal, SRC, "riffelblech_n.png")


TASKS = {"boden": make_ground, "src": make_src, "lack": make_lack_only, "riffel": make_riffel_only}

if __name__ == "__main__":
    names = sys.argv[1:] or list(TASKS)
    os.makedirs(SRC, exist_ok=True)
    gd = os.path.join(SRC, ".gdignore")
    if not os.path.exists(gd):
        open(gd, "w").close()
    for nm in names:
        print(nm)
        TASKS[nm]()
