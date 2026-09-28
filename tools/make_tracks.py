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
              type "ai": KI-Modell {model, x, z, rot, h | w+d} mit Klötzchen-Ersatz (color) solange es fehlt
              type "water": Wasserfläche {x, z, w, d, rot}
2,5D (Leitplanke 8), alle optional:
  open        true = Sprintstrecke (Start und Ziel getrennt, eine Durchfahrt)
  elevation   [[s, Höhe]] Höhenprofil der Fahrbahn
  ramps/gaps/loops/shortcuts/guardrails/terrain – siehe game/scripts/track.gd
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


# ---------------------------------------------------------------------------------------------------------
# Werkzeuge für die großen Strecken (Runde 2)

def turtle(start, heading_deg, commands, step=1.0):
    """Weg aus Befehlen: ("S", Länge) gerade, ("T", Radius, Winkel°) Bogen (+ = gegen den Uhrzeigersinn in x/z).
    Liefert dichte Punktliste (Abstand ~step)."""
    x, z = start
    a = math.radians(heading_deg)
    pts = [(x, z)]
    for cmd in commands:
        if cmd[0] == "S":
            n = max(1, int(cmd[1] / step))
            for _ in range(n):
                x += math.cos(a) * cmd[1] / n
                z += math.sin(a) * cmd[1] / n
                pts.append((x, z))
        else:
            r, ang = cmd[1], math.radians(cmd[2])
            n = max(2, int(abs(ang) * r / step))
            for _ in range(n):
                a += ang / n
                x += math.cos(a) * abs(ang) * r / n
                z += math.sin(a) * abs(ang) * r / n
                pts.append((x, z))
    return pts


def resample_open(pts, step=1.0):
    cum = [0.0]
    for i in range(1, len(pts)):
        cum.append(cum[-1] + math.dist(pts[i - 1], pts[i]))
    total = cum[-1]
    n = int(total / step)
    out, j = [], 0
    for k in range(n + 1):
        d = k * total / n
        while j < len(cum) - 2 and cum[j + 1] < d:
            j += 1
        f = (d - cum[j]) / max(1e-9, cum[j + 1] - cum[j])
        out.append((pts[j][0] + (pts[j + 1][0] - pts[j][0]) * f, pts[j][1] + (pts[j + 1][1] - pts[j][1]) * f))
    return out, total


def nearest(pts, p, closed=True):
    """(Abstand, Index, Anteil im Abschnitt) zum nächsten Streckenabschnitt."""
    best = (1e9, 0, 0.0)
    count = len(pts) if closed else len(pts) - 1
    for i in range(count):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        abx, aby = b[0] - a[0], b[1] - a[1]
        t = max(0.0, min(1.0, ((p[0] - a[0]) * abx + (p[1] - a[1]) * aby) / (abx * abx + aby * aby + 1e-9)))
        d = math.dist(p, (a[0] + abx * t, a[1] + aby * t))
        if d < best[0]:
            best = (d, i, t)
    return best


def s_of(pts, p, closed=True):
    d, i, t = nearest(pts, p, closed)
    span = len(pts) if closed else len(pts) - 1
    return (i + t) / span


def point_at(pts, s, offset=0.0, closed=True):
    span = len(pts) if closed else len(pts) - 1
    f = (s % 1.0 if closed else min(max(s, 0.0), 1.0)) * span
    i = min(int(f), span - 1)
    a, b = pts[i % len(pts)], pts[(i + 1) % len(pts)]
    q = (a[0] + (b[0] - a[0]) * (f - i), a[1] + (b[1] - a[1]) * (f - i))
    t = norm((b[0] - a[0], b[1] - a[1]))
    return (q[0] - t[1] * offset, q[1] + t[0] * offset), math.degrees(math.atan2(t[1], t[0]))


def keep_open(props, pts, clearance):
    out = []
    for p in props:
        need = HALF_WIDTH + clearance
        if all(nearest(pts, q, closed=False)[0] > need for q in footprint(p)):
            out.append({k: (round(v, 2) if isinstance(v, float) else v) for k, v in p.items()})
    return out


