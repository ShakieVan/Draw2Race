"""Erzeugt die Stoß- und Fahrgeräusche der Fahrzeuge (eigene Synthese, kein fremdes Klangmaterial): Berührung zweier Autos,
Aufprall an der Leitplanke, Landung nach dem Sprung, Absturz, Turbo-Einsatz und Rumpeln auf dem Randstein.

Bausteine: abklingender Dumpfschlag (Sinus mit fallender Tonhöhe), Knackgeräusch (bandbegrenztes Rauschen), Blechklang
(unharmonische Teiltöne mit eigener Abklingzeit) und die Rumpelschleife. Die Schleife ist im
Frequenzbereich gebaut (exakt periodisch, nahtlos). Jede Variante nutzt eigene Zufallswerte, damit Wiederholungen nicht gleich klingen.

Aufruf:  python tools/make_impact_sounds.py [ausgabeordner]
Benötigt numpy. Ergebnis: <ausgabe>/impacts.json und WAV-Dateien (22,05 kHz, mono, 16 Bit).
"""
import json
import os
import sys
import wave

import numpy as np

FS = 22050
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "game", "assets", "sfx", "impacts")


def t_axis(seconds):
    return np.arange(int(seconds * FS)) / FS


def band_noise(rng, n, lo, hi, order=2):
    """Bandbegrenztes Rauschen (Butterworth-ähnlich im Frequenzbereich)."""
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / FS)
    resp = (1.0 / np.sqrt(1.0 + (lo / np.maximum(f, 1e-6)) ** (2 * order))) * (1.0 / np.sqrt(1.0 + (f / hi) ** (2 * order)))
    x = np.fft.irfft(spec * resp, n)
    return x / (np.abs(x).max() + 1e-9)


def thump(n, f0, f1, tau, amp=1.0):
    """Dumpfschlag: Sinus, dessen Tonhöhe von f0 auf f1 fällt, exponentiell abklingend."""
    t = np.arange(n) / FS
    freq = f1 + (f0 - f1) * np.exp(-t / (tau * 0.6))
    phase = 2 * np.pi * np.cumsum(freq) / FS
    return amp * np.sin(phase) * np.exp(-t / tau)


def ring(n, modes, rng, amp=1.0):
    """Blechklang: unharmonische Teiltöne (Frequenz, Abklingzeit, Stärke), leicht verstimmt je Aufruf."""
    t = np.arange(n) / FS
    out = np.zeros(n)
    for f, tau, a in modes:
        f = f * rng.uniform(0.97, 1.03)
        out += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / tau)
    return amp * out


def place(dst, src, at, gain=1.0):
    i = int(at * FS)
    m = min(len(src), len(dst) - i)
    if m > 0:
        dst[i:i + m] += src[:m] * gain


def finish(x, peak=0.9, fade=0.004):
    x = np.asarray(x, float)
    k = int(fade * FS)
    if k > 0:
        x[-k:] *= np.linspace(1, 0, k)
    x = np.tanh(x * 1.2) / np.tanh(1.2)
    return x * peak / (np.abs(x).max() + 1e-9)


def write(name, x):
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(FS)
        wf.writeframes((np.clip(x, -1, 1) * 32000).astype("<i2").tobytes())


def grains(rng, n, count, span, tau):
    """Hüllkurve aus mehreren kurzen, zufällig verteilten Stößen (Knirschen, Splittern)."""
    env = np.zeros(n)
    t = np.arange(n) / FS
    for _ in range(count):
        at = rng.uniform(0, span)
        env += rng.uniform(0.4, 1.0) * np.where(t >= at, np.exp(-(t - at) / tau), 0.0)
    return env


def hit_car(seed):
    """Zwei Autos berühren sich: dumpfer Schlag, Knirschen von Kunststoff und Blech, nur wenig Klang."""
    rng = np.random.default_rng(seed)
    n = int(0.36 * FS)
    x = np.zeros(n)
    x += thump(n, rng.uniform(90, 115), 45, 0.085, 1.2)
    x += 0.7 * band_noise(rng, n, 300, 2400) * grains(rng, n, 4, 0.12, 0.022)
    x += 0.4 * band_noise(rng, n, 120, 700) * np.exp(-t_axis(0.36) / 0.11)          # Nachrasseln
    x += ring(n, [(330, 0.04, 0.12), (900, 0.025, 0.09)], rng, 0.8)
    return finish(x)


def hit_rail(seed):
    rng = np.random.default_rng(100 + seed)
    n = int(0.75 * FS)
    t = t_axis(0.75)
    x = np.zeros(n)
    x += thump(n, rng.uniform(85, 105), 50, 0.08, 0.7)
    x += 0.8 * band_noise(rng, n, 1200, 7000) * np.exp(-t / 0.022)
    x += ring(n, [(235, 0.16, 0.26), (580, 0.12, 0.22), (1070, 0.08, 0.18), (1710, 0.05, 0.14), (2490, 0.035, 0.10)], rng, 1.0)
    x += 0.5 * band_noise(rng, n, 400, 3000) * grains(rng, n, 6, 0.2, 0.03)
    scrape = band_noise(rng, n, 1500, 5200) * np.clip(0.3 + 0.9 * smooth_noise(rng, n, 28), 0.0, 1.0)
    x += 0.5 * scrape * np.exp(-t / 0.2) * np.minimum(1.0, t / 0.03)
    return finish(x)


