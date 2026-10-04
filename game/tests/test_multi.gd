extends SceneTree

# Mehrere Menschen in einem Feld (M2 „Umbau mehrere Menschen“, docs/MULTIPLAYER_RECHERCHE.md 5.3), noch ohne Netz:
#   - Teilnehmerliste: Einzelspieler-Aufstellung über setup() und über eine ausgeschriebene Liste rechnen Takt für Takt gleich.
#   - 2–4 Menschen: zweimal gerechnet identisch; Menschen weichen nie aus und treffen keine Wippen-Entscheidung; Turbo je Auto.
#   - Menschen mit KI-Linien und KI-Turbo (Berührungen aus) fahren bitgleich wie dieselben KI-Autos allein auf ihrem Startplatz.
#   - Turbo-Wechselliste (turbo_log) als Eingabe wiedergegeben ergibt dasselbe Rennen.
#   - main.gd mit „mein Auto“ = 1: Halo, Kamera, Platzanzeige und Ergebnis folgen Auto 1; das Rennen selbst hängt nicht davon ab.
const DT := 1.0 / 60.0
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
	else:
		print("PASS: ", message)

func _initialize() -> void:
	call_deferred("run")

static func same_cars(a: Array, b: Array) -> bool:
	# Exakter Vergleich des Fahrzustands (kein Runden).
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		var p: RaceVehicle = a[i]
		var q: RaceVehicle = b[i]
		if p.pos != q.pos or p.heading != q.heading or p.velocity != q.velocity or p.progress != q.progress or p.z != q.z \
				or p.vz != q.vz or p.turbo != q.turbo or p.finish_time != q.finish_time or p.crashed != q.crashed or p.avoid_offset != q.avoid_offset:
			return false
	return true

func legacy_lineup() -> void:
	# setup(route, stage) gegen die ausgeschriebene Teilnehmerliste (Mensch + KI mit Stärke/Spur aus RIVAL_SKILL/RIVAL_LANES).
	for spec in [["kids", 2], ["serra", 1], ["azure", 2]]:
		var t := Circuit.load_track(spec[0])
		var stage: int = spec[1]
		RaceVehicle.weather_grip = float(Atmosphere.WEATHER_GRIP.get(t.conditions_for(stage).weather, 1.0))
		var route := t.ai_route(2.0, 0.0)
		var a := RaceField.new(t)
		a.setup(route, stage)
		var list: Array = [RaceField.human_entry(route)]
		for k in range(stage + 1):
			list.append(RaceField.ai_entry(float(RaceField.RIVAL_SKILL[stage][k]), float(RaceField.RIVAL_LANES[k])))
		var b := RaceField.new(t)
		b.setup_entries(list)
		var same := a.human_indices() == [0] and b.human_indices() == [0] and a.cars.size() == b.cars.size()
		for tick in range(60 * 70):
			var boost := RaceField.player_boost_test(a.cars[0])
			a.step(DT, float(tick + 1) * DT, boost)
			b.step_inputs(DT, float(tick + 1) * DT, [boost])
			if not same_cars(a.cars, b.cars):
				same = false
				break
		check(same, "%s Stufe %d: Einzelspieler über setup() und über die Teilnehmerliste Takt für Takt gleich" % [spec[0], stage + 1])
	RaceVehicle.weather_grip = 1.0

