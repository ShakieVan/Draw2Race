# Draw2Race — Projektkontext

## Stand

Am 24.09.2026 wurden Referenzanalyse, Richtlinien und Umsetzungsplan erstellt und anschließend auf Nutzerauftrag die erste spielbare Version umgesetzt. `game/` enthält das Godot-4.6.1-Projekt, `builds/` die Windows- und Android-Builds. `docs/IMPLEMENTIERUNG.md` dokumentiert tatsächlichen Stand, Tests und offene Geräteabnahme. Die ursprünglichen Pläne bleiben Entwurfsunterlagen.

## Einstieg

- `README.md`: Zusammenfassung und Dokumentverzeichnis.
- `docs/REFERENZANALYSE.md`: Beobachtungen mit Zeitmarken; Annahmen von Belegen getrennt.
- `docs/RICHTLINIEN.md`: vorgeschlagenes Spielgefühl, Touch-, Physik-, Kamera-, Grafik- und Tonregeln.
- `docs/UMSETZUNGSPLAN.md`: vorgeschlagene Architektur, Meilensteine und Abnahme.
- `Videos/`: vom Nutzer bereitgestellte Referenz.
- `docs/reference/`: abgeleitete Analysebilder und Hörstellen, keine Produktionsassets.
- `tools/analyze_reference.py`: reproduzierbare Bildextraktion.
- `tools/analyze_audio.ps1`: reproduzierbare Tonmessung (Spektrogramme, Lautheit, Stille, Stereobreite; nur ffmpeg).
- `docs/KLANG_STECKBRIEFE.md`: KI-gestützte Höranalyse der Referenz, Musik- und Effekt-Steckbriefe, Werkzeuge und Lizenzen.
- `audio/entwurf/`: KI-erzeugte Musikentwürfe (eigene Kompositionen); `yue2/` enthält die bevorzugten YuE2-Stücke (FLAC), noch nicht endgültig ausgewählt.
- `game/scripts/`: getrennte Eingabe-, Strecken-, Fahrzeug-, Renn-, UI-, Audio- und Speicherlogik.
- `game/tracks/*.json` und `tools/make_tracks.py`: Strecken als Daten (Mittellinie, Thema, Belag, Deko). Neue Strecken entstehen als Datei, nicht im Code; eine spätere Companion-App soll dieses Format erzeugen.
- `game/tests/`: Godot-Headless-Prüfungen; `tools/build.ps1 -Target Test` führt sie aus.
- `tools/diorama.py`: baut aus einer Streckendatei in Blender ein Diorama (Bildebene: Straße, Kreuzungen, Häuser, Bäume, gebackene Umgebungsverdeckung, Szenenrezept `<id>_recipe.json`); Häuser kommen aus dem prozeduralen Bausatz `tools/kit_house.py` mit den Texturen aus `tools/make_kit_textures.py` (`game/assets/kit/`), Laternen aus `tools/make_lamp.py`. Stand und Entscheidungen: `docs/IMPLEMENTIERUNG.md` (Abschnitt 30.09.2026) und `docs/BESPRECHUNG_GRAFIK.md`.
- `docs/MULTIPLAYER_RECHERCHE.md`: lokaler Mehrspieler (bis 4 Handys, offline), Begründung, Nutzerentscheidungen (Abschnitt 9); Code in `game/scripts/net/`, `pass_party.gd`, `lobby_hud.gd`. Der Einzelspieler muss bitgleich bleiben (`make_golden.gd` FIELD=1 vorher/nachher).
- `docs/dioramen/README.md`: Dioramen-Pipeline seit 02.10.2026 (Themenmodule `tools/dio_themes/<thema>.py`, Straßenart `runtime` für Strecken mit Stunts, `tools/dio_build.ps1 -Track <id> -Shots`); je Strecke `docs/dioramen/<id>.md`.

## Dauerhafte fachliche Leitplanken

1. Projektname ist **Draw2Race**, Zielplattform Android. Kommunikation und Projektdokumentation vorzugsweise auf Deutsch.
2. Kerneingabe ist eine zeitgestempelte Fahrlinie innerhalb der Strecke. Der Plan enthält eine Route und Tempovorgaben, keine Positionsanimation des Autos.
3. Bremsweg, Haftungsgrenzen, seitliches Rutschen und gegebenenfalls Dreher müssen durch Fahrzeugbewegung entstehen.
4. Darstellung, Kamera und Renderbildrate dürfen das Simulationsergebnis nicht verändern.
5. Nichts aus dem Referenzspiel übernehmen; Referenzmaterial separat halten. Fremde und KI-erzeugte Assets sind ausdrücklich erlaubt (Nutzerentscheidung 26.09.2026): freie Bibliotheken (z. B. Poly Haven, ambientCG) und lokale 3D-KI-Werkzeuge. Herkunft lokal in einem Asset-Verzeichnis festhalten; ob und wie sie veröffentlicht wird, entscheidet der Nutzer.
   - 3D-Werkstatt: eine vorhandene lokale Laufzeit (Bild-zu-3D-Modelle, Blender) mitbenutzen statt neu installieren; Einzelheiten stehen in den lokalen Notizen des Nutzers. Ergebnisse für Draw2Race nur im Draw2Race-Ordner ablegen.
   - Grafikstufen: Die heutige Klötzchen-Grafik bleibt als Stufe für schwache Handys erhalten, bis sich zeigt, dass die Premium-Grafik auch dort läuft. Premium-Ziel: nahezu realistisch (Lack-/Nässe-Spiegelungen, gefederte Autos mit drehenden Rädern, weiche Belagübergänge, Funken). Jeder Deko-Typ im Streckenformat bekommt dafür ein einfaches und ein Premium-Modell.
