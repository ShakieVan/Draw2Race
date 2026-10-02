"""Bauwerke und Fahrzeuge des Küstenstadions „Azure Coast Speedway“ (Thema coast): Segeldach, Boxengebäude, Team-Transporter,
Rennwagen, Reifenstapel, Videowand, Flaggen, Streckenposten, Rettungsturm. Reine Geometrie ohne Blender (siehe make_coast_parts.py)."""
import math

from make_coast_parts import *   # noqa: F401,F403  (Farben, add, vquad, hquad, box, boxd, cyl, strut, wheel ...)
from make_coast_parts import (add, vquad, hquad, sloped, box, boxd, cyl, strut, wheel, shade, lin, rgb_mix,
                              AZURE, AZURE_D, NAVY, WHITE, OFFWHITE, CONCRETE, CONCRETE_D, SAND, CORAL, TEAL, STEEL, STEEL_D, DARK, BLACK, GLASS,
                              ASPHALT, TIRE, RIM, YELLOW, RED, GRAY_L, GRAY_M)

SCREEN_V = (0.085, 0.085, 0.085)   # Vertexfarbe der Bildfläche: Albedo = Textur x diese Farbe (am Tag dunkles, schwach lesbares Bild), und das Laternenlicht des Spiels
                                   # (Zusatzdurchgang, gewichtet mit der Vertexfarbe) überstrahlt das Leuchtbild nachts nicht
LAMP = (0.9, 0.86, 0.72)         # Farbe der Leuchtflächen („k:lampe“: nachts leuchtend)
LAMP_OFF = (0.78, 0.78, 0.74)


# ---------------------------------------------------------------- Segeldach der Haupttribüne
def sail_roof(x_a, x_b, z_rear, z_front, y_rear, y_front, y_base=0.0, bay=7.0, sag=0.8, bulge=1.1, stay=9.5):
    """Auskragendes weißes Segeldach (entlang x) über der Haupttribüne: Rückkante bei z_rear (hoch), Vorderkante zur Strecke hin tiefer und
    zwischen den Masten ausgebuchtet (Segel). Dazu Masten, Abspannungen und Lichtleisten (leuchten nachts)."""
    parts = []
    nx = int(round((x_b - x_a) / 1.0))
    rows = 6

    def surf(i, t):
        x = x_a + (x_b - x_a) * i / nx
        u = ((x - x_a) / bay) % 1.0
        sc = math.sin(math.pi * u)
        zf = z_front - bulge * sc
        yf = y_front - sag * sc
        z = z_rear + (zf - z_rear) * t
        y = y_rear + (yf - y_rear) * t - 0.22 * sc * math.sin(math.pi * t)
        return x, z, y_base + y, yf

    for i in range(nx):
        for j in range(rows):
            t0, t1 = j / rows, (j + 1) / rows
            c = [surf(i, t0), surf(i + 1, t0), surf(i + 1, t1), surf(i, t1)]
            top = [(p[0], p[1], p[2]) for p in c]
            th0, th1 = 0.26 * (1 - t0) + 0.07, 0.26 * (1 - t1) + 0.07
            col_t = shade(WHITE, 0.96 + 0.05 * (j % 2))
            add(parts, "k:farbe", top[::-1] if False else top, None, None, [col_t] * 4)
            bot = [(top[0][0], top[0][1], top[0][2] - th0), (top[1][0], top[1][1], top[1][2] - th0), (top[2][0], top[2][1], top[2][2] - th1),
                   (top[3][0], top[3][1], top[3][2] - th1)]
            add(parts, "k:farbe", bot, None, "down", [shade(OFFWHITE, 0.8)] * 4)
        # Vorderkante: blaues Band; Rückkante: weißes Band
        xa, za, ya, _ = surf(i, 1.0)
        xb, zb, yb, _ = surf(i + 1, 1.0)
        add(parts, "k:farbe", [(xa, za, ya - 0.26), (xb, zb, yb - 0.26), (xb, zb, yb + 0.03), (xa, za, ya + 0.03)], None, (0.0, -1.0), [AZURE] * 4)
        xa, za, ya, _ = surf(i, 0.0)
        xb, zb, yb, _ = surf(i + 1, 0.0)
        add(parts, "k:farbe", [(xa, za, ya - 0.33), (xb, zb, yb - 0.33), (xb, zb, yb + 0.02), (xa, za, ya + 0.02)], None, (0.0, 1.0), [OFFWHITE] * 4)
        # Lichtleiste unter der Vorderkante (nachts leuchtend)
        xa, za, ya, _ = surf(i, 0.88)
        xb, zb, yb, _ = surf(i + 1, 0.88)
        thk = 0.26 * 0.12 + 0.07
        add(parts, "k:lampe", [(xa, za, ya - thk - 0.02), (xb, zb, yb - thk - 0.02), (xb, zb + 0.14, yb - thk - 0.02), (xa, za + 0.14, ya - thk - 0.02)], None, "down",
            [LAMP] * 4)
    # Stirnseiten
    for (i, sgn) in ((0, -1), (nx, 1)):
        for j in range(rows):
            p0, p1 = surf(i, j / rows), surf(i, (j + 1) / rows)
            th0, th1 = 0.26 * (1 - j / rows) + 0.07, 0.26 * (1 - (j + 1) / rows) + 0.07
            add(parts, "k:farbe", [(p0[0], p0[1], p0[2] - th0), (p1[0], p1[1], p1[2] - th1), (p1[0], p1[1], p1[2]), (p0[0], p0[1], p0[2])], None, (sgn, 0.0), [OFFWHITE] * 4)
    # Masten, Abspannung
    z_m = z_rear + 1.3
    n_m = int(round((x_b - x_a) / bay))
    for k in range(n_m + 1):
        x = x_a + k * bay
        top = y_base + y_rear + 3.2
        cyl(parts, x, z_m, 0.3, y_base, top, STEEL, sides=8, r_top=0.14, ao=0.8)
        cyl(parts, x, z_m, 0.46, y_base, y_base + 0.5, CONCRETE_D, sides=8, ao=0.8)
        strut(parts, (x, z_m, top - 0.1), (x, z_m + stay, y_base + 0.05), 0.1, STEEL_D)
        _, zf, yf, _ = surf(min(nx, int(round(k * bay))), 1.0)
        strut(parts, (x, z_m, top - 0.1), (x, zf, yf + 0.05), 0.1, STEEL_D)
        _, zm, ym, _ = surf(min(nx, int(round(k * bay))), 0.5)
        strut(parts, (x, z_m, top - 0.1), (x, zm, ym + 0.05), 0.08, STEEL_D)
        cyl(parts, x, z_m, 0.12, top, top + 0.7, STEEL_D, sides=6, r_top=0.03)
    return parts


