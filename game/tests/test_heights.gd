extends SceneTree

# Höhenniveaus (docs/dioramen/HOEHEN_PLAN.md, Abschnitt 9 A): Landung auf Gefälle, Landelippe, Hindernisse mit Unterkante, Astbezug,
# Ausweichen/Turbosperre, Wippe, Sprungfenster der KI, Sprint-Start, Formatprüfung und Messanker (golden_times.json).
# Prüfstrecken: game/tests/tracks/*.json (Erzeuger make_test_tracks.py daneben).
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

func plan(track: Circuit, speed: float, shortcut := -1) -> Array[Dictionary]:
	var route := track.ai_route(2.0, 0.0, shortcut)
	for p in route:
		p.speed = speed
	return route

func placed(track: Circuit, s: float, speed: float, shortcut := -1) -> RaceVehicle:
	# Auto auf der Mittellinie bei s, schon auf Tempo (Fortschritt und Phase passend gesetzt).
	var v := RaceVehicle.new(track, plan(track, speed, shortcut), s)
	v.velocity = Vector2.from_angle(v.heading) * speed
	return v

func run(v: RaceVehicle, seconds: float, watch := Callable()) -> void:
	for tick in range(int(seconds * 60.0)):
		v.step(DT, false, float(tick + 1) * DT)
		if watch.is_valid():
			watch.call(v)
		if v.crashed or v.finish_time >= 0.0:
			break

func _init() -> void:
	var oval := Circuit.new("res://tests/tracks/hoehen_oval.json")
	check(oval.validate().is_empty() and oval.length > 500.0, "Prüfoval Höhen: gültig (%.1f m)" % oval.length)
	var m := func(meters: float) -> float: return oval.phase(Vector2(-100.0 + meters, -25.0))
	test_landing(oval, m)
	test_lip(oval, m)
	test_obstacle_base(oval, m)
	test_branches()
	test_avoidance(oval, m)
	test_seesaw()
	test_jump_windows()
	test_sprint_start()
	test_format()
	test_golden()
	print("RESULT: ", checks - failures, "/", checks, " passed")
	quit(1 if failures else 0)

# 1. Landung auf 30 % Gefälle ohne zweiten Flug; Abschlag nach relativem vz; flache Landung wie bisher (vz 0).
func test_landing(oval: Circuit, m: Callable) -> void:
	var results := {}
	for where in ["slope", "flat"]:
		var s: float = m.call(76.0 if where == "slope" else 100.0)
		var v := placed(oval, s, 15.0)
		v.airborne = true
		v.z = oval.ground_height(s) + 0.6
		v.vz = -3.0
		var state := {"landed": -1, "again": 0, "was": true, "before": 0.0, "after": 0.0, "vz": 99.0}
		for tick in range(90):
			var speed_before := v.velocity.length()
			v.step(DT, false, float(tick + 1) * DT)
			if bool(state.was) and not v.airborne and int(state.landed) < 0:
				state.landed = tick
				state.before = speed_before
				state.after = v.velocity.length()
				state.vz = v.vz
			elif int(state.landed) >= 0 and v.airborne and not bool(state.was):
				state.again = int(state.again) + 1
			state.was = v.airborne
			if v.crashed:
				break
		results[where] = state
		if where == "slope":
			check(int(state.landed) >= 0 and int(state.again) == 0 and not v.crashed, "Landung auf 30 %% Gefälle ohne zweiten Flug (vz danach %.2f m/s)" % float(state.vz))
	var slope_loss := 1.0 - float(results.slope.after) / maxf(float(results.slope.before), 0.01)
	var flat_loss := 1.0 - float(results.flat.after) / maxf(float(results.flat.before), 0.01)
	check(slope_loss < flat_loss, "Abschlag nach relativem vz: Gefälle %.3f < eben %.3f" % [slope_loss, flat_loss])
	check(float(results.flat.vz) == 0.0, "Ebene Landung: danach vz = 0 wie bisher")

