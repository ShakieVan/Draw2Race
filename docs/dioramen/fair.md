# Diorama Fun Fair Eight (`fair`)

Stand 02.10.2026 (Politur nach der ersten Fassung). Modul: `tools/dio_themes/fair.py` (gemeinsame Geometrie: `tools/make_fair_kids_geom.py`), Texturen:
`tools/make_fair_textures.py` → `game/assets/dio/fair/` (Herkunft dort in `HERKUNFT.md`). Bauen: `tools\dio_build.ps1 -Track fair -Shots -Times day,dusk,night -Tag _x`.
Der Jahrmarkt ist der Nachtbild-Vorzeigefall: bunte Lichter sind die Lichtquellen, alles andere wird von ihnen beleuchtet.

## Was gebaut ist

- **Straße `runtime`**, Boden auf 0,08. Unter Rampe und Lücke lässt `stunt_cells()` die Bodenkacheln stehen (dort fehlt die Laufzeit-Fahrbahn).
- **Boden** als Geländenetz `D_Gelaende` (1-m-/2-m-/4-m-Kacheln je nach Nähe zur Strecke), Vertexfarbe R Helligkeit, G Sägemehl, B festgetretene Erde.
  Rasen abgetreten (`gras_getreten`), Sägemehl/Hackschnitzel (`saegespaene`) in Gassen, Wartezone und Biergarten, Erde um die Fahrgeschäfte, Wirtschaftshof
  und Parkplätze; weiche Übergänge über den Boden-Shader. Eingangsplatz mit Pflaster (`Boden_pflaster`, PavingStones142 aus `art/texturen`). Die weite
  Wiese außerhalb (`D_Wiese`) ist über `tints` auf den Farbton des Bodens gebracht (vorher dunkler Rand an den Ecken).
- **Fressmeile und Spielstraße** in den Tälern der Acht: je sechs Buden mit Brettern, Sockel, Seitenfeldern, Ausgabeöffnung, Theke, gestreifter Markise mit
  Zackenvolant, Schild (Atlas, Text lesbar von oben), Dachform je Bude, Zusatz je Typ. Gasse mit Sägemehl, Girlanden, Kabeln, Verteilerkästen.
- **Eingang**: Holzzaun um den Festplatz, Tor mit Pfeilern, A-Rahmen-Schild „EINLASS“, Drehkreuzen, Kassenbuden, Warteschlange, Fahnenmasten; Platz mit
  Brunnen, Beeten, Bänken, Ständen, Ballonhändler, Lichterketten und **Hüpfburg** (6 x 5 m: Bodenwulst, Wülste in vier Farben, Ecktürme mit Kegeldach,
  Eingang, Gebläse; Kinder springen darin, Eltern warten davor). Sie wird vor Beeten und Bänken gebaut, damit der Platz nicht belegt ist.
- **Schleifeninnenräume**: Riesenrad mit Kasse, Warteschlange (zehn Personen) hinter Gittern; **Karussell mit rundem Holzpodest** (Planken, Kantenbrett,
  Eingangspodest zur Kasse hin), Zaun als Bogen mit Eingang, Wartende am Eingang, Gäste im Podest, Familien am Zaun; Kinderkarussell, Biergarten, Buden.
- **Hinterhof (Westen)**: zwei Reihen Wohnwagen (Räder in Fahrtrichtung, ein Teil mit leuchtenden Fenstern und Licht an der Tür), Campingtische mit Klappstühlen
  und Grill in den Lücken, Aggregat-LKW und Kofferwagen, Container, Toiletten, Müllcontainer, Paletten; **neu**: Tieflader mit Fahrgeschäftsteilen (Traversen,
  Gondelschalen), Ersatzgondeln des Riesenrads auf Paletten, Mulde mit Bauschutt, Sattelauflieger an der Nordkante, abgedeckte Stapel (Plane, Spanngurte),
  Getränkekisten, Wassertanks (IBC). Baumring außerhalb des Zauns.
