# Diorama Toy Box Speedway (`kids`)

Stand 03.10.2026 (Lineal-Wippe als Abkürzung, Bauplan `docs/dioramen/HOEHEN_PLAN.md` 4.4/7; davor 02.10.2026 Politur und Sandfläche). Modul: `tools/dio_themes/kids.py` (gemeinsame Geometrie: `tools/make_fair_kids_geom.py`), Texturen:
`tools/make_kids_textures.py` → `game/assets/dio/kids/` (Herkunft dort in `HERKUNFT.md`, alles prozedural). Bauen: `tools\dio_build.ps1 -Track kids -Shots -Times day,dusk,night -Tag _x`.

## Maßstab

Spielzeugauto etwa 1 : 50: Ein Duplo-Stein ist 3,2 x 1,6 x 1 m, ein Buntstift 8 m lang, eine Murmel 0,9 m, ein Buch 12 x 9 m, das Regal 48 m breit. Neue Spielsachen
folgen dem (grob 1 m = 1,8 cm): Würfel 1,1 m, Spielkarte 3,6 x 5 m, Badeente 3 m, Bagger 8 m, Hausschuhe 11 m, Brettspiel 14 m, Puppenhaus 18 m.
Das Titel- und Fußband des Spiels deckt in der Übersicht etwa z < -42 und z > 40 ab (rund 12 m oben und unten); Wichtiges, das im Bild sein soll, steht dazwischen.

## Lineal-Wippe (03.10.2026, Streckenfassung `rev` 2)

Die Abkürzung (`shortcuts[0]`, 73,9 m, s 0,598 bis 0,852) führt über ein 24 m langes Lineal, das auf einem Filzstift kippt (`seesaws[0]`: Drehpunkt bei
Pfadmeter 28 = (8,2 | -32,74), `pivot_h` 1,1, Dicke 0,3). Das Lineal ist ein **Laufzeit-Bauteil**: `world.gd` (`build_seesaw_nodes`) setzt einen Knoten an den
Drehpunkt, lädt `game/assets/props/kinder_lineal.glb` und kippt ihn mit dem Simulationszustand. Das Diorama liefert alles darum herum:

- **Lineal-Modell** `tools/make_kids_ruler.py` (Blender: `powershell -File tools/blender.ps1 tools/make_kids_ruler.py`) → `kinder_lineal.glb`, normiert wie
  im Bauplan A5 (1 m längs +x = Ausfahrt, Oberseite y 0, Breite 1 m; das Spiel skaliert auf 24 x 0,3 x 4 m), gebaut in den Maßen der Streckendatei:
  Buche, Oberseite mit Zentimeterskala 0 bis 60 (Millimeterstriche an der Südkante, Zentimeter an der Nordkante), Ziffern von oben lesbar (in der Übersicht
  liegt 0 im Westen = Ausfahrtsende), Aufdruck „TOY BOX · 60 cm“; rote Endkappen (2,5 cm über dem Deck), rot-weiß schraffierte Stirn am Einfahrtsende (sie
  wird für Nachfolger zur Kante), Fase 0,14 m an der Unterseite beider Enden (das tiefe Ende liegt in Ruhelage plan), rote Knetkugel als Gegengewicht an der
  Südkante des Einfahrtsendes. Seidenmatter Lack (Rauigkeit 0,78, wenig Glanz). 296 Dreiecke. Texturen `lineal_wippe_oben.jpg` (3072 x 512) und
  `lineal_wippe_teile.png` aus `make_kids_textures.py lineal_wippe`.
- **Filzstift** (`build_pen`, gebacken mit Umgebungsverdeckung): grün, 7 m lang quer unter dem Drehpunkt, Durchmesser 0,89 m (seit 03.10.2026, vorher 0,72 m),
  damit er auf dem Parkett liegt (0,08) und seine Oberkante (0,97) genau die Unterseite des Lineals am Drehpunkt trägt (das Lineal liegt wie jede Fahrbahn
  0,17 m über der Simulationshöhe, `K_SEESAW_LIFT` = `world.gd SEESAW_LIFT`; die Collider der Stiftenden sind 0,9 m breit); Schaft mit Etikett, Griffzone, weißer Konus,
  Filzspitze (Norden), aufgesteckte Kappe mit Clip (Süden). Die Hindernisse sind die zwei Collider der Streckendatei an den Stiftenden.