# 2. Landelippe: zu langsam -> Aufprall an der Stirnseite; schnell genug -> Landung; ohne "lip" wie bisher hochgezogen.
func test_lip(oval: Circuit, m: Callable) -> void:
	var cases := [[0.4, 13.0, true], [-1.0, 13.0, false], [0.4, 18.0, false]]
	for c in cases:
		var t := Circuit.new("res://tests/tracks/hoehen_oval.json")
		if float(c[0]) >= 0.0:
			t.gaps[0]["lip"] = float(c[0])
		var v := placed(t, m.call(117.0), float(c[1]))
		var flew := [false]
		run(v, 2.5, func(car: RaceVehicle): flew[0] = flew[0] or car.airborne)
		var label := "Lippe %.1f m" % float(c[0]) if float(c[0]) >= 0.0 else "ohne Lippe"
		if bool(c[2]):
			check(v.crashed and v.lip_hit > 0.0 and v.velocity.length() == 0.0, "%s, %.0f m/s: Aufprall an der Stirnseite (Absturz)" % [label, float(c[1])])
		else:
			check(flew[0] and not v.crashed and v.progress > m.call(141.0), "%s, %.0f m/s: Landung hinter der Lücke" % [label, float(c[1])])
	# Steinbruch (Prüfung 03.10.2026): wer knapp hinter der Lippe landet (Absprung 11,5–12,3 m/s), fährt weiter – die unsichtbare Stirnwand
	# unter der Lippe reicht nur bis Lippe − lip (2,6 m) und hält Autos auf der Rampe nicht fest. Zu langsam (10,7 m/s) prallt an die Stirnseite.
	var q := Circuit.load_track("quarry")
	var g: Dictionary = q.gaps[0]
	for u in [13.0, 14.0, 14.5, 15.0, 16.0]:
		var route := q.ai_route(2.3, 0.0)
		for e in route:
			var x := q.unit(float(e.s))
			if x > float(g.from) - 45.0 / q.length and x <= float(g.from) + 0.002:
				e.speed = u
		var car := RaceVehicle.new(q, route)
		var take_off := [0.0]
		var was := [false]
		run(car, 45.0, func(c: RaceVehicle):
			if c.airborne and not was[0] and absf(q.unit(c.progress) - float(g.from)) < 0.01:
				take_off[0] = c.velocity.length()
			was[0] = c.airborne)
		var past := car.progress > float(g.to) + 25.0 / q.length
		if u < 13.5:
			check(car.crashed and car.lip_hit > 0.0, "Steinbruch, Absprung %.1f m/s: Aufprall an der Landelippe" % take_off[0])
		else:
			check(past and not car.crashed and not car.wrecked, "Steinbruch, Absprung %.1f m/s: Landung an der Lippe, weiter auf der Schüttrampe (s %.3f %s)" % [take_off[0], car.progress, car.wreck_cause])

# 3. Hindernis mit Unterkante: auf dem Plateau darüber hinweg, darunter Aufprall; Flug absolut; ohne b wie bisher.
func test_obstacle_base(oval: Circuit, m: Callable) -> void:
	var over := placed(oval, m.call(50.0), 12.0)
	over.z = oval.ground_height(m.call(50.0))
	run(over, 1.2)
	check(not over.crashed and over.obstacle_hit == 0.0 and over.progress > m.call(58.0), "Collider unter dem Plateau: Auto oben fährt darüber (Höhe %.1f m)" % over.z)
	var spot := Vector2(-100.0 + 55.0 - 1.6, -25.0)
	var cases := [[0.0, false, true, "darunter am Boden: Aufprall"], [6.0, false, false, "auf Plateauhöhe: kein Kontakt"],
		[2.0, true, true, "im Flug auf 2 m: Aufprall"], [4.5, true, false, "im Flug über der Oberkante: frei"]]
	for c in cases:
		var v := placed(oval, m.call(50.0), 10.0)
		v.pos = spot
		v.heading = 0.0
		v.velocity = Vector2(10.0, 0.0)
		v.z = float(c[0])
		v.airborne = bool(c[1])
		v.collide_obstacles(DT)
		check((v.obstacle_hit > 0.0) == bool(c[2]), "Collider (b 0, h 4): " + str(c[3]))
	# Baumstamm ohne Unterkante: am Boden Kontakt, im Flug darüber frei (wie bisher).
	for c in [[0.0, false, true], [1.0, true, false]]:
		var v := placed(oval, m.call(100.0), 10.0)
		v.pos = Vector2(-100.0 + 105.0 - 3.35, -22.5)     # vorderer Kreis 0,5 m vor der Stirnseite des Stamms
		v.heading = 0.0
		v.velocity = Vector2(10.0, 0.0)
		v.z = float(c[0])
		v.airborne = bool(c[1])
		v.collide_obstacles(DT)
		check((v.obstacle_hit > 0.0) == bool(c[2]), "Hindernis ohne b: %s" % ("am Boden Kontakt" if bool(c[2]) else "im Flug darüber frei"))

