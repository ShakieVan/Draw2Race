# Dioramen-Pipeline (Stand 02.10.2026)

Ein **Diorama** ist die gebackene Bildebene einer Strecke: Boden, Straße, Bauten, Bäume, Wasser und eine Lichttextur mit Kontaktschatten, gebaut in
Blender aus der Streckendatei. Die **Spielebene** (Fahrphysik, KI, Zeichnen, Hindernisse) bleibt die Streckendatei `game/tracks/<id>.json` plus die
Begleitdatei `<id>_layout.json`. Dieses Dokument beschreibt die Pipeline so, dass mehrere Agenten gleichzeitig Dioramen für verschiedene Strecken
bauen können, ohne einander in die Quere zu kommen.

## 1. Ablauf auf einen Blick

```
game/tracks/<id>.json ──┐
tools/dio_themes/<thema>.py (Thema = Feld "theme" der Strecke) ─┤
                                                               ▼
 tools/dio_build.ps1 -Track <id>
   1. Blender: tools/diorama.py  →  .tools/dio_tmp/<id>/{<id>.glb, <id>_ao.jpg, <id>_layout.json, <id>_recipe.json}   (parallel möglich)
   2. unter der Godot-Sperre: nach game/dioramas/ verschieben → Godot-Import → Importanpassungen → ggf. erneuter Import
   3. mit -Shots: tests/dio_shot.gd je Tageszeit → Übersicht und Nahansicht als PNG
```

