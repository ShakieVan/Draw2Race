"""Erzeugt die Streckendateien game/tracks/*.json (Format 1) reproduzierbar.

Format (auch Ziel einer späteren Companion-App):
  points      geschlossene Mittellinie als Kontrollpunkte [x, z] in Fahrtrichtung; points[0] = Start/Ziel.
              Das Spiel glättet sie (Catmull-Rom) und tastet gleichmäßig ab.
  half_width  halbe Fahrbahnbreite in m
  theme       coast | city | forest (Boden, Himmel, Randfarben)
  road        Fahrbahnbelag: asphalt (Standard) | gravel (Schotterpiste)
  surfaces    Belagzonen neben der Fahrbahn: from/to als Streckenanteil, side outer|inner|both, kind mud|...
  conditions  Bedingungen je Herausforderung (3 Einträge): time day|dusk|night, weather dry|rain|snow, fog 0|1|2
  props       Deko-Bausteine: type, x, z, optional rot (Grad), w, d, h, scale, color, text
Nur Standardbibliothek; Aufruf: python tools/make_tracks.py
"""
import json
import math
import random
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "game" / "tracks"
HALF_WIDTH = 3.5


def stadium(straight=28.0, radius=13.0, step=1.0):
    half = straight / 2
    length = 2 * straight + 2 * math.pi * radius
    pts = []
    n = int(length / step)
    for i in range(n):
        d = i * length / n
        if d < half:
            p = (d, radius)
        elif d < half + math.pi * radius:
            a = (d - half) / radius
            p = (half + math.sin(a) * radius, math.cos(a) * radius)
        elif d < half + math.pi * radius + straight:
            p = (half - (d - half - math.pi * radius), -radius)
        elif d < half + 2 * math.pi * radius + straight:
            a = (d - half - math.pi * radius - straight) / radius
            p = (-half - math.sin(a) * radius, -math.cos(a) * radius)
        else:
            p = (-half + (d - half - 2 * math.pi * radius - straight), radius)
        pts.append(p)
    return pts


def fillet_polygon(corners, radii, step=1.0):
    """Polygon mit abgerundeten Ecken (Radius je Ecke) als dichte Punktliste, Start in der Mitte der ersten Kante."""
    n = len(corners)
    arcs = []
    for i in range(n):
        a, p, b = corners[i - 1], corners[i], corners[(i + 1) % n]
        d1 = norm((p[0] - a[0], p[1] - a[1]))
        d2 = norm((b[0] - p[0], b[1] - p[1]))
        turn = math.atan2(d1[0] * d2[1] - d1[1] * d2[0], d1[0] * d2[0] + d1[1] * d2[1])
        r = radii[i]
        t = r * math.tan(abs(turn) / 2)
        start = (p[0] - d1[0] * t, p[1] - d1[1] * t)
        side = 1 if turn > 0 else -1
        center = (start[0] - d1[1] * r * side, start[1] + d1[0] * r * side)
        a0 = math.atan2(start[1] - center[1], start[0] - center[0])
        steps = max(2, int(abs(turn) * r / step))
        arc = [(center[0] + r * math.cos(a0 + turn * k / steps), center[1] + r * math.sin(a0 + turn * k / steps))
               for k in range(steps + 1)]
        arcs.append(arc)
    pts = []
    first_mid = ((corners[0][0] + corners[1][0]) / 2, (corners[0][1] + corners[1][1]) / 2)
    order = list(range(1, n)) + [0]
    pts += line(first_mid, arcs[1][0], step)
    for k, i in enumerate(order):
        pts += arcs[i][:-1]
        nxt = arcs[order[(k + 1) % n]][0]
        end = nxt if k < n - 1 else first_mid
        pts += line(arcs[i][-1], end, step)
    return pts


def lemniscate(a=34.0, b=30.0, t0=0.45, samples=260):
    pts = []
    for i in range(samples):
        t = t0 + 2 * math.pi * i / samples
        pts.append((a * math.sin(t), b * math.sin(t) * math.cos(t)))
    return pts