def ai(model, x, z, rot=0.0, h=None, w=None, d=None, color="a3aaa9"):
    prop = {"type": "ai", "model": model, "x": x, "z": z, "rot": rot, "color": color}
    if h is not None:
        prop["h"] = h
    if w is not None:
        prop["w"], prop["d"] = w, d
    return prop


# ---------------------------------------------------------------------------------------------------------
def mirror_z(data):
    """Strecke an der x-Achse spiegeln (Mittellinie, Abkürzungspfade, Bausteine, Kaikante). Die Reihenfolge der
    Punkte bleibt, damit gelten Anteile s (Schanzen, Lücken, Abkürzungen) unverändert."""
    data["points"] = [[x, -z] for x, z in data["points"]]
    for sc in data.get("shortcuts", []):
        sc["path"] = [[x, -z] for x, z in sc["path"]]
    for p in data["props"]:
        p["z"] = -p["z"]
        if p["type"] == "crane":
            p["rot"] = 180 - p.get("rot", 0)   # Ausleger (lokal +z) muss mit zur Wasserseite klappen
        elif "rot" in p:
            p["rot"] = -p["rot"]
    if "quay_z" in data:
        data["quay_z"] = -data["quay_z"]
        data["quay_dir"] = -data.get("quay_dir", 1)
    return data


