class_name NameTags
extends Control

# Namensschilder und Sprechblasen über den Autos (M1, docs/MULTIPLAYER_RECHERCHE.md 6) – 2D im HUD gezeichnet, an die
# 3D-Autopositionen geheftet (Camera3D.unproject_position). Reine Darstellung: liest Kamera, Modelle und Fahrzeuge, ändert nichts.
# Regeln:
# - Das Schild sitzt hinter dem Auto (Bildschirm-Gegenrichtung der Fahrt, leicht nach oben gezogen): Es verdeckt nie die Fahrbahn
#   und die Linie vor dem Auto. Die Richtung gleitet weich nach, damit das Schild nicht springt.
# - Gleich große Schrift, beim Herauszoomen etwas kleiner (bis 78 %); überlappende Schilder werden auseinandergeschoben.
# - Schilder und Blasen weichen den Autos aus (kein Auto wird verdeckt). Mein Schild ist größer, weiß umrandet und liegt obenauf;
#   ein fremdes Schild, das trotzdem über meinem Auto liegt, verliert seinen Kasten und bleibt nur als umrandete Schrift (verdeckt
#   kaum etwas und sieht nachts nicht wie ein leerer grauer Kasten aus).
# - Mehrspieler auf einem Handy: alle Menschen gelten als „eigene“ Autos (größeres Schild, obenauf); Turboknöpfe sind Hindernisse.
# - Schriftgrößen wie im HUD (RaceHUD.readable), auf dem Handy 3 px größer.
# - Auto außerhalb des Bildes: Schild klebt am Bildrand (unter der Kopfleiste) mit einem Pfeil zum Auto.
# - Im Ziel blasser, ausgeschieden noch blasser (und nicht mehr am Rand).
# - Sprechblase (RaceChatter) außen am Schild, „Plopp“ beim Erscheinen, verblasst am Ende; ohne Schilder direkt am Auto.
# Lesbar bei Tag und Nacht: Schild in der Autofarbe mit dunklem Rand und Schatten, Schrift hell mit Kontur oder dunkel.

const AI_NAMES := ["Flinke Fee", "Greta Grip", "Rallye-Rudi", "Donner-Dora", "Ada Apex", "Paula Pass", "Kalle Kipper",
	"Drift-Dieter"]   # KI-Fahrer je Karosserie (Index in RaceVehicle.CARS): dasselbe Auto hat immer denselben Fahrer
const INK := Color("173a40")
const ORANGE := Color("ed6948")
const LIFT := 0.4           # m: Bezugspunkt über dem Boden (Wagenmitte)
const CAR_HALF := 1.8       # m: so weit um den Bezugspunkt gilt das Auto als Hindernis für Schilder
const GAP := 26.0           # px zwischen Auto und Schild
const EDGE := 14.0          # px Rand beim Anheften
const FONT_SIZE := 17       # Grundgrößen im HUD-Maß: readable() macht daraus 21 / 24 / 23 px, auf dem Handy je +PHONE_EXTRA
const OWN_SIZE := 20
const BUBBLE_SIZE := 19
const PHONE_EXTRA := 3
static var phone := OS.has_feature("mobile")   # Handy-Schriftgröße (Aufnahmen am PC können sie einschalten)

var app: Node
var font: Font
var box := StyleBoxFlat.new()
var dirs := {}              # Auto -> geglättete Schild-Richtung (Bildschirm)
var drawn: Array = []       # zuletzt gezeichnet (Tests/Aufnahmen): [{car, kind: "tag"/"bubble", rect, pinned, alpha, text, faded}]
# Wiederverwendete Puffer für _draw (schwache Geräte: keine Speicheranforderungen je Bild, keine Lambdas, keine Array-Literale).
var _order: Array[int] = []
var _placed: Array[Rect2] = []
var _own_boxes: Array[Rect2] = []
var _party := false         # Mehrspieler auf einem Handy (je Bild aus app.party)
var _radius := PackedFloat64Array()
var _slots: Array[TagSlot] = []
var _drawn_pool: Array[Dictionary] = []
var _drawn_n := 0
var _moves := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _tri := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])

