# Referenzmaterial zur Analyse

> Die hier verlinkten Bilder und Hörstellen stammen aus einem fremden, urheberrechtlich geschützten Video. Sie liegen nur lokal vor und sind nicht Teil des veröffentlichten Repositorys.

Quelle: `../../Videos/DrawRace 2 - iPhone - NZ - HD Gameplay Trailer.mp4` (15:02 Minuten). Alle Zeitmarken beziehen sich auf das Video. Extraktion am 24.09.2026. Dateien in diesem Ordner sind Analysebelege und keine fertigen Spielassets.

## Überblick über die gesamte Aufnahme

Die Übersicht enthält ein Bild je 150 Quellframes, also etwa alle 5,005 Sekunden. Die Zeitmarken stehen jeweils über den Bildern. Schwarze Ränder stammen aus der Aufnahme.

| Zeitraum, ungefähr | Kontaktbogen |
|---|---|
| 00:00–01:15 | [01 — Menüs, Tutorial, Zeichnen](overview_01.jpg) |
| 01:20–02:35 | [02 — erstes Rennen und Freischaltungen](overview_02.jpg) |
| 02:40–03:55 | [03 — weitere Gegner](overview_03.jpg) |
| 04:00–05:15 | [04 — Niederlage, Sieg, Turboeinführung](overview_04.jpg) |
| 05:20–06:35 | [05 — zweites Oval](overview_05.jpg) |
| 06:40–07:55 | [06 — Oval, steigende Gegnerzahl](overview_06.jpg) |
| 08:00–09:15 | [07 — Kurventutorial und Palmenstrecke](overview_07.jpg) |
| 09:20–10:35 | [08 — Palmenstrecke, weitere Versuche](overview_08.jpg) |
| 10:40–11:55 | [09 — knappes Ergebnis und Wiederholung](overview_09.jpg) |
| 12:00–13:15 | [10 — Übergang zur Schneestrecke](overview_10.jpg) |
| 13:20–14:35 | [11 — Schneestrecke und Niederlage](overview_11.jpg) |
| 14:40–15:01 | [12 — Ergebnis, Pause, Karrierefortschritt](overview_12.jpg) |

## Dichtere Bildsequenzen

Die schwarzen Aufnahmeflächen wurden für diese Kontaktbögen weitgehend abgeschnitten. Jede Zelle zeigt ihre eigene Videoposition.

- [00:44–01:04: Tutorialhand, Zeichnen und Rennen](sequence_0044.00_01.jpg), alle zwei Sekunden.
- [01:23–01:34: Linie, Countdown, Kamerazoom, erste Kurve](sequence_0083.00_01.jpg), jede Sekunde.
- [08:35–08:57: Palmenstrecke, Kameraführung und Turboanzeige](sequence_0515.00_01.jpg), alle zwei Sekunden.
- [12:50–13:00: Schneestrecke, Kurvenfahrt und Orientierung](sequence_0770.00_01.jpg), jede Sekunde.

## Ausgewählte Belege

- [00:15 Hauptmenü](detail_0015.jpg)
- [00:22 Karriereklasse und Freischaltschwelle](detail_0022.jpg)
- [00:40 Erklärung der drei Gold-Herausforderungen](frame_0040.00.jpg)
- [01:55 Ergebnis mit erster Goldmedaille](frame_0115.00.jpg)
- [02:00 Fahrzeugfreischaltung](detail_0120.jpg)
- [02:05 Streckenfreischaltung](detail_0125.jpg)
- [02:15 Fahrzeugwerte](detail_0135.jpg)
- [04:00 Silber für Platz zwei](detail_0240.jpg)
- [04:55 Turbo lädt beim Bremsen](frame_0295.00.jpg)
- [08:05 Tutorial zu frühem Bremsen und weitem Kurvenradius](frame_0485.00.jpg)
- [11:25 Ergebnis mit vier Millisekunden Abstand](frame_0685.00.jpg)
- [14:01 Niederlage verhindert nächste Freischaltung](frame_0841.00.jpg)
- [14:56 Pausemenü](frame_0896.00.jpg)

## Vorbereitete Hörstellen

Die Tonspur ist vorhanden. Die Ausschnitte sind **noch nicht hörend analysiert**, wurden aber am 26.09.2026 messtechnisch ausgewertet (siehe unten). Die Namen bezeichnen die sichtbaren Szenen.

- [Menü/Auswahl, 00:15–00:33](audio_menu.mp3)
- [Start/Oval, 01:25–01:39](audio_start_oval.mp3)
- [Rennen mit Turboanzeige, 05:25–05:49](audio_turbo.mp3)
- [Ergebnis/Freischaltung, 01:53–02:07](audio_ergebnis.mp3)
- [Schneestrecke, 12:52–13:12](audio_schnee.mp3)

Zusätzlich liegt `audio_race_0525.wav` als technisch vorbereiteter Mono-Ausschnitt vor. Er diente dem erfolglosen Versuch, Audio an die Analyse zu übergeben; daraus wurden keine Höreindrücke abgeleitet.

## Spektrogramme der Tonspur

Die Ergebnisse stehen in [REFERENZANALYSE.md, Abschnitt 9](../REFERENZANALYSE.md#9-ton). Die Bilder erzeugt `tools/analyze_audio.ps1` (nur ffmpeg nötig).

- [Gesamte Aufnahme](audio_spec_gesamt.png)
- [Menü, 00:15–00:33](audio_spec_menu.png): Musik, UI-Sweep bei „Career“
- [Start, 01:24,5–01:29](audio_spec_start.png) und [Startsignal linear, 700–2200 Hz](audio_spec_startsignal.png)
- [Motorband im Oval, 01:27–01:41](audio_spec_motor.png)
- [Ergebnis/Übergang, 01:53–02:13](audio_spec_ergebnis.png)
- [Rennen mit Turbo-HUD, 05:25–05:49](audio_spec_turbo.png)
- [Schneestrecke, 12:52–13:12](audio_spec_schnee.png)

## Reproduktion

`tools/analyze_reference.py` benötigt Python mit Pillow und `ffmpeg` im Suchpfad. Vom Projektverzeichnis aus:

```powershell
python tools/analyze_reference.py --overview
python tools/analyze_reference.py --times 15 40 115 295 485 685 841 896
python tools/analyze_reference.py --sequence 83 94 1
```

Verwendet wurde ein eigenständiger Python-Interpreter, weil der normale `python`-Befehl auf den Windows-Store-Alias zeigte. Das Skript verwendet Arial aus dem Windows-Fontordner. Die dichten Sequenzbögen benutzen einen auf diese Aufnahme abgestimmten Ausschnitt; das ist keine allgemeine Videozuschneidefunktion.

Die kleinen Rohbilder in `overview_frames/` und die vollständigen `frame_*.jpg` ermöglichen einen späteren genaueren Vergleich. Die Analyse erklärt die Grenzen dieser Stichproben.