6. Drei Gold-Herausforderungen eines Karriereevents und die Platzierung eines einzelnen Rennens sind getrennte Begriffe.
7. Offline spielbarer Kern hat in der bisherigen Planung Vorrang. Onlineumfang ist noch offen.
8. Godot 4.6.1/GDScript, 3D-Darstellung, eigene Simulation mit 60 Hz. Ein Enginewechsel ist keine beiläufige Änderung.
   - Seit 27.09.2026 (Nutzerentscheidung) „2,5D“: Die Fahrdynamik bleibt in der Ebene; dazu kommen Höhe und senkrechte Geschwindigkeit. Rampen/Schanzen geben einen Impuls nach oben; in der Luft gibt es keinen Grip, keine Lenkung und kein Bremsen; bei der Landung setzt der Grip verzögert ein. Brückenkreuzungen (oberer Ast überspringt den unteren) und Loopings (autonome Durchfahrt mit dem Schwung, Absturz bei zu wenig Tempo) entstehen aus dieser Bewegung, nicht aus Animation.
   - Gezeichnet wird weiterhin in der Draufsicht. An Brückenkreuzungen gibt es eine unsichtbare Zeichenbrücke; im Looping wird nicht gezeichnet (Linie endet an der Einfahrt, setzt an der Ausfahrt fort).
   - Weitere Streckenarten: offene Sprintstrecken (Start → Ziel, eine Durchfahrt), Abzweige/Abkürzungen (alternative Wegpunkt-Ketten), brechende Leitplanken mit Absturz, Drift-Modus (Punkte für Driftwinkel × Tempo × Dauer, Zeitlimit, Berührung der Begrenzung wird bestraft). Die KI-Gegner müssen alle Elemente beherrschen.
   - Vereinbarte neue Strecken: Hafenviertel, Jahrmarkt, Serra-Pass (Sprint, Steilküste), Steinbruch (Looping), Drift-Arena; Bonus-Gegend „Kinderzimmer“; Zusatzfunktion „Geisterlinie“ (beste eigene Fahrt als Geisterauto).
