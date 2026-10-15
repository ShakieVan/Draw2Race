extends SceneTree

# Fahrer-Regler (15.10.2026): Rückkehr auf die Linie nach einem Ausflug (Rückkehr-Episoden statt des 7-m/s-Schalters), Tempo stetig nach
# Abstand und Ausrichtung, Einfahrt in Schwungzonen und aufs Lineal, Freifahren nach Festhängen und die Wrack-Regel. Prüfstrecke Stadion
# (tests/tracks/stadion.json, aus make_test_tracks.py): zwei Geraden à 220 m, Kurven R 22 m, ohne Bausteine; Plan auf der Geraden 18 m/s.
# Vergleichswerte des alten Reglers (gleiche Physik bicycle-7) stehen in den Meldungen ("bisher"). Nachbesserung nach der Gegenprüfung:
# Schwungzonen 15–30 m vor der Einfahrt, wellig gezeichnete Linien (Zeit gegen die glatte Linie), Nase zur Leitplanke, Seitenaufprall am
# Lineal, Freifahren mit erzwungenem Zurücksetzen, Goldläufe aller Autos bei jedem Wetter, Startaufstellung.
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

func line_error(v: RaceVehicle, route: Array) -> float:
	# Querabstand zur eigenen Linie (links positiv), unabhängig von der Messung im Regler; Linienstücke über eine Looping-Einfahrt zählen nicht.
	var i := clampi(v.cursor, 0, route.size() - 2)
	var best := INF
	var signed := 0.0
	for j in range(maxi(0, i - 6), mini(route.size() - 1, i + 16)):
		if not v.track.loops.is_empty() and not v.track.loop_between(float(route[j].s), float(route[j + 1].s)).is_empty():
			continue
		var a: Vector2 = route[j].p
		var b: Vector2 = route[j + 1].p
		var q := Geometry2D.get_closest_point_to_segment(v.pos, a, b)
		var d := v.pos.distance_to(q)
		if d < best:
			best = d
			signed = signf((b - a).cross(v.pos - q)) * d
	return signed

func stadion() -> Circuit:
	return Circuit.new("res://tests/tracks/stadion.json")

func return_case(t: Circuit, route: Array[Dictionary], m0: float, d: float, psi: float, standing: bool, seconds := 9.0, bins := {}) -> Dictionary:
	# Start m0 Meter nach dem Start (Gerade), d Meter neben der Linie, Kurs um psi gedreht, mit Plantempo oder stehend.
	var s0 := m0 / t.length
	var v := RaceVehicle.new(t, route, s0, d)
	v.heading += psi
	v.velocity = Vector2.from_angle(v.heading) * (0.0 if standing else 18.0)
	var sign0 := signf(d)
	var t_line := -1.0
	var over := 0.0
	var crossed := false
	var crossings := 0
	var last_sign := int(sign0)
	var vmin := 99.0
	var ep_start := -1.0
	var ep_end := -1.0
	var near_at := -1.0
	var road_at := -1.0
	var approach := 0.0
	for tick in range(int(seconds * 60.0)):
		v.step(DT, false, float(tick + 1) * DT)
		var time := float(tick + 1) * DT
		if v.crashed or v.progress * t.length > 212.0:
			break
		var e := line_error(v, route)
		var sp := v.velocity.length()
		if t_line < 0.0 and absf(e) < 0.25:
			t_line = time
		if near_at < 0.0 and absf(e) < 0.5:
			near_at = time
		if road_at < 0.0 and absf(e) < t.hw(v.progress) - 0.5:
			road_at = time
		if absf(e) > 0.5:
			# Annäherungswinkel an die Linie (Kurs gegen die Linienrichtung, nur auf sie zu)
			approach = maxf(approach, -signf(e) * v.line_course) if absf(e) < t.hw(v.progress) - 0.5 else approach
		if e * sign0 < 0.0:
			crossed = true
			over = maxf(over, absf(e))
		if absf(e) > 0.35:
			var sg := int(signf(e))
			if last_sign != 0 and sg != last_sign:
				crossings += 1
			last_sign = sg
		if not standing and time > 0.2 and (t_line < 0.0 or time < t_line + 0.5):
			vmin = minf(vmin, sp)
		if v.rec_episode and ep_start < 0.0:
			ep_start = time
		if ep_start >= 0.0 and ep_end < 0.0 and not v.rec_episode:
			ep_end = time
		if not bins.is_empty() and not standing and time > 0.3:
			var k := mini(int(absf(e)), 6)
			bins[k][0] += sp / maxf(float(route[v.cursor].speed), 1.0)
			bins[k][1] += v.throttle
			bins[k][2] += 1.0
	return {"t_line": t_line, "over": over, "cross": crossings, "vmin": vmin, "crashed": v.crashed, "ep_start": ep_start, "road_at": road_at, "approach": approach,
		"ep_end": ep_end, "near_at": near_at, "fade": v.rec_fade, "still": v.rec_episode, "pos": v.pos, "heading": v.heading}

func feasible(d: float, psi: float, speed: float) -> bool:
	# Physikalisch ohne Überschwingen machbar? Schräg auf die Linie zu muss der Kurs auf dem verbleibenden Querweg (abzüglich des Wegs, bis
	# Lenkung und Gierrate stehen) parallel werden: v²·(1 − cos ψ)/Querweg ≤ Querhaftung. 2,5 m daneben mit 20° bei 18 m/s verlangt 20 m/s².
	var toward := -signf(d) * psi
	if toward <= 0.0 or speed <= 0.0:
		return true
	var room := absf(d) - speed * sin(toward) * RaceVehicle.REC_LAG
	return room > 0.1 and speed * speed * (1.0 - cos(toward)) / room <= RaceVehicle.REC_ARC_GRIP * 12.0

