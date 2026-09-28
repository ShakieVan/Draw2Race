"""Netzprüfung für KI-Modelle (in Blender): Löcher, nicht-mannigfaltige Kanten, lose Bruchstücke, entartete Flächen,
dazu eine Vorschau aus zwei Blickwinkeln.
Aufruf: tools/blender.ps1 tools/mesh_check.py <modell.glb> <vorschau_ordner>
"""
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[-2:]
src, out_dir = Path(args[0]), Path(args[1])
out_dir.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(src))
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]

total = {"faces": 0, "verts": 0, "boundary": 0, "nonmanifold": 0, "degenerate": 0, "islands": 0, "tiny_islands": 0}
for obj in meshes:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.transform(obj.matrix_world)
    # Punkte an Texturnähten zusammenführen (glTF trennt sie), sonst zählt jede Naht als Loch.
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    total["faces"] += len(bm.faces)
    total["verts"] += len(bm.verts)
    total["boundary"] += sum(1 for e in bm.edges if e.is_boundary)
    total["nonmanifold"] += sum(1 for e in bm.edges if not e.is_manifold and not e.is_boundary)
    total["degenerate"] += sum(1 for f in bm.faces if f.calc_area() < 1e-10)
    # Zusammenhängende Teile (über gemeinsame Kanten) und ihre Flächenanteile.
    seen = set()
    area_all = sum(f.calc_area() for f in bm.faces) or 1.0
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, area = [f], 0.0
        seen.add(f.index)
        while stack:
            g = stack.pop()
            area += g.calc_area()
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        total["islands"] += 1
        if area / area_all < 0.001:
            total["tiny_islands"] += 1
    bm.free()

# Grobe Einordnung: Kanten mit offenem Rand oder Bruchstücke sind bei KI-Modellen üblich, solange es wenige sind.
print("MESHCHECK %s %s" % (src.parent.name, " ".join(f"{k}={v}" for k, v in total.items())))

# Vorschau: zwei Ansichten, neutrales Licht.
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
scene.render.resolution_x, scene.render.resolution_y = 900, 700
scene.render.film_transparent = False
world = bpy.data.worlds.new("w")
world.color = (0.55, 0.58, 0.62)
scene.world = world
lo = Vector((min(v[i] for o in meshes for v in [o.matrix_world @ Vector(c) for c in o.bound_box]) for i in range(3)))
hi = Vector((max(v[i] for o in meshes for v in [o.matrix_world @ Vector(c) for c in o.bound_box]) for i in range(3)))
center, radius = (lo + hi) / 2, (hi - lo).length / 2
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 3.5
sun.rotation_euler = (math.radians(50), 0, math.radians(35))
scene.collection.objects.link(sun)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
scene.collection.objects.link(cam)
scene.camera = cam
for name, az, el in (("vorn", -35, 25), ("hinten", 145, 35)):
    d = Vector((math.cos(math.radians(el)) * math.sin(math.radians(az)), -math.cos(math.radians(el)) * math.cos(math.radians(az)), math.sin(math.radians(el))))
    cam.location = center + d * radius * 3.2
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 50
    scene.render.filepath = str(out_dir / f"{src.parent.name}_{name}.png")
    bpy.ops.render.render(write_still=True)
