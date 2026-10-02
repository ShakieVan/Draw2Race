# Diorama Harbour Run (Thema `harbor`, Stand 02.10.2026, Politur)

Modul: `tools/dio_themes/harbor.py` (gemeinsam mit der Drift Arena, siehe `arena.md`), Texturen: `tools/make_harbor_textures.py` →
`game/assets/dio/harbor/`, Vorschau ohne Blender: `tools/make_harbor_preview.py`. Bauen: `tools/dio_build.ps1 -Track harbor -Shots -Times day,dusk,night -Tag _x`.

## Geschichte des Ortes

Ein arbeitender Containerhafen an der Kaikante: Die Kräne laufen auf zwei Schienen parallel zur Kaimauer, davor liegt der Frachter im Hafenwasser,
dahinter stehen die Container in Blöcken mit Gassen, Sattelzüge, Reach Stacker und Portalhubwagen bewegen sich zwischen den Blöcken, im Süden stehen
eine Lagerhalle, ein Bürogebäude, ein Tank, im Osten liegt ein Gleisanschluss mit Rangierlok und Containertragwagen. Die Lücke der Straße ist ein
**Hafenbecken** (Schlepper liegt darin); die Holzschanze springt über das Wasser. Straßenart `runtime`: Fahrbahn, Randsteine, Rampe, Lücke und
Abkürzung baut das Spiel wie ohne Diorama; der Boden des Dioramas liegt bei 0,08 m und überdeckt nichts.

## Boden

- Netz in drei Stufen (1, 2, 4 m) mit Verschmelzung der Übergänge (keine T-Kreuzungen); Bereich um Kai, Becken und Fahrbahn (15 m) in 1-m-Zellen.
- Material `D_Gelaende` (Boden-Shader `ground_blend.gdshader`) mit **eigenen** Texturen: Beton (Platten 4 x 4 m mit Fugen, Rissen), Asphalt
  (Fugen, Körnung aus Asphalt031), Verschleiß (öliger Belag mit Reifenabrieb, Rost, Splitt). Die Gewichte stehen in der Vertexfarbe
  (R Plattenhelligkeit, G Asphalt, B Verschleiß, Funktion `hb_fields`): Beton unter den Containerblöcken, am Kai und als Streifen an der Fahrbahn,
  dazwischen Asphalt.
- **Belagsflicken** (`hb_plan_patches`, seit 02.10.2026): statt der früheren Rauschflecken (sie wirkten wie große schwarze Ölseen mit ausgefranstem Rand)
  setzt das Thema Rechtecke an den Plattenfugen: Asphalt im Beton (halbe und ganze Platten, dazu 2 m breite Sägeschnitt-Streifen) und einzelne neue
  Betonplatten im Asphalt. Die Kanten liegen auf ganzen Metern; die Zelle bekommt die Gewichte als Ganzes (die Vertexfarbe gilt je Dreieckseckpunkt, das Netz
  verschweißt nichts), die Kante ist deshalb scharf wie bei einem echten Flicken. Der Verschleiß-Belag (B) bleibt schwach und weich: Radspur zwischen den
  Kranschienen nur dort, wo die Schienen liegen (früher lief das Band über das Schienenende hinaus und bildete einen schwarzen Fleck), Reifenstaub am Rand,
  Gummi an den Kurven. Ölflecken stehen nur noch in der Lichttextur (weich, `hb_plan_oil`).
- **Lichttextur** (gebackene Umgebungsverdeckung): Containerstapel, Hallen, Fahrzeuge und die Stellvertreter der Laufzeit-Bausteine (`ao_proxies`)
  werfen Kontaktschatten. Zusätzlich wird nach dem Backen (Hook `theme_layout`, `hb_paint_ao`) in die Lichttextur multipliziert: Radspuren in
  den Gassen, Ölflecken, Gummi am Auslauf der Kurven. Die Laufzeit-Fahrbahn liest die Lichttextur nicht.
- Rund um das Gelände liegt eine weite Asphaltfläche (`Weite_gelaende`, gleicher Shader, ohne Lichttextur); im Norden endet das Land an der Kaikante.

## Kai, Wasser, Kran

