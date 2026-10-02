"""Themenmodul "mountain" (Serra Pass): Küstenpass mit Steilküste, Terrassenhängen, Pinien, Oliven und Trockenmauern.

Wird von tools/diorama.py in dessen Globals ausgeführt (siehe docs/dioramen/README.md; Beschreibung der Szene und Entscheidungen:
docs/dioramen/serra.md). Straße: "runtime" (das Spiel baut Fahrbahn, Randsteine und Linien mit dem Höhenprofil der Streckendatei selbst);
das Diorama liefert das **glatte Gelände**, das das Höhenraster der Strecke (track.terrain, 3 m) fein nachbildet: Rechnung in
tools/make_mountain_terrain.py (reines numpy, außerhalb von Blender prüfbar). Im Fahrschlauch (Abstand <= 4,3 m zur Mittellinie) liegt der
Boden exakt 0,08 m über der Fahrbahnbasis, davon geht es weich in Bankett, Böschung und Hang über; die Streckendatei bleibt die Spielebene
(Absturz bei mehr als 2,5 m Gefälle neben der Fahrbahn, Höhe der Laufzeit-Bausteine).

Gelände: ein Netz für Wiesen/Terrassenböden (Boden-Shader: Trockengras, Kalkschotter, Terra rossa), eines für Felswände (Schichtkalk, an
steilem Gelände), eines für die Stützmauern der Terrassen (Trockenmauer). Die Ränder zwischen den drei Netzen sind **glatt**: eine Steilheit je
Rasterpunkt entscheidet, Zellen mit Rand werden entlang der Linie geschnitten (make_mountain_terrain.Terrain.polys, m_poly_object), die Netze
teilen die Punkte am Rand; das Relief der Felswand verschwindet zum Rand hin (kein Riss). Meer mit Brandung am Kliff (Tiefe zum Bildrand hin
offenes Wasser: kein Sprung zum Wasserrahmen), Felsinsel mit dem Leuchtturm. Eine ebene Terrasse (tr.hut) trägt die Hirtenhütte mit Pferch
und Bienenstöcken.
Bewuchs und Gerät sind selbst gebaut (Pinien, Olivenhaine, Zypressen, Macchia, Agaven, Opuntien, Grasbüschel, Findlinge, Parapetmauern,
Bildstock, Hütte, Bienenstöcke, Boote, Warnschilder, Leitpfosten) und tragen
Hindernisse der Begleitdatei nur dort, wo sie nahe der Fahrbahn stehen. Gebacken sind die Bausteintypen Pinie, Olive, Agave und Fels der
Streckendatei (sie lägen zum Teil im Meer); Kapelle, Leuchtturm und Aussichtsplattform bleiben Laufzeit-Bauteile und bekommen die Bodenhöhe
des Dioramas (prop_y) und ihren Kontaktschatten (ao_proxies). Echte Lichtquellen der Nacht: die Leuchtturmlampe und die Kapellenlaterne.
Alle Namen dieses Moduls beginnen mit m_, weil das Modul in die Globals des Kerns ausgeführt wird.
"""
import math
import os
import random

import numpy as np
from mathutils import noise

import kit_car
import make_mountain_terrain as mt

M_TEX = "res://assets/dio/mountain/"
M_SRC = os.path.normpath(os.path.join(PROPS, "..", "dio", "mountain", "quelle"))
M_BAKED = ["ai:serra_pinie", "ai:serra_olivenbaum", "ai:serra_agave", "ai:serra_fels"]
THEME_CFG = {
    "road": "runtime",
    "ground_y": 0.08,
    "margin": 46.0,
    "baked": M_BAKED,
    "vertex_colors": "ACTIVE",
    "runtime_terrain": False,
    # Bodenmischung: Platz "grass" = ausgebrannter Mittelmeerrasen, "sand" = Kalkschotter (Bankett, Geröll, Kiesel am Wasser), "dirt" = Terra rossa
    "ground_set": {"grass": M_TEX + "boden_trockengras", "sand": M_TEX + "boden_kalk", "dirt": M_TEX + "boden_terrarossa"},
    "ground_scales": {"grass": 3.6, "sand": 3.0, "dirt": 3.2},
    "ground_tints": {"grass": [1.0, 0.94, 0.78], "sand": [1.0, 0.99, 0.96], "dirt": [1.0, 0.97, 0.94]},
    # Meer: türkis im Flachen, tiefes Blau, weiße Brandung am Kliff
    "water": {"lagoon": [0.10, 0.52, 0.55], "open": [0.015, 0.20, 0.36], "foam": [0.94, 0.97, 0.97]},
    "water_nodes": ["Meer"],
}

m_tr = None                 # Gelände (make_mountain_terrain.Terrain)
m_mats = {}
m_models = {}               # Schlüssel -> [(Teilname, Objekt)] (nicht in der Szene; m_put kopiert)
m_solids = []               # feste Teile (x, z, Radius) für Abstandsprüfungen
m_stats = {}


