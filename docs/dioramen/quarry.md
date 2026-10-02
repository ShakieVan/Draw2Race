# Diorama Quarry Loop (Thema `quarry`)

Stand 02.10.2026 (nach der Überarbeitung am Nachmittag). Modul: `tools/dio_themes/quarry.py`, Texturen: `tools/make_quarry_textures.py` →
`game/assets/dio/quarry/` (Herkunft dort in `HERKUNFT.md`, alles prozedural). Bauen: `tools\dio_build.ps1 -Track quarry -Shots -Times day,dusk,night -Tag _stb`.

## Was gebaut ist

- **Straße**: `runtime` (Fahrbahn, Rampen, Graben-Lücke, Looping und Abkürzung baut das Spiel). Die Grubensohle bleibt eben auf 0,08 m.
- **Gelände** (`Gelaende`): Sohle = Inneres der Strecke, 10 m Rand um die Fahrbahn, ebene Flächen um Bagger, Kipper, Brecher, Büro, Kieshaufen,
  Förderband und beidseits 9 m um die Abkürzung. Dahinter steigt der Boden in vier Bänken an (Absatz 8,5 m, Böschung 2 m, Stufe 2,8 m, Ränder mit
  Rauschen verzogen), insgesamt rund 11 m. Böschungen nehmen Felsstruktur an, die Sohle Schotter, Betriebswege, Pistenrand und Absätze Staub. Eine Mulde
  mit Baggersee (1,5 m tief, türkis im Flachen, Kalksaum, Uferschlamm).
- **Graben in der Lücke der Fahrbahn** (neu): Die Lücke (`gaps`, 5,9 m) ist ein echter Einschnitt von 1,7 m Tiefe quer über die Piste (Maße aus der
  Streckendatei, `q_pit_plan`): an den beiden Fahrbahnenden senkrechte Bruchsteinmauern mit Betonabdeckplatten, an den Schmalseiten Erdböschungen aus Fels und
  Staub, unten Wasser (gleicher Flachwasser-Shader wie der See, `See_Graben`). Das Hauptnetz des Bodens hat dort ein Loch (ganze Zellen), ein Feinnetz (0,5 m)
  füllt den Rand. Die Pfützen im Graben entfallen; vor dem Graben stehen weiter die Absperrschranken, Warnschilder und neu je vier Leitkegel an den Schultern.
  Der Graben hat kein Hindernis: Wer die Lücke nicht schafft, fällt (Fahrphysik, nicht Darstellung).
- **Förderband** (neu, `baked: ai:steinbruch_foerderband`): Das KI-Modell war auf 3 m geschrumpft und warf einen 20 x 3 m großen Schatten (`ao_proxies`). Jetzt ein
  eigener Gurtförderer in der Länge der Streckendatei (20 m, steigend von 1,2 auf 4,8 m): gelber Aufgabetrichter mit Rost, Muldengurt mit Schotterladung,
  Seitenbleche, Tragrollenstationen, Stahlböcke mit Betonfüßen und Verstrebung, Laufsteg mit gelbem Geländer, Antriebskopf mit blauem Motor, Abwurfschurre über der
  Halde. Zwei LED-Strahler (echte Lichtquellen, `add_light`). Hindernis: Rechteck 20 x 3 m wie das Modell. Die Halden an beiden Enden (Vorrat und Abwurf) stehen da.
- **Boden-Texturen**: gebrochener Kalkstein (Schotter), Lehmstaub, Felsplatten; feuchte Stellen an Schlammstrecke und Graben dunkler.
- **Betriebswege** mit zwei Fahrspuren schwerer Maschinen (Bänder mit Profilstollen, Enden verlaufen), Wasserpfützen in den Spuren.
- **Felsen**: 150 Findlinge (selbst gebaut, Kalkstein-Textur), 620 Felsschollen mit Neigung in den Böschungen (Mauerwerk der Bänke, körperlos), 216 Felsriegel
  als **unsichtbare** Hindernisse (`visible=False`) am Fuß der ersten Böschung (damit niemand in den Hang fährt; die einfache Grafikstufe zeichnet dafür keine
  Klötze). Die 22 Felswand-Modelle der Streckendatei (z = ±58) bleiben Laufzeit-Bauteile, **stehen aber auf dem Gelände**: `set_prop_heights(q_base_y,
  types=["ai"])` mit der Höhe unter ihrer Grundfläche (12-%-Perzentil, 25 cm eingelassen), dieselbe Funktion für die Kontaktschatten.