- **Straßen-Spielteppich** (`build_road_mat`, Bodenauflage mit AO): graue Filzbahn 4,9 m breit unter der ganzen Abkürzung (die dunkle Laufzeit-Fahrbahn,
  4 m, liegt mittig darauf), weiße Randlinien knapp außerhalb der Fahrbahn (nicht unter dem Lineal), helle Steppnaht am Rand. So liest sich die Abkürzung
  als Spielzeugstraße und nicht als Asphaltband im Kinderzimmer.
- **Abrieb**: aufgeraute hellere Filzflecken neben den Linealenden und feine helle Kratzer im Parkett dahinter (das Lineal ist so breit wie die Fahrbahn,
  unter seinen Enden liegt die Laufzeit-Fahrbahn).
- **Korridor**: kein Spielzeug näher als 3,5 m an der Pfadmitte (`reserve_shortcut`, Rechtecke je Pfadstück); die Ruhelage des Lineals wirft beim Backen
  einen Kontaktschatten (`ruler_ao`, schräge Platte als AO-Stellvertreter).
- Prüfung: `test_diorama` kids besteht (0 Verstöße im Fahrschlauch der Abkürzung; die beiden Stift-Collider meldet der Test als `WARN`, sie gehören zur
  Streckendatei), `test_field` kids alle Stufen mit und ohne Spieler auf dem Lineal.

## Was gebaut ist (Stand 02.10.2026, weiter gültig)

- **Straße `runtime`** (orange Spielzeugbahn, Rampe, Lücke, Looping baut das Spiel), Boden auf 0,08.
- **Parkett**: einzelne Dielen (3 m x 24 m) aus einem Atlas mit acht Holztönen, je Diele zufällig gespiegelt, versetzte Stöße je Spalte (`floor_rect`).
- **Spielteppich** unter einem Teil der Bahn (78 x 54 m, 6° gedreht): dunkelblaue Wolle mit Sternen, Monden, Wölkchen, cremefarbener und roter Streifen, Fransen.
- **Raum**: vier Wände (Tapete, leicht nach außen gekippt), weiße Fußleisten mit Hindernis rundum.
- **Möbel**: Spielzeugregal an der Südwand mit **Lichterkette** (15 Birnen auf der Vorderkante, Kabel; jede zweite beleuchtet den Boden), Bettecke in der Nordostecke
  (Kopfteil im Süden, zwei Kissen, Stofftier am Fußende, Gestell in hellem Holz) mit Nachttisch, Wecker und **Nachttischlampe**, Spielzeugtruhe „TOY BOX“ in der
  Nordwestecke, **Mondlampe** (warm leuchtende Kugel auf Holzfuß) an der Westwand.
- **Licht (nachts, alle echte Lichtquellen über `add_light`, 16 Einträge)**:
  - Nachttischlampe in 12,2 m Höhe, warm (1,0 / 0,8 / 0,5), Stärke 1,0, Reichweite 66 m, mit echtem Punktlicht und Fleck: erhellt die Osthälfte; die Lampe liegt
    seit dieser Politur unterhalb der Titelleiste (Nachttisch bei -36,5, Lampe bei -34,9) und ist in der Übersicht zu sehen;
  - **Mondlicht** durch das Westfenster: sechs helle Dielenfelder (zwei Spalten, drei Reihen, Sprossenkreuz) bei x -84 bis -68 und z -27 bis -3; nachts je Feld ein
    kühles Punktlicht (0,55 / 0,72 / 1,0, Stärke 0,68, Reichweite 10 m): der Fleck ist deutlich heller und bläulich;
  - Mondlampe bei -83 | 19 (warm, Stärke 0,55, Reichweite 26 m), Lichterkette am Regal (pastellfarben, 0,22, Reichweite 8,5 m).
