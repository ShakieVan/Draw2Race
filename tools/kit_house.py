"""Prozedurale Häuser (Bausatz) für die Dioramen: Wände mit Fassaden- und Erdgeschosskacheln, Dächer, Dachaufbauten.

Reine Geometrie ohne Blender-Abhängigkeit. Alle Koordinaten sind Spielkoordinaten (x, z) und Höhe y; ein Haus liefert
"Flächen" im Format von tools/diorama.py: (Materialschlüssel, Ecken [(x, z, y)], UVs, Blickrichtung (x, z) | None, Farben).
Die Materialschlüssel entsprechen den Texturen aus tools/make_kit_textures.py ("k:fassade_altbau", "k:dach_kies", …);
"k:farbe" ist einfarbig (nur Vertexfarbe). UVs sind in Kacheleinheiten (Meter / Kachelgröße), das Spiel setzt nur noch die
Texturen ein. Vertexfarben sind Multiplikatoren (linear): Putzfarbe des Hauses, Verschattung am Boden, Randschatten am Dach.

Ein Haus wird über ein Bezugssystem beschrieben: Mittelpunkt (cx, cz), Einheitsvektor u längs der Fassade, Einheitsvektor
f zur Straße (Vorderseite). Breite w liegt längs u, Tiefe d längs f. Maße werden auf Fensterfelder gerundet, damit an
den Ecken keine Fenster angeschnitten sind.
"""
import math
import random

GF = 3.6                  # Erdgeschosshöhe (= Kachelhöhe der Erdgeschosstexturen)
# Fassadenstile: Feldbreite (Meter) und Geschosshöhe der Obergeschosse; müssen zu tools/make_kit_textures.py passen.
STYLES = {
    "altbau": {"bay": 3.2, "fh": 3.2, "cornice": True},
    "backstein": {"bay": 3.0, "fh": 3.0, "cornice": True},
    "riegel": {"bay": 3.6, "fh": 2.8, "cornice": False},
    "buero": {"bay": 3.2, "fh": 3.6, "cornice": False},
    "putz": {"bay": 3.4, "fh": 3.0, "cornice": False},
}
SOCKEL_BAY = 3.2           # Feldbreite der Erdgeschosstexturen

# Putzfarben (sRGB, sichtbar); als lineare Vertexfarbe mit der grauweißen Putztextur malgenommen.
PLASTER = [(0.97, 0.93, 0.82), (0.96, 0.85, 0.66), (0.93, 0.74, 0.62), (0.85, 0.9, 0.8), (0.9, 0.9, 0.88), (0.84, 0.88, 0.93),
           (0.98, 0.96, 0.9), (0.94, 0.82, 0.74)]
BRICK_TINT = [(1.0, 1.0, 1.0), (0.94, 0.9, 0.86), (1.05, 0.98, 0.94)]

# Haustypen (Maße in Metern; w längs der Straße, d Tiefe; Geschosse einschließlich Erdgeschoss)
KINDS = {
    "reihenhaus": {"w": (6.0, 9.0), "d": (9.0, 13.0), "floors": (2, 3), "styles": ["altbau", "putz", "backstein"], "roof": ["gable"], "front": ["wohn"]},
    "stadthaus": {"w": (9.0, 14.0), "d": (10.0, 16.0), "floors": (3, 6), "styles": ["altbau", "backstein", "putz", "altbau"], "roof": ["flat", "hip", "flat"], "front": ["wohn", "laden", "laden"]},
    "eckhaus": {"w": (16.0, 24.0), "d": (16.0, 22.0), "floors": (4, 5), "styles": ["altbau", "backstein"], "roof": ["flat"], "front": ["laden"]},
    "riegel": {"w": (24.0, 36.0), "d": (11.0, 15.0), "floors": (5, 8), "styles": ["riegel"], "roof": ["flat"], "front": ["wohn"]},
    "buero": {"w": (16.0, 24.0), "d": (16.0, 26.0), "floors": (4, 7), "styles": ["buero"], "roof": ["flat"], "front": ["wohn"]},
}
WEIGHTS = {"reihenhaus": 14, "stadthaus": 42, "eckhaus": 10, "riegel": 14, "buero": 14}


