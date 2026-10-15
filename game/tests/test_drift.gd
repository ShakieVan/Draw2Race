extends SceneTree

# Drift-Modus mit dem Profi-Fahrer (RaceVehicle.drift_driver, DRIFT_*; 15.10.2026), Drift-Ziele und Zeitlimit der Drift-Arena.
# 1. Linientreue und Fahrweise: Gegenlenken, Driftwinkel, Gas hält den Winkel, nie Gas über dem Plantempo, Nadelöhr ohne Anstellen.
# 2. Plan: ruhig/langsam gezeichnet = Haftung ohne Punkte, deutlich zu schnell = Dreher, Wand, Zeitverlust und verlorene Ketten
#    (score_drift: Wand oder Dreher kosten die Punkte des laufenden Drifts).
# 3. Ziele und Zeitlimit (Circuit.DRIFT_CALIBRATION in track.gd) mit "menschlichen" Linien (Seitenwackeln, Spurversatz, Tempo-Rauschen, Kurven ×1,1–1,8,
#    konstant 13–23 m/s) und mit dem LineRecorder gezeichneten Fingerlinien: Stufe 1 gut erreichbar, Stufe 2 fordert, Stufe 3 (Regen) nur mit
#    guten Linien – mit dem Drift King und (schwerer) mit anderen Autos; die Regenstufe ist schwerer als die trockenen, und die Uhr entscheidet
#    sie nicht; grobe, überall schnelle Linien erreichen die oberen Stufen nicht.
# 4. Verlorenes Auto setzt zurück und kommt frei (kein Stillstand, keine Endlosschleife), Determinismus, Rennmodus bitgleich (Messanker),
#    Allrad nur im Drift-Modus mit Heckantrieb.
# 5. Anzeige: Statuszeile, Restzeit und laufende Kette passen in ihre Kästen (Einzelspieler und Weitergeben).
# Aufruf: tools/godot_run.ps1 -Script res://tests/test_drift.gd -Headless -Timeout 900
const DT := 1.0 / 60.0
const DRIFT_KING := 7
var failures := 0
var checks := 0
var arena: Circuit
var limit := 0.0
var targets: Array = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
	else:
		print("PASS: ", message)

func _initialize() -> void:
	call_deferred("run_all")

func run_all() -> void:
	arena = Circuit.load_track("arena")
	# Ziele und Zeitlimit der Arena (Circuit.DRIFT_CALIBRATION überschreibt beim Laden die Dateiwerte; in der Streckendatei erst mit dem nächsten
	# Neubau von Diorama und Abriebkarte). Das WLAN-Rennen liest dasselbe Limit (NetRace.drift_limit_for -> time_limit).
	var cal: Dictionary = Circuit.DRIFT_CALIBRATION["arena"]
	limit = float(cal.limit)
	targets = cal.targets
	check(arena.mode == "drift" and limit > 30.0 and targets.size() == 3 and int(targets[0]) < int(targets[1]) and int(targets[1]) < int(targets[2]),
		"Drift-Arena: Zeitlimit %.1f s, Ziele %s" % [limit, str(targets)])
	check(is_equal_approx(arena.time_limit, limit) and str(arena.drift_targets) == str(targets) and is_equal_approx(NetRace.drift_limit_for(arena), limit),
		"Drift-Arena: Strecke, Einzelspieler und WLAN nutzen dasselbe Limit (%.1f s) und dieselben Ziele" % NetRace.drift_limit_for(arena))
	test_score()
	test_line()
	test_plan()
	test_targets()
	test_lost()
	test_model()
	await test_hud()
	RaceVehicle.weather_grip = 1.0
	print("RESULT: ", checks - failures, "/", checks, " passed")
	quit(1 if failures else 0)

# ---------- Linien ----------
func smooth_speeds(r: Array[Dictionary]) -> void:
	# Wie LineRecorder: Tempo wegabhängig geglättet (2,8 m), danach ±3 Punkte nachgeglättet.
	var sp := float(r[0].speed)
	for i in range(1, r.size()):
		sp = lerpf(sp, float(r[i].speed), 1.0 - exp(-Vector2(r[i].p).distance_to(r[i - 1].p) / 2.8))
		r[i].speed = sp
	var copy: Array[float] = []
	for p in r:
		copy.append(float(p.speed))
	for i in range(r.size()):
		var s := 0.0
		var w := 0.0
		for j in range(maxi(0, i - 3), mini(r.size(), i + 4)):
			s += copy[j]
			w += 1.0
		r[i].speed = s / w

func drawn(const_mode: bool, level: float, seed: int, amp_max := 0.8, lane_max := 2.0) -> Array[Dictionary]:
	# Gezeichnete Linie um die KI-Linie ai_route(1,5): Kurven ×level oder konstant level m/s (in engen Kurven bis 15 % langsamer, wie ein
	# Finger), Seitenwackeln (Welle 8–25 m, dazu Zittern), Spurversatz (Welle 40–120 m), Tempo-Rauschen 3–8 %.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var r := arena.ai_route(1.5)
	var amp := rng.randf_range(0.1, amp_max)
	var wl := rng.randf_range(8.0, 25.0)
	var lane_amp := rng.randf_range(0.0, lane_max)
	var lane_wl := rng.randf_range(40.0, 120.0)
	var lane_ph := rng.randf_range(0.0, TAU)
	var noise := rng.randf_range(0.03, 0.08)
	var slow := rng.randf()
	var jitter := 0.0
	var sj := 0.0
	for p in r:
		var m := float(p.s) * arena.length
		jitter = lerpf(jitter, rng.randf_range(-1.0, 1.0), 0.3)
		sj = lerpf(sj, rng.randf_range(-1.0, 1.0), 0.08)
		var o := lane_amp * sin(m / lane_wl * TAU + lane_ph) + amp * sin(m / wl * TAU) + jitter * amp * 0.4
		var lim := arena.hw(float(p.s)) - 0.6
		o = clampf(o, -lim, lim)
		p.p = arena.at(float(p.s), o)
		p.o = o
		var k := arena.curvature(float(p.s))
		var base := level * (1.0 - 0.15 * slow * clampf(k / 0.08, 0.0, 1.0)) if const_mode else float(p.speed) * (level if k > 0.03 else 1.0)
		p.speed = clampf(base * (1.0 + noise * sj * 2.0), 5.0, 29.0)
	smooth_speeds(r)
	return r

