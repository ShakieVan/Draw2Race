"""Dreht die Fahrwerke einer KI-Containerbrücke um 90° (Räder laufen dann parallel zur Kaikante, quer zum Ausleger).

Die Bild-zu-3D-KI hat die Fahrwerke verdreht rekonstruiert. Alles unterhalb von CUT (Anteil der Höhe) wird nach
Stütze (vier Quadranten um die Mitte der Fußpunkte) gruppiert und je Gruppe um ihre eigene Mitte um 90° gedreht.
Die Stützen sind quadratisch, der Übergang oberhalb bleibt deshalb geschlossen.
Aufruf: tools/blender.ps1 tools/fix_crane_bogies.py <eingabe.glb> <ausgabe.glb> [cut=0.12] [--preview <png>]
"""
import math
import sys

import bpy
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:]
src, dst = args[0], args[1]
cut = float(args[2]) if len(args) > 2 and not args[2].startswith("--") else 0.12
preview = args[args.index("--preview") + 1] if "--preview" in args else ""

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
world = [(o, v) for o in meshes for v in o.data.vertices]
zs = [(o.matrix_world @ v.co).z for o, v in world]
z0, z1 = min(zs), max(zs)
limit = z0 + (z1 - z0) * cut
low = [(o, v) for o, v in world if (o.matrix_world @ v.co).z < limit]
cx = sum((o.matrix_world @ v.co).x for o, v in low) / len(low)
cy = sum((o.matrix_world @ v.co).y for o, v in low) / len(low)
groups = {}
for o, v in low:
    p = o.matrix_world @ v.co
    groups.setdefault((p.x > cx, p.y > cy), []).append((o, v))
for key, members in groups.items():
    # Drehpunkt = Achse der Stütze: Mitte des Querschnitts knapp unter dem Schnitt (nicht der Fahrwerks-
    # schwerpunkt), damit die quadratische Stütze nach der Drehung wieder genau auf sich selbst liegt.
    ring = [o.matrix_world @ v.co for o, v in members if (o.matrix_world @ v.co).z > limit - (z1 - z0) * 0.015]
    ring = ring or [o.matrix_world @ v.co for o, v in members]
    gx = (min(p.x for p in ring) + max(p.x for p in ring)) / 2
    gy = (min(p.y for p in ring) + max(p.y for p in ring)) / 2
    turn = Matrix.Translation((gx, gy, 0)) @ Matrix.Rotation(math.radians(90), 4, "Z") @ Matrix.Translation((-gx, -gy, 0))
    for o, v in members:
        v.co = o.matrix_world.inverted() @ (turn @ (o.matrix_world @ v.co))
    print("FAHRWERK", key, len(members), "Punkte, Mitte", round(gx, 3), round(gy, 3))
for o in meshes:
    o.data.update()
print("HOEHE", round(z1 - z0, 3), "SCHNITT", round(limit, 3))
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB")

if preview:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x, scene.render.resolution_y = 900, 700
    world_bg = bpy.data.worlds.new("w")
    world_bg.color = (0.55, 0.58, 0.62)
    scene.world = world_bg
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), 0, math.radians(35))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    target = Vector((cx, cy, z0 + (z1 - z0) * 0.08))
    cam.location = target + Vector((0.55, -0.75, 0.35)) * (z1 - z0)
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = preview
    bpy.ops.render.render(write_still=True)
