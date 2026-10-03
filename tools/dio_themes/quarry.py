"""Themenmodul "quarry" (Quarry Loop): offener Kalksteinbruch mit Schotterpiste, Gruben, Sprungschanze, Looping und Abkürzung.

Wird von tools/diorama.py in dessen Globals ausgeführt (siehe docs/dioramen/README.md; Beschreibung der Szene und Entscheidungen:
docs/dioramen/quarry.md). Straße: "runtime" (das Spiel baut die Schotterpiste samt Rampen, Graben, Looping und Abkürzung selbst, auf Höhe
0,17); das Diorama liefert den Boden mit Geländestufen, Findlinge, Wasserfläche und Baustellenausrüstung.

Gelände: Die Grubensohle (Fahrbahn plus 10 m Rand, das Innere der Strecke und die Flächen um die KI-Modelle) bleibt eben auf 0,08 m. Dahinter
steigt das Gelände in vier Bänken (Sohle 8,5 m breit, Böschung 2 m, Stufe 2,8 m) bis zur Hochfläche an; die Felswand-Modelle der
Streckendatei (bei z = +-58) stehen dort halb eingegraben. Alles Feste, was dieses Modul zusätzlich setzt, hat ein Hindernis in der
Begleitdatei; die KI-Modelle (Bagger, Kipper, Brecher, Förderband, Büro, Kieshaufen, Felswände) bleiben Laufzeit-Bauteile und bekommen über
ao_proxies() ihren Kontaktschatten. Echte Lichtquellen der Nacht: die Baustellenleuchten (lamps).
"""
from mathutils import noise

Q_TEX = "res://assets/dio/quarry/"
THEME_CFG = {
    "road": "runtime",
    "ground_y": 0.08,
    "margin": 46.0,
    "baked": ["ai:steinbruch_kieshaufen", "ai:steinbruch_foerderband"],   # Kieshaufen und Förderband baut das Diorama selbst (die KI-Modelle waren unbrauchbar bzw. winzig)
    "vertex_colors": "ACTIVE",
    # Bodenmischung: Platz "grass" = Schotter (Sohle, Absätze), "sand" = Staub und Lehm (Pistenrand, Betriebswege), "dirt" = Fels (Böschungen)
    "ground_set": {"grass": Q_TEX + "boden_schotter", "sand": Q_TEX + "boden_staub", "dirt": Q_TEX + "boden_fels"},
    "ground_scales": {"grass": 3.0, "sand": 3.5, "dirt": 4.0},
    "ground_tints": {"grass": [1.0, 0.99, 0.96], "sand": [1.0, 0.97, 0.92], "dirt": [1.0, 0.98, 0.95]},
    # Baggersee: türkisgrün im Flachen (Kalk), tief dunkles Blaugrün, heller Kalksaum am Ufer
    "water": {"lagoon": [0.22, 0.46, 0.44], "open": [0.035, 0.17, 0.21], "foam": [0.60, 0.66, 0.60]},
    "water_nodes": ["See"],
}

Q_STEP = 1.0                                   # Raster des Bodens (m)
Q_DF = 10.0                                    # Breite der ebenen Sohle neben der Fahrbahn
Q_BENCHES, Q_U0, Q_PERIOD, Q_RISE, Q_SLOPE = 4, 1.5, 10.5, 2.8, 2.0
Q_LAKE = {"x": -42.0, "z": -5.0, "w": 18.0, "d": 11.0}
Q_WATER_DEPTH = 1.5
Q_LAKE_SLOPE = 4.5                              # Länge der Uferböschung (m)
if data.get("rev", 1) >= 2:
    Q_LAKE = {"x": 9.0, "z": -9.5, "w": 7.5, "d": 4.2}      # Pumpensumpf östlich des Sohlenwegs (Wasserhaltung der Grube)
    Q_WATER_DEPTH = 1.1
    Q_LAKE_SLOPE = 1.1
Q_AI = [p for p in data["props"] if p["type"] == "ai"]
Q_PLAN = {}
Q_PIT = {}                                      # Graben in der Lücke der Fahrbahn (Lage und Raster), von q_pit_plan() gefüllt
Q_SOLIDS = []
q_stats = {}
q_mats = {}
# ebene Flächen um die KI-Modelle der Streckendatei (Mitte, Radius); das Förderband ist eine Strecke mit Abstand
Q_FLAT = {"steinbruch_bagger": 9.0, "steinbruch_kipper": 8.5, "steinbruch_brecher": 14.0, "steinbruch_buero": 11.0, "steinbruch_kieshaufen": 7.0}
Q_BELT = ((50.6, 41.6), (69.4, 48.4), 7.5)


