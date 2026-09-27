"""Parametrischer Autogenerator für Draw2Race (Blender-Skript, frei entworfene Fahrzeuge).

Aufruf:  powershell -File tools/blender.ps1 tools/make_car.py <ausgabeordner> <stil[,stil...]> [--preview]

Die Karosserie wird aus Querschnitten entlang der Fahrzeuglänge geloftet (u = 0 Heck ... 1 Front) und mit
Catmull-Clark geglättet; Radläufe werden ausgeschnitten. Räder sind eigene Objekte (Wheel_FL/FR/RL/RR, Ursprung
in der Nabe), damit das Spiel sie drehen und einlenken kann. Die Lackfarbe setzt das Spiel zur Laufzeit.
Maßstab: 1 Einheit = 1 m im Spiel (Autos sind ~2 m lang, die Fahrbahn 7 m breit). Blender: x vorn, y links, z oben.
"""
import bpy
import bmesh
import math
import sys
from mathutils import Vector

# L Länge, W halbe Breite, clear Bodenfreiheit, belt/nose/tail Gürtellinie mitte/vorn/hinten, roof Dachhöhe,
# rear/wind: u-Bereiche von Heckscheibe (steigt) und Frontscheibe (fällt), roofw halbe Dachbreite,
# r Radradius, axles u-Position Hinter-/Vorderachse, tw Reifenbreite.
STYLES = {
    "coupe":  dict(L=2.08, W=0.43, clear=0.075, belt=0.40, nose=0.31, tail=0.39, roof=0.60, rear=(0.14, 0.33), wind=(0.56, 0.72), roofw=0.32, r=0.155, axles=(0.20, 0.80), tw=0.11),
    "hatch":  dict(L=1.86, W=0.42, clear=0.08, belt=0.41, nose=0.32, tail=0.42, roof=0.66, rear=(0.03, 0.12), wind=(0.60, 0.76), roofw=0.34, r=0.15, axles=(0.17, 0.82), tw=0.105),
    "rally":  dict(L=2.02, W=0.44, clear=0.11, belt=0.45, nose=0.35, tail=0.43, roof=0.68, rear=(0.10, 0.27), wind=(0.57, 0.73), roofw=0.34, r=0.175, axles=(0.19, 0.81), tw=0.12),
    "muscle": dict(L=2.24, W=0.46, clear=0.07, belt=0.41, nose=0.36, tail=0.40, roof=0.59, rear=(0.20, 0.36), wind=(0.52, 0.66), roofw=0.33, r=0.165, axles=(0.20, 0.79), tw=0.125),
    "gt":     dict(L=2.14, W=0.46, clear=0.06, belt=0.34, nose=0.25, tail=0.36, roof=0.53, rear=(0.16, 0.38), wind=(0.52, 0.70), roofw=0.30, r=0.16, axles=(0.20, 0.79), tw=0.13),
}
STATIONS = 44


