"""Prozedurale, einfache Stadtautos (parkend) für die Dioramen: rund 100 Dreiecke je Auto, nur Vertexfarbe.

Reine Geometrie ohne Blender-Abhängigkeit, Flächenformat wie tools/kit_house.py:
(Materialschlüssel, Ecken [(x, z, y)], UVs, Blickrichtung (x, z) | None, Farben). Alle Teile nutzen den Schlüssel "k:farbe"
(einfarbig, nur Vertexfarbe): Lack, Glas, Reifen und Leuchten unterscheiden sich durch die Farbe.

Ein Auto steht in einem Bezugssystem: Mittelpunkt (cx, cz), Einheitsvektor u = Fahrtrichtung (vorne), Breite quer dazu.
Die Bauformen (Limousine, Fließheck, Transporter, Geländewagen) unterscheiden sich in Länge, Höhe und Kabine.
"""
import math

BODY_COLORS = [(0.85, 0.85, 0.83), (0.06, 0.06, 0.07), (0.45, 0.46, 0.48), (0.65, 0.66, 0.68), (0.55, 0.06, 0.05),
               (0.05, 0.12, 0.38), (0.08, 0.22, 0.12), (0.62, 0.45, 0.06), (0.18, 0.2, 0.22), (0.7, 0.3, 0.05)]    # linear
GLASS = (0.012, 0.018, 0.026)
TIRE = (0.012, 0.012, 0.014)
BUMPER = (0.03, 0.03, 0.035)
HEAD = (0.9, 0.88, 0.75)
TAIL = (0.55, 0.02, 0.02)

KINDS = {
    #            Länge Breite  Kabine von/bis (Anteil), Kabinenhöhe, Gesamthöhe Karosserie, Radstand-Anteil
    "limousine": dict(length=4.5, width=1.82, body=0.70, cab=(-0.36, 0.14), roof=1.42, slope=0.30),
    "fliessheck": dict(length=3.95, width=1.76, body=0.72, cab=(-0.40, 0.12), roof=1.46, slope=0.18),
    "transporter": dict(length=5.2, width=1.95, body=0.95, cab=(-0.46, 0.46), roof=2.05, slope=0.10),
    "gelaendewagen": dict(length=4.6, width=1.9, body=0.92, cab=(-0.44, 0.18), roof=1.75, slope=0.16),
}


def _quad(parts, pts, facing, color):
    parts.append(("k:farbe", pts, [(0, 0), (1, 0), (1, 1), (0, 1)], facing, [color] * 4))


