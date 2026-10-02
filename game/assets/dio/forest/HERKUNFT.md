# Texturen des Wald-Dioramas

Alles prozedural erzeugt mit `tools/make_forest_textures.py` (numpy, scipy, Pillow), kein fremdes Material.

- `boden_wald`, `boden_nadeln`, `boden_erde` (+ `_n` Normalkarten): Bodenmischung des Dioramas (`ground_set`). `boden_erde` (Wegerde: festgefahrene Erde mit Schotter, Laub und Nadeln, dazu dunkle feuchte Flecken) bildet den Saum der Piste; der frühere Schlamm steckt als `quelle/matsch.jpg` im Material F_Matsch, die Radspuren als `quelle/spur.jpg` im Material F_Spur.
- `quelle/`: Texturen für in Blender gebaute Teile (Holz, Rinde, Schindeln, Laub, Matsch, Spur); der Ordner ist per `.gdignore` vom
  Godot-Import ausgenommen, die Bilder stecken eingebettet in `game/dioramas/forest.glb`.
- Hütte, Felsen, Wegweiser, Holzstapel, Baumstümpfe, Stämme, Laternen: KI-Modelle aus `game/assets/props/wald_*` (Herkunft dort dokumentiert).
- Bäume, Unterholz, Steg, Ruderboot, Hochsitz, Holzpolter, Strohballen: selbst gebaut in `tools/dio_themes/forest.py` (Blender, keine fremden Modelle).