func test_straight() -> void:
	# Gerade, 4 m neben der Linie, parallel, Plantempo: asymptotisch zurück, mit Gas statt Vollbremsung (bisher: 0,62 m darüber hinaus,
	# Tempo bis 8,0 m/s, erst auf der Linie wieder Gas).
	for grip in [1.0, 0.85, 0.7]:
		RaceVehicle.weather_grip = grip
		var t := stadion()
		var r := return_case(t, t.ai_route(2.3), 30.0, 4.0, 0.0, false)
		var tag := "Gerade 4 m daneben (Haftung %.2f)" % grip
		check(float(r.over) <= 0.3 and int(r.cross) == 0, "%s: Überschwinger %.2f m ≤ 0,3, kein Pendeln (bisher 0,62 m)" % [tag, r.over])
		check(float(r.vmin) >= 14.0, "%s: Mindesttempo %.1f m/s ≥ 14 (bisher 8,0)" % [tag, r.vmin])
		check(float(r.t_line) > 0.0 and float(r.t_line) <= 3.0, "%s: auf der Linie nach %.2f s ≤ 3,0" % [tag, r.t_line])
		check(float(r.ep_start) >= 0.0 and float(r.ep_end) > 0.0 and not bool(r.still) and float(r.fade) == 0.0,
			"%s: Episode %.2f–%.2f s, danach wieder normale Linienfolge" % [tag, r.ep_start, r.ep_end])
	# Weit draußen (9 m neben der Linie, 5,5 m neben der Fahrbahn auf Erde): erst steil zurück auf die Fahrbahn, dann flach zur Linie.
	var t9 := stadion()
	var far9 := return_case(t9, t9.ai_route(2.3), 30.0, 9.0, 0.0, false)
	print("  9 m daneben: auf der Fahrbahn nach %.2f s, auf der Linie nach %.2f s, Annäherung auf dem Belag höchstens %.2f rad" % [far9.road_at, far9.t_line, far9.approach])
	check(float(far9.over) <= 0.3 and float(far9.road_at) > 0.0 and float(far9.t_line) - float(far9.road_at) >= 1.0,
		"9 m daneben: Überschwinger %.2f m, Fahrbahn nach %.2f s, dann flach bis zur Linie (%.2f s)" % [far9.over, far9.road_at, far9.t_line])
	RaceVehicle.weather_grip = 1.0

func test_grid() -> void:
	# Raster: zwei Startpunkte × ±2,5/4/6 m × Kurs 0/±20° × Plantempo/stehend (72 Fälle; bisher: alle über 0,3 m, im Mittel 0,64 m).
	RaceVehicle.weather_grip = 1.0
	var t := stadion()
	var route := t.ai_route(2.3)
	var bins := {}
	for k in range(7):
		bins[k] = [0.0, 0.0, 0.0]
	var n := 0
	var sum := 0.0
	var bad := []
	var late_max := 0.0
	var crashed := 0
	var hanging := 0
	var slow_end := 0
	for m0 in [20.0, 90.0]:
		for d in [4.0, -4.0, 6.0, -6.0, 2.5, -2.5]:
			for psi in [0.0, 0.35, -0.35]:
				for standing in [false, true]:
					var r := return_case(t, route, m0, d, psi, standing, 9.0, bins)
					n += 1
					sum += float(r.over)
					crashed += 1 if bool(r.crashed) else 0
					hanging += 1 if bool(r.still) or float(r.fade) > 0.0 else 0
					if float(r.near_at) > 0.0 and float(r.ep_end) > float(r.near_at) + 4.0:
						slow_end += 1
					if feasible(d, psi, 0.0 if standing else 18.0):
						if float(r.over) > 0.3:
							bad.append("m%.0f d%+.1f psi%+.2f %s: %.2f" % [m0, d, psi, "steh" if standing else "plan", r.over])
					else:
						late_max = maxf(late_max, float(r.over))
	check(crashed == 0 and hanging == 0, "Raster: kein Abflug (%d), alle Episoden zu Ende (%d hängen)" % [crashed, hanging])
	check(bad.is_empty(), "Raster: Überschwinger ≤ 0,3 m in allen machbaren Fällen %s" % str(bad))
	check(late_max <= 0.8, "Raster: zu spät schräg auf die Linie (2,5 m, 20°, 18 m/s; Physikgrenze) höchstens %.2f m ≤ 0,8" % late_max)
	check(sum / n <= 0.2, "Raster: Überschwinger im Mittel %.2f m ≤ 0,2 (bisher 0,64)" % (sum / n))
	check(slow_end == 0, "Raster: Episoden enden spätestens 4 s, nachdem das Auto 0,5 m an der Linie ist (%d zu spät)" % slow_end)
	# Tempo stetig nach Abstand (nur Starts mit Plantempo): Tempo/Plan fällt mit |e| ohne Sprung (bisher am Schalter 0,61 → 0,41), und auch
	# weit neben der Linie gibt der Fahrer Gas (bisher 0,18–0,29 bei 3–6 m).
	var ratio := []
	var gas := 0.0
	var gas_n := 0.0
	for k in range(7):
		ratio.append(bins[k][0] / maxf(bins[k][2], 1.0))
		if k >= 3 and k <= 5:
			gas += bins[k][1]
			gas_n += bins[k][2]
	var steady := true
	for k in range(1, 7):
		if float(ratio[k]) > float(ratio[k - 1]) + 0.03 or float(ratio[k - 1]) - float(ratio[k]) > 0.15:
			steady = false
	var text := ""
	for x in ratio:
		text += " %.2f" % float(x)
	check(steady, "Tempo/Plan nach Abstand 0–1 … ≥ 6 m stetig fallend:%s" % text)
	check(gas / maxf(gas_n, 1.0) >= 0.5, "Gas bei 3–6 m neben der Linie %.2f ≥ 0,5 (bisher 0,18–0,29)" % (gas / maxf(gas_n, 1.0)))
	# Nässe und Schnee: kleineres Raster.
	for grip in [0.85, 0.7]:
		RaceVehicle.weather_grip = grip
		var tw := stadion()
		var rw := tw.ai_route(2.3)
		var worst := 0.0
		for d in [4.0, -4.0, 6.0, -6.0]:
			for psi in [0.0, 0.35]:
				worst = maxf(worst, float(return_case(tw, rw, 30.0, d, psi, false).over))
		check(worst <= 0.3, "Raster Haftung %.2f: Überschwinger höchstens %.2f m ≤ 0,3" % [grip, worst])
	RaceVehicle.weather_grip = 1.0

