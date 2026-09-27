# Referenzanalyse: DrawRace 2 → Draw2Race

Stand: 24.09.2026. Quelle: `../Videos/DrawRace 2 - iPhone - NZ - HD Gameplay Trailer.mp4`.

## 1. Methode und Verlässlichkeit

Die Datei dauert 902,095 Sekunden, enthält ein 1440 × 1080 großes Bild bei rund 29,97 Bildern/s und eine AAC-Stereospur mit 44,1 kHz. Innerhalb der Videodatei liegt das eigentliche Spielbild ungefähr in einem 1020 × 680 großen Rechteck. Die schwarzen Außenflächen gehören zur Aufnahme. Daraus folgt **keine** Vorgabe für das Seitenverhältnis der neuen App.

Ausgewertet wurden 181 Übersichtsbilder über die gesamte Laufzeit sowie gezielte Einzelbilder und vier dichtere Bildsequenzen. Zeitmarken sind Videopositionen, nicht die eingeblendete Rennzeit; Abschnittsgrenzen sind ungefähr. Kurze Vorgänge zwischen den Stichproben können fehlen. Exakte Kamerakurven, Kollisionsregeln, Latenz und Physikparameter lassen sich daraus nicht messen.

Kennzeichnungen:

- **Beobachtung:** im Bild oder einem eingeblendeten Tutorial erkennbar.
- **Ableitung:** plausible Interpretation; interne Umsetzung unbekannt.
- **Vorschlag:** Entscheidung für Draw2Race, nicht als Originalverhalten belegt.
- **Offen:** in dieser Referenz oder mit der Auswertungsmethode nicht geklärt.

Die Audiospur wurde am 26.09.2026 zweifach ausgewertet:
- **messtechnisch** (Spektrogramme, Pegel, Stille, Stereobreite; Abschnitt 9);
- **KI-gestützt beschrieben** mit lokalen Modellen (Musikstil, Instrumente, Stimmung, Effekte; siehe [KLANG_STECKBRIEFE.md](KLANG_STECKBRIEFE.md)).

Claude hört nicht selbst. Stilaussagen gelten nur, wenn mindestens zwei Verfahren übereinstimmen.

## 2. Ablauf mit Zeitmarken

| Videoposition | Beobachtung | Bedeutung für Draw2Race |
|---|---|---|
| 00:00–00:14 | Marken-/Ladebilder | Kurzer Einstieg; Ladeanzeige getrennt vom Hauptmenü |
| 00:15–00:18 | Hauptmenü mit Career, Multiplayer, World League, Friend Challenge; mehrere Schloss-Symbole | Karriere als klarer Einstieg, weitere Modi getrennt |
| 00:19–00:30 | Horizontal wechselnde Karriereklassen; Rookie offen, höhere Klassen gesperrt; Goldzähler | Freischaltung über erspielten Fortschritt |
| 00:31–00:39 | Eventkarten mit Vorschaubild und Sperren | Streckenauswahl über wiedererkennbare Bilder |
| 00:40–01:04 | Missionshinweis und animierte Zeichendemonstration mit Hand | Mechanik durch Vormachen erklären |
| 01:05–01:25 | Erstes eigenes Zeichnen auf einem Stadionoval, zwei Runden | Eine zusammenhängende Planung vor dem Rennen |
| 01:26–01:54 | Ampelstart, zwei Autos, näher heranfahrende und mitbewegte Kamera | Deutlicher Wechsel vom Planen zum Rennen |
| 01:55–02:09 | Ergebnis, erstes Gold, Fahrzeug- und Streckenfreischaltung | Erfolg führt unmittelbar zu neuem Inhalt |
| 02:10–03:09 | Event-/Fahrzeugauswahl und Wiederholung mit zwei Gegnern | Gleiche Strecke, nächste Herausforderung |
| 03:10–04:45 | Rennen mit drei Gegnern, zunächst Platz zwei, dann Sieg und 3/3 Gold | Wiederholen und Verbessern als Kern des Fortschritts |
| 04:50–05:10 | Fahrzeugwahl, Turbo-Tutorial und Demonstration | Turbo wird nach den Grundlagen eingeführt |
| 05:11–07:55 | Zweites Oval mit anderer Beleuchtung; Turbo unten rechts; drei Erfolgsstufen | Wenig zusätzliche Bedienung während des Rennens |
| 08:00–08:22 | Tutorial zu frühem Bremsen und weitem Kurvenradius | Fahrtechnik wird in kleinen Schritten vermittelt |
| 08:23–09:14 | Verwinkelte Strecke um Palmen/Wasser, erstes Gold, Rallyauto und Schneestrecke als Belohnung | Neue Strecken verlangen andere Linien und Bremspunkte |
| 09:15–12:18 | Wiederholungen der Palmenstrecke, enges Ergebnis, schließlich drei Gold-Erfolge | Kleine Verbesserungen entscheiden über den Sieg |
| 12:19–14:52 | Fahrzeugwahl und mehrere Versuche auf verschneiter Strecke, auch Niederlagen | Andere Umgebung und anspruchsvollerer Fahrverlauf |
| ca. 14:55–15:02 | Kurzes Pausemenü, Rückkehr in die Karriere; Goldstand 9/36 und gesamt 9/180 | Fortschritt bleibt nach dem Verlassen erhalten |