def harbor():
    """Hafenviertel: schräge Straßenzüge, Abkürzung durch eine Lagerhalle, Schanze über ein Hafenbecken."""
    corners = [(-60, 25), (10, 25), (30, 5), (55, 5), (62, -15), (40, -32), (15, -32), (0, -15),
               (-20, -30), (-52, -30), (-66, -10)]
    pts = fillet_polygon(corners, [9, 8, 7, 6, 8, 7, 6, 6, 7, 8, 9])
    dense, total = resample(pts, 1.0)
    # Abkürzung: statt des Schlenkers über (0,-15) gerade durch die Lagerhalle bei z ≈ -31.
    a_s = s_of(dense, (13, -32))
    b_s = s_of(dense, (-18, -30.5))
    (ax, az), _ = point_at(dense, a_s)
    (bx, bz), _ = point_at(dense, b_s)
    path = [[round(ax + (bx - ax) * k / 8, 2), round(az + (bz - az) * k / 8, 2)] for k in range(9)]
    shortcut = {"from": round(a_s, 4), "to": round(b_s, 4), "path": path, "width": 4.0, "surface": "asphalt"}
    # Schanze über das Hafenbecken auf der Geraden z = -30 (Fahrtrichtung nach Westen).
    ramp_s = s_of(dense, (-24, -30))
    gap_from = ramp_s + 5.0 / total
    gap_to = gap_from + 7.5 / total
    props = []
    # Kaimauer (Land endet bei z = QUAY, dahinter offenes Meer), Frachter längsseits.
    QUAY = 37.5
    # Frachter als KI-Modell; Kiel 1,4 m unter der Wasserlinie (Meer bei y = −2,3). Ersatz ohne Modell: Grundformen.
    ship = ai("hafen_frachtschiff", -8, QUAY + 7.5, rot=0, w=36, d=9, color="1f3550")
    ship["y"] = -3.7
    props.append(ship)
    for x in range(-60, 61, 12):
        props.append(ai("hafen_poller", x, QUAY - 0.8, h=0.9, color="2b2b2b"))
    # Becken unter dem Sprung (quer zur Straße).
    (gx, gz), gh = point_at(dense, (gap_from + gap_to) / 2)
    props.append({"type": "water", "x": gx, "z": gz, "w": 6.5, "d": 34, "rot": 0})
    # Lagerhalle direkt neben der Abkürzung (nicht darüber: das Dach würde Auto und Linie verdecken),
    # längs zur Abkürzung; die Seite, auf der sie die Hauptstrecke nicht berührt.
    dx, dz = bx - ax, bz - az
    ln = math.hypot(dx, dz)
    nx, nz = -dz / ln, dx / ln
    hall_rot = math.degrees(math.atan2(dz, dx))
    for side in (1, -1):
        hall = ai("hafen_lagerhalle", round((ax + bx) / 2 + nx * 12.0 * side, 2), round((az + bz) / 2 + nz * 12.0 * side, 2),
                  rot=round(hall_rot, 1), w=min(16, ln * 0.7), d=9, color="8c969a")
        if keep([hall], dense, 1.2):
            break
    hall_kept = [hall] if keep([hall], dense, 1.2) else []
    props.append(ai("hafen_absperrung_kaputt", ax + 2.5, az - 3.5, rot=20, h=1.0, color="d8d0c0"))
    # Kräne, Container, Fässer, Paletten, Stapler.
    # Containerbrücken ganz auf dem Kai (Beine 2,5 m vor der Kante), Ausleger über das Wasser.
    for x in (-24, -2, 36):
        props.append({"type": "crane", "x": x, "z": QUAY - 4.0, "rot": 0, "h": 16})
    rng = random.Random(21)
    for x, z in [(-40, 5), (-25, 8), (-10, 3), (-38, -12), (22, -14), (40, -12), (70, 20), (75, -5), (-80, 10), (-78, -25)]:
        props.append(ai("hafen_container", x, z, rot=rng.choice([0, 90]), w=6, d=2.5, color=rng.choice(["8e3b2e", "3d5a6b", "4a6b3d"])))
    for x, z in [(5, 0), (-50, 15), (58, -28), (-45, -45)]:
        props.append(ai("hafen_faesser", x, z, h=1.0, color="2f5f9f"))
        props.append(ai("hafen_paletten", x + 3, z + 2, h=1.2, color="a07a4a"))
    props.append(ai("hafen_gabelstapler", -30, -12, rot=45, h=2.2, color="e0b020"))
    # Laternen entlang der Straße (Leuchtenköpfe zur Fahrbahn, siehe world.gd).
    for i in range(22):
        (x, z), _ = point_at(dense, i / 22 + 0.01, 5.8 if i % 2 else -5.8)
        props.append({"type": "lamp", "x": x, "z": z, "model": "hafen_laterne"})
    data = {"format": 1, "id": "harbor", "name": "Harbour Run", "subtitle": "Kräne, Container – und eine Abkürzung an der Lagerhalle vorbei.",
            "theme": "harbor", "half_width": HALF_WIDTH, "points": pts, "quay_z": QUAY,
            "conditions": [{"time": "day", "weather": "dry", "fog": 0}, {"time": "dusk", "weather": "rain", "fog": 0},
                           {"time": "night", "weather": "dry", "fog": 1}],
            "ramps": [{"s": round(ramp_s, 4), "length": 5.0, "height": 1.5}],
            "gaps": [{"from": round(gap_from, 4), "to": round(gap_to, 4)}],
            "shortcuts": [shortcut], "surfaces": [],
            "props": keep(props, dense, 1.2) + hall_kept}
    # Gespiegelt (z → −z): so liegt das Meer im Norden, und die hohen Kräne kippen in der Schrägansicht von der
    # Strecke weg statt über sie.
    save(mirror_z(data))


