"""Bereitet ein KI-Kulissenmodell (TRELLIS.2) für das Spiel auf.

Aufruf:  powershell -File tools/blender.ps1 tools/ai_prop.py <eingabe.glb> <ausgabe.glb> <dreiecke> <textur_px> [--preview ORDNER]

Netz vereinen, auf den Boden stellen (tiefster Punkt y = 0), Grundfläche zentrieren, auf Höhe 1 normieren (die
echte Größe setzt das Spiel je Objekttyp), auf das Dreiecksbudget ausdünnen und Texturen verkleinern. Das
Material heißt "AIProp".
"""
import sys

import bpy
from mathutils import Matrix, Vector


def main():
    a = sys.argv[sys.argv.index("--") + 1:]
    src, dst, tris, tex = a[0], a[1], int(a[2]), int(a[3])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.active_object
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in list(bpy.context.scene.objects):
        if o != obj:
            bpy.data.objects.remove(o, do_unlink=True)
    obj.name = "Prop"
    for m in obj.data.materials:
        if m is not None:
            m.name = "AIProp"
    vs = [v.co for v in obj.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    obj.data.transform(Matrix.Translation(Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z))))
    obj.data.transform(Matrix.Scale(1.0 / max(hi.z - lo.z, 1e-4), 4))
    faces = len(obj.data.polygons)
    if faces > tris:
        mod = obj.modifiers.new("Duenn", "DECIMATE")
        mod.ratio = tris / faces
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for img in bpy.data.images:
        if img.size[0] > tex:
            img.scale(tex, tex)
    ext = [(max(v.co[i] for v in obj.data.vertices) - min(v.co[i] for v in obj.data.vertices)) for i in range(3)]
    print("AIPROP", dst.split("/")[-1], "faces", faces, "->", len(obj.data.polygons), "footprint x/y", round(ext[0], 3), round(ext[1], 3))
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_apply=True, export_yup=True,
                              export_image_format="JPEG", export_jpeg_quality=85)


if __name__ == "__main__":
    main()
