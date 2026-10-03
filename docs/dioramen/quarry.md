# Diorama Quarry Loop (Thema `quarry`)

Stand 03.10.2026 (Fassung 2 der Strecke, „Bruchkante Ost“, Bauplan `docs/dioramen/HOEHEN_PLAN.md` 4.1 und 7 C1). Modul: `tools/dio_themes/quarry.py`,
Texturen: `tools/make_quarry_textures.py` → `game/assets/dio/quarry/` (Herkunft dort in `HERKUNFT.md`, alles prozedural).
Bauen: `tools\dio_build.ps1 -Track quarry -Shots -Times day,dusk,night -Tag _q`. Nahansichten der Höhen: `AT=0.515` (Sprung über den Sohlenweg),
`AT=0.36` (Fahrrampe), `AT=0.56` (Landerampe), `CX=60,CZ=-14` (Ecke 4, Bruchwand), `CX=28,CZ=-12` (Bruchwand von der Sohle), `CX=10,CZ=-8` (Pumpensumpf).

## Höhenniveaus (Fassung 2)

Maßgeblich ist das Geländeraster der Streckendatei (`terrain`, 2-m-Zellen, wie `Circuit.terrain_height`): Grubensohle 0, obere Sohle 5,6 m (x ≥ 4, z ≤ −18),
Dämme der Fahr- und der Landerampe auf Fahrbahnhöhe bis Halbbreite + 2,5 m, Sohlenweg-Korridor 0. Das Thema leitet alles daraus und aus den `collider`-Bausteinen ab
(`q_levels_plan`), nichts davon ist im Modul fest eingetragen:

- **Bruchwände**: An den unsichtbaren Bruchwand-Hindernissen (`collider`, `mauer`, b 0, h < 10) wird der 2-m-Übergang des Rasters zu einer senkrechten Wand an
  der Hinderniskante (`q_crisp`, Linie auf halbe Meter gelegt). Die Wand wird entlang des Hindernisses verlängert, solange das Raster dort eine Stufe hat: Westwand
  x = 3,5 von z −85 bis −17, Nordwand z = −17,5 von x 3,4 bis 57, dazu die Landelippe x = −7,5. Im Bodennetz rücken die beiden Knotenreihen beidseits der Linie auf
  3 cm heran (`q_snap_faces`): fast senkrecht, ohne Risse. Davor steht das eigene Netz `Bruchwand_*`: gesprengter Kalkstein (Textur `F_Fels`), leicht zerklüftet,
  **Bohrlochpfeifen** (senkrechte Halbrinnen alle 2,6 bis 3,6 m), feuchter Fuß, verwitterte Krone; abseits der Fahrbahn (> 14 m) eine **Bankstufe** auf halber
  Höhe (unterer Teil 1,1 m vor der Wand, an den Enden auslaufend; 60 m der Westwand). Der Boden am Wandfuß ist feucht und dunkler, die obere Sohle heller und
  staubiger (Höhenebene in der Draufsicht lesbar).
- **Dämme**: geneigte Abschnitte des Höhenprofils (Fahrrampe 0,2898–0,3916, Landerampe 0,5407–0,5738). Außerhalb des ebenen Kamms (Halbbreite + 2,5 m)
  Haufwerkböschung 1 : 1,3 (Boden dort Schotter statt Fels, `q_dam_mask`). Unter der Fahrbahn liegt die **Dammkrone** (`Gelaende_Dammkrone`, ±4,3 m auf Basis
  + 0,10, mit kurzen Schürzen): Die Kernprüfung `check_runtime_ground` nimmt das Minimum der Basis aller Segmente im Umkreis HW + 0,3, auf 17 bis 27 % Gefälle
  liegt das 0,6 bis 1 m unter der Fahrbahn; das Bodennetz hält diese Grenze (`q_mesh_h`), die Krone deckt den Streifen und wird erst nach der Prüfung an
  `objs_ground` gehängt (bekommt die Lichttextur; liegt nach Bauart 6 cm unter der Grenze, Protokollzeile `Dammkrone`).
- **Felswand Ost**: außen an Fahrrampe, Ecke 3 und Ecke 4 (Seite der Felswand-Hindernisse h 12) bleibt der Boden auf Fahrbahnhöhe; die Bänke beginnen dort
  6,5 m neben der Mittellinie, die erste Stufe ist doppelt so hoch (5,6 m) und steiler. Felsschollen dort kleiner und seltener.
- **Sohlenweg**: Innerhalb Halbbreite + 0,8 m eines deutlich tieferen Asts (≥ 1,5 m) liegt der Boden auf dessen Höhe (Sohlenweg unter dem Sprung, Fuß der
  Landelippe). Kein Graben mehr: `q_pit_plan` baut ihn nur noch bei ebener Lücke (Fassung 1).
- **Bänke** wie bisher (vier Stufen, 2,8 m), jetzt über der Arbeitsebene (obere Sohle: Bänke ab 5,6 m); innen gilt die konvexe Hülle der Mittellinie als
  Sohle (die Strecke kreuzt sich, Punkt-in-Polygon wäre dort falsch).
- Höhen der Laufzeit-Bauteile: Das Spiel setzt sie auf `terrain_height` + `prop_y`; eingetragen wird nur der Unterschied Dioramaboden − Geländeraster
  (`set_prop_heights(q_base_y − terrain_y)`), z. B. Brecher und Felswände auf der oberen Sohle.

