"""Baut aus einer Streckendatei ein gebackenes Diorama (Bildebene) für das Spiel.

Die Streckendatei bleibt die Spielebene (Physik, KI, Zeichnen). Dieses Skript erzeugt daraus in Blender eine
komponierte Szene: Fahrbahn, Randsteine und Gehweg als glatte Bänder entlang der Mittellinie, Boden nach Zonen
(außen Pflaster, innen Park), Häuserreihen, Bäume, Brunnen – und backt die Umgebungsverdeckung des Bodens
(Kontaktschatten an Häusern, unter Bäumen, an Randsteinen) in eine Lichttextur (zweite UV-Ebene).

Koordinaten: Spiel (x, y oben, z) = Blender (x, -z, y).
Aufruf: tools/blender.ps1 tools/diorama.py <strecke.json> <aus.glb> <aus_ao.png> <texturordner> <modellordner>
"""
import json
import math
import random
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

A = sys.argv[sys.argv.index("--") + 1:]
TRACK, OUT_GLB, OUT_AO, TEX, PROPS = A[:5]
data = json.load(open(TRACK, encoding="utf-8"))
HW = float(data.get("half_width", 3.5))
ROAD_Y, KERB_Y, WALK_Y, GROUND_Y = 0.17, 0.30, 0.30, 0.295
KERB_W, WALK_W = 0.55, 3.45                  # Randstein 3,5–4,05; Gehweg bis 7,5 m von der Mitte
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
curv = []
for i in range(N):
    a, b = tang[i - 2], tang[(i + 2) % N]
    curv.append(abs(math.atan2(a.x * b.y - a.y * b.x, a.dot(b))) / 2.0)

C = np.array([[p.x, p.y] for p in center])
SEG_A, SEG_B = C, np.roll(C, -1, axis=0)


def dist_to_center(P):
    """Abstand vieler Punkte (n×2) zur Mittellinie."""
    out = np.full(len(P), 1e9)
    d = SEG_B - SEG_A
    ll = np.maximum((d ** 2).sum(1), 1e-9)
    for k in range(0, len(P), 4000):
        q = P[k:k + 4000, None, :]
        t = np.clip(((q - SEG_A) * d).sum(2) / ll, 0, 1)
        proj = SEG_A + t[..., None] * d
        out[k:k + 4000] = np.sqrt(((q - proj) ** 2).sum(2)).min(1)
    return out


def inside(P):
    """Punkt-in-Polygon (Mittellinie) für viele Punkte."""
    x, y = P[:, 0][:, None], P[:, 1][:, None]
    ax, ay, bx, by = SEG_A[:, 0], SEG_A[:, 1], SEG_B[:, 0], SEG_B[:, 1]
    cond = (ay > y) != (by > y)
    xs = ax + (y - ay) * (bx - ax) / np.where(by - ay == 0, 1e-9, by - ay)
    return (cond & (x < xs)).sum(1) % 2 == 1


# ---------------------------------------------------------------- Materialien
def image(path):
    img = bpy.data.images.load(path, check_existing=True)
    return img


def material(name, tex=None, tint=(1, 1, 1), rough=0.8, normal=None, color=None):
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
    "asphalt": material("D_Asphalt", tex("Asphalt031"), (0.42, 0.44, 0.46), 0.85, tex("Asphalt031", "NormalGL")),
    "linie": material("D_Markierung", color=(0.86, 0.84, 0.78), rough=0.6),
    "kerb": material("D_Randstein", tex("Concrete034"), (0.8, 0.8, 0.78), 0.8),
    "kerb_paint": material("D_Randstein_Farbe", stripes(), rough=0.6),
    "gehweg": material("D_Gehweg", tex("Concrete034"), (0.78, 0.76, 0.72), 0.85, tex("Concrete034", "NormalGL")),
    "pflaster": material("D_Pflaster", tex("PavingStones138"), (0.86, 0.84, 0.8), 0.85, tex("PavingStones138", "NormalGL")),
    "gras": material("D_Gras", tex("Grass005"), (0.9, 0.95, 0.85), 0.9, tex("Grass005", "NormalGL")),
    "erde": material("D_Erde", tex("Ground037"), (1, 1, 1), 0.9),
    "wasser": material("D_Wasser", color=(0.25, 0.5, 0.5), rough=0.1),
    "stein": material("D_Stein", tex("Concrete034"), (0.9, 0.88, 0.84), 0.7),
    "weite": material("D_Weite", tex("PavingStones138"), (0.8, 0.78, 0.74), 0.9),
}
MAT_INDEX = {}


