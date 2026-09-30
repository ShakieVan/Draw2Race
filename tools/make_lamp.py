"""Erzeugt die Straßenlaterne der Stadt (Bausatz) als GLB: Stahlmast, Ausleger mit Strebe, flacher Leuchtenkopf.

Der Ausleger zeigt in +x (das Spiel dreht ihn zur Fahrbahn), der Mast steht im Ursprung, Höhe 4,3 m.
Materialien: K_farbe (Vertexfarbe) und K_lampe (Leuchtfläche unter dem Kopf; das Spiel setzt Emission nach Tageszeit).
Aufruf: tools/blender.ps1 tools/make_lamp.py <ausgabe.glb>
"""
import math
import sys

import bmesh
import bpy

DST = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def lin(c):
    return tuple(v ** 2.2 for v in c)


def material(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.6
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Color"
    nt.links.new(vc.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    return mat


bm = bmesh.new()
col = bm.loops.layers.float_color.new("Color")
uv = bm.loops.layers.uv.new("UVMap")
STEEL = lin((0.30, 0.32, 0.34))
DARK = lin((0.16, 0.17, 0.18))
GLOW = lin((1.0, 0.9, 0.7))


def face(points, color, mat, normal_hint=None):
    """Fläche aus Punkten (x, y, z) in Blender-Koordinaten (z oben); Normale zeigt von normal_hint weg."""
    f = bm.faces.new([bm.verts.new(p) for p in points])
    f.material_index = mat
    for loop in f.loops:
        loop[col] = (*color, 1.0)
        loop[uv].uv = (0.0, 0.0)
    return f


def fix(f, outward):
    bm.normal_update()
    if f.normal.dot(outward) < 0:
        f.normal_flip()


def prism(cx, cy, z0, z1, rx, ry, color, sides=8, mat=0):
    """Senkrechter Prisma-Mast (achteckig) um (cx, cy)."""
    ring = [(cx + rx * math.cos(2 * math.pi * k / sides), cy + ry * math.sin(2 * math.pi * k / sides)) for k in range(sides)]
    for k in range(sides):
        a, b = ring[k], ring[(k + 1) % sides]
        f = face([(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1)], color, mat)
        fix(f, ((a[0] + b[0]) / 2 - cx, (a[1] + b[1]) / 2 - cy, 0.0))
    f = face([(p[0], p[1], z1) for p in ring], color, mat)
    fix(f, (0, 0, 1))


def box(x0, x1, y0, y1, z0, z1, color, bottom_glow=False):
    """Quader; optional mit leuchtender Unterseite (Material 1)."""
    cx, cy, cz = (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2
    for pts, out in (
        ([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], (0, 0, 1)),
        ([(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], (0, -1, 0)),
        ([(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)], (0, 1, 0)),
        ([(x0, y0, z0), (x0, y1, z0), (x0, y1, z1), (x0, y0, z1)], (-1, 0, 0)),
        ([(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)], (1, 0, 0)),
    ):
        fix(face(pts, color, 0), out)
    f = face([(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)], GLOW if bottom_glow else color, 1 if bottom_glow else 0)
    fix(f, (0, 0, -1))


def strut(x0, z0, x1, z1, thick, color):
    """Schräge Strebe in der x-z-Ebene (Rechteckprofil thick × thick)."""
    dx, dz = x1 - x0, z1 - z0
    ln = math.hypot(dx, dz)
    nx, nz = -dz / ln * thick / 2, dx / ln * thick / 2
    y0, y1 = -thick / 2, thick / 2
    quad = [(x0 - nx, y0, z0 - nz), (x1 - nx, y0, z1 - nz), (x1 + nx, y0, z1 + nz), (x0 + nx, y0, z0 + nz)]
    top = [(p[0], y1, p[2]) for p in quad]
    fix(face(quad, color, 0), (0, -1, 0))
    fix(face(top, color, 0), (0, 1, 0))
    for i in range(4):
        j = (i + 1) % 4
        f = face([quad[i], quad[j], top[j], top[i]], color, 0)
        mid = ((quad[i][0] + quad[j][0]) / 2 - (x0 + x1) / 2, 0, (quad[i][2] + quad[j][2]) / 2 - (z0 + z1) / 2)
        fix(f, mid)


H = 4.3
prism(0, 0, 0.0, 0.5, 0.12, 0.12, STEEL, mat=0)                 # Fuß
prism(0, 0, 0.5, H - 0.25, 0.07, 0.07, STEEL, mat=0)            # Mast
prism(0, 0, H - 0.35, H - 0.25, 0.09, 0.09, DARK, mat=0)        # Kragen
box(0.0, 1.15, -0.035, 0.035, H - 0.28, H - 0.20, STEEL)         # Ausleger
strut(0.02, H - 0.9, 0.85, H - 0.24, 0.05, STEEL)               # Strebe
box(0.85, 1.55, -0.16, 0.16, H - 0.31, H - 0.13, DARK, bottom_glow=True)   # Leuchtenkopf

mesh = bpy.data.meshes.new("Laterne")
bm.to_mesh(mesh)
bm.free()
mesh.materials.append(material("K_farbe"))
mesh.materials.append(material("K_lampe"))
obj = bpy.data.objects.new("Prop", mesh)
scene.collection.objects.link(obj)
print("LAMPE Dreiecke", sum(len(p.vertices) - 2 for p in mesh.polygons))
bpy.ops.export_scene.gltf(filepath=DST, export_format="GLB", export_apply=True, export_yup=True, export_image_format="JPEG")