def smoothstep(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


class Shape:
    def __init__(self, p):
        self.p = p

    def greenhouse(self, u):
        p = self.p
        return smoothstep(*p["rear"], u) * (1.0 - smoothstep(*p["wind"], u))

    def belt(self, u):
        p = self.p
        if u < 0.5:
            return lerp(p["tail"], p["belt"], smoothstep(0.0, 0.28, u))
        return lerp(p["belt"], p["nose"], smoothstep(0.62, 1.0, u))

    def half_width(self, u):
        e = 5.0
        return self.p["W"] * (1.0 - abs(2 * u - 1) ** e) ** (1 / e) * (1.0 - 0.05 * u)

    def bottom(self, u):
        c = self.p["clear"]
        return c + 0.05 * smoothstep(0.86, 1.0, u) + 0.05 * (1.0 - smoothstep(0.0, 0.12, u))

    def ring(self, u):
        wb = max(self.half_width(u), 0.004)
        hs = self.belt(u)
        zb = self.bottom(u)
        gh = self.greenhouse(u)
        hr = hs + max(0.0, self.p["roof"] - hs) * gh
        wr = lerp(wb * 0.78, self.p["roofw"] * min(1.0, wb / self.p["W"] + 0.1), gh)
        half = [
            (wb * 0.80, zb),
            (wb * 0.98, zb + 0.05),
            (wb, zb + 0.6 * (hs - zb)),
            (wb * 0.96, hs),
            (lerp(wb * 0.88, wr, gh), lerp(hs + 0.015, hr - 0.035, gh)),
            (lerp(wb * 0.52, wr * 0.74, gh), lerp(hs + 0.03, hr, gh)),
        ]
        top = (0.0, lerp(hs + 0.035, hr + 0.006, gh))
        pts = [(0.0, zb)] + [(-y, z) for y, z in half] + [top] + [(y, z) for y, z in reversed(half)]
        x = u * self.p["L"] - self.p["L"] / 2
        return [Vector((x, y, z)) for y, z in pts]


def material(name, color, metallic=0.0, rough=0.5, emission=None, coat=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = rough
    if coat > 0:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = 0.03
    if emission:
        b.inputs["Emission Color"].default_value = (*emission, 1.0)
        b.inputs["Emission Strength"].default_value = 3.0
    return m


def make_materials():
    return {
        "Paint": material("Paint", (0.75, 0.12, 0.08), metallic=0.55, rough=0.25, coat=1.0),
        "Glass": material("Glass", (0.015, 0.025, 0.035), metallic=0.0, rough=0.04),
        "Trim": material("Trim", (0.025, 0.028, 0.03), rough=0.55),
        "Rubber": material("Rubber", (0.02, 0.02, 0.022), rough=0.88),
        "Rim": material("Rim", (0.78, 0.8, 0.82), metallic=1.0, rough=0.22),
        "HeadLight": material("HeadLight", (0.9, 0.9, 0.85), rough=0.1, emission=(1.0, 0.95, 0.85)),
        "TailLight": material("TailLight", (0.5, 0.02, 0.02), rough=0.15, emission=(1.0, 0.05, 0.03)),
    }


def link(obj):
    bpy.context.collection.objects.link(obj)
    return obj


def build_body(shape, mats):
    p = shape.p
    mesh = bpy.data.meshes.new("Body")
    bm = bmesh.new()
    rings = []
    for i in range(STATIONS + 1):
        u = 0.004 + 0.992 * i / STATIONS
        rings.append([bm.verts.new(v) for v in shape.ring(u)])
    n = len(rings[0])
    # Materialien schon am groben Gitter vergeben: Die Glättung macht daraus saubere, runde Scheibenkanten.
    # Ringsegmente: 4 und n-5 = Seitenfenster, 5..n-6 = Dach bzw. Front-/Heckscheibe.
    side = {4, n - 5}
    top = set(range(5, n - 5))
    for i, (a, b) in enumerate(zip(rings, rings[1:])):
        u = 0.004 + 0.992 * (i + 0.5) / STATIONS
        gh = shape.greenhouse(u)
        for k in range(n):
            f = bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
            if k in side and gh > 0.3:
                f.material_index = 1
            elif k in top and 0.1 < gh < 0.93:
                f.material_index = 1
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    body = link(bpy.data.objects.new("Body", mesh))
    for name in ["Paint", "Glass", "Trim"]:
        body.data.materials.append(mats[name])
    for poly in mesh.polygons:
        poly.use_smooth = True
    sub = body.modifiers.new("Glatt", "SUBSURF")
    sub.levels = 2
    sub.render_levels = 2
    apply_modifiers(body)
    # Radläufe ausschneiden; die Schnittflächen übernehmen das dunkle Material des Schneidwerkzeugs.
    for ax in p["axles"]:
        bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=p["r"] * 1.2, depth=p["W"] * 2 + 0.4,
                                            location=(ax * p["L"] - p["L"] / 2, 0, p["r"] + 0.01),
                                            rotation=(math.pi / 2, 0, 0))
        cutter = bpy.context.active_object
        cutter.data.materials.append(mats["Trim"])
        boolean = body.modifiers.new("Radlauf", "BOOLEAN")
        boolean.operation = "DIFFERENCE"
        boolean.object = cutter
        boolean.material_mode = "TRANSFER"
        apply_modifiers(body)
        bpy.data.objects.remove(cutter, do_unlink=True)
    return body


def apply_modifiers(obj):
    bpy.context.view_layer.objects.active = obj
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def box(name, loc, size, mat, parent):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    o = bpy.context.active_object
    o.name = name
    o.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    bpy.ops.object.transform_apply(scale=True)
    bev = o.modifiers.new("Kante", "BEVEL")
    bev.width = min(size) * 0.25
    bev.segments = 2
    apply_modifiers(o)
    o.data.materials.append(mat)
    o.parent = parent
    return o


def build_details(shape, mats, body, style):
    p = shape.p
    L, W = p["L"], p["W"]
    xf = lambda u: u * L - L / 2
    for side in (-1, 1):
        u = 0.955
        bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=10, location=(xf(u), side * shape.half_width(u) * 0.62, shape.belt(u) - 0.045))
        light = bpy.context.active_object
        light.name = "HeadLight_%s" % ("L" if side > 0 else "R")
        light.scale = (0.05, 0.085, 0.03)
        bpy.ops.object.transform_apply(scale=True)
        light.data.materials.append(mats["HeadLight"])
        light.parent = body
        u = 0.018
        box("TailLight_%s" % ("L" if side > 0 else "R"), (xf(u), side * shape.half_width(0.05) * 0.58, shape.belt(0.05) - 0.05),
            (0.035, shape.half_width(0.05) * 0.62, 0.045), mats["TailLight"], body)
        u = 0.66
        box("Mirror_%s" % ("L" if side > 0 else "R"), (xf(u), side * (shape.half_width(u) * 0.93 + 0.012), shape.belt(u) + 0.005),
            (0.05, 0.05, 0.035), mats["Paint"], body)
    box("Grille", (xf(0.99), 0, shape.bottom(0.99) + 0.07), (0.03, W * 0.8, 0.06), mats["Trim"], body)
    box("Diffusor", (xf(0.01), 0, shape.bottom(0.01) + 0.03), (0.04, W * 1.1, 0.05), mats["Trim"], body)
    if style == "gt":
        for side in (-1, 1):
            box("WingStand", (xf(0.06), side * W * 0.45, shape.belt(0.06) + 0.06), (0.04, 0.02, 0.1), mats["Trim"], body)
        box("Wing", (xf(0.05), 0, shape.belt(0.05) + 0.12), (0.16, W * 1.75, 0.018), mats["Trim"], body)
    elif style == "coupe":
        box("Lip", (xf(0.03), 0, shape.belt(0.03) + 0.012), (0.08, W * 1.3, 0.015), mats["Paint"], body)
    elif style == "rally":
        for k, y in enumerate((-0.12, -0.04, 0.04, 0.12)):
            bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.035, depth=0.03, location=(xf(0.62), y, p["roof"] + 0.03), rotation=(0, math.pi / 2, 0))
            lamp = bpy.context.active_object
            lamp.name = "RoofLamp%d" % k
            lamp.data.materials.append(mats["HeadLight"])
            lamp.parent = body
        box("RoofRack", (xf(0.45), 0, p["roof"] + 0.015), (0.4, p["roofw"] * 1.6, 0.02), mats["Trim"], body)
    elif style == "muscle":
        box("Scoop", (xf(0.8), 0, shape.belt(0.8) + 0.04), (0.28, 0.2, 0.06), mats["Trim"], body)
    elif style == "hatch":
        box("RoofSpoiler", (xf(0.1), 0, p["roof"] - 0.01), (0.1, p["roofw"] * 1.7, 0.02), mats["Paint"], body)