Die Übersichtsbilder sind im [Referenzverzeichnis](reference/README.md) gruppiert.

## 3. Grafikstil und Strecken

**Beobachtung:** Die Fahrzeuge und Strecken wirken räumlich, aus erhöhter, schräger Perspektive betrachtet. Die Umgebungen sind als kompakte, detailreiche Rennanlagen gestaltet. Sichtbare Merkmale sind klare Fahrzeugfarben, Schatten, Curbs, Straßenmarkierungen, Zäune, Tribünen, Zuschauermassen und zahlreiche kleine Dekorationen.

Vier ausgiebig gezeigte Umgebungen:

1. Helles Stadionoval mit roten Tribünen, markantem Innenbereich und breiter Fahrbahn.
2. Zweites Oval mit dunklerer Umgebung, farbiger Beleuchtung und blau/roten Begrenzungen.
3. Verwinkelte Straßenstrecke um ein zentrales Wasser-/Felsmotiv mit Palmen, engen Kehren und einem kleinen hölzernen Objekt quer zur Fahrbahn.
4. Verschneite Strecke mit deutlichen Fahrspuren, Tannen, Felsen, Warnpfeilen und enger oberer Kehre.

**Ableitung:** Der Reiz entsteht aus einem Modellbau-/Diorama-Eindruck und der guten Erkennbarkeit kleiner Autos. Die Strecke besitzt erkennbare Orientierungspunkte; ein bloß aufgemalter Straßenring würde diesen Eindruck nur teilweise treffen.

**Offen:** Ob das hölzerne Objekt tatsächlich eine physikalische Sprungrampe ist, wie stark Höhen und Fahrbahnneigung simuliert werden und welche Hintergrundelemente animiert sind, ist mit den untersuchten Bildern nicht sicher feststellbar. Schnee als Bildmotiv beweist allein keine konkrete Reibungskennlinie.

**Vorschlag:** 3D-Darstellung mit eigener Gestaltung, zunächst ebene Fahrsimulation. Visuelle Umgebung, befahrbare Fläche und Kollisionsgeometrie getrennt modellieren. Beleuchtung und Materialien dürfen abwechslungsreich sein, aber die Fahrbahn muss schnell lesbar bleiben.

## 4. Menüs und Bedienung

**Beobachtung:** Helle graue Hintergründe, rote Überschriften und Aktionen, weiße Flächen, dunkle Schrift, Metallränder und große runde Schaltflächen. Karten zeigen Autos und Events. Sperren sind mit Schlössern und Freischaltbedingungen dargestellt. Gold ist ein auffälliger Erfolgsakzent.

Belege: [Hauptmenü 00:15](reference/detail_0015.jpg), [Karriereklasse 00:22](reference/detail_0022.jpg), [Fahrzeugwahl 02:15](reference/detail_0135.jpg).

Der sichtbare Ablauf ist:

`Hauptmenü → Karriereklasse → Event → gegebenenfalls Fahrzeugwahl/Tutorial → Zeichnen → Start → Rennen → Ergebnis → Belohnung oder nächster Versuch`

