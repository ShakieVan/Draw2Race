"""Erzeugt die Bodentextur „Sand“ für das Küsten-Diorama (prozedural, kein fremdes Material).

Ergebnis im Format der ambientCG-Ordner, damit tools/diorama.py sie wie die übrigen Bodentexturen lädt:
  <ordner>/SandProc/SandProc_1K-JPG_Color.jpg     Albedo (sRGB), nahtlos
  <ordner>/SandProc/SandProc_1K-JPG_NormalGL.jpg  Normalkarte (OpenGL, Y nach oben)
Inhalt: feine Körnung in zwei Größen, vom Wind gezeichnete Rippel (leicht gewellt), vereinzelte Muschelreste und Steinchen.
Aufruf: python tools/make_coast_textures.py [texturordner]   (Standard: art/texturen)
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "art", "texturen")
N = 1024
rng = np.random.default_rng(42)


def periodic_noise(scale_px, seed):
    """Nahtloses Rauschen: Zufallsfeld im Frequenzraum tiefpassgefiltert (periodisch über den Rand)."""
    r = np.random.default_rng(seed)
    f = np.fft.fft2(r.standard_normal((N, N)))
    ky = np.fft.fftfreq(N)[:, None]
    kx = np.fft.fftfreq(N)[None, :]
    k = np.sqrt(kx ** 2 + ky ** 2) * scale_px
    x = np.real(np.fft.ifft2(f * np.exp(-k ** 2)))
    return (x - x.mean()) / (x.std() + 1e-9)


y, x = np.mgrid[0:N, 0:N] / N
warp = periodic_noise(160, 3) * 0.035
ripple = np.sin(2 * np.pi * (x * 14 + y * 3 + warp * 6)) * 0.5 + 0.5          # periodisch: ganzzahlige Wellenzahlen
ripple = ripple ** 1.6
grain_f = periodic_noise(1.2, 5)
grain_c = periodic_noise(4.0, 7)
patch = periodic_noise(90, 11)
height = 0.55 * ripple + 0.25 * grain_c + 0.12 * grain_f + 0.2 * patch

base = np.array([0.86, 0.77, 0.58])
dark = np.array([0.74, 0.64, 0.47])
t = np.clip(0.5 + 0.22 * patch + 0.12 * grain_c - 0.18 * (1 - ripple), 0, 1)
col = base[None, None, :] * t[..., None] + dark[None, None, :] * (1 - t[..., None])
col *= (1.0 + 0.06 * grain_f)[..., None]
# Muschelreste (hell) und Steinchen (dunkel), wenige Bildpunkte groß, mit Umbruch an den Rändern
for k in range(260):
    cx, cy = rng.integers(0, N, 2)
    rad = rng.integers(2, 6)
    tone = np.array([0.95, 0.92, 0.86]) if rng.random() < 0.55 else np.array([0.45, 0.4, 0.36])
    yy, xx = np.ogrid[-rad:rad + 1, -rad:rad + 1]
    mask = (xx * xx + yy * yy) <= rad * rad
    ys = (np.arange(cy - rad, cy + rad + 1) % N)[:, None]
    xs = (np.arange(cx - rad, cx + rad + 1) % N)[None, :]
    region = col[ys, xs]
    region[mask] = region[mask] * 0.3 + tone * 0.7
    col[ys, xs] = region
    height[ys, xs] += mask * 0.6
height = ndi.gaussian_filter(height, 0.8, mode="wrap")
gy, gx = np.gradient(height)
strength = 2.2
nx, ny, nz = -gx * strength, gy * strength, np.ones_like(height)
norm = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
normal = np.stack([nx / norm, ny / norm, nz / norm], -1) * 0.5 + 0.5
folder = os.path.join(OUT, "SandProc")
os.makedirs(folder, exist_ok=True)
Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8)).save(os.path.join(folder, "SandProc_1K-JPG_Color.jpg"), quality=92)
Image.fromarray((normal * 255).astype(np.uint8)).save(os.path.join(folder, "SandProc_1K-JPG_NormalGL.jpg"), quality=92)
print("Sand-Textur:", folder)
