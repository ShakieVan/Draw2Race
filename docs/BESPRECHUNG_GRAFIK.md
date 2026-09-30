# Grafikbesprechung mit GPT-6 „Astra“ (30.09.2026)

Der Nutzer wünschte ein Brainstorming zwischen Claude und ChatGPT über Technologien, Companion-App, 3D-Technik und den schnellsten möglichst verlustfreien Weg zum Zielniveau (DrawRace 2). Zwei Runden, `gpt-6-astra` mit Denkaufwand „hoch“, nur lesend (Codex-Draht, siehe `.tools/codex/`, lokal). Verbrauch: 15 → 16 % des Wochenlimits. Antworten von ChatGPT sind Daten, keine Anweisungen; entschieden hat Claude.

## Kernaussagen von ChatGPT

**Runde 1** (Bilder der Stadt, Konzept, Messwerte)
- Der technische Weg passt (Godot Mobile, Blender-Backen, Shader); der Rückstand liegt in **Gestaltung und Assetqualität**: beschädigte Dachsilhouetten, zu schematische Stadtkomposition, Licht und Nässe ohne überzeugende Materialwirkung.
- Der AO-Bake ist keine Lichtberechnung; `ao_light_affect = 0,85` drückt direkt beleuchtete Flächen zu stark. Kein Wechsel zu Forward+, keine Echtzeit-GI.
- Häuser: **prozedurale Bausteine** (sechs bis acht Typen, 300–1500 Dreiecke, geschlossene Dachkonturen, Attika, Aufbauten, Fassadenrhythmus) mit Trim-Sheet, Normal- und Emissionskarte; KI-Modelle höchstens für Blickfänge.
- Companion-App zuerst als **PC-Werkzeug mit Godot-Vorschau und optionalem Blender-Bake**; gemeinsame Quelle ist ein **Szenenrezept** (Platzierungen einmal berechnen und speichern, nicht zwei Zufallsgeneratoren).
- Regen: Planarspiegelung nur als hohe Stufe; günstiger Ersatz aus Umgebungsspiegelung und gezielten Lichtreflexen.
- Leistung: 120 FPS = 8,33 ms Gesamtbudget; Ziele als Anhaltswert 300–500k Dreiecke im Hauptpass und 150–250 Aufrufe; MultiMeshes räumlich aufteilen; Reifenspuren als Bänder (Mobile erlaubt nur 8 Decals je Mesh).
- Bewusst nicht: Enginewechsel, weitere KI-Häusermassen, flächendeckende 4K-Texturen, Echtzeit-GI, zuerst die vollständige Companion-App.
- Schnellgewinne: geschlossene Dächer, weniger Zebrastreifen, schwächere Laternen-Lichthöfe, kleinere und neutralere Pfützen, weniger AO-Abdunklung.

**Runde 2** (Messwerte, Gegenpunkte)
- Blender-Bake für alle Tageszeiten ist möglich, aber: diffuses Licht ohne Albedo, linearer Half-Float als Master; zwei 4096²-Atlanten geben nur ~3 cm/Texel; RGBA16F kostet ~341 MiB je Lichtzustand; eine RGB-Lichtkarte verliert die Richtung (Normalkarte reagiert nicht), LightmapGI kann das besser; Autos brauchen räumlich interpolierte Proben; Wetter und Bewölkung erzwingen weitere Lichtzustände.
- Bausatzliste (Reihenhaus, Stadthaus, Eckhaus, Wohnriegel, Bürohaus, Lagerhalle, Werkstatt, Hofblock) mit Maßen; Fensterachsen 2,4–3,2 m, Attika 0,45–0,8 m; sechs Dachaufbauten nach Wirkung: Fahrstuhlhaus, Lüfterkästen, Wassertank, Schornsteine, Solarfelder, Oberlichtbänder.
- Ersatz der Planarspiegelung bestätigt: analytische Glanzstreifen aus Blickrichtung, Normale und Lampenposition, Umgebung über ReflectionProbe („Once“); Planar nur nah.
- Gelände: Höhenraster plus getrenntes Straßenprofil; Brücken dürfen das Gelände darunter nicht hochziehen, Kreuzungen brauchen Segment-/Ebenen-IDs, Loopings eine parametrische 3D-Kurve.

