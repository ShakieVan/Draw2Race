"""Schnellvorschau für das Hafen-Themenmodul (tools/dio_themes/harbor.py) OHNE Blender.

Die reinen Python-Teile des Kerns (tools/diorama.py: Mittellinie, Frame, flat/wall/box, collide_*, Absperrschranken, Zuschauer-Helfer)
werden aus dem Quelltext herausgeschnitten und mit Ersatzteilen für bpy/bmesh ausgeführt; danach laufen die Hooks des Themas.
Die entstandenen Flächen zeichnet ein einfacher Maler-Algorithmus (schräge Parallelprojektion) in ein Bild. Zweck: Anordnung, Maße und
Erkennbarkeit der Bauten in Sekunden prüfen, bevor Blender und Godot (gemeinsame Sperren) laufen. Das ist NICHT das Spielbild:
keine Beleuchtung durch die Engine, keine Texturen, keine gebackene Umgebungsverdeckung.

Aufruf:  python tools/make_harbor_preview.py <harbor|arena> <aus.png> [x0 z0 x1 z1 [Pixel je m [Neigung Grad]]]
         (Python mit numpy und Pillow, z. B. E:/Draw2Race-AudioLab/analyse/.venv/Scripts/python.exe)
"""
import ast
import json
import math
import os
import random
import re
import sys
import types

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))


class Vector:
    """Minimaler Ersatz für mathutils.Vector (2D/3D)."""

    def __init__(self, v=(0.0, 0.0)):
        self.v = [float(a) for a in (v.v if isinstance(v, Vector) else v)]

    x = property(lambda s: s.v[0], lambda s, a: s.v.__setitem__(0, a))
    y = property(lambda s: s.v[1], lambda s, a: s.v.__setitem__(1, a))
    z = property(lambda s: s.v[2], lambda s, a: s.v.__setitem__(2, a))

    def __iter__(self):
        return iter(self.v)

    def __len__(self):
        return len(self.v)

    def __getitem__(self, i):
        return self.v[i]

    def __add__(self, o):
        return Vector([a + b for a, b in zip(self.v, o)])

    def __sub__(self, o):
        return Vector([a - b for a, b in zip(self.v, o)])

    def __mul__(self, k):
        return Vector([a * k for a in self.v])

    __rmul__ = __mul__

    def __truediv__(self, k):
        return Vector([a / k for a in self.v])

    def __neg__(self):
        return Vector([-a for a in self.v])

    def dot(self, o):
        return sum(a * b for a, b in zip(self.v, o))

    @property
    def length(self):
        return math.sqrt(sum(a * a for a in self.v))

    def normalized(self):
        n = self.length or 1.0
        return Vector([a / n for a in self.v])

    def lerp(self, o, t):
        return Vector([a + (b - a) * t for a, b in zip(self.v, o)])

    def copy(self):
        return Vector(self.v)

    def __repr__(self):
        return "Vector(%s)" % self.v