Aufruf (aus der PowerShell; aus Bash: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/dio_build.ps1 …`):

```powershell
& tools\dio_build.ps1 -Track harbor -Shots -Times day,night -Tag _hafen1
```

| Parameter | Bedeutung |
|---|---|
| `-Track <id>` | Strecke (Datei `game/tracks/<id>.json`) |
| `-Shots` | nach dem Import Kontrollbilder aufnehmen |
| `-Times day,dusk,night` | Tageszeiten der Bilder (Standard `day`) |
| `-Tag <text>` | Namensanhang der Bilder, z. B. `_hafen1`; **je Agent eindeutig wählen**, die Bilder liegen alle im selben Ordner |
| `-ThemeFile <pfad>` | ein Themenmodul von Hand statt `tools/dio_themes/<thema>.py` (Versuche, z. B. `tools/dio_themes/_vorlage.py`) |

Die Bilder landen in `%APPDATA%\Godot\app_userdata\Draw2Race\dio_<id>_<zeit><tag>_uebersicht.png` und `…_nah.png`; das Skript gibt die Pfade aus.
Dauer: Blender 30 bis 120 s (die Stadt mit Häusern und Backen am längsten), Import und Bilder je etwa 15 bis 40 s.

Vergleichsbilder der Stadt (zum Prüfen, dass der Kern unverändert blieb): `dio_city_day_vorher_*.png` (älterer Stand, anderes Fenster) und
`dio_city_day_ist_*.png` / `dio_city_day_neu_*.png` (vor und nach dem Umbau der Pipeline, gleiches Fenster; Unterschiede nur durch bewegte Shader).

## 2. Themenmodule

`tools/diorama.py` ist der **Kern**: Mittellinie, Materialien, Netz-Helfer, die Stadt (Thema `city`: Kreuzungen, Häuser, Park, Tribünen, Bänke,
parkende Autos), Zuschauerzonen, Startportal, Backen der Lichttextur, Begleitdatei, glTF-Export. Alles Themenspezifische steht in
`tools/dio_themes/<thema>.py`. Existiert die Datei, führt der Kern sie direkt nach dem Laden der Streckendaten in **seine eigenen Globals** aus.
Dadurch sieht das Modul jeden Helfer und jede Variable des Kerns; auf der obersten Ebene darf aber nur *definiert* werden (Konstanten,
Funktionen), weil die Helfer erst später entstehen. Aufrufe von `mesh_object`, `box` usw. gehören in die Hook-Funktionen.

Vorlage: `tools/dio_themes/_vorlage.py` (lauffähig, Laufzeit-Fahrbahn mit flachem Rasen). Beispiel: `tools/dio_themes/coast.py` (Küste, bemalte Fahrbahn,
Gelände aus Dreiecksnetz, Meer, Felsen; unverändert aus dem früheren Kern ausgelagert).
Mehrere Strecken können sich ein Thema teilen (`arena` und `harbor` haben das Thema `harbor`): das Modul unterscheidet sie über `TRACK_ID`.

### 2.1 `THEME_CFG` (Dictionary, alle Schlüssel optional)

| Schlüssel | Vorgabe | Bedeutung |
|---|---|---|
| `road` | `"city"` für Thema `city`, sonst `"painted"` | Straßenart, siehe Abschnitt 3 |
| `ground_y` | city 0,295 · painted 0,185 · runtime **0,08** | Höhe der Bodenfläche (`GROUND_Y`) |
| `margin` | city 46 · sonst 34 | Rand um die Mittellinie (m): Ausdehnung von Bodenraster, Lichttextur und `extent` |
| `portal` | `road != "runtime"` | Startportal mit Pylonen auf den Gehwegen bauen |
| `crowd` | `road != "runtime"` | Zuschauerzonen (Gitter, Banner, Menge, Fahnen) an den Geraden bauen |
| `junctions` | `road == "city"` | Kreuzungen, Zufahrten, Ampeln an 90°-Ecken planen (nie bei offenen Strecken) |
| `baked` | city: `building, street_tree, fountain` · sonst `[]` | Bausteintypen, die das Diorama selbst enthält: Das Spiel baut sie nicht mehr zur Laufzeit, ihre Hindernisse kommen aus der Begleitdatei. `"ai:<modell>"` meint nur dieses KI-Modell |
| `vertex_colors` | `"ACTIVE"` | `export_vertex_color` des glTF-Exports (Wasser-/Geländegewichte stecken in der Vertexfarbe). Der Kern macht das Farbattribut jedes Netzes selbst zum aktiven (Abschnitt 2.5); Umgehungen im Thema (`fix_vertex_colors`, `az_fix_vertex_colors`, `hb_fix_vertex_colors`) sind überflüssig und dürfen entfallen |
| `runtime_terrain` | `False` | das Spiel baut das Geländerelief der Strecke (`terrain`) weiter selbst, Abschnitt 3 |
| `edge_out`, `edge_in` | Stadt-Werte bzw. `HW+1` bei runtime | Backen: Kacheln `Boden_*` näher als dieser Abstand (+0,75 m) zur Mittellinie backen nicht mit |
| `ground_set`, `ground_tints`, `ground_scales`, `tints`, `water`, `water_nodes` | – | wandern unverändert in die Begleitdatei, Abschnitt 4 |

### 2.2 Hooks (Funktionen im Modul; der Kern ruft sie an festen Stellen)

Reihenfolge im Kern: Materialien → Straßenbänder/Kreuzungen/Portal → **`theme_ground`** → Hilfsfunktionen → Häuser/Zuschauerzonen/Bänke/parkende
Autos/Park (Stadt) → **`theme_scenery`** → Haus-Objekte → Backen (**`theme_bake_hidden`**) → Begleitdatei (**`theme_layout`**) → Export.

| Hook | Aufruf | Zweck |
|---|---|---|
| `theme_materials()` | nach den Kernmaterialien `M` | eigene Materialien in `M[...]` eintragen (`material(name, tex, rough, normal, color)`, `tex("Ordner")` aus `art/texturen`) |
| `theme_ground()` | nach den Straßenbändern (und dem Stadtboden) | Gelände, Boden, Wasser. **Objekte, die an `objs_ground` angehängt werden, bekommen die gebackene Umgebungsverdeckung.** Bei `runtime` prüft der Kern danach, dass nichts die Fahrbahn überdeckt |
| `theme_scenery()` | nach allen Kernbauteilen, vor dem Backen | Modelle (`place`), Tribünen (`bleachers`), Bauten, eigene Laternen (`lamps.append((Vector((x, z)), Vector((zu_x, zu_z))))`), `ao_proxies()` |
| `theme_bake_hidden()` | beim Backen | Liste von Objektnamen-Präfixen, die beim Backen unsichtbar sind (z. B. `["Meer"]`) |
| `theme_layout(layout)` | vor dem Schreiben | Begleitdatei (dict) ändern/ergänzen, z. B. `layout["water_y"] = …` |

### 2.3 Wichtige Helfer und Daten des Kerns

- Geometrie: `Frame(o, u, v)` (ausgerichtetes 2D-System, `.pt(a, b)`, `.poly(…)`), `flat`, `wall`, `box`, `cone`, `post`, `sloped`, `ribbon`,
  `mesh_object(name, parts)` (ein Objekt), `mesh_objects(name, parts)` (**ein Objekt je Material**, Namen `<name>_<schlüssel>`). Teile sind
  `(Material-Schlüssel, Ecken als (x, z, y), UVs[, Blickrichtung[, Vertexfarben]])` in **Spielkoordinaten** (x, z, Höhe y); Blender-y = −z.
- Platzierung: `place(modell, x, z, drehung, höhe, …)` (Modell aus `game/assets/props/<modell>.glb`, prüft `placed`, trägt Hindernis und Rezept ein),
  `model`, `rect_corners`, `overlaps`, `placed` (belegte Flächen), `collide_rect`, `collide_circle` (Hindernisse der Fahrphysik, Art:
  `mauer, absperrung, gitter, bank, baum, mast, auto, reifen`; weich sind `absperrung, gitter, bank, reifen`). Beide haben das Schlüsselwort
  `visible=False` für unsichtbare Begrenzer (Abschnitt 2.5).
- Rennausstattung: `fence_panel`, `banner_quad`, `crowd_quad`, `flag_parts`, `crowd_zone`, `bleachers`, `build_portal`, `dress_parts`.
- Strecke: `data` (Streckendatei), `HW`, `center` (Mittellinie alle 0,5 m als Vector2 (x, z)), `tang`, `left`, `dist` (Länge bis Punkt), `N`, `C`
  (numpy), `curv`, `inside_sign`/`outer`, `dist_to_center(P)`, `inside(P)`, `x0 x1 z0 z1` (Ausdehnung), `TRACK_ID`, `THEME`, `OPEN`.
- Rauschen und Tönung: `value_noise(x, z, maßstab)`, `ground_tint("gras"|"pflaster", x, z)`.
- Höhen: `ROAD_Y` 0,17 (Fahrbahn), `KERB_Y`/`WALK_Y` 0,30, `GROUND_Y`, `Y_W` 0,302 (Gehweg), `HW`, `KERB_W`, `SIDE`, `FOOT`.
- Pfade und Zustand: `TEX` (`art/texturen`), `PROPS` (`game/assets/props`), `M` (Materialien), `CFG` (zusammengeführte Einstellungen), `ROAD_MODE`,
  `objs_ground`, `colliders`, `lamps`, `recipe`, `scene`.

**Namensregeln fürs Backen** (nach dem Objektnamen-Ende): `…_linie` sind Markierungen und backen nicht, `…_rot/_weiss/_beton/_orange/_gummi/_dunkel/_blau/_gelb/_stahl`
sind feste Aufbauten und backen nicht mit; alles andere in `objs_ground` empfängt die Lichttextur (zweite UV-Ebene „Licht“, Ausdehnung = `extent`).
Objekte mit Präfix `Boden_` werden zusätzlich dort ausgespart, wo Straßenbänder darüber liegen.

### 2.4 AO-Stellvertreter für Laufzeit-Bauteile

Was das Spiel zur Laufzeit setzt (KI-Modelle `ai`, Laternen, Bäume, …), fehlt im Blender-Bild und würfe sonst keinen Kontaktschatten. In
`theme_scenery()`:

```python
ao_proxies()                                   # alle bekannten Bausteine, die nicht in CFG["baked"] stehen
ao_proxies(types=["ai", "lamp", "palm"], base_y=lambda x, z: höhe_am_ort(x, z))
```

Erzeugt Quader/Kegelstümpfe nach den Maßen der Fahrphysik (`game/scripts/track.gd`: `AI_RADIUS`, `PROP_CIRCLES`; `w`/`d`/`h` der Bausteine; Kronen von
Bäumen aus `AO_CROWN`), auch für die vom Kern gesetzten Laternen (`lamps`). Sie existieren nur beim Backen und werden vor dem glTF-Export gelöscht.
Ohne Boden zum Backen (`objs_ground` leer) entsteht eine weiße Lichttextur.

### 2.5 Lichter, Lichtblocker, Bodenhöhen, unsichtbare Hindernisse, Laternenmodelle, Vertexfarben (Kern seit 02.10.2026)

Alles datengetrieben: Ein Thema ruft im Hook `theme_scenery()` (oder `theme_layout()`) die Helfer auf, der Kern schreibt die Begleitdatei (Abschnitt 4), das Spiel
liest sie. Ohne Aufruf bleibt alles beim Alten. Die Zeile `DIORAMA Lichter: … | Lichtblocker … | Bodenhöhen … | unsichtbare Hindernisse …` im Blender-Protokoll
zeigt, was angekommen ist; `DIORAMA Warnung:` meldet Punktlichter außerhalb der Fläche und Bodenhöhen ohne Baustein.

**Punktlichter** (`add_light`): echte Lichtquellen ohne Laterne – Nachttischlampe, Budenbirne, Bildschirmschein, Flutlichtkopf. Sie gehen durch denselben Mechanismus
wie die Straßenlaternen in die Lichtkarte des Spiels (`Atmosphere.bake_rain_lights`, im Shader `lamp_at()`): beleuchten Boden, Fahrbahn, Häuser, Autos und Nebel, werfen
Schatten an Gebäuden und Lichtblockern und sind am Tag aus (Dämmerung 60 %, Nacht voll).

```python
add_light(x, z, y, color=(1.0, 0.82, 0.5), energy=1.0, range=7.0, omni=True, glow=0.0)
add_light(10, 8, 3.0, (1.0, 0.7, 0.35), 1.6, 12.0, glow=1.5)   # warmes Licht in 3 m Höhe, 12 m Radius am Boden, mit leuchtendem Fleck
```

| Argument | Bedeutung |
|---|---|
| `x, z, y` | Lage in Spielkoordinaten; `y` = Höhe der Lichtquelle (m), wichtig für Lichtblocker (siehe unten) |
| `color`, `energy` | linearer Farbton und Stärke; `energy` 1,0 = Straßenlaterne (Farbe 1,0/0,82/0,5). Farbige Lichter färben den Boden: Violett auf Gras wirkt bräunlich, Rot auf Gras dunkel |
| `range` | Radius (m) am Boden, an dem das Licht ausläuft; es fällt quadratisch ab, sichtbar ist es bis etwa 70 % davon |
| `omni` | zusätzlich ein echtes `OmniLight3D` (nur Premium, **ohne Schatten**, Stärke 0,35 x `energy`, Reichweite `range`); das Spiel baut höchstens 6 solche Lichter (`MAX_OMNI`), die übrigen bleiben Lichtkarte. Wirkung auf den Boden gering (rund 1 %), deutlicher auf Modelle mit Normalkarte; für unwichtige Lichter `False` |
| `glow` | Größe (m) eines leuchtenden Flecks (Billboard) an der Lichtquelle, 0 = keiner. Nur nötig, wenn das Thema kein eigenes Leuchtmodell setzt |

**Polygon-Lichtblocker** (`add_occluder_poly`, `add_occluder_chain`): Bisher blockierten nur die Häuser (`occluders`, Rechtecke) das Laternenlicht. Gekrümmte Tribünen,
Mauern und Zäune lassen sich jetzt als Polygon oder Linienzug mit Höhe beschreiben; ohne sie malen Flutlichter den Rasen vor und hinter den Tribünen lichtgrün.

```python
add_occluder_poly([(x1, z1), (x2, z2), (x3, z3), ...], height=8.0)       # beliebiges Polygon, mindestens drei Ecken
add_occluder_chain([(x, z), ...], width=0.6, height=8.0, closed=False)   # Linienzug (Wand, Tribünenrand) als Folge schmaler Streifen
```

Die Höhe zählt: Ein Strahl vom Lichtkopf (Höhe `y`) zum Boden hat auf halbem Weg nur noch die halbe Höhe. Ein Blocker verdeckt ihn nur, solange seine Oberkante höher liegt
als der Strahl an dieser Stelle. Eine 0,4 m hohe Mauer wirft deshalb für eine Laterne in 4 m Höhe nur einen kurzen Schatten dicht dahinter, eine 8-m-Tribüne dagegen einen
langen. Häuser (Rechtecke) blockieren wie bisher alles. Der Boden innerhalb eines Blockers bleibt unbeleuchtet. Die Lichtkarte hat 512 x 512 Zellen über die ganze
Fläche (je nach Größe 0,25 bis 0,5 m je Zelle); Streifen unter einer Zellbreite schließen trotzdem lückenlos.

**Bodenhöhen für Laufzeit-Bauteile** (`set_prop_y`, `set_prop_heights`): KI-Modelle (`place_ai`), Baumkarten, Laternen und der Klötzchen-Ersatz stehen im Spiel auf Höhe 0
(plus `y` des Bausteins und dem Relief der Strecke `terrain`). Hat das Diorama echtes Relief (Bänke des Steinbruchs), stehen sie darin oder schweben. Mit der Bodenhöhe
am Standort setzt das Spiel sie auf den Dioramaboden:

```python
set_prop_y(7, 3.2)                  # Baustein Nr. 7 der Streckendatei (Index in data["props"]) steht auf 3,2 m Boden
set_prop_y((x, z), 3.2)             # oder an einem Ort (Toleranz 6 cm; auch für die Diorama-Laternen aus lamps)
n = set_prop_heights(lambda x, z: boden_hoehe(x, z), types=None)   # alle Laufzeit-Bauteile (nicht in CFG["baked"]); types=["ai"] begrenzt auf Typen
```

`set_prop_heights` überspringt Bauteile im Wasser (`y` < -1) und Höhen unter 5 mm. Das Spiel addiert die Höhe zu `y` und `terrain_height`: **nicht** zusammen mit
`runtime_terrain` verwenden, wenn das Relief schon aus der Streckendatei kommt. Lichtköpfe der Laternen und Klötzchen-Ersatz (`shape`) steigen mit. Die Kontaktschatten
(`ao_proxies(base_y=…)`) brauchen dieselbe Höhenfunktion.

**Unsichtbare Hindernisse** (`collide_rect(..., visible=False)`, `collide_circle(..., visible=False)`): Fahrschlauch-Begrenzer ohne Körper im Bild (Felsriegel am Hangfuß).
Die Begleitdatei trägt dann `"v": false`; die Fahrphysik kennt das Hindernis wie jedes andere, aber die einfache Grafikstufe (`World.build_obstacle_blocks`) zeichnet keinen
Klotz dafür. Die Premium-Stufe hat ohnehin nur, was das Diorama baut.

**Laternenmodell** (`add_lamp`): Einträge von `lamps` dürfen ein Modell tragen, das das Spiel statt der Vorgabe baut (Stadt: `stadt_laterne_kit`, sonst `kueste_laterne`):

```python
add_lamp(x, z, zu_x, zu_z, model="hafen_laterne")                    # Mast bei (x, z), Ausleger zeigt zu (zu_x, zu_z)
lamps.append((Vector((x, z)), Vector((zu_x, zu_z)), "hafen_laterne"))   # gleichwertig; ohne drittes Element gilt die Vorgabe wie bisher
```

Das Modell muss unter `game/assets/props/<modell>.glb` liegen (`test_diorama` prüft es). Reichweite und Lichtkopf werden aus der Form des Modells gemessen
(`ai_arm`), nur `stadt_laterne_kit` hat feste Maße (`LAMP_HEAD`).

**Vertexfarben** (`activate_vertex_colors(me)`): Der glTF-Export mit `export_vertex_color='ACTIVE'` schreibt für ein Netz, dessen Farbattribut nicht aktiv ist, ein weißes
`COLOR_0` und legt die Daten als `COLOR_1` ab, die Godot nicht liest. `mesh_object()` macht das Attribut deshalb selbst aktiv und zur Render-Farbe, und der Kern holt es vor
dem Export für **alle** Netze nach (auch solche, die ein Thema mit `bmesh` baut; ein bereits gesetztes aktives Attribut bleibt unberührt). Folgen für die Stadt: Rasen
(Mähstreifen, weiche Flecken) und Pflaster tragen jetzt ihre Tönung (`ground_tint`), die Fahrbahn ihr Spurrillen-Schwarz (`COLOR.r < 0.5` im Fahrbahn-Shader: Pfützen liegen länglich
in den Fahrspuren), dazu wirkt `vertex_color_use_as_albedo` automatisch auf alle `D_*`-Materialien dieser Netze. Wer Vertexfarben als Gewichte nutzt (`D_Gelaende`: R Helligkeit,
G Sand, B Erde), bekommt sie ohne eigene Umgehung. Die Umgehungen der Themen coast, harbor, fair und kids (setzen Index 0 aktiv) bleiben verträglich und können gelöscht werden.

**So passen die Themen an** (Vorschläge; die Themenmodule gehören ihren Agenten): Steinbruch `collide_*(…, visible=False)` für die Felsriegel und
`set_prop_heights(hoehe_am_ort, types=["ai"])` für die 24 Felswand-Modelle (z = ±58) mit derselben Funktion wie `ao_proxies(base_y=…)`; Küste `add_occluder_chain` entlang der
gekrümmten Tribünen (Höhe wie die Rückwand) und `add_light` für Flutlichtköpfe; Hafen `add_lamp(…, model="hafen_laterne")` statt der Vorgabe `kueste_laterne`;
Kinderzimmer `add_light` für die Nachttischlampe; Jahrmarkt `add_light(…, omni=False)` für die Budenbirnen (viele kleine Lichter).

### 2.6 Nachtlicht im Spiel: Lichtmodell, Wasser, Schanzen, Fahnen (Kern seit 02.10.2026)

Die Lichtkarte (Abschnitt 2.5) enthält je Zelle Lichtfarbe x Energie aller Lampen; die Shader addieren daraus ein Zusatzlicht auf die Fläche. Wie, regelt
`game/assets/lamp_light.gdshaderinc` an einer Stelle (`lamp_lit(albedo, licht, gain, sat, knee, peak)`):

- **Entsättigt:** Die Albedo wird bei Kunstlicht zur Luminanz hin gemischt (`sat` = Anteil der Eigenfarbe). Vorher addierte jeder Boden Albedo x Licht x 2,6 ungebremst, und
  gesättigter Rasen unter Flutlicht leuchtete neongrün (Azure-Infield, Ring, Umgebung der Lampen).
- **Begrenzt:** Die Helligkeit der Emission läuft ab dem Knie (`knee`) weich in einen Grenzwert (`peak`), der Farbton bleibt. Überlappende Lichter brennen nicht aus; unterhalb des Knies
  bleibt alles wie bisher. Werte: Rasen/Gelände `ground_blend.gdshader`, `terrain.gdshader` gain 2,3, sat 0,72, Knie 0,28, Grenze 0,6; Wasser gain 0,55, Knie 0,06, Grenze 0,16;
  Zusatzlicht `lit_overlay.gdshader` Knie 0,5, Grenze 0,95 (`light_sat` 1; Rasenmaterialien `D_Gras`, `D_Wiese` bekommen in `world.gd` `GRASS_LIGHT_SAT` 0,72); Fahnen Knie 0,35, Grenze 0,7.
  Die Fahrbahn (`road.gdshader`) behält ihre Verstärkung 2,6 und das Glanzlicht der Nässe; ihr diffuser Teil läuft aber durch die Tageslicht-Grenze (nächster Punkt).
- **Höchstens Tageslicht** (seit 02.10.2026 abends, Befund Azure: das Stadion wirkte nachts wie bei Tag, der Rasen blass-lindgrün und heller als am Tag): Vor Knie und Grenze
  wird das wirksame Licht (Lichtkarte x gain) weich auf `LAMP_DAY` = 1,0 begrenzt (`lamp_day()`, Knie `LAMP_DAY_KNEE` 0,6). Eine beleuchtete Fläche wird so höchstens so hell wie
  ihre Albedo, also wie am Tag (Tageslicht des Spiels auf flachem Boden etwa Albedo x 0,9 bis 1,2). Gilt für alles mit `lamp_lit` und den diffusen Teil der Fahrbahn. Gewöhnliche
  Laternen (Stadt, Hafen, Jahrmarkt) ändern sich nur in der Mitte ihres Lichtkegels (dort 10 bis 20 % dunkler, vorher bis zum 1,7-Fachen der Tageshelligkeit); der Steinbruch
  verliert seine überhellen Lichtinseln auf der Piste (vorher heller als am Tag, jetzt etwa wie am Tag).
- **Wie hell eine Nacht wirkt, entscheidet das Thema** über die Summe seiner Lichter: Im Oval des Azure-Stadions lag die Lichtkarte beim 1- bis 3-Fachen des Tageslichts (vierzehn
  Masten und sieben Flutlichter überlappen); die Grenze machte daraus eine gleichmäßig taghelle Fläche. `coast.py` dimmt deshalb seine Masten (`AZ_POLE_GAIN` 0,36, Reichweite
  `AZ_POLE_REACH` x 1,12), die warmen Lichter (`AZ_WARM_GAIN` 0,6) und über `prop_light` (Abschnitt 4) die Flutlichter der Streckendatei (Stärke 0,7, Lichtradius x 0,55: sie
  strahlen die Tribünen vor sich an, nicht mehr das ganze Oval). Ergebnis: Oval etwa 85 % der Tageshelligkeit mit Lichtinseln der Masten, Rasen naturgrün und dunkler als am Tag,
  Umgebung und Himmel dunkel. Richtwert für neue Themen: Lichtkarte auf befahrenen Flächen 0,2 bis 0,4 (Probe: `Atmosphere.keep_map`, siehe `tests/test_diorama.gd`).
- **Laufzeit-Bauteile** (`world.gd`, `runtime_overlay`): Seitenstreifen, Schlammbänder und Randlinien (`road_strip`, vorher ganz ohne Zusatzlicht: schwarze Bänder neben
  beleuchteter Piste, Steinbruch östlich des Grabens) lesen die Lichtkarte wie der Boden daneben (`STRIP_LIGHT_GAIN` 3 x 0,75 = 2,25, Boden 2,3); die Fahrbahn selbst
  (`road_strip(..., lit = false)`) bekommt kein zweites Zusatzlicht. Looping-Band und -Borde, Schanzen und Streifen nehmen die beidseitige Fassung des Zusatzlichts
  (`lit_overlay_two_sided.gdshader`, `cull_disabled`, Rückseiten mit umgedrehter Normale: die Oberseite des Rings ist aus der Draufsicht die Rückseite); das Looping liest das
  Licht der Karte auch unabhängig von der Normale (`omni`). Schanzen, Looping, Streifen und KI-Modelle mit Leitplanken-/Wandnamen (`WALL_PROPS`) bekommen eine kleine
  Grundhelligkeit der Nacht (`ambient_floor`, `lamp_floor()`: Albedo x Mond-/Himmelslicht wie auf dem Boden, kein Eigenleuchten; das halbtransparente Band nur die Hälfte je
  Seite, weil Vorder- und Rückseite übereinanderliegen). Die Zuschauer (`crowd.gdshader`) lesen die Lichtkarte selbst (`lamp_lit`, gain 1,6) plus dieselbe Grundhelligkeit;
  vorher waren sie nachts fast schwarz. Der Inhalt des Zusatzlichts steht in `lit_overlay.gdshaderinc`; `lit_overlay.gdshader` (einseitig, `cull_back`, alle übrigen Bauteile
  und Dioramen) blieb im Verhalten unverändert, `lit_overlay_two_sided.gdshader` setzt `TWO_SIDED`.
- **Zuschauer feste Körper** (seit 02.10.2026 spät, Befund: auf den Azure-Tribünen wirkte die Menge in Dämmerung und Nacht blass und durchsichtig wie Geister). Ursache war die
  Reihenfolge der durchsichtigen Durchgänge, nicht das Licht der Menge: Der Zuschauerstreifen (`E_menge`) liegt 4 mm über Stufe bzw. Gehweg, war halbtransparent und schrieb keine
  Tiefe; das additive Zusatzlicht der Stufe darunter (`lit_overlay`, nur bei Dunkelheit; bei Schneefall ebenso die Schneedecke) wurde je nach Blickwinkel danach gezeichnet und
  addierte Sitzfarbe x Licht auf die Menschen. Jetzt zwei Durchgänge (`world.gd`, `event_material("menge")`): Der Hauptdurchgang ist undurchsichtig mit Ausschnitt
  (`ALPHA_SCISSOR_THRESHOLD`, Innenflächen ab Alpha 0,95) und schreibt Tiefe, Zusatzlicht und Schneedecke der Stufe kommen nicht mehr über die Menschen, Nebelbänke und Regen
  liegen richtig davor. Die weichen Teile des Bildes (Schlagschatten, Umriss, Kantenglättung) zeichnet ein `next_pass` aus derselben Datei mit `#define CROWD_SOFT`
  (`Diorama.crowd_soft_shader()`) halbtransparent wie bisher, mit `render_priority` 1 also nach dem Zusatzlicht: Die Schatten liegen auf der beleuchteten Stufe. Alpha kommt nur
  aus dem Ausschnitt der Textur, das Licht ist Albedo x (Lichtkarte über `lamp_lit` + `lamp_floor`), kein Eigenleuchten; am Tag sieht die Menge aus wie vorher. Die
  Mengen-Knoten werfen keinen Schatten (`cast_shadow` aus; er wäre 4 mm über der Stufe unsichtbar und kostete auf dem Handy Zeit im Schattendurchgang).
- **Wasser** (`D_Wasser`: Meer, Becken, Teich, Brunnen, See) bekommt **keinen** Zusatzlicht-Durchgang (`lit_overlay`) mehr. Der Durchgang multiplizierte die Vertexfarbe, und die
  Wassertiefe steckt im Rotkanal: Wasser unter Lampen wurde rot bis magenta. `water.gdshader` liest die Lichtkarte selbst (dunkles Wasser streut nur wenig). Die Umgehung der Themen
  (dunkle Grundfarbe, `R = G = B` in der Vertexfarbe) schadet nicht, ist aber überflüssig; die Tiefe liest nur der Küstenmodus des Wasser-Shaders (`use_depth`, `COLOR.r`).
- **Schanzen und Looping** (Laufzeit-Bauteile aus `build_stunts`) tragen das Zusatzlicht der Randsteine (`lit_overlay_color`); vorher waren sie nachts fast schwarz. Wangen und Stirnseite haben
  jetzt richtige Normalen (nach außen bzw. in Fahrtrichtung). Der Looping ist halbtransparent und nimmt nur wenig Zusatzlicht an; wo keine Lampe in der Nähe steht, bleibt er dunkel wie die Umgebung.
- **Fahnen** (`E_flagge`, `flag.gdshader`) lesen die Lichtkarte am Standort plus eine Grundhelligkeit des Flutlichts (`flood`, skaliert mit `lamp_strength`: Tag 0, Dämmerung 0,6, Nacht 1).
- **Erdflecken der Schotterpiste** (`build_gravel_road`, Strecken mit `runtime_road`) werden nicht über Lücken (`track.in_gap`, z. B. der Graben im Steinbruch) gesetzt.

Prüfen: Nachtbilder von `azure`, `city`, `fair`, `harbor`, `quarry`, `kids` (Dämmerung und Nacht) vorher/nachher; `AT=<Streckenanteil>` richtet die Nahansicht auf Schanzen (fair 0,40, harbor 0,64,
kids 0,53, quarry 0,62) und Looping (kids 0,21, quarry 0,30). Zuschauer: Azure `CX=0,CZ=-20` (Gegentribüne, sechs Ränge) und `CX=0,CZ=20` (Starttribüne), Stadt ohne `AT` (Start). Neue Themen brauchen nichts zu tun; wer eigene Shader mit Lampenlicht schreibt, nimmt `lamp_lit` statt `ALBEDO * lamp_at(...) * k`. Schlammbänder prüfen: quarry 0,66
(östlich des Grabens).

## 3. Straßenarten (`THEME_CFG["road"]`)

| Art | Baut der Kern | Straße im Spiel |
|---|---|---|
| `"city"` | Fahrbahn mit Spurrillen-Vertexfarbe, Linien, Randkante, Randstein, Gehweg, Parkweg, Kreuzungen/Zufahrten | gebacken |
| `"painted"` | Fahrbahn, Linien, flacher rot-weißer Randstein | gebacken |
| `"runtime"` | **nichts** von alledem; Begleitdatei erhält `"runtime_road": true` | das Spiel baut Fahrbahn, Randsteine, Linien, Rampen, Brücken/Lücken, Loopings und Abkürzungen **genau wie ohne Diorama** (`build_asphalt_road`/`build_gravel_road`, `build_stunts`, `build_shortcuts`) |

Bei `city` und `painted` baut das Spiel nur die Fahrbahn nicht selbst; Stützen, Rampen, Loopings (`build_stunts`) und Abkürzungen (`build_shortcuts`) entstehen in jeder Art zur Laufzeit.
Die gebackene Fahrbahn kennt aber weder Lücken noch Höhenprofil. Für Strecken mit Rampen, Lücken, Loopings, Abkürzungen, Höhenprofil oder Gelände
(harbor, fair, quarry, kids, serra, arena) ist **`runtime` der vorgesehene Weg**.

Regeln für `runtime`:

- Der Boden des Dioramas darf die Laufzeit-Fahrbahn nicht überdecken. Die Fahrbahn liegt bei 0,17 (plus Höhenprofil/Rampe), die Randsteine reichen von 0,14 bis 0,285,
  Reifenspuren liegen bei 0,105 und 0,137. Vorgabe `ground_y = 0.08` (wie der Laufzeit-Boden ohne Diorama). Der Kern bricht ab, wenn Netzpunkte
  von `objs_ground` näher als `HW+0,3` an der Mittellinie höher als 0,16 über der Basis des tiefsten nahen Asts liegen (relativ zum Höhenprofil, Abschnitt 4.1).
- Es gibt keine Gehwege, Portale und Zuschauerzonen (Vorgaben `portal`/`crowd` aus), weil sie auf Gehweghöhe 0,30 gebaut würden.
- Bei Strecken mit Geländerelief (`terrain` in der Streckendatei, z. B. serra) überspringt das Spiel `build_terrain`, sobald ein Diorama existiert. Zwei Wege:
  **`runtime_terrain: True`** (empfohlen: Relief wie bisher aus dem Höhenraster; das Thema baut dann *keinen* ebenen Boden, nur Szenerie und Wasser unterhalb), oder das Thema
  backt das Relief selbst (Höhen aus `data["terrain"]`, Straße dazu passend).
- Abkürzungen (`shortcuts` der Streckendatei) baut das Spiel in jeder Art selbst (`build_shortcuts`). Seit 02.10.2026 mit dem Belag der Hauptstraße: gleiche Farbe wie die
  Laufzeit-Fahrbahn (Thema-Farbe `road` bzw. Asphalt/Schotter), gleicher Fahrbahn-Shader mit Nässe, Pfützen, Schnee, Spiegelung und Laternenlicht. (Früher lief die Umlaufrichtung der
  Dreiecke gegen die der Hauptstraße; die Fläche blickte nach unten und erschien fast schwarz. `test_diorama` prüft die Richtung.)
- Offene Strecken (Sprint, `"open": true`): Der Kern rechnet die Mittellinie ohne Schlusssegment; `inside(P)` liefert nie „innen“, Kreuzungen und Zuschauerzonen entfallen.

## 4. Begleitdatei `<id>_layout.json`

| Schlüssel | Pflicht | Inhalt |
|---|---|---|
| `blocked` | ja | gebackene Fahrbahnflächen `[ox, oz, ux, uz, vx, vz, a0, a1, b0, b1]`: Laufzeit-Bauteile darauf entfallen. Bei `runtime` leer |
| `extent` | ja | `[x0, z0, x1, z1]` der Lichttextur und des Dioramas (Laternenlicht, Niederschlag, Nebel) |
| `occluders` | ja | Häuser als Rechtecke für den Laternenschatten (Stadt) |
| `occluder_polys` | nein | Lichtblocker beliebiger Form `[[[x, z], ...], Höhe]` (je Eintrag Ecken und Oberkante in m), Helfer `add_occluder_poly`/`add_occluder_chain`, Abschnitt 2.5 |
| `obstacles` | ja | **Hindernisse der Spielebene** aus `collide_rect`/`collide_circle`; ersetzen die Hindernisse der gebackenen Bausteintypen. Mit `"v": false` (`visible=False`) sind sie unsichtbar: kollidieren, aber kein Klotz in der einfachen Grafikstufe |
| `baked` | ja | gebackene Bausteintypen (`"ai:<modell>"` je Modell) |
| `water_y` | ja | Wasserspiegel oder `null` (nasser Sand im Boden-Shader) |
| `lamps` | ja | zusätzliche Laternen `{x, z, toward[, model]}`; Mast als Hindernis, Licht im Spiel; `model` (z. B. `hafen_laterne`) ersetzt das Standardmodell |
| `lights` | nein | Punktlichter ohne Laterne `{x, z, y, color [r, g, b], energy, range[, omni, glow]}` (Helfer `add_light`, Abschnitt 2.5); gehen wie Laternen in die Lichtkarte, am Tag aus |
| `prop_y` | nein | Bodenhöhe des Dioramas an Standorten von Laufzeit-Bauteilen `[[x, z, y], ...]` (Helfer `set_prop_y`; das Spiel akzeptiert auch `{"<Index in props>": y}`) |
| `prop_light` | nein | Lichtstärke der Laufzeit-Lichter je Bausteintyp der Streckendatei (`floodlight`, `lamp`, `lantern`): Zahl (Stärke) oder `{"energy": …, "reach": …}` (Faktoren auf Stärke und Lichtradius in der Lichtkarte); Leuchtkopf und einfache Grafikstufe bleiben. Setzen im Hook `theme_layout` (Azure: `{"floodlight": {"energy": 0.7, "reach": 0.55}}`), Abschnitt 2.6 |
| `runtime_road` | nein | `true` bei Straßenart `runtime` |
| `runtime_terrain` | nein | `true`: das Spiel baut das Relief weiter selbst |
| `ground_set` | nein | `{"grass": "res://…/gras", "sand": …, "dirt": …}`: Dateinamen der Bodentexturen ohne Endung (`.jpg` oder `.png`), Normalkarte = Name + `_n`. Vorgabe: `res://assets/ground/gras`, `sand`, `erde` |
| `ground_tints`, `ground_scales` | nein | Farbton (`[r, g, b]`) und Kachelgröße (m) je `grass`/`sand`/`dirt` für den Boden-Shader `ground_blend.gdshader` |
| `tints` | nein | `{"D_Name": [r, g, b]}`, über die Tönungen `DIORAMA_TINT` in `world.gd` gelegt (Albedo-Faktor der `D_*`-Materialien, Fahrbahn-Multiplikator) |
| `water` | nein | `{"lagoon": [..], "open": [..], "foam": [..]}`: Farben des Flachwasser-Shaders |
| `water_nodes` | nein | Namenspräfixe der Wasserobjekte, deren Vertexfarbe die Tiefe trägt (Vorgabe `["Meer"]`) |

Ohne die optionalen Schlüssel gilt das bisherige Verhalten. Materialnamen im Diorama: `D_*` (Kern-/Themenmaterial, Tönung und Lichttextur
setzt das Spiel), `K_*` (Bausatz-Oberflächen, Texturen aus `assets/kit`), `E_*` (Rennausstattung); `D_Asphalt`, `D_Asphalt_Strasse` bekommen den
Fahrbahn-Shader, `D_Gelaende` die Bodenmischung (Vertexfarbe: R Helligkeit, G Sand, B Erde), `D_Wasser` den Wasser-Shader.
Für `K_*`/`E_*` ohne Spielmaterial schlägt `tests/test_diorama.gd` an („Platzhalter“).

### 4.1 Höhen (Kern, seit 03.10.2026; Bauplan `docs/dioramen/HOEHEN_PLAN.md`, A6)

Für Strecken mit mehreren Ebenen (Brücke über den Hohlweg, Sprung über den eigenen Sohlenweg, Containerterrasse) kennt der Kern das Höhenprofil der
Streckendatei und schreibt drei weitere Schlüssel:

| Schlüssel | Inhalt |
|---|---|
| `track_hash` | SHA-256 (hex) der Streckendatei beim Bau (immer geschrieben). Das Spiel benutzt Diorama **und** dessen Hindernisse nur, wenn der Hash zur Streckendatei passt, oder wenn der Schlüssel fehlt und die Strecke Fassung `rev` ≤ 1 hat (alte Dioramen). Sonst Laufzeitgrafik und Hindernisse aus den Bausteinen (`push_warning`); `test_diorama` meldet die Strecke mit `WARN` und überspringt sie. Nach jeder Datenänderung also neu bauen |
| `obstacles[].b` | Unterkante (m, absolut) eines Hindernisses: Kontakt nur bei Höhenüberlappung (`z < b + y` und `z + 1,4 > b`, am Boden wie im Flug). Ohne `b` wie bisher (am Boden immer, im Flug überfliegbar ab `z > y`) |
| `supports` | `[[s0, s1], ...]`: Abschnitte, deren Fahrbahn das Diorama trägt (Container, Brückenträger) – das Spiel setzt dort keine Laufzeit-Pfeiler |

Helfer:

- `road_base(s)` = Höhenprofil + Schanze wie `Circuit.surface_z` (bis 16 Stützpunkte Smoothstep, sonst linear; ohne `ROAD_Y`), `base_height(s)`, `ramp_height(s)`, `in_gap(s)`;
  `terrain_y(x, z)` = Gelände wie `Circuit.terrain_height` (bilinear, ohne Raster 0). s = Bogenlänge der Mittellinie dieses Skripts / Gesamtlänge (`S_OF[i]` je Punkt).
- `branch_floor(P)`: je Punkt die tiefste Basis der Äste, deren Mittellinie näher als `HW + 0,3` liegt (ohne Lückenstücke).
- `collide_rect(..., base=None)`, `collide_circle(..., base=None)`: mit `base` entsteht `"b"` (Container unter der Terrasse: `base` 0 und Oberkante ≤ Fahrbahn − 0,05;
  Brückenträger über dem Hohlweg: `base` ≥ Fahrbahn unten + 1,4 – beides zählt im Fahrschlauch nicht).
- `add_supports(s0, s1)`.
- **Namensregel `Deck_*`**: Objekte über einem anderen Ast (Brückenträger, Geländer, Bohlen) heißen `Deck_…`. Das Spiel blendet sie im Zeichenmodus auf 35 % Deckkraft
  (wie die Laufzeit-Fahrbahn über dem anderen Ast), im Rennen sind sie deckend.

`check_runtime_ground` prüft **relativ**: zulässig ist `y ≤ branch_floor + ROAD_Y − 0,01` (auf ebenen Strecken die bisherige Grenze 0,16; unter einer Brücke zählt der
untere Ast). Themen-Ersatzprüfungen (mountain) bleiben gültig. `test_diorama` prüft den Fahrschlauch höhenbewusst (Hindernis mit `b` zählt nicht, wenn seine Oberkante
≤ Fahrbahn − 0,05 oder seine Unterkante ≥ Fahrbahn + 1,4 liegt), `supports`, `track_hash` und `Deck_*` (im Zeichenmodus durchscheinend).

Streckendatei-Bausteine `{"type": "collider", x, z, w, d, rot, b, h, kind, visible}` sind Körper der Spielebene (Bruchwand, Wall, Stift): Das Spiel lädt sie mit und ohne
Diorama, sie werden nie „gebacken“; das Bild folgt ihnen (sichtbar in der einfachen Grafikstufe als Klotz ab `b`, wenn `visible`).

## 5. Importanpassungen und Texturen

`dio_build.ps1` und `build.ps1` passen nach dem Import `.import`-Dateien an und importieren dann neu:
- `game/dioramas/*.jpg` (von Godot neben die `.glb` extrahierte Modelltexturen): WebP statt verlustfrei.
- Shader-Texturen in `assets/kit`, `assets/event`, `assets/ground` und `assets/dio/**` (PNG und JPG): Mipmaps, Grafikkartenkompression (VRAM), Normalkarten `*_n.*` als
  Normalkarte. **Eigene Texturen eines Themas gehören nach `game/assets/dio/<thema>/`** und werden über `ground_set`/`ground_tints` oder als Blender-Material
  (liegt dann in der `.glb`) verwendet.
- Godot schreibt extrahierte Texturen nur neu, wenn sich ihr Inhalt ändert (MD5 in der `.import`); nicht mehr gebrauchte `<id>_*.jpg` bleiben liegen und dürfen gelöscht werden.

## 6. Tests

`game/tests/test_diorama.gd` (Teil von `tools/build.ps1 -Target Test`) prüft die Stadt im Einzelnen und danach **jede Strecke mit `game/dioramas/<id>.glb`**:
Diorama lädt, kein `E_/K_`-Platzhalter ohne Spielmaterial, Begleitdatei vollständig, Fläche deckt die Strecke ab, `runtime_road`/`runtime_terrain` wirken (bei `runtime`
gibt es die Laufzeit-Fahrbahn, sonst keine zweite), **Hindernisse der Begleitdatei halten den Fahrschlauch frei** (Mittellinie im Meterabstand, Halbbreite
`hw(s)` + 0,4 m für feste, + 0,05 m für weiche Hindernisse; in Rampen-, Lücken- und Looping-Zonen zusätzlich 1,0 bzw. 0,5 m; Abkürzungspfade mit ihrer Breite) und
**die KI fährt die Strecke mit allen Hindernissen ohne Zusammenstoß ins Ziel** (`ai_route(1.6)`). Bausteine der Streckendatei, die im Fahrschlauch stehen, werden nur
als `WARN:` gemeldet (z. B. zwei Hafenlaternen auf der Abkürzung von `harbor`); sie lassen sich über `baked: ["lamp"]` plus eigene `lamps` beheben.

Dazu prüft `test_diorama` die Kernfunktionen aus Abschnitt 2.5: die Lichtkarte (hoher Lichtblocker wirft Schatten, 0,4-m-Mauer nicht, Haus wie bisher), `prop_y`, unsichtbare Hindernisse
in der einfachen Grafikstufe (nicht gezeichnet, kollidieren) und je Strecke die optionalen Schlüssel der Begleitdatei: Punktlichter innerhalb der Fläche mit Reichweite, Farbe, Stärke;
gültige Lichtblocker-Polygone; Bodenhöhen nur an Orten von Bausteinen oder Laternen und im Spiel wirksam (Anzahl <= Bausteine + Laternen); Laternenmodelle vorhanden und gebaut;
Abkürzungsfläche blickt wie die Hauptfahrbahn nach oben. Zum Nachtlicht (Abschnitt 2.6) prüft `test_diorama`: das Lichtmodell steckt in den Shadern (`lamp_lit`, kein ungebremstes
`ALBEDO * lamp_at`), Wasserflächen haben keinen Zusatzlicht-Durchgang, jede Schanze hat Zusatzlicht, die Erdflecken der Schotterpiste liegen nie über Lücken. Die Zuschauer
sind ein undurchsichtiger Ausschnitt mit Weichteil-Durchgang (`CROWD_SOFT`, `render_priority` über dem Hauptdurchgang), Alpha nur aus der Textur, Licht nur über `lamp_lit`
und `lamp_floor`, Mengen-Knoten ohne Schattenwurf.

Vollständiger Lauf: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/build.ps1 -Target Test`. Alle Testläufe laufen immer durch (auch wenn einer scheitert);
danach folgt eine Zusammenfassung je Lauf (`OK`/`FEHLER`, RESULT-Zeile, bis zu fünf Fehlerzeilen) und das Skript endet mit Fehler, sobald ein Lauf scheiterte (Exitcode ≠ 0,
Fehlermuster `SCRIPT ERROR`/`ERROR:`/`FAIL:` oder keine RESULT-Zeile).

## 7. Regeln für paralleles Arbeiten

- **Eigene Dateien** je Themen-Agent: `tools/dio_themes/<thema>.py`, `tools/make_<thema>_*.py`, `game/assets/dio/<thema>/**`, die erzeugten Dateien der eigenen Strecke
  `game/dioramas/<id>*`. Nichts anderes ändern, insbesondere **nicht** `game/scripts/world.gd`, `game/scripts/track.gd`, den Kern von `tools/diorama.py`,
  `tools/make_tracks.py`, die Streckendateien `game/tracks/*.json`, `tools/dio_build.ps1`, `tools/build.ps1`, `tools/godot_run.ps1`, die Tests. Fehlt dem Thema etwas
  im Kern, im Bericht melden statt selbst eingreifen.
- **Godot-Läufe laufen nacheinander**: `godot_run.ps1`, `build.ps1` und `dio_build.ps1` halten den benannten Systemmutex `Global\Draw2RaceGodot`. Wer wartet, wartet bis zu
  60 bis 120 Minuten (`-LockWaitMinutes`). Ein abgestürzter Vorbesitzer gibt die Sperre frei. `build.ps1` hält sie von der ersten bis zur letzten Godot-Ausführung.
  Eigene Godot-Aufrufe immer über diese Skripte (nicht `Godot_…exe` direkt), damit nie zwei Läufe gleichzeitig `game/.godot` und `game/dioramas` anfassen.
- **Blender-Läufe sind parallel möglich** (eigener Ordner `.tools/dio_tmp/<id>/`); nur ein Lauf je Strecke gleichzeitig.
- Bilder in `%APPDATA%\Godot\app_userdata\Draw2Race` teilen sich alle: `-Tag` mit dem Themennamen versehen, fremde Bilder nicht löschen.
- `godot_run.ps1 -EnvPairs 'A=1','B=2'` und `dio_build.ps1 -Times day,night` verlangen echte Arrays: aus der PowerShell aufrufen. `dio_build.ps1` teilt eine Zeichenkette `day,night`
  zwar selbst, `godot_run.ps1` nicht (Werte können Kommas enthalten).
- `godot_run.ps1` beendet bei Zeitüberschreitung nur den eigenen Prozess samt Kindern.
- Dateien mit Windows-Zeilenenden (CRLF: `diorama.py`, `build.ps1`, `godot_run.ps1`, GDScript) behalten sie; Themenmodule dürfen LF oder CRLF haben.

## 8. Bekannte Eigenheiten

- Die Küste (`azure`, Thema `coast`) ist Arbeitsstand und wird neu gestaltet. Ihr Diorama hat eine Begleitdatei mit Hindernissen; deshalb erwarten `test_core.gd` (Standardstrecke
  azure, „Überziehen kostet messbar Rundenzeit“) und `test_collision.gd` („Azure: Hindernisse aus den Bausteinen“) einen Zustand ohne Diorama und schlagen an, solange
  `game/dioramas/azure_layout.json` mit Hindernissen existiert. Beide Tests müssen mit der Umgestaltung auf eine Strecke ohne Diorama oder auf die Begleitdatei umgestellt werden.
- `dio_shot.gd`: Umgebungsvariablen `TRACK`, `TIME`, `WEATHER`, `FOG`, `TAG`, `AT` (Streckenanteil der Nahansicht; die Blickhöhe ist die Fahrbahnhöhe dort, daher stimmt der Ausschnitt auch bei
  Strecken mit Höhenprofil wie der Serra), `CX`/`CZ` (freier Weltpunkt, Höhe `CY` oder das Gelände dort).
- Beim Beenden von `dio_shot.gd` auf der Küste meldet Godot gelegentlich „ObjectDB instances leaked at exit“ (unabhängig von der Pipeline, tritt auch mit dem alten `world.gd` auf).
- Gehwege, Randsteine und Portale sitzen auf Höhe 0,30; wer sie in einem Thema mit niedrigerem Boden benutzt, muss die Höhen selbst anpassen.
- Kontrollbilder (`dio_shot.gd`, auch über `dio_build -Shots`): Verliert das Spielfenster beim Aufnehmen den Fokus (anderes Fenster im Vordergrund), pausiert das Spiel und legt
  die „Kurze Boxenpause“ über das Bild. Dann das Bild wiederholen, ohne anderes Fenster zu bedienen, oder in einer Kopie des Skripts nach dem Start `app.resume_game()` aufrufen.
- Die einfache Grafikstufe lässt sich auf dem PC mit `godot_run.ps1 … -Extra '--rendering-method','gl_compatibility'` aufnehmen (Hindernisklötze, Laternenscheiben).

## 9. Nutzungsspuren (seit 03.10.2026; Bauplan `docs/dioramen/HOEHEN_PLAN.md` 2.3 und 8)

Vorab gelegte, **unbunte** Spuren auf jeder Laufzeit-Fahrbahn (`forest`, `quarry`, `harbor`, `fair`, `serra`, `arena`, `kids`): alter Gummiabrieb in Brems-, Rutsch- und
Anfahrzonen, Politur der Ideallinie, Spurrinnen auf Schotter. Nur Darstellung (Premium-Grafik); Simulation, KI und Hindernisse lesen die Karten nie.
Gebackene Fahrbahnen (`azure`, `city`) und Abkürzungen haben keine Karte.

| Teil | Datei | Inhalt |
|---|---|---|
| Erzeuger (Werkzeug, keine Suite) | `game/tests/make_wear.gd` | `tools/godot_run.ps1 -Script res://tests/make_wear.gd -Headless -Timeout 900 -EnvPairs 'TRACK=all'` (oder `TRACK=<id>`), ≈ 20 s je Strecke |
| Karte | `game/assets/wear/<id>.png` | RGBA8 im Streckenraum: Spalte = Seitenversatz −`lat` … +`lat` (0,0625 m), Zeile = Bogenlänge ab s 0 (`step` ≈ 0,25 m). **R** Gummi, **G** Politur, **B** Rinne, A 255 |
| Begleitdatei | `game/assets/wear/<id>.json` | `{version 1, lat, px_lat, step, length, rows, cols, hash, rev, drivers, crashed}`; `hash` = SHA-256 der Streckendatei |
| Import | `game/assets/wear/<id>.png.import` | verlustfrei (`compress/mode=0`), Mipmaps an, `detect_3d/compress_to=0` (keine Grafikkartenkompression) – liegt bei, nicht neu anlegen |
| Anschluss | `world.gd` `apply_wear_map()` | lädt Karte + JSON nur in der Premium-Stufe und nur bei passendem Hash, sonst `wear_strength` 0 und `push_warning` „make_wear neu erzeugen“ |
| Look | `game/assets/road.gdshader` | siehe unten; ohne Karte rechnet der Shader exakt wie vorher |
| Prüfung | `game/tests/test_wear.gd` (Suite) | Karte je Strecke, Maße zu Länge/Breite, Hash aktuell, keine Spuren an Startlinie ±1 m, in Lücken, Looping-Zone, Schanzen und neben der Fahrbahn, keine geschlossene Gummifläche > 1,6 m quer, Rinnen nur auf Schotter, Import, Simulationsskripte ohne Kartenbezug |

**Herkunft der Spuren:** echte Solo-Fahrten mit `RaceVehicle` (trocken) – skill 1,6/1,9/2,3/2,7/3,0 × Spur 1/−1/0,4/0 von den Startplätzen wie im Rennen – und zehn
„Fahrer“ auf einer geglätteten Ideallinie (Gummiband, ±(hw − 1,4) m; langwelliger Versatz σ 0,35 m; Bremspunkt ±3 m; dreifaches Gewicht). Je Rad (Lage wie
`tyre_tracks.gd`) wird gestempelt: **R** schmale Striche (≈ 0,14 m) bei Verzögerung > 3 m/s², Schlupf, Anfahren unter 12 m/s (Hinterräder), an den Startplätzen und bei
Landungen nach einem Flug; nur ein Teil der Episoden hinterlässt einen Strich (15 %, Drift-Arena 45 %), Striche setzen weich ein, dazu ein weicher Schleier (≤ 0,22).
**G** jede Überfahrt (σ 0,10 m). **B** nur auf Schotter: Überfahrtsdichte (σ 0,19 m, in Schlammzonen bis 0,30 m mit 5 m Übergang) plus alte Rinnen bei ±0,95 m.
Alles 1 px weichgezeichnet und normiert; Zeilen mit quer zusammenhängendem dunklem Gummi (R > 0,45 über 1,5 m) werden weich gedämpft. Fest gesät, also reproduzierbar.

**Look** (`road.gdshader`, nur wenn `wear_strength` > 0): Gummi leicht entsättigt („alt, gräulich“) und höchstens 30 % dunkler; frische Laufzeitspuren (`tyre_tracks.gd`) liegen
dunkler und scharf darüber. Politur bis 0,08 weniger Rauheit. Rinne bis 16 % dunkler, 60 % weniger Körnung, falsche Normale aus 3 cm Tiefe (wirkt nur im Tageslicht; das
Laternenlicht ist Emission, nachts bleibt also nur die Abdunklung). Regen: Gummi glänzt etwas (Rauheit −0,10·R, Spiegelung +0,06·R), Pfützen sammeln sich in Rinnen
(`pn += B·0,12`). Schnee bleibt in Rinnen und auf der Ideallinie weniger liegen (`snow·(1 − 0,5·B)·(1 − 0,35·G)`): die Fahrspuren zeichnen sich ab.

**Wann neu erzeugen:** nach **jeder** Änderung einer der sieben Streckendateien (der Hash veraltet sonst; `test_wear` meldet `FAIL … make_wear neu erzeugen`, das Spiel zeigt
keine Spuren). Die `.png.import` bleiben gültig, Godot importiert die neue Karte beim nächsten `build.ps1`/`dio_build.ps1` mit denselben Einstellungen.
Ansicht einer Karte ohne Godot: Zeilen × 4 strecken (dann isotrop), R als Abdunklung auf Grau darstellen.
