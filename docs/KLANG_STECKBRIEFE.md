# Klang-Steckbriefe: Referenz-Höranalyse und Vorgaben für Draw2Race

Stand: 26.09.2026. Quelle: `../Videos/DrawRace 2 - iPhone - NZ - HD Gameplay Trailer.mp4`. Werkzeuge: `E:\Draw2Race-AudioLab` (siehe Abschnitt 7).

## 1. Methode und Verlässlichkeit

Ich (Claude) kann Audio nicht selbst hören. Die Beschreibungen stammen aus lokalen KI-Modellen und aus Messungen. Als Beobachtung gilt nur, was mindestens zwei unabhängige Verfahren übereinstimmend zeigen.

| Verfahren | Liefert | Bewertung |
|---|---|---|
| **Qwen3-Omni-30B-A3B-Captioner** (Apache 2.0, lokal, int8) | ausführliche Textbeschreibung je Szene | Hauptquelle. Genre, Instrumente und Stimmung sind plausibel und zu AST konsistent. **Bekannte Fehler** (durch Gegenproben an eigenen Stücken bestätigt):<br>• Es behauptet Stereo-Bewegung, obwohl die Aufnahme mono ist.<br>• Es erfindet Orte (Garage, Tunnel), Automarken und Handlungen.<br>• Kurze Töne nennt es manchmal „Klick“.<br>• Am Clipende hört es fast immer einen „tiefen elektronischen Brummton“, der nicht existiert.<br>• Langsames Moll-Klavier ordnet es reflexhaft Satie zu. |
| **AST AudioSet-Klassifikator** (BSD-3) | Wahrscheinlichkeiten für 527 Klassen | Gegenprobe für Instrumente und Kategorien. Grob, aber robust. |
| **Messung** (librosa, ffmpeg, Spektrogramm) | BPM, Tonart, Frequenzen, Zeiten | Tonart eindeutig nur in Szenen ohne Motor. BPM ist bei Rubato-Klavier unzuverlässig. |
| **Demucs** (MIT) | Trennung in Schlagzeug, Bass und Übriges | Den Motor trennt es nicht sauber von der Musik. Die Rennmusik bleibt deshalb unsicher. |
| ACE-Step `understand_music` | Stil, BPM, Tonart | **Verworfen:** widerspricht allen anderen Verfahren (erfindet Metal, Surf-Punk, deutschen Gesang). Es ist für saubere Musik gedacht, nicht für Spielton mit Effekten. |

Rohdaten liegen im AudioLab: `out/captions_qwen.json`, `out/tags_ast.json`, `out/messung.json`.

## 2. Klangbild der Referenz je Szene

