"""Erzeugt die Motorgeräusche der Fahrzeuge (eigene Synthese, kein fremdes Klangmaterial).

Je Fahrzeug entstehen Drehzahlschichten (nahtlose Schleifen bei wachsender Drehzahl) für "Last" (Gas) und "Schub" (Gas weg),
dazu Turbo-/Kompressorschleifen sowie Einzelklänge (Schubventil, Fehlzündungen). Das Spiel überblendet zwei benachbarte
Schichten und passt die Tonhöhe an die gerade gewünschte Drehzahl an (game/scripts/engine_audio.gd).

Modell (Frequenzbereich, dadurch exakt nahtlos): Zündereignisse je Zylinder (Reihenfolge, Unregelmäßigkeit) -> Druckimpuls in
Kurbelwinkel-Skalierung -> Abgasanlage als Kammfilter-Kette (Reflexionen im Rohr) mit Schalldämpfer-Tiefpass und Formanten
(Ansaug-/Auspuffresonanzen) -> dazu Ansaug-/Verbrennungsrauschen im Takt der Zündungen, Ventilticken und beim Diesel Nageln.
Die Kennwerte der Fahrzeuge stehen in PROFILES.

Aufruf:  python tools/make_engine_sounds.py [ausgabeordner] [--car id ...] [--sweeps ordner]
Benötigt numpy. Ergebnis: <ausgabe>/engines.json und WAV-Dateien (22,05 kHz, mono, 16 Bit).
"""
import json
import math
import os
import sys
import wave

import numpy as np

FS = 22050
ARGS = sys.argv[1:]
OUT = ARGS[0] if ARGS and not ARGS[0].startswith("--") else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "assets", "sfx", "engines")
ONLY = [ARGS[i + 1] for i, a in enumerate(ARGS) if a == "--car"]
SWEEPS = ARGS[ARGS.index("--sweeps") + 1] if "--sweeps" in ARGS else None
LAYERS = 6
C_SOUND = 343.0

# Kennwerte je Fahrzeug (Schlüssel = id in vehicle.gd):
#  cyl/pattern  Zylinder und Zündfolge ("even", "boxer", "crossplane")
#  idle/redline Leerlauf-/Höchstdrehzahl (U/min)
#  pipe         [(Rohrlänge m, Rückwirkung), ...] Kammfilter der Abgasanlage
#  fc/fc_coast  Tiefpass des Schalldämpfers bei Höchstdrehzahl unter Last/im Schub (Hz)
#  peaks        [(Frequenz Hz, Güte, Verstärkung), ...] Formanten (Ansaug-/Rohrresonanzen)
#  pulse        Impulslänge als Anteil der Zündperiode (größer = weicherer, tieferer Klang)
#  noise/tick/knock Anteile von Ansaugrauschen, Ventilticken, Dieselnageln (Effektivwert relativ zum Abgas)
#  jitter       Streuung der Zündstärken je Ereignis; rms Grundlautstärke; gain_db Pegel im Spiel
#  gears        Faktor der Schaltdrehzahlen (Übersetzung), turbo Art der Aufladung, pops Fehlzündungen im Schub
PROFILES = {
    "sprint": dict(cyl=4, pattern="even", idle=1000, redline=7800, pipe=[(1.4, 0.45), (0.5, 0.30)], fc=3400, fc_coast=1700,
                   peaks=[(650, 1.6, 0.7), (1700, 1.6, 0.35)], pulse=0.16, noise=0.30, tick=0.25, knock=0.0, jitter=0.14,
                   rms=0.20, gain_db=0.0, gears=1.0, turbo="mid", pops=False),
    "grip": dict(cyl=3, pattern="even", idle=1050, redline=7000, pipe=[(1.1, 0.42), (0.45, 0.28)], fc=2600, fc_coast=1500,
                 peaks=[(420, 1.8, 0.9), (1400, 1.6, 0.3)], pulse=0.20, noise=0.35, tick=0.20, knock=0.0, jitter=0.16,
                 rms=0.19, gain_db=-1.5, gears=0.92, turbo="mid_soft", pops=False),
    "rally": dict(cyl=4, pattern="boxer", idle=1000, redline=7200, pipe=[(1.0, 0.56), (0.42, 0.34)], fc=3800, fc_coast=2000,
                  peaks=[(900, 2.2, 0.9), (2400, 1.8, 0.4)], pulse=0.14, noise=0.40, tick=0.30, knock=0.0, jitter=0.15,
                  rms=0.21, gain_db=0.5, gears=1.05, turbo="hi", pops=True),
    "muscle": dict(cyl=8, pattern="crossplane", idle=750, redline=6200, pipe=[(1.7, 0.50), (0.6, 0.30)], fc=2100, fc_coast=1300,
                   peaks=[(110, 1.6, 1.1), (230, 2.0, 0.7), (520, 2.0, 0.4)], pulse=0.24, noise=0.28, tick=0.18, knock=0.0, jitter=0.12,
                   rms=0.23, gain_db=1.5, gears=1.12, turbo="blower", pops=True, noise_scale=2.8),
    "gt": dict(cyl=10, pattern="even", idle=1100, redline=9200, pipe=[(1.1, 0.40), (0.4, 0.26)], fc=5000, fc_coast=2600,
               peaks=[(2000, 1.8, 0.7), (800, 1.6, 0.5)], pulse=0.12, noise=0.26, tick=0.30, knock=0.0, jitter=0.13,
               rms=0.20, gain_db=0.0, gears=1.0, turbo="mid", pops=False),
    "roadster": dict(cyl=4, pattern="even", idle=1300, redline=8800, pipe=[(1.0, 0.46), (0.36, 0.30)], fc=4200, fc_coast=2200,
                     peaks=[(1100, 2.0, 0.8), (2400, 1.6, 0.4)], pulse=0.13, noise=0.45, tick=0.30, knock=0.0, jitter=0.15,
                     rms=0.19, gain_db=-0.5, gears=0.96, turbo="hi_soft", pops=False),
    "pickup": dict(cyl=6, pattern="even", idle=700, redline=4600, pipe=[(1.9, 0.52), (0.7, 0.30)], fc=1700, fc_coast=1100,
                   peaks=[(90, 1.5, 1.3), (300, 2.0, 0.6)], pulse=0.30, noise=0.50, tick=0.15, knock=0.85, jitter=0.17,
                   rms=0.24, gain_db=1.0, gears=1.25, turbo="low", pops=False, noise_scale=2.8),
    "drift": dict(cyl=6, pattern="even", idle=950, redline=8000, pipe=[(1.3, 0.50), (0.45, 0.30)], fc=3700, fc_coast=1900,
                  peaks=[(520, 1.8, 0.7), (1500, 1.8, 0.4)], pulse=0.15, noise=0.30, tick=0.22, knock=0.0, jitter=0.14,
                  rms=0.21, gain_db=0.5, gears=1.0, turbo="hi", pops=True, noise_scale=3.2),
}


