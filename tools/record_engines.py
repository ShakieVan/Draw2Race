"""Nimmt die Motorgeräusche der Fahrzeuge mit engine-sim auf (physikalische Motorsimulation, MIT-Lizenz) und schneidet daraus
die Drehzahlschichten für das Spiel (game/assets/sfx/engines/, Format wie tools/make_engine_sounds.py).

engine-sim läuft ohne Fenster in einem Podman-Container der Klangwerkstatt (E:/Draw2Race-AudioLab/engine-sim, Prüfstand
headless/es_render). Je Fahrzeug ein Prüfstandslauf in Simulationszeit:
  Anlassen -> Leerlauf (Schicht 0 im Schub) -> Vollgas im Leerlauf bis in den Begrenzer (Begrenzer-Schleife) ->
  Prüfstand hält nacheinander jede Schichtdrehzahl: Vollgas (Last), dann Gas weg (Schub).
Aus jeder Strecke wird eine nahtlose Schleife aus ganzen Arbeitsspielen (2 Kurbelumdrehungen) mit kurzer Überblendung.
Pegel: Das Rohsignal hat einen festen Maßstab (vergleichbar zwischen allen Aufnahmen eines Motors); die Dynamik wird auf
DYN_RATIO zusammengedrückt, die lauteste Lastschicht liegt bei REF_DB (Effektivwert).

Turbo, Schubumluftventil und Fehlzündungen kommen weiterhin aus tools/make_engine_sounds.py (engine-sim kennt sie nicht);
deren Dateien und Einträge in engines.json bleiben erhalten.

Aufruf:  python tools/record_engines.py [--car id ...] [--keep] [--align-only]
         --align-only: nur den Gleichtakt der vorhandenen Schleifen herstellen (ohne neue Aufnahme)
Benötigt numpy, scipy, soundfile und Podman mit dem Abbild d2r-enginesim.
"""
import json
import math
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "game", "assets", "sfx", "engines")
LAB = "E:/Draw2Race-AudioLab/engine-sim"
LAB_WIN = r"E:\Draw2Race-AudioLab\engine-sim"
SCRIPTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "engine_sim")     # eigene/angepasste Motordateien
IMAGE = "d2r-enginesim"
FS_IN = 44100
FS = 24000
STEP = 1.055                  # Drehzahlabstand benachbarter Schichten (5,5 %): im Spiel wird höchstens ±3 % verstimmt
LOOP_S = 0.7                  # Ziel-Schleifenlänge (s)
XFADE_S = 0.025
REF_DB = -12.0                # Effektivwert der lautesten Lastschicht
DYN_RATIO = 0.4               # Rohdynamik (dB) wird auf diesen Anteil zusammengedrückt
ARGS = sys.argv[1:]
ONLY = [ARGS[i + 1] for i, a in enumerate(ARGS) if a == "--car"]

# Fahrzeug -> Motorbeschreibung (Pfad relativ zu engine-sim/assets) und Begrenzer-/Rotgrenzdrehzahl für das Spiel.
# limit: Drehzahl, bei der der Begrenzer greift (gemessen); die oberste Schicht liegt bei 0,97 * limit.
# cut: Zündunterbrechung des Begrenzers (s); kurz (50–90 ms) ergibt das schnelle Abregeln echter Motoren.
CARS = {
    "sprint":   dict(script="engines/atg-video-1/07_audi_i5.mr", cut=0.07, idle=960, limit=6450, name="Audi-Reihenfünfzylinder 2.3"),
    "grip":     dict(script="draw2race/grip_i3.mr", idle=1120, limit=6750, name="Dreizylinder 1.0 (aus Honda B18C abgeleitet)"),
    "rally":    dict(script="engines/atg-video-2/02_subaru_ej25_uh.mr", cut=0.07, idle=765, limit=6800, name="Subaru EJ25, ungleich lange Krümmer"),
    "muscle":   dict(script="draw2race/muscle.mr", idle=920, limit=6150, name="Chevrolet 454 Big-Block V8"),
    "gt":       dict(script="draw2race/gt_v12.mr", cut=0.07, idle=1180, limit=8950, name="V12 (Ferrari 412 T2, auf Straßendrehzahl begrenzt)"),
    "roadster": dict(script="engines/atg-video-1/05_honda_vtec.mr", idle=760, limit=9300, name="Honda B18C5 VTEC"),
    "pickup":   dict(script="engines/atg-video-2/05_odd_fire_v6.mr", cut=0.09, idle=930, limit=5550, name="V6 mit ungleichem Zündabstand"),
    "drift":    dict(script="engines/atg-video-2/03_2jz.mr", cut=0.07, idle=1050, limit=6450, name="Toyota 2JZ Reihensechszylinder"),
}


