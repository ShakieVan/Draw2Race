# Draw2Race — Spiel- und Gestaltungsrichtlinien

Stand: 24.09.2026. Arbeitsentwurf auf Basis der [Videoanalyse](REFERENZANALYSE.md). Diese Richtlinien beschreiben das vorgeschlagene neue Spiel; sie sind keine Rekonstruktion des unbekannten Originalcodes.

## 1. Ziel und Prioritäten

Draw2Race soll das Vergnügen am Planen, Beobachten und Verbessern einer Rennlinie wiederbringen. Ein guter Versuch belohnt vorausschauendes Bremsen, einen passenden Kurvenradius und gezieltes Beschleunigen. Ein Fehler muss an der Fahrt erkennbar sein.

Priorität bei Zielkonflikten:

1. Nachvollziehbares Fahrgefühl und unmittelbare Touchreaktion.
2. Gut lesbare Strecke, Linie, Autos und Rennsituation.
3. Schneller Wechsel zwischen Versuch, Ergebnis und erneutem Zeichnen.
4. Stimmige Kamera, Geräusche und visuelles Feedback.
5. Umfang an Strecken, Autos und Modi.

Vom Nutzer festgelegt: **Android**, **Projektname Draw2Race**, **Zeichnen innerhalb der Strecke**, **Zeichentempo beeinflusst die Fahrt**, **Physik mit Bremsweg/Ausbrechen**. Die zusätzliche Ausgestaltung ist zunächst ein Vorschlag.

## 2. Spielablauf und Touchregeln

Der Standardablauf lautet `Auswahl → Zeichnen → Countdown → Rennen → Ergebnis`. Der Prototyp verwendet zwei vorab gezeichnete Runden, später wird die Rundenzahl pro Event konfiguriert.

- Startpunkt und Fahrtrichtung sind eindeutig markiert. Eine Linie beginnt nur am Startbereich.
- Das Spiel gibt sofort sichtbare Rückmeldung auf die Bewegung. Geometrische Glättung darf bewusste Bremspunkte nicht entfernen.
- Die aktuelle Runde ist deutlich, die vorherige Runde nur schwach sichtbar.
- **Verbindliche Nutzerpräzisierung (24.09.2026): Langsam = breite, helle Linie; schnell = schmale, rote Linie.** Farbe und Breite bilden dieselbe lokale Tempovorgabe kontinuierlich ab. Für Draw2Race verläuft die Farbskala von hellem Gelb bis kräftigem Rot; die langsame Linie ist gut dreimal so breit wie die schnelle. Farbe ist nie die einzige Information. Eine grafische Legende steht direkt in der Zeichenansicht, die Fahrhilfe erklärt sie.
- Tempoaufbau/Beschleunigungsabsicht wird als Übergang zu schmaler und röter sichtbar, Bremsabsicht als Übergang zu breiter und heller. Die Linie zeigt die **geplante Vorgabe**, nicht die bereits erreichte Fahrzeuggeschwindigkeit oder eine zusätzliche unabhängige Beschleunigungssteuerung. Tatsächliche Beschleunigung und Bremsung entstehen weiterhin durch die begrenzten Fahrzeugkräfte.
- Menüflächen und Turbo dürfen nicht versehentlich als Streckeneingabe zählen.
- Ein zweiter Finger übernimmt keine aktive Zeichenlinie.
- Es gibt einen erreichbaren Befehl zum Neuzeichnen.

**Vorgeschlagene Sonderfallregeln für den ersten Prototyp:**

| Situation | Verhalten |
|---|---|
| Finger hebt während einer Runde ab | Zeichnen pausiert; Fortsetzen am sichtbaren Endpunkt, Pausezeit zählt nicht als Bremsvorgabe |
| Finger bleibt auf dem Bildschirm stehen | Aktive Verweilzeit wird als sehr niedrige Tempovorgabe erfasst; Untergrenze und Wirkung werden spielerisch abgestimmt |
| Finger verlässt die Strecke | Ungültigen Abschnitt sichtbar markieren und keine Abkürzung übernehmen; Fortsetzen am letzten gültigen Endpunkt |
| Zwei gültige Punkte liegen beiderseits eines Innenbereichs | Das verbindende Segment ebenfalls auf Gültigkeit prüfen, nicht nur seine Endpunkte |
| Falsche Richtung oder ausgelassener Streckenteil | Runde erst bei vollständiger, geordneter Durchfahrt der Streckenabschnitte gültig |
| App verliert den Fokus | Zeichen-/Rennzustand pausieren; keine Eingabe- oder Rennzeit aus der Unterbrechung addieren |
| Linie kreuzt nach Runde eins die Startlinie | Zweite Runde weiterzeichnen; kein vorzeitiger Rennstart |