def lin(c):
    return tuple(max(0.0, v) ** 2.2 for v in c)


def scale(c, k):
    return tuple(v * k for v in c)


def area(pts):
    s = 0.0
    for i in range(len(pts)):
        x0, z0 = pts[i]
        x1, z1 = pts[(i + 1) % len(pts)]
        s += x0 * z1 - x1 * z0
    return s / 2.0


def unit(x, z):
    n = math.hypot(x, z) or 1.0
    return x / n, z / n


def inset(pts, d):
    """Polygon um d nach innen (d < 0: nach außen), Gehrungsecken."""
    n = len(pts)
    ccw = area(pts) > 0
    out = []
    for i in range(n):
        p0, p, p1 = pts[i - 1], pts[i], pts[(i + 1) % n]
        e0, e1 = unit(p[0] - p0[0], p[1] - p0[1]), unit(p1[0] - p[0], p1[1] - p[1])
        n0 = (-e0[1], e0[0]) if ccw else (e0[1], -e0[0])
        n1 = (-e1[1], e1[0]) if ccw else (e1[1], -e1[0])
        k = d / max(0.2, 1.0 + n0[0] * n1[0] + n0[1] * n1[1])
        out.append((p[0] + (n0[0] + n1[0]) * k, p[1] + (n0[1] + n1[1]) * k))
    return out


def inside(poly, x, z):
    hit = False
    n = len(poly)
    for i in range(n):
        x0, z0 = poly[i]
        x1, z1 = poly[(i + 1) % n]
        if (z0 > z) != (z1 > z) and x < (x1 - x0) * (z - z0) / (z1 - z0) + x0:
            hit = not hit
    return hit