func gold_run(id: String, car: int, grip: float) -> Dictionary:
	RaceVehicle.weather_grip = grip
	var t := Circuit.load_track(id)
	var v := RaceVehicle.new(t, t.ai_route(2.3), 0.0, 0.0, car)
	var starts := 0
	var ep := 0.0
	var was := false
	for tick in range(60 * 300):
		v.step(DT, false, float(tick + 1) * DT)
		if v.rec_episode and not was:
			starts += 1
		if v.rec_episode:
			ep += DT
		was = v.rec_episode
		if v.finish_time >= 0.0 or v.crashed:
			break
	RaceVehicle.weather_grip = 1.0
	return {"time": v.finish_time, "starts": starts, "ep": ep, "ep_end": not v.rec_episode}

func test_gold() -> void:
	# Goldläufe (ai_route 2.3) aller Autos auf allen Strecken, trocken, nass und Schnee. Episodenfrei, solange das Auto der Linie normal folgt
	# (Kurvenschneiden bis 1,9 m; bei Nässe und Schnee und nach einer Landung liegt die Schwelle weiter draußen). Echte Ausflüge der Goldläufe
	# selbst: trocken nur Thunder V8 (weniger Haftung, mehr Kraft) auf Serra, Jahrmarkt und Kinderzimmer; nass und im Schnee rutschen mehr Autos
	# über die Schwelle, höchstens so viele Läufe wie mit dem alten 7-m/s-Schalter (Gegenprüfung: trocken 2, nass 7, Schnee 13 Läufe mit
	# Deckel; vor der Nachbesserung mit Episode 10/11/14, der Jahrmarkt kostete trocken jeden Goldlauf 0,06–0,39 s). Alle kommen ins Ziel, jede
	# Episode endet.
	var bad := []
	var excursions := {1.0: [], 0.85: [], 0.7: []}
	for grip in [1.0, 0.85, 0.7]:
		for id in ["azure", "city", "forest", "harbor", "quarry", "arena", "kids", "serra", "fair"]:
			for car in range(RaceVehicle.CARS.size()):
				var r := gold_run(id, car, grip)
				if float(r.time) < 0.0:
					bad.append("%s c%d Haftung %.2f nicht im Ziel" % [id, car, grip])
				elif int(r.starts) > 0:
					excursions[grip].append("%s c%d" % [id, car])
					if not bool(r.ep_end) or float(r.ep) > 12.0:
						bad.append("%s c%d Haftung %.2f: Episode %.1f s offen %s" % [id, car, grip, r.ep, not bool(r.ep_end)])
	var dry: Array = excursions[1.0]
	var dry_ok := true
	for e in dry:
		dry_ok = dry_ok and str(e) in ["serra c3", "fair c3", "kids c3"]
	check(bad.is_empty() and dry_ok, "Goldläufe ohne Ausflug episodenfrei (trocken nur Thunder V8 auf Serra/Jahrmarkt/Kinderzimmer: %s) %s" % [str(dry), str(bad)])
	check((excursions[0.85] as Array).size() <= 7 and (excursions[0.7] as Array).size() <= 13,
		"Goldläufe nass %d, Schnee %d mit Episode ≤ 7 bzw. 13 (alter Schalter 7/13): %s | %s" % [(excursions[0.85] as Array).size(), (excursions[0.7] as Array).size(), str(excursions[0.85]), str(excursions[0.7])])

func test_zones() -> void:
	# Schwungzonen: 15–70 m vor Looping, Schanze bzw. Absprungkante, 2,5–4 m neben der Linie mit Plantempo gestartet. Weit vorher liegt der
	# Zielpunkt der Episode höchstens auf halber Strecke vor der Einfahrt, das Auto kommt ausgerichtet an (Looping quer ≤ 0,5 m); im Anlauf
	# (unter 30–50 m) geht Tempo vor Querlage: kein Rückkehrdeckel unter den Plan (Gegenprüfung: 15–30 m vorher bremste die Episode auf 12–15
	# statt 15–16 m/s, das Auto stürzte im Looping ab, wo der alte Regler durchkam). Starts in einem Hindernis zählen nicht.
	RaceVehicle.weather_grip = 1.0
	var total := 0
	var ok := 0
	var lat := 0.0
	var fails := []
	for id in ["quarry", "kids", "harbor", "fair"]:
		var t := Circuit.load_track(id)
		var route := t.ai_route(2.3)
		var zones := []
		for l in t.loops:
			zones.append(float(l.s))
		for r in t.ramps:
			zones.append(float(r.s))
		for g in t.gaps:
			if t.gap_kicker(g).is_empty():
				zones.append(float(g.from))
		for z in zones:
			for before in [15.0, 20.0, 25.0, 30.0, 45.0, 70.0]:
				for d in ([2.5, -2.5, 3.0, -3.0] if before < 40.0 else [2.5, -2.5, 4.0, -4.0]):
					var s0: float = float(z) - before / t.length
					var probe := RaceVehicle.new(t, route, s0, d)
					probe.collide_obstacles(DT)
					if probe.obstacle_hit > 0.0:
						continue
					var v := RaceVehicle.new(t, route, s0, d)
					var idx := 0
					while idx < route.size() - 1 and float(route[idx + 1].s) <= s0:
						idx += 1
					v.velocity = Vector2.from_angle(v.heading) * float(route[idx].speed)
					var good := false
					for tick in range(60 * 12):
						var pre := v.in_loop
						var e := line_error(v, route)
						v.step(DT, false, float(tick + 1) * DT)
						if v.in_loop and not pre and before > 40.0:
							lat = maxf(lat, absf(e))
						if v.crashed:
							break
						if v.progress > float(z) + 40.0 / t.length and not v.in_loop and not v.airborne:
							good = true
							break
					total += 1
					ok += 1 if good else 0
					if not good:
						fails.append("%s %.4f %.0f m %+.1f" % [id, z, before, d])
	check(total >= 120 and ok == total, "Schwungzonen: %d/%d Starts neben der Linie kommen durch (vor der Nachbesserung 15–30 m vorher 17 Abstürze) %s" % [ok, total, str(fails)])
	check(lat <= 0.5, "Schwungzonen: Looping-Einfahrt (45/70 m vorher gestartet) höchstens %.2f m quer ≤ 0,5" % lat)

