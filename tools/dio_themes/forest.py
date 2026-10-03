"""Themenmodul "forest" (Forest Eight): dichter Mischwald mit Schotterpiste, Teich, Blockhütte und Zuschauerplatz.

Wird von tools/diorama.py in dessen Globals ausgeführt (siehe docs/dioramen/README.md; Beschreibung der Szene und Entscheidungen:
docs/dioramen/forest.md). Straße: "runtime" (das Spiel baut die Schotterpiste mit Pfosten und Feldsteinen selbst, auf Höhe 0,17); das
Diorama liefert Boden, Bäume, Teich, Unterholz und Waldgerät.

Gebacken (Begleitdatei-Eintrag "baked"): Kiefern, Eichen, der Teich und die Blockhütte. Die Bäume sind selbst gebaut (dichte Kronen aus
verformten Blasen, Blatt- bzw. Nadeltextur, drei Detailstufen je Entfernung zur Strecke), stehen an den Orten der Streckendatei (Bäume, die
Hütte, Teich, Fahrbahn oder Zuschauerplatz verdecken würden, werden versetzt oder weggelassen) und tragen als Hindernisse "baum" mit den
Radien von track.gd (Kiefer 0,35, Eiche 0,45, mal Skalierung). Die Hütte ist ein eigener Bau (Rundstämme, Schindeldach mit Moos,
Schornstein, Fenster mit Läden) mit echten Lichtquellen (Fensterlicht, Türlampe). Laternen (echte Lichtquellen), Felsen, Tribüne,
Zeitnahmeturm und der liegende Stamm bleiben Laufzeit-Bauteile und bekommen über ao_proxies() ihren Kontaktschatten. Alle zusätzlichen
festen Teile (Findlinge, Stümpfe, Holzstapel, Hochsitz ...) haben Hindernisse in der Begleitdatei; Unterholz unter etwa 0,4 m (Farne, Gras)
ist körperlos.

Höhen (seit 03.10.2026, Streckenfassung rev 2): Alles steht auf dem Dioramaboden f_level (Gelände der Streckendatei, am Fahrbahnrand auf
Fahrbahnhöhe, Erdwand im Hohlweg, Böschung an Dämmen); die Holzbrücke über den Hohlweg (Widerlager, Träger, Bohlen, Geländer, Laternen) baut
f_bridge, den Hohlweg f_hollow_way. Teile über dem unteren Ast heißen Deck_*. Beschreibung: docs/dioramen/forest.md.
"""
from mathutils import noise

F_TEX = "res://assets/dio/forest/"
THEME_CFG = {
    "road": "runtime",
    "ground_y": 0.08,
    "margin": 40.0,
    "baked": ["pine", "oak", "pond", "cabin", "rock"],
    "vertex_colors": "ACTIVE",
    # Bodenmischung: Platz "grass" = Waldboden (Moos, Humus, Laub), "sand" = Nadelstreu, "dirt" = Wegerde (festgefahrene Erde mit Schotter, dunkle feuchte Flecken)
    "ground_set": {"grass": F_TEX + "boden_wald", "sand": F_TEX + "boden_nadeln", "dirt": F_TEX + "boden_erde"},
    "ground_scales": {"grass": 4.0, "sand": 3.2, "dirt": 3.6},
    "ground_tints": {"grass": [0.92, 0.95, 0.88], "sand": [0.78, 0.72, 0.66], "dirt": [1.0, 0.98, 0.95]},
    # Teichwasser: flach trüb olivgrün, tief dunkel; der Saum ist kein Schaum, sondern heller Algenrand
    "water": {"lagoon": [0.20, 0.28, 0.14], "open": [0.045, 0.085, 0.075], "foam": [0.30, 0.36, 0.20]},
    "water_nodes": ["Teich"],
}

F_STEP = 1.0                                   # Raster des Bodens (m)
F_POND = next((p for p in data["props"] if p["type"] == "pond"), None)
F_PINES = [p for p in data["props"] if p["type"] == "pine"]
F_OAKS = [p for p in data["props"] if p["type"] == "oak"]
F_WATER_DEPTH = 0.62                           # Tiefe der Teichmulde unter dem Boden (m)
F_CROWN = {"pine": 1.8, "oak": 2.3}            # Kronenradius bei Skalierung 1
F_PLAN = {}                                    # Planung (Hindernisse, Lichtungen, Pfade, Baumorte), von f_plan() gefüllt
F_SOLIDS = []                                  # feste Teile (x, z, Radius) für Abstandsprüfungen
f_stats = {}


# ---------------------------------------------------------------- numpy-Helfer
def f_smooth(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def f_noise(x, z, scale, ox=0.0):
    """Weiches Wertrauschen wie value_noise des Kerns, aber für numpy-Felder (Werte 0..1)."""
    u, v = np.asarray(x) / scale + ox, np.asarray(z) / scale + ox * 0.61
    i0, j0 = np.floor(u).astype(int), np.floor(v).astype(int)
    fu, fv = f_smooth(u - i0), f_smooth(v - j0)
    g = _noise_grid
    a = g[j0 % 64, i0 % 64] * (1 - fu) + g[j0 % 64, (i0 + 1) % 64] * fu
    b = g[(j0 + 1) % 64, i0 % 64] * (1 - fu) + g[(j0 + 1) % 64, (i0 + 1) % 64] * fu
    return a * (1 - fv) + b * fv


def f_fbm(x, z, scale, octaves=3, ox=0.0):
    out, amp, tot = 0.0, 1.0, 0.0
    for k in range(octaves):
        out = out + amp * f_noise(x, z, scale / (2 ** k), ox + 17.0 * k)
        tot += amp
        amp *= 0.5
    return out / tot


def f_nearest_center(P):
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


def f_dc(x, z):
    return float(dist_to_center(np.array([(x, z)]))[0])


# ---------------------------------------------------------------- Höhen: Gelände der Streckendatei, Bodenhöhe des Dioramas
# Die Fahrphysik kennt neben der Fahrbahn keine Geländehöhe (ein Auto neben der Piste fährt auf der Höhe seines Asts), das Höhenraster
# "terrain" (2-m-Zellen, bilinear) verschmiert zudem die Fahrbahnkante um bis zu 0,2 m. Der Boden des Dioramas folgt deshalb nicht roh
# dem Raster, sondern f_level: am Fahrbahnrand genau die Fahrbahnhöhe des nächsten Asts, liegt das Gelände höher (Einschnitt, Hohlweg),
# bleibt eine 1,5 m breite ebene Schulter und dahinter steigt eine Erdwand mit F_WALL (2,4 : 1) bis zum Gelände; liegt es tiefer (Damm),
# fällt die Böschung über F_BLEND Meter weich ins Gelände. Ab dort gilt das Raster. Brückenstücke (Fahrbahn mehr als F_BRIDGE_GAP über dem
# Gelände) zählen dabei nicht als Ast: unter der Brücke gilt der untere Ast.
F_WALL = 2.4
F_SHOULDER = 1.5
F_BLEND = 2.5
F_BRIDGE_GAP = 1.0                             # Fahrbahn so weit über dem Gelände: Brücke (zählt nicht als Ast, Diorama trägt sie)
_F_LV = {}


def f_ty(P):
    """Gelände der Streckendatei (wie Circuit.terrain_height, bilinear, am Rand geklemmt) für viele Punkte P (n x 2)."""
    P = np.asarray(P, float).reshape(-1, 2)
    if not TERRAIN:
        return np.zeros(len(P))
    if "H" not in _F_LV:
        _F_LV["H"] = np.array(TERRAIN["heights"], float).reshape(int(TERRAIN["h"]), int(TERRAIN["w"]))
    H = _F_LV["H"]
    h_, w_ = H.shape
    cell = float(TERRAIN["cell"])
    fx = (P[:, 0] - float(TERRAIN["origin"][0])) / cell
    fz = (P[:, 1] - float(TERRAIN["origin"][1])) / cell
    ix = np.clip(np.floor(fx).astype(int), 0, w_ - 2)
    iz = np.clip(np.floor(fz).astype(int), 0, h_ - 2)
    tx = np.clip(fx - ix, 0.0, 1.0)
    tz = np.clip(fz - iz, 0.0, 1.0)
    a = H[iz, ix] + (H[iz, ix + 1] - H[iz, ix]) * tx
    b = H[iz + 1, ix] + (H[iz + 1, ix + 1] - H[iz + 1, ix]) * tx
    return a + (b - a) * tz


def f_lv_setup():
    """Fahrbahnhöhe je Mittellinienpunkt, Brückenmaske, gültige Stücke und Ecken der Mittellinie (einmal)."""
    if "base" in _F_LV:
        return
    base = np.array([base_height(float(s)) for s in S_OF])
    br = (base - f_ty(C)) > F_BRIDGE_GAP
    nseg = len(SEG_A)
    nxt = np.array([(i + 1) % N for i in range(nseg)])
    keep = ~(br[:nseg] | br[nxt])
    _F_LV.update(base=base, bridge=br, seg_keep=keep, seg_b0=base[:nseg], seg_b1=base[nxt])
    # Ecken zwischen zwei gültigen Stücken (am Brückenkopf endet die Kette ohne Ecke: dahinter zählt dieser Ast nicht)
    vi = [i for i in range(N) if keep[i % nseg] and keep[(i - 1) % nseg] and (not OPEN or 0 < i < N - 1)]
    vi = np.array(vi, int)
    t_in = SEG_B[(vi - 1) % nseg] - SEG_A[(vi - 1) % nseg]
    t_out = SEG_B[vi % nseg] - SEG_A[vi % nseg]
    _F_LV.update(v_idx=vi, v_in=t_in, v_out=t_out)


def f_nearest_branch(P):
    """Abstand (m), Fahrbahnhöhe und Index der nächsten Mittellinienstütze für Punkte P (n x 2), ohne Brückenstücke. Nächster Punkt einer
    Kette = senkrechte Projektion auf ein Stück oder eine Ecke, in deren Keil der Punkt liegt (über ein Kettenende hinaus zählt nichts)."""
    f_lv_setup()
    P = np.asarray(P, float).reshape(-1, 2)
    keep = _F_LV["seg_keep"]
    A, B = SEG_A[keep], SEG_B[keep]
    b0, b1 = _F_LV["seg_b0"][keep], _F_LV["seg_b1"][keep]
    ids = np.nonzero(keep)[0]
    V, vin, vout, vids = C[_F_LV["v_idx"]], _F_LV["v_in"], _F_LV["v_out"], _F_LV["v_idx"]
    vb = _F_LV["base"][vids]
    dd = B - A
    ll = np.maximum((dd ** 2).sum(1), 1e-9)
    dist_ = np.full(len(P), 1e6)
    base_ = np.zeros(len(P))
    idx_ = np.zeros(len(P), int)
    for k in range(0, len(P), 1200):
        q = P[k:k + 1200, None, :]
        r = np.arange(q.shape[0])
        t = ((q - A) * dd).sum(2) / ll
        proj = A + np.clip(t, 0, 1)[..., None] * dd
        d2 = np.where((t >= 0.0) & (t <= 1.0), ((q - proj) ** 2).sum(2), np.inf)
        j = d2.argmin(1)
        ds, tt = d2[r, j], np.clip(t[r, j], 0, 1)
        rel = q - V
        inside = ((rel * vin).sum(2) >= 0.0) & ((rel * vout).sum(2) <= 0.0)
        dv = np.where(inside, (rel ** 2).sum(2), np.inf)
        jv = dv.argmin(1)
        dvs = dv[r, jv]
        use_v = dvs < ds
        dist_[k:k + 1200] = np.sqrt(np.minimum(np.minimum(ds, dvs), 1e12))
        base_[k:k + 1200] = np.where(use_v, vb[jv], b0[j] * (1 - tt) + b1[j] * tt)
        idx_[k:k + 1200] = np.where(use_v, vids[jv], ids[j])
    return dist_, base_, idx_


def f_level(P):
    """Bodenhöhe des Dioramas (ohne GROUND_Y) für Punkte P (n x 2), siehe oben."""
    P = np.asarray(P, float).reshape(-1, 2)
    T = f_ty(P)
    dist_, b, _ = f_nearest_branch(P)
    e = dist_ - HW
    up = np.minimum(T, b + F_WALL * np.maximum(e - F_SHOULDER, 0.0))
    t = np.clip(e / F_BLEND, 0.0, 1.0)
    down = b + (T - b) * t * t * (3.0 - 2.0 * t)
    return np.where(T >= b, up, down)

def f_gy(x, z):
    """Bodenhöhe des Dioramas (mit GROUND_Y) an einem Punkt."""
    return GROUND_Y + float(f_level(np.array([(x, z)]))[0])


F_RING = np.array([(math.cos(2 * math.pi * k / 8), math.sin(2 * math.pi * k / 8)) for k in range(8)] + [(0.0, 0.0)])


def f_gy_min(x, z, r=0.3):
    """Tiefste Bodenhöhe unter einer runden Grundfläche (Mitte und acht Randpunkte): ein Teil, das dort aufsitzt, schwebt nirgends."""
    return GROUND_Y + float(f_level(np.array([(x, z)]) + F_RING * r).min())


def f_slope(P, h=0.5):
    """Steigung (Betrag des Gradienten) des Dioramabodens an Punkten P (n x 2)."""
    P = np.asarray(P, float).reshape(-1, 2)
    gx_ = (f_level(P + [h, 0.0]) - f_level(P - [h, 0.0])) / (2 * h)
    gz_ = (f_level(P + [0.0, h]) - f_level(P - [0.0, h])) / (2 * h)
    return np.sqrt(gx_ ** 2 + gz_ ** 2)


class FLift:
    """Alles, was im with-Block neu entsteht (Netze, Punktlichter, Lichtblocker), auf den Dioramaboden setzen. Gebaut wird wie auf ebenem
    Boden (GROUND_Y). mode "lift": ein starres Teil (Hütte, Hochsitz) um die tiefste Bodenhöhe unter seinen Ecken anheben (nichts schwebt,
    bergseitig steht es etwas im Boden); "drape": jeden Eckpunkt um die Bodenhöhe an seinem Ort (lange, flache oder dünne Teile:
    Holzpolter, Strohballenreihe, Pfosten). Modelle aus f_put (Namen "Prop_") setzt f_put selbst."""

    def __init__(self, mode="lift"):
        self.mode = mode

    def __enter__(self):
        self.before = set(o.name for o in scene.objects)
        self.n_light, self.n_occ = len(extra_lights), len(occluder_polys)
        return self

    def __exit__(self, *exc):
        if exc[0] is not None:
            return False
        new = [o for o in scene.objects if o.name not in self.before and o.type == "MESH" and not o.name.startswith("Prop_")]
        co_all = []
        for o in new:
            co = np.empty(len(o.data.vertices) * 3, np.float64)
            o.data.vertices.foreach_get("co", co)
            co_all.append(co.reshape(-1, 3))
        dy = 0.0
        if self.mode == "lift" and co_all:
            pts = np.concatenate(co_all)
            dy = float(f_level(np.stack([pts[:, 0], -pts[:, 1]], 1)).min())
        for o, co in zip(new, co_all):
            if self.mode == "lift":
                co[:, 2] += dy
            else:
                co[:, 2] += f_level(np.stack([co[:, 0], -co[:, 1]], 1))
            o.data.vertices.foreach_set("co", co.ravel())
            o.data.update()
        for e in extra_lights[self.n_light:]:
            e["y"] = round(e["y"] + (dy if self.mode == "lift" else float(f_level(np.array([(e["x"], e["z"])]))[0])), 2)
        for e in occluder_polys[self.n_occ:]:
            e[1] = round(e[1] + (dy if self.mode == "lift" else float(f_level(np.array(e[0], float)).min())), 2)
        self.dy = dy
        return False


def f_pond_sdf(X, Z):
    """Näherung des vorzeichenbehafteten Abstands zum Teichrand in Metern (negativ = im Wasser); unregelmäßiger Umriss."""
    if not F_POND:
        return np.full(np.shape(X), 99.0)
    dx, dz = np.asarray(X) - F_POND["x"], np.asarray(Z) - F_POND["z"]
    a, b = F_POND["w"] / 2.0, F_POND["d"] / 2.0
    ang = np.arctan2(dz / b, dx / a)
    k = 1.0 + 0.10 * np.sin(3 * ang + 0.7) + 0.06 * np.sin(5 * ang + 2.1) + 0.045 * np.sin(8 * ang + 4.0)
    r = np.sqrt((dx / a) ** 2 + (dz / b) ** 2) / k
    return (r - 1.0) * min(a, b) * 1.05


def f_pond_height(X, Z):
    """Mulde des Teichs: sanft vom Ufer zur Mitte, unter dem Boden; außerhalb 0."""
    sd = f_pond_sdf(X, Z)
    return -F_WATER_DEPTH * f_smooth(-sd / 3.2) * (sd < 0.4)


# ---------------------------------------------------------------- Netz-Helfer
def f_grid_mesh(name, key, gx, gz, H, COL, skip=None, tile=4.0):
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


def f_grid_mesh_quad(name, key, gx, gz, H, COL, skip=None, tile=4.0, tol_h=0.012, tol_c=0.05, max_size=8, tol_scale=None):
    """Wie f_grid_mesh, aber als Viererbaum: Ein Block aus s x s Zellen (s = 8, 4, 2) wird zu einem Viereck, wenn Höhe und Vertexfarben darin
    von der bilinearen Interpolation der vier Ecken nicht mehr als tol_h (m) bzw. tol_c abweichen. Spart Dreiecke auf ebenen, gleichmäßigen
    Flächen; die Abweichung (höchstens 1,2 cm) bleibt unsichtbar. tol_scale (Form wie H): Faktor auf tol_c je Ecke; abseits der Strecke
    darf der Boden gröber sein (weniger Dreiecke), nahe der Strecke bleibt es bei der feinen Toleranz."""
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
        fac = float(tol_scale[j:j + sz + 1, i:i + sz + 1].min()) if tol_scale is not None else 1.0
        return float(np.abs(c - cp).max()) <= tol_c * fac

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


def f_bm_object(name, bm, materials, link=True):
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


def f_put(name, x, z, ang, height=None, footprint=None, y=None, label="Prop", anchor="bbox", scale=None, foot=0.3):
    """Modell aus LIB (KI-Modell oder selbst gebautes Teil) wie world.gd place_ai setzen: Mitte der Grundfläche auf (x, z), Unterkante auf y
    (absolut; Vorgabe: tiefste Bodenhöhe im Umkreis foot, f_gy_min), gleichmäßig auf Höhe bzw. Grundfläche (footprint = (Breite entlang u,
    Tiefe)) skaliert. Drehung ang (Bogenmaß) wie das Feld "rot" der Strecke. anchor "origin": Ursprung des Modells ist der Fußpunkt. Kein
    Kollisionseintrag. Rückgabe: Objekt."""
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
    inst.matrix_world = (Matrix.Translation((x, -z, f_gy_min(x, z, foot) if y is None else y)) @ Matrix.Rotation(-ang, 4, "Z")
                         @ Matrix.Scale(s, 4) @ Matrix.Translation((-cx, -cy, -zmin)))
    return inst


def f_register(key, obj):
    """Selbst gebautes Teil für f_put in LIB eintragen (Objekt nicht in der Szene)."""
    for col_ in list(obj.users_collection):
        col_.objects.unlink(obj)
    vs = [v.co for v in obj.data.vertices]
    ext = Vector((max(v.x for v in vs) - min(v.x for v in vs), max(v.y for v in vs) - min(v.y for v in vs), max(v.z for v in vs) - min(v.z for v in vs)))
    LIB[key] = (obj, ext)
    return key


def f_decimated(name, ratio, suffix="_lo2"):
    """Verkleinerte Fassung eines KI-Modells (Decimate-Modifikator, UV und Glättung bleiben): Eintrag in LIB unter name + suffix. Die KI-Findlinge
    haben 2000 Dreiecke; für ein Dutzend Steine im Wald genügt ein Drittel."""
    key = name + suffix
    if key in LIB:
        return key
    obj, _ = model(name)
    tmp = obj.copy()
    tmp.data = obj.data.copy()
    scene.collection.objects.link(tmp)
    mod = tmp.modifiers.new("dec", "DECIMATE")
    mod.ratio = ratio
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    scene.collection.objects.unlink(tmp)
    bpy.data.objects.remove(tmp)
    print("DIORAMA Modell verkleinert:", name, sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons), "->", sum(max(1, len(p.vertices) - 2) for p in me.polygons))
    return f_register(key, bpy.data.objects.new(key, me))


def f_spin(x, z):
    """Feste Zufallsdrehung je Ort (wie world.gd premium_prop)."""
    return (x * 12.9898 + z * 78.233) % (2 * math.pi)


def f_solid(x, z, r, height, kind="baum"):
    """Festes Teil melden: Abstandsliste für weitere Platzierungen und Hindernis der Spielebene (Kreis)."""
    F_SOLIDS.append((x, z, r))
    collide_circle(x, z, r, height, kind)


def f_solid_rect(cx, cz, ang, ha, hb, height, kind="mauer"):
    F_SOLIDS.append((cx, cz, math.hypot(ha, hb)))
    collide_rect(cx, cz, math.cos(ang), math.sin(ang), ha, hb, height, kind)


# ---------------------------------------------------------------- Planung (Lichtungen, Pfade, Baumorte)
def f_in_rect(x, z, cx, cz, ang, ha, hb, pad=0.0):
    dx, dz = x - cx, z - cz
    a = dx * math.cos(ang) + dz * math.sin(ang)
    b = -dx * math.sin(ang) + dz * math.cos(ang)
    return abs(a) <= ha + pad and abs(b) <= hb + pad


def f_prop(kind):
    return next((p for p in data["props"] if p["type"] == kind), None)


def f_plan():
    """Legt fest, was wo steht: feste Flächen (Hütte, Tribüne, Turm, Laternen, Felsen, Stamm), Lichtungen (keine Bäume) und Pfade."""
    P = F_PLAN
    P.clear()
    cabin, stand, tower, log = f_prop("cabin"), f_prop("stand"), f_prop("tower"), f_prop("log")
    P["rects"] = []        # feste Rechtecke: (cx, cz, ang, ha, hb)
    P["circles"] = []      # feste Kreise: (x, z, r)
    P["clear"] = []        # Lichtungen (keine Bäume, Unterholz erlaubt): (x, z, ra, rb, ang)
    P["paths"] = []        # Pfade: Punktlisten (x, z) mit Breite
    if cabin:
        ang = math.radians(cabin.get("rot", 0.0))
        P["cabin"] = (cabin["x"], cabin["z"], ang)
        P["rects"].append((cabin["x"], cabin["z"], ang, 2.5, 2.0))
        fx, fz = -math.sin(ang), math.cos(ang)                                   # Vorderseite (Tür) der Hütte
        P["clear"].append((cabin["x"] + fx * 3.0, cabin["z"] + fz * 3.0, 4.8, 4.2, ang))
        P["clear"].append((cabin["x"], cabin["z"], 5.5, 4.8, ang))
        # Pfad von der Tür (links der Mitte der Vorderseite, 0,8 m, Stufe bei b = 2,2) zur Fahrbahn (Boden: festgetretene Erde)
        door = (cabin["x"] + math.cos(ang) * -0.8 + fx * 2.7, cabin["z"] + math.sin(ang) * -0.8 + fz * 2.7)
        idx, _ = f_nearest_center(np.array([door]))
        road = C[idx[0]]
        dd = np.array(door) - road
        dd = dd / np.linalg.norm(dd)
        end = road + dd * (HW + 0.3)
        mid = (np.array(door) + end) / 2 + np.array([-dd[1], dd[0]]) * 0.9
        P["paths"].append(([door, tuple(mid), tuple(end)], 1.3))
    # Holzpolter außen an der linken Schleife, Strohballen als Kurvenschutz außen an der rechten (Rallye)
    i_l, i_r = int(np.argmin(C[:, 0])), int(np.argmax(C[:, 0]))
    t_l = tang[i_l]
    q_l = center[i_l] + Vector((-1.0, 0.0)) * (HW + 6.4)
    P["polter"] = (float(q_l.x), float(q_l.y), math.atan2(t_l.y, t_l.x))
    P["clear"].append((float(q_l.x), float(q_l.y), 3.6, 3.4, P["polter"][2]))
    P["rects"].append((float(q_l.x), float(q_l.y), P["polter"][2], 2.4, 1.2))
    t_r = tang[i_r]
    q_r = center[i_r] + Vector((1.0, 0.0)) * (HW + 3.6)
    P["bales"] = (float(q_r.x), float(q_r.y), math.atan2(t_r.y, t_r.x))
    P["clear"].append((float(q_r.x), float(q_r.y), 2.8, 4.2, P["bales"][2]))
    P["rects"].append((float(q_r.x), float(q_r.y), P["bales"][2], 0.8, 3.6))
    if stand:
        P["rects"].append((stand["x"], stand["z"], math.radians(stand.get("rot", 0.0)), stand["w"] / 2.0, (stand["d"] + 2.0) / 2.0))
        P["clear"].append((stand["x"], stand["z"] + 1.0, stand["w"] / 2.0 + 3.5, 5.0, 0.0))
    if tower:
        P["circles"].append((tower["x"], tower["z"], 1.3))
        P["clear"].append((tower["x"], tower["z"], 3.5, 3.5, 0.0))
    if log:
        P["rects"].append((log["x"], log["z"], math.radians(log.get("rot", 0.0)), 1.6, 0.35))
    # Brücke: Widerlager (je 2 x 12,4 m) und Brückenköpfe frei von Bäumen und festen Teilen (f_bridge baut sie später)
    f_lv_setup()
    bi = np.nonzero(_F_LV["bridge"])[0]
    if len(bi):
        D = np.array(dist[:N])
        for i_e, sgn in ((int(bi.min()) - 1, 1.0), (int(bi.max()) + 1, -1.0)):
            q, t, lf = f_tpos(float(D[i_e % N]) + sgn * 0.4)
            P["rects"].append((float(q[0]), float(q[1]), math.atan2(t[1], t[0]), 1.4, 6.6))
            P["clear"].append((float(q[0]), float(q[1]), 3.0, 8.0, math.atan2(t[1], t[0])))
    for p in data["props"]:
        if p["type"] == "lantern":
            P["circles"].append((p["x"], p["z"], 0.3))
        elif p["type"] == "rock":
            P["circles"].append((p["x"], p["z"], 0.9 * p.get("scale", 1.0)))


