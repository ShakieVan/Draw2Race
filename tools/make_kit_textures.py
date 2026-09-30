"""Erzeugt die Bausatz-Texturen (Fassaden, Erdgeschosse, Dächer) für die prozeduralen Häuser der Dioramen.

Alles entsteht prozedural (numpy, scipy, Pillow), kein fremdes Material. Ergebnis in game/assets/kit/:
  <name>.png      Albedo (sRGB)          <name>_n.png  Normalkarte (OpenGL-Konvention, Y nach oben)
  <name>_e.png    Emission (RGB, nachts leuchtende Fenster; nur Fassaden und Erdgeschosse)
  kit.json        Kachelgröße in Metern und Pixeln je Textur (liest tools/diorama.py und das Spiel)
Aufruf: python tools/make_kit_textures.py [ausgabeordner] [--sheet kontaktbogen.png]
Alle Kacheln sind nahtlos (Elemente laufen umlaufend über den Rand, Rauschen ist periodisch).
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

SS = 2                                  # Überabtastung beim Zeichnen
_args = [a for a in sys.argv[1:] if not a.startswith("--")]
OUT = _args[0] if _args else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "assets", "kit")
SHEET = sys.argv[sys.argv.index("--sheet") + 1] if "--sheet" in sys.argv else None
os.makedirs(OUT, exist_ok=True)


def srgb(*c):
    """Farbe als 0..1 (sRGB) übernehmen."""
    return np.array(c, np.float32)


def mix(a, b, t):
    return a * (1 - t) + b * t


class Canvas:
    """Kachel mit Albedo, Höhe (Meter, für die Normalkarte) und Emission; Maße in Metern, y nach oben."""

    def __init__(self, w_px, h_px, tile_w, tile_h, seed):
        self.w, self.h = w_px * SS, h_px * SS
        self.tw, self.th = tile_w, tile_h
        self.px, self.py = self.w / tile_w, self.h / tile_h
        self.rgb = np.zeros((self.h, self.w, 3), np.float32)
        self.ht = np.zeros((self.h, self.w), np.float32)
        self.em = np.zeros((self.h, self.w, 3), np.float32)
        self.rng = np.random.default_rng(seed)
        yy, xx = np.mgrid[0:self.h, 0:self.w]
        self.X = ((xx + 0.5) / self.px).astype(np.float32)
        self.Y = (self.th - (yy + 0.5) / self.py).astype(np.float32)

    def noise(self, sigma_m, amp=1.0):
        """Periodisches, glattes Rauschen (Standardabweichung amp); Korrelationslänge sigma_m Meter."""
        n = self.rng.standard_normal((self.h, self.w)).astype(np.float32)
        n = ndi.gaussian_filter(n, (sigma_m * self.py, sigma_m * self.px), mode="wrap")
        return n / (n.std() + 1e-6) * amp

    def sl(self, x0, x1, y0, y1):
        c0, c1 = int(round(x0 * self.px)), int(round(x1 * self.px))
        r0, r1 = int(round((self.th - y1) * self.py)), int(round((self.th - y0) * self.py))
        return slice(max(r0, 0), min(r1, self.h)), slice(max(c0, 0), min(c1, self.w))

    def rect(self, x0, x1, y0, y1, color=None, height=None, add_height=None, emission=None, alpha=1.0, wrap=True):
        """Rechteck zeichnen (Albedo/Höhe/Emission); wrap: auch an den gegenüberliegenden Rändern (nahtlos)."""
        offsets = [(0.0, 0.0)]
        if wrap:
            offsets = [(dx, dy) for dx in (-self.tw, 0.0, self.tw) for dy in (-self.th, 0.0, self.th)]
        for dx, dy in offsets:
            if x1 + dx <= 0 or x0 + dx >= self.tw or y1 + dy <= 0 or y0 + dy >= self.th:
                continue
            s = self.sl(x0 + dx, x1 + dx, y0 + dy, y1 + dy)
            if color is not None:
                col = color(self.X[s], self.Y[s]) if callable(color) else np.asarray(color, np.float32)
                self.rgb[s] = self.rgb[s] * (1 - alpha) + col * alpha
            if height is not None:
                self.ht[s] = height
            if add_height is not None:
                self.ht[s] += add_height
            if emission is not None:
                self.em[s] = np.asarray(emission, np.float32)

    def shade_cavities(self, strength=0.5, sigma_m=0.05):
        """Vertiefungen dunkler, Erhabenes minimal heller (billige Umgebungsverdeckung aus der Höhenkarte)."""
        blur = ndi.gaussian_filter(self.ht, (sigma_m * self.py, sigma_m * self.px), mode="wrap")
        cav = np.clip(blur - self.ht, -0.05, 0.05) / 0.05
        self.rgb *= (1.0 - strength * np.clip(cav, 0, 1) + 0.15 * strength * np.clip(-cav, 0, 1))[..., None]

    def finish(self, name, normal_strength=1.0, emission=True):
        """Kachel herunterrechnen und als PNG schreiben; liefert die Albedo."""
        dhx = ndi.sobel(self.ht, axis=1, mode="wrap") / 8.0 * self.px
        dhy = ndi.sobel(self.ht, axis=0, mode="wrap") / 8.0 * self.py
        nx, ny, nz = -dhx * normal_strength, dhy * normal_strength, np.ones_like(dhx)

        def down(a):
            return a.reshape(self.h // SS, SS, self.w // SS, SS, *a.shape[2:]).mean((1, 3))
        nx, ny, nz = down(nx), down(ny), down(nz)
        ln = np.sqrt(nx * nx + ny * ny + nz * nz)
        normal = np.stack([nx / ln, ny / ln, nz / ln], -1) * 0.5 + 0.5
        albedo = down(self.rgb)
        Image.fromarray((np.clip(albedo, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, name + ".png"))
        Image.fromarray((np.clip(normal, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, name + "_n.png"))
        if emission:
            Image.fromarray((np.clip(down(self.em), 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, name + "_e.png"))
        return albedo


# ------------------------------------------------------------------ Wandflächen
def plaster(cv, base, mott=0.05, grain=0.025, streak=0.018):
    """Putz mit Wolkung, feinem Korn und senkrechten Läufern."""
    n = cv.noise(0.9, mott) + cv.noise(0.25, mott * 0.6)
    g = cv.noise(0.012, grain)
    s = ndi.gaussian_filter(cv.rng.standard_normal((cv.h, cv.w)).astype(np.float32), (1.2 * cv.py, 0.14 * cv.px), mode="wrap")
    s = s / (s.std() + 1e-6) * streak
    cv.rgb[:] = base[None, None, :] * (1.0 + n + g + s)[..., None]
    cv.ht[:] = cv.noise(0.02, 0.0015) + cv.noise(0.12, 0.002)


def bricks(cv, colors, course=0.075, length=0.25, mortar=0.011, mortar_col=(0.62, 0.6, 0.56)):
    """Backsteinverband (Läufer): je Stein Farbe und Höhe verschieden, Fugen vertieft."""
    row = np.floor(cv.Y / course).astype(np.int32)
    off = (row % 2) * length * 0.5
    xs = cv.X + off
    col = np.floor(xs / length).astype(np.int32)
    ncols = int(round(cv.tw / length))
    idx = (row * 7919 + (col % ncols) * 104729) % 9973
    rnd = (idx / 9973.0).astype(np.float32)
    pal = np.array(colors, np.float32)
    k = (rnd * (len(pal) - 1e-3)).astype(np.int32)
    base = pal[k]
    base = base * (1.0 + (((idx * 31) % 97) / 97.0 - 0.5) * 0.14)[..., None]
    fx = np.mod(xs, length)
    fy = np.mod(cv.Y, course)
    joint = (fx < mortar) | (fy < mortar)
    edge = np.minimum(np.minimum(fx, length - fx), np.minimum(fy, course - fy))
    cv.rgb[:] = np.where(joint[..., None], np.array(mortar_col, np.float32), base)
    cv.rgb *= (1.0 + cv.noise(0.5, 0.05) + cv.noise(0.015, 0.03))[..., None]
    cv.ht[:] = np.where(joint, -0.010, 0.0) + np.clip(edge / 0.004, 0, 1) * 0.004 + (rnd - 0.5) * 0.002


def window(cv, x0, y0, w, h, frame=0.06, frame_col=(0.92, 0.92, 0.9), glass=None, mullion_v=1, transom=0.68, sill=True,
           lintel=True, shutter=None, curtain=True, lit=0.4, em_col=None, depth=0.07, sill_col=(0.78, 0.76, 0.7)):
    """Fenster mit Rahmen, Sprossen, Glas (Himmelsverlauf), Vorhang, Sohlbank, Sturz, Läden; das Glas kann leuchten."""
    rng = cv.rng
    if glass is None:
        glass = (srgb(0.42, 0.52, 0.62), srgb(0.13, 0.18, 0.24))                 # oben hell, unten dunkel
    cv.rect(x0 - 0.02, x0 + w + 0.02, y0 - 0.02, y0 + h + 0.02, color=srgb(*frame_col) * 0.6, height=-depth * 0.4)
    if shutter is not None:
        sw = w * 0.5
        for xs_ in (x0 - sw - 0.03, x0 + w + 0.03):
            cv.rect(xs_, xs_ + sw, y0 - 0.02, y0 + h + 0.02, color=srgb(*shutter) * (0.9 + rng.random() * 0.2), height=0.02)
            n = int(h / 0.09)
            for k in range(n):                                                  # Lamellen
                yy = y0 + 0.05 + k * (h - 0.05) / n
                cv.rect(xs_, xs_ + sw, yy, yy + 0.02, color=srgb(*shutter) * 0.72, height=0.012)
    cv.rect(x0, x0 + w, y0, y0 + h, color=srgb(*frame_col), height=-depth * 0.5)
    gx0, gx1, gy0, gy1 = x0 + frame, x0 + w - frame, y0 + frame, y0 + h - frame
    top, bot = glass

    def glass_fill(X, Y):
        t = np.clip((Y - gy0) / max(gy1 - gy0, 1e-3), 0, 1)[..., None]
        return mix(bot, top, t ** 1.4)
    cv.rect(gx0, gx1, gy0, gy1, color=glass_fill, height=-depth)
    if curtain and rng.random() < 0.55:
        cc = [srgb(0.86, 0.82, 0.7), srgb(0.75, 0.78, 0.82), srgb(0.9, 0.86, 0.8), srgb(0.62, 0.5, 0.42), srgb(0.8, 0.7, 0.6)][rng.integers(0, 5)]
        cv.rect(gx0, gx1, gy1 - (gy1 - gy0) * rng.uniform(0.25, 0.7), gy1, color=cc, alpha=0.8, height=-depth * 0.9)
    for k in range(1, mullion_v + 1):
        xm = gx0 + (gx1 - gx0) * k / (mullion_v + 1)
        cv.rect(xm - 0.02, xm + 0.02, gy0, gy1, color=srgb(*frame_col), height=-depth * 0.3)
    if transom:
        ym = gy0 + (gy1 - gy0) * transom
        cv.rect(gx0, gx1, ym - 0.02, ym + 0.02, color=srgb(*frame_col), height=-depth * 0.3)
    if sill:
        cv.rect(x0 - 0.12, x0 + w + 0.12, y0 - 0.11, y0 - 0.0, color=srgb(*sill_col), height=0.07)
        cv.rect(x0 - 0.12, x0 + w + 0.12, y0 - 0.115, y0 - 0.10, color=srgb(*sill_col) * 0.55, height=0.0)
    if lintel:
        cv.rect(x0 - 0.14, x0 + w + 0.14, y0 + h + 0.02, y0 + h + 0.2, color=srgb(*sill_col) * 1.02, height=0.045)
    if em_col is not None and rng.random() < lit:
        c = np.array(em_col, np.float32) if rng.random() > 0.15 else np.array([0.62, 0.78, 1.0], np.float32)   # selten bläulich (Fernseher)
        cv.rect(gx0, gx1, gy0, gy1, emission=c * rng.uniform(0.6, 1.0))


def dirt(cv, amount=0.12):
    """Verschmutzung: dunkle Läufer nach unten."""
    s = ndi.gaussian_filter(cv.rng.standard_normal((cv.h, cv.w)).astype(np.float32), (0.9 * cv.py, 0.14 * cv.px), mode="wrap")
    s = np.clip(s / (s.std() + 1e-6), -1, 2)
    cv.rgb *= (1.0 - amount * 0.5 * np.clip(s, 0, 2))[..., None]


# ------------------------------------------------------------------ Fassaden
def facade_altbau(seed=1):
    cv = Canvas(1024, 512, 12.8, 6.4, seed)
    plaster(cv, srgb(0.87, 0.84, 0.77))
    for f in range(2):
        yf = f * 3.2
        cv.rect(0, cv.tw, yf + 2.96, yf + 3.1, color=srgb(0.92, 0.9, 0.84), height=0.05)                # Gurtgesims
        cv.rect(0, cv.tw, yf + 2.9, yf + 2.96, color=srgb(0.5, 0.48, 0.44), height=0.0)
        for b in range(4):
            cx = b * 3.2 + 1.6
            shut = (0.27, 0.42, 0.32) if cv.rng.random() < 0.22 else ((0.45, 0.3, 0.2) if cv.rng.random() < 0.1 else None)
            window(cv, cx - 0.62, yf + 0.85, 1.24, 1.75, frame_col=(0.93, 0.92, 0.88), shutter=shut, lit=0.42, em_col=(1.0, 0.82, 0.5))
    for b in range(4):                                                                                   # Lisenen
        xb = b * 3.2
        cv.rect(xb - 0.09, xb + 0.09, 0, cv.th, color=srgb(0.91, 0.89, 0.83), height=0.025)
    dirt(cv, 0.14)
    cv.shade_cavities(0.6)
    return cv


def facade_backstein(seed=2):
    cv = Canvas(1024, 512, 12.0, 6.0, seed)
    bricks(cv, [srgb(0.55, 0.27, 0.2), srgb(0.6, 0.31, 0.22), srgb(0.5, 0.24, 0.19), srgb(0.62, 0.36, 0.26), srgb(0.44, 0.22, 0.18)])
    for f in range(2):
        yf = f * 3.0
        cv.rect(0, cv.tw, yf + 2.82, yf + 2.98, color=srgb(0.82, 0.8, 0.74), height=0.03)              # helles Gesims
        for b in range(4):
            cx = b * 3.0 + 1.5
            fc = (0.94, 0.94, 0.92) if cv.rng.random() < 0.7 else (0.32, 0.22, 0.16)
            window(cv, cx - 0.55, yf + 0.9, 1.1, 1.55, frame_col=fc, mullion_v=1, transom=0.72, lit=0.45, em_col=(1.0, 0.78, 0.45),
                   sill_col=(0.72, 0.7, 0.64), lintel=False)
            cv.rect(cx - 0.68, cx + 0.68, yf + 2.47, yf + 2.56, color=srgb(0.7, 0.55, 0.45), height=0.02)   # Rollschicht
    dirt(cv, 0.2)
    cv.shade_cavities(0.6)
    return cv


def facade_riegel(seed=3):
    cv = Canvas(1024, 512, 14.4, 8.4, seed)
    plaster(cv, srgb(0.78, 0.78, 0.76), mott=0.05, grain=0.03, streak=0.03)
    for f in range(3):
        yf = f * 2.8
        for b in range(4):
            x0 = b * 3.6
            cv.rect(x0 - 0.012, x0 + 0.012, 0, cv.th, color=srgb(0.5, 0.5, 0.5), height=-0.01)          # Plattenfugen
        cv.rect(0, cv.tw, yf - 0.012, yf + 0.012, color=srgb(0.5, 0.5, 0.5), height=-0.01)
        for b in range(4):
            x0 = b * 3.6
            for k in range(2):
                window(cv, x0 + 0.45 + k * 1.6, yf + 0.85, 1.25, 1.25, frame=0.05, frame_col=(0.88, 0.88, 0.86), mullion_v=0, transom=0.0,
                       lintel=False, sill_col=(0.66, 0.66, 0.64), lit=0.4, em_col=(1.0, 0.85, 0.55), depth=0.05)
            if (b % 2 == 1 and f > 0) or (b % 2 == 0 and f == 0):                                      # Balkone
                cv.rect(x0 + 0.2, x0 + 3.4, yf - 0.02, yf + 0.12, color=srgb(0.7, 0.7, 0.68), height=0.35)
                cv.rect(x0 + 0.2, x0 + 3.4, yf + 0.12, yf + 1.0, color=srgb(0.4, 0.42, 0.44), alpha=0.35, height=0.36)
                for k in range(0, 33):
                    xx = x0 + 0.24 + k * 0.1
                    cv.rect(xx, xx + 0.02, yf + 0.12, yf + 1.0, color=srgb(0.32, 0.34, 0.36), height=0.4)
                cv.rect(x0 + 0.2, x0 + 3.4, yf + 0.98, yf + 1.04, color=srgb(0.3, 0.32, 0.34), height=0.42)
    dirt(cv, 0.22)
    cv.shade_cavities(0.55)
    return cv


def facade_buero(seed=4):
    cv = Canvas(1024, 512, 12.8, 7.2, seed)
    cv.rgb[:] = srgb(0.36, 0.4, 0.44)
    for f in range(2):
        yf = f * 3.6
        cv.rect(0, cv.tw, yf, yf + 0.95, color=srgb(0.27, 0.32, 0.37), height=0.0)                     # Brüstungspaneel
        for b in range(8):
            x0 = b * 1.6
            top = srgb(0.5, 0.62, 0.72) * cv.rng.uniform(0.85, 1.1)
            bot = srgb(0.1, 0.16, 0.22)
            gy0, gy1 = yf + 0.95, yf + 3.5
            cv.rect(x0 + 0.05, x0 + 1.55, gy0, gy1, color=lambda X, Y, t=top, bo=bot, a=gy0, b_=gy1: mix(bo, t, np.clip((Y - a) / (b_ - a), 0, 1)[..., None] ** 1.3),
                    height=-0.05)
            if cv.rng.random() < 0.33:                                                                  # Jalousie
                cv.rect(x0 + 0.05, x0 + 1.55, gy1 - cv.rng.uniform(0.4, 1.6), gy1, color=srgb(0.78, 0.75, 0.68), alpha=0.85, height=-0.045)
            if cv.rng.random() < 0.5:
                c = np.array([1.0, 0.95, 0.8], np.float32) if cv.rng.random() > 0.2 else np.array([0.75, 0.9, 1.0], np.float32)
                cv.rect(x0 + 0.05, x0 + 1.55, gy0, gy1, emission=c * cv.rng.uniform(0.55, 1.0))
            cv.rect(x0 - 0.05, x0 + 0.05, yf, yf + 3.6, color=srgb(0.17, 0.19, 0.21), height=0.04)      # Pfosten
        cv.rect(0, cv.tw, yf + 3.45, yf + 3.6, color=srgb(0.17, 0.19, 0.21), height=0.04)
        cv.rect(0, cv.tw, yf + 0.9, yf + 0.97, color=srgb(0.17, 0.19, 0.21), height=0.04)
    cv.rgb *= (1.0 + cv.noise(0.6, 0.03))[..., None]
    cv.shade_cavities(0.5)
    return cv


def facade_putz(seed=5):
    cv = Canvas(1024, 512, 13.6, 6.0, seed)
    plaster(cv, srgb(0.9, 0.89, 0.86), mott=0.035, grain=0.02, streak=0.012)
    for f in range(2):
        yf = f * 3.0
        for b in range(4):
            cx = b * 3.4 + 1.7
            window(cv, cx - 0.95, yf + 0.85, 1.9, 1.6, frame=0.08, frame_col=(0.2, 0.22, 0.24), mullion_v=1, transom=0.0, sill=True,
                   lintel=False, sill_col=(0.62, 0.62, 0.6), lit=0.45, em_col=(1.0, 0.85, 0.6), depth=0.09, curtain=True)
            if (b + f) % 3 == 0:                                                                        # französischer Balkon
                cv.rect(cx - 1.0, cx + 1.0, yf + 0.85, yf + 1.75, color=srgb(0.5, 0.65, 0.7), alpha=0.25, height=0.05)
                cv.rect(cx - 1.0, cx + 1.0, yf + 1.72, yf + 1.78, color=srgb(0.2, 0.22, 0.24), height=0.06)
    dirt(cv, 0.1)
    cv.shade_cavities(0.5)
    return cv


# ------------------------------------------------------------------ Erdgeschosse (3,6 m hoch)
def ground_laden(seed=6):
    cv = Canvas(1024, 256, 12.8, 3.6, seed)
    plaster(cv, srgb(0.82, 0.8, 0.75))
    cv.rect(0, cv.tw, 0, 0.5, color=srgb(0.42, 0.4, 0.38), height=0.02)                                 # Sockel
    shops = [(0.30, 0.55, 0.85), (0.72, 0.16, 0.14), (0.15, 0.4, 0.28), (0.9, 0.7, 0.15), (0.25, 0.25, 0.28), (0.55, 0.25, 0.5)]
    order = cv.rng.permutation(len(shops))
    for b in range(4):
        x0 = b * 3.2
        sc = srgb(*shops[order[b]])
        door = b in (1, 3)
        gx0, gx1 = x0 + 0.25, x0 + 2.95
        cv.rect(gx0 - 0.06, gx1 + 0.06, 0.45, 2.55, color=srgb(0.16, 0.17, 0.18), height=-0.05)
        top, bot = srgb(0.62, 0.66, 0.66), srgb(0.22, 0.24, 0.24)
        cv.rect(gx0, gx1, 0.5, 2.5, color=lambda X, Y, t=top, bo=bot: mix(bo, t, np.clip((Y - 0.5) / 2.0, 0, 1)[..., None] ** 1.5), height=-0.09)
        for k in range(cv.rng.integers(2, 5)):                                                          # Auslagen
            wx = cv.rng.uniform(gx0 + 0.1, gx1 - 0.5)
            cv.rect(wx, wx + cv.rng.uniform(0.25, 0.6), 0.55, 0.55 + cv.rng.uniform(0.3, 1.2), color=sc * cv.rng.uniform(0.6, 1.1), alpha=0.7, height=-0.085)
        cv.rect(gx0, gx1, 0.5, 2.5, emission=np.array([1.0, 0.92, 0.75], np.float32) * 0.85)
        for xm in np.linspace(gx0, gx1, 4)[1:-1]:
            cv.rect(xm - 0.03, xm + 0.03, 0.5, 2.5, color=srgb(0.16, 0.17, 0.18), height=-0.04)
        if door:
            dx0 = gx1 - 1.15
            cv.rect(dx0, gx1, 0.4, 2.6, color=srgb(0.15, 0.16, 0.17), height=-0.06)
            cv.rect(dx0 + 0.07, gx1 - 0.07, 0.5, 2.5, color=srgb(0.55, 0.6, 0.6), alpha=0.7, height=-0.1)
            cv.rect(dx0 + 0.07, gx1 - 0.07, 0.5, 2.5, emission=np.array([1.0, 0.92, 0.75], np.float32) * 0.6)
        cv.rect(x0 + 0.1, x0 + 3.1, 2.75, 3.4, color=sc * 0.9, height=0.05)                            # Schild
        cv.rect(x0 + 0.3, x0 + 2.9, 2.9, 3.2, color=srgb(0.96, 0.95, 0.92), alpha=0.85, height=0.06)
        cv.rect(x0 + 0.1, x0 + 3.1, 2.75, 3.4, emission=sc * 0.35)
        if cv.rng.random() < 0.5:                                                                       # Markise
            n = 8
            for k in range(n):
                cv.rect(x0 + 0.1 + k * 3.0 / n, x0 + 0.1 + (k + 1) * 3.0 / n, 2.5, 2.78, color=sc if k % 2 == 0 else srgb(0.95, 0.94, 0.9), height=0.1 - 0.02 * (k % 2))
    dirt(cv, 0.1)
    cv.shade_cavities(0.55)
    return cv


def ground_wohn(seed=7):
    cv = Canvas(1024, 256, 12.8, 3.6, seed)
    plaster(cv, srgb(0.82, 0.8, 0.75))
    for r in range(6):                                                                                  # Rustika-Sockel
        y0 = r * 0.17
        off = 0.0 if r % 2 == 0 else 0.35
        for k in range(0, 19):
            x0 = k * 0.7 + off
            if x0 + 0.7 > cv.tw + 1e-3:
                continue
            g = cv.rng.uniform(0.85, 1.1)
            cv.rect(x0 + 0.015, x0 + 0.685, y0 + 0.012, y0 + 0.158, color=srgb(0.66, 0.63, 0.58) * g, height=0.012)
    cv.rect(0, cv.tw, 1.0, 1.05, color=srgb(0.92, 0.9, 0.84), height=0.04)
    for b in range(4):
        x0 = b * 3.2
        if b in (1, 3):
            dx = x0 + 1.6                                                                               # Haustür mit Oberlicht
            cv.rect(dx - 0.85, dx + 0.85, 0.0, 2.75, color=srgb(0.86, 0.84, 0.78), height=0.04)
            cv.rect(dx - 0.6, dx + 0.6, 0.25, 2.3, color=srgb(0.30, 0.2, 0.13), height=-0.04)
            for r in range(3):
                cv.rect(dx - 0.5, dx - 0.05, 0.4 + r * 0.6, 0.85 + r * 0.6, color=srgb(0.36, 0.25, 0.17), height=-0.02)
                cv.rect(dx + 0.05, dx + 0.5, 0.4 + r * 0.6, 0.85 + r * 0.6, color=srgb(0.36, 0.25, 0.17), height=-0.02)
            cv.rect(dx - 0.6, dx + 0.6, 2.35, 2.65, color=srgb(0.3, 0.36, 0.4), height=-0.06)
            cv.rect(dx - 0.6, dx + 0.6, 2.35, 2.65, emission=np.array([1.0, 0.85, 0.55], np.float32) * 0.7)
            cv.rect(dx + 0.35, dx + 0.42, 1.0, 1.1, color=srgb(0.85, 0.75, 0.3), height=0.05)
        else:
            window(cv, x0 + 0.85, 1.35, 1.1, 1.4, frame_col=(0.93, 0.92, 0.88), lit=0.4, em_col=(1.0, 0.82, 0.5), sill_col=(0.72, 0.7, 0.64), lintel=False)
            for k in range(1, 6):                                                                       # Gitter
                xx = x0 + 0.85 + k * 1.1 / 6
                cv.rect(xx - 0.008, xx + 0.008, 1.35, 2.75, color=srgb(0.12, 0.12, 0.13), height=0.05)
    cv.rect(0, cv.tw, 3.35, 3.5, color=srgb(0.92, 0.9, 0.84), height=0.04)
    dirt(cv, 0.14)
    cv.shade_cavities(0.55)
    return cv


# ------------------------------------------------------------------ Dächer (4-m-Kachel)
def roof_kies(seed=11):
    cv = Canvas(512, 512, 4.0, 4.0, seed)
    base = srgb(0.5, 0.47, 0.42)
    n = cv.noise(0.015, 1.0)
    big = cv.noise(0.5, 1.0)
    speck = cv.rng.random((cv.h, cv.w)).astype(np.float32)
    cv.rgb[:] = base * (1 + 0.16 * n + 0.07 * big)[..., None]
    cv.rgb *= np.where(speck > 0.93, 1.35, np.where(speck < 0.07, 0.6, 1.0))[..., None]
    cv.ht[:] = n * 0.006
    return cv


def roof_bahn(seed=12):
    cv = Canvas(512, 512, 4.0, 4.0, seed)
    cv.rgb[:] = srgb(0.24, 0.25, 0.26)
    cv.rgb *= (1 + cv.noise(0.6, 0.12) + cv.noise(0.03, 0.05))[..., None]
    cv.ht[:] = cv.noise(0.03, 0.002)
    for k in range(4):                                                                                   # Bahnenstöße
        x = k * 1.0
        cv.rect(x - 0.02, x + 0.02, 0, cv.th, color=srgb(0.4, 0.4, 0.4), height=0.012)
    for k in range(int(cv.rng.integers(3, 7))):                                                          # Ausbesserungen
        x, y = cv.rng.uniform(0, 3.2), cv.rng.uniform(0, 3.2)
        cv.rect(x, x + cv.rng.uniform(0.3, 0.8), y, y + cv.rng.uniform(0.3, 0.8), color=srgb(0.2, 0.21, 0.22), alpha=0.6, height=0.006)
    return cv


def roof_ziegel(seed=13):
    cv = Canvas(512, 512, 4.0, 4.0, seed)
    rows, per = 10, 20
    course = cv.th / rows
    width = cv.tw / per
    row = np.floor(cv.Y / course).astype(np.int32)
    xs = cv.X + (row % 2) * width * 0.5
    col = np.floor(xs / width).astype(np.int32)
    rnd = (((row * 7919 + (col % per) * 104729) % 9973) / 9973.0).astype(np.float32)
    pal = np.array([srgb(0.62, 0.28, 0.17), srgb(0.7, 0.34, 0.2), srgb(0.55, 0.24, 0.16), srgb(0.66, 0.31, 0.21)], np.float32)
    base = pal[(rnd * 3.99).astype(np.int32)] * (0.9 + 0.25 * rnd)[..., None]
    fy = np.mod(cv.Y, course) / course
    fx = np.mod(xs, width) / width
    cv.rgb[:] = base * (0.72 + 0.28 * fy)[..., None] * (0.86 + 0.14 * np.sin(fx * math.pi))[..., None]
    cv.rgb *= (1 + cv.noise(0.5, 0.07))[..., None]
    cv.ht[:] = (fy * 0.05 + np.sin(fx * math.pi) * 0.02).astype(np.float32)
    return cv


def roof_schiefer(seed=14):
    cv = Canvas(512, 512, 4.0, 4.0, seed)
    rows, per = 14, 12
    course = cv.th / rows
    width = cv.tw / per
    row = np.floor(cv.Y / course).astype(np.int32)
    xs = cv.X + (row % 2) * width * 0.5
    col = np.floor(xs / width).astype(np.int32)
    rnd = (((row * 6271 + (col % per) * 92821) % 9967) / 9967.0).astype(np.float32)
    base = srgb(0.27, 0.3, 0.34) * (0.75 + 0.5 * rnd)[..., None]
    fy = np.mod(cv.Y, course) / course
    fxx = np.mod(xs, width) / width
    cv.rgb[:] = base * (0.7 + 0.3 * fy)[..., None]
    cv.rgb = np.where(((fxx < 0.03) | (fxx > 0.97))[..., None], cv.rgb * 0.5, cv.rgb)
    cv.rgb *= (1 + cv.noise(0.4, 0.06))[..., None]
    cv.ht[:] = (fy * 0.03 - ((fxx < 0.03) | (fxx > 0.97)) * 0.01).astype(np.float32)
    return cv


def roof_blech(seed=15):
    cv = Canvas(512, 512, 4.0, 4.0, seed)
    n = 8
    w = cv.tw / n
    cv.rgb[:] = srgb(0.42, 0.5, 0.47)
    for k in range(n):
        g = cv.rng.uniform(0.9, 1.1)
        cv.rect(k * w, (k + 1) * w, 0, cv.th, color=srgb(0.42, 0.5, 0.47) * g, height=0.0)
        cv.rect(k * w - 0.015, k * w + 0.015, 0, cv.th, color=srgb(0.55, 0.62, 0.58), height=0.02)
    cv.rgb *= (1 + cv.noise(0.8, 0.09))[..., None]
    return cv


TEXTURES = {
    "fassade_altbau": (facade_altbau, {"em": True, "role": "fassade"}),
    "fassade_backstein": (facade_backstein, {"em": True, "role": "fassade"}),
    "fassade_riegel": (facade_riegel, {"em": True, "role": "fassade"}),
    "fassade_buero": (facade_buero, {"em": True, "role": "fassade"}),
    "fassade_putz": (facade_putz, {"em": True, "role": "fassade"}),
    "sockel_laden": (ground_laden, {"em": True, "role": "sockel"}),
    "sockel_wohn": (ground_wohn, {"em": True, "role": "sockel"}),
    "dach_kies": (roof_kies, {"em": False, "role": "dach"}),
    "dach_bahn": (roof_bahn, {"em": False, "role": "dach"}),
    "dach_ziegel": (roof_ziegel, {"em": False, "role": "dach"}),
    "dach_schiefer": (roof_schiefer, {"em": False, "role": "dach"}),
    "dach_blech": (roof_blech, {"em": False, "role": "dach"}),
}

if __name__ == "__main__":
    spec = {}
    thumbs = []
    for name, (fn, meta) in TEXTURES.items():
        cv = fn()
        albedo = cv.finish(name, normal_strength=1.0, emission=meta["em"])
        spec[name] = {"tile_m": [cv.tw, cv.th], "size": [cv.w // SS, cv.h // SS], "role": meta["role"], "emission": meta["em"]}
        thumbs.append((name, albedo))
        print("TEX", name, spec[name]["size"], spec[name]["tile_m"])
    json.dump(spec, open(os.path.join(OUT, "kit.json"), "w"), indent=1)
    if SHEET:
        cols, cell = 3, 512
        rows = math.ceil(len(thumbs) / cols)
        sheet = Image.new("RGB", (cols * cell, rows * cell), (30, 30, 30))
        for i, (name, albedo) in enumerate(thumbs):
            im = Image.fromarray((np.clip(albedo, 0, 1) * 255).astype(np.uint8))
            im.thumbnail((cell - 4, cell - 4))
            sheet.paste(im, ((i % cols) * cell + 2, (i // cols) * cell + 2))
        sheet.save(SHEET)
