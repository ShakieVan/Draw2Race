"""Geometriebausteine für das Küstenstadion „Azure Coast Speedway“ (Thema coast, tools/dio_themes/coast.py).

Reine Geometrie ohne Blender-Abhängigkeit (testbar mit gewöhnlichem Python). Alle Koordinaten sind Spielkoordinaten: (x, z) in der
Ebene, y ist die Höhe. Ein Teil („Fläche“) hat das Format von tools/diorama.py:
    (Materialschlüssel, Ecken [(x, z, y)], UVs, Blickrichtung (x, z) | "down" | None, Vertexfarben | None)
„k:farbe“ ist das einfarbige Bausatzmaterial (nur Vertexfarbe, Farben linear), alle anderen Schlüssel sind Materialien, die das Thema
selbst anlegt (z. B. „sitz_az“, „mauer“, „lkw_azure“). Blickrichtung None = waagerecht, nach oben; „down“ = waagerecht, nach unten.

Inhalt: Farben, Grundkörper (Quader, Zylinder, Rad, Strebe), Oval (Versatzlinien zur Mittellinie), Zaun und Mauer, Tribünen
(Sitzreihen, Menge, Gänge, Rückwand), Segeldach, Boxengebäude, Transporter, Rennwagen, Reifenstapel, Videowand, Flaggen.
"""
import math
import random

# ---------------------------------------------------------------- Farben (sRGB-Hex -> linear)


