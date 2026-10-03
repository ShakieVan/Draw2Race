# Diorama Forest Eight (Thema `forest`)

Stand 03.10.2026 (Höhenniveaus: Hügelacht mit Holzbrücke über den Hohlweg, Bauplan `docs/dioramen/HOEHEN_PLAN.md` 4.3/7; davor 02.10.2026 Überarbeitung und Wegsaum). Modul: `tools/dio_themes/forest.py`, Texturen: `tools/make_forest_textures.py` →
`game/assets/dio/forest/` (Herkunft dort in `HERKUNFT.md`, alles prozedural). Bauen: `tools\dio_build.ps1 -Track forest -Shots -Times day,dusk,night -Tag _wald`.

## Höhenniveaus (03.10.2026, Streckenfassung `rev` 2)

Die Strecke steigt in der rechten Schleife auf 4,5 m, überquert die Kreuzung auf einer Holzbrücke (s 0,36 bis 0,445) und fällt in der linken Schleife
wieder; der untere Ast läuft bei s 0,86 bis 0,95 durch einen Hohlweg unter der Brücke. Gelände (`terrain`), Leitplanken, Hohlweg-Collider und Bausteine
stammen aus der Streckendatei (Agent B), Fahrbahn und Brückenfahrbahn baut das Spiel zur Laufzeit. Das Diorama folgt dem so:

- **Dioramaboden `f_level`** (Abschnitt „Höhen“ in `forest.py`): Die Fahrphysik kennt neben der Fahrbahn keine Geländehöhe (ein Auto neben der Piste fährt
  auf der Höhe seines Asts), und das 2-m-Raster verschmiert die Fahrbahnkante um bis zu 0,2 m. Der Boden folgt deshalb dem Raster erst ab einigem Abstand:
  am Fahrbahnrand genau die Fahrbahnhöhe des nächsten Asts; liegt das Gelände höher (Einschnitt, Hohlweg), bleibt eine **1,5 m breite ebene Schulter**,
  dahinter steigt eine **Erdwand 2,4 : 1** bis zum Gelände; liegt es tiefer (Damm, Hang unter der oberen Schleife), fällt die Böschung über 2,5 m weich ins
  Gelände. Brückenstücke (Fahrbahn mehr als 1,0 m über dem Gelände) zählen nicht als Ast: Unter der Brücke gilt der untere Ast, über die Brückenköpfe
  hinaus zählt die obere Kette nicht (nächster Punkt nur als senkrechte Projektion oder im Keil einer Ecke). Abweichung vom Raster: im Hohlweg bis 0,7 m
  (Wandfuß), an den Dämmen bis 0,75 m (Böschungsschulter), sonst wenige Zentimeter; Absicht, damit Bild und Fahrphysik zusammenpassen (die Hohlweg-Collider
  der Strecke liegen 5,1 bis 6,1 m neben der Mittellinie, die Erdwand beginnt bei 5,0 m).
- **Alles steht auf diesem Boden**: Bodennetz, Weite (folgt dem am Rand geklemmten Raster), Saum, Matsch, Radspuren, Streugut und Pfützen relativ zu
  `f_level`; Modelle aus `f_put` auf der tiefsten Bodenhöhe unter ihrem Fuß (`f_gy_min`, Bäume mit 0,45 m x Skalierung: nichts schwebt am Hang); feste
  Baugruppen über `FLift` („lift“: Hütte, Regentonne, Feuerstelle, Hochsitz starr um die tiefste Ecke; „drape“: Holzpolter, Strohballen, Leuchtpfosten folgen
  dem Boden je Eckpunkt), Punktlichter und Lichtblocker wandern mit. Wasser (Teich) und Pfützen sind eben: Der Teich liegt 0,13 m unter dem Boden seiner
  Mulde (Gelände -0,4 m), Pfützen nur bis 0,14 m Gefälle unter dem Ring (bergseitig taucht ihr Rand in den Boden). Unter der Laufzeit-Fahrbahn bleibt das
  Bodennetz unter der Kernprüfung (`branch_floor` + 0,158 m; im Gefälle liegt es dort einige Zentimeter tiefer, der Saum deckt es).
- **Laufzeit-Bauteile** (Laternen, Tribüne, Zeitnahmeturm, liegender Stamm) stellt das Spiel auf das Raster; `prop_y` gleicht den Unterschied zum
  Dioramaboden aus (tiefste Bodenhöhe unter der Grundfläche minus Raster am Standort, 21 Einträge, -0,29 bis 0 m). Kein `set_prop_heights`.
