"""Stadtbaum mit dichter, geschlossener Krone (Blender): Stamm plus überlappende Kronenblasen, Blatttextur aus dem Bild.

Die Bild-zu-3D-KI baut Laub nur als dünne, löchrige Hülle; für die Draufsicht braucht es volle Kronen. Deshalb baut dieses
Skript die Form selbst (Blasen mit leichter Verformung, innen liegende Flächen entfernt, Vertexfarben als Höhenschatten)
und legt die Blätter der ChatGPT-Vorlage als Textur darüber. Ergebnis ist auf Höhe 1 normiert, Fuß auf y = 0.
Aufruf: tools/blender.ps1 tools/make_tree.py <blatt.jpg> <aus.glb> <art> <seed> [<feinheit 2|3>]      art: linde | ahorn | platane | kastanie
"""
import math
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

blatt, dst, art, seed = sys.argv[sys.argv.index("--") + 1:][:4]
_extra = sys.argv[sys.argv.index("--") + 5:]
SUBDIV = int(_extra[0]) if _extra else 2      # Feinheit der Kronenblasen: 2 genügt (Blattstruktur kommt aus der Textur), 3 ist das Doppelte
rng = random.Random(int(seed))
# Verhältnisse zur Gesamthöhe 8 m: Kronenradius, Kronenhöhe (Anteil), Stammhöhe bis Kronenansatz, Stammfarbe, Blattfarbton
ARTEN = {
    "linde":    dict(rx=0.42, hz=0.72, stamm=0.28, rinde=(0.30, 0.24, 0.19), ton=(1.00, 1.05, 0.85)),
    "ahorn":    dict(rx=0.34, hz=0.80, stamm=0.24, rinde=(0.27, 0.23, 0.19), ton=(0.92, 1.00, 0.88)),
    "platane":  dict(rx=0.50, hz=0.68, stamm=0.32, rinde=(0.62, 0.58, 0.48), ton=(1.02, 1.06, 0.86)),
    "kastanie": dict(rx=0.46, hz=0.66, stamm=0.30, rinde=(0.20, 0.15, 0.12), ton=(0.80, 0.92, 0.80)),
}[art]
H = 8.0
crown_r = H * ARTEN["rx"]
crown_h = H * ARTEN["hz"]
z_base = H * ARTEN["stamm"]
cz = z_base + crown_h / 2

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# --- Kronenblasen: Kugeln auf einer Ellipsoid-Schale plus einige im Inneren/oben, damit nichts durchscheint
blobs = []
n_shell = 19
for i in range(n_shell):
    phi = math.acos(1 - 2 * (i + 0.5) / n_shell)                       # gleichmäßig über die Kugel
    theta = math.pi * (1 + 5 ** 0.5) * i
    p = Vector((math.sin(phi) * math.cos(theta) * crown_r * 0.62, math.sin(phi) * math.sin(theta) * crown_r * 0.62,
                math.cos(phi) * crown_h * 0.34))
    p.z = max(p.z, -crown_h * 0.28)
    p *= rng.uniform(0.88, 1.12)                                          # Schale unregelmäßig
    blobs.append((Vector((p.x, p.y, cz + p.z)), crown_r * rng.uniform(0.30, 0.44)))
for _ in range(6):
    blobs.append((Vector((rng.uniform(-1, 1) * crown_r * 0.30, rng.uniform(-1, 1) * crown_r * 0.30, cz + crown_h * rng.uniform(0.02, 0.30))),
                  crown_r * rng.uniform(0.42, 0.52)))
for _ in range(6):                                                         # kleine Büschel an der Oberfläche
    phi = rng.uniform(0.0, 1.2)
    theta = rng.uniform(0.0, 2 * math.pi)
    blobs.append((Vector((math.sin(phi) * math.cos(theta) * crown_r * 0.85, math.sin(phi) * math.sin(theta) * crown_r * 0.85,
                          cz + math.cos(phi) * crown_h * 0.46)), crown_r * rng.uniform(0.18, 0.26)))

bm = bmesh.new()
for center, radius in blobs:
    bmesh.ops.create_icosphere(bm, subdivisions=SUBDIV, radius=radius, matrix=Matrix.Translation(center), calc_uvs=False)
bm.verts.ensure_lookup_table()
# Verformung: Rauschen entlang der Normale (Blattbüschel), Kugelzugehörigkeit vorher merken.
owner = {}
per = len(bmesh.ops.create_icosphere(bmesh.new(), subdivisions=SUBDIV, radius=1.0)["verts"])
for idx, v in enumerate(bm.verts):
    owner[v.index] = idx // per
for v in bm.verts:
    c, r = blobs[owner[v.index]]
    n = (v.co - c).normalized()
    bump = noise.noise(v.co * 1.9 + Vector((3.1, 1.3, 7.7))) * 0.24 * r + noise.noise(v.co * 5.1) * 0.10 * r
    v.co += n * bump
# Innenliegende Flächen entfernen (alle Ecken liegen in einer anderen Blase).
def inside_other(v):
    for j, (c, r) in enumerate(blobs):
        if j != owner[v.index] and (v.co - c).length < r * 0.90:
            return True
    return False
