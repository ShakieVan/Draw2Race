extends SceneTree

# 2,5D-Physik (Leitplanke 8): Schanze, Flugphase ohne Grip, Landung, Lücke, Looping.
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
	else:
		print("PASS: ", message)

func plan(track: Circuit, speed: float) -> Array[Dictionary]:
	var route := track.ai_route(2.0)
	for p in route:
		p.speed = speed
	return route

func drive(track: Circuit, speed: float, seconds := 8.0, watch := Callable()) -> RaceVehicle:
	var v := RaceVehicle.new(track, plan(track, speed))
	# Mit Anlauf: gleich auf Zieltempo, damit die Tests das Verhalten an den Elementen prüfen.
	v.velocity = Vector2.from_angle(v.heading) * speed
	for tick in range(int(seconds * 60)):
		v.step(1.0 / 60.0, false, float(tick + 1) / 60.0)
		if watch.is_valid():
			watch.call(v)
		if v.crashed or v.finish_time >= 0.0:
			break
	return v

func meters(track: Circuit, m: float) -> float:
	return m / track.length

func _init() -> void:
	# Flache Strecke: nie in der Luft.
	var flat := Circuit.load_track("azure")
	var calm := drive(flat, 18.0, 4.0)
	check(not calm.airborne and calm.air_time == 0.0 and absf(calm.z) < 0.001, "Flache Strecke: kein Abheben")

	# Schanze auf der Startgeraden: 4 m lang, 1 m hoch.
	var jump := Circuit.load_track("azure")
	jump.ramps = [{"s": meters(jump, 8.0), "length": 4.0, "height": 1.0}]
	var peak := [0.0]
	var steer_in_air := [0.0]
	var v := drive(jump, 18.0, 4.0, func(car: RaceVehicle):
		peak[0] = maxf(peak[0], car.z)
		if car.airborne:
			steer_in_air[0] = maxf(steer_in_air[0], absf(car.yaw)))
	check(v.air_time > 0.2 and peak[0] > 1.0, "Schanze: Auto hebt ab (Flugzeit %.2f s, Scheitel %.2f m)" % [v.air_time, peak[0]])
	check(not v.airborne and not v.crashed, "Schanze: sichere Landung auf der Fahrbahn")
	var slow_jump := drive(jump, 7.0, 4.0)
	check(slow_jump.air_time < v.air_time, "Langsamer = kürzerer Flug (%.2f s gegen %.2f s)" % [slow_jump.air_time, v.air_time])

	# Lücke nach der Schanze (Sprung über eine andere Straße): 9 m ohne Boden.
	var gap := Circuit.load_track("azure")
	gap.obstacles.clear()        # hier zählt nur die Flugphase (Deko-Hindernisse prüft test_collision.gd)
	gap.obstacle_grid.clear()
	gap.ramps = [{"s": meters(gap, 8.0), "length": 5.0, "height": 1.6}]
	gap.gaps = [{"from": meters(gap, 13.05), "to": meters(gap, 22.0)}]
	var fast := drive(gap, 20.0, 4.0)
	check(not fast.crashed and fast.progress > meters(gap, 30.0), "Lücke: mit Tempo übersprungen")
	var short := drive(gap, 7.0, 4.0)
	check(short.crashed, "Lücke: zu langsam -> Absturz")

	# Looping mit 3,5 m Radius: Mindesttempo an der Einfahrt ~ sqrt(5 g R) ≈ 13 m/s (plus Luftwiderstand).
	var loop := Circuit.load_track("azure")
	loop.loops = [{"s": meters(loop, 10.0), "radius": 3.5}]
	var looped := [false]
	var top := [0.0]
	var ok_loop := drive(loop, 16.0, 5.0, func(car: RaceVehicle):
		if car.in_loop:
			looped[0] = true
			top[0] = maxf(top[0], car.z))
	check(looped[0] and not ok_loop.crashed and ok_loop.progress > meters(loop, 20.0), "Looping: mit genug Schwung durchfahren (Höhe %.1f m)" % top[0])
	var weak := drive(loop, 9.0, 5.0)
	check(weak.crashed, "Looping: zu langsam -> Absturz")

	# Gleiche Eingabe, gleiches Ergebnis (auch mit Flug).
	var again := drive(jump, 18.0, 4.0)
	check(again.pos.is_equal_approx(drive(jump, 18.0, 4.0).pos), "Flugphase reproduzierbar")

	# Sprintstrecke (offen): gewundene Bergstraße von Start zum Ziel, eine Durchfahrt.
	var pts := []
	for i in range(14):
		pts.append([i * 18.0, sin(i * 0.9) * 22.0])
	var data := {"format": 1, "id": "sprint_test", "name": "Test", "open": true, "half_width": 3.5, "points": pts}
	var file := FileAccess.open("user://sprint_test.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var sprint := Circuit.new("user://sprint_test.json")
	check(sprint.open and sprint.laps == 1 and sprint.at(0.0).distance_to(sprint.at(1.0)) > 150.0, "Sprint: offene Strecke mit getrenntem Start und Ziel")
	var runner := RaceVehicle.new(sprint, sprint.ai_route(2.0))
	for tick in range(60 * 90):
		runner.step(1.0 / 60.0, false, float(tick + 1) / 60.0)
		if runner.finish_time >= 0.0:
			break
	check(runner.finish_time > 5.0 and runner.progress >= 1.0, "Sprint: KI erreicht das Ziel (%.1f s)" % runner.finish_time)
	var pen := LineRecorder.new(sprint)
	pen.begin(sprint.at(0.0), 0.0)
	var t := 0.0
	for i in range(1, 2000):
		t += 1.0 / 60.0
		pen.sample(sprint.at(i / 1800.0), t)
		if pen.complete:
			break
	check(pen.complete and pen.gates_passed == LineRecorder.GATES_PER_LAP, "Sprint: Linie von Start bis Ziel vollständig (%d Tore)" % pen.gates_passed)
	# Abkürzung: Sehne quer durch eine Kurve der Küstenstrecke (Streckenanteil 0,20 -> 0,32).
	var cutter := Circuit.load_track("azure")
	var a0 := cutter.at(0.20)
	var b0 := cutter.at(0.32)
	var trail := []
	for i in range(11):
		var q := a0.lerp(b0, i / 10.0)
		trail.append([q.x, q.y])
	cutter.shortcuts = []
	# Pfaddaten wie beim Laden aufbereiten (ohne eigene Datei): gleiche Struktur wie Circuit._init.
	var tpath: Array[Vector2] = []
	for q in trail:
		tpath.append(Vector2(q[0], q[1]))
	var tcum := PackedFloat32Array([0.0])
	for i in range(1, tpath.size()):
		tcum.append(tcum[-1] + tpath[i - 1].distance_to(tpath[i]))
	cutter.shortcuts.append({"from": 0.20, "to": 0.32, "path": tpath, "cum": tcum, "width": 4.0, "surface": "asphalt"})
	var mid := a0.lerp(b0, 0.5)
	check(absf(cutter.phase_near(mid, 0.24) - 0.26) < 0.02, "Abkürzung: Streckenanteil läuft gleitend über den Pfad")
	# Linie: Hauptstrecke bis 0,20, dann die Sehne, dann weiter bis ins Ziel.
	var drawn := LineRecorder.new(cutter)
	drawn.begin(cutter.at(0.0), 0.0)
	var clock := 0.0
	var pts2: Array[Vector2] = []
	for i in range(1, 121):
		pts2.append(cutter.at(i * 0.20 / 120.0))
	for i in range(1, 41):
		pts2.append(a0.lerp(b0, i / 40.0))
	for i in range(1, 920):
		pts2.append(cutter.at(0.32 + i * 1.68 / 900.0))
	for q in pts2:
		clock += 1.0 / 60.0
		drawn.sample(q, clock)
		if drawn.complete or not drawn.active:
			break
	check(drawn.complete, "Abkürzung: gezeichnete Linie über den Pfad ist gültig (Tore %d, %s)" % [drawn.gates_passed, drawn.hint])
	var on_path := drawn.route.filter(func(r): return int(r.get("sc", -1)) == 0)
	check(on_path.size() > 5 and Vector2(on_path[on_path.size() / 2].p).distance_to(mid) < 4.0, "Abkürzung: Linie folgt dem Pfad statt der Kurve")
	# KI kennt Mindesttempo: fährt Looping und Lückensprung aus eigener Planung sicher.
	for kind in ["loop", "gap"]:
		var ai_track := Circuit.load_track("azure")
		ai_track.obstacles.clear()   # Schanze vor der Kurve: die Landung liegt neben der Fahrbahn bei der Deko
		ai_track.obstacle_grid.clear()
		if kind == "loop":
			ai_track.loops = [{"s": 0.51, "radius": 3.5}]   # Mitte der Gegengeraden: genug Anlauf (Mindesttempo nie über dem Kurventempo davor)
		else:
			ai_track.ramps = [{"s": meters(ai_track, 8.0), "length": 5.0, "height": 1.6}]
			ai_track.gaps = [{"from": meters(ai_track, 13.05), "to": meters(ai_track, 22.0)}]
		var bot := RaceVehicle.new(ai_track, ai_track.ai_route(1.0))
		for tick in range(60 * 70):
			bot.step(1.0 / 60.0, false, float(tick + 1) / 60.0)
			if bot.finish_time >= 0.0 or bot.crashed:
				break
		check(not bot.crashed and bot.finish_time > 0.0, "KI: %s aus eigener Planung sicher (%.1f s)" % [kind, bot.finish_time])
	# Höhenprofil: Anstieg kostet Tempo, Gefälle bringt Tempo; seitlich von der Brücke -> Absturz.
	var hill := Circuit.load_track("azure")
	hill.elevation = [[0.0, 0.0], [0.02, 0.0], [0.30, 6.0], [0.5, 6.0], [0.8, 0.0]]
	var coast_car := RaceVehicle.new(hill, plan(hill, 10.0))
	coast_car.velocity = Vector2.from_angle(coast_car.heading) * 10.0
	var flat_car := RaceVehicle.new(flat, plan(flat, 10.0))
	flat_car.velocity = Vector2.from_angle(flat_car.heading) * 10.0
	for tick in range(120):
		coast_car.step(1.0 / 60.0, false, tick / 60.0)
		flat_car.step(1.0 / 60.0, false, tick / 60.0)
	check(coast_car.velocity.length() < flat_car.velocity.length() - 0.3 and coast_car.z > 0.3, "Steigung bremst (%.1f gegen %.1f m/s, Höhe %.1f m)" % [coast_car.velocity.length(), flat_car.velocity.length(), coast_car.z])
	var bridge := Circuit.load_track("azure")
	bridge.elevation = [[0.0, 3.0]]
	var fall := RaceVehicle.new(bridge, plan(bridge, 10.0))
	fall.z = 3.0
	fall.pos += Vector2.from_angle(fall.heading).orthogonal() * 5.0
	fall.step(1.0 / 60.0, false, 0.0)
	check(fall.crashed, "Seitlich von der erhöhten Fahrbahn -> Absturz")
	# Gelände-Raster und Leitplanke: Abgrund rechts der Startgeraden (Gelände 20 m unter der Straße).
	var cliff := Circuit.load_track("azure")
	var gw := 60
	var gh := 40
	var heights := []
	for iz in range(gh):
		for ix in range(gw):
			heights.append(0.0)
	cliff.terrain = {"origin": [-60.0, -40.0], "cell": 2.0, "w": gw, "h": gh, "heights": heights}
	check(absf(cliff.terrain_height(Vector2(3, 2))) < 0.001, "Gelände-Raster: Höhe abrufbar")
	cliff.elevation = [[0.0, 20.0]]
	cliff.guardrails = [{"from": 0.9, "to": 0.3, "side": "right"}]   # über den Start hinweg
	var bump := RaceVehicle.new(cliff, plan(cliff, 10.0))
	bump.z = 20.0
	var right := Vector2.from_angle(bump.heading).orthogonal()   # Godot: orthogonal() = rechts der Fahrtrichtung
	bump.pos += right * 4.6
	bump.velocity = right * 5.0 + Vector2.from_angle(bump.heading) * 8.0
	bump.step(1.0 / 60.0, false, 0.0)
	check(not bump.crashed and bump.velocity.dot(right) <= 0.0, "Leitplanke hält bei langsamem Anprall")
	var smash := RaceVehicle.new(cliff, plan(cliff, 10.0))
	smash.z = 20.0
	smash.pos += right * 4.6
	smash.velocity = right * 14.0
	smash.step(1.0 / 60.0, false, 0.0)
	check(smash.crashed and smash.broke_rail, "Leitplanke bricht bei hartem Anprall -> Absturz")
	var left := -Vector2.from_angle(bump.heading).orthogonal()
	var over := RaceVehicle.new(cliff, plan(cliff, 10.0))
	over.z = 20.0
	over.pos += left * 4.8
	over.step(1.0 / 60.0, false, 0.0)
	check(over.crashed and not over.broke_rail, "Ohne Leitplanke: Absturz über die Kante")
	# Neue Strecken: KI kommt ohne Absturz ins Ziel (Sprung, Abkürzung, Kehren, Leitplanken).
	for id in ["harbor", "serra", "fair", "quarry", "kids"]:
		var real := Circuit.load_track(id)
		var bot2 := RaceVehicle.new(real, real.ai_route(2.3))
		for tick in range(60 * 150):
			bot2.step(1.0 / 60.0, false, float(tick + 1) / 60.0)
			if bot2.finish_time >= 0.0 or bot2.crashed:
				break
		check(not bot2.crashed and bot2.finish_time > 10.0, "Strecke %s: KI im Ziel (%.1f s)" % [id, bot2.finish_time])
	# Drift-Modus: Breitenprofil, Punkte für Drifts, Strafe bei Wandberührung, kein Einfluss im Rennmodus.
	var arena := Circuit.load_track("arena")
	check(arena.mode == "drift" and arena.hw(0.5) > 7.0 and arena.widths.size() >= 4, "Drift-Arena: weite Flächen und Nadelöhre")
	var calm_route := arena.ai_route(1.5)
	var wild_route := arena.ai_route(1.5)
	for p in wild_route:
		if arena.curvature(float(p.s)) > 0.03:
			p.speed = float(p.speed) * 1.45
	var calm_drift := RaceVehicle.new(arena, calm_route, 0.0, 0.0, 7)
	var wild_drift := RaceVehicle.new(arena, wild_route, 0.0, 0.0, 7)
	for tick in range(60 * 90):
		calm_drift.step(1.0 / 60.0, false, float(tick + 1) / 60.0)
		wild_drift.step(1.0 / 60.0, false, float(tick + 1) / 60.0)
	check(wild_drift.drift_score > calm_drift.drift_score * 2.0, "Drift: zu schnell geplante Kurven bringen Punkte (%d gegen %d)" % [int(wild_drift.drift_score), int(calm_drift.drift_score)])
	var wall_car := RaceVehicle.new(arena, calm_route)
	wall_car.drift_score = 500.0
	wall_car.pos = arena.at(0.1, arena.hw(0.1) - 0.2)
	wall_car.score_drift(1.0 / 60.0)
	check(wall_car.wall_hits == 1 and wall_car.drift_score <= 440.0 and wall_car.drift_multiplier == 1.0, "Drift: Wandberührung kostet Punkte und Multiplikator")
	var racer := drive(flat, 20.0, 3.0)
	check(racer.drift_score == 0.0, "Rennmodus: keine Drift-Wertung")
	print("RESULT: ", checks - failures, "/", checks, " passed")
	quit(1 if failures else 0)
