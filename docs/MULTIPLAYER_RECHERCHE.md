# Draw2Race – Lokaler Mehrspieler: Recherche und Empfehlung

Stand: 03.10.2026, korrigiert am 04.10.2026 (Hotspot-Adressen in 4.2). Status: **umgesetzt** in den Versionen 0.2.29 bis 1.0.0: M0 bis M5 samt „Weitergeben“ (M2b); Wertung, Revanche und Abbrüche sind in M3 bis M5 aufgegangen. Offen sind der Feldtest mit vier Handys (M7) und die Komfortstufe M8 (LocalOnlyHotspot, QR-Code). Was tatsächlich gebaut, getestet und anders als geplant gelöst wurde, steht in `docs/IMPLEMENTIERUNG.md`. Dieses Dokument bleibt die Recherche- und Entscheidungsgrundlage. Grundlage der Recherche waren der Code von Version 0.2.28, die Android- und Godot-Dokumentation sowie Erfahrungsberichte (Quellen in Abschnitt 11).

So sind die Aussagen gekennzeichnet:

- **[belegt]**: in offizieller Dokumentation oder im Code nachgeprüft.
- **[Bericht]**: nur aus Foren, Erfahrungsberichten oder Fachartikeln.
- **[ungeprüft]**: plausibel, aber nicht nachgewiesen.
- **[Gerätetest]**: lässt sich nur auf echten Handys klären.

---

## 1. Kurzfassung

**Deine Idee funktioniert.** Ein Handy schaltet den WLAN-Hotspot ein und ist der Gastgeber („Host“). Bis zu drei weitere Handys verbinden sich mit diesem WLAN und finden das Spiel automatisch. Ein Internetzugang ist dafür nicht nötig. Dasselbe Programm funktioniert auch, wenn alle im gleichen Heim-WLAN sind.

**Empfehlung:**

| | Weg | Wann |
|---|---|---|
| **Hauptweg** | Normaler Handy-Hotspot des Hosts oder gemeinsames WLAN; Verbindung über Godots eingebautes Netzwerkmodul (ENet); das Spiel findet den Host selbst | immer |
| **Rückfall** | Host-Adresse von Hand eintippen (steht groß in der Lobby des Hosts) | wenn die automatische Suche auf einem Gerät nicht klappt |
| **Komfort (später)** | Das Spiel öffnet selbst ein WLAN („LocalOnlyHotspot“) und zeigt einen QR-Code; die Mitspieler scannen ihn | wenn sich der Hauptweg im Alltag bewährt hat |
| **Nicht empfohlen** | Wi-Fi Direct, Bluetooth, Google Nearby | zu viel Aufwand, zu viele Gerätefehler oder Abhängigkeit von Google |

**Was synchronisiert werden muss, ist etwas mehr als vermutet.** Zeichenstart und Rennstart reichen nicht ganz, denn während des Rennens gibt es eine Live-Eingabe: den **Turbo-Knopf**. Am robustesten ist deshalb:

- **Der Host ist der Schiedsrichter.** Er rechnet das Rennen für alle Autos (wie heute schon für die KI-Gegner).
- **Die anderen Handys bekommen 30-mal pro Sekunde den Stand aller Autos** und zeigen ihn an.
- Die Mitspieler schicken ihre gezeichnete Linie einmal vorab und während des Rennens nur ihre Turbo-Drücke.

Ein kleiner Ping ist dabei tatsächlich unwichtig. Eine feste Verzögerung von etwa 0,1 s ist für alle gleich und fällt kaum auf.

**Wichtigste Stolperstelle:** Haben die Mitspieler **mobile Daten an**, schickt Android Verbindungen oft am Hotspot vorbei ins Mobilnetz, weil der Hotspot „kein Internet“ hat. Dagegen gibt es eine Programmlösung. Bis sie getestet ist, hilft eine einfache Regel: **Bei den Mitspielern mobile Daten aus.**

**Spielernamen und Sprechblasen** sind gut machbar. Jedes Auto bekommt ein kleines Namensschild in seiner Farbe. Bei Ereignissen erscheinen kurze Blasen, etwa „Überholt!“, „Dreher!“ oder „Turbo!“. Dazu kommen optional vorgefertigte Sprüche. Alles lässt sich abschalten.

**Aufwand:** etwa **13–20 Entwicklertage** bis zum Feldtest mit vier Handys (Abschnitt 7). Möglicher erster Schritt ohne Netzwerk: ein **„Weitergeben“-Modus auf einem Handy**. Die Spieler zeichnen nacheinander, dann fahren alle gemeinsam. Der Umbau dafür wird für das Netzwerkspiel ohnehin gebraucht.

---

## 2. Was die Spieler tun müssen (geplanter Ablauf)

### Variante A: Unterwegs, ohne Router (Handy-Hotspot)

**Host (ein Handy):**

1. Von oben wischen und in den Schnelleinstellungen **„Hotspot“** einschalten. Mobile Daten dürfen dabei aus sein; der Hotspot hat dann eben kein Internet.
2. Draw2Race öffnen → **Mehrspieler → Gastgeber**. Die Lobby zeigt den Namen des Hotspots und eine Adresse, z. B. `192.168.97.1`.

**Mitspieler (bis zu 3 Handys):**

1. **Mobile Daten ausschalten** (oder Flugmodus an und danach WLAN wieder an).
2. In den WLAN-Einstellungen den Hotspot des Hosts wählen und das Passwort eingeben. Viele Handys zeigen in den Hotspot-Einstellungen auch einen QR-Code zum Teilen **[ungeprüft für alle Hersteller]**.
3. Fragt Android „Dieses Netzwerk hat keinen Internetzugang – verbunden bleiben?“, mit **Ja** antworten.
4. Draw2Race → **Mehrspieler → Mitspielen**. Der Host erscheint automatisch in der Liste. Falls nicht: **„Adresse eingeben“** und die Adresse aus der Lobby des Hosts eintippen.

**Alle:** Namen und Auto wählen und auf **„Bereit“** tippen. Den Rest steuert der Host (Abschnitt 5.2).

### Variante B: Zu Hause im gleichen WLAN

