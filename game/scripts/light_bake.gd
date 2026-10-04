class_name LightBake
extends RefCounted

# Lichtkarte (Laternen- und Flutlicht in der Draufsicht, Atmosphere.bake_rain_lights) außerhalb des Hauptfadens. Ergebnis bitgleich zur
# früheren Rechnung am Stück:
# - Streifen: Die Zeilen der Karte werden auf mehrere Arbeitsfäden verteilt. Jeder Streifen geht alle Lampen in derselben Reihenfolge
#   durch, je Zelle summieren sich die Beiträge also in derselben Reihenfolge wie vorher.
# - Grobraster: Ein Strahl Lampe → Zelle wird nur dann Schritt für Schritt durch die Hindernismaske verfolgt, wenn er an einem Block
#   (BLOCK x BLOCK Zellen) mit Hindernis vorbeiführt (Nachbarblöcke eingeschlossen). Strahlen fern aller Hindernisse könnten ohnehin
#   nicht verdeckt sein; dort ändert das Auslassen nichts.
# - Merkspeicher: Die letzten MEMORY Karten bleiben im Speicher (Schlüssel: SHA-256 über alle Eingaben). Zurück zur vorigen Strecke
#   (Mehrspieler verlassen) kostet dann nichts.
# Ablauf: start() → je Bild poll() bis true (oder wait() am Stück) → image. Abbruch: abandon() (die Fäden enden bald, reap() räumt auf).

const BLOCK := 8
const BANDS := 32
const MEMORY := 3
static var _memory := {}          # Schlüssel -> Image
static var _memory_order: Array = []
static var _orphans: Array = []   # abgebrochene Aufträge, deren Fäden noch laufen
static var threads := 0           # Fäden für die Streifen; 0 = Prozessorkerne − 2 (Hauptfaden und Darstellung bleiben frei)
static var cull := true           # Grobraster nutzen (false nur für Prüfungen: jeder Strahl Schritt für Schritt wie früher)

var occluders: Array
var occluder_polys: Array
var lamps: Array
var area: Rect2
var cells := 256
var key := ""
var image: Image                  # Ergebnis (RGBF, cells x cells, weichgezeichnet)
var from_memory := false
var cancelled := false
var solid := PackedFloat32Array() # Höhenmaske der Hindernisse je Zelle
var near := PackedByteArray()     # je Block: 1 = Hindernis in diesem oder einem Nachbarblock
var blocks := 0
var bands: Array = []             # je Streifen die Zeilen [r0, r1) als RGB-Werte
var data := PackedFloat32Array()
var _stage := ""                  # "" → "solid" → "bands" → "finish" → "done"
var _task := -1
var _group := -1
var _mutex := Mutex.new()

func _init(occ: Array, polys: Array, lamp_list: Array, bake_area: Rect2, cell_count: int) -> void:
	occluders = occ.duplicate(true)
	occluder_polys = polys.duplicate(true)
	lamps = lamp_list.duplicate(true)
	area = bake_area
	cells = cell_count
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes([occluders, occluder_polys, lamps, area, cells, Atmosphere.LAMP_REACH]))
	key = ctx.finish().hex_encode()

func done() -> bool:
	return _stage == "done"

func start() -> void:
	# Merkspeicher oder Hindernismaske in einem Arbeitsfaden; weiter mit poll().
	if _stage != "":
		return
	if _memory.has(key):
		image = _memory[key]
		from_memory = true
		_stage = "done"
		return
	_stage = "solid"
	_task = WorkerThreadPool.add_task(_build_solid, true, "Lichtkarte: Hindernisse")

func poll() -> bool:
	# Je Bild vom Hauptfaden: nächste Stufe anstoßen, sobald die laufende fertig ist. true = image steht bereit.
	if cancelled:
		return false
	if _stage == "":
		start()
	if _stage == "solid" and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_start_bands()
	if _stage == "bands" and WorkerThreadPool.is_group_task_completed(_group):
		WorkerThreadPool.wait_for_group_task_completion(_group)
		_group = -1
		_stage = "finish"
		_task = WorkerThreadPool.add_task(_finish, true, "Lichtkarte: Weichzeichnen")
	if _stage == "finish" and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_stage = "done"
		_remember()
	return _stage == "done"

func wait() -> void:
	# Am Stück (blockiert den aufrufenden Faden; die Streifen laufen trotzdem parallel).
	if _stage == "":
		start()
	if _stage == "solid":
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_start_bands()
	if _stage == "bands":
		WorkerThreadPool.wait_for_group_task_completion(_group)
		_group = -1
		_stage = "finish"
		_task = WorkerThreadPool.add_task(_finish, true, "Lichtkarte: Weichzeichnen")
	if _stage == "finish":
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_stage = "done"
		_remember()

func abandon() -> void:
	# Andere Strecke gewählt: Streifen brechen ab; laufende Fäden werden später eingesammelt (reap), nie blockierend.
	cancelled = true
	if _task >= 0 or _group >= 0:
		_orphans.append(self)

