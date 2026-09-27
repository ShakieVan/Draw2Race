"""Erzeugt art/bildvorlagen/: je Objekt eine Bildbeschreibung (vollständiger Prompt) für ein Bild-KI-Werkzeug.

Die Bilder dienen als Vorlage für die Bild-zu-3D-Umrechnung (z. B. TRELLIS.2). Deshalb enthält jeder
Prompt dieselben Regeln: genau ein Objekt, freigestellt, schräg von oben, weiches Licht, keine Schrift/Marken.
Aufruf: python tools/make_image_prompts.py
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "art" / "bildvorlagen"

REGELN = """Bildregeln (für die Umrechnung in ein 3D-Modell, bitte genau einhalten):
- Genau EIN Objekt, vollständig im Bild, mittig, füllt etwa 80 % der Bildfläche, nichts abgeschnitten.
- Perspektive (verbindlich, hat Vorrang vor allen anderen Wünschen):
  - Kamera links vorne, leicht erhöht. Man sieht vor allem die LINKE Seite des Objekts und schräg ein Stück der Vorderseite
    (horizontal etwa 30–40° aus der reinen Seitenansicht in Richtung Front gedreht – also mehr Seite als Front).
  - Kamera etwa 20–30° über der Horizontalen, Blick leicht von oben, sodass auch die Oberseite (Dach) sichtbar ist.
  - Niemals von unten, keine Froschperspektive, keine Unterseite, keine reine Draufsicht, keine reine Front- oder Seitenansicht.
  - Natürliche Verdeckung ist ausdrücklich erwünscht: Was auf der abgewandten Seite liegt, darf verdeckt sein.
  - Brennweite wie ein Teleobjektiv / Produktfoto, also kaum perspektivische Verzerrung.
- Hintergrund: freigestellt (transparent) oder reines, gleichmäßiges Weiß. Kein Boden, keine Bodenschatten, keine Spiegelung, keine Umgebung.
- Licht: weich und gleichmäßig wie in einer Studio-Softbox, neutralweiß, keine harten Schatten, keine farbigen Lichter, keine Gegenlicht-Effekte.
- Stil: fotorealistisch, hochwertiges 3D-Rendering, realistische Materialien und Gebrauchsspuren, aber sauber und klar lesbar.
- Keine Schrift, keine Zahlen, keine Logos, keine Markenembleme, keine Kennzeichen, keine Wasserzeichen, keine Personen oder Tiere.
- Format: quadratisch (1024 × 1024), PNG."""

AUTO_REGELN = """Zusätzlich für Autos:
- Frei erfundenes Design, keinem realen Modell und keinem Hersteller nachempfunden, keine Markenembleme oder Kühlergrill-Logos.
- Lack einheitlich hellgrau bis weiß, ohne Streifen, Aufkleber oder Werbung (die Farbe wird im Spiel gesetzt).
- Scheiben dunkel getönt, Räder gerade (nicht eingeschlagen), Felgen silbern bzw. dunkel metallisch.
- Räder: Die beiden Räder der linken (zugewandten) Seite sind vollständig zu sehen. Die Räder der rechten Seite sind durch die
  Karosserie natürlich verdeckt – das ist richtig so. Die Perspektive NICHT ändern, um mehr Räder zu zeigen.