def car_parts(cx, cz, ux, uz, kind, color, base_y=0.0):
    """Flächen eines parkenden Autos; (ux, uz) zeigt nach vorn."""
    k = KINDS[kind]
    vx, vz = -uz, ux
    L, Wd = k["length"], k["width"]
    parts = []

    def P(a, b, y):
        return (cx + ux * a + vx * b, cz + uz * a + vz * b, base_y + y)

    def out(da, db):
        return (ux * da + vx * db, uz * da + vz * db)

    hl, hw = L / 2, Wd / 2
    y_s, y_b = 0.28, k["body"]                      # Schweller, Oberkante Karosserie (Motorhaube/Kofferraum)
    # Karosserie: Quader mit leicht zurückgesetzter Haube und Heck (Oberkante), Seiten in Lackfarbe
    sh = color
    dark = tuple(c * 0.72 for c in color)
    # Seitenwände (links/rechts)
    for sb in (-1, 1):
        _quad(parts, [P(-hl, sb * hw, y_s), P(hl, sb * hw, y_s), P(hl, sb * hw, y_b), P(-hl, sb * hw, y_b)], out(0, sb), sh if sb > 0 else dark)
    # Front und Heck
    _quad(parts, [P(hl, -hw, y_s), P(hl, hw, y_s), P(hl, hw, y_b), P(hl, -hw, y_b)], out(1, 0), sh)
    _quad(parts, [P(-hl, hw, y_s), P(-hl, -hw, y_s), P(-hl, -hw, y_b), P(-hl, hw, y_b)], out(-1, 0), dark)
    # Haube und Kofferraum (oben, leicht zur Kabine ansteigend)
    a0, a1 = k["cab"][0] * L, k["cab"][1] * L
    cab_y = y_b + 0.06
    _quad(parts, [P(hl, -hw, y_b), P(hl, hw, y_b), P(a1, hw, cab_y), P(a1, -hw, cab_y)], None, tuple(c * 1.08 for c in sh))
    _quad(parts, [P(a0, -hw, cab_y), P(a0, hw, cab_y), P(-hl, hw, y_b), P(-hl, -hw, y_b)], None, tuple(c * 1.05 for c in sh))
    # Kabine: Trapez (Fensterband aus Glas, Dach in Lackfarbe); Schräge nach vorn (Windschutzscheibe) und hinten
    slope = k["slope"] * L
    top = k["roof"]
    t0, t1 = a0 + slope * 0.9, a1 - slope * 0.7           # Dachkante hinten/vorn
    wi = hw * 0.86                                        # Kabinenbreite unten
    wt = hw * 0.76                                        # oben
    for sb in (-1, 1):                                    # Seitenfenster
        _quad(parts, [P(a0, sb * wi, cab_y), P(a1, sb * wi, cab_y), P(t1, sb * wt, top), P(t0, sb * wt, top)], out(0, sb), GLASS)
    _quad(parts, [P(a1, -wi, cab_y), P(a1, wi, cab_y), P(t1, wt, top), P(t1, -wt, top)], out(1, 0), GLASS)      # Windschutzscheibe
    _quad(parts, [P(t0, -wt, top), P(t0, wt, top), P(a0, wi, cab_y), P(a0, -wi, cab_y)], out(-1, 0), GLASS)     # Heckscheibe
    _quad(parts, [P(t0, -wt, top), P(t1, -wt, top), P(t1, wt, top), P(t0, wt, top)], None, tuple(c * 1.15 for c in sh))   # Dach
    # Stoßfänger, Scheinwerfer, Rückleuchten
    _quad(parts, [P(hl + 0.04, -hw * 0.95, y_s), P(hl + 0.04, hw * 0.95, y_s), P(hl + 0.04, hw * 0.95, y_s + 0.22), P(hl + 0.04, -hw * 0.95, y_s + 0.22)], out(1, 0), BUMPER)
    _quad(parts, [P(-hl - 0.04, hw * 0.95, y_s), P(-hl - 0.04, -hw * 0.95, y_s), P(-hl - 0.04, -hw * 0.95, y_s + 0.22), P(-hl - 0.04, hw * 0.95, y_s + 0.22)], out(-1, 0), BUMPER)
    for sb in (-1, 1):
        _quad(parts, [P(hl + 0.03, sb * hw * 0.78, y_b - 0.16), P(hl + 0.03, sb * hw * 0.42, y_b - 0.16), P(hl + 0.03, sb * hw * 0.42, y_b - 0.04), P(hl + 0.03, sb * hw * 0.78, y_b - 0.04)], out(1, 0), HEAD)
        _quad(parts, [P(-hl - 0.03, sb * hw * 0.42, y_b - 0.18), P(-hl - 0.03, sb * hw * 0.78, y_b - 0.18), P(-hl - 0.03, sb * hw * 0.78, y_b - 0.05), P(-hl - 0.03, sb * hw * 0.42, y_b - 0.05)], out(-1, 0), TAIL)
    # Räder: vier dunkle Quader (außen leicht vorstehend), Radkästen ergeben sich durch den Schweller darüber
    r = 0.33
    for sa in (-1, 1):
        for sb in (-1, 1):
            ca = sa * (hl - 0.85)
            cb = sb * (hw - 0.02)
            _quad(parts, [P(ca - r, cb + sb * 0.05, 0.0), P(ca + r, cb + sb * 0.05, 0.0), P(ca + r, cb + sb * 0.05, 2 * r), P(ca - r, cb + sb * 0.05, 2 * r)], out(0, sb), TIRE)
            _quad(parts, [P(ca - r, cb - sb * 0.3, 2 * r), P(ca + r, cb - sb * 0.3, 2 * r), P(ca + r, cb + sb * 0.05, 2 * r), P(ca - r, cb + sb * 0.05, 2 * r)], None, TIRE)
    return parts


def random_car(rng, cx, cz, ux, uz, base_y=0.0):
    kind = rng.choices(list(KINDS), weights=[4, 4, 1.2, 1.6])[0]
    color = rng.choice(BODY_COLORS)
    return car_parts(cx, cz, ux, uz, kind, color, base_y), (KINDS[kind]["length"], KINDS[kind]["width"])