static func reap() -> void:
	# Je Bild: abgebrochene Aufträge abschließen, deren Fäden fertig sind (WorkerThreadPool verlangt das Abwarten jeder Aufgabe).
	for job in _orphans.duplicate():
		var j: LightBake = job
		if j._task >= 0 and WorkerThreadPool.is_task_completed(j._task):
			WorkerThreadPool.wait_for_task_completion(j._task)
			j._task = -1
		if j._group >= 0 and WorkerThreadPool.is_group_task_completed(j._group):
			WorkerThreadPool.wait_for_group_task_completion(j._group)
			j._group = -1
		if j._task < 0 and j._group < 0:
			_orphans.erase(job)

static func shutdown() -> void:
	# Programmende: laufende Fäden abgebrochener Aufträge abwarten.
	for job in _orphans:
		var j: LightBake = job
		if j._task >= 0:
			WorkerThreadPool.wait_for_task_completion(j._task)
			j._task = -1
		if j._group >= 0:
			WorkerThreadPool.wait_for_group_task_completion(j._group)
			j._group = -1
	_orphans.clear()
	forget()

static func forget() -> void:
	# Nur für Prüfungen: Merkspeicher leeren.
	_memory.clear()
	_memory_order.clear()

func _remember() -> void:
	if cancelled or image == null:
		return
	_memory[key] = image
	_memory_order.erase(key)
	_memory_order.append(key)
	while _memory_order.size() > MEMORY:
		_memory.erase(_memory_order.pop_front())

func _start_bands() -> void:
	bands.resize(BANDS)
	_stage = "bands"
	_group = WorkerThreadPool.add_group_task(_band, BANDS, threads if threads > 0 else maxi(1, OS.get_processor_count() - 2), true, "Lichtkarte: Streifen")

func _build_solid() -> void:
	# Hindernismaske wie bisher (Gebäude unendlich hoch, Lichtblocker mit ihrer Höhe), dazu das Grobraster.
	var cell := area.size / cells
	solid.resize(cells * cells)
	for o in occluders:
		var oc: Vector2 = o[0]
		var oh: Vector2 = o[1]
		var rot := float(o[2])
		var rad := oh.length()
		var bx0 := maxi(0, int((oc.x - rad - area.position.x) / cell.x))
		var bx1 := mini(cells - 1, int((oc.x + rad - area.position.x) / cell.x))
		var by0 := maxi(0, int((oc.y - rad - area.position.y) / cell.y))
		var by1 := mini(cells - 1, int((oc.y + rad - area.position.y) / cell.y))
		for iy in range(by0, by1 + 1):
			for ix in range(bx0, bx1 + 1):
				var local := (area.position + Vector2((ix + 0.5) * cell.x, (iy + 0.5) * cell.y) - oc).rotated(-rot)
				if absf(local.x) < oh.x and absf(local.y) < oh.y:
					solid[iy * cells + ix] = Atmosphere.SOLID_HIGH
	for pol in occluder_polys:
		if cancelled:
			return
		var pts: PackedVector2Array = pol[0]
		var ph := float(pol[1])
		if pts.size() < 3:
			continue
		var lo := pts[0]
		var hi := pts[0]
		for q in pts:
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		var px0 := maxi(0, int((lo.x - area.position.x) / cell.x) - 1)
		var px1 := mini(cells - 1, int((hi.x - area.position.x) / cell.x) + 1)
		var py0 := maxi(0, int((lo.y - area.position.y) / cell.y) - 1)
		var py1 := mini(cells - 1, int((hi.y - area.position.y) / cell.y) + 1)
		for iy in range(py0, py1 + 1):
			for ix in range(px0, px1 + 1):
				var c0 := area.position + Vector2((ix + 0.5) * cell.x, (iy + 0.5) * cell.y)
				# Mitte und vier Punkte nahe den Zellecken: auch Streifen, die schmaler als eine Zelle sind, schließen lückenlos
				var hit := Atmosphere.inside_poly(c0, pts)
				if not hit:
					for off: Vector2 in [Vector2(-0.3, -0.3), Vector2(0.3, -0.3), Vector2(0.3, 0.3), Vector2(-0.3, 0.3)]:
						if Atmosphere.inside_poly(c0 + off * cell, pts):
							hit = true
							break
				if hit:
					var k0 := iy * cells + ix
					solid[k0] = maxf(solid[k0], ph)
	# Grobraster: Block mit Hindernis, auf die Nachbarblöcke ausgedehnt.
	blocks = ceili(float(cells) / BLOCK)
	var raw := PackedByteArray()
	raw.resize(blocks * blocks)
	for iy in range(cells):
		for ix in range(cells):
			if solid[iy * cells + ix] > 0.0:
				raw[(iy / BLOCK) * blocks + ix / BLOCK] = 1
	near.resize(blocks * blocks)
	for by in range(blocks):
		for bx in range(blocks):
			if raw[by * blocks + bx] == 0:
				continue
			for ny in range(maxi(0, by - 1), mini(blocks, by + 2)):
				for nx in range(maxi(0, bx - 1), mini(blocks, bx + 2)):
					near[ny * blocks + nx] = 1