- **Parkplätze** (Nord/Süd, 63 Autos aus `kit_car`) ordentlich in Reihen eingewiesen (Winkel ±4°, kaum Lücken); Einweiser in orangefarbenen Warnwesten, Leitkegel
  an den Einfahrten, Besucher in den Gassen zwischen den Reihen.
- **Besucher als Figuren** (statt der Texturstreifen `E_menge`): `human()` baut je Person etwa 60 Dreiecke (Hose, Oberteil, Arme, Kopf mit Haarkappe, manchmal Mütze;
  Kinder kleiner mit größerem Kopf, sitzende Gäste auf Bänken und Klappstühlen), dazu Kinder mit Luftballons (`kid_balloons`) und Kinderwagen (`stroller`). Alle
  Personen werden vorgemerkt (`person`, `people`, `queue_line`, `family`) und erst in `flush_people()` gebaut: nicht in Aufbauten (`in_placed`), nicht auf der
  Fahrbahn (HW + 0,9 m), höchstens 560 (gleichmäßig ausgedünnt). Ergebnis: rund 590 Besucher (Gassen der Täler, Eingangsplatz, Wartende an Riesenrad/Karussell/
  Autoscooter/Tor, Familien in den Schleifen, Zuschauer hinter den Gittern an den Außenbögen, Biergärten, Parkplätze, Hof).
- **Lichter** (alles Nachtlicht kommt aus echten Quellen, `add_light` in der Begleitdatei, 173 Einträge, höchstens vier mit echtem Punktlicht `omni`):
  - jede Bude ein bis zwei Lichter vor der Markise, Farbe je Sorte (Pommes warm, Zuckerwatte rosa, Eis hellblau, Losbude violett, Schießbude grün ...), Stärke 0,26 bis 0,34;
  - Girlanden alle 2,6 m ein Licht (Warmweiß, Rosa, Hellblau, Gelb, Grün), Stärke 0,17;
  - Riesenrad: 16 Lichter auf der Felge (Radius 8,4 um die Nabe in 9,4 m, acht davon leuchten den Boden an, alle mit leuchtendem Fleck) und ein Punktlicht an der
    Nabe; Karussell: Kranz aus zwölf Lichtern am Dachrand plus Krone; Autoscooter: sechs Dachkanten (Cyan/Magenta); Festzelt: Kranz in Gelb/Rot, Mastspitze;
    Kinderkarussell: sechs Pastelllichter; Brunnen: Unterwasserlicht in Cyan; Tor: drei Lichter am Querbalken; Hüpfburg, Buden und Losbuden der Streckendatei;
  - **Lichtmasten der Streckendatei** (`lamp`, `baked: ["lamp"]`): als Mast mit Tellerring und Birnenkranz im Diorama gebaut (Hindernis `mast`), Licht in
    Warm-, Neutral- und Rosaweiß (0,6, Reichweite 12,5 m) statt des gelben Laternenscheins des Spiels;
  - Wohnwagen: warmes Fensterlicht und Schein vor der Tür.
  Die Parklaternen des Spiels (`lamps`, gelb) sind von 45 auf 15 gesunken und stehen nur noch an Parkplätzen, Eingangsplatz und Hof; die Gassen der Täler,
  die Fahrgeschäfte und die Taschen werden von den Buden- und Fahrgeschäftslichtern beleuchtet.
- **Laufzeit-Bauteile** (Riesenrad, Karussell, Autoscooter, Zelt, Buden, Losbuden) bleiben Laufzeit; `fair_ao()` backt ihre Kontaktschatten mit den im Modell
  gemessenen Grundflächen (`PROP_FOOT`).
- **Hindernisse**: 481 gebackene Hindernisse (Buden, Zaun, Gitter, Wohnwagen, LKW, Autos, Masten, Bäume, Tieflader, Hüpfburg ...); Abstand zur Fahrbahn mindestens
  `HW + 2,5 m` für Aufbauten (`try_place`). Kleinteile ohne Hindernis: Besucher, Figuren, Stühle, Leitkegel.