def f_solid_blocked(x, z, r):
    """Überschneidet ein Kreis (x, z, r) ein festes Teil der Planung oder ein bereits gesetztes festes Teil?"""
    for cx, cz, ang, ha, hb in F_PLAN["rects"]:
        if f_in_rect(x, z, cx, cz, ang, ha, hb, r):
            return True
    for cx, cz, cr in F_PLAN["circles"]:
        if (x - cx) ** 2 + (z - cz) ** 2 < (cr + r) ** 2:
            return True
    for cx, cz, cr in F_SOLIDS:
        if (x - cx) ** 2 + (z - cz) ** 2 < (cr + r) ** 2:
            return True
    return False


def f_in_clearing(x, z, pad=0.0):
    for cx, cz, ra, rb, ang in F_PLAN["clear"]:
        dx, dz = x - cx, z - cz
        a = dx * math.cos(ang) + dz * math.sin(ang)
        b = -dx * math.sin(ang) + dz * math.cos(ang)
        if (a / (ra + pad)) ** 2 + (b / (rb + pad)) ** 2 < 1.0:
            return True
    return False


def f_tree_sites():
    """Baumorte: die der Streckendatei, aber Kronen dürfen nicht über Fahrbahn, Teich, Hütte, Lichtungen oder feste Teile ragen; ein Baum, der
    zu nah an der Fahrbahn steht, rückt nach außen, ist dafür kein Platz, entfällt er."""
    sites = []
    removed = moved = 0
    for kind, props, h0, rad in (("pine", F_PINES, 5.6, 0.35), ("oak", F_OAKS, 4.6, 0.45)):
        for p in props:
            x, z, sc = p["x"], p["z"], p.get("scale", 1.0)
            cr = F_CROWN[kind] * sc
            need = HW + cr * 0.78 - 0.1                                           # Mindestabstand Stamm - Mittellinie
            dc = f_dc(x, z)
            ok = True
            if dc < need:
                idx, _ = f_nearest_center(np.array([(x, z)]))
                c = C[idx[0]]
                away = np.array([x, z]) - c
                n = np.linalg.norm(away)
                away = away / n if n > 1e-6 else np.array([left[idx[0]].x, left[idx[0]].y])
                for step in np.arange(0.4, 3.01, 0.4):
                    nx_, nz_ = x + away[0] * step, z + away[1] * step
                    if f_dc(nx_, nz_) >= need:
                        x, z = nx_, nz_
                        moved += 1
                        break
                else:
                    ok = False
            if ok and (F_POND and float(f_pond_sdf(x, z)) < 0.8 + cr * 0.55):
                ok = False
            if ok and (f_in_clearing(x, z, cr * 0.4) or f_solid_blocked(x, z, cr * 0.45)):
                ok = False
            if not ok:
                removed += 1
                continue
            sites.append((kind, x, z, sc, h0, rad))
    # keine Stämme ineinander
    keep = []
    for s in sites:
        if all((s[1] - t[1]) ** 2 + (s[2] - t[2]) ** 2 > (0.45 * (s[3] + t[3])) ** 2 + 0.2 for t in keep):
            keep.append(s)
    f_stats["trees"] = (len(keep), moved, removed + len(sites) - len(keep))
    return keep


F_RUNOFF_K = 1.0 / 16.0       # Kehren enger als Radius 16 m ...
F_RUNOFF = 7.0                 # ... bekommen außen bis hw + 7 m eine Auslaufzone ohne Zusatzbäume (bis 12 m hinter dem Scheitel)


def f_in_runoff(x, z):
    """Auslaufzone (seit 03.10.2026, Prüfung: Übertempo in der Talkehre endete immer festgeklemmt an einem Zusatzbaum, den die Streckendatei
    dort gar nicht hat – sie hält die Kehre außen bis hw + 6 m frei): außen an engen Kehren und bis 12 m dahinter keine Zusatzbäume."""
    idx, lat = f_nearest_center(np.array([(x, z)]))
    i, la = int(idx[0]), float(lat[0])
    if abs(la) >= HW + F_RUNOFF:
        return False
    for back in range(0, 25, 2):                       # 0,5-m-Stützen: aktuelle Stelle und bis 12 m zurück
        j = nb(i, -back)
        a, b = tang[nb(j, -2)], tang[nb(j, 2)]
        k = math.atan2(a.x * b.y - a.y * b.x, a.dot(b)) / 2.0   # vorzeichenbehaftet: + Linkskurve
        if abs(k) > F_RUNOFF_K and la * k < 0.0:        # außen = Seite gegen die Kurvenrichtung (links positiv)
            return True
    return False


def f_extra_tree_sites(existing):
    """Zusätzliche Bäume in Lücken des Bestands (ein Mischwald soll dicht sein): Abstand zum nächsten Stamm mindestens 4,4 m, Kronen
    nie über Fahrbahn, Teich, Lichtungen oder feste Teile."""
    rng_ = np.random.default_rng(55)
    P, dc, sd = f_cands(rng_, 9000)
    taken = [(t[1], t[2]) for t in existing]
    out = []
    for i in rng_.permutation(len(P)):
        if len(out) >= 70:
            break
        x, z = float(P[i, 0]), float(P[i, 1])
        kind = "pine" if rng_.random() < 0.55 else "oak"
        sc = float(rng_.choice([0.9, 1.0, 1.1, 1.2]))
        cr = F_CROWN[kind] * sc
        if dc[i] < HW + cr * 0.8 + 0.8 or sd[i] < 1.0 + cr * 0.55:
            continue
        if f_in_clearing(x, z, cr * 0.4) or f_solid_blocked(x, z, cr * 0.45) or f_in_runoff(x, z):
            f_stats["runoff"] = f_stats.get("runoff", 0) + (1 if f_in_runoff(x, z) else 0)
            continue
        if min(math.hypot(x - tx, z - tz) for tx, tz in taken) < 4.4:
            continue
        taken.append((x, z))
        out.append((kind, x, z, sc, 5.6 if kind == "pine" else 4.6, 0.35 if kind == "pine" else 0.45))
    f_stats["extra"] = len(out)
    return out