# Gemeinsame Einstellungen (per Suche mit dem AudioSet-Klassifikator ermittelt, siehe tools/tag_engine_sounds.py): Motoren klingen
# nach viel breitbandigem Rauschen im Takt der Zündungen und schwingender Abgasanlage, kaum nach Ventilticken. Zu schmale
# Resonanzen und zu reine Töne erkennt der Klassifikator als Sirene oder Pfeife, zu viel Höhenrauschen als Regen.
COMMON = dict(noise_hp=200.0, noise_lp0=2400.0, noise_lp1=1200.0, noise_floor=0.28, drive=1.0, roar=0.0, pipe_scale=1.0,
              noise_scale=4.0, tick_scale=0.08, tjit=0.018, am_rough=0.25, am_hz=90.0, jitter_min=0.22)
# Wichtig für den Eindruck "Motor": Die Verbrennung schwankt von Zündung zu Zündung (Zeit und Stärke). Ohne diese Unregelmäßigkeit
# klingen die Schichten wie eine Sirene; mit ihr erkennt der Klassifikator auch hochdrehende Motoren in der Probefahrt.
for _p in PROFILES.values():
    for _k, _v in COMMON.items():
        _p.setdefault(_k, _v)
    _p["jitter"] = max(_p["jitter"], _p["jitter_min"])
    _p["pipe"] = [(length, min(0.86, gain * _p["pipe_scale"])) for length, gain in _p["pipe"]]
    _p["noise"] = _p["noise"] * _p["noise_scale"]
    _p["tick"] = _p["tick"] * _p["tick_scale"]


def firing_pattern(kind, cyl):
    """Phase im Arbeitsspiel (0..1), Stärke und Auspuff-Verzögerung je Zündung eines Zyklus."""
    phase = np.arange(cyl) / cyl
    amp = np.ones(cyl)
    delay = np.zeros(cyl)
    if kind == "boxer":            # ungleich lange Krümmer: jede zweite Zündung kommt verspätet -> Blubbern
        amp = np.array([1.0, 0.86, 1.0, 0.86])[:cyl]
        delay = np.array([0.0, 0.05, 0.0, 0.05])[:cyl] / cyl * 4
    elif kind == "crossplane":     # V8 mit Kreuzwelle: ungleichmäßige Bankfolge -> tiefes Wummern
        amp = np.array([1.0, 0.80, 1.0, 1.2, 0.9, 1.1, 0.85, 1.0])[:cyl]
        delay = np.array([0.0, 0.012, -0.008, 0.02, -0.012, 0.008, -0.02, 0.004])[:cyl]
    return phase, amp, delay


