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
	# Kurven 85 % zu schnell geplant. Bis bicycle-6 genügten 45 %: Der Vorzeichenfehler legte jede Kurve mit 11–15° Schein-Drift hin.
	# Mit dem richtigen Einspurmodell und dem alten Fahrer fuhr der Drift King eine 45-%-Linie noch mit Haftung (×1,45 0 Punkte, ×1,7 1493,
	# ×1,85 2223); seit dem Profi-Drifter driftet er schon ab ×1,2 (Fahrweise, Linientreue und Ziele: tests/test_drift.gd).
	for p in wild_route:
		if arena.curvature(float(p.s)) > 0.03:
			p.speed = float(p.speed) * 1.85
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
	test_bicycle()
	test_rear_drive()
	test_drift_throttle(arena, wild_route)
	print("RESULT: ", checks - failures, "/", checks, " passed")

func test_track(name: String, pts: Array, hw: float, elevation := []) -> Circuit:
	# Prüfstrecke ohne Hindernisse und Deko (user://): hier zählt nur das Fahrwerk.
	var data := {"format": 1, "id": name, "name": name, "laps": 2, "points": pts, "widths": [[0.0, hw], [0.5, hw]]}
	if not elevation.is_empty():
		data["elevation"] = elevation
	var file := FileAccess.open("user://%s.json" % name, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	return Circuit.new("user://%s.json" % name)

func oval_track(hill := false) -> Circuit:
	# 400-m-Geraden mit Halbkreisen R 60 m. hill: die erste Gerade steigt gleichmäßig um 30 m (rund 8 %), die zweite fällt wieder
	# (mehr als 16 Stützpunkte: linear statt weich interpoliert).
	var elevation := []
	if hill:
		for k in range(18):
			elevation.append([0.02 * k, 30.0 * k / 17.0])
		for k in range(18):
			elevation.append([0.5 + 0.02 * k, 30.0 * (17 - k) / 17.0])
	var pts := []
	for i in range(41):
		pts.append([i * 10.0, 0.0])
	for i in range(1, 12):
		pts.append([400.0 + 60.0 * cos(-PI * 0.5 + PI * i / 12.0), 60.0 + 60.0 * sin(-PI * 0.5 + PI * i / 12.0)])
	for i in range(41):
		pts.append([400.0 - i * 10.0, 120.0])
	for i in range(1, 12):
		pts.append([60.0 * cos(PI * 0.5 + PI * i / 12.0), 60.0 + 60.0 * sin(PI * 0.5 + PI * i / 12.0)])
	return test_track("air_hill" if hill else "air_oval", pts, 8.0, elevation)

func circle_track(radius: float) -> Circuit:
	var pts := []
	for i in range(72):
		pts.append([radius * cos(TAU * i / 72.0), radius * sin(TAU * i / 72.0)])
	return test_track("air_circle_%d" % int(radius), pts, 9.0)

func steady_route(track: Circuit, speed: float, lane := 0.0) -> Array[Dictionary]:
	var route := track.ai_route(1.5)
	for p in route:
		p.speed = speed
		p.p = track.at(float(p.s), lane)
	return route

func test_bicycle() -> void:
	# bicycle-7 (15.10.2026): Vorzeichen des Einspurmodells. "Links" = Richtung positiver Gierrate und positiven Lenkwinkels. Bis bicycle-6 drückte
	# die Vorderachse beim Einlenken erst nach außen (−1,6 m/s² im ersten Takt), und jede Kurve lief mit 11–15° Schein-Drift.
	RaceVehicle.weather_grip = 1.0
	var oval := oval_track()
	var car := RaceVehicle.new(oval, steady_route(oval, 12.0, 1.5), 0.02)
	car.velocity = Vector2.from_angle(car.heading) * 12.0
	var a_lat := 0.0
	for tick in range(30):
		var left := Vector2.from_angle(car.heading + PI * 0.5)
		var before := car.velocity
		car.step(1.0 / 60.0, false, float(tick + 1) / 60.0)
		if car.steering > 0.0:
			a_lat = (car.velocity - before).dot(left) * 60.0
			break
	check(car.steering > 0.0 and a_lat > 0.5 and car.yaw > 0.0,
		"Einlenken nach links: Seitenkraft nach links (%.2f m/s²) und Gier nach links (%.3f rad/s)" % [a_lat, car.yaw])
	# Stationäre Kreisfahrt R 40 m mit 15 m/s (5,7 m/s² quer): kleiner Schwimmwinkel, die Nase leicht innen (vorher 6,2°).
	var ring := circle_track(40.0)
	var round_car := RaceVehicle.new(ring, steady_route(ring, 17.0))
	round_car.velocity = Vector2.from_angle(round_car.heading) * 17.0
	var beta := 0.0
	for tick in range(60 * 16):
		round_car.step(1.0 / 60.0, false, float(tick + 1) / 60.0)
		if tick >= 60 * 8:
			beta += wrapf(round_car.heading - round_car.velocity.angle(), -PI, PI) / (60.0 * 8.0)
	check(rad_to_deg(beta) > 0.0 and rad_to_deg(beta) < 4.0 and absf(round_car.pos.length() - 40.0) < 1.5,
		"Kreisfahrt R 40 m: Schwimmwinkel %.2f° (Nase innen, < 4°), Radius %.2f m" % [rad_to_deg(beta), round_car.pos.length()])
	# Kurven einer echten Strecke (Azure, ai_route 2.3): kein Schein-Drift mehr (bicycle-6: Ø 11,4°, 27 % der Kurventakte über 12°).
	var azure := Circuit.load_track("azure")
	var racer := RaceVehicle.new(azure, azure.ai_route(2.3))
	var sum := 0.0
	var n := 0
	var over := 0
	for tick in range(60 * 60):
		racer.step(1.0 / 60.0, false, float(tick + 1) / 60.0)
		if racer.finish_time >= 0.0 or racer.crashed:
			break
		if racer.velocity.length() > 5.0 and azure.curvature(azure.unit(racer.progress)) > 0.04:
			var b := absf(wrapf(racer.heading - racer.velocity.angle(), -PI, PI))
			sum += b
			n += 1
			if b > deg_to_rad(12.0):
				over += 1
	check(n > 100 and rad_to_deg(sum / n) < 3.0 and over == 0,
		"Azure-Kurven: Schwimmwinkel im Mittel %.2f°, %d von %d Takten über 12°" % [rad_to_deg(sum / maxf(1, n)), over, n])
	# Stillstand mit vollem Lenkeinschlag: Ohne Rollen und Rutschen baut der Reifen keine Seitenkraft auf, das Auto dreht nicht auf der Stelle
	# (bisher 59° in 2 s).
	var still := RaceVehicle.new(oval, steady_route(oval, 0.0), 0.05)
	still.heading -= PI * 0.5
	var h0 := still.heading
	for tick in range(120):
		still.step(1.0 / 60.0, false, float(tick + 1) / 60.0)
	check(absf(still.steering) > 0.3 and absf(still.heading - h0) < 0.01 and still.velocity.length() < 0.01,
		"Stillstand, voll eingelenkt: keine Drehung auf der Stelle (%.2f°)" % rad_to_deg(still.heading - h0))

func launch(track: Circuit, car: int, boost: bool) -> Dictionary:
	# Anfahren auf der Geraden (Plantempo 29 m/s): Zeit bis 20 m/s, größte Beschleunigung, größtes rear_spin.
	var v := RaceVehicle.new(track, steady_route(track, 29.0), 0.0, 0.0, car)
	var t20 := -1.0
	var spin := 0.0
	var spin_min := 0.0
	var acc := 0.0
	for tick in range(600):
		var before := v.velocity
		var forward := Vector2.from_angle(v.heading)
		v.step(1.0 / 60.0, boost, float(tick + 1) / 60.0)
		spin = maxf(spin, v.rear_spin)
		spin_min = minf(spin_min, v.rear_spin)
		acc = maxf(acc, (v.velocity - before).dot(forward) * 60.0)    # Längsbeschleunigung (ohne die kleinen Seitenkräfte beim Anrollen)
		if v.velocity.length() >= 20.0:
			t20 = float(tick + 1) / 60.0
			break
	return {"t20": t20, "spin": spin, "spin_min": spin_min, "acc": acc}

func pull(track: Circuit, s: float, speed: float) -> Dictionary:
	# Ein Takt Vollgas des Drift King bei Tempo speed an Stelle s (Plantempo 29 m/s): rear_spin, Längsbeschleunigung und Hangabtrieb dort.
	var v := RaceVehicle.new(track, steady_route(track, 29.0), s, 0.0, 7)
	var forward := Vector2.from_angle(v.heading)
	v.velocity = forward * speed
	var grade := (track.ground_height(s + 1.0 / track.length) - track.ground_height(s))
	v.step(1.0 / 60.0, false, 1.0 / 60.0)
	return {"spin": v.rear_spin, "acc": (v.velocity.dot(forward) - speed) * 60.0, "slope": RaceVehicle.GRAVITY * grade / sqrt(1.0 + grade * grade), "car": v}

func test_rear_drive() -> void:
	# Antriebsart je Auto (15.10.2026): Der Drift King hat Heckantrieb. Sein Vortrieb läuft allein über den Reibkreis der Hinterachse
	# (Haftung · Anteil hinten); was der nicht überträgt, dreht durch (rear_spin) und fehlt der Beschleunigung. bicycle-6: 0–20 m/s in 2,45 s.
	var oval := oval_track()
	var spec: Dictionary = RaceVehicle.CARS[7]
	check(str(spec.id) == "drift" and str(spec.get("drive", "")) == "rwd", "Drift King: Heckantrieb (drive = rwd)")
	var dk := launch(oval, 7, false)
	var traction := float(spec.grip) * float(spec.rear)
	check(float(dk.t20) >= 3.3 and float(dk.t20) <= 3.8 and float(dk.spin) > 2.0 and float(dk.acc) <= traction + 0.01,
		"Drift King: 0–20 m/s in %.2f s (Ziel 3,3–3,8), Hinterräder drehen beim Anfahren durch (rear_spin bis %.2f m/s²), Beschleunigung höchstens die Traktion (%.2f ≤ %.2f m/s²)" % [dk.t20, dk.spin, dk.acc, traction])
	var turbo := launch(oval, 7, true)
	check(float(turbo.acc) <= traction + 0.01 and float(turbo.spin) > float(dk.spin),
		"Drift King mit Turbo: Traktion begrenzt (%.2f m/s²), mehr Durchdrehen (%.2f m/s²)" % [turbo.acc, turbo.spin])
	# Hangabtrieb greift am Wagen an, nicht über den Reifen: Bergauf drehen die Räder genauso durch wie in der Ebene, und der Wagen beschleunigt
	# um den Hangabtrieb weniger. Bis zur Nachbesserung lief die Steigung durch den Reibkreis: bergauf weniger Durchdrehen bei voller Traktion.
	var flat_pull := pull(oval, 0.15, 8.0)
	var hill_pull := pull(oval_track(true), 0.15, 8.0)
	check(float(hill_pull.slope) > 0.5 and float(flat_pull.spin) > 1.0 and absf(float(hill_pull.spin) - float(flat_pull.spin)) < 0.02
		and absf(float(flat_pull.acc) - float(hill_pull.acc) - float(hill_pull.slope)) < 0.05,
		"Drift King bergauf (Hangabtrieb %.2f m/s²): rear_spin %.2f wie in der Ebene (%.2f), Beschleunigung %.2f statt %.2f m/s²" % [hill_pull.slope, hill_pull.spin, flat_pull.spin, hill_pull.acc, flat_pull.acc])
	# rear_spin ist eine reine Anzeigegröße: nie negativ, 0 nach einem Wrack und im Ziel (dort wird nicht mehr gerechnet, sonst qualmte das
	# Auto mit dem letzten Wert weiter).
	var wrecked: RaceVehicle = flat_pull.car
	var spun := wrecked.rear_spin
	wrecked.wreck()
	var finisher := RaceVehicle.new(oval, steady_route(oval, 29.0), 1.995, 0.0, 7)
	finisher.velocity = Vector2.from_angle(finisher.heading) * 8.0
	var spin_before := 0.0
	for tick in range(240):
		finisher.step(1.0 / 60.0, false, float(tick + 1) / 60.0)
		if finisher.finish_time >= 0.0:
			break
		spin_before = finisher.rear_spin
	check(float(dk.spin_min) >= 0.0 and float(turbo.spin_min) >= 0.0 and spun > 1.0 and wrecked.rear_spin == 0.0
		and finisher.finish_time >= 0.0 and spin_before > 1.0 and finisher.rear_spin == 0.0,
		"rear_spin: nie negativ, nach dem Wrack 0 (vorher %.2f), im Ziel 0 (davor %.2f m/s²)" % [spun, spin_before])
	var others := 0.0
	var v8 := {}
	for car in range(7):
		var r := launch(oval, car, true)
		others = maxf(others, float(r.spin))
		if str(RaceVehicle.CARS[car].id) == "muscle":
			v8 = launch(oval, car, false)
	check(others == 0.0 and float(v8.t20) < float(dk.t20) - 0.8,
		"Allrad-Grundmodell: rear_spin bleibt 0 (auch mit Turbo); Thunder V8 0–20 m/s in %.2f s" % float(v8.t20))
	# Gas in der Kurve (R 25 m, 11 m/s, dann Plantempo 25): Beim Heckantrieb kommt das Heck (Nase weiter innen, Bahn enger),
	# das Allrad-Grundauto schiebt dagegen eher nach außen. Geprüft wird das Fahrwerk: ohne die Gasdosierung des Rennfahrers (driver_tc), die
	# das Heck seit dem 15.10.2026 (Durchdrehen überträgt den Antrieb, traction) im Rennen gerade nicht kommen lässt.
	var ring := circle_track(25.0)
	var result := {}
	for car in [0, 7]:
		var route := steady_route(ring, 11.0)
		var v := RaceVehicle.new(ring, route, 0.0, 0.0, car)
		v.driver_tc = false
		v.velocity = Vector2.from_angle(v.heading) * 11.0
		var beta := -9.0
		var spin := 0.0
		for tick in range(60 * 8):
			if tick == 60 * 6:
				for p in route:
					p.speed = 25.0
			v.step(1.0 / 60.0, false, float(tick + 1) / 60.0)
			if tick >= 60 * 6:
				beta = maxf(beta, wrapf(v.heading - v.velocity.angle(), -PI, PI))
				spin = maxf(spin, v.rear_spin)
		result[car] = [rad_to_deg(beta), spin, v.crashed]
	check(float(result[7][0]) > float(result[0][0]) + 2.0 and float(result[7][1]) > 1.0 and not result[7][2],
		"Gas in der Kurve: Heck kommt beim Drift King (Nase %.1f° innen gegen %.1f° beim Grundauto, rear_spin %.2f m/s²)" % [result[7][0], result[0][0], result[7][1]])

func slide_stats(track: Circuit, route: Array[Dictionary]) -> Dictionary:
	# Drift-Auto auf der Route; ausgewertet werden die Takte, in denen es quer rutscht (> 15°) und auf der Fahrbahn bleibt.
	RaceVehicle.weather_grip = 1.0
	var v := RaceVehicle.new(track, route, 0.0, 0.0, 7)
	var slides := 0
	var braked := 0
	var capped := 0
	var min_ratio := 9.0
	var sum_ratio := 0.0
	var sum_throttle := 0.0
	for tick in range(60 * 90):
		v.step(1.0 / 60.0, false, float(tick + 1) / 60.0)
		if v.finish_time >= 0.0 or v.crashed:
			break
		var speed := v.velocity.length()
		var plan_speed := float(route[v.cursor].speed)
		if speed > 6.0 and absf(wrapf(v.velocity.angle() - v.heading, -PI, PI)) > deg_to_rad(15.0) and not v.beyond_edge(0.0):
			slides += 1
			if v.braking > 0.0 and speed < plan_speed:
				braked += 1
			if v.recovering:
				capped += 1
			min_ratio = minf(min_ratio, speed / plan_speed)
			sum_ratio += speed / plan_speed
			sum_throttle += v.throttle
	return {"car": v, "slides": slides, "braked": braked, "capped": capped, "min_ratio": min_ratio, "mean_ratio": sum_ratio / maxf(1.0, slides),
		"throttle": sum_throttle / maxf(1.0, slides)}

func test_drift_throttle(arena: Circuit, wild_route: Array[Dictionary]) -> void:
	# Seit 03.10.2026: Im Drift-Modus gibt es beim Rutschen keinen Erholungsdeckel; Abflug, Dreher und Wandkontakt entstehen aus der Fahrphysik
	# (seit 15.10.2026 mit dem Profi-Drifter, der den Winkel mit dem Gas hält). Seit dem Nutzerplan vom 15.10.2026 bremst er vor einer Kurve
	# auf das Tempo, mit dem er sie beim Zielwinkel hält (drift_line), auch unter das Plantempo – quer rutschend kaum (höchstens 3 % der Takte
	# quer: am Kurvenausgang vor der nächsten Kurve und, seit 16.10.2026, bei zu schnell gezeichneten Kurven vor dem Anstellen unter 20°,
	# gemessen 26 von 1228). Dieselbe Linie im Rennmodus siehe unten.
	var drift := slide_stats(arena, wild_route)
	var drift_car: RaceVehicle = drift.car
	check(int(drift.slides) > 300 and int(drift.braked) * 100 <= int(drift.slides) * 3 and int(drift.capped) == 0,
		"Drift-Modus: %d Takte quer, dabei kaum unter Plan gebremst (%d) und kein Erholungsdeckel (%d)" % [drift.slides, drift.braked, drift.capped])
	# Seit bicycle-7 (15.10.2026) kostet echtes Querrutschen Tempo (die Reifen reiben quer zur Fahrt); der Schein-Drift lief bei über 78 % des
	# Plans. Seit dem Profi-Drifter (drift_driver, 15.10.2026) hält das Gas den Driftwinkel, statt stur auf dem Plan zu bleiben: Vollgas, wenn
	# Winkel fehlt, Lupfen bei zu viel (gemessen 58 % im Mittel, vorher 93 %); über das Plantempo gibt er nie Gas (tests/test_drift.gd).
	# Geprüft wird, dass er im Drift Gas gibt, ohne Vollgas zu halten, und das Tempo nicht einbricht.
	check(float(drift.throttle) > 0.4 and float(drift.throttle) < 0.9 and float(drift.mean_ratio) > 0.55,
		"Drift-Modus: Fahrer hält den Winkel mit dem Gas (Gas im Mittel %.0f %%, Tempo im Mittel %.0f %%, min. %.0f %% des Plans)" % [float(drift.throttle) * 100.0, float(drift.mean_ratio) * 100.0, float(drift.min_ratio) * 100.0])
	var race_arena := Circuit.load_track("arena")
	race_arena.mode = "race"
	var race := slide_stats(race_arena, wild_route)
	var race_car: RaceVehicle = race.car
	# Der frühere Vergleich "Rennmodus im Mittel 10 % langsamer im Rutschen" entfällt: Beide Modi verlieren beim echten Rutschen Tempo. Der
	# Unterschied der Modi ist der Rückkehr-Deckel. Seit dem Fahrer-Regler vom 15.10.2026 (Rückkehr-Episoden) ist er stetig: Das Rückkehrtempo
	# folgt dem fahrbaren Bogen (nie unter 7 m/s), und quer rutschend bremst der Fahrer höchstens mit BRAKE_FLOOR (vorher Vollbremsung auf
	# 7 m/s, die das Heck kommen ließ). Unter den Plan gebremst wird deshalb kaum noch, und im Mittel ist der Rennmodus beim Rutschen nicht
	# mehr langsamer (gemessen 69 % gegen 63 % des Plans); geprüft wurde, dass der Deckel greift (im Drift-Modus nie, siehe oben). Seit dem
	# 15.10.2026 (Durchdrehen überträgt den Antrieb, traction) dosiert der Rennfahrer beim Heckantrieb das Gas am Reibkreis der Hinterachse
	# (traction_room): Der Drift King bricht im Rennmodus auf dieser Linie kaum noch aus, also greift der Deckel dort kaum; geprüft wird, dass
	# er im Rennmodus weit seltener quer steht als im Drift-Modus oder der Deckel greift.
	check(int(race.capped) > 0 or int(race.slides) * 4 < int(drift.slides),
		"Rennmodus: dieselbe Linie – %d Takte quer (Drift-Modus %d), gedeckelt %d Takte, Tempo im Mittel %.0f %% gegen %.0f %% im Drift-Modus, Gas %.0f %%" % [race.slides, drift.slides, race.capped, float(race.mean_ratio) * 100.0, float(drift.mean_ratio) * 100.0, float(race.throttle) * 100.0])
	# Der Zeitvergleich (Drift-Modus mindestens 3 s schneller) entfällt ebenfalls: Er beruhte darauf, dass der Rennmodus nach dem Ausbrechen
	# mit 7 m/s zur Linie zurückkroch; mit der stetigen Rückkehr ist er gleich schnell oder schneller. Der Drift-Modus muss ins Ziel kommen
	# und Punkte sammeln. Für den Profi-Drifter ist ×1,85 deutlich zu schnell gezeichnet (Zielwinkel rund 65°): Er driftet mit mehr Winkel,
	# aber langsamer, und bekommt rund die Hälfte der Punkte des Sweetspots (Wertungskurve: tests/test_drift.gd; gemessen 815, Sweetspot-Linien
	# 1400–1700) – daher 600 als Schwelle (vorher 1200, als zu schnell noch zwei Drittel brachte).
	check(drift_car.finish_time > 0.0 and race_car.finish_time > 0.0 and drift_car.drift_score > 600.0,
		"Drift-Modus: Linie mit 85 %% zu schnellen Kurven im Ziel (%.1f s, Rennmodus %.1f s, %d Punkte)" % [drift_car.finish_time, race_car.finish_time, int(drift_car.drift_score)])
	# Woran der Fahrer das Plantempo misst, unterscheidend geprüft (auf der 85-%-Linie ist der Plan unerreichbar, dort gäbe jeder Fahrer
	# Vollgas): Das Auto rutscht 30° quer, genau mit Plantempo. Im Drift-Modus zählt das Fahrtempo, also kein Gas über den Plan hinaus; im
	# Rennmodus das Längstempo u = |v|·cos 30°, das unter dem Plan liegt, also Gas.
	var straight := 0.0
	for k in range(100):
		if absf(arena.curvature(k / 100.0)) < absf(arena.curvature(straight)):
			straight = k / 100.0
	var gas := {}
	for track in [arena, race_arena]:
		var probe := RaceVehicle.new(track, steady_route(track, 15.0), straight, 0.0, 7)
		probe.driver_tc = false     # gemessen wird, woran der Fahrer das Plantempo misst, nicht seine Gasdosierung am Reibkreis
		probe.velocity = Vector2.from_angle(probe.heading - deg_to_rad(30.0)) * 15.0
		probe.step(1.0 / 60.0, false, 1.0 / 60.0)
		gas[track.mode] = [probe.throttle, probe.braking, probe.recovering]
	check(float(gas.drift[0]) < 0.02 and float(gas.drift[1]) == 0.0 and not bool(gas.drift[2]) and float(gas.race[0]) > 0.3 and not bool(gas.race[2]),
		"Plantempo: 30° quer mit Plantempo im Drift-Modus kein Gas (%.0f %%), im Rennmodus Gas nach dem Längstempo (%.0f %%)" % [float(gas.drift[0]) * 100.0, float(gas.race[0]) * 100.0])
	# Wirklich verloren (am Inselrand, Blick nach außen, stehend): Der Profi setzt zurück (free_driver) und dreht dabei die Nase zur Linie,
	# statt mit vollem Einschlag zu kriechen; danach zurück auf die Fahrbahn.
	var lost := RaceVehicle.new(arena, arena.ai_route(1.5), 0.3225, 0.0, 7)
	var s := 0.3225     # zwischen zwei Reifenstapeln (alle 1/24 Runde, abwechselnd links und rechts)
	var t := arena.tangent(s)
	var outward := Vector2(-t.y, t.x)
	lost.pos = arena.at(s) + outward * (arena.hw(s) + 9.5)
	lost.heading = outward.angle()
	lost.previous_phase = s
	var was_recovering := false
	for tick in range(60 * 20):
		lost.step(1.0 / 60.0, false, float(tick + 1) / 60.0)
		was_recovering = was_recovering or lost.recovering
		if lost.crashed or not lost.beyond_edge(0.0):
			break
	check(was_recovering and not lost.crashed and not lost.beyond_edge(0.0),
		"Drift-Modus: verlorenes Auto am Inselrand dreht um und kehrt auf die Fahrbahn zurück (Fortschritt %.3f)" % lost.progress)
	quit(1 if failures else 0)