9. Exaktes Originalverhalten nicht erfinden: Die Referenz wurde anhand von Bildstichproben ausgewertet, der Ton gemessen und KI-gestützt beschrieben (siehe Punkt 13). Online-Ranglisten wurden im Video nicht geöffnet.
10. Vor der Produktion vieler Strecken zuerst Eingabe und Fahrgefühl auf einem echten Android-Gerät prüfen.
11. Verbindliche Linienkodierung: **Langsam = breit und grün; schnell = schmal und rot** (dazwischen gelb/orange; Nutzerentscheidung 30.09.2026, vorher hellgelb → rot). Fließende Übergänge zeigen geplanten Tempoaufbau/Bremsen. Die tatsächliche Beschleunigung bleibt Aufgabe der Fahrzeugphysik.
12. Reifen hinterlassen untergrundabhängige Profil-/Schmutzspuren (Erde, Dreck, Matsch); starkes Bremsen und Rutschen erzeugen dunklen Abrieb. Spuren folgen den tatsächlichen Rädern, bleiben begrenzt und beeinflussen die Simulation nicht.
13. **Klang und Musik:** Verbindliche Grundlage ist `docs/KLANG_STECKBRIEFE.md`. Der Referenzton wurde am 26.09.2026 mit lokalen KI-Modellen beschrieben und gemessen; Claude selbst kann nicht hören.
    - **Menüs:** ruhig, melancholisch, akustisch. Solo-Klavier mit Rubato, Streicher; tonales Zentrum d-Moll/F-Dur.
    - **Rennen:** laut und mechanisch. Motor, Turbo, Reifen und Vorbeifahrten; leise elektronische Musik (unsicher belegt).
    - **Stings:** kurze filmisch-orchestrale Akzente bei Zieleinlauf, Sieg (synth-orchestrale Fanfare) und Niederlage (Cello).
    - **Startampel:** vier kurze Töne und ein langer, eine Oktave höherer Startton.
    - **Motoren (seit 01.10.2026):** Ein eigener Motor je Auto (`RaceVehicle.CARS[].id`), aufgenommen mit der physikalischen Motorsimulation engine-sim (MIT) im Podman-Container der Klangwerkstatt (`tools/record_engines.py` → `game/assets/sfx/engines/`, eigene Motordateien in `tools/engine_sim/`). 34–48 Drehzahlstufen im Abstand von 5,5 %, alle im Gleichtakt der Zündungen; `game/scripts/engine_audio.gd` blendet sie phasenrichtig über (drei Abspielerpaare je Stimme), dazu Begrenzer-Schleife. Big-Block vom Nutzer als „sehr authentisch“ abgenommen; Gegner nur wenig leiser als das eigene Auto. Turbo, Schubumluftventil und Fehlzündungen bleiben selbst synthetisiert (`tools/make_engine_sounds.py --effects`). Dazu eigene Stoßgeräusche (`tools/make_impact_sounds.py` → `game/assets/sfx/impacts/`: Berührung, Leitplanke, Landung, Absturz, Turbo-Einsatz, Randsteinrumpeln), ausgelöst aus Zustandswechseln der Fahrzeuge.
    - **Werkstatt:** `E:\Draw2Race-AudioLab`, eigenständig und durch Löschen des Ordners entfernbar.
    - **Musik:** Hauptwerkzeug ist seit 26.09.2026 **YuE2-3B**. Der Nutzer bewertet die Qualität als weit besser als ACE-Step.
      - `generate/yue_generate.py`: Basismodell über das offizielle Instrumental-Werkzeug.
      - `generate/yue_lora_generate.py`: mit Mothersuperiors Instrumental-AR-LoRA und Real-Audio-NAR-LoRA. Weniger Gesang, Zeitmarken wirken teilweise; sehr lange/rhythmische Stücke laufen aber an die Längengrenze und scheitern am Speicher.
      - Entwürfe liegen in `audio/entwurf/yue2/`. ACE-Step-Entwürfe bleiben in `audio/entwurf/` als Vergleich.
    - **Lizenzen:** Draw2Race wird **nicht-kommerziell** auf GitHub veröffentlicht. CC-BY-NC-Modelle (YuE2, LoRAs) sind deshalb erlaubt; die NC-Herkunft der Musik muss im Repo dokumentiert sein.
    - **Gesang:** YuE2 kann trotz „Instrumental“ singen. Jedes Stück mit `analyse/vocal_check.py` prüfen. Kurze Vokalisen („Ahh“) sind für den Nutzer in Ordnung, gesungener Text nicht.
    - **LoRA:** Der Nutzer bevorzugt das Basismodell ohne LoRA; mit LoRA klingen die Töne künstlich abgehackt.
    - **Zwei Musikstile** (Option im Spiel, Standard „energiegeladen“):
      - „energiegeladen“: eigene Songs mit Gesang, Texten und Kraftausdrücken, ausdrücklich erwünscht. Stilvorlagen sind die Lieblingslieder des Nutzers in `audio/Vorschläge/`, verwendet nur als Genre-Beschreibung, nie als Cover oder Melodievorgabe.
      - „ruhig“: Instrumentalstücke.
      - Songtexte stehen in `E:\Draw2Race-AudioLab\generate\songs.json` bzw. `audio/entwurf/yue2/songs/songs_mit_texten.json`.
    - **Musikablauf im Spiel:**
      - Eine durchgehende Zufalls-Playlist, keine Musik je Menü.
      - Überblendung am gemessenen Ausklingpunkt.
      - Beim Zeichnen stark abgesenkt, im Rennen wieder voll.
      - Eigene Stücke für Sieg und Niederlage (Sieg setzt am Punkt voller Energie ein), danach zurück zur Playlist.
      - Spielfertig machen mit `generate/export_music.py` nach `generate/spielmusik.json`.
    - **Nie veröffentlichen:** `audio/Vorschläge/`, `Videos/` und Referenz-Audio sind fremdes Material und in `.gitignore` ausgeschlossen.
    - **Keine Kopien:** Referenzaudio nie als Generator-Vorgabe einspeisen (kein Cover-/Melodie-Modus); nur Stil und Funktion beschreiben.
    - **Belegregel:** Tonaussagen nur treffen, wenn mindestens zwei Verfahren übereinstimmen. Offensichtliche Modellfehler (Stereo, Orte, Marken) nicht übernehmen.
    - **Abnahme:** Entwürfe gelten erst nach menschlicher Hörabnahme als verwendbar.
14. **Vereinbarte Reihenfolge (26.09.2026):**
    1. Streckenformat (erledigt)
    2. weitere Strecken: Stadt/L und Wald/Acht (erledigt, erste Fassung)
    3. Karriere mit Aufstieg und freischaltbaren Autos (erledigt: 5 Autos in `RaceVehicle.CARS`, Freischaltung über Gold)
    4. Bestenliste (erledigt, lokal: 10 beste Fahrten je Strecke/Herausforderung; online noch offen)
    5. erst danach der große Grafikschritt (Tag/Nacht, Wetter, Spiegelungen)

    Die Gegner sollen einen Spieler auf Niveau ~23 s (Azure) herausfordern.

Diese Datei fasst den vorhandenen Kontext zusammen. Sie führt keine zusätzliche Genehmigungspflicht ein; konkrete neuere Nutzeranweisungen haben Vorrang.