# ---------------------------------------------------------------- Boxengebäude
def pit_building(ox, oz, bays=6, y_base=0.0, bay_w=3.0, pier=0.7, depth=4.4, hgt=3.6, glass_bay=5):
    """Boxengebäude (flach, weiß, Garagen zur Strecke, azurblaue Blende, Lichtdach, Rennleitung auf dem Dach). (ox, oz) = Mitte der Vorderseite,
    die Garagen schauen nach +z. Rückgabe: Teile; die Breite ist bays * (bay_w + pier) + pier."""
    parts = []
    pitch = bay_w + pier
    width = bays * pitch + pier
    x0, x1 = -width / 2, width / 2
    yb = y_base

    def B(a0, a1, b0, b1, y0, y1, col, key="k:farbe", **kw):
        boxd(parts, ox + a0, ox + a1, oz + b0, oz + b1, yb + y0, yb + y1, col, key, **kw)
    B(x0 - 0.3, x1 + 0.3, -depth - 0.3, 0.35, 0.0, 0.16, CONCRETE_D, ao=1.0)                      # Sockel
    B(x0, x1, -depth, -2.5, 0.16, hgt, OFFWHITE)                                                    # Rückteil
    B(x0, x1, -2.5, 0.0, hgt - 0.85, hgt, OFFWHITE)                                                 # Sturz über den Toren
    for k in range(bays + 1):                                                                       # Pfeiler zwischen den Toren
        a = x0 + k * pitch
        B(a, a + pier, -2.5, 0.0, 0.16, hgt - 0.85, WHITE)
    # Innenräume der Garagen: dunkel, mit Deckenleuchte (nachts warm); Rolltor teilweise geöffnet
    door_open = [2.75, 1.7, 2.75, 1.05, 2.75, 2.2, 2.75]
    for k in range(bays):
        a0 = x0 + k * pitch + pier
        a1 = a0 + bay_w
        if k == glass_bay:
            # Aufenthaltsraum: Glasfront (leuchtet nachts), weiße Sprossen
            add(parts, "k:lampe", [(ox + a0, oz - 0.9, yb + 0.3), (ox + a1, oz - 0.9, yb + 0.3), (ox + a1, oz - 0.9, yb + 2.75), (ox + a0, oz - 0.9, yb + 2.75)],
                None, (0.0, 1.0), [(0.05, 0.1, 0.13)] * 4)
            for m in range(1, 4):
                aa = a0 + m * bay_w / 4
                B(aa - 0.04, aa + 0.04, -0.95, -0.85, 0.3, 2.75, WHITE)
            B(a0, a1, -0.95, -0.85, 0.3, 0.34, WHITE)
            B(a0, a1, -0.95, -0.85, 2.7, 2.75, WHITE)
            continue
        hquad(parts, [(ox + a0, oz - 2.5), (ox + a1, oz - 2.5), (ox + a1, oz), (ox + a0, oz)], yb + 0.17, shade(ASPHALT, 0.7))
        add(parts, "k:farbe", [(ox + a0, oz - 2.488, yb + 0.17), (ox + a1, oz - 2.488, yb + 0.17), (ox + a1, oz - 2.488, yb + 2.75), (ox + a0, oz - 2.488, yb + 2.75)],
            None, (0.0, 1.0), [shade(DARK, 1.4)] * 2 + [DARK] * 2)
        for sa, sx in ((a0, a0 + 0.012), (a1, a1 - 0.012)):
            add(parts, "k:farbe", [(ox + sx, oz - 2.5, yb + 0.17), (ox + sx, oz, yb + 0.17), (ox + sx, oz, yb + 2.75), (ox + sx, oz - 2.5, yb + 2.75)],
                None, (1.0 if sa == a0 else -1.0, 0.0), [shade(DARK, 1.2)] * 4)
        add(parts, "k:lampe", [(ox + a0 + 0.4, oz - 1.5, yb + 2.74), (ox + a1 - 0.4, oz - 1.5, yb + 2.74), (ox + a1 - 0.4, oz - 1.2, yb + 2.74),
                               (ox + a0 + 0.4, oz - 1.2, yb + 2.74)], None, "down", [LAMP] * 4)
        h_open = door_open[k % len(door_open)]
        if h_open < 2.7:                                                                            # herabgelassenes Rolltor (Rippen)
            B(a0 + 0.03, a1 - 0.03, -0.12, -0.04, h_open, 2.75, shade(GRAY_L, 1.0))
            n_rib = int((2.75 - h_open) / 0.18)
            for r in range(1, n_rib):
                B(a0 + 0.03, a1 - 0.03, -0.125, -0.115, h_open + r * 0.18, h_open + r * 0.18 + 0.025, shade(GRAY_M, 0.8))
            B(a0 + 0.03, a1 - 0.03, -0.14, -0.1, h_open - 0.05, h_open, STEEL_D)
        # Torziffer
        B(a0 + bay_w * 0.5 - 0.35, a0 + bay_w * 0.5 + 0.35, 0.02, 0.1, hgt - 0.78, hgt - 0.3, AZURE_D)
    # Blende (Azur) mit Schriftfeld, Dachrand, Flachdach
    B(x0 - 0.1, x1 + 0.1, 0.0, 0.14, hgt - 0.7, hgt - 0.1, AZURE, ao=1.0)
    for (a0, a1, b0, b1) in ((x0 - 0.15, x1 + 0.15, 0.0, 0.2), (x0 - 0.15, x1 + 0.15, -depth - 0.15, -depth + 0.1), (x0 - 0.15, x0 + 0.1, -depth, 0.0), (x1 - 0.1, x1 + 0.15, -depth, 0.0)):
        B(a0, a1, b0, b1, hgt, hgt + 0.3, OFFWHITE)                                                  # Attika (Ring)
    hquad(parts, [(ox + x0, oz - depth), (ox + x1, oz - depth), (ox + x1, oz), (ox + x0, oz)][::-1], yb + hgt + 0.02, lin("#7d8184"))
    # Lichtdach über der Boxengasse (flach, leicht, Stützen, Leuchtleiste)
    cw = 1.5
    for sgn, col in ((1, WHITE),):
        hquad(parts, [(ox + x0 - 0.5, oz + 0.14), (ox + x1 + 0.5, oz + 0.14), (ox + x1 + 0.5, oz + cw), (ox + x0 - 0.5, oz + cw)][::-1], yb + hgt - 0.16, col)
        hquad(parts, [(ox + x0 - 0.5, oz + 0.14), (ox + x1 + 0.5, oz + 0.14), (ox + x1 + 0.5, oz + cw), (ox + x0 - 0.5, oz + cw)], yb + hgt - 0.28, shade(OFFWHITE, 0.85), up=False)
        vquad(parts, (ox + x0 - 0.5, oz + cw), (ox + x1 + 0.5, oz + cw), yb + hgt - 0.28, yb + hgt - 0.14, (0.0, 1.0), AZURE, 1.0)
        for k in range(bays + 1):
            a = x0 + k * pitch + pier / 2
            cyl(parts, ox + a, oz + cw - 0.15, 0.06, yb, yb + hgt - 0.28, STEEL, sides=6, cap=False)
        for k in range(bays):
            a = x0 + k * pitch + pier + bay_w / 2
            add(parts, "k:lampe", [(ox + a - 1.0, oz + 1.0, yb + hgt - 0.29), (ox + a + 1.0, oz + 1.0, yb + hgt - 0.29), (ox + a + 1.0, oz + 1.2, yb + hgt - 0.29),
                                   (ox + a - 1.0, oz + 1.2, yb + hgt - 0.29)], None, "down", [LAMP] * 4)
    # Rennleitung auf dem Dach (Glasband leuchtet nachts), Dachaufbauten; die Dachhaut liegt bei hgt + 0,02
    rc0, rc1, rb0, rb1 = -2.9, 2.9, -4.0, -1.4
    r0 = hgt + 0.02
    B(rc0, rc1, rb0, rb1, r0, r0 + 2.5, WHITE)
    add(parts, "k:lampe", [(ox + rc0 + 0.25, oz + rb1 + 0.012, yb + r0 + 0.8), (ox + rc1 - 0.25, oz + rb1 + 0.012, yb + r0 + 0.8),
                           (ox + rc1 - 0.25, oz + rb1 + 0.012, yb + r0 + 2.15), (ox + rc0 + 0.25, oz + rb1 + 0.012, yb + r0 + 2.15)], None, (0.0, 1.0),
        [(0.05, 0.1, 0.14)] * 4)
    for m in range(1, 5):
        aa = rc0 + 0.25 + m * (rc1 - rc0 - 0.5) / 5
        B(aa - 0.035, aa + 0.035, rb1 + 0.0, rb1 + 0.05, r0 + 0.8, r0 + 2.15, WHITE)
    B(rc0 - 0.5, rc1 + 0.5, rb0 - 0.4, rb1 + 0.9, r0 + 2.5, r0 + 2.7, AZURE)
    B(rc0 - 0.5, rc1 + 0.5, rb0 - 0.4, rb1 + 0.9, r0 + 2.7, r0 + 2.75, WHITE, ao=1.0)
    for sa in (-1, 1):
        add(parts, "k:lampe", [(ox + sa * 2.912, oz - 2.6, yb + r0 + 1.0), (ox + sa * 2.912, oz - 1.4, yb + r0 + 1.0), (ox + sa * 2.912, oz - 1.4, yb + r0 + 2.0),
                               (ox + sa * 2.912, oz - 2.6, yb + r0 + 2.0)], None, (sa, 0.0), [(0.05, 0.1, 0.14)] * 4)
    cyl(parts, ox + 2.2, oz - 3.2, 0.04, yb + r0 + 2.75, yb + r0 + 5.7, STEEL, sides=5, cap=False)
    cyl(parts, ox - 2.2, oz - 3.4, 0.03, yb + r0 + 2.75, yb + r0 + 4.7, STEEL, sides=5, cap=False)
    for (a, b) in ((-8.5, -3.0), (-6.0, -3.0), (7.5, -3.2)):
        B(a - 0.9, a + 0.9, b - 0.7, b + 0.7, r0, r0 + 0.7, GRAY_L)
        cyl(parts, ox + a - 0.4, oz + b, 0.28, yb + r0 + 0.7, yb + r0 + 0.74, DARK, sides=8)
        cyl(parts, ox + a + 0.4, oz + b, 0.28, yb + r0 + 0.7, yb + r0 + 0.74, DARK, sides=8)
    return parts, width