Diese Regeln sind eine bewusste Ausgestaltung. Das Video zeigt die meisten Sonderfälle nicht. Großzügige Touch-Toleranz und gültige Fahrbahn müssen getrennt behandelt werden: Der Finger darf leicht ungenau sein, aber nicht über Inseln oder Haarnadeln abkürzen.

## 3. Fahrzeug und Physik

Die Linie liefert **gewünschte Route und Tempoprofil**. Ein Fahrregler erzeugt daraus begrenzte Lenk-, Gas- und Bremsbefehle. Nur die Simulation bestimmt die tatsächliche Position, Geschwindigkeit und Ausrichtung.

- Beschleunigung und Bremskraft sind begrenzt. Eine langsam gezeichnete Stelle setzt die aktuelle Geschwindigkeit nicht sofort herab.
- Der Regler darf eine riskant gezeichnete Kurve nicht durch perfekte automatische Ideallinienplanung entschärfen.
- Vorder- und Hinterachse benötigen unterscheidbare Haftungsgrenzen, damit Unter- und Übersteuern plausibel entstehen können.
- Längs- und Seitenkräfte teilen sich die verfügbare Haftung. Starkes Bremsen oder Beschleunigen beeinflusst die Kurvenreserve.
- Querbewegung und Drehbewegung werden simuliert. Ein optisches Schrägstellen allein erfüllt die Anforderung nicht.
- Nach einem Ausbruch orientiert sich der Regler am fortlaufenden Streckenabschnitt. Er darf nicht zum räumlich nächsten Abschnitt einer benachbarten Kehre springen.
- Rutschen muss zunächst kontrollierbar und verständlich sein; extremes Überziehen darf stärker bestraft werden.
- Ein Neustart stellt einen definierten Ausgangszustand wieder her. Keine zufälligen Gripänderungen zur künstlichen Spannung.

Das Ziel ist eine zugängliche, physikalisch nachvollziehbare Fahrweise. Die erste Version braucht weder ein vollständiges Reifenlabor noch Getriebe-/Fahrwerksdetails. Unterschiedliche Fahrzeuge sollen später tatsächlich anders fahren, nicht nur andere Balken besitzen.

## 4. Turbo, Gegner und Rennauswertung

**Turbo-Vorschlag:** Ein großer Knopf im Rennen. Halten verbraucht Ladung und erzeugt zusätzliche Antriebskraft; Loslassen beendet den Einsatz. Aufladen erfolgt bei wirksamem Bremsen aus Bewegung. Die konkreten Werte bleiben abstimmbar. Dieses Halteverhalten ist eine Designentscheidung, nicht aus dem Video bewiesen.

Aufladen im Stillstand sowie schnelles Gas-/Bremswechseln als unbegrenzte Energiequelle müssen verhindert werden. Turbo hebt Haftungsgrenzen nicht auf. Ein zu früher Einsatz in einer Kurve darf Zeit kosten. Eine optionale Position links unterstützt Linkshänder.

**Gegner-Vorschlag:** Eigene Linien, Bremspunkte und Turboentscheidungen innerhalb derselben Fahrzeuggrenzen. Für frühe Versuche reicht ein Gegner; später werden die Eventstufen mit einem, zwei und drei Gegnern aufgebaut. Physische Fahrzeugkontakte sind ein separat zu prüfender Ausbau. Ein transparentes Geistfahrzeug für persönliche Bestzeiten wird als solches gekennzeichnet.

**Ranking-Vorschlag:**

- Im Rennen zählt geordneter Streckenfortschritt einschließlich Rundenzahl, nicht die Luftlinie zum Ziel.
- Nach Zieleinlauf zählt die ungerundete Rennzeit. Millisekundenanzeige erst nach der Sortierung formatieren.
- Der Übertritt der Ziellinie wird innerhalb des Simulationsschritts interpoliert.
- Exakt gleiche interne Zeiten erhalten dieselbe sportliche Platzierung; stabile Anzeige-Reihenfolge ist kein versteckter Siegentscheid.
- Eventfortschritt und Platzierungsmedaille werden getrennt gespeichert.
- Eine Eventstufe vergibt ihren Gold-Erfolg nur einmal. Wiederholte Siege vervielfachen keine Freischaltpunkte.
- Bestzeiten gehören zu Strecke, Fahrzeug, Eventregeln und Physikversion. Änderungen an diesen Grundlagen können getrennte Bestenlisten benötigen.

Lokale Ergebnisse und persönliche Rekorde sind die erste Ausbaustufe. Online-Ranglisten und Freundesrennen sind später eigenständige Funktionen.

## 5. Grafik und Oberfläche

Zielbild: eine kompakte, detailreiche 3D-Rennwelt aus erhöhter Ansicht. Vier Grundthemen sind naheliegend: helles Stadion, beleuchtetes Oval, grüne Straßenanlage und Winterstrecke. Layouts und Gestaltung werden für Draw2Race neu entwickelt.