- Das Auto steht auf seinen Rädern in normaler Fahrposition (kein Kippen, keine Ansicht von unten).
- Zustand: sauber, ohne Schmutz (Ausnahme: Rallye-Auto darf leicht verstaubt sein)."""

OBJEKTE = {
    # --- Autos (Spielwerte in RaceVehicle.CARS) ---
    "auto_sprint": ("Auto „Sprint“ – der Allrounder",
        "Ein kompaktes, sportliches zweitüriges Coupé mit weich fließender, moderner Linienführung, kurzen Überhängen, "
        "flacher Frontscheibe und einer dezenten Abrisskante am Heck. Wirkt leicht, flink und freundlich."),
    "auto_grip": ("Auto „Grip“ – der Kurvenkünstler",
        "Ein kleiner, breit stehender dreitüriger Hot-Hatch mit kurzem Heck, ausgestellten Radhäusern, großem Dachkantenspoiler "
        "und tief sitzender Frontschürze. Wirkt agil und bissig."),
    "auto_dirt_hawk": ("Auto „Dirt Hawk“ – Rallye",
        "Ein Rallye-Coupé mit höhergelegtem Fahrwerk, grobstolligen Geländereifen, Schmutzfängern hinter allen Rädern, "
        "Lufthutze auf dem Dach, Dachträger mit vier runden Zusatzscheinwerfern und robustem Unterfahrschutz."),
    "auto_thunder_v8": ("Auto „Thunder V8“ – Muscle-Car",
        "Ein kraftvolles Muscle-Car im klassischen amerikanischen Stil, aber frei erfunden: sehr lange Motorhaube mit großer "
        "Lufthutze, kurzes Fastback-Heck, breite Hinterbacken, breite Reifen, markante rechteckige Scheinwerfer."),
    "auto_apex_gt": ("Auto „Apex GT“ – Supersportwagen",
        "Ein extrem flacher, breiter Mittelmotor-Supersportwagen mit keilförmiger Front, großen seitlichen Lufteinlässen, "
        "Kanzel-Cockpit, großem freistehendem Heckflügel und breitem Diffusor."),
    # --- Küste (Azure Coast) ---
    "kueste_palme": ("Palme", "Eine einzelne, schlanke Kokospalme mit leicht gebogenem, geringeltem Stamm und dichter, frischgrüner Wedelkrone, etwa 5 m hoch."),
    "kueste_sonnenschirm": ("Strand-Sonnenschirm", "Ein aufgespannter, runder Strandsonnenschirm mit Stoffbespannung in Korallenrot und Creme gestreift, Holzmast, im Sand steckend (Sand nur als kleiner Kegel am Fuß)."),
    "kueste_bootshaus": ("Bootshaus", "Ein kleines hölzernes Bootshaus auf Pfählen mit Satteldach, verwittertem, hellblau gestrichenem Holz, offener Front zum Wasser und kleinem Steg davor."),
    "kueste_clubhaus": ("Clubhaus der Rennstrecke", "Ein modernes, flaches Clubhaus im mediterranen Stil: weiß verputzt, große Glasfront, Dachterrasse mit Geländer, Sonnensegel in Korallenrot."),
    "kueste_tribuene": ("Tribüne", "Eine kleine Zuschauertribüne aus Stahl mit sechs Sitzreihen (Sitze abwechselnd türkis und creme), Treppenaufgang und leichtem Flachdach auf Stützen."),
    "kueste_flutlicht": ("Flutlichtmast", "Ein hoher, schlanker Stahl-Flutlichtmast mit einer rechteckigen Leuchtengruppe aus acht Strahlern oben, Wartungsleiter am Mast, Betonfundament."),
    "kueste_laterne": ("Promenaden-Laterne", "Eine elegante Straßenlaterne für eine Strandpromenade: dunkelgrüner gusseiserner Mast, geschwungener Arm, Glaslaterne."),
    "kueste_steg": ("Holzsteg-Stück", "Ein gerades Stück eines hölzernen Bootsstegs mit verwitterten Planken, dicken Pfählen und einem Poller mit aufgewickeltem Tau."),
    "kueste_zeitnahme": ("Zeitnahme-Turm", "Ein schmaler, zweistöckiger Rennleitungsturm mit rundum verglaster Kanzel oben, Außentreppe und Antenne auf dem Dach."),
    "kueste_werbetafel": ("Werbetafel", "Eine große freistehende Werbetafel an der Rennstrecke auf zwei Stahlstützen, die Bildfläche ist komplett weiß und leer."),
    "kueste_reifenstapel": ("Reifenstapel", "Ein Reifenstapel als Streckenbegrenzung: drei gestapelte, zusammengebundene alte Autoreifen, der mittlere weiß gestrichen."),
    "kueste_leitplanke": ("Leitplanke", "Ein gerades, etwa 4 m langes Stück einer verzinkten Stahl-Leitplanke auf drei Pfosten, mit leichten Kratzern."),
    "kueste_pflanzkuebel": ("Pflanzkübel", "Ein länglicher Beton-Pflanzkübel voller blühender Bougainvillea und kleiner Agaven."),
    "kueste_felsen": ("Küstenfelsen", "Ein mittelgroßer, verwitterter heller Küstenfelsen mit rauer Oberfläche und etwas Flechten."),
    # --- Stadt (Downtown L) ---
    "stadt_altbau": ("Altbau-Stadthaus", "Ein vierstöckiges europäisches Altbau-Stadthaus mit Stuckfassade in warmem Sandton, hohen Sprossenfenstern, kleinen Balkonen und Flachdach mit Dachterrasse."),
    "stadt_eckladen": ("Eckhaus mit Laden", "Ein dreistöckiges Eckhaus aus rotem Backstein mit Ladengeschäft im Erdgeschoss (große Schaufenster, Markise, kein Schriftzug) und Wohnungen darüber."),
    "stadt_wohnblock": ("Wohnblock", "Ein moderner sechsstöckiger Wohnblock mit hellgrauer Fassade, durchgehenden Balkonbändern mit Glasgeländern und Flachdach."),
    "stadt_buero": ("Bürohaus", "Ein schlankes, achtstöckiges Bürogebäude mit Glasfassade in dunklem Blaugrün und schmalen Metallrahmen, Technikaufbau auf dem Dach."),
    "stadt_laterne": ("Straßenlaterne Stadt", "Eine moderne Straßenlaterne mit grauem Stahlmast und flachem, langem LED-Leuchtenkopf."),
    "stadt_schild_kurve": ("Verkehrsschild Kurve", "Ein Verkehrszeichen „Kurve rechts“ (roter Rand, weißes Dreieck, schwarzer Kurvenpfeil) an einem grauen Rohrpfosten, ohne Schrift."),
    "stadt_schild_kaputt": ("Beschädigtes Verkehrsschild", "Ein beschädigtes Verkehrszeichen: runder Richtungspfeil-Schild, verbogen und schief am geknickten Pfosten, zerkratzt, mit Rost und einer Delle, ohne Schrift."),
    "stadt_baum": ("Straßenbaum", "Eine junge Platane als Straßenbaum mit gleichmäßiger, runder Krone, Baumscheibe mit gusseisernem Gitter am Fuß."),
    "stadt_brunnen": ("Stadtbrunnen", "Ein runder Stadtbrunnen aus hellem Stein mit zweistufiger Schale in der Mitte, das Wasser als klare, stehende Oberfläche."),
    "stadt_bank": ("Parkbank", "Eine Parkbank mit gusseisernen Seitenteilen und Holzlatten."),
    "stadt_bushaltestelle": ("Bushaltestelle", "Ein modernes Bushaltestellen-Häuschen aus Glas und Stahl mit Sitzbank und leerer, weißer Plakatfläche an der Seite."),
    "stadt_absperrung": ("Absperrgitter", "Ein mobiles Absperrgitter aus verzinktem Stahl auf zwei Betonfüßen, mit rot-weißem Warnband."),
    "stadt_bake": ("Baustellenbake", "Eine Leitbake für Baustellen mit rot-weißen Schrägstreifen auf schwarzem Fuß, leicht verschmutzt."),
    # --- Wald (Forest Eight) ---
    "wald_kiefer": ("Kiefer", "Eine hohe, natürlich gewachsene Waldkiefer mit rötlich-schuppigem Stamm und unregelmäßiger, dunkelgrüner Nadelkrone."),
    "wald_eiche": ("Eiche", "Eine ausladende alte Eiche mit knorrigem Stamm und dichter, sattgrüner Laubkrone."),
    "wald_busch": ("Busch", "Ein dichter, runder Waldstrauch (Haselnuss) mit frischgrünen Blättern."),
    "wald_felsen": ("Bemooster Felsen", "Ein großer grauer Granitfelsen, oben teilweise mit Moos bewachsen."),
    "wald_baumstamm": ("Liegender Baumstamm", "Ein gefällter, liegender Baumstamm mit Rinde, abgesägten Enden mit Jahresringen und etwas Moos."),
    "wald_huette": ("Holzhütte", "Eine kleine Blockhütte aus dunklen Rundhölzern mit Schindeldach, Steinkamin, Veranda und kleinem Fenster."),
    "wald_laterne": ("Wegleuchte Wald", "Eine rustikale Wegleuchte: kurzer Holzpfosten mit einer schmiedeeisernen Laterne mit Glasscheiben oben."),
    "wald_zaun": ("Holzzaun", "Ein etwa 3 m langes Stück eines rustikalen Weidezauns aus gespaltenen Holzbalken, leicht schief."),
    "wald_wegweiser": ("Wegweiser (verwittert)", "Ein alter hölzerner Wegweiser mit drei leeren, verwitterten Richtungsbrettern ohne Schrift, eines davon abgebrochen und schief hängend."),
    "wald_holzstapel": ("Holzstapel", "Ein ordentlich gestapelter Stapel Brennholz-Scheite mit einer kleinen Plane obenauf."),
    "wald_baumstumpf": ("Baumstumpf", "Ein alter Baumstumpf mit Rinde, Pilzen am Fuß und Moos."),
    # ===== Runde 2 (27.09.2026): neue Strecken =====
    # --- Autos ---
    "auto_drift": ("Auto „Drift King“ – Drift-Coupé",
        "Ein breites, tiefergelegtes zweitüriges Heckantriebs-Coupé im Tuning-Stil: stark ausgestellte Kotflügel, "
        "leicht negativer Radsturz, flacher Heckflügel auf dem Kofferraumdeckel, tiefe Frontlippe, sportliche Felgen."),
    "auto_bergsprint": ("Auto „Col Racer“ – Bergsprint",
        "Ein sehr leichter, kleiner, offener zweisitziger Roadster ohne Dach mit Überrollbügeln hinter den Sitzen, "
        "kurzer Radstand, schmale Karosserie, runde Scheinwerfer, wirkt wendig und agil."),
    "auto_pickup": ("Auto „Quarry Truck“ – Pick-up",
        "Ein robuster, höhergelegter Pick-up mit Doppelkabine, grobstolligen Reifen, Ladefläche mit Überrollbügel "
        "und Zusatzscheinwerfern, kräftiger Rammschutz vorne."),
    # --- Hafenviertel ---
    "hafen_container": ("Container-Stapel", "Drei übereinander gestapelte Schiffscontainer aus Stahl mit Wellblechwänden, Farben rostrot, blaugrau und grün, leichte Gebrauchsspuren und Rost, ohne Schrift oder Logos."),
    "hafen_kran": ("Portalkran", "Ein großer Hafen-Portalkran aus rot-weißem Stahlfachwerk auf vier Stützen mit Laufkatze und Führerhaus."),
    "hafen_lagerhalle": ("Lagerhalle mit offenem Tor", "Eine lange Hafen-Lagerhalle aus Wellblech mit flachem Satteldach, an der Stirnseite ein großes, weit offenes Rolltor, durch das man hindurchfahren könnte; kein Schriftzug."),
    "hafen_poller": ("Hafenpoller", "Ein schwerer gusseiserner Hafenpoller, schwarz lackiert, mit um den Kopf gelegtem dickem Tau."),
    "hafen_faesser": ("Ölfässer", "Eine Gruppe aus sechs stehenden Stahlfässern, teils blau, teils rot lackiert, mit Dellen und Rost."),
    "hafen_paletten": ("Palettenstapel", "Ein Stapel aus acht hölzernen Europaletten, leicht verwittert, ohne Aufdrucke."),
    "hafen_gabelstapler": ("Gabelstapler", "Ein gelber Industrie-Gabelstapler mit Fahrerschutzdach und abgesenkter Gabel, ohne Schrift."),
    "hafen_frachtschiff": ("Kleines Frachtschiff", "Ein kleines Küstenfrachtschiff mit dunkelblauem Rumpf, weißem Brückenaufbau am Heck und einigen Containern an Deck, ganz ohne Wasser dargestellt."),
    "hafen_laterne": ("Hafen-Laterne", "Eine hohe Hafen-Straßenlaterne aus verzinktem Stahl mit zwei nach beiden Seiten auskragenden Leuchtenköpfen."),
    "hafen_absperrung_kaputt": ("Umgefahrene Absperrung", "Eine rot-weiße Baustellen-Absperrschranke, die umgefahren wurde: ein Fuß umgekippt, die Latte schräg am Boden liegend und leicht verbogen – ein Hinweis auf eine Durchfahrt."),
    # --- Jahrmarkt ---
    "jahrmarkt_riesenrad": ("Riesenrad", "Ein klassisches Jahrmarkts-Riesenrad aus weißem Stahl mit bunten Gondeln und vielen kleinen Glühlampen an den Speichen."),
    "jahrmarkt_karussell": ("Kettenkarussell", "Ein Kettenkarussell mit bunt bemaltem Dach, Sitzen an langen Ketten, im Stillstand, mit vielen kleinen Glühlampen am Dachrand."),
    "jahrmarkt_bude": ("Imbissbude", "Eine hölzerne Jahrmarkts-Imbissbude mit gestreiftem Vordach in Rot und Weiß, Theke, Lichterkette am Dachrand, ohne Schrift."),
    "jahrmarkt_losbude": ("Losbude", "Eine bunte Jahrmarkts-Losbude mit Regalen voller Plüsch-Preise, Vordach mit Glühlampen, ohne Schrift."),
    "jahrmarkt_zelt": ("Zirkuszelt", "Ein kleines rundes Zirkuszelt mit rot-gelb gestreifter Plane, spitzem Dach und Wimpeln."),
    "jahrmarkt_lichtermast": ("Lichtermast", "Ein schlanker Holzmast mit mehreren sternförmig abgespannten bunten Glühlampen-Ketten (nur der Mast mit den Ansätzen der Ketten)."),
    "jahrmarkt_autoscooter": ("Autoscooter-Halle", "Ein offenes Autoscooter-Fahrgeschäft: flaches Dach mit Lichterrand auf Stützen, darunter die glatte Fahrfläche mit einigen bunten Scootern."),
    "jahrmarkt_bruecke": ("Holzbrücke", "Eine kurze, breite Fahrbrücke aus Holzbohlen mit Stahlträgern und schlichtem Geländer, wie für ein Rennen über eine andere Straße hinweg."),
    # --- Serra-Pass (Steilküste, Serpentinen) ---
    "serra_fels": ("Kalkfelsen", "Ein großer, zerklüfteter heller Kalksteinfelsen, wie an einer mediterranen Steilküste, mit etwas Buschwerk in den Spalten."),
    "serra_trockenmauer": ("Trockenmauer", "Ein etwa 3 m langes Stück einer mediterranen Trockenmauer aus unregelmäßig geschichteten hellen Natursteinen."),
    "serra_leitplanke": ("Stein-Leitplanke", "Ein etwa 4 m langes Stück einer niedrigen Straßen-Schutzmauer aus hellem Naturstein mit abgerundeter Mauerkrone, wie an einer Bergstraße."),
    "serra_olivenbaum": ("Olivenbaum", "Ein knorriger, alter Olivenbaum mit gedrehtem Stamm und silbrig-grüner, lichter Krone."),
    "serra_pinie": ("Pinie", "Eine mediterrane Schirmpinie mit hohem, leicht gebogenem Stamm und flacher, schirmförmiger dunkelgrüner Krone."),
    "serra_agave": ("Agave", "Eine große Agave mit dicken, blaugrünen, spitzen Blättern."),
    "serra_kapelle": ("Bergkapelle", "Eine kleine weiße mediterrane Kapelle mit Glockengiebel, Holztür und Ziegeldach."),
    "serra_leuchtturm": ("Leuchtturm", "Ein weißer Leuchtturm mit roter Laterne auf einem kleinen Felssockel."),
    "serra_aussicht": ("Aussichtspunkt", "Ein kleiner gepflasterter Aussichtspunkt mit Steinbrüstung und einer Bank, wie an einer Küstenstraße."),
    # --- Steinbruch ---
    "steinbruch_felswand": ("Steinbruch-Felswand", "Ein Stück einer abgestuften Steinbruch-Felswand aus grauem Gestein mit waagerechten Abbaustufen."),
    "steinbruch_foerderband": ("Förderband", "Ein langes, schräg ansteigendes Förderband auf Stahlstützen, das Kies nach oben transportiert."),
    "steinbruch_bagger": ("Bagger", "Ein großer gelber Kettenbagger mit ausgefahrenem Arm und Schaufel, ohne Schrift."),
    "steinbruch_kipper": ("Muldenkipper", "Ein großer gelber Muldenkipper für den Steinbruch mit riesigen Reifen, ohne Schrift."),
    "steinbruch_kieshaufen": ("Kieshaufen", "Ein kegelförmiger Haufen aus grauem Kies und Schotter."),
    "steinbruch_brecher": ("Steinbrecher", "Eine Steinbrecher-Anlage aus Stahl mit Einfülltrichter, Treppen und Geländern."),
    "steinbruch_buero": ("Container-Büro", "Ein weißer Bürocontainer auf Stelzen mit Außentreppe und kleinem Fenster."),
    # --- Drift-Arena ---
    "drift_reifenwand": ("Reifenwand", "Eine gerade Wand aus drei Lagen gestapelter, zusammengeschraubter alter Autoreifen, abwechselnd schwarz und rot-weiß bemalt."),
    "drift_betonblock": ("Betonschutzwand", "Ein etwa 3 m langes Element einer Beton-Schutzwand (New-Jersey-Profil), grau mit Schrammen und Reifenabrieb."),
    "drift_pylone": ("Leitkegel", "Ein orange-weißer Verkehrs-Leitkegel aus Kunststoff."),
    "drift_flutlicht": ("Arena-Flutlicht", "Ein Flutlichtmast aus Gittermast-Stahl mit großer Leuchtengruppe oben."),
    "drift_zaun": ("Maschendrahtzaun", "Ein etwa 4 m langes Stück Maschendrahtzaun mit Stahlpfosten und Stacheldraht oben."),
    "drift_zuschauer_container": ("Zuschauer-Container", "Zwei übereinander gestapelte Container, der obere als Zuschauertribüne mit Geländer umgebaut, ohne Schrift."),
    "drift_parkhaus": ("Parkdeck", "Ein offenes zweistöckiges Beton-Parkdeck mit Rampe und Stützen, ohne Schrift."),
    # --- Kinderzimmer (Bonus) ---
    "kinder_bauklotz": ("Holzbauklotz", "Ein großer bunter Holzbauklotz (Würfel) mit abgerundeten Kanten, lackiert."),
    "kinder_bausteinturm": ("Bausteinturm", "Ein Turm aus bunten Steckbausteinen, leicht schief gebaut, ohne Markenlogo."),
    "kinder_buntstifte": ("Buntstifte", "Ein Bündel bunter Holz-Buntstifte, locker nebeneinander liegend."),
    "kinder_buch": ("Bilderbuch", "Ein aufgeklapptes, dickes Kinderbilderbuch mit leeren, hellen Seiten ohne Schrift, auf dem Rücken liegend."),
    "kinder_ball": ("Spielball", "Ein bunter Gummiball mit Streifen."),
    "kinder_teddy": ("Teddybär", "Ein sitzender, etwas abgeliebter Plüsch-Teddybär."),
    "kinder_holzeisenbahn": ("Holzeisenbahn", "Eine kleine Holzspielzeug-Lokomotive mit zwei Waggons, bunt lackiert."),
    "kinder_kreisel": ("Spielkreisel", "Ein bunt lackierter Holz-Spielkreisel."),
}

LIESMICH = """# Bildvorlagen für 3D-Modelle