# ---------------------------------------------------------------- Team-Transporter
def transporter(cx, cz, ux, uz, livery, y_base=0.0, cab=WHITE, length=11.4):
    """Sattelzug eines Rennstalls: Zugmaschine (Frontlenker) mit Auflieger; vorne in Richtung u. livery = Materialschlüssel der Seitenfläche."""
    n = math.hypot(ux, uz)
    ux, uz = ux / n, uz / n
    vx, vz = -uz, ux
    parts = []
    yb = y_base

    def L(a0, a1, b0, b1, y0, y1, col, key="k:farbe", **kw):
        ac, bc = (a0 + a1) / 2, (b0 + b1) / 2
        box(parts, cx + ux * ac + vx * bc, cz + uz * ac + vz * bc, ux, uz, a1 - a0, b1 - b0, yb + y0, yb + y1, col, key, **kw)

    def Pt(a, b):
        return (cx + ux * a + vx * b, cz + uz * a + vz * b)
    h = length / 2
    t0, t1 = -h, h - 3.0                       # Auflieger von hinten bis kurz vor der Zugmaschine
    wd = 1.28
    L(t0 + 0.2, h - 0.5, -0.55, 0.55, 0.45, 0.92, DARK, ao=1.0)                                     # Rahmen
    # Auflieger: Seiten mit Beschriftung, Dach weiß, Heck mit Türen
    y_a, y_b = 0.92, 3.7
    for sgn in (1, -1):
        p0, p1 = Pt(t0, sgn * wd), Pt(t1, sgn * wd)
        if sgn > 0:
            uvs = [(0, 0), (1, 0), (1, 1), (0, 1)]
        else:
            uvs = [(1, 0), (0, 0), (0, 1), (1, 1)]
        add(parts, livery, [(p0[0], p0[1], yb + y_a), (p1[0], p1[1], yb + y_a), (p1[0], p1[1], yb + y_b), (p0[0], p0[1], yb + y_b)], uvs, (vx * sgn, vz * sgn), None)
    for sgn in (1, -1):                                       # Randprofile
        L(t0, t1, sgn * (wd - 0.02), sgn * (wd + 0.02), y_a - 0.06, y_a + 0.08, STEEL_D, ao=1.0)
    hquad(parts, [Pt(t0, -wd), Pt(t1, -wd), Pt(t1, wd), Pt(t0, wd)][::-1], yb + y_b, WHITE)
    stripe_a, stripe_b = {"lkw_azure": (AZURE, TEAL), "lkw_coral": (CORAL, OFFWHITE), "lkw_navy": (NAVY, AZURE)}.get(livery, (AZURE, TEAL))
    for (b0_, b1_, col_) in ((-0.5, 0.5, stripe_a), (-0.78, -0.62, stripe_b), (0.62, 0.78, stripe_b)):          # Dachstreifen in den Teamfarben
        hquad(parts, [Pt(t0 + 0.35, b0_), Pt(t1 - 0.35, b0_), Pt(t1 - 0.35, b1_), Pt(t0 + 0.35, b1_)][::-1], yb + y_b + 0.01, col_)
    hquad(parts, [Pt(t0, -wd), Pt(t1, -wd), Pt(t1, wd), Pt(t0, wd)], yb + y_a, DARK, up=False)
    for sgn in (-1, 1):
        L(t0, t1, sgn * wd - 0.0, sgn * wd + (0.01 if sgn > 0 else -0.01), y_b - 0.01, y_b + 0.03, STEEL, ao=1.0, top=1.0)
    # Stirnseite (zur Zugmaschine) und Heck
    p0, p1 = Pt(t1, -wd), Pt(t1, wd)
    vquad(parts, p0, p1, yb + y_a, yb + y_b, (ux, uz), OFFWHITE, 0.8)
    p0, p1 = Pt(t0, wd), Pt(t0, -wd)
    vquad(parts, p0, p1, yb + y_a, yb + y_b, (-ux, -uz), OFFWHITE, 0.85)
    for sgn in (-1, 1):                                                                              # Hecktüren: Mittelfuge, Griffe, Rückleuchten
        p0, p1 = Pt(t0 - 0.01, sgn * 0.03), Pt(t0 - 0.01, sgn * 0.04)
        L(t0 - 0.03, t0, sgn * 0.02 - 0.02, sgn * 0.02 + 0.02, y_a + 0.1, y_b - 0.1, STEEL_D, ao=1.0)
        L(t0 - 0.04, t0, sgn * (wd - 0.18) - 0.07, sgn * (wd - 0.18) + 0.07, y_a + 0.12, y_a + 0.5, RED, ao=1.0)
    L(t0 - 0.05, t0, -wd, wd, y_a - 0.1, y_a + 0.04, STEEL_D, ao=1.0)
    # Zugmaschine (Frontlenker)
    c0, c1 = h - 2.75, h
    L(c0, c1, -1.22, 1.22, 0.5, 1.5, cab, ao=0.75)                                                  # unterer Teil mit Kühlergrill
    L(c0 + 0.2, c1 - 0.15, -1.2, 1.2, 1.5, 3.05, cab, ao=0.9)                                       # Fahrerhaus
    L(c1 - 0.03, c1 + 0.04, -0.9, 0.9, 0.62, 1.2, STEEL_D, ao=1.0)                                  # Grill
    L(c1 - 0.03, c1 + 0.12, -1.24, 1.24, 0.42, 0.62, DARK, ao=1.0)                                  # Stoßfänger
    for sgn in (-1, 1):
        L(c1 - 0.02, c1 + 0.06, sgn * 1.0 - 0.17, sgn * 1.0 + 0.17, 0.82, 1.02, shade(YELLOW, 0.9), ao=1.0)   # Scheinwerfer (aus)
    # Windschutzscheibe (geneigt) und Seitenfenster
    wa, wb = c1 - 0.15, c1 - 0.55
    add(parts, "k:farbe", [(*Pt(wa, -1.1), yb + 1.55), (*Pt(wa, 1.1), yb + 1.55), (*Pt(wb, 1.1), yb + 2.85), (*Pt(wb, -1.1), yb + 2.85)], None, (ux, uz), [GLASS] * 4)
    for sgn in (1, -1):
        p0, p1 = Pt(c1 - 0.6, sgn * 1.215), Pt(c1 - 1.5, sgn * 1.215)
        vquad(parts, p0, p1, yb + 1.85, yb + 2.8, (vx * sgn, vz * sgn), GLASS, 1.0)
        L(c1 - 0.5, c1 - 0.62, sgn * 1.28 - 0.02, sgn * 1.28 + 0.02, 1.6, 2.1, STEEL_D, ao=1.0)      # Spiegel
    L(c0 + 0.3, c1 - 0.7, -1.18, 1.18, 3.05, 3.55, cab, ao=0.85)                                    # Spoiler
    L(c0 + 0.3, c1 - 0.7, -1.19, 1.19, 3.55, 3.62, AZURE, ao=1.0)
    # Räder: vorn eine Achse, Antrieb Zwilling, Auflieger Tandem (Zwillingsreifen)
    for a in (h - 0.85, h - 4.6):
        pass
    axes = [(h - 0.95, False), (h - 3.45, True), (t0 + 2.1, True), (t0 + 3.4, True)]
    for a, twin in axes:
        for sgn in (1, -1):
            lat = sgn * (1.08 if not twin else 1.02)
            wheel(parts, cx, cz, ux, uz, a, lat, 0.5, 0.3, yb + 0.5, sides=10)
            if twin:
                wheel(parts, cx, cz, ux, uz, a, sgn * 1.42, 0.5, 0.3, yb + 0.5, sides=10)
    for a in (t0 + 2.1, t0 + 3.4):
        for sgn in (1, -1):
            L(a - 0.62, a + 0.62, sgn * 1.15 - 0.03, sgn * 1.15 + 0.03, 0.55, 1.0, DARK, ao=1.0)        # Kotflügel
    for sgn in (1, -1):
        L(h - 3.45 - 0.62, h - 3.45 + 0.62, sgn * 1.2 - 0.03, sgn * 1.2 + 0.03, 0.75, 1.1, cab, ao=0.9)
    return parts


# ---------------------------------------------------------------- Rennwagen (GT-Prototyp)
def race_car(cx, cz, ux, uz, color, accent, y_base=0.0, number_col=WHITE):
    """Niedriger Rennwagen (Karosserie als Längsschnitte, geschlossenes Cockpit, Heckflügel, Frontsplitter, vier Räder mit Slicks)."""
    n = math.hypot(ux, uz)
    ux, uz = ux / n, uz / n
    vx, vz = -uz, ux
    parts = []
    yb = y_base

    def Pt(a, b, y):
        return (cx + ux * a + vx * b, cz + uz * a + vz * b, yb + y)
    # Längsschnitte: (a, halbe Breite, Unterkante, Oberkante)
    sec = [(-2.1, 0.52, 0.30, 0.62), (-1.4, 0.70, 0.20, 0.68), (-0.3, 0.74, 0.17, 0.56), (0.7, 0.72, 0.16, 0.50), (1.5, 0.60, 0.16, 0.40), (2.15, 0.40, 0.17, 0.30)]
    for s0, s1 in zip(sec, sec[1:]):
        a0, w0, lo0, hi0 = s0
        a1, w1, lo1, hi1 = s1
        # Oberseite dreigeteilt (Mittelstreifen in der Akzentfarbe)
        for (b0f, b1f, col) in ((-1.0, -0.22, color), (-0.22, 0.22, accent), (0.22, 1.0, color)):
            add(parts, "k:farbe", [Pt(a0, b0f * w0, hi0), Pt(a1, b0f * w1, hi1), Pt(a1, b1f * w1, hi1), Pt(a0, b1f * w0, hi0)][::-1], None, None, [col] * 4)
        for sgn in (-1, 1):                                                                         # Flanken
            add(parts, "k:farbe", [Pt(a0, sgn * w0, lo0), Pt(a1, sgn * w1, lo1), Pt(a1, sgn * w1, hi1), Pt(a0, sgn * w0, hi0)], None, (vx * sgn, vz * sgn),
                [shade(color, 0.78), shade(color, 0.78), color, color])
        add(parts, "k:farbe", [Pt(a0, -w0, lo0), Pt(a1, -w1, lo1), Pt(a1, w1, lo1), Pt(a0, w0, lo0)], None, "down", [DARK] * 4)
    a0, w0, lo0, hi0 = sec[0]
    add(parts, "k:farbe", [Pt(a0, w0, lo0), Pt(a0, -w0, lo0), Pt(a0, -w0, hi0), Pt(a0, w0, hi0)], None, (-ux, -uz), [shade(color, 0.7)] * 4)
    a1, w1, lo1, hi1 = sec[-1]
    add(parts, "k:farbe", [Pt(a1, -w1, lo1), Pt(a1, w1, lo1), Pt(a1, w1, hi1), Pt(a1, -w1, hi1)], None, (ux, uz), [color] * 4)
    # Cockpit: Glaskanzel mit Dach in Wagenfarbe
    cp = [(-1.15, 0.36, 0.64), (-0.65, 0.42, 0.98), (0.05, 0.40, 1.02), (0.6, 0.34, 0.74), (0.95, 0.30, 0.56)]
    for s0, s1 in zip(cp, cp[1:]):
        a0, w0, y0 = s0
        a1, w1, y1 = s1
        add(parts, "k:farbe", [Pt(a0, -w0, y0), Pt(a1, -w1, y1), Pt(a1, w1, y1), Pt(a0, w0, y0)][::-1], None, None, [shade(GLASS, 1.6)] * 4)
        for sgn in (-1, 1):
            add(parts, "k:farbe", [Pt(a0, sgn * w0, 0.58), Pt(a1, sgn * w1, 0.54), Pt(a1, sgn * w1, y1), Pt(a0, sgn * w0, y0)], None, (vx * sgn, vz * sgn), [GLASS] * 4)
    add(parts, "k:farbe", [Pt(-0.6, -0.30, 1.005), Pt(0.0, -0.31, 1.03), Pt(0.0, 0.31, 1.03), Pt(-0.6, 0.30, 1.005)][::-1], None, None, [color] * 4)     # Dach
    # Startnummer (weiße Scheibe) auf der Haube, Lufteinlass hinter dem Cockpit
    ring = [Pt(1.05 + 0.2 * math.cos(2 * math.pi * k / 10), 0.0 + 0.2 * math.sin(2 * math.pi * k / 10), 0.46) for k in range(10)]
    add(parts, "k:farbe", ring[::-1], None, None, [number_col] * 10)
    boxd_local = lambda a0, a1, b0, b1, y0, y1, col: box(parts, cx + ux * (a0 + a1) / 2 + vx * (b0 + b1) / 2, cz + uz * (a0 + a1) / 2 + vz * (b0 + b1) / 2, ux, uz,
                                                         a1 - a0, b1 - b0, yb + y0, yb + y1, col, ao=0.9)
    boxd_local(-1.0, -0.55, -0.16, 0.16, 0.9, 1.1, DARK)
    # Heckflügel auf zwei Stützen mit Endplatten, Frontsplitter
    boxd_local(-2.35, -1.95, -0.86, 0.86, 1.02, 1.07, accent)
    for sgn in (-1, 1):
        boxd_local(-2.4, -1.9, sgn * 0.86 - 0.025, sgn * 0.86 + 0.025, 0.62, 1.2, color)
        boxd_local(-2.05, -1.95, sgn * 0.3 - 0.03, sgn * 0.3 + 0.03, 0.58, 1.02, DARK)
    boxd_local(2.0, 2.35, -0.78, 0.78, 0.10, 0.15, DARK)
    # Räder
    for a, lat, rad in ((1.35, 0.78, 0.34), (-1.45, 0.80, 0.37)):
        for sgn in (-1, 1):
            wheel(parts, cx, cz, ux, uz, a, sgn * lat, rad, 0.3, yb + rad, sides=10, hub=0.55)
    return parts