- **Spielsachen** (alle als Körper mit Hindernis, erkennbare Alltagsdinge): **Bauklotzburg** (vier Türme mit Kegeldächern, Zinnenmauern, Torbogen, Bergfried, Fahne),
  **Puppenhaus** (zwei Stockwerke, Satteldach, Schornstein, Fenster mit Vorhängen, Tür, Balkon), **Brettspiel** (Mensch ärgere dich nicht) mit Spielfiguren, angefangenes
  **Puzzle** mit losen Teilen, **Teeparty** auf rundem rosa Teppich (Kanne, Tassen, Untertassen, Plüschhase, Badeente), Spielwürfel mit Augen, Spielkarten (Rücken, Herz-Ass,
  Pik-König), aufgeschlagenes Heft mit Kritzelei, Stickerbogen, Bilderbuch-Stapel, Papierflieger, Steckfiguren, Plastik-Dinosaurier, Plüschhase, Blechroboter,
  **Bagger** und **Kipplaster**, Spielautos aus dem Autobausatz, Hausschuhe, dazu Bausteine, Murmeln und Buntstifte wie zuvor. Die flach liegenden Dinge (Karte, Heft,
  Sticker, Puzzle) liegen im Atlas `spiel.jpg` (4 x 4 Felder, `make_kids_textures.py spiel`).
- **Orte werden gesucht**: `spot()`, `near_or_search()` und die Kandidatenlisten in `paper_and_ruler()` suchen freie Stellen (Fahrschlauch bleibt frei, nichts überlappt).
  Die früher verworfenen Stücke (Zeichnung, Lineal, Radiergummi, mehrere Steine, Murmeln, Stifte) stehen jetzt an gültigen Orten; wo nichts frei ist, meldet das
  Blender-Protokoll „keine freie Stelle für …“.
- **Sandkasten-Malheur** (neu, Abschnitt „Sandkasten-Malheur“ in `kids.py`): Die Streckendatei hat einen langsamen Belag (`surfaces`: von 0,36 bis 0,46, Seite `inner`, Art `dirt`).
  Das Spiel zeichnet dafür zur Laufzeit nur einen 0,85 m breiten Streifen auf 0,13 m (rote Themenfarbe, `road_strip` in `world.gd`) – derselbe Wert wie die Oberkante des
  Teppichs, der Streifen ging im Diorama also verloren. Im Diorama liegt dort jetzt umgekippter Spielsand: ein **gelbes Sandkasten-Eimerchen** (roter Rand, auf der Seite,
  Mündung zur Bahn, Sand in der Mündung) neben dem Anfang der Zone, aus dem eine **ausgefranste Sandfläche** über den Teppich bis an den Randstein geflossen ist (Material `D_Sand`
  mit Sandtextur und Normalkarte): Die Fläche deckt die ganze Zone (Abstand 3,5 m bis zu einem unregelmäßigen Rand bei 5,4 bis 7,2 m, also 1,5 bis 3 m neben dem Randstein) und läuft
  vor ihr als Fächer vom Eimer aus. Dazu **drei Sandhaufen** mit aufgesetzter Kuppe, eine **blaue Schaufel mit orangem Stiel**, eine **Sandburg** (drei Türme mit Zinnenkranz, rotes
  Fähnchen) am Ende der Zone und rund 3 200 verstreute Sandkörner (Dreieckchen in vier Sandtönen, nach außen dünner). Die Fläche ist ein Gitternetz (0,5 m), dessen Höhe
  stetig vom Sandfeld abhängt (4 mm bis 2 cm über dem Teppich, höchstens 0,152 m, die Fahrbahn liegt bei 0,17 m): Die Schnittlinie mit dem Teppich ist der weiche, unregelmäßige
  Rand. Wie der Wegsaum im Wald liegt sie nicht in `objs_ground`; sie ist beim Backen unsichtbar (`theme_bake_hidden`: Präfix `Sand`) und liest über eine eigene Licht-UV die
  Verdeckung des Teppichs darunter (Eimer, Haufen und Burg werfen so Kontaktschatten in den Sand). Spielzeug darf nicht auf den Sand (`keep_out` entlang der Zone).
  **Der Laufzeitstreifen bleibt im Spiel bestehen** (einfache Grafikstufe, ohne Diorama) und liegt im Diorama unter dem Sand (der Sand liegt 4 mm höher); sichtbar bleibt er
  nicht – ein roter Streifen neben dem rot-weißen Randstein wäre ohnehin leicht mit diesem zu verwechseln.
  Hindernisse: Eimer (Rechteck, weich), Burg (Kreis, weich), beide mehr als 6 m von der Mittellinie.