# ---------------------------------------------------------------- Materialien
def f_vertex_color(mat):
    """Materialzweig, der die Vertexfarbe "Color" liest: Der glTF-Export gibt sie nur dann als COLOR_0 aus (sonst steht dort Weiß und die
    Gewichte des Bodens/Wassers landen in COLOR_1, das der Boden-Shader nicht liest)."""
    nt = mat.node_tree
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Color"
    nt.links.new(vc.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    return mat


F_SRC = os.path.normpath(os.path.join(PROPS, "..", "dio", "forest", "quelle"))
f_mats = {}


def f_tex_material(name, image, tint_by_vertex=True, rough=0.9, color=None):
    """Material mit Bildtextur, auf Wunsch mit Vertexfarbe multipliziert (der glTF-Export macht daraus Textur x COLOR_0)."""
    if name in f_mats:
        return f_mats[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    if image:
        tx = nt.nodes.new("ShaderNodeTexImage")
        tx.image = bpy.data.images.load(os.path.join(F_SRC, image), check_existing=True)
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
    f_mats[name] = mat
    return mat


def theme_materials():
    M["gelaende"] = f_vertex_color(material("D_Gelaende", color=(0.20, 0.30, 0.12), rough=0.9))      # Platzhalter: Misch-Shader im Spiel
    # Die Teichtiefe steckt in der Vertexfarbe (Rot, nur das Wasser des Spiels liest sie; Grün und Blau gleich Rot, damit das Zusatzbild grau bleibt); das Material selbst bekommt eine dunkle Grundfarbe OHNE
    # Verknüpfung mit der Vertexfarbe: Das Laternenlicht-Zusatzbild (lit_overlay) nimmt Grundfarbe x Vertexfarbe als Albedo, sonst würde das
    # Wasser unter Lampen rot. Der Export schreibt die aktive Vertexfarbe ohnehin als COLOR_0 (vertex_colors "ACTIVE").
    M["wasser"].node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.02, 0.03, 0.03, 1.0)
    M["f_holz"] = f_tex_material("F_Holz", "holz.jpg", False, 0.85)
    M["f_holz_grau"] = f_tex_material("F_Holz_grau", "holz_grau.jpg", False, 0.9)
    M["f_stamm"] = f_tex_material("F_Stamm", "stamm.jpg", False, 0.9)
    M["f_schindel"] = f_tex_material("F_Schindel", "schindel.jpg", False, 0.9)
    M["f_dach"] = f_tex_material("F_Dach_alt", "dach_alt.jpg")                                         # Hüttendach (Vertexfarbe = Moos und Alterung)
    M["f_laub"] = f_tex_material("F_Laub", "laub.jpg")
    M["stroh"] = f_tex_material("F_Stroh", None, False, 0.95, color=(0.42, 0.27, 0.05))
    M["stroh_dunkel"] = f_tex_material("F_Stroh_dunkel", None, False, 0.95, color=(0.16, 0.10, 0.03))
    M["farbe"] = M["k:farbe"]
    M["f_spur"] = f_tex_material("F_Spur", "spur.jpg", False, 0.92)                                          # dunklere trockene Wegerde (Radspuren im Saum)
    M["f_matsch"] = f_tex_material("F_Matsch", "matsch.jpg", False, 0.92)                                    # Schlamm und feuchte Erde (Schlammflächen, Ufer)
    puddle = f_tex_material("F_Pfuetze", None, False, 0.04, color=(0.2, 0.15, 0.1))
    f_vertex_color(puddle)
    puddle.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.04
    M["pfuetze"] = puddle
    linsen = f_tex_material("F_Linsen", None, False, 0.92, color=(1.0, 1.0, 1.0))
    f_vertex_color(linsen)
    M["linsen"] = linsen


# ---------------------------------------------------------------- Boden
def f_path_field(P):
    """Erdweg-Gewicht (0..1) entlang der Pfade der Planung."""
    out = np.zeros(len(P))
    for pts, width in F_PLAN["paths"]:
        for (ax, az), (bx, bz) in zip(pts, pts[1:]):
            ab = np.array([bx - ax, bz - az])
            L2 = float(ab @ ab) + 1e-9
            t = np.clip(((P - np.array([ax, az])) @ ab) / L2, 0, 1)
            proj = np.array([ax, az]) + t[:, None] * ab
            d = np.sqrt(((P - proj) ** 2).sum(1))
            wob = (f_noise(P[:, 0], P[:, 1], 1.7, 3.0) - 0.5) * 0.5
            out = np.maximum(out, 1.0 - f_smooth((d - width * 0.5 * (1.0 + wob)) / 0.9))
    return out


def f_wet_fields(P, dc, s, lat, n_mid, n_fine):
    """Schlamm- und Uferfeld (0..1) je Punkt: mud = Schlammabschnitte der Streckendatei (an den Rändern des Abschnitts weich ausgeblendet, außen
    ausgefranst), shore = Teichufer; dazu der Abstand zum Teichrand."""
    mud = np.zeros(len(P))
    for zone in data.get("surfaces", []):
        if zone.get("kind") != "mud":
            continue
        fade = np.clip(np.minimum((s - zone["from"]) / 0.012, (zone["to"] - s) / 0.012), 0.0, 1.0)
        side_ok = 1.0 if zone["side"] == "both" else ((lat > 0) == (zone["side"] == "outer"))
        reach = HW + 2.0 + 2.6 * n_mid + 0.8 * n_fine
        mud = np.maximum(mud, fade * side_ok * (1.0 - f_smooth((dc - (HW + 0.3)) / (reach - HW))))
    # Sohle des Hohlwegs unter der Brücke: feucht und dunkel bis an den Fuß der Erdwände (Schulter F_SHOULDER neben der Fahrbahn)
    hz = f_hollow_range()
    if hz is not None:
        fade = np.clip(np.minimum((s - hz[0]) / 0.012, (hz[1] - s) / 0.012), 0.0, 1.0)
        e = dc - HW
        mud = np.maximum(mud, fade * (e > -0.6) * (1.0 - f_smooth((e - (0.75 + 0.6 * n_mid + 0.2 * n_fine)) / 0.55)))
    sd = f_pond_sdf(P[:, 0], P[:, 1])
    shore = 1.0 - f_smooth((sd - 0.1) / (1.5 + 0.8 * n_mid))
    near = shore > 0.01
    if near.any():                                                   # kein Uferschlamm am steilen Hang (Nordufer unter der oberen Fahrbahn)
        shore[near] *= 1.0 - f_smooth((f_slope(P[near]) - 0.35) / 0.3)
    return mud, shore, sd


def f_branch_info(P):
    """Abstand zur Mittellinie, Index der nächsten Stütze und Seitenabstand (links positiv) je Punkt, bezogen auf den nächsten Ast ohne
    Brückenstücke (unter der Brücke zählt der untere Ast: Saum, Schlamm und Wegerde gehören auf den Boden des Hohlwegs)."""
    P = np.asarray(P, float).reshape(-1, 2)
    dc, _, idx = f_nearest_branch(P)
    lat = ((P - C[idx]) * f_left()[idx]).sum(1)
    return dc, idx, lat


def f_hollow_range():
    """s-Bereich des unteren Asts unter der Brücke (Hohlweg): Stützen ohne Brücke, die näher als 14 m an einem Brückenstück liegen und im
    Streckenverlauf weit davon entfernt sind. None ohne Brücke."""
    if "hollow" not in _F_LV:
        f_lv_setup()
        bi = np.nonzero(_F_LV["bridge"])[0]
        out = None
        if len(bi):
            sb = S_OF[bi].mean()
            dmin = np.sqrt(((C[:, None, :] - C[bi][None, :, :]) ** 2).sum(2)).min(1)
            far = np.abs(((S_OF - sb + 0.5) % 1.0) - 0.5) > 0.12
            hi = np.nonzero((dmin < 14.0) & far & ~_F_LV["bridge"])[0]
            if len(hi):
                out = (float(S_OF[hi].min()), float(S_OF[hi].max()))
        _F_LV["hollow"] = out
    return _F_LV["hollow"]


def f_mud_at(P):
    """Schlammfeld (0..1) an den Punkten P (n x 2)."""
    dc, idx, lat = f_branch_info(P)
    n_mid = f_fbm(P[:, 0], P[:, 1], 3.2, 2, 5.0)
    n_fine = f_noise(P[:, 0], P[:, 1], 1.1, 9.0)
    return f_wet_fields(P, dc, idx / float(N), lat, n_mid, n_fine)[0]


def f_ground_fields(X, Z):
    """Gewichte des Bodens je Punkt: (Helligkeit, Nadelstreu, Schlamm/Erde). Die Gewichte sind um 0,5 verdichtet, damit der Übergang im Shader
    (Schwelle 0,42 bis 0,58) über etwa einen Meter weich verläuft."""
    P = np.stack([X.ravel(), Z.ravel()], 1)
    dc, idx, lat = f_branch_info(P)
    s = idx / float(N)
    shape = X.shape
    n_big = f_fbm(P[:, 0], P[:, 1], 11.0, 3)
    n_mid = f_fbm(P[:, 0], P[:, 1], 3.2, 2, 5.0)
    n_fine = f_noise(P[:, 0], P[:, 1], 1.1, 9.0)
    # Wegsaum: Erd- und Schotterstreifen neben der Fahrbahn, ausgefranst (Abschnitt "Wegsaum": f_verge_dirt)
    dirt = f_verge_dirt(P, dc, n_mid, n_fine)
    # Schlammstrecken (Streckenanteile "surfaces") und Teichufer: nasser, dunkler Waldboden (Moos und Laub bei etwa der Hälfte der Helligkeit); darüber
    # liegt der Matsch (f_build_mud: Netz mit der Schlammtextur), dort ist kein heller Schotter mehr, der Saum geht in den dunklen Matsch über
    mud, shore, sd = f_wet_fields(P, dc, s, lat, n_mid, n_fine)
    wet = np.maximum(mud, shore)
    dirt = dirt * (1.0 - 0.8 * mud)
    # Lichtungen (Hof der Hütte, Zuschauerplatz): festgetretene Erde, Rand ausgefranst
    for cx, cz, ra, rb, ang in F_PLAN["clear"]:
        dx, dz = P[:, 0] - cx, P[:, 1] - cz
        a = dx * math.cos(ang) + dz * math.sin(ang)
        b = -dx * math.sin(ang) + dz * math.cos(ang)
        r = np.sqrt((a / ra) ** 2 + (b / rb) ** 2)
        dirt = np.maximum(dirt, 0.8 * (1.0 - f_smooth((r - 0.45 - 0.25 * n_mid) / 0.5)))
    dirt = np.maximum(dirt, 0.9 * f_path_field(P))
    # Nadelstreu unter den Kiefern, dazu große Flecken (Kieferngruppen)
    needles = np.zeros(len(P))
    for kind, x, z, sc, h0, rad in F_PLAN.get("trees", []):
        if kind != "pine":
            continue
        d2 = (P[:, 0] - x) ** 2 + (P[:, 1] - z) ** 2
        r = 2.6 * sc
        needles = np.maximum(needles, np.exp(-d2 / (r * r)))
    needles = np.clip(needles * 0.95 + 0.5 * f_smooth((n_big - 0.58) * 5.0), 0.0, 1.0) * (1.0 - dirt) * (1.0 - 0.7 * wet)
    # Sonnenflecken und Schatten des Blätterdachs (zeitlos eingebacken: sanfte Helligkeitsflecken)
    dapple = f_smooth((f_fbm(P[:, 0], P[:, 1], 2.6, 2, 21.0) - 0.40) * 5.0)
    bright = (0.74 + 0.20 * (n_big - 0.5) + 0.34 * dapple) * (1.0 - 0.52 * wet)
    # Steile Hänge (Erdwände des Hohlwegs, Böschungen der Dämme, Ufer am Hang): offene, dunklere Erde statt Moos und Nadeln
    steep = f_smooth((f_slope(P) - 0.55 - 0.25 * (n_mid - 0.5)) / 0.45)
    dirt = np.maximum(dirt, 0.92 * steep)
    needles = needles * (1.0 - steep)
    bright = bright * (1.0 - 0.24 * steep)
    comp = lambda w: 0.5 + (np.clip(w, 0.0, 1.0) - 0.5) * 0.62
    return (bright.reshape(shape), comp(needles).reshape(shape), comp(dirt).reshape(shape))


def f_ground_h(X, Z):
    """Höhe des Bodennetzes: Dioramaboden (f_level), unter der Laufzeit-Fahrbahn höchstens so hoch, wie der Kern es zulässt (branch_floor:
    tiefste Fahrbahn in HW + 0,3 m; im Gefälle liegt sie bis zu einige Dezimeter unter der Fahrbahn an dieser Stelle; dort deckt der Saum)."""
    P = np.stack([np.asarray(X, float).ravel(), np.asarray(Z, float).ravel()], 1)
    H = GROUND_Y + f_level(P)
    H = np.minimum(H, branch_floor(P) + ROAD_Y - 0.012)
    return H.reshape(np.shape(X))


def f_build_ground():
    gx = np.arange(x0, x1 + 0.001, F_STEP)
    gz = np.arange(z0, z1 + 0.001, F_STEP)
    X, Z = np.meshgrid(gx, gz)
    skip = None
    pond_box = None
    if F_POND:
        bx0, bx1 = math.floor(F_POND["x"] - F_POND["w"] / 2 - 3), math.ceil(F_POND["x"] + F_POND["w"] / 2 + 3)
        bz0, bz1 = math.floor(F_POND["z"] - F_POND["d"] / 2 - 3), math.ceil(F_POND["z"] + F_POND["d"] / 2 + 3)
        pond_box = (bx0, bx1, bz0, bz1)
        cxm, czm = (gx[:-1] + gx[1:]) / 2, (gz[:-1] + gz[1:]) / 2
        skip = ((czm[:, None] > bz0) & (czm[:, None] < bz1) & (cxm[None, :] > bx0) & (cxm[None, :] < bx1))
    bright, needles, dirt = f_ground_fields(X, Z)
    H = f_ground_h(X, Z)
    COL = np.stack([bright, needles, dirt], -1)
    far_fac = 1.0 + 1.3 * f_smooth((dist_to_center(np.stack([X.ravel(), Z.ravel()], 1)).reshape(X.shape) - 9.0) / 12.0)
    objs_ground.append(f_grid_mesh_quad("Gelaende", "gelaende", gx, gz, H, COL, skip, tol_scale=far_fac))
    if pond_box:
        fx = np.arange(pond_box[0], pond_box[1] + 0.001, 0.5)
        fz = np.arange(pond_box[2], pond_box[3] + 0.001, 0.5)
        FX, FZ = np.meshgrid(fx, fz)
        br2, nd2, dt2 = f_ground_fields(FX, FZ)
        H2 = f_ground_h(FX, FZ) + f_pond_height(FX, FZ)
        objs_ground.append(f_grid_mesh("Gelaende_Teich", "gelaende", fx, fz, H2, np.stack([br2, nd2, dt2], -1)))
    # Weite: Waldboden bis weit hinter den Bildrand (Neigung der Rennkamera); folgt dem Gelände (am Rand des Rasters geklemmt), damit am
    # Übergang zum Bodennetz keine Stufe entsteht
    far = 140.0
    for k, (ax0, az0, ax1, az1) in enumerate(((x0 - far, z0 - far, x1 + far, z0), (x0 - far, z1, x1 + far, z1 + far),
                                              (x0 - far, z0, x0, z1), (x1, z0, x1 + far, z1))):
        wx = np.unique(np.concatenate([np.arange(ax0, ax1, 8.0), gx[(gx > ax0) & (gx < ax1)][::8], [ax1]]))
        wz = np.unique(np.concatenate([np.arange(az0, az1, 8.0), gz[(gz > az0) & (gz < az1)][::8], [az1]]))
        WX, WZ = np.meshgrid(wx, wz)
        objs_ground.append(f_grid_mesh("Weite_%d" % k, "gelaende", wx, wz, f_ground_h(WX, WZ),
                                       np.tile(np.array([0.62, 0.55, 0.55]), (len(wz), len(wx), 1)), tile=8.0))


def f_water_y():
    """Wasserspiegel des Teichs (absolut): 0,13 m unter dem Boden der Teichmulde (das Gelände legt sie als ebene Senke an)."""
    return f_gy(F_POND["x"], F_POND["z"]) - 0.13 if F_POND else GROUND_Y - 0.13


def f_build_pond_water():
    if not F_POND:
        return
    water_y = f_water_y()
    fx = np.arange(math.floor(F_POND["x"] - F_POND["w"] / 2 - 3), math.ceil(F_POND["x"] + F_POND["w"] / 2 + 3) + 0.001, 0.5)
    fz = np.arange(math.floor(F_POND["z"] - F_POND["d"] / 2 - 3), math.ceil(F_POND["z"] + F_POND["d"] / 2 + 3) + 0.001, 0.5)
    FX, FZ = np.meshgrid(fx, fz)
    h = f_ground_h(FX, FZ) + f_pond_height(FX, FZ)
    depth = np.clip((water_y - h) / 0.5, 0.0, 1.0)
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
        mesh_object("Teich", parts)


# ---------------------------------------------------------------- Wegsaum: Erdsaum, Schotterkante, Radspuren, Laub, Steine, Pfützen
# Die Laufzeit-Piste ist ein ebenes Band (0,17 m) mit harter Kante zum Waldboden (0,08 m). Der Saum vermittelt: ein flacher Wall aus festgefahrener
# Erde und Schotter (0,147 m am Fahrbahnrand, fällt über rund einen Meter auf einen 2 cm hohen Sockel und läuft nach 2 m in den Waldboden aus) mit
# Erdgewicht in der Vertexfarbe (ausgefranster Rand, der Boden-Shader blendet weich), flachen Radspuren, Schotter, Laub, Ästen und Pfützen.
# Alles liegt unter der Fahrbahn (check_runtime_ground prüft nur objs_ground; der Saum hält die Grenze selbst ein) und hat keine Hindernisse.
# Der Saum liegt NICHT in objs_ground (sonst backte er seine Umgebungsverdeckung über die des Bodens darunter, und der Boden darunter würde vom
# Saum verdunkelt): Er ist beim Backen unsichtbar ("Saum" in theme_bake_hidden) und liest mit derselben Licht-UV die Verdeckung des Bodens.
F_VERGE_E = [-0.2, 0.0, 0.14, 0.3, 0.5, 0.78, 1.1, 1.5, 2.0]     # Stationen quer zur Piste, Abstand vom Fahrbahnrand (m)
F_VERGE_RAISE = 0.022                                            # Sockel des Saums über dem Waldboden (m)
F_VERGE_MAXH = 0.152                                             # höchste Stelle (Fahrbahn 0,17, Prüfgrenze des Kerns 0,16)
_F_LEFT = []


def f_left():
    """Linksnormalen der Mittellinie als Feld (N x 2); erst nach dem Laden der Mittellinie verfügbar, deshalb beim ersten Aufruf gebaut."""
    if not _F_LEFT:
        _F_LEFT.append(np.array([[l.x, l.y] for l in left]))
    return _F_LEFT[0]


def f_verge_dirt(P, dc, n_mid, n_fine):
    """Erdgewicht des Wegsaums (0..1, vor der Verdichtung): voll am Fahrbahnrand, nach außen ausgefranst (Rand 0,2 bis 1,3 m, danach 0,7 m weicher
    Übergang); bei e >= 2 m null, damit der Saum (endet bei 2,0 m) und der Boden dahinter dieselben Gewichte haben."""
    e = dc - HW
    rag = f_fbm(P[:, 0], P[:, 1], 2.1, 3, 13.0)
    edge = np.clip(0.95 + 0.9 * (n_mid - 0.5) + 0.8 * (rag - 0.5), 0.2, 1.3)
    return (1.0 - f_smooth((e - edge) / 0.7)) * (0.8 + 0.2 * n_fine)


def f_verge_mask(P):
    """Wo die Radspuren sichtbar sind (0..1): stellenweise, in Streifen von einigen Metern Länge."""
    return f_smooth((f_noise(P[:, 0], P[:, 1], 14.0, 41.0) - 0.35) * 4.0)


def f_verge_height(P, dc=None):
    """Höhe des Saums (m, absolut: Dioramaboden f_level plus Saumprofil) und Abstand e zum Fahrbahnrand (m) für Punkte P (n x 2); dc =
    Abstand zum nächsten Ast ohne Brückenstücke (f_nearest_branch)."""
    if dc is None:
        dc = f_nearest_branch(P)[0]
    e = dc - HW
    ec = np.maximum(e, -0.3)
    x, z = P[:, 0], P[:, 1]
    berm = 0.045 * (1.0 - f_smooth(ec / 0.95))
    sockel = 0.003 + (F_VERGE_RAISE - 0.003) * (1.0 - f_smooth((ec - 1.0) / 1.0))
    rough = 0.005 * (f_noise(x, z, 1.3, 7.0) * 2.0 - 1.0) * f_smooth(ec / 0.5)
    groove = 0.011 * np.exp(-((ec - 0.52) / 0.2) ** 2) * f_verge_mask(P)
    h = np.minimum(GROUND_Y + sockel + berm + rough - groove, F_VERGE_MAXH) + f_level(P)
    return h, e


def f_verge_points(rng_, n, e_lo, e_hi, power=1.0):
    """Zufallsorte neben der Piste: (Punkte n x 2, e, Seite, Index). Nur dort, wo e wirklich der Abstand zur nächsten Mittellinie ist (nicht
    auf der Kurveninnenseite jenseits der Krümmung und nicht auf der anderen Fahrbahn der Kreuzung)."""
    i = rng_.integers(0, N, n)
    side = rng_.choice([-1.0, 1.0], n)
    e = e_lo + (e_hi - e_lo) * rng_.random(n) ** power
    P = C[i] + f_left()[i] * (side * (HW + e))[:, None]
    f_lv_setup()
    ok = (np.abs(dist_to_center(P) - (HW + e)) < 0.15) & ~_F_LV["bridge"][i]          # nicht neben der Brücke (dort ist kein Saum)
    return P[ok], e[ok], side[ok], i[ok]


def f_build_verge():
    closed = not OPEN
    idxs = list(range(0, N, 2))
    rows = idxs + ([idxs[0]] if closed else [])
    R, K = len(rows), len(F_VERGE_E)
    rows_i = np.array(rows)
    E = np.array(F_VERGE_E)
    tris = 0
    near_max = 0.0
    for side, name in ((1.0, "Saum_L"), (-1.0, "Saum_R")):
        G = C[rows_i][:, None, :] + f_left()[rows_i][:, None, :] * (side * (HW + E))[None, :, None]
        flat = G.reshape(-1, 2)
        dc, base_n, _ = f_nearest_branch(flat)
        h, e_real = f_verge_height(flat, dc)
        near_max = max(near_max, float((h - base_n)[e_real < 0.3].max()))
        bright, needles, dirt = f_ground_fields(G[..., 0], G[..., 1])
        H = h.reshape(R, K)
        COL = np.stack([bright, needles, dirt], -1)
        Pc = ((G[:-1, :-1] + G[1:, 1:]) / 2).reshape(-1, 2)
        _, _, idx_c = f_nearest_branch(Pc)
        diff = (idx_c.reshape(R - 1, K - 1) - rows_i[:-1, None] + N // 2) % N - N // 2
        own = np.abs(diff) <= 14                     # Viereck gehört der Strecke, die ihm am nächsten liegt (Kreuzung: kein Doppelsaum)
        brg = _F_LV["bridge"][rows_i]
        own &= ~(brg[:-1] | brg[1:])[:, None]        # auf der Brücke kein Erdsaum (dort liegen Bohlen und Geländer)
        bm = bmesh.new()
        uv0 = bm.loops.layers.uv.new("UVMap")
        uv1 = bm.loops.layers.uv.new("Licht")        # wie der Kern die Licht-UV legt: dieselbe Verdeckung wie der Boden darunter
        col = bm.loops.layers.float_color.new("Color")
        verts = {}

        def vert(r, k):
            if (r, k) not in verts:
                verts[(r, k)] = bm.verts.new((float(G[r, k, 0]), -float(G[r, k, 1]), float(H[r, k])))
            return verts[(r, k)]

        for r in range(R - 1):
            for k in range(K - 1):
                if not own[r, k]:
                    continue
                corners = ((r, k), (r + 1, k), (r + 1, k + 1), (r, k + 1))
                try:
                    f = bm.faces.new([vert(a, b) for a, b in corners])
                except ValueError:
                    continue
                f.smooth = True
                f.normal_update()
                if f.normal.z < 0:
                    f.normal_flip()
                cmap = {vert(a, b): (a, b) for a, b in corners}
                for loop in f.loops:
                    a, b = cmap[loop.vert]
                    gx, gz = float(G[a, b, 0]), float(G[a, b, 1])
                    loop[uv0].uv = (gx / 4.0, -gz / 4.0)
                    loop[uv1].uv = ((gx - x0) / (x1 - x0), 1.0 - (gz - z0) / (z1 - z0))
                    c = COL[a, b]
                    loop[col] = (float(c[0]), float(c[1]), float(c[2]), 1.0)
                tris += 2
        bm.normal_update()
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(M["gelaende"])
        obj = bpy.data.objects.new(name, me)
        scene.collection.objects.link(obj)
    f_stats["saum_tris"] = tris
    print("DIORAMA Wegsaum:", tris, "Dreiecke, höchste Stelle nahe der Fahrbahn %.3f m über deren Basis (Fahrbahn %.2f)" % (near_max, ROAD_Y))
    if near_max > ROAD_Y - 0.012:
        raise ValueError("Wegsaum überdeckt die Laufzeit-Fahrbahn (%.3f m)" % near_max)


def f_build_mud():
    """Matsch: dunkle, nasse Erde (Schlammtextur, Material F_Matsch) in den Schlammabschnitten neben der Piste und an den Teichufern. Gitter mit
    0,6 m Zellen; die Höhe folgt dem Saum plus 8 mm und hängt stetig vom Schlammfeld ab (höher bei hohem Feld, unter dem Boden bei niedrigem):
    Der Rand der Fläche ist die weiche, ausgefranste Schnittlinie von Matsch und Boden (kein harter Streifen, das Feld bestimmt sie). Das Netz liegt nicht in objs_ground (beim Backen unsichtbar, Namen "Saum_..."); die Laufzeit-Schlammstreifen des Spiels (0,13 m)
    bleiben darüber sichtbar."""
    cell = 0.6
    regions = []
    for zone in data.get("surfaces", []):
        if zone.get("kind") == "mud":
            ids = [i % N for i in range(int(zone["from"] * N) - 14, int(zone["to"] * N) + 15)]
            regions.append(("zone", C[ids][:, 0].min() - HW - 9.0, C[ids][:, 0].max() + HW + 9.0, C[ids][:, 1].min() - HW - 9.0, C[ids][:, 1].max() + HW + 9.0))
    hz = f_hollow_range()
    if hz is not None:
        ids = [i % N for i in range(int(hz[0] * N) - 6, int(hz[1] * N) + 7)]
        regions.append(("hohlweg", C[ids][:, 0].min() - HW - 3.0, C[ids][:, 0].max() + HW + 3.0, C[ids][:, 1].min() - HW - 3.0, C[ids][:, 1].max() + HW + 3.0))
    if F_POND:
        regions.append(("ufer", F_POND["x"] - F_POND["w"] / 2 - 4.5, F_POND["x"] + F_POND["w"] / 2 + 4.5, F_POND["z"] - F_POND["d"] / 2 - 4.5, F_POND["z"] + F_POND["d"] / 2 + 4.5))
    tris = 0
    for k, (kind, xa, xb, za, zb) in enumerate(regions):
        gx = np.arange(math.floor(xa), math.ceil(xb) + 0.001, cell)
        gz = np.arange(math.floor(za), math.ceil(zb) + 0.001, cell)
        X, Z = np.meshgrid(gx, gz)
        P = np.stack([X.ravel(), Z.ravel()], 1)
        dc, idx, lat = f_branch_info(P)
        n_mid = f_fbm(P[:, 0], P[:, 1], 3.2, 2, 5.0)
        n_fine = f_noise(P[:, 0], P[:, 1], 1.1, 9.0)
        mud, shore, sd = f_wet_fields(P, dc, idx / float(N), lat, n_mid, n_fine)
        m = np.maximum(mud, shore * (sd > -0.15)).reshape(X.shape)
        lv = f_level(P)
        hv = f_verge_height(P, dc)[0] - lv                                                         # Saumprofil relativ zum Dioramaboden
        rough = 0.006 * (f_noise(P[:, 0], P[:, 1], 0.9, 23.0).reshape(X.shape) - 0.5)
        base = (np.minimum(np.maximum(hv, GROUND_Y + 0.004) + 0.004, 0.148) + lv).reshape(X.shape) + f_pond_height(X, Z)
        H = base + np.minimum(0.05 * (m - 0.5), 0.010) + rough * (m > 0.4)                         # stetig im Feld: die Schnittlinie mit dem Boden (m etwa 0,42) ist glatt; höchstens 0,16 m
        corner_max = np.maximum.reduce([m[:-1, :-1], m[1:, :-1], m[:-1, 1:], m[1:, 1:]])
        skip = corner_max < 0.34
        if skip.all():
            continue
        nz, nx = len(gz), len(gx)
        bm = bmesh.new()
        uv0 = bm.loops.layers.uv.new("UVMap")
        col = bm.loops.layers.float_color.new("Color")
        verts = {}

        def vert(i, j):
            if (i, j) not in verts:
                verts[(i, j)] = bm.verts.new((float(gx[i]), -float(gz[j]), float(H[j, i])))
            return verts[(i, j)]

        for j in range(nz - 1):
            for i in range(nx - 1):
                if skip[j, i]:
                    continue
                quad = ((i, j), (i, j + 1), (i + 1, j + 1), (i + 1, j))
                f = bm.faces.new([vert(a, b) for a, b in quad])
                f.smooth = True
                for loop, (a, b) in zip(f.loops, quad):
                    loop[uv0].uv = (float(gx[a]) / 3.6, float(-gz[b]) / 3.6)
                    loop[col] = (1.0, 1.0, 1.0, 1.0)
                tris += 2
        bm.normal_update()
        for f in bm.faces:
            if f.normal.z < 0:
                f.normal_flip()
        bm.normal_update()
        f_bm_object("Saum_Matsch_%s%d" % (kind, k), bm, [M["f_matsch"]])
    f_stats["matsch_tris"] = tris
    print("DIORAMA Matsch:", len(regions), "Flächen,", tris, "Dreiecke")


class FDebris:
    """Kleinteile (Schotter, Laub) als Netze je 40-m-Kachel mit Vertexfarben (Material K_farbe); beim Backen unsichtbar (Namen "Saum_...")."""

    def __init__(self):
        self.chunks = {}
        self.n_tri = 0

    def _bm(self, x, z):
        key = (int(math.floor(x / 40.0)), int(math.floor(z / 40.0)))
        if key not in self.chunks:
            bm = bmesh.new()
            self.chunks[key] = (bm, bm.loops.layers.uv.new("UVMap"), bm.loops.layers.float_color.new("Color"))
        return self.chunks[key]

    def tri(self, x, z, pts, cols, up=False, out_from=None):
        """Dreieck in Blender-Koordinaten (x, y = -z, Höhe); up: Normale nach oben, out_from: Normale zeigt vom Punkt weg."""
        bm, uv, col = self._bm(x, z)
        vs = [bm.verts.new(p) for p in pts]
        try:
            f = bm.faces.new(vs)
        except ValueError:
            return
        f.smooth = False
        f.normal_update()
        if up and f.normal.z < 0:
            f.normal_flip()
        if out_from is not None and f.normal.dot(f.calc_center_median() - Vector(out_from)) < 0:
            f.normal_flip()
        cmap = {v: c for v, c in zip(vs, cols)}
        for loop in f.loops:
            c = cmap[loop.vert]
            loop[uv].uv = (0.0, 0.0)
            loop[col] = (c[0] ** 2.2, c[1] ** 2.2, c[2] ** 2.2, 1.0)
        self.n_tri += 1

    def pebble(self, x, z, y, r, tone, rng_):
        """Kieselstein: flache fünfseitige Pyramide (5 Dreiecke), unten dunkel, oben hell; leicht in den Boden gedrückt."""
        n = 5
        el, yaw, a0 = rng_.uniform(1.0, 1.7), rng_.uniform(0.0, math.pi), rng_.uniform(0.0, 6.28)
        cy, sy = math.cos(yaw), math.sin(yaw)
        ring = []
        for k in range(n):
            a = a0 + 2.0 * math.pi * k / n + rng_.uniform(-0.25, 0.25)
            rr = r * rng_.uniform(0.75, 1.2)
            u, v = math.cos(a) * rr * el, math.sin(a) * rr
            ring.append((x + u * cy - v * sy, -(z + u * sy + v * cy), y - 0.012))
        top = (x + rng_.uniform(-0.2, 0.2) * r, -(z + rng_.uniform(-0.2, 0.2) * r), y + r * rng_.uniform(0.5, 0.85))
        dark = tuple(c * 0.62 for c in tone)
        light = tuple(min(1.0, c * 1.06) for c in tone)
        for k in range(n):
            self.tri(x, z, [ring[k], ring[(k + 1) % n], top], [dark, dark, light], out_from=(x, -z, y - 0.03))

    def leaf(self, x, z, y, L, W, yaw, col, rng_):
        """Blatt: flacher Rhombus aus zwei Dreiecken, in der Mitte leicht gewölbt; Spitze und Stiel etwas heller."""
        dx, dz = math.cos(yaw), math.sin(yaw)
        px, pz = -dz, dx
        up = rng_.uniform(0.0, 0.01)
        head = (x + dx * L / 2, -(z + dz * L / 2), y + 0.002)
        tail = (x - dx * L / 2, -(z - dz * L / 2), y)
        lft = (x + px * W / 2, -(z + pz * W / 2), y + 0.004 + up)
        rgt = (x - px * W / 2, -(z - pz * W / 2), y + 0.004)
        tip = tuple(min(1.0, c * 1.12) for c in col)
        rim = tuple(c * 0.86 for c in col)
        self.tri(x, z, [tail, rgt, head], [tip, rim, tip], up=True)
        self.tri(x, z, [tail, head, lft], [tip, tip, rim], up=True)

    def finish(self):
        n = 0
        for key, (bm, uv, col) in sorted(self.chunks.items()):
            f_bm_object("Saum_Streu_%d_%d" % key, bm, [M["farbe"]])
            n += 1
        return n


F_GRAVEL = [(0.52, 0.49, 0.44), (0.60, 0.57, 0.51), (0.43, 0.41, 0.38), (0.66, 0.63, 0.57), (0.48, 0.43, 0.35), (0.56, 0.50, 0.38)]
F_LEAVES = [(0.66, 0.30, 0.07), (0.58, 0.40, 0.10), (0.35, 0.18, 0.07), (0.50, 0.28, 0.09), (0.70, 0.55, 0.14), (0.30, 0.30, 0.10), (0.42, 0.22, 0.08), (0.52, 0.12, 0.05)]


def f_verge_site(x, z, td, r_tree, r_solid=0.1):
    return td > r_tree and f_pond_sdf(x, z) > 0.3 and not f_solid_blocked(x, z, r_solid)


def f_verge_gravel_leaves(rng_, deb):
    """Schotter am Fahrbahnrand (in Flecken, nach außen dünner) und Laub (in Flecken und Nestern, nach außen dichter)."""
    stats = {"kies": 0, "laub": 0}
    P, e, side, ii = f_verge_points(rng_, 5600, 0.0, 1.6, 1.3)
    td = f_tree_dist(P)
    h, _ = f_verge_height(P)
    gw = f_smooth((f_noise(P[:, 0], P[:, 1], 5.5, 63.0) - 0.30) * 3.0)
    for k in range(len(P)):
        x, z = float(P[k, 0]), float(P[k, 1])
        if rng_.random() > 0.12 + 0.88 * gw[k] * max(0.0, 1.0 - e[k] / 1.8):
            continue
        if not f_verge_site(x, z, td[k], 0.55):
            continue
        sh = 0.7 + 0.3 * f_smooth((td[k] - 1.0) / 3.0)
        tone = tuple(c * sh * rng_.uniform(0.88, 1.1) for c in F_GRAVEL[rng_.integers(0, len(F_GRAVEL))])
        deb.pebble(x, z, float(h[k]), 0.04 + 0.1 * rng_.random() ** 1.6, tone, rng_)
        stats["kies"] += 1
    P, e, side, ii = f_verge_points(rng_, 9000, 0.2, 2.3, 0.9)
    td = f_tree_dist(P)
    h, _ = f_verge_height(P)
    lw = 0.2 + 0.8 * f_smooth((f_noise(P[:, 0], P[:, 1], 4.0, 91.0) - 0.35) * 3.0)
    for k in range(len(P)):
        x, z = float(P[k, 0]), float(P[k, 1])
        if rng_.random() > lw[k] * (0.45 + 0.55 * f_smooth((e[k] - 0.2) / 1.0)) * 0.62:
            continue
        if not f_verge_site(x, z, td[k], 0.45):
            continue
        sh = 0.62 + 0.38 * f_smooth((td[k] - 1.0) / 3.0)
        nest = 1 + (int(rng_.integers(2, 5)) if rng_.random() < 0.14 else 0)           # Nester: Laub weht zusammen
        for m in range(nest):
            lx, lz = x + rng_.normal(0.0, 0.14) * (m > 0), z + rng_.normal(0.0, 0.14) * (m > 0)
            col = tuple(c * sh * rng_.uniform(0.85, 1.15) for c in F_LEAVES[rng_.integers(0, len(F_LEAVES))])
            deb.leaf(lx, lz, float(h[k]) + 0.006, rng_.uniform(0.10, 0.2), rng_.uniform(0.05, 0.1), rng_.uniform(0.0, 6.28), col, rng_)
            stats["laub"] += 1
    return stats


def f_verge_puddles(rng_):
    """Pfützen am Saum: spiegelnde Wasserhäute (5 mm über dem Saum) in den flachen Mulden jenseits des Walls, Rand dunkel, Mitte hell."""
    P, e, side, ii = f_verge_points(rng_, 5000, 0.95, 1.6)
    td = f_tree_dist(P) + np.where(f_mud_at(P) > 0.25, -99.0, 0.0)               # im Matsch (f_build_mud) entfallen sie: dort liegen die älteren Pfützen; unter Kronen sieht man sie nicht
    mid = tuple(v ** 2.2 for v in (0.50, 0.52, 0.52))
    edge = tuple(v ** 2.2 for v in (0.28, 0.21, 0.15))
    chosen, parts = [], []
    for k in rng_.permutation(len(P)):
        if len(chosen) >= 34:
            break
        x, z = float(P[k, 0]), float(P[k, 1])
        a, b = rng_.uniform(0.8, 1.9), rng_.uniform(0.26, 0.5)
        if not f_verge_site(x, z, td[k] - b, 2.9, 0.4) or any(math.hypot(x - cx, z - cz) < 6.0 for cx, cz in chosen):
            continue
        ang = math.atan2(tang[ii[k]].y, tang[ii[k]].x) + rng_.uniform(-0.2, 0.2)
        ring = []
        for m in range(14):
            th = 2 * math.pi * m / 14
            rr = rng_.uniform(0.82, 1.12)
            ring.append((x + math.cos(ang) * math.cos(th) * a * rr - math.sin(ang) * math.sin(th) * b * rr,
                         z + math.sin(ang) * math.cos(th) * a * rr + math.cos(ang) * math.sin(th) * b * rr))
        ys = f_verge_height(np.array(ring + [(x, z)]))[0] + 0.006
        if float(ys.max() - ys.min()) > 0.10:
            continue                                                             # kein Wasser im steilen Gefälle
        if float(ys.max() - ys.min()) > 0.02:
            ys = np.full(len(ys), float(ys.min()) + 0.45 * float(ys.max() - ys.min()))     # ebener Wasserspiegel im Gefälle: bergseitig taucht der Rand ein
        for m in range(14):
            m2 = (m + 1) % 14
            parts.append(("farbe_p", [(x, z, float(ys[14])), (ring[m][0], ring[m][1], float(ys[m])), (ring[m2][0], ring[m2][1], float(ys[m2]))][::-1],
                          [(0, 0), (1, 0), (1, 1)], None, [mid, edge, edge][::-1]))
        chosen.append((x, z))
    print("DIORAMA Saum-Pfützen (Beispiele):", [(round(c[0], 1), round(c[1], 1)) for c in chosen[:4]])
    return parts, len(chosen)


F_TRACK_E = [0.1, 0.22, 0.34, 0.46, 0.58, 0.7, 0.82, 0.94]       # Stationen quer für die Radspuren (m vom Fahrbahnrand)


def f_build_tracks():
    """Radspuren: dunkle, festgefahrene Bänder im Wall (e = 0,5 m, 0,4 bis 0,6 m breit, stellenweise unterbrochen, ausgefranst); auf der Außenseite
    enger Kurven breiter und häufiger, weil dort die Autos über den Rand ausschwingen. Wie der Matsch (f_build_mud) ein Gitternetz mit der
    Spurtextur (dunklere, trockene Wegerde), dessen Höhe stetig vom Feld abhängt: Die Schnittlinie mit dem Saum ist der weiche, unregelmäßige Rand, kein Streifen. Das Feld ist
    die Spur entlang e = 0,5 m mal ein Rauschen entlang der Strecke (Streifen von einigen Metern Länge) mal feines Rauschen; die Rillen im Wall
    (f_verge_height) liegen darunter."""
    closed = not OPEN
    idxs = list(range(0, N, 2))
    rows = idxs + ([idxs[0]] if closed else [])
    rows_i = np.array(rows)
    R, K = len(rows), len(F_TRACK_E)
    E = np.array(F_TRACK_E)
    turn = np.array([tang[nb(i, -2)].x * tang[nb(i, 2)].y - tang[nb(i, -2)].y * tang[nb(i, 2)].x for i in range(N)])
    cv = np.array(curv)
    tris = 0
    for side, name in ((1.0, "Saum_Spur_L"), (-1.0, "Saum_Spur_R")):
        G = C[rows_i][:, None, :] + f_left()[rows_i][:, None, :] * (side * (HW + E))[None, :, None]
        flat = G.reshape(-1, 2)
        dc = f_nearest_branch(flat)[0]
        hv, e_real = f_verge_height(flat, dc)
        bonus = np.where(side * turn[rows_i] < 0, np.clip(cv[rows_i] / 0.03, 0.0, 1.0), 0.0)           # Außenseite enger Kurven
        bonus_f = np.repeat(bonus, K)
        mask = np.clip(f_smooth((f_noise(flat[:, 0], flat[:, 1], 14.0, 41.0) - 0.48) * 5.0) + 0.5 * bonus_f, 0.0, 1.0)
        meander = (f_noise(flat[:, 0], flat[:, 1], 7.0, 77.0) - 0.5) * 0.2
        wid = 0.17 * (1.0 + 0.4 * bonus_f)
        lat = np.exp(-(((e_real - 0.5 - meander) / wid) ** 2))
        rag = 0.8 + 0.4 * f_noise(flat[:, 0], flat[:, 1], 0.9, 19.0)
        mf = lat * mask * rag
        valid = np.abs(e_real - np.tile(E, R)) < 0.15
        mf = np.where(valid, mf, 0.0)
        H = (hv + 0.004 + np.minimum(0.04 * (mf - 0.5), 0.004)).reshape(R, K)
        M2 = mf.reshape(R, K)
        corner_max = np.maximum.reduce([M2[:-1, :-1], M2[1:, :-1], M2[:-1, 1:], M2[1:, 1:]])
        Pc = ((G[:-1, :-1] + G[1:, 1:]) / 2).reshape(-1, 2)
        _, _, idx_c = f_nearest_branch(Pc)
        diff = (idx_c.reshape(R - 1, K - 1) - rows_i[:-1, None] + N // 2) % N - N // 2
        brg = _F_LV["bridge"][rows_i]
        skip = (corner_max < 0.34) | (np.abs(diff) > 14) | (brg[:-1] | brg[1:])[:, None]
        if skip.all():
            continue
        bm = bmesh.new()
        uv0 = bm.loops.layers.uv.new("UVMap")
        col = bm.loops.layers.float_color.new("Color")
        verts = {}

        def vert(r, k):
            if (r, k) not in verts:
                verts[(r, k)] = bm.verts.new((float(G[r, k, 0]), -float(G[r, k, 1]), float(H[r, k])))
            return verts[(r, k)]

        for r in range(R - 1):
            for k in range(K - 1):
                if skip[r, k]:
                    continue
                corners = ((r, k), (r + 1, k), (r + 1, k + 1), (r, k + 1))
                try:
                    f = bm.faces.new([vert(a, b) for a, b in corners])
                except ValueError:
                    continue
                f.smooth = True
                cmap = {vert(a, b): (a, b) for a, b in corners}
                for loop in f.loops:
                    a, b = cmap[loop.vert]
                    loop[uv0].uv = (float(G[a, b, 0]) / 3.6, -float(G[a, b, 1]) / 3.6)
                    loop[col] = (1.0, 1.0, 1.0, 1.0)
                tris += 2
        bm.normal_update()
        for f in bm.faces:
            if f.normal.z < 0:
                f.normal_flip()
        bm.normal_update()
        f_bm_object(name, bm, [M["f_spur"]])
    print("DIORAMA Radspuren:", tris, "Dreiecke")
    f_stats["spur_tris"] = tris


def f_verge_detail():
    rng_ = np.random.default_rng(303)
    deb = FDebris()
    stats = f_verge_gravel_leaves(rng_, deb)
    n_chunks = deb.finish()
    pparts, n_p = f_verge_puddles(rng_)
    if pparts:
        M["farbe_p"] = M["pfuetze"]
        mesh_object("Saum_Pfuetzen", pparts)
    f_build_tracks()
    # Steine und Äste (Laufzeit-unabhängige Prop_-Netze wie das übrige Unterholz, körperlos)
    pr = random.Random(12)
    P, e, side, ii = f_verge_points(rng_, 3000, 0.25, 1.9)
    td = f_tree_dist(P)
    h, _ = f_verge_height(P)
    n_s = n_a = 0
    taken = []
    for k in rng_.permutation(len(P)):
        if n_s >= 34 and n_a >= 44:
            break
        x, z = float(P[k, 0]), float(P[k, 1])
        if not f_verge_site(x, z, td[k], 0.6) or any(math.hypot(x - cx, z - cz) < 1.2 for cx, cz in taken):
            continue
        if n_s < 34 and (n_a >= 44 or pr.random() < 0.5):
            f_put(f_stone(int(abs(x * 1.9 + z * 6.1)) % 3), x, z, pr.uniform(0, 6.28), scale=pr.uniform(0.25, 0.6), anchor="origin", y=float(h[k]) - 0.03)
            n_s += 1
        elif n_a < 44:
            f_put(f_branch(int(abs(x * 4.3 + z)) % 2), x, z, pr.uniform(0, 6.28), scale=pr.uniform(0.6, 1.1), anchor="origin", y=float(h[k]))
            n_a += 1
        taken.append((x, z))
    print("DIORAMA Wegsaum-Kleinteile:", stats, "Dreiecke Streu", deb.n_tri, "Kacheln", n_chunks, "Pfützen", n_p, "Steine", n_s, "Äste", n_a)


def theme_ground():
    f_plan()
    F_PLAN["trees"] = f_tree_sites()
    F_PLAN["trees"] = F_PLAN["trees"] + f_extra_tree_sites(F_PLAN["trees"])
    f_build_ground()
    f_build_pond_water()
    f_build_verge()
    f_build_mud()


# ---------------------------------------------------------------- Bäume (selbst gebaut: dichte Kronen aus Blasen, Blatt-/Nadeltextur)
def f_tube(bm, pts, radii, sides=6, uv_len=2.0, uv_layer=None, swap=False):
    """Verjüngte Röhre entlang einer Punktfolge (Blender-Koordinaten, z oben); UV: Winkel x Länge (swap: Länge x Winkel, die Maserung
    der Textur läuft dann entlang der Röhre, wie bei Rundhölzern)."""
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
                    loop[uv_layer].uv = (lens[a] / uv_len, un / sides) if swap else (un / sides, lens[a] / uv_len)


def f_blob_crown(blobs, subdiv, rng_, bump=0.22, tint=(1.0, 1.0, 1.0), tile=2.2, shade_lo=0.5, drop_down=False):
    """Krone aus verformten (gestauchten) Kugeln: innen liegende Flächen entfallen, Würfelprojektion als UV, Vertexfarbe = Höhenschatten.
    blobs: Liste (Mitte Vector, Radius, (sx, sy, sz)). drop_down: auch die nach unten zeigenden Flächen entfallen (von oben und aus der
    geneigten Rennkamera nie zu sehen; spart rund ein Viertel der Dreiecke). Rückgabe: bmesh (Blender-Koordinaten)."""
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
    if drop_down:
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.normal.z < -0.5], context="FACES")
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


# Detailstufen der Bäume je Entfernung zur Strecke: sub = Unterteilung der Kugelblasen, oak_shell/oak_core = Blasen der Eichenkrone,
# pine_pads = Nadelpolster der Kiefer, trunk = Seiten des Stamms, limbs = Aststützen. "near" (unter F_LOD_NEAR m) sieht die Rennkamera groß,
# "mid" bis F_LOD_MID m die Übersicht, "far" ist nur noch Kulisse.
F_LOD = {
    "near": {"sub": 2, "oak_shell": 9, "oak_core": 3, "pine_pads": 5, "trunk": 7, "limbs": True},
    "mid": {"sub": 1, "oak_shell": 11, "oak_core": 3, "pine_pads": 6, "trunk": 5, "limbs": True},
    "far": {"sub": 1, "oak_shell": 7, "oak_core": 2, "pine_pads": 4, "trunk": 4, "limbs": False},
}
F_LOD_NEAR, F_LOD_MID = 9.0, 22.0


def f_build_tree(kind, seed, detail):
    """Eiche oder Kiefer als Blender-Objekt (Fuß im Ursprung, Maße bei Skalierung 1: Kiefer 5,6 m, Eiche 4,6 m). detail: Schlüssel von F_LOD."""
    key = "baum_%s%d_%s" % (kind, seed, detail)
    if key in LIB:
        return key
    lod = F_LOD[detail]
    rng_ = random.Random(seed * 101 + (7 if kind == "pine" else 13))
    sub = lod["sub"]
    stem_bm = bmesh.new()
    suv = stem_bm.loops.layers.uv.new("UVMap")
    if kind == "oak":
        cz, rx, rz = 3.15, 2.25, 1.38
        blobs = []
        n_shell = lod["oak_shell"]
        for i in range(n_shell):
            phi = math.acos(1 - 2 * (i + 0.5) / n_shell)
            theta = math.pi * (1 + 5 ** 0.5) * i + seed
            p = Vector((math.sin(phi) * math.cos(theta) * rx * 0.64, math.sin(phi) * math.sin(theta) * rx * 0.64, math.cos(phi) * rz * 0.5))
            p.z = max(p.z, -rz * 0.42)
            p *= rng_.uniform(0.9, 1.1)
            r = rx * rng_.uniform(0.30, 0.42) * (13.0 / n_shell) ** 0.35                  # weniger Blasen: etwas größer, die Krone bleibt voll
            blobs.append((Vector((p.x, p.y, cz + p.z)), r, (1.0, 1.0, 0.82)))
        for _ in range(lod["oak_core"]):
            blobs.append((Vector((rng_.uniform(-1, 1) * rx * 0.3, rng_.uniform(-1, 1) * rx * 0.3, cz + rz * rng_.uniform(0.0, 0.4))),
                          rx * rng_.uniform(0.40, 0.5), (1.0, 1.0, 0.9)))
        bm = f_blob_crown(blobs, sub, rng_, bump=0.24, tint=(0.98, 1.06, 0.84), tile=2.4, shade_lo=0.55, drop_down=True)
        trunk_pts = [(0, 0, 0.0), (0.02, 0.0, 0.35), (0.05, 0.02, 1.2), (0.0, 0.05, 2.0), (-0.05, 0.0, cz - 0.2)]
        f_tube(stem_bm, trunk_pts, [0.50, 0.36, 0.28, 0.22, 0.16], lod["trunk"], 2.0, suv)
        if lod["limbs"]:
            for k in range(3):
                a = seed + k * 2.1 + rng_.uniform(-0.3, 0.3)
                f_tube(stem_bm, [(0, 0, 1.8), (math.cos(a) * 0.5, math.sin(a) * 0.5, 2.5), (math.cos(a) * 1.1, math.sin(a) * 1.1, cz + 0.1)],
                       [0.15, 0.1, 0.06], 4, 2.0, suv)
        crown_mat, bark_mat = M["f_laub"], f_tex_material("F_Rinde_Eiche", "rinde.jpg", False)
    else:
        blobs = []
        n_pad = lod["pine_pads"]
        for i in range(n_pad):
            t = i / max(1, n_pad - 1)
            zc = 3.0 + 2.1 * t + rng_.uniform(-0.15, 0.15)
            reach = (1.15 - 0.75 * t) * rng_.uniform(0.8, 1.15)
            a = seed * 0.9 + i * 2.4 + rng_.uniform(-0.3, 0.3)
            r = (1.25 - 0.55 * t) * rng_.uniform(0.85, 1.12)
            blobs.append((Vector((math.cos(a) * reach, math.sin(a) * reach, zc)), r, (1.0, rng_.uniform(0.85, 1.0), 0.46)))
        blobs.append((Vector((rng_.uniform(-0.15, 0.15), rng_.uniform(-0.15, 0.15), 5.15)), 0.72, (1.0, 1.0, 0.62)))
        bm = f_blob_crown(blobs, sub, rng_, bump=0.30, tint=(1.0, 1.0, 1.0), tile=1.6, shade_lo=0.6, drop_down=True)
        bend = rng_.uniform(-0.25, 0.25)
        trunk_pts = [(0, 0, 0.0), (0.02, 0.0, 0.4), (bend * 0.2, 0.0, 1.6), (bend * 0.6, 0.05, 3.2), (bend, 0.1, 4.6), (bend * 1.1, 0.1, 5.4)]
        f_tube(stem_bm, trunk_pts, [0.27, 0.19, 0.15, 0.11, 0.07, 0.03], lod["trunk"], 2.0, suv)
        if lod["limbs"]:
            for b_ in blobs[:-1]:
                c = b_[0]
                f_tube(stem_bm, [(bend * min(1.0, c.z / 4.6), 0.0, c.z - 0.5), (c.x * 0.5, c.y * 0.5, c.z - 0.2), (c.x * 0.9, c.y * 0.9, c.z)],
                       [0.05, 0.035, 0.02], 3, 2.0, suv)
        crown_mat, bark_mat = f_tex_material("F_Nadelkrone", "nadelkrone.jpg"), f_tex_material("F_Rinde_Kiefer", "rinde.jpg", False)
    bmesh.ops.recalc_face_normals(stem_bm, faces=stem_bm.faces)
    obj_c = f_bm_object("c", bm, [crown_mat])
    obj_s = f_bm_object("s", stem_bm, [bark_mat])
    bpy.ops.object.select_all(action="DESELECT")
    obj_c.select_set(True)
    obj_s.select_set(True)
    bpy.context.view_layer.objects.active = obj_c
    bpy.ops.object.join()
    tree = bpy.context.active_object
    tree.name = key
    print("DIORAMA Baumnetz", key, sum(max(1, len(q.vertices) - 2) for q in tree.data.polygons), "Dreiecke")
    return f_register(key, tree)


def f_lod_of(x, z):
    """Detailstufe eines Baums am Ort (x, z) nach dem Abstand zur Strecke."""
    d = f_dc(x, z)
    return "near" if d < F_LOD_NEAR else ("mid" if d < F_LOD_MID else "far")


def f_trees():
    """Kiefern und Eichen: Orte aus f_tree_sites, Drehung und Größe wie die Laufzeit-Bäume (world.gd); je Entfernung zur Strecke ein
    einfacheres Netz (F_LOD), drei Varianten je Art. Gleiche Netze heißen Prop_* und werden im Spiel zu MultiMeshes zusammengefasst."""
    counts = {"near": 0, "mid": 0, "far": 0}
    for kind, x, z, sc, h0, rad in F_PLAN["trees"]:
        variant = int(abs(x * 7.3 + z * 3.1)) % 3
        lod = f_lod_of(x, z)
        counts[lod] += 1
        key = f_build_tree(kind, variant, lod)
        f_put(key, x, z, f_spin(x, z), h0 * sc, label="Prop", anchor="origin", foot=0.45 * sc)
        F_SOLIDS.append((x, z, F_CROWN[kind] * sc * 0.45))
        collide_circle(x, z, rad * sc, 4.0, "baum")
    print("DIORAMA Wald: Bäume (gesetzt, versetzt, entfallen)", f_stats.get("trees"), "Zusatzbäume", f_stats.get("extra"), "davon Auslaufzone verworfen", f_stats.get("runoff", 0), "Detailstufen", counts)


def f_rocks():
    """Die Findlinge der Streckendatei (Typ rock): wie die Bäume im Diorama gebaut (das Laufzeit-Modell wirkte neben den gebackenen Steinen
    fahl und glatt). Gleiches Modell wie die übrigen Findlinge (verkleinert, moosig), Drehung wie world.gd; Steine, die zu nah an der Fahrbahn
    liegen, rücken nach außen. Hindernis: Kreis 0,9 m x Skalierung (Maß von track.gd)."""
    n = moved = 0
    for p in data["props"]:
        if p["type"] != "rock":
            continue
        x, z, sc = p["x"], p["z"], p.get("scale", 1.0)
        need = HW + 0.9 * sc + 0.55
        if f_dc(x, z) < need:
            idx, _ = f_nearest_center(np.array([(x, z)]))
            away = np.array([x, z]) - C[idx[0]]
            away = away / (np.linalg.norm(away) + 1e-9)
            for step in np.arange(0.4, 3.5, 0.4):
                if f_dc(x + away[0] * step, z + away[1] * step) >= need:
                    x, z = x + away[0] * step, z + away[1] * step
                    moved += 1
                    break
            else:
                continue
        h = 1.0 * sc
        f_put(f_decimated("wald_felsen", 0.27), x, z, f_spin(p["x"], p["z"]), h, y=f_gy_min(x, z, 0.6 * sc) - 0.1 * h)
        f_solid(x, z, 0.9 * sc, 1.2, "mauer")
        n += 1
    print("DIORAMA Findlinge der Streckendatei:", n, "versetzt", moved)


# ---------------------------------------------------------------- Unterholz und Kleinteile (selbst gebaut, Vertexfarben "K_farbe")
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
        obj = f_bm_object(key, self.bm, [M[material_key]], link=False)
        return f_register(key, obj)


def f_lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def f_col_noise(c, rng_, amt=0.15):
    v = 1.0 + rng_.uniform(-amt, amt)
    return tuple(min(1.0, x * v) for x in c)


def f_fern(seed):
    """Farnbüschel: Wedel als gefiederte Dreiecksreihen, von dunklem Fuß zu hellen Spitzen; Fuß im Ursprung, Durchmesser ~1,6 m."""
    key = "farn%d" % seed
    if key in LIB:
        return key
    r = random.Random(seed * 31 + 5)
    b = FBuild()
    nf = 5 + seed % 3
    for k in range(nf):
        a = k * (2 * math.pi / nf) + r.uniform(-0.3, 0.3)
        L = r.uniform(0.6, 1.0)
        elev = r.uniform(0.45, 0.8)
        ca, sa = math.cos(a), math.sin(a)
        n = 4
        pts = []
        for i in range(n + 1):
            t = i / n
            hor = L * t * 0.92
            h = 0.06 + L * (math.sin(elev) * t - 0.85 * t * t) * 0.8
            pts.append(Vector((ca * hor, sa * hor, max(h, 0.025))))
        perp = Vector((-sa, ca, 0.0))
        tone = r.uniform(0.85, 1.2)
        base_c, tip_c = (0.08, 0.20, 0.07), (0.22, 0.40, 0.13)
        for i in range(n):
            t0, t1 = i / n, (i + 1) / n
            w0 = 0.14 * math.sin(math.pi * min(1.0, t0 ** 0.8)) if i else 0.04
            c0 = tuple(x * tone for x in f_lerp(base_c, tip_c, t0))
            c1 = tuple(x * tone for x in f_lerp(base_c, tip_c, t1))
            tip_l = pts[i] + perp * (w0 + 0.03) + (pts[i + 1] - pts[i]) * 0.55 + Vector((0, 0, -0.03))
            tip_r = pts[i] - perp * (w0 + 0.03) + (pts[i + 1] - pts[i]) * 0.55 + Vector((0, 0, -0.03))
            lit = tuple(min(1.0, x * 1.15) for x in c1)
            b.poly([pts[i], tip_l, pts[i + 1]], [c0, lit, c1], up=True)
            b.poly([pts[i], pts[i + 1], tip_r], [c0, c1, lit], up=True)
    return b.finish(key)


def f_tuft(seed):
    """Grasbüschel aus gebogenen Halmen (Dreiecke)."""
    key = "gras%d" % seed
    if key in LIB:
        return key
    r = random.Random(seed * 17 + 3)
    b = FBuild()
    for k in range(7):
        a = r.uniform(0, 2 * math.pi)
        h = r.uniform(0.18, 0.4)
        lean = r.uniform(0.05, 0.16)
        bx, by = r.uniform(-0.05, 0.05), r.uniform(-0.05, 0.05)
        tip = Vector((bx + math.cos(a) * lean, by + math.sin(a) * lean, h))
        perp = Vector((-math.sin(a), math.cos(a), 0)) * 0.014
        tone = r.uniform(0.85, 1.25)
        b.poly([Vector((bx, by, 0.0)) + perp, Vector((bx, by, 0.0)) - perp, tip],
               [tuple(x * tone for x in (0.10, 0.20, 0.06)), tuple(x * tone for x in (0.10, 0.20, 0.06)), tuple(min(1.0, x * tone) for x in (0.36, 0.50, 0.16))], up=True)
    return b.finish(key)


def f_reeds(seed):
    """Schilf mit Rohrkolben: schmale hohe Blätter und braune Kolben an einem Teil der Halme."""
    key = "schilf%d" % seed
    if key in LIB:
        return key
    r = random.Random(seed * 13 + 1)
    b = FBuild()
    for k in range(9):
        a = r.uniform(0, 2 * math.pi)
        h = r.uniform(0.9, 1.6)
        lean = r.uniform(0.04, 0.3)
        bx, by = r.uniform(-0.18, 0.18), r.uniform(-0.18, 0.18)
        tip = Vector((bx + math.cos(a) * lean, by + math.sin(a) * lean, h))
        perp = Vector((-math.sin(a), math.cos(a), 0)) * 0.022
        tone = r.uniform(0.85, 1.2)
        mid = Vector((bx + math.cos(a) * lean * 0.3, by + math.sin(a) * lean * 0.3, h * 0.55))
        cb, ct = tuple(x * tone for x in (0.14, 0.26, 0.08)), tuple(min(1, x * tone) for x in (0.38, 0.50, 0.17))
        b.poly([Vector((bx, by, 0.0)) + perp, Vector((bx, by, 0.0)) - perp, mid - perp * 0.8, mid + perp * 0.8], [cb, cb, ct, ct])
        b.poly([mid + perp * 0.8, mid - perp * 0.8, tip], [ct, ct, ct])
        b.poly([Vector((bx, by, 0.0)) - perp, Vector((bx, by, 0.0)) + perp, mid + perp * 0.8, mid - perp * 0.8], [cb, cb, ct, ct])
        if k % 2 == 0:                                                      # Rohrkolben: kurzer brauner Zylinder am oberen Drittel
            c0 = Vector((bx + math.cos(a) * lean * 0.22, by + math.sin(a) * lean * 0.22, h * 0.74))
            rr, hh, sd = 0.035, 0.17, 5
            ring0 = [c0 + Vector((math.cos(2 * math.pi * j / sd) * rr, math.sin(2 * math.pi * j / sd) * rr, 0)) for j in range(sd)]
            ring1 = [p + Vector((0, 0, hh)) for p in ring0]
            hc = (0.28, 0.15, 0.09)
            for j in range(sd):
                b.poly([ring0[j], ring0[(j + 1) % sd], ring1[(j + 1) % sd], ring1[j]], hc)
            b.poly(ring1, (0.34, 0.19, 0.11))
    return b.finish(key, recalc=False)


def f_stone(seed):
    """Kleiner Stein (gestauchte, verformte Kugel mit wenigen Flächen): grau, oben mit Moos, unten dunkel; Fuß im Ursprung (halb eingesunken)."""
    key = "stein%d" % seed
    if key in LIB:
        return key
    r = random.Random(seed * 7 + 2)
    bm = bmesh.new()
    res = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.5, matrix=Matrix.Diagonal((1.0, r.uniform(0.7, 0.95), r.uniform(0.5, 0.7), 1.0)), calc_uvs=False)
    for v in res["verts"]:
        n = v.co.normalized()
        v.co += n * (noise.noise(v.co * 2.4 + Vector((seed, 1, 2))) * 0.16)
        v.co.z = max(v.co.z, -0.08) + 0.12
    for f in bm.faces:
        f.smooth = False
    bm.normal_update()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.calc_center_median().z < 0.05], context="FACES")      # Unterseite liegt im Boden
    bm.normal_update()
    uv = bm.loops.layers.uv.new("UVMap")
    col = bm.loops.layers.float_color.new("Color")
    for f in bm.faces:
        n = f.normal
        g = r.uniform(0.30, 0.46)
        moss = min(1.0, max(0.0, n.z - 0.40) * 1.6)
        moss *= 0.65
        c = (g * (1 - moss) + 0.30 * moss, g * (1 - moss * 0.2) + 0.36 * moss * 0.8, g * (1 - moss) + 0.20 * moss)
        c = tuple(x * (0.55 + 0.45 * min(1.0, (f.calc_center_median().z + 0.1) / 0.3)) for x in c)
        for loop in f.loops:
            loop[uv].uv = (0.0, 0.0)
            loop[col] = (c[0] ** 2.2, c[1] ** 2.2, c[2] ** 2.2, 1.0)
    obj = f_bm_object(key, bm, [M["farbe"]], link=False)
    return f_register(key, obj)