# ---------------------------------------------------------------- Reifenstapel
def tyre_stack(cx, cz, n=3, y_base=0.0, r=0.40, h=0.27, tones=None):
    """Stapel von n Reifen (Fassform, Loch), oberster mit Öffnung; Farben: schwarz, der mittlere weiß gestrichen."""
    parts = []
    tones = tones or [BLACK, lin("#d9dcde"), BLACK]
    sides = 10
    for t in range(n):
        y0 = y_base + t * h
        col = tones[t % len(tones)]
        for k in range(sides):
            a0, a1 = 2 * math.pi * k / sides, 2 * math.pi * (k + 1) / sides
            for (ya, yb, ra, rb) in ((y0, y0 + h * 0.5, r * 0.9, r), (y0 + h * 0.5, y0 + h, r, r * 0.9)):
                p0 = (cx + ra * math.cos(a0), cz + ra * math.sin(a0), ya)
                p1 = (cx + ra * math.cos(a1), cz + ra * math.sin(a1), ya)
                q1 = (cx + rb * math.cos(a1), cz + rb * math.sin(a1), yb)
                q0 = (cx + rb * math.cos(a0), cz + rb * math.sin(a0), yb)
                tone = 0.92 + 0.1 * math.cos((a0 + a1) / 2)
                add(parts, "k:farbe", [p0, p1, q1, q0], None, (math.cos((a0 + a1) / 2), math.sin((a0 + a1) / 2)),
                    [shade(col, tone * 0.85)] * 2 + [shade(col, tone)] * 2)
    # Oberseite: Ring mit Loch
    y_top = y_base + n * h
    for k in range(sides):
        a0, a1 = 2 * math.pi * k / sides, 2 * math.pi * (k + 1) / sides
        ro, ri = r * 0.9, r * 0.45
        pts = [(cx + ro * math.cos(a0), cz + ro * math.sin(a0), y_top), (cx + ro * math.cos(a1), cz + ro * math.sin(a1), y_top),
               (cx + ri * math.cos(a1), cz + ri * math.sin(a1), y_top), (cx + ri * math.cos(a0), cz + ri * math.sin(a0), y_top)]
        add(parts, "k:farbe", pts[::-1], None, None, [shade(tones[(n - 1) % len(tones)], 1.1)] * 4)
    return parts


# ---------------------------------------------------------------- Videowand
SCREEN_KEY = "k:../dio/coast/screen"      # K_-Oberfläche des Spiels; der Schlüssel zeigt auf die Themen-Textur screen.png / screen_e.png (Leuchtbild)


def video_screen(cx, cz, fx, fz, w=8.4, h=4.725, y0=2.0, lean=28.0, y_base=0.0, key=SCREEN_KEY):
    """Große Videowand auf Stahlgerüst, nach hinten geneigt (so ist das Bild auch aus der Rennkamera von schräg oben lesbar). (cx, cz) = Mitte der
    Unterkante, die Bildfläche zeigt in Richtung f = (fx, fz). Das Bild trägt das K_-Material (tagsüber dunkles Bild, nachts Leuchtbild mit
    Fensterlicht des Spiels). Rückgabe: Teile und Tiefe der Gerüstfüße hinter der Unterkante (m)."""
    n = math.hypot(fx, fz)
    fx, fz = fx / n, fz / n
    ux, uz = fz, -fx                      # Bildrechts für einen Betrachter vor der Wand
    lr = math.radians(lean)
    sn, cs = math.sin(lr), math.cos(lr)   # Neigung: Oberkante liegt um h*sn hinter der Unterkante und h*cs höher
    parts = []

    def P(a, b, y):
        return (cx + ux * a + fx * b, cz + uz * a + fz * b, y_base + y)

    def Q(a, t, off=0.0):
        """Punkt auf der Bildebene: a seitlich, t entlang der Bildhöhe (0 = unten), off = Versatz entlang der Flächennormalen (nach vorn)."""
        return P(a, -t * sn + off * cs, y0 + t * cs + off * sn)

    # Bildfläche
    add(parts, key, [Q(-w / 2, 0), Q(w / 2, 0), Q(w / 2, h), Q(-w / 2, h)], [(0, 0), (1, 0), (1, 1), (0, 1)], (fx, fz), [SCREEN_V] * 4)
    # Gehäuse: Platte hinter dem Bild, Rahmen steht m seitlich über, Tiefe th entlang der Normalen
    m, th = 0.16, 0.5
    fr = [(-w / 2 - m, -m), (w / 2 + m, -m), (w / 2 + m, h + m), (-w / 2 - m, h + m)]
    front = [Q(a, t, 0.01) for a, t in fr]
    back = [Q(a, t, -th) for a, t in fr]
    inn = [(-w / 2, 0.0), (w / 2, 0.0), (w / 2, h), (-w / 2, h)]
    for k in range(4):                                                   # Rahmen vorn: vier Streifen zwischen Außen- und Innenkante
        k2 = (k + 1) % 4
        add(parts, "k:farbe", [Q(*fr[k], 0.012), Q(*fr[k2], 0.012), Q(*inn[k2], 0.012), Q(*inn[k], 0.012)], None, (fx, fz), [STEEL_D] * 4)
    add(parts, "k:farbe", [back[1], back[0], back[3], back[2]], None, (-fx, -fz), [DARK] * 4)                       # Rückseite
    add(parts, "k:farbe", [front[1], front[2], back[2], back[1]], None, (ux, uz), [shade(STEEL_D, 0.9)] * 4)         # rechte Seite
    add(parts, "k:farbe", [front[3], front[0], back[0], back[3]], None, (-ux, -uz), [shade(STEEL_D, 0.9)] * 4)       # linke Seite
    add(parts, "k:farbe", [front[2], front[3], back[3], back[2]], None, None, [shade(STEEL_D, 1.1)] * 4)             # Oberseite
    add(parts, "k:farbe", [front[0], front[1], back[1], back[0]], None, "down", [DARK] * 4)                           # Unterseite
    # Gerüst: zwei Stützen hinter der Wand, Betonfüße, Streben zur Wand und zwischen den Stützen
    s_top = h * sn
    foot_b = -s_top - 1.7
    for sgn in (-1, 1):
        a = sgn * w * 0.32
        top_pt = Q(a, h - 0.4, -th)
        base_pt = P(a, foot_b, 0.0)
        cyl(parts, base_pt[0], base_pt[1], 0.3, y_base, y_base + 0.25, CONCRETE_D, sides=8, ao=0.8)
        cyl(parts, base_pt[0], base_pt[1], 0.16, y_base + 0.25, top_pt[2], STEEL, sides=8, r_top=0.12, ao=0.75)
        p0 = P(a, -0.35, 0.0)
        box(parts, p0[0], p0[1], ux, uz, 0.9, 0.8, y_base, y_base + 0.3, CONCRETE_D, ao=0.8)
        strut(parts, (*P(a, foot_b, 0.0)[:2], y_base + 0.35), Q(a, h * 0.75, -th), 0.1, STEEL_D)
        strut(parts, (*p0[:2], y_base + 0.3), Q(a, h * 0.1, -th), 0.1, STEEL_D)
    strut(parts, P(-w * 0.32, foot_b, y0 + 0.9), P(w * 0.32, foot_b, y0 - 0.2), 0.08, STEEL_D)
    strut(parts, P(w * 0.32, foot_b, y0 + 0.9), P(-w * 0.32, foot_b, y0 - 0.2), 0.08, STEEL_D)
    q = P(0.0, -0.5, 0.0)
    box(parts, q[0], q[1], ux, uz, w + 0.2, 0.7, y_base + y0 - 0.55, y_base + y0 - 0.5, STEEL, ao=1.0)               # Wartungssteg unter der Wand
    return parts, s_top + 1.7