- Die Fahrbahn bleibt gegenüber Dekoration deutlich erkennbar. Innen-/Außenrand, Fahrtrichtung und Start/Ziel brauchen klare Kontraste.
- Umgebungsdetails geben Maßstab und Charakter: Curbs, Reifenstapel, Geländer, Tribünen, Bäume, Wasser, Beleuchtung und markante Gebäude.
- Große Objekte dürfen aus der Spielkamera keine kritischen Kurven oder Autos verdecken. Bei Bedarf werden verdeckende Teile ausgeblendet.
- Autos erhalten erkennbare Silhouetten und unterscheidbare Farben. Spielerkennzeichnung zusätzlich durch ein dezentes Symbol oder Kontur.
- **Nutzerpräzisierung (24.09.2026): Reifen-/Untergrundspuren und Brems-/Abriebspuren gehören zur Darstellung.** Auf Erde, Dreck und Matsch hinterlassen rollende Reifen untergrundfarbene Profilspuren auch ohne Bremsen. Verschmutzte Reifen tragen Schmutz ein Stück auf Asphalt weiter; die Spur wird mit gefahrenem Weg schwächer. Starkes Bremsen und seitlicher Schlupf erzeugen dunklen Reifenabrieb auf Asphalt, abhängig von der Intensität. Normales sauberes Rollen erzeugt dort keinen permanenten schwarzen Strich.
- Spuren folgen den tatsächlichen Radpositionen, nicht der gemalten Fahrlinie. Stillstand, Pause und Positionssprünge erzeugen keine neuen Verbindungsstriche. Alte Spuren verblassen; Anzahl und Lebensdauer bleiben begrenzt. Ein Neustart setzt Spuren und Reifenverschmutzung zurück. Die Darstellung darf das Simulationsergebnis nicht verändern.
- Staub, Schnee und Rauch ergänzen das Zustandsfeedback später. Keine dauerhafte Effektwand über der Linie.
- Die Zeichenspur liegt leicht über der Fahrbahn und darf nicht durch Tiefenflimmern verschwinden.
- Referenzbilder und Tonfragmente bleiben Analyseunterlagen; Produktionsgrafik und Produktionsaudio werden separat erstellt oder bezogen.

**UI-Richtung:** Die klare Hierarchie aus hellem Hintergrund, kräftigem Aktionsakzent und großen Bedienelementen kann übernommen werden. Als erster Entwurf eignen sich warmes Hellgrau, dunkle Schrift, ein roter/oranger Akzent und Gold für Erfolge. Die genaue Palette und das Draw2Race-Logo sind noch offen.

Menüs verwenden wiedererkennbare Strecken-/Autokarten, sichtbaren Fortschritt und lesbare Freischaltbedingungen. Im Rennen bleibt das HUD sparsam. Neustart und Weiter sind im Ergebnis direkt erreichbar. Ein Einstellungenbereich enthält mindestens Musik, Effekte und Kamerabewegung; die Existenz dieser Optionen im Original ist nicht belegt.

Querformat mit anpassungsfähigem Layout ist die Arbeitsannahme. UI und Streckenansicht müssen verschiedene Handy- und Tabletformate sowie Displayausschnitte berücksichtigen. Die schwarzen Ränder des Referenzvideos werden nicht nachgebaut.

## 6. Kamera

Vier Zustände, jeweils mit eigener Aufgabe:

| Zustand | Aufgabe | Leitplanke |
|---|---|---|
| Zeichenübersicht | Ganze relevante Strecke und Startbereich zeigen | Während aktiver Eingabe zunächst stabil; keine unkontrollierte Bewegung unter dem Finger |
| Startübergang | Zur Startgruppe heranfahren | Weicher Übergang während des Countdowns, keine Eingaben mehr übernehmen |
| Rennen | Spieler und nächste Kurve lesbar halten | Gedämpft folgen, begrenzt vorausblicken, Zoom und Rotation begrenzen |
| Ergebnis | Orientierung zur Strecke erhalten | Ruhiger Ausschnitt, klare Priorität der Ergebnistafel |

Als abstimmbare Startwerte eignen sich etwa eine halbe bis eine Sekunde für den Übergang und eine eher hohe Ansicht. Das sind Vorschläge, keine am Video gemessenen Originalwerte. Winkel, Abstand, Blickvorlauf und Dämpfung werden in Konfigurationsdaten gehalten.

Der Blickvorlauf soll sich an Strecke und tatsächlicher Bewegung orientieren. Ein Dreher darf nicht dazu führen, dass die Kamera abrupt mitrotiert. Ein entfernter Gegner darf den Spieler nicht aus dem Bild ziehen. Zoomwechsel sollten nicht ständig pumpen. Ein ruhiger Modus begrenzt Rotation und dynamischen Zoom.