def lin(c):
    if isinstance(c, str):
        c = c.lstrip("#")
        c = tuple(int(c[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return tuple(max(0.0, v) ** 2.2 for v in c)


def shade(c, k):
    return tuple(min(1.0, v * k) for v in c)


AZURE = lin("#1b86c9")
AZURE_D = lin("#0e4f86")
NAVY = lin("#123a5c")
WHITE = lin("#f3f5f6")
OFFWHITE = lin("#e2e5e6")
CONCRETE = lin("#c9cccd")
CONCRETE_D = lin("#8e9395")
SAND = lin("#e6d2a8")
CORAL = lin("#ef6a4c")
TEAL = lin("#16a0a3")
STEEL = lin("#8d959c")
STEEL_D = lin("#4c5359")
DARK = lin("#202327")
BLACK = lin("#0d0e10")
GLASS = lin("#183645")
ASPHALT = lin("#4a4d50")
TIRE = lin("#17181a")
RIM = lin("#b9bec3")
YELLOW = lin("#f3c031")
RED = lin("#c3221c")
GRAY_L = lin("#d7d9da")
GRAY_M = lin("#a3a8ab")


def rgb_mix(a, b, t):
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3))


# ---------------------------------------------------------------- Grundflächen
def add(parts, key, pts, uvs=None, facing=None, colors=None):
    if uvs is None:
        uvs = [(0, 0), (1, 0), (1, 1), (0, 1)] if len(pts) == 4 else [(0, 0), (1, 0), (0.5, 1)] if len(pts) == 3 else [(0, 0)] * len(pts)
    parts.append((key, pts, uvs, facing, colors))


def vquad(parts, p0, p1, y0, y1, out, color, ao=0.84, key="k:farbe", uvs=None):
    """Senkrechte Fläche von p0 nach p1 (x, z), zwischen y0 und y1; unten dunkler (Kontaktverdeckung)."""
    cb = shade(color, ao) if color is not None else None
    ct = color
    add(parts, key, [(p0[0], p0[1], y0), (p1[0], p1[1], y0), (p1[0], p1[1], y1), (p0[0], p0[1], y1)], uvs, out,
        [cb, cb, ct, ct] if color is not None else None)


def hquad(parts, pts4, y, color, key="k:farbe", up=True, uvs=None):
    """Waagerechte Fläche (Ecken (x, z)) auf Höhe y; up False = Blick nach unten."""
    add(parts, key, [(p[0], p[1], y) for p in pts4], uvs, None if up else "down", [color] * len(pts4) if color is not None else None)


def sloped(parts, pts3, color, key="k:farbe", up=True, uvs=None, colors=None):
    """Beliebige Fläche mit Ecken (x, z, y); Blick nach oben (Normale zeigt nach oben) oder nach unten."""
    add(parts, key, pts3, uvs, None if up else "down", colors if colors is not None else ([color] * len(pts3) if color is not None else None))


def box(parts, cx, cz, ux, uz, a, b, y0, y1, color, key="k:farbe", ao=0.82, top=1.06, bottom=False):
    """Quader um (cx, cz); a entlang u = (ux, uz), b entlang v = (-uz, ux); Seiten unten dunkler, abwechselnd leicht verschieden."""
    n = math.hypot(ux, uz) or 1.0
    ux, uz = ux / n, uz / n
    vx, vz = -uz, ux
    corners = []
    for sa, sb in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        corners.append((cx + ux * sa * a / 2 + vx * sb * b / 2, cz + uz * sa * a / 2 + vz * sb * b / 2))
    for i in range(4):
        p0, p1 = corners[i], corners[(i + 1) % 4]
        out = ((p0[0] + p1[0]) / 2 - cx, (p0[1] + p1[1]) / 2 - cz)
        vquad(parts, p0, p1, y0, y1, out, shade(color, 1.0 if i % 2 == 0 else 0.92), ao, key)
    hquad(parts, corners[::-1], y1, shade(color, top), key)
    if bottom:
        hquad(parts, corners, y0, shade(color, 0.6), key, up=False)


def boxd(parts, x0, x1, z0, z1, y0, y1, color, key="k:farbe", ao=0.82, top=1.06, bottom=False):
    """Achsenparalleler Quader von (x0, z0) bis (x1, z1)."""
    box(parts, (x0 + x1) / 2, (z0 + z1) / 2, 1.0, 0.0, x1 - x0, z1 - z0, y0, y1, color, key, ao, top, bottom)


def cyl(parts, cx, cz, r, y0, y1, color, sides=8, r_top=None, ao=0.85, cap=True, key="k:farbe"):
    """Stehender Zylinder bzw. Kegelstumpf (r_top)."""
    rt = r if r_top is None else r_top
    ring0 = [(cx + r * math.cos(2 * math.pi * k / sides), cz + r * math.sin(2 * math.pi * k / sides)) for k in range(sides)]
    ring1 = [(cx + rt * math.cos(2 * math.pi * k / sides), cz + rt * math.sin(2 * math.pi * k / sides)) for k in range(sides)]
    for k in range(sides):
        k2 = (k + 1) % sides
        mid = ((ring0[k][0] + ring0[k2][0]) / 2 - cx, (ring0[k][1] + ring0[k2][1]) / 2 - cz)
        tone = 0.9 + 0.12 * math.cos(2 * math.pi * (k + 0.5) / sides)
        cb, ct = shade(color, tone * ao), shade(color, tone)
        add(parts, key, [(ring0[k][0], ring0[k][1], y0), (ring0[k2][0], ring0[k2][1], y0), (ring1[k2][0], ring1[k2][1], y1), (ring1[k][0], ring1[k][1], y1)],
            None, mid, [cb, cb, ct, ct])
    if cap and rt > 0.0:
        add(parts, key, [(p[0], p[1], y1) for p in ring1[::-1]], None, None, [shade(color, 1.08)] * sides)


def strut(parts, p0, p1, w, color, key="k:farbe"):
    """Dünner Stab zwischen zwei Punkten (x, z, y): zwei gekreuzte Flächen der Breite w (doppelseitig dargestellt)."""
    d = (p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2])
    ln = math.sqrt(d[0] ** 2 + d[1] ** 2 + d[2] ** 2) or 1.0
    d = (d[0] / ln, d[1] / ln, d[2] / ln)
    # Seitenvektoren: s1 waagerecht quer zum Stab, s2 quer dazu
    s1 = (-d[1], d[0], 0.0)           # (x, z, y)-Komponenten: waagerecht senkrecht zur Horizontalprojektion
    if math.hypot(s1[0], s1[1]) < 1e-6:
        s1 = (1.0, 0.0, 0.0)
    else:
        m = math.hypot(s1[0], s1[1])
        s1 = (s1[0] / m, s1[1] / m, 0.0)
    s2 = (d[1] * s1[2] - d[2] * s1[1], d[2] * s1[0] - d[0] * s1[2], d[0] * s1[1] - d[1] * s1[0])
    m2 = math.sqrt(s2[0] ** 2 + s2[1] ** 2 + s2[2] ** 2) or 1.0
    s2 = (s2[0] / m2, s2[1] / m2, s2[2] / m2)
    for s in (s1, s2):
        h = w / 2
        pts = [(p0[0] - s[0] * h, p0[1] - s[1] * h, p0[2] - s[2] * h), (p0[0] + s[0] * h, p0[1] + s[1] * h, p0[2] + s[2] * h),
               (p1[0] + s[0] * h, p1[1] + s[1] * h, p1[2] + s[2] * h), (p1[0] - s[0] * h, p1[1] - s[1] * h, p1[2] - s[2] * h)]
        add(parts, key, pts, None, None, [color] * 4)