def serra():
    """Serra-Pass: Sprint entlang der Steilküste, dann Serpentinen den Berg hinauf. Start und Ziel getrennt."""
    cmds = [("S", 35), ("T", 40, -25), ("T", 40, 25), ("S", 25),
            ("T", 8, -160), ("S", 40), ("T", 8, 140), ("S", 40), ("T", 8, -140), ("S", 40), ("T", 8, 140), ("S", 25)]
    raw = turtle((-80, 40), 0, cmds)
    dense, total = resample_open(raw, 1.0)
    n = len(dense) - 1
    # Höhenprofil: Küste auf 14 m, danach steigt die Straße nur auf den Geraden (Kehren flach).
    heights = []
    h = 14.0
    for i in range(len(dense)):
        if i > 0:
            a, b, c = dense[max(0, i - 3)], dense[i], dense[min(n, i + 3)]
            h1 = math.atan2(b[1] - a[1], b[0] - a[0])
            h2 = math.atan2(c[1] - b[1], c[0] - b[0])
            bend = abs((h2 - h1 + math.pi) % (2 * math.pi) - math.pi)
            coast = i < 95
            if not coast and bend < 0.05:
                h += 0.2 * math.dist(dense[i - 1], dense[i])
        heights.append(h)
    # Steigungswechsel weich ausrunden (±12 m), sonst heben Autos an jeder Kuppe ab.
    smooth = []
    for i in range(len(heights)):
        lo, hi = max(0, i - 12), min(n, i + 12)
        smooth.append(sum(heights[lo:hi + 1]) / (hi - lo + 1))
    heights = smooth
    elevation = [[round(i / n, 4), round(heights[i], 2)] for i in range(0, len(dense), 4)]
    if elevation[-1][0] < 1.0:
        elevation.append([1.0, round(heights[-1], 2)])

    def road_h(i):
        return heights[i]

    # Gelände: weicher Hang aus den Straßenhöhen (inverse Abstandsgewichtung), an der Straße eingeschnitten;
    # talseitig steile Böschung (dort droht der Absturz), bergseitig ansteigend; südlich der Küstenstraße
    # Steilküste zum Meer (-3 m).
    xs = [q[0] for q in dense]
    zs = [q[1] for q in dense]
    x0, x1 = min(xs) - 45, max(xs) + 45
    z0, z1 = min(zs) - 45, max(zs) + 40
    cell = 3.0
    w = int((x1 - x0) / cell) + 1
    hgt = int((z1 - z0) / cell) + 1
    samples = [(dense[i], heights[i]) for i in range(0, len(dense), 3)]
    grid = []
    for iz in range(hgt):
        for ix in range(w):
            p = (x0 + ix * cell, z0 + iz * cell)
            d, i, t = nearest(dense, p, closed=False)
            i2 = min(n, i + 1)
            base = heights[i] + (heights[i2] - heights[i]) * t
            num = den = 0.0
            for q, hq in samples:
                wgt = 1.0 / (math.dist(p, q) ** 2 + 4.0)
                num += wgt * hq
                den += wgt
            v = num / den
            # Nach Norden (bergauf) über die Straßenhöhen hinaus weiter ansteigen.
            v += max(0.0, min(zs) - p[1]) * 0.5
            a_, b_ = dense[i], dense[i2]
            tx, tz = norm((b_[0] - a_[0] + 1e-9, b_[1] - a_[1]))
            nl = (-tz, tx)
            side = (p[0] - a_[0]) * nl[0] + (p[1] - a_[1]) * nl[1]
            downhill = (nl[1] > 0) == (side > 0)       # Seite, deren Normale nach Süden (+z) zeigt
            e = d - 4.6
            if e <= 0:
                v = base
            elif downhill:
                v = min(v, base - 1.4 * e)
            else:
                v = max(v, base + 0.35 * e)
            if i < 95 and downhill and e > 1.0:
                v = min(v, -3.0 + max(0.0, 14.0 - (e - 1.0) * 6.0))     # Steilküste
            if e < 1.6:
                v = min(v, base - 0.25)      # Gelände nie über der Fahrbahn (Rasterzellen zwischen den Punkten)
            edge = min(ix, iz, w - 1 - ix, hgt - 1 - iz) * cell
            if edge < 18.0:
                v = min(v, -3.0 + (v + 3.0) * edge / 18.0)   # Küste rundum statt eckiger Kante
            grid.append(round(max(v, -3.0), 2))
    terrain = {"origin": [x0, z0], "cell": cell, "w": w, "h": hgt, "heights": grid}
    # Leitplanken (Steinmauer) talseitig, mit Lücken am Scheitel der Kehren.
    guardrails = []
    # Leitplanken dort, wo das Gelände neben der Straße steil abfällt (auch an Kehren-Innenseiten).
    def terr(q):
        fx, fz = (q[0] - x0) / cell, (q[1] - z0) / cell
        ix, iz = max(0, min(w - 2, int(fx))), max(0, min(hgt - 2, int(fz)))
        tx, tz = min(1.0, max(0.0, fx - ix)), min(1.0, max(0.0, fz - iz))
        g0 = grid[iz * w + ix] + (grid[iz * w + ix + 1] - grid[iz * w + ix]) * tx
        g1 = grid[(iz + 1) * w + ix] + (grid[(iz + 1) * w + ix + 1] - grid[(iz + 1) * w + ix]) * tx
        return g0 + (g1 - g0) * tz
    for side, sign in (("left", 1.0), ("right", -1.0)):
        run = None
        for k in range(0, n + 1, 2):
            (qx, qz), _ = point_at(dense, k / n, sign * 6.7, closed=False)
            steep = heights[k] - terr((qx, qz)) > 2.0
            if steep and run is None:
                run = [k / n, k / n]
            elif steep:
                run[1] = k / n
            elif run is not None:
                if (run[1] - run[0]) * total > 4.0:
                    guardrails.append({"from": round(max(0.0, run[0] - 0.004), 4), "to": round(min(1.0, run[1] + 0.004), 4), "side": side})
                run = None
        if run is not None and (run[1] - run[0]) * total > 4.0:
            guardrails.append({"from": round(max(0.0, run[0] - 0.004), 4), "to": round(min(1.0, run[1] + 0.004), 4), "side": side})
    props = []
    rng = random.Random(33)
    for r in guardrails:
        m = int((r["to"] - r["from"]) * total / 4.2)
        for j in range(m):
            sj = r["from"] + (j + 0.5) * (r["to"] - r["from"]) / m
            off = 4.6 if r["side"] == "left" else -4.6
            (x, z), rot = point_at(dense, sj, off, closed=False)
            props.append(ai("serra_leitplanke", x, z, rot=-rot, w=4.2, d=0.6, color="cfc3a8"))
    for _ in range(120):
        x, z = rng.uniform(x0, x1), rng.uniform(z0, 44)
        kind = rng.choice(["serra_olivenbaum", "serra_pinie", "serra_pinie", "serra_agave", "serra_fels"])
        props.append(ai(kind, x, z, rot=rng.uniform(0, 360), h={"serra_olivenbaum": 4.5, "serra_pinie": 8.0,
                     "serra_agave": 1.4, "serra_fels": 2.5}[kind], color="6f7f4a"))
    (fx, fz), _ = point_at(dense, 1.0, 0, closed=False)
    props.append(ai("serra_kapelle", fx + 6, fz - 12, rot=0, h=6.5, color="f2efe6"))
    props.append(ai("serra_leuchtturm", -60, 62, h=14, color="f2efe6"))
    props.append(ai("serra_aussicht", -20, 50, h=1.5, color="c8bca4"))
    data = {"format": 1, "id": "serra", "name": "Serra Pass", "subtitle": "Steilküste, Kehren, kein Netz – ein Sprint bis zum Pass.",
            "theme": "mountain", "half_width": HALF_WIDTH, "points": dense, "open": True,
            "elevation": elevation, "terrain": terrain, "guardrails": guardrails,
            "conditions": [{"time": "day", "weather": "dry", "fog": 0}, {"time": "dusk", "weather": "dry", "fog": 0},
                           {"time": "day", "weather": "rain", "fog": 1}],
            "surfaces": [], "props": keep_open(props, dense, 1.0)}
    save(data)