# 4. Astbezug an einer Brückenkreuzung (Wald mit Höhenprofil des Plans): neben dem oberen Ast Absturz, unten nicht; Belag je Ast.
func test_branches() -> void:
	# Seit Fassung 2 hat die Wald-Datei selbst Höhenprofil, Hohlweg-Gelände und Leitplanken an der Brücke: als ebene Vergleichsstrecke
	# dient sie ohne Höhen; für den Absturz neben dem oberen Ast ohne Leitplanken (sonst prallt das Auto dort ab).
	var flat := Circuit.load_track("forest")
	flat.elevation = []
	flat.terrain = {}
	flat.guardrails = []
	var f := Circuit.load_track("forest")
	f.elevation = [[0.07, 1.4], [0.24, 3.6], [0.35, 4.5], [0.455, 4.5], [0.52, 3.9], [0.57, 3.4], [0.74, 0.8], [0.86, 0.0], [0.98, 0.0]]
	f.guardrails = []
	var best := [INF, 0.0, 0.0]
	var s1 := 0.34
	while s1 < 0.47:
		var s2 := 0.84
		while s2 < 0.97:
			var d := f.at(s1).distance_to(f.at(s2))
			if d < float(best[0]):
				best = [d, s1, s2]
			s2 += 0.001
		s1 += 0.001
	var upper := float(best[1])
	var lower := float(best[2])
	check(float(best[0]) < 1.0 and f.surface_z(upper) - f.surface_z(lower) > 3.0, "Wald-Acht: Kreuzung gefunden (oben %.3f auf %.1f m, unten %.3f auf %.1f m)" % [upper, f.surface_z(upper), lower, f.surface_z(lower)])
	var route := f.ai_route(2.0)
	var below := RaceVehicle.new(f, route, lower)
	below.pos = f.at(lower)
	below.z = f.ground_height(lower)
	check(not below.edge_check(lower, f.ground_height(lower)), "Auto auf dem unteren Ast unter der Brücke: kein Absturz")
	var beside := RaceVehicle.new(f, route, upper)
	beside.pos = f.at(upper, 5.5)
	beside.previous_phase = upper
	beside.z = f.ground_height(upper)
	check(beside.edge_check(upper, f.ground_height(upper)), "Auto 5,5 m neben dem oberen Ast über tiefem Grund: Absturz")
	var probe := f.at(upper, 5.5)
	check(str(f.surface_at(probe, lower).kind) == f.road and str(f.surface_at(probe, upper).kind) != f.road,
		"surface_at mit Astbezug: unten Fahrbahn (%s), oben neben der Bahn (%s)" % [f.surface_at(probe, lower).kind, f.surface_at(probe, upper).kind])
	var same := true
	for k in range(40):
		var p := flat.at(upper, -6.0 + k * 0.3)
		for hint in [upper, lower]:
			var a := flat.query(p)
			var b := flat.query_branch(p, hint)
			same = same and float(a.s) == float(b.s) and float(a.distance) == float(b.distance)
	check(same, "Ebene Kreuzung: Astbezug liefert exakt dieselbe Projektion wie bisher")

