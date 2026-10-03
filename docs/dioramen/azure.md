# Azure Coast Speedway (Strecke `azure`, Thema `coast`)

Stand 02.10.2026 (Politur nach der Stadion-Fassung). Die Küste ist ein Stadion am Meer. Anlass war der Nutzerwunsch, die Küste im Sinn eines
Motorsport-Stadions umzugestalten und Teich und Steg in der Mitte zu entfernen. Es wurde nur das Konzept „Stadion“ übernommen (Tribünen ringsum,
Boxengebäude im Innenfeld, Transporter, Rennwagen), nichts aus dem Referenzspiel. Eigene Identität: Weiß, Azurblau, Sand, Korallrot; saubere moderne
Architektur (weißer Beton, Segeldach).

## Dateien

| Datei | Inhalt |
|---|---|
| `tools/dio_themes/coast.py` | Themenmodul: Hooks, Gelände (Zellen mit Vertexfarbe, Hügel, Terrassen), Meer, Pflaster, Szenerie, Seestadt, Park, Licht, Hindernisse |
| `tools/make_coast_parts.py` | Geometrie ohne Blender: Oval-Versatzlinien, Mauer mit Fangzaun, Tribünen (Menge, Gänge, Treppenleute), Brüstung, Banner, Lichtblenden |
| `tools/make_coast_objects.py` | Segeldach, Boxengebäude, Transporter, Rennwagen, Reifenstapel, Videowand, Lichtmast, Posten, Rettungsturm, Café, Figuren, Pflanzen (Palme, Zypresse, Schirmpinie, Busch) |
| `tools/make_coast_stadium.py` | Texturen (eigene Grafik, Schrift Outfit): Mauer-Werbebahn, Sitzschalen, Boxenblende, Lackierungen, Videowand (Albedo und Leuchtbild), Planken, Platten, Schilder, Blumen |
| `game/assets/dio/coast/` | erzeugte Texturen, `HERKUNFT.md` |
| `tools/make_tracks.py` (nur `azure()`) | Streckendatei: Mittellinie unverändert, sieben Flutlichter als Bausteine |
| `game/dioramas/azure*` | erzeugtes Diorama (`dio_build.ps1`) |

Die Entwicklungsdatei `tools/dio_themes/_azure_dev.py` ist gelöscht. Der Sand der Küste (`tools/make_coast_textures.py`) und `game/assets/ground/` blieben unverändert.

## Aufbau (Abstand d zur Mittellinie, Halbbreite 3,5 m)

- **Fahrbahn**: Straßenart `painted` (gebackene Fahrbahn, flacher rot-weißer Randstein); der Boden liegt bei y = 0,10, darunter eine senkrechte
  Randsteinkante. Belagzonen (Schlamm außen in beiden Kurven) im Boden als Vertexfarbe (B = Erde). **Schlammband** (`az_mud_strips`): Das Spiel legt
  neben den Randstein einen braunen Streifen bei y = 0,13, der nachts unbeleuchtet schwarz wirkte; ein Band aus Bodenfläche (Erdgewicht 1, y = 0,148, fällt
  zu den Rändern ab) liegt darüber und trägt Bodentextur und Laternenlicht.
- **Auslauf** bis d = 6,6 (Gras mit Mähbändern, in den Kurven Schlamm), dann **Sicherheitsmauer** bei d = 6,8 (0,9 m hoch, azurblauer Streifen,
  Werbebahn) mit **Fangzaun**. Mauer und Zaun sind Hindernisse der Art `mauer`. In den Schlammzonen steht davor eine Reifenwand (weiche Hindernisse `reifen`).
