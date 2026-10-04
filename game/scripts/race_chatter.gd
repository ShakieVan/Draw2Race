class_name RaceChatter
extends RefCounted

# Sprechblasen aus Ereignissen (M1, docs/MULTIPLAYER_RECHERCHE.md 6): Überholen, Führung, Rempler, Leitplanke, Dreher, Sprung,
# Looping, Turbo, Absturz, Zieleinlauf. Die Blasen entstehen aus Zustandswechseln der Fahrzeuge, die hier nur GELESEN werden
# (Leitplanke 4: die Simulation bleibt unberührt). Kein freier Text. Je Auto höchstens eine Blase; wichtigere Ereignisse
# verdrängen unwichtigere, sonst gilt je Auto ein Mindestabstand. Zeitbasis ist die Rennzeit (Pause hält die Blasen an).
# Später (Netz) kann der Host dieselben Ereignisse melden und die Mitspieler rufen say() mit Art und Text auf.

const LIFE := 2.0            # s Lebensdauer einer Blase ...
const LIFE_LONG := 2.5       # ... Absturz und Ziel etwas länger
const CAR_GAP := 3.0         # s: so lange nach einer Blase schweigt ein Auto (außer bei Absturz und Ziel)
const TURBO_GAP := 12.0      # s: „Turbo!“ höchstens so oft je Auto (nur Menschen)
const START_QUIET := 2.5     # s nach dem Start: kein Überholen/keine Führung (Gedränge am Start)
const MAX_ACTIVE := 3        # höchstens so viele Blasen gleichzeitig (mein Auto, Absturz und Ziel dürfen immer)
const PASS_MARGIN := 1.0     # m Vorsprung, ab dem ein Platztausch zählt (gegen Flackern Seite an Seite)
const PASS_NEAR := 25.0      # m: nur echte Überholmanöver (Autos nah beieinander)
const CONTACT_MIN := 2.0     # m/s Aufprall Auto–Auto
const WALL_MIN := 5.0        # m/s Aufprall an der Leitplanke
const SPIN_ANGLE := 1.9      # rad zwischen Blick- und Fahrtrichtung: Dreher (≈ 110°) ...
const SPIN_RESET := 0.6      # ... wieder scharf unter ≈ 35°
const SPIN_SPEED := 4.0      # m/s
const JUMP_TIME := 0.55      # s in der Luft: großer Sprung

const PRIORITY := {"finish": 9, "crash": 8, "lead": 6, "overtake": 5, "spin": 5, "contact": 4, "wall": 4, "jump": 3,
	"loop": 2, "turbo": 1}
const TEXTS := {
	"overtake": ["Überholt!", "Vorbei!", "Platz da!", "Tschüss!"],
	"lead": ["Führung!", "Ich führe!", "Vorne!"],
	"contact": ["Hey!", "Rempler!", "Pass auf!", "Autsch!"],
	"wall": ["Autsch!", "Uff!", "Knirsch!"],
	"spin": ["Dreher!", "Huiii!", "Wo ist vorne?"],
	"crash": ["Abgeflogen!", "Neeein!"],
	"wreck": ["Totalschaden!", "Kawumm!"],
	"rolled": ["Zu langsam …", "Rückwärts?!"],
	"jump": ["Juhu!", "Abflug!", "Ich fliege!"],
	"loop": ["Looping!", "Kopfüber!"],
	"turbo": ["Turbo!", "Vollgas!"],
}

var bubbles: Array = []          # je Auto: {} oder {text, kind, born, life, priority}
var last_said: Array = []        # je Auto: Zeitpunkt der letzten Blase
var last_turbo: Array = []
var said_count: Array = []       # je Auto: Zahl der Blasen (wählt den Text, deterministisch statt zufällig)
var state: Array = []            # je Auto: zuletzt gesehener Zustand
var ahead := {}                  # Vector2i(i, j) -> true, wenn i vor j liegt (i < j)
var leader := -1
var history: Array = []            # alle Blasen dieses Rennens [{car, kind, text, time}] (Tests, später Wiederholung)

func reset(count: int) -> void:
	bubbles.clear()
	last_said.clear()
	last_turbo.clear()
	said_count.clear()
	state.clear()
	ahead.clear()
	history.clear()
	leader = -1
	for _i in range(count):
		bubbles.append({})
		last_said.append(-99.0)
		last_turbo.append(-99.0)
		said_count.append(0)
		state.append({})

const NONE := {}             # „keine Blase“ (unveränderlich; active() legt so je Bild kein neues Dictionary an)

func active(i: int, time: float) -> Dictionary:
	# Laufende Blase des Autos i (leer, wenn keine). Nur lesen: das Ergebnis kann NONE sein.
	if i < 0 or i >= bubbles.size():
		return NONE
	var b: Dictionary = bubbles[i]
	if b.is_empty() or time - float(b.born) > float(b.life) or time < float(b.born):
		return NONE
	return b

func active_count(time: float) -> int:
	var n := 0
	for i in range(bubbles.size()):
		if not active(i, time).is_empty():
			n += 1
	return n

func say(i: int, kind: String, time: float, text := "", focus := -1) -> bool:
	# Blase für Auto i; false, wenn sie wegen Ratenbegrenzung oder einer wichtigeren laufenden Blase entfällt.
	if i < 0 or i >= bubbles.size():
		return false
	var priority := int(PRIORITY.get(kind, PRIORITY.get(_base_kind(kind), 1)))
	var current := active(i, time)
	var urgent := priority >= int(PRIORITY.crash)
	if not current.is_empty():
		if priority <= int(current.priority):
			return false
	elif not urgent:
		if time - float(last_said[i]) < CAR_GAP:
			return false
		if i != focus and active_count(time) >= MAX_ACTIVE:
			return false
	if text == "":
		var list: Array = TEXTS.get(kind, ["…"])
		text = str(list[(int(said_count[i]) + i) % list.size()])
	said_count[i] = int(said_count[i]) + 1
	last_said[i] = time
	bubbles[i] = {"text": text, "kind": kind, "born": time, "priority": priority,
		"life": LIFE_LONG if urgent else LIFE}
	history.append({"car": i, "kind": kind, "text": text, "time": time})
	return true