func multi_humans() -> void:
	# 2–4 Menschen: Determinismus, kein Ausweichen, keine Wippen-Wahl, Turbo-Protokoll je Auto.
	for spec in [["kids", 2, 2], ["serra", 2, 3], ["quarry", 2, 4], ["harbor", 1, 2]]:
		var id: String = spec[0]
		var stage: int = spec[1]
		var n: int = spec[2]
		var t := Circuit.load_track(id)
		var plans: Array = []
		var turbo: Array = []
		for k in range(n):
			plans.append(t.ai_route(1.6 + 0.4 * k, [0.0, 0.8, -0.8, 0.4][k]))
			turbo.append(k % 2 == 0)
		var one := RaceField.run_humans(t, stage, plans, 300.0, turbo, 4)
		var two := RaceField.run_humans(Circuit.load_track(id), stage, plans, 300.0, turbo, 4)
		var f: RaceField = one.field
		check(str(one.times) == str(two.times) and one.text == two.text, "%s Stufe %d, %d Menschen + %d KI: zweimal gerechnet identisch – %s" % [id, stage + 1, n, 4 - n, one.text])
		check(f.human_indices().size() == n and f.cars.size() == 4, "%s: %d Menschen auf den ersten Startplätzen, KI füllt auf 4 auf" % [id, n])
		var humans_finish := true
		var logs_ok := true
		for k in range(n):
			humans_finish = humans_finish and f.cars[k].finish_time > 0.0
			# Turbo-Protokoll nur bei den Menschen mit Turbo-Rhythmus; KI-Autos protokollieren nie.
			logs_ok = logs_ok and ((not (f.turbo_log[k] as Array).is_empty()) == bool(turbo[k]))
		for i in range(n, 4):
			logs_ok = logs_ok and (f.turbo_log[i] as Array).is_empty()
		check(humans_finish, "%s: alle Menschen im Ziel – %s" % [id, one.text])
		check(logs_ok, "%s: Turbo-Protokoll genau für die Menschen mit Turbo" % id)
		var ai_only := true
		for d in f.decisions:
			ai_only = ai_only and not f.is_human(int(d[0]))
		check(ai_only and (id != "kids" or not f.decisions.is_empty()), "%s: Wippen-Entscheidungen nur von KI-Autos (%d)" % [id, f.decisions.size()])
	# Menschen weichen nie aus: Takt für Takt avoid_offset = 0 (Kinderzimmer, enger Start mit 3 Menschen und 1 KI).
	var kt := Circuit.load_track("kids")
	var kf := RaceField.new(kt)
	kf.build([kt.ai_route(2.0, 0.0), kt.ai_route(2.2, 0.6), kt.ai_route(1.8, -0.6)], 2, [0, 1, 2], 4)
	var still := true
	var ai_moved := false
	for tick in range(60 * 60):
		kf.step_inputs(DT, float(tick + 1) * DT, [false, true, false, true])
		for k in range(3):
			still = still and kf.cars[k].avoid_offset == 0.0 and int(kf.cars[k].get_meta("decided", -1)) == -1
		ai_moved = ai_moved or kf.cars[3].avoid_offset != 0.0
	check(still, "Menschen fahren ihre Linie: kein Ausweichversatz, keine Wippen-Entscheidung")
	print("INFO: KI-Auto hat im Pulk ausgewichen: ", ai_moved)
	# Menschen an beliebigen Startplätzen (KI auf der Pole).
	var at := Circuit.load_track("azure")
	var mixed: Array = [RaceField.ai_entry(2.3, 1.0), RaceField.human_entry(at.ai_route(2.0, 0.0), 3, "A"), RaceField.ai_entry(1.9, -1.0), RaceField.human_entry(at.ai_route(2.4, 0.0), 5, "B")]
	var m1 := RaceField.run_humans(at, 2, [], 300.0, [true, false], -1, mixed)
	var m2 := RaceField.run_humans(Circuit.load_track("azure"), 2, [], 300.0, [true, false], -1, mixed)
	var mf: RaceField = m1.field
	check(mf.human_indices() == [1, 3] and mf.first_human() == 1 and str(mf.entries[3].name) == "B" and int(mf.entries[1].car) == 3, "Teilnehmerliste: Menschen auf Platz 2 und 4, Name und Auto übernommen")
	check(str(m1.times) == str(m2.times) and float(m1.times[1]) > 0.0 and float(m1.times[3]) > 0.0, "Menschen auf Platz 2 und 4: deterministisch und im Ziel – %s" % m1.text)
	check(not (mf.turbo_log[1] as Array).is_empty() and (mf.turbo_log[3] as Array).is_empty(), "Turbo nur beim Menschen, der ihn gibt (Auto 2)")