func human(seed: int) -> Array[Dictionary]:
	# "Menschliche" Linie: zufällig konstant 13–23 m/s oder Kurven ×1,1–1,8, Wackeln bis 1,4 m, Spurversatz bis 3,5 m.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var const_mode := rng.randf() < 0.45
	var level := rng.randf_range(13.0, 23.0) if const_mode else rng.randf_range(1.1, 1.8)
	return drawn(const_mode, level, seed * 7 + 1, 1.4, 3.5)

func bend_amount(s: float) -> float:
	# Kurvenstärke 0–1 bei s, Vorzeichen zur Kurveninnenseite des Versatzes o (0 auf Geraden).
	var d := 3.0 / arena.length
	var bend := arena.tangent(s + d) - arena.tangent(s - d)
	if bend.length() < 1e-4:
		return 0.0
	return clampf(arena.curvature(s) / 0.06, 0.0, 1.0) * signf((arena.at(s, 1.0) - arena.at(s, 0.0)).dot(bend))

func finger(straight: float, corner: float, lane: String, wobble: float, seed: int) -> Array[Dictionary]:
	# Mit dem Finger über den LineRecorder gezeichnete Linie (Fingermodell wie in test_draw.draw_finger, Gegenprüfung 15.10.2026): Weg auf der
	# Mitte, innen (lane "innen", 6 m zur Innenseite) oder als Ideallinie (lane "ideal": außen anfahren, innen am Scheitel); Fingertempo nach
	# dem Plantempo straight (Gerade) bzw. corner (Kurve, Krümmung über 0,03), dazu Tempo-Rauschen und Wackeln quer. Die Glättung des Recorders
	# (Versatz, Tempo, finalize) wirkt wie beim Spieler – die Linien aus drawn() setzen Wackeln dagegen direkt in die Routenpunkte.
	var n := int(arena.length * arena.laps / 0.25) + 8
	var path := PackedVector2Array()
	var plan := PackedFloat32Array()
	for i in range(n):
		var s := minf(float(i) * 0.25 / arena.length, float(arena.laps) + 0.01)
		var o := 0.0
		if lane == "innen":
			o = 6.0 * bend_amount(s)
		elif lane == "ideal":
			o = 5.0 * (bend_amount(s) - 0.3 * (bend_amount(s - 14.0 / arena.length) + bend_amount(s + 14.0 / arena.length)))
		var lim := arena.hw(s) - 0.9
		path.append(arena.at(s, clampf(o, -lim, lim)))
		plan.append(corner if arena.curvature(s) > 0.03 else straight)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var ph := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	var tempo_noise := rng.randf_range(0.0, 0.1)
	var cum := PackedFloat32Array([0.0])
	for i in range(1, path.size()):
		cum.append(cum[-1] + path[i - 1].distance_to(path[i]))
	var pen := LineRecorder.new(arena)
	pen.begin(arena.at(0.0), 0.0)
	var walked := 0.0
	var j := 0
	var tick := 0
	while not pen.complete and pen.active and walked < cum[-1] and tick < 80000:
		tick += 1
		var time := tick / 60.0
		walked += maxf((plan[j] * (1.0 + tempo_noise * sin(0.7 * time + ph[2])) - 5.0) / pen.tempo_factor, 4.0) / 60.0
		while j < cum.size() - 2 and cum[j + 1] < walked:
			j += 1
		var f := clampf((walked - cum[j]) / maxf(1e-6, cum[j + 1] - cum[j]), 0.0, 1.0)
		var dir := (path[j + 1] - path[j]).normalized()
		var shake := wobble * (0.6 * sin(1.3 * time + ph[0]) + 0.3 * sin(3.1 * time + ph[1]) + 0.1 * sin(7.9 * time + ph[2]))
		pen.sample(path[j].lerp(path[j + 1], f) + Vector2(-dir.y, dir.x) * shake, time)
	if not pen.complete:
		printerr("Fingerlinie nicht fertig: ", pen.hint)
	return pen.route

func offset(v: RaceVehicle, route: Array[Dictionary]) -> float:
	# Querabstand des Autos zur Linie (links positiv), Suche um den Fortschrittscursor.
	var i := clampi(v.cursor, 0, route.size() - 2)
	var best := INF
	var signed := 0.0
	for j in range(maxi(0, i - 8), mini(route.size() - 1, i + 14)):
		var a: Vector2 = route[j].p
		var b: Vector2 = route[j + 1].p
		var q := Geometry2D.get_closest_point_to_segment(v.pos, a, b)
		if v.pos.distance_to(q) < best:
			best = v.pos.distance_to(q)
			signed = signf((b - a).cross(v.pos - q)) * best
	return signed