- **Holzbrücke** (`f_bridge`): zwei **Feldstein-Widerlager** im Hang vor den Brückenköpfen (Stirn 1,4 m vor dem Kopf, 12,4 m breit, Steinlagen auf Stirn
  und Flanken, dunkle Hintermauerung als Fugen, bemooste Decksteine), darauf je ein Auflagerbalken; **vier Rundholz-Längsträger** (die äußeren mit Moos)
  über 13,7 m lichte Weite; **Querbohlen** (49, unregelmäßig, 10,1 m lang) 2 cm unter der Laufzeit-Schotterbahn, sichtbar an beiden Rändern;
  **Rundholzgeländer** entlang der Leitplanken der Streckendatei (s 0,35 bis 0,46, Pfosten alle 2 m 4,85 m neben der Mittellinie, zwei Holme; die
  Leitplanken-Physik hält die Wagenmitte bei 4,2 m); **zwei Laternen** über Kreuz an den Brückenköpfen (Holzmast mit Schirmlampe, Punktlicht 1,0/12,5 m,
  Hindernis „mast“): Die Kreuzung hatte nachts sonst kein Licht. Brückenteile über dem unteren Ast heißen `Deck_*` (Bohlen, Träger, Trägerköpfe, Moos,
  Geländer; im Zeichenmodus 35 % deckend), die Widerlager nicht. `add_supports(0.357, 0.449)`: keine Laufzeit-Pfeiler. Die zwei Holzpfosten, die das Spiel
  an den Brückenköpfen neben die Piste setzt (`build_gravel_road`, gleiche Regeln in `f_runtime_posts`), bekommen eine Aussparung in den Bohlen.
- **Hohlweg** (`f_hollow_way`, s 0,83 bis 0,97 des unteren Asts, nur wo eine Wand ist): Erdwände (steile Flächen tragen im Bodenmischer offene, dunklere
  Erde statt Moos und Nadeln, gilt für alle Hänge), 27 freiliegende Wurzeln, 22 Steine am Wandfuß (hinter der Wandkante der Fahrphysik), 21 Farne an der
  Krone; die Sohle ist feucht und dunkel (Schlammfeld bis an den Wandfuß, Matschnetz „hohlweg“).
- Bäume und feste Teile halten die Widerlager frei (Planung: Rechteck und Lichtung je Brückenkopf). Kein Uferschlamm am steilen Nordufer des Teichs.
- Prüfung: `test_diorama` forest besteht (0 Verstöße im Fahrschlauch, `supports`, `track_hash`, 5 `Deck_*`-Knoten, KI ohne Stoß),
  `test_field` forest alle Stufen (auch Schnee) mit allen Gegnern im Ziel. Dreiecke rund 196 000 (Grenze 220 000), Brücke und Widerlager rund 3 600.

## Was gebaut ist (Stand 02.10.2026, weiter gültig)

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
- **Auslaufzonen** (seit 03.10.2026, `f_in_runoff`): außen an Kehren enger als Radius 16 m und bis 12 m hinter dem Scheitel setzt das Thema bis hw + 7 m
  keine Zusatzbäume. Anlass (Prüfung der Nachtschicht): Übertempo in der Talkehre endete immer festgeklemmt an einem Zusatzbaum innerhalb des Freiraums,
  den die Streckendatei dort hält (hw + 6 m außen). Probe (Plantempo fest auf s 0,30–0,62, Stufe 2,3 sonst): 12, 14 und 18 m/s kommen mit 1,2–3,5 s
  Verlust ins Ziel, 16 m/s bleibt an einem Baum der Streckendatei hängen, ab 22 m/s an der Hohlwegwand. 52 statt 70 Zusatzbäume.
- `runtime_terrain` bleibt aus: Das Diorama backt das Relief selbst (`f_level`, siehe oben); der Boden liegt 0,08 m über dem Dioramaboden.
- Alle festen Zusatzteile haben Hindernisse in der Begleitdatei (rund 360); der Fahrschlauch bleibt frei (Test `test_diorama` für `forest` besteht, die KI fährt ohne
  Zusammenstoß).

## Offene Punkte

- Höhen (03.10.2026): Fahrgefühl auf Steigung, Brücke und im Hohlweg auf dem Gerät prüfen (Leitplanke 10). In der Draufsicht des Zeichenmodus liest sich
  das Relief nur über Schatten, Erdwände und Brückengeländer; die Brückenfahrbahn ist dort durchscheinend und nachts dunkel (Ersatzmaterial des Spiels
  ohne Lichtkarte). Die gebackene Umgebungsverdeckung unter der Brücke fällt auf den Boden, nicht auf die Laufzeit-Fahrbahn des Hohlwegs.

- Nicht auf einem Gerät gemessen (MultiMeshes der Bäume, Lichtkarte, Premium-Wasser, die rund 33 000 Dreiecke des Wegsaums).
- Die Fahrbahn ist die Laufzeit-Piste des Spiels (flache Schotterfarbe mit Flecken); das Diorama kann nur den Rand gestalten (Wegsaum). Spurrillen **auf** der Piste und Laub darauf
  wären nur mit Flächen über 0,17 m möglich (Regel `ground_y`: nichts über der Laufzeit-Fahrbahn); das bleibt Sache des Spiels (Fahrbahn-Shader).
- Der Saum kennt keine Gleise im Sinne der Fahrphysik: Die Radspuren sind Optik, die KI und das Fahrzeug spüren nichts.
- Der zweite Leuchtpfosten am Zuschauerplatz fand keinen freien Platz (ein Pfosten steht).
- Einfache Grafikstufe: Alle Hindernisse erscheinen als Klötzchen (Baum = Stamm plus grüner Würfel); die Dichte stimmt, Strohballen und Steg sind grau und grob.