def smooth_noise(rng, n, rate):
    """Langsam schwankende Hüllkurve (Tiefpass-Rauschen um 0 bis rate Hz), auf etwa ±1 normiert."""
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / FS)
    spec *= 1.0 / np.sqrt(1.0 + (f / rate) ** 4)
    x = np.fft.irfft(spec, n)
    return x / (np.abs(x).max() + 1e-9)


def land(seed):
    rng = np.random.default_rng(400 + seed)
    n = int(0.5 * FS)
    t = t_axis(0.5)
    x = thump(n, rng.uniform(75, 90), 38, 0.10, 1.0)
    x += 0.5 * band_noise(rng, n, 120, 900) * np.exp(-t / 0.05)
    x += 0.25 * np.sin(2 * np.pi * 160 * t) * np.exp(-t / 0.12)          # Nachfedern
    x += 0.15 * band_noise(rng, n, 1500, 5000) * np.exp(-t / 0.012)       # Reifenklatsch
    return finish(x)


def crash(seed):
    rng = np.random.default_rng(500 + seed)
    n = int(1.5 * FS)
    x = np.zeros(n)
    big = hit_rail(seed + 7) * 1.0
    place(x, big, 0.0, 1.0)
    place(x, hit_car(seed + 3), 0.27, 0.8)
    place(x, hit_rail(seed + 11), 0.52, 0.6)
    t = t_axis(1.5)
    x += 0.25 * band_noise(rng, n, 1800, 6500) * (np.abs(np.sin(2 * np.pi * 14 * t)) ** 2) * np.exp(-np.maximum(t - 0.3, 0) / 0.5) * (t > 0.3)
    for k in range(26):                                                      # Glas- und Kleinteile: kurze Geräuschkörner statt Töne
        at = 0.3 + rng.uniform(0, 0.95)
        m = int(rng.uniform(0.01, 0.03) * FS)
        g = band_noise(rng, m, rng.uniform(2500, 4500), 9000) * np.exp(-np.arange(m) / FS / 0.008)
        place(x, g, at, rng.uniform(0.15, 0.45))
    return finish(x)


def kick():
    """Turbo-Einsatz: aufsteigendes Luftrauschen mit dumpfem Schlag."""
    rng = np.random.default_rng(600)
    n = int(0.55 * FS)
    t = t_axis(0.55)
    sweep = np.zeros(n)
    bands = [(500, 1600), (900, 2800), (1600, 4500), (2600, 7000)]
    for k, (lo, hi) in enumerate(bands):
        seg = band_noise(rng, n, lo, hi)
        w = np.exp(-((t - (0.06 + 0.06 * k)) / 0.07) ** 2)
        sweep += seg * w
    x = 0.7 * sweep + thump(n, 110, 55, 0.07, 0.8) + 0.3 * band_noise(rng, n, 200, 900) * np.exp(-t / 0.12)
    return finish(x)


def rumble_loop():
    """Randsteinrumpeln, 1 s nahtlos: dumpfe Schläge (32 je Sekunde) mit Rauschen; das Spiel ändert die Tonhöhe mit dem Tempo."""
    rng = np.random.default_rng(700)
    n = FS
    x = np.zeros(n)
    period = n // 32
    for k in range(32):
        at = k * period + int(rng.uniform(-0.05, 0.05) * period)
        m = int(0.03 * FS)
        t = np.arange(m) / FS
        pulse = np.sin(2 * np.pi * rng.uniform(85, 110) * t) * np.exp(-t / 0.011) * rng.uniform(0.75, 1.0)
        pulse += 0.35 * band_noise(rng, m, 300, 2500) * np.exp(-t / 0.008)
        for shift in (0, -n, n):
            i = at + shift
            if 0 <= i < n:
                j = min(m, n - i)
                x[i:i + j] += pulse[:j]
            elif -m < i < 0:
                x[:m + i] += pulse[-i:]
    x += 0.12 * band_noise(rng, n, 60, 600)
    return finish(x, 0.8, fade=0.0)


def main():
    os.makedirs(OUT, exist_ok=True)
    manifest = {"rate": FS, "files": {}}
    jobs = {}
    for i in range(3):
        jobs[f"hit_car_{i}.wav"] = ("car", hit_car(i))
        jobs[f"hit_rail_{i}.wav"] = ("rail", hit_rail(i))
    for i in range(2):
        jobs[f"land_{i}.wav"] = ("land", land(i))
        jobs[f"crash_{i}.wav"] = ("crash", crash(i))
    jobs["kick.wav"] = ("kick", kick())
    jobs["rumble_loop.wav"] = ("rumble", rumble_loop())
    for name, (kind, x) in jobs.items():
        write(name, x)
        manifest["files"][name] = {"kind": kind, "frames": len(x), "loop": name.endswith("_loop.wav")}
    with open(os.path.join(OUT, "impacts.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=1)
    print("Stoßgeräusche:", len(jobs), "Dateien in", OUT)


main()