# ---------------------------------------------------------------- Lichtmast mit Auslegerlampe
def light_pole(cx, cz, ux, uz, h=6.0, y_base=0.0, arm=0.9, key_lamp="k:lampe"):
    """Lichtmast: Betonfuß, konischer Stahlmast, Ausleger zur Strecke (u zeigt zur Strecke) und Lampenträger mit vier Leuchtflächen (nachts hell).
    Der Lampenkopf liegt bei (cx + ux * arm, cz + uz * arm) in der Höhe y_base + h."""
    n = math.hypot(ux, uz) or 1.0
    ux, uz = ux / n, uz / n
    vx, vz = -uz, ux
    parts = []
    box(parts, cx, cz, ux, uz, 0.55, 0.55, y_base, y_base + 0.22, CONCRETE_D, ao=0.8)
    cyl(parts, cx, cz, 0.15, y_base + 0.22, y_base + h - 0.3, STEEL, sides=8, r_top=0.085, ao=0.8)
    box(parts, cx + ux * arm * 0.5, cz + uz * arm * 0.5, ux, uz, arm + 0.1, 0.09, y_base + h - 0.36, y_base + h - 0.27, STEEL, ao=1.0)
    hx, hz = cx + ux * arm, cz + uz * arm
    box(parts, hx, hz, ux, uz, 0.5, 1.45, y_base + h - 0.34, y_base + h + 0.04, shade(STEEL, 0.78), ao=0.8, top=1.3)   # Lampengehäuse (hellgrau, von oben kein schwarzes Loch)
    box(parts, hx - ux * 0.02, hz - uz * 0.02, ux, uz, 0.14, 1.5, y_base + h - 0.36, y_base + h - 0.3, DARK, ao=1.0)      # dunkler Rand unter den Leuchtflächen
    for k in range(4):                                                                                    # vier Leuchtflächen an der Vorderkante (zur Strecke)
        b = (k - 1.5) * 0.34
        xs = hx + ux * 0.252
        zs = hz + uz * 0.252
        add(parts, key_lamp, [(xs + vx * (b - 0.14), zs + vz * (b - 0.14), y_base + h - 0.3), (xs + vx * (b + 0.14), zs + vz * (b + 0.14), y_base + h - 0.3),
                              (xs + vx * (b + 0.14), zs + vz * (b + 0.14), y_base + h - 0.02), (xs + vx * (b - 0.14), zs + vz * (b - 0.14), y_base + h - 0.02)],
            None, (ux, uz), [LAMP] * 4)
    return parts


# ---------------------------------------------------------------- Volleyballnetz
def volley_net(cx, cz, ux, uz, length=8.6, y_base=0.0, h_top=2.43, h_bot=1.43):
    """Beachvolleyball-Netz zwischen zwei Pfosten: Raster feiner Streifen (beide Seiten), weißes Band oben, dunkles unten, Antennen an den Enden.
    Das Netz verläuft entlang u durch (cx, cz); die Pfosten stehen 0,15 m hinter den Enden."""
    n = math.hypot(ux, uz) or 1.0
    ux, uz = ux / n, uz / n
    vx, vz = -uz, ux
    parts = []
    half = length / 2

    def P(a, off, y):
        return (cx + ux * a + vx * off, cz + uz * a + vz * off, y_base + y)
    for sgn in (-1, 1):
        px, pz = cx + ux * sgn * (half + 0.15), cz + uz * sgn * (half + 0.15)
        cyl(parts, px, pz, 0.17, y_base, y_base + 0.04, CONCRETE_D, sides=6, ao=1.0)
        cyl(parts, px, pz, 0.055, y_base + 0.04, y_base + h_top + 0.15, STEEL, sides=6)
    gray = shade(GRAY_M, 0.9)
    for side in (-1, 1):                                                 # beide Seiten des Netzes
        face = (vx * side, vz * side)
        off = 0.004 * side
        nh = 8
        for r in range(nh + 1):                                          # waagerechte Maschen
            yy = h_bot + (h_top - h_bot) * r / nh
            add(parts, "k:farbe", [P(-half, off, yy - 0.007), P(half, off, yy - 0.007), P(half, off, yy + 0.007), P(-half, off, yy + 0.007)], None, face, [gray] * 4)
        nv = int(length / 0.3)
        for c in range(nv + 1):                                          # senkrechte Maschen
            a = -half + length * c / nv
            add(parts, "k:farbe", [P(a - 0.007, off, h_bot), P(a + 0.007, off, h_bot), P(a + 0.007, off, h_top), P(a - 0.007, off, h_top)], None, face, [gray] * 4)
        for (y1, y2, col) in ((h_top - 0.09, h_top, WHITE), (h_bot, h_bot + 0.07, DARK)):          # Bänder oben und unten
            add(parts, "k:farbe", [P(-half, off * 2, y1), P(half, off * 2, y1), P(half, off * 2, y2), P(-half, off * 2, y2)], None, face, [col] * 4)
    for sgn in (-1, 1):                                                  # Antennen
        px, pz = cx + ux * sgn * (half - 0.02), cz + uz * sgn * (half - 0.02)
        cyl(parts, px, pz, 0.012, y_base + h_top, y_base + h_top + 0.8, RED, sides=4)
    return parts


# ---------------------------------------------------------------- Flagge, Streckenposten, Rettungsturm
def flag_pole(cx, cz, ux, uz, h, color, y_base=0.0, length=0.9, hgt=0.55, n=4):
    """Fahnenmast mit wehender Fahne (E_flagge, vier Stücke); die Fahne zeigt in Richtung u."""
    parts = []
    cyl(parts, cx, cz, 0.04, y_base, y_base + h, STEEL, sides=5, cap=False)
    for k in range(n):
        a0, a1 = 0.04 + k * length / n, 0.04 + (k + 1) * length / n
        p0 = (cx + ux * a0, cz + uz * a0)
        p1 = (cx + ux * a1, cz + uz * a1)
        add(parts, "e:flagge", [(p0[0], p0[1], y_base + h - hgt - 0.1), (p1[0], p1[1], y_base + h - hgt - 0.1), (p1[0], p1[1], y_base + h - 0.1),
                                (p0[0], p0[1], y_base + h - 0.1)], [(k / n, 0.0), ((k + 1) / n, 0.0), ((k + 1) / n, 1.0), (k / n, 1.0)], None, [color] * 4)
    return parts


def flag_static(cx, cz, ux, uz, h, color, y_base=0.0, length=0.8, hgt=0.5, n=3):
    """Fahnenmast mit ruhender, leicht gewellter Fahne aus K_-Flächen (die wehende E_flagge bekommt nachts kein Laternenlicht und wirkt dann schwarz)."""
    parts = []
    vx, vz = -uz, ux
    cyl(parts, cx, cz, 0.04, y_base, y_base + h, STEEL, sides=5, cap=False)
    for k in range(n):
        a0, a1 = 0.04 + k * length / n, 0.04 + (k + 1) * length / n
        w0, w1 = 0.07 * math.sin(k * 1.9), 0.07 * math.sin((k + 1) * 1.9)
        q = [(cx + ux * a0 + vx * w0, cz + uz * a0 + vz * w0, y_base + h - hgt - 0.1), (cx + ux * a1 + vx * w1, cz + uz * a1 + vz * w1, y_base + h - hgt - 0.1),
             (cx + ux * a1 + vx * w1, cz + uz * a1 + vz * w1, y_base + h - 0.1), (cx + ux * a0 + vx * w0, cz + uz * a0 + vz * w0, y_base + h - 0.1)]
        add(parts, "k:farbe", q, None, (vx, vz), [shade(color, 1.0 - 0.08 * k)] * 4)
        add(parts, "k:farbe", q[::-1], None, (-vx, -vz), [shade(color, 0.85 - 0.08 * k)] * 4)
    return parts