# ---------------------------------------------------------------- Materialien
def m_vcol(mat):
    """Materialzweig, der die Vertexfarbe "Color" liest (wie bei den anderen Themen): sorgt dafür, dass der glTF-Export sie als COLOR_0 ausgibt."""
    nt = mat.node_tree
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Color"
    nt.links.new(vc.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    return mat


def m_tex(name, image, normal=None, rough=0.9, vertex=True):
    """Material mit Bildtextur aus game/assets/dio/mountain/quelle, auf Wunsch mit Vertexfarbe multipliziert und mit Normalkarte."""
    if name in m_mats:
        return m_mats[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    uvn = nt.nodes.new("ShaderNodeUVMap")
    uvn.uv_map = "UVMap"
    tx = nt.nodes.new("ShaderNodeTexImage")
    tx.image = bpy.data.images.load(os.path.join(M_SRC, image), check_existing=True)
    nt.links.new(uvn.outputs["UV"], tx.inputs["Vector"])
    if vertex:
        vc = nt.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = "Color"
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        nt.links.new(tx.outputs["Color"], mix.inputs[6])
        nt.links.new(vc.outputs["Color"], mix.inputs[7])
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    else:
        nt.links.new(tx.outputs["Color"], bsdf.inputs["Base Color"])
    if normal:
        nn = nt.nodes.new("ShaderNodeTexImage")
        nn.image = bpy.data.images.load(os.path.join(M_SRC, normal), check_existing=True)
        nn.image.colorspace_settings.name = "Non-Color"
        nt.links.new(uvn.outputs["UV"], nn.inputs["Vector"])
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(nn.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    m_mats[name] = mat
    return mat


def theme_materials():
    M["gelaende"] = m_vcol(material("D_Gelaende", color=(0.5, 0.48, 0.42), rough=0.9))      # Platzhalter: Misch-Shader im Spiel
    # Wasser: Die Tiefe steckt in Rot der Vertexfarbe (Wasser-Shader). Das Laternen-Zusatzlicht des Spiels (lit_overlay) multipliziert diese Farbe mit dem
    # Materialton; mit weißem Ton leuchtete das Meer nachts rot um den Leuchtturm. Fast schwarzer Ton: der Zusatzdurchgang trägt dort nichts bei.
    M["wasser"].node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.01, 0.015, 0.02, 1.0)
    M["farbe"] = M["k:farbe"]
    M["m_fels"] = m_tex("D_Fels", "fels.jpg", "fels_n.jpg", 0.93)
    M["m_mauer"] = m_tex("D_Mauer", "mauer.jpg", "mauer_n.jpg", 0.92)
    M["m_rinde"] = m_tex("F_Rinde", "rinde.jpg", None, 0.95)
    M["m_kiefer"] = m_tex("F_Kiefer", "kiefer.jpg", None, 0.9)
    M["m_olive"] = m_tex("F_Olive", "olive.jpg", None, 0.85)
    M["m_busch"] = m_tex("F_Busch", "busch.jpg", None, 0.9)
    M["m_zypresse"] = m_tex("F_Zypresse", "zypresse.jpg", None, 0.9)
    M["m_agave"] = m_tex("F_Agave", "agave.jpg", None, 0.7)
    M["m_opuntie"] = m_tex("F_Opuntie", "opuntie.jpg", None, 0.7)


# ---------------------------------------------------------------- Netze aus dem Höhenraster
def m_poly_object(name, key, tr, A, quads, polys, kind, tile, cols):
    """Netz aus ganzen Zellen (quads: (i, j, Größe) des Feinrasters) und geschnittenen Vielecken (polys: Listen von Eigenschaftsvektoren, siehe
    make_mountain_terrain.Terrain.attrs). Gemeinsame Punkte (gleiche Lage) werden geteilt, damit die Normalen glatt sind und die Ränder zu den
    Nachbarnetzen auf denselben Punkten liegen. kind "ground": UV = Weltkoordinaten; sonst Würfelprojektion nach der Flächenrichtung (Wände).
    cols: Anfang der Farbwerte im Eigenschaftsvektor (5 Boden, 8 Fels)."""
    bm = bmesh.new()
    uv0 = bm.loops.layers.uv.new("UVMap")
    col = bm.loops.layers.float_color.new("Color")
    verts = {}
    pos = {}

    def vert(a):
        k = (int(round(float(a[0]) * 1000)), int(round(float(a[1]) * 1000)))
        if k not in verts:
            p = tr.final_pos(a)
            pos[k] = p
            verts[k] = bm.verts.new((p[0], -p[2], p[1]))
        return k

    def add(arr):
        ks, at = [], []
        for a in arr:
            k = vert(a)
            if ks and k == ks[-1]:
                continue
            ks.append(k)
            at.append(a)
        while len(ks) > 1 and ks[0] == ks[-1]:
            ks.pop()
            at.pop()
        if len(set(ks)) < 3:
            return
        for t in range(1, len(ks) - 1):
            idx = (0, t, t + 1)
            try:
                f = bm.faces.new([verts[ks[i]] for i in idx])
            except ValueError:
                continue
            f.smooth = True
            p3 = [pos[ks[i]] for i in idx]
            if kind != "ground":
                nx = (p3[1][1] - p3[0][1]) * (p3[2][2] - p3[0][2]) - (p3[1][2] - p3[0][2]) * (p3[2][1] - p3[0][1])
                nz_ = (p3[1][2] - p3[0][2]) * (p3[2][0] - p3[0][0]) - (p3[1][0] - p3[0][0]) * (p3[2][2] - p3[0][2])
                hor = abs(nx) >= abs(nz_)
            for loop, i, q in zip(f.loops, idx, p3):
                if kind == "ground":
                    loop[uv0].uv = (q[0] / tile, -q[2] / tile)
                else:
                    loop[uv0].uv = ((q[2] if hor else q[0]) / tile, q[1] / tile)
                c = at[i][cols:cols + 3]
                loop[col] = (float(c[0]), float(c[1]), float(c[2]), 1.0)
    for i, j, sz in quads:
        add([A[j, i], A[j + sz, i], A[j + sz, i + sz], A[j, i + sz]])
    for poly in polys:
        add(poly)
    if not bm.faces:
        bm.free()
        return None
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(M[key])
    obj = bpy.data.objects.new(name, me)
    scene.collection.objects.link(obj)
    activate_vertex_colors(me)
    return obj


def m_build_sea(tr):
    """Meer: Netz über die ganze Fläche (2 m), Tiefe in der Vertexfarbe (Rot: 0 = Ufer, 1 = offen) aus dem Abstand zum Land; Brandung und
    Schaumsaum macht der Wasser-Shader. Dahinter ein weiter Rahmen gleicher Tiefe bis zum Horizont."""
    gx = np.arange(x0, x1 + 1e-6, 2.0)
    gz = np.arange(z0, z1 + 1e-6, 2.0)
    X, Z = np.meshgrid(gx, gz)
    dist = tr.at(tr.land_dist, X, Z)
    hgt = tr.at(tr.H, X, Z)
    depth = np.clip(dist / 9.0, 0.0, 1.0)
    edge = np.minimum.reduce([X - gx[0], gx[-1] - X, Z - gz[0], gz[-1] - Z])
    depth = depth + (1.0 - depth) * mt.smooth(1.0 - edge / 14.0)          # zum Rand hin offenes Wasser: Anschluss an den Rahmen ohne Kante
    COL = np.stack([depth, np.zeros_like(depth), np.zeros_like(depth)], -1)
    skip = np.zeros((len(gz) - 1, len(gx) - 1), bool)
    lo = np.minimum.reduce([hgt[:-1, :-1], hgt[:-1, 1:], hgt[1:, :-1], hgt[1:, 1:]])
    skip |= lo > mt.WATER_Y + 0.6                       # Zellen ganz an Land: kein Wasser nötig
    quads = mt.quadtree(np.zeros_like(depth), COL, skip, 0.01, 0.03, 8)
    bm = bmesh.new()
    uv0 = bm.loops.layers.uv.new("UVMap")
    col = bm.loops.layers.float_color.new("Color")
    verts = {}

    def vert(i, j):
        k = (i, j)
        if k not in verts:
            verts[k] = bm.verts.new((float(gx[i]), -float(gz[j]), mt.WATER_Y))
        return verts[k]
    for i, j, sz in quads:
        corners = ((i, j), (i, j + sz), (i + sz, j + sz), (i + sz, j))
        f = bm.faces.new([vert(a, b) for a, b in corners])
        for loop, (a, b) in zip(f.loops, corners):
            loop[uv0].uv = (float(gx[a]) / 8.0, -float(gz[b]) / 8.0)
            c = COL[b, a]
            loop[col] = (float(c[0]), 0.0, 0.0, 1.0)
    bm.normal_update()
    me = bpy.data.meshes.new("Meer")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(M["wasser"])
    obj = bpy.data.objects.new("Meer", me)
    scene.collection.objects.link(obj)
    activate_vertex_colors(me)
    # Rahmen bis weit hinter den Bildrand (gleiche Tiefe wie der Rand)
    far = 400.0
    parts = []
    xa, xb, za, zb = float(gx[0]), float(gx[-1]), float(gz[0]), float(gz[-1])
    for (ax, bx, az, bz) in ((xa - far, xb + far, za - far, za), (xa - far, xb + far, zb, zb + far), (xa - far, xa, za, zb), (xb, xb + far, za, zb)):
        quad = [(ax, bz, mt.WATER_Y), (bx, bz, mt.WATER_Y), (bx, az, mt.WATER_Y), (ax, az, mt.WATER_Y)]
        parts.append(("wasser", quad, [(q[0] / 8.0, -q[1] / 8.0) for q in quad], None, [(1.0, 0.0, 0.0)] * 4))
    mesh_object("Meer_Weite", parts)
    return obj


def m_check_ground():
    """Ersatz für die Prüfung des Kerns (check_runtime_ground), die ein ebenes Gelände unter 0,16 m voraussetzt: Der Boden nahe der Mittellinie
    muss unter der Fahrbahn des Höhenprofils liegen (Basis + ROAD_Y)."""
    bad = 0
    for o in objs_ground:
        me = o.data
        n = len(me.vertices)
        if not n:
            continue
        co = np.empty(n * 3, np.float32)
        me.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3)
        P = np.stack([co[:, 0], -co[:, 1]], 1)
        near = dist_to_center(P) < HW + 0.3
        if not near.any():
            continue
        _, _, bn, _ = m_tr.nearest(P[near, 0], P[near, 1])
        n_bad = int((co[near, 2] > bn + ROAD_Y - 0.01).sum())
        if n_bad:
            print("DIORAMA Boden überdeckt die Laufzeit-Fahrbahn:", o.name, n_bad, "Punkte")
        bad += n_bad
    if bad:
        raise ValueError("Boden des Themas überdeckt die Laufzeit-Fahrbahn (%d Netzpunkte)" % bad)
    print("DIORAMA Fahrschlauch geprüft: Boden liegt überall unter der Fahrbahn")


def theme_ground():
    global m_tr
    globals()["check_runtime_ground"] = m_check_ground          # Prüfung des Kerns kennt kein Höhenprofil
    tr = mt.Terrain(data, x0, x1, z0, z1, 1.0).build().classify()
    tr.dist_to_land()
    tr.relief_raw()
    tr.dist_to_cliff()
    m_tr = tr
    A = tr.attrs()
    P = tr.polys(A)
    q = mt.quadtree(tr.H, A[..., 5:8], P["ground_skip"], 0.05, 0.08, 8)
    for name, key, quads, polys, kind, tile, cols in (("Boden_gelaende", "gelaende", q, P["ground"], "ground", 4.0, 5),
                                                      ("Boden_fels", "m_fels", P["cliff_q"], P["cliff"], "rock", 12.0, 8),
                                                      ("Boden_mauer", "m_mauer", P["wall_q"], P["wall"], "rock", 3.3, 8)):
        obj = m_poly_object(name, key, tr, A, quads, polys, kind, tile, cols)
        if obj is not None:
            objs_ground.append(obj)
    m_build_sea(tr)
    m_stats.update(ground=len(q), rock=len(P["cliff_q"]) + len(P["cliff"]), wall=len(P["wall_q"]) + len(P["wall"]))
    print("DIORAMA Gelände: Boden %d Blöcke + %d Randdreiecke, Fels %d + %d, Terrassenmauern %d + %d | Meer, Land %.0f %%" % (
        len(q), len(P["ground"]), len(P["cliff_q"]), len(P["cliff"]), len(P["wall_q"]), len(P["wall"]), 100.0 * float((tr.H > mt.WATER_Y).mean())))


# ---------------------------------------------------------------- Bausteine: Netze und Modelle
def m_bm():
    bm = bmesh.new()
    return bm, bm.loops.layers.uv.new("UVMap"), bm.loops.layers.float_color.new("Color")


def m_finish(name, bm, mat_key):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(M[mat_key])
    obj = bpy.data.objects.new(name, me)
    activate_vertex_colors(me)
    return obj


def m_tube(bm, uv, col, pts, radii, sides, color, uv_len=1.0, cap=True):
    """Verjüngte Röhre entlang einer Punktfolge (Blender-Koordinaten); UV: Winkel x Länge, Farbe leicht verlaufend."""
    rings, lens = [], [0.0]
    for i in range(1, len(pts)):
        lens.append(lens[-1] + (Vector(pts[i]) - Vector(pts[i - 1])).length)
    for i, p in enumerate(pts):
        p = Vector(p)
        t = (Vector(pts[min(i + 1, len(pts) - 1)]) - Vector(pts[max(i - 1, 0)])).normalized()
        a = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
        u = t.cross(a).normalized()
        v = t.cross(u).normalized()
        rings.append([bm.verts.new(p + (u * math.cos(2 * math.pi * k / sides) + v * math.sin(2 * math.pi * k / sides)) * radii[i]) for k in range(sides)])
    faces = []
    for i in range(len(rings) - 1):
        for k in range(sides):
            quad = [(i, k), (i, (k + 1) % sides), (i + 1, (k + 1) % sides), (i + 1, k)]
            f = bm.faces.new([rings[a][b] for a, b in quad])
            f.smooth = True
            faces.append(f)
            for loop, (a, b), un in zip(f.loops, quad, (k, k + 1, k + 1, k)):
                loop[uv].uv = (un / sides, lens[a] / uv_len)
                sh = 0.78 + 0.22 * (a / max(1, len(pts) - 1))
                loop[col] = (color[0] * sh, color[1] * sh, color[2] * sh, 1.0)
    if cap:
        f = bm.faces.new(rings[-1])
        for loop in f.loops:
            loop[uv].uv = (0.5, 0.5)
            loop[col] = (color[0], color[1], color[2], 1.0)
    bm.normal_update()
    return rings


def m_blob_crown(blobs, subdiv, rng_, bump=0.25, tint=(1.0, 1.0, 1.0), tile=2.2, shade_lo=0.5):
    """Krone aus verformten Kugeln: innen liegende Flächen entfallen, Würfelprojektion als UV, Vertexfarbe = Höhenschatten.
    blobs: Liste (Mitte Vector, Radius, (sx, sy, sz)). Rückgabe: (bmesh, uv-Ebene, Farbebene) in Blender-Koordinaten."""
    bm = bmesh.new()
    own = bm.verts.layers.int.new("own")
    for bi, (c, r, sc3) in enumerate(blobs):
        mat = Matrix.Translation(c) @ Matrix.Diagonal((sc3[0], sc3[1], sc3[2], 1.0))
        res = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=r, matrix=mat, calc_uvs=False)
        for v in res["verts"]:
            v[own] = bi
    bm.verts.ensure_lookup_table()
    for v in bm.verts:
        c, r, sc3 = blobs[v[own]]
        d = v.co - c
        n = Vector((d.x / (sc3[0] ** 2), d.y / (sc3[1] ** 2), d.z / (sc3[2] ** 2))).normalized()
        b = noise.noise(v.co * 1.7 + Vector((3.1, 1.3, 7.7))) * bump * r + noise.noise(v.co * 4.6) * bump * 0.45 * r
        v.co += n * b

    def inside_other(v):
        for j, (c, r, sc3) in enumerate(blobs):
            if j == v[own]:
                continue
            d = v.co - c
            if (d.x / sc3[0]) ** 2 + (d.y / sc3[1]) ** 2 + (d.z / sc3[2]) ** 2 < (r * 0.88) ** 2:
                return True
        return False
    inner = {v.index for v in bm.verts if inside_other(v)}
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if all(v.index in inner for v in f.verts)], context="FACES")
    for f in list(bm.faces):
        f.smooth = True
    bm.normal_update()
    uv = bm.loops.layers.uv.new("UVMap")
    col = bm.loops.layers.float_color.new("Color")
    zmin = min(v.co.z for v in bm.verts)
    zmax = max(v.co.z for v in bm.verts)
    shade = {i: rng_.uniform(0.9, 1.08) for i in range(len(blobs))}
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda k: abs(n[k]))
        for loop in f.loops:
            p = loop.vert.co
            u, w = ((p.y, p.z), (p.x, p.z), (p.x, p.y))[ax]
            loop[uv].uv = (u / tile, w / tile)
            t = (p.z - zmin) / max(zmax - zmin, 1e-6)
            sh = (shade_lo + (1.0 - shade_lo) * t ** 0.85) * shade.get(loop.vert[own], 1.0)
            loop[col] = (min(1.0, sh * tint[0]), min(1.0, sh * tint[1]), min(1.0, sh * tint[2]), 1.0)
    return bm