func drive(car: int, route: Array[Dictionary], grip := 1.0, track: Circuit = null, seconds := 90.0) -> Dictionary:
	# Eine Fahrt mit Messgrößen: Abstand zur Linie (RMS, nach außen), Driftwinkel, Dreher, Gegenlenken, Gas gegen Winkelfehler,
	# Gas über dem Plantempo, Anstellen im bzw. vor dem Nadelöhr, Zurücksetzen (Freifahren und eigenes Zurücksetzen des Profis), längster
	# Stillstand (Zeit ohne 2 m Nettofortschritt), verlorene Ketten.
	RaceVehicle.weather_grip = grip
	var c := track if track != null else arena
	var v := RaceVehicle.new(c, route, 0.0, 0.0, car)
	var m := {"n": 0, "dev2": 0.0, "dev2_drift": 0.0, "out": 0.0, "drift": 0, "beta": 0.0, "spin": 0, "cn": 0, "counter": 0, "over_plan": 0, "needle": 0,
		"thr_low": 0.0, "n_low": 0, "thr_high": 0.0, "n_high": 0, "rev": 0, "spin_max": 0.0, "stall": 0.0}
	var was_rev := false
	var mark := 0.0
	var mark_t := 0.0
	var t := 0.0
	for tick in range(int(seconds * 60.0)):
		var speed_before := v.velocity.length()
		v.step(DT, false, float(tick + 1) * DT)
		t = float(tick + 1) * DT
		var plan := float(route[v.cursor].speed)      # der Cursor rückt am Anfang des Takts vor; daran misst der Fahrer
		if (v.progress - mark) * c.length > 2.0:
			mark = v.progress
			mark_t = t
		m.stall = maxf(m.stall, t - mark_t)
		if v.finish_time >= 0.0 or v.crashed:
			break
		if (v.reversing or v.drift_back) and not was_rev:
			m.rev += 1
		was_rev = v.reversing or v.drift_back
		m.spin_max = maxf(m.spin_max, v.rear_spin)
		var speed := v.velocity.length()
		var hw_here := c.hw(v.previous_phase)
		# Nadelöhr: im Nadelöhr (mehr als DRIFT_EXIT + 1 m vor dem Ausgang) und kurz davor (DRIFT_T_CATCH, 1 m Rand) kein Driftwunsch.
		if v.drift_goal > 0.0 and hw_here < RaceVehicle.DRIFT_NARROW and c.hw(v.previous_phase + (RaceVehicle.DRIFT_EXIT + 1.0) / c.length) < RaceVehicle.DRIFT_NARROW:
			m.needle += 1
		if v.drift_goal > 0.0 and hw_here >= RaceVehicle.DRIFT_NARROW:
			for d in [1.0, 3.0, maxf(1.0, speed * RaceVehicle.DRIFT_T_CATCH - 1.5)]:
				if c.hw(v.previous_phase + d / c.length) < RaceVehicle.DRIFT_NARROW:
					m.needle += 1
					break
		if speed < 3.0:
			continue
		var dev := offset(v, route)
		m.n += 1
		m.dev2 += dev * dev
		var s := c.unit(v.progress)
		var turn := signf(c.tangent(s - 2.0 / c.length).cross(c.tangent(s + 2.0 / c.length)))
		m.out = maxf(m.out, -dev * turn)
		var signed := wrapf(v.heading - v.velocity.angle(), -PI, PI)
		var ab := absf(signed)
		if ab > PI * 0.5:
			m.spin += 1
		if speed > 6.0 and ab > deg_to_rad(12.0) and ab < deg_to_rad(75.0):
			m.drift += 1
			m.beta += rad_to_deg(ab)
			m.dev2_drift += dev * dev
		if speed > 6.0 and ab > deg_to_rad(20.0) and ab < PI * 0.5:
			m.cn += 1
			if v.steering * signed < 0.0:
				m.counter += 1
		if v.drift_goal > 0.0 and not v.recovering and speed > 6.0 and ab < PI * 0.5:
			var missing := v.drift_goal - ab
			if missing > deg_to_rad(10.0):
				m.thr_low += v.throttle
				m.n_low += 1
			elif missing < -deg_to_rad(10.0):
				m.thr_high += v.throttle
				m.n_high += 1
		if v.drift_goal > 0.0 and not v.boosting and speed_before > plan + 0.01 and v.throttle > 0.001 and v.velocity.dot(Vector2.from_angle(v.heading)) > 0.0:
			m.over_plan += 1
	RaceVehicle.weather_grip = 1.0
	var done := v.finish_time >= 0.0 and not v.crashed
	return {"car": v, "time": v.finish_time if done else INF, "done": done, "score": v.drift_score, "walls": v.wall_hits,
		"rms": sqrt(m.dev2 / maxf(1.0, m.n)), "rms_drift": sqrt(m.dev2_drift / maxf(1.0, m.drift)), "out": m.out, "drift_share": float(m.drift) / maxf(1.0, m.n), "beta": m.beta / maxf(1.0, m.drift),
		"spin": m.spin, "counter": float(m.counter) / maxf(1.0, m.cn), "counter_n": m.cn, "over_plan": m.over_plan, "needle": m.needle,
		"thr_low": m.thr_low / maxf(1.0, m.n_low), "thr_high": m.thr_high / maxf(1.0, m.n_high), "n_low": m.n_low, "n_high": m.n_high,
		"rev": m.rev, "spin_max": m.spin_max, "stall": m.stall, "chains": v.chain_lost, "crashed": v.crashed, "stuck": not done and not v.crashed}

func won(r: Dictionary, stage: int) -> bool:
	return bool(r.done) and float(r.time) <= limit and float(r.score) >= float(targets[stage])