def impulse_spectrum(times, amps, w):
    spectrum = np.zeros(len(w), complex)
    for i in range(0, len(times), 96):
        spectrum += (amps[i:i + 96, None] * np.exp(-1j * np.outer(times[i:i + 96], w))).sum(0)
    return spectrum


def lowpass(f, fc, order=2):
    return 1.0 / np.sqrt(1.0 + (f / max(fc, 1.0)) ** (2 * order))


def highpass(f, fc, order=2):
    x = (f + 1e-9) / fc
    return x ** order / np.sqrt(1.0 + x ** (2 * order))


def rms(x):
    return float(np.sqrt(np.mean(x * x)) + 1e-12)


def synth_layer(p, rpm, mode, seed, dur):
    """Eine nahtlose Drehzahlschicht; mode "load" (Gas) oder "coast" (Schub). Liefert (Signal float, tatsächliche Drehzahl)."""
    rng = np.random.default_rng(seed)
    cyl = p["cyl"]
    cycle = 120.0 / rpm
    cycles = max(3, int(round(dur / cycle)))
    n = int(round(cycles * cycle * FS))
    cycle = n / FS / cycles
    rpm_eff = 120.0 / cycle
    f = np.fft.rfftfreq(n, 1.0 / FS)
    w = 2 * np.pi * f
    coast = mode == "coast"
    frac = float(np.clip((rpm_eff - p["idle"]) / (p["redline"] - p["idle"]), 0, 1))
    # Zündereignisse
    phase, amp, delay = firing_pattern(p["pattern"], cyl)
    jitter = p["jitter"] * (1.7 if coast else 1.0)
    t_e, a_e = [], []
    for c in range(cycles):
        for j in range(cyl):
            a = amp[j] * (1.0 + jitter * rng.standard_normal())
            t_e.append((c + phase[j] + delay[j] + p.get("tjit", 0.0035) * rng.standard_normal()) * cycle)
            a_e.append(max(0.15, a) * (0.55 if coast else 1.0))
    t_e, a_e = np.array(t_e), np.array(a_e)
    fire = cycle / cyl
    # Druckimpuls: schneller Anstieg, Abfall proportional zur Zündperiode (Kurbelwinkel-Skalierung)
    tau_d = float(np.clip(p["pulse"] * (1.9 if coast else 1.0) * fire, 0.0004, 0.006))
    tau_a = 0.00011
    kernel = (1.0 / (1.0 / tau_d + 1j * w) - 1.0 / (1.0 / tau_a + 1j * w)) * tau_d
    x = impulse_spectrum(t_e, a_e, w) * kernel
    # Abgasanlage: zwei Kammfilter (Reflexionen), Dämpfer-Tiefpass, Formanten
    for length, gain in p["pipe"]:
        g = gain * (0.55 if coast else 1.0)
        x *= 1.0 / (1.0 - g * np.exp(-1j * w * (2.0 * length / C_SOUND)))
    fc = (p["fc_coast"] if coast else p["fc"]) * (0.5 + 0.5 * frac)
    x *= lowpass(f, fc, 2) * highpass(f, 45.0, 2)
    for f0, q, gain in p["peaks"]:
        x *= 1.0 + gain * (0.6 if coast else 1.0) / (1.0 + (q * (f / f0 - f0 / (f + 1e-9))) ** 2)
    exhaust = np.fft.irfft(x, n)
    exhaust /= rms(exhaust)
    if p.get("am_rough", 0.0) > 0:          # Rauigkeit: langsame, zufällige Stärkeschwankung des Abgasklangs (Verbrennungsstreuung)
        am = np.fft.irfft(np.fft.rfft(rng.standard_normal(n)) * lowpass(f, p.get("am_hz", 90.0), 2), n)
        exhaust *= np.maximum(0.2, 1.0 + p["am_rough"] * am / rms(am))
        exhaust /= rms(exhaust)
    # Ansaug-/Verbrennungsrauschen im Takt der Zündungen
    noise = np.fft.irfft(np.fft.rfft(rng.standard_normal(n)) * highpass(f, p.get("noise_hp", 260.0), 2)
                         * lowpass(f, p.get("noise_lp0", 1800.0) + p.get("noise_lp1", 2600.0) * frac, 2), n)
    env = np.fft.irfft(impulse_spectrum(t_e, a_e, w) / (1.0 / (0.45 * fire) + 1j * w), n)
    env = np.maximum(env, 0)
    floor = p.get("noise_floor", 0.28)
    env = floor + (1.0 - floor) * env / (env.mean() + 1e-12)
    noise = noise * env
    noise /= rms(noise)
    # Verbrennungsdröhnen: tiefes Rauschen (90–700 Hz) im Takt der Zündungen, breiter als das Ansaugrauschen
    roar = np.fft.irfft(np.fft.rfft(rng.standard_normal(n)) * highpass(f, 90.0, 2) * lowpass(f, 500.0 + 500.0 * frac, 2), n)
    env2 = np.fft.irfft(impulse_spectrum(t_e, a_e, w) / (1.0 / (0.9 * fire) + 1j * w), n)
    env2 = np.maximum(env2, 0)
    roar = roar * (0.2 + 0.8 * env2 / (env2.mean() + 1e-12))
    roar /= rms(roar)
    # Ventilticken (Ansaugventile: einmal je Zylinder und Arbeitsspiel, zufällige Stärke)
    tick_h = np.zeros(n)
    m = int(0.004 * FS)
    tt = np.arange(m) / FS
    tick_h[:m] = np.exp(-tt / 0.00035) * np.sin(2 * np.pi * (2800 + 900 * frac) * tt)
    tick_t = np.array([(c + (j + 0.5) / cyl) * cycle for c in range(cycles) for j in range(cyl)])
    tick_a = 0.5 + rng.random(len(tick_t))
    ticks = np.fft.irfft(impulse_spectrum(tick_t, tick_a, w) * np.fft.rfft(tick_h), n)
    ticks /= rms(ticks)
    # Dieselnageln: kurze, raue Breitbandstöße bei jeder Zündung
    knock = np.zeros(n)
    if p["knock"] > 0:
        k_h = np.zeros(n)
        mk = int(0.006 * FS)
        kt = np.arange(mk) / FS
        k_h[:mk] = np.exp(-kt / 0.0018) * rng.standard_normal(mk)
        k_h = np.fft.irfft(np.fft.rfft(k_h) * highpass(f, 1100.0, 2) * lowpass(f, 5200.0, 2), n)
        knock = np.fft.irfft(impulse_spectrum(t_e, a_e * (1.0 + 0.4 * rng.standard_normal(len(a_e))), w) * np.fft.rfft(k_h), n)
        knock /= rms(knock)
    mix = (exhaust * (1.0 + 0.3 * frac) + p["noise"] * (1.5 if coast else 1.0) * (1.0 - 0.25 * frac) * noise + p.get("roar", 0.0) * (0.8 if coast else 1.0) * roar
           + p["tick"] * (0.6 if coast else 1.0) * ticks + p["knock"] * (0.5 if coast else 1.0) * knock)
    mix -= mix.mean()
    target = p["rms"] * (0.58 if coast else 1.0) * (0.72 + 0.56 * frac)
    mix *= target / rms(mix)
    drive = p.get("drive", 1.35)
    mix = np.tanh(mix * drive) / drive         # weiche Begrenzung: dichter, "fetter" Klang
    mix *= target / rms(mix)
    peak = float(np.max(np.abs(mix)))
    if peak > 0.92:
        mix *= 0.92 / peak
    return mix, rpm_eff