def program(car, idle_guess):
    c = CARS[car]
    top = 0.97 * c["limit"]
    count = int(math.ceil(math.log(top / idle_guess) / math.log(STEP))) + 1
    rpms = [idle_guess * (top / idle_guess) ** (k / (count - 1)) for k in range(count)]
    lines = ["rpmlog 0.25", "ignition on", "throttle 0.05", "starter on", "run 3", "starter off", "throttle 0", "run 6",
             "mark idle_s", "run 2.5", "mark idle_e",
             "throttle 1", "run 2.5", "mark lim_s", "run 3", "mark lim_e", "throttle 0", "run 4",
             "dyno on", "hold on"]
    # Last und Schub in je einem durchgehenden Lauf: Wechselt das Gas zwischen den Stufen, ist der Motor (Saugrohrdruck,
    # Abgas) bei der nächsten Aufnahme noch nicht eingeschwungen und jede Stufe klingt anders (Klangfarbe springt).
    lines += [f"dynorpm {rpms[0]:.1f}", "throttle 1", "run 2.0"]
    for k, r in enumerate(rpms):
        lines += [f"dynorpm {r:.1f}", "run 0.8", f"mark L{k}_s", "run 0.9", f"mark L{k}_e"]
    lines += ["throttle 0", "run 2.0"]
    for k, r in reversed(list(enumerate(rpms))):
        lines += [f"dynorpm {r:.1f}", "run 0.8", f"mark C{k}_s", "run 0.9", f"mark C{k}_e"]
    return "\n".join(lines) + "\n", rpms


def script_for(car):
    """Motordatei für den Lauf; mit "cut" wird die Zündunterbrechung des Begrenzers (limiter_duration, s) ersetzt."""
    c = CARS[car]
    if "cut" not in c:
        return c["script"]
    text = open(os.path.join(LAB, "src", "assets", c["script"]), encoding="utf-8").read()
    text, n = re.subn(r"limiter_duration:\s*[0-9.]+", f"limiter_duration: {c['cut']}", text)
    if n == 0:
        raise RuntimeError(f"{car}: keine limiter_duration in {c['script']}")
    name = f"draw2race/{car}_cut.mr"
    open(os.path.join(LAB, "src", "assets", name), "w", encoding="utf-8", newline="\n").write(text)
    return name


def render(car, idle_guess):
    prog, rpms = program(car, idle_guess)
    work = os.path.join(LAB, "rec", "d2r")
    os.makedirs(work, exist_ok=True)
    open(os.path.join(work, f"{car}.txt"), "w", newline="\n").write(prog)
    open(os.path.join(LAB, "src", "assets", f"d2r_{car}.mr"), "w", newline="\n").write(
        f'import "engine_sim.mr"\nimport "{CARS[car]["script"]}"\n\nmain()\n')
    cmd = ["podman", "run", "--rm", "-v", f"{LAB_WIN}:/es", "-w", "/es/src/bin", IMAGE, "sh", "-c",
           f"../../headless/build/es_render ../assets/d2r_{car}.mr ../../rec/d2r/{car}.txt ../../rec/d2r/{car}.wav"]
    env = dict(os.environ, MSYS_NO_PATHCONV="1")
    res = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if res.returncode != 0:
        raise RuntimeError(f"{car}: es_render {res.returncode}\n{res.stderr}")
    marks, log = {}, []
    for line in res.stdout.splitlines():
        p = line.split()
        if p and p[0] == "MARK":
            marks[p[1]] = (float(p[2]), float(p[3]))
        elif p and p[0] == "RPM":
            log.append((float(p[1]), float(p[2])))
    return os.path.join(work, f"{car}.wav"), marks, log, rpms


def loop_from(x, rpm, cycles_hint=None):
    """Nahtlose Schleife aus ganzen Arbeitsspielen: Länge L = n * (120 / rpm) s, Überblendung des Endes mit dem Vorlauf."""
    cycle = 120.0 / rpm * FS
    n = max(2, int(round(LOOP_S * FS / cycle))) if cycles_hint is None else cycles_hint
    L = int(round(n * cycle))
    X = int(XFADE_S * FS)
    if len(x) < L + X + 1:
        n = max(1, int((len(x) - X - 1) / cycle))
        L = int(round(n * cycle))
    seg = x[: L + X]
    out = seg[X: X + L].copy()
    fi = np.sin(np.linspace(0, math.pi / 2, X)) ** 2
    out[L - X:] = out[L - X:] * (1 - fi) + seg[:X] * fi
    return out


