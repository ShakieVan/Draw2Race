# Motorbeschreibungen für engine-sim

Eingabedateien für [engine-sim](https://github.com/ange-yaghi/engine-sim) (Ange Yaghi, MIT-Lizenz), mit denen
`tools/record_engines.py` die Motorgeräusche aufnimmt. Die übrigen Motoren nimmt das Werkzeug unverändert aus den
Beispielmotoren von engine-sim (siehe `CARS` im Werkzeug).

| Datei | Grundlage | Änderung |
|---|---|---|
| `muscle.mr` | `engines/chevrolet/chev_truck_454.mr` | Begrenzer 6200 U/min, eigenes Fahrzeug/Getriebe und `main` |
| `gt_v12.mr` | `engines/atg-video-2/12_ferrari_412_t2.mr` | Rotgrenze 8600, Begrenzer 9000, Schwungrad 25 lb, Leerlauf-Drosselklappe 0,998 (Straßen-V12) |
| `grip_i3.mr` | `engines/atg-video-1/05_honda_vtec.mr` | Dreizylinder: Hubzapfen 0/240/120°, Zündabstand 240°, Bohrung 74 / Hub 82 mm, ein Auspuff, Begrenzer 6800 |

Die Klänge selbst entstehen durch Simulation (kein Fremdklangmaterial); engine-sim steht unter MIT-Lizenz.

Lizenztext von engine-sim (MIT, Copyright 2022 Ange Yaghi): `LICENSE-engine-sim.txt` in diesem Ordner. Er gilt für die drei abgeleiteten `.mr`-Dateien.