def f_branch(seed):
    """Abgebrochener Ast mit zwei Seitenzweigen, liegend; Fuß im Ursprung."""
    key = "ast%d" % seed
    if key in LIB:
        return key
    r = random.Random(seed * 5 + 9)
    b = FBuild()
    L = r.uniform(1.5, 2.6)
    a = 0.0
    pts = [(0.0, 0.0, 0.03), (L * 0.5, r.uniform(-0.1, 0.1), 0.045), (L, r.uniform(-0.2, 0.2), 0.03)]
    f_tube(b.bm, pts, [0.04, 0.028, 0.012], 4, 2.0, b.uv)
    for k in range(2):
        t = 0.3 + 0.35 * k
        px, py = L * t, 0.0
        sgn = 1 if k == 0 else -1
        f_tube(b.bm, [(px, py, 0.04), (px + 0.35, py + sgn * 0.35, 0.05), (px + 0.65, py + sgn * 0.6, 0.035)], [0.018, 0.012, 0.006], 4, 2.0, b.uv)
    for f in b.bm.faces:
        for loop in f.loops:
            c = f_col_noise((0.27, 0.18, 0.11), r, 0.2)
            loop[b.col] = (c[0] ** 2.2, c[1] ** 2.2, c[2] ** 2.2, 1.0)
    return b.finish(key, recalc=True)