def m_register(key, parts):
    """Modell (Liste (Teilname, Objekt)) für m_put eintragen; die Objekte liegen nicht in der Szene."""
    m_models[key] = parts
    return key


def m_put(key, x, z, yaw, scale, y, tilt=0.0):
    """Modell an (x, z) auf Höhe y setzen (Fuß im Ursprung des Modells), gedreht um yaw, gleichmäßig skaliert. Gleiche Netze heißen Prop_*
    (das Spiel fasst sie zu MultiMeshes zusammen). Kein Hindernis."""
    for suffix, base in m_models[key]:
        inst = base.copy()
        inst.name = "Prop_%s_%s" % (key, suffix)
        scene.collection.objects.link(inst)
        inst.matrix_world = (Matrix.Translation((x, -z, y)) @ Matrix.Rotation(-yaw, 4, "Z") @ Matrix.Rotation(tilt, 4, "X") @ Matrix.Scale(scale, 4))


def m_height(x, z):
    return float(m_tr.height(x, z))


def m_solid(x, z, r, height, kind="baum"):
    """Hindernis in die Begleitdatei (nur nahe der Fahrbahn nötig) und Eintrag für Abstandsprüfungen."""
    collide_circle(x, z, r, height, kind)
    m_solids.append((x, z, r))


# ---------------------------------------------------------------- Pflanzen und Steine
def m_pine(seed):
    """Pinie: gebogener Stamm, weit ausladende Schirmkrone aus flachen Blasen. Höhe etwa 7,5 m."""
    key = "pinie%d" % seed
    if key in m_models:
        return key
    r = random.Random(seed * 31 + 7)
    h = r.uniform(5.3, 6.4)
    lean = r.uniform(-0.8, 0.8)
    bm, uv, col = m_bm()
    pts = [(lean * t * t * 1.4, 0.35 * math.sin(t * 3.0 + seed), h * t) for t in (0.0, 0.25, 0.5, 0.75, 1.0)]
    m_tube(bm, uv, col, pts, [0.36, 0.28, 0.22, 0.17, 0.12], 6, (0.62, 0.50, 0.40), 1.3)
    for k in range(3):                                   # Hauptäste
        a = r.uniform(0, 6.28) + k * 2.1
        top = Vector(pts[-1])
        m_tube(bm, uv, col, [(top.x, top.y, top.z - 0.8), (top.x + math.cos(a) * 1.0, top.y + math.sin(a) * 1.0, top.z - 0.1),
                             (top.x + math.cos(a) * 2.0, top.y + math.sin(a) * 2.0, top.z + 0.5)], [0.12, 0.09, 0.06], 5, (0.62, 0.50, 0.40), 1.3)
    trunk = m_finish("stamm", bm, "m_rinde")
    top = Vector(pts[-1])
    blobs = [(Vector((top.x, top.y, top.z + 0.9)), 2.0, (1.0, 1.0, 0.46))]
    for k in range(5):
        a = k * 1.256 + r.uniform(-0.3, 0.3)
        dd = r.uniform(1.7, 2.3)
        blobs.append((Vector((top.x + math.cos(a) * dd, top.y + math.sin(a) * dd, top.z + r.uniform(0.2, 0.8))), r.uniform(1.25, 1.65), (1.0, 1.0, 0.5)))
    cb = m_blob_crown(blobs, 2, r, 0.30, (1.0, 0.98, 0.9), 2.4, 0.55)
    crown = m_finish("krone", cb, "m_kiefer")
    return m_register(key, [("stamm", trunk), ("krone", crown)])


def m_olive(seed):
    """Olivenbaum: kurzer, geteilter, knorriger Stamm, breite niedrige Krone in Silbergrün. Höhe etwa 4 m."""
    key = "olive%d" % seed
    if key in m_models:
        return key
    r = random.Random(seed * 17 + 3)
    bm, uv, col = m_bm()
    stems = r.choice([2, 3])
    tops = []
    for k in range(stems):
        a = k * 6.28 / stems + r.uniform(-0.4, 0.4)
        sp = r.uniform(0.25, 0.5)
        pts = [(0, 0, 0), (math.cos(a) * sp * 0.4, math.sin(a) * sp * 0.4, 0.55), (math.cos(a + 0.5) * sp, math.sin(a + 0.5) * sp, 1.2),
               (math.cos(a + 0.2) * sp * 1.7, math.sin(a + 0.2) * sp * 1.7, 1.9)]
        m_tube(bm, uv, col, pts, [0.30, 0.24, 0.17, 0.11], 6, (0.55, 0.50, 0.45), 1.0)
        tops.append(Vector(pts[-1]))
    trunk = m_finish("stamm", bm, "m_rinde")
    blobs = [(Vector((0, 0, 2.7)), 1.35, (1.0, 1.0, 0.8))]
    for t in tops:
        blobs.append((Vector((t.x * 1.4, t.y * 1.4, 2.4 + r.uniform(0.0, 0.5))), r.uniform(1.05, 1.35), (1.0, 1.0, 0.78)))
    for k in range(2):
        a = r.uniform(0, 6.28)
        blobs.append((Vector((math.cos(a) * 1.1, math.sin(a) * 1.1, 3.0 + r.uniform(0, 0.4))), r.uniform(0.8, 1.05), (1.0, 1.0, 0.8)))
    cb = m_blob_crown(blobs, 2, r, 0.34, (1.0, 1.02, 0.95), 2.0, 0.62)
    crown = m_finish("krone", cb, "m_olive")
    return m_register(key, [("stamm", trunk), ("krone", crown)])


def m_cypress(seed):
    """Zypresse: schlank, dunkel, 7 bis 9 m."""
    key = "zypresse%d" % seed
    if key in m_models:
        return key
    r = random.Random(seed * 23 + 11)
    blobs = [(Vector((0, 0, 1.3)), 0.8, (1.0, 1.0, 1.5)), (Vector((0.04, 0, 3.4)), 0.72, (0.85, 0.85, 3.0)), (Vector((0.0, 0.05, 5.6)), 0.55, (0.8, 0.8, 2.4)),
             (Vector((0.0, 0.0, 7.2)), 0.35, (0.8, 0.8, 1.8))]
    cb = m_blob_crown(blobs, 1, r, 0.2, (1.0, 1.0, 1.0), 1.6, 0.6)
    return m_register(key, [("krone", m_finish("krone", cb, "m_zypresse"))])


def m_bush(seed):
    """Macchia-Busch: ein bis zwei verformte Kugeln, halbhoch. Fuß im Ursprung."""
    key = "busch%d" % seed
    if key in m_models:
        return key
    r = random.Random(seed * 13 + 5)
    n = r.choice([1, 2])
    blobs = [(Vector((0, 0, 0.42)), 0.78, (1.0, 1.0, 0.62))]
    if n == 2:
        a = r.uniform(0, 6.28)
        blobs.append((Vector((math.cos(a) * 0.55, math.sin(a) * 0.55, 0.36)), 0.55, (1.0, 1.0, 0.65)))
    tints = [(1.0, 1.0, 0.95), (1.05, 0.95, 0.75), (0.85, 0.95, 0.9), (1.0, 0.82, 0.62)]
    cb = m_blob_crown(blobs, 2, r, 0.32, tints[seed % len(tints)], 1.4, 0.55)
    return m_register(key, [("krone", m_finish("krone", cb, "m_busch"))])


def m_agave(seed):
    """Agave: Rosette aus fleischigen, spitzen Blättern; manche mit Blütenstand."""
    key = "agave%d" % seed
    if key in m_models:
        return key
    r = random.Random(seed * 29 + 1)
    bm, uv, col = m_bm()
    nl = 15
    for k in range(nl):
        a = k * 2.399963
        tilt = 0.25 + 1.0 * (k / nl) ** 0.8              # innen aufrecht, außen flach
        ln = r.uniform(0.85, 1.25) * (1.0 - 0.12 * (k / nl))
        w = 0.17
        dx, dy = math.cos(a), math.sin(a)
        up = math.cos(tilt)
        out = math.sin(tilt)

        def pt(f, side, lift=0.0):
            px, py = -dy, dx
            return (dx * out * ln * f + px * side * w * (1.0 - f * 0.7), dy * out * ln * f + py * side * w * (1.0 - f * 0.7), 0.12 + up * ln * f + lift * f * f)
        f1 = 0.45
        b0, b1 = pt(0.0, -0.4), pt(0.0, 0.4)
        m0, m1 = pt(f1, -1.0, -0.08 * ln), pt(f1, 1.0, -0.08 * ln)
        tip = pt(1.0, 0.0, -0.25 * ln)
        tone = r.uniform(0.85, 1.1)
        for tri, us in (([b0, b1, m1, m0], ((0, 0), (1, 0), (1, 0.5), (0, 0.5))), ([m0, m1, tip], ((0, 0.5), (1, 0.5), (0.5, 1)))):
            f = bm.faces.new([bm.verts.new(p) for p in tri])
            for loop, u in zip(f.loops, us):
                loop[uv].uv = u
                s = tone * (0.75 + 0.25 * loop.vert.co.z / 1.2)
                loop[col] = (min(1, s), min(1, s), min(1, s), 1.0)
    bm.normal_update()
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    parts = [("rosette", m_finish("rosette", bm, "m_agave"))]
    if seed % 2 == 0:                                    # Blütenstand
        bm2, uv2, col2 = m_bm()
        m_tube(bm2, uv2, col2, [(0, 0, 0.2), (0.05, 0.03, 1.4), (0.1, 0.0, 2.6), (0.12, 0.02, 3.6)], [0.07, 0.055, 0.04, 0.03], 5, (0.66, 0.60, 0.40), 1.0)
        parts.append(("schaft", m_finish("schaft", bm2, "m_rinde")))
    return m_register(key, parts)


