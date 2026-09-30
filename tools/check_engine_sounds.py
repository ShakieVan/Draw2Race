"""Prüft die erzeugten Motorgeräusche objektiv (ich kann nicht hören): Kennwerte je Schicht, Spektrogramm-Bogen, Nahtlosigkeit.

Aufruf:  python tools/check_engine_sounds.py <ordner_mit_engines.json> <car> [bogen.png]
Gibt je Schicht aus: Drehzahl, Zündfrequenz (soll), stärkster Spitzenwert im Spektrum unter 1 kHz, Schwerpunkt, Effektivwert,
Sprung an der Schleifennaht. Schreibt auf Wunsch einen Bogen mit Spektrogrammen aller Schichten (Last oben, Schub unten).
"""
import json
import os
import sys
import wave

import numpy as np
from scipy import signal

folder, car = sys.argv[1], sys.argv[2]
sheet = sys.argv[3] if len(sys.argv) > 3 else None
manifest = json.load(open(os.path.join(folder, "engines.json"), encoding="utf-8"))
info = manifest["cars"][car]
FS = manifest["rate"]


def load(name):
    with wave.open(os.path.join(folder, name), "rb") as wf:
        return np.frombuffer(wf.readframes(wf.getnframes()), dtype="<i2").astype(np.float64) / 32768.0


print("MOTOR", car, "Zylinder", info["cyl"], "Leerlauf", info["idle"], "Höchstdrehzahl", info["redline"])
images = []
for k, layer in enumerate(info["layers"]):
    for mode in ("load", "coast"):
        x = load(layer[mode])
        spec = np.abs(np.fft.rfft(x * np.hanning(len(x))))
        f = np.fft.rfftfreq(len(x), 1.0 / FS)
        band = (f > 30) & (f < 1000)
        peak_f = f[band][np.argmax(spec[band])]
        centroid = float((f * spec).sum() / spec.sum())
        fire = layer["rpm"] / 60.0 * info["cyl"] / 2.0
        seam = abs(x[0] - x[-1]) / (np.std(x) + 1e-9)
        step = np.abs(np.diff(x)).mean() / (np.std(x) + 1e-9)
        print("  Schicht %d %-5s rpm=%6.0f zuend=%6.1f Hz spitze=%6.1f Hz (%.2fx) schwerpunkt=%5.0f Hz rms=%.3f sprung_naht=%.2f (mittlerer Schritt %.2f)" % (
            k, mode, layer["rpm"], fire, peak_f, peak_f / fire, centroid, np.sqrt(np.mean(x * x)), seam, step))
        if sheet:
            ff, tt, sxx = signal.spectrogram(np.tile(x, 3), FS, nperseg=1024, noverlap=768)
            images.append((k, mode, ff, tt, 10 * np.log10(sxx + 1e-12)))
if sheet:
    from PIL import Image
    w, h = 200, 150
    canvas = Image.new("RGB", (w * len(info["layers"]), h * 2), (0, 0, 0))
    for k, mode, ff, tt, db in images:
        keep = ff < 8000
        img = np.clip((db[keep][::-1] + 90) / 60, 0, 1)
        im = Image.fromarray((img * 255).astype(np.uint8)).resize((w, h)).convert("RGB")
        canvas.paste(im, (k * w, 0 if mode == "load" else h))
    canvas.save(sheet)
    print("BOGEN", sheet)