func finger_path(t: Circuit, lane_main: float, lane_path: float) -> PackedVector2Array:
	# Fingerweg über die Abkürzung 0 (Lineal): Hauptstrecke, dann der Pfad mit Spur lane_path (weich übergeblendet), wieder Hauptstrecke.
	var out := PackedVector2Array()
	var step := 0.1 / t.length
	var s := 0.0
	var from := float(t.shortcuts[0].from)
	var total := t.shortcut_length(0)
	for lap in range(t.laps):
		while s < lap + from:
			out.append(t.at(s, lane_main))
			s += step
		var m := 0.0
		while m <= total:
			var pose := t.path_pose(0, m)
			var dir: Vector2 = pose[1]
			var lane := lerpf(lane_main, lane_path, smoothstep(0.0, 8.0, m) * smoothstep(total, total - 8.0, m))
			out.append(Vector2(pose[0]) + Vector2(-dir.y, dir.x) * lane)
			m += 0.1
		s = lap + float(t.shortcuts[0].to)
	while s <= t.laps + 0.03:
		out.append(t.at(s, lane_main))
		s += step
	return out

func draw_line(t: Circuit, path: PackedVector2Array, factor: float, plan: Array, wobble: float, seed_value: int) -> LineRecorder:
	# Zeichnung mit 60 Hz: Fingertempo nach dem Plantempo der KI × factor, etwas Wackeln (feste Saat).
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var phases := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	var cum := PackedFloat32Array([0.0])
	for i in range(1, path.size()):
		cum.append(cum[-1] + path[i - 1].distance_to(path[i]))
	var pen := LineRecorder.new(t)
	pen.begin(t.at(0.0), 0.0)
	var walked := 0.0
	var j := 0
	var near := 0
	var tick := 0
	while not pen.complete and pen.active and walked < cum[-1] and tick < 60000:
		tick += 1
		var best := INF
		for k in range(near, mini(near + 40, plan.size())):
			var d := Vector2(plan[k].p).distance_to(path[j])
			if d < best:
				best = d
				near = k
		var v := clampf((float(plan[near].speed) * factor - 5.0) / pen.tempo_factor, 4.0, 60.0)
		walked += v / 60.0
		while j < cum.size() - 2 and cum[j + 1] < walked:
			j += 1
		var f := clampf((walked - cum[j]) / maxf(1e-6, cum[j + 1] - cum[j]), 0.0, 1.0)
		var dir := (path[j + 1] - path[j]).normalized()
		var time := tick / 60.0
		var shake: float = wobble * (0.6 * sin(1.3 * time + phases[0]) + 0.3 * sin(3.1 * time + phases[1]) + 0.1 * sin(7.9 * time + phases[2]))
		pen.sample(path[j].lerp(path[j + 1], f) + Vector2(-dir.y, dir.x) * shake, time)
	return pen

func deck_run(t: Circuit, route: Array[Dictionary]) -> Dictionary:
	# Allein mit Wippe: Querlage beim Auffahren aufs Deck (|b| und Abstand zur eigenen Linie dort), Ergebnis.
	var f := RaceField.new(t)
	f.setup_entries([RaceField.human_entry(route)])
	var v := f.cars[0]
	var bs := []
	var off := 0.0
	var was_deck := false
	var jumps := 0
	var sc: Dictionary = t.shortcuts[0]
	for tick in range(60 * 200):
		var p0 := v.progress
		f.step(DT, float(tick + 1) * DT)
		# Fortschritt im Bezug der eigenen Linie: kein Sprung zwischen Pfad- und Hauptstreckenanteil (bisher bis 16,7 m in einem Takt).
		var x := t.unit(v.progress)
		if x > float(sc.from) - 0.03 and x < float(sc.to) + 0.03 and absf(v.progress - p0) * t.length > 1.5:
			jumps += 1
		if v.deck != null and not was_deck:
			var b := v.deck.local(v.pos).y
			bs.append(absf(b))
			var best := INF
			var lb := 0.0
			for k in range(maxi(0, v.cursor - 30), mini(route.size(), v.cursor + 30)):
				var dq := v.pos.distance_squared_to(route[k].p)
				if dq < best:
					best = dq
					lb = v.deck.local(route[k].p).y
			off = maxf(off, absf(b - lb))
		was_deck = v.deck != null
		if v.finish_time >= 0.0 or v.crashed:
			break
	return {"bs": bs, "off": off, "time": v.finish_time, "cause": v.wreck_cause if v.wrecked else ("Absturz" if v.crashed else ""), "jumps": jumps}

