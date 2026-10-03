# Höhenniveaus – Bauplan Nachtschicht 02./03.10.2026

Stand 03.10.2026: **umgesetzt** in der Nachtschicht 02./03.10. (Agenten A, B, C1–C3), geprüft und danach nachgebessert – siehe Abschnitt 13
„Stand nach der Prüfung“ am Ende. Die Abschnitte 0–12 bleiben der Bauplan, wie er vor dem Bau galt. Ursprüngliche Grundlage: Entwurfs-Workflow (Journal `wf_84540223-ee4`: Bestand, Entwürfe
Steinbruch/Hafen, Wald/Kinderzimmer, weitere Strecken/Spuren, Machbarkeitskritik) und dessen Proben im lokalen Scratch-Ordner der Sitzung
(`proto\` Wald/Wippe, `kritik_proj\` Feldproben, `lv_tracks\` Prototyp-Strecken, `lv_plan_quarry.png`, `lv_plan_harbor.png`, `plan\*.py` = Geometrie dieses Plans).
Diese Belege sind Scratch-Material (Prototypen in Kopien), keine Projektdateien.

Nutzerwunsch (02.10.2026, sinngemäß): ab dem Wald Höhenniveaus. Steinbruch: Strecke steigt am Bruchrand hoch, ein bis zwei Kurven oben, dann Sprung über
den unteren Teil auf eine abschüssige Rampe, die wieder in die Strecke mündet (Skizze nicht 1:1). Hafen: Rampe hoch auf Container, oben um die Kurve, mit
einem Sprung zurück nach unten. Wald: Teil der Strecke anheben (Steigung, Gefälle). Kinderzimmer: Abkürzung über ein langes Lineal als Wippe auf einem Stift;
es kippt mit dem Gewicht der Autos und durch ein kleines Ungleichgewicht zurück; der angehobene Anfang bedeutet für Nachfolger einen Crash; ein Umweg
umfährt die Wippe. Weitere Spielereien für andere Strecken. Vorab gelegte Nutzungsspuren (Reifenabrieb auf Asphalt, Spurrinnen im Wald).

---

## 0. Kurzfassung: Paket für heute Nacht

| # | Strecke | Element | Kern der Umsetzung |
|---|---|---|---|
| 1 | Steinbruch `quarry` | **Bruchkante Ost (Q1')**: Fahrrampe auf die obere Sohle (5,6 m), zwei Kurven oben, Kicker, Sprung über den eigenen Sohlenweg auf eine Schüttrampe | neue Mittellinie (≈ 500 m), Lücke mit Landelippe, Landung auf Gefälle, Geländeraster, höhenbewusste Hindernisse |
| 2 | Hafen `harbor` | **Containerterrasse Ost (H1')**: Stahlrampe auf zwei Containerlagen (5,2 m), Ecke 3 und 4 oben, Sprung über die Gasse auf eine abwärts führende Stahlrampe | Ecke 5 entfällt (37 m Diagonale), Lippe, Leitplanken, Geländeraster |
| 3 | Wald `forest` | **Hügelacht mit Holzbrücke**: rechte Schleife steigt, Kreuzung wird eine Brücke (4,5 m) über einen Hohlweg, linke Schleife fällt | Höhenprofil, Astbezug, Brückendeck beim Zeichnen durchscheinend, hangbewusste KI |
| 4 | Kinderzimmer `kids` | **Lineal-Wippe** auf einem Filzstift als Abkürzung, Umweg über die Kehre | neues simuliertes Element `Seesaw` (Zustand in der 60-Hz-Schleife), KI-Abkürzungsroute mit Zustandsregel |
| 5 | alle Laufzeit-Fahrbahnen | **Nutzungsspuren vorab**: Gummiabrieb, Politur, Spurrinnen, Landeflecken | Spurenkarte im Streckenraum (offline aus echten KI-Fahrten), Fahrbahn-Shader liest sie, Simulation nicht |
| 6 | Bestand | **Bestandsfehler, die „Gegner kommen ins Ziel“ verletzen** (billig, Pflicht) | Bücherlücke Kinderzimmer (Gegner 1 stürzt heute in jeder Stufe), Sprint-Start Serra (Gegner kommen nie ins Ziel), Nässe/Schnee-Planung, Ausweichen in Schwungzonen |

Weitere Ideen für andere Strecken (Serra-Viadukt, Jahrmarkt-Motodrom, Arena-Parkdeck, Kinder-Steilkurve, Wald-Kuppen mit Lastfaktor) sind **nicht billig** und
werden bewusst verschoben (Abschnitt 12). Heute kommen von den Zusatzideen nur die Bestandsfehler (Zeile 6).

Arbeitsteilung: **(A) Unterbau** allein → **(B) Streckendaten** allein → **(C) Dioramen** parallel: C1 Steinbruch+Hafen(+Arena), C2 Wald+Kinderzimmer,
C3 Nutzungsspuren+übrige Strecken. Dateihoheit: Abschnitt 10.

---

## 1. Abnahmeregeln (gelten für alle Agenten und die Prüfung)

1. **Determinismus:** 60 Hz, alles hängt nur am Simulationszustand (s, Lage, z, vz, Tempo, Wippenwinkel). Darstellung, Kamera und Bildrate ändern nichts (Leitplanke 4).
2. **Bitgleich ohne neue Felder:** Jede Änderung im Unterbau wirkt nur über neue Felder oder nur dort, wo Ebenen wirklich verschieden hoch sind. Messanker:
   Solo-Zeiten `ai_route(2.3, 0)` trocken (`game/tests/golden_times.json`, vor jeder Änderung aufgenommen) bleiben für `azure`, `city`, `arena` bitgleich.
   `RaceVehicle.VERSION` bleibt `bicycle-4`, solange das gilt.
3. **Gegner kommen ins Ziel:** neuer Feldtest (Abschnitt 9) fährt jede Rennstrecke × 3 Herausforderungen so wie `main.gd` (Aufstellung, Spuren, Wetter der
   `conditions`, Ausweichen, Kontakte, Gegner-Turbo) mit einem Spieler-Ersatz `ai_route(2.0, 0)`. Für `forest`, `harbor`, `quarry`, `kids`, `serra` ist jeder
   ausgeschiedene Gegner ein **FAIL**. Für unveränderte Strecken (`azure`, `city`, `fair`) ist ein verbliebener Bestandsfehler nur dann ein `WARN:`, wenn seine
   Ursache im Bericht benannt ist (Ziel bleibt grün).
4. **Folgen aus der Physik:** zu langsam = Aufprall an der Lippe/Absturz, zu schnell = harte oder späte Landung, Abflug in der nächsten Kurve, Bruch der
   Leitplanke; Wippe: Crash an der angehobenen Kante. Keine Skripte, keine Animation des Ergebnisses.
5. **Unveränderte Streckendateien bleiben byte-identisch** (`azure`, `city`, `serra`, `fair`, `arena`); geprüft mit `git diff --stat game/tracks`.
6. **Alle Testsuiten grün** am Ende jeder Phase (`tools/build.ps1 -Target Test`, heute 386 Prüfungen, neue kommen dazu).
7. Nichts committen, nichts herunterladen; fremde ungesicherte Arbeit (z. B. `art/bildvorlagen/bilder/*.png`) bleibt unangetastet.

---

## 2. Datenformat

### 2.1 Streckendatei `game/tracks/<id>.json` (neu oder geändert; alles optional)

| Feld | Bedeutung | Vorgabe / heute |
|---|---|---|
| `rev` | Fassung der Strecke (Geometrie). Bestzeiten/Bestenliste gelten je Fassung; B setzt `2` für forest, harbor, quarry, kids | `1` |
| `gaps[].lip` | Landelippe (m): Liegt die Fahrbahn am Lückenende beim ersten Takt außerhalb der Lücke mehr als `lip` über dem Auto, prallt es an die Stirnseite (Absturz). Bis `lip` wird es wie heute hochgezogen | `3.0` (= heutige Toleranz) |
| `props[]` Typ `"collider"` | unsichtbarer oder einfacher Körper der Spielebene: `{type:"collider", x, z, w, d, rot, b, h, kind:"mauer"|"absperrung", visible:bool}`; Unterkante `b`, Höhe `h` über `b`. Nie „gebacken“, gilt mit und ohne Diorama | – |
| `seesaws` | Wippen: `[{shortcut, at, length, width, thickness, pivot_h, inertia, bias, damping, restitution, rail, edge_ok, edge_wreck, decide, ai}]` (Abschnitt 3, A3) | – |
| `shortcuts` | Format unverändert. **Neue Semantik:** Höhe auf dem Pfad = `terrain_height(pos)` (+ Wippendeck), nicht mehr Profil/Schanzen/Lücken der Hauptstrecke bei gleichem s. Für alle heutigen Strecken numerisch gleich (dort ist beides 0) | – |
| `elevation` | Format unverändert; **muss nach s sortiert** sein (Generator bricht ab, `Circuit.validate()` meldet Fehler). Unsortiert erzeugt eine Stufe, die das Auto auf ~33 m schleudert | – |
| `terrain`, `guardrails`, `ramps`, `loops`, `surfaces` | unverändert; werden jetzt auf geschlossenen Strecken benutzt | – |

### 2.2 Begleitdatei `game/dioramas/<id>_layout.json` (vom Diorama-Kern geschrieben)

| Schlüssel | Bedeutung |
|---|---|
| `track_hash` | SHA-256 (hex) der Streckendatei beim Bau. Spiel: Layout gültig, wenn gleich, oder wenn der Schlüssel fehlt und `rev` ≤ 1. Ungültig → Spiel nutzt weder Diorama noch dessen Hindernisse (Laufzeitgrafik, Hindernisse aus den Bausteinen), `push_warning`. So wird ein veraltetes Diorama nach einer Datenänderung nie still benutzt |
| `obstacles[].b` | Unterkante (m, absolut) eines Hindernisses; Kontakt nur bei Höhenüberlappung (A1 c). Ohne `b` wie heute |
| `supports` | `[[s0, s1], ...]`: Abschnitte, deren Fahrbahn das Diorama trägt (Container, Brücke) → keine Laufzeit-Pfeiler |
| Knotennamen `Deck_*` | Teile über einem anderen Ast (Brückenträger, Geländer, Bohlen). Das Spiel blendet sie im Zeichenmodus auf 35 % Deckkraft |

### 2.3 Spurenkarte `game/assets/wear/<id>.png` + `<id>.json`

PNG RGBA8 im Streckenraum: Spalte = Querversatz (−`lat` … +`lat`, 0,0625 m je Pixel), Zeile = Bogenlänge ab s 0 (0,25 m je Pixel).
Kanäle: **R** Gummi (Abdunklung), **G** Politur/Glanz, **B** Spurrinne (Schotter), **A** frei (255). JSON: `{"version":1, "lat", "px_lat":0.0625, "step":0.25,
"length", "hash"}` (`hash` = SHA-256 der Streckendatei). Fehlt die Karte oder passt der Hash nicht, zeigt das Spiel keine Spuren. Die Simulation liest sie nie.

---

## 3. Unterbau (Agent A) – Reihenfolge und Inhalt

Prioritäten: **P1** Pflicht für das Paket, **P2** sollte heute fertig werden, **P3** nur bei Zeit (sonst im Bericht als offen).

### A0 Messgrundlage (P1, zuerst)
- Vor jeder Änderung: `golden_times.json` (Solo `ai_route(2.3, 0)`, trocken, alle 9 Strecken, 6 Nachkommastellen) und Feldtest-Status (welche Gegner heute
  scheitern, mit s und Ursache) aufnehmen.
- Neu `game/scripts/race_field.gd` (`class_name RaceField`): Aufstellung wie heute (`start_s = −0,012·i`, Spur 0 bzw. ±1,2; Pläne
  `ai_route(RIVAL_SKILL[stage][i−1], RIVAL_LANES[i−1])`; Konstanten wandern aus `main.gd` hierher), Wippen, Takt `step(dt, time, player_boost, phase)` und
  Kontakte; liefert Aufprall-Ereignisse für Funken. **Taktfolge:** Wippen (lesen Lagen des Vortakts) → `update_avoidance` → Fahrzeuge in Indexfolge →
  Kontakte (a < b). Ohne Wippen bitgleich zu heute. Geist: eigene Wippen, eigener Schritt.
- `static func rival_boost(v) -> bool` = heutige Regel (`|sin(progress·τ)| < 0,35 und turbo > 0,25`) **und** `not track.boost_locked(progress)`. `main.gd`
  (Rennen und Ergebnisphase) und alle Tests benutzen nur noch `RaceField`/`rival_boost`.

### A1 Physik (P1; alles bitgleich ohne neue Felder)
- **a) Landung auf Gefälle** (`update_height`): beim Aufsetzen `vz_road = (Boden(s + u·dt/L) − Boden(s)) / dt`; Abschlag
  `velocity *= clamp(1 + (vz − vz_road)·0,01; 0,85; 1)`; danach `vz = vz_road` statt 0. Flache Landung: `vz_road = 0` → wie heute. Beseitigt den zweiten Flug
  auf Gefälle über 3/v (heute 0,4–0,8 s bei 30 %).
- **b) Landelippe:** nur am Lückenende (voriger Takt `in_gap`, jetziger nicht) und nur `ground − z > lip` → Absturz an der Stirnseite (`crashed`, Tempo 0,
  Aufprall-Ereignis für Ton/Funken). Sonst Landung wie heute. Nicht bei gewöhnlichen Landungen (sonst würden schnelle Landungen auf steigender Fläche fälschlich
  zum Wrack, Kritik Punkt 1).
- **c) Hindernisse mit Unterkante:** Hindernis mit `b`: Kontakt nur, wenn `z < b + y` und `z + 1,4 > b` – am Boden und in der Luft. Ohne `b`: wie heute
  (Boden immer; Luft überfliegt bei `z > y`). Bausteintyp `collider` (2.1) → Rechteck mit `b`, `kind`, `v`. `World.build_obstacle_blocks` zeichnet Klötze ab
  `b`. Die Serra (Hindernisse ohne `b`) bleibt dadurch unverändert.
- **d) Astbezug:** `Circuit.query_branch(p, hint)`: globale `query(p)`; nur wenn `|surface_z(q.s) − surface_z(hint)| > 1,0` die nächste Mittellinie im Fenster
  ±0,08 um `hint` (wie `phase_near`). Verwendet für Inselklemme, `surface_at(p, hint)`, `center_distance(p, hint)`, `edge_check` und Drift-Wandprüfung
  (Fahrzeug übergibt `previous_phase`). Ebene Kreuzungen (heutige Wald-Acht, Jahrmarkt) bleiben exakt wie heute.
- **e) Abkürzungen mit eigener Höhe:** auf dem Pfad (`shortcut_at`) Bodenhöhe = `terrain_height(pos)` bzw. Wippendeck (A3), Hangabtrieb aus dieser Höhe bei
  `pos ± 1 m` in Fahrtrichtung, kein `edge_check`. Auf der Hauptstrecke unverändert (`ground_height(previous_phase ± 1/L)`).
- **f) `Circuit.validate()`:** elevation und widths sortiert, keine doppelten s; Fehler per `push_error` (Test prüft).
- **g) Layout-Gültigkeit:** `Circuit.hash` (`FileAccess.get_sha256`), `Circuit.rev`, `layout_valid()` (2.2) in `load_obstacles` und `World.build`.
- **h) Geist/Läufe/Bestenliste:** Geist und Lauf speichern `track_hash`; `spawn_ghost` verlangt Gleichheit (fehlend = nur bei `rev` 1 gültig). In
  `progress.gd` gelten Bestzeit und Bestenliste je `rev` (rev 1 = heutiger Schlüssel); Gold bleibt erhalten.

### A2 KI (P1)
- **a) Sprungfenster** (`Circuit.jump_windows()`, ersetzt den Lückenteil von `momentum_needs`): je Lücke Absprung `s_t = gap.from`; Kicker = Schanze, die
  höchstens 3 m vor `s_t` endet (`vz0 = u·height/length`), sonst `vz0 = u·Steigung` der Fahrbahn. Flugrechnung wie im Fahrzeug (dt 1/60, g, waagrecht nur
  Luftwiderstand 0,010·u², Fortschritt entlang der Mittellinie) für u = 4 … 32 m/s in 0,25er-Schritten; Erfolg = Landung hinter `gap.to` ohne Lippenverstoß und ohne
  `z < base − 3`. `v_min` = kleinster Erfolg; `v_hi` = größtes u, bei dem Landepunkt + 0,35 s·u (Haftungsaufbau) vor der ersten Stelle liegt, deren
  Kurventempo `√(lat_ref/k)` (Stufe 2,3) unter 0,9·Landetempo fällt. Fenster `lo = max(v_min + 2; 1,2·v_min)`, `hi = v_hi − 1,5`; `lo > hi` → Fehler.
- **b) Plan im Anlauf:** nur auf geraden Stücken (k < 1/60) seit dem letzten Kurvenende, höchstens 40 m vor `s_t`: Ist-Ziel `u* = clamp(Plan, lo, hi)`, Plantempo
  mit Reglerversatz `P = u* + (0,010·u*² + u*·(0,09 + Belagwiderstand) + g·Steigung)/2,2`; Erreichbarkeit per 1D-Vorwärtsrechnung des Reglers (Grundauto
  `power` 9, ohne Turbo) aus dem Kurventempo; unerreichbar → `push_error` (Test FAIL; dann ändert B die Geometrie).
- **c) Kurvendeckel** für alle Mindesttempi (auch Looping `√(5gR)·1,15`): nie über `√(lat/k)` des jeweiligen Punkts. Behebt die Bücherlücke (Gegner 1 rutscht heute
  in der R-8-Kurve vor der Schanze neben die Bahn und fällt; Probe mit Deckel 40/40). Reicht der Anlauf nicht, verschiebt B die Schanze (4.4).
- **d) Hangbewusst** (nur mit `elevation`): Rückwärtsdurchlauf `b_eff = max(2; brake + g·k)` (k = Steigung in Fahrtrichtung, bergab negativ); bergab Plan um
  `g·|k|/1,6` senken (Bremsregler liegt im Gefälle sonst konstant darüber). Wald-Probe: 28/40 → 40/40 (5,5-m-Brücke), Hügelacht 39/40 → 40/40.
- **e) Ausweichen** (`update_avoidance`): kein Versatz gegen Autos mit `|Δz| > 1 m`; kein Versatz auf erhöhter Fahrbahn (Basis − Gelände am Rand > 1,0 m) und in
  **Schwungzonen** (25 m vor Absprung/Looping bis Lückenende + 15 m bzw. Looping-Ausfahrt + 10 m; auf Wippen-Abkürzungen). Behebt den Looping-Absturz im Feld
  (Kinderzimmer Stufe 3: 10,1 statt ~16 m/s nach Ausweichen) und den Q1-Feldabsturz von der Sohle.
- **f) Gegner-Turbosperre** `boost_locked(s)`: von `s_t − 40 m` bis `gap.to + 20 m` (Q1: ohne Sperre landet ein Gegner mit Turbo 6 m vor L1 mit 30 % Haftung).
- **g) Nässe/Schnee:** Bestands-Wracks durch Festhängen (Baum, Bank, Gitter, Mauer; Wald Stufe 3, Steinbruch Stufe 2, Jahrmarkt Stufe 3, Hafen Stufe 2/3 im Feld)
  messen und in der Nässeplanung beheben, z. B. weiche Hindernisse in `wet_wall_margins` mitzählen (sie fangen ebenfalls fest) und den Faktor je Haftung staffeln
  (Schnee kleiner als Regen). Trocken bitgleich. Ziel: Feldtest grün.
- **h) Sprint-Start (offene Strecken, Serra):** heute klemmt `at()` alle Gegner auf s 0, ihr Fortschritt hängt 0,012·i hinterher → sie kriechen mit 7 m/s und
  kommen nie ins Ziel. Neu: Startplätze hinter der Linie entlang der Starttangente (4,5 m je Platz, Spur wie bisher), Fortschritt = −Abstand/Länge, solange das Auto
  vor der Linie steht; dort kein Rand-/Inselcheck und kein 3-m-Erholungsdeckel; Spieler unverändert bei s 0. `world.gd` legt bei offenen Strecken ein
  Fahrbahn-Vorfeld von 15 m hinter s 0. (Serra-Gegner werden damit erstmals echte Gegner; B misst nur, ändert die Serra-Datei nicht.)

### A3 Wippe (P1) – neu `game/scripts/seesaw.gd` (`class_name Seesaw`)
- **Zustand** φ (+ = Ausfahrtsende oben), ω. Achse a vom Drehpunkt (+ zur Ausfahrt), quer b. **Deck-Oberseite** `y(a) = pivot_h + a·sin φ`; Anschläge ±Θ mit
  `Θ = asin(pivot_h/(length/2))` (tiefes Ende liegt auf dem Boden). Ruhelage: Einfahrt unten (φ = +Θ), gehalten vom Gegengewicht `bias`.
- **Bewegung:** `φ̈ = g·cos φ·(bias − Σaᵢ)/(inertia + Σaᵢ²) − damping·φ̇`, halbimplizit mit 60 Hz; Anschlag mit Rückprall `restitution`, unter |ω| < 0,05 liegt sie.
  Last = jedes Auto am Boden (nicht im Flug, nicht ausgeschieden, nicht im Ziel), innerhalb der Grundfläche und `|z − y(a)| < 0,35`. Signal `clack` für den Ton.
- **Fahrzeug:** in der Grundfläche und `z ≥ y − 0,35` → Boden = Deck, `vz` = Deckgeschwindigkeit `a·cos φ·ω`; Auffahrstufe > 5 cm: −4 % Tempo und 0,15 s
  Haftungsaufbau (sonst Katapult durch die Steigratenregel). Landen auf dem Deck übernimmt dessen vz.
- **Kante an der Einfahrt** (Höhe h der Einfahrtskante beim Einfahren vom Boden): `h ≤ edge_ok` (0,35) auffahren; `edge_ok < h ≤ edge_wreck` (0,6) harter Stoß,
  Längstempo 0, kein Wrack (das Lineal kommt durch das Gegengewicht zurück); `h > edge_wreck` → `wreck()` (der vom Nutzer gewünschte Crash für Nachfolger).
  Seiten: festes Rechteck für Autos unterhalb der Deckhöhe (Abprall wie Mauer, Wrack über `WRECK_SPEED`). Seitlich oder am hohen Ende herunterfahren = Flug und
  Landung auf dem Boden (normale Physik).
- **Geist** hat eine eigene Wippe, auf der nur er Last ist. Ergebnisphase: Wippen laufen weiter.
- **KI-Route:** `ai_route(skill, lane, shortcut)` liefert eine zweite Route mit **denselben s-Stützstellen** (`place(s, o, sc)`, Einträge mit `sc`), Spur in den
  12 m vor dem Abzweig auf 0, Tempo aus der Pfadkrümmung, auf dem Lineal höchstens 16 m/s. **Entscheidung** beim Überfahren von `decide` (je Runde): Lineal nur,
  wenn `ai` true, skill ≥ 1,9 und `t_frei + Marge < t_Ankunft`. `t_frei` = Maximum aus unbelasteter Rückkehr ab (φ, ω) (Vorwärtsrechnung) und, für jedes Auto vor
  mir, das das Lineal nimmt (KI-Entscheidung oder Spielerplan mit `sc`), dessen Zeit bis zur Ausfahrt + 1,7 s; Marge 0,9 s (skill < 2,7) bzw. 0,5 s; sonst Umweg.
  Routenwechsel tauscht nur das Routen-Array (Cursor bleibt gültig). Prototyp: `scratchpad\proto\scripts\seesaw.gd`, `proto\kids_race2.gd` (0 Kantenunfälle).
- **Notbremse:** `ai: false` in der Streckendatei → KI nimmt immer den Umweg (Stufe 2 der Kritik). B setzt das, falls der Feldtest mit Zustandsregel nicht stabil grün wird.

### A4 Zeichnen (P1, Brücken-Teil P2)
- `world_point`: Fenster `min(0,15; 40 m/Länge)` statt 0,2 (Q1-Abstand der Äste 124 m); Iteration auch bei Wippen/Abkürzungen (Höhe = `draw_height`).
- `Circuit.draw_height(s, sc, p)`: Hauptstrecke `surface_z(s)`, Abkürzung Gelände, Wippe Deck in **Ruhelage**. `draw_route` und Marker benutzen sie.
- Recorder: auf dem Lineal Seitenversatz auf ±`rail` (0,8 m) klemmen.
- Unterer Ast unter einem höheren Ast (Wald-Brücke): Linienstück zusätzlich gestrichelt **ohne Tiefentest**, nur im Zeichenmodus; Deck (Laufzeit-Fahrbahnstück
  über dem anderen Ast als eigenes Netz + Diorama-Knoten `Deck_*`) im Zeichenmodus 35 % Deckkraft, Übergang mit der Kamera; im Rennen deckend.
- P3: **Tempoklammer**: kleiner Winkel 2 m vor jedem Absprung, gefärbt wie die Linie bei `lo` (Leitplanke 11), nur beim Zeichnen.

### A5 Darstellung zur Laufzeit (P2)
- **Pfeiler** (`build_stunts`) nicht, wo `other_branch_distance(p, s) < hw + 1,0`, nicht in `supports`, nicht in Lücken.
- Mittelstriche, Startkaro, Pfeile, Pfützen, Schotterflecken, Pfosten, Laternen, Schlammbänder auf `base_height` bzw. `terrain_height` (heute fest am Boden).
- **Auto nickt** (`place_models`, nur Darstellung): am Boden Nickwinkel aus `(Boden(+1,25 m) − Boden(−1,25 m))/2,5`, im Flug aus vz/u (±25°), weich gefiltert;
  Spieler, Gegner, Geist; Looping unverändert.
- **Absturzdarstellung** endet auf dem Boden darunter (`terrain_height`, unterer Ast), wenn er höchstens 8 m tiefer liegt (Q1: Auto liegt auf dem Sohlenweg).
- **Wippenknoten:** Node3D am Drehpunkt; lädt `res://assets/props/kinder_lineal.glb`, falls vorhanden (Modell: 1 m entlang +x, Oberseite bei y 0, Mitte am
  Drehpunkt; das Spiel skaliert auf length/width/thickness), sonst Quader (Buche) mit dunklen Skalenstrichen; Drehung aus interpoliertem φ (Vor-/Ist-Takt).
  Das Linienstück auf dem Lineal ist im Rennen Kindknoten (kippt mit).
- Einfache Grafikstufe: Leitplanken (`guardrails`) als schmales Band, Collider (`visible`) als Klotz ab `b`.
- **Spurenkarten-Anschluss:** `road_strip` der Hauptfahrbahn bekommt UV = (Versatz m, s·Länge m); `world.gd` Funktion `apply_wear_map()` lädt Karte+JSON
  (2.3), prüft Hash, setzt im Fahrbahn-Shader `wear_map`, `wear_strength` (0 ohne Karte), `wear_lat`, `wear_len`; `road.gdshader` tastet ab und wendet eine
  neutrale Grundwirkung an (R dunkelt höchstens 30 %, G ≤ 8 % Glanz, B dunkelt Schotter). Nur Premium. Den Look stimmt C3 ab.
- P3: Seitenschürzen an erhöhter Laufzeit-Fahrbahn ohne Diorama; Ampel am Wippenabzweig (grün, wenn Kante < 0,35 m und 1,5 s frei vorhergesagt; Modell
  `kinder_ampel.glb`, falls vorhanden); Ton „Klack“ am Anschlag (vorhandener Landestoß leise); Hinweistext „Lineal nicht direkt hinter einem Gegner“.

### A6 Diorama-Kern (P1) – `tools/diorama.py`
- `road_base(s)` und `terrain_y(x, z)`: Port von `base_height`+`ramp_height` (≤ 16 Stützpunkte Smoothstep, sonst linear; Lücken) und `terrain_height` (bilinear).
- `check_runtime_ground` **relativ**: zulässig ist `y ≤ min(Basis der Äste, deren Mittellinie näher als HW + 0,3 liegt, ohne Lückenstücke) + ROAD_Y − 0,01`.
  Themen-Ersatzprüfungen (mountain) bleiben gültig.
- `collide_rect(..., base=None)`, `collide_circle(..., base=None)` → `"b"`; `add_supports(s0, s1)` → `"supports"`; `"track_hash"`; Namensregel `Deck_*` dokumentieren.
- `test_diorama.gd`: Fahrschlauch-Prüfung höhenbewusst (Hindernis mit `b` zählt nicht, wenn Oberkante ≤ Fahrbahn − 0,05 oder Unterkante ≥ Fahrbahn + 1,4),
  `supports` gültig, `track_hash` passt (sonst `WARN`, Strecke übersprungen), `Deck_*` erlaubt.
- `docs/dioramen/README.md`: neuer Abschnitt „Höhen (Kern)“ mit 2.2 und den Helfern.

### A7 Tests (P1) – Abschnitt 9; Suiten in `tools/build.ps1` eintragen; volle Suite am Ende.

---

## 4. Strecken (Agent B)

s-Werte sind Richtwerte aus `scratchpad\plan\geo.py`/`harbor.py`/`kids.py` (Generator-Abtastung); **maßgeblich sind Meter und Koordinaten**, B rechnet s im
Generator (`s_of`, Meter/Länge). Höhen in m über der Grubensohle bzw. dem Boden.

### 4.1 Steinbruch – Q1' „Bruchkante Ost“ (`rev` 2)
Mittellinie (Spielkoordinaten, ohne Spiegelung), Ecken/Radien: `(-70,-40) R9, (-65,30) R9, (45,30) R8, (66,8) R7, (62,-24) R9, (-50,-24) R10, (-50,-4) R9,
(-2,-4) R9, (-2,-40) R8`. Länge ≈ 499,8 m (heute 362,7), 2 Runden. Gegenüber dem Entwurf Q1 liegen L1/L2 bei x = −50 statt −40 (Kritik: ≥ 15 m Auslauf).

| Abschnitt | Meter (s ≈) | Höhe / Element |
|---|---|---|
| Start/Ziel West | 0 (0) bei (−67,5 \| −5) | 0 |
| Looping | 116,8 (0,2337) bei (20 \| 30) | R 3,2 (unverändertes Element) |
| Fahrrampe | 145 → 195 (0,290 → 0,390), durch Ecke 3 (66 \| 8) | 0 → 5,6; Ø 11,2 %, max 16,8 % |
| Obere Sohle | 195 → 259,3: Ecke 4 (62 \| −24) 194,6–209,8, dann Bermenstraße z = −24 nach Westen | 5,6 |
| Kicker | 254,3 → 259,3 (0,5088 → 0,5188), x 8,5 → 3,5 | `ramps {length 5, height 1.0}` (11,3°) |
| Lücke | 259,3 → 270,3 (0,5188 → 0,5408), x 3,5 → −7,5 | 11 m, `lip 0.4`; darunter der Sohlenweg |
| Landung | Lippe 270,3 (x −7,5) → Rampenfuß 286,8 (0,5738, x −24) | 3,0 → 0; Schüttrampe Ø 18 %, max 27 % (flach an Lippe und Fuß) |
| Auslauf | 286,8 → 302,8 (L1-Beginn) | 16 m eben |
| Kehrschleife | L1 (−50 \| −24), L2 (−50 \| −4), Ostweg z = −4, L3 (−2 \| −4) | 0 |
| Sohlenweg | x = −2 von z −4 nach −40; Kreuzung unter dem Sprung bei 388,9 (s ≈ 0,778), 90°, Δs 0,248 | 0; Matsch beidseits s ≈ 0,757–0,792 |
| Nordstraße | L4 (−2 \| −40), z = −40 nach Westen; Kicker 2 bei x = −45 (444,3, s ≈ 0,889) | `ramps {length 4, height 0.8}` wie heute |

- `elevation` (m → s): `[[145,0],[195,5.6],[259.3,5.6],[270.3,3.0],[286.8,0]]` ≈ `[[0.2901,0],[0.3902,5.6],[0.5188,5.6],[0.5408,3.0],[0.5738,0]]` (5 Punkte, Smoothstep).
- `terrain` (Zelle 2 m): Sohle 0; **obere Sohle 5,6** für x ≥ 3,5 und z ≤ −19 (1,5 m über den Nordrand der Bermenstraße hinaus); **Damm** = Fahrbahnhöhe bis
  hw + 1,5 von der Mittellinie entlang Fahrrampe und Schüttrampe; unter der Lücke 0; **Sohlenweg-Korridor** (≤ hw + 0,8 vom unteren Ast) immer 0 (senkrechte
  Bruchwand, keine Böschung).
- `collider`-Bausteine: **Bruchwand** (unsichtbar, `mauer`, b 0, h 5,5) in der Grube vor der Plateaukante: x 2,5…3,5 für z −44…−19 und z −19…−18 für x 3,5…50 (endet vor Ecke 4, deren Innenseite der Wall schützt);
  **Sicherheitswall** (sichtbar, `absperrung`, b = Fahrbahnhöhe, h 1,0) 3,7…4,5 m neben der Mittellinie auf der Grubenseite der Fahrrampe (wo Basis > 1,5 m) und am
  Nordrand der Bermenstraße bis 3 m vor dem Kicker, in Stücken ≤ 4 m; **Felswand Ost** (unsichtbar, `mauer`, b 0, h 12) 5,0…6,0 m außen an Fahrrampe, Ecke 3, Ecke 4.
  An der Kante (letzte 3 m und Kicker) offen.
- Bausteine: Kipper (−22 \| 12), Brecher (80 \| −30), Bagger (20 \| 6); Kieshaufen neu (Freihaltung ≥ 1,5 m); das Wasser des alten Grabens entfällt; Felswand-Modelle
  bei z = ±58 bleiben. `surfaces`: alte Zone 0,55–0,62 entfällt.
- **Tempofenster** (waagrechtes Tempo an der Kante; Belege Q1-Probe): < ≈ 10,7 m/s Aufprall an der Lippe (Absturz); 10,7–14 Landung 0–5 m hinter der Lippe;
  14–19 Landung 5–16 m auf der Schüttrampe (weich, relatives vz klein); ≥ 19,5 (nur mit Turbo; Schotter ohne Turbo ≈ 17) hinter dem Rampenfuß, −12 %, 30 % Haftung
  16 m vor L1. KI-Ziel 13–14 m/s. Flughöhe über dem Sohlenweg 6,4–7,2 m (keine Berührung mit Autos darunter).
- Gegner-Turbosperre ≈ 214–290 m. Erwartete Renndauer ≈ 97–103 s (heute 73–83 s).
- Rückfall bei rotem Feldtest: Kicker 5/1,2; L1/L2 auf x = −52; Lücke 10 m.

### 4.2 Hafen – H1' „Containerterrasse Ost“ (`rev` 2)
Generatorkoordinaten (vor `mirror_z`; im Spiel ist z negiert, s gleich). **Ecke 5 (40 \| −32) entfällt**: Ecken
`[(-60,25),(10,25),(30,5),(55,5),(62,-15),(15,-32),(0,-15),(-20,-30),(-52,-30),(-66,-10)]`, Radien `[9,8,7,6,8,6,6,7,8,9]`, Länge ≈ 322,0 m (heute 327,1).
Ecke 4 dreht dann 89° (R 8), Ecke 6 69° (R 6); dazwischen 37 m Gerade (113–150 m). So liegt keine Kurve mehr in Landung/Gefälle (Kritik: Ecke 5 vereinte Kurve,
29 % Gefälle und Haftungsaufbau; Feldwrack bei s 0,423).

| Abschnitt | Meter (s ≈) | Höhe / Element |
|---|---|---|
| Auffahrt (Stahlrampe auf gestuften Containern) | 37 → 83 (0,115 → 0,258) durch Ecke-1-Ausgang, Diagonale, Ecke 2 (45°, 60–67) | 0 → 5,2; Ø 11,3 %, max 17 % |
| Terrasse (zwei Containerlagen) | 83 → 123: Ecke 3 (55 \| 5) R6 83–92, Ecke 4 (62 \| −15) R8 99–113, 10 m Anlauf | 5,2 |
| Kante, ohne Kicker | 123 (0,3820) | – |
| Gasse (Lücke) | 123 → 128,5 (0,3820 → 0,3991) | 5,5 m, `lip 0.4` |
| Landerampe (Stahl) | Lippe 128,5 → Fuß 147 (0,4565) | 2,6 → 0; Ø 14 %, max 21 %; danach 3 m eben bis Ecke 6 (150) |

- `elevation` (m): `[[37,0],[83,5.2],[123,5.2],[128.5,2.6],[147,0]]` ≈ `[[0.1149,0],[0.2578,5.2],[0.3820,5.2],[0.3991,2.6],[0.4565,0]]`.
- `guardrails` beidseits 58–123 m (s ≈ 0,180–0,382; ab 2,5 m Höhe; brechen ab 9 m/s quer → Absturz).
- `terrain` (Zelle 2 m): Containerblock = Fahrbahnhöhe bis hw + 1,0 von der Mittellinie für 37–147 m außer der Gasse; sonst 0. Keine Laufzeit-Bausteine im Block + 1 m;
  Laternen am Hochabschnitt bleiben am Boden (5,8 m Abstand). Abkürzung (ab ≈ 155 m) und Beckensprung bleiben (s rechnet der Generator neu).
- **Tempofenster** (Kante): sauber ab 7,6 m/s (mit Lippe 0,4 ab 7,0); sicher 9,5–12 (Landung 1–4 m hinter der Lippe auf dem flachen Rampenkopf, ≈ −6 %);
  über ≈ 15 m/s (Turbo) Landung weit unten, Ecke 6 kaum zu halten (Physik). Natürliche Ausfahrt aus Ecke 4 ≈ 9–10 m/s; KI-Ziel 10–11.
- Gegner-Turbosperre ≈ 83–148 m. Renndauer ≈ 55–62 s.
- Rückfall: Ecke 6 R 8 (Bausteine prüfen) oder Landerampe bis 149 m. Falls Ecke 5 doch bleiben muss: R 12, Rampe durch die Kurve, ≥ 15 m Auslauf vor Ecke 6.

### 4.3 Wald – Hügelacht mit Holzbrücke (`rev` 2)
Mittellinie unverändert (Lemniskate, 195,5 m). Untertitel neu, z. B. „Schotterpiste über den Hügel – und eine Holzbrücke über den Hohlweg.“

- `elevation` (s): `[[0.07,1.4],[0.24,3.6],[0.35,4.5],[0.455,4.5],[0.52,3.9],[0.57,3.4],[0.74,0.8],[0.86,0.0],[0.98,0.0]]` (9 Punkte, Smoothstep; `[0.52,3.9]`
  aus der Kritik: Gefälle endet vor der Talkehre). Max ≈ 11,9 % Steigung, 11,8 % Gefälle; kleinster Kuppen-/Wannenradius ≈ 41 m → kein Abheben (5-cm-Regel);
  Hangabtrieb ≤ 1,15 m/s². Rechte Schleife (mit Start) steigt, linke fällt. Startaufstellung (s 0,964–1,0) eben auf 0.
- Kreuzung: oberer Ast s ≈ 0,403 auf 4,5 m (Plateau 0,35–0,455), unterer Ast s ≈ 0,903 auf 0 (eben 0,86–0,98), Winkel 98°, Δs 0,5.
- Brücke s 0,357–0,449 (≈ 18 m; Diorama setzt `supports`). `guardrails` beidseits 0,350–0,460.
- `terrain` (Zelle 2 m): Höhe des nächsten Asts, weich gemischt (Gewicht 1/d²); Korridor des unteren Asts (≤ hw + 0,8) = dessen Höhe; Kappung
  `Gelände ≤ h_unten + (d − 4,3)` (Böschung 1:1) → Hohlweg mit ≈ 8,8 m halber Breite an der Kreuzung, Spannweite ≈ 18 m ohne Pfeiler. Ebenen (waagrechte
  Mulden/Terrassen) für Teich (19 \| 0), Hütte (−20 \| 1), Tribüne (0 \| 24).
- `collider` Hohlwegwände (unsichtbar, `mauer`, b 0, h 3,0) bei hw + 1,6 … hw + 2,6 vom unteren Ast, s 0,87–0,94, beidseits (unter der Brücke liegen sie 1,5 m unter dem Deck).
- Schneestufe: an der Außenseite der Talkehre s 0,56–0,61 alle Bäume, Bänke, Masten näher als hw + 6 m entfernen (Kritik: dort hängen heute alle drei Gegner fest).
- Kein Lastfaktor, kein eigener Holzbelag (verschoben).

### 4.4 Kinderzimmer – Lineal-Wippe (`rev` 2)
Mittellinie unverändert (334,0 m). Schanze s 0,5239, Bücherlücke 0,5418–0,5598 bleiben; nur wenn der Kurvendeckel (A2 c) nicht reicht, rückt die Schanze 6–8 m später.

- `shortcuts` neu: `{from ≈ 0.608 (32,1 | −30,7), to ≈ 0.81–0.825, width 4.0, surface "asphalt"}`; Pfad: gerade Sehne (≈ 57 m, tangential aus der Kurve bei (32 \| −32)) und,
  falls `to` > 0,81, ein Einlaufbogen, sodass die Einmündung ≥ 10 m hinter dem Ausgang der Kurve bei (−24 \| −36) liegt (Kritik). Umweg = Hauptstrecke über die
  Kehre (4 \| −14) R 6 (≈ 67–73 m, KI ≈ 7,8 m/s).
- `seesaws`: `[{shortcut 0, at <Pfadmeter des Drehpunkts ≈ 28, dort ist die Sehne ≈ 14,5 m von der Hauptbahn entfernt>, length 24, width 4.0, thickness 0.3,
  pivot_h 1.1, inertia 26, bias 1.0, damping 0.4, restitution 0.2, rail 0.8, edge_ok 0.35, edge_wreck 0.6, decide 0.515, ai true}]`. Θ ≈ 5,3°, Enden 0 bzw. 2,2 m.
  Linealecken ≥ 1,5 m vom Fahrbahnrand der Hauptstrecke (Generator prüft; sonst kürzer). `inertia` ≈ 0,045·length² m² (30-m-Prototyp: 40).
- `collider` Stift (`mauer`, b 0, h 0,75): je ein Rechteck an den 1,5 m über die Linealbreite hinausragenden Stiftenden (Stift Ø 0,8 m quer zum Lineal, Länge 7 m).
- Zeitgewinn der KI (skill 2,3, freies Lineal) Ziel **0,8–1,5 s je Runde** (Prototyp mit 30 m/57-m-Sehne: ≈ 2 s – zu viel). Stellschrauben: `pivot_h` 1,1–1,5,
  `length` 24–30, Einlaufbogen, Lage der Einmündung.
- Verhalten (Prototyp, 30 m): Plan 10–20 m/s kippt 0,25–0,3 s nach dem Drehpunkt an, liegt 0,65 s später um, Ausfahrtsende beim Verlassen ≤ 0,07 m; Plan ≥ 25 m/s
  kleiner Hüpfer am Ende; Einfahrtskante 0,8–1,2 s nach dem Verlassen wieder < 0,35 m. Gefährlich ist ein Abstand von ≈ 1,4–3,6 s hinter einem Vordermann.

### 4.5 Unverändert
`azure`, `city`, `serra`, `fair`, `arena`: Dateien byte-identisch. Ihre KI-Zeiten können sich durch A2 (Sprungfenster, Sprint-Start, Nässe) ändern; B weist sie aus.

### 4.6 Ablauf B
1. Bericht von A lesen; Helfer in `make_tracks.py`: Meter → s, `terrain_from_roads(...)` (Damm, Plateaus, Korridor, Böschung 1:1 oder senkrecht), `collider(...)`,
   Leitplanken aus Höhenbereichen, Abbruch bei unsortierter `elevation`, Freihaltung der Bausteine gegen alle Äste.
2. `quarry()`, `harbor()`, `forest()`, `kids()` nach 4.1–4.4; Formatkopf des Generators ergänzen. Alle Dateien neu erzeugen, unveränderte byte-identisch prüfen.
3. Feldtest und Abstimmung (höchstens ~6 Durchgänge je Strecke): alle Gegner aller Stufen im Ziel; Sprungtempo der KI innerhalb des Fensters; Gegnerzeiten je Stufe
   ausweisen (Faustregel Ø-Tempo des Stufe-3-Siegers: Schotter 9–11 m/s, Asphalt 10–13 m/s wie heute); Gold bleibt der Sieg über die Gegner.
4. Dioramen: je geänderte Strecke **einmal** `dio_build.ps1` mit dem alten Themenmodul. Vorher `game/dioramas/<id>*` in den Scratch-Ordner sichern; scheitert der Bau
   oder `test_diorama`, die Sicherung zurückkopieren (sie ist dann wegen `rev` 2 ohne `track_hash` ungültig, das Spiel zeigt Laufzeitgrafik) und im Bericht melden.
5. Bilder (`dio_shot.gd`, Tag und Nacht, Tag `_b`): quarry AT 0,34/0,51/0,54/0,778; harbor AT 0,19/0,33/0,39/0,44; forest AT 0,24/0,40/0,90; kids AT 0,55 und
   CX/CZ am Drehpunkt. Spurtreue der Laufzeit-Fahrbahn auf Höhe, keine Pfeiler im Hohlweg/Sohlenweg.
6. Volle Suite. Spurabhängige Erwartungen in bestehenden Tests darf B anpassen (begründet), Unterbau-Logik nur mit belegtem Fehler und kleinem Eingriff.

---

## 5. KI-Strategie (Übersicht)

| Element | Regel |
|---|---|
| Lücke/Sprung | Fenster `[lo, hi]` aus ballistischer Vorausrechnung (A2 a), Plan nur im geraden Anlauf mit Reglerversatz (A2 b), Kurvendeckel; Turbosperre; kein Ausweichen |
| Looping | wie heute √(5gR)·1,15, jetzt mit Kurvendeckel; kein Ausweichen in der Schwungzone |
| Gefälle/Steigung | hangbewusster Bremsdurchlauf und Plan bergab abgesenkt (A2 d) |
| erhöhte Fahrbahn | kein Ausweichversatz; Leitplanken/Wall verhindern Abstürze bei normalem Fahren |
| Kreuzung über/unter | Astbezug (A1 d), Autos mit \|Δz\| > 1 m berühren sich nicht und weichen sich nicht aus |
| Wippe | Abkürzungsroute + Zustandsregel bei `decide`, Rückfall `ai: false` |
| Abkürzungen Hafen | wie heute (KI fährt sie nicht; verschoben) |
| Nässe/Schnee | Planung an Hindernissen vorsichtiger (A2 g), Feldtest grün |

---

## 6. Zeichenregeln

1. Linienkodierung bleibt Leitplanke 11 (langsam breit/grün, schnell schmal/rot). Nutzungsspuren sind **unbunt**, kein Grün, Gelb oder Rot.
2. Gezeichnet wird in der Draufsicht; der Fingerpunkt wird auf die Fahrbahnhöhe des eigenen Asts projiziert (`world_point`, Fenster 40 m).
3. Kreuzungen: unsichtbare Zeichenbrücke über `phase_near` (Recorder-Fenster 0,15); jede Kreuzung braucht Δs ≥ 0,2 (Q1 0,248; Wald 0,5).
4. Über Lücken läuft die Linie durch (auf `surface_z`, sie fällt sichtbar zur Lippe ab). Tore in Lücken sind unkritisch.
5. Brücke Wald: im Zeichenmodus Deck 35 % und untere Linie gestrichelt durchscheinend; im Rennen deckend (Auto ≈ 1 s unter der Brücke).
6. Wippe: Linie folgt dem Abkürzungspfad, auf dem Lineal mittig eingerastet (±0,8 m), Höhe der Ruhelage; im Rennen kippt das Linienstück mit dem Lineal.
7. P3: Tempoklammer am Absprung zeigt die Mindestfarbe.

---

## 7. Darstellung je Diorama-Thema (Agenten C)

Allgemein: nichts schwebt, kein Z-Flackern, Boden immer unter der Laufzeit-Fahrbahn (relative Kernprüfung), Hindernisse passen zum Bild (Collider der Streckendatei
sind maßgeblich, das Bild folgt ihnen), Relief nahe der Fahrbahn = `data["terrain"]` (± 0,1 m innerhalb hw + 3), Nacht plausibel (Lichtkarte auf befahrenen Flächen
0,2–0,4). Höchstens 6 `dio_build`-Läufe je Strecke, eindeutiger `-Tag`. Laufzeit-Bausteine stehen dank `terrain` schon auf Geländehöhe: **kein**
`set_prop_heights` für dieselben Bausteine (README 2.5).

**C1 Steinbruch** (`quarry.py`, zuerst): Relief für das neue Layout; obere Sohle als echte Abbausohle (Bruchwand mit Bohrlochpfeifen, Bankstufe auf halber Höhe nur
abseits der Fahrbahn); Fahrrampe als Damm mit Sicherheitswall aus Haufwerk (Lage wie Collider); Felswand Ost; Holzkicker mit Bruchstein umschüttet, Leitkegel und
Schild „Sprengbereich“ an der Kante (außerhalb des Fahrschlauchs); Schüttkegel aus Kalkschotter mit verkratzter Stahlkante an der Lippe; Sohlenweg nass mit
Pumpensumpf (vorhandene Motorpumpe); Felsriegel (unsichtbar) für das neue Layout neu; Felswand-Modelle z = ±58 wie bisher; Lichter an Kante und Kreuzung.
**C1 Hafen** (`harbor.py`): Terrasse aus zwei Lagen 40-Fuß-Container (12,2 × 2,44 × 2,59 m, Dächer ≤ Fahrbahn − 0,05) im Footprint des Geländerasters; gestufte
Containertürme unter der Stahlrampe (Riffelblech, gelbe Kanten); gelbe Geländer entlang der `guardrails`; schwarz-gelbe Absprungkante; Gasse mit Portalhubwagen;
Landerampe aus Stahl mit verkratzter Lippe; Lichter auf der Terrasse (`add_light`/`add_lamp`); `add_supports` für 0,115–0,4565; keine Container-Hindernisse unter
oder an der Terrassenfahrbahn; Containerfelder um den neuen Footprint umplanen (Ecke 5 entfällt). **Arena** (gleiches Thema) muss weiter bauen und bestehen.

**C2 Wald** (`forest.py`): alles relativ zur Geländehöhe (Boden aus `data["terrain"]`, Saum, Schlamm, Pfützen, Radspuren, Streugut, gebackene Bäume, Hütte auf Terrasse,
Teich als ebene Mulde, Tribüne); Hohlweg mit Erdwänden, freiliegenden Wurzeln, Farn/Moos an der Krone, Steinen, feuchter dunkler Sohle (Lage wie Hohlweg-Collider);
Holzbrücke: zwei Feldstein-Widerlager auf den Böschungskronen, zwei Rundholz-Längsträger mit Moos, Querbohlen sichtbar an den Rändern (die Laufzeit-Schotterfahrbahn
liegt oben: Schotter auf Bohlen), Rundholzgeländer (Pfosten alle 2 m, zwei Holme) entlang der `guardrails`, Laterne am Brückenkopf; alle Brückenteile über dem unteren
Ast als `Deck_*`; `add_supports(0.357, 0.449)`; Dreiecke ≤ ≈ 220 k.
**C2 Kinderzimmer** (`kids.py`): grüner Filzstift (Ø 0,8 m, 7 m, Kappe und Spitze) gebacken mit Umgebungsverdeckung an den Collidern; Korridor ±3 m entlang des
Abkürzungspfads frei; Kratzspuren im Parkett unter den Linealenden. Neues Werkzeug `tools/make_kids_ruler.py` → `game/assets/props/kinder_lineal.glb` (Maße wie in A5
normiert): Buche, schwarze Zentimeterskala 0–60 mit von oben lesbaren Ziffern, rote Endkappen, rot-weiß schraffierte Stirnseite am Einfahrtsende, abgeschrägte
Enden (tiefes Ende liegt plan auf), rote Knetkugel als Gegengewicht an der Seitenkante des Einfahrtsendes. Optional `kinder_ampel.glb`.

**C3 Nutzungsspuren und übrige Strecken:** siehe Abschnitt 8; dazu Serra: sichtbares Startvorfeld (`mountain.py`, falls das Gelände hinter s 0 die
Laufzeit-Fahrbahn verdeckt; Bild der Startaufstellung). Fair, Azure, Stadt: nur prüfen, dass nichts kaputtging.

---

## 8. Nutzungsspuren (C3; Anschluss im Spiel A5)

- **Erzeuger** `game/tests/make_wear.gd` (Werkzeug, keine Suite; Aufruf über `godot_run.ps1`, `TRACK=<id>|all`): echte Solo-Fahrten mit `RaceVehicle` (trocken,
  `weather_grip` 1) für skill 1,6/1,9/2,3/2,7/3,0 × Spur 1/−1/0,4/0 plus eine geglättete Ideallinie (minimale Krümmung innerhalb ±(hw − 1,2), mit langwelligem
  Versatz σ 0,35 m und Bremspunkt ±3 m für zehn „Fahrer“, viel Gewicht, sonst entstehen drei künstliche Streifen). Je Rad (Spurweite wie `tyre_tracks.gd`) in die
  Karte stempeln: **R** bei Verzögerung > 3 m/s², Schlupf, Anfahren < 12 m/s, Startplätze, Landungen (echte Landepunkte hinter Lücken); **G** jede Überfahrt
  (Politur, ≤ 8 %); **B** auf Schotter Überfahrtsdichte (Rinnen ±0,5 m um die Radspur, in Schlammzonen breiter), dazu alte Forstrinnen ±0,95 m. Ausgespart: Lücken,
  Looping-Zone, Holzschanzen, Start-/Ziellinie ±1 m. 1 px weichzeichnen, normieren, PNG + JSON schreiben.
- **Strecken:** alle mit Laufzeit-Fahrbahn: forest, quarry (Schotter), harbor, fair, serra, arena, kids (Asphalt/Kunststoff). Abkürzungen und gebackene Fahrbahnen
  (azure, city) bleiben heute ohne Karte.
- **Look** (`road.gdshader`, nur Premium): unbunt; Gummi höchstens 30 % dunkler, Striche ≤ 0,2 m, keine geschlossene Fläche > 1,6 m; alt = weich und gräulich, frische
  Laufzeitspuren bleiben dunkler und scharf darüber; Regen: Gummi glänzt etwas, Pfützen sammeln sich in Rinnen (`pn += B·0,12`); Schnee: weniger auf Politur und in
  Rinnen (`snow·(1 − 0,5·B)`); Schotterrinnen: verdichtet (weniger Körnung), Tag mit falscher Normale aus B (optisch ≤ 3 cm), Nacht reine Abdunklung.
- **Import:** verlustfrei, Mipmaps an, kein Wechsel auf VRAM-Kompression (`.import` nach dem ersten Import anpassen, neu importieren).
- **Neue Suite** `game/tests/test_wear.gd` (in `build.ps1` eintragen): Karte je Laufzeit-Strecke vorhanden, Maße passen zu Länge/Breite, Hash aktuell
  (sonst FAIL „make_wear neu erzeugen“), keine Spuren in Lücken/Looping-Zone/Startlinie, Höchstwerte, `track.gd`/`vehicle.gd` lesen keine Karte.

---

## 9. Tests (neu oder erweitert)

**A – `game/tests/test_heights.gd` (neue Suite)**, Prüfstrecken als JSON unter `game/tests/tracks/` (neu):
1. Landung auf 30 % Gefälle ohne zweiten Flug; Abschlag nach relativem vz; flache Landung bitgleich zur Referenz.
2. Lippe 0,4: zu langsam → Absturz am Lückenende; schnell genug → Landung; ohne `lip` wie heute (Hochziehen bis 3 m).
3. Hindernis mit `b`: Auto auf dem Plateau fährt darüber, Auto darunter prallt; Flugprüfung absolut; Hindernisse ohne `b` unverändert (Serra-Zeit bitgleich).
4. Astbezug: Auto neben dem oberen Ast stürzt über tiefem Gelände ab, Auto auf dem unteren Ast darunter nicht; `surface_at` am unteren Ast liefert dessen Belag; ebene Kreuzung unverändert.
5. Ausweichen ignoriert Autos mit \|Δz\| > 1 m; kein Versatz in Schwungzonen und auf erhöhter Fahrbahn; `rival_boost` in gesperrten Zonen false.
6. Wippe: Ruhelage; Kippen unter Last nach dem Drehpunkt; Rückkehr ohne Last ≤ 1,5 s; Nachfolger bei Kante > 0,6 → Wrack, 0,35–0,6 → Stillstand ohne Wrack, ≤ 0,35 → fährt auf;
   seitlich herunter → Flug und Landung ohne Absturz; zwei Läufe identisch; Geist-Wippe unabhängig.
7. Sprungfenster: für jede Strecke mit Lücke `lo < hi`, Plan erreichbar, Absprungtempo der KI je Stufe in `[v_min + 1, v_hi − 1]`.
8. Sprint-Start: kein Überlappen am Start (Abstand ≥ 1,2 m), alle Serra-Gegner im Ziel.
9. `validate()`: unsortierte elevation wird gemeldet. Veraltetes Layout (kein Hash, `rev` 2) wird ignoriert.
10. Golden times `azure`, `city`, `arena` bitgleich.

**A – `game/tests/test_field.gd` (neue Suite):** jede Rennstrecke × 3 Stufen mit Wetter, Aufstellung, Ausweichen, Kontakten, Gegner-Turbo über `RaceField`, Spieler-Ersatz
`ai_route(2.0, 0)`; Kinderzimmer zusätzlich mit Spieler-Ersatz **auf dem Lineal**; Arena: Zeitlimit-Bot kommt ins Ziel. Bewertung nach Regel 1.3; Zeittabelle ausgeben;
Kinderzimmer Stufe 3 zweimal → identische Zeiten.

**A – `test_diorama.gd` erweitert** (A6), bestehende Suiten an Startaufstellung/`RaceField` angepasst. **C3 – `test_wear.gd`** (Abschnitt 8).

---

## 10. Dateihoheit (wer darf was ändern)

| Agent | Phase | Darf ändern / anlegen | Darf nicht |
|---|---|---|---|
| **A Unterbau** | allein | `game/scripts/track.gd`, `vehicle.gd`, `world.gd`, `main.gd`, `recorder.gd`, `progress.gd`, `hud.gd`/`sound.gd` (nur P3-Haken); neu `game/scripts/seesaw.gd`, `race_field.gd`; `game/assets/road.gdshader` (Anschluss), neue Shader für Durchsicht/Deck; `game/tests/*.gd`, neu `game/tests/test_heights.gd`, `test_field.gd`, `golden_times.json`, `game/tests/tracks/**`; `tools/build.ps1` (nur Suitenliste); `tools/diorama.py` (Kern, A6); `docs/dioramen/README.md` (Kern/Format) | `tools/make_tracks.py`, `game/tracks/*.json`, `tools/dio_themes/*`, `game/dioramas/*` |
| **B Streckendaten** | allein, nach A | `tools/make_tracks.py`, `game/tracks/*.json` (nur forest, harbor, quarry, kids inhaltlich), `game/dioramas/{forest,harbor,quarry,kids}*` (nur über `dio_build`, Sicherung/Rückkopie), spurabhängige Erwartungen in `game/tests/*.gd`; kleine belegte Korrekturen in `game/scripts/*` | Themenmodule, `diorama.py`, Shader |
| **C1 Steinbruch+Hafen** | parallel, nach B | `tools/dio_themes/quarry.py`, `harbor.py`, `tools/make_quarry_*.py`, `tools/make_harbor_*.py`, `game/assets/dio/quarry/**`, `game/assets/dio/harbor/**`, neue `game/assets/props/steinbruch_*.glb`/`hafen_*.glb`, `docs/dioramen/quarry.md`, `harbor.md`, `arena.md`, `game/dioramas/quarry*`, `harbor*`, `arena*` | alles andere; Kernwünsche im Bericht |
| **C2 Wald+Kinder** | parallel, nach B | `tools/dio_themes/forest.py`, `kids.py`, `tools/make_forest_textures.py`, `tools/make_kids_textures.py`, `tools/make_fair_kids_geom.py` (nur ergänzen), neu `tools/make_kids_ruler.py`, `game/assets/props/kinder_lineal.glb`, `kinder_ampel.glb`, `game/assets/dio/forest/**`, `game/assets/dio/kids/**`, `docs/dioramen/forest.md`, `kids.md`, `game/dioramas/forest*`, `kids*` | alles andere |
| **C3 Spuren+übrige** | parallel, nach B | neu `game/tests/make_wear.gd`, `game/tests/test_wear.gd`, `game/assets/wear/**`; `game/assets/road.gdshader` (Spuren-Look); in `game/scripts/world.gd` **nur** `apply_wear_map()`; `tools/build.ps1` (nur `test_wear` eintragen); `tools/dio_themes/mountain.py`, `coast.py`, `fair.py` (nur falls nötig); `tools/diorama.py` (in Phase C nur C3, falls für Spuren nötig); `docs/dioramen/README.md` (neuer Abschnitt „Nutzungsspuren“), `serra.md`, `fair.md`, `azure.md`; `game/dioramas/serra*`, `fair*`, `azure*`, `city*` (nur Neubau) | Themen von C1/C2, übrige Skripte |

Gemeinsam: Godot/Blender nur über die Skripte (Mutex), Bilder mit eigenem `-Tag` (`_q`, `_h`, `_w`, `_k`, `_sp`), fremde Bilder nicht löschen. Diese Datei
(`HOEHEN_PLAN.md`), `AGENTS.md` und `docs/IMPLEMENTIERUNG.md` ändert nur der Leiter. Wer außerhalb seiner Hoheit etwas braucht, meldet es im Bericht.

---

## 11. Risiken

- **A ist der Engpass.** Reihenfolge A0 → A7 und P1/P2/P3 einhalten; was offen bleibt, steht im Bericht (B und C bauen nur auf P1 auf).
- **Feldtest heute schon rot** auf mehreren Strecken (Kritik: Kinderzimmer, Steinbruch Regen, Jahrmarkt Regen, Wald Schnee, Hafen im Feld, Serra). Ohne A2 c, e, g, h
  sind die Entwurfsbelege („12/12“, „40/40“, alle solo und trocken) nicht belastbar.
- **Steinbruch +38 % Länge** (≈ 100 s Rennen), weniger wiedererkennbar (V-Schlenker, Graben, Abkürzung entfallen); großer Dioramaumbau.
- **Hafen-Geometrie H1' ist neu** (Ecke 5 entfällt) und nur rechnerisch geprüft; Rückfälle in 4.2.
- **Wippe**: erstes bewegtes Element; der Spieler plant blind, ein Wrack kostet das Rennen (deterministisch und lernbar; Stoß ohne Wrack bis 0,6 m Kante). Abkürzung
  könnte dominieren (Ziel ≤ 1,5 s je Runde). Einmündung ist Treffpunkt von Haupt- und Abkürzungsverkehr.
- **Bestzeiten/Geister** der vier geänderten Strecken gelten nicht mehr (rev/Hash); Gold bleibt.
- **Dioramen** vorübergehend ungültig (zwischen B und C Laufzeitgrafik); Waldumbau (alles absolut auf 0,08/0,147) und Dreiecksbudget.
- **Parallaxe** beim Zeichnen auf erhöhter Fahrbahn (FOV 40°): 1–3 m am Bildrand, `world_point` gleicht aus.
- **Spurenkarten veralten** bei jeder Datenänderung (Hash-Test erzwingt Neuerzeugung); ein Texturzugriff mehr auf dem Handy.
- **Nicht auf dem Gerät geprüft** (Leitplanke 10): Fahrgefühl auf Rampen, Kanten, Wippe und Brücke muss der Nutzer auf Android abnehmen, bevor weitere Höhenstrecken entstehen.

---

## 12. Bewusst verschoben

| Thema | Grund |
|---|---|
| Lastfaktor/Kuppen-Entlastung (Wald-Buckelbrücke) | globale Physikänderung, Serra-Knicke, VERSION-Sprung; nur später je Strecke (`crest_load`) nach Gerätetest |
| Querneigung `banks` (Jahrmarkt-Motodrom, Kinder-Steilkurve) | neues Haftungsmodell ohne Prototyp, Kontakt-Δz bei 30° Schräge; später als ein Paket mit fester 20°-Vorstufe |
| Serra-Kehrschleife mit Bruchsteinviadukt | erst Sprint-Start (heute) und neue Gegnerkalibrierung abwarten; Geländeregel „Minimum der Straßenhöhen“ |
| Arena-Parkdeck mit Flugdrift | braucht Abkürzungen mit Höhenprofil, neue Driftwertung, neue Bestenlisten-Fassung |
| Abkürzungen mit eigenem Höhenprofil (Hafen-Gassenweg, Arena-Gasse) | heute nur Gelände + Wippendeck |
| KI auf den Abkürzungen von Hafen und Steinbruch | wie bisher nicht; Wippe ist die erste KI-Abkürzung |
| Holzbelag mit eigener Haftung, Bohlenrumpeln | `road_zones` neu in `surface_at`; heute Schotter auf der Brücke |
| Spuren auf gebackenen Fahrbahnen (Azure, Stadt) und Abkürzungen; Einstellung „Spuren aus/dezent/voll“ | eigene UV-Wege bzw. neue Menüoption |
| Prüfstrecke für das Gerät außerhalb der Karriere | heute nur als Testgeometrie in `game/tests/tracks/` |

**Weitere Ideen für andere Strecken** (für die nächsten Runden, Entwürfe im Journal):
1. **Serra – Kehrschleife mit Viadukt** vor der Passhöhe (300°-Schleife, 8 %, Straße über sich selbst, Brüstung bricht ab 9 m/s).
2. **Jahrmarkt – Holz-Motodrom**: überhöhte Schüssel statt der zwei Haarnadeln, Linienwahl innen/Mitte/oben, danach die Schanze als Schwung-Prüfstein.
3. **Drift-Arena – Parkdeck mit Dachkante**: Driftkurve auf dem Dach, kurzer Abflug, „Flugdrift“-Wertung; unten die enge Gasse.
4. **Kinderzimmer – Steilkurve aus Bahnteilen** mit wachsender Neigung (5° innen bis 30° außen).
5. **Wald – Buckelbrücke/Wurzelkuppe** mit Lastwechsel (nur auf Wunsch je Strecke).

---

## 13. Stand nach der Prüfung (03.10.2026, Nachbesserung)

Die Prüfung der Nachtschicht (Journal `wf_c04b9333-1af`) bewertete den Steinbruch als **mangelhaft**, Hafen, Wald, Wippe und die Feldtest-Regel als
**brauchbar**. Behoben wurde, was ein echter Fehler war; gewollte physikalische Folgen (Übertempo bricht die Leitplanke am Hafen, Nachfolger im Gefahrenfenster
der Wippe wird zum Wrack) bleiben und sind lesbarer geworden. Alle 9 Suiten grün, **653 Prüfungen** (vorher 596).

**Steinbruch (Q1').** Die unsichtbare Stirnwand unter der Landelippe (x −8,5…−7,5, z −30…−18, b 0) war mit 3,0 m so hoch wie die Lippe und fing korrekt
gelandete Autos auf dem ersten Rampenmeter fest (Absprung 11,1–12,3 m/s). Sie reicht jetzt bis Lippe − `lip` = 2,6 m (`tools/make_tracks.py`): Was die
Lippenregel landen lässt, fährt darüber; tiefer prallt es ohnehin an die Stirnseite. Probe: Absprung ≤ 10,3 m/s fällt in die Lücke, 10,7–11,1 Aufprall an
der Lippe, ab 11,5 m/s Landung und Weiterfahrt (neu in `test_heights`, Punkt 2). Das Fenster der KI bleibt [13,5; 24], sie springt mit 16,6–17,5 m/s ab und
landet 5–16 m die Schüttrampe hinunter (über dem Planziel 13–14, bewusst so gelassen: weich und weit weg von der Lippe). Diorama neu gebaut (Lage und
Normale der Lippenwand kommen weiter aus dem Hindernis), Spurenkarte neu. Offen: Die 5,6 m Höhe sind aus der 72°-Rennkamera kaum zu sehen.

**Gemeinsame Ursachen verlorener Gegner (Unterbau, gelten für alle Strecken).**
1. *Festkleben an Hindernissen* (`vehicle.gd collide_obstacles`): Reibung längs der Wand war ein fester Anteil der Tangentialgeschwindigkeit je Takt, weiche
   Hindernisse nahmen zusätzlich 10 % je Takt. Wer mit Vollgas anlag, stand bei 0,2 m/s und war nach `STUCK_TIME` ein Wrack (Steinbruch-Wall, Stadt-Gitter,
   Jahrmarkt-Mast). Jetzt Coulomb: höchstens `WALL_FRICTION` (0,6) · Normalstoß, gedeckelt auf den bisherigen Anteil; weiche Hindernisse schlucken
   bis 10 % nur beim Aufprall (ab 3 m/s Stoß). Harte Treffer verhalten sich wie bisher; neu in `test_collision`: Anliegen an Absperrung und Mauer schrammt entlang.
2. *Ausweichen* (`RaceVehicle.update_avoidance`): Seitenversatz nur noch auf Geraden (voll bis Radius 40 m, keiner ab 18 m), nur mit Haftungsreserve
   (v²·k unter 45 % der Querhaftung voll, ab 80 % keiner), nie über `hw − 1,3` hinaus, nicht eingeklemmt zwischen zwei Autos, und vor Schwungzonen und
   Kurven schon 1,5 s voraus sanft zurück (1,5 m/s). Vorher drehte der verschobene Zielpunkt Gegner in Kurven über, am Ausgang folgte mit Vollgas ein
   Heckrutscher bis an Wall oder Absperrung, und am Beginn der Schwungzone vor dem Kicker pendelte G2 bis zum schrägen Absprung.
3. *Looping-Anlauf* (`track.gd ai_route`): Das Mindesttempo trägt jetzt den Reglerversatz wie bei Sprüngen; die KI kam vorher 1,5–2 m/s unter
   √(5gR)·1,15 an und fiel im Pulk beim kleinsten Kontakt aus dem Looping.
4. *Sprungziel* (`track.gd plan_jumps`): Ist-Ziel mindestens `lo + JUMP_AIM` (1 m/s). Hafen: Absprung 10,2 statt 9,0–9,3 m/s (Fenster [9,5; 21,25],
   Planziel 10–11). `test_heights` Punkt 7 prüft jetzt das eigene Fenster [lo − 0,3; hi] statt [v_min + 1; v_hi − 1].
5. *Wippen-Entscheidung* (`race_field.gd`): steht beim Entscheiden ein anderes Auto näher als 10 m (`SEESAW_CROWD`), nimmt die KI den Umweg (vorher schob ein
   am Kurvenausgang hinausrutschendes Auto den Abkürzer neben das Lineal ans Stiftende).

**Feldtest robust** (`test_field.gd`): Die Pflichtstrecken (Wald, Hafen, Steinbruch, Kinderzimmer, Serra) fahren je Stufe zusätzlich mit drei trocken
gerechneten Spielerlinien (1,2 Außenspur 0,8; 2,6 Gegenspur −0,8 mit Turbo ohne Sperrzonen; 3,0 mittig), das Kinderzimmer zusätzlich 2,8 mit Turbo auf dem
Lineal; `RaceField.run_field` hat dafür `player_turbo`. Breitere Probe (Scratch `nb/sim.gd sweep`, je Strecke 30–36 Rennen: Spieler 1,0/1,5/2,5/3,0 × Spur
0/0,8, Turbo-Linien, Lineal-Linien): verlorene Gegner vorher Steinbruch 11, Stadt 24, Jahrmarkt 9, Wald 3, Kinderzimmer 3, Hafen 2, Serra 1, Azure 1; jetzt
0 auf allen Strecken außer der unveränderten Stadt (3 von 30, Stufe 3 Regen mit schnellem Spieler auf Spur 0,8: Mast bei s 0,958, Gitter bei s 1,005). Ein
Gegner, der ohne Wrack nie ankommt („Zeit“, Prüfung: Steinbruch Stufe 2), trat in keinem der neuen Läufe mehr auf; die Ursache ist nicht geklärt.
Gleichgewicht Stufe 3: Steinbruch Gegner 93,3–99,8 s gegen Spieler-Ersatz 2,0 97,7 s (vorher gewann er), Hafen 59,2–62,5 gegen 61,7.
Solozeiten azure/city/arena bitgleich (`golden_times.json`), `RaceVehicle.VERSION` bleibt `bicycle-4`.

**Hafen (H1').** Nur über die gemeinsamen Ursachen: Absprungtempo im Fenster, keine verlorenen Gegner an der Auffahrt mehr. Übertempo auf der Terrasse
(Plan ≥ 17 m/s) bricht weiter die Leitplanke an Ecke 4 (gewollt).

**Wald.** Übertempo in der Talkehre endete immer festgeklemmt an einem Zusatzbaum des Themas, der im Freiraum der Streckendatei stand. `forest.py` hält
außen an Kehren enger als 16 m bis hw + 7 m Auslaufzonen frei (52 statt 70 Zusatzbäume): Plan 12–18 m/s kostet 1,2–3,5 s, grobes Übertempo endet
an Baum oder Hohlwegwand. Diorama neu gebaut (Streckendatei unverändert).

**Kinderzimmer (Wippe).** Das Lineal liegt in der Darstellung wie jede Fahrbahn 0,17 m über der Simulationshöhe (`world.gd SEESAW_LIFT`): Autos schweben
nicht mehr, das tiefe Einfahrtsende mit rot-weißer Kante liegt in Ruhe sichtbar auf Fahrbahnhöhe; der Laufzeitstreifen der Abkürzung spart die Grundfläche
des Lineals aus. Filzstift Ø 0,89 m (trägt die Unterseite bei 0,97 m), Stift-Collider 0,9 m breit; Diorama und Spurenkarte neu. Gefahrenfenster unverändert
(Nachfolger mit 2,0–3,2 s Abstand an der Kante zum Wrack), Gewinn 1,53 s je Runde (Stufe 2,3). Belag der Abkürzung bleibt `dirt` (mit Asphalt fielen
Stufe 2,7/3,0 vom Lineal, Agent B). Offen: Die Wippe liegt in der Rennkamera am oberen Bildrand unter der HUD-Leiste.

**Unverändert offen:** Gerätetest auf Android (Leitplanke 10); Höhenwirkung in der Rennkamera; Stadt-Bestandsfehler bei Regen mit schnellem Spieler.
`AGENTS.md` und `docs/IMPLEMENTIERUNG.md` (Prüfungszahl 653, neue Konstanten) pflegt der Leiter.