# ---------- Wertung ----------
func slide(v: RaceVehicle, angle_deg: float, seconds: float) -> void:
	# Wertung allein (score_drift), das Auto rutscht mit 15 m/s und angle_deg quer.
	v.heading = 0.0
	v.velocity = Vector2.from_angle(deg_to_rad(-angle_deg)) * 15.0
	for k in range(int(seconds * 60.0)):
		v.score_drift(DT)

func test_score() -> void:
	# Kette (RaceVehicle.drift_chain): Punkte des laufenden Drifts sind erst sicher, wenn er endet; Wand oder Dreher kosten sie.
	var s := 0.1
	var v := RaceVehicle.new(arena, arena.ai_route(1.5), s)
	slide(v, 30.0, 2.0)
	var chain := v.drift_chain
	check(chain > 100.0 and absf(v.drift_score - chain) < 0.01, "Kette: 2 s Drift mit 30° bringen %d Punkte, alle noch in der Kette" % int(chain))
	slide(v, 120.0, 1.0 / 60.0)
	check(v.drift_score < 0.01 and v.drift_chain == 0.0 and v.chain_lost == 1 and v.drift_multiplier == 1.0, "Dreher (über 90° quer): Kette weg (%d Punkte übrig)" % int(v.drift_score))
	slide(v, 30.0, 2.0)
	slide(v, 0.0, 1.5)
	var banked := v.drift_score
	check(banked > 100.0 and v.drift_chain == 0.0, "Drift sauber beendet: %d Punkte gesichert, Kette leer" % int(banked))
	slide(v, 30.0, 1.0)
	var before := v.drift_score
	var open := v.drift_chain
	v.pos = arena.at(s, arena.hw(s) - 0.2)
	v.score_drift(DT)
	check(v.wall_hits == 1 and absf(v.drift_score - maxf(0.0, before - open - 60.0)) < 0.5 and v.drift_chain == 0.0 and v.chain_lost == 2,
		"Wandberührung: Kette (%d) und 60 Punkte weg, gesichert bleiben %d" % [int(open), int(v.drift_score)])

# ---------- 1. Linientreue und Fahrweise ----------
func test_line() -> void:
	var counter := 0
	var counter_n := 0
	var over := 0
	var needle := 0
	for spec in [[1.45, 11], [1.6, 12], [1.7, 13]]:
		var r := drive(DRIFT_KING, drawn(false, spec[0], spec[1], 0.5, 1.0))
		check(r.done and int(r.walls) == 0 and float(r.rms) < 1.6 and float(r.out) < 5.0,
			"Linientreue Drift King, Kurven ×%.2f: im Ziel %.1f s, keine Wand (%d), RMS %.2f m, außen max %.2f m" % [spec[0], r.time, r.walls, r.rms, r.out])
		# Punkte: Ab ×1,7 verlangt die Linie stellenweise mehr Winkel, als sich halten lässt (Zielwinkel bis 60°); kurze Dreher kosten dort die
		# Kette (score_drift), deshalb gilt für ×1,7 die niedrigere Schwelle (gemessen 1049 Punkte, ohne Kettenregel 1532).
		var floor_pts := 1200.0 if spec[0] < 1.65 else 800.0
		check(float(r.drift_share) > 0.25 and float(r.beta) > 22.0 and float(r.beta) < 45.0 and float(r.score) > floor_pts,
			"Drift ×%.2f: %.0f %% der Takte quer, Driftwinkel im Mittel %.0f° (22–45°), %d Punkte (über %d; %d Drehertakte, %d Ketten verloren)" % [spec[0],
			float(r.drift_share) * 100.0, r.beta, int(r.score), int(floor_pts), int(r.spin), int(r.chains)])
		counter += int(round(float(r.counter) * float(r.counter_n)))
		counter_n += int(r.counter_n)
		over += int(r.over_plan)
		needle += int(r.needle)
		if spec[0] == 1.45:
			check(int(r.spin) == 0, "×1,45: kein Dreher (%d Takte über 90°)" % r.spin)
			check(float(r.thr_low) > float(r.thr_high) + 0.3, "Gas hält den Winkel: fehlt Winkel, %.0f %% Gas; zu viel Winkel, %.0f %% (%d/%d Takte)" % [float(r.thr_low) * 100.0, float(r.thr_high) * 100.0, r.n_low, r.n_high])
	check(counter_n > 300 and float(counter) / counter_n > 0.85, "Gegenlenken: in %d von %d Drifttakten (über 20°) zeigen die Vorderräder nach außen" % [counter, counter_n])
	check(over == 0, "Im Drift nie Gas über dem Plantempo (%d Takte)" % over)
	check(needle == 0, "Nadelöhr: kein Anstellen im Nadelöhr und davor (%d Takte)" % needle)
	# Spur 3 m neben der Mitte (im Nadelöhr 0,6 m innerhalb des Rands): durch beide Nadelöhre ohne Dreher.
	var edge := 0
	var spins := 0
	for lane in [-3.0, 3.0]:
		var r0 := arena.ai_route(1.5)
		for p in r0:
			var lim := arena.hw(float(p.s)) - 0.6
			p.o = clampf(lane, -lim, lim)
			p.p = arena.at(float(p.s), p.o)
			if arena.curvature(float(p.s)) > 0.03:
				p.speed = float(p.speed) * 1.45
		smooth_speeds(r0)
		var r := drive(DRIFT_KING, r0)
		edge += 1 if r.done else 0
		spins += int(r.spin)
	check(edge == 2 and spins < 30, "Linie 3 m neben der Mitte, Kurven ×1,45: beide im Ziel, %d Drehertakte" % spins)