- **Ausrüstung**: Wasserwagen, Dieseltankstelle (Betonwanne, Zapfsäule, Poller, Bauzaun), drei Stapel gesägter Natursteinblöcke, Frachtcontainer, Betonrohre am
  Graben, Fässer, Riesenreifen als Prallschutz am Looping, Schüttkegel (Halden), Bauzaun um Containerwache und Tankstelle, Absperrschranken mit Warnleuchte,
  Warnschilder. Neu: weißer Bauleiter-Geländewagen mit Dachträger und orangem Rundumlicht am Zaun des Büros, elf Leitkegel (orange, Reflexband), eine
  Motorpumpe am Baggersee (Wasserhaltung: Saugschlauch mit Schwimmer im See, blauer Druckschlauch zum Weg).
- **Nacht** (neu): echte Lichtquellen sind zehn Flutlichtmasten (Betonfuß, konischer Stahlmast, Plattform mit Geländer, je vier Strahler) außen um die
  Betriebsstraße, drei Lichtmast-Anhänger bei den Maschinen, zwei Strahler am Förderband, die drei Baustellenleuchten (`lamps`) und die Warnleuchten der
  Absperrschranken (blinken): 15 Punktlichter (`lights`) plus drei Laternen. Alle Strahlerköpfe leuchten nur nachts (`K_lampe`), am Tag sind sie aus. Nichts
  leuchtet von selbst. **Wasser unter Lampen**: Das Zusatzlicht des Spiels (`lit_overlay`) nimmt Grundfarbe x Vertexfarbe (Tiefe in Rot) als Albedo; das Wasser
  bekam deshalb eine dunkle Grundfarbe ohne Verknüpfung mit der Vertexfarbe und Grün = Blau = Rot in der Vertexfarbe (der Wasser-Shader liest nur Rot), sonst
  leuchtete der See unter Flutlicht rot. (Der Eintrag `tints` der Begleitdatei hilft hier nicht: das Wasser wird vor der Tönung abgezweigt.)
- **KI-Modelle bleiben zur Laufzeit** (Bagger, Kipper, Brecher, Büro, Felswände); die Kieshaufen und das Förderband baut das Diorama selbst. Kontaktschatten
  kommen über `ao_proxies` (ohne Förderband und Kieshaufen).

## Entscheidungen

- Die Bänke und der See sind echtes Gelände im Boden (nicht im Spiel gebaut): `runtime_terrain` bleibt aus, weil die Streckendatei kein `terrain` hat.
- Der Graben setzt voraus, dass die Lücke achsparallel läuft (z konstant); sonst überspringt `q_pit_plan` ihn mit einer Warnung. Er liegt innerhalb der Lücke
  (höchstens 0,6 m schmaler); Mauerkrone auf Geländehöhe (0,08 m), die Fahrbahnenden stehen 9 cm darüber. Die Flecken auf dem Wasser (braune Quadrate) sind
  Schotterflecken der Laufzeit-Fahrbahn, die das Spiel auch über die Lücke legt (Kern, nicht Thema).
- Hindernisse: alles Feste in der Nähe der Fahrbahn bekommt ein Hindernis (367 insgesamt, davon 216 unsichtbar). `test_diorama` für `quarry`: Fahrschlauch frei,
  KI fährt ohne Zusammenstoß; Leitkegel (weich) stehen mindestens HW + 1,5 m von der Mittellinie.
- Dreiecke: rund 113 000 instanziert (Richtwert 100 bis 150 k).

## Offene Punkte

- Die Laufzeit-Rampe vor dem Graben ist nachts fast schwarz (Rampen-Shader des Spiels kennt kein Laternenlicht); nicht Sache des Themas.
- Die Felswand-Modelle (KI) wirken in Farbe (kühles Grau) und Dreiecken gröber als die Felsschollen; sie liegen 36 m von der Piste entfernt und sind nur am Bildrand
  zu sehen. Ein Ersatz durch gebaute Wände wäre über `baked: ai:steinbruch_felswand` plus gleichwertige Hindernisse möglich.
- Die Rampen-/Looping-Stützen sind Laufzeit; das Diorama hat dort nichts verändert.
- Einfache Grafikstufe: Sie zeichnet nur die Hindernisse der Begleitdatei als Klötze (das Förderband als 20-m-Block, die 216 Felsriegel gar nicht); Graben,
  Wasser, Pumpe, Auto und Leitkegel gibt es dort nicht.
- Nicht auf einem Gerät gemessen.