func test_lineal() -> void:
	# Kinderzimmer-Lineal: Der Stift unter dem Lineal bleibt (Nutzerentscheidung), der Fahrer trifft die Deck-Einfahrt sauber. Gezeichnete
	# Linien über das Lineal (Fingertempo ×0,95–1,15 der KI, Spur −1 … +1 m, Wackeln 0,3 m) ohne Unfall am Lineal (vor dem Strang 10/35).
	RaceVehicle.weather_grip = 1.0
	var kids := Circuit.load_track("kids")
	var plan := kids.ai_route(2.0, 0.0, 0)
	var n := 0
	var fin := 0
	var fails := []
	var off := 0.0
	var jumps := 0
	for factor in [0.95, 1.05, 1.15]:
		for lane in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			for sd in [1, 2]:
				var pen := draw_line(kids, finger_path(kids, 0.0, lane), factor, plan, 0.3, sd * 31 + int(lane * 10.0) + int(factor * 100.0))
				if not pen.complete:
					continue
				n += 1
				var r := deck_run(Circuit.load_track("kids"), pen.route)
				off = maxf(off, float(r.off))
				jumps += int(r.jumps)
				if float(r.time) >= 0.0:
					fin += 1
				else:
					fails.append("×%.2f Spur %+.1f: %s" % [factor, lane, r.cause])
	check(n >= 28 and fin == n, "Lineal: %d/%d gezeichnete Linien im Ziel, kein Unfall am Lineal %s" % [fin, n, str(fails)])
	check(off <= 0.5, "Lineal: Auto fährt höchstens %.2f m neben der eigenen Linie aufs Deck ≤ 0,5" % off)
	check(jumps == 0, "Abkürzung: Fortschritt springt nicht zwischen Pfad und Hauptstrecke (%d Sprünge > 1,5 m; bisher 52 in 30 Rennen)" % jumps)
	var bmax := 0.0
	var ai_fail := []
	for skill in [2.0, 2.3, 2.7, 3.0]:
		for lane in [0.0, 1.0, -1.0]:
			var tk := Circuit.load_track("kids")
			var r := deck_run(tk, tk.ai_route(skill, lane, 0))
			for b in r.bs:
				bmax = maxf(bmax, float(b))
			if float(r.time) < 0.0 or (r.bs as Array).size() < 2:
				ai_fail.append("%.1f/%+.0f" % [skill, lane])
	check(ai_fail.is_empty() and bmax <= 1.2, "Lineal: KI Stufe 2,0–3,0 fährt mit |b| ≤ %.2f m aufs Deck (≤ 1,2; vorher bis 2,0) %s" % [bmax, str(ai_fail)])
	# Deck verfehlt (Start 0–6 m vor der Einfahrt, 2,7–4 m neben dem Deck, 4–12 m/s): seitlich kommt das Auto nicht hinauf (Seitenwand,
	# Stiftenden). Es setzt bis vor die Einfahrt zurück und nimmt neuen Anlauf, statt sich am Stift festzufahren (vorher Wrack „fest mauer“;
	# Gegenprüfung: 10 von 72 noch Wrack „fest lineal“). Die Uhr der Hängeserie beginnt mit dem neuen Anlauf neu.
	var miss := []
	var retried := 0
	var clock := 0.0
	for m in [10.0, 12.0, 14.0, 16.0]:
		for lat in [2.7, -2.7, 3.3, -3.3, 4.0, -4.0]:
			for sp in [4.0, 8.0, 12.0]:
				var r := deck_miss(m, lat, sp)
				retried += int(r.reverse)
				clock = maxf(clock, float(r.clock))
				if not bool(r.ok):
					miss.append("m%.0f %+.1f v%.0f: %s" % [m, lat, sp, r.cause])
	check(miss.is_empty() and retried > 0, "Lineal verfehlt: zurück vor die Einfahrt und neuer Anlauf (%d× zurückgesetzt), alle 72 aufs Deck und weiter %s" % [retried, str(miss)])
	check(clock < RaceVehicle.STUCK_TIME, "Lineal verfehlt: Hängeserie beim Auffahren nach dem neuen Anlauf höchstens %.1f s alt < STUCK_TIME (vorher 9–11 s)" % clock)
	# Seitenaufprall am Lineal (2,6 m neben der Seitenwand, quer darauf zu): wie an einer Mauer – Stoß mit Funken und Ton, über WRECK_SPEED
	# ein Wrack; der Bug bleibt außerhalb der Seitenwand (Gegenprüfung: die Bug/Heck-Regel schluckte jeden Stoß lautlos, auch mit 24 m/s).
	var side_bad := []
	for a in [-6.0, 6.0]:
		for sd in [1.0, -1.0]:
			var soft := side_hit(a, sd, 10.0)
			var hard := side_hit(a, sd, 24.0)
			if bool(soft.wrecked) or float(soft.hit) < 5.0 or float(soft.lat) < float(soft.half_w):
				side_bad.append("a %+.0f Seite %+.0f 10 m/s: %s" % [a, sd, str(soft)])
			if not bool(hard.wrecked):
				side_bad.append("a %+.0f Seite %+.0f 24 m/s: kein Wrack, Stoß %.1f" % [a, sd, hard.hit])
	check(side_bad.is_empty(), "Seitenaufprall am Lineal: 10 m/s Stoß ohne Wrack, Bug außerhalb; 24 m/s Wrack %s" % str(side_bad))

func side_hit(a: float, sd: float, sp: float) -> Dictionary:
	var t := Circuit.load_track("kids")
	var route := t.ai_route(2.3, 0.0, 0)
	var f := RaceField.new(t)
	f.setup_entries([RaceField.human_entry(route)])
	var w: Seesaw = f.seesaws[0]
	var v := f.cars[0]
	v.pos = w.world(a, sd * (w.half_w + 2.6))
	var inward: Vector2 = -Vector2(-w.u.y, w.u.x) * sd
	v.heading = inward.angle()
	v.velocity = inward * sp
	v.z = t.terrain_height(v.pos)
	var sc: Dictionary = t.shortcuts[0]
	var s0: float = lerpf(float(sc.from), float(sc.to), (a + float(w.spec.get("at", 0.0))) / t.shortcut_length(0))
	v.progress = s0
	v.previous_phase = s0
	var hit := 0.0
	var lat := 99.0
	for tick in range(60 * 2):
		f.step(DT, float(tick + 1) * DT)
		hit = maxf(hit, v.obstacle_hit)
		lat = minf(lat, absf(w.local(v.pos + Vector2.from_angle(v.heading) * RaceVehicle.CAR_REACH).y))
		if v.crashed:
			break
	return {"hit": hit, "wrecked": v.wrecked, "lat": lat, "half_w": w.half_w}

func deck_miss(m: float, lat: float, sp: float) -> Dictionary:
	var t := Circuit.load_track("kids")
	var route := t.ai_route(2.3, 0.0, 0)
	var f := RaceField.new(t)
	f.setup_entries([RaceField.human_entry(route)])
	var v := f.cars[0]
	var pose := t.path_pose(0, m)
	var dir: Vector2 = pose[1]
	v.pos = Vector2(pose[0]) + Vector2(-dir.y, dir.x) * lat
	v.heading = dir.angle()
	v.velocity = dir * sp
	var sc: Dictionary = t.shortcuts[0]
	var s0: float = lerpf(float(sc.from), float(sc.to), m / t.shortcut_length(0))
	v.progress = s0
	v.previous_phase = s0
	var reverse := 0
	var was := false
	var on_deck := false
	var clock := 0.0
	for tick in range(60 * 40):
		f.step(DT, float(tick + 1) * DT)
		if v.reversing and not was:
			reverse += 1
		was = v.reversing
		if v.deck != null and not on_deck and v.free_series:
			clock = v.free_clock
		on_deck = on_deck or v.deck != null
		if v.crashed or v.progress > s0 + 80.0 / t.length:
			break
	return {"ok": on_deck and not v.crashed, "reverse": reverse, "clock": clock, "cause": v.wreck_cause if v.wrecked else ("Absturz" if v.crashed else "Zeit")}

