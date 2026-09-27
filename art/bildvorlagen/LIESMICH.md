# Bildvorlagen für 3D-Modelle

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
