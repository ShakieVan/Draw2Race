class_name RaceField
extends RefCounted

# Starterfeld eines Rennens (Spieler + Gegner), Wippen und der gemeinsame 60-Hz-Takt. main.gd und alle Tests fahren Rennen nur
# hierüber, damit Spiel und Prüfung dieselbe Taktfolge haben (docs/dioramen/HOEHEN_PLAN.md, A0):
#   Wippen (lesen die Lagen des Vortakts) -> Wippen-Entscheidungen der KI -> Ausweichen -> Fahrzeuge in Indexfolge -> Kontakte (a < b).
# Der Geist fährt mit eigenen Wippen, auf denen nur er Last ist, und berührt niemanden.
# Teilnehmerliste (seit 03.10.2026, M2 „mehrere Menschen“, docs/MULTIPLAYER_RECHERCHE.md 5.3): ein Eintrag je Auto, Listenplatz =
# Startplatz = Index in cars. Menschen fahren ihre Linie (kein Ausweichen, keine Wippen-Wahl, Turbo als Eingabe je Auto), KI wie bisher.
# Der Einzelspieler ist der Sonderfall „ein Mensch auf Startplatz 0“ (setup) und bleibt bitgleich.
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
var post_state: Dictionary = {}   # Randpfosten dieses Rennens (RaceVehicle.post_state): alle Autos teilen ihn, der Geist hat einen eigenen
var impacts: Array = []           # Kontakte des letzten Takts: [a, b, Aufprallgeschwindigkeit]
var decisions: Array = []         # Protokoll der Wippen-Entscheidungen (Tests): [Auto, Runde, Lineal?, Ankunft s, frei ab s]
# Teilnehmer (je Auto ein Dictionary, siehe human_entry/ai_entry; zusätzlich "slot" = Startplatz). Weitere Schlüssel (z. B. "look"
# für Karosserie und Farbe, "peer" fürs Netz) reicht RaceField unverändert durch.
var entries: Array[Dictionary] = []
var human_mask: Array[bool] = []  # je Auto: Mensch?
var contacts := true              # false: Autos berühren sich nicht (Lobby-Schalter „Berührungen aus“, Drift zu mehreren)
var turbo_log: Array = []         # je Auto die Turbo-Wechsel der Menschen: [{time, held}] (Geist/Wiederholung je Spieler, 5.5)
var turbo_last: Array[bool] = []
var turbo_input: Array[bool] = [] # Puffer der Einzelspieler-Form step()

func _init(circuit: Circuit) -> void:
	track = circuit
	seesaws = Seesaw.from_track(track)

static func lane_for(i: int) -> float:
	return 0.0 if i == 0 else (1.2 if i % 2 else -1.2)

# ---------- Teilnehmerliste ----------
static func human_entry(plan: Array, car := 0, name := "") -> Dictionary:
	# Mensch: fährt seine gezeichnete Linie mit dem gewählten Auto (Physik), Turbo kommt als Eingabe (step_inputs).
	return {"human": true, "name": name, "car": car, "plan": plan, "skill": -1.0, "lane": 0.0}

static func ai_entry(skill: float, lane: float, car := 0, name := "", plan: Array = []) -> Dictionary:
	# KI-Gegner: Route ai_route(skill, lane) beim Aufstellen (oder die übergebene Linie), Turbo im festen Rhythmus (rival_boost).
	# car = Physik (die KI fährt bisher das Grundmodell 0; Karosserie und Klang wählt die Darstellung).
	return {"human": false, "name": name, "car": car, "plan": plan, "skill": skill, "lane": lane}

static func ai_skill(stage: int, k: int) -> float:
	# Stärke des k-ten KI-Autos (0 = erstes) einer Herausforderung; mehr KI als Einträge: die letzte Stufe wiederholt sich.
	var row: Array = RIVAL_SKILL[clampi(stage, 0, RIVAL_SKILL.size() - 1)]
	return float(row[mini(k, row.size() - 1)])

static func lineup(humans: Array, stage: int, field := -1, drift := false) -> Array[Dictionary]:
	# Menschen auf den ersten Startplätzen (in Listenfolge), KI füllt auf: field > 0 Autos insgesamt, sonst wie im Einzelspieler
	# stage + 2 (Drift-Modus: nur die Menschen); nie weniger Autos als Menschen. Die KI bekommt Stärke und Spur der Reihe nach
	# (RIVAL_SKILL, RIVAL_LANES) – mit einem Menschen genau die bisherige Aufstellung.
	var list: Array[Dictionary] = []
	for h in humans:
		list.append(h)
	var count := field if field > 0 else (humans.size() if drift else stage + 2)
	count = maxi(count, humans.size())
	for k in range(count - humans.size()):
		list.append(ai_entry(ai_skill(stage, k), float(RIVAL_LANES[k % RIVAL_LANES.size()])))
	return list