# 5. Ausweichen ignoriert Autos mit |Δz| > 1 m; kein Versatz in Schwungzonen und auf erhöhter Fahrbahn; Turbosperre der Gegner.
func test_avoidance(oval: Circuit, m: Callable) -> void:
	var az := Circuit.load_track("azure")
	# Auf einer Geraden (seit 03.10.2026 weichen Gegner in Kurven nicht mehr seitlich aus): erste Stelle ab s 0,1, an der die 20 m um die
	# Vorausschau (4 m zurück bis 16 m voraus) gerade sind.
	var s0 := 0.1
	while s0 < 1.0:
		var flat_ok := true
		for k in range(11):
			flat_ok = flat_ok and az.curvature(s0 + (k * 2.0 - 4.0) / az.length) < RaceVehicle.AVOID_K0
		if flat_ok:
			break
		s0 += 0.005
	var offsets := []
	for dz in [0.0, 2.0]:
		var lead := placed(az, s0, 10.0)
		var me := placed(az, s0 - 2.5 / az.length, 10.0)
		lead.z = dz
		for _i in range(12):
			RaceVehicle.update_avoidance([lead, me], DT)
		offsets.append(absf(me.avoid_offset))
	check(s0 < 1.0 and offsets[0] > 0.3 and offsets[1] == 0.0, "Ausweichen auf der Geraden (s %.3f): gleiche Ebene %.2f m, |Δz| 2 m kein Versatz" % [s0, offsets[0]])
	# Kurve (Radius < 18 m): kein Seitenversatz; vor einer Schwungzone (Vorausschau 1,5 s) schon zurück auf 0.
	var sc := 0.0
	while sc < 1.0 and az.curvature(sc) < RaceVehicle.AVOID_K1 * 1.2:
		sc += 0.002
	var lead_c := placed(az, sc + 2.0 / az.length, 10.0)
	var me_c := placed(az, sc - 0.5 / az.length, 10.0)
	for _i in range(12):
		RaceVehicle.update_avoidance([lead_c, me_c], DT)
	check(me_c.avoid_offset == 0.0, "Kurve (Radius %.0f m): kein seitlicher Ausweichversatz" % (1.0 / maxf(az.curvature(sc), 1e-6)))
	var pre := Circuit.load_track("azure")
	# dieselbe Gerade wie oben, Schwungzone beginnt 10 m vor mir (JUMP_CALM vor dem Absprung): ohne Vorausschau gäbe es Versatz
	var me_s := s0 - 2.5 / pre.length
	pre.gaps = [{"from": me_s + (Circuit.JUMP_CALM + 10.0) / pre.length, "to": me_s + (Circuit.JUMP_CALM + 16.0) / pre.length}]
	var lead_p := placed(pre, s0, 10.0)
	var me_p := placed(pre, me_s, 10.0)
	for _i in range(12):
		RaceVehicle.update_avoidance([lead_p, me_p], DT)
	check(not pre.calm_at(me_p.progress) and me_p.avoid_offset == 0.0, "Kurz vor der Schwungzone (Vorausschau): kein neuer Versatz")
	var looped := Circuit.load_track("azure")
	looped.loops = [{"s": 0.51, "radius": 3.5}]
	var lead2 := placed(looped, 0.51 - 8.0 / looped.length, 10.0)
	var me2 := placed(looped, 0.51 - 10.5 / looped.length, 10.0)
	for _i in range(12):
		RaceVehicle.update_avoidance([lead2, me2], DT)
	check(me2.avoid_offset == 0.0 and looped.calm_at(0.51 - 10.0 / looped.length), "Schwungzone vor dem Looping: kein Ausweichversatz")
	var lead3 := placed(oval, m.call(58.0), 10.0)
	var me3 := placed(oval, m.call(55.5), 10.0)
	lead3.z = oval.ground_height(m.call(58.0))
	me3.z = oval.ground_height(m.call(55.5))
	for _i in range(12):
		RaceVehicle.update_avoidance([lead3, me3], DT)
	check(me3.avoid_offset == 0.0 and oval.calm_at(m.call(55.0)), "Erhöhte Fahrbahn (Plateau 6 m): kein Ausweichversatz")
	var jump := Circuit.load_track("azure")
	jump.gaps = [{"from": 0.49, "to": 0.51}]
	var rival := placed(jump, 0.5, 10.0)
	rival.turbo = 1.0
	var free := placed(jump, 0.0, 10.0)
	free.turbo = 1.0
	check(not RaceField.rival_boost(rival) and RaceField.rival_boost(free) and jump.boost_locked(0.49 - 30.0 / jump.length), "Gegner-Turbo in der Sperrzone um einen Sprung aus, sonst wie bisher")