def f_bush(seed):
    """Strauch (Hasel, Brombeere): vier bis sechs verformte Blasen mit Blatttextur, flach und breit."""
    key = "busch%d" % seed
    if key in LIB:
        return key
    r = random.Random(seed * 23 + 11)
    blobs = []
    for i in range(4):
        a = i * 2.4 + r.uniform(-0.3, 0.3)
        d = r.uniform(0.0, 0.55) if i else 0.0
        rad = r.uniform(0.36, 0.55)
        blobs.append((Vector((math.cos(a) * d, math.sin(a) * d, rad * 0.9 + r.uniform(0.0, 0.2))), rad, (1.0, 1.0, 0.85)))
    bm = f_blob_crown(blobs, 1, r, bump=0.3, tint=(0.72, 0.86, 0.62), tile=1.3, shade_lo=0.5, drop_down=True)
    obj = f_bm_object(key, bm, [M["f_laub"]], link=False)
    return f_register(key, obj)


def f_variant(builder, count, seed):
    return builder(seed % count)


# ---------------------------------------------------------------- Platzierung des Waldgeräts und des Unterholzes
def f_view_box():
    """Bereich, in dem Details gebaut werden (Übersicht und Rennansicht zeigen höchstens ~18 m neben der Strecke)."""
    return (float(C[:, 0].min()) - 16.0, float(C[:, 0].max()) + 16.0, float(C[:, 1].min()) - 14.0, float(C[:, 1].max()) + 24.0)


def f_cands(rng_, n):
    xa, xb, za, zb = f_view_box()
    P = np.stack([rng_.uniform(xa, xb, n), rng_.uniform(za, zb, n)], 1)
    return P, dist_to_center(P), f_pond_sdf(P[:, 0], P[:, 1])


def f_tree_dist(P):
    """Abstand jedes Punktes zum nächsten Baumstamm."""
    T = np.array([(t[1], t[2]) for t in F_PLAN["trees"]])
    out = np.full(len(P), 99.0)
    for k in range(0, len(P), 2000):
        q = P[k:k + 2000]
        out[k:k + 2000] = np.sqrt(((q[:, None, :] - T[None, :, :]) ** 2).sum(2)).min(1)
    return out


def f_pick(P, w, count, rng_, min_dist, solid_r=0.0, core_pad=-1.6):
    """Zufällige Auswahl nach Gewicht w (0..1) mit Mindestabstand; feste Teile werden gemieden, Lichtungskerne frei gehalten."""
    chosen = []
    order = rng_.permutation(len(P))
    for i in order:
        if len(chosen) >= count:
            break
        if rng_.random() > w[i]:
            continue
        x, z = float(P[i, 0]), float(P[i, 1])
        if f_in_clearing(x, z, core_pad):
            continue
        if any((x - cx) ** 2 + (z - cz) ** 2 < min_dist ** 2 for cx, cz in chosen):
            continue
        if f_solid_blocked(x, z, solid_r):
            continue
        chosen.append((x, z))
    return chosen


def f_scatter_understory():
    rng_ = np.random.default_rng(77)
    pr = random.Random(5)
    P, dc, sd = f_cands(rng_, 26000)
    td = f_tree_dist(P)
    n1 = f_fbm(P[:, 0], P[:, 1], 6.5, 2, 40.0)
    n2 = f_fbm(P[:, 0], P[:, 1], 9.0, 2, 60.0)
    land = sd > 0.2
    count = {}
    # Büsche (Hasel, Brombeere): in Gruppen, am Rand der Lichtungen und zwischen den Bäumen, nie nahe der Fahrbahn
    wb = np.where(land & (dc > HW + 2.6), f_smooth((n2 - 0.50) * 5.0) * 0.8 + 0.12 * (td < 3.5), 0.0)
    bushes = f_pick(P, wb, 38, rng_, 2.6, 0.55)
    for x, z in bushes:
        f_put(f_bush(int(abs(x * 3.7 + z)) % 3), x, z, pr.uniform(0, 6.28), scale=pr.uniform(0.85, 1.45), anchor="origin")
        f_solid(x, z, 0.5, 1.0, "bank")
    count["busch"] = len(bushes)
    # Farne: Kolonien im Halbschatten, am Teich und neben Stämmen
    wf = np.where(land & (dc > HW + 1.6) & (dc < 15.0), np.clip(f_smooth((n1 - 0.50) * 6.0) * 0.85 + 0.35 * ((sd > 0.3) & (sd < 3.6)) + 0.12 * (td < 3.0), 0, 1), 0.0)
    ferns = f_pick(P, wf, 190, rng_, 1.15, 0.0)
    for x, z in ferns:
        f_put(f_fern(int(abs(x * 5.1 + z * 2.3)) % 3), x, z, pr.uniform(0, 6.28), scale=pr.uniform(0.75, 1.3), anchor="origin")
    count["farn"] = len(ferns)
    # Grasbüschel: am Wegrand dicht, sonst verstreut
    shoulder = (dc > HW + 0.7) & (dc < HW + 3.6)
    wt = np.where(land & (dc > HW + 0.7), np.where(shoulder, 0.8, 0.12 + 0.3 * (td < 2.5)), 0.0)
    tufts = f_pick(P, wt, 520, rng_, 0.9, 0.0, core_pad=-0.6)
    for x, z in tufts:
        f_put(f_tuft(int(abs(x * 2.9 + z * 4.1)) % 3), x, z, pr.uniform(0, 6.28), scale=pr.uniform(0.8, 1.4), anchor="origin")
    count["gras"] = len(tufts)
    # Steine und Äste
    ws = np.where(land & (dc > HW + 0.9), np.where(shoulder, 0.5, 0.12), 0.0)
    stones = f_pick(P, ws, 90, rng_, 1.1, 0.0, core_pad=-0.8)
    for x, z in stones:
        f_put(f_stone(int(abs(x * 1.9 + z * 6.1)) % 3), x, z, pr.uniform(0, 6.28), scale=pr.uniform(0.35, 0.8), anchor="origin", y=f_gy_min(x, z, 0.25) - 0.03)
    count["stein"] = len(stones)
    wa = np.where(land & (dc > HW + 1.6), 0.05 + 0.9 * (td < 3.3), 0.0)
    sticks = f_pick(P, wa, 46, rng_, 2.0, 0.0)
    for x, z in sticks:
        f_put(f_branch(int(abs(x * 4.3 + z)) % 2), x, z, pr.uniform(0, 6.28), scale=pr.uniform(0.7, 1.2), anchor="origin")
    count["ast"] = len(sticks)
    print("DIORAMA Unterholz:", count)


def f_scatter_solids():
    """Findlinge (KI-Modell, moosig), Baumstümpfe und liegende Stämme mit Hindernissen."""
    rng_ = np.random.default_rng(91)
    pr = random.Random(9)
    P, dc, sd = f_cands(rng_, 20000)
    td = f_tree_dist(P)
    land = sd > 1.0
    n1 = f_fbm(P[:, 0], P[:, 1], 8.0, 2, 80.0)
    # Findlinge: nahe am Teich, am Wegrand außen, im Wald
    wr = np.where(land & (dc > HW + 2.4) & (dc < 14.0), 0.12 + 0.7 * ((sd < 6.0) & (sd > 1.4)) + 0.25 * (n1 > 0.6), 0.0)
    rocks = f_pick(P, wr, 12, rng_, 6.0, 1.6)
    for x, z in rocks:
        h = pr.uniform(0.85, 1.5)
        f_put(f_decimated("wald_felsen", 0.27), x, z, pr.uniform(0, 6.28), h, y=f_gy_min(x, z, 0.6 * h) - 0.1 * h)
        f_solid(x, z, 0.8 * h, 1.2, "mauer")
    # Baumstümpfe
    ws = np.where(land & (dc > HW + 2.0) & (dc < 15.0), 0.15 + 0.7 * (td < 4.0), 0.0)
    stumps = f_pick(P, ws, 9, rng_, 7.0, 0.8)
    for x, z in stumps:
        h = pr.uniform(0.5, 0.85)
        f_put("wald_baumstumpf_lo", x, z, pr.uniform(0, 6.28), h, y=f_gy_min(x, z, 0.45 * h) - 0.03)
        f_solid(x, z, 0.45 * h + 0.15, 0.9, "baum")
    # Liegende Stämme, längs zur nächsten Fahrbahn gerichtet oder quer
    wl = np.where(land & (dc > HW + 2.4) & (dc < 15.0), 0.15 + 0.6 * (td < 3.5), 0.0)
    logs = f_pick(P, wl, 6, rng_, 8.0, 1.8)
    for x, z in logs:
        ang = pr.uniform(0, math.pi)
        s = pr.uniform(0.8, 1.15)
        f_put("wald_baumstamm_lo", x, z, ang, footprint=(2.9 * s, 0.9 * s), y=f_gy_min(x, z, 1.0 * s) - 0.04)
        f_solid_rect(x, z, ang, 1.35 * s, 0.38 * s, 0.7, "baum")
    print("DIORAMA Findlinge, Stümpfe, Stämme:", len(rocks), len(stumps), len(logs))


# ---------------------------------------------------------------- Teich: Schilf, Seerosen, Steg und Ruderboot
def f_pond_point(theta, offset=0.0):
    """Punkt am Teichrand in Richtung theta (Winkel im normierten Ellipsenraum); offset in Metern nach außen (näherungsweise)."""
    a, b = F_POND["w"] / 2.0, F_POND["d"] / 2.0
    k = 1.0 + 0.10 * math.sin(3 * theta + 0.7) + 0.06 * math.sin(5 * theta + 2.1) + 0.045 * math.sin(8 * theta + 4.0)
    x = F_POND["x"] + a * k * math.cos(theta)
    z = F_POND["z"] + b * k * math.sin(theta)
    n = np.array([math.cos(theta) / a, math.sin(theta) / b])
    n = n / np.linalg.norm(n)
    return x + n[0] * offset, z + n[1] * offset


def f_lily(seed):
    """Seerosenblatt: flache Scheibe mit Einschnitt, grün; jedes dritte mit weißer Blüte."""
    key = "seerose%d" % seed
    if key in LIB:
        return key
    r = random.Random(seed * 3 + 1)
    b = FBuild()
    n = 12
    rad = 0.5
    gap = r.uniform(0.0, 6.28)
    ring = []
    for k in range(n):
        t = 2 * math.pi * k / n
        if abs(((t - gap + math.pi) % (2 * math.pi)) - math.pi) < 0.25:
            continue
        ring.append(Vector((math.cos(t) * rad, math.sin(t) * rad, 0.0)))
    c0, c1 = (0.12, 0.30, 0.10), (0.22, 0.42, 0.16)
    for i in range(len(ring) - 1):
        b.poly([Vector((0, 0, 0.0)), ring[i], ring[i + 1]], [c1, c0, c0], up=True)
    if seed % 3 == 0:
        petal = (0.95, 0.93, 0.88)
        for k in range(6):
            t = 2 * math.pi * k / 6
            tip = Vector((math.cos(t) * 0.16, math.sin(t) * 0.16, 0.07))
            side = Vector((-math.sin(t), math.cos(t), 0)) * 0.05
            b.poly([Vector((0, 0, 0.02)) + side, Vector((0, 0, 0.02)) - side, tip], [petal, petal, (1.0, 0.85, 0.5)], up=True)
    return b.finish(key)


def f_puddles():
    """Schlammpfützen in den Schlammabschnitten neben der Fahrbahn: braun spiegelnde Flächen (Rand erdbraun, Mitte hell vom Himmel)."""
    r = random.Random(14)
    parts = []
    n_p = 0
    mid = tuple(v ** 2.2 for v in (0.50, 0.52, 0.52))
    edge = tuple(v ** 2.2 for v in (0.30, 0.23, 0.17))
    for zone in data.get("surfaces", []):
        if zone.get("kind") != "mud":
            continue
        i = int(zone["from"] * N) + 4
        while i < int(zone["to"] * N) - 4:
            for side in (1, -1):
                for attempt in range(4):
                    lat = side * r.uniform(HW + 2.5, HW + 4.6)
                    c = center[i + r.randint(-3, 3)] + left[i] * lat
                    a, b = r.uniform(0.8, 1.7), r.uniform(0.45, 0.85)
                    if f_dc(c.x, c.y) < HW + 2.1 or f_in_clearing(c.x, c.y, 0.5):
                        continue
                    if any(math.hypot(c.x - sx, c.y - sz) < sr + 0.45 + b for sx, sz, sr in F_PLAN["circles"]) or                             any(math.hypot(c.x - t[1], c.y - t[2]) < 0.9 + b for t in F_PLAN["trees"]):
                        continue
                    ang = math.atan2(tang[i].y, tang[i].x) + r.uniform(-0.3, 0.3)
                    ring = []
                    for k in range(14):
                        th = 2 * math.pi * k / 14
                        rr_ = r.uniform(0.82, 1.12)
                        ring.append((c.x + math.cos(ang) * math.cos(th) * a * rr_ - math.sin(ang) * math.sin(th) * b * rr_,
                                     c.y + math.sin(ang) * math.cos(th) * a * rr_ + math.cos(ang) * math.sin(th) * b * rr_))
                    ys = f_level(np.array(ring + [(c.x, c.y)])) + GROUND_Y
                    if float(ys.max() - ys.min()) > 0.14:
                        continue                                         # kein Wasser im steilen Hang
                    y = float(ys.min()) + 0.03 + 0.5 * float(ys.max() - ys.min())     # ebener Wasserspiegel; bergseitig taucht der Rand in den Boden
                    for k in range(14):
                        k2 = (k + 1) % 14
                        parts.append(("pfuetze", [(c.x, c.y, y), (ring[k][0], ring[k][1], y), (ring[k2][0], ring[k2][1], y)][::-1],
                                      [(0, 0), (1, 0), (1, 1)], None, [mid, edge, edge][::-1]))
                    n_p += 1
                    F_SOLIDS.append((c.x, c.y, 0.2))
                    break
            i += r.randint(6, 12)
    if parts:
        mesh_object("Pfuetzen", parts)
    print("DIORAMA Pfützen:", n_p)


def f_duckweed(water_y, steg_xz, boat_xz):
    """Wasserlinsendecke: matte grüne Teppiche in Flecken auf der Wasserfläche (ein stehendes Waldgewässer ist selten ganz offen). Sie bedecken
    den größten Teil des Teichs, nur die Bahn am Steg, das Boot und einige offene Stellen bleiben frei; nachts glitzert so nur wenig Wasser."""
    rr = random.Random(33)
    blobs = []
    tries = 0
    while len(blobs) < 17 and tries < 900:
        tries += 1
        x = F_POND["x"] + rr.uniform(-1, 1) * F_POND["w"] / 2
        z = F_POND["z"] + rr.uniform(-1, 1) * F_POND["d"] / 2
        if float(f_pond_sdf(x, z)) > -0.25:
            continue
        if f_noise(np.array([x]), np.array([z]), 3.4, 7.0)[0] < 0.40:
            continue                                                        # offene Stellen
        if abs(x - steg_xz[0]) < 1.1 and z > steg_xz[1] - 4.6:             # Bahn am Steg
            continue
        if math.hypot(x - boat_xz[0], z - boat_xz[1]) < 2.0:
            continue
        rad = rr.uniform(0.5, 1.15)
        blobs.append((x, z, rad, rr.uniform(0.5, 1.0), rr.uniform(0, 6.28)))
    blobs.sort(key=lambda b: -b[2])
    parts = []
    c_mid = tuple(v ** 2.2 for v in (0.22, 0.36, 0.10))
    c_edge = tuple(v ** 2.2 for v in (0.13, 0.23, 0.07))
    for i, (x, z, rad, ratio, rot) in enumerate(blobs):
        ring = []
        for k in range(14):
            th = 2 * math.pi * k / 14
            q = rr.uniform(0.78, 1.15)
            ex, ez = math.cos(th) * rad * q, math.sin(th) * rad * ratio * q
            ring.append((x + ex * math.cos(rot) - ez * math.sin(rot), z + ex * math.sin(rot) + ez * math.cos(rot)))
        y = water_y + 0.012 + 0.003 * i
        for k in range(14):
            k2 = (k + 1) % 14
            tone = rr.uniform(0.9, 1.1)
            parts.append(("linsen", [(x, z, y), (ring[k][0], ring[k][1], y), (ring[k2][0], ring[k2][1], y)][::-1], [(0, 0), (1, 0), (1, 1)], None,
                          [tuple(v * tone for v in c_mid), c_edge, c_edge][::-1]))
    if parts:
        mesh_object("Linsen", parts)
    return len(blobs), 0.003 * len(blobs)


def f_pond_decor():
    if not F_POND:
        return
    pr = random.Random(21)
    water_y = f_water_y()
    # Schilf in Gruppen am Ufer, eine Lücke am Steg im Süden
    n_reed = 0
    for k in range(26):
        theta = 2 * math.pi * k / 26 + pr.uniform(-0.1, 0.1)
        if abs(((theta - math.pi / 2 + math.pi) % (2 * math.pi)) - math.pi) < 0.55:
            continue                                                  # Steg
        if pr.random() < 0.3:
            continue
        x, z = f_pond_point(theta, pr.uniform(-0.5, 0.35))
        f_put(f_reeds(k % 3), x, z, pr.uniform(0, 6.28), scale=pr.uniform(0.75, 1.3), y=water_y - 0.05, anchor="origin")
        n_reed += 1
    # Seerosen
    n_lily = 0
    for k in range(40):
        x = F_POND["x"] + pr.uniform(-1, 1) * F_POND["w"] / 2
        z = F_POND["z"] + pr.uniform(-1, 1) * F_POND["d"] / 2
        if float(f_pond_sdf(x, z)) > -0.9:
            continue
        if n_lily >= 13:
            break
        f_put(f_lily(n_lily % 6), x, z, pr.uniform(0, 6.28), scale=pr.uniform(0.55, 0.95), y=water_y + 0.105, anchor="origin")
        n_lily += 1
    # Steg (Bretter auf Pfosten) von der Südseite ins Wasser und ein Ruderboot daneben
    sx, sz0 = f_pond_point(math.pi / 2, 0.9)
    parts = []
    g = Frame(Vector((sx, sz0)), Vector((1.0, 0.0)), Vector((0.0, -1.0)))                     # b-Achse zeigt in den Teich (nach -z)
    deck_y = water_y + 0.34
    length = 4.2
    n_planks = 14
    pw = length / n_planks
    for i in range(n_planks):
        b0 = i * pw + 0.012
        parts += box(g, "f_holz_grau", -0.62, 0.62, b0, b0 + pw - 0.025, deck_y - 0.045, deck_y)
    for side in (-0.55, 0.55):                                                                  # Längsholme
        parts += box(g, "f_holz", side - 0.05, side + 0.05, 0.0, length, deck_y - 0.16, deck_y - 0.045)
    for i in range(5):
        for side in (-0.55, 0.55):
            bpos = 0.25 + i * (length - 0.5) / 4
            parts += box(g, "f_stamm", side - 0.065, side + 0.065, bpos - 0.065, bpos + 0.065, water_y - 0.65, deck_y + (0.22 if i % 2 == 0 else 0.0))
    mesh_objects("Steg", parts)
    c = g.pt(0.0, length / 2)
    collide_rect(c.x, c.y, g.u.x, g.u.y, 0.62, length / 2, 0.4, "bank")
    # Ruderboot, an die Ostseite des Stegs gelegt
    bx, bz = g.pt(1.55, 2.2)
    f_boat(bx, bz, water_y, 1.45)
    n_dw, dw_h = f_duckweed(water_y, (sx, sz0), (bx, bz))
    print("DIORAMA Teich: Schilf", n_reed, "Seerosen", n_lily, "Linsenteppiche", n_dw)


def f_boat(x, z, water_y, ang):
    """Ruderboot (Planken, dunkelgrün gestrichen, innen Holz) mit zwei Ruderbänken und zwei Rudern; Länge 3,0 m, Breite 1,25 m."""
    b = FBuild()
    L, Wd = 3.0, 1.25
    stations = 9
    out_c, in_c, rim_c = (0.18, 0.36, 0.28), (0.55, 0.38, 0.22), (0.42, 0.30, 0.20)
    axis_pt = lambda xx: Vector((xx, 0.0, 0.22))

    def sect(i):
        t = (i / (stations - 1)) * 2 - 1                                  # -1 .. 1 (Heck .. Bug)
        hw = Wd / 2 * (1.0 - t ** 4) ** 0.55 * (0.82 if t > 0 else 1.0)
        sheer = 0.42 + 0.16 * abs(t) ** 2.2
        return t * L / 2, hw, sheer
    ring = []
    for i in range(stations):
        xx, hw, sheer = sect(i)
        ring.append([(xx, hw, sheer), (xx, hw * 0.93, sheer * 0.55), (xx, hw * 0.55, 0.06), (xx, 0.0, 0.0)])
    for i in range(stations - 1):
        for j in range(3):
            for s in (1, -1):
                p = [Vector((ring[i][j][0], s * ring[i][j][1], ring[i][j][2])), Vector((ring[i + 1][j][0], s * ring[i + 1][j][1], ring[i + 1][j][2])),
                     Vector((ring[i + 1][j + 1][0], s * ring[i + 1][j + 1][1], ring[i + 1][j + 1][2])), Vector((ring[i][j + 1][0], s * ring[i][j + 1][1], ring[i][j + 1][2]))]
                b.poly(p, out_c, out_from=axis_pt(p[0].x))
                inner = [Vector((q.x, q.y * 0.94, q.z + 0.035)) for q in p]
                b.poly(inner, in_c, out_from=axis_pt(p[0].x), inward=True)
    for i in range(stations - 1):                                         # Bordkante oben
        for s in (1, -1):
            a0, a1 = ring[i][0], ring[i + 1][0]
            b.poly([Vector((a0[0], s * a0[1], a0[2])), Vector((a1[0], s * a1[1], a1[2])), Vector((a1[0], s * (a1[1] - 0.05), a1[2] + 0.002)),
                    Vector((a0[0], s * (a0[1] - 0.05), a0[2] + 0.002))], rim_c, up=True)
    for xb in (-0.55, 0.45):                                              # Ruderbänke
        hwb = sect(int(round((xb / (L / 2) + 1) / 2 * (stations - 1))))[1]
        b.poly([Vector((xb - 0.14, -hwb * 0.92, 0.3)), Vector((xb + 0.14, -hwb * 0.92, 0.3)), Vector((xb + 0.14, hwb * 0.92, 0.3)),
                Vector((xb - 0.14, hwb * 0.92, 0.3))], (0.52, 0.38, 0.24), up=True)
    for s, off in ((1, 0.2), (-1, -0.1)):                                 # Ruder: Stange und Blatt, im Boot liegend
        b.poly([Vector((-0.8 + off, s * 0.12, 0.34)), Vector((1.0 + off, s * 0.2, 0.34)), Vector((1.0 + off, s * 0.25, 0.34)),
                Vector((-0.8 + off, s * 0.17, 0.34))], (0.62, 0.47, 0.30), up=True)
        b.poly([Vector((1.0 + off, s * 0.16, 0.345)), Vector((1.4 + off, s * 0.2, 0.345)), Vector((1.4 + off, s * 0.31, 0.345)),
                Vector((1.0 + off, s * 0.3, 0.345))], (0.62, 0.47, 0.30), up=True)
    key = f_register("ruderboot", f_bm_object("ruderboot", b.bm, [M["farbe"]], link=False))
    f_put(key, x, z, ang, y=water_y - 0.1, anchor="origin", scale=1.0)
    collide_rect(x, z, math.cos(ang), math.sin(ang), 1.5, 0.62, 0.5, "bank")
    F_SOLIDS.append((x, z, 1.5))