def norm(v):
    length = math.hypot(v[0], v[1])
    return (v[0] / length, v[1] / length)


def line(a, b, step):
    n = max(1, int(math.dist(a, b) / step))
    return [(a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n) for k in range(n)]


def resample(pts, step=1.0):
    closed = pts + [pts[0]]
    cum = [0.0]
    for i in range(1, len(closed)):
        cum.append(cum[-1] + math.dist(closed[i - 1], closed[i]))
    total = cum[-1]
    n = int(total / step)
    out, j = [], 0
    for k in range(n):
        d = k * total / n
        while cum[j + 1] < d:
            j += 1
        f = (d - cum[j]) / max(1e-9, cum[j + 1] - cum[j])
        out.append((closed[j][0] + (closed[j + 1][0] - closed[j][0]) * f,
                    closed[j][1] + (closed[j + 1][1] - closed[j][1]) * f))
    return out, total


def dist_to_track(p, pts):
    best = 1e9
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        abx, aby = b[0] - a[0], b[1] - a[1]
        t = max(0.0, min(1.0, ((p[0] - a[0]) * abx + (p[1] - a[1]) * aby) / (abx * abx + aby * aby + 1e-9)))
        best = min(best, math.dist(p, (a[0] + abx * t, a[1] + aby * t)))
    return best


def at(pts, total, s, offset=0.0):
    """Punkt bei Streckenanteil s mit Seitenversatz (positiv = links der Fahrtrichtung gedreht wie im Spiel)."""
    n = len(pts)
    f = (s % 1.0) * n
    i = int(f)
    a, b = pts[i % n], pts[(i + 1) % n]
    p = (a[0] + (b[0] - a[0]) * (f - i), a[1] + (b[1] - a[1]) * (f - i))
    t = norm((b[0] - a[0], b[1] - a[1]))
    return (p[0] - t[1] * offset, p[1] + t[0] * offset), math.degrees(math.atan2(t[1], t[0]))


def footprint(p):
    """Randpunkte der Grundfläche (Rechteck, gedreht) bzw. Mittelpunkt bei kleinen Objekten."""
    w, d = p.get("w", 0.0) * p.get("scale", 1.0), p.get("d", 0.0) * p.get("scale", 1.0)
    if p["type"] in ("label",):
        return [(p["x"], p["z"])]
    if w <= 0 or d <= 0:
        r = 1.0 * p.get("scale", 1.0)
        return [(p["x"] + r * math.cos(a), p["z"] + r * math.sin(a)) for a in (0, 1.57, 3.14, 4.71)]
    rot = math.radians(p.get("rot", 0.0))
    ellipse = p["type"] in ("lagoon", "pond", "fountain")
    pts = []
    for k in range(24):
        a = 2 * math.pi * k / 24
        if ellipse:
            lx, lz = w / 2 * math.cos(a), d / 2 * math.sin(a)
        else:
            c, sn = math.cos(a), math.sin(a)
            m = max(abs(c) / (w / 2), abs(sn) / (d / 2))
            lx, lz = c / m, sn / m
        pts.append((p["x"] + lx * math.cos(rot) - lz * math.sin(rot), p["z"] + lx * math.sin(rot) + lz * math.cos(rot)))
    return pts


def keep(props, pts, clearance):
    """Nur Bausteine, deren Grundfläche genug Abstand zur Fahrbahn hat."""
    out = []
    for p in props:
        need = HALF_WIDTH + (0.4 if p["type"] == "label" else clearance)
        if all(dist_to_track(q, pts) > need for q in footprint(p)):
            out.append({k: (round(v, 2) if isinstance(v, float) else v) for k, v in p.items()})
    return out


def save(data):
    OUT.mkdir(parents=True, exist_ok=True)
    data["points"] = [[round(x, 3), round(z, 3)] for x, z in data["points"]]
    (OUT / f"{data['id']}.json").write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    print(data["id"], len(data["points"]), "Punkte,", len(data["props"]), "Bausteine")


