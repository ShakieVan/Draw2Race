"""Macht aus einem KI-Automodell (z. B. TRELLIS.2, ein Netz mit Farbtextur) ein spielfertiges Auto.

Aufruf:  powershell -File tools/blender.ps1 tools/ai_car.py <eingabe.glb> <ausgabe.glb> <stil> [--flip] [--yaw GRAD] [--preview ORDNER]

Schritte: Netz vereinen, Längsachse per Hauptachsenanalyse auf x drehen (vorn/hinten automatisch an den roten Rückleuchten; --flip: Ergebnis umkehren, --yaw:
Feinkorrektur), auf die Spiellänge des Stils skalieren, auf den Boden stellen. Die Radpositionen werden aus den
Aufstandsflächen der Reifen bestimmt; die KI-Räder werden herausgeschnitten und durch bewegliche Räder aus
make_car.py ersetzt (Wheel_FL/FR/RL/RR). Dunkle Radhaus-Schalen verdecken die Schnittkanten. Die Karosserie heißt
"Body" (für Federung im Spiel), ihr Material "AIBody" (Lack-Shader im Spiel).
"""
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_car  # noqa: E402  (Radbau und Materialien wiederverwenden)

# Ziellänge je Stil (m, wie im Spiel) und Radmaße.
TARGET = {k: (v["L"], v["r"], v["tw"]) for k, v in make_car.STYLES.items()}


def args():
    a = sys.argv[sys.argv.index("--") + 1:]
    opts = {"flip": "--flip" in a, "yaw": 0.0, "preview": None}
    if "--yaw" in a:
        opts["yaw"] = float(a[a.index("--yaw") + 1])
    if "--radius" in a:
        opts["radius"] = float(a[a.index("--radius") + 1])
    if "--preview" in a:
        opts["preview"] = a[a.index("--preview") + 1]
    return a[0], a[1], a[2], opts


