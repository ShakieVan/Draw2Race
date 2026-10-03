class_name LineRecorder
extends RefCounted

# Glättung im Streckenkoordinatensystem: Fortschritt s bleibt exakt (kein Nachhinken),
# seitlicher Versatz und Tempo werden wegabhängig tiefpassgefiltert. So verschwinden Zittern und der
# wandernde Druckpunkt der Fingerkuppe, unabhängig von der Abtastrate des Displays.
const OFFSET_SMOOTH := 2.4   # Meter Weg bis ~63 % einer seitlichen Änderung übernommen sind
const SPEED_SMOOTH := 2.8    # dito für das Tempo
const FINAL_WINDOW := 5      # Nachglättung nach dem Zeichnen: ±5 Routenpunkte (~±3 m)
const EDGE_MARGIN := 0.35
# Pflicht-Wegpunkte: Tore quer zur Strecke; knapp daneben (Toleranz) zählt noch als durchfahren.
const GATES_PER_LAP := 24
const GATE_TOLERANCE := 1.5
# Zeichnen ist auf der ganzen Insel erlaubt (Untergrund bremst), nur nicht ins Meer.
const DRAW_LIMIT := Circuit.HALF_WIDTH + 9.0
const MAX_JUMP := 13.0
# Unterbrechen und Wiederansetzen:
# - fest: Werte, die älter als OPEN_TIME Malzeit sind (Malzeit = nur Zeit mit Finger auf dem Display);
# - offen: jüngere Werte; dort darf neu angesetzt werden (die Linie schimmert);
# - Probe: ein neuer Ansatz gilt erst nach TRIAL_TIME Malzeit ab der ersten Bewegung. Dann werden die alten
#   Werte ab dem Ansatzpunkt verworfen und das Tempo vom Ansatzpunkt zum neuen Wert geglättet. Hört man
#   früher auf, verschwindet die Probe und die alte Linie gilt wieder. Die Ziellinie bestätigt sofort.
const OPEN_TIME := 1.0
const TRIAL_TIME := 0.5
const GRAB_DEFAULT := 3.1
# Tempo-Faktor: Tempovorgabe = 5 + Zeichentempo (m/s) * Faktor, höchstens 29 m/s. Grundwert 0,38
# (Höchsttempo bei ~63 m/s Zeichentempo); einstellbar von der Hälfte bis zum Doppelten.
const TEMPO_BASE := 0.38
var tempo_factor := TEMPO_BASE

static func tempo_from_setting(value: float) -> float:
	# Regler 0..1, Mitte = Grundwert; logarithmisch: 0 = halb (-50 %), 1 = doppelt (+100 %).
	return TEMPO_BASE * pow(2.0, (clampf(value, 0.0, 1.0) - 0.5) * 2.0)

var track: Circuit
var route: Array[Dictionary] = []
var raw: Array[Dictionary] = []
var progress := 0.0
var active := false
var last_time := 0.0
var last_phase := 0.0
var last_pos := Vector2.ZERO
var offset_f := 0.0
var speed_f := 12.0
var hint := "Beginne am leuchtenden Startpunkt."
var complete := false
var gates_passed := 0
var draw_time := 0.0
var last_tick := 0.0
var marks: Array[Dictionary] = []   # Zwischenstand nach jeder angenommenen Abtastung (marks[0] = Start)
var trial := false
var trial_moved_at := -1.0
var trial_base_index := 0
var trial_base_speed := -1.0        # -1: kein alter Wert (allererster Strich / Ansatz am Start)
var backup := {}
var discarded := false              # letzte Probe wurde verworfen (für den Hinweis)

func _init(circuit: Circuit) -> void:
	track = circuit

func state() -> Dictionary:
	return {"route_len": route.size(), "raw_len": raw.size(), "progress": progress, "last_phase": last_phase,
		"last_pos": last_pos, "offset_f": offset_f, "speed_f": speed_f, "gates": gates_passed, "time": draw_time}

func rewind(m: Dictionary) -> void:
	route.resize(int(m.route_len))
	raw.resize(int(m.raw_len))
	progress = float(m.progress)
	last_phase = float(m.last_phase)
	last_pos = m.last_pos
	offset_f = float(m.offset_f)
	speed_f = float(m.speed_f)
	gates_passed = int(m.gates)

func open_mark() -> int:
	# Ältester noch offener Zwischenstand: der jüngste, der gerade fest geworden ist (Grenzpunkt).
	var k := 0
	for i in range(marks.size()):
		if draw_time - float(marks[i].time) >= OPEN_TIME:
			k = i
	return k

func open_route_index() -> int:
	# Routenindex, ab dem die Linie offen ist (schimmert); -1 = alles fest.
	if complete or marks.is_empty():
		return -1
	return int(marks[open_mark()].route_len) - 1

