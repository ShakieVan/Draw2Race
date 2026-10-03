"""Themenmodul "kids" (Toy Box Speedway): Kinderzimmer von oben, die Autos sind Spielzeugautos (Maßstab etwa 1 : 50).

Wird von tools/diorama.py in dessen Globals ausgeführt (siehe docs/dioramen/README.md); Beschreibung und Entscheidungen: docs/dioramen/kids.md.
Straße: "runtime" (orange Spielzeugbahn, Rampe, Lücke und Looping baut das Spiel), der Boden liegt auf 0,08.
Gebacken: Parkett aus einzelnen Dielen mit Fugen (Atlas), Spielteppich mit Fransen, Wände und Fußleisten am Rand der Fläche, Spielzeugregal,
Bettecke mit Nachttisch und Lampe, Spielzeugtruhe, verstreute Bausteine, Murmeln, Buntstifte, Zeichnung und Lineal, Fensterlicht auf dem Boden.
Die KI-Bauteile der Streckendatei (Teddy, Ball, Bauklötze, Bausteinturm, Bücher, Buntstifte, Holzeisenbahn, Kreisel) bleiben Laufzeit-Bauteile;
ihren Kontaktschatten backt kids_ao(). Nachts leuchtet nur die Nachttischlampe (K_lampe).
Seit 03.10.2026 (rev 2): Abkürzung über ein Lineal als Wippe. Das Lineal ist Laufzeit (game/assets/props/kinder_lineal.glb aus tools/make_kids_ruler.py);
das Diorama backt den Filzstift darunter, legt die Abkürzung als Straßen-Spielteppich aus und hält ihren Korridor frei (Abschnitt "Lineal-Wippe").
"""
_GEOM = os.path.join(os.path.dirname(os.path.abspath(__file__)), "make_fair_kids_geom.py")
with open(_GEOM, encoding="utf-8") as _fh:
    exec(compile(_fh.read(), _GEOM, "exec"), globals())

THEME_CFG = {
    "road": "runtime",
    "margin": 26.0,
    "baked": [],
}

PROP_FOOT = {"kinder_teddy": (4.3, 3.6), "kinder_ball": (3.2, 3.2), "kinder_bauklotz": (1.5, 1.5), "kinder_bausteinturm": (2.0, 1.8), "kinder_buch": (6.2, 4.7),
             "kinder_buntstifte": (5.0, 3.2), "kinder_holzeisenbahn": (10.3, 2.8), "kinder_kreisel": (1.9, 1.9)}
PLANK_W, PLANK_L, N_ATLAS = 3.0, 24.0, 8
WALL_H = 36.0
LEAN = {"west": 0.47, "east": 0.47, "north": 0.47, "south": 0.85}      # Wände kippen nach außen: kein Schattenwurf der Sonne (kommt von Südwesten) in den Raum

KIDS = []            # Szenerie (ein Objekt je Material)
KFLOOR = []          # Boden-Auflagen mit Umgebungsverdeckung (Teppich, Papier ...)
krng = random.Random(41)
QUIET = [0]


def KT(name):
    return os.path.normpath(os.path.join(PROPS, "..", "dio", "kids", name))


def theme_materials():
    M["k_parkett"] = material("D_Parkett", KT("parkett.jpg"), 0.42, KT("parkett_n.jpg"))
    M["k_licht"] = material("D_ParkettLicht", KT("parkett_licht.jpg"), 0.42, KT("parkett_n.jpg"))
    M["k_teppich"] = material("D_Teppich", KT("teppich.jpg"), 0.95, KT("teppich_n.jpg"))
    M["k_wolle"] = material("D_Wolle", KT("wolle.jpg"), 0.95, KT("wolle_n.jpg"))
    M["k_tapete"] = material("D_Tapete", KT("tapete.jpg"), 0.9)
    M["k_zeichnung"] = material("D_Zeichnung", KT("zeichnung.jpg"), 0.9)
    M["k_lineal"] = material("D_Lineal", KT("lineal.jpg"), 0.6)
    M["k_truhe"] = material("D_Truhe", KT("truhe.jpg"), 0.7)
    M["k_spiel"] = material("D_Spiel", KT("spiel.jpg"), 0.7)
    M["k_sand"] = material("D_Sand", KT("sand.jpg"), 0.95, KT("sand_n.jpg"))


PAL = {"rot": lin("d63a2a"), "gelb": lin("f2c21b"), "blau": lin("2d5fc4"), "gruen": lin("2f9a4c"), "weiss": lin("f1ede2"), "orange": lin("ee7d22"), "rosa": lin("ee6fa8"),
       "lila": lin("7a3a9a"), "tuerkis": lin("1fa7b8"), "holz": lin("c48a52"), "holzhell": lin("deb882"), "holzdunkel": lin("7d5230"), "stahl": lin("a9adb3"),
       "creme": lin("f2eee4"), "schwarz": lin("17181a"), "braun": lin("8a5a34")}
TOYCOLS = [PAL["rot"], PAL["gelb"], PAL["blau"], PAL["gruen"], PAL["orange"], PAL["weiss"]]


# ---------------------------------------------------------------- Parkett
def col_offset(c):
    return random.Random(900 + c).uniform(0.0, PLANK_L)


def plank_style(c, k):
    r_ = random.Random(c * 1009 + k * 31 + 7)
    return r_.randrange(N_ATLAS), r_.random() < 0.5, r_.random() < 0.5, r_.uniform(0.93, 1.06)


def floor_rect(key, xa, xb, za, zb, y, tone=True):
    """Rechteck als Dielen: wird an Dielenspalten und -fugen geteilt, jede Diele holt ihr Stück aus dem Atlas (Maserung, Spiegelung)."""
    parts = []
    c0 = int(math.floor((xa - x0) / PLANK_W + 1e-9))
    c1 = int(math.floor((xb - x0) / PLANK_W - 1e-9))
    for c in range(c0, c1 + 1):
        cx0, cx1 = x0 + c * PLANK_W, x0 + (c + 1) * PLANK_W
        sx0, sx1 = max(xa, cx0), min(xb, cx1)
        if sx1 - sx0 < 1e-5:
            continue
        origin = z0 - col_offset(c)
        k0 = int(math.floor((za - origin) / PLANK_L + 1e-9))
        k1 = int(math.floor((zb - origin) / PLANK_L - 1e-9))
        for k in range(k0, k1 + 1):
            ps = origin + k * PLANK_L
            sz0, sz1 = max(za, ps), min(zb, ps + PLANK_L)
            if sz1 - sz0 < 1e-5:
                continue
            idx, fu, fv, tn = plank_style(c, k)
            f0, f1 = (sx0 - cx0) / PLANK_W, (sx1 - cx0) / PLANK_W
            if fu:
                f0, f1 = 1.0 - f0, 1.0 - f1
            v0, v1 = (sz0 - ps) / PLANK_L, (sz1 - ps) / PLANK_L
            if fv:
                v0, v1 = 1.0 - v0, 1.0 - v1
            inset = 0.0
            ua, ub = (idx + f0) / N_ATLAS, (idx + f1) / N_ATLAS
            corners_ = [(sx0, sz0, y), (sx1, sz0, y), (sx1, sz1, y), (sx0, sz1, y)]
            uvs = [(ua, v0), (ub, v0), (ub, v1), (ua, v1)]
            t_ = tn if tone else 1.0
            parts.append((key, corners_, uvs, None, [(t_, t_ * 0.995, t_ * 0.985)] * 4))
    return parts


# ---------------------------------------------------------------- Hilfen
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


def try_place(cx, cz, ux, uz, ha, hb, margin=3.5, what="", inside_room=True):
    poly_ = rect_poly(cx, cz, ux, uz, ha, hb)
    pts = edge_pts(poly_)
    if inside_room and not all(x0 + 1.0 <= p[0] <= x1 - 1.0 and z0 + 1.0 <= p[1] <= z1 - 1.0 for p in pts):
        if not QUIET[0]:
            print("DIORAMA kids: abgelehnt (Raumrand)", what, round(cx, 1), round(cz, 1))
        return False
    if road_gap(pts) < HW + margin:
        if not QUIET[0]:
            print("DIORAMA kids: abgelehnt (Straße)", what, round(cx, 1), round(cz, 1))
        return False
    hit = next((q for q in placed if overlaps(poly_, q)), None)
    if hit is not None:
        if not QUIET[0]:
            print("DIORAMA kids: abgelehnt (belegt)", what, round(cx, 1), round(cz, 1))
        return False
    placed.append(poly_)
    return True


def keep_out(cx, cz, ux, uz, ha, hb):
    placed.append(rect_poly(cx, cz, ux, uz, ha, hb))


def reserve_runtime():
    for p in data["props"]:
        if p["type"] == "ai":
            hx, hz = PROP_FOOT.get(p["model"], (2.0, 2.0))
            r = math.radians(float(p.get("rot", 0.0)))
            keep_out(p["x"], p["z"], math.cos(r), math.sin(r), hx + 0.8, hz + 0.8)


def band(fr, A, B, d0, d1, y, key, col):
    """Rahmenband zwischen den Insets d0 und d1 eines Rechtecks (Halbmaße A, B) als vier Trapeze."""
    P = lambda a, b: (*fr.pt(a, b), y)
    out = []
    for (p0, p1, p2, p3) in (
        ((-A + d0, -B + d0), (A - d0, -B + d0), (A - d1, -B + d1), (-A + d1, -B + d1)),
        ((A - d0, B - d0), (-A + d0, B - d0), (-A + d1, B - d1), (A - d1, B - d1)),
        ((-A + d0, B - d0), (-A + d0, -B + d0), (-A + d1, -B + d1), (-A + d1, B - d1)),
        ((A - d0, -B + d0), (A - d0, B - d0), (A - d1, B - d1), (A - d1, -B + d1)),
    ):
        pts = [P(*p0), P(*p1), P(*p2), P(*p3)]
        out.append((key, pts, [(q[0] / 4.0, -q[1] / 4.0) for q in pts], None, [col] * 4))
    return out


# ---------------------------------------------------------------- Teppich
RUG = {"c": (24.0, 8.0), "L": 78.0, "W": 54.0, "ang": 6.0}


def build_rug():
    cx, cz = RUG["c"]
    L, W = RUG["L"], RUG["W"]
    fr = frame_at(cx, cz, RUG["ang"])
    y = GROUND_Y + 0.05
    A, B = L / 2, W / 2
    parts = []
    P = lambda a, b, yy=y: (*fr.pt(a, b), yy)
    field = [P(-A + 3.3, -B + 3.3), P(A - 3.3, -B + 3.3), P(A - 3.3, B - 3.3), P(-A + 3.3, B - 3.3)]
    parts.append(("k_teppich", field, [(q[0] / 12.0, -q[1] / 12.0) for q in field], None, [(1.0, 1.0, 1.0)] * 4))
    parts += band(fr, A, B, 0.0, 0.8, y - 0.012, "k_wolle", lin("141c33"))        # Einfassung
    parts += band(fr, A, B, 0.8, 2.0, y, "k_wolle", lin("efe6cf"))                 # cremefarbener Streifen
    parts += band(fr, A, B, 2.0, 2.7, y, "k_wolle", lin("c73a34"))                 # roter Streifen
    parts += band(fr, A, B, 2.7, 3.3, y, "k_wolle", lin("efe6cf"))
    # Fransen an den beiden kurzen Seiten
    n = 46
    for sgn in (-1, 1):
        for j in range(n):
            b = -B + 0.7 + j * (W - 1.4) / (n - 1)
            skew = krng.uniform(-0.5, 0.5)
            ln = krng.uniform(1.9, 2.5)
            tone = krng.uniform(0.85, 1.0)
            pts = [P(sgn * A, b - 0.13, GROUND_Y + 0.045), P(sgn * (A + ln), b - 0.1 + skew, GROUND_Y + 0.045), P(sgn * (A + ln), b + 0.1 + skew, GROUND_Y + 0.045), P(sgn * A, b + 0.13, GROUND_Y + 0.045)]
            parts.append(("k_wolle", pts, [(0, 0), (1, 0), (1, 1), (0, 1)], None, [shade(lin("ede4cb"), tone)] * 4))
    KFLOOR.extend(parts)


# ---------------------------------------------------------------- Räume: Wände, Fußleisten
def build_walls():
    P = KIDS
    H = WALL_H
    skirt = lin("f2eee4")
    sides = (
        ("west", Vector((x0, 0)), (0.0, 1.0), (1.0, 0.0), z0, z1),
        ("east", Vector((x1, 0)), (0.0, 1.0), (-1.0, 0.0), z0, z1),
        ("north", Vector((0, z0)), (1.0, 0.0), (0.0, 1.0), x0, x1),
        ("south", Vector((0, z1)), (1.0, 0.0), (0.0, -1.0), x0, x1),
    )
    for name, o, u, v, s0, s1 in sides:
        o_ = Vector(o)
        if name in ("west", "east"):
            base = lambda s: Vector((o_.x, s))
        else:
            base = lambda s: Vector((s, o_.y))
        vv = Vector(v)
        lean = LEAN[name]
        top = lambda s: base(s) - vv * (lean * H)
        L = s1 - s0
        slant = math.hypot(H, lean * H)
        pts = [(*base(s0), GROUND_Y), (*base(s1), GROUND_Y), (*top(s1), H), (*top(s0), H)]
        P.append(("k_tapete", pts, [(0, 0), (L / 6.0, 0), (L / 6.0, slant / 6.0), (0, slant / 6.0)], (vv.x, vv.y), [(1, 1, 1)] * 4))
        # Fußleiste (Plattenbreite 0,7 m, Höhe 5,3 m) und Abschlussleiste
        fr = Frame(base((s0 + s1) / 2), Vector(u), vv)
        P += cbox(fr, "k:farbe", -L / 2, L / 2, 0.0, 0.7, GROUND_Y, GROUND_Y + 5.3, skirt, 4.0, grad=(0.82, 1.0), sides=(0, 1, 0, 0))
        P += cbox(fr, "k:farbe", -L / 2, L / 2, 0.0, 0.45, GROUND_Y + 5.3, GROUND_Y + 5.85, shade(skirt, 1.03), 4.0, grad=(1, 1), sides=(0, 1, 0, 0))
        c = fr.pt(0.0, 0.35)
        collide_rect(c.x, c.y, fr.u.x, fr.u.y, L / 2, 0.45, 6.0, "mauer")


# ---------------------------------------------------------------- Möbel und Spielzeug
def wood_box(fr, a0, a1, b0, b1, y0, y1, col, grad=(0.8, 1.0)):
    return cbox(fr, "k:farbe", a0, a1, b0, b1, y0, y1, col, 3.0, grad=grad)


