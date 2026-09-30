"""Baut aus einer Streckendatei ein gebackenes Diorama (Bildebene) für das Spiel.

Die Streckendatei bleibt die Spielebene (Physik, KI, Zeichnen). Dieses Skript erzeugt daraus in Blender eine
komponierte Szene:
- Fahrbahn, Randsteine und Gehwege als glatte Bänder entlang der Mittellinie,
- an jeder rechtwinkligen Ecke eine Kreuzung: die beiden Straßen laufen geradeaus weiter und enden an Absperrungen,
- Seitenstraßen (T-Einmündungen) an den langen Geraden, ebenfalls mit Absperrung,
- Boden nach Zonen (außen Pflaster, innen Park), Häuserreihen entlang aller Straßen, Bäume, Brunnen,
- die gebackene Umgebungsverdeckung des Bodens (Kontaktschatten an Häusern, Bäumen, Randsteinen) als Lichttextur
  (zweite UV-Ebene) und eine Begleitdatei <name>_layout.json mit den Straßenflächen (Laufzeit-Bauteile wie Laternen
  werden dort ausgespart).

Koordinaten: Spiel (x, y oben, z) = Blender (x, -z, y). Im Skript ist "2D" immer (x, z) des Spiels.
Aufruf: tools/blender.ps1 tools/diorama.py <strecke.json> <aus.glb> <aus_ao.jpg> <texturordner> <modellordner>
"""
import json
import math
import os
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit_house

A = sys.argv[sys.argv.index("--") + 1:]
TRACK, OUT_GLB, OUT_AO, TEX, PROPS = A[:5]
data = json.load(open(TRACK, encoding="utf-8"))
HW = float(data.get("half_width", 3.5))
ROAD_Y, KERB_Y, WALK_Y, GROUND_Y = 0.17, 0.30, 0.30, 0.295
Y_J, Y_K, Y_W = ROAD_Y + 0.006, KERB_Y + 0.002, WALK_Y + 0.002   # Kreuzungen/Seitenstraßen liegen knapp darüber
KERB_W, WALK_W = 0.55, 3.45
SIDE = KERB_W + WALK_W                        # Randstein + Gehweg = 4,0 m
FOOT = HW + SIDE                              # Halbbreite Fahrbahn + Rand + Gehweg = 7,5 m
rng = random.Random(3)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


# ---------------------------------------------------------------- Mittellinie
def resample(points, step):
    pts = [Vector((p[0], p[1])) for p in points]
    pts.append(pts[0])
    out, carry = [], 0.0
    for a, b in zip(pts, pts[1:]):
        seg = (b - a).length
        t = carry
        while t < seg:
            out.append(a.lerp(b, t / seg))
            t += step
        carry = t - seg
    return out


center = resample(data["points"], 0.5)
N = len(center)
tang = [(center[(i + 1) % N] - center[i - 1]).normalized() for i in range(N)]
left = [Vector((-t.y, t.x)) for t in tang]
dist = [0.0]
for i in range(1, N + 1):
    dist.append(dist[-1] + (center[i % N] - center[i - 1]).length)
area = sum(center[i].x * center[(i + 1) % N].y - center[(i + 1) % N].x * center[i].y for i in range(N)) * 0.5
inside_sign = 1.0 if area > 0 else -1.0     # links der Fahrtrichtung liegt innen, wenn gegen den Uhrzeigersinn
outer = -inside_sign
curv = []
for i in range(N):
    a, b = tang[i - 2], tang[(i + 2) % N]
    curv.append(abs(math.atan2(a.x * b.y - a.y * b.x, a.dot(b))) / 2.0)

C = np.array([[p.x, p.y] for p in center])
SEG_A, SEG_B = C, np.roll(C, -1, axis=0)


def dist_to_center(P, keep=None):
    """Abstand vieler Punkte (n×2) zur Mittellinie; keep = Bool-Maske der Segmente, die zählen."""
    a, b = (SEG_A, SEG_B) if keep is None else (SEG_A[keep], SEG_B[keep])
    out = np.full(len(P), 1e9)
    d = b - a
    ll = np.maximum((d ** 2).sum(1), 1e-9)
    for k in range(0, len(P), 4000):
        q = P[k:k + 4000, None, :]
        t = np.clip(((q - a) * d).sum(2) / ll, 0, 1)
        proj = a + t[..., None] * d
        out[k:k + 4000] = np.sqrt(((q - proj) ** 2).sum(2)).min(1)
    return out


def inside(P):
    """Punkt-in-Polygon (Mittellinie) für viele Punkte."""
    x, y = P[:, 0][:, None], P[:, 1][:, None]
    ax, ay, bx, by = SEG_A[:, 0], SEG_A[:, 1], SEG_B[:, 0], SEG_B[:, 1]
    cond = (ay > y) != (by > y)
    xs = ax + (y - ay) * (bx - ax) / np.where(by - ay == 0, 1e-9, by - ay)
    return (cond & (x < xs)).sum(1) % 2 == 1


def keep_except(lo, hi):
    """Segmentmaske ohne den (zyklischen) Indexbereich lo..hi."""
    keep = np.ones(N, bool)
    for k in range((hi - lo) % N + 1):
        keep[(lo + k) % N] = False
    return keep


# ---------------------------------------------------------------- Materialien
def image(path):
    return bpy.data.images.load(path, check_existing=True)


