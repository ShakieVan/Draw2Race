# Draw2Race 0.1.0 — Implementierungsstand

24.09.2026. Eine erste durchspielbare Küstenserie, auf Basis der vorhandenen Richtlinien. Der Nutzerauftrag autorisierte die Umsetzung. Der geplante frühe Gerätetest bleibt der nächste fachliche Abnahmepunkt vor zusätzlichen Strecken.

## Enthalten

- Eigene Strecke **Azure Coast** als 3D-Diorama: Lagune, Boxenhaus, Tribünen, Palmen, Strandmöbel, Anleger, Curbs, Startaufstellung und Reifenspuren. Wiederholte statische Geometrie wird über MultiMesh gebündelt.
- Untergrundabhängige Spuren an allen vier Radpositionen: dunkler Abrieb beim starken Bremsen oder Rutschen, profilartige Erd-/Matschspuren auf dem unbefestigten Bankett und zwei sichtbar dunkleren Matschabschnitten. Reifen tragen Verschmutzung auf die Fahrbahn; sie nimmt über gefahrene Strecke ab. Spuren verblassen nach 33 Sekunden und verschwinden nach 45 Sekunden Simulationszeit; maximal 4096 Segmente. Pause hält die Alterung an, Neustart löscht Spuren und Verschmutzung. Das System liest die Fahrzeugbewegung ausschließlich; die bisherige Physik und deren Versionskennung bleiben unverändert. Separate Reibwerte für Erde/Matsch sind noch nicht implementiert.
- Deutsche Menüs, Hinweise, Optionen und Ergebnisanzeige; skalierbare Oberfläche im Querformat. Breite Displays zeigen zusätzliche Umgebung statt schwarzer Seitenbalken.
- Maus und Touch; aktiver Finger wird eindeutig verfolgt. Zwei separat aufgezeichnete Runden, zeitgestempelte Eingabe in Weltkoordinaten, Prüfung ganzer Segmente, Endpunkt-Fortsetzung, Neustart und Pause bei Fokusverlust.
- Tempolinie gemäß Nutzerpräzisierung: langsam = breit und hellgelb, schnell = schmal und kräftig rot; Breitenverhältnis 3,2:1. Beide Merkmale gehen entlang der Linie fließend ineinander über und zeigen so den geplanten Tempoaufbau bzw. Bremsen. Grafische Legende und Fahrhilfe erklären die Zuordnung. Das Profil wird räumlich abgetastet, nicht als Positionsanimation abgespielt; die tatsächliche Beschleunigung entsteht aus der Physik.
- Eigene dynamische Zweiachsphysik: Längs- und Querbewegung, Giergeschwindigkeit, endliches Lenken und Bremsen, getrennte Vorder-/Hinterachsgrenzen, kombinierte Haftungsreserve, Fahrbahnrand und vereinfachte Fahrzeugkontakte. Feste 60 Simulationsschritte pro Sekunde.
- Countdown, gedämpfte Verfolgungskamera mit abschaltbarer Bewegung, Runden, Platzierung und innerhalb des Simulationsschritts interpolierte Zielzeiten.
- Turbo zum Halten; Ladung aus tatsächlich abgebauter Bewegungsenergie. Gegner nutzen denselben Fahrzeugkern.
- Ein Event mit drei Gold-Herausforderungen gegen einen, zwei und drei Rivalen. Zweites Fahrzeug mit höherem Grip und geringerem Antrieb nach erstem Gold. Rennplatzierung und Event-Gold werden getrennt behandelt.
- Lokale Bestzeiten je Strecken-/Physikversion, Fahrzeug und Herausforderung. Versionierte Spielstände mit temporärer Datei und Sicherung, kein doppeltes Gold. Letzter Lauf mit Rohgesten, verarbeiteter Linie und Turboaktionen.
- **Autos, Bestenliste, Sound (26.09.2026, spät):**
  - **Fünf Autos** (`RaceVehicle.CARS`), freigeschaltet über Gold:
    - Sprint: Start
    - Grip: 1 Gold
    - Dirt Hawk: 3 Gold, halbe Strafe neben der Fahrbahn
    - Thunder V8: 6 Gold, viel Kraft, wenig Grip
    - Apex GT: 9 Gold, Grip, Kraft und starker Turbo

    Die Werte wirken physikalisch über grip, power, offroad und turbo. Jedes Auto hat eine eigene Form (`world.gd` `CAR_STYLES`).
  - **Menü:** Auto-Karussell mit drehender 3D-Vorschau (eigene SubViewport-Welt) und Werte-Balken; ein gesperrtes Auto kann nicht starten.
  - **Bestenliste (lokal):** 10 schnellste Fahrten je Strecke und Herausforderung mit Auto und Datum. Platz im Ergebnis, Bestzeit im Menü, eigener Dialog.
  - **Soundmenü:** Musik und Geräusche auf eigenen Audiokanälen, Lautstärkeregler, erreichbar aus Optionen und Pause.
  - **Eigenes Startbild** statt Godot-Logo (`game/assets/splash.png`).
  - **Fahrbahnbelag im Streckenformat** (`"road": "asphalt" | "gravel"`). Forest Eight ist eine Schotterpiste:
    - Physik: Grip 0,8 und leichter Rollwiderstand; die KI senkt ihr Kurventempo entsprechend.
    - Optik: Körnung und festgefahrene Spuren, Holzpfosten und Feldsteine statt Randsteinen.
    - Klang und Spuren: Schotterknirschen statt Quietschen, helle Staubspuren.
- **Streckenformat und Karriere (26.09.2026, abends):**
  - **Strecken als Dateien:** `game/tracks/<id>.json` (Format 1), erzeugt mit `tools/make_tracks.py`. Inhalt:
    - Mittellinie als Kontrollpunkte (Catmull-Rom-geglättet, gleichmäßig abgetastet)
    - Thema: coast, city oder forest
    - Belagzonen
    - Deko-Bausteine mit Typ, Position, Drehung und Maßen
    Die Companion-App soll künftig genau dieses Format erzeugen.
  - **Generische Strecken-Engine** (`track.gd`):
    - Suchraster für schnelle Abstandsabfragen
    - `phase_near` wertet lokal um den bisherigen Streckenanteil aus; an der Kreuzung der Acht springt die Zählung nicht auf den anderen Ast
    - `other_branch_distance` erkennt Kreuzungen: Randsteine und Randlinien werden dort ausgespart, die Fahrbahn ist nach Streckenanteil minimal gestaffelt
  - **Welt aus Datei** (`world.gd`): Themen mit Inselsockel, Stadtboden oder Waldboden und 20 Deko-Bausteine, darunter Palme, Tribüne, Hochhaus, Laterne, Kiefer, Laubbaum, Teich und Hütte.
  - **Strecken:**
    - Azure Coast: Stadion-Oval, 138 m
    - Downtown L: Stadt, L-Umriss, 186 m
    - Forest Eight: Wald, liegende Acht mit Kreuzung, 196 m; Kollisionen an der Kreuzung sind möglich
  - **KI-Tempoprofil aus der Krümmung:** Kurventempo aus der Querbeschleunigung, Bremsen per Rückwärtsdurchlauf. Stärke 0–3; 3 ist das gemessene Optimum, mehr würde überziehen.
  - **Gegner:**
    - Die Gegner waren viel zu schwach: 35–41 s, der Nutzer fuhr ~23 s.
    - Jetzt beste Gegner je Stufe auf Azure 27,9 / 25,2 / 24,2 s (`RIVAL_SKILL`, `RIVAL_LANES` in `main.gd`).
  - **Speicherstand Version 2:**
    - Gold wird als eindeutiger Eintrag „strecke/stufe“ gespeichert.
    - Ursache des Fehlers „4 von 3 Gold“: In Version 1 wurden Zahlen gespeichert, nach dem Laden aus JSON waren es Kommazahlen, und in GDScript ist `0 in [0.0]` falsch.
    - Alte Stände werden ohne doppeltes Gold übernommen.
  - **Aufstieg:** 3 Gold auf einer Strecke öffnen die nächste.
- **Überarbeitung 26.09.2026 (Nutzerwünsche nach erstem Gerätetest):**
  - **Strecke:** Stadion-Oval nach Art des Dover Motor Speedway, mit zwei 28-m-Geraden und zwei Halbkreiskurven von 13 m Radius; Länge ≈ 138 m wie zuvor. Palmen halten mindestens 7,5 m Abstand zur Mittellinie.
  - **Linienglättung:** Im Streckenkoordinatensystem. Der Fortschritt bleibt exakt, seitlicher Versatz und Tempo werden wegabhängig gefiltert; nach dem Zeichnen folgt eine Gauß-Nachglättung. Das gleicht Fingerzittern und wandernden Druckpunkt aus.
  - **Fahrregler:**
    - Zielpunkt als Mittel eines Linienfensters um den Vorausblick (4 m + 0,4 s × v) plus Gierdämpfung.
    - Gemessen mit `game/tests/tune_controller.gd`: glatte Linie 7 → 0 Überschwinger; wackelige Linie 61,3 → 36,6 s, max. Abweichung 4,9 → 1,2 m, keine Dreher mehr.
    - Überziehen kostet dadurch weniger Zeit als früher (32,2 gegen 32,9 s), denn der frühere große Verlust kam vom Schlingern, nicht aus der Physik.
  - **Gegner:**
    - Eigene Spuren (+1,6 / −1,6 / +2,3 m) und seitliches Ausweichen statt Dauerkontakt (vorher ~29 s Reiben pro Rennen).
    - Der Vorteil der kürzeren Innenspur wird über das Tempo ausgeglichen.
    - Stufen: 1 Gegner leicht, 2 knapp, 3 nur mit besserer Linie/Turbo.
  - **Eigenes Auto:** selbstleuchtende Karosserie und pulsierender Lichtkranz.
  - **Menü:** Eigener gezeichneter Hintergrund; die 3D-Strecke wird erst beim Zeichnen gezeigt.
  - **Android-Signatur:** fester Debugschlüssel `.tools/draw2race-debug.keystore` über `tools/build.ps1`.
- **Klang (Stand 26.09.2026):** Effekte werden zur Laufzeit synthetisiert. Die Musik ist KI-erzeugt und liegt als OGG vor. Musik und Effekte sind getrennt schaltbar. Outfit-Schrift unter SIL OFL; keine Referenzassets im Spiel.
  - **Startampel:** dreimal Rot (tiefes Signalhorn), einmal Grün (hohes, langes Horn).
  - **Motor:** zwei Loops (Last/Schub), überblendet nach dem Gasanteil des Fahrzeugs. Die Tonhöhe folgt simulierten Gängen, beim Hochschalten fällt die Drehzahl. Dazu Turbo-Pfeifen.
  - **Reifen:** Quietschen auf Asphalt/Curbs nach Schlupf und Bremsdruck. Auf Erde Knirschen/Prasseln nach Tempo und Schlupf, bei Matsch tiefer.
  - **Musik:**
    - Zwei Stile, umschaltbar in den Optionen: „energiegeladen“ (Songs mit Gesang) und „ruhig“ (Instrumentalstücke).
    - Durchgehende Zufalls-Playlist ohne direkte Wiederholung. Überblendung am vorab gemessenen Ausklingpunkt (`game/assets/music/music.json`).
    - Beim Zeichnen −15 dB, im Rennen volle Lautstärke.
    - Eigene Stücke für Sieg und Niederlage, danach zurück zur Playlist.
  - **Herkunft:** YuE2-3B (CC BY-NC 4.0), daher nur nicht-kommerzielle Weitergabe. Details in `docs/KLANG_STECKBRIEFE.md`.
- Installierbare Android-Debug-APK und eigenständige Windows-Anwendung; reproduzierbare Buildskripte.

## Modulübersicht

| Datei | Aufgabe |
|---|---|
| `game/scripts/track.gd` | Streckenraum, Segmentprüfung, geordneter Fortschritt, Gegnerlinien |
| `game/scripts/recorder.gd` | Fingerzuordnung im Hauptablauf, Rohproben, Abtastung, Tempovorgaben |
| `game/scripts/vehicle.gd` | Fahrregler, Kräfteintegration, Kontakte, Turbo und Zielübertritt |
| `game/scripts/main.gd` | Phasen, Eingabeverteilung, Rennuhr, Kamera, Ergebnisse |
| `game/scripts/world.gd` | Eigene Geometrie, statische Batches, Autos und Spuren |
| `game/scripts/tyre_tracks.gd` | Radbezogene Spuraufnahme, Verschmutzung, Abrieb, Speicherlimit und Lebensdauer |
| `game/scripts/hud.gd` | Menüs, Tutorial, HUD und Optionen |
| `game/scripts/sound.gd` | Effektsynthese, zustandsabhängige Mischung, Musik-Playlist mit Überblendung und Absenkung |
| `game/assets/music/` | spielfertige Musik (OGG, −14 LUFS) und `music.json` (Stil, Rolle, Ein-/Ausklingpunkte); erzeugt mit `E:\Draw2Race-AudioLab\generate\export_music.py` |
| `game/tests/audio_smoke.gd` | manueller Audiotest mit Fenster (Musik läuft, wird abgesenkt, wechselt bei Ergebnis) |
| `game/scripts/progress.gd` | Versionierter Speicherstand, Gold, Rekorde und Optionen |

## Prüfen

`tools/build.ps1 -Target Test` importiert das Projekt und führt drei Testsuiten aus. Sie prüfen reale Regeln: Abkürzungen und Gegenrichtung, unterschiedliche Rundenprofile, Fortsetzen und Verweilen, Eingabe bei 30/60/144 Hz, Fahrtabschluss und Wiederholbarkeit, Bremsweg, Schlupf/Überziehen, Turbo, Mehrfinger-Eingabe, Touchprojektion, Pause, alle drei vollständigen Herausforderungen, Gegnerziele, eindeutiges Gold, Speichern/Laden, beschädigte Primärdatei und Neustart. Die Spurprüfungen decken Untergrunderkennung, sauberes Rollen, Stillstand, gerades Bremsen, seitlichen Schlupf, Schmutzmitnahme und -abnahme, Positionssprünge, Speicherlimit, Alterung und Rücksetzen ab.

Referenzmessung im selben Build ohne Turbo: kontrollierte konstante Vorgabe 10 m/s ≈ **31,04 s**, überzogene Vorgabe 29 m/s ≈ **62,42 s**. Das demonstriert realen Zeitverlust durch Ausbrechen, keine abschließende Balancebewertung.

**56/56 automatische Prüfungen bestanden** (zuletzt 26.09.2026 nach Einbau von Musik und neuen Effekten; Audio zusätzlich mit `game/tests/audio_smoke.gd` im Fenster geprüft) (20 Kernprüfungen, 22 Ablaufprüfungen einschließlich Ergebnisreihenfolge/Gleichständen sowie 14 Prüfungen der Reifenspuren). Die neue Spurendarstellung wurde zusätzlich unter Windows visuell geprüft; Windows- und Android-Builds wurden aktualisiert. Windows-Ansichten wurden aus dem laufenden Spiel gerendert. Die Android-APK wurde im API-36-Emulator installiert und gestartet: Menü, zwei Runden per nativen Touchgesten bis zum gespeicherten Zieleinlauf (51,076 s, 305 Rohproben) sowie vollständige Vorführfahrt bis zur Ergebnisliste wurden geprüft. Die Audioschleifen laufen nach Korrektur ihrer Sample-Endindizes über mehrere Schleifendurchläufe stabil. Breites 2400×1080-Display mit zusätzlicher Umgebung und ohne Seitenbalken geprüft.