def build_shelf():
    """Spielzeugregal an der Südwand: Rahmen, 2 x 6 Fächer mit bunten Kisten, Spielzeug obenauf."""
    cx, cz_wall, L, D, H = 46.0, z1 - 0.4, 48.0, 10.2, 14.0
    fr = Frame((cx, cz_wall), (1.0, 0.0), (0.0, -1.0))      # Ursprung an der Wand, v zeigt in den Raum (nach -z)
    if not try_place(cx, cz_wall - D / 2, 1.0, 0.0, L / 2, D / 2, margin=3.0, what="Regal", inside_room=False):
        return
    y = GROUND_Y
    wood = PAL["holz"]
    P = KIDS
    P += wood_box(fr, -L / 2, L / 2, 0.0, 0.6, y, y + H, shade(wood, 0.75))                   # Rückwand an der Wand
    P += wood_box(fr, -L / 2, L / 2, 0.0, D, y + H - 0.8, y + H, shade(wood, 1.1), grad=(1, 1))   # Deckplatte
    P += wood_box(fr, -L / 2, -L / 2 + 0.8, 0.0, D, y, y + H, wood)
    P += wood_box(fr, L / 2 - 0.8, L / 2, 0.0, D, y, y + H, wood)
    P += wood_box(fr, -L / 2, L / 2, 0.0, D, y, y + 0.8, shade(wood, 0.8))
    rows, cols_ = 2, 6
    cw = (L - 1.6) / cols_
    rh = (H - 1.6) / rows
    for r_ in range(rows):
        y0 = y + 0.8 + r_ * rh
        P += wood_box(fr, -L / 2, L / 2, 0.0, D, y0 + rh - 0.2, y0 + rh + 0.4, wood, grad=(1, 1))
        for c_ in range(cols_):
            a0 = -L / 2 + 0.8 + c_ * cw
            if c_ > 0:
                P += wood_box(fr, a0 - 0.2, a0 + 0.2, 0.0, D, y0, y0 + rh, wood)
            kind = krng.random()
            if kind < 0.7:
                col = krng.choice(TOYCOLS)
                P += cbox(fr, "k:farbe", a0 + 0.7, a0 + cw - 0.7, 0.9, D - 1.3, y0 + 0.4, y0 + rh * (0.5 + 0.25 * krng.random()), col, 2.0, grad=(0.7, 1.0))
                if krng.random() < 0.6:
                    P += cbox(fr, "k:farbe", a0 + 1.5, a0 + cw - 1.5, 1.8, D - 2.4, y0 + rh * 0.55, y0 + rh * 0.75, shade(col, 0.8), 2.0, grad=(0.9, 1.0))
            else:
                P += wood_box(fr, a0 + 0.3, a0 + 0.6, 0.6, D - 0.9, y0 + 0.4, y0 + rh - 0.5, krng.choice(TOYCOLS))        # aufrecht stehende Bücher
                for q in range(3):
                    P += wood_box(fr, a0 + 1.0 + q * 0.9, a0 + 1.8 + q * 0.9, 0.8, D - 1.2, y0 + 0.4, y0 + rh - 0.6 - 0.3 * q, krng.choice(TOYCOLS), grad=(0.8, 1.0))
    # Spielzeug obenauf: Bauklötze, ein Stapel Ringe, Bücherstapel
    for k in range(5):
        a = -L / 2 + 4 + k * 8.5 + krng.uniform(-1, 1)
        s_ = krng.uniform(1.6, 2.4)
        P += cbox(frame_at(*fr.pt(a, 4.0 + krng.uniform(-1, 1)), krng.uniform(0, 90)), "k:farbe", -s_ / 2, s_ / 2, -s_ / 2, s_ / 2, y + H, y + H + s_, krng.choice(TOYCOLS), 2.0, grad=(0.8, 1.0))
    for q in range(4):
        P += cbox(fr, "k:farbe", 14.0 - q * 0.0, 17.5 - q * 0.3, 3.0, 7.0, y + H + q * 0.5, y + H + q * 0.5 + 0.5, krng.choice(TOYCOLS), 2.0, grad=(1, 1))
    c = fr.pt(0.0, D / 2)
    collide_rect(c.x, c.y, fr.u.x, fr.u.y, L / 2, D / 2, H, "mauer")


def build_chest():
    """Spielzeugtruhe in der Nordwestecke; Deckel mit Aufschrift TOY BOX, davor ein paar herausgefallene Spielsachen."""
    cx, cz, A, B, H = x0 + 15.0, z0 + 9.8, 12.0, 8.2, 9.0   # in der Nordwestecke, 1,5 m von beiden Wänden
    if not try_place(cx, cz, 1.0, 0.0, A + 0.5, B + 0.5, margin=3.0, what="Truhe", inside_room=False):
        return
    fr = Frame((cx, cz), (1.0, 0.0), (0.0, 1.0))
    y = GROUND_Y
    P = KIDS
    wood = PAL["holz"]
    P += cbox(fr, "k:farbe", -A, A, -B, B, y, y + H, wood, 3.0, grad=(0.7, 1.0), top=False)
    for k_ in (0.2, 0.55, 0.85):                                   # Bretterfugen an der Front
        P.append(poly("k:farbe", [(*fr.pt(-A, B + 0.02), y + H * k_), (*fr.pt(A, B + 0.02), y + H * k_), (*fr.pt(A, B + 0.02), y + H * k_ + 0.12), (*fr.pt(-A, B + 0.02), y + H * k_ + 0.12)],
                      shade(wood, 0.55), (0.0, 1.0)))
    for a in (-A + 1.2, A - 1.2):                                  # Beschläge
        P += cbox(fr, "k:farbe", a - 0.5, a + 0.5, -B - 0.05, B + 0.05, y, y + H, PAL["stahl"], 2.0, grad=(0.8, 1.0), top=False)
    lid_y = y + H + 0.8
    P += cbox(fr, "k:farbe", -A - 0.3, A + 0.3, -B - 0.3, B + 0.3, y + H, lid_y, shade(wood, 1.05), 3.0, grad=(0.9, 1.0), top=False)
    P.append(("k_truhe", [(*fr.pt(-A - 0.3, -B - 0.3), lid_y), (*fr.pt(A + 0.3, -B - 0.3), lid_y), (*fr.pt(A + 0.3, B + 0.3), lid_y), (*fr.pt(-A - 0.3, B + 0.3), lid_y)],
              [(0, 1), (1, 1), (1, 0), (0, 0)], None, [(1, 1, 1)] * 4))
    P += cbox(fr, "k:farbe", -1.2, 1.2, B + 0.1, B + 0.6, y + H - 2.2, y + H - 0.8, PAL["gelb"], 2.0, grad=(0.8, 1.0))      # Schloss
    collide_rect(cx, cz, 1.0, 0.0, A + 0.3, B + 0.3, lid_y, "mauer")
    light_blockers.append([cx, cz, A, B, 0.0])


def brick(x, z, ang_deg, col, nz=2, nx=4, tall=1.0, stack=0):
    """Duplo-Stein (3,2 x 1,6 x 1,0 m) mit Noppen."""
    fr = frame_at(x, z, ang_deg)
    ha, hb = nx * 0.4, nz * 0.4
    y = GROUND_Y + stack * 1.0
    P = KIDS
    P += cbox(fr, "k:farbe", -ha, ha, -hb, hb, y, y + 1.0 * tall, col, 2.0, grad=(0.8, 1.0))
    for i in range(nx):
        for j in range(nz):
            q = fr.pt(-ha + 0.4 + i * 0.8, -hb + 0.4 + j * 0.8)
            P += cyl("k:farbe", q.x, q.y, 0.26, y + tall, y + tall + 0.22, 8, shade(col, 1.05), grad=(0.85, 1.0))


def place_brick(x, z, ang, col, nx=4, nz=2, margin=3.2):
    ha, hb = nx * 0.4 + 0.15, nz * 0.4 + 0.15
    if not try_place(x, z, math.cos(math.radians(ang)), math.sin(math.radians(ang)), ha, hb, margin=margin, what="Stein"):
        return False
    brick(x, z, ang, col, nz, nx)
    collide_rect(x, z, math.cos(math.radians(ang)), math.sin(math.radians(ang)), ha - 0.1, hb - 0.1, 1.2, "mauer")
    return True


def marble(x, z, col_a, col_b):
    if not try_place(x, z, 1.0, 0.0, 0.5, 0.5, margin=2.6, what="Murmel"):
        return False
    KIDS.extend(dome("k:farbe", x, z, GROUND_Y + 0.4, 0.42, 10, 4, col_a, lat0=-0.9, cols_alt=col_b))
    collide_circle(x, z, 0.45, 0.8, "mast")
    return True


def crayon(x, z, ang_deg, col):
    """Buntstift (8 m lang, 0,4 m dick): Holz, Farbmantel, Spitze."""
    fr = frame_at(x, z, ang_deg)
    if not try_place(x, z, fr.u.x, fr.u.y, 4.3, 0.5, margin=2.8, what="Stift"):
        return False
    y = GROUND_Y
    P = KIDS
    P += cbox(fr, "k:farbe", -4.0, 3.0, -0.2, 0.2, y, y + 0.4, col, 2.0, grad=(0.8, 1.0))
    P += cbox(fr, "k:farbe", 3.0, 3.9, -0.15, 0.15, y + 0.04, y + 0.36, PAL["holzhell"], 2.0, grad=(0.9, 1.0))
    P += cbox(fr, "k:farbe", 3.9, 4.2, -0.07, 0.07, y + 0.1, y + 0.3, col, 2.0, grad=(1, 1))
    P += cbox(fr, "k:farbe", -4.0, -3.6, -0.21, 0.21, y, y + 0.41, PAL["weiss"], 2.0, grad=(0.9, 1.0))
    collide_rect(x, z, fr.u.x, fr.u.y, 4.0, 0.3, 0.45, "bank")
    return True


def kids_ao():
    """Kontaktschatten für die Laufzeit-Bauteile (Maße aus den Modellen)."""
    parts = []
    y0 = GROUND_Y
    for p in data["props"]:
        if p["type"] != "ai":
            continue
        m = p["model"]
        r = math.radians(float(p.get("rot", 0.0)))
        x, z = float(p["x"]), float(p["z"])
        fr = Frame((x, z), (math.cos(r), math.sin(r)), (-math.sin(r), math.cos(r)))
        if m == "kinder_teddy":
            ao_prism(parts, x, z, 4.2, 3.6, y0, y0 + 7.0, 12)
        elif m == "kinder_ball":
            ao_prism(parts, x, z, 2.0, 1.4, y0, y0 + 3.2, 12)
        elif m == "kinder_bauklotz":
            parts += box(fr, "ao", -1.3, 1.3, -1.3, 1.3, y0, y0 + 2.6)
        elif m == "kinder_bausteinturm":
            parts += box(fr, "ao", -1.8, 1.8, -1.5, 1.5, y0, y0 + 8.0)
        elif m == "kinder_buch":
            parts += box(fr, "ao", -5.8, 5.8, -4.2, 4.2, y0, y0 + 1.6)
        elif m == "kinder_buntstifte":
            parts += box(fr, "ao", -4.8, 4.8, -3.0, 3.0, y0, y0 + 1.3)
        elif m == "kinder_holzeisenbahn":
            parts += box(fr, "ao", -10.0, 10.0, -2.4, 2.4, y0, y0 + 4.5)
        elif m == "kinder_kreisel":
            ao_prism(parts, x, z, 1.5, 0.9, y0, y0 + 4.5, 10)
    add_ao_parts(parts)


# ---------------------------------------------------------------- Neue Spielsachen (02.10.2026): erkennbare Alltagsdinge statt Klötzchen
PIPS = {1: [(0, 0)], 2: [(-1, -1), (1, 1)], 3: [(-1, -1), (0, 0), (1, 1)], 4: [(-1, -1), (1, -1), (-1, 1), (1, 1)],
        5: [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)], 6: [(-1, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (1, 1)]}


def hexpoly(cx, cz, y, r, col, key="k:farbe"):
    return poly(key, [(cx + r * math.cos(k * math.pi / 3), cz + r * math.sin(k * math.pi / 3), y) for k in range(6)], col)