def m_opuntia(seed):
    """Feigenkaktus: wenige übereinander gewachsene flache Glieder."""
    key = "opuntie%d" % seed
    if key in m_models:
        return key
    r = random.Random(seed * 41 + 9)
    bm, uv, col = m_bm()
    base = Vector((0, 0, 0.3))
    ang = 0.0
    for k in range(r.randint(3, 5)):
        sx, sy = r.uniform(0.38, 0.52), r.uniform(0.5, 0.7)
        mat = Matrix.Translation(base) @ Matrix.Rotation(ang, 4, "Y") @ Matrix.Rotation(r.uniform(0, 3.1), 4, "Z") @ Matrix.Diagonal((sx, 0.12, sy, 1.0))
        res = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0, matrix=mat, calc_uvs=False)
        base = base + Vector((r.uniform(-0.35, 0.35), r.uniform(-0.35, 0.35), sy * 0.8))
        ang = r.uniform(-0.6, 0.6)
    for f in bm.faces:
        f.smooth = True
    uv_l = bm.loops.layers.uv.new("UVMap")
    col_l = bm.loops.layers.float_color.new("Color")
    for f in bm.faces:
        for loop in f.loops:
            p = loop.vert.co
            loop[uv_l].uv = (p.x * 0.8 + 0.5, p.y * 0.8 + p.z * 0.4)
            s = 0.75 + 0.25 * min(1.0, p.z / 1.8)
            loop[col_l] = (s, s, s, 1.0)
    return m_register(key, [("glieder", m_finish("glieder", bm, "m_opuntie"))])


def m_tuft(seed):
    """Grasbüschel: sieben bis zehn schräg abstehende Halme (dreiseitige Nadeln), Fuß olivgrün, Spitze strohgelb. Höhe etwa 0,5 m."""
    key = "tuft%d" % seed
    if key in m_models:
        return key
    r = random.Random(seed * 19 + 4)
    bm, uv, col = m_bm()
    base_c = (0.42, 0.42, 0.18)
    tip_c = [(0.86, 0.76, 0.42), (0.78, 0.70, 0.36), (0.90, 0.82, 0.52), (0.74, 0.66, 0.30)][seed % 4]
    for k in range(r.randint(7, 10)):
        a = r.uniform(0, 6.28)
        lean = r.uniform(0.12, 0.75)
        ln = r.uniform(0.34, 0.66)
        bx, by = r.uniform(-0.09, 0.09), r.uniform(-0.09, 0.09)
        w = 0.032
        base = [bm.verts.new((bx + w * math.cos(t), by + w * math.sin(t), 0.0)) for t in (0.0, 2.094, 4.189)]
        tip = bm.verts.new((bx + math.cos(a) * lean * ln, by + math.sin(a) * lean * ln, ln * math.cos(lean * 0.7)))
        tone = r.uniform(0.85, 1.12)
        for q in range(3):
            f = bm.faces.new([base[q], base[(q + 1) % 3], tip])
            f.smooth = False
            for loop in f.loops:
                c = base_c if loop.vert in base else tuple(min(1.0, v * tone) for v in tip_c)
                c = tuple(v ** 2.2 for v in c)
                loop[col] = (c[0], c[1], c[2], 1.0)
                loop[uv].uv = (0.5, 0.5)
    bm.normal_update()
    return m_register(key, [("halme", m_finish("halme", bm, "farbe"))])


def m_boulder(seed):
    """Kantiger Felsblock mit Schichtkalk-Textur; Fuß im Ursprung, Größe etwa 1 m."""
    key = "block%d" % seed
    if key in m_models:
        return key
    r = random.Random(seed * 37 + 5)
    bm = bmesh.new()
    sc3 = (1.0, r.uniform(0.72, 1.0), r.uniform(0.55, 0.85))
    res = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.5, matrix=Matrix.Diagonal((sc3[0], sc3[1], sc3[2], 1.0)), calc_uvs=False)
    off = Vector((seed * 3.1, 1.7, 5.3))
    for v in res["verts"]:
        n = v.co.normalized()
        v.co += n * (noise.noise(v.co * 2.0 + off) * 0.28 + noise.noise(v.co * 5.5 + off) * 0.06)
    zmin = min(v.co.z for v in bm.verts)
    for v in bm.verts:
        v.co.z = max(v.co.z, zmin + 0.10) - zmin - 0.04
    for f in bm.faces:
        f.smooth = False
    bm.normal_update()
    uv = bm.loops.layers.uv.new("UVMap")
    col = bm.loops.layers.float_color.new("Color")
    zmax = max(v.co.z for v in bm.verts)
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda k: abs(n[k]))
        tone = r.uniform(0.86, 1.08)
        for loop in f.loops:
            p = loop.vert.co
            u, w = ((p.y, p.z), (p.x, p.z), (p.x, p.y))[ax]
            loop[uv].uv = (u / 1.6 + seed * 0.37, w / 1.6)
            sh = (0.60 + 0.40 * min(1.0, max(0.0, p.z) / max(zmax, 1e-3))) * tone
            loop[col] = (sh, sh * 0.99, sh * 0.96, 1.0)
    return m_register(key, [("fels", m_finish("fels", bm, "m_fels"))])


# ---------------------------------------------------------------- Mauern
def m_wall(name, pts, height, thick, tone=1.0):
    """Trockenmauer entlang einer Punktfolge (Spielkoordinaten x, z; Mitte der Mauer): zwei Seiten und Krone auf dem Gelände (Fuß 0,25 m
    eingegraben). Rückgabe: Objekt (nicht in objs_ground: keine Lichttextur)."""
    pts = [np.array(p, float) for p in pts]
    fine = [pts[0]]
    for a, b in zip(pts, pts[1:]):
        n = max(1, int(np.linalg.norm(b - a) / 0.7))
        for k in range(1, n + 1):
            fine.append(a + (b - a) * (k / n))
    rows = []
    run = 0.0
    rng_ = random.Random(len(fine) + int(height * 10))
    for i, p in enumerate(fine):
        a = fine[max(i - 1, 0)]
        b = fine[min(i + 1, len(fine) - 1)]
        t = (b - a) / (np.linalg.norm(b - a) + 1e-9)
        nrm = np.array([-t[1], t[0]])
        if i > 0:
            run += float(np.linalg.norm(p - fine[i - 1]))
        pl, pr = p + nrm * thick / 2, p - nrm * thick / 2
        gl, gr = m_height(pl[0], pl[1]), m_height(pr[0], pr[1])
        top = max(gl, gr) + height + rng_.uniform(-0.05, 0.06)
        rows.append((pl, pr, gl - 0.25, gr - 0.25, top, run, rng_.uniform(0.86, 1.08) * tone, nrm))
    parts = []
    for r0, r1 in zip(rows, rows[1:]):
        pl0, pr0, bl0, br0, t0, u0, s0, n0 = r0
        pl1, pr1, bl1, br1, t1, u1, s1, n1 = r1
        sh = min(1.0, (s0 + s1) * 0.5)
        cols = [(sh, sh * 0.99, sh * 0.97)] * 4
        parts.append(("m_mauer", [(pl0[0], pl0[1], bl0), (pl1[0], pl1[1], bl1), (pl1[0], pl1[1], t1), (pl0[0], pl0[1], t0)],
                      [(u0 / 3.3, bl0 / 3.3), (u1 / 3.3, bl1 / 3.3), (u1 / 3.3, t1 / 3.3), (u0 / 3.3, t0 / 3.3)], (n0[0], n0[1]), cols))
        parts.append(("m_mauer", [(pr1[0], pr1[1], br1), (pr0[0], pr0[1], br0), (pr0[0], pr0[1], t0), (pr1[0], pr1[1], t1)],
                      [(u1 / 3.3, br1 / 3.3), (u0 / 3.3, br0 / 3.3), (u0 / 3.3, t0 / 3.3), (u1 / 3.3, t1 / 3.3)], (-n0[0], -n0[1]), cols))
        parts.append(("m_mauer", [(pl0[0], pl0[1], t0), (pl1[0], pl1[1], t1), (pr1[0], pr1[1], t1), (pr0[0], pr0[1], t0)],
                      [(u0 / 3.3, 0.0), (u1 / 3.3, 0.0), (u1 / 3.3, thick / 3.3), (u0 / 3.3, thick / 3.3)], None, [(min(1.0, sh * 1.1),) * 3] * 4))
    return mesh_object(name, parts)


# ---------------------------------------------------------------- Planung der Aufstellung
def m_fields(x, z):
    """Gelände-Felder an Orten: Abstand zur Fahrbahn, Höhe, Neigung, Terrassenmaske, Abstand zur Felswand, Abstand zum Land."""
    tr = m_tr
    return dict(gr=tr.grove(x, z), d=tr.at(tr.d, x, z), h=tr.at(tr.H, x, z), sl=tr.at(tr.slope, x, z), T=tr.at(tr.T, x, z), cd=tr.at(tr.cliff_dist, x, z), rd=tr.at(tr.rock_dist, x, z), ld=tr.at(tr.land_dist, x, z))


def m_free(x, z, r):
    for sx, sz, sr in m_solids:
        if (x - sx) ** 2 + (z - sz) ** 2 < (r + sr) ** 2:
            return False
    return True