def fair():
    """Jahrmarkt: Acht mit Wellen; an der Kreuzung springt der obere Ast per Schanze über den unteren."""
    pts = []
    samples = 340
    t0 = 0.45
    for i in range(samples):
        t = t0 + 2 * math.pi * i / samples
        wob = 1.0 + 0.10 * math.sin(3 * t)
        pts.append((60 * math.sin(t) * wob, 40 * math.sin(t) * math.cos(t) * wob))
    dense, total = resample(pts, 1.0)
    # Kreuzung: zweiter Durchgang durch (0,0) (t = π) – dort springt man über den ersten Ast.
    cross = (math.pi - t0) / (2 * math.pi)
    gap_half = 6.0 / total
    ramp_len = 7.0
    ramp_s = cross - gap_half - ramp_len / total
    props = []
    rng = random.Random(44)
    spots = [("jahrmarkt_riesenrad", -42, -2, 18), ("jahrmarkt_karussell", 40, 4, 7), ("jahrmarkt_autoscooter", 0, 36, 4),
             ("jahrmarkt_zelt", 0, -36, 7), ("jahrmarkt_bude", -20, 28, 3.5), ("jahrmarkt_bude", 22, 28, 3.5),
             ("jahrmarkt_losbude", -22, -30, 3.5), ("jahrmarkt_losbude", 24, -30, 3.5), ("jahrmarkt_bude", 75, 0, 3.5),
             ("jahrmarkt_losbude", -78, 4, 3.5)]
    for model, x, z, h in spots:
        props.append(ai(model, x, z, rot=rng.choice([0, 90, 180, 270]), h=h, color=rng.choice(["c0392b", "f1c40f", "2e86c1", "8e44ad"])))
    for i in range(18):
        (x, z), _ = point_at(dense, i / 18 + 0.02, 6.2 if i % 2 else -6.2)
        props.append({"type": "lamp", "x": x, "z": z, "model": "jahrmarkt_lichtermast"})
    data = {"format": 1, "id": "fair", "name": "Fun Fair Eight", "subtitle": "Riesenrad, Lichter – und ein Sprung über die eigene Strecke.",
            "theme": "fair", "half_width": HALF_WIDTH, "points": pts,
            "conditions": [{"time": "dusk", "weather": "dry", "fog": 0}, {"time": "night", "weather": "dry", "fog": 0},
                           {"time": "night", "weather": "rain", "fog": 0}],
            "ramps": [{"s": round(ramp_s, 4), "length": ramp_len, "height": 1.8}],
            "gaps": [{"from": round(cross - gap_half, 4), "to": round(cross + gap_half, 4)}],
            "surfaces": [], "props": keep(props, dense, 1.5)}
    save(data)


