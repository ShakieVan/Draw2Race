"""Baumkarten (Billboards) aus den freigestellten Bildvorlagen: auf das Motiv zuschneiden, Höhe 512 px, PNG mit
Transparenz. Ergebnis game/assets/cards/<name>.png. Ein Baum ist im Spiel dann nur noch eine Bildkarte
(2 Dreiecke) statt eines 3D-Modells mit tausenden Dreiecken.
Aufruf: python tools/make_cards.py
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "art" / "bildvorlagen" / "freigestellt"
DST = ROOT / "game" / "assets" / "cards"
TREES = ["wald_kiefer", "wald_eiche", "kueste_palme", "stadt_baum", "serra_olivenbaum", "serra_pinie"]
HEIGHT = 512


def main():
    DST.mkdir(parents=True, exist_ok=True)
    for name in TREES:
        img = Image.open(SRC / f"{name}.png").convert("RGBA")
        box = img.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox()
        img = img.crop(box)
        # Weiße Säume entfernen: Die Vorlagen standen auf Weiß, Randpixel der Blätter sind mit Weiß vermischt.
        # 1) helle, kaum gesättigte Pixel sind Hintergrundreste -> transparent;
        # 2) Maske um 2 px verkleinern (nur Kerne der Blätter bleiben).
        import numpy as np
        from PIL import ImageFilter
        a = np.asarray(img).astype(np.float32)
        rgb = a[:, :, :3] / 255.0
        hi = rgb.max(axis=2)
        lo = rgb.min(axis=2)
        sat = np.where(hi > 0, (hi - lo) / np.maximum(hi, 1e-3), 0)
        alpha = a[:, :, 3]
        # nur in einem 4-px-Streifen am Rand, damit helle Rinde und Lichter im Inneren bleiben
        clear = Image.fromarray((alpha < 128).astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(9))
        band = np.asarray(clear) > 0
        alpha[(hi > 0.8) & (sat < 0.14)] = 0            # fast reines Weiß überall (Hintergrundreste zwischen Ästen)
        alpha[band & (hi > 0.58) & (sat < 0.30)] = 0
        mask = Image.fromarray((alpha > 128).astype(np.uint8) * 255).filter(ImageFilter.MinFilter(5))
        a[:, :, 3] = np.asarray(mask)
        img = Image.fromarray(a.astype(np.uint8), "RGBA")
        w = max(1, round(img.width * HEIGHT / img.height))
        img = img.resize((w, HEIGHT), Image.LANCZOS)
        # Randfarbe in transparente Pixel ausbluten lassen: keine hellen Säume beim Filtern.
        rgb = Image.new("RGBA", img.size, (0, 0, 0, 0))
        solid = img.copy()
        for _ in range(4):
            grown = solid.filter(__import__("PIL.ImageFilter", fromlist=["MaxFilter"]).MaxFilter(3))
            mask = solid.getchannel("A").point(lambda a: 255 if a > 0 else 0)
            grown.paste(solid, (0, 0), mask)
            solid = grown
        out = Image.merge("RGBA", (*solid.convert("RGB").split(), img.getchannel("A")))
        out.save(DST / f"{name}.png")
        print(name, out.size)


if __name__ == "__main__":
    main()