class TagSlot:
	# Ein Schild dieses Bilds (aus dem Vorrat _slots).
	var car := 0
	var rect := Rect2()
	var p := Vector2.ZERO
	var dir := Vector2.ZERO
	var pinned := false
	var edge := Vector2.ZERO
	var alpha := 1.0
	var text := ""
	var fs := 0
	var own := false
	var faded := false      # fremdes Schild über einem eigenen Auto: nur Schrift, kein Kasten
	var color := Color()
	var gap := 0.0

func setup(owner_node: Node, bold: Font) -> void:
	app = owner_node
	font = bold
	name = "NameTags"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

static func unique_name(wanted: String, taken: Array) -> String:
	# Gleiche Namen bekommen eine Ziffer („Anna“, „Anna 2“ …), höchstens ProgressStore.NAME_MAX Zeichen (wie NetProtocol).
	if not taken.has(wanted):
		return wanted
	for n in range(2, 100):
		var suffix := " %d" % n
		var candidate := wanted.left(ProgressStore.NAME_MAX - suffix.length()).strip_edges() + suffix
		if not taken.has(candidate):
			return candidate
	return wanted

static func names_for(entries: Array, looks: Array, me: int, own_name: String) -> Array[String]:
	# Anzeigenamen je Auto: Name aus der Teilnehmerliste, sonst mein Name (me), andere Menschen „Spieler n“, KI ihr Fahrer zur
	# Karosserie. Menschen zuerst vergeben, damit bei Gleichstand die KI die Ziffer bekommt.
	var names: Array[String] = []
	names.resize(entries.size())
	var taken: Array = []
	for pass_humans in [true, false]:
		for i in range(entries.size()):
			var e: Dictionary = entries[i]
			var human := bool(e.get("human", false))
			if human != pass_humans:
				continue
			var wanted := ProgressStore.clean_name(str(e.get("name", "")))
			if wanted == "":
				if human:
					wanted = ProgressStore.clean_name(own_name) if i == me else "Spieler %d" % (i + 1)
					if wanted == "":
						wanted = "Spieler %d" % (i + 1)
				else:
					var look := int(looks[i]) if i < looks.size() else int(e.get("car", 0))
					wanted = AI_NAMES[posmod(look, AI_NAMES.size())]
			names[i] = unique_name(wanted, taken)
			taken.append(names[i])
	return names

static func size_for(base: int) -> int:
	return RaceHUD.readable(base) + (PHONE_EXTRA if phone else 0)

func is_own(i: int) -> bool:
	# Eigene Autos: meins; im Mehrspieler auf einem Handy alle Menschen (alle schauen auf denselben Bildschirm).
	if i == int(app.me):
		return true
	return _party and app.field.is_human(i)

func show_names() -> bool:
	return bool(app.store.data.get("show_names", true))

func show_bubbles() -> bool:
	return bool(app.store.data.get("bubbles", true))

func _process(_dt: float) -> void:
	var phase: String = app.phase if app != null else ""
	var on: bool = (phase == "countdown" or phase == "race" or phase == "result") and not app.vehicles.is_empty() \
		and app.models.size() == app.vehicles.size() and (show_names() or show_bubbles())
	visible = on
	if on:
		queue_redraw()
	else:
		drawn.clear()

func area() -> Rect2:
	# Erlaubter Bereich für Schilder: ganzer Bildschirm ohne Rand und Kopfleiste.
	var screen := get_viewport_rect().size
	var top := EDGE
	if app.hud != null and app.hud.content != null:
		top = maxf(EDGE, app.hud.content.position.y + 118.0)
	return Rect2(EDGE, top, screen.x - 2.0 * EDGE, maxf(10.0, screen.y - top - EDGE))

func zoom_scale() -> float:
	return clampf(remap(float(app.cam_zoom), 30.0, 120.0, 1.0, 0.78), 0.78, 1.0)

