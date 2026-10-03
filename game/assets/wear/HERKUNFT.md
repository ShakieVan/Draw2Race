# Herkunft: Spurenkarten (Nutzungsspuren)

Alle Dateien in diesem Ordner sind **eigene, prozedural erzeugte Daten** des Projekts (keine fremden Assets, keine KI-Bildmodelle).

- Erzeuger: `game/tests/make_wear.gd` (Godot-Werkzeug, deterministisch). Grundlage sind Fahrten der eigenen Fahrphysik (`RaceVehicle`) auf den Streckendateien
  `game/tracks/<id>.json`; Format und Look: `docs/dioramen/README.md` Abschnitt 9, Bauplan `docs/dioramen/HOEHEN_PLAN.md` 2.3 und 8.
- `<id>.png`: RGBA8 im Streckenraum (R Gummi, G Politur, B Spurrinne), `<id>.json`: Maße und SHA-256 der Streckendatei.
- `<id>.png.import`: verlustfrei, Mipmaps, keine Grafikkartenkompression (nicht durch Standardeinstellungen ersetzen).
- Erzeugt am 03.10.2026 für forest, quarry, harbor, fair, serra, arena, kids.