def quarry():
    """Steinbruch: Schotter, Looping auf der langen Geraden, Schanze über einen Graben, Kicker, Abkürzung."""
    # Start auf der linken Geraden, damit vor dem Looping die ganze untere Gerade als Anlauf bleibt.
    corners = [(-72, -25), (-65, 30), (45, 30), (65, 8), (55, -22), (0, -22), (-18, -2), (-40, -30)]
    pts = fillet_polygon(corners, [9, 9, 8, 7, 7, 6, 6, 7])
    dense, total = resample(pts, 1.0)
    loop_s = s_of(dense, (20, 30))
    # Schanze erst 30 m nach der Kurve (Anlauf), Graben 6 m, danach 13 m bis zur nächsten Kurve.
    ramp1 = s_of(dense, (25, -22))
    gap_from = ramp1 + 6.0 / total
    gap_to = gap_from + 6.0 / total
    ramp2 = s_of(dense, (-48, -29))
    a_s = s_of(dense, (-3, -22))
    b_s = s_of(dense, (-37, -29.5))
    (ax, az), _ = point_at(dense, a_s)
    (bx, bz), _ = point_at(dense, b_s)
    path = [[round(ax + (bx - ax) * k / 8, 2), round(az + (bz - az) * k / 8, 2)] for k in range(9)]
    props = []
    rng = random.Random(55)
    (gx, gz), _ = point_at(dense, (gap_from + gap_to) / 2)
    props.append({"type": "water", "x": gx, "z": gz, "w": 6.0, "d": 30})
    for x in range(-80, 81, 16):
        props.append(ai("steinbruch_felswand", x, -58, rot=0, w=16, d=10, color="8d8a83"))
        props.append(ai("steinbruch_felswand", x, 58, rot=180, w=16, d=10, color="8d8a83"))
    props += [ai("steinbruch_bagger", 20, 0, rot=30, h=5, color="e0b020"), ai("steinbruch_kipper", -30, 10, rot=-20, h=4, color="e0b020"),
              ai("steinbruch_brecher", 70, -30, h=8, color="6b6f73"), ai("steinbruch_foerderband", 60, 45, rot=20, w=20, d=3, color="6b6f73"),
              ai("steinbruch_buero", -85, 5, h=4, color="e8e8e8")]
    for x, z in [(-12, -30), (-26, -21), (-5, -14), (40, 5), (-55, 10)]:
        props.append(ai("steinbruch_kieshaufen", x, z, h=3.0, color="a9a39a"))
    data = {"format": 1, "id": "quarry", "name": "Quarry Loop", "subtitle": "Schotter, Graben, Kicker – und ein Looping.",
            "theme": "quarry", "road": "gravel", "half_width": HALF_WIDTH, "points": pts,
            "conditions": [{"time": "day", "weather": "dry", "fog": 0}, {"time": "dusk", "weather": "rain", "fog": 0},
                           {"time": "night", "weather": "dry", "fog": 1}],
            "loops": [{"s": round(loop_s, 4), "radius": 3.2}],   # auf Schotter ist ~15 m/s Anlauftempo realistisch
            "ramps": [{"s": round(ramp1, 4), "length": 6.0, "height": 1.7}, {"s": round(ramp2, 4), "length": 4.0, "height": 0.8}],
            "gaps": [{"from": round(gap_from, 4), "to": round(gap_to, 4)}],
            "shortcuts": [{"from": round(a_s, 4), "to": round(b_s, 4), "path": path, "width": 4.0, "surface": "gravel"}],
            "surfaces": [{"from": 0.55, "to": 0.62, "side": "both", "kind": "mud"}],
            "props": keep(props, dense, 1.5)}
    save(data)