- **Tribünen** ab d = 7,5 rund um das Oval: Haupttribüne (12 Reihen, Zone M, Startgerade) mit **Segeldach** auf Masten, Ost- und Westkurve 9 Reihen,
  Seeseite (Zone F) 6 Reihen. Sitze als Textur (Azur/Weiß/Koralle/Marine/Türkis), Gänge alle 18 Indizes mit Handläufen, Zugänge in der Rückwand,
  Glasbrüstung, Banner, Fahnen, Beschilderung. **Menge** (`E_menge`-Streifen): Je Block (Abschnitt x Dreierreihengruppe) eine eigene Sitzfarbe und ein eigener
  Füllgrad (meist gut gefüllt, einzelne fast leere Blöcke), nach hinten lichter; Streifen zufälliger Länge, Größe, Versatz und Spiegelung; einzelne Leute
  stehen auf den Treppen der Gänge. Eine Tribüne ist ein Hindernis `mauer` von der ersten Reihe bis zur Rückwand.
- **Innenfeld** (>= d 5,0): Rasen, **Boxengebäude** (sechs Garagen, Glasfront, Azurblende mit Schriftzug, Lichtdach, Rennleitung), Boxengasse, vier
  **Rennwagen** mit Boxencrew, Reifenstapel, **Fahrerlager** mit drei Team-Transportern, **Videowand** auf Stahlgerüst, Blumen- und Palmenbeete, Streckenposten
  (Hütte mit **ruhender** Flagge aus `K_`-Flächen: die wehende `E_flagge` bekommt nachts kein Laternenlicht und wirkte schwarz). Die Boxenmauer hat an der
  Startlinie (|x| < 4,2) eine Lücke.
- **Küste**: Promenade (Holzplanken) hinter der Seetribüne mit Palmen, Bänken und Laternen; Strand mit Schirmen und Liegen, zwei Rettungstürme, Strandcafé mit
  Tischen, Surfbrettern, Badegästen, **Beachvolleyballfeld** (ebene Terrasse im Strandhang, Linien, Netz mit Pfosten und Antennen, vier Spieler, Ball, zwei
  Flutlichtmasten mit warmem Licht auf einer flachen Landzunge `cape` der Uferlinie), Felsen, Meer mit Tiefenfarbe und Brandung, Segelboote.
- **Eingang** (Nord): Allee aus Sandplatten, Eingangstor mit Schildern, zwei Kassenhäuschen, Fahnenmasten, Bänke, Palmen, Blumenbeete, Parkplätze links und rechts.
- **Kiesband**: Um den gepflasterten Ring (d 19 bis etwa 22,5, unregelmäßiger Rand) liegt ein Streifen Sand/Kies statt Rasen. Grund: Das warme Licht der
  Ringlaternen färbt Rasen limettengrün (die Lichtkarte addiert Albedo mal Laternenfarbe), auf Kies bleibt es warmweiß.
- **Umgebung** (Seestadt, `az_town_plan`, `az_town`, `az_hang`, `az_park`): Hügel (`AZ_HILLS`, Nordhang bis 12 m, Seitenhänge 8 m und 5,5 m) mit Hausplätzen als
  ebenen Terrassen (`AZ_PADS`); **47 Häuser und Hotels** aus dem Bausatz des Kerns (`kit_house`, Fenster leuchten nachts mit dem Fensterlicht), davon fünf hohe
  Riegel/Türme (6 bis 10 Geschosse) am Rand; neun Gassen am Hang (Asphaltband, quer zur Gasse eben, mit Längsparkern); Zypressen, Schirmpinien, Büsche und einfache Palmen
  (`palm_cheap` etc., 16 bis 60 Dreiecke je Baum) in Hainen nach einem Rauschfeld; **Küstenpark** auf den Rasenflächen zwischen Stadion, Parkplätzen und Straßen
  (96 Bäume und Büsche, Hecken entlang der Straßen, Blumenbeete); Nord-, Ost- und Weststraße mit Mittellinie, Randlinien und parkenden Autos (`kit_car`).
  Der Rasen weit vom Oval hat große Helligkeitsflecken (Wiese statt Rasen).