def build_wheel(name, loc, r, tw, mats):
    bpy.ops.mesh.primitive_cylinder_add(vertices=36, radius=r, depth=tw, location=(0, 0, 0), rotation=(math.pi / 2, 0, 0))
    tire = bpy.context.active_object
    bev = tire.modifiers.new("Flanke", "BEVEL")
    bev.width = tw * 0.3
    bev.segments = 4
    apply_modifiers(tire)
    for poly in tire.data.polygons:
        poly.use_smooth = True
    tire.data.materials.append(mats["Rubber"])
    parts = [tire]
    bpy.ops.mesh.primitive_cylinder_add(vertices=36, radius=r * 0.64, depth=tw + 0.006, location=(0, 0, 0), rotation=(math.pi / 2, 0, 0))
    rim = bpy.context.active_object
    rim.data.materials.append(mats["Rim"])
    parts.append(rim)
    for k in range(5):
        a = k * 2 * math.pi / 5
        bpy.ops.mesh.primitive_cube_add(location=(math.cos(a) * r * 0.4, 0, math.sin(a) * r * 0.4), rotation=(0, -a, 0))
        spoke = bpy.context.active_object
        spoke.scale = (r * 0.3, tw * 0.5 + 0.006, r * 0.06)
        bpy.ops.object.transform_apply(scale=True)
        spoke.data.materials.append(mats["Trim"])
        parts.append(spoke)
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = tire
    bpy.ops.object.join()
    # Drehung der Grundkörper ins Netz übernehmen: Das Rad-Objekt selbst bleibt ungedreht, seine Achse ist y
    # (im Spiel z), damit das Spiel es sauber um die Achse drehen und einlenken kann.
    bpy.ops.object.select_all(action="DESELECT")
    tire.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    tire.name = name
    tire.location = loc
    return tire


