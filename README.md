# Draw2Race

Ein Rennspiel für Android, bei dem du nicht lenkst, sondern planst: Du zeichnest mit dem Finger zwei Runden Ideallinie – **wie schnell** du zeichnest, ist das Tempo, das dein Auto fahren will. Dann startet das Rennen, und die Fahrphysik zeigt, ob deine Linie hält: Bremsweg, Haftungsgrenze, Rutschen und Dreher entstehen aus der Bewegung des Autos, nicht aus einer Animation.

**Version 0.1.0** · Godot 4.6.1 · offline spielbar · nicht-kommerzielles Hobbyprojekt

## Spielen

1. Unter [Releases](../../releases) die Datei `Draw2Race.apk` herunterladen.
2. Auf dem Android-Handy öffnen und die Installation erlauben (Installation aus unbekannten Quellen).
3. „Linie zeichnen“, am leuchtenden Startpunkt ansetzen und **zwei Runden in Pfeilrichtung** zeichnen.

**Linienkodierung:** langsam = breit und grün, schnell = schmal und rot (dazwischen gelb/orange). Wird die Linie breiter, bremst das Auto – plane den Bremsweg vor der Kurve ein.

**Beim Zeichnen**
- Finger abheben pausiert. Im **schimmernden Linienende** (jüngste Sekunde) darfst du neu ansetzen; nach 0,5 s Weitermalen ersetzt der neue Ansatz den alten Rest, das Tempo wird weich übergeblendet.
- Ein Finger auf freier Fläche verschiebt die Kamera, zwei Finger zoomen, Doppeltipp zeigt die ganze Strecke.
- Neben der Fahrbahn darfst du zeichnen (der Untergrund bremst), die Wegpunkt-Tore musst du aber durchfahren.

**Im Rennen:** Turbo halten. Er lädt sich beim Bremsen auf.

## Inhalt

- **Drei Strecken:** Azure Coast (Küstenoval), Downtown L (Stadt, L-Form), Forest Eight (Schotter-Acht mit Kreuzung ohne Ampel).
- **Karriere:** je Strecke drei Gold-Herausforderungen mit bis zu drei Rivalen; Gold schaltet Strecken und fünf Autos mit eigenen Fahrwerten frei.
- **Tageszeit, Wetter, Nebel:** fest je Herausforderung, von Tag bis Nacht mit Regen, Schnee und Nebelschwaden. Nässe und Schnee senken die Haftung.
- **Bestenliste:** die zehn schnellsten Fahrten je Strecke und Herausforderung.
- **Musik:** durchgehende Zufalls-Playlist in zwei Stilen („energiegeladen“ mit Gesang, „ruhig“ instrumental), eigene Stücke für Sieg und Niederlage.
- **Einstellungen:** Rennkamera, Tempo der Linie, Grafikqualität, getrennte Lautstärken für Musik und Geräusche.

## Selbst bauen

```powershell
./tools/setup.ps1              # lädt Godot 4.6.1 und Exportvorlagen nach .tools/
./tools/build.ps1 -Target Test # Headless-Prüfungen
./tools/build.ps1 -Target All  # Windows- und Android-Build nach builds/
```

Android benötigt zusätzlich JDK 17 und das Android SDK. Strecken sind Daten (`game/tracks/*.json`), erzeugt mit `tools/make_tracks.py`.

## Unterlagen

- [Implementierung und Teststand](docs/IMPLEMENTIERUNG.md)
- [Gestaltungs- und Spielrichtlinien](docs/RICHTLINIEN.md)
- [Umsetzungsplan](docs/UMSETZUNGSPLAN.md)
- [Referenzanalyse](docs/REFERENZANALYSE.md) und [Klang-Steckbriefe](docs/KLANG_STECKBRIEFE.md)
- [Grafikbesprechung mit ChatGPT (30.09.2026)](docs/BESPRECHUNG_GRAFIK.md)

## Herkunft und Lizenzen

Draw2Race steht unter **[CC BY-NC 4.0](LICENSE)**: Teilen und Verändern mit Namensnennung erlaubt, kommerzielle Nutzung nicht.

- **Musik:** eigene Stücke, lokal mit dem KI-Musikmodell **YuE2** erzeugt. Das Modell steht unter einer nicht-kommerziellen Lizenz (CC BY-NC 4.0); die Musik darf daher ebenfalls nur nicht-kommerziell genutzt werden.
- **Engine:** [Godot Engine](https://godotengine.org) (MIT), Lizenztexte in `game/assets/Godot-LICENSE.txt` und `Godot-COPYRIGHT.txt`.
- **Schrift:** Outfit (SIL Open Font License 1.1), `game/assets/OFL.txt`.
- **Inspiration:** Das Spielprinzip ist von *DrawRace 2* (RedLynx) inspiriert. Grafik, Strecken, Fahrzeuge, Musik und Geräusche sind eigene Arbeiten; aus dem Original wurde nichts übernommen.