| Szene (Video) | Musik | Effekte | Sicherheit |
|---|---|---|---|
| Intro/Logo 00:03–00:14 | kurzes Synth-Motiv: glockiges Arpeggio über warmer Fläche, Moll, retro/80er, nachdenklich; **d-Moll** gemessen (0,83) | Metall-Kreischen und Aufprall als Auftakt, harter Schnitt | mittel |
| Hauptmenü/Karriere 00:15–00:43 | **Solo-Klavier**, langsam, frei im Tempo (Rubato), melancholisch-kontemplativ, gebrochene Akkorde links, liedhafte Melodie rechts, Hallraum; Tonart im Bereich d-Moll/F-Dur/B-Dur | UI: trockener Kameraverschluss-Klick mit leisem, tiefem „Thud“ je Tastendruck | hoch (Qwen und AST: Klavier) |
| Turbo-Tutorial 04:50, Pause 14:55 | dasselbe Klavierthema; **d-Moll** gemessen (0,83–0,86). Das Modell nennt Saties *Gymnopédie Nr. 1*, tut das aber auch bei unserem eigenen Klavierentwurf. Es ist also eine Modelltendenz für „langsames Moll-Klavier“, keine Erkennung. | Klick mit kurzem Quietschen | hoch (AST: Piano 0,14) |
| Auswahl/Garage 02:10–02:40 | filmische Streicher in Moll, spannungsvoll, „Trailer“-Charakter; ~129–136 BPM gemessen | Fahrzeugvorschau: Motor startet und dreht hoch; mechanisches Klacken; Bestätigungs-Chime; Luft-„Whoosh“ | mittel |
| Zeichenphase 01:04–01:25 | keine eindeutige Musik | Motor im Leerlauf und Hochdrehen, dominierend | mittel |
| Rennen (Oval, Palmen, Schnee) | leise **elektronische Rennmusik** darunter wahrscheinlich: pulsierender, verzerrter Synth-Bass, Synth-Flächen, Drumcomputer (nur in Demucs-Fassungen erkennbar) | kräftiger Verbrennermotor (V8-artig), Turbo-Pfeifen, Tonhöhe folgt dem Tempo; Reifenquietschen in Kurven; Vorbeifahrten mit Doppler (Gegner); metallisches Klirren/Kollisionen; elektronischer Chime beim Start | Effekte hoch, Musik niedrig |
| Startampel 01:26 | – | vier kurze Töne (~1050 Hz, Abstand ~0,35 s) und ein langer Startton eine Oktave höher (~2030 Hz, ~0,7 s); das Modell hört „helle elektronische Chimes“ | hoch (Messung) |
| Zieleinlauf 01:50–01:56 | orchestraler Akzent: Blech-Akkord, aufsteigende Streicher, Pauke und Becken, „Trailer-Hit“ | Kreischen und metallischer Schlag | mittel |
| Ergebnis/Sieg 01:55–02:09 | **synthetisch-orchestrale Fanfare**: Glocken-Arpeggios, schimmernde chorartige Flächen, Synth-Bass-Puls, Pauken-Hit mit Crash-Becken, triumphaler Höhepunkt; AST: „Theme music / Video game music“; d-Moll→F-Dur gemessen (0,83/0,78), ~103 BPM | – | hoch |
| Niederlage 14:00 | tiefer elektronischer Ton, dann langsames Cello mit Streichern, Moll, melancholisch; **d-Moll** gemessen (0,83) | Chime | mittel |

**Übergreifende Ableitung:** Das Original setzt zwei Klangwelten gegeneinander. Die Menüs sind ruhig, melancholisch und akustisch (Klavier, Streicher). Das Rennen ist laut, mechanisch und aggressiv (Motor, Reifen). Musikalische Höhepunkte kommen als kurze filmische Stings bei Ergebnis und Zieleinlauf. Das tonale Zentrum der Menü- und Ergebnismusik liegt wiederholt bei **d-Moll/F-Dur**.

## 3. Musik-Steckbriefe für Draw2Race (eigene Kompositionen)

Die Steckbriefe beschreiben **Stil und Funktion**, keine Melodien des Originals. Die Prompts sind englisch, weil die Generatoren darauf trainiert sind. Die maschinenlesbare Fassung ist `E:\Draw2Race-AudioLab\generate\briefs.json`.

| Name | Einsatz | Tempo/Tonart/Länge | Prompt (Kurzform) |
|---|---|---|---|
| `menu_klavier` | Hauptmenü, Karriere, Tutorials, Pause (Loop) | 72 BPM, d-Moll, 90 s | melancholic contemplative solo grand piano, slow rubato, sparse broken-chord arpeggios, lyrical melody, minimalist impressionist, warm hall reverb, seamless loop |
| `intro_synth` | Logo/Start | 96 BPM, d-Moll, 20 s | moody retro 1980s synth, bell-like arpeggio over warm analog pad, nostalgic, short logo sting |
| `sieg_fanfare` | Sieg/Gold/Freischaltung | 104 BPM, F-Dur, 24 s | epic synth-orchestral victory fanfare, crystalline bell arpeggios, shimmering pads, synth bass pulse, timpani hit and crash, bright major chord |
| `auswahl_spannung` | Event-/Fahrzeugauswahl (Loop) | 128 BPM, g-Moll, 60 s | tense cinematic strings, staccato ostinato, low cellos, soft brass swells, subtle electronic pulse, loopable |
| `niederlage_cello` | Ergebnis ohne Sieg | 66 BPM, d-Moll, 20 s | somber solo cello over soft strings, slow, low electronic drone, short defeat cue |
| `rennen_elektro` | Rennen (Loop, leise) | 128 BPM, e-Moll, 90 s | driving dark electronic racing music, pulsing distorted synth bass, drum machine, atmospheric pads, sparse mid-range to leave room for engine |

