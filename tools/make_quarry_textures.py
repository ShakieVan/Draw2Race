"""Erzeugt die Texturen des Steinbruch-Dioramen (Thema "quarry"): alles prozedural (numpy, scipy, Pillow), kein fremdes Material.

Ergebnis in game/assets/dio/quarry/ (Mischung des Boden-Shaders, assets/ground_blend.gdshader; Normalkarte = Name + _n):
  boden_schotter(.jpg|_n.jpg)   gebrochener Kalkstein, Schotter in vielen Korngrößen mit Staub dazwischen   (Platz "grass")
  boden_staub(.jpg|_n.jpg)      trockener, lehmiger Staub mit Windspuren und Steinchen                       (Platz "sand")
  boden_fels(.jpg|_n.jpg)       Felswand: Kalkstein in Blöcken mit Klüften und Schichtung                    (Platz "dirt")
und für Blender (quelle/, dort ignoriert Godot den Ordner per .gdignore):
  quelle/fels.jpg, blockstein.jpg, container_rot.jpg, container_blau.jpg, container_gelb.jpg, wellblech.jpg
Alle Kacheln sind nahtlos (Rauschen im Frequenzraum, Voronoi-Zellen mit Umbruch an den Rändern).
Aufruf: python tools/make_quarry_textures.py [ausgabeordner] [--sheet kontaktbogen.png]
"""
import math
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi
from scipy.spatial import cKDTree

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET = sys.argv[sys.argv.index("--sheet") + 1] if "--sheet" in sys.argv else None
_args = [a for i, a in enumerate(sys.argv[1:], 1) if not a.startswith("--") and not (i > 1 and sys.argv[i - 1] == "--sheet")]
OUT = _args[0] if _args else os.path.join(ROOT, "game", "assets", "dio", "quarry")
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


def voronoi(n_pts, seed, n=N, warp=None):
    """Nahtlose Voronoi-Zellen: (Abstand zum nächsten Punkt F1, zum zweitnächsten F2, Zellennummer). warp = (dx, dy) verschiebt die Abfragepunkte."""
    r = np.random.default_rng(seed)
    pts = r.uniform(0, n, (n_pts, 2))
    big = np.concatenate([pts + np.array([dx * n, dy * n]) for dx in (-1, 0, 1) for dy in (-1, 0, 1)])
    ids = np.tile(np.arange(n_pts), 9)
    tree = cKDTree(big)
    yy, xx = np.mgrid[0:n, 0:n]
    qx, qy = xx.astype(np.float64), yy.astype(np.float64)
    if warp is not None:
        qx, qy = qx + warp[0], qy + warp[1]
    d, i = tree.query(np.stack([qx.ravel(), qy.ravel()], 1), k=2, workers=-1)
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


STONE = np.array([(0.74, 0.70, 0.62), (0.66, 0.63, 0.57), (0.80, 0.77, 0.70), (0.58, 0.55, 0.50), (0.69, 0.66, 0.60), (0.73, 0.64, 0.50),
                  (0.62, 0.60, 0.56), (0.84, 0.82, 0.76), (0.46, 0.44, 0.41)], np.float32)
STONE_P = np.array([0.20, 0.18, 0.12, 0.13, 0.16, 0.07, 0.06, 0.05, 0.03])