Alle sind schon im selben WLAN. Einer tippt **Gastgeber**, die anderen **Mitspielen**. Mehr ist nicht nötig. Ausnahme sind Gast- oder Hotel-WLANs: Dort sperrt der Router oft den Verkehr zwischen Geräten. Dann Variante A nehmen.

### Vorher zu Hause erledigen

- **Alle auf dieselbe Draw2Race-Version bringen.** Unterwegs ohne Internet geht das Update nicht. Die Lobby lehnt abweichende Versionen mit einem klaren Hinweis ab.
- Bei Pixel-Handys ab Android 14 den Hotspot unter „Geschwindigkeit und Kompatibilität“ nicht auf „nur 6 GHz“ stellen, sonst sehen ältere Handys ihn nicht **[Bericht]**.

---

## 3. Die Möglichkeiten im Vergleich

| Weg | Was die Spieler tun | Geräte | Berechtigungen / Dialoge | Passt zu Godot | Aufwand | Hauptrisiken | Bewertung |
|---|---|---|---|---|---|---|---|
| **(a) Normaler Handy-Hotspot** | Host schaltet den Hotspot ein, die anderen wählen das WLAN | laut Google bis zu 10 **[belegt]** | keine Dialoge; nur normale Berechtigungen | ideal (ENet über WLAN) | 2–3 Tage für die Verbindungsschicht | mobile Daten der Mitspieler (4.3); manche Anbieter oder Geräte sperren Tethering **[belegt: Google-Hilfe]**; ohne SIM teils kein Hotspot **[Gerätetest]** | **Empfohlen** |
| **(e) Gemeinsames WLAN / Router** | nichts, alle sind schon drin | praktisch unbegrenzt | keine | ideal, gleicher Code wie (a) | 0 zusätzlich | Gast-WLANs mit Geräte-Isolierung; Router, die Broadcasts filtern | **Empfohlen** (gleichwertig) |
| **(b) LocalOnlyHotspot** (das Spiel öffnet selbst ein WLAN) | Host tippt „Gastgeber“, die anderen scannen einen QR-Code | nicht dokumentiert, für 4 unkritisch **[ungeprüft]** | Laufzeitdialog „Geräte in der Nähe“ (Android 13+) bzw. Standort (bis Android 12) **[belegt]** | danach wie (a) | +2–3 Tage (Java-Helfer, QR, Tests) | geht nicht, solange der normale Hotspot läuft; System kann ihn beenden; ab Android 8 | **Später als Komfort** |
| **(c) Wi-Fi Direct** | Gerätesuche und Einladungen annehmen | mehrere Clients je Gruppe | Standort bzw. „Geräte in der Nähe“, Standortdienste an | danach ENet möglich | 3–5 Tage, viel Java | langsamer, launischer Verbindungsaufbau; große Gerätevielfalt | **Nicht empfohlen** |
| **(d) Google Nearby Connections** | Suchen, beide Seiten bestätigen | Stern 1:N, Zahl nicht dokumentiert **[belegt: Strategie-Doku]** | viele Bluetooth- und WLAN-Laufzeitberechtigungen | schlecht: keine IP-Verbindung, eigene Netzschicht nötig | 3–5+ Tage | braucht Google-Play-Dienste (nicht auf Huawei / Handys ohne Google); proprietär im offenen Projekt | **Nur Plan C** |
| **(f) Bluetooth** | Koppeln, Verbindungen annehmen | klassisch höchstens 7 aktive Partner (Piconetz-Grenze, Grundwissen) | Bluetooth-Laufzeitberechtigungen (Android 12+) | schlecht: keine IP, eigenes Protokoll | 4–6 Tage | mehrere gleichzeitige Verbindungen auf Android oft wackelig **[Bericht]** | **Nicht empfohlen** |
| **(g) „Weitergeben“ auf einem Handy** | nacheinander zeichnen, gemeinsam zuschauen | 2–4 Spieler, 1 Gerät | keine | kein Netzwerk nötig | 2–3 Tage (Umbau, der ohnehin nötig ist) | nur ein Bildschirm; Turbo nur für den „aktuellen“ Spieler sinnvoll | **Guter Zwischenschritt** |

Zum Vergleich ist das Datenvolumen winzig. Eine gezeichnete Linie (2 Runden) hat roh **18–66 KB**, komprimiert deutlich weniger. Während des Rennens fließen etwa **6 KB/s pro Mitspieler**, insgesamt rund **0,15 Mbit/s**. Jedes WLAN schafft das spielend, auch ein schwacher 2,4-GHz-Hotspot.

---

## 4. Technik der Verbindung (für Entwickler)

### 4.1 Grundlage: Godot ENet

- **Host:** `ENetMultiplayerPeer.create_server(port, 3)`. **Mitspieler:** `create_client(ip, port)` **[belegt: Godot-Doku]**. Ein fester UDP-Port, z. B. 24680.
- Nachrichten laufen als RPCs:
  - `reliable` für Lobby, Linien, Startbefehle, Ereignisse und Ergebnisse.
  - `unreliable_ordered` auf einem eigenen Kanal für die Schnappschüsse **[belegt]**.
- `MultiplayerSpawner` und `MultiplayerSynchronizer` braucht es nicht. Die Autos entstehen auf jedem Gerät lokal aus dem Renn-Setup.
- **Sicherheit:** Beim Entpacken der Daten keine Objekte zulassen (`allow_object_decoding` bleibt aus). Empfangene Linien auf Größe, Länge und gültige Werte prüfen.

### 4.2 Den Host finden

Godot hat **keine eingebaute LAN-Suche** **[belegt: Doku nennt nur manuelle IP]**. Die Adresse des Hosts ist auch nicht fest. Laut AOSP-Quelltext (`IpServer`, `PrivateAddressCoordinator`, Quellen in Abschnitt 11) gilt **[belegt: Quelltext; Korrektur 04.10.2026]**:

