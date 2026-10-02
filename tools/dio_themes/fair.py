"""Themenmodul "fair" (Fun Fair Eight): Rummelplatz mit Achterbahnkurs, abends und nachts.

Wird von tools/diorama.py in dessen Globals ausgeführt (siehe docs/dioramen/README.md); Beschreibung der Szene und der Entscheidungen:
docs/dioramen/fair.md. Straße: "runtime" (das Spiel baut Fahrbahn, Randsteine, Rampe und Lücke selbst), der Boden liegt auf 0,08.
Die KI-Bauteile der Streckendatei (Riesenrad, Karussell, Autoscooter, Zelt, Buden, Lichtmasten) bleiben Laufzeit-Bauteile (AO-Stellvertreter
backen ihren Kontaktschatten); alles Weitere hier ist gebacken und trägt seine Hindernisse in die Begleitdatei ein.

Nachts leuchtet nur, was eine Lichtquelle ist: Glühbirnen (K_lampe, K_ampel_*, K_lampe_blau), Leuchtleisten unter den Markisen und die
Lichtmasten der Streckendatei. Schilder, Wände und Menschen sind Körper, die von diesem Licht getroffen werden.
"""
_GEOM = os.path.join(os.path.dirname(os.path.abspath(__file__)), "make_fair_kids_geom.py")
with open(_GEOM, encoding="utf-8") as _fh:
    exec(compile(_fh.read(), _GEOM, "exec"), globals())

THEME_CFG = {
    "road": "runtime",
    "margin": 40.0,
    "baked": ["lamp"],
    "ground_set": {"grass": "res://assets/dio/fair/gras_getreten", "sand": "res://assets/dio/fair/saegespaene", "dirt": "res://assets/dio/fair/erde_platt"},
    "ground_scales": {"grass": 3.4, "sand": 3.2, "dirt": 3.4},
    "ground_tints": {"grass": [0.9, 0.9, 0.72], "sand": [1.0, 0.97, 0.92], "dirt": [0.98, 0.94, 0.88]},
    "tints": {"D_Wiese": [0.8, 0.82, 0.55], "D_PflasterMarkt": [0.84, 0.82, 0.78]},
}

SIGN_CELL = {"pommes": 0, "wurst": 1, "zuckerwatte": 2, "mandeln": 3, "crepes": 4, "eis": 5, "dosen": 6, "schiessen": 7, "enten": 8,
             "los": 9, "kasse": 10, "einlass": 11, "bier": 12, "riesenrad": 13, "autoscooter": 14, "karussell": 15}
# Grundflächen der Laufzeit-Modelle (halbe Maße längs/quer zur Modell-x-Achse, in m, nach Skalierung auf die Höhe der Streckendatei)
PROP_FOOT = {"jahrmarkt_riesenrad": (2.6, 8.6), "jahrmarkt_karussell": (4.2, 4.2), "jahrmarkt_autoscooter": (4.95, 3.6), "jahrmarkt_zelt": (5.3, 5.3),
             "jahrmarkt_bude": (1.95, 1.6), "jahrmarkt_losbude": (2.25, 1.65), "jahrmarkt_lichtermast": (1.5, 1.5)}
FENCE_IN = 6.0                 # Zaun des Festplatzes: so weit innerhalb der Diorama-Fläche

FAIR = []                      # Flächen der Szenerie (ein Objekt je Material)
CROWD = []                     # Besucher (E_menge)
FLOOR = []                     # flache Beläge auf dem Boden (Pflaster, Bohlen), bekommen die gebackene Umgebungsverdeckung
FIRST_BAKE = []


def FT(name):
    return os.path.normpath(os.path.join(PROPS, "..", "dio", "fair", name))


def theme_materials():
    M["f_planken"] = material("D_Planken", FT("planken.jpg"), 0.85, FT("planken_n.jpg"))
    M["f_schild"] = material("D_Schild", FT("schilder.jpg"), 0.6)
    M["f_markt"] = material("D_PflasterMarkt", tex("PavingStones142"), 0.85, tex("PavingStones142", "NormalGL"))
    M["f_gelaende"] = material("D_Gelaende", color=(0.45, 0.55, 0.35), rough=0.9)
    M["f_wiese"] = material("D_Wiese", tex("Grass005"), 0.95, tex("Grass005", "NormalGL"))


# ---------------------------------------------------------------- Hilfen
def vnoise(X, Z, scale, seed=0):
    """Wertrauschen (bilinear) auf Feldern (numpy), Werte 0..1."""
    g = np.random.default_rng(1000 + seed).random((64, 64))
    u, v = np.asarray(X) / scale, np.asarray(Z) / scale
    i0, j0 = np.floor(u).astype(int), np.floor(v).astype(int)
    fu, fv = u - i0, v - j0
    fu, fv = fu * fu * (3 - 2 * fu), fv * fv * (3 - 2 * fv)
    a = g[j0 % 64, i0 % 64] * (1 - fu) + g[j0 % 64, (i0 + 1) % 64] * fu
    b = g[(j0 + 1) % 64, i0 % 64] * (1 - fu) + g[(j0 + 1) % 64, (i0 + 1) % 64] * fu
    return a * (1 - fv) + b * fv


def road_gap(pts):
    return float(dist_to_center(np.array(pts, float)).min())


def rect_poly(cx, cz, ux, uz, ha, hb):
    fr = Frame((cx, cz), (ux, uz), (-uz, ux))
    return [tuple(fr.pt(a, b)) for a, b in ((-ha, -hb), (ha, -hb), (ha, hb), (-ha, hb))]


def edge_pts(poly_):
    out = list(poly_)
    for i in range(4):
        p, q = poly_[i], poly_[(i + 1) % 4]
        out.append(((p[0] + q[0]) / 2, (p[1] + q[1]) / 2))
    out.append((sum(p[0] for p in poly_) / 4, sum(p[1] for p in poly_) / 4))
    return out


QUIET = [0]


def try_place(cx, cz, ux, uz, ha, hb, margin=3.0, what=""):
    """Fläche reservieren: ausreichend Abstand zur Fahrbahn, keine Überschneidung mit Belegtem."""
    poly_ = rect_poly(cx, cz, ux, uz, ha, hb)
    if road_gap(edge_pts(poly_)) < HW + margin:
        if not QUIET[0]:
            print("DIORAMA fair: abgelehnt (Straße)", what, round(cx, 1), round(cz, 1))
        return False
    hit = next((q for q in placed if overlaps(poly_, q)), None)
    if hit is not None:
        if not QUIET[0]:
            print("DIORAMA fair: abgelehnt (belegt)", what, round(cx, 1), round(cz, 1), "von", round(sum(v[0] for v in hit) / 4, 1), round(sum(v[1] for v in hit) / 4, 1))
        return False
    placed.append(poly_)
    return True


def keep_out(cx, cz, ux, uz, ha, hb):
    placed.append(rect_poly(cx, cz, ux, uz, ha, hb))


def fence_rect():
    return x0 + FENCE_IN, x1 - FENCE_IN, z0 + FENCE_IN, z1 - FENCE_IN


def wood_col(name):
    return {"roh": lin("e9c08a"), "rot": lin("f0584a"), "blau": lin("5b88e6"), "gruen": lin("63c27a"), "gelb": lin("f5d24c"),
            "creme": lin("f4ebd2"), "rosa": lin("f58cb8"), "dunkel": lin("b07a4a"), "lila": lin("a56ac4"), "tuerkis": lin("55c2cf"),
            "weiss": lin("f3f1ea")}[name]


PAL = {"rot": lin("d63a2a"), "rot2": lin("a8231b"), "blau": lin("2d5fc4"), "gelb": lin("f2c21b"), "gruen": lin("2f9a4c"), "weiss": lin("f1ede2"),
       "creme": lin("e8dcb8"), "rosa": lin("ee6fa8"), "tuerkis": lin("1fa7b8"), "orange": lin("ee7d22"), "lila": lin("7a3a9a"),
       "schwarz": lin("17181a"), "grau": lin("8d9094"), "dgrau": lin("4a4d52"), "stahl": lin("aab0b8"), "braun": lin("6b4426"),
       "hellbraun": lin("c08a52"), "glas": lin("2a3a4a"), "gold": lin("d4a437")}


def bulb_key(rng_):
    r = rng_.random()
    if r < 0.40:
        return "k:ampel_gelb"
    if r < 0.68:
        return "k:lampe"
    if r < 0.82:
        return "k:ampel_rot"
    if r < 0.92:
        return "k:ampel_gruen"
    return "k:lampe_blau"


def bulb(x, z, y, key, s=0.09):
    fr = Frame((x, z), (1, 0), (0, 1))
    return cbox(fr, key, -s, s, -s, s, y - s, y + s, (1.0, 0.96, 0.85), grad=(1, 1))


def pole(x, z, h, r=0.07, col=None, obstacle=True):
    parts = cyl("k:farbe", x, z, r, GROUND_Y, GROUND_Y + h, 6, col or PAL["braun"], grad=(0.7, 1.0))
    if obstacle:
        collide_circle(x, z, r + 0.05, h, "mast")
    return parts


# ---------------------------------------------------------------- Besucher als kleine Figuren (statt Texturstreifen)
HUM_SKIN = [lin(c) for c in ("f3cfae", "e6b48c", "cf9a72", "a8714a", "7a4d30")]
HUM_HAIR = [lin(c) for c in ("1c1410", "3a2616", "6a4220", "b88a3c", "cfc4b0", "101010", "8a3a22", "d6b25a")]
HUM_TOP = [lin(c) for c in ("c9382c", "2d5fc4", "e8b81c", "2f9a4c", "e8791e", "e8689c", "7a3a9a", "1fa7b8", "efeae0", "3d4048", "9ac33a", "e8e04a")]
HUM_BOT = [lin(c) for c in ("2b3a5c", "1b1c20", "6e5d46", "8a8d92", "3a4d70", "4d3b2a", "d9d2c0")]
HQ = []                        # vorgemerkte Besucher (x, z, Blickrichtung, Kind, Sitzhöhe, sitzend, prüfen); flush_people() baut sie, wenn alles Feste steht
PLACED_BB = []                 # Begrenzungsrahmen der belegten Flächen (Cache für in_placed)
HUM_STATS = {"gebaut": 0, "abgelehnt": 0}


def in_placed(x, z):
    """Liegt der Punkt in einer belegten Fläche (Bude, Bank, Baum ...)? Besucher stehen nicht in Aufbauten."""
    while len(PLACED_BB) < len(placed):
        q = placed[len(PLACED_BB)]
        PLACED_BB.append((min(p[0] for p in q), max(p[0] for p in q), min(p[1] for p in q), max(p[1] for p in q), q))
    for (xa, xb, za, zb, q) in PLACED_BB:
        if xa <= x <= xb and za <= z <= zb:
            sg = 0
            inside_q = True
            for i in range(len(q)):
                ax, az = q[i]
                bx, bz = q[(i + 1) % len(q)]
                c = (bx - ax) * (z - az) - (bz - az) * (x - ax)
                if abs(c) > 1e-9:
                    s_ = 1 if c > 0 else -1
                    if sg == 0:
                        sg = s_
                    elif s_ != sg:
                        inside_q = False
                        break
            if inside_q:
                return True
    return False


def human(x, z, face_deg, kid=False, seated_y=None, hat=None, rng_=None, top=None):
    """Ein Besucher als Figur (etwa 60 Dreiecke): Hose, Oberteil, Arme, Kopf mit Haarkappe, manchmal Mütze; Kinder kleiner mit größerem Kopf.
    seated_y: Sitzhöhe (Bank): Oberschenkel waagerecht, Unterschenkel zum Boden."""
    r_ = rng_ or frng
    s = r_.uniform(0.60, 0.72) if kid else r_.uniform(0.94, 1.06)
    hs = 1.28 if kid else 1.0
    fr = frame_at(x, z, face_deg)
    P = FAIR
    top, bot = top or r_.choice(HUM_TOP), r_.choice(HUM_BOT)
    skin, hair = r_.choice(HUM_SKIN), r_.choice(HUM_HAIR)
    if seated_y is None:
        hy = GROUND_Y + 0.82 * s
        P += cbox(fr, "k:farbe", -0.08 * s, 0.08 * s, -0.15 * s, 0.15 * s, GROUND_Y, hy, bot, 1.0, grad=(0.7, 1.0), top=False)
    else:
        hy = seated_y + 0.1 * s
        P += cbox(fr, "k:farbe", 0.0, 0.46 * s, -0.15 * s, 0.15 * s, seated_y, seated_y + 0.16 * s, bot, 1.0, grad=(1, 1))
        P += cbox(fr, "k:farbe", 0.38 * s, 0.5 * s, -0.15 * s, 0.15 * s, GROUND_Y + 0.02, seated_y, bot, 1.0, grad=(0.7, 1.0), top=False)
    P += cbox(fr, "k:farbe", -0.115 * s, 0.115 * s, -0.215 * s, 0.215 * s, hy, hy + 0.6 * s, top, 1.0, grad=(0.82, 1.0))
    for sgn in (-1, 1):
        b0, b1 = (0.215 * s, 0.3 * s) if sgn > 0 else (-0.3 * s, -0.215 * s)
        P += cbox(fr, "k:farbe", -0.055 * s, 0.055 * s, b0, b1, hy - 0.08 * s, hy + 0.58 * s, shade(top, 0.92), 1.0, grad=(0.85, 1.0))
    yh = hy + 0.7 * s
    P += dome("k:farbe", x, z, yh, 0.105 * s * hs, 6, 2, skin, lat0=-0.45)
    P += dome("k:farbe", x, z, yh + 0.01 * s, 0.114 * s * hs, 6, 1, hair, lat0=0.25)
    if hat is None:
        hat = (not kid) and r_.random() < 0.18
    if hat:
        P += cyl("k:farbe", x, z, 0.12 * s * hs, yh + 0.07 * s, yh + 0.12 * s, 6, r_.choice(HUM_TOP), cap=True)


def kid_balloons(x, z, face_deg, n=3):
    """Kind mit Luftballons: Hand hebt die Schnur, bunte Ballons schweben darüber."""
    human(x, z, face_deg, kid=True, hat=False)
    br = random.Random(int(x * 7 + z * 3))
    f = math.radians(face_deg)
    hx_, hz_ = x - math.sin(f) * 0.2, z + math.cos(f) * 0.2
    for i in range(n):
        a = br.uniform(0, 6.28)
        d = br.uniform(0.05, 0.4)
        h = br.uniform(1.8, 2.5)
        bx_, bz_ = hx_ + math.cos(a) * d, hz_ + math.sin(a) * d
        c = lin(br.choice(["e8452c", "f7c52b", "3a8ae0", "3fb86a", "e86aa8", "ff8a2a", "a56ac4"]))
        FAIR.extend(dome("k:farbe", bx_, bz_, GROUND_Y + h, 0.24, 6, 2, c, lat0=-0.9))
        FAIR.append(poly("dunkel", [(hx_, hz_, GROUND_Y + 0.8), (hx_ + 0.012, hz_, GROUND_Y + 0.8), (bx_ + 0.012, bz_, GROUND_Y + h - 0.22), (bx_, bz_, GROUND_Y + h - 0.22)], None, None, 1.0,
                         [(0, 0), (1, 0), (1, 1), (0, 1)]))


def stroller(x, z, face_deg):
    """Kinderwagen (Gestell, Wanne, Verdeck, Schiebebügel) mit zwei Rädern vorn und hinten."""
    fr = frame_at(x, z, face_deg)
    y = GROUND_Y
    col = frng.choice([lin("2d5fc4"), lin("d63a2a"), lin("2f9a4c"), lin("3d4048"), lin("e8689c")])
    P = FAIR
    P += cbox(fr, "k:farbe", -0.4, 0.35, -0.2, 0.2, y + 0.3, y + 0.55, col, 1.0, grad=(0.8, 1.0))
    P += cbox(fr, "k:farbe", 0.0, 0.35, -0.2, 0.2, y + 0.55, y + 0.78, shade(col, 0.85), 1.0, grad=(0.9, 1.0))        # Verdeck
    P += cbox(fr, "k:farbe", -0.45, -0.4, -0.19, 0.19, y + 0.5, y + 0.95, PAL["stahl"], 1.0, grad=(1, 1))
    for a in (-0.3, 0.28):
        for sgn in (-1, 1):
            P += cbox(fr, "k:farbe", a - 0.08, a + 0.08, sgn * 0.23 - 0.02, sgn * 0.23 + 0.02, y, y + 0.18, PAL["schwarz"], 1.0, grad=(1, 1))


def person(x, z, face_deg, length=1.2, y=None, seated=False, guard=True, kid=None):
    """Ein bis zwei Besucher nebeneinander (ab Länge 1,5 zwei); gebaut wird erst in flush_people()."""
    n = 2 if length >= 1.5 else 1
    f = math.radians(face_deg)
    for k in range(n):
        off = (k - (n - 1) / 2) * 0.62
        HQ.append((x - math.sin(f) * off, z + math.cos(f) * off, face_deg + frng.uniform(-12, 12), kid, y if seated else None, seated, guard))


def people(x, z, n, spread, face_deg, jitter=60.0):
    """Gruppe verstreuter Besucher um (x, z), grob in dieselbe Richtung blickend."""
    for _ in range(n):
        a = frng.uniform(0, 2 * math.pi)
        r_ = spread * math.sqrt(frng.random())
        person(x + math.cos(a) * r_, z + math.sin(a) * r_, face_deg + frng.uniform(-jitter, jitter), frng.choice([0.9, 1.3, 1.7]))


def queue_line(p0, p1, n, face_deg=None, kids=0.2):
    """Warteschlange: Besucher hintereinander von p0 nach p1 (Blick in Laufrichtung)."""
    a, b = Vector(p0), Vector(p1)
    if face_deg is None:
        d_ = b - a
        face_deg = math.degrees(math.atan2(d_.y, d_.x))
    for i in range(n):
        q = a.lerp(b, (i + 0.5) / n)
        person(q.x + frng.uniform(-0.15, 0.15), q.y + frng.uniform(-0.15, 0.15), face_deg + frng.uniform(-10, 10), 0.95, kid=frng.random() < kids)


def family(x, z, face_deg):
    """Familie: zwei Erwachsene, ein bis zwei Kinder (eines mit Ballons), manchmal Kinderwagen."""
    f = math.radians(face_deg)
    fx, fz = math.cos(f), math.sin(f)
    px, pz = -fz, fx
    person(x + px * 0.5, z + pz * 0.5, face_deg, 0.9, kid=False)
    person(x - px * 0.5, z - pz * 0.5, face_deg + 8, 0.9, kid=False)
    person(x + fx * 0.8, z + fz * 0.8 + 0.1, face_deg + 12, 0.9, kid=True)
    BALLOON_KIDS.append((x - fx * 0.6 + px * 1.3, z - fz * 0.6 + pz * 1.3, face_deg + 20))
    if frng.random() < 0.3:
        STROLLERS.append((x - fx * 1.2, z - fz * 1.2, face_deg))


BALLOON_KIDS = []
STROLLERS = []


def flush_people(limit=560):
    """Alle vorgemerkten Besucher bauen: nicht in Aufbauten, nicht auf der Fahrbahn; bei zu vielen gleichmäßig ausdünnen."""
    ok = [h for h in HQ if not h[6] or not (in_placed(h[0], h[1]) or road_gap([(h[0], h[1])]) < HW + 0.9)]
    HUM_STATS["abgelehnt"] = len(HQ) - len(ok)
    step = max(1.0, len(ok) / float(limit))
    i = 0.0
    while int(i) < len(ok):
        x, z, face, kid, y, seated, _ = ok[int(i)]
        human(x, z, face, kid=(frng.random() < 0.2) if kid is None else kid, seated_y=y if seated else None)
        HUM_STATS["gebaut"] += 1
        i += step
    for (x, z, f) in BALLOON_KIDS:
        if not in_placed(x, z) and road_gap([(x, z)]) >= HW + 0.9:
            kid_balloons(x, z, f, frng.choice([2, 3, 3]))
            HUM_STATS["gebaut"] += 1
    for (x, z, f) in STROLLERS:
        if not in_placed(x, z) and road_gap([(x, z)]) >= HW + 0.9:
            stroller(x, z, f)