func add_block(t: Circuit, c: Vector2, u: Vector2, half: Vector2) -> void:
	# Mauer zur Laufzeit (Rechteck, 1,2 m hoch) samt Eintrag im Suchraster.
	t.add_rect(c, u, half, 1.2, "mauer")
	var i := t.obstacles.size() - 1
	var reach := half.length()
	for gx in range(floori((c.x - reach) / Circuit.OBSTACLE_CELL), floori((c.x + reach) / Circuit.OBSTACLE_CELL) + 1):
		for gz in range(floori((c.y - reach) / Circuit.OBSTACLE_CELL), floori((c.y + reach) / Circuit.OBSTACLE_CELL) + 1):
			var key := Vector2i(gx, gz)
			if not t.obstacle_grid.has(key):
				t.obstacle_grid[key] = []
			t.obstacle_grid[key].append(i)

func free_run(kind: String, psi: float, speed: float) -> Dictionary:
	# Stadion-Gerade mit Mauern zur Laufzeit; Linie in der Mitte (ai_route), Start 40 m nach dem Start.
	#   "laengs":  Mauer längs am rechten Rand (b −5), das Auto liegt an, Nase um psi hineingedreht.
	#   "ecke":    dazu eine Quermauer über die rechte Hälfte (b −1 … −5,5) 6 m voraus: Nase in der Ecke, die Linie führt daran vorbei.
	#   "quer":    Quermauer über die ganze Insel 25 m voraus: Die Linie führt hindurch.
	#   "nase":    wie "laengs", aber die Nase (um psi gedreht) liegt mit dem vorderen Kreis an der Mauer an.
	RaceVehicle.weather_grip = 1.0
	var t := stadion()
	var route := t.ai_route(2.3)
	var s0 := 40.0 / t.length
	var tg := t.tangent(s0)
	var side := Vector2(-tg.y, tg.x)
	var lane := 0.0
	if kind in ["laengs", "ecke", "nase"]:
		add_block(t, t.at(s0, -5.0) + tg * 10.0, tg, Vector2(30.0, 0.2))
		lane = -5.0 + 0.2 + RaceVehicle.CAR_RADIUS + 0.05
	if kind == "ecke":
		add_block(t, t.at(s0, -3.25) + tg * 6.0, tg, Vector2(0.3, 2.25))
		lane = -3.5
	if kind == "quer":
		add_block(t, t.at(s0) + tg * 25.0, tg, Vector2(0.3, 16.0))
	var v := RaceVehicle.new(t, route, s0, lane)
	v.heading += psi
	if kind == "nase":
		var nose: float = (v.pos + Vector2.from_angle(v.heading) * RaceVehicle.CAR_REACH - t.at(s0)).dot(side)
		v.pos += side * (-5.0 + 0.2 + RaceVehicle.CAR_RADIUS + 0.05 - nose)
	v.velocity = Vector2.from_angle(v.heading) * speed
	var reverse := 0
	var was := false
	var wrong_brake := 0
	var time := 0.0
	var blocked := false
	for tick in range(60 * 30):
		var u0 := v.velocity.dot(Vector2.from_angle(v.heading))
		v.step(DT, false, float(tick + 1) * DT)
		time = float(tick + 1) * DT
		# Bremse immer gegen die Bewegung: Sie kehrt das Längstempo in einem Takt nie über den Stillstand hinaus um.
		var u1 := v.velocity.dot(Vector2.from_angle(v.heading))
		if v.braking > 0.5 and absf(u0) > 0.5 and u0 * u1 < 0.0 and absf(u1) > 0.3:
			wrong_brake += 1
		if v.reversing and not was:
			reverse += 1
			if reverse == 1:
				blocked = v.line_blocked()
		was = v.reversing
		if v.crashed or (v.progress - s0) * t.length > 80.0:
			break
	return {"wrecked": v.wrecked, "cause": v.wreck_cause, "gain": (v.progress - s0) * t.length, "reverse": reverse, "time": time, "brake": wrong_brake, "blocked": blocked,
		"pos": v.pos, "heading": v.heading, "side": side}

func test_free() -> void:
	# Freifahren (Nutzerentscheidung 15.10.2026): Nach kurzem Festhängen setzt das Auto ein Stück vom Hindernis weg zurück und fährt weiter.
	# Führt die Linie mitten durchs Hindernis, bleibt es beim Wrack.
	for psi in [-0.5, -1.0]:
		for sp in [2.0, 5.0]:
			var r := free_run("laengs", psi, sp)
			check(not bool(r.wrecked) and float(r.gain) > 80.0 and int(r.brake) == 0,
				"Mauer längs, Nase %.1f rad hinein, %.0f m/s: frei und weiter (%.0f m, %d× zurückgesetzt, %.1f s)" % [psi, sp, r.gain, r.reverse, r.time])
	# Nase quer an der Mauer (die Linie verläuft parallel in der Mitte): Vorwärts kommt das Auto nicht los, es setzt zurück und fährt weiter.
	# Die Fälle oben kommen ohne Zurücksetzen frei (Gegenprüfung: sie prüften das Freifahren gar nicht).
	for c in [[-1.57, 0.0], [-1.57, 5.0], [-1.4, 0.0], [-1.4, 2.0]]:
		var rn := free_run("nase", float(c[0]), float(c[1]))
		check(not bool(rn.wrecked) and float(rn.gain) > 80.0 and int(rn.reverse) >= 1 and int(rn.brake) == 0,
			"Nase %.2f rad an der Mauer, %.0f m/s: zurückgesetzt (%d×) und weiter (%.0f m, %.1f s)" % [c[0], c[1], rn.reverse, rn.gain, rn.time])
	var corner := free_run("ecke", 0.0, 3.0)
	check(not bool(corner.wrecked) and float(corner.gain) > 80.0 and int(corner.reverse) >= 1,
		"Nase in einer Ecke, Linie führt vorbei: zurücksetzen und weiter (%d× zurückgesetzt, %.0f m, %.1f s)" % [corner.reverse, corner.gain, corner.time])
	var cross := free_run("quer", 0.0, 0.0)
	check(bool(cross.wrecked) and str(cross.cause).begins_with("fest") and int(cross.reverse) == RaceVehicle.FREE_TRIES and float(cross.time) < 20.0,
		"Linie durch die Mauer (line_blocked): nach %d Versuchen Wrack „%s“ nach %.1f s" % [cross.reverse, cross.cause, cross.time])
	check(bool(cross.blocked) and not bool(corner.blocked), "Wrack-Regel prüft die Linie: durch die Quermauer gesperrt (%s), an der Ecke vorbei frei (%s) – dort mehr Versuche" % [cross.blocked, corner.blocked])
	check(int(corner.brake) == 0 and int(cross.brake) == 0, "Bremse wirkt immer gegen die Bewegung (vorwärts wie rückwärts)")
	# Reproduzierbar: dieselbe Befreiung zweimal ergibt dieselbe Lage.
	var again := free_run("ecke", 0.0, 3.0)
	check(Vector2(corner.pos).is_equal_approx(again.pos) and is_equal_approx(float(corner.heading), float(again.heading)), "Freifahren reproduzierbar")

