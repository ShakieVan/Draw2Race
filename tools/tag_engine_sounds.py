"""Gegenprobe für die Motorgeräusche mit dem AudioSet-Klassifikator (AST, BSD-3) aus der Audio-Werkstatt.

Jede Datei wird zu 6 s aneinandergereiht, auf 16 kHz gebracht und bewertet. Ausgabe je Datei: die stärksten Klassen und die
motorbezogenen (Engine, Vehicle, Car, Race car, Idling, Accelerating/revving, Motor vehicle, Truck, Motorcycle …).
Aufruf (in der Analyse-Umgebung der Werkstatt):  python tag_engine_sounds.py <ordner> [muster ...]
Benötigt torch, transformers, librosa; das Modell MIT/ast-finetuned-audioset-10-10-0.4593 liegt im Cache der Werkstatt.
"""
import glob
import json
import os
import sys

import librosa
import numpy as np
import torch
from transformers import ASTFeatureExtractor, ASTForAudioClassification

MODEL = "MIT/ast-finetuned-audioset-10-10-0.4593"
folder = sys.argv[1]
patterns = sys.argv[2:] or ["*_load_*.wav"]
fe = ASTFeatureExtractor.from_pretrained(MODEL)
model = ASTForAudioClassification.from_pretrained(MODEL).eval()
labels = model.config.id2label
engine_words = ("Engine", "Vehicle", "Car", "Race car", "Idling", "Accelerating", "Motor", "Truck", "Motorcycle", "Light engine",
                "Medium engine", "Heavy engine", "Engine knocking", "Turbo", "Whoosh", "Hiss", "Buzz", "Noise")
files = sorted({f for pat in patterns for f in glob.glob(os.path.join(folder, pat))})
report = {}
for path in files:
    y, _ = librosa.load(path, sr=16000, mono=True)
    reps = int(np.ceil(6 * 16000 / len(y)))
    y = np.tile(y, reps)[:6 * 16000]
    inp = fe(y, sampling_rate=16000, return_tensors="pt")
    with torch.no_grad():
        prob = torch.sigmoid(model(**inp).logits)[0].numpy()
    top = np.argsort(prob)[::-1][:6]
    motor = {labels[i]: round(float(prob[i]), 2) for i in range(len(prob)) if any(w in labels[i] for w in engine_words) and prob[i] > 0.08}
    name = os.path.basename(path)
    report[name] = {"top": [(labels[int(i)], round(float(prob[i]), 2)) for i in top], "motor": motor}
    print(name, "| top:", ", ".join("%s %.2f" % (labels[int(i)], prob[i]) for i in top[:5]), "| motor:", motor, flush=True)
json.dump(report, open(os.path.join(folder, "tags_ast.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