## Bauteile an der Bruchkante

- **Sicherheitswall aus Haufwerk** entlang der sichtbaren Wall-Hindernisse (`absperrung`, 1,0 m über b, 44 Stücke als eine Kette): Schüttwall (Fuß 1,5 m,
  Krone 0,35 m, Schotter) mit Brocken, Höhe folgt b; die Flächen gelten als belegt (`Q_SOLIDS`).
- **Holzschanze umschüttet** (Laufzeit-Schanze an der Lücke): Bruchstein-Schüttung beidseits ab 3,28 m bis knapp unter die Schanzenkante, 1,5 m Anlauf, Brocken.
- **Landelippe**: Stützmauer aus Betonblöcken (4 Lagen, versetzt, Fugen) an der Stirnseite des Schüttkegels und eine verkratzte Stahlkante (Stirnblech mit
  blanken Kratzern und Rost, Oberflansch 1,5 cm unter dem Fahrbahnende) über die ganze Dammkrone. Das unsichtbare Hindernis der Stirnwand (x −8,5 bis −7,5,
  z −30 bis −18) reicht seit 03.10.2026 nur bis 2,6 m (Lippe 3,0 − `lip` 0,4): Vorher fing es mit 3,0 m Oberkante Autos, die korrekt knapp hinter der
  Lippe landeten (Absprung 11,1–12,3 m/s), auf dem ersten Rampenmeter fest. Jetzt landet ab 11,5 m/s jedes Auto und fährt weiter; darunter prallt es
  an die Stirnseite (Lippenregel). Das Diorama nimmt Lage und Normale der Wand weiter aus diesem Hindernis, die Höhe der Mauer aus der Fahrbahn.
- **Schild „Sprengbereich“** (gelbes Dreieck mit Sprengzeichen, Zusatztafel) 15 m vor der Kante auf der oberen Sohle, Mast als Hindernis; Absperrschranken
  dort 6,3 m neben der Mitte; Leitkegel 13 bis 19 m vor der Kante und auf der Dammkrone hinter der Landelippe.
- **Pumpensumpf** statt Baggersee (der See lag auf der neuen Kehrschleife): kleine Wasserhaltung östlich des Sohlenwegs (x 9, z −9,5; steile Böschung), die
  Motorpumpe mit Saug- und Druckschlauch daneben, Betonrohre, Zufahrt mit Fahrspuren. Haldenweg auf der oberen Sohle zum Brecher.
- **Licht an Kante und Kreuzung**: zusätzliche Flutlichtmasten auf der oberen Sohle vor der Kante, am Fuß der Fahrrampe und an der Nordstraße, ein
  Lichtmast-Anhänger in der Kehrschleife, der die Kreuzung unter dem Sprung anstrahlt (insgesamt 12 Masten, 4 Anhänger, 18 Lichter).

## Was unverändert blieb

Förderband (baked), Kieshaufen (baked), Findlinge, Felsschollen, Felsriegel am Böschungsfuß (unsichtbar, neu verteilt), Betriebswege mit Fahrspuren und Pfützen,
Wasserwagen, Tankstelle, Natursteinblöcke, Büro mit Bauzaun und Geländewagen, Reifenwand am Looping, Flutlichtmasten und Anhänger, Wasser ohne Zusatzlicht
(siehe Fassung 1: dunkle Grundfarbe, Tiefe nur im Rotkanal). Die alten Aufstellungsorte werden geprüft; was jetzt auf erhöhtem Boden läge, fällt weg
(`q_free` verlangt ebene Sohle, `q_flat_floor`), Masten, Kegel, Schilder, Halden und Findlinge stehen auf dem Boden am Ort (`q_ground_y` mit Relief).

## Entscheidungen

- Relief nahe der Fahrbahn = Geländeraster, außer an den Bruchwänden (senkrecht statt 2-m-Rampe, an der Kante der Hindernisse) und unter der Fahrbahn auf
  Rampen (Kernprüfung, Dammkrone). Die Abweichungen liegen hinter Hindernissen der Spielebene.
- Hindernisse: 355 (193 unsichtbar). Neu nur Schildmast und Leitkegel/Schranken; der Wall hat seine Hindernisse in der Streckendatei.
- Dreiecke: rund 129 000 instanziert (Boden 47 000, Felsschollen 30 000, Bruchwände 7 200).

## Offene Punkte

- Kernwunsch: `check_runtime_ground`/`branch_floor` könnte je Ast die Basis am nächsten Punkt nehmen statt des Minimums im Umkreis; dann bräuchte es die
  Dammkrone nicht.
- Die Felswand-Modelle (KI) wirken gröber als die gebauten Wände; Ersatz über `baked: ai:steinbruch_felswand` möglich.
- Einfache Grafikstufe: Klötze nur für sichtbare Hindernisse (Wall als Klötze der Streckendatei); Bruchwände, Dammkrone, Lippe gibt es dort nicht.
- Der Höhenunterschied von 5,6 m ist aus der Rennkamera (72°) kaum zu erkennen (Prüfung 03.10.2026); Schatten und Wandflächen helfen nur in Schrägansicht.
- Nicht auf einem Gerät gemessen.