def arena():
    """Drift-Arena: weite Driftflächen mit großen Radien, zwei kurze gerade Nadelöhre. Punkte statt Platzierung."""
    corners = [(-55, 25), (20, 25), (48, 0), (22, -26), (-8, -8), (-40, -30), (-68, -4)]
    pts = fillet_polygon(corners, [16, 14, 13, 11, 11, 13, 16])
    dense, total = resample(pts, 1.0)
    # Breitenprofil: überall weit (8 m halbe Breite), in zwei Nadelöhren 2,6 m.
    widths = []
    for a, b in [((-8, 25), (4, 25)), ((13, -20), (1, -12))]:
        sa, sb = sorted((s_of(dense, a), s_of(dense, b)))
        widths += [[round(sa - 0.02, 4), 8.0], [round(sa, 4), 2.6], [round(sb, 4), 2.6], [round(sb + 0.02, 4), 8.0]]
    widths.sort()
    props = []
    for k, (a, b) in enumerate([((-8, 25), (4, 25)), ((13, -20), (1, -12))]):
        for q in (a, b):
            (x, z), rot = point_at(dense, s_of(dense, q), 3.6)
            props.append(ai("drift_betonblock", x, z, rot=-rot, w=3.0, d=0.8, color="a0a0a0"))
            (x, z), rot = point_at(dense, s_of(dense, q), -3.6)
            props.append(ai("drift_betonblock", x, z, rot=-rot, w=3.0, d=0.8, color="a0a0a0"))
    for x, z in [(-80, 30), (60, 30), (60, -35), (-80, -35)]:
        props.append({"type": "floodlight", "x": x, "z": z, "reach": 22.0})
    for i in range(24):
        (x, z), rot = point_at(dense, i / 24 + 0.01, 11.5 if i % 2 else -11.5)
        props.append(ai("drift_reifenwand", x, z, rot=-rot, w=4.0, d=1.0, color="2b2b2b"))
    props += [ai("drift_zuschauer_container", 0, 45, h=5.5, color="3d5a6b"), ai("drift_parkhaus", -20, -52, w=30, d=14, color="9a9a9a")]
    data = {"format": 1, "id": "arena", "name": "Drift Arena", "subtitle": "Quer ist mehr: Punkte für Winkel und Tempo – ohne die Wand zu küssen.",
            "theme": "harbor", "half_width": HALF_WIDTH, "points": pts, "mode": "drift", "widths": widths,
            "drift_targets": [600, 1100, 1600],   # kalibriert: Drift-Auto mit ~45 % zu schnell geplanten Kurven ~1800 Pkt.
            "conditions": [{"time": "dusk", "weather": "dry", "fog": 0}, {"time": "night", "weather": "dry", "fog": 0},
                           {"time": "night", "weather": "rain", "fog": 0}],
            "surfaces": [], "props": keep(props, dense, 0.2)}
    save(data)


