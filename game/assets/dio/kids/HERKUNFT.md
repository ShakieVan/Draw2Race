# Texturen des Themas kids (Toy Box Speedway)

Alle Texturen sind eigene prozedurale Erzeugnisse (`tools/make_kids_textures.py`, numpy/scipy/Pillow), kein Fremdmaterial.

- `parkett*.jpg`: Dielenatlas (8 Dielen), `parkett_licht.jpg` dieselben Dielen heller für das Fensterlicht.
- `teppich*.jpg`, `wolle*.jpg`: Spielteppich mit Sternen/Monden und neutrale Wollstruktur.
- `tapete.jpg`, `zeichnung.jpg`, `lineal.jpg`, `truhe.jpg`: Wand, Kinderzeichnung (Wachsmalstift-Optik), Lineal, Truhendeckel.
- Schriften in Zeichnung/Lineal/Truhe: Caveat Bold und Barlow Condensed Bold (SIL OFL).
- `spiel.jpg`: Atlas 4 x 4 Felder zu 256 Bildpunkten für flach liegende Spielsachen (Kreuzbrett, Kartenrücken, Herz-Ass, Pik-König, Heft mit Kritzelei, Stickerbogen,
  Bilderbuch „Frosch“, Puzzle); gezeichnet mit Pillow in `make_kids_textures.py spiel`, Schrift Barlow Condensed Bold (SIL OFL).
- `sand*.jpg`: Spielsand für die Sandfläche an der langsamen Stelle (umgekipptes Sandkasten-Eimerchen, Haufen, Burg); nahtlos, 6 m je Kachel.
- `lineal_wippe_oben.jpg`, `lineal_wippe_teile.png`: Oberseite (Buche, Zentimeterskala 0 bis 60, Aufdruck) und Seiten/Stirn (Buchenkante, rot-weiße Schraffur)
  des Wippen-Lineals; `make_kids_textures.py lineal_wippe`, Schrift Barlow Condensed Bold (SIL OFL). Das Modell `game/assets/props/kinder_lineal.glb` baut
  `tools/make_kids_ruler.py` in Blender daraus (eigene Geometrie, Texturen eingebettet).