func ai_equivalence() -> void:
	# Menschen mit den Linien der KI und deren Turbo-Rhythmus fahren – ohne Berührungen – bitgleich wie dieselben KI-Autos, jedes allein
	# auf seinem Startplatz (Ausweichen hat dort niemanden, die Wippe gibt es auf diesen Strecken nicht).
	for spec in [["azure", 2, 4], ["serra", 1, 3], ["city", 0, 2]]:
		var t := Circuit.load_track(spec[0])
		var stage: int = spec[1]
		var n: int = spec[2]
		RaceVehicle.weather_grip = 1.0
		var humans: Array = []
		var singles: Array = []
		for k in range(n):
			var skill := RaceField.ai_skill(2, k)
			var lane := float(RaceField.RIVAL_LANES[k % 3])
			humans.append(RaceField.human_entry(t.ai_route(skill, lane)))
			var solo := RaceField.new(t)
			solo.add_car(t.ai_route(skill, lane), k, 0, skill, lane, false)
			singles.append(solo)
		var f := RaceField.new(t)
		f.contacts = false
		f.setup_entries(humans)
		var same := true
		var first_diff := ""
		for tick in range(60 * 120):
			var time := float(tick + 1) * DT
			var inputs: Array = []
			for k in range(n):
				inputs.append(RaceField.rival_boost(f.cars[k]))
			f.step_inputs(DT, time, inputs)
			for k in range(n):
				var s: RaceField = singles[k]
				s.step_inputs(DT, time, [])
				if same and not same_cars([f.cars[k]], [s.cars[0]]):
					same = false
					first_diff = "Auto %d bei Takt %d" % [k, tick]
			if f.done():
				break
		var times: Array = []
		for k in range(n):
			times.append("%.2f%s" % [f.cars[k].finish_time, " (Wrack %s)" % f.cars[k].wreck_cause if f.cars[k].wrecked else (" (Absturz)" if f.cars[k].crashed else "")])
		# Bewertet wird die Gleichheit; ein Wrack der KI-Linie (Bestandsfehler, test_field: WARN) zeigt sich in beiden gleich.
		check(same and f.done(), "%s: %d Menschen mit KI-Linien (Berührungen aus) = %d KI-Autos einzeln, bitgleich %s %s" % [spec[0], n, n, first_diff, str(times)])

func turbo_replay() -> void:
	# Die protokollierten Turbo-Wechsel (turbo_log) als Eingabe ergeben dasselbe Rennen (Geist je Spieler, Wiederholung).
	var t := Circuit.load_track("harbor")
	var plans: Array = [t.ai_route(1.8, 0.0), t.ai_route(2.0, 0.8)]
	var live := RaceField.run_humans(t, 2, plans, 300.0, [true, true])
	var lf: RaceField = live.field
	var replay := RaceField.run_humans(Circuit.load_track("harbor"), 2, plans, 300.0, [lf.turbo_log[0], lf.turbo_log[1]])
	var used := not (lf.turbo_log[0] as Array).is_empty() and not (lf.turbo_log[1] as Array).is_empty()
	check(used and str(live.times) == str(replay.times) and same_cars(lf.cars, (replay.field as RaceField).cars), "Turbo-Wiedergabe aus turbo_log: identisches Rennen – %s" % live.text)

func race_in_app(app: Node, entries: Array, me: int, own_turbo: bool, remote: Dictionary) -> Dictionary:
	app.stage = 2
	app.start_drawing()
	app.recorder.route = app.track.ai_route(1.0)
	app.race_entries = entries
	app.race_me = me
	app.begin_race()
	app.remote_turbo = remote.duplicate()
	app.turbo_held = own_turbo
	for tick in range(10800):
		app._physics_process(DT)
		if app.phase == "result":
			break
	var phase: String = app.phase
	var rows: Array = app.sorted_results()
	var rank: int = app.player_result_rank(rows)
	for tick in range(6000):
		if app.field.done():
			break
		app._physics_process(DT)
	app.turbo_held = false
	var times: Array = []
	var poses: Array = []
	for v in app.vehicles:
		times.append(v.finish_time)
		poses.append(v.pos)
	return {"phase": phase, "times": times, "poses": poses, "rank": rank, "rows": rows, "log": app.field.turbo_log.duplicate(true)}