# ---------------------------------------------------------------- Hilfsfunktionen (gleich wie im Waldthema, Präfix q_)
def q_smooth(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def q_noise(x, z, scale, ox=0.0):
    """Weiches Wertrauschen wie value_noise des Kerns, aber für numpy-Felder (Werte 0..1)."""
    u, v = np.asarray(x) / scale + ox, np.asarray(z) / scale + ox * 0.61
    i0, j0 = np.floor(u).astype(int), np.floor(v).astype(int)
    fu, fv = q_smooth(u - i0), q_smooth(v - j0)
    g = _noise_grid
    a = g[j0 % 64, i0 % 64] * (1 - fu) + g[j0 % 64, (i0 + 1) % 64] * fu
    b = g[(j0 + 1) % 64, i0 % 64] * (1 - fu) + g[(j0 + 1) % 64, (i0 + 1) % 64] * fu
    return a * (1 - fv) + b * fv


def q_fbm(x, z, scale, octaves=3, ox=0.0):
    out, amp, tot = 0.0, 1.0, 0.0
    for k in range(octaves):
        out = out + amp * q_noise(x, z, scale / (2 ** k), ox + 17.0 * k)
        tot += amp
        amp *= 0.5
    return out / tot


def q_nearest_center(P):
    """Index der nächsten Mittellinienstütze (alle 0,5 m) und Seitenabstand (links positiv) für viele Punkte."""
    idx = np.zeros(len(P), int)
    lat = np.zeros(len(P))
    Cc = C[::2]
    for k in range(0, len(P), 1500):
        q = P[k:k + 1500]
        d2 = ((q[:, None, :] - Cc[None, :, :]) ** 2).sum(2)
        ii = d2.argmin(1) * 2
        idx[k:k + 1500] = ii
        Lf = np.array([[left[i].x, left[i].y] for i in ii])
        lat[k:k + 1500] = ((q - C[ii]) * Lf).sum(1)
    return idx, lat


def q_dc(x, z):
    return float(dist_to_center(np.array([(x, z)]))[0])


def q_grid_mesh_quad(name, key, gx, gz, H, COL, skip=None, tile=4.0, tol_h=0.012, tol_c=0.05, max_size=8):
    """Wie q_grid_mesh, aber als Viererbaum: Ein Block aus s x s Zellen (s = 8, 4, 2) wird zu einem Viereck, wenn Höhe und Vertexfarben darin
    von der bilinearen Interpolation der vier Ecken nicht mehr als tol_h (m) bzw. tol_c abweichen. Spart Dreiecke auf ebenen, gleichmäßigen
    Flächen; die Abweichung (höchstens 1,2 cm) bleibt unsichtbar."""
    nx, nz = len(gx), len(gz)
    ncx, ncz = nx - 1, nz - 1
    bm = bmesh.new()
    uv0 = bm.loops.layers.uv.new("UVMap")
    col = bm.loops.layers.float_color.new("Color")
    verts = {}

    def vert(i, j):
        if (i, j) not in verts:
            verts[(i, j)] = bm.verts.new((float(gx[i]), -float(gz[j]), float(H[j, i])))
        return verts[(i, j)]

    def emit(i, j, sz):
        corners = ((i, j), (i, j + sz), (i + sz, j + sz), (i + sz, j))
        f = bm.faces.new([vert(a_, b_) for a_, b_ in corners])
        f.smooth = True
        for loop, (a_, b_) in zip(f.loops, corners):
            loop[uv0].uv = (float(gx[a_]) / tile, float(-gz[b_]) / tile)
            c = COL[b_, a_]
            loop[col] = (float(c[0]), float(c[1]), float(c[2]), 1.0)

    def block_ok(i, j, sz):
        if i + sz > ncx or j + sz > ncz:
            return False
        if skip is not None and skip[j:j + sz, i:i + sz].any():
            return False
        u = np.linspace(0.0, 1.0, sz + 1)[None, :]
        v = np.linspace(0.0, 1.0, sz + 1)[:, None]
        h = H[j:j + sz + 1, i:i + sz + 1]
        hp = h[0, 0] * (1 - u) * (1 - v) + h[0, -1] * u * (1 - v) + h[-1, 0] * (1 - u) * v + h[-1, -1] * u * v
        if np.abs(h - hp).max() > tol_h:
            return False
        c = COL[j:j + sz + 1, i:i + sz + 1]
        cp = (c[0, 0] * ((1 - u) * (1 - v))[..., None] + c[0, -1] * (u * (1 - v))[..., None] + c[-1, 0] * ((1 - u) * v)[..., None] + c[-1, -1] * (u * v)[..., None])
        return float(np.abs(c - cp).max()) <= tol_c

    def rec(i, j, sz):
        if i >= ncx or j >= ncz:
            return
        if sz == 1:
            if not (skip is not None and skip[j, i]):
                emit(i, j, 1)
        elif block_ok(i, j, sz):
            emit(i, j, sz)
        else:
            h2 = sz // 2
            for dj in (0, h2):
                for di in (0, h2):
                    rec(i + di, j + dj, h2)
    for j in range(0, ncz, max_size):
        for i in range(0, ncx, max_size):
            rec(i, j, max_size)
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(M[key])
    obj = bpy.data.objects.new(name, me)
    scene.collection.objects.link(obj)
    return obj


def q_grid_mesh(name, key, gx, gz, H, COL, skip=None, tile=4.0):
    """Glatt schattiertes Höhennetz mit gemeinsamen Ecken. gx, gz: Koordinaten (n,), H: Höhen (nz, nx), COL: Vertexfarben (nz, nx, 3),
    skip: (nz-1, nx-1) Bool = Zelle auslassen."""
    nx, nz = len(gx), len(gz)
    bm = bmesh.new()
    uv0 = bm.loops.layers.uv.new("UVMap")
    col = bm.loops.layers.float_color.new("Color")
    verts = [[bm.verts.new((float(gx[i]), -float(gz[j]), float(H[j, i]))) for i in range(nx)] for j in range(nz)]
    for j in range(nz - 1):
        for i in range(nx - 1):
            if skip is not None and skip[j, i]:
                continue
            quad = ((i, j), (i, j + 1), (i + 1, j + 1), (i + 1, j))
            f = bm.faces.new([verts[b][a] for a, b in quad])
            f.smooth = True
            for loop, (a, b) in zip(f.loops, quad):
                loop[uv0].uv = (float(gx[a]) / tile, float(-gz[b]) / tile)
                c = COL[b, a]
                loop[col] = (float(c[0]), float(c[1]), float(c[2]), 1.0)
    bm.normal_update()
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(M[key])
    obj = bpy.data.objects.new(name, me)
    scene.collection.objects.link(obj)
    return obj


def q_bm_object(name, bm, materials, link=True):
    """bmesh in ein Objekt mit Materialien wandeln (bm wird freigegeben)."""
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in materials:
        me.materials.append(m)
    obj = bpy.data.objects.new(name, me)
    if link:
        scene.collection.objects.link(obj)
    return obj


def q_put(name, x, z, ang, height=None, footprint=None, y=None, label="Prop", anchor="bbox", scale=None):
    """Modell aus LIB (KI-Modell oder selbst gebautes Teil) wie world.gd place_ai setzen: Mitte der Grundfläche auf (x, z), Unterkante auf y
    (Vorgabe Boden), gleichmäßig auf Höhe bzw. Grundfläche (footprint = (Breite entlang u, Tiefe)) skaliert. Drehung ang (Bogenmaß) wie das
    Feld "rot" der Strecke. anchor "origin": Ursprung des Modells ist der Fußpunkt. Kein Kollisionseintrag. Rückgabe: Objekt."""
    obj, ext = model(name)
    vs = np.array([(v.co.x, v.co.y, v.co.z) for v in obj.data.vertices])
    lo, hi = vs.min(0), vs.max(0)
    cx, cy, zmin = (lo[0] + hi[0]) / 2.0, (lo[1] + hi[1]) / 2.0, lo[2]
    if anchor == "origin":
        cx, cy, zmin = 0.0, 0.0, 0.0
    if scale is not None:
        s = scale
    elif footprint is not None:
        s = min(footprint[0] / max(hi[0] - lo[0], 1e-4), footprint[1] / max(hi[1] - lo[1], 1e-4))
    else:
        s = height / max(hi[2] - lo[2], 1e-4)
    inst = obj.copy()
    inst.name = "%s_%s" % (label, name.replace("@", "_").replace(".", "_"))
    scene.collection.objects.link(inst)
    inst.matrix_world = (Matrix.Translation((x, -z, GROUND_Y if y is None else y)) @ Matrix.Rotation(-ang, 4, "Z")
                         @ Matrix.Scale(s, 4) @ Matrix.Translation((-cx, -cy, -zmin)))
    return inst


def q_register(key, obj):
    """Selbst gebautes Teil für q_put in LIB eintragen (Objekt nicht in der Szene)."""
    for col_ in list(obj.users_collection):
        col_.objects.unlink(obj)
    vs = [v.co for v in obj.data.vertices]
    ext = Vector((max(v.x for v in vs) - min(v.x for v in vs), max(v.y for v in vs) - min(v.y for v in vs), max(v.z for v in vs) - min(v.z for v in vs)))
    LIB[key] = (obj, ext)
    return key


def q_spin(x, z):
    """Feste Zufallsdrehung je Ort (wie world.gd premium_prop)."""
    return (x * 12.9898 + z * 78.233) % (2 * math.pi)


def q_vertex_color(mat):
    """Materialzweig, der die Vertexfarbe "Color" liest: Der glTF-Export gibt sie nur dann als COLOR_0 aus (sonst steht dort Weiß und die
    Gewichte des Bodens/Wassers landen in COLOR_1, das der Boden-Shader nicht liest)."""
    nt = mat.node_tree
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Color"
    nt.links.new(vc.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    return mat


def q_tex_material(name, image, tint_by_vertex=True, rough=0.9, color=None):
    """Material mit Bildtextur, auf Wunsch mit Vertexfarbe multipliziert (der glTF-Export macht daraus Textur x COLOR_0)."""
    if name in q_mats:
        return q_mats[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    if image:
        tx = nt.nodes.new("ShaderNodeTexImage")
        tx.image = bpy.data.images.load(os.path.join(Q_SRC, image), check_existing=True)
        if tint_by_vertex:
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
    elif color:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    q_mats[name] = mat
    return mat


def q_tube(bm, pts, radii, sides=6, uv_len=2.0, uv_layer=None):
    """Verjüngte Röhre entlang einer Punktfolge (Blender-Koordinaten, z oben); UV: Winkel x Länge."""
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
    for i in range(len(rings) - 1):
        for k in range(sides):
            quad = [(i, k), (i, (k + 1) % sides), (i + 1, (k + 1) % sides), (i + 1, k)]
            f = bm.faces.new([rings[a][b] for a, b in quad])
            f.smooth = True
            if uv_layer is not None:
                for loop, (a, b), un in zip(f.loops, quad, (k, k + 1, k + 1, k)):
                    loop[uv_layer].uv = (un / sides, lens[a] / uv_len)


def q_blob_crown(blobs, subdiv, rng_, bump=0.22, tint=(1.0, 1.0, 1.0), tile=2.2, shade_lo=0.5):
    """Krone aus verformten (gestauchten) Kugeln: innen liegende Flächen entfallen, Würfelprojektion als UV, Vertexfarbe = Höhenschatten.
    blobs: Liste (Mitte Vector, Radius, (sx, sy, sz)). Rückgabe: bmesh (Blender-Koordinaten)."""
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


def q_lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def q_col_noise(c, rng_, amt=0.15):
    v = 1.0 + rng_.uniform(-amt, amt)
    return tuple(min(1.0, x * v) for x in c)


def q_in_rect(x, z, cx, cz, ang, ha, hb, pad=0.0):
    dx, dz = x - cx, z - cz
    a = dx * math.cos(ang) + dz * math.sin(ang)
    b = -dx * math.sin(ang) + dz * math.cos(ang)
    return abs(a) <= ha + pad and abs(b) <= hb + pad


def q_quad(key, p0, p1, p2, p3, tile=2.0):
    """Beliebiges Viereck (x, z, y) mit UV in Metern / tile."""
    pts = [p0, p1, p2, p3]
    e1 = Vector(p1) - Vector(p0)
    e2 = Vector(p3) - Vector(p0)
    u1, u2 = e1.normalized(), (e2 - e1.normalized() * e2.dot(e1.normalized())).normalized()
    uvs = [((Vector(p) - Vector(p0)).dot(u1) / tile, (Vector(p) - Vector(p0)).dot(u2) / tile) for p in pts]
    return (key, [(p[0], p[1], p[2]) for p in pts], uvs)


class FBuild:
    """Flächen mit Vertexfarben für das Material K_farbe (ohne Textur): Dreiecke und Vielecke in Blender-Koordinaten (x, y, z oben)."""

    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.col = self.bm.loops.layers.float_color.new("Color")

    def poly(self, pts, cols, up=False, out_from=None, inward=False):
        """Fläche anlegen; up: Normale nach oben; out_from: Normale zeigt vom Punkt weg (inward: zum Punkt hin)."""
        vs = [self.bm.verts.new(p) for p in pts]
        try:
            f = self.bm.faces.new(vs)
        except ValueError:
            return None
        f.normal_update()
        if up and f.normal.z < 0:
            f.normal_flip()
        if out_from is not None:
            d = f.calc_center_median() - Vector(out_from)
            if (f.normal.dot(d) < 0) != inward:
                f.normal_flip()
        for loop in f.loops:
            c = cols[vs.index(loop.vert)] if isinstance(cols, (list, tuple)) and isinstance(cols[0], (list, tuple)) else cols
            loop[self.uv].uv = (0.0, 0.0)
            loop[self.col] = (c[0] ** 2.2, c[1] ** 2.2, c[2] ** 2.2, 1.0)     # Farben sind sRGB, die Vertexfarbe ist linear
        return f

    def finish(self, key, material_key="farbe", recalc=False):
        if recalc:
            bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        obj = q_bm_object(key, self.bm, [M[material_key]], link=False)
        return q_register(key, obj)




# ---------------------------------------------------------------- Gelände
def q_seg_dist(P, a, b):
    ab = np.array(b) - np.array(a)
    t = np.clip(((P - np.array(a)) @ ab) / (float(ab @ ab) + 1e-9), 0, 1)
    return np.sqrt(((P - (np.array(a) + t[:, None] * ab)) ** 2).sum(1))


# ---------------------------------------------------------------- Höhenniveaus (Fassung 2, Bruchkante Ost; docs/dioramen/HOEHEN_PLAN.md 4.1, 7 C1)
# Maßgeblich ist das Geländeraster der Streckendatei ("terrain", wie Circuit.terrain_height): obere Sohle 5,6 m, Dämme der Fahr- und der
# Landerampe, Sohlenweg-Korridor 0. Das Diorama schärft es nur dort, wo die Spielebene ohnehin eine Wand hat: an den unsichtbaren
# Bruchwand-Hindernissen ("collider", mauer, b 0) wird der 2-m-Übergang des Rasters zu einer senkrechten Wand an der Hinderniskante; die
# Dämme bekommen außerhalb ihres ebenen Kamms (Halbbreite + 2,5 m) eine Haufwerkböschung 1 : 1,3; außen an der Fahrrampe (Felswand-
# Hindernisse, h >= 10) bleibt der Boden auf Fahrbahnhöhe und die Felswand Ost steigt 6,5 m neben der Mittellinie an. Innerhalb von
# Halbbreite + 0,8 m einer tieferen Fahrbahn bleibt der Boden auf deren Höhe (Sohlenweg unter dem Sprung).
Q_TER = data.get("terrain", {})
Q_TER_H = np.array(Q_TER["heights"], float).reshape(int(Q_TER["h"]), int(Q_TER["w"])) if Q_TER else None
Q_TG = None                                     # Tangenten der Mittellinie (numpy), in q_levels_plan() gefüllt (der Kern rechnet sie erst nach dem Laden des Moduls)
Q_BASE_TAB = None                               # Höhenprofil je Mittellinienpunkt
Q_FACES = []                                    # Bruchwände: dict(o, a, n, lo, hi, a0, a1, h_lo, h_hi, axis)
Q_HULL = []                                     # konvexe Hülle der Mittellinie (Grubensohle innerhalb)
Q_DAMS = []                                     # (s0, s1, Seiten): Dammabschnitte mit Haufwerkböschung (+1 links, -1 rechts)
Q_EAST = []                                     # (s0, s1, Seite): Außenseite der Fahrrampe mit Felswand Ost


def q_terrain(P):
    """Geländeraster der Streckendatei für viele Punkte (bilinear, am Rand fortgesetzt wie Circuit.terrain_height)."""
    if Q_TER_H is None:
        return np.zeros(len(P))
    cell = float(Q_TER["cell"])
    w, h = Q_TER_H.shape[1], Q_TER_H.shape[0]
    fx = (P[:, 0] - float(Q_TER["origin"][0])) / cell
    fz = (P[:, 1] - float(Q_TER["origin"][1])) / cell
    ix = np.clip(np.floor(fx).astype(int), 0, w - 2)
    iz = np.clip(np.floor(fz).astype(int), 0, h - 2)
    tx = np.clip(fx - ix, 0.0, 1.0)
    tz = np.clip(fz - iz, 0.0, 1.0)
    a = Q_TER_H[iz, ix] + (Q_TER_H[iz, ix + 1] - Q_TER_H[iz, ix]) * tx
    b = Q_TER_H[iz + 1, ix] + (Q_TER_H[iz + 1, ix + 1] - Q_TER_H[iz + 1, ix]) * tx
    return a + (b - a) * tz


def q_track_s(P):
    """Nächster Mittellinienpunkt je Punkt: Streckenanteil s (genau, mit Längsversatz), Seitenabstand (links positiv), Längsversatz."""
    idx, lat = q_nearest_center(P)
    along = ((P - C[idx]) * Q_TG[idx]).sum(1)
    s = (S_OF[idx] + along / TOTAL) % 1.0
    return s, lat, along


def q_base_at(s):
    """Höhenprofil (ohne Schanze) für viele s, aus der Tabelle des Kerns (base_height je 0,5 m) interpoliert."""
    f = (np.asarray(s) % 1.0) * N
    i0 = np.floor(f).astype(int) % N
    t = f - np.floor(f)
    return Q_BASE_TAB[i0] * (1 - t) + Q_BASE_TAB[(i0 + 1) % N] * t


def q_in_window(s, s0, s1, fade=0.006):
    """Weiches Fenster 0..1 über s (zyklisch), Rand fade."""
    d0 = (np.asarray(s) - s0) % 1.0
    span = (s1 - s0) % 1.0
    inside_ = d0 <= span
    e = np.minimum(d0, span - d0)
    return np.where(inside_, np.clip(e / fade, 0.0, 1.0), 0.0)


def q_levels_plan():
    """Bruchwände, Dämme, Felswand Ost und Hülle aus der Streckendatei ableiten (vor dem Boden)."""
    global Q_TG, Q_BASE_TAB
    Q_TG = np.array([[t.x, t.y] for t in tang])
    Q_BASE_TAB = np.array([base_height(float(S_OF[i])) for i in range(N)])
    Q_FACES.clear()
    Q_DAMS.clear()
    Q_EAST.clear()
    Q_HULL.clear()
    pts = [tuple(p) for p in C]
    pts = sorted(set(pts))
    lower, upper = [], []
    cross = lambda o, a, b: (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    Q_HULL.extend(lower[:-1] + upper[:-1])
    if Q_TER_H is None:
        return
    for p in data["props"]:
        if p.get("type") != "collider" or p.get("kind") != "mauer" or bool(p.get("visible", True)):
            continue
        h = float(p.get("h", 0.0))
        rot = math.radians(float(p.get("rot", 0.0)))
        ux, uz = math.cos(rot), math.sin(rot)
        w_, d_ = float(p["w"]), float(p["d"])
        if h >= 10.0:                                          # Felswand Ost (außen an der Fahrrampe)
            s_, lat_, _ = q_track_s(np.array([(p["x"], p["z"])], float))
            Q_EAST.append((float(s_[0]), 1.0 if lat_[0] > 0 else -1.0))
            continue
        if float(p.get("b", 0.0)) > 0.05:
            continue
        # Längsachse = längere Seite; Normale zeigt zur tieferen Seite (Geländeraster 2,3 m beidseits der Achse)
        if w_ >= d_:
            a = np.array([ux, uz]); half_a, half_n = w_ / 2, d_ / 2
        else:
            a = np.array([-uz, ux]); half_a, half_n = d_ / 2, w_ / 2
        n = np.array([-a[1], a[0]])
        o = np.array([p["x"], p["z"]], float)
        tp = q_terrain(np.array([o + n * 2.3, o - n * 2.3]))
        if abs(tp[0] - tp[1]) < 1.5:
            continue
        if tp[0] > tp[1]:
            n = -n                                             # n zeigt zur tiefen Seite
        line = o + n * half_n                                  # Wand an der Hinderniskante zur tiefen Seite
        axis = None
        if abs(n[0]) > 0.999:
            axis = 0
            line[0] = math.floor(line[0] - 1e-6) + 0.5        # auf halbe Meter (Bodenraster 1 m: je ein Knoten beidseits)
        elif abs(n[1]) > 0.999:
            axis = 1
            line[1] = math.floor(line[1] - 1e-6) + 0.5
        # entlang der Achse verlängern, solange das Raster dort eine Stufe hat (Bruchkante läuft über das Hindernis hinaus)
        ext = []
        for sgn in (-1.0, 1.0):
            t = half_a
            while t < 120.0:
                q = line + a * sgn * (t + 1.0)
                tq = q_terrain(np.array([q - n * 2.3, q + n * 2.3]))
                if tq[0] - tq[1] < 1.5 or not (x0 < q[0] < x1 and z0 < q[1] < z1):
                    break
                t += 1.0
            ext.append(t)
        Q_FACES.append({"o": line, "a": a, "n": n, "a0": -ext[0], "a1": ext[1], "axis": axis, "h": h})
    # Dämme: geneigte Abschnitte des Höhenprofils (Fahrrampe, Landerampe), Lücken ausgenommen
    el = data.get("elevation", [])
    for k in range(len(el) - 1):
        s0, h0 = float(el[k][0]), float(el[k][1])
        s1, h1 = float(el[k + 1][0]), float(el[k + 1][1])
        if abs(h1 - h0) < 0.3:
            continue
        for g in data.get("gaps", []):
            if float(g["from"]) <= s0 + 1e-4 < float(g["to"]):
                s0 = float(g["to"])
        Q_DAMS.append((s0, s1))
    print("DIORAMA Höhen: Bruchwände", [(round(float(f["o"][0]), 1), round(float(f["o"][1]), 1), round(f["a0"], 1), round(f["a1"], 1)) for f in Q_FACES],
          "| Dämme", [(round(a_, 4), round(b_, 4)) for a_, b_ in Q_DAMS], "| Felswand Ost", len(Q_EAST))


def q_face_coords(P, f):
    """Längs- und Querkoordinate (quer: positiv zur tiefen Seite) eines Punktfelds zu einer Bruchwand."""
    rel = P - f["o"]
    return rel @ f["a"], rel @ f["n"]


def q_crisp(P, T):
    """Geländeraster mit senkrechten Bruchwänden: im Band ±2,4 m um die Wandlinie gilt die Höhe 2,4 m weiter auf der jeweiligen Seite."""
    T = T.copy()
    for f in Q_FACES:
        al, cr = q_face_coords(P, f)
        band = (al >= f["a0"] - 0.5) & (al <= f["a1"] + 0.5) & (np.abs(cr) < 2.4)
        if not band.any():
            continue
        proj = f["o"] + al[band, None] * f["a"]
        hi = np.maximum(q_terrain(proj - f["n"] * 2.4), q_terrain(proj - f["n"] * 0.6))   # Landelippe: Krone direkt hinter der Kante
        lo = q_terrain(proj + f["n"] * 2.4)
        T[band] = np.where(cr[band] > 0.0, lo, hi)
    return T


def q_east_w(s, lat):
    """Gewicht der Felswand Ost (Außenseite der Fahrrampe) je Punkt."""
    if not Q_EAST:
        return np.zeros(len(s))
    ss = [e[0] for e in Q_EAST]
    side = Q_EAST[0][1]
    s0, s1 = min(ss) - 0.012, max(ss) + 0.012
    return q_in_window(s, s0, s1, 0.012) * (np.sign(lat) == side)


def q_floor(P):
    """Arbeitsebene (m über der Grubensohle): Raster mit Bruchwänden, Dammböschungen, Außenseite der Fahrrampe, Korridore tieferer Äste."""
    T = q_crisp(P, q_terrain(P))
    if not Q_TER:
        return T
    s, lat, along = q_track_s(P)
    base = q_base_at(s)
    alat = np.abs(lat)
    ok = np.abs(along) < 0.75                             # nur neben, nicht vor/hinter dem Abschnitt (Landelippe, Rampenfuß)
    F = T
    for s0, s1 in Q_DAMS:
        w = q_in_window(s, s0, s1, 0.002) * ok
        D = np.clip(base - np.maximum(alat - (HW + 2.5), 0.0) / 1.3, 0.0, None) * w
        F = np.maximum(F, D)
    we = q_east_w(s, lat)
    F = np.where(we > 0.0, np.maximum(F, base * np.minimum(1.0, we * 2.0)), F)
    # Korridor eines deutlich tieferen Asts (Sohlenweg unter dem Sprung, Fuß der Landelippe): Boden auf dessen Höhe. Auf Rampen liegt
    # das Minimum des Kerns (alle Segmente im Umkreis) nur wegen der Steigung tiefer; dort gilt die Ebene selbst.
    floor = branch_floor(P, HW + 0.8)
    return np.where(floor < base - 1.5, np.minimum(F, floor), F)


def q_dam_mask(P):
    """Anteil Haufwerk (Dammböschung) je Punkt: dort Schotter statt Fels."""
    if not Q_TER:
        return np.zeros(len(P))
    s, lat, along = q_track_s(P)
    alat = np.abs(lat)
    out = np.zeros(len(P))
    for s0, s1 in Q_DAMS:
        w = q_in_window(s, s0, s1, 0.004) * (np.abs(along) < 0.75)
        out = np.maximum(out, w * (alat > HW + 0.5) * (alat < HW + 2.5 + 1.3 * 6.0))
    return out


def q_in_hull(P):
    if len(Q_HULL) < 3:
        return inside(P)
    H_ = np.array(Q_HULL)
    a, b = H_, np.roll(H_, -1, axis=0)
    cr = (b[None, :, 0] - a[None, :, 0]) * (P[:, None, 1] - a[None, :, 1]) - (b[None, :, 1] - a[None, :, 1]) * (P[:, None, 0] - a[None, :, 0])
    return (cr >= 0).all(1)


def q_u(P):
    """Abstand zur Grubensohle in Metern (negativ innen): Sohle = Inneres der Strecke (konvexe Hülle; die Strecke kreuzt sich selbst),
    10 m Rand um die Fahrbahn (außen an der Fahrrampe 5 m: Felswand Ost), Flächen um die KI-Modelle."""
    df = Q_DF
    if Q_EAST:
        s, lat, _ = q_track_s(P)
        df = Q_DF - 5.0 * q_east_w(s, lat)
    d = dist_to_center(P) - df
    d = np.where(q_in_hull(P), np.minimum(d, -1.0), d)
    for p in Q_AI:
        r = Q_FLAT.get(p.get("model"))
        if r:
            d = np.minimum(d, np.hypot(P[:, 0] - p["x"], P[:, 1] - p["z"]) - r)
    d = np.minimum(d, q_seg_dist(P, Q_BELT[0], Q_BELT[1]) - Q_BELT[2])
    for sc in data.get("shortcuts", []):                 # Abkürzung: ebene Sohle 9 m beidseits (das Spiel baut sie auf Bodenhöhe)
        pts = sc["path"]
        for p0, p1 in zip(pts, pts[1:]):
            d = np.minimum(d, q_seg_dist(P, p0, p1) - 9.0)
    return d


def q_height(P, u):
    """Bänke über der Arbeitsebene (m): vier Bänke mit weichen Böschungen, Ränder durch Rauschen verzogen, Absätze leicht uneben. Außen an der
    Fahrrampe (Felswand Ost) ist die erste Stufe doppelt so hoch und steiler."""
    x, z = P[:, 0], P[:, 1]
    ramp = np.minimum(1.0, np.maximum(u, 0.0) / 6.0)
    uw = u + ramp * ((q_noise(x, z, 14.0, 3.0) - 0.5) * 3.4 + (q_noise(x, z, 5.0, 9.0) - 0.5) * 1.3)
    we = np.zeros(len(P))
    if Q_EAST:
        s, lat, _ = q_track_s(P)
        we = q_east_w(s, lat)
    h = np.zeros(len(P))
    for k in range(Q_BENCHES):
        rise = Q_RISE * (1.0 + we) if k == 0 else Q_RISE
        slope = Q_SLOPE * (1.0 - 0.45 * we) if k == 0 else Q_SLOPE
        h += rise * q_smooth((uw - (Q_U0 + k * Q_PERIOD)) / slope)
    h += 0.16 * (q_noise(x, z, 3.7, 11.0) - 0.5) * np.minimum(1.0, np.maximum(u, 0.0) / 4.0)
    return h


def q_rel(P):
    """Bodenhöhe über GROUND_Y: Arbeitsebene (Raster der Streckendatei, geschärft) plus Bänke."""
    return q_floor(P) + q_height(P, q_u(P))


def q_lake_sdf(X, Z):
    dx, dz = np.asarray(X) - Q_LAKE["x"], np.asarray(Z) - Q_LAKE["z"]
    a, b = Q_LAKE["w"] / 2.0, Q_LAKE["d"] / 2.0
    ang = np.arctan2(dz / b, dx / a)
    k = 1.0 + 0.10 * np.sin(3 * ang + 0.9) + 0.07 * np.sin(5 * ang + 2.6) + 0.04 * np.sin(8 * ang + 1.1)
    r = np.sqrt((dx / a) ** 2 + (dz / b) ** 2) / k
    return (r - 1.0) * min(a, b) * 1.05


def q_lake_height(X, Z):
    sd = q_lake_sdf(X, Z)
    return -Q_WATER_DEPTH * q_smooth(-sd / Q_LAKE_SLOPE) * (sd < 0.4)


def q_ground_y(x, z):
    """Bodenhöhe an einem Ort (Gelände ohne See)."""
    P = np.array([(x, z)], float)
    return GROUND_Y + float(q_rel(P)[0])


def q_mesh_h(P, extra=0.0):
    """Höhe der Bodennetze: Relief (+ extra), unter der Laufzeit-Fahrbahn höchstens so hoch, wie die Kernprüfung erlaubt (tiefste Basis
    der Äste im Umkreis HW + 0,3 plus ROAD_Y - 0,012). Auf Rampen liegt diese Grenze bis 1 m unter der Fahrbahn (Minimum über alle Segmente
    im Umkreis); die Dammkrone (q_crown_build) deckt dort den Streifen unter der Fahrbahn ab."""
    h = GROUND_Y + q_rel(P) + extra
    return np.minimum(h, branch_floor(P) + ROAD_Y - 0.012)


def q_flat_floor(x, z, r):
    """Steht ein Bauteil (Radius r) ganz auf der ebenen Grubensohle (Höhe 0)? Die alten Bausteine kennen nur GROUND_Y."""
    a = np.array([(x, z)] + [(x + r * math.cos(k * 0.785), z + r * math.sin(k * 0.785)) for k in range(8)], float)
    return float(np.abs(q_rel(a)).max()) < 0.05


# ---------------------------------------------------------------- Planung
def q_plan():
    P = Q_PLAN
    P.clear()
    P["circles"] = []
    P["rects"] = []
    P["clear"] = []
    P["paths"] = []          # Betriebswege: (Punktfolge, Breite)
    P["ruts"] = []           # Fahrspuren schwerer Maschinen: Punktfolgen
    for p in Q_AI:
        m = p.get("model")
        if m == "steinbruch_felswand":
            continue
        x, z = p["x"], p["z"]
        rot = math.radians(p.get("rot", 0.0))
        if "w" in p and "d" in p:
            P["rects"].append((x, z, rot, p["w"] / 2.0, p["d"] / 2.0))
        else:
            r = {"steinbruch_bagger": 2.5, "steinbruch_kipper": 2.5, "steinbruch_brecher": 4.0, "steinbruch_buero": 3.0, "steinbruch_kieshaufen": 3.0}.get(m, 2.0)
            P["circles"].append((x, z, r))
    for sc in data.get("shortcuts", []):
        P["short"] = [tuple(q) for q in sc["path"]]
        P["short_w"] = sc.get("width", 4.0)
    # Betriebswege: Büro -> Bahn, Kipper <-> Bagger <-> Kieshaufen (Schleifen durch die Sohle)
    P["paths"].append(([(-82.0, 5.5), (-77.0, 6.2), (-72.2, 6.0)], 4.5))
    P["paths"].append(([(-30.0, 10.0), (-14.0, 7.5), (4.0, 3.5), (20.0, 0.0), (32.0, 3.0), (40.0, 5.0)], 5.0))
    P["paths"].append(([(-55.0, 10.0), (-44.0, 14.0), (-30.0, 10.0)], 4.5))
    if data.get("rev", 1) >= 2:
        P["paths"].append(([(16.0, -33.0), (34.0, -32.5), (52.0, -33.5), (68.0, -32.0), (78.0, -36.0)], 5.0))   # obere Sohle: Haldenweg zum Brecher
        P["paths"].append(([(4.0, -2.0), (9.0, -4.5), (14.0, -9.0)], 4.0))                                       # Zufahrt zum Pumpensumpf
    else:
        P["paths"].append(([(-12.0, -30.0), (-9.0, -27.0), (-6.0, -23.0)], 4.0))
        P["paths"].append(([(70.0, -30.0), (66.0, -26.0), (62.0, -20.0)], 5.0))
    for pts, w in P["paths"]:
        for off in (-1.15, 1.15):
            P["ruts"].append(q_offset_path(pts, off))


def q_offset_path(pts, off):
    out = []
    for i, p in enumerate(pts):
        a = np.array(pts[max(i - 1, 0)])
        b = np.array(pts[min(i + 1, len(pts) - 1)])
        t = (b - a) / (np.linalg.norm(b - a) + 1e-9)
        out.append((p[0] - t[1] * off, p[1] + t[0] * off))
    return out


def q_catmull(pts, step=0.6):
    """Glatte Kurve durch die Punkte (Catmull-Rom), gleichmäßig abgetastet."""
    P = [np.array(p, float) for p in pts]
    if len(P) < 3:
        return [tuple(p) for p in P]
    ext = [P[0] * 2 - P[1]] + P + [P[-1] * 2 - P[-2]]
    fine = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        n = max(2, int(np.linalg.norm(p2 - p1) / 0.25))
        for k in range(n):
            t = k / n
            fine.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    fine.append(P[-1])
    out, acc = [tuple(fine[0])], 0.0
    for a, b in zip(fine, fine[1:]):
        acc += float(np.linalg.norm(b - a))
        if acc >= step:
            out.append(tuple(b))
            acc = 0.0
    out.append(tuple(fine[-1]))
    return out


def q_path_field(P, paths, wob=0.5):
    out = np.zeros(len(P))
    for pts, width in paths:
        sm = q_catmull(pts)
        for a, b in zip(sm, sm[1:]):
            d = q_seg_dist(P, a, b)
            w = (q_noise(P[:, 0], P[:, 1], 2.3, 5.0) - 0.5) * wob
            out = np.maximum(out, 1.0 - q_smooth((d - width * 0.5 * (1.0 + w)) / 1.2))
    return out


def q_blocked(x, z, r):
    for cx, cz, ang, ha, hb in Q_PLAN["rects"]:
        if q_in_rect(x, z, cx, cz, ang, ha, hb, r):
            return True
    for cx, cz, cr in Q_PLAN["circles"]:
        if (x - cx) ** 2 + (z - cz) ** 2 < (cr + r) ** 2:
            return True
    for cx, cz, cr in Q_SOLIDS:
        if (x - cx) ** 2 + (z - cz) ** 2 < (cr + r) ** 2:
            return True
    return False


def q_solid(x, z, r, height, kind="mauer"):
    Q_SOLIDS.append((x, z, r))
    collide_circle(x, z, r, height, kind)


def q_solid_rect(cx, cz, ang, ha, hb, height, kind="mauer"):
    Q_SOLIDS.append((cx, cz, math.hypot(ha, hb)))
    collide_rect(cx, cz, math.cos(ang), math.sin(ang), ha, hb, height, kind)


# ---------------------------------------------------------------- Boden
def q_fields(X, Z, H, step):
    """Gewichte des Bodens je Punkt: (Helligkeit, Staub, Fels)."""
    P = np.stack([X.ravel(), Z.ravel()], 1)
    shape = X.shape
    dc = dist_to_center(P)
    idx, lat = q_nearest_center(P)
    s = idx / float(N)
    u = q_u(P)
    gz_, gx_ = np.gradient(H, step)
    slope = np.hypot(gx_, gz_).ravel()
    n_big = q_fbm(P[:, 0], P[:, 1], 13.0, 3, 2.0)
    n_mid = q_fbm(P[:, 0], P[:, 1], 3.6, 2, 7.0)
    n_fine = q_noise(P[:, 0], P[:, 1], 1.2, 15.0)
    # Fels: Böschungen und Felsrippen am Rand der Sohle
    rock = q_smooth((slope - 0.32) / 0.5)
    rib = q_smooth((q_fbm(P[:, 0], P[:, 1], 6.0, 2, 33.0) - 0.60) * 9.0) * ((u > -0.5) & (u < 16.0))
    rock = np.clip(np.maximum(rock, rib * 0.9), 0.0, 1.0)
    dam = q_dam_mask(P)
    rock = rock * (1.0 - 0.8 * dam)
    # Staub: Pistenrand (wie die braune Fahrbahn), Betriebswege, Absätze und Windflecken
    dust = 0.85 * (1.0 - q_smooth((dc - (HW + 0.2)) / (1.8 + 2.0 * n_mid)))
    if "short" in Q_PLAN:
        sd_ = np.full(len(P), 99.0)
        pts = Q_PLAN["short"]
        for a, b in zip(pts, pts[1:]):
            sd_ = np.minimum(sd_, q_seg_dist(P, a, b))
        dust = np.maximum(dust, 1.0 - q_smooth((sd_ - (Q_PLAN["short_w"] * 0.5 + 0.2)) / (2.0 + 2.0 * n_mid)))
    dust = np.maximum(dust, 0.92 * q_path_field(P, Q_PLAN["paths"]))
    dust = np.maximum(dust, np.clip(0.30 + 0.9 * (n_mid - 0.5), 0.0, 0.7) * (u > 0.5) * (1.0 - rock))
    dust = np.maximum(dust, q_smooth((n_big - 0.64) * 5.0) * 0.5)
    # Ufer des Sees: feuchter Kalkschlamm (Staub, dunkel)
    sdl = q_lake_sdf(P[:, 0], P[:, 1])
    dust = np.maximum(dust, 1.0 - q_smooth((sdl - 0.2) / (2.2 + 0.8 * n_mid)))
    dust = dust * (1.0 - rock) * (1.0 - 0.7 * dam)
    # Schlammstrecke der Piste und Graben (Lücke): feucht = dunkler
    damp = np.zeros(len(P))
    for zone in data.get("surfaces", []):
        if zone.get("kind") == "mud":
            fade = np.clip(np.minimum((s - zone["from"]) / 0.012, (zone["to"] - s) / 0.012), 0.0, 1.0)
            damp = np.maximum(damp, fade * (1.0 - q_smooth((dc - (HW + 0.3)) / (3.2 + 1.5 * n_mid))))
    for g in data.get("gaps", []):
        fade = np.clip(np.minimum((s - g["from"]) / 0.004, (g["to"] - s) / 0.004), 0.0, 1.0)
        damp = np.maximum(damp, fade * (1.0 - q_smooth((dc - (HW + 0.5)) / 2.0)))
    dust = np.maximum(dust, damp * 0.6 * (1.0 - rock))
    if Q_FACES:
        fl_ = q_floor(P)
        upper = q_smooth((fl_ - 3.5) / 1.5) * (1.0 - rock)
        dust = np.maximum(dust, 0.55 * upper)
        for f in Q_FACES:
            if f["h"] < 4.0:
                continue
            al, cr = q_face_coords(P, f)
            foot = ((al > f["a0"]) & (al < f["a1"]) & (cr > 0.0)) * (1.0 - q_smooth((cr - 0.4) / (2.2 + 1.2 * n_mid)))
            damp = np.maximum(damp, 0.75 * foot)
    else:
        upper = np.zeros(len(P))
    dapple = 0.93 + 0.20 * (n_big - 0.5) + 0.08 * (n_mid - 0.5) + 0.06 * upper
    bright = dapple * (1.0 - 0.38 * damp)
    comp = lambda w: 0.5 + (np.clip(w, 0.0, 1.0) - 0.5) * 0.62
    return bright.reshape(shape), comp(dust).reshape(shape), comp(rock).reshape(shape)


def q_build_ground():
    gx = np.arange(x0, x1 + 0.001, Q_STEP)
    gz = np.arange(z0, z1 + 0.001, Q_STEP)
    X, Z = np.meshgrid(gx, gz)
    P = np.stack([X.ravel(), Z.ravel()], 1)
    H = q_mesh_h(P).reshape(X.shape)
    cxm, czm = (gx[:-1] + gx[1:]) / 2, (gz[:-1] + gz[1:]) / 2
    bx0, bx1 = math.floor(Q_LAKE["x"] - Q_LAKE["w"] / 2 - 4), math.ceil(Q_LAKE["x"] + Q_LAKE["w"] / 2 + 4)
    bz0, bz1 = math.floor(Q_LAKE["z"] - Q_LAKE["d"] / 2 - 4), math.ceil(Q_LAKE["z"] + Q_LAKE["d"] / 2 + 4)
    skip = ((czm[:, None] > bz0) & (czm[:, None] < bz1) & (cxm[None, :] > bx0) & (cxm[None, :] < bx1))
    if Q_PIT:                                                                  # Graben in der Lücke der Fahrbahn: Loch im Netz, Rand als Feinnetz
        px0, px1, pz0, pz1 = Q_PIT["hole"]
        skip = skip | ((czm[:, None] > pz0) & (czm[:, None] < pz1) & (cxm[None, :] > px0) & (cxm[None, :] < px1))
    br, du, ro = q_fields(X, Z, H, Q_STEP)
    COL = np.stack([br, du, ro], -1)
    og = q_grid_mesh_quad("Gelaende", "gelaende", gx, gz, H, COL, skip, tile=4.0, tol_h=0.02, tol_c=0.07)
    print("DIORAMA Bodennetz: senkrechte Bruchwände, verschobene Knoten", q_snap_faces(og))
    objs_ground.append(og)
    if Q_PIT:
        px0, px1, pz0, pz1 = Q_PIT["hole"]
        sx0, sx1, sz0, sz1 = Q_PIT["box"]
        rx = np.arange(px0, px1 + 0.001, 0.5)
        rz = np.arange(pz0, pz1 + 0.001, 0.5)
        RX, RZ = np.meshgrid(rx, rz)
        PR = np.stack([RX.ravel(), RZ.ravel()], 1)
        HR = q_mesh_h(PR).reshape(RX.shape)
        brr, dur, ror = q_fields(RX, RZ, HR, 0.5)
        rcx, rcz = (rx[:-1] + rx[1:]) / 2, (rz[:-1] + rz[1:]) / 2
        pit_cells = (rcz[:, None] > sz0) & (rcz[:, None] < sz1) & (rcx[None, :] > sx0) & (rcx[None, :] < sx1)
        objs_ground.append(q_grid_mesh("Gelaende_Graben", "gelaende", rx, rz, HR, np.stack([brr, dur, ror], -1), pit_cells))
    # See: feiner aufgelöstes Teilnetz mit Mulde
    fx = np.arange(bx0, bx1 + 0.001, 0.5)
    fz = np.arange(bz0, bz1 + 0.001, 0.5)
    FX, FZ = np.meshgrid(fx, fz)
    H2 = q_mesh_h(np.stack([FX.ravel(), FZ.ravel()], 1), q_lake_height(FX, FZ).ravel()).reshape(FX.shape)
    br2, du2, ro2 = q_fields(FX, FZ, H2, 0.5)
    objs_ground.append(q_grid_mesh("Gelaende_See", "gelaende", fx, fz, H2, np.stack([br2, du2, ro2], -1)))
    # Weite: die Ränder des Netzes bis weit hinter den Bildrand fortsetzen (gleiche Höhe und Gewichte wie der Rand)
    far = 160.0
    strips = (
        (np.array([x0 - far, x0]), gz, np.tile(H[:, 0:1], (1, 2)), np.repeat(COL[:, 0:1, :], 2, axis=1)),
        (np.array([x1, x1 + far]), gz, np.tile(H[:, -1:], (1, 2)), np.repeat(COL[:, -1:, :], 2, axis=1)),
        (gx, np.array([z0 - far, z0]), np.tile(H[0:1, :], (2, 1)), np.repeat(COL[0:1, :, :], 2, axis=0)),
        (gx, np.array([z1, z1 + far]), np.tile(H[-1:, :], (2, 1)), np.repeat(COL[-1:, :, :], 2, axis=0)))
    for k, (sx, sz, sh, sc) in enumerate(strips):
        objs_ground.append(q_grid_mesh("Weite_%d" % k, "gelaende", sx, sz, sh, sc, tile=8.0))
    for k, (cx_, cz_, iy, ix) in enumerate(((x0 - far, z0 - far, 0, 0), (x1, z0 - far, 0, -1), (x0 - far, z1, -1, 0), (x1, z1, -1, -1))):
        objs_ground.append(q_grid_mesh("Weite_E%d" % k, "gelaende", np.array([cx_, cx_ + far]), np.array([cz_, cz_ + far]),
                                       np.full((2, 2), H[iy, ix]), np.tile(COL[iy, ix], (2, 2, 1)), tile=8.0))


def q_build_lake_water():
    water_y = GROUND_Y - 0.28
    bx0, bx1 = math.floor(Q_LAKE["x"] - Q_LAKE["w"] / 2 - 4), math.ceil(Q_LAKE["x"] + Q_LAKE["w"] / 2 + 4)
    bz0, bz1 = math.floor(Q_LAKE["z"] - Q_LAKE["d"] / 2 - 4), math.ceil(Q_LAKE["z"] + Q_LAKE["d"] / 2 + 4)
    fx = np.arange(bx0, bx1 + 0.001, 0.5)
    fz = np.arange(bz0, bz1 + 0.001, 0.5)
    FX, FZ = np.meshgrid(fx, fz)
    h = GROUND_Y + q_rel(np.stack([FX.ravel(), FZ.ravel()], 1)).reshape(FX.shape) + q_lake_height(FX, FZ)
    depth = np.clip((water_y - h) / 0.9, 0.0, 1.0)
    parts = []
    for j in range(len(fz) - 1):
        for i in range(len(fx) - 1):
            if h[j:j + 2, i:i + 2].min() >= water_y:
                continue
            quad = [(fx[i], fz[j]), (fx[i + 1], fz[j]), (fx[i + 1], fz[j + 1]), (fx[i], fz[j + 1])][::-1]
            dv = [depth[j, i], depth[j, i + 1], depth[j + 1, i + 1], depth[j + 1, i]][::-1]
            parts.append(("wasser", [(qx, qz, water_y) for qx, qz in quad], [(qx / 6.0, -qz / 6.0) for qx, qz in quad], None,
                          [(float(v), float(v), float(v)) for v in dv]))
    if parts:
        mesh_object("See", parts)


def theme_materials():
    M["gelaende"] = q_vertex_color(material("D_Gelaende", color=(0.5, 0.48, 0.42), rough=0.9))      # Platzhalter: Misch-Shader im Spiel
    # Die Teichtiefe steckt in der Vertexfarbe (Rot, nur das Wasser des Spiels liest sie); das Material selbst bekommt eine dunkle Grundfarbe OHNE
    # Verknüpfung mit der Vertexfarbe: Das Laternenlicht-Zusatzbild (lit_overlay) nimmt Grundfarbe x Vertexfarbe als Albedo, sonst würde das
    # Wasser unter Lampen rot. Der Export schreibt die aktive Vertexfarbe ohnehin als COLOR_0 (vertex_colors "ACTIVE").
    M["wasser"].node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.02, 0.03, 0.03, 1.0)
    M["farbe"] = M["k:farbe"]
    M["q_fels"] = q_tex_material("F_Fels", "fels.jpg", True, 0.95)
    M["q_schotter"] = q_tex_material("F_Schotter", "schotter.jpg", True, 0.95)
    M["q_block"] = q_tex_material("F_Naturstein", "blockstein.jpg", False, 0.85)
    M["q_wellblech"] = q_tex_material("F_Wellblech", "wellblech.jpg", False, 0.6)
    M["q_cont_rot"] = q_tex_material("F_Container_rot", "container_rot.jpg", False, 0.7)
    M["q_cont_blau"] = q_tex_material("F_Container_blau", "container_blau.jpg", False, 0.7)
    M["q_cont_gelb"] = q_tex_material("F_Container_gelb", "container_gelb.jpg", False, 0.7)
    puddle = q_tex_material("F_Pfuetze", None, False, 0.04, color=(0.2, 0.2, 0.2))
    q_vertex_color(puddle)
    puddle.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.04
    M["pfuetze"] = puddle


def theme_ground():
    q_levels_plan()
    q_plan()
    q_pit_plan()
    q_build_ground()
    q_build_lake_water()


Q_SRC = os.path.normpath(os.path.join(PROPS, "..", "dio", "quarry", "quelle"))


def q_report():
    groups = {}
    tris = 0
    for o in scene.objects:
        if o.type == "MESH" and o.data is not None and not o.name.startswith("AOProxy"):
            n = sum(max(1, len(p.vertices) - 2) for p in o.data.polygons)
            tris += n
            m = re.match(r"(Prop_[A-Za-z]+|[A-Za-z]+)", o.name)
            key = m.group(1) if m else o.name
            groups[key] = groups.get(key, 0) + n
    uniq = sum(max(1, len(p.vertices) - 2) for me in bpy.data.meshes if me.users for p in me.polygons)
    print("DIORAMA Dreiecke je Gruppe:", sorted(groups.items(), key=lambda kv: -kv[1])[:14])
    print("DIORAMA Dreiecke (instanziert, ungefähr):", tris, "| verschiedene Netze:", uniq)


def theme_bake_hidden():
    return ["See"]


def theme_layout(layout):
    layout["water_y"] = None
    # Das Laternenlicht-Zusatzbild des Spiels (lit_overlay) nimmt für Wasser die Vertexfarbe (Tiefe in Rot) als Farbe: unter Flutlicht würde der
    # Baggersee rot. Ein dunkler Tönungswert dämpft diesen Zusatz auf einen schwachen Schimmer.
    layout["tints"] = {"D_Wasser": [0.02, 0.03, 0.03]}


# ---------------------------------------------------------------- Bausteine aus Quadern und Röhren (Vertexfarben, K_farbe)
def qV(x, z, h):
    """Punkt in Blender-Koordinaten aus Spielkoordinaten (x, z) und Höhe h."""
    return Vector((x, -z, h))


def q_fb_box(fb, x, z, y0, y1, hx, hz, ang, col, top=None, bottom=None):
    """Quader (Mitte x, z; Unterkante y0, Oberkante y1; halbe Maße hx entlang ang, hz quer) mit nach außen zeigenden Flächen."""
    ca, sa = math.cos(ang), math.sin(ang)
    pts = [(x + ca * a - sa * b, z + sa * a + ca * b) for a, b in ((-hx, -hz), (hx, -hz), (hx, hz), (-hx, hz))]
    cen = qV(x, z, (y0 + y1) / 2)
    for i in range(4):
        p, q = pts[i], pts[(i + 1) % 4]
        fb.poly([qV(p[0], p[1], y0), qV(q[0], q[1], y0), qV(q[0], q[1], y1), qV(p[0], p[1], y1)], col, out_from=cen)
    fb.poly([qV(px, pz, y1) for px, pz in pts], top or col, out_from=cen)
    if bottom is not None:
        fb.poly([qV(px, pz, y0) for px, pz in pts], bottom, out_from=cen)


def q_fb_tube(fb, a, b, r0, r1, sides, col, cap0=None, cap1=None, band=None):
    """Röhre/Kegelstumpf zwischen a und b (je (x, z, h)); cap0/cap1: Farbe der Endflächen (None = offen). band: (t0, t1, Farbe) färbt einen Abschnitt."""
    A, B = qV(*a), qV(*b)
    t = (B - A).normalized()
    up = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
    u = t.cross(up).normalized()
    v = t.cross(u).normalized()
    ra = [A + (u * math.cos(2 * math.pi * k / sides) + v * math.sin(2 * math.pi * k / sides)) * r0 for k in range(sides)]
    rb = [B + (u * math.cos(2 * math.pi * k / sides) + v * math.sin(2 * math.pi * k / sides)) * r1 for k in range(sides)]
    mid = (A + B) / 2
    for k in range(sides):
        k2 = (k + 1) % sides
        c = col
        fb.poly([ra[k], ra[k2], rb[k2], rb[k]], c, out_from=mid)
    if cap0 is not None:
        fb.poly(ra, cap0, out_from=B)
    if cap1 is not None:
        fb.poly(rb, cap1, out_from=A)


def q_fb_tube_banded(fb, a, b, r, sides, cols, splits):
    """Röhre aus Abschnitten mit unterschiedlichen Farben (splits: Anteile 0..1 der Grenzen, cols: eine Farbe mehr)."""
    A = np.array(a, float)
    B = np.array(b, float)
    ts = [0.0] + list(splits) + [1.0]
    for i in range(len(ts) - 1):
        q_fb_tube(fb, tuple(A + (B - A) * ts[i]), tuple(A + (B - A) * ts[i + 1]), r, r, sides, cols[i])


def q_local(x, z, ang):
    ca, sa = math.cos(ang), math.sin(ang)
    return lambda a, b: (x + ca * a - sa * b, z + sa * a + ca * b)


def q_srgb(c):
    return tuple(v ** 2.2 for v in c)


# ---------------------------------------------------------------- Wasserwagen, Dieseltank, Container, Naturstein
def q_water_bowser(x, z, ang):
    """Wasserwagen (Anhänger mit gelbem Tank, zwei Achsen, Zugdeichsel, Sprühbalken hinten, Mannloch) zum Befeuchten der Fahrwege."""
    fb = FBuild()
    L = q_local(x, z, ang)
    yellow, dark = (0.86, 0.64, 0.08), (0.10, 0.10, 0.11)
    steel, rubber, rim = (0.45, 0.47, 0.50), (0.07, 0.07, 0.075), (0.60, 0.50, 0.12)
    # Rahmen und Tank
    px, pz = L(0.0, 0.0)
    q_fb_box(fb, px, pz, 0.62, 0.78, 2.35, 0.62, ang, steel)
    for a in (-1.45, 1.35):                                                       # Tanksättel
        sx, sz = L(a, 0.0)
        q_fb_box(fb, sx, sz, 0.78, 1.05, 0.12, 0.7, ang, steel)
    a0, a1 = L(-2.2, 0.0), L(2.2, 0.0)
    q_fb_tube(fb, (a0[0], a0[1], 1.82), (a1[0], a1[1], 1.82), 0.82, 0.82, 20, yellow, cap0=(0.70, 0.50, 0.06), cap1=(0.70, 0.50, 0.06))
    for t_ in (-0.9, 0.0, 0.9):                                                   # Spannbänder
        b0, b1 = L(t_ - 0.04, 0.0), L(t_ + 0.04, 0.0)
        q_fb_tube(fb, (b0[0], b0[1], 1.82), (b1[0], b1[1], 1.82), 0.835, 0.835, 20, (0.18, 0.18, 0.19))
    mx, mz = L(0.2, 0.0)
    q_fb_tube(fb, (mx, mz, 2.60), (mx, mz, 2.72), 0.27, 0.25, 12, steel, cap1=(0.38, 0.40, 0.43))      # Mannloch
    # Achsen und Räder (Radachse quer zur Fahrtrichtung)
    for au in (-0.85, 0.35):
        l0, l1 = L(au, -0.98), L(au, 0.98)
        q_fb_tube(fb, (l0[0], l0[1], 0.55), (l1[0], l1[1], 0.55), 0.06, 0.06, 8, dark)
        for side in (-1, 1):
            w0, w1 = L(au, side * 0.78), L(au, side * 1.10)
            q_fb_tube(fb, (w0[0], w0[1], 0.55), (w1[0], w1[1], 0.55), 0.55, 0.55, 18, rubber,
                      cap0=rim if side < 0 else None, cap1=rim if side > 0 else None)
            f0, f1 = L(au - 0.62, side * 0.74), L(au + 0.62, side * 0.74)                 # Kotflügel
            q_fb_box(fb, *L(au, side * 0.93), 1.00, 1.05, 0.66, 0.24, ang, yellow)
    # Zugdeichsel (A-Form) mit Zugöse
    d0, d1, d2 = L(1.8, -0.55), L(1.8, 0.55), L(3.55, 0.0)
    q_fb_tube(fb, (d0[0], d0[1], 0.66), (d2[0], d2[1], 0.62), 0.045, 0.04, 6, dark)
    q_fb_tube(fb, (d1[0], d1[1], 0.66), (d2[0], d2[1], 0.62), 0.045, 0.04, 6, dark)
    e0, e1 = L(3.5, 0.0), L(3.7, 0.0)
    q_fb_tube(fb, (e0[0], e0[1], 0.62), (e1[0], e1[1], 0.62), 0.12, 0.12, 10, dark)
    # Stützfuß vorn
    s0 = L(2.4, 0.0)
    q_fb_tube(fb, (s0[0], s0[1], 0.0), (s0[0], s0[1], 0.6), 0.04, 0.04, 6, steel, cap0=dark)
    # Sprühbalken hinten mit Düsen und Anschlussstutzen
    r0, r1 = L(-2.45, -0.95), L(-2.45, 0.95)
    q_fb_tube(fb, (r0[0], r0[1], 0.70), (r1[0], r1[1], 0.70), 0.05, 0.05, 8, steel)
    for k in range(7):
        n0 = L(-2.45, -0.8 + k * 0.27)
        q_fb_tube(fb, (n0[0], n0[1], 0.70), (n0[0] - math.cos(ang) * 0.12, n0[1] - math.sin(ang) * 0.12, 0.62), 0.03, 0.012, 6, (0.2, 0.2, 0.21))
    o = q_bm_object("Wasserwagen", fb.bm, [M["farbe"]])
    q_solid_rect(*L(0.6, 0.0), ang, 3.1, 1.15, 2.7, "mauer")
    return o


def q_fuel_station(x, z, ang):
    """Dieseltankstelle der Grube: liegender Stahltank auf Sätteln in einer Auffangwanne aus Beton, Zapfsäule, Poller, Entlüftung."""
    fb = FBuild()
    L = q_local(x, z, ang)
    conc, conc_d = (0.62, 0.61, 0.58), (0.50, 0.49, 0.47)
    tank, tank_band, yellow = (0.30, 0.38, 0.46), (0.80, 0.18, 0.12), (0.92, 0.72, 0.08)
    hx, hz = 3.2, 1.9
    cx, cz = L(0.0, 0.0)
    q_fb_box(fb, cx, cz, GROUND_Y - 0.02, GROUND_Y + 0.08, hx, hz, ang, conc_d, top=conc)                            # Wannenboden
    for sgn in (-1, 1):
        wx, wz = L(0.0, sgn * (hz - 0.12))
        q_fb_box(fb, wx, wz, GROUND_Y, GROUND_Y + 0.42, hx, 0.12, ang, conc, top=conc_d)
        wx, wz = L(sgn * (hx - 0.12), 0.0)
        q_fb_box(fb, wx, wz, GROUND_Y, GROUND_Y + 0.42, 0.12, hz - 0.2, ang, conc, top=conc_d)
    for a in (-1.5, 1.5):                                                                                          # Sättel
        sx, sz = L(a, 0.0)
        q_fb_box(fb, sx, sz, GROUND_Y + 0.08, GROUND_Y + 0.55, 0.14, 0.72, ang, (0.25, 0.26, 0.28))
    a0, a1 = L(-2.2, 0.0), L(2.2, 0.0)
    yy = GROUND_Y + 1.38
    q_fb_tube(fb, (a0[0], a0[1], yy), (a1[0], a1[1], yy), 0.82, 0.82, 22, tank, cap0=(0.26, 0.33, 0.40), cap1=(0.26, 0.33, 0.40))
    q_fb_tube(fb, (L(-0.2, 0)[0], L(-0.2, 0)[1], yy), (L(0.35, 0)[0], L(0.35, 0)[1], yy), 0.835, 0.835, 22, tank_band)   # roter Warnring
    m0 = L(-0.9, 0.0)
    q_fb_tube(fb, (m0[0], m0[1], yy + 0.78), (m0[0], m0[1], yy + 0.95), 0.28, 0.26, 12, (0.55, 0.57, 0.60), cap1=(0.42, 0.44, 0.47))
    v0 = L(1.7, 0.0)
    q_fb_tube(fb, (v0[0], v0[1], yy + 0.7), (v0[0], v0[1], yy + 1.8), 0.04, 0.04, 6, (0.45, 0.46, 0.48), cap1=(0.3, 0.3, 0.3))    # Entlüftungsrohr
    # Zapfsäule mit Zapfhahn
    px, pz = L(0.6, 2.7)
    q_fb_box(fb, px, pz, GROUND_Y, GROUND_Y + 1.5, 0.28, 0.2, ang + math.pi / 2, yellow, top=(0.8, 0.62, 0.06))
    fx_, fz_ = L(0.6, 2.5)
    q_fb_box(fb, fx_, fz_, GROUND_Y + 1.05, GROUND_Y + 1.25, 0.1, 0.12, ang + math.pi / 2, (0.12, 0.12, 0.13))
    q_fb_tube(fb, (px, pz, GROUND_Y + 1.1), (L(1.5, 2.9)[0], L(1.5, 2.9)[1], GROUND_Y + 0.15), 0.025, 0.025, 6, (0.08, 0.08, 0.09))   # Schlauch
    # Anfahrschutz: gelb-schwarze Poller an den Ecken
    for a, b in ((-hx - 0.4, -hz - 0.4), (hx + 0.4, -hz - 0.4), (hx + 0.4, hz + 0.4), (-hx - 0.4, hz + 0.4)):
        bx, bz = L(a, b)
        q_fb_tube(fb, (bx, bz, GROUND_Y), (bx, bz, GROUND_Y + 0.5), 0.09, 0.09, 8, yellow)
        q_fb_tube(fb, (bx, bz, GROUND_Y + 0.5), (bx, bz, GROUND_Y + 1.0), 0.09, 0.09, 8, (0.10, 0.10, 0.10), cap1=(0.10, 0.10, 0.10))
    o = q_bm_object("Tankstelle", fb.bm, [M["farbe"]])
    q_solid_rect(cx, cz, ang, hx + 0.5, hz + 0.6, 1.6, "mauer")
    return o


def q_box_tex(key, x, z, y0, y1, hx, hz, ang, tile=2.0, rotate_tex=False):
    """Quader mit Textur (Kacheln in Metern): Flächenliste für mesh_objects. Rippen der Container laufen senkrecht."""
    ca, sa = math.cos(ang), math.sin(ang)
    pts = [(x + ca * a - sa * b, z + sa * a + ca * b) for a, b in ((-hx, -hz), (hx, -hz), (hx, hz), (-hx, hz))]
    parts = []
    for i in range(4):
        p, q = pts[i], pts[(i + 1) % 4]
        ln = math.hypot(q[0] - p[0], q[1] - p[1])
        nx_, nz_ = (q[1] - p[1]) / ln, -(q[0] - p[0]) / ln                          # Außenseite (rechts der Laufrichtung in Spielkoordinaten)
        parts.append((key, [(p[0], p[1], y0), (q[0], q[1], y0), (q[0], q[1], y1), (p[0], p[1], y1)],
                      [(0, 0), (ln / tile, 0), (ln / tile, (y1 - y0) / tile), (0, (y1 - y0) / tile)], (nx_, nz_)))
    parts.append((key, [(px, pz, y1) for px, pz in pts], [(px / tile, pz / tile) for px, pz in pts]))
    return parts


def q_container(x, z, ang, kinds=("rot",), door_end=1):
    """Frachtcontainer 6,06 x 2,44 x 2,59 m (Wellblech-Texturen), auf Wunsch gestapelt; Türseite mit Riegelstangen, Eckbeschläge."""
    parts, fb = [], FBuild()
    L = q_local(x, z, ang)
    for level, kind in enumerate(kinds):
        y0 = GROUND_Y - 0.02 + level * 2.59
        parts += q_box_tex("q_cont_" + kind, x, z, y0, y0 + 2.59, 3.03, 1.22, ang, 2.0)
        for a in (-3.03, 3.03):                                                     # Eckbeschläge
            for b in (-1.22, 1.22):
                cx_, cz_ = L(a * 0.995, b * 0.995)
                q_fb_box(fb, cx_, cz_, y0, y0 + 0.16, 0.09, 0.09, ang, (0.12, 0.12, 0.13))
                q_fb_box(fb, cx_, cz_, y0 + 2.43, y0 + 2.59, 0.09, 0.09, ang, (0.12, 0.12, 0.13))
        for b in (-0.9, -0.3, 0.3, 0.9):                                            # Türriegel an der Stirnseite
            tx, tz = L(door_end * 3.06, b)
            q_fb_box(fb, tx, tz, y0 + 0.2, y0 + 2.4, 0.02, 0.025, ang, (0.55, 0.56, 0.58))
    mesh_objects("Container", parts)
    q_bm_object("Container_Beschlaege", fb.bm, [M["farbe"]])
    q_solid_rect(x, z, ang, 3.1, 1.28, 2.6 * len(kinds), "mauer")


def q_cut_block_stack(x, z, ang, cols=3, rows=2, layers=2, seed=1):
    """Gesägte Natursteinblöcke (1,6 x 0,9 x 0,8 m) in Reihen gestapelt; leicht versetzt, Holzunterleger."""
    parts, fb = [], FBuild()
    r = random.Random(seed)
    L = q_local(x, z, ang)
    bw, bd, bh = 1.6, 0.95, 0.82
    for lay in range(layers):
        for i in range(cols):
            for j in range(rows):
                a = (i - (cols - 1) / 2) * (bw + 0.12) + r.uniform(-0.06, 0.06)
                b = (j - (rows - 1) / 2) * (bd + 0.14) + r.uniform(-0.05, 0.05)
                cx_, cz_ = L(a, b)
                y0 = GROUND_Y + 0.1 + lay * (bh + 0.12)
                parts += q_box_tex("q_block", cx_, cz_, y0, y0 + bh, bw / 2, bd / 2, ang + r.uniform(-0.03, 0.03), 1.5)
                if lay == 0:
                    for off in (-0.55, 0.55):                                      # Kanthölzer
                        ux_, uz_ = L(a + off, b)
                        q_fb_box(fb, ux_, uz_, GROUND_Y - 0.02, GROUND_Y + 0.11, 0.07, bd / 2 + 0.1, ang, (0.52, 0.40, 0.26))
    mesh_objects("Natursteinblocks", parts)
    q_bm_object("Natursteinblocks_Holz", fb.bm, [M["farbe"]])
    q_solid_rect(x, z, ang, cols * (bw + 0.12) / 2 + 0.1, rows * (bd + 0.14) / 2 + 0.1, layers * (bh + 0.12), "mauer")


def q_tire(x, z, ang, r=1.05, width=0.85):
    """Riesenreifen eines Muldenkippers (Prallschutz): schwarzer Wulst, Felge in Grau-Gelb; steht aufrecht, Achse quer zu ang."""
    fb = FBuild()
    rubber, hub = (0.06, 0.06, 0.065), (0.55, 0.46, 0.16)
    ca, sa = -math.sin(ang), math.cos(ang)
    p0 = (x - ca * width / 2, z - sa * width / 2, GROUND_Y + r)
    p1 = (x + ca * width / 2, z + sa * width / 2, GROUND_Y + r)
    q_fb_tube(fb, p0, p1, r, r, 22, rubber)
    q_fb_tube(fb, (p0[0] - ca * 0.01, p0[1] - sa * 0.01, p0[2]), (p0[0] + ca * 0.03, p0[1] + sa * 0.03, p0[2]), r * 0.55, r * 0.5, 18, hub, cap0=hub, cap1=hub)
    q_fb_tube(fb, (p1[0] + ca * 0.01, p1[1] + sa * 0.01, p1[2]), (p1[0] - ca * 0.03, p1[1] - sa * 0.03, p1[2]), r * 0.55, r * 0.5, 18, hub, cap0=hub, cap1=hub)
    q_bm_object("Reifen", fb.bm, [M["farbe"]])


def q_barrel(fb, x, z, col):
    q_fb_tube(fb, (x, z, GROUND_Y), (x, z, GROUND_Y + 0.88), 0.29, 0.29, 12, col, cap1=tuple(min(1.0, c * 1.2) for c in col))
    for hh in (0.18, 0.44, 0.70):
        q_fb_tube(fb, (x, z, GROUND_Y + hh), (x, z, GROUND_Y + hh + 0.03), 0.3, 0.3, 12, tuple(c * 0.75 for c in col))


def q_barrels(x, z, n=5, seed=1):
    fb = FBuild()
    r = random.Random(seed)
    palette = [(0.70, 0.12, 0.10), (0.12, 0.28, 0.58), (0.20, 0.42, 0.20), (0.82, 0.62, 0.08), (0.45, 0.46, 0.48)]
    pos = []
    for i in range(n):
        for tries in range(10):
            bx, bz = x + r.uniform(-0.9, 0.9), z + r.uniform(-0.7, 0.7)
            if all(math.hypot(bx - px, bz - pz) > 0.64 for px, pz in pos):
                pos.append((bx, bz))
                q_barrel(fb, bx, bz, r.choice(palette))
                break
    q_bm_object("Fass_Gruppe", fb.bm, [M["farbe"]])
    q_solid(x, z, 1.1, 0.9, "mauer")


def q_pipes(x, z, ang):
    """Betonrohre (Durchlass für den Graben): drei Rohre liegend, zwei unten und eines obenauf; Öffnungen dunkel."""
    fb = FBuild()
    L = q_local(x, z, ang)
    conc, dark = (0.64, 0.63, 0.60), (0.08, 0.08, 0.08)
    R_, ln = 0.68, 2.4
    ca, sa = math.cos(ang), math.sin(ang)
    for (b_, h) in ((-0.72, 0.0), (0.72, 0.0), (0.0, 1.1)):
        a0, a1 = L(-ln / 2, b_), L(ln / 2, b_)
        yy = GROUND_Y + R_ + h
        q_fb_tube(fb, (a0[0], a0[1], yy), (a1[0], a1[1], yy), R_, R_, 20, conc)
        q_fb_tube(fb, (a0[0] + ca * 0.02, a0[1] + sa * 0.02, yy), (a0[0] + ca * 0.12, a0[1] + sa * 0.12, yy), R_ * 0.8, R_ * 0.8, 18, dark, cap0=dark)
        q_fb_tube(fb, (a1[0] - ca * 0.02, a1[1] - sa * 0.02, yy), (a1[0] - ca * 0.12, a1[1] - sa * 0.12, yy), R_ * 0.8, R_ * 0.8, 18, dark, cap0=dark)
    q_bm_object("Betonrohre", fb.bm, [M["farbe"]])
    q_solid_rect(x, z, ang, ln / 2 + 0.1, 1.4, 2.4, "mauer")


def q_sign(x, z, ang, kind="warn"):
    """Dreieckiges Warnschild (rot umrandet, weiß, schwarzes Ausrufezeichen bzw. fallende Steine) auf einem Stahlmast; blickt in Richtung ang."""
    fb = FBuild()
    f_ = (math.cos(ang), math.sin(ang))
    side = (-math.sin(ang), math.cos(ang))
    steel, red, white, black = (0.58, 0.60, 0.62), (0.78, 0.07, 0.06), (0.96, 0.95, 0.92), (0.08, 0.08, 0.08)
    gy = q_ground_y(x, z)
    q_fb_tube(fb, (x, z, gy - 0.05), (x, z, gy + 2.35), 0.035, 0.035, 8, steel, cap1=steel)
    base_h = gy + 1.35
    cx_, cz_ = x + f_[0] * 0.05, z + f_[1] * 0.05

    def tri(scale, h0, col, off):
        s_ = 0.5 * scale
        pts = [(cx_ + f_[0] * off - side[0] * s_, cz_ + f_[1] * off - side[1] * s_, base_h + h0),
               (cx_ + f_[0] * off + side[0] * s_, cz_ + f_[1] * off + side[1] * s_, base_h + h0),
               (cx_ + f_[0] * off, cz_ + f_[1] * off, base_h + h0 + scale * 0.866)]
        fb.poly([qV(*p) for p in pts], col, out_from=qV(x - f_[0], z - f_[1], base_h + 0.4), inward=False)
    tri(0.90, 0.0, red, 0.000)
    tri(0.66, 0.085, white, 0.004)
    # Symbol
    def bar(a0, a1, h0, h1, col, off):
        pts = [(cx_ + f_[0] * off + side[0] * a0, cz_ + f_[1] * off + side[1] * a0, base_h + h0), (cx_ + f_[0] * off + side[0] * a1, cz_ + f_[1] * off + side[1] * a1, base_h + h0),
               (cx_ + f_[0] * off + side[0] * a1, cz_ + f_[1] * off + side[1] * a1, base_h + h1), (cx_ + f_[0] * off + side[0] * a0, cz_ + f_[1] * off + side[1] * a0, base_h + h1)]
        fb.poly([qV(*p) for p in pts], col, out_from=qV(x - f_[0], z - f_[1], base_h + 0.4))
    if kind == "warn":
        bar(-0.035, 0.035, 0.26, 0.52, black, 0.008)
        bar(-0.035, 0.035, 0.17, 0.23, black, 0.008)
    else:                                                       # Steinschlag: Hang mit drei fallenden Brocken
        bar(-0.22, 0.22, 0.16, 0.20, black, 0.008)
        for a0, h0 in ((-0.12, 0.32), (0.02, 0.26), (0.10, 0.42)):
            bar(a0, a0 + 0.07, h0, h0 + 0.07, black, 0.008)
    q_bm_object("Warnschild", fb.bm, [M["farbe"]])
    q_solid(x, z, 0.1, 2.3, "mast")


def q_barrier(x, z, ang, length=2.3, lamp=True):
    """Baustellen-Absperrschranke nach Art der Straßenbaustellen: zwei rot-weiß gefelderte Bretter, senkrechte Latten, Pfosten, Gummifüße quer
    zur Reihe, rote Warnleuchte (blinkt dämmerungs- und nachts)."""
    g = Frame((x, z), (math.cos(ang), math.sin(ang)), (-math.sin(ang), math.cos(ang)))
    yb = q_ground_y(x, z) + 0.004
    parts = []
    a0, a1 = -length / 2, length / 2
    for a in (a0 + 0.2, a1 - 0.2):
        parts += box(g, "gummi", a - 0.07, a + 0.07, -0.34, 0.34, yb, yb + 0.09)
    for a in (a0 + 0.05, a1 - 0.05):
        parts += box(g, "weiss", a - 0.035, a + 0.035, -0.035, 0.035, yb + 0.09, yb + 1.02)
    i0, i1 = a0 + 0.09, a1 - 0.09
    n = 7
    w = (i1 - i0) / n
    for (y0, y1), phase in (((0.76, 1.02), 0), ((0.48, 0.70), 1)):
        parts += box(g, "weiss", i0, i1, -0.02, 0.02, yb + y0, yb + y1)
        for i in range(n):
            if (i + phase) % 2 == 0:
                parts += box(g, "rot", i0 + i * w + 0.012, i0 + (i + 1) * w - 0.012, -0.024, 0.024, yb + y0 + 0.025, yb + y1 - 0.025)
    ns = 7
    ws = (i1 - i0) / (2 * ns - 1)
    for i in range(ns):
        parts += box(g, "weiss", i0 + 2 * i * ws, i0 + (2 * i + 1) * ws, -0.015, 0.015, yb + 0.14, yb + 0.46)
    if lamp:
        parts += post(g.pt(a0 + 0.05, 0.0), 0.09, yb + 1.02, yb + 1.18, "k:lampe_rot", "k:lampe_rot", cap_h=0.05)
    mesh_objects("Absperrschranke", parts)
    c = g.pt(0.0, 0.0)
    collide_rect(c.x, c.y, g.u.x, g.u.y, length / 2, 0.3, 1.1, "absperrung")
    Q_SOLIDS.append((c.x, c.y, length / 2))


# ---------------------------------------------------------------- Findlinge, Halden
def q_boulder(seed):
    """Kantiger Felsbrocken (verformte, flach schattierte Kugel mit Kalkstein-Textur); Fuß im Ursprung, Größe etwa 1 m."""
    key = "fels%d" % seed
    if key in LIB:
        return key
    r = random.Random(seed * 37 + 5)
    bm = bmesh.new()
    sc3 = (1.0, r.uniform(0.72, 1.0), r.uniform(0.55, 0.85))
    res = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=0.5, matrix=Matrix.Diagonal((sc3[0], sc3[1], sc3[2], 1.0)), calc_uvs=False)
    off = Vector((seed * 3.1, 1.7, 5.3))
    for v in res["verts"]:
        n = v.co.normalized()
        v.co += n * (noise.noise(v.co * 2.0 + off) * 0.30 + noise.noise(v.co * 5.5 + off) * 0.07)
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
            loop[uv].uv = (u / 1.1, w / 1.1)
            sh = (0.55 + 0.45 * min(1.0, max(0.0, p.z) / max(zmax, 1e-3))) * tone
            loop[col] = (sh, sh * 0.99, sh * 0.96, 1.0)
    obj = q_bm_object(key, bm, [M["q_fels"]], link=False)
    return q_register(key, obj)


def q_heap(seed):
    """Schüttkegel (Halde) mit rauer Oberfläche, Radius 1, Höhe 0,46; Schotter-Textur, Vertexfarbe = Materialton."""
    key = "halde%d" % seed
    if key in LIB:
        return key
    r = random.Random(seed * 11 + 3)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    col = bm.loops.layers.float_color.new("Color")
    rings, seg = 7, 22
    tones = [(0.95, 0.93, 0.88), (1.0, 0.92, 0.72), (0.78, 0.76, 0.74), (1.0, 1.0, 0.97)]
    tone = tones[seed % len(tones)]
    top = bm.verts.new((0.0, 0.0, 0.46))
    grid = []
    for i in range(1, rings + 1):
        rr = i / rings
        row = []
        for k in range(seg):
            th = 2 * math.pi * k / seg
            jitter = 1.0 + 0.12 * noise.noise(Vector((math.cos(th) * 1.5 + seed, math.sin(th) * 1.5, rr * 2.0)))
            rad = rr * jitter
            h = 0.46 * max(0.0, 1.0 - rr ** 1.7) ** 1.15
            h *= 1.0 + 0.16 * noise.noise(Vector((math.cos(th) * 2.8, math.sin(th) * 2.8, rr * 3.0 + seed)))
            h += 0.05 * noise.noise(Vector((math.cos(th) * 7.0 + 3, math.sin(th) * 7.0, rr * 9.0 + seed))) * (1.0 - rr)
            row.append(bm.verts.new((math.cos(th) * rad, math.sin(th) * rad, h - (0.05 if i == rings else 0.0))))
        grid.append(row)
    faces = []
    for k in range(seg):
        faces.append(bm.faces.new([top, grid[0][(k + 1) % seg], grid[0][k]]))
    for i in range(rings - 1):
        for k in range(seg):
            k2 = (k + 1) % seg
            faces.append(bm.faces.new([grid[i][k], grid[i][k2], grid[i + 1][k2], grid[i + 1][k]]))
    for f in faces:
        f.smooth = True
        f.normal_update()
        if f.normal.z < 0:
            f.normal_flip()
        for loop in f.loops:
            p = loop.vert.co
            loop[uv].uv = (p.x * 2.2, p.y * 2.2)
            sh = 0.62 + 0.55 * (p.z / 0.46) + r.uniform(-0.10, 0.10)
            loop[col] = (min(1, tone[0] * sh), min(1, tone[1] * sh), min(1, tone[2] * sh), 1.0)
    obj = q_bm_object(key, bm, [M["q_schotter"]], link=False)
    return q_register(key, obj)


# ---------------------------------------------------------------- Linien am Boden: Fahrspuren, Pfützen
def q_ribbon(fb, pts, width, y_off, col_a, col_b, fade=2.0, pattern=0.0):
    """Band entlang einer Punktfolge dicht über dem Boden; Farbe geht an den Enden von col_b (hell) nach col_a. pattern > 0: Profilstollen
    (abwechselnd hellere Abschnitte dieser Länge in m)."""
    n = len(pts)
    if n < 2:
        return
    tot = [0.0]
    for a, b in zip(pts, pts[1:]):
        tot.append(tot[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    L_ = tot[-1]
    rows = []
    for i, p in enumerate(pts):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, n - 1)]
        t = ((b[0] - a[0]), (b[1] - a[1]))
        ln = math.hypot(*t) or 1.0
        nx_, nz_ = -t[1] / ln, t[0] / ln
        y = q_ground_y(p[0], p[1]) + y_off
        e = min(1.0, min(tot[i], L_ - tot[i]) / fade)
        c = tuple(col_b[k] + (col_a[k] - col_b[k]) * e for k in range(3))
        if pattern > 0 and int(tot[i] / pattern) % 2 == 1:
            c = tuple(col_b[k] + (c[k] - col_b[k]) * 0.72 for k in range(3))
        rows.append(((p[0] + nx_ * width / 2, p[1] + nz_ * width / 2, y), (p[0] - nx_ * width / 2, p[1] - nz_ * width / 2, y), c))
    for i in range(n - 1):
        a, b = rows[i], rows[i + 1]
        fb.poly([qV(*a[0]), qV(*b[0]), qV(*b[1]), qV(*a[1])], [a[2], b[2], b[2], a[2]], up=True)


def q_ruts():
    """Fahrspuren schwerer Maschinen entlang der Betriebswege: zwei dunkle Bänder mit Profilstollen und verlaufenden Enden."""
    fb = FBuild()
    base, light = (0.36, 0.32, 0.27), (0.60, 0.56, 0.49)
    for pts in Q_PLAN["ruts"]:
        sm = q_catmull(pts, 0.32)
        q_ribbon(fb, sm, 0.55, 0.012, base, light, 3.0, pattern=0.32)
    q_bm_object("Fahrspuren", fb.bm, [M["farbe"]])


def q_puddles():
    """Wasserpfützen (grau, spiegelnd) in den Fahrspuren, am Graben und in Senken der Sohle."""
    r = random.Random(31)
    parts = []
    spots = []
    for pts, w in Q_PLAN["paths"]:
        sm = q_catmull(pts, 1.0)
        for i in range(3, len(sm) - 3, r.randint(5, 9)):
            if r.random() < 0.5:
                a, b = sm[i], sm[i + 1]
                t = (b[0] - a[0], b[1] - a[1])
                ln = math.hypot(*t) or 1.0
                off = r.uniform(-1.2, 1.2)
                spots.append((a[0] - t[1] / ln * off, a[1] + t[0] / ln * off, math.atan2(t[1], t[0])))
    if not Q_PIT:                                                        # ohne eigenen Graben: Pfützen in der Lücke
        for g in [g_ for g_ in data.get("gaps", []) if base_height(float(g_["from"])) < 0.5]:
            i = int(((g["from"] + g["to"]) / 2) * N)
            c = center[i]
            for off in (-1.6, 0.4, 1.9):
                spots.append((c.x + 0.4, c.y + off, math.atan2(tang[i].y, tang[i].x)))
    mid = tuple(v ** 2.2 for v in (0.20, 0.22, 0.24))
    edge = tuple(v ** 2.2 for v in (0.30, 0.27, 0.22))
    n_p = 0
    for x, z, ang in spots:
        a_, b_ = r.uniform(0.9, 2.2), r.uniform(0.6, 1.3)
        if q_blocked(x, z, 0.4):
            continue
        ring = []
        for k in range(14):
            th = 2 * math.pi * k / 14
            rr_ = r.uniform(0.84, 1.12)
            ring.append((x + math.cos(ang) * math.cos(th) * a_ * rr_ - math.sin(ang) * math.sin(th) * b_ * rr_,
                         z + math.sin(ang) * math.cos(th) * a_ * rr_ + math.cos(ang) * math.sin(th) * b_ * rr_))
        y = q_ground_y(x, z) + 0.016
        for k in range(14):
            k2 = (k + 1) % 14
            parts.append(("pfuetze", [(x, z, y), (ring[k][0], ring[k][1], y), (ring[k2][0], ring[k2][1], y)][::-1],
                          [(0, 0), (1, 0), (1, 1)], None, [mid, edge, edge][::-1]))
        n_p += 1
    if parts:
        mesh_object("Pfuetzen", parts)
    print("DIORAMA Pfützen:", n_p)


# ---------------------------------------------------------------- Zaun
def q_fence_panel_model():
    """Bauzaunfeld 3,5 x 2,0 m (verzinkter Rohrrahmen mit Drahtgitter) auf zwei Betonfüßen; Ursprung am Fuß in der Mitte, Länge entlang x."""
    key = "bauzaun"
    if key in LIB:
        return key
    fb = FBuild()
    zinc, wire, conc = (0.66, 0.68, 0.70), (0.55, 0.57, 0.59), (0.58, 0.57, 0.55)
    W_, H_ = 3.5, 2.0
    y0 = 0.12
    for xx in (-W_ / 2 + 0.03, W_ / 2 - 0.03):
        q_fb_tube(fb, (xx, 0, y0), (xx, 0, y0 + H_ - 0.12), 0.017, 0.017, 6, zinc, cap1=zinc)
    for hh in (0.0, H_ - 0.16):
        q_fb_tube(fb, (-W_ / 2, 0, y0 + hh + 0.03), (W_ / 2, 0, y0 + hh + 0.03), 0.017, 0.017, 6, zinc)
    q_fb_tube(fb, (-W_ / 2, 0, y0 + 0.95), (W_ / 2, 0, y0 + 0.95), 0.012, 0.012, 5, wire)
    n = 28
    for k in range(n + 1):                                                # senkrechte Drähte (flache Streifen)
        xx = -W_ / 2 + 0.06 + k * (W_ - 0.12) / n
        fb.poly([qV(xx - 0.004, 0, y0 + 0.05), qV(xx + 0.004, 0, y0 + 0.05), qV(xx + 0.004, 0, y0 + H_ - 0.14), qV(xx - 0.004, 0, y0 + H_ - 0.14)], wire, out_from=qV(xx, -1, y0))
        fb.poly([qV(xx + 0.004, 0, y0 + 0.05), qV(xx - 0.004, 0, y0 + 0.05), qV(xx - 0.004, 0, y0 + H_ - 0.14), qV(xx + 0.004, 0, y0 + H_ - 0.14)], wire, out_from=qV(xx, 1, y0))
    for xx in (-W_ / 2 + 0.25, W_ / 2 - 0.25):                            # Betonfüße quer zum Zaun
        q_fb_box(fb, xx, 0.0, 0.0, 0.2, 0.09, 0.30, 0.0, conc, top=(0.64, 0.63, 0.61))
    obj = q_bm_object(key, fb.bm, [M["farbe"]], link=False)
    return q_register(key, obj)


def q_fence(pts, closed=False, gaps=()):
    """Bauzaun entlang einer Punktfolge (Felder à 3,5 m, ein Hindernis je Feld, weich); gaps: Listen (x, z, Radius) für Tore ohne Zaun."""
    key = q_fence_panel_model()
    n = 0
    seq = list(pts) + ([pts[0]] if closed else [])
    for a, b in zip(seq, seq[1:]):
        d = math.hypot(b[0] - a[0], b[1] - a[1])
        k = max(1, int(round(d / 3.5)))
        ang = math.atan2(b[1] - a[1], b[0] - a[0])
        for i in range(k):
            t = (i + 0.5) / k
            x, z = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
            if any(math.hypot(x - gx_, z - gz_) < gr for gx_, gz_, gr in gaps):
                continue
            q_put(key, x, z, ang, scale=(d / k) / 3.5, y=q_ground_y(x, z) - 0.02, anchor="origin")
            collide_rect(x, z, math.cos(ang), math.sin(ang), d / k / 2, 0.3, 1.9, "gitter")
            n += 1
    return n


# ---------------------------------------------------------------- Grubenrand: Sicherheitswall am Fuß der ersten Böschung
def q_foot_walls():
    """Die Böschungen sind für die Fahrphysik unsichtbar; damit niemand in sie hineinfährt, stehen am Fuß der ersten Stufe Felsriegel als
    Hindernisse ("mauer", 2,8 m), je Quadrat von 3 m ein Stück längs der Höhenlinie."""
    xs_ = np.arange(x0 + 1.5, x1, 1.0)
    zs_ = np.arange(z0 + 1.5, z1, 1.0)
    X, Z = np.meshgrid(xs_, zs_)
    P = np.stack([X.ravel(), Z.ravel()], 1)
    u = q_u(P)
    band = (u > 0.2) & (u < 1.2)
    Pb, ub = P[band], u[band]
    taken = {}
    for (px, pz), uu in zip(Pb, ub):
        key = (int(px // 3.0), int(pz // 3.0))
        if key not in taken or abs(uu - 0.7) < abs(taken[key][2] - 0.7):
            taken[key] = (px, pz, uu)
    n = 0
    for (px, pz, uu) in taken.values():
        e = 0.7
        g = np.array([q_u(np.array([[px + e, pz]]))[0] - q_u(np.array([[px - e, pz]]))[0], q_u(np.array([[px, pz + e]]))[0] - q_u(np.array([[px, pz - e]]))[0]])
        ln = np.linalg.norm(g)
        if ln < 1e-4:
            continue
        g = g / ln
        ang = math.atan2(g[0], -g[1])                      # Längsachse quer zum Gefälle
        if f_dc_ok(px, pz):
            collide_rect(px, pz, math.cos(ang), math.sin(ang), 2.0, 0.6, 2.8, "mauer", visible=False)      # kein Klotz in der einfachen Grafikstufe
            n += 1
    print("DIORAMA Felsriegel am Böschungsfuß:", n)


def f_dc_ok(x, z):
    return q_dc(x, z) > HW + 6.0


# ---------------------------------------------------------------- Aufstellung
def q_free(x, z, r, dc_min=None):
    if dc_min is None:
        dc_min = HW + 1.5 + r
    return (q_dc(x, z) >= dc_min and not q_blocked(x, z, r) and float(q_u(np.array([(x, z)]))[0]) < -0.5
            and q_flat_floor(x, z, r))


def q_site():
    pr = random.Random(12)
    placed = {}
    # --- Wasserwagen und Tankstelle in der Sohle
    for name, fn, spots in (("wasserwagen", q_water_bowser, ((-4.0, 12.5, 0.2), (-8.0, 16.0, 0.1), (2.0, 15.0, -0.1))),
                            ("tankstelle", q_fuel_station, ((10.0, 17.0, 0.0), (6.0, 18.0, 0.1), (28.0, 14.0, 0.0)))):
        for (x, z, a) in spots:
            if q_free(x, z, 3.4):
                fn(x, z, a)
                placed[name] = (x, z)
                break
    # --- Natursteinblöcke: zwei Lagerplätze mit Zaun an der Südseite der Sohle
    stacks = [(-47.0, 19.5, 0.04), (-38.0, 20.5, -0.03), (-29.0, 21.5, 0.02)]
    got = 0
    for k, (x, z, a) in enumerate(stacks):
        if q_free(x, z, 3.2):
            q_cut_block_stack(x, z, a, cols=3, rows=2, layers=2 if k != 1 else 1, seed=k + 1)
            got += 1
    placed["bloecke"] = got
    # --- Container am Büro und am Brecher
    for x, z, a, kinds in ((-87.0, -8.0, 0.0, ("rot", "blau")), (-80.5, -8.5, 0.05, ("gelb",)), (60.0, -42.0, 0.0, ("blau",))):
        if q_free(x, z, 3.6, dc_min=4.0):
            q_container(x, z, a, kinds)
    # --- Betonrohre am Graben, Warnschilder und Absperrschranken
    for x, z, a in (((15.5, -13.0, 0.4), (16.5, -6.0, 0.2)) if data.get("rev", 1) >= 2 else ((6.0, -29.5, 0.2), (28.0, -30.0, -0.1))):
        if q_free(x, z, 2.4, dc_min=HW + 3.0):
            q_pipes(x, z, a)
            break
    for g in data.get("gaps", []):
        i0, i1 = int(g["from"] * N), int(g["to"] * N)
        high = base_height(float(g["from"])) > 0.5
        for i in (i0 - 14, i1 + 14):
            c, t, l_ = center[i % N], tang[i % N], left[i % N]
            ang = math.atan2(t.y, t.x)
            for side in (1, -1):
                off = HW + (2.8 if (high and i < i0) else 1.8)
                x, z = c.x + l_.x * side * off, c.y + l_.y * side * off
                if q_dc(x, z) >= HW + 1.4 and not q_blocked(x, z, 1.2):
                    q_barrier(x, z, ang, 2.3)
    sign_spots = []
    for g in data.get("gaps", []):
        i0, i1 = int(g["from"] * N), int(g["to"] * N)
        for i, face in ((i0 - 40, 1), (i1 + 40, -1)):
            c, t, l_ = center[i % N], tang[i % N], left[i % N]
            x, z = c.x - l_.x * (HW + 1.7), c.y - l_.y * (HW + 1.7)
            sign_spots.append((x, z, math.atan2(-t.y, -t.x)))
    for lp in data.get("loops", []):
        i = int(lp["s"] * N) - 30
        c, t, l_ = center[i % N], tang[i % N], left[i % N]
        sign_spots.append((c.x + l_.x * (HW + 1.7), c.y + l_.y * (HW + 1.7), math.atan2(-t.y, -t.x)))
    for sc in data.get("shortcuts", []):
        i = int(sc["from"] * N) - 14
        c, t, l_ = center[i % N], tang[i % N], left[i % N]
        sign_spots.append((c.x + l_.x * (HW + 1.7), c.y + l_.y * (HW + 1.7), math.atan2(-t.y, -t.x)))
    for k, (x, z, a) in enumerate(sign_spots):
        if q_dc(x, z) >= HW + 1.2 and not q_blocked(x, z, 0.3):
            q_sign(x, z, a, "warn" if k % 2 == 0 else "stein")
    print("DIORAMA Steinbruch: Tankstelle/Wasserwagen/Blöcke", placed)
    return placed


def q_boulders():
    rng_ = np.random.default_rng(5)
    pr = random.Random(7)
    xa, xb, za, zb = x0 + 8, x1 - 8, z0 + 8, z1 - 8
    P = np.stack([rng_.uniform(-125, 118, 14000), rng_.uniform(-80, 82, 14000)], 1)
    u = q_u(P)
    dc = dist_to_center(P)
    sdl = q_lake_sdf(P[:, 0], P[:, 1])
    n1 = q_fbm(P[:, 0], P[:, 1], 8.0, 2, 71.0)
    # Bereiche: Böschungsfuß/-kante (u um 0 und 1,5..3), See-Ufer, Sohle verstreut, Hochfläche hinter den Bänken
    w = np.where((u > -3.0) & (u < 6.0), 0.55 + 0.4 * (n1 > 0.55), 0.0)
    w = np.maximum(w, np.where((sdl > -0.5) & (sdl < 5.0), 0.7, 0.0))
    w = np.maximum(w, np.where((u < -2.0) & (dc > HW + 4.0), 0.06 + 0.25 * (n1 > 0.62), 0.0))
    w = np.where(dc > HW + 3.4, w, 0.0)
    for f in Q_FACES:
        al, cr = q_face_coords(P, f)
        w = np.where((al > f["a0"] - 1.0) & (al < f["a1"] + 1.0) & (np.abs(cr) < 1.6), 0.0, w)
    chosen = []
    for i in rng_.permutation(len(P)):
        if len(chosen) >= 150:
            break
        if rng_.random() > w[i]:
            continue
        x, z = float(P[i, 0]), float(P[i, 1])
        if abs(x) > 105 or abs(z) > 70:
            continue
        if any((x - cx) ** 2 + (z - cz) ** 2 < 2.6 ** 2 for cx, cz, _ in chosen):
            continue
        if q_blocked(x, z, 1.0) or float(q_lake_sdf(x, z)) < -0.3:
            continue
        sz_ = pr.choice([0.7, 0.9, 1.1, 1.4, 1.9, 2.5]) * pr.uniform(0.85, 1.15)
        chosen.append((x, z, sz_))
    for x, z, sz_ in chosen:
        key = q_boulder(int(abs(x * 3.1 + z * 1.7)) % 5)
        gy = q_ground_y(x, z)
        q_put(key, x, z, pr.uniform(0, 6.28), scale=sz_, y=gy - 0.12 * sz_, anchor="origin")
        reachable = float(q_u(np.array([(x, z)]))[0]) < 0.5
        if reachable and sz_ >= 0.8:
            q_solid(x, z, 0.5 * sz_ * 0.85, 1.2, "mast")
        else:
            Q_SOLIDS.append((x, z, 0.4 * sz_))
    print("DIORAMA Findlinge:", len(chosen))


Q_HEAP_AI = []                                  # die Kieshaufen der Streckendatei (vom Diorama selbst gebaut)


def q_heaps():
    """Halden: erst die drei Vorratshaufen anstelle der KI-Kieshaufen (Kalksplitt, grauer Schotter, Sand), dann kleinere Schüttkegel an den
    Rändern. Die Vorratshaufen sind steiler als die Halden (Schüttwinkel von Brechsplitt rund 35 Grad) und tragen Hindernisse wie vorher."""
    pr = random.Random(2)
    kinds = (2, 3, 1)
    k = 0
    for p in Q_AI:
        if p.get("model") != "steinbruch_kieshaufen":
            continue
        Q_HEAP_AI.append(p)
        x, z = float(p["x"]), float(p["z"])
        rad = 3.2
        key = q_heap(kinds[k % len(kinds)])
        k += 1
        q_put_nu(key, x, z, pr.uniform(0, 6.28), rad, rad, rad * 1.55, q_ground_y(x, z) - 0.04)
        q_solid(x, z, 2.7, 3.0, "mauer")
    spots = [(44.0, 38.0, 4.2, 1), (73.0, 51.0, 5.0, 0), (64.0, -37.0, 3.4, 2), (-8.0, 31.0, 0.0, 0)]
    for x, z, rad, kind in spots:
        if rad <= 0 or q_blocked(x, z, rad * 0.8):
            continue
        key = q_heap(kind)
        q_put(key, x, z, pr.uniform(0, 6.28), scale=rad, y=q_ground_y(x, z) - 0.02, anchor="origin")
        q_solid(x, z, rad * 0.78, rad * 0.46, "bank")


def q_lamps_and_misc():
    for pos, toward in (((-79.5, 12.5), (-84.0, 6.0)), ((5.5, 12.0), (10.0, 17.0)), ((-37.0, 24.8), (-38.0, 20.5)), ((62.0, -24.0), (68.0, -29.0))):
        if q_dc(*pos) >= HW + 3.0 and not q_blocked(pos[0], pos[1], 0.4):
            lamps.append((Vector(pos), Vector(toward)))
    # Barrels bei Tankstelle und Büro
    for x, z, n_, sd in ((4.0, 22.0, 5, 1), (-90.0, 14.0, 4, 2)):
        if q_free(x, z, 1.4, dc_min=5.0):
            q_barrels(x, z, n_, sd)
    # Reifenwand an der Kante zur Hochfläche und am Looping
    for x, z in ((12.0, 35.5), (15.0, 35.8), (26.5, 35.6), (29.5, 35.3)):
        if q_dc(x, z) >= HW + 1.8 and not q_blocked(x, z, 1.2):
            q_tire(x, z, 0.0)
            q_solid(x, z, 1.1, 2.1, "reifen")


# ---------------------------------------------------------------- Beleuchtung: Flutlichtmasten und Lichtmast-Anhänger (echte Lichtquellen)
Q_FLOOD = (0.94, 0.96, 1.0)            # Flutlicht: kühles Weiß (LED-Strahler); die vier Baustellenleuchten (lamps) bleiben warm
Q_LIGHT_STATS = {"poles": 0, "towers": 0}


def q_tilt_box(fb, fl, x, z, y, heading, tilt, hw=0.24, hd=0.09, hh=0.19, col=(0.20, 0.21, 0.23)):
    """Flutlichtstrahler: Gehäuse (Quader, Breite 2 hw, Tiefe 2 hd, Höhe 2 hh) um (x, z, y), nach vorn (heading, Bogenmaß in Spielkoordinaten)
    um tilt nach unten geneigt; auf der Vorderseite sitzt die Linse (K_lampe, eigenes Netz fl: nachts warmweiß), dahinter ein Kühlkörper."""
    cf, sf = math.cos(heading), math.sin(heading)
    ct, st = math.cos(tilt), math.sin(tilt)

    def pt(lf, ls, lu):
        wf = lf * ct + lu * st                     # Neigung um die Seitenachse (Vorderseite nach unten)
        wu = -lf * st + lu * ct
        return qV(x + cf * wf - sf * ls, z + sf * wf + cf * ls, y + wu)
    cen = pt(0, 0, 0)
    for sa in (-1, 1):
        face = [pt(sa * hd, -hw, -hh), pt(sa * hd, hw, -hh), pt(sa * hd, hw, hh), pt(sa * hd, -hw, hh)]
        if sa > 0:
            fb.poly([pt(hd, -hw, -hh), pt(hd, hw, -hh), pt(hd, hw, hh), pt(hd, -hw, hh)], col, out_from=cen)
            fl.poly([pt(hd + 0.012, -hw * 0.86, -hh * 0.82), pt(hd + 0.012, hw * 0.86, -hh * 0.82), pt(hd + 0.012, hw * 0.86, hh * 0.82),
                     pt(hd + 0.012, -hw * 0.86, hh * 0.82)], (0.92, 0.92, 0.86), out_from=cen)
        else:
            fb.poly(face, col, out_from=cen)
    for sb in (-1, 1):
        fb.poly([pt(-hd, sb * hw, -hh), pt(hd, sb * hw, -hh), pt(hd, sb * hw, hh), pt(-hd, sb * hw, hh)], col, out_from=cen)
    for sc in (-1, 1):
        fb.poly([pt(-hd, -hw, sc * hh), pt(hd, -hw, sc * hh), pt(hd, hw, sc * hh), pt(-hd, hw, sc * hh)], tuple(v * 0.8 for v in col) if sc < 0 else col, out_from=cen)
    for k in range(5):                                                 # Kühlrippen oben
        ls = -hw * 0.8 + k * hw * 0.4
        fb.poly([pt(-hd * 0.8, ls - 0.012, hh), pt(hd * 0.5, ls - 0.012, hh), pt(hd * 0.5, ls - 0.012, hh + 0.05), pt(-hd * 0.8, ls - 0.012, hh + 0.05)], (0.12, 0.12, 0.13), out_from=cen)


def q_flood_pole(x, z, heading, H=10.0, lamps=4):
    """Flutlichtmast der Grube: Betonfundament mit Fußplatte und Ankerschrauben, Schaltkasten, konischer Stahlmast (zwei Schüsse mit Flansch),
    Wartungsplattform mit Geländer, Traverse mit zwei mal zwei Strahlern, die zur Grube blicken. Hindernis: Mast."""
    fb, fl = FBuild(), FBuild()
    gy = q_ground_y(x, z)
    steel, steel_d, conc, dark = (0.50, 0.53, 0.57), (0.34, 0.36, 0.40), (0.62, 0.61, 0.58), (0.14, 0.15, 0.16)
    q_fb_box(fb, x, z, gy - 0.06, gy + 0.34, 0.55, 0.55, heading, conc, top=(0.68, 0.67, 0.64))
    q_fb_box(fb, x, z, gy + 0.34, gy + 0.39, 0.27, 0.27, heading, steel_d)
    L = q_local(x, z, heading)
    for sa in (-1, 1):
        for sb in (-1, 1):
            ax_, az_ = L(sa * 0.2, sb * 0.2)
            q_fb_tube(fb, (ax_, az_, gy + 0.39), (ax_, az_, gy + 0.49), 0.022, 0.022, 6, dark)
    bx, bz = L(0.0, 0.5)
    q_fb_box(fb, bx, bz, gy + 0.0, gy + 0.62, 0.14, 0.2, heading, (0.30, 0.34, 0.31), top=(0.36, 0.40, 0.37))        # Schaltkasten
    q_fb_tube(fb, (x, z, gy + 0.39), (x, z, gy + H * 0.52), 0.155, 0.125, 8, steel)
    q_fb_tube(fb, (x, z, gy + H * 0.52 - 0.04), (x, z, gy + H * 0.52 + 0.05), 0.165, 0.165, 8, steel_d)                   # Flansch
    q_fb_tube(fb, (x, z, gy + H * 0.52 + 0.05), (x, z, gy + H), 0.115, 0.085, 8, steel)
    ty = gy + H - 0.55
    q_fb_box(fb, x, z, ty, ty + 0.05, 0.42, 0.42, heading, steel_d, top=steel)                                       # Plattform
    for k in range(8):                                                                                              # Geländer
        a_ = 2 * math.pi * k / 8
        px_, pz_ = x + math.cos(a_) * 0.4, z + math.sin(a_) * 0.4
        q_fb_tube(fb, (px_, pz_, ty + 0.05), (px_, pz_, ty + 0.55), 0.012, 0.012, 4, steel_d)
    for k in range(8):                                                                                              # Handlauf
        a_, b_ = 2 * math.pi * k / 8, 2 * math.pi * (k + 1) / 8
        q_fb_tube(fb, (x + 0.4 * math.cos(a_), z + 0.4 * math.sin(a_), ty + 0.55), (x + 0.4 * math.cos(b_), z + 0.4 * math.sin(b_), ty + 0.55), 0.012, 0.012, 4, steel_d)
    head_y = gy + H - 0.05
    sx, sz = -math.sin(heading), math.cos(heading)
    a0, a1 = (x - sx * 1.25, z - sz * 1.25, head_y), (x + sx * 1.25, z + sz * 1.25, head_y)
    q_fb_tube(fb, a0, a1, 0.04, 0.04, 6, steel_d)                                                                    # Traverse
    for row in range(lamps // 2):
        for k in range(2):
            for sgn in (-1, 1):
                off = sgn * (0.35 + 0.45 * k)
                q_tilt_box(fb, fl, x + sx * off + math.cos(heading) * 0.12, z + sz * off + math.sin(heading) * 0.12, head_y + 0.28 + 0.46 * row,
                           heading, math.radians(24))
    q_bm_object("Flutlichtmast", fb.bm, [M["farbe"]])
    q_bm_object("Flutlichtmast_Linsen", fl.bm, [M["k:lampe"]])
    q_solid(x, z, 0.55, H, "mast")
    Q_LIGHT_STATS["poles"] += 1
    return (x + math.cos(heading) * 0.15, z + math.sin(heading) * 0.15, head_y + 0.4)


def q_light_tower(x, z, ang, heading):
    """Lichtmast-Anhänger (mobiler Baustellenturm): Zweiachs-Anhänger mit gelbem Aggregatgehäuse, vier Stützen, ausgefahrener Teleskopmast
    (vier Schüsse mit Manschetten) und vier Strahlern, die zu heading zeigen. ang = Längsrichtung des Anhängers."""
    fb, fl = FBuild(), FBuild()
    gy = q_ground_y(x, z)
    L = q_local(x, z, ang)
    yellow, dark, steel, rubber, rim = (0.93, 0.70, 0.07), (0.12, 0.12, 0.13), (0.50, 0.53, 0.57), (0.07, 0.07, 0.075), (0.62, 0.62, 0.60)
    px, pz = L(0.0, 0.0)
    q_fb_box(fb, px, pz, gy + 0.46, gy + 0.62, 1.55, 0.50, ang, dark, top=(0.22, 0.22, 0.24))                              # Rahmen
    hx_, hz_ = L(0.1, 0.0)
    q_fb_box(fb, hx_, hz_, gy + 0.62, gy + 1.78, 1.05, 0.64, ang, yellow, top=(0.80, 0.60, 0.05))                          # Aggregatgehäuse
    for k in range(4):                                                                                              # Lüftungsschlitze
        lx_, lz_ = L(-0.5 + k * 0.28, 0.655)
        q_fb_box(fb, lx_, lz_, gy + 0.95, gy + 1.45, 0.09, 0.012, ang, (0.30, 0.22, 0.04))
        lx_, lz_ = L(-0.5 + k * 0.28, -0.655)
        q_fb_box(fb, lx_, lz_, gy + 0.95, gy + 1.45, 0.09, 0.012, ang, (0.30, 0.22, 0.04))
    for au in (0.15,):                                                                                              # Achse und Räder (Achse quer zur Längsrichtung)
        for side in (-1, 1):
            w0, w1 = L(au, side * 0.55), L(au, side * 0.80)
            q_fb_tube(fb, (w0[0], w0[1], gy + 0.34), (w1[0], w1[1], gy + 0.34), 0.34, 0.34, 18, rubber, cap0=rim if side < 0 else None, cap1=rim if side > 0 else None)
            f0 = L(au, side * 0.66)
            q_fb_box(fb, f0[0], f0[1], gy + 0.66, gy + 0.70, 0.46, 0.2, ang, yellow)
    d0, d1, d2 = L(-1.35, -0.4), L(-1.35, 0.4), L(-2.7, 0.0)                                                          # Zugdeichsel
    q_fb_tube(fb, (d0[0], d0[1], gy + 0.54), (d2[0], d2[1], gy + 0.50), 0.04, 0.035, 6, dark)
    q_fb_tube(fb, (d1[0], d1[1], gy + 0.54), (d2[0], d2[1], gy + 0.50), 0.04, 0.035, 6, dark)
    j = L(-2.3, 0.0)
    q_fb_tube(fb, (j[0], j[1], gy + 0.0), (j[0], j[1], gy + 0.52), 0.035, 0.035, 6, steel, cap0=dark)                  # Stützrad
    for sa in (-1, 1):                                                                                              # Stützen mit Fußplatten
        for sb in (-1, 1):
            ox, oz = L(sa * 1.3, sb * 0.52)
            fx_, fz_ = L(sa * 1.62, sb * 0.95)
            q_fb_tube(fb, (ox, oz, gy + 0.54), (fx_, fz_, gy + 0.46), 0.03, 0.03, 5, steel_d if False else dark)
            q_fb_tube(fb, (fx_, fz_, gy + 0.46), (fx_, fz_, gy + 0.05), 0.035, 0.035, 6, steel, cap0=dark)
            q_fb_box(fb, fx_, fz_, gy + 0.0, gy + 0.045, 0.14, 0.14, ang, dark)
    mx, mz = L(0.35, 0.0)
    H = 8.0
    for i, (r0, r1, t0, t1) in enumerate(((0.095, 0.095, 1.78, 3.6), (0.080, 0.080, 3.6, 5.4), (0.066, 0.066, 5.4, 7.2), (0.052, 0.052, 7.2, H))):
        q_fb_tube(fb, (mx, mz, gy + t0), (mx, mz, gy + t1), r0, r1, 8, steel)
        q_fb_tube(fb, (mx, mz, gy + t0 - 0.03), (mx, mz, gy + t0 + 0.05), r0 + 0.018, r0 + 0.018, 8, dark)                 # Manschette
    cf, sf = math.cos(heading), math.sin(heading)
    sx, sz = -sf, cf
    head_y = gy + H + 0.02
    q_fb_tube(fb, (mx - sx * 1.0, mz - sz * 1.0, head_y), (mx + sx * 1.0, mz + sz * 1.0, head_y), 0.035, 0.035, 6, steel)    # Traverse
    for off in (-0.78, -0.26, 0.26, 0.78):
        q_tilt_box(fb, fl, mx + sx * off + cf * 0.1, mz + sz * off + sf * 0.1, head_y + 0.24, heading, math.radians(28), hw=0.22, hd=0.085, hh=0.17)
    q_bm_object("Lichtmast", fb.bm, [M["farbe"]])
    q_bm_object("Lichtmast_Linsen", fl.bm, [M["k:lampe"]])
    q_solid_rect(px, pz, ang, 1.75, 0.95, 1.8, "mauer")
    Q_LIGHT_STATS["towers"] += 1
    return (mx + cf * 0.2, mz + sf * 0.2, head_y + 0.3)


def q_site_ok(x, z, r, dc_min=None):
    """Standort für Masten: in der Grubensohle, abseits der Fahrbahn, der Abkürzung und aller festen Teile."""
    if q_dc(x, z) < (dc_min if dc_min is not None else HW + 3.0 + r):
        return False
    if q_blocked(x, z, r):
        return False
    if float(q_u(np.array([(x, z)]))[0]) > -1.0:
        return False
    for sc in data.get("shortcuts", []):
        pts = sc["path"]
        for p0, p1 in zip(pts, pts[1:]):
            if float(q_seg_dist(np.array([(x, z)], float), p0, p1)[0]) < sc.get("width", 4.0) / 2 + 1.5 + r:
                return False
    return True


def q_lights():
    """Flutlicht der Grube: zehn Masten außen um die Betriebsstraße (Abstand etwa 40 m), drei Lichtmast-Anhänger in der Sohle bei den
    Maschinen. Jede Lichtquelle ist eine echte Quelle in der Lichtkarte (add_light), die Strahlerköpfe leuchten nur nachts; am Tag sind sie aus."""
    poles = ((-76.0, -12.0), (-76.0, 26.0), (-40.0, 36.5), (5.0, 36.5), (46.0, 38.0), (68.5, 6.0), (52.0, -35.0), (22.0, -34.5),
             (-20.0, -34.0), (-62.0, -35.0))
    if data.get("rev", 1) >= 2:
        poles = poles + ((12.0, -34.0), (49.0, 2.0), (-12.0, -45.5))          # Bruchkante, Fahrrampe, Nordstraße hinter der Kreuzung
    placed = []
    skipped = []
    for (px, pz) in poles:
        site = None
        for dx, dz in ((0, 0), (2, 0), (-2, 0), (0, 2), (0, -2), (3, 3), (-3, -3), (3, -3), (-3, 3), (5, 0), (-5, 0), (0, 5), (0, -5)):
            if q_site_ok(px + dx, pz + dz, 0.9):
                site = (px + dx, pz + dz)
                break
        if site is None:
            skipped.append((px, pz))
            continue
        # Blickrichtung: zur nächsten Stelle der Fahrbahn (die Strahler leuchten die Straße und die Maschinen an)
        i = int(np.argmin([(c.x - site[0]) ** 2 + (c.y - site[1]) ** 2 for c in center]))
        head = math.atan2(center[i].y - site[1], center[i].x - site[0])
        hx, hz, hy = q_flood_pole(site[0], site[1], head)
        add_light(hx, hz, hy, Q_FLOOD, 1.05, 25.0, omni=False, glow=1.6)
        placed.append(site)
    towers = (((-9.0, 3.0), (-30.0, 10.0)), ((30.0, 13.0), (20.0, 0.0)), ((-46.0, 3.0), (-30.0, 10.0)))
    if data.get("rev", 1) >= 2:
        towers = towers + (((-14.0, -11.0), (-2.0, -24.0)),)                   # Kreuzung unter dem Sprung
    for k, ((px, pz), (tx, tz)) in enumerate(towers):
        site = None
        for dx, dz in ((0, 0), (3, 0), (-3, 0), (0, 3), (0, -3), (5, 4), (-5, -4)):
            if q_site_ok(px + dx, pz + dz, 2.2):
                site = (px + dx, pz + dz)
                break
        if site is None:
            skipped.append((px, pz))
            continue
        heading = math.atan2(tz - site[1], tx - site[0])
        hx, hz, hy = q_light_tower(site[0], site[1], heading + math.pi / 2 + 0.25, heading)
        add_light(hx, hz, hy, Q_FLOOD, 1.1, 21.0, omni=(k == 0), glow=1.2)
        placed.append(site)
    print("DIORAMA Flutlicht: Masten", Q_LIGHT_STATS["poles"], "Lichtmast-Anhänger", Q_LIGHT_STATS["towers"], "| Standorte", [(round(a, 1), round(b, 1)) for a, b in placed],
          "| ohne Platz", skipped)


# ---------------------------------------------------------------- Graben in der Lücke der Fahrbahn
Q_PIT_DEPTH = 1.7                          # Tiefe der Grabensohle unter dem Gelände (m)
Q_PIT_WATER = 1.15                         # Wasserspiegel unter dem Gelände (m)
Q_PIT_SLOPE = 2.4                          # Länge der Böschungen an den Schmalseiten (m)


def q_pit_plan():
    """Lage des Grabens: die Lücke der Fahrbahn (Eintrag gaps der Streckendatei). Die Strecke läuft dort gerade und achsparallel; der Graben ist
    ein rechteckiger Einschnitt quer über die Piste: an den beiden Fahrbahnenden Bruchsteinmauern, an den Schmalseiten Erdböschungen, unten Wasser.
    Das Hauptnetz des Bodens bekommt ein Loch (ganze Zellen, 1,5 m Rand), das ein Feinnetz (0,5 m) mit Aussparung für den Graben füllt."""
    Q_PIT.clear()
    gaps = data.get("gaps", [])
    if not gaps:
        return
    g = gaps[0]
    if base_height(float(g["from"])) > 0.5 or base_height(float(g["to"])) > 0.5:
        print("DIORAMA Lücke liegt erhöht (Sprung über den Sohlenweg): kein Graben")
        return
    c0, c1 = center[int(round(g["from"] * N)) % N], center[int(round(g["to"] * N)) % N]
    if abs(c0.y - c1.y) > 0.3 or abs(c0.x - c1.x) < 2.0:
        print("DIORAMA Warnung: Lücke der Fahrbahn nicht achsparallel, kein Graben")
        return
    xa, xb = min(c0.x, c1.x), max(c0.x, c1.x)
    zc = (c0.y + c1.y) / 2.0
    W = HW + 3.5
    gx = np.arange(x0, x1 + 0.001, Q_STEP)
    gz = np.arange(z0, z1 + 0.001, Q_STEP)
    hx0 = float(gx[max(0, int(np.searchsorted(gx, xa - 1.5, side="right")) - 1)])
    hx1 = float(gx[min(len(gx) - 1, int(np.searchsorted(gx, xb + 1.5, side="left")))])
    hz0 = float(gz[max(0, int(np.searchsorted(gz, zc - W - 1.5, side="right")) - 1)])
    hz1 = float(gz[min(len(gz) - 1, int(np.searchsorted(gz, zc + W + 1.5, side="left")))])
    sx0 = hx0 + 0.5 * math.ceil((xa + 0.05 - hx0) / 0.5)                       # Graben auf dem Feinraster, höchstens innerhalb der Lücke
    sx1 = hx0 + 0.5 * math.floor((xb - 0.05 - hx0) / 0.5)
    sz0 = hz0 + 0.5 * round((zc - W - hz0) / 0.5)
    sz1 = hz0 + 0.5 * round((zc + W - hz0) / 0.5)
    Q_PIT.update(hole=(hx0, hx1, hz0, hz1), box=(sx0, sx1, sz0, sz1), zc=zc)
    print("DIORAMA Graben: x %.1f bis %.1f, z %.1f bis %.1f, Tiefe %.1f" % (sx0, sx1, sz0, sz1, Q_PIT_DEPTH))


def q_pit_build():
    """Böschungen, Sohle, Bruchsteinmauern mit Abdeckplatten und das Wasser des Grabens (Maße aus q_pit_plan)."""
    if not Q_PIT:
        return
    sx0, sx1, sz0, sz1 = Q_PIT["box"]
    ys, yb = GROUND_Y, GROUND_Y - Q_PIT_DEPTH
    yw = GROUND_Y - Q_PIT_WATER
    sl = Q_PIT_SLOPE
    rr = random.Random(17)
    bm = bmesh.new()
    uv0 = bm.loops.layers.uv.new("UVMap")
    colL = bm.loops.layers.float_color.new("Color")

    def poly(pts, cols):
        vs = [bm.verts.new((px, -pz, py)) for px, pz, py in pts]
        try:
            f = bm.faces.new(vs)
        except ValueError:
            return
        f.normal_update()
        if f.normal.z < 0:
            f.normal_flip()
        f.smooth = True
        for loop in f.loops:
            k = vs.index(loop.vert)
            loop[uv0].uv = (pts[k][0] / 4.0, -pts[k][1] / 4.0)
            loop[colL] = (cols[k][0], cols[k][1], cols[k][2], 1.0)

    # Böschungen an den Schmalseiten: Raster mit leicht unregelmäßigen Höhen und Gewichten (Fels/Staub); die Mauerenden verlaufen im Profil
    nx = max(2, int(round((sx1 - sx0) / 0.75)))
    rows = 4
    for side in (-1, 1):
        z_top = sz1 if side > 0 else sz0
        grid = {}
        for i in range(nx + 1):
            px = sx0 + (sx1 - sx0) * i / nx
            for j in range(rows + 1):
                t = j / rows
                pz = z_top - side * sl * t
                py = ys - (ys - yb) * t ** 0.85
                if 0 < j < rows:
                    py += rr.uniform(-0.10, 0.10)
                    pz += rr.uniform(-0.12, 0.12)
                if 0 < i < nx:
                    px_ = px + rr.uniform(-0.12, 0.12)
                else:
                    px_ = px
                wet = min(1.0, max(0.0, (yw + 0.25 - py) / 0.5))
                grid[(i, j)] = ((px_, pz, py), (0.80 - 0.30 * wet + rr.uniform(-0.05, 0.05), 0.46 + 0.20 * wet, 0.74 - 0.20 * wet))
        for i in range(nx):
            for j in range(rows):
                q = [grid[(i, j)], grid[(i + 1, j)], grid[(i + 1, j + 1)], grid[(i, j + 1)]]
                poly([c[0] for c in q], [c[1] for c in q])
    # Sohle
    fl = [(sx0, sz0 + sl, yb), (sx1, sz0 + sl, yb), (sx1, sz1 - sl, yb), (sx0, sz1 - sl, yb)]
    poly(fl, [(0.52, 0.80, 0.34)] * 4)
    og = q_bm_object("Gelaende_Graben_Boeschung", bm, [M["gelaende"]])
    objs_ground.append(og)
    # Bruchsteinmauern an den beiden Fahrbahnenden (Trapez: oben volle Breite, unten bis zur Sohle) mit Abdeckplatten aus Beton
    parts = []
    t_ = 1.6
    for xw, face in ((sx0, 1.0), (sx1, -1.0)):
        pts = [(xw, sz0, ys), (xw, sz1, ys), (xw, sz1 - sl, yb), (xw, sz0 + sl, yb)]
        uvs = [(pz / t_, py / t_) for _, pz, py in pts]
        parts.append(("q_block", pts, uvs, (face, 0.0)))
    mesh_objects("Graben_Mauer", parts)
    fb = FBuild()
    for xw, face in ((sx0, 1.0), (sx1, -1.0)):
        cx = xw - face * 0.15
        q_fb_box(fb, cx, (sz0 + sz1) / 2, ys - 0.06, ys + 0.065, 0.25, (sz1 - sz0) / 2 + 0.05, 0.0, (0.62, 0.61, 0.58), top=(0.68, 0.67, 0.64))
    q_bm_object("Graben_Abdeckung_beton", fb.bm, [M["farbe"]])
    # Wasser: gleiche Flachwasser-Darstellung wie der Baggersee; Tiefe in der Vertexfarbe (Rot)
    wparts = []
    nzw = 14
    for i in range(2):
        for j in range(nzw):
            za, zb_ = sz0 + (sz1 - sz0) * j / nzw, sz0 + (sz1 - sz0) * (j + 1) / nzw
            xa_, xb_ = sx0 + (sx1 - sx0) * i / 2, sx0 + (sx1 - sx0) * (i + 1) / 2
            quad = [(xa_, za), (xb_, za), (xb_, zb_), (xa_, zb_)][::-1]

            dv = []
            for qx, qz in quad:
                e = min(qz - sz0, sz1 - qz)
                tt = min(1.0, max(0.0, 1.0 - e / sl))                  # 0 auf der Sohle, 1 am Rand
                h = ys - (ys - yb) * (1.0 - tt) ** 0.85 if tt < 1.0 else ys     # wie das Böschungsprofil (t = Abstand vom Rand / Länge)
                dv.append(float(np.clip((yw - h) / 0.9, 0.0, 1.0)))
            wparts.append(("wasser", [(qx, qz, yw) for qx, qz in quad], [(qx / 6.0, -qz / 6.0) for qx, qz in quad], None, [(v, v, v) for v in dv]))
    mesh_object("See_Graben", wparts)
    print("DIORAMA Graben gebaut: Mauern, Böschungen, Wasser")


# ---------------------------------------------------------------- Förderband (baked: ersetzt das winzige KI-Modell)
def q_beam(fb, p0, p1, hw, hh, col, top=None):
    """Balken mit Rechteckquerschnitt zwischen p0 und p1 (je (x, z, h) in Spielkoordinaten): halbe Breite hw (waagerecht quer), halbe Höhe hh."""
    A, B = qV(*p0), qV(*p1)
    t = (B - A).normalized()
    side = t.cross(Vector((0, 0, 1)))
    if side.length < 1e-6:
        side = Vector((1, 0, 0))
    side.normalize()
    nrm = side.cross(t).normalized()
    cen = (A + B) / 2
    cs = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    ra = [A + side * hw * a + nrm * hh * b for a, b in cs]
    rb = [B + side * hw * a + nrm * hh * b for a, b in cs]
    for k in range(4):
        k2 = (k + 1) % 4
        fb.poly([ra[k], ra[k2], rb[k2], rb[k]], (top if (top is not None and nrm.z > 0.3 and k == 2) else col), out_from=cen)
    fb.poly(ra, col, out_from=cen)
    fb.poly(rb, col, out_from=cen)


def q_conveyor():
    """Gurtförderer zwischen den beiden Halden (Mitte und Richtung wie das KI-Modell der Streckendatei, 20 x 3 m): Aufgabetrichter am unteren Ende,
    steigende Gurtbahn (Muldengurt mit Schotterladung, Seitenbleche, Tragrollenstationen) auf Stahlböcken mit Betonfüßen, Laufsteg mit Geländer,
    Antriebskopf mit Motor und Abwurfschurre über die Halde (Mitte rund 13,6 m vom Kopf). Echte Lichtquellen: je ein LED-Strahler an Kopf und
    Trichter. Hindernis: Rechteck 20 x 3 m wie das KI-Modell."""
    props = [p for p in Q_AI if p.get("model") == "steinbruch_foerderband"]
    if not props:
        return
    p = props[0]
    cx, cz = float(p["x"]), float(p["z"])
    ang = math.radians(float(p.get("rot", 0.0)))
    Lb = float(p.get("w", 20.0))
    L = q_local(cx, cz, ang)
    gy = q_ground_y(cx, cz)
    Y0, Y1 = gy + 1.15, gy + 4.70                                           # Gurtoberseite am Aufgabeende und am Abwurfkopf
    a_lo, a_hi = -Lb / 2, Lb / 2
    yb_ = lambda a: Y0 + (Y1 - Y0) * (a - a_lo) / (a_hi - a_lo)
    P3 = lambda a, b, y: (*L(a, b), y)
    steel, steel_d, dark, rubber = (0.46, 0.49, 0.53), (0.30, 0.32, 0.35), (0.13, 0.13, 0.14), (0.065, 0.065, 0.07)
    yellow, conc = (0.93, 0.70, 0.07), (0.60, 0.59, 0.56)
    fb, fl = FBuild(), FBuild()
    rg = random.Random(29)
    # --- Gurt (Muldenform: flache Mitte, aufgebogene Ränder), Seitenbleche, Stringer, Tragrollenstationen
    for (b0, b1, d0, d1) in ((-0.55, -0.30, 0.17, 0.0), (-0.30, 0.30, 0.0, 0.0), (0.30, 0.55, 0.0, 0.17)):
        pts = [qV(*P3(a_lo, b0, yb_(a_lo) + d0)), qV(*P3(a_lo, b1, yb_(a_lo) + d1)), qV(*P3(a_hi, b1, yb_(a_hi) + d1)), qV(*P3(a_hi, b0, yb_(a_hi) + d0))]
        fb.poly(pts, rubber, up=True)
    for sb in (-1, 1):
        q_beam(fb, P3(a_lo - 0.3, sb * 0.80, yb_(a_lo - 0.3) - 0.27), P3(a_hi + 0.3, sb * 0.80, yb_(a_hi + 0.3) - 0.27), 0.05, 0.14, steel_d, top=steel)       # Stringer
        q_beam(fb, P3(a_lo, sb * 0.585, yb_(a_lo) + 0.17), P3(a_hi, sb * 0.585, yb_(a_hi) + 0.17), 0.012, 0.17, steel)                                      # Seitenblech
        q_beam(fb, P3(a_lo, sb * 0.585, yb_(a_lo) + 0.355), P3(a_hi, sb * 0.585, yb_(a_hi) + 0.355), 0.03, 0.02, steel_d)                                  # Kante
    a = a_lo + 0.6
    while a < a_hi - 0.4:                                                    # Tragrollenstationen: Querträger mit Rollenköpfen über die Stringer hinaus
        q_beam(fb, P3(a, -0.78, yb_(a) - 0.11), P3(a, 0.78, yb_(a) - 0.11), 0.035, 0.045, steel_d)
        for sb in (-1, 1):
            q_beam(fb, P3(a, sb * 0.60, yb_(a) + 0.075), P3(a, sb * 0.80, yb_(a) + 0.075), 0.04, 0.04, dark)
        a += 1.25
    # --- Ladung: länglicher Schotterrücken auf dem Gurt (Höhe 0,22 m in der Mitte, Rauschen), hell gegen den dunklen Gurt
    prev = None
    a = a_lo + 1.2
    while a <= a_hi - 0.9:
        row = []
        for bb in (-0.42, -0.26, -0.09, 0.09, 0.26, 0.42):
            hh = 0.24 * max(0.0, 1.0 - (bb / 0.46) ** 2) ** 0.8 * (0.85 + 0.30 * rg.random()) + 0.012
            row.append((a + rg.uniform(-0.05, 0.05), bb, yb_(a) + hh))
        if prev:
            for k in range(5):
                tone = rg.uniform(0.50, 0.68)
                col = (tone, tone * 0.97, tone * 0.90)
                fb.poly([qV(*P3(*prev[k])), qV(*P3(*prev[k + 1])), qV(*P3(*row[k + 1])), qV(*P3(*row[k]))], col, up=True)
        prev = row
        a += 0.55
    # --- Laufsteg (Gitterrost, Handlauf) an der linken Seite
    wb0, wb1 = -1.72, -0.92
    for (a0, a1) in ((a_lo + 0.4, a_hi - 0.8),):          # (eine Schleife, damit der Block eingerückt bleibt und die Maße beisammen stehen)
        fb.poly([qV(*P3(a0, wb0, yb_(a0) - 0.30)), qV(*P3(a0, wb1, yb_(a0) - 0.30)), qV(*P3(a1, wb1, yb_(a1) - 0.30)), qV(*P3(a1, wb0, yb_(a1) - 0.30))], (0.22, 0.23, 0.24), up=True)
        q_beam(fb, P3(a0, wb0, yb_(a0) - 0.34), P3(a1, wb0, yb_(a1) - 0.34), 0.03, 0.05, steel_d)
        q_beam(fb, P3(a0, wb1, yb_(a0) - 0.34), P3(a1, wb1, yb_(a1) - 0.34), 0.03, 0.05, steel_d)
        q_beam(fb, P3(a0, wb0, yb_(a0) + 0.72), P3(a1, wb0, yb_(a1) + 0.72), 0.02, 0.02, yellow)
        q_beam(fb, P3(a0, wb0, yb_(a0) + 0.36), P3(a1, wb0, yb_(a1) + 0.36), 0.015, 0.015, yellow)
        aa = a0
        while aa <= a1 + 0.01:
            x_, z_ = L(aa, wb0)
            q_fb_tube(fb, (x_, z_, yb_(aa) - 0.30), (x_, z_, yb_(aa) + 0.72), 0.022, 0.022, 5, yellow)
            aa += 2.0
        for ac in (a0 + 1.0, a0 + 5.0, a0 + 9.0, a0 + 13.0, a0 + 17.0):          # Konsolen vom Stringer zum Laufsteg
            if ac < a1:
                q_beam(fb, P3(ac, -0.80, yb_(ac) - 0.30), P3(ac, wb0, yb_(ac) - 0.30), 0.03, 0.04, steel_d)
    # --- Stahlböcke mit Betonfüßen und Verstrebung
    for ak in (-8.0, -4.0, 0.0, 4.0, 8.0):
        yt = yb_(ak) - 0.41
        for sb in (-1, 1):
            lx, lz = L(ak, sb * 0.85)
            q_fb_box(fb, lx, lz, gy - 0.04, gy + 0.26, 0.26, 0.26, ang, conc, top=(0.66, 0.65, 0.62))
            q_fb_box(fb, lx, lz, gy + 0.26, yt, 0.055, 0.055, ang, steel)
        q_beam(fb, P3(ak, -0.85, gy + 0.55), P3(ak, 0.85, yt - 0.30), 0.02, 0.02, steel_d)
        q_beam(fb, P3(ak, 0.85, gy + 0.55), P3(ak, -0.85, yt - 0.30), 0.02, 0.02, steel_d)
        q_beam(fb, P3(ak, -0.85, yt - 0.05), P3(ak, 0.85, yt - 0.05), 0.03, 0.03, steel_d)
    # --- Aufgabetrichter am unteren Ende (gelb, Blechtrichter auf vier Beinen) mit Schlagleisten
    tp = [(a_lo - 2.5, -1.45), (a_lo + 0.9, -1.45), (a_lo + 0.9, 1.45), (a_lo - 2.5, 1.45)]
    bt = [(a_lo - 1.0, -0.62), (a_lo + 0.1, -0.62), (a_lo + 0.1, 0.62), (a_lo - 1.0, 0.62)]
    yt_, yb2 = Y0 + 1.35, Y0 + 0.12
    for k in range(4):
        k2 = (k + 1) % 4
        quad = [qV(*P3(*tp[k], yt_)), qV(*P3(*tp[k2], yt_)), qV(*P3(*bt[k2], yb2)), qV(*P3(*bt[k], yb2))]
        fb.poly(quad, yellow, out_from=qV(*P3(a_lo - 0.8, 0.0, (yt_ + yb2) / 2)), inward=True)
    fb.poly([qV(*P3(*q, yt_ - 0.02)) for q in tp], (0.10, 0.085, 0.07), up=True)            # Füllung im Trichter (dunkles Material)
    for sa in (-1, 1):
        for sbb in (-1, 1):
            lx, lz = L(a_lo - 0.9 + sa * 1.3, sbb * 1.2)
            q_fb_box(fb, lx, lz, gy - 0.02, yt_ - 0.35, 0.07, 0.07, ang, steel_d)
    # Schlagleisten über dem Trichter (Roste): Rundstäbe quer
    for ia in range(6):
        aa = a_lo - 2.3 + ia * 0.5
        q_beam(fb, P3(aa, -1.4, yt_ + 0.03), P3(aa, 1.4, yt_ + 0.03), 0.018, 0.018, steel_d)
    # --- Antriebskopf: Gehäuse, Motor mit Getriebe, Abwurfschurre
    ah = a_hi
    q_fb_box(fb, *L(ah - 0.35, 0.0), yb_(ah) - 0.55, yb_(ah) + 0.62, 0.95, 0.80, ang, steel_d, top=(0.42, 0.44, 0.47))
    q_fb_tube(fb, P3(ah - 0.20, -0.95, yb_(ah) - 0.12), P3(ah - 0.20, 0.95, yb_(ah) - 0.12), 0.20, 0.20, 12, dark)                          # Kopftrommel
    mx, mz = L(ah - 0.55, 1.25)
    q_fb_box(fb, mx, mz, yb_(ah) - 0.45, yb_(ah) + 0.02, 0.38, 0.22, ang, (0.10, 0.30, 0.55), top=(0.14, 0.36, 0.62))                       # Motor (blau)
    q_fb_tube(fb, P3(ah - 0.55, 0.85, yb_(ah) - 0.22), P3(ah - 0.55, 1.12, yb_(ah) - 0.22), 0.11, 0.11, 8, steel)                           # Welle/Getriebe
    for sb in (-1, 1):                                                        # Motorbock
        q_beam(fb, P3(ah - 0.55, sb * 0.18 + 1.25, gy + 0.2), P3(ah - 0.55, sb * 0.18 + 1.25, yb_(ah) - 0.45), 0.035, 0.035, steel_d)
    sh0 = (ah + 0.45, yb_(ah) - 0.35)
    sh1 = (ah + 2.0, yb_(ah) - 1.65)
    q_beam(fb, P3(sh0[0], 0.0, sh0[1]), P3(sh1[0], 0.0, sh1[1]), 0.42, 0.03, steel_d)                                                    # Schurrenboden
    for sb in (-1, 1):
        q_beam(fb, P3(sh0[0], sb * 0.44, sh0[1] + 0.2), P3(sh1[0], sb * 0.44, sh1[1] + 0.2), 0.02, 0.22, steel)
    # Kranhaken-Öse und Warnstreifen am Kopf
    for k in range(4):
        q_fb_box(fb, *L(ah - 0.35 + 0.95, -0.55 + k * 0.37), yb_(ah) - 0.5, yb_(ah) + 0.5, 0.012, 0.13, ang, yellow if k % 2 == 0 else dark)
    # --- LED-Strahler an Kopf und Trichter (echte Lichtquellen; Linsen nur nachts hell)
    hx, hz = L(ah - 0.2, -1.05)
    q_fb_tube(fb, (hx, hz, yb_(ah) + 0.62), (hx, hz, yb_(ah) + 1.35), 0.04, 0.04, 6, steel_d)
    head1 = math.atan2(math.sin(ang) * 1.0, math.cos(ang) * 1.0)
    q_tilt_box(fb, fl, hx + math.cos(ang) * 0.12, hz + math.sin(ang) * 0.12, yb_(ah) + 1.47, head1, math.radians(32), hw=0.22, hd=0.085, hh=0.17)
    add_light(hx + math.cos(ang) * 3.0, hz + math.sin(ang) * 3.0, yb_(ah) + 1.45, Q_FLOOD, 0.55, 11.0, omni=False, glow=0.0)
    tx, tz = L(a_lo - 2.6, 1.1)
    q_fb_tube(fb, (tx, tz, gy), (tx, tz, Y0 + 2.2), 0.045, 0.045, 6, steel_d)
    q_tilt_box(fb, fl, tx + math.cos(ang + math.pi) * 0.12, tz + math.sin(ang + math.pi) * 0.12, Y0 + 2.34, ang, math.radians(34), hw=0.22, hd=0.085, hh=0.17)
    add_light(tx + math.cos(ang) * 2.5, tz + math.sin(ang) * 2.5, Y0 + 2.3, Q_FLOOD, 0.5, 10.0, omni=False, glow=0.0)
    q_bm_object("Foerderband", fb.bm, [M["farbe"]])
    q_bm_object("Foerderband_Linsen", fl.bm, [M["k:lampe"]])
    q_solid_rect(cx, cz, ang, Lb / 2, float(p.get("d", 3.0)) / 2, float(p.get("h", 3.0)), "mauer")
    print("DIORAMA Förderband bei", round(cx, 1), round(cz, 1), "Höhe Kopf", round(Y1, 1))


# ---------------------------------------------------------------- Kleinigkeiten, die die Grube bewohnt wirken lassen
def q_cone(fb, x, z, y0=None):
    """Leitkegel (orange, weißes Reflexband, schwarzer Fuß), 0,7 m hoch."""
    y0 = GROUND_Y if y0 is None else y0
    orange, white, black = (0.95, 0.38, 0.06), (0.92, 0.92, 0.90), (0.07, 0.07, 0.075)
    q_fb_box(fb, x, z, y0, y0 + 0.035, 0.19, 0.19, 0.0, black, top=(0.10, 0.10, 0.11))
    r_at = lambda h: 0.145 - 0.11 * (h / 0.66)
    q_fb_tube(fb, (x, z, y0 + 0.035), (x, z, y0 + 0.24), r_at(0.0), r_at(0.205), 8, orange)
    q_fb_tube(fb, (x, z, y0 + 0.24), (x, z, y0 + 0.42), r_at(0.205), r_at(0.385), 8, white)
    q_fb_tube(fb, (x, z, y0 + 0.42), (x, z, y0 + 0.70), r_at(0.385), 0.025, 8, orange, cap1=orange)


def q_extras():
    """Bauleiter-Geländewagen am Tor des Büros, Leitkegel an den Absperrungen vor dem Graben und der Abkürzung, Pumpe mit Saug- und Druckschlauch am
    Baggersee (Wasserhaltung). Alles Feste hat ein Hindernis; die Kegel (weich) stehen außerhalb des Fahrschlauchs (mindestens HW + 1,4 m)."""
    # --- Geländewagen (weiß, orange Warnleuchte), erster freier Platz vor dem Bürotor
    for x, z, a in ((-76.8, 10.5, math.pi / 2 + 0.12), (-76.8, -0.5, math.pi / 2 - 0.1), (-76.0, 17.0, math.pi / 2 + 0.2), (-74.5, 22.0, 0.3)):
        if q_free(x, z, 2.4, dc_min=HW + 1.8):
            ux, uz = math.cos(a), math.sin(a)
            mesh_objects("Bauleiterauto", kit_car.car_parts(x, z, ux, uz, "gelaendewagen", (0.62, 0.62, 0.60), base_y=GROUND_Y))
            fb, fl = FBuild(), FBuild()
            q_fb_box(fb, x + ux * 0.1, z + uz * 0.1, GROUND_Y + 1.78, GROUND_Y + 1.88, 0.55, 0.12, a + math.pi / 2, (0.12, 0.12, 0.13))                # Dachträger
            q_fb_tube(fb, (x - ux * 0.2, z - uz * 0.2, GROUND_Y + 1.86), (x - ux * 0.2, z - uz * 0.2, GROUND_Y + 1.93), 0.10, 0.09, 8, (0.12, 0.12, 0.13), cap1=(0.12, 0.12, 0.13))
            q_fb_tube(fb, (x - ux * 0.2, z - uz * 0.2, GROUND_Y + 1.93), (x - ux * 0.2, z - uz * 0.2, GROUND_Y + 2.07), 0.085, 0.085, 8, (0.95, 0.55, 0.05), cap1=(0.95, 0.55, 0.05))
            q_bm_object("Bauleiterauto_Zubehoer", fb.bm, [M["farbe"]])
            q_solid_rect(x, z, a, 2.35, 0.97, 1.5, "mauer")
            break
    # --- Leitkegel: je vier an den Schultern vor und hinter dem Graben (auf der Seite der Absperrschranke) und drei an der Einfahrt der Abkürzung
    spots = []
    for g in data.get("gaps", []):
        i0, i1 = int(g["from"] * N), int(g["to"] * N)
        high = base_height(float(g["from"])) > 0.5
        for i_, step in (((i0 - 28) if high else (i0 - 3), -1), (i1 + 3, 1)):
            for k in range(4):
                j = (i_ + step * k * 4) % N
                c, l_ = center[j], left[j]
                for side in (1, -1):
                    spots.append((c.x + l_.x * side * (HW + 1.5), c.y + l_.y * side * (HW + 1.5)))
    for sc in data.get("shortcuts", []):
        j = int(sc["from"] * N) % N
        c, l_ = center[j], left[j]
        for k in range(3):
            jj = (j - 2 - 3 * k) % N
            spots.append((center[jj].x + left[jj].x * (HW + 1.5), center[jj].y + left[jj].y * (HW + 1.5)))
    fb = FBuild()
    n = 0
    for x, z in spots:
        if q_dc(x, z) >= HW + 1.4 and not q_blocked(x, z, 0.3) and (not Q_PIT or not (Q_PIT["hole"][0] - 0.5 < x < Q_PIT["hole"][1] + 0.5 and Q_PIT["hole"][2] - 0.5 < z < Q_PIT["hole"][3] + 0.5)):
            q_cone(fb, x, z, q_ground_y(x, z))
            collide_circle(x, z, 0.2, 0.7, "absperrung")
            n += 1
    q_bm_object("Leitkegel", fb.bm, [M["farbe"]])
    # --- Pumpe am Baggersee: gelbe Motorpumpe auf Kufen am Ufer, Saugschlauch (schwarz, Schwimmer) in den See, Druckschlauch (blau) zum Weg
    lx, lz = Q_LAKE["x"], Q_LAKE["z"]
    px = pz = None
    for dx in np.arange(Q_LAKE["w"] / 2 - 1.0, Q_LAKE["w"] / 2 + 7.0, 0.25):
        for dz in (2.5, 1.5, 3.5):
            if float(q_lake_sdf(np.array([lx + dx]), np.array([lz + dz]))[0]) > 2.2 and q_free(lx + dx, lz + dz, 1.4, dc_min=HW + 3.0):
                px, pz = lx + dx, lz + dz
                break
        if px is not None:
            break
    if px is not None:
        fbp = FBuild()
        a = math.atan2(-1.0, 0.8)
        yel, dark, steel = (0.93, 0.70, 0.07), (0.12, 0.12, 0.13), (0.50, 0.53, 0.57)
        for sb in (-1, 1):
            q_fb_box(fbp, px, pz + sb * 0.32, GROUND_Y, GROUND_Y + 0.07, 0.62, 0.05, 0.0, dark)                             # Kufen
        q_fb_box(fbp, px, pz, GROUND_Y + 0.07, GROUND_Y + 0.14, 0.58, 0.34, 0.0, dark, top=(0.2, 0.2, 0.21))               # Rahmen
        q_fb_box(fbp, px - 0.12, pz, GROUND_Y + 0.14, GROUND_Y + 0.72, 0.30, 0.28, 0.0, yel, top=(0.80, 0.60, 0.05))          # Motor
        q_fb_tube(fbp, (px + 0.28, pz, GROUND_Y + 0.38), (px + 0.28, pz, GROUND_Y + 0.64), 0.17, 0.17, 12, steel, cap1=(0.55, 0.57, 0.6))   # Pumpengehäuse
        q_fb_tube(fbp, (px - 0.30, pz + 0.12, GROUND_Y + 0.72), (px - 0.30, pz + 0.12, GROUND_Y + 0.86), 0.035, 0.035, 6, dark, cap1=dark)  # Auspuff
        q_fb_box(fbp, px - 0.2, pz - 0.18, GROUND_Y + 0.72, GROUND_Y + 0.76, 0.12, 0.08, 0.0, (0.75, 0.15, 0.10))              # Tankdeckel
        # Saugschlauch: Bogen vom Gehäuse in Richtung See (bis 1,6 m ins Wasser)
        sdx, sdz = lx - px, lz - pz
        ln = math.hypot(sdx, sdz)
        sdx, sdz = sdx / ln, sdz / ln
        d_in = 0.0
        while d_in < 30.0 and float(q_lake_sdf(np.array([px + sdx * d_in]), np.array([pz + sdz * d_in]))[0]) > -0.4:
            d_in += 0.1                                                      # Abstand bis ins Wasser (Näherung des Seerands ist zu kurz)
        pts = []
        for t in np.linspace(0.0, 1.0, 12):
            d_ = t * (d_in + 1.3)
            h_ = GROUND_Y + 0.46 * (1.0 - t) + 0.05 + 0.20 * math.sin(math.pi * t) - 0.30 * t * t
            pts.append((px + sdx * d_ + 0.28 * (1 - t), pz + sdz * d_, h_))
        for p0_, p1_ in zip(pts, pts[1:]):
            q_fb_tube(fbp, p0_, p1_, 0.065, 0.065, 6, (0.09, 0.09, 0.10))
        q_fb_tube(fbp, (pts[-1][0], pts[-1][1], pts[-1][2] - 0.02), (pts[-1][0], pts[-1][1], pts[-1][2] + 0.16), 0.13, 0.13, 8, (0.85, 0.30, 0.10), cap1=(0.9, 0.35, 0.12))  # Schwimmer
        # Druckschlauch (blau) vom Motor weg zum Weg
        pr = random.Random(5)
        cur = (px - 0.1, pz + 0.30, GROUND_Y + 0.40)
        dirx, dirz = 0.35, 1.0                                               # nach Süden, weg von der Piste und vom See
        pts = [cur]
        for k in range(8):
            dirx += pr.uniform(-0.25, 0.25)
            dirz += pr.uniform(-0.15, 0.15)
            nrm = math.hypot(dirx, dirz)
            nx_, nz_ = cur[0] + dirx / nrm * 1.3, cur[1] + dirz / nrm * 1.3
            if q_dc(nx_, nz_) < HW + 1.6 or q_blocked(nx_, nz_, 0.3):
                break
            cur = (nx_, nz_, GROUND_Y + (0.40 if k == 0 else 0.065))
            pts.append(cur)
        for p0_, p1_ in zip(pts, pts[1:]):
            q_fb_tube(fbp, p0_, p1_, 0.06, 0.06, 6, (0.12, 0.28, 0.62))
        q_bm_object("Pumpe", fbp.bm, [M["farbe"]])
        q_solid_rect(px, pz, 0.0, 0.8, 0.45, 0.9, "mauer")
        print("DIORAMA Pumpe am See bei", round(px, 1), round(pz, 1))
    print("DIORAMA Leitkegel:", n)


# ---------------------------------------------------------------- Felswand-Modelle der Streckendatei auf den Bänken
Q_BASE_Y = {}                                  # (x, z) der Felswände -> Standhöhe (aus dem Gelände unter der Grundfläche)


def q_base_y(x, z):
    """Bodenhöhe für Laufzeit-Bauteile: Felswände nach ihrer Grundfläche, sonst die Höhe des Geländes am Ort."""
    return Q_BASE_Y.get((round(x, 2), round(z, 2)), q_ground_y(x, z))


def q_plan_wall_heights():
    """Die 22 Felswand-Modelle (steinbruch_felswand, 16 x 8 m Grundfläche, z = +-58) stehen im Spiel auf Höhe 0, das Gelände ist dort 5 bis 6 m
    hoch (dritte Bank): sie versänken halb im Hang. Standhöhe = niedrigster Geländepunkt unter der Grundfläche (nichts schwebt; wo der Hang
    höher liegt, steckt die Wand ein Stück darin), mit 25 cm Einsatz."""
    n = 0
    for p in Q_AI:
        if p.get("model") != "steinbruch_felswand":
            continue
        x, z = float(p["x"]), float(p["z"])
        w, d = float(p.get("w", 16.0)), float(p.get("d", 10.0))
        xs = np.linspace(x - w / 2, x + w / 2, 9)
        zs = np.linspace(z - d * 0.4, z + d * 0.4, 5)
        X, Z = np.meshgrid(xs, zs)
        P = np.stack([X.ravel(), Z.ravel()], 1)
        h = GROUND_Y + q_rel(P)
        Q_BASE_Y[(round(x, 2), round(z, 2))] = float(np.percentile(h, 12)) - 0.25
        n += 1
    return n


# ---------------------------------------------------------------- Szenerie (überschreibt die vorläufige Fassung oben)
def q_fences(placed):
    pts = [(-97.0, -4.0), (-79.0, -4.0), (-79.0, 14.0), (-97.0, 14.0)]
    n = q_fence(pts, closed=True, gaps=[(-79.0, 5.5, 3.4)])
    if "tankstelle" in placed:
        tx, tz = placed["tankstelle"]
        rect = [(tx - 5.6, tz - 4.6), (tx + 5.6, tz - 4.6), (tx + 5.6, tz + 4.6), (tx - 5.6, tz + 4.6)]
        n += q_fence(rect, closed=True, gaps=[(tx + 5.6, tz, 3.2)])
    if placed.get("bloecke"):
        n += q_fence([(-52.0, 24.4), (-24.0, 24.9)], closed=False)
    print("DIORAMA Bauzaunfelder:", n)


def theme_scenery():
    q_levels_build()
    q_crown_build()
    q_foot_walls()
    q_riser_blocks()
    placed = q_site()
    q_pit_build()
    q_conveyor()
    q_extras()
    q_heaps()
    q_fences(placed)
    q_lamps_and_misc()
    q_lights()
    q_boulders()
    q_ruts()
    q_puddles()
    # Bodenhöhe der Laufzeit-Bauteile (KI-Modelle, Laternen): sie stehen im Spiel auf Höhe 0; die Felswände auf den hohen Bänken (z = +-58)
    # versänken sonst im Hang. Dieselbe Höhenfunktion gilt für die Kontaktschatten (ao_proxies).
    q_plan_wall_heights()
    # Das Spiel setzt Laufzeit-Bauteile auf terrain_height + prop_y: eingetragen wird nur der Unterschied zum Geländeraster der Streckendatei.
    n_h = set_prop_heights(lambda x, z: q_base_y(x, z) - terrain_y(x, z), types=["ai"])
    # Die selbst gebauten Kieshaufen brauchen keinen Stellvertreter (ihr Netz wirft den Kontaktschatten selbst).
    hidden = [(p, p["type"]) for p in Q_HEAP_AI] + [(p, p["type"]) for p in Q_AI if p.get("model") == "steinbruch_foerderband"]
    for p, _ in hidden:
        p["type"] = "ai_gebaut"
    ao_proxies(types=["ai", "lamp"], base_y=q_base_y)
    for p, t in hidden:
        p["type"] = t
    print("DIORAMA Bodenhöhen für Laufzeit-Bauteile:", n_h, "| Felswände:", len(Q_BASE_Y))
    q_report()


# ---------------------------------------------------------------- Felsschollen an den Böschungen
def q_scholle(seed):
    """Kantige Felsscholle (leicht verformter, unterteilter Quader, flach schattiert, Kalkstein-Textur); Fuß auf z = 0, Maße etwa 1 x 1 x 1 m."""
    key = "scholle%d" % seed
    if key in LIB:
        return key
    r = random.Random(seed * 19 + 4)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=1, use_grid_fill=True)
    off = Vector((seed * 2.3, 4.1, 1.9))
    for v in bm.verts:
        n = v.co.normalized()
        v.co += Vector((r.uniform(-1, 1) * 0.07, r.uniform(-1, 1) * 0.07, r.uniform(-1, 1) * 0.06)) + n * (noise.noise(v.co * 3.2 + off) * 0.10)
        v.co.z += 0.5
    for f in bm.faces:
        f.smooth = False
    bm.normal_update()
    uv = bm.loops.layers.uv.new("UVMap")
    col = bm.loops.layers.float_color.new("Color")
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda k: abs(n[k]))
        tone = r.uniform(0.82, 1.08)
        for loop in f.loops:
            p = loop.vert.co
            u, w = ((p.y, p.z), (p.x, p.z), (p.x, p.y))[ax]
            loop[uv].uv = (u / 1.2 + seed * 0.37, w / 1.2)
            sh = (0.58 + 0.42 * min(1.0, max(0.0, p.z))) * tone
            loop[col] = (sh, sh * 0.99, sh * 0.95, 1.0)
    obj = q_bm_object(key, bm, [M["q_fels"]], link=False)
    return q_register(key, obj)


def q_put_nu(name, x, z, ang, sx, sy, sz, y, lean=0.0):
    """Wie q_put, aber mit ungleichmäßiger Skalierung (Länge, Tiefe, Höhe) und Neigung um die Längsachse; Ursprung des Modells ist der Fuß."""
    obj, ext = model(name)
    inst = obj.copy()
    inst.name = "Prop_%s" % name
    scene.collection.objects.link(inst)
    inst.matrix_world = (Matrix.Translation((x, -z, y)) @ Matrix.Rotation(-ang, 4, "Z") @ Matrix.Rotation(lean, 4, "X")
                         @ Matrix.Diagonal((sx, sy, sz, 1.0)))
    return inst


def q_riser_blocks(limit=620):
    """Felsschollen auf den steilen Böschungen: Längsachse entlang der Höhenlinie, in den Hang eingelassen und mit dem Hang geneigt
    (schichtiges Mauerwerk der Bänke)."""
    rng_ = np.random.default_rng(23)
    pr = random.Random(3)
    P = np.stack([rng_.uniform(x0 + 4, x1 - 4, 80000), rng_.uniform(z0 + 4, z1 - 4, 80000)], 1)
    u = q_u(P)
    sel = (u > 0.3) & (u < 2 * Q_PERIOD + 3.0)
    P, u = P[sel], u[sel]
    e = 0.5
    ex, ez = np.array([e, 0.0]), np.array([0.0, e])
    hx = (q_height(P + ex, q_u(P + ex)) - q_height(P - ex, q_u(P - ex))) / (2 * e)
    hz = (q_height(P + ez, q_u(P + ez)) - q_height(P - ez, q_u(P - ez))) / (2 * e)
    slope = np.hypot(hx, hz)
    h = q_rel(P)
    keep = slope > 0.6
    for f in Q_FACES:                                                   # nicht auf die Bruchwände
        al, cr = q_face_coords(P, f)
        keep &= ~((al > f["a0"] - 1.0) & (al < f["a1"] + 1.0) & (np.abs(cr) < 1.8))
    cnt = 0
    taken = {}
    for i in rng_.permutation(np.nonzero(keep)[0]):
        if cnt >= limit:
            break
        x, z = float(P[i, 0]), float(P[i, 1])
        cell = (int(x // 1.9), int(z // 1.9))
        if cell in taken:
            continue
        taken[cell] = True
        gn = np.array([hx[i], hz[i]]) / (slope[i] + 1e-9)
        ang = math.atan2(gn[0], -gn[1])
        sx_, sy_, sz_ = pr.uniform(1.5, 3.2), pr.uniform(0.9, 1.6), pr.uniform(0.7, 1.4)
        if Q_EAST and q_dc(x, z) < 14.0:                                # Felswand Ost dicht an der Fahrrampe: flache, kleinere Schollen
            if pr.random() < 0.5:
                continue
            sx_, sy_, sz_ = sx_ * 0.6, sy_ * 0.6, sz_ * 0.45
        lean = math.atan(float(slope[i])) * 0.75
        key = q_scholle(int(abs(x * 1.3 + z * 2.1)) % 4)
        q_put_nu(key, x, z, ang, sx_, sy_, sz_, GROUND_Y + float(h[i]) - 0.35 * sz_, lean)
        cnt += 1
    print("DIORAMA Felsschollen:", cnt)


# ---------------------------------------------------------------- Bruchkante Ost (Fassung 2): Bruchwände, Sicherheitswall, Schanzenschüttung, Landelippe, Schild
def q_snap_faces(obj):
    """Senkrechte Bruchwand im Bodennetz: Die beiden Knotenreihen beidseits einer Wandlinie (je 0,5 m entfernt) rücken auf 3 cm an die Linie;
    aus dem 1-m-Übergang wird eine fast senkrechte Wand an der Kante des Hindernisses (die Reihen bleiben gerade, keine Risse)."""
    if not Q_FACES:
        return 0
    me = obj.data
    n_moved = 0
    for v in me.vertices:
        p = np.array([v.co.x, -v.co.y])
        for f in Q_FACES:
            rel = p - f["o"]
            al, cr = float(rel @ f["a"]), float(rel @ f["n"])
            if f["a0"] - 0.6 <= al <= f["a1"] + 0.6 and abs(cr) < 0.9:
                new = 0.03 if cr > 0 else -0.03
                d = f["n"] * (new - cr)
                v.co.x += float(d[0])
                v.co.y -= float(d[1])
                n_moved += 1
                break
    me.update()
    return n_moved


def q_face_ledge_factor(A, far):
    """Bankstufe nur in langen Abschnitten abseits der Fahrbahn; an den Enden über 1,5 m auslaufend."""
    Lf = np.zeros(len(A))
    idx_far = np.nonzero(far)[0]
    if len(idx_far) == 0:
        return Lf
    near_pts = A[~far]
    for i in idx_far:
        d = float(np.abs(near_pts - A[i]).min()) if len(near_pts) else 99.0
        d = min(d, A[i] - A[0] + 0.5, A[-1] - A[i] + 0.5)
        Lf[i] = min(1.0, max(0.0, (d - 0.5) / 1.5))
    return Lf


def q_faces_build():
    """Bruchwände (Kante der oberen Sohle, Landelippe ausgenommen): gesprengte Kalksteinwand mit Bohrlochpfeifen (senkrechte Halbrinnen alle
    2,6 bis 3,6 m), leicht zerklüftet, am Fuß feucht, oben verwittert; abseits der Fahrbahn eine Bankstufe auf halber Höhe (unterer Teil 1,1 m vor
    der Wand). Die Wand steht 7 bis 23 cm vor der senkrechten Stufe des Bodennetzes; Hindernisse hat die Streckendatei (Bruchwand-collider)."""
    rr = random.Random(41)
    n_faces = 0
    for k, f in enumerate(Q_FACES):
        if f["h"] < 4.0:
            continue                                         # Landelippe: eigene Mauer (q_lip_build)
        a0, a1 = f["a0"], f["a1"]
        holes = []
        t = a0 + rr.uniform(0.6, 1.8)
        while t < a1 - 0.4:
            holes.append(t)
            t += rr.uniform(2.6, 3.6)
        cols = list(np.arange(a0, a1 + 1e-6, 0.5))
        for hp in holes:
            cols += [hp - 0.14, hp - 0.07, hp, hp + 0.07, hp + 0.14]
        A = np.array(sorted(set(round(float(c), 3) for c in cols if a0 <= c <= a1)))
        line = f["o"][None, :] + A[:, None] * f["a"][None, :]
        y_lo = GROUND_Y + q_rel(line + f["n"] * 0.7)
        y_hi = GROUND_Y + q_rel(line - f["n"] * 0.7)
        far = (dist_to_center(line + f["n"] * 2.0) > 14.0) & ((y_hi - y_lo) > 4.0)
        Lf = q_face_ledge_factor(A, far)
        groove = np.zeros(len(A))
        for hp in holes:
            groove = np.maximum(groove, 0.085 * np.cos(np.clip(np.abs(A - hp) / 0.14, 0.0, 1.0) * math.pi / 2))
        parts = []

        def rowpts(i, t_rows, ya, yb, extra):
            out = []
            for t_ in t_rows:
                y = ya + (yb - ya) * t_
                j = float(q_noise(np.array([A[i] * 1.0]), np.array([y * 1.3]), 2.6, 3.1 + k)[0])
                off = 0.11 + 0.07 * j - groove[i] + extra
                p = line[i] + f["n"] * off
                tone = (0.80 + 0.12 * j) * (1.0 - 1.6 * groove[i])
                if y - y_lo[i] < 0.45:
                    tone *= 0.62 + 0.38 * max(0.0, y - y_lo[i]) / 0.45          # feuchter Fuß
                if y_hi[i] - y < 0.35:
                    tone *= 1.08                                              # verwitterte Oberkante
                streak = float(q_noise(np.array([A[i] * 3.0]), np.array([0.0]), 1.0, 7.7 + k)[0])
                if streak > 0.78:
                    tone *= 0.88                                              # dunkle Laufspuren von oben
                tone = max(0.25, min(1.05, tone))
                out.append(((float(p[0]), float(p[1]), float(y)), (tone, tone * 0.98, tone * 0.93), (float(A[i]) / 2.4, float(y) / 2.4)))
            return out
        lower_t, upper_t = (0.0, 0.18, 0.5, 0.8, 1.0), (0.0, 0.3, 0.62, 1.0)
        prev = None
        for i in range(len(A)):
            ym = y_lo[i] + (y_hi[i] - y_lo[i]) * 0.48
            lo_rows = rowpts(i, lower_t, y_lo[i] - 0.08, ym, 1.1 * Lf[i])
            up_rows = rowpts(i, upper_t, ym, y_hi[i] + 0.02, 0.0)
            cur = (lo_rows, up_rows)
            if prev is not None and min(y_hi[i] - y_lo[i], y_hi[i - 1] - y_lo[i - 1]) > 0.4:
                for rows_a, rows_b in ((prev[0], cur[0]), (prev[1], cur[1])):
                    for r_ in range(len(rows_a) - 1):
                        q = [rows_a[r_], rows_b[r_], rows_b[r_ + 1], rows_a[r_ + 1]]
                        parts.append(("q_fels", [c[0] for c in q], [c[2] for c in q], (float(f["n"][0]), float(f["n"][1])), [c[1] for c in q]))
                # Absatz der Bankstufe (waagerecht) zwischen unterem Teil und Wand
                if Lf[i] > 0.01 or Lf[i - 1] > 0.01:
                    q = [prev[0][-1], cur[0][-1], cur[1][0], prev[1][0]]
                    parts.append(("q_fels", [c[0] for c in q], [(c[0][0] / 2.4, c[0][1] / 2.4) for c in q], None, [tuple(v * 1.05 for v in c[1]) for c in q]))
                # Krone: Kante 28 cm zurück auf die obere Sohle (deckt den Spalt zur Bodenstufe)
                ta, tb = prev[1][-1], cur[1][-1]
                ba = (float(line[i - 1][0] - f["n"][0] * 0.28), float(line[i - 1][1] - f["n"][1] * 0.28), ta[0][2])
                bb = (float(line[i][0] - f["n"][0] * 0.28), float(line[i][1] - f["n"][1] * 0.28), tb[0][2])
                crown = (0.86, 0.84, 0.79)
                q = [(ta[0], crown), (tb[0], crown), (bb, crown), (ba, crown)]
                parts.append(("q_fels", [c[0] for c in q], [(c[0][0] / 2.4, c[0][1] / 2.4) for c in q], None, [c[1] for c in q]))     # waagerecht: UV planar
            prev = cur
        if parts:
            mesh_object("Bruchwand_%d" % k, parts)
            n_faces += 1
        print("DIORAMA Bruchwand %d: %.1f m, Bohrlöcher %d, Bankstufe auf %.0f m" % (k, a1 - a0, len(holes), float((Lf > 0.5).sum()) * 0.5))
    return n_faces


def q_rubble_strip(name, stations, rr, mat="q_schotter", tone=(0.92, 0.90, 0.86)):
    """Haufwerk als Band: stations = Liste (Punkt (x, z), Querrichtung (x, z), [(Querversatz, Höhe), ...]) mit gleicher Profilzahl; Höhen absolut."""
    parts = []
    m = len(stations[0][2])
    for (pa, na, pra), (pb, nb, prb) in zip(stations, stations[1:]):
        for j in range(m - 1):
            q = [(pa, na, pra[j]), (pb, nb, prb[j]), (pb, nb, prb[j + 1]), (pa, na, pra[j + 1])]
            pts, uvs, cols = [], [], []
            for p_, n_, (off, y) in q:
                x, z = p_[0] + n_[0] * off, p_[1] + n_[1] * off
                pts.append((x, z, y))
                uvs.append((x / 1.6, z / 1.6))
                sh = rr.uniform(0.86, 1.04)
                cols.append((tone[0] * sh, tone[1] * sh, tone[2] * sh))
            parts.append((mat, pts, uvs, None, cols))
    return mesh_object(name, parts) if parts else None


def q_berms_build():
    """Sicherheitswall aus Haufwerk entlang der sichtbaren Wall-Hindernisse der Streckendatei (absperrung, 1,0 m über der Unterkante b):
    durchgehender Schüttwall (Fuß 1,5 m, Krone 0,35 m) mit eingesetzten Brocken, Lage und Höhe wie die Hindernisse."""
    walls = [p for p in data["props"] if p.get("type") == "collider" and p.get("kind") == "absperrung" and bool(p.get("visible", True))]
    if not walls:
        return 0
    rr = random.Random(9)
    rest = list(walls)
    chains = []
    while rest:
        ch = [rest.pop(0)]
        grown = True
        while grown:
            grown = False
            for end in (0, -1):
                e = ch[end]
                for w in list(rest):
                    if math.hypot(w["x"] - e["x"], w["z"] - e["z"]) < 0.5 * (w["w"] + e["w"]) + 1.2:
                        rest.remove(w)
                        if end == 0:
                            ch.insert(0, w)
                        else:
                            ch.append(w)
                        grown = True
                        break
        chains.append(ch)
    n = 0
    prof = ((-0.78, 0.0), (-0.52, 0.42), (-0.26, 0.86), (0.0, 1.0), (0.26, 0.86), (0.52, 0.42), (0.78, 0.0))
    for ci, ch in enumerate(chains):
        pts = [np.array([w["x"], w["z"]], float) for w in ch]
        bs = [float(w.get("b", 0.0)) for w in ch]
        hs = [float(w.get("h", 1.0)) for w in ch]
        if len(pts) >= 2:
            d0 = (pts[0] - pts[1]) / (np.linalg.norm(pts[0] - pts[1]) + 1e-9)
            d1 = (pts[-1] - pts[-2]) / (np.linalg.norm(pts[-1] - pts[-2]) + 1e-9)
        else:
            r_ = math.radians(ch[0].get("rot", 0.0))
            d0, d1 = -np.array([math.cos(r_), math.sin(r_)]), np.array([math.cos(r_), math.sin(r_)])
        pts = [pts[0] + d0 * ch[0]["w"] * 0.5] + pts + [pts[-1] + d1 * ch[-1]["w"] * 0.5]
        bs = [bs[0]] + bs + [bs[-1]]
        hs = [hs[0]] + hs + [hs[-1]]
        seg = [float(np.linalg.norm(b - a)) for a, b in zip(pts, pts[1:])]
        tot = sum(seg)
        stations = []
        nst = max(2, int(tot / 0.5) + 1)
        for k in range(nst):
            d = tot * k / (nst - 1)
            acc, j = 0.0, 0
            while j < len(seg) - 1 and acc + seg[j] < d:
                acc += seg[j]
                j += 1
            t_ = min(1.0, (d - acc) / (seg[j] + 1e-9))
            p = pts[j] + (pts[j + 1] - pts[j]) * t_
            tdir = (pts[j + 1] - pts[j]) / (seg[j] + 1e-9)
            nrm = np.array([-tdir[1], tdir[0]])
            b = bs[j] + (bs[j + 1] - bs[j]) * t_
            h = hs[j] + (hs[j + 1] - hs[j]) * t_
            taper = min(1.0, d / 0.9, (tot - d) / 0.9)
            gy = GROUND_Y + b
            row = []
            for off, hh in prof:
                inner = 0 < abs(off) < 0.7
                y = gy - 0.04 + (h + 0.04) * hh * (0.25 + 0.75 * taper) + (rr.uniform(-0.08, 0.06) if inner else 0.0)
                row.append((off * (0.75 + 0.25 * taper) + (rr.uniform(-0.07, 0.07) if inner else 0.0), y))
            stations.append(((float(p[0]), float(p[1])), (float(nrm[0]), float(nrm[1])), row))
            Q_SOLIDS.append((float(p[0]), float(p[1]), 0.85))
            if k % 3 == 1 and rr.random() < 0.55:                       # Brocken auf der Krone und an den Flanken
                side = rr.choice((-0.45, 0.0, 0.4))
                sz_ = rr.uniform(0.35, 0.6)
                bx, bz = p[0] + nrm[0] * side, p[1] + nrm[1] * side
                q_put(q_boulder(rr.randint(0, 4)), float(bx), float(bz), rr.uniform(0, 6.28), scale=sz_,
                      y=gy + h * (0.95 if side == 0.0 else 0.55) - 0.25 * sz_, anchor="origin")
        q_rubble_strip("Sicherheitswall_%d" % ci, stations, rr, "q_schotter", (0.80, 0.77, 0.72))
        n += 1
    print("DIORAMA Sicherheitswall: Ketten", n, "aus", len(walls), "Hindernissen")
    return n


def q_kicker_rubble():
    """Holzschanze an der Bruchkante mit Bruchstein umschüttet: beidseits der Schanzenwangen (ab 3,28 m Querabstand) eine Schüttung bis knapp
    unter die Schanzenkante, nach außen auf die obere Sohle auslaufend; vor der Schanze 1,5 m Anlauf."""
    rr = random.Random(23)
    n = 0
    for r in data.get("ramps", []):
        s0, L_ = float(r["s"]), float(r["length"])
        se = s0 + L_ / TOTAL
        if not any(abs(((float(g["from"]) - se + 0.5) % 1.0) - 0.5) * TOTAL < 1.5 for g in data.get("gaps", [])):
            continue                                                   # nur die Schanze an einer Lücke (Bruchkante)
        if base_height(s0) < 0.5:
            continue
        for side in (-1.0, 1.0):
            stations = []
            k_n = int((L_ + 1.5) / 0.4) + 1
            for k in range(k_n):
                d = -1.5 + (L_ + 1.5) * k / (k_n - 1)
                s = s0 + d / TOTAL
                i = int((s % 1.0) * N) % N
                c = np.array([center[i].x, center[i].y])
                nl = np.array([left[i].x, left[i].y])
                base = float(q_base_at(np.array([s]))[0])
                hk = float(r["height"]) * max(0.0, d) / L_
                top = base + hk + 0.2 - 0.06
                g0 = GROUND_Y + base
                row = []
                for off, w in ((3.28, 1.0), (3.6, 0.92), (4.1, 0.7), (4.7, 0.35), (5.4, 0.0)):
                    if d < 0:
                        y = g0 - 0.03 + 0.12 * w * (1.5 + d) / 1.5
                    elif w > 0:
                        y = g0 - 0.03 + max(0.0, top - g0) * w * (0.92 + 0.12 * rr.random())
                    else:
                        y = g0 - 0.03
                    row.append((side * off, y))
                stations.append(((float(c[0]), float(c[1])), (float(nl[0]), float(nl[1])), row))
                for off in (3.6, 4.4):
                    Q_SOLIDS.append((float(c[0] + nl[0] * side * off), float(c[1] + nl[1] * side * off), 0.5))
                if k % 2 == 0 and d > 0.3 and rr.random() < 0.7:
                    sz_ = rr.uniform(0.3, 0.55)
                    off = rr.uniform(3.7, 4.6)
                    bx, bz = c + nl * side * off
                    hgt = g0 + max(0.0, top - g0) * max(0.0, 1.0 - (off - 3.28) / 2.1)
                    q_put(q_boulder(rr.randint(0, 4)), float(bx), float(bz), rr.uniform(0, 6.28), scale=sz_, y=hgt - 0.3 * sz_, anchor="origin")
            q_rubble_strip("Schanzenschuettung_%d" % int(side > 0), stations, rr, "q_fels", (0.88, 0.86, 0.82))
            n += 1
    print("DIORAMA Schanze an der Bruchkante umschüttet:", n, "Seiten")
    return n


def q_lip_build():
    """Landelippe: Stützmauer aus Betonblöcken (1,6 x 0,8 m, versetzt, dunkle Fugen) an der Stirnseite des Schüttkegels und eine verkratzte Stahlkante
    (Stirnblech mit Kratzern und Rost, Oberflansch unter dem Fahrbahnende) über die ganze Dammkrone."""
    faces = [f for f in Q_FACES if f["h"] < 4.0]
    if not faces:
        return 0
    rr = random.Random(5)
    fb = FBuild()
    for f in faces:
        a0, a1 = f["a0"] + 0.1, f["a1"] - 0.1
        A = np.linspace(a0, a1, 7)
        line = f["o"][None, :] + A[:, None] * f["a"][None, :]
        y_lo = float((GROUND_Y + q_rel(line + f["n"] * 0.7)).min())
        s_l, _, _ = q_track_s(f["o"][None, :] - f["n"][None, :] * 0.05)
        y_top = float(q_base_at(s_l)[0]) + 0.155                           # knapp unter der Fahrbahn (Basis + 0,17) an der Lippe
        steel_h = 0.62
        y_b = y_top - steel_h
        nf = f["n"]
        c2 = f["o"] - nf * 2.0
        cen = qV(float(c2[0]), float(c2[1]), 0.5 * (y_lo + y_top))      # Punkt im Damm: Flächen zeigen von ihm weg (zur Lücke)
        joint = (0.24, 0.24, 0.23)

        def P(al, off, y):
            p = f["o"] + f["a"] * al + nf * off
            return qV(float(p[0]), float(p[1]), y)
        fb.poly([P(a0, 0.05, y_lo - 0.05), P(a1, 0.05, y_lo - 0.05), P(a1, 0.05, y_b), P(a0, 0.05, y_b)], joint, out_from=cen)
        courses = max(1, int(math.ceil((y_b - y_lo) / 0.8)))
        hc = (y_b - y_lo) / courses
        for c_ in range(courses):
            ya, yb_ = y_lo + c_ * hc, y_lo + (c_ + 1) * hc
            al = a0 - (0.8 if c_ % 2 else 0.0)
            while al < a1:
                b0, b1 = max(a0, al), min(a1, al + 1.6)
                if b1 - b0 > 0.15:
                    off = 0.09 + rr.uniform(-0.015, 0.02)
                    tone = rr.uniform(0.56, 0.68)
                    col = (tone, tone * 0.99, tone * 0.95)
                    col_t = tuple(v * 1.06 for v in col)
                    fb.poly([P(b0 + 0.025, off, ya + 0.025), P(b1 - 0.025, off, ya + 0.025), P(b1 - 0.025, off, yb_ - 0.025), P(b0 + 0.025, off, yb_ - 0.025)],
                            [col, col, col_t, col_t], out_from=cen)
                    fb.poly([P(b0 + 0.025, off, yb_ - 0.025), P(b1 - 0.025, off, yb_ - 0.025), P(b1 - 0.025, 0.06, yb_), P(b0 + 0.025, 0.06, yb_)],
                            tuple(v * 1.1 for v in col), out_from=cen)
                al += 1.6
        al = a0
        while al < a1 - 1e-6:
            b1 = min(a1, al + 0.2)
            v = rr.random()
            base_c = (0.27, 0.28, 0.30)
            if v < 0.22:
                base_c = (0.52, 0.53, 0.55)            # blank gekratzt
            elif v < 0.36:
                base_c = (0.42, 0.27, 0.15)            # Rost
            top_c = tuple(min(1.0, x * 1.25) for x in base_c)
            fb.poly([P(al, 0.13, y_b), P(b1, 0.13, y_b), P(b1, 0.13, y_top), P(al, 0.13, y_top)], [base_c, base_c, top_c, top_c], out_from=cen)
            al = b1
        fb.poly([P(a0, 0.13, y_top), P(a1, 0.13, y_top), P(a1, -0.32, y_top), P(a0, -0.32, y_top)], (0.36, 0.37, 0.39), up=True)
        fb.poly([P(a0, 0.13, y_b), P(a1, 0.13, y_b), P(a1, 0.05, y_b - 0.02), P(a0, 0.05, y_b - 0.02)], (0.20, 0.20, 0.21), out_from=cen)
        for sgn, al_ in ((-1, a0), (1, a1)):
            ref = f["o"] + f["a"] * (al_ - sgn)
            fb.poly([P(al_, 0.13, y_b), P(al_, -0.32, y_b), P(al_, -0.32, y_top), P(al_, 0.13, y_top)], (0.25, 0.26, 0.28),
                    out_from=qV(float(ref[0]), float(ref[1]), y_b))
        print("DIORAMA Landelippe: Betonblöcke %d Lagen, Stahlkante %.2f bis %.2f m" % (courses, y_b, y_top))
    q_bm_object("Landelippe", fb.bm, [M["farbe"]])
    return len(faces)


def q_blast_sign(x, z, ang):
    """Warnschild "Sprengbereich": gelbes Dreieck mit schwarzem Rand und schwarzem Sprengzeichen (Stern), darunter weiße Zusatztafel mit rotem Balken und
    schwarzer Schriftzeile; Stahlmast mit Betonfuß. Blickt in Richtung ang."""
    fb = FBuild()
    gy = q_ground_y(x, z)
    f_ = (math.cos(ang), math.sin(ang))
    sd = (-math.sin(ang), math.cos(ang))
    steel, yellow, black, white, red = (0.58, 0.60, 0.62), (0.96, 0.78, 0.06), (0.06, 0.06, 0.06), (0.95, 0.95, 0.93), (0.80, 0.08, 0.06)
    q_fb_box(fb, x, z, gy - 0.1, gy + 0.18, 0.22, 0.22, ang, (0.60, 0.59, 0.56))
    q_fb_tube(fb, (x, z, gy + 0.18), (x, z, gy + 2.55), 0.04, 0.04, 8, steel, cap1=steel)
    cx, cz = x + f_[0] * 0.06, z + f_[1] * 0.06
    behind = qV(cx - f_[0], cz - f_[1], gy + 1.9)

    def V(a, h, o=0.0):
        return qV(cx + sd[0] * a + f_[0] * o, cz + sd[1] * a + f_[1] * o, h)
    yb, s_ = gy + 1.62, 0.92

    def tri(sc, o):
        lift = 0.06 * (1 - sc)
        return [V(-s_ / 2 * sc, yb + lift, o), V(s_ / 2 * sc, yb + lift, o), V(0.0, yb + lift + s_ * 0.866 * sc, o)]
    fb.poly(tri(1.0, 0.0), black, out_from=behind)
    fb.poly(tri(0.82, 0.01), yellow, out_from=behind)
    cy = yb + 0.31
    star = []
    for k in range(16):
        r = 0.16 if k % 2 == 0 else 0.065
        th = math.pi / 2 + k * math.pi / 8
        star.append((math.cos(th) * r, cy + math.sin(th) * r))
    for k in range(16):
        a_, b_ = star[k], star[(k + 1) % 16]
        fb.poly([V(0.0, cy, 0.02), V(a_[0], a_[1], 0.02), V(b_[0], b_[1], 0.02)], black, out_from=behind)
    pa, pb = yb - 0.42, yb - 0.06
    fb.poly([V(-0.42, pa, 0.0), V(0.42, pa, 0.0), V(0.42, pb, 0.0), V(-0.42, pb, 0.0)], white, out_from=behind)
    fb.poly([V(-0.42, pb - 0.07, 0.01), V(0.42, pb - 0.07, 0.01), V(0.42, pb, 0.01), V(-0.42, pb, 0.01)], red, out_from=behind)
    for k in range(7):
        a_ = -0.33 + k * 0.1
        fb.poly([V(a_, pa + 0.09, 0.01), V(a_ + 0.07, pa + 0.09, 0.01), V(a_ + 0.07, pa + 0.2, 0.01), V(a_, pa + 0.2, 0.01)], black, out_from=behind)
    fb.poly([V(-s_ / 2, yb, -0.01), V(s_ / 2, yb, -0.01), V(0.0, yb + s_ * 0.866, -0.01)], (0.55, 0.56, 0.57),
            out_from=qV(cx + f_[0], cz + f_[1], gy + 1.9))
    q_bm_object("Schild_Sprengbereich", fb.bm, [M["farbe"]])
    q_solid(x, z, 0.24, 2.6, "mast")


def q_levels_build():
    """Alle Bauteile der Bruchkante (vor der übrigen Aufstellung, damit deren Flächen als belegt gelten)."""
    if not Q_TER:
        return
    q_faces_build()
    q_berms_build()
    q_kicker_rubble()
    q_lip_build()
    for g in data.get("gaps", []):
        if base_height(float(g["from"])) < 0.5:
            continue
        s = float(g["from"]) - 15.0 / TOTAL
        i = int((s % 1.0) * N) % N
        c, t = np.array([center[i].x, center[i].y]), np.array([tang[i].x, tang[i].y])
        nl = np.array([left[i].x, left[i].y])
        best = None
        for side in (1.0, -1.0):
            p = c + nl * side * (HW + 2.8)
            pp = c + nl * side * 9.0
            if abs(float(q_rel(np.array([pp]))[0]) - float(q_base_at(np.array([s]))[0])) < 0.3 and not q_blocked(float(p[0]), float(p[1]), 0.5):
                best = p
                break
        if best is not None:
            q_blast_sign(float(best[0]), float(best[1]), math.atan2(-t[1], -t[0]))
            print("DIORAMA Schild Sprengbereich bei", round(float(best[0]), 1), round(float(best[1]), 1))


def q_crown_build():
    """Dammkrone unter der Laufzeit-Fahrbahn auf den Rampen (Fahrrampe, Landerampe): ebenes Schotterband ±4,3 m auf Basis + 0,10 (7 cm unter der
    Fahrbahn, Basis exakt je 0,5 m) mit kurzen Schürzen an den Rändern. Das Bodennetz liegt dort tiefer (Kernprüfung, q_mesh_h). Die Krone
    wird erst hier (nach der Kernprüfung) an objs_ground gehängt und bekommt so die Lichttextur; sie liegt nach Bauart unter der Fahrbahn
    und wird unten selbst geprüft."""
    if not Q_DAMS:
        return 0
    parts = []
    col = (0.93, 0.72, 0.19)
    worst = -1.0
    for s0, s1 in Q_DAMS:
        if (s1 - s0) % 1.0 < 1e-4:
            continue
        i0, i1 = int(math.floor((s0 % 1.0) * N)) - 4, int(math.ceil((s1 % 1.0) * N)) + 4
        rows = []
        for i in range(i0, i1 + 1):
            k = i % N
            if in_gap(float(S_OF[k])):
                rows.append(None)
                continue
            c, l_ = center[k], left[k]
            y = float(Q_BASE_TAB[k]) + 0.10
            worst = max(worst, y - (float(Q_BASE_TAB[k]) + ROAD_Y - 0.01))
            row = []
            for off, dy in ((-4.36, -0.6), (-4.3, 0.0), (0.0, 0.0), (4.3, 0.0), (4.36, -0.6)):
                row.append((c.x + l_.x * off, c.y + l_.y * off, y + dy))
            rows.append(row)
        for a, b in zip(rows, rows[1:]):
            if a is None or b is None:
                continue
            for j in range(4):
                q = [a[j], b[j], b[j + 1], a[j + 1]]
                facing = None
                if j in (0, 3):
                    mx = (a[j][0] + b[j][0]) / 2 - (a[2][0] + b[2][0]) / 2
                    mz = (a[j][1] + b[j][1]) / 2 - (a[2][1] + b[2][1]) / 2
                    facing = (mx, mz)
                parts.append(("gelaende", q, [(p[0] / 4.0, -p[1] / 4.0) for p in q], facing, [col] * 4))
    if not parts:
        return 0
    obj = mesh_object("Gelaende_Dammkrone", parts)
    objs_ground.append(obj)
    print("DIORAMA Dammkrone: %d Flächen, höchster Punkt %.3f m unter der Fahrbahngrenze" % (len(parts), -worst))
    return len(parts)
