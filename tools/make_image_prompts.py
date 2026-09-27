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
}

LIESMICH = """# Bildvorlagen für 3D-Modelle

Jede `.txt`-Datei in diesem Ordner ist ein vollständiger Bild-Prompt für genau ein Objekt. Die Bilder werden
anschließend lokal per Bild-zu-3D-KI in Modelle umgerechnet; deshalb sind alle Prompts mit denselben Bildregeln
versehen (freigestellt, ein Objekt, schräg von oben, weiches Licht, keine Schrift/Marken).

## Auftrag an die Bild-KI (z. B. ChatGPT)

> Geh bitte alle `.txt`-Dateien in diesem Ordner nacheinander durch. Erzeuge für jede Datei genau ein Bild, das
> exakt der Beschreibung in der Datei entspricht und alle dort genannten Bildregeln einhält. Speichere jedes Bild
> als PNG im Unterordner `bilder/` unter demselben Dateinamen wie die Beschreibung (z. B. `auto_sprint.txt` →
> `bilder/auto_sprint.png`) und überschreibe dabei vorhandene Bilder. Die Perspektive-Regel ist verbindlich:
> Kamera links vorne, etwa 20–30° von oben, überwiegend Seitenansicht mit etwas Front; abgewandte Teile (z. B. die
> rechten Räder) dürfen und sollen verdeckt sein – niemals die Perspektive ändern, um mehr zu zeigen, und niemals
> von unten. Wenn ein Bild die Regeln nicht einhält (falsche Perspektive, Schrift, Logo, abgeschnitten, Boden oder
> Schatten sichtbar, mehr als ein Objekt), erzeuge es neu. Erfinde keine zusätzlichen Objekte und frage nicht nach,
> sondern halte dich an die Regeln.

## Reihenfolge

1. `auto_*` – die fünf Autos (Probe-Szene)
2. `kueste_*` – Küstenstrecke (Probe-Szene)
3. `stadt_*` und `wald_*`

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