# 6. Wippe: Ruhelage, Kippen unter Last, Rückkehr, Einfahrtskante (Wrack / Stoß / Auffahren), seitlich herunter, Determinismus, Geist.
func test_seesaw() -> void:
	var t := Circuit.new("res://tests/tracks/wippe_oval.json")
	check(t.validate().is_empty() and t.seesaws.size() == 1 and t.shortcuts.size() == 1, "Prüfoval Wippe: gültig")
	var w: Seesaw = Seesaw.from_track(t)[0]
	check(absf(w.phi - w.theta) < 1e-6 and absf(w.entry_edge()) < 0.01 and absf(w.end_height(1.0) - 2.0 * w.pivot_h) < 0.02, "Wippe: Ruhelage (Einfahrt unten, Ausfahrtsende %.2f m)" % w.end_height(1.0))
	var load_car := placed(t, 0.1, 0.0)
	load_car.pos = w.world(4.0)
	load_car.z = w.deck_y(4.0)
	for _i in range(60):
		w.step(DT, [load_car])
		load_car.z = w.deck_y(4.0)
	check(w.phi < 0.0 and w.load_count == 1, "Wippe kippt unter Last hinter dem Drehpunkt (φ %.3f)" % w.phi)
	w.phi = -w.theta
	w.omega = 0.0
	var back := 0.0
	while w.phi < w.theta - 1e-4 and back < 5.0:
		w.step(DT, [])
		back += DT
	check(back <= 1.5, "Rückkehr ohne Last in %.2f s" % back)
	var sc_route := plan(t, 10.0, 0)
	var on_path := sc_route.filter(func(e): return int(e.get("sc", -1)) == 0)
	check(on_path.size() > 50, "KI-Route über die Abkürzung mit denselben s-Stützstellen (%d Punkte auf dem Pfad)" % on_path.size())
	for c in [[0.8, "wreck"], [0.5, "stop"], [0.2, "on"]]:
		var ws := Seesaw.from_track(t)
		var w2: Seesaw = ws[0]
		w2.phi = asin((w2.pivot_h - float(c[0])) / w2.half_len)
		var car := RaceVehicle.new(t, sc_route, 0.0)
		car.seesaws = ws
		car.pos = w2.world(-w2.half_len - 4.0)
		car.heading = w2.u.angle()
		car.velocity = w2.u * 10.0
		var hit := t.shortcut_at(car.pos)
		car.progress = float(hit.s)
		car.previous_phase = float(hit.s)
		car.z = 0.0
		var seen := {"deck": false, "stop": false}
		for tick in range(60):
			car.step(DT, false, float(tick + 1) * DT)
			if car.deck != null:
				seen.deck = true
			if car.edge_hit > 0.0 and car.velocity.dot(w2.u) <= 0.05:
				seen.stop = true
			if car.crashed:
				break
		match str(c[1]):
			"wreck":
				check(car.wrecked and car.edge_hit > 0.0, "Kante 0,8 m an der Einfahrt: Wrack")
			"stop":
				check(not car.crashed and bool(seen.stop) and not bool(seen.deck), "Kante 0,5 m: harter Stoß, Längstempo 0, kein Wrack")
			"on":
				check(not car.crashed and bool(seen.deck) and car.edge_hit == 0.0, "Kante 0,2 m: Auto fährt auf")
	# Seitlich herunter: Flug und Landung auf dem Boden, kein Absturz.
	var ws3 := Seesaw.from_track(t)
	var w3: Seesaw = ws3[0]
	var side_car := RaceVehicle.new(t, sc_route, 0.0)
	side_car.seesaws = ws3
	var lateral := Vector2(-w3.u.y, w3.u.x)
	side_car.pos = w3.world(6.0, 1.2)
	side_car.heading = lateral.angle()
	side_car.velocity = lateral * 8.0
	var hit3 := t.shortcut_at(side_car.pos)
	side_car.progress = float(hit3.s)
	side_car.previous_phase = float(hit3.s)
	side_car.z = w3.deck_y(6.0)
	var flown := [false]
	run(side_car, 1.5, func(car: RaceVehicle): flown[0] = flown[0] or car.airborne)
	check(flown[0] and not side_car.airborne and not side_car.crashed and absf(side_car.z) < 0.05, "Seitlich vom Lineal: Flug und Landung auf dem Boden")
	# Feld über das Lineal: Spieler-Ersatz auf dem Lineal, zwei Gegner mit Zustandsregel; zweimal gerechnet identisch.
	var runs: Array = []
	for _k in range(2):
		var field_track := Circuit.new("res://tests/tracks/wippe_oval.json")
		var res := RaceField.run_field(field_track, 1, field_track.ai_route(2.0, 0.0, 0))
		runs.append(res)
	var f0: RaceField = runs[0].field
	var takes := 0
	var edge_wrecks := 0
	for d in f0.decisions:
		takes += 1 if bool(d[2]) else 0
	for v in f0.cars:
		edge_wrecks += 1 if v.wrecked and v.edge_hit > 0.0 else 0
	print("Wippe-Feld: ", runs[0].text, " | Entscheidungen ", f0.decisions)
	check(runs[0].failed.is_empty() and edge_wrecks == 0, "Wippe-Feld: alle im Ziel, keine Kantenunfälle (%s)" % runs[0].text)
	check(takes > 0, "KI nimmt das Lineal, wenn die Kante frei ist (%d von %d Entscheidungen)" % [takes, f0.decisions.size()])
	check(str(runs[0].times) == str(runs[1].times) and str(f0.decisions) == str(runs[1].field.decisions), "Wippe-Feld zweimal gerechnet: identisch")
	# Geist: eigene Wippe, auf der nur er Last ist.
	var gt := Circuit.new("res://tests/tracks/wippe_oval.json")
	var gf := RaceField.new(gt)
	gf.setup(gt.ai_route(2.0, 0.0), 0, 0, 1)
	gf.set_ghost(RaceVehicle.new(gt, gt.ai_route(2.0, 0.0, 0)))
	var main_min := INF
	var ghost_min := INF
	for tick in range(60 * 30):
		gf.step(DT, float(tick + 1) * DT, false, "race", false)
		main_min = minf(main_min, gf.seesaws[0].phi)
		ghost_min = minf(ghost_min, gf.ghost_seesaws[0].phi)
	check(main_min >= gf.seesaws[0].theta - 1e-6 and ghost_min < 0.0, "Geist kippt nur seine eigene Wippe (Feld φ min %.3f, Geist φ min %.3f)" % [main_min, ghost_min])