Der Emulator ersetzt keine Messung von Fingergefühl, thermischer Last oder Leistung auf echter ARM-Hardware.

## Bewusste Grenzen und nächste Abnahme

**Dies ist keine vollständige M5-Veröffentlichungsversion.** M1/M2 sowie der kleine Karriereablauf aus M3 sind implementiert. M0 bleibt hinsichtlich echtem Gerät offen. Ein gestaltetes Diorama aus M4 ist enthalten; weitere Strecken entstehen erst nach der Touch-/Fahrgefühl-Abnahme gemäß Projektleitplanke.

Noch offen: reale Android-Gerätematrix, Langzeit-/Thermikmessung, Balancing mit menschlichen Spielern, weitere Strecken und Fahrzeuge, Schnee/andere Untergründe, ausgefeiltere Kontakte und Effekte, Geister, Onlinefunktionen und Release-Schlüssel. Strecken- und Fahrzeugparameter liegen derzeit in den Modulen; ein externer Inhaltseditor ist nicht enthalten. Sound ist ein eigener erster Entwurf, kein nachgehörter Referenznachbau.

Die gespeicherten Eingaben dienen Diagnose und Weiterentwicklung. Geräteübergreifend bitgenaue Replays werden nicht zugesichert.

## Builds und Quellen

