"""Rendert eine Probefahrt je Fahrzeug aus den Motorschichten, so wie das Spiel sie überblendet (game/scripts/engine_audio.gd):
Leerlauf, Vollgas durch die Gänge, Gas weg, Bremsen. Dient der objektiven Kontrolle (Spektrogramm, Klassifikator, Beschreibung).

Aufruf:  python tools/render_engine_sweep.py <ordner_mit_engines.json> <ausgabeordner> [car ...]
"""
import json
import os
import sys
import wave

import numpy as np

folder, out_dir = sys.argv[1], sys.argv[2]
only = sys.argv[3:]
manifest = json.load(open(os.path.join(folder, "engines.json"), encoding="utf-8"))
FS = manifest["rate"]
os.makedirs(out_dir, exist_ok=True)
BLOCK = 441


def load(name):
    with wave.open(os.path.join(folder, name), "rb") as wf:
        return np.frombuffer(wf.readframes(wf.getnframes()), dtype="<i2").astype(np.float64) / 32768.0


def rpm_plan(info, seconds=16.0):
    """Drehzahl und Gas über die Zeit: 1,5 s Leerlauf, Vollgas in vier Gängen, Gas weg (Schub), Ausrollen."""
    idle, red = info["idle"], info["redline"] * 0.97
    t = np.arange(0, seconds, BLOCK / FS)
    rpm = np.zeros_like(t)
    thr = np.zeros_like(t)
    for i, ti in enumerate(t):
        if ti < 1.5:
            rpm[i], thr[i] = idle * (1.0 + 0.02 * np.sin(ti * 9)), 0.0
        elif ti < 11.0:
            u = ti - 1.5
            gear, within = divmod(u, 2.4)                      # vier Gänge à 2,4 s
            low = idle * 1.7 if gear == 0 else red * 0.58
            rpm[i] = low + (red - low) * (within / 2.4) ** 0.9
            thr[i] = 1.0
        elif ti < 14.0:
            u = (ti - 11.0) / 3.0
            rpm[i] = red * (1 - u) + idle * 1.6 * u            # Schub: Drehzahl fällt
            thr[i] = 0.0
        else:
            rpm[i], thr[i] = idle * 1.3, 0.0
    # Drehzahl träge nachführen (aufwärts schnell, abwärts langsam)
    for i in range(1, len(rpm)):
        rate = 0.30 if rpm[i] > rpm[i - 1] else 0.10
        rpm[i] = rpm[i - 1] + (rpm[i] - rpm[i - 1]) * rate if abs(rpm[i] - rpm[i - 1]) < 2500 else rpm[i]
    return t, rpm, thr


def render(car):
    info = manifest["cars"][car]
    layers = info["layers"]
    rpms = [l["rpm"] for l in layers]
    data = [{"load": load(l["load"]), "coast": load(l["coast"])} for l in layers]
    t, rpm, thr = rpm_plan(info)
    pos = {}
    out = np.zeros(len(t) * BLOCK)
    throttle_s = 0.0
    for bi in range(len(t)):
        r = float(np.clip(rpm[bi], rpms[0], rpms[-1]))
        throttle_s += (thr[bi] - throttle_s) * 0.25
        k = int(np.searchsorted(rpms, r, side="right") - 1)
        k = min(max(k, 0), len(rpms) - 2)
        w = (r - rpms[k]) / (rpms[k + 1] - rpms[k])
        gains = {(k, "load"): np.cos(w * np.pi / 2), (k + 1, "load"): np.sin(w * np.pi / 2)}
        load_w, coast_w = np.sqrt(0.12 + 0.88 * throttle_s), np.sqrt(1.0 - 0.88 * throttle_s)
        block = np.zeros(BLOCK)
        for (layer, mode), g in list(gains.items()) + [((layer, "coast"), g * coast_w) for (layer, m), g in list(gains.items())]:
            amp = g * (load_w if mode == "load" else 1.0)
            if mode == "load":
                amp = g * load_w
            sig = data[layer][mode]
            rate = rpm[bi] / rpms[layer]
            p = pos.get((layer, mode), 0.0)
            idx = p + np.arange(BLOCK) * rate
            i0 = np.floor(idx).astype(int)
            frac = idx - i0
            a = sig[i0 % len(sig)]
            b = sig[(i0 + 1) % len(sig)]
            block += amp * (a * (1 - frac) + b * frac)
            pos[(layer, mode)] = (p + BLOCK * rate) % len(sig)
        out[bi * BLOCK:(bi + 1) * BLOCK] = block
    out *= 0.9 / max(1e-6, np.abs(out).max())
    path = os.path.join(out_dir, f"{car}_probefahrt.wav")
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(FS)
        wf.writeframes((out * 32000).astype("<i2").tobytes())
    print("PROBEFAHRT", car, path)


for car in (only or list(manifest["cars"])):
    render(car)