# 7. Sprungfenster: je Strecke mit Lücke lo < hi, Plan erreichbar, Absprungtempo der KI je Stufe in [lo − 0,3; hi] (Ziel mindestens lo + JUMP_AIM).
func test_jump_windows() -> void:
	for id in ["harbor", "fair", "quarry", "kids"]:
		var t := Circuit.load_track(id)
		var windows := t.jump_windows()
		for w in windows:
			check(bool(w.ok) and float(w.lo) < float(w.hi), "%s: Sprungfenster bei s %.4f [%.2f, %.2f] (v_min %.2f, v_hi %.2f)" % [id, float(w.s_t), float(w.lo), float(w.hi), float(w.v_min), float(w.v_hi)])
		var speeds := []
		var inside := true
		for skill in [1.6, 1.9, 2.3, 2.7, 3.0]:
			var v := RaceVehicle.new(t, t.ai_route(skill, 0.0))
			var was_air := false
			for tick in range(60 * 150):
				v.step(DT, false, float(tick + 1) * DT)
				if v.airborne and not was_air:
					for w in windows:
						var d := wrapf(t.unit(v.progress) - float(w.s_t), -0.5, 0.5) * t.length
						if absf(d) < 2.5:
							var u := v.velocity.dot(t.tangent(float(w.s_t)))
							speeds.append(snappedf(u, 0.1))
							# Seit 03.10.2026 im eigenen Fenster [lo − 0,3; hi] (vorher [v_min + 1; v_hi − 1]: der Hafen sprang 0,3–0,5 m/s unter lo ab)
							inside = inside and u >= float(w.lo) - 0.3 and u <= float(w.hi)
				was_air = v.airborne
				if v.finish_time >= 0.0 or v.crashed:
					break
			inside = inside and not v.crashed
		check(t.jump_problems.is_empty(), "%s: Anlauf je Stufe erreichbar %s" % [id, str(t.jump_problems)])
		check(inside and speeds.size() >= windows.size() * 5, "%s: Absprungtempo der KI im Fenster %s" % [id, str(speeds)])