- **Kaimauer** aus Beton (Concrete034) mit Feuchteverlauf zur Wasserlinie, Kantenstein, gelbe Sicherheitslinie, Fender (Gummi) am Liegeplatz,
  Festmacherleinen von den Pollern der Streckendatei zum Schiff (Aufhängehöhe aus dem Modell). **Rettungsstationen** (zwei, x = -15 und 18, zwischen den
  Kränen und mit Abstand zu den Pollern): roter Schrank mit weißem Kreuz plus Rettungsringständer (Pfosten, rot-weißer Ring, beidseitig). Sie standen vorher
  auf dem seeseitigen Warnstreifen der Kranbahn und neben einem Poller; jetzt liegen sie zwischen Kaikante und Warnstreifen.
- **Hafenwasser**: eigenes Netz (`D_Wasser`, Flachwasser-Shader über `water_nodes`), Tiefenwert in der Vertexfarbe: dunkel an der Mauer, heller draußen,
  Schaumsaum um den Rumpf. Der Umriss des Frachters wird aus dem KI-Modell berechnet (Wasserlinie nach der Anpassung von `world.gd`).
- **Kranbahn**: Die Schienen folgen den Maßen des Kranmodells (`hafen_kran`: seeseitige Räder bei z = -37,4, landseitige Füße bei z = -30,7). Die
  seeseitige Schiene liegt im Boden auf Schwellen mit gelb-schwarzen Warnstreifen; die landseitigen Füße des KI-Modells hängen 0,78 m über dem Boden,
  deshalb läuft die landseitige Schiene auf einem Betonbalken (0,62 m hoch, festes Hindernis). Prellböcke an den Enden. Nahansichten: Kranfüße stehen
  mit allen drei Rädern auf der Schiene, die Räder laufen längs der Schiene.
- **Kranscheinwerfer** (neu): je Kran zwei Arbeitsscheinwerfer an den seeseitigen Beinen (`add_light`, 9 m hoch, warmweiß, Reichweite 14 m, kleiner
  Leuchtfleck am Kopf). Das KI-Modell hat keine Lampen; der Fleck steht für den Scheinwerferkopf, das Licht beleuchtet Kai und Schiffsdeck.

## Hafenbecken an der Lücke

Rechteck mit ganzzahligen Kanten (x -37..-29, z 18..46) ausgeschnitten, Mauern bis unter die Meeresfläche, Kantenstein, gelbe Linie, Geländer (gelb,
weiches Hindernis), Poller, Steigleitern, Hafenschlepper (Rumpf mit Bordwand, Deckshaus, Brücke, Schornstein, Fender, Schubknie), vor dem Becken
Absperrschranken (Kern-Bauteil `barrier_segment`, wie die Baustellenschranken der Stadt). Die Rampe endet an der Beckenkante, die Landestelle
hängt 0,5 m über dem Wasser.

## Container, Fahrzeuge, Gebäude

- Containerfelder (`hb_plan_field`): Raster aus Reihen und Buchten, Gassen quer und längs, Stapelhöhe folgt einem Rauschfeld, 20- und 40-Fuß-Container,
  Farben aus einer Palette, Wellblechtextur mit Normalkarte, Türseite mit Verriegelungen und Nummer, Dach mit Rost. Die Seitentextur trägt Rostläufer
  vom Dachrand, Rostpunkte und einen Rostsaum unten (vier Varianten, `hb_cont_v`). Jeder Stapel wird vor dem Setzen
  gegen die belegten Flächen und den Fahrschlauch geprüft und ist ein festes Hindernis.
- Leere Buchten tragen weiße Eckwinkel, Gassen gestrichelte Mittellinien, Pfeile und Blocknummern (Siebensegment-Schablone), Verkehrszeichen
  (Tempo 20, Vorfahrt gewähren, Einbahnstraße).
- **Fahrzeuglack** (neu): Das Material `D_Lack` trägt eine eigene Verwitterungstextur (`src/lack.png`: Regenschlieren, Staubsaum, ausgebleichte Stellen,
  Rostpunkte und -läufer, Mittel sRGB 0,91 = die frühere Helligkeit) und wird mit der Vertexfarbe des Fahrzeugs multipliziert. Lkw, Lok, Wagen, Stapler,
  Schlepper, Teamfahrzeuge und Zelte der Arena zeigen dadurch Alterungsspuren statt Einheitsfarbe.
