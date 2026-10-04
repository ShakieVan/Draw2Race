class_name TurboPads
extends Control

# Turboknöpfe im Mehrspieler „Weitergeben“ (M2b): je Mensch ein großer Knopf in seiner Farbe und mit seinem Namen, jeder in einer
# eigenen Bildschirmecke, damit mehrere Leute rund um ein Handy gleichzeitig drücken können. Spieler 1 unten rechts (wie der
# Einzelspieler-Knopf), Spieler 2 unten links, Spieler 3 oben rechts, Spieler 4 oben links. Oben rücken die Knöpfe unter die
# Kopfleiste, wenn sie neben ihr keinen Platz haben (schmale Bildschirme).
# Nur Darstellung und Trefferprüfung; welche Finger welchen Knopf halten, verwaltet main.gd (pad_touch/pad_held, Mehrfachberührung
# über InputEventScreenTouch, nicht über die Knopf-Logik der Oberfläche, die nur einen Finger kennt).
# Je Knopf: Name, Platz (Drift: Punkte); der Knopf selbst ist die Turbo-Anzeige (wie TurboGauge): dunkel getönt = leer, von unten in
# der Spielerfarbe gefüllt, Prozentzahl, „+“ beim Laden, pulsierend, solange der Turbo zieht; gehalten mit weißem Rand.

const SIZE := Vector2(268, 156)
const MARGIN := 16.0
const INK := Color("173a40")
const WORD_SIZE := 40           # „TURBO“

var app: Node
var font: Font
var cars: Array[int] = []        # Autoindex je Knopf
var players: Array[int] = []     # Spielerindex je Knopf (Ecke)
var rects: Array[Rect2] = []
var colors: Array[Color] = []
var names: Array[String] = []
var _box := StyleBoxFlat.new()     # wiederverwendet (keine neuen Stilobjekte je Bild)
var _back := StyleBoxFlat.new()
var _front := StyleBoxFlat.new()
var _last := PackedFloat32Array()    # Ladung je Knopf im letzten Bild (für das „+“)
var _plus := PackedFloat32Array()    # Restzeit des „+“ je Knopf
var _time := 0.0

func setup(owner_node: Node, bold: Font) -> void:
	app = owner_node
	font = bold
	name = "TurboPads"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func show_pads(car_list: Array[int], player_list: Array[int], color_list: Array[Color], name_list: Array[String]) -> void:
	cars = car_list
	players = player_list
	colors = color_list
	names = name_list
	_last.resize(cars.size())
	_last.fill(-1.0)
	_plus.resize(cars.size())
	_plus.fill(0.0)
	layout()
	visible = not cars.is_empty()
	queue_redraw()

func hide_pads() -> void:
	cars.clear()
	players.clear()
	rects.clear()
	visible = false

func corner_rect(player: int) -> Rect2:
	# Ecke je Spieler (siehe oben), in Bildschirmkoordinaten.
	var screen := get_viewport_rect().size
	var top := MARGIN
	if app != null and app.hud != null and app.hud.content != null:
		# Kopfleiste: x content.x + 32 … + 1408, bis y content.y + 110.
		var c: Vector2 = app.hud.content.position
		if c.x + 32.0 < MARGIN + SIZE.x + 8.0:
			top = c.y + 124.0
	var left := player % 2 == 1
	var upper := player >= 2
	var x := MARGIN if left else screen.x - MARGIN - SIZE.x
	var y := top if upper else screen.y - MARGIN - SIZE.y
	return Rect2(Vector2(x, y), SIZE)

func layout() -> void:
	rects.clear()
	for k in range(cars.size()):
		rects.append(corner_rect(players[k]))

func pad_at(pos: Vector2) -> int:
	# Autoindex des Knopfs unter pos (etwas großzügiger als gezeichnet), sonst -1.
	for k in range(rects.size()):
		if rects[k].grow(10.0).has_point(pos):
			return cars[k]
	return -1