- **Bis Android 10:** fest `192.168.43.1`.
- **Android 11:** bei jedem Einschalten ein zufälliges Netz `192.168.x.0/24`. Nur hierfür stimmte die frühere Aussage „zufällig bei jedem Start“.
- **Ab Android 12:** Android merkt sich die letzte Adresse je Schnittstellenart (WLAN-Hotspot, USB, Bluetooth …) und vergibt sie beim nächsten Einschalten wieder, solange sie nicht mit dem Netz kollidiert, über das das Handy selbst online ist. Gemerkt wird nur im Arbeitsspeicher; nach einem Neustart oder bei einem Konflikt wird neu gewählt. Gesucht wird zuerst in `192.168.0.0/16`, danach in `172.16.0.0/12` und `10.0.0.0/8`. Unter Android 12 hängen die beiden zusätzlichen Bereiche an einem Schalter, der ab Werk an ist (`tether_enable_select_all_prefix_ranges`), ab Android 13 gehören sie fest dazu.
- **Neuere Fassungen (im Quelltext von Android 15):** Ein weiterer Schalter (`tether_force_random_prefix_base_selection`) lässt auch den Bereich zufällig wählen, dann landet der Hotspot meist in `10.x`. Ob er auf den Geräten aktiv ist, ist **[ungeprüft]**.
- **Gemessen:** S21 mit Android 15 `172.17.251.0/24`, S24 mit Android 16 `10.110.43.x` **[Gerätetest]**.
- Das Tethering ist seit Android 11 ein Mainline-Modul, das Google über Systemupdates austauscht, und Hersteller können eigene Regeln haben. Das Verhalten hängt also nicht allein von der Android-Version ab **[ungeprüft je Gerät]**.

Für das Spiel heißt das: Die Adresse kann wechseln, spätestens nach einem Neustart, und liegt nicht unbedingt in `192.168.x`. Darum dreistufig:

