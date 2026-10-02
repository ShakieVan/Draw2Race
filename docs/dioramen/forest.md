# Diorama Forest Eight (Thema `forest`)

Stand 02.10.2026 (nach der Überarbeitung am Nachmittag und dem Wegsaum am Abend). Modul: `tools/dio_themes/forest.py`, Texturen: `tools/make_forest_textures.py` →
`game/assets/dio/forest/` (Herkunft dort in `HERKUNFT.md`, alles prozedural). Bauen: `tools\dio_build.ps1 -Track forest -Shots -Times day,dusk,night -Tag _wald`.

## Was gebaut ist

- **Straße**: `runtime` (Schotterpiste samt Pfosten und Feldsteinen baut das Spiel, Boden bei 0,08 m). Das Modul liefert nichts auf Fahrbahnhöhe.
- **Boden**: ein Netz `Gelaende` (1-m-Raster, als Viererbaum auf bis zu 8 m große Vierecke zusammengefasst, wo Höhe und Vertexfarben ebenmäßig sind)
  mit dem Misch-Shader des Spiels. Gewichte in der Vertexfarbe: Helligkeit (großflächige Flecken plus Sonnenflecken des Blätterdachs, Abdunklung
  unter Kronen kommt aus der gebackenen Umgebungsverdeckung; in den Schlammabschnitten und an den Teichufern zusätzlich auf rund die Hälfte gedrückt: nasser, dunkler
  Waldboden), Nadelstreu (unter jeder Kiefer plus große Flecken), Erde (Wegsaum, festgetretene Höfe von Hütte, Tribüne und Zeitnahmeturm, ein Erdweg von der
  Hüttentür zur Fahrbahn). Texturen: Waldboden (Moos, Humus, Laub, Zweige, Steinchen), Nadelstreu, **Wegerde** (`boden_erde`, seit 02.10.2026 statt des Schlamms:
  festgefahrene Erde in der Farbe der Piste mit Kieseln, grobem Schotter, Laub, Nadeln und einem Viertel dunkler feuchter Flecken). Die Gewichte sind um 0,5 verdichtet,
  damit der Übergang im Shader (Schwelle 0,42 bis 0,58) über rund einen Meter weich verläuft.
- **Wegsaum** (neu 02.10.2026, Abschnitt „Wegsaum“ in `forest.py`; Rückmeldung der Prüfung: „kein Erdsaum, keine Spurrillen, kein Laub“): Die Laufzeit-Piste ist ein ebenes Band mit
  einer 9 cm hohen harten Kante zum Waldboden. Beiderseits der Piste liegt jetzt ein 2 m breiter Saum aus zwei Netzen `Saum_L`/`Saum_R` (Material `D_Gelaende`, 9 Stationen quer,
  alle 1 m längs, 5 700 Dreiecke):
  - **Höhe**: ein flacher Wall aus festgefahrener Erde und Schotter, am Fahrbahnrand 0,147 m (die Fahrbahn liegt bei 0,17 m: die Kante schrumpft von 9 auf 2,3 cm und liest
    sich als abgerundeter Rand), fällt über rund einen Meter auf einen 2,2 cm hohen Sockel und läuft nach 2 m in den Waldboden aus; unruhige Oberfläche und stellenweise
    flache **Radspur-Rillen** (1,1 cm tief, e = 0,5 m) im Wall. Nichts reicht höher als 0,152 m (Prüfung im Modul; der Kern prüft nur `objs_ground`).
  - **Gewichte**: Erdgewicht voll am Rand, dann ein unregelmäßiger Rand bei 0,2 bis 1,3 m und 0,7 m weicher Übergang in Waldboden und Nadelstreu (Funktion `f_verge_dirt`, gilt
    auch für den Boden darunter, so gibt es am Saumrand keine Naht); der Boden-Shader bricht den Übergang mit der Textur auf.
  - **Der Saum liegt nicht in `objs_ground`.** Dort würde er seine Umgebungsverdeckung über die des Bodens darunter backen (zwei Flächen im selben Bildpunkt, der Boden darunter
    wäre vom Saum verdunkelt). Stattdessen ist er beim Backen unsichtbar (`theme_bake_hidden`: Präfix `Saum`) und hat eine zweite UV-Ebene `Licht` mit derselben Abbildung wie
    der Kern sie legt: Er liest die Verdeckung, die der Boden darunter bekommen hat (TEXCOORD_1 im glb geprüft).
  - **Kreuzung**: Jedes Viereck gehört der Strecke, der es am nächsten liegt (kein doppelter Saum, keine Fläche über der anderen Fahrbahn).