class House:
    """Sammelt die Flächen eines Hauses."""

    def __init__(self, tiles, rng):
        self.tiles = tiles                  # kit.json (Kachelgrößen)
        self.rng = rng
        self.parts = []

    def face(self, key, pts, uvs, facing=None, colors=None):
        self.parts.append((key, pts, uvs, facing, colors if colors is not None else [(1.0, 1.0, 1.0)] * len(pts)))

    def tile(self, name):
        return self.tiles[name]["tile_m"]

    def wall(self, key, p0, p1, y0, y1, u_start, v_start, tile_w, tile_h, out, tint, ao0=1.0, ao1=1.0):
        """Senkrechte Wand; die Textur läuft von außen gesehen von links nach rechts (u wächst gegen die Umlaufrichtung)."""
        length = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        ua, ub = u_start + length / tile_w, u_start                 # p0 rechts, p1 links
        va, vb = v_start, v_start + (y1 - y0) / tile_h
        c0, c1 = scale(tint, ao0), scale(tint, ao1)
        self.face(key, [(p0[0], p0[1], y0), (p1[0], p1[1], y0), (p1[0], p1[1], y1), (p0[0], p0[1], y1)],
                  [(ua, va), (ub, va), (ub, vb), (ua, vb)], out, [c0, c0, c1, c1])

    def quad_v(self, key, p0, p1, y0, y1, out, color):
        """Einfarbige senkrechte Fläche."""
        self.face(key, [(p0[0], p0[1], y0), (p1[0], p1[1], y0), (p1[0], p1[1], y1), (p0[0], p0[1], y1)], [(0, 0), (1, 0), (1, 1), (0, 1)],
                  out, [color] * 4)

    def prism_box(self, cx, cz, ux, uz, a, b, y0, y1, color, top=None):
        """Quader um (cx, cz), Länge a entlang u, Breite b entlang v = (−uz, ux); Seiten alternierend leicht verschieden hell."""
        vx, vz = -uz, ux
        corners = [(cx + ux * sa * a / 2 + vx * sb * b / 2, cz + uz * sa * a / 2 + vz * sb * b / 2) for sa, sb in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        for i in range(4):
            p0, p1 = corners[i], corners[(i + 1) % 4]
            self.quad_v("k:farbe", p0, p1, y0, y1, ((p0[0] + p1[0]) / 2 - cx, (p0[1] + p1[1]) / 2 - cz), scale(color, 1.0 if i in (0, 2) else 0.86))
        self.face("k:farbe", [(p[0], p[1], y1) for p in corners], [(0, 0), (1, 0), (1, 1), (0, 1)], None, [top or scale(color, 1.12)] * 4)

    def cylinder(self, cx, cz, r, y0, y1, color, sides=10, cap=None):
        ring = [(cx + r * math.cos(2 * math.pi * k / sides), cz + r * math.sin(2 * math.pi * k / sides)) for k in range(sides)]
        for k in range(sides):
            p0, p1 = ring[k], ring[(k + 1) % sides]
            self.quad_v("k:farbe", p0, p1, y0, y1, ((p0[0] + p1[0]) / 2 - cx, (p0[1] + p1[1]) / 2 - cz), scale(color, 0.92 + 0.16 * math.cos(2 * math.pi * (k + 0.5) / sides)))
        self.face("k:farbe", [(p[0], p[1], y1) for p in ring],
                  [(0.5 + 0.5 * math.cos(2 * math.pi * k / sides), 0.5 + 0.5 * math.sin(2 * math.pi * k / sides)) for k in range(sides)],
                  None, [cap or scale(color, 1.1)] * sides)

    def cone(self, cx, cz, r, y0, y1, color, sides=10):
        ring = [(cx + r * math.cos(2 * math.pi * k / sides), cz + r * math.sin(2 * math.pi * k / sides)) for k in range(sides)]
        for k in range(sides):
            p0, p1 = ring[k], ring[(k + 1) % sides]
            self.face("k:farbe", [(p0[0], p0[1], y0), (p1[0], p1[1], y0), (cx, cz, y1)], [(0, 0), (1, 0), (0.5, 1)],
                      ((p0[0] + p1[0]) / 2 - cx, (p0[1] + p1[1]) / 2 - cz), [color] * 3)


def rect_poly(w, d):
    return [(-w / 2, -d / 2), (w / 2, -d / 2), (w / 2, d / 2), (-w / 2, d / 2)]


def l_poly(w, d, wing_w, wing_d, mirror):
    """L-Grundriss: Rechteck w × d, dem hinten an einer Ecke ein Rechteck fehlt (die Vorderseite bleibt vollständig)."""
    hw, hd = w / 2, d / 2
    cut_x, cut_z = hw - (w - wing_w), hd - (d - wing_d)
    pts = [(-hw, -hd), (cut_x, -hd), (cut_x, -cut_z), (hw, -cut_z), (hw, hd), (-hw, hd)]
    if mirror:
        pts = [(-a, b) for a, b in pts][::-1]
    return pts


def choose(rng, max_h, row_len=None):
    """Zufälligen Haustyp mit Maßen wählen; row_len begrenzt die Breite (freie Länge längs der Straße)."""
    kinds = list(WEIGHTS)
    kind = rng.choices(kinds, [WEIGHTS[k] for k in kinds])[0]
    k = KINDS[kind]
    style = rng.choice(k["styles"])
    w = rng.uniform(*k["w"])
    if row_len is not None:
        w = min(w, row_len)
    return {"kind": kind, "style": style, "w": w, "d": rng.uniform(*k["d"]), "floors": rng.randint(*k["floors"]),
            "roof": rng.choice(k["roof"]), "front": rng.choice(k["front"]), "seed": rng.randrange(1 << 30), "max_h": max_h}


def build_house(tiles, spec, cx, cz, ux, uz, fx, fz, base_y=0.0):
    """Baut ein Haus; liefert (Flächen, Grundriss-Rechteck in Weltkoordinaten für Überschneidungsprüfungen, (w, d, Höhe))."""
    rng = random.Random(spec["seed"])
    H = House(tiles, rng)
    style, kind, roof = spec["style"], spec["kind"], spec["roof"]
    st = STYLES[style]
    bay, fh = st["bay"], st["fh"]
    w = max(2, round(spec["w"] / bay)) * bay
    d = max(2, round(spec["d"] / bay)) * bay
    nw, nd = round(w / bay), round(d / bay)
    if kind == "eckhaus" and (nw < 4 or nd < 4):
        kind = "stadthaus"
    if roof == "hip" and w < d:
        roof = "flat"

    def P(a, b):
        return (cx + ux * a + fx * b, cz + uz * a + fz * b)

    if kind == "eckhaus":
        local = l_poly(w, d, bay * max(2, nw // 2), bay * max(2, nd // 2), rng.random() < 0.5)
    else:
        local = rect_poly(w, d)
    poly = [P(a, b) for a, b in local]
    if area(poly) < 0:
        poly = poly[::-1]                                   # gegen den Uhrzeigersinn (in der x-z-Ebene)
    tint_p = lin(rng.choice(PLASTER)) if style != "backstein" else lin(rng.choice(BRICK_TINT))
    tint_r = lin((0.93, 0.93, 0.93))
    floors = spec["floors"]
    if spec.get("max_h"):
        floors = max(1, min(floors, int((spec["max_h"] - GF) / fh) + 1))
    y0 = 0.0
    y_up = y0 + GF                                          # Oberkante Erdgeschoss
    y_top = y0 + floors * fh if style == "buero" else y_up + (floors - 1) * fh
    tw, th = H.tile("fassade_" + style)
    uo = rng.randrange(0, 4) * bay / tw                     # Muster je Haus verschieben
    vo = rng.randrange(0, 2) * fh / th
    n = len(poly)
    shop = spec["front"] == "laden"
    for i in range(n):
        p0, p1 = poly[i], poly[(i + 1) % n]
        ex, ez = unit(p1[0] - p0[0], p1[1] - p0[1])
        out = (ez, -ex)                                     # außen: rechts der Umlaufrichtung
        mid = ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2)
        is_front = abs((mid[0] - cx) * fx + (mid[1] - cz) * fz - d / 2) < 0.05 and out[0] * fx + out[1] * fz > 0.8
        if style == "buero":
            H.wall("k:fassade_buero", p0, p1, y0, y_top, uo, vo, tw, th, out, tint_r, 0.85, 1.0)
            continue
        if shop and is_front:
            add_awning(H, p0, p1, out, random.Random(spec["seed"] * 7 + 3))
        skey = "k:sockel_laden" if (shop and is_front) else "k:sockel_wohn"
        stw = H.tile(skey[2:])[0] * bay / SOCKEL_BAY        # Erdgeschosskachel an die Feldbreite des Stils anpassen
        H.wall(skey, p0, p1, y0, y_up, (uo * tw / stw) % 1.0, 0.0, stw, GF, out, tint_p if style != "backstein" else lin((0.95, 0.9, 0.85)), 0.72, 1.0)
        if floors > 1:
            H.wall("k:fassade_" + style, p0, p1, y_up, y_top, uo, vo, tw, th, out, tint_p, 1.0, 1.0)
    tint_c = lin(scale(rng.choice(PLASTER), 0.97)) if style != "backstein" else lin((0.85, 0.8, 0.74))
    if roof == "flat":
        add_flat(H, poly, y_top, rng, st["cornice"], tint_c, floors)
    else:
        add_pitched(H, poly, y_top, roof, rng, style, tint_p, (tw, th))
    parts = [(k, [(x, z, y + base_y) for x, z, y in pts], uvs, facing, cols) for k, pts, uvs, facing, cols in H.parts]
    foot = [P(-w / 2 - 0.15, -d / 2 - 0.15), P(w / 2 + 0.15, -d / 2 - 0.15), P(w / 2 + 0.15, d / 2 + 0.15), P(-w / 2 - 0.15, d / 2 + 0.15)]
    return parts, foot, (w, d, y_top + (5.0 if roof != "flat" else 1.0))


AWNING_COLORS = [(0.50, 0.10, 0.07), (0.05, 0.24, 0.12), (0.04, 0.08, 0.30), (0.62, 0.40, 0.04), (0.28, 0.04, 0.08), (0.03, 0.28, 0.28)]   # linear
AWNING_CREAM = (0.72, 0.68, 0.58)


def add_awning(H, p0, p1, out, rng):
    """Markise über dem Schaufenster (gestreift, schräg nach außen abfallend) und ein Nasenschild mit Leuchtschrift (nachts leuchtend)."""
    ex, ez = unit(p1[0] - p0[0], p1[1] - p0[1])
    length = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
    if length < 4.0:
        return
    margin = 0.5
    a0, a1 = margin, length - margin
    proj = 1.05
    y_hi, y_lo, y_val = 2.95, 2.45, 2.18
    color = rng.choice(AWNING_COLORS)
    n = max(4, int((a1 - a0) / 0.55))
    if n % 2:
        n += 1
    for i in range(n):
        ta, tb = a0 + (a1 - a0) * i / n, a0 + (a1 - a0) * (i + 1) / n
        c = color if i % 2 == 0 else AWNING_CREAM
        q0 = (p0[0] + ex * ta, p0[1] + ez * ta)
        q1 = (p0[0] + ex * tb, p0[1] + ez * tb)
        f0 = (q0[0] + out[0] * proj, q0[1] + out[1] * proj)
        f1 = (q1[0] + out[0] * proj, q1[1] + out[1] * proj)
        H.face("k:farbe", [(q0[0], q0[1], y_hi), (q1[0], q1[1], y_hi), (f1[0], f1[1], y_lo), (f0[0], f0[1], y_lo)],
               [(0, 0), (1, 0), (1, 1), (0, 1)], None, [c] * 4)
        H.face("k:farbe", [(f0[0], f0[1], y_val), (f1[0], f1[1], y_val), (f1[0], f1[1], y_lo), (f0[0], f0[1], y_lo)],
               [(0, 0), (1, 0), (1, 1), (0, 1)], out, [scale(c, 0.85)] * 4)
    # Nasenschild: dunkle Halterung und Leuchtkasten quer zur Fassade, an einem Ende der Fassade
    ta = a1 - 0.6 if rng.random() < 0.5 else a0 + 0.6
    base = (p0[0] + ex * ta, p0[1] + ez * ta)
    key = "k:lampe_blau" if rng.random() < 0.3 else "k:lampe"
    y0, y1 = 3.0, 3.75
    for sa in (-1, 1):
        pa = (base[0] + ex * 0.04 * sa, base[1] + ez * 0.04 * sa)
        pb = (pa[0] + out[0] * 0.75, pa[1] + out[1] * 0.75)
        H.face(key, [(pa[0], pa[1], y0), (pb[0], pb[1], y0), (pb[0], pb[1], y1), (pa[0], pa[1], y1)], [(0, 0), (1, 0), (1, 1), (0, 1)],
               (ex * sa, ez * sa), [(1.0, 1.0, 1.0)] * 4)
    far = (base[0] + out[0] * 0.75, base[1] + out[1] * 0.75)
    H.face(key, [(far[0] - ex * 0.04, far[1] - ez * 0.04, y0), (far[0] + ex * 0.04, far[1] + ez * 0.04, y0),
                 (far[0] + ex * 0.04, far[1] + ez * 0.04, y1), (far[0] - ex * 0.04, far[1] - ez * 0.04, y1)], [(0, 0), (1, 0), (1, 1), (0, 1)],
           out, [(1.0, 1.0, 1.0)] * 4)
    H.face("k:farbe", [(base[0] + ex * 0.04, base[1] + ez * 0.04, y1), (base[0] + out[0] * 0.75 + ex * 0.04, base[1] + out[1] * 0.75 + ez * 0.04, y1),
                       (base[0] + out[0] * 0.75 - ex * 0.04, base[1] + out[1] * 0.75 - ez * 0.04, y1), (base[0] - ex * 0.04, base[1] - ez * 0.04, y1)],
           [(0, 0), (1, 0), (1, 1), (0, 1)], None, [(0.05, 0.05, 0.06)] * 4)


def add_flat(H, poly, top, rng, cornice, tint_c, floors):
    """Flachdach: optionales Traufgesims, Attika mit Abdeckung, Dachhaut mit Randschatten, Aufbauten."""
    n = len(poly)
    edge = poly
    if cornice:
        edge = inset(poly, -0.22)
        for i in range(n):
            q0, q1, p0, p1 = edge[i], edge[(i + 1) % n], poly[i], poly[(i + 1) % n]
            ex, ez = unit(p1[0] - p0[0], p1[1] - p0[1])
            H.quad_v("k:farbe", q0, q1, top - 0.45, top, (ez, -ex), scale(tint_c, 0.9))
    pa = 0.6 + rng.random() * 0.3
    coping = inset(edge, 0.3)
    for i in range(n):
        q0, q1, c0, c1 = edge[i], edge[(i + 1) % n], coping[i], coping[(i + 1) % n]
        ex, ez = unit(q1[0] - q0[0], q1[1] - q0[1])
        out = (ez, -ex)
        H.quad_v("k:farbe", q0, q1, top, top + pa, out, scale(tint_c, 0.95))
        H.face("k:farbe", [(q0[0], q0[1], top + pa), (q1[0], q1[1], top + pa), (c1[0], c1[1], top + pa), (c0[0], c0[1], top + pa)],
               [(0, 0)] * 4, None, [scale(tint_c, 1.15)] * 4)
        H.quad_v("k:farbe", c0, c1, top + 0.05, top + pa, (-out[0], -out[1]), scale(tint_c, 0.72))
    roof_key = rng.choice(["k:dach_kies", "k:dach_bahn", "k:dach_kies"])
    deep = inset(coping, 0.5)
    y_r = top + 0.05
    dark, light = lin((0.55, 0.55, 0.55)), lin((0.95, 0.95, 0.95))
    for i in range(n):
        c0, c1, e0, e1 = coping[i], coping[(i + 1) % n], deep[i], deep[(i + 1) % n]
        H.face(roof_key, [(c0[0], c0[1], y_r), (c1[0], c1[1], y_r), (e1[0], e1[1], y_r), (e0[0], e0[1], y_r)],
               [(c[0] / 4, -c[1] / 4) for c in (c0, c1, e1, e0)], None, [dark, dark, light, light])
    H.face(roof_key, [(p[0], p[1], y_r) for p in deep], [(p[0] / 4, -p[1] / 4) for p in deep], None, [light] * len(deep))
    add_clutter(H, deep, y_r, rng, floors)


def add_clutter(H, poly, y, rng, floors):
    """Dachaufbauten: Fahrstuhlhaus, Lüfterkästen, Schornsteine, Wassertank, Oberlichter, Solarfelder."""
    xs, zs = [p[0] for p in poly], [p[1] for p in poly]
    best = max(range(len(poly)), key=lambda i: math.hypot(poly[(i + 1) % len(poly)][0] - poly[i][0], poly[(i + 1) % len(poly)][1] - poly[i][1]))
    ax, az = unit(poly[(best + 1) % len(poly)][0] - poly[best][0], poly[(best + 1) % len(poly)][1] - poly[best][1])
    bx, bz = -az, ax
    inner = inset(poly, 0.5)
    taken = []

    def spot(sa, sb, margin=0.5):
        """Freien Platz für einen Aufbau der Größe sa × sb (entlang a/b) suchen; liefert die Mitte oder None."""
        for _ in range(50):
            x, z = rng.uniform(min(xs), max(xs)), rng.uniform(min(zs), max(zs))
            if not all(inside(inner, x + ax * da + bx * db, z + az * da + bz * db) for da, db in ((-sa / 2, -sb / 2), (sa / 2, -sb / 2), (sa / 2, sb / 2), (-sa / 2, sb / 2))):
                continue
            if any(math.hypot(x - tx, z - tz) < (math.hypot(sa, sb) + tr) / 2 + margin for tx, tz, tr in taken):
                continue
            taken.append((x, z, math.hypot(sa, sb)))
            return x, z
        return None

    area_m2 = abs(area(poly))
    concrete, metal, dark = lin((0.72, 0.72, 0.7)), lin((0.62, 0.64, 0.66)), lin((0.25, 0.26, 0.28))
    if floors >= 4 and rng.random() < 0.7:                                    # Fahrstuhlhaus
        p = spot(2.6, 2.4)
        if p:
            H.prism_box(p[0], p[1], ax, az, 2.6, 2.4, y, y + 2.3, concrete)
    for _ in range(rng.randrange(1, 3) + (1 if area_m2 > 250 else 0)):        # Lüfterkästen
        p = spot(3.6, 1.4)
        if p:
            for k in range(rng.randrange(2, 4)):
                oa = (k - 1) * 1.15
                H.prism_box(p[0] + ax * oa, p[1] + az * oa, ax, az, 1.0, 1.2, y, y + 0.9, metal)
                H.cylinder(p[0] + ax * oa, p[1] + az * oa, 0.32, y + 0.9, y + 1.02, dark, sides=8)
    if rng.random() < 0.55:                                                    # Schornsteine
        p = spot(1.6, 1.6)
        if p:
            for k in range(rng.randrange(1, 3)):
                H.prism_box(p[0] + bx * k * 0.9, p[1] + bz * k * 0.9, ax, az, 0.7, 0.7, y, y + rng.uniform(1.4, 2.2), lin((0.55, 0.3, 0.24)))
    if rng.random() < 0.3 and area_m2 > 200:                                   # Wassertank auf Stützen
        p = spot(2.4, 2.4)
        if p:
            H.cylinder(p[0], p[1], 1.0, y + 1.0, y + 2.6, lin((0.42, 0.36, 0.3)), sides=12)
            H.cone(p[0], p[1], 1.1, y + 2.6, y + 3.3, lin((0.3, 0.27, 0.24)), sides=12)
            for da, db in ((-0.7, -0.7), (0.7, -0.7), (0.7, 0.7), (-0.7, 0.7)):
                H.prism_box(p[0] + ax * da + bx * db, p[1] + az * da + bz * db, ax, az, 0.12, 0.12, y, y + 1.0, lin((0.3, 0.3, 0.3)))
    if rng.random() < 0.4:                                                     # Oberlichter
        p = spot(3.4, 1.7)
        if p:
            for k in range(2):
                oa = (k - 0.5) * 1.7
                H.prism_box(p[0] + ax * oa, p[1] + az * oa, ax, az, 1.5, 1.6, y, y + 0.35, lin((0.55, 0.6, 0.62)))
                H.prism_box(p[0] + ax * oa, p[1] + az * oa, ax, az, 1.0, 1.1, y + 0.35, y + 0.55, lin((0.28, 0.42, 0.55)))
    if rng.random() < 0.35 and area_m2 > 150:                                  # Solarfeld
        p = spot(4.0, 3.0)
        if p:
            for k in range(3):
                oa = (k - 1) * 1.25
                H.prism_box(p[0] + ax * oa, p[1] + az * oa, ax, az, 1.1, 2.6, y + 0.3, y + 0.55, lin((0.1, 0.16, 0.28)), top=lin((0.16, 0.24, 0.38)))


def add_pitched(H, poly, y_wall, kind, rng, style, tint_p, tile_wh):
    """Sattel- ("gable") oder Walmdach ("hip") über einem Rechteck-Grundriss; die Firstlinie läuft längs der Fassade."""
    ax = unit(poly[1][0] - poly[0][0], poly[1][1] - poly[0][1])
    bx = (-ax[1], ax[0])
    c = (sum(p[0] for p in poly) / 4, sum(p[1] for p in poly) / 4)
    length = math.hypot(poly[1][0] - poly[0][0], poly[1][1] - poly[0][1])
    depth = math.hypot(poly[2][0] - poly[1][0], poly[2][1] - poly[1][1])
    over = 0.35
    key = rng.choice(["k:dach_ziegel", "k:dach_ziegel", "k:dach_schiefer"])
    tan = min(math.tan(math.radians(32)), 4.2 / (depth / 2))               # Dachneigung
    rise = depth / 2 * tan
    y_ridge = y_wall + rise
    hd = depth / 2 + over
    y_e = y_ridge - hd * tan                                               # Traufe (etwas unter der Wandoberkante)
    slope = math.hypot(hd, y_ridge - y_e)
    tint = lin((1.0, 1.0, 1.0))

    def Q(a, b, y):
        return (c[0] + ax[0] * a + bx[0] * b, c[1] + ax[1] * a + bx[1] * b, y)

    def surface_y(b):
        return y_ridge - abs(b) * tan

    chimney = None
    if kind == "gable":
        hl = length / 2 + 0.25
        for sb in (-1, 1):
            e0, e1, r1, r0 = Q(-hl, sb * hd, y_e), Q(hl, sb * hd, y_e), Q(hl, 0, y_ridge), Q(-hl, 0, y_ridge)
            pts = [e0, e1, r1, r0] if sb > 0 else [e1, e0, r0, r1]
            uvs = [(0, 0), (2 * hl / 4, 0), (2 * hl / 4, slope / 4), (0, slope / 4)]
            H.face(key, pts, uvs, None, [scale(tint, 0.9), scale(tint, 0.9), tint, tint])
        for sa in (-1, 1):                                                  # Giebeldreiecke aus einfarbigem Putz
            b0, b1, apex = Q(sa * length / 2, -depth / 2, y_wall), Q(sa * length / 2, depth / 2, y_wall), Q(sa * length / 2, 0, y_ridge)
            H.face("k:farbe", [b0, b1, apex], [(0, 0), (1, 0), (0.5, 1)], (ax[0] * sa, ax[1] * sa), [scale(tint_p, 0.95)] * 3)
        chimney = (rng.uniform(-length * 0.3, length * 0.3), depth * 0.12)
    else:
        ridge = max(0.0, length - depth) / 2
        hl = length / 2 + over
        cs = [Q(-hl, -hd, y_e), Q(hl, -hd, y_e), Q(hl, hd, y_e), Q(-hl, hd, y_e)]
        r0, r1 = Q(-ridge, 0, y_ridge), Q(ridge, 0, y_ridge)
        for pts in ([cs[0], cs[1], r1, r0], [cs[2], cs[3], r0, r1], [cs[1], cs[2], r1], [cs[3], cs[0], r0]):
            el = math.hypot(pts[1][0] - pts[0][0], pts[1][1] - pts[0][1])
            if len(pts) == 4:
                rl = math.hypot(pts[3][0] - pts[2][0], pts[3][1] - pts[2][1])
                uvs = [(0, 0), (el / 4, 0), ((el + rl) / 8, slope / 4), ((el - rl) / 8, slope / 4)]
            else:
                uvs = [(0, 0), (el / 4, 0), (el / 8, slope / 4)]
            H.face(key, pts, uvs, None, [scale(tint, 0.92)] * 2 + [tint] * (len(pts) - 2))
        chimney = (rng.uniform(-max(ridge, 0.5), max(ridge, 0.5)), depth * 0.1)
    if chimney and rng.random() < 0.8:
        a, b = chimney
        pos = Q(a, b, 0)
        H.prism_box(pos[0], pos[1], ax[0], ax[1], 0.7, 0.7, surface_y(b) - 0.3, y_ridge + 1.2, lin((0.55, 0.3, 0.24)))