def boden_schotter():
    """Gebrochener Kalkstein: große Brocken über feinem Splitt, dazwischen heller Staub."""
    rng = np.random.default_rng(11)
    n1, n2, n3 = pink(2.6, 111), pink(1.8, 112), pink(1.0, 113)
    # feiner Splitt
    d1, d2, cid = voronoi(16000, 21)
    tone = STONE[rng.choice(len(STONE), 16000, p=STONE_P)] * rng.uniform(0.82, 1.1, (16000, 1)).astype(np.float32)
    fine = tone[cid]
    edge_f = smooth(d2 - d1, 0.0, 2.2)
    dome_f = 1.0 - smooth(d1, 0.0, 9.0)
    fine = fine * (0.55 + 0.45 * edge_f)[..., None] * (0.85 + 0.25 * dome_f)[..., None]
    h_fine = edge_f * 0.5 + dome_f * 0.4
    # größere Steine
    d1b, d2b, cidb = voronoi(1500, 22)
    toneb = STONE[rng.choice(len(STONE), 1500, p=STONE_P)] * rng.uniform(0.85, 1.08, (1500, 1)).astype(np.float32)
    big = toneb[cidb]
    edge_b = smooth(d2b - d1b, 0.0, 3.4)
    dome_b = 1.0 - smooth(d1b, 0.0, 22.0)
    big = big * (0.50 + 0.50 * edge_b)[..., None] * (0.80 + 0.35 * dome_b)[..., None]
    cover = smooth(n1 * 0.9 + n2 * 0.3, -0.1, 0.55)                           # wo die großen Steine liegen
    cover = np.where(rng.random(1500)[cidb] < 0.55, cover, 0.0)
    rgb = fine * (1 - cover[..., None]) + big * cover[..., None]
    h = h_fine * (1 - cover) + (edge_b * 0.9 + dome_b * 1.3) * cover
    # Staub in den Zwischenräumen und Flecken
    dust = np.array([0.66, 0.62, 0.55])
    dust_m = smooth(n2 - 0.3 * n3, 0.4, 1.4) * 0.45
    rgb = mixc(rgb, dust, dust_m)
    rgb *= (1.0 + 0.07 * n3 + 0.05 * n2)[..., None]
    save("schotter", rgb, np.zeros((N, N), np.float32), 0.0, SRC)
    return save("boden_schotter", rgb, h * 0.7, 3.0)


def boden_staub():
    """Trockener Lehmstaub: feines Korn, Windspuren, wenige Steinchen."""
    rng = np.random.default_rng(31)
    n1, n2, n3, n4 = pink(2.8, 311), pink(2.0, 312), pink(1.2, 313), pink(0.8, 314)
    dry = np.array([0.69, 0.62, 0.50])
    light = np.array([0.77, 0.71, 0.60])
    damp = np.array([0.54, 0.47, 0.37])
    rgb = mixc(dry, light, smooth(n1 * 0.8 + n2 * 0.4, -0.5, 1.2))
    rgb = mixc(rgb, damp, smooth(n2 - n1 * 0.4, 0.7, 1.7) * 0.5)
    rgb *= (1.0 + 0.06 * n3 + 0.05 * n4)[..., None]
    # Windspuren: feine, leicht gekrümmte Streifen
    yy, xx = np.mgrid[0:N, 0:N] / N
    ripple = np.sin(2 * math.pi * (xx * 6 + yy * 2 + pink(3.0, 315) * 0.06) * 3) * 0.5 + 0.5
    rgb *= (1.0 + 0.035 * (ripple - 0.5))[..., None]
    h = 0.5 * ripple + 0.6 * n4 + 0.3 * n3
    # Steinchen
    d1, d2, cid = voronoi(380, 32)
    tone = STONE[rng.choice(len(STONE), 380, p=STONE_P)][cid]
    stone_m = (rng.random(380)[cid] < 0.25) & (d1 < 7.0)
    stone_col = tone * (0.7 + 0.3 * (1.0 - smooth(d1, 0.0, 7.0)))[..., None]
    rgb = np.where(stone_m[..., None], stone_col, rgb)
    h = h + stone_m * (1.0 - smooth(d1, 0.0, 7.0)) * 2.0
    return save("boden_staub", rgb, h * 0.55, 2.0)