- **Nacht**: Das Licht kommt ausschließlich von echten Quellen (`az_lighting`, 34 Punktlichter): 14 Lichtmasten vor den Tribünen, je zwei am Innenfeldende, auf dem
  Boxendach und am Volleyballfeld; Lichtleisten unter dem Segeldach, Deckenleuchten der Garagen, Torleuchten, Schein der Videowand; dazu die sieben Flutlichter der
  Streckendatei, die Laternen (Promenade, Parkplätze, Ring, Fahrerlager) und die Fensterlichter (Glasfronten, Häuser).

## Licht: Lichtblocker und Blenden

- **Tribünen als Lichtblocker** (`add_occluder_chain`): Je Zone eine Kette entlang der Rückwand (Breite 0,8 m, Höhe = Rückwandkante: 5,35 m bei 9 Reihen, 6,7 m bei
  12 Reihen, 4,0 m bei 6 Reihen). Dazu Polygone für das Boxengebäude (3,9 m), die Rennleitung (6,5 m) und die drei Transporter (3,8 m).
- **Blenden an den sieben Flutlichtern** der Streckendatei (`azp.hood_poly`, Halbring mit 120 Grad hinter dem Lampenkopf, Höhe 9,5 m): Ihr Licht zeigt zum Oval, nicht
  nach außen (die Köpfe stehen hinter den Tribünen bei d ≈ 19).
- Ergebnis: Oval und Tribünen gleichmäßig beleuchtet, außerhalb nur die Lichtpfützen der Ringlaternen auf Kies. Lichtstärken der Masten 0,26 bis 0,30 (Vorgabe war 0,4 bis 0,5: zu hell).
- **Videowand**: `K_`-Oberfläche des Spiels (`k:../dio/coast/screen`): Albedo `screen.png` mal dunkle Vertexfarbe (`SCREEN_V`) = am Tag dunkles, gut lesbares Bild ohne Leuchten;
  `screen_e.png` ist die Emission (Faktor 2 heller als das Albedo), die das Spiel mit dem Fensterlicht schaltet (Tag 0, Dämmerung schwach, Nacht voll). Beim Backen
  gibt es `add_light` (kühles Blau, Reichweite 10 m) für den Schein auf dem Boden.

## Spielebene

- Mittellinie, Bedingungen, Belagzonen und Halbbreite sind unverändert (`make_tracks.py`, nur `azure()` geändert).
- Hindernisse (322): Mauer, Tribünen, Boxengebäude, Transporter, Autos, Pfosten, Bänke, Bäume (Palmen am Ring, Park und Hang sind nur Bild).
- Einfache Grafikstufe: Das Spiel baut aus den Hindernissen der Begleitdatei Klötze und die sieben Flutlichter (lesbare, einfache Stadionform).
- Der Fahrschlauch bleibt frei (Mauer bei d = 6,62 bis 6,98), `test_diorama` meldet 0 Verstöße, die KI fährt azure ohne Zusammenstoß.

## Entscheidungen

- **Zellenboden statt Texturmeshes**: Der Boden (`Gelaende`) ist ein Vertexfarben-Netz im Format des Boden-Shaders (R Helligkeit, G Sand, B Erde): weiche Übergänge
  Gras/Sand/Erde. Feine Zellen (0,25 m) nur an Fahrbahnrand und Schlamm, 1 m am Ring, 6 m (1,5 m im Küstenband) außerhalb des Rahmens. Das 4-m-Raster endet nach
  oben aufgerundet (`AZ["xe"]`, `AZ["ze"]`): vorher blieb am Ost- und Nordrand ein 2 m breiter Streifen offen, durch den das Meer schimmerte.
- **Vertexfarben-Umgehung entfernt**: Der Kern macht das Farbattribut aller Netze selbst aktiv (README 2.5); `az_fix_vertex_colors` ist gelöscht. Geprüft: Mischung Gras/Sand/Erde,
  Mähbänder und Meerestiefe erscheinen unverändert.
- **Meer**: Küstenstreifen mit Tiefenfarbe 2-m-Raster von x0-100 bis xe+100 und z = -58 bis -33; weiter draußen große Flächen. Die Zeilen der großen Flächen reichen bis
  zum Ende des Rasters (vorher klaffte eine Lücke von bis zu 16 m, durch die die türkise Grundfarbe des Spiels schien).