def azure():
    pts = stadium()
    dense, total = resample(pts, 1.0)
    props = [
        {"type": "lagoon", "x": -7, "z": -1, "w": 22, "d": 14},
        {"type": "walkway", "x": -9.3, "z": 3.9, "w": 12, "d": 1.8},
        {"type": "pavilion", "x": 11, "z": -2, "w": 11, "d": 5, "text": "AZURE MOTOR CLUB"},
        {"type": "label", "x": 0, "z": 8, "text": "DRAW  /  DRIVE  /  REPEAT", "flat": True},
        {"type": "tower", "x": -5, "z": 21, "text": "02  /  AZURE"},
        {"type": "boathouse", "x": 40, "z": 18},
    ]
    for fx, fz in [(-24, -21), (24, -21), (-26, 21), (26, 21)]:
        props.append({"type": "floodlight", "x": fx, "z": fz, "reach": 13.0})
    for x in (-12.0, 0.0, 12.0):
        props.append({"type": "stand", "x": x, "z": -23.5, "w": 10, "d": 3.5})
    for p in [(-33, -12), (-36, -5), (-34, 8), (33, -10), (35, 2), (32, 13), (-22, 19), (20, 20),
              (-18, -8), (19, -7), (-19, 7), (20, 7), (-16, -4), (17, 4)]:
        props.append({"type": "palm", "x": p[0], "z": p[1], "h": 3.1 + (p[0] % 2.0)})
    for i in range(7):
        props.append({"type": "parasol", "x": -20 + i * 6.4, "z": 23, "color": "coral" if i % 2 else "cream"})
    for i in range(18):
        p, rot = at(dense, total, i / 18.0, 6.0)
        if abs(p[1]) < 18:
            props.append({"type": "planter", "x": p[0], "z": p[1], "rot": rot, "w": 2.0, "d": 0.6})
    for i in range(16):
        p, _ = at(dense, total, 0.02 + i * 0.029, -5.5)
        props.append({"type": "flower", "x": p[0], "z": p[1], "w": 0.6, "d": 0.6, "color": "coral" if i % 2 else "gold"})
    save({"format": 1, "id": "azure", "name": "Azure Coast", "subtitle": "Salzluft. Heiße Reifen. Deine Ideallinie.",
          "theme": "coast", "half_width": HALF_WIDTH, "points": pts,
          "conditions": [{"time": "day", "weather": "dry", "fog": 0}, {"time": "dusk", "weather": "dry", "fog": 0},
                         {"time": "night", "weather": "rain", "fog": 0}],
          "surfaces": [{"from": 0.21, "to": 0.29, "side": "outer", "kind": "mud"},
                       {"from": 0.71, "to": 0.79, "side": "outer", "kind": "mud"}],
          "props": keep(props, dense, 1.2)})


def min_other(prop, dense):
    # Abstand zur nächsten Streckenmitte; an der Kreuzung der 8 liegt eine Laterne sonst auf dem anderen Ast.
    return min(math.hypot(prop["x"] - q[0], prop["z"] - q[1]) for q in dense)