def boden_fels():
    """Felswand (Draufsicht und Seitenansicht): Kalksteinblöcke mit verzerrten Klüften, Schichtbänder, Flechten, Verwitterungsstreifen."""
    rng = np.random.default_rng(41)
    n1, n2, n3 = pink(2.2, 411), pink(1.5, 412), pink(0.9, 413)
    wx, wy = pink(2.6, 414) * 26.0, pink(2.6, 415) * 26.0
    d1, d2, cid = voronoi(52, 42, warp=(wx, wy))
    blk = STONE[rng.choice(len(STONE), 52, p=STONE_P)] * rng.uniform(0.84, 1.1, (52, 1)).astype(np.float32)
    rgb = blk[cid]
    wid = 2.5 + 3.5 * smooth(n2, -1.0, 1.5)
    crack = smooth(d2 - d1, 0.0, wid)
    rgb = rgb * (0.40 + 0.60 * crack)[..., None]
    # zweite, feinere Zerklüftung (schwach)
    e1, e2, ecid = voronoi(420, 43, warp=(wy * 0.5, wx * 0.5))
    fine = smooth(e2 - e1, 0.0, 2.0)
    rgb *= (0.88 + 0.12 * fine)[..., None]
    # Schichtung: ockerfarbene und graue Bänder (periodisch in y, verzerrt)
    yy = np.arange(N)[:, None] / N
    band = np.sin(2 * math.pi * (yy * 6 + n1 * 0.05 + wy / 400.0)) * 0.5 + 0.5
    rgb = mixc(rgb, rgb * np.array([1.07, 0.96, 0.80]), band * 0.55)
    lichen = smooth(n2 * 0.7 + n3 * 0.5, 0.9, 1.5) * (crack > 0.5)
    rgb = mixc(rgb, np.array([0.58, 0.60, 0.34]), lichen * 0.45)
    streak = ndi.gaussian_filter(rng.standard_normal((N, N)).astype(np.float32), (40, 1.5), mode="wrap")
    streak = streak / (streak.std() + 1e-6)
    rgb *= (1.0 - 0.12 * smooth(streak, 0.8, 2.0))[..., None]
    rgb *= (1.0 + 0.08 * n3)[..., None]
    h = (crack * 1.7 + fine * 0.5 + (1.0 - smooth(d1, 0.0, 90.0)) * 0.9) + 0.2 * n3
    return save("boden_fels", rgb, h * 1.2, 3.4)


def fels_quelle():
    """Fels für Findlinge und Blöcke (Blender): wie boden_fels, etwas kleinteiliger und dunkler in den Spalten."""
    rng = np.random.default_rng(51)
    n1, n3 = pink(2.0, 511), pink(0.9, 513)
    d1, d2, cid = voronoi(260, 52)
    blk = STONE[rng.choice(len(STONE), 260, p=STONE_P)] * rng.uniform(0.82, 1.1, (260, 1)).astype(np.float32)
    rgb = blk[cid]
    crack = smooth(d2 - d1, 0.0, 4.0)
    rgb = rgb * (0.35 + 0.65 * crack)[..., None]
    rgb *= (1.0 + 0.10 * n3 + 0.06 * n1)[..., None]
    return save("fels", rgb, np.zeros((N, N), np.float32), 0.0, SRC)


def blockstein():
    """Gesägter Naturstein (Blöcke): feine Sägespuren, Maserung, helle Kanten."""
    rng = np.random.default_rng(61)
    n1, n2, n3 = pink(2.4, 611), pink(1.4, 612), pink(0.8, 613)
    rgb = mixc(np.array([0.70, 0.66, 0.58]), np.array([0.78, 0.75, 0.68]), smooth(n1 * 0.7 + n2 * 0.4, -0.5, 1.0))
    yy = np.arange(N)[:, None] + np.zeros((1, N))
    saw = np.sin(yy * 0.9 + pink(2.0, 614) * 2.0) * 0.5 + 0.5
    rgb *= (1.0 + 0.05 * (saw - 0.5) + 0.05 * n3)[..., None]
    veins = smooth(np.abs(pink(1.6, 615)), 0.0, 0.1)
    rgb = mixc(rgb, rgb * 0.82, (1 - veins) * 0.35)
    return save("blockstein", rgb, np.zeros((N, N), np.float32), 0.0, SRC)


