"""Gemeinsame Geometrie-Helfer der Themenmodule "fair" (Fun Fair Eight) und "kids" (Toy Box Speedway).

Wird NICHT einzeln gestartet: tools/dio_themes/fair.py und kids.py führen diese Datei per exec in die Globals von tools/diorama.py aus
(Blender). Deshalb stehen hier nur Definitionen; alle Kern-Helfer (Frame, box, flat, mesh_object, M, scene ...) sind zur Laufzeit der
Funktionen sichtbar. Flächenformat wie im Kern: (Materialschlüssel, Ecken [(x, z, y)], UVs, Blickrichtung (x, z) | None,
Vertexfarben [(r, g, b)] | None) in Spielkoordinaten (x, z, Höhe y).

Farben sind linear (wie bei tools/kit_car.py); lin("c0392b") rechnet sichtbare sRGB-Werte um.
"""


def lin(c):
    """sRGB ("rrggbb" oder (r, g, b) in 0..1) -> linear."""
    if isinstance(c, str):
        c = c.lstrip("#")
        c = [int(c[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(((v + 0.055) / 1.055) ** 2.4 if v > 0.04045 else v / 12.92 for v in c)


def shade(c, k):
    return (c[0] * k, c[1] * k, c[2] * k)


def mixc(a, b, t):
    return tuple(x * (1 - t) + y * t for x, y in zip(a, b))


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def poly(key, pts, col=None, facing=None, tile=1.0, uv=None, grad=None):
    """Fläche mit beliebig vielen Ecken (x, z, y) in einheitlichem Umlaufsinn. UV: automatisch in Kacheleinheiten (m / tile): waagerecht
    nach (x, z), senkrecht nach (Weg entlang der Wand, Höhe). col: eine Farbe oder je Ecke; grad = (unten, oben): Verdunkelungsfaktoren nach
    Höhe (billige Verdeckung, y0..y1 der Fläche). facing (x, z): Blickrichtung senkrechter bzw. geneigter Flächen."""
    n = len(pts)
    if uv is None:
        ex = (pts[1][0] - pts[0][0], pts[1][2] - pts[0][2], pts[1][1] - pts[0][1])
        fx = (pts[2][0] - pts[0][0], pts[2][2] - pts[0][2], pts[2][1] - pts[0][1])
        nx = ex[1] * fx[2] - ex[2] * fx[1]
        ny = ex[2] * fx[0] - ex[0] * fx[2]
        nz = ex[0] * fx[1] - ex[1] * fx[0]
        ln = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
        if abs(ny) / ln > 0.6:
            uv = [(p[0] / tile, p[1] / tile) for p in pts]
        else:
            tx, tz = -nz, nx
            tl = math.hypot(tx, tz) or 1.0
            tx, tz = tx / tl, tz / tl
            uv = [((p[0] * tx + p[1] * tz) / tile, p[2] / tile) for p in pts]
    cols = None
    if col is not None:
        if isinstance(col[0], (tuple, list)):
            cols = [tuple(c) for c in col]
        else:
            cols = [tuple(col)] * n
            if grad is not None:
                ys = [p[2] for p in pts]
                y0, y1 = min(ys), max(ys)
                if y1 - y0 > 1e-4:
                    cols = [shade(col, grad[0] + (grad[1] - grad[0]) * (p[2] - y0) / (y1 - y0)) for p in pts]
    return (key, [tuple(p) for p in pts], uv, facing, cols)


def cbox(fr, key, a0, a1, b0, b1, y0, y1, col=None, tile=1.0, grad=(0.78, 1.0), top=True, bottom=False, sides=(1, 1, 1, 1)):
    """Quader im Bezugssystem fr (Flächen: oben, vier Wände, auf Wunsch unten). sides = (-b, +b, -a, +a) schaltet Wände ein/aus."""
    P = lambda a, b, y: (*fr.pt(a, b), y)
    out = []
    if top:
        out.append(poly(key, [P(a0, b0, y1), P(a1, b0, y1), P(a1, b1, y1), P(a0, b1, y1)], col, None, tile))
    if bottom:
        out.append(poly(key, [P(a0, b0, y0), P(a0, b1, y0), P(a1, b1, y0), P(a1, b0, y0)], col, None, tile))
    ud, vd = fr.u, fr.v
    for on, (pa, pb, qa, qb), face in ((sides[0], (a0, b0, a1, b0), (-vd.x, -vd.y)), (sides[1], (a1, b1, a0, b1), (vd.x, vd.y)),
                                       (sides[2], (a0, b1, a0, b0), (-ud.x, -ud.y)), (sides[3], (a1, b0, a1, b1), (ud.x, ud.y))):
        if on:
            out.append(poly(key, [P(pa, pb, y0), P(qa, qb, y0), P(qa, qb, y1), P(pa, pb, y1)], col, face, tile, None, grad))
    return out


def cyl(key, cx, cz, r, y0, y1, n=10, col=None, r_top=None, cap=True, tile=1.0, grad=(0.78, 1.0), rot=0.0, uv_turn=None):
    """Stehender Zylinder bzw. Kegelstumpf (r unten, r_top oben) mit n Seiten."""
    rt = r if r_top is None else r_top
    out = []
    ring0 = [(cx + r * math.cos(rot + 2 * math.pi * k / n), cz + r * math.sin(rot + 2 * math.pi * k / n)) for k in range(n)]
    ring1 = [(cx + rt * math.cos(rot + 2 * math.pi * k / n), cz + rt * math.sin(rot + 2 * math.pi * k / n)) for k in range(n)]
    circ = 2 * math.pi * max(r, rt) / tile
    for k in range(n):
        a, b = ring0[k], ring0[(k + 1) % n]
        c, d = ring1[(k + 1) % n], ring1[k]
        mid = ((a[0] + b[0]) / 2 - cx, (a[1] + b[1]) / 2 - cz)
        uv = [(circ * k / n, 0.0), (circ * (k + 1) / n, 0.0), (circ * (k + 1) / n, (y1 - y0) / tile), (circ * k / n, (y1 - y0) / tile)]
        out.append(poly(key, [(a[0], a[1], y0), (b[0], b[1], y0), (c[0], c[1], y1), (d[0], d[1], y1)], col, mid, tile, uv, grad))
    if cap and rt > 1e-4:
        top_col = col[0] if (col is not None and isinstance(col[0], (tuple, list))) else col
        out.append(poly(key, [(p[0], p[1], y1) for p in ring1], top_col, None, tile,
                        [((p[0] - cx) / tile + 0.5, (p[1] - cz) / tile + 0.5) for p in ring1]))
    return out


def dome(key, cx, cz, y_c, r, n=8, rings=3, col=None, lat0=-0.25, cols_alt=None):
    """Kuppel (obere Kugelhälfte ab Breite lat0, Bogenmaß) für Murmeln, Glühbirnen, Bälle. y_c = Höhe des Kugelmittelpunkts.
    cols_alt: zweite Farbe, wechselt je Segment (Murmel mit zwei Farben)."""
    out = []
    lats = [lat0 + (math.pi / 2 - lat0) * i / rings for i in range(rings + 1)]
    for i in range(rings):
        for k in range(n):
            pts = []
            for (la, kk) in ((lats[i], k), (lats[i], k + 1), (lats[i + 1], k + 1), (lats[i + 1], k)):
                ang = 2 * math.pi * kk / n
                pts.append((cx + r * math.cos(la) * math.cos(ang), cz + r * math.cos(la) * math.sin(ang), y_c + r * math.sin(la)))
            c = col if (cols_alt is None or (k + (i % 2)) % 2 == 0) else cols_alt
            if i == rings - 1:
                pts = [pts[0], pts[1], pts[2]]
            mid = ((pts[0][0] + pts[1][0]) / 2 - cx, (pts[0][1] + pts[1][1]) / 2 - cz)
            out.append(poly(key, pts, c, mid if i < rings - 1 else None, 1.0, None, None))
    return out


def gable(fr, key, a0, a1, b0, b1, y0, y1, col=None, tile=4.0, ridge_along="a"):
    """Satteldach über dem Rechteck a0..a1 x b0..b1: Traufe auf Höhe y0, First auf y1. ridge_along "a": First längs a (Dachflächen zu ±b).
    UV: u längs des Firsts, v den Hang hinauf (Kachelreihen laufen parallel zur Traufe)."""
    out = []
    P = lambda a, b, y: (*fr.pt(a, b), y)
    if ridge_along == "a":
        bm = (b0 + b1) / 2
        L = math.hypot(bm - b0, y1 - y0)
        for sgn, bb, face in ((-1, b0, (-fr.v.x, -fr.v.y)), (1, b1, (fr.v.x, fr.v.y))):
            if sgn < 0:
                pts, uv = [P(a0, bb, y0), P(a1, bb, y0), P(a1, bm, y1), P(a0, bm, y1)], [(a0, 0), (a1, 0), (a1, L), (a0, L)]
            else:
                pts, uv = [P(a1, bb, y0), P(a0, bb, y0), P(a0, bm, y1), P(a1, bm, y1)], [(a1, 0), (a0, 0), (a0, L), (a1, L)]
            out.append(poly(key, pts, col, face, tile, [(u / tile, v / tile) for u, v in uv]))
        for aa, face in ((a0, (-fr.u.x, -fr.u.y)), (a1, (fr.u.x, fr.u.y))):
            out.append(poly(key, [P(aa, b0, y0), P(aa, b1, y0), P(aa, bm, y1)], col, face, tile))
    else:
        am = (a0 + a1) / 2
        L = math.hypot(am - a0, y1 - y0)
        for sgn, aa, face in ((-1, a0, (-fr.u.x, -fr.u.y)), (1, a1, (fr.u.x, fr.u.y))):
            if sgn < 0:
                pts, uv = [P(aa, b1, y0), P(aa, b0, y0), P(am, b0, y1), P(am, b1, y1)], [(b1, 0), (b0, 0), (b0, L), (b1, L)]
            else:
                pts, uv = [P(aa, b0, y0), P(aa, b1, y0), P(am, b1, y1), P(am, b0, y1)], [(b0, 0), (b1, 0), (b1, L), (b0, L)]
            out.append(poly(key, pts, col, face, tile, [(u / tile, v / tile) for u, v in uv]))
        for bb, face in ((b0, (-fr.v.x, -fr.v.y)), (b1, (fr.v.x, fr.v.y))):
            out.append(poly(key, [P(a0, bb, y0), P(a1, bb, y0), P(am, bb, y1)], col, face, tile))
    return out


def ribbon_poly(path, width, y, key, col=None, tile=1.0, closed=False, y_end=None):
    """Band entlang einer Polylinie (Liste (x, z)) mit Gehrungsecken; Höhe y (optional bis y_end linear)."""
    pts = [Vector(p) for p in path]
    n = len(pts)
    left = []
    for i in range(n):
        a = pts[i - 1] if (i > 0 or closed) else pts[i]
        b = pts[(i + 1) % n] if (i < n - 1 or closed) else pts[i]
        t = (b - a)
        if t.length < 1e-9:
            t = Vector((1, 0))
        t.normalize()
        left.append(Vector((-t.y, t.x)))
    # Gehrung
    off = []
    for i in range(n):
        if (i == 0 or i == n - 1) and not closed:
            off.append(left[i] * (width / 2))
        else:
            l0, l1 = left[i - 1] if i > 0 else left[i], left[i]
            m = (l0 + l1)
            if m.length < 1e-6:
                m = l1
            m.normalize()
            off.append(m * (width / 2) / max(0.4, m.dot(l1)))
    out = []
    dist_ = 0.0
    segs = n if closed else n - 1
    for i in range(segs):
        j = (i + 1) % n
        yi = y if y_end is None else y + (y_end - y) * i / max(1, segs)
        yj = y if y_end is None else y + (y_end - y) * (i + 1) / max(1, segs)
        seg = (pts[j] - pts[i]).length
        p0, p1 = pts[i] + off[i], pts[j] + off[j]
        p2, p3 = pts[j] - off[j], pts[i] - off[i]
        uv = [(dist_ / tile, 0.0), ((dist_ + seg) / tile, 0.0), ((dist_ + seg) / tile, width / tile), (dist_ / tile, width / tile)]
        out.append(poly(key, [(p0.x, p0.y, yi), (p1.x, p1.y, yj), (p2.x, p2.y, yj), (p3.x, p3.y, yi)], col, None, tile, uv))
        dist_ += seg
    return out


def resample_path(path, step):
    """Polylinie in gleichmäßigen Abständen abtasten (Liste von Vector)."""
    pts = [Vector(p) for p in path]
    out = [pts[0]]
    carry = 0.0
    for a, b in zip(pts, pts[1:]):
        seg = (b - a).length
        t = step - carry if carry > 0 else step
        while t <= seg:
            out.append(a.lerp(b, t / seg))
            t += step
        carry = seg - (t - step)
    return out


def dist_polyline(P, path):
    """Abstand vieler Punkte (n x 2) zu einer Polylinie (Liste (x, z))."""
    a = np.array(path[:-1], float)
    b = np.array(path[1:], float)
    d = b - a
    ll = np.maximum((d ** 2).sum(1), 1e-9)
    q = P[:, None, :]
    t = np.clip(((q - a) * d).sum(2) / ll, 0, 1)
    proj = a + t[..., None] * d
    return np.sqrt(((q - proj) ** 2).sum(2)).min(1)


def seg_dist_pt(p, a, b):
    """Abstand des Punktes p zur Strecke a-b (Vector 2D)."""
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.dot(ab), 1e-9)))
    return (p - (a + ab * t)).length


def rotv(v, ang):
    c, s = math.cos(ang), math.sin(ang)
    return Vector((v.x * c - v.y * s, v.x * s + v.y * c))


def frame_at(x, z, yaw_deg):
    """Bezugssystem an (x, z): u zeigt in Richtung yaw (Grad, Spielwinkel von +x zu +z), v steht rechts davon (+z-Seite für yaw 0)."""
    a = math.radians(yaw_deg)
    return Frame((x, z), (math.cos(a), math.sin(a)), (-math.sin(a), math.cos(a)))


def add_ao_parts(parts):
    """Zusätzliche AO-Stellvertreter (nur beim Backen; werden vor dem Export gelöscht)."""
    if parts:
        ao_proxy_objs.append(mesh_object("AOProxy_x%d" % len(ao_proxy_objs), parts))