def build_car(style, out_dir, preview):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    shape = Shape(STYLES[style])
    p = shape.p
    mats = make_materials()
    body = build_body(shape, mats)
    build_details(shape, mats, body, style)
    for ax, tag in ((p["axles"][0], "R"), (p["axles"][1], "F")):
        for side, s in ((1, "L"), (-1, "R")):
            build_wheel("Wheel_%s%s" % (tag, s), (ax * p["L"] - p["L"] / 2, side * (p["W"] - p["tw"] * 0.5 + 0.015), p["r"]), p["r"], p["tw"], mats)
    path = "%s/%s.glb" % (out_dir, style)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_yup=True)
    print("CAR", style, path)
    if preview:
        render_preview(style, out_dir, p)


def render_preview(style, out_dir, p):
    scene = bpy.context.scene
    world = bpy.data.worlds.new("Welt")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.62, 0.66, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    scene.world = world
    bpy.ops.mesh.primitive_plane_add(size=12, location=(0, 0, 0))
    ground = bpy.context.active_object
    ground.data.materials.append(material("Boden", (0.18, 0.2, 0.21), rough=0.6))
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(40), math.radians(10), math.radians(-35)))
    bpy.context.active_object.data.energy = 3.5
    for name, loc, rot in (("oben", (0, 0, 5.2), (0, 0, math.radians(-90))),
                           ("schraeg", (2.6, -2.6, 2.0), (math.radians(62), 0, math.radians(45)))):
        bpy.ops.object.camera_add(location=loc, rotation=rot)
        cam = bpy.context.active_object
        if name == "oben":
            cam.data.type = "ORTHO"
            cam.data.ortho_scale = p["L"] * 1.35
        scene.camera = cam
        scene.render.engine = "CYCLES"
        scene.cycles.samples = 48
        scene.cycles.use_denoising = True
        scene.render.resolution_x = 900
        scene.render.resolution_y = 600
        scene.render.filepath = "%s/%s_%s.png" % (out_dir, style, name)
        bpy.ops.render.render(write_still=True)
        print("PREVIEW", scene.render.filepath)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = args[0] if args else "."
    styles = args[1].split(",") if len(args) > 1 else ["coupe"]
    for s in styles:
        build_car(s, out, "--preview" in args)
