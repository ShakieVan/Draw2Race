"""Stapelumrechnung Bild -> 3D mit TRELLIS.2 in der vorhandenen Ocean-3D-Werkstatt (WSL).

Lädt die Pipeline EINMAL und rechnet dann alle angegebenen freigestellten Bilder nacheinander. Ergebnisse landen
direkt in Draw2Race/.tools/ai3d/runs/<name>/ (model.glb, input.png, provenance.json). Vorhandene Ergebnisse
werden übersprungen. Start über tools/ai3d_batch.sh (setzt die Umgebung wie run.sh der Werkstatt).
Aufruf: ai3d_batch.sh <dreiecke> <textur_px> name [name ...]
"""
import gc
import os
import hashlib
import json
import sys
import time
from pathlib import Path

import lab  # Modul der lokalen 3D-Werkstatt (Pfad über PYTHONPATH, siehe ai3d_batch.sh)

D2R = Path(__file__).resolve().parents[1]
SRC = D2R / "art" / "bildvorlagen" / "freigestellt"
RUNS = D2R / ".tools" / "ai3d" / "runs"


def main():
    triangles, texture = int(sys.argv[1]), int(sys.argv[2])
    names = [n for n in sys.argv[3:] if not (RUNS / n / "model.glb").exists()]
    print("Zu rechnen:", len(names), names, flush=True)
    if not names:
        return
    import torch
    import numpy as np
    import o_voxel
    lab.check_access()
    pipeline = lab.load_pipeline("1024")
    for name in names:
        try:
            convert(pipeline, name, triangles, texture)
        except RuntimeError as error:
            # Sehr detailreiches Laub kann den Grafikspeicher sprengen: Objekt überspringen, Rest weiterrechnen.
            print(f"FEHLER {name}: {error}", flush=True)
            import shutil
            shutil.rmtree(RUNS / name, ignore_errors=True)
            gc.collect()
            torch.cuda.empty_cache()


def convert(pipeline, name, triangles, texture):
    import torch
    import o_voxel
    if True:
        start = time.monotonic()
        image = lab.validate_image(str(SRC / f"{name}.png"))
        run = RUNS / name
        run.mkdir(parents=True, exist_ok=True)
        image.save(run / "input.png")
        mesh = pipeline.run(image, seed=42, pipeline_type="1024_cascade")[0]
        # Rohnetz vor der Nachbearbeitung begrenzen: bei feingliedrigen Objekten (Latten, Laub) sprengt ein Rohnetz
        # mit vielen Millionen Dreiecken sonst den Grafikspeicher. Fürs Endergebnis (wenige tausend) ohne Bedeutung.
        mesh.simplify(int(os.environ.get("AI3D_RAW_FACES", "16777216")))
        glb = o_voxel.postprocess.to_glb(
            vertices=mesh.vertices, faces=mesh.faces, attr_volume=mesh.attrs,
            coords=mesh.coords, attr_layout=mesh.layout, voxel_size=mesh.voxel_size,
            aabb=[[-.5, -.5, -.5], [.5, .5, .5]],
            decimation_target=triangles, texture_size=texture,
            remesh=True, remesh_band=1, remesh_project=0, verbose=False,
        )
        glb.export(str(run / "model.glb"))
        (run / "provenance.json").write_text(json.dumps({
            "generator": lab.REPO, "model_revisions": pipeline.ocean_revisions, "resolution": "1024", "seed": 42,
            "target_triangles": triangles, "texture_size": texture, "seconds": round(time.monotonic() - start, 1),
            "input_sha256": hashlib.sha256((run / "input.png").read_bytes()).hexdigest(),
            "image_source": "Bild-KI (ChatGPT) nach art/bildvorlagen/%s.txt" % name,
        }, indent=2))
        print(f"FERTIG {name} {time.monotonic() - start:.0f}s", flush=True)
        del mesh, glb
        gc.collect()
        torch.cuda.empty_cache()


if __name__ == "__main__":
    main()