def m_special_free(x, z, pad=0.0):
    """Nicht auf den Besonderheiten: Kapellenplatz, Leuchtturm-Insel, Aussichtsplattform, Start- und Zielschotterplatz."""
    cx, cz = mt.PLAZA
    if math.hypot(x - cx, z - cz) < mt.PLAZA_R + 1.0 + pad:
        return False
    if m_tr.hut is not None and math.hypot(x - m_tr.hut[0], z - m_tr.hut[1]) < 9.0 + pad:
        return False
    for key in ("lighthouse", "lookout"):
        hx, hz = mt.HILL[key]
        if math.hypot(x - hx, z - hz) < 7.0 + pad:
            return False
    for end, (ax, az, tx, tz, by, length) in m_tr.ends().items():
        along = (x - ax) * tx + (z - az) * tz
        across = abs(-(x - ax) * tz + (z - az) * tx)
        if across < 9.0 + pad and ((end == "start" and -length - 3.0 < along < 3.0) or (end == "finish" and -3.0 < along < length + 3.0)):
            return False
    return True


def m_plan():
    """Orte der Pflanzen und Steine. Rückgabe: dict Art -> Liste (x, z, Drehung, Skalierung, Variante)."""
    tr = m_tr
    rng_ = np.random.default_rng(31)
    plan = {"olive": [], "pine": [], "cypress": [], "bush": [], "agave": [], "opuntia": [], "boulder": [], "tuft": []}
    ex0, ex1, ez0, ez1 = x0 + 6, x1 - 6, z0 + 6, z1 - 6

    def cand(n):
        return rng_.uniform(ex0, ex1, n), rng_.uniform(ez0, ez1, n)
    # --- Olivenhaine: Raster mit 6,6 m auf den Terrassenböden der Hainzonen
    ang = 0.35
    ca, sa = math.cos(ang), math.sin(ang)
    spots = []
    for a in np.arange(-150.0, 150.0, 6.6):
        for b in np.arange(-150.0, 150.0, 6.6):
            x = (ca * a - sa * b) + (rng_.random() - 0.5) * 1.4 - 28.0
            z = (sa * a + ca * b) + (rng_.random() - 0.5) * 1.4 - 40.0
            if ex0 < x < ex1 and ez0 < z < ez1:
                spots.append((x, z))
    P = np.array(spots)
    f = m_fields(P[:, 0], P[:, 1])
    gr = tr.grove(P[:, 0], P[:, 1])
    ok = (f["d"] > 10.5) & (f["h"] > 3.0) & (f["sl"] < 0.42) & (f["cd"] > 3.0) & (f["rd"] > 1.4) & (gr > 0.4)
    # Nachbarschaft ebenfalls flach (Baum steht nicht an einer Mauer)
    for dx, dz in ((1.8, 0), (-1.8, 0), (0, 1.8), (0, -1.8)):
        ok &= tr.at(tr.slope, P[:, 0] + dx, P[:, 1] + dz) < 0.5
    idx = np.nonzero(ok)[0]
    idx = idx[np.argsort(f["d"][idx])][:46]
    for i in idx:
        x, z = float(P[i, 0]), float(P[i, 1])
        if m_special_free(x, z):
            plan["olive"].append((x, z, rng_.uniform(0, 6.28), rng_.uniform(0.9, 1.25), int(rng_.integers(3))))
            m_solids.append((x, z, 1.6))
    # --- Pinien: Gruppen auf Hängen und Kanten
    X, Z = cand(30000)
    f = m_fields(X, Z)
    cluster = tr.noise.fbm(X, Z, 34.0, 2, 13.0)
    ok = (f["d"] > 9.0) & (f["h"] > 6.0) & (f["sl"] < 0.5) & (f["rd"] > 1.8) & (cluster > 0.47) & (f["T"] < 0.6) & (f["gr"] < 0.6)
    got = 0
    for i in np.nonzero(ok)[0][rng_.permutation(int(ok.sum()))]:
        if got >= 40:
            break
        x, z = float(X[i]), float(Z[i])
        if m_free(x, z, 4.2) and m_special_free(x, z):
            plan["pine"].append((x, z, rng_.uniform(0, 6.28), rng_.uniform(0.85, 1.2), int(rng_.integers(3))))
            m_solids.append((x, z, 3.0))
            got += 1
    # --- Zypressen: am Kapellenplatz, am Schotterplatz des Starts, vereinzelt an Terrassenrändern
    cx, cz = mt.PLAZA
    for k in range(9):
        a = math.radians(25 + k * 16)
        x, z = cx + math.cos(a) * 9.6, cz - math.sin(a) * 9.6
        if m_tr.at(m_tr.d, np.array([x]), np.array([z]))[0] > 6.0:
            plan["cypress"].append((x, z, rng_.uniform(0, 6.28), rng_.uniform(0.9, 1.15), int(rng_.integers(2))))
            m_solids.append((x, z, 1.2))
    ax_, az_, tx_, tz_, by_, ln_ = tr.ends()["start"]
    for k, (al, ac) in enumerate(((-6.0, 7.8), (-12.0, 8.4), (-16.0, -9.0), (-3.0, 11.0))):
        x = ax_ + tx_ * al - tz_ * ac
        z = az_ + tz_ * al + tx_ * ac
        if tr.at(tr.H, np.array([x]), np.array([z]))[0] > 5.0 and tr.at(tr.slope, np.array([x]), np.array([z]))[0] < 0.6:
            plan["cypress"].append((x, z, rng_.uniform(0, 6.28), rng_.uniform(0.9, 1.1), k % 2))
            m_solids.append((x, z, 1.2))
    X, Z = cand(16000)
    f = m_fields(X, Z)
    ok = (f["d"] > 12.0) & (f["h"] > 8.0) & (f["sl"] < 0.3) & (f["cd"] < 5.0) & (f["cd"] > 1.5) & (f["T"] > 0.2)
    got = 0
    for i in np.nonzero(ok)[0][rng_.permutation(int(ok.sum()))]:
        if got >= 9:
            break
        x, z = float(X[i]), float(Z[i])
        if m_free(x, z, 3.0) and m_special_free(x, z):
            plan["cypress"].append((x, z, rng_.uniform(0, 6.28), rng_.uniform(0.85, 1.15), int(rng_.integers(2))))
            m_solids.append((x, z, 1.2))
            got += 1
    # --- Agaven und Opuntien: Kliffrand und Böschung neben der Küstenstraße
    X, Z = cand(30000)
    f = m_fields(X, Z)
    s_ = tr.at(tr.Sn, X, Z)
    wgt = (f["cd"] < 4.5) & (f["cd"] > 0.8) & (f["sl"] < 0.7) & (f["h"] > 0.5) & (f["d"] > 6.4)
    wgt |= (f["d"] > 6.4) & (f["d"] < 11.0) & (s_ < 0.36) & (f["sl"] < 0.9) & (f["h"] > 5.0)
    got = 0
    for i in np.nonzero(wgt)[0][rng_.permutation(int(wgt.sum()))]:
        if got >= 34:
            break
        x, z = float(X[i]), float(Z[i])
        if m_free(x, z, 1.4) and m_special_free(x, z):
            kind = "agave" if rng_.random() < 0.6 else "opuntia"
            plan[kind].append((x, z, rng_.uniform(0, 6.28), rng_.uniform(0.8, 1.25), int(rng_.integers(4))))
            m_solids.append((x, z, 0.9))
            got += 1
    # --- Macchia: Hänge und Kanten
    X, Z = cand(40000)
    f = m_fields(X, Z)
    nb = tr.noise.fbm(X, Z, 12.0, 2, 21.0)
    ok = (f["d"] > 6.6) & (f["h"] > 0.8) & (f["sl"] > 0.12) & (f["sl"] < 1.0) & ((nb > 0.5) | (f["cd"] < 3.0)) & (f["cd"] > 0.6)
    got = 0
    for i in np.nonzero(ok)[0][rng_.permutation(int(ok.sum()))]:
        if got >= 130:
            break
        x, z = float(X[i]), float(Z[i])
        if m_free(x, z, 1.1) and m_special_free(x, z):
            plan["bush"].append((x, z, rng_.uniform(0, 6.28), rng_.uniform(0.7, 1.35), int(rng_.integers(8))))
            m_solids.append((x, z, 0.8))
            got += 1
    # --- Findlinge: am Fuß und am Rand der Wände, an Böschungen
    X, Z = cand(40000)
    f = m_fields(X, Z)
    ok = (f["d"] > 6.4) & (f["h"] > 0.2) & (f["cd"] < 3.2) & (f["sl"] > 0.15) & (f["sl"] < 1.1)
    got = 0
    for i in np.nonzero(ok)[0][rng_.permutation(int(ok.sum()))]:
        if got >= 90:
            break
        x, z = float(X[i]), float(Z[i])
        if m_free(x, z, 1.3) and m_special_free(x, z):
            plan["boulder"].append((x, z, rng_.uniform(0, 6.28), float(rng_.choice([0.8, 1.0, 1.3, 1.7, 2.3])) * rng_.uniform(0.85, 1.15), int(rng_.integers(5))))
            m_solids.append((x, z, 0.8))
            got += 1
    # --- Grasbüschel: in Flecken auf den Wiesen (nicht auf Kalkschotter), dicht bis an den Bankettrand
    X, Z = cand(70000)
    f = m_fields(X, Z)
    sandw = tr.at(tr.GC[..., 1], X, Z)
    ok = (f["d"] > 5.5) & (f["h"] > 0.6) & (f["sl"] < 0.55) & (sandw < 0.42) & (tr.noise.fbm(X, Z, 9.0, 2, 33.0) > 0.44)
    got = 0
    for i in np.nonzero(ok)[0][rng_.permutation(int(ok.sum()))]:
        if got >= 520:
            break
        x, z = float(X[i]), float(Z[i])
        if m_free(x, z, 0.45) and m_special_free(x, z):
            plan["tuft"].append((x, z, rng_.uniform(0, 6.28), rng_.uniform(0.8, 1.4), int(rng_.integers(8))))
            got += 1
    return plan