func test_spin() -> void:
	# Dreher-Raster als Regression: quer (±90°) oder rückwärts (180°) auf der Linie, stehend oder mit 6 m/s, 8 Strecken × 4 Stellen.
	# Ankommen = 60 m Fortschritt in 20 s. Alter Regler: 45 von 192 Starts ausgefallen.
	RaceVehicle.weather_grip = 1.0
	var n := 0
	var fail := 0
	for id in ["azure", "city", "forest", "harbor", "serra", "fair", "quarry", "kids"]:
		var t := Circuit.load_track(id)
		var route := t.ai_route(2.3)
		for s0 in [0.1, 0.35, 0.6, 0.85]:
			for turn in [PI * 0.5, -PI * 0.5, PI]:
				for sp in [0.0, 6.0]:
					var probe := RaceVehicle.new(t, route, s0, 0.0)
					probe.heading += turn
					probe.collide_obstacles(DT)
					if probe.obstacle_hit > 0.0:
						continue   # im Hindernis gestartet
					var v := RaceVehicle.new(t, route, s0, 0.0)
					v.heading += turn
					v.velocity = Vector2.from_angle(v.heading) * sp
					var goal: float = s0 + 60.0 / t.length
					var done := false
					for tick in range(60 * 20):
						v.step(DT, false, float(tick + 1) * DT)
						if v.crashed or v.finish_time >= 0.0:
							break
						if v.progress > goal:
							done = true
							break
					n += 1
					# Serra ist eine Sprintstrecke: hinter dem Ziel (s 0,85 + 60 m) zählt das Ziel als angekommen.
					if not done and not (v.finish_time >= 0.0):
						fail += 1
	check(n >= 180 and fail <= 19, "Dreher-Raster: %d von %d Starts ausgefallen ≤ 19 (alter Regler 45, vor der Nachbesserung 19)" % [fail, n])

func test_lines() -> void:
	# Zu schnell gezeichnete Kurven (Plantempo in Kurven ×1,3/×1,45) und wellige Linien (±1,6 m): Das Auto rutscht hinaus, bremst dabei
	# nur so stark, wie der Reibkreis neben dem Zurücklenken zulässt (keine Vollbremsung quer), findet zurück und kommt ins Ziel. Alter Regler:
	# Stadt ×1,45 und Wald ×1,45 Wrack.
	RaceVehicle.weather_grip = 1.0
	var fails := []
	var n := 0
	for id in ["azure", "city", "forest", "harbor", "serra", "fair", "quarry", "kids"]:
		for va in [1.3, 1.45, 0.0]:
			var t := Circuit.load_track(id)
			var route := t.ai_route(2.3)
			if float(va) > 0.0:
				for p in route:
					if t.curvature(t.unit(float(p.s))) > 0.02:
						p.speed = float(p.speed) * float(va)
			else:
				var rng := RandomNumberGenerator.new()
				rng.seed = 4
				var jitter := 0.0
				for point in route:
					if int(point.get("sc", -1)) >= 0:
						continue
					jitter = lerpf(jitter, rng.randf_range(-1.0, 1.0), 0.3)
					var o := 1.6 * sin(float(point.s) * TAU * 11.0) + jitter * 0.8
					point.o = clampf(o, -t.hw(float(point.s)) + 0.5, t.hw(float(point.s)) - 0.5)
					point.p = t.at(float(point.s), float(point.o))
			var v := RaceVehicle.new(t, route)
			var hard := 0
			for tick in range(60 * 200):
				# Schwimmwinkel zu Beginn des Takts: danach dosiert der Fahrer in diesem Takt die Bremse.
				var slide := absf(wrapf(v.heading - v.velocity.angle(), -PI, PI)) if v.velocity.length() > 3.0 else 0.0
				v.step(DT, false, float(tick + 1) * DT)
				if slide > RaceVehicle.BRAKE_SLIDE1 and v.braking > RaceVehicle.BRAKE_FLOOR + 0.01 and not v.reversing:
					hard += 1
				if v.crashed or v.finish_time >= 0.0:
					break
			n += 1
			if v.finish_time < 0.0 or hard > 0:
				fails.append("%s %s: %s, %d Takte Vollbremsung quer" % [id, ("×%.2f" % va) if va > 0.0 else "wellig", "Ziel" if v.finish_time >= 0.0 else v.wreck_cause, hard])
	check(fails.is_empty(), "Zu schnelle und wellige Linien: %d/%d im Ziel, quer rutschend nie voll gebremst %s" % [n - fails.size(), n, str(fails)])

func solo_time(t: Circuit, route: Array[Dictionary]) -> float:
	var v := RaceVehicle.new(t, route)
	for tick in range(60 * 200):
		v.step(DT, false, float(tick + 1) * DT)
		if v.crashed or v.finish_time >= 0.0:
			break
	return v.finish_time

