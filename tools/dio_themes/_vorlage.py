"""Vorlage für ein Themenmodul (tools/dio_themes/<thema>.py). Wird nie automatisch geladen (Name beginnt mit "_").

Kopieren nach tools/dio_themes/<thema>.py, wobei <thema> das Feld "theme" der Streckendatei ist (harbor, fair, forest, kids, quarry,
mountain, coast ...). Zum Ausprobieren ohne Kopie:
    tools/dio_build.ps1 -Track <id> -ThemeFile tools/dio_themes/_vorlage.py -Shots -Tag _probe
(Achtung: schreibt game/dioramas/<id>*; danach wieder löschen oder das richtige Thema bauen.)

Das Modul wird in die Globals von tools/diorama.py ausgeführt: Alle Kern-Helfer (mesh_object, box, flat, wall, cone, place, collide_rect,
ao_proxies ...) und Daten (data, HW, center, x0 ... z1, objs_ground, lamps, M ...) stehen in den Hook-Funktionen zur Verfügung. Auf der
obersten Ebene dürfen nur Konstanten und Funktionen stehen; Aufrufe der Helfer gehören in die Hooks (die Helfer entstehen erst danach).
Die vollständige Beschreibung steht in docs/dioramen/README.md.

Diese Vorlage macht eine Laufzeit-Fahrbahn ("runtime"): Das Spiel baut Straße, Randsteine, Rampen, Lücken, Schleifen und Abkürzungen wie ohne
Diorama; das Diorama liefert Boden und Szenerie. Eigener Boden: nur Objekte, deren Namen mit "Boden_" beginnen und die an objs_ground
angehängt werden, bekommen die gebackene Umgebungsverdeckung.
"""
THEME_CFG = {
    "road": "runtime",                 # "city" | "painted" | "runtime"
    # "ground_y": 0.08,                # Höhe des Bodens; bei "runtime" muss sie unter der Fahrbahn (0,17) liegen, Vorgabe 0,08
    "margin": 30.0,                    # Rand um die Mittellinie (m): Größe von Bodenraster und Lichttextur
    "baked": [],                       # Bausteintypen, die dieses Diorama selbst enthält (laufen nicht mehr zur Laufzeit); "ai:<modell>" je Modell
    "runtime_terrain": bool(data.get("terrain")),   # Strecke mit Geländerelief (track.terrain): das Spiel baut es weiter selbst
    # Bodentexturen der Mischung (Dateinamen ohne Endung, Normalkarte = Name + "_n"); eigene Texturen unter game/assets/dio/<thema>/
    "ground_set": {"grass": "res://assets/ground/gras", "sand": "res://assets/ground/sand", "dirt": "res://assets/ground/erde"},
    "ground_scales": {"grass": 4.0},   # Kachelgröße der Texturen in m (Vorgabe 3 / 4 / 3)
    # "ground_tints": {"grass": [0.9, 0.95, 0.85]},   # Farbton je Boden
    # "tints": {"D_Gras": [0.9, 0.95, 0.85]},          # Farbton einzelner D_*-Materialien (ergänzt DIORAMA_TINT in world.gd)
}


def theme_materials():
    """Hook 1: eigene Materialien eintragen, z. B. M["fels"] = material("D_Fels", tex("Rock030"), 0.9, tex("Rock030", "NormalGL"))."""


def theme_ground():
    """Hook 2: Boden, Gelände, Wasser. Hier: flacher Rasen aus 4-m-Kacheln über die ganze Fläche."""
    if data.get("terrain"):
        return                          # mit Laufzeit-Relief kein ebener Boden aus dem Diorama
    step = 4.0
    parts = []
    for x in np.arange(x0, x1, step):
        for z in np.arange(z0, z1, step):
            corners_ = [(x, z, GROUND_Y), (x + step, z, GROUND_Y), (x + step, z + step, GROUND_Y), (x, z + step, GROUND_Y)][::-1]
            parts.append(("gras", corners_, [(a / 3.0, -b / 3.0) for a, b, _ in corners_], None,
                          [ground_tint("gras", x + step / 2, z + step / 2)] * 4))
    objs_ground.append(mesh_object("Boden_gras", parts))


def theme_scenery():
    """Hook 3: Modelle, Bauten, Tribünen ... Für alles, was das Spiel zur Laufzeit setzt, Kontaktschatten ins Licht backen:"""
    ao_proxies()


def theme_bake_hidden():
    """Hook 4: Namenspräfixe von Objekten, die beim Backen der Umgebungsverdeckung unsichtbar sind (z. B. ein Wasserspiegel)."""
    return []


def theme_layout(layout):
    """Hook 5: Begleitdatei ergänzen, z. B. eigene Laternen: lamps.append((Vector((x, z)), Vector((x_zur_Straße, z_zur_Straße)))) im
    Hook 3 (danach schreibt der Kern sie als layout["lamps"])."""