def load_core(track_id, theme_path=None):
    """Kern-Teile ausführen und ein Namensraum wie in diorama.py zurückgeben (mit aufzeichnendem mesh_object)."""
    src = open(os.path.join(ROOT, "tools", "diorama.py"), encoding="utf-8").read()
    lines = src.split("\n")

    def between(start, end):
        a = next(i for i, l in enumerate(lines) if l.startswith(start))
        b = next(i for i, l in enumerate(lines) if i > a and l.startswith(end))
        return "\n".join(lines[a:b])

    path = os.path.join(ROOT, "game", "tracks", track_id + ".json")
    data = json.load(open(path, encoding="utf-8"))
    ns = {"__name__": "core", "json": json, "math": math, "os": os, "random": random, "re": re, "sys": sys, "np": np, "Vector": Vector}
    ns.update(data=data, HW=float(data.get("half_width", 3.5)), THEME=data.get("theme", "city"), TRACK_ID=str(data.get("id", track_id)),
              OPEN=bool(data.get("open", False)), CITY=False, TRACK=path, TEX=os.path.join(ROOT, "art", "texturen"),
              PROPS=os.path.join(ROOT, "game", "assets", "props"), rng=random.Random(3))
    ns["THEME_FILE"] = theme_path or os.path.join(ROOT, "tools", "dio_themes", ns["THEME"] + ".py")
    exec("ROAD_Y, KERB_Y, WALK_Y = 0.17, 0.30, 0.30\nY_J, Y_K, Y_W = ROAD_Y + 0.006, KERB_Y + 0.002, WALK_Y + 0.002\n"
         "KERB_W, WALK_W = 0.55, 3.45\nSIDE = KERB_W + WALK_W\nFOOT = HW + SIDE\n", ns)
    # Themenmodul wie im Kern: direkt nach dem Laden der Streckendaten (Mittellinie existiert noch nicht)
    ns["THEME_CFG"] = {}
    for hook in ("theme_materials", "theme_ground", "theme_scenery", "theme_layout"):
        ns[hook] = lambda *a: None
    ns["theme_bake_hidden"] = lambda: []
    tp = ns["THEME_FILE"]
    if os.path.isfile(tp):
        exec(compile(open(tp, encoding="utf-8").read(), tp, "exec"), ns)
    cfg = {"road": "city" if False else "painted", "ground_y": 0.185, "margin": 34.0, "portal": False, "crowd": False, "baked": [], "runtime_terrain": False,
           "edge_out": None, "edge_in": None, "vertex_colors": "ACTIVE", "junctions": False}
    cfg.update(ns["THEME_CFG"])
    if cfg.get("road") == "runtime" and "ground_y" not in ns["THEME_CFG"]:
        cfg["ground_y"] = 0.08
    ns["CFG"] = cfg
    ns["ROAD_MODE"] = cfg["road"]
    ns["GROUND_Y"] = float(cfg["ground_y"])
    ns["MARGIN"] = float(cfg["margin"])
    exec(between("def resample", "# ---------------------------------------------------------------- Materialien"), ns)
    ns["M"] = {}

    def material(name, tex=None, rough=0.8, normal=None, color=None):
        return {"name": name, "tex": tex, "color": color}

    ns["material"] = material
    ns["tex"] = lambda name, kind="Color": os.path.join(ns["TEX"], name, f"{name}_1K-JPG_{kind}.jpg")
    for k_, c_ in (("asphalt", None), ("linie", (0.86, 0.84, 0.78)), ("beton", None), ("rot", (0.82, 0.08, 0.05)), ("weiss", (0.9, 0.9, 0.87)),
                   ("orange", (0.95, 0.42, 0.05)), ("gummi", (0.035, 0.035, 0.04)), ("dunkel", (0.012, 0.012, 0.016)), ("blau", (0.03, 0.2, 0.68)),
                   ("gelb", (0.96, 0.74, 0.04)), ("stahl", (0.62, 0.64, 0.68)), ("holz", (0.34, 0.17, 0.07)), ("wasser", (0.1, 0.28, 0.33))):
        ns["M"][k_] = material("D_" + k_, color=c_)
    ns["theme_materials"]()                                   # wie im Kern: vor Netz-Helfern, Rauschen, x0 ... (nur Mittellinie und material() stehen bereit)
    exec(between("class Frame:", "def mesh_object"), ns)
    objects = {}
    ns["OBJECTS"] = objects

    class Obj:
        def __init__(self, name, parts):
            self.name, self.parts = name, parts

    def mesh_object(name, parts):
        o = Obj(name, parts)
        objects[name] = o
        return o

    ns["mesh_object"] = mesh_object
    exec(between("def mesh_objects", "# ---------------------------------------------------------------- Kreuzungen und Seitenstra"), ns)
    exec(between("placed = []", "def build_arm"), ns)
    exec(between("def rect_corners", "LOD_DIST"), ns)
    exec("xs, zs = C[:, 0], C[:, 1]\nx0, x1 = math.floor(xs.min() - MARGIN), math.ceil(xs.max() + MARGIN)\n"
         "z0, z1 = math.floor(zs.min() - MARGIN), math.ceil(zs.max() + MARGIN)", ns)
    exec(between("_noise_rng = np.random", "if CITY:"), ns)
    exec(between("lamp_pos = [", "def crowd_zone"), ns)
    ns["objs_ground"] = []
    ns["lamps"] = []
    ns["event_decals"] = []
    ns["LIB"] = {}
    ns["recipe"] = {"houses": [], "trees": []}
    class _Objs(list):
        def get(self, name):
            return None

    sys.path.insert(0, os.path.join(ROOT, "tools"))
    import kit_car as _kc
    ns["kit_car"] = _kc
    ns["bpy"] = types.SimpleNamespace(data=types.SimpleNamespace(objects=_Objs()))
    ns["place"] = lambda *a, **k: True
    ns["place_house"] = lambda *a, **k: True
    ns["ao_proxies"] = lambda *a, **k: 0
    ns["ao_proxy_objs"] = []
    ns["model"] = lambda name: (None, Vector((1, 1, 1)))
    return ns


