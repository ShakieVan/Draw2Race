class_name RaceField
extends RefCounted

# Starterfeld eines Rennens (Spieler + Gegner), Wippen und der gemeinsame 60-Hz-Takt. main.gd und alle Tests fahren Rennen nur
# hierüber, damit Spiel und Prüfung dieselbe Taktfolge haben (docs/dioramen/HOEHEN_PLAN.md, A0):
#   Wippen (lesen die Lagen des Vortakts) -> Wippen-Entscheidungen der KI -> Ausweichen -> Fahrzeuge in Indexfolge -> Kontakte (a < b).
# Der Geist fährt mit eigenen Wippen, auf denen nur er Last ist, und berührt niemanden.
# Eigene Spuren der Gegner mit Seitenabstand zur (meist mittigen) Spielerlinie.
const RIVAL_LANES := [1.0, -1.0, 0.4]
# Spielstärke je Herausforderung (1, 2, 3 Rivalen) und Gegner; 3 = nahe am physikalischen Limit.
const RIVAL_SKILL := [[1.6], [2.3, 1.9], [3.0, 2.7, 2.3]]
const START_GAP := 0.012          # Rundkurs: Startplätze je Auto um diesen Streckenanteil zurück
const SPRINT_SLOT := 4.5          # Sprintstrecke: Meter je Startplatz hinter der Linie (entlang der Starttangente)
const SEESAW_SKILL := 1.9         # erst ab dieser Stufe nimmt die KI ein Lineal
const SEESAW_MARGIN := [0.9, 0.5] # s Sicherheitsabstand (Stufe < 2,7 bzw. darüber)
const SEESAW_CROWD := 10.0        # m: steht beim Entscheiden ein anderes Auto so nah, nimmt die KI den Umweg

var track: Circuit
var cars: Array[RaceVehicle] = []
var seesaws: Array = []           # Seesaw je Eintrag der Streckendatei
var ghost: RaceVehicle
var ghost_seesaws: Array = []
var impacts: Array = []           # Kontakte des letzten Takts: [a, b, Aufprallgeschwindigkeit]
var decisions: Array = []         # Protokoll der Wippen-Entscheidungen (Tests): [Auto, Runde, Lineal?, Ankunft s, frei ab s]

func _init(circuit: Circuit) -> void:
	track = circuit
	seesaws = Seesaw.from_track(track)

static func lane_for(i: int) -> float:
	return 0.0 if i == 0 else (1.2 if i % 2 else -1.2)

func setup(player_route: Array[Dictionary], stage: int, player_car := 0, field := -1) -> void:
	# Aufstellung wie bisher in main.gd: Spieler auf s 0, Gegner dahinter auf Spur ±1,2; Drift-Modus allein.
	cars.clear()
	var count := field if field > 0 else (1 if track.mode == "drift" else stage + 2)
	for i in range(count):
		var skill := float(RIVAL_SKILL[stage][i - 1]) if i > 0 else -1.0
		var lane := float(RIVAL_LANES[i - 1]) if i > 0 else 0.0
		var v := add_car(player_route if i == 0 else track.ai_route(skill, lane), i, player_car if i == 0 else 0, skill, lane)
		# Wippen-Route schon beim Aufstellen rechnen (kein Ruckler am Entscheidungspunkt).
		if i > 0 and skill >= SEESAW_SKILL:
			for w in seesaws:
				if w.ai and w.shortcut >= 0 and not v.has_meta("alt_route"):
					v.set_meta("alt_route", track.ai_route(skill, lane, w.shortcut))

func add_car(plan: Array[Dictionary], i: int, car := 0, skill := -1.0, lane := 0.0) -> RaceVehicle:
	var v: RaceVehicle
	if track.open and i > 0:
		# Sprintstrecke: Startplätze hinter der Linie entlang der Starttangente (at() klemmt s < 0 sonst auf die Linie).
		v = RaceVehicle.new(track, plan, 0.0, lane_for(i), car)
		var back := float(i) * SPRINT_SLOT
		v.pos = track.at(0.0, lane_for(i)) - track.tangent(0.0) * back
		v.progress = -back / track.length
		v.previous_phase = 0.0
	else:
		v = RaceVehicle.new(track, plan, -float(i) * START_GAP, lane_for(i), car)
	v.seesaws = seesaws
	v.set_meta("skill", skill)
	v.set_meta("lane", lane)
	v.set_meta("decided", -1)
	v.set_meta("main_route", plan)
	cars.append(v)
	return v

func set_ghost(v: RaceVehicle) -> void:
	ghost = v
	ghost_seesaws = Seesaw.from_track(track)
	if ghost != null:
		ghost.seesaws = ghost_seesaws