def barrier_panel(fr, a_c, length=2.2, y=None):
    """Absperrgitter (Fußgängerleitgitter): zwei Holme, Stäbe, zwei Bügelfüße."""
    y = GROUND_Y if y is None else y
    P = lambda a, b, yy: (*fr.pt(a, b), yy)
    parts = []
    col = PAL["stahl"]
    for a in (a_c - length / 2 + 0.1, a_c + length / 2 - 0.1):
        parts += cbox(fr, "k:farbe", a - 0.04, a + 0.04, -0.3, 0.3, y, y + 0.05, shade(col, 0.8), grad=(1, 1), sides=(1, 1, 0, 0))
    parts += cbox(fr, "k:farbe", a_c - length / 2, a_c + length / 2, -0.02, 0.02, y + 1.0, y + 1.06, col, grad=(1, 1), sides=(1, 1, 0, 0))
    parts += cbox(fr, "k:farbe", a_c - length / 2, a_c + length / 2, -0.02, 0.02, y + 0.28, y + 0.33, col, grad=(1, 1), sides=(1, 1, 0, 0))
    n = 8
    for k in range(n):
        a = a_c - length / 2 + 0.12 + k * (length - 0.24) / (n - 1)
        parts.append(poly("k:farbe", [P(a, 0, y + 0.05), P(a + 0.025, 0, y + 0.05), P(a + 0.025, 0, y + 1.0), P(a, 0, y + 1.0)], col, (fr.v.x, fr.v.y)))
    return parts


def barrier_line(path, spacing=2.2, collide=True, closed=False):
    """Absperrgitter entlang einer Polylinie; trägt weiche Hindernisse ein."""
    pts = [Vector(p) for p in path]
    segs = list(zip(pts, pts[1:] + ([pts[0]] if closed else [])))
    for a, b in segs:
        L = (b - a).length
        n = max(1, int(round(L / spacing)))
        t = (b - a).normalized()
        for i in range(n):
            mid = a + t * (L * (i + 0.5) / n)
            fr = Frame(mid, t, Vector((-t.y, t.x)))
            FAIR.extend(barrier_panel(fr, 0.0, L / n * 0.98))
            if collide:
                collide_rect(mid.x, mid.y, t.x, t.y, L / n / 2, 0.12, 1.1, "gitter")


def festoon(p0, p1, sag=0.5, step=0.9, bulbs=True, pennants=False, rng_=None, bulb_y=0.1, lights=True):
    """Girlande zwischen zwei Punkten (x, z, y): Kabel mit Glühbirnen oder Wimpeln."""
    r_ = rng_ or frng
    a, b = Vector(p0[:2]), Vector(p1[:2])
    L = (b - a).length
    n = max(2, int(L / step))
    t = (b - a).normalized()
    nrm = Vector((-t.y, t.x)) * 0.025
    pts = []
    for i in range(n + 1):
        s = i / n
        q = a.lerp(b, s)
        pts.append((q.x, q.y, p0[2] + (p1[2] - p0[2]) * s - sag * 4 * s * (1 - s)))
    for (x_, z_, y_), (x2, z2, y2) in zip(pts, pts[1:]):
        FAIR.append(poly("dunkel", [(x_ + nrm.x, z_ + nrm.y, y_), (x2 + nrm.x, z2 + nrm.y, y2), (x2 - nrm.x, z2 - nrm.y, y2), (x_ - nrm.x, z_ - nrm.y, y_)], None, None, 1.0,
                         [(0, 0), (1, 0), (1, 1), (0, 1)]))
    if bulbs:
        for (x_, z_, y_) in pts[1:-1]:
            FAIR.extend(bulb(x_, z_, y_ - bulb_y, bulb_key(r_)))
        if lights:
            for i in range(1, n, max(1, int(round(2.6 / step)))):
                (x_, z_, y_) = pts[i]
                add_light(x_, z_, y_ - bulb_y, FESTOON_COLS[int(abs(x_ * 0.37 + z_ * 0.53)) % len(FESTOON_COLS)], 0.17, 4.2, omni=False)
    if pennants:
        cols = [PAL["rot"], PAL["gelb"], PAL["blau"], PAL["weiss"], PAL["gruen"], PAL["orange"]]
        k = 0
        for (x_, z_, y_) in pts[1:-1]:
            half = Vector((t.x, t.y)) * 0.17
            facing = (nrm.x / 0.025, nrm.y / 0.025)
            FAIR.append(poly("k:farbe", [(x_ - half.x, z_ - half.y, y_), (x_ + half.x, z_ + half.y, y_), (x_, z_, y_ - 0.42)], cols[k % len(cols)], facing, 1.0,
                             [(0, 1), (1, 1), (0.5, 0)]))
            k += 1


# ---------------------------------------------------------------- Buden
STALL = {
    # kind: (Schild, Holzfarbe, Markise a, Markise b, Dachbelag, Dachfarbe, Dachform, Höhe, Zusatz)
    "pommes": ("pommes", "rot", "rot", "weiss", "k:dach_ziegel", None, "gable", 2.5, "schlot"),
    "wurst": ("wurst", "roh", "rot", "weiss", "k:dach_ziegel", None, "gable", 2.5, "schlot"),
    "zuckerwatte": ("zuckerwatte", "rosa", "rosa", "weiss", "k:farbe", "ee8fbd", "flat", 2.6, "watte"),
    "mandeln": ("mandeln", "dunkel", "braun", "creme", "k:dach_blech", None, "gable", 2.5, "schlot"),
    "crepes": ("crepes", "creme", "blau", "weiss", "k:dach_ziegel", None, "gable", 2.5, "schlot"),
    "eis": ("eis", "tuerkis", "tuerkis", "weiss", "k:farbe", "5fc9d6", "flat", 2.6, "eistuete"),
    "dosen": ("dosen", "blau", "gelb", "blau", "k:farbe", "3f6fd0", "flat", 2.7, "plueschseite"),
    "schiessen": ("schiessen", "gruen", "rot", "weiss", "k:farbe", "3fa05a", "flat", 2.7, "scheiben"),
    "enten": ("enten", "gelb", "blau", "weiss", "k:dach_ziegel", None, "gable", 2.5, "enten"),
    "los": ("los", "lila", "lila", "gelb", "k:farbe", "a36ac8", "flat", 2.7, "plueschseite"),
    "kasse": ("kasse", "rot", "rot", "weiss", "k:dach_ziegel", None, "gable", 2.5, "kasse"),
    "bier": ("bier", "dunkel", "rot2", "creme", "k:dach_blech", None, "gable", 2.6, "fass"),
}

STALL_LIGHT = {  # Lichtfarbe vor der Bude (linear): Birnen und Leuchtleiste färben den Boden vor der Theke
    "pommes": (1.0, 0.72, 0.38), "wurst": (1.0, 0.7, 0.36), "zuckerwatte": (1.0, 0.55, 0.78), "mandeln": (1.0, 0.68, 0.32), "crepes": (0.62, 0.78, 1.0),
    "eis": (0.55, 0.92, 1.0), "dosen": (0.6, 0.7, 1.0), "schiessen": (0.6, 1.0, 0.7), "enten": (1.0, 0.9, 0.5), "los": (0.92, 0.55, 1.0),
    "kasse": (1.0, 0.85, 0.6), "bier": (1.0, 0.8, 0.5),
}
FESTOON_COLS = [(1.0, 0.82, 0.55), (1.0, 0.6, 0.78), (0.65, 0.9, 1.0), (1.0, 0.9, 0.5), (0.7, 1.0, 0.72)]


def scallop_band(fr, a0, a1, b, y_top, drop, col_a, col_b, n=None, face=None, bumps=True):
    """Volant mit Zackenkante (Markisen- und Dachrand): senkrechtes Band bei b, Oberkante y_top, Länge der Zacken `drop`."""
    n = n or max(4, int(round((a1 - a0) / 0.3)))
    sw = (a1 - a0) / n
    face = face or (fr.v.x, fr.v.y)
    out = []
    for i in range(n):
        aa0, aa1 = a0 + i * sw, a0 + (i + 1) * sw
        am = (aa0 + aa1) / 2
        c = col_a if i % 2 == 0 else col_b
        if bumps:
            pts = [(*fr.pt(aa0, b), y_top), (*fr.pt(aa1, b), y_top), (*fr.pt(aa1, b), y_top - drop * 0.5), (*fr.pt(am, b), y_top - drop), (*fr.pt(aa0, b), y_top - drop * 0.5)]
            uv = [(0, 1), (1, 1), (1, 0.5), (0.5, 0), (0, 0.5)]
        else:
            pts = [(*fr.pt(aa0, b), y_top), (*fr.pt(aa1, b), y_top), (*fr.pt(aa1, b), y_top - drop), (*fr.pt(aa0, b), y_top - drop)]
            uv = [(0, 1), (1, 1), (1, 0), (0, 0)]
        out.append(poly("k:farbe", pts, c, face, 1.0, uv))
    return out


