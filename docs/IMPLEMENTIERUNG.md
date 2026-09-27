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
- Tests: 3 Prüfungen in `test_core.gd` (Versionsvergleich, gültiges Release, Ablehnung fremder URL/Entwurf/fehlender Prüfsumme).
- Regen nur im Licht (`assets/rain.gdshader`): Tropfen ohne Eigenfarbe, additiv; Helligkeit = Tageslicht + Lichtkarte der Straßenlichter (beim Aufbau berechnet, `Atmosphere.bake_rain_lights`) + Scheinwerferkegel/Rücklichter der Autos (live, `update_rain_cars`). Zum Boden hin heller als Tiefenhinweis in der orthografischen Draufsicht.
- Kontrollbild-Aufrufe immer mit `timeout`/`--quit-after`: Bricht ein Skript beim Laden ab, erreicht das Testskript sein `quit()` nie.
- 0.2.2: Lichtkranz des eigenen Autos über den Randsteinen; Linie halb so breit (langsam 0,48 m, schnell 0,05 m) und schon bei mittlerem Tempo schmal (Breite ~ Tempo^0,4); im Rennen dezentes Eigenleuchten (Emission 0,16), damit sie nachts zu ahnen bleibt.
- 0.2.3 – APK von 345 auf 172 MB: nur noch ARM64 (x86_64 war nur für PC-Emulatoren), Programmbibliothek gepackt (`gradle_build/compress_native_libraries`), Musik aus den verlustfreien Originalen neu mit Vorbis q2 (~96 kbit/s, ~0,64 MB/min; `QUALITY` in `export_music.py` des AudioLab), 110 → 67 MB. Verbleibend: Texturen 51 MB, Szenen 19 MB.
- 0.2.4 – vorberechnetes Laternenlicht mit weichen Schatten und indirekter Beleuchtung (Premium): Beim Streckenaufbau entsteht eine Draufsicht-Lichtkarte aller Straßenlichter (`Atmosphere.bake_rain_lights`, 256², Radius 1,8 × Lichtscheibe, 7–80 ms). Größere Bauten (`occluders`, aus `place_ai`) werfen Schatten; Unschärfe durch Verkleinern/Vergrößern. Die Karte ist ein globaler Shaderwert (`[shader_globals]` in `project.godot`, `assets/lamp_light.gdshaderinc`) und wird von Fahrbahn (diffus + Glanz, bei Nässe stärker), Gelände, Lack der Autos, Regen und über `assets/lit_overlay.gdshader` (material_overlay) von Kulisse, Randsteinen und Markierungen gelesen: zugewandte Flächen direkt beleuchtet, untere Wandbereiche indirekt vom Boden aufgehellt. Die additiven Lichtscheiben entfallen im Premium-Modus. Sonne mit Halbschatten (`light_angular_distance` 1,2, `shadow_blur` 1,5).
- 0.2.5 – Straßenlaternen zur Fahrbahn ausgerichtet: Ausleger-Richtung aus dem Modell ermittelt (`ai_arm`: oberste gegen unterste 8 % der Punkte), gedreht zur nächsten Streckenstelle; Lichtkegel unter dem Leuchtenkopf.