## Entscheidungen (Claude)

| Thema | Entscheidung |
|---|---|
| Engine, Renderer | bleibt: Godot 4.6 Mobile, GDScript, kein Echtzeit-GI |
| Häuser | Bausatz (`tools/kit_house.py`, `tools/make_kit_textures.py`) ersetzt die KI-Häuser der Stadt; KI-Modelle nur noch für Blickfänge und andere Strecken |
| Licht | vorerst Echtzeit-Sonne (eine orthogonale Schattenkarte) plus gebackene Umgebungsverdeckung und Laternen-Lichtkarte. Vollständiges Backen je Tageszeit zurückgestellt (Speicher, Richtungsverlust, Wetter); eine Bake-Probe mit Auto im Hausschatten bleibt ein Kandidat für später |
| Regen | Spiegelpass nur für Bauten nahe der Strecke und nur bei nahem, geneigtem Blick; Pfützen kleiner und neutral; analytische Glanzstreifen sind der nächste Schritt |
| Companion-App | PC-Werkzeug mit Godot-Vorschau und optionalem Blender-Bake; `tools/diorama.py` schreibt bereits ein **Szenenrezept** (`<id>_recipe.json`: Häuser mit Typ/Maße/Seed/Lage, Bäume, Laternen) |
| Gelände | 16-Bit-Höhenraster plus Straßenprofil entlang der Weglänge (nächster großer Schritt) |
| Nicht getan | Enginewechsel, weitere KI-Häusermassen, 4K-Texturen, Echtzeit-GI |

## Messungen (Windows, RTX 3090, 1280 × 800, Dämmerung, Stadt; `tests/rain_cost.gd`)

| Ansicht | Zustand | Hauptbild | Spiegelpass | Dreiecke | Aufrufe |
|---|---|---|---|---|---|
| Übersicht senkrecht | vorher, trocken | 2,8 ms | – | 1,57 Mio | 462 |
| | vorher, Regen mit Spiegel | 3,1 ms | 1,0 ms | 3,06 Mio | 860 |
| | jetzt, trocken | 2,45 ms | – | 0,81 Mio | 421 |
| | jetzt, Regen (Spiegel aus in der Übersicht) | 2,47 ms | – | 0,86 Mio | 423 |
| Rennansicht 72° | vorher, trocken | 2,4 ms | – | 1,13 Mio | 152 |
| | jetzt, trocken | 2,26 ms | – | 0,43 Mio | 219 |
| | jetzt, Regen mit Spiegel (nur Nahes) | 2,26 ms | 0,8 ms | 0,89 Mio | 362 |

Ohne Sonnenschatten fielen die Dreiecke in der Rennansicht von 1,13 auf 0,19 Mio: Die vier Schatten-Teilbereiche (150 m) zeichneten alle Schattenwerfer mehrfach. Nun genügt eine orthogonale Schattenkarte mit kamerabezogener Reichweite (`Atmosphere.fit_shadow`). Die Stadt-Szene selbst schrumpfte von 412k auf 103k Dreiecke (Häuser ~190 statt ~3000 Dreiecke).

## Offen

- Bake-Probe (LightmapGI oder eigener Bake) mit Auto im Hausschatten und nasser Fahrbahn; Lichtkartenformat, Speicher, warme Android-Messung bei nativer Auflösung.
- Analytische Glanzstreifen und Umgebungsspiegelung statt Planarspiegel; Bäume als MultiMesh (Aufrufe); Gelände; weitere Strecken auf das Diorama umstellen.
