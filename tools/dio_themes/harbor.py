"""Themenmodul "harbor": Diorama für Harbour Run (Containerhafen am Kai) und Drift Arena (Industriegelände am Hafen).

Wird von tools/diorama.py in dessen Globals ausgeführt (siehe docs/dioramen/README.md); beide Strecken teilen sich das Modul
(Verzweigung über TRACK_ID). Straße: "runtime" (das Spiel baut Fahrbahn, Randsteine, Rampe, Lücke und Abkürzung selbst), das Diorama
liefert Boden, Wasser, Kai, Container, Hallen, Fahrzeuge, Markierungen und Zubehör.

Alle Namen des Moduls beginnen mit hb_ / HB_, weil das Modul in die Globals des Kerns läuft (keine Namenskollisionen).
Beschreibung der Entscheidungen: docs/dioramen/harbor.md und docs/dioramen/arena.md.
"""
import os

IS_ARENA = TRACK_ID == "arena"
THEME_CFG = {
    "road": "runtime",
    "margin": 34.0,
    "baked": ["lamp"],                    # Laternen der Streckendatei entfallen; eigene (lamps.append) stehen außerhalb des Fahrschlauchs
    "vertex_colors": "ACTIVE",
    "ground_set": {"grass": "res://assets/dio/harbor/beton", "sand": "res://assets/dio/harbor/asphalt", "dirt": "res://assets/dio/harbor/verschleiss"},
    "ground_scales": {"grass": 8.0, "sand": 6.0, "dirt": 8.0},
    "ground_tints": {"grass": [0.74, 0.74, 0.73], "sand": [1.0, 1.0, 1.0], "dirt": [1.0, 1.0, 1.0]},
    "water_nodes": ["Hafenwasser"],
    "water": {"lagoon": [0.05, 0.17, 0.2], "open": [0.07, 0.25, 0.3], "foam": [0.80, 0.86, 0.86]},
}

if IS_ARENA:
    THEME_CFG["baked"] = ["lamp", "floodlight"]       # Flutlichter baut das Diorama selbst (Masten mit echten Lichtquellen, hb_build_masts)
    THEME_CFG["ground_tints"] = {"grass": [0.62, 0.62, 0.61], "sand": [1.0, 1.0, 1.0], "dirt": [1.0, 1.0, 1.0]}     # große Betonfläche unter Flutlicht: dunkler
HB_LAMP_MODEL = "hafen_laterne"
HB_QUAY_Z = float(data.get("quay_z", 1e9))        # Kaikante (Land bei z > quay_z, Meer dahinter); nur Harbour Run
HB_WATER_Y = -2.3                                  # Meeresfläche des Spiels (Kasten unter dem Diorama)
HB_TEX_DIR = os.path.normpath(os.path.join(os.path.dirname(THEME_FILE), "..", "..", "game", "assets", "dio", "harbor", "src"))
HB_NOISE = np.random.default_rng(17).random((64, 64))     # gleiches Rauschgitter wie value_noise im Kern
HB = {}                                            # Zustand (wird in theme_materials() gefüllt)


def hb_lin(c):
    """sRGB (sichtbar) -> linear (Blender-/glTF-Farbe, Vertexfarbe)."""
    return tuple(max(0.0, v) ** 2.2 for v in c)


