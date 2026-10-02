# Texturen des Serra-Pass-Dioramen (Thema mountain)

Alles prozedural erzeugt mit `tools/make_mountain_textures.py` (numpy, scipy, Pillow), kein fremdes Material.

- `boden_trockengras`, `boden_kalk`, `boden_terrarossa` (+ `_n` Normalkarten): Bodenmischung des Dioramen (`ground_set`).
- `quelle/`: Texturen für in Blender gebaute Teile (Fels, Trockenmauer, Kiefer, Olive, Macchia, Zypresse, Agave, Opuntie, Borke);
  der Ordner ist per `.gdignore` vom Godot-Import ausgenommen, die Bilder stecken eingebettet in `game/dioramas/serra.glb`.
- Kapelle, Leuchtturm, Aussichtsplattform: KI-Modelle aus `game/assets/props/serra_*` (Herkunft dort dokumentiert); sie bleiben Laufzeit-Bauteile.