def kids():
    """Bonus Kinderzimmer: Spielzeug-Rennbahn auf dem Parkett zwischen riesigem Spielzeug – Looping und Buchsprung."""
    # Start links unten, damit die lange obere Gerade Anlauf für den Looping bietet.
    corners = [(-62, -18), (-58, 30), (15, 34), (55, 20), (64, -8), (32, -32), (4, -14), (-24, -36)]
    pts = fillet_polygon(corners, [9, 10, 9, 8, 8, 6, 6, 8])
    dense, total = resample(pts, 1.0)
    loop_s = s_of(dense, (-8, 32))
    # Buchsprung auf der langen Diagonale: Schanze 6 m, Lücke 6 m zwischen zwei Buchstapeln.
    ramp_s = s_of(dense, (56, -16))
    gap_from = ramp_s + 6.0 / total
    gap_to = gap_from + 6.0 / total
    props = []
    rng = random.Random(66)
    props += [ai("kinder_teddy", 2, 6, rot=160, h=11, color="a0703c"),
              ai("kinder_bausteinturm", 34, 2, rot=15, h=8, color="d64541"),
              ai("kinder_ball", -34, 6, h=6, color="3a7bd5"),
              ai("kinder_holzeisenbahn", -10, 52, rot=0, w=22, d=5, color="b5773a"),
              ai("kinder_buntstifte", -50, -50, rot=25, w=12, d=6, color="f1c40f"),
              ai("kinder_kreisel", 78, 22, h=4.5, color="8e44ad"),
              ai("kinder_buch", 78, -26, rot=-30, w=12, d=9, color="27ae60"),
              ai("kinder_buch", -80, 8, rot=80, w=12, d=9, color="c0392b")]
    for x, z in [(-20, -8), (-44, 16), (20, -46), (48, 42), (-78, -30), (70, -44), (-30, 48), (12, 18)]:
        props.append(ai("kinder_bauklotz", x, z, rot=rng.choice([0, 20, 45, 70]), h=2.6,
                        color=rng.choice(["d64541", "f1c40f", "3a7bd5", "27ae60"])))
    data = {"format": 1, "id": "kids", "name": "Toy Box Speedway", "subtitle": "Bonus: Spielzeugbahn im Kinderzimmer – Looping und Sprung über die Bücherlücke.",
            "theme": "kids", "half_width": HALF_WIDTH, "points": pts,
            "conditions": [{"time": "day", "weather": "dry", "fog": 0}, {"time": "dusk", "weather": "dry", "fog": 0},
                           {"time": "day", "weather": "dry", "fog": 0}],
            "loops": [{"s": round(loop_s, 4), "radius": 4.0}],
            "ramps": [{"s": round(ramp_s, 4), "length": 6.0, "height": 1.7}],
            "gaps": [{"from": round(gap_from, 4), "to": round(gap_to, 4)}],
            # Teppich im Innenraum der Kurve rechts oben: bremst wie Erde.
            "surfaces": [{"from": 0.36, "to": 0.46, "side": "inner", "kind": "dirt"}],
            "props": keep(props, dense, 1.5)}
    save(data)


if __name__ == "__main__":
    azure()
    city()
    forest()
    harbor()
    serra()
    fair()
    quarry()
    arena()
    kids()