def m_build_plan(plan):
    near = 12.0                                           # Hindernisse nur nahe der Fahrbahn
    for kind, lst in plan.items():
        for x, z, yaw, sc, var in lst:
            y = m_height(x, z)
            d = float(m_tr.at(m_tr.d, np.array([x]), np.array([z]))[0])
            if kind == "olive":
                m_put(m_olive(var), x, z, yaw, sc, y - 0.1)
                if d < near:
                    collide_circle(x, z, 0.4 * sc, 3.0, "baum")
            elif kind == "pine":
                m_put(m_pine(var), x, z, yaw, sc, y - 0.15)
                if d < near:
                    collide_circle(x, z, 0.4 * sc, 4.0, "baum")
            elif kind == "cypress":
                m_put(m_cypress(var), x, z, yaw, sc, y - 0.1)
                if d < near:
                    collide_circle(x, z, 0.45 * sc, 4.0, "baum")
            elif kind == "bush":
                m_put(m_bush(var), x, z, yaw, sc, y - 0.05)
            elif kind == "agave":
                m_put(m_agave(var), x, z, yaw, sc, y - 0.05)
            elif kind == "opuntia":
                m_put(m_opuntia(var), x, z, yaw, sc, y - 0.05)
            elif kind == "tuft":
                m_put(m_tuft(var), x, z, yaw, sc, y - 0.03)
            elif kind == "boulder":
                m_put(m_boulder(var), x, z, yaw, sc, y - 0.1 * sc)
                if d < near and sc >= 0.9:
                    collide_circle(x, z, 0.45 * sc, 1.2, "mauer")
    print("DIORAMA Aufstellung:", {k: len(v) for k, v in plan.items()})


# ---------------------------------------------------------------- Parapetmauern (Leitplanken der Streckendatei) und Mauer um die Besonderheiten
def m_guard_walls():
    """Niedrige Trockenmauer am talseitigen Rand dort, wo die Streckendatei Leitplanken (guardrails) hat; die Fahrphysik prallt dort ab bzw. bricht
    durch. Die Mauer steht 4,9 m neben der Mittellinie (Mitte), 0,5 m dick, 0,72 m hoch."""
    count = 0
    n_c = len(center)
    for g in data.get("guardrails", []):
        side = 1.0 if g["side"] == "left" else -1.0
        i0, i1 = int(g["from"] * (n_c - 1)), int(g["to"] * (n_c - 1))
        pts = []
        for i in range(i0, i1 + 1, 2):
            p = center[i] + left[i] * side * (HW + 1.42)
            pts.append((p.x, p.y))
        if len(pts) >= 2:
            m_wall("Mauer_parapet_%d" % count, pts, 0.72, 0.5)
            count += 1
    print("DIORAMA Parapetmauern:", count)


# ---------------------------------------------------------------- Kleinteile aus Flächen (Material K_farbe: Vertexfarbe, linear)
def m_lin(c):
    return tuple(v ** 2.2 for v in c)


def m_box(parts, cx, cz, ang, hx, hz, y0, y1, color, top=True, key="farbe", tile=None, top_color=None):
    """Quader (Mitte, Drehung um die Senkrechte, halbe Maße, Höhen) als Flächenliste für mesh_object. tile: Texturgröße in m für Wandmaterial."""
    ca, sa = math.cos(ang), math.sin(ang)

    def P(a, b, y):
        return (cx + ca * a - sa * b, cz + sa * a + ca * b, y)
    corners = [(-hx, -hz), (hx, -hz), (hx, hz), (-hx, hz)]
    for k in range(4):
        (a0, b0), (a1, b1) = corners[k], corners[(k + 1) % 4]
        da, db = a1 - a0, b1 - b0
        ln = math.hypot(da, db)
        fa, fb = db / ln, -da / ln
        uvs = [(0, y0 / tile), (ln / tile, y0 / tile), (ln / tile, y1 / tile), (0, y1 / tile)] if tile else [(0, 0), (1, 0), (1, 1), (0, 1)]
        parts.append((key, [P(a0, b0, y0), P(a1, b1, y0), P(a1, b1, y1), P(a0, b0, y1)], uvs, (ca * fa - sa * fb, sa * fa + ca * fb), [color] * 4))
    if top:
        uvs = [(a / tile, b / tile) for a, b in corners] if tile else [(0, 0), (1, 0), (1, 1), (0, 1)]
        parts.append((key, [P(a, b, y1) for a, b in corners], uvs, None, [top_color or color] * 4))


def m_hut(x, z, ang):
    """Hirtenhütte aus Bruchstein mit Satteldach (Ziegel): 4,8 x 3,8 m, Tür und Fenster auf der Vorderseite (+b), Schornstein."""
    ca, sa = math.cos(ang), math.sin(ang)
    hx, hz = 2.4, 1.9

    def P(a, b, y):
        return (x + ca * a - sa * b, z + sa * a + ca * b, y)
    ys = [m_height(x + ca * a - sa * b, z + sa * a + ca * b) for a, b in ((-hx, -hz), (hx, -hz), (hx, hz), (-hx, hz))]
    yb, yw = min(ys) - 0.35, max(ys) + 2.3
    yr = yw + 1.3
    ye = yw - 0.12
    hl, hd = hx + 0.35, hz + 0.4
    parts = []
    m_box(parts, x, z, ang, hx, hz, yb, yw, (0.98, 0.96, 0.93), top=False, key="m_mauer", tile=3.3)
    for sb in (1, -1):
        e0, e1, r1, r0 = P(-hl, sb * hd, ye), P(hl, sb * hd, ye), P(hl, 0, yr), P(-hl, 0, yr)
        sl = math.hypot(hd, yr - ye)
        parts.append(("k:dach_ziegel", [e0, e1, r1, r0] if sb > 0 else [e1, e0, r0, r1], [(0, 0), (2 * hl / 4, 0), (2 * hl / 4, sl / 4), (0, sl / 4)], None,
                      [(0.9, 0.9, 0.9), (0.9, 0.9, 0.9), (1.0, 1.0, 1.0), (1.0, 1.0, 1.0)]))
    for sg in (-1, 1):
        pts = [P(sg * hx, -hz, yw), P(sg * hx, hz, yw), P(sg * hx, 0, yr)]
        parts.append(("m_mauer", pts, [(p[0] / 3.3, p[2] / 3.3) for p in pts], (ca * sg, sa * sg), [(0.95, 0.93, 0.9)] * 3))
    yg = m_height(P(0.0, hz + 0.05, 0.0)[0], P(0.0, hz + 0.05, 0.0)[1])
    uv4 = [(0, 0), (1, 0), (1, 1), (0, 1)]
    frame = [P(-0.62, hz + 0.02, yg), P(0.62, hz + 0.02, yg), P(0.62, hz + 0.02, yg + 1.97), P(-0.62, hz + 0.02, yg + 1.97)]
    parts.append(("farbe", frame, uv4, (-sa, ca), [m_lin((0.62, 0.60, 0.56))] * 4))
    door = [P(-0.5, hz + 0.03, yg), P(0.5, hz + 0.03, yg), P(0.5, hz + 0.03, yg + 1.85), P(-0.5, hz + 0.03, yg + 1.85)]
    parts.append(("farbe", door, uv4, (-sa, ca), [m_lin((0.12, 0.07, 0.04))] * 4))
    win = [P(1.2, hz + 0.03, yg + 1.0), P(1.9, hz + 0.03, yg + 1.0), P(1.9, hz + 0.03, yg + 1.7), P(1.2, hz + 0.03, yg + 1.7)]
    parts.append(("farbe", win, uv4, (-sa, ca), [m_lin((0.08, 0.1, 0.12))] * 4))
    cx_, cz_, _y = P(-1.2, -0.5, 0)
    m_box(parts, cx_, cz_, ang, 0.26, 0.26, yr - 0.5, yr + 0.9, (0.95, 0.93, 0.9), key="m_mauer", tile=3.3)
    return mesh_object("Huette", parts)


def m_boat(x, z, ang, hull, stripe):
    """Kleines Fischerboot (5,8 m): Rumpf mit Sprung, Deck, Kajüte, Mast. Treibt im Meer (Wasserlinie im Ursprung)."""
    ca, sa = math.cos(ang), math.sin(ang)

    def P(a, b, y):
        return (x + ca * a - sa * b, z + sa * a + ca * b, mt.WATER_Y + y)
    L = 5.8
    st = [(-0.5, 0.40, 0.62), (-0.30, 0.78, 0.50), (0.0, 0.95, 0.48), (0.28, 0.82, 0.55), (0.46, 0.45, 0.80), (0.5, 0.0, 0.95)]       # (Lage, halbe Breite, Höhe der Bordwand)
    parts = []
    uv4 = [(0, 0), (1, 0), (1, 1), (0, 1)]
    for (t0, w0, h0), (t1, w1, h1) in zip(st, st[1:]):
        a0, a1 = t0 * L, t1 * L
        for sb in (-1, 1):
            q = [P(a0, sb * w0, -0.3), P(a1, sb * w1, -0.3), P(a1, sb * w1, h1), P(a0, sb * w0, h0)]
            parts.append(("farbe", q, uv4, (-sa * sb, ca * sb), [hull, hull, stripe, stripe]))
        deck = [P(a0, -w0, h0 - 0.05), P(a1, -w1, h1 - 0.05), P(a1, w1, h1 - 0.05), P(a0, w0, h0 - 0.05)]
        parts.append(("farbe", deck, uv4, None, [m_lin((0.55, 0.42, 0.28))] * 4))
    m_box(parts, x + ca * (-0.9), z + sa * (-0.9), ang, 0.7, 0.55, mt.WATER_Y + 0.5, mt.WATER_Y + 1.55, m_lin((0.92, 0.92, 0.9)), top=True, top_color=m_lin((0.78, 0.2, 0.14)))
    for sg, fac in ((1, (-sa, ca)), (-1, (sa, -ca))):
        wn = [P(-0.2, sg * 0.56, 0.9), P(-1.6, sg * 0.56, 0.9), P(-1.6, sg * 0.56, 1.3), P(-0.2, sg * 0.56, 1.3)]
        parts.append(("farbe", wn, uv4, fac, [m_lin((0.06, 0.09, 0.12))] * 4))
    m_box(parts, x + ca * 0.9, z + sa * 0.9, ang, 0.04, 0.04, mt.WATER_Y + 0.5, mt.WATER_Y + 3.0, m_lin((0.4, 0.34, 0.28)))
    return mesh_object("Boot", parts)


