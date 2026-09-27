# Draw2Race — Umsetzungsplan

Stand: 24.09.2026. Status: **Planung**, keine beauftragte oder begonnene Spielimplementierung. Ausgangspunkt sind die [Referenzanalyse](REFERENZANALYSE.md) und [Richtlinien](RICHTLINIEN.md).

## 1. Technischer Vorschlag

**Arbeitsannahme: Godot mit GDScript, 3D-Darstellung und zunächst ebener eigener Fahrzeugsimulation.** Die konkrete stabile Engineversion wird beim Projektstart gewählt und festgehalten. Der Android-Export ist dokumentiert: [Godot-Dokumentation](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html), [Android Developers](https://developer.android.com/games/engines/godot/godot-export).

Diese Wahl ist noch keine Nutzerfestlegung. Sie passt als Ausgangspunkt zu kleinen 3D-Strecken, Touchbedienung, eigener Fahrphysik und einem frühen installierbaren Android-Prototyp. Eine andere Engine bleibt möglich; vor einer endgültigen Entscheidung stehen ein Gerätebuild und ein kurzer Versuch mit Darstellung, Eingabe und Simulation.

Die Fahrzeugbewegung wird zunächst in einer Ebene berechnet. Das sichtbare Auto und die Umgebung sind dennoch dreidimensional. Rampen, Sprünge, starke Fahrbahnneigungen und mehrstöckige Strecken erfordern eine spätere bewusste Erweiterung. Das vermeidet eine verfrühte Festlegung auf eine umfassende 3D-Fahrwerksimulation, ohne das visuelle Ziel aufzugeben.

## 2. Meilensteine und Abnahme

| Stufe | Lieferumfang | Fertig, wenn … |
|---|---|---|
| M0: technische Grundlage | Engine-/Projektstruktur, Android-Testbuild, Querformat, leere 3D-Teststrecke, Touchkoordinaten | App auf einem echten Zielgerät läuft; Eingabe auf verschiedenen Bildformaten stimmt; Fokusverlust sicher pausiert |
| M1: spielbarer Kern | Ein eigenes Oval, ein Fahrzeug, zwei gezeichnete Runden, Tempoprofil, Beschleunigen/Bremsen/Lenken/Haftung, Countdown, erste Kameraumschaltung, Ergebnis und Neuzeichnen | Unterschiedliche Linien und Bremspunkte messbar anders fahren; Übertreiben nachvollziehbar Zeit kostet; kompletter Ablauf ohne Bedienbruch wiederholbar ist |
| M2: erstes vollständiges Rennen | Ein Gegner, Turbo mit Bremsaufladung, gedämpfte Rennkamera, erste Motor-/Reifengeräusche, Platzierung und Neustart | Turbo eine echte Timingentscheidung ist; Gegner den gleichen Fahrzeugregeln folgt; Spieler und nächste Kurve sichtbar bleiben |
| M3: kleine Karriere | Hauptmenü, Eventkarten, Fahrzeugwahl, drei Eventstufen mit 1/2/3 Gegnern, Goldfortschritt, Freischaltungen, lokaler Spielstand, kurze Tutorials | Ein Event komplett durchspielbar ist; Sieg/Niederlage und Gold korrekt getrennt sind; Fortschritt nach App-Neustart erhalten bleibt |
| M4: visuelle und spielerische Vielfalt | Eine ausgearbeitete Dioramastrecke, danach verwinkelte Strecke und Winterthema, weitere Fahrzeuge, Effekte und abgemischter Sound | Grafik auch im Rennzoom lesbar ist; Fahrzeuge/Untergründe spürbar verschieden sind; Spiel auf dem Zielgerät dauerhaft flüssig bleibt |
| M5: lokale Veröffentlichungsversion | Lokale Bestzeiten/optional Geister, Einstellungen, robuste Speicherstände, Gerätetests, reproduzierbarer signierter Build | Gesamter lokaler Spielablauf offline funktioniert und die festgelegte Gerätematrix besteht |
| M6: optionale Vernetzung | Freundesherausforderungen, Online-Ranglisten, gegebenenfalls weiterer Mehrspieler | Regeln, Versionierung, Ergebnisprüfung und Betrieb geklärt sind; Grundspiel weiterhin offline verfügbar ist |

Abhängigkeit: **M0 → M1 → M2 → M3 → M4 → M5**. Erste Platzhalter für Sound und Grafik entstehen schon in M1/M2; die vollständige Ausarbeitung folgt später. M6 ist ein eigener Ausbau und keine Voraussetzung der ersten Version.

Nach M1 wird zuerst das Fahrgefühl beurteilt. Wenn Linienfolge oder Reifenverhalten noch nicht überzeugen, wird dort weiter abgestimmt, bevor viele Strecken entstehen. Nach M2 wird die Kamera mit dem Turbo zusammen getestet. Nach M3 lässt sich der Aufwand für zusätzlichen Inhalt wesentlich zuverlässiger planen.

Es gibt bewusst noch keinen belastbaren Kalendertermin: Zielgerät, grafischer Produktionsaufwand, gewünschte Inhaltsmenge und Abstimmungsbedarf der Physik sind offen. Eine Aufwandsschätzung sollte nach M1 mit tatsächlichen Erkenntnissen aktualisiert werden.

## 3. Vorgeschlagene Systemaufteilung

| Baustein | Verantwortung | Darf nicht übernehmen |
|---|---|---|
| TouchRecorder | Rohpositionen, Zeitstempel, Finger-ID, aktive Eingabezeit | Fahrzeug bewegen |
| TrackQuery | Fahrbahnbereich, Segmente, Richtung, Checkpoints, Untergrund | Spielregeln heimlich korrigieren |
| LineProcessor | Gültige Route, Glättung, räumliche Abtastung, Tempoprofil je Runde | Bewusst gezeichnete Bremspunkte durch eine Ideallinie ersetzen |
| DriverController | Lenken, Gas und Bremse aus Route und Zustand | Position setzen oder Kurvenfehler vollständig ausgleichen |
| VehicleSimulation | Kräfte, Geschwindigkeit, Gierbewegung, Schlupf, Kontakte | UI, Kamera oder Fortschritt steuern |
| RaceDirector | Phasen, Countdown, Runden, Platzierung, Zielzeiten | Bildrate als Rennuhr verwenden |
| OpponentDriver | Gegnerroute, Tempo-/Turboentscheidungen | Verdeckte Sonderphysik nutzen |
| CameraDirector | Übersicht, Übergänge, Verfolgung, Zoom | Simulationsergebnisse verändern |
| Presentation/Audio | Modelle, Partikel, HUD, Klang aus Zustand und Ereignissen | Neue physikalische Zustände erfinden |
| TyreTracks | Radpositionen, Untergrundspuren, Schmutzmitnahme und Brems-/Abriebspuren; begrenzter Speicher und Verblassen | Fahrzeugkräfte, Haftung oder Rundenzeiten verändern |
| ProgressStore | Ergebnisse, Goldstufen, Freischaltungen, Einstellungen | Belohnungen bei jedem Laden erneut vergeben |

Für die erste Version ist eine eigene feste Simulation mit einem klaren Besitzer des Fahrzeugzustands vorgesehen. Falls Engine-Kollisionsabfragen genutzt werden, darf nicht gleichzeitig ein RigidBody dieselbe Bewegung ein zweites Mal integrieren. Welche Kollisionsmethode passt, wird in M1/M2 erprobt.

## 4. Verarbeitung der gezeichneten Linie

1. Fingerposition mit Zeitstempel erfassen und in Streckenkoordinaten umrechnen. UI-Treffer, fremde Finger und pausierte Zeit getrennt behandeln.
2. Vollständige Segmente gegen die befahrbare Fläche prüfen, einschließlich Löchern/Innenflächen und Fahrtrichtung.
3. Rohdaten erhalten, um später Aufnahmefehler von Physikfehlern unterscheiden zu können.
4. Route geometrisch vorsichtig glätten und nach Wegstrecke abtasten. Start-/Rundennähte geschlossen und ohne Richtungsbruch behandeln.
5. Zeichengeschwindigkeit aus Weg und aktiver Zeit bestimmen. Verweilzeiten bei aufliegendem Finger ausdrücklich abbilden; keine Division durch null bei identischen Punkten.
6. Daraus eine begrenzte gewünschte Geschwindigkeit ableiten. Sie wird verbindlich als breite, helle Linie bei langsamem Tempo und schmale, rote Linie bei schnellem Tempo dargestellt (Nutzerpräzisierung vom 24.09.2026). Breite und Farbe gehen entlang der Linie fließend ineinander über und zeigen dadurch geplanten Tempoaufbau bzw. Bremsen. Der Fahrregler übersetzt die Vorgabe in Gas/Bremse mit endlicher Wirkung.
7. Jede Runde erhält ihr eigenes Profil. Voranschreiten über einen laufenden Streckenparameter und Checkpoints, nicht über unbeschränkte Suche nach dem nächstgelegenen Punkt.

Normalisierung und Kalibrierung müssen sicherstellen, dass höhere Bildschirmauflösung oder eine andere Bildrate keine andere Eingabe erzeugen. Bildschirmgröße und Komfort sind zusätzlich auf Handy und Tablet zu testen. Der Fahrregler liest die Vorgabe an seinem erreichten Streckenabschnitt; Zeichnungszeit ist nicht identisch mit einer starren Wiedergabeuhr.

## 5. Fahrzeugmodell und Abstimmung

Vorgeschlagener Minimalzustand: Position, Orientierung, Längs-/Quergeschwindigkeit, Gierrate, Lenkzustand und Turboladung. Grundparameter: Masse, Trägheitsmoment, Radstand, Vorder-/Hinterachsgrip, maximale Antriebs-/Bremskraft, Lenkeinschlag und Lenkgeschwindigkeit, Roll-/Luftwiderstand.

Ein einfaches Achsmodell mit begrenzten kombinierten Reifenkräften ist ein sinnvoller Start. Zunächst wird bei festem Zeitschritt, beispielsweise 60 Hz, gearbeitet; kleinere Schritte oder gezielte Unterteilungen werden bei tatsächlich auftretenden Stabilitäts-/Kontaktproblemen geprüft. Dieser Wert ist ein Arbeitsvorschlag, keine gemessene Eigenschaft der Referenz.

Die Abstimmung erfolgt in dieser Reihenfolge:

1. Gerade: Beschleunigung, Höchstgeschwindigkeit, Bremsweg.
2. Konstanter Kurvenradius: Haftungsgrenze und stabiler Bereich.
3. Lastwechsel: Bremsen in der Kurve, Beschleunigen am Ausgang.
4. Zu hohe Eingabe: verständliches Unter-/Übersteuern und Zeitverlust.
5. Rückkehr zur Linie nach Ausbruch ohne Abkürzung.
6. Turbo und anschließend Gegnerkontakte.

Zum Entwickeln werden geplante Linie, tatsächliche Spur, Soll-/Isttempo, Lenkwinkel, Schlupf und Rundenfortschritt optional eingeblendet. Diese Diagnosewerte gehören nicht in die normale Spieleroberfläche.

## 6. Daten und spätere Erweiterbarkeit

Vorgeschlagene Datenobjekte:

- `TrackDefinition`: ID/Version, Fahrbahnflächen, Ränder, Start/Ziel, geordnete Checkpoints, Untergrundzonen, Referenzroute, Kameraübersicht und Umgebungsreferenz.
- `CarDefinition`: ID/Version, Fahrzeugparameter, Modell, Audiozuordnung, UI-Werte.
- `EventDefinition`: Strecke, erlaubte Fahrzeuge, Rundenzahl, Gegnerstufen, Siegbedingungen, Freischaltungen.
- `RunRecord`: Strecke/Fahrzeug/Event/Physikversion, Roh- bzw. verarbeitete Eingabe, Turboaktionen auf Simulationszeit, Startzustand, Gegnerkonfiguration/Seed, Zielzeit und gegebenenfalls aufgezeichnete Zustände.
- `PlayerProgress`: eindeutige gewonnene Eventstufen, Bestzeiten, Freischaltungen und Einstellungen mit Speicherformatversion.

Roh-Eingabe und feste Zeitschritte allein garantieren keine bitgenauen Wiederholungen auf verschiedenen Geräten. Für erste Geister können tatsächlich aufgezeichnete Zustände verwendet werden. Für spätere verifizierte Online-Ergebnisse braucht es eine gesonderte Lösung; eine bloß vom Client gemeldete Zeit reicht dafür nicht.

Spielstände werden nach abgeschlossenen Ergebnissen atomar geschrieben, mit Formatversion und Rückfallkopie. Laden darf keine bereits vergebene Belohnung duplizieren. Unterbrechungen während eines Rennens verändern keinen bereits erreichten Karrierefortschritt.

## 7. Tests mit konkretem Erkenntniswert

Automatisierte Prüfungen konzentrieren sich auf Regeln, deren Fehler dem Spieler tatsächlich schaden:

| Bereich | Aussagekräftige Prüfung |
|---|---|
| Touch | Gleiche zeitgestempelte Geste bei verschiedenen Renderbildraten ergibt vergleichbares Profil |
| Gültigkeit | Segment schneidet Innenfläche trotz gültiger Endpunkte; große Eingabesprünge; falsche Richtung |
| Zeitbehandlung | Fingerpause und App-Pause erzeugen keine unbeabsichtigte Vollbremsung; aktives Verweilen hat die definierte Wirkung |
| Runden | Zweite gezeichnete Runde bleibt verschieden; Zielübertritt erst nach geordneten Checkpoints; kein Sieg durch Rückwärtskreuzen |
| Physik | Kontrollierte Vergleichsfälle für Bremsweg, Kurvengrenze und Überschwingen, keine bloße Prüfung interner Funktionsnamen |
| Turbo | Ladung bleibt im gültigen Bereich; kein Aufladen im Stillstand; kein Verbrauch in Pause |
| Ergebnis | Zwei Zielübertritte innerhalb eines Schritts korrekt sortieren; gleiche Anzeigezeit entscheidet nicht über Gleichstand |
| Fortschritt | Gold nur einmal je Stufe; Niederlage erhält Fortschritt; Laden/Neustart verdoppelt keine Belohnung |
| Wiederholung | Gleicher Ausgangszustand und Eingabe liefern im selben Build innerhalb definierter Toleranz dieselbe Fahrt |

Manuelle Geräteprüfung ergänzt diese Tests: Fingergefühl, Lesbarkeit, Kamerabewegung, Ton, Displayausschnitte, Android-Zurück/Fokuswechsel, mindestens eine längere Spielsession. Als anfängliches Leistungsziel werden 60 dargestellte Bilder/s auf dem später benannten Zielgerät angestrebt; ein begrenzter 30-fps-Modus darf die Simulation nicht verändern. Das ist ein Ziel, keine bereits gemessene Leistung.

## 8. Hauptrisiken und Gegenmaßnahmen

| Risiko | Früher Gegenversuch |
|---|---|
| Auto fährt wie auf Schienen | Zu schnelle Kurve bewusst vorgeben und Abweichung/Verlust messen |
| Auto wirkt unkontrollierbar | Gleiche Testlinien wiederholen, Regler und Reifen getrennt abstimmen |
| Zeichnen wird auf kleinem Display fummelig | M0/M1 auf echtem Handy testen, großzügige Endpunkt-/Starttoleranz |
| Kamera verdeckt Fehler oder erzeugt Unruhe | Feste Übersicht als Vergleich, gedämpfte Verfolgung mit begrenztem Zoom |
| Umfang der Grafik verdrängt Kernmechanik | Zuerst eine vollständig spielbare Strecke, dann ein visuelles Muster ausarbeiten |
| Reifen-/Kontaktphysik wird zu komplex | Ebener Kern zuerst; Höhen, Sprünge und mehrstöckige Strecken separat bewerten |
| Gegner erscheinen unfair | Gemeinsame Physik und nachvollziehbare Gegnerprofile; Kontakte gesondert abstimmen |
| Bestenlisten werden nach Updates unvergleichbar | Physik-, Strecken-, Fahrzeug- und Regelversion im Ergebnis speichern |

## 9. Offene Entscheidungen mit vorläufiger Annahme

Diese Punkte blockieren die jetzige Planung nicht. Sie werden zu dem Zeitpunkt entschieden, an dem sie die Umsetzung beeinflussen.

| Entscheidung | Arbeitsannahme | Spätestens relevant |
|---|---|---|
| Engine und Sprache | Godot/GDScript nach Geräteversuch | M0 |
| Zielhandy/-tablet und Android-Untergrenze | Noch nicht bekannt; reale Geräte festlegen | M0 |
| Nähe zum Originallook | 3D-Diorama, eigene Oberfläche und Assets | M1/M4 |
| Fingerabheben/Neuzeichnen | Fortsetzen am Endpunkt, expliziter Neustart | M1 |
| Spielgefühl | Zugänglich, mit echten Haftungsgrenzen | M1 |
| Turbo bedienen | Halten zum Verbrauchen | M2 |
| Fahrzeugkontakte | Physische Kontakte nach Grundmodelltest; Bestzeitgeist ohne Kollision | M2 |
| Karrieregröße der ersten Version | Kleine Auswahl; keine automatische Übernahme der 180 Originalherausforderungen | M3 |
| Soundcharakter | Erst Hörvergleich, dann eigene Klangproduktion | M2/M4 |
| Onlinefunktionen | Lokaler Kern zuerst, Vernetzung optional | M6 |
| Monetarisierung | Keine Annahme und kein Bestandteil des Prototyps | Vor Veröffentlichungsplanung |

## 10. Nächster konkreter Arbeitsschritt

Bei einem anschließenden Umsetzungsauftrag beginnt die Arbeit mit M0/M1: eine eigene einfache Ovalstrecke, eine sichtbare Linie mit zeitbasierter Eingabe und ein Auto, dessen Beschleunigung, Bremsen und Kurvengrenzen unabhängig von der Linie berechnet werden. Kamera und Ergebnis machen daraus schon einen vollständig wiederholbaren Ablauf.

Die wichtigste gemeinsame Beurteilung lautet anschließend: **Ist eine bewusst besser gezeichnete Runde nachvollziehbar schneller, und macht der nächste Versuch Lust?** Erst danach wird der Umfang erweitert.
