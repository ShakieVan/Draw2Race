"""Themenmodul "coast": Azure Coast Speedway, ein Küstenstadion.

Wird von tools/diorama.py in dessen Globals ausgeführt (siehe docs/dioramen/README.md). Straße: "painted" (bemalte Fahrbahn und roter/weißer
Randstein im Kern). Gestaltung (Stand 02.10.2026, siehe docs/dioramen/azure.md):
- Oval mit Auslaufzone (Gras, in den Kurven Schlamm), weißer Sicherheitsmauer mit Fangzaun, Tribünen ringsum (Haupttribüne mit Segeldach an
  der Startgeraden, niedrige offene Tribüne zur Seeseite), Menge, Fahnen, Banner;
- Innenfeld mit Boxengebäude, Team-Transportern, Rennwagen, Reifenstapeln, Videowand und Palmenbeeten;
- Promenade (Holz), Strand mit Schirmen und Liegen, Meer mit Brandung, Felsen, Parkplätze mit Autos, Flutlichtmasten.
Geometrie liegt in tools/make_coast_parts.py und tools/make_coast_objects.py (ohne Blender testbar), Texturen in game/assets/dio/coast/
(tools/make_coast_stadium.py).
Alle Namen dieses Moduls beginnen mit az_, weil das Modul in die Globals des Kerns ausgeführt wird.
"""
import math
import os
import random

import numpy as np

import make_coast_objects as azo
import make_coast_parts as azp

AZ_GY = 0.10                          # Bodenhöhe (unter der Fahrbahn bei 0,17, damit Reifenspuren der Erde sichtbar bleiben)
AZ_WATER_Y = -0.35                    # Wasserspiegel
AZ_WALL_D = 3.5 + 3.3                 # Mauer (Mitte) im Abstand zur Mittellinie
AZ_STAND_D = 7.5                      # erste Sitzreihe
AZ_PAVE_IN, AZ_PAVE_OUT = 6.6, 19.0   # gepflasterter Ring (Umlauf) von der Mauer bis hierher
THEME_CFG = {
    "road": "painted",
    "ground_y": AZ_GY,
    "margin": 50.0,
    "portal": True,                    # Startportal über der Startlinie
    "crowd": False,                    # Zuschauer sitzen auf den Tribünen (eigene Reihen), nicht am Gitter
    "baked": [],                       # Bausteine der Streckendatei: nur Flutlichter (laufen zur Laufzeit), alles Übrige steckt im Diorama
    "vertex_colors": "ACTIVE",
    "ground_set": {"grass": "res://assets/ground/gras", "sand": "res://assets/ground/sand", "dirt": "res://assets/ground/erde"},
    "ground_scales": {"grass": 3.0, "sand": 4.0, "dirt": 3.0},
    "ground_tints": {"grass": [0.88, 0.97, 0.78], "sand": [1.0, 0.97, 0.92], "dirt": [0.88, 0.8, 0.72]},
    "water": {"lagoon": [0.30, 0.80, 0.78], "open": [0.04, 0.30, 0.54], "foam": [0.95, 0.98, 0.98]},
}
AZ_SCREEN = dict(x=18.5, z=2.5, fx=0.259, fz=0.966, w=7.2, h=4.05, y0=1.9, lean=24.0)       # Videowand am Ostende des Innenfelds (Bildfläche nach Nordnordost)
Y_W = AZ_GY + 0.002                   # Fußhöhe des Startportals (Kern: 0,302 = Gehweghöhe der Stadt)
AZ = {}


# ---------------------------------------------------------------- Hilfen
def az_vnoise(x, z, scale):
    """Wertrauschen wie value_noise des Kerns, aber für numpy-Felder."""
    x = np.asarray(x, float)
    z = np.asarray(z, float) + np.zeros_like(x)
    u, v = x / scale, z / scale
    i0, j0 = np.floor(u).astype(int), np.floor(v).astype(int)
    fu, fv = u - i0, v - j0
    fu, fv = fu * fu * (3 - 2 * fu), fv * fv * (3 - 2 * fv)
    g = _noise_grid
    a = g[j0 % 64, i0 % 64] * (1 - fu) + g[j0 % 64, (i0 + 1) % 64] * fu
    b = g[(j0 + 1) % 64, i0 % 64] * (1 - fu) + g[(j0 + 1) % 64, (i0 + 1) % 64] * fu
    return a * (1 - fv) + b * fv