func _draw() -> void:
	_drawn_n = 0
	if app == null or app.vehicles.is_empty():
		drawn.resize(0)
		return
	var cam: Camera3D = app.camera
	var bounds := area()
	var mid := bounds.get_center()
	var k := zoom_scale()
	var me: int = app.me
	var count: int = mini(app.vehicles.size(), app.models.size())
	var names: Array = app.car_names
	var names_on := show_names()
	var bubbles_on := show_bubbles()
	var dt := get_process_delta_time()
	_party = app.get(&"party") != null and app.field != null
	# Mein Auto zuerst platzieren, dann die übrigen eigenen (Mehrspieler), dann der Rest nach Startplatz.
	_order.resize(0)
	if me < count:
		_order.append(me)
	for i in range(count):
		if i != me and is_own(i):
			_order.append(i)
	for i in range(count):
		if i != me and not is_own(i):
			_order.append(i)
	# Die Autos selbst sind Hindernisse: Schilder und Blasen weichen ihnen aus und verdecken so kein Auto.
	_placed.resize(0)
	if _radius.size() < count:
		_radius.resize(count)
	_radius.fill(0.0)
	_own_boxes.resize(0)
	for i in range(count):
		var model: Node3D = app.models[i]
		if not is_instance_valid(model) or not model.visible:
			continue
		var c3 := model.global_position + Vector3(0, LIFT, 0)
		if cam.is_position_behind(c3):
			continue
		var c := cam.unproject_position(c3)
		var r := clampf(cam.unproject_position(c3 + cam.global_basis.x * CAR_HALF).distance_to(c), 12.0, 90.0)
		_radius[i] = r
		var body := Rect2(c - Vector2(r, r), Vector2(2.0 * r, 2.0 * r))
		if is_own(i):
			_own_boxes.append(body.grow(-0.3 * r))
		if bounds.grow(r).has_point(c):
			_placed.append(body)
	# Turboknöpfe (Mehrspieler) halten Schilder und Blasen fern.
	var pads: TurboPads = app.hud.pads if app.hud != null else null
	if pads != null and pads.visible:
		for r in pads.rects:
			_placed.append(r.grow(6.0))
	var own_fs := size_for(OWN_SIZE)
	var other_fs := size_for(FONT_SIZE)
	var n := 0
	for i in _order:
		var model: Node3D = app.models[i]
		var v: RaceVehicle = app.vehicles[i]
		if not is_instance_valid(model) or not model.visible:
			continue
		var anchor := model.global_position + Vector3(0, LIFT, 0)
		var behind := cam.is_position_behind(anchor)
		var p := cam.unproject_position(anchor)
		if behind:
			p = mid + (mid - p) * 4.0
		var pinned := behind or not bounds.has_point(p)
		if pinned and v.crashed:
			continue
		var own := is_own(i)
		# Richtung des Schilds: gegen die Fahrt auf dem Bildschirm, leicht nach oben; weich nachgeführt.
		var want := Vector2(0, -1)
		if not pinned:
			var ahead := cam.unproject_position(anchor + Vector3(v.velocity.x, 0, v.velocity.y) * 0.3)
			var travel := ahead - p
			if travel.length() > 3.0:
				want = (Vector2(0, -0.35) - travel.normalized()).normalized()
				if want.length() < 0.5:
					want = Vector2(-1, 0)
		var dir: Vector2 = dirs.get(i, want)
		dir = dir.lerp(want, 1.0 - exp(-dt * 6.0)).normalized() if dt > 0.0 else want
		if dir.length() < 0.5:
			dir = want
		dirs[i] = dir
		var text: String = str(names[i]) if i < names.size() else ("DU" if own else "Auto %d" % (i + 1))
		var fs := int(round((own_fs if own else other_fs) * k))
		var tsize := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var box_size := Vector2(tsize.x + 22.0 * k, font.get_height(fs) + 8.0 * k)
		var center: Vector2
		var edge_dir := Vector2.ZERO
		if pinned:
			# Am Bildrand auf der Linie Bildmitte → Auto, innerhalb des erlaubten Bereichs.
			var d := (p - mid)
			if d.length() < 1.0:
				d = Vector2(0, -1)
			var half := bounds.size * 0.5 - box_size * 0.5 - Vector2(14, 14) * k
			var t := minf(half.x / maxf(absf(d.x), 0.001), half.y / maxf(absf(d.y), 0.001))
			center = mid + d * t
			edge_dir = d.normalized()
		else:
			var gap := maxf(GAP * k, _radius[i] + 4.0)
			center = p + dir * (gap + 0.5 * (absf(dir.x) * box_size.x + absf(dir.y) * box_size.y))
		var rect := Rect2(center - box_size * 0.5, box_size)
		rect = _separate(rect, _placed, bounds)
		var alpha := 1.0 if own else 0.92
		if pinned:
			alpha = 0.82
		if v.finish_time >= 0.0:
			alpha *= 0.6
		if v.crashed:
			alpha *= 0.45
		var faded := false
		if not own:
			for b in _own_boxes:
				if rect.intersects(b):
					faded = true    # liegt trotz Ausweichen über einem eigenen Auto: nur als umrandete Schrift
					break
		if app.phase == "countdown":
			alpha = maxf(alpha, 0.92)
		if names_on:
			_placed.append(rect)
		if n >= _slots.size():
			_slots.append(TagSlot.new())
		var slot: TagSlot = _slots[n]
		slot.car = i
		slot.rect = rect
		slot.p = p
		slot.dir = dir
		slot.pinned = pinned
		slot.edge = edge_dir
		slot.alpha = alpha
		slot.text = text
		slot.fs = fs
		slot.own = own
		slot.faded = faded
		slot.color = _car_color(i)
		slot.gap = _radius[i] + 4.0
		n += 1
	if names_on:
		# Fremde zuerst, mein Schild obenauf.
		for j in range(n):
			if not _slots[j].own:
				_draw_tag(_slots[j], k)
		for j in range(n):
			if _slots[j].own:
				_draw_tag(_slots[j], k)
	if bubbles_on and app.get("chatter") != null:
		# Meine Blase zuerst (sie weicht nicht aus), dann die übrigen.
		var chatter: RaceChatter = app.chatter
		var now := float(app.race_time)
		for j in range(n):
			var b: Dictionary = chatter.active(_slots[j].car, now)
			if not b.is_empty():
				_draw_bubble(_slots[j], b, k, names_on, bounds, _placed)
	# drawn zeigt genau die Einträge dieses Bilds (aus dem Vorrat; gleiche Länge wie zuvor = keine neue Liste).
	drawn.resize(_drawn_n)
	for j in range(_drawn_n):
		drawn[j] = _drawn_pool[j]