def container(name, base, seed):
    """Wellblech-Container: senkrechte Rippen, Rost an den Kanten, Kratzer."""
    rng = np.random.default_rng(seed)
    n1, n2, n3 = pink(2.2, seed + 1), pink(1.2, seed + 2), pink(0.7, seed + 3)
    xx = np.arange(N)[None, :] + np.zeros((N, 1))
    rib = np.sin(xx / N * 2 * math.pi * 24)
    shade = 0.78 + 0.22 * rib
    rgb = np.array(base, np.float32)[None, None, :] * shade[..., None]
    rgb *= (1.0 + 0.08 * n2 + 0.05 * n3)[..., None]
    rust = smooth(n1 * 0.8 + n3 * 0.5, 0.9, 1.7)
    rgb = mixc(rgb, np.array([0.38, 0.17, 0.08]), rust * 0.55)
    scratch = ndi.gaussian_filter(rng.standard_normal((N, N)).astype(np.float32), (35, 0.7), mode="wrap")
    scratch = scratch / (scratch.std() + 1e-6)
    rgb *= (1.0 + 0.05 * smooth(scratch, 1.0, 2.5))[..., None]
    return save(name, rgb, np.zeros((N, N), np.float32), 0.0, SRC)


def wellblech():
    rng = np.random.default_rng(71)
    n2, n3 = pink(1.4, 712), pink(0.8, 713)
    xx = np.arange(N)[None, :] + np.zeros((N, 1))
    rib = np.sin(xx / N * 2 * math.pi * 30)
    rgb = np.array([0.56, 0.58, 0.60], np.float32)[None, None, :] * (0.75 + 0.25 * rib)[..., None]
    rgb *= (1.0 + 0.10 * n2 + 0.06 * n3)[..., None]
    return save("wellblech", rgb, np.zeros((N, N), np.float32), 0.0, SRC)


def build():
    big = [boden_schotter(), boden_staub(), boden_fels()]
    small = [fels_quelle(), blockstein(), container("container_rot", (0.50, 0.16, 0.10), 80), container("container_blau", (0.10, 0.22, 0.46), 90),
             container("container_gelb", (0.78, 0.60, 0.10), 95), wellblech()]
    return big, small


if __name__ == "__main__":
    big, small = build()
    if SHEET:
        tiles = [np.tile(b, (2, 2, 1))[::2, ::2] for b in big] + small
        ims = [Image.fromarray((np.clip(t, 0, 1) * 255 + 0.5).astype(np.uint8)).resize((384, 384)) for t in tiles]
        cols = 3
        rows = (len(ims) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * 384, rows * 384))
        for i, t in enumerate(ims):
            sheet.paste(t, ((i % cols) * 384, (i // cols) * 384))
        sheet.save(SHEET)
    with open(os.path.join(OUT, "HERKUNFT.md"), "w", encoding="utf-8") as fh:
        fh.write("# Texturen des Steinbruch-Dioramen\n\n"
                 "Alles prozedural erzeugt mit `tools/make_quarry_textures.py` (numpy, scipy, Pillow), kein fremdes Material.\n\n"
                 "- `boden_schotter`, `boden_staub`, `boden_fels` (+ `_n` Normalkarten): Bodenmischung des Dioramen (`ground_set`).\n"
                 "- `quelle/`: Texturen für in Blender gebaute Teile (Findlinge, Natursteinblöcke, Container, Wellblech); der Ordner ist\n"
                 "  per `.gdignore` vom Godot-Import ausgenommen, die Bilder stecken eingebettet in `game/dioramas/quarry.glb`.\n"
                 "- Bagger, Kipper, Brecher, Förderband, Büro, Kieshaufen, Felswände: KI-Modelle aus `game/assets/props/steinbruch_*`\n"
                 "  (Herkunft dort dokumentiert); sie bleiben Laufzeit-Bauteile.\n")
    print("Steinbruch-Texturen:", OUT)