func _band(index: int) -> void:
	# Zeilen [r0, r1) aller Lampen in der bisherigen Reihenfolge (Rechnung wie Atmosphere.bake_rain_lights vor dem Umbau).
	var r0 := index * cells / BANDS
	var r1 := (index + 1) * cells / BANDS
	var out := PackedFloat32Array()
	out.resize((r1 - r0) * cells * 3)
	var cell := area.size / cells
	var step_len := minf(cell.x, cell.y)
	var coarse_len := step_len * BLOCK * 0.5
	var block_w := cell.x * BLOCK
	var block_h := cell.y * BLOCK
	var mask := solid          # lokale Verweise (schneller als Mitglieder, nur gelesen)
	var near_mask := near
	for lamp in lamps:
		if cancelled:
			return
		var p: Vector3 = lamp[0]
		var reach: float = lamp[1] * Atmosphere.LAMP_REACH
		var col: Color = lamp[2]
		var head := Vector2(p.x, p.z)
		var x0 := maxi(0, int((p.x - reach - area.position.x) / cell.x))
		var x1 := mini(cells - 1, int((p.x + reach - area.position.x) / cell.x))
		var y0 := maxi(0, int((p.z - reach - area.position.y) / cell.y))
		var y1 := mini(cells - 1, int((p.z + reach - area.position.y) / cell.y))
		var ry0 := maxi(y0, r0)
		var ry1 := mini(y1, r1 - 1)
		if ry0 > ry1:
			continue
		# Liegt im ganzen Lichtkreis kein Hindernis (samt Nachbarblöcken), ist jeder Strahl frei.
		var any_near := false
		for by in range(y0 / BLOCK, y1 / BLOCK + 1):
			for bx in range(x0 / BLOCK, x1 / BLOCK + 1):
				if near_mask[by * blocks + bx] != 0:
					any_near = true
					break
			if any_near:
				break
		for iy in range(ry0, ry1 + 1):
			for ix in range(x0, x1 + 1):
				if mask[iy * cells + ix] > 0.0:
					continue
				var q := area.position + Vector2((ix + 0.5) * cell.x, (iy + 0.5) * cell.y)
				var d := q.distance_to(head)
				if d >= reach:
					continue
				var hidden := false
				if not cull or (any_near and _passes_near(near_mask, head, q, d, coarse_len, block_w, block_h)):
					# Sichtlinie Laterne -> Zelle durch die Gebäudemaske (die ersten 1,2 m am Mast zählen nicht).
					var steps := int(d / step_len)
					for k in range(1, steps):
						var t := float(k) / steps
						if d * t < 1.2:
							continue
						var sx := int((lerpf(head.x, q.x, t) - area.position.x) / cell.x)
						var sy := int((lerpf(head.y, q.y, t) - area.position.y) / cell.y)
						# Der Strahl vom Lichtkopf (Höhe p.y) zum Boden hat auf halbem Weg nur noch die halbe Höhe.
						if sx >= 0 and sy >= 0 and sx < cells and sy < cells and mask[sy * cells + sx] > p.y * (1.0 - t):
							hidden = true
							break
				if hidden:
					continue
				var f := 1.0 - smoothstep(0.0, reach, d)
				f = f * f * 1.6
				var k2 := ((iy - r0) * cells + ix) * 3
				out[k2] += col.r * f
				out[k2 + 1] += col.g * f
				out[k2 + 2] += col.b * f
	_mutex.lock()
	bands[index] = out
	_mutex.unlock()

func _passes_near(near_mask: PackedByteArray, head: Vector2, q: Vector2, d: float, coarse_len: float, block_w: float, block_h: float) -> bool:
	# Grobe Sichtprüfung: Proben im Abstand von höchstens einem halben Block entlang des Strahls. Jede Probe der feinen Prüfung liegt
	# höchstens einen Viertelblock (plus eine Zelle Rundung) neben einer groben – deren Block oder ein Nachbar enthält dann das Hindernis.
	var n := ceili(d / coarse_len) + 1
	for j in range(n + 1):
		var t := float(j) / n
		var bx := clampi(floori((head.x + (q.x - head.x) * t - area.position.x) / block_w), 0, blocks - 1)
		var by := clampi(floori((head.y + (q.y - head.y) * t - area.position.y) / block_h), 0, blocks - 1)
		if near_mask[by * blocks + bx] != 0:
			return true
	return false

func _finish() -> void:
	# Streifen zusammensetzen, weichzeichnen wie bisher: verkleinern und wieder vergrößern (wirkt wie eine Unschärfe von ~1 m).
	if cancelled:
		return
	data = PackedFloat32Array()
	for b in bands:
		data.append_array(b)
	var img := Image.create_from_data(cells, cells, false, Image.FORMAT_RGBF, data.to_byte_array())
	img.resize(cells / 3, cells / 3, Image.INTERPOLATE_BILINEAR)
	img.resize(cells, cells, Image.INTERPOLATE_CUBIC)
	image = img