static func as_plan(data) -> Array[Dictionary]:
	# Linie als Array[Dictionary]; eine schon typisierte Linie wird nicht kopiert (Einzelspieler: dieselbe Route wie bisher).
	if data is Array and (data as Array).get_typed_builtin() == TYPE_DICTIONARY:
		return data
	var plan: Array[Dictionary] = []
	if data is Array:
		plan.assign(data)
	return plan

func setup(player_route: Array[Dictionary], stage: int, player_car := 0, field := -1) -> void:
	# Einzelspieler wie bisher in main.gd: Spieler auf s 0, Gegner dahinter auf Spur ±1,2; Drift-Modus allein.
	setup_entries(lineup([human_entry(player_route, player_car)], stage, field, track.mode == "drift"))

func build(plans: Array, stage: int, human_cars: Array = [], field := -1) -> void:
	# Mehrere Menschen (Weitergeben, Netz): je Linie ein Mensch (Auto aus human_cars, sonst 0), KI füllt auf wie lineup().
	var humans: Array = []
	for k in range(plans.size()):
		humans.append(human_entry(plans[k], int(human_cars[k]) if k < human_cars.size() else 0))
	setup_entries(lineup(humans, stage, field, track.mode == "drift"))

func setup_entries(list: Array) -> void:
	# Aufstellung aus der Teilnehmerliste: Listenplatz = Startplatz (Rundkurs: um START_GAP zurück, Spur ±1,2; Sprint: SPRINT_SLOT).
	cars.clear()
	entries.clear()
	human_mask.clear()
	turbo_log.clear()
	turbo_last.clear()
	post_state = {}
	for i in range(list.size()):
		var e: Dictionary = (list[i] as Dictionary).duplicate()
		e["slot"] = i
		var human := bool(e.get("human", false))
		var skill := float(e.get("skill", -1.0))
		var lane := float(e.get("lane", 0.0))
		var plan := as_plan(e.get("plan", []))
		if plan.is_empty():
			# KI: Route aus Stärke und Spur. Mensch ohne Linie (z. B. Abbruch vor dem Zeichnen): vorsichtige Ersatzlinie.
			plan = track.ai_route(skill, lane) if not human else track.ai_route(1.0, 0.0)
		e["plan"] = plan
		entries.append(e)
		var v := add_car(plan, i, int(e.get("car", 0)), skill, lane, human)
		# Wippen-Route schon beim Aufstellen rechnen (kein Ruckler am Entscheidungspunkt).
		if not human and skill >= SEESAW_SKILL:
			for w in seesaws:
				if w.ai and w.shortcut >= 0 and not v.has_meta("alt_route"):
					v.set_meta("alt_route", track.ai_route(skill, lane, w.shortcut))

func is_human(i: int) -> bool:
	return i >= 0 and i < human_mask.size() and human_mask[i]

func human_indices() -> Array[int]:
	var list: Array[int] = []
	for i in range(human_mask.size()):
		if human_mask[i]:
			list.append(i)
	return list

func human_count() -> int:
	return human_indices().size()

func first_human() -> int:
	# Index des ersten Menschen (Einzelspieler: 0); -1, wenn nur KI fährt.
	return human_mask.find(true)

func add_car(plan: Array[Dictionary], i: int, car := 0, skill := -1.0, lane := 0.0, human := false) -> RaceVehicle:
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
	v.post_state = post_state
	v.set_meta("skill", skill)
	v.set_meta("lane", lane)
	v.set_meta("decided", -1)
	v.set_meta("main_route", plan)
	cars.append(v)
	human_mask.append(human)
	turbo_log.append([])
	turbo_last.append(false)
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
	# Einzelspieler-Form: player_boost ist der Turbo des ersten Menschen (im Einzelspieler Auto 0), weitere Menschen ohne Turbo.
	if turbo_input.size() != cars.size():
		turbo_input.resize(cars.size())
	var first := first_human()
	for i in range(turbo_input.size()):
		turbo_input[i] = player_boost and i == first
	step_inputs(dt, time, turbo_input, phase, ghost_boost)