# 8. Sprint-Start: Startplätze hinter der Linie ohne Überlappung, alle Gegner der Serra im Ziel.
func test_sprint_start() -> void:
	var t := Circuit.load_track("serra")
	var f := RaceField.new(t)
	f.setup(t.ai_route(2.0, 0.0), 2)
	var gap := INF
	for a in range(f.cars.size()):
		for b in range(a + 1, f.cars.size()):
			gap = minf(gap, f.cars[a].pos.distance_to(f.cars[b].pos))
	var behind := true
	for i in range(1, f.cars.size()):
		behind = behind and f.cars[i].progress < 0.0
	check(gap >= 1.2 and behind, "Sprint-Start: Startplätze hinter der Linie, Abstand mindestens %.2f m" % gap)
	for stage in range(3):
		var res := RaceField.run_field(Circuit.load_track("serra"), stage)
		check(res.failed.is_empty(), "Serra Stufe %d: alle Gegner im Ziel (%s)" % [stage + 1, res.text])

# 9. Formatprüfung und Gültigkeit der Diorama-Begleitdatei.
func test_format() -> void:
	var t := Circuit.load_track("azure")
	check(t.validate().is_empty(), "validate: azure ohne Befund")
	t.elevation = [[0.5, 1.0], [0.2, 0.0]]
	check(not t.validate().is_empty(), "validate: unsortiertes Höhenprofil wird gemeldet")
	t.elevation = []
	check(t.layout_valid({}) and t.layout_valid({"track_hash": t.file_hash}) and not t.layout_valid({"track_hash": "0"}), "Begleitdatei: ohne Hash bei Fassung 1 gültig, falscher Hash ungültig")
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://tracks/azure.json"))
	data["rev"] = 2
	var file := FileAccess.open("user://azure_rev2.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var newer := Circuit.new("user://azure_rev2.json")
	check(newer.rev == 2 and not newer.layout_ok and newer.obstacle_source == "props", "Veraltetes Diorama (kein Hash, rev 2) wird ignoriert: Hindernisse aus den Bausteinen")
	check(ProgressStore.board_key("azure") == "azure", "Bestenliste: Fassung 1 behält den bisherigen Schlüssel")

# 10. Messanker: Solo-Zeiten ai_route(2.3, 0) für azure, city, arena bitgleich.
func test_golden() -> void:
	var golden = JSON.parse_string(FileAccess.get_file_as_string("res://tests/golden_times.json"))
	check(golden is Dictionary and golden.has("times"), "golden_times.json vorhanden")
	if not golden is Dictionary:
		return
	for id in ["azure", "city", "arena"]:
		var got := solo_time(id)
		var want := float(golden.times[id].time)
		check(snappedf(got, 0.000001) == snappedf(want, 0.000001), "Messanker %s: %.6f s (Referenz %.6f s)" % [id, got, want])

func solo_time(id: String) -> float:
	RaceVehicle.weather_grip = 1.0
	var track := Circuit.load_track(id)
	var v := RaceVehicle.new(track, track.ai_route(2.3, 0.0))
	for tick in range(60 * 300):
		v.step(DT, false, float(tick + 1) * DT)
		if v.finish_time >= 0.0 or v.crashed:
			break
	return v.finish_time