func _record(car: int, kind: String, rect: Rect2, pinned: bool, alpha: float, text: String, faded := false) -> void:
	# Eintrag für drawn aus dem Vorrat: {car, kind, rect, pinned, alpha, text, faded}.
	if _drawn_n >= _drawn_pool.size():
		_drawn_pool.append({"car": 0, "kind": "", "rect": Rect2(), "pinned": false, "alpha": 0.0, "text": "", "faded": false})
	var d: Dictionary = _drawn_pool[_drawn_n]
	d.car = car
	d.kind = kind
	d.rect = rect
	d.pinned = pinned
	d.alpha = alpha
	d.text = text
	d.faded = faded
	_drawn_n += 1

func _car_color(i: int) -> Color:
	var model: Node3D = app.models[i]
	if model.has_meta("tag_color"):
		return model.get_meta("tag_color")
	return Color("6d7a7c")

func _separate(rect: Rect2, placed: Array[Rect2], bounds: Rect2) -> Rect2:
	# Überlappende Schilder/Blasen auseinanderschieben: je Überdeckung der kürzeste der vier Wege (links, rechts, hoch, runter)
	# heraus, der im erlaubten Bereich bleibt; passt keiner, der kürzeste überhaupt. Die vier Wege liegen in einem festen Puffer,
	# stabil nach Länge sortiert (bei Gleichstand bleibt die Reihenfolge links, rechts, hoch, runter).
	rect = _clamp_rect(rect, bounds)
	for _n in range(8):
		var moved := false
		for q in placed:
			var r := rect.grow(3.0)
			if not r.intersects(q):
				continue
			_moves[0] = Vector2(q.end.x - r.position.x, 0)
			_moves[1] = Vector2(q.position.x - r.end.x, 0)
			_moves[2] = Vector2(0, q.end.y - r.position.y)
			_moves[3] = Vector2(0, q.position.y - r.end.y)
			for a in range(1, 4):
				var m := _moves[a]
				var b := a - 1
				while b >= 0 and m.length() < _moves[b].length():
					_moves[b + 1] = _moves[b]
					b -= 1
				_moves[b + 1] = m
			var pick: Vector2 = _moves[0]
			for a in range(4):
				if bounds.encloses(Rect2(rect.position + _moves[a], rect.size)):
					pick = _moves[a]
					break
			rect.position += pick
			moved = true
		if not moved:
			break
	return rect