func wavy_route(t: Circuit, amp: float, waves: float, seed_value: int) -> Array[Dictionary]:
	# Spielerlinie ai_route(2.0) mit Wellen (amp m, waves je Runde) und Zittern; Abkürzungen bleiben glatt.
	var route := t.ai_route(2.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var jitter := 0.0
	for point in route:
		if int(point.get("sc", -1)) >= 0:
			continue
		jitter = lerpf(jitter, rng.randf_range(-1.0, 1.0), 0.3)
		var o: float = amp * sin(float(point.s) * TAU * waves) + jitter * 0.8
		point.o = clampf(o, -t.hw(float(point.s)) + 0.5, t.hw(float(point.s)) - 0.5)
		point.p = t.at(float(point.s), float(point.o))
	return route

func test_wavy() -> void:
	# Wellig gezeichnete Linien (±1,1/1,6 m, 11/20 Wellen je Runde, zwei Saaten) schneidet die Linienfolge glatt, wie ein Tiefpass: höchstens
	# 4 % langsamer als die glatte Linie derselben Stufe (alter Regler bis 3,2 %). Gegen die rohe Linie gemessen begann die Episode im
	# Sekundentakt und bremste jedes Mal (Gegenprüfung: Azure +45 %, Kinderzimmer Absturz im Looping); jetzt misst sie gegen die geglättete
	# Linie (smooth_line).
	RaceVehicle.weather_grip = 1.0
	var worst := 0.0
	var text := []
	var fails := []
	for id in ["azure", "city", "kids"]:
		var t := Circuit.load_track(id)
		var smooth := solo_time(t, t.ai_route(2.0))
		for amp in [1.1, 1.6]:
			for waves in [11.0, 20.0]:
				for sd in [1, 2]:
					var time := solo_time(t, wavy_route(t, amp, waves, sd))
					if time < 0.0:
						fails.append("%s %.1f/%.0f/%d nicht im Ziel" % [id, amp, waves, sd])
						continue
					worst = maxf(worst, time / smooth - 1.0)
					if sd == 1:
						text.append("%s %.1f/%.0f %+.1f %%" % [id, amp, waves, (time / smooth - 1.0) * 100.0])
	check(fails.is_empty() and worst <= 0.04, "Wellige Linien höchstens %.1f %% langsamer als glatt (≤ 4 %%): %s %s" % [worst * 100.0, ", ".join(text), str(fails)])

func test_rail() -> void:
	# Nase zur Leitplanke: Serra, 2,5 m neben der Linie quer zur nahen Kante, 8/10 m/s, 28 Stellen. Die Episode beginnt dann ohne Einblenden,
	# voller Einschlag, Tempodeckel sofort: Die Planke hält (Gegenprüfung: mit 0,25 s Einblenden gab der Fahrer erst Plantempo-Gas, lenkte
	# nur −0,25 statt −0,62 ein und durchbrach sie). Abstürze ohne Planke (Steilküste ohne Leitplanke) weniger als mit dem alten Regler (10).
	RaceVehicle.weather_grip = 1.0
	var t := Circuit.load_track("serra")
	var route := t.ai_route(2.3)
	var n := 0
	var broke := []
	var fell := 0
	for k in range(32):
		var s0 := (float(k) + 0.5) / 32.0
		if s0 > 0.9:
			continue
		for sd in [1.0, -1.0]:
			for sp in [8.0, 10.0]:
				var probe := RaceVehicle.new(t, route, s0, sd * 2.5)
				probe.heading += sd * PI * 0.5
				probe.collide_obstacles(DT)
				if probe.obstacle_hit > 0.0:
					continue
				var v := RaceVehicle.new(t, route, s0, sd * 2.5)
				v.heading += sd * PI * 0.5
				v.velocity = Vector2.from_angle(v.heading) * sp
				n += 1
				for tick in range(60 * 8):
					v.step(DT, false, float(tick + 1) * DT)
					if v.crashed:
						break
				if v.broke_rail:
					broke.append("s%.3f %+.0f %.0f m/s" % [s0, sd, sp])
				elif v.crashed and not v.wrecked:
					fell += 1
	check(n >= 100 and broke.is_empty() and fell <= 9, "Nase zur Leitplanke (Serra, %d Starts): Planke hält %s, Abstürze %d ≤ 9 (alter Regler 10)" % [n, str(broke), fell])

func test_grid_start() -> void:
	# Startaufstellung: Autos hinter dem ersten Linienpunkt messen den Querabstand zur Verlängerung der Linie, nicht den Punktabstand
	# (Gegenprüfung: jedes Auto ab Startplatz 2 begann sofort eine Episode, 3–19 m „neben der Linie“).
	var bad := []
	for id in ["azure", "harbor", "kids"]:
		RaceVehicle.weather_grip = 1.0
		var t := Circuit.load_track(id)
		var f := RaceField.new(t)
		f.setup_entries(RaceField.lineup([RaceField.human_entry(t.ai_route(2.0, 0.0))], 2, -1, false))
		for tick in range(60 * 2):
			f.step(DT, float(tick + 1) * DT)
			for i in range(f.cars.size()):
				if f.cars[i].rec_episode and not bad.has("%s Platz %d" % [id, i + 1]):
					bad.append("%s Platz %d" % [id, i + 1])
	check(bad.is_empty(), "Startaufstellung: keine Episode in den ersten 2 s %s" % str(bad))

func test_misc() -> void:
	# Drift-Modus: eigener Fahrer (drift_driver), keine Rückkehr-Episoden; die Arena fährt wie bisher durch.
	RaceVehicle.weather_grip = 1.0
	var arena := Circuit.load_track("arena")
	var d := RaceVehicle.new(arena, arena.ai_route(2.3))
	var ep := false
	for tick in range(60 * 200):
		d.step(DT, false, float(tick + 1) * DT)
		ep = ep or d.rec_episode or d.rec_fade > 0.0
		if d.finish_time >= 0.0 or d.crashed:
			break
	check(arena.mode == "drift" and d.finish_time > 0.0 and not ep, "Drift-Modus: eigener Fahrer, keine Rückkehr-Episode, Arena im Ziel (%.2f s)" % d.finish_time)
	# Determinismus: derselbe Rückkehrfall zweimal.
	var t := stadion()
	var route := t.ai_route(2.3)
	var a := return_case(t, route, 30.0, 6.0, 0.35, false, 4.0)
	var b := return_case(t, route, 30.0, 6.0, 0.35, false, 4.0)
	check(Vector2(a.pos).is_equal_approx(b.pos) and is_equal_approx(float(a.heading), float(b.heading)), "Rückkehr reproduzierbar")
	check(RaceVehicle.VERSION == "bicycle-7", "Physikversion bleibt bicycle-7 (%s)" % RaceVehicle.VERSION)

func _init() -> void:
	var t0 := Time.get_ticks_msec()
	test_straight()
	test_grid()
	test_free()
	test_misc()
	test_zones()
	test_lineal()
	test_gold()
	test_lines()
	test_wavy()
	test_rail()
	test_grid_start()
	test_spin()
	print("Dauer %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	print("RESULT: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures > 0 else 0)