def m_gantry(i_c, kind):
    """Torbogen quer über die Fahrbahn an Mittellinienindex i_c: zwei Pfosten außerhalb der Randsteine und ein Querträger mit Schachbrett (Ziel)
    bzw. rot-weißen Feldern (Start). Steht neben der Fahrbahn: ohne Hindernis."""
    c, t, l_ = center[i_c], tang[i_c], left[i_c]
    ang = math.atan2(t.y, t.x)
    base = float(m_tr.nearest(np.array([c.x]), np.array([c.y]))[2][0]) + ROAD_Y
    off = HW + 1.2
    parts = []
    for side in (1, -1):
        p = c + l_ * side * off
        gy = m_height(p.x, p.y)
        m_box(parts, p.x, p.y, ang, 0.16, 0.16, gy - 0.1, base + 5.3, m_lin((0.82, 0.82, 0.8)))
    y0, y1 = base + 4.5, base + 5.4
    for face in (1, -1):                                  # Vorder- und Rückseite des Querträgers
        for k in range(int((2 * off + 0.4) / 0.45)):
            b0 = -off - 0.2 + k * 0.45
            for r in range(2):
                white = (k + r) % 2 == 0
                col = m_lin((0.93, 0.93, 0.9)) if white else m_lin((0.04, 0.04, 0.05))
                if kind == "start":
                    col = m_lin((0.93, 0.93, 0.9)) if white else m_lin((0.8, 0.12, 0.08))
                ya, yb2 = y0 + r * 0.45, y0 + (r + 1) * 0.45
                q = [(c.x + l_.x * b0 + t.x * 0.13 * face, c.y + l_.y * b0 + t.y * 0.13 * face, ya),
                     (c.x + l_.x * (b0 + 0.45) + t.x * 0.13 * face, c.y + l_.y * (b0 + 0.45) + t.y * 0.13 * face, ya),
                     (c.x + l_.x * (b0 + 0.45) + t.x * 0.13 * face, c.y + l_.y * (b0 + 0.45) + t.y * 0.13 * face, yb2),
                     (c.x + l_.x * b0 + t.x * 0.13 * face, c.y + l_.y * b0 + t.y * 0.13 * face, yb2)]
                parts.append(("farbe", q, [(0, 0), (1, 0), (1, 1), (0, 1)], (t.x * face, t.y * face), [col] * 4))
    m_box(parts, c.x, c.y, ang, 0.12, off + 0.3, y0 - 0.04, y1 + 0.04, m_lin((0.7, 0.7, 0.72)), top=True)
    return mesh_object("Torbogen_" + kind, parts)


def m_finish_line(i_c):
    """Schachbrettstreifen quer über die Fahrbahn (zwei Reihen wie die Startlinie des Spiels), knapp über der Fahrbahn."""
    c, t, l_ = center[i_c], tang[i_c], left[i_c]
    base = float(m_tr.nearest(np.array([c.x]), np.array([c.y]))[2][0]) + ROAD_Y + 0.036
    parts = []
    for row in range(2):
        for k in range(10):
            b0 = -HW + 0.35 + k * 0.7
            a0 = (row - 1) * 0.36
            key = "weiss" if (row + k) % 2 == 0 else "dunkel"
            q = [(c.x + l_.x * b0 + t.x * a0, c.y + l_.y * b0 + t.y * a0, base), (c.x + l_.x * (b0 + 0.7) + t.x * a0, c.y + l_.y * (b0 + 0.7) + t.y * a0, base),
                 (c.x + l_.x * (b0 + 0.7) + t.x * (a0 + 0.36), c.y + l_.y * (b0 + 0.7) + t.y * (a0 + 0.36), base),
                 (c.x + l_.x * b0 + t.x * (a0 + 0.36), c.y + l_.y * b0 + t.y * (a0 + 0.36), base)]
            parts.append((key, q, [(0, 0), (1, 0), (1, 1), (0, 1)]))
    return mesh_objects("Ziel", parts)


def m_plaza():
    """Kapellenplatz: Pflaster auf dem ebenen Platz vor der Kapelle, Laterne mit Steinsockel neben dem Weg."""
    cx, cz = mt.PLAZA
    y = m_tr.plaza_y + 0.07
    pts = []
    for k in range(32):
        a = 2 * math.pi * k / 32
        r = 5.6 * (1.0 + 0.07 * math.sin(3 * a + 0.8) + 0.05 * math.sin(5 * a + 2.0))
        pts.append((cx + math.cos(a) * r, cz + math.sin(a) * r))
    parts = []
    for k in range(32):
        p0, p1 = pts[k], pts[(k + 1) % 32]
        tri = [(cx, cz, y), (p0[0], p0[1], y), (p1[0], p1[1], y)]
        parts.append(("pflaster", tri, [(q[0] / 3.0, -q[1] / 3.0) for q in tri], None))
    mesh_object("Pflaster", parts)
    lx, lz = 4.6, -84.2                                   # Laterne: Steinsockel, Eisenmast, Laternenkorb
    ly = m_height(lx, lz)
    pr = []
    m_box(pr, lx, lz, 0.2, 0.28, 0.28, ly - 0.1, ly + 1.05, (0.97, 0.95, 0.92), key="m_mauer", tile=3.3, top_color=(0.8, 0.78, 0.74))
    m_box(pr, lx, lz, 0.0, 0.045, 0.045, ly + 1.05, ly + 2.1, m_lin((0.07, 0.07, 0.08)))
    m_box(pr, lx, lz, 0.0, 0.17, 0.17, ly + 2.1, ly + 2.55, m_lin((0.9, 0.86, 0.7)), top=True, top_color=m_lin((0.08, 0.08, 0.09)))
    m_box(pr, lx, lz, 0.0, 0.2, 0.2, ly + 2.55, ly + 2.7, m_lin((0.07, 0.07, 0.08)))
    mesh_object("Laterne", pr)


def m_posts():
    """Leitpfosten (weiß mit rotem Reflektorband) alle 16 m an beiden Fahrbahnrändern, wo keine Parapetmauer steht."""
    parts = []
    n_c = len(center)
    spans = []
    for g in data.get("guardrails", []):
        spans.append((int(g["from"] * (n_c - 1)) - 6, int(g["to"] * (n_c - 1)) + 6, 1.0 if g["side"] == "left" else -1.0))
    count = 0
    for i in range(24, n_c - 24, 32):
        for side in (1.0, -1.0):
            if any(a <= i <= b and sd == side for a, b, sd in spans):
                continue
            p = center[i] + left[i] * side * (HW + 1.05)
            if float(m_tr.at(m_tr.d, np.array([p.x]), np.array([p.y]))[0]) < HW + 0.9:
                continue
            gy = m_height(p.x, p.y)
            ang = math.atan2(tang[i].y, tang[i].x)
            m_box(parts, p.x, p.y, ang, 0.055, 0.055, gy - 0.05, gy + 0.95, m_lin((0.88, 0.88, 0.86)))
            m_box(parts, p.x, p.y, ang, 0.06, 0.06, gy + 0.62, gy + 0.82, m_lin((0.75, 0.06, 0.04)), top=False)
            count += 1
    if parts:
        mesh_object("Leitpfosten", parts)
    print("DIORAMA Leitpfosten:", count)


def m_warning_signs():
    """Warndreiecke "Kurve" vor den Kehren auf der rechten Straßenseite (Pfosten, rotes Dreieck, weiße Fläche, schwarzer Pfeil)."""
    parts = []
    n_c = len(center)
    kehren = []
    last = -999
    for i in range(n_c):
        if curv[i] > 0.09:
            if i - last > 120:
                kehren.append(i)
            last = i
    for i0 in kehren:
        i = max(i0 - 90, 8)
        t, l_ = tang[i], left[i]
        p = center[i] - l_ * (HW + 1.35)
        gy = m_height(p.x, p.y)
        ang = math.atan2(t.y, t.x)
        if float(m_tr.at(m_tr.d, np.array([p.x]), np.array([p.y]))[0]) < HW + 1.0:
            continue
        m_box(parts, p.x, p.y, ang, 0.03, 0.03, gy - 0.05, gy + 2.3, m_lin((0.55, 0.57, 0.6)), top=False)
        fx, fz = -t.x, -t.y                                # das Schild blickt dem Fahrer entgegen
        sx, sz = -fz, fx
        cy = gy + 2.35
        for r, col, dz in ((0.62, m_lin((0.78, 0.05, 0.04)), 0.02), (0.46, m_lin((0.95, 0.95, 0.93)), 0.035)):
            tri = [(p.x + fx * dz - sx * r * 0.9, p.y + fz * dz - sz * r * 0.9, cy - r * 0.55),
                   (p.x + fx * dz + sx * r * 0.9, p.y + fz * dz + sz * r * 0.9, cy - r * 0.55),
                   (p.x + fx * dz, p.y + fz * dz, cy + r * 1.0)]
            parts.append(("farbe", tri, [(0, 0), (1, 0), (0.5, 1)], (fx, fz), [col] * 3))
        arrow = [(-0.04, -0.28), (0.04, -0.28), (0.04, 0.0), (0.2, 0.12), (0.12, 0.2), (-0.04, 0.05)]
        pts3 = [(p.x + fx * 0.05 + sx * a, p.y + fz * 0.05 + sz * a, cy + b - 0.05) for a, b in arrow]
        parts.append(("farbe", pts3, [(0, 0)] * len(pts3), (fx, fz), [m_lin((0.04, 0.04, 0.05))] * len(pts3)))
    if parts:
        mesh_object("Warnschilder", parts)
    print("DIORAMA Warnschilder vor Kehren:", len(kehren))


def m_start_cars():
    """Einige parkende Autos auf dem Schotterplatz hinter dem Start (Service und Zuschauer)."""
    ax_, az_, tx_, tz_, by_, ln_ = m_tr.ends()["start"]
    rng_ = random.Random(77)
    parts_all = []
    placed_ = 0
    for al, ac, turn in ((-5.5, 7.0, 0.0), (-9.5, 7.2, 0.15), (-5.0, -7.2, math.pi), (-10.0, -7.4, math.pi - 0.2), (-15.0, 7.6, 0.4), (-14.0, -7.6, math.pi + 0.2)):
        x = ax_ + tx_ * al - tz_ * ac
        z = az_ + tz_ * al + tx_ * ac
        yy = m_height(x, z)
        if abs(yy - (by_ + mt.GROUND_Y)) > 0.4 or float(m_tr.at(m_tr.slope, np.array([x]), np.array([z]))[0]) > 0.15:
            continue
        ang = math.atan2(tz_, tx_) + turn
        ux, uz = math.cos(ang), math.sin(ang)
        parts_c, (car_len, car_wid) = kit_car.random_car(rng_, x, z, ux, uz, base_y=yy)
        parts_all += parts_c
        collide_rect(x, z, ux, uz, car_len / 2, car_wid / 2, 1.5, "auto")
        placed_ += 1
    if parts_all:
        mesh_object("Auto_start", parts_all)
    print("DIORAMA Autos am Start:", placed_)