func _clamp_rect(rect: Rect2, bounds: Rect2) -> Rect2:
	rect.position.x = clampf(rect.position.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - rect.size.x))
	rect.position.y = clampf(rect.position.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - rect.size.y))
	return rect

func _edge_point(rect: Rect2, toward: Vector2) -> Vector2:
	# Punkt auf dem Rand von rect in Richtung toward (von der Mitte aus).
	var c := rect.get_center()
	var d := toward - c
	if d.length() < 0.001:
		return c
	var half := rect.size * 0.5
	var t := minf(half.x / maxf(absf(d.x), 0.001), half.y / maxf(absf(d.y), 0.001))
	return c + d * minf(t, 1.0)

func _style(bg: Color, border: Color, width: int, radius: float, shadow: float) -> StyleBoxFlat:
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(int(radius))
	box.shadow_color = Color(0, 0, 0, shadow)
	box.shadow_size = 4 if shadow > 0.0 else 0
	box.shadow_offset = Vector2(0, 2)
	box.anti_aliasing = true
	return box

func _triangle(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	_tri[0] = a
	_tri[1] = b
	_tri[2] = c
	draw_colored_polygon(_tri, color)

func _draw_tag(t: TagSlot, k: float) -> void:
	var rect: Rect2 = t.rect
	var a: float = t.alpha
	var color: Color = t.color
	var own: bool = t.own
	if t.faded:
		# Über einem eigenen Auto: kein Kasten, nur Schrift in hellerer Wagenfarbe mit dunkler Kontur (bei Nacht kein grauer Kasten).
		var fa := minf(a, 0.85)
		var fpos := Vector2(rect.position.x + 11.0 * k, rect.get_center().y + (font.get_ascent(t.fs) - font.get_descent(t.fs)) * 0.5)
		draw_string_outline(font, fpos, t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, t.fs, 6, Color(0.02, 0.07, 0.09, 0.8 * fa))
		draw_string(font, fpos, t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, t.fs, Color(color.lightened(0.35), fa))
		_record(t.car, "tag", rect, t.pinned, fa, t.text, true)
		return
	var border := Color(1, 1, 1, a) if own else Color(0.02, 0.07, 0.09, 0.8 * a)
	# Zipfel zum Auto (angeheftet: Pfeil nach außen zum Auto).
	if t.pinned:
		var e: Vector2 = t.edge
		var tip := _edge_point(rect, rect.get_center() + e * 1000.0) + e * 13.0 * k
		var side := e.orthogonal() * 8.0 * k
		var base := tip - e * 13.0 * k
		_triangle(tip, base + side, base - side, Color(border, maxf(a, 0.7)))
	else:
		var p: Vector2 = t.p
		var from := _edge_point(rect, p)
		var dist := from.distance_to(p)
		if dist > 10.0:
			var e := (p - from) / dist
			var tip := from + e * minf(10.0 * k, dist - 4.0)
			var side := e.orthogonal() * 6.0 * k
			_triangle(tip, from + side, from - side, Color(border, a))
	draw_style_box(_style(Color(color, 0.94 * a), border, 3 if own else 2, rect.size.y * 0.5, 0.35 * a), rect)
	var light := color.get_luminance() < 0.6
	var fs: int = t.fs
	var text: String = t.text
	var pos := Vector2(rect.position.x + 11.0 * k, rect.get_center().y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
	if light:
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0.02, 0.07, 0.09, 0.85 * a))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, a) if light else Color(INK, a))
	_record(t.car, "tag", rect, t.pinned, a, text)

