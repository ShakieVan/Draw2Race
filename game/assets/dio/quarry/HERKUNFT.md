# Texturen des Steinbruch-Dioramen

Alles prozedural erzeugt mit `tools/make_quarry_textures.py` (numpy, scipy, Pillow), kein fremdes Material.

- `boden_schotter`, `boden_staub`, `boden_fels` (+ `_n` Normalkarten): Bodenmischung des Dioramen (`ground_set`).
- `quelle/`: Texturen für in Blender gebaute Teile (Findlinge, Natursteinblöcke, Container, Wellblech); der Ordner ist
  per `.gdignore` vom Godot-Import ausgenommen, die Bilder stecken eingebettet in `game/dioramas/quarry.glb`.
- Bagger, Kipper, Brecher, Förderband, Büro, Kieshaufen, Felswände: KI-Modelle aus `game/assets/props/steinbruch_*`
  (Herkunft dort dokumentiert); sie bleiben Laufzeit-Bauteile.