def wheel(parts, cx, cz, ux, uz, a, lat, rad, width, yc, tire=TIRE, rim=RIM, sides=10, hub=0.62):
    """Rad mit waagerechter Achse quer zur Fahrtrichtung u: Mitte a vor/zurück, lat seitlich (v = (-uz, ux)), Radius, Breite, Höhe der Achse."""
    vx, vz = -uz, ux
    ring = [(a + rad * math.cos(2 * math.pi * k / sides), yc + rad * math.sin(2 * math.pi * k / sides)) for k in range(sides)]

    def W(aa, ll, yy):
        return (cx + ux * aa + vx * ll, cz + uz * aa + vz * ll, yy)
    for k in range(sides):
        (a0, y0), (a1, y1) = ring[k], ring[(k + 1) % sides]
        cm = math.cos(2 * math.pi * (k + 0.5) / sides)
        tone = 0.9 + 0.1 * math.sin((k + 0.5) * 2 * math.pi / sides)
        add(parts, "k:farbe", [W(a0, lat - width / 2, y0), W(a1, lat - width / 2, y1), W(a1, lat + width / 2, y1), W(a0, lat + width / 2, y0)], None,
            (ux * cm, uz * cm) if abs(cm) > 0.25 else None, [shade(tire, tone)] * 4)
    for sgn in (-1, 1):
        lat_s = lat + sgn * width / 2
        out = (vx * sgn, vz * sgn)
        pts = [W(a + rad * math.cos(2 * math.pi * k / sides), lat_s, yc + rad * math.sin(2 * math.pi * k / sides)) for k in range(sides)]
        add(parts, "k:farbe", pts, None, out, [shade(tire, 0.8)] * sides)
        pts = [W(a + hub * rad * math.cos(2 * math.pi * k / sides), lat_s + sgn * 0.004, yc + hub * rad * math.sin(2 * math.pi * k / sides)) for k in range(sides)]
        add(parts, "k:farbe", pts, None, out, [rim] * sides)