def marshal_post(cx, cz, ux, uz, y_base=0.0):
    """Streckenposten: kleine weiße Hütte mit Satteldach, Fenster zur Strecke (u zeigt zur Strecke), Feuerlöscher und gelber Flagge."""
    n = math.hypot(ux, uz)
    ux, uz = ux / n, uz / n
    vx, vz = -uz, ux
    parts = []
    box(parts, cx, cz, ux, uz, 1.3, 1.8, y_base, y_base + 2.05, WHITE)
    box(parts, cx, cz, ux, uz, 1.38, 1.88, y_base, y_base + 0.12, CONCRETE_D, ao=1.0)

    def Pt(a, b, y):
        return (cx + ux * a + vx * b, cz + uz * a + vz * b, y_base + y)
    ov_, hl_ = 0.95, 1.05                   # Dach: halbe Tiefe und halbe Länge mit Überstand
    add(parts, "k:farbe", [Pt(ov_, -hl_, 2.05), Pt(ov_, hl_, 2.05), Pt(0.0, hl_, 2.6), Pt(0.0, -hl_, 2.6)], None, None, [shade(STEEL, 0.9)] * 4)
    add(parts, "k:farbe", [Pt(-ov_, hl_, 2.05), Pt(-ov_, -hl_, 2.05), Pt(0.0, -hl_, 2.6), Pt(0.0, hl_, 2.6)], None, None, [shade(STEEL, 1.1)] * 4)
    for sgn in (-1, 1):
        add(parts, "k:farbe", [Pt(-ov_, sgn * hl_, 2.05), Pt(ov_, sgn * hl_, 2.05), Pt(0.0, sgn * hl_, 2.6)], None, (vx * sgn, vz * sgn), [shade(STEEL, 0.95)] * 3)
    add(parts, "k:farbe", [Pt(0.655, -0.6, 1.1), Pt(0.655, 0.6, 1.1), Pt(0.655, 0.6, 1.85), Pt(0.655, -0.6, 1.85)], None, (ux, uz), [GLASS] * 4)     # Fenster zur Strecke
    box(parts, cx + ux * 0.66, cz + uz * 0.66, ux, uz, 0.05, 1.3, y_base + 1.05, y_base + 1.1, STEEL, ao=1.0)
    add(parts, "k:farbe", [Pt(-0.2, 0.905, 0.05), Pt(0.4, 0.905, 0.05), Pt(0.4, 0.905, 1.85), Pt(-0.2, 0.905, 1.85)], None, (vx, vz), [shade(AZURE_D, 1.2)] * 4)   # Tür
    cyl(parts, cx + ux * 0.85 - vx * 0.8, cz + uz * 0.85 - vz * 0.8, 0.07, y_base, y_base + 0.45, RED, sides=6)            # Feuerlöscher
    parts += flag_static(cx + ux * 0.9 + vx * 1.15, cz + uz * 0.9 + vz * 1.15, vx, vz, 3.4, YELLOW, y_base, 0.75, 0.5)
    return parts


def lifeguard_tower(cx, cz, ux, uz, y_base=0.0):
    """Rettungsschwimmer-Turm auf Stelzen (weiße Kabine, korallenrotes Dach, Treppe); u zeigt zum Wasser."""
    n = math.hypot(ux, uz)
    ux, uz = ux / n, uz / n
    vx, vz = -uz, ux
    parts = []
    for sa in (-1, 1):
        for sb in (-1, 1):
            cyl(parts, cx + ux * sa * 1.0 + vx * sb * 0.9, cz + uz * sa * 1.0 + vz * sb * 0.9, 0.09, y_base, y_base + 1.7, lin("#caa56a"), sides=6, ao=0.8)
    box(parts, cx, cz, ux, uz, 2.6, 2.4, y_base + 1.7, y_base + 1.82, lin("#b88e55"), ao=1.0)
    box(parts, cx, cz, ux, uz, 1.8, 1.8, y_base + 1.82, y_base + 3.0, WHITE)
    add(parts, "k:farbe", [(cx + ux * 0.905 + vx * 0.7, cz + uz * 0.905 + vz * 0.7, y_base + 2.2), (cx + ux * 0.905 - vx * 0.7, cz + uz * 0.905 - vz * 0.7, y_base + 2.2),
                           (cx + ux * 0.905 - vx * 0.7, cz + uz * 0.905 - vz * 0.7, y_base + 2.8), (cx + ux * 0.905 + vx * 0.7, cz + uz * 0.905 + vz * 0.7, y_base + 2.8)],
        None, (ux, uz), [GLASS] * 4)
    box(parts, cx, cz, ux, uz, 2.6, 2.5, y_base + 3.0, y_base + 3.14, CORAL, ao=1.0)
    parts += flag_pole(cx - ux * 0.9 + vx * 0.9, cz - uz * 0.9 + vz * 0.9, vx, vz, 4.6, RED, y_base, 0.7, 0.45)
    for k in range(4):                                                                                  # Treppe
        box(parts, cx - ux * (1.3 + k * 0.35), cz - uz * (1.3 + k * 0.35), ux, uz, 0.35, 0.8, y_base, y_base + 0.4 + k * 0.32, lin("#b88e55"), ao=0.9)
    return parts


# ---------------------------------------------------------------- Strand und Promenade
def lounger(cx, cz, ux, uz, towel, y_base=0.0):
    """Sonnenliege mit Handtuch; u zeigt zum Fußende."""
    n = math.hypot(ux, uz)
    ux, uz = ux / n, uz / n
    parts = []
    # Liegefläche und Rückenlehne (hochgestellt)
    box(parts, cx, cz, ux, uz, 1.25, 0.62, y_base + 0.27, y_base + 0.33, WHITE, ao=0.9)
    vx, vz = -uz, ux
    bx, bz = cx - ux * 0.95, cz - uz * 0.95
    a0 = (bx - vx * 0.31, bz - vz * 0.31)
    a1 = (bx + vx * 0.31, bz + vz * 0.31)
    t0 = (bx - ux * 0.38 - vx * 0.31, bz - uz * 0.38 - vz * 0.31)
    t1 = (bx - ux * 0.38 + vx * 0.31, bz - uz * 0.38 + vz * 0.31)
    add(parts, "k:farbe", [(a0[0], a0[1], y_base + 0.32), (a1[0], a1[1], y_base + 0.32), (t1[0], t1[1], y_base + 0.62), (t0[0], t0[1], y_base + 0.62)], None, None, [WHITE] * 4)
    box(parts, cx + ux * 0.05, cz + uz * 0.05, ux, uz, 1.0, 0.5, y_base + 0.335, y_base + 0.345, towel, ao=1.0, top=1.0)
    for sa in (-0.55, 0.5):
        for sb in (-0.28, 0.28):
            cyl(parts, cx + ux * sa + vx * sb, cz + uz * sa + vz * sb, 0.025, y_base, y_base + 0.27, STEEL, sides=4, cap=False)
    return parts


def bench(cx, cz, ux, uz, y_base=0.0):
    """Parkbank aus Holzlatten auf Stahlfüßen; Sitzrichtung u (Blick nach vorn)."""
    n = math.hypot(ux, uz)
    ux, uz = ux / n, uz / n
    vx, vz = -uz, ux
    parts = []
    wood = lin("#b08a5a")
    for k in range(4):
        box(parts, cx + ux * (0.18 - k * 0.1), cz + uz * (0.18 - k * 0.1), ux, uz, 0.08, 1.7, y_base + 0.44, y_base + 0.47, wood, ao=1.0)
    for k in range(3):
        bx, bz = cx - ux * 0.27, cz - uz * 0.27
        box(parts, bx, bz, ux, uz, 0.04, 1.7, y_base + 0.62 + k * 0.12, y_base + 0.68 + k * 0.12, wood, ao=1.0)
    for sb in (-0.75, 0.75):
        box(parts, cx + vx * sb, cz + vz * sb, ux, uz, 0.5, 0.05, y_base, y_base + 0.44, STEEL_D, ao=0.9)
    return parts


def tree_pit(cx, cz, y_base=0.0, r=0.8):
    """Baumscheibe: niedrige Betoneinfassung mit dunkler Erde (rund)."""
    parts = []
    cyl(parts, cx, cz, r, y_base, y_base + 0.22, CONCRETE, sides=10, ao=0.85, cap=False)
    pts = [(cx + (r - 0.08) * math.cos(2 * math.pi * k / 10), cz + (r - 0.08) * math.sin(2 * math.pi * k / 10), y_base + 0.17) for k in range(10)]
    add(parts, "k:farbe", pts[::-1], None, None, [lin("#4a3a2a")] * 10)
    pts = [(cx + r * math.cos(2 * math.pi * k / 10), cz + r * math.sin(2 * math.pi * k / 10), y_base + 0.225) for k in range(10)]
    ring = [(cx + (r - 0.08) * math.cos(2 * math.pi * k / 10), cz + (r - 0.08) * math.sin(2 * math.pi * k / 10), y_base + 0.225) for k in range(10)]
    for k in range(10):
        k2 = (k + 1) % 10
        add(parts, "k:farbe", [pts[k], pts[k2], ring[k2], ring[k]][::-1], None, None, [shade(CONCRETE, 1.05)] * 4)
    return parts


# ---------------------------------------------------------------- Personen (Boxencrew, Streckenposten)
def person(cx, cz, ux, uz, shirt, pants=None, y_base=0.0, helmet=None, skin=None):
    """Kleine Figur (gut 1,7 m) aus Quadern und einem Kopf; u = Blickrichtung."""
    n = math.hypot(ux, uz)
    ux, uz = ux / n, uz / n
    vx, vz = -uz, ux
    parts = []
    pants = pants or DARK
    skin = skin or lin("#d9a47c")
    for sb in (-0.1, 0.1):
        box(parts, cx + vx * sb, cz + vz * sb, ux, uz, 0.16, 0.16, y_base, y_base + 0.82, pants, ao=0.85)
    box(parts, cx, cz, ux, uz, 0.26, 0.44, y_base + 0.82, y_base + 1.4, shirt, ao=0.9)
    for sb in (-0.28, 0.28):
        box(parts, cx + vx * sb, cz + vz * sb, ux, uz, 0.12, 0.12, y_base + 0.85, y_base + 1.38, shade(shirt, 0.88), ao=0.9)
    cyl(parts, cx, cz, 0.105, y_base + 1.4, y_base + 1.62, skin, sides=6)
    if helmet is not None:
        cyl(parts, cx, cz, 0.125, y_base + 1.52, y_base + 1.66, helmet, sides=6)
    return parts


