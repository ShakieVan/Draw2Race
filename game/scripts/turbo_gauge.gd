class_name TurboGauge
extends Control

# Turbo-Knopf als Füllstandsanzeige (Nutzerwunsch 03.10.2026): Der Knopf selbst zeigt, wie voll der Turbo ist. Er füllt sich von
# unten, zeigt die Prozentzahl, beim Laden (Bremsen) leuchtet kurz ein „+“ auf, solange der Turbo zieht, pulsiert die Füllung.
# Vorher war es ein 6 px dünner Streifen unten im großen Knopf, der kaum auffiel.
# Nur Darstellung: liest RaceVehicle.turbo/boosting des eigenen Autos (app.me), ändert nichts an der Simulation.
# Die Füll- und Plus-Logik nutzen auch die Mehrspieler-Knöpfe (TurboPads) über die statischen Hilfen.

const FILL := Color("ed6948")          # Turbo-Orange (wie RaceHUD.ORANGE)
const FILL_BOOST := Color("ffb347")    # heller, solange der Turbo zieht
const PLUS_TIME := 0.7                 # so lange bleibt das „+“ nach dem letzten Laden sichtbar
const RADIUS := 14                     # wie die Knöpfe des HUD (RaceHUD.button)

var app: Node
var font: Font
var _fill := StyleBoxFlat.new()        # wiederverwendet (keine Stilobjekte je Bild)
var _last := -1.0                      # Ladung im letzten Bild
var _car_id := 0                       # Objekt des zuletzt gelesenen Autos (neues Rennen = neue Fahrzeuge)
var _plus := 0.0                       # Restzeit des „+“
var _time := 0.0
var tint := Color(0, 0, 0, 0)          # WLAN-Mehrspieler: Füllung in der Spielerfarbe (Alpha 0 = Turbo-Orange)

func setup(owner_node: Node, bold: Font) -> void:
	app = owner_node
	font = bold
	name = "TurboGauge"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func vehicle() -> RaceVehicle:
	if app == null or app.vehicles.is_empty() or app.me >= app.vehicles.size():
		return null
	return app.vehicles[app.me]

func _process(dt: float) -> void:
	_time += dt
	var v := vehicle()
	if v != null:
		if v.get_instance_id() != _car_id:
			_car_id = v.get_instance_id()
			_last = -1.0
			_plus = 0.0
		_plus = charge_plus(_last, v.turbo, _plus, dt)
		_last = v.turbo
	queue_redraw()

static func charge_plus(last: float, now: float, plus: float, dt: float) -> float:
	# Restzeit des „+“: neu gesetzt, sobald die Ladung steigt (Laden geht nur übers Bremsen), sonst läuft sie ab.
	if last >= 0.0 and now > last + 0.00001:
		return PLUS_TIME
	return maxf(0.0, plus - dt)

static func draw_fill(ci: CanvasItem, box: StyleBoxFlat, rect: Rect2, charge: float, color: Color, radius: int) -> void:
	# Füllung von unten, Höhe = Ladung. Unten die Rundung des Knopfs, oben flach, bis der Tank voll ist.
	var c := clampf(charge, 0.0, 1.0)
	if c <= 0.004:
		return
	var h := maxf(2.0, rect.size.y * c)
	box.bg_color = color
	var top := radius if c > 0.97 else 3
	box.corner_radius_top_left = top
	box.corner_radius_top_right = top
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	ci.draw_style_box(box, Rect2(rect.position.x, rect.end.y - h, rect.size.x, h))

static func boost_color(base: Color, time: float) -> Color:
	# Zieht der Turbo, pulsiert die Füllung leicht (4 Hz), damit man sieht, dass er gerade verbraucht wird.
	return base.lerp(Color.WHITE, 0.18 + 0.12 * sin(time * TAU * 4.0))

func _draw() -> void:
	var v := vehicle()
	if v == null:
		return
	var rect := Rect2(Vector2.ZERO, size)
	var base := tint if tint.a > 0.0 else FILL
	var color := boost_color(FILL_BOOST if tint.a <= 0.0 else tint.lightened(0.25), _time) if v.boosting else base
	draw_fill(self, _fill, rect, v.turbo, color, RADIUS)
	var ink := Color.WHITE
	var outline := Color(0.04, 0.16, 0.18, 0.9)
	var word := "TURBO"
	var ww := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	var mid := size.x * 0.5
	draw_string_outline(font, Vector2(mid - ww * 0.5, size.y * 0.42), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, 8, outline)
	draw_string(font, Vector2(mid - ww * 0.5, size.y * 0.42), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, ink)
	var pct := "%d %%" % int(round(clampf(v.turbo, 0.0, 1.0) * 100.0))
	var pw := font.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	draw_string_outline(font, Vector2(mid - pw * 0.5, size.y * 0.74), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 8, outline)
	draw_string(font, Vector2(mid - pw * 0.5, size.y * 0.74), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ink)
	if _plus > 0.0:
		# „+“ oben rechts, blendet nach dem letzten Laden aus.
		var a := clampf(_plus / PLUS_TIME, 0.0, 1.0)
		var pos := Vector2(size.x - 44.0, 44.0 - 6.0 * (1.0 - a))
		draw_string_outline(font, pos, "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, 8, Color(outline, a))
		draw_string(font, pos, "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(1.0, 0.95, 0.7, a))