func _base_kind(kind: String) -> String:
	return "crash" if kind in ["wreck", "rolled"] else kind

func observe(cars: Array, impacts: Array, time: float, humans: Array = [], focus := -1, racing := true) -> void:
	# Nach jedem Simulationstakt aufrufen (nur lesen). humans[i]: Mensch? (Turbo-Blasen nur für Menschen); focus: mein Auto.
	if bubbles.size() != cars.size():
		reset(cars.size())
	var length := 1.0
	if not cars.is_empty() and cars[0].track != null:
		length = maxf(1.0, cars[0].track.length)
	for i in range(cars.size()):
		var v: RaceVehicle = cars[i]
		var st: Dictionary = state[i]
		var first := st.is_empty()
		var finished := v.finish_time >= 0.0
		if finished and not bool(st.get("finished", true if first else false)):
			var place := 1
			for other in cars:
				if other != v and other.finish_time >= 0.0 and other.finish_time < v.finish_time:
					place += 1
			say(i, "finish", time, "Ziel!" if cars.size() == 1 else "Ziel – Platz %d" % place, focus)
		elif v.crashed and not bool(st.get("crashed", true if first else false)):
			say(i, "wreck" if v.wrecked else ("rolled" if v.rolled_back else "crash"), time, "", focus)
		elif not v.crashed and not finished:
			# Sprung: lange genug in der Luft.
			var air_from := float(st.get("air_from", -1.0))
			if v.airborne:
				if air_from < 0.0:
					air_from = time
				if time - air_from >= JUMP_TIME and not bool(st.get("jump_said", false)):
					st["jump_said"] = true
					say(i, "jump", time, "", focus)
			else:
				air_from = -1.0
				st["jump_said"] = false
			st["air_from"] = air_from
			if v.in_loop and not bool(st.get("in_loop", false)):
				say(i, "loop", time, "", focus)
			# Dreher: Fahrtrichtung weit weg von der Blickrichtung (am Boden, mit Tempo).
			var speed := v.velocity.length()
			if not v.airborne and not v.in_loop and speed > SPIN_SPEED:
				var angle := absf(angle_difference(v.heading, v.velocity.angle()))
				if angle > SPIN_ANGLE and not bool(st.get("spun", false)):
					st["spun"] = true
					say(i, "spin", time, "", focus)
				elif angle < SPIN_RESET:
					st["spun"] = false
			if racing and v.guard_hit >= WALL_MIN:
				say(i, "wall", time, "", focus)
			if i < humans.size() and bool(humans[i]) and v.boosting and not bool(st.get("boosting", false)) \
					and time - float(last_turbo[i]) >= TURBO_GAP:
				if say(i, "turbo", time, "", focus):
					last_turbo[i] = time
		st["finished"] = finished
		st["crashed"] = v.crashed
		st["in_loop"] = v.in_loop
		st["boosting"] = v.boosting
	# Rempler: der Vordere beschwert sich.
	for hit in impacts:
		if float(hit[2]) >= CONTACT_MIN:
			var a: int = hit[0]
			var b: int = hit[1]
			if a < cars.size() and b < cars.size():
				say(a if cars[a].progress >= cars[b].progress else b, "contact", time, "", focus)
	_observe_order(cars, time, length, focus)

func _racing(v: RaceVehicle) -> bool:
	return not v.crashed and v.finish_time < 0.0

func _observe_order(cars: Array, time: float, length: float, focus: int) -> void:
	# Platztausch zweier nah beieinander fahrender Autos (mit Vorsprung PASS_MARGIN gegen Flackern) und Führungswechsel.
	for i in range(cars.size()):
		for j in range(i + 1, cars.size()):
			var key := Vector2i(i, j)
			var a: RaceVehicle = cars[i]
			var b: RaceVehicle = cars[j]
			var gap := (a.progress - b.progress) * length
			if not ahead.has(key):
				ahead[key] = gap > 0.0
				continue
			if not (_racing(a) and _racing(b)):
				continue
			var was: bool = ahead[key]
			if was and gap < -PASS_MARGIN:
				ahead[key] = false
				if time >= START_QUIET and a.pos.distance_to(b.pos) < PASS_NEAR:
					say(j, "overtake", time, "", focus)
			elif not was and gap > PASS_MARGIN:
				ahead[key] = true
				if time >= START_QUIET and a.pos.distance_to(b.pos) < PASS_NEAR:
					say(i, "overtake", time, "", focus)
	if cars.size() < 2:
		return
	var best := -1
	for i in range(cars.size()):
		if _racing(cars[i]) and (best < 0 or cars[i].progress > cars[best].progress):
			best = i
	# Wer im Ziel ist, führt nicht mehr „live“; neue Führung nur unter den Fahrenden und mit Vorsprung.
	if best >= 0 and best != leader:
		var clear_lead: bool = leader < 0 or not _racing(cars[leader]) \
			or (cars[best].progress - cars[leader].progress) * length > PASS_MARGIN
		if clear_lead:
			var previous := leader
			leader = best
			if previous >= 0 and cars[previous].finish_time < 0.0 and time >= START_QUIET:
				say(best, "lead", time, "", focus)