- **Fensterlicht**: das Westfenster (früher Nordfenster unter der Titelleiste); Zeichnung, Lineal und Radiergummi liegen im Lichtfleck.
- **Laufzeit-Bauteile** (Teddy, Ball, Bauklötze, Bausteinturm, Bücher, Buntstiftkasten, Holzeisenbahn, Kreisel) bleiben Laufzeit; `kids_ao()` backt ihre
  Kontaktschatten (Maße aus den Modellen).
- **Hindernisse**: 106 gebackene (Wände, Regal, Bett, Truhe, Burg, Puppenhaus, Spielsachen, Steine, Murmeln, Stifte); Lichtblocker-Polygone für Burg (7,5 m) und
  Puppenhaus (15 m), der Rest des Zimmers ohne (das Regal blockiert nicht mehr, damit die Lichterkette die Boden- und Regalfläche erreicht).
- Tests: `test_diorama` für kids besteht (Stand 02.10.2026 abends: 122 Hindernisse im Spiel, 0 Verstöße im Fahrschlauch, 16 Punktlichter, 2 Lichtblocker-Polygone gültig, KI im Ziel ohne Stoß).
- Flächen: das Zimmernetz hat jetzt 9 200 Flächen (vorher 7 200; +2 000 für Körner, Haufen, Eimer, Schaufel und Burg), dazu das Sandnetz mit 1 000 Dreiecken; insgesamt weiterhin sehr leicht.

## Entscheidungen

- Kein Fremdmaterial: Alles aus `make_kids_textures.py` und der Geometrie in `kids.py`; keine Bildvorlagen aus `Videos/` oder `audio/Vorschläge`.
- Wände kippen nach außen (Lean 0,47 bis 0,85) statt senkrecht, weil die Draufsicht sonst ein Stück Wand vor dem Boden zeigt.
- Das Bett liegt mit dem Kopfende im Süden (Kopfteil, Kissen): So steht die Nachttischlampe im sichtbaren Teil der Übersicht, und das Zimmer bekommt trotzdem
  seine warme Lichtquelle von Osten; die Mondlampe und das Mondlicht stehen im Westen im Bild.
- Gestell und Kopfteil des Bettes in hellem Holz: dunkles Holz bleibt im Lampenlicht schwarz.
- Kern-Eigenheit Vertexfarbe: `fix_vertex_colors` in `theme_layout` ist seit dem Kern-Update überflüssig, bleibt aber verträglich.

## Offene Punkte

- ~~Lineal sitzt 0,17 m zu tief~~ behoben am 03.10.2026: `world.gd` setzt den Wippenknoten auf `pivot_h` + Gelände + `SEESAW_LIFT` (0,17), Autos stehen
  wie auf jeder Fahrbahn 3 cm über der Oberseite; der Laufzeitstreifen der Abkürzung spart die Grundfläche des Lineals aus, das tiefe Einfahrtsende mit
  rot-weißer Kante liegt in Ruhelage sichtbar auf Fahrbahnhöhe. Stift und Kontaktschatten (`ruler_ao`) folgen der Anhebung.
- Die Wippe liegt in der Rennkamera am oberen Bildrand knapp unter der HUD-Leiste, das Kippen sieht man nur schräg (Kameraführung, nicht geändert).
- Eine Ampel am Wippenabzweig (`kinder_ampel.glb`, P3) ist nicht gebaut.

- Das Lampenlicht der Lichtkarte wirkt auf senkrechten Flächen nur bis etwa 9 m Höhe (`lit_overlay.gdshader`: `reach = 1 - smoothstep(3, 9, height)`, auf die Stadt
  zugeschnitten). Im Kinderzimmer sind Möbel höher (Regal 14 m, Bett 11,6 m, Puppenhaus 10,5 m): Ihre Oberseiten und oberen Wandteile bleiben nachts dunkel. Siehe
  Änderungswünsche an den Kern.
- Ein Bildschirmschein (Tablet) oder ein weiteres Nachtlicht ist nicht gebaut; die Titelleiste deckt die Nordstreifen (Burg, Puppenhaus, Puzzle, Brettspiel) in der
  Übersicht ab, im Rennen sind sie voll sichtbar.
- Der Plastik-Dinosaurier sieht von oben wie ein Krokodil aus (Quader-Körper); ein stärkerer Kopf mit Zähnen wäre eine spätere Verbesserung.
- Einzelne Papierflieger und Bücherstapel haben keinen freien Platz gefunden (siehe Protokoll); das ist gewollt so, kein Fehler.