# ---------------------------------------------------------------- Hütte und Hof, Hochsitz, Holzpolter, Wegweiser
def f_quad(key, p0, p1, p2, p3, tile=2.0):
    """Beliebiges Viereck (x, z, y) mit UV in Metern / tile."""
    pts = [p0, p1, p2, p3]
    e1 = Vector(p1) - Vector(p0)
    e2 = Vector(p3) - Vector(p0)
    u1, u2 = e1.normalized(), (e2 - e1.normalized() * e2.dot(e1.normalized())).normalized()
    uvs = [((Vector(p) - Vector(p0)).dot(u1) / tile, (Vector(p) - Vector(p0)).dot(u2) / tile) for p in pts]
    return (key, [(p[0], p[1], p[2]) for p in pts], uvs)


# ---------------------------------------------------------------- Blockhütte (eigener Bau statt KI-Modell)
def fV(x, z, h):
    """Blender-Punkt aus Spielkoordinaten (x, z) und Höhe h."""
    return Vector((x, -z, h))


def f_fbox(fb, g, a0, a1, b0, b1, y0, y1, col, top=None, bottom=None):
    """Quader im Bezugssystem g (a, b) mit Vertexfarbe für FBuild (Normalen zeigen nach außen)."""
    P = lambda a, b, y: fV(*g.pt(a, b), y)
    cen = P((a0 + a1) / 2, (b0 + b1) / 2, (y0 + y1) / 2)
    fb.poly([P(a0, b0, y0), P(a1, b0, y0), P(a1, b0, y1), P(a0, b0, y1)], col, out_from=cen)
    fb.poly([P(a1, b0, y0), P(a1, b1, y0), P(a1, b1, y1), P(a1, b0, y1)], col, out_from=cen)
    fb.poly([P(a1, b1, y0), P(a0, b1, y0), P(a0, b1, y1), P(a1, b1, y1)], col, out_from=cen)
    fb.poly([P(a0, b1, y0), P(a0, b0, y0), P(a0, b0, y1), P(a0, b1, y1)], col, out_from=cen)
    fb.poly([P(a0, b0, y1), P(a1, b0, y1), P(a1, b1, y1), P(a0, b1, y1)], top or col, out_from=cen)
    if bottom is not None:
        fb.poly([P(a0, b0, y0), P(a1, b0, y0), P(a1, b1, y0), P(a0, b1, y0)], bottom, out_from=cen)


def f_log(bm, uvl, caps, g, p0, p1, y, r, rng_, sides=6, head=(0.70, 0.52, 0.33)):
    """Waagerechter Rundstamm von (a0, b0) nach (a1, b1) in Höhe y; die Maserung läuft entlang des Stamms, die Stirnflächen sind hell."""
    q0, q1 = g.pt(*p0), g.pt(*p1)
    n0 = len(bm.faces)
    f_tube(bm, [fV(q0.x, q0.y, y), fV(q1.x, q1.y, y)], [r, r * 0.97], sides, 2.0, uvl, swap=True)
    off = rng_.random()
    for f in list(bm.faces)[n0:]:
        for loop in f.loops:
            loop[uvl].uv = (loop[uvl].uv[0] + off, loop[uvl].uv[1])
    axis = fV(q1.x - q0.x, q1.y - q0.y, 0.0).normalized()
    side = Vector((-axis.y, axis.x, 0.0))
    tone = rng_.uniform(0.9, 1.08)
    for q, sgn, rad in ((q0, -1, r), (q1, 1, r * 0.97)):
        c = fV(q.x, q.y, y)
        ring = [c + (side * math.cos(2 * math.pi * k / sides) + Vector((0, 0, 1)) * math.sin(2 * math.pi * k / sides)) * rad for k in range(sides)]
        caps.poly(ring, tuple(min(1.0, v * tone) for v in head), out_from=c - axis * sgn)


def f_tint_parts(parts, col):
    """Flächenliste mit gleichmäßiger Vertexfarbe versehen (box() liefert Teile mit und ohne Blickrichtung)."""
    return [(p[0], p[1], p[2], p[3] if len(p) > 3 else None, [col] * len(p[1])) for p in parts]


def f_segments(lo, hi, cuts, min_len=0.12):
    """Teilstücke von [lo, hi] ohne die Aussparungen cuts (Tür, Fenster)."""
    out, cur = [], lo
    for c0, c1 in sorted(cuts):
        if c0 > cur and c0 - cur > min_len:
            out.append((cur, c0))
        cur = max(cur, c1)
    if hi - cur > min_len:
        out.append((cur, hi))
    return out


F_CAB = {}            # Maße der Hütte (A, B halbe Länge/Tiefe, Ort der Fenster ...), für Hof, Lichter und Prüfung