# ---------------------------------------------------------------- Oval: Versatzlinien zur Mittellinie
class Oval:
    """Versatzlinien zur Mittellinie: p(i, d) = Punkt bei Index i im Abstand d (d > 0 nach außen, d < 0 zur Innenfläche)."""

    def __init__(self, pts, lefts, sign, straight):
        self.pts, self.lefts, self.sign, self.n = pts, lefts, sign, len(pts)
        self.straight = straight           # Liste: ist die Mittellinie bei Index i gerade?
        self._cum = {}

    def p(self, i, d):
        k = i % self.n
        return (self.pts[k][0] + self.lefts[k][0] * self.sign * d, self.pts[k][1] + self.lefts[k][1] * self.sign * d)

    def out(self, i):
        k = i % self.n
        return (self.lefts[k][0] * self.sign, self.lefts[k][1] * self.sign)

    def fwd(self, i):
        """Fahrtrichtung (Einheitsvektor) bei Index i."""
        k = i % self.n
        a, b = self.pts[(k - 1) % self.n], self.pts[(k + 1) % self.n]
        dx, dz = b[0] - a[0], b[1] - a[1]
        m = math.hypot(dx, dz) or 1.0
        return (dx / m, dz / m)

    def cum(self, d):
        key = round(d, 3)
        if key not in self._cum:
            c = [0.0]
            for i in range(self.n):
                a, b = self.p(i, d), self.p(i + 1, d)
                c.append(c[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
            self._cum[key] = c
        return self._cum[key]

    def u(self, i, d):
        """Länge entlang der Linie im Abstand d bis zum Index i (läuft über den Ringschluss hinaus weiter)."""
        c = self.cum(d)
        return c[i % self.n] + (i // self.n) * c[self.n]

    def span(self, i0, i1, step_curve=3, step_straight=12):
        """Indexbereich i0..i1 in Stücke teilen: auf Geraden lang, in Kurven kurz."""
        out, j = [], i0
        while j < i1:
            st = step_straight if all(self.straight[(j + t) % self.n] for t in range(0, min(step_straight, i1 - j) + 1)) else step_curve
            jn = min(j + st, i1)
            out.append((j, jn))
            j = jn
        return out


# ---------------------------------------------------------------- Sicherheitsmauer und Fangzaun
def build_wall(ov, i0, i1, d, y_base, thick=0.35, h=0.9, fence_h=2.5, lean=0.45, tile=12.0, post_every=3.0):
    """Betonmauer (Schriftbahn „mauer“) mit Fangzaun darüber (Pfosten, Drahtseile, Holm). Rückgabe: Teile."""
    parts = []
    d_in, d_out = d - thick / 2, d + thick / 2
    y_top = y_base + h
    total_in, total_out = ov.cum(d_in)[-1], ov.cum(d_out)[-1]
    tile_in, tile_out = total_in / max(1, round(total_in / tile)), total_out / max(1, round(total_out / tile))
    for (ja, jb) in ov.span(i0, i1, 2, 8):
        a_in, b_in = ov.p(ja, d_in), ov.p(jb, d_in)
        a_out, b_out = ov.p(ja, d_out), ov.p(jb, d_out)
        ua, ub = ov.u(ja, d_in), ov.u(jb, d_in)
        # Innenseite (zur Strecke): der Betrachter schaut nach außen, sein Rechts ist Gegen-Indexrichtung -> Schrift läuft gegen den Index
        add(parts, "mauer", [(a_in[0], a_in[1], y_base), (b_in[0], b_in[1], y_base), (b_in[0], b_in[1], y_top), (a_in[0], a_in[1], y_top)],
            [(-ua / tile_in, 0.0), (-ub / tile_in, 0.0), (-ub / tile_in, 1.0), (-ua / tile_in, 1.0)], (-ov.out(ja)[0], -ov.out(ja)[1]), None)
        ua2, ub2 = ov.u(ja, d_out), ov.u(jb, d_out)
        add(parts, "mauer", [(a_out[0], a_out[1], y_base), (b_out[0], b_out[1], y_base), (b_out[0], b_out[1], y_top), (a_out[0], a_out[1], y_top)],
            [(ua2 / tile_out, 0.0), (ub2 / tile_out, 0.0), (ub2 / tile_out, 1.0), (ua2 / tile_out, 1.0)], ov.out(ja), None)
        hquad(parts, [a_in, b_in, b_out, a_out][::-1], y_top + 0.04, WHITE)
        # Deckleiste: etwas überstehend
        for (pa, pb, off) in ((a_in, b_in, -1), (a_out, b_out, 1)):
            o = ov.out(ja)
            vquad(parts, pa, pb, y_top, y_top + 0.04, (o[0] * off, o[1] * off), OFFWHITE, 1.0)
    # Fangzaun: geneigt zur Strecke, fünf Drahtseile, Holm, Pfosten
    for (ja, jb) in ov.span(i0, i1, 2, 8):
        for lvl in (0.18, 0.36, 0.54, 0.72):
            ta = lvl
            a = ov.p(ja, d - lean * ta)
            b = ov.p(jb, d - lean * ta)
            ya = y_top + 0.04 + fence_h * ta
            o = ov.out(ja)
            vquad(parts, a, b, ya - 0.025, ya + 0.025, o, GRAY_M, 1.0)
            add(parts, "k:farbe", [(a[0], a[1], ya - 0.025), (b[0], b[1], ya - 0.025), (b[0], b[1], ya + 0.025), (a[0], a[1], ya + 0.025)], None,
                (-o[0], -o[1]), [GRAY_M] * 4)
        a = ov.p(ja, d - lean)
        b = ov.p(jb, d - lean)
        o = ov.out(ja)
        yt = y_top + 0.04 + fence_h
        vquad(parts, a, b, yt - 0.07, yt + 0.07, o, AZURE, 1.0)
        add(parts, "k:farbe", [(a[0], a[1], yt - 0.07), (b[0], b[1], yt - 0.07), (b[0], b[1], yt + 0.07), (a[0], a[1], yt + 0.07)], None, (-o[0], -o[1]),
            [AZURE] * 4)
    run = 0.0
    last = ov.p(i0, d)
    for i in range(i0, i1 + 1):
        pt = ov.p(i, d)
        run += math.hypot(pt[0] - last[0], pt[1] - last[1])
        last = pt
        if run >= post_every or i == i0 or i == i1:
            run = 0.0
            p_a = ov.p(i, d)
            p_b = ov.p(i, d - lean)
            strut(parts, (p_a[0], p_a[1], y_top), (p_b[0], p_b[1], y_top + 0.04 + fence_h), 0.11, STEEL_D)
    return parts


# ---------------------------------------------------------------- Tribünen
CROWD_TILE = 6.0                 # Länge einer Mengenkachel (m), wie in tools/diorama.py


def build_stand(ov, i0, i1, rows, rng, d0, y_base, row_d=0.8, rise=0.45, h0=0.55, sec_len=18, aisle_w=2, density=0.9, seats=("sitz_az", "sitz_wh"),
                caps=(True, True), cap_skip=(0, 0), back_h=1.1, seat_w=None, salt=0):
    """Tribüne zwischen den Indizes i0..i1 der Mittellinie: Sitzreihen (Farbblöcke je Abschnitt und Reihengruppe), Stufen, Gänge, Menge (Dichte und
    Lücken je Block und Reihe, Streifen zufälliger Länge, Größe und Versatz, Leute auf den Treppen), Stirn- und Rückwand.
    seats: Materialschlüssel der Sitzfarben, seat_w: Gewichte. density: mittlere Füllung (vorn dichter, hinten lichter).
    Rückgabe: (Teile, Höhe der letzten Sitzreihe über y_base, d der Rückwand)."""
    parts = []
    seat_w = seat_w or [1.0] * len(seats)
    # Abschnitte: Sitzblock (sec_len Indizes), Gang (aisle_w Indizes) ...
    chunks = []
    idx, sec = i0, 0
    while idx < i1:
        s_end = min(idx + sec_len, i1)
        for (ja, jb) in ov.span(idx, s_end, 3, 14):
            chunks.append((ja, jb, False, sec))
        idx = s_end
        if idx < i1:
            jn = min(idx + aisle_w, i1)
            chunks.append((idx, jn, True, sec))
            idx = jn
        sec += 1
    y_of = lambda k: y_base + h0 + k * rise
    band_rows = 3                                                       # Reihen je Farbblock
    block_seat, block_fill = {}, {}

    def block(secn, k):
        """Sitzfarbe und Füllgrad (0..1) des Blocks (Abschnitt, Reihengruppe); Nachbarblöcke haben verschiedene Farben."""
        key = (secn, k // band_rows)
        if key not in block_seat:
            r = random.Random(salt * 7919 + secn * 131 + (k // band_rows) * 17 + 5)
            for _ in range(6):
                c = r.choices(range(len(seats)), weights=seat_w)[0]
                if (secn - 1, key[1]) in block_seat and block_seat[(secn - 1, key[1])] == c:
                    continue
                if (secn, key[1] - 1) in block_seat and block_seat[(secn, key[1] - 1)] == c:
                    continue
                break
            block_seat[key] = c
            u = r.random()
            block_fill[key] = 0.5 + 0.5 * (u ** 0.5) if r.random() < 0.82 else 0.1 + 0.3 * u         # meist gut gefüllt, einzelne fast leere Blöcke
        return seats[block_seat[key]], block_fill[key]

    for k in range(rows):
        da, db = d0 + k * row_d, d0 + (k + 1) * row_d
        y_hi = y_of(k)
        y_lo = y_of(k - 1) if k > 0 else y_base
        row_fall = 1.0 - 0.26 * (k / max(1, rows - 1)) ** 1.2            # hinten lichter
        for (ja, jb, aisle, sec) in chunks:
            a0, a1 = ov.p(ja, da), ov.p(jb, da)
            b0, b1 = ov.p(ja, db), ov.p(jb, db)
            fo = ov.out(ja)
            # Stufenstirn (zur Strecke)
            riser_col = shade(OFFWHITE, 0.95) if not aisle else shade(CONCRETE, 0.9)
            vquad(parts, a0, a1, y_lo, y_hi, (-fo[0], -fo[1]), riser_col, 0.78)
            ua0, ua1 = ov.u(ja, da), ov.u(jb, da)
            ub0, ub1 = ua0, ua1                                          # u radial (keine Scherung zwischen den Ringen)
            if aisle:
                hquad(parts, [b0, b1, a1, a0], y_hi, shade(CONCRETE, 1.05 + 0.03 * (k % 2)))
                # Leute auf den Treppen: gelegentlich eine Person (ein Streifen von etwa einem Mann Breite) auf der Stufe
                if rng.random() < 0.16 * row_fall and (jb - ja) >= 2:
                    t = rng.uniform(0.3, 0.7)
                    wq = 0.46 / max(1e-6, math.hypot(a1[0] - a0[0], a1[1] - a0[1]))
                    t0, t1 = max(0.0, t - wq / 2), min(1.0, t + wq / 2)
                    m = 0.08
                    P0 = ov.p(ja, da + m)
                    P1 = ov.p(jb, da + m)
                    R0 = ov.p(ja, db - m)
                    R1 = ov.p(jb, db - m)
                    lp = lambda p, q, f: (p[0] + (q[0] - p[0]) * f, p[1] + (q[1] - p[1]) * f)
                    uo = rng.uniform(0.0, CROWD_TILE)
                    vn, vf = (1.0, 0.5) if rng.random() < 0.5 else (0.5, 0.0)
                    pts = [lp(P0, P1, t0), lp(P0, P1, t1), lp(R0, R1, t1), lp(R0, R1, t0)]
                    add(parts, "e:menge", [(p[0], p[1], y_hi + 0.03) for p in pts], [(uo / CROWD_TILE, vn), ((uo + 0.46) / CROWD_TILE, vn),
                                                                                       ((uo + 0.46) / CROWD_TILE, vf), (uo / CROWD_TILE, vf)], None, None)
                continue
            key, fill = block(sec, k)
            add(parts, key, [(a0[0], a0[1], y_hi), (a1[0], a1[1], y_hi), (b1[0], b1[1], y_hi), (b0[0], b0[1], y_hi)],
                [(ua0 / 0.5, 0.0), (ua1 / 0.5, 0.0), (ub1 / 0.5, 1.0), (ub0 / 0.5, 1.0)], None, None)
            # Menge: Streifen zufälliger Länge (1,3 bis 3,4 m); je Streifen: da/nicht da, Versatz, Größe, Spiegelung, Reihe der Mengentextur
            p_fill = min(0.97, density * fill * row_fall + 0.04)
            L = math.hypot(a1[0] - a0[0], a1[1] - a0[1])
            m = 0.06
            Q0, Q1 = ov.p(ja, da + m), ov.p(jb, da + m)
            R0, R1 = ov.p(ja, db - m), ov.p(jb, db - m)
            lp = lambda p, q, f: (p[0] + (q[0] - p[0]) * f, p[1] + (q[1] - p[1]) * f)
            pos = 0.0
            while pos < L - 0.05:
                step = L if L < 2.2 else rng.uniform(1.3, 3.4)
                end = min(L, pos + step)
                if L - end < 0.9:
                    end = L
                if rng.random() < p_fill:
                    f0, f1 = pos / L, end / L
                    pts = [lp(Q0, Q1, f0), lp(Q0, Q1, f1), lp(R0, R1, f1), lp(R0, R1, f0)]
                    su = rng.uniform(0.84, 1.18)                          # Größe der Leute (kleiner = größer dargestellt)
                    off = rng.uniform(0.0, CROWD_TILE)
                    u_a, u_b = (ua0 + (ua1 - ua0) * f0) * su + off, (ua0 + (ua1 - ua0) * f1) * su + off
                    if rng.random() < 0.45:
                        u_a, u_b = u_b, u_a                              # gespiegelt
                    vn, vf = (1.0, 0.5) if rng.random() < 0.5 else (0.5, 0.0)
                    add(parts, "e:menge", [(p[0], p[1], y_hi + 0.03) for p in pts],
                        [(u_a / CROWD_TILE, vn), (u_b / CROWD_TILE, vn), (u_b / CROWD_TILE, vf), (u_a / CROWD_TILE, vf)], None, None)
                pos = end
    d_back = d0 + rows * row_d
    y_last = y_of(rows - 1)
    y_wall = y_last + back_h
    # Rückwand: außen Beton (Schriftbahn „beton“), innen weiß; oben Abdeckung
    for (ja, jb) in ov.span(i0, i1, 3, 14):
        a, b = ov.p(ja, d_back), ov.p(jb, d_back)
        a2, b2 = ov.p(ja, d_back + 0.5), ov.p(jb, d_back + 0.5)
        fo = ov.out(ja)
        ua, ub = ov.u(ja, d_back + 0.5), ov.u(jb, d_back + 0.5)
        add(parts, "beton", [(a2[0], a2[1], y_base), (b2[0], b2[1], y_base), (b2[0], b2[1], y_wall), (a2[0], a2[1], y_wall)],
            [(ua / 4.0, 0.0), (ub / 4.0, 0.0), (ub / 4.0, (y_wall - y_base) / 2.0), (ua / 4.0, (y_wall - y_base) / 2.0)], fo, None)
        vquad(parts, a, b, y_last, y_wall, (-fo[0], -fo[1]), OFFWHITE, 0.85)
        hquad(parts, [a, b, b2, a2][::-1], y_wall, WHITE)
    # Handläufe an den Gängen (schräg über alle Reihen) und Zugänge (dunkle Türen mit weißem Rahmen) in der Rückwand
    for (ja, jb, aisle, sec) in chunks:
        if not aisle:
            continue
        for j in (ja, jb):
            p_lo, p_hi = ov.p(j, d0 - 0.05), ov.p(j, d_back)
            strut(parts, (p_lo[0], p_lo[1], y_of(0) + 0.95), (p_hi[0], p_hi[1], y_last + 0.95), 0.07, WHITE)
        a, b = ov.p(ja, d_back + 0.5), ov.p(jb, d_back + 0.5)
        fo = ov.out(ja)
        ln = math.hypot(b[0] - a[0], b[1] - a[1])
        if ln < 0.3:
            continue
        ex, ez = (b[0] - a[0]) / ln, (b[1] - a[1]) / ln
        for (grow, y1, col) in ((0.3, 2.9, OFFWHITE), (0.0, 2.55, shade(DARK, 1.3))):
            pa = (a[0] - ex * grow + fo[0] * (0.01 + 0.012 * (grow == 0.0)), a[1] - ez * grow + fo[1] * (0.01 + 0.012 * (grow == 0.0)))
            pb = (b[0] + ex * grow + fo[0] * (0.01 + 0.012 * (grow == 0.0)), b[1] + ez * grow + fo[1] * (0.01 + 0.012 * (grow == 0.0)))
            vquad(parts, pa, pb, y_base, y_base + y1, fo, col, 1.0)
    # Stirnwände (Treppenprofil) an den freien Enden
    for (ja, end) in ((i0, -1), (i1, 1)):
        if not caps[0 if end < 0 else 1]:
            continue
        f = ov.fwd(ja)
        o = (f[0] * end, f[1] * end)
        for k in range(cap_skip[0 if end < 0 else 1], rows):
            da, db = d0 + k * row_d, d0 + (k + 1) * row_d
            pa, pb = ov.p(ja, da), ov.p(ja, db)
            vquad(parts, pa, pb, y_base, y_of(k), o, CONCRETE, 0.8)
        pa, pb = ov.p(ja, d_back), ov.p(ja, d_back + 0.5)
        vquad(parts, pa, pb, y_base, y_wall, o, CONCRETE, 0.8)
    return parts, y_last - y_base, d_back


def build_barrier(ov, i0, i1, d, y_base, h=1.05, base=0.35):
    """Glasbrüstung an der Stirn der ersten Sitzreihe (gläserne Fläche, Holm), über den Indexbereich."""
    parts = []
    for (ja, jb) in ov.span(i0, i1, 3, 14):
        a, b = ov.p(ja, d), ov.p(jb, d)
        fo = ov.out(ja)
        vquad(parts, a, b, y_base + base, y_base + base + h, (-fo[0], -fo[1]), GLASS, 1.0, key="glas")
        vquad(parts, a, b, y_base + base, y_base + base + h, fo, GLASS, 1.0, key="glas")
        vquad(parts, a, b, y_base + base + h, y_base + base + h + 0.06, (-fo[0], -fo[1]), WHITE, 1.0)
        a2, b2 = ov.p(ja, d + 0.06), ov.p(jb, d + 0.06)
        hquad(parts, [a, b, b2, a2][::-1], y_base + base + h + 0.06, WHITE)
    return parts


def banner_strip(ov, i0, i1, d, y0, y1, cells, step=6):
    """Werbebanner (E_banner, Bildaufteilung 2 x 4) in Feldern von 2,2 m, zur Strecke gerichtet; Schrift läuft passend zur Blickrichtung."""
    parts = []
    k = 0
    for (ja, jb) in ov.span(i0, i1, step, step):
        a, b = ov.p(ja, d), ov.p(jb, d)
        fo = ov.out(ja)
        cell = cells[k % len(cells)]
        k += 1
        c, r = cell % 2, cell // 2
        u0, u1 = c / 2.0, (c + 1) / 2.0
        v1, v0 = 1.0 - r / 4.0, 1.0 - (r + 1) / 4.0
        # Betrachter auf der Strecke: Rechts = Gegen-Indexrichtung -> a (kleiner Index) liegt rechts im Bild
        add(parts, "e:banner", [(a[0], a[1], y0), (b[0], b[1], y0), (b[0], b[1], y1), (a[0], a[1], y1)],
            [(u1, v0), (u0, v0), (u0, v1), (u1, v1)], (-fo[0], -fo[1]), None)
    return parts


# ---------------------------------------------------------------- Lichtblocker (nur Berechnung, keine Geometrie im Bild)
def hood_poly(cx, cz, aim, r_in=1.4, r_out=2.0, half_deg=100.0, n=8):
    """Blende hinter einer Lichtquelle bei (cx, cz): Halbring (Kreisbogen) auf der Seite, die von der Zielrichtung aim (Einheitsvektor) abgewandt ist.
    Als Lichtblocker in der Lichtkarte des Spiels hält er das Licht vom Rücken der Lampe fern (wie die Blende eines Flutlichts)."""
    ab = math.atan2(-aim[1], -aim[0])
    half = math.radians(half_deg)
    angs = [ab - half + 2 * half * k / (n - 1) for k in range(n)]
    outer = [(cx + r_out * math.cos(a), cz + r_out * math.sin(a)) for a in angs]
    inner = [(cx + r_in * math.cos(a), cz + r_in * math.sin(a)) for a in reversed(angs)]
    return outer + inner


def stand_dims(rows, d0=7.5, row_d=0.8, rise=0.45, h0=0.55, back_h=1.1):
    """(Höhe der Rückwand-Oberkante über dem Boden, d der Rückwand) einer Tribüne mit rows Reihen (wie build_stand)."""
    return h0 + (rows - 1) * rise + back_h, d0 + rows * row_d