func app_checks() -> void:
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	await process_frame
	var test_path := "user://test_multi_%s.json" % Time.get_ticks_usec()
	app.store = ProgressStore.new(test_path)
	app.run_record_path = test_path + ".run"
	app.store.data["camera"] = true
	app.select_track("azure")
	var t: Circuit = app.track
	var entries: Array = RaceField.lineup([RaceField.human_entry(t.ai_route(1.8, 0.0), 0, "Eins"), RaceField.human_entry(t.ai_route(2.0, 0.0), 2, "Zwei")], 2)
	# Vor dem Start (Countdown, Autos stehen): Halo, Aussehen, Kamera und Platzanzeige gehören zu Auto 1.
	app.stage = 2
	app.start_drawing()
	app.recorder.route = t.ai_route(1.0)
	app.race_entries = entries
	app.race_me = 1
	app.begin_race()
	check(app.me == 1 and app.vehicles.size() == 4 and app.field.human_indices() == [0, 1] and app.race_entries.is_empty(), "main: zwei Menschen + zwei KI, mein Auto = 1, Teilnehmerliste verbraucht")
	check(app.models[1].has_node("Halo") and not app.models[0].has_node("Halo"), "main: Halo am eigenen Auto (1), nicht am anderen Menschen (0)")
	check(app.world.line_mesh.mesh != null and app.world.extra_lines.size() == 1, "main: im Rennen beide Linien der Menschen sichtbar (world.draw_routes)")
	var looks: Array = app.car_looks()
	check(int(looks[0]) == 0 and int(looks[1]) == 2 and not (int(looks[2]) in [0, 2]) and not (int(looks[3]) in [0, 2]) and looks[2] != looks[3], "main: Menschen mit ihrem Auto, KI in anderen Autos %s" % str(looks))
	for k in range(400):
		app._process(DT)
	var follow := lerpf(0.45, 1.0, sqrt(clampf(float(app.store.data.get("camera_zoom", 0.4)), 0.0, 1.0)))
	var c: Vector3 = app.track_center()
	var expect := []
	for i in range(2):
		var p: Vector2 = app.vehicles[i].pos
		expect.append(c + (Vector3(p.x, app.vehicles[i].z, p.y) - c) * follow)
	var cam: Vector3 = app.camera_target
	check(cam.distance_to(expect[1]) < 0.05 and cam.distance_to(expect[0]) > 0.5, "main: Kamera folgt Auto 1 (Abstand %.3f m, zu Auto 0 %.2f m)" % [cam.distance_to(expect[1]), cam.distance_to(expect[0])])
	check(app.live_rank() == 2 and app.hud.rank_label.text == "2 / 4", "main: Platzanzeige für Auto 1 (%s)" % app.hud.rank_label.text)
	# Ganzes Rennen: mein Auto 1 mit Turbo-Knopf gegen dasselbe Rennen mit mein Auto 0, Auto 1 per remote_turbo.
	var gold_before: int = app.store.data.gold.size()
	app.store.last_place = 3   # Platz aus einem früheren Einzelspieler-Rennen: darf im Mehrspieler nicht erscheinen
	var a := race_in_app(app, entries, 1, true, {})
	check(a.phase == "result", "main: Ergebnis, wenn beide Menschen fertig sind")
	var shown := ""
	for l in app.hud.content.find_children("*", "Label", true, false):
		shown += (l as Label).text + " | "
	check(not shown.contains("Gold") and not shown.contains("Bestenliste") and not shown.contains("BESTZEIT"), "main: Ergebnis mit zwei Menschen ohne Gold und ohne Platz in der Bestenliste")
	check(not (a.log[1] as Array).is_empty() and (a.log[0] as Array).is_empty(), "main: Turbo-Knopf wirkt auf mein Auto (1), nicht auf Auto 0")
	var own_rank := 0
	for row in a.rows:
		if int(row.index) == 1:
			own_rank = int(row.rank)
	check(a.rank == own_rank and own_rank > 0, "main: Ergebnisplatz ist der von Auto 1 (%d)" % own_rank)
	check(app.store.data.gold.size() == gold_before and not FileAccess.file_exists(test_path + ".run"), "main: mehrere Menschen – kein Gold, keine Bestenliste, keine letzte Fahrt")
	var b := race_in_app(app, entries, 0, false, {1: true})
	check(str(a.times) == str(b.times) and a.poses == b.poses, "main: Rennen unabhängig von „mein Auto“ (Turbo über Knopf bzw. remote_turbo) – %s" % str(a.times))
	check(not (b.log[1] as Array).is_empty() and (b.log[0] as Array).is_empty(), "main: remote_turbo wirkt auf Auto 1")
	# Danach wieder Einzelspieler: Teilnehmerliste gilt nur für ein Rennen.
	app.start_drawing()
	app.recorder.route = t.ai_route(1.0)
	app.begin_race()
	check(app.me == 0 and app.field.human_indices() == [0] and app.models[0].has_node("Halo"), "main: nächstes Rennen wieder Einzelspieler (mein Auto 0)")
	check(app.world.line_mesh.mesh != null and app.world.extra_lines.is_empty(), "main: Einzelspieler zeigt nur die eigene Linie")
	for suffix in ["", ".bak", ".tmp", ".run"]:
		if FileAccess.file_exists(test_path + suffix):
			DirAccess.remove_absolute(test_path + suffix)
	app.queue_free()
	await process_frame

func run() -> void:
	legacy_lineup()
	multi_humans()
	ai_equivalence()
	turbo_replay()
	await app_checks()
	print("RESULT: ", checks - failures, "/", checks, " passed")
	quit(1 if failures else 0)