def hb_smooth(x, lo, hi):
    t = np.clip((x - lo) / (hi - lo), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def hb_vnoise(X, Z, scale, ox=0.0, oz=0.0):
    """Wertrauschen (wie value_noise des Kerns) für Zahlenfelder."""
    u = (np.asarray(X, float) + ox) / scale
    v = (np.asarray(Z, float) + oz) / scale
    i0, j0 = np.floor(u).astype(int), np.floor(v).astype(int)
    fu, fv = u - i0, v - j0
    fu, fv = fu * fu * (3 - 2 * fu), fv * fv * (3 - 2 * fv)
    g = HB_NOISE
    a = g[j0 % 64, i0 % 64] * (1 - fu) + g[j0 % 64, (i0 + 1) % 64] * fu
    b = g[(j0 + 1) % 64, i0 % 64] * (1 - fu) + g[(j0 + 1) % 64, (i0 + 1) % 64] * fu
    return a * (1 - fv) + b * fv


# ---------------------------------------------------------------- Spielebene: Mittellinie und Fahrschlauch wie in track.gd
class HbTrack:
    """Mittellinie der Spielebene (Catmull-Rom wie track.gd, 0,5-m-Abtastung), Breitenprofil, Flugzonen und Abkürzungen. Damit lässt sich
    für jedes Hindernis dieselbe Abstandsprüfung rechnen wie in tests/test_diorama.gd (Halbbreite + Abstand, in Rampen-/Lückenzonen mehr)."""

    def __init__(self):
        ctl = np.array(data["points"], float)
        n = len(ctl)
        fine = []
        for i in range(n):
            p0, p1, p2, p3 = ctl[(i - 1) % n], ctl[i], ctl[(i + 1) % n], ctl[(i + 2) % n]
            sub = max(2, int(math.ceil(np.linalg.norm(p2 - p1) / 0.25)))
            t = (np.arange(sub) / sub)[:, None]
            fine.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t ** 2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
        fine = np.vstack(fine)
        nxt = np.roll(fine, -1, axis=0)
        cum = np.concatenate([[0.0], np.cumsum(np.linalg.norm(nxt - fine, axis=1))])
        self.length = float(cum[-1])
        self.count = max(16, int(round(self.length / 0.5)))
        d = self.length * np.arange(self.count) / self.count
        j = np.clip(np.searchsorted(cum, d, side="left") - 1, 0, len(fine) - 1)
        f = np.clip((d - cum[j]) / np.maximum(cum[j + 1] - cum[j], 1e-6), 0.0, 1.0)
        self.P = fine[j] + (fine[(j + 1) % len(fine)] - fine[j]) * f[:, None]
        t = np.roll(self.P, -1, axis=0) - np.roll(self.P, 1, axis=0)
        self.T = t / np.linalg.norm(t, axis=1)[:, None]
        self.Lft = np.stack([-self.T[:, 1], self.T[:, 0]], 1)
        self.S = np.arange(self.count) / self.count
        self.widths = data.get("widths", [])
        self.HW = np.array([self.hw(s) for s in self.S])
        meter = 1.0 / self.length
        zones = []
        for r in data.get("ramps", []):
            zones.append((float(r["s"]), float(r["s"]) + float(r["length"]) * meter + 3.0 * meter, 1.0))
        for g in data.get("gaps", []):
            zones.append((float(g["from"]) - 6.0 * meter, float(g["to"]) + 25.0 * meter, 1.0))
        for lp in data.get("loops", []):
            zones.append((float(lp["s"]) - 20.0 * meter, float(lp["s"]) + 40.0 * meter, 0.5))
        self.zones = zones
        self.RAD = self.HW.copy()
        for i, s in enumerate(self.S):
            for z in zones:
                if (s - z[0]) % 1.0 <= (z[1] - z[0]) % 1.0:
                    self.RAD[i] += z[2]
                    break
        self.shortcuts = []
        for sc in data.get("shortcuts", []):
            path = np.array(sc["path"], float)
            pts = []
            for a, b in zip(path[:-1], path[1:]):
                m = max(1, int(math.ceil(np.linalg.norm(b - a))))
                pts += [a + (b - a) * k / m for k in range(m + 1)]
            self.shortcuts.append((np.array(pts), float(sc.get("width", 3.0)) * 0.5))

    def hw(self, s):
        if not self.widths:
            return float(HW)
        ws = self.widths
        xs = [float(w[0]) for w in ws] + [float(ws[0][0]) + 1.0]
        ys = [float(w[1]) for w in ws] + [float(ws[0][1])]
        s = s % 1.0
        if s < xs[0]:
            s += 1.0
        return float(np.interp(s, xs, ys))

    def at(self, s):
        """Punkt und Tangente bei Streckenanteil s."""
        f = (s % 1.0) * self.count
        i = int(f) % self.count
        k = f - int(f)
        p = self.P[i] + (self.P[(i + 1) % self.count] - self.P[i]) * k
        t = self.T[i] + (self.T[(i + 1) % self.count] - self.T[i]) * k
        return p, t / np.linalg.norm(t)

    def edge_dist(self, X, Z):
        """Abstand zum Rand der Fahrbahn (Hauptstrecke, Mittellinie minus Halbbreite) für Zahlenfelder; negativ = auf der Fahrbahn."""
        Q = np.stack([np.ravel(X), np.ravel(Z)], 1)
        out = np.empty(len(Q))
        for k in range(0, len(Q), 3000):
            q = Q[k:k + 3000, None, :]
            d = np.sqrt(((q - self.P[None, :, :]) ** 2).sum(2)) - self.HW[None, :]
            out[k:k + 3000] = d.min(1)
        return out.reshape(np.shape(X))

    def near_s(self, X, Z):
        """Streckenanteil des nächsten Mittellinienpunkts (für Zahlenfelder)."""
        Q = np.stack([np.ravel(X), np.ravel(Z)], 1)
        out = np.empty(len(Q))
        for k in range(0, len(Q), 3000):
            q = Q[k:k + 3000, None, :]
            d = ((q - self.P[None, :, :]) ** 2).sum(2)
            out[k:k + 3000] = self.S[d.argmin(1)]
        return out.reshape(np.shape(X))

    def rect_slack(self, cx, cz, ux, uz, hx, hz):
        """Kleinster Abstand zwischen Fahrschlauchrand (Halbbreite + Zonenzuschlag) und Rechteck; wie corridor_offenders im Test."""
        rel = self.P[::2] - np.array([cx, cz])
        a = rel @ np.array([ux, uz])
        b = rel @ np.array([-uz, ux])
        dist = np.hypot(a - np.clip(a, -hx, hx), b - np.clip(b, -hz, hz))
        slack = float((dist - self.RAD[::2]).min())
        for pts, half in self.shortcuts:
            rel = pts - np.array([cx, cz])
            a = rel @ np.array([ux, uz])
            b = rel @ np.array([-uz, ux])
            slack = min(slack, float((np.hypot(a - np.clip(a, -hx, hx), b - np.clip(b, -hz, hz)) - half).min()))
        return slack

    def circle_slack(self, cx, cz, r):
        d = np.hypot(self.P[::2, 0] - cx, self.P[::2, 1] - cz) - r
        slack = float((d - self.RAD[::2]).min())
        for pts, half in self.shortcuts:
            slack = min(slack, float((np.hypot(pts[:, 0] - cx, pts[:, 1] - cz) - r - half).min()))
        return slack


# ---------------------------------------------------------------- Belegung und Hindernisse (Rechtecke in Spielkoordinaten)
def hb_poly(cx, cz, ux, uz, hx, hz, pad=0.0):
    vx, vz = -uz, ux
    return [(cx + ux * a + vx * b, cz + uz * a + vz * b) for a, b in ((-hx - pad, -hz - pad), (hx + pad, -hz - pad), (hx + pad, hz + pad), (-hx - pad, hz + pad))]


def hb_overlap(poly_a, poly_b):
    """Trennachsentest zweier konvexer Vierecke (wie overlaps im Kern, steht aber schon in theme_materials zur Verfügung)."""
    for poly in (poly_a, poly_b):
        n = len(poly)
        for i in range(n):
            ax, az = poly[i]
            bx, bz = poly[(i + 1) % n]
            nx, nz = az - bz, bx - ax
            pa = [nx * x + nz * z for x, z in poly_a]
            pb = [nx * x + nz * z for x, z in poly_b]
            if max(pa) <= min(pb) or max(pb) <= min(pa):
                return False
    return True


def hb_free(cx, cz, ux, uz, hx, hz, margin=1.0, pad=0.0, check_track=True):
    """Ist die Fläche frei von Belegtem und hält sie den Fahrschlauch um margin Meter frei?"""
    r = math.hypot(hx, hz) + pad
    pa = hb_poly(cx, cz, ux, uz, hx, hz, pad)
    for (ox, oz, ou, ov, ohx, ohz) in HB["occ"]:
        rr = r + math.hypot(ohx, ohz)
        if abs(ox - cx) > rr or abs(oz - cz) > rr:
            continue
        if hb_overlap(pa, hb_poly(ox, oz, ou, ov, ohx, ohz)):
            return False
    if check_track and HB["track"].rect_slack(cx, cz, ux, uz, hx, hz) < margin:
        return False
    return True


def hb_occupy(cx, cz, ux, uz, hx, hz):
    HB["occ"].append((cx, cz, ux, uz, hx, hz))


def hb_solid(cx, cz, ux, uz, hx, hz, height, kind="mauer", margin=1.0, pad=0.15):
    """Fester Körper: prüfen, belegen und als Hindernis der Spielebene vormerken (hb_commit_colliders schreibt sie später in den Kern).
    Rückgabe: True, wenn gesetzt."""
    n = math.hypot(ux, uz) or 1.0
    ux, uz = ux / n, uz / n
    if not hb_free(cx, cz, ux, uz, hx, hz, margin, pad):
        return False
    hb_occupy(cx, cz, ux, uz, hx, hz)
    HB["solids"].append((cx, cz, ux, uz, hx, hz, height, kind))
    return True


def hb_solid_force(cx, cz, ux, uz, hx, hz, height, kind="mauer", margin=1.0):
    """Wie hb_solid, aber ohne Überschneidungsprüfung (Bauteile innerhalb bereits belegter Flächen: Kranbahn, Becken); nur der Fahrschlauch zählt."""
    n = math.hypot(ux, uz) or 1.0
    ux, uz = ux / n, uz / n
    if HB["track"].rect_slack(cx, cz, ux, uz, hx, hz) < margin:
        return False
    HB["solids"].append((cx, cz, ux, uz, hx, hz, height, kind))
    return True


def hb_circle_solid(cx, cz, r, height, kind="mauer", margin=1.0):
    if not hb_free(cx, cz, 1.0, 0.0, r, r, margin, 0.05):
        return False
    hb_occupy(cx, cz, 1.0, 0.0, r, r)
    HB["circles"].append((cx, cz, r, height, kind))
    return True


def hb_commit_colliders():
    """Alle vorgemerkten festen Körper als Hindernisse der Spielebene eintragen (collide_rect / collide_circle des Kerns)."""
    for (cx, cz, ux, uz, hx, hz, height, kind) in HB["solids"]:
        collide_rect(cx, cz, ux, uz, hx, hz, height, kind)
    for (cx, cz, r, height, kind) in HB["circles"]:
        collide_circle(cx, cz, r, height, kind)
    print("DIORAMA Hindernisse des Themas:", len(HB["solids"]), "Rechtecke,", len(HB["circles"]), "Kreise")


def hb_occupy_props():
    """Laufzeit-Bausteine der Streckendatei als belegte Flächen eintragen (Container, Fässer, Paletten, Gabelstapler)."""
    sizes = {"hafen_poller": 0.5, "hafen_faesser": 1.3, "hafen_paletten": 1.2, "hafen_gabelstapler": 1.8, "drift_zuschauer_container": 3.2}
    for p in data["props"]:
        if p.get("type") != "ai":
            continue
        x, z, rot = float(p["x"]), float(p["z"]), math.radians(float(p.get("rot", 0.0)))
        u = (math.cos(rot), math.sin(rot))
        model_ = str(p.get("model", ""))
        if float(p.get("y", 0.0)) < -1.0 or model_ == "hafen_kran":
            continue                                                 # Schiffsrumpf im Wasser; Kräne: eigene Fläche (Kranbahn)
        if "w" in p and "d" in p:
            hb_occupy(x, z, u[0], u[1], float(p["w"]) / 2 + 0.3, float(p["d"]) / 2 + 0.3)
        elif model_ in sizes:
            r = sizes[model_]
            hb_occupy(x, z, 1.0, 0.0, r, r)
    for p in data["props"]:
        if p.get("type") in (("lamp",) if IS_ARENA else ("floodlight", "lamp")):          # Arena: Flutlichter entfallen (baked), die Masten plant hb_plan_arena_extras
            hb_occupy(float(p["x"]), float(p["z"]), 1.0, 0.0, 1.0, 1.0)


# ---------------------------------------------------------------- Teile-Helfer (Flächenlisten für mesh_object)
def hb_quad(out, key, pts, uvs, facing=None, cols=None):
    out.append((key, pts, uvs, facing, cols) if cols is not None else ((key, pts, uvs, facing) if facing is not None else (key, pts, uvs)))


def hb_cuboid(out, cx, cz, ux, uz, hx, hz, y0, y1, key_top, key_side=None, key_end=None, col=None, shade=(0.62, 1.0), tile=2.0, bottom_fade=True, top_col=None):
    """Quader um (cx, cz): u = Längsrichtung (Halblänge hx), Quer-Halbmaß hz. Seiten tragen eine Vertexfarbe mit Verlauf (unten dunkler),
    UV in Meter / tile. Längsseiten: key_side, Stirnseiten: key_end (Vorgabe key_side). Ohne Boden."""
    key_side = key_side or key_top
    key_end = key_end or key_side
    vx, vz = -uz, ux
    col = col or (1.0, 1.0, 1.0)
    lo, hi = (shade if bottom_fade else (1.0, 1.0))

    def pt(a, b, y):
        return (cx + ux * a + vx * b, cz + uz * a + vz * b, y)
    h = y1 - y0
    for (a0, b0, a1, b1, key, out_n, ln) in ((-hx, -hz, hx, -hz, key_side, (-vx, -vz), 2 * hx), (hx, hz, -hx, hz, key_side, (vx, vz), 2 * hx),
                                              (hx, -hz, hx, hz, key_end, (ux, uz), 2 * hz), (-hx, hz, -hx, -hz, key_end, (-ux, -uz), 2 * hz)):
        c0 = tuple(v * lo for v in col)
        c1 = tuple(v * hi for v in col)
        hb_quad(out, key, [pt(a0, b0, y0), pt(a1, b1, y0), pt(a1, b1, y1), pt(a0, b0, y1)],
                [(0, 0), (ln / tile, 0), (ln / tile, h / tile), (0, h / tile)], out_n, [c0, c0, c1, c1])
    tc = top_col or tuple(v * 1.05 for v in col)
    hb_quad(out, key_top, [pt(-hx, -hz, y1), pt(hx, -hz, y1), pt(hx, hz, y1), pt(-hx, hz, y1)],
            [(-hx / tile, -hz / tile), (hx / tile, -hz / tile), (hx / tile, hz / tile), (-hx / tile, hz / tile)], None, [tc] * 4)


def hb_prism(out, cx, cz, r, y0, y1, key, col=(1, 1, 1), sides=8, r_top=None, tile=2.0, cap_key=None, cap_col=None, shade=(0.8, 1.0)):
    """Zylinder / Kegelstumpf mit Vertexfarbe (Tanks, Fässer, Reifen, Pfosten)."""
    r_top = r if r_top is None else r_top
    ring0 = [(cx + r * math.cos(2 * math.pi * k / sides), cz + r * math.sin(2 * math.pi * k / sides)) for k in range(sides)]
    ring1 = [(cx + r_top * math.cos(2 * math.pi * k / sides), cz + r_top * math.sin(2 * math.pi * k / sides)) for k in range(sides)]
    for k in range(sides):
        j = (k + 1) % sides
        mid = ((ring0[k][0] + ring0[j][0]) / 2 - cx, (ring0[k][1] + ring0[j][1]) / 2 - cz)
        shade_k = 0.9 + 0.1 * math.cos(2 * math.pi * (k + 0.5) / sides)
        c0 = tuple(v * shade[0] * shade_k for v in col)
        c1 = tuple(v * shade[1] * shade_k for v in col)
        w = math.hypot(ring0[j][0] - ring0[k][0], ring0[j][1] - ring0[k][1])
        hb_quad(out, key, [(ring0[k][0], ring0[k][1], y0), (ring0[j][0], ring0[j][1], y0), (ring1[j][0], ring1[j][1], y1), (ring1[k][0], ring1[k][1], y1)],
                [(0, 0), (w / tile, 0), (w / tile, (y1 - y0) / tile), (0, (y1 - y0) / tile)], mid, [c0, c0, c1, c1])
    cc = cap_col or tuple(v * 1.05 for v in col)
    hb_quad(out, cap_key or key, [(x, z, y1) for x, z in ring1], [(0.5 + 0.5 * math.cos(2 * math.pi * k / sides), 0.5 + 0.5 * math.sin(2 * math.pi * k / sides)) for k in range(sides)],
            None, [cc] * sides)


def hb_strip(out, key, x_a, z_a, x_b, z_b, width, y, col=None, tile=1.0, v0=0.0):
    """Flaches Band von (x_a, z_a) nach (x_b, z_b) mit Breite width auf Höhe y."""
    dx, dz = x_b - x_a, z_b - z_a
    ln = math.hypot(dx, dz)
    if ln < 1e-6:
        return
    nx, nz = -dz / ln * width / 2, dx / ln * width / 2
    pts = [(x_a - nx, z_a - nz, y), (x_b - nx, z_b - nz, y), (x_b + nx, z_b + nz, y), (x_a + nx, z_a + nz, y)]
    hb_quad(out, key, pts, [(0, 0), (ln / tile, 0), (ln / tile, 1), (0, 1)], None, [col or (1, 1, 1)] * 4 if col else None)


def hb_rect_flat(out, key, x_a, z_a, x_b, z_b, y, col=None, tile=2.0):
    """Waagerechtes Rechteck achsenparallel."""
    pts = [(x_a, z_a, y), (x_b, z_a, y), (x_b, z_b, y), (x_a, z_b, y)]
    hb_quad(out, key, pts, [(a / tile, b / tile) for a, b, _ in pts], None, [col] * 4 if col else None)


# ---------------------------------------------------------------- Boden: Gewichte für den Boden-Shader (R Helligkeit der Platten, G Asphalt, B Verschleiß)
def hb_fields(X, Z):
    """Zahlenfelder (R, G, B) der Vertexfarbe. Der Boden-Shader (ground_blend.gdshader) mischt Beton (Platten), Asphalt und Verschleiß
    (dunkel, ölig, Reifenabrieb); Übergänge sind weich, weil die Gewichte über ein Meter-Netz laufen und der Shader sie mit dem Rauschen
    der Texturen aufbricht. Beton liegt unter den Containerfeldern, am Kai und als Streifen an der Fahrbahn, dazwischen Asphalt."""
    X, Z = np.asarray(X, float), np.asarray(Z, float)
    dr = HB["track"].edge_dist(X, Z) - 0.55                           # Abstand zum Außenrand des Randsteins
    n_big = hb_vnoise(X, Z, 9.0, 11.0, 5.0)
    n_mid = hb_vnoise(X, Z, 3.1, 40.0, 17.0)
    n_fine = hb_vnoise(X, Z, 1.3, 7.0, 71.0)
    r = 1.0 + (n_big - 0.5) * 0.16 + (n_mid - 0.5) * 0.10
    pad = hb_pad_at(X, Z)
    if IS_ARENA:
        ax0, az0, ax1, az1 = HB_ARENA_PAD
        inpad = hb_smooth(X, ax0 - 1.5, ax0 + 1.5) * (1 - hb_smooth(X, ax1 - 1.5, ax1 + 1.5)) * hb_smooth(Z, az0 - 1.5, az0 + 1.5) * (1 - hb_smooth(Z, az1 - 1.5, az1 + 1.5))
        conc = np.maximum(inpad, pad)
        rub = hb_rub_at(X, Z)
        g = np.clip(1.0 - conc, 0.0, 1.0)                                                       # Reparaturflicken: Rechtecke, siehe hb_plan_patches
        b = np.clip(rub * 0.55 + 0.03 * n_fine * inpad, 0.0, 1.0)
    else:
        band = 1.0 - hb_smooth(dr, 1.4, 3.6)                          # Betonstreifen an der Fahrbahn
        apron = hb_smooth(-Z, 27.2, 29.0)                             # Kaiapron: Beton
        conc = np.maximum(np.maximum(band, apron), pad)
        g = np.clip(1.0 - conc, 0.0, 1.0)                             # Flicken (Asphalt im Beton, Platten im Asphalt): Rechtecke, siehe hb_plan_patches
        cr = HB.get("crane")
        rx0, rx1 = (min(cr["xs"]) - 38.0, max(cr["xs"]) + 30.0) if cr else (0.0, 0.0)
        rails = hb_smooth(X, rx0 - 4.0, rx0 + 2.0) * (1.0 - hb_smooth(X, rx1 - 2.0, rx1 + 4.0))
        lane = np.exp(-((Z + 34.05) / 1.9) ** 2) * rails              # Spur der Terminalzugmaschinen zwischen den Kranschienen (nur dort, wo die Schienen liegen)
        grime = (1.0 - hb_smooth(dr, 0.4, 2.2)) * 0.30 * (0.6 + 0.4 * n_fine)       # Reifenstaub am Fahrbahnrand (schmaler und heller als zuvor)
        lane_wear = g * (0.02 + 0.07 * hb_smooth(n_mid, 0.55, 0.9))   # befahrene Gassen: etwas dunkler
        b = np.clip(lane * 0.26 * (0.5 + 0.5 * n_mid) + grime + lane_wear + hb_rub_at(X, Z) * 0.35, 0.0, 1.0)
    return np.clip(r, 0.7, 1.25), np.clip(g, 0, 1), np.clip(b, 0, 1)


def hb_plan_patches(level_fn):
    """Reparaturflicken im Belag als Rechtecke an den Plattenfugen (die Fugen des Betons liegen alle 4 m): Asphalt im Beton (Modus 1, auch als
    Sägeschnitt-Streifen von 2 m Breite) und neue Betonplatten im Asphalt (Modus 0). Nur dort, wo das Netz Meterzellen hat (level_fn(x, z) == 1);
    die Kanten liegen auf ganzen Metern und werden je Zelle gesetzt (scharfe Kanten wie echte Flicken). Liste (xa, za, xb, zb, Modus)."""
    rng_ = random.Random(23 + (6 if IS_ARENA else 0))
    if IS_ARENA:
        ax0, az0, ax1, az1 = HB_ARENA_PAD
        zone, n_slab, n_strip = (ax0 + 4, az0 + 4, ax1 - 4, az1 - 4), 7, 5
    else:
        zone, n_slab, n_strip = (x0 + 8, max(z0, HB_QUAY_Z + 4) + 2, x1 - 8, z1 - 6), 13, 6
    out = []
    tries = 0
    while len(out) < n_slab + n_strip and tries < 800:
        tries += 1
        strip = len(out) >= n_slab
        gx = int(rng_.uniform(zone[0], zone[2]) // 4) * 4
        gz = int(rng_.uniform(zone[1], zone[3]) // 4) * 4
        if strip:
            ln = rng_.choice((8, 12, 16))
            rect = (gx, gz - 1, gx + ln, gz + 1) if rng_.random() < 0.5 else (gx - 1, gz, gx + 1, gz + ln)
        else:
            rect = (gx, gz, gx + rng_.choice((2, 4, 4, 8)), gz + rng_.choice((2, 4, 4)))
        cx_, cz_ = (rect[0] + rect[2]) / 2, (rect[1] + rect[3]) / 2
        if rect[0] < zone[0] or rect[2] > zone[2] or rect[1] < zone[1] or rect[3] > zone[3]:
            continue
        if any(level_fn(px, pz) != 1 for px, pz in ((rect[0] + 0.5, rect[1] + 0.5), (rect[2] - 0.5, rect[3] - 0.5), (cx_, cz_), (rect[0] + 0.5, rect[3] - 0.5), (rect[2] - 0.5, rect[1] + 0.5))):
            continue
        if any(not (rect[2] + 1 < o[0] or o[2] + 1 < rect[0] or rect[3] + 1 < o[1] or o[3] + 1 < rect[1]) for o in out):
            continue
        g_here = float(hb_fields(np.array([cx_]), np.array([cz_]))[1][0])
        mode = 1 if g_here < 0.5 else 0
        if mode == 0 and strip:
            continue
        out.append((rect[0], rect[1], rect[2], rect[3], mode))
    print("DIORAMA Belagsflicken:", len(out), "(Asphalt", sum(1 for o in out if o[4] == 1), ", Beton", sum(1 for o in out if o[4] == 0), ")")
    return out


def hb_build_ground(skip_rects=(), force_rects=(), land_z_min=None):
    """Bodennetz in drei Stufen (1, 2, 4 m) mit Verschmelzung der Übergänge (Mittelpunkte auf den Kanten der gröberen Zelle, keine
    T-Kreuzungen); Gewichte analytisch je Eckpunkt. Rückgabe: Objekt "Boden_gelaende" (bekommt die gebackene Umgebungsverdeckung)."""
    track = HB["track"]
    nbx, nbz = int(math.ceil((x1 - x0) / 4.0)), int(math.ceil((z1 - z0) / 4.0))
    bcx = x0 + 4.0 * np.arange(nbx) + 2.0
    bcz = z0 + 4.0 * np.arange(nbz) + 2.0
    CX, CZ = np.meshgrid(bcx, bcz)
    dr = track.edge_dist(CX, CZ)
    lev = np.where(dr < 15.0, 1, np.where(dr < 32.0, 2, 4)).astype(int)
    for (ax0, az0, ax1, az1) in force_rects:
        sel = (CX + 2 > ax0) & (CX - 2 < ax1) & (CZ + 2 > az0) & (CZ - 2 < az1)
        lev[sel] = 1
    lev[:, -1] = 1
    lev[-1, :] = 1                                                    # Randblöcke (eventuell nicht vier Meter breit)
    if (x1 - x0) % 4 == 0:
        lev[:, -1] = np.minimum(lev[:, -1], lev[:, -1])
    changed = True
    while changed:
        changed = False
        for dz, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            sh = np.full_like(lev, 99)
            if dz == 1:
                sh[:-1, :] = lev[1:, :]
            elif dz == -1:
                sh[1:, :] = lev[:-1, :]
            elif dx == 1:
                sh[:, :-1] = lev[:, 1:]
            else:
                sh[:, 1:] = lev[:, :-1]
            bad = lev > 2 * sh
            if bad.any():
                lev[bad] = (2 * sh)[bad]
                changed = True

    def level_at(bx, bz):
        if 0 <= bx < nbx and 0 <= bz < nbz:
            return int(lev[bz, bx])
        return None

    def skipped(xa, za, xb, zb):
        mx, mz = (xa + xb) / 2, (za + zb) / 2
        if land_z_min is not None and zb <= land_z_min + 1e-9:
            return True
        return any(a0 < mx < a1 and b0 < mz < b1 for a0, b0, a1, b1 in skip_rects)
    patches = hb_plan_patches(lambda px, pz: level_at(int((px - x0) // 4), int((pz - z0) // 4)))
    cells = []
    for bz in range(nbz):
        for bx in range(nbx):
            L = int(lev[bz, bx])
            X0, Z0 = x0 + 4 * bx, z0 + 4 * bz
            n = 4 // L
            for iz in range(n):
                for ix in range(n):
                    xa, za = X0 + ix * L, Z0 + iz * L
                    xb, zb = xa + L, za + L
                    if xb > x1 + 1e-9 or zb > z1 + 1e-9 or skipped(xa, za, xb, zb):
                        continue
                    flags = [False] * 4                              # West, Ost, Süd (z-), Nord (z+): Nachbar ist feiner
                    if L > 1:
                        for k, (edge, nbk) in enumerate(((ix == 0, (bx - 1, bz)), (ix == n - 1, (bx + 1, bz)), (iz == 0, (bx, bz - 1)), (iz == n - 1, (bx, bz + 1)))):
                            if edge:
                                nl = level_at(*nbk)
                                flags[k] = nl is not None and nl == L // 2
                    mode = None
                    if L == 1:
                        for (pa, pb, pc, pd, pm) in patches:
                            if pa <= xa and xa + 1 <= pc and pb <= za and za + 1 <= pd:
                                mode = pm
                                break
                    cells.append((xa, za, L, flags, mode))
    pts_all = {}
    polys = []
    for xa, za, L, f, mode in cells:
        ring = [(xa, za)]
        if f[2]:
            ring.append((xa + L / 2, za))
        ring.append((xa + L, za))
        if f[1]:
            ring.append((xa + L, za + L / 2))
        ring.append((xa + L, za + L))
        if f[3]:
            ring.append((xa + L / 2, za + L))
        ring.append((xa, za + L))
        if f[0]:
            ring.append((xa, za + L / 2))
        for p in ring:
            pts_all.setdefault(p, None)
        polys.append((ring, mode))
    keys = list(pts_all)
    arr = np.array(keys)
    R, G, B = hb_fields(arr[:, 0], arr[:, 1])
    for k, key in enumerate(keys):
        pts_all[key] = (float(R[k]), float(G[k]), float(B[k]))
    parts = []
    for ring, mode in polys:
        cols = [pts_all[p] for p in ring][::-1]
        if mode is not None:                                         # Belagsflicken: Asphalt (1) oder Beton (0) in der ganzen Zelle, keine Abnutzung
            cols = [(c[0], float(mode), min(c[2], 0.06)) for c in cols]
        parts.append(("gelaende", [(x, z, GROUND_Y) for x, z in ring][::-1], [(x / 3.0, -z / 3.0) for x, z in ring][::-1], None, cols))
    print("DIORAMA Hafenboden: Zellen", len(polys), "Eckpunkte", len(keys))
    return mesh_object("Boden_gelaende", parts)


# ---------------------------------------------------------------- Kai (Harbour Run): Mauer, Kantenstein, Sicherheitslinie, Poller-Nachbarschaft, Fender
def hb_wall_band(out, key, p_a, p_b, y_top, y_bot, facing, rng_, seg=4.0, tile=3.0, col=(1.0, 1.0, 1.0), wet=True):
    """Senkrechte Mauer von p_a nach p_b (2D) in Abschnitten zu seg Metern; die Vertexfarbe dunkelt zum Wasser hin (Feuchte, Algensaum
    an der Wasserlinie) und schwankt je Abschnitt leicht."""
    ln = math.hypot(p_b[0] - p_a[0], p_b[1] - p_a[1])
    n = max(1, int(math.ceil(ln / seg)))
    levels = [(y_top, 1.0), (HB_WATER_Y + 1.7, 0.92), (HB_WATER_Y + 0.55, 0.62), (HB_WATER_Y + 0.05, 0.30), (y_bot, 0.15)] if wet else [(y_top, 1.0), (y_bot, 0.9)]
    for k in range(n):
        t0, t1 = k / n, (k + 1) / n
        a0 = (p_a[0] + (p_b[0] - p_a[0]) * t0, p_a[1] + (p_b[1] - p_a[1]) * t0)
        a1 = (p_a[0] + (p_b[0] - p_a[0]) * t1, p_a[1] + (p_b[1] - p_a[1]) * t1)
        v0, v1 = rng_.uniform(0.86, 1.04), rng_.uniform(0.86, 1.04)
        for (ya, fa), (yb, fb) in zip(levels[:-1], levels[1:]):
            def c(f, v):
                g = f * v
                return (g, g * (1.0 if f > 0.5 else 1.05), g * (1.0 if f > 0.5 else 0.92))
            hb_quad(out, key, [(a0[0], a0[1], yb), (a1[0], a1[1], yb), (a1[0], a1[1], ya), (a0[0], a0[1], ya)],
                    [(t0 * ln / tile, yb / tile), (t1 * ln / tile, yb / tile), (t1 * ln / tile, ya / tile), (t0 * ln / tile, ya / tile)],
                    facing, [c(fb, v0), c(fb, v1), c(fa, v1), c(fa, v0)])


def hb_build_quay(rng_):
    """Kaimauer mit Kantenstein, Sicherheitslinie und Fendern. Das Spiel baut im Diorama keinen Kai; die Mauer reicht unter die Meeresfläche."""
    qz = HB_QUAY_Z
    xa, xb = x0 - 420.0, x1 + 420.0
    wall_parts, cop_parts, line_parts = [], [], []
    hb_wall_band(wall_parts, "beton", (xa, qz), (xb, qz), 0.14, HB_WATER_Y - 0.5, (0, -1), rng_, seg=6.0)
    # Kantenstein: 0,6 m breit, 6 cm über dem Boden, hellerer Beton
    n = int((xb - xa) / 6.0)
    for k in range(n):
        xs_ = xa + k * 6.0
        v = rng_.uniform(0.9, 1.05)
        hb_quad(cop_parts, "beton", [(xs_, qz, 0.14), (xs_ + 6.0, qz, 0.14), (xs_ + 6.0, qz + 0.6, 0.14), (xs_, qz + 0.6, 0.14)],
                [(xs_ / 3.0, 0), ((xs_ + 6.0) / 3.0, 0), ((xs_ + 6.0) / 3.0, 0.2), (xs_ / 3.0, 0.2)], None, [(v, v, v)] * 4)
    hb_quad(cop_parts, "beton", [(xa, qz + 0.6, 0.14), (xb, qz + 0.6, 0.14), (xb, qz + 0.6, GROUND_Y), (xa, qz + 0.6, GROUND_Y)],
            [(0, 0), (1, 0), (1, 1), (0, 1)], (0, 1), [(0.8, 0.8, 0.8)] * 4)
    objs_ground.extend(mesh_objects("Kai", cop_parts))
    mesh_object("Kaimauer", wall_parts)
    return qz


# ---------------------------------------------------------------- Frachter: Wasserlinie aus dem KI-Modell (wie world.gd place_ai die Grundfläche anpasst)
def hb_convex_hull(pts):
    pts = sorted(set((round(float(x), 3), round(float(z), 3)) for x, z in pts))
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, up = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(up) >= 2 and cross(up[-2], up[-1], p) <= 0:
            up.pop()
        up.append(p)
    return lo[:-1] + up[:-1]


def hb_ship_outline():
    """Umriss des Frachters auf der Wasserlinie (Weltkoordinaten, gegen den Uhrzeigersinn) oder None."""
    ship = next((p for p in data["props"] if str(p.get("model", "")).startswith("hafen_frachtschiff")), None)
    if ship is None:
        return None
    x, z = float(ship["x"]), float(ship["z"])
    try:
        obj, _ext = model("hafen_frachtschiff")
        me = obj.data
        co = np.empty(len(me.vertices) * 3, np.float32)
        me.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3).astype(float)
    except Exception as err:                                   # Vorschau ohne Blender oder fehlendes Modell
        print("DIORAMA Frachter-Umriss nicht ermittelbar:", err)
        return None
    gx, gy, gz = co[:, 0], co[:, 2], -co[:, 1]                 # Blender (x, y, z) -> glTF/Spiel (x, y hoch, z)
    size = np.array([gx.max() - gx.min(), gy.max() - gy.min(), gz.max() - gz.min()])
    ax, ay, az = (gx.max() + gx.min()) / 2, gy.min(), (gz.max() + gz.min()) / 2
    w, d = float(ship.get("w", 0.0)), float(ship.get("d", 0.0))
    yaw = -math.radians(float(ship.get("rot", 0.0))) + math.radians(90.0)       # AI_PROP_YAW["hafen_frachtschiff"] = 90
    fp = (d, w)                                                 # Grundfläche in Modellachsen (nach dem 90°-Tausch)
    u = min(fp[0] / max(size[0], 1e-3), fp[1] / max(size[2], 1e-3))
    c, s = math.cos(yaw), math.sin(yaw)
    wx = x + u * (c * (gx - ax) + s * (gz - az))
    wz = z + u * (-s * (gx - ax) + c * (gz - az))
    wy = float(ship.get("y", 0.0)) + u * (gy - ay)
    sel = np.abs(wy - HB_WATER_Y) < 0.45
    if sel.sum() < 12:
        return None
    hull = hb_convex_hull(list(zip(wx[sel], wz[sel])))
    print("DIORAMA Frachter: Wasserlinie", len(hull), "Punkte, Länge", round(float(wx[sel].max() - wx[sel].min()), 1), "m, Deckhöhe etwa", round(float(wy.max()), 1))
    return hull


def hb_hull_dist(X, Z, hull):
    """Vorzeichenbehafteter Abstand zu einem konvexen Polygon (negativ innen), für Zahlenfelder."""
    best = None
    pts = np.array(hull, float)
    area_ = 0.5 * np.sum(pts[:, 0] * np.roll(pts[:, 1], -1) - np.roll(pts[:, 0], -1) * pts[:, 1])
    sign = 1.0 if area_ > 0 else -1.0
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        e = b - a
        ln = np.hypot(*e) or 1.0
        nrm = np.array([e[1], -e[0]]) / ln * sign                 # nach außen
        dd = (X - a[0]) * nrm[0] + (Z - a[1]) * nrm[1]
        best = dd if best is None else np.maximum(best, dd)
    return best


# ---------------------------------------------------------------- Wasser: ein Netz mit Tiefenwert in der Vertexfarbe (Rot), Schaum am Rumpf
def hb_water_depth(X, Z, hulls=None, basin=None):
    d = 0.17 + np.clip(HB_QUAY_Z - Z, 0.0, None) * 0.012
    if basin is not None:
        bx0_, bz0_, bx1_, bz1_ = basin
        dw = np.minimum.reduce([X - bx0_, bx1_ - X, Z - bz0_, bz1_ - Z])
        d = np.where((X > bx0_ - 0.01) & (X < bx1_ + 0.01) & (Z > bz0_ - 0.01) & (Z < bz1_ + 0.01), 0.17 + np.clip(dw, 0.0, None) * 0.045, d)
    for hull in (hulls or []):
        dh = np.clip(hb_hull_dist(X, Z, hull), 0.0, None)
        ring = dh * 0.32
        k = hb_smooth(dh, 0.3, 1.4)
        d = ring * (1.0 - k) + d * k
    return np.clip(d, 0.0, 1.0)


def hb_build_water(hulls, basin):
    """Hafenwasser: Netz nördlich der Kaimauer (Meerseite) und im Becken; D_Wasser mit Flachwasser-Shader (water_nodes). Fein (1 m) an der
    Mauer und um den Frachter (Schaumsaum am Rumpf), sonst 4 m."""
    qz = HB_QUAY_Z
    parts = []
    y = HB_WATER_Y + 0.015

    def add(xa, za, xb, zb):
        ring = [(xa, za), (xb, za), (xb, zb), (xa, zb)]
        X = np.array([p[0] for p in ring])
        Z = np.array([p[1] for p in ring])
        d = hb_water_depth(X, Z, hulls, basin)
        parts.append(("wasser", [(p[0], p[1], y) for p in ring][::-1], [(p[0] / 8.0, -p[1] / 8.0) for p in ring][::-1], None, [(float(v), 0.0, 0.0) for v in d][::-1]))
    if qz < 1e8:
        fine = [(x0 - 4.0, qz - 5.0, x1 + 4.0, qz)]
        for hull in hulls:
            hp = np.array(hull)
            fine.append((hp[:, 0].min() - 3.0, hp[:, 1].min() - 3.0, hp[:, 0].max() + 3.0, hp[:, 1].max() + 3.0))
        zlo = z0 - 40.0
        for xa in np.arange(x0 - 4.0, x1 + 4.0, 4.0):
            for za in np.arange(zlo, qz, 4.0):
                zb = min(za + 4.0, qz)
                if any(xa < f[2] and xa + 4.0 > f[0] and za < f[3] and zb > f[1] for f in fine):
                    for xs_ in np.arange(xa, xa + 4.0, 1.0):
                        for zs_ in np.arange(za, zb, 1.0):
                            if zs_ + 1.0 <= qz + 1e-9:
                                add(xs_, zs_, xs_ + 1.0, zs_ + 1.0)
                else:
                    add(xa, za, xa + 4.0, zb)
        far = 420.0
        for (ax0, az0, ax1, az1) in ((x0 - 4.0 - far, zlo - far, x1 + 4.0 + far, zlo), (x0 - 4.0 - far, zlo, x0 - 4.0, qz), (x1 + 4.0, zlo, x1 + 4.0 + far, qz)):
            ring = [(ax0, az0), (ax1, az0), (ax1, az1), (ax0, az1)]
            parts.append(("wasser", [(p[0], p[1], y) for p in ring][::-1], [(p[0] / 8.0, -p[1] / 8.0) for p in ring][::-1], None, [(0.8, 0.0, 0.0)] * 4))
    if basin is not None:
        bx0_, bz0_, bx1_, bz1_ = basin
        for xa in np.arange(bx0_, bx1_, 1.0):
            for za in np.arange(bz0_, bz1_, 1.0):
                add(xa, za, xa + 1.0, za + 1.0)
    return mesh_object("Hafenwasser", parts)


# ---------------------------------------------------------------- Warnmarkierung, Poller, Geländer
def hb_hatch(out_black, out_yellow, xa, za, xb, zb, width, y, period=0.6, angle_deg=45.0, wear=None):
    """Gelb-schwarz schräg gestreiftes Band von (xa, za) nach (xb, zb): schwarze Grundfläche und gelbe Parallelogramme."""
    dx, dz = xb - xa, zb - za
    ln = math.hypot(dx, dz)
    if ln < 0.2:
        return
    ux, uz = dx / ln, dz / ln
    vx, vz = -uz, ux
    hw_ = width / 2
    out_black.append(("linie_schwarz", [(xa - vx * hw_, za - vz * hw_, y), (xb - vx * hw_, zb - vz * hw_, y), (xb + vx * hw_, zb + vz * hw_, y), (xa + vx * hw_, za + vz * hw_, y)],
                      [(0, 0), (1, 0), (1, 1), (0, 1)]))
    shear = width / math.tan(math.radians(angle_deg))
    k = 0
    t = -shear
    while t < ln:
        a0, a1 = t, t + period / 2
        pts = []
        for (aa, bb) in ((a0, -hw_), (a1, -hw_), (a1 + shear, hw_), (a0 + shear, hw_)):
            aa_c = min(max(aa, 0.0), ln)
            pts.append((xa + ux * aa_c + vx * bb, za + uz * aa_c + vz * bb, y + 0.005))
        # Kanten am Bandende abschneiden: Punkte außerhalb auf das Ende klemmen (entartete Dreiecke sind harmlos)
        if abs(pts[0][0] - pts[1][0]) + abs(pts[0][1] - pts[1][1]) + abs(pts[2][0] - pts[3][0]) + abs(pts[2][1] - pts[3][1]) > 0.05:
            out_yellow.append(("linie_gelb", pts, [(0, 0), (1, 0), (1, 1), (0, 1)]))
        t += period
        k += 1


def hb_bollard(out, x, z, y0=None, scale=1.0, col=(0.05, 0.05, 0.055), collide=True):
    """Pfahlpoller aus Guss: Sockel, Schaft, Pilzkopf."""
    y0 = GROUND_Y if y0 is None else y0
    hb_prism(out, x, z, 0.20 * scale, y0, y0 + 0.50 * scale, "stahl_dunkel", col, 8, 0.17 * scale)
    hb_prism(out, x, z, 0.28 * scale, y0 + 0.50 * scale, y0 + 0.64 * scale, "stahl_dunkel", col, 8, 0.24 * scale, cap_col=tuple(v * 1.6 for v in col))
    if collide:
        collide_circle(x, z, 0.3 * scale, 0.7, "mauer")


def hb_railing(out, pts, y0=None, height=1.05, key="gelb", col=(1, 1, 1), post_every=2.4, collide=True, margin=0.6):
    """Geländer entlang eines Linienzugs (2D): Pfosten, Handlauf, Knieleiste. Eintrag als weiches Hindernis (Gitter) in Stücken."""
    y0 = GROUND_Y if y0 is None else y0
    for (xa, za), (xb, zb) in zip(pts[:-1], pts[1:]):
        ln = math.hypot(xb - xa, zb - za)
        if ln < 0.1:
            continue
        ux, uz = (xb - xa) / ln, (zb - za) / ln
        n = max(1, int(round(ln / post_every)))
        for k in range(n + 1):
            px, pz = xa + ux * ln * k / n, za + uz * ln * k / n
            hb_cuboid(out, px, pz, 1.0, 0.0, 0.035, 0.035, y0, y0 + height, key, col=col, tile=1.0, bottom_fade=False)
        for hy in (height, height * 0.5):
            hb_cuboid(out, (xa + xb) / 2, (za + zb) / 2, ux, uz, ln / 2, 0.022, y0 + hy - 0.02, y0 + hy + 0.02, key, col=col, tile=1.0, bottom_fade=False)
        if collide:
            hb_solid_force((xa + xb) / 2, (za + zb) / 2, ux, uz, ln / 2, 0.06, 1.0, "gitter", margin=margin)


def hb_hazard_post(out, x, z, height=1.0):
    """Gelb-schwarz geringelter Absperrpfosten (Rammschutz)."""
    n = 5
    for k in range(n):
        hb_prism(out, x, z, 0.09, GROUND_Y + height * k / n, GROUND_Y + height * (k + 1) / n, "gelb" if k % 2 == 0 else "stahl_dunkel", (1, 1, 1) if k % 2 == 0 else (0.03, 0.03, 0.035), 8, tile=1.0)


# ---------------------------------------------------------------- Kranbahn: zwei Schienen parallel zum Kai
HB_CRANE_SCALE = 22.0


def hb_crane_rails():
    """Schienen aus den Kränen der Streckendatei: seeseitig (im Boden, auf Schwellen) und landseitig (auf erhöhtem Balken, die KI-Beine hängen
    0,8 m über dem Boden). Maße aus dem Modell hafen_kran (Beine bei x = -0,145 und -0,449 der Länge, Drehung 180°)."""
    cranes = [p for p in data["props"] if p.get("model") == "hafen_kran"]
    if not cranes:
        return None
    sc = float(cranes[0].get("h", HB_CRANE_SCALE))
    cz = float(cranes[0]["z"])
    xs_ = [float(p["x"]) for p in cranes]
    return {"z_sea": cz + 0.1455 * sc, "z_land": cz + 0.449 * sc, "xs": xs_, "scale": sc, "h_land": 0.78, "leg_dx": 0.2 * sc}


def hb_build_rails(rng_, info, dec_black, dec_yellow):
    """Rückgabe: Teilelisten (beton, stahl, rot, ...) als dict key -> Flächen."""
    out = {"beton": [], "stahl": [], "stahl_dunkel": [], "rot": [], "gelb": []}
    xa, xb = min(info["xs"]) - 38.0, max(info["xs"]) + 30.0
    zs, zl = info["z_sea"], info["z_land"]
    y = GROUND_Y
    # seeseitige Schiene: Betonbalken bündig im Boden, Schwellen, Schienenfuß, Schienenkopf
    hb_rect_flat(out["beton"], "beton", xa, zs - 0.55, xb, zs + 0.55, y + 0.012, (0.95, 0.95, 0.95), 3.0)
    x = xa + 0.4
    while x < xb - 0.3:
        hb_rect_flat(out["stahl_dunkel"], "stahl_dunkel", x, zs - 0.30, x + 0.22, zs + 0.30, y + 0.018, (0.55, 0.55, 0.55))
        x += 0.65
    hb_cuboid(out["stahl"], (xa + xb) / 2, zs, 1.0, 0.0, (xb - xa) / 2, 0.075, y + 0.018, y + 0.135, "stahl", col=(1.0, 1.0, 1.0), tile=1.0, bottom_fade=False)
    # Warnstreifen beidseits
    for side in (-1, 1):
        hb_hatch(dec_black, dec_yellow, xa, zs + side * 0.80, xb, zs + side * 0.80, 0.34, y + 0.016, 0.55)
    # landseitige Schiene: wie die seeseitige bündig im Boden (vorher ein 0,62 m hoher Balken über die ganze Länge, 1,6 m neben dem Randstein der
    # Start-Ziel-Geraden: Gegner, die aus der letzten Kurve weit hinaustragen, blieben daran hängen, Feldtest 03.10.2026). Die KI-Kranbeine
    # hängen 0,78 m über dem Boden; sie stehen jetzt auf Stützböcken (Beton mit Stahlplatte, 2,8 x 1,2 m) unter jedem landseitigen Fuß.
    hl = info["h_land"]
    hb_rect_flat(out["beton"], "beton", xa, zl - 0.55, xb, zl + 0.55, y + 0.012, (0.95, 0.95, 0.95), 3.0)
    x = xa + 0.4
    while x < xb - 0.3:
        hb_rect_flat(out["stahl_dunkel"], "stahl_dunkel", x, zl - 0.30, x + 0.22, zl + 0.30, y + 0.018, (0.55, 0.55, 0.55))
        x += 0.65
    hb_cuboid(out["stahl"], (xa + xb) / 2, zl, 1.0, 0.0, (xb - xa) / 2, 0.075, y + 0.018, y + 0.135, "stahl", col=(1.0, 1.0, 1.0), tile=1.0, bottom_fade=False)
    for side in (-1, 1):
        hb_hatch(dec_black, dec_yellow, xa, zl + side * 0.80, xb, zl + side * 0.80, 0.34, y + 0.016, 0.55)
    for cx_ in info["xs"]:
        for sg_ in (-1, 1):
            fx_ = cx_ + sg_ * info["leg_dx"]
            hb_cuboid(out["beton"], fx_, zl, 1.0, 0.0, 1.4, 0.6, y - 0.02, hl - 0.1, "beton", col=(0.9, 0.9, 0.9), tile=1.5, bottom_fade=False)
            hb_cuboid(out["stahl_dunkel"], fx_, zl, 1.0, 0.0, 1.3, 0.5, hl - 0.1, hl - 0.02, "stahl_dunkel", col=(0.75, 0.75, 0.76), tile=1.0, bottom_fade=False)
            if not hb_solid_force(fx_, zl, 1.0, 0.0, 1.4, 0.6, hl, "mauer", margin=1.0):
                print("DIORAMA Warnung: Stützbock des Krans verletzt den Fahrschlauchabstand", round(fx_, 1))
    # Prellböcke an den Enden (rot-gelb)
    for (bx_, sgn) in ((xa, 1), (xb, -1)):
        for zc, yb in ((zs, y), (zl, y)):
            hb_cuboid(out["rot"], bx_ - sgn * 0.45, zc, 1.0, 0.0, 0.45, 0.42, yb, yb + 0.7, "rot", col=(1.0, 1.0, 1.0), tile=1.0, bottom_fade=False)
            hb_cuboid(out["gelb"], bx_ - sgn * 0.02, zc, 1.0, 0.0, 0.03, 0.40, yb + 0.12, yb + 0.55, "gelb", col=(1.0, 1.0, 1.0), tile=1.0, bottom_fade=False)
    return out, (xa, xb)


# ---------------------------------------------------------------- Hafenbecken an der Lücke der Straße (Schanze über das Wasser)
def hb_basin_rect():
    """Rechteck des Hafenbeckens (x0, z0, x1, z1) mit ganzzahligen Kanten: spannt die Lücke der Straße; das Spiel lässt dort die Fahrbahn weg."""
    gaps = [g for g in data.get("gaps", []) if base_height(float(g["from"])) < 0.5]      # Fassung 2: die erhöhte Lücke ist die Gasse der Terrasse
    if IS_ARENA or not gaps:
        return None
    tr = HB["track"]
    pa, _ta = tr.at(float(gaps[0]["from"]))
    pb, _tb = tr.at(float(gaps[0]["to"]))
    xl, xr = sorted((float(pa[0]), float(pb[0])))
    zc = 0.5 * (float(pa[1]) + float(pb[1]))
    return (math.floor(xl), math.floor(zc) - 12, round(xr), math.floor(zc) + 16)


def hb_build_basin(rng_, rect, dec_black, dec_yellow):
    """Becken mit Mauern, Kantenstein, Sicherheitslinie, Geländer, Pollern, Leitern, Rettungsring und Schlepper. Rückgabe: dict Teilelisten."""
    bx0, bz0, bx1, bz1 = rect
    tr = HB["track"]
    zc = 0.5 * (bz0 + bz1) - 2.0
    pa, _ = tr.at(float(data["gaps"][0]["from"]))
    zroad = float(pa[1])
    hw_road = HW + 1.2
    out = {"beton": [], "wall": [], "gelb": [], "stahl_dunkel": [], "rot": [], "weiss": [], "gummi": [], "stahl": []}
    wall = out["wall"]
    hb_wall_band(wall, "beton", (bx1, bz0), (bx1, bz1), 0.14, HB_WATER_Y - 0.5, (-1, 0), rng_)
    hb_wall_band(wall, "beton", (bx0, bz0), (bx0, bz1), 0.14, HB_WATER_Y - 0.5, (1, 0), rng_)
    hb_wall_band(wall, "beton", (bx0, bz0), (bx1, bz0), 0.14, HB_WATER_Y - 0.5, (0, 1), rng_)
    hb_wall_band(wall, "beton", (bx0, bz1), (bx1, bz1), 0.14, HB_WATER_Y - 0.5, (0, -1), rng_)
    # Kantenstein 0,6 m breit, Lücke dort, wo die Straße das Becken kreuzt
    def cop(xa, za, xb, zb):
        hb_rect_flat(out["beton"], "beton", min(xa, xb), min(za, zb), max(xa, xb), max(za, zb), 0.14, (1.0, 1.0, 1.0), 2.0)
    cop(bx1, bz0 - 0.6, bx0 - 0.6, bz0)
    cop(bx1 + 0.6, bz1, bx0 - 0.6, bz1 + 0.6)
    for xe, d in ((bx1, 1), (bx0, -1)):
        cop(xe, bz0, xe + d * 0.6, zroad - hw_road)
        cop(xe, zroad + hw_road, xe + d * 0.6, bz1)
    # Sicherheitslinie 1,0 m hinter der Kante (gelb, abgenutzt: kurze Lücken)
    def yline(xa, za, xb, zb):
        ln = math.hypot(xb - xa, zb - za)
        n = max(1, int(ln / 3.0))
        for k in range(n):
            if rng_.random() < 0.12:
                continue
            t0, t1 = k / n, (k + 1) / n - 0.02
            hb_strip(dec_yellow, "linie_gelb", xa + (xb - xa) * t0, za + (zb - za) * t0, xa + (xb - xa) * t1, za + (zb - za) * t1, 0.2, GROUND_Y + 0.004,
                     (rng_.uniform(0.7, 1.0),) * 3)
    yline(bx1 + 0.8, bz0 - 1.4, bx0 - 0.8, bz0 - 1.4)
    yline(bx1 + 0.8, bz1 + 1.4, bx0 - 0.8, bz1 + 1.4)
    for xe, d in ((bx1, 1), (bx0, -1)):
        yline(xe + d * 1.4, bz0 - 1.4, xe + d * 1.4, zroad - hw_road - 0.4)
        yline(xe + d * 1.4, zroad + hw_road + 0.4, xe + d * 1.4, bz1 + 1.4)
    # Geländer (Stahlrohr, gelb) und Poller
    yy = GROUND_Y + 0.06
    hb_railing(out["gelb"], [(bx1 + 0.35, bz0 - 0.35), (bx0 - 0.35, bz0 - 0.35)], yy)
    hb_railing(out["gelb"], [(bx1 + 0.35, bz1 + 0.35), (bx0 - 0.35, bz1 + 0.35)], yy)
    for xe, d in ((bx1, 1), (bx0, -1)):
        hb_railing(out["gelb"], [(xe + d * 0.35, bz0 - 0.35), (xe + d * 0.35, zroad - hw_road - 0.2)], yy)
        hb_railing(out["gelb"], [(xe + d * 0.35, zroad + hw_road + 0.2), (xe + d * 0.35, bz1 + 0.35)], yy)
    for px, pz in ((bx1 + 0.55, bz0 - 0.55), (bx0 - 0.55, bz0 - 0.55), (bx1 + 0.55, bz1 + 0.55), (bx0 - 0.55, bz1 + 0.55),
                   (bx1 + 0.55, bz1 - 6.0), (bx0 - 0.55, bz1 - 6.0)):
        if tr.circle_slack(px, pz, 0.3) >= 1.0:
            hb_bollard(out["stahl_dunkel"], px, pz, yy + 0.04, collide=False)
            HB["circles"].append((px, pz, 0.3, 0.7, "mauer"))
    # Leitern in Nischen (West- und Ostwand), Stufen als helle Stäbe
    for xw, fx in ((bx0, 1), (bx1, -1)):
        zl = bz0 + 4.0 if fx > 0 else bz1 - 4.0
        for k in range(10):
            yk = 0.0 - k * 0.27
            hb_quad(out["stahl"], "stahl", [(xw + fx * 0.04, zl - 0.2, yk), (xw + fx * 0.04, zl + 0.2, yk), (xw + fx * 0.04, zl + 0.2, yk - 0.04), (xw + fx * 0.04, zl - 0.2, yk - 0.04)],
                    [(0, 0), (1, 0), (1, 1), (0, 1)], (fx, 0), [(0.8, 0.8, 0.8)] * 4)
        for dz in (-0.22, 0.22):
            hb_quad(out["stahl"], "stahl", [(xw + fx * 0.04, zl + dz - 0.015, 0.1), (xw + fx * 0.04, zl + dz + 0.015, 0.1), (xw + fx * 0.04, zl + dz + 0.015, -2.6), (xw + fx * 0.04, zl + dz - 0.015, -2.6)],
                    [(0, 0), (1, 0), (1, 1), (0, 1)], (fx, 0), [(0.7, 0.7, 0.7)] * 4)
    return out


# ---------------------------------------------------------------- Hooks
def hb_decal_objects(prefix, parts):
    """Markierungen (flache Auflagen): ein Objekt je Material, Name endet auf _linie (der Kern gibt ihnen die Lichttextur zum Lesen,
    sie schreiben beim Backen nicht), und in objs_ground aufnehmen."""
    groups = {}
    for p in parts:
        groups.setdefault(p[0], []).append(p)
    for key, ps in groups.items():
        objs_ground.append(mesh_object("%s_%s_linie" % (prefix, key), ps))


def theme_materials():
    HB["track"] = HbTrack()
    HB["occ"] = []
    HB["rng"] = random.Random(7 if not IS_ARENA else 19)
    M["gelaende"] = material("D_Gelaende", color=(0.5, 0.5, 0.5), rough=0.9)          # Platzhalter: der Boden-Shader des Spiels ersetzt ihn
    M["linie_gelb"] = material("D_MarkierungGelb", color=hb_lin((0.93, 0.70, 0.08)), rough=0.6)
    M["linie_schwarz"] = material("D_MarkierungSchwarz", color=hb_lin((0.06, 0.06, 0.065)), rough=0.8)
    M["stahl_dunkel"] = material("D_StahlDunkel", color=hb_lin((0.22, 0.23, 0.25)), rough=0.5)
    sd = HB_TEX_DIR
    M["cont_seite"] = material("D_ContSeite", os.path.join(sd, "container_seite.png"), 0.55, os.path.join(sd, "container_seite_n.png"))
    M["cont_tuer"] = material("D_ContTuer", os.path.join(sd, "container_tuer.png"), 0.55, os.path.join(sd, "container_tuer_n.png"))
    M["cont_dach"] = material("D_ContDach", os.path.join(sd, "container_dach.png"), 0.6, os.path.join(sd, "container_dach_n.png"))
    M["lack"] = material("D_Lack", os.path.join(sd, "lack.png"), 0.42)                  # verwitterter Lack (Regenschlieren, Staub, Rost) x Vertexfarbe des Fahrzeugs
    M["seil"] = material("D_Seil", color=hb_lin((0.3, 0.26, 0.18)), rough=0.9)
    M["planen"] = material("D_Planen", os.path.join(sd, "planen.png"), 0.85, os.path.join(sd, "planen_n.png"))
    M["glas"] = material("D_Glas", color=hb_lin((0.06, 0.09, 0.12)), rough=0.12)
    M["lichtband"] = material("D_Lichtband", color=hb_lin((0.62, 0.72, 0.78)), rough=0.25)
    M["solar"] = material("D_Solar", color=hb_lin((0.07, 0.10, 0.20)), rough=0.4)
    M["blech_wand"] = material("D_BlechWand", os.path.join(sd, "blech_wand.png"), 0.5, os.path.join(sd, "blech_wand_n.png"))
    M["schotter"] = material("D_Schotter", os.path.join(sd, "schotter.png"), 0.95, os.path.join(sd, "schotter_n.png"))
    M["blech_dach"] = material("D_BlechDach", os.path.join(sd, "blech_dach.png"), 0.45, os.path.join(sd, "blech_dach_n.png"))
    M["riffel"] = material("D_Riffelblech", os.path.join(sd, "riffelblech.png"), 0.45, os.path.join(sd, "riffelblech_n.png"))
    hb_plan_layout()


def theme_ground():
    skip, force = [], []
    if HB["basin"]:
        bx0, bz0, bx1, bz1 = HB["basin"]
        skip.append((bx0, bz0, bx1, bz1))
        force.append((bx0 - 6, bz0 - 6, bx1 + 6, bz1 + 6))
    if HB_QUAY_Z < 1e8:
        force.append((x0, HB_QUAY_Z - 8, x1, HB_QUAY_Z + 18))
    if IS_ARENA:
        force.append(HB_ARENA_PAD)
    hb_build_rubber_raster()
    hb_build_pad_raster()
    objs_ground.append(hb_build_ground(skip, force, HB_QUAY_Z if HB_QUAY_Z < 1e8 else None))


def hb_ground_far():
    """Weite Fläche rund um das Diorama (ohne Lichttextur): derselbe Boden-Shader, Asphalt; im Hafen nur landseitig der Kaikante."""
    far = 420.0
    parts = []

    def add(ax0, az0, ax1, az1):
        ring = [(ax0, az0), (ax1, az0), (ax1, az1), (ax0, az1)]
        parts.append(("gelaende", [(a, b, GROUND_Y) for a, b in ring][::-1], [(a / 3.0, -b / 3.0) for a, b in ring][::-1], None, [(1.0, 0.9, 0.0)] * 4))
    top = HB_QUAY_Z if HB_QUAY_Z < 1e8 else z0 - far
    add(x0 - far, top, x0, z1 + far)
    add(x1, top, x1 + far, z1 + far)
    add(x0, z1, x1, z1 + far)
    if HB_QUAY_Z >= 1e8:
        add(x0, z0 - far, x1, z0)
    mesh_object("Weite_gelaende", parts)


def hb_ai_yaw_table():
    """AI_PROP_YAW aus game/scripts/world.gd: Drehung der KI-Modelle (Grad) vor dem Einpassen auf w x d."""
    if "yaw" not in HB:
        tab = {}
        try:
            with open(os.path.join(PROPS, "..", "..", "scripts", "world.gd"), encoding="utf-8") as fh:
                m = re.search(r"const\s+AI_PROP_YAW\s*:=\s*\{(.*?)\}", fh.read(), re.S)
            if m:
                tab = {k: float(v) for k, v in re.findall(r'"([^"]+)"\s*:\s*(-?[0-9.]+)', m.group(1))}
        except OSError:
            pass
        HB["yaw"] = tab
    return HB["yaw"]


def hb_ai_footprint(p):
    """Tatsächliche Grundfläche eines KI-Modells mit w und d nach dem Einpassen im Spiel (world.gd place_ai: gleichmäßig auf das Maß w x d skaliert,
    das Seitenverhältnis des Modells bleibt erhalten, die Mitte der Hüllbox liegt auf (x, z)). Rückgabe: halbe Breite (x), halbe Tiefe (z) vor der Drehung
    des Bausteins und Höhe. Ohne lesbares Modell (Vorschau): das Maß w x d."""
    w, d = float(p["w"]), float(p["d"])
    name = str(p.get("model", ""))
    try:
        obj, _ext = model(name)
        co = np.empty(len(obj.data.vertices) * 3, np.float32)
        obj.data.vertices.foreach_get("co", co)
        co = co.reshape(-1, 3).astype(float)
        sx, sy, sz = (float(co[:, 0].max() - co[:, 0].min()), float(co[:, 2].max() - co[:, 2].min()), float(co[:, 1].max() - co[:, 1].min()))
    except Exception:
        return w / 2, d / 2, float(p.get("h", 3.0))
    yaw = hb_ai_yaw_table().get(name, 0.0)
    swapped = abs(yaw) == 90.0
    fp = (d, w) if swapped else (w, d)
    u = min(fp[0] / max(sx, 1e-3), fp[1] / max(sz, 1e-3))
    ex, ez = sx * u, sz * u
    if swapped:
        ex, ez = ez, ex
    return ex / 2, ez / 2, sy * u


def hb_ai_rect_proxies(props):
    """Kontaktschatten für KI-Modelle mit w x d: Quader in der wirklichen Grundfläche (nicht in w x d, das sonst zu große Schatten wirft)."""
    parts = []
    for p in props:
        hx, hz, h = hb_ai_footprint(p)
        x, z = float(p["x"]), float(p["z"])
        rot = math.radians(float(p.get("rot", 0.0)))
        fr = Frame((x, z), (math.cos(rot), math.sin(rot)), (-math.sin(rot), math.cos(rot)))
        parts += box(fr, "ao", -hx, hx, -hz, hz, GROUND_Y, GROUND_Y + max(h, 0.5))
    if parts:
        ao_proxy_objs.append(mesh_object("AOProxy_ki_%d" % len(ao_proxy_objs), parts))
    print("DIORAMA AO-Stellvertreter (KI-Modelle, wirkliche Grundfläche):", len(props))


def hb_crane_proxies():
    """Kontaktschatten unter den Kranfüßen (vier Fußplatten je Kran, auf beiden Schienen); der Kran selbst ist ein Laufzeit-Modell."""
    info = HB.get("crane")
    if not info:
        return
    parts = []
    for cx in info["xs"]:
        for dx in (-info["leg_dx"], info["leg_dx"]):
            for zc, y1 in ((info["z_sea"], GROUND_Y + 1.3), (info["z_land"], info["h_land"] + 1.3)):
                fr = Frame((cx + dx, zc), (1.0, 0.0), (0.0, 1.0))
                parts += box(fr, "ao", -1.1, 1.1, -1.3, 1.3, GROUND_Y, y1)
    if parts:
        ao_proxy_objs.append(mesh_object("AOProxy_kran", parts))


def theme_scenery():
    rng_ = HB["rng"]
    dec_black, dec_yellow, dec_white = [], [], []
    if HB_QUAY_Z < 1e8:
        HB["hull"] = hb_ship_outline()                  # model() existiert erst ab hier (Kern definiert es nach theme_ground)
        hulls = [HB["hull"]] if HB["hull"] else []
        if HB["basin"]:
            bx0, bz0, bx1, bz1 = HB["basin"]
            HB["tug"] = ((bx0 + bx1) / 2.0, bz1 - 6.7, 0.0, -1.0)
            hulls.append(hb_tug_hull_world(*HB["tug"]))
        hb_build_water(hulls, HB["basin"])
        hb_build_quay(rng_)
        hb_build_quay_details(rng_, HB["hull"])
        if HB["basin"]:
            hb_build_tug(*HB["tug"])
    hb_ground_far()
    info = HB["crane"]
    if info:
        rails, _span = hb_build_rails(rng_, info, dec_black, dec_yellow)
        for k, parts in rails.items():
            if parts:
                mesh_objects("Kranbahn_" + k, parts)
        for cx_ in info["xs"]:                                       # Arbeitsscheinwerfer an den seeseitigen Kranbeinen (echte Lichtquellen über der Kaikante)
            for sg_ in (-1, 1):
                lx_ = cx_ + sg_ * info["leg_dx"]
                add_light(lx_, info["z_sea"] - 0.4, 9.0, color=(1.0, 0.93, 0.8), energy=0.03, range=2.0, omni=False, glow=0.8)
                add_light(lx_, info["z_sea"] - 2.8, 9.0, color=(1.0, 0.93, 0.8), energy=0.5, range=14.0, omni=False)
    if HB["basin"]:
        b = hb_build_basin(rng_, HB["basin"], dec_black, dec_yellow)
        for k, parts in b.items():
            if parts:
                mesh_objects("Becken_" + k, parts)
    hb_portal()
    hb_build_containers(rng_)
    hb_lv_build(rng_, dec_black, dec_yellow)
    hb_build_buildings(rng_, dec_white)
    hb_build_vehicles(rng_)
    if not IS_ARENA:
        hb_build_masts()
        for (lx_, lz_, ly_) in HB.get("dock_lights", []):
            add_light(lx_, lz_, ly_, color=(1.0, 0.92, 0.75), energy=0.65, range=9.0, omni=False, glow=0.5)
    hb_build_cars(rng_)
    hb_build_siding(rng_)
    hb_build_barriers()
    hb_build_signs()
    hb_build_clutter(rng_)
    hb_build_fences(rng_)
    if IS_ARENA:
        hb_build_arena(rng_, dec_white, dec_yellow)
    for (lx, lz, tx, tz) in HB["lamps"]:
        add_lamp(lx, lz, tx, tz, model=HB_LAMP_MODEL)                  # Hafenlaterne statt der Küstenlaterne des Spiels
    hb_slot_marks(dec_white)
    hb_lane_marks(dec_white, dec_yellow)
    if dec_black or dec_yellow:
        hb_decal_objects("Warn", dec_black + dec_yellow)
    if dec_white:
        hb_decal_objects("Bucht", dec_white)
    hb_commit_colliders()
    saved = data["props"]
    rect_props = [p for p in saved if p.get("type") == "ai" and "w" in p and "d" in p and float(p.get("y", 0.0)) >= -1.0 and p.get("model") != "hafen_kran"]
    data["props"] = [p for p in saved if p.get("model") != "hafen_kran" and not any(p is r for r in rect_props)]
    ao_proxies()
    data["props"] = []
    ao_proxies(types=["lamp"])                       # unsere eigenen Laternen (die der Streckendatei sind baked): Kontaktschatten am Mastfuß
    data["props"] = saved
    hb_ai_rect_proxies(rect_props)
    hb_crane_proxies()


def hb_build_arena(rng_, dec_white, dec_yellow):
    """Szene der Drift Arena: Driftzonen mit Leitkegeln, Boxengasse (Zelte, Transporter, Reifen, Aggregate), Richterturm, Zuschauerzeilen."""
    cone = hb_new_parts("gummi", "lack")
    hb_build_corner_marks(dec_yellow, dec_white, cone)
    for k, v in cone.items():
        if v:
            mesh_objects("Leitkegel_" + k, v)
    parts = hb_new_parts("lack", "stahl", "stahl_dunkel", "glas", "gummi", "beton", "e:flagge", "e:banner")
    for kind, x, z, ang, col in HB["paddock_items"]:
        if kind == "tent":
            hb_tent(parts, x, z, ang, col, num=int(round((x + 46.0) / 5.2)) + 1)
            add_light(x, z + 0.6, 2.7, color=(1.0, 0.95, 0.86), energy=0.5, range=8.0, omni=False)         # LED-Leuchte unter dem Zeltdach (echte Lichtquelle)
            fx, fz = x + 2.2, z + 3.2
            if hb_free(fx, fz, 1.0, 0.0, 0.3, 0.3, 2.0, 0.0):
                hb_occupy(fx, fz, 1.0, 0.0, 0.3, 0.3)
                hb_flag_pole(parts, fx, fz, col, 4.0, rng_.uniform(-0.4, 0.4))
        elif kind == "tyres":
            hb_tyre_stack(parts, x, z, 6)
            hb_tyre_stack(parts, x + 0.85, z + 0.2, 5)
        elif kind == "gen":
            hb_generator(parts, x, z, ang)
    if HB["tower"]:
        tx, tz, ta = HB["tower"]
        hb_judge_tower(parts, tx + 0.4, tz, ta)
    for k, v in parts.items():
        if v:
            mesh_objects("Arena_" + k.replace(":", "_"), v)
    hb_build_service_vehicles(rng_)
    cparts = hb_new_parts("stahl", "e:banner", "e:menge", "e:flagge")
    total = 0
    for k, (pa, pb, side) in enumerate(HB["crowd_lines"]):
        total += hb_crowd_line(cparts, pa, pb, side, k)
    for key, v in cparts.items():
        if v:
            objs = mesh_objects("Zuschauer_" + key.replace(":", "_"), v)
            if key == "e:menge":
                event_decals.extend(objs)
    print("DIORAMA Zuschauerfelder:", total)
    hb_build_masts()
    hb_build_stands()
    hb_build_pit_cars()


def theme_bake_hidden():
    return ["Hafenwasser"]


def hb_fix_vertex_colors():
    """Der glTF-Export (Blender 4.5) verliert die Vertexfarben, solange kein aktives Farbattribut gesetzt ist: Gewichte des Boden-Shaders und
    Tiefe des Wassers kämen sonst als Weiß an. Hier wird das einzige Attribut je Netz aktiv und zum Vorgabe-Attribut gemacht."""
    fixed = 0
    for o in bpy.data.objects:
        if o.type != "MESH":
            continue
        ca = o.data.color_attributes
        if len(ca) == 0:
            continue
        try:
            ca.active_color = ca[0]
            ca.default_color_name = ca[0].name
            ca.render_color_index = 0
            fixed += 1
        except Exception as err:
            print("DIORAMA Vertexfarbe nicht setzbar:", o.name, err)
    print("DIORAMA Vertexfarben aktiviert:", fixed)


def theme_layout(layout):
    hb_fix_vertex_colors()
    hb_paint_ao(HB.get("wheel_tracks", []))



# ---------------------------------------------------------------- Containerfelder: Planung (Raster aus Reihen und Buchten, Gassen dazwischen)
HB_L40, HB_L20, HB_CW, HB_CH = 12.192, 6.058, 2.438, 2.591
HB_PALETTE = [((0.06, 0.14, 0.34), 2.0), ((0.10, 0.28, 0.52), 2.0), ((0.38, 0.58, 0.78), 1.0), ((0.62, 0.10, 0.08), 3.0), ((0.50, 0.20, 0.12), 2.0),
              ((0.86, 0.40, 0.08), 1.5), ((0.90, 0.72, 0.12), 1.0), ((0.10, 0.36, 0.20), 2.0), ((0.08, 0.38, 0.40), 1.0), ((0.52, 0.54, 0.55), 2.0),
              ((0.86, 0.87, 0.85), 1.5), ((0.38, 0.22, 0.12), 1.0), ((0.15, 0.16, 0.17), 1.0)]


def hb_pick_color(rng_):
    tot = sum(w for _c, w in HB_PALETTE)
    t = rng_.uniform(0, tot)
    for c, w in HB_PALETTE:
        t -= w
        if t <= 0:
            return c
    return HB_PALETTE[0][0]


def hb_plan_field(rect, axis="x", rows_per_block=6, bays_per_block=3, lane_across=5.6, lane_along=6.2, density=0.9, tiers=(1, 4), margin=3.5, seed=0,
                  empty_marks=True, tier_scale=18.0):
    """Container-Stapel in einem Rechteck auslegen. axis "x": Container liegen längs der x-Achse. Reihen (quer) zu je rows_per_block, dann
    eine Querstraße lane_across; Buchten (längs) zu je bays_per_block, dann lane_along. Stapelhöhe folgt einem weichen Rauschfeld (Blöcke mit
    Höhenverlauf), Lücken entstehen durch density. Jeder Stapel wird auf Fahrschlauch-Abstand (margin) und Überschneidung geprüft."""
    xa, za, xb, zb = rect
    rng_ = random.Random(seed)
    a0, a1, b0, b1 = (xa, xb, za, zb) if axis == "x" else (za, zb, xa, xb)
    pitch_a, pitch_b = HB_L40 + 0.5, HB_CW + 0.32
    placed_n = 0
    b = b0 + HB_CW / 2
    row = 0
    while b + HB_CW / 2 <= b1:
        if row > 0 and row % rows_per_block == 0:
            lb0 = b - pitch_b + HB_CW / 2 + 0.25
            b += lane_across
            HB["lanes"].append((axis, a0, a1, lb0, b - HB_CW / 2 - 0.25, True))
            if b + HB_CW / 2 > b1:
                break
        a = a0
        bay = 0
        while a + HB_L40 <= a1:
            if bay > 0 and bay % bays_per_block == 0:
                la0 = a - 0.5 + 0.25
                a += lane_along
                if row == 0:
                    HB["lanes"].append((axis, la0, a - 0.25, b0, b1, False))
                if a + HB_L40 > a1:
                    break
            ac, bc = a + HB_L40 / 2, b
            cx, cz = (ac, bc) if axis == "x" else (bc, ac)
            ux, uz = (1.0, 0.0) if axis == "x" else (0.0, 1.0)
            hx, hz = HB_L40 / 2, HB_CW / 2
            nz = hb_vnoise(cx, cz, tier_scale, seed * 13.0, seed * 7.0)
            present = rng_.random() < density * (0.72 + 0.28 * hb_vnoise(cx, cz, 26.0, seed * 3.0, 17.0))
            if present:
                n_t = int(min(tiers[1], max(tiers[0], round(tiers[0] + nz * (tiers[1] - tiers[0] + 0.6) + rng_.uniform(-0.7, 0.7)))))
                kind = "20" if rng_.random() < 0.28 else "40"
                parts_c = [(0.0, HB_L40 / 2)] if kind == "40" else [(-HB_L20 / 2 - 0.15, HB_L20 / 2), (HB_L20 / 2 + 0.15, HB_L20 / 2)]
                ok = hb_solid(cx, cz, ux, uz, hx, hz, n_t * HB_CH, "mauer", margin=margin, pad=0.12)
                recs = []
                if ok:
                    recs = parts_c
                    HB["slots"].append((cx, cz, ux, uz, hx, hz, True))
                else:
                    # Ganzer Platz nicht frei: einzelne 20-Fuß-Container in den Hälften versuchen
                    kind = "20"
                    for off in (-HB_L20 / 2 - 0.15, HB_L20 / 2 + 0.15):
                        if rng_.random() < 0.85 and hb_solid(cx + ux * off, cz + uz * off, ux, uz, HB_L20 / 2, hz, n_t * HB_CH, "mauer", margin=margin, pad=0.12):
                            recs.append((off, HB_L20 / 2))
                    if recs:
                        HB["slots"].append((cx, cz, ux, uz, hx, hz, True))
                if recs:
                    same = rng_.random() < 0.55
                    base_col = hb_pick_color(rng_)
                    for off, half in recs:
                        cols = [base_col if same else hb_pick_color(rng_) for _ in range(n_t)]
                        HB["stacks"].append({"c": (cx + ux * off, cz + uz * off), "u": (ux, uz), "hx": half, "hz": hz, "tiers": n_t, "colors": cols,
                                             "door": rng_.random() < 0.5, "seed": rng_.randrange(1 << 20)})
                    placed_n += 1
            else:
                if hb_free(cx, cz, ux, uz, hx, hz, margin, 0.1):
                    HB["slots"].append((cx, cz, ux, uz, hx, hz, False))
            a += pitch_a
            bay += 1
        b += pitch_b
        row += 1
    return placed_n


def hb_build_pad_raster():
    """Betonflächen unter den Containerfeldern (Raster 0,5 m, weich), für die Gewichte des Bodens."""
    step = 0.5
    nx, nz = int(math.ceil((x1 - x0) / step)) + 1, int(math.ceil((z1 - z0) / step)) + 1
    g = np.zeros((nz, nx), np.float32)
    for (cx, cz, ux, uz, hx, hz, _stack) in HB["slots"]:
        if abs(ux) > 0.5:
            ex, ez = hx + 0.9, hz + 0.9
        else:
            ex, ez = hz + 0.9, hx + 0.9
        i0, i1 = int(max(0, (cx - ex - x0) / step)), int(min(nx, (cx + ex - x0) / step + 1))
        j0, j1 = int(max(0, (cz - ez - z0) / step)), int(min(nz, (cz + ez - z0) / step + 1))
        g[j0:j1, i0:i1] = 1.0
    for (ax0_, az0_, ax1_, az1_) in HB["conc_rects"]:
        i0, i1 = int(max(0, (ax0_ - x0) / step)), int(min(nx, (ax1_ - x0) / step + 1))
        j0, j1 = int(max(0, (az0_ - z0) / step)), int(min(nz, (az1_ - z0) / step + 1))
        g[j0:j1, i0:i1] = 1.0
    HB["pad"] = ndi_blur(g, 2.4)                                   # breiter Übergang: keine diagonalen Dreieckskanten der 1-m-Zellen
    HB["pad_step"] = step


def ndi_blur(a, sigma):
    """Gaußunschärfe ohne scipy (Blender bringt es nicht mit): getrennte 1D-Faltung."""
    r = int(math.ceil(sigma * 3))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    out = np.apply_along_axis(lambda m: np.convolve(m, k, mode="same"), 1, a)
    return np.apply_along_axis(lambda m: np.convolve(m, k, mode="same"), 0, out).astype(np.float32)


def hb_pad_at(X, Z):
    g = HB["pad"]
    step = HB["pad_step"]
    i = np.clip(((np.asarray(X, float) - x0) / step).astype(int), 0, g.shape[1] - 1)
    j = np.clip(((np.asarray(Z, float) - z0) / step).astype(int), 0, g.shape[0] - 1)
    return g[j, i]


# ---------------------------------------------------------------- Container: Geometrie
def hb_lum(c):
    return (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2])


def hb_cont_v(var):
    """v-Bereich einer Seitenwand-Variante im Atlas container_seite.png (vier Streifen übereinander, Variante 0 unten)."""
    return var * 0.25 + 0.004, (var + 1) * 0.25 - 0.004


def hb_weather_color(col_lin, r2):
    """Vertexfarbe eines Containers mit Verwitterung: ausgeblichener Lack (zum Grau hin, heller), je Container andere Stärke und leichte Tonabweichung."""
    fade = r2.random() ** 2.2 * 0.5                                    # meist kaum, selten stark ausgeblichen
    g = hb_lum(col_lin)
    base = [v * 1.18 * r2.uniform(0.9, 1.06) for v in col_lin]
    out = [b * (1.0 - fade) + (g * 1.25 + 0.03) * fade for b in base]
    return tuple(min(1.6, max(0.0, v)) for v in out)


def hb_build_containers(rng_):
    """Alle geplanten Stapel als Netz: Längsseiten (Wellblech), Stirnseiten (Türen / glatt), Dach. Farbe über die Vertexfarbe."""
    side, door, roof = [], [], []
    gy = GROUND_Y
    for st in HB["stacks"]:
        cx, cz = st["c"]
        ux, uz = st["u"]
        vx, vz = -uz, ux
        hx, hz = st["hx"], st["hz"]
        r2 = random.Random(st["seed"])
        for t in range(st["tiers"]):
            col_s = hb_lin(st["colors"][t])
            lum_ = hb_lum(st["colors"][t])
            col = hb_weather_color(col_s, r2)
            var = r2.randrange(4)                                   # Variante der Seitenwand im Atlas (Rost, Beulen, Ausbesserung)
            v0, v1 = hb_cont_v(var)
            y0 = gy + t * HB_CH
            y1 = y0 + HB_CH
            lo = 0.55 if t == 0 else 0.86
            c_lo = tuple(v * lo for v in col)

            def P(a, b, y):
                return (cx + ux * a + vx * b, cz + uz * a + vz * b, y)
            u_off = r2.random() * 3.0
            ln = 2 * hx
            for (b, nrm) in ((-hz, (-vx, -vz)), (hz, (vx, vz))):
                a_s, a_e = (-hx, hx) if b < 0 else (hx, -hx)
                hb_quad(side, "cont_seite", [P(a_s, b, y0), P(a_e, b, y0), P(a_e, b, y1), P(a_s, b, y1)],
                        [(u_off, v0), (u_off + ln / 2.0, v0), (u_off + ln / 2.0, v1), (u_off, v1)], nrm, [c_lo, c_lo, col, col])
            # Stirnseiten: eine mit Türen (Atlas links/rechts nach Helligkeit), die andere glatt wie die Längsseite
            for (a, sgn) in ((hx, 1), (-hx, -1)):
                nrm = (ux * sgn, uz * sgn)
                is_door = (sgn > 0) == st["door"]
                if is_door:
                    ua = 0.0 if lum_ > 0.18 else 0.5
                    pts = [P(a, -hz * sgn, y0), P(a, hz * sgn, y0), P(a, hz * sgn, y1), P(a, -hz * sgn, y1)]
                    hb_quad(door, "cont_tuer", pts, [(ua, 0), (ua + 0.5, 0), (ua + 0.5, 1), (ua, 1)], nrm, [c_lo, c_lo, col, col])
                else:
                    pts = [P(a, -hz * sgn, y0), P(a, hz * sgn, y0), P(a, hz * sgn, y1), P(a, -hz * sgn, y1)]
                    hb_quad(side, "cont_seite", pts, [(0, v0), (hz * 2 / 2.0, v0), (hz * 2 / 2.0, v1), (0, v1)], nrm, [c_lo, c_lo, col, col])
            if t == st["tiers"] - 1:
                ct = tuple(v * 0.98 for v in col)
                hb_quad(roof, "cont_dach", [P(-hx, -hz, y1), P(hx, -hz, y1), P(hx, hz, y1), P(-hx, hz, y1)],
                        [(0, 0), (ln / 2.0, 0), (ln / 2.0, hz * 2 / 2.0), (0, hz * 2 / 2.0)], None, [ct] * 4)
    n_t = sum(s["tiers"] for s in HB["stacks"])
    for name, parts in (("Container_seite", side), ("Container_tuer", door), ("Container_dach", roof)):
        if parts:
            mesh_object(name, parts)
    print("DIORAMA Container:", n_t, "in", len(HB["stacks"]), "Stapeln (Teile:", len(side) + len(door) + len(roof), ")")


def hb_slot_marks(dec_white):
    """Leere Stellplätze: weiße Eckwinkel (Container-Buchtmarkierung)."""
    rng_ = HB["rng"]
    n = 0
    for (cx, cz, ux, uz, hx, hz, stack) in HB["slots"]:
        if stack:
            continue
        vx, vz = -uz, ux
        for sa in (-1, 1):
            for sb in (-1, 1):
                ca, cb = sa * (hx + 0.15), sb * (hz + 0.1)
                px, pz = cx + ux * ca + vx * cb, cz + uz * ca + vz * cb
                wear = rng_.uniform(0.55, 1.0)
                for (da, db, ln_) in ((-sa, 0, 0.9), (0, -sb, 0.9)):
                    ex, ez = px + (ux * da + vx * db) * ln_, pz + (uz * da + vz * db) * ln_
                    hb_strip(dec_white, "linie", px - (ux * da + vx * db) * 0.06, pz - (uz * da + vz * db) * 0.06, ex, ez, 0.12, GROUND_Y + 0.004, (wear, wear, wear))
        n += 1
    return n


# ---------------------------------------------------------------- Gebäude und Fahrzeuge: Planung
def hb_plan_buildings():
    """Hallen, Büro, Tanks und Lkw-Reihen vormerken (belegen vor den Containerfeldern). HB["buildings"]: Einträge mit Typ und Maßen."""
    B = HB["buildings"]

    def add_building(kind, cx, cz, ux, uz, hx, hz, height, **kw):
        n = math.hypot(ux, uz)
        ux, uz = ux / n, uz / n
        if kind == "office":                    # place_house trägt sein Hindernis selbst ein
            if not hb_free(cx, cz, ux, uz, hx, hz, 3.0, 0.5):
                print("DIORAMA Gebäude", kind, "nicht platzierbar:", (cx, cz))
                return False
            hb_occupy(cx, cz, ux, uz, hx, hz)
        elif not hb_solid(cx, cz, ux, uz, hx, hz, height, "mauer", margin=3.0, pad=0.5):
            print("DIORAMA Gebäude", kind, "nicht platzierbar:", (cx, cz))
            return False
        B.append(dict(kind=kind, c=(cx, cz), u=(ux, uz), hx=hx, hz=hz, **kw))
        HB["conc_rects"].append((cx - hx - 6.0, cz - hz - 6.0, cx + hx + 6.0, cz + hz + 6.0))
        return True
    if not IS_ARENA:
        add_building("hall", 41.0, 55.0, 1.0, 0.0, 22.0, 10.0, 8.6, length=44.0, depth=20.0, front=-1, docks=6, number=True, seed=3,
                     wall=(0.58, 0.66, 0.72), roof=(0.72, 0.73, 0.74), solar=True)
        add_building("hall", -22.0, 56.5, 1.0, 0.0, 11.5, 6.5, 7.4, length=23.0, depth=13.0, front=-1, docks=3, number=False, seed=5,
                     wall=(0.78, 0.74, 0.62), roof=(0.55, 0.57, 0.6), h_eave=5.2, h_ridge=6.8)
        add_building("office", 3.0, 57.0, 1.0, 0.0, 11.2, 6.4, 12.0, w=22.4, d=12.8, floors=3, seed=9, front=(0.0, -1.0))
        add_building("tank", -50.0, 57.0, 1.0, 0.0, 5.0, 5.0, 9.0, r=5.0, h=9.0, col=(0.88, 0.88, 0.86))


# ---------------------------------------------------------------- Gesamtplanung (läuft in theme_materials: nur reines Python)
def hb_plan_layout():
    HB.update(siding=None, barrier_rows=[], signs=[], clutter=[], stackers=[], trucks=[], boxtrucks=[], service=[], cars=[], wheel_tracks=[], rubber=[],
              smoke=[], donuts=[], corners=[], paddock_items=[], tower=None, crowd_lines=[], lamps=[], hull=None, tug=None)
    HB["stacks"], HB["slots"], HB["solids"], HB["circles"], HB["conc_rects"] = [], [], [], [], []
    HB["lanes"] = []
    HB["buildings"] = []
    hb_occupy_props()
    hb_lv_plan()
    hb_plan_lamps()
    info = hb_crane_rails() if not IS_ARENA else None
    HB["crane"] = info
    basin = hb_basin_rect()
    HB["basin"] = basin
    if info:
        xa, xb = min(info["xs"]) - 38.0, max(info["xs"]) + 30.0
        zs, zl = info["z_sea"], info["z_land"]
        hb_occupy((xa + xb) / 2, (zs + zl) / 2, 1.0, 0.0, (xb - xa) / 2 + 1.5, (zl - zs) / 2 + 1.8)
    if basin:
        bx0, bz0, bx1, bz1 = basin
        hb_occupy((bx0 + bx1) / 2, (bz0 + bz1) / 2, 1.0, 0.0, (bx1 - bx0) / 2 + 3.0, (bz1 - bz0) / 2 + 3.0)
    if IS_ARENA:
        hb_plan_arena()
        return
    hb_portal_plan(0.0, cantilever=True, clear=3.6)          # Harbour Run: Pylon 7,1 m neben der Mitte (Feldtest: Gegner kurz vor dem Ziel)
    hb_plan_buildings()
    hb_plan_barriers()
    hb_plan_siding()
    # Container-Felder (Rechteck, Achse, Reihen je Block, Buchten je Block, Gasse quer, Gasse längs, Dichte, Stapelhöhen, Samen)
    fields = [
        ((-58, -22, 56, 22), "x", 5, 3, 5.4, 6.4, 0.80, (1, 4), 11),
        ((22, -28.5, 66, -9), "x", 5, 2, 5.4, 6.4, 0.85, (1, 4), 12),
        ((69, -39, 77.0, 38), "z", 3, 5, 5.6, 6.0, 0.85, (1, 3), 13),
        ((84.2, -39, 92.5, 38), "z", 3, 5, 5.6, 6.0, 0.85, (1, 3), 17),
        ((-96, -39, -73, 36), "z", 4, 5, 5.6, 6.0, 0.85, (1, 3), 14),
        ((-96, 38, -66, 63), "x", 4, 3, 5.4, 6.4, 0.85, (1, 3), 15),
        ((70, 38, 92.5, 63), "x", 4, 2, 5.4, 6.4, 0.85, (1, 3), 16),
    ]
    for rect, axis, rows, bays, la, lb, dens, tiers, seed in fields:
        n = hb_plan_field(rect, axis, rows, bays, la, lb, dens, tiers, margin=2.6, seed=seed)
        print("DIORAMA Containerfeld", rect, ":", n, "Stapel")
    hb_plan_vehicles()
    if HB_LV.get("straddle"):
        HB["straddles"].append(HB_LV["straddle"])                      # Portalhubwagen in der Gasse unter dem Sprung
    hb_plan_cars()
    hb_plan_clutter()
    hb_plan_signs()
    hb_plan_wheel_tracks()
    HB["corners"] = hb_corners()
    HB["donuts"] = []
    hb_plan_rubber(0.45)
    hb_plan_oil()
    hb_plan_yard_masts()


# ---------------------------------------------------------------- Lokale Bezugssysteme und Einzelteile (Räder, Wandflächen)
class HbFrame:
    """Lokales System: Ursprung (cx, cz), u = Längsrichtung, v = quer (links von u). a längs, b quer, y absolut."""

    def __init__(self, cx, cz, ux, uz):
        n = math.hypot(ux, uz) or 1.0
        self.cx, self.cz, self.ux, self.uz = cx, cz, ux / n, uz / n
        self.vx, self.vz = -self.uz, self.ux

    def p(self, a, b, y):
        return (self.cx + self.ux * a + self.vx * b, self.cz + self.uz * a + self.vz * b, y)

    def d(self, da, db):
        return (self.ux * da + self.vx * db, self.uz * da + self.vz * db)


def hb_wall(out, key, fr, a0, b0, a1, b1, y0, y1, col0=(1, 1, 1), col1=(1, 1, 1), tile_u=2.0, tile_v=2.0, u_off=0.0, flip_uv=False, facing=None, v_off=0.0):
    """Senkrechte Wand zwischen zwei Punkten des lokalen Systems; facing = (da, db) lokale Blickrichtung."""
    ln = math.hypot(a1 - a0, b1 - b0)
    fa = facing if facing is not None else (-(b1 - b0), (a1 - a0))
    ex, ez = fr.d(fa[0], fa[1])
    if flip_uv:
        uvs = [(y0 / tile_v + v_off, u_off), (y0 / tile_v + v_off, u_off + ln / tile_u), (y1 / tile_v + v_off, u_off + ln / tile_u), (y1 / tile_v + v_off, u_off)]
    else:
        uvs = [(u_off, y0 / tile_v + v_off), (u_off + ln / tile_u, y0 / tile_v + v_off), (u_off + ln / tile_u, y1 / tile_v + v_off), (u_off, y1 / tile_v + v_off)]
    hb_quad(out, key, [fr.p(a0, b0, y0), fr.p(a1, b1, y0), fr.p(a1, b1, y1), fr.p(a0, b0, y1)], uvs, (ex, ez), [col0, col0, col1, col1])


def hb_wheel(out, fr, a, b, y_c, r, width, col=(0.04, 0.04, 0.045), sides=8, hub=True, key="gummi", both_sides=False):
    """Rad mit Achse quer (b), rollt längs (a): Lauffläche aus Vierecken, Seitenscheibe mit Nabe nur auf der Außenseite (b > 0: +, b < 0: -;
    both_sides für Räder, die beidseits sichtbar sind). Weniger Dreiecke als zuvor: Innenseiten verschwinden unter dem Fahrzeug.
    Zwillingsreifen werden als ein breites Rad (width = beide Reifen) gebaut."""
    ring = [(a + r * math.cos(2 * math.pi * k / sides), y_c + r * math.sin(2 * math.pi * k / sides)) for k in range(sides)]
    for k in range(sides):
        (a0, y0), (a1, y1) = ring[k], ring[(k + 1) % sides]
        mid = (0.5 * (a0 + a1) - a, 0.5 * (y0 + y1) - y_c)
        hb_quad(out, key, [fr.p(a0, b - width / 2, max(y0, GROUND_Y)), fr.p(a1, b - width / 2, max(y1, GROUND_Y)), fr.p(a1, b + width / 2, max(y1, GROUND_Y)), fr.p(a0, b + width / 2, max(y0, GROUND_Y))],
                [(0, 0), (1, 0), (1, 1), (0, 1)], fr.d(mid[0], 0.0) if abs(mid[0]) > 1e-6 else (0.0, 0.0), [col] * 4)
    faces = (-1, 1) if (both_sides or abs(b) < 1e-3) else ((1,) if b > 0 else (-1,))
    for side_ in faces:
        bb = b + side_ * width / 2
        hb_quad(out, key, [fr.p(a0_, bb, max(y0_, GROUND_Y)) for a0_, y0_ in ring], [(0.5, 0.5)] * len(ring), fr.d(0.0, side_), [tuple(v * 1.6 for v in col)] * len(ring))
        if hub and (width < 0.5 or r > 0.7):                                     # Zwillingsreifen (breit, klein) ohne Nabe: wenige Dreiecke, von oben nicht zu sehen
            hr = r * 0.55
            hring = [(a + hr * math.cos(2 * math.pi * k / sides), y_c + hr * math.sin(2 * math.pi * k / sides)) for k in range(sides)]
            hb_quad(out, "stahl_dunkel", [fr.p(a0_, bb + side_ * 0.01, max(y0_, GROUND_Y)) for a0_, y0_ in hring], [(0.5, 0.5)] * len(hring), fr.d(0.0, side_), [(1, 1, 1)] * len(hring))


def hb_box_l(out, key, fr, a0, a1, b0, b1, y0, y1, col=(1, 1, 1), shade=(0.8, 1.0), tile=2.0, top_key=None):
    """Quader im lokalen System (a, b Bereiche): Wrapper um hb_cuboid."""
    ca, cb = (a0 + a1) / 2, (b0 + b1) / 2
    cx, cz, _y = fr.p(ca, cb, 0)
    hb_cuboid(out, cx, cz, fr.ux, fr.uz, (a1 - a0) / 2, (b1 - b0) / 2, y0, y1, top_key or key, key, key, col, shade, tile, True)


# ---------------------------------------------------------------- Container auf Fahrzeugen: gemeinsame Einzelteile
def hb_container_one(lists, cx, cz, ux, uz, hx, hz, y0, color_srgb, door_front=True, shade_lo=0.86, seed=1, top=True):
    """Ein Container (wie in hb_build_containers) in die Listen (side, door, roof)."""
    side, door, roof = lists
    r2 = random.Random(seed)
    vx, vz = -uz, ux
    col_s = hb_lin(color_srgb)
    lum_ = hb_lum(color_srgb)
    col = hb_weather_color(col_s, r2)
    v0, v1 = hb_cont_v(r2.randrange(4))
    c_lo = tuple(v * shade_lo for v in col)
    y1 = y0 + HB_CH

    def P(a, b, y):
        return (cx + ux * a + vx * b, cz + uz * a + vz * b, y)
    ln = 2 * hx
    u_off = r2.random() * 3.0
    for (b, nrm) in ((-hz, (-vx, -vz)), (hz, (vx, vz))):
        a_s, a_e = (-hx, hx) if b < 0 else (hx, -hx)
        hb_quad(side, "cont_seite", [P(a_s, b, y0), P(a_e, b, y0), P(a_e, b, y1), P(a_s, b, y1)],
                [(u_off, v0), (u_off + ln / 2.0, v0), (u_off + ln / 2.0, v1), (u_off, v1)], nrm, [c_lo, c_lo, col, col])
    for (a, sgn) in ((hx, 1), (-hx, -1)):
        nrm = (ux * sgn, uz * sgn)
        pts = [P(a, -hz * sgn, y0), P(a, hz * sgn, y0), P(a, hz * sgn, y1), P(a, -hz * sgn, y1)]
        if (sgn > 0) == door_front:
            ua = 0.0 if lum_ > 0.18 else 0.5
            hb_quad(door, "cont_tuer", pts, [(ua, 0), (ua + 0.5, 0), (ua + 0.5, 1), (ua, 1)], nrm, [c_lo, c_lo, col, col])
        else:
            hb_quad(side, "cont_seite", pts, [(0, v0), (hz, v0), (hz, v1), (0, v1)], nrm, [c_lo, c_lo, col, col])
    if top:
        ct = tuple(v * 0.98 for v in col)
        hb_quad(roof, "cont_dach", [P(-hx, -hz, y1), P(hx, -hz, y1), P(hx, hz, y1), P(-hx, hz, y1)], [(0, 0), (ln / 2.0, 0), (ln / 2.0, hz), (0, hz)], None, [ct] * 4)


# ---------------------------------------------------------------- Van Carrier (Portalhubwagen): fährt über den Container, trägt ihn zwischen den Beinen
def hb_straddle(lists, cx, cz, ux, uz, body_col=(0.9, 0.62, 0.05), cont_col=None, seed=1):
    """Portalhubwagen (Straddle Carrier): vier Stützen mit je einem Rad unten, Längs- und Querträger oben, Fahrerkabine auf einem Träger, Spreader
    über dem Container, der zwischen den Stützen hängt (ragt vorn und hinten über). Fahrtrichtung +u; Länge 8 m (Stützen), Breite 4,6 m, Höhe 6,4 m."""
    fr = HbFrame(cx, cz, ux, uz)
    gy = GROUND_Y
    lack, dunkel, glas, stahl = lists["lack"], lists["stahl_dunkel"], lists["glas"], lists["stahl"]
    col = hb_lin(body_col)
    blk = hb_lin((0.06, 0.06, 0.07))
    top = gy + 4.5
    for sa in (-1, 1):
        for sb in (-1, 1):
            a, b = sa * 3.2, sb * 2.0
            hb_box_l(lack, "lack", fr, a - 0.3, a + 0.3, b - 0.28, b + 0.28, gy + 0.75, top, col, (0.75, 1.0))              # Stütze
            hb_box_l(dunkel, "stahl_dunkel", fr, a - 0.5, a + 0.5, b - 0.34, b + 0.34, gy + 0.35, gy + 1.2, (0.9, 0.9, 0.92), (1.0, 1.0))  # Radgabel
            hb_wheel(lists["gummi"], fr, a, b + sb * 0.2, gy + 0.55, 0.55, 0.42, sides=10)                                 # Rad (rollt längs)
    for sb in (-1, 1):                                                                                                   # Längsträger
        hb_box_l(lack, "lack", fr, -3.7, 3.7, sb * 2.0 - 0.3, sb * 2.0 + 0.3, top, top + 0.55, col, (0.8, 1.0))
    for a in (-3.2, 0.0, 3.2):                                                                                           # Querträger
        hb_box_l(lack, "lack", fr, a - 0.25, a + 0.25, -2.0, 2.0, top + 0.05, top + 0.45, tuple(v * 0.9 for v in col), (0.85, 1.0))
    for sb in (-1, 1):                                                                                                   # Stützstreben
        for sa in (-1, 1):
            p0, p1 = fr.p(sa * 3.2, sb * 2.0, gy + 2.6), fr.p(sa * 2.4, sb * 2.0, top)
            hb_quad(stahl, "stahl", [p0, p1, (p1[0], p1[1], p1[2] + 0.04), (p0[0], p0[1], p0[2] + 0.04)], [(0, 0), (1, 0), (1, 1), (0, 1)], fr.d(0.0, sb), [(0.7, 0.7, 0.72)] * 4)
    # Fahrerkabine auf dem linken Längsträger am Vorderende, Fenster rundum, Dach, Scheinwerfer
    hb_box_l(lack, "lack", fr, 1.6, 3.6, -2.35, -1.25, top + 0.55, top + 2.0, col, (0.8, 1.0))
    hb_wall(glas, "glas", fr, 3.605, -2.3, 3.605, -1.3, top + 1.0, top + 1.9, facing=(1, 0))
    hb_wall(glas, "glas", fr, 1.7, -2.355, 3.5, -2.355, top + 1.0, top + 1.9, facing=(0, -1))
    hb_wall(glas, "glas", fr, 1.7, -1.245, 3.5, -1.245, top + 1.0, top + 1.9, facing=(0, 1))
    hb_box_l(lack, "lack", fr, 1.5, 3.7, -2.45, -1.15, top + 2.0, top + 2.12, hb_lin((0.3, 0.3, 0.32)), (1.0, 1.0))
    hb_box_l(lack, "lack", fr, 3.6, 3.66, -2.2, -2.0, top + 1.1, top + 1.25, hb_lin((0.96, 0.9, 0.7)), (1.0, 1.0))
    # Container zwischen den Stützen (40 Fuß, ragt vorn und hinten über) und Spreader
    ccol = cont_col if cont_col is not None else (0.5, 0.2, 0.12)
    cx2, cz2, _ = fr.p(0.0, 0.0, 0)
    hb_container_one(lists["container"], cx2, cz2, fr.ux, fr.uz, HB_L40 / 2, HB_CW / 2, gy + 1.15, ccol, door_front=True, seed=seed)
    hb_box_l(dunkel, "stahl_dunkel", fr, -2.6, 2.6, -1.1, 1.1, gy + 1.15 + HB_CH, gy + 1.15 + HB_CH + 0.35, (0.8, 0.8, 0.82), (1.0, 1.0))
    for sa in (-1, 1):
        hb_box_l(stahl, "stahl", fr, sa * 1.6 - 0.1, sa * 1.6 + 0.1, -0.3, 0.3, gy + 1.15 + HB_CH + 0.35, top, (0.7, 0.7, 0.72), (1.0, 1.0))      # Aufhängung
    # Kühlergitter und Rücklicht-Farbtupfer
    hb_box_l(dunkel, "stahl_dunkel", fr, -3.65, -3.55, -1.7, 1.7, top + 0.06, top + 0.5, (0.7, 0.7, 0.72), (1.0, 1.0))


def hb_straddle_rect(cx, cz, ux, uz):
    """Grundfläche des Portalhubwagens samt überstehendem Container: 12,4 x 4,8 m, Mitte im Ursprung."""
    n = math.hypot(ux, uz) or 1.0
    return cx, cz, ux / n, uz / n, 6.2, 2.4


# ---------------------------------------------------------------- Sattelzug mit Container
def hb_truck(lists, cx, cz, ux, uz, cab_col=(0.85, 0.85, 0.83), cont_col=None, seed=1, with_container=True, y_base=None):
    """Sattelzugmaschine (Fahrerhaus mit Windschutzscheibe, Dachspoiler, Tank, Auspuff) mit Containerchassis; lists = dict key -> Teilliste.
    Vorderseite = +u. Länge etwa 19 m, Breite 2,55 m."""
    y_base = GROUND_Y if y_base is None else y_base
    fr = HbFrame(cx, cz, ux, uz)
    r2 = random.Random(seed)
    lack, dunkel, glas, stahl = lists["lack"], lists["stahl_dunkel"], lists["glas"], lists["stahl"]
    cc = tuple(v for v in hb_lin(cab_col))
    # Rahmen der Zugmaschine
    hb_box_l(dunkel, "stahl_dunkel", fr, 0.5, 9.0, -0.55, 0.55, y_base + 0.55, y_base + 0.95, (1, 1, 1))
    # Fahrerhaus (Frontlenker): Karosserie, Windschutzscheibe, Seitenscheiben, Dachspoiler, Kühlergrill, Stoßstange
    hb_box_l(lack, "lack", fr, 6.2, 8.9, -1.27, 1.27, y_base + 0.95, y_base + 3.0, cc, (0.7, 1.0))
    hb_wall(glas, "glas", fr, 8.905, -1.15, 8.905, 1.15, y_base + 1.85, y_base + 2.75, (1, 1, 1), (1, 1, 1), facing=(1, 0))
    for sgn in (-1, 1):
        hb_wall(glas, "glas", fr, 6.8, sgn * 1.275, 8.55, sgn * 1.275, y_base + 1.9, y_base + 2.65, (1, 1, 1), (1, 1, 1), facing=(0, sgn))
    hb_box_l(lack, "lack", fr, 6.2, 7.7, -1.1, 1.1, y_base + 3.0, y_base + 3.55, tuple(v * 0.95 for v in cc), (1.0, 1.0))
    hb_box_l(dunkel, "stahl_dunkel", fr, 8.86, 9.1, -1.2, 1.2, y_base + 0.5, y_base + 1.1, (1, 1, 1))
    hb_wall(dunkel, "stahl_dunkel", fr, 8.91, -0.9, 8.91, 0.9, y_base + 1.15, y_base + 1.75, (0.7, 0.7, 0.72), (0.7, 0.7, 0.72), facing=(1, 0))
    for sgn in (-1, 1):
        hb_wall(lack, "lack", fr, 8.915, sgn * 1.0, 8.915, sgn * 1.2, y_base + 1.1, y_base + 1.3, (1.3, 1.25, 1.0), (1.3, 1.25, 1.0), facing=(1, 0))       # Scheinwerfer
    # Dieseltank, Auspuffrohr, Batteriekasten
    hb_prism(stahl, fr.p(3.0, 1.2, 0)[0], fr.p(3.0, 1.2, 0)[1], 0.36, y_base + 0.55, y_base + 1.0, "stahl", (1, 1, 1), 8, tile=1.0)
    ex_, ez_, _ = fr.p(6.0, -1.35, 0)
    hb_prism(stahl, ex_, ez_, 0.07, y_base + 0.9, y_base + 3.4, "stahl", (0.9, 0.9, 0.9), 6, tile=1.0)
    # Sattelplatte und Achsen
    cx_, cz_, _ = fr.p(3.0, 0.0, 0)
    hb_prism(dunkel, cx_, cz_, 0.55, y_base + 0.95, y_base + 1.1, "stahl_dunkel", (0.9, 0.9, 0.9), 10, tile=1.0)
    for a_ax in (7.5,):
        for sgn in (-1, 1):
            hb_wheel(lists["gummi"], fr, a_ax, sgn * 1.0, y_base + 0.52, 0.52, 0.32)
    for a_ax in (2.2, 3.6):
        for sgn in (-1, 1):
            hb_wheel(lists["gummi"], fr, a_ax, sgn * 1.17, y_base + 0.52, 0.52, 0.68)          # Zwillingsreifen als ein breites Rad
        hb_box_l(dunkel, "stahl_dunkel", fr, a_ax - 0.5, a_ax + 0.5, -1.2, 1.2, y_base + 0.5, y_base + 0.66, (1, 1, 1))
    # Container-Chassis (Sattelauflieger): zwei Längsträger, Querträger, Dreifachachse
    hb_box_l(dunkel, "stahl_dunkel", fr, -9.4, 3.2, -1.0, -0.7, y_base + 1.0, y_base + 1.3, (1, 1, 1))
    hb_box_l(dunkel, "stahl_dunkel", fr, -9.4, 3.2, 0.7, 1.0, y_base + 1.0, y_base + 1.3, (1, 1, 1))
    for a_c in (-8.8, -6.0, -3.2, -0.4, 2.4):
        hb_box_l(dunkel, "stahl_dunkel", fr, a_c - 0.1, a_c + 0.1, -1.1, 1.1, y_base + 1.0, y_base + 1.2, (1, 1, 1))
    for a_ax in (-5.0, -6.3, -7.6):
        for sgn in (-1, 1):
            hb_wheel(lists["gummi"], fr, a_ax, sgn * 1.14, y_base + 0.5, 0.5, 0.62)
        hb_box_l(dunkel, "stahl_dunkel", fr, a_ax - 0.15, a_ax + 0.15, -1.15, 1.15, y_base + 0.46, y_base + 0.58, (1, 1, 1))
    for sgn in (-1, 1):
        hb_box_l(dunkel, "stahl_dunkel", fr, -8.2, -4.4, sgn * 1.0, sgn * 1.2, y_base + 0.95, y_base + 1.05, (1, 1, 1))       # Kotflügel/Schutzbleche
    hb_box_l(dunkel, "stahl_dunkel", fr, -9.55, -9.35, -1.1, 1.1, y_base + 0.55, y_base + 0.8, (1, 1, 1))                         # Unterfahrschutz
    for sgn in (-1, 1):
        hb_box_l(lack, "lack", fr, -9.62, -9.5, sgn * 0.8, sgn * 1.0, y_base + 0.85, y_base + 0.98, (1.5, 0.05, 0.05))             # Rückleuchten (nur Farbe, kein Glühen)
    if with_container and cont_col is not None and "container" in lists:
        cx2, cz2, _ = fr.p(-3.1, 0.0, 0)
        hb_container_one(lists["container"], cx2, cz2, fr.ux, fr.uz, HB_L40 / 2, HB_CW / 2, y_base + 1.2, cont_col, door_front=False, seed=seed)
    return fr


def hb_truck_rect(cx, cz, ux, uz):
    """Grundfläche eines Sattelzugs als Rechteck (Mitte, u, Halbmaße): 19 m x 2,6 m, Mitte 0,2 m hinter dem Ursprung."""
    n = math.hypot(ux, uz) or 1.0
    ux, uz = ux / n, uz / n
    return cx - ux * 0.2, cz - uz * 0.2, ux, uz, 9.5, 1.35


# ---------------------------------------------------------------- Lagerhalle (Stahlhalle mit Trapezblech, Satteldach, Rolltore / Verladetore)
def hb_digit_quads(out, fr, a, b, y, digit, h=0.6, w=0.34, t=0.07, key="linie", col=(1, 1, 1), facing=(0, 1), vertical=True):
    """Ziffer aus Segmenten (Siebensegment, Schablonenschrift) auf einer senkrechten Wand (vertical) oder dem Boden; (a, b) = linke untere Ecke."""
    segs = {0: "abcdef", 1: "bc", 2: "abged", 3: "abgcd", 4: "fgbc", 5: "afgcd", 6: "afgedc", 7: "abc", 8: "abcdefg", 9: "abcdfg"}[int(digit)]
    rects = {"a": (0, h - t, w, h), "b": (w - t, h / 2, w, h), "c": (w - t, 0, w, h / 2), "d": (0, 0, w, t), "e": (0, 0, t, h / 2), "f": (0, h / 2, t, h),
             "g": (0, h / 2 - t / 2, w, h / 2 + t / 2)}
    for s_ in segs:
        r0, s0, r1, s1 = rects[s_]
        if vertical:
            hb_quad(out, key, [fr.p(a + r0, b, y + s0), fr.p(a + r1, b, y + s0), fr.p(a + r1, b, y + s1), fr.p(a + r0, b, y + s1)], [(0, 0), (1, 0), (1, 1), (0, 1)], fr.d(*facing), [col] * 4)
        else:
            hb_quad(out, key, [fr.p(a + r0, b + s0, y), fr.p(a + r1, b + s0, y), fr.p(a + r1, b + s1, y), fr.p(a + r0, b + s1, y)], [(0, 0), (1, 0), (1, 1), (0, 1)], None, [col] * 4)


def hb_number_quads(out, fr, a, b, y, number, h=0.6, w=0.34, gap=0.14, **kw):
    for k, ch in enumerate(str(number)):
        if ch.isdigit():
            hb_digit_quads(out, fr, a + k * (w + gap), b, y, int(ch), h, w, **kw)


def hb_hall(parts, cx, cz, ux, uz, length, depth, h_eave=6.5, h_ridge=8.6, wall_col=(0.62, 0.68, 0.72), roof_col=(0.70, 0.72, 0.74), front=1, n_docks=6,
            number=None, seed=1, dock_col=(0.20, 0.27, 0.34), solar=False):
    """Halle: Längsachse u, Vorderseite (Tore) bei +v * front. parts: dict key -> Liste. Rückgabe: (Mitte, u, Halbmaße) für Belegung."""
    fr = HbFrame(cx, cz, ux, uz)
    r2 = random.Random(seed)
    hx, hz = length / 2, depth / 2
    gy = GROUND_Y
    wc, rc = hb_lin(wall_col), hb_lin(roof_col)
    wc = tuple(v * 1.15 for v in wc)
    rc = tuple(v * 1.15 for v in rc)
    plinth = 1.1
    W, R, B = parts["blech_wand"], parts["blech_dach"], parts["beton"]
    # Sockel aus Beton
    for (a0, b0, a1, b1, fa) in ((-hx, -hz, hx, -hz, (0, -1)), (hx, -hz, hx, hz, (1, 0)), (hx, hz, -hx, hz, (0, 1)), (-hx, hz, -hx, -hz, (-1, 0))):
        hb_wall(B, "beton", fr, a0, b0, a1, b1, gy, gy + plinth, (0.8, 0.8, 0.8), (0.95, 0.95, 0.95), tile_u=3.0, tile_v=3.0, facing=fa)
        hb_wall(W, "blech_wand", fr, a0, b0, a1, b1, gy + plinth, gy + h_eave, tuple(v * 0.8 for v in wc), wc, facing=fa, u_off=r2.random())
    # Giebel (Dreieck oberhalb der Traufe)
    for sgn in (-1, 1):
        a_ = sgn * hx
        fa = (sgn, 0)
        hb_quad(W, "blech_wand", [fr.p(a_, -hz, gy + h_eave), fr.p(a_, hz, gy + h_eave), fr.p(a_, 0, gy + h_ridge)], [(0, 3.2), (depth / 2.0, 3.2), (depth / 4.0, 4.3)], fr.d(*fa), [wc] * 3)
    # Dach: je Seite in Bahnen (Felder) längs, jede mit eigener Helligkeit und Texturversatz (einzelne neu gedeckte, hellere Bleche), Dachrinne,
    # Lichtplatten mit Rahmen und Sprossen, Drehlüfter am First, auf der Südseite ein Feld Solarmodule
    ov = 0.5
    slope_len = math.hypot(hz + ov, h_ridge - h_eave + 0.25)
    n_bay = max(2, int(round(length / 4.0)))
    bay = (length + 2 * ov) / n_bay

    def roof_y(bb):
        return gy + h_ridge - (h_ridge - h_eave + 0.25) * abs(bb) / (hz + ov) + 0.03
    for sgn in (-1, 1):
        for kb in range(n_bay):
            a0, a1 = -hx - ov + kb * bay, -hx - ov + (kb + 1) * bay
            fade = r2.uniform(0.9, 1.04) * (1.10 if r2.random() < 0.14 else 1.0)
            c_lo = tuple(v * 0.92 * fade for v in rc)
            c_hi = tuple(v * fade for v in rc)
            pts = [fr.p(a0, sgn * (hz + ov), gy + h_eave - 0.25), fr.p(a1, sgn * (hz + ov), gy + h_eave - 0.25), fr.p(a1, 0, gy + h_ridge), fr.p(a0, 0, gy + h_ridge)]
            hb_quad(R, "blech_dach", pts, [(a0 / 2.0 + 5.0, 0), (a1 / 2.0 + 5.0, 0), (a1 / 2.0 + 5.0, slope_len / 2.0), (a0 / 2.0 + 5.0, slope_len / 2.0)], None, [c_lo, c_lo, c_hi, c_hi])
        # Dachrinne an der Traufe (dunkles Band) und Fallrohrkästen
        hb_box_l(parts["stahl_dunkel"], "stahl_dunkel", fr, -hx - ov, hx + ov, sgn * (hz + ov) - 0.14, sgn * (hz + ov) + 0.14, gy + h_eave - 0.42, gy + h_eave - 0.2, (0.8, 0.8, 0.82), (1.0, 1.0))
        # Lichtplatten (liegen 3 cm über der Dachhaut) mit dunklem Rahmen und zwei Sprossen quer
        for k in range(int(length // 9)):
            a_c = -hx + 4.5 + k * 9.0
            if abs(a_c) > hx - 2.0:
                continue
            b_in, b_out = hz * 0.22, hz * 0.62
            ww = 1.7
            fq = [fr.p(a_c - ww - 0.14, sgn * (b_out + 0.14), roof_y(b_out + 0.14) - 0.012), fr.p(a_c + ww + 0.14, sgn * (b_out + 0.14), roof_y(b_out + 0.14) - 0.012),
                  fr.p(a_c + ww + 0.14, sgn * (b_in - 0.14), roof_y(b_in - 0.14) - 0.012), fr.p(a_c - ww - 0.14, sgn * (b_in - 0.14), roof_y(b_in - 0.14) - 0.012)]
            hb_quad(parts["stahl_dunkel"], "stahl_dunkel", fq, [(0, 0), (1, 0), (1, 1), (0, 1)], None, [(0.55, 0.55, 0.57)] * 4)
            q = [fr.p(a_c - ww, sgn * b_out, roof_y(b_out)), fr.p(a_c + ww, sgn * b_out, roof_y(b_out)), fr.p(a_c + ww, sgn * b_in, roof_y(b_in)), fr.p(a_c - ww, sgn * b_in, roof_y(b_in))]
            hb_quad(parts["lichtband"], "lichtband", q, [(0, 0), (1, 0), (1, 1), (0, 1)], None, [(0.85, 0.92, 0.95)] * 4)
            for j in (-0.57, 0.57):
                sq = [fr.p(a_c + j - 0.03, sgn * b_out, roof_y(b_out) + 0.004), fr.p(a_c + j + 0.03, sgn * b_out, roof_y(b_out) + 0.004),
                      fr.p(a_c + j + 0.03, sgn * b_in, roof_y(b_in) + 0.004), fr.p(a_c + j - 0.03, sgn * b_in, roof_y(b_in) + 0.004)]
                hb_quad(parts["stahl_dunkel"], "stahl_dunkel", sq, [(0, 0), (1, 0), (1, 1), (0, 1)], None, [(0.6, 0.6, 0.62)] * 4)
    if solar:
        # Solarmodule auf der Südseite (b > 0) zwischen Lichtplatten und Traufe: zwei Reihen, Fugen zeigen das helle Dach als Rahmen
        for row_b0, row_b1 in ((6.9, 8.3), (8.4, 9.8)):
            n_p = int((length - 6.0) / 2.15)
            a_start_p = -n_p * 2.15 / 2
            for kp in range(n_p):
                a0 = a_start_p + kp * 2.15 + 0.04
                a1 = a0 + 2.07
                tone = r2.uniform(0.85, 1.12)
                col_p = (0.9 * tone, 0.95 * tone, 1.2 * tone)
                q = [fr.p(a0, row_b1, roof_y(row_b1) + 0.05), fr.p(a1, row_b1, roof_y(row_b1) + 0.05), fr.p(a1, row_b0, roof_y(row_b0) + 0.05), fr.p(a0, row_b0, roof_y(row_b0) + 0.05)]
                hb_quad(parts["solar"], "solar", q, [(0, 0), (1, 0), (1, 1), (0, 1)], None, [col_p] * 4)
    hb_box_l(parts["stahl"], "stahl", fr, -hx - ov, hx + ov, -0.18, 0.18, gy + h_ridge, gy + h_ridge + 0.3, (0.9, 0.9, 0.92), (1.0, 1.0))          # Firstkappe
    for k in range(int(length // 11)):                                                                                                                  # Drehlüfter
        a_c = -hx + 5.5 + k * 11.0
        vx_, vz_, _ = fr.p(a_c, 0.0, 0)
        hb_prism(parts["stahl"], vx_, vz_, 0.28, gy + h_ridge + 0.3, gy + h_ridge + 0.6, "stahl", (0.8, 0.82, 0.84), 8, tile=1.0)
        hb_prism(parts["stahl"], vx_, vz_, 0.42, gy + h_ridge + 0.6, gy + h_ridge + 1.05, "stahl", (0.85, 0.87, 0.9), 8, r_top=0.46, tile=1.0, cap_col=(0.7, 0.72, 0.75))
    # Vorderseite: Verladetore mit Stoßdämpfern und Vordach
    fb = front * hz
    dock_w, dock_h, pitch = 3.0, 3.6, max(5.0, (length - 8.0) / max(1, n_docks))
    a_start = -hx + (length - pitch * (n_docks - 1)) / 2
    for k in range(n_docks):
        a_c = a_start + k * pitch
        # Torblatt: waagerecht gerippt (UV vertauscht), dunkelblau
        hb_wall(W, "blech_wand", fr, a_c - dock_w / 2, fb + front * 0.04, a_c + dock_w / 2, fb + front * 0.04, gy + 1.2, gy + 1.2 + dock_h, hb_lin(dock_col), hb_lin(dock_col),
                flip_uv=True, facing=(0, front))
        for sgn in (-1, 1):
            hb_box_l(parts["gummi"], "gummi", fr, a_c + sgn * 1.7 - 0.12, a_c + sgn * 1.7 + 0.12, fb, fb + front * 0.35, gy + 0.9, gy + 1.8, (1, 1, 1))     # Torpuffer
        hb_box_l(parts["stahl_dunkel"], "stahl_dunkel", fr, a_c - 1.5, a_c + 1.5, fb, fb + front * 0.12, gy + 1.0, gy + 1.15, (1, 1, 1))
        # Torleuchte über dem Tor: Gehäuse an der Wand, Lichtquelle davor (add_light in theme_scenery)
        hb_box_l(parts["stahl_dunkel"], "stahl_dunkel", fr, a_c - 0.22, a_c + 0.22, fb, fb + front * 0.32, gy + 5.0, gy + 5.28, (0.8, 0.8, 0.82), (0.8, 1.0))
        hb_quad(parts["lack"], "lack", [fr.p(a_c - 0.18, fb + front * 0.33, gy + 5.04), fr.p(a_c + 0.18, fb + front * 0.33, gy + 5.04), fr.p(a_c + 0.18, fb + front * 0.33, gy + 5.24), fr.p(a_c - 0.18, fb + front * 0.33, gy + 5.24)],
                [(0, 0), (1, 0), (1, 1), (0, 1)], fr.d(0.0, front), [(1.5, 1.45, 1.25)] * 4)
        lx_, lz_, _ = fr.p(a_c, fb + front * 0.5, 0)
        HB.setdefault("dock_lights", []).append((lx_, lz_, gy + 5.1))
        if number is not None:
            hb_number_quads(parts["marke"], fr, a_c - 0.34, fb + front * 0.045, gy + 5.0, k + 1, 0.55, 0.3, 0.08, key="linie", facing=(0, front))
    # Vordach über den Toren
    ca, cb = 0.0, fb + front * 1.6
    cxx, czz, _ = fr.p(ca, cb, 0)
    hb_cuboid(parts["blech_dach"], cxx, czz, fr.ux, fr.uz, hx - 1.5, 1.6, gy + 5.45, gy + 5.6, "blech_dach", "stahl_dunkel", "stahl_dunkel", rc, (1.0, 1.0), 2.0, False)
    for k in range(int((length - 3) // 6) + 1):
        a_p = -hx + 1.5 + k * 6.0
        px_, pz_, _ = fr.p(a_p, fb + front * 3.0, 0)
        hb_cuboid(parts["stahl_dunkel"], px_, pz_, fr.ux, fr.uz, 0.07, 0.07, gy, gy + 5.45, "stahl_dunkel", col=(1, 1, 1), tile=1.0, bottom_fade=False)
    # Fallrohre und Personentür an der Stirnseite
    for sgn in (-1, 1):
        hb_wall(parts["stahl_dunkel"], "stahl_dunkel", fr, sgn * (hx + 0.02), -0.6, sgn * (hx + 0.02), 0.6, gy, gy + 2.2, (0.4, 0.4, 0.42), (0.4, 0.4, 0.42), facing=(sgn, 0))
    return (cx, cz, fr.ux, fr.uz, hx + 0.8, hz + 0.8)


# ---------------------------------------------------------------- Tanks, Hallen und Büro bauen
def hb_new_parts(*keys):
    return {k: [] for k in keys}


def hb_build_tank(parts, cx, cz, r, h, col):
    """Stehender Lagertank: Mantel (Vertexfarbe), Dach mit Rand, Leiter, Rohrbrücke; Auffangwanne aus Beton."""
    gy = GROUND_Y
    cc = tuple(v * 1.1 for v in hb_lin(col))
    hb_prism(parts["lack"], cx, cz, r, gy + 0.4, gy + h, "lack", cc, 22, tile=3.0, shade=(0.7, 1.0))
    hb_prism(parts["stahl"], cx, cz, r + 0.04, gy + h - 0.15, gy + h + 0.05, "stahl", (0.8, 0.8, 0.82), 22, tile=3.0, r_top=r + 0.04, cap_col=(0.7, 0.7, 0.72))
    hb_prism(parts["lack"], cx, cz, r * 0.96, gy + h + 0.05, gy + h + 0.45, "lack", cc, 22, r_top=r * 0.55, tile=3.0, cap_col=tuple(v * 0.9 for v in cc))
    hb_prism(parts["beton"], cx, cz, r + 0.3, gy, gy + 0.4, "beton", (0.9, 0.9, 0.9), 22, tile=3.0)
    fr = HbFrame(cx, cz, 1.0, 0.0)
    hb_box_l(parts["stahl_dunkel"], "stahl_dunkel", fr, r - 0.05, r + 0.2, -0.3, 0.3, gy + 0.4, gy + h, (1, 1, 1), (1.0, 1.0))                       # Steigleiter
    hb_box_l(parts["stahl"], "stahl", fr, -0.25, 0.25, -0.25, 0.25, gy + h + 0.45, gy + h + 0.95, (0.9, 0.9, 0.9), (1.0, 1.0))
    # Auffangwanne (Betonmauer, 0,9 m hoch) ringsum
    bw = r + 2.2
    for (a0, a1, b0, b1) in ((-bw, bw, -bw - 0.2, -bw + 0.2), (-bw, bw, bw - 0.2, bw + 0.2), (-bw - 0.2, -bw + 0.2, -bw, bw), (bw - 0.2, bw + 0.2, -bw, bw)):
        hb_box_l(parts["beton"], "beton", fr, a0, a1, b0, b1, gy, gy + 0.9, (0.95, 0.95, 0.95), (0.85, 1.0), 2.5)
    return bw


def hb_build_buildings(rng_, dec_white):
    """Gebäude aus HB["buildings"] erzeugen (Hallen, Tanks, Büro) und Fahrzeuge der Pläne."""
    hall_keys = ("blech_wand", "blech_dach", "beton", "stahl", "gummi", "stahl_dunkel", "lichtband", "marke", "solar", "lack")
    hp = hb_new_parts(*hall_keys)
    tp = hb_new_parts("lack", "stahl", "stahl_dunkel", "beton")
    for b in HB["buildings"]:
        cx, cz = b["c"]
        ux, uz = b["u"]
        if b["kind"] == "hall":
            hb_hall(hp, cx, cz, ux, uz, b["length"], b["depth"], b.get("h_eave", 6.5), b.get("h_ridge", 8.6), b["wall"], b["roof"], b["front"], b["docks"],
                    b["number"] if b["number"] else None, b["seed"], solar=b.get("solar", False))
            add_occluder_poly(hb_poly(cx, cz, ux, uz, b["hx"], b["hz"]), height=b.get("h_ridge", 8.6))          # die Halle wirft Schatten im Laternenlicht
        elif b["kind"] == "tank":
            hb_build_tank(tp, cx, cz, b["r"], b["h"], b["col"])
            add_occluder_poly([(cx + b["r"] * math.cos(2 * math.pi * k / 12), cz + b["r"] * math.sin(2 * math.pi * k / 12)) for k in range(12)], height=b["h"])
        elif b["kind"] == "office":
            spec = {"kind": "buero", "style": "buero", "w": b["w"], "d": b["d"], "floors": b["floors"], "roof": "flat", "front": "wohn", "seed": b["seed"], "max_h": 20.0}
            fx, fz = b["front"]
            if not place_house(spec, cx, cz, ux, uz, fx, fz, check_center=False):
                print("DIORAMA Büro konnte nicht gesetzt werden")
    for k, v in hp.items():
        if v:
            if k == "marke":
                hb_decal_objects("Halle", v)
            else:
                mesh_objects("Halle_" + k, v)
    for k, v in tp.items():
        if v:
            mesh_objects("Tank_" + k, v)


def hb_build_vehicles(rng_):
    """Sattelzüge aus HB["trucks"]."""
    lists = hb_new_parts("lack", "stahl_dunkel", "glas", "stahl", "gummi")
    cont = ([], [], [])
    lists["container"] = cont
    for t in HB["trucks"]:
        hb_truck(lists, t["c"][0], t["c"][1], t["u"][0], t["u"][1], t["cab"], t["cont"], t["seed"])
    for t in HB.get("stackers", []):
        hb_reach_stacker(lists, t["c"][0], t["c"][1], t["u"][0], t["u"][1], t["body"], t["cont"], t["seed"])
    for t in HB.get("straddles", []):
        hb_straddle(lists, t["c"][0], t["c"][1], t["u"][0], t["u"][1], t["body"], t["cont"], t["seed"])
    for k in ("lack", "stahl_dunkel", "glas", "stahl", "gummi"):
        if lists[k]:
            mesh_objects("Lkw_" + k, lists[k])
    for name, parts in zip(("Lkw_container_seite", "Lkw_container_tuer", "Lkw_container_dach"), cont):
        if parts:
            mesh_object(name, parts)
    print("DIORAMA Sattelzüge:", len(HB["trucks"]), " Reach Stacker:", len(HB.get("stackers", [])), " Portalhubwagen:", len(HB.get("straddles", [])))
    print("DIORAMA Fahrzeugorte: Lkw", [tuple(round(v, 1) for v in t["c"]) for t in HB["trucks"]], "Stacker", [tuple(round(v, 1) for v in t["c"]) for t in HB.get("stackers", [])],
          "Portal", [tuple(round(v, 1) for v in t["c"]) for t in HB.get("straddles", [])])


def hb_plan_vehicles():
    """Sattelzüge in freie Stellen setzen: feste Wunschplätze, danach Zufallssuche in den Gassen."""
    HB["trucks"] = []
    rng_ = random.Random(31)
    cab_cols = [(0.85, 0.85, 0.83), (0.12, 0.20, 0.42), (0.78, 0.10, 0.08), (0.9, 0.55, 0.05), (0.12, 0.45, 0.28), (0.3, 0.32, 0.34)]
    wish = [(25.0, 40.2, 1, 0), (47.0, 40.2, 1, 0), (-8.0, 49.0, 1, 0), (-36.0, 44.0, -1, 0)]

    def try_truck(cx, cz, ux, uz, with_cont=True):
        rc = hb_truck_rect(cx, cz, ux, uz)
        if hb_solid(rc[0], rc[1], rc[2], rc[3], rc[4], rc[5], 4.2, "auto", margin=1.6, pad=0.2):
            HB["trucks"].append({"c": (cx, cz), "u": (ux, uz), "cab": rng_.choice(cab_cols), "cont": hb_pick_color(rng_) if with_cont else None, "seed": rng_.randrange(1 << 20)})
            return True
        return False
    for cx, cz, ux, uz in wish:
        try_truck(cx, cz, ux, uz, rng_.random() < 0.8)
    HB["stackers"] = []
    lanes = [ln for ln in HB["lanes"] if ((ln[4] - ln[3]) if ln[5] else (ln[2] - ln[1])) >= 4.6]
    rng_.shuffle(lanes)
    for ln in lanes:
        if len(HB["stackers"]) >= 4:
            break
        axis, a0, a1, b0, b1, across = ln
        mid = (b0 + b1) / 2 if across else (a0 + a1) / 2
        lo, hi = (a0, a1) if across else (b0, b1)
        for t in np.arange(lo + 9.0, hi - 9.0, 6.0):
            a_, b_ = (t, mid) if across else (mid, t)
            cx, cz = (a_, b_) if axis == "x" else (b_, a_)
            along = (1.0, 0.0) if ((axis == "x") == across) else (0.0, 1.0)
            sgn = 1.0 if rng_.random() < 0.5 else -1.0
            ux, uz = along[0] * sgn, along[1] * sgn
            if hb_solid(cx + ux * 3.1, cz + uz * 3.1, ux, uz, 6.9, 1.6, 4.0, "auto", margin=2.0, pad=0.2):
                HB["stackers"].append({"c": (cx, cz), "u": (ux, uz), "body": (0.95, 0.72, 0.06) if len(HB["stackers"]) % 2 == 0 else (0.82, 0.12, 0.08),
                                       "cont": hb_pick_color(rng_), "seed": rng_.randrange(1 << 20)})
                break
    rects = [(-58, -22, 56, 22, 5), (69, -39, 97, 38, 2), (-101, -39, -73, 36, 2)]
    for (xa, za, xb, zb, n) in rects:
        got, tries = 0, 0
        while got < n and tries < 400:
            tries += 1
            cx, cz = rng_.uniform(xa + 10, xb - 10), rng_.uniform(za + 3, zb - 3)
            ux, uz = (1.0, 0.0) if (rng_.random() < 0.5 or xb - xa < 40) and not (zb - za > 50 and xb - xa < 40) else (0.0, 1.0)
            if xb - xa < 40:
                ux, uz = (0.0, 1.0)
            if try_truck(cx, cz, ux, uz, rng_.random() < 0.7):
                got += 1
    HB["straddles"] = []
    lanes2 = [ln for ln in HB["lanes"] if ((ln[4] - ln[3]) if ln[5] else (ln[2] - ln[1])) >= 5.3 and ((ln[2] - ln[1]) if ln[5] else (ln[4] - ln[3])) >= 16.0]
    rng_.shuffle(lanes2)
    for ln in lanes2:
        if len(HB["straddles"]) >= 3:
            break
        axis, a0, a1, b0, b1, across = ln
        mid = (b0 + b1) / 2 if across else (a0 + a1) / 2
        lo, hi = (a0, a1) if across else (b0, b1)
        for t in np.arange(lo + 8.0, hi - 8.0, 4.0):
            a_, b_ = (t, mid) if across else (mid, t)
            cx, cz = (a_, b_) if axis == "x" else (b_, a_)
            along = (1.0, 0.0) if ((axis == "x") == across) else (0.0, 1.0)
            sgn = 1.0 if rng_.random() < 0.5 else -1.0
            rc = hb_straddle_rect(cx, cz, along[0] * sgn, along[1] * sgn)
            if hb_solid(rc[0], rc[1], rc[2], rc[3], rc[4], rc[5], 5.2, "auto", margin=2.0, pad=0.2):
                HB["straddles"].append({"c": (cx, cz), "u": (rc[2], rc[3]), "body": (0.95, 0.72, 0.06) if len(HB["straddles"]) % 2 == 0 else (0.12, 0.34, 0.62),
                                        "cont": hb_pick_color(rng_), "seed": rng_.randrange(1 << 20)})
                break


def hb_plan_lamps():
    """Eigene Laternen (das Spiel baut sie als Laufzeit-Bauteile): Abstand zur Fahrbahn, nie im Fahrschlauch, nie auf Kranbahn/Stapeln. Abgelehnte
    Plätze werden ein Stück längs der Straße verschoben."""
    HB["lamps"] = []
    tr = HB["track"]
    cand = []
    if not IS_ARENA:
        s = 0.0
        k = 0
        while s < 1.0:
            side = 1.0 if k % 2 == 0 else -1.0
            cand.append((s, side))
            s += 14.0 / tr.length
            k += 1
        for x in (-54.0, -39.0, 10.0, 54.0):
            cand.append((None, (x, HB_QUAY_Z + 1.9)))
    for (s, side) in cand:
        if s is None:
            pos = np.array(side)
            toward = np.array([pos[0], pos[1] + 3.1])
            tries = [(pos, toward)]
        else:
            tries = []
            for dt in (0.0, 3.0, -3.0, 6.0, -6.0):
                ss = s + dt / tr.length
                p, t = tr.at(ss)
                left = np.array([-t[1], t[0]])
                for extra in (0.0, 1.2):
                    off = tr.hw(ss) + 5.0 + extra             # 8,5 m: Gegner, die im Regen oder in schnellen Kurven breit rutschen, treffen keinen Mast (Feldtest)
                    q = p + left * side * off
                    if HB_QUAY_Z - 0.5 < q[1] < -29.0:
                        continue                              # Kranbahn: dort stehen nur die Kai-Laternen
                    if tr.circle_slack(float(q[0]), float(q[1]), 0.2) < 4.0:
                        continue                              # auch zu anderen Abschnitten (Kurveninnenseite) mindestens 7,7 m
                    if hb_lv_unguarded_dist(float(q[0]), float(q[1])) < 12.0:
                        continue                              # neben erhöhter Fahrbahn ohne Leitplanke: wer herunterfällt, rutscht nicht in einen Mast
                    tries.append((q, p + left * side * (off - 4.0)))
        for pos, toward in tries:
            if hb_free(float(pos[0]), float(pos[1]), 1.0, 0.0, 0.3, 0.3, 1.0, 0.2):
                hb_occupy(float(pos[0]), float(pos[1]), 1.0, 0.0, 0.8, 0.8)
                HB["lamps"].append((float(pos[0]), float(pos[1]), float(toward[0]), float(toward[1])))
                break
    print("DIORAMA Laternen:", len(HB["lamps"]))


# ---------------------------------------------------------------- Kleine Ausstattung (Leitkegel, Betonleitwand, Reifenstapel, Fässer, Zaun mit Plane, Zelt, Generator)
def hb_cone(parts, x, z, scale=1.0, collide=True):
    """Leitkegel (Verkehrskegel) mit weißer Reflexbinde auf schwarzem Fuß; weich (Absperrung)."""
    gy = GROUND_Y
    hb_cuboid(parts["gummi"], x, z, 1.0, 0.0, 0.19 * scale, 0.19 * scale, gy, gy + 0.03 * scale, "gummi", col=(1, 1, 1), tile=1.0, bottom_fade=False)
    org = hb_lin((0.95, 0.38, 0.04))
    wht = hb_lin((0.9, 0.9, 0.88))
    hb_prism(parts["lack"], x, z, 0.145 * scale, gy + 0.03 * scale, gy + 0.22 * scale, "lack", org, 8, 0.115 * scale, tile=1.0, shade=(0.9, 1.0))
    hb_prism(parts["lack"], x, z, 0.115 * scale, gy + 0.22 * scale, gy + 0.36 * scale, "lack", wht, 8, 0.092 * scale, tile=1.0, shade=(1.0, 1.0))
    hb_prism(parts["lack"], x, z, 0.092 * scale, gy + 0.36 * scale, gy + 0.65 * scale, "lack", org, 8, 0.03 * scale, tile=1.0, shade=(0.95, 1.0), cap_col=org)
    if collide and HB["track"].circle_slack(x, z, 0.2 * scale) >= 0.3:
        HB["circles"].append((x, z, 0.2 * scale, 0.65, "absperrung"))


def hb_jersey(parts, p_a, p_b, col=(0.78, 0.78, 0.76), stripe=None, height=0.82, margin=1.0, segment=3.0):
    """Betonleitwand (New-Jersey-Profil) entlang einer Strecke, in Elementen zu segment Metern; optional zweite Farbe im Wechsel (Vertexfarbe).
    Hindernis: ein Rechteck für die ganze Strecke."""
    ax, az = p_a
    bx, bz = p_b
    ln = math.hypot(bx - ax, bz - az)
    if ln < 1.0:
        return False
    ux, uz = (bx - ax) / ln, (bz - az) / ln
    cx, cz = (ax + bx) / 2, (az + bz) / 2
    if not hb_solid(cx, cz, ux, uz, ln / 2, 0.31, height, "mauer", margin=margin, pad=0.1):
        return False
    fr = HbFrame(cx, cz, ux, uz)
    n = max(1, int(round(ln / segment)))
    seg = ln / n
    gy = GROUND_Y
    for k in range(n):
        a0 = -ln / 2 + k * seg + 0.02
        a1 = -ln / 2 + (k + 1) * seg - 0.02
        c = col if stripe is None or k % 2 == 0 else stripe
        c = hb_lin(c)
        lo = tuple(v * 0.7 for v in c)
        for sgn in (-1, 1):
            for (bb0, y0_, bb1, y1_) in ((0.31, 0.0, 0.23, 0.28), (0.23, 0.28, 0.11, height)):
                cl = lo if y0_ == 0 else c
                hb_quad(parts["beton"], "beton", [fr.p(a0, sgn * bb0, gy + y0_), fr.p(a1, sgn * bb0, gy + y0_), fr.p(a1, sgn * bb1, gy + y1_), fr.p(a0, sgn * bb1, gy + y1_)],
                        [(0, y0_), (seg / 1.5, y0_), (seg / 1.5, y1_), (0, y1_)], fr.d(0.0, sgn), [cl, cl, c, c])
        hb_quad(parts["beton"], "beton", [fr.p(a0, -0.11, gy + height), fr.p(a1, -0.11, gy + height), fr.p(a1, 0.11, gy + height), fr.p(a0, 0.11, gy + height)],
                [(0, 0), (1, 0), (1, 1), (0, 1)], None, [c] * 4)
        for a_, sgn_a in ((a0, -1), (a1, 1)):
            hb_quad(parts["beton"], "beton", [fr.p(a_, -0.31, gy), fr.p(a_, 0.31, gy), fr.p(a_, 0.11, gy + height), fr.p(a_, -0.11, gy + height)],
                    [(0, 0), (1, 0), (0.8, 1), (0.2, 1)], fr.d(sgn_a, 0.0), [lo, lo, c, c])
    return True


def hb_tyre_stack(parts, x, z, n=5, r=0.39, collide=True):
    """Gestapelte Reifen (liegend): Zehnkant-Ringe, leicht versetzt."""
    gy = GROUND_Y
    hh = 0.2
    for k in range(n):
        off = (k % 2) * 0.04
        hb_prism(parts["gummi"], x + off, z - off, r, gy + k * hh, gy + (k + 1) * hh, "gummi", (1, 1, 1), 10, tile=1.0, shade=(0.85, 1.0), cap_col=(0.9, 0.9, 0.92))
    if collide and HB["track"].circle_slack(x, z, r) >= 0.3:
        HB["circles"].append((x, z, r, n * hh, "reifen"))


def hb_drum(parts, x, z, col=(0.1, 0.25, 0.6), h=0.88, r=0.29):
    """Ölfass (200 l) mit zwei Rollsicken."""
    gy = GROUND_Y
    c = hb_lin(col)
    hb_prism(parts["lack"], x, z, r, gy, gy + h, "lack", c, 10, tile=1.0, shade=(0.85, 1.0))
    for yb in (0.25, 0.62):
        hb_prism(parts["lack"], x, z, r + 0.012, gy + yb, gy + yb + 0.04, "lack", tuple(v * 0.7 for v in c), 10, tile=1.0, shade=(1.0, 1.0))


def hb_tarp_fence(parts, p_a, p_b, h=2.0, col=(0.10, 0.28, 0.20), post_every=2.5, margin=1.0, collide=True):
    """Zaun mit Gewebeplane (Bauzaun-Blende): Stahlpfosten, Rohre oben und unten, Plane beidseitig."""
    ax, az = p_a
    bx, bz = p_b
    ln = math.hypot(bx - ax, bz - az)
    if ln < 1.0:
        return False
    ux, uz = (bx - ax) / ln, (bz - az) / ln
    cx, cz = (ax + bx) / 2, (az + bz) / 2
    if collide and not hb_solid(cx, cz, ux, uz, ln / 2, 0.08, h, "gitter", margin=margin, pad=0.05):
        return False
    fr = HbFrame(cx, cz, ux, uz)
    gy = GROUND_Y
    n = max(1, int(round(ln / post_every)))
    c = hb_lin(col)
    for k in range(n + 1):
        a = -ln / 2 + ln * k / n
        px, pz, _ = fr.p(a, 0.0, 0)
        hb_cuboid(parts["stahl"], px, pz, ux, uz, 0.04, 0.04, gy, gy + h + 0.1, "stahl", col=(0.9, 0.9, 0.92), tile=1.0, bottom_fade=False)
    for yy in (0.08, h - 0.04):
        hb_box_l(parts["stahl"], "stahl", fr, -ln / 2, ln / 2, -0.03, 0.03, gy + yy, gy + yy + 0.05, (0.85, 0.85, 0.88), (1.0, 1.0))
    for sgn in (-1, 1):
        hb_wall(parts["planen"], "planen", fr, -ln / 2, sgn * 0.045, ln / 2, sgn * 0.045, gy + 0.15, gy + h - 0.08, tuple(v * 0.8 for v in c), c,
                tile_u=2.0, tile_v=1.0, facing=(0, sgn))
    return True


def hb_tent(parts, x, z, ang, col=(0.8, 0.1, 0.08), size=3.0, num=None):
    """Faltpavillon (Pop-up-Zelt, 3 x 3 m) eines Teams: Dach in Streifen (Teamfarbe und Weiß), Volant, Rückwand, halbhohe Seitenwände, Arbeitstisch,
    Werkzeugwagen und ein Boxenschild mit der Nummer. Offen zur +b-Seite (Boxengasse); ang dreht das Bezugssystem (a = cos/sin)."""
    fr = HbFrame(x, z, math.cos(ang), math.sin(ang))
    gy = GROUND_Y
    h = size / 2
    c = hb_lin(col)
    wht = hb_lin((0.92, 0.92, 0.9))
    for sa in (-1, 1):
        for sb in (-1, 1):
            px, pz, _ = fr.p(sa * (h - 0.05), sb * (h - 0.05), 0)
            hb_cuboid(parts["stahl"], px, pz, fr.ux, fr.uz, 0.03, 0.03, gy, gy + 2.3, "stahl", col=(0.9, 0.9, 0.92), tile=1.0, bottom_fade=False)
    top = gy + 2.9
    eave = gy + 2.35
    corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for i in range(4):
        (sa0, sb0), (sa1, sb1) = corners[i], corners[(i + 1) % 4]
        for j in range(3):                                          # Rück- und Vorderfläche: Team - weiß - Team (ein weißes Band über den First), Seiten einfarbig
            t0, t1 = j / 3.0, (j + 1) / 3.0
            e0 = (sa0 + (sa1 - sa0) * t0, sb0 + (sb1 - sb0) * t0)
            e1 = (sa0 + (sa1 - sa0) * t1, sb0 + (sb1 - sb0) * t1)
            col_j = c if (j != 1 or i in (1, 3)) else wht
            q = [fr.p(e0[0] * h, e0[1] * h, eave), fr.p(e1[0] * h, e1[1] * h, eave), fr.p(e1[0] * h * 0.35, e1[1] * h * 0.35, top), fr.p(e0[0] * h * 0.35, e0[1] * h * 0.35, top)]
            hb_quad(parts["lack"], "lack", q, [(0, 0), (1, 0), (1, 1), (0, 1)], None, [tuple(v * 0.85 for v in col_j)] * 2 + [col_j] * 2)
        q2 = [fr.p(sa0 * h, sb0 * h, eave - 0.28), fr.p(sa1 * h, sb1 * h, eave - 0.28), fr.p(sa1 * h, sb1 * h, eave), fr.p(sa0 * h, sb0 * h, eave)]
        mid = ((sa0 + sa1) / 2, (sb0 + sb1) / 2)
        hb_quad(parts["lack"], "lack", q2, [(0, 0), (1, 0), (1, 1), (0, 1)], fr.d(*mid), [wht] * 2 + [c] * 2)
    hb_quad(parts["lack"], "lack", [fr.p(sa * h * 0.35, sb * h * 0.35, top) for sa, sb in corners], [(0, 0), (1, 0), (1, 1), (0, 1)], None, [c] * 4)
    hb_wall(parts["lack"], "lack", fr, -h, -h, h, -h, gy + 0.1, gy + 2.3, tuple(v * 0.9 for v in c), tuple(v * 0.9 for v in c), facing=(0, 1))
    for sa in (-1, 1):                                              # Seitenwände halbhoch (Außenseite)
        hb_wall(parts["lack"], "lack", fr, sa * h, -h, sa * h, 0.0, gy + 0.1, gy + 1.3, tuple(v * 0.75 for v in c), tuple(v * 0.85 for v in c), facing=(sa, 0))
    hb_box_l(parts["lack"], "lack", fr, -1.0, 0.8, -1.2, -0.5, gy + 0.72, gy + 0.78, (0.9, 0.9, 0.88), (1.0, 1.0))      # Tisch an der Rückwand
    for sa in (-0.9, 0.7):
        for sb in (-1.1, -0.6):
            px, pz, _ = fr.p(sa, sb, 0)
            hb_cuboid(parts["stahl"], px, pz, fr.ux, fr.uz, 0.03, 0.03, gy, gy + 0.72, "stahl", col=(0.8, 0.8, 0.82), tile=1.0, bottom_fade=False)
    hb_box_l(parts["lack"], "lack", fr, 0.95, 1.4, -1.2, -0.4, gy + 0.05, gy + 1.0, hb_lin((0.75, 0.08, 0.06)), (0.8, 1.0))   # Werkzeugwagen
    hb_box_l(parts["stahl_dunkel"], "stahl_dunkel", fr, 0.95, 1.4, -1.2, -0.4, gy + 1.0, gy + 1.04, (1, 1, 1), (1.0, 1.0))
    if num is not None:                                              # Boxenschild vor dem Zelt: Pfosten mit weißer Tafel und Nummer
        sx_, sz_, _ = fr.p(-h - 0.5, h + 0.7, 0)
        hb_cuboid(parts["stahl"], sx_, sz_, fr.ux, fr.uz, 0.02, 0.02, gy, gy + 1.9, "stahl", col=(0.8, 0.8, 0.82), tile=1.0, bottom_fade=False)
        hb_box_l(parts["lack"], "lack", fr, -h - 0.78, -h - 0.22, h + 0.67, h + 0.73, gy + 1.45, gy + 1.9, (1.1, 1.1, 1.08), (1.0, 1.0))
        hb_number_quads(parts["lack"], fr, -h - 0.62, h + 0.74, gy + 1.52, int(num), 0.3, 0.17, 0.05, key="lack", col=(0.04, 0.04, 0.05), facing=(0, 1), t=0.04)


def hb_generator(parts, x, z, ang, col=(0.95, 0.72, 0.08)):
    """Stromaggregat (schallgedämmt) auf Kufen mit Auspuffrohr."""
    fr = HbFrame(x, z, math.cos(ang), math.sin(ang))
    gy = GROUND_Y
    hb_box_l(parts["stahl_dunkel"], "stahl_dunkel", fr, -1.25, 1.25, -0.6, 0.6, gy, gy + 0.18, (1, 1, 1))
    hb_box_l(parts["lack"], "lack", fr, -1.2, 1.2, -0.55, 0.55, gy + 0.18, gy + 1.5, hb_lin(col), (0.8, 1.0))
    hb_box_l(parts["stahl_dunkel"], "stahl_dunkel", fr, 0.2, 1.1, -0.4, 0.4, gy + 1.5, gy + 1.56, (1, 1, 1))
    px, pz, _ = fr.p(-0.7, 0.25, 0)
    hb_prism(parts["stahl"], px, pz, 0.06, gy + 1.5, gy + 2.1, "stahl", (0.8, 0.8, 0.82), 6, tile=1.0)


# ---------------------------------------------------------------- Startportal
def hb_portal_plan(s=0.0, cantilever=False, clear=1.65):
    """Pylonenstellen des Startportals vormerken (belegen, Hindernis); clear = Abstand Fahrbahnrand - Pylonmitte."""
    tr = HB["track"]
    p, t = tr.at(s)
    fr = HbFrame(float(p[0]), float(p[1]), float(t[0]), float(t[1]))
    hw = tr.hw(s)
    bp = hw + clear
    sides = (1,) if cantilever else (-1, 1)
    info = {"s": s, "bp": bp, "sides": sides, "cant": cantilever, "fr": (float(p[0]), float(p[1]), float(t[0]), float(t[1])), "hw": hw}
    for sgn in sides:
        cx, cz, _ = fr.p(0.0, sgn * bp, 0)
        hb_occupy(cx, cz, fr.ux, fr.uz, 1.0, 1.0)
        HB["solids"].append((cx, cz, fr.ux, fr.uz, 0.45, 0.45, 6.3, "mauer"))
    HB["portal"] = info


def hb_portal():
    """Startportal über der Startlinie: Pylone neben der Fahrbahn, Querbalken mit Schriftzug (Längsseiten) und Schachbrett (oben). Wie
    build_portal des Kerns (der für Laufzeit-Fahrbahnen nicht läuft). Mit cantilever steht nur ein Pylon (Ausleger über die Fahrbahn)."""
    info = HB["portal"]
    fr = HbFrame(*info["fr"])
    bp, hw = info["bp"], info["hw"]
    hb_ = bp + 0.5
    b_lo = -(hw + 0.9) if info["cant"] else -hb_
    y0, y1 = 5.4, 6.6
    gy = GROUND_Y
    parts = hb_new_parts("e:portal", "e:schach", "weiss", "beton", "rot")
    for sgn in info["sides"]:
        hb_box_l(parts["beton"], "beton", fr, -0.45, 0.45, sgn * bp - 0.45, sgn * bp + 0.45, gy, gy + 0.5, (1, 1, 1), (1.0, 1.0), 1.0)
        hb_box_l(parts["weiss"], "weiss", fr, -0.35, 0.35, sgn * bp - 0.35, sgn * bp + 0.35, gy + 0.5, gy + 6.3, (1.1, 1.1, 1.1), (0.8, 1.0), 1.0)
        hb_box_l(parts["rot"], "rot", fr, -0.37, 0.37, sgn * bp - 0.37, sgn * bp + 0.37, gy + 3.4, gy + 3.9, (1, 1, 1), (1.0, 1.0), 1.0)
    if info["cant"]:
        for a_ in (-0.3, 0.3):
            hb_quad(parts["weiss"], "weiss", [fr.p(a_, bp - 0.35, y0), fr.p(a_, bp - 3.2, y0), fr.p(a_, bp - 0.35, y0 - 2.6)], [(0, 0), (1, 0), (0, 1)], fr.d(0.0, 1.0) if a_ > 0 else fr.d(0.0, -1.0))
    for a0, a1, key in ((-0.42, -0.15, "weiss"), (-0.15, 0.15, "e:schach"), (0.15, 0.42, "weiss")):
        ab = ((a0, b_lo), (a1, b_lo), (a1, hb_), (a0, hb_))
        hb_quad(parts[key], key, [fr.p(a, b, y1) for a, b in ab], [(a / 0.3, b / 0.3) for a, b in ab], None)
    ln = hb_ - b_lo
    for a, fa, uv in ((-0.42, (-1, 0), ((0, 0), (1, 0), (1, 1), (0, 1))), (0.42, (1, 0), ((1, 0), (0, 0), (0, 1), (1, 1)))):
        hb_quad(parts["e:portal"], "e:portal", [fr.p(a, b_lo, y0), fr.p(a, hb_, y0), fr.p(a, hb_, y1), fr.p(a, b_lo, y1)], list(uv), fr.d(*fa))
    for b, fa in ((b_lo, (0, -1)), (hb_, (0, 1))):
        hb_wall(parts["weiss"], "weiss", fr, -0.42, b, 0.42, b, y0, y1, facing=fa)
    for k, v in parts.items():
        if v:
            mesh_objects("Portal_" + k.replace(":", "_"), v)


# ---------------------------------------------------------------- Festmacherleinen, Fender, Rettungsstation am Kai
def hb_hull_zmax(hull, x):
    """Größtes z des Umrisspolygons bei gegebenem x (landseitiger Rumpfrand)."""
    best = None
    n = len(hull)
    for i in range(n):
        (ax, az), (bx, bz) = hull[i], hull[(i + 1) % n]
        if (ax - x) * (bx - x) <= 0 and ax != bx:
            t = (x - ax) / (bx - ax)
            z = az + (bz - az) * t
            best = z if best is None else max(best, z)
    return best


def hb_rope(parts, p0, p1, sag=0.5, width=0.07, n=9, col=(0.34, 0.29, 0.2)):
    """Leine von p0 nach p1 (x, y, z) mit Durchhang: Kette aus zwei gekreuzten Bändern."""
    pts = []
    for k in range(n + 1):
        t = k / n
        pts.append((p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t - sag * 4 * t * (1 - t), p0[2] + (p1[2] - p0[2]) * t))
    c = hb_lin(col)
    for (xa, ya, za), (xb, yb, zb) in zip(pts[:-1], pts[1:]):
        dx, dz = xb - xa, zb - za
        ln = math.hypot(dx, dz) or 1.0
        nx, nz = -dz / ln * width / 2, dx / ln * width / 2
        hb_quad(parts["seil"], "seil", [(xa - nx, za - nz, ya), (xb - nx, zb - nz, yb), (xb + nx, zb + nz, yb), (xa + nx, za + nz, ya)], [(0, 0), (1, 0), (1, 1), (0, 1)], None, [c] * 4)
        hb_quad(parts["seil"], "seil", [(xa, za, ya - width / 2), (xb, zb, yb - width / 2), (xb, zb, yb + width / 2), (xa, za, ya + width / 2)], [(0, 0), (1, 0), (1, 1), (0, 1)], (-dz, dx), [c] * 4)


def hb_build_quay_details(rng_, hull):
    """Fender an der Kaikante, Festmacherleinen vom Poller zum Schiff, Rettungsstation, Leiter."""
    qz = HB_QUAY_Z
    parts = hb_new_parts("gummi", "seil", "rot", "weiss", "stahl", "stahl_dunkel", "lack")
    gy = GROUND_Y
    xs_f = []
    if hull:
        hp = np.array(hull)
        xs_f = list(np.arange(math.floor(hp[:, 0].min() / 6.0) * 6.0 + 3.0, hp[:, 0].max(), 6.0))
    for x in xs_f:
        hb_prism(parts["gummi"], x, qz - 0.3, 0.3, -1.7, 0.1, "gummi", (1, 1, 1), 10, tile=1.0, shade=(0.7, 1.0), cap_col=(0.9, 0.9, 0.92))
        hb_cuboid(parts["stahl_dunkel"], x, qz - 0.05, 1.0, 0.0, 0.12, 0.05, -1.4, 0.14, "stahl_dunkel", col=(0.8, 0.8, 0.8), tile=1.0, bottom_fade=False)
    if hull:
        pollers = sorted(float(p["x"]) for p in data["props"] if p.get("model") == "hafen_poller")
        hp = np.array(hull)
        x_lo, x_hi = hp[:, 0].min() + 2.0, hp[:, 0].max() - 2.0
        for i, x in enumerate([x for x in pollers if x_lo <= x <= x_hi]):
            zt = hb_hull_zmax(hull, x + (3.0 if i % 2 == 0 else -3.0))
            if zt is None:
                continue
            tx = x + (3.0 if i % 2 == 0 else -3.0)
            hb_rope(parts, (x, 0.55, qz + 0.8), (tx, 2.9, zt + 0.05), sag=0.45)
    # Rettungsstation: Pfahl mit rotem Schrank und weißem Kreuz, am Kai zwischen den Kränen (zwischen Kaikante und seeseitigem Warnstreifen der Kranbahn)
    for cx in (-15.0, 18.0):                                           # zwischen den Kränen (x -30..-18, -8..4, 30..42) und mit Abstand zu den Pollern (alle 12 m)
        cz = qz + 1.15
        hb_cuboid(parts["rot"], cx, cz, 1.0, 0.0, 0.35, 0.18, gy, gy + 1.15, "rot", col=(1, 1, 1), tile=1.0, bottom_fade=False)
        # Rettungsringständer daneben: Pfosten mit Ring (rot-weiß, beidseitig sichtbar) und Wurfleine als Bündel
        hb_cuboid(parts["stahl_dunkel"], cx + 0.75, cz, 1.0, 0.0, 0.03, 0.03, gy, gy + 1.35, "stahl_dunkel", col=(0.9, 0.9, 0.92), tile=1.0, bottom_fade=False)
        hb_life_ring(parts, cx + 0.75, cz, gy + 1.0)
        hb_cuboid(parts["weiss"], cx, cz + 0.185, 1.0, 0.0, 0.2, 0.012, gy + 0.55, gy + 0.65, "weiss", col=(1, 1, 1), tile=1.0, bottom_fade=False)
        hb_cuboid(parts["weiss"], cx, cz + 0.185, 1.0, 0.0, 0.05, 0.012, gy + 0.4, gy + 0.8, "weiss", col=(1, 1, 1), tile=1.0, bottom_fade=False)
        HB["circles"].append((cx, cz, 0.4, 1.2, "mast"))
    for k, v in parts.items():
        if v:
            mesh_objects("Kaidetail_" + k, v)


def hb_life_ring(parts, x, z, y_c, r_out=0.31, r_in=0.18, n=12):
    """Rettungsring (senkrecht, Fläche zeigt nach +z und -z): zwölf Segmente im Wechsel rot und weiß."""
    for k in range(n):
        a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
        key = "rot" if k % 2 == 0 else "weiss"
        pts = [(x + r_out * math.cos(a0), z, y_c + r_out * math.sin(a0)), (x + r_out * math.cos(a1), z, y_c + r_out * math.sin(a1)),
               (x + r_in * math.cos(a1), z, y_c + r_in * math.sin(a1)), (x + r_in * math.cos(a0), z, y_c + r_in * math.sin(a0))]
        for fz_ in (1, -1):
            hb_quad(parts[key], key, [(px, z + fz_ * 0.012, py) for (px, _pz, py) in pts], [(0, 0), (1, 0), (1, 1), (0, 1)], (0.0, float(fz_)), [(1.0, 1.0, 1.0)] * 4)


# ---------------------------------------------------------------- Schlepper im Hafenbecken
HB_TUG = [(-5.5, -1.5), (-5.0, -2.0), (-3.0, -2.2), (1.5, -2.2), (3.5, -1.8), (5.0, -1.0), (5.5, 0.0), (5.0, 1.0), (3.5, 1.8), (1.5, 2.2), (-3.0, 2.2), (-5.0, 2.0), (-5.5, 1.5)]


def hb_tug_hull_world(cx, cz, ux, uz):
    fr = HbFrame(cx, cz, ux, uz)
    return [(fr.p(a, b, 0)[0], fr.p(a, b, 0)[1]) for a, b in HB_TUG]


def hb_build_tug(cx, cz, ux, uz):
    """Hafenschlepper (11 m): schwarzer Rumpf mit roter Bordwand und umlaufender Scheuerleiste aus Gummi, Fender aus Reifen, Deckshaus mit
    Brücke (Fenster ringsum, Brückennocken), Schornstein (rot, weißes Band, schwarze Kappe), Mast mit Radar, Rettungsinsel, Scheinwerfer,
    Ankerwinde auf dem Vorschiff, Schlepphaken-Bock achtern, Doppelpoller mit Festmacherleinen zu den Pollern am Beckenrand."""
    fr = HbFrame(cx, cz, ux, uz)
    parts = hb_new_parts("lack", "gummi", "glas", "stahl", "stahl_dunkel", "seil")
    yw = HB_WATER_Y
    yd = yw + 1.1                       # Deck
    yb = yd + 0.55                      # Oberkante Bordwand
    blk, red, wht = hb_lin((0.035, 0.035, 0.04)), hb_lin((0.62, 0.07, 0.05)), hb_lin((0.9, 0.9, 0.88))
    deck_c = hb_lin((0.27, 0.30, 0.28))
    n = len(HB_TUG)
    for i in range(n):
        (a0, b0), (a1, b1) = HB_TUG[i], HB_TUG[(i + 1) % n]
        fa = (b1 - b0, -(a1 - a0))                   # nach außen (Umlaufsinn des Polygons beachten: Prüfung unten)
        mid = ((a0 + a1) / 2, (b0 + b1) / 2)
        if fa[0] * mid[0] + fa[1] * mid[1] < 0:
            fa = (-fa[0], -fa[1])
        fl = math.hypot(*fa) or 1.0
        nx, nz_ = fa[0] / fl * 0.09, fa[1] / fl * 0.09
        hb_wall(parts["lack"], "lack", fr, a0, b0, a1, b1, yw - 0.15, yd - 0.45, blk, blk, facing=fa)
        hb_wall(parts["lack"], "lack", fr, a0, b0, a1, b1, yd - 0.45, yb, tuple(v * 0.8 for v in red), red, facing=fa)
        # Scheuerleiste: schwarzer Gummiwulst knapp unter der Deckskante (steht 9 cm vor der Bordwand)
        hb_wall(parts["gummi"], "gummi", fr, a0 + nx, b0 + nz_, a1 + nx, b1 + nz_, yd - 0.34, yd - 0.04, facing=fa)
        hb_quad(parts["gummi"], "gummi", [fr.p(a0 + nx, b0 + nz_, yd - 0.04), fr.p(a1 + nx, b1 + nz_, yd - 0.04), fr.p(a1, b1, yd - 0.04), fr.p(a0, b0, yd - 0.04)],
                [(0, 0), (1, 0), (1, 1), (0, 1)], None, [(1.5, 1.5, 1.5)] * 4)
        k = 0.12 / max(1e-3, math.hypot(*mid))
        ia0, ib0, ia1, ib1 = a0 * (1 - k), b0 * (1 - k), a1 * (1 - k), b1 * (1 - k)
        hb_quad(parts["lack"], "lack", [fr.p(a0, b0, yb), fr.p(a1, b1, yb), fr.p(ia1, ib1, yb), fr.p(ia0, ib0, yb)], [(0, 0), (1, 0), (1, 1), (0, 1)], None, [tuple(v * 1.2 for v in red)] * 4)
        hb_wall(parts["lack"], "lack", fr, ia0, ib0, ia1, ib1, yd, yb, tuple(v * 0.6 for v in red), tuple(v * 0.8 for v in red), facing=(-fa[0], -fa[1]))
    deck = [fr.p(a * 0.955, b * 0.955, yd) for a, b in HB_TUG]
    hb_quad(parts["lack"], "lack", deck, [(0.5, 0.5)] * n, None, [deck_c] * n)
    # Decksausrüstung: Luken (Vorschiff, achtern), Ankerwinde, Schlepphaken-Bock, Doppelpoller, Scheuerholz am Bug
    hb_box_l(parts["lack"], "lack", fr, 2.4, 3.4, -0.7, 0.7, yd, yd + 0.14, hb_lin((0.45, 0.14, 0.1)), (0.9, 1.0))
    hb_box_l(parts["lack"], "lack", fr, -5.0, -4.3, -0.6, 0.6, yd, yd + 0.12, hb_lin((0.45, 0.14, 0.1)), (0.9, 1.0))
    wx_, wz_, _ = fr.p(4.0, 0.0, 0)
    hb_prism(parts["stahl_dunkel"], wx_, wz_, 0.32, yd, yd + 0.5, "stahl_dunkel", (0.9, 0.9, 0.92), 10, tile=1.0, cap_col=(1.3, 1.3, 1.35))
    hb_box_l(parts["lack"], "lack", fr, 3.55, 4.45, -0.5, 0.5, yd + 0.5, yd + 0.62, hb_lin((0.55, 0.1, 0.07)), (1.0, 1.0))
    for sgn in (-1, 1):
        hb_box_l(parts["stahl_dunkel"], "stahl_dunkel", fr, -5.0 - 0.0, -4.85, sgn * 1.25 - 0.08, sgn * 1.25 + 0.08, yd, yd + 2.1, (0.9, 0.9, 0.92), (1.0, 1.0))
    hb_box_l(parts["stahl_dunkel"], "stahl_dunkel", fr, -5.05, -4.8, -1.33, 1.33, yd + 2.0, yd + 2.18, (1, 1, 1), (1.0, 1.0))
    hb_box_l(parts["gummi"], "gummi", fr, 5.0, 5.6, -0.95, 0.95, yw + 0.2, yd + 0.5, (1, 1, 1), (0.9, 1.0))          # Schubknie (Bugfender)
    cleats = []
    for a in (2.6, -0.7, -2.9):
        for sgn in (-1, 1):
            for da in (-0.22, 0.22):
                px, pz, _ = fr.p(a + da, sgn * 1.6, 0)
                hb_prism(parts["stahl_dunkel"], px, pz, 0.1, yd, yd + 0.42, "stahl_dunkel", (1, 1, 1), 8, 0.08, tile=1.0, cap_col=(1.5, 1.5, 1.55))
            cleats.append((a, sgn))
    # Deckshaus (unten), Brücke (oben) mit Fensterband ringsum, Brückennocken, Dach, Geländer
    hb_box_l(parts["lack"], "lack", fr, -4.2, 0.4, -1.55, 1.55, yd, yd + 1.9, wht, (0.8, 1.0))
    for sgn in (-1, 1):
        for a0_, a1_ in ((-3.7, -2.6), (-2.2, -1.1), (-0.8, 0.0)):
            hb_wall(parts["glas"], "glas", fr, a0_, sgn * 1.555, a1_, sgn * 1.555, yd + 0.85, yd + 1.45, facing=(0, sgn))
    hb_wall(parts["glas"], "glas", fr, 0.405, -1.1, 0.405, 1.1, yd + 0.85, yd + 1.45, facing=(1, 0))
    hb_box_l(parts["lack"], "lack", fr, -3.3, -0.4, -1.25, 1.25, yd + 1.9, yd + 2.95, wht, (0.9, 1.0))
    for sgn in (-1, 1):
        hb_wall(parts["glas"], "glas", fr, -3.2, sgn * 1.255, -0.5, sgn * 1.255, yd + 2.25, yd + 2.75, facing=(0, sgn))
        hb_box_l(parts["lack"], "lack", fr, -3.0, -0.7, sgn * 1.25, sgn * 1.7, yd + 1.88, yd + 1.96, hb_lin((0.55, 0.57, 0.6)), (1.0, 1.0))        # Brückennock
        hb_box_l(parts["stahl"], "stahl", fr, -3.0, -0.7, sgn * 1.68, sgn * 1.7, yd + 1.96, yd + 2.55, (0.9, 0.9, 0.92), (1.0, 1.0))                  # Nockreling (Fläche)
    hb_wall(parts["glas"], "glas", fr, -0.395, -1.15, -0.395, 1.15, yd + 2.25, yd + 2.75, facing=(1, 0))
    hb_wall(parts["glas"], "glas", fr, -3.305, -1.15, -3.305, 1.15, yd + 2.25, yd + 2.75, facing=(-1, 0))
    hb_box_l(parts["lack"], "lack", fr, -3.55, -0.1, -1.45, 1.45, yd + 2.95, yd + 3.07, hb_lin((0.62, 0.64, 0.66)), (1.0, 1.0))
    # Brückendach: Radar, Mast, Rettungsinsel, Scheinwerfer, Antenne, Typhon
    mx, mz, _ = fr.p(-1.8, 0.0, 0)
    hb_prism(parts["stahl"], mx, mz, 0.05, yd + 3.07, yd + 5.2, "stahl", (0.8, 0.8, 0.82), 6, tile=1.0)
    hb_box_l(parts["stahl_dunkel"], "stahl_dunkel", fr, -2.5, -1.1, -0.04, 0.04, yd + 5.0, yd + 5.14, (1, 1, 1), (1.0, 1.0))                          # Radarbalken
    hb_box_l(parts["stahl"], "stahl", fr, -1.85, -1.75, -0.35, 0.35, yd + 4.2, yd + 4.24, (0.8, 0.8, 0.82), (1.0, 1.0))                              # Quersaling
    hb_box_l(parts["lack"], "lack", fr, -1.6, -0.6, 0.7, 1.2, yd + 3.07, yd + 3.55, hb_lin((0.95, 0.45, 0.06)), (0.9, 1.0))                        # Rettungsinsel (Behälter)
    hb_box_l(parts["stahl_dunkel"], "stahl_dunkel", fr, -0.9, -0.5, -0.9, -0.55, yd + 3.07, yd + 3.35, (1, 1, 1), (1.0, 1.0))                       # Scheinwerfer
    hb_box_l(parts["stahl_dunkel"], "stahl_dunkel", fr, -3.2, -2.7, -1.0, -0.4, yd + 3.07, yd + 3.2, (0.8, 0.8, 0.82), (1.0, 1.0))
    hb_railing(parts["stahl"], [fr.p(-3.45, -1.4, 0)[:2], fr.p(-0.2, -1.4, 0)[:2], fr.p(-0.2, 1.4, 0)[:2], fr.p(-3.45, 1.4, 0)[:2]], y0=yd + 3.07, height=0.8,
               key="stahl", col=(0.9, 0.9, 0.92), post_every=1.6, collide=False)
    # Schornstein: rot, weißes Band, schwarze Kappe
    cx_, cz_, _ = fr.p(-3.9, 0.0, 0)
    hb_prism(parts["lack"], cx_, cz_, 0.55, yd + 1.9, yd + 3.0, "lack", red, 10, 0.52, tile=1.0)
    hb_prism(parts["lack"], cx_, cz_, 0.52, yd + 3.0, yd + 3.3, "lack", wht, 10, 0.5, tile=1.0)
    hb_prism(parts["lack"], cx_, cz_, 0.5, yd + 3.3, yd + 3.9, "lack", red, 10, 0.48, tile=1.0)
    hb_prism(parts["lack"], cx_, cz_, 0.5, yd + 3.9, yd + 4.35, "lack", blk, 10, 0.5, tile=1.0, cap_col=tuple(v * 5.0 for v in blk))
    hb_prism(parts["lack"], cx_, cz_, 0.36, yd + 4.351, yd + 4.4, "lack", (0.0, 0.0, 0.0), 10, 0.36, tile=1.0, cap_col=(0.0, 0.0, 0.0))        # Abgasöffnung
    # Fender aus Reifen außen an der Bordwand (hängen knapp über dem Wasser) und Festmacherleinen zu den Pollern des Beckens
    for a in (-4.0, -2.0, 0.0, 2.2, 3.7):
        for sgn in (-1, 1):
            bb = sgn * (2.32 if abs(a) < 3 else 1.97)
            px, pz, _ = fr.p(a, bb, 0)
            hb_prism(parts["gummi"], px, pz, 0.27, yw + 0.35, yw + 0.8, "gummi", (1, 1, 1), 8, tile=1.0, cap_col=(0.9, 0.9, 0.92))
    bx0_, bz0_, bx1_, bz1_ = HB["basin"]
    tops = [(bx1_ + 0.55, bz1_ - 6.0), (bx0_ - 0.55, bz1_ - 6.0)]
    for (a, sgn) in cleats:
        if abs(a - (-0.7)) > 1e-6:
            continue
        px, pz, _ = fr.p(a, sgn * 1.6, 0)
        tx_, tz_ = tops[0] if sgn > 0 else tops[1]
        hb_rope(parts, (px, yd + 0.4, pz), (tx_, GROUND_Y + 0.74, tz_), sag=0.25, width=0.06)
    for k, v in parts.items():
        if v:
            mesh_objects("Schlepper_" + k, v)


# ---------------------------------------------------------------- Gassen: Mittellinien, Pfeile, Blocknummern
def hb_arrow(out, key, cx, cz, ux, uz, length=3.2, width=1.0, shaft=0.16, col=(1, 1, 1), y=None):
    """Richtungspfeil auf dem Boden (Schaft + Spitze)."""
    y = GROUND_Y + 0.004 if y is None else y
    vx, vz = -uz, ux
    h = length / 2

    def P(a, b):
        return (cx + ux * a + vx * b, cz + uz * a + vz * b, y)
    hb_quad(out, key, [P(-h, -shaft / 2), P(h - width * 0.9, -shaft / 2), P(h - width * 0.9, shaft / 2), P(-h, shaft / 2)], [(0, 0), (1, 0), (1, 1), (0, 1)], None, [col] * 4)
    hb_quad(out, key, [P(h - width * 0.9, -width / 2), P(h, 0.0), P(h - width * 0.9, width / 2)], [(0, 0), (1, 0), (0.5, 1)], None, [col] * 3)


def hb_lane_marks(dec_white, dec_yellow):
    """Mittellinien (gestrichelt, abgenutzt), Pfeile und Blocknummern in den Gassen der Containerfelder; nur, wo nichts steht und der Fahrschlauch
    mindestens 0,6 m entfernt ist."""
    rng_ = HB["rng"]
    n_dash = n_arrow = n_num = 0
    y = GROUND_Y + 0.004

    def ok(cx, cz, ux, uz, hx, hz):
        return hb_free(cx, cz, ux, uz, hx, hz, 0.6, 0.0)

    def world(axis, a, b):
        return (a, b) if axis == "x" else (b, a)
    num = 10
    for ln in HB["lanes"]:
        axis, a0, a1, b0, b1, across = ln
        width = (b1 - b0) if across else (a1 - a0)
        if width < 4.4:
            continue
        mid = (b0 + b1) / 2 if across else (a0 + a1) / 2
        lo, hi = (a0, a1) if across else (b0, b1)
        t = lo + 1.0
        while t + 2.0 < hi:
            ca = t + 1.0
            wear = rng_.uniform(0.45, 1.0)
            if rng_.random() < 0.9:
                if across:
                    cx, cz = world(axis, ca, mid)
                    ux, uz = world(axis, 1.0, 0.0)
                else:
                    cx, cz = world(axis, mid, ca)
                    ux, uz = world(axis, 0.0, 1.0)
                if ok(cx, cz, ux, uz, 1.0, 0.06):
                    hb_strip(dec_white, "linie", cx - ux * 1.0, cz - uz * 1.0, cx + ux * 1.0, cz + uz * 1.0, 0.12, y, (wear,) * 3)
                    n_dash += 1
            t += 3.6
        # Pfeile alle ~38 m, Blocknummer an Gassenanfang
        t = lo + 9.0
        while t + 5.0 < hi:
            if across:
                cx, cz = world(axis, t, mid)
                ux, uz = world(axis, 1.0, 0.0)
            else:
                cx, cz = world(axis, mid, t)
                ux, uz = world(axis, 0.0, 1.0)
            sgn = 1.0 if rng_.random() < 0.5 else -1.0
            if ok(cx, cz, ux, uz, 1.8, 0.7):
                hb_arrow(dec_white, "linie", cx, cz, ux * sgn, uz * sgn, 3.6, 1.1, 0.17, (0.85,) * 3)
                n_arrow += 1
            t += 38.0
        if width >= 5.0:
            cx, cz = world(axis, lo + 3.0, mid) if across else world(axis, mid, lo + 3.0)
            ux, uz = world(axis, 1.0, 0.0) if across else world(axis, 0.0, 1.0)
            if ok(cx, cz, ux, uz, 1.4, 0.8):
                fr = HbFrame(cx, cz, ux, uz)
                hb_number_quads(dec_white, fr, -0.95, -0.5, y, num, 1.0, 0.5, 0.2, t=0.11, key="linie", vertical=False, col=(0.9, 0.9, 0.9))
                n_num += 1
                num += 7 if rng_.random() < 0.5 else 11
    print("DIORAMA Gassenmarkierung: Striche", n_dash, "Pfeile", n_arrow, "Nummern", n_num)


# ---------------------------------------------------------------- Spuren-Raster: Reifengummi, Rauch, Ölspuren (Striche mit weichem Rand)
def hb_stroke_raster(shape, strokes, ext):
    """Zeichnet Striche in ein Raster (Zeile 0 = Norden, z wächst nach unten). strokes: Liste (Punkte Nx2, Breite m je Punkt, Stärke 0..1 je Punkt);
    ext = (x0, z0, x1, z1) der Rasterfläche. Rückgabe: float32-Array 0..1 (Maximum der Striche)."""
    H, W = shape
    ex0, ez0, ex1, ez1 = ext
    sx, sz = W / (ex1 - ex0), H / (ez1 - ez0)
    img = np.zeros((H, W), np.float32)
    for pts, ws, ss in strokes:
        for i in range(len(pts) - 1):
            ax, az = pts[i]
            bx, bz = pts[i + 1]
            w = 0.5 * (ws[i] + ws[i + 1])
            s = 0.5 * (ss[i] + ss[i + 1])
            if s <= 0.01 or w <= 0.0:
                continue
            r = w / 2.0
            i0 = int(max(0, math.floor((min(ax, bx) - r - ex0) * sx)))
            i1 = int(min(W, math.ceil((max(ax, bx) + r - ex0) * sx) + 1))
            j0 = int(max(0, math.floor((min(az, bz) - r - ez0) * sz)))
            j1 = int(min(H, math.ceil((max(az, bz) + r - ez0) * sz) + 1))
            if i1 <= i0 or j1 <= j0:
                continue
            xs_ = ex0 + (np.arange(i0, i1) + 0.5) / sx
            zs_ = ez0 + (np.arange(j0, j1) + 0.5) / sz
            XX, ZZ = np.meshgrid(xs_, zs_)
            dx, dz = bx - ax, bz - az
            l2 = dx * dx + dz * dz
            t = np.clip(((XX - ax) * dx + (ZZ - az) * dz) / l2, 0.0, 1.0) if l2 > 1e-9 else np.zeros_like(XX)
            d = np.hypot(XX - (ax + t * dx), ZZ - (az + t * dz))
            m = hb_smooth(1.0 - d / r, 0.0, 1.0) * s
            sub = img[j0:j1, i0:i1]
            np.maximum(sub, m.astype(np.float32), out=sub)
    return img


def hb_corners(min_k=0.034):
    """Kurven der Mittellinie: Gruppen aufeinanderfolgender Punkte mit starker Krümmung. Rückgabe: Liste (Index-Anfang, Index-Ende, Scheitel, Vorzeichen)."""
    tr = HB["track"]
    n = tr.count
    T = tr.T
    k = np.zeros(n)
    for i in range(n):
        a, b = T[(i - 3) % n], T[(i + 3) % n]
        k[i] = math.atan2(a[0] * b[1] - a[1] * b[0], a[0] * b[0] + a[1] * b[1]) / 3.0
    hot = np.abs(k) > min_k
    groups = []
    i = 0
    start = next((j for j in range(n) if not hot[j]), None)
    if start is None:
        return []
    i = start
    cur = None
    for step in range(1, n + 1):
        j = (start + step) % n
        if hot[j]:
            if cur is None:
                cur = [j, j]
            else:
                cur[1] = j
        else:
            if cur is not None:
                groups.append(cur)
                cur = None
    if cur is not None:
        groups.append(cur)
    out = []
    for g in groups:
        idx = [(g[0] + q) % n for q in range(((g[1] - g[0]) % n) + 1)]
        if len(idx) * 0.5 < 5.0:
            continue
        apex = max(idx, key=lambda q: abs(k[q]))
        out.append({"i0": g[0], "i1": g[1], "apex": apex, "sign": 1.0 if np.mean(k[idx]) > 0 else -1.0, "n": len(idx), "k": float(np.mean(np.abs(k[idx])))})
    return out


def hb_offset_path(i0, count, off, side):
    """Punkte parallel zur Mittellinie ab Index i0 (count Punkte), seitlicher Abstand = Halbbreite + 0,55 + off auf Seite side (+1 links)."""
    tr = HB["track"]
    n = tr.count
    pts = []
    for q in range(count):
        i = (i0 + q) % n
        o = tr.HW[i] + 0.55 + off
        pts.append(tr.P[i] + tr.Lft[i] * side * o)
    return np.array(pts)


def hb_plan_rubber(scale=1.0):
    """Reifenspuren und Rauch: Striche entlang der Außenseite jeder Kurve (Auslauf neben der Fahrbahn), Driftkreise auf freien Flächen."""
    tr = HB["track"]
    rng_ = random.Random(77)
    n = tr.count
    strokes = []                                           # (Punkte, Breiten, Stärken) in Weltkoordinaten
    smoke = []
    for ci, c in enumerate(HB["corners"]):
        outer = -c["sign"]
        i0 = (c["i0"] - 24) % n
        cnt = c["n"] + 48
        for (off, w, s) in ((0.9, 0.5, 0.85), (1.7, 0.7, 0.7), (2.9, 1.0, 0.6), (4.6, 1.5, 0.42), (6.5, 2.2, 0.28)):
            pts = hb_offset_path(i0, cnt, off + rng_.uniform(-0.4, 0.4), outer)
            idx = (np.arange(cnt) + i0) % n
            fade = np.clip(np.minimum(np.arange(cnt), cnt - 1 - np.arange(cnt)) / 14.0, 0.0, 1.0)
            noise = np.array([0.45 + 0.55 * float(hb_vnoise(pts[q, 0], pts[q, 1], 2.3, ci * 7.0, off * 5.0)) for q in range(cnt)])
            strokes.append((pts, np.full(cnt, w), fade * noise * s * scale))
        for (off, w, s) in ((2.5, 5.0, 0.20), (5.5, 8.0, 0.12)):
            pts = hb_offset_path(i0, cnt, off, outer)
            fade = np.clip(np.minimum(np.arange(cnt), cnt - 1 - np.arange(cnt)) / 18.0, 0.0, 1.0)
            smoke.append((pts, np.full(cnt, w), fade * s * scale))
        # Innenseite am Scheitel: kurze Schleifspur
        pts = hb_offset_path((c["apex"] - 12) % n, 24, 1.0 + rng_.uniform(0, 1.0), c["sign"])
        fade = np.clip(np.minimum(np.arange(24), 23 - np.arange(24)) / 6.0, 0.0, 1.0)
        strokes.append((pts, np.full(24, 0.7), fade * 0.55 * scale))
    # Driftkreise (Donuts): konzentrische Spuren auf freien Flächen
    for (cx, cz, r0) in HB.get("donuts", []):
        for k, rr in enumerate((r0, r0 - 0.9, r0 - 1.8)):
            ang = np.linspace(0, 2 * math.pi, 120)
            pts = np.stack([cx + rr * np.cos(ang), cz + rr * np.sin(ang)], 1)
            s = np.array([0.5 + 0.5 * float(hb_vnoise(p[0], p[1], 1.7, k * 3.0, 9.0)) for p in pts]) * (0.75 - 0.15 * k)
            strokes.append((pts, np.full(120, 0.8 - 0.1 * k), s))
        ang = np.linspace(0, 2 * math.pi, 120)
        pts = np.stack([cx + (r0 - 0.9) * np.cos(ang), cz + (r0 - 0.9) * np.sin(ang)], 1)
        smoke.append((pts, np.full(120, 5.0), np.full(120, 0.18)))
    HB["rubber"] = strokes
    HB["smoke"] = smoke
    print("DIORAMA Gummispuren:", len(strokes), "Striche,", len(smoke), "Rauchbänder")


def hb_plan_oil():
    """Ölflecken und Tropfspuren in den Gassen (Striche für die Lichttextur und die Verschleißgewichte)."""
    rng_ = random.Random(44)
    lanes = [ln for ln in HB["lanes"] if ((ln[4] - ln[3]) if ln[5] else (ln[2] - ln[1])) >= 4.4]
    if not lanes:
        return
    for _ in range(46):
        axis, a0, a1, b0, b1, across = rng_.choice(lanes)
        if across:
            a_, b_ = rng_.uniform(a0, a1), rng_.uniform(b0, b1)
        else:
            a_, b_ = rng_.uniform(a0, a1), rng_.uniform(b0, b1)
        x, z = (a_, b_) if axis == "x" else (b_, a_)
        ang = rng_.uniform(0, 3.14)
        ln = rng_.uniform(0.4, 2.6)
        pts = np.array([(x, z), (x + math.cos(ang) * ln, z + math.sin(ang) * ln)])
        HB["rubber"].append((pts, np.array([rng_.uniform(0.7, 1.8)] * 2), np.array([rng_.uniform(0.25, 0.55)] * 2)))
        if rng_.random() < 0.4:
            HB["smoke"].append((pts, np.array([rng_.uniform(2.0, 3.5)] * 2), np.array([0.14] * 2)))


def hb_build_rubber_raster():
    """Grobes Raster (0,5 m) der Gummi-/Rauchspuren für die Verschleiß-Gewichte des Bodens."""
    step = 0.5
    nx, nz = int(math.ceil((x1 - x0) / step)), int(math.ceil((z1 - z0) / step))
    img = hb_stroke_raster((nz, nx), HB["smoke"] + HB["rubber"], (x0, z0, x1, z1))
    HB["rub"] = ndi_blur(img, 1.0)
    HB["rub_step"] = step


def hb_rub_at(X, Z):
    g = HB["rub"]
    step = HB["rub_step"]
    i = np.clip(((np.asarray(X, float) - x0) / step).astype(int), 0, g.shape[1] - 1)
    j = np.clip(((np.asarray(Z, float) - z0) / step).astype(int), 0, g.shape[0] - 1)
    return g[j, i]


def hb_paint_ao(extra_strokes=()):
    """Nach dem Backen: Gummispuren, Rauch und Ölspuren in die Lichttextur (Umgebungsverdeckung) multiplizieren. Die Textur gilt für alle
    Objekte mit der Licht-UV (Boden, Markierungen); die Laufzeit-Fahrbahn liest sie nicht (Spuren dort kommen aus dem Spiel)."""
    strokes_dark = list(HB.get("rubber", [])) + list(extra_strokes)
    smoke = list(HB.get("smoke", []))
    if not strokes_dark and not smoke:
        return
    try:
        img = bpy.data.images.load(OUT_AO, check_existing=False)
        img.colorspace_settings.name = "Non-Color"
        w, h = img.size
        px = np.empty(w * h * 4, np.float32)
        img.pixels.foreach_get(px)
        px = px.reshape(h, w, 4)
        ext = (x0, z0, x1, z1)
        dark = hb_stroke_raster((h, w), strokes_dark, ext)
        haze = hb_stroke_raster((h, w), smoke, ext) if smoke else 0.0
        mask = np.clip(dark * 0.88 + haze * 0.55, 0.0, 0.92)[::-1]             # Blender-Zeile 0 = unten (Süden)
        px[..., :3] *= (1.0 - mask)[..., None]
        img.pixels.foreach_set(px.ravel())
        img.update()
        img.file_format = "JPEG"
        img.filepath_raw = OUT_AO
        img.save()
        print("DIORAMA Lichttextur mit Spuren überlagert:", w, "x", h, "mittlere Abdunklung", round(float(np.mean(mask)), 4))
    except Exception as err:
        print("DIORAMA Spuren in der Lichttextur nicht möglich:", err)


# ---------------------------------------------------------------- Drift Arena: Planung
HB_ARENA_PAD = (-92.0, -47.0, 70.0, 43.0)             # Betonfläche der Arena (x0, z0, x1, z1); dahinter Asphalt, Stapel und Zäune


def hb_flag_pole(parts, x, z, col, height=4.2, ang=0.0, y0=None):
    """Fahnenmast mit wehender Fahne (vier Stücke, Vertexfarbe; Wehen im Shader)."""
    gy = GROUND_Y if y0 is None else y0
    hb_cuboid(parts["stahl"], x, z, 1.0, 0.0, 0.03, 0.03, gy, gy + height + 0.1, "stahl", col=(0.9, 0.9, 0.92), tile=1.0, bottom_fade=False)
    fr = HbFrame(x, z, math.cos(ang), math.sin(ang))
    c = hb_lin(col)
    length, h = 1.3, 0.85
    n = 4
    for k in range(n):
        a0, a1 = 0.03 + k * length / n, 0.03 + (k + 1) * length / n
        p0, p1 = fr.p(a0, 0.0, gy + height - h), fr.p(a1, 0.0, gy + height - h)
        q0, q1 = fr.p(a1, 0.0, gy + height), fr.p(a0, 0.0, gy + height)
        hb_quad(parts["e:flagge"], "e:flagge", [p0, p1, q0, q1], [(k / n, 0.0), ((k + 1) / n, 0.0), ((k + 1) / n, 1.0), (k / n, 1.0)], None, [c] * 4)


def hb_plan_yard_masts():
    """Flutlichtmasten im Containerhof (Hafen): in den Gassen der Felder, mindestens 30 m auseinander, nie im Fahrschlauch; die Strahler zielen zur Hofmitte."""
    HB["masts"] = []
    rng_ = random.Random(77)
    rects = [(-58, -22, 56, 22), (-96, -39, -73, 36), (69, -39, 97, 38), (22, -28.5, 66, -9), (-96, 38, -66, 63)]
    for (xa, za, xb, zb) in rects:
        want = max(1, int(((xb - xa) * (zb - za)) / 1500.0))
        got, tries = 0, 0
        while got < want and tries < 400:
            tries += 1
            x, z = rng_.uniform(xa + 3, xb - 3), rng_.uniform(za + 3, zb - 3)
            if any(math.hypot(x - m["p"][0], z - m["p"][1]) < 30.0 for m in HB["masts"]):
                continue
            if hb_circle_solid(x, z, 0.55, HB_MAST_H, "mast", margin=2.5):
                HB["masts"].append({"p": (x, z), "aim": (0.0, 0.0), "focus": (x, z), "energy": 0.85, "range": 30.0})
                got += 1
    print("DIORAMA Hof: Flutlichtmasten", len(HB["masts"]))


def hb_plan_arena():
    """Arena: Portal, Kurvenmarkierungen, Boxengasse im Innenfeld, Richterturm, Zuschauerzeilen, Stapel am Rand, Laternen. Läuft in theme_materials."""
    tr = HB["track"]
    HB["corners"] = hb_corners()
    print("DIORAMA Kurven:", [(c["apex"], round(c["k"], 3), int(c["sign"])) for c in HB["corners"]])
    HB["trucks"] = []
    HB["boxtrucks"] = []
    HB["service"] = []
    hb_portal_plan(0.0, cantilever=False)
    HB["conc_rects"].append(HB_ARENA_PAD)
    # Leitkegel-/Zonen-Plan je Kurve wird beim Bauen aus HB["corners"] erzeugt; Geräte im Innenfeld:
    HB["donuts"] = [(18.0, 3.5, 6.5), (-64.0, -37.0, 6.0), (48.0, 30.0, 6.0), (-62.0, 32.0, 6.0)]
    hb_plan_rubber()
    HB["paddock"] = []
    # Boxengasse: Zelte in Teamfarben, Transporter dahinter, Reifenstapel, Aggregate; Positionen im linken Innenfeld
    tent_cols = [(0.82, 0.10, 0.08), (0.10, 0.28, 0.62), (0.10, 0.5, 0.25), (0.95, 0.5, 0.05), (0.6, 0.6, 0.62), (0.4, 0.1, 0.5)]
    pad_items = []
    for k in range(5):
        x = -46.0 + k * 5.2
        pad_items.append(("tent", x, -4.5, 0.0, tent_cols[k % len(tent_cols)]))
    for k, (x, z) in enumerate(((-40.0, 8.0), (-27.0, 8.6), (-53.0, 7.0))):
        pad_items.append(("truck", x, z, 0.0, tent_cols[(k + 1) % len(tent_cols)]))
    for (x, z) in ((-47.0, 1.5), (-42.8, 1.8), (-27.0, 2.0), (-23.0, 1.6)):
        pad_items.append(("tyres", x, z, 0.0, None))
    pad_items.append(("gen", -49.0, -2.0, 0.3, None))
    pad_items.append(("gen", -19.5, -3.0, 2.8, None))
    HB["paddock_items"] = []
    for kind, x, z, ang, col in pad_items:
        if kind == "tent":
            ux, uz = math.cos(ang), math.sin(ang)
            ok = hb_solid(x, z, ux, uz, 1.5, 1.5, 3.0, "mauer", margin=2.5, pad=0.4)
        elif kind == "truck":
            ok = hb_solid(x, z, 1.0, 0.0, 5.0, 1.4, 3.6, "auto", margin=2.5, pad=0.3)
        elif kind == "tyres":
            ok = hb_free(x, z, 1.0, 0.0, 0.5, 0.5, 2.5, 0.2)
            if ok:
                hb_occupy(x, z, 1.0, 0.0, 0.5, 0.5)
        else:
            ux, uz = math.cos(ang), math.sin(ang)
            ok = hb_solid(x, z, ux, uz, 1.25, 0.6, 1.5, "mauer", margin=2.5, pad=0.2)
        if ok:
            HB["paddock_items"].append((kind, x, z, ang, col))
            if kind == "truck":
                HB["boxtrucks"].append({"c": (x, z), "u": (1.0, 0.0), "cab": (0.9, 0.9, 0.88), "body": col, "seed": int(x * 7 + z) & 0xFFFF})
    HB["conc_rects"].append((-52.0, -12.0, -16.0, 5.0))
    # Richterturm am Start/Ziel auf der Innenseite
    HB["tower"] = None
    for (tx, tz, ta) in ((-12.0, 10.5, 0.0), (-6.0, 11.0, 0.0), (-20.0, 11.0, 0.0), (0.0, 12.0, 0.0)):
        if hb_solid(tx + 0.4, tz, 1.0, 0.0, 2.6, 1.7, 3.2, "mauer", margin=2.0, pad=0.4):
            HB["tower"] = (tx, tz, ta)
            break
    for (ax_, az_) in ((26.0, 7.0), (-2.0, 14.5), (-36.0, 9.5)):
        if hb_solid(ax_, az_, 1.0, 0.0, 2.8, 1.1, 2.7, "auto", margin=2.0, pad=0.3):
            HB["service"].append({"c": (ax_, az_), "u": (1.0, 0.0)})
            break
    hb_plan_arena_extras()
    # Zuschauerzeilen (Zaun, Banner, Menge dahinter): Linienzüge; die Menge steht auf der Seite side (+1 links der Richtung a->b)
    HB["crowd_lines"] = [((-56.0, 38.8), (46.0, 38.8), 1.0), ((-62.0, -43.0), (56.0, -43.0), -1.0), ((-77.0, -30.0), (-77.0, 28.0), 1.0),
                         ((57.5, -26.0), (57.5, 28.0), -1.0)]
    # Containerfelder am Rand der Arena (außerhalb der Zuschauerzeilen)
    HB["fields_done"] = []
    fields = [((2, -62, 77, -50), "x", 4, 3, 5.4, 6.4, 0.85, (1, 3), 41), ((-99, -62, -40, -50), "x", 4, 3, 5.4, 6.4, 0.85, (1, 3), 42),
              ((-99, -46, -86, 56), "z", 3, 5, 5.4, 6.0, 0.8, (1, 3), 43), ((72, -46, 78, 56), "z", 2, 5, 5.4, 6.0, 0.8, (1, 3), 44),
              ((-99, 47, -10, 59), "x", 4, 3, 5.4, 6.4, 0.85, (1, 3), 45), ((10, 48, 71, 59), "x", 4, 3, 5.4, 6.4, 0.85, (1, 3), 46)]
    for rect, axis, rows, bays, la, lb, dens, tiers, seed in fields:
        n = hb_plan_field(rect, axis, rows, bays, la, lb, dens, tiers, margin=3.0, seed=seed)
        print("DIORAMA Containerfeld", rect, ":", n, "Stapel")
    rng_ = random.Random(53)
    cab_cols = [(0.85, 0.85, 0.83), (0.12, 0.20, 0.42), (0.78, 0.10, 0.08), (0.12, 0.45, 0.28)]
    for (cx, cz, ux, uz) in ((-60.0, 52.0, 1.0, 0.0), (30.0, 53.0, 1.0, 0.0)):
        rc = hb_truck_rect(cx, cz, ux, uz)
        if hb_solid(rc[0], rc[1], rc[2], rc[3], rc[4], rc[5], 4.2, "auto", margin=2.0, pad=0.3):
            HB["trucks"].append({"c": (cx, cz), "u": (ux, uz), "cab": rng_.choice(cab_cols), "cont": hb_pick_color(rng_), "seed": rng_.randrange(1 << 20)})
    # Laternen: beidseits der Fahrbahn (neben dem Randstein) alle 17 m, dazu entlang der Zuschauerzeilen und im Innenfeld
    HB["lamps"] = []
    cand = []
    for side in (1.0, -1.0):
        s_ = 0.0 if side > 0 else 8.5 / tr.length
        while s_ < 1.0:
            p_, t_ = tr.at(s_)
            lf = np.array([-t_[1], t_[0]])
            off = tr.hw(s_) + 0.55 + 1.5
            cand.append((p_ + lf * side * off, p_ + lf * side * (off - 4.0)))
            s_ += 30.0 / tr.length                                 # Flutlicht übernimmt die Fläche: die Laternen stehen nur noch locker an der Fahrbahn
    cand += [(np.array([x, 36.8]), np.array([x, 30.0])) for x in (-40.0, 0.0, 38.0)]               # locker an den Zuschauerzeilen: das Flutlicht beleuchtet die Fläche
    cand += [(np.array([x, -41.5]), np.array([x, -36.0])) for x in (-40.0, 0.0, 40.0)]
    cand += [(np.array([-73.5, z]), np.array([-68.0, z])) for z in (-12.0, 12.0)] + [(np.array([55.0, z]), np.array([50.0, z])) for z in (-12.0, 12.0)]
    cand += [(np.array([-32.0, -10.5]), np.array([-32.0, -4.0])), (np.array([-32.0, 7.0]), np.array([-32.0, 2.0]))]
    for pos, toward in cand:
        if hb_free(float(pos[0]), float(pos[1]), 1.0, 0.0, 0.3, 0.3, 1.0, 0.2):
            hb_occupy(float(pos[0]), float(pos[1]), 1.0, 0.0, 0.8, 0.8)
            HB["lamps"].append((float(pos[0]), float(pos[1]), float(toward[0]), float(toward[1])))
    hb_plan_clutter()
    hb_plan_wheel_tracks()
    HB["cars"] = []
    print("DIORAMA Laternen:", len(HB["lamps"]), " Paddock:", len(HB["paddock_items"]), " Turm:", HB["tower"])


# ---------------------------------------------------------------- Drift Arena: Flutlichtmasten (echte Lichtquellen), Tribünen, Teamautos im Fahrerlager
HB_FLOOD_ENERGY = 0.44            # Stärke des mittleren Lichtflecks eines Flutlichtmastes (1,0 = Straßenlaterne)
HB_FLOOD_RANGE = 36.0             # Radius je Lichtfleck am Boden (m)
HB_FLOOD_REACH = ((0.22, 1.0), (0.50, 0.95), (0.80, 0.68))   # Lage der Lichtflecke zwischen Mast und Arenamitte (Anteil der Entfernung) und relative Stärke: die Scheinwerfer
                                  # zielen auf drei Punkte; der Rand hinter dem Mast bleibt dunkler (kein Ausbrennen), Fahrbahn und Innenfeld bekommen das meiste Licht
HB_MAST_H = 12.5 if IS_ARENA else 14.5


def hb_plan_arena_extras():
    """Flutlichtmasten (statt der vier Flutlichter der Streckendatei: THEME_CFG baked "floodlight"), zwei Gerüsttribünen hinter den Zuschauerzeilen
    im Osten und Westen und Teamautos vor den Boxenzelten. Läuft in hb_plan_arena, nach Boxengasse und Richterturm."""
    HB["masts"] = []
    center = np.array([-11.0, -2.0])
    for (x, z) in ((-80.0, 30.0), (60.0, 30.0), (60.0, -35.0), (-80.0, -35.0), (-8.0, 43.0), (-8.0, -47.0)):
        if hb_circle_solid(x, z, 0.55, HB_MAST_H, "mast", margin=1.5):
            d = center - np.array([x, z])
            ln = float(np.hypot(*d))
            u_ = d / max(ln, 1e-6)
            e_ = HB_FLOOD_ENERGY * float(np.clip(ln / 70.0, 0.55, 1.0))                 # kurze Wege (Masten am Nord-/Südrand) leuchten schwächer
            pools = [(float(x + u_[0] * ln * t), float(z + u_[1] * ln * t), e_ * w_, HB_FLOOD_RANGE) for (t, w_) in HB_FLOOD_REACH]
            aim = (float(x + u_[0] * ln * 0.45), float(z + u_[1] * ln * 0.45))
            HB["masts"].append({"p": (x, z), "aim": aim, "pools": pools})
    HB["stands"] = []
    for (fx, fz, bx, bz, length, depth) in ((59.9, 1.0, 1.0, 0.0, 46.0, 5.6), (-79.4, -1.0, -1.0, 0.0, 46.0, 5.6)):
        ux, uz = bz, -bx
        cx, cz = fx + bx * depth / 2, fz + bz * depth / 2
        if hb_solid(cx, cz, ux, uz, length / 2 + 0.2, depth / 2 + 0.1, 3.6, "mauer", margin=2.0, pad=0.2):
            HB["stands"].append({"f": (fx, fz), "b": (bx, bz), "length": length, "depth": depth, "seed": len(HB["stands"]) * 3})
    HB["pit_cars"] = []
    tents = [it for it in HB["paddock_items"] if it[0] == "tent"]
    for k, (_kind, x, z, _ang, col) in enumerate(tents):
        cz = z + 2.3
        if HB["track"].rect_slack(x, cz, 0.0, 1.0, 0.95, 2.3) >= 1.5:
            HB["pit_cars"].append((x, cz, "limousine" if k % 2 == 0 else "fliessheck", col))
            HB["solids"].append((x, cz, 0.0, 1.0, 2.3, 0.95, 1.5, "auto"))
    print("DIORAMA Arena: Masten", len(HB["masts"]), " Tribünen", len(HB["stands"]), " Boxenautos", len(HB["pit_cars"]))


def hb_floodlight_mast(parts, x, z, tx, tz, height=HB_MAST_H):
    """Flutlichtmast: Betonfundament, Sockelflansch, konischer Stahlrohrmast (acht Seiten), Wartungsplattform mit Geländer, Steigleiter, Schaltschrank und
    oben ein Trägerrahmen mit zwei Reihen zu je vier Scheinwerfern (Gehäuse, Blende, Linse), die zum Punkt (tx, tz) hin geneigt sind.
    Rückgabe: Höhe des Lampenkopfs (m)."""
    gy = GROUND_Y
    dx, dz = tx - x, tz - z
    n = math.hypot(dx, dz) or 1.0
    ux, uz = dx / n, dz / n                                  # Blickrichtung der Scheinwerfer (+a); b quer dazu
    fr = HbFrame(x, z, ux, uz)
    hb_cuboid(parts["beton"], x, z, ux, uz, 0.8, 0.8, gy, gy + 0.45, "beton", col=(0.9, 0.9, 0.9), tile=1.5, bottom_fade=False)
    hb_prism(parts["stahl"], x, z, 0.38, gy + 0.45, gy + 0.62, "stahl", (0.7, 0.72, 0.75), 8, tile=1.0)
    hb_prism(parts["stahl"], x, z, 0.27, gy + 0.62, gy + height, "stahl", (0.82, 0.84, 0.87), 8, r_top=0.15, tile=2.0, cap_col=(0.7, 0.72, 0.75))
    # Wartungsplattform bei zwei Dritteln der Höhe
    yp = gy + height * 0.68
    hb_prism(parts["stahl_dunkel"], x, z, 0.85, yp - 0.05, yp, "stahl_dunkel", (0.9, 0.9, 0.92), 8, tile=1.0, cap_col=(1.1, 1.1, 1.15))
    hb_railing(parts["stahl"], [fr.p(0.7, -0.7, 0)[:2], fr.p(0.7, 0.7, 0)[:2], fr.p(-0.7, 0.7, 0)[:2], fr.p(-0.7, -0.7, 0)[:2], fr.p(0.7, -0.7, 0)[:2]], y0=yp, height=0.9,
               key="stahl", col=(0.85, 0.87, 0.9), post_every=1.4, collide=False)
    # Steigleiter an der Rückseite (-a): zwei Holme und Sprossen
    for sb in (-0.14, 0.14):
        hb_box_l(parts["stahl"], "stahl", fr, -0.36, -0.30, sb - 0.015, sb + 0.015, gy + 0.9, gy + height - 0.2, (0.75, 0.77, 0.8), (1.0, 1.0))
    for k in range(int((height - 1.4) / 0.5)):
        hb_box_l(parts["stahl"], "stahl", fr, -0.37, -0.30, -0.14, 0.14, gy + 1.0 + k * 0.5, gy + 1.02 + k * 0.5, (0.75, 0.77, 0.8), (1.0, 1.0))
    # Schaltschrank am Fuß
    hb_box_l(parts["stahl_dunkel"], "stahl_dunkel", fr, -0.7, -0.15, 0.9, 1.7, gy, gy + 1.25, (0.55, 0.62, 0.58), (0.8, 1.0))
    top = gy + height
    # Kopf: Querträger und zwei Reihen Scheinwerfer
    hb_box_l(parts["stahl"], "stahl", fr, -0.15, 0.15, -2.1, 2.1, top - 0.1, top + 0.1, (0.75, 0.77, 0.8), (1.0, 1.0))
    for row, ry in enumerate((top + 0.12, top - 0.6)):
        for j in range(4):
            bc = -1.5 + j * 1.0
            hb_box_l(parts["stahl_dunkel"], "stahl_dunkel", fr, -0.1, 0.5, bc - 0.38, bc + 0.38, ry, ry + 0.45, (0.55, 0.57, 0.6), (0.8, 1.0))        # Gehäuse
            # Linse (leicht nach unten geneigte Frontfläche, hell) und Blende darüber
            q = [fr.p(0.5, bc - 0.34, ry + 0.02), fr.p(0.62, bc - 0.34, ry + 0.4), fr.p(0.62, bc + 0.34, ry + 0.4), fr.p(0.5, bc + 0.34, ry + 0.02)]
            hb_quad(parts["lack"], "lack", q, [(0, 0), (1, 0), (1, 1), (0, 1)], fr.d(1.0, 0.0), [(1.5, 1.45, 1.25)] * 4)
            hb_box_l(parts["stahl_dunkel"], "stahl_dunkel", fr, 0.1, 0.62, bc - 0.4, bc + 0.4, ry + 0.45, ry + 0.5, (0.5, 0.5, 0.52), (1.0, 1.0))
    # Verbindung Mast - Kopf: zwei Streben
    for sb in (-1.0, 1.0):
        p0, p1 = fr.p(0.0, 0.0, top - 0.8), fr.p(0.0, sb * 1.6, top - 0.15)
        hb_quad(parts["stahl"], "stahl", [p0, p1, (p1[0], p1[1], p1[2] + 0.06), (p0[0], p0[1], p0[2] + 0.06)], [(0, 0), (1, 0), (1, 1), (0, 1)], fr.d(1.0, 0.0), [(0.75, 0.77, 0.8)] * 4)
    return top


def hb_build_masts():
    """Alle Flutlichtmasten bauen und je Mast zwei echte Lichter eintragen: einen kleinen hellen Fleck am Lampenkopf (Glühen nur dort) und das
    eigentliche Flutlicht mit Schwerpunkt vor dem Mast (die Strahler zielen in die Arena; so brennt der Rand nicht aus)."""
    parts = hb_new_parts("stahl", "stahl_dunkel", "beton", "lack")
    col = (0.92, 0.96, 1.0) if IS_ARENA else (1.0, 0.93, 0.80)
    for m in HB.get("masts", []):
        x, z = m["p"]
        top = hb_floodlight_mast(parts, x, z, m["aim"][0], m["aim"][1])
        dx, dz = m["aim"][0] - x, m["aim"][1] - z
        n = math.hypot(dx, dz) or 1.0
        add_light(x + dx / n * 0.4, z + dz / n * 0.4, top - 0.3, color=col, energy=0.02, range=2.5, omni=False, glow=2.0)
        for (px_, pz_, pe_, pr_) in m.get("pools") or [(m["focus"][0], m["focus"][1], m["energy"], m["range"])]:
            add_light(px_, pz_, top - 1.0, color=col, energy=pe_, range=pr_, omni=False)
    for k, v in parts.items():
        if v:
            mesh_objects("Mast_" + k, v)


def hb_stand(parts, fx, fz, bx, bz, length, depth, n_tiers=4, seed=0):
    """Gerüsttribüne: Stufen aus Aluminiumdecks mit Werbebannern an den Stirnseiten der Stufen, Menge auf den Decks, Stützen, Seitenwände, Geländer vorn und
    hinten, Fahnenmasten oben, Treppe an einem Ende. (fx, fz) = Mitte der Vorderkante (Arena-Seite), (bx, bz) = Richtung nach hinten (steigt an)."""
    ux, uz = bz, -bx
    g = Frame((fx, fz), (ux, uz), (bx, bz))
    fr = HbFrame(fx, fz, ux, uz)
    gy = GROUND_Y
    td = depth / n_tiers
    h0, rise = 0.75, 0.8
    L2 = length / 2
    steel = (0.78, 0.8, 0.84)
    dark = hb_lin((0.12, 0.13, 0.15))
    n_seg = max(2, int(round(length / 2.3)))
    seg = length / n_seg
    n_post = max(2, int(length // 4.0))
    prev_y = gy
    for k in range(n_tiers):
        b0, b1 = k * td, (k + 1) * td
        y = gy + h0 + k * rise
        hb_quad(parts["stahl"], "stahl", [fr.p(-L2, b0, y), fr.p(L2, b0, y), fr.p(L2, b1, y), fr.p(-L2, b1, y)],
                [(-L2 / 2, b0 / 2), (L2 / 2, b0 / 2), (L2 / 2, b1 / 2), (-L2 / 2, b1 / 2)], None, [steel] * 4)
        parts["e:menge"].append(crowd_quad(g, -L2 + 0.1, L2 - 0.1, b0 + 0.12, b1 - 0.06, y + 0.004, k * 2.7 + seed * 5.0))
        for j in range(n_seg):
            a0, a1 = -L2 + j * seg, -L2 + (j + 1) * seg
            parts["e:banner"].append(hb_banner_cell(g, a0 + 0.04, a1 - 0.04, b0 - 0.02, prev_y + 0.04, y - 0.02, -1, (j * 3 + k * 5 + seed) % 8))
        for j in range(n_post + 1):
            px, pz, _ = fr.p(-L2 + j * length / n_post, b0 + 0.08, 0)
            hb_cuboid(parts["stahl_dunkel"], px, pz, ux, uz, 0.05, 0.05, gy, y - 0.02, "stahl_dunkel", col=(0.9, 0.9, 0.92), tile=1.0, bottom_fade=False)
        prev_y = y
    top_y = gy + h0 + (n_tiers - 1) * rise
    for sgn in (-1, 1):                                                                       # Seitenwände (gestuftes Profil)
        for k in range(n_tiers):
            y = gy + h0 + k * rise
            hb_quad(parts["stahl_dunkel"], "stahl_dunkel", [fr.p(sgn * L2, k * td, gy), fr.p(sgn * L2, (k + 1) * td, gy), fr.p(sgn * L2, (k + 1) * td, y), fr.p(sgn * L2, k * td, y)],
                    [(0, 0), (1, 0), (1, 1), (0, 1)], fr.d(sgn, 0.0), [dark] * 4)
    # Geländer: vorn auf der ersten Stufe, hinten auf der obersten, Fahnen oben
    hb_railing(parts["stahl"], [fr.p(-L2, 0.18, 0)[:2], fr.p(L2, 0.18, 0)[:2]], y0=gy + h0, height=0.9, key="stahl", col=(0.85, 0.87, 0.9), post_every=2.3, collide=False)
    hb_railing(parts["stahl"], [fr.p(-L2, depth - 0.1, 0)[:2], fr.p(L2, depth - 0.1, 0)[:2]], y0=top_y, height=1.1, key="stahl", col=(0.85, 0.87, 0.9), post_every=2.3, collide=False)
    for j in range(n_post + 1):                                                               # hintere Stützen bis zum Boden
        px, pz, _ = fr.p(-L2 + j * length / n_post, depth - 0.1, 0)
        hb_cuboid(parts["stahl_dunkel"], px, pz, ux, uz, 0.07, 0.07, gy, top_y - 0.02, "stahl_dunkel", col=(0.9, 0.9, 0.92), tile=1.0, bottom_fade=False)
    flag_cols = [(0.70, 0.03, 0.02), (0.86, 0.86, 0.84), (0.02, 0.08, 0.50), (0.90, 0.50, 0.02)]
    for j, a in enumerate((-L2 + 2.0, -L2 / 2, 0.0, L2 / 2, L2 - 2.0)):
        px, pz, _ = fr.p(a, depth - 0.3, 0)
        hb_flag_pole(parts, px, pz, flag_cols[(j + seed) % 4], 3.2, math.atan2(uz, ux), y0=top_y)
    for k in range(n_tiers):                                                                  # Treppe am +a-Ende
        hb_box_l(parts["stahl_dunkel"], "stahl_dunkel", fr, L2 + 0.05, L2 + 1.05, k * td, (k + 1) * td, gy, gy + 0.35 + k * rise, (0.9, 0.9, 0.92), (1.0, 1.0))


def hb_build_stands():
    parts = hb_new_parts("stahl", "stahl_dunkel", "e:banner", "e:menge", "e:flagge")
    for st in HB.get("stands", []):
        hb_stand(parts, st["f"][0], st["f"][1], st["b"][0], st["b"][1], st["length"], st["depth"], 4, st["seed"])
        ux, uz = st["b"][1], -st["b"][0]
        fx, fz = st["f"]
        bx, bz = st["b"]
        L2, dp = st["length"] / 2, st["depth"]
        poly = [(fx + ux * a + bx * b, fz + uz * a + bz * b) for a, b in ((-L2, 0.0), (L2, 0.0), (L2, dp), (-L2, dp))]
        add_occluder_poly(poly, height=3.6)                                                  # die Tribüne wirft Schatten im Licht der Masten
    for k, v in parts.items():
        if v:
            objs = mesh_objects("Tribuene_" + k.replace(":", "_"), v)
            if k == "e:menge":
                event_decals.extend(objs)


def hb_build_pit_cars():
    """Teamautos halb unter den Zelten (Heck unter dem Dach, Bug zur Boxengasse)."""
    parts = []
    for (x, cz, kind, col) in HB.get("pit_cars", []):
        parts += kit_car.car_parts(x, cz, 0.0, 1.0, kind, hb_lin(col), base_y=GROUND_Y)
    if parts:
        mesh_objects("Boxenauto", parts)


# ---------------------------------------------------------------- Drift Arena: Kurvenmarkierungen, Leitkegel, Richterturm, Zuschauerzeilen
def hb_build_corner_marks(dec_yellow, dec_white, cone_parts):
    """Je Kurve eine Driftzone auf der Innenseite (gelbe Schrägstreifen mit weißem Rand und Kurvennummer) und Leitkegel am Scheitelpunkt."""
    tr = HB["track"]
    n = tr.count
    y = GROUND_Y + 0.004
    rng_ = HB["rng"]
    count_bars = 0

    def radius_at(i):
        """Krümmungsradius der Mittellinie (m) bei Index i (Winkel zwischen den Tangenten +-3 Punkte)."""
        ta, tb = tr.T[(i - 3) % n], tr.T[(i + 3) % n]
        k_ = abs(math.atan2(ta[0] * tb[1] - ta[1] * tb[0], ta[0] * tb[0] + ta[1] * tb[1])) / 3.0
        return 1.0 / max(k_, 1e-6)
    for ci, c in enumerate(HB["corners"]):
        side = c["sign"]
        apex = c["apex"]
        rungs = []
        last_in = None
        for q in range(-30, 31):
            i = (apex + q) % n
            if radius_at(i) < tr.HW[i] + 0.55 + 3.45 + 0.8:                 # Innenradius kleiner als die Zonenbreite: die Streifen würden sich zum Fächer kreuzen
                continue
            base = tr.P[i] + tr.Lft[i] * side * (tr.HW[i] + 0.55)
            t = tr.T[i]
            nrm = tr.Lft[i] * side
            p_in = base + nrm * 3.45                                        # inneres Streifenende (näher am Kurvenmittelpunkt): dort liegen die Streifen am dichtesten
            if last_in is not None and float(np.hypot(*(p_in - last_in))) < 1.15:
                continue                                                    # enge Kurven: Streifen auslassen, damit sie nicht zu einer gelben Fläche verschmelzen
            last_in = p_in
            rungs.append((base + nrm * 0.45, base + nrm * 3.45, t, nrm, i))
        for (a, b, t, nrm, i) in rungs:
            mid = (a + b) / 2
            if not hb_free(float(mid[0]), float(mid[1]), float(nrm[0]), float(nrm[1]), 1.5, 0.35, 0.4, 0.0):
                continue
            wear = rng_.uniform(0.6, 1.0)
            s1 = t * 0.22
            s2 = t * 3.0
            pts = [(a - s1)[:2], (a + s1)[:2], (b + s1 + s2)[:2], (b - s1 + s2)[:2]]
            hb_quad(dec_yellow, "linie_gelb", [(float(p[0]), float(p[1]), y) for p in pts], [(0, 0), (1, 0), (1, 1), (0, 1)], None, [(wear,) * 3] * 4)
            count_bars += 1
        # Randlinien (weiß) entlang beider Kanten der Zone
        for off in (0.45, 3.45):
            prev = None
            for q in range(-30, 31, 2):
                i = (apex + q) % n
                if radius_at(i) < tr.HW[i] + 0.55 + off + 0.5:
                    prev = None
                    continue
                p = tr.P[i] + tr.Lft[i] * side * (tr.HW[i] + 0.55 + off)
                if prev is not None and hb_free(float((p[0] + prev[0]) / 2), float((p[1] + prev[1]) / 2), 1.0, 0.0, 1.2, 1.2, 0.4, 0.0):
                    hb_strip(dec_white, "linie", float(prev[0]), float(prev[1]), float(p[0]), float(p[1]), 0.16, y, (rng_.uniform(0.7, 1.0),) * 3)
                prev = p
        # Kurvennummer (weiß, quer zur Fahrtrichtung lesbar) in der Zone am Scheitel
        i = apex
        pc = tr.P[i] + tr.Lft[i] * side * (tr.HW[i] + 0.55 + 1.95)
        fr = HbFrame(float(pc[0]), float(pc[1]), float(tr.T[i][0]), float(tr.T[i][1]))
        if hb_free(float(pc[0]), float(pc[1]), fr.ux, fr.uz, 0.8, 1.0, 0.4, 0.0):
            hb_number_quads(dec_white, fr, -0.2, -0.6, y + 0.002, ci + 1, 1.2, 0.6, 0.1, t=0.14, key="linie", vertical=False, col=(0.95, 0.95, 0.95))
        # Leitkegel am Scheitelpunkt, innen neben dem Randstein
        for dq in (-4, 0, 4):
            i = (apex + dq) % n
            p = tr.P[i] + tr.Lft[i] * side * (tr.HW[i] + 0.55 + 0.35)
            if hb_free(float(p[0]), float(p[1]), 1.0, 0.0, 0.3, 0.3, 0.4, 0.0):
                hb_cone(cone_parts, float(p[0]), float(p[1]))
    print("DIORAMA Driftzonen:", len(HB["corners"]), "Kurven,", count_bars, "Streifen")


def hb_judge_tower(parts, x, z, ang):
    """Richterturm auf Stahlstützen (Gerüstbau): Treppe mit Geländer, Plattform mit Geländer und Werbebanner, verglaste Kabine mit Dach, Zeitnahmekamera,
    Lautsprecher, Antenne und Zielflagge. Die Kabine blickt in +a."""
    fr = HbFrame(x, z, math.cos(ang), math.sin(ang))
    gy = GROUND_Y
    gal = (0.8, 0.82, 0.85)
    for sa in (-1, 1):
        for sb in (-1, 1):
            px, pz, _ = fr.p(sa * 1.8, sb * 1.3, 0)
            hb_cuboid(parts["stahl"], px, pz, fr.ux, fr.uz, 0.08, 0.08, gy, gy + 3.1, "stahl", col=gal, tile=1.0, bottom_fade=False)
            hb_cuboid(parts["beton"], px, pz, fr.ux, fr.uz, 0.22, 0.22, gy, gy + 0.12, "beton", col=(0.9, 0.9, 0.9), tile=1.0, bottom_fade=False)    # Fußplatten
    for yy in (1.2, 2.2):                                                                                                  # Querriegel
        for sb in (-1.3, 1.3):
            hb_box_l(parts["stahl"], "stahl", fr, -1.8, 1.8, sb - 0.03, sb + 0.03, gy + yy, gy + yy + 0.06, gal, (1.0, 1.0))
        for sa in (-1.8, 1.8):
            hb_box_l(parts["stahl"], "stahl", fr, sa - 0.03, sa + 0.03, -1.3, 1.3, gy + yy, gy + yy + 0.06, gal, (1.0, 1.0))
    for sb in (-1, 1):                                                                                                     # Diagonalverstrebungen (seitlich)
        for (a0, y0_, a1, y1_) in ((-1.8, 0.1, 1.8, 2.2), (1.8, 0.1, -1.8, 2.2)):
            p0, p1 = fr.p(a0, sb * 1.3, gy + y0_), fr.p(a1, sb * 1.3, gy + y1_)
            hb_quad(parts["stahl"], "stahl", [p0, p1, (p1[0], p1[1], p1[2] + 0.05), (p0[0], p0[1], p0[2] + 0.05)], [(0, 0), (1, 0), (1, 1), (0, 1)], fr.d(0.0, sb), [gal] * 4)
    hb_box_l(parts["stahl_dunkel"], "stahl_dunkel", fr, -2.2, 2.2, -1.7, 1.7, gy + 3.0, gy + 3.2, (1, 1, 1), (1.0, 1.0))
    wht = hb_lin((0.9, 0.9, 0.88))
    hb_box_l(parts["lack"], "lack", fr, -1.7, 1.7, -1.3, 1.3, gy + 3.2, gy + 5.4, wht, (0.85, 1.0))
    for sgn in (-1, 1):
        hb_wall(parts["glas"], "glas", fr, -1.5, sgn * 1.305, 1.5, sgn * 1.305, gy + 3.9, gy + 5.15, facing=(0, sgn))
    hb_wall(parts["glas"], "glas", fr, 1.705, -1.1, 1.705, 1.1, gy + 3.9, gy + 5.15, facing=(1, 0))
    hb_wall(parts["glas"], "glas", fr, -1.705, -1.1, -1.705, 1.1, gy + 3.9, gy + 5.15, facing=(-1, 0))
    hb_box_l(parts["lack"], "lack", fr, -2.0, 2.0, -1.6, 1.6, gy + 5.4, gy + 5.55, hb_lin((0.66, 0.68, 0.71)), (1.0, 1.0))                     # helles Blechdach
    # Dach: Zeitnahmekamera (Dreibein mit Kasten), Lautsprecherpaar, Antenne, Wetterhahn, Zielflagge
    cxm, czm, _ = fr.p(1.3, 0.8, 0)
    hb_prism(parts["stahl"], cxm, czm, 0.05, gy + 5.55, gy + 5.95, "stahl", gal, 6, tile=1.0)
    hb_box_l(parts["stahl_dunkel"], "stahl_dunkel", fr, 1.05, 1.65, 0.55, 1.05, gy + 5.95, gy + 6.25, (1, 1, 1), (1.0, 1.0))
    hb_box_l(parts["lack"], "lack", fr, 1.65, 1.8, 0.65, 0.95, gy + 6.03, gy + 6.17, hb_lin((0.1, 0.12, 0.2)), (1.0, 1.0))
    for sb in (-0.9, 0.0):
        hb_box_l(parts["stahl_dunkel"], "stahl_dunkel", fr, -0.4, 0.2, sb - 0.2, sb + 0.2, gy + 5.55, gy + 5.95, (0.9, 0.9, 0.92), (1.0, 1.0))
    mx, mz, _ = fr.p(-1.0, 0.6, 0)
    hb_prism(parts["stahl"], mx, mz, 0.04, gy + 5.55, gy + 7.6, "stahl", gal, 6, tile=1.0)
    fx_, fz_, _ = fr.p(1.2, -0.9, 0)
    hb_flag_pole(parts, fx_, fz_, (0.95, 0.95, 0.95), 2.4, 0.0, y0=gy + 5.55)
    # Treppe an der Rückseite (-a): zwölf Stufen mit Wangen und Handlauf
    for k in range(12):
        a0 = -2.2 - 0.3 * (k + 1)
        hb_box_l(parts["stahl_dunkel"], "stahl_dunkel", fr, a0, a0 + 0.3, -0.5, 0.5, gy + 0.0, gy + 0.25 * (12 - k), (0.9, 0.9, 0.92), (1.0, 1.0))
    for sb in (-0.55, 0.55):                                                                                              # Handläufe schräg mit Pfosten
        p0, p1 = fr.p(-5.8, sb, gy + 1.15), fr.p(-2.2, sb, gy + 3.9)
        hb_quad(parts["stahl"], "stahl", [p0, p1, (p1[0], p1[1], p1[2] + 0.05), (p0[0], p0[1], p0[2] + 0.05)], [(0, 0), (1, 0), (1, 1), (0, 1)], fr.d(0.0, sb), [gal] * 4)
        for a in (-5.7, -4.5, -3.3, -2.3):
            kst = min(11, max(0, int((-2.2 - a) / 0.3)))
            px, pz, _ = fr.p(a, sb, 0)
            y_s = gy + 0.25 * (12 - kst)
            hb_cuboid(parts["stahl"], px, pz, fr.ux, fr.uz, 0.025, 0.025, y_s, y_s + 0.9, "stahl", col=gal, tile=1.0, bottom_fade=False)
    # Geländer um die Plattform (Vorderseite +a und Seiten) und Werbebanner am vorderen Geländer
    for yy in (3.6, 4.1):
        hb_box_l(parts["stahl"], "stahl", fr, 1.75, 1.8, -1.7, 1.7, gy + yy, gy + yy + 0.05, gal, (1.0, 1.0))
        for sb in (-1.7, 1.7):
            hb_box_l(parts["stahl"], "stahl", fr, -2.2, 1.8, sb - 0.025, sb + 0.025, gy + yy, gy + yy + 0.05, gal, (1.0, 1.0))
    g_front = Frame((fr.cx, fr.cz), (fr.vx, fr.vz), (fr.ux, fr.uz))                   # a' = quer, b' = nach vorn (+a)
    parts["e:banner"].append(hb_banner_cell(g_front, -1.6, 1.6, 1.84, gy + 3.2, gy + 3.95, 1, 4))
    return


def hb_banner_cell(g, a0, a1, b, y0, y1, toward, cell):
    """Werbebanner wie banner_quad des Kerns, mit richtig gewählter Spiegelung (Schrift nie spiegelverkehrt)."""
    fvx, fvz = g.v.x * toward, g.v.y * toward       # Flächennormale = Richtung zum Betrachter
    rx, rz = fvz, -fvx                              # rechts des Betrachters (er blickt in -f; Karte: x nach rechts, z nach unten)
    flip = (rx * g.u.x + rz * g.u.y) < 0            # u zeigt dem Betrachter nach links: Schrift spiegeln, damit sie lesbar bleibt (wie crowd_zone des Kerns)
    return banner_quad(g, a0, a1, b, y0, y1, toward, cell, flip)


def hb_crowd_line(parts, p_a, p_b, side, seed=0):
    """Absperrgitter-Reihe mit Werbebannern beidseitig und Zuschauern dahinter (Menge als Auflage), Fahnen hinter der Menge. side = +1: Menge links
    der Richtung a -> b. Rückgabe: Zahl der Felder."""
    ax, az = p_a
    bx, bz = p_b
    ln = math.hypot(bx - ax, bz - az)
    ux, uz = (bx - ax) / ln, (bz - az) / ln
    vx, vz = -uz * side, ux * side
    rng_ = random.Random(seed)
    gy = GROUND_Y
    panel = 2.4
    n = int(ln // panel)
    count = 0
    flag_cols = [(0.70, 0.03, 0.02), (0.86, 0.86, 0.84), (0.90, 0.50, 0.02), (0.02, 0.08, 0.50)]
    for k in range(n):
        s = (k + 0.5) * panel
        cx, cz = ax + ux * s, az + uz * s
        # Fläche von Zaun bis Menge: Mitte 0,9 m hinter dem Zaun
        if not hb_free(cx + vx * 0.9, cz + vz * 0.9, ux, uz, panel / 2, 1.0, 3.0, 0.0):
            continue
        hb_occupy(cx + vx * 0.9, cz + vz * 0.9, ux, uz, panel / 2, 1.0)
        HB["solids"].append((cx, cz, ux, uz, panel / 2, 0.12, 1.1, "gitter"))
        g = Frame((cx, cz), (ux, uz), (vx, vz))
        # Gitter: zwei Füße, zwei Holme, sechs Stäbe (flache Flächen), Pfosten
        for a in (-panel / 2 + 0.12, panel / 2 - 0.12):
            parts["stahl"].extend(box(g, "stahl", a - 0.04, a + 0.04, -0.28, 0.28, gy, gy + 0.05))
        parts["stahl"].extend(box(g, "stahl", -panel / 2, panel / 2, -0.015, 0.015, gy + 0.98, gy + 1.04))
        parts["stahl"].extend(box(g, "stahl", -panel / 2, panel / 2, -0.015, 0.015, gy + 0.25, gy + 0.3))
        for j in range(7):
            a = -panel / 2 + 0.12 + j * (panel - 0.24) / 6
            p0, p1 = g.pt(a, 0.0), g.pt(a, 0.0)
            parts["stahl"].append(("stahl", [(p0.x, p0.y, gy + 0.05), (p0.x + ux * 0.025, p0.y + uz * 0.025, gy + 0.05), (p0.x + ux * 0.025, p0.y + uz * 0.025, gy + 0.98), (p0.x, p0.y, gy + 0.98)],
                                   [(0, 0), (1, 0), (1, 1), (0, 1)], (vx, vz)))
        cell = (k * 3 + (0 if side > 0 else 5)) % 8
        for toward in (-1, 1):
            parts["e:banner"].append(hb_banner_cell(g, -1.1, 1.1, 0.03 * toward, gy + 0.36, gy + 0.91, toward, cell))
        parts["e:menge"].append(crowd_quad(g, -panel / 2, panel / 2, 0.30, 1.55, gy + 0.004, s + (0.0 if side > 0 else 7.0)))
        if k % 5 == 2:
            fx, fz = cx + vx * 1.85, cz + vz * 1.85
            if hb_free(fx, fz, 1.0, 0.0, 0.4, 0.4, 3.0, 0.0):
                hb_occupy(fx, fz, 1.0, 0.0, 0.4, 0.4)
                hb_flag_pole(parts, fx, fz, flag_cols[(k // 5 + int(seed)) % 4], 4.4, math.atan2(uz, ux))
        count += 1
    return count


# ---------------------------------------------------------------- Teamtransporter (Koffer-Lkw) und Rettungswagen
def hb_box_truck(lists, cx, cz, ux, uz, cab_col=(0.9, 0.9, 0.88), body_col=(0.8, 0.1, 0.08), seed=1):
    """Koffer-Lkw (9,6 m) eines Teams: Frontlenker-Fahrerhaus mit Dachspoiler, Spiegeln, Trittstufe und Kühlergrill, Kofferaufbau mit Teamfarbe,
    Zierstreifen, Dach-Klimagerät, Heckrolltor mit Hebebühne und Rückleuchten, Zwillingsreifen hinten, Schmutzfänger. Vorne = +u."""
    fr = HbFrame(cx, cz, ux, uz)
    gy = GROUND_Y
    lack, dunkel, glas, stahl = lists["lack"], lists["stahl_dunkel"], lists["glas"], lists["stahl"]
    cc, bc = hb_lin(cab_col), hb_lin(body_col)
    wht = hb_lin((0.92, 0.92, 0.9))
    hb_box_l(dunkel, "stahl_dunkel", fr, -4.6, 4.7, -0.55, 0.55, gy + 0.5, gy + 0.95, (1, 1, 1))
    hb_box_l(lack, "lack", fr, 2.6, 4.8, -1.25, 1.25, gy + 0.95, gy + 3.0, cc, (0.7, 1.0))
    hb_box_l(lack, "lack", fr, 3.2, 4.0, -1.1, 1.1, gy + 3.0, gy + 3.16, tuple(v * 0.9 for v in cc), (1.0, 1.0))             # Sonnenblende / Dachspoiler
    hb_wall(glas, "glas", fr, 4.805, -1.12, 4.805, 1.12, gy + 1.85, gy + 2.75, facing=(1, 0))
    for sgn in (-1, 1):
        hb_wall(glas, "glas", fr, 3.0, sgn * 1.255, 4.5, sgn * 1.255, gy + 1.9, gy + 2.65, facing=(0, sgn))
        hb_box_l(dunkel, "stahl_dunkel", fr, 4.2, 4.35, sgn * 1.35 - 0.05, sgn * 1.35 + 0.05, gy + 1.8, gy + 2.5, (1, 1, 1), (1.0, 1.0))      # Spiegel
        hb_box_l(dunkel, "stahl_dunkel", fr, 3.3, 3.9, sgn * 1.26 - 0.1, sgn * 1.26 + 0.1, gy + 0.62, gy + 0.68, (0.9, 0.9, 0.92), (1.0, 1.0))  # Trittstufe
        hb_wall(lack, "lack", fr, 4.806, sgn * 1.0, 4.806, sgn * 1.2, gy + 1.2, gy + 1.4, (1.3, 1.25, 1.0), (1.3, 1.25, 1.0), facing=(1, 0))    # Scheinwerfer
    hb_box_l(dunkel, "stahl_dunkel", fr, 4.78, 5.0, -1.2, 1.2, gy + 0.5, gy + 1.0, (1, 1, 1))
    hb_wall(dunkel, "stahl_dunkel", fr, 4.806, -0.8, 4.806, 0.8, gy + 1.05, gy + 1.7, (0.6, 0.6, 0.62), (0.9, 0.9, 0.92), facing=(1, 0))        # Kühlergrill
    # Kofferaufbau
    hb_box_l(lack, "lack", fr, -4.6, 2.4, -1.28, 1.28, gy + 1.0, gy + 3.5, bc, (0.7, 1.0))
    for sgn in (-1, 1):                                                  # weißer Zierstreifen und dunklerer Akzentstreifen auf beiden Seiten
        hb_wall(lack, "lack", fr, -4.55, sgn * 1.285, 2.35, sgn * 1.285, gy + 1.9, gy + 2.3, wht, wht, facing=(0, sgn))
        hb_wall(lack, "lack", fr, -4.55, sgn * 1.285, 2.35, sgn * 1.285, gy + 1.55, gy + 1.8, tuple(v * 0.45 for v in bc), tuple(v * 0.45 for v in bc), facing=(0, sgn))
    hb_wall(lack, "lack", fr, -4.605, -1.1, -4.605, 1.1, gy + 1.2, gy + 3.3, tuple(v * 0.6 for v in bc), tuple(v * 0.6 for v in bc), facing=(-1, 0))   # Rolltor
    hb_box_l(dunkel, "stahl_dunkel", fr, -5.3, -4.6, -1.15, 1.15, gy + 0.95, gy + 1.0, (0.9, 0.9, 0.92), (1.0, 1.0))                          # Hebebühne (heruntergeklappt)
    hb_box_l(dunkel, "stahl_dunkel", fr, -4.4, -3.0, -0.5, 0.5, gy + 3.5, gy + 3.82, (0.8, 0.8, 0.82), (1.0, 1.0))                            # Dach-Klimagerät
    hb_box_l(lack, "lack", fr, -4.62, -4.56, 0.8, 1.15, gy + 0.9, gy + 1.15, hb_lin((0.75, 0.04, 0.03)), (1.0, 1.0))
    hb_box_l(lack, "lack", fr, -4.62, -4.56, -1.15, -0.8, gy + 0.9, gy + 1.15, hb_lin((0.75, 0.04, 0.03)), (1.0, 1.0))                        # Rückleuchten (nur Farbe)
    wf = lists["gummi"]
    for sgn in (-1, 1):
        hb_wheel(wf, fr, 3.7, sgn * 1.0, gy + 0.5, 0.5, 0.3)
        for a_ax in (-2.6, -3.9):
            hb_wheel(wf, fr, a_ax, sgn * 1.13, gy + 0.5, 0.5, 0.56)                    # Zwillingsreifen als ein Rad
        hb_box_l(dunkel, "stahl_dunkel", fr, -4.45, -4.35, sgn * 1.0 - 0.3, sgn * 1.0 + 0.3, gy + 0.3, gy + 0.85, (0.8, 0.8, 0.82), (1.0, 1.0))  # Schmutzfänger
    return fr


def hb_ambulance(lists, cx, cz, ux, uz):
    """Rettungswagen (Kastenwagen): weiß mit roten Streifen, rotem Kreuz auf dem Dach, Blaulichtbalken (nur Farbe), Heckfenstern, Spiegeln."""
    fr = HbFrame(cx, cz, ux, uz)
    gy = GROUND_Y
    wht = hb_lin((0.93, 0.93, 0.91))
    red = hb_lin((0.8, 0.06, 0.04))
    lack, dunkel, glas = lists["lack"], lists["stahl_dunkel"], lists["glas"]
    hb_box_l(dunkel, "stahl_dunkel", fr, -2.7, 2.7, -0.8, 0.8, gy + 0.3, gy + 0.6, (1, 1, 1))
    hb_box_l(lack, "lack", fr, -2.7, 2.7, -1.0, 1.0, gy + 0.55, gy + 2.45, wht, (0.75, 1.0))
    hb_box_l(lack, "lack", fr, 2.0, 2.75, -0.98, 0.98, gy + 0.55, gy + 1.3, wht, (0.8, 1.0))
    for sgn in (-1, 1):
        hb_wall(lack, "lack", fr, -2.65, sgn * 1.005, 2.65, sgn * 1.005, gy + 1.0, gy + 1.35, red, red, facing=(0, sgn))
        hb_wall(glas, "glas", fr, 1.4, sgn * 1.005, 2.3, sgn * 1.005, gy + 1.6, gy + 2.2, facing=(0, sgn))
        hb_box_l(dunkel, "stahl_dunkel", fr, 1.9, 2.05, sgn * 1.08 - 0.04, sgn * 1.08 + 0.04, gy + 1.4, gy + 1.9, (1, 1, 1), (1.0, 1.0))        # Spiegel
    hb_wall(glas, "glas", fr, 2.705, -0.85, 2.705, 0.85, gy + 1.55, gy + 2.25, facing=(1, 0))
    hb_wall(glas, "glas", fr, -2.705, -0.8, -2.705, -0.1, gy + 1.5, gy + 2.2, facing=(-1, 0))
    hb_wall(glas, "glas", fr, -2.705, 0.1, -2.705, 0.8, gy + 1.5, gy + 2.2, facing=(-1, 0))                                                     # Hecktüren mit Fenstern
    hb_box_l(dunkel, "stahl_dunkel", fr, 1.55, 1.95, -0.62, 0.62, gy + 2.45, gy + 2.55, (0.9, 0.9, 0.92), (1.0, 1.0))                            # Lichtbalken: Träger
    for b0_ in (-0.58, 0.1):
        hb_box_l(lack, "lack", fr, 1.6, 1.9, b0_, b0_ + 0.48, gy + 2.55, gy + 2.66, hb_lin((0.05, 0.2, 0.9)), (1.0, 1.0))                       # zwei blaue Lichthauben (nur Farbe)
    for (a0, a1, b0, b1) in ((-1.2, 0.6, -0.1, 0.1), (-0.3, -0.1, -0.6, 0.6)):                                                                  # rotes Kreuz auf dem Dach
        hb_quad(lack, "lack", [fr.p(a0, b0, gy + 2.452), fr.p(a1, b0, gy + 2.452), fr.p(a1, b1, gy + 2.452), fr.p(a0, b1, gy + 2.452)], [(0, 0), (1, 0), (1, 1), (0, 1)], None, [red] * 4)
    for a_ax in (1.7, -1.7):
        for sgn in (-1, 1):
            hb_wheel(lists["gummi"], fr, a_ax, sgn * 0.92, gy + 0.36, 0.36, 0.24)


def hb_build_service_vehicles(rng_):
    """Rettungs- und Teamfahrzeuge der Arena (aus HB["service"]) sowie Koffer-Lkw (HB["boxtrucks"])."""
    lists = hb_new_parts("lack", "stahl_dunkel", "glas", "stahl", "gummi")
    for t in HB.get("boxtrucks", []):
        hb_box_truck(lists, t["c"][0], t["c"][1], t["u"][0], t["u"][1], t["cab"], t["body"], t["seed"])
    for t in HB.get("service", []):
        hb_ambulance(lists, t["c"][0], t["c"][1], t["u"][0], t["u"][1])
    for k, v in lists.items():
        if v:
            mesh_objects("Dienst_" + k, v)


# ---------------------------------------------------------------- Kleinkram, Zäune, Büro-Parkplatz, Radspuren
def hb_plan_clutter():
    """Fässer, Reifenstapel, Leitkegel, Aggregate und Paletten an freien Stellen der Gassen und Randstreifen (nur Planung)."""
    HB["clutter"] = []
    rng_ = random.Random(91)
    zones = [(-58, -22, 56, 22, 14), (22, -28.5, 66, -9, 3), (-101, -39, -73, 36, 5), (69, -39, 97, 38, 5), (-60, 38, 70, 66, 6)] if not IS_ARENA else \
        [(-92, -46, 70, 43, 18)]
    for (xa, za, xb, zb, n) in zones:
        got, tries = 0, 0
        while got < n and tries < 300:
            tries += 1
            x, z = rng_.uniform(xa, xb), rng_.uniform(za, zb)
            kind = rng_.choice(["drums", "drums", "tyres", "cones", "pallets"])
            if kind == "drums":
                ok = hb_free(x, z, 1.0, 0.0, 0.9, 0.9, 2.0, 0.1)
                if ok:
                    hb_occupy(x, z, 1.0, 0.0, 0.9, 0.9)
                    for j in range(3):
                        HB["circles"].append((x + (j % 2) * 0.62 - 0.3, z + (j // 2) * 0.58, 0.29, 0.9, "mauer"))
            elif kind == "tyres":
                ok = hb_free(x, z, 1.0, 0.0, 0.55, 0.55, 2.0, 0.1)
                if ok:
                    hb_occupy(x, z, 1.0, 0.0, 0.55, 0.55)
            elif kind == "cones":
                ok = hb_free(x, z, 1.0, 0.0, 1.2, 0.5, 2.0, 0.1)
                if ok:
                    hb_occupy(x, z, 1.0, 0.0, 1.2, 0.5)
            else:
                ok = hb_solid(x, z, 1.0, 0.0, 0.6, 0.5, 1.2, "mauer", margin=2.0, pad=0.1)
            if ok:
                HB["clutter"].append((kind, x, z, rng_.uniform(0, 6.28)))
                got += 1


def hb_build_clutter(rng_):
    parts = hb_new_parts("lack", "gummi", "stahl", "stahl_dunkel", "holz", "beton")
    cols = [(0.1, 0.25, 0.6), (0.7, 0.12, 0.08), (0.12, 0.45, 0.25), (0.8, 0.5, 0.08), (0.3, 0.32, 0.34)]
    for kind, x, z, ang in HB.get("clutter", []):
        if kind == "drums":
            for j in range(3):
                hb_drum(parts, x + (j % 2) * 0.62 - 0.3, z + (j // 2) * 0.58, cols[(int(x * 3 + z) + j) % len(cols)])
        elif kind == "tyres":
            hb_tyre_stack(parts, x, z, 5, collide=False)
            if HB["track"].circle_slack(x, z, 0.4) >= 1.0:
                HB["circles"].append((x, z, 0.4, 1.0, "reifen"))
        elif kind == "cones":
            for j in range(3):
                hb_cone(parts, x - 0.8 + j * 0.8, z, 1.0, collide=False)
        else:
            fr = HbFrame(x, z, math.cos(ang), math.sin(ang))
            gy = GROUND_Y
            hb_box_l(parts["holz"], "holz", fr, -0.6, 0.6, -0.5, 0.5, gy, gy + 0.14, (1, 1, 1), (0.8, 1.0))
            hb_box_l(parts["lack"], "lack", fr, -0.55, 0.55, -0.45, 0.45, gy + 0.14, gy + 1.15, hb_lin((0.82, 0.78, 0.66)), (0.8, 1.0))
    for k, v in parts.items():
        if v:
            mesh_objects("Kram_" + k, v)


def hb_build_fences(rng_):
    """Zaun mit Gewebeplane am Rand des Geländes (Hafen) und Zäune um das Hafenbecken-Umfeld."""
    parts = hb_new_parts("stahl", "planen")
    cols = [(0.10, 0.28, 0.20), (0.12, 0.2, 0.34)]
    n = 0
    lines = []
    if not IS_ARENA:
        lines = [((x1 - 1.0, HB_QUAY_Z + 2.0), (x1 - 1.0, z1 - 1.0)), ((x0 + 1.0, HB_QUAY_Z + 2.0), (x0 + 1.0, z1 - 1.0)), ((x0 + 1.0, z1 - 1.0), (x1 - 1.0, z1 - 1.0))]
    for (pa, pb) in lines:
        ln = math.hypot(pb[0] - pa[0], pb[1] - pa[1])
        m = int(ln // 10.0)
        for k in range(m):
            a = (pa[0] + (pb[0] - pa[0]) * k / m, pa[1] + (pb[1] - pa[1]) * k / m)
            b = (pa[0] + (pb[0] - pa[0]) * (k + 1) / m, pa[1] + (pb[1] - pa[1]) * (k + 1) / m)
            if hb_tarp_fence(parts, a, b, 2.0, cols[(k // 3) % 2], margin=2.0):
                n += 1
    for k, v in parts.items():
        if v:
            mesh_objects("Zaun_" + k, v)
    print("DIORAMA Zaunfelder:", n)


def hb_plan_wheel_tracks():
    """Radspuren in den Gassen (zwei Streifen im Spurabstand, leicht schwankend) für die Lichttextur."""
    rng_ = random.Random(5)
    tracks = []
    for ln in HB["lanes"]:
        axis, a0, a1, b0, b1, across = ln
        width = (b1 - b0) if across else (a1 - a0)
        if width < 4.4:
            continue
        mid = (b0 + b1) / 2 if across else (a0 + a1) / 2
        lo, hi = (a0, a1) if across else (b0, b1)
        ts = np.arange(lo, hi, 1.0)
        for off in (-0.95, 0.95):
            pts = []
            for t in ts:
                a, b = (t, mid + off + 0.12 * math.sin(t * 0.37 + off)) if across else (mid + off + 0.12 * math.sin(t * 0.37 + off), t)
                pts.append((a, b) if axis == "x" else (b, a))
            pts = np.array(pts)
            strength = np.array([0.35 + 0.65 * float(hb_vnoise(p[0], p[1], 3.5, 12.0, 1.0)) for p in pts]) * 0.20
            tracks.append((pts, np.full(len(pts), 0.6), strength))
    HB["wheel_tracks"] = tracks


def hb_plan_cars():
    """Parkende Pkw vor dem Büro (Pkw-Reihe aus kit_car)."""
    HB["cars"] = []
    if IS_ARENA:
        return
    rng_ = random.Random(23)
    for row, zc in enumerate((47.6, 50.2)):
        x = -7.0
        while x < 15.0:
            if rng_.random() < 0.7 and hb_solid(x, zc, 0.0, 1.0, 2.3, 0.95, 1.5, "auto", margin=2.0, pad=0.12):
                HB["cars"].append((x, zc, 0.0, 1.0 if row == 0 else -1.0, rng_.randrange(1 << 20)))
            x += 2.9


def hb_build_cars(rng_):
    parts = []
    for (x, z, ux, uz, seed) in HB["cars"]:
        r2 = random.Random(seed)
        p, _dims = kit_car.random_car(r2, x, z, ux, uz, base_y=GROUND_Y)
        parts += p
    if parts:
        mesh_objects("Pkw", parts)


# ---------------------------------------------------------------- Absperrschranken (Baustellenschranken wie im Kern) und Verkehrsschilder
def hb_plan_barriers():
    """Reihen aus Baustellen-Absperrschranken (rot-weiße Bretter, Gummifüße, Warnleuchten) vor dem Hafenbecken und an Sperrungen."""
    HB["barrier_rows"] = []
    rows = []
    if HB["basin"]:
        bx0, bz0, bx1, bz1 = HB["basin"]
        cxb = (bx0 + bx1) / 2.0
        rows += [(cxb + 5.0, bz0 - 3.6, 1.0, 0.0, 9.2), (cxb, bz1 + 2.7, 1.0, 0.0, 9.2)]
    for (cx, cz, ux, uz, ln) in rows:
        n = max(2, int(math.ceil(ln / 2.3)))
        if hb_solid(cx, cz, ux, uz, ln / 2, 0.3, 1.1, "absperrung", margin=2.0, pad=0.3):
            HB["barrier_rows"].append((cx, cz, ux, uz, ln, n))
            HB["solids"].pop()                                         # barrier_segment trägt sein Hindernis selbst ein


def hb_build_barriers():
    global Y_J
    parts = []
    old = Y_J
    Y_J = GROUND_Y + 0.004                                            # Schranken stehen auf dem Boden, nicht auf der Fahrbahn
    try:
        for (cx, cz, ux, uz, ln, n) in HB.get("barrier_rows", []):
            g = Frame((cx, cz), (ux, uz), (-uz, ux))
            seg = (ln - (n - 1) * 0.3) / n
            for k in range(n):
                parts += barrier_segment(g, -ln / 2 + seg / 2 + k * (seg + 0.3), seg, lamp=(k % 2 == 0))
    finally:
        Y_J = old
    if parts:
        mesh_objects("Schranke", parts)
    cone = hb_new_parts("gummi", "lack")
    for (cx, cz, ux, uz, ln, n) in HB.get("barrier_rows", []):
        for a in (-ln * 0.38, ln * 0.38):
            hb_cone(cone, cx + ux * a - uz * 1.1, cz + uz * a + ux * 1.1, 1.0, collide=False)
            hb_cone(cone, cx + ux * a + uz * 1.1, cz + uz * a - ux * 1.1, 1.0, collide=False)
    for k, v in cone.items():
        if v:
            mesh_objects("Schrankenkegel_" + k, v)


def hb_sign(parts, x, z, ang, kind, h=2.3):
    """Verkehrszeichen auf Pfosten: kind 'tempo20' (rund, rot umrandet), 'vorfahrt' (Dreieck, Spitze unten), 'einbahn' (blaues Rechteck mit Pfeil).
    Schild zeigt in Richtung ang (Blickrichtung des Fahrers, der es liest)."""
    fr = HbFrame(x, z, math.cos(ang), math.sin(ang))          # u zeigt zum Betrachter hin
    gy = GROUND_Y
    hb_cuboid(parts["stahl"], x, z, fr.ux, fr.uz, 0.04, 0.04, gy, gy + h, "stahl", col=(0.8, 0.8, 0.82), tile=1.0, bottom_fade=False)
    off = 0.06
    yc = gy + h - 0.35
    red, wht, blk, blue = hb_lin((0.8, 0.05, 0.04)), hb_lin((0.93, 0.93, 0.9)), hb_lin((0.04, 0.04, 0.05)), hb_lin((0.0, 0.2, 0.62))

    def face(pts_ab, col, o):
        hb_quad(parts["lack"], "lack", [fr.p(o, a, y) for a, y in pts_ab], [(0, 0), (1, 0), (1, 1), (0, 1)][:len(pts_ab)], fr.d(1.0, 0.0), [col] * len(pts_ab))
    if kind == "tempo20":
        n = 14
        outer = [(0.36 * math.cos(2 * math.pi * k / n), yc + 0.36 * math.sin(2 * math.pi * k / n)) for k in range(n)]
        inner = [(0.27 * math.cos(2 * math.pi * k / n), yc + 0.27 * math.sin(2 * math.pi * k / n)) for k in range(n)]
        face(outer, red, off)
        face(inner, wht, off + 0.004)
        # Ziffern liegen in der Wandebene u = off: lokales System dafür drehen (a = quer)
        fr2 = HbFrame(fr.cx, fr.cz, fr.vx, fr.vz)
        for k, ch in enumerate("20"):
            hb_digit_quads(parts["lack"], fr2, -0.20 + k * 0.22, -off - 0.008, yc - 0.16, int(ch), 0.32, 0.17, 0.045, key="lack", col=blk, facing=(0, -1))
    elif kind == "vorfahrt":
        tri = [(-0.45, yc + 0.35), (0.45, yc + 0.35), (0.0, yc - 0.40)]
        face(tri, red, off)
        tri2 = [(-0.31, yc + 0.27), (0.31, yc + 0.27), (0.0, yc - 0.23)]
        face(tri2, wht, off + 0.004)
    else:
        face([(-0.35, yc - 0.35), (0.35, yc - 0.35), (0.35, yc + 0.35), (-0.35, yc + 0.35)], blue, off)
        face([(-0.07, yc - 0.22), (0.07, yc - 0.22), (0.07, yc + 0.02), (0.20, yc + 0.02), (0.0, yc + 0.26), (-0.20, yc + 0.02), (-0.07, yc + 0.02)], wht, off + 0.004)


# ---------------------------------------------------------------- Reach Stacker (Containerstapler) mit 20-Fuß-Container
def hb_reach_stacker(lists, cx, cz, ux, uz, body_col=(0.95, 0.72, 0.06), cont_col=(0.1, 0.28, 0.52), seed=1):
    """Containerstapler: Chassis mit vier großen Rädern, Fahrerkabine links vorn, Teleskopausleger mit Spreader über einem 20-Fuß-Container;
    Fahrtrichtung +u, Länge etwa 13 m mit Last."""
    fr = HbFrame(cx, cz, ux, uz)
    gy = GROUND_Y
    col = hb_lin(body_col)
    dark = hb_lin((0.08, 0.08, 0.09))
    lack, dunkel, glas, stahl = lists["lack"], lists["stahl_dunkel"], lists["glas"], lists["stahl"]
    # Chassis und Motorhaube
    hb_box_l(lack, "lack", fr, -3.6, 2.4, -1.4, 1.4, gy + 0.65, gy + 1.7, col, (0.7, 1.0))
    hb_box_l(lack, "lack", fr, -3.6, -1.2, -1.3, 1.3, gy + 1.7, gy + 2.3, tuple(v * 0.9 for v in col), (0.9, 1.0))
    hb_box_l(dunkel, "stahl_dunkel", fr, -3.7, -3.55, -1.0, 1.0, gy + 1.0, gy + 1.9, (1, 1, 1))                         # Kühlergitter hinten (Heckmotor)
    # Kabine links (in Fahrtrichtung), Fenster ringsum
    hb_box_l(lack, "lack", fr, 0.4, 2.3, -1.35, -0.1, gy + 1.7, gy + 3.7, col, (0.8, 1.0))
    hb_wall(glas, "glas", fr, 2.305, -1.25, 2.305, -0.2, gy + 2.2, gy + 3.55, facing=(1, 0))
    hb_wall(glas, "glas", fr, 0.5, -1.355, 2.2, -1.355, gy + 2.2, gy + 3.55, facing=(0, -1))
    hb_wall(glas, "glas", fr, 0.5, -0.095, 2.2, -0.095, gy + 2.2, gy + 3.55, facing=(0, 1))
    hb_box_l(lack, "lack", fr, 0.3, 2.4, -1.4, -0.05, gy + 3.7, gy + 3.82, dark, (1.0, 1.0))
    # Ausleger: Grundrohr, ausgefahrenes Stück, Spreader
    hb_box_l(lack, "lack", fr, -3.0, 1.4, 0.0, 0.9, gy + 2.3, gy + 2.95, tuple(v * 0.85 for v in col), (0.9, 1.0))
    hb_box_l(dunkel, "stahl_dunkel", fr, 1.4, 5.6, 0.1, 0.8, gy + 2.6, gy + 3.2, (1, 1, 1))
    hb_box_l(stahl, "stahl", fr, 3.3, 9.6, 0.15, 0.75, gy + 3.2, gy + 3.45, (0.8, 0.8, 0.82), (1.0, 1.0))
    # Räder (groß)
    for a_ax in (-2.3, 1.2):
        for sgn in (-1, 1):
            hb_wheel(lists["gummi"], fr, a_ax, sgn * 1.45, gy + 0.78, 0.78, 0.55, sides=12)
    hb_box_l(dunkel, "stahl_dunkel", fr, -2.7, -1.9, -1.45, 1.45, gy + 0.7, gy + 0.9, (1, 1, 1))
    hb_box_l(dunkel, "stahl_dunkel", fr, 0.8, 1.6, -1.45, 1.45, gy + 0.7, gy + 0.9, (1, 1, 1))
    for a_ax in (-2.3, 1.2):                                                                                           # Kotflügel über den Rädern
        for sgn in (-1, 1):
            hb_box_l(dunkel, "stahl_dunkel", fr, a_ax - 0.95, a_ax + 0.95, sgn * 1.45 - 0.36, sgn * 1.45 + 0.36, gy + 1.58, gy + 1.66, (0.75, 0.75, 0.78), (1.0, 1.0))
    hb_box_l(dunkel, "stahl_dunkel", fr, -4.25, -3.6, -1.3, 1.3, gy + 0.8, gy + 2.1, (0.55, 0.55, 0.58), (0.9, 1.0))     # Gegengewicht hinten
    for k_, bb in enumerate((-1.1, -0.55, 0.0, 0.55, 1.1)):                                                            # gelb-schwarze Warnstreifen am Heck
        hb_box_l(lack, "lack", fr, -4.27, -4.25, bb - 0.25, bb + 0.25, gy + 1.0, gy + 1.5, hb_lin((0.95, 0.74, 0.05)) if k_ % 2 == 0 else dark, (1.0, 1.0))
    ex_, ez_, _ = fr.p(-2.0, 1.05, 0)
    hb_prism(stahl, ex_, ez_, 0.07, gy + 2.3, gy + 3.4, "stahl", (0.35, 0.35, 0.38), 6, tile=1.0)                      # Auspuff
    for sgn in (-1, 1):                                                                                                # Scheinwerfer vorn (nur Farbe)
        hb_box_l(lack, "lack", fr, 2.4, 2.43, sgn * 0.95 - 0.14, sgn * 0.95 + 0.14, gy + 1.15, gy + 1.35, hb_lin((0.96, 0.9, 0.7)), (1.0, 1.0))
    # Last: 20-Fuß-Container unter dem Spreader
    hb_container_one(lists["container"], *fr.p(6.5, 0.45, 0)[:2], fr.ux, fr.uz, HB_L20 / 2, HB_CW / 2, gy + 0.65, cont_col, door_front=True, seed=seed)
    hb_box_l(stahl, "stahl", fr, 3.5, 9.5, 0.4, 0.5, gy + 3.25, gy + 3.3, (0.7, 0.7, 0.72), (1.0, 1.0))
    # Zubehör: Warnleuchte (nur Farbe), Spiegel
    hb_box_l(lack, "lack", fr, 1.1, 1.4, -1.0, -0.8, gy + 3.82, gy + 3.98, hb_lin((0.9, 0.5, 0.05)), (1.0, 1.0))


# ---------------------------------------------------------------- Verkehrszeichen an Gassen
def hb_plan_signs():
    HB["signs"] = []
    rng_ = random.Random(61)
    kinds = ["tempo20", "vorfahrt", "einbahn", "tempo20", "vorfahrt"]
    lanes = [ln for ln in HB["lanes"] if ((ln[4] - ln[3]) if ln[5] else (ln[2] - ln[1])) >= 4.6]
    rng_.shuffle(lanes)
    for ln in lanes:
        if len(HB["signs"]) >= 9:
            break
        axis, a0, a1, b0, b1, across = ln
        mid = (b0 + b1) / 2 if across else (a0 + a1) / 2
        half = ((b1 - b0) if across else (a1 - a0)) / 2
        lo, hi = (a0, a1) if across else (b0, b1)
        t = lo + 1.6
        a_, b_ = (t, mid + half - 0.35) if across else (mid + half - 0.35, t)
        cx, cz = (a_, b_) if axis == "x" else (b_, a_)
        if hb_free(cx, cz, 1.0, 0.0, 0.2, 0.2, 3.5, 0.2):                      # Schildmast mindestens 3,5 m neben dem Fahrschlauch (Feldtest)
            hb_occupy(cx, cz, 1.0, 0.0, 0.3, 0.3)
            along = (-1.0, 0.0) if ((axis == "x") == across) else (0.0, -1.0)       # Schild zeigt zum Gassenanfang hin (zum Betrachter, der einfährt)
            ang = math.atan2(along[1], along[0])
            HB["signs"].append((cx, cz, ang, kinds[len(HB["signs"]) % len(kinds)]))
            HB["circles"].append((cx, cz, 0.1, 2.3, "mast"))


def hb_build_signs():
    parts = hb_new_parts("stahl", "lack")
    for (x, z, ang, kind) in HB.get("signs", []):
        hb_sign(parts, x, z, ang, kind)
    for k, v in parts.items():
        if v:
            mesh_objects("Schild_" + k, v)


# ---------------------------------------------------------------- Gleisanschluss (Hafenbahn) im Osten: Schotterbett, Schwellen, Schienen, Rangierlok, Containertragwagen
HB_SIDING_X = 80.5


def hb_plan_siding():
    """Gleis in Nord-Süd-Richtung (parallel zur Kaikante nicht, sondern ins Hafengelände): Belegung, Fahrzeuge als feste Körper."""
    HB["siding"] = None
    if IS_ARENA:
        return
    xs_, z_a, z_b = HB_SIDING_X, -37.5, 37.5
    vehicles = []
    z = -35.1                                                  # Rangierlok an der Kaispitze
    vehicles.append(("loco", z + 4.6, 4.6, 1.5, 4.2))
    z += 9.2 + 0.8
    for k in range(3):
        vehicles.append(("wagon", z + 9.85, 9.85, 1.4, 4.4))
        z += 19.7 + 0.8
    HB["siding"] = {"x": xs_, "z_a": z_a, "z_b": z_b, "vehicles": []}
    rng_ = random.Random(37)
    for (kind, zc, hl, hw_, hgt) in vehicles:
        if hb_solid(xs_, zc, 0.0, 1.0, hl, hw_, hgt, "auto", margin=2.0, pad=0.1):
            HB["siding"]["vehicles"].append((kind, zc, hl, [hb_pick_color(rng_) for _ in range(2)], rng_.randrange(1 << 20)))
    hb_occupy(xs_, (z_a + z_b) / 2, 1.0, 0.0, 3.4, (z_b - z_a) / 2 + 0.5)


def hb_buffer(lists, fr, a, b, gy, sgn):
    """Puffer (Pufferteller auf Stoßdämpferzylinder) am Wagenende; sgn = +1 am vorderen (+a), -1 am hinteren Ende."""
    stahl = lists["stahl"]
    hb_box_l(stahl, "stahl", fr, min(a, a + sgn * 0.34), max(a, a + sgn * 0.34), b - 0.09, b + 0.09, gy + 0.93, gy + 1.07, (0.7, 0.7, 0.72), (1.0, 1.0))
    hb_box_l(stahl, "stahl", fr, min(a + sgn * 0.34, a + sgn * 0.42), max(a + sgn * 0.34, a + sgn * 0.42), b - 0.19, b + 0.19, gy + 0.86, gy + 1.14, (0.85, 0.85, 0.87), (1.0, 1.0))


def hb_wagon(lists, cx, cz, ux, uz, cols, seed):
    """Containertragwagen (4 Achsen, 19,7 m): Rahmen, Drehgestelle mit Achslagern, Puffer, Bremserbühnen, Containerzapfen, darauf ein
    40-Fuß- oder zwei 20-Fuß-Container (oder leer: dann sind die Zapfen zu sehen)."""
    fr = HbFrame(cx, cz, ux, uz)
    gy = GROUND_Y + 0.5                                        # Schienenoberkante: Schotter 0,18 + Schwelle 0,16 + Schienenkopf 0,16
    dunkel, stahl, lack = lists["stahl_dunkel"], lists["stahl"], lists["lack"]
    rost = hb_lin((0.34, 0.2, 0.14))
    frame_c = (1.15, 0.95, 0.85) if seed % 2 else (0.9, 0.9, 0.95)                      # Rahmenton: rostig oder grau
    for sgn in (-1, 1):                                                                 # Längsträger beidseits (offener Rahmen: dazwischen sieht man den Schotter)
        hb_box_l(dunkel, "stahl_dunkel", fr, -9.85, 9.85, sgn * 1.1, sgn * 1.25, gy + 0.78, gy + 1.1, frame_c)
    hb_box_l(dunkel, "stahl_dunkel", fr, -9.85, 9.85, -0.3, 0.3, gy + 0.7, gy + 1.0, (0.8, 0.8, 0.8))          # Mittelträger
    for a_q in np.arange(-8.4, 8.5, 2.4):                                               # Querträger
        hb_box_l(dunkel, "stahl_dunkel", fr, a_q - 0.1, a_q + 0.1, -1.25, 1.25, gy + 0.8, gy + 1.05, frame_c)
    for a in (-9.9, 9.9):
        hb_box_l(dunkel, "stahl_dunkel", fr, a - 0.1, a + 0.1, -1.3, 1.3, gy + 0.7, gy + 1.1, (1, 1, 1))
        for b in (-0.85, 0.85):
            hb_buffer(lists, fr, a + (0.1 if a > 0 else -0.1), b, gy, 1 if a > 0 else -1)
    for bog in (-6.9, 6.9):
        hb_box_l(dunkel, "stahl_dunkel", fr, bog - 1.45, bog + 1.45, -0.95, 0.95, gy + 0.55, gy + 0.78, (1, 1, 1))
        for ax in (-1.0, 1.0):
            for b in (-0.72, 0.72):
                hb_wheel(lists["stahl_dunkel"], fr, bog + ax, b, gy + 0.46, 0.46, 0.14, sides=10, hub=False, key="stahl_dunkel", col=(0.5, 0.5, 0.52), both_sides=True)
                hb_box_l(dunkel, "stahl_dunkel", fr, bog + ax - 0.17, bog + ax + 0.17, b + (0.12 if b > 0 else -0.28), b + (0.28 if b > 0 else -0.12), gy + 0.36, gy + 0.56, (0.7, 0.7, 0.72), (1.0, 1.0))
        for b in (-0.95, 0.95):                                                                                      # Blattfedern
            hb_box_l(dunkel, "stahl_dunkel", fr, bog - 1.1, bog + 1.1, b - 0.04, b + 0.04, gy + 0.62, gy + 0.7, (0.8, 0.8, 0.8), (1.0, 1.0))
    for a in (-9.2, 9.2):                                                                                            # Bremserbühne und Handbremse
        for sgn in (-1, 1):
            hb_box_l(dunkel, "stahl_dunkel", fr, a - 0.5, a + 0.5, sgn * 1.1 - 0.12, sgn * 1.1 + 0.12, gy + 1.1, gy + 1.14, (0.9, 0.9, 0.92), (1.0, 1.0))
    bx, bz, _ = fr.p(-9.0, 1.0, 0)
    hb_prism(stahl, bx, bz, 0.16, gy + 1.5, gy + 1.54, "stahl", (0.6, 0.6, 0.62), 8, tile=1.0)
    hb_prism(stahl, bx, bz, 0.02, gy + 1.1, gy + 1.5, "stahl", (0.6, 0.6, 0.62), 6, tile=1.0)
    rng2 = random.Random(seed)
    loaded = rng2.random() < 0.75
    if loaded:
        if rng2.random() < 0.5:
            cxx, czz, _ = fr.p(0.0, 0.0, 0)
            hb_container_one(lists["container"], cxx, czz, fr.ux, fr.uz, HB_L40 / 2, HB_CW / 2, gy + 1.1, cols[0], door_front=rng2.random() < 0.5, seed=seed)
        else:
            for off, c in ((-6.15, cols[0]), (6.15, cols[1])):
                cxx, czz, _ = fr.p(off, 0.0, 0)
                hb_container_one(lists["container"], cxx, czz, fr.ux, fr.uz, HB_L20 / 2, HB_CW / 2, gy + 1.1, c, door_front=rng2.random() < 0.5, seed=seed + int(off))
    else:
        for a in (-9.2, -3.15, 3.15, 9.2):                                                                           # leerer Wagen: Containerzapfen auf dem Rahmen
            for b in (-1.0, 1.0):
                hb_box_l(lack, "lack", fr, a - 0.1, a + 0.1, b - 0.1, b + 0.1, gy + 1.1, gy + 1.2, rost, (1.0, 1.0))


def hb_loco(lists, cx, cz, ux, uz):
    """Kleine Rangierlok (Diesel, Vorbild V 60/Köf): lange Motorhaube mit Kühlergitter und Auspuff, Führerhaus mit Fenstern rundum und Dachlüfter,
    Umlauf mit Geländer, Pufferbohlen gelb-schwarz, Puffer, Scheinwerfer, zwei Achsen mit Kuppelstange."""
    fr = HbFrame(cx, cz, ux, uz)
    gy = GROUND_Y + 0.5
    lack, dunkel, glas, stahl = lists["lack"], lists["stahl_dunkel"], lists["glas"], lists["stahl"]
    red, yel = hb_lin((0.72, 0.1, 0.05)), hb_lin((0.95, 0.74, 0.05))
    blk = hb_lin((0.05, 0.05, 0.055))
    hb_box_l(dunkel, "stahl_dunkel", fr, -4.3, 4.3, -1.25, 1.25, gy + 0.62, gy + 1.0, (1, 1, 1))                       # Rahmen
    for a_end, sg in ((-4.5, -1), (4.5, 1)):                                                                          # Pufferbohlen, gelb-schwarz
        for k, (b0, b1) in enumerate(((-1.4, -0.7), (-0.7, 0.0), (0.0, 0.7), (0.7, 1.4))):
            hb_box_l(lack, "lack", fr, min(a_end, a_end - sg * 0.3), max(a_end, a_end - sg * 0.3), b0, b1, gy + 0.78, gy + 1.18, yel if k % 2 == 0 else blk, (0.85, 1.0))
        for b in (-0.85, 0.85):
            hb_buffer(lists, fr, a_end, b, gy, sg)
    # Motorhaube (lang, niedrig) mit Absatz, Kühlergitter am Ende, Lüftungsgittern an den Seiten
    hb_box_l(lack, "lack", fr, -4.3, 0.5, -1.3, 1.3, gy + 1.0, gy + 2.2, red, (0.7, 1.0))
    hb_box_l(lack, "lack", fr, -4.1, 0.4, -1.1, 1.1, gy + 2.2, gy + 2.42, tuple(v * 0.85 for v in red), (0.95, 1.0))
    hb_wall(dunkel, "stahl_dunkel", fr, -4.305, -0.95, -4.305, 0.95, gy + 1.25, gy + 2.05, (0.5, 0.5, 0.52), (0.8, 0.8, 0.82), facing=(-1, 0))
    for sgn in (-1, 1):
        hb_wall(dunkel, "stahl_dunkel", fr, -3.6, sgn * 1.305, -1.6, sgn * 1.305, gy + 1.45, gy + 2.0, (0.7, 0.7, 0.72), (0.9, 0.9, 0.92), facing=(0, sgn))
        hb_wall(lack, "lack", fr, -4.28, sgn * 1.305, 0.45, sgn * 1.305, gy + 1.0, gy + 1.28, yel, yel, facing=(0, sgn))        # gelber Streifen
    px, pz, _ = fr.p(-1.9, 0.55, 0)
    hb_prism(stahl, px, pz, 0.12, gy + 2.42, gy + 3.2, "stahl", (0.35, 0.35, 0.37), 8, r_top=0.10, tile=1.0)
    hb_prism(stahl, px, pz, 0.17, gy + 3.2, gy + 3.28, "stahl", (0.25, 0.25, 0.27), 8, tile=1.0)
    hb_box_l(dunkel, "stahl_dunkel", fr, -3.2, -2.3, -0.5, 0.2, gy + 2.42, gy + 2.62, (0.8, 0.8, 0.82), (1.0, 1.0))        # Dachlüfter der Haube
    # Führerhaus: Fenster vorn/hinten/seitlich, Dach mit Überstand, Dachlüfter, Hupe
    hb_box_l(lack, "lack", fr, 0.5, 4.3, -1.45, 1.45, gy + 1.0, gy + 3.7, red, (0.7, 1.0))
    for sgn in (-1, 1):
        hb_wall(glas, "glas", fr, 1.0, sgn * 1.455, 2.2, sgn * 1.455, gy + 2.25, gy + 3.35, facing=(0, sgn))
        hb_wall(glas, "glas", fr, 2.7, sgn * 1.455, 3.9, sgn * 1.455, gy + 2.25, gy + 3.35, facing=(0, sgn))
        hb_wall(lack, "lack", fr, 0.52, sgn * 1.455, 4.28, sgn * 1.455, gy + 1.0, gy + 1.3, yel, yel, facing=(0, sgn))
    hb_wall(glas, "glas", fr, 4.305, -1.2, 4.305, -0.1, gy + 2.25, gy + 3.35, facing=(1, 0))
    hb_wall(glas, "glas", fr, 4.305, 0.1, 4.305, 1.2, gy + 2.25, gy + 3.35, facing=(1, 0))
    hb_wall(glas, "glas", fr, 0.495, -0.9, 0.495, 0.9, gy + 2.3, gy + 3.2, facing=(-1, 0))
    hb_box_l(lack, "lack", fr, 0.4, 4.45, -1.55, 1.55, gy + 3.7, gy + 3.86, hb_lin((0.3, 0.3, 0.32)), (1.0, 1.0))
    hb_box_l(lack, "lack", fr, 1.4, 2.8, -0.5, 0.5, gy + 3.86, gy + 4.06, hb_lin((0.4, 0.4, 0.42)), (1.0, 1.0))
    hb_box_l(dunkel, "stahl_dunkel", fr, 3.6, 3.9, -0.2, 0.2, gy + 3.86, gy + 4.0, (1, 1, 1), (1.0, 1.0))                  # Hupe
    for b in (-0.9, 0.9):                                                                                             # Scheinwerfer und Schlusslichter (nur Farbe)
        hb_box_l(lack, "lack", fr, 4.3, 4.34, b - 0.12, b + 0.12, gy + 1.5, gy + 1.7, hb_lin((0.96, 0.9, 0.7)), (1.0, 1.0))
        hb_box_l(lack, "lack", fr, -4.34, -4.3, b - 0.1, b + 0.1, gy + 1.3, gy + 1.45, hb_lin((0.7, 0.04, 0.03)), (1.0, 1.0))
    # Umlauf mit Geländer an der Haube
    for sgn in (-1, 1):
        pts = [fr.p(-4.0, sgn * 1.55, 0)[:2], fr.p(0.4, sgn * 1.55, 0)[:2]]
        hb_box_l(dunkel, "stahl_dunkel", fr, -4.1, 0.5, sgn * 1.3, sgn * 1.55, gy + 0.98, gy + 1.03, (0.9, 0.9, 0.92), (1.0, 1.0))
        hb_railing(lists["stahl"], pts, y0=gy + 1.03, height=0.9, key="stahl", col=(0.9, 0.9, 0.92), post_every=1.5, collide=False)
    # Räder, Achslager und Kuppelstange
    for ax in (-2.0, 2.0):
        for b in (-0.72, 0.72):
            hb_wheel(lists["stahl_dunkel"], fr, ax, b, gy + 0.55, 0.55, 0.14, sides=10, hub=False, key="stahl_dunkel", col=(0.5, 0.5, 0.52), both_sides=True)
            hb_box_l(dunkel, "stahl_dunkel", fr, ax - 0.2, ax + 0.2, b + (0.12 if b > 0 else -0.3), b + (0.3 if b > 0 else -0.12), gy + 0.4, gy + 0.66, (0.7, 0.7, 0.72), (1.0, 1.0))
    for b in (-1.0, 1.0):
        hb_box_l(stahl, "stahl", fr, -2.0, 2.0, b - 0.04, b + 0.04, gy + 0.5, gy + 0.58, (0.8, 0.8, 0.82), (1.0, 1.0))


def hb_build_siding(rng_):
    sd = HB["siding"]
    if not sd:
        return
    xs_, z_a, z_b = sd["x"], sd["z_a"], sd["z_b"]
    gy = GROUND_Y
    top = gy + 0.18
    parts = hb_new_parts("schotter", "beton", "stahl", "stahl_dunkel", "rot", "gelb")
    # Schotterbett: Trapezquerschnitt (oben 3,6 m, unten 5,2 m)
    for sgn in (-1, 1):
        hb_quad(parts["schotter"], "schotter", [(xs_ + sgn * 2.6, z_a, gy), (xs_ + sgn * 2.6, z_b, gy), (xs_ + sgn * 1.8, z_b, top), (xs_ + sgn * 1.8, z_a, top)],
                [(0, z_a / 2), (0, z_b / 2), (0.4, z_b / 2), (0.4, z_a / 2)], (sgn, 0), [(0.8, 0.8, 0.8)] * 2 + [(1, 1, 1)] * 2)
    hb_quad(parts["schotter"], "schotter", [(xs_ - 1.8, z_a, top), (xs_ + 1.8, z_a, top), (xs_ + 1.8, z_b, top), (xs_ - 1.8, z_b, top)],
            [(-0.9, z_a / 2), (0.9, z_a / 2), (0.9, z_b / 2), (-0.9, z_b / 2)], None, [(1, 1, 1)] * 4)
    z = z_a + 0.4
    while z < z_b - 0.3:
        hb_box_l(parts["beton"], "beton", HbFrame(xs_, z, 0.0, 1.0), -0.13, 0.13, -1.3, 1.3, top, top + 0.16, (0.8, 0.8, 0.78), (0.9, 1.0), 1.0)
        z += 0.65
    for b in (-0.7175, 0.7175):
        hb_cuboid(parts["stahl"], xs_ + b, (z_a + z_b) / 2, 0.0, 1.0, (z_b - z_a) / 2 - 0.2, 0.035, top + 0.16, top + 0.32, "stahl", col=(0.75, 0.75, 0.78), tile=1.0, bottom_fade=False)
    for zb_, sg in ((z_a + 0.5, 1), (z_b - 0.5, -1)):
        hb_box_l(parts["rot"], "rot", HbFrame(xs_, zb_, 0.0, 1.0), -0.5, 0.5, -0.9, 0.9, top + 0.16, top + 1.0, (1, 1, 1), (1.0, 1.0), 1.0)
        hb_box_l(parts["gelb"], "gelb", HbFrame(xs_, zb_ - sg * 0.52, 0.0, 1.0), -0.03, 0.03, -0.85, 0.85, top + 0.4, top + 0.9, (1, 1, 1), (1.0, 1.0), 1.0)
    lists = hb_new_parts("lack", "stahl_dunkel", "glas", "stahl", "gummi")
    cont = ([], [], [])
    lists["container"] = cont
    for (kind, zc, hl, cols, seed) in sd["vehicles"]:
        if kind == "loco":
            hb_loco(lists, xs_, zc, 0.0, 1.0)
        else:
            hb_wagon(lists, xs_, zc, 0.0, 1.0, cols, seed)
    for k, v in parts.items():
        if v:
            mesh_objects("Gleis_" + k, v)
    for k, v in lists.items():
        if k != "container" and v:
            mesh_objects("Bahn_" + k, v)
    for name, ps in zip(("Bahn_container_seite", "Bahn_container_tuer", "Bahn_container_dach"), cont):
        if ps:
            mesh_object(name, ps)
    print("DIORAMA Gleisanschluss: Fahrzeuge", len(sd["vehicles"]))


# ---------------------------------------------------------------- Containerterrasse Ost (Harbour Run, Fassung 2; docs/dioramen/HOEHEN_PLAN.md 4.2, 7 C1)
# Die Spielebene (Höhenprofil, Geländeraster = Fahrbahnhöhe bis Halbbreite + 1 m, Leitplanken, Lücke mit Lippe 0,4) steht in der Streckendatei.
# Das Diorama trägt die Laufzeit-Fahrbahn sichtbar: zwei Lagen Container unter der Terrasse, gestufte Containertürme und Stahlstützen unter der
# Auffahrt, ein durchgehendes Stahldeck aus Riffelblech (±4,5 m = Geländeraster, 5 cm unter der Fahrbahn) mit gelber Kante, gelbe Geländer entlang der
# Leitplanken, eine schwarz-gelbe Absprungkante, die Gasse mit Portalhubwagen und die Landerampe aus Stahl mit verkratzter Lippe. Keine
# Container-Hindernisse unter oder an der Terrassenfahrbahn; "supports" verbietet dem Spiel Laufzeit-Pfeiler.
HB_LV = {}
HB_DECK_DY = 0.12                                  # Oberkante Stahldeck über der Basis (Fahrbahn 0,17, Randsteine 0,14 bis 0,285)
HB_DECK_HW = 4.5                                   # Halbbreite des Decks (Geländeraster: Fahrbahnhöhe bis Halbbreite + 1 m)
HB_GIRDER = 0.42                                   # Höhe der Randträger unter dem Deck


def hb_lv_sections():
    """Abschnitte des Hochteils aus der Streckendatei: Auffahrt, Terrasse, Gasse (erhöhte Lücke), Landerampe; None ohne Hochteil."""
    if IS_ARENA:
        return None
    el = data.get("elevation", [])
    high = [g for g in data.get("gaps", []) if base_height(float(g["from"])) > 0.5]
    if len(el) < 4 or not high:
        return None
    g = high[0]
    return {"up": (float(el[0][0]), float(el[1][0])), "top": (float(el[1][0]), float(g["from"])), "gap": (float(g["from"]), float(g["to"])),
            "land": (float(g["to"]), float(el[-1][0])), "lip": float(g.get("lip", 3.0))}


def hb_lv_i(s):
    return int(round((s % 1.0) * N)) % N


def hb_lv_at(k):
    """Mittellinienpunkt k des Kerns (0,5 m): Punkt, Tangente, links, Basis."""
    k %= N
    return (np.array([center[k].x, center[k].y]), np.array([tang[k].x, tang[k].y]), np.array([left[k].x, left[k].y]), float(base_height(float(S_OF[k]))))


def hb_lv_range(s0, s1):
    """Indizes der Mittellinie von s0 bis s1 (ohne Lückenstücke an den Enden)."""
    i0, i1 = hb_lv_i(s0), hb_lv_i(s1)
    if i1 < i0:
        i1 += N
    return [k for k in range(i0, i1 + 1)]


def hb_lv_unguarded_dist(x, z):
    """Abstand zur Mittellinie der erhöhten Abschnitte ohne Leitplanke (Auffahrt unterhalb der Leitplanken, Landerampe); ohne Hochteil groß."""
    if not HB_LV:
        return 1e9
    g0 = min([float(g["from"]) for g in data.get("guardrails", [])] or [HB_LV["top"][0]])
    best = 1e9
    for s0, s1 in ((HB_LV["up"][0], g0), (HB_LV["land"][0], HB_LV["land"][1])):
        for k in hb_lv_range(s0, s1)[::2]:
            best = min(best, math.hypot(center[k % N].x - x, center[k % N].y - z))
    return best


def hb_lv_plan():
    """Planung vor den Containerfeldern: Band der Hochstrecke belegen, Portalhubwagen in der Gasse, Gasse freihalten, Leuchten auf der Terrasse."""
    HB_LV.clear()
    sec = hb_lv_sections()
    if not sec:
        return
    HB_LV.update(sec)
    for k in hb_lv_range(sec["up"][0] - 2.0 / TOTAL, sec["land"][1] + 2.0 / TOTAL)[::4]:
        p, t, _l, _b = hb_lv_at(k)
        hb_occupy(float(p[0]), float(p[1]), float(t[0]), float(t[1]), 1.4, 5.4)
    gm = (sec["gap"][0] + sec["gap"][1]) / 2.0
    p, t, l, _b = hb_lv_at(hb_lv_i(gm))
    glen = ((sec["gap"][1] - sec["gap"][0]) % 1.0) * TOTAL
    HB_LV["gap_mid"] = (p, t, l, glen)
    HB_LV["straddle"] = None
    for off in (13.5, -13.5, 15.5, -15.5, 18.0, -18.0):
        q = p + l * off
        rc = hb_straddle_rect(float(q[0]), float(q[1]), float(l[0]), float(l[1]))
        if hb_solid(rc[0], rc[1], rc[2], rc[3], rc[4], rc[5], 6.6, "auto", margin=2.0, pad=0.2):
            HB_LV["straddle"] = {"c": (float(q[0]), float(q[1])), "u": (rc[2], rc[3]), "body": (0.95, 0.72, 0.06), "cont": (0.10, 0.28, 0.52), "seed": 31}
            break
    hb_occupy(float(p[0]), float(p[1]), float(t[0]), float(t[1]), glen / 2.0 + 1.0, 26.0)       # Gasse quer durch den Hof bleibt frei
    # Leuchten auf der Terrasse: Mast auf dem Deck außerhalb des Geländers, je auf der Seite ohne andere Fahrbahn
    HB_LV["masts"] = []
    s_t0, s_t1 = sec["top"]
    for frac in (0.32, 0.78):
        s = s_t0 + ((s_t1 - s_t0) % 1.0) * frac
        p, t, l, b = hb_lv_at(hb_lv_i(s))
        best = None
        for side in (1.0, -1.0):
            far = float(dist_to_center(np.array([p + l * side * 9.0]))[0])
            if best is None or far > best[0]:
                best = (far, side)
        side = best[1]
        q = p + l * side * 4.36
        HB_LV["masts"].append((float(q[0]), float(q[1]), b + HB_DECK_DY, (float(p[0]), float(p[1]))))
    add_supports(sec["up"][0], sec["land"][1])
    print("DIORAMA Containerterrasse: Abschnitte", {k: v for k, v in sec.items()}, "| Portalhubwagen", HB_LV["straddle"] is not None, "| Leuchten", len(HB_LV["masts"]))


def hb_lv_containers(lists, rng_):
    """Container unter Auffahrt und Terrasse: vier Reihen längs der Fahrbahn (Mitte ±1,235 und ±3,705 m), 40-Fuß auf Geraden, 20-Fuß in Kurven;
    Lagen nach der Basis (oberste Lage höchstens 3 cm unter der Deckunterkante), keine Überlappung. Rückgabe: Liste (Viereck, Oberkante)."""
    sec = HB_LV
    idx = hb_lv_range(sec["up"][0], sec["gap"][0])
    base = np.array([float(base_height(float(S_OF[k % N]))) for k in idx])
    placed = []
    n_c = 0
    for off in (-3.705, -1.235, 1.235, 3.705):
        P = np.array([[center[k % N].x + left[k % N].x * off, center[k % N].y + left[k % N].y * off] for k in idx])
        arc = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(P, axis=0), axis=1))])
        L_end = float(arc[-1])

        def at(d):
            j = int(np.clip(np.searchsorted(arc, d) - 1, 0, len(arc) - 2))
            f = (d - arc[j]) / max(arc[j + 1] - arc[j], 1e-6)
            return P[j] + (P[j + 1] - P[j]) * f
        pos = 0.0
        while pos < L_end - 2.0:
            done = False
            for L, dev_max in ((HB_L40, 0.30), (HB_L20, 0.75)):
                if pos + L > L_end + 0.01:
                    continue
                pa, pb = at(pos), at(pos + L)
                ch = pb - pa
                ln = float(np.linalg.norm(ch))
                if ln < L * 0.7:
                    continue
                u = ch / ln
                sel = (arc >= pos) & (arc <= pos + L)
                mids = P[sel]
                dev = float(np.abs((mids - pa) @ np.array([-u[1], u[0]])).max()) if len(mids) else 0.0
                if dev > dev_max:
                    continue
                b_min = float(base[sel].min()) if sel.any() else 0.0
                tiers = int(math.floor((b_min + HB_DECK_DY - HB_GIRDER * 0.0 - 0.03 - 0.06) / HB_CH + 1e-6))
                tiers = min(tiers, 2)
                if tiers <= 0:
                    break
                c = (pa + pb) / 2.0
                poly = hb_poly(float(c[0]), float(c[1]), float(u[0]), float(u[1]), ln / 2.0, HB_CW / 2.0, 0.0)
                if any(hb_overlap(poly, q) for q, _ in placed):
                    continue
                col = hb_pick_color(rng_)
                door = rng_.random() < 0.5
                for tt in range(tiers):
                    hb_container_one(lists, float(c[0]), float(c[1]), float(u[0]), float(u[1]), ln / 2.0, HB_CW / 2.0, 0.06 + tt * HB_CH,
                                     col if tt == tiers - 1 else hb_pick_color(rng_), door_front=door, seed=rng_.randrange(1 << 20), top=(tt == tiers - 1))
                    n_c += 1
                placed.append((poly, 0.06 + tiers * HB_CH))
                pos += L + 0.08
                done = True
                break
            if not done:
                pos += 0.5
    print("DIORAMA Containerterrasse: Container", n_c, "in", len(placed), "Stapeln")
    return placed


def hb_lv_point_top(x, z, placed):
    """Oberkante der Terrassen-Container an einem Punkt (sonst Boden)."""
    best = GROUND_Y
    for poly, top in placed:
        inside_ = True
        n = len(poly)
        for i in range(n):
            ax, az = poly[i]
            bx, bz = poly[(i + 1) % n]
            if (bx - ax) * (z - az) - (bz - az) * (x - ax) < 0:
                inside_ = False
                break
        if inside_:
            best = max(best, top)
    return best


def hb_lv_deck(parts, dec_yellow):
    """Stahldeck (Riffelblech) über Auffahrt, Terrasse und Landerampe, gelbe Kante, Randträger (Stirnblech) und Unterseite."""
    sec = HB_LV
    rows = []
    for s0, s1 in ((sec["up"][0], sec["gap"][0]), (sec["land"][0], sec["land"][1])):
        rr = []
        for k in hb_lv_range(s0, s1):
            if in_gap(float(S_OF[k % N])):
                continue
            p, t, l, b = hb_lv_at(k)
            rr.append((p, t, l, b + HB_DECK_DY))
        rows.append(rr)
    n = 0
    for rr in rows:
        for (pa, ta, la, ya), (pb, tb, lb, yb) in zip(rr, rr[1:]):
            A = lambda o, dy=0.0: (float(pa[0] + la[0] * o), float(pa[1] + la[1] * o), ya + dy)
            B = lambda o, dy=0.0: (float(pb[0] + lb[0] * o), float(pb[1] + lb[1] * o), yb + dy)
            hw_ = HB_DECK_HW
            q = [A(-hw_), B(-hw_), B(hw_), A(hw_)]
            hb_quad(parts["riffel"], "riffel", q, [(c[0], c[1]) for c in q], None, [(0.92, 0.93, 0.95)] * 4)
            for sg in (-1.0, 1.0):
                o0, o1 = sg * (hw_ - 0.12), sg * hw_
                hb_quad(dec_yellow, "linie_gelb", [A(o0, 0.004), B(o0, 0.004), B(o1, 0.004), A(o1, 0.004)], [(0, 0), (1, 0), (1, 1), (0, 1)])
                face = (float(la[0] * sg), float(la[1] * sg))
                hb_quad(parts["stahl_dunkel"], "stahl_dunkel", [A(o1, 0.0), B(o1, 0.0), B(o1, -HB_GIRDER), A(o1, -HB_GIRDER)],
                        [(0, 0), (1, 0), (1, 0.4), (0, 0.4)], face, [(0.62, 0.62, 0.60)] * 2 + [(0.46, 0.46, 0.45)] * 2)
                hb_quad(dec_yellow, "linie_gelb", [A(o1 + sg * 0.005, -0.01), B(o1 + sg * 0.005, -0.01), B(o1 + sg * 0.005, -0.09), A(o1 + sg * 0.005, -0.09)],
                        [(0, 0), (1, 0), (1, 1), (0, 1)], face)
            n += 1
    HB_LV["deck_rows"] = rows
    print("DIORAMA Stahldeck:", n, "Felder")


def hb_lv_supports(parts, placed):
    """Stützen der Auffahrt (über den Containertürmen bzw. vom Boden) und der Landerampe: je Joch zwei Stahlstützen (HEB 300) unter den
    Randträgern, Querträger, bei hohen Jochen ein Mittelriegel; Fußplatten auf Boden oder Containerdach."""
    sec = HB_LV
    n = 0

    def brace(pa, ya, pb, yb, sg, nrm):
        """Diagonalstrebe (Flachstahl 12 cm) zwischen zwei Punkten, beidseitig sichtbar."""
        d = np.array([pb[0] - pa[0], pb[1] - pa[1], yb - ya])
        ln = float(np.linalg.norm(d)) or 1.0
        up = np.array([0.0, 0.0, 1.0])
        w = np.cross(d / ln, np.array([nrm[0], nrm[1], 0.0]))
        w = w / (np.linalg.norm(w) or 1.0) * 0.06
        q = [(pa[0] - w[0], pa[1] - w[1], ya - w[2]), (pb[0] - w[0], pb[1] - w[1], yb - w[2]), (pb[0] + w[0], pb[1] + w[1], yb + w[2]), (pa[0] + w[0], pa[1] + w[1], ya + w[2])]
        for f in (1.0, -1.0):
            hb_quad(parts["stahl"], "stahl", q if f > 0 else q[::-1], [(0, 0), (1, 0), (1, 1), (0, 1)], (nrm[0] * f * sg, nrm[1] * f * sg), [(0.72, 0.74, 0.77)] * 4)
    for s0, s1 in ((sec["up"][0], sec["top"][0] + 6.0 / TOTAL), (sec["land"][0], sec["land"][1])):
        ks = hb_lv_range(s0, s1)
        prev = {}
        for k in ks[2::9]:
            p, t, l, b = hb_lv_at(k)
            y_top = b + HB_DECK_DY - HB_GIRDER
            if y_top - GROUND_Y < 0.35:
                continue
            feet = []
            for sg in (-1.0, 1.0):
                q = p + l * sg * 3.95
                y0 = hb_lv_point_top(float(q[0]), float(q[1]), placed)
                if y_top - y0 < 0.2:
                    feet.append(None)
                    prev[sg] = None
                    continue
                hb_cuboid(parts["stahl"], float(q[0]), float(q[1]), float(t[0]), float(t[1]), 0.15, 0.15, y0, y_top, "stahl", col=(0.78, 0.80, 0.82), tile=1.0,
                          bottom_fade=False)
                hb_cuboid(parts["stahl_dunkel"], float(q[0]), float(q[1]), float(t[0]), float(t[1]), 0.24, 0.24, y0, y0 + 0.03, "stahl_dunkel", col=(0.7, 0.7, 0.72),
                          tile=1.0, bottom_fade=False)
                feet.append((q, y0))
                n += 1
                pv = prev.get(sg)
                if pv is not None and y_top - y0 > 1.4 and pv[2] - pv[1] > 1.4:          # Längsverband: Kreuz zwischen zwei Jochen
                    q_l = (float(l[0] * sg), float(l[1] * sg))
                    brace((float(pv[0][0]), float(pv[0][1])), pv[1] + 0.15, (float(q[0]), float(q[1])), y_top - 0.1, 1.0, q_l)
                    brace((float(pv[0][0]), float(pv[0][1])), pv[2] - 0.1, (float(q[0]), float(q[1])), y0 + 0.15, 1.0, q_l)
                prev[sg] = (q, y0, y_top)
            if any(f is not None for f in feet):
                hb_cuboid(parts["stahl_dunkel"], float(p[0]), float(p[1]), float(l[0]), float(l[1]), 4.2, 0.14, y_top - 0.3, y_top, "stahl_dunkel",
                          col=(0.72, 0.72, 0.70), tile=1.0, bottom_fade=False)
                if all(f is not None for f in feet) and y_top - max(f[1] for f in feet) > 2.2:
                    ym = (y_top + max(f[1] for f in feet)) / 2.0
                    hb_cuboid(parts["stahl"], float(p[0]), float(p[1]), float(l[0]), float(l[1]), 3.85, 0.06, ym - 0.08, ym + 0.08, "stahl",
                              col=(0.7, 0.72, 0.75), tile=1.0, bottom_fade=False)
    print("DIORAMA Stützen der Rampen:", n)


def hb_lv_rails(parts):
    """Gelbe Geländer entlang der Leitplanken der Streckendatei (Pfosten alle 2 m, Handlauf 1,1 m und Knieleiste) auf dem Deck, 4,2 m neben der Mitte."""
    n = 0
    for g in data.get("guardrails", []):
        side = 1.0 if str(g.get("side")) == "left" else -1.0
        ks = [k for k in hb_lv_range(float(g["from"]), float(g["to"])) if not in_gap(float(S_OF[k % N]))]
        pts = []
        for k in ks:
            p, t, l, b = hb_lv_at(k)
            q = p + l * side * 4.2
            pts.append((float(q[0]), float(q[1]), b + HB_DECK_DY, t))
        for j, (x, z, y, t) in enumerate(pts):
            if j % 4 == 0 or j == len(pts) - 1:
                hb_cuboid(parts["gelb"], x, z, float(t[0]), float(t[1]), 0.04, 0.04, y, y + 1.12, "gelb", col=(1.0, 1.0, 1.0), tile=1.0, bottom_fade=False)
                n += 1
        for (xa, za, ya, ta), (xb, zb, yb, tb) in zip(pts, pts[1:]):
            nx_, nz_ = -ta[1] * 0.025, ta[0] * 0.025
            for hy in (1.1, 0.55):
                top = [(xa - nx_, za - nz_, ya + hy + 0.025), (xb - nx_, zb - nz_, yb + hy + 0.025), (xb + nx_, zb + nz_, yb + hy + 0.025), (xa + nx_, za + nz_, ya + hy + 0.025)]
                hb_quad(parts["gelb"], "gelb", top, [(0, 0), (1, 0), (1, 1), (0, 1)], None, [(1.0, 1.0, 1.0)] * 4)
                for sg in (-1.0, 1.0):
                    fx, fz = nx_ * sg, nz_ * sg
                    side_q = [(xa + fx, za + fz, ya + hy - 0.025), (xb + fx, zb + fz, yb + hy - 0.025), (xb + fx, zb + fz, yb + hy + 0.025), (xa + fx, za + fz, ya + hy + 0.025)]
                    hb_quad(parts["gelb"], "gelb", side_q, [(0, 0), (1, 0), (1, 1), (0, 1)], (fx, fz), [(0.85, 0.85, 0.85)] * 4)
    print("DIORAMA Geländer auf der Terrasse: Pfosten", n)


def hb_lv_edge(parts, dec_black, dec_yellow):
    """Schwarz-gelbe Absprungkante: Schrägstreifen quer über Fahrbahn und Deck (letzte 0,6 m vor der Gasse, Höhe der Laufzeit-Markierungen) und an der
    Stirnseite der Terrasse (Blende 0,6 m) zur Gasse hin."""
    sec = HB_LV
    s_e = sec["gap"][0] - 0.35 / TOTAL
    p, t, l, b = hb_lv_at(hb_lv_i(s_e))
    a, c = p - l * HB_DECK_HW, p + l * HB_DECK_HW
    hb_hatch(dec_black, dec_yellow, float(a[0]), float(a[1]), float(c[0]), float(c[1]), 0.6, b + 0.197, period=0.5, angle_deg=45.0)
    # Stirnseite: abwechselnd gelbe und schwarze Schrägstreifen
    k_e = hb_lv_i(sec["gap"][0])
    while in_gap(float(S_OF[k_e % N])):
        k_e -= 1
    p, t, l, b = hb_lv_at(k_e)
    y1, y0 = b + HB_DECK_DY, b + HB_DECK_DY - 0.6
    face = (float(t[0]), float(t[1]))
    w = 0.32
    o = -HB_DECK_HW
    k = 0
    while o < HB_DECK_HW - 1e-6:
        o1 = min(HB_DECK_HW, o + w)
        sh = 0.6
        q0 = p + l * o + t * 0.02
        q1 = p + l * o1 + t * 0.02
        q2 = p + l * min(HB_DECK_HW, o1 + sh) + t * 0.02
        q3 = p + l * min(HB_DECK_HW, o + sh) + t * 0.02
        pts = [(float(q0[0]), float(q0[1]), y1), (float(q1[0]), float(q1[1]), y1), (float(q2[0]), float(q2[1]), y0), (float(q3[0]), float(q3[1]), y0)]
        key, out = ("linie_gelb", dec_yellow) if k % 2 == 0 else ("linie_schwarz", dec_black)
        hb_quad(out, key, pts, [(0, 0), (1, 0), (1, 1), (0, 1)], face)
        o = o1
        k += 1
    # Rest der Stirnseite links unten (Schräge) schwarz schließen
    q0, q1 = p - l * HB_DECK_HW + t * 0.015, p - l * (HB_DECK_HW - 0.6) + t * 0.015
    hb_quad(dec_black, "linie_schwarz", [(float(q0[0]), float(q0[1]), y1), (float(q0[0]), float(q0[1]), y0), (float(q1[0]), float(q1[1]), y0)],
            [(0, 0), (1, 0), (1, 1)], face)
    print("DIORAMA Absprungkante: Schrägstreifen", k)


def hb_lv_lip(parts):
    """Landerampe: Stirnwand zur Gasse aus Stahlblech (senkrechte Bahnen, Kratzer blank, Rostläufer) und eine verkratzte Lippe (Winkelstahl) oben."""
    sec = HB_LV
    rr = HB_LV.get("deck_rows", [[], []])[1]
    if not rr:
        return
    p, t, l, y_top = rr[0]
    rng_ = random.Random(61)
    face = (float(-t[0]), float(-t[1]))
    o = -HB_DECK_HW
    while o < HB_DECK_HW - 1e-6:
        o1 = min(HB_DECK_HW, o + 0.25)
        v = rng_.random()
        col = (0.30, 0.31, 0.33)
        if v < 0.2:
            col = (0.55, 0.56, 0.58)
        elif v < 0.33:
            col = (0.45, 0.30, 0.18)
        q0, q1 = p + l * o - t * 0.03, p + l * o1 - t * 0.03
        hb_quad(parts["stahl_dunkel"], "stahl_dunkel", [(float(q0[0]), float(q0[1]), GROUND_Y - 0.02), (float(q1[0]), float(q1[1]), GROUND_Y - 0.02),
                                                         (float(q1[0]), float(q1[1]), y_top - 0.3), (float(q0[0]), float(q0[1]), y_top - 0.3)],
                [(0, 0), (1, 0), (1, 1), (0, 1)], face, [tuple(c * 0.8 for c in col)] * 2 + [col] * 2)
        lip = tuple(min(1.0, c * 1.5) for c in col)
        hb_quad(parts["stahl_dunkel"], "stahl_dunkel", [(float(q0[0]), float(q0[1]), y_top - 0.3), (float(q1[0]), float(q1[1]), y_top - 0.3),
                                                         (float(q1[0]), float(q1[1]), y_top + 0.01), (float(q0[0]), float(q0[1]), y_top + 0.01)],
                [(0, 0), (1, 0), (1, 1), (0, 1)], face, [lip] * 4)
        o = o1
    print("DIORAMA Landerampe: Stirnwand und Lippe")


def hb_lv_masts(parts):
    """Leuchten auf der Terrasse: verzinkter Mast (7 m) auf dem Deck außerhalb des Geländers, Ausleger zur Fahrbahn, LED-Kopf; echte Lichtquelle und
    Mast als Hindernis ab Deckhöhe (b)."""
    for (x, z, y0, (tx, tz)) in HB_LV.get("masts", []):
        dx, dz = tx - x, tz - z
        n = math.hypot(dx, dz) or 1.0
        ux, uz = dx / n, dz / n
        hb_prism(parts["stahl"], x, z, 0.16, y0, y0 + 0.08, "stahl", (0.7, 0.72, 0.75), 8, tile=1.0)
        hb_prism(parts["stahl"], x, z, 0.085, y0 + 0.08, y0 + 7.0, "stahl", (0.84, 0.86, 0.88), 8, r_top=0.06, tile=2.0)
        hx, hz = x + ux * 1.6, z + uz * 1.6
        hb_cuboid(parts["stahl"], (x + hx) / 2, (z + hz) / 2, ux, uz, 0.85, 0.04, y0 + 6.9, y0 + 6.98, "stahl", col=(0.84, 0.86, 0.88), tile=1.0, bottom_fade=False)
        hb_cuboid(parts["stahl_dunkel"], hx, hz, ux, uz, 0.32, 0.14, y0 + 6.78, y0 + 6.92, "stahl_dunkel", col=(0.5, 0.52, 0.55), tile=1.0, bottom_fade=False)
        add_light(hx, hz, y0 + 6.8, color=(1.0, 0.92, 0.78), energy=0.03, range=2.0, omni=False, glow=0.7)
        add_light(hx + ux * 2.0, hz + uz * 2.0, y0 + 6.8, color=(1.0, 0.92, 0.78), energy=0.85, range=13.0, omni=False)
        collide_circle(x, z, 0.16, 7.0, "mast", base=round(y0 - HB_DECK_DY, 3))
    print("DIORAMA Leuchten auf der Terrasse:", len(HB_LV.get("masts", [])))


def hb_lv_build(rng_, dec_black, dec_yellow):
    """Alle Bauteile der Containerterrasse (Hook theme_scenery, vor den Hindernissen des Themas)."""
    if not HB_LV:
        return
    parts = hb_new_parts("riffel", "stahl", "stahl_dunkel", "gelb")
    cont = ([], [], [])
    placed = hb_lv_containers(cont, random.Random(83))
    hb_lv_deck(parts, dec_yellow)
    hb_lv_supports(parts, placed)
    hb_lv_rails(parts)
    hb_lv_edge(parts, dec_black, dec_yellow)
    hb_lv_lip(parts)
    hb_lv_masts(parts)
    for name, ps in zip(("Terrasse_container_seite", "Terrasse_container_tuer", "Terrasse_container_dach"), cont):
        if ps:
            mesh_object(name, ps)
    for k, v in parts.items():
        if v:
            mesh_objects("Terrasse_" + k, v)