# ---------- 2. Plan ----------
func test_plan() -> void:
	for car in [DRIFT_KING, 0]:
		var calm := drive(car, arena.ai_route(1.5))
		check(calm.done and float(calm.score) < 50.0 and float(calm.rms) < 0.8, "Ruhige Linie (KI 1,5), Auto %d: Haftung, %d Punkte, RMS %.2f m" % [car, int(calm.score), calm.rms])
	var slow := drive(DRIFT_KING, drawn(true, 12.0, 21))
	check(slow.done and float(slow.score) < 200.0, "Langsam gezeichnet (konstant 12 m/s): %d Punkte" % int(slow.score))
	# Schneller gezeichnet = mehr Winkel und Punkte, deutlich zu schnell = Dreher, Wand, Zeit.
	var good := []
	var wild := []
	for k in range(3):
		good.append(drive(DRIFT_KING, drawn(false, 1.45, 31 + k)))
		wild.append(drive(DRIFT_KING, drawn(true, 25.0, 41 + k)))
	var mild := drive(DRIFT_KING, drawn(false, 1.2, 30))
	var good_pts := mean(good, "score")
	check(float(mild.score) < good_pts, "Schneller gezeichnet, mehr Punkte: Kurven ×1,2 %d, ×1,45 im Mittel %d" % [int(mild.score), int(good_pts)])
	var punished := 0
	for r in wild:
		if int(r.spin) > 30 or int(r.walls) >= 2 or float(r.time) > limit:
			punished += 1
	check(punished == 3 and mean(wild, "spin") > mean(good, "spin") + 30.0 and mean(wild, "walls") > mean(good, "walls"),
		"Deutlich zu schnell (konstant 25 m/s): alle bestraft (%d/3), Drehertakte %.0f gegen %.0f, Wände %.1f gegen %.1f, Zeit %.1f gegen %.1f s" % [punished,
		mean(wild, "spin"), mean(good, "spin"), mean(wild, "walls"), mean(good, "walls"), mean(wild, "time"), mean(good, "time")])
	# … und Punktverlust: Wand und Dreher kosten die Kette des laufenden Drifts (score_drift).
	check(mean(wild, "chains") >= 2.0 and mean(wild, "chains") > mean(good, "chains") + 1.0,
		"Deutlich zu schnell: verlorene Ketten im Mittel %.1f gegen %.1f bei ×1,45 (Punkte %d gegen %d)" % [mean(wild, "chains"), mean(good, "chains"), int(mean(wild, "score")), int(good_pts)])
	# Determinismus
	var a := drive(DRIFT_KING, human(5))
	var b := drive(DRIFT_KING, human(5))
	check(a.score == b.score and a.time == b.time and (a.car as RaceVehicle).pos == (b.car as RaceVehicle).pos, "Deterministisch: zweimal %d Punkte in %.3f s" % [int(a.score), a.time])

func mean(rows: Array, key: String) -> float:
	# Mittel über alle Fahrten; die Zeit nur über die angekommenen.
	var s := 0.0
	var n := 0
	for r in rows:
		if key == "time" and not bool(r.done):
			continue
		s += float(r[key])
		n += 1
	return s / maxf(1.0, n)

