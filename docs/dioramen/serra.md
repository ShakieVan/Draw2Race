# Diorama Serra Pass (Thema `mountain`)

Stand 02.10.2026. Modul: `tools/dio_themes/mountain.py`, Geländerechnung (reines numpy, auch außerhalb von Blender prüfbar):
`tools/make_mountain_terrain.py`, Texturen: `tools/make_mountain_textures.py` → `game/assets/dio/mountain/` (Herkunft in `HERKUNFT.md`, alles prozedural).
Bauen: `tools\dio_build.ps1 -Track serra -Shots -Times day,dusk,night -Tag _serra`. Nahansichten an beliebigen Orten: `tests/dio_shot.gd` mit `AT`
bzw. `CX`/`CZ` (Achtung: die Kamera folgt im Rennen der Fahrbahnhöhe, bei einer Position ohne Höhe zeigt `dio_shot.gd` nur Boden auf Höhe 0 an; für
Höhenstrecken eine eigene Aufnahme mit `camera_target.y = track.surface_z(s)` nutzen).

## Was gebaut ist

- **Straße**: `runtime` (Fahrbahn, Randsteine, Linien, Höhenprofil 14 bis 40 m baut das Spiel selbst). Die Streckendatei bleibt die Spielebene.
- **Glattes Gelände** statt der Treppenstufen des Höhenrasters (`runtime_terrain: False`): `make_mountain_terrain.Terrain` bildet das 3-m-Raster der Strecke
  (`track.terrain`) mit 1-m-Raster nach, verzieht es mit Rauschen (Küstenlinie, Felskanten laufen nicht mehr gerade), formt mäßige Hänge zu Terrassen
  (Trockenmauern auf den Höhenlinien) und legt den **Fahrschlauch (Abstand <= 4,3 m) exakt auf Fahrbahnhöhe + 0,08 m** (Höhe des Laufzeit-Bodens). Davon geht es
  in 1,7 m weich in Bankett, Böschung und Hang über. Der Kern prüft (Ersatzprüfung `m_check_ground`), dass nirgends Boden über der Fahrbahn liegt.
  Besonderheiten: Felsinsel mit Leuchtturm, Landzunge mit Aussichtsplattform, ebener Kapellenplatz, ebener Schotterplatz hinter dem Start und hinter dem Ziel
  (kein Loch mehr im Boden, dort liegt keine Laufzeit-Straße), ebene Terrasse für die Hirtenhütte (Platz wird gesucht), Felsnadeln im Meer.
- **Drei Netze mit glatten Rändern**: `Boden_gelaende` (Boden-Shader: Trockengras, Kalkschotter, Terra rossa), `Boden_fels` (Schichtkalk, Würfelprojektion,
  Relief der Wand), `Boden_mauer` (Trockenmauer an Terrassenstufen). Die Einteilung folgt einer Steilheit je Rasterpunkt; Zellen, durch die ein Rand läuft, werden
  entlang der Linie geschnitten (`Terrain.polys`, `m_poly_object`), die Netze teilen die Randpunkte (kein Treppenrand, kein Spalt). Das Relief der Felswand
  hat zum Rand hin das Gewicht 0. Im Fahrschlauch gibt es nie Fels.
- **Meer**: türkis im Flachen, tiefes Blau, Brandung und Schaumsaum am Kliff (Wasser-Shader); die Tiefe geht zum Bildrand hin in offenes Wasser über (kein
  Sprung vom Flachwasser zum Rahmen der Weite). Felsnadeln und drei Fischerboote.
- **Bewuchs**: Pinien mit Schirmkrone (25), Olivenhaine auf den Terrassen (13), Zypressen am Kapellenplatz, am Start und an Terrassenrändern (18), Macchia (130),
  Agaven (19) und Opuntien (15), 520 Grasbüschel (dreiseitige Halme), 90 Findlinge mit Schichtkalk-Textur. Alles selbst gebaut, gleiche Netze heißen `Prop_*`.
- **Bauten und Gerät**: Kapelle mit gepflastertem Platz und Laterne, Leuchtturm, Aussichtsplattform (KI-Modelle bleiben Laufzeit), Hirtenhütte aus Bruchstein mit
  Ziegeldach, Pferch und vier Bienenstöcken, Bildstock am Straßenrand, Parapetmauern (Trockenmauer 0,72 m) an der Talseite überall dort, wo die Streckendatei
  Leitplanken hat, Leitpfosten, Warndreieck vor der Kehre, Torbogen mit Schachbrett am Ziel (rot-weiß am Start), Zielstrich, ein parkender Transporter am Start.
- **Nacht und Dämmerung**: nichts leuchtet selbst. Echte Lichtquellen: die Leuchtturmlampe (`add_light`, Energie 0,8, Reichweite 30 m, ohne `OmniLight3D`) und die
  Kapellenlaterne (warm, 12 m). Die Fahrbahn bleibt abseits davon dunkel, aber lesbar (Randsteine).