def city():
    corners = [(-30, 18), (30, 18), (30, -2), (-6, -2), (-6, -26), (-30, -26)]
    pts = fillet_polygon(corners, [9, 9, 9, 7, 9, 9])
    dense, total = resample(pts, 1.0)
    rng = random.Random(7)
    props = []
    palette = ["cream", "coral", "teal", "sand", "slate"]
    # Häuserblöcke rund um die Strecke und in der Innenfläche/Aussparung des L.
    blocks = [(0, 31, 16, 8), (-22, 31, 12, 8), (22, 31, 12, 8), (43, 10, 8, 14), (43, -12, 8, 12),
              (14, -16, 18, 12), (26, -22, 8, 8), (-18, -40, 16, 8), (4, -38, 8, 10), (-43, 0, 8, 14),
              (-43, -20, 8, 12), (-43, 20, 8, 10), (10, 8, 18, 8), (-18, -9, 9, 14), (-20, 8, 8, 6)]
    for x, z, w, d in blocks:
        props.append({"type": "building", "x": x, "z": z, "w": w, "d": d, "h": rng.choice([5, 7, 9, 12, 15]),
                      "color": rng.choice(palette)})
    for i in range(24):
        for side in (-1, 1):
            p, rot = at(dense, total, i / 24.0 + 0.01, side * 5.8)
            props.append({"type": "lamp", "x": p[0], "z": p[1], "rot": rot})
    for i in range(14):
        p, _ = at(dense, total, i / 14.0 + 0.035, 7.5)
        props.append({"type": "street_tree", "x": p[0], "z": p[1]})
    props += [{"type": "billboard", "x": 0, "z": 23.5, "text": "DRAW2RACE CITY"},
              {"type": "billboard", "x": 36, "z": 3, "rot": 90, "text": "NIGHT RUN"},
              {"type": "stand", "x": -14, "z": 24, "w": 10, "d": 3.5},
              {"type": "tower", "x": 12, "z": 24, "text": "03  /  CITY"},
              {"type": "fountain", "x": -18, "z": 7}]
    save({"format": 1, "id": "city", "name": "Downtown L", "subtitle": "Enge Häuserschluchten, harte Bremspunkte.",
          "theme": "city", "half_width": HALF_WIDTH, "points": pts,
          "conditions": [{"time": "dusk", "weather": "dry", "fog": 0}, {"time": "night", "weather": "dry", "fog": 0},
                         {"time": "night", "weather": "rain", "fog": 1}], "surfaces": [], "props": keep(props, dense, 1.0)})


def forest():
    pts = lemniscate()
    dense, total = resample(pts, 1.0)
    rng = random.Random(11)
    props = []
    for _ in range(420):
        x, z = rng.uniform(-50, 50), rng.uniform(-34, 34)
        kind = "pine" if rng.random() < 0.65 else "oak"
        props.append({"type": kind, "x": x, "z": z, "scale": rng.uniform(0.8, 1.35)})
    for _ in range(26):
        props.append({"type": "rock", "x": rng.uniform(-48, 48), "z": rng.uniform(-32, 32), "scale": rng.uniform(0.6, 1.6)})
    props += [{"type": "pond", "x": 19, "z": 0, "w": 12, "d": 8},
              {"type": "cabin", "x": -20, "z": 1, "rot": 20},
              {"type": "stand", "x": 0, "z": 24, "w": 10, "d": 3.5},
              {"type": "tower", "x": -12, "z": 24, "text": "04  /  FOREST"},
              {"type": "log", "x": 8, "z": -22, "rot": 30}, {"type": "log", "x": -30, "z": 20, "rot": -15}]
    # Laternen direkt am Wegrand; erst nach dem Freihalte-Filter ergänzt, damit sie nicht wegfallen.
    lanterns = []
    for i in range(16):
        for side in (-1, 1):
            q, _ = at(dense, total, i / 16.0 + 0.02, side * (HALF_WIDTH + 1.4))
            lanterns.append({"type": "lantern", "x": q[0], "z": q[1]})
    save({"format": 1, "id": "forest", "name": "Forest Eight", "subtitle": "Schotterpiste durch den Wald – und eine Kreuzung ohne Ampel.",
          "theme": "forest", "road": "gravel", "half_width": HALF_WIDTH, "points": pts,
          "conditions": [{"time": "day", "weather": "dry", "fog": 0}, {"time": "day", "weather": "dry", "fog": 1},
                         {"time": "dusk", "weather": "snow", "fog": 1}],
          "surfaces": [{"from": 0.18, "to": 0.32, "side": "both", "kind": "mud"},
                       {"from": 0.68, "to": 0.82, "side": "both", "kind": "mud"}],
          "props": keep(props, dense, 2.0) + [l for l in lanterns if min_other(l, dense) > HALF_WIDTH + 0.8]})


if __name__ == "__main__":
    azure()
    city()
    forest()