def turbo_loop(kind, dur=1.0):
    n = int(dur * FS)
    t = np.arange(n) / FS
    rng = np.random.default_rng(91)
    f0, harm, air, flutter = {
        "hi": (3200, (1.0, 0.45, 0.18), 0.10, 0.22), "hi_soft": (3000, (1.0, 0.35, 0.10), 0.08, 0.12),
        "mid": (2200, (1.0, 0.50, 0.22), 0.14, 0.10), "mid_soft": (2000, (1.0, 0.30, 0.10), 0.12, 0.08),
        "low": (1300, (1.0, 0.60, 0.30), 0.20, 0.06), "blower": (1700, (1.0, 0.25, 0.08), 0.06, 0.04),
    }[kind]
    y = np.zeros(n)
    for k, a in enumerate(harm, 1):
        y += a * np.sin(2 * np.pi * f0 * k * t + 0.4 * np.sin(2 * np.pi * 5 * t))
    y *= 1.0 + flutter * np.sin(2 * np.pi * 11 * t) * np.sin(2 * np.pi * 3 * t)
    f = np.fft.rfftfreq(n, 1.0 / FS)
    air_n = np.fft.irfft(np.fft.rfft(rng.standard_normal(n)) * highpass(f, f0 * 0.5, 2) * lowpass(f, f0 * 2.2, 2), n)
    y = y / rms(y) + air * air_n / rms(air_n)
    y *= 0.22 / rms(y)
    return np.clip(y, -0.95, 0.95)