Jede `.txt`-Datei in diesem Ordner ist ein vollständiger Bild-Prompt für genau ein Objekt. Die Bilder werden
anschließend lokal per Bild-zu-3D-KI in Modelle umgerechnet; deshalb sind alle Prompts mit denselben Bildregeln
versehen (freigestellt, ein Objekt, schräg von oben, weiches Licht, keine Schrift/Marken).

## Auftrag an die Bild-KI (z. B. ChatGPT)

> Geh bitte alle `.txt`-Dateien in diesem Ordner nacheinander durch. Erzeuge für jede Datei genau ein Bild, das
> exakt der Beschreibung in der Datei entspricht und alle dort genannten Bildregeln einhält. Speichere jedes Bild
> als PNG im Unterordner `bilder/` unter demselben Dateinamen wie die Beschreibung (z. B. `auto_sprint.txt` →
> `bilder/auto_sprint.png`). Überspringe Beschreibungen, zu denen in `bilder/` bereits ein Bild existiert. Die Perspektive-Regel ist verbindlich:
> Kamera links vorne, etwa 20–30° von oben, überwiegend Seitenansicht mit etwas Front; abgewandte Teile (z. B. die
> rechten Räder) dürfen und sollen verdeckt sein – niemals die Perspektive ändern, um mehr zu zeigen, und niemals
> von unten. Wenn ein Bild die Regeln nicht einhält (falsche Perspektive, Schrift, Logo, abgeschnitten, Boden oder
> Schatten sichtbar, mehr als ein Objekt), erzeuge es neu. Erfinde keine zusätzlichen Objekte und frage nicht nach,
> sondern halte dich an die Regeln.