inner = {v.index for v in bm.verts if inside_other(v)}
bmesh.ops.delete(bm, geom=[f for f in bm.faces if all(v.index in inner for v in f.verts)], context="FACES")
bm.verts.ensure_lookup_table()
for f in bm.faces:
    f.smooth = True

# --- UV (Würfelprojektion in Weltmaßen) und Vertexfarben (Höhenschatten, leichte Blasenvariation)
uv = bm.loops.layers.uv.new("UVMap")
col = bm.loops.layers.float_color.new("Color")
tile = 2.2
zmin = min(v.co.z for v in bm.verts)
zmax = max(v.co.z for v in bm.verts)
shade_of = {}
for i, (c, r) in enumerate(blobs):
    shade_of[i] = rng.uniform(0.90, 1.08)
for f in bm.faces:
    n = f.normal
    ax = max(range(3), key=lambda k: abs(n[k]))
    for loop in f.loops:
        p = loop.vert.co
        u, w = ((p.y, p.z), (p.x, p.z), (p.x, p.y))[ax]
        loop[uv].uv = (u / tile, w / tile)
        t = (p.z - zmin) / max(zmax - zmin, 1e-6)
        s = (0.50 + 0.50 * t ** 0.85) * shade_of[owner[loop.vert.index]]
        tint = ARTEN["ton"]
        loop[col] = (min(1.0, s * tint[0]), min(1.0, s * tint[1]), min(1.0, s * tint[2]), 1.0)
mesh_krone = bpy.data.meshes.new("Krone")
bm.to_mesh(mesh_krone)
bm.free()
krone = bpy.data.objects.new("Krone", mesh_krone)
scene.collection.objects.link(krone)

# --- Stamm: verjüngter Zylinder bis in die Krone
bm2 = bmesh.new()
sides = 8
r_bot, r_top = H * 0.036, H * 0.022
top = cz + crown_h * 0.1
rings = []
for zk, rk in ((0.0, r_bot * 1.25), (0.35, r_bot), (z_base * 0.9, r_top * 1.3), (top, r_top)):
    rings.append([bm2.verts.new((math.cos(2 * math.pi * k / sides) * rk, math.sin(2 * math.pi * k / sides) * rk, zk)) for k in range(sides)])
for a, b in zip(rings, rings[1:]):
    for k in range(sides):
        bm2.faces.new([a[k], a[(k + 1) % sides], b[(k + 1) % sides], b[k]])
uv2 = bm2.loops.layers.uv.new("UVMap")
for f in bm2.faces:
    for loop in f.loops:
        loop[uv2].uv = (math.atan2(loop.vert.co.y, loop.vert.co.x) / math.pi * 0.5, loop.vert.co.z / 2.0)
    f.smooth = True
bmesh.ops.recalc_face_normals(bm2, faces=bm2.faces)
mesh_stamm = bpy.data.meshes.new("Stamm")
bm2.to_mesh(mesh_stamm)
bm2.free()
stamm = bpy.data.objects.new("Stamm", mesh_stamm)
scene.collection.objects.link(stamm)

# --- Materialien
m_blatt = bpy.data.materials.new("AIProp")
m_blatt.use_nodes = True
nt = m_blatt.node_tree
bsdf = nt.nodes["Principled BSDF"]
bsdf.inputs["Roughness"].default_value = 0.85
tex_node = nt.nodes.new("ShaderNodeTexImage")
tex_node.image = bpy.data.images.load(blatt)
vc = nt.nodes.new("ShaderNodeVertexColor")
vc.layer_name = "Color"
mix = nt.nodes.new("ShaderNodeMix")
mix.data_type = "RGBA"
mix.blend_type = "MULTIPLY"
mix.inputs["Factor"].default_value = 1.0
nt.links.new(tex_node.outputs["Color"], mix.inputs[6])
nt.links.new(vc.outputs["Color"], mix.inputs[7])
nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
krone.data.materials.append(m_blatt)
m_rinde = bpy.data.materials.new("AIProp_Rinde")
m_rinde.use_nodes = True
m_rinde.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*[c ** 2.2 for c in ARTEN["rinde"]], 1.0)  # sRGB → linear
m_rinde.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
stamm.data.materials.append(m_rinde)

# --- Zusammenführen, normieren (Höhe 1, Fuß auf 0, mittig), exportieren
for o in (krone, stamm):
    o.select_set(True)
bpy.context.view_layer.objects.active = krone
bpy.ops.object.join()
obj = bpy.context.active_object
obj.name = "Prop"
vs = [v.co for v in obj.data.vertices]
lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
obj.data.transform(Matrix.Translation(Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z))))
obj.data.transform(Matrix.Scale(1.0 / max(hi.z - lo.z, 1e-4), 4))
print("BAUM", art, "Dreiecke", sum(len(p.vertices) - 2 for p in obj.data.polygons), "Breite/Tiefe", round((hi.x - lo.x) / (hi.z - lo.z), 2), round((hi.y - lo.y) / (hi.z - lo.z), 2))
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_apply=True, export_yup=True,
                          export_image_format="JPEG", export_jpeg_quality=88)