func ghost() -> Array[Dictionary]:
	# Während einer Probe: der alte Linienrest ab dem Ansatzpunkt (wird bei Bestätigung verworfen).
	var tail: Array[Dictionary] = []
	if trial and not backup.is_empty():
		var old: Array[Dictionary] = backup.route
		for i in range(trial_base_index, old.size()):
			tail.append(old[i])
	return tail

func begin(p: Vector2, time: float, tolerance := GRAB_DEFAULT) -> bool:
	if complete:
		return false
	discarded = false
	var base := 0
	if route.is_empty():
		if p.distance_to(track.at(0.0)) > tolerance or track.center_distance(p) > DRAW_LIMIT:
			hint = "Beginne am leuchtenden Startpunkt."
			return false
		last_pos = track.at(0.0)
		last_phase = 0.0
		offset_f = 0.0
		speed_f = 12.0
		route.append({"p": last_pos, "speed": 12.0, "s": 0.0, "o": 0.0})
		marks.clear()
		marks.append(state())
	else:
		# Nur im offenen (schimmernden) Bereich ansetzen; an der Kreuzung der Acht zählt nur die eigene Linie.
		base = -1
		var best := tolerance
		for i in range(open_mark(), marks.size()):
			var d: float = p.distance_to(marks[i].last_pos)
			if d <= best:
				best = d
				base = i
		if base < 0:
			hint = "Setze im schimmernden Linienende an."
			return false
	backup = {"state": state(), "route": route.duplicate(), "raw": raw.duplicate(), "marks": marks.duplicate()}
	rewind(marks[base])
	marks.resize(base + 1)
	trial = true
	trial_moved_at = -1.0
	trial_base_index = route.size() - 1
	trial_base_speed = float(route[-1].speed) if base > 0 else -1.0
	active = true
	last_time = time
	last_tick = time
	return true

func advance(time: float) -> void:
	# Malzeit läuft nur mit Finger auf dem Display.
	if not active:
		return
	draw_time += maxf(0.0, time - last_tick)
	last_tick = time
	if trial and trial_moved_at >= 0.0 and draw_time - trial_moved_at >= TRIAL_TIME:
		confirm()

func tick(time: float) -> void:
	advance(time)

func confirm() -> void:
	# Probe bestätigt: alter Rest ist schon abgeschnitten; Tempo vom Ansatzpunkt zum neuen Wert glätten.
	trial = false
	backup = {}
	if trial_base_speed < 0.0 or route.size() - 1 <= trial_base_index:
		return
	var s0 := float(route[trial_base_index].s)
	var s1 := float(route[-1].s)
	var v1 := float(route[-1].speed)
	for i in range(trial_base_index + 1, route.size()):
		var t := clampf((float(route[i].s) - s0) / maxf(0.001, s1 - s0), 0.0, 1.0)
		route[i].speed = lerpf(trial_base_speed, v1, t)

func discard() -> void:
	# Probe zu kurz: alte Linie samt Malzeit wiederherstellen, als hätte es den Versuch nie gegeben.
	var st: Dictionary = backup.state
	route = backup.route
	raw = backup.raw
	marks = backup.marks
	progress = float(st.progress)
	last_phase = float(st.last_phase)
	last_pos = st.last_pos
	offset_f = float(st.offset_f)
	speed_f = float(st.speed_f)
	gates_passed = int(st.gates)
	draw_time = float(st.time)
	trial = false
	backup = {}
	discarded = true

func stop() -> void:
	active = false
	if trial:
		discard()

func end() -> void:
	if not active:
		return
	stop()
	if discarded:
		hint = "Zu kurz – nach dem Ansetzen mindestens 0,5 s weitermalen."

func lateral(p: Vector2, ph: float) -> float:
	var sc := track.shortcut_at(p)
	if not sc.is_empty():
		return (p - Vector2(sc.point)).dot(Vector2(sc.normal))
	var t := track.tangent(ph)
	return (p - track.at(ph)).dot(Vector2(-t.y, t.x))

