# Diorama Drift Arena (Thema `harbor`, Stand 02.10.2026, Politur)

Modul: `tools/dio_themes/harbor.py` (Zweig `IS_ARENA`), gemeinsam mit Harbour Run (siehe `harbor.md`). Bauen:
`tools/dio_build.ps1 -Track arena -Shots -Times day,dusk,night -Tag _x`.

## Geschichte des Ortes

Ein Driftevent auf einer großen Betonfläche eines Industriehafens: Flutlichtmasten rund um die Fläche, zwei Gerüsttribünen im Osten und Westen, Zuschauerzeilen
an allen Rändern, Boxengasse mit Teamzelten im Innenfeld, Richterturm am Start/Ziel, Containerblöcke am Rand. Die Fahrbahn (16 m breit, zwei Nadelöhre)
baut das Spiel zur Laufzeit (`runtime`); das Diorama liefert Betonfläche, Spuren, Markierungen, Boxengasse, Richterturm, Zuschauer und die Umgebung.

## Boden und Spuren

- Betonfläche (`HB_ARENA_PAD`, x -92..70, z -47..43) aus Plattenbeton mit Fugen; dahinter Asphalt (weite Fläche) mit Containerfeldern.
- **Belagsflicken** (`hb_plan_patches`): Asphalt im Beton als Rechtecke an den Plattenfugen, dazu 2 m breite Sägeschnitt-Streifen (siehe `harbor.md`).
  Vorher standen dort weiche Rauschflecken, die wie große Ölseen aussahen.
- **Reifenspuren und Rauch**: Außen an jeder Kurve (`hb_corners`) laufen fünf Gummi-Striche (0,5 bis 2,2 m breit, nach außen schwächer) und zwei Rauchbänder
  (5 und 8 m breit); am Scheitel kurze Schleifspuren innen; vier Driftkreise (Donuts). Die Striche werden nach dem Backen in die Lichttextur
  multipliziert (`hb_paint_ao`, dunkler Gummi) und fließen als weiche Gewichte in den Verschleiß-Belag des Bodens ein. Bei Tag sind sie sichtbar, aber
  zurückhaltend (feine dunkle Bögen hinter den Kurven, Ringe in den Donuts, kein Teppich). Auf der Laufzeit-Fahrbahn liegt nichts davon (das Spiel zeichnet
  dort die echten Reifenspuren).
- **Driftzonen**: In jeder Kurve eine Zone auf der Innenseite neben dem Randstein (gelbe Schrägstreifen, weiße Randlinien, weiße Kurvennummer) und
  Leitkegel am Scheitelpunkt. In engen Kurven lässt `hb_build_corner_marks` Streifen aus (Mindestabstand 1,15 m am inneren Streifenende), damit sie nicht zu
  einer gelben Fläche verschmelzen (vorher entstand im engen Innenfeld eine gelbe Sichel).

## Ausstattung

- **Boxengasse** im linken Innenfeld: Faltpavillons in Teamfarben mit Teamauto darunter, Tisch, Fahnen, Reifenstapel, Stromaggregate, zwei Koffer-Lkw
  (Teamtransporter, mit Abstand zueinander). Unter jedem Zeltdach hängt eine LED-Leuchte (`add_light`, 2,7 m hoch, warmweiß, Reichweite 8 m).
- **Richterturm** auf Stahlstützen mit Treppe, verglaster Kabine, hellem Blechdach (vorher dunkel und deshalb eine schwarze Platte), Antenne und Flagge;
  Rettungswagen auf der Innenseite (Lichtbalken mit zwei blauen Hauben statt eines großen blauen Blocks).
- **Zuschauerzeilen** an Nord-, Süd-, West- und Ostrand: Absperrgitter, Werbebanner, Menge dahinter (Menge-Shader), Fahnen. Die Zuschauer stehen jeweils hinter dem
  Zaun. **Korrektur**: `hb_banner_cell` rechnete die Lesrichtung seitenverkehrt (links statt rechts des Betrachters); alle Banner der Arena (Zeilen, Tribünen,
  Richterturm) erschienen mit gespiegelter Schrift. Jetzt gilt dieselbe Regel wie in `crowd_zone` des Kerns.
- Zwei Gerüsttribünen (vier Stufen, Banner an den Stufen, Menge, Geländer, Fahnen, Treppe) hinter den Zeilen im Osten und Westen.
- Startportal über der 16 m breiten Start/Ziel-Linie, zwei Pylone außerhalb des Fahrschlauchs.
- Containerfelder, Leitkegel, Reifenstapel, Fässer, Paletten am Rand; Laternen nur noch locker (alle 30 m entlang der Fahrbahn, wenige an den
  Zuschauerzeilen), weil das Flutlicht die Fläche beleuchtet.
- Fahrzeuge und Zelte tragen den verwitterten Lack (`D_Lack`, siehe `harbor.md`).

## Flutlicht und Nacht

Fünf Masten (12,5 m, Wartungsplattform, Steigleiter, Schaltschrank, Trägerrahmen mit 2 x 4 Scheinwerfern) stehen an den Rändern; die Flutlichter der Streckendatei
entfallen (`baked: ["lamp", "floodlight"]`). Jeder Mast trägt **echte Lichtquellen**: einen kleinen Leuchtfleck am Lampenkopf (Glühen nur dort) und drei Lichtflecke am
Boden (`HB_FLOOD_REACH`: bei 22, 50 und 80 % des Weges von Mast zur Arenamitte, Radius 36 m, Stärke 1,0 / 0,95 / 0,68 x 0,44). Vorher lag ein einziger starker Fleck
15 m vor jedem Mast (Stärke 1,15, Radius 40 m): die Ränder brannten aus, Fahrbahn und Innenfeld blieben dunkel. Jetzt bleibt der Rand hinter dem Mast dunkler, Fahrbahn und Innenfeld sind
gleichmäßig ausgeleuchtet, die Boxengasse bekommt zusätzlich das Licht der Zeltleuchten. Nichts im Diorama leuchtet selbst (nur Banner des Kerns beleuchtet). Die Betonfläche ist
dunkler getönt (0,62), damit sie unter den Lichtkegeln nicht ausbrennt.

## Kontrolle

Ansichten (Tag, Dämmerung, Nacht): Boxengasse, Richterturm, Zuschauerzeilen, Tribünen, Masten, Kurven mit Reifenspuren, Driftkreis, Start/Ziel. Dreiecke (ohne
KI-Modelle der Laufzeit): etwa 59 000.

## Offene Punkte

- Die Zuschauermenge hinter den Zäunen ist flach (Textur); die Tribünen tragen ebenfalls die Mengentextur.
- Die Masten stehen außerhalb des Zuschauerrings; der Mast am Südrand (x -8, z -47) ließ sich wegen des Containerfelds nicht setzen. Die Flutlichtflecke der übrigen Masten
  decken die Südseite mit ab.
- Ein Rauchband ist nur als Verdunklung der Lichttextur umgesetzt (kein Partikelrauch im Diorama).