def limiter_loop(x):
    """Begrenzer: Schleife über ganze Pendelperioden (Hüllkurve per Autokorrelation)."""
    env = np.sqrt(np.convolve(x ** 2, np.ones(160) / 160, mode="same"))
    env = env[::32] - env[::32].mean()
    ac = np.correlate(env, env, mode="full")[len(env) - 1:]
    lo, hi = int(0.04 * FS / 32), int(0.5 * FS / 32)
    period = (lo + int(np.argmax(ac[lo:hi]))) * 32
    n = max(2, int(round(1.6 * FS / period)))
    L = n * period
    X = int(XFADE_S * FS)
    seg = x[: L + X]
    out = seg[X: X + L].copy()
    fi = np.sin(np.linspace(0, math.pi / 2, X)) ** 2
    out[L - X:] = out[L - X:] * (1 - fi) + seg[:X] * fi
    return out, period / FS


def db(x):
    return 20 * math.log10(math.sqrt(float(np.mean(x * x))) + 1e-12)


def build(car, old):
    guess = float(CARS[car]["idle"])
    wav, marks, log, rpms = render(car, guess)
    idle_rpm = float(np.mean([r for t, r in log if marks["idle_s"][0] <= t <= marks["idle_e"][0]]))
    # Leerlauf weicht vom Schätzwert ab: Lauf mit gemessenem Leerlauf wiederholen, damit Schicht 0 genau dort liegt
    if abs(idle_rpm - guess) > 40:
        wav, marks, log, rpms = render(car, idle_rpm)
        idle_rpm = float(np.mean([r for t, r in log if marks["idle_s"][0] <= t <= marks["idle_e"][0]]))
    x, fs = sf.read(wav, dtype="float64")
    x = resample_poly(x, FS, FS_IN)

    def cut(a, b):
        return x[int(marks[a][0] * FS): int(marks[b][0] * FS)]

    loops = {}
    for k, r in enumerate(rpms):
        loops[("load", k)] = (loop_from(cut(f"L{k}_s", f"L{k}_e"), marks[f"L{k}_s"][1]), marks[f"L{k}_s"][1])
        if k == 0:
            loops[("coast", 0)] = (loop_from(cut("idle_s", "idle_e"), idle_rpm), idle_rpm)
        else:
            loops[("coast", k)] = (loop_from(cut(f"C{k}_s", f"C{k}_e"), marks[f"C{k}_s"][1]), marks[f"C{k}_s"][1])
    lim, lim_period = limiter_loop(cut("lim_s", "lim_e"))
    raw_max = max(db(l) for (mode, _), (l, _) in loops.items() if mode == "load")
    gain = lambda raw: 10 ** ((REF_DB + DYN_RATIO * (raw - raw_max) - raw) / 20)
    layers = []
    for k in range(len(rpms)):
        entry = {}
        for mode in ("load", "coast"):
            sig, rpm = loops[(mode, k)]
            sig = sig * gain(db(sig))
            name = f"{car}_{mode}_{k}.wav"
            sf.write(os.path.join(OUT, name), np.clip(sig, -1, 1), FS, subtype="PCM_16")
            if mode == "load":
                entry["rpm"] = round(rpm, 1)
                entry["frames"] = len(sig)
            else:
                entry["coast_frames"] = len(sig)
                entry["coast_rpm"] = round(rpm, 1)
            entry[mode] = name
        layers.append(entry)
    lim = lim * gain(db(lim))
    sf.write(os.path.join(OUT, f"{car}_limiter.wav"), np.clip(lim, -1, 1), FS, subtype="PCM_16")
    lim_rpm = float(np.mean([r for t, r in log if marks["lim_s"][0] <= t <= marks["lim_e"][0]]))
    o = old.get(car, {})
    entry = {"id": car, "engine": CARS[car]["name"], "idle": round(idle_rpm), "redline": CARS[car]["limit"],
             "layers": layers, "limiter": f"{car}_limiter.wav", "limiter_frames": len(lim), "limiter_rpm": round(lim_rpm),
             "limiter_period": round(lim_period, 4), "dynamics": "baked", "gain_db": o.get("gain_db", 0.0),
             "gears": o.get("gears", 1.0), "turbo": o.get("turbo", "mid"), "pops": o.get("pops", False)}
    print("MOTOR", car, CARS[car]["name"], "Leerlauf", round(idle_rpm), "Schichten", [round(l["rpm"]) for l in layers],
          "Begrenzer", round(lim_rpm), f"Pendel {lim_period * 1000:.0f} ms", flush=True)
    if "--keep" not in ARGS:
        os.remove(wav)
    return entry