static func rival_boost(v: RaceVehicle) -> bool:
	# Turbo der Gegner: in einem festen Rhythmus über die Runde, nicht in den gesperrten Zonen vor und hinter Sprüngen.
	return absf(sin(v.progress * TAU)) < 0.35 and v.turbo > 0.25 and not v.track.boost_locked(v.progress)

func step(dt: float, time: float, player_boost := false, phase := "race", ghost_boost := false) -> void:
	# phase "race": alle Autos; "result": nur noch die Gegner (der Spieler ist im Ziel oder ausgeschieden).
	impacts.clear()
	var first := 0 if phase == "race" else 1
	for w in seesaws:
		w.step(dt, cars)
	if not seesaws.is_empty():
		decide_seesaws()
	RaceVehicle.update_avoidance(cars, dt)
	for i in range(first, cars.size()):
		var v := cars[i]
		if phase != "race" and v.finish_time >= 0.0:
			continue
		v.step(dt, player_boost if i == 0 else rival_boost(v), time)
	for a in range(first, cars.size()):
		for b in range(a + 1, cars.size()):
			if cars[a].finish_time < 0 and cars[b].finish_time < 0:
				var hit := RaceVehicle.resolve_contact(cars[a], cars[b])
				if hit > 0.0:
					impacts.append([a, b, hit])
	if ghost != null:
		for w in ghost_seesaws:
			w.step(dt, [ghost])
		ghost.step(dt, ghost_boost, time)

# ---------- Wippen-Entscheidung der KI (A3) ----------
func path_meters(v: RaceVehicle, k: int) -> float:
	# Pfadmeter eines Autos auf der Abkürzung k (aus dem Streckenanteil, wie phase_near ihn auf dem Pfad liefert).
	var sc: Dictionary = track.shortcuts[k]
	return (track.unit(v.progress) - float(sc.from)) / maxf(float(sc.to) - float(sc.from), 1e-6) * track.shortcut_length(k)

func takes_seesaw(j: int, w: Seesaw) -> bool:
	# Fährt Auto j in seiner jetzigen Runde über das Lineal? KI: Entscheidung dieser Runde; Spieler: Linie mit sc auf dem Pfad.
	var v := cars[j]
	var sc: Dictionary = track.shortcuts[w.shortcut]
	var lap := floorf(v.progress)
	if j > 0:
		return int(v.get_meta("decided", -1)) == int(lap) and v.route != v.get_meta("main_route")
	var probe := lap + (float(sc.from) + float(sc.to)) * 0.5
	for e in v.route:
		if absf(float(e.s) - probe) < 0.01:
			return int(e.get("sc", -1)) == w.shortcut
	return false

func time_to_exit(v: RaceVehicle, w: Seesaw) -> float:
	# Sekunden, bis Auto v das Ausfahrtsende des Lineals verlassen hat (Schätzung mit seinem Tempo, mindestens 6 m/s); < 0 = vorbei.
	var sc: Dictionary = track.shortcuts[w.shortcut]
	var x := track.unit(v.progress)
	var exit_m := float(w.spec.get("at", 0.0)) + w.half_len
	var remaining: float
	if x < float(sc.from):
		remaining = (float(sc.from) - x) * track.length + exit_m
	else:
		remaining = exit_m - path_meters(v, w.shortcut)
	if remaining < 0.0:
		return -1.0
	return remaining / maxf(v.velocity.length(), 6.0)