def import_body(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    body = bpy.context.active_object
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in list(bpy.context.scene.objects):
        if o != body:
            bpy.data.objects.remove(o, do_unlink=True)
    body.name = "Body"
    body.data.name = "Body"
    for i, m in enumerate(body.data.materials):
        if m is not None:
            m.name = "AIBody" if i == 0 else "AIBody%d" % i
    return body


def align(body, length, flip, yaw):
    verts = [v.co.copy() for v in body.data.vertices]
    cx = sum(v.x for v in verts) / len(verts)
    cy = sum(v.y for v in verts) / len(verts)
    sxx = sum((v.x - cx) ** 2 for v in verts)
    syy = sum((v.y - cy) ** 2 for v in verts)
    sxy = sum((v.x - cx) * (v.y - cy) for v in verts)
    angle = 0.5 * math.atan2(2 * sxy, sxx - syy)   # Hauptachse in der Bodenebene
    body.data.transform(Matrix.Rotation(-angle, 4, "Z"))
    # Vorn/hinten: Die Hauptachse hat kein Vorzeichen. Das Ende mit mehr Rot (Rückleuchten) ist das Heck (-x).
    red_front, red_back = redness_by_end(body)
    turn = red_front > red_back
    if flip:
        turn = not turn
    print("AICAR Rot vorn/hinten", round(red_front, 5), round(red_back, 5), "-> drehen" if turn else "")
    body.data.transform(Matrix.Rotation(math.radians(yaw) + (math.pi if turn else 0.0), 4, "Z"))
    xs = [v.co.x for v in body.data.vertices]
    zs = [v.co.z for v in body.data.vertices]
    scale = length / (max(xs) - min(xs))
    body.data.transform(Matrix.Scale(scale, 4))
    xs = [v.co.x for v in body.data.vertices]
    ys = [v.co.y for v in body.data.vertices]
    zs = [v.co.z for v in body.data.vertices]
    body.data.transform(Matrix.Translation(Vector((-(max(xs) + min(xs)) / 2, -(max(ys) + min(ys)) / 2, -min(zs)))))
    body.data.update()


def redness_by_end(body):
    """Rotanteil der Farbtextur an beiden Enden (x > 0 bzw. x < 0): Rückleuchten verraten das Heck."""
    import numpy as np
    img = None
    for mat in body.data.materials:
        if mat and mat.use_nodes:
            for node in mat.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image is not None:
                    img = node.image
                    break
        if img:
            break
    if img is None:
        return 0.0, 0.0
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    uv = body.data.uv_layers.active.data
    xs = [v.co.x for v in body.data.vertices]
    lo, hi = min(xs), max(xs)
    score = {1: 0.0, -1: 0.0}
    for poly in body.data.polygons:
        c = poly.center.x
        side = 1 if c > hi - (hi - lo) * 0.12 else (-1 if c < lo + (hi - lo) * 0.12 else 0)
        if side == 0:
            continue
        u, v = uv[poly.loop_start].uv
        r, g, b, _ = px[min(h - 1, max(0, int(v * h))), min(w - 1, max(0, int(u * w)))]
        if r > 0.35 and r > 2.2 * g and r > 2.2 * b:
            score[side] += poly.area
    return score[1], score[-1]


def find_wheels(body, r_guess):
    """Aufstandsflächen: Punkte knapp über dem Boden, außen. Je Achse Mittelpunkt in x."""
    vs = [v.co for v in body.data.vertices]
    height = max(v.z for v in vs)
    half = max(abs(v.y) for v in vs)
    low = [v for v in vs if v.z < height * 0.05 and abs(v.y) > half * 0.55]
    front = [v.x for v in low if v.x > 0]
    rear = [v.x for v in low if v.x < 0]
    axles = []
    for group in (rear, front):
        axles.append(sum(group) / len(group) if group else None)
    # Radius messen: senkrechter Schnitt außen durch die Achse. Der Reifen reicht vom Boden bis 2r; darüber
    # folgt die Lücke zum Kotflügel. Erste Lücke > 1,5 cm über dem unteren Viertel = Reifenoberkante.
    radii = []
    for ax in axles:
        if ax is None:
            continue
        zs = sorted(v.z for v in vs if abs(v.x - ax) < 0.03 and abs(v.y) > half * 0.8)
        top = None
        for a, b in zip(zs, zs[1:]):
            if a > r_guess * 1.2 and b - a > 0.015:
                top = a
                break
        if top is not None and r_guess * 0.7 < top / 2 < r_guess * 1.6:
            radii.append(top / 2)
    radius = sum(radii) / len(radii) if radii else r_guess
    return axles, half, height, radius


def cut_wheels(body, axles, r, tw, half):
    bm = bmesh.new()
    bm.from_mesh(body.data)
    doomed = []
    for f in bm.faces:
        c = f.calc_center_median()
        for ax in axles:
            if ax is None:
                continue
            if (Vector((c.x - ax, c.z - r))).length < r * 1.04 and abs(c.y) > half * 0.4:
                doomed.append(f)
                break
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bm.to_mesh(body.data)
    bm.free()
    body.data.update()
    return len(doomed)


def add_wheels(axles, r, tw, half, mats):
    liner = bpy.data.materials.new("Trim")
    liner.use_nodes = True
    liner.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.02, 0.022, 0.025, 1)
    liner.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.7
    for ax, tag in zip(axles, ("R", "F")):
        if ax is None:
            continue
        for side, s in ((1, "L"), (-1, "R")):
            y = side * (half - tw * 0.5 - 0.005)
            make_car.build_wheel("Wheel_%s%s" % (tag, s), (ax, y, r), r, tw, mats)
            # Radhaus-Schale: dunkler Zylinder hinter dem Rad verdeckt die Schnittkante.
            bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=r * 1.12, depth=tw * 1.4,
                                                location=(ax, side * (half - tw * 0.95), r + 0.01), rotation=(math.pi / 2, 0, 0))
            shell = bpy.context.active_object
            shell.name = "Liner_%s%s" % (tag, s)
            shell.data.materials.append(liner)


def main():
    src, dst, style, opts = args()
    length, r, tw = TARGET[style]
    body = import_body(src)
    align(body, length, opts["flip"], opts["yaw"])
    axles, half, height, measured = find_wheels(body, r)
    if opts.get("radius"):
        measured = opts["radius"]
    print("AICAR Radradius Stil/gemessen", r, round(measured, 3))
    r = measured
    tw = tw * max(1.0, r / TARGET[style][1])
    removed = cut_wheels(body, axles, r, tw, half)
    mats = make_car.make_materials()
    add_wheels(axles, r, tw, half, mats)
    for o in bpy.context.scene.objects:
        if o.name.startswith(("Wheel_", "Liner_")):
            o.parent = body if o.name.startswith("Liner_") else None
    print("AICAR", style, "axles", [round(a, 3) if a is not None else None for a in axles], "half", round(half, 3),
          "height", round(height, 3), "removed", removed)
    # Handytauglich: Texturen auf 1024 px, als JPEG im GLB (das Auto ist auf dem Bildschirm klein).
    for img in bpy.data.images:
        if img.size[0] > 1024:
            img.scale(1024, 1024)
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_apply=True, export_yup=True,
                              export_image_format="JPEG", export_jpeg_quality=88)
    if opts["preview"]:
        make_car.render_preview(style, opts["preview"], {"L": length})


if __name__ == "__main__":
    main()