Fahrzeugkarten haben vier Werte: **Top Speed, Acceleration, Cornering, Turbo**. Die Werte werden als Balken statt Zahlen gezeigt. In der Karriere sind nicht alle dargestellten Fahrzeuge gleichermaßen auswählbar; daraus lässt sich eine Einschränkung nach Event/Fahrzeugklasse vermuten.

Das HUD bleibt klein: Rundenanzeige und Zeit links oben, ein Zurück-/Pauseelement rechts oben, später der Turbo rechts unten. Die Ergebnisansicht bietet Vergleich, Neustart und Weiter. Ein Pauseoverlay mit drei Symbolaktionen ist am Ende sichtbar; die einzelnen Aktionen wurden nicht vollständig ausgeführt.

**Offen:** Wisch- versus Tippbedienung der Karten ist aus einer Aufnahme ohne echte Touchmarker nicht überall eindeutig. Die Tutorialhand ist eine Demonstration, kein Nachweis aller tatsächlichen Fingereingaben. Einstellungen, Audiooptionen und vollständige Hilfemenüs werden nicht gezeigt.

## 5. Zeichnen und Tempovorgabe

**Beobachtung:** Vor dem Rennen steht „Please draw 2 laps“. Am Start befinden sich ein Kreis und Richtungspfeile. Während des Zeichnens wachsen rot-orange bis gelbliche Linien mit unterschiedlicher Breite. Der Rundenfortschritt wird angezeigt. Nach Abschluss folgt die Startampel. Im Rennen ist die geplante Route zumindest in Abschnitten schwach sichtbar.

Belege: [Tutorial 00:44–01:04](reference/sequence_0044.00_01.jpg), [Zeichnen → Start 01:23–01:34](reference/sequence_0083.00_01.jpg).

**Nutzeranforderung:** Zeichentempo beeinflusst Gas/Tempo; Zeichnen soll innerhalb der Strecke bleiben. Das Video passt zu diesem Grundprinzip. Die exakte Zuordnung von Farbe/Breite zu Geschwindigkeit und die mathematische Umrechnung sind nicht ausgelesen.

**Ableitung:** Die breiteren helleren Linienabschnitte in Kurven sprechen für eine sichtbare Rückmeldung zum geplanten Tempo. Die genaue Kennlinie bleibt offen.

**Offen:** Verhalten bei Fingerabheben, Pausen, Rückwärtszeichnen, sehr schnellen Bewegungen, absichtlichem Verlassen der Fahrbahn oder Abkürzungen. Aus regulären Runden kann keine bestimmte Fehlerbehandlung abgeleitet werden.

**Vorschlag:** Zwei separat gespeicherte Runden in einem Zeichenablauf. Nicht einfach eine Runde zweimal abspielen. Positionen und Zeitstempel aufzeichnen, Tempo in Streckenkoordinaten bestimmen und Eingaberuckeln vorsichtig glätten. Die frühere Rundenlinie bei Überlagerung deutlich abschwächen.

## 6. Fahrphysik, Gegner und Turbo

**Beobachtung:** Autos beschleunigen aus dem Stand, verlieren und gewinnen Abstand, nehmen unterschiedliche Kurvenradien und erscheinen in Kurven teils quer zur Fahrtrichtung. Die vorgezeichnete Route bleibt eine sichtbare Referenz. Ein eingeblendetes Tutorial fordert frühes Bremsen und eine weite Kurvenlinie. Eine vollständige 360°-Drehung ist in den analysierten Stichproben nicht eindeutig belegt.

**Nutzeranforderung:** Bremsweg, Ausbrechen und gegebenenfalls Dreher sollen aus überzogenen Vorgaben entstehen. Dafür muss das Fahrzeug über Gas, Bremse und Lenkung gesteuert werden; die Linie darf nicht direkt seine Position setzen.

**Beobachtung:** Aufeinanderfolgende Karrierestufen desselben Events zeigen einen, zwei und drei Gegner. Fahrzeuge liegen teils dicht zusammen. Ob jeder Kontakt physische Impulse erzeugt oder bestimmte Situationen anders behandelt werden, ist nicht eindeutig belegt.