def stall(x, z, fx, fz, kind, w=4.0, d=3.0, sign=None, label=None):
    """Bude, Vorderseite (Theke, Markise, Schild) zeigt in Richtung (fx, fz); u liegt für den Betrachter vor der Bude rechts."""
    sc, wood, ma, mb, roof, roof_col, rform, h, extra = STALL[kind]
    n_ = math.hypot(fx, fz)
    fx, fz = fx / n_, fz / n_
    ux, uz = fz, -fx
    proj = 1.35
    if not try_place(x + fx * 0.75, z + fz * 0.75, ux, uz, w / 2 + 0.2, (d + proj + 0.2) / 2 + 0.3, margin=2.5, what="Bude " + kind):
        return False
    fr = Frame((x, z), (ux, uz), (fx, fz))
    hw, hd = w / 2, d / 2
    y0 = GROUND_Y
    wc = wood_col(wood)
    ca, cb = PAL[ma], PAL[mb]
    P = FAIR
    t_wall = 0.12
    P += cbox(fr, "k:farbe", -hw - 0.05, hw + 0.05, -hd - 0.05, hd + 0.05, y0, y0 + 0.16, shade(wc, 0.45), grad=(0.7, 1.0), top=False)       # Sockel
    P += cbox(fr, "f_planken", -hw, hw, -hd, -hd + t_wall, y0 + 0.16, y0 + h, wc, 1.28)                                                      # Rückwand
    P += cbox(fr, "f_planken", -hw, -hw + t_wall, -hd, hd, y0 + 0.16, y0 + h, wc, 1.28)                                                      # Seitenwände
    P += cbox(fr, "f_planken", hw - t_wall, hw, -hd, hd, y0 + 0.16, y0 + h, wc, 1.28)
    P += cbox(fr, "f_planken", -hw, hw, hd - t_wall, hd, y0 + 0.16, y0 + 1.0, wc, 1.28)                                                      # Brüstung
    P += cbox(fr, "f_planken", -hw, hw, hd - t_wall, hd, y0 + 2.12, y0 + h, wc, 1.28)                                                        # Sturz
    P.append(poly("dunkel", [(*fr.pt(-hw + t_wall, -hd + t_wall), y0 + 0.2), (*fr.pt(hw - t_wall, -hd + t_wall), y0 + 0.2),
                             (*fr.pt(hw - t_wall, hd - t_wall), y0 + 0.2), (*fr.pt(-hw + t_wall, hd - t_wall), y0 + 0.2)]))
    # Seitenwände: bemalte Füllung in der Akzentfarbe mit hellem Rahmen
    for sgn in (-1, 1):
        face = (fr.u.x * sgn, fr.u.y * sgn)
        a = sgn * (hw + 0.006)
        for (db, dy, cc) in ((0.35, 0.0, cb), (0.5, 0.15, ca)):
            P.append(poly("k:farbe", [(*fr.pt(a, -hd + db), y0 + 0.45 + dy), (*fr.pt(a, hd - db), y0 + 0.45 + dy), (*fr.pt(a, hd - db), y0 + h - 0.4 - dy), (*fr.pt(a, -hd + db), y0 + h - 0.4 - dy)],
                          cc, face, 1.0, [(0, 0), (1, 0), (1, 1), (0, 1)]))
    # Leuchtleiste unter dem Sturz (Lichtquelle) und Thekenbrett
    P += cbox(fr, "k:lampe", -hw + 0.3, hw - 0.3, hd - 0.2, hd - 0.14, y0 + 2.06, y0 + 2.1, (1.0, 0.95, 0.8), grad=(1, 1))
    P += cbox(fr, "f_planken", -hw - 0.08, hw + 0.08, hd - t_wall, hd + 0.55, y0 + 1.0, y0 + 1.07, shade(wc, 0.85), 1.28)
    # Dach
    y_e = y0 + h
    rc = lin(roof_col) if roof_col else (1, 1, 1)
    if rform == "gable":
        P += gable(fr, roof, -hw - 0.25, hw + 0.25, -hd - 0.3, hd + 0.4, y_e, y_e + 0.75, rc, 4.0, "a")
        P += cbox(fr, "k:farbe", -hw - 0.27, hw + 0.27, hd + 0.38, hd + 0.44, y_e - 0.12, y_e + 0.06, shade(wc, 0.7), grad=(1, 1), top=False, sides=(0, 1, 0, 0))   # Ortgang
        y_roof_front = y_e + 0.04
    else:
        P += cbox(fr, roof, -hw - 0.2, hw + 0.2, -hd - 0.2, hd + 0.4, y_e, y_e + 0.14, rc, 4.0, grad=(1, 1))
        for q in (-1, 1):                                                        # Spannleisten der Plane
            P += cbox(fr, "k:farbe", q * hw * 0.5 - 0.05, q * hw * 0.5 + 0.05, -hd - 0.2, hd + 0.4, y_e + 0.14, y_e + 0.17, shade(rc, 0.7), grad=(1, 1), sides=(0, 0, 0, 0))
        P += scallop_band(fr, -hw - 0.2, hw + 0.2, hd + 0.4, y_e + 0.14, 0.42, ca, cb, bumps=True)                       # Dachvolant vorn
        y_roof_front = y_e + 0.16
        for q in (-1, 1):                                                        # Fähnchen auf den Dachecken
            fcx, fcz = fr.pt(q * (hw + 0.1), -hd - 0.1)
            P += cyl("k:farbe", fcx, fcz, 0.025, y_e + 0.14, y_e + 1.3, 6, PAL["stahl"], cap=False)
            P.append(poly("k:farbe", [(fcx, fcz, y_e + 1.3), (fcx, fcz, y_e + 0.9), (*fr.pt(q * (hw + 0.1) + 0.5, -hd - 0.1), y_e + 1.1)], ca if q < 0 else cb, (fr.v.x, fr.v.y), 1.0, [(0, 1), (0, 0), (1, 0.5)]))
    # Markise: gestreifter Stoff, Zackenvolant, Leuchtleiste
    y_hi, y_lo = y_e - 0.15, y0 + 2.18
    b_in, b_out = hd + 0.06, hd + 0.06 + proj
    n_str = max(6, int(round((w + 0.3) / 0.3)))
    a_s = -hw - 0.15
    sw = (w + 0.3) / n_str
    for i in range(n_str):
        aa0, aa1 = a_s + i * sw, a_s + (i + 1) * sw
        c = ca if i % 2 == 0 else cb
        P.append(poly("k:farbe", [(*fr.pt(aa0, b_in), y_hi), (*fr.pt(aa1, b_in), y_hi), (*fr.pt(aa1, b_out), y_lo), (*fr.pt(aa0, b_out), y_lo)], c, (fx, fz), 1.0,
                      [(0, 0), (1, 0), (1, 1), (0, 1)]))
    P += scallop_band(fr, a_s, a_s + w + 0.3, b_out, y_lo, 0.27, ca, cb, n=n_str, bumps=True)
    P += cbox(fr, "k:lampe", -hw + 0.1, hw - 0.1, b_out - 0.2, b_out - 0.15, y_lo - 0.06, y_lo - 0.02, (1.0, 0.95, 0.8), grad=(1, 1))
    for a in (-hw - 0.05, hw + 0.05):
        q = fr.pt(a, b_out - 0.04)
        P += cyl("k:farbe", q.x, q.y, 0.035, y0, y_lo, 6, PAL["hellbraun"], cap=False)
    # Glühbirnen an Volant und Dachkante
    n_b = int(w / 0.42) + 1
    for i in range(n_b):
        a = -hw + 0.1 + i * (w - 0.2) / max(1, n_b - 1)
        q = fr.pt(a, b_out + 0.02)
        P += bulb(q.x, q.y, y_lo - 0.34, bulb_key(frng), 0.08)
        q = fr.pt(a, hd + 0.46)
        P += bulb(q.x, q.y, y_roof_front + 0.1, bulb_key(frng), 0.07)
    # Schild: geneigt (liest sich auch von oben), Leuchtbirnen rundum
    cell = SIGN_CELL[sign or sc]
    cu0, cu1 = (cell % 4) / 4.0 + 0.004, (cell % 4 + 1) / 4.0 - 0.004
    cv1, cv0 = 1.0 - (cell // 4) / 4.0 - 0.006, 1.0 - (cell // 4 + 1) / 4.0 + 0.006
    sw_, sh_ = min(w * 0.92, 3.9), 0.95 if rform == "gable" else 1.1
    y_s = y_roof_front + 0.1
    b_s = hd + 0.3
    lean = 0.55
    sa0, sa1 = -sw_ / 2, sw_ / 2
    P.append(("f_schild", [(*fr.pt(sa0, b_s), y_s), (*fr.pt(sa1, b_s), y_s), (*fr.pt(sa1, b_s - lean), y_s + sh_), (*fr.pt(sa0, b_s - lean), y_s + sh_)],
              [(cu0, cv0), (cu1, cv0), (cu1, cv1), (cu0, cv1)], (fx, fz), [(1, 1, 1)] * 4))
    n_s = int(sw_ / 0.4) + 1
    for i in range(n_s):
        a = sa0 + 0.05 + i * (sw_ - 0.1) / max(1, n_s - 1)
        q = fr.pt(a, b_s - lean - 0.04)
        P += bulb(q.x, q.y, y_s + sh_ + 0.06, bulb_key(frng), 0.065)
    for sgn in (-1, 1):
        for qq in (0.33, 0.66):
            q = fr.pt(sgn * sw_ / 2, b_s - lean * qq - 0.02)
            P += bulb(q.x, q.y, y_s + sh_ * qq, bulb_key(frng), 0.065)
    # Licht der Bude: Birnen und Leuchtleiste vor der Markise (die Bude selbst bleibt ein beleuchteter Körper)
    cl = STALL_LIGHT.get(kind, (1.0, 0.78, 0.45))
    for aa in ((0.0,) if w < 4.3 else (-w * 0.25, w * 0.25)):
        q = fr.pt(aa, b_out + 0.35)
        add_light(q.x, q.y, 2.2, cl, 0.34 if w < 4.3 else 0.26, 5.6, omni=False)
    # Zusatz
    counter_y = y0 + 1.07
    pr = random.Random(int(x * 13 + z * 7))
    if extra == "schlot":
        q = fr.pt(-hw * 0.5, -hd * 0.4)
        P += cyl("k:farbe", q.x, q.y, 0.16, y_e + 0.4, y_e + 1.3, 8, PAL["dgrau"], cap=True)
        P += cbox(fr, "k:farbe", hw * 0.2, hw * 0.2 + 0.7, -hd * 0.6, -hd * 0.6 + 0.5, y_e + 0.5, y_e + 0.62, PAL["stahl"], grad=(1, 1))
    elif extra == "watte":
        for i in range(7):
            a = -hw + 0.55 + i * (w - 1.1) / 6
            q = fr.pt(a, hd + 0.2)
            P += dome("k:farbe", q.x, q.y, counter_y + 0.2, 0.2, 8, 2, PAL["rosa"] if i % 2 == 0 else lin("8fd3f4"), lat0=-0.5)
        for i in range(5):
            a = -hw + 0.5 + i * (w - 1.0) / 4
            q = fr.pt(a, b_out - 0.15)
            P += dome("k:farbe", q.x, q.y, y_lo - 0.62, 0.22, 8, 2, PAL["rosa"] if i % 2 == 0 else lin("8fd3f4"), lat0=-0.6)
    elif extra == "eistuete":
        c_ = fr.pt(hw - 0.6, 0.0)
        P += cyl("k:farbe", c_.x, c_.y, 0.34, y_e + 0.2, y_e + 1.4, 8, lin("e0a860"), r_top=0.02, cap=False)
        P += dome("k:farbe", c_.x, c_.y, y_e + 1.4, 0.46, 10, 3, lin("f6a8c8"), lat0=-0.3)
        P += dome("k:farbe", c_.x, c_.y, y_e + 1.93, 0.34, 8, 2, lin("fff3d6"), lat0=-0.2)
    elif extra == "plueschseite":
        for sgn in (-1, 1):
            for j in range(5):
                for k2 in range(2):
                    q = fr.pt(sgn * (hw + 0.2 + k2 * 0.24), -hd + 0.4 + j * 0.55)
                    P += dome("k:farbe", q.x, q.y, y0 + 0.7 + 0.35 * (j % 3), 0.2, 8, 2, lin(pr.choice(["f58cb8", "ffd23a", "6fc3f5", "ff7b4a", "a98ae0", "7ad07a"])), lat0=-0.7)
        for j in range(5):                                         # Dosenpyramide / Preise hinter der Theke
            for k2 in range(5 - j):
                q = fr.pt(-0.6 + j * 0.15 + k2 * 0.3, -hd + 0.5)
                P += cyl("k:farbe", q.x, q.y, 0.11, y0 + 1.1 + j * 0.2, y0 + 1.3 + j * 0.2, 6, lin(pr.choice(["e03a3a", "f5d24c", "4a8ae0"])))
        for i in range(4):                                         # Plüschtiere an der Dachkante
            q = fr.pt(-hw + 0.5 + i * (w - 1.0) / 3, -hd + 0.3)
            P += dome("k:farbe", q.x, q.y, y_e + 0.14 + 0.25, 0.26, 8, 2, lin(pr.choice(["f58cb8", "ffd23a", "6fc3f5", "ff7b4a", "a98ae0", "7ad07a"])), lat0=-0.6)
    elif extra == "scheiben":
        for i in range(4):                                         # Zielscheiben (rot-weiß) am Sturz
            a = -hw + 0.55 + i * (w - 1.1) / 3
            for k_, (rr, cc) in enumerate(((0.26, PAL["weiss"]), (0.19, PAL["rot"]), (0.1, PAL["weiss"]), (0.04, PAL["rot"]))):
                bb = hd + 0.004 + 0.002 * k_
                P.append(poly("k:farbe", [(*fr.pt(a - rr, bb), y0 + 2.34 - rr), (*fr.pt(a + rr, bb), y0 + 2.34 - rr), (*fr.pt(a + rr, bb), y0 + 2.34 + rr), (*fr.pt(a - rr, bb), y0 + 2.34 + rr)],
                              cc, (fx, fz)))
    elif extra == "enten":
        # Wasserbecken vor der Bude mit Plastikenten
        pc = fr.pt(0.0, b_out + 0.9)
        pf = Frame(pc, fr.u, fr.v)
        P += cbox(pf, "k:farbe", -1.5, 1.5, -0.8, 0.8, y0, y0 + 0.5, lin("3a7bd5"), grad=(0.7, 1.0), top=False)
        P.append(poly("wasser", [(*pf.pt(-1.42, -0.72), y0 + 0.42), (*pf.pt(1.42, -0.72), y0 + 0.42), (*pf.pt(1.42, 0.72), y0 + 0.42), (*pf.pt(-1.42, 0.72), y0 + 0.42)]))
        P += cbox(pf, "k:farbe", -1.5, 1.5, -0.8, -0.72, y0 + 0.5, y0 + 0.56, lin("3a7bd5"), grad=(1, 1))
        for i in range(9):
            e_ = pf.pt(pr.uniform(-1.2, 1.2), pr.uniform(-0.55, 0.55))
            P += dome("k:farbe", e_.x, e_.y, y0 + 0.42, 0.11, 6, 2, lin("ffd21f"), lat0=-0.1)
            P += cbox(Frame((e_.x, e_.y), (1, 0), (0, 1)), "k:farbe", 0.08, 0.17, -0.025, 0.025, y0 + 0.43, y0 + 0.47, lin("ff7a1a"), grad=(1, 1))
        collide_rect(pc.x, pc.y, fr.u.x, fr.u.y, 1.5, 0.8, 0.6, "bank")
    elif extra == "fass":
        for i in range(3):
            q = fr.pt(-hw + 0.6 + i * 0.8, -hd - 0.45)
            P += cyl("k:farbe", q.x, q.y, 0.32, y0, y0 + 0.75, 10, PAL["hellbraun"], r_top=0.3)
            P += cyl("k:farbe", q.x, q.y, 0.325, y0 + 0.2, y0 + 0.26, 10, PAL["stahl"], cap=False)
            P += cyl("k:farbe", q.x, q.y, 0.325, y0 + 0.5, y0 + 0.56, 10, PAL["stahl"], cap=False)
    elif extra == "kasse":
        P += cbox(fr, "k:farbe", -hw * 0.6, hw * 0.6, hd - 0.14, hd - 0.05, y0 + 1.07, y0 + 1.12, PAL["weiss"], grad=(1, 1))
    # Theke: ein paar Waren
    cr = random.Random(int(x * 3 + z * 11))
    for i in range(6):
        a = -hw + 0.5 + i * (w - 1.0) / 5
        P += cbox(fr, "k:farbe", a - 0.14, a + 0.14, hd + 0.05, hd + 0.35, counter_y, counter_y + 0.12 + 0.1 * cr.random(),
                  lin(cr.choice(["e03a3a", "f5d24c", "ffffff", "6bb8f5", "ff9a3a"])), grad=(1, 1))
    # Gasflasche hinter der Bude
    if extra in ("schlot", "watte", "fass"):
        q = fr.pt(hw * 0.5, -hd - 0.35)
        P += cyl("k:farbe", q.x, q.y, 0.15, y0, y0 + 0.62, 8, lin("c9d3dc") if extra == "schlot" else lin("d86a1e"))
    q = fr.pt(0.0, 0.1)
    collide_rect(q.x, q.y, fr.u.x, fr.u.y, hw + 0.1, hd + 0.45, 3.0, "mauer")
    light_blockers.append([round(x, 3), round(z, 3), round(hw + 0.05, 3), round(hd + 0.05, 3), round(math.atan2(uz, ux), 4)])
    # Kunden vor der Theke
    kr = random.Random(int(x * 5 + z * 3))
    if kr.random() < 0.9:
        q = fr.pt(kr.uniform(-hw * 0.5, hw * 0.5), b_out + 0.45 + (1.9 if extra == "enten" else 0.0))
        people(q.x, q.y, kr.choice([2, 3, 4]), 0.9, math.degrees(math.atan2(-fz, -fx)), 35)
    return True


frng = random.Random(77)


def near(fn, x, z, *args, r_max=3.2, **kw):
    """Ruft fn(x, z, ...) an (x, z) auf; gelingt es nicht (belegt/zu nah an der Straße), wird in Ringen bis r_max herum die nächste freie Stelle probiert."""
    for r in (0.0, 0.9, 1.8, 2.7, 3.6):
        if r > r_max:
            break
        for k in range(1 if r == 0.0 else 8):
            ang = k * math.pi / 4 + 0.3
            QUIET[0] = 1
            ok = fn(x + r * math.cos(ang), z + r * math.sin(ang), *args, **kw)
            QUIET[0] = 0
            if ok:
                return True
    print("DIORAMA fair: keine freie Stelle für", getattr(fn, "__name__", fn), round(x, 1), round(z, 1))
    return False


def stall_try(kind, spots, w=3.8, d=3.0, sign=None):
    """Bude an der ersten passenden Stelle der Liste [(x, z, fx, fz), ...] bauen."""
    for i, (x, z, fx, fz) in enumerate(spots):
        QUIET[0] = 1 if i < len(spots) - 1 else 0
        ok = stall(x, z, fx, fz, kind, w=w, d=d, sign=sign)
        QUIET[0] = 0
        if ok:
            return True
    return False


def crowd_at(x, z, face_deg, length=3.0, rows=2, y=None):
    """Gäste auf einer Bank (Sitzhöhe y), ein bis zwei nebeneinander."""
    person(x, z, face_deg, length, y=y, seated=True, guard=False)


# ---------------------------------------------------------------- Möbel und Kleinteile
def bench(x, z, ang_deg):
    """Parkbank (1,6 m): Sitzbretter, Rückenlehne, zwei Seitenteile aus Gusseisen."""
    fr = frame_at(x, z, ang_deg)
    if not try_place(x, z, fr.u.x, fr.u.y, 0.95, 0.5, margin=2.2, what="Bank"):
        return False
    y = GROUND_Y
    wood = lin("a8703c")
    P = FAIR
    P += cbox(fr, "k:farbe", -0.8, 0.8, -0.2, 0.2, y + 0.43, y + 0.47, wood, grad=(1, 1))
    P += cbox(fr, "k:farbe", -0.8, 0.8, -0.24, -0.2, y + 0.55, y + 0.88, wood, grad=(0.8, 1.0))
    for a in (-0.7, 0.7):
        P += cbox(fr, "k:farbe", a - 0.03, a + 0.03, -0.22, 0.2, y, y + 0.43, PAL["dgrau"], grad=(0.8, 1.0))
        P += cbox(fr, "k:farbe", a - 0.03, a + 0.03, -0.26, -0.22, y, y + 0.9, PAL["dgrau"], grad=(0.8, 1.0))
    collide_rect(x, z, fr.u.x, fr.u.y, 0.85, 0.28, 0.9, "bank")
    return True


def bin_(x, z, col=None):
    if not try_place(x, z, 1, 0, 0.45, 0.45, margin=1.8, what="Eimer"):
        return False
    P = FAIR
    P += cyl("k:farbe", x, z, 0.27, GROUND_Y, GROUND_Y + 0.95, 10, col or lin("2f6f4a"), r_top=0.25, grad=(0.7, 1.0))
    P += cyl("k:farbe", x, z, 0.29, GROUND_Y + 0.9, GROUND_Y + 0.99, 10, PAL["dgrau"], cap=True)
    collide_circle(x, z, 0.3, 0.95, "mast")
    return True


def table_set(x, z, ang_deg, tw=2.2, sitters=True):
    """Bierzeltgarnitur: Tisch mit zwei Bänken; auf den Bänken sitzen Gäste."""
    fr = frame_at(x, z, ang_deg)
    if not try_place(x, z, fr.u.x, fr.u.y, tw / 2 + 0.1, 1.0, margin=2.5, what="Tisch"):
        return False
    y = GROUND_Y
    P = FAIR
    P += cbox(fr, "k:farbe", -tw / 2, tw / 2, -0.35, 0.35, y + 0.74, y + 0.78, lin("d9b88a"), grad=(1, 1))
    for a in (-tw / 2 + 0.3, tw / 2 - 0.3):
        P += cbox(fr, "k:farbe", a - 0.03, a + 0.03, -0.3, 0.3, y, y + 0.74, PAL["dgrau"], grad=(0.7, 1.0))
        for sgn in (-1, 1):
            P += cbox(fr, "k:farbe", a - 0.03, a + 0.03, sgn * 0.62 - 0.12, sgn * 0.62 + 0.12, y, y + 0.43, PAL["dgrau"], grad=(0.7, 1.0), top=False)
    for sgn in (-1, 1):
        P += cbox(fr, "k:farbe", -tw / 2, tw / 2, sgn * 0.62 - 0.13, sgn * 0.62 + 0.13, y + 0.43, y + 0.47, lin("c9a273"), grad=(1, 1))
        if sitters and frng.random() < 0.75:
            c = fr.pt(frng.uniform(-0.4, 0.4), sgn * 0.62)
            crowd_at(c.x, c.y, math.degrees(math.atan2(-sgn * fr.v.y, -sgn * fr.v.x)), frng.uniform(1.2, 2.0), 1, y + 0.52)
    P += cbox(fr, "k:farbe", -0.12, 0.12, -0.08, 0.08, y + 0.78, y + 0.98, lin("e8e6df"), grad=(1, 1))   # Krug
    collide_rect(x, z, fr.u.x, fr.u.y, tw / 2, 0.75, 0.8, "bank")
    return True


def flower_bed(x, z, r=1.1):
    """Blumenbeet mit Steineinfassung, grünem Laub und bunten Blüten."""
    if not try_place(x, z, 1, 0, r + 0.2, r + 0.2, margin=2.0, what="Beet"):
        return False
    P = FAIR
    P += cyl("k:farbe", x, z, r, GROUND_Y, GROUND_Y + 0.4, 14, lin("c4bcad"), grad=(0.75, 1.0), cap=False)
    P += cyl("k:farbe", x, z, r - 0.12, GROUND_Y, GROUND_Y + 0.3, 14, lin("4a3322"), cap=True)
    for i in range(7):
        a = 2 * math.pi * i / 7
        P += dome("k:farbe", x + math.cos(a) * r * 0.45, z + math.sin(a) * r * 0.45, GROUND_Y + 0.28, r * 0.36, 7, 2, lin(frng.choice(["3a8a3a", "2f7a35", "4a9a40"])), lat0=-0.2)
    P += dome("k:farbe", x, z, GROUND_Y + 0.28, r * 0.42, 7, 2, lin("3a8a3a"), lat0=-0.2)
    for i in range(26):
        a = frng.uniform(0, 6.28)
        d = frng.uniform(0, r - 0.3)
        P += dome("k:farbe", x + math.cos(a) * d, z + math.sin(a) * d, GROUND_Y + 0.5 + 0.1 * (1 - d / r), 0.15, 5, 1, lin(frng.choice(["e8452c", "f7c52b", "e86aa8", "ffffff", "9a5ad0", "ff8a2a"])), lat0=-0.2)
    collide_circle(x, z, r + 0.05, 0.45, "mauer")
    return True


def flag_pole(x, z, color, h=6.5, ang=0.0, length=1.5, height=1.0):
    """Fahnenmast mit wehender Fahne (E_flagge, Shader bewegt die Fläche)."""
    if not try_place(x, z, 1, 0, 0.5, 0.5, margin=1.8, what="Fahne"):
        return False
    FAIR.extend(cyl("k:farbe", x, z, 0.05, GROUND_Y, GROUND_Y + h, 6, PAL["stahl"]))
    u = Vector((math.cos(ang), math.sin(ang)))
    n = 4
    for k in range(n):
        a0, a1 = 0.04 + k * length / n, 0.04 + (k + 1) * length / n
        p0, p1 = Vector((x, z)) + u * a0, Vector((x, z)) + u * a1
        FAIR.append(("e:flagge", [(p0.x, p0.y, GROUND_Y + h - height), (p1.x, p1.y, GROUND_Y + h - height), (p1.x, p1.y, GROUND_Y + h), (p0.x, p0.y, GROUND_Y + h)],
                     [(k / n, 0.0), ((k + 1) / n, 0.0), ((k + 1) / n, 1.0), (k / n, 1.0)], None, [color] * 4))
    collide_circle(x, z, 0.12, h, "mast")
    return True


def bush(x, z, r=0.9):
    """Strauch (grüne Kuppel, zwei Töne)."""
    c = lin(frng.choice(["3f7a3a", "4b8a40", "356b34"]))
    FAIR.extend(dome("k:farbe", x, z, GROUND_Y + r * 0.25, r, 9, 3, c, lat0=-0.5, cols_alt=shade(c, 0.82)))


def hedge(path, width=0.9, h=1.1):
    """Hecke entlang einer Polylinie (Quader mit gestuften Höhen)."""
    pts = resample_path(path, 1.6)
    for a, b in zip(pts, pts[1:]):
        t = (b - a)
        if t.length < 0.1:
            continue
        t.normalize()
        fr = Frame((a + b) / 2, t, Vector((-t.y, t.x)))
        L = (b - a).length
        hh = h * frng.uniform(0.9, 1.1)
        FAIR.extend(cbox(fr, "k:farbe", -L / 2 - 0.05, L / 2 + 0.05, -width / 2, width / 2, GROUND_Y, GROUND_Y + hh, lin(frng.choice(["3b7a38", "34703a", "42823d"])), grad=(0.65, 1.0)))
        mid = (a + b) / 2
        collide_rect(mid.x, mid.y, t.x, t.y, L / 2, width / 2, hh, "gitter")


def balloons(x, z, n=14):
    """Luftballonstrauß (Händler): bunte Kugeln an Schnüren."""
    P = FAIR
    br = random.Random(int(x * 3 + z))
    for i in range(n):
        a = br.uniform(0, 6.28)
        d = br.uniform(0.0, 0.7)
        h = br.uniform(2.2, 3.4)
        cx_, cz_ = x + math.cos(a) * d, z + math.sin(a) * d
        c = lin(br.choice(["e8452c", "f7c52b", "3a8ae0", "3fb86a", "e86aa8", "ff8a2a", "a56ac4"]))
        P += dome("k:farbe", cx_, cz_, GROUND_Y + h, 0.28, 8, 3, c, lat0=-0.9)
        P.append(poly("dunkel", [(x, z, GROUND_Y + 1.2), (x + 0.012, z, GROUND_Y + 1.2), (cx_ + 0.012, cz_, GROUND_Y + h - 0.2), (cx_, cz_, GROUND_Y + h - 0.2)], None, None, 1.0,
                      [(0, 0), (1, 0), (1, 1), (0, 1)]))


def caravan(x, z, ang_deg, stripe="blau"):
    """Wohnwagen der Schausteller (6,2 m, Deichsel zeigt nach +u): Aufbau, Dachwölbung, Fenster, Tür, Zierstreifen, Achse mit Rädern längs der
    Fahrtrichtung, Deichsel mit Stützrad."""
    fr = frame_at(x, z, ang_deg)
    c0 = fr.pt(0.9, 0)
    if not try_place(c0.x, c0.y, fr.u.x, fr.u.y, 4.1, 1.45, margin=3.0, what="Wohnwagen"):
        return False
    y = GROUND_Y
    P = FAIR
    lit = frng.random() < 0.55                                # Licht im Wohnwagen: leuchtende Fenster und Schein vor der Tür
    if lit:
        q = fr.pt(0.6, 2.2)
        add_light(q.x, q.y, 1.8, (1.0, 0.78, 0.48), 0.3, 4.6, omni=False)
    body = lin("ece8dc")
    P += cbox(fr, "k:farbe", -3.1, 3.1, -1.15, 1.15, y + 0.6, y + 2.35, body, grad=(0.78, 1.0))
    P += cbox(fr, "k:farbe", -3.0, 3.0, -1.1, 1.1, y + 0.42, y + 0.62, PAL["dgrau"], grad=(0.8, 1.0), top=False)
    P += gable(fr, "k:farbe", -3.1, 3.1, -1.15, 1.15, y + 2.35, y + 2.7, lin("f4f1e8"), 4.0, "a")
    P += cbox(fr, "k:farbe", 0.3, 1.3, -0.3, 0.3, y + 2.62, y + 2.78, lin("c9ccd2"), grad=(1, 1))             # Dachluke
    for sgn in (-1, 1):
        face = (fr.v.x * sgn, fr.v.y * sgn)
        b = sgn * 1.165
        P.append(poly("k:farbe", [(*fr.pt(-3.08, b), y + 1.15), (*fr.pt(3.08, b), y + 1.15), (*fr.pt(3.08, b), y + 1.5), (*fr.pt(-3.08, b), y + 1.5)], PAL[stripe], face))
        for a0, a1 in ((-2.4, -1.1), (0.4, 1.7)):
            P.append(poly("k:lampe" if lit else "k:farbe", [(*fr.pt(a0, b * 1.001), y + 1.6), (*fr.pt(a1, b * 1.001), y + 1.6), (*fr.pt(a1, b * 1.001), y + 2.1), (*fr.pt(a0, b * 1.001), y + 2.1)],
                          (1.0, 0.92, 0.75) if lit else PAL["glas"], face))
    # Tür auf der +v-Seite
    vf = (fr.v.x, fr.v.y)
    P.append(poly("k:farbe", [(*fr.pt(1.95, 1.168), y + 0.7), (*fr.pt(2.85, 1.168), y + 0.7), (*fr.pt(2.85, 1.168), y + 2.2), (*fr.pt(1.95, 1.168), y + 2.2)], lin("d7d2c4"), vf))
    P.append(poly("k:farbe", [(*fr.pt(2.1, 1.17), y + 1.4), (*fr.pt(2.7, 1.17), y + 1.4), (*fr.pt(2.7, 1.17), y + 2.05), (*fr.pt(2.1, 1.17), y + 2.05)], PAL["glas"], vf))
    P += cbox(fr, "k:farbe", 2.0, 2.8, 1.15, 1.5, y + 0.45, y + 0.5, PAL["dgrau"], grad=(1, 1), top=True, sides=(0, 0, 0, 0))     # Trittstufe
    # Räder (Achse nahe der Mitte), Stützen, Deichsel
    for sgn in (-1, 1):
        b0, b1 = (1.0, 1.2) if sgn > 0 else (-1.2, -1.0)
        P += cbox(fr, "k:farbe", -0.35, 0.35, b0, b1, y, y + 0.7, PAL["schwarz"], grad=(0.8, 1.0))
        for sa in (-1, 1):
            P += cbox(fr, "k:farbe", sa * 2.75 - 0.06, sa * 2.75 + 0.06, sgn * 0.95 - 0.06, sgn * 0.95 + 0.06, y, y + 0.5, PAL["dgrau"], grad=(0.8, 1.0))
        P.append(poly("k:farbe", [(*fr.pt(3.1, sgn * 0.8), y + 0.62), (*fr.pt(3.1, sgn * 0.7), y + 0.62), (*fr.pt(4.5, sgn * 0.06), y + 0.62), (*fr.pt(4.5, sgn * 0.0), y + 0.62)],
                      PAL["dgrau"], None))
    P += cbox(fr, "k:farbe", 4.35, 4.7, -0.1, 0.1, y + 0.58, y + 0.7, PAL["dgrau"], grad=(1, 1))
    q = fr.pt(4.0, 0.0)
    P += cyl("k:farbe", q.x, q.y, 0.1, y, y + 0.6, 6, PAL["schwarz"])
    q = fr.pt(2.4, 1.3)
    P += bulb(q.x, q.y, y + 2.45, "k:lampe", 0.07)                                  # Türlampe
    q = fr.pt(0.7, 0.0)
    collide_rect(q.x, q.y, fr.u.x, fr.u.y, 3.9, 1.2, 2.6, "mauer")
    return True


def truck(x, z, ang_deg, kind="generator"):
    """Schaustellerfahrzeug (Zugmaschine mit Koffer / Stromaggregat), Front zeigt nach +u; drei Achsen, Räder längs."""
    fr = frame_at(x, z, ang_deg)
    if not try_place(x, z, fr.u.x, fr.u.y, 4.6, 1.6, margin=3.0, what="LKW"):
        return False
    y = GROUND_Y
    P = FAIR
    box_col = lin("eceae2") if kind == "generator" else lin("c0392b")
    P += cbox(fr, "k:farbe", -4.4, 2.3, -1.25, 1.25, y + 0.95, y + 3.2, box_col, grad=(0.8, 1.0))                 # Koffer
    P += cbox(fr, "k:farbe", -4.4, 4.3, -1.05, 1.05, y + 0.55, y + 0.95, PAL["dgrau"], grad=(0.8, 1.0), top=False)  # Fahrgestell
    P += cbox(fr, "k:farbe", 2.4, 4.2, -1.2, 1.2, y + 0.95, y + 2.55, lin("2a58b0"), grad=(0.8, 1.0))            # Fahrerhaus
    P.append(poly("k:farbe", [(*fr.pt(4.21, -1.0), y + 1.55), (*fr.pt(4.21, 1.0), y + 1.55), (*fr.pt(4.21, 1.0), y + 2.4), (*fr.pt(4.21, -1.0), y + 2.4)], PAL["glas"], (fr.u.x, fr.u.y)))
    P += cbox(fr, "k:farbe", 4.2, 4.5, -1.1, 1.1, y + 0.55, y + 1.0, PAL["dgrau"], grad=(1, 1))                  # Stoßstange
    for sgn in (-1, 1):
        face = (fr.v.x * sgn, fr.v.y * sgn)
        P.append(poly("k:farbe", [(*fr.pt(2.6, sgn * 1.21), y + 1.6), (*fr.pt(3.6, sgn * 1.21), y + 1.6), (*fr.pt(3.6, sgn * 1.21), y + 2.4), (*fr.pt(2.6, sgn * 1.21), y + 2.4)],
                      PAL["glas"], face))
        b0, b1 = (1.0, 1.25) if sgn > 0 else (-1.25, -1.0)
        for a in (3.3, -0.9, -2.5):
            P += cbox(fr, "k:farbe", a - 0.5, a + 0.5, b0, b1, y, y + 1.0, PAL["schwarz"], grad=(0.8, 1.0))
    if kind == "generator":
        for sgn in (-1, 1):
            face = (fr.v.x * sgn, fr.v.y * sgn)
            for a in (-3.6, -2.2, -0.8, 0.6):
                P.append(poly("k:farbe", [(*fr.pt(a, sgn * 1.26), y + 1.5), (*fr.pt(a + 1.1, sgn * 1.26), y + 1.5), (*fr.pt(a + 1.1, sgn * 1.26), y + 2.6), (*fr.pt(a, sgn * 1.26), y + 2.6)],
                              PAL["dgrau"], face))
        q = fr.pt(2.0, 0.9)
        P += cyl("k:farbe", q.x, q.y, 0.12, y + 3.2, y + 4.2, 8, PAL["dgrau"])
        P += cbox(fr, "k:farbe", -2.0, 1.6, -0.6, 0.6, y + 3.2, y + 3.35, lin("b5b8be"), grad=(1, 1))
    else:
        for a in (-3.6, -1.0):
            P.append(poly("k:farbe", [(*fr.pt(a, 1.26), y + 1.5), (*fr.pt(a + 1.8, 1.26), y + 1.5), (*fr.pt(a + 1.8, 1.26), y + 2.8), (*fr.pt(a, 1.26), y + 2.8)],
                          lin("e8c26a"), (fr.v.x, fr.v.y)))
    collide_rect(x, z, fr.u.x, fr.u.y, 4.5, 1.3, 3.2, "mauer")
    return True


def container(x, z, ang_deg, col=None):
    fr = frame_at(x, z, ang_deg)
    if not try_place(x, z, fr.u.x, fr.u.y, 3.1, 1.3, margin=3.0, what="Container"):
        return False
    y = GROUND_Y
    c = col or lin(frng.choice(["2f5f9a", "9a3b2f", "3d7a4f", "b8892a"]))
    FAIR.extend(cbox(fr, "k:farbe", -3.0, 3.0, -1.2, 1.2, y + 0.05, y + 2.6, c, grad=(0.75, 1.0), top=False))
    FAIR.extend(cbox(fr, "k:dach_blech", -3.0, 3.0, -1.2, 1.2, y + 2.6, y + 2.64, (0.8, 0.8, 0.8), 4.0, grad=(1, 1), sides=(0, 0, 0, 0)))
    for k in range(-5, 6):                                              # Wellblechrippen als dunkle Streifen
        for sgn in (-1, 1):
            FAIR.append(poly("k:farbe", [(*fr.pt(k * 0.5 + 0.2, sgn * 1.205), y + 0.2), (*fr.pt(k * 0.5 + 0.32, sgn * 1.205), y + 0.2), (*fr.pt(k * 0.5 + 0.32, sgn * 1.205), y + 2.5),
                                         (*fr.pt(k * 0.5 + 0.2, sgn * 1.205), y + 2.5)], shade(c, 0.7), (fr.v.x * sgn, fr.v.y * sgn)))
    collide_rect(x, z, fr.u.x, fr.u.y, 3.0, 1.2, 2.7, "mauer")
    return True


def toilets(x, z, ang_deg, n=4):
    """Reihe Toilettenkabinen (blau, helles Dach)."""
    fr = frame_at(x, z, ang_deg)
    ha = n * 0.65
    if not try_place(x, z, fr.u.x, fr.u.y, ha + 0.1, 0.9, margin=3.0, what="Toiletten"):
        return False
    y = GROUND_Y
    for i in range(n):
        a = -ha + 0.65 + i * 1.3
        FAIR.extend(cbox(fr, "k:farbe", a - 0.62, a + 0.62, -0.62, 0.62, y, y + 2.3, lin("2d6fb8"), grad=(0.75, 1.0), top=False))
        FAIR.extend(cbox(fr, "k:farbe", a - 0.64, a + 0.64, -0.64, 0.64, y + 2.3, y + 2.42, lin("e8eef4"), grad=(1, 1)))
        FAIR.append(poly("k:farbe", [(*fr.pt(a - 0.4, 0.625), y + 0.05), (*fr.pt(a + 0.4, 0.625), y + 0.05), (*fr.pt(a + 0.4, 0.625), y + 2.0), (*fr.pt(a - 0.4, 0.625), y + 2.0)],
                          lin("e8eef4"), (fr.v.x, fr.v.y)))
    collide_rect(x, z, fr.u.x, fr.u.y, ha, 0.65, 2.4, "mauer")
    return True


def pallet_stack(x, z, ang_deg, crates=True):
    fr = frame_at(x, z, ang_deg)
    if not try_place(x, z, fr.u.x, fr.u.y, 0.7, 0.55, margin=2.0, what="Paletten"):
        return False
    y = GROUND_Y
    FAIR.extend(cbox(fr, "k:farbe", -0.6, 0.6, -0.4, 0.4, y, y + 0.14, lin("b48a55"), grad=(0.7, 1.0)))
    if crates:
        for k in range(3):
            c = lin(frng.choice(["f2c21b", "d63a2a", "2d8a4a"]))
            FAIR.extend(cbox(fr, "k:farbe", -0.55, 0.55, -0.38, 0.38, y + 0.14 + k * 0.3, y + 0.14 + (k + 1) * 0.3 - 0.01, c, grad=(0.8, 1.0)))
    collide_rect(x, z, fr.u.x, fr.u.y, 0.62, 0.42, 1.0, "mauer")
    return True


def waste_bin(x, z, ang_deg):
    """Müllcontainer 1100 l (grau, Deckel)."""
    fr = frame_at(x, z, ang_deg)
    if not try_place(x, z, fr.u.x, fr.u.y, 0.8, 0.65, margin=2.0, what="Müllcontainer"):
        return False
    y = GROUND_Y
    FAIR.extend(cbox(fr, "k:farbe", -0.55, 0.55, -0.5, 0.5, y + 0.12, y + 1.0, lin("5c6770"), grad=(0.75, 1.0)))
    FAIR.extend(cbox(fr, "k:farbe", -0.58, 0.58, -0.53, 0.53, y + 1.0, y + 1.1, lin("2a3a2e"), grad=(1, 1)))
    collide_rect(x, z, fr.u.x, fr.u.y, 0.58, 0.55, 1.1, "mauer")
    return True


def car_park(rows):
    """Besucherparkplatz: Autos in Reihen (kit_car), ordentlich eingewiesen; rows = Liste ((Anfang x, z), (Schritt dx, dz), Anzahl, (Autorichtung hx, hz))."""
    kr = random.Random(21)
    count = 0
    for (sx, sz), (dx, dz), n, (hx, hz) in rows:
        for i in range(n):
            if kr.random() < 0.14:
                continue
            cx, cz = sx + dx * i * 2.8 + kr.uniform(-0.08, 0.08), sz + dz * i * 2.8 + kr.uniform(-0.1, 0.1)
            ang = kr.uniform(-0.07, 0.07)
            heading = Vector((hx * math.cos(ang) - hz * math.sin(ang), hx * math.sin(ang) + hz * math.cos(ang))) * (1 if kr.random() < 0.92 else -1)
            parts_c, (cl, cw) = kit_car.random_car(kr, cx, cz, heading.x, heading.y, base_y=GROUND_Y)
            if try_place(cx, cz, heading.x, heading.y, cl / 2 + 0.2, cw / 2 + 0.2, margin=3.0, what="Auto"):
                FAIR.extend(parts_c)
                collide_rect(cx, cz, heading.x, heading.y, cl / 2, cw / 2, 1.5, "auto")
                count += 1
    return count


def wood_fence(path, gaps=(), post_step=2.5, h=1.25):
    """Holzzaun entlang einer Polylinie: Pfosten und zwei Riegel; gaps = Liste (a, b) von Strecken (Vector-Paare) ohne Zaun (Tore)."""
    pts = [Vector(p) for p in path]
    P = FAIR
    wood = lin("9a6a3c")
    for a, b in zip(pts, pts[1:]):
        L = (b - a).length
        n = max(1, int(round(L / post_step)))
        t = (b - a).normalized()
        fr = Frame(a, t, Vector((-t.y, t.x)))
        for i in range(n + 1):
            p = a + t * (L * i / n)
            if any(seg_dist_pt(p, g0, g1) < 0.4 for g0, g1 in gaps) and i not in (0, n):
                continue
            P += cbox(Frame(p, t, Vector((-t.y, t.x))), "k:farbe", -0.06, 0.06, -0.06, 0.06, GROUND_Y, GROUND_Y + h, wood, grad=(0.75, 1.0))
        for i in range(n):
            s0, s1 = L * i / n, L * (i + 1) / n
            mid = a + t * ((s0 + s1) / 2)
            if any(seg_dist_pt(mid, g0, g1) < 0.5 for g0, g1 in gaps):
                continue
            for yy in (0.45, 1.0):
                P += cbox(fr, "k:farbe", s0 + 0.06, s1 - 0.06, -0.025, 0.025, GROUND_Y + yy, GROUND_Y + yy + 0.1, shade(wood, 1.1), grad=(1, 1), top=True, sides=(1, 1, 0, 0))
        m = max(1, int(round(L / 5.0)))
        for i in range(m):
            mid = a + t * (L * (i + 0.5) / m)
            if any(seg_dist_pt(mid, g0, g1) < 1.5 for g0, g1 in gaps):
                continue
            collide_rect(mid.x, mid.y, t.x, t.y, L / m / 2, 0.1, 1.2, "gitter")


def cable(path, width=0.09, y_off=0.03, col=None):
    """Stromkabel auf dem Boden (schwarzer Gummi)."""
    FAIR.extend(ribbon_poly(path, width, GROUND_Y + y_off, "dunkel", None, 1.0))


def cable_bridge(x, z, ang_deg, length=2.2):
    """Kabelbrücke (gelbes Kunststoffprofil mit schwarzen Streifen) über einem Kabel."""
    fr = frame_at(x, z, ang_deg)
    y = GROUND_Y
    n = 8
    for i in range(n):
        a0, a1 = -length / 2 + i * length / n, -length / 2 + (i + 1) * length / n
        FAIR.extend(cbox(fr, "k:farbe", a0, a1, -0.3, 0.3, y, y + 0.07, PAL["gelb"] if i % 2 == 0 else PAL["schwarz"], grad=(1, 1), sides=(1, 1, 0, 0)))


def power_box(x, z, ang_deg):
    fr = frame_at(x, z, ang_deg)
    FAIR.extend(cbox(fr, "k:farbe", -0.35, 0.35, -0.25, 0.25, GROUND_Y, GROUND_Y + 0.85, lin("c9ccd2"), grad=(0.75, 1.0)))
    FAIR.extend(cbox(fr, "k:farbe", -0.3, 0.3, 0.25, 0.27, GROUND_Y + 0.55, GROUND_Y + 0.8, PAL["gelb"], grad=(1, 1), top=False, sides=(0, 1, 0, 0)))
    collide_circle(x, z, 0.45, 0.85, "mast")


def gate(fx1):
    """Eingangstor am Zaun (x = fx1, Öffnung z -5,5..5,5): zwei Pfeiler, Querbalken mit Schild, Drehkreuze, Fahnen."""
    P = FAIR
    y = GROUND_Y
    fr = Frame((fx1, 0.0), (0.0, 1.0), (-1.0, 0.0))          # u entlang z, v zeigt nach innen (-x)
    for sgn in (-1, 1):
        a = sgn * 5.9
        P += cbox(fr, "k:farbe", a - 0.45, a + 0.45, -0.45, 0.45, y, y + 0.5, lin("b8b0a2"), grad=(0.8, 1.0))
        P += cbox(fr, "f_planken", a - 0.36, a + 0.36, -0.36, 0.36, y + 0.5, y + 5.0, wood_col("creme"), 1.28)
        P += cbox(fr, "k:farbe", a - 0.46, a + 0.46, -0.46, 0.46, y + 5.0, y + 5.25, PAL["rot"], grad=(1, 1))
        P += cbox(fr, "k:farbe", a - 0.4, a + 0.4, -0.4, 0.4, y + 2.2, y + 2.55, PAL["rot"], grad=(1, 1), top=False)
        collide_rect(fx1, a, 1.0, 0.0, 0.5, 0.5, 5.2, "mauer")
        flag_pole(fx1 - 1.2, a + sgn * 0.3, [(0.70, 0.03, 0.02), (0.02, 0.08, 0.50)][(sgn + 1) // 2], 7.4, 0.0 if sgn < 0 else 3.14)
    # Querbalken
    P += cbox(fr, "f_planken", -5.9, 5.9, -0.35, 0.35, y + 4.4, y + 5.05, wood_col("blau"), 1.28)
    # Schild als A-Rahmen auf dem Balken: zwei Tafeln lehnen gegeneinander, von innen und außen aus der Luft lesbar
    cell = SIGN_CELL["einlass"]
    cu0, cu1 = (cell % 4) / 4.0 + 0.004, (cell % 4 + 1) / 4.0 - 0.004
    cv1, cv0 = 1.0 - (cell // 4) / 4.0 - 0.006, 1.0 - (cell // 4 + 1) / 4.0 + 0.006
    for side in (1, -1):
        face = (fr.v.x * side, fr.v.y * side)
        us = [(cu0, cv0), (cu1, cv0), (cu1, cv1), (cu0, cv1)] if side > 0 else [(cu1, cv0), (cu0, cv0), (cu0, cv1), (cu1, cv1)]
        P.append(("f_schild", [(*fr.pt(-3.6, side * 0.45), y + 5.05), (*fr.pt(3.6, side * 0.45), y + 5.05), (*fr.pt(3.6, side * 0.04), y + 6.75), (*fr.pt(-3.6, side * 0.04), y + 6.75)],
                  us, face, [(1, 1, 1)] * 4))
    for i in range(25):
        a_ = -5.7 + i * 0.475
        for side in (-0.42, 0.42):
            P += bulb(*fr.pt(a_, side), y + 5.14, bulb_key(frng), 0.07)
    for i in range(16):
        a_ = -3.6 + i * 0.48
        P += bulb(*fr.pt(a_, 0.0), y + 6.85, bulb_key(frng), 0.07)
    for side in (-1, 1):
        for a_ in (-3.6, 3.6):
            for q in (0.25, 0.5, 0.75):
                P += bulb(*fr.pt(a_, side * (0.45 - 0.41 * q)), y + 5.05 + 1.7 * q, bulb_key(frng), 0.065)
    # Drehkreuze und Gitter
    for k, a in enumerate((-3.6, -1.2, 1.2, 3.6)):
        c = fr.pt(a, 0.0)
        P += cyl("k:farbe", c.x, c.y, 0.09, y, y + 1.05, 8, PAL["stahl"])
        for arm in range(3):
            ang = arm * 2 * math.pi / 3 + 0.4
            P += cbox(Frame(c, (math.cos(ang), math.sin(ang)), (-math.sin(ang), math.cos(ang))), "k:farbe", 0.0, 0.55, -0.025, 0.025, y + 0.95, y + 1.0, PAL["stahl"], grad=(1, 1))
        collide_circle(c.x, c.y, 0.55, 1.1, "gitter")
    kassen = ((fx1 - 4.0, -8.0, 0.0, 1.0), (fx1 - 4.0, 8.0, 0.0, -1.0))
    for (kx, kz, kfx, kfz) in kassen:
        stall(kx, kz, kfx, kfz, "kasse", w=2.6, d=2.2, sign="kasse")
    # Warteschlange vor dem Tor (Besucher außen)
    for k in range(7):
        person(fx1 + 2.4 + (k % 3) * 1.4, -5.0 + k * 1.6 + frng.uniform(-0.3, 0.3), 180 + frng.uniform(-25, 25), 1.0)
    for k in range(5):
        person(fx1 - 3.0 - (k % 2) * 1.5, -3.0 + k * 1.5, 180 + frng.uniform(-25, 25), 1.0)


def fair_fields(X, Z, d):
    """Bodenfelder (Rasenhelligkeit, Sägemehl, Erde) auf einem Raster (X, Z) mit Abstand d zur Mittellinie."""
    shape = X.shape
    Pp = np.stack([X.ravel(), Z.ravel()], 1)
    fx0, fx1, fz0, fz1 = fence_rect()
    out_f = np.maximum(np.maximum(fx0 - X, X - fx1), np.maximum(fz0 - Z, Z - fz1))
    inside_ = 1 - smooth(-0.5, 2.5, out_f)
    n1, n2, n3 = vnoise(X, Z, 11, 1), vnoise(X, Z, 4.5, 2), vnoise(X, Z, 23, 3)
    dirt = smooth(0.50, 0.78, 0.55 * n1 + 0.30 * n2 + 0.15 * n3) * 0.75 * inside_
    sand = np.zeros(shape)
    verge = (1 - smooth(0.3, 1.8, np.abs(d - (HW + 1.5)))) * smooth(0.40, 0.62, n2) * 0.7 * inside_      # abgetretener Streifen am Fahrbahnrand (unregelmäßig)
    dirt = np.maximum(dirt, verge)
    for path, hs, hd_ in LANES:
        dl = dist_polyline(Pp, path).reshape(shape)
        sand = np.maximum(sand, 1 - smooth(hs - 0.8, hs + 0.7, dl))
        dirt = np.maximum(dirt, 1 - smooth(hd_ - 1.4, hd_ + 0.9, dl))
    for (cx, cz, rx, rz, dv, sv) in ZONES:
        sd = (np.hypot((X - cx) / rx, (Z - cz) / rz) - 1.0) * min(rx, rz) + (n1 - 0.5) * 6.0
        w = 1 - smooth(-2.0, 1.5, sd)
        dirt = np.maximum(dirt, w * dv)
        sand = np.maximum(sand, (1 - smooth(-4.0, 0.5, sd)) * sv)
    for (cx, cz, hx, hz, dv, sv) in RECTS:
        sd = np.maximum(np.abs(X - cx) - hx, np.abs(Z - cz) - hz) + (n1 - 0.5) * 4.0
        dirt = np.maximum(dirt, (1 - smooth(-1.5, 1.8, sd)) * dv)
        sand = np.maximum(sand, (1 - smooth(-2.5, 0.8, sd)) * sv)
    dirt = np.maximum(dirt, (1 - smooth(0.3, 2.0, np.abs(out_f - 0.8))) * 0.65)         # Streifen am Zaun
    sand = np.clip(sand * (0.62 + 0.7 * vnoise(X, Z, 1.9, 5)), 0, 1)
    dirt = np.clip(dirt, 0, 1) * (1 - sand * 0.9)
    bright = 0.9 + 0.2 * n3 - 0.12 * dirt
    stripe = np.where(np.floor((X + 0.35 * Z) / 2.6) % 2 == 0, 0.05, -0.05)
    bright = bright + stripe * (1 - inside_)
    return bright, sand, dirt


def stunt_cells(X, Z, d):
    """Raster-Maske: Punkte nahe der Fahrbahn, die zu einer Rampe, Lücke, Schleife oder Abkürzung gehören (dort fehlt die Laufzeit-Fahrbahn teilweise)."""
    mask = np.zeros(X.shape, bool)
    spans = []
    total = dist[N] if dist[N] > 0 else 1.0
    for r in data.get("ramps", []):
        spans.append((r["s"] - 0.02, r["s"] + r.get("length", 6.0) / total + 0.03))
    for g in data.get("gaps", []):
        spans.append((g["from"] - 0.03, g["to"] + 0.03))
    for l in data.get("loops", []):
        spans.append((l["s"] - 0.04, l["s"] + 0.05))
    if not spans:
        return mask
    near = np.argwhere(d < HW + 0.5)
    pts = np.array([[X[a, b], Z[a, b]] for a, b in near])
    for k in range(0, len(pts), 2000):
        q = pts[k:k + 2000]
        idx = np.argmin(((q[:, None, :] - C[None, :, :]) ** 2).sum(2), axis=1)
        sv = np.array([dist[i] / total for i in idx])
        for (s0, s1) in spans:
            sel = ((sv - s0) % 1.0) <= ((s1 - s0) % 1.0)
            for (a, b) in near[k:k + 2000][sel]:
                mask[a, b] = True
    return mask


def fair_ground():
    gx = np.arange(x0, x1 + 1, 1.0)
    gz = np.arange(z0, z1 + 1, 1.0)
    X, Z = np.meshgrid(gx, gz)
    P = np.stack([X.ravel(), Z.ravel()], 1)
    d = dist_to_center(P).reshape(X.shape)
    bright, sand, dirt = fair_fields(X, Z, d)
    parts = []
    nx_, nz_ = len(gx), len(gz)
    need = stunt_cells(X, Z, d)                  # unter Rampe und Lücke liegt keine Fahrbahn: dort bleibt der Boden

    def emit(j, i, st):
        ci = [(j, i), (j, i + st), (j + st, i + st), (j + st, i)]
        if all(d[a, b] < HW - 0.1 for a, b in ci) and not any(need[a, b] for a, b in ci):
            return
        corners_ = [(float(X[a, b]), float(Z[a, b]), GROUND_Y) for a, b in ci]
        colors = [(float(bright[a, b]), float(sand[a, b]), float(dirt[a, b])) for a, b in ci]
        parts.append(("f_gelaende", corners_, [(cx / 3.0, -cz / 3.0) for cx, cz, _ in corners_], None, colors))

    for j in range(0, nz_ - 4, 4):                                   # Blöcke von 4 m: 1 m nahe der Strecke und wo sich Wege ändern, sonst 2 m bzw. 4 m
        for i in range(0, nx_ - 4, 4):
            dmin = d[j:j + 5, i:i + 5].min()
            var = max(np.ptp(sand[j:j + 5, i:i + 5]), np.ptp(dirt[j:j + 5, i:i + 5]))
            if dmin < 11.0 or var > 0.3:
                for jj in range(j, j + 4):
                    for ii in range(i, i + 4):
                        emit(jj, ii, 1)
            elif dmin < 24.0:
                for jj in range(j, j + 4, 2):
                    for ii in range(i, i + 4, 2):
                        emit(jj, ii, 2)
            else:
                emit(j, i, 4)
    objs_ground.append(mesh_object("Boden_gelaende", parts))
    print("DIORAMA fair: Boden", len(parts), "Kacheln")


def fair_far_surround():
    """Weite Wiese rund um die Diorama-Fläche (kein sichtbarer Rand bei breiten Bildschirmen)."""
    far = 400
    frame = []
    for ax0, az0, ax1, az1 in ((x0 - far, z0 - far, x1 + far, z0), (x0 - far, z1, x1 + far, z1 + far), (x0 - far, z0, x0, z1), (x1, z0, x1 + far, z1)):
        quad = [(ax0, az1, GROUND_Y), (ax1, az1, GROUND_Y), (ax1, az0, GROUND_Y), (ax0, az0, GROUND_Y)]
        frame.append(("f_wiese", quad, [(x / 6.0, -z / 6.0) for x, z, _ in quad]))
    mesh_object("Weite", frame)



def brunnen(x, z):
    """Springbrunnen auf dem Eingangsplatz: Steinbecken, Wasser, Säule mit Schale."""
    if not try_place(x, z, 1, 0, 3.4, 3.4, margin=3.0, what="Brunnen"):
        return False
    P = FAIR
    y = GROUND_Y + 0.014
    stone = lin("b9b2a4")
    P += cyl("k:farbe", x, z, 3.0, y, y + 0.55, 20, stone, grad=(0.75, 1.0), cap=False)
    P += cyl("k:farbe", x, z, 3.0, y + 0.5, y + 0.58, 20, shade(stone, 1.1), r_top=2.55, cap=False)
    P += cyl("wasser", x, z, 2.7, y + 0.4, y + 0.42, 20, None, cap=True)
    P += cyl("k:farbe", x, z, 0.3, y, y + 1.5, 10, stone, r_top=0.22)
    P += cyl("k:farbe", x, z, 1.1, y + 1.5, y + 1.75, 14, stone, r_top=0.7, cap=False)
    P += cyl("wasser", x, z, 0.95, y + 1.72, y + 1.76, 14, None, cap=True)
    P += cyl("k:farbe", x, z, 0.08, y + 1.76, y + 2.5, 6, stone, r_top=0.03)
    collide_circle(x, z, 3.05, 0.6, "mauer")
    return True


def fair_plaza():
    """Gepflasterter Eingangsplatz (Platten, Bordstein) in FLOOR; Beete und Bänke in FAIR."""
    pz0, pz1, px0, px1 = -14.0, 14.0, 60.5, fence_rect()[1] - 0.6
    y = GROUND_Y + 0.014
    quad = [(px0, pz0, y), (px1, pz0, y), (px1, pz1, y), (px0, pz1, y)]
    FLOOR.append(("pflaster", quad, [(x / 3.0, -z / 3.0) for x, z, _ in quad]))
    k = lin("b9b4a8")
    for (ax, az, bx, bz) in ((px0, pz0, px1, pz0), (px0, pz1, px1, pz1), (px0, pz0, px0, pz1)):
        t = Vector((bx - ax, bz - az)).normalized()
        fr = Frame((ax, az), t, Vector((-t.y, t.x)))
        L = math.hypot(bx - ax, bz - az)
        FAIR.extend(cbox(fr, "k:farbe", 0.0, L, -0.14, 0.14, GROUND_Y, y + 0.07, k, grad=(0.8, 1.0)))
    for (cx, cz) in ((64.5, -10.5), (64.5, 10.5), (80.0, -10.5), (80.0, 10.5)):
        flower_bed(cx, cz, 1.3)
    brunnen(68.5, 0.0)
    stall_try("zuckerwatte", [(73.0, -11.6, 0, 1), (75.0, -11.6, 0, 1)], 3.6)
    stall_try("crepes", [(73.0, 11.6, 0, -1), (75.0, 11.6, 0, -1)], 3.8)
    fcol = [(0.70, 0.03, 0.02), (0.86, 0.86, 0.84), (0.90, 0.50, 0.02), (0.02, 0.08, 0.50)]
    for k, (fx_, fz_) in enumerate(((62.5, -3.0), (62.5, 3.0), (84.0, -3.5), (84.0, 3.5), (68.5, -4.4), (68.5, 4.4))):
        flag_pole(fx_, fz_, fcol[k % 4], 6.0, 0.3 * k)
    for sgn in (-1, 1):
        near(bench, 70.0, sgn * 5.6, 90)
        near(bench, 79.0, sgn * 6.5, 0)
        near(bin_, 66.0, sgn * 8.0)
        near(bin_, 80.0, sgn * 4.5)
    # Mittelachse: Besucher laufen zum Tor
    for k in range(7):
        people(66 + k * 3.0 + frng.uniform(-0.5, 0.5), frng.uniform(-6.0, 6.0), 2, 1.6, 0 if k % 2 else 180, 70)
    # Luftballonhändler
    balloons(63.5, 4.0)
    FAIR.extend(cbox(Frame((63.5, 4.0), (1, 0), (0, 1)), "k:farbe", -0.5, 0.5, -0.4, 0.4, GROUND_Y, GROUND_Y + 1.0, lin("f2c21b"), grad=(0.8, 1.0)))
    collide_rect(63.5, 4.0, 1.0, 0.0, 0.5, 0.4, 1.0, "mauer")


# ---------------------------------------------------------------- Wege und Zonen des Bodens (Sägemehl, Erde)
LANES = [  # (Polylinie, halbe Breite Sägemehl, halbe Breite festgetretene Erde)
    ([(0.0, -5.0), (0.0, -34.0)], 3.4, 5.8),
    ([(0.0, 5.0), (0.0, 34.0)], 3.4, 5.8),
    ([(-42.0, 3.0), (-42.0, 10.0)], 2.0, 4.5),
    ([(61.0, 0.0), (88.0, 0.0)], 0.0, 3.0),
]
ZONES = [  # Ellipse (Mitte x, z, Halbachsen, Erde, Sägemehl)
    (-42.0, 1.0, 15.0, 9.5, 0.95, 0.30),            # Riesenrad
    (40.0, 4.0, 11.5, 11.5, 0.95, 0.45),            # Karussell
    (0.0, 36.0, 9.5, 8.0, 0.95, 0.0),               # Autoscooter
    (0.0, -36.0, 9.5, 9.5, 0.95, 0.10),             # Festzelt
]
RECTS = [  # Rechteck (Mitte x, z, halbe Maße, Erde, Sägemehl)
    (73.0, 0.0, 14.0, 14.5, 1.0, 0.0),              # Eingangsplatz
    (-88.0, 0.0, 12.0, 54.0, 0.9, 0.0),             # Wirtschaftshof der Schausteller
    (74.0, 36.0, 13.0, 15.0, 0.85, 0.0),            # Parkplatz Süd
    (74.0, -36.0, 13.0, 15.0, 0.85, 0.0),           # Parkplatz Nord
    (-15.0, -37.0, 8.0, 5.0, 0.8, 0.9),             # Biergarten West
    (15.0, -37.0, 8.0, 5.0, 0.8, 0.9),              # Biergarten Ost
]


def reserve_runtime():
    """Grundflächen der Laufzeit-Bauteile (KI-Modelle, Lichtmasten) als belegt eintragen."""
    for p in data["props"]:
        if p["type"] == "ai":
            hx, hz = PROP_FOOT.get(p["model"], (2.0, 2.0))
            r = math.radians(float(p.get("rot", 0.0)))
            keep_out(p["x"], p["z"], math.cos(r), math.sin(r), hx + 0.6, hz + 0.6)
        elif p["type"] == "lamp":
            keep_out(p["x"], p["z"], 1.0, 0.0, 1.6, 1.6)


def fair_ao():
    """Kontaktschatten für die Laufzeit-Bauteile (Maße aus den Modellen gemessen, siehe docs/dioramen/fair.md)."""
    parts = []
    y0 = GROUND_Y
    for p in data["props"]:
        if p["type"] == "lamp":
            continue
        if p["type"] != "ai":
            continue
        m = p["model"]
        r = math.radians(float(p.get("rot", 0.0)))
        fr = Frame((p["x"], p["z"]), (math.cos(r), math.sin(r)), (-math.sin(r), math.cos(r)))
        if m == "jahrmarkt_riesenrad":
            for s in (-1, 1):
                parts += box(fr, "ao", -2.7, 2.7, s * 3.4 if s > 0 else -6.6, 6.6 if s > 0 else -3.4, y0, y0 + 3.5)
            parts += box(fr, "ao", -1.0, 1.0, -3.4, 3.4, y0, y0 + 2.0)
        elif m == "jahrmarkt_karussell":
            ao_prism(parts, p["x"], p["z"], 3.3, 3.0, y0, y0 + 3.5, 12)
        elif m == "jahrmarkt_autoscooter":
            parts += box(fr, "ao", -3.55, 3.55, -4.9, 4.9, y0, y0 + 1.4)
        elif m == "jahrmarkt_zelt":
            ao_prism(parts, p["x"], p["z"], 5.1, 4.6, y0, y0 + 3.5, 14)
        elif m in ("jahrmarkt_bude", "jahrmarkt_losbude"):
            hx, hz = (1.87, 1.53) if m == "jahrmarkt_bude" else (2.12, 1.53)
            parts += box(fr, "ao", -hx, hx, -hz, hz, y0, y0 + 3.5)
    add_ao_parts(parts)


# ---------------------------------------------------------------- Aufbau

LAMPS = [  # (x, z, Zielpunkt des Auslegers x, z): nur noch Parkplatz, Eingangsplatz und Hof (gelbes Laternenlicht); Buden und Fahrgeschäfte leuchten selbst
    (66.0, 26.0, 70.0, 30.0), (80.0, 26.0, 76.0, 30.0), (66.0, 45.0, 70.0, 42.0), (66.0, -26.0, 70.0, -30.0), (80.0, -26.0, 76.0, -30.0), (66.0, -45.0, 70.0, -42.0),
    (62.5, -12.5, 66.0, -12.5), (62.5, 12.5, 66.0, 12.5), (77.0, -13.0, 77.0, -9.0), (77.0, 13.0, 77.0, 9.0),
    (-82.0, -22.0, -86.0, -22.0), (-82.0, 22.0, -86.0, 22.0), (-91.0, 0.0, -86.0, 0.0), (-82.0, -42.0, -88.0, -42.0), (-82.0, 42.0, -88.0, 42.0),
]


def lamp_post(x, z, tx, tz, margin=1.8):
    """Parklaterne eintragen (Begleitdatei "lamps"); bei Überschneidung wird in der Umgebung (bis 2,5 m) die nächste freie Stelle genommen."""
    best = None
    for r in (0.0, 0.8, 1.6, 2.5):
        for k in range(1 if r == 0.0 else 8):
            ang = k * math.pi / 4
            px, pz = x + r * math.cos(ang), z + r * math.sin(ang)
            if road_gap([(px, pz)]) < HW + margin:
                continue
            poly_ = rect_poly(px, pz, 1.0, 0.0, 0.45, 0.45)
            if any(overlaps(poly_, q) for q in placed):
                continue
            best = (px, pz, poly_)
            break
        if best:
            break
    if not best:
        print("DIORAMA fair: Laterne abgelehnt", x, z)
        return False
    placed.append(best[2])
    lamps.append((Vector((best[0], best[1])), Vector((tx, tz))))
    return True


def stall_row(x, fx, z_start, dz, items, gap=0.12):
    """Buden in einer Reihe längs z dicht aneinander (Breite je Bude); z_start = Kante der ersten Bude, dz = Laufrichtung (±1)."""
    z = z_start
    centers = []
    for kind, w, sg in items:
        half = w / 2 + 0.2
        zc = z + dz * half
        stall(x, zc, fx, 0, kind, w=w, sign=sg)
        centers.append(zc)
        z = zc + dz * (half + gap)
    return centers


def build_valleys():
    """Nördliche Spielstraße und südliche Fressmeile in den Tälern der Acht; Bude und Gegenüber zeigen zur Gasse (x = 0)."""
    zn = stall_row(-6.0, 1, -13.8, -1, [("dosen", 4.6, "dosen"), ("schiessen", 4.8, "schiessen"), ("enten", 3.8, "enten")])
    zn2 = stall_row(6.0, -1, -13.8, -1, [("los", 4.0, "los"), ("dosen", 4.6, "dosen"), ("los", 4.2, "los")])
    zs = stall_row(-6.0, 1, 13.8, 1, [("pommes", 3.8, "pommes"), ("wurst", 4.0, "wurst"), ("zuckerwatte", 3.6, "zuckerwatte")])
    zs2 = stall_row(6.0, -1, 13.8, 1, [("eis", 3.6, "eis"), ("mandeln", 4.0, "mandeln"), ("crepes", 3.8, "crepes")])
    # Girlanden quer über die Gassen (zwischen den Dächern)
    for zz in (-16.0, -21.4, -26.6, 16.0, 21.4, 26.6):
        festoon((-4.4, zz, 3.4), (4.4, zz, 3.4), sag=0.55, step=0.8)
    # Besucher in den Gassen
    for zz in (-13.5, -18.5, -23.5, 13.5, 18.5, 23.5):
        people(frng.uniform(-1.0, 1.0), zz + frng.uniform(-1.0, 1.0), frng.choice([2, 3, 4]), 1.3, 90 if frng.random() < 0.5 else 270, 50)
    # Stromkabel hinter den Reihen
    for sgn in (-1, 1):
        cable([(sgn * 8.3, -14.0), (sgn * 8.3, -28.5)], 0.07)
        cable([(sgn * 8.3, 14.0), (sgn * 8.3, 28.5)], 0.07)
        for zz in (-16.0, -21.0, -26.0, 16.0, 21.0, 26.0):
            cable([(sgn * 8.3, zz), (sgn * 7.6, zz)], 0.06)
        power_box(sgn * 8.9, -29.5, 90)
        power_box(sgn * 8.9, 29.5, 90)
    # Bänke und Eimer an den Gassenenden
    bin_(2.6, -9.2)
    bin_(-2.6, 9.4)
    bench(-3.6, -9.5, 0)
    bench(3.6, 9.5, 0)


def build_loop_interiors():
    # --- Riesenrad (Mitte -42 | -2, Rad längs x)
    stall(-33.2, 5.5, -1, 0, "kasse", w=2.6, d=2.2, sign="riesenrad")
    barrier_line([(-43.4, 2.4), (-43.4, 9.6)])
    barrier_line([(-40.6, 2.4), (-40.6, 9.6)])
    barrier_line([(-43.4, 9.6), (-40.6, 9.6)], collide=False)
    stall_try("mandeln", [(-56.0, -3.5, 0, 1), (-56.0, 3.5, 0, -1)], 3.8)
    stall_try("wurst", [(-35.5, -9.6, 0, 1), (-38.5, -9.6, 0, 1), (-33.0, -9.4, 0, 1)], 3.8)
    stall_try("crepes", [(-50.5, 9.0, 0, -1), (-52.0, 9.0, 0, -1)], 3.8)
    table_set(-46.0, 10.5, 0, 2.2)
    for (x, z, a) in ((-52.0, 3.5, 90), (-29.5, 9.0, 0), (-30.5, -5.0, 90)):
        near(bench, x, z, a)
    for (x, z) in ((-38.5, 4.0), (-49.5, 6.0), (-34.5, -6.0), (-50.0, -10.5)):
        near(bin_, x, z)
    near(parasol, -48.0, 6.5, PAL["gelb"], PAL["weiss"], 1.6)
    near(parasol, -39.0, -8.5, PAL["blau"], PAL["weiss"], 1.6)
    near(flower_bed, -58.0, 3.0, 1.2)
    near(flower_bed, -28.0, 1.0, 1.2)
    balloons(-36.5, -10.5, 10)
    FAIR.extend(cbox(Frame((-36.5, -10.5), (1, 0), (0, 1)), "k:farbe", -0.5, 0.5, -0.4, 0.4, GROUND_Y, GROUND_Y + 1.0, lin("3a8ae0"), grad=(0.8, 1.0)))
    collide_rect(-36.5, -10.5, 1.0, 0.0, 0.5, 0.4, 1.0, "mauer")
    for k in range(5):
        people(frng.uniform(-56, -32), frng.uniform(6, 11), 3, 1.4, frng.uniform(0, 360), 120)
    # --- Karussell (Mitte 40 | 4)
    carousel_area()
    kid_carousel(21.5, 0.0)
    stall(33.0, -4.5, 1, 0, "kasse", w=2.6, d=2.2, sign="karussell")
    stall_try("eis", [(29.0, -7.8, 0, 1), (29.5, -8.2, 0, 1)], 3.6)
    stall_try("schiessen", [(29.0, 8.0, 0, -1), (29.5, 8.5, 0, -1)], 4.0)
    near(bench, 46.0, -3.0, 20)
    near(bench, 46.0, 11.0, 160)
    near(bin_, 33.5, 9.5)
    near(bin_, 44.0, -1.0)
    near(flower_bed, 31.0, 1.5, 1.1)
    balloons(43.0, 13.0, 12)
    near(parasol, 47.0, 3.5, PAL["rot"], PAL["weiss"], 1.6)
    for k in range(6):
        people(40 + 8.6 * math.cos(k * 1.1 + 0.3), 4 + 8.6 * math.sin(k * 1.1 + 0.3), 3, 1.0, math.degrees(k * 1.1 + 0.3) + 180, 40)


def build_spectators():
    """Zuschauer hinter Absperrgittern an den äußeren Kurvenbögen (links und rechts der Acht)."""
    for name, sel in (("links", lambda p: p.x < -60.0), ("rechts", lambda p: p.x > 50.5)):
        idx = [i for i in range(0, N, 2) if sel(center[i])]
        if not idx:
            continue
        # zusammenhängende Läufe (der Index läuft ringförmig)
        runs_ = []
        cur = [idx[0]]
        for i in idx[1:]:
            if i - cur[-1] <= 4:
                cur.append(i)
            else:
                runs_.append(cur)
                cur = [i]
        runs_.append(cur)
        for run_ in runs_:
            if len(run_) < 8:
                continue
            path_b, path_c = [], []
            for i in run_:
                n_ = left[i]
                if inside(np.array([(center[i].x + n_.x * 3.0, center[i].y + n_.y * 3.0)]))[0]:
                    n_ = -n_
                pb = center[i] + n_ * (HW + 2.2)
                path_b.append((pb.x, pb.y))
                pc = center[i] + n_ * (HW + 3.6)
                path_c.append((pc.x, pc.y, n_))
            barrier_line(path_b[::2] if len(path_b) > 6 else path_b)
            for k in range(0, len(path_c), 3):
                x_, z_, n_ = path_c[k]
                if frng.random() < 0.8:
                    people(x_, z_, frng.choice([2, 3, 3, 4]), 1.0, math.degrees(math.atan2(-n_.y, -n_.x)), 30)
            # Fahnen hinter den Zuschauern
            for k in range(6, len(path_c) - 3, 16):
                x_, z_, n_ = path_c[k]
                flag_pole(x_ + n_.x * 2.4, z_ + n_.y * 2.4, [(0.70, 0.03, 0.02), (0.86, 0.86, 0.84), (0.90, 0.50, 0.02), (0.02, 0.08, 0.50)][(k // 16) % 4], 6.0, math.atan2(-n_.y, -n_.x) + 1.57)


def build_beer_garden():
    """Biergarten vor dem Festzelt (Mitte 0 | -36), Autoscooter-Kasse und Wartebereich."""
    for sgn in (-1, 1):
        for row in range(3):
            for col in range(2):
                table_set(sgn * (11.0 + col * 4.4), -39.0 + row * 3.0, 0 if col == 0 else 0)
    for bx in (-7.0, 7.0):
        near(flower_bed, bx, -30.6, 1.0, r_max=1.0)
    stall(10.0, 31.0, -1, 0, "kasse", w=2.6, d=2.2, sign="autoscooter")
    barrier_line([(-2.4, 27.5), (-2.4, 31.8)])
    barrier_line([(2.4, 27.5), (2.4, 31.8)])
    queue_line((0.0, 27.5), (0.0, 31.5), 5, 90)
    bin_(-5.0, 30.5)
    bench(-8.5, 31.0, 90)
    waste_bin(-12.0, 29.0, 0)
    waste_bin(13.0, -30.0, 0)
    # Imbisse vor dem Autoscooter und am Zelt
    stall(-12.0, 33.0, 0, -1, "wurst", w=3.6, d=2.8)


def build_backstage_and_parking():
    # Wirtschaftshof (Westen): Wohnwagen in Reihen, Aggregat, Container, Toiletten
    for i, zz in enumerate((-46.0, -40.0, -34.0, -28.0)):
        caravan(-95.5, zz, 0, ("blau", "rot", "gruen", "gelb")[i % 4])
    for i, zz in enumerate((28.0, 34.0, 40.0, 46.0)):
        caravan(-95.5, zz, 0, ("rot", "blau", "gelb", "gruen")[i % 4])
    for i, zz in enumerate((-46.0, -40.0, -34.0, -28.0)):
        caravan(-84.0, zz - 0.0, 180, ("gelb", "gruen", "blau", "rot")[i % 4])
    for i, zz in enumerate((28.0, 34.0, 40.0, 46.0)):
        caravan(-84.0, zz, 180, ("gruen", "gelb", "rot", "blau")[i % 4])
    truck(-86.0, -14.0, 90, "generator")
    truck(-86.0, 14.0, 90, "kasten")
    container(-90.0, -22.0, 0)
    container(-90.0, 22.0, 0)
    near(toilets, -74.5, 31.0, 90, 4)
    for (x, z) in ((-79.0, -30.0), (-79.0, -24.0), (-79.0, 28.0)):
        waste_bin(x, z, 90)
    for (x, z) in ((-80.0, -6.0), (-80.0, 8.0), (-84.0, 2.0)):
        pallet_stack(x, z, frng.choice([0, 90]))
    # Verteilerkasten und dickes Kabel vom Aggregat
    power_box(-82.5, -8.0, 0)
    cable([(-83.0, -8.0), (-74.0, -8.0), (-71.0, -6.0)], 0.2)
    cable_bridge(-77.0, -8.0, 90, 2.0)
    # Parkplätze am Eingang: Reihen quer zur Zufahrt
    rows = []
    for k in range(5):
        rows.append(((64.0, 21.5 + k * 7.0), (1.0, 0.0), 7, (0.0, 1.0)))
        rows.append(((64.0, -21.5 - k * 7.0), (1.0, 0.0), 7, (0.0, -1.0)))
    n = car_park(rows)
    print("DIORAMA fair: Parkplatz-Autos", n)


def build_fence_and_trees():
    fx0, fx1, fz0, fz1 = fence_rect()
    gap = [(Vector((fx1, -5.6)), Vector((fx1, 5.6)))]
    wood_fence([(fx0, fz0), (fx1, fz0), (fx1, fz1), (fx0, fz1), (fx0, fz0)], gap)
    gate(fx1)
    names = ["stadt_baum_linde", "stadt_baum_kastanie", "stadt_baum_ahorn", "stadt_baum_platane"]
    tr = random.Random(9)
    n = 0
    # Baumreihe rund um den Festplatz, außerhalb des Zauns
    def ring_points(off):
        pts = []
        for x in np.arange(fx0 + 2, fx1, 17.0):
            pts += [(x, fz0 - off), (x, fz1 + off)]
        for z in np.arange(fz0 + 6, fz1 - 4, 17.0):
            pts += [(fx0 - off, z), (fx1 + off, z)]
        return pts
    for (x, z) in ring_points(3.0):
        x += tr.uniform(-2, 2)
        z += tr.uniform(-1.5, 1.5)
        if abs(z) < 8 and x > fx1 - 2:
            continue
        if place(tr.choice(names), x, z, tr.uniform(0, 6.28), tr.uniform(8.5, 11.5), trunk=0.5, clearance=HW + 8.0):
            n += 1
    # einzelne Bäume im Festplatz (hinten im Wirtschaftshof, am Biergarten)
    for (x, z) in ((-98.0, -4.0), (-98.0, 6.0), (-62.0, 40.0), (-62.0, -42.0), (28.0, -44.0), (-30.0, 44.0)):
        if place(tr.choice(names), x, z, tr.uniform(0, 6.28), tr.uniform(8.0, 10.0), trunk=0.5, clearance=HW + 8.0):
            n += 1
    print("DIORAMA fair: Bäume", n)


MAST_COLS = [(1.0, 0.88, 0.68), (0.85, 0.92, 1.0), (1.0, 0.78, 0.88)]


def light_masts():
    """Die Lichtmasten der Streckendatei (Typ lamp) als Diorama-Bauteile: Stahlrohrmast mit Tellerring und Birnenkranz; das Licht kommt aus
    add_light in warmen bis kühlen Weißtönen (statt des gelben Laternenscheins des Spiels). Hindernis: Mast."""
    k = 0
    for p in data["props"]:
        if p["type"] != "lamp":
            continue
        x, z = float(p["x"]), float(p["z"])
        gap = road_gap([(x, z)])
        if gap < HW + 0.9:
            print("DIORAMA fair: Warnung Lichtmast", round(x, 1), round(z, 1), "nahe der Fahrbahn", round(gap, 2))
        y = GROUND_Y
        P = FAIR
        ang = (x * 13.7 + z * 7.1) % 360
        fr = frame_at(x, z, ang)
        P += cbox(fr, "k:farbe", -0.3, 0.3, -0.3, 0.3, y, y + 0.12, PAL["dgrau"], 1.0, grad=(0.8, 1.0))
        P += cyl("k:farbe", x, z, 0.13, y + 0.12, y + 6.3, 8, lin("9aa4ae"), r_top=0.08, grad=(0.75, 1.0))
        P += cyl("k:farbe", x, z, 1.0, y + 6.15, y + 6.25, 12, lin("9aa4ae"), r_top=0.9, cap=True, grad=(0.8, 1.0))      # Lichtkranz: Tellerring mit Birnen
        for i_ in range(8):
            a = 2 * math.pi * i_ / 8
            P += bulb(x + 0.88 * math.cos(a), z + 0.88 * math.sin(a), y + 6.05, bulb_key(frng), 0.12)
        P += cyl("k:farbe", x, z, 0.06, y + 6.25, y + 6.7, 6, lin("9aa4ae"), cap=False)
        P += bulb(x, z, y + 6.8, bulb_key(frng), 0.15)
        collide_circle(x, z, 0.32, 6.3, "mast")
        col = MAST_COLS[k % 3]
        add_light(x, z, 6.2, col, 0.6, 12.5, omni=False)
        k += 1


def build_poles_and_strings():
    """Holzmasten mit Lichterketten über dem Biergarten, dem Eingangsplatz und der Karussell-Zone."""
    pr = random.Random(33)
    # Eingangsplatz: Querketten zwischen Masten am Rand
    top = fence_rect()[1]
    for x in (66.0, 74.0, 82.0):
        a, b = (x, -12.0), (x, 12.0)
        if try_place(a[0], a[1], 1, 0, 0.4, 0.4, 2.0, "Mast") and try_place(b[0], b[1], 1, 0, 0.4, 0.4, 2.0, "Mast"):
            FAIR.extend(pole(a[0], a[1], 4.8))
            FAIR.extend(pole(b[0], b[1], 4.8))
            festoon((a[0], a[1], 4.6), (b[0], b[1], 4.6), sag=1.4, step=0.85)
    # Längsketten zwischen den Masten der Querketten
    for z in (-12.0, 12.0):
        festoon((66.0, z, 4.6), (74.0, z, 4.6), sag=0.7, pennants=True, bulbs=False, step=0.6)
        festoon((74.0, z, 4.6), (82.0, z, 4.6), sag=0.7, pennants=True, bulbs=False, step=0.6)
    # Biergarten
    for sgn in (-1, 1):
        for x in (sgn * 8.0, sgn * 22.0):
            for z in (-43.0, -33.0):
                if try_place(x, z, 1, 0, 0.4, 0.4, 2.0, "Mast"):
                    FAIR.extend(pole(x, z, 4.6))
        festoon((sgn * 8.0, -43.0, 4.4), (sgn * 22.0, -43.0, 4.4), sag=0.8)
        festoon((sgn * 8.0, -33.0, 4.4), (sgn * 22.0, -33.0, 4.4), sag=0.8)
        festoon((sgn * 8.0, -43.0, 4.4), (sgn * 8.0, -33.0, 4.4), sag=0.7, pennants=True, bulbs=False, step=0.6)
        festoon((sgn * 22.0, -43.0, 4.4), (sgn * 22.0, -33.0, 4.4), sag=0.7, pennants=True, bulbs=False, step=0.6)
    # Karussell: Ring von Masten
    pts = []
    for k in range(8):
        a = 2 * math.pi * k / 8 + 0.2
        x, z = 40 + 9.4 * math.cos(a), 4 + 9.4 * math.sin(a)
        if try_place(x, z, 1, 0, 0.4, 0.4, 2.0, "Mast"):
            FAIR.extend(pole(x, z, 4.4))
            pts.append((x, z))
        else:
            pts.append(None)
    for i in range(8):
        a, b = pts[i], pts[(i + 1) % 8]
        if a and b:
            festoon((a[0], a[1], 4.2), (b[0], b[1], 4.2), sag=0.7, step=0.8)



def parasol(x, z, col_a, col_b, r=1.5, h=2.5):
    """Sonnenschirm: Mast, acht gestreifte Segmente (Draufsicht!), Fuß."""
    if not try_place(x, z, 1, 0, r, r, margin=2.0, what="Schirm"):
        return False
    P = FAIR
    y = GROUND_Y
    P += cyl("k:farbe", x, z, 0.04, y, y + h, 6, PAL["stahl"], cap=False)
    P += cyl("k:farbe", x, z, 0.28, y, y + 0.1, 8, PAL["dgrau"])
    n = 8
    for k in range(n):
        a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
        am = (a0 + a1) / 2
        P.append(poly("k:farbe", [(x, z, y + h + 0.35), (x + r * math.cos(a0), z + r * math.sin(a0), y + h - 0.1), (x + r * math.cos(a1), z + r * math.sin(a1), y + h - 0.1)],
                      col_a if k % 2 == 0 else col_b, (math.cos(am), math.sin(am)), 1.0, [(0.5, 1), (0, 0), (1, 0)]))
    collide_circle(x, z, 0.12, h, "mast")
    return True


def kid_carousel(x, z):
    """Kinderkarussell: runde Plattform, sechs Tiere an Stangen, gestreiftes Zeltdach mit Lichterkranz."""
    if not try_place(x, z, 1, 0, 3.4, 3.4, margin=3.0, what="Kinderkarussell"):
        return False
    P = FAIR
    y = GROUND_Y
    P += cyl("k:farbe", x, z, 3.0, y, y + 0.3, 16, lin("c9b78c"), grad=(0.7, 1.0))
    P += cyl("k:farbe", x, z, 2.8, y + 0.3, y + 0.34, 16, lin("a8473a"), cap=True)
    P += cyl("k:farbe", x, z, 0.28, y + 0.34, y + 3.0, 8, lin("e8d9a8"))
    animals = [lin("e8d8c0"), lin("c97a3a"), lin("f4d03f"), lin("8fb8e6"), lin("e8798f"), lin("7ac47a")]
    for k in range(6):
        a = 2 * math.pi * k / 6 + 0.3
        ax, az = x + 1.95 * math.cos(a), z + 1.95 * math.sin(a)
        P += cyl("k:farbe", ax, az, 0.035, y + 0.34, y + 2.6, 6, PAL["gold"], cap=False)
        fr = Frame((ax, az), (-math.sin(a), math.cos(a)), (math.cos(a), math.sin(a)))
        P += cbox(fr, "k:farbe", -0.4, 0.4, -0.14, 0.14, y + 0.8, y + 1.2, animals[k], grad=(0.8, 1.0))
        P += cbox(fr, "k:farbe", 0.3, 0.52, -0.1, 0.1, y + 1.05, y + 1.45, animals[k], grad=(0.8, 1.0))
    # Dach: acht Segmente rot-weiß, Volant mit Lichtern
    n = 12
    r_roof, y_rim, y_top = 3.15, y + 2.65, y + 3.7
    for k in range(n):
        a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
        am = (a0 + a1) / 2
        c = PAL["rot"] if k % 2 == 0 else PAL["weiss"]
        P.append(poly("k:farbe", [(x, z, y_top), (x + r_roof * math.cos(a0), z + r_roof * math.sin(a0), y_rim), (x + r_roof * math.cos(a1), z + r_roof * math.sin(a1), y_rim)],
                      c, (math.cos(am), math.sin(am)), 1.0, [(0.5, 1), (0, 0), (1, 0)]))
        P.append(poly("k:farbe", [(x + r_roof * math.cos(a0), z + r_roof * math.sin(a0), y_rim), (x + r_roof * math.cos(a1), z + r_roof * math.sin(a1), y_rim),
                                  (x + r_roof * math.cos(a1), z + r_roof * math.sin(a1), y_rim - 0.35), (x + r_roof * math.cos(a0), z + r_roof * math.sin(a0), y_rim - 0.35)],
                      c, (math.cos(am), math.sin(am)), 1.0, [(0, 1), (1, 1), (1, 0), (0, 0)]))
        P += bulb(x + (r_roof + 0.04) * math.cos(am), z + (r_roof + 0.04) * math.sin(am), y_rim - 0.42, bulb_key(frng), 0.08)
    P += cyl("k:farbe", x, z, 0.06, y_top, y_top + 0.5, 6, PAL["gold"])
    P += bulb(x, z, y_top + 0.58, "k:ampel_rot", 0.1)
    collide_circle(x, z, 3.2, 3.8, "mauer")
    return True


def build_pockets():
    """Die beiden Taschen links und rechts der Kreuzung: Biergarten mit Schankhütte (Westen), Kinderkarussell (Osten)."""
    stall_try("bier", [(-25.5, -3.5, 0, 1), (-24.0, -3.5, 0, 1), (-27.0, -3.0, 0, 1)], 4.6, sign="bier")
    near(table_set, -26.0, 4.5, 0, 2.2)
    near(table_set, -21.0, 3.8, 0, 2.2)
    near(parasol, -29.0, 2.0, PAL["rot"], PAL["weiss"], 1.7)
    near(parasol, -18.0, 0.8, PAL["gelb"], PAL["weiss"], 1.5)
    near(bin_, -29.5, -4.5)
    near(bench, 14.5, 0.0, 90)
    near(bin_, 17.0, -4.4)
    balloons(14.0, 4.0, 10)
    for k in range(5):
        people(21.5 + 5.0 * math.cos(k * 1.3), 4.5 * math.sin(k * 1.3), 3, 1.0, math.degrees(k * 1.3) + 180, 40)


# ---------------------------------------------------------------- Licht der Fahrgeschäfte, Leben, Hof und Parkplatz (Politur 02.10.2026)
RIDE_COLS = [(1.0, 0.35, 0.45), (1.0, 0.8, 0.35), (0.35, 0.9, 1.0), (0.9, 0.45, 1.0), (0.45, 1.0, 0.55)]


def ring_lights(cx, cz, r, y, n, size, energy, reach, cols=None, phase=0.0, ground_every=1, omni=False):
    """Lichterkranz: n Lichter im Kreis (Radius r, Höhe y) mit leuchtendem Fleck; je ground_every-tes Licht beleuchtet den Boden."""
    cols = cols or RIDE_COLS
    for k in range(n):
        a = phase + 2 * math.pi * k / n
        col = cols[k % len(cols)]
        if k % ground_every == 0:
            add_light(cx + r * math.cos(a), cz + r * math.sin(a), y, col, energy, reach, omni=omni, glow=size)
        else:
            add_light(cx + r * math.cos(a), cz + r * math.sin(a), y, col, 0.0, 0.5, omni=False, glow=size)


def ride_lights():
    """Echte Lichtquellen der Fahrgeschäfte (die Modelle der Streckendatei leuchten nicht von selbst): Lichterkranz am Rad, Kranz am Karussell,
    Kanten des Autoscooters, Zelteingang, Kinderkarussell, Brunnen. Farbe färbt den Boden; wenige davon sind echte Punktlichter (Premium)."""
    # Riesenrad: Mitte (-42 | -2), Rad längs x, Nabe in 9,4 m, Felge Radius 8,4
    cx, cz, cy, R = -42.0, -2.0, 9.4, 8.4
    for k in range(16):
        a = 2 * math.pi * k / 16
        x_, y_ = cx + R * math.cos(a), cy + R * math.sin(a)
        col = RIDE_COLS[k % 5]
        if k % 2 == 0:
            add_light(x_, cz, y_, col, 0.34, 10.0, omni=False, glow=1.2)
        else:
            add_light(x_, cz, y_, col, 0.0, 0.5, omni=False, glow=1.0)
    add_light(cx, cz, cy, (1.0, 0.85, 0.6), 0.45, 15.0, omni=True)
    # Karussell (40 | 4): Kranz am Dachrand, Krone in der Mitte
    ring_lights(40.0, 4.0, 3.9, 5.2, 12, 0.9, 0.3, 8.5, phase=0.2, ground_every=2)
    add_light(40.0, 4.0, 6.5, (1.0, 0.8, 0.5), 0.5, 12.0, omni=True, glow=1.4)
    # Autoscooter (0 | 36): Dachkanten
    for (px, pz, col) in ((-4.8, 32.4, RIDE_COLS[2]), (4.8, 32.4, RIDE_COLS[3]), (-4.8, 39.6, RIDE_COLS[3]), (4.8, 39.6, RIDE_COLS[2]), (0.0, 32.2, RIDE_COLS[1]), (0.0, 39.8, RIDE_COLS[0])):
        add_light(px, pz, 3.6, col, 0.4, 9.0, omni=False, glow=0.9)
    # Festzelt (0 | -36): Kranz am Dach, Mastspitze
    ring_lights(0.0, -36.0, 5.4, 3.4, 10, 0.9, 0.34, 8.5, cols=[(1.0, 0.78, 0.4), (1.0, 0.4, 0.3), (1.0, 0.9, 0.55)], phase=0.1, ground_every=2)
    add_light(0.0, -36.0, 9.0, (1.0, 0.8, 0.45), 0.45, 12.0, omni=True)
    # Kinderkarussell (21,5 | 0)
    ring_lights(21.5, 0.0, 2.9, 2.5, 6, 0.6, 0.32, 6.5, cols=[(1.0, 0.65, 0.85), (0.6, 0.85, 1.0), (1.0, 0.9, 0.5)], ground_every=1)
    # Brunnen: farbiges Unterwasserlicht
    add_light(68.5, 0.0, 0.7, (0.4, 0.85, 1.0), 0.6, 9.0, omni=True)
    add_light(68.5, 0.0, 2.6, (1.0, 0.6, 0.9), 0.25, 6.0, omni=False)
    # Tor: Querbalken und Schild
    gx = fence_rect()[1]
    for zz in (-4.0, 0.0, 4.0):
        add_light(gx - 0.4, zz, 5.4, (1.0, 0.85, 0.55), 0.5, 8.0, omni=False)
    # Buden und Lose der Streckendatei (Laufzeit-Modelle ohne eigenes Licht)
    for p in data["props"]:
        if p["type"] == "ai" and p["model"] in ("jahrmarkt_bude", "jahrmarkt_losbude"):
            col = (1.0, 0.75, 0.42) if p["model"] == "jahrmarkt_bude" else (0.92, 0.6, 1.0)
            add_light(p["x"], p["z"], 3.4, col, 0.5, 7.0, omni=False, glow=0.0)


# ---------------------------------------------------------------- Karussell: Podest, Zaun mit Eingang, Wartende
def ring_deck(cx, cz, r0, r1, y, key, a0, a1, n, tile=3.0):
    """Ringsegment (Podest) von Winkel a0 bis a1 (Bogenmaß) als Trapeze."""
    out = []
    for i in range(n):
        s0 = a0 + (a1 - a0) * i / n
        s1 = a0 + (a1 - a0) * (i + 1) / n
        pts = [(cx + r0 * math.cos(s0), cz + r0 * math.sin(s0), y), (cx + r1 * math.cos(s0), cz + r1 * math.sin(s0), y),
               (cx + r1 * math.cos(s1), cz + r1 * math.sin(s1), y), (cx + r0 * math.cos(s1), cz + r0 * math.sin(s1), y)]
        out.append((key, pts, [(p[0] / tile, -p[1] / tile) for p in pts], None, [(0.9, 0.88, 0.85)] * 4))
    return out


def carousel_area():
    """Karussell (40 | 4): Holzpodest rund um das Fahrgeschäft, Zaun mit Eingang zur Kasse hin (Westseite), Wartende davor, Zuschauer am Zaun."""
    cx, cz = 40.0, 4.0
    gate = math.pi
    g = 0.17
    a0, a1 = gate + g, gate + 2 * math.pi - g
    y = GROUND_Y + 0.07
    FAIR.extend(ring_deck(cx, cz, 0.0, 4.3, y, "f_planken", 0.0, 2 * math.pi, 24))
    FAIR.extend(ring_deck(cx, cz, 4.3, 7.3, y, "f_planken", 0.0, 2 * math.pi, 36))
    ex_, ez_ = cx + 7.4 * math.cos(gate), cz + 7.4 * math.sin(gate)
    FAIR.extend(cbox(Frame((ex_ - 1.4, ez_), (0, 1), (-1, 0)), "f_planken", -1.5, 1.5, -1.5, 1.5, GROUND_Y, y, wood_col("roh"), 3.0, grad=(0.85, 1.0)))   # Eingangspodest
    # Kantenbrett des Podests
    pts = [(cx + 7.38 * math.cos(a0 + (a1 - a0) * i / 30), cz + 7.38 * math.sin(a0 + (a1 - a0) * i / 30)) for i in range(31)]
    for (p, q) in zip(pts, pts[1:]):
        t = (Vector(q) - Vector(p))
        L = t.length
        t.normalize()
        fr = Frame((Vector(p) + Vector(q)) / 2, t, Vector((-t.y, t.x)))
        FAIR.extend(cbox(fr, "k:farbe", -L / 2, L / 2, -0.07, 0.07, GROUND_Y, y + 0.03, shade(lin("a8703c"), 0.9), 1.0, grad=(0.8, 1.0), sides=(1, 1, 0, 0)))
    # Zaun: Bogen mit Öffnung bei 180 Grad (zur Kasse)
    fpts = [(cx + 7.4 * math.cos(a0 + (a1 - a0) * i / 34), cz + 7.4 * math.sin(a0 + (a1 - a0) * i / 34)) for i in range(35)]
    barrier_line(fpts, spacing=1.6)
    for sg in (-1, 1):                                               # Pfosten am Eingang
        a = gate + sg * (g - 0.01)
        px, pz = cx + 7.4 * math.cos(a), cz + 7.4 * math.sin(a)
        FAIR.extend(cyl("k:farbe", px, pz, 0.09, GROUND_Y, GROUND_Y + 1.25, 8, PAL["rot"], cap=True))
        FAIR.extend(cyl("k:farbe", px, pz, 0.11, GROUND_Y + 1.15, GROUND_Y + 1.25, 8, PAL["weiss"], cap=True))
    # Besucher: Wartende am Eingang, im Podest, am Zaun
    queue_line((35.6, -2.8), (33.0, 2.4), 8, 100)
    queue_line((34.2, -3.4), (31.6, 1.8), 6, 100)
    for k in range(10):
        a = 2 * math.pi * k / 10 + 0.3
        person(cx + 5.8 * math.cos(a), cz + 5.8 * math.sin(a), math.degrees(a) + 180, 0.95, kid=k % 3 == 0)
    for k in range(9):
        a = 2 * math.pi * (k + 0.5) / 9 + 0.9
        family(cx + 8.7 * math.cos(a), cz + 8.7 * math.sin(a), math.degrees(a) + 180)


# ---------------------------------------------------------------- Leben: Familien und Gruppen auf den Wegen
def ambient_life():
    r_ = random.Random(5)
    # Gassen der beiden Täler
    for sgn in (-1, 1):
        for k in range(9):
            zz = sgn * (12.5 + k * 2.55 + r_.uniform(-0.4, 0.4))
            xx = r_.uniform(-2.5, 2.5)
            d = 90 if r_.random() < 0.5 else 270
            if r_.random() < 0.4:
                family(xx, zz, d)
            else:
                people(xx, zz, r_.choice([2, 3, 4]), 1.0, d, 25)
    # Eingangsplatz: Familien und Paare Richtung Tor und Brunnen
    for k in range(14):
        x_ = 63.0 + r_.uniform(0, 21)
        z_ = r_.uniform(-12.5, 12.5)
        if math.hypot(x_ - 68.5, z_) < 4.2:
            continue
        if r_.random() < 0.5:
            family(x_, z_, 0 if r_.random() < 0.6 else 180)
        else:
            people(x_, z_, r_.choice([2, 3]), 0.9, r_.uniform(0, 360), 90)
    for k in range(10):                                                # am Brunnenrand
        a = 2 * math.pi * k / 10
        person(68.5 + 3.8 * math.cos(a), math.sin(a) * 3.8, math.degrees(a) + 180 + r_.uniform(-30, 30), 0.95)
    # Riesenrad: Warteschlange, Gruppen am Kassenhäuschen und auf den Wegen
    queue_line((-42.0, 3.0), (-42.0, 9.6), 10, 270)
    for (x_, z_) in ((-36.0, 4.5), (-47.0, 8.0), (-35.0, -2.5), (-50.0, -4.0), (-38.0, 9.5), (-45.0, 1.0), (-52.0, 6.0)):
        family(x_, z_, r_.uniform(0, 360))
    for (x_, z_) in ((-33.0, 2.0), (-31.0, -3.0), (-55.0, 9.0), (-30.0, 8.0), (-48.0, -9.0), (-40.0, -9.0)):
        people(x_, z_, 3, 1.1, r_.uniform(0, 360), 120)
    # Karussell-Innenraum (Wege, Bänke, Kinderkarussell)
    for (x_, z_) in ((26.5, -6.0), (31.0, 10.5), (36.0, 9.0), (46.0, 10.0), (47.0, -5.0), (30.0, 5.0)):
        family(x_, z_, r_.uniform(0, 360))
    for k in range(6):                                                 # Kinderkarussell: Eltern am Rand, Kinder mit Ballons
        a = 2 * math.pi * k / 6 + 0.4
        person(21.5 + 4.6 * math.cos(a), 4.6 * math.sin(a) * 0.9, math.degrees(a) + 180, 1.0, kid=False)
    # Biergarten: Gruppen zwischen den Tischen
    for sgn in (-1, 1):
        for k in range(4):
            people(sgn * (9.0 + k * 3.4), -41.4 + r_.uniform(-0.5, 0.5), 3, 1.1, r_.uniform(0, 360), 120)
        people(sgn * 16.0, -34.2, 3, 1.4, r_.uniform(0, 360), 120)
    # Autoscooter und Zelt
    for k in range(6):
        family(r_.uniform(-7, 7), 29.0 + r_.uniform(-1, 1), 90)
    for k in range(5):
        people(r_.uniform(-6, 6), -29.5 + r_.uniform(-1.5, 1.5), 3, 1.2, 90, 100)
    # Biergarten West und Ost (Taschen an der Kreuzung)
    for (x_, z_) in ((-27.0, 1.5), (-20.0, 6.5), (-24.0, -1.5), (16.0, 3.0), (18.5, -3.5)):
        people(x_, z_, 3, 1.1, r_.uniform(0, 360), 120)


# ---------------------------------------------------------------- Hof der Schausteller: Lagerplatz, Stühle, Wasser
def tarp_stack(x, z, ang, w=2.6, d=1.6, h=1.1, col=None):
    """Abgedeckter Stapel (Plane, Spanngurte)."""
    fr = frame_at(x, z, ang)
    if not try_place(x, z, fr.u.x, fr.u.y, w / 2 + 0.2, d / 2 + 0.2, margin=3.0, what="Plane"):
        return False
    c = col or frng.choice([lin("2a5fa8"), lin("3d7a4f"), lin("a8a8a0")])
    y = GROUND_Y
    FAIR.extend(cbox(fr, "k:farbe", -w / 2, w / 2, -d / 2, d / 2, y + 0.12, y + h, c, 2.0, grad=(0.75, 1.0)))
    FAIR.extend(cbox(fr, "k:farbe", -w / 2 - 0.05, w / 2 + 0.05, -d / 2 - 0.05, d / 2 + 0.05, y, y + 0.14, lin("b48a55"), 1.0, grad=(0.8, 1.0)))   # Palette
    for a in (-w * 0.28, w * 0.28):                                                                                                          # Spanngurte
        FAIR.extend(cbox(fr, "k:farbe", a - 0.04, a + 0.04, -d / 2 - 0.01, d / 2 + 0.01, y + 0.13, y + h + 0.01, PAL["gelb"], 1.0, grad=(1, 1)))
    collide_rect(x, z, fr.u.x, fr.u.y, w / 2 + 0.05, d / 2 + 0.05, h, "mauer")
    return True


def crate_stack(x, z, ang):
    """Getränkekisten (gelb, rot, blau) in drei Lagen."""
    fr = frame_at(x, z, ang)
    if not try_place(x, z, fr.u.x, fr.u.y, 0.95, 0.65, margin=3.0, what="Kisten"):
        return False
    y = GROUND_Y
    cols = [lin("f2c21b"), lin("d63a2a"), lin("2d5fc4"), lin("2f9a4c")]
    for layer in range(3):
        for i in range(3):
            for j in range(2):
                a0, b0 = -0.9 + i * 0.6, -0.6 + j * 0.6
                if layer == 2 and (i + j) % 2:
                    continue
                FAIR.extend(cbox(fr, "k:farbe", a0 + 0.02, a0 + 0.58, b0 + 0.02, b0 + 0.58, y + layer * 0.3, y + (layer + 1) * 0.3 - 0.01, cols[(i + j + layer) % 4], 1.0, grad=(0.8, 1.0)))
    collide_rect(x, z, fr.u.x, fr.u.y, 0.92, 0.62, 0.9, "mauer")
    return True


def water_tank(x, z):
    """1000-l-Wassertank im Gitterrahmen (IBC) auf Palette."""
    fr = frame_at(x, z, 0)
    if not try_place(x, z, 1, 0, 0.65, 0.6, margin=3.0, what="Tank"):
        return False
    y = GROUND_Y
    FAIR.extend(cbox(fr, "k:farbe", -0.6, 0.6, -0.5, 0.5, y, y + 0.14, lin("b48a55"), 1.0, grad=(0.8, 1.0)))
    FAIR.extend(cbox(fr, "k:farbe", -0.56, 0.56, -0.46, 0.46, y + 0.14, y + 1.1, lin("d9dde0"), 1.0, grad=(0.85, 1.0)))
    for a in (-0.57, -0.19, 0.19, 0.57):
        FAIR.extend(cbox(fr, "k:farbe", a - 0.012, a + 0.012, -0.5, 0.5, y + 0.14, y + 1.12, PAL["stahl"], 1.0, grad=(1, 1), sides=(0, 0, 0, 0)))
    FAIR.extend(cyl("k:farbe", x, z, 0.12, y + 1.1, y + 1.16, 8, PAL["dgrau"]))
    collide_rect(x, z, 1, 0, 0.62, 0.55, 1.2, "mauer")
    return True


def camp_set(x, z, ang):
    """Campingtisch mit zwei Klappstühlen und kleinem Grill davor (Schausteller sitzen vor ihrem Wohnwagen)."""
    fr = frame_at(x, z, ang)
    if not try_place(x, z, fr.u.x, fr.u.y, 0.95, 0.75, margin=3.0, what="Camping"):
        return False
    y = GROUND_Y
    FAIR.extend(cbox(fr, "k:farbe", -0.4, 0.4, -0.35, 0.35, y + 0.68, y + 0.72, lin("d9b88a"), 1.0, grad=(1, 1)))
    for a in (-0.35, 0.35):
        for b in (-0.3, 0.3):
            FAIR.extend(cbox(fr, "k:farbe", a - 0.02, a + 0.02, b - 0.02, b + 0.02, y, y + 0.68, PAL["stahl"], 1.0, grad=(1, 1), top=False))
    for sgn in (-1, 1):
        face_ = math.degrees(math.atan2(-sgn * fr.v.y, -sgn * fr.v.x))
        cf = frame_at(*fr.pt(0, sgn * 0.7), face_)
        c = frng.choice([PAL["blau"], PAL["rot"], PAL["gruen"], PAL["orange"]])
        FAIR.extend(cbox(cf, "k:farbe", -0.2, 0.2, -0.22, 0.22, y + 0.36, y + 0.4, c, 1.0, grad=(1, 1)))
        FAIR.extend(cbox(cf, "k:farbe", -0.22, -0.18, -0.22, 0.22, y + 0.4, y + 0.8, c, 1.0, grad=(0.9, 1.0)))
        for a in (-0.18, 0.18):
            for b in (-0.2, 0.2):
                FAIR.extend(cbox(cf, "k:farbe", a - 0.012, a + 0.012, b - 0.012, b + 0.012, y, y + 0.36, PAL["stahl"], 1.0, grad=(1, 1), top=False))
        if frng.random() < 0.6:
            person(*fr.pt(0, sgn * 0.7), face_, 0.9, y=GROUND_Y + 0.4, seated=True, guard=False, kid=False)
    g = fr.pt(1.3, 0)
    FAIR.extend(cyl("k:farbe", g.x, g.y, 0.28, y + 0.55, y + 0.78, 10, PAL["schwarz"], r_top=0.3, cap=True))
    for k_ in (-1, 1):
        FAIR.extend(cbox(Frame(g, fr.u, fr.v), "k:farbe", k_ * 0.2 - 0.02, k_ * 0.2 + 0.02, -0.02, 0.02, y, y + 0.55, PAL["stahl"], 1.0, grad=(1, 1), top=False))
    return True


def ride_trailer(x, z, ang):
    """Tieflader mit Fahrgeschäftsteilen: Ladefläche, Traversenstücke (Aluminium), zwei Gondelschalen, Achsen mit Doppelrädern längs der Fahrtrichtung, Deichsel."""
    fr = frame_at(x, z, ang)
    if not try_place(x, z, fr.u.x, fr.u.y, 5.6, 1.6, margin=3.0, what="Tieflader"):
        return False
    y = GROUND_Y
    P = FAIR
    P += cbox(fr, "k:farbe", -4.8, 4.8, -1.25, 1.25, y + 0.78, y + 0.98, lin("3a3d44"), 2.0, grad=(0.8, 1.0))
    P += cbox(fr, "k:farbe", -4.6, 4.6, -0.9, 0.9, y + 0.55, y + 0.78, PAL["dgrau"], 2.0, grad=(0.8, 1.0), top=False)
    for a in (-3.6, -2.6, 2.6, 3.6):
        for sg in (-1, 1):
            P += cbox(fr, "k:farbe", a - 0.5, a + 0.5, sg * 1.35 - 0.15, sg * 1.35 + 0.15, y, y + 1.0, PAL["schwarz"], 1.0, grad=(0.8, 1.0))
    for b in (-0.8, 0.0, 0.8):
        P += cbox(fr, "k:farbe", -4.4, 2.0, b - 0.14, b + 0.14, y + 0.98, y + 1.34, lin("b9bec6"), 1.0, grad=(0.8, 1.0))
        for a in range(-4, 2, 1):
            P += cbox(fr, "k:farbe", a + 0.0, a + 0.08, b - 0.145, b + 0.145, y + 0.98, y + 1.35, lin("7c828a"), 1.0, grad=(1, 1), sides=(0, 0, 0, 0))
    for k, col in enumerate((lin("c8442f"), lin("2d5fc4"))):
        q = fr.pt(3.3, -0.6 + k * 1.2)
        P += dome("k:farbe", q.x, q.y, y + 1.0, 0.62, 8, 3, col, lat0=-0.2)
    P.append(poly("k:farbe", [(*fr.pt(4.8, -1.0), y + 0.88), (*fr.pt(4.8, 1.0), y + 0.88), (*fr.pt(6.6, 0.12), y + 0.9), (*fr.pt(6.6, -0.12), y + 0.9)], PAL["dgrau"], None))
    collide_rect(x, z, fr.u.x, fr.u.y, 4.9, 1.45, 1.4, "mauer")
    return True


def gondola_pods(x, z, ang):
    """Ersatzgondeln des Riesenrads auf Paletten (vier Schalen mit Dach), bunt."""
    fr = frame_at(x, z, ang)
    if not try_place(x, z, fr.u.x, fr.u.y, 3.5, 1.1, margin=3.0, what="Gondeln"):
        return False
    y = GROUND_Y
    cols = [lin("c8442f"), lin("2d5fc4"), lin("e8b81c"), lin("2f9a4c")]
    for k in range(4):
        q = fr.pt(-2.55 + k * 1.7, 0.0)
        pf = Frame(q, fr.u, fr.v)
        FAIR.extend(cbox(pf, "k:farbe", -0.75, 0.75, -0.55, 0.55, y, y + 0.14, lin("b48a55"), 1.0, grad=(0.8, 1.0)))
        FAIR.extend(dome("k:farbe", q.x, q.y, y + 0.14, 0.7, 8, 3, cols[k], lat0=-0.1))
        FAIR.extend(cyl("k:farbe", q.x, q.y, 0.78, y + 0.9, y + 0.96, 8, shade(cols[k], 0.8), cap=True))
    collide_rect(x, z, fr.u.x, fr.u.y, 3.5, 0.95, 1.0, "mauer")
    return True


def skip_container(x, z, ang):
    """Absetzmulde (Bauschutt): gelbe Wanne mit schrägen Seiten und Abfall."""
    fr = frame_at(x, z, ang)
    if not try_place(x, z, fr.u.x, fr.u.y, 2.6, 1.3, margin=3.0, what="Mulde"):
        return False
    y = GROUND_Y
    c = lin("e0a81c")
    P = FAIR
    for sg in (-1, 1):
        P.append(poly("k:farbe", [(*fr.pt(-2.4, sg * 1.0), y + 0.1), (*fr.pt(2.4, sg * 1.0), y + 0.1), (*fr.pt(2.6, sg * 1.25), y + 1.2), (*fr.pt(-2.6, sg * 1.25), y + 1.2)], c, (fr.v.x * sg, fr.v.y * sg)))
    for sg in (-1, 1):
        P.append(poly("k:farbe", [(*fr.pt(sg * 2.4, -1.0), y + 0.1), (*fr.pt(sg * 2.4, 1.0), y + 0.1), (*fr.pt(sg * 2.6, 1.25), y + 1.2), (*fr.pt(sg * 2.6, -1.25), y + 1.2)], shade(c, 0.9), (fr.u.x * sg, fr.u.y * sg)))
    P.append(poly("k:farbe", [(*fr.pt(-2.3, -0.95), y + 0.9), (*fr.pt(2.3, -0.95), y + 0.9), (*fr.pt(2.3, 0.95), y + 0.9), (*fr.pt(-2.3, 0.95), y + 0.9)], lin("5a4a3a"), None))
    krr = random.Random(int(x * 3 + z))
    for k in range(9):
        q = fr.pt(krr.uniform(-1.9, 1.9), krr.uniform(-0.7, 0.7))
        P += cbox(frame_at(q.x, q.y, krr.uniform(0, 360)), "k:farbe", -0.3, 0.3, -0.2, 0.2, y + 0.9, y + 0.9 + krr.uniform(0.15, 0.5), lin(krr.choice(["9a8a7a", "b48a55", "6b6e74", "c9c2b0"])), 1.0, grad=(0.8, 1.0))
    collide_rect(x, z, fr.u.x, fr.u.y, 2.6, 1.3, 1.3, "mauer")
    return True


def huepfburg(x, z, ang):
    """Hüpfburg (aufgeblasen, 6 x 5 m): Bodenwulst, Wände aus Luftwülsten, vier Ecktürme mit Kegeldach, Eingang auf der +v-Seite, Gebläse; Kinder springen darin,
    Eltern warten davor."""
    fr = frame_at(x, z, ang)
    if not try_place(x, z, fr.u.x, fr.u.y, 3.4, 2.9, margin=2.5, what="Hüpfburg"):
        return False
    y = GROUND_Y
    P = FAIR
    cols = [PAL["rot"], PAL["gelb"], PAL["blau"], PAL["gruen"]]
    A, B = 3.0, 2.5
    P += cbox(fr, "k:farbe", -A, A, -B, B, y, y + 0.35, PAL["blau"], 2.0, grad=(0.8, 1.0))
    P += cbox(fr, "k:farbe", -A + 0.45, A - 0.45, -B + 0.45, B - 0.45, y + 0.36, y + 0.4, lin("f2c21b"), 2.0, grad=(1, 1), sides=(0, 0, 0, 0))
    for k in range(6):                                                              # Rückwand und Seitenwände aus Wülsten
        a0 = -A + k * (2 * A) / 6
        P += cbox(fr, "k:farbe", a0 + 0.04, a0 + 2 * A / 6 - 0.04, -B, -B + 0.55, y + 0.35, y + 1.7, cols[k % 4], 1.0, grad=(0.85, 1.0))
    for sg in (-1, 1):
        for k in range(5):
            b0 = -B + 0.5 + k * (2 * B - 1.0) / 5
            P += cbox(fr, "k:farbe", sg * A - (0.55 if sg > 0 else 0.0), sg * A + (0.0 if sg > 0 else 0.55), b0 + 0.04, b0 + (2 * B - 1.0) / 5 - 0.04, y + 0.35, y + 1.7, cols[(k + 1) % 4], 1.0, grad=(0.85, 1.0))
    for (a0, a1) in ((-A, -0.9), (0.9, A)):                                         # Frontwand mit Eingang
        P += cbox(fr, "k:farbe", a0, a1, B - 0.55, B, y + 0.35, y + 1.3, PAL["rot"], 1.0, grad=(0.85, 1.0))
    P += cbox(fr, "k:farbe", -0.9, 0.9, B - 0.55, B, y + 0.35, y + 0.8, PAL["gelb"], 1.0, grad=(0.85, 1.0))
    for k, (a, b) in enumerate(((-A, -B), (A, -B), (A, B), (-A, B))):               # Ecktürme
        q = fr.pt(a, b)
        P += cyl("k:farbe", q.x, q.y, 0.65, y + 0.35, y + 2.6, 8, cols[k], grad=(0.8, 1.0))
        P += cyl("k:farbe", q.x, q.y, 0.78, y + 2.6, y + 3.5, 8, cols[(k + 2) % 4], r_top=0.04, cap=False, grad=(0.85, 1.0))
    q = fr.pt(A + 0.9, 0.0)
    P += cbox(frame_at(q.x, q.y, ang), "k:farbe", -0.35, 0.35, -0.3, 0.3, y, y + 0.55, PAL["dgrau"], 1.0, grad=(0.8, 1.0))   # Gebläse
    P.append(poly("k:farbe", [(*fr.pt(A, -0.14), y + 0.2), (*fr.pt(A + 0.6, -0.14), y + 0.2), (*fr.pt(A + 0.6, 0.14), y + 0.2), (*fr.pt(A, 0.14), y + 0.2)], PAL["schwarz"], None))
    collide_rect(x, z, fr.u.x, fr.u.y, A + 0.1, B + 0.1, 1.7, "mauer")
    light_blockers.append([round(x, 3), round(z, 3), A + 0.05, B + 0.05, round(math.radians(ang), 4)])
    add_light(*fr.pt(0.0, B + 1.2), 2.8, (1.0, 0.7, 0.85), 0.4, 7.5, omni=False)
    for k in range(4):                                                              # Kinder springen drinnen (Hüpfhöhe 0,3 bis 0,9 m)
        c = fr.pt(frng.uniform(-A + 1.0, A - 1.0), frng.uniform(-B + 1.0, B - 1.5))
        HQ.append((c.x, c.y, frng.uniform(0, 360), True, None, False, False))
    for k in range(5):                                                              # Wartende am Eingang
        c = fr.pt(-1.2 + k * 0.55, B + 0.8 + frng.uniform(0, 0.8))
        HQ.append((c.x, c.y, math.degrees(math.atan2(-fr.v.y, -fr.v.x)), frng.random() < 0.6, None, False, True))
    return True


def place_huepfburg():
    """Hüpfburg an der ersten freien Stelle einer Kandidatenliste (Schleifeninnenräume, nahe den Wegen) bauen."""
    QUIET[0] = 1
    ok = False
    for (cx, cz, a) in ((79.0, -8.0, 0), (79.0, 8.0, 180), (-52.0, -9.0, 90), (-36.0, 10.5, 0), (47.0, 11.0, 180), (50.0, -7.0, 270), (26.0, 12.0, 0), (-30.0, -9.5, 180)):
        for (dx, dz) in ((0, 0), (1.5, 0), (-1.5, 0), (0, 1.5), (0, -1.5), (2.5, 2.5), (-2.5, -2.5), (2.5, -2.5), (-2.5, 2.5)):
            if huepfburg(cx + dx, cz + dz, a):
                ok = True
                break
        if ok:
            break
    QUIET[0] = 0
    if not ok:
        print("DIORAMA fair: keine freie Stelle für die Hüpfburg")


def build_yard_edge():
    """Westrand und Ecken des Hofs: Tieflader mit Fahrgeschäftsteilen, Ersatzgondeln, Mulde, Sattelauflieger (bisher kahl und nie aus der Nähe geprüft)."""
    for (x, z, a) in ((-97.0, -17.0, 90), (-97.0, 12.0, 90), (-97.0, 24.0, 90)):
        near(ride_trailer, x, z, a, r_max=3.6)
    for (x, z, a) in ((-93.0, 3.0, 0), (-93.0, -8.0, 0), (-93.0, 17.5, 0)):
        near(gondola_pods, x, z, a, r_max=3.0)
    for (x, z, a) in ((-79.0, -45.0, 20), (-79.0, 47.0, 160)):
        near(skip_container, x, z, a, r_max=3.0)
    for (x, z) in ((-96.0, -53.0), (-96.0, 53.0), (-84.0, -53.0), (-84.0, 53.0)):
        near(truck, x, z, 90, "kasten", r_max=3.0)
    for (x, z) in ((-76.5, -40.0), (-76.5, 40.0)):
        near(camp_set, x, z, 90, r_max=3.0)


def build_yard_details():
    """Lagerplatz, Wasser, Sitzplätze und Fahrzeuge im Hof: der Hof sieht bewohnt und genutzt aus."""
    for (x, z, a) in ((-98.0, -10.0, 0), (-98.0, 6.0, 0), (-79.0, 17.0, 90), (-79.0, -19.0, 90), (-96.0, 20.0, 0)):
        near(tarp_stack, x, z, a, r_max=2.7)
    for (x, z, a) in ((-80.0, -12.0, 0), (-80.0, 20.0, 90), (-98.0, -20.0, 0), (-98.0, 24.0, 0)):
        near(crate_stack, x, z, a, r_max=2.7)
    for (x, z) in ((-96.5, 14.0), (-96.5, -3.0), (-80.0, -25.0)):
        near(water_tank, x, z, r_max=2.7)
    # Sitzplätze vor den Wohnwagen (in den Lücken der Reihen)
    for zz in (-43.0, -37.0, -31.0, 31.0, 37.0, 43.0):
        near(camp_set, -93.6, zz, 90, r_max=1.5)
    for zz in (-43.0, -37.0, 31.0, 43.0):
        near(camp_set, -86.4, zz, 270, r_max=1.5)
    # Gespräche und Pausen
    for (x_, z_) in ((-90.0, -3.0), (-88.0, 8.0), (-83.0, -20.0), (-78.5, 3.0), (-92.0, 28.0), (-86.0, -33.0)):
        people(x_, z_, 3, 1.2, frng.uniform(0, 360), 120)


def traffic_cone(x, z):
    FAIR.extend(cyl("k:farbe", x, z, 0.16, GROUND_Y, GROUND_Y + 0.55, 6, lin("ee6a1c"), r_top=0.035, cap=True))
    FAIR.extend(cbox(Frame((x, z), (1, 0), (0, 1)), "k:farbe", -0.19, 0.19, -0.19, 0.19, GROUND_Y, GROUND_Y + 0.03, PAL["schwarz"], 1.0, grad=(1, 1)))


def build_parking_details():
    """Parkplätze: Einweiser in Warnwesten, Leitkegel an den Einfahrten, Besucher auf dem Weg zu den Autos."""
    orange = lin("ee7d22")
    for (x, z, a) in ((64.0, 18.0, 180), (64.0, -18.0, 180), (86.0, 19.0, 0), (86.0, -19.0, 0)):
        if not in_placed(x, z):
            human(x, z, a, kid=False, hat=False, top=orange)
    for sgn in (-1, 1):
        for k in range(8):
            traffic_cone(61.8 + k * 3.2, sgn * 19.6)
        for k in range(4):
            traffic_cone(87.5, sgn * (21.0 + k * 2.4))
    for sgn in (-1, 1):                                                # Besucher in den Gassen zwischen den Reihen
        for j in range(4):
            for k in range(3):
                zz = sgn * (25.0 + 7.0 * j)
                if frng.random() < 0.5:
                    family(63.5 + k * 8.5 + frng.uniform(-1.5, 1.5), zz, frng.choice([0, 180]))
                else:
                    people(63.5 + k * 8.5 + frng.uniform(-1.5, 1.5), zz, 2, 0.8, frng.choice([0, 180]), 20)


# ---------------------------------------------------------------- Hooks
def theme_ground():
    fair_ground()
    fair_far_surround()


def theme_scenery():
    reserve_runtime()
    for name, fn in (("Hüpfburg", place_huepfburg), ("Eingangsplatz", fair_plaza), ("Täler", build_valleys), ("Schleifeninnenräume", build_loop_interiors), ("Taschen", build_pockets), ("Zuschauer", build_spectators), ("Biergarten", build_beer_garden),
                     ("Hof und Parkplatz", build_backstage_and_parking), ("Zaun und Bäume", build_fence_and_trees), ("Masten", build_poles_and_strings)):
        try:
            fn()
        except Exception as error:                 # ein Fehler in einem Bereich soll die übrigen nicht verhindern, aber nicht untergehen
            import traceback
            print("DIORAMA fair FEHLER in", name, ":", error)
            traceback.print_exc()
    for name, fn in (("Karussell", None), ("Leben", ambient_life), ("Hofrand", build_yard_edge), ("Hof", build_yard_details), ("Parkplatzdetails", build_parking_details), ("Lichter", ride_lights), ("Lichtmasten", light_masts)):
        if fn is None:
            continue
        try:
            fn()
        except Exception as error:
            import traceback
            print("DIORAMA fair FEHLER in", name, ":", error)
            traceback.print_exc()
    flush_people()
    if FLOOR:
        objs_ground.append(mesh_object("Boden_pflaster", FLOOR))
    mesh_objects("Fair", FAIR)
    for (lx, lz, tx, tz) in LAMPS:
        lamp_post(lx, lz, tx, tz)
    fair_ao()
    print("DIORAMA fair: Flächen", len(FAIR), "Besucher", HUM_STATS, "Hindernisse", len(colliders), "Lichter", len(extra_lights))


def theme_bake_hidden():
    return []


def theme_layout(layout):
    fix_vertex_colors()


def fix_vertex_colors():
    """Kern-Eigenheit umgehen: mesh_object legt das Farbattribut an, setzt es aber nicht aktiv; der glTF-Export (ACTIVE) schreibt dann COLOR_0 weiß
    und die Daten als COLOR_1, die Godot nicht liest. Hier das Attribut aktiv schalten (Hinweis an den Kern in docs/dioramen/fair.md)."""
    for o in scene.objects:
        me = getattr(o, 'data', None)
        ca = getattr(me, 'color_attributes', None)
        if ca is not None and len(ca) and ca.active_color is None:
            ca.active_color = ca[0]
            ca.render_color_index = 0
