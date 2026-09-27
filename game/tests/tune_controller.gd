extends SceneTree

# Messaufbau Fahrregler: Abweichung von der Linie, Überschwinger (Vorzeichenwechsel), Rundenzeit.
# Aufruf: Godot --headless --path game --script res://tests/tune_controller.gd

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

func _initialize() -> void:
	var track := Circuit.new()
	measure(track, track.ai_route(0.0), "glatt (KI)")
	measure(track, track.ai_route(3.0), "glatt schnell")
	measure(track, wobbly_route(track, 0.6, 14.0, 1), "leicht wackelig")
	measure(track, wobbly_route(track, 1.4, 9.0, 2), "stark wackelig")
	quit()