def mesh_object(name, parts):
    """parts: Liste (Material-Schlüssel, Ecken[4|3] als (x, z, y), uv0-Liste)."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    uv0 = bm.loops.layers.uv.new("UVMap")
    keys = []
    for key, corners, uvs in parts:
        if key not in keys:
            keys.append(key)
        vs = [bm.verts.new((x, -z, y)) for x, z, y in corners]
        f = bm.faces.new(vs)
        f.material_index = keys.index(key)
        for loop, uv in zip(f.loops, uvs):
            loop[uv0].uv = uv
    bm.normal_update()
    # Waagerechte Flächen nach oben ausrichten (die Achsenumrechnung spiegelt die Umlaufrichtung).
    bmesh.ops.reverse_faces(bm, faces=[f for f in bm.faces if f.normal.z < -0.01])
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for key in keys:
        me.materials.append(M[key])
    obj = bpy.data.objects.new(name, me)
    scene.collection.objects.link(obj)
    return obj


def ribbon(name, key_of, off_a, off_b, y_a, y_b, tile, side=0.0, skip=None):
    """Band parallel zur Mittellinie zwischen den seitlichen Abständen off_a..off_b (links positiv)."""
    parts = []
    for i in range(N):
        j = (i + 1) % N
        if skip and skip(i):
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
    return mesh_object(name, parts)


# ---------------------------------------------------------------- Fahrbahn, Randstein, Gehweg
objs_ground = []
objs_ground.append(ribbon("Fahrbahn", lambda i: "asphalt", -HW, HW, ROAD_Y, ROAD_Y, 6.0))
for s in (-1, 1):
    objs_ground.append(ribbon(f"Linie_{s}", lambda i: "linie", s * (HW - 0.32), s * (HW - 0.2), ROAD_Y + 0.004, ROAD_Y + 0.004, 1.0))
    paint = lambda i: "kerb_paint" if curv[i] > 0.02 else "kerb"
    # Randstein: senkrechte Innenkante, dann Oberseite.
    objs_ground.append(ribbon(f"Randkante_{s}", paint, s * HW, s * HW, ROAD_Y, KERB_Y, 1.0))
    objs_ground.append(ribbon(f"Randstein_{s}", paint, s * HW, s * (HW + KERB_W), KERB_Y, KERB_Y, 1.0))
    objs_ground.append(ribbon(f"Gehweg_{s}", lambda i: "gehweg", s * (HW + KERB_W), s * (HW + KERB_W + WALK_W), WALK_Y, WALK_Y, 2.5))
# Innen: gepflasterter Weg als Übergang zum Park.
s_in = inside_sign
objs_ground.append(ribbon("Parkweg", lambda i: "pflaster", s_in * (HW + KERB_W + WALK_W), s_in * (HW + 5.8), WALK_Y + 0.002, WALK_Y + 0.002, 3.0))

# ---------------------------------------------------------------- Bodenraster (Zonen)
xs, zs = C[:, 0], C[:, 1]
MARGIN = 46.0
x0, x1 = math.floor(xs.min() - MARGIN), math.ceil(xs.max() + MARGIN)
z0, z1 = math.floor(zs.min() - MARGIN), math.ceil(zs.max() + MARGIN)
BOUNDS = (x0, z0, x1, z1)
cells = {"pflaster": [], "gras": []}
for step, want_inside in ((1.0, False), (0.5, True)):
    gx = np.arange(x0, x1, step) + step / 2
    gz = np.arange(z0, z1, step) + step / 2
    P = np.array([[x, z] for z in gz for x in gx])
    d = dist_to_center(P)
    ins = inside(P)
    for (x, z), dd, ii in zip(P, d, ins):
        if dd < HW + 3.0 or ii != want_inside:
            continue
        key = "gras" if ii and dd > HW + 5.2 else "pflaster"
        tile = 3.0
        h = step / 2
        corners = [(x - h, z - h, GROUND_Y), (x + h, z - h, GROUND_Y), (x + h, z + h, GROUND_Y), (x - h, z + h, GROUND_Y)]
        corners = corners[::-1]
        cells[key].append((key, corners, [(cx / tile, -cz / tile) for cx, cz, _ in corners]))
for key, parts in cells.items():
    objs_ground.append(mesh_object(f"Boden_{key}", parts))
# Horizont: weiter Rahmen rund um das Stadtgebiet (nicht darunter – er läge über der Fahrbahn).
far = 400
frame = []
for ax0, az0, ax1, az1 in ((x0 - far, z0 - far, x1 + far, z0), (x0 - far, z1, x1 + far, z1 + far),
                           (x0 - far, z0, x0, z1), (x1, z0, x1 + far, z1)):
    quad = [(ax0, az1, GROUND_Y), (ax1, az1, GROUND_Y), (ax1, az0, GROUND_Y), (ax0, az0, GROUND_Y)]
    frame.append(("weite", quad, [(x / 3.0, -z / 3.0) for x, z, _ in quad]))
objs_far = [mesh_object("Weite", frame)]

# ---------------------------------------------------------------- Modelle laden
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
        scene.collection.objects.unlink(obj) if obj.name in scene.collection.objects else None
        for col in obj.users_collection:
            col.objects.unlink(obj)
        vs = [obj.matrix_world @ v.co for v in obj.data.vertices]
        ext = Vector((max(v.x for v in vs) - min(v.x for v in vs), max(v.y for v in vs) - min(v.y for v in vs),
                      max(v.z for v in vs) - min(v.z for v in vs)))
        LIB[name] = (obj, ext)
    return LIB[name]


placed = []   # (Mitte xz, Halbachsen, Winkel) für Überlappungsprüfung


def rect_corners(cx, cz, hw_, hd, ang):
    ca, sa = math.cos(ang), math.sin(ang)
    return [(cx + ca * dx - sa * dz, cz + sa * dx + ca * dz) for dx, dz in ((-hw_, -hd), (hw_, -hd), (hw_, hd), (-hw_, hd))]


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


def place(name, x, z, ang, height, clearance=HW + KERB_W + WALK_W + 0.2, trunk=0.0):
    """trunk > 0: nur der Stamm zählt (Bäume dürfen mit der Krone über Gehweg/Straße ragen)."""
    obj, ext = model(name)
    s = height / max(ext.z, 1e-4)
    hw_, hd = (trunk, trunk) if trunk > 0 else (ext.x * s / 2 + 0.2, ext.y * s / 2 + 0.2)
    poly = rect_corners(x, z, hw_, hd, ang)
    if True:
        if (dist_to_center(np.array(poly + [(x, z)])) < clearance).any():
            return False
        if any(overlaps(poly, q) for q in placed):
            return False
    inst = obj.copy()
    scene.collection.objects.link(inst)
    inst.matrix_world = Matrix.Translation((x, -z, GROUND_Y)) @ Matrix.Rotation(-ang, 4, "Z") @ Matrix.Scale(s, 4)
    placed.append(poly)
    return True


# ---------------------------------------------------------------- Häuserreihen außen
HOUSES = ["stadt_altbau", "stadt_eckladen", "stadt_wohnblock", "stadt_buero"]
outer = -inside_sign


def house_row(offset, heights):
    """Häuser dicht an dicht entlang der Straße, Längsseite zur Straße; misslingt ein Platz, wird ein
    kleineres Haus probiert, erst dann ein Stück weitergerückt."""
    i = 0
    while i < N:
        done = False
        for attempt in range(4):
            name = rng.choice(HOUSES)
            obj, ext = model(name)
            h = rng.uniform(*heights) * (1.0 - 0.18 * attempt)
            s = h / ext.z
            turn = ext.y > ext.x                      # Längsseite entlang der Straße
            width, depth = (ext.y * s, ext.x * s) if turn else (ext.x * s, ext.y * s)
            k = min(N - 1, i + int(width / 2 / 0.5))
            p = center[k] + left[k] * outer * (offset + depth / 2)
            ang = math.atan2(tang[k].y, tang[k].x) + (math.pi / 2 if turn else 0.0)
            if place(name, p.x, p.y, ang, h):
                i += int((width + 0.3) / 0.5)
                done = True
                break
        if not done:
            i += 3


house_row(HW + KERB_W + WALK_W + 0.6, (9, 14))
house_row(HW + KERB_W + WALK_W + 14, (11, 17))
house_row(HW + KERB_W + WALK_W + 27, (12, 19))

# ---------------------------------------------------------------- Park, Brunnen, Bäume
fountain = next((p for p in data["props"] if p["type"] == "fountain"), None)
if fountain:
    fx, fz = fountain["x"], fountain["z"]
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=3.4, depth=0.55, location=(fx, -fz, GROUND_Y + 0.27))
    rim = bpy.context.active_object
    rim.name = "Brunnen_Rand"
    rim.data.materials.append(M["stein"])
    bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=3.05, depth=0.05, location=(fx, -fz, GROUND_Y + 0.5))
    water = bpy.context.active_object
    water.name = "Brunnen_Wasser"
    water.data.materials.append(M["wasser"])
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.35, depth=1.6, location=(fx, -fz, GROUND_Y + 0.8))
    col = bpy.context.active_object
    col.data.materials.append(M["stein"])
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=1.1, depth=0.25, location=(fx, -fz, GROUND_Y + 1.55))
    bowl = bpy.context.active_object
    bowl.data.materials.append(M["stein"])
    for o in (rim, water, col, bowl):
        # Einfache Zylinderabwicklung (Winkel × Höhe) für die Steintextur.
        me = o.data
        uv = me.uv_layers[0] if me.uv_layers else me.uv_layers.new()
        uv.name = "UVMap"
        for loop in me.loops:
            v = me.vertices[loop.vertex_index].co
            uv.data[loop.index].uv = (math.atan2(v.y, v.x) * 3.4 / 2.0 + v.z * 0.0, v.z / 2.0 + (v.x + v.y) * 0.0)
        o.matrix_world = o.matrix_world
    placed.append(rect_corners(fx, fz, 3.6, 3.6, 0))
# Straßenbäume auf dem Gehweg (außen), zwischen den Laternen.
step = int(11.0 / 0.5)
for i in range(step // 2, N, step):
    for side in (outer, inside_sign):
        p = center[i] + left[i] * side * (HW + KERB_W + WALK_W - 1.1)
        place("stadt_baum", p.x, p.y, rng.uniform(0, 6.28), rng.uniform(6.5, 8.0), clearance=HW + KERB_W + 1.2, trunk=0.8)
# Parkbäume auf dem Rasen.
gx = np.arange(x0, x1, 3.0)
gz = np.arange(z0, z1, 3.0)
P = np.array([[x + rng.uniform(-1, 1), z + rng.uniform(-1, 1)] for z in gz for x in gx])
d = dist_to_center(P)
ins = inside(P)
for (x, z), dd, ii in zip(P, d, ins):
    if ii and dd > HW + 7.5 and rng.random() < 0.45:
        place("stadt_baum", x, z, rng.uniform(0, 6.28), rng.uniform(6, 9), clearance=HW + 7.0, trunk=1.2)

# ---------------------------------------------------------------- Lichttextur (Umgebungsverdeckung) backen
SIZE = 4096
ao = bpy.data.images.new("Diorama_AO", SIZE, SIZE, alpha=False)
bake_objs = objs_ground + [o for o in scene.objects if o.name.startswith("Brunnen_Rand")]
EDGE_OUT, EDGE_IN = HW + KERB_W + WALK_W, HW + 5.8      # Außenkanten der glatten Bänder
for o in bake_objs:
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
scene.cycles.samples = 64
scene.world = bpy.data.worlds.new("Himmel")
scene.world.color = (1, 1, 1)
scene.world.light_settings.distance = 6.0
bpy.ops.object.select_all(action="DESELECT")
for o in bake_objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = bake_objs[0]
bpy.ops.object.bake(type="AO", margin=8)
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
for o in bake_objs:
    o.data.uv_layers.active = o.data.uv_layers["UVMap"]
    o.data.uv_layers["UVMap"].active_render = True
print("DIORAMA Boden", sum(len(o.data.polygons) for o in objs_ground), "Flächen, Modelle", len(placed))
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", export_yup=True, export_image_format="JPEG",
                          export_jpeg_quality=88, export_apply=True)