- **Matsch** (neu, `f_build_mud`, Netze `Saum_Matsch_zone0/1`, `…_ufer2`, 4 800 Dreiecke): In den beiden Schlammabschnitten und an den Teichufern liegt die frühere Schlammtextur
  (`quelle/matsch.jpg`, Material `F_Matsch`) als Gitter mit 0,6 m Zellen über dem Boden. Seine Höhe hängt stetig vom Schlammfeld ab (bei hohem Feld 4 bis 14 mm über dem Saum,
  bei niedrigem darunter): Der Rand ist die glatte, ausgefranste Schnittlinie von Matsch und Boden, kein harter Streifen. Die Laufzeit-Schlammstreifen des Spiels (0,13 m)
  liegen darüber und bleiben sichtbar, stehen jetzt aber wieder im dunklen Schlamm (mit nur dunklem Waldboden daneben stach das flache Band als graubrauner Streifen heraus). Grund für den Umbau: Der Boden-Shader hat nur drei Texturplätze
  (Waldboden, Nadelstreu, Erde); die helle Wegerde brauchte den Erdplatz, der Schlamm musste also in ein eigenes Netz.
- **Radspuren** (neu, `f_build_tracks`, `Saum_Spur_L/R`, `F_Spur`, 1 500 Dreiecke): dunklere, festgefahrene Bänder (`quelle/spur.jpg`: dieselbe Wegerde, 30 % dunkler, ohne feuchte Flecken)
  auf der Rille bei e = 0,5 m, stellenweise unterbrochen, auf der Außenseite enger Kurven breiter und häufiger. Gleiches Verfahren wie der Matsch (Höhe stetig vom Feld abhängig).
- **Kleinteile am Saum** (`f_verge_detail`): 2 200 Kiesel (fünfseitige Pyramiden, 5 Dreiecke, in Flecken und zum Rand dünner), 2 900 Blätter in sieben Herbsttönen (Rhomben, in
  Flecken und Nestern, unter Kronen dunkler), alles als vier Netze `Saum_Streu_*` je 40-m-Kachel (Material `K_farbe`, beim Backen unsichtbar), dazu 34 Steine (`f_stone`) und 44 Äste
  (`f_branch`) als `Prop_`-Netze und **34 Pfützen** (`Saum_Pfuetzen`: spiegelnde Wasserhäute 6 mm über dem Saum, Rand dunkel, Mitte hell; nicht im Matsch und nicht unter Kronen,
  dort liegen die 23 älteren Pfützen der Schlammabschnitte, die jetzt 3 cm über dem Boden liegen, damit der Matsch sie nicht deckt).
- **Bäume** (`baked`: `pine`, `oak`): selbst gebaut (verformte Kugelblasen mit Blatt- bzw. Nadeltextur, Stamm als Röhre, drei Varianten je Art). Drei Detailstufen
  je Abstand zur Strecke (`F_LOD`): nah (unter 9 m, Unterteilung 2, rund 430 bis 600 Dreiecke), mittel (bis 22 m, 220 bis 250) und fern (100 bis 160), alle ohne
  Unterseiten. Namen `Prop_*`, die das Spiel zu MultiMeshes verschmilzt. Orte, Drehung und Größe wie in der Streckendatei; Bäume, deren Krone Fahrbahn, Teich,
  Hütte, Feuerstelle, Lichtung oder ein festes Teil überdecken würde, rücken nach außen oder entfallen (199 von 268 Bäumen der Streckendatei bleiben), dazu 53 Zusatzbäume in Lücken (252 Bäume, davon 56 nah, 155 mittel, 41 fern).
  Hindernis `baum` mit den Radien aus `track.gd` (Kiefer 0,35, Eiche 0,45, mal Skalierung).
- **Teich** (`baked`: `pond`): Mulde im Boden (0,62 m), Wassernetz `Teich` mit Tiefe in der Vertexfarbe (Wasser-Shader mit Teichfarben: olivgrün flach, dunkel
  tief), Seerosen mit Blüten, Schilf mit Rohrkolben, Holzsteg auf Pfosten (Hindernis), Ruderboot mit Rudern und Bänken (Hindernis). Das Wasser hat eine dunkle
  Grundfarbe ohne Verknüpfung mit der Vertexfarbe und Grün = Blau = Rot in der Vertexfarbe: Das Laternenlicht-Zusatzbild des Spiels (`lit_overlay`) multipliziert
  beides, sonst wäre der Teich unter Lampen rot geworden. Das Glitzern bei Nacht sind Mondreflexe des Wasser-Shaders (Rauigkeit 0,08), kein Eigenleuchten.
- **Hütte und Hof** (`baked`: `cabin`, eigener Bau statt KI-Modell): Blockhütte aus Rundstämmen mit Feldsteinsockel, überstehenden Stammköpfen, Satteldach aus
  verwitterten Holzschindeln mit Moos (Vertexfarbe: Moos vor allem auf der sonnenabgewandten Seite), Schornstein aus Feldsteinen mit Tonaufsatz, Tür mit Stufe,
  Fenster mit offenen grünen Läden, Regenrinne mit Fallrohr und Regentonne, Bank, Wandlaterne. Dazu: Brennholzstapel an beiden Seiten, Hackklotz,
  Förster-Geländewagen (dunkles Waldgrün), Erdweg zur Straße. Von oben liest sich die Hütte als Schindeldach mit Schornstein, nicht mehr als dunkle Fläche.