## Reihenfolge

Runde 1 (fertig): `auto_*` (5 Autos), `kueste_*`, `stadt_*`, `wald_*`.

Runde 2 (neue Strecken) – nur Beschreibungen, zu denen es in `bilder/` noch kein Bild gibt:
1. `auto_drift`, `auto_bergsprint`, `auto_pickup`
2. `hafen_*`, `serra_*`
3. `jahrmarkt_*`, `steinbruch_*`
4. `drift_*`, `kinder_*`

Gern mehrere Varianten eines Objekts als `name_2.png`, `name_3.png` – die beste wird ausgewählt.

Erzeugt mit `tools/make_image_prompts.py`.
"""


def main():
    ROOT.mkdir(parents=True, exist_ok=True)
    (ROOT / "bilder").mkdir(exist_ok=True)
    (ROOT / "LIESMICH.md").write_text(LIESMICH, encoding="utf-8")
    for name, (titel, text) in OBJEKTE.items():
        extra = "\n\n" + AUTO_REGELN if name.startswith("auto_") else ""
        prompt = f"Objekt: {titel}\n\n{text}\n\n{REGELN}{extra}\n"
        (ROOT / f"{name}.txt").write_text(prompt, encoding="utf-8")
    print(len(OBJEKTE), "Beschreibungen in", ROOT)


if __name__ == "__main__":
    main()