- **Zuschauer** sind Texturstreifen (`E_menge`), kein Gitter am Rand: `crowd` ist ausgeschaltet.
- **Palmen, Schirme, Felsen** am Ring als Modelle `Prop_*` (MultiMeshes im Spiel); Hang- und Parkbäume als einfache Netze (`palm_cheap` und Verwandte), weil sie nur Bild sind.
- **Flutlichter**: sieben mit großen Reichweiten (28 / 24 / 26 m, Lichtkarte des Spiels: Reichweite mal 1,8, Gaußsche Kuppe, keine Strahler).
- **Wehende Fahnen** (`E_flagge`) gibt es nur an Tribünenrückwänden und der Allee, wo die Fahne dem Tageslicht reicht; der Streckenposten hat eine ruhige `K_`-Fahne.

## Messwerte

- Dreiecke Diorama rund 129 000 instanziert, rund 79 000 einzeln (Gelände 14 000, Palmen als Instanzen 36 000, Felsen 12 000, Reifen 5 500, Boxen 4 900, Autos 4 400,
  Häuser fern 4 300, Transporter 3 000, Hangbewuchs 3 000, Meer 1 800). Stadt zum Vergleich rund 100 000.
- Texturen höchstens 1024 Pixel. `azure.glb` 13 MB.

## Offene Punkte

- **Tests**: `tools/build.ps1 -Target Test` am 02.10.2026: alle sechs Läufe bestanden (`test_core` 46/46, `test_flow` 37/37, `test_tracks` 14/14, `test_air` 32/32,
  `test_diorama` 198/198 mit azure: Fahrschlauch frei, KI ohne Zusammenstoß, Lichter und Lichtblocker gültig, `test_collision` 12/12). `test_flow` schlug früher an (ein Rivale rutschte
  bei Nässe bis 8,7 m hinaus und blieb an der Mauer bei 6,6 m hängen); das ist inzwischen behoben (Änderung außerhalb dieses Themas). Falls es wiederkehrt: Rivalen-Können bei Nässe
  senken oder die Mauer samt Tribünen um etwa 3 m nach außen schieben (`AZ_WALL_D` / `AZ_STAND_D` / `AZ_PAVE_*` und feste Koordinaten im Modul).
- Hörabnahme und Geräteprüfung stehen aus (nur Windows-Aufnahmen).
- Die Boxencrew und die Rennwagen sind einfache Körper (keine drehenden Räder); Fahrzeuge der Autowahl sind Laufzeitmodelle und nicht im Bild.
- Das Gelände hat Höhen nur am Strand und an den Hügeln (Hügel ab 40 m vom Oval, Terrassen nur unter den Häusern); die Tribünen stehen auf ebenem Boden.
- Die Hügel beginnen jenseits der Fläche des Dioramas (Ausdehnung ±77 / ±63): Häuser stehen am Rand der Fläche und darüber hinaus (Ferne ohne gebackenen Kontaktschatten).
- Laternen am Rand der Parkplätze werfen limettengrünes Licht auf den Rasen hinter dem Asphalt (Lichtfarbe der Laternen des Spiels, nicht änderbar vom Thema).
- Ferner Rand des Meeres und der Horizont-Ebene bei x ≈ ±177 (Küstenstreifen endet dort): außerhalb jeder Spielkamera.

## Nachtrag 03.10.2026 (Höhen-Paket, C3)

- Die Küste hat eine **gebackene** Fahrbahn und deshalb **keine** Spurenkarte (HOEHEN_PLAN 8, verschoben: Spuren auf gebackenen Fahrbahnen brauchen eigene UV-Wege). Der
  Fahrbahn-Shader rechnet ohne Karte exakt wie vorher (`wear_strength` 0); Kontrollbild Tag (`dio_shot.gd`, Tag `_c3chk`, `AT` 0,3) ohne Auffälligkeiten. Kein Neubau.