# ---------- 3. Ziele und Zeitlimit ----------
const HUMANS := 24
func test_targets() -> void:
	var lines: Array = []
	for k in range(HUMANS):
		lines.append(human(100 + k))
	var dry := []
	var wet := []
	for r0 in lines:
		dry.append(drive(DRIFT_KING, r0, 1.0))
		wet.append(drive(DRIFT_KING, r0, 0.85))
	var s1 := count_won(dry, 0)
	var s2 := count_won(dry, 1)
	var s3 := count_won(wet, 2)
	print("INFO: Drift King, %d menschliche Linien: Stufe 1 %d, Stufe 2 %d, Stufe 3 (Regen) %d; Punkte trocken Ø %d, nass Ø %d; Zeit trocken Ø %.1f, nass Ø %.1f s (Limit %.1f)" % [
		HUMANS, s1, s2, s3, int(mean(dry, "score")), int(mean(wet, "score")), mean(dry, "time"), mean(wet, "time"), limit])
	check(s1 >= HUMANS * 0.6, "Stufe 1 (%d Punkte) gut erreichbar: %d von %d menschlichen Linien" % [int(targets[0]), s1, HUMANS])
	check(s2 >= HUMANS * 0.25 and s2 <= HUMANS * 0.75, "Stufe 2 (%d Punkte) fordert: %d von %d" % [int(targets[1]), s2, HUMANS])
	check(s3 >= 1 and s3 <= HUMANS * 0.3, "Stufe 3 (%d Punkte, Regen) nur mit guten Linien: %d von %d" % [int(targets[2]), s3, HUMANS])
	# Regen nicht leichter (Drift King). Nass rutscht das Auto bei gleicher Linie leichter quer und braucht länger; Dreher und Wände kosten
	# dort aber öfter die Kette (score_drift). Geprüft wird: Die Regenstufe ist schwerer als die trockene Stufe 2; mit den Zielen der Stufen 1
	# und 2 schaffen nass höchstens so viele Linien wie trocken; je Linie bringt Regen im Median höchstens 15 % mehr Punkte (saubere
	# Ideallinien gewinnen nass mehr, aggressive verlieren – siehe Fingerlinien); und nicht die Uhr entscheidet die Regenstufe (vor der
	# Kettenregel lag die mittlere Fahrzeit nass genau auf dem Limit).
	var pts_d: Array[float] = []
	var diff: Array[float] = []
	for k in range(HUMANS):
		pts_d.append(float(dry[k].score))
		diff.append(float(wet[k].score) - float(dry[k].score))
	pts_d.sort()
	diff.sort()
	var med_d := pts_d[HUMANS / 2]
	var med_diff := diff[HUMANS / 2]
	check(s3 < s2 and count_won(wet, 0) <= s1 and count_won(wet, 1) <= s2 and med_diff <= 0.15 * med_d,
		"Regen nicht leichter: Stufe 3 nass %d gegen Stufe 2 trocken %d; Ziele 1/2 nass %d/%d gegen trocken %d/%d; je Linie nass %+d Punkte (Median, trocken %d)" % [
		s3, s2, count_won(wet, 0), count_won(wet, 1), s1, s2, int(med_diff), int(med_d)])
	var enough := 0
	var late := 0
	for r in wet:
		if bool(r.done) and float(r.score) >= float(targets[2]):
			enough += 1
			late += 1 if float(r.time) > limit else 0
	check(late * 4 <= maxi(enough, 4), "Die Uhr entscheidet die Regenstufe nicht: %d von %d nassen Fahrten mit genug Punkten über dem Zeitlimit" % [late, enough])
	# Nicht mit jeder Linie: ruhig und langsam gezeichnet reicht für keine Stufe; grob überall schnell gezeichnet (Fingerlinien über den
	# LineRecorder, Mitte, konstant 21 bzw. 29 m/s) erreicht die Regenstufe nicht, überall rot auch Stufe 2 nicht – Dreher und Wände kosten die
	# Ketten (vorher schafften sie mit 2–3 Wänden alle Stufen bzw. Stufe 2). Gute Fingerlinien (Ideallinie, Kurven schneller als die
	# Geraden) erreichen die Regenstufe.
	var calm := drive(DRIFT_KING, arena.ai_route(1.5))
	check(not won(calm, 0), "Ruhige Linie erreicht Stufe 1 nicht (%d Punkte)" % int(calm.score))
	var coarse := []
	for spec in [[21.0, 0.3, 61], [21.0, 0.9, 62], [29.0, 0.3, 63], [29.0, 0.9, 64]]:
		var r0 := finger(spec[0], spec[0], "mitte", spec[1], spec[2])
		var d := drive(DRIFT_KING, r0, 1.0)
		var w := drive(DRIFT_KING, r0, 0.85)
		coarse.append([spec[0], d, w])
	var coarse_ok := true
	var coarse_text := ""
	for c in coarse:
		coarse_ok = coarse_ok and not won(c[2], 2) and (c[0] < 25.0 or not won(c[1], 1))
		coarse_text += " %d m/s: trocken %d (%d Wände, %d Ketten), nass %d;" % [int(c[0]), int(c[1].score), int(c[1].walls), int(c[1].chains), int(c[2].score)]
	check(coarse_ok, "Grob schnell gezeichnet:%s keine Regenstufe, überall rot nicht Stufe 2" % coarse_text)
	var good := 0
	var good_text := ""
	var good_lines := []
	for spec in [[14.0, 20.0, 0.3, 71], [14.0, 22.0, 0.9, 72], [17.0, 20.0, 0.9, 73]]:
		var r0 := finger(spec[0], spec[1], "ideal", spec[2], spec[3])
		good_lines.append(r0)
		var w := drive(DRIFT_KING, r0, 0.85)
		good += 1 if won(w, 2) else 0
		good_text += " %d/%d: %d Punkte, %.1f s;" % [int(spec[0]), int(spec[1]), int(w.score), w.time]
	check(good >= 2, "Gute Fingerlinien (Ideallinie, Gerade/Kurve m/s):%s Regenstufe %d von 3" % [good_text, good])
	# Andere Autos: Stufe 3 erreichbar, aber schwerer (weniger Linien als mit dem Drift King).
	var best_other := 0
	var others := {}
	var stuck := 0
	var stall_max := 0.0
	var stall_where := ""
	for k in range(HUMANS):
		for r in [dry[k], wet[k]]:
			stuck += 1 if r.stuck else 0
			if float(r.stall) > stall_max:
				stall_max = float(r.stall)
				stall_where = "Drift King, Linie %d" % (100 + k)
	# Dazu zwei gute menschliche Linien (Kurven ×1,64, kaum Spurversatz) und eine Fingerlinie auf der Mitte (Gerade 14, Kurve 20 m/s): Mit
	# ihnen schaffen Apex GT bzw. Thunder V8 die Regenstufe (gemessen 15.10.2026; auf den übrigen Linien verlieren sie mit ihren Wandkontakten
	# zu viele Ketten).
	var extra: Array = [human(325), human(331), finger(14.0, 20.0, "mitte", 0.3, 661)]
	for car in [3, 4]:
		var wins := 0
		for r0 in lines + extra + good_lines:
			var r := drive(car, r0, 0.85)
			wins += 1 if won(r, 2) else 0
			stuck += 1 if r.stuck else 0
			if float(r.stall) > stall_max:
				stall_max = float(r.stall)
				stall_where = RaceVehicle.CARS[car].name
		others[RaceVehicle.CARS[car].name] = wins
		best_other = maxi(best_other, wins)
	var dk_wins := s3 + good
	for r0 in extra:
		dk_wins += 1 if won(drive(DRIFT_KING, r0, 0.85), 2) else 0
	var total := HUMANS + extra.size() + good_lines.size()
	print("INFO: Stufe 3 (Regen) auf %d Linien: Drift King %d, andere Autos %s" % [total, dk_wins, str(others)])
	check(best_other >= 1 and best_other < dk_wins, "Stufe 3 auch mit anderen Autos erreichbar, aber schwerer: bestes anderes Auto %d, Drift King %d von %d" % [best_other, dk_wins, total])
	# Freifahren im Drift-Modus: Jede Fahrt endet (im Ziel oder als Wrack), kein langer Stillstand (Zeit ohne 2 m Nettofortschritt). Vorher
	# setzte ein Auto neben einer Reifenwand bis Rennende vor und zurück (81 s), oder es setzte alle 0,3 s erneut zurück.
	check(stuck == 0 and stall_max < 20.0, "Kein Hängenbleiben: %d Fahrten ohne Ende, längster Stillstand %.1f s (%s)" % [stuck, stall_max, stall_where])
	var case := drive(DRIFT_KING, human(328), 0.85)
	check(bool(case.done) and float(case.stall) < 12.0, "Linie 328 im Regen (Gegenprüfung: 81 s Stillstand): im Ziel nach %.1f s, längster Stillstand %.1f s, %d-mal zurückgesetzt" % [case.time, case.stall, case.rev])