Wenn später eine bewegte Zeichenansicht eingeführt wird, muss jede Fingerprobe mit der zum Aufnahmezeitpunkt gültigen Kamera in Streckenkoordinaten umgerechnet werden. Kamerabewegung darf kein künstliches Zeichentempo erzeugen.

## 7. Soundentwurf

**Status: vorgeschlagene Klangfunktionen.** Seit dem 26.09.2026 durch eine [messtechnische Referenzauswertung](REFERENZANALYSE.md#9-ton) gestützt, aber noch nicht durch einen Hörvergleich. Aus der Messung stammen: eine Startsequenz aus vier kurzen Tönen und einem langen, eine Oktave höheren Startton; ein Motorton, der der Fahrgeschwindigkeit in mäßigem Tonhöhenbereich folgt; Rutschgeräusche in Kurven, die vom Untergrund abhängen. Draw2Race erstellt dafür eigene Klänge und übernimmt keine Originalfrequenzen als Vorgabe. Stilvorgaben für Musik und Effekte stehen in [KLANG_STECKBRIEFE.md](KLANG_STECKBRIEFE.md).

| Funktion | Vorgeschlagene Umsetzung | Zweck |
|---|---|---|
| Motor | Mehrere Last-/Drehzahlbereiche weich mischen | Beschleunigen, Rollen und Bremsen akustisch unterscheiden |
| Reifen | Intensität abhängig von Schlupf und Untergrund | Haftungsgrenze und Querbewegung verständlich machen |
| Turbo | Kurzer, klarer Zusatzklang während des Einsatzes | Aktivierung und Ende erkennbar machen |
| Countdown | Klar unterscheidbare Startsignale | Aufmerksamkeit auf den Rennbeginn lenken |
| Kontakt | Aufprallstärke und Material berücksichtigen | Kollisionen statt bloßer Nähe melden |
| Menüs | Zurückhaltende Klick-/Bestätigungsgeräusche | Aktionen bestätigen |
| Sieg/Freischaltung | Kurzer positiver Akzent | Fortschritt belohnen, Neustart nicht verzögern |
| Musik | Eigene Menü-/Rennmischung mit moderatem Pegel | Stimmung, ohne Fahrzeugfeedback zu verdecken |

Motorgeräusche basieren auf simuliertem Fahrzeugzustand, nicht direkt auf Fingergeschwindigkeit. Der Spielerwagen bleibt hörbar, mehrere Gegner dürfen die Mischung nicht überladen. Musik und Effekte sind getrennt regelbar; Pause und Fokusverlust müssen alle Loops sauber behandeln.

## 8. Technische Leitplanken und Dokumentation

- Eigene Namen, Daten und Assets verwenden; das Original ist eine Verhaltens- und Stilreferenz.
- Beobachtungen mit Zeitmarke dokumentieren. Annahmen und neue Entscheidungen ausdrücklich benennen.
- Simulation, Eingabeaufbereitung, Kamera, Oberfläche, Fortschritt und Audio getrennt halten.
- Fester Simulationszeitschritt, von der Bildausgabe unabhängig. Änderungen an Bildrate oder Kamera dürfen das Ergebnis nicht verändern.
- Die vollständige Originalsimulation ist unbekannt. Reproduzierbarkeit der eigenen Simulation wird gemessen, nicht einfach vorausgesetzt.
- Karten, Fahrzeuge, Oberflächen und Eventregeln sollen datengetrieben sein.
- Android früh auf einem echten Gerät prüfen, besonders Touch, Pause/Fortsetzen, Bildformat und thermische Dauerlast.
- Eine komplette Runde bleibt ohne Netzwerk spielbar. Serverfunktionen dürfen später nicht zur Voraussetzung des Grundspiels werden.
- Vor größerer Inhaltsproduktion müssen Zeichengefühl, Kurvenverhalten und Neustartablauf überzeugen.

## 9. Fachliche Abnahme des Fahrgefühls

Eine gemeinsame Spielprobe sollte diese Situationen nachvollziehbar unterscheiden:

1. Gleiche Linie langsam und schnell gezeichnet → erkennbar anderes Tempoprofil.
2. Frühes Bremsen vor der Kurve → kontrollierter Kurveneingang.
3. Spätes Bremsen → weiterer Radius oder Rutschen mit Zeitverlust.
4. Engere gegen weitere Kurvenlinie → echter Unterschied im fahrbaren Tempo.
5. Turbo am Kurvenausgang → nützlich; Turbo bei ausgeschöpfter Haftung → riskant.
6. Gleiche Eingabe wiederholt → vergleichbares Ergebnis im selben Build.
7. Neustart nach einer Niederlage → unmittelbar wieder verständliches Zeichnen.

Diese Prüfung entscheidet über die nächste Ausbaustufe. Eine hübsche Streckenszene allein erfüllt den Meilenstein nicht.