- Sattelzüge mit Containerchassis, Reach Stacker mit 20-Fuß-Container (Kotflügel, Gegengewicht mit Warnstreifen, Auspuff, Scheinwerfer), Portalhubwagen,
  parkende Pkw (Bausatz `kit_car`), Fässer, Reifenstapel, Paletten, Leitkegel. Räder rollen in Fahrtrichtung. **Dreiecke je Rad** (`hb_wheel`): acht statt zehn
  Seiten, Zwillingsreifen ohne Nabe (von oben nicht zu sehen), Nabe nur an einzelnen Rädern und an den großen Staplerrädern.
- Lagerhalle mit Trapezblech, Satteldach, Lichtbändern, Verladetoren, Vordach und Nummern; kleine Halle; Bürogebäude (Bausatz `kit_house`, Stil Büro);
  Lagertank mit Auffangwanne; Zaun mit Gewebeplane am Rand.
- Gleisanschluss (x = 80,5): Schotterbett, Betonschwellen, Schienen, Prellböcke, Rangierlok, drei Containertragwagen.
- Startportal als Ausleger (ein Pylon, der Kranbalken verbietet den zweiten).

## Laternen, Lichter und Nacht

Die Laternen der Streckendatei entfallen (`baked: ["lamp"]`, zwei standen auf der Abkürzung). Eigene Laternen werden mit
`add_lamp(…, model="hafen_laterne")` eingetragen (alle 14 m neben der Fahrbahn und an der Kaikante zwischen den Kränen); das Spiel baut sie als
Laufzeit-Bauteile samt Licht und übernimmt das Modell. Echte Lichtquellen (`add_light`): Flutlichtmasten im Hof (sechs, in den Gassen der Felder, 14,5 m hoch,
Strahler zur Hofmitte), Torleuchten über den Hallentoren, die Kranscheinwerfer. Nichts im Diorama leuchtet selbst: Materialien ohne Emission; nur die
Warnleuchten der Absperrschranken und das Startportal-Banner gehören zu den Kernbauteilen (echte Leuchten).

## Spielebene

Hindernisse aus dem Diorama (Stapel, Fahrzeuge, Gebäude, Zaun, Poller, Zeichen, Kranbalken ...) werden aus `HbTrack` geprüft, das die Mittellinie wie
`track.gd` aufbaut (Catmull-Rom, Breitenprofil, Rampen-/Lückenzonen mit Zuschlag, Abkürzungspfade) und dieselbe Abstandsrechnung wie
`tests/test_diorama.gd` verwendet; Mindestabstand zum Fahrschlauch 1,0 m, Containerblöcke 2,6 m. Neu in dieser Politur: nur Rettungsstationen
(verschoben, Kreishindernis wie zuvor) und der Ringständer (Pfosten ohne Hindernis, weit vom Fahrschlauch).

## Kontrolle (Nahansichten)

Eigenes Aufnahmeskript (Scratchpad, nicht im Projekt): beliebige Ansichten über `VIEWS="name,x,z,zoom,neigung;…"`, Bedienoberfläche ausgeblendet. Geprüft in
Tag, Dämmerung und Nacht: Kranbahn und Kranfüße, Kai mit Station, Becken mit Schlepper, Lagerhalle, Büro, Gleisanschluss mit Lok und Wagen, Lkw, Stapler,
Portalhubwagen. Triangles (ohne KI-Modelle der Laufzeit): Harbour Run etwa 70 000 (Boden 36 000), Drift Arena etwa 59 000.

## Offene Punkte / Hinweise

- Die Abkürzung zeichnet das Spiel schwarz (`world.gd build_shortcuts`); das ist unabhängig vom Diorama (auch ohne Diorama so).
- Der Kran (KI-Modell) hat keine Lampen; die Scheinwerfer sind reine Lichtquellen mit Leuchtfleck.
- Mobile Grafik: Die Containerfelder könnten für schwache Geräte ausgedünnt werden; der Boden (36 000 Dreiecke) ließe sich mit gröberen Zellen außerhalb der
  Flicken verkleinern.