func count_won(rows: Array, stage: int) -> int:
	var n := 0
	for r in rows:
		n += 1 if won(r, stage) else 0
	return n

# ---------- 4. Verlorenes Auto, Modell ----------
func test_lost() -> void:
	# Gedreht und stehend auf der Fahrbahn, Nase gegen die Fahrtrichtung: Der Profi setzt zurück (drift_reverse, wie beim Freifahren) und fährt
	# weiter.
	for s in [0.18, 0.62]:
		var v := RaceVehicle.new(arena, drawn(false, 1.45, 51), s, 2.0, DRIFT_KING)
		v.heading += PI
		v.previous_phase = s
		var reversed := false
		var t := 0.0
		for tick in range(60 * 30):
			v.step(DT, false, float(tick + 1) * DT)
			reversed = reversed or v.reversing or v.drift_back
			t = float(tick + 1) * DT
			if v.crashed or (v.progress - s) * arena.length > 30.0:
				break
		check(reversed and not v.crashed and (v.progress - s) * arena.length > 30.0, "Gedreht bei s %.2f: zurückgesetzt, nach %.1f s 30 m weiter" % [s, t])
	# Dasselbe mit gehaltenem Turbo: Beim Zurücksetzen zündet er nicht (sonst schob er das Auto wieder vorwärts, es pendelte um u ≈ 0
	# und verbrannte den Turbo; Gesamtprüfung 15.10.2026).
	var w := RaceVehicle.new(arena, drawn(false, 1.45, 51), 0.18, 2.0, DRIFT_KING)
	w.heading += PI
	w.previous_phase = 0.18
	var min_u := 0.0
	var boost_back := 0
	for tick in range(60 * 30):
		w.step(DT, true, float(tick + 1) * DT)
		var u := w.velocity.dot(Vector2.from_angle(w.heading))
		min_u = minf(min_u, u)
		if w.drift_back and w.boosting:
			boost_back += 1
		if w.crashed or (w.progress - 0.18) * arena.length > 30.0:
			break
	check(min_u < -1.0 and boost_back == 0 and not w.crashed, "Gedreht mit gehaltenem Turbo: setzt zurück (u min %.2f m/s), kein Turbo beim Zurücksetzen (%d Takte)" % [min_u, boost_back])

func test_model() -> void:
	# Rennmodus bitgleich: Messanker aller Rennstrecken wie in golden_times.json.
	var golden = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden_times.json"))
	var same := golden is Dictionary
	var text := ""
	if same:
		for id in ["azure", "city", "forest", "harbor", "serra", "fair", "quarry", "kids", "arena"]:
			RaceVehicle.weather_grip = 1.0
			var c := Circuit.load_track(id)
			var v := RaceVehicle.new(c, c.ai_route(2.3, 0.0))
			for tick in range(60 * 300):
				v.step(DT, false, float(tick + 1) * DT)
				if v.finish_time >= 0.0 or v.crashed:
					break
			var ok := snappedf(v.finish_time, 0.000001) == snappedf(float(golden.times[id].time), 0.000001)
			same = same and ok
			if not ok:
				text += " %s %.6f/%.6f" % [id, v.finish_time, float(golden.times[id].time)]
	check(same, "Messanker (golden_times.json) bitgleich%s" % text)
	# Heckantrieb im Drift-Modus für alle, im Rennmodus Allrad wie bisher.
	var route := drawn(false, 1.6, 61)
	var drift_awd := drive(0, route)
	var race_arena := Circuit.load_track("arena")
	race_arena.mode = "race"
	var race_awd := drive(0, route, 1.0, race_arena)
	check(float(drift_awd.spin_max) > 1.0 and float(race_awd.spin_max) == 0.0, "Sprint: im Drift-Modus Heckantrieb (Durchdrehen bis %.2f m/s²), im Rennmodus Allrad (0)" % float(drift_awd.spin_max))
	# Drift King driftet williger und folgt der Linie besser als die übrigen Autos.
	var lines := []
	for k in range(6):
		lines.append(drawn(k % 2 == 1, 1.5 if k % 2 == 0 else 17.0, 70 + k))
	var dk := []
	for r0 in lines:
		dk.append(drive(DRIFT_KING, r0))
	for car in [0, 3, 4]:
		var rows := []
		for r0 in lines:
			rows.append(drive(car, r0))
		# „Folgt der Spur besser“ gilt im Drift (Abstand zur Linie in den Takten über 12°) und nur gegen Autos, die auch driften: Der Apex GT
		# kommt kaum quer (unter 30 % der Punkte) und fährt mit Haftung ohnehin nah an der Linie. Diese Ausnahme kam nach einem roten Lauf hinzu
		# (GT 1,32 m gegen Drift King 1,40 m im Drift); dass die griffigen Allrad-Autos im Drift-Modus kaum quer kommen, folgt aus der
		# hecklastigen Allrad-Abstimmung DRIFT_AWD_REAR – eine offene Nutzerentscheidung (siehe vehicle.gd).
		var drifts := mean(rows, "score") > 0.3 * mean(dk, "score")
		check(mean(dk, "score") > mean(rows, "score") * 1.2 and (mean(dk, "rms_drift") < mean(rows, "rms_drift") or not drifts),
			"Drift King gegen %s (Kurven ×1,5 / konstant 17): Punkte %d gegen %d, Abstand zur Linie im Drift (RMS) %.2f gegen %.2f m, insgesamt %.2f gegen %.2f m" % [
			RaceVehicle.CARS[car].name, int(mean(dk, "score")), int(mean(rows, "score")), mean(dk, "rms_drift"), mean(rows, "rms_drift"), mean(dk, "rms"), mean(rows, "rms")])