func step_inputs(dt: float, time: float, turbo: Array, phase := "race", ghost_boost := false) -> void:
	# Ein 60-Hz-Takt. turbo[i]: Turbo-Eingabe des Menschen auf Auto i (KI-Einträge werden ignoriert, fehlende gelten als aus).
	# phase "race": alle Autos; "result": nur noch die KI (alle Menschen sind im Ziel oder ausgeschieden; sie stehen still und
	# berühren niemanden mehr).
	impacts.clear()
	var racing := phase == "race"
	for w in seesaws:
		w.step(dt, cars)
	if not seesaws.is_empty():
		decide_seesaws()
	RaceVehicle.update_avoidance(cars, dt, human_mask)
	for i in range(cars.size()):
		var v := cars[i]
		var human := is_human(i)
		if not racing and (human or v.finish_time >= 0.0):
			continue
		var boost: bool
		if human:
			boost = i < turbo.size() and bool(turbo[i])
			if boost != turbo_last[i]:
				turbo_log[i].append({"time": time, "held": boost})
				turbo_last[i] = boost
		else:
			boost = rival_boost(v)
		v.step(dt, boost, time)
	if contacts:
		for a in range(cars.size()):
			if not racing and is_human(a):
				continue
			for b in range(a + 1, cars.size()):
				if not racing and is_human(b):
					continue
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
	# Fährt Auto j in seiner jetzigen Runde über das Lineal? KI: Entscheidung dieser Runde; Mensch: Linie mit sc auf dem Pfad.
	var v := cars[j]
	var sc: Dictionary = track.shortcuts[w.shortcut]
	var lap := floorf(v.progress)
	if not is_human(j):
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
	# Nur KI-Autos entscheiden; ein Mensch fährt seine Linie.
	for i in range(cars.size()):
		var v := cars[i]
		if is_human(i) or v.crashed or v.finish_time >= 0.0:
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
	return run_humans(circuit, stage, [player_route], limit, [player_turbo])

static func run_humans(circuit: Circuit, stage: int, plans: Array, limit := 300.0, turbo: Array = [], field := -1, entries_override: Array = []) -> Dictionary:
	# Wie run_field, mit einem Menschen je Linie in plans (Startplätze 0 … n−1, KI füllt auf wie lineup(); leere Linie = Spieler-Ersatz
	# ai_route(2.0, 0)). turbo[k]: Mensch k zündet im eigenen Rhythmus (player_boost_test), ein Array statt bool = feste Turbo-Wechsel
	# [{time, held}] (Wiedergabe von turbo_log). entries_override: fertige Teilnehmerliste statt plans (Menschen an beliebigen Plätzen).
	# Ergebnisphase, sobald alle Menschen im Ziel oder 1,6 s ausgeschieden sind (mit einem Menschen genau wie bisher).
	var cond := circuit.conditions_for(stage)
	RaceVehicle.weather_grip = float(Atmosphere.WEATHER_GRIP.get(cond.weather, 1.0))
	var f := RaceField.new(circuit)
	if entries_override.is_empty():
		var humans: Array = []
		for plan in plans:
			humans.append(human_entry(plan if not (plan as Array).is_empty() else circuit.ai_route(2.0, 0.0)))
		f.setup_entries(lineup(humans, stage, field, circuit.mode == "drift"))
	else:
		f.setup_entries(entries_override)
	var people := f.human_indices()
	var inputs: Array[bool] = []
	inputs.resize(f.cars.size())
	var crash_wait: Array[float] = []
	crash_wait.resize(f.cars.size())
	var time := 0.0
	var phase := "race"
	for tick in range(int(limit * 60.0)):
		time = float(tick + 1) / 60.0
		for k in range(people.size()):
			var rule = turbo[k] if k < turbo.size() else false
			var i := people[k]
			inputs[i] = replay_turbo(rule, time) if rule is Array else (bool(rule) and RaceField.player_boost_test(f.cars[i]))
		f.step_inputs(1.0 / 60.0, time, inputs, phase)
		if phase == "race":
			var all_done := true
			for i in people:
				if f.cars[i].crashed:
					crash_wait[i] += 1.0 / 60.0
				if not (f.cars[i].finish_time >= 0.0 or crash_wait[i] > 1.6):
					all_done = false
			if all_done:
				phase = "result"
		if f.done():
			break
	var parts: Array = []
	var times: Array = []
	var failed: Array = []
	var number := 0
	for i in range(f.cars.size()):
		var v := f.cars[i]
		var label := "G%d" % i
		if f.is_human(i):
			number += 1
			label = "S" if people.size() == 1 else "S%d" % number
		if v.finish_time >= 0.0:
			parts.append("%s %.2f" % [label, v.finish_time])
		else:
			var why := "Lineal" if v.edge_hit > 0.0 and v.wrecked else (("Wrack(%s)" % v.wreck_cause) if v.wrecked else ("Looping" if v.in_loop or v.loop_fall or v.rolled_back else ("Planke" if v.broke_rail else ("Lippe" if v.lip_hit > 0.0 else ("Absturz" if v.crashed else "Zeit")))))
			parts.append("%s %s s=%.3f" % [label, why, v.progress])
			if not f.is_human(i):
				failed.append({"car": i, "why": why, "s": v.progress, "x": v.pos.x, "z": v.pos.y})
		times.append(v.finish_time)
	RaceVehicle.weather_grip = 1.0
	return {"weather": str(cond.weather), "text": ", ".join(parts), "times": times, "failed": failed, "field": f, "humans": people}

static func replay_turbo(actions: Array, time: float) -> bool:
	# Turbo-Zustand zur Zeit time aus einer Wechselliste [{time, held}] (turbo_log, Geisterdatei).
	var held := false
	for action in actions:
		if float(action.time) <= time:
			held = bool(action.held)
		else:
			break
	return held