- **Kontaktschatten**: gebackene Lichttextur für das Gelände; Kapelle, Leuchtturm und Aussichtsplattform über `ao_proxies`, Bodenhöhe über `prop_y`.
- **Gebacken** (`baked`): `ai:serra_pinie`, `ai:serra_olivenbaum`, `ai:serra_agave`, `ai:serra_fels` (sie lägen zum Teil im Meer); ihre Hindernisse stehen nur
  dort in der Begleitdatei, wo Bäume und Findlinge nahe der Fahrbahn stehen (22 Hindernisse). Kapelle, Leuchtturm, Aussichtsplattform bleiben Laufzeit-Bauteile.

## Entscheidungen

- Glattes Gelände wurde selbst gebacken (statt `runtime_terrain`), weil nur so Terrassen, Mauern, Kliffwände und Küstenlinie glatt werden. Die Fahrphysik nutzt
  weiter `track.terrain` (3 m); das Diorama weicht nur außerhalb des Fahrschlauchs davon ab. Der Absturz (Fahrbahn mehr als 2,5 m über dem Gelände) bleibt Sache der Streckendatei.
- Der Wasserkörper hat fast schwarzen Materialton: das Laternen-Zusatzlicht des Spiels (`lit_overlay`) multipliziert den Materialton mit der Vertexfarbe, und die
  Tiefe steckt in Rot. Mit weißem Ton leuchtete das Meer nachts rot um den Leuchtturm.
- Das Wasser trägt keine eigene Vertexfarbknoten-Verbindung; der Export mit `vertex_colors: ACTIVE` schreibt `COLOR_0` ohnehin.
- Triangle-Budget: rund 131 000 instanziert (Gelände rund 56 000, Bewuchs rund 55 000). Texturen höchstens 1024 px.
- Geplant, aber nicht gebaut: eine Freileitung entlang des ersten Abschnitts (der Platzfilter fand keinen Mast; der Code wurde wieder entfernt, weil das
  Bauten-Limit von sechs Läufen erreicht war).

## Prüfung (Stand dieser Fassung)

- Nahansichten mit Rennkamera (Neigung 72°, Zoom 26 m) an zehn Stellen (`AT` 0,05 bis 0,95) bei Tag und sechs bei Nacht: keine Spalten, Löcher oder
  Treppenränder; der Boden liegt unter der Fahrbahn; Start und Ziel (Schotterplatz, Torbogen, Kapellenplatz) vollständig.
- `test_diorama`: Fahrschlauch frei (0 Verstöße), KI fährt ohne Zusammenstoß ins Ziel, `runtime_road`/Lichter/Bodenhöhen wirken.

## Offene Punkte

- Die Felswand-Textur ist bei sehr starkem Zoom (< 16 m Bildbreite) etwas gestreckt (Würfelprojektion an steilen Flächen).
- Findlinge sind flach schattiert (kantig) und wirken aus der Nähe polygonal.
- Nachts leuchtet die Felswand nahe dem Leuchtturm (30 m Reichweite) kräftig warm; die Lichtkarte kennt keinen schmalen Strahl.
- Keine Freileitung (siehe oben); Strommasten wären ein guter Zusatz für Hütte und Kapelle.

## Nachtrag 03.10.2026 (Höhen-Paket, C3): Startvorfeld und Nutzungsspuren

- **Startvorfeld:** Seit dem Sprint-Start (HOEHEN_PLAN A2 h) stehen die Gegner 4,5 m je Platz hinter der Linie auf einem 15 m langen Laufzeit-Vorfeld (`world.gd`
  `build_sprint_apron`). Geprüft mit Draufsicht (`dio_shot.gd`, `AT=0`, Tag `_sp1`) und einer Rennaufnahme während des Countdowns (Kamera 7 m hinter der Linie,
  Bild `dio_serra_day_sp_grid.png`): Das Gelände des Dioramas (Schotterplatz) liegt überall unter dem Vorfeld, alle drei Gegner stehen sichtbar darauf, nichts verdeckt.
  `mountain.py` und das Diorama bleiben deshalb **unverändert** (kein Neubau). Das Vorfeld hat keine Randsteine und keine Spurenkarte (UV 0, liegt auf der ausgesparten
  Startzeile); es wirkt wie eine asphaltierte Haltebucht vor dem Torbogen.
- **Nutzungsspuren:** `game/assets/wear/serra.png` (120 × 1284 px, README Abschnitt 9): Gummistriche in den Bremszonen vor den Kehren, Politur der Ideallinie, keine
  Rinnen (Asphalt). Start- und Ziellinie ±1 m frei.
