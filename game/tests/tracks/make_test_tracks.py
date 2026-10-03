# Prüfstrecken für game/tests/test_heights.gd (Höhen-Paket, docs/dioramen/HOEHEN_PLAN.md Abschnitt 9). Ausgabe: neben diesem Skript.
# Aufruf: python game/tests/tracks/make_test_tracks.py
import json, math, os
OUT = os.path.dirname(os.path.abspath(__file__))
os.makedirs(OUT, exist_ok=True)

def oval(straight=140.0, radius=25.0, step=5.0):
    # Unten von links nach rechts (+x) bei z = -radius, rechts herum nach oben, oben zurück, links herum. Start bei x = -straight/2.
    pts = []
    h = straight / 2
    n = int(straight / step)
    for i in range(n):
        pts.append([-h + i * step, -radius])
    m = int(math.pi * radius / step)
    for i in range(m):
        a = -math.pi / 2 + math.pi * i / m
        pts.append([h + radius * math.cos(a), radius * math.sin(a)])
    for i in range(n):
        pts.append([h - i * step, radius])
    for i in range(m):
        a = math.pi / 2 + math.pi * i / m
        pts.append([-h + radius * math.cos(a), radius * math.sin(a)])
    length = 2 * straight + 2 * math.pi * radius
    return pts, length

pts, L = oval(straight=200.0)
X0 = -100.0
def s(m):
    return round(m / L, 6)

# 1) Höhen: Anstieg 15 % (0..40 m) auf ein Plateau 6 m (40..70 m), 30 % Gefälle (70..90 m), Schanze (125 m) + Lücke 130..140 m mit
#    1 m höherer Landeseite (140..160 m), Collider unter dem Plateau, Baumstamm ohne Unterkante.
prof = [[0, 0], [10, 1.5], [20, 3], [30, 4.5], [40, 6], [50, 6], [60, 6], [70, 6], [75, 4.5], [80, 3], [85, 1.5], [90, 0], [100, 0], [110, 0],
        [120, 0], [129.9, 0], [139.9, 1], [150, 1], [160, 1], [167, 0.5], [175, 0]]
heights = {
    "format": 1, "id": "hoehen_oval", "name": "Prüfoval Höhen", "theme": "city", "road": "asphalt", "laps": 1,
    "points": [[round(x, 3), round(z, 3)] for x, z in pts],
    "elevation": [[s(m), z] for m, z in prof],
    "ramps": [{"s": s(125.0), "length": 5.0, "height": 1.0}],
    "gaps": [{"from": s(130.0), "to": s(140.0)}],
    "props": [
        {"type": "collider", "x": X0 + 55.0, "z": -25.0, "w": 2.0, "d": 2.0, "rot": 0.0, "b": 0.0, "h": 4.0, "kind": "mauer", "visible": False},
        {"type": "log", "x": X0 + 105.0, "z": -25.0 + 2.5, "rot": 0.0},
    ],
}
json.dump(heights, open(os.path.join(OUT, 'hoehen_oval.json'), 'w', encoding='utf8'), ensure_ascii=False, indent=1)

# 2) Wippe: Abkürzung parallel zur oberen Geraden (Fahrtrichtung -x), 14 m außen, Lineal mittig auf dem geraden Pfadstück.
#    Entscheidungspunkt der KI in der Kurve davor (rund 48 m vor dem Abzweig), damit alle mit Tempo ankommen.
TOP = 200.0 + math.pi * 25.0
x0, x1 = 80.0, -80.0
path = [[x0, 25.0], [x0 - 20.0, 39.0], [x1 + 20.0, 39.0], [x1, 25.0]]
diag = math.hypot(20.0, 14.0)
at = diag + (x0 - x1 - 40.0) / 2.0
seesaw = {
    "format": 1, "id": "wippe_oval", "name": "Prüfoval Wippe", "theme": "kids", "road": "asphalt", "laps": 2,
    "points": [[round(x, 3), round(z, 3)] for x, z in pts],
    "shortcuts": [{"from": s(TOP + 20.0), "to": s(TOP + 180.0), "path": path, "width": 4.0, "surface": "asphalt"}],
    "seesaws": [{"shortcut": 0, "at": round(at, 3), "length": 24.0, "width": 4.0, "thickness": 0.3, "pivot_h": 1.1, "inertia": 26.0,
                 "bias": 1.0, "damping": 0.4, "restitution": 0.2, "rail": 0.8, "edge_ok": 0.35, "edge_wreck": 0.6,
                 "decide": s(250.0), "ai": True}],
}
json.dump(seesaw, open(os.path.join(OUT, 'wippe_oval.json'), 'w', encoding='utf8'), ensure_ascii=False, indent=1)
print('L', round(L, 2), 'at', round(at, 2))