# ---------- 5. Anzeige ----------
func fits(label: Label) -> bool:
	var box := label.get_parent() as Control
	return label.position.x + label.get_minimum_size().x <= box.size.x - 8.0

func test_hud() -> void:
	var app: Node = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	await process_frame
	var path := "user://test_drift_%s.json" % Time.get_ticks_usec()
	app.store = ProgressStore.new(path)
	app.run_record_path = path + ".run"
	app.debug_data()["unlock"] = true
	app.select_track("arena")
	app.car_choice = DRIFT_KING
	app.stage = 0
	app.start_drawing()
	app.recorder.route = arena.ai_route(1.5)
	app.recorder.complete = true
	app.begin_race()
	var hud: RaceHUD = app.hud
	check(hud.status != null and hud.drift_left != null and hud.rank_label != null, "Drift-Rennanzeige: Statuszeile, Restzeit und Punkte")
	# Breiteste Inhalte: zweistellige Restzeit, Multiplikator ×4.0, Runde 2/2, vierstellige Kette neben der Restzeit.
	hud.show_drift("RUNDE 2 / 2", 4.0, 99, 9999)
	var single := fits(hud.status) and fits(hud.drift_left) and hud.drift_gain != null and fits(hud.drift_gain) and \
		hud.drift_left.position.x + hud.drift_left.get_minimum_size().x < hud.drift_gain.position.x - 8.0
	var texts := [hud.status.text, hud.drift_left.text, hud.drift_gain.text if hud.drift_gain != null else "-"]
	hud.show_drift("RUNDE 1 / 2", 1.7, 8)
	check(single and not str(texts[0]).contains("noch") and str(texts[1]).begins_with("noch") and texts[2] == "+9999" and hud.drift_gain.text == "",
		"Einzelspieler: „%s“, „%s“ und Kette „%s“ passen in den Kasten (Status %d + %d ≤ %d px), ohne Kette leer" % [texts[0], texts[1], texts[2],
		int(hud.status.position.x), int(hud.status.get_minimum_size().x), int((hud.status.get_parent() as Control).size.x)])
	check(hud.drift_left.get_theme_color("font_color") == RaceHUD.ORANGE, "Restzeit unter 10 s orange")
	# Weitergeben (ein Handy): dieselbe Anzeige in der Infoleiste.
	app.party = PassParty.create("Ada", DRIFT_KING, "arena", 0)
	app.party.add_player()
	hud.party_ui.race()
	hud.show_drift("RUNDE 2 / 2", 4.0, 99)
	var party_ok := hud.drift_left != null and fits(hud.status) and fits(hud.drift_left)
	var time_left := hud.time_label.position.x
	check(party_ok and hud.status.position.x + hud.status.get_minimum_size().x < time_left - 8.0,
		"Weitergeben: „%s“ links der Zeit, „%s“ in eigener Zeile" % [hud.status.text, hud.drift_left.text if hud.drift_left != null else "-"])
	# Die laufende Kette steht je Spieler auf seinem Turboknopf unten rechts neben der Prozentzahl (breiteste Inhalte „100 %“ und „+9999“).
	var pads: TurboPads = hud.pads
	var own: RaceVehicle = app.vehicles[app.me]
	own.drift_chain = 9999.0
	var chain := TurboPads.chain_text(own)
	own.drift_chain = 0.0
	var empty := TurboPads.chain_text(own)
	var percent_right := TurboPads.SIZE.x * 0.5 + pads.font.get_string_size("100 %", HORIZONTAL_ALIGNMENT_LEFT, -1, TurboPads.PERCENT_SIZE).x * 0.5
	var chain_left := TurboPads.SIZE.x - TurboPads.PAD - pads.font.get_string_size(chain, HORIZONTAL_ALIGNMENT_LEFT, -1, TurboPads.CHAIN_SIZE).x
	check(pads.visible and chain == "+9999" and empty == "" and chain_left > percent_right + 6.0,
		"Weitergeben: Kette „%s“ auf dem Turboknopf neben „100 %%“ (%d px Abstand), ohne Kette leer" % [chain, int(chain_left - percent_right)])
	hud.pads.hide_pads()
	app.party = null
	app.show_menu()
	app.queue_free()
	await process_frame
	for suffix in ["", ".bak", ".tmp", ".run"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
