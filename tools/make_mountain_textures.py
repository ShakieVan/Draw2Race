"""Erzeugt die Texturen des Serra-Pass-Dioramen (Thema "mountain"): alles prozedural (numpy, scipy, Pillow), kein fremdes Material.

Ergebnis in game/assets/dio/mountain/ (Mischung des Boden-Shaders, assets/ground_blend.gdshader; Normalkarte = Name + _n):
  boden_trockengras(.jpg|_n.jpg)   ausgebrannter Mittelmeerrasen mit Halmen, Strohflecken und Kräuterpolstern   (Platz "grass")
  boden_kalk(.jpg|_n.jpg)          heller Kalkschotter und Staub (Bankett, Pfade, kahle Stellen)               (Platz "sand")
  boden_terrarossa(.jpg|_n.jpg)    rotbraune Erde mit Steinchen (Terrassenböden, Haine, Wege)                  (Platz "dirt")
und für Blender (quelle/, Godot ignoriert den Ordner per .gdignore; die Bilder stecken eingebettet in game/dioramas/serra.glb):
  fels(.jpg|_n.jpg)      Kalkfels: Schichtung, Klüfte, Regenstreifen, Flechten
  mauer(.jpg|_n.jpg)     Trockenmauer: unregelmäßige Steine in Lagen mit dunklen Fugen
  rinde.jpg, kiefer.jpg, olive.jpg, busch.jpg, zypresse.jpg, agave.jpg, opuntie.jpg    Stämme und Laub (Kronen aus Blasen)
Alle Kacheln sind nahtlos (Rauschen im Frequenzraum, Voronoi-Zellen mit Umbruch an den Rändern).
Aufruf: python tools/make_mountain_textures.py [ausgabeordner] [--sheet kontaktbogen.png]
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
from scipy.spatial import cKDTree

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET = sys.argv[sys.argv.index("--sheet") + 1] if "--sheet" in sys.argv else None
_args = [a for i, a in enumerate(sys.argv[1:], 1) if not a.startswith("--") and not (i > 1 and sys.argv[i - 1] == "--sheet")]
OUT = _args[0] if _args else os.path.join(ROOT, "game", "assets", "dio", "mountain")
SRC = os.path.join(OUT, "quelle")
os.makedirs(SRC, exist_ok=True)
with open(os.path.join(SRC, ".gdignore"), "w") as _fh:
    _fh.write("")
N = 1024


def pink(beta, seed, n=N):
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


def voronoi(pts, n=N, scale=(1.0, 1.0), warp=None):
    """Nahtlose Voronoi-Zellen (Abstand zum nächsten Punkt F1, zum zweitnächsten F2, Zellennummer). pts in Pixeln; scale streckt die Abfrage
    (z. B. (1, 2): Zellen werden in x doppelt so lang). warp = (dx, dy) verschiebt die Abfragepunkte."""
    big = np.concatenate([pts + np.array([dx * n, dy * n]) for dx in (-1, 0, 1) for dy in (-1, 0, 1)])
    ids = np.tile(np.arange(len(pts)), 9)
    sc = np.array(scale, float)
    tree = cKDTree(big * sc)
    yy, xx = np.mgrid[0:n, 0:n]
    qx, qy = xx.astype(np.float64), yy.astype(np.float64)
    if warp is not None:
        qx, qy = qx + warp[0], qy + warp[1]
    d, i = tree.query(np.stack([qx.ravel() * sc[0], qy.ravel() * sc[1]], 1), k=2, workers=-1)
    return d[:, 0].reshape(n, n).astype(np.float32), d[:, 1].reshape(n, n).astype(np.float32), ids[i[:, 0]].reshape(n, n)


def normal_from(height, strength):
    height = ndi.gaussian_filter(height, 0.7, mode="wrap")
    gy, gx = np.gradient(height)
    nx, ny, nz = -gx * strength, gy * strength, np.ones_like(height)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5


def save(name, rgb, height, strength, out=OUT, quality=92):
    Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(out, name + ".jpg"), quality=quality)
    if strength > 0:
        Image.fromarray((normal_from(height, strength) * 255 + 0.5).astype(np.uint8)).save(os.path.join(out, name + "_n.jpg"), quality=quality)
    return rgb


class Layer:
    """Zeichenfläche (Farbe und Höhe) mit nahtlosem Umbruch an den Rändern."""

    def __init__(self, base, n=N, height_base=128):
        self.n = n
        self.img = Image.fromarray((np.clip(base, 0, 1) * 255 + 0.5).astype(np.uint8))
        self.hgt = Image.new("L", (n, n), height_base)
        self.d = ImageDraw.Draw(self.img)
        self.h = ImageDraw.Draw(self.hgt)

    def _wrap(self, pts):
        n = self.n
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        for dx in (-n, 0, n):
            for dy in (-n, 0, n):
                if max(xs) + dx < 0 or min(xs) + dx > n or max(ys) + dy < 0 or min(ys) + dy > n:
                    continue
                yield dx, dy

    def poly(self, pts, color, height=None):
        for dx, dy in self._wrap(pts):
            q = [(x + dx, y + dy) for x, y in pts]
            self.d.polygon(q, fill=tuple(int(c * 255) for c in color))
            if height is not None:
                self.h.polygon(q, fill=int(height))

    def line(self, p0, p1, color, width=1, height=None):
        for dx, dy in self._wrap([p0, p1]):
            a, b = (p0[0] + dx, p0[1] + dy), (p1[0] + dx, p1[1] + dy)
            self.d.line([a, b], fill=tuple(int(c * 255) for c in color), width=width)
            if height is not None:
                self.h.line([a, b], fill=int(height), width=width)

    def ellipse(self, cx, cy, rx, ry, rot, color, height=None, k=14):
        pts = []
        for i in range(k):
            t = 2 * math.pi * i / k
            x, y = rx * math.cos(t), ry * math.sin(t)
            pts.append((cx + x * math.cos(rot) - y * math.sin(rot), cy + x * math.sin(rot) + y * math.cos(rot)))
        self.poly(pts, color, height)

    def result(self):
        return np.asarray(self.img, np.float32) / 255.0, np.asarray(self.hgt, np.float32)


def jitter(rng, col, amt):
    v = rng.uniform(-amt, amt)
    return tuple(min(1.0, max(0.0, c * (1 + v))) for c in col)


# ------------------------------------------------------------------------------------------------ Böden
def boden_trockengras():
    """Ausgebrannter Mittelmeerrasen: Strohgelb und Olivgrün in Flecken, viele feine Halme, Steinchen, dunkle Kräuterpolster."""
    rng = np.random.default_rng(101)
    n1, n2, n3 = pink(2.4, 1011), pink(1.6, 1012), pink(1.0, 1013)
    straw = np.array([0.66, 0.57, 0.34])
    pale = np.array([0.78, 0.71, 0.50])
    olive = np.array([0.40, 0.43, 0.22])
    dark = np.array([0.24, 0.28, 0.14])
    rgb = mixc(straw, pale, smooth(n1 * 0.8 + n2 * 0.3, -0.2, 1.4))
    rgb = mixc(rgb, olive, smooth(n1 * 0.7 - n2 * 0.5 + n3 * 0.2, -0.1, 1.2) * 0.85)
    rgb = mixc(rgb, dark, smooth(n2 * 0.6 + n3 * 0.5 - n1 * 0.3, 0.7, 1.8) * 0.7)
    h = 0.4 * n3 + 0.3 * n2
    ly = Layer(rgb)
    cols = [(0.72, 0.64, 0.38), (0.60, 0.52, 0.30), (0.48, 0.48, 0.24), (0.80, 0.74, 0.52), (0.36, 0.40, 0.19), (0.66, 0.56, 0.32)]
    for _ in range(26000):                                       # Halme: kurze, leicht gebogene Striche in einheitlicher Blickrichtung
        x, y = rng.uniform(0, N, 2)
        a = rng.normal(-math.pi / 2, 0.9)
        ln = rng.uniform(5, 15)
        col = jitter(rng, cols[rng.integers(len(cols))], 0.14)
        ly.line((x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln), col, 1, rng.integers(110, 190))
    for _ in range(90):                                          # Büschel: dichter, dunkler
        x, y = rng.uniform(0, N, 2)
        for _k in range(rng.integers(14, 26)):
            a = rng.uniform(-math.pi * 0.95, -math.pi * 0.05)
            ln = rng.uniform(10, 24)
            ly.line((x, y), (x + math.cos(a) * ln, y + math.sin(a) * ln), jitter(rng, (0.50, 0.46, 0.24), 0.2), 1, rng.integers(140, 210))
    for _ in range(70):                                          # Steinchen
        x, y = rng.uniform(0, N, 2)
        r = rng.uniform(2.5, 6.5)
        ly.ellipse(x, y, r, r * rng.uniform(0.6, 1.0), rng.uniform(0, 3.14), jitter(rng, (0.72, 0.69, 0.62), 0.12), 200, 8)
    rgb2, h2 = ly.result()
    rgb2 *= (1.0 + 0.06 * n3 + 0.05 * n2)[..., None]
    return save("boden_trockengras", rgb2, h * 20 + (h2 - 128) * 0.8, 2.4)


def boden_kalk():
    """Heller Kalkschotter mit Staub: feine Splitter, vereinzelt größere flache Platten, Staubschleier."""
    rng = np.random.default_rng(111)
    n1, n2, n3 = pink(2.6, 1111), pink(1.8, 1112), pink(1.0, 1113)
    stones = np.array([(0.86, 0.82, 0.72), (0.78, 0.74, 0.65), (0.90, 0.88, 0.80), (0.70, 0.66, 0.58), (0.82, 0.76, 0.62), (0.64, 0.62, 0.58),
                       (0.92, 0.86, 0.70)], np.float32)
    cnt = 14000
    pts = rng.uniform(0, N, (cnt, 2))
    d1, d2, cid = voronoi(pts)
    tone = stones[rng.integers(len(stones), size=cnt)] * rng.uniform(0.88, 1.08, (cnt, 1)).astype(np.float32)
    fine = tone[cid]
    edge = smooth(d2 - d1, 0.0, 2.0)
    dome = 1.0 - smooth(d1, 0.0, 8.5)
    fine = fine * (0.60 + 0.40 * edge)[..., None] * (0.86 + 0.22 * dome)[..., None]
    dust = np.array([0.80, 0.76, 0.67])
    rgb = mixc(fine, dust, smooth(n2 - 0.4 * n3, 0.2, 1.7) * 0.45)
    # größere flache Platten
    ptsb = rng.uniform(0, N, (130, 2))
    e1, e2, ecid = voronoi(ptsb, scale=(1.0, 1.4), warp=(pink(2.4, 1114) * 20, pink(2.4, 1115) * 20))
    toneb = stones[rng.integers(len(stones), size=130)][ecid] * rng.uniform(0.9, 1.05, (130, 1)).astype(np.float32)[ecid]
    edgeb = smooth(e2 - e1, 0.0, 3.0)
    domeb = 1.0 - smooth(e1, 0.0, 24.0)
    cover = (rng.random(130)[ecid] < 0.22) & (e1 < 40)
    big = toneb * (0.55 + 0.45 * edgeb)[..., None] * (0.88 + 0.2 * domeb)[..., None]
    rgb = np.where(cover[..., None], big, rgb)
    rgb = rgb * (1.0 + 0.05 * n3)[..., None]
    h = edge * 0.5 + dome * 0.5 + np.where(cover, edgeb * 0.9 + domeb * 0.8, 0.0)
    return save("boden_kalk", rgb, h * 0.8, 3.0)


def boden_terrarossa():
    """Rotbraune Terra rossa: feiner Krümel, Trockenrisse, Kiesel, hellere Kalkstaubfahnen."""
    rng = np.random.default_rng(121)
    n1, n2, n3, n4 = pink(2.6, 1211), pink(1.8, 1212), pink(1.1, 1213), pink(0.8, 1214)
    red = np.array([0.50, 0.29, 0.18])
    brown = np.array([0.42, 0.27, 0.18])
    light = np.array([0.66, 0.46, 0.32])
    rgb = mixc(red, brown, smooth(n1 * 0.8 + n2 * 0.5, -0.4, 1.4))
    rgb = mixc(rgb, light, smooth(n2 * 0.7 - n1 * 0.4, 0.6, 1.8) * 0.5)
    rgb *= (1.0 + 0.07 * n3 + 0.05 * n4)[..., None]
    # Trockenrisse
    pts = rng.uniform(0, N, (170, 2))
    d1, d2, cid = voronoi(pts, warp=(pink(2.4, 1215) * 14, pink(2.4, 1216) * 14))
    crack = smooth(d2 - d1, 0.0, 1.7)
    rgb *= (0.62 + 0.38 * crack)[..., None]
    h = crack * 0.7 + 0.35 * n3 + 0.3 * n4
    # Kiesel
    cnt = 320
    pb = rng.uniform(0, N, (cnt, 2))
    f1, f2, fid = voronoi(pb)
    tone = np.array([(0.74, 0.70, 0.62), (0.66, 0.60, 0.52), (0.82, 0.78, 0.70), (0.58, 0.50, 0.42)], np.float32)[rng.integers(4, size=cnt)][fid]
    stone = (rng.random(cnt)[fid] < 0.30) & (f1 < 10.0)
    scol = tone * (0.7 + 0.3 * (1.0 - smooth(f1, 0.0, 10.0)))[..., None]
    rgb = np.where(stone[..., None], scol, rgb)
    h = h + stone * (1.0 - smooth(f1, 0.0, 10.0)) * 1.6
    return save("boden_terrarossa", rgb, h * 0.8, 2.6)


# ------------------------------------------------------------------------------------------------ Fels und Mauer
ROCK = np.array([(0.80, 0.76, 0.66), (0.72, 0.68, 0.60), (0.86, 0.83, 0.75), (0.64, 0.62, 0.57), (0.78, 0.70, 0.56), (0.70, 0.64, 0.52),
                 (0.60, 0.58, 0.54), (0.90, 0.88, 0.82), (0.74, 0.60, 0.46)], np.float32)
ROCK_P = np.array([0.19, 0.17, 0.10, 0.13, 0.12, 0.09, 0.08, 0.05, 0.07])


def fels():
    """Kalkfels in Seitenansicht (u waagerecht, v senkrecht): Schichten verschiedener Tönung, an den Fugen Absätze, senkrechte Klüfte,
    Regenstreifen, Pusteln und Flechten."""
    rng = np.random.default_rng(131)
    n1, n2, n3 = pink(2.2, 1311), pink(1.5, 1312), pink(0.9, 1313)
    wy = pink(2.8, 1314)
    yy = np.arange(N)[:, None] + np.zeros((1, N))
    # Schichten: Grenzen alle 40..110 Pixel, in x verzogen
    bounds = [0.0]
    while bounds[-1] < N:
        bounds.append(bounds[-1] + rng.uniform(58, 170))
    bounds[-1] = N
    # an den Kachelrändern müssen die Grenzen passen: auf genau N strecken
    bounds = np.array(bounds)
    bounds = bounds / bounds[-1] * N
    sid = np.zeros((N, N), int)
    yw = yy + wy * 15.0 + n1 * 12.0 + pink(2.2, 1319) * 9.0
    yw = np.mod(yw, N)
    for k in range(len(bounds) - 1):
        sid[(yw >= bounds[k]) & (yw < bounds[k + 1])] = k
    tones = ROCK[rng.choice(len(ROCK), len(bounds), p=ROCK_P)] * rng.uniform(0.86, 1.08, (len(bounds), 1)).astype(np.float32)
    rgb = tones[sid]
    # Fugen und Absätze: Abstand zur nächsten Schichtgrenze
    dist_b = np.full((N, N), 1e3, np.float32)
    for b in bounds[:-1]:
        dist_b = np.minimum(dist_b, np.abs(yw - b))
    dist_b = np.minimum(dist_b, np.abs(yw - N))
    ledge = 1.0 - smooth(dist_b, 0.0, 5.0)
    rgb = rgb * (1.0 - 0.36 * ledge)[..., None]
    # senkrechte Klüfte (gestreckte Zellen)
    pts = rng.uniform(0, N, (110, 2))
    d1, d2, cid = voronoi(pts, scale=(1.0, 0.33), warp=(wy * 9.0, n1 * 6.0))
    joint = 1.0 - smooth(d2 - d1, 0.0, 2.4)
    keep = rng.random(len(pts))[cid] < 0.5
    rgb = rgb * (1.0 - 0.38 * joint * keep)[..., None]
    # Blockflächen leicht verschieden hell (Würfelschalen)
    rgb = rgb * (0.94 + 0.12 * (rng.random(len(pts))[cid]))[..., None]
    # Regenstreifen: lange senkrechte dunkle und ockerfarbene Bahnen
    streak = ndi.gaussian_filter(rng.standard_normal((N, N)).astype(np.float32), (46, 1.6), mode="wrap")
    streak = streak / (streak.std() + 1e-6)
    rgb = rgb * (1.0 - 0.18 * smooth(streak, 0.9, 2.4))[..., None]
    rgb = mixc(rgb, rgb * np.array([1.07, 0.96, 0.82]), smooth(streak, -2.2, -0.8) * 0.32)
    # Flechten (orange, gelbgrün) und Pusteln
    lich = smooth(n2 * 0.8 + n3 * 0.5, 1.0, 1.9)
    rgb = mixc(rgb, np.array([0.80, 0.58, 0.22]), lich * 0.20 * (1 - joint))
    lich2 = smooth(n3 * 0.9 - n2 * 0.3, 1.1, 2.0)
    rgb = mixc(rgb, np.array([0.60, 0.62, 0.34]), lich2 * 0.30)
    rgb *= (1.0 + 0.10 * n3 + 0.05 * n2)[..., None]
    h = ledge * -1.2 + joint * keep * -0.9 + 0.5 * n3 + 0.35 * n2 + (sid % 3) * 0.2
    return save("fels", rgb, h, 3.2, SRC)


def mauer():
    """Trockenmauer: Steine in waagerechten Lagen, verschieden lang, dunkle Fugen mit Zwickelsteinen, Moos und Flechten."""
    rng = np.random.default_rng(141)
    n1, n2, n3 = pink(2.2, 1411), pink(1.5, 1412), pink(0.9, 1413)
    rows = 9
    pts = []
    for r in range(rows):
        y = (r + 0.5) * N / rows + rng.uniform(-4, 4)
        x = rng.uniform(0, 60)
        while x < N:
            w = rng.uniform(80, 190)
            pts.append((x + w / 2, y + rng.uniform(-6, 6)))
            x += w
    pts = np.array(pts)
    # Zeilen und Spaltenzahl schließen sich nur näherungsweise (Umbruch über Voronoi mit Spiegelung in 3x3)
    d1, d2, cid = voronoi(pts, scale=(1.0, 2.3), warp=(pink(2.6, 1414) * 7, pink(2.6, 1415) * 5))
    cnt = len(pts)
    stone = ROCK[rng.choice(len(ROCK), cnt, p=ROCK_P)] * rng.uniform(0.82, 1.1, (cnt, 1)).astype(np.float32)
    rgb = stone[cid]
    edge = smooth((d2 - d1), 0.0, 6.0)
    dome = 1.0 - smooth(d1, 0.0, 70.0)
    rgb = rgb * (0.30 + 0.70 * edge)[..., None] * (0.80 + 0.30 * dome)[..., None]
    rgb *= (1.0 + 0.12 * n3 + 0.06 * n2)[..., None]
    moss = smooth(n2 * 0.7 + n3 * 0.5, 0.9, 1.8) * (1.0 - edge * 0.6)
    rgb = mixc(rgb, np.array([0.38, 0.44, 0.22]), moss * 0.4)
    lich = smooth(n3 * 0.8 - n1 * 0.3, 1.0, 2.0)
    rgb = mixc(rgb, np.array([0.80, 0.62, 0.22]), lich * 0.3)
    h = edge * 1.6 + dome * 1.3 + 0.35 * n3
    return save("mauer", rgb, h, 3.4, SRC)


# ------------------------------------------------------------------------------------------------ Bäume und Büsche
def leaf_pts(cx, cy, length, width, rot):
    pts = []
    for k in range(-5, 6):
        t = k / 5.0
        w = width * 0.5 * (1 - t * t) ** 0.8
        pts.append((t * length * 0.5, w))
    pts += [(-p[0], -p[1]) for p in pts[::-1]]
    c, s = math.cos(rot), math.sin(rot)
    return [(cx + x * c - y * s, cy + x * s + y * c) for x, y in pts]


def foliage(name, base_lo, base_hi, leaf_cols, count, length, aspect, seed, back=None, star=False, n=512):
    """Laubstruktur (nahtlos, n x n): dunkler Grund, darüber Blätter bzw. Nadelbüschel; back = helle Blattunterseite (Olive)."""
    rng = np.random.default_rng(seed)
    n1 = pink(1.5, seed + 1, n)
    base = mixc(np.array(base_lo), np.array(base_hi), smooth(n1, -1.1, 1.1))
    ly = Layer(base, n)
    scale = n / 512.0
    for _ in range(count):
        x, y = rng.uniform(0, n, 2)
        ln = rng.uniform(*length) * scale
        rot = rng.uniform(0, 2 * math.pi)
        if star:
            col = leaf_cols[rng.integers(len(leaf_cols))]
            a0 = rng.uniform(0, 2 * math.pi)
            for _k in range(rng.integers(6, 12)):
                a = a0 + rng.uniform(-0.9, 0.9)
                l2 = ln * rng.uniform(0.6, 1.0)
                ly.line((x, y), (x + math.cos(a) * l2, y + math.sin(a) * l2), jitter(rng, col, 0.2), 1, rng.integers(90, 190))
        else:
            use_back = back is not None and rng.random() < 0.38
            col = jitter(rng, back if use_back else leaf_cols[rng.integers(len(leaf_cols))], 0.13)
            ly.poly(leaf_pts(x, y, ln, ln * aspect, rot), col, rng.integers(110, 200))
            ly.line((x - math.cos(rot) * ln * 0.45, y - math.sin(rot) * ln * 0.45), (x + math.cos(rot) * ln * 0.45, y + math.sin(rot) * ln * 0.45),
                    tuple(min(1, c * 1.25) for c in col), 1)
    rgb, _ = ly.result()
    Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(SRC, name + ".jpg"), quality=90)
    return rgb


def kiefer():
    return foliage("kiefer", (0.08, 0.15, 0.07), (0.15, 0.25, 0.10), [(0.17, 0.32, 0.12), (0.24, 0.40, 0.14), (0.13, 0.25, 0.10), (0.30, 0.43, 0.15),
                                                                    (0.22, 0.34, 0.12)], 520, (24, 44), 0.0, 701, star=True)


def olive():
    return foliage("olive", (0.17, 0.22, 0.12), (0.28, 0.34, 0.20), [(0.38, 0.46, 0.26), (0.32, 0.40, 0.22), (0.44, 0.52, 0.32), (0.26, 0.34, 0.18)],
                   1500, (12, 22), 0.20, 702, back=(0.66, 0.70, 0.58))


def busch():
    return foliage("busch", (0.06, 0.12, 0.05), (0.12, 0.21, 0.08), [(0.14, 0.27, 0.08), (0.20, 0.34, 0.10), (0.11, 0.22, 0.07), (0.26, 0.36, 0.11),
                                                                    (0.30, 0.38, 0.12)], 1500, (11, 20), 0.46, 703)


def zypresse():
    return foliage("zypresse", (0.03, 0.08, 0.04), (0.07, 0.14, 0.06), [(0.07, 0.16, 0.07), (0.10, 0.20, 0.08), (0.05, 0.12, 0.06), (0.12, 0.22, 0.09)],
                   2400, (8, 14), 0.40, 704)


def agave():
    """Fleischige blaugrüne Blätter."""
    rng = np.random.default_rng(705)
    n = 512
    n1 = pink(1.5, 7051, n)
    base = mixc(np.array([0.22, 0.34, 0.26]), np.array([0.34, 0.48, 0.38]), smooth(n1, -1.0, 1.0))
    ly = Layer(base, n)
    for _ in range(700):
        x, y = rng.uniform(0, n, 2)
        ln = rng.uniform(26, 60)
        rot = math.pi / 2 + rng.normal(0, 0.12)
        col = jitter(rng, [(0.30, 0.46, 0.38), (0.36, 0.52, 0.42), (0.26, 0.40, 0.32), (0.42, 0.56, 0.44)][rng.integers(4)], 0.10)
        ly.poly(leaf_pts(x, y, ln, ln * 0.2, rot), col, 150)
    rgb, _ = ly.result()
    Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(SRC, "agave.jpg"), quality=90)
    return rgb


def opuntie():
    """Feigenkaktus: grüne Glieder mit hellen Areolen."""
    rng = np.random.default_rng(706)
    n = 512
    n1 = pink(1.5, 7061, n)
    base = mixc(np.array([0.20, 0.34, 0.14]), np.array([0.30, 0.46, 0.20]), smooth(n1, -1.0, 1.0))
    ly = Layer(base, n)
    for _ in range(46):
        x, y = rng.uniform(0, n, 2)
        col = jitter(rng, [(0.26, 0.42, 0.16), (0.32, 0.48, 0.20), (0.22, 0.38, 0.14)][rng.integers(3)], 0.10)
        ly.ellipse(x, y, rng.uniform(26, 42), rng.uniform(34, 56), rng.uniform(0, 3.14), col, 150, 18)
    for _ in range(420):
        x, y = rng.uniform(0, n, 2)
        ly.ellipse(x, y, 1.6, 1.6, 0, (0.84, 0.80, 0.50), 200, 6)
    rgb, _ = ly.result()
    Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(SRC, "opuntie.jpg"), quality=90)
    return rgb


def rinde():
    """Borke (senkrechte Furchen), graubraun, nahtlos (n = 512)."""
    rng = np.random.default_rng(707)
    n = 512
    n1 = pink(1.6, 7071, n)
    warp = ndi.gaussian_filter(rng.standard_normal((n, n)).astype(np.float32), (30, 3), mode="wrap")
    warp = warp / (warp.std() + 1e-6)
    x = np.arange(n)[None, :] + np.zeros((n, 1))
    ridge = np.abs(np.sin((x / n * 22 * math.pi) + warp * 2.0)) ** 0.7
    fine = ndi.gaussian_filter(rng.standard_normal((n, n)).astype(np.float32), (14, 1.0), mode="wrap")
    fine = fine / (fine.std() + 1e-6)
    rgb = mixc(np.array([0.13, 0.095, 0.07]), np.array([0.40, 0.32, 0.24]), np.clip(ridge * 0.8 + 0.12 * fine + 0.1 * n1, 0, 1))
    Image.fromarray((np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(SRC, "rinde.jpg"), quality=90)
    return rgb


def build():
    big = [boden_trockengras(), boden_kalk(), boden_terrarossa()]
    small = [fels(), mauer(), rinde(), kiefer(), olive(), busch(), zypresse(), agave(), opuntie()]
    return big, small


if __name__ == "__main__":
    big, small = build()
    if SHEET:
        tiles = [np.tile(b, (2, 2, 1))[::2, ::2] for b in big] + [np.tile(s, (2, 2, 1)) if s.shape[0] < N else s for s in small]
        ims = [Image.fromarray((np.clip(t, 0, 1) * 255 + 0.5).astype(np.uint8)).resize((384, 384)) for t in tiles]
        cols = 4
        rows = (len(ims) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * 384, rows * 384))
        for i, t in enumerate(ims):
            sheet.paste(t, ((i % cols) * 384, (i // cols) * 384))
        sheet.save(SHEET)
    with open(os.path.join(OUT, "HERKUNFT.md"), "w", encoding="utf-8") as fh:
        fh.write("# Texturen des Serra-Pass-Dioramen (Thema mountain)\n\n"
                 "Alles prozedural erzeugt mit `tools/make_mountain_textures.py` (numpy, scipy, Pillow), kein fremdes Material.\n\n"
                 "- `boden_trockengras`, `boden_kalk`, `boden_terrarossa` (+ `_n` Normalkarten): Bodenmischung des Dioramen (`ground_set`).\n"
                 "- `quelle/`: Texturen für in Blender gebaute Teile (Fels, Trockenmauer, Kiefer, Olive, Macchia, Zypresse, Agave, Opuntie, Borke);\n"
                 "  der Ordner ist per `.gdignore` vom Godot-Import ausgenommen, die Bilder stecken eingebettet in `game/dioramas/serra.glb`.\n"
                 "- Kapelle, Leuchtturm, Aussichtsplattform: KI-Modelle aus `game/assets/props/serra_*` (Herkunft dort dokumentiert); sie bleiben Laufzeit-Bauteile.\n")
    print("Serra-Texturen:", OUT)