def material(name, tex=None, rough=0.8, normal=None, color=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    uv = nt.nodes.new("ShaderNodeUVMap")
    uv.uv_map = "UVMap"
    if tex:
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = image(tex)
        nt.links.new(uv.outputs["UV"], node.inputs["Vector"])
        nt.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
        # Farbton setzt das Spiel (Materialname → Tönung), der glTF-Export übernimmt Mischknoten nicht zuverlässig.
    elif color:
        bsdf.inputs["Base Color"].default_value = (*color, 1)
    if normal:
        nn = nt.nodes.new("ShaderNodeTexImage")
        nn.image = image(normal)
        nn.image.colorspace_settings.name = "Non-Color"
        nt.links.new(uv.outputs["UV"], nn.inputs["Vector"])
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(nn.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def tex(name, kind="Color"):
    return f"{TEX}/{name}/{name}_1K-JPG_{kind}.jpg"


def stripes():
    img = bpy.data.images.new("Randstein_Streifen", 16, 64)
    px = []
    for y in range(64):
        c = (0.72, 0.12, 0.08, 1) if y < 32 else (0.9, 0.88, 0.84, 1)
        px += list(c) * 16
    img.pixels = px
    img.filepath_raw = bpy.app.tempdir + "randstein_streifen.png"
    img.file_format = "PNG"
    img.save()
    return img.filepath_raw


M = {
    "asphalt": material("D_Asphalt", tex("Asphalt031"), 0.85, tex("Asphalt031", "NormalGL")),
    "asphalt_str": material("D_Asphalt_Strasse", tex("Asphalt033"), 0.85, tex("Asphalt033", "NormalGL")),
    "linie": material("D_Markierung", color=(0.86, 0.84, 0.78), rough=0.6),
    "kerb": material("D_Randstein", tex("Concrete034"), 0.8),
    "kerb_paint": material("D_Randstein_Farbe", stripes(), rough=0.6),
    "gehweg": material("D_Gehweg", tex("Concrete034"), 0.85, tex("Concrete034", "NormalGL")),
    "pflaster": material("D_Pflaster", tex("PavingStones138"), 0.85, tex("PavingStones138", "NormalGL")),
    "gras": material("D_Gras", tex("Grass005"), 0.9, tex("Grass005", "NormalGL")),
    "wasser": material("D_Wasser", color=(0.25, 0.5, 0.5), rough=0.1),
    "stein": material("D_Stein", tex("Concrete034"), 0.7),
    "weite": material("D_Weite", tex("Concrete034"), 0.9),
    "beton": material("D_Beton", tex("Concrete034"), 0.8),
    "rot": material("D_Rot", color=(0.72, 0.09, 0.07), rough=0.55),
    "weiss": material("D_Weiss", color=(0.9, 0.9, 0.87), rough=0.55),
    "orange": material("D_Orange", color=(0.95, 0.42, 0.05), rough=0.5),
}


def kit_material(name):
    """Platzhalter für Bausatz-Oberflächen: nur der Name (die Textur setzt das Spiel) und die Vertexfarbe (Putzton, Verschattung)."""
    mat = bpy.data.materials.new("K_" + name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.85
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Color"
    nt.links.new(vc.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    return mat


KIT_TILES = json.load(open(os.path.join(PROPS, "..", "kit", "kit.json"), encoding="utf-8"))
for _name in list(KIT_TILES) + ["farbe"]:
    M["k:" + _name] = kit_material(_name)


# ---------------------------------------------------------------- Netz-Helfer
class Frame:
    """Ausgerichtetes 2D-Bezugssystem (Ursprung, Achse u = a, Achse v = b) für achsenparallele Rechtecke."""

    def __init__(self, o, u, v):
        self.o, self.u, self.v = Vector(o), Vector(u).normalized(), Vector(v).normalized()

    def pt(self, a, b):
        return self.o + self.u * a + self.v * b

    def poly(self, a0, a1, b0, b1):
        return [tuple(self.pt(a, b)) for a, b in ((a0, b0), (a1, b0), (a1, b1), (a0, b1))]


def flat(fr, key, a0, a1, b0, b1, y, tile=2.5):
    """Waagerechtes Rechteck in einem Bezugssystem (UV = lokale Koordinaten / tile)."""
    ab = ((a0, b0), (a1, b0), (a1, b1), (a0, b1))
    return (key, [(*fr.pt(a, b), y) for a, b in ab], [(a / tile, b / tile) for a, b in ab])


def wall(fr, key, a0, b0, a1, b1, y0, y1, facing):
    """Senkrechte Fläche von (a0,b0) nach (a1,b1); facing = Blickrichtung im lokalen System (fa, fb)."""
    p0, p1 = fr.pt(a0, b0), fr.pt(a1, b1)
    f = fr.u * facing[0] + fr.v * facing[1]
    ln = (p1 - p0).length
    return (key, [(p0.x, p0.y, y0), (p1.x, p1.y, y0), (p1.x, p1.y, y1), (p0.x, p0.y, y1)],
            [(0, 0), (ln, 0), (ln, y1 - y0), (0, y1 - y0)], (f.x, f.y))


def box(fr, key, a0, a1, b0, b1, y0, y1):
    """Quader (ohne Boden) als Flächenliste."""
    return [flat(fr, key, a0, a1, b0, b1, y1, 1.0),
            wall(fr, key, a0, b0, a1, b0, y0, y1, (0, -1)), wall(fr, key, a0, b1, a1, b1, y0, y1, (0, 1)),
            wall(fr, key, a0, b0, a0, b1, y0, y1, (-1, 0)), wall(fr, key, a1, b0, a1, b1, y0, y1, (1, 0))]


def cone(fr, key, a, b, radius, height, y0, sides=6):
    """Leitkegel als Pyramide."""
    apex = fr.pt(a, b)
    out = []
    for k in range(sides):
        t0, t1 = 2 * math.pi * k / sides, 2 * math.pi * (k + 1) / sides
        p0 = fr.pt(a + radius * math.cos(t0), b + radius * math.sin(t0))
        p1 = fr.pt(a + radius * math.cos(t1), b + radius * math.sin(t1))
        mid = fr.pt(a + math.cos((t0 + t1) / 2), b + math.sin((t0 + t1) / 2)) - apex
        out.append((key, [(p0.x, p0.y, y0), (p1.x, p1.y, y0), (apex.x, apex.y, y0 + height)], [(0, 0), (1, 0), (0.5, 1)], (mid.x, mid.y)))
    return out


def mesh_object(name, parts):
    """parts: Liste (Material-Schlüssel, Ecken als (x, z, y), UVs[, Blickrichtung (x, z) für senkrechte Flächen])."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    uv0 = bm.loops.layers.uv.new("UVMap")
    col = bm.loops.layers.float_color.new("Color") if any(len(p) > 4 for p in parts) else None
    keys, faces = [], []
    for key, corners, uvs, *rest in parts:
        if key not in keys:
            keys.append(key)
        f = bm.faces.new([bm.verts.new((x, -z, y)) for x, z, y in corners])
        f.material_index = keys.index(key)
        for k, (loop, uv) in enumerate(zip(f.loops, uvs)):
            loop[uv0].uv = uv
            if col is not None:
                c = rest[1][k] if len(rest) > 1 and rest[1] is not None else (1.0, 1.0, 1.0)
                loop[col] = (c[0], c[1], c[2], 1.0)
        faces.append((f, rest[0] if rest else None))
    bm.normal_update()
    for f, facing in faces:
        if facing is not None:           # senkrechte Fläche: zur gewünschten Seite drehen
            if f.normal.dot(Vector((facing[0], -facing[1], 0.0))) < 0:
                f.normal_flip()
        elif f.normal.z < -0.01:         # waagerecht: nach oben (die Achsenumrechnung spiegelt die Umlaufrichtung)
            f.normal_flip()
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for key in keys:
        me.materials.append(M[key])
    obj = bpy.data.objects.new(name, me)
    scene.collection.objects.link(obj)
    return obj


def mesh_objects(name, parts):
    """Ein Objekt je Material (das Spiel legt sein Zusatzlicht je Objekt aus der ersten Textur an)."""
    groups = {}
    for p in parts:
        groups.setdefault(p[0], []).append(p)
    return [mesh_object(f"{name}_{k.replace(chr(58), chr(95))}", ps) for k, ps in groups.items()]


# ---------------------------------------------------------------- Kreuzungen und Seitenstraßen planen
placed = []          # Flächen (Vierecke in 2D), auf denen keine Häuser/Bäume stehen dürfen
footprints = []      # (Frame, a0, a1, b0, b1): Gesamtfläche von Straße + Rand + Gehweg (für Boden und Häuser)
asphalt_rects = []   # (Frame, a0, a1, b0, b1): reine Fahrbahnflächen (Begleitdatei für das Spiel)
arm_parts = []       # Flächen aller Kreuzungen/Seitenstraßen
lamps = []           # neue Laternen für Kreuzungen und Nebenstraßen: (Standort, Blickpunkt auf der Straße)
arms = []            # Achsen der Zufahrten für Häuserreihen: (Ursprung, Richtung, Seitenrichtung, s_von, s_bis)
skip_by_side = {1.0: set(), -1.0: set()}   # Segmente der Hauptbänder, die an Kreuzungen entfallen (je Seite)
BAKED = {"lamp", "building", "street_tree", "fountain"}
obstacles = [(Vector((p["x"], p["z"])), max(p.get("w", 3), p.get("d", 3)) / 2 + 2.5)
             for p in data["props"] if p["type"] not in BAKED]


def poly_hits_obstacle(poly):
    for pos, radius in obstacles:
        xs = [q[0] for q in poly]
        zs = [q[1] for q in poly]
        if min(xs) - radius < pos.x < max(xs) + radius and min(zs) - radius < pos.y < max(zs) + radius:
            return True
    return False


def overlaps(poly_a, poly_b):
    for poly in (poly_a, poly_b):
        for i in range(4):
            ax, az = poly[i]
            bx, bz = poly[(i + 1) % 4]
            nx, nz = az - bz, bx - ax
            pa = [nx * x + nz * z for x, z in poly_a]
            pb = [nx * x + nz * z for x, z in poly_b]
            if max(pa) <= min(pb) or max(pb) <= min(pa):
                return False
    return True


def edge_samples(poly, step=2.0):
    pts = []
    for i in range(4):
        p, q = Vector(poly[i]), Vector(poly[(i + 1) % 4])
        n = max(1, int((q - p).length / step))
        pts += [tuple(p.lerp(q, k / n)) for k in range(n + 1)]
    return np.array(pts)


def fits(fr, region, length, keep):
    """Passt die Zufahrt mit dieser Länge? Rückgabe "" = ja, sonst der Grund."""
    poly = fr.poly(*region(length))
    if any(overlaps(poly, q) for q in placed):
        return "Überschneidung mit anderer Zufahrt/Kreuzung"
    if poly_hits_obstacle(poly):
        return "fester Bau (Werbetafel/Tribüne)"
    if not (dist_to_center(edge_samples(poly), keep) >= FOOT + 0.5).all():
        return "zu nah an anderem Streckenteil"
    return ""


def best_length(fr, region, lmax, keep, lmin=10.0):
    """Längste passende Länge (von lmax in 2-m-Schritten abwärts); ohne Treffer 0 und der Grund der kürzesten Prüfung."""
    length, why = lmax, ""
    while length >= lmin:
        why = fits(fr, region, length, keep)
        if not why:
            return length, ""
        length -= 2.0
    return 0.0, why


def barrier(pos, lateral, normal, half):
    """Absperrung quer über die Straße: gestreifte Balken auf Pfosten, Betonblöcke dahinter, Leitkegel davor.
    normal zeigt zur Straße hin."""
    g = Frame(pos, lateral, normal)
    parts = []
    for s in (-1, 1):
        parts += box(g, "weiss", s * (half - 0.15) - 0.06, s * (half - 0.15) + 0.06, -0.06, 0.06, Y_J, Y_J + 1.35)
    n = max(2, int(2 * half / 0.6))
    for z0, z1, flip in ((0.85, 1.15, 0), (0.45, 0.75, 1)):
        for i in range(n):
            a0 = -half + i * (2 * half / n)
            parts += box(g, "rot" if (i + flip) % 2 == 0 else "weiss", a0, a0 + 2 * half / n, -0.05, 0.05, Y_J + z0, Y_J + z1)
    for a in (-half * 0.62, 0.0, half * 0.62):
        parts += box(g, "beton", a - 0.95, a + 0.95, -0.85, -0.3, Y_J, Y_J + 0.6)
    for a in (-half * 0.85, -half * 0.42, half * 0.42, half * 0.85):
        parts += cone(g, "orange", a, 0.9, 0.2, 0.6, Y_J)
    return parts


def build_arm(fr, region, length, kind_key, lateral_a, lateral_b, start, axis_dir, axis_side, end_pos):
    """Gemeinsame Bauteile einer Zufahrt (Fahrbahn, Randsteine, Gehwege, Absperrung) mit Länge length.
    fr: Bezugssystem der Zufahrt, dessen b-Achse entlang der Zufahrt zeigt und a quer dazu (Mitte a = 0)."""
    parts = arm_parts
    end = start + length
    parts.append(flat(fr, "asphalt_str", -HW, HW, start, end, Y_J, 6.0))
    b0 = start + 2.0                     # gestrichelte Mittellinie (nur wo Platz ist)
    while b0 + 2.5 < end - 5.0:
        parts.append(flat(fr, "linie", -0.08, 0.08, b0, b0 + 2.5, Y_J + 0.003, 1.0))
        b0 += 6.0
    for s in (-1, 1):
        a_in, a_k, a_w = s * HW, s * (HW + KERB_W), s * (HW + SIDE)
        lo, hi = sorted((a_in, a_k))
        parts.append(flat(fr, "kerb", lo, hi, start, end, Y_K, 1.0))
        parts.append(wall(fr, "kerb", a_in, start, a_in, end, Y_J, Y_K, (-s, 0)))
        lo, hi = sorted((a_k, a_w))
        # Gehwege beginnen bei T-Einmündungen und Süd-Zufahrten hinter dem Eckbereich der Hauptstraße bzw. Kreuzung
        parts.append(flat(fr, "gehweg", lo, hi, start + (SIDE if kind_key in ("T", "S") else 0.0), end, Y_W, 2.5))
    asphalt_rects.append((fr, -HW, HW, start, end))
    # Laternen abwechselnd links/rechts auf dem Gehweg, alle 9 m (je Seite alle 18 m)
    b = start + (SIDE + 3.0 if kind_key in ("T", "S") else 3.0)
    k = 0
    while b < end - 7.0:
        side = 1 if k % 2 == 0 else -1
        lamps.append((fr.pt(side * (HW + SIDE * 0.5 + 0.2), b), fr.pt(0, b)))
        b += 9.0
        k += 1
    parts += barrier(fr.pt(0, end - 2.2), fr.u, -fr.v, HW - 0.35)


# Ecken (Kurven um rund 90°): Erkennung über Krümmungsabschnitte
def find_corners():
    hot = [c > 0.05 for c in curv]
    starts = [i for i in range(N) if hot[i] and not hot[i - 1]]
    found = []
    for i0 in starts:
        j = i0
        while hot[(j + 1) % N] and j - i0 < N:
            j += 1
        j1 = j % N
        ia, ib = (i0 - 3) % N, (j1 + 3) % N
        t_in, t_out = tang[ia], tang[ib]
        den = t_in.x * t_out.y - t_in.y * t_out.x
        turn = math.degrees(math.atan2(den, t_in.dot(t_out)))
        if not 70 < abs(turn) < 110:
            continue
        d = center[ib] - center[ia]
        P = center[ia] + t_in * ((d.x * t_out.y - d.y * t_out.x) / den)
        sigma = 1.0 if turn > 0 else -1.0
        ta, tb = center[(i0 + 1) % N], center[(j1 - 1) % N]
        v = Vector((-t_in.y, t_in.x)) * sigma
        found.append(dict(P=P, u=t_in, v=v, sigma=sigma, i0=i0, j1=j1,
                          r_in=-(ta - P).dot(t_in), r_out=(tb - P).dot(v)))
    return found


corners = find_corners()
print("DIORAMA Ecken:", len(corners), [(round(c["P"].x, 1), round(c["P"].y, 1), int(c["sigma"])) for c in corners])
K, W, H = KERB_W, SIDE, HW

def post(pos, radius, y0, y1, key_body, key_cap, cap_h=0.2, sides=8):
    """Betonpoller: achteckiger Körper mit farbiger Kappe."""
    ring = [(pos.x + radius * math.cos(2 * math.pi * k / sides), pos.y + radius * math.sin(2 * math.pi * k / sides)) for k in range(sides)]
    parts = []
    for key, ya, yb in ((key_body, y0, y1 - cap_h), (key_cap, y1 - cap_h, y1)):
        for k in range(sides):
            p0, p1 = ring[k], ring[(k + 1) % sides]
            mid = ((p0[0] + p1[0]) / 2 - pos.x, (p0[1] + p1[1]) / 2 - pos.y)
            parts.append((key, [(p0[0], p0[1], ya), (p1[0], p1[1], ya), (p1[0], p1[1], yb), (p0[0], p0[1], yb)],
                          [(0, 0), (1, 0), (1, 1), (0, 1)], mid))
    parts.append((key_cap, [(x, z, y1) for x, z in ring],
                  [(0.5 + 0.5 * math.cos(2 * math.pi * k / sides), 0.5 + 0.5 * math.sin(2 * math.pi * k / sides)) for k in range(sides)]))
    return parts


for J in corners:
    P, u, v = J["P"], J["u"], J["v"]
    F = Frame(P, u, v)
    Rw, Rn = J["r_in"], J["r_out"]
    keep = keep_except(J["i0"] - 60, J["j1"] + 60)
    # Zufahrten beginnen hinter dem Kreuzungsbereich (dort schließt er ohnehin an); Mindestlänge 10 m
    e_len, e_why = best_length(F, lambda L: (H + W, H + W + L, -H - W, H + W), 42.0, keep)
    s_len, s_why = best_length(F, lambda L: (-H - W, H + W, -H - W - L, -H - W), 42.0, keep)
    if not e_len and not s_len:
        print("DIORAMA Ecke", (round(P.x, 1), round(P.y, 1)), "ohne Kreuzung (kein Platz):", e_why, "|", s_why)
        continue
    e_len = e_len + W if e_len else 0.0     # Länge ab Kreuzungsrand
    s_len = s_len + W if s_len else 0.0
    outer_lat = -J["sigma"]                 # seitliches Vorzeichen der Außenseite dieser Kurve
    win = [(J["i0"] + 1 + k) % N for k in range(max(0, (J["j1"] - J["i0"]) % N - 1))]
    skip_by_side[outer_lat].update(win)
    foot_j = [(-Rw, H + W, -H - W, H + W), (-H - W, H + W, H + W, Rn)]   # Kreuzungsbereich samt Randbereichen
    # Mittelfläche und die geraden Reststücke bis zu den Bogenenden (Straße läuft geradeaus durch)
    for reg in ((-H, H, -H, H), (-Rw, -H, -H, H), (-H, H, H, Rn)):
        arm_parts.append(flat(F, "asphalt", *reg, Y_J, 6.0))
        asphalt_rects.append((F, *reg))
    # Außenkanten der beiden anschließenden Straßen, gerade bis zur Kreuzung
    arm_parts += [flat(F, "kerb", -Rw, -H, -H - K, -H, Y_K + 0.001, 1.0), wall(F, "kerb", -Rw, -H, -H, -H, Y_J, Y_K, (0, 1)),
                  flat(F, "gehweg", -Rw, -H, -H - W, -H - K, Y_W, 2.5),
                  flat(F, "kerb", H, H + K, H, Rn, Y_K + 0.001, 1.0), wall(F, "kerb", H, H, H, Rn, Y_J, Y_K, (-1, 0)),
                  flat(F, "gehweg", H + K, H + W, H + W, Rn, Y_W, 2.5)]
    # Fehlt eine Zufahrt, wird ihre Seite wie ein normaler Straßenrand geschlossen (Randstein und Gehweg über die Mündung)
    if not e_len:
        arm_parts += [flat(F, "kerb", H, H + K, -H, H, Y_K + 0.002, 1.0), wall(F, "kerb", H, -H, H, H, Y_J, Y_K, (-1, 0)),
                      flat(F, "gehweg", H + K, H + W, -H - W, H + W, Y_W, 2.5)]
        footprints.append((F, H, H + W, -H - W, H + W))
        placed.append(F.poly(H, H + W, -H - W, H + W))
    if not s_len:
        arm_parts += [flat(F, "kerb", -H, H + K, -H - K, -H, Y_K + 0.002, 1.0), wall(F, "kerb", -H, -H, H, -H, Y_J, Y_K, (0, 1)),
                      flat(F, "gehweg", -H, H + K, -H - W, -H - K, Y_W, 2.5)]
        footprints.append((F, -H - W, H + W, -H - W, -H))
        placed.append(F.poly(-H - W, H + W, -H - W, -H))
    # Einzelne Betonpoller (rot-weiße Kappen) entlang des äußeren Bogens der Rennstrecke zeigen den Weg durch die Kreuzung,
    # wie bei Umleitungen und Stadtkursen; die geradeaus weiterführenden Straßen bleiben trotzdem als Straßen erkennbar.
    if e_len or s_len:
        mid = center[(J["i0"] + ((J["j1"] - J["i0"]) % N) // 2) % N]
        r_arc = (mid - P).length / (math.sqrt(2.0) - 1.0)            # Bogenradius der Mittellinie (90°-Kurve)
        r_wall = r_arc + H + 0.45
        n_posts = max(8, int(0.5 * math.pi * r_wall / 1.8))
        for kb in range(n_posts):
            th = -math.pi / 2 + (math.pi / 2) * (kb + 0.5) / n_posts # vom Bogenanfang (Richtung -b) bis zum Bogenende (+a)
            pos = F.pt(-r_arc, r_arc) + (F.u * math.cos(th) + F.v * math.sin(th)) * r_wall
            la, lb = (pos - P).dot(F.u), (pos - P).dot(F.v)
            # nur auf der Fahrbahn (nicht auf Randstein/Gehweg): Kreuzband der beiden Straßen
            if not ((abs(lb) < H - 0.3 and la < H - 0.3) or (abs(la) < H - 0.3 and lb > -H + 0.3)):
                continue
            arm_parts += post(pos, 0.25, Y_J, Y_J + 1.0, "beton", "rot" if kb % 2 == 0 else "weiss", cap_h=0.22)
    # Laternen in den äußeren Eckblöcken der Kreuzung
    for la, lb in ((H + W * 0.5 + 0.3, H + W * 0.5 + 0.3), (H + W * 0.5 + 0.3, -H - W * 0.5 - 0.3), (-H - W * 0.5 - 0.3, -H - W * 0.5 - 0.3)):
        lamps.append((F.pt(la, lb), F.pt(0, 0)))
    # Zebrastreifen auf der ankommenden und der abgehenden Straße der Rennstrecke
    if e_len or s_len:
        for k in range(-3, 4):
            arm_parts.append(flat(F, "linie", -H - 4.5, -H - 1.5, k - 0.25, k + 0.25, Y_J + 0.003, 1.0))
            arm_parts.append(flat(F, "linie", k - 0.25, k + 0.25, H + 1.5, min(H + 4.5, Rn - 0.5), Y_J + 0.003, 1.0))
    for reg in foot_j:
        footprints.append((F, *reg))
        placed.append(F.poly(*reg))
    if e_len:
        fe = Frame(F.pt(H, 0), v, u)          # b-Achse entlang u, a-Achse quer (v)
        build_arm(fe, None, e_len, "E", 0, 0, 0.0, u, 1, 0)
        footprints.append((F, H, H + e_len, -H - W, H + W))
        placed.append(F.poly(H, H + e_len, -H - W + 1.5, H + W - 1.5))       # Gehwegrand bleibt für Bäume frei
        arms.append((F.pt(H, 0), u, v, W + 14, e_len - 5))
    if s_len:
        fs = Frame(F.pt(0, -H), u, -v)
        build_arm(fs, None, s_len, "S", 0, 0, 0.0, -v, 1, 0)
        footprints.append((F, -H - W, H + W, -H - s_len, -H))
        placed.append(F.poly(-H - W + 1.5, H + W - 1.5, -H - s_len, -H))
        arms.append((F.pt(0, -H), -v, u, W + 14, s_len - 5))
    print("DIORAMA Ecke", (round(P.x, 1), round(P.y, 1)), "Ost-Arm", e_len, "| Süd-Arm", s_len)

# T-Einmündungen an langen Geraden (Außenseite der Gesamtform)
t_count = 0
runs = []
straight = [c < 0.01 for c in curv]
for i0 in [i for i in range(N) if straight[i] and not straight[i - 1]]:
    e = i0
    while straight[(e + 1) % N] and e - i0 < N:      # zyklisch: die Gerade darf über den Streckenanfang laufen
        e += 1
    runs.append((i0, e))
for (r0, r1) in runs:
    length_m = (r1 - r0) * 0.5
    if length_m < 16:
        continue
    slots = [(r0 + r1) // 2] if length_m < 70 else [r0 + (r1 - r0) // 3, r0 + 2 * (r1 - r0) // 3]
    for kk in slots:
        kk %= N
        Ft = Frame(center[kk], tang[kk], left[kk] * outer)
        keep = keep_except(kk - 80, kk + 80)
        t_len, t_why = best_length(Ft, lambda L: (-FOOT, FOOT, H + W, H + W + L), 40.0, keep)
        if not t_len:
            print("DIORAMA T-Einmündung bei", (round(center[kk].x, 1), round(center[kk].y, 1)), "abgelehnt:", t_why)
            continue
        t_len += W
        skip_by_side[outer].update(x % N for x in range(kk - 8, kk + 9))
        ft = Frame(Ft.pt(0, 0), Ft.u, Ft.v)
        build_arm(ft, None, t_len, "T", 0, 0, H, Ft.v, 1, 0)
        footprints.append((Ft, -FOOT, FOOT, H, H + t_len))
        placed.append(Ft.poly(-FOOT + 1.5, FOOT - 1.5, H, H + t_len))
        arms.append((Ft.pt(0, 0), Ft.v, Ft.u, H + W + 14, H + t_len - 5))
        t_count += 1
        print("DIORAMA T-Einmündung bei", (round(center[kk].x, 1), round(center[kk].y, 1)), "Länge", t_len)

# ---------------------------------------------------------------- Hauptbänder (Fahrbahn, Randsteine, Gehwege)
def ribbon(name, key_of, off_a, off_b, y_a, y_b, tile, skip=None):
    """Band parallel zur Mittellinie zwischen den seitlichen Abständen off_a..off_b (links positiv)."""
    parts = []
    for i in range(N):
        j = (i + 1) % N
        if skip and i in skip:
            continue
        pa0, pa1 = center[i] + left[i] * off_a, center[j] + left[j] * off_a
        pb0, pb1 = center[i] + left[i] * off_b, center[j] + left[j] * off_b
        v0, v1 = dist[i] / tile, dist[i + 1] / tile
        ua, ub = off_a / tile, off_b / tile
        quad = [(pa0.x, pa0.y, y_a), (pb0.x, pb0.y, y_b), (pb1.x, pb1.y, y_b), (pa1.x, pa1.y, y_a)]
        uvs = [(ua, v0), (ub, v0), (ub, v1), (ua, v1)]
        if off_b < off_a:
            quad, uvs = quad[::-1], uvs[::-1]
        parts.append((key_of(i), quad, uvs))
    return mesh_objects(name, parts)


objs_ground = []
objs_ground += ribbon("Fahrbahn", lambda i: "asphalt", -HW, HW, ROAD_Y, ROAD_Y, 6.0)
for s in (-1, 1):
    skip = skip_by_side[float(s)]
    paint = lambda i: "kerb_paint" if curv[i] > 0.02 else "kerb"
    objs_ground += ribbon(f"Linie_{s}", lambda i: "linie", s * (HW - 0.32), s * (HW - 0.2), ROAD_Y + 0.004, ROAD_Y + 0.004, 1.0, skip)
    objs_ground += ribbon(f"Randkante_{s}", paint, s * HW, s * HW, ROAD_Y, KERB_Y, 1.0, skip)
    objs_ground += ribbon(f"Randstein_{s}", paint, s * HW, s * (HW + KERB_W), KERB_Y, KERB_Y, 1.0, skip)
    objs_ground += ribbon(f"Gehweg_{s}", lambda i: "gehweg", s * (HW + KERB_W), s * (HW + SIDE), WALK_Y, WALK_Y, 2.5, skip)
# Innen: gepflasterter Weg als Übergang zum Park (an Kreuzungen der Innenseite ebenfalls ausgespart).
s_in = inside_sign
objs_ground += ribbon("Parkweg", lambda i: "pflaster", s_in * (HW + SIDE), s_in * (HW + 5.8), WALK_Y + 0.002, WALK_Y + 0.002, 3.0,
                      skip_by_side[s_in])
objs_ground += mesh_objects("Kreuzungen", arm_parts)


# ---------------------------------------------------------------- Bodenraster (Zonen)
def in_footprints(P, margin=0.6):
    hit = np.zeros(len(P), bool)
    for fr, a0, a1, b0, b1 in footprints:
        rel = P - np.array([fr.o.x, fr.o.y])
        a = rel @ np.array([fr.u.x, fr.u.y])
        b = rel @ np.array([fr.v.x, fr.v.y])
        hit |= (a >= a0 - margin) & (a <= a1 + margin) & (b >= b0 - margin) & (b <= b1 + margin)
    return hit


xs, zs = C[:, 0], C[:, 1]
MARGIN = 46.0
x0, x1 = math.floor(xs.min() - MARGIN), math.ceil(xs.max() + MARGIN)
z0, z1 = math.floor(zs.min() - MARGIN), math.ceil(zs.max() + MARGIN)
cells = {"pflaster": [], "gras": []}
for step, want_inside in ((1.0, False), (0.5, True)):
    gx = np.arange(x0, x1, step) + step / 2
    gz = np.arange(z0, z1, step) + step / 2
    P = np.array([[x, z] for z in gz for x in gx])
    d = dist_to_center(P)
    ins = inside(P)
    blocked = in_footprints(P)
    for (x, z), dd, ii, bl in zip(P, d, ins, blocked):
        if dd < HW + 3.0 or ii != want_inside or bl:
            continue
        key = "gras" if ii and dd > HW + 5.2 else "pflaster"
        tile = 3.0
        h = step / 2
        corners_ = [(x - h, z - h, GROUND_Y), (x + h, z - h, GROUND_Y), (x + h, z + h, GROUND_Y), (x - h, z + h, GROUND_Y)][::-1]
        cells[key].append((key, corners_, [(cx / tile, -cz / tile) for cx, cz, _ in corners_]))
for key, parts in cells.items():
    objs_ground.append(mesh_object(f"Boden_{key}", parts))
# Horizont: weiter Rahmen rund um das Stadtgebiet.
far = 400
frame = []
for ax0, az0, ax1, az1 in ((x0 - far, z0 - far, x1 + far, z0), (x0 - far, z1, x1 + far, z1 + far),
                           (x0 - far, z0, x0, z1), (x1, z0, x1 + far, z1)):
    quad = [(ax0, az1, GROUND_Y), (ax1, az1, GROUND_Y), (ax1, az0, GROUND_Y), (ax0, az0, GROUND_Y)]
    frame.append(("weite", quad, [(x / 3.0, -z / 3.0) for x, z, _ in quad]))
mesh_object("Weite", frame)

# ---------------------------------------------------------------- Modelle laden (Bäume, Brunnen) und Häuser (Bausatz)
LIB = {}


def model(name):
    if name not in LIB:
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=f"{PROPS}/{name}.glb")
        new = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
        for o in bpy.data.objects:
            if o not in before and o.type != "MESH":
                bpy.data.objects.remove(o, do_unlink=True)
        obj = new[0]
        for o in new[1:]:
            bpy.data.objects.remove(o, do_unlink=True)
        obj.parent = None
        obj.data.transform(obj.matrix_world)       # Importdrehung in die Punkte übernehmen
        obj.matrix_world = Matrix.Identity(4)
        for col in list(obj.users_collection):
            col.objects.unlink(obj)
        vs = [v.co for v in obj.data.vertices]
        ext = Vector((max(v.x for v in vs) - min(v.x for v in vs), max(v.y for v in vs) - min(v.y for v in vs),
                      max(v.z for v in vs) - min(v.z for v in vs)))
        LIB[name] = (obj, ext)
    return LIB[name]


def rect_corners(cx, cz, hw_, hd, ang):
    ca, sa = math.cos(ang), math.sin(ang)
    return [(cx + ca * dx - sa * dz, cz + sa * dx + ca * dz) for dx, dz in ((-hw_, -hd), (hw_, -hd), (hw_, hd), (-hw_, hd))]


LOD_DIST = 24.0      # Bauten näher als so viele Meter an der Rennstrecke spiegeln sich in der nassen Fahrbahn (eigene Objekte)


def place(name, x, z, ang, height, clearance=FOOT + 0.2, trunk=0.0, check_center=True):
    """Modell (Baum) platzieren. trunk > 0: nur der Stamm zählt (Bäume dürfen mit der Krone über Gehweg/Straße ragen)."""
    obj, ext = model(name)
    s = height / max(ext.z, 1e-4)
    hw_, hd = (trunk, trunk) if trunk > 0 else (ext.x * s / 2 + 0.2, ext.y * s / 2 + 0.2)
    poly = rect_corners(x, z, hw_, hd, ang)
    if check_center and (dist_to_center(np.array(poly + [(x, z)])) < clearance).any():
        return False
    if any(overlaps(poly, q) for q in placed):
        return False
    inst = obj.copy()
    scene.collection.objects.link(inst)
    inst.matrix_world = Matrix.Translation((x, -z, GROUND_Y)) @ Matrix.Rotation(-ang, 4, "Z") @ Matrix.Scale(s, 4)
    placed.append(poly)
    return True


kit_near, kit_far = [], []      # Flächen aller Häuser, getrennt nach Nähe zur Strecke
house_kinds = {}


def kit_dims(spec):
    st = kit_house.STYLES[spec["style"]]
    return max(2, round(spec["w"] / st["bay"])) * st["bay"], max(2, round(spec["d"] / st["bay"])) * st["bay"]


def place_house(spec, cx, cz, ux, uz, fx, fz, check_center=True, clearance=FOOT + 0.2):
    """Haus aus dem Bausatz setzen (u längs der Fassade, f zur Straße); False, wenn es nicht passt."""
    parts, foot, dims = kit_house.build_house(KIT_TILES, spec, cx, cz, ux, uz, fx, fz, base_y=GROUND_Y - 0.03)
    if check_center and (dist_to_center(np.array(foot + [(cx, cz)])) < clearance).any():
        return False
    if any(overlaps(foot, q) for q in placed):
        return False
    placed.append(foot)
    house_kinds[spec["kind"]] = house_kinds.get(spec["kind"], 0) + 1
    (kit_near if dist_to_center(np.array([(cx, cz)]))[0] < LOD_DIST else kit_far).extend(parts)
    return True


# ---------------------------------------------------------------- Häuserreihen entlang aller Straßen
def row_along(pts, tans, lefts, side, offset, max_h, check_center=True):
    """Häuser dicht an dicht entlang einer Linie, Fassade zur Straße; misslingt ein Platz, wird ein kleineres Haus
    probiert, erst dann ein Stück weitergerückt."""
    n = len(pts)
    i = 0
    while i < n:
        done = False
        for attempt in range(5):
            spec = kit_house.choose(rng, max_h)
            spec["w"] *= 1.0 - 0.17 * attempt
            spec["floors"] = max(2, spec["floors"] - attempt // 2)
            w, d = kit_dims(spec)
            k = min(n - 1, i + int(w / 2 / 0.5))
            p = pts[k] + lefts[k] * side * (offset + d / 2)
            f = -lefts[k] * side
            if place_house(spec, p.x, p.y, tans[k].x, tans[k].y, f.x, f.y, check_center=check_center):
                i += int((w + 0.3) / 0.5)
                done = True
                break
        if not done:
            i += 3


row_along(center, tang, left, outer, FOOT + 0.6, 14.0)
row_along(center, tang, left, outer, FOOT + 14, 18.0)
row_along(center, tang, left, outer, FOOT + 27, 21.0)
for origin, direction, normal, s0, s1 in arms:
    if s1 - s0 < 6:
        continue
    n_pts = int((s1 - s0) / 0.5)
    pts = [origin + direction * (s0 + 0.5 * k) for k in range(n_pts)]
    for side in (1, -1):
        row_along(pts, [direction] * n_pts, [normal] * n_pts, side, FOOT + 0.6, 14.0, check_center=False)


def nearest_street(p):
    """Richtung (Einheitsvektor) und Blickrichtung zur nächsten Straße (Rennstrecke oder Zufahrt) vom Punkt p aus."""
    d2 = ((C - np.array([p.x, p.y])) ** 2).sum(1)
    i = int(d2.argmin())
    best = (math.sqrt(float(d2[i])), tang[i], (Vector(C[i]) - p).normalized() if d2[i] > 1e-6 else left[i])
    for origin, direction, normal, s0, s1 in arms:
        rel = p - origin
        side = 1.0 if rel.dot(normal) >= 0 else -1.0
        if -1.0 <= rel.dot(direction) <= s1 + 8.0 and abs(rel.dot(normal)) < best[0]:
            best = (abs(rel.dot(normal)), direction, -normal * side)
    return best[1], best[2]


def infill():
    """Übrige Blockflächen mit Häusern füllen, Fassade zur nächsten Straße; Plätze am Raster, leicht versetzt."""
    for zz in np.arange(z0 + 4, z1 - 2, 11.0):
        for xx in np.arange(x0 + 4, x1 - 2, 11.0):
            if rng.random() > 0.92:
                continue
            p = Vector((xx + rng.uniform(-2, 2), zz + rng.uniform(-2, 2)))
            dirv, to_street = nearest_street(p)
            f = to_street - dirv * to_street.dot(dirv)
            f = f.normalized() if f.length > 1e-4 else Vector((-dirv.y, dirv.x))
            for attempt in range(3):
                spec = kit_house.choose(rng, 16.0)
                spec["w"] *= 1.0 - 0.2 * attempt
                spec["floors"] = max(2, spec["floors"] - attempt)
                if place_house(spec, p.x, p.y, dirv.x, dirv.y, f.x, f.y):
                    break


infill()
print("DIORAMA Häuser", sum(house_kinds.values()), house_kinds, len(kit_near), "+", len(kit_far), "Flächen (nah + fern)")

# ---------------------------------------------------------------- Park, Brunnen, Bäume
fountain = next((p for p in data["props"] if p["type"] == "fountain"), None)
if fountain:
    fx, fz = fountain["x"], fountain["z"]
    def ring_object(name, r_out, r_in, y0, y1):
        """Ring (Beckenrand): Außenwand, Oberseite, Innenwand – mit Zylinder-UV für die Steintextur."""
        me = bpy.data.meshes.new(name)
        bm_r = bmesh.new()
        uv_r = bm_r.loops.layers.uv.new("UVMap")
        n_r = 48
        for k in range(n_r):
            t0, t1 = 2 * math.pi * k / n_r, 2 * math.pi * (k + 1) / n_r
            spec = ((r_out, y0, r_out, y1, 1.0), (r_out, y1, r_in, y1, 0.0), (r_in, y1, r_in, y0, -1.0))
            for ra, ya, rb, yb, side in spec:
                pts = [(fx + ra * math.cos(t0), -(fz + ra * math.sin(t0)), ya), (fx + ra * math.cos(t1), -(fz + ra * math.sin(t1)), ya),
                       (fx + rb * math.cos(t1), -(fz + rb * math.sin(t1)), yb), (fx + rb * math.cos(t0), -(fz + rb * math.sin(t0)), yb)]
                f = bm_r.faces.new([bm_r.verts.new(q) for q in pts])
                want = Vector((0, 0, 1)) if side == 0.0 else Vector((math.cos((t0 + t1) / 2), -math.sin((t0 + t1) / 2), 0)) * side
                bm_r.normal_update()
                if f.normal.dot(want) < 0:
                    f.normal_flip()
                for loop in f.loops:
                    v = loop.vert.co
                    loop[uv_r].uv = (math.atan2(-(v.y + 0), v.x - fx) * r_out / 2.0, (v.z if side != 0.0 else math.hypot(v.x - fx, v.y + fz)) / 2.0)
        bm_r.to_mesh(me)
        bm_r.free()
        o = bpy.data.objects.new(name, me)
        scene.collection.objects.link(o)
        me.materials.append(M["stein"])
        return o
    rim = ring_object("Brunnen_Rand", 3.4, 2.95, GROUND_Y, GROUND_Y + 0.55)
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=3.0, depth=0.04, location=(fx, -fz, GROUND_Y + 0.42))
    water = bpy.context.active_object
    water.name = "Brunnen_Wasser"
    water.data.materials.append(M["wasser"])
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.35, depth=1.6, location=(fx, -fz, GROUND_Y + 0.8))
    col = bpy.context.active_object
    col.data.materials.append(M["stein"])
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=1.1, depth=0.25, location=(fx, -fz, GROUND_Y + 1.55))
    bowl = bpy.context.active_object
    bowl.data.materials.append(M["stein"])
    for o in (water, col, bowl):
        # Einfache Zylinderabwicklung (Winkel × Höhe) für die Steintextur.
        me = o.data
        uv = me.uv_layers[0] if me.uv_layers else me.uv_layers.new()
        uv.name = "UVMap"
        for loop in me.loops:
            v = me.vertices[loop.vertex_index].co
            uv.data[loop.index].uv = (math.atan2(v.y, v.x) * 3.4 / 2.0, v.z / 2.0)
    placed.append(rect_corners(fx, fz, 3.6, 3.6, 0))
TREES = ["stadt_baum"]
tree_pool = [t for t in ("stadt_baum_linde", "stadt_baum_ahorn", "stadt_baum_platane", "stadt_baum_kastanie")
             if __import__("os").path.exists(f"{PROPS}/{t}.glb")] or TREES
# Straßenbäume auf dem Gehweg (außen), zwischen den Laternen.
step = int(9.0 / 0.5)
for i in range(step // 2, N, step):
    for side in (outer, inside_sign):
        # Straßenbäume am Außenrand des Gehwegs und klein genug, dass die Krone (Radius ≈ 0,4 × Höhe) nicht über die Fahrbahn ragt
        p = center[i] + left[i] * side * (FOOT - 0.9)
        place(rng.choice(tree_pool), p.x, p.y, rng.uniform(0, 6.28), rng.uniform(5.0, 5.8), clearance=HW + KERB_W + 1.2, trunk=0.5)
# Straßenbäume an den Nebenstraßen (beide Seiten, alle 12 m, am Außenrand des Gehwegs)
for origin, direction, normal, s0, s1 in arms:
    b = 8.0
    while b < s1 + 4.0:
        for side in (1, -1):
            p = origin + direction * b + normal * side * (FOOT - 0.9)
            place(rng.choice(tree_pool), p.x, p.y, rng.uniform(0, 6.28), rng.uniform(5.0, 5.8), trunk=0.5, check_center=False)
        b += 12.0
# Parkbäume auf dem Rasen.
gx = np.arange(x0, x1, 3.0)
gz = np.arange(z0, z1, 3.0)
P = np.array([[x + rng.uniform(-1, 1), z + rng.uniform(-1, 1)] for z in gz for x in gx])
d = dist_to_center(P)
ins = inside(P)
for (x, z), dd, ii in zip(P, d, ins):
    if ii and dd > HW + 7.5 and rng.random() < 0.45:
        place(rng.choice(tree_pool), x, z, rng.uniform(0, 6.28), rng.uniform(6, 9), clearance=HW + 7.0, trunk=1.2)

# ---------------------------------------------------------------- Haus-Objekte (ein Objekt je Oberfläche und Nähe-Gruppe)
house_objs = mesh_objects("Haus_nah", kit_near) + mesh_objects("Haus_fern", kit_far)

# ---------------------------------------------------------------- Lichttextur (Umgebungsverdeckung) backen
SIZE = 4096
ao = bpy.data.images.new("Diorama_AO", SIZE, SIZE, alpha=False)
# Dünne Markierungen (drei Millimeter über dem Asphalt) und die Absperrungen schreiben nicht in die Lichttextur:
# Sie würden den Asphalt darunter dunkel färben und mit ihm um dieselben Bildpunkte streiten. Markierungen bekommen
# die Licht-UV nur zum Auslesen im Spiel und sind beim Backen unsichtbar; Absperrungen bleiben als Hindernis sichtbar.
decal_objs = [o for o in objs_ground if o.name.endswith("_linie")]
solid_objs = [o for o in objs_ground if o.name.endswith(("_rot", "_weiss", "_beton", "_orange"))]
bake_objs = [o for o in objs_ground if o not in decal_objs and o not in solid_objs] +             [o for o in scene.objects if o.name.startswith("Brunnen_Rand")]
EDGE_OUT, EDGE_IN = FOOT, HW + 5.8      # Außenkanten der glatten Bänder
for o in bake_objs + decal_objs:
    me = o.data
    lu = me.uv_layers.new(name="Licht")
    hidden = set()
    if o.name.startswith("Boden_"):
        # Kacheln, die (teilweise) unter den Bändern liegen, backen nicht mit: sonst schreiben sie ihre Verdeckung
        # an dieselbe Stelle der Lichttextur wie das sichtbare Band darüber.
        cen = np.array([[pl.center.x, -pl.center.y] for pl in me.polygons])
        dd = dist_to_center(cen)
        ii = inside(cen)
        limit = np.where(ii, EDGE_IN, EDGE_OUT) + 0.75
        hidden = {k for k in range(len(me.polygons)) if dd[k] < limit[k]}
    for pl in me.polygons:
        for li in pl.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            if pl.index in hidden:
                lu.data[li].uv = (0.0005, 0.9995)
            else:
                lu.data[li].uv = ((v.x - x0) / (x1 - x0), 1.0 - (-v.y - z0) / (z1 - z0))
    me.uv_layers.active = lu
    lu.active_render = True
for mat in {m for o in bake_objs for m in o.data.materials}:
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = ao
    node.name = "Bake"
    mat.node_tree.nodes.active = node
scene.render.engine = "CYCLES"
prefs = bpy.context.preferences.addons["cycles"].preferences
try:
    prefs.compute_device_type = "OPTIX"
    prefs.get_devices()
    for dev in prefs.devices:
        dev.use = dev.type == "OPTIX"
    scene.cycles.device = "GPU"
except Exception as error:
    print("GPU nicht verfügbar:", error)
scene.cycles.samples = 128
scene.world = bpy.data.worlds.new("Himmel")
scene.world.color = (1, 1, 1)
scene.world.light_settings.distance = 6.0
bpy.ops.object.select_all(action="DESELECT")
for o in bake_objs:
    o.select_set(True)
for o in decal_objs:
    o.hide_render = True
bpy.context.view_layer.objects.active = bake_objs[0]
bpy.ops.object.bake(type="AO", margin=8)
for o in decal_objs:
    o.hide_render = False
# Ungebackene Lücken (reines Schwarz) hell füllen, dann kompakt als Graustufen-JPG speichern.
px = np.array(ao.pixels[:], dtype=np.float32).reshape(SIZE, SIZE, 4)
px[px[..., 0] < 0.02, :3] = 1.0
ao.pixels = px.ravel()
ao.scale(2048, 2048)
scene.view_settings.view_transform = "Standard"
settings = scene.render.image_settings
settings.file_format = "JPEG"
settings.color_mode = "BW"
settings.quality = 90
ao.save_render(OUT_AO, scene=scene)
for mat in {m for o in bake_objs for m in o.data.materials}:
    mat.node_tree.nodes.remove(mat.node_tree.nodes["Bake"])
for o in bake_objs + decal_objs:
    o.data.uv_layers.active = o.data.uv_layers["UVMap"]
    o.data.uv_layers["UVMap"].active_render = True

# ---------------------------------------------------------------- Begleitdatei: Straßenflächen für das Spiel
blocked = []
for fr, a0, a1, b0, b1 in asphalt_rects:
    blocked.append([round(fr.o.x, 3), round(fr.o.y, 3), round(fr.u.x, 5), round(fr.u.y, 5), round(fr.v.x, 5), round(fr.v.y, 5),
                    a0 - 0.4, a1 + 0.4, b0 - 0.4, b1 + 0.4])
json.dump({"blocked": blocked,
           "lamps": [{"x": round(a.x, 3), "z": round(a.y, 3), "toward": [round(t.x, 3), round(t.y, 3)]} for a, t in lamps]},
          open(OUT_GLB.replace(".glb", "_layout.json"), "w"))
print("DIORAMA Boden", sum(len(o.data.polygons) for o in objs_ground), "Flächen, Modelle", len(placed), "Zufahrten", len(arms))
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", export_yup=True, export_image_format="JPEG",
                          export_jpeg_quality=88, export_apply=True)