def flower_bed(cx, cz, r, y_base=0.0, sides=14):
    """Rundes Blumenbeet mit niedriger Steineinfassung (Material „blumen“, Weltkoordinaten-UV, Kachel 2 m)."""
    parts = []
    ring_o = [(cx + r * math.cos(2 * math.pi * k / sides), cz + r * math.sin(2 * math.pi * k / sides)) for k in range(sides)]
    ring_i = [(cx + (r - 0.14) * math.cos(2 * math.pi * k / sides), cz + (r - 0.14) * math.sin(2 * math.pi * k / sides)) for k in range(sides)]
    cyl(parts, cx, cz, r, y_base, y_base + 0.2, CONCRETE, sides=sides, ao=0.85, cap=False)
    for k in range(sides):
        k2 = (k + 1) % sides
        add(parts, "k:farbe", [(*ring_o[k], y_base + 0.2), (*ring_o[k2], y_base + 0.2), (*ring_i[k2], y_base + 0.2), (*ring_i[k], y_base + 0.2)][::-1], None, None,
            [shade(CONCRETE, 1.1)] * 4)
    pts = [(p[0], p[1], y_base + 0.13) for p in ring_i]
    add(parts, "blumen", pts[::-1], [((p[0]) / 2.0, -(p[1]) / 2.0) for p in ring_i[::-1]], None, None)
    return parts


# ---------------------------------------------------------------- Segelboot (Kulisse im Meer)
def sailboat(cx, cz, ux, uz, hull_col=WHITE, sail_col=OFFWHITE, y_base=0.0, length=6.0):
    """Kleines Segelboot (Rumpf aus Längsschnitten, Mast, Groß- und Vorsegel); u = Bug."""
    n = math.hypot(ux, uz)
    ux, uz = ux / n, uz / n
    vx, vz = -uz, ux
    parts = []

    def Pt(a, b, y):
        return (cx + ux * a + vx * b, cz + uz * a + vz * b, y_base + y)
    L = length
    sec = [(-0.5 * L, 0.55, 0.0, 0.55), (-0.2 * L, 0.95, -0.15, 0.62), (0.15 * L, 0.9, -0.15, 0.6), (0.5 * L, 0.0, 0.1, 0.78)]
    for s0, s1 in zip(sec, sec[1:]):
        a0, w0, lo0, hi0 = s0
        a1, w1, lo1, hi1 = s1
        add(parts, "k:farbe", [Pt(a0, -w0, hi0), Pt(a1, -w1, hi1), Pt(a1, w1, hi1), Pt(a0, w0, hi0)][::-1], None, None, [lin("#b9926a")] * 4)          # Deck
        for sgn in (-1, 1):
            add(parts, "k:farbe", [Pt(a0, sgn * w0, lo0), Pt(a1, sgn * w1, lo1), Pt(a1, sgn * w1, hi1), Pt(a0, sgn * w0, hi0)], None, (vx * sgn, vz * sgn),
                [shade(RED, 0.9)] * 2 + [hull_col] * 2)
    add(parts, "k:farbe", [Pt(sec[0][0], sec[0][1], sec[0][3]), Pt(sec[0][0], -sec[0][1], sec[0][3]), Pt(sec[0][0], -sec[0][1], 0.0), Pt(sec[0][0], sec[0][1], 0.0)], None,
        (-ux, -uz), [hull_col] * 4)
    mast_h = 0.95 * L
    cyl(parts, cx + ux * 0.05 * L, cz + uz * 0.05 * L, 0.05, y_base + 0.6, y_base + mast_h, STEEL, sides=5, cap=False)
    a_m = 0.05 * L
    for sgn in (-1, 1):       # Großsegel (Dreieck) beidseitig sichtbar
        add(parts, "k:farbe", [Pt(a_m - 0.02, 0.0, 1.0), Pt(-0.42 * L, 0.0, 1.0), Pt(a_m - 0.02, 0.0, mast_h - 0.2)], None, (vx * sgn, vz * sgn), [sail_col] * 3)
    add(parts, "k:farbe", [Pt(a_m + 0.05, 0.0, 0.9), Pt(0.48 * L, 0.0, 0.9), Pt(a_m + 0.05, 0.0, mast_h - 0.5)], None, (vx, vz), [shade(sail_col, 0.92)] * 3)
    return parts


# ---------------------------------------------------------------- Strandcafé
def beach_cafe(cx, cz, ux, uz, y_base=0.0):
    """Strandcafé: weißer Kiosk mit Glasfront, korallenrotem Walmdach, Tresen und Markise; u zeigt zur Gästeseite (Wasser)."""
    n = math.hypot(ux, uz)
    ux, uz = ux / n, uz / n
    vx, vz = -uz, ux
    parts = []
    box(parts, cx, cz, ux, uz, 3.6, 7.0, y_base, y_base + 2.7, WHITE)
    box(parts, cx - ux * 1.0, cz - uz * 1.0, ux, uz, 0.5, 7.2, y_base + 2.7, y_base + 2.78, AZURE, ao=1.0)
    # Walmdach (First entlang v)
    hl, hw_, ridge = 3.85, 2.15, 2.0
    h0, h1 = y_base + 2.78, y_base + 4.0

    def Rf(a, b, y):
        return (cx + ux * a + vx * b, cz + uz * a + vz * b, y)
    add(parts, "k:farbe", [Rf(hw_, -hl, h0), Rf(hw_, hl, h0), Rf(0.0, ridge, h1), Rf(0.0, -ridge, h1)], None, None, [shade(CORAL, 0.9)] * 4)
    add(parts, "k:farbe", [Rf(-hw_, hl, h0), Rf(-hw_, -hl, h0), Rf(0.0, -ridge, h1), Rf(0.0, ridge, h1)], None, None, [CORAL] * 4)
    add(parts, "k:farbe", [Rf(hw_, hl, h0), Rf(-hw_, hl, h0), Rf(0.0, ridge, h1)], None, None, [shade(CORAL, 0.82)] * 3)
    add(parts, "k:farbe", [Rf(-hw_, -hl, h0), Rf(hw_, -hl, h0), Rf(0.0, -ridge, h1)], None, None, [shade(CORAL, 0.86)] * 3)
    # Glasfront und Tresen zur Wasserseite, Markise
    add(parts, "k:lampe", [Rf(1.81, -3.0, y_base + 0.5), Rf(1.81, 3.0, y_base + 0.5), Rf(1.81, 3.0, y_base + 2.3), Rf(1.81, -3.0, y_base + 2.3)], None, (ux, uz), [(0.05, 0.1, 0.14)] * 4)
    box(parts, cx + ux * 2.4, cz + uz * 2.4, ux, uz, 0.7, 5.6, y_base, y_base + 1.05, lin("#b08a5a"))
    for k in range(12):
        c = CORAL if k % 2 == 0 else WHITE
        a0, a1 = -3.3 + k * 0.55, -3.3 + (k + 1) * 0.55
        add(parts, "k:farbe", [Rf(1.8, a0, y_base + 2.65), Rf(1.8, a1, y_base + 2.65), Rf(3.1, a1, y_base + 2.25), Rf(3.1, a0, y_base + 2.25)], None, None, [c] * 4)
    return parts


# ---------------------------------------------------------------- Pflanzen für die Hänge (billig, nur Vertexfarbe)
LEAF_DARK = lin("#2f5a2c")
LEAF_MID = lin("#4a7a35")
LEAF_OLIVE = lin("#6e8a45")
TRUNK = lin("#6b5238")


def cypress(cx, cz, h, y_base=0.0, sides=7):
    """Zypresse: schmaler, dunkler Kegel auf kurzem Stamm (etwa 16 Dreiecke)."""
    parts = []
    r = max(0.28, 0.17 * h)
    cyl(parts, cx, cz, 0.07 * h * 0.5, y_base, y_base + 0.18 * h, TRUNK, sides=4, cap=False)
    ring = [(cx + r * math.cos(2 * math.pi * k / sides), cz + r * math.sin(2 * math.pi * k / sides)) for k in range(sides)]
    for k in range(sides):
        p0, p1 = ring[k], ring[(k + 1) % sides]
        add(parts, "k:farbe", [(p0[0], p0[1], y_base + 0.16 * h), (p1[0], p1[1], y_base + 0.16 * h), (cx, cz, y_base + h)], None,
            ((p0[0] + p1[0]) / 2 - cx, (p0[1] + p1[1]) / 2 - cz), [shade(LEAF_DARK, 0.7), shade(LEAF_DARK, 0.7), shade(LEAF_DARK, 1.15)])
    return parts


def stone_pine(cx, cz, h, y_base=0.0, sides=8):
    """Schirmpinie: Stamm und flache, breite Krone (zwei Ringe, etwa 40 Dreiecke)."""
    parts = []
    cyl(parts, cx, cz, 0.16 * h * 0.35, y_base, y_base + 0.72 * h, TRUNK, sides=5, cap=False)
    r = 0.36 * h
    y0, y1, y2 = y_base + 0.66 * h, y_base + 0.82 * h, y_base + 0.95 * h
    for (ra, ya, rb, yb, c0, c1) in ((r * 0.55, y0, r, y1, 0.75, 0.95), (r, y1, r * 0.5, y2, 0.95, 1.2)):
        for k in range(sides):
            a0, a1 = 2 * math.pi * k / sides, 2 * math.pi * (k + 1) / sides
            p0 = (cx + ra * math.cos(a0), cz + ra * math.sin(a0), ya)
            p1 = (cx + ra * math.cos(a1), cz + ra * math.sin(a1), ya)
            q1 = (cx + rb * math.cos(a1), cz + rb * math.sin(a1), yb)
            q0 = (cx + rb * math.cos(a0), cz + rb * math.sin(a0), yb)
            add(parts, "k:farbe", [p0, p1, q1, q0], None, (math.cos((a0 + a1) / 2), math.sin((a0 + a1) / 2)),
                [shade(LEAF_MID, c0)] * 2 + [shade(LEAF_MID, c1)] * 2)
    add(parts, "k:farbe", [(cx + r * 0.5 * math.cos(2 * math.pi * k / sides), cz + r * 0.5 * math.sin(2 * math.pi * k / sides), y2) for k in range(sides)][::-1], None, None,
        [shade(LEAF_MID, 1.25)] * sides)
    return parts