- **Feuerstelle** (neu): Feldsteinring, Asche mit Glut, Tipi aus vier Scheiten, zwei Sitzstämme; Platz vor oder neben der Hütte (erster freier mit Abstand zu den
  Kronen). Die Flamme ist ein `K_lampe`-Netz (nachts hell), dazu eine echte Lichtquelle (`add_light`, warmes Orange).
- **Waldgerät**: Hochsitz (vier Stämme, Kabine mit Satteldach, Leiter), Holzpolter am äußeren Rand der linken Schleife (24 Stämme mit hellen Schnittflächen),
  Wegweiser (KI-Modell) im Keil der Kreuzung, Strohballen-Reihe vor der Tribüne und eine doppelte Strohwand als Kurvenschutz außen an der rechten Schleife,
  Findlinge (KI-Modell `wald_felsen`, auf 27 % der Dreiecke verkleinert, moosig), Baumstümpfe, liegende Stämme, ein Leuchtpfosten am Zuschauerplatz (Holzmast,
  Schirmlampe, Schaltkasten).
- **Unterholz** (körperlos, bis auf Büsche): Farne, Gras, Steine, Äste, Büsche (Büsche als weiches Hindernis).
- **Pfützen** (Schlammabschnitte): 23 spiegelnde Pfützen neben den Schlammabschnitten (Material mit niedriger Rauigkeit), 3 cm über dem Boden (über dem Matsch).
- **Nacht**: Nichts leuchtet von selbst. Echte Lichtquellen: die 28 Laternen der Streckendatei (Laufzeit, `lantern`) und vier Punktlichter des Moduls
  (Hüttenfenster mit Lampe im Raum, Wandlaterne an der Tür, Leuchtpfosten am Zuschauerplatz, Feuerstelle) mit Lichtblocker für die Hütte (`add_occluder_poly`).
  Die Fahrbahn zwischen den Laternen bleibt dunkel (so ist das Laternenmodell des Spiels), die Wälder wirken im Mondlicht.

## Entscheidungen

- Eigene Bäume statt der Kartenbäume des Spiels: Kontaktschatten kommen so gebacken ins Bild, und die Pipeline fasst gleiche Netze zu MultiMeshes zusammen.
  Die Baumkarten (`wald_kiefer.png`, `wald_eiche.png`) entfallen dadurch in diesem Diorama.
- Dreiecke: rund 180 000 instanziert (vorher 147 000 vor dem Wegsaum und 296 000 davor; Richtwert 100 bis 150 k), verschiedene Netze 76 000. Der Saum kostet rund 33 000: Saumnetze 5 700,
  Matsch 4 800, Radspuren 1 500, Kiesel und Blätter 16 800, Steine und Äste (Prop) und Pfützen den Rest. Das Streugut ist auf vier Kacheln verteilt (Sichtbarkeitsprüfung je Kachel), im Bild
  stehen immer nur ein bis zwei davon (rund 8 000 Dreiecke). Eingespart durch kleinere Nah-Zone (9 statt 26 m),
  Unterteilung 1 im mittleren und fernen Bereich, entfallene Kronen-Unterseiten (`drop_down`) und stärker verkleinerte Findlinge. Der Wald wirkt dabei nicht dünner:
  Zahl und Orte der Bäume sind unverändert.
- Die Kreuzung ist eben (Acht ohne Brücke): `runtime_terrain` ist aus, der Boden ist überall bei 0,08 m.
- Alle festen Zusatzteile haben Hindernisse in der Begleitdatei (rund 360); der Fahrschlauch bleibt frei (Test `test_diorama` für `forest` besteht, die KI fährt ohne
  Zusammenstoß).

## Offene Punkte

- Nicht auf einem Gerät gemessen (MultiMeshes der Bäume, Lichtkarte, Premium-Wasser, die rund 33 000 Dreiecke des Wegsaums).
- Die Fahrbahn ist die Laufzeit-Piste des Spiels (flache Schotterfarbe mit Flecken); das Diorama kann nur den Rand gestalten (Wegsaum). Spurrillen **auf** der Piste und Laub darauf
  wären nur mit Flächen über 0,17 m möglich (Regel `ground_y`: nichts über der Laufzeit-Fahrbahn); das bleibt Sache des Spiels (Fahrbahn-Shader).
- Der Saum kennt keine Gleise im Sinne der Fahrphysik: Die Radspuren sind Optik, die KI und das Fahrzeug spüren nichts.
- Der zweite Leuchtpfosten am Zuschauerplatz fand keinen freien Platz (ein Pfosten steht).
- Einfache Grafikstufe: Alle Hindernisse erscheinen als Klötzchen (Baum = Stamm plus grüner Würfel); die Dichte stimmt, Strohballen und Steg sind grau und grob.