func decide_seesaws() -> void:
	# Beim Überfahren von decide (je Runde): Lineal nur, wenn die Strecke es der KI erlaubt (ai), die Stufe reicht und die
	# Einfahrtskante bei Ankunft sicher unten ist: frei ab = Maximum aus der unbelasteten Rückkehr ab (φ, ω) und, für jedes Auto vor
	# mir auf dem Lineal, dessen Zeit bis zur Ausfahrt + T_RETURN; Marge 0,9 s (Stufe < 2,7) bzw. 0,5 s. Sonst Umweg.
	for i in range(1, cars.size()):
		var v := cars[i]
		if v.crashed or v.finish_time >= 0.0:
			continue
		for w in seesaws:
			if w.decide < 0.0 or w.shortcut < 0:
				continue
			var lap := int(floorf(v.progress))
			if track.unit(v.progress) < w.decide or int(v.get_meta("decided", -1)) >= lap:
				continue
			if track.unit(v.progress) > float(track.shortcuts[w.shortcut].from):
				continue
			v.set_meta("decided", lap)
			var skill := float(v.get_meta("skill", -1.0))
			var take := false
			var arrive := 0.0
			var free_at := 0.0
			if w.ai and skill >= SEESAW_SKILL:
				var sc: Dictionary = track.shortcuts[w.shortcut]
				arrive = ((float(sc.from) - track.unit(v.progress)) * track.length + float(w.spec.get("at", 0.0)) - w.half_len) / maxf(v.velocity.length(), 6.0)
				free_at = w.predict_free()
				for j in range(cars.size()):
					if j == i:
						continue
					var o := cars[j]
					if o.crashed or o.finish_time >= 0.0 or o.progress < v.progress:
						continue
					if not takes_seesaw(j, w):
						continue
					var t_exit := time_to_exit(o, w)
					if t_exit >= 0.0:
						free_at = maxf(free_at, t_exit + Seesaw.T_RETURN)
				var margin: float = SEESAW_MARGIN[0] if skill < 2.7 else SEESAW_MARGIN[1]
				take = free_at + margin < arrive
				# Im Pulk kein Lineal: Abzweig und Einmündung liegen am Kurvenausgang; ein Auto daneben oder dicht dahinter, das dort weit
				# hinausrutscht, schob den Abkürzer neben das Lineal (Prüfung 03.10.: Wrack am Stiftende). Gilt auch für den Spieler.
				for j in range(cars.size()):
					var o := cars[j]
					if j != i and not o.crashed and o.finish_time < 0.0 and o.pos.distance_to(v.pos) < SEESAW_CROWD:
						take = false
			if take:
				if not v.has_meta("alt_route"):
					v.set_meta("alt_route", track.ai_route(skill, float(v.get_meta("lane", 0.0)), w.shortcut))
				v.route = v.get_meta("alt_route")
			else:
				v.route = v.get_meta("main_route")
			decisions.append([i, lap, take, arrive, free_at])

func done() -> bool:
	for v in cars:
		if not v.crashed and v.finish_time < 0.0:
			return false
	return true

static func player_boost_test(v: RaceVehicle) -> bool:
	# Turbo des Spieler-Ersatzes im Feldtest: eigener Rhythmus, ohne die Sperrzonen der Gegner (ein Mensch zündet auch vor dem Sprung).
	return absf(sin(v.progress * TAU * 1.5)) < 0.3 and v.turbo > 0.25

static func run_field(circuit: Circuit, stage: int, player_route: Array[Dictionary] = [], limit := 300.0, player_turbo := false) -> Dictionary:
	# Rennen ohne Darstellung wie im Spiel: Wetter der Herausforderung, Aufstellung, Ausweichen, Kontakte, Gegner-Turbo.
	# Spieler-Ersatz ai_route(2.0, 0) ohne Turbo, falls keine Linie übergeben wird; player_turbo: Spieler zündet im eigenen Rhythmus.
	var cond := circuit.conditions_for(stage)
	RaceVehicle.weather_grip = float(Atmosphere.WEATHER_GRIP.get(cond.weather, 1.0))
	var f := RaceField.new(circuit)
	f.setup(player_route if not player_route.is_empty() else circuit.ai_route(2.0, 0.0), stage)
	var time := 0.0
	var phase := "race"
	var crash_wait := 0.0
	for tick in range(int(limit * 60.0)):
		time = float(tick + 1) / 60.0
		f.step(1.0 / 60.0, time, player_turbo and RaceField.player_boost_test(f.cars[0]), phase)
		if phase == "race":
			if f.cars[0].crashed:
				crash_wait += 1.0 / 60.0
			if f.cars[0].finish_time >= 0.0 or crash_wait > 1.6:
				phase = "result"
		if f.done():
			break
	var parts: Array = []
	var times: Array = []
	var failed: Array = []
	for i in range(f.cars.size()):
		var v := f.cars[i]
		var label := "S" if i == 0 else "G%d" % i
		if v.finish_time >= 0.0:
			parts.append("%s %.2f" % [label, v.finish_time])
		else:
			var why := "Lineal" if v.edge_hit > 0.0 and v.wrecked else (("Wrack(%s)" % v.wreck_cause) if v.wrecked else ("Looping" if v.in_loop or v.loop_fall or v.rolled_back else ("Planke" if v.broke_rail else ("Lippe" if v.lip_hit > 0.0 else ("Absturz" if v.crashed else "Zeit")))))
			parts.append("%s %s s=%.3f" % [label, why, v.progress])
			if i > 0:
				failed.append({"car": i, "why": why, "s": v.progress, "x": v.pos.x, "z": v.pos.y})
		times.append(v.finish_time)
	RaceVehicle.weather_grip = 1.0
	return {"weather": str(cond.weather), "text": ", ".join(parts), "times": times, "failed": failed, "field": f}