def run_hooks(ns):
    for hook in ("theme_ground", "theme_scenery"):
        ns[hook]()
    layout = {"obstacles": ns["colliders"], "lamps": [], "baked": list(ns["CFG"]["baked"])}
    ns["theme_layout"](layout)
    return layout


# ---------------------------------------------------------------- Vorschau-Zeichnung (schräge Parallelprojektion, Maler-Algorithmus)
KEY_COLORS = {
    "gelaende": (0.62, 0.62, 0.60), "beton": (0.64, 0.64, 0.62), "asphalt": (0.30, 0.31, 0.32), "linie": (0.9, 0.9, 0.85), "gelb": (0.96, 0.74, 0.04),
    "rot": (0.82, 0.08, 0.05), "weiss": (0.9, 0.9, 0.87), "orange": (0.95, 0.42, 0.05), "gummi": (0.035, 0.035, 0.04), "dunkel": (0.05, 0.05, 0.06),
    "blau": (0.03, 0.2, 0.68), "stahl": (0.62, 0.64, 0.68), "holz": (0.34, 0.17, 0.07), "wasser": (0.10, 0.28, 0.33), "ao": (0.5, 0.5, 0.5),
}


def key_color(key, mats):
    m = mats.get(key)
    if isinstance(m, dict) and m.get("color"):
        return tuple(m["color"])
    if key in KEY_COLORS:
        return KEY_COLORS[key]
    h = (sum(ord(c) * (i + 3) for i, c in enumerate(key)) % 97) / 97.0
    return tuple(0.35 + 0.5 * v for v in (h, 1 - h, abs(0.5 - h) * 2))


