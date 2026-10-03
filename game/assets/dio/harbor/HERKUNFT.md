# Texturen des Hafen-Themas (Harbour Run, Drift Arena)

Alle Dateien dieses Ordners sind **selbst erzeugt** (`tools/make_harbor_textures.py`, Python mit numpy, scipy, Pillow); es wurde nichts heruntergeladen.

| Datei(en) | Verwendung | Herkunft |
|---|---|---|
| `beton.jpg`, `beton_n.jpg` | Boden-Shader (Kachel 8 m): Betonplatten mit Fugen, Haarrissen, Flecken | eigenes FFT-Rauschen; Betonkörnung aus **Concrete034** (ambientCG, CC0, `art/texturen`) herausgefiltert und eingemischt |
| `asphalt.jpg`, `asphalt_n.jpg` | Boden-Shader (Kachel 6 m): Asphalt mit Flicken, Fugen, Rissen | Körnung und Normalkarte aus **Asphalt031** (ambientCG, CC0), verkleinert und gekachelt; Rest eigenes Rauschen |
| `verschleiss.jpg`, `verschleiss_n.jpg` | Boden-Shader (Kachel 8 m): ölig-dunkler Belag mit Reifenabrieb, Rost, Splitt | Körnung aus **Asphalt031**, Rest eigenes Rauschen |
| `src/` | Quellen der Blender-Materialien (Container, Wellblech, Lehm, Gewebeplane, verwitterter Fahrzeuglack `lack.png`); `.gdignore`: Godot importiert den Ordner nicht, die Bilder landen eingebettet in `game/dioramas/{harbor,arena}.glb` | eigenes Rauschen und Zeichnen; Schrift der Containernummern: **Outfit** (SIL OFL 1.1, `game/assets/Outfit.ttf`) |

Zusätzlich verwendet das Thema die Spielmaterialien `assets/event/{banner,portal,schach,menge}.png` (Rennausstattung des Kerns) und die
CC0-Texturen Concrete034 (Kaimauer, Betonbauteile) aus `art/texturen`.

Lizenz der erzeugten Bilder: wie das Projekt; sie enthalten kein fremdes Material außer den oben genannten CC0-Körnungen.
- `src/riffelblech.png`, `src/riffelblech_n.png` (03.10.2026): Tränenblech für das Stahldeck der Containerterrasse, prozedural (`tools/make_harbor_textures.py riffel`), keine fremden Quellen.