Das [Turbo-Tutorial bei 04:55](reference/frame_0295.00.jpg) sagt ausdrücklich, dass Turbo kurz beschleunigt und sich beim Bremsen auflädt. Später zeigt ein runder roter Knopf rechts unten einen farbigen Ladezustand. Seine Helligkeit/Füllung verändert sich. In der [Palmen-Rennsequenz](reference/sequence_0515.00_01.jpg) sind auch kurze helle Effekte hinter einem Fahrzeug sichtbar.

**Offen:** Mindestladung, Halten versus Tippen, genaue Dauer, Verbrauchsrate, Aufladeformel, Startfüllung und Einfluss auf die Höchstgeschwindigkeit. Auch die Gegnersteuerung ist unbekannt.

**Vorschlag:** Turbo nur als zusätzliche Antriebskraft innerhalb derselben Fahrzeugphysik. Bremsen lädt nach einer konfigurierbaren Regel. Gegner verwenden ebenfalls gültige Routen und dieselbe Physik, erhalten aber eigene Tempoprofile und Turboentscheidungen.

## 7. Kamera und Zoom

**Beobachtung:** Beim Zeichnen ist nahezu die ganze jeweilige Strecke sichtbar. Es gibt auch dort leichte Veränderungen des Ausschnitts bzw. der Perspektive; eine vollkommen starre Originalkamera ist nicht belegt. Beim Wechsel zum Rennen wird die Ansicht deutlich näher. Danach bewegen sich Ausschnitt und Orientierung über die Strecke. Das HUD bleibt am Bildschirm verankert.

Die [Sequenz 01:23–01:34](reference/sequence_0083.00_01.jpg) zeigt den Übergang besonders klar. [08:35–08:57](reference/sequence_0515.00_01.jpg) und [12:50–13:00](reference/sequence_0770.00_01.jpg) zeigen die Kamera auf verwinkelten Strecken.

**Ableitung:** Eine geführte Kamera, die dem Renngeschehen folgt und etwas vorausblickt, ist eine passende Nachbildung. Ob das Original auf den Spieler, eine Fahrzeuggruppe, die Strecke oder eine Kombination zielt, ist aus dem Video nicht sicher bestimmbar. Gleiches gilt für geschwindigkeitsabhängigen Zoom und exakte Neigungswinkel.

**Vorschlag:** Eigene Kamerazustände für Übersicht, Startübergang, Rennen und Ergebnis. Zunächst eine feste Übersicht während aktiver Zeicheneingaben, eine weich folgende Rennkamera und ein begrenzter Vorausblick. Erweiterte Drehung und dynamischer Zoom erst nach einem Vergleich auf echten Geräten abstimmen.

## 8. Ranking, Medaillen und Freischaltungen

Zwei unterschiedliche Systeme müssen getrennt werden:

1. **Platzierung im einzelnen Rennen:** Ergebnisliste mit Namen und Zeiten, Spielerzeile rot hervorgehoben, große Medaille. Platz zwei zeigt Silber.
2. **Karrierefortschritt eines Events:** Drei Gold-Erfolge gegen steigende Gegnerzahl. Ein weiterer Sieg erhöht den Eventstand von 1/3 auf 2/3 auf 3/3.

Belege: [erstes Ergebnis 01:55](reference/frame_0115.00.jpg), [zweiter Platz 04:00](reference/detail_0240.jpg), Übersichtsbilder bei 04:40 und 07:50. Das [Missions-Tutorial](reference/frame_0040.00.jpg) beschreibt diese Struktur ausdrücklich.

Bei der Schneestrecke enthält die Silber-Ergebnisansicht am Ende den Hinweis, dass zum Freischalten des nächsten Rennens ein Sieg nötig ist. Der Karrierebildschirm zeigt zum Ende neun Goldmedaillen; höhere Klassen besitzen eigene Schwellen. Die große Gesamtzahl von 180 gehört zum Originalumfang und wird nicht automatisch zum Umfang von Draw2Race.