def blow_off(kind, dur=0.8):
    n = int(dur * FS)
    t = np.arange(n) / FS
    rng = np.random.default_rng(17)
    f = np.fft.rfftfreq(n, 1.0 / FS)
    center = 3500 if kind in ("hi", "hi_soft") else 2200
    y = np.fft.irfft(np.fft.rfft(rng.standard_normal(n)) * highpass(f, center * 0.4, 2) * lowpass(f, center * 1.8, 2), n)
    y *= (1 - np.exp(-t / 0.004)) * np.exp(-t / 0.22)
    f_start, f_end = center * 0.8, center * 0.3            # Zischen mit fallender Tonhöhe
    y += 0.25 * np.sin(2 * np.pi * (f_start * t - (f_start - f_end) * t * t / (2 * dur))) * np.exp(-t / 0.18)
    y *= 0.5 / (np.max(np.abs(y)) + 1e-9)
    return y


def pop(seed, dur=0.35):
    n = int(dur * FS)
    t = np.arange(n) / FS
    rng = np.random.default_rng(300 + seed)
    f = np.fft.rfftfreq(n, 1.0 / FS)
    body = np.fft.irfft(np.fft.rfft(rng.standard_normal(n)) * highpass(f, 120.0, 2) * lowpass(f, 1500.0 + 300 * seed, 2), n)
    y = body * np.exp(-t / (0.030 + 0.01 * seed)) + 0.5 * np.sin(2 * np.pi * (70 + 12 * seed) * t) * np.exp(-t / 0.05)
    y *= (1 - np.exp(-t / 0.0008))
    y *= 0.7 / (np.max(np.abs(y)) + 1e-9)
    return y


def write_wav(path, samples):
    data = (np.clip(samples, -1, 1) * 32000).astype("<i2")
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(FS)
        wf.writeframes(data.tobytes())


def build(car, p, out_dir):
    rpms = [p["idle"] * (p["redline"] * 0.97 / p["idle"]) ** (k / (LAYERS - 1)) for k in range(LAYERS)]
    layers = []
    for k, rpm in enumerate(rpms):
        dur = 2.2 if k == 0 else (1.5 if k < 3 else 1.2)
        entry = {}
        for mode in ("load", "coast"):
            sig, rpm_eff = synth_layer(p, rpm, mode, seed=1000 * (list(PROFILES).index(car) + 1) + 10 * k + (mode == "coast"), dur=dur)
            name = f"{car}_{mode}_{k}.wav"
            write_wav(os.path.join(out_dir, name), sig)
            entry[mode] = name
            entry["rpm"] = round(rpm_eff, 1)
            entry["frames"] = len(sig)
        layers.append(entry)
    return {"id": car, "cyl": p["cyl"], "idle": p["idle"], "redline": p["redline"], "layers": layers, "gain_db": p["gain_db"],
            "gears": p["gears"], "turbo": p["turbo"], "pops": p["pops"]}


def main():
    os.makedirs(OUT, exist_ok=True)
    manifest = {"rate": FS, "cars": {}}
    for car, p in PROFILES.items():
        if ONLY and car not in ONLY:
            continue
        manifest["cars"][car] = build(car, p, OUT)
        print("MOTOR", car, [round(l["rpm"]) for l in manifest["cars"][car]["layers"]], flush=True)
    kinds = sorted({p["turbo"] for p in PROFILES.values()})
    for kind in kinds:
        write_wav(os.path.join(OUT, f"turbo_{kind}.wav"), turbo_loop(kind))
        write_wav(os.path.join(OUT, f"bov_{kind}.wav"), blow_off(kind))
    for k in range(4):
        write_wav(os.path.join(OUT, f"pop_{k}.wav"), pop(k))
    manifest["turbo_kinds"] = kinds
    manifest["pops"] = 4
    path = os.path.join(OUT, "engines.json")
    if ONLY and os.path.exists(path):          # Teilläufe ergänzen das vorhandene Verzeichnis
        old = json.load(open(path, encoding="utf-8"))
        old["cars"].update(manifest["cars"])
        manifest["cars"] = old["cars"]
    json.dump(manifest, open(path, "w", encoding="utf-8"), indent=1)
    print("MOTOR fertig:", len(manifest["cars"]), "Fahrzeuge ->", OUT)


if __name__ == "__main__":
    main()
