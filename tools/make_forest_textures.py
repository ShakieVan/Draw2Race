"""Erzeugt die Bodentexturen des Wald-Dioramas (Thema "forest"): alles prozedural (numpy, scipy, Pillow), kein fremdes Material.

Ergebnis in game/assets/dio/forest/ (Mischung des Boden-Shaders, assets/ground_blend.gdshader; Normalkarte = Name + _n):
  boden_wald(.jpg|_n.jpg)      Waldboden: Moos, Humus, Laub, Gras, kleine Zweige und Steinchen        (Platz "grass")
  boden_nadeln(.jpg|_n.jpg)    Nadelstreu unter Kiefern: Nadelpaare, Zapfen, Zweige                    (Platz "sand")
  boden_erde(.jpg|_n.jpg)      Wegerde: festgefahrene Erde mit Schotter, Laub, Nadeln, feuchten Flecken (Platz "dirt", Saum der Piste)
  quelle/matsch.jpg            Schlamm und feuchte Erde für die Schlammflächen und Uferstreifen (Blender-Material F_Matsch, früher Platz "dirt")
  quelle/spur.jpg              dunklere, trockene Wegerde für die Radspuren im Saum (Blender-Material F_Spur)
und für Blender (liegen in quelle/, dort ignoriert Godot den Ordner per .gdignore):
  quelle/rinde.jpg, quelle/holz.jpg, quelle/schindel.jpg, quelle/dach_alt.jpg, quelle/laub.jpg   Texturen für gebaute Teile (Blender-Materialien)
Alle Kacheln sind nahtlos (Rauschen im Frequenzraum, Formen mit Umbruch an den Rändern).
Aufruf: python tools/make_forest_textures.py [ausgabeordner] [--sheet kontaktbogen.png]
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage as ndi

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET = sys.argv[sys.argv.index("--sheet") + 1] if "--sheet" in sys.argv else None
_args = [a for i, a in enumerate(sys.argv[1:], 1) if not a.startswith("--") and not (i > 1 and sys.argv[i - 1] == "--sheet")]
OUT = _args[0] if _args else os.path.join(ROOT, "game", "assets", "dio", "forest")
SRC = os.path.join(OUT, "quelle")
os.makedirs(SRC, exist_ok=True)
with open(os.path.join(SRC, ".gdignore"), "w") as _fh:
    _fh.write("")
N = 1024


def pink(beta, seed, n=N):
    """Nahtloses Rauschen mit Spektrum 1/f^beta (Standardabweichung 1)."""
    r = np.random.default_rng(seed)
    fy = np.fft.fftfreq(n)[:, None]
    fx = np.fft.fftfreq(n)[None, :]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    amp = f ** (-beta / 2.0)
    amp[0, 0] = 0.0
    spec = (r.standard_normal((n, n)) + 1j * r.standard_normal((n, n))) * amp
    out = np.real(np.fft.ifft2(spec))
    return (out / (out.std() + 1e-9)).astype(np.float32)


def smooth(a, lo, hi):
    t = np.clip((a - lo) / (hi - lo), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def mixc(a, b, t):
    return a * (1 - t[..., None]) + b * t[..., None]


class Layer:
    """Zeichenfläche (RGB + Höhe) mit Umbruch an den Rändern; Formen in Pixeln."""

    def __init__(self, rgb):
        self.img = Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")
        self.hgt = Image.new("F", (N, N), 0.0)
        self.d = ImageDraw.Draw(self.img)
        self.h = ImageDraw.Draw(self.hgt)

    def poly(self, pts, color, height=None):
        for dx in (-N, 0, N):
            for dy in (-N, 0, N):
                if min(p[0] for p in pts) + dx > N or max(p[0] for p in pts) + dx < 0:
                    continue
                if min(p[1] for p in pts) + dy > N or max(p[1] for p in pts) + dy < 0:
                    continue
                q = [(x + dx, y + dy) for x, y in pts]
                self.d.polygon(q, fill=tuple(int(c * 255) for c in color))
                if height is not None:
                    self.h.polygon(q, fill=height)

    def line(self, p0, p1, color, width=1, height=None):
        for dx in (-N, 0, N):
            for dy in (-N, 0, N):
                if max(p0[0], p1[0]) + dx < 0 or min(p0[0], p1[0]) + dx > N or max(p0[1], p1[1]) + dy < 0 or min(p0[1], p1[1]) + dy > N:
                    continue
                a, b = (p0[0] + dx, p0[1] + dy), (p1[0] + dx, p1[1] + dy)
                self.d.line([a, b], fill=tuple(int(c * 255) for c in color), width=width)
                if height is not None:
                    self.h.line([a, b], fill=height, width=width)

    def ellipse(self, cx, cy, rx, ry, rot, color, height=None, n=14):
        pts = []
        for k in range(n):
            t = 2 * math.pi * k / n
            x, y = rx * math.cos(t), ry * math.sin(t)
            pts.append((cx + x * math.cos(rot) - y * math.sin(rot), cy + x * math.sin(rot) + y * math.cos(rot)))
        self.poly(pts, color, height)

    def result(self):
        return np.asarray(self.img, np.float32) / 255.0, np.asarray(self.hgt, np.float32)


def leaf_pts(cx, cy, length, width, rot):
    """Laubblatt (Spitzoval) als Polygon."""
    pts = []
    for k in range(-5, 6):
        t = k / 5.0
        w = width * 0.5 * (1 - t * t) ** 0.8
        pts.append((t * length * 0.5, w))
    pts += [(-p[0], -p[1]) for p in pts[::-1]]
    c, s = math.cos(rot), math.sin(rot)
    return [(cx + x * c - y * s, cy + x * s + y * c) for x, y in pts]


def jitter(rng, col, amt):
    v = rng.uniform(-amt, amt)
    return tuple(min(1.0, max(0.0, c * (1 + v))) for c in col)


def save(name, rgb, height, strength, out=OUT, quality=92):
    """Albedo und Normalkarte (OpenGL, Y nach oben) schreiben."""
    height = ndi.gaussian_filter(height, 0.7, mode="wrap")
    gy, gx = np.gradient(height)
    nx, ny, nz = -gx * strength, gy * strength, np.ones_like(height)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    normal = np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5
    Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(out, name + ".jpg"), quality=quality)
    if strength > 0:
        Image.fromarray((normal * 255 + 0.5).astype(np.uint8)).save(os.path.join(out, name + "_n.jpg"), quality=quality)
    return rgb


# ------------------------------------------------------------------------------------------------ Waldboden
def boden_wald():
    rng = np.random.default_rng(101)
    n1, n2, n3, n4 = pink(2.8, 1), pink(2.2, 2), pink(1.4, 3), pink(0.8, 4)
    moss_m = smooth(n1 * 0.7 + n2 * 0.5, -0.5, 0.8)                      # Moosflecken
    grass_m = smooth(n2 * 0.6 - n1 * 0.3 + 0.1, 0.0, 0.8)                # grasige Stellen
    humus = np.array([0.13, 0.10, 0.065])
    soil = np.array([0.24, 0.18, 0.11])
    moss = np.array([0.13, 0.245, 0.075])
    moss2 = np.array([0.21, 0.34, 0.11])
    grass = np.array([0.18, 0.29, 0.085])
    base = mixc(humus, soil, smooth(n2 + 0.4 * n3, -0.4, 0.9))
    base = mixc(base, moss, moss_m * 0.85)
    base = mixc(base, moss2, moss_m * smooth(n3 * 0.7 + n4 * 0.4, 0.2, 1.1) * 0.9)
    base = mixc(base, grass, grass_m * 0.55)
    base *= (1.0 + 0.10 * n3 + 0.12 * n4)[..., None]
    ly = Layer(base)
    # Grashalme (kurze Striche), nur in den grasigen Bereichen
    for _ in range(9000):
        x, y = rng.uniform(0, N, 2)
        if grass_m[int(y) % N, int(x) % N] < 0.35 and rng.random() < 0.9:
            continue
        a = rng.uniform(-0.6, 0.6) + math.pi / 2 + rng.choice([0, math.pi])
        ln = rng.uniform(7, 22)
        col = jitter(rng, (0.22, 0.40, 0.09) if rng.random() < 0.7 else (0.34, 0.46, 0.14), 0.25)
        ly.line((x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln), col, 1, 1.5)
    # Laubstreu: gefallene Blätter, braun bis orange, mit Mittelrippe
    palette = [(0.34, 0.20, 0.08), (0.50, 0.28, 0.09), (0.44, 0.36, 0.13), (0.22, 0.14, 0.07), (0.58, 0.40, 0.12), (0.30, 0.22, 0.10)]
    for _ in range(950):
        x, y = rng.uniform(0, N, 2)
        ln = rng.uniform(13, 30)
        col = jitter(rng, palette[rng.integers(len(palette))], 0.18)
        rot = rng.uniform(0, 2 * math.pi)
        ly.poly(leaf_pts(x, y, ln, ln * rng.uniform(0.38, 0.6), rot), col, rng.uniform(2.0, 4.5))
        ly.line((x - math.cos(rot) * ln * 0.45, y - math.sin(rot) * ln * 0.45), (x + math.cos(rot) * ln * 0.45, y + math.sin(rot) * ln * 0.45),
                tuple(c * 0.6 for c in col), 1)
    # Zweige
    for _ in range(150):
        x, y = rng.uniform(0, N, 2)
        a = rng.uniform(0, 2 * math.pi)
        ln = rng.uniform(25, 110)
        col = jitter(rng, (0.20, 0.14, 0.09), 0.25)
        w = int(rng.integers(1, 4))
        ly.line((x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln), col, w, 3.0 + w)
        if rng.random() < 0.5:
            bx, by = x + math.cos(a) * ln * 0.5, y + math.sin(a) * ln * 0.5
            ly.line((bx, by), (bx + math.cos(a + 0.7) * ln * 0.3, by + math.sin(a + 0.7) * ln * 0.3), col, 1, 2.5)
    # Steinchen
    for _ in range(90):
        x, y = rng.uniform(0, N, 2)
        r = rng.uniform(3, 9)
        g = rng.uniform(0.32, 0.55)
        ly.ellipse(x, y, r, r * rng.uniform(0.6, 0.95), rng.uniform(0, 3), (g, g * 0.98, g * 0.92), 6.0 + r * 0.4)
    # Eicheln und Zapfen-Schuppen, vereinzelt
    for _ in range(36):
        x, y = rng.uniform(0, N, 2)
        r = rng.uniform(4, 6)
        ly.ellipse(x, y, r * 1.5, r, rng.uniform(0, 3), (0.38, 0.24, 0.1), 5.0)
        ly.ellipse(x - r * 0.6, y, r * 0.6, r * 0.85, 0, (0.22, 0.14, 0.07), 6.0)
    rgb, hgt = ly.result()
    # Moos- und Humusrelief
    hgt = hgt + 1.2 * n4 + 0.8 * n3 * moss_m
    fine = (ndi.gaussian_filter(rgb.mean(2), 1.4, mode="wrap") - rgb.mean(2))                     # kleine Vertiefungen dunkler
    rgb = rgb * (1.0 + np.clip(fine * 1.3, -0.15, 0.1))[..., None]
    return save("boden_wald", rgb, hgt * 0.45, 2.6)


# ------------------------------------------------------------------------------------------------ Nadelstreu
def boden_nadeln():
    rng = np.random.default_rng(202)
    n1, n2, n3 = pink(2.4, 11), pink(1.6, 12), pink(1.0, 13)
    duff = np.array([0.16, 0.105, 0.065])
    rust = np.array([0.27, 0.17, 0.09])
    base = mixc(duff, rust, smooth(n1 + 0.5 * n2, -0.8, 1.0))
    base *= (1.0 + 0.12 * n2 + 0.1 * n3)[..., None]
    ly = Layer(base)
    palette = [(0.42, 0.26, 0.13), (0.50, 0.37, 0.21), (0.33, 0.20, 0.10), (0.26, 0.18, 0.09), (0.38, 0.30, 0.15), (0.46, 0.29, 0.14),
               (0.22, 0.24, 0.10)]
    # Zweige und Rindenstücke
    for _ in range(100):
        x, y = rng.uniform(0, N, 2)
        a = rng.uniform(0, 2 * math.pi)
        ln = rng.uniform(30, 120)
        col = jitter(rng, (0.24, 0.15, 0.09), 0.2)
        w = int(rng.integers(1, 4))
        ly.line((x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln), col, w, 3.0 + w)
    # Nadelpaare (Kiefer): zwei dicht nebeneinander liegende Striche
    for _ in range(26000):
        x, y = rng.uniform(0, N, 2)
        a = rng.uniform(0, math.pi)
        ln = rng.uniform(15, 30)
        col = jitter(rng, palette[rng.integers(len(palette))], 0.15)
        dx, dy = math.cos(a) * ln, math.sin(a) * ln
        ox, oy = -math.sin(a) * 1.5, math.cos(a) * 1.5
        ly.line((x, y), (x + dx, y + dy), col, 1, 1.2)
        ly.line((x + ox, y + oy), (x + dx + ox * 0.6, y + dy + oy * 0.6), jitter(rng, col, 0.1), 1, 1.2)
    # Zapfen
    for _ in range(11):
        x, y = rng.uniform(0, N, 2)
        a = rng.uniform(0, 2 * math.pi)
        L, Wd = rng.uniform(26, 36), rng.uniform(12, 17)
        ly.ellipse(x, y, L, Wd, a, (0.34, 0.20, 0.09), 9.0, 18)
        for k in range(7):                                                   # Schuppen
            t = -0.8 + k * 0.27
            px, py = x + math.cos(a) * L * t, y + math.sin(a) * L * t
            ly.ellipse(px, py, Wd * 0.45, Wd * 0.9, a, jitter(rng, (0.46, 0.28, 0.13), 0.12), 10.5, 10)
    # grünliche Moosreste
    for _ in range(140):
        x, y = rng.uniform(0, N, 2)
        r = rng.uniform(4, 11)
        ly.ellipse(x, y, r, r * 0.8, rng.uniform(0, 3), jitter(rng, (0.17, 0.27, 0.08), 0.2), 4.0, 9)
    rgb, hgt = ly.result()
    hgt = hgt + 0.8 * n3
    return save("boden_nadeln", rgb, hgt * 0.4, 2.2)


# ------------------------------------------------------------------------------------------------ Schlamm
def boden_schlamm(name="boden_schlamm", out=OUT, strength=2.0):
    """Schlamm und feuchte Erde mit Steinchen und Pflanzenresten. Seit 02.10.2026 nicht mehr im Boden-Shader, sondern als Blender-Material
    "F_Matsch" der Schlammflächen und Uferstreifen (Name "matsch", Ziel quelle/, ohne Normalkarte)."""
    rng = np.random.default_rng(303)
    n1, n2, n3, n4 = pink(2.8, 21), pink(2.0, 22), pink(1.2, 23), pink(0.7, 24)
    wet = np.array([0.095, 0.065, 0.04])
    dry = np.array([0.24, 0.17, 0.105])
    clay = np.array([0.30, 0.22, 0.14])
    base = mixc(wet, dry, smooth(n1 * 0.8 + n2 * 0.4, -0.7, 1.1))
    base = mixc(base, clay, smooth(n2 - n3 * 0.5, 0.6, 1.5) * 0.5)
    base *= (1.0 + 0.10 * n3 + 0.14 * n4)[..., None]
    ly = Layer(base)
    # Steinchen und Schotterkörner aus der Fahrbahn
    for _ in range(420):
        x, y = rng.uniform(0, N, 2)
        r = rng.uniform(2.0, 8.5)
        g = rng.uniform(0.22, 0.46)
        tint = (g * rng.uniform(0.95, 1.1), g * 0.93, g * rng.uniform(0.75, 0.9))
        ly.ellipse(x, y, r, r * rng.uniform(0.55, 0.95), rng.uniform(0, 3), tint, 5.0 + r * 0.5, 9)
        ly.ellipse(x - r * 0.25, y - r * 0.25, r * 0.5, r * 0.4, 0, tuple(min(1, c * 1.2) for c in tint), 5.4 + r * 0.5, 7)   # Lichtkante
    # Pflanzenreste, Blätter im Matsch
    for _ in range(130):
        x, y = rng.uniform(0, N, 2)
        ln = rng.uniform(12, 26)
        ly.poly(leaf_pts(x, y, ln, ln * 0.45, rng.uniform(0, 6.28)), jitter(rng, (0.19, 0.13, 0.065), 0.25), 2.0)
    # Halme am Rand (Gras, das aus dem Schlamm ragt)
    for _ in range(1100):
        x, y = rng.uniform(0, N, 2)
        a = rng.uniform(0, 2 * math.pi)
        ln = rng.uniform(6, 14)
        ly.line((x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln), jitter(rng, (0.18, 0.26, 0.08), 0.3), 1, 1.8)
    rgb, hgt = ly.result()
    # feuchter Glanz: Senken dunkler, Wülste heller
    ridge = n3 * 0.7 + n4 * 0.5
    hgt = hgt + 2.0 * ridge
    rgb = rgb * (1.0 + 0.10 * np.clip(ridge, -1, 1))[..., None]
    return save(name, rgb, hgt * 0.5, strength, out)


# ------------------------------------------------------------------------------------------------ Wegerde (Saum der Schotterpiste)
def boden_erde(name="boden_erde", out=OUT, strength=2.2, dark=1.0, wet_share=1.0):
    """Festgefahrene Erde mit Schotter, wie sie neben einer Waldpiste liegt (Platz "dirt", seit 02.10.2026 statt des Schlamms): hell getrocknete Stellen
    in der Farbe der Fahrbahn, mittlere Erde, dunkle feuchte Flecken; viele Kiesel, einige grobe Schottersteine, Laub, Nadeln und Wurzelfasern.
    Abwandlung "spur" (Radspuren im Saum, Material F_Spur): dunkler (dark < 1) und ohne feuchte Flecken (wet_share 0)."""
    rng = np.random.default_rng(404)
    n1, n2, n3, n4 = pink(2.6, 31), pink(1.9, 32), pink(1.2, 33), pink(0.7, 34)
    wet = np.array([0.15, 0.105, 0.065])
    mid = np.array([0.34, 0.26, 0.175])
    dry = np.array([0.47, 0.375, 0.265])
    dust = np.array([0.54, 0.45, 0.33])
    base = mixc(mid, dry, smooth(n1 * 0.8 + n2 * 0.5, -0.4, 1.2))
    base = mixc(base, dust, smooth(n2 - n3 * 0.4, 0.7, 1.7) * 0.55)
    base = mixc(base, wet, smooth(-n1 * 0.9 - n2 * 0.3 + 0.1, 0.35, 1.3) * 0.9 * wet_share)                 # feuchte, dunkle Flecken (rund ein Viertel)
    base *= (1.0 + 0.09 * n3 + 0.13 * n4)[..., None]
    ly = Layer(base)
    # feiner Schotter und Sand: viele kleine Körner in Grau, Beige, Ocker
    for _ in range(1500):
        x, y = rng.uniform(0, N, 2)
        r = rng.uniform(1.4, 4.5)
        g = rng.uniform(0.38, 0.72)
        tint = (g * rng.uniform(0.98, 1.08), g * rng.uniform(0.9, 0.98), g * rng.uniform(0.72, 0.9))
        ly.ellipse(x, y, r, r * rng.uniform(0.6, 0.95), rng.uniform(0, 3), tint, 4.0 + r * 0.5, 7)
    # grober Schotter (3 bis 8 cm): Körner mit heller Kante und dunklem Fuß
    for _ in range(230):
        x, y = rng.uniform(0, N, 2)
        r = rng.uniform(5.0, 15.0)
        g = rng.uniform(0.34, 0.66)
        tint = (g * rng.uniform(0.98, 1.08), g * rng.uniform(0.9, 0.97), g * rng.uniform(0.7, 0.88))
        rot = rng.uniform(0, 3)
        ly.ellipse(x + 1.5, y + 1.5, r, r * 0.85, rot, tuple(c * 0.45 for c in tint), 4.5, 10)               # Schattenfuß
        ly.ellipse(x, y, r, r * rng.uniform(0.6, 0.95), rot, tint, 5.0 + r * 0.5, 10)
        ly.ellipse(x - r * 0.25, y - r * 0.25, r * 0.55, r * 0.42, rot, tuple(min(1, c * 1.22) for c in tint), 5.4 + r * 0.5, 8)
    # Laub und Reste: braun, im Boden festgetreten
    for _ in range(70):
        x, y = rng.uniform(0, N, 2)
        ln = rng.uniform(14, 28)
        col = jitter(rng, [(0.36, 0.20, 0.08), (0.50, 0.30, 0.10), (0.26, 0.17, 0.08), (0.44, 0.34, 0.13)][rng.integers(4)], 0.2)
        ly.poly(leaf_pts(x, y, ln, ln * 0.45, rng.uniform(0, 6.28)), col, 2.5)
    # Kiefernnadeln und Wurzelfasern
    for _ in range(1700):
        x, y = rng.uniform(0, N, 2)
        a = rng.uniform(0, math.pi)
        ln = rng.uniform(10, 22)
        ly.line((x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln), jitter(rng, (0.38, 0.24, 0.12), 0.25), 1, 1.5)
    for _ in range(60):
        x, y = rng.uniform(0, N, 2)
        a = rng.uniform(0, 2 * math.pi)
        ln = rng.uniform(40, 120)
        ly.line((x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln), jitter(rng, (0.21, 0.145, 0.09), 0.2), int(rng.integers(1, 3)), 2.5)
    # wenig Gras und Moos an den feuchten Stellen
    for _ in range(300):
        x, y = rng.uniform(0, N, 2)
        if base[int(y) % N, int(x) % N].mean() > 0.27 and rng.random() < 0.8:
            continue
        a = rng.uniform(0, 2 * math.pi)
        ln = rng.uniform(6, 13)
        ly.line((x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln), jitter(rng, (0.18, 0.28, 0.085), 0.3), 1, 1.8)
    rgb, hgt = ly.result()
    # Körnung: pixelfeines Rauschen auf Farbe und Höhe (Sand, Splitt), Mulden dunkler
    grain = np.random.default_rng(5).standard_normal((N, N)).astype(np.float32)
    grain = ndi.gaussian_filter(grain, 0.8, mode="wrap") * 2.2
    rgb = rgb * (1.0 + 0.07 * np.clip(grain, -1.5, 1.5))[..., None]
    ridge = n3 * 0.7 + n4 * 0.5
    hgt = hgt + 1.6 * ridge + 0.5 * grain
    return save(name, rgb * dark, hgt * 0.5, strength, out)


# ------------------------------------------------------------------------------------------------ Texturen für gebaute Teile
def holz(name, base_cols, stripes=18, plank=True, seed=0):
    """Längsfaseriges Holz (Maserung entlang der x-Achse). plank: senkrechte Fugen zwischen Brettern."""
    rng = np.random.default_rng(seed)
    n1, n2 = pink(1.8, seed + 1), pink(1.1, seed + 2)
    rgb = np.zeros((N, N, 3), np.float32)
    y = (np.arange(N)[:, None] + np.zeros((1, N)))
    x = (np.arange(N)[None, :] + np.zeros((N, 1)))
    # Maserung: Streifen entlang x, durch Rauschen verzogen
    warp = ndi.gaussian_filter(rng.standard_normal((N, N)).astype(np.float32), (14, 90), mode="wrap")
    warp = warp / (warp.std() + 1e-6)
    stripe = 0.5 + 0.5 * np.sin((y / N * stripes * 2 * math.pi) + warp * 2.2 + n1 * 0.6)
    fine = ndi.gaussian_filter(rng.standard_normal((N, N)).astype(np.float32), (0.8, 18), mode="wrap")
    fine = fine / (fine.std() + 1e-6)
    a, b = np.array(base_cols[0]), np.array(base_cols[1])
    rgb = mixc(a, b, stripe * 0.7 + 0.15 * fine)
    rgb *= (1.0 + 0.1 * n2)[..., None]
    hgt = stripe * 0.4 + fine * 0.2
    if plank:
        rows = 8
        for r in range(rows):
            y0 = int(r * N / rows)
            rgb[max(0, y0 - 2):y0 + 2, :, :] *= 0.35
            hgt[max(0, y0 - 2):y0 + 2, :] -= 1.5
            rgb[y0 + 2:int((r + 1) * N / rows) - 2] *= (0.85 + 0.3 * rng.random())
    return rgb, hgt


def rinde():
    """Baumrinde (senkrechte Furchen), nahtlos."""
    rng = np.random.default_rng(404)
    n1 = pink(1.6, 41)
    warp = ndi.gaussian_filter(rng.standard_normal((N, N)).astype(np.float32), (60, 5), mode="wrap")
    warp = warp / (warp.std() + 1e-6)
    x = np.arange(N)[None, :] + np.zeros((N, 1))
    ridge = np.abs(np.sin((x / N * 26 * math.pi) + warp * 2.0)) ** 0.7
    fine = ndi.gaussian_filter(rng.standard_normal((N, N)).astype(np.float32), (22, 1.2), mode="wrap")
    fine = fine / (fine.std() + 1e-6)
    base = mixc(np.array([0.10, 0.075, 0.055]), np.array([0.30, 0.22, 0.15]), np.clip(ridge * 0.8 + 0.12 * fine + 0.1 * n1, 0, 1))
    return base, ridge + 0.3 * fine


def schindel():
    """Dachschindeln aus Holz: Reihen, versetzte Fugen, ergraut."""
    rng = np.random.default_rng(505)
    rows, cols = 10, 14
    rgb = np.zeros((N, N, 3), np.float32)
    hgt = np.zeros((N, N), np.float32)
    n2 = pink(1.3, 51)
    for r in range(rows):
        y0, y1 = int(r * N / rows), int((r + 1) * N / rows)
        off = (r % 2) * 0.5
        for c in range(cols):
            x0 = int(((c + off) / cols) * N)
            x1 = int(((c + off + 1) / cols) * N)
            tone = rng.uniform(0.7, 1.15)
            col = np.array([0.27, 0.17, 0.10]) * tone if rng.random() < 0.7 else np.array([0.30, 0.27, 0.22]) * tone
            for dx in (-N, 0, N):
                xa, xb = x0 + dx, x1 + dx
                if xb <= 0 or xa >= N:
                    continue
                xa, xb = max(xa, 0), min(xb, N)
                seg = rgb[y0:y1, xa:xb]
                grain = 1.0 + 0.1 * np.sin(np.linspace(0, 6, xb - xa) * 9 + rng.random() * 6)[None, :, None]
                seg[:] = col[None, None, :] * grain
                rgb[y0:y1, xa:xb, :] *= np.linspace(0.65, 1.1, y1 - y0)[:, None, None]                 # Schatten unter der Reihe darüber
                rgb[y0:y1, xa:xa + 3] *= 0.45
                hgt[y0:y1, xa:xb] = np.linspace(0.0, 1.0, y1 - y0)[:, None]
                hgt[y0:y1, xa:xa + 3] -= 1.0
        rgb[y0:y0 + 3] *= 0.4
    rgb *= (1.0 + 0.16 * n2)[..., None]
    return rgb, hgt


def dach_alt():
    """Verwitterte Holzschindeln für das Hüttendach: silbergraue und warmbraune Schindeln in versetzten Reihen, an den Unterkanten heller,
    unter der Reihe darüber schattiert, Regenstreifen und Moospolster in den unteren Dritteln. Heller als `schindel`, damit das Dach von
    oben als Schindeldach und nicht als dunkle Fläche gelesen wird."""
    rng = np.random.default_rng(515)
    rows, cols = 12, 16
    rgb = np.zeros((N, N, 3), np.float32)
    hgt = np.zeros((N, N), np.float32)
    n2, n3 = pink(1.3, 52), pink(2.4, 53)
    silver = np.array([0.46, 0.43, 0.38])
    warm = np.array([0.40, 0.25, 0.15])
    for r in range(rows):
        y0, y1 = int(r * N / rows), int((r + 1) * N / rows)
        off = (r % 2) * 0.5
        for c in range(cols):
            x0 = int(((c + off) / cols) * N)
            x1 = int(((c + off + 1) / cols) * N)
            tone = rng.uniform(0.78, 1.18)
            t_mix = rng.uniform(0.0, 1.0)
            col = (silver * t_mix + warm * (1 - t_mix)) * tone
            lower = rng.uniform(0.0, 0.18)                                                         # Schindeln stehen unterschiedlich weit vor
            for dx in (-N, 0, N):
                xa, xb = x0 + dx, x1 + dx
                if xb <= 0 or xa >= N:
                    continue
                xa, xb = max(xa, 0), min(xb, N)
                yy1 = min(N, y1 + int(lower * (y1 - y0)))
                seg = rgb[y0:yy1, xa:xb]
                grain = 1.0 + 0.09 * np.sin(np.linspace(0, 6, xb - xa) * 11 + rng.random() * 6)[None, :, None]
                seg[:] = col[None, None, :] * grain
                rgb[y0:yy1, xa:xb, :] *= np.linspace(0.62, 1.12, yy1 - y0)[:, None, None]            # Schatten der Reihe darüber, helle Unterkante
                rgb[y0:yy1, xa:xa + 3] *= 0.5
                hgt[y0:yy1, xa:xb] = np.linspace(0.0, 1.0, yy1 - y0)[:, None]
                hgt[y0:yy1, xa:xa + 3] -= 1.0
        rgb[y0:y0 + 3] *= 0.45
    rgb *= (1.0 + 0.14 * n2)[..., None]
    # Moos: Polster in den Senken und an den unteren Kanten, grün und etwas dunkler
    yy = (np.arange(N)[:, None] % (N / rows)) / (N / rows)
    moss = smooth(n3 + 0.9 * yy - 0.6, 0.35, 1.05) * smooth(pink(1.9, 54), 0.2, 1.4)
    rgb = mixc(rgb, np.array([0.17, 0.27, 0.09]) * (0.8 + 0.4 * smooth(n2, -1, 1))[..., None], np.clip(moss * 0.75, 0, 0.8))
    # Regenstreifen: senkrechte dunkle Spuren
    streak = ndi.gaussian_filter(rng.standard_normal((N, N)).astype(np.float32), (40, 2.0), mode="wrap")
    streak = smooth(streak / (streak.std() + 1e-6), 0.8, 2.4)
    rgb *= (1.0 - 0.28 * streak)[..., None]
    return rgb, hgt


def laub():
    """Dichtes Laub (Blätter in Grüntönen) für Büsche und Unterholz, nahtlos."""
    rng = np.random.default_rng(606)
    n1 = pink(1.5, 61)
    base = mixc(np.array([0.05, 0.12, 0.035]), np.array([0.10, 0.22, 0.06]), smooth(n1, -1, 1))
    ly = Layer(base)
    greens = [(0.12, 0.28, 0.06), (0.18, 0.38, 0.08), (0.10, 0.22, 0.05), (0.26, 0.44, 0.10), (0.15, 0.32, 0.07), (0.30, 0.40, 0.10)]
    for _ in range(2600):
        x, y = rng.uniform(0, N, 2)
        ln = rng.uniform(26, 52)
        col = jitter(rng, greens[rng.integers(len(greens))], 0.15)
        rot = rng.uniform(0, 2 * math.pi)
        ly.poly(leaf_pts(x, y, ln, ln * rng.uniform(0.45, 0.62), rot), col, rng.uniform(0, 6))
        ly.line((x - math.cos(rot) * ln * 0.45, y - math.sin(rot) * ln * 0.45), (x + math.cos(rot) * ln * 0.45, y + math.sin(rot) * ln * 0.45),
                tuple(min(1, c * 1.35) for c in col), 1)
    rgb, hgt = ly.result()
    return rgb, hgt


def nadelkrone():
    """Kiefernnadeln in Büscheln (dunkel blaugrün), nahtlos: für die Kronen der Kiefern."""
    rng = np.random.default_rng(707)
    n1 = pink(1.4, 71)
    base = mixc(np.array([0.07, 0.15, 0.09]), np.array([0.13, 0.25, 0.13]), smooth(n1, -1.2, 1.2))
    ly = Layer(base)
    greens = [(0.12, 0.30, 0.14), (0.17, 0.38, 0.17), (0.09, 0.22, 0.11), (0.24, 0.44, 0.17), (0.14, 0.32, 0.20), (0.30, 0.44, 0.16)]
    for _ in range(900):                                           # Nadelbüschel: Strahlen von einem Punkt aus
        x, y = rng.uniform(0, N, 2)
        col = greens[rng.integers(len(greens))]
        a0 = rng.uniform(0, 2 * math.pi)
        for k in range(rng.integers(7, 14)):
            a = a0 + rng.uniform(-0.9, 0.9)
            ln = rng.uniform(26, 55)
            ly.line((x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln), jitter(rng, col, 0.2), 1, rng.uniform(1, 4))
    rgb, hgt = ly.result()
    return rgb, hgt


def build_sources():
    outs = {}
    for name, base_cols, stripes, plank, seed in (
            ("holz", ((0.20, 0.12, 0.07), (0.42, 0.28, 0.16)), 26, True, 70),
            ("holz_grau", ((0.22, 0.20, 0.17), (0.40, 0.36, 0.30)), 22, True, 80),
            ("stamm", ((0.25, 0.15, 0.08), (0.46, 0.31, 0.17)), 9, False, 90)):
        rgb, hgt = holz(name, base_cols, stripes, plank, seed)
        save(name, rgb, hgt, 0.0, SRC)
        outs[name] = rgb
    rgb, hgt = rinde()
    outs["rinde"] = save("rinde", rgb, hgt, 0.0, SRC)
    rgb, hgt = schindel()
    outs["schindel"] = save("schindel", rgb, hgt, 0.0, SRC)
    rgb, hgt = dach_alt()
    outs["dach_alt"] = save("dach_alt", rgb, hgt, 0.0, SRC)
    rgb, hgt = laub()
    outs["laub"] = save("laub", rgb, hgt, 0.0, SRC)
    rgb, hgt = nadelkrone()
    outs["nadelkrone"] = save("nadelkrone", rgb, hgt, 0.0, SRC)
    outs["matsch"] = boden_schlamm("matsch", SRC, 0.0)
    outs["spur"] = boden_erde("spur", SRC, 0.0, 0.7, 0.0)
    return outs


def sheet(items, path):
    tiles = [Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)).resize((384, 384)) for rgb in items]
    cols = 4
    rows = (len(tiles) + cols - 1) // cols
    img = Image.new("RGB", (cols * 384, rows * 384))
    for i, t in enumerate(tiles):
        img.paste(t, ((i % cols) * 384, (i // cols) * 384))
    img.save(path)


if __name__ == "__main__":
    if "--nur-dach" in sys.argv:                       # nur das Hüttendach neu erzeugen (Schnelllauf, keine Bodentexturen)
        rgb, hgt = dach_alt()
        save("dach_alt", rgb, hgt, 0.0, SRC)
        if SHEET:
            sheet([rgb], SHEET)
        sys.exit(0)
    if "--nur-erde" in sys.argv:                       # nur die Wegerde neu erzeugen (Schnelllauf)
        rgb = boden_erde()
        boden_schlamm("matsch", SRC, 0.0)
        boden_erde("spur", SRC, 0.0, 0.7, 0.0)
        if SHEET:
            sheet([np.tile(rgb, (2, 2, 1))[::2, ::2]], SHEET)
        sys.exit(0)
    big = [boden_wald(), boden_nadeln(), boden_erde()]
    src = build_sources()
    if SHEET:
        # Vorschau: Bodenkacheln 2x2 gekachelt (Nahtprobe) + Quellen
        tiled = [np.tile(b, (2, 2, 1))[::2, ::2] for b in big]
        sheet(tiled + list(src.values()), SHEET)
    with open(os.path.join(OUT, "HERKUNFT.md"), "w", encoding="utf-8") as fh:
        fh.write("# Texturen des Wald-Dioramas\n\n"
                 "Alles prozedural erzeugt mit `tools/make_forest_textures.py` (numpy, scipy, Pillow), kein fremdes Material.\n\n"
                 "- `boden_wald`, `boden_nadeln`, `boden_erde` (+ `_n` Normalkarten): Bodenmischung des Dioramas (`ground_set`). `boden_erde` (Wegerde: festgefahrene Erde\n"
                 "  mit Schotter, Laub und Nadeln, dazu dunkle feuchte Flecken) bildet den Saum der Piste; der frühere Schlamm steckt als `quelle/matsch.jpg` im Material F_Matsch, die Radspuren als `quelle/spur.jpg` im Material F_Spur.\n"
                 "- `quelle/`: Texturen für in Blender gebaute Teile (Holz, Rinde, Schindeln, Laub, Matsch); der Ordner ist per `.gdignore` vom\n"
                 "  Godot-Import ausgenommen, die Bilder stecken eingebettet in `game/dioramas/forest.glb`.\n"
                 "- Hütte, Felsen, Wegweiser, Holzstapel, Baumstümpfe, Stämme, Laternen: KI-Modelle aus `game/assets/props/wald_*` (Herkunft dort dokumentiert).\n"
                 "- Bäume, Unterholz, Steg, Ruderboot, Hochsitz, Holzpolter, Strohballen: selbst gebaut in `tools/dio_themes/forest.py` (Blender, keine fremden Modelle).\n")
    print("Wald-Texturen:", OUT)