FOLD = 512                    # Punkte je Arbeitsspiel für den Gleichtaktvergleich


def cycle_template(x, cycles, envelope=False):
    """Mittleres Arbeitsspiel einer Schleife (FOLD Punkte), auf Effektivwert 1 normiert; envelope: Hüllkurve statt Welle."""
    c = len(x) / cycles
    y = x * x if envelope else x
    if envelope:
        k = max(1, int(c / 24))
        y = np.convolve(np.concatenate([y[-k:], y, y[:k]]), np.ones(k) / k, mode="same")[k:-k]
    pos = np.arange(cycles * FOLD) / FOLD * c
    t = np.interp(pos, np.arange(len(y)), y).reshape(cycles, FOLD).mean(0)
    t = t - t.mean()
    return t / (np.sqrt(np.mean(t * t)) + 1e-12)


def best_shift(t, ref):
    """Verschiebung s (in FOLD-Punkten), mit der np.roll(t, -s) am besten auf ref passt (Kreuzkorrelation über das Arbeitsspiel)."""
    xc = np.fft.irfft(np.fft.rfft(ref) * np.conj(np.fft.rfft(t)), FOLD)
    return (-int(np.argmax(xc))) % FOLD


def align_car(car, entry):
    """Gleichtakt: alle Schleifen eines Motors so drehen, dass ihre Zündungen an derselben Stelle des Arbeitsspiels liegen.
    Die Lastschichten werden der Reihe nach an die Nachbarschicht angeglichen, jede Schubschicht an die Lastschicht gleicher
    Drehzahl (über die Hüllkurve, weil sich die Wellenform im Schub stark ändert). Im Spiel setzt jede neue Schicht an der
    Stelle des Arbeitsspiels ein, an der die laufende gerade ist (engine_audio.gd); die Zündimpulse fallen dann zusammen."""
    ref = None
    for layer in entry["layers"]:
        for mode in ("load", "coast"):
            path = os.path.join(OUT, layer[mode])
            x, fs = sf.read(path, dtype="float64")
            rpm = layer["rpm"] if mode == "load" else layer.get("coast_rpm", layer["rpm"])
            cycles = max(1, int(round(len(x) / (120.0 / rpm * FS))))
            if mode == "load":
                t = cycle_template(x, cycles)
                s = 0 if ref is None else best_shift(t, ref)
                ref = np.roll(t, -s)
                env_ref = cycle_template(np.roll(x, -int(round(s / FOLD * len(x) / cycles))), cycles, envelope=True)
            else:
                s = best_shift(cycle_template(x, cycles, envelope=True), env_ref)
            x = np.roll(x, -int(round(s / FOLD * len(x) / cycles)))
            sf.write(path, x, FS, subtype="PCM_16")
            layer["cycles" if mode == "load" else "coast_cycles"] = cycles
    print("MOTOR Gleichtakt", car, len(entry["layers"]), "Schichten", flush=True)


def main():
    if "--align-only" in ARGS:
        path = os.path.join(OUT, "engines.json")
        manifest = json.load(open(path, encoding="utf-8"))
        for car, entry in manifest["cars"].items():
            if (not ONLY or car in ONLY) and entry.get("dynamics") == "baked":
                align_car(car, entry)
        json.dump(manifest, open(path, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
        return
    # eigene Motordateien in die Werkstatt kopieren (Zeilenenden LF, sonst versteht der Linux-Parser sie nicht)
    dst = os.path.join(LAB, "src", "assets", "draw2race")
    os.makedirs(dst, exist_ok=True)
    for f in os.listdir(SCRIPTS):
        if f.endswith(".mr"):
            text = open(os.path.join(SCRIPTS, f), encoding="utf-8").read().replace("\r\n", "\n")
            open(os.path.join(dst, f), "w", encoding="utf-8", newline="\n").write(text)
    path = os.path.join(OUT, "engines.json")
    manifest = json.load(open(path, encoding="utf-8"))
    old = manifest.get("cars", {})
    cars = [c for c in CARS if not ONLY or c in ONLY]
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(lambda c: (c, build(c, old)), cars))
    for car, entry in results:
        align_car(car, entry)
        manifest["cars"][car] = entry
    manifest["rate"] = FS
    manifest["source"] = "engine-sim (github.com/ange-yaghi/engine-sim, MIT), tools/record_engines.py"
    json.dump(manifest, open(path, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    print("MOTOR fertig:", len(results), "Fahrzeuge ->", OUT)


if __name__ == "__main__":
    main()
