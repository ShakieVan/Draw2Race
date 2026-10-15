extends SceneTree

# Messaufbau Fahrregler: Abweichung von der Linie, Überschwinger (Vorzeichenwechsel), Rundenzeit; Rückkehr auf die Linie im Prüfoval,
# wellig gezeichnete Linien gegen die glatte und Rückkehr auf echten Strecken (relativ zur ungestörten Fahrt).
# Aufruf: tools/godot_run.ps1 -Script res://tests/tune_controller.gd -Headless -Timeout 900

func wobbly_route(track: Circuit, amplitude: float, waves: float, seed_value: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var route := track.ai_route(0.0)
	var jitter := 0.0
	for point in route:
		jitter = lerpf(jitter, rng.randf_range(-1.0, 1.0), 0.3)
		var o := amplitude * sin(float(point.s) * TAU * waves) + jitter * amplitude * 0.5
		point.p = track.at(float(point.s), clampf(o, -3.0, 3.0))
	return route

func measure(track: Circuit, route: Array[Dictionary], label: String) -> Dictionary:
	var v := RaceVehicle.new(track, route, 0.0, 0.0, 0)
	var t := 0.0
	var errors := PackedFloat32Array()
	var last_sign := 0
	var crossings := 0
	var peak := 0.0
	while v.finish_time < 0.0 and t < 120.0:
		v.step(1.0 / 60.0, false, t)
		t += 1.0 / 60.0
		# Vorzeichenbehaftete Querabweichung zur Route in der Nähe des Fahrzeugs.
		var i := clampi(v.cursor, 0, route.size() - 2)
		var best := INF
		var signed := 0.0
		for j in range(maxi(0, i - 6), mini(route.size() - 1, i + 12)):
			var a: Vector2 = route[j].p
			var b: Vector2 = route[j + 1].p
			var q := Geometry2D.get_closest_point_to_segment(v.pos, a, b)
			var d := v.pos.distance_to(q)
			if d < best:
				best = d
				var dir := (b - a).normalized()
				signed = signf(dir.cross(v.pos - q)) * d
		errors.append(signed)
		peak = maxf(peak, absf(signed))
		if absf(signed) > 0.35:
			var s := int(signf(signed))
			if last_sign != 0 and s != last_sign:
				crossings += 1
			last_sign = s
	var rms := 0.0
	for e in errors:
		rms += e * e
	rms = sqrt(rms / maxf(1, errors.size()))
	print("%-18s Zeit %6.2f s  RMS %.2f m  Spitze %.2f m  Überschwinger %d  max. Schlupf %.2f" % [label, v.finish_time, rms, peak, crossings, v.max_slip])
	return {"time": v.finish_time, "rms": rms, "crossings": crossings}

func meters_after(track: Circuit, route: Array[Dictionary], s0: float, lane: float, psi: float, speed: float, metres: float, trace := false) -> Dictionary:
	# Rückkehrfall: Start bei s0 mit Querversatz lane und Kurs psi; Zeit bis metres Fortschritt, Querfehler zur eigenen Linie im Verlauf.
	var v := RaceVehicle.new(track, route, s0, lane, 0)
	v.heading += psi
	v.velocity = Vector2.from_angle(v.heading) * speed
	var t := 0.0
	var over := 0.0
	var settle := 0.0
	var sign0 := signf(lane)
	while t < 20.0 and (v.progress - s0) * track.length < metres and not v.crashed:
		v.step(1.0 / 60.0, false, t)
		t += 1.0 / 60.0
		if not trace:
			continue
		var i := clampi(v.cursor, 0, route.size() - 2)
		var best := INF
		var e := 0.0
		for j in range(maxi(0, i - 6), mini(route.size() - 1, i + 16)):
			var q := Geometry2D.get_closest_point_to_segment(v.pos, route[j].p, route[j + 1].p)
			if v.pos.distance_to(q) < best:
				best = v.pos.distance_to(q)
				e = signf((Vector2(route[j + 1].p) - Vector2(route[j].p)).cross(v.pos - q)) * best
		if e * sign0 < 0.0:
			over = maxf(over, absf(e))
		if absf(e) >= 0.25:
			settle = t
	return {"time": t if not v.crashed else -1.0, "over": over, "settle": settle}

func recovery(grip: float) -> void:
	# Rückkehr auf die Linie (Rückkehr-Episoden, 15.10.2026): Prüfoval Stadion (tests/tracks/stadion.json), Gerade, Plan 18 m/s. Querfehler
	# relativ zur Linie, Überschwinger (über die Linie hinaus), Einschwingzeit (|e| < 0,25 m), Verlust bis +100 m gegenüber einem Auto, das
	# auf der Linie startet.
	RaceVehicle.weather_grip = grip
	var track := Circuit.new("res://tests/tracks/stadion.json")
	var route := track.ai_route(2.3)
	var s0 := 30.0 / track.length
	for standing in [false, true]:
		var speed := 0.0 if standing else 18.0
		var reference := float(meters_after(track, route, s0, 0.0, 0.0, speed, 100.0).time)
		for lane in [2.5, 4.0, 6.0, 9.0]:
			for psi in [0.0, -0.35, 0.35]:
				var r := meters_after(track, route, s0, lane, psi, speed, 100.0, true)
				print("Rückkehr Haftung %.2f %-7s %3.1f m %+5.2f rad: Überschwinger %.2f m  eingeschwungen %.2f s  Verlust %+.2f s" % [grip, "stehend" if standing else "Plan", lane, psi, r.over, r.settle, float(r.time) - reference])
	RaceVehicle.weather_grip = 1.0

func solo(track: Circuit, route: Array[Dictionary], s0 := 0.0, d := 0.0, psi := 0.0) -> Dictionary:
	# Fahrt mit Plantempo ab s0, d m neben der Linie (links positiv) und um psi gedreht; Querfehler je halben Meter Fortschritt (bis +100 m).
	var v := RaceVehicle.new(track, route, s0)
	var idx := 0
	while idx < route.size() - 1 and float(route[idx + 1].s) <= s0:
		idx += 1
	var dir := (Vector2(route[mini(idx + 2, route.size() - 1)].p) - Vector2(route[idx].p)).normalized()
	v.pos = Vector2(route[idx].p) + Vector2(-dir.y, dir.x) * d
	v.heading = dir.angle() + psi
	v.velocity = Vector2.from_angle(v.heading) * float(route[idx].speed)
	var probe := RaceVehicle.new(track, route, s0)
	probe.pos = v.pos
	probe.heading = v.heading
	probe.collide_obstacles(1.0 / 60.0)
	if probe.obstacle_hit > 0.0:
		return {"skip": true}
	var prof := {}
	var t100 := -1.0
	var t := 0.0
	while t < 14.0 and not v.crashed and v.finish_time < 0.0:
		v.step(1.0 / 60.0, false, t)
		t += 1.0 / 60.0
		var m := (v.progress - s0) * track.length
		if t100 < 0.0 and m >= 100.0:
			t100 = t
		if m > 100.0 or v.in_loop or v.airborne:
			continue
		var i := clampi(v.cursor, 0, route.size() - 2)
		var best := INF
		var e := 0.0
		for j in range(maxi(0, i - 6), mini(route.size() - 1, i + 16)):
			var q := Geometry2D.get_closest_point_to_segment(v.pos, route[j].p, route[j + 1].p)
			if v.pos.distance_to(q) < best:
				best = v.pos.distance_to(q)
				e = signf((Vector2(route[j + 1].p) - Vector2(route[j].p)).cross(v.pos - q)) * best
		prof[int(m * 2.0)] = [e, t]
	return {"prof": prof, "t100": t100, "crashed": v.crashed, "skip": false}

func real_returns() -> void:
	# Rückkehr auf echten Strecken (Gegenprüfung 15.10.2026): 8 Strecken × 4 Stellen × ±3/±5 m × Kurs 0/±0,3 rad, mit Plantempo; Starts in
	# einem Hindernis zählen nicht. Querfehler relativ zu einem ungestörten Auto auf derselben Linie (dessen Kurvenschneiden zählt nicht):
	# Überschwinger über diese Bahn hinaus, Einschwingen (bis |Δe| zuletzt über 0,5 m), Verlust bis +100 m, Ausfälle (Absturz, Wrack oder
	# in 14 s keine 100 m).
	RaceVehicle.weather_grip = 1.0
	var n := 0
	var fails := 0
	var over := 0.0
	var settle := 0.0
	var loss := 0.0
	for id in ["azure", "city", "forest", "harbor", "serra", "fair", "quarry", "kids"]:
		var track := Circuit.load_track(id)
		var route := track.ai_route(2.3)
		for s0 in [0.19, 0.44, 0.69, 0.94 if not track.open else 0.81]:
			var ref := solo(track, route, s0)
			for d in [3.0, -3.0, 5.0, -5.0]:
				for psi in [0.0, 0.3, -0.3]:
					var r := solo(track, route, s0, d, psi)
					if bool(r.skip):
						continue
					n += 1
					if bool(r.crashed) or float(r.t100) < 0.0 or float(ref.t100) < 0.0:
						fails += 1
						continue
					var worst := 0.0
					var last := 0.0
					var sign0 := 0.0
					var rp: Dictionary = r.prof
					var fp: Dictionary = ref.prof
					for key in rp:
						if not fp.has(key):
							continue
						var de: float = float(rp[key][0]) - float(fp[key][0])
						if sign0 == 0.0:
							sign0 = signf(de)
						if de * sign0 < 0.0:
							worst = maxf(worst, absf(de))
						if absf(de) > 0.5:
							last = maxf(last, float(rp[key][1]))
					over += worst
					settle += last
					loss += minf(float(r.t100) - float(ref.t100), 5.0)
	var ok := maxi(1, n - fails)
	print("Rückkehr echte Strecken: %d Fälle, %d Ausfälle, Überschwinger im Mittel %.2f m, Einschwingen %.2f s, Verlust bis +100 m %.2f s" % [n, fails, over / ok, settle / ok, loss / ok])

func wavy_real() -> void:
	# Wellig gezeichnete Spielerlinien auf echten Strecken (ai_route 2.0 mit Wellen und Zittern, Abkürzungen glatt): Zeit gegen die glatte Linie.
	RaceVehicle.weather_grip = 1.0
	for id in ["azure", "city", "kids", "fair"]:
		var track := Circuit.load_track(id)
		var smooth := solo_time(track, track.ai_route(2.0))
		var text := ""
		for amp in [1.1, 1.6]:
			for waves in [6.0, 11.0, 20.0]:
				var route := track.ai_route(2.0)
				var rng := RandomNumberGenerator.new()
				rng.seed = 1
				var jitter := 0.0
				for point in route:
					if int(point.get("sc", -1)) >= 0:
						continue
					jitter = lerpf(jitter, rng.randf_range(-1.0, 1.0), 0.3)
					var o: float = amp * sin(float(point.s) * TAU * waves) + jitter * 0.8
					point.o = clampf(o, -track.hw(float(point.s)) + 0.5, track.hw(float(point.s)) - 0.5)
					point.p = track.at(float(point.s), float(point.o))
				var time := solo_time(track, route)
				text += "  %.1f/%2.0f %s" % [amp, waves, ("%+.1f %%" % ((time / smooth - 1.0) * 100.0)) if time > 0.0 else "Ausfall"]
		print("Wellig %-6s glatt %.2f s:%s" % [id, smooth, text])

func solo_time(track: Circuit, route: Array[Dictionary]) -> float:
	var v := RaceVehicle.new(track, route)
	var t := 0.0
	while v.finish_time < 0.0 and not v.crashed and t < 200.0:
		v.step(1.0 / 60.0, false, t)
		t += 1.0 / 60.0
	return v.finish_time

func _initialize() -> void:
	var track := Circuit.new()
	measure(track, track.ai_route(0.0), "glatt (KI)")
	measure(track, track.ai_route(3.0), "glatt schnell")
	measure(track, wobbly_route(track, 0.6, 14.0, 1), "leicht wackelig")
	measure(track, wobbly_route(track, 1.4, 9.0, 2), "stark wackelig")
	recovery(1.0)
	recovery(0.7)
	wavy_real()
	real_returns()
	quit()
