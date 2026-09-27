"""Stellt die Bildvorlagen frei (weißer Hintergrund -> transparent) für die Bild-zu-3D-Umrechnung.

Die Bild-KI liefert Motive auf sehr gleichmäßigem Weiß (≈253–254). Hintergrund = nahezu reines, ungefärbtes Weiß,
das mit dem Bildrand verbunden ist. Bei durchbrochenen Motiven (Pflanzen, Gitter, Zäune, Laternen) werden auch
eingeschlossene größere Weißflächen entfernt; bei Autos und Gebäuden nicht (weißer Lack/Putz bliebe sonst löchrig).
Kanten werden um 1 px geglättet.
Aufruf: python tools/cutout.py [name ...]   (ohne Namen: alle Bilder)
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

BASE = Path(__file__).resolve().parents[1] / "art" / "bildvorlagen"
SRC = BASE / "bilder"
DST = BASE / "freigestellt"
# Motive mit Durchblicken: eingeschlossene Weißflächen gelten ebenfalls als Hintergrund.
OPEN = ("palme", "baum", "busch", "eiche", "kiefer", "absperrung", "tribuene", "flutlicht", "laterne", "zaun",
        "leitplanke", "wegweiser", "bank", "sonnenschirm", "pflanzkuebel", "steg", "zeitnahme")


def cutout(path: Path) -> Path:
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(np.int16)
    lo = rgb.min(axis=2)
    spread = rgb.max(axis=2) - lo
    white = (lo >= 246) & (spread <= 6)
    labels, count = ndimage.label(white)
    border = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))) - {0}
    background = np.isin(labels, list(border))
    if any(key in path.stem for key in OPEN):
        sizes = ndimage.sum(white, labels, index=np.arange(1, count + 1))
        big = [i + 1 for i, size in enumerate(sizes) if size >= 60]
        background |= np.isin(labels, big)
    # Helle Säume am Rand (Antialiasing gegen Weiß) mitnehmen, dann weich auslaufen lassen.
    near = (lo >= 236) & (spread <= 10)
    background |= ndimage.binary_dilation(background, iterations=1) & near
    alpha = np.where(background, 0, 255).astype(np.uint8)
    alpha_img = Image.fromarray(alpha).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.7))
    out = Image.fromarray(rgb.astype(np.uint8)).convert("RGBA")
    out.putalpha(alpha_img)
    DST.mkdir(exist_ok=True)
    target = DST / path.name
    out.save(target)
    return target


if __name__ == "__main__":
    names = sys.argv[1:]
    files = [SRC / f"{n}.png" for n in names] if names else sorted(SRC.glob("*.png"))
    for f in files:
        t = cutout(f)
        a = np.asarray(Image.open(t))[:, :, 3]
        print(f"{f.stem}: {100 * (a > 128).mean():.1f} % Motiv")