def az_smooth(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def az_mesh(name, parts, smooth=False):
    """Wie mesh_object des Kerns, kennt aber auch "down" (waagerechte Flächen mit Blick nach unten). smooth: gemeinsame Ecken verschweißen und
    weich schattieren (Gelände: Hänge und Strand ohne Kanten)."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    uv0 = bm.loops.layers.uv.new("UVMap")
    col = bm.loops.layers.float_color.new("Color") if any(p[4] is not None for p in parts) else None
    keys, faces = [], []
    for key, corners, uvs, facing, colors in parts:
        if key not in keys:
            keys.append(key)
        try:
            f = bm.faces.new([bm.verts.new((x, -z, y)) for x, z, y in corners])
        except ValueError:
            continue
        f.material_index = keys.index(key)
        for k, (loop, uv) in enumerate(zip(f.loops, uvs)):
            loop[uv0].uv = uv
            if col is not None:
                c = colors[k] if colors is not None else (1.0, 1.0, 1.0)
                loop[col] = (c[0], c[1], c[2], 1.0)
        faces.append((f, facing))
    bm.normal_update()
    for f, facing in faces:
        if facing == "down":
            if f.normal.z > 0.01:
                f.normal_flip()
        elif facing is not None:
            if f.normal.dot(Vector((facing[0], -facing[1], 0.0))) < 0:
                f.normal_flip()
        elif f.normal.z < -0.01:
            f.normal_flip()
    bm.normal_update()
    if smooth:
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
        for f in bm.faces:
            f.smooth = True
        bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    for key in keys:
        me.materials.append(M[key])
    obj = bpy.data.objects.new(name, me)
    scene.collection.objects.link(obj)
    return obj


def az_emit(name, parts, ground=False, decal=False):
    """Teile nach Material gruppiert als Objekte anlegen (Name <name>_<schlüssel>). ground: empfängt die gebackene Umgebungsverdeckung;
    decal: beim Backen unsichtbar (Menge und andere dünne Auflagen)."""
    groups = {}
    for p in parts:
        groups.setdefault(p[0], []).append(p)
    objs = [az_mesh(f"{name}_{k.replace(chr(58), chr(95)).replace(chr(47), chr(95)).replace(chr(46), '')}", ps) for k, ps in groups.items()]
    if ground:
        objs_ground.extend(objs)
    if decal:
        event_decals.extend(o for o in objs if o.name.endswith("_e_menge"))
    return objs


def az_rect(x0_, x1_, z0_, z1_, y, key, color=None, tile=None, up=True):
    pts = [(x0_, z0_), (x1_, z0_), (x1_, z1_), (x0_, z1_)]
    uvs = [(a / tile, -b / tile) for a, b in pts] if tile else None
    return [(key, [(a, b, y) for a, b in pts], uvs if uvs else [(0, 0), (1, 0), (1, 1), (0, 1)], None if up else "down",
             [color] * 4 if color is not None else None)]


def az_dist_edge(poly_pts):
    """Kleinster Abstand der Punkte zur Mittellinie (Prüfung der Freihaltung)."""
    return float(dist_to_center(np.array(poly_pts)).min())


# ---------------------------------------------------------------- Materialien
def theme_materials():
    own = os.path.normpath(os.path.join(PROPS, "..", "dio", "coast"))

    def own_tex(n):
        return os.path.join(own, n)
    M["sand"] = material("D_Sand", tex("SandProc"), 0.95, tex("SandProc", "NormalGL"))
    M["erde"] = material("D_Erde", tex("Ground037"), 0.95, tex("Ground037", "NormalGL"))
    M["gelaende"] = material("D_Gelaende", color=(0.45, 0.55, 0.35), rough=0.9)      # Platzhalter: Misch-Shader im Spiel
    M["mauer"] = material("D_Mauer", own_tex("mauer.png"), 0.7)
    M["sitz_az"] = material("D_Sitz_Azur", own_tex("sitz_az.png"), 0.6)
    M["sitz_wh"] = material("D_Sitz_Weiss", own_tex("sitz_wh.png"), 0.6)
    M["sitz_co"] = material("D_Sitz_Koralle", own_tex("sitz_co.png"), 0.6)
    M["sitz_na"] = material("D_Sitz_Marine", own_tex("sitz_na.png"), 0.6)
    M["sitz_te"] = material("D_Sitz_Tuerkis", own_tex("sitz_te.png"), 0.6)
    M["fascia"] = material("D_Blende", own_tex("fascia.png"), 0.5)
    M["lkw_azure"] = material("D_Lack_Azur", own_tex("lkw_azure.png"), 0.45)
    M["lkw_coral"] = material("D_Lack_Koralle", own_tex("lkw_coral.png"), 0.45)
    M["lkw_navy"] = material("D_Lack_Marine", own_tex("lkw_navy.png"), 0.45)
    M["planken"] = material("D_Planken", own_tex("planken.png"), 0.9)
    M["platten"] = material("D_Platten", own_tex("platten.png"), 0.85)
    M["schilder"] = material("D_Schilder", own_tex("schilder.png"), 0.6)
    M["blumen"] = material("D_Blumen", own_tex("blumen.png"), 0.9)
    M["glas"] = material("D_Glas", color=(0.03, 0.09, 0.12), rough=0.05)
    # Videowand: K_-Oberfläche des Spiels (Fensterlicht). Der Schlüssel "../dio/coast/screen" lädt screen.png (Tag, gedimmt) und screen_e.png (Nacht,
    # Leuchtbild) aus dem Themenordner; das Spiel schaltet die Emission mit der Tageszeit (World.set_windows), am Tag leuchtet nichts.
    M[azo.SCREEN_KEY] = kit_material("../dio/coast/screen")


# ---------------------------------------------------------------- Aufbau: Oval, Zonen
def az_setup():
    pts = [(p.x, p.y) for p in center]
    lefts = [(v.x, v.y) for v in left]
    ov = azp.Oval(pts, lefts, float(outer), [c < 0.01 for c in curv])
    AZ["ov"] = ov
    reg = []
    for i in range(N):
        x, z = center[i].x, center[i].y
        reg.append("E" if x > 14.01 else ("W" if x < -14.01 else ("M" if z > 0 else "F")))
    trans = [i for i in range(N) if reg[i] != reg[i - 1]]
    zones = {}
    for k, i in enumerate(trans):
        nxt = trans[(k + 1) % len(trans)]
        if nxt <= i:
            nxt += N
        zones[reg[i]] = (i, nxt)
    AZ["zones"] = zones
    AZ["rows"] = {"M": 12, "E": 9, "F": 6, "W": 9}
    AZ["screen"] = (AZ_SCREEN["x"] + AZ_SCREEN["fx"] * 2.6, AZ_SCREEN["z"] + AZ_SCREEN["fz"] * 2.6)      # Standort des Videowand-Scheins (vor der Wand)
    print("DIORAMA Küste Zonen:", zones)


# ---------------------------------------------------------------- Gelände: Höhe, Anteile
AZ_SHORE0 = -41.0
AZ_MUD_Y = 0.148                      # Höhe des Schlammbands über dem Streifen des Spiels (Belagzone "mud": y = 0,13, 0,85 m neben dem Randstein); der Streifen bleibt nachts sonst schwarz
# Sanfte Hügel hinter dem Stadion (Mitte x, Mitte z, Halbachse x, Halbachse z, Höhe): Nordhang mit der Stadt, niedrigere Hänge im Osten und Westen
AZ_HILLS = ((0.0, 120.0, 108.0, 48.0, 12.0), (-118.0, 42.0, 36.0, 64.0, 8.0), (118.0, 42.0, 36.0, 64.0, 8.0),
            (-116.0, -20.0, 34.0, 38.0, 5.5), (116.0, -20.0, 34.0, 38.0, 5.5))
# Platzhöhen der Hausplätze (Terrassen am Hang), gefüllt von az_town_plan: (Mitte x, Mitte z, halbe Breite, halbe Tiefe, Höhe über AZ_GY)
AZ_PADS = []
# Nord- und Seitenstraßen, Parkplätze und Zugangsallee: auf diesen Flächen entfällt der Boden (kein Flackern von Asphalt über Gras)
AZ_LOTS = {"E": (48.5, 61.1, -14.0, 14.0), "W": (-61.1, -48.5, -14.0, 14.0), "NW": (-38.0, -8.0, 41.5, 55.5), "NE": (8.0, 38.0, 41.5, 55.5)}
AZ_BLVD = (-7.5, 7.5, 32.0, 56.5)                 # Zugangsallee (Sandplatten) vom Ring zur Nordstraße
AZ_ROAD_N = (-120.0, 120.0, 56.5, 62.0)           # Nordstraße (Asphalt)
AZ_ROAD_E = (67.0, 72.5, -30.0, 62.0)             # Oststraße
AZ_ROAD_W = (-72.5, -67.0, -30.0, 62.0)           # Weststraße


def az_shore(x):
    """Uferlinie (z): leicht gewellt, vor dem Volleyballfeld eine flache Landzunge (der Strand ist dort tiefer, das Feld liegt trocken)."""
    cape = 4.8 * np.exp(-((np.asarray(x, float) - AZ_VB["x"]) / 15.0) ** 2)
    return AZ_SHORE0 - cape + (az_vnoise(x + 300.0, 7.0, 14.0) - 0.5) * 3.0 + (az_vnoise(x, 11.0, 4.0) - 0.5) * 0.8


def az_hill_h(x, z):
    """Höhe der Hügel über dem Boden (m), 0 außerhalb; mit etwas Rauschen, damit die Hänge nicht wie Kegel aussehen."""
    x = np.asarray(x, float)
    z = np.asarray(z, float) + np.zeros_like(x)
    h = np.zeros_like(x)
    for (cx, cz, rx, rz, hh) in AZ_HILLS:
        r = np.sqrt(((x - cx) / rx) ** 2 + ((z - cz) / rz) ** 2)
        k = 1.0 - az_smooth(r)
        h = np.maximum(h, hh * k * (0.82 + 0.36 * az_vnoise(x + 17.0, z + 5.0, 26.0)))
    return h


def az_alley_lines():
    """Gassen am Hang: (xa, za, xb, zb) wie in az_hang."""
    lines = [(-120.0, zr - 11.5, 120.0, zr - 11.5) for zr in AZ_TOWN_ROWS]
    for side in (1, -1):
        for xr in (98.0, 114.0, 130.0):
            lines.append((side * (xr - 11.5), -8.0, side * (xr - 11.5), 98.0))
    return lines


def az_height(x, z):
    zs = az_shore(x)
    t = az_smooth((zs + 9.0 - z) / 9.0)
    h = AZ_GY + (AZ_WATER_Y - 0.02 - AZ_GY) * t
    h = np.where(z < zs, AZ_WATER_Y - 0.02 - (zs - z) * 0.12, h)
    h = h + az_hill_h(x, z)
    for (xa, za, xb, zb) in az_alley_lines():                 # Gassen: quer zur Gasse eben (Höhe der Gassenmitte), weicher Übergang zum Hang
        ex, ez = xb - xa, zb - za
        el = math.hypot(ex, ez)
        t = np.clip(((x - xa) * ex + (z - za) * ez) / (el * el), 0.0, 1.0)
        qx, qz = xa + t * ex, za + t * ez
        dq = np.hypot(x - qx, z - qz)
        w = 1.0 - az_smooth((dq - 2.6) / 4.0)
        h = h * (1.0 - w) + (AZ_GY + az_hill_h(qx, qz)) * w
    for (px, pz, hx, hz, ph) in AZ_PADS:                      # Hausplätze: ebene Terrasse mit weichem Übergang
        dx = np.maximum(np.abs(x - px) - hx, 0.0)
        dz = np.maximum(np.abs(z - pz) - hz, 0.0)
        w = 1.0 - az_smooth(np.hypot(dx, dz) / 4.0)
        h = h * (1.0 - w) + (AZ_GY + ph) * w
    return np.maximum(h, -3.0)


AZ_MUD = [z_ for z_ in data.get("surfaces", []) if z_.get("kind") == "mud"]


def az_nearest_index(Q):
    """Index der nächsten Mittellinienpunkte (jeder zweite Punkt, Schrittweite 1 m) für Punkte Q (n x 2)."""
    near = np.zeros(len(Q), int)
    for k in range(0, len(Q), 3000):
        q = Q[k:k + 3000]
        near[k:k + 3000] = np.argmin(((q[:, None, :] - C[None, ::2, :]) ** 2).sum(2), axis=1) * 2
    return near


def az_attributes(P):
    """Höhe, Rasenhelligkeit, Sand- und Erdanteil, Abstand und Innen-Kennzeichen für Punkte P (n x 2)."""
    n = len(P)
    dd = np.zeros(n)
    ins = np.zeros(n, bool)
    for k in range(0, n, 3000):
        dd[k:k + 3000] = dist_to_center(P[k:k + 3000])
        ins[k:k + 3000] = inside(P[k:k + 3000])
    x, z = P[:, 0], P[:, 1]
    h = az_height(x, z)
    # Rasen: Mähbänder parallel zum Oval, außerhalb schräge Streifen und Flecken
    band = np.where(np.floor(dd / 3.0).astype(int) % 2 == 0, 0.05, -0.05)
    diag = np.where(np.floor((x + 0.35 * z) / 2.6).astype(int) % 2 == 0, 0.045, -0.045)
    stripe = np.where(dd < 24.0, band, diag)
    patch = (az_vnoise(x, z, 7.0) - 0.5) * 0.16 + (az_vnoise(x + 91, z + 37, 2.3) - 0.5) * 0.06
    wide = az_smooth((dd - 22.0) / 6.0)                                    # weit vom Oval: große Flecken (Wiese statt Rasen), sonst wirkt das Land flach und leer
    bright = 1.0 + stripe + patch + wide * ((az_vnoise(x + 200.0, z - 80.0, 38.0) - 0.5) * 0.30 + (az_vnoise(x - 40.0, z + 10.0, 13.0) - 0.5) * 0.14)
    sand = az_smooth((-32.6 + (az_vnoise(x, 3.0, 11.0) - 0.5) * 1.6 - z) / 1.4 + 0.05)
    mud = np.zeros(n)
    sel = np.where((dd < 7.4) & (~ins))[0]
    if len(sel):
        Q = P[sel]
        near = az_nearest_index(Q)
        s_ = near / N
        lat = ((Q - C[near]) * np.array([[left[i].x, left[i].y] for i in near])).sum(1) * float(outer)
        m = np.zeros(len(sel))
        for zone in AZ_MUD:
            fade = np.minimum((s_ - zone["from"]) / 0.012, (zone["to"] - s_) / 0.012)
            fade = np.clip(fade, 0.0, 1.0)
            ok = (lat > 0) if zone["side"] in ("outer",) else np.ones(len(sel), bool)
            edge = az_smooth((dd[sel] - (3.9 + (az_vnoise(Q[:, 0], Q[:, 1], 1.7) - 0.5) * 0.5)) / 0.55)
            m = np.maximum(m, fade * ok * edge)
        mud[sel] = m
    sand = sand * (1.0 - mud)
    gravel = az_smooth((dd - AZ_PAVE_OUT + 0.4) / 0.9) * (1.0 - az_smooth((dd - (AZ_PAVE_OUT + 3.2 + (az_vnoise(x + 70.0, z, 3.1) - 0.5) * 2.2)) / 1.2)) * (~ins)
    sand = np.maximum(sand, 0.92 * gravel * (z > AZ_SHORE0 + 6.0) * (1.0 - mud))
    # Hänge: trockene Erdflecken und etwas dunkleres, unruhigeres Gras (Macchia), je höher desto trockener
    hh = az_hill_h(x, z)
    dry = az_smooth((az_vnoise(x + 13.0, z + 71.0, 19.0) - 0.5) / 0.16) * az_smooth((hh - 1.5) / 5.0) * 0.75
    mud = np.maximum(mud, dry)
    bright = bright * (1.0 - 0.12 * az_smooth(hh / 8.0)) + (az_vnoise(x + 5.0, z + 9.0, 9.0) - 0.5) * 0.14 * az_smooth(hh / 3.0)
    return h, bright, sand, mud, dd, ins


# ---------------------------------------------------------------- Gelände: Zellen
AZ_STRIP = 6.0                        # Zellgröße der Streifen außerhalb des Rahmens (Hänge brauchen genug Stützstellen)


def az_cells():
    """Zellen (xa, xb, za, zb): Raster aus 4-m-Blöcken über den Rahmen; Blöcke nahe dem Oval, dem Ring und im Strandstreifen werden in 2-m-Zellen,
    nahe dem Oval in 1-m-Zellen und nur in den Schlammzonen in 0,5-m-Zellen geteilt. Außerhalb des Rahmens Streifen (Strand, Land, Hänge)."""
    cells = []
    nx, nz = int(math.ceil((x1 - x0) / 4.0)), int(math.ceil((z1 - z0) / 4.0))
    AZ["xe"], AZ["ze"] = x0 + 4.0 * nx, z0 + 4.0 * nz                  # Ende des 4-m-Rasters (>= Fläche): die Streifen außen schließen hier lückenlos an
    gx2 = x0 + 1.0 + 2.0 * np.arange(nx * 2)
    gz2 = z0 + 1.0 + 2.0 * np.arange(nz * 2)
    PX2, PZ2 = np.meshgrid(gx2, gz2)
    P2 = np.stack([PX2.ravel(), PZ2.ravel()], 1)
    d2 = np.zeros(len(P2))
    i2 = np.zeros(len(P2), bool)
    for k in range(0, len(P2), 3000):
        d2[k:k + 3000] = dist_to_center(P2[k:k + 3000])
        i2[k:k + 3000] = inside(P2[k:k + 3000])
    fine2 = (np.where(i2, d2 < 9.5, d2 < 9.8) | ((~i2) & (d2 > 14.0) & (d2 < 24.0)) | ((P2[:, 1] < -27.0) & (P2[:, 1] > -45.0))).reshape(PX2.shape)
    block_fine = fine2.reshape(nz, 2, nx, 2).any(axis=(1, 3))
    d2 = d2.reshape(PX2.shape)
    i2 = i2.reshape(PX2.shape)
    subs = []                                                          # 1-m-Zellen aus feinen 2-m-Zellen: Mitten
    for bj in range(nz):
        for bi in range(nx):
            if not block_fine[bj, bi]:
                cx, cz = x0 + 2.0 + 4.0 * bi, z0 + 2.0 + 4.0 * bj
                cells.append((cx - 2.0, cx + 2.0, cz - 2.0, cz + 2.0))
                continue
            for sj in (0, 1):
                for si in (0, 1):
                    cx, cz = gx2[2 * bi + si], gz2[2 * bj + sj]
                    if not fine2[2 * bj + sj, 2 * bi + si]:
                        cells.append((cx - 1.0, cx + 1.0, cz - 1.0, cz + 1.0))
                    else:
                        for dx in (-0.5, 0.5):
                            for dz in (-0.5, 0.5):
                                subs.append((cx + dx, cz + dz))
    Q = np.array(subs)
    dq = np.zeros(len(Q))
    iq = np.zeros(len(Q), bool)
    for k in range(0, len(Q), 3000):
        dq[k:k + 3000] = dist_to_center(Q[k:k + 3000])
        iq[k:k + 3000] = inside(Q[k:k + 3000])
    near = (iq & (dq < 7.0)) | ((~iq) & (dq < 7.6))
    in_mud = np.zeros(len(Q), bool)
    if near.any():
        s_ = az_nearest_index(Q[near]) / N
        flag = np.zeros(len(s_), bool)
        for zone in AZ_MUD:
            flag |= (s_ > zone["from"] - 0.03) & (s_ < zone["to"] + 0.03)
        in_mud[np.where(near)[0]] = flag
    for (qx, qz), m in zip(Q, in_mud):
        if m:                                                          # Schlammzone: Rand und Mischung brauchen 0,5-m-Zellen
            for ex in (-0.25, 0.25):
                for ez in (-0.25, 0.25):
                    cells.append((qx + ex - 0.25, qx + ex + 0.25, qz + ez - 0.25, qz + ez + 0.25))
        else:
            cells.append((qx - 0.5, qx + 0.5, qz - 0.5, qz + 0.5))
    # Streifen außerhalb des Rahmens (Strand läuft weiter, Land und Hänge auf den anderen Seiten)
    ext_x, ext_zl, ext_zh = 100.0, 60.0, 100.0
    xe, ze = AZ["xe"], AZ["ze"]
    strips = [(xe, xe + ext_x, z0 - ext_zl, ze + ext_zh), (x0 - ext_x, x0, z0 - ext_zl, ze + ext_zh),
              (x0, xe, ze, ze + ext_zh), (x0, xe, z0 - ext_zl, z0)]
    for xa, xb, za, zb in strips:
        cuts = [c for c in (-48.0, -24.0) if za < c < zb]            # Küstenband (z -48 bis -24): feine Zellen, damit Sand und Gras wie im Raster innen scharf wechseln
        edges = [za] + cuts + [zb]
        for ya, yb in zip(edges, edges[1:]):
            size = 1.5 if (ya >= -48.0 - 1e-6 and yb <= -24.0 + 1e-6) else AZ_STRIP
            ncx, ncz = max(1, int(round((xb - xa) / AZ_STRIP))), max(1, int(round((yb - ya) / size)))
            for i in range(ncx):
                for j in range(ncz):
                    cells.append((xa + (xb - xa) * i / ncx, xa + (xb - xa) * (i + 1) / ncx, ya + (yb - ya) * j / ncz, ya + (yb - ya) * (j + 1) / ncz))
    return np.array(cells)


AZ_COVER_RECTS = [(-11.95, 11.95, -1.25, 3.8), (-14.0, 14.0, 3.0, 7.55), (-17.4, 17.4, -6.8, -1.3)]    # Boxengebäude, Boxengasse, Fahrerlager


def az_ground():
    cells = az_cells()
    xa, xb, za, zb = cells[:, 0], cells[:, 1], cells[:, 2], cells[:, 3]
    cx = np.stack([xa, xb, xb, xa], 1)
    cz = np.stack([za, za, zb, zb], 1)
    P = np.stack([cx.ravel(), cz.ravel()], 1)
    h, bright, sand, mud, dd, ins = az_attributes(P)
    shape4 = (len(cells), 4)
    h, bright, sand, mud, dd, ins = (a.reshape(shape4) for a in (h, bright, sand, mud, dd, ins))
    PX, PZ = cx, cz
    under_road = (dd < HW + KERB_W - 0.15).all(1)
    ring = ((~ins) & (dd > AZ_PAVE_IN + 0.06) & (dd < AZ_PAVE_OUT - 0.06)).all(1)
    rects = np.zeros(len(cells), bool)
    for (ra, rb, rc, rd) in AZ_COVER_RECTS + list(AZ_LOTS.values()) + [AZ_BLVD, AZ_ROAD_N, AZ_ROAD_E, AZ_ROAD_W]:
        rects |= ((PX > ra + 0.05) & (PX < rb - 0.05) & (PZ > rc + 0.05) & (PZ < rd - 0.05)).all(1)
    sunk = (h < AZ_WATER_Y - 0.03).all(1)
    keep = ~(under_road | ring | rects | sunk)
    parts = []
    for k in np.where(keep)[0]:
        corners = [(PX[k, c], PZ[k, c], float(h[k, c])) for c in (3, 2, 1, 0)]
        cols = [(float(bright[k, c]), float(sand[k, c]), float(mud[k, c])) for c in (3, 2, 1, 0)]
        parts.append(("gelaende", corners, [(a / 3.0, -b / 3.0) for a, b, _ in corners], None, cols))
    # Horizont: weiter Rahmen aus flachem Rasen um die Streifen (kein Rand im Bild); an den Hangenden liegt die Höhe wieder bei null
    far = 400.0
    xe, ze = AZ["xe"], AZ["ze"]
    xa_, xb_, za_, zb_ = x0 - 100.0 - far, xe + 100.0 + far, z0 - 60.0, ze + 100.0 + far
    for ax0, az0, ax1, az1 in ((xa_, ze + 100.0, xb_, zb_), (xa_, -34.0, x0 - 100.0, ze + 100.0), (xe + 100.0, -34.0, xb_, ze + 100.0)):
        corners = [(ax0, az1, AZ_GY), (ax1, az1, AZ_GY), (ax1, az0, AZ_GY), (ax0, az0, AZ_GY)]
        parts.append(("gelaende", corners, [(a / 3.0, -b / 3.0) for a, b, _ in corners], None, [(0.95, 0.0, 0.0)] * 4))
    objs_ground.append(az_mesh("Gelaende", parts, smooth=True))
    print("DIORAMA Gelände:", len(cells), "Zellen,", len(parts), "sichtbar; Schlamm", int((mud.max(1) > 0.5).sum()), "Zellen; Sand", int((sand.max(1) > 0.5).sum()))


# ---------------------------------------------------------------- Wasser (Meer)
def az_water():
    parts = []

    def add_quad(xa_, xb_, za_, zb_, depths):
        quad = [(xa_, za_), (xb_, za_), (xb_, zb_), (xa_, zb_)][::-1]
        dv = depths[::-1]
        cols = [(min(1.0, max(0.0, v / 1.6)), 0.0, 0.0) for v in dv]
        parts.append(("wasser", [(a, b, AZ_WATER_Y) for a, b in quad], [(a / 8.0, -b / 8.0) for a, b in quad], None, cols))
    # Küstenstreifen (Tiefenfarbe und Brandung): 2-m-Raster zwischen z = -52 und der Küste; weiter draußen große Flächen (Tiefe überall gleich)
    step = 2.0
    gx = np.arange(x0 - 100.0, AZ["xe"] + 100.0 + 0.1, step)       # so weit wie die Küste (Bodenstreifen) reicht: sonst endet die Flachwasserzone sichtbar
    gz = np.arange(-58.0, -33.0 + 0.1, step)
    XS, ZS = np.meshgrid(gx, gz)
    depth = AZ_WATER_Y - az_height(XS, ZS)
    for iz in range(XS.shape[0] - 1):
        for ix in range(XS.shape[1] - 1):
            dq = depth[iz:iz + 2, ix:ix + 2]
            if dq.max() < -0.4:
                continue
            add_quad(XS[iz, ix], XS[iz, ix + 1], ZS[iz, ix], ZS[iz + 1, ix], [dq[0, 0], dq[0, 1], dq[1, 1], dq[1, 0]])
    gz_far = np.arange(gz[0], z0 - 20 - 0.1, -8.0)[::-1]
    gx_far = np.arange(gx[0], gx[-1] - 0.1, 16.0)
    gx_far = np.append(gx_far, gx[-1])                                # bis zum Ende des Küstenstreifens: sonst klafft eine Lücke (türkis, die Grundfarbe des Spiels)
    for iz in range(len(gz_far) - 1):
        for ix in range(len(gx_far) - 1):
            add_quad(gx_far[ix], gx_far[ix + 1], gz_far[iz], gz_far[iz + 1], [3.0] * 4)
    far = 450
    xa, xb, za, zb = gx[0], gx[-1], gz_far[0], gz[-1]
    for ax0, az0, ax1, az1 in ((xa - far, za - far, xb + far, za), (xa - far, za, xa, -33.0), (xb, za, xb + far, -33.0)):
        quad = [(ax0, az1, AZ_WATER_Y), (ax1, az1, AZ_WATER_Y), (ax1, az0, AZ_WATER_Y), (ax0, az0, AZ_WATER_Y)]
        parts.append(("wasser", quad, [(q[0] / 8.0, -q[1] / 8.0) for q in quad], None, [(1.0, 0.0, 0.0)] * 4))
    mesh_object("Meer", parts)


def az_mud_strips():
    """Schlammband über dem Belagstreifen des Spiels (World.road_strip, y = 0,13, nachts unbeleuchtet und damit schwarz): ein Band aus Bodenfläche mit
    Erdgewicht 1 (gleiche Mischung und Textur wie der übrige Schlamm) liegt knapp darüber und fällt nach außen und an den Enden sanft zum Boden ab."""
    ov = AZ["ov"]
    rows = ((3.95, 1.0), (4.5, 1.0), (5.05, 1.0), (5.9, 0.0))            # (Abstand zur Mittellinie, Anteil der Anhebung)
    parts = []
    for zone in AZ_MUD:
        a, b = int(zone["from"] * N), int(zone["to"] * N) + 1
        for i in range(a - 2, b + 2):
            f0 = min(1.0, max(0.0, min(i - (a - 2), (b + 1) - i) / 2.0))
            f1 = min(1.0, max(0.0, min(i + 1 - (a - 2), (b + 1) - (i + 1)) / 2.0))
            for (da, ka), (db, kb) in zip(rows, rows[1:]):
                q = [(ov.p(i, da), ka * f0), (ov.p(i + 1, da), ka * f1), (ov.p(i + 1, db), kb * f1), (ov.p(i, db), kb * f0)]
                corners = [(p_[0], p_[1], AZ_GY + (AZ_MUD_Y - AZ_GY) * k_) for p_, k_ in q]
                parts.append(("gelaende", corners[::-1], [(c[0] / 3.0, -c[1] / 3.0) for c in corners[::-1]], None, [(1.0, 0.0, 1.0)] * 4))
    if parts:
        objs_ground.append(az_mesh("Schlammband", parts))


def theme_ground():
    az_setup()
    az_town_plan()
    az_ground()
    az_mud_strips()
    az_paving()
    az_water()


def theme_bake_hidden():
    return ["Meer"]                    # das Meer wirft/empfängt beim Backen nichts


def theme_layout(layout):
    layout["water_y"] = AZ_WATER_Y     # Wasserspiegel: nasser Sand im Gelände-Shader
    layout["prop_light"] = {"floodlight": dict(AZ_FLOOD_LIGHT)}   # Flutlichter der Streckendatei gedimmt (siehe AZ_FLOOD_LIGHT, docs/dioramen/README.md 2.6)


# ---------------------------------------------------------------- Pflaster: Ring um das Oval, Promenade, Boxengasse, Fahrerlager
def az_paving():
    ov = AZ["ov"]
    zones = AZ["zones"]
    parts = []
    y_p = AZ_GY + 0.03
    # Ring: Platten; auf der Seeseite (Zone F und ein Stück der Kurven) Holzplanken im äußeren Teil
    f0, f1 = zones["F"]
    pl0, pl1 = f0 - 30, f1 + 30
    AZ["planks"] = (pl0, pl1)
    for (ja, jb) in ov.span(0, N, 2, 8):
        is_pl = any(pl0 <= (j + t * N) <= pl1 for t in (0, 1) for j in (ja, jb))
        d_a = 13.0 if is_pl else AZ_PAVE_IN
        # Platten
        a0, a1 = ov.p(ja, AZ_PAVE_IN), ov.p(jb, AZ_PAVE_IN)
        b0, b1 = ov.p(ja, d_a), ov.p(jb, d_a)
        if d_a > AZ_PAVE_IN:
            quad = [a0, a1, b1, b0]
            parts.append(("platten", [(p[0], p[1], y_p) for p in quad], [(p[0] / 4.0, -p[1] / 4.0) for p in quad], None, None))
        if is_pl:
            c0, c1 = ov.p(ja, 13.0), ov.p(jb, 13.0)
            e0, e1 = ov.p(ja, AZ_PAVE_OUT), ov.p(jb, AZ_PAVE_OUT)
            quad = [c0, c1, e1, e0]
            ua, ub = ov.u(ja, 13.0), ov.u(jb, 13.0)
            ue_a, ue_b = ov.u(ja, AZ_PAVE_OUT), ov.u(jb, AZ_PAVE_OUT)
            parts.append(("planken", [(p[0], p[1], y_p + 0.012) for p in quad], [(ua / 2.0, 0.0), (ub / 2.0, 0.0), (ue_b / 2.0, 3.0), (ue_a / 2.0, 3.0)], None, None))
        else:
            e0, e1 = ov.p(ja, AZ_PAVE_OUT), ov.p(jb, AZ_PAVE_OUT)
            quad = [a0, a1, e1, e0]
            parts.append(("platten", [(p[0], p[1], y_p) for p in quad], [(p[0] / 4.0, -p[1] / 4.0) for p in quad], None, None))
    # Randbord außen
    for (ja, jb) in ov.span(0, N, 2, 8):
        a, b = ov.p(ja, AZ_PAVE_OUT), ov.p(jb, AZ_PAVE_OUT)
        a2, b2 = ov.p(ja, AZ_PAVE_OUT + 0.22), ov.p(jb, AZ_PAVE_OUT + 0.22)
        o = ov.out(ja)
        parts += [("k:farbe", [(a[0], a[1], y_p), (b[0], b[1], y_p), (b[0], b[1], y_p + 0.09), (a[0], a[1], y_p + 0.09)], [(0, 0), (1, 0), (1, 1), (0, 1)], (-o[0], -o[1]),
                   [azp.shade(azp.CONCRETE, 0.8)] * 2 + [azp.CONCRETE] * 2),
                  ("k:farbe", [(a[0], a[1], y_p + 0.09), (b[0], b[1], y_p + 0.09), (b2[0], b2[1], y_p + 0.09), (a2[0], a2[1], y_p + 0.09)][::-1], [(0, 0), (1, 0), (1, 1), (0, 1)],
                   None, [azp.CONCRETE] * 4),
                  ("k:farbe", [(a2[0], a2[1], AZ_GY), (b2[0], b2[1], AZ_GY), (b2[0], b2[1], y_p + 0.09), (a2[0], a2[1], y_p + 0.09)], [(0, 0), (1, 0), (1, 1), (0, 1)], o,
                   [azp.shade(azp.CONCRETE, 0.8)] * 2 + [azp.CONCRETE] * 2)]
    az_emit("Platz", parts, ground=True)
    # Boxengasse und Fahrerlager: Asphalt mit Markierungen
    y_a = AZ_GY + 0.025
    ap = []
    for (ra, rb, rc, rd) in ((-14.0, 14.0, 3.0, 7.55), (-17.4, 17.4, -6.8, -1.3)):
        ap += az_rect(ra, rb, rc, rd, y_a, "asphalt_str", tile=6.0)
    az_emit("Asphalt", ap, ground=True)
    marks = []
    y_m = y_a + 0.006
    marks += az_rect(-13.8, 13.8, 7.2, 7.34, y_m, "linie", tile=1.0)                  # Linie der Boxengasse zur Strecke
    marks += az_rect(-13.8, 13.8, 5.55, 5.63, y_m, "linie", tile=1.0)
    for k in range(7):                                                              # Trennlinien der Boxen
        xk = -11.45 + k * 3.7
        marks += az_rect(xk - 0.04, xk + 0.04, 3.55, 5.0, y_m, "linie", tile=1.0)
    for k in range(-5, 6):                                                          # Stellplätze der Transporter
        xk = k * 3.3
        marks += az_rect(xk - 0.04, xk + 0.04, -6.6, -1.5, y_m, "linie", tile=1.0)
    az_emit("Markierung", marks)


# ---------------------------------------------------------------- Szenerie
def az_put(model_name, x, z, ang, h, name="Prop_Modell", kind="baum", r=0.35, rect=None, trunk=0.0, clearance=None, base_y=None, ch=3.0):
    """Modell setzen (place des Kerns) und Hindernis passend ändern; benennt das Objekt "Prop_*" (gleiche Netze werden im Spiel zu MultiMeshes)."""
    ok = place(model_name, x, z, ang, h, clearance=(HW + 1.2) if clearance is None else clearance, trunk=trunk, base_y=base_y)
    if not ok:
        return False
    scene.collection.objects[-1].name = name
    c = colliders[-1]
    if kind is None:
        colliders.pop()
    elif rect is not None:
        colliders.pop()
        collide_rect(x, z, math.cos(ang), math.sin(ang), rect[0], rect[1], ch, kind)
    else:
        c["k"], c["r"], c["y"] = kind, round(r, 3), round(ch, 2)
    return True


def az_ring_rects(i0, i1, d1, d2, height, kind, step_curve=3, step_straight=12, pad=0.1):
    """Hindernisse entlang des Ovals zwischen den Abständen d1 und d2 (gedrehte Rechtecke je Teilstück)."""
    ov = AZ["ov"]
    dm = (d1 + d2) / 2
    for (ja, jb) in ov.span(i0, i1, step_curve, step_straight):
        a, b = ov.p(ja, dm), ov.p(jb, dm)
        ln = math.hypot(b[0] - a[0], b[1] - a[1])
        if ln < 1e-6:
            continue
        collide_rect((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (b[0] - a[0]) / ln, (b[1] - a[1]) / ln, ln / 2 + pad, (d2 - d1) / 2, height, kind)


AZ_SIGNS = {"haupt": (0, 0, 1024, 128), "tribuene_a": (0, 128, 512, 256), "tribuene_w": (512, 128, 1024, 256), "tribuene_o": (0, 256, 512, 384),
            "tribuene_s": (512, 256, 1024, 384), "fahrerlager": (0, 384, 512, 512), "willkommen": (512, 384, 1024, 512)}


def az_sign(parts, cell, cx, cz, out, width, y0, height, y_off=0.02):
    """Schild aus dem Beschilderungsatlas auf einer senkrechten Wand; out = Blickrichtung (Einheitsvektor), Betrachter davor."""
    xa, ya, xb, yb = AZ_SIGNS[cell]
    u0, u1, v1, v0 = xa / 1024.0, xb / 1024.0, 1.0 - ya / 512.0, 1.0 - yb / 512.0
    rx, rz = out[1], -out[0]                      # Rechts des Betrachters, der gegen out schaut
    px, pz = cx + out[0] * y_off, cz + out[1] * y_off
    p0 = (px - rx * width / 2, pz - rz * width / 2)
    p1 = (px + rx * width / 2, pz + rz * width / 2)
    parts.append(("schilder", [(p0[0], p0[1], y0), (p1[0], p1[1], y0), (p1[0], p1[1], y0 + height), (p0[0], p0[1], y0 + height)],
                  [(u0, v0), (u1, v0), (u1, v1), (u0, v1)], out, None))


def theme_scenery():
    rng_s = random.Random(31)
    az_kerb_skirts()
    az_wall_and_fence()
    az_stands(rng_s)
    az_roof()
    az_pit_area()
    az_light_masts()
    az_ring_decor(rng_s)
    az_beach(rng_s)
    az_parking(rng_s)
    az_town()
    az_hang(rng_s)
    az_park()
    az_lighting()
    ao_proxies()
    print("DIORAMA Küste: Hindernisse", len(colliders))


# ---------------------------------------------------------------- Nachtlicht: Lichtmasten, Lichtquellen und Lichtblocker
AZ_FLOOD_HEAD = 8.6                   # Höhe der Flutlichtköpfe, die das Spiel aus der Streckendatei baut (World.premium_prop "floodlight")
AZ_HOOD_DEG = 120.0                   # Blende der Flutlichter: halber Öffnungswinkel des Halbrings hinter dem Lampenkopf
AZ_POLE_D = 7.15                      # Abstand der Lichtmasten vor den Tribünen zur Mittellinie (zwischen Mauer und Glasbrüstung)
AZ_POLE_N = 14                        # Anzahl der Masten rund um das Oval
AZ_VB = dict(x=-10.0, z=-36.6, hx=7.0, hz=3.5)         # Beachvolleyballfeld (Mitte, halbe Maße; das Netz verläuft quer in der Mitte entlang z)
AZ_COOL = (0.95, 0.97, 1.0)           # Farbe der Flutlichter (wie die des Spiels), Lichtleisten und Torleuchten sind warmweiß
# Nachtstimmung (Befund 02.10.2026: das Stadion wirkte nachts wie bei Tag, der Rasen hellgrün und heller als am Tag). Die Lichtkarte summierte im Oval das
# 1- bis 3-Fache des Tageslichts; jetzt etwa die Hälfte, mit sichtbaren Lichtinseln der Masten. Die Werte in az_poles bleiben die Gestalt (wer wie stark
# im Verhältnis leuchtet), diese Faktoren die Gesamthelligkeit:
AZ_POLE_GAIN = 0.36                   # kalte Mastleuchten (Oval, Innenfeld, Boxendach): Stärke
AZ_POLE_REACH = 1.12                  # ... und Reichweite am Boden (etwas weiter: die Lichtinseln überlappen, das Oval bleibt durchgehend befahrbar hell)
AZ_WARM_GAIN = 0.6                    # warme Lichter (Volleyball, Lichtleisten, Boxengasse, Tor) und Schein der Videowand
# Die sieben Flutlichter der Streckendatei (Laufzeit-Bauteile "floodlight", Lichtradius 50 m) dimmt die Begleitdatei ("prop_light", World.light_pool):
# kürzere Reichweite, damit sie die Tribünen vor sich anstrahlen, aber nicht mehr flächig das ganze Oval.
AZ_FLOOD_LIGHT = {"energy": 0.7, "reach": 0.55}
AZ_WARM = (1.0, 0.93, 0.8)


def az_poles():
    """Lichtmasten des Stadions: rund um das Oval vor den Tribünen, an den Enden des Innenfelds und auf dem Boxendach. Eintrag: Mastfuß (x, z),
    Richtung des Auslegers (ux, uz), Fußhöhe y, Höhe des Lampenkopfs über dem Fuß h, Länge des Auslegers, Lichtstärke e, Reichweite r, Leuchtfleck glow."""
    ov = AZ["ov"]
    poles = []
    for k in range(AZ_POLE_N):
        i = int(round((k + 0.5) * N / AZ_POLE_N)) % N
        p = ov.p(i, AZ_POLE_D)
        o = ov.out(i)
        poles.append(dict(x=p[0], z=p[1], ux=-o[0], uz=-o[1], y=AZ_GY, h=6.0, arm=0.9, e=0.26, r=19.0, glow=1.2))
    for (x, z, cx, cz) in ((-21.6, -3.9, -14.0, 0.0), (21.7, -4.0, 14.0, 0.0)):         # Innenfeld: Ausleger zur Strecke (vom Mittelpunkt des Bogens weg)
        n = math.hypot(x - cx, z - cz)
        poles.append(dict(x=x, z=z, ux=(x - cx) / n, uz=(z - cz) / n, y=AZ_GY, h=9.0, arm=0.9, e=0.30, r=20.0, glow=1.3))
    for x in (-10.6, 10.6):                                                             # Boxendach (Dachhaut bei 3,62 m)
        poles.append(dict(x=x, z=2.4, ux=0.0, uz=1.0, y=AZ_GY + 3.62, h=3.6, arm=0.9, e=0.30, r=18.0, glow=1.2))
    vb = AZ_VB                                                                          # Flutlicht am Beachvolleyballfeld (Fußhöhe = Sand)
    for sgn in (-1, 1):
        x = vb["x"] + sgn * (vb["hx"] + 1.2)
        poles.append(dict(x=x, z=vb["z"], ux=-sgn, uz=0.0, y=az_land_h(x, vb["z"]), h=5.4, arm=0.9, e=0.5, r=12.0, glow=0.9, warm=True))
    return poles


def az_light_masts():
    """Geometrie der Lichtmasten (az_poles); die am Boden stehenden sind Hindernisse (Mast)."""
    parts = []
    for p in az_poles():
        parts += azo.light_pole(p["x"], p["z"], p["ux"], p["uz"], p["h"], p["y"], p["arm"])
        if p["y"] < AZ_GY + 1.0:
            collide_circle(p["x"], p["z"], 0.2, p["h"], "mast")
            placed.append(rect_corners(p["x"], p["z"], 0.45, 0.45, 0.0))
    az_emit("Lichtmasten", parts)


def az_lighting():
    """Echte Lichtquellen und Lichtblocker (Lichtkarte des Spiels, siehe docs/dioramen/README.md Abschnitt 2.5).
    - Rückwände der Tribünen, Boxengebäude und Transporter: werfen Schatten (kein lichtgrüner Rasen hinter den Tribünen).
    - Blenden hinter den sieben Flutlichtern der Streckendatei: ihr Licht zeigt zum Oval und nicht nach außen (die Köpfe stehen hinter den Tribünen).
    - Lichtquellen im Stadion: Lichtmasten, Lichtleisten des Segeldachs, Lichtdach der Boxengasse, Torleuchten, Schein der Videowand."""
    ov = AZ["ov"]
    for z_name, (i0, i1) in AZ["zones"].items():
        top, d_back = azp.stand_dims(AZ["rows"][z_name], AZ_STAND_D)
        add_occluder_chain([ov.p(i, d_back + 0.25) for i in range(i0, i1 + 1, 2)], width=0.8, height=AZ_GY + top)
    add_occluder_poly(rect_corners(0.0, 1.3, 11.5, 2.25, 0.0), AZ_GY + 3.9)             # Boxengebäude (3,9 m) mit Rennleitung (6,4 m)
    add_occluder_poly(rect_corners(0.0, 0.5, 2.9, 1.3, 0.0), AZ_GY + 6.5)
    for x in (-11.2, 0.0, 11.2):                                                         # Team-Transporter (3,8 m)
        add_occluder_poly(rect_corners(x, -4.1, 5.2, 1.3, 0.0), AZ_GY + 3.8)
    n_hoods = 0
    for p in data["props"]:
        if p.get("type") != "floodlight":
            continue
        px, pz = float(p["x"]), float(p["z"])
        n = math.hypot(px, pz) or 1.0
        add_occluder_poly(azp.hood_poly(px, pz, (-px / n, -pz / n), 1.5, 2.1, AZ_HOOD_DEG), AZ_FLOOD_HEAD + 0.9)
        n_hoods += 1
    for p in az_poles():
        warm = p.get("warm")
        add_light(p["x"] + p["ux"] * p["arm"], p["z"] + p["uz"] * p["arm"], p["y"] + p["h"] - 0.15, AZ_WARM if warm else AZ_COOL,
                  round(p["e"] * (AZ_WARM_GAIN if warm else AZ_POLE_GAIN), 3), round(p["r"] * (1.0 if warm else AZ_POLE_REACH), 2), omni=False, glow=p["glow"])
    for k in range(5):                                                                   # Lichtleisten unter der Vorderkante des Segeldachs
        add_light(-14.0 + 7.0 * k, 24.2, AZ_GY + 6.6, AZ_WARM, 0.4 * AZ_WARM_GAIN, 17.0, omni=False, glow=1.0)
    for k in range(6):                                                                   # Lichtdach der Boxengasse
        add_light(-9.25 + 3.7 * k, 4.65, AZ_GY + 3.2, AZ_WARM, 0.55 * AZ_WARM_GAIN, 7.0, omni=False)
    for sgn in (-1, 1):                                                                  # Torleuchten am Eingang
        add_light(sgn * 5.4, 34.2, AZ_GY + 4.6, AZ_WARM, 0.6 * AZ_WARM_GAIN, 9.0, omni=False, glow=0.9)
    sx, sz = AZ["screen"]
    add_light(sx, sz, 3.6, (0.4, 0.65, 1.0), 0.5 * AZ_WARM_GAIN, 10.0, omni=False)   # Schein der Videowand
    print("DIORAMA Küste: Lichtblocker", len(occluder_polys) if "occluder_polys" in globals() else n_hoods, "Blenden an Flutlichtern", n_hoods)


def az_kerb_skirts():
    """Senkrechte Kante unter dem flachen Randstein (der Boden liegt tiefer als die gemalte Fahrbahn)."""
    parts = []
    off = HW + KERB_W
    top = ROAD_Y + 0.018
    for s in (-1, 1):
        for i in range(N):
            j = (i + 1) % N
            p0 = center[i] + left[i] * s * off
            p1 = center[j] + left[j] * s * off
            o = left[i] * s
            v0, v1 = dist[i], dist[i + 1]
            parts.append(("kerb_paint", [(p0.x, p0.y, AZ_GY), (p1.x, p1.y, AZ_GY), (p1.x, p1.y, top), (p0.x, p0.y, top)],
                          [(0.0, v0), (0.0, v1), (0.15, v1), (0.15, v0)], (o.x, o.y), None))
    az_emit("Kerbkante", parts)


def az_wall_and_fence():
    ov = AZ["ov"]
    az_emit("Mauer", azp.build_wall(ov, 0, N, AZ_WALL_D, AZ_GY))
    az_ring_rects(0, N, AZ_WALL_D - 0.18, AZ_WALL_D + 0.18, 1.0, "mauer", 4, 8, 0.08)


def az_stands(rng_s):
    ov = AZ["ov"]
    zones = AZ["zones"]
    rows = AZ["rows"]
    # Sitzfarben (Palette, Gewichte) und mittlere Füllung der Tribünen je Zone: Haupttribüne voll, Seeseite lichter
    seats = {"M": (("sitz_az", "sitz_wh", "sitz_na", "sitz_co"), (4, 3, 2, 1), 0.98), "E": (("sitz_co", "sitz_wh", "sitz_az", "sitz_te"), (4, 3, 2, 1), 0.93),
             "F": (("sitz_te", "sitz_wh", "sitz_az", "sitz_co"), (4, 3, 2, 1), 0.84), "W": (("sitz_az", "sitz_wh", "sitz_co", "sitz_na"), (4, 3, 2, 1), 0.9)}
    allp = []
    info = {}
    order = ["M", "E", "F", "W"]                                     # Nachbarn im Umlauf; Stirnwände nur gegen niedrigere Nachbarn
    for z_name, (i0, i1) in zones.items():
        k = order.index(z_name)
        prev_rows, next_rows = rows[order[k - 1]], rows[order[(k + 1) % 4]]
        mine = rows[z_name]
        pal, wts, dens = seats[z_name]
        st, h_last, d_back = azp.build_stand(ov, i0, i1, mine, rng_s, AZ_STAND_D, AZ_GY, seats=pal, seat_w=wts, density=dens, salt=k + 1,
                                             caps=(prev_rows < mine, next_rows < mine), cap_skip=(prev_rows, next_rows))
        allp += st
        info[z_name] = (h_last, d_back)
        az_ring_rects(i0, i1, AZ_STAND_D - 0.05, d_back + 0.5, h_last + 1.1, "mauer", 6, 14)
    allp += azp.build_barrier(ov, 0, N, AZ_STAND_D - 0.12, AZ_GY, base=0.35)
    allp += azp.banner_strip(ov, 0, N, AZ_STAND_D - 0.03, AZ_GY + 0.05, AZ_GY + 0.52, [0, 6, 7, 1, 5, 2, 4], step=4)
    # Beschilderung an den Rückwänden, Fahnen auf den Rückwänden
    for z_name, cell in (("M", "haupt"), ("E", "tribuene_o"), ("F", "tribuene_s"), ("W", "tribuene_w")):
        i0, i1 = zones[z_name]
        h_last, d_back = info[z_name]
        if z_name == "M":                     # zwischen den Dachmasten (Abstand 7 m): Namensschild in der Mitte, Schriftzug links und rechts
            yb_ = 13.0 + d_back + 0.5
            az_sign(allp, "tribuene_a", 0.0, yb_, (0.0, 1.0), 6.0, AZ_GY + 2.6, 1.5)
            for sx in (-7.0, 7.0):
                az_sign(allp, "haupt", sx, yb_, (0.0, 1.0), 6.0, AZ_GY + 3.0, 0.75)
        else:
            im = (i0 + i1) // 2
            p = ov.p(im, d_back + 0.5)
            az_sign(allp, cell, p[0], p[1], ov.out(im), 7.0, AZ_GY + max(1.8, h_last * 0.45), 1.75)
        run = 0.0
        last = ov.p(i0, d_back + 0.25)
        col = 0
        flag_cols = [azp.AZURE, azp.WHITE, azp.CORAL]
        for i in range(i0, i1 + 1):
            q = ov.p(i, d_back + 0.25)
            run += math.hypot(q[0] - last[0], q[1] - last[1])
            last = q
            if run >= 6.5 and i < i1 - 2:
                run = 0.0
                allp += azo.flag_pole(q[0], q[1], 0.0, -1.0, 3.6, flag_cols[col % 3], AZ_GY + h_last + 1.1)
                col += 1
    az_emit("Tribuene", allp, decal=True)
    AZ["stand_info"] = info


def az_roof():
    parts = azo.sail_roof(-17.5, 17.5, 13.0 + 18.6, 13.0 + 11.2, 9.0, 7.3, y_base=AZ_GY, stay=6.5)
    az_emit("Dach", parts)
    for k in range(6):                                               # Masten als Hindernisse
        collide_circle(-17.5 + 7.0 * k, 13.0 + 18.6 + 1.3, 0.35, 10.0, "mast")


def az_pit_area():
    """Boxengebäude mit Rennleitung, Rennwagen vor den Toren, Reifenstapel, Boxenmauer, Fahrerlager mit Transportern, Videowand."""
    y_a = AZ_GY + 0.025
    parts, width = azo.pit_building(0.0, 3.5, y_base=AZ_GY)
    # Schriftfeld auf der Blende
    parts.append(("fascia", [(-5.0, 3.655, AZ_GY + 2.9), (5.0, 3.655, AZ_GY + 2.9), (5.0, 3.655, AZ_GY + 3.45), (-5.0, 3.655, AZ_GY + 3.45)], [(0, 0), (1, 0), (1, 1), (0, 1)], (0.0, 1.0), None))
    # Boxenmauer an der Boxengasse (niedrig, weiß mit azurblauer Kappe); an der Startlinie bleibt eine Lücke (Boxeneinfahrt/-ausfahrt)
    for (xa_, xb_) in ((-14.0, -4.2), (4.2, 14.0)):
        azp.boxd(parts, xa_, xb_, 7.46, 7.74, y_a, y_a + 0.5, azp.OFFWHITE)
        azp.boxd(parts, xa_ - 0.05, xb_ + 0.05, 7.44, 7.76, y_a + 0.5, y_a + 0.56, azp.AZURE, ao=1.0)
        collide_rect((xa_ + xb_) / 2, 7.6, 1.0, 0.0, (xb_ - xa_) / 2, 0.15, 0.55, "mauer")
    collide_rect(0.0, 1.3, 1.0, 0.0, 11.5, 2.25, 3.8, "mauer")
    light_blockers.append([0.0, 1.3, 11.5, 2.25, 0.0])
    placed.append(rect_corners(0.0, 1.3, 11.8, 2.5, 0.0))
    placed.append(rect_corners(0.0, 5.3, 14.2, 2.4, 0.0))
    # Rennwagen vor den Toren (Tor 0, 1, 3, 4), leicht versetzt
    bay_x = [-9.25 + 3.7 * k for k in range(6)]
    liveries = [(azp.AZURE, azp.WHITE), (azp.WHITE, azp.CORAL), None, (azp.CORAL, azp.NAVY), (azp.TEAL, azp.WHITE)]
    for k, lv in enumerate(liveries):
        if lv is None:
            continue
        yaw = (0.07, -0.05, 0.0, 0.04, -0.08)[k]
        ux, uz = math.sin(yaw), math.cos(yaw)
        cx, cz = bay_x[k] + 0.1 * k - 0.2, 4.6 + (0.1 if k % 2 else -0.1)
        parts += azo.race_car(cx, cz, ux, uz, lv[0], lv[1], y_base=y_a)
        collide_rect(cx, cz, ux, uz, 2.2, 0.95, 1.1, "auto")
    # Boxencrew: je Wagen drei Leute in der Teamfarbe, dazu Gäste vor dem Aufenthaltsraum
    crew_cols = [azp.AZURE, azp.OFFWHITE, None, azp.CORAL, azp.TEAL]
    for k, lv in enumerate(liveries):
        if lv is None:
            continue
        cx = bay_x[k] + 0.1 * k - 0.2
        for (dx, dz, face) in ((-1.15, 6.2, (0.4, 1.0)), (1.2, 6.5, (-0.3, 1.0)), (0.0, 2.9, (0.0, 1.0))):
            parts += azo.person(cx + dx, dz, face[0], face[1], crew_cols[k], azp.NAVY, y_a, helmet=azp.WHITE if k % 2 else azp.CORAL)
            collide_circle(cx + dx, dz, 0.22, 1.7, "mast")
    for (gx, gz) in ((9.0, 5.1), (9.7, 5.5), (11.2, 5.2)):
        parts += azo.person(gx, gz, -0.5, 1.0, azp.OFFWHITE, azp.STEEL_D, y_a)
    # Reifenstapel an den Gebäudeenden und an der Boxenmauer
    for (x, z) in ((-12.6, 4.4), (-12.6, 5.3), (-11.7, 4.85), (12.6, 4.4), (12.6, 5.3), (11.7, 4.85), (-6.0, 7.0), (6.0, 7.0), (-13.0, 6.9), (13.0, 6.9)):
        parts += azo.tyre_stack(x, z, 3, y_a)
        collide_circle(x, z, 0.42, 0.85, "reifen")
    az_emit("Boxen", parts)
    # Fahrerlager: drei Transporter
    tp = []
    for (x, direction, livery, cab) in ((-11.2, 1.0, "lkw_azure", azp.WHITE), (0.0, -1.0, "lkw_coral", azp.OFFWHITE), (11.2, 1.0, "lkw_navy", azp.WHITE)):
        tp += azo.transporter(x, -4.1, direction, 0.0, livery, y_base=y_a, cab=cab, length=10.4)
        collide_rect(x, -4.1, 1.0, 0.0, 5.2, 1.3, 3.8, "mauer")
        placed.append(rect_corners(x, -4.1, 5.4, 1.5, 0.0))
    az_emit("Transporter", tp)
    for x_l in (-14.0, -5.0, 5.0, 14.0):                             # Laternen am Südrand des Fahrerlagers
        lamps.append((Vector((x_l, -8.0)), Vector((x_l, -3.5))))
        placed.append(rect_corners(x_l, -8.0, 0.4, 0.4, 0.0))
    # Videowand am Ostende des Innenfelds: nach hinten geneigt, Bild zur Rennkamera hin (K_-Oberfläche: tagsüber dunkel, nachts Leuchtbild)
    sd = AZ_SCREEN
    sc, back = azo.video_screen(sd["x"], sd["z"], sd["fx"], sd["fz"], sd["w"], sd["h"], sd["y0"], sd["lean"], y_base=AZ_GY)
    az_emit("Videowand", sc)
    ux, uz = sd["fz"], -sd["fx"]
    cb = -(back - 0.4) / 2.0                                         # Mitte des Grundrisses längs der Blickrichtung (vorn 0,4 m, hinten bis zu den Füßen)
    collide_rect(sd["x"] + sd["fx"] * cb, sd["z"] + sd["fz"] * cb, ux, uz, sd["w"] / 2 + 0.3, (back + 0.4) / 2.0, 5.5, "mauer")
    placed.append(rect_corners(sd["x"] + sd["fx"] * cb, sd["z"] + sd["fz"] * cb, sd["w"] / 2 + 0.6, (back + 0.8) / 2.0, math.atan2(uz, ux)))
    # Palmenbeete: Westende (Blumenbeet mit drei Palmen, sechs Kübel ringsum), Ostende (Beet mit zwei Palmen vor der Videowand)
    bed = azo.flower_bed(-18.0, 0.0, 1.9, AZ_GY)
    bed += azo.flower_bed(19.6, -3.0, 1.4, AZ_GY)
    az_emit("Beete", bed, ground=False)
    ccx, ccz = -18.0, 0.0
    for k in range(6):
        a = 2 * math.pi * k / 6 + 0.3
        px, pz = ccx + 3.0 * math.cos(a), ccz + 3.0 * math.sin(a)
        az_put("kueste_pflanzkuebel_lo", px, pz, a + math.pi / 2, 0.9, "Prop_Kuebel", kind="bank", rect=(0.93, 0.33), ch=0.9, clearance=HW + 1.2)
    for (dx, dz, h) in ((0.0, 0.0, 4.6), (-0.9, 0.9, 3.8), (0.8, -0.9, 4.1)):
        az_put("kueste_palme_lo", ccx + dx, ccz + dz, 0.0, h, "Prop_Palme", trunk=0.35)
    for (px, pz, h) in ((19.3, -2.8, 4.4), (20.2, -3.4, 3.8)):
        az_put("kueste_palme_lo", px, pz, 0.0, h, "Prop_Palme", trunk=0.35)


def az_ring_decor(rng_s):
    """Streckenposten im Innenfeld, Reifenwand in den Schlammzonen, Palmen am äußeren Rand des Rings, Laternen, Bänke."""
    ov = AZ["ov"]
    parts = []
    # Streckenposten (Innenfeld, Blick zur Strecke)
    for i in (62, 138, 205):
        p = ov.p(i, -5.9)
        o = ov.out(i)
        parts += azo.marshal_post(p[0], p[1], o[0], o[1], y_base=AZ_GY)
        collide_rect(p[0], p[1], o[0], o[1], 0.8, 1.0, 2.4, "mauer")
        placed.append(rect_corners(p[0], p[1], 1.3, 1.3, 0.0))
    # Reifenwand vor der Mauer in den Schlammzonen (eine Reihe Dreierstapel, weiche Hindernisse)
    for zone in [z_ for z_ in data.get("surfaces", []) if z_.get("kind") == "mud"]:
        a, b = int(zone["from"] * N) + 2, int(zone["to"] * N) - 2
        for i in range(a, b):
            q = ov.p(i, 6.1)
            parts += azo.tyre_stack(q[0], q[1], 3, AZ_GY, r=0.37)
        for (ja, jb) in ov.span(a, b, 4, 4):
            qa, qb = ov.p(ja, 6.1), ov.p(jb, 6.1)
            ln = math.hypot(qb[0] - qa[0], qb[1] - qa[1])
            collide_rect((qa[0] + qb[0]) / 2, (qa[1] + qb[1]) / 2, (qb[0] - qa[0]) / ln, (qb[1] - qa[1]) / ln, ln / 2 + 0.3, 0.4, 0.85, "reifen")
    az_emit("Reifenwand", parts)
    # Palmen am Außenrand des Rings (nicht an der Promenade)
    pl0, pl1 = AZ["planks"]
    run = 0.0
    last = ov.p(0, 20.3)
    n_palm = 0
    for i in range(0, N):
        q = ov.p(i, 20.5)
        run += math.hypot(q[0] - last[0], q[1] - last[1])
        last = q
        in_pl = any(pl0 <= i + t * N <= pl1 for t in (0, 1))
        if run >= 10.0 and not in_pl:
            run = 0.0
            if az_put("kueste_palme_lo", q[0], q[1], rng_s.uniform(0, 6.28), rng_s.uniform(4.2, 5.4), "Prop_Palme", trunk=0.35, clearance=HW + 3.0):
                n_palm += 1
    # Promenade: Palmen in Baumscheiben, Bänke, Laternen
    pp = []
    run = 0.0
    last = ov.p(pl0, 15.6)
    for i in range(pl0, pl1 + 1):
        q = ov.p(i, 15.6)
        run += math.hypot(q[0] - last[0], q[1] - last[1])
        last = q
        if run >= 7.5:
            run = 0.0
            if az_put("kueste_palme_lo", q[0], q[1], rng_s.uniform(0, 6.28), rng_s.uniform(4.4, 5.4), "Prop_Palme", trunk=0.35, clearance=HW + 3.0):
                pp += azo.tree_pit(q[0], q[1], AZ_GY + 0.03)
                n_palm += 1
    run, k = 0.0, 0
    last = ov.p(pl0, 18.1)
    for i in range(pl0 + 3, pl1 - 2):
        q = ov.p(i, 18.1)
        run += math.hypot(q[0] - last[0], q[1] - last[1])
        last = q
        if run >= 9.0:
            run = 0.0
            o = ov.out(i)
            if k % 2 == 0:
                pp += azo.bench(q[0], q[1], o[0], o[1], AZ_GY + 0.042)
                collide_rect(q[0], q[1], -o[1], o[0], 0.85, 0.3, 0.9, "bank")
            else:
                tw = ov.p(i, 16.5)
                lamps.append((Vector(q), Vector(tw)))
            k += 1
    az_emit("Promenade", pp)
    # Laternen am Rand des Rings (laufen zur Laufzeit; nachts Licht)
    run, k = 0.0, 0
    last = ov.p(0, 18.4)
    for i in range(0, N):
        q = ov.p(i, 18.4)
        run += math.hypot(q[0] - last[0], q[1] - last[1])
        last = q
        if run >= 15.0 and not any(pl0 <= i + t * N <= pl1 for t in (0, 1)):
            run = 0.0
            lamps.append((Vector(q), Vector(ov.p(i, 12.0))))
    print("DIORAMA Küste: Palmen am Ring", n_palm)


def az_beach(rng_s):
    """Strand: Sonnenschirme mit Liegen, Rettungstürme, Felsen an den Strandenden."""
    parts = []
    vb_ = AZ_VB
    placed.append(rect_corners(vb_["x"], vb_["z"], vb_["hx"] + 1.8, vb_["hz"] + 1.8, 0.0))     # Spielfeld bleibt frei von Schirmen
    for (tx_, tz_) in ((-35.0, -38.4), (28.0, -38.5), (0.0, -31.8)):                              # Rettungstürme und der Flutlichtmast des Spiels (Streckendatei)
        placed.append(rect_corners(tx_, tz_, 2.2, 2.2, 0.0))
    towel = [(0.7, 0.05, 0.04), (0.02, 0.18, 0.55), (0.85, 0.6, 0.05), (0.04, 0.4, 0.38), (0.9, 0.9, 0.87)]
    n = 0
    for k in range(11):
        x = -30.0 + k * 6.0 + rng_s.uniform(-1.0, 1.0)
        z = -35.6 - rng_s.uniform(0.0, 2.2) - (1.2 if k % 2 else 0.0)
        zs = float(az_shore(np.array([x]))[0])
        if z < zs + 3.0:
            continue
        y = float(az_height(np.array([x]), np.array([z]))[0])
        if az_put("kueste_sonnenschirm_lo", x, z, rng_s.uniform(0, 6.28), 2.5, "Prop_Schirm", kind="mast", r=0.14, base_y=y, clearance=HW + 3.0, ch=2.4):
            for sgn in (-1, 1):
                lx, lz = x + sgn * 0.95, z + 0.55
                ly = float(az_height(np.array([lx]), np.array([lz]))[0])
                parts += azo.lounger(lx, lz, 0.0, -1.0, towel[(k + (sgn > 0)) % len(towel)], y_base=ly)
                collide_rect(lx, lz, 0.0, 1.0, 0.95, 0.32, 0.5, "bank")
            n += 1
    for (x, z) in ((-35.0, -38.4), (28.0, -38.5)):
        y = float(az_height(np.array([x]), np.array([z]))[0])
        parts += azo.lifeguard_tower(x, z, 0.0, -1.0, y_base=y)
        collide_rect(x, z, 1.0, 0.0, 1.3, 1.3, 3.2, "mauer")
    cafe = azo.beach_cafe(36.0, -35.2, 0.0, -1.0, y_base=float(az_height(np.array([36.0]), np.array([-35.2]))[0]))
    az_emit("Strandcafe", cafe)
    collide_rect(36.0, -35.2, 0.0, -1.0, 1.9, 3.5, 3.8, "mauer")
    placed.append(rect_corners(36.0, -35.2, 4.5, 4.5, 0.0))
    for (tx, tz) in ((33.0, -39.0), (36.5, -39.4), (40.0, -38.8)):
        ty = float(az_height(np.array([tx]), np.array([tz]))[0])
        az_put("kueste_sonnenschirm_lo", tx, tz, rng_s.uniform(0, 6.28), 2.5, "Prop_Schirm", kind="mast", r=0.14, base_y=ty, clearance=HW + 3.0, ch=2.4)
    boats = []
    for (bx, bz, bu, col, sail) in ((-32.0, -52.0, 0.3, azp.WHITE, azp.OFFWHITE), (-12.0, -60.0, -0.2, azp.AZURE, azp.WHITE), (18.0, -49.0, 0.5, azp.WHITE, azp.CORAL),
                                    (42.0, -58.0, -0.4, azp.NAVY, azp.OFFWHITE), (-50.0, -57.0, 0.1, azp.CORAL, azp.WHITE)):
        boats += azo.sailboat(bx, bz, math.cos(bu), math.sin(bu), col, sail, y_base=AZ_WATER_Y + 0.08)
    az_emit("Boote", boats)
    az_emit("Strand", parts)
    for (x, z, h) in ((-58.0, -38.0, 1.5), (-54.0, -41.5, 1.0), (-49.0, -43.5, 0.8), (51.0, -42.5, 1.3), (56.0, -39.0, 1.6), (47.0, -44.0, 0.9)):
        y = float(az_height(np.array([x]), np.array([z]))[0])
        az_put("kueste_felsen", x, z, rng_s.uniform(0, 6.28), h, "Prop_Fels", kind="mauer", r=h * 0.6, base_y=y - 0.15 * h, clearance=HW + 9.0, ch=h)
    az_volleyball(rng_s)
    az_beach_life(rng_s)
    print("DIORAMA Küste: Schirme", n)


# ---------------------------------------------------------------- Seestadt am Hang (Umgebung hinter dem Stadion)
AZ_TOWN_ROWS = (78.0, 98.0, 118.0)          # Häuserreihen am Nordhang (Mitte z); die Gassen liegen 11,5 m davor
AZ_TOWN = []                                # geplante Häuser: dict(spec, cx, cz, f, w, d, ph)


def az_house_dims(spec):
    """Breite und Tiefe eines Bausatzhauses nach Rasterung (wie kit_dims des Kerns)."""
    bay = kit_house.STYLES[spec["style"]]["bay"]
    return max(2, round(spec["w"] / bay)) * bay, max(2, round(spec["d"] / bay)) * bay


def az_house_spec(r, kind, max_floors):
    k = kit_house.KINDS[kind]
    styles = ("putz", "putz", "altbau") if kind in ("reihenhaus", "stadthaus") else k["styles"]
    return {"kind": kind, "style": r.choice(styles), "w": r.uniform(*k["w"]), "d": r.uniform(*k["d"]), "floors": min(r.randint(*k["floors"]), max_floors),
            "roof": r.choice(k["roof"]), "front": "wohn", "seed": r.randrange(1 << 30), "max_h": 60.0}


def az_town_plan():
    """Häuser und Hotels der Seestadt festlegen (und die Hausplätze als ebene Terrassen in AZ_PADS eintragen), bevor das Gelände gebaut wird."""
    r = random.Random(1717)
    AZ_TOWN.clear()
    taken = []

    def put(spec, cx, cz, face):
        w, d = az_house_dims(spec)
        hx, hz = (w / 2, d / 2) if face[0] == 0 else (d / 2, w / 2)
        box_ = (cx - hx - 2.0, cx + hx + 2.0, cz - hz - 2.0, cz + hz + 2.0)
        if any(box_[0] < t[1] and box_[1] > t[0] and box_[2] < t[3] and box_[3] > t[2] for t in taken):
            return False
        taken.append(box_)
        ph = float(az_hill_h(np.array([cx]), np.array([cz]))[0])
        AZ_PADS.append((cx, cz, hx + 0.8, hz + 0.8, ph))
        AZ_TOWN.append(dict(spec=spec, cx=cx, cz=cz, f=face, w=w, d=d, ph=ph))
        return True
    # Hotels zuerst: hohe Riegel und Türme auf den oberen Reihen (so verdecken sie die Häuser davor nicht)
    for (kind, x, z, fl) in (("buero", -46.0, 124.0, 10), ("riegel", 26.0, 110.0, 7), ("buero", -104.0, 100.0, 8), ("riegel", 88.0, 104.0, 6), ("buero", 62.0, 132.0, 10)):
        put(az_house_spec(r, kind, fl), x, z, (0.0, -1.0))
    # Reihen am Nordhang (Fassaden nach Süden zum Stadion und zum Meer); vorn niedrige, hinten höhere Häuser
    for zrow, fl_max in zip(AZ_TOWN_ROWS, (3, 4, 5)):
        x = -116.0 + r.uniform(0.0, 6.0)
        while x < 112.0:
            kind = r.choices(("reihenhaus", "stadthaus"), (5, 5))[0]
            spec = az_house_spec(r, kind, fl_max)
            w, d = az_house_dims(spec)
            put(spec, x + w / 2, zrow + r.uniform(-1.5, 1.5), (0.0, -1.0))
            x += w + r.uniform(1.5, 7.0)
    # Seitenhänge: Fassaden zur Mitte (Osten: nach Westen)
    for side in (1, -1):
        face = (-float(side), 0.0)
        for xrow, fl_max in zip((98.0, 114.0, 130.0), (3, 4, 5)):
            z = -6.0 + r.uniform(0.0, 6.0)
            while z < 92.0:
                kind = r.choices(("reihenhaus", "stadthaus"), (5, 5))[0]
                spec = az_house_spec(r, kind, fl_max)
                w, d = az_house_dims(spec)
                put(spec, side * (xrow + r.uniform(-1.5, 1.5)), z + w / 2, face)
                z += w + r.uniform(1.5, 8.0)
    AZ["town_boxes"] = taken
    vb = AZ_VB                                                       # Beachvolleyball: ebenes Feld in der Mitte des Strandhangs
    AZ_PADS.append((vb["x"], vb["z"], vb["hx"] + 1.4, vb["hz"] + 1.4, az_land_h(vb["x"], vb["z"] + 1.0) - AZ_GY))
    print("DIORAMA Seestadt: Häuser", len(AZ_TOWN))


def az_town():
    """Häuser der Seestadt aus dem Bausatz des Kerns (Fenster leuchten nachts mit dem Fensterlicht des Spiels); nur Bild, keine Hindernisse."""
    for t in AZ_TOWN:
        fx, fz = t["f"]
        ux, uz = -fz, fx
        parts, foot, dims = kit_house.build_house(KIT_TILES, t["spec"], t["cx"], t["cz"], ux, uz, fx, fz, base_y=AZ_GY + t["ph"] - 0.05)
        kit_far.extend(parts)
        recipe["houses"].append({**{k: (round(v, 3) if isinstance(v, float) else v) for k, v in t["spec"].items()},
                                 "at": [round(t["cx"], 3), round(t["cz"], 3)], "u": [round(ux, 5), round(uz, 5)], "f": [round(fx, 5), round(fz, 5)]})


def az_land_h(x, z):
    return float(az_height(np.array([x]), np.array([z]))[0])


def az_hang(rng_s):
    """Gassen am Hang (Asphaltbänder, dem Gelände folgend) mit parkenden Autos, Hecken, Zypressen, Schirmpinien und einfachen Palmen."""
    r = random.Random(4242)
    road, marks, cars, veg = [], [], [], []
    lines = az_alley_lines()                                         # Gassen: (Anfang x, z, Ende x, z)
    for (xa, za, xb, zb) in lines:
        L = math.hypot(xb - xa, zb - za)
        ux, uz = (xb - xa) / L, (zb - za) / L
        n = int(L // 2.0)
        for k in range(n):
            p0 = (xa + ux * 2.0 * k, za + uz * 2.0 * k)
            p1 = (xa + ux * 2.0 * (k + 1), za + uz * 2.0 * (k + 1))
            nx_, nz_ = -uz * 2.0, ux * 2.0
            pts = [(p0[0] - nx_, p0[1] - nz_), (p1[0] - nx_, p1[1] - nz_), (p1[0] + nx_, p1[1] + nz_), (p0[0] + nx_, p0[1] + nz_)]
            hs = [az_land_h(q[0], q[1]) + 0.10 for q in pts]
            road.append(("asphalt_str", [(q[0], q[1], h) for q, h in zip(pts, hs)], [(q[0] / 6.0, -q[1] / 6.0) for q in pts], None, None))
        az_cars_along(rng_s, xa + ux * 3.0 + (-uz) * 1.3, za + uz * 3.0 + ux * 1.3, xb + (-uz) * 1.3, zb + ux * 1.3, cars,
                      lambda x, z: az_land_h(x, z) + 0.10, fill=0.22)
    az_emit("Gassen", road, ground=True)
    az_emit("Gassenautos", cars)
    boxes = AZ.get("town_boxes", [])
    nveg = 0
    for zz in np.arange(64.0, 168.0, 6.5):
        for xx in np.arange(-130.0, 130.0, 6.5):
            x, z = xx + r.uniform(-2.5, 2.5), zz + r.uniform(-2.5, 2.5)
            hh = float(az_hill_h(np.array([x]), np.array([z]))[0])
            if hh < 0.4 and z > 70.0:
                continue
            if any(b[0] - 1.5 < x < b[1] + 1.5 and b[2] - 1.5 < z < b[3] + 1.5 for b in boxes):
                continue
            if any(abs(z - (zr - 11.5)) < 3.3 for zr in AZ_TOWN_ROWS):
                continue
            grove = float(az_vnoise(np.array([x]), np.array([z]), 21.0)[0])
            if r.random() > (0.62 if grove > 0.5 else 0.2):
                continue
            y = az_land_h(x, z)
            pick = r.random()
            if grove > 0.5 and pick < 0.5:
                veg += azo.cypress(x, z, r.uniform(5.5, 8.5), y)
            elif pick < 0.62:
                veg += azo.stone_pine(x, z, r.uniform(6.0, 8.5), y)
            elif pick < 0.82:
                veg += azo.shrub(x, z, r.uniform(0.9, 1.7), y, color=r.choice((azo.LEAF_OLIVE, azo.LEAF_MID, azo.LEAF_DARK)))
            else:
                veg += azo.palm_cheap(x, z, r.uniform(5.0, 7.0), y, seed=r.random() * 6.0)
            nveg += 1
    for x in np.arange(-110.0, 110.0, 13.0):                          # Palmen an der Nordstraße (Nordseite)
        z = 64.5 + r.uniform(-0.5, 0.5)
        veg += azo.palm_cheap(x + r.uniform(-1.5, 1.5), z, r.uniform(5.0, 6.5), AZ_GY, seed=r.random() * 6.0)
        nveg += 1
    az_emit("Hangbewuchs", veg)
    print("DIORAMA Küste: Hang, Pflanzen", nveg, "Gassen", len(lines))


def az_park():
    """Küstenpark auf den Rasenflächen zwischen Stadion, Parkplätzen und Straßen: lockere Haine aus Palmen, Schirmpinien, Zypressen und Büschen,
    Hecken entlang der Straßen, Blumenbeete am Eingang (nur Bild, außerhalb der Reichweite der Fahrzeuge). Dichte nach einem Rauschfeld: Haine und Lichtungen."""
    r = random.Random(909)
    veg, beds, hedge = [], [], []
    rects = list(AZ_LOTS.values()) + [AZ_BLVD, AZ_ROAD_N, AZ_ROAD_E, AZ_ROAD_W]

    def free(x, z, m):
        return not any(ra - m < x < rb + m and rc - m < z < rd + m for (ra, rb, rc, rd) in rects)
    cand = []
    for zz in np.arange(-29.0, 58.0, 4.0):
        for xx in np.arange(-76.0, 76.0, 4.0):
            cand.append((xx + r.uniform(-1.6, 1.6), zz + r.uniform(-1.6, 1.6)))
    P = np.array(cand)
    dd = dist_to_center(P)
    ins = inside(P)
    grove = az_vnoise(P[:, 0], P[:, 1], 17.0)
    n_tree = 0
    for k, (x, z) in enumerate(cand):
        if ins[k] or dd[k] < 23.5 or not free(x, z, 2.2) or z < -29.0:
            continue
        if abs(x) < 12.0 and z > 30.0:                               # Zugangsallee und Eingangsplatz bleiben offen
            continue
        if r.random() > (0.9 if grove[k] > 0.50 else 0.22):
            continue
        box_ = rect_corners(x, z, 1.0, 1.0, 0.0)
        if any(overlaps(box_, q) for q in placed):
            continue
        y = az_land_h(x, z)
        pick = r.random()
        if pick < 0.36:
            veg += azo.palm_cheap(x, z, r.uniform(5.0, 7.2), y, seed=r.random() * 6.0)
        elif pick < 0.60:
            veg += azo.stone_pine(x, z, r.uniform(6.0, 8.5), y)
        elif pick < 0.72:
            veg += azo.cypress(x, z, r.uniform(5.5, 8.0), y)
        else:
            veg += azo.shrub(x, z, r.uniform(0.9, 1.8), y, color=r.choice((azo.LEAF_OLIVE, azo.LEAF_MID, azo.LEAF_DARK)))
        placed.append(box_)
        n_tree += 1
    # Hecken: niedrige Streifen mit Lücken an der Innenseite der Straßen (zu den Rasenflächen hin)
    for (ra, rb, rc, rd, axis, edge) in ((AZ_ROAD_N[0], AZ_ROAD_N[1], AZ_ROAD_N[2], AZ_ROAD_N[3], "x", AZ_ROAD_N[2] - 0.9),
                                         (AZ_ROAD_E[0], AZ_ROAD_E[1], AZ_ROAD_E[2], AZ_ROAD_E[3], "z", AZ_ROAD_E[0] - 0.9),
                                         (AZ_ROAD_W[0], AZ_ROAD_W[1], AZ_ROAD_W[2], AZ_ROAD_W[3], "z", AZ_ROAD_W[1] + 0.9)):
        a0, a1 = (ra + 4.0, rb - 4.0) if axis == "x" else (rc + 4.0, rd - 4.0)
        t = a0
        while t < a1:
            ln = r.uniform(3.0, 6.5)
            if r.random() < 0.7:
                hx, hz = ((t + ln / 2, edge), (ln / 2, 0.35)) if axis == "x" else ((edge, t + ln / 2), (0.35, ln / 2))
                if free(hx[0], hx[1], 0.0) or axis == "z":
                    xa_, xb_, za_, zb_ = hx[0] - hz[0], hx[0] + hz[0], hx[1] - hz[1], hx[1] + hz[1]
                    if axis == "x" and any(ra_ - 0.5 < xb_ and xa_ < rb_ + 0.5 and rc_ - 0.5 < zb_ and za_ < rd_ + 0.5 for (ra_, rb_, rc_, rd_) in list(AZ_LOTS.values()) + [AZ_BLVD]):
                        t += ln + r.uniform(1.0, 3.0)
                        continue
                    y0 = AZ_GY
                    azp.boxd(hedge, xa_, xb_, za_, zb_, y0, y0 + 0.95, r.choice((azo.LEAF_DARK, azo.LEAF_MID)), ao=0.9, top=1.2)
            t += ln + r.uniform(1.0, 3.0)
    # Blumenbeete beiderseits der Zugangsallee (vor dem Stadionring) und Büsche an den Eckpunkten
    for (bx, bz, br) in ((-15.5, 30.5, 1.6), (15.5, 30.5, 1.6), (-24.0, 26.0, 1.3), (24.0, 26.0, 1.3), (-15.5, 45.5, 1.4), (15.5, 45.5, 1.4)):
        if not any(overlaps(rect_corners(bx, bz, br + 0.3, br + 0.3, 0.0), q) for q in placed) and dist_to_center(np.array([[bx, bz]]))[0] > 21.0:
            beds += azo.flower_bed(bx, bz, br, AZ_GY)
            placed.append(rect_corners(bx, bz, br + 0.3, br + 0.3, 0.0))
    az_emit("Park", veg)
    az_emit("Hecken", hedge)
    az_emit("Parkbeete", beds)
    print("DIORAMA Küste: Park, Bäume und Büsche", n_tree)


def az_lot(xa, xb, za, zb, along, rng_s, cars, asphalt, marks, y_a, fill=0.62, depth=4.6, stall=2.6):
    """Parkplatz: Asphalt, zwei Stellplatzbänder an den Rändern mit Fahrgasse dazwischen, Markierungen und Autos (along = Fahrzeuglängsachse x oder z)."""
    asphalt += az_rect(xa, xb, za, zb, y_a, "asphalt_str", tile=6.0)
    count = 0
    if along == "x":
        n = max(1, int(round((zb - za) / stall)))
        pitch = (zb - za) / n
        bands = [(xa, xa + depth), (xb - depth, xb)]
        for (sa, sb) in bands:
            for k in range(n + 1):
                zl = za + k * pitch
                marks += az_rect(sa, sb, zl - 0.05, zl + 0.05, y_a + 0.012, "linie", tile=1.0)
                if k < n and rng_s.random() < fill:
                    heading = rng_s.choice((-1.0, 1.0))
                    cx, cz = (sa + sb) / 2 + rng_s.uniform(-0.15, 0.15), zl + pitch / 2
                    parts_c, (cl, cw) = kit_car.random_car(rng_s, cx, cz, heading, 0.0, base_y=y_a)
                    cars += parts_c
                    collide_rect(cx, cz, heading, 0.0, cl / 2, cw / 2, 1.5, "auto")
                    count += 1
    else:
        n = max(1, int(round((xb - xa) / stall)))
        pitch = (xb - xa) / n
        bands = [(za, za + depth), (zb - depth, zb)]
        for (sa, sb) in bands:
            for k in range(n + 1):
                xl = xa + k * pitch
                marks += az_rect(xl - 0.05, xl + 0.05, sa, sb, y_a + 0.012, "linie", tile=1.0)
                if k < n and rng_s.random() < fill:
                    heading = rng_s.choice((-1.0, 1.0))
                    cx, cz = xl + pitch / 2, (sa + sb) / 2 + rng_s.uniform(-0.15, 0.15)
                    parts_c, (cl, cw) = kit_car.random_car(rng_s, cx, cz, 0.0, heading, base_y=y_a)
                    cars += parts_c
                    collide_rect(cx, cz, 0.0, heading, cw / 2, cl / 2, 1.5, "auto")
                    count += 1
    return count


def az_volleyball(rng_s):
    """Beachvolleyball: Spielfeld aus Linien auf dem Sand, Netz mit Pfosten und Antennen, Ball; zwei Spielerinnen und zwei Spieler."""
    vb = AZ_VB
    cx, cz = vb["x"], vb["z"]
    y = az_land_h(cx, cz)
    hx, hz = vb["hx"], vb["hz"]
    vm, vp = [], []
    for (xa, xb, za, zb) in ((cx - hx, cx + hx, cz - hz, cz - hz + 0.1), (cx - hx, cx + hx, cz + hz - 0.1, cz + hz),
                             (cx - hx, cx - hx + 0.1, cz - hz, cz + hz), (cx + hx - 0.1, cx + hx, cz - hz, cz + hz)):
        vm += az_rect(xa, xb, za, zb, y + 0.02, "linie", tile=1.0)
    vp += azo.volley_net(cx, cz, 0.0, 1.0, length=hz * 2 + 0.7, y_base=y)
    vp += azo.beach_ball(cx + 3.2, cz + 0.9, y + 0.03)
    for (dx, dz, face, shirt) in ((-3.4, -1.0, (1.0, 0.2), azp.CORAL), (-4.8, 1.6, (1.0, -0.3), azp.AZURE), (3.6, 0.8, (-1.0, 0.1), azp.WHITE), (5.0, -1.6, (-1.0, 0.4), azp.TEAL)):
        py = az_land_h(cx + dx, cz + dz)
        vp += azo.person(cx + dx, cz + dz, face[0], face[1], shirt, azp.NAVY, py)
    az_emit("Volleyball", vp)
    az_emit("Volleyballfeld", vm)
    for sgn in (-1, 1):
        collide_circle(cx, cz + sgn * (hz + 0.2), 0.08, 2.55, "mast")
    placed.append(rect_corners(cx, cz, hx + 1.0, hz + 1.0, 0.0))


def az_beach_life(rng_s):
    """Leben am Strand: Tische und Stühle vor dem Café, Brettständer, Badegäste auf Handtüchern und beim Spaziergang."""
    parts = []
    for (tx, tz, sd) in ((31.4, -37.0, 0.3), (34.6, -38.6, 1.1), (40.5, -37.2, 2.0)):
        ty = az_land_h(tx, tz)
        parts += azo.table_set(tx, tz, ty, 4, sd)
        collide_circle(tx, tz, 0.9, 0.9, "bank")
    parts += azo.surf_rack(26.5, -37.4, 1.0, 0.0, az_land_h(26.5, -37.4))
    cols = [azp.CORAL, azp.AZURE, azp.WHITE, azp.TEAL, azp.YELLOW, azp.RED]
    for k, (px, pz) in enumerate(((-24.0, -35.0), (-21.5, -37.4), (-30.5, -37.0), (2.8, -35.4), (4.0, -37.6), (9.5, -35.0), (14.0, -37.4), (22.0, -35.6), (-33.0, -36.4), (29.5, -34.5))):
        py = az_land_h(px, pz)
        parts += azo.person(px, pz, math.cos(k * 1.7), math.sin(k * 1.7), cols[k % len(cols)], azp.NAVY, py + 0.0)
    az_emit("Strandleben", parts)


def az_cars_along(rng_s, xa, za, xb, zb, cars, base_y, fill=0.55):
    """Längs parkende Autos auf der Strecke von (xa, za) nach (xb, zb) (nur Bild, keine Hindernisse: liegt außerhalb der Reichweite der Fahrzeuge)."""
    L = math.hypot(xb - xa, zb - za)
    ux, uz = (xb - xa) / L, (zb - za) / L
    s, n = rng_s.uniform(0.5, 3.0), 0
    while s < L - 3.0:
        heading = rng_s.choice((-1.0, 1.0))
        cx, cz = xa + ux * s, za + uz * s
        y = float(base_y(cx, cz)) if callable(base_y) else float(base_y)
        parts_c, (cl, cw) = kit_car.random_car(rng_s, cx, cz, ux * heading, uz * heading, base_y=y)
        if rng_s.random() < fill:
            cars += parts_c
            n += 1
        s += cl + rng_s.uniform(0.6, 3.5)
    return n


def az_road_marks(marks, xa, xb, za, zb, along, y, dash=3.0, gap=3.5):
    """Mittellinie (gestrichelt) und Randlinien einer Straße; along = Längsrichtung (x oder z)."""
    if along == "x":
        zc = (za + zb) / 2
        marks += az_rect(xa, xb, za + 0.35, za + 0.47, y, "linie", tile=1.0)
        marks += az_rect(xa, xb, zb - 0.47, zb - 0.35, y, "linie", tile=1.0)
        x = xa + 1.0
        while x + dash < xb:
            marks += az_rect(x, x + dash, zc - 0.07, zc + 0.07, y, "linie", tile=1.0)
            x += dash + gap
    else:
        xc = (xa + xb) / 2
        marks += az_rect(xa + 0.35, xa + 0.47, za, zb, y, "linie", tile=1.0)
        marks += az_rect(xb - 0.47, xb - 0.35, za, zb, y, "linie", tile=1.0)
        z = za + 1.0
        while z + dash < zb:
            marks += az_rect(xc - 0.07, xc + 0.07, z, z + dash, y, "linie", tile=1.0)
            z += dash + gap


def az_parking(rng_s):
    """Parkplätze an den Enden (Ost und West) mit Autos, Laternen, Palmenreihen; Straßen ringsum; Wiese mit Palmengruppen; Nordbereich: az_north."""
    cars, asphalt, marks = [], [], []
    y_a = AZ_GY + 0.04
    count = 0
    for side in (1, -1):
        xa, xb = AZ_LOTS["E" if side > 0 else "W"][:2]
        count += az_lot(xa, xb, -14.0, 14.0, "x", rng_s, cars, asphalt, marks, y_a)
        for z_l in (-12.0, 0.0, 12.0):
            lamps.append((Vector(((xa + xb) / 2, z_l)), Vector(((xa + xb) / 2 + 3.0 * side, z_l))))
            placed.append(rect_corners((xa + xb) / 2, z_l, 0.4, 0.4, 0.0))
        for z_p in (-15.5, -9.0, 9.0, 15.5):
            az_put("kueste_palme_lo", xa - 1.4 if side > 0 else xb + 1.4, z_p, rng_s.uniform(0, 6.28), rng_s.uniform(4.4, 5.4), "Prop_Palme", trunk=0.35, clearance=HW + 3.0)
        # Zufahrt vom Parkplatz zur Seitenstraße
        fx0, fx1 = (xb, 67.0) if side > 0 else (-67.0, xa)
        asphalt += az_rect(fx0, fx1, -2.5, 2.5, y_a, "asphalt_str", tile=6.0)
        # Seitenstraße (Nord-Süd) mit Längsparkern auf der Außenseite
        ra, rb, rc, rd = AZ_ROAD_E if side > 0 else AZ_ROAD_W
        asphalt += az_rect(ra, rb, rc, rd, y_a, "asphalt_str", tile=6.0)
        az_road_marks(marks, ra, rb, rc, rd, "z", y_a + 0.012)
        xcar = rb - 1.15 if side > 0 else ra + 1.15
        count += az_cars_along(rng_s, xcar, rc + 2.0, xcar, rd - 3.0, cars, y_a, fill=0.4)
    az_north(rng_s, cars, asphalt, marks, y_a)
    az_emit("Parkplatz", asphalt, ground=True)
    az_emit("Parkmarkierung", marks)
    az_emit("Auto", cars)
    # Wiese zwischen Kurvenende und Strand: Palmengruppen (Ost und West)
    n_pg = 0
    for side in (1, -1):
        n_side = 0
        for k in range(40):
            px = side * rng_s.uniform(37.0, 56.0)
            pz = rng_s.uniform(-30.0, -14.0)
            if abs(px) < 43.0 and pz > -22.0:
                continue
            if az_put("kueste_palme_lo", px, pz, rng_s.uniform(0, 6.28), rng_s.uniform(4.0, 5.4), "Prop_Palme", trunk=0.35, clearance=HW + 4.0):
                n_pg += 1
                n_side += 1
            if n_side >= 7:
                break
    print("DIORAMA Küste: geparkte Autos", count, "Palmen auf der Wiese", n_pg)


def az_north(rng_s, cars, asphalt, marks, y_a):
    """Nordbereich hinter der Haupttribüne: Zugangsallee mit Eingangstor, Kassenhäuschen, Fahnen und Palmen, zwei Parkplätze, Nordstraße mit Autos."""
    GZ = 34.5                                                       # Lage des Eingangstors (Mitte)
    # Allee: Sandplatten vom Ring (z = 32) bis zur Nordstraße
    ba, bb, bc, bd = AZ_BLVD
    asphalt += az_rect(ba, bb, bc, bd, AZ_GY + 0.03, "platten", tile=4.0)
    count = az_lot(AZ_LOTS["NW"][0], AZ_LOTS["NW"][1], AZ_LOTS["NW"][2], AZ_LOTS["NW"][3], "z", rng_s, cars, asphalt, marks, y_a)
    count += az_lot(AZ_LOTS["NE"][0], AZ_LOTS["NE"][1], AZ_LOTS["NE"][2], AZ_LOTS["NE"][3], "z", rng_s, cars, asphalt, marks, y_a)
    for x_l in (-26.0, -14.0, 14.0, 26.0):
        lamps.append((Vector((x_l, 48.5)), Vector((x_l, 44.0))))
        placed.append(rect_corners(x_l, 48.5, 0.4, 0.4, 0.0))
    # Nordstraße
    ra, rb, rc, rd = AZ_ROAD_N
    asphalt += az_rect(ra, rb, rc, rd, y_a, "asphalt_str", tile=6.0)
    az_road_marks(marks, ra, rb, rc, rd, "x", y_a + 0.012)
    count += az_cars_along(rng_s, ra + 4.0, rc + 1.3, rb - 4.0, rc + 1.3, cars, y_a, fill=0.38)
    count += az_cars_along(rng_s, ra + 4.0, rd - 1.3, rb - 4.0, rd - 1.3, cars, y_a, fill=0.38)
    for x_l in (-60.0, -30.0, 0.0, 30.0, 60.0):                     # Straßenlaternen an der Nordstraße (Südseite)
        lamps.append((Vector((x_l, rc - 0.8)), Vector((x_l, rc + 2.5))))
        placed.append(rect_corners(x_l, rc - 0.8, 0.4, 0.4, 0.0))
    # Eingangstor über der Allee
    gate = []
    gx = 5.4
    for sgn in (-1, 1):
        azp.boxd(gate, sgn * gx - 0.45, sgn * gx + 0.45, GZ - 0.5, GZ + 0.5, AZ_GY + 0.03, AZ_GY + 5.4, azp.OFFWHITE)
        azp.boxd(gate, sgn * gx - 0.5, sgn * gx + 0.5, GZ - 0.55, GZ + 0.55, AZ_GY + 5.4, AZ_GY + 5.5, azp.AZURE, ao=1.0)
        collide_rect(sgn * gx, GZ, 1.0, 0.0, 0.45, 0.5, 5.4, "mauer")
    azp.boxd(gate, -gx - 0.5, gx + 0.5, GZ - 0.45, GZ + 0.45, AZ_GY + 4.3, AZ_GY + 5.5, azp.AZURE)
    az_sign(gate, "haupt", 0.0, GZ + 0.45, (0.0, 1.0), 9.0, AZ_GY + 4.45, 1.1)
    az_sign(gate, "willkommen", 0.0, GZ - 0.45, (0.0, -1.0), 5.2, AZ_GY + 4.35, 1.2)
    az_emit("Eingangstor", gate)
    # Kassenhäuschen beiderseits der Allee, Fahnenmasten entlang der Allee
    bo = []
    for sgn in (-1, 1):
        bo += azo.ticket_booth(sgn * 6.4, 38.6, 0.0, 1.0, AZ_GY + 0.03)
        collide_rect(sgn * 6.4, 38.6, 1.0, 0.0, 1.0, 1.2, 2.6, "mauer")
    cols = [azp.AZURE, azp.WHITE, azp.CORAL]
    for k in range(8):
        for sgn in (-1, 1):
            bo += azo.flag_pole(sgn * 7.0, 41.5 + k * 1.9, -sgn, 0.0, 5.2, cols[(k + (sgn > 0)) % 3], AZ_GY + 0.03)
    for sgn in (-1, 1):
        for zb_ in (44.0, 50.0):
            bo += azo.bench(sgn * 6.0, zb_, -sgn, 0.0, AZ_GY + 0.04)
    az_emit("Eingang", bo)
    for sgn in (-1, 1):                                             # Palmenreihe zu beiden Seiten der Allee, Nordrand der Parkplätze
        for z_p in (36.0, 43.0, 51.0):
            az_put("kueste_palme_lo", sgn * 10.4, z_p, rng_s.uniform(0, 6.28), rng_s.uniform(4.4, 5.4), "Prop_Palme", trunk=0.35, clearance=HW + 3.0, kind=None)
    print("DIORAMA Küste: Nordbereich, Autos", count)