def shrub(cx, cz, r, y_base=0.0, color=None, sides=6):
    """Niedriger Busch (flache Kuppel aus zwei Ringen, etwa 24 Dreiecke)."""
    parts = []
    col = color or LEAF_OLIVE
    ring = [(cx + r * math.cos(2 * math.pi * k / sides), cz + r * math.sin(2 * math.pi * k / sides)) for k in range(sides)]
    top = [(cx + r * 0.45 * math.cos(2 * math.pi * k / sides + 0.3), cz + r * 0.45 * math.sin(2 * math.pi * k / sides + 0.3)) for k in range(sides)]
    for k in range(sides):
        k2 = (k + 1) % sides
        add(parts, "k:farbe", [(*ring[k], y_base), (*ring[k2], y_base), (*top[k2], y_base + r * 0.8), (*top[k], y_base + r * 0.8)], None,
            ((ring[k][0] + ring[k2][0]) / 2 - cx, (ring[k][1] + ring[k2][1]) / 2 - cz), [shade(col, 0.7)] * 2 + [shade(col, 1.0)] * 2)
    add(parts, "k:farbe", [(*p, y_base + r * 0.8) for p in top][::-1], None, None, [shade(col, 1.15)] * sides)
    return parts


def palm_cheap(cx, cz, h, y_base=0.0, seed=0.0, n=7):
    """Einfache Palme für die Ferne: leicht gekrümmter Stamm, sieben hängende Wedel (etwa 60 Dreiecke)."""
    parts = []
    lean = 0.12 * h
    ax, az = math.cos(seed * 2.1), math.sin(seed * 2.1)
    segs = 3
    prev = (cx, cz, y_base)
    for k in range(1, segs + 1):
        t = k / segs
        p = (cx + ax * lean * t * t, cz + az * lean * t * t, y_base + h * 0.85 * t)
        r0, r1 = 0.17 * (1.05 - 0.4 * (k - 1) / segs), 0.17 * (1.05 - 0.4 * k / segs)
        for s in range(5):
            a0, a1 = 2 * math.pi * s / 5, 2 * math.pi * (s + 1) / 5
            add(parts, "k:farbe", [(prev[0] + r0 * math.cos(a0), prev[1] + r0 * math.sin(a0), prev[2]), (prev[0] + r0 * math.cos(a1), prev[1] + r0 * math.sin(a1), prev[2]),
                                   (p[0] + r1 * math.cos(a1), p[1] + r1 * math.sin(a1), p[2]), (p[0] + r1 * math.cos(a0), p[1] + r1 * math.sin(a0), p[2])], None,
                (math.cos((a0 + a1) / 2), math.sin((a0 + a1) / 2)), [shade(TRUNK, 0.85)] * 2 + [shade(TRUNK, 1.05)] * 2)
        prev = p
    top = prev
    for k in range(n):
        a = 2 * math.pi * k / n + seed
        dx, dz = math.cos(a), math.sin(a)
        L = 0.42 * h
        px, pz = -dz, dx
        mid = (top[0] + dx * L * 0.55, top[1] + dz * L * 0.55, top[2] + 0.25 * h * 0.45)
        end = (top[0] + dx * L, top[1] + dz * L, top[2] - 0.22 * h)
        w = 0.11 * h
        add(parts, "k:farbe", [(top[0], top[1], top[2]), (mid[0] + px * w, mid[1] + pz * w, mid[2]), (mid[0] - px * w, mid[1] - pz * w, mid[2])], None, None,
            [shade(LEAF_MID, 0.9), shade(LEAF_MID, 1.1), shade(LEAF_MID, 1.1)])
        add(parts, "k:farbe", [(mid[0] + px * w, mid[1] + pz * w, mid[2]), (end[0], end[1], end[2]), (mid[0] - px * w, mid[1] - pz * w, mid[2])], None, None,
            [shade(LEAF_MID, 1.1), shade(LEAF_MID, 0.8), shade(LEAF_MID, 1.1)])
    return parts


# ---------------------------------------------------------------- Kassenhäuschen am Eingang
def ticket_booth(cx, cz, ux, uz, y_base=0.0):
    """Kassenhäuschen: weißes Häuschen mit Fensterband zur Besucherseite (u zeigt dorthin), korallenrotem Vordach und kleinem Schild."""
    n = math.hypot(ux, uz) or 1.0
    ux, uz = ux / n, uz / n
    vx, vz = -uz, ux
    parts = []
    box(parts, cx, cz, ux, uz, 2.0, 2.6, y_base, y_base + 0.12, CONCRETE_D, ao=1.0)
    box(parts, cx, cz, ux, uz, 1.8, 2.4, y_base + 0.12, y_base + 2.5, WHITE)
    fx, fz = cx + ux * 0.905, cz + uz * 0.905
    add(parts, "k:farbe", [(fx + vx * 0.9, fz + vz * 0.9, y_base + 1.15), (fx - vx * 0.9, fz - vz * 0.9, y_base + 1.15), (fx - vx * 0.9, fz - vz * 0.9, y_base + 2.1),
                           (fx + vx * 0.9, fz + vz * 0.9, y_base + 2.1)], None, (ux, uz), [GLASS] * 4)
    box(parts, cx + ux * 0.9, cz + uz * 0.9, ux, uz, 0.1, 2.0, y_base + 1.1, y_base + 1.16, STEEL, ao=1.0)
    box(parts, cx + ux * 0.6, cz + uz * 0.6, ux, uz, 2.4, 3.0, y_base + 2.5, y_base + 2.62, CORAL, ao=1.0)
    return parts


# ---------------------------------------------------------------- Strandcafé: Tische, Surfbretter, Ball
def table_set(cx, cz, y_base=0.0, chairs=4, seed=0):
    """Runder Café-Tisch (Stahlfuß, weiße Platte) mit Stühlen aus hellem Holz rundherum."""
    parts = []
    cyl(parts, cx, cz, 0.04, y_base, y_base + 0.7, STEEL, sides=5, cap=False)
    cyl(parts, cx, cz, 0.2, y_base, y_base + 0.03, STEEL_D, sides=6, ao=1.0)
    cyl(parts, cx, cz, 0.46, y_base + 0.7, y_base + 0.74, WHITE, sides=10, ao=1.0)
    wood = lin("#c9a46c")
    for k in range(chairs):
        a = 2 * math.pi * k / chairs + seed
        px, pz = cx + 0.72 * math.cos(a), cz + 0.72 * math.sin(a)
        ux, uz = -math.cos(a), -math.sin(a)                                    # Blick zum Tisch
        box(parts, px, pz, ux, uz, 0.4, 0.4, y_base + 0.43, y_base + 0.47, wood, ao=1.0)
        box(parts, px - ux * 0.19, pz - uz * 0.19, ux, uz, 0.04, 0.4, y_base + 0.47, y_base + 0.86, wood, ao=1.0)
        for sa in (-1, 1):
            for sb in (-1, 1):
                cyl(parts, px + ux * sa * 0.17 - uz * sb * 0.17, pz + uz * sa * 0.17 + ux * sb * 0.17, 0.018, y_base, y_base + 0.43, STEEL_D, sides=4, cap=False)
    return parts


def surf_rack(cx, cz, ux, uz, y_base=0.0, cols=None):
    """Brettständer mit vier Surfbrettern (schräg angelehnt); u = Längsrichtung des Ständers."""
    n = math.hypot(ux, uz) or 1.0
    ux, uz = ux / n, uz / n
    vx, vz = -uz, ux
    parts = []
    cols = cols or [CORAL, AZURE, WHITE, TEAL]
    wood = lin("#9c7a4a")
    box(parts, cx, cz, ux, uz, 2.4, 0.2, y_base + 0.95, y_base + 1.02, wood, ao=1.0)
    for s in (-1, 1):
        box(parts, cx + ux * s * 1.1, cz + uz * s * 1.1, ux, uz, 0.1, 0.5, y_base, y_base + 1.0, wood, ao=0.9)
    for k, col in enumerate(cols):
        a = -0.9 + k * 0.6
        bx, bz = cx + ux * a, cz + uz * a
        lean = 0.35
        base = (bx - vx * 0.55, bz - vz * 0.55)
        tip = (bx + vx * lean, bz + vz * lean)
        pts = [(base[0] + ux * 0.26, base[1] + uz * 0.26, y_base + 0.02), (base[0] - ux * 0.26, base[1] - uz * 0.26, y_base + 0.02),
               (tip[0] - ux * 0.2, tip[1] - uz * 0.2, y_base + 1.7), (tip[0] + ux * 0.2, tip[1] + uz * 0.2, y_base + 1.7)]
        add(parts, "k:farbe", pts, None, (vx, vz), [shade(col, 0.9)] * 2 + [col] * 2)
        add(parts, "k:farbe", pts[::-1], None, (-vx, -vz), [shade(col, 0.8)] * 4)
    return parts


def beach_ball(cx, cz, y_base=0.0, r=0.11):
    """Kleiner Strandball (sechsseitig, bunt)."""
    parts = []
    cyl(parts, cx, cz, r, y_base, y_base + 2 * r, CORAL, sides=6, r_top=r * 0.55, ao=1.0)
    return parts