1. **Rundruf (UDP-Broadcast):** Mitspieler rufen „Wer ist Host?“, der Host antwortet und kündigt sich zusätzlich jede Sekunde selbst an. Das geht in Godot mit `PacketPeerUDP.set_broadcast_enabled(true)`.
   - Godot holt sich auf Android dafür automatisch den nötigen „Multicast-Lock“. Manche Geräte brauchen dazu die Berechtigung `CHANGE_WIFI_MULTICAST_STATE`, sonst kommen Rundrufe nicht an **[belegt: Godot-Doku, PR #33910]**.
2. **„Der Host ist das Gateway“:** Im Hotspot ist der Host zugleich der WLAN-Router der anderen. Ein kleiner Java-Helfer liest die Gateway-Adresse des WLANs, das Spiel fragt dort direkt nach. Das klappt auch dann, wenn ein Gerät Rundrufe verschluckt. Im Heim-WLAN hilft es nicht, weil dort der Router das Gateway ist.
3. **Adresse eintippen** als letzter Rückfall. Optional zeigt der Host zusätzlich einen QR-Code; ein reines GDScript-Addon dafür gibt es: Kenyoni „QR Code“, MIT, Godot 4.4–4.7 **[belegt]**.

Der Java-Helfer folgt demselben Muster wie der vorhandene Updater: `JavaClassWrapper.wrap("com.godot.game.Updater")` in `game/scripts/updater.gd` **[belegt]**. Ein eigenes Godot-Plugin ist nicht nötig.

### 4.3 Die Stolperstelle „WLAN ohne Internet“

- Android macht ein WLAN erst dann zum Standardnetz, wenn es Internet nachgewiesen hat. Bis dahin bleibt das Mobilnetz Standard, und **neue Verbindungen einer App laufen über das Standardnetz** **[belegt: Android-Doku „Read network state“]**.
- Ein Hotspot ohne Internet wird nie „nachgewiesen“. Hat ein Mitspieler mobile Daten an, landen die Pakete an den Host deshalb sehr wahrscheinlich im Mobilnetz statt im Hotspot. Viele Kamera- und Drohnen-Apps verlangen aus genau diesem Grund „mobile Daten aus“ **[Bericht]**. Wie Android das im Detail routet, ist nicht abschließend geprüft **[Gerätetest]**.
- **Programmlösung:** Für die Dauer der Mehrspieler-Sitzung den App-Prozess an das WLAN binden (`ConnectivityManager.bindProcessToNetwork(wlan)`), danach wieder lösen. Sonst bricht der Update-Download ab, der über das Internet geht.
  - Laut NDK-Doku gilt die Bindung für **alle künftig erzeugten Sockets des Prozesses** **[belegt]**.
  - Dass das auch die Sockets von Godots ENet erfasst, ist sehr plausibel, weil sie im selben Prozess entstehen **[Gerätetest]**.
  - Nach der Bindung erst den ENet-Peer und den Rundruf-Socket anlegen.
- **Ohne Programmlösung:** mobile Daten aus, Flugmodus plus WLAN, oder bei der Android-Frage „verbunden bleiben?“ **Ja** antworten. Ob Letzteres das WLAN zum Standardnetz macht, ist offen **[ungeprüft]**. Teilt der Host seine mobilen Daten, haben alle Internet und das Problem entfällt; das kostet aber Datenvolumen.

### 4.4 Berechtigungen und Android-Versionen

| Berechtigung | Wozu | Art | Heute im Projekt |
|---|---|---|---|
| `INTERNET` | jede Netzwerkverbindung | normal | ja |
| `CHANGE_WIFI_MULTICAST_STATE` | Rundrufe auf manchen Geräten empfangen | normal | nein (Exporteinstellung `permissions/change_wifi_multicast_state`) |
| `ACCESS_NETWORK_STATE` | WLAN-Netz finden, binden, Gateway lesen | normal | nein |
| `ACCESS_WIFI_STATE` | WLAN-Zustand lesen | normal | nein |
| `NEARBY_WIFI_DEVICES` / `ACCESS_FINE_LOCATION` (bis API 32) | nur für den späteren LocalOnlyHotspot | **Laufzeitdialog** | nein |
| `ACCESS_LOCAL_NETWORK` | Pflicht erst bei targetSdk 37 (Android 17) | **Laufzeitdialog** | nein, derzeit nicht nötig |

**Android 17 / lokales Netz:**

- Apps mit **targetSdk 37** brauchen die Laufzeitberechtigung `ACCESS_LOCAL_NETWORK` (Gruppe „Geräte in der Nähe“). Sie gilt für eingehende und ausgehende TCP-Verbindungen, UDP-Unicast, Broadcast, Multicast und mDNS. Ausnahmen für Hotspot oder Wi-Fi Direct nennt die Doku nicht **[belegt]**.
- Apps mit niedrigerem targetSdk behalten den Zugriff über `INTERNET` **[belegt]**.
- Draw2Race hat **targetSdk 35** (`game/android/build/config.gradle`) und ist daher vorerst nicht betroffen. Es wird über GitHub verteilt, nicht über Google Play, also erzwingt keine Store-Regel ein Anheben.
- Ein künftiges Godot-Update kann den Standard-targetSdk aber anheben. Dann muss der Dialog eingebaut werden.

### 4.5 Bonus: Der Windows-Build kann mitspielen

Weil der Host das Rennen allein rechnet (Abschnitt 5), muss kein Gerät bitgenau gleich rechnen. Ein PC mit dem Windows-Build könnte deshalb als Mitspieler oder Host teilnehmen. Der Android-Java-Helfer entfällt dort; die Windows-Firewall fragt beim ersten Start nach. Für Tests am Schreibtisch ist das sehr praktisch: Host am PC, ein Handy als Mitspieler.

---

## 5. Spielablauf und Synchronisation

### 5.1 Warum nicht einfach „alle rechnen selbst“?

Naheliegend wäre: Alle tauschen ihre Linien aus und jedes Handy rechnet das Rennen selbst. Das geht hier aus zwei Gründen nicht zuverlässig.

1. **Der Turbo ist eine Live-Eingabe** (`main.gd:534`). Jedes Gerät müsste in jedem Takt die Turbo-Zustände aller anderen kennen. Dann wäre der Ping doch wieder wichtig.
2. **Gleitkomma-Rechnungen sind zwischen Handys nicht garantiert gleich.**
   - Die Simulation ruft pro Auto und Takt mehrfach Winkelfunktionen wie `sin`, `cos`, `atan2` und `pow` auf (`vehicle.gd`).
   - Diese kommen auf Android aus der Mathebibliothek des Geräts (bionic libm), nicht aus der APK **[belegt: Bionic-Quellcode]**. Welche Funktion genau aus welchem Teil stammt, ist nicht im Einzelnen geprüft.
   - Verschiedene Android-Versionen können daher im letzten Bit abweichen **[ungeprüft, ob es hier vorkommt]**. Durch Rutschen und Zusammenstöße wächst so ein Unterschied an.
   - Godot plant keinen Modus für garantiert gleiche Rechnung: Vorschlag #7128 wurde **„closed as not planned“** **[belegt]**.

**Darum rechnet nur der Host.** Er nutzt dieselbe Simulation wie heute, mit 60 Hz und festem Ablauf; heute rechnet ein Handy bereits 4 Autos. Leitplanke 4 („Darstellung darf das Ergebnis nicht verändern“) bleibt gewahrt, weil die Mitspieler nur anzeigen. Gerechnet wird an genau einer Stelle.

### 5.2 Ablauf eines Mehrspieler-Rennens

```
Lobby ─► Strecke laden ─► Zeichenstart (3-2-1) ─► Zeichnen ─► Linien abgeben ─►
Enthüllung aller Linien ─► Ampel ─► Rennen ─► Ergebnis ─► Revanche / Lobby
```

1. **Lobby**
   - Beim Beitritt prüft der Host Name, App-Version, Protokollversion und Physikversion (`RaceVehicle.VERSION`). Bei Abweichung kommt ein klarer Hinweis.
   - Der Host stellt ein:
     - Strecke
     - Herausforderung bzw. Bedingungen (Wetter, Tageszeit); Debug-Schalter sind im Mehrspieler gesperrt
     - KI auffüllen (0 bis insgesamt 4 Autos)
     - Berührungen an/aus
     - Zeichen-Zeitlimit (aus / 60 / 90 / 120 s)
     - Autos (eigene Freischaltungen / alle frei / alle gleich)
   - Jeder wählt Auto und Farbe und tippt „Bereit“.
2. **Strecke laden:** Alle Geräte laden sofort und melden „geladen“. Erst wenn die Prüfsumme der Streckendatei (`track.file_hash`) überall gleich ist, geht es weiter.
3. **Zeichenstart**
   - Die Uhren werden vorher abgeglichen: 8 Pings; die schnellste Antwort zählt; alle 2 s nachführen.
   - Der Host sendet „Zeichnen startet bei Host-Zeit T“, etwa 3 s in der Zukunft. Alle zählen gleichzeitig 3-2-1.
4. **Zeichnen**
   - Wie lange jemand zeichnet, ändert das Ergebnis nicht; das Tempo kommt aus der Strichgeschwindigkeit. Deshalb wird auf alle gewartet.
   - Mit Zeitlimit wird eine unfertige Linie ab dem letzten Punkt durch eine schwache KI-Linie ergänzt.
   - Wer fertig ist, schickt seine Linie und sieht die Fortschrittsbalken der anderen (Name und %). Die Linien selbst bleiben verdeckt.
   - Neu zeichnen ist erlaubt, bis alle fertig sind.
   - Im Code ist das die Stelle, an der `record_point()` heute sofort `begin_race()` aufruft (`main.gd`, `func record_point`).
5. **Enthüllung:** Für 2–3 s erscheinen alle Linien in den Autofarben. Das macht Spaß und erklärt hinterher, warum wer gewonnen hat. `world.draw_route` muss dafür mehrere Linien zeichnen können.
6. **Ampel**
   - Der Host sendet die Startzeit, die Startaufstellung und die Bedingungen. Alle spielen Ampel und Töne nach der abgeglichenen Uhr, Ziel unter 20 ms Versatz, damit es im Raum nicht „hallt“.
   - Bluetooth-Kopfhörer verzögern den Ton um ein Vielfaches davon; das lässt sich nicht ausgleichen.
   - Startaufstellung 2×2: im ersten Rennen zufällig, danach in umgekehrter Reihenfolge des letzten Ergebnisses.
7. **Rennen:** Der Host rechnet, die Mitspieler zeigen an (5.3–5.4).
8. **Ergebnis**
   - Der Host beendet das Rennen, wenn alle Menschen im Ziel oder ausgeschieden sind, spätestens 30 s nach dem Sieger.
   - Er schickt an alle Rang, Zeit und Status jedes Autos. Danach geht es mit „Revanche“ (gleiche Strecke) oder zurück in die Lobby weiter.

### 5.3 Der Host rechnet: nötige Umbauten

Heute ist an vielen Stellen fest verdrahtet, dass **Auto 0 der Spieler** ist **[belegt]**:

- `vehicles[0]`: 18-mal in `main.gd`, 4-mal in `hud.gd`
- `is_player = index == 0` in `engine_audio.gd`
- „DU“ / „RIVALE n“ in `hud.gd`
- Turbo nur für Index 0 in `race_field.gd`
- Wippen-Entscheidung und Ausweichen nur für Index > 0

Umbau:

- `RaceField.setup()` bekommt eine Teilnehmerliste: Mensch/KI, Linie, Auto, Spur, Name, Farbe.
- `step()` bekommt die Turbo-Zustände aller Autos.
- Ausweichen und Wippen-Wahl gelten nur für KI-Autos. Ein Mensch fährt seine Linie, auch wenn's knallt.
- Überall gibt es einen Index „mein Auto“ statt `0`.
- Der bestehende Einzelspieler muss danach **bitgleich** dieselben Ergebnisse liefern. Die vorhandenen Headless-Tests (`game/tests/`) sichern das ab.

**Turbo der Mitspieler:**

- Der Druck geht mit Taktnummer an den Host. Der Host wendet ihn mit einer festen Verzögerung von etwa 6 Takten (0,1 s) an, für den Host selbst genauso; das ist fair.
- Flamme und Ton erscheinen beim Drückenden sofort (nur Optik). Der nächste Schnappschuss korrigiert das.

**Verbindungsabbruch:**

- Fällt ein Mitspieler aus, fährt sein Auto seine Linie einfach zu Ende; der Host kennt sie ja. Es fährt dann nur ohne Turbo.
- Fällt der Host aus, endet die Runde für alle mit einem Hinweis. Eine Übergabe an einen anderen Host wäre zu aufwendig.

**Pause:** Im Mehrspieler hält niemand das gemeinsame Rennen an. Das Pausemenü bietet nur „Verlassen“. Heute pausiert `pause_game()` bei Fokusverlust; das muss im Mehrspieler entfallen.

### 5.4 Was die Mitspieler anzeigen

- **Schnappschüsse:** 30 pro Sekunde, je Auto rund 36 Byte. Sie enthalten Position, Höhe, Richtung, Tempo, Lenkung, Rutschen, Bremsen, Turbo, Zustände sowie Looping- und Wippenwinkel.
- **Ereignisse** kommen zusätzlich zuverlässig an: Zusammenstöße, Leitplanke, Absturz, Looping, Zieleinlauf mit exakter Zeit und Sprechblasen.
- **Darstellung:**
  - Die Mitspieler führen die normalen Fahrzeug-Objekte als „Marionetten“: Ihre Werte kommen aus einem kleinen Puffer, die Simulation läuft nicht.
  - Die Anzeige ist um etwa 0,1 s verzögert, damit Schwankungen nicht ruckeln.
  - Modelle, Reifenspuren, Motorklang und Kamera lesen dieselben Werte wie bisher und brauchen kaum Änderungen.
- **Option „Gleiche Bilder“** (empfohlen):
  - Auch der Host zeigt sein Rennen mit derselben Verzögerung. Dann laufen alle Bildschirme und Motorgeräusche im Raum gleichzeitig.
  - Es gibt nur einen Darstellungsweg.
  - Nebenbei ist der Schnappschuss-Strom eine fertige **Wiederholung** des Rennens (ca. 0,5 MB je Rennen).

### 5.5 Ergebnisse, Gold und Bestenliste

- **Im Mehrspieler gibt es kein Gold und keinen Eintrag in die Einzelspieler-Bestenliste.** Zusammenstöße mit Menschen verfälschen die Zeiten, und Leitplanke 6 trennt Gold und Platzierung ohnehin.
- Stattdessen gibt es eine eigene kleine Mehrspieler-Statistik je Gerät: Siege, Rennen, beste Zeit je Strecke mit Namen.
- Die Turbo-Zeitleisten schickt der Host mit. Damit lässt sich die Fahrt jedes Spielers später als Geist speichern.

### 5.6 Sonderfälle der Strecken

- **Sprint (Serra-Pass), Looping, Brücken, Wippe:** Das ist alles Fahrzeugbewegung, die der Host ohnehin rechnet. Es braucht keine Sonderbehandlung.
- **Drift-Arena:** Heute fährt dort ein Auto allein (`race_field.gd`). Im Mehrspieler fahren entweder alle gleichzeitig **ohne Berührung** („Geisterfahrt“), oder nacheinander mit Punktevergleich. Das entscheidest du (Abschnitt 9).

---

## 6. Spielernamen und Sprechblasen

**Namen**

- Beim ersten Mehrspielerstart fragt das Spiel nach einem Namen: höchstens 12 Zeichen, Umlaute erlaubt. Er wird im Spielstand gespeichert und ist später in den Einstellungen änderbar.
- Vorschlag ohne Eingabe: „Fahrer 37“ o. Ä.
- Gleiche Namen in einer Lobby bekommen automatisch eine Ziffer.
- Namen ersetzen „DU“ / „RIVALE n“ in Platzierung und Ergebnis. KI-Autos können im Einzelspieler ebenfalls Namen bekommen; das ist optional und auch ohne Netzwerk lustig.

**Namensschilder über den Autos**

- Ein kleines abgerundetes Schild in der Autofarbe schwebt über jedem Auto. Das eigene ist hervorgehoben oder auf Wunsch ausgeblendet.
- **Empfohlen ist die 2D-Variante:** Die Autoposition wird mit der Kamera auf den Bildschirm umgerechnet (`Camera3D.unproject_position`), das Schild wird im HUD gezeichnet. Vorteile:
  - Es bleibt immer gleich groß und lesbar.
  - Ist das Auto außerhalb des Bildes, klebt das Schild am Bildrand mit einem Pfeil.
  - Überlappende Schilder werden gestapelt.
- Die Alternative `Label3D` mit Billboard wird im Projekt schon für Deko benutzt. Sie ist einfacher, überlappt aber leichter und wird beim Herauszoomen klein.

**Dynamische Sprechblasen**

- Sie erscheinen für 1,5–2,5 s mit einem kleinen „Plopp“ und verblassen dann.
- Auslöser sind Ereignisse: „Überholt!“, „Führung!“, „Dreher!“, „Abgeflogen!“, „Turbo!“, „Ziel – Platz 2“. Die Texte erzeugt das Spiel aus Zustandswechseln, die der Host ohnehin meldet.
- **Schnellsprüche (optional):** 6–8 vorgefertigte Sprüche zum Antippen, z. B. „Gleich hab ich dich!“, „Ups“, „GG“. Sie gehen in der Lobby, beim Warten aufs Zeichnen und im Rennen.
  - Kein freier Text, also keine Moderation nötig.
  - Höchstens ein Spruch alle 3 s.
  - Die Sprüche liegen als Datei vor und lassen sich leicht durch eigene ersetzen, auch derbere.
- **Einstellungen:**
  - Namen: aus / nur Mitspieler / alle
  - Sprechblasen: aus / Ereignisse / Ereignisse + Sprüche

Das alles ist reine Darstellung und beeinflusst die Simulation nicht (Leitplanke 4). Namen und Ereignisblasen lassen sich **schon im Einzelspieler** bauen und testen, bevor es ein Netzwerk gibt.

---

## 7. Meilensteine und Aufwand

Aufwand in Entwicklertagen (mit KI-Unterstützung, inklusive Tests). Grobe Schätzung; sie wird nach M0 nachgeschärft.

| Stufe | Inhalt | Aufwand | Fertig, wenn … |
|---|---|---|---|
| **M0 Gerätetest** | Versteckter „Netztest“ im Debug-Menü: Host / Mitspielen, Rundruf, Gateway-Probe, Echo-Ping, mit und ohne mobile Daten, mit `bindProcessToNetwork` | 1 | Auf 2–3 echten Handys (verschiedene Marken/Android-Versionen) ist klar, welche Suche klappt und ob die Bindung das Mobilnetz-Problem löst |
| **M1 Namen und Blasen** | Name im Spielstand, Namensschilder, Ereignisblasen, Einstellungen; KI-Namen optional | 1–2 | Im Einzelspieler sichtbar, abschaltbar, ohne Einfluss auf Ergebnisse |
| **M2 Umbau „mehrere Menschen“** | Teilnehmerliste in `RaceField`, Turbo je Auto, „mein Auto“ statt Index 0, mehrere Linien zeichnen | 2–3 | Einzelspieler-Ergebnisse bitgleich (Headless-Tests grün) |
| **M2b „Weitergeben“ (optional)** | 2–4 Spieler zeichnen nacheinander auf einem Handy, dann gemeinsames Rennen | +1 | Spielbar ohne Netzwerk; erstes Mehrspieler-Gefühl |
| **M3 Lobby und Verbindung** | ENet, Rundruf, Gateway-Probe, manuelle Adresse, Java-Helfer, Versionsprüfung, Lobby-Bildschirm, Berechtigungen | 2–3 | 4 Geräte finden sich im Hotspot und im Heim-WLAN; falsche Version wird abgelehnt |
| **M4 Zeichnen synchron** | Uhrabgleich, gemeinsamer Zeichenstart, Linien senden und prüfen, Fortschritt, Zeitlimit, Enthüllung | 2 | Alle starten gleichzeitig; Linien kommen vollständig an |
| **M5 Rennen** | Host-Simulation, Schnappschüsse, Marionetten, Turbo über Netz, gemeinsame Ampel, Ereignisse | 3–5 | Rennen sieht auf allen Geräten gleich aus; Turbo fühlt sich gut an |
| **M6 Ende und Fehlerfälle** | Ergebnis, Revanche, Abbruch, Host weg, App im Hintergrund, Mehrspieler-Statistik | 1–2 | Kein Gerät „hängt“ nach Abbruch |
| **M7 Feldtest** | Vier Handys, verschiedene Strecken, Feinschliff | 1–2 | Du und deine Mitspieler wollen eine zweite Runde |
| **M8 Komfort (später)** | LocalOnlyHotspot + QR-Code im Spiel | 2–3 | Beitritt ohne Ausflug in die Einstellungen |

**Summe M0–M7: etwa 13–20 Tage**, ohne M2b und M8. Reihenfolge: M0 → M1 → M2 → (M2b) → M3 → M4 → M5 → M6 → M7. M0 kann sofort laufen; M1 und M2 sind auch ohne Netzwerk ein Gewinn.

---

## 8. Risiken

| Risiko | Einschätzung | Gegenmittel |
|---|---|---|
| Mobile Daten lenken Pakete am Hotspot vorbei | wahrscheinlich, je nach Gerät | `bindProcessToNetwork` (in M0 testen); Anleitung „mobile Daten aus“ |
| Rundrufe kommen auf manchen Geräten nicht an | bekannt (Godot-Issue #24666) | Multicast-Berechtigung, Gateway-Probe, manuelle Adresse |
| Hotspot ohne SIM / vom Anbieter gesperrt | gerätespezifisch | Heim-WLAN; anderes Handy als Host; später LocalOnlyHotspot |
| Älteres Handy sieht 6-GHz-Hotspot nicht | bei neueren Pixel-Geräten | Hotspot auf 2,4 GHz / „Kompatibilität erweitern“ |
| Hotspot schaltet sich bei Inaktivität ab | gerätespezifisch | Lobby hält die Verbindung aktiv; Hinweis in der Anleitung |
| Host-Handy wird heiß oder der Akku leert sich schnell (Hotspot + Rechnen + Darstellung) | mittel | Grafikstufe beim Host automatisch senken; Ladekabel |
| Turbo fühlt sich mit 0,1 s Verzögerung träge an | gering bis mittel | Sofortige Optik beim Drücken; Verzögerung im Feldtest abstimmen |
| Bluetooth-Kopfhörer: Ampelton zu spät | sicher, aber nur für diese Person | nicht lösbar; Hinweis |
| App geht in den Hintergrund (Anruf), Verbindung reißt | mittel | Auto fährt die Linie weiter; Wiedereinstieg in die nächste Lobby |
| Unterschiedliche App-Versionen | häufig unterwegs | strikte Versionsprüfung; vorher aktualisieren |
| Künftiges Anheben auf targetSdk 37 | sicher irgendwann | `ACCESS_LOCAL_NETWORK`-Dialog einplanen |
| Umbau „Index 0 = Spieler“ verändert versehentlich den Einzelspieler | mittel | Bitgleichheit per Headless-Test als Bedingung für M2 |

---

## 9. Offene Entscheidungen für dich

1. **Testgeräte:** Wie viele und welche Handys stehen für M0 und den Feldtest bereit (Marke, Android-Version)? Mindestens zwei verschiedene Hersteller wären gut.
2. **Freischaltungen im Mehrspieler:** Darf jeder nur seine eigenen Autos und Strecken nutzen, gibt der Host alles frei, oder fahren alle dasselbe Auto?
3. **KI auffüllen:** Sollen freie Plätze mit KI-Gegnern besetzt werden (z. B. 2 Menschen + 2 KI)?
4. **Berührungen zwischen Spielern:** standardmäßig an (mehr Chaos) oder aus (reiner Linienvergleich)?
5. **Zeichnen:** ohne Zeitlimit (auf alle warten) oder mit Limit? Bleiben die Linien der anderen bis zur Enthüllung verdeckt?
6. **Drift-Arena im Mehrspieler:** gleichzeitig ohne Berührung oder nacheinander?
7. **Anzeige beim Host:** Soll auch der Host mit 0,1 s Verzögerung sehen, damit alle Bildschirme im Raum gleich laufen (empfohlen)?
8. **Sprechblasen:** Nur Ereignisse oder auch Schnellsprüche? Dürfen die Sprüche derb sein (wie bei der „energiegeladenen“ Musik)?
9. **Karriere:** Bleibt der Mehrspieler komplett getrennt von Gold und Bestenliste (empfohlen)?
10. **„Weitergeben“-Modus (M2b):** als Zwischenschritt gewünscht?
11. **Später:** Komfort-Beitritt per QR (M8)? PC als Mitspieler offiziell unterstützen?

### Entscheidungen des Nutzers (03.10.2026)

- **Testgeräte (1):** S10 (Android 12) und S21 (Android 15) per WLAN-Debugging, bei Bedarf als drittes das S24 Ultra (Android 16). Alle von Samsung.
- **Freischaltungen (2):** Im Mehrspieler sind alle Strecken und Autos frei. Danach gilt wieder der eigene Fortschritt: Was im Mehrspieler frei war, bleibt nicht freigeschaltet.
- **KI auffüllen (3):** In der Lobby wählbar.
- **Zeichnen (5):** ohne Zeitlimit, es wird auf alle gewartet. Die Linien bleiben verdeckt, bis alle fertig sind.
- **„Weitergeben“-Modus (10):** ja, als Zwischenschritt (M2b).
- **Autowahl (03.10.2026, nach dem ersten Test):**
  - Mehrere Spieler dürfen dasselbe Auto nehmen, damit ein ebenbürtiges Spiel möglich ist. Die Regel „jedes Auto nur einmal“ entfällt.
  - Erkennbar bleibt jeder Spieler an seiner eigenen Spielerfarbe: Lack, Schild, Lichtkranz, Turbo-Knopf und Linie.
  - Die Autowahl gleicht der des Einzelspielers: drehendes 3D-Auto (lackiert in der Spielerfarbe), Motorklang zur Probe und die Fahrwerte (Haftung, Kraft, Gelände, Turbo). Sie nutzt dieselbe Garage wie der Einzelspieler, im Mehrspieler mit allen Autos. Das gilt im „Weitergeben“-Modus und in der WLAN-Lobby.
- **WLAN-Bindung:**
  - Beim Betreten des WLAN-Mehrspielers (Lobby, Gastgeber wie Mitspieler) bindet das Spiel sich automatisch ans WLAN, ohne Schalter.
  - Beim Verlassen wird die Bindung gelöst, damit Update-Suche und Internet wieder gehen.
  - Ohne WLAN-Verbindung erscheint ein Hinweis.
  - Der „Weitergeben“-Modus braucht keine Bindung.
  - Der Netztest behält den Schalter für Vergleichsmessungen.
- **Vorläufig nach Empfehlung, noch offen für Änderungen:**
  - Berührungen zwischen Spielern sind an und in der Lobby abschaltbar (4).
  - Drift-Arena: alle gleichzeitig, ohne Berührung (6).
  - Auch der Gastgeber sieht das Rennen mit der gemeinsamen Verzögerung (7).
  - Sprechblasen zunächst nur bei Ereignissen, Sprüche später (8).
  - Der Mehrspieler bleibt getrennt von Gold und Bestenliste (9).

---

## 10. Prüfprotokoll dieser Recherche

Zwei Vorarbeiten (Verbindungstechnik, Spielarchitektur) wurden gegen Quellen und den Code gegengeprüft.

**Bestätigt**

- Android-17-Berechtigung `ACCESS_LOCAL_NETWORK`: Umfang, targetSdk-37-Grenze und Weiterbetrieb über `INTERNET` bei niedrigerem targetSdk.
- LocalOnlyHotspot: kein Internet; Berechtigungen `NEARBY_WIFI_DEVICES` bzw. `ACCESS_FINE_LOCATION` (bis API 32).
- WifiNetworkSpecifier: Systemdialog, kein Internet, ab API 29.
- Hotspot mit bis zu 10 Geräten; Anbieter können Tethering beschränken.
- Godot: ENet-API, RPC-Übertragungsarten, keine eingebaute LAN-Suche.
- Android-Hinweis zu Rundrufen und automatischer Multicast-Lock.
- Vector2 ist 32 Bit, `float` ist 64 Bit.
- Nearby-Strategie P2P_STAR; play-services-nearby 19.5.1 vom 28.09.2026.
- Codestellen: `record_point()` → `begin_race()`, Index-0-Annahmen, Turbo in `main.gd`, GitHub-Updater, targetSdk 35, Drift-Modus allein.

**Korrigiert**

- Der Godot-Vorschlag #7128 (Soft-Float/Festkomma) ist **nicht offen**, sondern „closed as not planned“.
- Die Google-Hilfe erwähnt **keinen QR-Code** für den Hotspot. Der Hinweis darauf bleibt als „ungeprüft je Hersteller“ stehen.
- **04.10.2026, Hotspot-Adresse:** Ein zufälliges Netz bei jedem Einschalten gibt es laut AOSP-Quelltext nur unter Android 11. Ab Android 12 wird die letzte Adresse wiederverwendet (bis zum Neustart oder Konflikt), und es kommen `172.16.0.0/12` und `10.0.0.0/8` hinzu. Die Erfahrungsberichte bezogen sich auf Android 11. Abschnitt 4.2 ist berichtigt.

**Nur teilweise bestätigt**

- Die genaue Aufteilung der Bionic-Mathebibliothek (welche Funktion aus FreeBSD, welche aus ARM optimized-routines). Bestätigt ist nur, dass beide Quellen verwendet werden. Für die Empfehlung ist das unerheblich, weil nur der Host rechnet.

**Offen für den Gerätetest**

- Wie Android bei aktiven mobilen Daten die Pakete zum Hotspot genau routet.
- Ob `bindProcessToNetwork` die nativen ENet-Sockets erfasst.
- Hotspot ohne SIM.
- Hotspot-Abschaltzeiten je Hersteller.

---

## 11. Quellen

Android (offiziell)

- Local network permission (Android 16 opt-in, Android 17 Pflicht): https://developer.android.com/privacy-and-security/local-network-permission
- Behavior changes Android 17: https://developer.android.com/about/versions/17/behavior-changes-17
- Local-only Wi-Fi hotspot: https://developer.android.com/develop/connectivity/wifi/localonlyhotspot
- Wi-Fi Network Request API (WifiNetworkSpecifier): https://developer.android.com/develop/connectivity/wifi/wifi-bootstrap
- Read network state (Standardnetz, Validierung): https://developer.android.com/develop/connectivity/network-ops/reading-network-state
- NDK Networking (`android_setprocnetwork`, entspricht `bindProcessToNetwork`): https://developer.android.com/ndk/reference/group/networking
- Google-Hilfe Hotspot/Tethering (bis zu 10 Geräte, Anbieterbeschränkungen): https://support.google.com/android/answer/9059108?hl=en
- Bionic libm (FreeBSD-Quellen und ARM optimized-routines): https://android.googlesource.com/platform/bionic/+/master/libm/
- Nearby Connections, Strategien: https://developers.google.com/nearby/connections/strategies
- Google Play services Release Notes (play-services-nearby 19.5.x): https://developers.google.com/android/guides/releases

Android-Quelltext (AOSP), Hotspot-Adresse (geprüft am 04.10.2026)

- Android 10, feste Adresse `WIFI_HOST_IFACE_ADDR = "192.168.43.1"`: https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-10.0.0_r1/services/net/java/android/net/ip/IpServer.java
- Android 11, Zufallsnetz in `192.168.0.0/16` ohne Merken. Unter Android 11 lag das Tethering-Modul noch in `frameworks/base`; derselbe Pfad unter `packages/modules/Connectivity` existiert für diesen Tag nicht: https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-11.0.0_r1/packages/Tethering/src/com/android/networkstack/tethering/PrivateAddressCoordinator.java
- Android 12, letzte Adresse je Schnittstellenart (`mCachedAddresses`, `useLastAddress`): https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/tags/android-12.0.0_r1/Tethering/src/com/android/networkstack/tethering/PrivateAddressCoordinator.java
- Android 12, `requestIpv4Address(true /* useLastAddress */)` beim Einschalten, `false` bei Konflikt: https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/tags/android-12.0.0_r1/Tethering/src/android/net/ip/IpServer.java
- Android 12, Schalter `tether_enable_select_all_prefix_ranges` (ab Werk an): https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/tags/android-12.0.0_r1/Tethering/src/com/android/networkstack/tethering/TetheringConfiguration.java
- Android 13, alle drei Bereiche fest: https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/tags/android-13.0.0_r1/Tethering/src/com/android/networkstack/tethering/PrivateAddressCoordinator.java
- Android 15, zufälliger Startbereich (`getStartedPrefixIndex`, Schalter `tether_force_random_prefix_base_selection`): https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/tags/android-15.0.0_r1/Tethering/src/com/android/networkstack/tethering/PrivateAddressCoordinator.java

Godot

- ENetMultiplayerPeer: https://docs.godotengine.org/en/stable/classes/class_enetmultiplayerpeer.html
- High-level multiplayer (RPC-Modi, Android-INTERNET, keine Suche): https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html
- PacketPeerUDP (Broadcast, `CHANGE_WIFI_MULTICAST_STATE`): https://docs.godotengine.org/en/stable/classes/class_packetpeerudp.html
- PR #33910, Multicast-Lock auf Android: https://github.com/godotengine/godot/pull/33910
- Issue #24666, UDP-Broadcast nicht auf allen Android-Geräten: https://github.com/godotengine/godot/issues/24666
- Android-Exportoptionen (Berechtigungen): https://docs.godotengine.org/en/stable/classes/class_editorexportplatformandroid.html
- Vector2 (32-Bit-Komponenten): https://docs.godotengine.org/en/stable/classes/class_vector2.html
- Vorschlag #7128 Soft-Float/Festkomma (closed as not planned): https://github.com/godotengine/godot-proposals/issues/7128
- Kenyoni QR Code Addon (MIT): https://kenyoni-software.github.io/godot-addons/addons/qr_code/

Erfahrungsberichte / Fachartikel **[Bericht]**

- Zufälliges Hotspot-Netz unter Android 11 (ab Android 12 siehe AOSP-Quelltext oben): https://github.com/Mygod/VPNHotspot/issues/193
- Pixel-Hotspot 6 GHz / Kompatibilität: https://www.androidpolice.com/android-14-control-wi-fi-hotspot-frequency-band/
- LocalSend funktioniert über Handy-Hotspot ohne Internet (Praxisbeleg für Variante A): https://www.makeuseof.com/localsend-got-so-much-better-once-i-started-using-it-like-this/
- WLAN ohne Internet und mobile Daten (Nutzerberichte): https://xdaforums.com/t/force-android-to-use-mobile-data-when-wifi-connected-but-has-no-internet.4501535/
- Wi-Fi Direct, Gruppenbesitzer 192.168.49.1: https://www.researchgate.net/publication/340771475_Android_Wi-Fi_Direct_Architecture_From_Protocol_Implementation_to_Formal_Specification