- Engine: [Godot 4.6.1](https://godotengine.org/download/archive/4.6.1-stable/), kompatibler OpenGL-Renderer.
- [Offizielle Android-Exportanleitung](https://docs.godotengine.org/en/4.6/tutorials/export/exporting_for_android.html).
- `builds/Draw2Race.apk`: ARM64 und x86_64, Paket `de.draw2race.game`, Debugsignatur, Offline-Spiel ohne INTERNET-Berechtigung.
- `builds/Draw2Race.exe`: Windows x86_64, Spieldaten eingebettet.
- Spielstand unter Godots `user://`: Windows `%APPDATA%/Godot/app_userdata/Draw2Race/`; Android im privaten App-Verzeichnis.

Google-Play-Publikation und ein signierter Release-Build sind nicht Bestandteil dieses ersten Gerätebuilds.

## Schritt 5, Teil 1: Atmosphäre, Grafikstufen, Entwickler-Menü (26.09.2026)

- `game/scripts/atmosphere.gd`: Tageszeit (Tag/Dämmerung/Nacht), Wetter (trocken/Regen/Schnee), Nebel (0 aus, 1 treibende Nebelschwaden, 2 dicht). Nur Darstellung – bis auf die Wetterhaftung `WEATHER_GRIP` (1,0/0,85/0,7), die als `RaceVehicle.weather_grip` in Fahrphysik und KI-Tempoprofil wirkt. Die Bedingung ist Teil der Herausforderung, also nicht spielerwählbar.
- Streckenformat: optionales Feld `conditions` (3 Einträge, je Herausforderung). Küste: Tag / Dämmerung / Nacht+Regen. Stadt: Dämmerung / Nacht / Nacht+Regen+Schwaden. Wald: Tag / Tag+Schwaden / Dämmerung+Schnee+Schwaden. Das Menü zeigt die Bedingung neben „Herausforderung“.
- Dunkelheit: Lichtkegel von Laternen, Flutlicht (Küste) und Wegleuchten (Wald), Scheinwerfer und Rücklichter an allen Autos. Regen: Pfützen, glänzende dunklere Fahrbahn. Schnee: aufgehellter Boden. Staubfahnen auf losem Grund (ab Stufe „Mittel“, nicht bei Regen).
- Einstellungen → Grafikqualität Niedrig/Mittel/Hoch (Schlüssel `gfx`): Schatten, MSAA, Partikel- und Nebelmenge.
- Entwickler-Menü: 5 schnelle Tipper auf das DRAW2RACE-Logo. Tageszeit/Wetter/Nebel/Grafik live umschalten, Originalbedingungen, alles freischalten, FPS-Anzeige, Vorführfahrt. Gespeichert unter `debug` im Spielstand.
- Schotterstrecke ohne Spurbegrenzungsstreifen; Richtungspfeile zeigen in Fahrtrichtung.
- Tests: 28/25/14 bestanden (neu: Bedingungen je Herausforderung, Nässe verlangsamt Physik und KI). `game/tests/weather_shots.gd` rendert Kontrollbilder aller Bedingungen.

## Zeichen-Kamera (26.09.2026)

- Beim Zeichnen zoomt die Kamera heran und folgt weich der Stiftspitze mit Vorlauf in Fahrtrichtung (Vorbild: Referenzvideo ab 8:10). Sie wird an den Streckenrändern begrenzt, damit kein leerer Rand ins Bild kommt.
- Einstellung „Kamera-Zoom beim Zeichnen“ (Schlüssel `draw_zoom`, Standard 35 %): 0 % = ganze Strecke wie bisher, 100 % = Fahrbahn füllt ein Drittel der kürzeren Bildschirmseite.
- Wandert die Kamera unter dem ruhenden Finger, wird der Zeichenpunkt je Bild nachgeführt. Das gemessene Tempo bezieht sich immer auf die Linie auf der Strecke; die Linienbreite zeigt es an.
- Kontrollbilder: `game/tests/draw_camera_shots.gd`.
- Nachbesserung: Die Kamera zielt auf die Mitte des freien Sichtbereichs zwischen Kopf- und Fußleiste (`RaceHUD.free_band()`), nicht auf die Bildschirmmitte. Bei starkem Zoom darf sie bis zu 40 % über die Streckenkante hinaus, bei der Gesamtansicht gar nicht.
- Leisten in der Zeichenansicht lassen Berührungen durch (nur ihre Knöpfe reagieren). Ein begonnener Strich wird in `_input` weiterverfolgt und reißt über einer Leiste nicht mehr ab.

## Kamera-Stick beim Zeichnen (27.09.2026)

- Standard (Option „Kamera per Stick schieben“, Schlüssel `draw_stick`; aus = Kamera folgt der Spitze automatisch).
- Gezeichnet wird wie immer direkt unter dem Finger, angesetzt am Linienende. Der erste Berührpunkt wird zur Stick-Mitte (Ring). Entfernt sich der Finger über die Totzone (15 % von 480 Bildpunkten) hinaus, fährt die Kamera in diese Richtung, bei voller Auslenkung mit 40 m/s (Kurve Auslenkung^1,4, weich gefiltert). Unter dem ruhenden Finger wandert der Zeichenpunkt dadurch über die Karte; das Tempo misst sich wie immer an der Linie auf der Strecke.
- Gummizug je Achse (x/y unabhängig): Steht die Kamera in der Mitte ihres Bereichs, zieht nichts nach. Je näher sie in Schubrichtung ihrer Grenze kommt, desto stärker wird die Stick-Mitte zum Finger gezogen (bis 8/s, quadratisch); an der Grenze geht die Mitte in dieser Achse direkt mit dem Finger mit. Weiter als der Radius (480 Bildpunkte) schleift der Ring am Rand mit.
- Ohne Stick-Auslenkung steht die Kamera still (kein automatisches Nachführen, kein Ruck). Grenze: Die Streckenkante (plus Bankett) darf bis in die Mitte des freien Sichtbereichs kommen.
- Tests: `test_flow.gd` prüft Stick am Berührpunkt, Kamerafahrt, Weiterzeichnen mit ruhendem Finger und Loslassen. Kontrollbild: `game/tests/stick_shots.gd`.
- Nachschärfung 27.09.2026: Höchsttempo der Linie (29 m/s) schon bei halbem Zeichentempo (Faktor 0,76 statt 0,38 in `recorder.gd`). Langsame Linie 3x so breit (Halbbreite 0,96 statt 0,32 m in `world.gd`). Stick-Kreis standardmäßig unsichtbar, einblendbar über „Stick-Kreis anzeigen“ (Schlüssel `stick_visible`).

## Handkamera und Wiederansetzen beim Zeichnen (27.09.2026)

Ersetzt Zeichen-Zoom-Regler, automatische Nachführung und Kamera-Stick (Nutzerentscheidung: Kamerabewegung beim Zeichnen stört).

- **Kamera:** Ziehen mit einem Finger verschiebt, zwei Finger zoomen um den Punkt zwischen den Fingern, Doppeltipp auf eine freie Stelle zeigt wieder die ganze Strecke. Zoom von „ganze Strecke im freien Sichtbereich“ bis „Fahrbahn füllt die kürzere Seite“; die Streckenkante darf bis in die Mitte des freien Bereichs kommen. Am PC: Mausrad zoomt. Von Android aus Berührungen erzeugte Maus-Ereignisse werden ignoriert.
- **Malen oder Kamera:** Gemalt wird nur, wenn der Finger im offenen Linienende (bzw. am Startpunkt) aufsetzt; Greifradius 64 Bildpunkte, unabhängig vom Zoom. Kommt ein zweiter Finger innerhalb von 0,15 s und bevor sich der erste bewegt hat, wird daraus ein Zoom und der Malbeginn verworfen; später kommende Finger werden ignoriert.
- **Malzeit:** zählt nur mit Finger auf dem Display (`LineRecorder.draw_time`).
- **Fest / offen / Probe** (`recorder.gd`): Werte älter als 1 s Malzeit sind fest. Jüngere sind offen, die Linie schimmert dort (Helligkeitspuls). Dort darf neu angesetzt werden; nur Punkte der eigenen Linie zählen, an der Kreuzung der Acht also nie der andere Ast. Ein neuer Ansatz ist eine Probe; der alte Rest bleibt als dunkler Schatten sichtbar. Nach 0,5 s Malzeit ab der ersten Bewegung wird die Probe bestätigt: Der alte Rest verschwindet, das Tempo wird linear vom Wert am Ansatzpunkt zum erreichten Wert geglättet. Hört man früher auf oder bricht der Strich an einer Grenze ab, wird die Probe verworfen und die alte Linie samt Malzeit wiederhergestellt. Die endgültige Zieldurchfahrt bestätigt sofort.
- **Zwischenstände:** Je Abtastung werden Fortschritt, Wegpunkt-Tore, Glättungszustand und Malzeit gespeichert; Rücksetzen stellt sie exakt her (keine doppelt gezählten Tore).
- **Allererster Strich:** Es gibt keinen alten Wert, also keine Glättung. Unter 0,5 s bleibt die Strecke leer.
- **Darstellung:** Die Linie ist ein durchgehendes Band mit gemittelten Normalen (keine Zacken bei breiter Linie). Offener Teil und Schatten sind deckend gezeichnet.
- **Tests:** 10 neue Prüfungen in `test_core.gd` (Rekorderlogik mit festen Zeitstempeln), 9 in `test_flow.gd` (Kamera- und Fingerlogik). Kontrollbilder: `game/tests/resume_shots.gd`.
- Nachtrag: Regler „Tempo der Linie“ (Schlüssel `draw_tempo`, 0..1, Standard 0,5). Mitte = Grundwert 0,38 wie vor der automatischen Kamera (Höchsttempo bei ~63 m/s Zeichentempo). Der Regler arbeitet logarithmisch: links −50 % (0,19), rechts +100 % (0,76). `LineRecorder.tempo_from_setting()`, 2 neue Prüfungen in `test_core.gd`.
- Menü: Die Bedingung der Herausforderung steht in einer eigenen Zeile unter den Rivalen-Knöpfen (vorher überlappte sie die Überschrift).

## Grafik-Umbau, Teil 1: Premium-Stufe (27.09.2026)

**Renderer:** Mobile-Renderer (Vulkan) mit automatischem Rückfall auf OpenGL (`rendering_device/fallback_to_opengl3`). Premium-Grafik nur mit Vulkan (`Diorama.premium_rendering()`); auf OpenGL bleibt die bisherige Klötzchen-Grafik (Stufe für schwache Handys).

**Asset-Kette (lokal, alles frei entworfen):**
1. `tools/make_image_prompts.py` → `art/bildvorlagen/*.txt`: je Objekt ein Bild-Prompt mit festen Regeln (freigestellt, links vorne, 20–30° von oben, keine Schrift/Marken; Autos hellgrau). Bilder erzeugt der Nutzer mit ChatGPT → `art/bildvorlagen/bilder/`.
2. `tools/cutout.py` → `art/bildvorlagen/freigestellt/`: weißen Hintergrund transparent machen (Durchblicke bei Pflanzen/Gittern).
3. `tools/ai3d_batch.sh` / `tools/ai3d_batch.py`: TRELLIS.2 (vorhandene 3D-Werkstatt in WSL, zweite RTX 3090), Pipeline einmal laden, Ergebnisse nach `.tools/ai3d/runs/<name>/`.
4. Autos: `tools/build_cars.ps1` + `tools/ai_car.py` (Einstellungen `tools/ai_cars.json`): Längsachse ausrichten, vorn/hinten an den roten Rückleuchten erkennen, auf Spiellänge skalieren, KI-Räder herausschneiden, Radradius am Modell messen, eigene bewegliche Räder (`make_car.py`) und dunkle Radhaus-Schalen einsetzen, Texturen 1024 px/JPEG → `game/assets/cars/<stil>.glb` (~2 MB je Auto).
5. Kulisse: `tools/build_props.ps1` + `tools/ai_prop.py`: auf Höhe 1 normieren, auf Dreiecksbudget ausdünnen (Bäume 2.500, Häuser bis 9.000), Texturen 256–1024 px → `game/assets/props/<name>.glb`.

**Im Spiel:**
- Autos: Lack-Shader `assets/cars/car_paint.gdshader` tönt den eingebackenen hellgrauen Lack (helle, ungesättigte Texel, im sRGB-Raum erkannt) in der Wagenfarbe, mit Klarlack; Scheiben/Kunststoff bleiben. `PAINT_SAT` je Stil für farbstichig gebackenen Lack. Räder drehen mit dem gefahrenen Weg, lenken ein; die Karosserie nickt/wankt aus der Beschleunigung (nur Darstellung).
- Fahrbahn: `assets/road.gdshader` mit Körnung, Nässe, Pfützen an festen Weltkoordinaten und echter Spiegelung: gespiegelte Kamera unter der Fahrbahnebene rendert Ebene 1 (Aufragendes) in halber Auflösung, nur bei Regen ab Qualität „Mittel“. Flaches liegt auf Ebene 2 (`sort_layers`).
- Gelände: `assets/terrain.gdshader` – Rasen mit Farbschwankungen, trockenen Stellen, Mähstreifen (Küste); Erd-Bankett mit per Rauschen unregelmäßigem, weich auslaufendem Rand (Abstandskarte zur Streckenmitte, beim Aufbau berechnet); Schnee/Nässe.
- Kulisse: Deko-Typen des Streckenformats werden auf KI-Modelle abgebildet (`premium_prop`), je Modell ein MultiMesh. Lichtflecken und Schriftzüge bleiben.
- Funken bei Kollisionen (`RaceVehicle.resolve_contact` liefert die Aufprallgeschwindigkeit, Simulation unverändert).
- Kontrollbilder: `tests/car_shots.gd`, `tests/car_lineup.gd`, `tests/mirror_test.gd`, `tests/spark_test.gd`.
- Nachbesserungen nach Gerätetest (S24: 112 FPS bei höchster Qualität):
  - Zittern in Fahrtrichtung behoben: Die Autos werden zwischen zwei 60-Hz-Physikschritten interpoliert dargestellt (`place_models`, `render_pos`), die Kamera folgt der interpolierten Position. Die Simulation bleibt unverändert.
  - Regen: kürzere, schräge Tropfen, die am Boden enden; Aufschlagringe im Fahrbahn-Shader (in Pfützen kräftiger). Niederschlag liegt auf Ebene 2 und wird nicht gespiegelt (vorher „fielen“ die Tropfen in der Pfütze nach oben).
  - Randsteine als durchgehendes Band je Seite (`curb_band`): Segmentgrenzen quer zur Strecke, keine Überlappung und kein Flackern in der Innenkurve, keine Lücken außen.
  - Stadthäuser werden gleichmäßig skaliert statt gestreckt.
- Waldbäume mit höherem Budget (Kiefer 9.000, Eiche 10.000 Dreiecke), sonst verschwinden Nadeln und Blätter beim Ausdünnen. Der Busch scheitert in TRELLIS am Grafikspeicher und wird nicht verwendet.
- Lichtflecken der Laternen liegen über den Randsteinen (0,30 m), damit diese mitbeleuchtet werden.
- Gezeichnete Linie im Rennen: 70 % durchsichtig und beleuchtet wie Fahrbahnmarkierung (nachts dunkel, unter Laternen hell) statt selbstleuchtend.

## Update-Funktion (27.09.2026)

- `game/scripts/updater.gd`: Prüft `https://api.github.com/repos/ShakieVan/Draw2Race/releases/latest` (automatisch höchstens einmal täglich beim Start auf dem Handy, sonst über Optionen → „Updates“). Angenommen wird nur ein fertiges Release (kein Entwurf/Vorabversion) mit Tag `vX.Y.Z`, genau einer Datei `Draw2Race-X.Y.Z.apk`, Größe ≤ 512 MB, SHA-256-Angabe der GitHub-API und exakt erwarteter Download-URL.
- Download nach `user://updates/<sha256>.apk`, danach Größe und SHA-256 prüfen (in eigenem Thread).
- `game/android/build/src/main/java/com/godot/game/Updater.java` (Aufruf per `JavaClassWrapper`): Paketname gleich, Versionscode höher, Versionsname wie im Release, Signatur identisch zur installierten App; dann System-Installer über den FileProvider der Godot-Bibliothek (`<paket>.fileprovider`). Fehlt die Android-Erlaubnis „Apps installieren“, öffnet sich die passende Einstellung.
- Oberfläche: Menü-Knopf „Update ↓“, sobald eine neuere Version vorliegt; Dialog mit installierter/neuer Version, Release-Notizen, Fortschritt und Aktion (Suchen/Herunterladen/Installieren).
- Voraussetzungen: Gradle-Export (`gradle_build/use_gradle_build=true`, Vorlage in `game/android/build`), Berechtigungen INTERNET und REQUEST_INSTALL_PACKAGES. `org.gradle.daemon=false`, sonst hält der Gradle-Dienst die Ausgabe offen und der Export kehrt nicht zurück.
- Versionen: `application/config/version` in `project.godot` und `version/name` im Exportprofil müssen übereinstimmen, `version/code` muss je Release steigen (`tools/build.ps1` prüft die Namen und legt `builds/Draw2Race-<version>.apk` an).
- Release veröffentlichen: `gh release create vX.Y.Z builds/Draw2Race-X.Y.Z.apk`.
- Nummernschema (Nutzerentscheidung 03.10.2026): Ein reguläres Release endet immer auf `.0` und hebt die mittlere Stelle (0.3.0, 0.4.0 …). Betas zählen danach die letzte Stelle hoch (0.3.1, 0.3.2 …). Wird eine Beta zum Release, wird sie mit der nächsten `.0`-Nummer und höherem `version/code` neu gebaut. So liegt jedes Release über allen Betas davor, und ein Beta-Handy bekommt das Release als normales Update, in beiden Kanälen. Der Updater vergleicht nur Zahlen (`X.Y.Z`); Zusätze wie `-beta` würden ältere Fassungen ablehnen.
- Tests: 3 Prüfungen in `test_core.gd` (Versionsvergleich, gültiges Release, Ablehnung fremder URL/Entwurf/fehlender Prüfsumme).
- Regen nur im Licht (`assets/rain.gdshader`): Tropfen ohne Eigenfarbe, additiv; Helligkeit = Tageslicht + Lichtkarte der Straßenlichter (beim Aufbau berechnet, `Atmosphere.bake_rain_lights`) + Scheinwerferkegel/Rücklichter der Autos (live, `update_rain_cars`). Zum Boden hin heller als Tiefenhinweis in der orthografischen Draufsicht.
- Kontrollbild-Aufrufe immer mit `timeout`/`--quit-after`: Bricht ein Skript beim Laden ab, erreicht das Testskript sein `quit()` nie.
- 0.2.2: Lichtkranz des eigenen Autos über den Randsteinen; Linie halb so breit (langsam 0,48 m, schnell 0,05 m) und schon bei mittlerem Tempo schmal (Breite ~ Tempo^0,4); im Rennen dezentes Eigenleuchten (Emission 0,16), damit sie nachts zu ahnen bleibt.
- 0.2.3 – APK von 345 auf 172 MB: nur noch ARM64 (x86_64 war nur für PC-Emulatoren), Programmbibliothek gepackt (`gradle_build/compress_native_libraries`), Musik aus den verlustfreien Originalen neu mit Vorbis q2 (~96 kbit/s, ~0,64 MB/min; `QUALITY` in `export_music.py` des AudioLab), 110 → 67 MB. Verbleibend: Texturen 51 MB, Szenen 19 MB.
- 0.2.4 – vorberechnetes Laternenlicht mit weichen Schatten und indirekter Beleuchtung (Premium): Beim Streckenaufbau entsteht eine Draufsicht-Lichtkarte aller Straßenlichter (`Atmosphere.bake_rain_lights`, 256², Radius 1,8 × Lichtscheibe, 7–80 ms). Größere Bauten (`occluders`, aus `place_ai`) werfen Schatten; Unschärfe durch Verkleinern/Vergrößern. Die Karte ist ein globaler Shaderwert (`[shader_globals]` in `project.godot`, `assets/lamp_light.gdshaderinc`) und wird von Fahrbahn (diffus + Glanz, bei Nässe stärker), Gelände, Lack der Autos, Regen und über `assets/lit_overlay.gdshader` (material_overlay) von Kulisse, Randsteinen und Markierungen gelesen: zugewandte Flächen direkt beleuchtet, untere Wandbereiche indirekt vom Boden aufgehellt. Die additiven Lichtscheiben entfallen im Premium-Modus. Sonne mit Halbschatten (`light_angular_distance` 1,2, `shadow_blur` 1,5).
- 0.2.5 – Straßenlaternen zur Fahrbahn ausgerichtet: Ausleger-Richtung aus dem Modell ermittelt (`ai_arm`: oberste gegen unterste 8 % der Punkte), gedreht zur nächsten Streckenstelle; Lichtkegel unter dem Leuchtenkopf.
- 0.2.6 – Leistung Wald (vorher 15 FPS auf dem S24, geschätzt ~7,5 Mio. Dreiecke/Bild): KI-Kulisse je Modell in 24-m-Kacheln (Aussortieren außerhalb des Bildes), vereinfachte Fassung `<name>_lo.glb` (~1/6 Dreiecke, `build_props.ps1`) für Schatten und Übersicht (`set_detail`, Kamera-Ortho-Größe < 26 = volle Modelle), Zusatzlicht-Durchgang nur bei Dunkelheit (`set_overlays`). Gemessen (`tests/render_load.gd`): Wald 0,2–0,7 Mio. Dreiecke/Bild, Küste/Stadt 0,1–0,34 Mio.
- 0.2.7 – Bäume als Bildkarten (Billboards, `assets/cards/tree_card.gdshader`, 2 Dreiecke je Baum) aus den freigestellten ChatGPT-Bildern (`tools/make_cards.py`: zuschneiden, weiße Säume entfernen – fast reines Weiß überall, Mischpixel im 4-px-Randstreifen – Maske um 2 px verkleinern, Farbe ausbluten, Höhe 512 px). Karten zur Hauptkamera gedreht (auch im Schattendurchgang), Höhe auf 65 % gestaucht (Projektion eines senkrechten Baums bei ~53° Blickwinkel), Größe ±15 %, zufällig gespiegelt, Laternenlicht über die Lichtkarte. Wald jetzt 0,13–0,35 Mio. Dreiecke/Bild.
- 0.2.8 – Ruckeln auf Schotter behoben: Reifenspuren als Ringpuffer-MultiMesh (`setup_track_ring`, `assets/tyre_track.gdshader`, Ausblenden per Shader über die Entstehungszeit) statt Neuaufbau des ganzen Netzes alle 8 Physiktakte (bis ~25.000 Eckpunkte in GDScript). Physiktakt im Wald am PC 9,7 → 1,9 ms im Mittel (`tests/frame_spikes.gd`).

## Neue Strecken, Teil 1: 2,5D-Unterbau, Hafenviertel, Serra-Pass (27.09.2026)

Leitplanke 8 erweitert (Nutzerentscheidung): Fahrdynamik in der Ebene plus Höhe.

- **Physik (`vehicle.gd`):** `z`, `vz`, `airborne`, `landing`, `crashed`. Am Boden folgt z der Fahrbahn (Steigrate ≤ 25 m/s); Abheben nur, wenn der Boden > 5 cm unter die ballistische Bahn fällt (Federung schluckt Knicke). In der Luft keine Reifenkräfte, kein Antrieb/Bremsen, nur Luftwiderstand; nach der Landung baut sich die Haftung über 0,35 s auf. Hangabtrieb entlang der Fahrtrichtung. Looping: autonome Durchfahrt (`step_loop`), Absturz bei fehlender Anpresskraft oder Stillstand. Abgrund neben der Fahrbahn (Gelände > 2,5 m unter der Straße): mit Leitplanke Abprallen, ab 9 m/s senkrecht bricht sie → Absturz; ohne Leitplanke Absturz.
- **Streckenformat (`track.gd`), alles optional:** `open` (Sprint, eine Durchfahrt, `laps` sonst 2), `elevation`, `ramps`, `gaps`, `loops`, `shortcuts` (Pfad mit gleitendem Streckenanteil; übersprungene Tore zählen), `terrain` (Höhenraster), `guardrails`. Offene Strecken: eigene Spline-/Abtastlogik (`wrap_index`, `span`, `unit`).
- **KI:** Mindesttempo vor Loopings (√(5gR)·1,15) und Lückensprüngen (`momentum_needs`).
- **Zeichnen:** Tore und Fortschritt für `laps`; Abkürzungspfade (`place`, `sc` je Routenpunkt); Touch trifft die Fahrbahn auch auf Höhe (`world_point` iterativ).
- **Darstellung:** Fahrbahn, Randsteine, Linie, Marker, Reifenspuren folgen der Höhe; Stützpfeiler nur über tiefem Gelände; Holzschanzen, halbtransparenter Looping-Ring, Geländenetz aus dem Raster (Felswände ab Neigung 0,9), Abkürzungsfahrbahn, Wasserflächen (`water`), generischer Baustein `ai` (KI-Modell, Klötzchen-Ersatz solange es fehlt). Abgestürzte Autos fallen sichtbar. Ergebnis „Abgestürzt!“ ohne Wertung.
- **Hafenviertel (`harbor`, 327 m):** schräge Straßenzüge, Abkürzung durch die Lagerhalle (offenes Tor, umgefahrene Absperrung als Hinweis), Holzschanze über ein Hafenbecken.
- **Serra-Pass (`serra`, 320 m Sprint):** Küstenstraße an der Steilküste, vier Kehren bergauf (14 → 41 m), Gelände aus Straßenhöhen (Hang, Böschungen, Steilküste), Leitplanken automatisch dort, wo es steil abfällt.
- **Tests:** `tests/test_air.gd` (25 Prüfungen: Schanze, Landung, Lücke, Looping, Sprint, Abkürzung, KI-Mindesttempo, Steigung, Brückenrand, Gelände, Leitplanke hält/bricht, KI im Ziel auf beiden neuen Strecken).

## Neue Strecken, Teil 2: Rummel, Steinbruch, Drift-Arena, Kinderzimmer, Geisterauto (27.09.2026)

- **Fun Fair Eight (`fair`, 340 m):** wellige Acht zwischen Riesenrad und Buden. An der Kreuzung springt der obere Ast per Schanze (7 m, 1,8 m hoch) über den unteren; übereinander fahrende Autos berühren sich nicht (`resolve_contact` prüft Höhenabstand, Looping, Absturz).
- **Quarry Loop (`quarry`, 354 m, Schotter):** Looping (r 3,2 m) auf der langen Geraden, Schanze über einen 6-m-Graben, Kicker, Schotter-Abkürzung, Matschzone.
- **Drift Arena (`arena`, Drift-Modus):** neues Streckenfeld `widths` (Breitenprofil; `track.hw(s)`, Darstellung über `edge_offset`), weite Flächen (8 m halbe Breite) und zwei Nadelöhre (2,6 m). `mode: "drift"`: nur das eigene Auto, Punkte = Driftwinkel × Tempo × Zeit × Multiplikator (bis ×4 bei durchgehendem Drift), Wandberührung −60 Punkte und Multiplikator zurück. Zeitlimit 1,4 × vorsichtige KI-Fahrt (`drift_limit`), Punkteziele je Herausforderung `drift_targets` (600/1100/1600). Bestenliste nach Punkten (`progress.result_drift`), eigenes Ergebnisblatt.
- **Toy Box Speedway (`kids`, 324 m, Bonus):** Spielzeugbahn (Theme `kids`: orangefarbene Fahrbahn über Theme-Feld `road`, Parkett aus Dielen) mit Looping (r 4 m), Sprung über eine Bücherlücke und Teppichzone. Freischaltung nicht über die Vorgängerstrecke, sondern ab 12 Gold insgesamt (`BONUS_TRACKS`).
- **Neue Autos:** Col Racer (12 Gold, wendig), Quarry Truck (15 Gold, geländestark), Drift King (18 Gold, `rear` 0,36: Haftungsanteil der Hinterachse kleiner, Heck bricht williger aus).
- **Geisterauto:** Nach einem Rekord werden Linie und Turbo-Einsätze in `user://ghosts/<strecke>_<herausforderung>.json` gespeichert (nur bei gleicher Physikversion wiedergegeben). Beim nächsten Rennen fährt die Bestfahrt als halbtransparentes Auto ungestört mit – keine Berührungen, keine Platzierung. In den Optionen abschaltbar; im Drift-Modus und in Vorführfahrten aus.
- **Menü:** Streckenwahl zweizeilig; Bestenliste mit Strecken über die volle Breite und Herausforderungen darunter (vorher überlappten die Knöpfe ab 8 Strecken).
- **Tests:** `test_air.gd` 32 Prüfungen (u. a. KI im Ziel auf Hafen, Pass, Rummel, Steinbruch, Kinderzimmer; Drift-Wertung), `test_flow.gd` 37 (Geist gespeichert, fährt mit, zählt nicht als Rivale).

## Looping, Hafen, Beta-Kanal, Perspektivkamera und Diorama-Prototyp (28.–29.09.2026)

- **Looping als Schraubenbahn (`track.gd`, `vehicle.gd`, `world.gd`):** Einfahrt links, Ausfahrt rechts (`loop_lateral`, `loop_basis`); die Bahn läuft an sich selbst vorbei. Zu wenig Schwung: unterhalb der Senkrechten rollt das Auto zurück (`rolled_back`), darüber fällt es vom Band (`loop_fall`), landet auf dem Bahnstück darunter und rutscht auf dem Dach hinunter (`loop_fall_pose`, nur Darstellung). Das Ergebnisfenster erscheint erst nach dem Absturz (`crash_wait`).
- **Hafen:** Kaikante (`quay_z`, `quay_dir`), dahinter offenes Meer; Containerbrücken als KI-Modell (Fahrwerke prüfen: Räder in Fahrtrichtung, Schienen parallel zum Kai), Frachter als KI-Modell, einfachere Fassung `hafen_frachtschiff_einfach` für die Qualitätsstufe „Niedrig“ (`LOW_VARIANTS`), Grundformen-Ersatz für die einfache Grafik. Die Strecke ist an der x-Achse gespiegelt (`mirror_z`).
- **Vereinfachte Fassungen (`_lo`):** nur für Massenware (ab `MASS_COUNT` Exemplaren je Strecke); Gebäude und Blickfänge (`ALWAYS_FULL`) bleiben immer voll. Automatische Grundform-Erzeugung wurde getestet (Voxelraster, Neubacken, MeshLab) und verworfen: die KI-Modelle sind dünne, offene Hüllen.
- **Modellaufbereitung:** `tools/ai_prop.py` entfernt lose Krümel (<0,1 % der Fläche); `tools/mesh_check.py` prüft Netze (offene Kanten, Krümel, entartete Flächen) und rendert Vorschauen; Texturen der Modelle werden verlustbehaftet importiert (`tools/build.ps1`), die APK schrumpfte dadurch von 297 auf 162 MB.
- **Beta-Kanal:** Testversionen erscheinen als Pre-Release im eigenen Repo `ShakieVan/Draw2Race-Beta`; unter Optionen → Updates schaltet „Beta-Versionen erhalten“ die Suche in beiden Repos ein (die höhere Version gewinnt, `updater.gd`).
- **Perspektivkamera (`main.gd`):** Zeichnen senkrecht von oben, Rennen geneigt (`PITCH_DRAW`, `PITCH_RACE`); `cam_zoom` ersetzt die frühere orthografische Größe.
- **Diorama-Prototyp Stadt (`tools/diorama.py`):** Blender baut aus der Streckendatei Straße, Randsteine, Gehwege, Kreuzungen an den Ecken (Straßen laufen geradeaus weiter und enden an Absperrungen), Seitenstraßen an Geraden, Häuserreihen und Blockfüllung, Bäume, Brunnen und backt die Umgebungsverdeckung in eine Lichttextur (`<id>_ao.jpg`, zweite UV-Ebene). Begleitdatei `<id>_layout.json` nennt die Straßenflächen; Laternen darauf entfallen (`diorama_blocks`). Dünne Markierungen und Absperrungen schreiben nicht in die Lichttextur. Texturen: CC0-Sets von ambientCG (`art/texturen/HERKUNFT.md`).
- **Bildvorlagen Runde 3:** vier Stadtbäume mit dichter Krone (`stadt_baum_*`); Erzeugung über die Bild-KI, Umrechnung lokal.
- **Zurückgestellt:** Streckenpakete (nachladbare Strecken und Autos) sowie die Freigabe der neuen Strecken, bis die Grafik auf Zielniveau ist.

## Diorama-Bausatz, Regen-Entlastung und Besprechung (30.09.2026)

Grundlage: Nutzerrückmeldung zur Beta 0.2.15 (Häuser „verkrüppelt“, Regen kostet 40–50 FPS beim Herauszoomen, Leitwände durch Poller ersetzen, Sackgassen wirken fehl am Platz) und die Besprechung mit GPT-6 Astra (`docs/BESPRECHUNG_GRAFIK.md`).

- **Häuser aus dem Bausatz (`tools/kit_house.py`, `tools/make_kit_textures.py`):** Die KI-Häuser der Stadt entfallen. Ein Haus entsteht aus Fassaden- und Erdgeschosskacheln (fünf Stile: Altbau, Backstein, Plattenbau-Riegel, Büro mit Glasfassade, moderner Putz; zwei Erdgeschosse: Läden, Eingänge), Dächern (Kies, Bahn, Ziegel, Schiefer, Blech), Traufgesims, Attika mit Abdeckung, Randschatten der Dachhaut und Aufbauten (Fahrstuhlhaus, Lüfterkästen, Schornsteine, Wassertank, Oberlichter, Solarfeld). Haustypen: Reihenhaus (Satteldach), Stadthaus (Flach-/Walmdach), Eckhaus (L-Grundriss), Riegel, Bürohaus. Breiten und Tiefen sind auf Fensterfelder gerundet, Muster je Haus verschoben. Im Mittel ~190 Dreiecke je Haus (vorher ~3000).
- **Texturen prozedural:** `tools/make_kit_textures.py` (numpy, scipy, Pillow) schreibt Albedo, Normalkarte und Fensterlicht-Maske nach `game/assets/kit/` (`kit.json` nennt die Kachelmaße). Kein fremdes Material. `tools/build.ps1` stellt die Importe auf Mipmaps und Grafikkartenkompression um.
- **Im Spiel (`world.gd`):** Materialien `K_*` der Diorama-Datei werden durch `kit_material()` ersetzt (Albedo, Normal, Fensterlicht als Emission mit Multiplikator statt Addition, Vertexfarbe = Putzton und Verschattung). `set_windows(level)`: Fensterlicht 0 (Tag) / 0,55 (Dämmerung) / 1 (Nacht), unter der Glühschwelle (sonst verschmieren die Fenster). Laternenlicht als Zusatzdurchgang nur für Häuser nahe der Strecke, weich abgefangen.
- **Ein Objekt je Oberfläche:** `Haus_nah_*` (näher als 24 m an der Rennstrecke, spiegelt sich in der nassen Fahrbahn) und `Haus_fern_*`. Zusammengeführt statt 118 Einzelobjekten.
- **Stadtraster:** erste Reihe hinter dem Gehweg der Rennstrecke, Reihen entlang der Zufahrten, Blockreihen (Ost-West-Linien, Fassaden einander zugewandt), Infill an den Achsen ausgerichtet; der Park im Inneren bleibt frei.
- **Szenenrezept:** `tools/diorama.py` schreibt `<id>_recipe.json` (Häuser mit Typ, Maßen, Seed, Lage; Bäume; Laternen) als gemeinsame Quelle für spätere Vorschau und Companion-App.
- **Absperrschranken statt Leitwand und Poller (Nutzerwunsch 30.09.):** einzelne Baustellen-Absperrungen (Länge 2 m, zwei rot-weiß gefelderte Bretter, senkrechte Latten, Gummifüße, rote Warnleuchte) entlang des äußeren Bogens (~2,4 m Abstand, nur auf Fahrbahn, keine ohne Querstraße) und quer über das Ende jeder Zufahrt (`barrier_segment` in `tools/diorama.py`). Die Warnleuchten blinken bei Dämmerung und Nacht (`world.gd`, `blink_materials`).
- **Nebel und Schnee ohne Eigenleuchten (Nutzerwunsch 30.09.):** Nebelbänke (`assets/fog_bank.gdshader`) und Schneeflocken (`assets/snow.gdshader`) sind nur so hell wie das Licht an ihrer Stelle: Umgebungs- und Sonnen-/Mondlicht relativ zum Tag (`Atmosphere.light_rel`, nachts klein) plus Laternenlicht aus der Lichtkarte (glimmt um die Laternen, Schatten der Gebäude), Schnee zusätzlich Scheinwerfer/Rücklichter der Autos. Der Tiefennebel der Umgebung (`fog_light_color`) folgt dem gleichen Licht (nachts dunkel) und wird zu 40 % entsättigt.
- **Fahrbahnverschleiß:** `road.gdshader` (`wear`): Ausbesserungsflecken, feine Risse und vereinzelte Ölflecken in Weltkoordinaten, nur im Diorama.
- **Keine Sackgassen:** Zufahrten kürzer als 10 m entfallen; die Seite wird mit Randstein und Gehweg geschlossen. Zebrastreifen nur noch auf den Rennstraßen.
- **Laternen aus dem Bausatz (`tools/make_lamp.py`, `stadt_laterne_kit.glb`):** Stahlmast, Ausleger mit Strebe, flacher Kopf mit Leuchtfläche (Material `K_lampe`); Mast steht genau auf dem Platz (`POLE_MODELS`), Lichtkegel genau unter dem Kopf (`LAMP_HEAD`).
- **Bäume leichter:** `tools/make_tree.py` mit Feinheit 2 (~1200 statt ~5500 Dreiecke).
- **Regen:** Nur Bauten und Bäume näher als 24 m an der Strecke gelangen in die Spiegelkamera (Ebenen); die Spiegelung ist aus, solange die Kamera senkrecht (> 82°) oder weit weg (Zoom > 0,66 der Übersicht) ist (`Atmosphere.limit_reflection`, Hysterese). Eine einzige orthogonale Sonnenschattenkarte statt vier Teilbereichen, Reichweite folgt der Kamera (`fit_shadow`). Pfützen kleiner, Spiegelbild entsättigt (keine violetten Flächen mehr).
- **Messung** (`tests/rain_cost.gd`): Übersicht 1,57 → 0,81 Mio Dreiecke trocken, Regen 3,06 → 0,86 Mio (Spiegel in der Übersicht aus); Rennansicht 1,13 → 0,43 Mio, Regen 2,0 → 0,89 Mio. Diorama-Szene 412k → ~100k Dreiecke.
- **Tests:** `tests/dio_shot.gd` (Umgebungsvariablen NOOVERLAY/NOWINDOWS/NOGLOW/WINLEVEL), `wide_view.gd` (ganze Stadt), `dio_stats.gd` (Dreiecke je Gruppe), `kit_debug.gd`, `rain_cost.gd`.
- **Linienfarbe grün → rot (Nutzerwunsch 30.09.):** `Diorama.line_color` läuft von Grün (langsam, breit, zart) über Gelb und Orange zu Rot (schnell, schmal, satt); Legende und Hilfetext ziehen mit.
- **Schneedecke (Nutzerwunsch 30.09.):** `assets/snow_cover.gdshader` als `material_overlay` über allen Dioramenteilen außer Fahrbahn und Wasser (Boden, Gehwege, Randsteine, Dächer, Kronen nur oben, Markierungen scheinen durch); die Fahrbahn deckt der Straßen-Shader zu ~90 % ab („kaum Straßenkonturen“). Der Schnee wird wie alles beleuchtet und erhält Laternenlicht (nicht auf Dächern). `World.set_snow` / `refresh_overlays` schalten Zusatzlicht (Nacht) und Schnee um.
- **Niederschlag ohne Grenze:** Regen- und Schneeemitter folgen der Kamera (`Atmosphere.follow_view` aus `main.set_camera`: Emissionsbox = sichtbarer Bereich samt Rand); Flocken leben lang genug, um den Boden zu erreichen. Nebelbänke treiben über das ganze Diorama (`set_area`).
- **Laternenlicht über die ganze Stadt:** Die Lichtkarte deckt das Diorama (Begleitdatei `extent`), 512 Zellen, Häuser als Schattenwerfer (Begleitdatei `occluders`, Gebäudemaske statt Strahlenprüfung je Gebäude); Laternen an Zufahrten stehen dichter.
- **Tiefgarage statt Sackgasse (Nutzerwunsch 30.09.):** Die kurze T-Zufahrt (< 20 m) ist eine Tiefgaragen-Ein-/-Ausfahrt (`build_garage` in `tools/diorama.py`): Vorplatz mit Schranken, Rampe zwischen Stützwänden (zwei Spuren, Pfeile rechts hinein/links heraus), Betonhaube mit dunklem Portal, gelb-schwarzen Pfeilern und leuchtendem P-Schild.
- **Schwarze Ränder an Zufahrten:** Bodenkacheln entfallen nur noch, wenn sie ganz unter einer Straßenfläche liegen (vorher Lücken bis 0,5 m, durch die der dunkle Untergrund sichtbar war).
- **Ansichtsgrenze beim Zeichnen:** `main.clamp_view_state` hält das sichtbare Stück Boden (zwischen den HUD-Leisten) höchstens `HALF_WIDTH + 6 m` hinter der Streckenkante; ist es in einer Richtung größer als die Strecke (breiter Bildschirm), bleibt die Ansicht dort mittig. Zoomen um den Fingerpunkt rechnet vor der Begrenzung. Prüfung: `tests/view_limit.gd`.
- **Bekannte Grenzen:** Trees noch als Einzelobjekte (Aufrufe); harte Grenze zwischen Rasen und Pflaster (0,5-m-Raster); Gelände noch flach; Lichthöfe der Laternen kräftig.

## Motorklang je Auto (30.09.2026)

Nutzerwunsch: Der Motor klang dürftig und bei allen Autos gleich; er soll zum gewählten Auto und zu denen der Gegner passen.

- **Erzeugung (eigene Synthese, kein fremdes Klangmaterial):** `tools/make_engine_sounds.py` baut je Auto sechs Drehzahlschichten (nahtlose, im Frequenzbereich exakt periodische Schleifen) für „Last“ (Gas) und „Schub“ (Gas weg) sowie Turbo-/Kompressorschleife, Schubumluftventil und vier Fehlzündungen. Modell: Zündfolge je Zylinder (Reihe, Boxer, Kreuzwellen-V8) mit Zeit- und Stärkeschwankung → Druckimpuls in Kurbelwinkel-Skalierung → Abgasanlage als Kammfilterkette → Formanten → Ansaug-/Verbrennungsrauschen im Takt der Zündungen. Acht Profile in `PROFILES`: Sprint (Vierzylinder), Grip (Dreizylinder), Dirt Hawk (Boxer mit Blubbern), Thunder V8 (Kreuzwelle mit Kompressor), Apex GT (V12), Col Racer (hochdrehender Vierzylinder), Quarry Truck (Diesel-Sechszylinder mit Nageln), Drift King (Sechszylinder mit Fehlzündungen). Ausgabe: `game/assets/sfx/engines/` (112 WAV, 22,05 kHz, mono, 16 Bit, 6,7 MB, dazu `engines.json` mit Drehzahlen, Schleifenlängen und Kennwerten). Der Import bleibt verlustfrei (`tools/build.ps1` stellt die Godot-Vorgabe QOA auf PCM um).
- **Objektive Kontrolle (Claude kann nicht hören):** `tools/check_engine_sounds.py` (Zündfrequenz gegen Sollwert, Spektrogramm-Bogen, Sprung an der Schleifennaht), `tools/render_engine_sweep.py` (Probefahrt aus den Schichten: Leerlauf, Vollgas durch vier Gänge, Gas weg) und `tools/tag_engine_sounds.py` (AudioSet-Klassifikator AST). Der erste Syntheseentwurf wurde als „Sirene/Regen/Rauschen“ erkannt; erst Unregelmäßigkeit von Zündung zu Zündung, Amplitudenrauheit und breitbandiges Rauschen im Takt der Zündungen brachten „Fahrzeug/Auto/Motor“. Bewertung der Probefahrten (Summe aus Fahrzeug, Auto, Motor, Beschleunigen, Leerlauf): Rally 0,95, Muscle 0,93, Sprint 0,88, Grip 0,87, Pickup 0,85, Drift 0,83, GT 0,82, Roadster 0,75. Zuerst lagen GT (0,45) und Drift (0,49) weit hinten: Sehr hohe Zündfrequenzen erkennt der Klassifikator nicht als Motor. Niedrigere Höchstdrehzahl (Sprint 7200, Drift 7600) und beim GT ein V12 bei 8600 U/min brachten die Wende; der Roadster blieb bei 8800 U/min, weil Absenken ihn verschlechterte (Erkundung mit Profilvarianten, `tools/make_engine_sounds.py`). **Die menschliche Hörabnahme steht aus.**
- **Im Spiel (`game/scripts/engine_audio.gd`, Kind von `RaceSound`):** je Fahrzeug eine Stimme mit zwölf Abspielern (sechs Schichten × Last/Schub), davon höchstens vier hörbar (zwei benachbarte Schichten gleichleistig überblendet); Tonhöhe = gewünschte Drehzahl / Schichtdrehzahl, die Schleifen erhalten Randproben für die Interpolation. Die Drehzahl wird nur für den Klang aus Geschwindigkeit, Gas und einem Gangmodell (`BASE_GEARS` × `gears` des Autos) gebildet: Beim Hochschalten fällt sie zurück, beim Anfahren folgt sie dem Gas (schleifende Kupplung), in der Luft dreht der Motor frei; aufwärts schnell (9/s), abwärts träge (4/s). Last und Schub gewichtet das Gas. Eigenes Auto: Turbo-Pfeifen, Schubumluftventil am Ende des Turbos, Fehlzündungen im Schub (Rallye-, Muskel-, Driftauto). Gegner: eigener Motor, leiser nach Abstand zum eigenen Auto und außerhalb des Bildes, Stereolage aus der Bildposition (Kanal `Eng<n>` mit Panner). Ampel: Leerlauf, in der letzten Sekunde dreht der Motor hoch. Ziel und Absturz: Der Motor fällt auf Leerlauf und klingt aus; Pause und „Geräusche aus“ schalten stumm. Die Simulation wird nur gelesen (Leitplanke 4). Der alte Synthese-Motor und der Synthese-Turbo in `sound.gd` sind entfernt.
- **Gegner mit anderen Autos:** `main.rival_lineup` ordnet je Strecke die anderen Autos fest an; Gegner tragen Karosserie, Farbe und Motorklang dieser Autos. Ihre Physik bleibt das Grundmodell, die Schwierigkeit ändert sich nicht.
- **Probehören in der Autowahl:** Die Pfeile im Garage-Menü spielen einen Probelauf des gewählten Motors (Leerlauf, Gas, Schalten, Turbo, Gas weg; `EngineAudio.preview`, 4,6 s).
- **Aufnahme zur Kontrolle:** `tests/engine_render.gd` fährt Vorführrennen (mit `PREVIEW=1` die Probeläufe der Autowahl) und nimmt den Master-Kanal als WAV auf (`%APPDATA%\Godot\app_userdata\Draw2Race\engine_render\`; Umgebungsvariablen CARS, TRACK, STAGE, SECS). Gemessen: Spitzen unter −4 dBFS, Spektrogramm mit der erwarteten Zündfrequenz (Vierzylinder bei 5700 U/min ≈ 190 Hz, V8 bei 3750 U/min ≈ 250 Hz) und glatten Übergängen beim Gasgeben, Schalten und Gaswegnehmen. `tests/race_view.gd` zeigt das Startfeld mit den verschiedenen Gegnerautos (STAGE, CAR).
- **Offen:** menschliche Hörabnahme je Auto (Probehören in der Autowahl), Feinabstimmung von Pegeln und Gangmodell nach Gehör, eigene Reifen-/Schottergeräusche der Gegner.

## Himmelslicht und Rennausstattung (30.09.2026)

- **Himmelslicht statt flacher Umgebungsfarbe (Premium):** `Atmosphere.apply_sky_light` setzt ein hemisphärisches Umgebungslicht aus einem `ProceduralSkyMaterial` (der Himmel wird nicht gezeichnet, der Hintergrund bleibt eine Farbe; er liefert nur Umgebungs- und Spiegellicht). Oben die Himmelsfarbe, an Wänden der Horizont, unten die Bodenrückstrahlung (`SKY_LIGHT` je Tageszeit, `OVERCAST_LIGHT` für Regen und Schnee). Folge: Schatten liegen kühler als besonnte Flächen, Wände dunkler als Dächer, Baumkronen oben heller, der Asphalt bleibt im Schatten lesbar. Die Sonne zeichnet keine Scheibe im Himmel (`SKY_MODE_LIGHT_ONLY`), sonst würde sie das Licht doppelt liefern. Die Niedrig-Stufe behält die flache Farbe. Dazu: Sonnenstärke am Tag 0,8 → 0,95, Asphalt-Tönung des Dioramas 0,42 → 0,62, Wirkung der gebackenen Verdeckung auf direktes Licht 0,85 → 0,7. Dämmerung und Nacht sind dem früheren Aussehen nachgebildet (Vergleich in `tests/dio_shot.gd` mit `OLDAMB=1`, Versuche mit `SKYAMB`, `AMBIENT`, `SUNE`, `ROAD`, `AOAFFECT`, `TONEMAP`). Tonemapper ACES, Filmic und AgX wurden geprüft und verworfen (ACES erschlug den Asphalt im Schatten, die anderen entsättigten); es bleibt LINEAR. Alle neun Strecken wurden am Tag gegen den alten Stand verglichen: heller und farbiger, nichts überstrahlt.
- **Rennausstattung (Stadt):** `tools/diorama.py`, Abschnitt „Rennausstattung“.
  - **Startportal** über der Startlinie: zwei Pylone auf den Gehwegen (Sockel, weiß, rotes Band), Querbalken 6,5 m hoch mit Schriftzug „START / ZIEL“ auf beiden Längsseiten (nicht gespiegelt) und einem Schachbrettstreifen oben. Eine Schutzfläche verhindert an der Startlinie eine Zufahrt gegenüber.
  - **Zuschauerzonen** beidseits der Startgeraden (±26 m, nur auf geraden Stücken, nicht über Zufahrten): Absperrgitter aus Stahl am Randstein, Werbebanner an beiden Gitterseiten (acht Entwürfe, Schrift in beiden Sichtrichtungen lesbar), dahinter ein Streifen Menschen in Draufsicht, dahinter Fahnen auf Masten zwischen den Laternen.
  - **Texturen** (`tools/make_event_textures.py`, eigene Grafik, Schrift Outfit unter OFL): `game/assets/event/menge.png` (Zuschauer, 6 m × 1,25 m, kachelt), `banner.png` (Bannerbild 2 × 4), `portal.png`, `schach.png`. Das Diorama trägt nur Platzhalter `E_*`; `world.gd` (`event_material`) weist Textur bzw. Shader zu. Der Import bekommt Mipmaps und Kompression (`tools/build.ps1`, wie beim Bausatz).
  - **Bewegung:** `assets/crowd.gdshader` lässt die Menge leicht wiegen, `assets/flag.gdshader` lässt die Fahnen wehen (Welle senkrecht zur Fläche, zum freien Ende stärker). Die Banner leuchten nachts schwach mit ihrem Bild.
  - Menge, Fahnen und Banner bekommen weder Laternen-Zusatzlicht noch Schneedecke; der Zuschauerstreifen ist beim Backen der Verdeckung unsichtbar (dünne Auflage wie die Markierungen).
  - Die Werbetafel und der Turm der Stadt stehen nun bei x = −14 und x = 14 (`tools/make_tracks.py`), damit die Startlinie frei bleibt.
- **Laternen:** Lichthöfe der Glühkörper kleiner und schwächer (1,25 m, Deckkraft 0,6).
- **Offen:** Zuschauerzonen an weiteren Geraden und Kurvenaußenseiten, Reifenstapel, Parkende Autos, Verkehrsschilder.

## Stadtleben und Bäume als MultiMesh (30.09.2026, Beta 0.2.21)

- **Parkende Autos:** `tools/kit_car.py` baut einfache Stadtautos (Limousine, Fließheck, Transporter, Geländewagen; rund 100 Dreiecke, nur Vertexfarbe, Glas und Reifen dunkel). `tools/diorama.py` stellt sie entlang der Zufahrten an den Randstein (beide Seiten, zufällige Lücken, Richtung beliebig); ein Objekt `Auto_k_farbe`, die Verdeckung wirft Kontaktschatten, Laternenlicht wie bei den nahen Häusern. Stadt: 30 Autos, `recipe["cars"]` hält die Standorte.
- **Markisen und Nasenschilder:** Läden (Erdgeschosse mit `front = laden`) bekommen eine gestreifte Markise über dem Schaufenster (sechs Farben, Creme) und ein Nasenschild, das nachts leuchtet (`tools/kit_house.py`, `add_awning`; eigener Zufallserzeuger, die übrigen Hausmerkmale bleiben unverändert).
- **Ampeln:** An den Kreuzungsecken abseits der Fahrbahn stehen Ampelmasten (`traffic_light`, `on_asphalt`); die beiden Achsen zeigen Rot und Grün, die aktive Lampe leuchtet nachts und strahlt über der Glühschwelle auf (`kit_material`, Schlüssel `ampel_*`).
- **Parkbänke** auf dem gepflasterten Parkweg der Innenseite (Holz, Stahlfüße), Blick zur Fahrbahn.
- **Bäume als MultiMesh:** `World.merge_props` fasst die Straßen- und Parkbäume des Dioramas nach Netz und Spiegelebene zusammen (vier Netze, acht MultiMeshes); Zusatzlicht und Schneedecke hängen am gemeinsamen Knoten. Zeichenaufrufe: Übersicht trocken 440 → 399, Regen mit Spiegelung 773 → 694; Rennansicht 226 → 218 bzw. 375 → 350.
- **Hilfsskript:** `tools/godot_run.ps1` startet Testskripte mit Zeitgrenze (ein Skriptfehler in einer Coroutine lässt Godot sonst offen).

## Stoßgeräusche, Randsteinrumpeln und kleinere Pfützen (01.10.2026, Beta 0.2.22)

- **Stoßgeräusche (bisher gab es keine):** `tools/make_impact_sounds.py` (numpy, eigene Synthese, kein Fremdmaterial) erzeugt `game/assets/sfx/impacts/`: Berührung zweier Autos (3 Varianten: dumpfer Schlag, Knirschen, kurzes Nachrasseln), Aufprall an der Leitplanke (3, mit Blechklang und Schleifschweif), Landung nach dem Sprung (2), Absturz (2, mehrere Stöße und Splitter aus Geräuschkörnern statt Tönen), Turbo-Einsatz (aufsteigendes Luftrauschen mit Schlag) und die Rumpelschleife für den Randstein. Erste Fassungen klangen nach Glocken („Ding“, „Music“ beim AudioSet-Klassifikator); die Teiltöne wurden stark gedämpft und durch Knirschkörner ersetzt (Berührung jetzt „Bang/Sound effect“, Leitplanke „Clang“, Landung „Bang“).
- **Einbau:** `RaceSound.impact(kind, strength, pan, extra_db)` (sechs Abspieler über den Kanal „Impact“ mit Stereoregler, leichte Tonhöhenstreuung); Auslöser in `main.gd`: `contact_sparks` (Autos), `race_sounds()` (Landung, Absturz, Leitplanke, Turbo-Einsatz; zustandsabgeleitet, die Simulation wird nur gelesen), Gegner leiser nach Abstand zum eigenen Auto und mit Stereolage aus der Bildposition. Der bisher ungenutzte Leitplankenaufprall (`guard_hit`) löst nun auch Funken aus. Der Randstein rumpelt (`rumble`, Tonhöhe und Stärke nach Tempo, nur am Boden). Importe der Geräusche stellt `build.ps1` auf PCM.
- **Test:** `tests/impact_events.gd` fährt Vorführrennen (headless) und zählt die Auslösungen in `RaceSound.impact_log` (Stadt: Berührungen und Turbo, Serra: Leitplanke, Steinbruch: Landungen, Rummel: Landungen und Absturz).
- **Pfützen kleiner (Regen):** `road.gdshader` mischt drei Rauschlagen (9 m, 3 m, 1 m), die Schwelle liegt bei 0,62 (vorher 0,56, großflächige Lachen), um jede Lache bleibt der Asphalt feucht; auf der Hauptfahrbahn liegen die Lachen bevorzugt in den Fahrspuren (Vertexfarbe der Hauptfahrbahn als Kennzeichen, Mulden bei ±1,05 m und ±2,55 m).

## Motorprofile nachgestellt, Gehwegplatten und Rasen (01.10.2026, Beta 0.2.23)

- **Motoren nach der Klassifikator-Kontrolle angepasst:** Sprint 7200 statt 7800 U/min (Impulslänge 0,19), Drift King 7600 statt 8000 (0,20), Apex GT als V12 bei 8600 statt V10 bei 9200 (Rohr und Dämpfer nachgestellt). Bewertung der Probefahrten danach: Sprint 0,88 (vorher 0,76), Drift 0,83 (0,49), GT 0,82 (0,45); die übrigen blieben gleich. Ob es auch nach Gehör besser klingt, prüft der Nutzer.
- **Gehwegplatten:** Die Gehwege der Stadt nutzen `Tiles107` (ambientCG, CC0) mit Normalkarte, Kachel 5 m = 8 Platten (0,62 m), gedämpft getönt. Von oben entsteht ein feines Plattenraster statt einer glatten Betonfläche.
- **Rasen und Pflaster nicht mehr gleichförmig:** Die Bodenkacheln tragen eine Vertexfarbe: Mähstreifen (2,6 m, abwechselnd ±4,5 %) und weiche Flecken (Wertrauschen mit 7 m und 2,3 m) auf dem Rasen, leichte Schwankung auf dem Pflaster (`ground_tint` in `tools/diorama.py`).

## Tribünen und weitere Zuschauerzonen (01.10.2026)

- **Offene Tribünen** (`bleachers` in `tools/diorama.py`): Links und rechts der Startlinie stehen auf dem Rasen der Innenseite zwei Tribünen mit drei Stufen (je 1,15 m tief, 0,55 m hoch), roten und blauen Blöcken im Wechsel, weißen Treppengeländern zwischen den Blöcken und der Menge (`E_menge`) auf jeder Stufe, Blick zur Fahrbahn; sie erinnern an die roten Tribünen der Referenz. Sie stehen nur auf geraden Stücken und nicht auf Zufahrtsflächen; der Bauplatz wird für Bäume gesperrt.
- **Weitere Zuschauerzonen:** Lange Geraden abseits der Startgeraden (ab 22 m, mittig, höchstens 22 m) bekommen beidseits Gitter, Banner, Menge und Fahnen wie die Startzone.
- **Siegkonfetti:** Bei einem Sieg (auch im Drift-Modus) fällt ein bunter Schauer über dem Ziel (`World.confetti`, zwei Emitter reihum, 170 Stück mit sRGB-Farbverlauf, nur Darstellung). Einen Jubel oder Applaus synthetisch zu erzeugen, scheiterte: Der Klassifikator hörte Rauschen, Regen und Knallkörper statt einer Menge; die Entwürfe wurden verworfen.
- **Test:** `tests/test_diorama.gd` (in `tools/build.ps1` eingereiht, 13 Prüfungen): Diorama der Stadt lädt, Bäume sind zu MultiMeshes zusammengefasst und vollständig, Rennausstattung, parkende Autos und Bänke sind vorhanden, kein Platzhalter-Material bleibt ohne Spielmaterial. `tests/confetti_shot.gd` zeigt das Konfetti in der Rennansicht.

## Zusammenstöße mit Deko (01.10.2026, Beta 0.2.25)

Nutzerentscheidung: Die Linie darf durch Hindernisse führen; dann kracht es.

- **Hindernisse sind Teil der Spielebene** (`Circuit.obstacles`, `load_obstacles`), in jeder Grafikstufe dieselben: Bei Strecken mit Diorama kommen sie aus der Begleitdatei (`tools/diorama.py` schreibt `obstacles`: Häuser, Absperrschranken, Gitter, Tribünen, Portal-Pylone, Ampeln, Bäume, parkende Autos, Bänke, Brunnen, Tiefgaragenschranke und -haube; Stadt: 228 Stück, dazu Laternen und Laufzeit-Bausteine wie Tafel und Turm), sonst aus den Bausteinen der Streckendatei (Maße aus `w`/`d`, sonst `PROP_CIRCLES` bzw. `AI_RADIUS`; flache Dinge wie Blumen, Wege, Teiche entfallen). Ein Raster (8 m) hält die Suche billig.
- **Physik** (`RaceVehicle.collide_obstacles`): Das Auto ist zwei Kreise (vorn/hinten, 0,95 m). Der Stoß wirkt an der Berührstelle: Rückprall entlang der Normalen (Mauer 0,3, weiche Absperrung/Gitter/Bank/Reifenwand 0,12 und zusätzlich gedämpft), Reibung quer dazu und ein Drehimpuls – schräge Treffer drehen das Auto. In der Luft fliegt es über niedrige Hindernisse. Frontal über 17 m/s gegen Mauer oder Auto: Totalschaden; hängt das Auto 3 s an einem Hindernis fest ohne voranzukommen (die Linie führt hindurch): Wrack. Beides zählt wie ein Absturz (Rennen verloren), das Auto bleibt aber stehen (`wrecked`). Physikversion `bicycle-4` (ältere Geisterfahrten werden nicht mehr abgespielt).
- **Rückmeldung:** Blech klirrt an Absperrung, Gitter und Mast, sonst dumpfer Schlag; Funken bei Metall oder harten Stößen.
- **Einfache Grafikstufe:** Bei Strecken mit Diorama zeigt sie die Hindernisse als Klötzchen (`World.build_obstacle_blocks`), damit Bild und Zusammenstöße übereinstimmen.
- **KI:** fährt die Stadt ohne einen Stoß ins Ziel; alle bisherigen KI-Tests bestehen. Zwei künstliche Sprungtests auf Azure (Schanze direkt vor der Kurve) räumen die Deko vorher weg, weil sie nur die Flugphase prüfen.
- **Tests:** `tests/test_collision.gd` (11 Prüfungen, in `tools/build.ps1`), `tests/crash_shot.gd` (Bilder einer zu schnellen Linie).
- **Grenzen:** Getroffene Absperrungen bleiben stehen (sie sind ins Diorama gebacken). Die Maße der KI-Modelle ohne `w`/`d` sind geschätzt.

## Hotfix Update-Download (01.10.2026, Beta 0.2.26)

- **Fehler:** Der Download des Updates brach nach 30 s ab. `HTTPRequest.timeout` begrenzt in Godot die gesamte Anfrage, nicht die Zeit ohne Daten; ein APK mit rund 180 MB braucht im Mobilfunk/WLAN länger.
- **Korrektur (`scripts/updater.gd`):** Die Versionsabfrage behält 30 s Grenze. Beim Download ist die Grenze aus; ein Wächter bricht erst ab, wenn 30 s lang kein Byte mehr ankommt (`get_downloaded_bytes()` unverändert).
- **Hinweis:** Installierte Versionen bis 0.2.25 haben noch den alten Updater; 0.2.26 muss einmal von Hand (Browser oder adb) installiert werden.

## Motoren aus engine-sim (01./02.10.2026, Beta 0.2.27)

Der Nutzer fand die synthetischen Motoren „total verrauscht“ (Ursache: die Synthese war auf einen Geräusch-Klassifikator abgestimmt, der breitbandiges Rauschen belohnt). Seitdem kommen die Motorschichten aus **engine-sim** (github.com/ange-yaghi/engine-sim, MIT): einer physikalischen Simulation von Zylindern, Zündfolge, Krümmern und Auspuff. Hörprobe des Big-Blocks vom Nutzer als „sehr authentisch“ abgenommen; Probe aller Autos: „hier und da noch ein Knacken, ein winziger Dudel-Rest, verkraftbar“.

- **Werkstatt:** `E:\Draw2Race-AudioLab\engine-sim` (Quellcode, eigener Prüfstand `headless/es_render.cpp` ohne Fenster, Podman-Abbild `d2r-enginesim` mit Debian/Clang). Der Prüfstand lädt eine Motorbeschreibung, fährt ein Steuerprogramm in Simulationszeit (Zündung, Anlasser, Gas, Prüfstandsdrehzahl, Gang, Kupplung) und schreibt das Rohsignal vor der Pegelregelung als Gleitkomma-WAV. Der Linux-Bau brauchte kleine Anpassungen am Quellcode (Boost → std::filesystem, `inline constexpr`, MSVC-Eigenheiten über `-fms-extensions -fdelayed-template-parsing`).
- **Aufnahme:** `tools/record_engines.py` (je Auto ein Lauf, vier parallel, ~4 min für alle). Ablauf: Anlassen → Leerlauf → Vollgas im Leerlauf bis in den Begrenzer (Begrenzer-Schleife) → Prüfstand hält jede Stufe unter Vollgas (ein durchgehender Lastlauf) → danach alle Stufen im Schub (durchgehender Schublauf). Stufenabstand 5,5 % (34–48 Stufen je Auto), Schleifen aus ganzen Arbeitsspielen, 24 kHz.
- **Gleichtakt:** Alle Schleifen eines Motors sind auf dieselbe Zündlage gedreht (Kreuzkorrelation des mittleren Arbeitsspiels; Nachbarstufen danach 0,97–0,98, Boxer 0,67, V12 0,74). Im Spiel setzt jede neue Stufe an der Stelle des Arbeitsspiels ein, an der die laufende gerade ist (`EngineAudio.slot_phase`: `get_playback_position()` ist das Ende des zuletzt gemischten Blocks; dort beginnt die neue Stimme). Ohne Gleichtakt verdoppelten sich beim Überblenden die Zündungen (Knacken) und Obertöne löschten sich aus („dudelludel“).
- **Motoren:** Grip = Dreizylinder 1.0 (aus dem Honda B18C abgeleitet), Sprint = Audi-Fünfzylinder, Col Racer = Honda VTEC, Dirt Hawk = Subaru-Boxer mit ungleichen Krümmern, Drift King = 2JZ, Thunder V8 = Chevy 454 Big-Block, Quarry Truck = V6 mit ungleichem Zündabstand (Diesel kann engine-sim nicht), Apex GT = V12 (Ferrari 412 T2 auf Straßendrehzahl begrenzt). Eigene/angepasste Motordateien in `tools/engine_sim/` (Herkunft dort). Begrenzer-Zündunterbrechung auf 70 ms (V6 90 ms) verkürzt.
- **Spiel (`engine_audio.gd`):** je Stimme nur drei Abspielerpaare (Last/Schub), die ihre Stufe wechseln, wenn die Drehzahl wandert; Dynamik der Aufnahmen auf 40 % verdichtet und eingebaut (`dynamics: baked`, kein künstlicher Drehzahlzuschlag mehr); Gas und Schub sauber getrennt; Begrenzer-Schleife bei Vollgas kurz vor dem Hochschalten und in der Luft; im letzten Gang begrenzt der Fahrtwind. Gegner nur noch 2 dB leiser als das eigene Auto (Nutzerwunsch), Entfernungsabschlag 0,4 dB/m bis 16 dB.
- **Fehlzündungen** neu synthetisiert (`make_engine_sounds.py --effects`: Druckstoß, Rohrnachklang, Zischen, Nachdruck, zwei Knattervarianten); Turbo und Schubumluftventil unverändert.
- **Prüfmittel:** `tests/engine_sweep.gd` (Drehzahlrampe über den Spiel-Mischer, `RAMP=` Dauer), `tests/engine_sweep_all.gd` (Gegenversuch, alle Stufen durchgehend), `tests/engine_sync.gd` (Gleichtakt zweier Stimmen messen). Mitschnitt jeweils auf einem eigenen Kanal bei stummem Hauptausgang (echter Treiber; der Dummy-Treiber mischt in unregelmäßigen Blöcken bis 72 ms und taugt nicht für Gleichtaktmessungen). `tools/godot_run.ps1 -Extra` reicht weitere Godot-Argumente durch.
- **Speicher:** Motordateien 23 MB (vorher 6,4 MB).

## Dioramen für alle Strecken (01./02.10.2026, Beta 0.2.27)

Auf Nutzerauftrag („Bring bitte die restlichen Karten auf den neuen Stand, angefangen bei der Küste“) wurden die Strecken in einem Arbeitsablauf mit mehreren Agenten auf Dioramen umgestellt. Einzelheiten je Strecke stehen in `docs/dioramen/<id>.md`, die Pipeline in `docs/dioramen/README.md`.

- **Pipeline:** `tools/diorama.py` ist der Kern (Stadt, Helfer, Backen, Export); Themenspezifisches liegt in `tools/dio_themes/<thema>.py` (Hooks `theme_materials/ground/scenery/bake_hidden/layout`, `THEME_CFG`). Straßenart `runtime`: Das Diorama liefert nur Boden und Kulisse, das Spiel baut Fahrbahn, Randsteine, Rampen, Lücken, Loopings und Abkürzungen wie ohne Diorama (Begleitdatei `runtime_road`). Bodentexturen, Farbtöne und Wasserfarben kommen aus der Begleitdatei (`ground_set`, `tints`, `water`). `ao_proxies()` lässt Laufzeit-Bauteile Kontaktschatten werfen. `tools/dio_build.ps1 -Track <id> -Shots` baut, importiert und macht Kontrollbilder; Godot- und Blender-Läufe sind über Systemsperren nacheinander geschaltet.
- **Azure Coast → Stadion** (Nutzerwunsch): Oval unverändert; Sicherheitsmauer mit Fangzaun, Tribünen rund um das Oval (Haupttribüne mit Segeldach, Seeseite niedrig), Innenfeld mit Boxengebäude, Rennwagen, Team-Transportern, Videowand; Promenade, Strand und Meer. Lagune, Steg, Bootshaus und Clubhaus entfallen (`make_tracks.py azure()`).
- **Hafen, Drift-Arena, Wald, Steinbruch, Jahrmarkt, Kinderzimmer, Serra-Pass:** jeweils eigene Bodenmischung, Kulisse und Kontaktschatten (Laufzeit-Straße). Der Serra-Pass hat ein selbst gebackenes glattes Gelände, das die Fahrbahnhöhen exakt trifft.
- **KI bei Nässe (`track.gd wet_wall_margins`):** Steht ein festes Hindernis bis 6 m neben dem Fahrbahnrand, plant die KI im Regen mit bis zu 14 % weniger Querbeschleunigung (Wand statt Auslaufzone). Anlass: Ein Gegner rutschte im Nachtregen gegen die Stadionmauer und wurde zum Wrack. Trocken unverändert.
- **Tests:** `test_diorama.gd` prüft jetzt jedes Diorama (Laden, Platzhalter, Fahrschlauch frei inklusive Rampen-/Lücken-/Loopingzonen und Abkürzungen, KI im Ziel ohne Stoß). `test_core`/`test_collision` an das Stadion angepasst. Stand: alle 257 Prüfungen bestehen.
- **Zweiter Tag (02.10.2026):** Kern: Vertexfarben-Export, Punktlichter (`add_light`), Polygon-Lichtblocker, Laternenmodell je Strecke, Bodenhöhen für Laufzeit-Modelle (`set_prop_y`), unsichtbare Hilfshindernisse, Abkürzungen nicht mehr schwarz (Dreiecke lagen falsch herum), `build.ps1` lässt alle Testreihen laufen. Nachtlicht: Laternen- und Flutlicht übersteigt nie die Tageshelligkeit (`lamp_day`), Grundhelligkeit aus Mond/Himmel (`lamp_floor`), Rampen, Looping, Leitplanken/Schlammbänder, Wasser, Fahnen und Zuschauer werden beleuchtet; Zuschauer sind feste Körper (vorher je nach Blickwinkel durchscheinend). Strecken nachgebessert (Stadion-Nacht, Wald 296k → 180k Dreiecke mit Fahrbahnsaum, Steinbruch-Flutlicht und Graben, Hafen-Details, Jahrmarkt-Lichter, Kinderzimmer-Nachttischlampe und Sandkasten-Schmutzzone).
- **Prüfurteile (unabhängige Prüfagenten):** gut: Stadt, Hafen, Arena, Wald, Steinbruch, Jahrmarkt, Kinderzimmer, Serra-Pass, Stadion (Nacht nach der letzten Runde: Lichtinseln, naturgrüner Rasen, feste Zuschauer). Tests: 386 Prüfungen (test_diorama 245).
- **Offen:** Sichtabnahme durch den Nutzer; Geräteprüfung auf Android (Dreiecke, doppelte Zuschauer-Durchgänge, Lichtkarte); Wald ~180k Dreiecke (über dem Richtwert); einfache Grafikstufe nicht bei allen Strecken angesehen; Wasser trägt keine Schneedecke mehr.

## Höhenniveaus, Sprünge, Wippe, Nutzungsspuren (02./03.10.2026, Beta 0.2.28)

Nutzerwunsch: verschiedene Höhenniveaus ab dem Wald. Entwurf, Bauplan und Stand: `docs/dioramen/HOEHEN_PLAN.md` (Abschnitt 13 „Stand nach der Prüfung“).
- **Steinbruch „Bruchkante Ost“:** Auffahrt auf eine obere Sohle (5,6 m), zwei Kurven oben, Kicker und Sprung über die eigene untere Strecke auf eine abschüssige Landerampe; Strecke rund 500 m. Unter 10,3 m/s Absturz in die Lücke, 10,7–11,1 m/s Aufprall an der Lippe, ab 11,5 m/s Landung.
- **Hafen:** Stahlrampe auf eine Containerterrasse (5,2 m), zwei Kurven oben, Sprung über eine Gasse auf eine Landerampe; Übertempo bricht die Leitplanke.
- **Wald „Hügelacht“:** Höhenprofil mit Kuppen und Senken, Holzbrücke (4,5 m) über den Hohlweg statt der ebenen Kreuzung.
- **Kinderzimmer:** Abkürzung über ein Lineal als Wippe auf einem Stift (`game/scripts/seesaw.gd`, deterministisch simuliert, eigene Wippe für das Geisterauto); angehobene Einfahrtskante = Aufprall/Wrack für Nachfolger im Zeitfenster 2,0–3,2 s; KI entscheidet an s 0,515 nach Zustand und Abstand, sonst Umweg.
- **Unterbau:** `RaceField` (Feld, Takt, Wippen), Landung auf Gefälle, Lückenlippe, Hindernisse mit Unterkante, Astbezug an Kreuzungen, Streckenrevision/-prüfsumme (Bestzeiten der geänderten Strecken getrennt, Gold bleibt), KI-Sprungfenster, Ausweichen nur auf Geraden, Wandreibung skaliert mit dem Stoß (Schrammen statt Festkleben). Physikversion `bicycle-5` (alte Geister werden nicht abgespielt).
- **Nutzungsspuren:** Spurenkarten aus echten KI-Fahrten (`game/assets/wear/`), nur der Fahrbahn-Shader liest sie (Reifenabrieb, Spurrinnen auf Schotter).
- **Tests:** neu `test_heights`, `test_field` (alle Strecken × 3 Stufen mit Wetter und mehreren Spielerlinien), `test_wear`; zusammen 653 Prüfungen. Unabhängige Prüfung: Steinbruch, Wippe, Gegnerfeld, Zeichnen, Determinismus gut; Hafen, Wald, Regression brauchbar.
- **Offen:** Sichtabnahme und Geräteprüfung; Stadt verliert in Regen-Stufe 3 bei sehr schneller Außenlinie selten einen Gegner (3 von 30 Proben); weitere Ideen (Steilkurven, Viadukt, Parkdeck) zurückgestellt (Plan Abschnitt „verschoben“).

## Drift, Randpfosten, Musik beim Streckenwechsel (03.10.2026, Beta 0.2.29)

- **Drift-Auto fuhr rückwärts:** Die Karosserie `game/assets/cars/drift.glb` saß verkehrt herum. Die automatische Vorn/Hinten-Erkennung in `tools/ai_car.py` sucht rote Rückleuchten, und die des Drift-Modells sind dunkel. `tools/ai_cars.json` erzwingt deshalb jetzt `"flip": true`, `tools/build_cars.ps1` reicht das weiter. Das Modell ist neu gebaut, die gelenkten Vorderräder sitzen jetzt an der Schnauze. Physikalisch fuhr das Auto nie rückwärts.
- **Drift-Modus:** Der Fahrer-Regler in `RaceVehicle.step()` deckelte nach einem Ausbrechen auf 7 m/s (Fehlwinkel > 0,85 rad oder > 3 m neben der Linie). Ein driftendes Auto bremste also und kroch zur Linie zurück.
  - Im Drift-Modus greift der Deckel nur noch, wenn das Auto wirklich verloren ist: Das Ziel liegt mehr als 2,0 rad daneben oder dahinter, oder das Auto steht mehr als 1 m jenseits des Fahrbahnrands.
  - Gas und Bremse richten sich nach der tatsächlichen Geschwindigkeit |v| statt nach der Längsgeschwindigkeit u.
  - Ein verlorenes Auto dreht mit vollem Einschlag bei 3 m/s um.
  - Der Rennmodus ist bitgleich (Vergleich mit dem alten Stand auf allen Rennstrecken). Ziele [600, 1100, 1600] unverändert. Beispiel: Drift King mit 45 % zu schnell geplanten Kurven erreicht 2136 Punkte in 47,6 s (vorher 1798 Punkte in 59,1 s).
- **Randpfosten:** Die Holzpfosten und Feldsteine an der Schotterpiste (Steinbruch, Wald) waren reine Grafik.
  - Sie stehen jetzt als Hindernisse in `Circuit.edge_posts` (`track.gd`), und `World.build_edge_posts()` zeichnet genau diese Liste.
  - Die Innenkante liegt 1 m hinter dem Fahrbahnrand. An Abkürzungen, Sprüngen, Lücken, Loopings und in Diorama-Bauteilen fallen sie weg.
  - Holzpfosten brechen ab 2 m/s Stoß oder nach gesammelter Last. Der Zustand gilt je Rennen für alle Autos (`post_state` über `RaceField`), umgefallene Pfosten kippen sichtbar.
  - Feldsteine bleiben fest. Ein Mittelkreis erfasst schlanke Hindernisse (r ≤ 0,3 m) und die Feldsteine, die sonst zwischen die beiden Wagenkreise passten.
  - Serra: Leitpfosten, Torpfosten und Schildmast sind jetzt fest (`tools/dio_themes/mountain.py`, `serra_layout.json` neu).
  - Physikversion `bicycle-6`: Die nassen Stufen von Steinbruch, Wald und Serra ändern sich leicht. Alle 27 Herausforderungen kommen ins Ziel, `golden_times.json` ist neu erzeugt.
- **Musik:** Wurde direkt nach dem Ergebnis die Strecke gewechselt, liefen Sieg-/Niederlage-Stück und Menümusik bis zum Ende des Ladens gemeinsam. `Sound.finish_crossfade()` schließt die Überblendung jetzt am Anfang von `select_track()` ab.
- **Tests:** 673 Prüfungen, neu sind `test_drift_throttle` in `test_air.gd` und 14 Pfostenprüfungen in `test_collision.gd`. Kontrollbild-Werkzeug: `game/tests/post_shot.gd`.
- **Offen:** Geräteprüfung des Driftgefühls. Beim Aufprall auf Holz sprühen bisher Funken statt Splittern. Das Grundauto braucht für Drift-Stufe 1 jetzt etwa 30 % zu schnell geplante Kurven.
- **Mehrspieler:** Die Recherche zu bis zu 4 Handys ohne Internet steht in `docs/MULTIPLAYER_RECHERCHE.md`.

## Mehrspieler, erste Stufen M0–M2 (03.10.2026, Beta 0.2.30)

Plan und Nutzerentscheidungen: `docs/MULTIPLAYER_RECHERCHE.md`.

- **M2, Umbau für mehrere Menschen:**
  - `RaceField` führt eine Teilnehmerliste (`human_entry`/`ai_entry`/`lineup`/`setup_entries`/`build`). Turbo kommt je Auto (`step_inputs`, `turbo_log`). Ausweichen und Wippenwahl gelten nur für die KI.
  - `main.me` ersetzt die festen `vehicles[0]`. Mehrere Linien sind über `main.race_entries` möglich; mit mehr als einem Menschen gibt es kein Gold, keine Bestenliste und keinen Geist.
  - Der Einzelspieler ist bitgleich: `make_golden` FIELD=1 und ein Vergleich mit 12 Nachkommastellen über 111 Varianten.
- **M1, Namen und Sprechblasen:**
  - Name im Spielstand (12 Zeichen, Umlaute erlaubt). Die KI-Fahrer haben feste Namen.
  - Namensschilder in Wagenfarbe hinter dem Auto, am Bildrand mit Pfeil (`name_tags.gd`). Kurze Ereignisblasen wie „Überholt!“, „Führung!“, „Dreher!“ oder „Ziel – Platz n“ (`race_chatter.gd`).
  - Beides ist in den Optionen abschaltbar und liest die Simulation nur.
- **M0, Netzschicht und Netztest:**
  - `game/scripts/net/`: ENet-Sitzung auf UDP 24680 mit höchstens 3 Mitspielern und versioniertem Protokoll mit Ablehnungsgrund. Ping, Uhrabgleich, Suche per Rundruf, Ankündigung, Gateway-Probe und Adresse von Hand.
  - `NetHelper.java` bindet das Spiel ans WLAN, meldet den Netzstatus und hält die Multicast-Sperre. Neue Berechtigungen: ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE, CHANGE_WIFI_MULTICAST_STATE.
  - Versteckter Bildschirm „Netztest (Mehrspieler)“ im Entwicklermenü (5× aufs Logo tippen). Er schreibt `user://netztest.log`, abzuholen mit `adb shell run-as de.draw2race.game cat files/netztest.log`.
  - PC-Test: `tools/net_test.ps1` (1 Host + 3 Mitspieler, Versionsablehnung, Suche).
- **Tests:** 845 Prüfungen in 12 Testreihen, neu sind `test_multi`, `test_net` und `test_tags`.
- **Gerätetest M0 (03.10.2026, S21 als Gastgeber mit Android 15, S10 als Mitspieler mit Android 12, beide ohne SIM):**
  - **Heim-WLAN:** Die Suche findet den Gastgeber nach 0,23 s über Rundruf, Netz-Rundruf und Ankündigung. Die Verbindung steht in unter 0,1 s.
  - **Heim-WLAN, Messwerte:** RTT im Schnitt 40 ms, meist 20–35 ms, Spitzen bis 220 ms durch den WLAN-Stromsparmodus. Verlust 0 %, keine ENet-Drosselung. Den Uhrversatz von 4,17 s messen beide Seiten übereinstimmend auf etwa 5 ms.
  - **Hotspot des S21:** Er läuft ohne SIM, weil Samsungs WLAN-Freigabe ihn neben dem Heim-WLAN betreibt (Netz 172.17.251.0/24). Die Suche findet den Gastgeber auf allen vier Wegen nach 60–120 ms, auch über die Gateway-Probe.
  - **Hotspot, Messwerte:** RTT im Schnitt 36 ms, Verlust der Echo-Pakete 8–9 %, vermutlich weil ein Funkteil Heim-WLAN und Hotspot gleichzeitig bedient. Das genügt für Schnappschüsse mit Puffer.
  - **WLAN-Bindung:** Sie greift, ändert ohne mobile Daten aber erwartungsgemäß nichts.
- **Offen:**
  - Rest des Gerätetests M0: Hotspot ganz ohne Internet (Gastgeber nicht im Heim-WLAN) und Mitspieler mit aktiven mobilen Daten. Dafür ist ein Handy mit SIM nötig.
  - ENet-Drosselung unzuverlässiger Pakete über 127.0.0.1 (über die LAN-Adresse unauffällig).
  - Schriftgröße der Schilder am Handy prüfen. Allokationen je Bild in `NameTags._draw()` für schwache Geräte verringern.
  - Ergebnisanzeige im Mehrspieler: „Gold“ und „Platz in der Bestenliste“ nur im Einzelspieler zeigen.

## Mehrspieler „Weitergeben“ (M2b), Turbo-Anzeige, Kamera (03.10.2026, Beta 0.2.30)

- **„Weitergeben“:** 2–4 Spieler spielen auf einem Handy (`pass_party.gd`, `party_hud.gd`, `turbo_pads.gd`).
  - **Menü:** „Mehrspieler · 2–4 Spieler“ führt zu „Auf einem Handy“. „Im WLAN“ ist schon zu sehen, aber noch ausgegraut („bald“).
  - **Einstellungen:** Namen, Auto und Spielerfarbe je Spieler (siehe „Freie Autowahl“), Strecke, Herausforderung, KI-Gegner (0 bis 4 minus Menschen) und „Berührungen zwischen Spielern“.
  - **Freigaben:** Im Mehrspieler ist alles frei, der Spielstand bleibt bytegleich.
  - **Zeichnen:** Vor jedem Zug verdeckt eine Übergabekarte die Strecke (350 ms Tippsperre). Nach dem Zeichnen „Neu zeichnen“ oder „Weitergeben →“. Danach werden alle Linien 3 s lang in Spielerfarben enthüllt.
  - **Rennen:** Turboknöpfe je Spieler in den Ecken, mit mehreren Fingern gleichzeitig (am PC Tasten 1–4). Die Kamera hält alle Menschen im Bild.
  - **Wertung:** mit Namen, ohne Gold und Bestenliste. Danach „Revanche“ (der Sieger startet hinten), „Einstellungen ändern“ oder „Zurück zum Menü“.
  - **Drift-Arena:** alle gleichzeitig, ohne Berührung, nach Punkten.
  - **Zurück-Taste:** in jedem Schritt sinnvoll belegt.
- **Turbo-Anzeige (Nutzerwunsch):** Der Knopf selbst ist jetzt die Anzeige (`turbo_gauge.gd`). Er füllt sich von unten, im Einzelspieler orange, im Mehrspieler in der Spielerfarbe. Er zeigt die Prozentzahl, ein kurzes „+“ beim Laden durch Bremsen und pulsiert, solange der Turbo zieht. Vorher war es ein 6 px dünner Streifen.
- **Kamera:** Der Vorhalt zur Streckenmitte ist begrenzt, im Einzelspieler auf 30 % des Ausschnitts, im Mehrspieler auf die Luft über dem Rahmen der Menschen. Auf dem Serra-Pass lag das eigene Auto vorher rund ein Viertel der Zeit außerhalb des Bildes, im Mehrspieler fehlten zeitweise 3 von 4 Autos. Der Einzelspieler bleibt dabei bitgleich, denn nur die Darstellung ändert sich.
- **Kleinigkeiten:**
  - Der „Menü“-Knopf der Mehrspieler-Wertung führt jetzt ins Menü.
  - Namensschilder sind am Handy 3 px größer.
  - Ein fremdes Schild über dem eigenen Auto erscheint als Kontur ohne Kasten.
  - `NameTags._draw()` legt kein Objekt mehr je Bild an.
- **Tests:** 13 Testreihen mit 1041 Prüfungen, neu ist `test_party`. Kontrollbilder: `game/tests/party_shots.gd`.
- **Offen:**
  - Geräteprüfung (Mehrfingerbedienung, Bildschirmtastatur, Schildgrößen).
  - Auf langen Strecken sind die enthüllten Linien schwer zu unterscheiden.
  - `test_party` läuft im quadratischen Testfenster und prüft daher kein Handyformat.

## Mehrspieler im WLAN: Lobby, gemeinsames Zeichnen, Rennen (M3–M5, 03./04.10.2026, Beta 0.2.30)

- **M3 Lobby** (`net/net_lobby.gd`, `lobby_hud.gd`):
  - Menü „Mehrspieler → Im WLAN“ mit „Spiel eröffnen“ und „Beitreten“. Das Beitreten zeigt eine Live-Liste über Rundruf, Ankündigung, Gateway-Probe und Adresse von Hand.
  - Beim Betreten bindet sich das Spiel automatisch ans WLAN, beim Verlassen löst es die Bindung. Ohne WLAN erscheint ein Hinweis auf den Hotspot. Ausnahme: Ein Gastgeber mit eigenem Hotspot bleibt ungebunden, das ist noch nicht am Gerät geprüft.
  - Der Gastgeber stellt Strecke, Stufe, KI-Gegner und Berührungen ein, live für alle. Mitspieler haben „Bereit“, der Gastgeber „Rennen starten“.
  - Abgelehnt wird bei anderer Spielversion, anderem Protokoll (jetzt 3), anderer Physik oder anderen Streckendaten (SHA-256 über alle Strecken), außerdem während eines Rennens und bei voller Lobby.
  - Abgänge, Abbrüche, Hintergrund und Zurück-Taste sind behandelt. Geräteprotokoll: `user://mehrspieler.log`.
- **M4 Zeichnen synchron** (`net/net_draw.gd`):
  - Gemeinsames 3-2-1 nach der gemeinsamen Uhr, am PC auf 1–5 ms genau. Jeder zeichnet verdeckt, ohne Zeitlimit, ein Status zeigt „Anna zeichnet … 60 %“.
  - „Fertig“ schickt die Linie (gepackt etwa 33 B je Punkt, höchstens etwa 66 KB) an den Gastgeber. Er prüft Runde, Streckenprüfsumme, Tore, Tempo und Lage, dann folgt die gemeinsame Enthüllung.
  - Wer nach der Abgabe geht, fährt ohne Turbo mit. Wer vorher geht, wird entfernt.
- **M5 Rennen** (`net/net_race.gd`):
  - Nur der Gastgeber rechnet mit `RaceField`. Turbo-Änderungen aller Menschen, auch des Gastgebers, gelten genau 6 Takte (0,1 s) später.
  - 30 Schnappschüsse/s, unzuverlässig geordnet, etwa 227 B für 4 Autos, rund 7 KB/s je Mitspieler. Ereignisse und Endergebnis gehen zuverlässig.
  - Alle Geräte zeigen dasselbe Bild 0,1 s versetzt, interpoliert, und überbrücken Lücken bis 0,25 s. Danach erscheint „Verbindung zum Gastgeber hakt …“.
  - Ende: wenn alle Menschen im Ziel sind, am Drift-Limit, 30 s nach dem ersten Zieleinlauf oder spätestens nach 180 s. Danach folgen Wertung, „Revanche“ oder „Lobby“.
- **Prüfung:**
  - In 19 Mehrprozess-Läufen am PC stimmen Wertung und Simulation auf allen Geräten bitgleich überein, nachgerechnet mit `RaceField`. Dazu kamen 13 Fehlerfälle und 10 % Paketverlust ohne Teleports.
  - Einzelspieler und „Weitergeben“ sind bitgleich.
  - 16 Testreihen mit 1254 Prüfungen, neu sind `test_lobby`, `test_draw` und `test_race`.

## Freie Autowahl, Spielerfarben, Netz-Korrekturen (04.10.2026, Beta 0.2.30)

- **Freie Autowahl (Nutzerwunsch):**
  - Mehrere Spieler dürfen dasselbe Auto fahren, im „Weitergeben“-Modus und in der WLAN-Lobby.
  - Spielerfarben aus `player_colors.gd`: 6 Farben, die sich auch bei Rot-Grün-Sehschwäche unterscheiden lassen (OKLab-Abstand ≥ 0,146). Jede Farbe gibt es einmal je Runde.
  - Die Spielerfarbe gilt für Lack, Schild, Lichtkranz, Linie, Enthüllung, Chips, Turbo-Knopf und Wertung. KI-Gegner bekommen Autos, deren Farbe sich deutlich davon abhebt.
  - Gewählt wird in derselben Garage wie im Einzelspieler (`RaceHUD.car_picker`/`garage`): drehendes 3D-Auto in der Spielerfarbe, Motorprobe, Fahrwerte und Farbfelder, alle Autos frei, nichts wird gespeichert.
  - Protokollversion 6.
- **Netz-Korrekturen aus der Prüfung:**
  - `NetSession._put()` sendet nur an verbundene Partner. Damit sind die Fehlerzeilen beim sauberen Abmelden weg.
  - Zeitgrenzen: normal 8–20 s, beim Laden 25–45 s. Zusätzlich trennt das Spiel selbst nach dieser Funkstille, frühestens nach 3 s. Ein langsames Handy fliegt beim Laden also nicht mehr raus.
  - Mitspieler senden im Rennen 10-mal je Sekunde ein Lebenszeichen. Nach 0,5 s Stille lässt der Gastgeber ihren Turbo los, über das Turbo-Protokoll und damit nachrechenbar.
  - Nach einem WLAN-Wechsel bindet sich das Spiel neu und sucht neu (`NetAndroid.bound_to_wifi`), am Gerät noch ungeprüft.
  - `main.solo()` ist auch im WLAN-Mehrspieler falsch.
  - Turbo-Hinweis gekürzt auf „Bremsen lädt den Turbo.“, er überlappt den Knopf nicht mehr.
  - Bildschirmtastatur: Die Oberfläche rückt nach oben, wenn sie ein Eingabefeld verdecken würde (`RaceHUD.update_keyboard_lift`).
- **Tests:** 16 Testreihen mit 1401 Prüfungen. `tools/net_test.ps1 -Lobby` mit 7 Läufen, darunter Hänger von 5–6 s, eine saubere Abmeldung und vier gleiche Autos.
- **Hinweis zu den Kontrollbildern:** `-Resolution 2400x1080` begrenzt Windows still auf 1924x1061. Für echtes 20:9 besser `-Resolution 1600x720` nehmen.
- **Offen (Gerätetest):** WLAN-Rennen auf S10/S21 mit Turbo-Gefühl, Hotspot ganz ohne Internet, Mitspieler mit mobilen Daten, Gastgeber mit eigenem Hotspot, Neu-Binden nach WLAN-Wechsel.

## Linienende und erster WLAN-Gerätetest (04.10.2026, Beta 0.2.31)

- **Fehler im Gerätetest:** „Linie nicht abgegeben – Die Linie läuft rückwärts“ trat auf beiden Handys auf, das Rennen ließ sich nicht starten.
  - Ursache: Ein zügiger letzter Strich (1–4 m je Bild) setzt mehrere Punkte auf einmal. Einige davon landeten bis zu 1/24 Runde hinter der Ziellinie, und nur der letzte wurde auf `s = laps` zurückgesetzt.
  - Am PC war das nicht aufgefallen, weil die KI-Linien dort immer exakt im Ziel enden.
  - Korrektur in `LineRecorder.sample()`: Punkte hinter dem Ziel werden abgeschnitten. Im Einzelspieler entfallen nur Punkte jenseits des Ziels.
  - Neuer Test in `test_draw`: schnell beendete Linien auf allen 8 Rundkursen mit 1,5, 2,5 und 4 m je Bild.
- **Gerätetest WLAN (S21 Gastgeber mit Android 15, S10 Mitspieler mit Android 12, Heim-WLAN):** Lobby, Suche, Autowahl, gemeinsames Zeichnen und Rennen liefen laut Nutzer „hervorragend“.
- **Nebenbefund S10:** Der Heim-Router (WPA3, 2,4 GHz) erneuert den Gruppenschlüssel alle 10 Minuten. Das S10 verpasst das gelegentlich und wird abgemeldet (`DISASSOC_STA_HAS_LEFT`), danach schaltet Android das Debugging über WLAN ab. Für den Mehrspieler ist das ein realistischer Störfall.
- **Tests:** 16 Testreihen, 1402 Prüfungen.
- **Noch offen:** Hotspot ganz ohne Internet, Mitspieler mit mobilen Daten (S24), Gastgeber mit eigenem Hotspot, Neu-Binden nach WLAN-Wechsel.

## Hotspot zweigleisig, Musik synchron, Strecke im Hintergrund laden (04.10.2026, Release 0.3.0)

- **Hotspot und WLAN beim Gastgeber:**
  - Ursache laut S24-Protokoll: Android 16 führt den eigenen Hotspot als eigenes Netz (`swlan0`, Fähigkeit LOCAL_NETWORK). Die Hotspot-Erkennung lieferte nichts, der Gastgeber blieb ans Heim-WLAN gebunden, und seine Antworten an 10.110.43.x gingen ins Heim-WLAN.
  - Neu (`NetAndroid.host_plan`):
    - kein Hotspot: Bindung an WLAN
    - Hotspot und WLAN: keine Bindung, erreichbar über beide Netze
    - nur Hotspot unter Android 16: Bindung an das Hotspot-Netz
    - nur Hotspot unter Android 15 oder älter: keine Bindung
  - Geht der Hotspot oder das WLAN erst nach dem Eröffnen an, löst der Gastgeber die Bindung und eröffnet neu, sobald niemand mehr verbunden ist.
  - Die Lobby zeigt beide Adressen („WLAN 192.168.178.4 · Hotspot 10.110.43.61“).
  - Hinweis an Mitspieler, die das Spiel nur über die Ankündigung sehen: Der Gastgeber soll das WLAN ausschalten und neu eröffnen.
  - Neu ist `NetHelper.bindNetwork(handle)`. Am Gerät noch ungeprüft ist, ob der zweigleisige Fall auf Android 16 ohne Bindung klappt.
- **Musik synchron (WLAN):**
  - Der Gastgeber bestimmt Stück, Stil, Überblendung und Folgestück. Die Mitspieler spielen dasselbe an derselben Position, über die gemeinsame Uhr. Ab 0,15 s Abweichung gleicht eine kurze 0,4-s-Überblendung aus, höchstens alle 2,5 s.
  - Auf der Wertung hören alle dasselbe Stück: „sieg“, wenn ein Mensch vorn liegt, sonst „niederlage“.
  - Lobby-Schalter „Musik auch bei den Mitspielern“: Er gilt nur für die laufende Sitzung, gespeichert wird nichts. Beim Verlassen gilt wieder die eigene Einstellung.
  - Protokoll 7.
  - Im PC-Test lagen 4 Geräte höchstens 4 ms auseinander.
- **Strecke im Hintergrund laden:**
  - Ursache der langen Hänger: Beim Wechsel blockierte der Weltaufbau 0,9–15,7 s am Stück. 90 % davon war die Lichtkarte (`Atmosphere.bake_rain_lights`).
  - `Circuit.load_track` lädt die Simulationsdaten weiter vollständig und sofort.
  - Die Grafik baut `World.build_async` in 8-ms-Scheiben. Diorama und KI-Modelle laden in Hintergrund-Threads, die Lichtkarte entsteht in parallelen Threads und ist bitgleich (`light_bake`).
  - Solange die Strecke nicht fertig ist, sind „Linie zeichnen“, „Vorführfahrt“ und die Einträge im Entwicklermenü gesperrt und zeigen „Strecke lädt …“.
  - Am PC ist das längste Bild jetzt 27–72 ms statt bis zu 15,6 s. Das Verlassen des Mehrspielers dauert 36–66 ms statt bis zu 5,2 s.
  - Beendet der Gastgeber, schließen die Mitspieler die Sitzung sofort.
- **Tests:** 18 Testreihen mit 1505 Prüfungen, neu sind `test_music` und `test_loading`. `net_test.ps1 -Lobby` hat 7 von 7 Läufen bestanden. Unabhängige Prüfung: alle fünf Punkte „gut“.
- **Offen (Gerät):**
  - Zweigleisiger Hotspot auf dem S24.
  - Musiksynchronität mit echten Audiotakten.
  - Ladezeiten auf dem S10, geschätzt 2–5 s ohne Einfrieren.

## App teilen ohne Internet (04.10.2026, Release 0.3.0)

- **„Draw2Race teilen“** (nur Android, unter Optionen → „Updates & Teilen“):
  - `ApkShare.java` kopiert die installierte APK in einem Hintergrund-Thread nach `files/share/Draw2Race-<Version>.apk` und berechnet dabei die SHA-256. Danach öffnet sich das Android-Teilen-Menü (`ACTION_SEND`, `application/vnd.android.package-archive`) über den vorhandenen FileProvider, zum Beispiel für Quick Share oder Bluetooth.
  - Eine kurze Anleitung für den Empfänger erklärt, die Datei anzutippen und die Installation aus unbekannten Quellen zu erlauben.
  - Die Kopie wird beim nächsten Start gelöscht.
- **Update aus der WLAN-Lobby:**
  - Bei einer Ablehnung wegen anderer Version bekommt nur die ältere Seite ein Angebot: „Neue Version (x.y.z) vom Gastgeber holen“. Ist der Mitspieler neuer, gibt er seine Version an den Gastgeber weiter.
  - Übertragen wird über einen kleinen HTTP-Dienst auf TCP 24683, der in allen Netzen lauscht, auch im Hotspot. Senden und Empfangen laufen in Threads, mit Fortschritt in MB und Restzeit.
  - Größe und SHA-256 werden geprüft. Danach installiert `Updater.install_file` mit den bekannten Prüfungen: gleiches Paket, höhere Version, gleiche Signatur. Ein Downgrade gibt es nie.
  - Während eines Rennens sendet der Gastgeber höchstens 2 MB/s. Die Drossel misst ab der letzten Änderung der Grenze; vorher brach eine schon schnell laufende Sendung beim Rennstart ab, das hatte die Prüfung gefunden.
  - Ältere Versionen sehen weiterhin einen lesbaren Ablehnungsgrund, das Format ist kompatibel erweitert. Das Protokoll bleibt bei 7.
- **Tests:** 19 Testreihen, neu ist `test_apk` mit Übertragung, Abbruch, verfälschtem Byte, falscher Größe und Drossel-Umschaltung. `tools/net_test.ps1 -Apk` läuft mehrprozessig.
- **Offen (Gerät):** Teilen-Menü mit Quick Share, Installation beim Empfänger, Übertragung im Heim-WLAN und über den Hotspot. Das Angebot hilft erst ab 0.2.32 auf beiden Seiten.

## Musik bei allen (04.10.2026, Beta 0.3.1, Release 1.0.0)

- Der Lobby-Schalter heißt jetzt „Musik bei allen“ und schaltet die Musik auch beim Gastgeber ab (Nutzerwunsch). Der Gastgeber führt die Playlist stumm weiter, damit beim Wiedereinschalten alle an derselben Stelle sind. Gespeichert wird nichts. Nach der Sitzung gilt wieder die eigene Einstellung jedes Handys (`NetLobby.music_muted`).

## Version 1.0 (04.10.2026)

- **Erstes offizielles Release.** Es fasst die Betas 0.2.28–0.3.1 zusammen; das kurzzeitige Release 0.3.0 ist darin aufgegangen. Neu sind die README mit Bildergalerie (`docs/screenshots/`, 10 Bilder in 1600×720) und der GitHub-Auftritt (Beschreibung, Themen).
- **Nummernschema ab jetzt:** Betas 1.0.1, 1.0.2 …, nächstes Release 1.1.0.
- **Testreihe:** `test_loading` wartet vor dem Programmende 0,5 s auf abgebrochene Ladefäden. Sonst meldete Godot gelegentlich ein übrig gebliebenes Mesh-RID beim Beenden, was `build.ps1` als Fehler wertete.
- **Bekannt, offen:**
  - Im Drift-Modus ragt „noch NN s“ bei 20:9 über das Punktefeld hinaus.
  - `test_net` (Hänger von 1,6 s bei langer Grenze) scheiterte einmal an der Zeitmessung des PCs.
  - Holzpfosten sprühen Funken statt Splitter.
  - In der Stadt bleibt bei Regen in Stufe 3 selten ein Gegner liegen.
  - Musik-Feinabgleich per Mikrofon als Idee.