def m_hut_site():
    """Ort der Hütte: die ebene Terrasse, die das Gelände dafür anlegt (tr.hut); Tür zur nächsten Fahrbahnstelle. Dazu ein Pferch aus Trockenmauer."""
    tr = m_tr
    if tr.hut is None:
        print("DIORAMA Hütte: kein Platz gefunden")
        return
    x, z = tr.hut
    k = int(np.argmin(((C - np.array([[x, z]])) ** 2).sum(1)))        # Tür zur nächsten Fahrbahnstelle
    dx, dz = C[k, 0] - x, C[k, 1] - z
    ang = math.atan2(-dx, dz)
    m_hut(x, z, ang)
    m_solids.append((x, z, 5.0))
    m_stats["hut"] = (x, z, ang)
    ca, sa = math.cos(ang), math.sin(ang)
    corners = [(3.2, -1.0), (10.2, -1.0), (10.2, 4.0), (3.2, 4.0)]
    pts = [(x + ca * a - sa * b, z + sa * a + ca * b) for a, b in corners]
    if all(abs(m_height(px, pz) - m_height(x, z)) < 0.9 for px, pz in pts):
        m_wall("Mauer_pferch", pts + [pts[0]], 1.05, 0.45)
    print("DIORAMA Hütte bei", (round(x, 1), round(z, 1)), "Höhe", round(tr.hut_y, 1), "Tür zur Fahrbahn")


def m_boats():
    tr = m_tr
    hx, hz = mt.HILL["lighthouse"]
    rng_ = np.random.default_rng(11)
    got = 0
    spots = []
    colors = [(m_lin((0.08, 0.2, 0.5)), m_lin((0.9, 0.9, 0.88))), (m_lin((0.7, 0.1, 0.08)), m_lin((0.92, 0.92, 0.9))), (m_lin((0.92, 0.9, 0.84)), m_lin((0.1, 0.35, 0.4)))]
    for _ in range(400):
        x, z = hx + rng_.uniform(-32, 32), hz + rng_.uniform(-14, 14)
        if (float(tr.at(tr.land_dist, np.array([x]), np.array([z]))[0]) > 7.0 and x0 + 10 < x < x1 - 10 and z < z1 - 8
                and all((x - sx) ** 2 + (z - sz) ** 2 > 100 for sx, sz in spots)):
            spots.append((x, z))
            h, st_ = colors[got % 3]
            m_boat(x, z, rng_.uniform(0, 6.28), h, st_)
            got += 1
            if got >= 3:
                break
    print("DIORAMA Boote:", got)


# ---------------------------------------------------------------- Bildstock, Bienenstöcke
def m_shrine():
    """Bildstock (weiß gekalkter Pfeiler mit Nische, Ziegeldach und Kreuz) am rechten Straßenrand zwischen zwei Kehren; blickt zur Fahrbahn."""
    n_c = len(center)
    spot = None
    for i in range(int(n_c * 0.55), int(n_c * 0.70), 4):
        c, l_ = center[i], left[i]
        p = c - l_ * (HW + 3.3)
        P1 = (np.array([p.x]), np.array([p.y]))
        gy = m_height(p.x, p.y)
        base = float(m_tr.nearest(np.array([c.x]), np.array([c.y]))[2][0]) + ROAD_Y
        flat = (float(m_tr.at(m_tr.d, *P1)[0]) > HW + 2.2 and abs(gy - base) < 0.6 and float(m_tr.at(m_tr.slope, *P1)[0]) < 0.25
                and float(m_tr.at(m_tr.cliff_dist, *P1)[0]) > 3.0)
        if flat and m_free(p.x, p.y, 1.6) and m_special_free(p.x, p.y):
            spot = (p, c, gy)
            break
    if spot is None:
        print("DIORAMA Bildstock: kein Platz")
        return
    p, c, gy = spot
    fx, fz = c.x - p.x, c.y - p.y
    fl = math.hypot(fx, fz)
    fx, fz = fx / fl, fz / fl
    ang = math.atan2(fz, fx)
    ca, sa = fx, fz
    white = (0.95, 0.93, 0.89)
    parts = []
    m_box(parts, p.x, p.y, ang, 0.55, 0.55, gy - 0.15, gy + 0.45, (0.9, 0.88, 0.84), key="m_mauer", tile=3.3, top_color=(0.8, 0.78, 0.74))
    m_box(parts, p.x, p.y, ang, 0.34, 0.34, gy + 0.45, gy + 1.75, white, key="m_mauer", tile=3.3, top_color=(0.8, 0.78, 0.74))
    m_box(parts, p.x + ca * 0.335, p.y + sa * 0.335, ang, 0.02, 0.17, gy + 1.0, gy + 1.55, m_lin((0.1, 0.08, 0.06)), top=False)
    m_box(parts, p.x + ca * 0.32, p.y + sa * 0.32, ang, 0.03, 0.05, gy + 1.0, gy + 1.13, m_lin((0.72, 0.1, 0.08)), top=False)
    apex = (p.x, p.y, gy + 2.2)
    eave = [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)]

    def W(a, b, y):
        return (p.x + ca * a - sa * b, p.y + sa * a + ca * b, y)
    for k in range(4):
        (a0, b0), (a1, b1) = eave[k], eave[(k + 1) % 4]
        am, bm = (a0 + a1) / 2, (b0 + b1) / 2
        out = (ca * am - sa * bm, sa * am + ca * bm)
        parts.append(("k:dach_ziegel", [W(a0, b0, gy + 1.75), W(a1, b1, gy + 1.75), apex], [(0, 0), (0.3, 0), (0.15, 0.3)], out, [(0.9, 0.9, 0.9), (0.9, 0.9, 0.9), (1.0, 1.0, 1.0)]))
    iron = m_lin((0.07, 0.07, 0.08))
    m_box(parts, p.x, p.y, ang, 0.018, 0.018, gy + 2.2, gy + 2.62, iron)
    m_box(parts, p.x, p.y, ang, 0.018, 0.075, gy + 2.43, gy + 2.48, iron)
    mesh_object("Bildstock", parts)
    collide_circle(p.x, p.y, 0.62, 2.0, "mauer")
    m_solids.append((p.x, p.y, 1.0))
    print("DIORAMA Bildstock bei", (round(p.x, 1), round(p.y, 1)))


def m_hives():
    """Vier Bienenstöcke (weiße Kästen mit farbigem Deckel auf niedrigen Böcken) auf der Terrasse hinter der Hütte."""
    if "hut" not in m_stats:
        return
    x, z, ang = m_stats["hut"]
    ca, sa = math.cos(ang), math.sin(ang)
    parts = []
    lids = [(0.18, 0.35, 0.62), (0.9, 0.72, 0.15), (0.2, 0.52, 0.28), (0.78, 0.22, 0.16)]
    for k in range(4):
        a, b = -2.6 + 1.25 * k, -4.3 + 0.25 * math.sin(k * 1.7)
        hx, hz = x + ca * a - sa * b, z + sa * a + ca * b
        gy = m_height(hx, hz)
        ar = ang + 0.05 * (k - 1.5)
        m_box(parts, hx, hz, ar, 0.23, 0.2, gy, gy + 0.24, m_lin((0.35, 0.28, 0.2)))
        m_box(parts, hx, hz, ar, 0.25, 0.22, gy + 0.24, gy + 0.7, m_lin((0.93, 0.92, 0.88)))
        m_box(parts, hx, hz, ar, 0.29, 0.26, gy + 0.7, gy + 0.77, m_lin(lids[k]), top_color=m_lin(lids[k]))
    mesh_object("Bienenstoecke", parts)
    print("DIORAMA Bienenstöcke: 4")


def m_safe(fn):
    """Zierbauteile dürfen den Bau nicht abbrechen: Fehler melden und weitermachen."""
    try:
        fn()
    except Exception as exc:
        print("DIORAMA Warnung:", fn.__name__, repr(exc))


# ---------------------------------------------------------------- Szenerie (Hook 3)
def m_lights():
    hx, hz = mt.HILL["lighthouse"]
    ly = m_height(hx, hz) + 13.0
    add_light(hx, hz, ly, (1.0, 0.9, 0.66), 0.8, 30.0, omni=False, glow=3.0)
    cx, cz = 4.6, -84.2
    cy = m_tr.plaza_y + 2.2
    add_light(cx, cz, cy, (1.0, 0.72, 0.38), 1.1, 12.0, omni=True, glow=0.9)


def m_runtime_props():
    """Bodenhöhe der Laufzeit-Bauteile (Kapelle, Leuchtturm, Aussicht) und ihr Kontaktschatten."""
    tr = m_tr
    n = set_prop_heights(lambda x, z: float(tr.height(x, z)) - float(tr.grid_height(np.array([x]), np.array([z]))[0]), types=["ai"])
    saved = data["props"]
    data["props"] = [p for p in saved if not (p.get("type") == "ai" and ("ai:" + str(p.get("model", ""))) in M_BAKED)]
    try:
        ao_proxies(types=["ai"], base_y=lambda x, z: m_height(x, z))
    finally:
        data["props"] = saved
    print("DIORAMA Laufzeit-Bauteile mit Bodenhöhe:", n)


def m_report():
    tris = 0
    for o in scene.objects:
        if o.type == "MESH" and o.data is not None:
            tris += sum(max(1, len(p.vertices) - 2) for p in o.data.polygons)
    uniq = sum(max(1, len(p.vertices) - 2) for me in bpy.data.meshes if me.users for p in me.polygons)
    print("DIORAMA Dreiecke (instanziert, ungefähr):", tris, "| verschiedene Netze:", uniq)


def theme_scenery():
    plan = m_plan()
    m_build_plan(plan)
    m_guard_walls()
    m_hut_site()
    m_safe(m_hives)
    m_posts()
    m_safe(m_shrine)
    m_warning_signs()
    m_start_cars()
    m_plaza()
    m_boats()
    m_gantry(4, "start")
    m_gantry(len(center) - 1 - 4, "ziel")
    m_finish_line(len(center) - 1 - 8)
    m_lights()
    m_runtime_props()
    m_report()


def theme_bake_hidden():
    return ["Meer"]


def theme_layout(layout):
    layout["water_y"] = mt.WATER_Y