def spiel_uv(cell_i):
    return (cell_i % 4) / 4.0 + 0.003, 1.0 - (cell_i // 4 + 1) / 4.0 + 0.003, (cell_i % 4 + 1) / 4.0 - 0.003, 1.0 - (cell_i // 4) / 4.0 - 0.003


def flat_toy(x, z, ang, ha, hb, cell_i, y, target=None, margin=2.2, what=""):
    """Flach liegendes Bedrucktes (Karte, Heft, Puzzle ...): Rechteck mit Ausschnitt aus dem Spielsachen-Atlas, Bild oben = -z bei ang 0."""
    fr = frame_at(x, z, ang)
    if not try_place(x, z, fr.u.x, fr.u.y, ha + 0.1, hb + 0.1, margin=margin, what=what):
        return None
    u0, v0, u1, v1 = spiel_uv(cell_i)
    corners_ = [(-ha, -hb), (ha, -hb), (ha, hb), (-ha, hb)]
    pts = [(*fr.pt(a, b), y) for a, b in corners_]
    uvs = [(u0 + (a + ha) / (2 * ha) * (u1 - u0), v1 - (b + hb) / (2 * hb) * (v1 - v0)) for a, b in corners_]
    (KFLOOR if target is None else target).append(("k_spiel", pts, uvs, None, [(1, 1, 1)] * 4))
    return fr


def toy_dice(x, z, ang, top=5, side=3):
    """Spielwürfel (1,1 m): weißer Würfel mit schwarzen Augen oben und an einer Seite."""
    fr = frame_at(x, z, ang)
    if not try_place(x, z, fr.u.x, fr.u.y, 0.85, 0.85, margin=2.6, what="Würfel"):
        return False
    s = 1.1
    y = GROUND_Y
    KIDS.extend(cbox(fr, "k:farbe", -s / 2, s / 2, -s / 2, s / 2, y, y + s, lin("f6f2e8"), 2.0, grad=(0.88, 1.0)))
    for (pa, pb) in PIPS[top]:
        c = fr.pt(pa * 0.27, pb * 0.27)
        KIDS.append(hexpoly(c.x, c.y, y + s + 0.008, 0.09, PAL["schwarz"]))
    for (pa, pb) in PIPS[side]:
        a, yy = pa * 0.27, y + s / 2 + pb * 0.27
        KIDS.append(poly("k:farbe", [(*fr.pt(a + 0.09 * math.cos(k * math.pi / 3), s / 2 + 0.006), yy + 0.09 * math.sin(k * math.pi / 3)) for k in range(6)], PAL["schwarz"], (fr.v.x, fr.v.y)))
    collide_rect(x, z, fr.u.x, fr.u.y, s / 2, s / 2, s, "bank")
    return True


def toy_card(x, z, ang, cell_i=1):
    """Spielkarte (3,6 x 5,0 m) flach auf dem Boden."""
    return flat_toy(x, z, ang, 1.8, 2.5, cell_i, GROUND_Y + 0.075, margin=2.0, what="Karte") is not None


def toy_notebook(x, z, ang):
    """Aufgeschlagenes Heft (8 x 11 m) mit Kritzelei; liegt flach."""
    return flat_toy(x, z, ang, 4.0, 5.5, 4, GROUND_Y + 0.085, margin=2.4, what="Heft") is not None


def toy_stickers(x, z, ang):
    return flat_toy(x, z, ang, 3.4, 3.4, 5, GROUND_Y + 0.08, margin=2.2, what="Sticker") is not None


def toy_puzzle(x, z, ang):
    """Angefangenes Puzzle (14 x 14 m) mit fünf fehlenden Teilen und einigen losen Teilen daneben."""
    fr = flat_toy(x, z, ang, 7.0, 7.0, 7, GROUND_Y + 0.095, margin=2.4, what="Puzzle")
    if fr is None:
        return False
    KIDS.extend(cbox(fr, "k:farbe", -7.1, 7.1, -7.1, 7.1, GROUND_Y, GROUND_Y + 0.09, lin("8a6a44"), 2.0, grad=(1, 1), top=False))
    for (a, b, col) in ((9.4, -2.0, lin("78bef0")), (10.6, 1.6, lin("5ab45a")), (8.8, 4.6, lin("c8442f")), (9.8, -5.0, lin("f6d440"))):
        pf = frame_at(*fr.pt(a, b), ang + a * 17)
        p0 = pf.o
        if not try_place(p0.x, p0.y, pf.u.x, pf.u.y, 1.2, 1.2, margin=2.2, what="Puzzleteil"):
            continue
        KIDS.extend(cbox(pf, "k:farbe", -0.9, 0.9, -0.9, 0.9, GROUND_Y, GROUND_Y + 0.14, col, 2.0, grad=(1, 1)))
        for (ka, kb) in ((1.05, 0.0), (0.0, -1.05)):
            q = pf.pt(ka, kb)
            KIDS.extend(cyl("k:farbe", q.x, q.y, 0.3, GROUND_Y, GROUND_Y + 0.14, 8, col, cap=True, grad=(1, 1)))
    return True


def toy_board_game(x, z, ang):
    """Brettspiel (Mensch ärgere dich nicht, 14 x 14 m) mit vier Spielfiguren und Würfel."""
    fr = frame_at(x, z, ang)
    if not try_place(x, z, fr.u.x, fr.u.y, 7.3, 7.3, margin=2.6, what="Brettspiel"):
        return False
    y = GROUND_Y
    KIDS.extend(cbox(fr, "k:farbe", -7.0, 7.0, -7.0, 7.0, y, y + 0.32, lin("8a5a34"), 2.0, grad=(0.8, 1.0), top=False))
    u0, v0, u1, v1 = spiel_uv(0)
    pts = [(*fr.pt(a, b), y + 0.33) for a, b in ((-7, -7), (7, -7), (7, 7), (-7, 7))]
    KIDS.append(("k_spiel", pts, [(u0, v1), (u1, v1), (u1, v0), (u0, v0)], None, [(1, 1, 1)] * 4))
    cols = [PAL["rot"], PAL["blau"], PAL["gruen"], PAL["gelb"]]
    for k, (a, b) in enumerate(((-4.6, -4.6), (4.6, -4.6), (4.6, 4.6), (-4.6, 4.6))):
        for (da, db) in ((-0.7, -0.7), (0.7, 0.7)):
            q = fr.pt(a + da, b + db)
            KIDS.extend(cyl("k:farbe", q.x, q.y, 0.3, y + 0.33, y + 0.85, 8, cols[k], r_top=0.22, cap=False))
            KIDS.extend(dome("k:farbe", q.x, q.y, y + 0.9, 0.24, 8, 2, cols[k], lat0=-0.3))
    collide_rect(x, z, fr.u.x, fr.u.y, 7.0, 7.0, 0.9, "bank")
    return True


def toy_duck(x, z, ang):
    """Badeente (gelb, orangefarbener Schnabel)."""
    fr = frame_at(x, z, ang)
    if not try_place(x, z, fr.u.x, fr.u.y, 1.9, 1.3, margin=2.6, what="Ente"):
        return False
    y = GROUND_Y
    yel = lin("ffd21f")
    c, t, h = fr.pt(0.0, 0.0), fr.pt(-1.15, 0.0), fr.pt(0.95, 0.0)
    P = KIDS
    P += dome("k:farbe", c.x, c.y, y + 0.7, 1.15, 10, 4, yel, lat0=-0.5)
    P += dome("k:farbe", t.x, t.y, y + 1.0, 0.65, 8, 3, yel, lat0=-0.6)
    P += dome("k:farbe", h.x, h.y, y + 1.65, 0.62, 8, 3, yel, lat0=-0.6)
    P += cbox(fr, "k:farbe", 1.4, 1.95, -0.3, 0.3, y + 1.55, y + 1.8, lin("ff7a1a"), 1.0, grad=(0.9, 1.0))
    for sg in (-1, 1):
        e = fr.pt(1.25, sg * 0.4)
        P += dome("k:farbe", e.x, e.y, y + 1.98, 0.09, 4, 1, PAL["schwarz"], lat0=-0.3)
        w = fr.pt(-0.1, sg * 0.95)
        P += dome("k:farbe", w.x, w.y, y + 0.95, 0.5, 6, 2, shade(yel, 0.88), lat0=-0.4)
    collide_circle(x, z, 1.4, 2.3, "bank")
    return True


def toy_dino(x, z, ang):
    """Plastik-Dinosaurier (Tyrannosaurus, grün): kräftiger Rumpf, großer Kopf mit Unterkiefer und Zähnen, kurze Arme, dicke Beine, kurzer Schwanz, Rückenzacken."""
    fr = frame_at(x, z, ang)
    if not try_place(x, z, fr.u.x, fr.u.y, 3.4, 1.7, margin=2.6, what="Dino"):
        return False
    y = GROUND_Y
    g, g2 = lin("5ab04a"), lin("3d8a3a")
    P = KIDS
    P += cbox(fr, "k:farbe", -1.2, 1.4, -1.25, 1.25, y + 1.5, y + 3.6, g, 2.0, grad=(0.8, 1.0))
    P += cbox(fr, "k:farbe", 1.1, 2.0, -0.8, 0.8, y + 2.4, y + 4.4, g, 2.0, grad=(0.85, 1.0))
    P += cbox(fr, "k:farbe", 1.9, 3.9, -0.9, 0.9, y + 3.3, y + 4.7, g, 2.0, grad=(0.9, 1.0))
    P += cbox(fr, "k:farbe", 2.0, 3.8, -0.72, 0.72, y + 2.8, y + 3.3, g2, 2.0, grad=(1, 1))
    for sg in (-1, 1):
        for k in range(5):
            P += cbox(fr, "k:farbe", 2.25 + k * 0.33, 2.4 + k * 0.33, sg * 0.72 - 0.04, sg * 0.72 + 0.04, y + 3.2, y + 3.42, lin("f6f2e8"), 1.0, grad=(1, 1))
        e = fr.pt(2.7, sg * 0.86)
        P += dome("k:farbe", e.x, e.y, y + 4.45, 0.14, 4, 1, lin("f6f2e8"), lat0=-0.2)
        P += cbox(fr, "k:farbe", 1.2, 1.9, sg * 1.25 - 0.12, sg * 1.25 + 0.12 + sg * 0.15, y + 2.3, y + 2.7, g2, 1.0, grad=(1, 1))
        P += cbox(fr, "k:farbe", -0.6, 0.9, sg * 1.2 - 0.45, sg * 1.2 + 0.45, y, y + 1.5, g2, 2.0, grad=(0.75, 1.0))
        P += cbox(fr, "k:farbe", -0.3, 1.4, sg * 1.2 - 0.5, sg * 1.2 + 0.5, y, y + 0.25, g2, 1.0, grad=(1, 1))
    P += cbox(fr, "k:farbe", -2.8, -1.1, -0.8, 0.8, y + 1.6, y + 2.8, g, 2.0, grad=(0.8, 1.0))
    P += cbox(fr, "k:farbe", -4.0, -2.8, -0.5, 0.5, y + 1.5, y + 2.2, g, 2.0, grad=(0.8, 1.0))
    P += cbox(fr, "k:farbe", -4.8, -4.0, -0.25, 0.25, y + 1.4, y + 1.8, g, 2.0, grad=(0.8, 1.0))
    for a in (-3.6, -2.2, -0.8, 0.6):
        P += cbox(fr, "k:farbe", a - 0.3, a + 0.3, -0.07, 0.07, y + (3.6 if a > -1 else 2.8), y + (4.2 if a > -1 else 3.3), lin("f2c21b"), 1.0, grad=(1, 1))
    collide_rect(x, z, fr.u.x, fr.u.y, 3.3, 1.4, 4.7, "mauer")
    return True


def toy_bunny(x, z, ang):
    """Plüschhase (hellgrau, lange Ohren mit rosa Innenseite, Stummelschwanz)."""
    fr = frame_at(x, z, ang)
    if not try_place(x, z, fr.u.x, fr.u.y, 2.6, 1.6, margin=2.6, what="Hase"):
        return False
    y = GROUND_Y
    fur, pink = lin("d8d4cc"), lin("f2a8b8")
    P = KIDS
    c, h, t = fr.pt(0.0, 0.0), fr.pt(1.9, 0.0), fr.pt(-2.0, 0.0)
    P += dome("k:farbe", c.x, c.y, y + 1.2, 2.0, 10, 4, fur, lat0=-0.45)
    P += dome("k:farbe", h.x, h.y, y + 2.5, 1.2, 8, 3, fur, lat0=-0.45)
    P += dome("k:farbe", t.x, t.y, y + 1.2, 0.6, 6, 2, lin("f6f4ee"), lat0=-0.3)
    for sg in (-1, 1):
        P += cbox(fr, "k:farbe", 1.0, 3.2, sg * 0.75 - 0.3, sg * 0.75 + 0.3, y + 3.2, y + 3.55, fur, 1.0, grad=(0.9, 1.0))
        P += cbox(fr, "k:farbe", 1.05, 3.0, sg * 0.75 - 0.15, sg * 0.75 + 0.15, y + 3.56, y + 3.58, pink, 1.0, grad=(1, 1), sides=(0, 0, 0, 0))
        e = fr.pt(2.7, sg * 0.5)
        P += dome("k:farbe", e.x, e.y, y + 2.9, 0.12, 4, 1, PAL["schwarz"], lat0=-0.3)
        w = fr.pt(1.4, sg * 1.5)
        P += dome("k:farbe", w.x, w.y, y + 0.9, 0.55, 6, 2, shade(fur, 0.92), lat0=-0.4)
    n = fr.pt(3.05, 0.0)
    P += dome("k:farbe", n.x, n.y, y + 2.4, 0.15, 4, 1, pink, lat0=-0.3)
    collide_circle(x, z, 2.1, 3.6, "bank")
    return True


def toy_excavator(x, z, ang):
    """Spielzeugbagger (gelb): zwei Raupenketten, Oberwagen, Kabine, Ausleger mit Löffelstiel und Schaufel."""
    fr = frame_at(x, z, ang)
    if not try_place(x, z, fr.u.x, fr.u.y, 4.4, 1.9, margin=2.6, what="Bagger"):
        return False
    y = GROUND_Y
    ye = lin("f2b81b")
    P = KIDS
    for sg in (-1, 1):
        P += cbox(fr, "k:farbe", -2.2, 2.2, sg * 1.4 - 0.55, sg * 1.4 + 0.55, y, y + 0.95, lin("2a2a2e"), 2.0, grad=(0.8, 1.0))
        for a in (-1.7, 0.0, 1.7):
            P += cbox(fr, "k:farbe", a - 0.3, a + 0.3, sg * 1.4 - 0.58, sg * 1.4 + 0.58, y + 0.15, y + 0.8, lin("55565c"), 1.0, grad=(1, 1), top=False)
    P += cbox(fr, "k:farbe", -1.9, 1.5, -1.3, 1.3, y + 0.95, y + 1.9, ye, 2.0, grad=(0.8, 1.0))
    P += cbox(fr, "k:farbe", -1.5, 0.2, -1.2, 0.2, y + 1.9, y + 3.3, ye, 2.0, grad=(0.85, 1.0))                   # Kabine
    P += cbox(fr, "k:farbe", 0.19, 0.22, -1.0, 0.0, y + 2.1, y + 3.1, lin("2a3a4a"), 1.0, grad=(1, 1), top=False, sides=(0, 0, 0, 1))
    P += cbox(fr, "k:farbe", -1.55, -1.2, -1.2, 0.2, y + 3.3, y + 3.38, lin("55565c"), 1.0, grad=(1, 1))
    P += cbox(fr, "k:farbe", 0.3, 3.8, 0.5, 1.1, y + 1.5, y + 2.4, ye, 1.0, grad=(0.8, 1.0))                        # Ausleger
    P += cbox(fr, "k:farbe", 3.6, 5.6, 0.62, 0.98, y + 0.9, y + 1.5, shade(ye, 0.9), 1.0, grad=(0.8, 1.0))          # Löffelstiel
    P += cbox(fr, "k:farbe", 5.3, 6.2, 0.1, 1.5, y + 0.0, y + 1.0, lin("5a5c62"), 1.0, grad=(0.75, 1.0), top=True)   # Schaufel
    collide_rect(x, z, fr.u.x, fr.u.y, 3.0, 1.9, 3.4, "mauer")
    return True


def toy_tipper(x, z, ang):
    """Kipplaster: rotes Fahrerhaus, graue Mulde, vier Räder."""
    fr = frame_at(x, z, ang)
    if not try_place(x, z, fr.u.x, fr.u.y, 3.5, 1.7, margin=2.6, what="Kipper"):
        return False
    y = GROUND_Y
    P = KIDS
    P += cbox(fr, "k:farbe", -3.2, 3.2, -1.2, 1.2, y + 0.5, y + 0.9, lin("3a3c42"), 2.0, grad=(0.8, 1.0), top=False)
    P += cbox(fr, "k:farbe", 1.4, 3.3, -1.25, 1.25, y + 0.7, y + 2.6, lin("d63a2a"), 2.0, grad=(0.8, 1.0))
    P += cbox(fr, "k:farbe", 3.28, 3.3, -1.0, 1.0, y + 1.5, y + 2.4, lin("2a3a4a"), 1.0, grad=(1, 1), top=False, sides=(0, 0, 0, 1))
    P += cbox(fr, "k:farbe", -3.2, 1.2, -1.3, 1.3, y + 0.9, y + 2.2, lin("c9ccd2"), 2.0, grad=(0.75, 1.0))
    P += cbox(fr, "k:farbe", -3.0, 1.0, -1.1, 1.1, y + 2.18, y + 2.2, lin("8a8d92"), 1.0, grad=(1, 1), sides=(0, 0, 0, 0))
    for a in (-2.0, 2.4):
        for sg in (-1, 1):
            P += cbox(fr, "k:farbe", a - 0.55, a + 0.55, sg * 1.25 - 0.18, sg * 1.25 + 0.18, y, y + 1.1, PAL["schwarz"], 1.0, grad=(0.8, 1.0))
    collide_rect(x, z, fr.u.x, fr.u.y, 3.3, 1.35, 2.7, "mauer")
    return True


def toy_robot(x, z, ang):
    """Blechroboter, auf dem Rücken liegend: Kopf mit Antenne, Brustplatte mit Knöpfen, Arme, Beine."""
    fr = frame_at(x, z, ang)
    if not try_place(x, z, fr.u.x, fr.u.y, 4.2, 2.2, margin=2.6, what="Roboter"):
        return False
    y = GROUND_Y
    si = lin("aab2bc")
    P = KIDS
    P += cbox(fr, "k:farbe", -1.8, 1.8, -1.3, 1.3, y, y + 1.9, si, 2.0, grad=(0.8, 1.0))
    P += cbox(fr, "k:farbe", -1.0, 1.0, -0.8, 0.8, y + 1.91, y + 1.95, lin("d63a2a"), 1.0, grad=(1, 1), sides=(0, 0, 0, 0))
    for k, c in enumerate((PAL["gelb"], PAL["blau"], PAL["gruen"])):
        q = fr.pt(-0.5 + k * 0.5, 0.0)
        P += cyl("k:farbe", q.x, q.y, 0.14, y + 1.95, y + 2.0, 6, c, cap=True, grad=(1, 1))
    P += cbox(fr, "k:farbe", 1.9, 3.5, -0.9, 0.9, y, y + 1.5, shade(si, 1.1), 2.0, grad=(0.85, 1.0))
    for sg in (-1, 1):
        e = fr.pt(3.51, sg * 0.4)
        P += dome("k:farbe", e.x, e.y, y + 0.9, 0.2, 5, 1, PAL["gelb"], lat0=-0.3)
        P += cbox(fr, "k:farbe", -0.5, 1.0, sg * 1.3, sg * 1.3 + sg * 1.4, y, y + 0.9, shade(si, 0.9), 1.0, grad=(0.8, 1.0))
        P += cbox(fr, "k:farbe", -3.9, -1.8, sg * 0.75 - 0.4, sg * 0.75 + 0.4, y, y + 1.0, shade(si, 0.8), 1.0, grad=(0.8, 1.0))
    q = fr.pt(2.7, 0.0)
    P += cyl("k:farbe", q.x, q.y, 0.05, y + 1.5, y + 2.4, 5, PAL["stahl"], cap=False)
    P += dome("k:farbe", q.x, q.y, y + 2.4, 0.16, 5, 1, PAL["rot"], lat0=-0.3)
    collide_rect(x, z, fr.u.x, fr.u.y, 4.0, 1.9, 2.4, "mauer")
    return True


def toy_slippers(x, z, ang):
    """Paar Hausschuhe (Frottee, rosa/blau): helle Sohle, Kappe mit runder Spitze, Fersenwand mit Fellrand um die dunkle Öffnung."""
    fr = frame_at(x, z, ang)
    if not try_place(x, z, fr.u.x, fr.u.y, 3.5, 3.1, margin=2.6, what="Hausschuhe"):
        return False
    y = GROUND_Y
    P = KIDS
    fur, sole = lin("fbf8f0"), lin("f2eee4")
    for sg, col in ((-1, lin("e88fb4")), (1, lin("7fb0e0"))):
        b = sg * 1.75
        c = fr.pt(2.3, b)
        P += cbox(fr, "k:farbe", -2.9, 2.3, b - 0.95, b + 0.95, y, y + 0.3, sole, 2.0, grad=(0.8, 1.0))
        P += cyl("k:farbe", c.x, c.y, 0.95, y, y + 0.3, 8, sole, cap=True, grad=(0.8, 1.0))
        P += cbox(fr, "k:farbe", 0.0, 2.3, b - 0.9, b + 0.9, y + 0.3, y + 1.1, col, 2.0, grad=(0.85, 1.0))
        P += dome("k:farbe", c.x, c.y, y + 0.3, 0.9, 8, 3, col, lat0=0.0)
        P += cbox(fr, "k:farbe", -2.8, -2.3, b - 0.9, b + 0.9, y + 0.3, y + 1.0, col, 2.0, grad=(0.85, 1.0))
        for q in (-1, 1):
            P += cbox(fr, "k:farbe", -2.8, 0.0, min(b + q * 0.65, b + q * 0.9), max(b + q * 0.65, b + q * 0.9), y + 0.3, y + 1.0, col, 2.0, grad=(0.85, 1.0))
        P.append(poly("k:farbe", [(*fr.pt(-2.3, b - 0.65), y + 0.34), (*fr.pt(0.0, b - 0.65), y + 0.34), (*fr.pt(0.0, b + 0.65), y + 0.34), (*fr.pt(-2.3, b + 0.65), y + 0.34)], lin("3a2a30"), None))
        P += cbox(fr, "k:farbe", -2.85, -2.25, b - 0.95, b + 0.95, y + 1.0, y + 1.14, fur, 1.0, grad=(1, 1))
        for q in (-1, 1):
            P += cbox(fr, "k:farbe", -2.85, 0.1, b + q * 0.8 - 0.15, b + q * 0.8 + 0.15, y + 1.0, y + 1.14, fur, 1.0, grad=(1, 1))
    collide_rect(x, z, fr.u.x, fr.u.y, 3.0, 2.8, 1.2, "bank")
    return True


def toy_books(x, z, ang):
    """Bücherstapel: vier Bände, leicht gegeneinander verdreht."""
    fr = frame_at(x, z, ang)
    if not try_place(x, z, fr.u.x, fr.u.y, 3.5, 2.6, margin=2.6, what="Bücher"):
        return False
    y = GROUND_Y
    cols = [lin("c0392b"), lin("2d5fc4"), lin("2f9a4c"), lin("e8b81c"), lin("7a3a9a")]
    krr = random.Random(int(x * 3 + z))
    yy = y
    for k in range(4):
        bf = frame_at(*fr.pt(krr.uniform(-0.25, 0.25), krr.uniform(-0.2, 0.2)), ang + krr.uniform(-14, 14))
        c = cols[(k + int(abs(x))) % 5]
        th = krr.uniform(0.55, 0.8)
        KIDS.extend(cbox(bf, "k:farbe", -3.0, 3.0, -2.1, 2.1, yy, yy + th, c, 2.0, grad=(0.85, 1.0)))
        KIDS.extend(cbox(bf, "k:farbe", -2.9, 3.0, -2.0, 2.0, yy + 0.1, yy + th - 0.1, lin("f4efe0"), 2.0, grad=(1, 1), top=False, sides=(0, 1, 0, 1)))
        yy += th
        last_bf = bf
    u0, v0, u1, v1 = spiel_uv(6)
    KIDS.append(("k_spiel", [(*last_bf.pt(a, b), yy + 0.01) for a, b in ((-3.0, -2.1), (3.0, -2.1), (3.0, 2.1), (-3.0, 2.1))], [(u0, v1), (u1, v1), (u1, v0), (u0, v0)], None, [(1, 1, 1)] * 4))
    collide_rect(x, z, fr.u.x, fr.u.y, 3.4, 2.5, yy - y, "bank")
    return True


def toy_minifig(x, z, ang, col=None):
    """Steckfigur (2,2 m): Beine, Torso mit Armen, Kopf mit Gesicht, Helm."""
    fr = frame_at(x, z, ang)
    if not try_place(x, z, fr.u.x, fr.u.y, 0.9, 0.9, margin=2.4, what="Figur"):
        return False
    y = GROUND_Y
    col = col or krng.choice([PAL["rot"], PAL["blau"], PAL["gruen"], PAL["orange"]])
    P = KIDS
    P += cbox(fr, "k:farbe", -0.28, 0.28, -0.4, 0.4, y, y + 0.7, lin("2d3a5c"), 1.0, grad=(0.8, 1.0), top=False)
    P += cbox(fr, "k:farbe", -0.3, 0.3, -0.5, 0.5, y + 0.7, y + 1.4, col, 1.0, grad=(0.85, 1.0))
    for sg in (-1, 1):
        P += cbox(fr, "k:farbe", -0.2, 0.2, sg * 0.5, sg * 0.5 + sg * 0.22, y + 0.75, y + 1.35, shade(col, 0.9), 1.0, grad=(0.85, 1.0))
    c = fr.pt(0, 0)
    P += cyl("k:farbe", c.x, c.y, 0.3, y + 1.4, y + 1.95, 8, lin("f2c21b"), cap=True, grad=(0.9, 1.0))
    P += cyl("k:farbe", c.x, c.y, 0.08, y + 1.95, y + 2.05, 6, lin("f2c21b"), cap=True, grad=(1, 1))
    P += cbox(fr, "k:farbe", 0.28, 0.31, -0.18, 0.18, y + 1.55, y + 1.75, PAL["schwarz"], 1.0, grad=(1, 1), top=False, sides=(0, 0, 0, 1))
    collide_circle(x, z, 0.65, 2.0, "bank")
    return True


def toy_plane(x, z, ang):
    """Papierflieger (weiß, 9 m lang) liegt auf dem Boden: zwei gefaltete Flügel und ein Kiel."""
    fr = frame_at(x, z, ang)
    if not try_place(x, z, fr.u.x, fr.u.y, 4.6, 2.2, margin=2.2, what="Papierflieger"):
        return False
    y = GROUND_Y
    w = lin("f6f4ee")
    for sg in (-1, 1):
        KIDS.append(poly("k:farbe", [(*fr.pt(4.5, 0.0), y + 0.1), (*fr.pt(-4.0, sg * 2.0), y + 0.08), (*fr.pt(-4.0, sg * 0.3), y + 0.7)], shade(w, 0.96 if sg > 0 else 1.0)))
    KIDS.append(poly("k:farbe", [(*fr.pt(4.5, 0.0), y + 0.1), (*fr.pt(-4.0, 0.0), y + 0.1), (*fr.pt(-4.0, 0.3), y + 0.9)], shade(w, 0.85), (fr.v.x, fr.v.y)))
    collide_rect(x, z, fr.u.x, fr.u.y, 4.5, 2.0, 0.9, "bank")
    return True


def toy_car(x, z, ang):
    """Spielzeugauto (nicht auf der Bahn): einfaches Modell aus dem Autobausatz."""
    fr = frame_at(x, z, ang)
    kr = random.Random(int(x * 7 + z * 13))
    parts_c, (cl, cw) = kit_car.random_car(kr, x, z, fr.u.x, fr.u.y, base_y=GROUND_Y)
    if not try_place(x, z, fr.u.x, fr.u.y, cl / 2 + 0.2, cw / 2 + 0.2, margin=2.8, what="Spielauto"):
        return False
    KIDS.extend(parts_c)
    collide_rect(x, z, fr.u.x, fr.u.y, cl / 2, cw / 2, 1.5, "auto")
    return True


# ---------------------------------------------------------------- Bauklotzburg und Puppenhaus
def toy_castle(x, z, ang):
    """Burg aus Holzbausteinen (15 x 11 m): vier Türme mit Kegeldächern, Zinnenmauern, Torbogen, Bergfried, Fahne."""
    fr = frame_at(x, z, ang)
    if not try_place(x, z, fr.u.x, fr.u.y, 8.8, 6.8, margin=3.0, what="Burg"):
        return False
    y = GROUND_Y
    P = KIDS
    wood, wood2 = lin("d9a566"), lin("b9803f")
    reds = [lin("c8442f"), lin("2d5fc4"), lin("2f9a4c"), lin("e8b81c")]
    A, B = 6.5, 4.5
    P += cbox(fr, "k:farbe", -A - 0.5, A + 0.5, -B - 0.5, B + 0.5, y, y + 0.35, lin("a8884f"), 3.0, grad=(0.8, 1.0))          # Grundplatte
    wh = 2.4
    for (a0, a1, b0, b1, sides) in ((-A, A, -B - 0.3, -B + 0.3, None), (-A, -2.0, B - 0.3, B + 0.3, None), (2.0, A, B - 0.3, B + 0.3, None),
                                    (-A - 0.3, -A + 0.3, -B, B, None), (A - 0.3, A + 0.3, -B, B, None)):
        P += cbox(fr, "k:farbe", a0, a1, b0, b1, y + 0.35, y + 0.35 + wh, wood, 3.0, grad=(0.8, 1.0))
        L = max(a1 - a0, b1 - b0)
        for k in range(int(L / 1.4)):
            if a1 - a0 > b1 - b0:
                aa, bb = a0 + 0.7 + k * 1.4, (b0 + b1) / 2
            else:
                aa, bb = (a0 + a1) / 2, b0 + 0.7 + k * 1.4
            if k % 2 == 0:
                P += cbox(fr, "k:farbe", aa - 0.3, aa + 0.3, bb - 0.35, bb + 0.35, y + 0.35 + wh, y + 0.35 + wh + 0.55, wood2, 2.0, grad=(0.85, 1.0))
    for sg in (-1, 1):                                                                                   # Torpfeiler
        P += cbox(fr, "k:farbe", sg * 2.0 - (0.55 if sg > 0 else 0.0), sg * 2.0 + (0.0 if sg > 0 else 0.55), B - 0.45, B + 0.45, y + 0.35, y + 3.4, wood2, 2.0, grad=(0.8, 1.0))
    P += cbox(fr, "k:farbe", -2.0, 2.0, B - 0.4, B + 0.4, y + 2.6, y + 3.2, wood2, 2.0, grad=(0.85, 1.0))
    for k, (a, b) in enumerate(((-A, -B), (A, -B), (A, B), (-A, B))):                                    # Türme mit Kegeldach
        q = fr.pt(a, b)
        P += cyl("k:farbe", q.x, q.y, 1.5, y + 0.35, y + 4.6, 10, wood, grad=(0.75, 1.0))
        P += cyl("k:farbe", q.x, q.y, 1.6, y + 4.6, y + 5.0, 10, wood2, cap=True, grad=(1, 1))
        P += cyl("k:farbe", q.x, q.y, 1.8, y + 5.0, y + 7.0, 10, reds[k], r_top=0.05, cap=False, grad=(0.8, 1.0))
    keep = fr.pt(0.0, -1.2)                                                                              # Bergfried
    P += cbox(fr, "k:farbe", -1.6, 1.6, -2.8, 0.4, y + 0.35, y + 4.2, lin("d6502f"), 3.0, grad=(0.75, 1.0))
    P += gable(fr, "k:farbe", -1.8, 1.8, -3.0, 0.6, y + 4.2, y + 5.8, lin("2d5fc4"), 3.0, "a")
    P += cyl("k:farbe", keep.x, keep.y, 0.05, y + 5.8, y + 8.0, 6, PAL["stahl"], cap=False)
    pf = fr.pt(0.0, -1.2)
    P.append(poly("k:farbe", [(pf.x, pf.y, y + 8.0), (pf.x, pf.y, y + 7.2), (*fr.pt(1.1, -1.2), y + 7.6)], lin("d63a2a"), (fr.v.x, fr.v.y)))
    for k, (a, b, col_) in enumerate(((-4.0, 1.5, "c8442f"), (3.4, 2.4, "2d5fc4"), (1.0, 1.8, "e8b81c"))):                # Spielfiguren-Klötze im Hof
        P += cbox(frame_at(*fr.pt(a, b), ang + 20 * k), "k:farbe", -0.5, 0.5, -0.5, 0.5, y + 0.35, y + 1.35, lin(col_), 1.0, grad=(0.8, 1.0))
    collide_rect(x, z, fr.u.x, fr.u.y, A + 0.6, B + 0.6, 7.0, "mauer")
    add_occluder_poly(rect_poly(x, z, fr.u.x, fr.u.y, A + 0.6, B + 0.6), 7.5)
    return True


def toy_dollhouse(x, z, ang):
    """Puppenhaus (18 x 12 m, zwei Stockwerke, Satteldach, Schornstein): Vorderseite zeigt in +v, Fenster mit Vorhängen, Tür, Balkon."""
    fr = frame_at(x, z, ang)
    if not try_place(x, z, fr.u.x, fr.u.y, 9.4, 6.4, margin=3.0, what="Puppenhaus"):
        return False
    y = GROUND_Y
    P = KIDS
    wall, trim = lin("f4e6c8"), lin("fbf8f0")
    A, B, H = 9.0, 6.0, 10.5
    P += cbox(fr, "k:farbe", -A - 0.3, A + 0.3, -B - 0.3, B + 0.3, y, y + 0.5, lin("8a8f96"), 3.0, grad=(0.8, 1.0), top=False)
    P += cbox(fr, "k:farbe", -A, A, -B, B, y + 0.5, y + H, wall, 4.0, grad=(0.8, 1.0))
    P += cbox(fr, "k:farbe", -A - 0.15, A + 0.15, -B - 0.15, B + 0.15, y + H * 0.5, y + H * 0.5 + 0.3, trim, 3.0, grad=(1, 1), top=False)     # Geschossband
    P += gable(fr, "k:farbe", -A - 0.8, A + 0.8, -B - 0.9, B + 0.9, y + H, y + H + 5.2, lin("c8442f"), 4.0, "a")
    ch = fr.pt(5.0, -2.0)
    P += cbox(frame_at(ch.x, ch.y, ang), "k:farbe", -0.7, 0.7, -0.7, 0.7, y + H + 2.0, y + H + 6.2, lin("a8553a"), 2.0, grad=(0.8, 1.0))
    P += cbox(frame_at(ch.x, ch.y, ang), "k:farbe", -0.85, 0.85, -0.85, 0.85, y + H + 6.2, y + H + 6.5, lin("6b6e74"), 1.0, grad=(1, 1))
    face = (fr.v.x, fr.v.y)
    bf = B + 0.012
    for fl in (0, 1):
        y0 = y + 0.9 + fl * H * 0.5
        for a in (-6.0, -2.0, 2.0, 6.0):
            if fl == 0 and a == 2.0:
                continue
            w0, w1 = a - 1.1, a + 1.1
            P.append(poly("k:farbe", [(*fr.pt(w0 - 0.2, bf), y0 + 0.9), (*fr.pt(w1 + 0.2, bf), y0 + 0.9), (*fr.pt(w1 + 0.2, bf), y0 + 4.5), (*fr.pt(w0 - 0.2, bf), y0 + 4.5)], trim, face))
            P.append(poly("k:farbe", [(*fr.pt(w0, bf + 0.01), y0 + 1.1), (*fr.pt(w1, bf + 0.01), y0 + 1.1), (*fr.pt(w1, bf + 0.01), y0 + 4.3), (*fr.pt(w0, bf + 0.01), y0 + 4.3)], lin("5a82b0"), face))
            P.append(poly("k:farbe", [(*fr.pt(w0, bf + 0.02), y0 + 3.0), (*fr.pt(w0 + 0.7, bf + 0.02), y0 + 3.0), (*fr.pt(w0 + 0.5, bf + 0.02), y0 + 4.3), (*fr.pt(w0, bf + 0.02), y0 + 4.3)], lin("e8689c"), face))
            P.append(poly("k:farbe", [(*fr.pt(w1 - 0.7, bf + 0.02), y0 + 3.0), (*fr.pt(w1, bf + 0.02), y0 + 3.0), (*fr.pt(w1, bf + 0.02), y0 + 4.3), (*fr.pt(w1 - 0.5, bf + 0.02), y0 + 4.3)], lin("e8689c"), face))
    P.append(poly("k:farbe", [(*fr.pt(1.0, bf + 0.01), y + 0.5), (*fr.pt(3.0, bf + 0.01), y + 0.5), (*fr.pt(3.0, bf + 0.01), y + 4.8), (*fr.pt(1.0, bf + 0.01), y + 4.8)], lin("7a4a2a"), face))   # Tür
    P += cbox(fr, "k:farbe", -3.5, 3.5, B, B + 1.6, y + H * 0.5 - 0.2, y + H * 0.5, lin("a8703c"), 2.0, grad=(1, 1))                                   # Balkon über der Tür
    P += cbox(fr, "k:farbe", -3.5, 3.5, B + 1.5, B + 1.6, y + H * 0.5, y + H * 0.5 + 1.0, trim, 1.0, grad=(0.9, 1.0), sides=(1, 1, 1, 1))
    collide_rect(x, z, fr.u.x, fr.u.y, A + 0.5, B + 0.5, H, "mauer")
    add_occluder_poly(rect_poly(x, z, fr.u.x, fr.u.y, A + 0.5, B + 0.5), 15.0)
    return True


def tea_party(x, z):
    """Teeparty auf rundem rosa Teppich (r = 9 m): Teekanne, vier Tassen auf Untertassen, Plüschhase und Ente als Gäste."""
    if not try_place(x, z, 1.0, 0.0, 9.6, 9.6, margin=2.8, what="Teeparty"):
        return False
    y = GROUND_Y + 0.05
    n = 28
    ring = [(x + 9.0 * math.cos(2 * math.pi * k / n), z + 9.0 * math.sin(2 * math.pi * k / n)) for k in range(n)]
    for rr, col in ((9.0, lin("f3b4c8")), (7.4, lin("f9d7e2")), (6.9, lin("f3b4c8"))):
        pts = [(x + rr * math.cos(2 * math.pi * k / n), z + rr * math.sin(2 * math.pi * k / n), y + (9.0 - rr) * 0.006) for k in range(n)]
        KFLOOR.append(("k_wolle", pts, [(p[0] / 4.0, -p[1] / 4.0) for p in pts], None, [col] * n))
    P = KIDS
    P += cyl("k:farbe", x, z, 0.9, y + 0.0, y + 0.8, 10, lin("f6f2e8"), r_top=0.8, cap=False)
    P += dome("k:farbe", x, z, y + 0.8, 0.9, 10, 3, lin("f6f2e8"), lat0=-0.1)
    P += cyl("k:farbe", x, z, 0.92, y + 0.4, y + 0.6, 10, lin("5a82b0"), cap=False)
    P += cbox(frame_at(x, z, 20), "k:farbe", 0.8, 1.7, -0.1, 0.1, y + 0.45, y + 0.9, lin("f6f2e8"), 1.0, grad=(1, 1))
    P += cbox(frame_at(x, z, 20), "k:farbe", -1.6, -0.8, -0.12, 0.12, y + 0.4, y + 1.3, lin("f6f2e8"), 1.0, grad=(1, 1))
    P += cyl("k:farbe", x, z, 0.2, y + 1.7, y + 1.85, 6, lin("f2c21b"), cap=True)
    for k in range(4):
        a = k * math.pi / 2 + 0.6
        cx_, cz_ = x + 3.2 * math.cos(a), z + 3.2 * math.sin(a)
        P += cyl("k:farbe", cx_, cz_, 0.85, y, y + 0.08, 10, lin("f6f2e8"), cap=True)
        P += cyl("k:farbe", cx_, cz_, 0.45, y + 0.08, y + 0.55, 8, [lin("e8689c"), lin("5a82b0"), lin("f2c21b"), lin("7fc27a")][k], r_top=0.5, cap=False)
        P += cbox(frame_at(cx_, cz_, math.degrees(a)), "k:farbe", 0.45, 0.8, -0.08, 0.08, y + 0.2, y + 0.45, lin("f6f2e8"), 1.0, grad=(1, 1))
    collide_circle(x, z, 1.2, 1.9, "bank")
    rug_poly = placed.pop()
    for (bx, bz, fn) in ((x + 6.3, z - 1.0, toy_bunny), (x - 6.2, z + 2.0, toy_duck)):
        QUIET[0] = 1
        fn(bx, bz, math.degrees(math.atan2(z - bz, x - bx)))
        QUIET[0] = 0
    placed.append(rug_poly)
    return True


def build_bed():
    """Bettecke in der Nordostecke: Gestell, Matratze, gesteppte Decke, Kissen, Kopfteil im Süden; daneben Nachttisch mit Lampe (leuchtet nachts und
    erhellt das Zimmer: echtes Punktlicht). Das Kopfende liegt im Süden, damit Nachttisch und Lampe unter der Titelleiste des Spiels sichtbar bleiben."""
    bx0, bx1, bz0, bz1 = 74.0, x1, z0, -37.0
    cx, cz = (bx0 + bx1) / 2, (bz0 + bz1) / 2
    if not try_place(cx, cz, 1.0, 0.0, (bx1 - bx0) / 2, (bz1 - bz0) / 2, margin=3.0, what="Bett", inside_room=False):
        return
    y = GROUND_Y
    P = KIDS
    fr = Frame((cx, cz), (1.0, 0.0), (0.0, 1.0))
    A, B = (bx1 - bx0) / 2, (bz1 - bz0) / 2
    wood = shade(PAL["holz"], 0.82)
    for sx in (-1, 1):
        for sz in (-1, 1):
            P += cbox(fr, "k:farbe", sx * (A - 0.9) - 0.9, sx * (A - 0.9) + 0.9, sz * (B - 0.9) - 0.9, sz * (B - 0.9) + 0.9, y, y + 4.2, wood, 2.0, grad=(0.7, 1.0))
    P += cbox(fr, "k:farbe", -A, A, -B, B, y + 4.0, y + 6.6, shade(wood, 1.1), 2.0, grad=(0.75, 1.0), top=False)
    P += cbox(fr, "k:farbe", -A + 0.4, A - 0.4, -B + 0.4, B - 0.4, y + 6.6, y + 11.6, lin("f6f1e4"), 2.0, grad=(0.85, 1.0))                  # Matratze
    P += cbox(fr, "k:farbe", -A, A, B - 0.3, B + 0.9, y + 3.0, y + 11.0, shade(wood, 1.05), 2.0, grad=(0.75, 1.0))                          # Kopfteil
    P += cbox(fr, "k:farbe", -A, A, -B - 0.9, -B + 0.3, y + 3.0, y + 8.5, wood, 2.0, grad=(0.75, 1.0))                                       # Fußteil
    # gesteppte Decke: 6 x 5 Felder in Pastelltönen, Seitenteile hängen herab
    cols_ = [lin(c) for c in ("f4b8c8", "b8d8f2", "f8e6a0", "bfe3c0", "d9c3ec", "f8c9a8")]
    nx, nz = 6, 4
    top_y = y + 11.9
    for i in range(nx):
        for j in range(nz):
            a0, a1 = -A + 0.2 + i * (2 * A - 0.4) / nx, -A + 0.2 + (i + 1) * (2 * A - 0.4) / nx
            b0, b1 = -B + 0.2 + j * (2 * B - 0.4 - 8.0) / nz, -B + 0.2 + (j + 1) * (2 * B - 0.4 - 8.0) / nz
            c = cols_[(i + 2 * j) % len(cols_)]
            P.append(poly("k:farbe", [(*fr.pt(a0 + 0.1, b0 + 0.1), top_y), (*fr.pt(a1 - 0.1, b0 + 0.1), top_y), (*fr.pt(a1 - 0.1, b1 - 0.1), top_y), (*fr.pt(a0 + 0.1, b1 - 0.1), top_y)], c, None))
            P.append(poly("k:farbe", [(*fr.pt(a0, b0), top_y - 0.15), (*fr.pt(a1, b0), top_y - 0.15), (*fr.pt(a1, b1), top_y - 0.15), (*fr.pt(a0, b1), top_y - 0.15)], shade(c, 0.78), None))
            if i == 0:
                P.append(poly("k:farbe", [(*fr.pt(-A + 0.2, b0), top_y), (*fr.pt(-A + 0.2, b1), top_y), (*fr.pt(-A + 0.2, b1), y + 7.3), (*fr.pt(-A + 0.2, b0), y + 7.3)], shade(c, 0.9), (-1.0, 0.0)))
            if j == 0:
                P.append(poly("k:farbe", [(*fr.pt(a0, -B + 0.2), top_y), (*fr.pt(a1, -B + 0.2), top_y), (*fr.pt(a1, -B + 0.2), y + 7.3), (*fr.pt(a0, -B + 0.2), y + 7.3)], shade(c, 0.9), (0.0, -1.0)))
    # Umschlag der Decke (hell) am Kopfende, zwei Kissen, Stofftier am Fußende
    P += cbox(fr, "k:farbe", -A + 0.3, A - 0.3, B - 8.0, B - 6.4, top_y, top_y + 0.2, lin("f4f0e6"), 2.0, grad=(1, 1))
    for k, a in enumerate((-3.6, 3.6)):
        P += cbox(fr, "k:farbe", a - 3.2, a + 3.2, B - 5.6, B - 0.9, top_y, top_y + 2.2, lin("f7f4ec"), 2.0, grad=(0.85, 1.0))
        P += cbox(fr, "k:farbe", a - 2.9, a + 2.9, B - 4.6, B - 4.1, top_y + 2.2, top_y + 2.23, lin("7fb0e0"), 2.0, grad=(1, 1), sides=(0, 0, 0, 0))
    tb = fr.pt(0.0, -B + 5.0)
    P += dome("k:farbe", tb.x, tb.y, top_y + 0.6, 1.9, 10, 4, lin("b7824f"), lat0=-0.3)
    P += dome("k:farbe", tb.x, tb.y + 1.6, top_y + 2.0, 1.3, 9, 3, lin("c08a58"), lat0=-0.3)
    for sgn in (-1, 1):
        P += dome("k:farbe", tb.x + sgn * 1.0, tb.y + 1.9, top_y + 3.1, 0.55, 6, 2, lin("a8703c"), lat0=-0.2)
    collide_rect(cx, cz, 1.0, 0.0, A, B, 12.0, "mauer")
    # Nachttisch (westlich des Kopfendes) mit Lampe
    nx_, nz_ = 70.2, -36.5
    if try_place(nx_, nz_, 1.0, 0.0, 3.4, 3.4, margin=3.0, what="Nachttisch", inside_room=False):
        nf = Frame((nx_, nz_), (1.0, 0.0), (0.0, 1.0))
        P += cbox(nf, "k:farbe", -3.0, 3.0, -3.0, 3.0, y, y + 7.0, PAL["holz"], 2.0, grad=(0.75, 1.0))
        P += cbox(nf, "k:farbe", -3.3, 3.3, -3.3, 3.3, y + 7.0, y + 7.5, shade(PAL["holz"], 1.1), 2.0, grad=(1, 1))
        for k_ in range(2):
            P += cbox(nf, "k:farbe", -2.5, 2.5, 3.0, 3.08, y + 0.6 + k_ * 3.2, y + 3.4 + k_ * 3.2, shade(PAL["holz"], 0.9), 2.0, grad=(1, 1), top=False, sides=(0, 0, 0, 0))
            P += dome("k:farbe", nx_, nz_ + 3.15, y + 2.0 + k_ * 3.2, 0.3, 6, 2, PAL["stahl"], lat0=-0.2)
        lp = Vector((nx_ - 0.4, nz_ + 1.6))
        P += cyl("k:farbe", lp.x, lp.y, 1.0, y + 7.5, y + 8.0, 12, PAL["rot"], grad=(0.8, 1.0))
        P += cyl("k:farbe", lp.x, lp.y, 0.2, y + 8.0, y + 11.0, 8, PAL["stahl"], cap=False)
        P += cyl("k:lampe", lp.x, lp.y, 2.6, y + 10.2, y + 13.0, 14, (1.0, 0.9, 0.7), r_top=1.7, cap=False, grad=(1, 1))        # Lampenschirm: Lichtquelle
        P += dome("k:lampe", lp.x, lp.y, y + 10.9, 0.7, 8, 2, (1.0, 0.95, 0.8), lat0=-0.3)
        P += cbox(nf, "k:farbe", -2.4, -0.6, 1.2, 2.4, y + 7.5, y + 8.0, lin("f2c21b"), 2.0, grad=(0.9, 1.0))                     # Wecker (Körper)
        collide_rect(nx_, nz_, 1.0, 0.0, 3.4, 3.4, 7.5, "mauer")
        # Das Zimmer wird von dieser Lampe erhellt: warmes Punktlicht (Schirm in 12 m Höhe), große Reichweite, mit echtem Lichtkegel (Premium)
        add_light(lp.x, lp.y, y + 12.2, (1.0, 0.8, 0.5), 1.0, 66.0, omni=True, glow=3.4)


def build_light_patch():
    """Fensterlicht auf dem Boden: Fenster in der Westwand, sechs helle Felder (zwei Spalten, drei Reihen) mit Sprossenkreuz, gleiche Dielen wie der Boden, nur
    heller. Nachts fällt kühles Mondlicht durch dasselbe Fenster: je Feld ein Punktlicht (Lichtkarte), der Fleck ist dann heller als der übrige Raum."""
    xs_ = [(-84.5, -77.5), (-75.5, -68.5)]
    zs_ = [(-27.0, -20.5), (-18.5, -12.0), (-10.0, -3.5)]
    parts = []
    for xa, xb in xs_:
        for za, zb in zs_:
            parts += floor_rect("k_licht", xa, xb, za, zb, GROUND_Y + 0.006, tone=True)
            add_light((xa + xb) / 2, (za + zb) / 2, 14.0, (0.55, 0.72, 1.0), 0.68, 10.0, omni=False)
    objs_ground.append(mesh_object("Boden_licht", parts))


def paper_and_ruler():
    """Zeichnung (14 x 10,5 m), Lineal, Radiergummi im Fensterlicht (Westfenster). Liegt eine Stelle ungünstig, wird in der Umgebung gesucht."""
    cx, cz = -76.0, -15.0
    fr = None
    QUIET[0] = 1
    for (dx, dz) in ((0, 0), (0, 4), (0, -4), (3, 0), (-3, 0), (0, 8), (0, -8)):
        cand = frame_at(cx + dx, cz + dz, 14.0)
        if try_place(cand.o.x, cand.o.y, cand.u.x, cand.u.y, 7.2, 5.5, margin=3.0, what="Zeichnung"):
            fr = cand
            break
    QUIET[0] = 0
    if fr is None:
        print("DIORAMA kids: keine freie Stelle für die Zeichnung")
        return
    cx, cz = fr.o.x, fr.o.y
    y = GROUND_Y + 0.05
    A, B = 7.0, 5.25
    pts = [(*fr.pt(-A, -B), y), (*fr.pt(A, -B), y), (*fr.pt(A, B), y), (*fr.pt(-A, B), y)]
    KFLOOR.append(("k_zeichnung", pts, [(0, 1), (1, 1), (1, 0), (0, 0)], None, [(1, 1, 1)] * 4))
    KFLOOR.append(("k:farbe", [(*fr.pt(-A - 0.15, -B - 0.15), y - 0.02), (*fr.pt(A + 0.15, -B - 0.15), y - 0.02), (*fr.pt(A + 0.15, B + 0.15), y - 0.02), (*fr.pt(-A - 0.15, B + 0.15), y - 0.02)],
                   [(0, 0), (1, 0), (1, 1), (0, 1)], None, [(0.25, 0.22, 0.18)] * 4))
    # Lineal: 15 m x 1,5 m, flach
    for (dx, dz, ang) in ((3.0, 8.5, 18.0), (3.0, -8.5, 10.0), (11.0, 0.0, 95.0), (-11.0, 1.0, 80.0)):
        rf = frame_at(cx + dx, cz + dz, ang)
        QUIET[0] = 1
        okr = try_place(rf.o.x, rf.o.y, rf.u.x, rf.u.y, 7.6, 0.9, margin=3.0, what="Lineal")
        QUIET[0] = 0
        if okr:
            ry = GROUND_Y + 0.12
            KFLOOR.append(("k_lineal", [(*rf.pt(-7.5, -0.75), ry), (*rf.pt(7.5, -0.75), ry), (*rf.pt(7.5, 0.75), ry), (*rf.pt(-7.5, 0.75), ry)], [(0, 0), (1, 0), (1, 1), (0, 1)], None, [(1, 1, 1)] * 4))
            KIDS.extend(cbox(rf, "k:farbe", -7.52, 7.52, -0.76, 0.76, GROUND_Y, ry - 0.005, lin("c9a050"), 2.0, grad=(0.8, 1.0), top=False))
            break
    # Radiergummi
    for (dx, dz) in ((-9.5, 2.0), (9.5, -4.0), (-8.5, -6.5), (0.0, 7.5)):
        ef = frame_at(cx + dx, cz + dz, 35.0)
        QUIET[0] = 1
        oke = try_place(ef.o.x, ef.o.y, ef.u.x, ef.u.y, 1.5, 1.0, margin=3.0, what="Radierer")
        QUIET[0] = 0
        if oke:
            KIDS.extend(cbox(ef, "k:farbe", -1.1, 1.1, -0.7, 0.7, GROUND_Y, GROUND_Y + 0.7, PAL["weiss"], 2.0, grad=(0.85, 1.0)))
            KIDS.extend(cbox(ef, "k:farbe", 0.3, 1.1, -0.72, 0.72, GROUND_Y, GROUND_Y + 0.72, PAL["blau"], 2.0, grad=(0.85, 1.0), top=True))
            collide_rect(ef.o.x, ef.o.y, ef.u.x, ef.u.y, 1.1, 0.7, 0.7, "bank")
            break


def build_moon_lamp():
    """Mondlampe (Nachtlicht, warm leuchtende Kugel auf Holzfuß) an der Westwand unterhalb des Fensters: zweite echte Lichtquelle der Nacht, im Bild links."""
    for (cx, cz) in ((-83.0, 19.0), (-83.0, 17.0), (-84.0, 21.0), (-52.0, 53.0)):
        QUIET[0] = 1
        okm = try_place(cx, cz, 1.0, 0.0, 2.2, 2.2, margin=3.0, what="Mondlampe")
        QUIET[0] = 0
        if okm:
            break
    else:
        print("DIORAMA kids: keine freie Stelle für die Mondlampe")
        return
    y = GROUND_Y
    KIDS.extend(cyl("k:farbe", cx, cz, 1.5, y, y + 0.7, 12, PAL["holzhell"], r_top=1.3, cap=True))
    KIDS.extend(dome("k:lampe", cx, cz, y + 2.1, 1.5, 12, 5, (1.0, 0.92, 0.7), lat0=-0.9))
    collide_circle(cx, cz, 1.6, 3.6, "mast")
    add_light(cx, cz, y + 2.2, (1.0, 0.82, 0.55), 0.55, 26.0, omni=False, glow=2.8)


def build_fairy_lights():
    """Lichterkette auf dem Regal (an der Vorderkante, Kabel und 15 Birnen): kleine warme und bunte Lichter, jedes zweite beleuchtet den Boden vor dem Regal."""
    cx, cz_wall, L, D, H = 46.0, z1 - 0.4, 48.0, 10.2, 14.0
    zf = cz_wall - D + 0.5
    y = GROUND_Y + H
    fr = Frame((cx, zf), (1.0, 0.0), (0.0, 1.0))
    KIDS.extend(cbox(fr, "k:farbe", -L / 2 + 0.8, L / 2 - 0.8, -0.05, 0.05, y, y + 0.07, PAL["schwarz"], 1.0, grad=(1, 1), sides=(0, 0, 0, 0)))
    keys = ["k:lampe", "k:ampel_gelb", "k:lampe", "k:ampel_rot", "k:lampe", "k:ampel_gruen", "k:lampe_blau"]
    pastel = [(1.0, 0.8, 0.55), (1.0, 0.6, 0.7), (0.65, 0.85, 1.0), (0.7, 1.0, 0.75)]
    n = 15
    for i in range(n):
        a = cx - L / 2 + 1.6 + i * (L - 3.2) / (n - 1)
        bf = Frame((a, zf), (1.0, 0.0), (0.0, 1.0))
        KIDS.extend(cbox(bf, keys[i % len(keys)], -0.17, 0.17, -0.17, 0.17, y + 0.04, y + 0.38, (1.0, 0.95, 0.85), 1.0, grad=(1, 1)))
        if i % 2 == 0:
            add_light(a, zf, y + 0.3, pastel[(i // 2) % 4], 0.22, 8.5, omni=False)


def build_toys():
    """Spielzeug und Dinge im Zimmer: große Stücke (Burg, Puppenhaus, Puzzle, Brettspiel) im Norden, danach Kleinteile an allen freien Stellen. Orte werden
    gesucht (Fahrschlauch bleibt frei, nichts überlappt); Plätze, die nicht passen, melden eine Warnung statt stillschweigend zu entfallen."""
    r_ = random.Random(77)

    def spot(builder, xr, zr, ang=(0.0, 360.0), args=(), n=80):
        QUIET[0] = 1
        ok = False
        for _ in range(n):
            a = r_.uniform(*ang) if isinstance(ang, tuple) else ang
            if builder(r_.uniform(*xr), r_.uniform(*zr), a, *args):
                ok = True
                break
        QUIET[0] = 0
        if not ok:
            print("DIORAMA kids: keine freie Stelle für", getattr(builder, "__name__", builder), xr, zr)
        return ok

    # Nordstreifen (z -58 bis -44), von West nach Ost
    spot(toy_castle, (-38, -30), (-55, -51), (-5.0, 5.0))
    spot(toy_puzzle, (-14, -8), (-55, -49), (-20.0, 20.0))
    spot(toy_board_game, (2, 9), (-55, -49), (-15.0, 15.0))
    spot(toy_dollhouse, (33, 46), (-55, -51), (-3.0, 3.0))
    spot(toy_dino, (55, 62), (-55, -48))
    # Fahrzeuge der Baustelle und Spielzeugautos (Süden und Westen)
    spot(toy_excavator, (-58, -34), (38, 50))
    spot(toy_tipper, (-50, -26), (36, 52))
    spot(toy_car, (-22, 14), (36, 46), (0.0, 360.0), n=80)
    spot(toy_car, (-22, 14), (36, 46), (0.0, 360.0), n=80)
    spot(toy_car, (66, 84), (-12, 4), (0.0, 360.0), n=80)
    # Plüsch, Gummitiere, Roboter
    spot(toy_bunny, (68, 84), (4, 14))
    spot(toy_robot, (68, 82), (-12, 0))
    spot(toy_dino, (68, 84), (30, 52))
    spot(toy_duck, (-84, -68), (18, 34))
    spot(toy_duck, (-16, 14), (-26, -18))
    spot(toy_duck, (60, 72), (8, 22))
    tea_party(-72.0, 44.0) or spot(tea_party_spot, (-80, -66), (30, 48), 0.0)
    # Westen: Hausschuhe, Bücher, Hefte
    spot(toy_slippers, (-84, -74), (24, 32))
    for xr, zr in (((-82, -68), (-48, -36)), ((-86, -68), (30, 40)), ((60, 84), (-14, 56)), ((-20, 20), (-30, -20))):
        spot(toy_books, xr, zr)
    spot(toy_notebook, (-62, -50), (-40, -34))
    spot(toy_notebook, (40, 64), (-44, -36))
    spot(toy_stickers, (-24, 0), (-58, -53))
    # Würfel, Karten, Papierflieger, Steckfiguren in allen Zonen
    zones = [((-80, -64), (-44, 54)), ((-30, 40), (-56, -42)), ((66, 86), (-12, 56)), ((-60, -26), (28, 56)), ((-24, 18), (30, 48)), ((-24, 36), (-26, 28))]
    for k in range(18):
        xr, zr = zones[k % len(zones)]
        spot(toy_dice, xr, zr, args=(r_.randrange(1, 7), r_.randrange(1, 7)), n=40)
    for k in range(16):
        xr, zr = zones[(k + 2) % len(zones)]
        spot(toy_card, xr, zr, args=(r_.choice([1, 1, 2, 3]),), n=40)
    for k in range(5):
        xr, zr = zones[(k * 2 + 1) % len(zones)]
        spot(toy_plane, xr, zr, n=40)
    for k in range(8):
        xr, zr = zones[(k * 3) % len(zones)]
        spot(toy_minifig, xr, zr, args=(None,), n=40)


def tea_party_spot(x, z, ang):
    return tea_party(x, z)


def build_scatter():
    """Bausteine, Murmeln und Buntstifte verstreut; um die Bauklotz-Gruppe und den Bausteinturm dichter. Lehnt die Platzprüfung einen festen Ort ab, wird
    in der Nähe gesucht (früher fielen diese Stücke weg und der Norden blieb leer)."""
    cols = TOYCOLS
    r_ = random.Random(31)

    def near_or_search(fn, x, z, ang, *args, span=(14.0, 10.0)):
        QUIET[0] = 1
        ok = fn(x, z, ang, *args)
        n = 0
        while not ok and n < 60:
            n += 1
            ok = fn(x + r_.uniform(-span[0], span[0]), z + r_.uniform(-span[1], span[1]), ang + r_.uniform(-30, 30), *args)
        QUIET[0] = 0
        if not ok:
            print("DIORAMA kids: keine freie Stelle für", getattr(fn, "__name__", fn), round(x), round(z))
        return ok

    spots = [(34.0 + 7.5, 7.0, 20), (27.0, -6.5, 100), (40.0, 11.5, 70), (-14.0, 32.0, 10), (-20.0, 44.0, 120), (-56.0, 24.0, 60), (-66.0, 40.0, 5),
             (8.0, -45.0, 40), (58.0, 45.0, 150), (-45.0, -22.0, 85), (-4.0, 22.0, 30), (66.0, 12.0, 95), (-38.0, 8.0, 15), (12.0, -52.0, 70)]
    for i, (x, z, a) in enumerate(spots):
        near_or_search(lambda xx, zz, aa, c=cols[i % len(cols)], nx=(4 if i % 3 else 2): place_brick(xx, zz, aa, c, nx, 2), x, z, a)
    # zwei gestapelte Steine an der Truhe
    for (x, z, a, c) in ((x0 + 15.0, z0 + 21.0, 30, PAL["rot"]), (x0 + 19.5, z0 + 22.0, 100, PAL["gelb"]), (x0 + 10.0, z0 + 21.5, 70, PAL["blau"])):
        near_or_search(lambda xx, zz, aa, c=c: place_brick(xx, zz, aa, c, 4, 2, margin=2.5), x, z, a, span=(6.0, 5.0))
    mcols = [(lin("e03a3a"), lin("f5f0e0")), (lin("2d6fe0"), lin("f5f0e0")), (lin("2fa84a"), lin("f5f0e0")), (lin("f5c52b"), lin("c43b2f")), (lin("8a3ad0"), lin("f5f0e0"))]
    for (x, z) in ((10.0, 12.0), (12.2, 14.0), (9.2, 15.0), (14.0, 11.0), (-26.0, 18.0), (-24.0, 20.5), (-27.5, 21.5), (-62.0, 12.0), (-60.0, 15.0), (55.0, 38.0), (57.0, 40.0), (50.0, -30.0),
                   (52.0, -33.0), (-8.0, -40.0), (-30.0, -52.0), (-12.0, -50.0), (4.0, -52.0), (30.0, -50.0), (62.0, -50.0), (-66.0, -22.0), (-70.0, 22.0), (72.0, 44.0)):
        a, b = r_.choice(mcols)
        near_or_search(lambda xx, zz, aa, a=a, b=b: marble(xx, zz, a, b), x, z, 0.0, span=(8.0, 6.0))
    # Buntstifte um den Stiftekasten (-50 | -50) und einzeln
    ccols = [PAL["rot"], PAL["gelb"], PAL["blau"], PAL["gruen"], PAL["orange"], PAL["lila"], PAL["braun"], PAL["rosa"]]
    for k, (x, z, a) in enumerate(((-39.5, -52.0, 12), (-61.0, -46.0, 98), (-47.0, -40.5, 160), (-55.0, -57.0, 30), (-30.0, 30.0, 140), (62.0, 30.0, 15), (-4.0, -50.0, 64), (36.0, -53.0, 175),
                                   (20.0, -56.0, 100), (-20.0, -42.0, 20), (50.0, -55.0, 60), (-70.0, -8.0, 130))):
        near_or_search(lambda xx, zz, aa, c=ccols[k % len(ccols)]: crayon(xx, zz, aa, c), x, z, a, span=(10.0, 6.0))


# ---------------------------------------------------------------- Sandkasten-Malheur (die langsame Stelle der Strecke)
# Die Streckendatei hat einen langsamen Belag "dirt" (surfaces: von 0,36 bis 0,46, Seite "inner"). Zur Laufzeit zeichnet das Spiel dafür nur einen
# dünnen Streifen (0,85 m breit, Höhe 0,13 m, Farbe des Themas), den der Teppich (ebenfalls 0,13 m) verschluckt. Im Diorama steht dort ein umgekipptes
# Sandkasten-Eimerchen, aus dem Sand über den Teppich bis an den Randstein geflossen ist: eine ausgefranste Sandfläche (Höhe 0,134 bis 0,157 m, unter der
# Fahrbahn) über der ganzen Zone und darüber hinaus, dazu Haufen, eine Schaufel, eine kleine Sandburg am Ende und verstreute Körner. Die Fläche ist ein
# Gitternetz, dessen Höhe stetig vom Sandfeld abhängt: die Schnittlinie mit dem Teppich ist der weiche, unregelmäßige Rand. Der Laufzeitstreifen
# bleibt im Spiel bestehen (einfache Grafikstufe), liegt im Diorama aber unter dem Sand.
SAND_SRC = {}
SAND_DUNES = []


def sand_zones():
    return [z for z in data.get("surfaces", []) if z.get("kind") == "dirt"]


def k_noise(x, z, scale, ox=0.0):
    """Weiches Wertrauschen (0..1) für numpy-Felder, wie value_noise des Kerns."""
    u, v = np.asarray(x) / scale + ox, np.asarray(z) / scale + ox * 0.61
    i0, j0 = np.floor(u).astype(int), np.floor(v).astype(int)
    fu, fv = u - i0, v - j0
    fu, fv = fu * fu * (3 - 2 * fu), fv * fv * (3 - 2 * fv)
    g = _noise_grid
    a = g[j0 % 64, i0 % 64] * (1 - fu) + g[j0 % 64, (i0 + 1) % 64] * fu
    b = g[(j0 + 1) % 64, i0 % 64] * (1 - fu) + g[(j0 + 1) % 64, (i0 + 1) % 64] * fu
    return a * (1 - fv) + b * fv


def k_nearest(P):
    """Nächste Mittellinienstütze (Index) und Seitenlage (links positiv, m) für viele Punkte."""
    Lf = np.array([[l.x, l.y] for l in left])
    idx = np.zeros(len(P), int)
    lat = np.zeros(len(P))
    for k in range(0, len(P), 1500):
        q = P[k:k + 1500]
        d2 = ((q[:, None, :] - C[None, :, :]) ** 2).sum(2)
        ii = d2.argmin(1)
        idx[k:k + 1500] = ii
        lat[k:k + 1500] = ((q - C[ii]) * Lf[ii]).sum(1)
    return idx, lat


def rug_y(P):
    """Oberkante des Bodens an den Punkten P (n x 2): Teppichfläche 0,13 m, sonst Parkett."""
    cx, cz = RUG["c"]
    a_ = math.radians(RUG["ang"])
    dx, dz = P[:, 0] - cx, P[:, 1] - cz
    a = dx * math.cos(a_) + dz * math.sin(a_)
    b = -dx * math.sin(a_) + dz * math.cos(a_)
    A, B = RUG["L"] / 2.0, RUG["W"] / 2.0
    return np.where((np.abs(a) <= A - 0.8) & (np.abs(b) <= B - 0.8), GROUND_Y + 0.05, GROUND_Y)


def sand_field(P, zone):
    """Sandfeld (0..1) je Punkt: in der Zone von der Fahrbahnkante (3,5 m) bis zu einem unregelmäßigen Rand bei 5,4 bis 7,2 m, vor der Zone ein Fächer
    vom Eimer, außen ausgefranst. li = Abstand zur Mittellinie auf der Streckenseite der Zone."""
    idx, lat = k_nearest(P)
    sgn = -1.0 if zone.get("side", "inner") == "inner" else 1.0
    li = lat * sgn
    s = idx / float(N)
    z0_, z1_ = float(zone["from"]), float(zone["to"])
    along = smooth(z0_ - 0.014, z0_ + 0.004, s) * (1.0 - smooth(z1_ - 0.004, z1_ + 0.016, s))
    nb_ = k_noise(P[:, 0], P[:, 1], 5.0, 3.0)
    nf_ = k_noise(P[:, 0], P[:, 1], 1.3, 11.0)
    outer_edge = 5.7 + 1.7 * (nb_ - 0.15) + 0.5 * (nf_ - 0.5)
    band = (1.0 - smooth(outer_edge - 0.8, outer_edge, li)) * smooth(3.3, 3.7, li)
    m = along * band
    for (bx, bz, r_) in SAND_SRC.get("path", []):         # Fächer vom Eimer bis in die Zone: Gaußblasen entlang der Fließrichtung
        d2 = (P[:, 0] - bx) ** 2 + (P[:, 1] - bz) ** 2
        m = np.maximum(m, 1.05 * np.exp(-d2 / (r_ * r_)))
    return np.clip(m * (0.9 + 0.2 * nf_), 0.0, 1.0)


def at_s(s, li, side_sign=-1.0):
    """Punkt bei Streckenanteil s und Abstand li von der Mittellinie (side_sign -1: Innenseite) -> (Vector 2, Index)."""
    i = int(round(s * N)) % N
    return center[i] + left[i] * (side_sign * li), i


def build_sand():
    zones = sand_zones()
    if not zones:
        return
    zone = zones[0]
    sign = -1.0 if zone.get("side", "inner") == "inner" else 1.0
    z0_, z1_ = float(zone["from"]), float(zone["to"])
    rr = random.Random(58)
    # Eimer neben dem Anfang der Zone, die Mündung zeigt zur Fahrbahn; der Sand fließt als Fächer in die Zone
    pb, ib = at_s(z0_ - 0.012, 8.6, sign)
    to_road = Vector((left[ib].x * -sign, left[ib].y * -sign))
    ang_b = math.degrees(math.atan2(to_road.y, to_road.x)) + 14.0
    tn = tang[ib]
    SAND_SRC["path"] = []
    for k in range(7):
        t = k / 6.0
        q = pb + to_road * (2.0 + 3.4 * t) + tn * (1.0 * t)
        SAND_SRC["path"].append((float(q.x), float(q.y), 1.15 - 0.15 * t + 0.1 * rr.random()))
    # Reservierung: Spielzeug darf nicht auf den Sand (Streifen quer von 2,5 bis 9,5 m, entlang der Zone)
    i0, i1 = int((z0_ - 0.02) * N), int((z1_ + 0.02) * N)
    for i in range(i0, i1, 8):
        i = i % N
        c = center[i] + left[i] * (sign * 6.0)
        keep_out(c.x, c.y, tang[i].x, tang[i].y, 2.6, 3.8)
    cell = 0.5
    pts_c = np.array([[center[i % N].x, center[i % N].y] for i in range(i0 - 20, i1 + 21)])
    xa, xb = pts_c[:, 0].min() - 11.0, pts_c[:, 0].max() + 11.0
    za, zb = pts_c[:, 1].min() - 11.0, pts_c[:, 1].max() + 11.0
    gx = np.arange(math.floor(xa), math.ceil(xb) + 0.001, cell)
    gz = np.arange(math.floor(za), math.ceil(zb) + 0.001, cell)
    X, Z = np.meshgrid(gx, gz)
    P = np.stack([X.ravel(), Z.ravel()], 1)
    m = sand_field(P, zone).reshape(X.shape)
    ry = rug_y(P).reshape(X.shape)
    ripple = 0.004 * (k_noise(X, Z, 1.6, 31.0) - 0.5) + 0.006 * (k_noise(X, Z, 4.5, 47.0) - 0.5)
    H = ry + 0.004 + np.minimum(0.055 * (m - 0.45), 0.014) + ripple * (m > 0.3)
    H = np.minimum(H, 0.157)
    skip = np.maximum.reduce([m[:-1, :-1], m[1:, :-1], m[:-1, 1:], m[1:, 1:]]) < 0.34
    nz, nx = len(gz), len(gx)
    bm = bmesh.new()
    uv0 = bm.loops.layers.uv.new("UVMap")
    uv1 = bm.loops.layers.uv.new("Licht")          # Licht-UV wie beim Kern: liest die gebackene Verdeckung des Teppichs darunter
    verts = {}

    def vert(i, j):
        if (i, j) not in verts:
            verts[(i, j)] = bm.verts.new((float(gx[i]), -float(gz[j]), float(H[j, i])))
        return verts[(i, j)]

    tris = 0
    for j in range(nz - 1):
        for i in range(nx - 1):
            if skip[j, i]:
                continue
            quad = ((i, j), (i, j + 1), (i + 1, j + 1), (i + 1, j))
            f = bm.faces.new([vert(a, b) for a, b in quad])
            f.smooth = True
            for loop, (a, b) in zip(f.loops, quad):
                loop[uv0].uv = (float(gx[a]) / 6.0, float(-gz[b]) / 6.0)
                loop[uv1].uv = ((float(gx[a]) - x0) / (x1 - x0), 1.0 - (float(gz[b]) - z0) / (z1 - z0))
            tris += 2
    bm.normal_update()
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    bm.normal_update()
    me = bpy.data.meshes.new("Sand_Flaeche")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(M["k_sand"])
    obj = bpy.data.objects.new("Sand_Flaeche", me)
    scene.collection.objects.link(obj)
    print("DIORAMA kids: Sandfläche", tris, "Dreiecke, höchste Stelle %.3f m (Fahrbahn 0.17)" % float(H[m > 0.45].max()))
    build_sand_props(zone, sign, pb, to_road, ang_b, rr)


def lying_cone(fr, a0, a1, r0, r1, y0, col, key="k:farbe", n=14):
    """Liegender Kegelstumpf (Achse längs fr.u, Fuß am Boden y0; Radius r0 bei a0, r1 bei a1): nur die Oberseite und die Flanken."""
    P = []

    def ring(a, k):
        r = r0 + (r1 - r0) * (a - a0) / (a1 - a0)
        ph = 2 * math.pi * k / n
        c = fr.pt(a, math.cos(ph) * r)
        return (c.x, c.y, y0 + r + math.sin(ph) * r)

    for k in range(n):
        phm = 2 * math.pi * (k + 0.5) / n
        if math.sin(phm) < -0.45:
            continue
        hv = math.cos(phm)
        face = (fr.v.x * hv, fr.v.y * hv) if abs(hv) > 0.3 else None
        P.append(poly(key, [ring(a0, k), ring(a0, k + 1), ring(a1, k + 1), ring(a1, k)], col, face, 1.0, [(0, 0), (1, 0), (1, 1), (0, 1)]))
    return P


def sand_heap(cx, cz, r, h, y0, n=14, rot=0.0, rings=(1.0, 0.64, 0.3)):
    """Sandhaufen: stumpfer Kegel in Ringen (unten r, oben spitz), Flächen mit planarer UV (Sand sieht von oben aus wie die Fläche, nicht gestreift)."""
    out = []
    hs = (0.0, 0.5 * h, 0.86 * h)
    for k in range(len(rings)):
        r0, r1 = r * rings[k], (r * rings[k + 1] if k + 1 < len(rings) else 0.0)
        z0_, z1_ = y0 + hs[k], (y0 + hs[k + 1] if k + 1 < len(rings) else y0 + h)
        for i in range(n):
            a0, a1 = rot + 2 * math.pi * i / n, rot + 2 * math.pi * (i + 1) / n
            p0 = (cx + r0 * math.cos(a0), cz + r0 * math.sin(a0), z0_)
            p1 = (cx + r0 * math.cos(a1), cz + r0 * math.sin(a1), z0_)
            q1 = (cx + r1 * math.cos(a1), cz + r1 * math.sin(a1), z1_)
            q0 = (cx + r1 * math.cos(a0), cz + r1 * math.sin(a0), z1_)
            am = (a0 + a1) / 2
            face = (math.cos(am), math.sin(am))
            pts = [p0, p1, q1, q0] if r1 > 0.01 else [p0, p1, q1]
            out.append(poly("k_sand", pts, None, face, 6.0, [(p[0] / 6.0, -p[1] / 6.0) for p in pts]))
    return out


def build_sand_props(zone, sign, pb, to_road, ang_b, rr):
    """Eimer, Schaufel, Sandhaufen, Burg und Körner."""
    P = KIDS
    y = GROUND_Y + 0.05 + 0.006
    # Eimer: gelb mit rotem Rand, liegt auf der Seite, Mündung zur Fahrbahn
    fr = frame_at(pb.x, pb.y, ang_b)
    P += lying_cone(fr, -1.9, 1.0, 1.05, 1.5, y, PAL["gelb"], n=14)
    P += lying_cone(fr, 1.0, 1.35, 1.5, 1.62, y, PAL["rot"], n=14)
    base_pts = []
    for k in range(14):
        ph = 2 * math.pi * k / 14
        c = fr.pt(-1.9, math.cos(ph) * 1.05)
        base_pts.append((c.x, c.y, y + 1.05 + math.sin(ph) * 1.05))
    P.append(poly("k:farbe", base_pts, shade(PAL["gelb"], 0.85), (-fr.u.x, -fr.u.y)))
    mouth_pts = []
    for k in range(14):
        ph = 2 * math.pi * k / 14
        c = fr.pt(1.0, math.cos(ph) * 1.4)
        mouth_pts.append((c.x, c.y, y + 1.5 + math.sin(ph) * 1.35))
    P.append(poly("k_sand", mouth_pts, None, (fr.u.x, fr.u.y), 6.0))
    c0 = fr.pt(-0.4, 0.0)
    collide_rect(c0.x, c0.y, fr.u.x, fr.u.y, 1.9, 1.5, 3.0, "bank")
    # Schaufel (blau, oranger Stiel) liegt im Sand neben dem Eimer
    sp, _ = at_s(float(zone["from"]) + 0.03, 8.0, sign)
    sf = frame_at(sp.x, sp.y, math.degrees(math.atan2(to_road.y, to_road.x)) + 55.0)
    P += cbox(sf, "k:farbe", -1.3, 1.8, -0.13, 0.13, y, y + 0.22, lin("ee7d22"), 1.0, grad=(0.85, 1.0))
    P += cbox(sf, "k:farbe", 1.8, 2.8, -0.55, 0.55, y, y + 0.16, lin("2d5fc4"), 1.0, grad=(0.85, 1.0))
    P += cbox(sf, "k:farbe", -1.9, -1.3, -0.3, 0.3, y, y + 0.3, lin("ee7d22"), 1.0, grad=(0.85, 1.0))
    # Sandhaufen entlang der Zone (stumpfe Kegel mit aufgesetzter kleinerer Kuppe)
    spots = [(float(zone["from"]) + 0.012, 7.0, 1.5, 0.95), (float(zone["from"]) + 0.052, 8.4, 1.2, 0.8), (float(zone["from"]) + 0.075, 7.3, 1.7, 1.05)]
    yb = GROUND_Y + 0.05 + 0.002
    for (s_, li, r_, h_) in spots:
        c, _ = at_s(s_, li, sign)
        P += sand_heap(c.x, c.y, r_, h_, yb, 16, rr.uniform(0, 3))
        c2 = c + Vector((rr.uniform(-0.6, 0.6), rr.uniform(-0.6, 0.6)))
        P += sand_heap(c2.x, c2.y, r_ * 0.6, h_ * 0.8, yb, 10, rr.uniform(0, 3))
    # Sandburg am Ende der Zone: Sockel mit drei Türmen und Fähnchen
    cc, ic = at_s(float(zone["to"]) + 0.022, 8.6, sign)
    fc = frame_at(cc.x, cc.y, math.degrees(math.atan2(tang[ic].y, tang[ic].x)))
    P += sand_heap(cc.x, cc.y, 1.9, 1.3, yb, 16, 0.2, rings=(1.0, 0.8, 0.7))
    for (a, b, r_, h_) in ((-1.1, -0.9, 0.62, 2.1), (1.2, -0.7, 0.55, 1.9), (0.1, 1.2, 0.58, 2.3)):
        q = fc.pt(a, b)
        P += cyl("k_sand", q.x, q.y, r_, yb + 0.9, yb + 0.9 + h_, 10, None, r_top=r_ * 0.8, cap=True, tile=6.0)
        P += cyl("k_sand", q.x, q.y, r_ * 1.12, yb + 0.9 + h_, yb + 1.1 + h_, 10, None, r_top=r_ * 1.12, cap=True, tile=6.0)
    ytop = yb + 0.9 + 2.3 + 0.2
    P += cbox(fc, "k:farbe", 0.1 - 0.04, 0.1 + 0.04, 1.2 - 0.04, 1.2 + 0.04, ytop, ytop + 1.3, lin("deb882"), 1.0, grad=(1, 1))
    flag = [(*fc.pt(0.14, 1.2), ytop + 1.3), (*fc.pt(0.14, 1.2), ytop + 0.8), (*fc.pt(0.84, 1.2), ytop + 1.05)]
    P.append(poly("k:farbe", flag, PAL["rot"], (fc.v.x, fc.v.y)))
    P.append(poly("k:farbe", flag[::-1], PAL["rot"], (-fc.v.x, -fc.v.y)))
    collide_circle(cc.x, cc.y, 1.9, 2.4, "bank")
    # verstreute Körner: Dreieckchen in Sandfarben, nach außen dünner
    cols = [lin("e3c98f"), lin("d6b878"), lin("c9a665"), lin("efd9a5")]
    z0_, z1_ = float(zone["from"]), float(zone["to"])
    n_g = 0
    for _ in range(3200):
        s_ = rr.uniform(z0_ - 0.03, z1_ + 0.03)
        li = 3.7 + 7.0 * rr.random() ** 1.8
        c, ic = at_s(s_, li, sign)
        if road_gap([(c.x, c.y)]) < HW + 0.2 or not (x0 + 1.0 <= c.x <= x1 - 1.0 and z0 + 1.0 <= c.y <= z1 - 1.0):
            continue
        r_ = rr.uniform(0.035, 0.1)
        yy = float(rug_y(np.array([[c.x, c.y]]))[0]) + 0.007
        th = rr.uniform(0, 6.28)
        pts = [(c.x + r_ * math.cos(th + k * 2.1), c.y + r_ * math.sin(th + k * 2.1), yy) for k in range(3)]
        P.append(poly("k:farbe", pts, shade(cols[rr.randrange(4)], rr.uniform(0.85, 1.05))))
        n_g += 1
    print("DIORAMA kids: Sand-Szene: Körner", n_g)


# ---------------------------------------------------------------- Hooks
# ---------------------------------------------------------------- Lineal-Wippe (Höhenplan 4.4/7): Filzstift, Straßen-Spielteppich, Kratzspuren
# Das Lineal selbst ist ein Laufzeit-Bauteil: world.gd (build_seesaw_nodes) lädt game/assets/props/kinder_lineal.glb (tools/make_kids_ruler.py)
# am Drehpunkt und kippt es mit dem Simulationszustand. Das Diorama backt darunter den Filzstift (Drehachse, mit Umgebungsverdeckung; seine Enden
# sind die Collider "mauer" der Streckendatei), legt die Abkürzung als Straßen-Spielteppich aus (graue Filzbahn mit weißen Randlinien; die
# dunkle Laufzeit-Fahrbahn der Abkürzung liegt mittig darauf), hält einen Korridor frei und zeichnet Abriebspuren, wo die Linealenden aufschlagen.
K_SEESAW_LIFT = 0.17    # Darstellung: das Lineal liegt wie jede Laufzeit-Fahrbahn 0,17 m über der Simulationshöhe (world.gd SEESAW_LIFT; Autos + 0,2)
K_PEN_R = 0.36          # Filzstift: Mindestradius; build_pen rechnet ihn so, dass die Oberkante die Unterseite des Lineals am Drehpunkt trägt
                        # (pivot_h + K_SEESAW_LIFT − Dicke = 0,97 m über dem Boden -> Radius 0,445 m bei GROUND_Y 0,08)
K_LANE = 3.5            # Korridor ohne Spielzeug: Abstand (m) zur Pfadmitte der Abkürzung
K_MAT_HALF = 2.45       # halbe Breite des Straßen-Spielteppichs (Laufzeit-Fahrbahn: 2,0)
K_MAT_LIFT = 0.022     # Filzbahn über dem Parkett (GROUND_Y)


def k_path():
    sc = data.get("shortcuts", [])
    return [Vector((float(p[0]), float(p[1]))) for p in sc[0]["path"]] if sc else []


def k_path_at(path, m):
    """Punkt und Richtung bei Pfadmeter m (wie Circuit.path_pose)."""
    acc = 0.0
    for a, b in zip(path, path[1:]):
        seg = (b - a).length
        if acc + seg >= m or b is path[-1]:
            t = max(0.0, min(1.0, (m - acc) / seg)) if seg > 1e-9 else 0.0
            return a.lerp(b, t), (b - a).normalized()
        acc += seg
    return path[-1], (path[-1] - path[-2]).normalized()


def k_seesaw():
    """Erste Wippe: (Drehpunkt, Achse u zur Ausfahrt, Querachse v = links von u, Eintrag) oder None."""
    ws, path = data.get("seesaws", []), k_path()
    if not ws or len(path) < 2:
        return None
    c, u = k_path_at(path, float(ws[0].get("at", 0.0)))
    return c, u, Vector((-u.y, u.x)), ws[0]


def reserve_shortcut():
    """Korridor der Abkürzung (K_LANE beiderseits der Pfadmitte) und Filzstift für Spielzeug sperren."""
    path = k_path()
    for a, b in zip(path, path[1:]):
        d = b - a
        if d.length < 1e-6:
            continue
        m = (a + b) * 0.5
        u = d.normalized()
        keep_out(m.x, m.y, u.x, u.y, d.length / 2 + 0.6, K_LANE)
    w = k_seesaw()
    if w:
        c, u, v, _ = w
        keep_out(c.x, c.y, v.x, v.y, 3.9, 0.9)


def k_tube(fr, a0, a1, r0, r1, yc, col, n=16, key="k:farbe"):
    """Liegender Kegelstumpf mit fester Achse (Höhe yc, längs fr.u von a0 bis a1, Radius r0 bis r1): Flanken und Oberseite, ohne Unterseite."""
    P = []

    def ring(a, k):
        r = r0 + (r1 - r0) * (a - a0) / (a1 - a0)
        ph = 2 * math.pi * k / n
        q = fr.pt(a, math.cos(ph) * r)
        return (q.x, q.y, yc + math.sin(ph) * r)

    for k in range(n):
        phm = 2 * math.pi * (k + 0.5) / n
        if math.sin(phm) < -0.45:
            continue
        hv = math.cos(phm)
        face = (fr.v.x * hv, fr.v.y * hv) if abs(hv) > 0.3 else None
        P.append(poly(key, [ring(a0, k), ring(a0, k + 1), ring(a1, k + 1), ring(a1, k)], col, face, 1.0, [(0, 0), (1, 0), (1, 1), (0, 1)]))
    return P


def build_pen():
    """Grüner Filzstift (7 m, Durchmesser 0,89 m) quer unter dem Drehpunkt: Schaft, aufgesteckte Kappe mit Clip am einen Ende, Griffzone,
    Konus und Filzspitze am anderen. Liegt auf dem Parkett; seine Oberkante trägt das Lineal. Die Hindernisse sind die Collider der Streckendatei."""
    w = k_seesaw()
    if not w:
        return
    c, u, v, spec = w
    fr = Frame((c.x, c.y), (v.x, v.y), (u.x, u.y))                 # a längs des Stifts (quer zum Lineal)
    y0 = GROUND_Y
    r = max(K_PEN_R, (float(spec.get("pivot_h", 1.1)) + K_SEESAW_LIFT - float(spec.get("thickness", 0.3)) - y0) / 2.0)
    green, dark, light = lin("2f9a4c"), lin("1d6b33"), lin("6fc48a")
    P = KIDS
    yc = y0 + r
    P += k_tube(fr, -2.1, 2.45, r, r, yc, green)                                     # Schaft
    P += k_tube(fr, -1.0, 0.9, r + 0.006, r + 0.006, yc, lin("f1ede2"))               # weißes Etikett (unter dem Lineal, von der Seite sichtbar)
    P += k_tube(fr, 2.45, 2.95, r, r * 0.86, yc, light)                               # Griffzone
    P += k_tube(fr, 2.95, 3.22, r * 0.86, r * 0.42, yc, lin("e8e4da"), 14)            # Konus (weißer Kunststoff)
    P += k_tube(fr, 3.22, 3.5, r * 0.42, r * 0.16, yc, dark, 10)                      # Filzspitze
    P += k_tube(fr, -3.5, -2.0, r + 0.05, r + 0.05, yc, dark)                         # aufgesteckte Kappe
    P += cbox(fr, "k:farbe", -3.25, -2.35, -0.07, 0.07, yc + r + 0.03, yc + r + 0.1, dark, 1.0, grad=(0.9, 1.0))   # Clip
    ring = []
    for k in range(16):                                                                     # Kappenboden
        ph = 2 * math.pi * k / 16
        q = fr.pt(-3.5, math.cos(ph) * (r + 0.05))
        ring.append((q.x, q.y, yc + math.sin(ph) * (r + 0.05)))
    P.append(poly("k:farbe", ring, shade(dark, 0.9), (-fr.u.x, -fr.u.y)))
    print("DIORAMA kids: Filzstift unter dem Lineal bei", round(c.x, 2), round(c.y, 2), "Oberkante", round(y0 + 2 * r, 3),
          "(Lineal-Unterseite am Drehpunkt", round(float(spec.get("pivot_h", 1.1)) + K_SEESAW_LIFT - float(spec.get("thickness", 0.3)), 3), ")")


def ruler_ao():
    """Kontaktschatten des Lineals in Ruhelage (Einfahrt unten): schräge Platte als AO-Stellvertreter (nur beim Backen)."""
    w = k_seesaw()
    if not w:
        return
    c, u, v, spec = w
    half, hw_ = float(spec.get("length", 24.0)) / 2, float(spec.get("width", 4.0)) / 2
    ph = math.asin(min(1.0, float(spec.get("pivot_h", 1.1)) / half))
    th = float(spec.get("thickness", 0.3))
    pts = {}
    for sa in (-1, 1):
        for sb in (-1, 1):
            q = c + u * (sa * half) + v * (sb * hw_)
            top = float(spec.get("pivot_h", 1.1)) + K_SEESAW_LIFT + sa * half * math.sin(ph)
            pts[(sa, sb, 1)] = (q.x, q.y, top)
            pts[(sa, sb, 0)] = (q.x, q.y, top - th)
    F = lambda *k: [pts[i] for i in k]
    parts = [poly("ao", F((-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1))), poly("ao", F((-1, -1, 0), (-1, 1, 0), (1, 1, 0), (1, -1, 0))),
             poly("ao", F((-1, -1, 0), (1, -1, 0), (1, -1, 1), (-1, -1, 1)), None, (-v.x, -v.y)), poly("ao", F((-1, 1, 0), (-1, 1, 1), (1, 1, 1), (1, 1, 0)), None, (v.x, v.y)),
             poly("ao", F((1, -1, 0), (1, 1, 0), (1, 1, 1), (1, -1, 1)), None, (u.x, u.y))]
    add_ao_parts(parts)


def build_road_mat():
    """Straßen-Spielteppich unter der Abkürzung: graue Filzbahn (K_MAT_HALF), weiße Randlinien knapp außerhalb der Laufzeit-Fahrbahn, helle
    Steppnaht am Rand; unter dem Lineal keine Linien (dort liegt das Lineal), an den Enden unter der Spielzeugbahn. Bodenauflage mit AO."""
    path = k_path()
    if len(path) < 2:
        return
    w = k_seesaw()
    pts = resample_path([(p.x, p.y) for p in path], 1.0)
    cum = [0.0]
    for a, b in zip(pts, pts[1:]):
        cum.append(cum[-1] + (b - a).length)
    m_lo, m_hi = -1.0, -1.0
    if w:
        at, half = float(w[3].get("at", 0.0)), float(w[3].get("length", 24.0)) / 2
        m_lo, m_hi = at - half - 0.3, at + half + 0.3
    felt, edge, line = lin("5b6168"), lin("8a9096"), lin("f2f0e8")
    KFLOOR.extend(ribbon_poly([(p.x, p.y) for p in pts], 2 * K_MAT_HALF, GROUND_Y + K_MAT_LIFT, "k_wolle", felt, 2.0))
    for sgn in (1.0, -1.0):
        for off, wid, col, dy in ((2.17, 0.16, line, 0.006), (K_MAT_HALF - 0.06, 0.05, edge, 0.006)):
            run = []
            for i, p in enumerate(pts):
                a = pts[max(i - 1, 0)]
                b = pts[min(i + 1, len(pts) - 1)]
                t = (b - a).normalized()
                n = Vector((-t.y, t.x))
                inside = m_lo <= cum[i] <= m_hi and col is line
                if inside:
                    if len(run) > 1:
                        KFLOOR.extend(ribbon_poly(run, wid, GROUND_Y + K_MAT_LIFT + dy, "k_wolle", col, 1.0))
                    run = []
                    continue
                q = p + n * (sgn * off)
                run.append((q.x, q.y))
            if len(run) > 1:
                KFLOOR.extend(ribbon_poly(run, wid, GROUND_Y + K_MAT_LIFT + dy, "k_wolle", col, 1.0))
    # Abrieb, wo die Linealenden auf den Teppich schlagen (Ruhelage: Einfahrtsende; gekippt: Ausfahrtsende): hellere, aufgeraute Filzflecken
    # neben der Laufzeit-Fahrbahn und feine helle Kratzer im Parkett dahinter
    if w:
        c, u, v, spec = w
        rr = random.Random(9)
        half, hw_ = float(spec.get("length", 24.0)) / 2, float(spec.get("width", 4.0)) / 2
        for sa in (-1.0, 1.0):
            for sb in (-1.0, 1.0):
                base = c + u * (sa * (half - 0.3)) + v * (sb * (hw_ + 0.22))
                for k in range(3):
                    q = base + u * rr.uniform(-0.6, 0.6) + v * (sb * rr.uniform(-0.1, 0.12))
                    ring = []
                    for j in range(10):
                        ang = 2 * math.pi * j / 10
                        rq = q + u * (math.cos(ang) * rr.uniform(0.35, 0.6)) + v * (math.sin(ang) * rr.uniform(0.08, 0.16))
                        ring.append((rq.x, rq.y, GROUND_Y + K_MAT_LIFT + 0.011))
                    KFLOOR.append(poly("k_wolle", ring, lin("9aa0a6"), None, 1.0))
                for k in range(5):                                      # Kratzer im Parkett jenseits des Teppichs
                    q = c + u * (sa * (half - rr.uniform(-0.2, 0.9))) + v * (sb * (K_MAT_HALF + rr.uniform(0.15, 0.7)))
                    d = (u * rr.uniform(0.7, 1.6) + v * rr.uniform(-0.25, 0.25))
                    nn = Vector((-d.y, d.x)).normalized() * rr.uniform(0.015, 0.03)
                    a, b = q - d * 0.5, q + d * 0.5
                    KFLOOR.append(poly("k_parkett", [(a.x - nn.x, a.y - nn.y, GROUND_Y + 0.006), (b.x - nn.x, b.y - nn.y, GROUND_Y + 0.006),
                                                     (b.x + nn.x, b.y + nn.y, GROUND_Y + 0.006), (a.x + nn.x, a.y + nn.y, GROUND_Y + 0.006)],
                                       lin("f6e2c0"), None, 1.0))
    print("DIORAMA kids: Straßen-Spielteppich der Abkürzung", round(cum[-1], 1), "m, Lineal von Pfadmeter", round(m_lo, 1), "bis", round(m_hi, 1))


def theme_ground():
    objs_ground.append(mesh_object("Boden_parkett", floor_rect("k_parkett", x0, x1, z0, z1, GROUND_Y)))


def theme_scenery():
    reserve_runtime()
    reserve_shortcut()
    for name, fn in (("Filzstift", build_pen), ("Spielteppich-Straße", build_road_mat), ("Teppich", build_rug), ("Wände", build_walls), ("Regal", build_shelf), ("Bett", build_bed), ("Truhe", build_chest), ("Fensterlicht", build_light_patch),
                     ("Zeichnung", paper_and_ruler), ("Mondlampe", build_moon_lamp), ("Lichterkette", build_fairy_lights), ("Sand", build_sand), ("Spielzeug", build_toys), ("Streugut", build_scatter)):
        try:
            fn()
        except Exception as error:
            import traceback
            print("DIORAMA kids FEHLER in", name, ":", error)
            traceback.print_exc()
    if KFLOOR:
        objs_ground.append(mesh_object("Boden_teppich", KFLOOR))
    mesh_objects("Zimmer", KIDS)
    kids_ao()
    ruler_ao()
    print("DIORAMA kids: Flächen", len(KIDS), "Hindernisse", len(colliders), "Lichter", len(extra_lights))


def theme_bake_hidden():
    return ["Sand"]


def fix_vertex_colors():
    """Kern-Eigenheit umgehen: mesh_object setzt das Farbattribut nicht aktiv, der glTF-Export (ACTIVE) schreibt dann COLOR_0 weiß."""
    for o in scene.objects:
        me = getattr(o, "data", None)
        ca = getattr(me, "color_attributes", None)
        if ca is not None and len(ca) and ca.active_color is None:
            ca.active_color = ca[0]
            ca.render_color_index = 0


def theme_layout(layout):
    fix_vertex_colors()