**Mischregeln (Vorschlag):**
- Die Rennmusik bleibt deutlich unter Motor und Reifen, weil das Fahrzeug-Feedback Vorrang hat.
- Die Menümusik läuft als nahtloser Loop mit Überblendung beim Szenenwechsel.
- Stings (Sieg, Niederlage) blenden die Loops kurz aus.
- Alle Musikstücke sind getrennt vom Effektpegel regelbar (siehe [RICHTLINIEN.md, Abschnitt 7](RICHTLINIEN.md#7-soundentwurf)).

## 4. Effekt-Steckbriefe für Draw2Race

| Effekt | Vorgabe | Umsetzung |
|---|---|---|
| Startampel | 4 kurze, weiche Pieptöne und ein langer, eine Oktave höherer Startton; eigene Frequenzen und Klangfarbe | prozedural in Godot, einfache Töne mit Hüllkurve |
| UI-Klick | trockener, kurzer „Verschluss“-Klick mit leichtem Tiefenanteil; Bestätigung als kurzer glockiger Chime | prozedural oder Soundeffekt-Generator |
| Motor | kräftiger Verbrenner, Tonhöhe und Lautheit folgen **simulierter** Drehzahl und Last; Turbo mit hellem Pfeifen | mehrere Loops (Leerlauf/Mitte/hoch) nach Drehzahl überblenden |
| Reifen | Quietschen proportional zum Schlupf, Klang abhängig vom Untergrund (Asphalt hell/tonal, Schnee/Erde rauschiger) | Loops nach Schlupf und Untergrund |
| Gegner-Vorbeifahrt | Motor mit Doppler und Abstandsdämpfung | 3D-Audio in Godot |
| Kollision | metallischer Schlag, Stärke abhängig vom Aufprall | kurze Varianten, zufällig gewählt |
| Zieleinlauf | kurzer orchestraler Hit (Blech, Pauke, Becken) | als Musik-Sting erzeugen |

## 5. Stand der erzeugten Entwürfe

Mit ACE-Step 1.5 (XL-SFT + 4B-LM, MIT) sind je Steckbrief zwei Varianten entstanden, für drei Steckbriefe zusätzlich eine zweite Runde. Die Tabelle in Abschnitt 3 nennt die ursprünglichen Prompts. Die nachgeschärften Prompts der Runde 2 stehen in `audio/entwurf/steckbriefe.json`. Sie liegen in `E:\Draw2Race-AudioLab\out\generated\` und `audio/entwurf/`. Tempo und Tonart wurden nachgemessen (`out/messung_generiert.json`). Die Stilprüfung durch den Captioner steht in Abschnitt 6.

**Die Hörabnahme durch einen Menschen steht aus.**

## 6. Prüfung der Entwürfe

Jeder Entwurf wurde mit demselben Captioner beschrieben (erste 30 s) und mit dem Steckbrief verglichen. Tempo und Tonart wurden nachgemessen. Nach Runde 1 wurden drei Prompts nachgeschärft (Runde 2, `_r2`).

| Steckbrief | Variante | Befund des Captioners | Passt? |
|---|---|---|---|
| menu_klavier | v1 | Harfe statt Klavier, ruhig, Rubato | nein |
| | v2 | langsames Solo-Klavier in Moll, kontemplativ | **ja** |
| | r2_v1 | Solo-Klavier, Moll, Rubato, introspektiv | **ja** |
| | r2_v2 | Celesta/Glockenspiel, spärlich | nein |
| intro_synth | v1 | glockiges Synth-Arpeggio über warmer Fläche, verträumt | **ja** |
| | v2 | J-Pop-/Anime-Beat, optimistisch | eher nein |
| sieg_fanfare | v1 | Moll, hektisch, EDM | nein |
| | v2 | ruhig, 80er-Spielmusik, nicht episch | eher nein |
| | r2_v1 | Glocken-Arpeggio, Moll, drängend | nein |
| | r2_v2 | triumphal, Dur, synth-orchestral mit Blech-Lead und Beat | **ja** |
| auswahl_spannung | v1, v2 | optimistisch bzw. Werbemusik | nein |
| | r2_v1 | Orchester, Moll-Streicher-Arpeggio, drängende Spannung | **ja** |
| | r2_v2 | filmische „Braam“-Schläge, Moll-Streicher, Spannung | **ja** |
| niederlage_cello | v1, v2 | Solo-Cello, langsam, traurig, großer Hall | **ja** |
| rennen_elektro | v1 | helles Progressive House | teilweise |
| | v2 | treibend, industriell, Four-on-the-floor, Synth-Bass | **ja** |

Tempo: Die Vorgaben werden bei rhythmischen Stücken fast genau getroffen (128→129, 104→103, 96→96–99 BPM). Bei Rubato-Stücken ist die Messung unzuverlässig.
Tonart: Grundton meist getroffen; Dur/Moll bestimmt der Schätzer bei diesen Stücken nicht sicher.

**Lehre für neue Prompts:** ACE-Step reagiert gut auf konkrete Besetzungen („full symphony orchestra“, „solo acoustic grand piano only“, „heroic brass with trumpets and french horns“). Abstrakte Stimmungswörter allein führen zu generischer Werbe- oder Popmusik. Je Steckbrief lohnen sich 2–4 Varianten mit automatischer Vorauswahl durch den Captioner. Die endgültige Wahl trifft ein Mensch.

## 6a. Runde 3: YuE2 (26.09.2026)

**Rückmeldung des Nutzers zu ACE-Step:**
- Das Menü-Klavier (v1, v2, r2_v1) begeistert.
- Sonst hört er MP3-artige, verrauschte Qualität.
- Viele Stücke sind zu kurz und enden abrupt.
- Die Auswahl-Musik ist zu eintönig.
- Im Rennen wünscht er treibenden Elektro/Techno mit 130 BPM.

Daraufhin wurde auf **YuE2-3B** gewechselt. Die Lizenz CC BY-NC 4.0 passt, weil das Spiel nicht-kommerziell auf GitHub erscheinen soll.

| Weg | Werkzeug | Ergebnis |
|---|---|---|
| Basismodell | offizielles Instrumental-Werkzeug (YuE2 schreibt ABC-Partitur, Gesangsstimme → Instrument) | Laut Nutzer „mit großem Abstand“ besser als ACE-Step, keine abrupten Enden; `rennen_techno_s22` „ziemlich cool“. Teilweise echter Gesang (vom Nutzer im Testlauf gehört). Länge 2–4 min. |
| Basismodell + LoRAs | Instrumental-AR-LoRA und Real-Audio-NAR-LoRA v4 (Mothersuperior, CC BY-NC) | Kaum Gesang (Median der Gesangsspur −54 bis −67 dB). Zeitmarken wirken teilweise (Cello s11: genau 1:30). Techno, Auswahl und ein Sieg-Seed liefen an die Längengrenze und scheiterten am Speicher. |

**Gesangsprüfung:** `analyse/vocal_check.py` trennt mit Demucs die Gesangsspur ab und zählt die Sekunden, in denen sie weniger als 12 dB unter dem Rest liegt. Cello und Synth-Leads erzeugen Fehlalarme. Kurze Vokalisen sind erlaubt, gesungener Text nicht.

**Technik unter Windows:**
- PyTorch für Windows hat kein FlashAttention. Die YuE2-Bibliothek in der Werkstatt ist deshalb so gepatcht, dass sie das prüft und auf cuDNN/SDPA ausweicht (`yue2/cuda_graph.py`).
- Die Stücke laufen auf GPU 1, weil GPU 0 den Bildschirm treibt.

**Einbauplan (Vorschlag):**
- Niederlage: zwei ~1,5-min-Cellostücke im Wechsel, solange die Ansicht offen ist.
- Menü und Rennen: Loop mit Überblendung.
- Sieg: einmal abspielen, danach Menümusik.

## 6b. Runde 4: Songs mit Gesang und Musiksystem im Spiel (26.09.2026)

**Entscheidungen des Nutzers:**
- Weiter nur mit dem Basismodell, ohne LoRA.
- Musik im ganzen Spiel durchgehend, umschaltbar zwischen „energiegeladen“ (Songs mit Gesang) und „ruhig“ (Instrumentals).
- Beim Zeichnen stark abgesenkt, beim Rennstart wieder hoch.
- Bei Niederlage ein motivierender Crunk-Rap, bei Sieg ein Club-Rap-Feierstück.
- Explizite Sprache ist erwünscht.

**Vorlagen:** 13 Lieblingslieder des Nutzers (`audio/Vorschläge/`, nicht veröffentlichen). Tempo, Tonart und Genre-Tags wurden gemessen (`E:\Draw2Race-AudioLab\out\vorschlaege_messung.json`). Daraus entstanden eigene Stilbeschreibungen und Texte; es wurden keine Melodien oder Texte übernommen.

| Song | Rolle | Stil (Vorbild) |
|---|---|---|
| You're the King | Sieg | Club-Rap/Hip-House (Hit The Floor, Get It Crackin) |
| Get Up | Niederlage | Crunk (Get Low) |
| Red Line | Playlist | Rawstyle/Hardstyle (Get It Crackin, Attention) |
| Burn It | Playlist | Trap-EDM (Turn Down For What) |
| Full Throttle | Playlist | Electrocore (Hypa Hypa) |
| Flashback Highway | Playlist | Hands-up/Trance (Flashback) |
| One More Lap | Playlist | melodischer Hardrock (One Step Away) |
| Pit Stop Party | Playlist | Club-Rap (Move Shake Drop, Party Up) |
| Outta the Pits | Playlist | UK-Hardcore (Outta My Head) |
| Dangerous Curves | Playlist | Funk-House (Dangerous) |
| Bounce/Drift | Playlist | Twerk/Moombahton (Bounce That) |

**Weitere Stücke dieser Runde:**
- **Menü s22 ohne Gesang:** Dieselbe Partitur wurde mit neuen Seeds gerendert. s44 und s55 sind gesangsfrei, das Original hatte 22 s Gesang.
- **Sieg sofort positiv:** Die neuen Varianten erreichen volle Energie nach 3,8 s, 5,5 s bzw. 8,5 s. Die alte Fanfare brauchte 18,8 s, was die Beobachtung des Nutzers bestätigt. Zusätzlich setzt das Spiel Siegstücke direkt am Energiepunkt ein.

**Spielfertig:** 22 Titel mit 58 MB in `game/assets/music/`, vorläufig Seed 11 je Song. Die endgültige Auswahl trifft der Nutzer.

## 6c. Songs verlängern (26.09.2026)

YuE2 kann eine fertige Aufnahme nicht fortsetzen. Der Weg führt deshalb über die Partitur (`generate/extend_song.py`):
1. Die gespeicherte ABC-Partitur des Songs wird gelesen.
2. Strophe und Refrain werden vor dem Schluss so oft wiederholt, bis rechnerisch über 3:10 erreicht sind. Die Rundenzahl ergibt sich aus Takten und BPM.
3. Jede Wiederholung bekommt eine neue Strophe (`generate/song_erweiterungen.json`).
4. Der Song wird mit gleichem Stil und Seed neu gerendert.

Für Rap-Songs ohne notierte Gesangstöne richtet sich die Wiederholung nach den Abschnittsmarken.

**Nutzerurteil:** Der bekannte Teil klingt „sehr ähnlich“ zum Original. Variante b mit dem Stilzusatz „full band instrumentation … in every chorus“ ist besser als a, deren Refrain zu trocken war. Ab sofort wird nur Variante b erzeugt.

**Ergebnisse:**
- „Get Up“: 3:32 (s11) und 3:15 (s22)
- „You're the King“: 3:11 (s11) und 3:18 (s22)
- übrige kurze Songs in Arbeit

## 6d. Motorklänge im Spiel (30.09.2026)

Die Motoren der Fahrzeuge stammen nicht aus der Referenz und nicht aus einem KI-Modell, sondern aus einer eigenen Synthese (`tools/make_engine_sounds.py`, nur numpy): Zündfolge, Druckimpuls, Abgasanlage und Ansaugrauschen je Auto, sechs Drehzahlschichten für Gas und Schub, dazu Turbo-/Kompressorpfeifen, Schubumluftventil und Fehlzündungen. Das Spiel überblendet zwei benachbarte Schichten und führt die Tonhöhe der gewünschten Drehzahl nach (`game/scripts/engine_audio.gd`); Einzelheiten und Messwerte stehen in `docs/IMPLEMENTIERUNG.md` (Abschnitt „Motorklang je Auto“).

- **Lizenz:** vollständig eigenes Material, wie das Spiel unter CC BY-NC 4.0. Der Klassifikator AST (BSD-3) diente nur zur Kontrolle und steckt nicht im Spiel.
- **Kontrolle ohne Gehör:** Spektrogramm-Bogen je Auto, Zündfrequenz gegen Sollwert, Sprung an der Schleifennaht, Probefahrt aus den Schichten und AudioSet-Bewertung. Die Belegregel (mindestens zwei übereinstimmende Verfahren) ist erfüllt für „klingt periodisch nach Zündfolge und ändert sich mit der Drehzahl“; ob es **gut** klingt, entscheidet die Hörabnahme.
- **Stilziel:** laut und mechanisch (Rennen), je Auto unterscheidbar: Sprint hell und sportlich, Grip kleiner Dreizylinder, Dirt Hawk Boxer mit Blubbern, Thunder V8 tief mit Kompressor, Apex GT V12, Col Racer hoch und spitz, Quarry Truck nagelnder Diesel, Drift King rau mit Fehlzündungen.

## 7. Werkzeuge, Lizenzen, Rechtliches

- **AudioLab:** Alles liegt in `E:\Draw2Race-AudioLab` (Python, Modelle, Caches). Es gibt keine Systeminstallation, zum Entfernen genügt es, den Ordner zu löschen. Die Bedienung beschreibt `LIESMICH.md` dort.
- **Kommerziell nutzbar:**
  - ACE-Step 1.5 (MIT) für Musik
  - Qwen3-Omni-Captioner (Apache 2.0), AST (BSD-3), Demucs (MIT) für die Analyse
- **Nicht-kommerziell, bewusst genutzt:** YuE2-3B und die Mothersuperior-LoRAs (CC BY-NC 4.0). Draw2Race wird nicht-kommerziell veröffentlicht. Damit kann auch das Spiel samt Musik nur nicht-kommerziell weitergegeben werden.
- **Nicht genutzt:** Music Flamingo (NVIDIA, nur nicht-kommerzielle Forschung)
- **Offen:** MOSS-SoundEffect v2 (Apache 2.0) für generierte Soundeffekte. Die Installation wurde von der automatischen Sicherheitsprüfung angehalten und muss freigegeben werden.
- **Keine Kopien:** Die Musik des Originals ist urheberrechtlich geschützt. Draw2Race nutzt nur Stil- und Funktionsbeschreibungen. Referenzaudio wird nicht als Vorgabe eingespeist (kein Cover-/Melodie-Modus). Ein Anklang an Saties *Gymnopédie* wäre gemeinfrei, ist aber nur eine unbestätigte Modellvermutung und keine Vorgabe.
