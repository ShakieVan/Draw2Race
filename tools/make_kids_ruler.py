"""Blender: Lineal der Wippe im Kinderzimmer -> game/assets/props/kinder_lineal.glb (Höhenplan docs/dioramen/HOEHEN_PLAN.md, A5/C2).

Das Spiel (world.gd build_seesaw_nodes) lädt das Modell am Drehpunkt der Wippe und skaliert es auf length x thickness x width der Streckendatei.
Das Modell ist deshalb normiert: 1 m entlang +x (Mitte am Drehpunkt, +x = Ausfahrtsende), Oberseite bei y 0 (Unterseite bei y -1), Breite 1 m
(z von -0,5 bis 0,5). Gebaut wird in echten Maßen der ersten Wippe von game/tracks/kids.json (24 x 4 x 0,3 m) und am Ende auf das Normmaß
geteilt; die Teile sehen deshalb nur bei diesen Maßen richtig aus (andere Maße: neu erzeugen).

Teile: Buche (Oberseite mit Zentimeterskala 0-60 und von oben lesbaren Ziffern, game/assets/dio/kids/lineal_wippe_oben.jpg aus
tools/make_kids_textures.py lineal_wippe), Seiten- und Unterseite Buche, rote Endkappen, rot-weiß schraffierte Stirn am Einfahrtsende (wird
angehoben zur Gefahr für Nachfolger), abgeschrägte Unterseite an beiden Enden (das tiefe Ende liegt in Ruhelage plan auf), rote Knetkugel als
Gegengewicht an der Seitenkante des Einfahrtsendes (Südseite, Godot -z).

Aufruf: powershell -File tools/blender.ps1 tools/make_kids_ruler.py   (oder blender --background --python tools/make_kids_ruler.py)
"""
import json
import math
import os

import bmesh
import bpy
from mathutils import Vector, noise

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TRACK = os.path.join(ROOT, "game", "tracks", "kids.json")
TEX = os.path.join(ROOT, "game", "assets", "dio", "kids")
OUT = os.path.join(ROOT, "game", "assets", "props", "kinder_lineal.glb")