func _process(dt: float) -> void:
	if visible:
		if rects.size() != cars.size():
			layout()
		_time += dt
		if app != null and _plus.size() == cars.size():
			for k in range(cars.size()):
				if cars[k] < app.vehicles.size():
					var charge: float = app.vehicles[cars[k]].turbo
					_plus[k] = TurboGauge.charge_plus(_last[k], charge, _plus[k], dt)
					_last[k] = charge
		queue_redraw()

func _draw() -> void:
	if app == null:
		return
	var drift: bool = app.track.mode == "drift"
	for k in range(mini(rects.size(), cars.size())):
		var car := cars[k]
		if car >= app.vehicles.size():
			continue
		var v: RaceVehicle = app.vehicles[car]
		var held := bool(app.pad_held.get(car, false))
		var rect := rects[k]
		if held:
			rect = rect.grow(5.0)
		var base := colors[k]
		var done := v.finish_time >= 0.0 or v.crashed
		var fill := base.lightened(0.18) if held else base
		var alpha := 0.55 if done else 0.9
		var box := _box
		box.bg_color = Color(base.darkened(0.62), alpha)   # leerer Tank
		box.set_corner_radius_all(26)
		box.set_border_width_all(5 if held else 3)
		box.border_color = Color(1, 1, 1, 0.95) if held else Color(0.02, 0.07, 0.09, 0.7)
		box.shadow_color = Color(0, 0, 0, 0.35)
		box.shadow_size = 8
		box.shadow_offset = Vector2(0, 3)
		draw_style_box(box, rect)
		# Füllung von unten in der Spielerfarbe (innerhalb des Rands); zieht der Turbo, pulsiert sie.
		var inner := rect.grow(-float(box.border_width_left))
		var tone := TurboGauge.boost_color(fill, _time) if v.boosting else fill
		TurboGauge.draw_fill(self, _front, inner, v.turbo, Color(tone, alpha), 22)
		var light := true   # Schrift immer hell mit Kontur: liegt teils über dunkler, teils über farbiger Fläche
		var ink := Color(1, 1, 1, 0.97) if light else Color(INK, 0.97)
		var outline := Color(0.02, 0.07, 0.09, 0.8)
		var pad := 16.0
		# Name oben links, Platz bzw. Punkte oben rechts.
		var name_text := names[k] if k < names.size() else ""
		_text(Vector2(rect.position.x + pad, rect.position.y + 34.0), name_text, 24, ink, outline, light)
		var place := ""
		if drift:
			place = "%d" % int(v.drift_score)
		elif v.crashed:
			place = "raus"
		else:
			place = "%d." % app.car_rank(car)
		var pw := font.get_string_size(place, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
		_text(Vector2(rect.end.x - pad - pw, rect.position.y + 38.0), place, 30, ink, outline, light)
		# Großes TURBO in der Mitte (im Ziel: ZIEL).
		var word := "ZIEL" if v.finish_time >= 0.0 else ("AUS" if v.crashed else "TURBO")
		var ww := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, WORD_SIZE).x
		_text(Vector2(rect.get_center().x - ww * 0.5, rect.position.y + 98.0), word, WORD_SIZE, ink, outline, light)
		# Prozent unten; „+“ beim Laden rechts neben TURBO (rechts oben steht der Platz).
		var pct := "%d %%" % int(round(clampf(v.turbo, 0.0, 1.0) * 100.0))
		var qw := font.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		_text(Vector2(rect.get_center().x - qw * 0.5, rect.end.y - 16.0), pct, 26, ink, outline, light)
		if k < _plus.size() and _plus[k] > 0.0:
			var a := clampf(_plus[k] / TurboGauge.PLUS_TIME, 0.0, 1.0)
			_text(Vector2(rect.get_center().x + ww * 0.5 + 8.0, rect.position.y + 92.0 - 6.0 * (1.0 - a)), "+", 38, Color(1.0, 0.95, 0.7, a), Color(outline, a), true)

func _text(pos: Vector2, text: String, size: int, color: Color, outline: Color, with_outline: bool) -> void:
	if with_outline:
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, outline)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
