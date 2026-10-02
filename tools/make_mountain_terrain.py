"""Gelände des Serra-Passes (Thema "mountain"): reine numpy-Rechnung, ohne Blender (wird vom Themenmodul tools/dio_themes/mountain.py
eingebunden und lässt sich auch außerhalb von Blender prüfen: python tools/make_mountain_terrain.py [bild.png]).

Die Fahrphysik kennt das Höhenraster der Streckendatei (track.terrain, 3-m-Raster, bilinear): daraus folgen Absturz (Fahrbahn mehr als
2,5 m über dem Gelände) und die Höhe, auf der das Spiel Bausteine setzt. Das Diorama bildet dasselbe Relief fein und glatt nach:
  1. Das Raster wird mit Rauschen verzogen (Küstenlinie, Felskanten und Schluchten laufen nicht mehr gerade), bilinear abgetastet und
     gerundet. Die Verzerrung wächst mit dem Abstand zur Fahrbahn: in Fahrbahnnähe bleibt das Relief des Rasters unverändert.
  2. Hänge mit mäßiger Neigung werden zu Terrassen (Trockenmauern auf den Höhenlinien).
  3. Der Fahrschlauch (Abstand <= CORRIDOR zur Mittellinie) liegt exakt auf der Fahrbahnhöhe des Höhenprofils plus 0,08 m (Höhe des
     Laufzeit-Bodens); davon geht es weich ins Relief über (Bankett, Böschung, Straßengraben).
  4. Besonderheiten: Felsinsel für den Leuchtturm, Landzunge für den Aussichtspunkt, Platz an der Kapelle, Auslauf an Start und Ziel,
     ebene Terrasse für die Hirtenhütte (Platz wird gesucht).
  5. Einteilung in Boden, Felswand und Terrassenmauer mit glatten Rändern (classify, polys): Steilheit je Rasterpunkt, Zellen mit Rand werden
     entlang der Linie gS = 0 bzw. T = 0,3 geschnitten.
Alle Höhen sind absolut (Meter über dem Meeresboden-Nullpunkt der Streckendatei, Meer bei WATER_Y).
"""
import json
import math
import os
import sys

import numpy as np

WATER_Y = -2.05                 # Meeresspiegel (das Spiel hat darunter einen Meereskasten mit Oberkante -2,3)
GROUND_Y = 0.08                 # Höhe des Laufzeit-Bodens über der Fahrbahnbasis (Fahrbahn liegt bei 0,17)
CORRIDOR = 4.3                  # Abstand zur Mittellinie, bis zu dem das Gelände exakt auf der Fahrbahnhöhe liegt
BLEND = 1.7                     # Breite des weichen Übergangs danach
TERRACE_H = 2.2                 # Höhe einer Terrasse (m)
CLIFF_SLOPE = 0.85              # ab dieser Neigung (Höhe je Meter) gilt das Gelände als Felswand
WALL_SLOPE = 0.62               # in der Terrassenzone schon ab dieser Neigung als Trockenmauer
HILL = {"lighthouse": (-60.0, 62.0), "lookout": (-20.0, 50.0), "chapel": (8.43, -89.8), "start": (-86.0, 40.0)}
STACKS = [(-35.0, 58.0, 2.4, 7.5), (-8.0, 63.0, 3.0, 9.0), (14.0, 56.0, 2.0, 5.5), (-86.0, 57.0, 2.6, 6.5), (31.0, 59.0, 2.3, 7.0), (-98.0, 66.0, 1.8, 4.5)]   # Felsnadeln im Meer: (x, z, Radius, Höhe über dem Meeresboden)
PLAZA = (8.0, -86.0)            # Mitte des Kapellenplatzes; Radius der ebenen Fläche
PLAZA_R = 7.8
HUT_R = 8.0                     # Radius der ebenen Terrasse der Hirtenhütte