def f_cabin_build():
    """Blockhütte aus Rundstämmen: Sockel aus Feldsteinen, Eckverbindung mit überstehenden Stammköpfen, Satteldach aus verwitterten
    Holzschindeln mit Moos, Schornstein aus Feldsteinen auf dem First, Tür mit Stufe, Fenster mit grünen Läden (nachts hell: echte Lampe im
    Raum, add_light), Wandlaterne an der Tür, Regenrinne mit Fallrohr und eine Bank unter dem Fenster. Hindernis: Rechteck 5 x 4 m."""
    cab = F_PLAN.get("cabin")
    if not cab:
        return
    cx, cz, ang = cab
    g = Frame(Vector((cx, cz)), Vector((math.cos(ang), math.sin(ang))), Vector((-math.sin(ang), math.cos(ang))))
    P = lambda a, b, y: fV(*g.pt(a, b), y)
    A, B = 2.15, 1.65                      # halbe Länge (a, Firstrichtung) und Tiefe (b, Tür vorn = +b) der Wände, außen
    R, PITCH, OV = 0.165, 0.30, 0.22       # Stammradius, Lagenabstand, Überstand der Stammköpfe
    BASE = 0.16                            # Sockelhöhe
    y0 = GROUND_Y
    RIDGE = y0 + 3.85
    SLOPE = 0.72                           # Dachneigung (Höhe je Meter zum First)
    EB, EA = 0.55, 0.38                    # Dachüberstand an den Traufen (b) und Giebeln (a)
    DOOR, WIN, WIN_B = (-1.30, -0.30), (0.80, 1.80), (-0.55, 0.55)
    rr = random.Random(41)
    F_CAB.update({"g": g, "A": A, "B": B, "y0": y0})
    det = FBuild()
    # --- Sockel aus Feldsteinen (Blöcke entlang der Wandlinie)
    def plinth(a_lo, a_hi, b_lo, b_hi, along_a):
        pos = a_lo if along_a else b_lo
        end = a_hi if along_a else b_hi
        while pos < end - 0.05:
            ln = min(rr.uniform(0.45, 0.85), end - pos)
            tone = rr.uniform(0.46, 0.64)
            col = (tone, tone * rr.uniform(0.95, 1.02), tone * rr.uniform(0.86, 0.96))
            top = y0 + BASE + rr.uniform(-0.015, 0.02)
            if along_a:
                f_fbox(det, g, pos, pos + ln - 0.02, b_lo, b_hi, y0 - 0.04, top, col, top=tuple(min(1.0, v * 1.12) for v in col))
            else:
                f_fbox(det, g, a_lo, a_hi, pos, pos + ln - 0.02, y0 - 0.04, top, col, top=tuple(min(1.0, v * 1.12) for v in col))
            pos += ln
    for s in (1, -1):
        plinth(-A - 0.04, A + 0.04, (B - 0.42) if s > 0 else -B - 0.04, (B + 0.04) if s > 0 else -(B - 0.42), True)
        plinth((A - 0.42) if s > 0 else -A - 0.04, (A + 0.04) if s > 0 else -(A - 0.42), -(B - 0.42), B - 0.42, False)
    # --- Wände aus Rundstämmen
    logs = bmesh.new()
    luv = logs.loops.layers.uv.new("UVMap")
    caps = FBuild()
    for side in (1, -1):                                                      # Langwände: vorn (+b) mit Tür und Fenster, hinten ein kleines Fenster
        b = side * (B - R)
        for k in range(8):
            cuts = []
            if side > 0:
                if k <= 5:
                    cuts.append(DOOR)
                if 2 <= k <= 4:
                    cuts.append(WIN)
            elif 3 <= k <= 4:
                cuts.append(WIN_B)
            y = y0 + BASE + R + k * PITCH
            for s0, s1 in f_segments(-(A + OV), A + OV, cuts):
                f_log(logs, luv, caps, g, (s0, b), (s1, b), y, R, rr)
    for side in (1, -1):                                                      # Giebelwände: sieben Lagen, um eine halbe Lage versetzt
        a = side * (A - R)
        for k in range(7):
            y = y0 + BASE + R + k * PITCH + PITCH / 2
            f_log(logs, luv, caps, g, (a, -(B + OV)), (a, B + OV), y, R, rr)
    bmesh.ops.recalc_face_normals(logs, faces=logs.faces)
    f_bm_object("Huette_Staemme", logs, [M["f_stamm"]])
    f_bm_object("Huette_Kappen", caps.bm, [M["farbe"]])
    # --- Flächen mit Texturen: Giebel (senkrechte Bretter), Dach, Zierbretter, Tür, Fensterrahmen, Bank, Regenrinne
    parts = []
    y_side_top = y0 + BASE + R + 6 * PITCH + PITCH / 2 + R                    # Oberkante der Giebelwände
    roof_under = lambda bb: RIDGE - 0.07 - SLOPE * abs(bb)
    for side in (1, -1):
        a = side * (A - 0.12)
        pts_b = [(-(B - R), y_side_top), (B - R, y_side_top), (B - R, roof_under(B - R)), (0.0, roof_under(0.0)), (-(B - R), roof_under(B - R))]
        corners = [(*g.pt(a, bb), yy) for bb, yy in pts_b]
        uvs = [(yy * 0.9, bb * 0.9) for bb, yy in pts_b]
        parts.append(("f_holz", corners, uvs, (g.u.x * side, g.u.y * side)))
    # Dach: je Seite ein Raster aus Flächen mit Vertexfarbe (Moos vor allem auf der sonnenabgewandten Seite, dunkel an den Traufen)
    sun = Vector((0.55, -0.85))                                               # Richtung zur Sonne in der Übersicht (Schatten fallen nach unten links)
    na, nb = 10, 4
    a_lo, a_hi = -(A + EA), A + EA
    def roof_col(a, bb):
        n1 = f_fbm(np.array([cx + a * 2.0]), np.array([cz + bb * 2.0]), 2.2, 2, 3.0)[0]
        face = g.v * (1 if bb >= 0 else -1)
        shade = 0.5 - 0.5 * float(face.dot(sun))                                # 1 = sonnenabgewandt
        moss = f_smooth((n1 - 0.40 + 0.42 * (shade - 0.5)) * 4.0) * (0.35 + 0.65 * shade)
        v = rr.uniform(0.93, 1.05) * (0.84 + 0.16 * (1.0 - abs(bb) / (B + EB)))
        return (min(1.0, v * (1.0 - 0.18 * moss)), min(1.0, v * (1.0 - 0.02 * moss)), min(1.0, v * (1.0 - 0.26 * moss)))
    for side in (1, -1):
        grid = {}
        for i in range(na + 1):
            for j in range(nb + 1):
                a = a_lo + (a_hi - a_lo) * i / na
                bb = side * (B + EB) * j / nb
                grid[(i, j)] = (a, bb, RIDGE - SLOPE * abs(bb), roof_col(a, bb))
        for i in range(na):
            for j in range(nb):
                q = [grid[(i, j)], grid[(i + 1, j)], grid[(i + 1, j + 1)], grid[(i, j + 1)]]
                corners = [(*g.pt(p[0], p[1]), p[2]) for p in q]
                slope_len = lambda bb: abs(bb) * math.hypot(1.0, SLOPE)
                uvs = [(p[0] / 2.4, -slope_len(p[1]) / 2.4) for p in q]
                parts.append(("f_dach", corners, uvs, None, [p[3] for p in q]))
    # Zierbretter: Trauf-/Ortgangbretter, First
    for side in (1, -1):
        bo = side * (B + EB)
        yo = RIDGE - SLOPE * (B + EB)
        parts += box(g, "f_holz_grau", a_lo - 0.02, a_hi + 0.02, bo - 0.02, bo + 0.02, yo - 0.17, yo + 0.0)
        for a in (a_lo - 0.02, a_hi + 0.02):                                    # Ortgangbrett: schmales Viereck entlang der Schräge
            p0, p1 = (a, side * (B + EB), yo), (a, 0.0, RIDGE)
            wd = 0.18
            corners = [(*g.pt(p0[0], p0[1]), p0[2] - 0.02), (*g.pt(p1[0], p1[1]), p1[2] - 0.02), (*g.pt(p1[0], p1[1]), p1[2] + wd * 0.5), (*g.pt(p0[0], p0[1]), p0[2] - 0.02 + wd)]
            parts.append(("f_holz_grau", corners, [(0, 0), (3, 0), (3, 0.25), (0, 0.25)], (g.u.x * (1 if a > 0 else -1), g.u.y * (1 if a > 0 else -1))))
        corners = [(*g.pt(a_lo - 0.02, side * 0.24), RIDGE - SLOPE * 0.24 + 0.045), (*g.pt(a_hi + 0.02, side * 0.24), RIDGE - SLOPE * 0.24 + 0.045),
                   (*g.pt(a_hi + 0.02, 0.0), RIDGE + 0.07), (*g.pt(a_lo - 0.02, 0.0), RIDGE + 0.07)]
        parts.append(("f_holz_grau", corners, [(0, 0), (4, 0), (4, 0.3), (0, 0.3)], None))
    for side in (1, -1):                                                                                                 # Pfette über den Langwänden
        parts += box(g, "f_holz_grau", -(A + OV), A + OV, (B - 0.34) if side > 0 else -B, B if side > 0 else -(B - 0.34), y0 + 2.46, y0 + 2.62)
    # Tür
    yd0, yd1 = y0 + 0.02, y0 + BASE + 1.82
    d0, d1 = DOOR
    parts += box(g, "f_holz", d0 + 0.08, d1 - 0.08, B - R - 0.04, B - R + 0.03, y0 + 0.06, yd1 - 0.04)                  # Türblatt aus Brettern
    parts += box(g, "f_holz_grau", d0 - 0.06, d0 + 0.08, B - 0.36, B + 0.04, y0, yd1 + 0.04)                            # Pfosten
    parts += box(g, "f_holz_grau", d1 - 0.08, d1 + 0.06, B - 0.36, B + 0.04, y0, yd1 + 0.04)
    parts += box(g, "f_holz_grau", d0 - 0.08, d1 + 0.08, B - 0.36, B + 0.05, yd1 - 0.04, yd1 + 0.10)                   # Sturz
    f_fbox(det, g, d0 - 0.18, d1 + 0.18, B + 0.0, B + 0.58, y0 - 0.03, y0 + 0.17, (0.55, 0.54, 0.50), top=(0.64, 0.62, 0.57))   # Stufe aus Stein
    for hy in (0.35, 1.45):                                                                                           # Bänder
        f_fbox(det, g, d0 + 0.08, d1 - 0.08, B - R + 0.03, B - R + 0.045, y0 + hy, y0 + hy + 0.11, (0.10, 0.10, 0.11))
    f_fbox(det, g, d1 - 0.22, d1 - 0.16, B - R + 0.03, B - R + 0.08, y0 + 0.95, y0 + 1.03, (0.14, 0.13, 0.12))         # Türgriff
    # Fenster vorn: Rahmen, Scheibe (K_lampe: nachts warmes Licht von der Lampe im Raum), Sprossen, Läden
    wa0, wa1 = WIN
    wy0, wy1 = y0 + BASE + 0.63, y0 + BASE + 1.50
    parts += box(g, "f_holz_grau", wa0 - 0.10, wa1 + 0.10, B - 0.36, B + 0.11, wy0 - 0.07, wy0)                         # Fensterbank
    parts += box(g, "f_holz_grau", wa0 - 0.06, wa0 + 0.03, B - 0.36, B + 0.04, wy0, wy1 + 0.02)
    parts += box(g, "f_holz_grau", wa1 - 0.03, wa1 + 0.06, B - 0.36, B + 0.04, wy0, wy1 + 0.02)
    parts += box(g, "f_holz_grau", wa0 - 0.08, wa1 + 0.08, B - 0.36, B + 0.04, wy1, wy1 + 0.08)
    pane = wall(g, "k:lampe", wa0 + 0.03, B - 0.20, wa1 - 0.03, B - 0.20, wy0 + 0.02, wy1 - 0.02, (0, 1))
    parts.append((*pane, [(0.06, 0.09, 0.11)] * 4))
    parts += box(g, "f_holz_grau", (wa0 + wa1) / 2 - 0.018, (wa0 + wa1) / 2 + 0.018, B - 0.21, B - 0.15, wy0 + 0.02, wy1 - 0.02)
    parts += box(g, "f_holz_grau", wa0 + 0.03, wa1 - 0.03, B - 0.21, B - 0.15, (wy0 + wy1) / 2 - 0.018, (wy0 + wy1) / 2 + 0.018)
    for a0_, a1_ in ((wa0 - 0.50, wa0 - 0.08), (wa1 + 0.08, wa1 + 0.50)):                                               # offene Fensterläden an der Wand
        f_fbox(det, g, a0_, a1_, B + 0.0, B + 0.045, wy0 - 0.03, wy1 + 0.05, (0.15, 0.30, 0.19))
        for k in range(3):
            f_fbox(det, g, a0_, a1_, B + 0.045, B + 0.065, wy0 + 0.06 + k * 0.30, wy0 + 0.11 + k * 0.30, (0.12, 0.25, 0.15))
    # Fenster hinten: einfach, dunkel
    parts += box(g, "f_holz_grau", WIN_B[0] - 0.05, WIN_B[1] + 0.05, -B - 0.04, -B + 0.36, y0 + BASE + 0.93 - 0.06, y0 + BASE + 0.93)
    pane_b = wall(g, "k:farbe", WIN_B[0], -B + R + 0.0, WIN_B[1], -B + R + 0.0, y0 + BASE + 0.95, y0 + BASE + 1.49, (0, -1))
    parts.append((*pane_b, [(0.05, 0.07, 0.08)] * 4))
    # Wandlaterne links der Tür (Lampe: K_lampe, nachts an; Fassung und Arm dunkel)
    la, lb = -1.62, B + 0.02
    f_fbox(det, g, la - 0.025, la + 0.025, lb, lb + 0.14, y0 + 2.00, y0 + 2.045, (0.10, 0.10, 0.11))
    f_fbox(det, g, la - 0.075, la + 0.075, lb + 0.12, lb + 0.27, y0 + 1.90, y0 + 1.94, (0.10, 0.10, 0.11), top=(0.10, 0.10, 0.11))
    f_fbox(det, g, la - 0.075, la + 0.075, lb + 0.12, lb + 0.27, y0 + 2.16, y0 + 2.20, (0.10, 0.10, 0.11))
    parts += f_tint_parts(box(g, "k:lampe", la - 0.055, la + 0.055, lb + 0.135, lb + 0.255, y0 + 1.94, y0 + 2.16), (0.85, 0.80, 0.62))
    # Bank unter dem Fenster
    parts += box(g, "f_holz", wa0 - 0.30, wa1 + 0.16, B + 0.18, B + 0.58, y0 + 0.42, y0 + 0.47)
    for a in (wa0 - 0.18, wa1 + 0.04):
        parts += box(g, "f_stamm", a - 0.05, a + 0.05, B + 0.24, B + 0.52, y0, y0 + 0.42)
    # Regenrinne an der Vorderkante des Dachs und Fallrohr zur Regentonne
    bo = B + EB
    yo = RIDGE - SLOPE * bo
    zinc = (0.30, 0.32, 0.34)
    f_fbox(det, g, a_lo + 0.1, a_hi - 0.02, bo - 0.04, bo + 0.12, yo - 0.12, yo - 0.05, zinc, top=(0.22, 0.24, 0.26))
    f_fbox(det, g, a_hi - 0.12, a_hi - 0.02, bo - 0.02, bo + 0.10, y0 + 0.9, yo - 0.05, zinc)
    # Schornstein aus Feldsteinen auf dem First (Lagen mit leicht versetzten Maßen), Kappe aus Beton, zwei Rauchrohre
    ca0, ca1, cb0, cb1 = -1.05, -0.40, -0.31, 0.31
    yy = RIDGE - 0.45
    k = 0
    while yy < RIDGE + 0.72:
        hh = rr.uniform(0.15, 0.20)
        tone = rr.uniform(0.50, 0.66)
        col = (tone, tone * 0.97, tone * 0.90)
        f_fbox(det, g, ca0 + rr.uniform(-0.015, 0.015), ca1 + rr.uniform(-0.015, 0.015), cb0 + rr.uniform(-0.015, 0.015), cb1 + rr.uniform(-0.015, 0.015), yy, yy + hh - 0.012, col,
               top=tuple(min(1.0, v * 1.1) for v in col))
        yy += hh
        k += 1
    f_fbox(det, g, ca0 - 0.07, ca1 + 0.07, cb0 - 0.07, cb1 + 0.07, yy - 0.012, yy + 0.07, (0.66, 0.65, 0.62), top=(0.72, 0.71, 0.68))
    pot = g.pt((ca0 + ca1) / 2, 0.0)                                                                                  # Schornsteinaufsatz aus Ton
    q = lambda r_, h_: [fV(pot.x + r_ * math.cos(2 * math.pi * i / 10), pot.y + r_ * math.sin(2 * math.pi * i / 10), h_) for i in range(10)]
    for i in range(10):
        j = (i + 1) % 10
        det.poly([q(0.15, yy + 0.07)[i], q(0.15, yy + 0.07)[j], q(0.13, yy + 0.30)[j], q(0.13, yy + 0.30)[i]], (0.52, 0.24, 0.14), out_from=fV(pot.x, pot.y, yy + 0.2))
    det.poly(q(0.13, yy + 0.30), (0.05, 0.05, 0.05), up=True)
    mesh_objects("Huette", parts)
    f_bm_object("Huette_Detail", det.bm, [M["farbe"]])
    # --- Hindernisse und Lichtblocker, Lichter
    collide_rect(cx, cz, g.u.x, g.u.y, 2.5, 2.0, 2.6, "mauer")
    bx, bz = g.pt((wa0 + wa1) / 2 - 0.07, B + 0.38)
    collide_rect(bx, bz, g.u.x, g.u.y, 0.73, 0.22, 0.5, "bank")
    foot = [g.pt(sa * (A + OV), sb * (B + OV)) for sa, sb in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    add_occluder_poly([(p.x, p.y) for p in foot], height=2.7)
    wx, wz = g.pt((wa0 + wa1) / 2, B + 0.30)
    add_light(wx, wz, y0 + 1.15, (1.0, 0.66, 0.32), 1.1, 8.0, omni=True)                      # Lampe im Raum, Licht fällt aus dem Fenster
    lx, lz = g.pt(la, lb + 0.20)
    add_light(lx, lz, y0 + 2.05, (1.0, 0.78, 0.44), 0.8, 5.5, omni=False)                     # Wandlaterne an der Tür
    F_CAB.update({"win": (wx, wz), "lamp": (lx, lz)})
    print("DIORAMA Hütte (eigener Bau) bei", round(cx, 1), round(cz, 1))


def f_cabin_yard():
    cab = F_PLAN.get("cabin")
    if not cab:
        return
    cx, cz, ang = cab
    ux, uz = math.cos(ang), math.sin(ang)
    vx, vz = -math.sin(ang), math.cos(ang)

    def at(a, b):
        return cx + ux * a + vx * b, cz + uz * a + vz * b
    with FLift("lift") as lift:                     # Hütte starr auf ihre Terrasse (das Gelände legt sie eben an)
        f_cabin_build()
    F_CAB["y0"] = F_CAB.get("y0", GROUND_Y) + lift.dy
    # Brennholzstapel rechts und links der Hütte, längs zur Wand
    for a, b in ((3.35, -0.3), (-3.3, 0.6)):
        x, z = at(a, b)
        f_put("wald_holzstapel_lo", x, z, ang + math.pi / 2 + (0.0 if a > 0 else math.pi), footprint=(2.1, 0.95), y=f_gy_min(x, z, 1.0) - 0.02)
        f_solid_rect(x, z, ang + math.pi / 2, 1.0, 0.45, 1.0, "mauer")
    # Hackklotz mit Stumpf vor der linken Seite
    x, z = at(-2.3, 3.5)
    f_put("wald_baumstumpf_lo", x, z, 0.4, 0.55, y=f_gy_min(x, z, 0.3) - 0.02)
    f_solid(x, z, 0.4, 0.6, "baum")
    # Regentonne unter dem Fallrohr der Regenrinne (Ecke vorn rechts)
    x, z = at(F_CAB.get("A", 2.15) + 0.28, F_CAB.get("B", 1.65) + 0.56)
    tonne = FLift("lift").__enter__()
    parts = []
    r_, h_ = 0.42, 0.9
    sides = 14
    for k in range(sides):
        a0, a1 = 2 * math.pi * k / sides, 2 * math.pi * (k + 1) / sides
        p0, p1 = (x + math.cos(a0) * r_, z + math.sin(a0) * r_), (x + math.cos(a1) * r_, z + math.sin(a1) * r_)
        mid = (math.cos((a0 + a1) / 2), math.sin((a0 + a1) / 2))
        parts.append(("f_holz", [(p0[0], p0[1], GROUND_Y), (p1[0], p1[1], GROUND_Y), (p1[0], p1[1], GROUND_Y + h_), (p0[0], p0[1], GROUND_Y + h_)],
                      [(k / sides * 2.6, 0), ((k + 1) / sides * 2.6, 0), ((k + 1) / sides * 2.6, 0.9), (k / sides * 2.6, 0.9)], mid))
        for hy in (0.18, 0.7):
            q0, q1 = (x + math.cos(a0) * (r_ + 0.012), z + math.sin(a0) * (r_ + 0.012)), (x + math.cos(a1) * (r_ + 0.012), z + math.sin(a1) * (r_ + 0.012))
            parts.append(("stahl", [(q0[0], q0[1], GROUND_Y + hy), (q1[0], q1[1], GROUND_Y + hy), (q1[0], q1[1], GROUND_Y + hy + 0.04), (q0[0], q0[1], GROUND_Y + hy + 0.04)],
                          [(0, 0), (1, 0), (1, 1), (0, 1)], mid))
    parts.append(("f_holz_grau", [(x + math.cos(2 * math.pi * k / sides) * r_ * 0.98, z + math.sin(2 * math.pi * k / sides) * r_ * 0.98, GROUND_Y + h_ - 0.05) for k in range(sides)],
                  [(0.5 + 0.5 * math.cos(2 * math.pi * k / sides), 0.5 + 0.5 * math.sin(2 * math.pi * k / sides)) for k in range(sides)]))
    mesh_objects("Regentonne", parts)
    tonne.__exit__(None, None, None)
    f_solid(x, z, 0.45, 0.9, "baum")
    # Geländewagen des Försters neben der Hütte (erster freier Platz)
    for ca, cb in ((-5.0, 4.4), (5.2, 4.8), (-6.0, -3.2), (5.8, -3.6)):
        ax, az = at(ca, cb)
        if f_solid_blocked(ax, az, 2.2) or f_dc(ax, az) < HW + 2.6 or f_in_rect(ax, az, cx, cz, ang, 2.5, 2.0, 2.0):
            continue
        parts_c = kit_car.car_parts(ax, az, math.cos(ang + 0.5), math.sin(ang + 0.5), "gelaendewagen", (0.022, 0.07, 0.04), base_y=f_gy_min(ax, az, 2.3))
        mesh_objects("Foersterauto", parts_c)
        collide_rect(ax, az, math.cos(ang + 0.5), math.sin(ang + 0.5), 2.3, 0.95, 1.5, "auto")
        F_SOLIDS.append((ax, az, 2.4))
        print("DIORAMA Hütte: Försterauto bei", round(ax, 1), round(az, 1))
        break


def f_campfire():
    """Feuerstelle vor der Hütte: Feldsteinring, Aschefläche mit Glut, vier schräg gegeneinander gestellte Scheite, zwei Sitzstämme und ein
    Kochtopf an der Kette. Echte Lichtquelle (add_light, warmes Orange, nachts; die Flamme leuchtet nur nachts, K_lampe). Hindernisse: Ring und Sitzstämme."""
    cab = F_PLAN.get("cabin")
    if not cab:
        return
    cx, cz, ang = cab
    ux, uz = math.cos(ang), math.sin(ang)
    vx, vz = -math.sin(ang), math.cos(ang)
    spot = None
    cands = [(r_ * math.cos(math.radians(t_)), r_ * math.sin(math.radians(t_))) for r_ in (4.8, 5.6, 6.4) for t_ in (60, 30, 90, 120, 0, 150, -30, 180)]
    for clear in (3.8, 2.9, 1.9):                                                # erst mit Abstand zu den Kronen, sonst enger
        for ca, cb in cands:                                                  # bevorzugt vor der Tür, sonst rund um die Hütte (erster freier Platz)
            x, z = cx + ux * ca + vx * cb, cz + uz * ca + vz * cb
            if f_dc(x, z) >= HW + 2.8 and not f_solid_blocked(x, z, clear) and not f_in_rect(x, z, cx, cz, ang, 2.5, 2.0, 2.6):
                spot = (x, z)
                break
        if spot is not None:
            break
    if spot is None:
        return
    x, z = spot
    g = Frame(Vector((x, z)), Vector((math.cos(ang + 0.4), math.sin(ang + 0.4))), Vector((-math.sin(ang + 0.4), math.cos(ang + 0.4))))
    rr = random.Random(53)
    det, fl = FBuild(), FBuild()
    y0 = GROUND_Y
    # Feldsteinring (neun Steine, unterschiedlich groß) und dunkle Asche in der Mitte
    n = 9
    for k in range(n):
        th = 2 * math.pi * k / n + rr.uniform(-0.08, 0.08)
        rad = 0.52 + rr.uniform(-0.03, 0.05)
        ca_, cb_ = math.cos(th) * rad, math.sin(th) * rad
        hs = rr.uniform(0.11, 0.16)
        tone = rr.uniform(0.42, 0.60)
        col = (tone, tone * 0.98, tone * 0.92)
        f_fbox(det, g, ca_ - hs * 1.15, ca_ + hs * 1.15, cb_ - hs, cb_ + hs, y0 - 0.03, y0 + rr.uniform(0.15, 0.24), col, top=tuple(min(1.0, v * 1.12) for v in col))
    ash = [fV(*g.pt(math.cos(2 * math.pi * k / 14) * 0.40, math.sin(2 * math.pi * k / 14) * 0.40), y0 + 0.04) for k in range(14)]
    det.poly(ash, (0.12, 0.10, 0.09), up=True)
    ash2 = [fV(*g.pt(math.cos(2 * math.pi * k / 10) * 0.20, math.sin(2 * math.pi * k / 10) * 0.20), y0 + 0.05) for k in range(10)]
    det.poly(ash2, (0.45, 0.14, 0.05), up=True)                                    # Glut
    # Scheite: vier schlanke Stämme lehnen gegeneinander (Tipi), dazu zwei liegende Hölzer im Feuer
    logs = bmesh.new()
    luv = logs.loops.layers.uv.new("UVMap")
    for k in range(4):
        th = 2 * math.pi * k / 4 + 0.5
        p0 = g.pt(math.cos(th) * 0.42, math.sin(th) * 0.42)
        p1 = g.pt(math.cos(th + 0.25) * 0.05, math.sin(th + 0.25) * 0.05)
        f_tube(logs, [fV(p0.x, p0.y, y0 + 0.07), fV(p1.x, p1.y, y0 + 0.62)], [0.045, 0.03], 5, 2.0, luv, swap=True)
    for th in (0.3, 2.2):
        p0, p1 = g.pt(math.cos(th) * 0.38, math.sin(th) * 0.38), g.pt(-math.cos(th) * 0.38, -math.sin(th) * 0.38)
        f_tube(logs, [fV(p0.x, p0.y, y0 + 0.09), fV(p1.x, p1.y, y0 + 0.09)], [0.05, 0.05], 5, 2.0, luv, swap=True)
    bmesh.ops.recalc_face_normals(logs, faces=logs.faces)
    f_bm_object("Feuerstelle_Scheite", logs, [M["f_stamm"]])
    # Flamme: drei ineinandergesteckte Zungen (nachts hell, K_lampe)
    for k, (hgt, rad_, th0) in enumerate(((0.52, 0.17, 0.0), (0.36, 0.15, 2.1), (0.42, 0.14, 4.2))):
        cxx, czz = g.pt(math.cos(th0) * 0.07, math.sin(th0) * 0.07)
        base = [fV(cxx + math.cos(2 * math.pi * i / 5) * rad_, czz + math.sin(2 * math.pi * i / 5) * rad_, y0 + 0.22) for i in range(5)]
        tip = fV(cxx, czz, y0 + 0.22 + hgt)
        for i in range(5):
            fl.poly([base[i], base[(i + 1) % 5], tip], (1.0, 0.52 + 0.10 * k, 0.12), out_from=fV(cxx, czz, y0 + 0.3))
    f_bm_object("Feuerstelle_Flamme", fl.bm, [M["k:lampe"]])
    # Sitzstämme links und rechts des Feuers (liegende dicke Stämme auf je zwei Klötzen)
    seat = bmesh.new()
    suv = seat.loops.layers.uv.new("UVMap")
    for sa in (-1, 1):
        p0, p1 = g.pt(sa * 1.45 - 0.0, -0.75), g.pt(sa * 1.45, 0.75)
        f_tube(seat, [fV(p0.x, p0.y, y0 + 0.2), fV(p1.x, p1.y, y0 + 0.2)], [0.17, 0.17], 7, 2.0, suv, swap=True)
        for t_ in (-0.55, 0.55):
            q_ = g.pt(sa * 1.45, t_)
            f_tube(seat, [fV(q_.x, q_.y, y0 - 0.02), fV(q_.x, q_.y, y0 + 0.08)], [0.15, 0.15], 6, 2.0, suv, swap=True)
        c = g.pt(sa * 1.45, 0.0)
        f_solid_rect(c.x, c.y, math.atan2(g.v.y, g.v.x), 0.78, 0.2, 0.45, "bank")
    bmesh.ops.recalc_face_normals(seat, faces=seat.faces)
    f_bm_object("Feuerstelle_Sitze", seat, [M["f_stamm"]])
    f_bm_object("Feuerstelle_Steine", det.bm, [M["farbe"]])
    f_solid(x, z, 0.62, 0.3, "mauer")
    F_SOLIDS.append((x, z, 2.0))
    add_light(x, z, y0 + 0.55, (1.0, 0.52, 0.22), 1.6, 9.5, omni=True)
    print("DIORAMA Feuerstelle bei", round(x, 1), round(z, 1))


def f_hochsitz():
    """Hochsitz (Jagdkanzel): vier Stützen, Kabine mit Satteldach, Leiter; am Waldrand links der Strecke."""
    best = None
    for gx_ in np.arange(-50.0, -38.0, 1.5):
        for gz_ in np.arange(-24.0, 26.0, 2.0):
            if f_dc(gx_, gz_) < HW + 7.5 or f_solid_blocked(gx_, gz_, 2.5) or f_in_clearing(gx_, gz_, 1.0):
                continue
            score = f_dc(gx_, gz_) + 0.0 * gz_
            if best is None or score < best[0]:
                best = (score, gx_, gz_)
    if best is None:
        return
    _, hx, hz = best
    ang = math.atan2(f_nearest_c(hx, hz)[1] - hz, f_nearest_c(hx, hz)[0] - hx)      # Blick zur Strecke
    g = Frame(Vector((hx, hz)), Vector((math.cos(ang), math.sin(ang))), Vector((-math.sin(ang), math.cos(ang))))
    parts = []
    y0 = GROUND_Y
    floor_y = y0 + 2.2
    for a in (-0.65, 0.65):
        for b in (-0.65, 0.65):
            parts += box(g, "f_stamm", a - 0.07, a + 0.07, b - 0.07, b + 0.07, y0 - 0.05, floor_y + 1.35)
    parts += box(g, "f_holz", -0.8, 0.8, -0.8, 0.8, floor_y - 0.08, floor_y)
    for s in (-0.65, 0.65):                                                       # Kreuzstreben
        parts += box(g, "f_holz", s - 0.03, s + 0.03, -0.66, 0.66, y0 + 1.0, y0 + 1.07)
    cab_y0, cab_y1 = floor_y, floor_y + 1.35
    # Wände: Brüstung ringsum, vorne (zur Strecke, +a) offenes Fenster
    parts += box(g, "f_holz_grau", -0.72, 0.72, -0.72, -0.66, cab_y0, cab_y1)
    parts += box(g, "f_holz_grau", -0.72, 0.72, 0.66, 0.72, cab_y0, cab_y1)
    parts += box(g, "f_holz_grau", -0.72, -0.66, -0.66, 0.66, cab_y0, cab_y1)
    parts += box(g, "f_holz_grau", 0.66, 0.72, -0.66, 0.66, cab_y0, cab_y0 + 0.55)
    parts += box(g, "f_holz_grau", 0.66, 0.72, -0.66, -0.35, cab_y0 + 0.55, cab_y1)
    parts += box(g, "f_holz_grau", 0.66, 0.72, 0.35, 0.66, cab_y0 + 0.55, cab_y1)
    # Dach
    ridge = cab_y1 + 0.5
    p = lambda a, b, y: tuple(g.pt(a, b)) + (y,)
    parts.append(f_quad("f_schindel", p(-0.95, -0.95, cab_y1 - 0.02), p(0.95, -0.95, cab_y1 - 0.02), p(0.95, 0.0, ridge), p(-0.95, 0.0, ridge), 1.4))
    parts.append(f_quad("f_schindel", p(-0.95, 0.95, cab_y1 - 0.02), p(-0.95, 0.0, ridge), p(0.95, 0.0, ridge), p(0.95, 0.95, cab_y1 - 0.02), 1.4))
    parts.append(("f_holz_grau", [p(-0.72, -0.72, cab_y1), p(-0.72, 0.72, cab_y1), p(-0.72, 0.0, ridge - 0.02)], [(0, 0), (1, 0), (0.5, 0.5)], (-g.u.x, -g.u.y)))
    # Leiter an der Rückseite (-a): Holme und Sprossen
    for bb in (-0.22, 0.22):
        parts += box(g, "f_holz", -1.18, -1.1, bb - 0.035, bb + 0.035, y0, floor_y + 0.9)
    for k in range(8):
        parts += box(g, "f_holz", -1.2, -1.08, -0.22, 0.22, y0 + 0.25 + k * 0.28, y0 + 0.29 + k * 0.28)
    mesh_objects("Hochsitz", parts)
    f_solid_rect(hx, hz, ang, 0.85, 0.85, 3.6, "mauer")
    print("DIORAMA Hochsitz bei", round(hx, 1), round(hz, 1))


def f_nearest_c(x, z):
    idx, _ = f_nearest_center(np.array([(x, z)]))
    return C[idx[0]]


def f_holzpolter():
    """Holzpolter: gestapelte Stämme mit hellen Schnittflächen am Waldweg (außen an der linken Schleife)."""
    if "polter" not in F_PLAN:
        return
    px, pz, ang = F_PLAN["polter"]
    g = Frame(Vector((px, pz)), Vector((math.cos(ang), math.sin(ang))), Vector((-math.sin(ang), math.cos(ang))))
    bm = bmesh.new()
    suv = bm.loops.layers.uv.new("UVMap")
    caps = FBuild()
    rr = random.Random(3)
    L = 4.6
    for ri, count in enumerate((5, 4, 3)):
        for k in range(count):
            lat = (k - (count - 1) / 2) * 0.46
            zz = GROUND_Y + 0.23 + ri * 0.4
            rad = rr.uniform(0.2, 0.25)
            ln = L + rr.uniform(-0.2, 0.2)
            a0 = -ln / 2 + rr.uniform(-0.1, 0.1)
            p0, p1 = g.pt(a0, lat), g.pt(a0 + ln, lat)
            f_tube(bm, [(p0.x, -p0.y, zz), (p1.x, -p1.y, zz)], [rad, rad * 0.92], 8, 2.0, suv)
            for pe, rad_e, sgn in ((p0, rad, -1), (p1, rad * 0.92, 1)):
                ring = []
                for j in range(10):
                    th = 2 * math.pi * j / 10
                    ring.append(Vector((pe.x + g.v.x * math.cos(th) * rad_e, -(pe.y + g.v.y * math.cos(th) * rad_e), zz + math.sin(th) * rad_e)))
                caps.poly(ring, (0.72, 0.56, 0.36), out_from=(pe.x - g.u.x * sgn, -(pe.y - g.u.y * sgn), zz))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    f_bm_object("Polter_Staemme", bm, [M["f_stamm"]])
    f_bm_object("Polter_Kappen", caps.bm, [M["farbe"]])
    f_solid_rect(px, pz, ang, L / 2, 1.2, 1.3, "baum")
    print("DIORAMA Holzpolter bei", round(px, 1), round(pz, 1))


def f_signpost():
    """Wegweiser an der Kreuzung (KI-Modell) im oberen Keil zwischen den Fahrbahnen."""
    for zz in np.arange(5.5, 14.0, 0.5):
        if f_dc(0.0, zz) >= HW + 1.8 and not f_solid_blocked(0.0, zz, 0.5):
            f_put("wald_wegweiser_lo", 0.0, zz, math.radians(200), 2.3, y=f_gy_min(0.0, zz, 0.3) - 0.02)
            f_solid(0.0, zz, 0.28, 2.3, "mast")
            print("DIORAMA Wegweiser bei", 0.0, zz)
            return


def f_apex_bales():
    """Strohballen als Kurvenschutz außen an der rechten Schleife: zwei Lagen, kurze Wand quer zur Strecke."""
    if "bales" not in F_PLAN:
        return
    bx, bz, ang = F_PLAN["bales"]
    g = Frame(Vector((bx, bz)), Vector((math.cos(ang), math.sin(ang))), Vector((-math.sin(ang), math.cos(ang))))
    parts = []
    rr = random.Random(8)
    for layer in range(2):
        n = 6 - layer
        for k in range(n):
            a = (k - (n - 1) / 2) * 1.22
            y0 = GROUND_Y - 0.02 + layer * 0.46
            parts += box(g, "stroh", a - 0.6, a + 0.6, -0.4 + rr.uniform(-0.05, 0.05), 0.4, y0, y0 + 0.46)
            for off in (-0.2, 0.2):
                parts += box(g, "stroh_dunkel", a + off - 0.015, a + off + 0.015, -0.405, 0.405, y0, y0 + 0.472)
    mesh_objects("Strohwand", parts)
    c = g.pt(0.0, 0.0)
    f_solid_rect(c.x, c.y, ang, 3.7, 0.4, 0.95, "bank")
    print("DIORAMA Strohwand bei", round(bx, 1), round(bz, 1))


def f_stand_lamps():
    """Zwei Leuchtpfosten am Zuschauerplatz (Holzmast mit Schirmlampe, Kabel zum Aggregat am Rand): beleuchten Tribüne, Zeitnahmeturm und die
    Strohballenreihe. Echte Lichtquellen (add_light), am Tag aus; der Lampenkopf leuchtet nur nachts (K_lampe)."""
    st = f_prop("stand")
    if not st:
        return
    n = 0
    for sx_ in (-1, 1):
        x, z = st["x"] + sx_ * (st["w"] / 2 + 3.3), st["z"] - (st["d"] + 2.0) / 2 - 3.2
        if f_dc(x, z) < HW + 2.2 or f_solid_blocked(x, z, 0.5):
            continue
        heading = math.atan2(st["z"] - z, st["x"] - x)
        pole = bmesh.new()
        puv = pole.loops.layers.uv.new("UVMap")
        f_tube(pole, [fV(x, z, GROUND_Y - 0.1), fV(x, z, GROUND_Y + 4.3)], [0.13, 0.09], 7, 2.0, puv, swap=True)
        bmesh.ops.recalc_face_normals(pole, faces=pole.faces)
        f_bm_object("Leuchtpfosten", pole, [M["f_stamm"]])
        det = FBuild()
        gg = Frame(Vector((x, z)), Vector((math.cos(heading), math.sin(heading))), Vector((-math.sin(heading), math.cos(heading))))
        f_fbox(det, gg, -0.06, 0.55, -0.04, 0.04, GROUND_Y + 4.10, GROUND_Y + 4.16, (0.16, 0.16, 0.17))                      # Ausleger
        f_fbox(det, gg, 0.30, 0.78, -0.24, 0.24, GROUND_Y + 3.78, GROUND_Y + 4.06, (0.12, 0.13, 0.14), top=(0.10, 0.10, 0.11))  # Schirm
        f_fbox(det, gg, -0.12, 0.12, -0.12, 0.12, GROUND_Y + 0.5, GROUND_Y + 1.35, (0.20, 0.30, 0.20))                          # Schaltkasten am Fuß
        f_bm_object("Leuchtpfosten_Detail", det.bm, [M["farbe"]])
        fl = FBuild()                                                                                                          # Leuchtfläche unter dem Schirm, blickt nach unten
        P4 = lambda a_, b_: fV(*gg.pt(a_, b_), GROUND_Y + 3.77)
        fl.poly([P4(0.34, -0.2), P4(0.74, -0.2), P4(0.74, 0.2), P4(0.34, 0.2)], (0.9, 0.85, 0.7), out_from=fV(*gg.pt(0.54, 0.0), GROUND_Y + 4.2))
        f_bm_object("Leuchtpfosten_Lampe", fl.bm, [M["k:lampe"]])
        f_solid(x, z, 0.2, 4.3, "mast")
        lx, lz = gg.pt(0.55, 0.0)
        add_light(lx, lz, GROUND_Y + 3.7, (1.0, 0.84, 0.58), 1.0, 11.5, omni=False, glow=0.9)
        n += 1
    print("DIORAMA Leuchtpfosten am Zuschauerplatz:", n)


def f_strohballen():
    """Strohballen (Rallye-Absperrung) in einer Reihe vor der Tribüne, die zweite Lage versetzt."""
    st = f_prop("stand")
    if not st:
        return
    parts = []
    z_row = st["z"] - (st["d"] + 2.0) / 2 - 2.0
    n = 9
    pitch = (st["w"] + 3.0) / (n - 1)
    for k in range(n):
        x = st["x"] - st["w"] / 2 - 1.5 + k * pitch
        if f_dc(x, z_row) < HW + 2.2:
            continue
        g = Frame(Vector((x, z_row)), Vector((1.0, 0.0)), Vector((0.0, 1.0)))
        parts += box(g, "stroh", -0.6, 0.6, -0.4, 0.4, GROUND_Y - 0.02, GROUND_Y + 0.46)
        for a in (-0.2, 0.2):
            parts += box(g, "stroh_dunkel", a - 0.015, a + 0.015, -0.405, 0.405, GROUND_Y - 0.02, GROUND_Y + 0.472)
        collide_rect(x, z_row, 1.0, 0.0, 0.6, 0.4, 0.5, "bank")
        F_SOLIDS.append((x, z_row, 0.8))
        if k % 2 == 1:
            g2 = Frame(Vector((x - pitch / 2, z_row)), Vector((1.0, 0.0)), Vector((0.0, 1.0)))
            parts += box(g2, "stroh", -0.6, 0.6, -0.4, 0.4, GROUND_Y + 0.46, GROUND_Y + 0.94)
            for a in (-0.2, 0.2):
                parts += box(g2, "stroh_dunkel", a - 0.015, a + 0.015, -0.405, 0.405, GROUND_Y + 0.46, GROUND_Y + 0.952)
    if parts:
        mesh_objects("Strohballen", parts)


# ---------------------------------------------------------------- Holzbrücke über den Hohlweg (Höhenplan 4.3/7): Widerlager, Träger, Bohlen, Geländer
# Die Fahrbahn der Brücke (Schotter) baut das Spiel zur Laufzeit; das Diorama trägt sie ("supports": keine Laufzeit-Pfeiler). Brückenstücke
# sind die Mittellinienstützen, deren Fahrbahn mehr als F_BRIDGE_GAP über dem Gelände liegt; an ihren Enden (Brückenköpfen) stehen die
# Widerlager. Alles über dem unteren Ast heißt "Deck_*" (im Zeichenmodus durchscheinend, damit die Linie darunter sichtbar bleibt).
F_BR = {}
F_RAIL_LAT = 4.85                  # Geländer (Pfosten) neben der Mittellinie: Die Leitplanken-Physik hält die Wagenmitte bei HW + 0,7 = 4,2 m
F_DECK_HALF = 5.05                 # halbe Länge der Querbohlen


def f_tpos(a, lat=0.0):
    """Punkt (x, z), Tangente und Linksnormale an Bogenlänge a (m) der Mittellinie mit Seitenabstand lat (links positiv)."""
    D = np.array(dist[:N])
    fi = float(np.interp(a % TOTAL, D, np.arange(N)))
    i = int(fi) % N
    f = fi - int(fi)
    j = (i + 1) % N
    p = C[i] * (1 - f) + C[j] * f
    lf = f_left()[i] * (1 - f) + f_left()[j] * f
    lf = lf / np.linalg.norm(lf)
    return p + lf * lat, np.array([lf[1], -lf[0]]), lf


def f_runtime_posts():
    """Holzpfosten und Feldsteine, die das Spiel neben der Schotterpiste setzt (track.gd Circuit.build_edge_posts; seit 03.10.2026
    Hindernisse der Spielebene mit der Innenkante 1,0 m neben dem Fahrbahnrand): (a, Seite, x, z). Nachgerechnet sind Abstand, Kreuzungs-
    und Höhenregel; das Spiel lässt außerdem Pfosten in Flugzonen (Schanze, Lücke, Looping) und an Hindernissen des Dioramas weg – der Wald
    hat keine Flugzonen, und an den Brückenköpfen stehen die beiden Pfosten frei (geprüft 03.10.2026)."""
    out = []
    count = int(TOTAL / 3.2)
    f_lv_setup()
    for i in range(count):
        s = i / count
        b = base_height(s)
        lateral = HW + 1.0 + (0.38 if i % 5 == 2 else 0.09)                # Feldstein (jeder fünfte Platz) bzw. Holzpfosten
        for edge in (-1.0, 1.0):
            p, _, _ = f_tpos(s * TOTAL, edge * lateral)
            far = np.abs(((S_OF - s + 0.5) % 1.0) - 0.5) > 0.12            # Abstand zu fernen Streckenteilen (other_branch_distance)
            if far.any() and float(np.sqrt(((C[far] - p) ** 2).sum(1)).min()) < lateral:
                continue
            if b - float(f_ty(np.array([p]))[0]) > 1.0:
                continue
            out.append((s * TOTAL, edge, float(p[0]), float(p[1])))
    return out


def f_bridge():
    f_lv_setup()
    bi = np.nonzero(_F_LV["bridge"])[0]
    if not len(bi):
        return
    if bi.max() - bi.min() + 1 != len(bi):
        print("DIORAMA Warnung: Brücke nicht zusammenhängend, kein Brückenbau")
        return
    D = np.array(dist[:N])
    i_a, i_b = int(bi.min()) - 1, int(bi.max()) + 1
    a_A, a_B = float(D[i_a]), float(D[i_b])
    base_of = lambda a: float(np.interp(a, D, _F_LV["base"]))
    b_mid = base_of((a_A + a_B) / 2)
    rr = random.Random(77)
    F_BR.update(a_A=a_A, a_B=a_B, s_A=a_A / TOTAL, s_B=a_B / TOTAL, b=b_mid)
    PLANK_TOP = 0.15                                  # Oberkante der Bohlen über der Fahrbahnbasis (die Laufzeit-Schotterbahn liegt bei 0,17)
    PLANK_T = 0.11
    R_IN, R_OUT = 0.29, 0.25
    SEAT = PLANK_TOP - PLANK_T - 2 * R_IN             # Auflager der Träger (Unterkante) relativ zur Fahrbahnbasis
    SILL_H = 0.28
    TOP = SEAT - SILL_H                               # Oberkante der Widerlager
    AB_FRONT, AB_BACK, AB_HALF = 1.4, 0.6, 6.2        # Widerlager: Stirn 1,4 m vor dem Brückenkopf (im Hang), 0,6 m dahinter, halbe Breite
    LAT_IN, LAT_OUT = 1.5, 3.9
    # Pfosten des Spiels im Bereich der Brücke: keine Bohle an ihrer Stelle
    posts = [(a, e) for a, e, x, z in f_runtime_posts() if a_A - AB_BACK - 1.5 < a < a_B + AB_BACK + 1.5]

    def post_clash(a0, a1, side):
        return any(e == side and a0 - 0.14 < a < a1 + 0.14 for a, e in posts)

    # --- Widerlager (Feldsteinmauerwerk, nicht durchscheinend): Stirn zum Hohlweg, Flanken, Hintermauerung dunkel (Fugen)
    stones = FBuild()
    for face, sgn in ((a_A, 1.0), (a_B, -1.0)):
        a_front = face + sgn * AB_FRONT
        a_back = face - sgn * AB_BACK
        y_top = base_of(face) + TOP
        p_c, t_c, l_c = f_tpos((a_front + a_back) / 2)
        g = Frame(Vector(p_c), Vector(t_c * sgn), Vector(l_c))                       # a zeigt zum Hohlweg
        half_a = (AB_FRONT + AB_BACK) / 2
        corners = np.array([tuple(g.pt(aa, bb)) for aa in (-half_a, 0.0, half_a) for bb in np.linspace(-AB_HALF, AB_HALF, 7)])
        y_bot = float(f_level(corners).min()) + GROUND_Y - 0.45
        f_fbox(stones, g, -half_a + 0.06, half_a - 0.06, -AB_HALF + 0.06, AB_HALF - 0.06, y_bot, y_top - 0.02, (0.10, 0.09, 0.08), top=(0.24, 0.25, 0.19))
        # Steinlagen auf Stirn (a = +half_a) und Flanken (b = +-AB_HALF)
        for wall_ in ("stirn", "links", "rechts"):
            length = 2 * AB_HALF if wall_ == "stirn" else 2 * half_a
            y = y_top
            course = 0
            while y > y_bot + 0.1:
                hgt = rr.uniform(0.26, 0.40)
                pos = -length / 2 + (rr.uniform(0.0, 0.3) if course % 2 else 0.0)
                while pos < length / 2 - 0.05:
                    ln = min(rr.uniform(0.45, 0.95), length / 2 - pos)
                    tone = rr.uniform(0.27, 0.46)                                    # Feldsteine, vom Wetter dunkel, oben oft bemoost
                    col = (tone, tone * rr.uniform(0.94, 1.0), tone * rr.uniform(0.80, 0.90))
                    moss = rr.random() < 0.35
                    top_c = (0.22, 0.29, 0.12) if moss else tuple(min(1.0, v * 1.08) for v in col)
                    depth = rr.uniform(0.0, 0.05)
                    y0_, y1_ = y - hgt + 0.02, y - rr.uniform(0.0, 0.02)
                    if wall_ == "stirn":
                        q = (half_a, pos + ln / 2)
                        box_ = (half_a - 0.3, half_a + 0.03 - depth, pos + 0.015, pos + ln - 0.015)
                    else:
                        sb = 1.0 if wall_ == "links" else -1.0
                        q = (pos + ln / 2, sb * AB_HALF)
                        bb0, bb1 = sb * AB_HALF - sb * 0.3, sb * AB_HALF + sb * (0.03 - depth)
                        box_ = (pos + 0.015, pos + ln - 0.015, min(bb0, bb1), max(bb0, bb1))
                    ground = f_gy(*g.pt(*q))
                    if y1_ > ground - 0.05:
                        f_fbox(stones, g, box_[0], box_[1], box_[2], box_[3], max(y0_, y_bot), y1_, col, top=top_c)
                    pos += ln
                y -= hgt
                course += 1
        # Auflagerbalken (Kantholz) quer über die Stirn, darauf liegen die Träger
        q0, _, _ = f_tpos(face + sgn * (AB_FRONT - 0.55))
        gs = Frame(Vector(q0), Vector(t_c), Vector(l_c))
        mesh_objects("Widerlager_Schwelle_%s" % ("A" if sgn > 0 else "B"), box(gs, "f_holz", -0.22, 0.22, -5.3, 5.3, y_top - 0.02, y_top + SILL_H))
    f_bm_object("Widerlager_Steine", stones.bm, [M["farbe"]])
    # --- Längsträger: vier Rundhölzer von Widerlager zu Widerlager, die äußeren mit Moos
    trunks = bmesh.new()
    tuv = trunks.loops.layers.uv.new("UVMap")
    caps, moss = FBuild(), FBuild()
    g0 = Frame(Vector((0.0, 0.0)), Vector((1.0, 0.0)), Vector((0.0, 1.0)))
    a0, a1 = a_A + AB_FRONT - 1.2, a_B - AB_FRONT + 1.2
    for lat, r in ((-LAT_OUT, R_OUT), (-LAT_IN, R_IN), (LAT_IN, R_IN), (LAT_OUT, R_OUT)):
        p0, _, _ = f_tpos(a0, lat)
        p1, _, _ = f_tpos(a1, lat)
        yc = b_mid + SEAT + r
        f_log(trunks, tuv, caps, g0, (p0[0], p0[1]), (p1[0], p1[1]), yc, r, rr, sides=8)
        if abs(lat) > 3.0:                                                         # Moos oben auf den äußeren Trägern (fleckig)
            a = a0 + rr.uniform(0.0, 1.0)
            while a < a1 - 0.5:
                ln = rr.uniform(0.4, 1.6)
                if rr.random() < 0.55:
                    pa, _, _ = f_tpos(a, lat)
                    pb, _, _ = f_tpos(min(a + ln, a1), lat)
                    w_ = r * rr.uniform(0.45, 0.75)
                    n_ = np.array([-(pb - pa)[1], (pb - pa)[0]]) / max(float(np.linalg.norm(pb - pa)), 1e-6)
                    yy = yc + r * 0.93
                    c_ = (0.20 * rr.uniform(0.85, 1.15), 0.30 * rr.uniform(0.85, 1.15), 0.10)
                    moss.poly([fV(*(pa - n_ * w_), yy), fV(*(pb - n_ * w_), yy), fV(*(pb + n_ * w_), yy), fV(*(pa + n_ * w_), yy)], c_, up=True)
                a += ln + rr.uniform(0.2, 1.2)
    bmesh.ops.recalc_face_normals(trunks, faces=trunks.faces)
    f_bm_object("Deck_Traeger", trunks, [M["f_stamm"]])
    f_bm_object("Deck_Traeger_Kappen", caps.bm, [M["farbe"]])
    f_bm_object("Deck_Moos", moss.bm, [M["farbe"]])
    # --- Querbohlen über die ganze Länge (unter der Laufzeit-Schotterbahn, sichtbar an den Rändern), leicht unregelmäßig
    planks = []
    a = a_A + AB_FRONT - 1.3
    n_pl = 0
    while a < a_B - AB_FRONT + 1.3:
        w = rr.uniform(0.27, 0.33)
        p, t, lf = f_tpos(a + w / 2)
        fr = Frame(Vector(p), Vector(t), Vector(lf))
        yb = base_of(a) + PLANK_TOP - rr.uniform(0.0, 0.012)
        l0 = -(F_DECK_HALF + rr.uniform(-0.12, 0.12))
        l1 = F_DECK_HALF + rr.uniform(-0.12, 0.12)
        if post_clash(a, a + w, -1.0):
            l0 = -4.1
        if post_clash(a, a + w, 1.0):
            l1 = 4.1
        planks += box(fr, "f_holz_grau", -w / 2, w / 2, l0, l1, yb - PLANK_T, yb)
        a += w + rr.uniform(0.02, 0.05)
        n_pl += 1
    mesh_objects("Deck_Bohlen", planks)
    # --- Rundholzgeländer entlang der Leitplanken der Streckendatei: Pfosten alle 2 m, zwei Holme
    rail = bmesh.new()
    ruv = rail.loops.layers.uv.new("UVMap")
    n_posts = 0
    for gr in data.get("guardrails", []):
        side = 1.0 if gr.get("side") == "left" else -1.0
        s0, s1 = float(gr["from"]), float(gr["to"])
        ga, gb = s0 * TOTAL, (s1 if s1 > s0 else s1 + 1.0) * TOTAL
        n_seg = max(1, int(round((gb - ga) / 2.0)))
        tops = []
        for k in range(n_seg + 1):
            a = ga + (gb - ga) * k / n_seg
            p, _, _ = f_tpos(a, side * F_RAIL_LAT)
            yb = base_of(a)
            on_deck = a_A + AB_FRONT - 1.3 < a < a_B - AB_FRONT + 1.3
            foot = yb - 0.35 if on_deck else f_gy_min(p[0], p[1], 0.15) - 0.15
            f_tube(rail, [fV(p[0], p[1], foot), fV(p[0], p[1], yb + 1.17)], [0.09, 0.08], 6, 2.0, ruv, swap=True)
            tops.append((p, yb))
            n_posts += 1
        for hy in (0.62, 1.08):
            f_tube(rail, [fV(p[0], p[1], yb + hy) for p, yb in tops], [0.06] * len(tops), 6, 2.0, ruv, swap=True)
    bmesh.ops.recalc_face_normals(rail, faces=rail.faces)
    f_bm_object("Deck_Gelaender", rail, [M["f_stamm"]])
    # --- Laternen an beiden Brückenköpfen (Holzmast mit Schirmlampe wie am Zuschauerplatz, über Kreuz), echte Lichtquellen: Die Kreuzung hat
    # sonst keine Laterne (die Laternen der Streckendatei stehen nur, wo das Gelände auf Fahrbahnhöhe liegt)
    lamps_at = []
    for face, sgn, pref in ((a_B, 1.0, 1.0), (a_A, -1.0, -1.0)):
        for side in (pref, -pref):
            a = face + sgn * (AB_BACK + 0.9)
            p, t, lf = f_tpos(a, side * (F_RAIL_LAT + 1.1))
            x, z = float(p[0]), float(p[1])
            if f_solid_blocked(x, z, 0.5) or f_dc(x, z) < HW + 2.0:
                continue
            f_lantern_post(x, z, math.atan2(-lf[1] * side, -lf[0] * side), "Bruecke%d" % len(lamps_at))
            lamps_at.append((round(x, 1), round(z, 1)))
            break
    lamp_done = lamps_at
    add_supports(min(F_BR["s_A"] - 0.006, 0.357), max(F_BR["s_B"] + 0.006, 0.449))
    print("DIORAMA Brücke: Köpfe s %.4f / %.4f (lichte Weite %.1f m zwischen den Widerlagern), Bohlen %d, Geländerpfosten %d, Pfosten des Spiels im Bereich %d, Laternen %s"
          % (F_BR["s_A"], F_BR["s_B"], a_B - a_A - 2 * AB_FRONT, n_pl, n_posts, len(posts), lamp_done))


def f_lantern_post(x, z, heading, tag):
    """Holzmast (4,3 m) mit Ausleger und Schirmlampe, Schaltkasten am Fuß; echte Lichtquelle (add_light), Hindernis "mast"."""
    y0 = f_gy_min(x, z, 0.2)
    pole = bmesh.new()
    puv = pole.loops.layers.uv.new("UVMap")
    f_tube(pole, [fV(x, z, y0 - 0.1), fV(x, z, y0 + 4.3)], [0.13, 0.09], 7, 2.0, puv, swap=True)
    bmesh.ops.recalc_face_normals(pole, faces=pole.faces)
    f_bm_object("Leuchtpfosten_%s" % tag, pole, [M["f_stamm"]])
    det = FBuild()
    gg = Frame(Vector((x, z)), Vector((math.cos(heading), math.sin(heading))), Vector((-math.sin(heading), math.cos(heading))))
    f_fbox(det, gg, -0.06, 0.75, -0.04, 0.04, y0 + 4.10, y0 + 4.16, (0.16, 0.16, 0.17))
    f_fbox(det, gg, 0.50, 0.98, -0.24, 0.24, y0 + 3.78, y0 + 4.06, (0.12, 0.13, 0.14), top=(0.10, 0.10, 0.11))
    f_fbox(det, gg, -0.12, 0.12, -0.12, 0.12, y0 + 0.5, y0 + 1.35, (0.20, 0.30, 0.20))
    f_bm_object("Leuchtpfosten_%s_Detail" % tag, det.bm, [M["farbe"]])
    fl = FBuild()
    P4 = lambda a_, b_: fV(*gg.pt(a_, b_), y0 + 3.77)
    fl.poly([P4(0.54, -0.2), P4(0.94, -0.2), P4(0.94, 0.2), P4(0.54, 0.2)], (0.9, 0.85, 0.7), out_from=fV(*gg.pt(0.74, 0.0), y0 + 4.2))
    f_bm_object("Leuchtpfosten_%s_Lampe" % tag, fl.bm, [M["k:lampe"]])
    f_solid(x, z, 0.2, 4.3, "mast")
    lx, lz = gg.pt(0.75, 0.0)
    add_light(lx, lz, y0 + 3.7, (1.0, 0.84, 0.58), 1.0, 12.5, omni=False, glow=0.9)


# ---------------------------------------------------------------- Hohlweg unter der Brücke: Wurzeln, Steine am Fuß, Farn an der Krone
def f_hollow_way():
    hz = f_hollow_range()
    if hz is None:
        return
    rr = random.Random(404)
    roots = FBuild()
    n_root = n_stone = n_fern = 0
    i0, i1 = int(hz[0] * N), int(hz[1] * N)
    es = np.arange(0.0, 6.01, 0.25)
    for i in range(i0, i1 + 1):
        for side in (1.0, -1.0):
            a = float(dist[i % N])
            b = float(_F_LV["base"][i % N])
            prof = np.array([f_tpos(a, side * (HW + e))[0] for e in es])
            lv = f_level(prof) - b
            if lv[-1] < 0.9 or f_dc(*prof[8]) < HW + 0.6:                    # keine Wand (oder schon die andere Fahrbahn)
                continue
            foot = int(np.argmax(lv > 0.06))
            e_foot = float(es[foot])
            e_crest = float(es[int(np.argmax(lv > 0.9 * lv[-1]))])
            if rr.random() < 0.42:                                           # Wurzel: aus der Wand, hängt nach unten zum Fuß
                h0 = rr.uniform(0.35, 0.95) * min(float(lv[-1]), 1.4)
                e0 = float(np.interp(h0, lv[foot:], es[foot:])) + 0.12
                pts = []
                bend = rr.uniform(-0.4, 0.4)
                for de, dh, da in ((0.0, 0.0, 0.0), (-0.2, -0.22, bend * 0.4), (-0.32, -0.55 * h0, bend * 0.8), (-0.36, -0.85 * h0, bend)):
                    q, _, _ = f_tpos(a + da, side * (HW + e0 + de))
                    pts.append(fV(q[0], q[1], b + GROUND_Y + h0 + dh))
                r0 = rr.uniform(0.035, 0.07)
                n0 = len(roots.bm.faces)
                f_tube(roots.bm, pts, [r0, r0 * 0.8, r0 * 0.5, r0 * 0.25], 4, 2.0, roots.uv)
                tone = rr.uniform(0.85, 1.15)
                for f in list(roots.bm.faces)[n0:]:
                    for loop in f.loops:
                        loop[roots.col] = ((0.24 * tone) ** 2.2, (0.16 * tone) ** 2.2, (0.10 * tone) ** 2.2, 1.0)
                n_root += 1
            if rr.random() < 0.3:                                            # Stein am Wandfuß (hinter der Wandkante der Fahrphysik)
                q, _, _ = f_tpos(a + rr.uniform(-0.3, 0.3), side * (HW + e_foot + rr.uniform(0.05, 0.3)))
                f_put(f_stone(int(abs(q[0] * 1.9 + q[1] * 6.1)) % 3), float(q[0]), float(q[1]), rr.uniform(0, 6.28), scale=rr.uniform(0.3, 0.6),
                      anchor="origin", y=f_gy_min(q[0], q[1], 0.2) - 0.03)
                n_stone += 1
            if rr.random() < 0.5:                                            # Farn an der Krone
                q, _, _ = f_tpos(a + rr.uniform(-0.3, 0.3), side * (HW + e_crest + rr.uniform(-0.2, 0.9)))
                if not f_solid_blocked(q[0], q[1], 0.3) and f_dc(q[0], q[1]) > HW + 1.0:
                    f_put(f_fern(int(abs(q[0] * 5.1 + q[1] * 2.3)) % 3), float(q[0]), float(q[1]), rr.uniform(0, 6.28), scale=rr.uniform(0.8, 1.25),
                          anchor="origin", foot=0.4)
                    n_fern += 1
    bmesh.ops.recalc_face_normals(roots.bm, faces=roots.bm.faces)
    f_bm_object("Hohlweg_Wurzeln", roots.bm, [M["farbe"]])
    print("DIORAMA Hohlweg s %.3f-%.3f: Wurzeln %d, Steine %d, Farne %d" % (hz[0], hz[1], n_root, n_stone, n_fern))


# ---------------------------------------------------------------- Laufzeit-Bauteile (Laternen, Tribüne, Turm, Stamm) auf den Dioramaboden
F_RT_DY = {}


def f_runtime_props_on_ground():
    """Das Spiel stellt Laufzeit-Bauteile auf das Gelände der Streckendatei (terrain_height am Standort). Der Dioramaboden weicht nahe der
    Fahrbahn davon ab (f_level: Schulter, Erdwand, Böschung); prop_y gleicht den Unterschied aus: tiefste Bodenhöhe unter der Grundfläche
    minus Gelände am Standort (kein set_prop_heights: das Gelände steckt schon im Spiel)."""
    n = 0
    for p in data["props"]:
        kind = p.get("type")
        if kind not in ("lantern", "tower", "stand", "log"):
            continue
        x, z = float(p["x"]), float(p["z"])
        if kind in ("stand", "log"):
            ang = math.radians(float(p.get("rot", 0.0)))
            hw_, hd = (float(p.get("w", 10.0)) / 2, float(p.get("d", 3.5)) / 2) if kind == "stand" else (1.6, 0.35)
            g = Frame(Vector((x, z)), Vector((math.cos(ang), math.sin(ang))), Vector((-math.sin(ang), math.cos(ang))))
            pts = np.array([tuple(g.pt(a, b)) for a in np.linspace(-hw_, hw_, 5) for b in np.linspace(-hd, hd, 3)])
        else:
            r = 1.3 if kind == "tower" else 0.25
            pts = np.array([(x, z)]) + F_RING * r
        dy = float(f_level(pts).min()) - float(f_ty(np.array([(x, z)]))[0])
        F_RT_DY[(round(x, 2), round(z, 2))] = dy
        if abs(dy) >= 0.005:
            set_prop_y((x, z), dy)
            n += 1
    print("DIORAMA Laufzeit-Bauteile auf Dioramaboden gesetzt:", n, "Abweichungen (m)", sorted(round(v, 2) for v in F_RT_DY.values() if abs(v) >= 0.005)[:12])


def f_runtime_dy(x, z):
    return F_RT_DY.get((round(float(x), 2), round(float(z), 2)), 0.0)


# ---------------------------------------------------------------- Szenerie
def theme_scenery():
    f_trees()
    f_rocks()
    f_cabin_yard()
    with FLift("lift"):
        f_campfire()
    with FLift("lift"):
        f_hochsitz()
    with FLift("drape"):
        f_holzpolter()
    f_signpost()
    with FLift("drape"):
        f_strohballen()
    with FLift("drape"):
        f_stand_lamps()
    with FLift("drape"):
        f_apex_bales()
    f_bridge()
    f_hollow_way()
    f_puddles()
    f_verge_detail()
    f_scatter_solids()
    f_pond_decor()
    f_scatter_understory()
    f_runtime_props_on_ground()
    ao_proxies(types=["lantern", "tower", "stand", "log"], base_y=lambda x, z: GROUND_Y + f_runtime_dy(x, z) + float(f_ty(np.array([(x, z)]))[0]))
    f_report()


def f_report():
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
    return ["Teich", "Saum"]


def theme_layout(layout):
    layout["water_y"] = None
    # Das Laternenlicht-Zusatzbild des Spiels (lit_overlay) nimmt für Wasser die Vertexfarbe (Tiefe in Rot) als Farbe: unter Lampen würde der
    # Teich rot. Ein dunkler Tönungswert dämpft diesen Zusatz auf einen schwachen Schimmer.
    layout["tints"] = {"D_Wasser": [0.02, 0.03, 0.03]}