func _draw_bubble(t: TagSlot, b: Dictionary, k: float, names_on: bool, bounds: Rect2, placed: Array[Rect2]) -> void:
	var age := float(app.race_time) - float(b.born)
	var life := float(b.life)
	# „Plopp“: schnell über 100 % hinaus, dann zurück; am Ende verblassen.
	var pop := 1.0
	if age < 0.12:
		pop = lerpf(0.35, 1.15, age / 0.12)
	elif age < 0.24:
		pop = lerpf(1.15, 1.0, (age - 0.12) / 0.12)
	var a := clampf((life - age) / 0.4, 0.0, 1.0)
	if a <= 0.0:
		return
	var text := str(b.text)
	# Lage mit voller Größe bestimmen (ausweichen, im Bild halten), gezeichnet wird um die Mitte skaliert („Plopp“).
	var fs_full := int(round(size_for(BUBBLE_SIZE) * k))
	var tsize := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs_full)
	var box_size := Vector2(tsize.x + 26.0 * k, font.get_height(fs_full) + 12.0 * k)
	var tag: Rect2 = t.rect
	var dir: Vector2 = t.dir
	var target: Vector2 = t.p   # Zipfel zeigt hierhin
	var center: Vector2
	if t.pinned:
		# Angeheftet: Blase nach innen (zur Bildmitte) neben das Schild.
		var inward := -t.edge
		center = tag.get_center() + inward * (0.5 * (absf(inward.x) * (tag.size.x + box_size.x) + absf(inward.y) * (tag.size.y + box_size.y)) + 8.0)
		target = tag.get_center()
	elif names_on:
		center = tag.get_center() + dir * (0.5 * (absf(dir.x) * (tag.size.x + box_size.x) + absf(dir.y) * (tag.size.y + box_size.y)) + 10.0 * k)
		target = tag.get_center()
	else:
		var gap := maxf(GAP * k, t.gap)
		center = target + dir * (gap + 0.5 * (absf(dir.x) * box_size.x + absf(dir.y) * box_size.y))
	var spot := _separate(Rect2(center - box_size * 0.5, box_size), placed, bounds)
	placed.append(spot)
	var fs := int(round(fs_full * pop))
	if fs < 6:
		return
	var rect := Rect2(spot.get_center() - spot.size * pop * 0.5, spot.size * pop)
	var own: bool = t.own
	var border := Color(ORANGE, a) if own else Color(INK, 0.85 * a)
	var from := _edge_point(rect, target)
	var dist := from.distance_to(target)
	if dist > 6.0:
		var e := (target - from) / dist
		var tip := from + e * minf(12.0 * k, dist)
		var side := e.orthogonal() * 7.0 * k
		_triangle(tip, from + side, from - side, border)
	draw_style_box(_style(Color(1.0, 0.99, 0.95, 0.97 * a), border, 3 if own else 2, 12.0 * k * pop, 0.3 * a), rect)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(rect.get_center().x - width * 0.5, rect.get_center().y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(INK, a))
	_record(t.car, "bubble", spot, t.pinned, a, text)
