class_name PlayerColors
extends RefCounted

# Spielerfarben im Mehrspieler (Nutzerentscheidung „Autowahl“ vom 03.10.2026, docs/MULTIPLAYER_RECHERCHE.md Abschnitt 9): Mehrere
# Spieler dürfen dasselbe Auto fahren. Erkennbar bleibt jeder an seiner eigenen Farbe: Lack, Namensschild, Lichtkranz, Turbo-Knopf,
# Linie, Enthüllung, Wertung. Einzelspieler und KI-Gegner behalten die Farben der Autos (RaceVehicle.CARS[].color).
# - Palette: sechs kräftige Farben, die sich auch bei Rot-Grün-Schwäche deutlich unterscheiden. Geprüft wird mit distance(): kleinster
#   OKLab-Abstand bei normalem Sehen, Protanopie und Deuteranopie (Simulation nach Machado, Oliveira, Fernandes 2009, Schweregrad 1).
#   Jedes Paar liegt bei mindestens 0,14; eben unterscheidbar ist etwa 0,02.
# - Vorgabe je Platz: die vier mit dem größten Mindestabstand untereinander (Rot, Himmelblau, Gelb, Lila, mindestens 0,24).
# - Jede Farbe gibt es in einer Runde höchstens einmal. Wer eine belegte wünscht, bekommt die nächste freie (wie gleiche Namen eine
#   Ziffer bekommen): free_color().
# - KI-Gegner: rival_order() wählt Autos, deren Farbe sich von allen Spielerfarben um mindestens CLASH abhebt.
# Reine Darstellung: Farben ändern nie die Simulation.

const PALETTE := [
	{"name": "Rot", "color": "e53935"},
	{"name": "Himmelblau", "color": "33bbee"},
	{"name": "Gelb", "color": "f0e442"},
	{"name": "Lila", "color": "7b3fc4"},
	{"name": "Orange", "color": "e69f00"},
	{"name": "Weiß", "color": "f2f2f2"},
]
const CLASH := 0.12               # KI-Autofarbe gilt ab diesem Abstand (distance) als deutlich anders als eine Spielerfarbe

# Simulation der Farbwahrnehmung (lineares RGB, Machado et al. 2009, Schweregrad 1,0)
const _CVD := [
	[[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],   # Protanopie
	[[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],   # Deuteranopie
]

static func count() -> int:
	return PALETTE.size()

static func color(index: int) -> Color:
	return Color(str(PALETTE[posmod(index, PALETTE.size())].color))

static func color_name(index: int) -> String:
	return str(PALETTE[posmod(index, PALETTE.size())].name)

static func default_for(slot: int) -> int:
	# Vorgabe für den Spieler auf Platz slot (0 = erster): Rot, Himmelblau, Gelb, Lila.
	return posmod(slot, PALETTE.size())

static func free_color(wanted: int, taken: Array) -> int:
	# Gewünschte Farbe oder, wenn ein anderer sie hat, die nächste freie in Palettenfolge (alle belegt: die gewünschte).
	var n := PALETTE.size()
	for k in range(n):
		var c := posmod(wanted + k, n)
		if not c in taken:
			return c
	return posmod(wanted, n)

static func _oklab(rgb: Vector3) -> Vector3:
	var r := clampf(rgb.x, 0.0, 1.0)
	var g := clampf(rgb.y, 0.0, 1.0)
	var b := clampf(rgb.z, 0.0, 1.0)
	var l := pow(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 1.0 / 3.0)
	var m := pow(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 1.0 / 3.0)
	var s := pow(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 1.0 / 3.0)
	return Vector3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)

static func _seen(c: Color, matrix: Array) -> Vector3:
	var lin := c.srgb_to_linear()
	var v := Vector3(lin.r, lin.g, lin.b)
	if not matrix.is_empty():
		v = Vector3(matrix[0][0] * v.x + matrix[0][1] * v.y + matrix[0][2] * v.z,
			matrix[1][0] * v.x + matrix[1][1] * v.y + matrix[1][2] * v.z,
			matrix[2][0] * v.x + matrix[2][1] * v.y + matrix[2][2] * v.z)
	return _oklab(v)

static func distance(a: Color, b: Color) -> float:
	# Wie verschieden zwei Farben aussehen: kleinster OKLab-Abstand bei normalem Sehen, Protanopie und Deuteranopie.
	var d := _seen(a, []).distance_to(_seen(b, []))
	for matrix in _CVD:
		d = minf(d, _seen(a, matrix).distance_to(_seen(b, matrix)))
	return d

static func rival_order(cars: Array, human_cars: Array, paints: Array) -> Array:
	# KI-Autos (Indizes in RaceVehicle.CARS, Reihenfolge cars) so sortiert, dass zuerst die kommen, deren Farbe sich von allen
	# Spielerfarben paints abhebt (distance ≥ CLASH) – davon zuerst Autos, die kein Mensch fährt –, dann die übrigen nach Abstand.
	# Innerhalb gleicher Stufe bleibt die Reihenfolge von cars (je Strecke fest, main.rival_lineup_excluding).
	var scored: Array = []
	for k in range(cars.size()):
		var car := int(cars[k])
		var gap := INF
		for p in paints:
			gap = minf(gap, distance(Color(str(RaceVehicle.CARS[car].color)), p))
		var clear := gap >= CLASH
		scored.append({"car": car, "tier": (0 if clear else 2) + (1 if clear and car in human_cars else 0), "gap": gap, "k": k})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.tier != b.tier:
			return a.tier < b.tier
		if a.tier == 2 and a.gap != b.gap:
			return a.gap > b.gap
		return a.k < b.k)
	return scored.map(func(e: Dictionary): return int(e.car))