Rennzeiten werden im Ergebnis mit drei Nachkommastellen gezeigt; das Renn-HUD nutzt zwei. Ein besonders knappes Ergebnis um **11:25** beträgt **20,850 s gegenüber 20,854 s**. Für Draw2Race sind daher präzise interne Zeitmessung und eine definierte Gleichstandsregel sinnvoll; die Anzeige allein beweist keine Messgenauigkeit der alten Engine.

**Ranking-Grenze:** „Compare with Others“, „World League“ und „Friend Challenge“ sind als Einstiege sichtbar. Deren Ranglistenseiten, Filter, Saisonregeln, Synchronisation und Mehrspielerablauf werden nicht vorgeführt. Diese Funktionen dürfen nicht als analysierte Details des Originals beschrieben werden.

## 9. Ton

### 9.1 Messtechnische Auswertung (26.09.2026)

Methode: `tools/analyze_audio.ps1` (ffmpeg). Die Spektrogramme liegen in `reference/audio_spec_*.png` und wurden mit Einzelbildern derselben Videopositionen verglichen. Die Frequenzangaben sind aus den Spektrogrammen abgelesen, also Näherungswerte (etwa ±30 Hz).

**Technik der Aufnahme (Beobachtung):**

- Die Spur ist zwar als Stereo gespeichert, das Seitensignal liegt aber bei etwa −75 dB gegenüber −18 dB Mittensignal. Praktisch ist sie also **mono**. Über Stereo-Panorama lässt sich daher nichts ableiten.
- Die integrierte Lautheit beträgt −14,3 LUFS bei einem Lautheitsbereich von 12,5 LU. Stille unter −45 dB tritt nur 3 s am Anfang und bei sechs rund 2 s langen Szenenschnitten auf (00:43, 01:02, 04:59, 05:09, 08:08, 08:20). Die Aufnahme ist also durchgehend vertont.
- Über fast die gesamte Laufzeit fällt ein schmales Band um ~1 kHz ab. Das ist wahrscheinlich ein Aufnahme- oder Kodierungsartefakt und kein Spielklang.

**Startsequenz 01:25–01:28 (Beobachtung, mit Bild abgeglichen):**

- Synchron zum Aufleuchten der Startampel ertönen **vier kurze Töne** von je ~0,1 s bei ~1050 Hz im Abstand von ~0,35 s. Die ungeradzahligen Obertöne (~3,1 kHz, ~5,2 kHz) sprechen für eine rechteck- oder pulsartige Wellenform (Ableitung).
- Beim Erlöschen der Ampel und dem Start der Rennuhr folgt **ein langer Startton** von ~0,7 s bei ~2030 Hz, eine Oktave höher, gleichzeitig mit ~1050 Hz.
- Direkt danach steigt die Energie im Tieftonbereich (100–300 Hz) deutlich an. Das passt zum Losfahren (Ableitung).

**Rennen (Beobachtung/Ableitung):**

- Im Oval (01:27–01:41, `audio_spec_motor.png`) verlaufen zwei tonale Bänder bei ~300–380 Hz und ~420–500 Hz. Auf Geraden steigen sie langsam an, beim Einlenken in Kurven (Renn-Uhr ~4,6 s und ~9,3 s) sinken sie kurz ab und steigen dann wieder. **Ableitung:** Ein Motorton folgt der Fahrzeuggeschwindigkeit bzw. Drehzahl. Die Tonhöhe ändert sich dabei nur mäßig, etwa um den Faktor 1,3–1,5, nicht über mehrere Oktaven. Deutliche Schaltsprünge sind nicht zu erkennen.
- Auf der Strecke mit Turbo-HUD (05:25–05:49) treten alle ~2,5–4 s breitbandige Rauschschübe auf (400 Hz–8 kHz) mit V-förmigen Tonhöhenverläufen. Sie fallen zeitlich mit Kurvenfahrten zusammen. **Ableitung:** Reifen- bzw. Rutschgeräusch, abhängig von der Querbelastung.
- Auf der Schneestrecke (12:52–13:12) gibt es in Kurven ebenfalls Rauschschübe, dort vor allem zwischen 2 und 10 kHz. Dazu kommen gebogene Tonverläufe bei 700–1400 Hz. **Ableitung:** Ein untergrundabhängiges Rutschgeräusch klingt anders als auf Asphalt. Ob der Untergrund oder das Fahrzeug die Ursache ist, lässt sich nicht trennen.
- In beiden Rennen gibt es kurze, einzelne Klicks mit Tonanteilen bei ~2,2 kHz und ~3,6 kHz, im Abstand von einigen Sekunden. **Offen:** Die Ursache ist nicht zugeordnet (Kollision, Checkpoint, Überholen oder Turbo wären möglich).