func sample(p: Vector2, time: float) -> bool:
	if not active or complete:
		return false
	advance(time)
	if not active:
		return false
	var elapsed := maxf(0.001, time - last_time)
	var distance := p.distance_to(last_pos)
	if distance < 0.20:
		# Keep active dwell time; lifting the finger resets this clock in begin().
		# Nur Punkte dieses Strichs; der Ansatzpunkt selbst gehört zur alten Linie.
		if elapsed > 0.22 and route.size() - 1 > trial_base_index:
			route[-1].speed = 5.0
			speed_f = 5.0
		return false
	var ph := track.phase_near(p, last_phase, 0.15)
	var advance := wrapf(ph - last_phase, -0.5, 0.5)
	if distance > MAX_JUMP or track.center_distance(p) > DRAW_LIMIT + track.hw(ph) - Circuit.HALF_WIDTH:
		hint = "Zu weit von der Strecke – bleib in ihrer Nähe."
		stop()
		return false
	if advance < -0.008 and advance > -0.2:
		hint = "Folge den Pfeilen."
		stop()
		return false
	# Große Phasensprünge = querfeldein über die Innenfläche; ohne Tore gibt es keinen Fortschritt.
	var cut := absf(advance) >= 0.2
	var gates_before := gates_passed
	count_gates(last_pos, p)
	var candidate := progress + (0.0 if cut else maxf(advance, 0.0))
	var on_shortcut := track.shortcut_at(p)
	if not on_shortcut.is_empty() and not cut:
		# Abkürzung: übersprungene Tore der Hauptstrecke gelten als durchfahren.
		gates_passed = maxi(gates_passed, int(floor(candidate * GATES_PER_LAP)))
	var cap := float(gates_passed + 1) / GATES_PER_LAP
	if cut or candidate > cap + 0.002:
		# Tor verpasst: Zeichnung stoppt, Endpunkt bleibt am letzten gültigen Punkt.
		gates_passed = gates_before
		hint = "Wegpunkt verpasst – setze im schimmernden Bereich wieder an."
		stop()
		return false
	if candidate <= progress + 0.0001:
		return false
	var speed := clampf(5.0 + distance / elapsed * tempo_factor, 5.0, 29.0)
	var start_offset := offset_f
	var start_speed := speed_f
	var limit := DRAW_LIMIT + track.hw(ph) - Circuit.HALF_WIDTH - EDGE_MARGIN
	offset_f = clampf(lerpf(offset_f, lateral(p, ph), 1.0 - exp(-distance / OFFSET_SMOOTH)), -limit, limit)
	if not on_shortcut.is_empty():
		# Auf einem Lineal (Wippe) rastet die Linie mittig ein: Seitenversatz höchstens ±rail.
		for w in track.rest_seesaws():
			if w.shortcut == int(on_shortcut.index) and w.inside(p, 1.0):
				offset_f = clampf(offset_f, -w.rail, w.rail)
	speed_f = lerpf(speed_f, speed, 1.0 - exp(-distance / SPEED_SMOOTH))
	progress = minf(candidate, cap)
	raw.append({"x": p.x, "z": p.y, "time": time, "active_dt": elapsed})
	var count := maxi(1, ceili(distance / 0.6))
	var start_s := float(route[-1].s)
	var sc_index := int(on_shortcut.index) if not on_shortcut.is_empty() else -1
	for i in range(1, count + 1):
		var t := float(i) / count
		var s := lerpf(start_s, progress, t)
		var o := lerpf(start_offset, offset_f, t)
		route.append({"p": track.place(s, o, sc_index), "speed": lerpf(start_speed, speed_f, t), "s": s, "o": o, "sc": sc_index})
	last_pos = p
	last_phase = ph
	last_time = time
	hint = "Langsam in die Kurve. Zügig auf die Gerade."
	marks.append(state())
	if trial and trial_moved_at < 0.0:
		trial_moved_at = draw_time
	complete = gates_passed >= GATES_PER_LAP * track.laps
	if complete and trial:
		# Ziellinie endgültig überquert: sofort festschreiben.
		confirm()
	if complete:
		progress = float(track.laps)
		route[-1].s = float(track.laps)
		finalize()
	return true

func gate(k: int) -> Array:
	var s := float(k) / GATES_PER_LAP
	var reach := track.hw(s) + GATE_TOLERANCE
	return [track.at(s, -reach), track.at(s, reach)]

func count_gates(a: Vector2, b: Vector2) -> void:
	# Tore in Reihenfolge; mehrere pro Segment möglich (schnelles Zeichnen).
	while gates_passed < GATES_PER_LAP * track.laps:
		var g := gate(gates_passed + 1)
		if Geometry2D.segment_intersects_segment(a, b, g[0], g[1]) == null:
			return
		gates_passed += 1

func finalize() -> void:
	# Gaußsche Nachglättung von Versatz und Tempo; Startpunkt bleibt fest.
	var n := route.size()
	var offsets := PackedFloat32Array()
	var speeds := PackedFloat32Array()
	for point in route:
		offsets.append(float(point.get("o", 0.0)))
		speeds.append(float(point.speed))
	for i in range(1, n):
		var wsum := 0.0
		var osum := 0.0
		var ssum := 0.0
		for k in range(-FINAL_WINDOW, FINAL_WINDOW + 1):
			var j := clampi(i + k, 0, n - 1)
			var w := exp(-float(k * k) / (2.0 * pow(FINAL_WINDOW * 0.5, 2)))
			wsum += w
			osum += offsets[j] * w
			ssum += speeds[j] * w
		route[i].o = osum / wsum
		route[i].speed = ssum / wsum
		route[i].p = track.place(float(route[i].s), float(route[i].o), int(route[i].get("sc", -1)))