def render(ns, out, box=None, ppm=6.0, tilt_deg=25.0, hide=()):
    objs = ns["OBJECTS"]
    x0, z0, x1, z1 = box or (ns["x0"], ns["z0"], ns["x1"], ns["z1"])
    T = math.radians(tilt_deg)
    sT, cT = math.sin(T), math.cos(T)
    W, H = int((x1 - x0) * ppm), int((z1 - z0) * ppm * cT + 60 * ppm * sT * 0.2)
    img = Image.new("RGB", (W, H), (60, 90, 110))
    dr = ImageDraw.Draw(img, "RGBA")
    mats = ns["M"]
    polys = []
    light = np.array([-0.35, 0.8, -0.45])
    light /= np.linalg.norm(light)
    for name, o in objs.items():
        if name.startswith(tuple(hide)):
            continue
        for part in o.parts:
            key, corners = part[0], part[1]
            colors = part[4] if len(part) > 4 and part[4] is not None else None
            P = np.array([(c[0], c[2], c[1]) for c in corners], float)       # (x, y hoch, z)
            if len(P) < 3:
                continue
            n = np.cross(P[1] - P[0], P[2] - P[0])
            ln = np.linalg.norm(n)
            if ln < 1e-9:
                continue
            n = n / ln
            facing = part[3] if len(part) > 3 else None
            if facing is not None:
                if n[0] * facing[0] + n[2] * facing[1] < 0:
                    n = -n
            elif n[1] < 0:
                n = -n
            shade = 0.45 + 0.55 * max(0.0, float(n @ light))
            base = np.array(key_color(key, mats))
            if colors is not None:
                cc = np.mean([np.array(c[:3]) for c in colors], 0)
                if key == "gelaende":
                    # Gewichte des Boden-Shaders (R Helligkeit, G Asphalt, B Verschleiß) in eine Näherungsfarbe übersetzen
                    conc = np.array((0.66, 0.66, 0.64)) * min(1.3, max(0.5, cc[0]))
                    asph = np.array((0.30, 0.30, 0.31))
                    wear = np.array((0.2, 0.19, 0.18))
                    base = conc * (1 - cc[1]) + asph * cc[1]
                    base = base * (1 - cc[2]) + wear * cc[2]
                elif key.startswith("cont_"):
                    base = 0.85 * np.clip(cc, 0, 1.5) ** (1 / 2.2)
                elif key == "wasser":
                    pass
                else:
                    base = base * np.clip(cc, 0, 2)
            col = np.clip(base * shade, 0, 1)
            # Projektion: Bild-x = x, Bild-y = z*cosT - y*sinT (Norden = oben)
            sx = (P[:, 0] - x0) * ppm
            sy = (P[:, 2] * cT - P[:, 1] * sT - z0 * cT) * ppm + 30 * ppm * sT * 0.2
            depth = P[:, 2].mean() * sT + P[:, 1].mean() * cT * 0.0 - P[:, 1].mean() * 0.0
            # Maler: weit entfernt (kleines z, niedrige Höhe) zuerst; Höhe zählt als näher
            order = P[:, 2].mean() * cT * 0.0 + P[:, 1].mean() * 1.0 + 0.0001 * P[:, 2].mean()
            polys.append((order, [(float(a), float(b)) for a, b in zip(sx, sy)], tuple(int(v * 255) for v in col), key))
    # Laufzeit-Fahrbahn (das Spiel baut sie): Band mit Randstein, damit die Anordnung beurteilt werden kann
    trk = ns.get("HB", {}).get("track")
    if trk is not None:
        def proj(x_, z_, y_):
            return ((x_ - x0) * ppm, (z_ * cT - y_ * sT - z0 * cT) * ppm + 30 * ppm * sT * 0.2)
        n_ = trk.count
        for i in range(n_):
            j = (i + 1) % n_
            for off0, off1, col_, y_ in ((-1.0, 1.0, (70, 80, 85), 0.17), (1.0, 1.55, (230, 110, 80), 0.28), (-1.55, -1.0, (230, 110, 80), 0.28)):
                quad = []
                for (ii, o) in ((i, off0), (i, off1), (j, off1), (j, off0)):
                    h_ = trk.HW[ii]
                    sgn_ = 1.0 if o >= 0 else -1.0
                    oo = o * h_ if abs(o) <= 1.0 else sgn_ * (h_ + (abs(o) - 1.0))
                    q_ = trk.P[ii] + trk.Lft[ii] * oo
                    quad.append(proj(float(q_[0]), float(q_[1]), y_))
                polys.append((y_ * 0.5, quad, col_, "road"))
    polys.sort(key=lambda t: t[0])
    for _, pts, col, key in polys:
        dr.polygon(pts, fill=col + (255,))
    img.save(out)
    return img


def draw_obstacles(img, ns, box, ppm, layout):
    x0, z0, x1, z1 = box
    dr = ImageDraw.Draw(img, "RGBA")
    cT = math.cos(math.radians(25.0))
    for o in layout["obstacles"]:
        if "r" in o:
            cx, cz = o["c"]
            r = o["r"]
            dr.ellipse([(cx - r - x0) * ppm, (cz - r - z0) * ppm * cT, (cx + r - x0) * ppm, (cz + r - z0) * ppm * cT], outline=(255, 0, 0, 200))


if __name__ == "__main__":
    track = sys.argv[1]
    out = sys.argv[2]
    ns = load_core(track)
    layout = run_hooks(ns)
    box = tuple(float(v) for v in sys.argv[3:7]) if len(sys.argv) >= 7 else None
    ppm = float(sys.argv[7]) if len(sys.argv) >= 8 else 6.0
    tilt = float(sys.argv[8]) if len(sys.argv) >= 9 else 25.0
    img = render(ns, out, box, ppm, tilt)
    print("Vorschau", out, img.size, "Objekte", len(ns["OBJECTS"]), "Flächen", sum(len(o.parts) for o in ns["OBJECTS"].values()),
          "Hindernisse", len(ns["colliders"]), "Laternen", len(ns["lamps"]))