**Menü und Ergebnis (Beobachtung/Ableitung):**

- In Menü- und Ergebnisszenen zeigt das Spektrogramm gestapelte, gehaltene Obertonreihen mit Abschnittswechseln. Das spricht für tonale **Musik**. Ob während der Rennen Musik läuft, lässt sich vom Fahrzeugklang nicht sicher trennen.
- Beim Antippen von „Career“ (00:18) erscheint ein kurzer, steil ansteigender Sweep im Bereich 4–9 kHz. **Ableitung:** Das ist ein Klickgeräusch für Bedienelemente.
- Beim Wechsel vom Ergebnis- bzw. Freischaltbildschirm zur Rennauswahl (~02:08) bricht der dichte Klangteppich abrupt ab. Die Menüszene danach ist deutlich leiser und enthält wieder einzelne Sweeps.

**KI-gestützte Beschreibung:** Musikstil, Instrumente, Stimmung und Effekte je Szene stehen in [KLANG_STECKBRIEFE.md](KLANG_STECKBRIEFE.md). Kurzfassung: Die Menüs verwenden melancholisches Solo-Klavier und Streicher (d-Moll/F-Dur). Ergebnisse werden mit synthetisch-orchestraler Fanfare bzw. Cello untermalt. Im Rennen dominieren Motor, Turbo und Reifen, darunter liegt wahrscheinlich leise elektronische Musik.

### 9.2 Hörstellen

Die folgenden Ausschnitte wurden aus der tatsächlichen Audiospur erzeugt. Ihre Benennung beschreibt die sichtbare Szene. Die Hörprüfung durch einen Menschen steht weiterhin aus.

| Szene | Videoposition | Hördatei | Zu prüfende Aspekte |
|---|---|---|---|
| Menü und Auswahl | 00:15–00:33 | [Audio](reference/audio_menu.mp3) | Musik, Klicks, Übergänge |
| Start und erstes Oval | 01:25–01:39 | [Audio](reference/audio_start_oval.mp3) | Countdown, Startsignal, Motoranstieg |
| Rennen mit Turbo-HUD | 05:25–05:49 | [Audio](reference/audio_turbo.mp3) | Motor, Reifen, möglicher Turboeffekt |
| Ergebnis und Belohnung | 01:53–02:07 | [Audio](reference/audio_ergebnis.mp3) | Ergebnisakzent, Freischaltung, Musikwechsel |
| Schneestrecke | 12:52–13:12 | [Audio](reference/audio_schnee.mp3) | Untergrund, Rutschen, Fahrzeugcharakter |

Eine menschliche Hörprüfung kann die KI-Beschreibungen bestätigen oder korrigieren. Die Messwerte aus 9.1 gelten unabhängig davon. Das [Soundkonzept](RICHTLINIEN.md#7-soundentwurf) ist ein Vorschlag für das neue Spiel.

## 10. Nicht durch diese Referenz beantwortet

- Vollständige Strecken-/Fahrzeugliste und alle Karriereklassen.
- Sondermodi wie die auf einer Eventkarte erwähnte Ballon-Herausforderung.
- Mehrspieler, Freundesrennen, echte Online-Ranglisten und deren technische Regeln.
- Exakte Reifenphysik, KI, Kollisionsbehandlung, Gelände-/Sprungphysik.
- Alle Sonderfälle der Touchbedienung und die Zuordnung jedes Symbols.
- Einstellungen, Barrierefreiheit, Cloud-Spielstand, Kaufablauf.
- Ob im Rennen tatsächlich Musik läuft (nur schwach belegt); Ursache der kurzen Klicks im Rennen und des Brummtons bei Szenenwechseln.

Diese Punkte sind Optionen bzw. offene Fragen, keine stillschweigenden Anforderungen an den ersten Prototyp.