def smooth(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


class Noise:
    """Weiches Wertrauschen (Werte 0..1), kachelnd, mit festem Samen."""

    def __init__(self, seed=17, size=128):
        self.g = np.random.default_rng(seed).random((size, size))
        self.n = size

    def __call__(self, x, z, scale, ox=0.0):
        u, v = np.asarray(x, float) / scale + ox, np.asarray(z, float) / scale + ox * 0.61
        i0, j0 = np.floor(u).astype(int), np.floor(v).astype(int)
        fu, fv = smooth(u - i0), smooth(v - j0)
        g, n = self.g, self.n
        a = g[j0 % n, i0 % n] * (1 - fu) + g[j0 % n, (i0 + 1) % n] * fu
        b = g[(j0 + 1) % n, i0 % n] * (1 - fu) + g[(j0 + 1) % n, (i0 + 1) % n] * fu
        return a * (1 - fv) + b * fv

    def fbm(self, x, z, scale, octaves=3, ox=0.0):
        out, amp, tot = 0.0, 1.0, 0.0
        for k in range(octaves):
            out = out + amp * self(x, z, scale / (2 ** k), ox + 17.0 * k)
            tot += amp
            amp *= 0.5
        return out / tot


def blur(a, sigma):
    """Gaußsche Glättung (getrennt, Ränder gespiegelt); sigma in Zellen."""
    if sigma <= 0.05:
        return a
    r = int(math.ceil(sigma * 3.0))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    out = a
    for axis in (0, 1):
        pad = [(0, 0), (0, 0)]
        pad[axis] = (r, r)
        p = np.pad(out, pad, mode="edge")
        acc = np.zeros_like(out)
        for i, w in enumerate(k):
            sl = [slice(None), slice(None)]
            sl[axis] = slice(i, i + out.shape[axis])
            acc = acc + w * p[tuple(sl)]
        out = acc
    return out


def resample_open(points, step):
    pts = [np.array(p, float) for p in points]
    out, carry = [], 0.0
    for a, b in zip(pts, pts[1:]):
        seg = float(np.linalg.norm(b - a))
        t = carry
        while t < seg:
            out.append(a + (b - a) * (t / seg))
            t += step
        carry = t - seg
    out.append(pts[-1])
    return np.array(out)


class Terrain:
    def __init__(self, data, x0, x1, z0, z1, step=1.0, extend_start=18.0, extend_end=8.0, seed=17):
        self.data = data
        self.step = step
        self.x0, self.x1, self.z0, self.z1 = x0, x1, z0, z1
        self.noise = Noise(seed)
        t = data["terrain"]
        self.gw, self.gh, self.gcell = int(t["w"]), int(t["h"]), float(t["cell"])
        self.gox, self.goz = float(t["origin"][0]), float(t["origin"][1])
        self.G = np.array(t["heights"], float).reshape(self.gh, self.gw)
        # Mittellinie alle 0,5 m (wie der Kern), dazu die Verlängerung vor dem Start und hinter dem Ziel (nur für den Fahrschlauch des Bodens)
        c0 = resample_open(data["points"], 0.5)
        seg = np.hypot(*np.diff(c0, axis=0).T)
        dist = np.concatenate([[0.0], np.cumsum(seg)])
        self.length = float(dist[-1])
        el = np.array(data["elevation"], float)
        s = dist / self.length
        base = np.interp(s, el[:, 0], el[:, 1])
        t0 = (c0[1] - c0[0]) / np.linalg.norm(c0[1] - c0[0])
        t1 = (c0[-1] - c0[-2]) / np.linalg.norm(c0[-1] - c0[-2])
        pre = np.array([c0[0] - t0 * k * 0.5 for k in range(int(extend_start / 0.5), 0, -1)]) if extend_start > 0 else np.zeros((0, 2))
        post = np.array([c0[-1] + t1 * k * 0.5 for k in range(1, int(extend_end / 0.5) + 1)]) if extend_end > 0 else np.zeros((0, 2))
        self.C = np.concatenate([pre, c0, post]) if len(pre) or len(post) else c0
        self.B = np.concatenate([np.full(len(pre), base[0]), base, np.full(len(post), base[-1])])
        self.S = np.concatenate([np.full(len(pre), 0.0), s, np.full(len(post), 1.0)])
        self.n_pre = len(pre)
        self.gx = np.arange(x0, x1 + 1e-6, step)
        self.gz = np.arange(z0, z1 + 1e-6, step)
        self.X, self.Z = np.meshgrid(self.gx, self.gz)

    # ------------------------------------------------------------------ Hilfen
    def grid_height(self, x, z):
        """Höhenraster der Strecke (bilinear) wie track.terrain_height im Spiel."""
        fx = (np.asarray(x, float) - self.gox) / self.gcell
        fz = (np.asarray(z, float) - self.goz) / self.gcell
        ix = np.clip(np.floor(fx).astype(int), 0, self.gw - 2)
        iz = np.clip(np.floor(fz).astype(int), 0, self.gh - 2)
        tx = np.clip(fx - ix, 0, 1)
        tz = np.clip(fz - iz, 0, 1)
        G = self.G
        a = G[iz, ix] * (1 - tx) + G[iz, ix + 1] * tx
        b = G[iz + 1, ix] * (1 - tx) + G[iz + 1, ix + 1] * tx
        return a * (1 - tz) + b * tz

    def nearest(self, x, z):
        """Nächster Punkt der (verlängerten) Mittellinie: Abstand, Seitenversatz (links +), Basishöhe am Fußpunkt, Streckenanteil."""
        P = np.stack([np.asarray(x, float).ravel(), np.asarray(z, float).ravel()], 1)
        C, B, S = self.C, self.B, self.S
        n = len(C)
        d_out = np.zeros(len(P))
        lat_out = np.zeros(len(P))
        b_out = np.zeros(len(P))
        s_out = np.zeros(len(P))
        for k in range(0, len(P), 3000):
            q = P[k:k + 3000]
            d2 = ((q[:, None, :] - C[None, :, :]) ** 2).sum(2)
            i = d2.argmin(1)
            best = np.full(len(q), 1e18)
            res_lat = np.zeros(len(q))
            res_b = np.zeros(len(q))
            res_s = np.zeros(len(q))
            for off in (-1, 0):
                a_i = np.clip(i + off, 0, n - 2)
                A, Bp = C[a_i], C[a_i + 1]
                ab = Bp - A
                ll = np.maximum((ab ** 2).sum(1), 1e-9)
                tt = np.clip(((q - A) * ab).sum(1) / ll, 0, 1)
                foot = A + ab * tt[:, None]
                dd = np.sqrt(((q - foot) ** 2).sum(1))
                tang = ab / np.sqrt(ll)[:, None]
                left = np.stack([-tang[:, 1], tang[:, 0]], 1)
                lat = ((q - foot) * left).sum(1)
                bb = B[a_i] + (B[a_i + 1] - B[a_i]) * tt
                ss = S[a_i] + (S[a_i + 1] - S[a_i]) * tt
                better = dd < best
                best = np.where(better, dd, best)
                res_lat = np.where(better, lat, res_lat)
                res_b = np.where(better, bb, res_b)
                res_s = np.where(better, ss, res_s)
            d_out[k:k + 3000] = best
            lat_out[k:k + 3000] = res_lat
            b_out[k:k + 3000] = res_b
            s_out[k:k + 3000] = res_s
        shape = np.asarray(x).shape
        return d_out.reshape(shape), lat_out.reshape(shape), b_out.reshape(shape), s_out.reshape(shape)

    # ------------------------------------------------------------------ Relief
    def build(self):
        X, Z, st = self.X, self.Z, self.step
        nz_ = self.noise
        d, lat, Bn, Sn = self.nearest(X, Z)
        self.d, self.lat, self.Bn, self.Sn = d, lat, Bn, Sn
        # 1. Raster verziehen: grobe Verformung (Küste, Schluchten) und feine (Felskanten); in Fahrbahnnähe unverändert.
        far = smooth((d - 9.0) / 9.0)
        mid = smooth((d - 7.0) / 6.0)
        wx = (nz_(X, Z, 26.0, 1.0) - 0.5) * 2 * 5.5 * far + (nz_(X, Z, 6.5, 4.0) - 0.5) * 2 * 1.3 * mid
        wz = (nz_(X, Z, 26.0, 9.0) - 0.5) * 2 * 5.5 * far + (nz_(X, Z, 6.5, 12.0) - 0.5) * 2 * 1.3 * mid
        Gw = self.grid_height(X + wx, Z + wz)
        Hs = blur(Gw, 1.35 / st)
        # 2. Terrassen: mäßig geneigte Hänge zu Stufen (Trockenmauern auf den Höhenlinien)
        gz_, gx_ = np.gradient(Hs, st)
        sl = np.hypot(gx_, gz_)
        ph = (nz_(X, Z, 70.0, 5.0) - 0.5) * TERRACE_H * 1.2 + (nz_(X, Z, 19.0, 8.0) - 0.5) * TERRACE_H * 0.55
        t = (Hs + ph) / TERRACE_H
        fl = np.floor(t)
        Hq = (fl + smooth((t - fl - 0.70) / 0.30)) * TERRACE_H - ph
        zone = smooth((nz_.fbm(X, Z, 52.0, 2, 9.0) - 0.36) * 7.0)          # Terrassen nur in Teilen des Hangs, sonst natürlicher Hang
        T = smooth((sl - 0.08) / 0.07) * (1.0 - smooth((sl - 0.46) / 0.22)) * smooth((d - 11.0) / 5.0) * smooth((Hs - 2.0) / 2.0) * zone
        for key, (hx, hz) in HILL.items():              # nicht an den Besonderheiten
            T *= smooth((np.hypot(X - hx, Z - hz) - 16.0) / 8.0)
        self.T = T
        H1 = Hs + T * (Hq - Hs)
        # 3. Besonderheiten
        H1 = self.features(H1, X, Z)
        # 4. Fahrschlauch: exakt Fahrbahnhöhe + 0,08, weicher Übergang ins Relief
        Hc = Bn + GROUND_Y
        wc = smooth((d - CORRIDOR) / BLEND)
        H = Hc + (H1 - Hc) * wc
        # Rand der Fläche: das Land taucht ins Meer ab (kein abgeschnittener Rand, auch nach der Verformung des Rasters)
        edge = np.minimum.reduce([X - self.x0, self.x1 - X, Z - self.z0, self.z1 - Z])
        H = -3.0 + (H + 3.0) * smooth(edge / 12.0)
        # Feines Rauschen (nur auf mäßigem Gelände, kleiner als die Zellgröße der Netzvereinfachung)
        self.H = H
        gz2, gx2 = np.gradient(H, st)
        self.slope = np.hypot(gx2, gz2)
        self.gx_, self.gz_ = gx2, gz2
        return self

    def relief_raw(self, amp=0.8):
        """Rohe Verschiebung (m) der Felswandpunkte: waagerecht entlang der Flächennormalen (ox, oz) und senkrecht (oy), damit die Wände nicht als glatte
        Ebene stehen. Wirksam wird sie über das Gewicht relief_weight (null am Rand der Felswand, also keine Risse zum Boden)."""
        ln = np.hypot(self.gx_, self.gz_) + 1e-6
        nx, nz_ = -self.gx_ / ln, -self.gz_ / ln
        n = self.noise
        off = ((n(self.X, self.Z, 3.4, 31.0) - 0.5) * 1.7 + (n(self.X, self.Z, 1.5, 41.0) - 0.5) * 0.8) * amp
        self.rox, self.roz = nx * off, nz_ * off
        self.roy = (n(self.X, self.Z, 2.3, 51.0) - 0.5) * 0.45
        return self

    def features(self, H, X, Z):
        nz_ = self.noise
        # Felsinsel mit dem Leuchtturm: unregelmäßige Kuppe im Meer
        hx, hz = HILL["lighthouse"]
        ang = np.arctan2(Z - hz, X - hx)
        rr = np.hypot(X - hx, Z - hz) / (7.5 * (1.0 + 0.22 * np.sin(3 * ang + 0.7) + 0.12 * np.sin(5 * ang + 2.1) + 0.5 * (nz_(X, Z, 5.0, 3.0) - 0.5)))
        isle = -3.0 + 9.4 * smooth(1.0 - rr) ** 0.8 + 0.4 * (nz_(X, Z, 3.0, 8.0) - 0.5) * smooth(1.0 - rr)
        H = np.where(rr < 1.0, np.maximum(H, isle), H)
        # Landzunge mit dem Aussichtspunkt: Felsrücken vom Küstenhang ins Meer
        hx, hz = HILL["lookout"]
        # Rücken entlang z von der Fahrbahn (z ~ 38) bis hz + 3,5; Breite ~ 9 m, Höhe 9 m über dem Meer
        along = np.clip((Z - 36.0) / (hz + 4.0 - 36.0), 0.0, 1.0)
        widthr = 5.2 * (1.0 - 0.35 * along) + 1.1 * (nz_(X, Z, 6.0, 2.0) - 0.5)
        across = np.abs(X - (hx + 2.0 * np.sin(Z * 0.11))) / np.maximum(widthr, 0.5)
        ridge = np.where((Z > 34.0) & (Z < hz + 6.5), 1.0 - smooth(across), 0.0)
        top = 7.2 - 1.5 * smooth((Z - 42.0) / (hz - 42.0))
        tail = smooth((hz + 6.5 - Z) / 3.5)
        lump = -3.0 + (top + 3.0) * ridge ** 0.7 * tail
        lump += 0.35 * (nz_(X, Z, 3.5, 6.0) - 0.5) * (lump > -2.0)
        H = np.where(lump > H, lump, H)
        # Felsnadeln im Meer (Brandung am Fuß)
        for sx, sz, sr, sh in STACKS:
            a_ = np.arctan2(Z - sz, X - sx)
            rr = np.hypot(X - sx, Z - sz) / (sr * (1.0 + 0.25 * np.sin(2 * a_ + sx) + 0.15 * np.sin(5 * a_ + sz)))
            stack = -3.0 + sh * smooth(1.0 - rr) ** 0.55 + 0.5 * (nz_(X, Z, 2.4, 3.0) - 0.5) * smooth(1.0 - rr)
            H = np.where(rr < 1.0, np.maximum(H, stack), H)
        # Aussichtsplattform: ebene Kuppe unter dem Aussichtspunkt
        hx, hz = HILL["lookout"]
        top_y = float(np.max(np.where(np.hypot(X - hx, Z - hz) < 1.0, H, -9.0)))
        r = np.hypot(X - hx, Z - hz)
        wl = 1.0 - smooth((r - 3.6) / 3.2)
        self.lookout_y = max(top_y, 5.0)
        H = np.where(r < 7.0, H + (self.lookout_y - H) * wl, H)
        # Platz an der Kapelle: eben auf Höhe des Fahrbahnendes, dahinter steigt der Hang an
        cx, cz = PLAZA
        self.plaza_y = float(self.B[-1]) + GROUND_Y
        r = np.hypot(X - cx, Z - cz) * (1.0 + 0.22 * (nz_(X, Z, 9.0, 14.0) - 0.5))
        wpl = 1.0 - smooth((r - PLAZA_R) / 10.0)
        H = H + (self.plaza_y - H) * wpl
        # Hirtenhütte: ebene Terrasse im Gras. Der Platz wird gesucht: mäßig geneigtes Gras 14 bis 26 m neben der Fahrbahn, nicht an Wänden, möglichst glatt
        sl_ = np.hypot(*np.gradient(H, self.step))
        rough = blur(sl_, 4.0 / self.step)
        far_special = np.ones(H.shape, bool)
        for key, (hx, hz) in HILL.items():
            far_special &= np.hypot(X - hx, Z - hz) > 22.0
        far_special &= np.hypot(X - PLAZA[0], Z - PLAZA[1]) > 26.0
        okc = (self.d > 14.0) & (self.d < 26.0) & (H > 8.0) & (sl_ < 0.38) & (rough < 0.42) & far_special & (X > self.x0 + 22) & (X < self.x1 - 22) & (Z > self.z0 + 22) & (Z < self.z1 - 22)
        if okc.any():
            score = np.where(okc, rough + 0.012 * np.abs(self.d - 18.0), 9.0)
            jh, ih = np.unravel_index(int(np.argmin(score)), score.shape)
            self.hut = (float(X[jh, ih]), float(Z[jh, ih]))
            rr = np.hypot(X - self.hut[0], Z - self.hut[1]) * (1.0 + 0.18 * (nz_(X, Z, 8.0, 21.0) - 0.5))
            hy = float(blur(H, 3.0 / self.step)[jh, ih])
            H = H + (hy - H) * (1.0 - smooth((rr - HUT_R) / 6.0))
            self.hut_y = hy
        else:
            self.hut, self.hut_y = None, 0.0
        # Auslauf hinter dem Start (Schotterplatz) und hinter dem Ziel: eben auf Fahrbahnhöhe, seitlich weich
        for end, (ax, az, tx, tz, by, length) in self.ends().items():
            rel_x, rel_z = X - ax, Z - az
            along = rel_x * tx + rel_z * tz + (nz_(X, Z, 7.0, 16.0) - 0.5) * 3.0       # entlang der Fahrtrichtung (negativ = davor)
            across = np.abs(-rel_x * tz + rel_z * tx) + (nz_(X, Z, 6.0, 18.0) - 0.5) * 2.5
            if end == "start":
                wa = smooth((along + length) / 4.0) * (1.0 - smooth(along / 2.5 + 0.0))
                wa = wa * (along < 1.0)
            else:
                wa = (1.0 - smooth((along - length) / 2.5)) * smooth((along + 2.5) / 2.5)
            wa = wa * (1.0 - smooth((across - 7.5) / 4.0))
            H = H + (by + GROUND_Y - H) * np.clip(wa, 0.0, 1.0)
        return H

    def ends(self):
        """Anfang und Ende der Strecke: (x, z, Richtung x, Richtung z, Basishöhe, Länge des ebenen Auslaufs)."""
        c = self.data["points"]
        p0 = np.array(c[0], float)
        p1 = np.array(c[1], float)
        pe = np.array(c[-1], float)
        pf = np.array(c[-2], float)
        t0 = (p1 - p0) / np.linalg.norm(p1 - p0)
        te = (pe - pf) / np.linalg.norm(pe - pf)
        return {"start": (p0[0], p0[1], t0[0], t0[1], float(self.B[self.n_pre]), 18.0),
                "finish": (pe[0], pe[1], te[0], te[1], float(self.B[-1]), 12.0)}

    # ------------------------------------------------------------------ Einteilung in Zellen und Farbfelder
    def classify(self):
        """Einteilung in Boden, Felswand (cliff) und Terrassenmauer (wall). Die Ränder sind glatt: Eine Steilheit je Rasterpunkt (gS = Gefälle minus
        Schwelle, >= 0 heißt steil) und die Terrassenzone T entscheiden; Zellen, durch die ein Rand läuft, werden in polys() entlang der
        Linie gS = 0 bzw. T = 0,3 geschnitten (kein Treppenrand mehr). Daneben grobe Zellmasken für Bewuchs und Abstände."""
        H, st = self.H, self.step
        P = np.pad(H, 1, mode="edge")
        ms = np.maximum.reduce([np.abs(P[1:-1, 2:] - H), np.abs(P[1:-1, :-2] - H), np.abs(P[2:, 1:-1] - H), np.abs(P[:-2, 1:-1] - H)]) / st
        ms = blur(ms, 0.7 / st)
        thr = CLIFF_SLOPE - (CLIFF_SLOPE - WALL_SLOPE) * smooth((self.T - 0.2) / 0.2)
        self.gS = ms - thr - 3.0 * (1.0 - smooth((self.d - 3.4) / 1.3))          # nie steil im Fahrschlauch (die Wand beginnt erst am Bankettrand)
        c00, c10, c01, c11 = H[:-1, :-1], H[:-1, 1:], H[1:, :-1], H[1:, 1:]
        cmax = np.maximum.reduce([c00, c10, c01, c11])
        water = cmax < WATER_Y - 0.3
        # Fahrbahn: nur dort liegt die Laufzeit-Straße auf dem Boden (nicht vor dem Start und hinter dem Ziel: Sn = 0 bzw. 1 in den Verlängerungen)
        inroad = (self.d < 2.3) & (self.Sn > 1e-6) & (self.Sn < 1.0 - 1e-6)
        road = inroad[:-1, :-1] & inroad[:-1, 1:] & inroad[1:, :-1] & inroad[1:, 1:]
        S = self.gS >= 0.0
        ns = S[:-1, :-1].astype(np.int32) + S[:-1, 1:] + S[1:, :-1] + S[1:, 1:]
        T = self.T
        Tc = (T[:-1, :-1] + T[:-1, 1:] + T[1:, :-1] + T[1:, 1:]) * 0.25
        steep = (ns >= 3) & ~water & ~road
        wall = steep & (Tc > 0.3)
        cliff = steep & ~wall
        self.cell_ns = ns
        self.c_water, self.c_road, self.c_wall, self.c_cliff = water, road, wall, cliff
        self.c_ground = ~(water | road | wall | cliff)
        return self

    def attrs(self):
        """Eigenschaften je Rasterpunkt als Feld (Zeile j, Spalte i, 14): x, z, Höhe, gS, T, Bodenfarbe (3), Felsfarbe (3), Reliefverschiebung (3)."""
        f = lambda a: np.asarray(a, float)[..., None]
        GC, RC = self.ground_colors(), self.rock_colors()
        self.GC, self.RC = GC, RC
        return np.concatenate([f(self.X), f(self.Z), f(self.H), f(self.gS), f(self.T), GC, RC, f(self.rox), f(self.roy), f(self.roz)], -1)

    @staticmethod
    def relief_weight(gS, T):
        """Gewicht der Reliefverschiebung: null am Rand der Felswand und an der Mauer, voll im Inneren der Felswand."""
        return smooth(gS / 0.3) * (1.0 - smooth((T - 0.2) / 0.3))

    def final_pos(self, a):
        w = float(self.relief_weight(a[3], a[4]))
        return (a[0] + w * a[11], a[2] + w * a[12], a[1] + w * a[13])

    @staticmethod
    def _cut(poly, idx, thr):
        """Konvexes Vieleck (Liste von Eigenschaftsvektoren) an der Linie Feld[idx] = thr schneiden: (Teil >= thr, Teil < thr). Die Schnittpunkte
        entstehen immer in derselben Reihenfolge der Endpunkte, damit Nachbarzellen bitgleiche Punkte erzeugen."""
        pos, neg = [], []
        n = len(poly)
        for k in range(n):
            a, b = poly[k], poly[(k + 1) % n]
            fa, fb = a[idx] - thr, b[idx] - thr
            (pos if fa >= 0.0 else neg).append(a)
            if (fa >= 0.0) != (fb >= 0.0):
                p, q, fp, fq = (a, b, fa, fb) if (a[0], a[1]) <= (b[0], b[1]) else (b, a, fb, fa)
                c = p + (q - p) * (fp / (fp - fq))
                pos.append(c)
                neg.append(c)
        return pos, neg

    def polys(self, A=None):
        """Geometrie der drei Netze. Rückgabe: dict mit "ground_skip" (Zellmaske für den Viererbaum der Bodenblöcke), "cliff_q", "wall_q" (ganze Zellen
        als (i, j, 1)) und "ground", "cliff", "wall" (Vielecke aus Zellen mit Rand: Listen von Eigenschaftsvektoren, gegen den Uhrzeigersinn)."""
        A = self.attrs() if A is None else A
        S = self.gS >= 0.0
        T3 = self.T >= 0.3
        ns = S[:-1, :-1].astype(np.int32) + S[:-1, 1:] + S[1:, :-1] + S[1:, 1:]
        nt = T3[:-1, :-1].astype(np.int32) + T3[:-1, 1:] + T3[1:, :-1] + T3[1:, 1:]
        valid = ~(self.c_water | self.c_road)
        out = {"ground": [], "cliff": [], "wall": [], "cliff_q": [], "wall_q": []}
        full_ground = valid & (ns == 0)
        out["ground_skip"] = ~full_ground
        jj, ii = np.nonzero(valid & (ns == 4) & (nt == 0))
        out["cliff_q"] = [(int(i), int(j), 1) for i, j in zip(ii, jj)]
        jj, ii = np.nonzero(valid & (ns == 4) & (nt == 4))
        out["wall_q"] = [(int(i), int(j), 1) for i, j in zip(ii, jj)]
        jj, ii = np.nonzero(valid & ((ns > 0) & (ns < 4) | ((ns == 4) & (nt > 0) & (nt < 4))))
        for i, j in zip(ii, jj):
            a, b, c, d = A[j, i], A[j + 1, i], A[j + 1, i + 1], A[j, i + 1]
            tris = [[a, b, c], [a, c, d]] if (i + j) % 2 == 0 else [[a, b, d], [b, c, d]]
            for tri in tris:
                if ns[j, i] == 0:
                    out["ground"].append(tri)
                    continue
                steep_p, ground_p = (tri, []) if ns[j, i] == 4 else self._cut(tri, 3, 0.0)
                if len(ground_p) >= 3:
                    out["ground"].append(ground_p)
                if len(steep_p) < 3:
                    continue
                wall_p, cliff_p = self._cut(steep_p, 4, 0.3)
                if len(wall_p) >= 3:
                    out["wall"].append(wall_p)
                if len(cliff_p) >= 3:
                    out["cliff"].append(cliff_p)
        return out

    def chamfer(self, seeds):
        """Abstand (m) jedes Rasterpunkts zum nächsten Punkt, an dem seeds (Bool-Feld) wahr ist; Chamfer-Verfahren, höchstens 400 m."""
        big = 1e6
        D = np.where(seeds, 0.0, big)
        nz_, nx_ = D.shape
        st, dg = self.step, self.step * 1.4142
        for j in range(nz_):
            row = D[j]
            if j > 0:
                prev = D[j - 1]
                row = np.minimum(row, prev + st)
                row[1:] = np.minimum(row[1:], prev[:-1] + dg)
                row[:-1] = np.minimum(row[:-1], prev[1:] + dg)
            for i in range(1, nx_):
                v = row[i - 1] + st
                if v < row[i]:
                    row[i] = v
            D[j] = row
        for j in range(nz_ - 1, -1, -1):
            row = D[j]
            if j < nz_ - 1:
                nxt = D[j + 1]
                row = np.minimum(row, nxt + st)
                row[1:] = np.minimum(row[1:], nxt[:-1] + dg)
                row[:-1] = np.minimum(row[:-1], nxt[1:] + dg)
            for i in range(nx_ - 2, -1, -1):
                v = row[i + 1] + st
                if v < row[i]:
                    row[i] = v
            D[j] = row
        return np.minimum(D, 400.0)

    def dist_to_land(self):
        """Abstand (m) jedes Rasterpunkts zum nächsten Land (Höhe über dem Meeresspiegel); 0 an Land."""
        self.land_dist = self.chamfer(self.H > WATER_Y)
        return self.land_dist

    def dist_to_cliff(self):
        """Abstand (m) zur nächsten Felswand (cliff_dist) bzw. Felswand oder Terrassenmauer (rock_dist) für Geröll, Büsche, Agaven am Kliffrand."""
        out = []
        for masks in ((self.c_cliff,), (self.c_cliff, self.c_wall)):
            rock = np.zeros(self.H.shape, bool)
            for m in masks:
                rock[:-1, :-1] |= m
                rock[:-1, 1:] |= m
                rock[1:, :-1] |= m
                rock[1:, 1:] |= m
            out.append(self.chamfer(rock))
        self.cliff_dist, self.rock_dist = out
        return self.cliff_dist

    def grove(self, X, Z):
        """Zonen der Olivenhaine (0..1): gleiches Feld für Bodenfarbe und Pflanzung."""
        return smooth((self.noise.fbm(X, Z, 46.0, 2, 5.0) - 0.50) * 9.0)

    def ground_colors(self):
        """Vertexfarben des Bodens für ground_blend.gdshader: R Helligkeit, G Kalkschotter (Platz "sand"), B Terra rossa (Platz "dirt")."""
        X, Z, H, d, T = self.X, self.Z, self.H, self.d, self.T
        sl = self.slope
        nz_ = self.noise
        n_big = nz_.fbm(X, Z, 24.0, 3, 2.0)
        n_mid = nz_.fbm(X, Z, 6.5, 2, 7.0)
        n_fine = nz_(X, Z, 1.7, 15.0)
        bright = 0.97 + 0.26 * (n_big - 0.5) + 0.10 * (n_mid - 0.5) + 0.06 * (n_fine - 0.5)
        verge = 1.0 - smooth((d - 4.3) / 3.2)                        # Kalkschotter am Fahrbahnrand
        verge = verge * (0.78 + 0.22 * smooth((n_mid - 0.3) * 4.0))
        bare = smooth((sl - 0.42) / 0.35) * 0.9                       # Geröll an steileren Hängen
        patch = smooth((n_big * 0.85 + n_mid * 0.35 - 0.64) * 7.0) * 0.8
        shore = (1.0 - smooth((H - (WATER_Y + 0.15)) / 1.5)) * 0.95   # Kiesel nahe dem Wasser
        sand = np.maximum.reduce([verge, bare, patch, shore])
        grove = self.grove(X, Z)                                      # Zonen der Olivenhaine
        tread = smooth((0.40 - sl) / 0.2)
        dirt = grove * tread * (0.55 + 0.42 * T)
        dirt = np.maximum(dirt, smooth((n_mid * 0.6 + n_big * 0.7 - 0.95) * 6.0) * 0.45 * (1 - sand))
        dirt = dirt * (1.0 - sand * 0.8)
        comp = lambda w: 0.5 + (np.clip(w, 0.0, 1.0) - 0.5) * 0.66
        return np.stack([np.clip(bright, 0.55, 1.2), comp(sand), comp(dirt)], -1)

    def rock_colors(self):
        """Tönung der Felswände: Verwitterung nach Rauschen, nasses dunkles Band über dem Wasser, helle Kanten."""
        X, Z, H = self.X, self.Z, self.H
        nz_ = self.noise
        n_big = nz_.fbm(X, Z, 17.0, 3, 6.0)
        n_mid = nz_(X, Z, 4.0, 11.0)
        tone = 0.90 + 0.22 * (n_big - 0.5) + 0.12 * (n_mid - 0.5)
        wet = 1.0 - smooth((H - WATER_Y - 0.1) / 2.4)
        wet_dark = 1.0 - 0.45 * wet
        green = 1.0 - 0.10 * wet
        r = np.clip(tone * wet_dark, 0.3, 1.0)
        g = np.clip(tone * wet_dark * (0.99 + 0.0 * green), 0.3, 1.0)
        b = np.clip(tone * wet_dark * (0.97 + 0.04 * wet), 0.3, 1.0)
        return np.stack([r, g, b], -1)

    # ------------------------------------------------------------------ Abfragen
    def at(self, arr, x, z):
        """Bilinear aus einem Feld auf dem Feinraster."""
        fx = (np.asarray(x, float) - self.x0) / self.step
        fz = (np.asarray(z, float) - self.z0) / self.step
        ix = np.clip(np.floor(fx).astype(int), 0, arr.shape[1] - 2)
        iz = np.clip(np.floor(fz).astype(int), 0, arr.shape[0] - 2)
        tx = np.clip(fx - ix, 0, 1)
        tz = np.clip(fz - iz, 0, 1)
        a = arr[iz, ix] * (1 - tx) + arr[iz, ix + 1] * tx
        b = arr[iz + 1, ix] * (1 - tx) + arr[iz + 1, ix + 1] * tx
        return a * (1 - tz) + b * tz

    def height(self, x, z):
        return self.at(self.H, x, z)


def quadtree(H, COL, skip, tol_h=0.03, tol_c=0.06, max_size=8):
    """Viererbaum über ein Höhenraster: Ein Block aus s x s Zellen (s = 8, 4, 2) wird ein Viereck, wenn Höhe und Vertexfarbe darin von der
    bilinearen Interpolation der vier Ecken nicht mehr als tol_h (m) bzw. tol_c abweichen und keine Zelle ausgelassen ist (skip).
    Rückgabe: Liste (i, j, Größe) der Vierecke (Spalte, Zeile, Zellen)."""
    nzp, nxp = H.shape
    ncz, ncx = nzp - 1, nxp - 1
    out = []
    skip_i = skip.astype(np.int32)
    cum = np.zeros((ncz + 1, ncx + 1), np.int32)
    cum[1:, 1:] = skip_i.cumsum(0).cumsum(1)

    def skipped(i, j, sz):
        return (cum[min(j + sz, ncz), min(i + sz, ncx)] - cum[j, min(i + sz, ncx)] - cum[min(j + sz, ncz), i] + cum[j, i]) > 0

    def block_ok(i, j, sz):
        if i + sz > ncx or j + sz > ncz or skipped(i, j, sz):
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
            if not skip[j, i]:
                out.append((i, j, 1))
        elif block_ok(i, j, sz):
            out.append((i, j, sz))
        else:
            h2 = sz // 2
            for dj in (0, h2):
                for di in (0, h2):
                    rec(i + di, j + dj, h2)
    for j in range(0, ncz, max_size):
        for i in range(0, ncx, max_size):
            rec(i, j, max_size)
    return out


def load_track(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


if __name__ == "__main__":
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.colors import LightSource
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    data = load_track(os.path.join(root, "game", "tracks", "serra.json"))
    C = np.array(data["points"])
    m = 46
    tr = Terrain(data, math.floor(C[:, 0].min() - m), math.ceil(C[:, 0].max() + m), math.floor(C[:, 1].min() - m), math.ceil(C[:, 1].max() + m)).build()
    out = sys.argv[1] if len(sys.argv) > 1 else "terrain_preview.png"
    ls = LightSource(azdeg=315, altdeg=45)
    fig, ax = plt.subplots(1, 1, figsize=(14, 15))
    rgb = ls.shade(tr.H, cmap=plt.cm.terrain, vert_exag=1.5, dx=tr.step, dy=tr.step, blend_mode="soft")
    ax.imshow(rgb, origin="lower", extent=[tr.x0, tr.x1, tr.z0, tr.z1])
    ax.plot(C[:, 0], C[:, 1], "r-", lw=1.2)
    ax.invert_yaxis()
    plt.tight_layout()
    plt.savefig(out, dpi=60)
    print("H", tr.H.min(), tr.H.max(), "Zellen", tr.H.shape)