spec = (json.load(open(TRACK, encoding="utf-8")).get("seesaws") or [{}])[0]
L = float(spec.get("length", 24.0))
W = float(spec.get("width", 4.0))
T = float(spec.get("thickness", 0.3))
PIVOT_H = float(spec.get("pivot_h", 1.1))
THETA = math.asin(min(1.0, PIVOT_H / (L / 2)))
BEVEL_LEN = 1.5                                  # abgeschrägte Unterseite an den Enden
BEVEL_H = BEVEL_LEN * math.sin(THETA)
CAP = 0.45                                       # Länge der Endkappen

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def mat_tex(name, image, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Specular IOR Level"].default_value = 0.25          # seidenmatter Lack: nachts kein heller Himmelsglanz
    tx = m.node_tree.nodes.new("ShaderNodeTexImage")
    tx.image = bpy.data.images.load(os.path.join(TEX, image))
    m.node_tree.links.new(tx.outputs["Color"], bsdf.inputs["Base Color"])
    return m


def mat_col(name, col, rough):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*col, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    return m


MATS = [mat_tex("Lineal_Oben", "lineal_wippe_oben.jpg", 0.78), mat_tex("Lineal_Teile", "lineal_wippe_teile.png", 0.8),
        mat_col("Lineal_Kappe", (0.62, 0.04, 0.03), 0.55), mat_col("Lineal_Knete", (0.70, 0.06, 0.05), 0.85)]
TOP, PARTS, CAPM, CLAY = range(4)

bm = bmesh.new()
uvl = bm.loops.layers.uv.new("UVMap")


def face(pts, uvs, mi, outward):
    """Fläche (Blender-Koordinaten: x längs, y = -Breite (Godot z), z oben) mit Normale in Richtung outward."""
    vs = [bm.verts.new(p) for p in pts]
    f = bm.faces.new(vs)
    f.material_index = mi
    f.normal_update()
    if f.normal.dot(Vector(outward)) < 0:
        f.normal_flip()
        uvs = list(uvs)
    for loop in f.loops:
        loop[uvl].uv = uvs[vs.index(loop.vert)]
    return f


def top_uv(x, y):
    """Oberseite: Bild links = Ausfahrtsende (+x), oben = Nordkante (Godot +z = Blender -y): von oben im Spiel lesbar."""
    return ((L / 2 - x) / L, (-y + W / 2) / W)


def side_uv(x, z):
    return ((x + L / 2) / L * 3.0, 0.5 + 0.5 * (z + T) / T * 0.98)


hw = W / 2
xa, xb = -L / 2, L / 2
# Unterseite: eben bis BEVEL_LEN vor den Enden, dann um BEVEL_H angehoben (Fase, das tiefe Ende liegt plan auf)
bot = [(xa, -T + BEVEL_H), (xa + BEVEL_LEN, -T), (xb - BEVEL_LEN, -T), (xb, -T + BEVEL_H)]
# Oberseite (Skala)
face([(xa, hw, 0), (xb, hw, 0), (xb, -hw, 0), (xa, -hw, 0)], [top_uv(xa, hw), top_uv(xb, hw), top_uv(xb, -hw), top_uv(xa, -hw)], TOP, (0, 0, 1))
# Unterseite in drei Stücken
for (x0, z0), (x1, z1) in zip(bot, bot[1:]):
    face([(x0, hw, z0), (x1, hw, z1), (x1, -hw, z1), (x0, -hw, z0)],
         [((x0 + L / 2) / L * 3.0, 0.52), ((x1 + L / 2) / L * 3.0, 0.52), ((x1 + L / 2) / L * 3.0, 0.98), ((x0 + L / 2) / L * 3.0, 0.98)], PARTS, (0, 0, -1))
# Seiten (Fünfecke durch die Fase)
for sy in (1.0, -1.0):
    outline = [(xa, 0.0), (xb, 0.0)] + [(x, z) for x, z in reversed(bot)]
    face([(x, sy * hw, z) for x, z in outline], [side_uv(x, z) for x, z in outline], PARTS, (0, sy, 0))
# Stirnseiten: Ausfahrt Buche, Einfahrt rot-weiß schraffiert
face([(xb, hw, 0), (xb, -hw, 0), (xb, -hw, -T + BEVEL_H), (xb, hw, -T + BEVEL_H)], [(0, 0.6), (1, 0.6), (1, 0.9), (0, 0.9)], PARTS, (1, 0, 0))
face([(xa, hw, 0), (xa, -hw, 0), (xa, -hw, -T + BEVEL_H), (xa, hw, -T + BEVEL_H)], [(0, 0.0), (1, 0.0), (1, 0.4), (0, 0.4)], PARTS, (-1, 0, 0))


def cap(x_in, x_out, hatched):
    """Endkappe aus rotem Kunststoff: umschließt die letzten CAP Meter, 4 cm breiter, 2,5 cm über der Oberseite."""
    sgn = 1.0 if x_out > x_in else -1.0
    y0, y1 = hw + 0.04, -(hw + 0.04)
    zt = 0.025
    zb_in = -T - 0.03 + (BEVEL_H * max(0.0, (abs(x_in) - (L / 2 - BEVEL_LEN)) / BEVEL_LEN))
    zb_out = -T - 0.03 + BEVEL_H
    c = (0.5, 0.5)
    face([(x_in, y0, zt), (x_out, y0, zt), (x_out, y1, zt), (x_in, y1, zt)], [c] * 4, CAPM, (0, 0, 1))
    for sy, yy in ((1.0, y0), (-1.0, y1)):
        face([(x_in, yy, zt), (x_out, yy, zt), (x_out, yy, zb_out), (x_in, yy, zb_in)], [c] * 4, CAPM, (0, sy, 0))
    face([(x_in, y0, zb_in), (x_out, y0, zb_out), (x_out, y1, zb_out), (x_in, y1, zb_in)], [c] * 4, CAPM, (0, 0, -1))
    if hatched:
        face([(x_out, y0, zt), (x_out, y1, zt), (x_out, y1, zb_out), (x_out, y0, zb_out)], [(0, 0.0), (1, 0.0), (1, 0.45), (0, 0.45)], PARTS, (sgn, 0, 0))
    else:
        face([(x_out, y0, zt), (x_out, y1, zt), (x_out, y1, zb_out), (x_out, y0, zb_out)], [c] * 4, CAPM, (sgn, 0, 0))


cap(xb - CAP, xb + 0.03, False)
cap(xa + CAP, xa - 0.03, True)
# Knetkugel: an der Südkante (Godot -z = Blender +y) des Einfahrtsendes angedrückt, etwas plattgedrückt und unregelmäßig
res = bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=9, radius=0.5)
ball_c = Vector((xa + 1.4, hw + 0.30, -0.08))
for v in res["verts"]:
    n = v.co.normalized()
    v.co = Vector((v.co.x * 1.05, v.co.y * 0.72, v.co.z * 0.9)) * (1.0 + 0.07 * noise.noise(n * 2.3 + Vector((3, 1, 2)))) + ball_c
for f in bm.faces:
    if all(v in res["verts"] for v in f.verts):
        f.material_index = CLAY
        f.smooth = True
        for loop in f.loops:
            loop[uvl].uv = (0.5, 0.5)
bm.normal_update()
# auf Normmaß teilen (das Spiel skaliert auf length x thickness x width)
for v in bm.verts:
    v.co = Vector((v.co.x / L, v.co.y / W, v.co.z / T))
me = bpy.data.meshes.new("kinder_lineal")
bm.to_mesh(me)
bm.free()
for m in MATS:
    me.materials.append(m)
obj = bpy.data.objects.new("kinder_lineal", me)
scene.collection.objects.link(obj)
bpy.ops.object.select_all(action="DESELECT")
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True, export_apply=True)
print("LINEAL", OUT, "Maße", L, W, T, "Fase", round(BEVEL_H, 3), "Dreiecke", sum(len(p.vertices) - 2 for p in me.polygons))