- Tests: `test_diorama` für fair besteht (506 Hindernisse mit den Laufzeit-Bauteilen, 0 Verstöße im Fahrschlauch, 173 Punktlichter gültig, KI im Ziel ohne Stoß).
- Dreiecke: etwa 131 500 (Boden 29 000, `Fair_k_farbe` 82 500 davon rund 35 000 Besucher, Glühbirnen 9 000; Bäume als MultiMesh über `Prop_*`); `fair.glb` 21 MB.

## Entscheidungen

- Bodentexturen über `ground_set` in `assets/dio/fair/` statt Blender-Material: weiche Übergänge und Laternenlicht kommen vom Boden-Shader.
- Besucher als echte Figuren statt Streifentextur: vom Rennwinkel (72 Grad) sind Streifen Raupen; kleine Figuren mit Schatten lesen sich als Menschen.
  Sie sind Dekor ohne Hindernis (wie bisher die Streifen); die einfache Grafikstufe zeigt sie nicht.
- Die Lichtmasten selbst zu bauen (`baked: ["lamp"]`) ist der einzige Weg, ihren Lichtfarbton zu ändern: das Spiel setzt Laternenlicht immer in Gelb.
- Leuchtende Flecken ohne Boden-Wirkung sind `add_light`-Einträge mit Stärke 0 (nur `glow`): Felgenbirnen des Riesenrads, jede zweite am Karussell.
- Die Wiesenbänder nördlich und südlich der Täler (z jenseits ±36 m) sind frei geblieben: Die Kamera folgt der Strecke (z-Bereich ±21,5 m plus Sicht), die
  Übersicht deckt dort Titel- und Fußleiste; zusätzliche Aufbauten wären nie im Bild (freie Flächen per Raster über die Hindernisse der Begleitdatei geprüft).

## Offene Punkte

- Der Tellerring der Lichtmasten verdeckt die Birnen von oben (sie hängen darunter, Höhe 6,05 m, der Teller liegt bei 6,15 m); in der Draufsicht sieht der Mast wie
  ein grauer Teller aus. Besserung: Birnen auf Höhe 6,2 m am Rand (Radius 1,05 m) oder Teller kleiner. Ohne weiteren Bauversuch (Grenze von sechs Läufen erreicht).
- Nacht nur objektiv geprüft (Bilder); Gerätetest auf dem Handy steht aus: 173 Punktlichter kosten beim Laden Zeit in `Atmosphere.bake_rain_lights`
  (geschätzt unter 1 s auf dem PC, auf dem Handy mehr).
- Zwei Orte der ersten Planung ohne Treffer: Sonnenschirm bei -39 | -8,5 und der dritte Tieflader bei -97 | 24 (belegt).
- Das Riesenrad, das Karussell, der Autoscooter und das Zelt sind die vorhandenen KI-Modelle (unverändert); ihre Lichter sind Punktlichter und Flecken, keine
  Leuchtflächen am Modell.

## Nachtrag 03.10.2026 (Höhen-Paket, C3)

- Streckendatei und Diorama unverändert (kein Neubau). Kontrolle nach den Änderungen am Fahrbahn-Shader: Tag, Nacht und Regen (`dio_shot.gd`, Tag `_c3w1`/`_c3w2`, `AT` 0,192)
  ohne Fehler, Pfützen und Spiegelung wie vorher.
- **Nutzungsspuren:** `game/assets/wear/fair.png` (120 × 1258 px, README Abschnitt 9): Gummistriche vor den Haarnadeln, Politur der Ideallinie; Schanze (s 0,387, 7 m) und Lücke
  0,4093–0,4475 sind ausgespart, an der ebenen Acht-Kreuzung liegt jede Spur auf ihrem eigenen Ast (Fahrbahn-UV des Asts).
